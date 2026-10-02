class_name HardwareAssemblyMinigame
extends RetroWindow
## Grubers jahresgenaue Servicebench. Das Brett zeigt geschlossene und geoeffnete
## Hardware als echten Zustand; Bild, Hotspots und Arbeitskarte lesen dasselbe Modell.

const Model := preload("res://scripts/minigames/hardware_assembly_model.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const TRAINING_ENERGY := 5

var job_id := ""
var _model: HardwareAssemblyModel
var _board: AssemblyBoard
var _status: Label
var _steps: Label
var _next_step: Label
var _esd_bar: ProgressBar
var _damage_bar: ProgressBar
var _action_buttons := {}
var _finished := false


func _init() -> void:
	title = Loc.t("ui.hardware_assembly_minigame.gruber_servicebench_esd_montage",
		"GRUBER SERVICEBENCH · ESD / MONTAGE")
	win_size = Vector2(1000, 650)


static func can_start(next_job_id := "") -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t(
			"ui.hardware_assembly_minigame.nur_im_laufenden_spiel_verfuegbar",
			"Nur im laufenden Spiel verfuegbar.")}
	if next_job_id != "":
		var job := JobManager.job_by_id(next_job_id)
		if job.is_empty() or str(job.get("minigame", "")) != "hardware_assembly":
			return {"ok": false, "reason": Loc.t(
				"ui.hardware_assembly_minigame.kein_hardware_montageauftrag",
				"Kein Hardware-Montageauftrag.")}
		if not JobManager.offered_here(job, GameManager.current_location_id):
			return {"ok": false, "reason": Loc.t(
				"ui.hardware_assembly_minigame.grubers_serviceauftrag_ist_gerade_nicht_verfuegbar",
				"Grubers Serviceauftrag ist gerade nicht verfuegbar.")}
		return JobManager.can_do(job)
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": Loc.t(
			"ui.hardware_assembly_minigame.freies_training_nur_an_heimischen_werkbank",
			"Freies Training nur an der heimischen Werkbank.")}
	return {
		"ok": PlayerStats.energie >= TRAINING_ENERGY,
		"reason": Loc.t("ui.hardware_assembly_minigame.zu_muede_fuer_montage",
			"Zu muede fuer die Montage.") if PlayerStats.energie < TRAINING_ENERGY else "",
	}


func _ready() -> void:
	super._ready()
	var wins := int(MinigameManager.record("hardware_assembly").get("wins", 0))
	# Ein spaeter Spielstand darf nicht mit einer 1990er Einsteigerkarte beginnen:
	# Kompetenzstufe waechst mit Karrierejahr und realer Werkstatterfahrung.
	var career_level := clampi(1 + floori(maxf(0.0,
		float(TimeManager.year - 1990)) / 2.0), 1, 4)
	var practice_level := clampi(1 + floori(float(wins) / 2.0), 1, 4)
	var assembly_level := maxi(career_level, practice_level)
	if job_id == "job_gesellenpruefung":
		assembly_level = 4
	_model = Model.new()
	_model.configure(assembly_level,
		hash("ESD/%d/%d/%s" % [TimeManager.day_counter, wins, job_id]),
		TimeManager.year, &"amiga_1200" if job_id == "job_gesellenpruefung" else &"")
	_build_ui()


func _build_ui() -> void:
	var preflight := HBoxContainer.new()
	preflight.add_theme_constant_override("separation", 10)
	content.add_child(preflight)
	var safety := Bezel.dim_label(Loc.t(
		"ui.hardware_assembly_minigame.sicher_arbeiten_stromlos_geerdet_kontrolliert_kein",
		"Sicher arbeiten: stromlos · geerdet · kontrolliert. Kein Zeitlimit."), 11)
	safety.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preflight.add_child(safety)
	var era := Bezel.lcd_label(Loc.t(
		"ui.hardware_assembly_minigame.sommer_d_s",
		"SOMMER %d · %s") % [
			_model.configured_year, Model.PLATFORM_LABELS[_model.platform]],
		Palette.LCD_AMBER, 11)
	preflight.add_child(era)

	var split := HBoxContainer.new()
	split.name = "AssemblyWorkbench25D"
	split.custom_minimum_size = Vector2(964, 492)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	content.add_child(split)
	var rig := DepthRig.new()
	split.add_child(rig)
	rig.configure(split, 0.48)

	_board = AssemblyBoard.new()
	_board.model = _model
	_board.action_requested.connect(_act)
	_board.custom_minimum_size = Vector2(658, 492)
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_board)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(294, 0)
	controls.add_theme_constant_override("separation", 5)
	split.add_child(controls)
	_build_job_card(controls)
	_build_action_grid(controls)
	_build_help_controls(controls)
	_refresh("Werkbank bereit. Arbeitskarte und Bauteilzonen pruefen.")


func _build_job_card(parent: VBoxContainer) -> void:
	var card := PanelContainer.new()
	var card_box := Bezel.panel_box()
	card_box.bg_color = Color8(11, 18, 19)
	card_box.border_color = Color8(75, 112, 101)
	card.add_theme_stylebox_override("panel", card_box)
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	card.add_child(body)
	var heading := Bezel.lcd_label(Loc.t(
		"ui.hardware_assembly_minigame.arbeitskarte_s",
		"ARBEITSKARTE · %s") % _model.platform_brief(), Palette.LCD_AMBER, 11)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(heading)
	_steps = Bezel.lcd_label("", Palette.LCD_GREEN, 10)
	body.add_child(_steps)
	_next_step = Label.new()
	_next_step.custom_minimum_size.y = 78
	_next_step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_step.add_theme_font_size_override("font_size", 12)
	_next_step.add_theme_color_override("font_color", Color8(225, 236, 225))
	body.add_child(_next_step)

	var esd_row := HBoxContainer.new()
	esd_row.add_child(Bezel.dim_label(Loc.t(
		"ui.hardware_assembly_minigame.esd", "ESD"), 9))
	_esd_bar = Bezel.bar(Color8(60, 217, 129), Vector2(132, 9))
	_esd_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	esd_row.add_child(_esd_bar)
	body.add_child(esd_row)
	var damage_row := HBoxContainer.new()
	damage_row.add_child(Bezel.dim_label(Loc.t(
		"ui.hardware_assembly_minigame.risiko", "RISIKO"), 9))
	_damage_bar = Bezel.bar(Color8(224, 74, 50), Vector2(132, 9))
	_damage_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	damage_row.add_child(_damage_bar)
	body.add_child(damage_row)


func _build_action_grid(parent: VBoxContainer) -> void:
	var caption := Bezel.dim_label(Loc.t(
		"ui.hardware_assembly_minigame.arbeitsgriffe_brett_oder_taste",
		"ARBEITSGRIFFE · BRETT ODER TASTE"), 9)
	caption.add_theme_color_override("font_color", Palette.LCD_AMBER)
	parent.add_child(caption)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for action: StringName in _model.sequence:
		var button := make_button("%s  %s" % [
			Model.ACTION_CODES[action], Model.ACTION_LABELS[action]], _act.bind(action))
		button.custom_minimum_size = Vector2(143, 31)
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = _model.guidance(action)
		grid.add_child(button)
		_action_buttons[action] = button


func _build_help_controls(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	var help_row := HBoxContainer.new()
	help_row.add_theme_constant_override("separation", 4)
	parent.add_child(help_row)
	var hint_button := make_button(Loc.t(
		"ui.hardware_assembly_minigame.hinweis_punkteabzug", "HINWEIS (-PUNKTE)"), _hint)
	hint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_row.add_child(hint_button)
	var demo_button := make_button(Loc.t(
		"ui.hardware_assembly_minigame.service_demo", "ABLAUF-DEMO"), _auto)
	demo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_row.add_child(demo_button)
	_status = Bezel.lcd_label("", Palette.LCD_AMBER, 10)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 46
	parent.add_child(_status)


func _act(action: StringName) -> void:
	if _finished:
		return
	var result := _model.perform(action)
	var ok := bool(result.get("ok", false))
	_board.animate_action(action, ok)
	_refresh(str(result.get("text", "")))
	AudioManager.minigame_cue("hardware_assembly", &"action" if ok else &"error")
	if _model.failed():
		_finished = true
		_status.text = Loc.t(
			"ui.hardware_assembly_minigame.abbruch_zwei_sicherheitskritische_fehler_keine_ressourcen",
			"ABBRUCH · Zwei sicherheitskritische Fehler. Keine Ressourcen verbraucht.")
		_board.queue_redraw()
	elif _model.complete():
		_commit()


func _hint() -> void:
	if _finished:
		return
	var action := _model.hint()
	_board.reveal_hint(action)
	_refresh("Werkstatthandbuch: %s\n%s" % [
		Model.ACTION_LABELS[action], _model.guidance(action)])


func _auto() -> void:
	if _finished:
		return
	_model.auto_finish()
	_board.animate_action(&"power_test", true)
	_refresh("Service-Demo hat die sichere Folge Schritt fuer Schritt gezeigt.")
	_commit()


func _refresh(message: String) -> void:
	var expected := _model.expected()
	_steps.text = Loc.t(
		"ui.hardware_assembly_minigame.level_d_schritt_d_d_fehler_d_schaden_d",
		"LEVEL %d · SCHRITT %d/%d · FEHLER %d · SCHADEN %d/2") % [
			_model.level, _model.cursor, _model.sequence.size(),
			_model.mistakes, _model.damage]
	_next_step.text = Loc.t(
		"ui.hardware_assembly_minigame.jetzt_s_s",
		"JETZT: %s\n%s") % [
		Model.ACTION_LABELS.get(expected, "ABSCHLUSS"),
		_model.guidance(expected) if not expected.is_empty() else "Arbeitskarte abgeschlossen."]
	_esd_bar.value = clampf((1.0 - _model.esd_charge) * 100.0, 0.0, 100.0) \
		if _model.completed_action(&"ground") else 0.0
	_damage_bar.value = clampf(float(_model.damage) / 2.0 * 100.0, 0.0, 100.0)
	for action: StringName in _action_buttons:
		var button := _action_buttons[action] as Button
		var done := _model.completed_action(action)
		var current := action == expected and not _finished
		button.disabled = done or _finished
		button.text = ("%s  %s" % [
			"OK" if done else (">" if current else Model.ACTION_CODES[action]),
			Model.ACTION_LABELS[action]])
		button.add_theme_color_override("font_color",
			Palette.LCD_GREEN if current else (Palette.UI_TEXT_DIM if done else Palette.WHITE_SOFT))
		button.add_theme_color_override("font_disabled_color",
			Color8(75, 170, 112) if done else Palette.UI_TEXT_DIM)
	_status.text = message
	_board.queue_redraw()


func _commit() -> bool:
	if _finished or not _model.complete():
		return false
	var score := _model.score()
	var details := _model.details()
	if job_id != "":
		var result := JobManager.complete_minigame_job(job_id, score, details)
		if not bool(result.get("ok", false)):
			if _status != null:
				_status.text = str(result.get("text",
					"Auftrag konnte nicht abgeschlossen werden."))
			return false
		details["pay"] = int(result.get("pay", 0))
	elif not PlayerStats.use_energy(TRAINING_ENERGY):
		if _status != null:
			_status.text = Loc.t(
				"ui.hardware_assembly_minigame.nicht_genug_energie_fuer_den_abschluss",
				"Nicht genug Energie fuer den Abschluss.")
		return false
	_finished = true
	MinigameManager.finish("hardware_assembly", true, score, details)
	GameManager.flags["last_hardware_assembly"] = details
	if _status != null:
		_status.text = Loc.t(
			"ui.hardware_assembly_minigame.bestanden_04d_punkte_kontakte_esd_sauber",
			"BESTANDEN · %04d PUNKTE · KONTAKTE UND ESD SAUBER") % score
		_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	for button: Button in _action_buttons.values():
		button.disabled = true
	AudioManager.key_enter()
	UIManager.toast(Loc.t("ui.hardware_assembly_minigame.hardware_sicher_montiert_d_punkte", "Hardware sicher montiert — %d Punkte.") % score)
	if _board != null:
		_board.queue_redraw()
	return true


class AssemblyBoard:
	extends Control
	signal action_requested(action: StringName)

	const UI_FONT := preload("res://assets/fonts/VT323_UI.ttf")
	const PLATFORM_ART := {
		&"amiga_500": preload("res://assets/ui/minigames/HARDWARE_SERVICE_A500_OPEN_V02.png"),
		&"amiga_600": preload("res://assets/ui/minigames/HARDWARE_SERVICE_A600_OPEN_V02.png"),
		&"amiga_1200": preload("res://assets/ui/minigames/HARDWARE_SERVICE_A1200_OPEN_V02.png"),
		&"external_drive": preload("res://assets/ui/minigames/HARDWARE_SERVICE_A1011_OPEN_V02.png"),
	}
	const CLOSED_ART := {
		&"amiga_500": preload("res://assets/backgrounds/layers/COMPUTER_AMIGA500_V02.png"),
		&"amiga_600": preload("res://assets/backgrounds/layers/COMPUTER_AMIGA600_V01.png"),
		&"amiga_1200": preload("res://assets/backgrounds/layers/COMPUTER_AMIGA1200_V03.png"),
		&"external_drive": preload("res://assets/backgrounds/layers/DRIVE_COMMODORE_A1011_V01.png"),
	}
	const COMMON_ZONES := {
		&"power_off": Rect2(.02, .04, .20, .23),
		&"ground": Rect2(.79, .04, .19, .23),
		&"open_case": Rect2(.22, .03, .56, .21),
		&"inspect": Rect2(.24, .25, .48, .27),
		&"diagnose": Rect2(.38, .31, .25, .19),
		&"ram": Rect2(.02, .43, .20, .38),
		&"drive": Rect2(.66, .24, .19, .35),
		&"secure": Rect2(.84, .42, .15, .39),
		&"visual": Rect2(.22, .23, .64, .50),
		&"power_test": Rect2(.39, .78, .22, .15),
	}
	const EXTERNAL_ZONES := {
		&"power_off": Rect2(.02, .04, .22, .25),
		&"ground": Rect2(.77, .04, .21, .25),
		&"open_case": Rect2(.27, .01, .46, .20),
		&"inspect": Rect2(.58, .23, .18, .34),
		&"diagnose": Rect2(.57, .31, .18, .22),
		&"drive": Rect2(.27, .21, .45, .42),
		&"secure": Rect2(.79, .41, .19, .39),
		&"visual": Rect2(.24, .20, .54, .48),
		&"power_test": Rect2(.39, .78, .22, .15),
	}

	var model: HardwareAssemblyModel
	var _hover: StringName = &""
	var _drag: StringName = &""
	var _last_action: StringName = &""
	var _last_ok := false
	var _action_flash := 0.0
	var _hint_action: StringName = &""
	var _hint_time := 0.0
	var _pulse := 0.0
	var _art_rect := Rect2()
	var _rail_rect := Rect2()


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		set_process(true)


	func _process(delta: float) -> void:
		var bounded_delta := minf(maxf(delta, 0.0), 1.0 / 20.0)
		if not bool(SettingsManager.value("reduced_motion")):
			_pulse = fmod(_pulse + bounded_delta, TAU)
		_action_flash = maxf(0.0, _action_flash - bounded_delta * 2.8)
		_hint_time = maxf(0.0, _hint_time - bounded_delta)
		if _hint_time <= 0.0:
			_hint_action = &""
		queue_redraw()


	func animate_action(action: StringName, ok: bool) -> void:
		_last_action = action
		_last_ok = ok
		_action_flash = 1.0
		queue_redraw()


	func reveal_hint(action: StringName) -> void:
		_hint_action = action
		_hint_time = 3.5
		queue_redraw()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			_hover = _action_at(event.position)
			tooltip_text = model.guidance(_hover) if not _hover.is_empty() else ""
			queue_redraw()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag = _action_at(event.position)
				grab_focus()
			else:
				var released := _action_at(event.position)
				if not _drag.is_empty() and (released == _drag or released.is_empty()):
					action_requested.emit(_drag)
				_drag = &""
				queue_redraw()
		elif event is InputEventKey and event.pressed \
				and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			action_requested.emit(model.expected())
			accept_event()


	func _zones() -> Dictionary:
		return EXTERNAL_ZONES if model.platform == &"external_drive" else COMMON_ZONES


	func _zone_rect(action: StringName) -> Rect2:
		var normal: Rect2 = _zones().get(action, Rect2())
		return Rect2(_art_rect.position + normal.position * _art_rect.size,
			normal.size * _art_rect.size)


	func _action_at(point: Vector2) -> StringName:
		var expected := model.expected()
		if not expected.is_empty() and _zone_rect(expected).has_point(point):
			return expected
		for action: StringName in model.sequence:
			if not model.completed_action(action) and _zone_rect(action).has_point(point):
				return action
		return &""


	func _draw() -> void:
		if model == null or size.x < 8.0 or size.y < 8.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color8(42, 29, 20), true)
		var art: Texture2D = PLATFORM_ART.get(model.platform, PLATFORM_ART[&"amiga_500"])
		_art_rect = _top_fit_rect(art.get_size(), Rect2(7, 7, size.x - 14, size.y - 14))
		draw_texture_rect(art, _art_rect, false)
		_draw_closed_state()
		_draw_top_plate()
		_draw_completed_markers()
		_draw_live_focus()
		_draw_progress_rail()
		_draw_service_log()
		_draw_feedback_flash()


	func _contain_rect(source_size: Vector2, bounds: Rect2) -> Rect2:
		var factor := minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
		var target_size := source_size * factor
		return Rect2(bounds.get_center() - target_size * 0.5, target_size)


	func _top_fit_rect(source_size: Vector2, bounds: Rect2) -> Rect2:
		var factor := minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
		var target_size := source_size * factor
		return Rect2(Vector2(bounds.get_center().x - target_size.x * 0.5,
			bounds.position.y), target_size)


	func _draw_closed_state() -> void:
		if model.completed_action(&"open_case"):
			return
		draw_rect(_art_rect, Color(0.005, 0.012, 0.012, 0.68), true)
		var closed: Texture2D = CLOSED_ART.get(model.platform, CLOSED_ART[&"amiga_500"])
		var closed_bounds := _art_rect.grow(-_art_rect.size.y * 0.17)
		var closed_rect := _contain_rect(closed.get_size(), closed_bounds)
		draw_texture_rect(closed, closed_rect, false)
		draw_rect(closed_rect.grow(8), Color(0.75, 0.90, 0.83, 0.22), false, 2)
		draw_string(UI_FONT, closed_rect.position + Vector2(8, -8),
			"GEHAEUSE GESCHLOSSEN · ERST STROMLOS UND GEERDET OEFFNEN",
			HORIZONTAL_ALIGNMENT_LEFT, closed_rect.size.x, 16, Color8(238, 214, 148))


	func _draw_top_plate() -> void:
		var plate := Rect2(_art_rect.position + Vector2(8, 8),
			Vector2(_art_rect.size.x - 16, 34))
		draw_rect(plate, Color(0.01, 0.018, 0.017, 0.88), true)
		draw_rect(plate, Color8(108, 137, 124), false, 1)
		draw_string(UI_FONT, plate.position + Vector2(10, 22),
			"%d // %s // %s" % [model.configured_year,
				Model.PLATFORM_LABELS[model.platform], model.platform_brief()],
			HORIZONTAL_ALIGNMENT_LEFT, plate.size.x - 150, 16, Color8(236, 225, 190))
		var grounded := model.completed_action(&"ground")
		var badge := Rect2(plate.end.x - 128, plate.position.y + 5, 118, 24)
		draw_rect(badge, Color(0.01, 0.035, 0.025, 0.94), true)
		draw_circle(badge.position + Vector2(12, 12), 6,
			Color8(62, 225, 132) if grounded else Color8(228, 79, 52))
		draw_string(UI_FONT, badge.position + Vector2(23, 17),
			"ESD SAFE" if grounded else "ESD OFFEN",
			HORIZONTAL_ALIGNMENT_LEFT, 90, 14, Color8(216, 239, 222))


	func _draw_completed_markers() -> void:
		for action: StringName in model.sequence:
			if not model.completed_action(action):
				continue
			# Die drei Sicherheitsgriffe liegen am oberen Gehaeuserand. Ihr Status
			# steht bereits eindeutig in ESD-Badge und Fortschrittsleiste; weitere
			# Marken wuerden dort das Geraeteschild verdecken.
			if action in [&"power_off", &"ground", &"open_case"]:
				continue
			var zone := _zone_rect(action)
			var badge_pos := zone.position + Vector2(11, 11)
			draw_circle(badge_pos, 10, Color(0.03, 0.13, 0.08, 0.94))
			draw_circle(badge_pos, 10, Color8(73, 226, 139), false, 2)
			draw_string(UI_FONT, badge_pos + Vector2(-6, 5), "OK",
				HORIZONTAL_ALIGNMENT_CENTER, 12, 11, Color8(145, 255, 190))


	func _draw_live_focus() -> void:
		var expected := model.expected()
		if expected.is_empty():
			draw_rect(_art_rect, Color(0.12, 0.95, 0.46, 0.08), true)
			return
		var zone := _zone_rect(expected)
		var hinting := _hint_action == expected and _hint_time > 0.0
		var pulse_alpha := 0.07 + (sin(_pulse * 4.0) * 0.5 + 0.5) * 0.06
		if bool(SettingsManager.value("reduced_motion")):
			pulse_alpha = 0.11
		var focus_color := Color(0.28, 1.0, 0.63, pulse_alpha)
		if hinting:
			focus_color = Color(1.0, 0.72, 0.18, 0.18)
		draw_rect(zone, focus_color, true)
		_draw_brackets(zone, Color8(255, 193, 64) if hinting else Color8(87, 245, 155), 3.0)
		var badge_y := maxf(zone.position.y + 7.0, _art_rect.position.y + 48.0)
		var badge := Rect2(Vector2(zone.position.x + 7, badge_y), Vector2(126, 25))
		draw_rect(badge, Color(0.015, 0.025, 0.021, 0.94), true)
		draw_rect(badge, Color8(255, 193, 64) if hinting else Color8(87, 245, 155), false, 1)
		draw_string(UI_FONT, badge.position + Vector2(7, 18),
			"%02d  %s" % [model.cursor + 1, Model.ACTION_CODES[expected]],
			HORIZONTAL_ALIGNMENT_LEFT, 112, 15, Color8(238, 245, 229))
		if _hover != &"" and _hover != expected:
			var hover_zone := _zone_rect(_hover)
			draw_rect(hover_zone, Color(1.0, 0.68, 0.15, 0.08), true)
			_draw_brackets(hover_zone, Color8(224, 157, 46), 2.0)


	func _draw_brackets(rect: Rect2, color: Color, width: float) -> void:
		var length := minf(22.0, minf(rect.size.x, rect.size.y) * 0.24)
		var p := rect.position
		var e := rect.end
		draw_line(p, p + Vector2(length, 0), color, width)
		draw_line(p, p + Vector2(0, length), color, width)
		draw_line(Vector2(e.x, p.y), Vector2(e.x - length, p.y), color, width)
		draw_line(Vector2(e.x, p.y), Vector2(e.x, p.y + length), color, width)
		draw_line(Vector2(p.x, e.y), Vector2(p.x + length, e.y), color, width)
		draw_line(Vector2(p.x, e.y), Vector2(p.x, e.y - length), color, width)
		draw_line(e, e - Vector2(length, 0), color, width)
		draw_line(e, e - Vector2(0, length), color, width)


	func _draw_progress_rail() -> void:
		var rail_top := _art_rect.end.y + 9.0
		if size.y - rail_top < 43.0:
			rail_top = _art_rect.end.y - 43.0
		_rail_rect = Rect2(_art_rect.position.x + 12, rail_top,
			_art_rect.size.x - 24, 39)
		draw_rect(_rail_rect, Color(0.008, 0.014, 0.014, 0.90), true)
		draw_rect(_rail_rect, Color8(67, 90, 82), false, 1)
		var count := model.sequence.size()
		for index in count:
			var x := _rail_rect.position.x \
				+ (float(index) + 0.5) / float(count) * _rail_rect.size.x
			if index < count - 1:
				var next_x := _rail_rect.position.x \
					+ (float(index) + 1.5) / float(count) * _rail_rect.size.x
				draw_line(Vector2(x, _rail_rect.position.y + 12),
					Vector2(next_x, _rail_rect.position.y + 12), Color8(69, 82, 78), 2)
			var done := index < model.cursor
			var current := index == model.cursor
			var color := Color8(73, 226, 139) if done else (
				Color8(255, 193, 64) if current else Color8(92, 102, 99))
			draw_circle(Vector2(x, _rail_rect.position.y + 12), 5, color)
			draw_string(UI_FONT, Vector2(x - 23, _rail_rect.position.y + 31),
				str(Model.ACTION_CODES[model.sequence[index]]),
				HORIZONTAL_ALIGNMENT_CENTER, 46, 11, color)


	func _draw_service_log() -> void:
		var top := _rail_rect.end.y + 7.0
		var available := size.y - top - 7.0
		if available < 30.0:
			return
		var panel := Rect2(_art_rect.position.x + 12, top,
			_art_rect.size.x - 24, available)
		draw_rect(panel, Color(0.018, 0.028, 0.025, 0.96), true)
		draw_rect(panel, Color8(73, 96, 87), false, 1)
		draw_rect(Rect2(panel.position, Vector2(4, panel.size.y)),
			Color8(255, 181, 46), true)
		draw_string(UI_FONT, panel.position + Vector2(13, 20),
			"WERKSTATT-PROTOKOLL // %02d VON %02d GRIFFEN BESTAETIGT" % [
				model.cursor, model.sequence.size()],
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24, 14, Color8(255, 193, 64))
		if available < 50.0:
			return
		var netz := "OK" if model.completed_action(&"power_off") else "OFFEN"
		var esd := "OK" if model.completed_action(&"ground") else "OFFEN"
		var geh := "OFFEN" if model.completed_action(&"open_case") else "GESCHLOSSEN"
		draw_string(UI_FONT, panel.position + Vector2(13, 39),
			"NETZ %s   ·   ESD %s   ·   GEHAEUSE %s   ·   RISIKO %d/2" % [
				netz, esd, geh, model.damage],
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24, 13, Color8(190, 218, 205))
		if available < 69.0:
			return
		var expected := model.expected()
		var next_text := "ABNAHME KOMPLETT" if expected.is_empty() else \
			"NAECHSTER MESSPUNKT: %s" % Model.ACTION_LABELS[expected]
		draw_string(UI_FONT, panel.position + Vector2(13, 58), next_text,
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24, 13, Color8(121, 235, 169))
		if available >= 88.0:
			draw_string(UI_FONT, panel.position + Vector2(13, 77),
				"KLICK/DRAG AUF ZONE · ENTER = SICHERER FOLGEGRIFF · KEIN ZEITLIMIT",
				HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 24, 12, Color8(156, 174, 167))


	func _draw_feedback_flash() -> void:
		if _action_flash <= 0.0 or _last_action.is_empty():
			return
		var zone := _zone_rect(_last_action)
		var color := Color(0.24, 1.0, 0.57, _action_flash * 0.24) if _last_ok \
			else Color(1.0, 0.18, 0.10, _action_flash * 0.32)
		draw_rect(zone, color, true)
		_draw_brackets(zone, color.lightened(0.25), 4.0)
