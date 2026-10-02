extends Control
## Animierte, jahresgenaue Servicebench der Ladendiagnose.
##
## Das Brett zeigt kein generisches Hintergrundbild mehr: Plattform, Messpunkte,
## Leitungen, Evidenz-LEDs und Instrumentenwert lesen alle denselben Modellstand.

signal test_requested(test: StringName)

const Model := preload("res://scripts/minigames/shop_diagnosis_model.gd")
const UI_FONT := preload("res://assets/fonts/VT323_UI.ttf")
const PLATFORM_ART := {
	&"amiga_500": preload("res://assets/ui/minigames/HARDWARE_SERVICE_A500_OPEN_V02.png"),
	&"amiga_600": preload("res://assets/ui/minigames/HARDWARE_SERVICE_A600_OPEN_V02.png"),
	&"amiga_1200": preload("res://assets/ui/minigames/HARDWARE_SERVICE_A1200_OPEN_V02.png"),
}
const PROBES := {
	&"visual": Vector2(0.18, 0.25),
	&"voltage": Vector2(0.35, 0.64),
	&"signal": Vector2(0.73, 0.34),
	&"memory": Vector2(0.49, 0.39),
	&"disk": Vector2(0.68, 0.61),
	&"known_good": Vector2(0.84, 0.72),
}

var model: ShopDiagnosisModel
var last_test: StringName = &""
var reading := "PROBES READY"
var state_color := Color8(100, 220, 155)
var _pulse := 0.0
var _phase := 0.0
var _hover: StringName = &""
var _solved := false
var _art_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_process(true)


func show_reading(test: StringName, value: String, positive: bool,
		ambiguous: bool) -> void:
	last_test = test
	reading = value
	state_color = Color8(245, 91, 70) if positive \
		else (Color8(245, 190, 70) if ambiguous else Color8(92, 225, 155))
	_pulse = 1.0
	queue_redraw()


func show_solved() -> void:
	_solved = true
	state_color = Color8(92, 244, 155)
	_pulse = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	var bounded_delta := minf(maxf(delta, 0.0), 1.0 / 20.0)
	if not bool(SettingsManager.value("reduced_motion")):
		_phase = fmod(_phase + bounded_delta, TAU)
	_pulse = maxf(0.0, _pulse - bounded_delta * 1.8)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if model == null:
		return
	if event is InputEventMouseMotion:
		_hover = _test_at(event.position)
		tooltip_text = str(Model.TEST_LABELS.get(_hover, ""))
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		var selected := _test_at(event.position)
		if not selected.is_empty():
			test_requested.emit(selected)
			accept_event()
	elif event is InputEventKey and event.pressed:
		var index := _key_index(event.keycode)
		if index >= 0 and index < Model.TESTS.size():
			test_requested.emit(Model.TESTS[index])
			accept_event()


func _key_index(keycode: Key) -> int:
	if keycode >= KEY_1 and keycode <= KEY_6:
		return int(keycode - KEY_1)
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_6:
		return int(keycode - KEY_KP_1)
	return -1


func _test_at(point: Vector2) -> StringName:
	var best: StringName = &""
	var best_distance := maxf(26.0, _art_rect.size.y * 0.075)
	for test: StringName in PROBES:
		var probe := _probe_point(test)
		var distance := point.distance_to(probe)
		if distance < best_distance:
			best_distance = distance
			best = test
	return best


func _probe_point(test: StringName) -> Vector2:
	var normalized: Vector2 = PROBES[test]
	return _art_rect.position + normalized * _art_rect.size


func _draw() -> void:
	if model == null or size.x < 16.0 or size.y < 16.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color8(25, 19, 15), true)
	draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), Color8(91, 66, 43), false, 2)
	var art: Texture2D = PLATFORM_ART.get(model.platform, PLATFORM_ART[&"amiga_1200"])
	_art_rect = _contain_rect(art.get_size(), Rect2(8, 42, size.x - 16, size.y - 112))
	draw_texture_rect(art, _art_rect, false)
	draw_rect(_art_rect, Color(0.01, 0.025, 0.02, 0.10), true)
	_draw_header()
	_draw_probe_lead()
	_draw_probes()
	_draw_meter()
	_draw_evidence_rail()


func _contain_rect(source_size: Vector2, bounds: Rect2) -> Rect2:
	var factor := minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
	var target := source_size * factor
	return Rect2(bounds.get_center() - target * 0.5, target)


func _draw_header() -> void:
	var header := Rect2(8, 8, size.x - 16, 29)
	draw_rect(header, Color(0.01, 0.025, 0.022, 0.94), true)
	draw_rect(header, Color8(87, 136, 116), false, 1)
	draw_string(UI_FONT, header.position + Vector2(9, 20),
		"FALL %03d // %d // %s" % [
			model.case_number, model.configured_year, model.device_label()],
		HORIZONTAL_ALIGNMENT_LEFT, header.size.x - 128, 14, Color8(235, 223, 184))
	var status := "BEFUND OK" if _solved else "MESSPLATZ AKTIV"
	draw_string(UI_FONT, header.position + Vector2(header.size.x - 118, 20), status,
		HORIZONTAL_ALIGNMENT_RIGHT, 108, 14,
		Color8(92, 244, 155) if _solved else Color8(243, 183, 56))


func _draw_probe_lead() -> void:
	if last_test.is_empty():
		return
	var start := Vector2(_art_rect.position.x + _art_rect.size.x * 0.13,
		_art_rect.end.y - 4)
	var target := _probe_point(last_test)
	var control_a := start + Vector2(_art_rect.size.x * 0.18, -28)
	var control_b := target + Vector2(-_art_rect.size.x * 0.13, 34)
	var points := PackedVector2Array()
	for index in 25:
		var t := float(index) / 24.0
		var inverse := 1.0 - t
		points.append(inverse * inverse * inverse * start
			+ 3.0 * inverse * inverse * t * control_a
			+ 3.0 * inverse * t * t * control_b
			+ t * t * t * target)
	draw_polyline(points, Color(0.02, 0.02, 0.018, 0.88), 6.0, true)
	draw_polyline(points, state_color.darkened(0.32), 2.2, true)


func _draw_probes() -> void:
	for index in Model.TESTS.size():
		var test: StringName = Model.TESTS[index]
		var point := _probe_point(test)
		var state := StringName(model.result_states.get(test, &""))
		var color := Color8(77, 154, 139)
		if state == &"positive":
			color = Color8(245, 91, 70)
		elif state == &"ambiguous":
			color = Color8(245, 190, 70)
		elif state == &"reference":
			color = Color8(92, 225, 155)
		var active := test == last_test
		var radius := 11.0 + (_pulse * 6.0 if active else 0.0)
		if test == _hover:
			radius += 3.0
		draw_circle(point, radius, Color(0.01, 0.025, 0.022, 0.82), true)
		draw_circle(point, radius, color, false, 2.5)
		draw_circle(point, 3.0, color, true)
		var label_rect := Rect2(point + Vector2(13, -9), Vector2(104, 18))
		draw_rect(label_rect, Color(0.01, 0.02, 0.018, 0.72), true)
		draw_string(UI_FONT, label_rect.position + Vector2(4, 13),
			"%d %s" % [index + 1, Model.TEST_LABELS[test]],
			HORIZONTAL_ALIGNMENT_LEFT, label_rect.size.x - 6, 11, Color8(235, 242, 226))


func _draw_meter() -> void:
	var meter := Rect2(18, size.y - 64, size.x - 36, 42)
	draw_rect(meter, Color(0.005, 0.018, 0.015, 0.96), true)
	draw_rect(meter, state_color.darkened(0.36), false, 1)
	draw_string(UI_FONT, meter.position + Vector2(10, 17), "METER",
		HORIZONTAL_ALIGNMENT_LEFT, 58, 14, Color8(193, 208, 192))
	draw_string(UI_FONT, meter.position + Vector2(68, 17), reading,
		HORIZONTAL_ALIGNMENT_LEFT, meter.size.x - 154, 16, state_color)
	var trace := PackedVector2Array()
	var trace_left := meter.end.x - 82.0
	for index in 25:
		var x := trace_left + float(index) / 24.0 * 68.0
		var wave := sin(float(index) * 0.72 + _phase * 3.0)
		var amplitude := 7.0 if not last_test.is_empty() else 10.0 + _pulse * 3.0
		trace.append(Vector2(x, meter.position.y + 22.0 + wave * amplitude * 0.32))
	draw_polyline(trace, state_color, 1.5, true)
	draw_circle(meter.position + Vector2(8, 31), 2.2, state_color, true)


func _draw_evidence_rail() -> void:
	var y := size.y - 15.0
	var required := model.evidence_required()
	for index in max(2, required):
		var filled: bool = index < model.evidence_count()
		var rect := Rect2(18 + index * 24, y - 4, 17, 5)
		draw_rect(rect, Color8(83, 232, 148) if filled else Color8(55, 67, 61), true)
	draw_string(UI_FONT, Vector2(72, y),
		"EVIDENZ %d/%d · %d HYPOTHESEN" % [
			model.evidence_count(), required, model.remaining_hypotheses().size()],
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 90, 12, Color8(180, 199, 184))
