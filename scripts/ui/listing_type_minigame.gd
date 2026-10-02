class_name ListingTypeMinigame
extends RetroWindow
## Magazin-Listing als vollwertiges Creator-Spiel: Vorlage lesen, exakt tippen,
## Diagnose laufen lassen, Fehler reparieren und das eigene PD-Tool sichern.
## Die Inszenierung komponiert ausschliesslich bestehende Projekt-Masterassets.

const Model := preload("res://scripts/minigames/listing_type_model.gd")
const Language := preload("res://scripts/sommer_basic/sommer_basic_language.gd")
const MagazinePrograms := preload("res://scripts/data/magazine_program_catalog.gd")
const ProjectStore := preload("res://scripts/sommer_basic/sommer_basic_project_store.gd")
const ENERGY_COST := 5

var listing_id := ""

var _model: ListingTypeModel
var _stage: ListingDeskStage
var _status: Label
var _instruction: Label
var _check_button: Button
var _finished := false
var _assisted := false
var _checks := 0
var _hints := 0
var _corrections := 0
var _last_text := ""
var _checked_once := false


func _init() -> void:
	title = Loc.t("ui.listing_type_minigame.magazin_listing_eigenes_pd_tool", "MAGAZIN-LISTING · EIGENES PD-TOOL")
	win_size = Vector2(1010, 810)


static func can_start(requested_listing_id := "") -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.listing_type_minigame.nur_waehrend_eines_laufenden_spiels_verfuegbar", "Nur waehrend eines laufenden Spiels verfuegbar.")}
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": Loc.t("ui.listing_type_minigame.zum_abtippen_brauchst_du_dein_heft", "Zum Abtippen brauchst du dein Heft und den Amiga im Zimmer.")}
	if InventoryManager.count("magazine") <= 0:
		return {"ok": false, "reason": Loc.t("ui.listing_type_minigame.kein_computer_magazin_im_regal_lager", "Kein Computer-Magazin im Regal (LAGER).")}
	if PlayerStats.energie < ENERGY_COST:
		return {"ok": false, "reason": Loc.t("ui.listing_type_minigame.zu_muede_fuer_fehlerfreies_listing_d", "Zu muede fuer ein fehlerfreies Listing (%d Energie noetig).") % ENERGY_COST}
	if not str(requested_listing_id).is_empty():
		var entry := MagazinePrograms.by_listing(str(requested_listing_id))
		var access := ProjectStore.access_status(entry, true)
		if not bool(access.get("ok", false)):
			return access
	return {"ok": true, "reason": ""}


func _ready() -> void:
	super._ready()
	var wins := int(MinigameManager.record("listing_type").get("wins", 0))
	_model = Model.new()
	var magazine_entry := MagazinePrograms.by_listing(listing_id) if not listing_id.is_empty() else {}
	if not magazine_entry.is_empty():
		_model.configure_from_magazine(magazine_entry, wins)
	else:
		_model.configure(TimeManager.year, wins,
			int(hash("LISTING/%d/%d/%d" % [TimeManager.day_counter, TimeManager.year, wins])))
	_build_shell()
	_stage.editor.grab_focus.call_deferred()


func _build_shell() -> void:
	var top := HBoxContainer.new()
	var intro := Bezel.dim_label(Loc.t("ui.listing_type_minigame.heft_links_lesen_quelltext_in_echte", "Heft links lesen · Quelltext in die echte 1084S-Roehre tippen · pruefen · Bugs korrigieren."), 11)
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(intro)
	_status = Bezel.lcd_label(Loc.t("ui.listing_type_minigame.s_s_s", "%s · %s · %s") % [_model.listing.get("title", "LISTING"),str(_model.language).to_upper(), _model.difficulty.to_upper()], Palette.LCD_AMBER, 11)
	top.add_child(_status)
	content.add_child(top)

	_stage = ListingDeskStage.new()
	_stage.model = _model
	_stage.custom_minimum_size = Vector2(974, 620)
	_stage.editor_changed.connect(_on_editor_changed)
	content.add_child(_stage)

	_instruction = Bezel.dim_label(Loc.t("ui.listing_type_minigame.leerzeichen_zeichen_zaehlen_abschliessende_leerzeilen_sind", "Leerzeichen und Zeichen zaehlen. Abschliessende Leerzeilen sind egal; der Inhalt nicht."), 11)
	_instruction.custom_minimum_size = Vector2(0, 27)
	content.add_child(_instruction)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 7)
	footer.add_child(make_button(Loc.t("ui.listing_type_minigame.zeile_zeigen", "ZEILE ZEIGEN"), _hint))
	footer.add_child(make_button(Loc.t("ui.listing_type_minigame.vorlage_tippfehler", "VORLAGE + TIPPFEHLER"), _assisted_copy))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_check_button = make_button(Loc.t("ui.listing_type_minigame.compilieren_pruefen", "▶ COMPILIEREN / PRUEFEN"), _check)
	_check_button.custom_minimum_size = Vector2(230, 38)
	footer.add_child(_check_button)
	content.add_child(footer)


func _on_editor_changed() -> void:
	var now := _stage.editor.text
	if _checked_once and now != _last_text:
		_corrections += 1
	_last_text = now
	AudioManager.key_click()
	var d := _model.diagnose(now)
	_stage.set_live_progress(int(d.get("line_count", 0)) - int(d.get("errors", 0)), int(d.get("line_count", 0)))


func _check() -> void:
	if _finished:
		return
	_checks += 1
	_checked_once = true
	_last_text = _stage.editor.text
	var d := _model.diagnose(_stage.editor.text)
	_stage.set_diagnostic(d)
	if bool(d.get("exact", false)):
		var compiler := Language.analyze_for_profile(_stage.editor.text, TimeManager.year,
			_target_hardware_profile())
		if not bool(compiler.get("ok", false)):
			_show_compiler_failure(compiler)
			return
		_complete()
		return
	var first := int(d.get("first_error", -1))
	_instruction.text = Loc.t("ui.listing_type_minigame.d_fehlerhafte_zeile_n_d_abweichende", "%d fehlerhafte Zeile(n), %d abweichende Zeichen. Die erste Fundstelle ist markiert.") % [
		int(d.get("errors", 0)), int(d.get("chars_wrong", 0))]
	_status.text = Loc.t("ui.listing_type_minigame.compiler_02d_fehler_durchlauf_02d", "COMPILER: %02d FEHLER  ·  DURCHLAUF %02d") % [int(d.get("errors", 0)), _checks]
	_status.add_theme_color_override("font_color", Color8(255, 104, 84))
	if first >= 0:
		_stage.focus_line(first)
	AudioManager.floppy_rattle()


func _hint() -> void:
	if _finished:
		return
	_hints += 1
	var d := _model.diagnose(_stage.editor.text)
	var line := maxi(0, int(d.get("first_error", 0)))
	var lines: Array = _model.listing.get("lines", [])
	line = mini(line, lines.size() - 1)
	_instruction.text = Loc.t("ui.listing_type_minigame.magazin_zeile_02d_s", "MAGAZIN-ZEILE %02d:  %s") % [line + 1, str(lines[line])]
	_stage.pulse_paper_line(line)
	_stage.focus_line(line)
	AudioManager.play("page_turn")


func _assisted_copy() -> void:
	if _finished:
		return
	_assisted = true
	_stage.editor.text = _model.assisted_copy()
	_last_text = _stage.editor.text
	_instruction.text = Loc.t("ui.listing_type_minigame.vorlage_uebernommen_einige_typische_0_o", "Vorlage uebernommen — einige typische 0/O- und Zeichenfehler sind absichtlich geblieben. Jetzt pruefen und reparieren.")
	_stage.editor.grab_focus()
	AudioManager.floppy_read()


func _complete() -> void:
	if _finished:
		return
	var score := _model.score(_checks, _corrections, _assisted, _hints)
	if not _commit_success(score, {
		"listing": str(_model.listing.get("id", "")), "checks": _checks,
		"corrections": _corrections, "hints": _hints, "assisted": _assisted,
	}):
		UIManager.toast(Loc.t("ui.listing_type_minigame.zu_wenig_energie_listing_bleibt_ungespeichert", "Zu wenig Energie — das Listing bleibt ungespeichert."))
		return
	_status.text = Loc.t("ui.listing_type_minigame.0_fehler_04d_punkte_sommer_basic", "0 FEHLER  ·  %04d PUNKTE  ·  SOMMER-BASIC-PROJEKT") % score \
		if _model.magazine_program else Loc.t("ui.listing_type_minigame.0_fehler_04d_punkte_pd_tool", "0 FEHLER  ·  %04d PUNKTE  ·  PD-TOOL GESPEICHERT") % score
	_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	_instruction.text = Loc.t("ui.listing_type_minigame.jahresprogramm_in_sommer_basic", "Quelle erfasst. Jetzt in Sommer BASIC ausfuehren, die Redaktionsaufgabe verbessern und erst danach implementieren.") \
		if _model.magazine_program else Loc.t("ui.listing_type_minigame.listing_laeuft_dein_eigenes_pd_tool", "Das Listing laeuft. Dein eigenes PD-Tool liegt jetzt dauerhaft auf der Werkbank.")
	_stage.celebrate()
	_check_button.disabled = true
	AudioManager.key_enter()
	UIManager.toast(Loc.t("ui.listing_type_minigame.listing_fehlerfrei_d_punkte_eigenes_pd", "Listing fehlerfrei — %d Punkte. Phase 1/4 abgeschlossen.") % score)


func _commit_success(score: int, details: Dictionary = {}) -> bool:
	if _finished or _model == null or PlayerStats.energie < ENERGY_COST:
		return false
	var magazine_entry: Dictionary = {}
	if _model.magazine_program:
		magazine_entry = MagazinePrograms.by_listing(str(_model.listing.get("id", "")))
		var access := ProjectStore.access_status(magazine_entry, true)
		if not bool(access.get("ok", false)):
			return false
	if not PlayerStats.use_energy(ENERGY_COST):
		return false
	if _model.magazine_program:
		var registered := ProjectStore.register_typed(
			magazine_entry, _model.target_text(), score)
		if not bool(registered.get("ok", false)):
			# Der Status wurde unmittelbar vorher geprueft; dieser Zweig ist nur
			# eine defensive Sicherung gegen einen unerwarteten Zustandswechsel.
			PlayerStats.energie = mini(100, PlayerStats.energie + ENERGY_COST)
			return false
	_finished = true
	MinigameManager.save_creation("listing", {
		"id": str(_model.listing.get("id", "listing")),
		"title": str(_model.listing.get("title", "MEIN LISTING")),
		"source": _model.target_text(), "score": score,
	})
	ProgramLibrary.install("my_listing_tool")
	if _model.magazine_program:
		ProgramLibrary.install("sommer_basic")
	GameManager.flags["listing_typed"] = true
	var result_details := details.duplicate(true)
	result_details["listing"] = str(_model.listing.get("id", ""))
	result_details["energy"] = ENERGY_COST
	MinigameManager.finish("listing_type", true, score, result_details)
	MemoryManager.record("kreativ", "das Magazin-Listing %s fehlerfrei abgetippt" % _model.listing.get("title", ""))
	return true


func _show_compiler_failure(compiler: Dictionary) -> void:
	var diagnostics: Array = compiler.get("diagnostics", [])
	var first: Dictionary = diagnostics[0] if not diagnostics.is_empty() else {}
	_instruction.text = Loc.t("ui.listing_type_minigame.compiler_profile_error", "Sommer BASIC meldet %s in Zeile %d: %s") % [
		str(first.get("code", "E?")), int(first.get("line", 0)), str(first.get("message", "Compilerfehler"))]
	_status.text = Loc.t("ui.listing_type_minigame.compiler_blocked", "COMPILER: PROFIL NICHT ERFUELLT")
	_status.add_theme_color_override("font_color", Color8(255, 104, 84))


func _target_hardware_profile() -> String:
	match str(PlayerStats.desk_model("computer_model")):
		"amiga_1200":
			return "amiga_1200_aga_hdd_4mb" if PlayerStats.hdd_is_usable() and \
				float(PlayerStats.hardware.get("ram_mb", 0.0)) >= 4.0 \
				else "amiga_1200_aga_2mb"
		"amiga_600":
			return "amiga_500_ecs_1mb"
		_:
			return "amiga_500_ocs_1mb"


class ListingDeskStage:
	extends Control
	signal editor_changed

	const DESK := preload("res://assets/ui/minigames/LISTING_DESK_EMPTY_MASTER_V01.png")
	const MONITOR := preload("res://assets/backgrounds/layers/MONITOR_COMMODORE_1084S_V02.png")
	const AMIGA := preload("res://assets/backgrounds/layers/COMPUTER_AMIGA500_V01.png")
	const MAGAZINE := preload("res://assets/backgrounds/layers/MAGAZINE_MASTER_V02.png")
	const LAMP := preload("res://assets/backgrounds/layers/DESK_LAMP_CLASSIC_V01.png")
	const LocationDepth := preload("res://scripts/gfx/location_stage_25d.gd")
	const SCREEN_FRAC := Rect2(0.099, 0.145, 0.802, 0.576)

	var model: ListingTypeModel
	var editor: TextEdit
	var _depth: Control
	var _items: Array[Dictionary] = []
	var _paper: Control
	var _crt: Control
	var _success := false
	var _pulse_line := -1
	var _pulse_t := 0.0

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
		_build_scene()
		set_process(true)

	func _build_scene() -> void:
		var bg := TextureRect.new()
		bg.name = "EmptyDeskMaster"
		bg.texture = DESK
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

		_depth = LocationDepth.new()
		_depth.configure(self, bg, "LISTING_DESK", {
			"horizon": 0.40, "strength": 0.010, "far_gain": 0.14, "near_gain": 0.72,
			"vertical_gain": 0.34, "overscan": 0.027, "pointer": 0.76, "idle": 0.06,
		})
		add_child(_depth)

		var mag := _object_group("MagazineMaster", MAGAZINE, Rect2(38, 185, 405, 382), -4.5, 0.82, 3)
		_paper = ListingPaper.new()
		_paper.model = model
		_paper.position = Vector2(50, 50)
		_paper.size = Vector2(310, 282)
		_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mag.add_child(_paper)

		var monitor := _object_group("Monitor1084S", MONITOR, Rect2(540, 34, 318, 299), 0.0, 0.54, 2)
		var sr := Rect2(SCREEN_FRAC.position * Vector2(318, 299), SCREEN_FRAC.size * Vector2(318, 299))
		editor = TextEdit.new()
		editor.name = "ListingEditor"
		editor.position = sr.position + Vector2(5, 4)
		editor.size = sr.size - Vector2(10, 8)
		editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE
		editor.scroll_fit_content_height = false
		editor.add_theme_font_override("font", load("res://assets/fonts/Topaz_a500_ui.ttf"))
		editor.add_theme_font_size_override("font_size", 12)
		editor.add_theme_color_override("font_color", Color8(126, 255, 183))
		editor.add_theme_color_override("caret_color", Color8(255, 228, 115))
		editor.add_theme_color_override("selection_color", Color(0.18, 0.48, 0.42, 0.75))
		var screen_box := StyleBoxFlat.new()
		screen_box.bg_color = Color8(3, 18, 20, 238)
		screen_box.border_color = Color8(54, 118, 105)
		screen_box.set_border_width_all(1)
		editor.add_theme_stylebox_override("normal", screen_box)
		editor.add_theme_stylebox_override("focus", screen_box)
		editor.text_changed.connect(func() -> void: editor_changed.emit())
		monitor.add_child(editor)
		_crt = CrtGlass.new()
		_crt.position = sr.position
		_crt.size = sr.size
		_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		monitor.add_child(_crt)

		_object_group("Amiga500", AMIGA, Rect2(470, 352, 450, 181), -0.8, 1.0, 4)
		_object_group("DeskLamp", LAMP, Rect2(830, 38, 146, 214), 3.0, 0.36, 1)

		var near := NearEdge.new()
		near.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		near.offset_top = -38
		near.mouse_filter = Control.MOUSE_FILTER_IGNORE
		near.z_index = 8
		add_child(near)

	func _object_group(node_name: String, texture: Texture2D, rect: Rect2,
			rotation_deg: float, gain: float, z: int) -> Control:
		var group := Control.new()
		group.name = node_name
		group.position = rect.position
		group.size = rect.size
		group.rotation_degrees = rotation_deg
		group.pivot_offset = rect.size * 0.5
		group.z_index = z
		add_child(group)
		var shadow := ObjectShadow.new()
		shadow.position = Vector2(rect.size.x * 0.07, rect.size.y * 0.78)
		shadow.size = Vector2(rect.size.x * 0.92, rect.size.y * 0.25)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(shadow)
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_SCALE
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(image)
		_items.append({"node": group, "position": rect.position, "gain": gain,
			"rotation": rotation_deg})
		return group

	func _process(delta: float) -> void:
		if _pulse_t > 0.0:
			_pulse_t = maxf(0.0, _pulse_t - delta)
			_paper.set("pulse_t", _pulse_t)
			_paper.queue_redraw()
		var look: Vector2 = _depth.look if _depth != null else Vector2.ZERO
		var enabled := bool(SettingsManager.value("location_depth"))
		for item: Dictionary in _items:
			var node := item["node"] as Control
			var gain := float(item["gain"]) if enabled else 0.0
			node.position = (item["position"] as Vector2) + Vector2(look.x * 8.0, look.y * 3.8) * gain
			node.rotation_degrees = float(item["rotation"]) + look.x * 0.16 * gain
			var focus := 1.0 + maxf(0.0, -look.y) * 0.003 * gain
			node.scale = Vector2.ONE * focus

	func set_live_progress(ok: int, total: int) -> void:
		if _crt != null:
			_crt.set("progress", float(ok) / maxf(1.0, total))
			_crt.queue_redraw()

	func set_diagnostic(d: Dictionary) -> void:
		_paper.set("states", d.get("line_states", []))
		_paper.queue_redraw()
		_crt.set("error_count", int(d.get("errors", 0)))
		_crt.queue_redraw()

	func focus_line(line: int) -> void:
		editor.set_caret_line(clampi(line, 0, maxi(0, editor.get_line_count() - 1)))
		editor.set_caret_column(0)
		editor.grab_focus()

	func pulse_paper_line(line: int) -> void:
		_pulse_line = line
		_pulse_t = 1.0
		_paper.set("pulse_line", line)
		_paper.set("pulse_t", _pulse_t)
		_paper.queue_redraw()

	func celebrate() -> void:
		_success = true
		editor.editable = false
		_crt.set("success", true)
		_crt.queue_redraw()
		_paper.set("states", [])
		_paper.queue_redraw()


class ListingPaper:
	extends Control
	var model: ListingTypeModel
	var states: Array = []
	var pulse_line := -1
	var pulse_t := 0.0

	func _ready() -> void:
		queue_redraw()

	func _draw() -> void:
		if model == null:
			return
		var font := load("res://assets/fonts/Topaz_a500_ui.ttf") as Font
		draw_string(font, Vector2(18, 24), str(model.listing.get("title", "LISTING")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color8(45, 35, 24))
		draw_string(font, Vector2(18, 42), "COMPUTER-MAGAZIN · LISTING", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color8(104, 72, 44))
		var lines: Array = model.listing.get("lines", [])
		for i in lines.size():
			var y := 65.0 + i * 19.0
			var col := Color8(48, 42, 34)
			if i < states.size() and str(states[i]) == "error":
				col = Color8(174, 53, 40)
			elif i < states.size() and str(states[i]) == "ok":
				col = Color8(40, 102, 58)
			if i == pulse_line and pulse_t > 0.0:
				draw_rect(Rect2(12, y - 13, 284, 17), Color(1.0, 0.72, 0.18, 0.22 * pulse_t))
			draw_string(font, Vector2(17, y), "%02d  %s" % [i + 1, str(lines[i])], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


class CrtGlass:
	extends Control
	var progress := 0.0
	var error_count := 0
	var success := false
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for y in range(1, int(size.y), 4):
			draw_line(Vector2(1, y), Vector2(size.x - 1, y), Color(0, 0, 0, 0.10), 1)
		var edge := Color(0.18, 0.72, 0.56, 0.26 + sin(_t * 2.0) * 0.025)
		draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), edge, false, 2.0)
		draw_rect(Rect2(6, size.y - 7, (size.x - 12) * clampf(progress, 0.0, 1.0), 2),
			Color8(98, 239, 160, 190))
		if error_count > 0:
			draw_string(ThemeDB.fallback_font, Vector2(size.x - 62, 13), "%02d ERR" % error_count,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color8(255, 104, 84))
		if success:
			draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(0.2, 1.0, 0.55, 0.12))


class ObjectShadow:
	extends Control
	func _draw() -> void:
		for i in 8:
			var inset := float(i) * 2.0
			_draw_shadow_ellipse(Rect2(Vector2(inset, inset * 0.35), size - Vector2(inset * 2.0, inset * 0.7)),
				Color(0.02, 0.015, 0.01, 0.055 * (1.0 - float(i) / 8.0)))

	func _draw_shadow_ellipse(rect: Rect2, color: Color) -> void:
		var points := PackedVector2Array()
		for i in 32:
			var a := TAU * float(i) / 32.0
			points.append(rect.get_center() + Vector2(cos(a) * rect.size.x * 0.5, sin(a) * rect.size.y * 0.5))
		draw_colored_polygon(points, color)


class NearEdge:
	extends Control
	func _draw() -> void:
		draw_rect(Rect2(0, 7, size.x, size.y - 7), Color(0.055, 0.026, 0.012, 0.82))
		draw_rect(Rect2(0, 0, size.x, 9), Color(0.34, 0.17, 0.07, 0.85))
		draw_line(Vector2(0, 1), Vector2(size.x, 1), Color(0.78, 0.45, 0.18, 0.40), 2.0)
