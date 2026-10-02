extends Control

## Interaktives Vierkanal-Brett: Eingabe, Loetwerte, Diagnose und Rendering.
const RepairModel := preload("res://scripts/minigames/joystick_repair_model.gd")
signal changed
signal request_heat
signal request_tin
signal request_finalize
signal request_undo
signal request_hint
signal request_reset
signal request_test

const WIRE := 0
const SOLDER := 1
const TEST := 2
const DONE := 3
const SOURCE_X := [0.38, 0.46, 0.54, 0.62]
const TARGET_NORM := [
	Vector2(0.504, 0.139), Vector2(0.670, 0.442),
	Vector2(0.507, 0.717), Vector2(0.335, 0.443),
]
const CHANNEL_COLORS := [
	Color8(224, 76, 74), Color8(74, 196, 230),
	Color8(244, 205, 70), Color8(115, 202, 91),
]

var board_texture: Texture2D
var model: RefCounted
var stage := WIRE
var selected_source := -1
var hint_visible := false
var hint: Dictionary = {}
var diagnostic: Dictionary = {}
var celebrate := false
var _heat: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _tin: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _dragging := false
var _pointer := Vector2.ZERO
var _keyboard_target_mode := false
var _keyboard_index := 0
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(true)


func set_stage(value: int) -> void:
	stage = value
	diagnostic = {}
	_keyboard_target_mode = false
	if stage == SOLDER and (selected_source < 0 or model.wire_targets[selected_source] < 0):
		selected_source = _first_connected_source()
	queue_redraw()


func sync_from_model() -> void:
	if selected_source >= 0 and model.wire_targets[selected_source] < 0:
		selected_source = -1
	queue_redraw()
	changed.emit()


func reset_local_values() -> void:
	_heat = [0.0, 0.0, 0.0, 0.0]
	_tin = [0.0, 0.0, 0.0, 0.0]
	selected_source = -1
	hint_visible = false
	hint = {}
	diagnostic = {}
	queue_redraw()


func show_hint(value: Dictionary) -> void:
	hint = value.duplicate(true)
	hint_visible = not hint.is_empty()
	queue_redraw()
	changed.emit()


func show_diagnostic(value: Dictionary) -> void:
	diagnostic = value.duplicate(true)
	queue_redraw()


func selected_values() -> Dictionary:
	if selected_source < 0:
		return {"heat": 0.0, "tin": 0.0}
	return {"heat": _heat[selected_source], "tin": _tin[selected_source]}


func add_heat(amount: float) -> void:
	if stage != SOLDER or selected_source < 0:
		return
	_heat[selected_source] = clampf(_heat[selected_source] + amount, 0.0, 1.25)
	queue_redraw()
	changed.emit()


func add_tin(amount: float) -> void:
	if stage != SOLDER or selected_source < 0:
		return
	_tin[selected_source] = clampf(_tin[selected_source] + amount, 0.0, 1.25)
	queue_redraw()
	changed.emit()


func finalize_selected_joint() -> String:
	if stage != SOLDER or selected_source < 0 or model.wire_targets[selected_source] < 0:
		return "open"
	var state: String = model.heat_joint(selected_source, _heat[selected_source], _tin[selected_source])
	queue_redraw()
	changed.emit()
	if state == "good":
		_select_next_open_joint()
	return state


func desolder_selected() -> bool:
	if selected_source < 0 or not model.desolder(selected_source):
		return false
	_heat[selected_source] = 0.0
	_tin[selected_source] = 0.0
	queue_redraw()
	changed.emit()
	return true


func source_hit_rect(source: int) -> Rect2:
	return Rect2(_source_position(source) - Vector2(24, 20), Vector2(48, 40))


func pad_hit_rect(target: int) -> Rect2:
	return Rect2(_target_position(target) - Vector2(29, 29), Vector2(58, 58))


func _process(delta: float) -> void:
	_pulse += delta
	if celebrate or hint_visible or not diagnostic.is_empty() or stage == SOLDER:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				_pointer = event.position
				if stage == WIRE:
					var source := _source_at(event.position)
					if source >= 0:
						selected_source = source
						_dragging = true
					else:
						var target := _target_at(event.position)
						if target >= 0 and selected_source >= 0:
							_connect_selected(target)
				elif stage == SOLDER:
					_select_joint_at(event.position)
			else:
				if stage == WIRE and _dragging:
					var target := _target_at(event.position)
					if target >= 0 and selected_source >= 0:
						_connect_selected(target)
				_dragging = false
	elif event is InputEventMouseMotion:
		_pointer = event.position
	queue_redraw()
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_key(event: InputEventKey) -> void:
	if event.ctrl_pressed and event.keycode == KEY_Z:
		request_undo.emit()
		return
	match event.keycode:
		KEY_H: request_hint.emit()
		KEY_R: request_reset.emit()
		KEY_LEFT, KEY_UP:
			_keyboard_index = posmod(_keyboard_index - 1, 4)
			_keyboard_select()
		KEY_RIGHT, KEY_DOWN:
			_keyboard_index = posmod(_keyboard_index + 1, 4)
			_keyboard_select()
		KEY_ENTER, KEY_KP_ENTER:
			if stage == WIRE:
				if not _keyboard_target_mode:
					selected_source = model.source_order[_keyboard_index]
					_keyboard_target_mode = true
				else:
					_connect_selected(_keyboard_index)
					_keyboard_target_mode = false
			elif stage == SOLDER:
				request_finalize.emit()
			elif stage == TEST:
				request_test.emit()
		KEY_SPACE:
			if stage == SOLDER:
				request_heat.emit()
		KEY_T:
			if stage == SOLDER:
				request_tin.emit()
	queue_redraw()


func _keyboard_select() -> void:
	if stage == WIRE:
		if not _keyboard_target_mode:
			selected_source = model.source_order[_keyboard_index]
	elif stage == SOLDER:
		var source := _source_for_target(_keyboard_index)
		if source >= 0:
			selected_source = source
	changed.emit()


func _connect_selected(target: int) -> void:
	if model.connect_wire(selected_source, target):
		_heat[selected_source] = 0.0
		_tin[selected_source] = 0.0
		AudioManager.key_click()
	else:
		UIManager.toast(Loc.t("ui.joystick_repair_board.diese_ose_ist_bereits_belegt", "Diese Öse ist bereits belegt."))
	_dragging = false
	queue_redraw()
	changed.emit()


func _select_joint_at(point: Vector2) -> void:
	var target := _target_at(point)
	if target < 0:
		return
	var source := _source_for_target(target)
	if source >= 0:
		selected_source = source
		changed.emit()


func _select_next_open_joint() -> void:
	for offset in range(1, 5):
		var candidate := posmod(selected_source + offset, 4)
		if str(model.joint_states[candidate].get("state", "open")) == "open":
			selected_source = candidate
			return


func _first_connected_source() -> int:
	for source in RepairModel.CHANNEL_COUNT:
		if model.wire_targets[source] >= 0:
			return source
	return -1


func _source_for_target(target: int) -> int:
	for source in RepairModel.CHANNEL_COUNT:
		if model.wire_targets[source] == target:
			return source
	return -1


func _source_at(point: Vector2) -> int:
	for source in RepairModel.CHANNEL_COUNT:
		if source_hit_rect(source).grow(6).has_point(point):
			return source
	return -1


func _target_at(point: Vector2) -> int:
	for target in RepairModel.CHANNEL_COUNT:
		if pad_hit_rect(target).grow(6).has_point(point):
			return target
	return -1


func _art_rect() -> Rect2:
	if board_texture == null:
		return Rect2(Vector2.ZERO, size)
	var ratio := board_texture.get_width() / float(board_texture.get_height())
	var draw_size := Vector2(size.x, size.x / ratio)
	if draw_size.y > size.y:
		draw_size = Vector2(size.y * ratio, size.y)
	return Rect2((size - draw_size) * 0.5, draw_size)


func _source_position(source: int) -> Vector2:
	var slot: int = model.source_order.find(source)
	if slot < 0:
		slot = source
	var ar := _art_rect()
	return ar.position + Vector2(ar.size.x * SOURCE_X[slot], ar.size.y * 0.885)


func _target_position(target: int) -> Vector2:
	var ar := _art_rect()
	return ar.position + TARGET_NORM[target] * ar.size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(5, 7, 10))
	var ar := _art_rect()
	if board_texture != null:
		draw_texture_rect(board_texture, ar, false)
	draw_rect(ar, Color(0.0, 0.0, 0.0, 0.08))
	_draw_service_strip(ar)
	_draw_wires()
	_draw_targets()
	if stage == SOLDER:
		_draw_solder_meter(ar)
	if stage == TEST and not diagnostic.is_empty():
		_draw_diagnostic(ar)
	if _dragging and selected_source >= 0:
		_draw_wire_curve(_source_position(selected_source), _pointer,
			CHANNEL_COLORS[selected_source], true)
	if celebrate:
		var glow := 0.52 + sin(_pulse * 7.0) * 0.22
		draw_rect(ar.grow(-5), Color(1.0, 0.72, 0.20, glow), false, 5.0)


func _draw_service_strip(ar: Rect2) -> void:
	var panel := Rect2(ar.position + Vector2(ar.size.x * 0.345, ar.size.y * 0.825),
		Vector2(ar.size.x * 0.31, ar.size.y * 0.145))
	draw_rect(panel, Color(0.025, 0.035, 0.04, 0.92))
	draw_rect(panel, Color8(80, 95, 98), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(9, 15), "4-KANAL · SERVICE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.UI_TEXT_DIM)
	for source in RepairModel.CHANNEL_COUNT:
		var pos := _source_position(source)
		var selected := selected_source == source
		draw_circle(pos, 17.0, Color(0.03, 0.04, 0.05, 0.96))
		draw_circle(pos, 17.0, CHANNEL_COLORS[source] if selected else CHANNEL_COLORS[source].darkened(0.25), false, 3.0)
		var symbol: String = str(RepairModel.CHANNEL_SYMBOLS[source])
		draw_string(font, pos + Vector2(-9, 6), symbol, HORIZONTAL_ALIGNMENT_CENTER, 18, 15, Palette.WHITE)
		if model.wire_targets[source] >= 0:
			draw_circle(pos + Vector2(13, -12), 4.0, Palette.LCD_GREEN)


func _draw_wires() -> void:
	for source in RepairModel.CHANNEL_COUNT:
		var target: int = model.wire_targets[source]
		if target < 0:
			continue
		var color: Color = CHANNEL_COLORS[source]
		_draw_wire_curve(_source_position(source), _target_position(target), color, false)


func _draw_wire_curve(start: Vector2, finish: Vector2, color: Color, preview: bool) -> void:
	var points := PackedVector2Array()
	var bend_a := start + Vector2(0, -55)
	var bend_b := finish + Vector2(0, 50 if finish.y < start.y else 28)
	for i in 25:
		var t := i / 24.0
		var u := 1.0 - t
		points.append(u * u * u * start + 3.0 * u * u * t * bend_a + 3.0 * u * t * t * bend_b + t * t * t * finish)
	draw_polyline(points, Color(0.02, 0.02, 0.025, 0.9), 9.0, false)
	draw_polyline(points, Color(color, 0.62 if preview else 0.96), 5.0, false)
	draw_polyline(points, Color(color.lightened(0.35), 0.42), 1.0, false)


func _draw_targets() -> void:
	var font := ThemeDB.fallback_font
	for target in RepairModel.CHANNEL_COUNT:
		var pos := _target_position(target)
		var source := _source_for_target(target)
		var color := Palette.LCD_CYAN
		if source >= 0:
			color = CHANNEL_COLORS[source]
		var pulse := 0.55 + sin(_pulse * 5.0 + target) * 0.18
		draw_circle(pos, 23.0, Color(color, pulse if selected_source == source else 0.22), false, 3.0)
		if hint_visible and int(hint.get("target", -1)) == target:
			draw_circle(pos, 31.0, Color(Palette.LCD_GREEN, 0.72), false, 4.0)
		var label := "%s %s" % [RepairModel.CHANNEL_KEYS[target], RepairModel.CHANNEL_SYMBOLS[target]]
		draw_rect(Rect2(pos + Vector2(-25, 27), Vector2(50, 18)), Color(0.02, 0.03, 0.04, 0.88))
		draw_string(font, pos + Vector2(-21, 41), label, HORIZONTAL_ALIGNMENT_CENTER, 42, 11, Palette.WHITE_SOFT)
		if source >= 0:
			_draw_joint(pos, source)


func _draw_joint(pos: Vector2, source: int) -> void:
	var state := str(model.joint_states[source].get("state", "open"))
	match state:
		"good":
			draw_circle(pos, 11.0, Color8(177, 190, 195))
			draw_circle(pos - Vector2(3, 3), 3.0, Color8(238, 242, 235))
		"cold":
			draw_circle(pos, 12.0, Color8(112, 116, 113))
			for i in 7:
				draw_circle(pos + Vector2(cos(i * 2.4), sin(i * 3.1)) * (3 + i % 4), 1.2, Color8(64, 67, 67))
		"overheated":
			draw_circle(pos, 14.0, Color(0.55, 0.20, 0.06, 0.65), false, 5.0)
			draw_circle(pos, 10.0, Color8(124, 117, 106))
		"bridge":
			draw_circle(pos, 17.0, Color8(157, 165, 166))
			draw_rect(Rect2(pos + Vector2(8, -5), Vector2(20, 10)), Color8(151, 160, 161))


func _draw_solder_meter(ar: Rect2) -> void:
	var panel := Rect2(ar.position + Vector2(ar.size.x * 0.70, ar.size.y * 0.73),
		Vector2(ar.size.x * 0.265, ar.size.y * 0.205))
	draw_rect(panel, Color(0.02, 0.03, 0.035, 0.94))
	draw_rect(panel, Color8(76, 88, 90), false, 2.0)
	var font := ThemeDB.fallback_font
	var source := selected_source
	var header := "ÖSE WÄHLEN"
	if source >= 0:
		header = "%s %s  ·  LÖTPROFIL" % [RepairModel.CHANNEL_KEYS[source], RepairModel.CHANNEL_SYMBOLS[source]]
	draw_string(font, panel.position + Vector2(10, 18), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.WHITE_SOFT)
	var heat := 0.0 if source < 0 else _heat[source]
	var tin := 0.0 if source < 0 else _tin[source]
	_draw_meter(Rect2(panel.position + Vector2(12, 31), Vector2(panel.size.x - 24, 14)), heat,
		model.safe_heat_min(), model.safe_heat_max(), "WÄRME")
	_draw_meter(Rect2(panel.position + Vector2(12, 61), Vector2(panel.size.x - 24, 14)), tin,
		model.safe_tin_min(), model.safe_tin_max(), "ZINN")


func _draw_meter(rect: Rect2, value: float, safe_min: float, safe_max: float, label: String) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(0, -3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.UI_TEXT_DIM)
	draw_rect(rect, Color8(10, 12, 13))
	var safe_x := rect.position.x + rect.size.x * clampf(safe_min, 0.0, 1.0)
	var safe_w := rect.size.x * clampf(safe_max - safe_min, 0.0, 1.0)
	draw_rect(Rect2(Vector2(safe_x, rect.position.y), Vector2(safe_w, rect.size.y)), Color(0.20, 0.72, 0.30, 0.48))
	var fill_color := Palette.LCD_GREEN if value >= safe_min and value <= safe_max else (Palette.LCD_AMBER if value > safe_max else Palette.LCD_CYAN)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(value, 0.0, 1.0), rect.size.y)), Color(fill_color, 0.78))
	draw_rect(rect, Color8(94, 101, 101), false, 1.0)


func _draw_diagnostic(ar: Rect2) -> void:
	var panel := Rect2(ar.position + Vector2(ar.size.x * 0.20, ar.size.y * 0.035),
		Vector2(ar.size.x * 0.60, ar.size.y * 0.13))
	draw_rect(panel, Color(0.015, 0.025, 0.03, 0.95))
	draw_rect(panel, Color8(68, 92, 97), false, 2.0)
	var font := ThemeDB.fallback_font
	var channels: Array = diagnostic.get("channels", [])
	for i in mini(4, channels.size()):
		var channel: Dictionary = channels[i]
		var status := str(channel.get("status", "open"))
		var color := Palette.LCD_GREEN if status == "ok" else Palette.LCD_AMBER
		var cell := Rect2(panel.position + Vector2(10 + i * (panel.size.x - 20) / 4.0, 8),
			Vector2((panel.size.x - 26) / 4.0, panel.size.y - 16))
		draw_rect(cell, Color(color, 0.12))
		draw_circle(cell.position + Vector2(14, 14), 6.0, color)
		var text := "%s %s  %s" % [channel.get("key", "?"), channel.get("symbol", "?"), _status_label(status)]
		draw_string(font, cell.position + Vector2(25, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


func _status_label(status: String) -> String:
	match status:
		"ok": return "STABIL"
		"cold": return "KALT"
		"bridge": return "BRÜCKE"
		"overheated": return "HEISS"
		"swapped": return "VERTAUSCHT"
		_: return "OFFEN"

