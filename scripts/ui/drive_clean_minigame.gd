class_name DriveCleanMinigame
extends RetroWindow
## Mehrstufige Laufwerkswartung auf einem authentischen 3,5-Zoll-DD-Board.
## Material und Spielzustand werden erst beim vollständigen Abschluss atomar
## übernommen. Schließen oder Abbrechen lässt Inventar und Verschmutzung intakt.

const BOARD_ART := preload("res://assets/ui/minigames/drive_clean_board_v01.png")
const CleanBoard := preload("res://scripts/ui/drive_clean_board.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const CLEANING_ITEM := "reinigungsdiskette"
const ENERGY_COST := 4
const SAFE_WET_MIN := 0.42
const SAFE_WET_MAX := 0.72

enum Stage { PREP, INSERT, CLEAN, DRY, DONE }

var _stage := Stage.PREP
var _finished := false
var _initial_dirt := 0.0
var _board: CleanBoard
var _stage_label: Label
var _quality_label: Label
var _instruction: Label
var _footer: HBoxContainer
var _primary_button: Button
var _wet_button: Button
var _blot_button: Button
var _assisted := false
var _depth_rig: Node


func _init() -> void:
	title = Loc.t("ui.drive_clean_minigame.laufwerkskopf_reinigungsdiskette", "LAUFWERKSKOPF · REINIGUNGSDISKETTE")
	win_size = Vector2(980, 720)


static func can_start() -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.drive_clean_minigame.nur_wahrend_eines_laufenden_spiels_verfugbar", "Nur während eines laufenden Spiels verfügbar.")}
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": Loc.t("ui.drive_clean_minigame.laufwerk_steht_in_deinem_zimmer", "Das Laufwerk steht in deinem Zimmer.")}
	if InventoryManager.count(CLEANING_ITEM) <= 0:
		return {"ok": false, "reason": Loc.t("ui.drive_clean_minigame.keine_reinigungsdiskette_im_vorrat_lager", "Keine Reinigungsdiskette im Vorrat (LAGER).")}
	var dirt := float(PlayerStats.hardware.get("drive_dirt", 0.0))
	if dirt <= 0.001:
		return {"ok": false, "reason": Loc.t("ui.drive_clean_minigame.lesekopf_ist_bereits_sauber", "Der Lesekopf ist bereits sauber.")}
	return {"ok": true, "reason": "", "dirt": dirt}


func _ready() -> void:
	super._ready()
	_initial_dirt = float(PlayerStats.hardware.get("drive_dirt", 0.0))
	_build_shell()
	_begin_prep()


func _exit_tree() -> void:
	if _stage == Stage.CLEAN or _stage == Stage.DRY:
		AudioManager.stop_floppy()


func _build_shell() -> void:
	var intro := Bezel.dim_label(
		Loc.t("ui.drive_clean_minigame.originale_reinigungsdiskette_vorbereiten_einlegen_den_kopf", "Originale Reinigungsdiskette vorbereiten, einlegen und den Kopf ruhig über alle Spuren führen."), 11)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)

	var telemetry := HBoxContainer.new()
	_stage_label = Bezel.lcd_label("", Palette.LCD_AMBER, 11)
	_stage_label.custom_minimum_size = Vector2(255, 22)
	telemetry.add_child(_stage_label)
	_quality_label = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	telemetry.add_child(_quality_label)
	content.add_child(telemetry)

	_board = CleanBoard.new()
	_board.board_texture = BOARD_ART
	_board.custom_minimum_size = Vector2(944, 470)
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.prep_changed.connect(_on_prep_changed)
	_board.insert_started.connect(_on_insert_started)
	_board.disk_inserted.connect(_on_disk_inserted)
	_board.clean_changed.connect(_on_clean_changed)
	_board.clean_complete.connect(_on_clean_complete)
	_board.dry_complete.connect(_on_dry_complete)
	content.add_child(_board)
	_depth_rig = DepthRig.new()
	add_child(_depth_rig)
	_depth_rig.configure(_board, 0.78)

	_instruction = Bezel.dim_label("", 11)
	_instruction.custom_minimum_size = Vector2(0, 30)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_instruction)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 6)
	content.add_child(_footer)


func _clear_footer() -> void:
	for child: Node in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()


func _footer_button(label: String, callback: Callable, width := 150.0) -> Button:
	var button := make_button(label, callback)
	button.custom_minimum_size = Vector2(width, 38)
	return button


func _footer_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _begin_prep() -> void:
	_stage = Stage.PREP
	_stage_label.text = Loc.t("ui.drive_clean_minigame.1_4_medium_vorbereiten", "1/4  MEDIUM VORBEREITEN")
	_instruction.text = Loc.t("ui.drive_clean_minigame.werkzeug_wahlen_jedes_vier_filzfenster_halten", "Werkzeug wählen und jedes der vier Filzfenster halten. Grün bedeutet: feucht genug, aber nicht tropfnass.")
	_clear_footer()
	_wet_button = _footer_button("● FLÜSSIGKEIT", _select_prep_tool.bind(1), 170)
	_blot_button = _footer_button("▧ ABTUPFEN", _select_prep_tool.bind(-1), 160)
	_footer.add_child(_wet_button)
	_footer.add_child(_blot_button)
	_footer.add_child(_footer_spacer())
	_primary_button = _footer_button("WEITER: EINLEGEN ▶", _begin_insert, 210)
	_primary_button.disabled = true
	_footer.add_child(_primary_button)
	_footer.add_child(_footer_button("AUTOMATISCH", _auto_clean, 145))
	_select_prep_tool(1)
	_board.begin_prep()


func _select_prep_tool(tool: int) -> void:
	_board.prep_tool = tool
	_wet_button.disabled = tool == 1
	_blot_button.disabled = tool == -1
	_board.queue_redraw()


func _on_prep_changed(values: Array) -> void:
	var prep_ready := true
	var deviation := 0.0
	for value: Variant in values:
		var wet := float(value)
		prep_ready = prep_ready and wet >= CleanBoard.SAFE_WET_MIN and wet <= CleanBoard.SAFE_WET_MAX
		deviation += absf(wet - 0.57)
	_quality_label.text = Loc.t("ui.drive_clean_minigame.filz_d_4_im_sollbereich", "FILZ  %d/4 IM SOLLBEREICH") % _board.ready_pad_count()
	_quality_label.add_theme_color_override("font_color", Palette.LCD_GREEN if prep_ready else Palette.LCD_CYAN)
	_primary_button.disabled = not prep_ready
	_board.prep_deviation = deviation / maxi(1, values.size())


func _begin_insert() -> void:
	if not _board.prep_is_ready():
		UIManager.toast(Loc.t("ui.drive_clean_minigame.alle_vier_filzflachen_zuerst_gleichmassig_anfeuchten", "Alle vier Filzflächen zuerst gleichmäßig anfeuchten."))
		return
	_stage = Stage.INSERT
	_stage_label.text = Loc.t("ui.drive_clean_minigame.2_4_reinigungsdiskette_einlegen", "2/4  REINIGUNGSDISKETTE EINLEGEN")
	_quality_label.text = Loc.t("ui.drive_clean_minigame.front_unten_sanft_bis_zum_einrasten", "FRONT UNTEN  ·  SANFT BIS ZUM EINRASTEN")
	_quality_label.add_theme_color_override("font_color", Palette.LCD_CYAN)
	_instruction.text = Loc.t("ui.drive_clean_minigame.grun_blaue_diskette_links_unten_greifen", "Die grün-blaue Diskette links unten greifen und in den leuchtenden Laufwerksschlitz ziehen.")
	_clear_footer()
	_footer.add_child(Bezel.dim_label(Loc.t("ui.drive_clean_minigame.ziehen_oder_barrierearme_einlegehilfe_benutzen", "Ziehen oder die barrierearme Einlegehilfe benutzen."), 10))
	_footer.add_child(_footer_spacer())
	_footer.add_child(_footer_button("EINLEGEHILFE", _board.auto_insert, 190))
	_footer.add_child(_footer_button("AUTOMATISCH", _auto_clean, 145))
	_board.begin_insert()


func _on_insert_started() -> void:
	AudioManager.floppy_insert()
	_quality_label.text = Loc.t("ui.drive_clean_minigame.mechanik_zieht", "MECHANIK ZIEHT EIN …")


func _on_disk_inserted() -> void:
	_begin_clean()


func _begin_clean() -> void:
	_stage = Stage.CLEAN
	_stage_label.text = Loc.t("ui.drive_clean_minigame.3_4_leskopf_uber_80_spuren", "3/4  LESKOPF ÜBER 80 SPUREN FÜHREN")
	_instruction.text = Loc.t("ui.drive_clean_minigame.kopfwagen_senkrecht_ziehen_seitlich_leicht_versetzen", "Kopfwagen senkrecht ziehen. Seitlich leicht versetzen regelt den Druck; langsam und gleichmäßig über alle Ablagerungen fahren.")
	_clear_footer()
	var assist := _footer_button("GEFÜHRTER DURCHGANG: AUS", _toggle_assist, 250)
	assist.name = "AssistButton"
	_footer.add_child(assist)
	_footer.add_child(Bezel.dim_label(Loc.t("ui.drive_clean_minigame.kein_zeitlimit_sorgfalt_bestimmt_wertung", "Kein Zeitlimit · Sorgfalt bestimmt die Wertung."), 10))
	_footer.add_child(_footer_spacer())
	_footer.add_child(_footer_button("AUTOMATISCH", _auto_clean, 145))
	_board.begin_clean(float(PlayerStats.wissen) / 100.0)
	AudioManager.floppy_read()


func _toggle_assist() -> void:
	_assisted = not _assisted
	_board.assisted = _assisted
	var button := _footer.get_node_or_null("AssistButton") as Button
	if button != null:
		button.text = Loc.t("ui.drive_clean_minigame.gefuhrter_durchgang_s",
			"GEFÜHRTER DURCHGANG: %s") % (
				Loc.t("ui.common.on", "AN") if _assisted
				else Loc.t("ui.common.off", "AUS"))
		button.add_theme_color_override("font_color", Palette.LCD_GREEN if _assisted else Palette.WHITE_SOFT)


func _on_clean_changed(cleanliness: float, pressure: float, passes: int, abrasion: float) -> void:
	var pressure_text := "ZU LEICHT"
	var color := Palette.LCD_CYAN
	if pressure >= _board.safe_pressure_min() and pressure <= _board.safe_pressure_max():
		pressure_text = "RUHIG"
		color = Palette.LCD_GREEN
	elif pressure > _board.safe_pressure_max():
		pressure_text = "ZU FEST"
		color = Palette.LCD_AMBER
	_quality_label.text = Loc.t("ui.drive_clean_minigame.sauberkeit_3d_druck_9s_durchgang_d", "SAUBERKEIT %3d%%  ·  DRUCK %-9s  ·  DURCHGANG %d") % [
		int(round(cleanliness * 100.0)), pressure_text, passes]
	_quality_label.add_theme_color_override("font_color", color if abrasion < 0.75 else Palette.LCD_AMBER)


func _on_clean_complete() -> void:
	if _stage != Stage.CLEAN:
		return
	_stage = Stage.DRY
	AudioManager.stop_floppy()
	AudioManager.floppy_eject()
	_stage_label.text = Loc.t("ui.drive_clean_minigame.4_4_auswerfen_verdunsten_lassen", "4/4  AUSWERFEN UND VERDUNSTEN LASSEN")
	_quality_label.text = Loc.t("ui.drive_clean_minigame.kopf_sauber_noch_nicht_lesen", "KOPF SAUBER  ·  NOCH NICHT LESEN")
	_quality_label.add_theme_color_override("font_color", Palette.LCD_AMBER)
	_instruction.text = Loc.t("ui.drive_clean_minigame.reinigungsdiskette_ist_ausgeworfen_einen_moment_warten", "Die Reinigungsdiskette ist ausgeworfen. Einen Moment warten, bis die Reinigungsflüssigkeit vollständig verdunstet ist.")
	_clear_footer()
	_footer.add_child(Bezel.dim_label(Loc.t("ui.drive_clean_minigame.abschluss_erfolgt_automatisch_ohne_zeitdruck", "Der Abschluss erfolgt automatisch und ohne Zeitdruck."), 11))
	_footer.add_child(_footer_spacer())
	_board.begin_dry()


func _on_dry_complete() -> void:
	_complete()


func _score() -> int:
	var wet_penalty := int(round(_board.prep_deviation * 420.0))
	var abrasion_penalty := int(round(_board.abrasion * 360.0))
	var pass_penalty := maxi(0, _board.passes - 4) * 35
	var assist_penalty := 180 if _assisted else 0
	return clampi(1000 - wet_penalty - abrasion_penalty - pass_penalty - assist_penalty, 100, 1000)


func _commit_success(score: int, details: Dictionary = {}) -> bool:
	if _finished:
		return false
	if not InventoryManager.consume(CLEANING_ITEM, 1):
		return false
	_finished = true
	var dirt_before := float(PlayerStats.hardware.get("drive_dirt", _initial_dirt))
	PlayerStats.clean_drive()
	PlayerStats.change_stat("energie", -ENERGY_COST)
	var result_details := details.duplicate(true)
	result_details["dirt_before"] = dirt_before
	result_details["energy"] = ENERGY_COST
	MinigameManager.finish("drive_clean", true, maxi(0, score), result_details)
	MemoryManager.record("werkstatt", "den Laufwerkskopf mit einer Reinigungsdiskette gepflegt")
	return true


func _complete() -> void:
	var score := _score() if _board != null else 750
	var details := {
		"passes": _board.passes if _board != null else 0,
		"abrasion": _board.abrasion if _board != null else 0.0,
		"coverage": _board.coverage_ratio() if _board != null else 1.0,
		"assisted": _assisted,
	}
	if not _commit_success(score, details):
		UIManager.toast(Loc.t("ui.drive_clean_minigame.reinigung_konnte_nicht_verbucht_werden_material", "Reinigung konnte nicht verbucht werden — Material fehlt."))
		queue_free()
		return
	_stage = Stage.DONE
	_stage_label.text = Loc.t("ui.drive_clean_minigame.fertig_leskopf_sauber", "FERTIG  ·  LESKOPF SAUBER")
	_quality_label.text = Loc.t("ui.drive_clean_minigame.04d_punkte_lese_schreibrisiko_gesenkt", "%04d PUNKTE  ·  LESE-/SCHREIBRISIKO GESENKT") % score
	_quality_label.add_theme_color_override("font_color", Palette.LCD_GREEN)
	_instruction.text = Loc.t("ui.drive_clean_minigame.saubere_arbeit_sauberkeit_100_verschmutzung_0", "Saubere Arbeit. Sauberkeit 100 %, Verschmutzung 0 %. Die mechanische Spurtreue bleibt davon getrennt.")
	_board.celebrate = true
	_board.queue_redraw()
	AudioManager.key_enter()
	UIManager.toast(Loc.t("ui.drive_clean_minigame.lesekopf_sauber_d_punkte_lese_schreibfehler", "Lesekopf sauber — %d Punkte, Lese- und Schreibfehler-Risiko gesenkt.") % score)
	await get_tree().create_timer(1.35).timeout
	queue_free()


func _auto_clean() -> void:
	if _finished:
		return
	if not InventoryManager.consume(CLEANING_ITEM, 1):
		UIManager.toast(Loc.t("ui.drive_clean_minigame.keine_reinigungsdiskette_im_vorrat_lager", "Keine Reinigungsdiskette im Vorrat (LAGER)."))
		return
	_finished = true
	PlayerStats.clean_drive()
	PlayerStats.change_stat("energie", -ENERGY_COST)
	MinigameManager.finish("drive_clean", false, 0, {"auto": true, "energy": ENERGY_COST})
	MemoryManager.record("werkstatt", "den Laufwerkskopf automatisch reinigen lassen")
	AudioManager.stop_floppy()
	UIManager.toast(Loc.t("ui.drive_clean_minigame.laufwerk_automatisch_gereinigt_bewusst_ohne_rekord", "Laufwerk automatisch gereinigt — bewusst ohne Rekord."))
	queue_free()
