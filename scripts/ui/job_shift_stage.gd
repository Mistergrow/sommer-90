class_name JobShiftStage
extends Control
## Code-native AGA-Buehne fuer spielbare Arbeitsschichten. Die vier Modi teilen
## sich nur HUD, Zeitvertrag und Feedback; ihre Eingaben bleiben bewusst
## verschieden. Die Buehne verbucht weder Zeit noch Geld.

signal choice_selected(index: int)
signal hud_changed(seconds_left: int, phase_label: String)

const AgaSprites := preload("res://scripts/gfx/aga_sprite_catalog.gd")

const INK := Color("071018")
const PANEL := Color("0b1722")
const PANEL_2 := Color("101d2b")
const CYAN := Color("31d8ff")
const GREEN := Color("51f28a")
const AMBER := Color("ffb52e")
const MAGENTA := Color("ff4f9a")
const RED := Color("ff5d62")
const PAPER := Color("e9e2c8")
const ROUTE_BG: Texture2D = preload("res://assets/ui/minigames/job_shift/job_route_aga_v01.png")
const FLYER_BG: Texture2D = preload("res://assets/ui/minigames/job_shift/job_flyer_aga_v01.png")
const STOCKROOM_BG: Texture2D = preload("res://assets/ui/minigames/job_shift/job_stockroom_aga_v01.png")
const REPAIR_BG: Texture2D = preload("res://assets/ui/minigames/job_shift/job_repair_aga_v01.png")
const CODE_BG: Texture2D = preload("res://assets/ui/minigames/job_shift/job_code_aga_v01.png")

var mode := "sort"
var prompt: Dictionary = {}
var round_index := 0
var total_rounds := 1
var choice_rects: Array[Rect2] = []
var route_lane := 1
var last_performance := 1.0

var _time_left := 0.0
var _round_time := 14.0
var _last_second := -1
var _phase := "BEREIT"
var _resolved := false
var _finished := false
var _passed := false
var _finish_text := ""

var _hover := -1
var _selected := -1
var _dragging := false
var _drag_pos := Vector2.ZERO
var _route_depth := 0.0
var _belt_progress := 0.08
var _meter_phase := 0.0
var _scan_phase := 0.0

var _flash_time := 0.0
var _flash_good := false
var _flash_index := -1
var _impact_time := 0.0
var _impact_origin := Vector2.ZERO
var _route_window_cued := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	queue_redraw()


func set_state(next_mode: String, next_prompt: Dictionary, next_round: int, next_total: int) -> void:
	mode = next_mode
	prompt = next_prompt.duplicate(true)
	round_index = next_round
	total_rounds = maxi(1, next_total)
	_finished = false
	_resolved = false
	_selected = -1
	_dragging = false
	_hover = -1
	_route_depth = 0.0
	_route_window_cued = false
	_belt_progress = 0.08
	_meter_phase = 0.0
	_scan_phase = 0.0
	last_performance = 1.0
	_round_time = _duration_for_mode()
	_time_left = _round_time
	_phase = _initial_phase()
	_layout_choices()
	_emit_hud(true)
	queue_redraw()


func feedback(good: bool, selected_index: int, expected_index: int) -> void:
	_flash_good = good
	_flash_index = selected_index if good else expected_index
	_flash_time = 0.72
	_impact_time = 0.55
	_impact_origin = _choice_center(selected_index)
	queue_redraw()


func finish(passed: bool, message: String) -> void:
	_finished = true
	_passed = passed
	_finish_text = message
	_phase = "accepted" if passed else "rejected"
	_emit_hud(true)
	queue_redraw()


func _process(delta: float) -> void:
	_flash_time = maxf(0.0, _flash_time - delta)
	_impact_time = maxf(0.0, _impact_time - delta)
	if _finished or _resolved or prompt.is_empty():
		if _flash_time > 0.0 or _impact_time > 0.0:
			queue_redraw()
		return
	_time_left = maxf(0.0, _time_left - delta)
	match mode:
		"route":
			_route_depth = fmod(_route_depth + delta * lerpf(0.19, 0.26, _round_pressure()), 1.0)
			var route_window := _route_window()
			_phase = "approach" if _route_depth < route_window.x else ("delivery_window" if _route_depth < route_window.y else "past")
			if _route_depth >= route_window.x and not _route_window_cued:
				_route_window_cued = true
				_cue(&"hint")
		"sort":
			if not _dragging:
				_belt_progress = minf(1.0, _belt_progress + delta * lerpf(0.085, 0.145, _round_pressure()))
			_phase = "grab_box" if not _dragging else "drag_to_bay"
		"repair":
			_meter_phase = fmod(_meter_phase + delta * 0.72, 1.0)
			_phase = "choose_tool" if _selected < 0 else "lock_meter"
		"code":
			_scan_phase = fmod(_scan_phase + delta * 0.34, 1.0)
			_phase = "grab_patch" if not _dragging else "drag_to_code"
	if _time_left <= 0.0:
		_resolve_timeout()
	_emit_hud(false)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _finished or _resolved:
		return
	if event is InputEventMouseMotion:
		_drag_pos = event.position
		_hover = _choice_at(event.position)
		if mode == "route":
			var aimed_lane := _route_lane_at(event.position)
			if aimed_lane >= 0:
				route_lane = aimed_lane
		queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_press(event.position)
		else:
			_mouse_release(event.position)
		accept_event()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_keyboard_input(event)
		accept_event()


func _mouse_press(at: Vector2) -> void:
	_drag_pos = at
	match mode:
		"route":
			var lane := _route_lane_at(at)
			if lane >= 0:
				route_lane = lane
				_deliver_route()
		"sort":
			if _parcel_rect().has_point(at):
				_dragging = true
				_cue(&"focus")
		"repair":
			var tool := _choice_at(at)
			if tool >= 0:
				_selected = tool
				_phase = "lock_meter"
				_cue(&"focus")
			elif _selected >= 0 and _meter_rect().has_point(at):
				_lock_meter()
		"code":
			var card := _choice_at(at)
			if card >= 0:
				_selected = card
				_dragging = true
				_cue(&"focus")


func _mouse_release(at: Vector2) -> void:
	if mode == "sort" and _dragging:
		_dragging = false
		var target := _choice_at(at)
		if target >= 0:
			_resolve(target, clampf(1.0 - _belt_progress * 0.45, 0.5, 1.0))
	elif mode == "code" and _dragging:
		_dragging = false
		if _code_target_rect().has_point(at):
			_resolve(_selected, 0.55 + 0.45 * _time_ratio())
	queue_redraw()


func _keyboard_input(event: InputEventKey) -> void:
	if mode == "route":
		if event.keycode in [KEY_LEFT, KEY_A]:
			route_lane = maxi(0, route_lane - 1)
		elif event.keycode in [KEY_RIGHT, KEY_D]:
			route_lane = mini(3, route_lane + 1)
		elif event.keycode in [KEY_SPACE, KEY_ENTER]:
			_deliver_route()
	elif mode == "sort":
		var idx := _number_index(event)
		if idx >= 0:
			_resolve(idx, clampf(1.0 - _belt_progress * 0.45, 0.5, 1.0))
	elif mode == "repair":
		var idx := _number_index(event)
		if idx >= 0:
			_selected = idx
			_cue(&"focus")
		elif event.keycode in [KEY_SPACE, KEY_ENTER] and _selected >= 0:
			_lock_meter()
	elif mode == "code":
		var idx := _number_index(event)
		if idx >= 0:
			_selected = idx
			_cue(&"focus")
		elif event.keycode == KEY_ENTER and _selected >= 0:
			_resolve(_selected, 0.55 + 0.45 * _time_ratio())
	queue_redraw()


func _number_index(event: InputEventKey) -> int:
	var idx := -1
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		idx = int(event.keycode - KEY_1)
	elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
		idx = int(event.keycode - KEY_KP_1)
	return idx if idx < choice_rects.size() else -1


func _deliver_route() -> void:
	var window := _route_window()
	var in_window := _route_depth >= window.x and _route_depth <= window.y
	var chosen := route_lane
	if not in_window and chosen == int(prompt.get("correct", -1)):
		chosen = (chosen + 1) % maxi(1, choice_rects.size())
	var window_centre := (window.x + window.y) * 0.5
	var window_half := maxf(0.001, (window.y - window.x) * 0.5)
	var precision := clampf(1.0 - absf(_route_depth - window_centre) / window_half, 0.0, 1.0)
	_resolve(chosen, 0.58 + precision * 0.42 if in_window else 0.0)


func _lock_meter() -> void:
	var window := _meter_window()
	var meter_value := _meter_value()
	var calibration_ok := meter_value >= window.x and meter_value <= window.y
	var chosen := _selected
	if not calibration_ok and chosen == int(prompt.get("correct", -1)):
		chosen = (chosen + 1) % maxi(1, choice_rects.size())
	var precision := clampf(1.0 - absf(meter_value - 0.525) / maxf(0.001, (window.y - window.x) * 0.5), 0.0, 1.0)
	_resolve(chosen, 0.6 + precision * 0.4 if calibration_ok else 0.0)


func _resolve_timeout() -> void:
	var correct := int(prompt.get("correct", 0))
	var wrong := (correct + 1) % maxi(1, choice_rects.size())
	_resolve(wrong, 0.0)


func _resolve(index: int, performance: float = 1.0) -> void:
	if _resolved or index < 0 or index >= choice_rects.size():
		return
	_resolved = true
	_selected = index
	last_performance = clampf(performance, 0.0, 1.0)
	choice_selected.emit(index)


func _duration_for_mode() -> float:
	var base := 14.0
	match mode:
		"route": base = 11.0
		"sort": base = 14.0
		"repair": base = 16.0
		"code": base = 18.0
	# Eine Schicht beginnt lesbar und endet merklich anspruchsvoller. Der Faktor
	# bleibt moderat, damit die Eingabemechanik und nicht hektisches Raten gewinnt.
	return base * lerpf(1.0, 0.78, _round_pressure())


func _round_pressure() -> float:
	return clampf(float(round_index) / maxf(1.0, float(total_rounds - 1)), 0.0, 1.0)


func _time_ratio() -> float:
	return clampf(_time_left / maxf(0.01, _round_time), 0.0, 1.0)


func _route_window() -> Vector2:
	var half_width := lerpf(0.17, 0.115, _round_pressure())
	return Vector2(0.69 - half_width, 0.69 + half_width)


func _meter_window() -> Vector2:
	var half_width := lerpf(0.095, 0.055, _round_pressure())
	return Vector2(0.525 - half_width, 0.525 + half_width)


func _initial_phase() -> String:
	match mode:
		"route": return "approach"
		"sort": return "grab_box"
		"repair": return "choose_tool"
		"code": return "grab_patch"
	return "ready"


func _emit_hud(force: bool) -> void:
	var second := ceili(_time_left)
	if force or second != _last_second:
		_last_second = second
		hud_changed.emit(second, _phase_label())


func _phase_label() -> String:
	return Loc.t("ui.job_shift_stage.phase.%s" % _phase,
		_phase.replace("_", " ").to_upper())


func _layout_choices() -> void:
	choice_rects.clear()
	var count := (prompt.get("choices", []) as Array).size()
	if count <= 0:
		return
	match mode:
		"route":
			var road := _road_rect()
			var lane_w := road.size.x / 4.0
			for i in count:
				choice_rects.append(Rect2(road.position.x + lane_w * i, road.end.y - 68.0, lane_w, 64.0))
		"sort":
			var gap := 8.0
			var x := 28.0
			var w := (size.x - 56.0 - gap * float(count - 1)) / float(count)
			for i in count:
				choice_rects.append(Rect2(x + (w + gap) * i, 390.0, w, 104.0))
		"repair":
			# Pro Fall werden nur drei plausible Werkzeuge angeboten. Ihre IDs
			# bestimmen den realen Platz auf der Bildplatte, nicht die zufaellige
			# Antwortposition. Dadurch bleibt die Werkbank raeumlich erlernbar.
			var choice_ids: Array = prompt.get("choice_ids", prompt.get("choices", []))
			for i in count:
				var tool_id := str(choice_ids[i]) if i < choice_ids.size() else ""
				choice_rects.append(_repair_hotspot(tool_id))
		_:
			var cols := 4
			var rows := ceili(float(count) / float(cols))
			var gap := 8.0
			var w := (size.x - 56.0 - gap * float(cols - 1)) / float(cols)
			var h := 58.0 if rows > 1 else 72.0
			var top := size.y - float(rows) * h - float(rows - 1) * gap - 18.0
			for i in count:
				choice_rects.append(Rect2(28.0 + float(i % cols) * (w + gap),
					top + float(floori(float(i) / float(cols))) * (h + gap), w, h))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_choices()
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	_draw_scene_backdrop()
	_draw_copper_backdrop()
	_draw_header()
	match mode:
		"route": _draw_route()
		"sort": _draw_sort()
		"repair": _draw_repair()
		"code": _draw_code()
	if _impact_time > 0.0:
		var radius := (0.55 - _impact_time) * 95.0 + 12.0
		draw_arc(_impact_origin, radius, 0.0, TAU, 32, GREEN if _flash_good else RED, 2.0)
	if _finished:
		_draw_finish_overlay()


func _draw_scene_backdrop() -> void:
	var texture: Texture2D = STOCKROOM_BG
	match mode:
		"route": texture = FLYER_BG if _is_flyer_route() else ROUTE_BG
		"repair": texture = REPAIR_BG
		"code": texture = CODE_BG
	draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
	# Die Bildplatte traegt den Ort; dieser leichte Firnis bindet sie an die
	# dunkelblaue Fensterwelt und schafft Kontrast fuer dynamische Sprites.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.05, 0.2))


func _draw_copper_backdrop() -> void:
	for y in range(0, int(size.y), 4):
		var pulse := 0.5 + 0.5 * sin(float(y) * 0.055 + _scan_phase * TAU)
		var c := Color(0.02 + pulse * 0.015, 0.055, 0.085 + pulse * 0.035, 0.18)
		draw_rect(Rect2(0, y, size.x, 2), c)
	for x in range(0, int(size.x), 64):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.1, 0.42, 0.58, 0.11), 1.0)


func _draw_header() -> void:
	var bar := Rect2(18, 12, size.x - 36.0, 68)
	_panel(bar, PANEL_2, CYAN, 1.0)
	_text(Vector2(34, 38), str(prompt.get("signal",
		Loc.t("ui.job_shift_stage.assignment", "ARBEITSAUFTRAG"))), PAPER, 19)
	_text(Vector2(34, 62), Loc.t("ui.job_shift_stage.process",
		"VORGANG %02d/%02d · %s") % [round_index + 1, total_rounds, _phase_label()], CYAN, 11)
	_text(Vector2(size.x - 386, 38), Loc.t("ui.job_shift_stage.pressure",
		"TAKT %d/3") % mini(3, 1 + floori(_round_pressure() * 3.0)), MAGENTA, 11)
	var time_ratio := clampf(_time_left / maxf(0.01, _round_time), 0.0, 1.0)
	var timer := Rect2(size.x - 244, 48, 192, 12)
	draw_rect(timer, Color("03080d"))
	draw_rect(Rect2(timer.position, Vector2(timer.size.x * time_ratio, timer.size.y)), GREEN if time_ratio > 0.33 else RED)
	_text(Vector2(size.x - 244, 38), Loc.t("ui.job_shift_stage.seconds",
		"%02d SEK") % ceili(_time_left), AMBER, 14)


func _draw_route() -> void:
	var road := _road_rect()
	draw_rect(road, Color(0.02, 0.05, 0.1, 0.08))
	draw_rect(road, CYAN.darkened(0.6), false, 2.0)
	var horizon_y := road.position.y + 98.0
	for lane in range(1, 4):
		var far_x := road.position.x + road.size.x * (0.44 + float(lane) * 0.03)
		var near_x := road.position.x + road.size.x * float(lane) / 4.0
		draw_line(Vector2(far_x, horizon_y), Vector2(near_x, road.end.y), Color(0.75, 0.82, 0.9, 0.42), 2.0)
	# Wurffenster wird als horizontales Zielband lesbar.
	var route_window := _route_window()
	var zone_y_top := lerpf(horizon_y, road.end.y - 25.0, route_window.x)
	var zone_y_bottom := lerpf(horizon_y, road.end.y - 25.0, route_window.y)
	draw_rect(Rect2(road.position.x + 4, zone_y_top, road.size.x - 8, zone_y_bottom - zone_y_top), Color(0.1, 0.82, 1.0, 0.12))
	draw_line(Vector2(road.position.x, zone_y_top), Vector2(road.end.x, zone_y_top), CYAN, 2.0)
	draw_line(Vector2(road.position.x, zone_y_bottom), Vector2(road.end.x, zone_y_bottom), CYAN, 2.0)
	# Ziele kommen aus der Tiefe auf den Fahrer zu. Die alte Richtung war
	# spiegelverkehrt und liess Briefkaesten zum Horizont rueckwaerts fahren.
	var depth_y := _route_target_y(_route_depth)
	var perspective := _route_perspective(_route_depth)
	var lane_w := road.size.x / 4.0
	var target_lane := clampi(int(prompt.get("correct", 0)), 0, 3)
	var centre_x := road.position.x + lane_w * (float(target_lane) + 0.5)
	centre_x = lerpf(road.position.x + road.size.x * 0.5, centre_x, perspective)
	if _is_flyer_route():
		_draw_flyer_target(Vector2(centre_x, depth_y), perspective)
	else:
		_draw_mailbox(Vector2(centre_x, depth_y), perspective, true)
	# Der Fahrer ist Teil der Bildplatte; gesteuert wird der sichtbare Wurfkegel.
	# So gibt es keinen zweiten, schwebenden Fahrrad-Sprite vor der Szene.
	var throw_x := road.position.x + lane_w * (float(route_lane) + 0.5)
	var throw_origin := Vector2(road.get_center().x, road.end.y - 42.0)
	draw_dashed_line(throw_origin, Vector2(throw_x, road.end.y - 112.0), CYAN, 3.0, 9.0)
	_draw_delivery_item(Vector2(throw_x, road.end.y - 116.0), route_lane == target_lane)
	for i in choice_rects.size():
		var active := i == route_lane
		# Die richtige Spur wird nicht als Antwort gruen markiert. Der Spieler
		# liest Ziel und Perspektive; Cyan signalisiert nur das Wurffenster.
		_choice_card(i, choice_rects[i], active, false)


func _draw_sort() -> void:
	var belt := Rect2(28, 120, size.x - 56, 218)
	draw_rect(belt, Color(0.02, 0.04, 0.07, 0.06))
	draw_rect(belt, CYAN.darkened(0.58), false, 2.0)
	var parcel := _parcel_rect()
	if _dragging:
		_draw_parcel(parcel, true)
	else:
		# Das reale Paket liegt bereits auf der Bildplatte; nur sein maschinen-
		# lesbares Auftragslabel und die Greifkante sind dynamisch.
		draw_rect(parcel, AMBER, false, 3.0)
		_text(parcel.position + Vector2(10, 24), str(prompt.get("signal", "WARE")), PAPER, 11)
	_text(Vector2(belt.position.x + 18, belt.position.y + 30), Loc.t("ui.job_shift_stage.conveyor",
		"LAUFENDES BAND · %s") % _phase_label(), CYAN, 13)
	for i in choice_rects.size():
		_choice_card(i, choice_rects[i], i == _hover, false)


func _draw_repair() -> void:
	var case_panel := Rect2(180, 88, size.x - 360.0, 122)
	_panel(case_panel, Color(0.015, 0.045, 0.065, 0.94), CYAN.darkened(0.35), 2.0)
	_text(case_panel.position + Vector2(16, 24), Loc.t("ui.job_shift_stage.customer_fault",
		"KUNDENFEHLER · BEOBACHTUNG"), AMBER, 12)
	_text(case_panel.position + Vector2(16, 50), str(prompt.get("clue", "")), PAPER, 12)
	_text(case_panel.position + Vector2(16, 78), Loc.t("ui.job_shift_stage.safe_next_step",
		"SICHERER NAECHSTER SCHRITT"), CYAN, 10)
	_text(case_panel.position + Vector2(16, 103), str(prompt.get("procedure", "")), GREEN, 11)

	var meter := _meter_rect()
	_panel(meter, Color(0.02, 0.05, 0.08, 0.82), Color("73828c"), 2.0)
	var selected_name := _selected_tool_name()
	_text(meter.position + Vector2(18, 26), Loc.t("ui.job_shift_stage.application",
		"ANWENDUNG · %s") % (selected_name if not selected_name.is_empty() else
		Loc.t("ui.job_shift_stage.no_tool_selected", "NOCH KEIN WERKZEUG")), AMBER, 12)
	var track := Rect2(meter.position + Vector2(22, 74), Vector2(meter.size.x - 44, 26))
	draw_rect(track, Color("03070a"))
	var meter_window := _meter_window()
	draw_rect(Rect2(track.position.x + track.size.x * meter_window.x, track.position.y,
		track.size.x * (meter_window.y - meter_window.x), track.size.y), Color(0.15, 0.9, 0.4, 0.34))
	var px := track.position.x + track.size.x * _meter_value()
	draw_line(Vector2(px, track.position.y - 14), Vector2(px, track.end.y + 14), CYAN, 4.0)
	_text(meter.position + Vector2(22, 54), str(prompt.get("gauge",
		Loc.t("ui.job_shift_stage.control_value", "KONTROLLWERT"))), CYAN, 10)
	var help := _selected_tool_help()
	_text(meter.position + Vector2(22, 126), help if not help.is_empty() else
		Loc.t("ui.job_shift_stage.choose_one_of_three", "1 · Eines der drei markierten Werkzeuge waehlen."),
		PAPER.darkened(0.16), 10)
	_text(meter.position + Vector2(22, 146),
		Loc.t("ui.job_shift_stage.confirm_application", "2 · Im gruenen Bereich mit Klick/Leertaste bestaetigen."),
		GREEN if _selected >= 0 else PAPER.darkened(0.38), 10)
	for i in choice_rects.size():
		_choice_card(i, choice_rects[i], i == _selected or i == _hover, false)


func _draw_code() -> void:
	var editor := Rect2(size.x * 0.292, 84, size.x * 0.39, 238)
	_panel(editor, Color(0.01, 0.035, 0.06, 0.88), CYAN.darkened(0.45), 2.0)
	_text(editor.position + Vector2(18, 26), Loc.t("ui.job_shift_stage.error_trace",
		"BUILD://NIGHT/%02d · FEHLERSPUR") % (round_index + 1), GREEN, 12)
	var lines := ["func process_frame(delta):", "    var next = queue[index]", "    # PATCH SLOT", "    render(next)", "    return STATUS_OK"]
	for i in lines.size():
		var y := editor.position.y + 62.0 + float(i) * 35.0
		if i == 2:
			draw_rect(Rect2(editor.position.x + 14, y - 22, editor.size.x - 28, 30), Color(0.15, 0.65, 0.9, 0.16))
		_text(Vector2(editor.position.x + 24, y), "%02d  %s" % [i + 1, lines[i]], CYAN if i == 2 else PAPER.darkened(0.25), 13)
	var scan_y := editor.position.y + 42.0 + (editor.size.y - 54.0) * _scan_phase
	draw_line(Vector2(editor.position.x + 4, scan_y), Vector2(editor.end.x - 4, scan_y), Color(0.2, 1.0, 0.7, 0.25), 2.0)
	var target := _code_target_rect()
	draw_rect(target, Color(0.1, 0.75, 0.95, 0.12))
	draw_rect(target, CYAN, false, 2.0)
	if _dragging and _selected >= 0:
		_draw_patch_card(Rect2(_drag_pos - Vector2(92, 24), Vector2(184, 48)), _selected, true)
	for i in choice_rects.size():
		_choice_card(i, choice_rects[i], i == _selected or i == _hover, false)


func _choice_card(index: int, rect: Rect2, active: bool, target: bool) -> void:
	var color := CYAN if active else Color("536272")
	if target:
		color = GREEN
	if _flash_time > 0.0 and index == _flash_index:
		color = GREEN if _flash_good else RED
	var fill := Color(0.07, 0.11, 0.16, 0.9) if active else Color(0.025, 0.045, 0.075, 0.78)
	if mode == "repair":
		fill.a = 0.16 if active else 0.04
		_panel(rect.grow(-2), fill, color, 3.0 if active else 1.0)
		var tag := Rect2(rect.position.x + 2, rect.end.y - 30, rect.size.x - 4, 28)
		draw_rect(tag, Color(0.015, 0.035, 0.055, 0.94))
		draw_rect(tag, color, false, 1.0)
		var repair_choices: Array = prompt.get("choices", [])
		var repair_value := str(repair_choices[index]) if index < repair_choices.size() else "?"
		_text(tag.position + Vector2(7, 19), "%d · %s" % [index + 1, repair_value], PAPER, 10)
		return
	_panel(rect.grow(-2), fill, color, 2.0 if active else 1.0)
	var choices: Array = prompt.get("choices", [])
	var value := str(choices[index]) if index < choices.size() else "?"
	_text(Vector2(rect.position.x + 10, rect.position.y + rect.size.y * 0.58), "%d · %s" % [index + 1, value], PAPER, 11 if value.length() > 16 else 13)


func _draw_parcel(rect: Rect2, lifted: bool) -> void:
	AgaSprites.draw_frame(self, "job_shift_props.parcel", rect.get_center(),
		rect.size * (1.04 if lifted else 0.96))
	draw_rect(rect, GREEN if lifted else AMBER, false, 3.0 if lifted else 2.0)
	var label_rect := Rect2(rect.position + Vector2(13, rect.size.y - 31),
		Vector2(rect.size.x - 26, 24))
	draw_rect(label_rect, Color(0.94, 0.89, 0.72, 0.9))
	_text(label_rect.position + Vector2(6, 17), str(prompt.get("signal", "WARE")), INK, 10)


func _draw_patch_card(rect: Rect2, index: int, active: bool) -> void:
	AgaSprites.draw_frame(self, "job_shift_props.patch_cards", rect.get_center(),
		rect.size * 0.9, Color(1, 1, 1, 0.9))
	_panel(rect, Color(0.03, 0.08, 0.12, 0.35), GREEN if active else CYAN, 2.0)
	var choices: Array = prompt.get("choices", [])
	var value := str(choices[index]) if index >= 0 and index < choices.size() else "PATCH"
	_text(rect.position + Vector2(10, rect.size.y * 0.62), value, PAPER, 11)


func _draw_mailbox(at: Vector2, scale_factor: float, target: bool) -> void:
	var sprite_rect := AgaSprites.draw_frame(self, "job_shift_props.mailbox", at,
		Vector2(78, 112) * scale_factor)
	draw_rect(sprite_rect.grow(2.0), GREEN if target else PAPER.darkened(0.35),
		false, maxf(1.0, 3.0 * scale_factor))


func _draw_delivery_item(at: Vector2, aligned: bool) -> void:
	draw_set_transform(at, sin(_scan_phase * TAU) * 0.12, Vector2.ONE)
	var frame_id := "job_shift_props.flyer" if _is_flyer_route() else "job_shift_props.newspaper"
	var sprite_rect := AgaSprites.draw_frame(self, frame_id, Vector2.ZERO, Vector2(48, 38))
	draw_rect(sprite_rect, GREEN if aligned else CYAN, false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_flyer_target(at: Vector2, scale_factor: float) -> void:
	var sprite_rect := AgaSprites.draw_frame(self, "job_shift_props.flyer", at,
		Vector2(68, 58) * scale_factor)
	draw_rect(sprite_rect.grow(2.0), MAGENTA, false, maxf(1.0, 3.0 * scale_factor))


func _is_flyer_route() -> bool:
	return str(prompt.get("job_id", "")) == "job_club_flyer"


func _draw_finish_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.04, 0.82))
	var box := Rect2(size.x * 0.22, size.y * 0.34, size.x * 0.56, 150)
	_panel(box, Color("08121c"), GREEN if _passed else RED, 3.0)
	_text(box.position + Vector2(24, 54), _finish_text, GREEN if _passed else RED, 24)
	_text(box.position + Vector2(24, 92), Loc.t("ui.job_shift_stage.log_closed",
		"SCHICHTPROTOKOLL GESCHLOSSEN"), PAPER.darkened(0.2), 12)


func _road_rect() -> Rect2:
	return Rect2(28, 92, size.x - 56, size.y - 112)


func _route_target_y(depth: float) -> float:
	## Ein wachsender Tiefenwert bedeutet bewusst ANNAEHERUNG: Das Ziel beginnt
	## am Horizont und wandert zum unteren Bildrand. Diese kleine Funktion ist
	## Teil des Interaktionsvertrags und wird gegen die alte Rueckwaertsbewegung
	## getestet.
	var road := _road_rect()
	var horizon_y := road.position.y + 98.0
	return lerpf(horizon_y + 10.0, road.end.y - 34.0, clampf(depth, 0.0, 1.0))


func _route_perspective(depth: float) -> float:
	## Gleichzeitig wird das Ziel groesser; nur Positionsbewegung ohne Wachstum
	## las sich zuvor wie ein schwebendes UI-Element statt wie eine Route.
	return lerpf(0.28, 1.0, clampf(depth, 0.0, 1.0))


func _parcel_rect() -> Rect2:
	if _dragging:
		return Rect2(_drag_pos - Vector2(92, 48), Vector2(184, 96))
	var belt := Rect2(28, 120, size.x - 56, 218)
	return Rect2(belt.position.x + 18.0 + (belt.size.x - 220.0) * _belt_progress,
		belt.position.y + 82.0, 184, 96)


func _meter_rect() -> Rect2:
	return Rect2(size.x * 0.335, 218, size.x * 0.33, 164)


func _repair_hotspot(tool_id: String) -> Rect2:
	match tool_id:
		"MULTIMETER": return Rect2(18, 226, 148, 130)
		"LOETSTATION": return Rect2(122, 392, 174, 132)
		"ISOPROPANOL": return Rect2(18, 402, 100, 122)
		"IC-ZIEHER": return Rect2(334, 402, 100, 122)
		"STROMLIMIT": return Rect2(706, 226, 220, 142)
		"DURCHGANG": return Rect2(440, 402, 112, 122)
		"KAELTESPRAY": return Rect2(570, 398, 110, 126)
		"SCHALTPLAN": return Rect2(690, 398, 244, 126)
	return Rect2(28, size.y - 94, 150, 74)


func _selected_tool_name() -> String:
	if _selected < 0:
		return ""
	var choices: Array = prompt.get("choices", [])
	return str(choices[_selected]) if _selected < choices.size() else ""


func _selected_tool_help() -> String:
	if _selected < 0:
		return ""
	var help: Array = prompt.get("tool_help", [])
	return str(help[_selected]) if _selected < help.size() else ""


func _meter_value() -> float:
	return 0.5 + sin(_meter_phase * TAU) * 0.48


func _code_target_rect() -> Rect2:
	return Rect2(size.x * 0.32, 198, size.x * 0.33, 38)


func _route_lane_at(at: Vector2) -> int:
	var road := _road_rect()
	if not road.has_point(at):
		return -1
	return clampi(int((at.x - road.position.x) / (road.size.x / 4.0)), 0, 3)


func _choice_at(at: Vector2) -> int:
	for i in choice_rects.size():
		if choice_rects[i].has_point(at):
			return i
	return -1


func _choice_center(index: int) -> Vector2:
	if index >= 0 and index < choice_rects.size():
		return choice_rects[index].get_center()
	return size * 0.5


func _panel(rect: Rect2, fill: Color, border: Color, width: float = 1.0) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, width)


func _cue(event: StringName) -> void:
	# Die Zeichen-/Interaktionsbuehne bleibt auch in Preview- und Unit-Szenen
	# autark. Im laufenden Spiel liefert der zentrale AudioManager das Foley.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio_manager := tree.root.get_node_or_null("AudioManager")
	if audio_manager != null and audio_manager.has_method("minigame_cue"):
		audio_manager.call("minigame_cue", "job_shift", event)


func _text(at: Vector2, value: String, color: Color, font_size: int) -> void:
	draw_string(get_theme_default_font(), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
