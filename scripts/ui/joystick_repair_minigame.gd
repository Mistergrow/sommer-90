class_name JoystickRepairMinigame
extends RetroWindow
## Dreistufige 4-Kanal-Werkstatt: Leitungen zuordnen, jede Lötstelle im
## sicheren Wärme-/Zinnfenster schließen und anschließend diagnostizieren.
## Kein Zeitlimit, Farbe immer plus Symbol und jede Fehlstelle ist reparierbar.

const BOARD_ART := preload("res://assets/ui/minigames/joystick_repair_board_v01.png")
const RepairModel := preload("res://scripts/minigames/joystick_repair_model.gd")
const RepairBoard := preload("res://scripts/ui/joystick_repair_board.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const ENERGY_COST := 6

enum Stage { WIRE, SOLDER, TEST, DONE }

var _stage := Stage.WIRE
var _finished := false
var _initial_condition := 1.0
var _difficulty := "lehrgang"
var _completion_result: Dictionary = {}
var _model: RefCounted
var _board: RepairBoard
var _stage_label: Label
var _quality_label: Label
var _instruction: Label
var _footer: HBoxContainer
var _primary_button: Button
var _depth_rig: Node


func _init() -> void:
	title = Loc.t("ui.joystick_repair_minigame.joystick_4_kanal_werkstatt", "JOYSTICK · 4-KANAL-WERKSTATT")
	win_size = Vector2(980, 720)


static func can_start() -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.joystick_repair_minigame.nur_wahrend_eines_laufenden_spiels_verfugbar", "Nur während eines laufenden Spiels verfügbar.")}
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": Loc.t("ui.joystick_repair_minigame.deine_kleine_lotstation_steht_im_zimmer", "Deine kleine Lötstation steht im Zimmer.")}
	if int(GameManager.flags.get("hardware_knowledge", 0)) < 1:
		return {"ok": false, "reason": Loc.t("ui.joystick_repair_minigame.lass_dir_loten_zuerst_an_svens", "Lass dir das Löten zuerst an Svens Werkbank zeigen.")}
	var condition := PlayerStats.joystick_condition()
	if condition >= 0.999:
		return {
			"ok": false,
			"reason": Loc.t("ui.joystick_repair_minigame.joystick_ist_bereits_vollstandig_repariert_alle", "Der Joystick ist bereits vollständig repariert — alle vier Richtungen sind stabil."),
			"condition": condition,
		}
	if PlayerStats.energie < ENERGY_COST:
		return {"ok": false, "reason": Loc.t("ui.joystick_repair_minigame.zu_mude_fur_ruhige_lotarbeit_d", "Zu müde für ruhige Lötarbeit (%d Energie nötig).") % ENERGY_COST}
	return {
		"ok": true,
		"reason": "",
		"condition": condition,
	}


func _ready() -> void:
	super._ready()
	_initial_condition = PlayerStats.joystick_condition()
	var wins := int(MinigameManager.record("joystick_repair").get("wins", 0))
	_difficulty = "lehrgang" if wins == 0 else ("werkbank" if wins < 3 else "profi")
	_model = RepairModel.new()
	var round_seed := int(hash("JOYSTICK/%d/%d/%d" % [TimeManager.day_counter, wins, roundi(_initial_condition * 100.0)]))
	_model.configure(_difficulty, false, round_seed)
	_build_shell()
	_begin_wire()
	_board.call_deferred("grab_focus")


func _build_shell() -> void:
	var safety := Bezel.dim_label(
		Loc.t("ui.joystick_repair_minigame.stecker_ab_nur_kleinspannung_spitze_heiss", "STECKER AB · NUR KLEINSPANNUNG · SPITZE HEISS  —  Farbe und Symbol gehören immer zusammen."), 11)
	safety.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(safety)

	var telemetry := HBoxContainer.new()
	_stage_label = Bezel.lcd_label("", Palette.LCD_AMBER, 11)
	_stage_label.custom_minimum_size = Vector2(300, 22)
	telemetry.add_child(_stage_label)
	_quality_label = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	telemetry.add_child(_quality_label)
	content.add_child(telemetry)

	_board = RepairBoard.new()
	_board.board_texture = BOARD_ART
	_board.model = _model
	_board.custom_minimum_size = Vector2(944, 470)
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.changed.connect(_refresh_telemetry)
	_board.request_heat.connect(_add_heat)
	_board.request_tin.connect(_add_tin)
	_board.request_finalize.connect(_finish_selected_joint)
	_board.request_undo.connect(_undo)
	_board.request_hint.connect(_show_hint)
	_board.request_reset.connect(_reset_round)
	_board.request_test.connect(_run_test)
	content.add_child(_board)
	_depth_rig = DepthRig.new()
	add_child(_depth_rig)
	_depth_rig.configure(_board, 0.82)

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


func _footer_button(label: String, callback: Callable, width := 145.0) -> Button:
	var button := make_button(label, callback)
	button.custom_minimum_size = Vector2(width, 38)
	return button


func _footer_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _add_common_footer(include_auto := true) -> void:
	_footer.add_child(_footer_button("ABBRECHEN", queue_free, 100))
	if include_auto:
		var auto_button := _footer_button("AUTO · 0 PUNKTE", _auto_repair, 155)
		auto_button.tooltip_text = Loc.t("ui.joystick_repair_minigame.repariert_sicher_zahlt_aber_nicht_als", "Repariert sicher, zählt aber nicht als eigener Werkstatt-Erfolg.")
		_footer.add_child(auto_button)


func _begin_wire() -> void:
	_stage = Stage.WIRE
	_board.set_stage(RepairBoard.WIRE)
	_stage_label.text = Loc.t("ui.joystick_repair_minigame.1_3_verdrahten_s_s_s", "1/3 VERDRAHTEN · %s · %s · %s") % [_difficulty.to_upper(),str(_model.joystick_model).to_upper(),str(_model.fault_family).to_upper()]
	_instruction.text = Loc.t("ui.joystick_repair_minigame.leitung_unten_wahlen_danach_passende_kupferose", "Leitung unten wählen und danach die passende Kupferöse anklicken. △/○/□/◇ machen die Zuordnung auch ohne Farberkennung eindeutig.")
	_clear_footer()
	_footer.add_child(_footer_button("PLAN / HILFE", _show_hint, 145))
	_footer.add_child(_footer_button("UNDO", _undo, 92))
	_footer.add_child(_footer_button("RESET", _reset_round, 92))
	_footer.add_child(_footer_spacer())
	_primary_button = _footer_button("WEITER: LÖTEN ▶", _begin_solder, 190)
	_primary_button.disabled = not _model.all_wired()
	_footer.add_child(_primary_button)
	_add_common_footer()
	_refresh_telemetry()


func _begin_solder() -> void:
	if not _model.all_wired():
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.erst_alle_vier_leitungen_mit_je", "Erst alle vier Leitungen mit je einer Öse verbinden."))
		return
	_stage = Stage.SOLDER
	_board.set_stage(RepairBoard.SOLDER)
	_stage_label.text = Loc.t("ui.joystick_repair_minigame.2_3_loten_warme_zinn_dosieren", "2/3  LÖTEN  ·  WÄRME + ZINN DOSIEREN")
	_instruction.text = Loc.t("ui.joystick_repair_minigame.ose_wahlen_warme_schrittweise_zufuhren_im", "Öse wählen. Wärme schrittweise zuführen, im grünen Fenster wenig Zinn dosieren und dann die Stelle werten. Kalt, zu heiß oder gebrückt? Mit Litze öffnen und neu löten.")
	_clear_footer()
	_footer.add_child(_footer_button("WÄRME +", _add_heat, 102))
	_footer.add_child(_footer_button("ZINN +", _add_tin, 92))
	_footer.add_child(_footer_button("ABKÜHLEN & WERTEN", _finish_selected_joint, 170))
	_footer.add_child(_footer_button("ENTLÖTLITZE", _desolder_selected, 120))
	_footer.add_child(_footer_button("UNDO", _undo, 72))
	_footer.add_child(_footer_spacer())
	_primary_button = _footer_button("WEITER: PRÜFEN ▶", _begin_test, 158)
	_primary_button.disabled = not _model.all_joints_closed()
	_footer.add_child(_primary_button)
	_add_common_footer(false)
	_refresh_telemetry()


func _begin_test() -> void:
	if not _model.all_joints_closed():
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.jede_vier_osen_muss_zuerst_bewertet", "Jede der vier Ösen muss zuerst bewertet sein."))
		return
	_stage = Stage.TEST
	_board.set_stage(RepairBoard.TEST)
	_stage_label.text = Loc.t("ui.joystick_repair_minigame.3_3_vierkanal_prufstand", "3/3  VIERKANAL-PRÜFSTAND")
	_instruction.text = Loc.t("ui.joystick_repair_minigame.prufsequenz_starten_stabiles_grun_durchgang_flackern", "Prüfsequenz starten. Stabiles Grün = Durchgang; Flackern = Kaltstelle; zwei Kanäle = Brücke; falsche Richtung = Leitung vertauscht.")
	_clear_footer()
	_footer.add_child(_footer_button("◀ ZURÜCK AN DIE BANK", _return_to_bank, 210))
	_footer.add_child(_footer_spacer())
	_primary_button = _footer_button("PRÜFSEQUENZ STARTEN", _run_test, 220)
	_footer.add_child(_primary_button)
	_add_common_footer()
	_refresh_telemetry()


func _refresh_telemetry() -> void:
	if _model == null or _board == null:
		return
	match _stage:
		Stage.WIRE:
			_quality_label.text = Loc.t("ui.joystick_repair_minigame.verbindungen_d_4_plan_s", "VERBINDUNGEN %d/4  ·  PLAN %s") % [
				_model.connected_count(), "SICHTBAR" if _board.hint_visible else "VERDECKT"]
			if _primary_button != null:
				_primary_button.disabled = not _model.all_wired()
		Stage.SOLDER:
			var values := _board.selected_values()
			_quality_label.text = Loc.t("ui.joystick_repair_minigame.lotstellen_d_4_warme_3d_zinn", "LÖTSTELLEN %d/4  ·  WÄRME %3d%%  ·  ZINN %3d%%") % [
				_model.good_joint_count(), roundi(float(values.get("heat", 0.0)) * 100.0),
				roundi(float(values.get("tin", 0.0)) * 100.0)]
			if _primary_button != null:
				_primary_button.disabled = not _model.all_joints_closed()
		Stage.TEST:
			_quality_label.text = Loc.t("ui.joystick_repair_minigame.gute_3d_prognose_04d_punkte", "GÜTE %3d%%  ·  PROGNOSE %04d PUNKTE") % [
				roundi(_model.average_quality() * 100.0), _model.score()]
		Stage.DONE:
			pass


func _add_heat() -> void:
	if _stage != Stage.SOLDER:
		return
	_board.add_heat(0.14)
	AudioManager.key_click()


func _add_tin() -> void:
	if _stage != Stage.SOLDER:
		return
	_board.add_tin(0.16)
	AudioManager.key_click()


func _finish_selected_joint() -> void:
	if _stage != Stage.SOLDER:
		return
	var result := _board.finalize_selected_joint()
	if result == "open":
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.erst_angeschlossene_kupferose_wahlen", "Erst eine angeschlossene Kupferöse wählen."))
		return
	AudioManager.play("solder_touch", 0.02)
	match result:
		"good": UIManager.toast(Loc.t("ui.joystick_repair_minigame.saubere_glanzende_lotstelle_mechanisch_stabil", "Saubere, glänzende Lötstelle — mechanisch stabil."))
		"cold": UIManager.toast(Loc.t("ui.joystick_repair_minigame.matte_kaltstelle_mehr_warme_genug_zinn", "Matte Kaltstelle: mehr Wärme und genug Zinn, dann neu fließen lassen."))
		"overheated": UIManager.toast(Loc.t("ui.joystick_repair_minigame.ose_uberhitzt_abkuhlen_mit_litze_offnen", "Öse überhitzt. Abkühlen, mit Litze öffnen und schonender neu löten."))
		"bridge": UIManager.toast(Loc.t("ui.joystick_repair_minigame.zu_viel_zinn_lotbrucke_mit_entlotlitze", "Zu viel Zinn: Lötbrücke. Mit Entlötlitze trennen."))
	_refresh_telemetry()


func _desolder_selected() -> void:
	if _stage != Stage.SOLDER or not _board.desolder_selected():
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.keine_geschlossene_lotstelle_ausgewahlt", "Keine geschlossene Lötstelle ausgewählt."))
		return
	AudioManager.key_click()
	_refresh_telemetry()


func _undo() -> void:
	if not _model.undo():
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.nichts_zum_ruckgangigmachen", "Nichts zum Rückgängigmachen."))
		return
	_board.sync_from_model()
	AudioManager.key_click()
	_refresh_telemetry()


func _reset_round() -> void:
	_model.reset_round()
	_board.reset_local_values()
	_begin_wire()
	UIManager.toast(Loc.t("ui.joystick_repair_minigame.werkbank_auf_denselben_serviceplan_zuruckgesetzt", "Werkbank auf denselben Serviceplan zurückgesetzt."))


func _show_hint() -> void:
	var hint: Dictionary = _model.next_hint()
	_board.show_hint(hint)
	if hint.is_empty():
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.alle_kanale_sehen_korrekt_aus_starte", "Alle Kanäle sehen korrekt aus — starte die Prüfsequenz."))
	elif str(hint.get("kind", "")) == "wire":
		var source := int(hint.get("source", 0))
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.serviceplan_s_s_gehort_zur_gleich", "Serviceplan: %s %s gehört zur gleich markierten Öse.") % [
			RepairModel.CHANNEL_KEYS[source], RepairModel.CHANNEL_SYMBOLS[source]])
	else:
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.grunes_warmefenster_ist_jetzt_verbreitert_zinn", "Grünes Wärmefenster ist jetzt verbreitert; Zinn weiterhin sparsam dosieren."))
	_refresh_telemetry()


func _run_test() -> void:
	if _stage != Stage.TEST:
		return
	var result: Dictionary = _model.diagnose()
	_board.show_diagnostic(result)
	if bool(result.get("success", false)):
		AudioManager.play("continuity_ok", 0.0)
		_complete()
	else:
		AudioManager.play("joint_bad", 0.01)
		_instruction.text = Loc.t("ui.joystick_repair_minigame.fehler_gefunden_lampen_nennen_kanal_ursache", "Fehler gefunden. Die Lampen nennen Kanal und Ursache — zurück an die Bank, gezielt korrigieren, erneut prüfen.")
		_quality_label.text = Loc.t("ui.joystick_repair_minigame.prufung_fehlgeschlagen_alles_reparierbar", "PRÜFUNG FEHLGESCHLAGEN  ·  ALLES REPARIERBAR")
		_quality_label.add_theme_color_override("font_color", Palette.LCD_AMBER)


func _return_to_bank() -> void:
	var routes_ok := true
	for source in RepairModel.CHANNEL_COUNT:
		routes_ok = routes_ok and _model.wire_targets[source] == source
	if routes_ok:
		_begin_solder()
	else:
		_begin_wire()


func _commit_success(score: int, details: Dictionary = {}) -> bool:
	if _finished or PlayerStats.energie < ENERGY_COST:
		return false
	if not PlayerStats.use_energy(ENERGY_COST):
		return false
	_finished = true
	var condition_before: float = PlayerStats.joystick_condition()
	PlayerStats.repair_joystick()
	var result_details: Dictionary = details.duplicate(true)
	result_details["condition_before"] = condition_before
	result_details["energy"] = ENERGY_COST
	result_details["practice"] = false
	_completion_result = MinigameManager.finish(
		"joystick_repair", true, maxi(0, score), result_details)
	# Savegame-kompatibler Welt-/Questmerker: Die erste echte Eigenreparatur ist
	# damit mehr als nur ein abstrakter Highscore und kann später aufgegriffen
	# werden, ohne die Reparatur erneut farmen zu müssen.
	AchievementManager.note("joystick_repaired")
	MemoryManager.record_once("joystick_repaired_self")
	return true


func _complete() -> void:
	var score: int = _model.score()
	if not _commit_success(score, _model.details()):
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.reparatur_konnte_nicht_verbucht_werden_zu", "Die Reparatur konnte nicht verbucht werden — zu wenig Energie."))
		return
	_stage = Stage.DONE
	var first_repair := bool(_completion_result.get("first_win", false))
	_stage_label.text = Loc.t("ui.joystick_repair_minigame.fertig_alle_vier_kanale_stabil", "FERTIG  ·  ALLE VIER KANÄLE STABIL")
	_quality_label.text = Loc.t("ui.joystick_repair_minigame.04d_punkte_joystick_repariert_s", "%04d PUNKTE  ·  JOYSTICK REPARIERT%s") % [
		score, "  ·  +1 WISSEN" if first_repair else ""]
	_quality_label.add_theme_color_override("font_color", Palette.LCD_GREEN)
	_instruction.text = (Loc.t("ui.joystick_repair_minigame.first_repair_saved",
		"Vier klare Prüfsignale. Erste Eigenreparatur im Werkstattbuch gespeichert.")
		if first_repair else Loc.t("ui.joystick_repair_minigame.maintenance_saved",
			"Vier klare Prüfsignale. Die Wartung ist im Werkstattbuch gespeichert."))
	_board.celebrate = true
	_board.queue_redraw()
	_clear_footer()
	_footer.add_child(_footer_spacer())
	_footer.add_child(_footer_button("WERKSTATT SCHLIESSEN", queue_free, 210))
	AudioManager.key_enter()
	UIManager.toast(("Joystick stabil — %d Punkte · +1 Wissen · dauerhaft repariert." % score)
		if first_repair else "Joystick wieder stabil — %d Punkte · Wartung gespeichert." % score)


func _auto_repair() -> void:
	if _finished or PlayerStats.energie < ENERGY_COST:
		UIManager.toast(Loc.t("ui.joystick_repair_minigame.zu_mude_fur_automatische_werkstattarbeit", "Zu müde für die automatische Werkstattarbeit."))
		return
	if not PlayerStats.use_energy(ENERGY_COST):
		return
	_finished = true
	var before := PlayerStats.joystick_condition()
	PlayerStats.repair_joystick()
	MinigameManager.finish("joystick_repair", false, 0, {
		"auto": true, "energy": ENERGY_COST, "condition_before": before,
	})
	AchievementManager.note("joystick_repaired_auto")
	MemoryManager.record("werkstatt", "den Joystick automatisch nachlöten lassen")
	UIManager.toast(Loc.t("ui.joystick_repair_minigame.joystick_dauerhaft_stabil_automatik_0_punkte", "Joystick dauerhaft stabil — Automatik: 0 Punkte, kein Werkstatt-Erfolg."))
	queue_free()
