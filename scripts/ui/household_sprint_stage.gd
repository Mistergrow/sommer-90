class_name HouseholdSprintStage
extends Control
## Gemeinsame AGA-Buehne fuer Hausauftraege. Die Kulissen sind handgepixelte
## Ortsplatten; Werkzeuge, Ziele, Copper-Firnis und Trefferfeedback bleiben
## animierte Godot-Sprites. Diese Klasse zahlt niemals Geld aus.

signal action_submitted(action: Dictionary)
signal hud_changed(elapsed_seconds: int, phase_label: String)

const Feedback := preload("res://scripts/ui/household_sprint_feedback.gd")

const AgaSprites := preload("res://scripts/gfx/aga_sprite_catalog.gd")
const Layout := preload("res://scripts/ui/household_sprint_layout.gd")

const ROOM_BG: Texture2D = preload("res://assets/ui/minigames/household/household_room_bins_aga_v01.png")
const DISHES_BG: Texture2D = preload("res://assets/ui/minigames/household/household_dishes_aga_v01.png")
const VACUUM_BG: Texture2D = preload("res://assets/ui/minigames/household/household_vacuum_aga_v01.png")
const SHOPPING_BG: Texture2D = preload("res://assets/ui/minigames/household/household_shopping_aga_v01.png")
const CAR_BG: Texture2D = preload("res://assets/ui/minigames/household/household_car_wash_aga_v01.png")
const LAWN_BG: Texture2D = preload("res://assets/ui/minigames/household/household_lawn_aga_v01.png")

# Interaktive AGA-Sprites. Die Kulissen allein reichen fuer die Spielqualitaet
# nicht aus: Diese Motive ersetzen die ehemaligen Rechteck-/Kreis-Prototypen.
const MOWER_SPRITE: Texture2D = preload("res://assets/ui/minigames/household/sprites/household_mower_red_aga_v02.png")
const GRASS_TUFT_SPRITE: Texture2D = preload("res://assets/ui/minigames/household/sprites/household_grass_tuft_aga_v01.png")
const VACUUM_SPRITE: Texture2D = preload("res://assets/ui/minigames/household/sprites/household_vacuum_aga_v01.png")
const SHOPPING_BASKET_SPRITE: Texture2D = preload("res://assets/ui/minigames/household/sprites/household_shopping_basket_aga_v01.png")
const CARWASH_TOOLS_SPRITE: Texture2D = preload("res://assets/ui/minigames/household/sprites/household_carwash_tools_aga_v01.png")
const SORTING_ITEMS_SPRITE: Texture2D = preload("res://assets/ui/minigames/household/sprites/household_sorting_items_aga_v01.png")
const RUBBISH_SPRITE: Texture2D = preload("res://assets/ui/minigames/household/sprites/household_rubbish_aga_v01.png")
const VACUUM_MOTOR_LOOP: AudioStream = preload("res://assets/audio/sfx/SFX_VACUUM_CLEANER_LOOP_V01.ogg")

const INK := Color("061019")
const PANEL := Color("08131e")
const CYAN := Color("35d8ff")
const GREEN := Color("4ff28c")
const AMBER := Color("ffb52f")
const MAGENTA := Color("ff4e9a")
const RED := Color("ff5d63")
const PAPER := Color("e7e1cc")

@export_category("Rasenmaeher · AGA-Layout")
@export var mower_lawn_polygon_normalized := PackedVector2Array([
	Vector2(0.31, 0.24), Vector2(0.86, 0.25), Vector2(0.87, 0.58),
	Vector2(0.73, 0.72), Vector2(0.10, 0.72), Vector2(0.09, 0.55),
	Vector2(0.20, 0.34),
])
@export var mower_sprite_size_far := Vector2(94, 111)
@export var mower_sprite_size_near := Vector2(132, 155)
@export var mower_grass_size_far := Vector2(58, 22)
@export var mower_grass_size_near := Vector2(92, 34)
@export_range(-12.0, 16.0, 1.0) var mower_ground_offset := 5.0

@export_category("Staubsauger · AGA-Asset-Anker")
@export var vacuum_rig_profile: Resource = preload(
	"res://data/household_vacuum_rig.tres")
@export var show_vacuum_anchors := false

const PRODUCT_FALLBACKS := [
	"MILCH", "BROT", "SAFT", "ERBSEN", "NUDELN", "SEIFE",
	"MEHL", "AEPFEL", "KAKAO", "BUTTER", "REIS", "TEE",
]
const PRODUCT_FRAME_IDS := [
	"milk", "bread", "juice", "peas", "noodles", "soap",
	"flour", "apples", "cocoa", "butter", "rice", "tea",
]

var chore_id := ""
var mode := "sort"
var targets: Array[Dictionary] = []
var cleared := 0
var total := 1
var combo := 0
var elapsed := 0.0
var completed := false
var last_performance := 1.0

var _phase := 0.0
var _drag_target := -1
var _drag_at := Vector2.ZERO
var _pointer := Vector2(560, 360)
var _tool_down := false
var _selected_tool := 0
var _hover_target := -1
var _hover_aux := -1
var _keyboard_cursor := 0
var _last_hud_second := -1
var _path_emit_cooldown := 0.0
var _flash_time := 0.0
var _flash_good := false
var _flash_at := Vector2.ZERO
var _burst_seed := 0
var _finish_message := ""
var _mower_trail := PackedVector2Array()
var _vacuum_trail := PackedVector2Array()
var _vacuum_cable_flash := 0.0
var _vacuum_player: AudioStreamPlayer = null
var _vacuum_keyboard_pulse := 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vacuum_player = AudioStreamPlayer.new()
	_vacuum_player.bus = "SFX"
	_vacuum_player.volume_db = -11.0
	var vacuum_stream := VACUUM_MOTOR_LOOP.duplicate()
	if vacuum_stream != null and "loop" in vacuum_stream:
		vacuum_stream.set("loop", true)
	_vacuum_player.stream = vacuum_stream
	add_child(_vacuum_player)
	set_process(true)
	queue_redraw()


func set_state(next_chore_id: String, next_mode: String, next_targets: Array,
		next_cleared: int, next_total: int, next_combo: int) -> void:
	var previous_mode := mode
	chore_id = next_chore_id
	mode = next_mode
	if previous_mode != mode:
		_pointer = Layout.default_tool_position(mode, size)
		_mower_trail.clear()
		_vacuum_trail.clear()
		_set_vacuum_motor(false)
	targets.clear()
	for target: Dictionary in next_targets:
		targets.append(target.duplicate(true))
	cleared = next_cleared
	total = maxi(1, next_total)
	combo = next_combo
	_drag_target = -1 if not _alive(_drag_target) else _drag_target
	_keyboard_cursor = _next_alive(_keyboard_cursor, 1)
	queue_redraw()


func feedback(good: bool, result: Dictionary) -> void:
	_flash_good = good
	_flash_time = 0.68
	_burst_seed = int(result.get("target", 0)) * 37 + cleared * 11
	var target_index := int(result.get("target", -1))
	_flash_at = Layout.target_center(target_index, targets, _pointer, size) \
		if target_index >= 0 else _pointer
	last_performance = clampf(1.0 - elapsed / 240.0, 0.55, 1.0)
	queue_redraw()


func finish(message: String) -> void:
	completed = true
	_finish_message = message
	_drag_target = -1
	_tool_down = false
	_vacuum_keyboard_pulse = 0.0
	_set_vacuum_motor(false)
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	_path_emit_cooldown = maxf(0.0, _path_emit_cooldown - delta)
	_flash_time = maxf(0.0, _flash_time - delta)
	_vacuum_cable_flash = maxf(0.0, _vacuum_cable_flash - delta)
	if _tool_down and mode in ["vacuum", "mower"] \
			and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_tool_down = false
		_set_vacuum_motor(false)
	if _vacuum_keyboard_pulse > 0.0:
		_vacuum_keyboard_pulse = maxf(0.0, _vacuum_keyboard_pulse - delta)
		if _vacuum_keyboard_pulse <= 0.0 and not _tool_down:
			_set_vacuum_motor(false)
	if not completed:
		elapsed += delta
		var elapsed_second := floori(elapsed)
		if elapsed_second != _last_hud_second:
			_last_hud_second = elapsed_second
			hud_changed.emit(elapsed_second, Layout.phase_label(mode))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if completed:
		return
	if event is InputEventMouseMotion:
		var pointer_at: Vector2 = Layout.mower_position(event.position, _pointer, size,
			mower_lawn_polygon_normalized) if mode == "mower" else event.position
		_pointer = pointer_at
		_drag_at = pointer_at
		_update_hover(pointer_at)
		if _tool_down and mode in ["vacuum", "mower"]:
			if mode == "mower":
				_append_mower_trail(pointer_at)
			else:
				_append_vacuum_trail(pointer_at)
			_submit_path(pointer_at)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pointer_at: Vector2 = Layout.mower_position(event.position, _pointer, size,
			mower_lawn_polygon_normalized) if mode == "mower" else event.position
		_pointer = pointer_at
		_drag_at = pointer_at
		if event.pressed:
			_mouse_press(pointer_at)
		else:
			_mouse_release(pointer_at)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		_keyboard(event)
		accept_event()


func _mouse_press(at: Vector2) -> void:
	match mode:
		"sort", "organize", "dishes":
			_drag_target = _target_at(at)
			if _drag_target >= 0:
				AudioManager.minigame_cue("household_sprint", &"focus")
		"vacuum", "mower":
			_tool_down = true
			if mode == "vacuum":
				_vacuum_keyboard_pulse = 0.0
				_set_vacuum_motor(true)
				_append_vacuum_trail(at)
			if mode == "mower":
				_append_mower_trail(at)
			_submit_path(at)
		"shopping":
			var product := _product_at(at)
			if product >= 0:
				action_submitted.emit({"kind": "pick", "product": product,
					"performance": _performance()})
		"detail":
			var tool := _aux_at(at)
			if tool >= 0:
				_selected_tool = tool
				AudioManager.minigame_cue("household_sprint", &"focus")
			else:
				var panel_index := _target_at(at)
				if panel_index >= 0:
					action_submitted.emit({"kind": "panel", "target": panel_index,
						"tool": _selected_tool, "performance": _performance()})
	queue_redraw()


func _mouse_release(at: Vector2) -> void:
	_tool_down = false
	_set_vacuum_motor(false)
	if _drag_target < 0:
		return
	var destination := _aux_at(at)
	if destination >= 0:
		var action_kind := "dish" if mode == "dishes" else "drop"
		var action := {"kind": action_kind, "target": _drag_target,
			"performance": _performance()}
		if mode == "dishes":
			action["station"] = destination
		else:
			action["destination"] = destination
		action_submitted.emit(action)
	_drag_target = -1
	queue_redraw()


func _keyboard(event: InputEventKey) -> void:
	var direction := 0
	if event.keycode in [KEY_LEFT, KEY_UP, KEY_A, KEY_W]:
		direction = -1
	elif event.keycode in [KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S]:
		direction = 1
	if direction != 0:
		if mode == "shopping":
			_keyboard_cursor = posmod(_keyboard_cursor + direction, PRODUCT_FALLBACKS.size())
		else:
			_keyboard_cursor = _next_alive(_keyboard_cursor, direction)
		AudioManager.minigame_cue("household_sprint", &"focus")
		queue_redraw()
		return
	var numeric := _number_index(event)
	if mode == "detail" and numeric >= 0 and numeric < 3:
		_selected_tool = numeric
		queue_redraw()
		return
	if event.keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		return
	match mode:
		"shopping": action_submitted.emit({"kind": "pick", "product": _keyboard_cursor,
			"performance": _performance()})
		"vacuum", "mower":
			if _alive(_keyboard_cursor):
				if mode == "vacuum":
					_vacuum_keyboard_pulse = 0.34
					_set_vacuum_motor(true)
				action_submitted.emit({"kind": "path", "position": targets[_keyboard_cursor].get("position"),
					"performance": _performance()})
		"detail":
			if _alive(_keyboard_cursor):
				action_submitted.emit({"kind": "panel", "target": _keyboard_cursor,
					"tool": _selected_tool, "performance": _performance()})
		"dishes":
			if _alive(_keyboard_cursor):
				action_submitted.emit({"kind": "dish", "target": _keyboard_cursor,
					"station": int(targets[_keyboard_cursor].get("phase", 0)), "performance": _performance()})
		"sort", "organize":
			if _alive(_keyboard_cursor):
				action_submitted.emit({"kind": "drop", "target": _keyboard_cursor,
					"destination": int(targets[_keyboard_cursor].get("destination", 0)),
					"performance": _performance()})


func _submit_path(at: Vector2) -> void:
	if _path_emit_cooldown > 0.0:
		return
	if mode == "vacuum" and Layout.vacuum_hits_power_cable(at, size,
			_vacuum_rig_point(_pointer, _vacuum_anchor(&"power_socket_anchor"))):
		_path_emit_cooldown = 0.26
		_vacuum_cable_flash = 0.72
		action_submitted.emit({"kind": "obstacle", "performance": _performance()})
		queue_redraw()
		return
	var normalized := Vector2(at.x / maxf(1.0, size.x), at.y / maxf(1.0, size.y))
	var nearest := _nearest_target(normalized, 0.085)
	if nearest < 0:
		return
	_path_emit_cooldown = 0.055
	action_submitted.emit({"kind": "path", "position": normalized, "performance": _performance()})


func _performance() -> float:
	return clampf(1.0 - elapsed / 240.0, 0.55, 1.0)


func _update_hover(at: Vector2) -> void:
	_hover_target = _target_at(at)
	_hover_aux = _aux_at(at)
	if mode == "shopping":
		_hover_aux = _product_at(at)


func _target_at(at: Vector2) -> int:
	for index in targets.size():
		if _alive(index) and Layout.target_rect(index, mode, targets, _pointer, size) \
				.grow(7.0).has_point(at):
			return index
	return -1


func _aux_at(at: Vector2) -> int:
	var count := Layout.aux_count(mode)
	for index in count:
		if Layout.aux_rect(index, count, mode, size).has_point(at):
			return index
	return -1


func _product_at(at: Vector2) -> int:
	for product in PRODUCT_FALLBACKS.size():
		if Layout.product_rect(product).has_point(at):
			return product
	return -1


func _nearest_target(normalized: Vector2, radius: float) -> int:
	var best := -1
	var best_distance := radius
	for index in targets.size():
		if not _alive(index):
			continue
		var target_at := Vector2(targets[index].get("position", Vector2.ZERO))
		var distance := normalized.distance_to(target_at)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


func _alive(index: int) -> bool:
	return index >= 0 and index < targets.size() and int(targets[index].get("hits", 0)) > 0


func _next_alive(from_index: int, direction: int) -> int:
	if targets.is_empty():
		return 0
	var candidate := posmod(from_index, targets.size())
	for unused in targets.size():
		if _alive(candidate):
			return candidate
		candidate = posmod(candidate + direction, targets.size())
	return 0


func _number_index(event: InputEventKey) -> int:
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		return int(event.keycode - KEY_1)
	if event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
		return int(event.keycode - KEY_KP_1)
	return -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_tool_down = false
		_set_vacuum_motor(false)


func _exit_tree() -> void:
	_set_vacuum_motor(false)


func _set_vacuum_motor(active: bool) -> void:
	if _vacuum_player == null:
		return
	var should_play := active and mode == "vacuum" and not completed
	if should_play and not _vacuum_player.playing:
		_vacuum_player.play()
	elif not should_play and _vacuum_player.playing:
		_vacuum_player.stop()
	if _vacuum_player.playing:
		_vacuum_player.pitch_scale = 1.0 + sin(_phase * 5.0) * 0.012


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	_draw_background()
	_draw_copper_firnis()
	_draw_header()
	match mode:
		"sort", "organize": _draw_sorting()
		"dishes": _draw_dishes()
		"vacuum": _draw_vacuum()
		"shopping": _draw_shopping()
		"detail": _draw_detail()
		"mower": _draw_mower()
	_draw_progress()
	if _flash_time > 0.0:
		_draw_burst()
	if completed:
		_draw_finish()


func _draw_background() -> void:
	var texture: Texture2D = ROOM_BG
	match mode:
		"dishes": texture = DISHES_BG
		"vacuum": texture = VACUUM_BG
		"shopping": texture = SHOPPING_BG
		"detail": texture = CAR_BG
		"mower": texture = LAWN_BG
	draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.015, 0.03, 0.14))


func _draw_copper_firnis() -> void:
	for line_y in range(0, int(size.y), 4):
		var pulse := 0.5 + sin(float(line_y) * 0.05 + _phase * 1.5) * 0.5
		draw_rect(Rect2(0, line_y, size.x, 1), Color(0.04, 0.16 + pulse * 0.03, 0.22, 0.12))
	var sweep_x := fmod(_phase * 58.0, size.x + 180.0) - 90.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(sweep_x - 70, 84), Vector2(sweep_x + 30, 84),
		Vector2(sweep_x + 150, size.y), Vector2(sweep_x + 20, size.y)]),
		Color(0.18, 0.72, 0.9, 0.035))


func _draw_header() -> void:
	var header := Rect2(16, 12, size.x - 32.0, 70)
	_panel(header, Color(0.02, 0.055, 0.09, 0.92), CYAN, 2.0)
	_text(header.position + Vector2(18, 29), Layout.mode_title(chore_id), PAPER, 19)
	_text(header.position + Vector2(18, 54), Layout.phase_label(mode), CYAN, 11)
	_text(Vector2(size.x - 315, 41), "AGA · COPPER 256 · BLITTER FX", AMBER, 11)
	_text(Vector2(size.x - 315, 63), "%02d:%02d · KOMBO %02d" % [floori(elapsed / 60.0), floori(elapsed) % 60, combo], GREEN, 12)


func _draw_sorting() -> void:
	var count := Layout.aux_count(mode)
	for destination in count:
		var destination_rect := Layout.aux_rect(destination, count, mode, size)
		var active := destination == _hover_aux and _drag_target >= 0
		_panel(destination_rect, Color(0.015, 0.045, 0.07, 0.82), GREEN if active else AMBER, 2.0)
		_draw_destination_icon(destination_rect.position + Vector2(28, 31), destination)
		_text(destination_rect.position + Vector2(53, 38),
			Layout.aux_label(mode, destination), PAPER, 11)
	for index in targets.size():
		if not _alive(index) or index == _drag_target:
			continue
		_draw_object(index, Layout.target_rect(index, mode, targets, _pointer, size),
			index == _hover_target or index == _keyboard_cursor)
	if _drag_target >= 0:
		_draw_object(_drag_target, Rect2(_drag_at - Vector2(25, 20), Vector2(50, 40)), true)
	var station_sprite := RUBBISH_SPRITE if mode == "sort" else SORTING_ITEMS_SPRITE
	_draw_sprite_centered(station_sprite, Vector2(size.x - 100.0, size.y - 90.0),
		Vector2(150, 140), Color(1, 1, 1, 0.74))


func _draw_dishes() -> void:
	for station in 3:
		var station_rect := Layout.aux_rect(station, 3, mode, size)
		var active := station == _hover_aux and _drag_target >= 0
		_panel(station_rect, Color(0.01, 0.04, 0.06, 0.18), GREEN if active else CYAN, 2.0)
		_text(station_rect.position + Vector2(10, 24), "%d · %s" % [
			station + 1, Layout.dish_label(station)], PAPER, 11)
	for index in targets.size():
		if not _alive(index) or index == _drag_target:
			continue
		var dish_rect := Layout.target_rect(index, mode, targets, _pointer, size)
		_draw_dish(dish_rect.get_center(), int(targets[index].get("phase", 0)), index == _hover_target or index == _keyboard_cursor)
	if _drag_target >= 0:
		_draw_dish(_drag_at, int(targets[_drag_target].get("phase", 0)), true)


func _draw_vacuum() -> void:
	_draw_vacuum_clean_trail()
	_draw_vacuum_power_cable()
	for index in targets.size():
		if not _alive(index):
			continue
		_draw_vacuum_debris(index)
	_draw_vacuum_rig(_pointer)


func _draw_shopping() -> void:
	for product in PRODUCT_FALLBACKS.size():
		var product_rect := Layout.product_rect(product)
		var needed := Layout.product_needed(product, targets)
		var active := product == _hover_aux or product == _keyboard_cursor
		draw_rect(product_rect, Color(0.05, 0.18, 0.24, 0.12 if not active else 0.28))
		draw_rect(product_rect, CYAN if active else Color(0.7, 0.8, 0.85, 0.18), false, 2.0 if active else 1.0)
		AgaSprites.draw_frame(self,
			"household_groceries.%s" % PRODUCT_FRAME_IDS[product],
			product_rect.get_center() + Vector2(0, 2), product_rect.size * 0.72,
			Color(1.0, 1.0, 1.0, 1.0 if needed else 0.72))
		if needed:
			draw_circle(product_rect.position + Vector2(12, 12), 4.0, AMBER)
	var list_panel := Rect2(size.x - 310, 104, 278, 330)
	_panel(list_panel, Color(0.015, 0.025, 0.035, 0.92), AMBER, 2.0)
	_text(list_panel.position + Vector2(18, 30), Loc.t("ui.household_sprint.shopping_list", "EINKAUFSZETTEL"), AMBER, 15)
	var list_row := 0
	for target in targets:
		if int(target.get("hits", 0)) <= 0:
			continue
		var product := int(target.get("variant", 0))
		_text(list_panel.position + Vector2(22, 65 + list_row * 36),
			"[ ]  " + Layout.product_label(product, PRODUCT_FALLBACKS), PAPER, 12)
		list_row += 1
	_text(list_panel.position + Vector2(18, list_panel.size.y - 20),
		Loc.t("ui.household_sprint.shopping_footer", "TUETE · WECHSELGELD · HEIMWEG"), GREEN, 9)
	var basket_at := Vector2(size.x - 166.0, size.y - 110.0)
	_draw_sprite_centered(SHOPPING_BASKET_SPRITE, basket_at, Vector2(205, 185))
	draw_arc(basket_at + Vector2(0, 25), 88.0 + sin(_phase * 2.0) * 2.0,
		0.06, PI - 0.06, 30, Color(CYAN, 0.42), 2.0)


func _draw_detail() -> void:
	for index in targets.size():
		_draw_car_surface_state(index)
	for tool in 3:
		var tool_rect := Layout.aux_rect(tool, 3, mode, size)
		var selected := tool == _selected_tool
		_panel(tool_rect, Color(0.015, 0.035, 0.055, 0.9), GREEN if selected else AMBER, 2.0)
		_draw_tool_icon(tool_rect.position + Vector2(30, 31), tool)
		_text(tool_rect.position + Vector2(56, 38), "%d · %s" % [
			tool + 1, Layout.car_tool_label(tool)], PAPER, 11)
	_draw_car_tool_on_paint()
	_draw_sprite_centered(CARWASH_TOOLS_SPRITE,
		Vector2(size.x - 126.0, size.y - 112.0), Vector2(205, 180), Color(1, 1, 1, 0.92))


func _draw_car_surface_state(index: int) -> void:
	var centre := Layout.target_center(index, targets, _pointer, size)
	var patch_size := Layout.car_patch_size(index, size)
	var phase_index := int(targets[index].get("phase", 0))
	var active := _alive(index)
	if not active or phase_index >= 3:
		_draw_car_polish(centre, patch_size, index)
	elif phase_index == 0:
		_draw_car_grime(centre, patch_size, index)
	elif phase_index == 1:
		_draw_car_foam(centre, patch_size, index)
	else:
		_draw_car_water(centre, patch_size, index)
	if active and (index == _hover_target or index == _keyboard_cursor):
		_draw_target_brackets(centre, patch_size + Vector2(12, 10))


func _draw_car_grime(centre: Vector2, patch_size: Vector2, index: int) -> void:
	# Unregelmaessige Schmutzschleier statt eines runden Zielmarkers. Die
	# versetzten Dither-Flecken folgen der horizontalen Form des Blechs.
	var grime := Color(0.16, 0.085, 0.035, 0.28)
	for dab in 13:
		var px := sin(float(index * 19 + dab * 7)) * patch_size.x * 0.40
		var py := cos(float(index * 11 + dab * 13)) * patch_size.y * 0.34
		var radius := 3.0 + float((index + dab * 3) % 5)
		draw_circle((centre + Vector2(px, py)).round(), radius, grime)
	for streak in 3:
		var y := centre.y - patch_size.y * 0.22 + streak * patch_size.y * 0.22
		draw_line(Vector2(centre.x - patch_size.x * 0.38, y).round(),
			Vector2(centre.x + patch_size.x * (0.19 + streak * 0.08), y + 2.0).round(),
			Color(0.08, 0.045, 0.02, 0.22), 2.0, false)


func _draw_car_foam(centre: Vector2, patch_size: Vector2, index: int) -> void:
	# Mehrlagige Seifeninseln: deckender Schaum, cyanfarbene Schatten und
	# einzelne animierte Blasen. Alles bleibt innerhalb des Blechsegments.
	var foam_polygon := PackedVector2Array([
		centre + Vector2(-patch_size.x * 0.46, -patch_size.y * 0.08),
		centre + Vector2(-patch_size.x * 0.31, -patch_size.y * 0.39),
		centre + Vector2( patch_size.x * 0.08, -patch_size.y * 0.43),
		centre + Vector2( patch_size.x * 0.45, -patch_size.y * 0.17),
		centre + Vector2( patch_size.x * 0.37,  patch_size.y * 0.33),
		centre + Vector2(-patch_size.x * 0.12,  patch_size.y * 0.43),
		centre + Vector2(-patch_size.x * 0.44,  patch_size.y * 0.22),
	])
	draw_colored_polygon(foam_polygon, Color(0.78, 0.93, 0.91, 0.68))
	for bubble in 19:
		var angle := float(bubble) * 2.399 + float(index) * 0.71
		var radius_factor := sqrt(float(bubble + 1) / 19.0)
		var bubble_at := centre + Vector2(cos(angle) * patch_size.x * 0.40,
			sin(angle) * patch_size.y * 0.34) * radius_factor
		bubble_at.y += sin(_phase * 2.8 + bubble + index) * 1.5
		var bubble_radius := 3.0 + float((bubble + index) % 5)
		draw_circle(bubble_at.round(), bubble_radius + 1.0,
			Color(0.16, 0.55, 0.68, 0.54))
		draw_circle(bubble_at.round(), bubble_radius,
			Color(0.91, 0.98, 0.91, 0.88))
		draw_arc(bubble_at.round(), bubble_radius - 1.0, PI, TAU * 0.92,
			8, Color(0.35, 0.89, 1.0, 0.74), 1.0, false)


func _draw_car_water(centre: Vector2, patch_size: Vector2, index: int) -> void:
	# Nach dem Abspritzen bleiben transparente Wasserbahnen, Tropfen und ein
	# wandernder AGA-Glanz auf dem Lack zurueck.
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(-patch_size.x * 0.46, -patch_size.y * 0.34),
		centre + Vector2( patch_size.x * 0.44, -patch_size.y * 0.29),
		centre + Vector2( patch_size.x * 0.37,  patch_size.y * 0.33),
		centre + Vector2(-patch_size.x * 0.41,  patch_size.y * 0.37),
	]), Color(0.18, 0.72, 0.96, 0.18))
	for stream in 7:
		var start_x := centre.x - patch_size.x * 0.40 + stream * patch_size.x * 0.13
		var run := fmod(_phase * (13.0 + stream) + float(index * 17 + stream * 9),
			patch_size.y * 0.62)
		var start_y := centre.y - patch_size.y * 0.38 + run * 0.18
		var points := PackedVector2Array()
		for segment in 5:
			points.append(Vector2(start_x + sin(float(segment + stream)) * 2.0,
				start_y + segment * patch_size.y * 0.14).round())
		draw_polyline(points, Color(0.54, 0.91, 1.0, 0.58), 2.0, false)
		draw_circle(points[-1], 2.5 + float(stream % 2),
			Color(0.71, 0.96, 1.0, 0.72))
	var shine_x := centre.x - patch_size.x * 0.35 + \
		fmod(_phase * 21.0 + index * 11.0, patch_size.x * 0.70)
	draw_line(Vector2(shine_x, centre.y - patch_size.y * 0.29).round(),
		Vector2(shine_x + patch_size.x * 0.12, centre.y + patch_size.y * 0.20).round(),
		Color(0.86, 0.98, 1.0, 0.72), 2.0, false)


func _draw_car_polish(centre: Vector2, patch_size: Vector2, index: int) -> void:
	# Fertige Flaechen bleiben als Lackglanz sichtbar, damit der Fortschritt
	# direkt am Fahrzeug ablesbar ist und nicht nur unten im Balken.
	var sweep := fmod(_phase * 24.0 + index * 31.0, patch_size.x * 1.55) - patch_size.x * 0.78
	var alpha := 0.18 + sin(_phase * 2.2 + index) * 0.05
	draw_line(Vector2(centre.x + sweep - patch_size.x * 0.12,
		centre.y + patch_size.y * 0.27).round(),
		Vector2(centre.x + sweep + patch_size.x * 0.12,
		centre.y - patch_size.y * 0.27).round(), Color(1.0, 0.91, 0.57, alpha), 4.0, false)
	if posmod(floori(_phase * 3.0) + index, 11) < 2:
		var glint := centre + Vector2(patch_size.x * 0.26, -patch_size.y * 0.18)
		draw_line(glint - Vector2(8, 0), glint + Vector2(8, 0), Color(PAPER, 0.74), 2.0, false)
		draw_line(glint - Vector2(0, 8), glint + Vector2(0, 8), Color(PAPER, 0.74), 2.0, false)


func _draw_car_tool_on_paint() -> void:
	var target_index := _hover_target
	if not _alive(target_index):
		target_index = _keyboard_cursor
	if not _alive(target_index):
		return
	var centre := Layout.target_center(target_index, targets, _pointer, size)
	var frame_ids := ["sponge", "hose", "chamois"]
	var tool_offset := Vector2(0, -7.0 + sin(_phase * 5.0) * 2.0)
	AgaSprites.draw_frame(self, "household_props.%s" % frame_ids[_selected_tool % 3],
		centre + tool_offset, Vector2(62, 54), Color(1.0, 1.0, 1.0, 0.96))


func _draw_mower() -> void:
	_draw_mown_trail()
	for index in targets.size():
		var centre := Layout.target_center(index, targets, _pointer, size)
		var depth := Layout.mower_depth(centre.y, size)
		if _alive(index):
			var tuft_size := mower_grass_size_far.lerp(mower_grass_size_near, depth)
			var sway := sin(_phase * 2.4 + float(index) * 1.7) * (1.0 + depth)
			_draw_sprite_centered(GRASS_TUFT_SPRITE, centre + Vector2(sway, 0), tuft_size,
				Color(0.84, 0.94, 0.78, 0.92))
			if index == _hover_target or index == _keyboard_cursor:
				_draw_target_brackets(centre, tuft_size + Vector2(8, 6))
		else:
			_draw_cut_patch(centre, depth, index)
	_draw_mower_head(_pointer)


func _draw_mown_trail() -> void:
	if _mower_trail.size() < 2:
		return
	draw_polyline(_mower_trail, Color(0.10, 0.31, 0.055, 0.34), 42.0, false)
	draw_polyline(_mower_trail, Color(0.36, 0.60, 0.13, 0.25), 2.0, false)


func _draw_cut_patch(centre: Vector2, depth: float, index: int) -> void:
	var half_width := lerpf(29.0, 46.0, depth)
	var half_height := lerpf(8.0, 13.0, depth)
	var skew := half_height * 0.8
	var patch := PackedVector2Array([
		centre + Vector2(-half_width + skew, -half_height),
		centre + Vector2(half_width + skew, -half_height),
		centre + Vector2(half_width - skew, half_height),
		centre + Vector2(-half_width - skew, half_height),
	])
	draw_colored_polygon(patch, Color(0.16, 0.40, 0.075, 0.31))
	for stripe in 3:
		var stripe_y := centre.y - half_height + 5.0 + stripe * half_height * 0.55
		draw_line(Vector2(centre.x - half_width * 0.72, stripe_y),
			Vector2(centre.x + half_width * 0.72, stripe_y - skew * 0.22),
			Color(0.48, 0.67, 0.18, 0.19 + float((index + stripe) % 2) * 0.05), 1.0)


func _draw_target_brackets(centre: Vector2, target_size: Vector2) -> void:
	Feedback.brackets(self, centre, target_size, GREEN)


func _draw_progress() -> void:
	Feedback.progress(self, cleared, total, GREEN, CYAN)


func _draw_burst() -> void:
	Feedback.burst(self, _flash_at, _flash_time, _burst_seed, GREEN if _flash_good else RED)

func _draw_finish() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.02, 0.035, 0.78))
	var finish_panel := Rect2(size.x * 0.20, size.y * 0.34, size.x * 0.60, 170)
	_panel(finish_panel, PANEL, GREEN, 3.0)
	_text(finish_panel.position + Vector2(24, 55),
		Loc.t("ui.household_sprint.finish_title", "HAUSAUFTRAG ABGENOMMEN"), GREEN, 24)
	_text(finish_panel.position + Vector2(24, 92), _finish_message, PAPER, 13)
	_text(finish_panel.position + Vector2(24, 126), "%02d:%02d · %02d KOMBO" % [floori(elapsed / 60.0), floori(elapsed) % 60, combo], AMBER, 12)


func _draw_object(index: int, target_rect: Rect2, active: bool) -> void:
	var variant := int(targets[index].get("variant", 0))
	var border := GREEN if active else AMBER
	var frame_id := ""
	if mode == "sort":
		match variant:
			0: frame_id = "household_props.newspapers"
			1: frame_id = "household_props.recycling_crate"
			2: frame_id = "household_props.binbag"
			_: frame_id = "household_props.sorting_items"
	else:
		match variant:
			0: frame_id = "household_props.book"
			1: frame_id = "household_props.floppy"
			2: frame_id = "household_props.shirt"
			_: frame_id = "household_props.newspapers"
	var object_size := Vector2(68, 62) if active else Vector2(60, 54)
	AgaSprites.draw_frame(self, frame_id, target_rect.get_center(), object_size)
	if active:
		draw_arc(target_rect.get_center(), 35.0 + sin(_phase * 5.0) * 2.0,
			0.0, TAU, 28, GREEN, 2.0)
	draw_rect(target_rect.grow(3), border, false, 2.0 if active else 1.0)


func _draw_dish(at: Vector2, phase_index: int, active: bool) -> void:
	var radius := 25.0 if active else 21.0
	AgaSprites.draw_frame(self, "household_props.dish_set", at,
		Vector2(radius * 2.65, radius * 2.65))
	if phase_index == 0:
		draw_circle(at + Vector2(-5, 3), 7, Color(0.45, 0.27, 0.12, 0.75))
	elif phase_index == 1:
		for bubble in 4:
			draw_circle(at + Vector2(cos(_phase + bubble * 1.5), sin(_phase + bubble * 1.5)) * 19, 4, Color(0.5, 0.9, 1.0, 0.75))
	draw_arc(at, radius + 5, 0.0, TAU, 24, GREEN if active else CYAN, 2.0)


func _draw_vacuum_debris(index: int) -> void:
	var debris_at := Layout.target_center(index, targets, _pointer, size)
	var remaining := int(targets[index].get("hits", 1))
	var density := 1.0 if remaining > 1 else 0.56
	var alpha := (0.72 + sin(_phase * 2.2 + index) * 0.05) * density
	match int(targets[index].get("variant", 0)) % 4:
		0: # Brot-/Kekskruemel
			for speck in 7:
				var offset := Vector2(sin(float(index * 7 + speck * 13)) * 16.0,
					cos(float(index * 11 + speck * 9)) * 8.0)
				draw_rect(Rect2((debris_at + offset).round(), Vector2(3 + speck % 2, 2 + speck % 3)),
					Color(0.63, 0.39, 0.14, alpha))
		1: # Wollmaus mit feinen Fasern
			for fibre in 8:
				var angle := float(fibre) * TAU / 8.0 + index * 0.4
				var inner := debris_at + Vector2(cos(angle), sin(angle)) * 3.0
				var outer := debris_at + Vector2(cos(angle), sin(angle)) * (13.0 + fibre % 3)
				draw_line(inner.round(), outer.round(), Color(0.57, 0.62, 0.64, alpha), 1.0, false)
			draw_circle(debris_at.round(), 5.0, Color(0.42, 0.47, 0.50, alpha))
		2: # Fadenrest
			var thread := PackedVector2Array()
			for segment in 7:
				thread.append((debris_at + Vector2(-18.0 + segment * 6.0,
					sin(float(segment) * 1.45 + index) * 7.0)).round())
			draw_polyline(thread, Color(0.73, 0.34, 0.27, alpha), 2.0, false)
		3: # Papier-/Fusselreste
			for scrap in 4:
				var scrap_at := debris_at + Vector2(-14 + scrap * 9, -5 + (scrap % 2) * 9)
				draw_colored_polygon(PackedVector2Array([
					scrap_at + Vector2(-3, -2), scrap_at + Vector2(4, -3),
					scrap_at + Vector2(3, 3), scrap_at + Vector2(-4, 2)]),
					Color(0.82, 0.76, 0.57, alpha))
	if index == _hover_target or index == _keyboard_cursor:
		_draw_target_brackets(debris_at, Vector2(48, 32))


func _draw_vacuum_clean_trail() -> void:
	if _vacuum_trail.size() < 2:
		return
	# Ein sanfter Florwechsel zeigt die bereits gereinigte Bahn, ohne den
	# gemusterten Teppich mit einer flachen UI-Farbe zu ueberdecken.
	draw_polyline(_vacuum_trail, Color(0.62, 0.82, 0.78, 0.16), 58.0, false)
	draw_polyline(_vacuum_trail, Color(0.08, 0.20, 0.27, 0.22), 3.0, false)
	for index in range(0, _vacuum_trail.size(), 3):
		var trail_at := _vacuum_trail[index]
		draw_line(trail_at + Vector2(-23, -7), trail_at + Vector2(23, -7),
			Color(0.76, 0.91, 0.80, 0.14), 1.0, false)


func _draw_vacuum_power_cable() -> void:
	var cable := Layout.vacuum_power_cable(size,
		_vacuum_rig_point(_pointer, _vacuum_anchor(&"power_socket_anchor")))
	var warning := RED if _vacuum_cable_flash > 0.0 else Color(0.045, 0.055, 0.06, 0.94)
	draw_polyline(cable, Color(0.0, 0.0, 0.0, 0.65), 10.0, false)
	draw_polyline(cable, warning, 6.0, false)
	draw_polyline(cable, Color(0.36, 0.42, 0.44, 0.42), 1.0, false)
	if _vacuum_cable_flash > 0.0:
		var pulse := 5.0 + (1.0 - _vacuum_cable_flash / 0.72) * 13.0
		draw_arc(cable[2], pulse, 0.0, TAU, 20, Color(RED, _vacuum_cable_flash), 2.0)


func _draw_vacuum_rig(at: Vector2) -> void:
	var bob := sin(_phase * 6.0) * 1.5 if _tool_down else sin(_phase * 2.0) * 0.6
	# Das Sprite enthaelt Kessel, echten geriffelten Schlauch, Metallrohr und
	# Bodenduese bereits perspektivisch konsistent. Es wird deshalb als EIN
	# Geraet am kalibrierten Bodenduesen-Anker bewegt; die fruehere zweite,
	# prozedurale Schlauchkurve war die sichtbare Fehlkonstruktion.
	var rig_rect: Rect2 = vacuum_rig_profile.call("sprite_rect_for", at, size.y, bob)
	var depth := float(vacuum_rig_profile.call("depth_for", at.y, size.y))
	var shadow_at := _vacuum_point_in_rect(rig_rect, _vacuum_anchor(&"shadow_anchor"))
	_draw_animated_shadow(shadow_at + Vector2(0, 4),
		Vector2(88, 18).lerp(Vector2(132, 27), depth))
	draw_texture_rect(VACUUM_SPRITE, rig_rect, false)
	if _tool_down:
		for stream in 7:
			var intake := at + Vector2(-28 + stream * 9, 2 + absf(stream - 3) * 1.5)
			var pull := Vector2(0, -12 - sin(_phase * 9.0 + stream) * 4.0)
			draw_line(intake, intake + pull, Color(CYAN, 0.58), 2.0, false)
	if show_vacuum_anchors:
		_draw_vacuum_anchor_gizmo(rig_rect, "DUESE",
			_vacuum_anchor(&"floor_head_anchor"), GREEN)
		_draw_vacuum_anchor_gizmo(rig_rect, "KABEL",
			_vacuum_anchor(&"power_socket_anchor"), AMBER)
		_draw_vacuum_anchor_gizmo(rig_rect, "SCHLAUCH/KESSEL",
			_vacuum_anchor(&"hose_canister_anchor"), MAGENTA)
		_draw_vacuum_anchor_gizmo(rig_rect, "SCHLAUCH/ROHR",
			_vacuum_anchor(&"hose_wand_anchor"), CYAN)


func _vacuum_rig_point(at: Vector2, normalized_anchor: Vector2) -> Vector2:
	var rig_rect: Rect2 = vacuum_rig_profile.call("sprite_rect_for", at, size.y)
	return _vacuum_point_in_rect(rig_rect, normalized_anchor)


func _vacuum_anchor(property_name: StringName) -> Vector2:
	var value: Variant = vacuum_rig_profile.get(property_name)
	return value if value is Vector2 else Vector2.ZERO


func _vacuum_point_in_rect(rig_rect: Rect2, normalized_anchor: Vector2) -> Vector2:
	return rig_rect.position + normalized_anchor * rig_rect.size


func _draw_vacuum_anchor_gizmo(rig_rect: Rect2, label: String,
		normalized_anchor: Vector2, color: Color) -> void:
	var anchor_at := _vacuum_point_in_rect(rig_rect, normalized_anchor).round()
	draw_circle(anchor_at, 6.0, Color(0.0, 0.0, 0.0, 0.82))
	draw_arc(anchor_at, 8.0, 0.0, TAU, 20, color, 2.0)
	draw_line(anchor_at - Vector2(12, 0), anchor_at + Vector2(12, 0), color, 1.0)
	draw_line(anchor_at - Vector2(0, 12), anchor_at + Vector2(0, 12), color, 1.0)
	_text(anchor_at + Vector2(13, -9), label, color, 9)


func _append_vacuum_trail(at: Vector2) -> void:
	if at.y < size.y * 0.52:
		return
	if _vacuum_trail.is_empty() or _vacuum_trail[-1].distance_to(at) >= 6.0:
		_vacuum_trail.append(at)
		if _vacuum_trail.size() > 190:
			_vacuum_trail.remove_at(0)


func _draw_mower_head(at: Vector2) -> void:
	var bob := sin(_phase * 7.0) * 2.0 if _tool_down else sin(_phase * 2.0)
	var depth := Layout.mower_depth(at.y, size)
	var sprite_size := mower_sprite_size_far.lerp(mower_sprite_size_near, depth)
	var ground_at := at + Vector2(0, bob)
	_draw_animated_shadow(ground_at + Vector2(0, 3),
		Vector2(62, 14).lerp(Vector2(88, 21), depth))
	_draw_sprite_grounded(MOWER_SPRITE, ground_at, sprite_size)
	if _tool_down:
		for chip in 9:
			var chip_at := ground_at + Vector2(-34 + chip * 9, -2 + sin(_phase * 10 + chip) * 7)
			draw_colored_polygon(PackedVector2Array([
				chip_at, chip_at + Vector2(3, -6), chip_at + Vector2(6, 1)]),
				GREEN if chip % 2 == 0 else AMBER)
		draw_arc(ground_at, 38 + depth * 8.0 + sin(_phase * 9.0) * 2.0,
			0.0, PI, 24, Color(GREEN, 0.75), 2.0)


func _draw_animated_shadow(at: Vector2, shadow_size: Vector2) -> void:
	draw_set_transform(at, 0.0, Vector2(1.0, shadow_size.y / shadow_size.x))
	draw_circle(Vector2.ZERO, shadow_size.x * 0.5, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sprite_centered(texture: Texture2D, centre: Vector2,
		max_size: Vector2, tint_color: Color = Color.WHITE) -> Rect2:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return Rect2()
	var source_size := Vector2(texture.get_width(), texture.get_height())
	var scale_factor := minf(max_size.x / source_size.x, max_size.y / source_size.y)
	var draw_size := (source_size * scale_factor).round()
	var target_rect := Rect2((centre - draw_size * 0.5).round(), draw_size)
	draw_texture_rect(texture, target_rect, false, tint_color)
	return target_rect


func _draw_sprite_grounded(texture: Texture2D, ground_at: Vector2,
		max_size: Vector2, tint_color: Color = Color.WHITE) -> Rect2:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return Rect2()
	var source_size := Vector2(texture.get_width(), texture.get_height())
	var scale_factor := minf(max_size.x / source_size.x, max_size.y / source_size.y)
	var draw_size := (source_size * scale_factor).round()
	var target_rect := Rect2(Vector2(ground_at.x - draw_size.x * 0.5,
		ground_at.y - draw_size.y + mower_ground_offset).round(), draw_size)
	draw_texture_rect(texture, target_rect, false, tint_color)
	return target_rect


func _append_mower_trail(at: Vector2) -> void:
	if _mower_trail.is_empty() or _mower_trail[-1].distance_to(at) >= 7.0:
		_mower_trail.append(at)
		if _mower_trail.size() > 160:
			_mower_trail.remove_at(0)


func _draw_destination_icon(at: Vector2, destination: int) -> void:
	var sort_frames := ["paper_bin", "recycling_crate", "refuse_bin"]
	var room_frames := ["book", "floppy", "laundry_basket", "paper_bin"]
	var frames := sort_frames if mode == "sort" else room_frames
	AgaSprites.draw_frame(self, "household_props.%s" % frames[destination % frames.size()],
		at, Vector2(45, 43))


func _draw_tool_icon(at: Vector2, tool: int) -> void:
	var frames := ["sponge", "hose", "chamois"]
	AgaSprites.draw_frame(self, "household_props.%s" % frames[tool % frames.size()],
		at, Vector2(45, 43))


func _panel(rect: Rect2, fill: Color, border: Color, width: float) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, width)
	draw_line(rect.position + Vector2(4, 4), Vector2(rect.end.x - 4, rect.position.y + 4), Color(border, 0.38), 1.0)


func _text(at: Vector2, value: String, color: Color, font_size: int) -> void:
	draw_string(get_theme_default_font(), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
