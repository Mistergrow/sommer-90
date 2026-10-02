class_name WunderwerkGame
extends Control
## WUNDERWERK '94: PARKDIREKTOR — eigenstaendiges OCS-Aufbauspiel fuer den
## A600 im abwaertskompatiblen OCS-Modus. Maus, Tastatur und Joystick.

const Model := preload("res://scripts/games/wunderwerk_model.gd")
const Catalog := preload("res://scripts/games/wunderwerk_catalog.gd")
const Renderer := preload("res://scripts/games/wunderwerk_renderer.gd")
const AmigaVideo := preload("res://scripts/games/standalone_amiga_video.gd")
const DisplayPipeline := preload("res://scripts/games/amiga_display_pipeline.gd")
const FrameScheduler := preload("res://scripts/games/amiga_frame_scheduler.gd")
const AudioDirector := preload("res://scripts/games/wunderwerk_audio.gd")
const MenuRenderer := preload("res://scripts/games/wunderwerk_menu_renderer.gd")
const GameInputMap := preload("res://scripts/games/wunderwerk_input_map.gd")
const TOPAZ: Font = preload("res://assets/fonts/Topaz_a500_ui.ttf")
const JUICE_SCRIPT_PATH := "res://scripts/ui/juice_layer.gd"

const GAME_ID := "wunderwerk_94"
const VW := 320.0
const VH := 256.0
const SAVE_FLAG := "wunderwerk_94_save"
const TOOL_PAGE_SIZE := 5

const INK := MenuRenderer.INK
const NAVY := MenuRenderer.NAVY
const PANEL := MenuRenderer.PANEL
const LINE := MenuRenderer.LINE
const WHITE := MenuRenderer.WHITE
const CREAM := MenuRenderer.CREAM
const DIM := MenuRenderer.DIM
const AMBER := MenuRenderer.AMBER
const ORANGE := Color8(238, 102, 34)
const RED := MenuRenderer.RED
const GREEN := MenuRenderer.GREEN
const CYAN := MenuRenderer.CYAN
const VIOLET := Color8(102, 68, 153)

enum Screen {
	BOOT, TITLE, SCENARIO, PARK, MANUAL, FINANCES, RECORDS, PAUSE,
	RESULTS, EXIT_CONFIRM,
}

var disk: Disk = null
var model := Model.new()
var renderer := Renderer.new()
var screen := Screen.BOOT
var _return_screen := Screen.TITLE
var _boot_time := 0.0
var _elapsed := 0.0
var _menu_index := 0
var _scenario_index := 0
var _manual_page := 0
var _tool_index := 1
var _tool_page := 0
var _cursor := Vector2i(10, 12)
var _camera := Vector2.ZERO
var _toolbar_open := true
var _selected_object_id := -1
var _speed := 1
var _last_report: Dictionary = {}
var _run_id := ""
var _run_committed := false
var _logical_scale := 1.0
var _logical_origin := Vector2.ZERO
var _video_profile: Dictionary = {}
var _frame_scheduler := FrameScheduler.new()
var _hit_rects: Array[Dictionary] = []
var _juice_layer: CanvasItem = null
var _audio = AudioDirector.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	z_index = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_video_profile = AmigaVideo.profile(GAME_ID, self)
	var scheduler_result := _frame_scheduler.configure(_video_profile)
	if not bool(scheduler_result.get("ok", false)):
		push_error("WunderwerkGame: OCS-PAL-Scheduler ungueltig: %s" %
			str(scheduler_result.get("errors", [])))
	model.reset()
	model.event.connect(_on_model_event)
	model.day_finished.connect(_on_day_finished)
	_build_audio()
	_juice_layer = _find_juice_layer()
	if _juice_layer != null:
		_juice_layer.visible = false
	_sync_layout()
	resized.connect(_sync_layout)
	grab_focus.call_deferred()
	set_process(true)
	set_process_input(true)
	_play_music(_audio.title_stream)


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_frame_scheduler.begin_frame(delta)
	var steps := 0
	while _frame_scheduler.consume_logic_step():
		steps += 1
	var pal_delta := float(steps) * FrameScheduler.PAL_STEP_SECONDS
	_elapsed += pal_delta
	if screen == Screen.BOOT:
		_boot_time += pal_delta
		if _boot_time >= 1.55:
			screen = Screen.TITLE
			_menu_index = 0
	elif screen == Screen.PARK:
		model.advance(pal_delta, _speed)
		if model.finished:
			_show_results()
	queue_redraw()


func _draw() -> void:
	_hit_rects = []
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	draw_set_transform(_logical_origin, 0.0, Vector2.ONE * _logical_scale)
	draw_rect(Rect2(0, 0, VW, VH), INK)
	match screen:
		Screen.BOOT: _draw_boot()
		Screen.TITLE: _draw_title()
		Screen.SCENARIO: _draw_scenarios()
		Screen.PARK: _draw_park()
		Screen.MANUAL: _draw_manual()
		Screen.FINANCES: _draw_finances()
		Screen.RECORDS: _draw_records()
		Screen.PAUSE:
			_draw_park()
			_draw_pause()
		Screen.RESULTS: _draw_results()
		Screen.EXIT_CONFIRM:
			_draw_title()
			_draw_exit_confirm()
	AmigaVideo.draw_post_fx(self, Vector2(VW, VH), _video_profile,
		_elapsed, _reduced_motion())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_letterbox_mask()


func _draw_boot() -> void:
	MenuRenderer.draw_boot(self, _boot_time)


func _draw_title() -> void:
	MenuRenderer.draw_title(self, _menu_index, _has_save())


func _draw_scenarios() -> void:
	MenuRenderer.draw_scenarios(self, _scenario_index)


func _draw_park() -> void:
	var origin := Vector2(119, 31) + _camera
	renderer.draw_world(self, model, origin, _cursor, selected_tool(),
		_selected_object_id, _elapsed)
	# OCS-HUD liegt nach dem Playfield und maskiert dessen Raender.
	draw_rect(Rect2(0, 0, VW, 20), Color(PANEL, 0.98))
	draw_line(Vector2(0, 19), Vector2(VW, 19), LINE, 1.0)
	_text("%d DM" % model.money, Rect2(4, 2, 56, 14), 13, 8,
		GREEN if model.money >= 0 else RED)
	_text("TAG %02d  %s" % [model.day, model.clock_text()],
		Rect2(62, 2, 76, 14), 13, 7, WHITE)
	_text("RUF %02d" % model.reputation, Rect2(140, 2, 48, 14), 13, 7, AMBER)
	_text("GÄSTE %02d" % model.guests.size(), Rect2(190, 2, 52, 14), 13, 7, CYAN)
	if _toolbar_open:
		_draw_toolbar()
	else:
		var tab := Rect2(304, 22, 16, 18)
		draw_rect(tab, Color(PANEL, 0.98))
		draw_rect(tab, LINE, false, 1.0)
		_text("B", tab, 35, 7, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
		_hit_rects.append({"rect": tab, "action": "toolbar"})
	draw_rect(Rect2(0, 236, VW, 20), Color(PANEL, 0.98))
	draw_line(Vector2(0, 236), Vector2(VW, 236), LINE, 1.0)
	_text(model.message.to_upper().left(48), Rect2(4, 239, 238, 12),
		249, 6, CREAM)
	_text("F1 ?  F2 DM  F5 SAVE", Rect2(232, 239, 84, 12),
		249, 5, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	if _selected_object_id >= 0:
		_draw_inspector()


func _draw_toolbar() -> void:
	var panel := Rect2(244, 20, 76, 216)
	draw_rect(panel, Color(PANEL, 0.985))
	draw_line(Vector2(244, 20), Vector2(244, 236), LINE, 1.0)
	var page_count := ceili(float(Catalog.ITEMS.size()) / TOOL_PAGE_SIZE)
	_text("BAUMENÜ %d/%d" % [_tool_page + 1, page_count], Rect2(247, 23, 69, 10),
		31, 6, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	var first := _tool_page * TOOL_PAGE_SIZE
	for slot in TOOL_PAGE_SIZE:
		var index := first + slot
		if index >= Catalog.ITEMS.size():
			break
		var definition: Dictionary = Catalog.ITEMS[index]
		var rect := Rect2(248, 36 + slot * 25, 68, 22)
		var selected := index == _tool_index
		draw_rect(rect, Color(NAVY, 0.96))
		draw_rect(rect, AMBER if selected else LINE, false, 1.0)
		_text(str(definition["name"]), rect.grow(-3), rect.position.y + 9,
			6, AMBER if selected else WHITE)
		var cost := int(definition.get("cost", 0))
		var info := "%d DM" % cost if cost > 0 else str(definition.get("icon", ""))
		_text(info, rect.grow(-3), rect.position.y + 18, 5,
			GREEN if model.money >= cost else RED, HORIZONTAL_ALIGNMENT_RIGHT)
		_hit_rects.append({"rect": rect, "action": "tool", "index": index})
	var map_rect := Rect2(248, 164, 68, 45)
	renderer.draw_minimap(self, model, map_rect, _cursor)
	_hit_rects.append({"rect": map_rect, "action": "minimap"})
	var speed_rect := Rect2(248, 214, 68, 17)
	draw_rect(speed_rect, Color(NAVY, 0.96))
	draw_rect(speed_rect, LINE, false, 1.0)
	var speed_text := "PAUSE" if _speed == 0 else ("%d× TEMPO" % _speed)
	_text(speed_text, speed_rect, 226, 6, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_hit_rects.append({"rect": speed_rect, "action": "speed"})
	var close_rect := Rect2(306, 22, 10, 10)
	_text("X", close_rect, 30, 5, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_hit_rects.append({"rect": close_rect, "action": "toolbar"})


func _draw_inspector() -> void:
	var object := model.object_by_id(_selected_object_id)
	if object.is_empty():
		_selected_object_id = -1
		return
	var definition: Dictionary = Catalog.item(str(object["type"]))
	var rect := Rect2(7, 25, 219, 53)
	draw_rect(rect, Color(INK, 0.94))
	draw_rect(rect, CYAN, false, 1.0)
	_text(str(definition["name"]), rect.grow(-5), 38, 9, AMBER)
	_text("PREIS %d DM · KASSE %d DM · BESUCHER %d" % [
		int(object["price"]), int(object["revenue"]), int(object["served"])],
		rect.grow(-5), 51, 6, WHITE)
	_text("ZUSTAND %d%% · WARTEN %d · %s" % [
		roundi(float(object["condition"])), (object["queue"] as Array).size(),
		"DEFEKT" if bool(object["broken"]) else (
			"OFFEN" if bool(object["open"]) else "GESCHLOSSEN")],
		rect.grow(-5), 63, 6, RED if bool(object["broken"]) else CYAN)
	_text("+/- PREIS · O ÖFFNEN/SCHLIESSEN · ESC SCHLIESST",
		rect.grow(-5), 74, 5, DIM)


func _draw_manual() -> void:
	MenuRenderer.draw_manual(self, _manual_page)


func _draw_finances() -> void:
	MenuRenderer.draw_finances(self, model)


func _draw_records() -> void:
	var manager := get_node_or_null("/root/AmigaGameManager")
	var record: Dictionary = manager.call("record", GAME_ID) if manager != null else {}
	MenuRenderer.draw_records(self, record)


func _draw_pause() -> void:
	MenuRenderer.draw_pause(self)


func _draw_results() -> void:
	MenuRenderer.draw_results(self, model)


func _draw_exit_confirm() -> void:
	MenuRenderer.draw_exit_confirm(self)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var point := _to_logical(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(point)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if screen == Screen.PARK:
				_tool_index = Catalog.item_index("inspect")
				_tool_page = floori(float(_tool_index) / float(TOOL_PAGE_SIZE))
				_selected_object_id = -1
		get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	_execute_command(GameInputMap.key_command(screen, event))


func _execute_command(command: Dictionary) -> void:
	match str(command.get("name", "")):
		"menu":
			_move_menu(int(command["delta"]), 5)
		"accept_title":
			_accept_title()
		"exit_confirm":
			screen = Screen.EXIT_CONFIRM
		"scenario":
			_scenario_index = posmod(_scenario_index + int(command["delta"]),
				Catalog.SCENARIOS.size())
			_play_sfx("move")
		"start_scenario":
			_start_new_park(str(Catalog.SCENARIOS[_scenario_index]["id"]))
		"title":
			screen = Screen.TITLE
			_play_music(_audio.title_stream)
		"resume":
			screen = Screen.PARK
			_speed = maxi(1, _speed)
		"save":
			_save_park()
		"save_title":
			_save_park()
			screen = Screen.TITLE
			_play_music(_audio.title_stream)
		"manual":
			_manual_page = posmod(_manual_page + int(command["delta"]), 4)
		"return":
			screen = _return_screen
		"pan":
			_camera += Vector2(command["delta"])
			_clamp_camera()
		"cursor":
			_move_cursor(Vector2i(command["delta"]))
		"tool":
			_cycle_tool(int(command["delta"]))
		"tool_page":
			_change_tool_page(int(command["delta"]))
		"toolbar":
			_toolbar_open = not _toolbar_open
			_clamp_camera()
		"use":
			_use_tool(_cursor)
		"speed":
			_cycle_speed()
		"manual_screen":
			_return_screen = Screen.PARK
			screen = Screen.MANUAL
		"finances":
			_return_screen = Screen.PARK
			screen = Screen.FINANCES
		"cancel":
			if _selected_object_id >= 0:
				_selected_object_id = -1
			else:
				screen = Screen.PAUSE
				_speed = 0
		"toggle_object":
			if _selected_object_id >= 0:
				model.toggle_object(_selected_object_id)
				_play_sfx("select")
		"price":
			if _selected_object_id >= 0:
				model.change_price(_selected_object_id, int(command["delta"]))
				_play_sfx("cash")
		"exit":
			_exit_game()


func _handle_click(point: Vector2) -> void:
	if screen != Screen.PARK:
		return
	for hit: Dictionary in _hit_rects:
		if not (hit["rect"] as Rect2).has_point(point):
			continue
		match str(hit["action"]):
			"tool":
				_tool_index = int(hit["index"])
				_tool_page = floori(float(_tool_index) / float(TOOL_PAGE_SIZE))
				_play_sfx("move")
			"speed":
				_cycle_speed()
			"toolbar":
				_toolbar_open = not _toolbar_open
				_clamp_camera()
			"minimap":
				var rect: Rect2 = hit["rect"]
				var relative := (point - rect.position) / rect.size
				_cursor = Vector2i(
					clampi(int(relative.x * model.GRID_W), 0, model.GRID_W - 1),
					clampi(int(relative.y * model.GRID_H), 0, model.GRID_H - 1))
				_center_on_cursor()
		return
	var playfield_right := 244.0 if _toolbar_open else 320.0
	if screen == Screen.PARK and point.x < playfield_right \
			and point.y >= 20.0 and point.y < 236.0:
		var origin := Vector2(119, 31) + _camera
		var cell := renderer.screen_to_cell(point, origin)
		if cell.x >= 0 and cell.y >= 0 and cell.x < model.GRID_W and cell.y < model.GRID_H:
			_cursor = cell
			_use_tool(cell)


func _accept_title() -> void:
	match _menu_index:
		0:
			screen = Screen.SCENARIO
		1:
			if _has_save():
				_continue_park()
			else:
				model.message = "NOCH KEIN PARK ARCHIVIERT"
				_play_sfx("alarm")
		2:
			_return_screen = Screen.TITLE
			screen = Screen.MANUAL
		3:
			_return_screen = Screen.TITLE
			screen = Screen.RECORDS
		4:
			screen = Screen.EXIT_CONFIRM


func _start_new_park(id: String) -> void:
	model.reset(id)
	_run_id = "%s-%d" % [id, Time.get_ticks_usec()]
	_run_committed = false
	_cursor = model.ENTRANCE + Vector2i(0, -3)
	_center_on_cursor()
	_tool_index = Catalog.item_index("path")
	_tool_page = 0
	_selected_object_id = -1
	_speed = 1
	screen = Screen.PARK
	_play_music(_audio.park_stream)
	_save_park()


func _continue_park() -> void:
	var flags := _game_flags()
	var data: Variant = flags.get(SAVE_FLAG, {})
	if data is Dictionary and model.from_dict(data):
		_run_id = "continue-%d-%d" % [model.day, Time.get_ticks_usec()]
		_run_committed = false
		_cursor = model.ENTRANCE + Vector2i(0, -3)
		_center_on_cursor()
		screen = Screen.PARK if not model.finished else Screen.RESULTS
		_speed = 1
		_play_music(_audio.park_stream)
	else:
		model.message = "PARKARCHIV NICHT LESBAR"
		_play_sfx("alarm")


func _save_park() -> void:
	_game_flags()[SAVE_FLAG] = model.to_dict()
	model.message = "PARK AUF DISK ARCHIVIERT"
	_play_sfx("build")


func _has_save() -> bool:
	return _game_flags().get(SAVE_FLAG, {}) is Dictionary \
		and not (_game_flags().get(SAVE_FLAG, {}) as Dictionary).is_empty()


func _game_flags() -> Dictionary:
	var manager := get_node_or_null("/root/GameManager")
	return manager.get("flags") if manager != null else {}


func _use_tool(cell: Vector2i) -> void:
	var id := selected_tool()
	if id == "inspect":
		var object := model.object_at(cell)
		_selected_object_id = int(object.get("id", -1))
		model.message = "WEG · VERBUNDEN" if object.is_empty() \
			and model.paths.has("%d,%d" % [cell.x, cell.y]) else (
				"NICHTS AUSGEWÄHLT" if object.is_empty() else
				str(Catalog.item(str(object["type"])).get("name", "BETRIEB")))
		_play_sfx("select")
		return
	var result: Dictionary
	if id == "demolish":
		result = model.demolish(cell)
	else:
		result = model.build(id, cell)
	_play_sfx("build" if bool(result.get("ok", false)) else "alarm")


func selected_tool() -> String:
	return str(Catalog.ITEMS[clampi(_tool_index, 0, Catalog.ITEMS.size() - 1)]["id"])


func _cycle_tool(direction: int) -> void:
	_tool_index = posmod(_tool_index + direction, Catalog.ITEMS.size())
	_tool_page = floori(float(_tool_index) / float(TOOL_PAGE_SIZE))
	_play_sfx("move")


func _change_tool_page(direction: int) -> void:
	var page_count := ceili(float(Catalog.ITEMS.size()) / TOOL_PAGE_SIZE)
	_tool_page = posmod(_tool_page + direction, page_count)
	_tool_index = mini(Catalog.ITEMS.size() - 1, _tool_page * TOOL_PAGE_SIZE)
	_play_sfx("move")


func _cycle_speed() -> void:
	_speed = 1 if _speed == 0 else (3 if _speed == 1 else 0)
	model.message = "ZEIT PAUSIERT" if _speed == 0 else "ZEITRAFFER %d×" % _speed
	_play_sfx("select")


func _move_cursor(direction: Vector2i) -> void:
	_cursor = Vector2i(
		clampi(_cursor.x + direction.x, 0, model.GRID_W - 1),
		clampi(_cursor.y + direction.y, 0, model.GRID_H - 1))
	_focus_cursor()
	_play_sfx("move")


func _focus_cursor() -> void:
	var point := renderer.cell_to_screen(_cursor, Vector2(119, 31) + _camera)
	if point.x < 24:
		_camera.x += 16
	elif point.x > 226:
		_camera.x -= 16
	if point.y < 36:
		_camera.y += 8
	elif point.y > 222:
		_camera.y -= 8
	_clamp_camera()


func _center_on_cursor() -> void:
	var base := renderer.cell_to_screen(_cursor, Vector2(119, 31))
	_camera = Vector2(122, 132) - base
	_clamp_camera()


func _clamp_camera() -> void:
	var top := renderer.cell_to_screen(Vector2i.ZERO, Vector2(119, 31))
	var right := renderer.cell_to_screen(Vector2i(model.GRID_W, 0), Vector2(119, 31))
	var left := renderer.cell_to_screen(Vector2i(0, model.GRID_H), Vector2(119, 31))
	var bottom := renderer.cell_to_screen(
		Vector2i(model.GRID_W, model.GRID_H), Vector2(119, 31))
	var playfield_right := 244.0 if _toolbar_open else 320.0
	_camera.x = clampf(_camera.x, playfield_right - 36.0 - right.x, 36.0 - left.x)
	_camera.y = clampf(_camera.y, 44.0 - bottom.y, 220.0 - top.y)


func _move_menu(direction: int, count: int) -> void:
	_menu_index = posmod(_menu_index + direction, count)
	_play_sfx("move")


func _show_results() -> void:
	screen = Screen.RESULTS
	_speed = 0
	_commit_run()
	_save_park()
	if model.won:
		_play_sfx("cheer")
	else:
		_play_sfx("alarm")


func _commit_run() -> void:
	if _run_committed:
		return
	if _run_id.is_empty():
		_run_id = "park-%d-%d" % [model.day, Time.get_ticks_usec()]
	var manager := get_node_or_null("/root/AmigaGameManager")
	if manager != null:
		manager.call("submit_run", GAME_ID, model.score(), model.won,
			model.sim_tick * 100, {
				"run_id": _run_id,
				"scenario": model.scenario_id,
				"day": model.day,
				"visits": model.total_visits,
				"rides": model.total_rides,
				"reputation": model.reputation,
			})
	_run_committed = true
	_game_flags()["wunderwerk_94_played"] = true
	if model.won:
		_game_flags()["wunderwerk_94_won"] = true


func _on_model_event(kind: String, _data: Dictionary) -> void:
	match kind:
		"build", "hire": _play_sfx("build")
		"breakdown": _play_sfx("alarm")
		"repair", "clean": _play_sfx("cash")
		"finished": pass


func _on_day_finished(_new_day: int, report: Dictionary) -> void:
	_last_report = report
	_save_park()


func _build_audio() -> void:
	_audio.setup(self)


func _play_music(stream: AudioStream) -> void:
	_audio.play_music(self, stream)


func _play_sfx(id: String) -> void:
	_audio.play_sfx(self, id)


func _reduced_motion() -> bool:
	var manager := get_node_or_null("/root/SettingsManager")
	return manager != null and bool(manager.call("value", "reduced_motion"))


func _find_juice_layer() -> CanvasItem:
	for candidate: Node in get_tree().root.find_children("*", "Control", true, false):
		var script := candidate.get_script() as Script
		if script != null and script.resource_path == JUICE_SCRIPT_PATH:
			return candidate as CanvasItem
	return null


func _exit_game() -> void:
	if not _run_id.is_empty():
		_save_park()
	_cleanup_presentation()
	queue_free()


func _exit_tree() -> void:
	_cleanup_presentation()


func _cleanup_presentation() -> void:
	_audio.cleanup(self)
	if _juice_layer != null and is_instance_valid(_juice_layer):
		_juice_layer.visible = true


func _sync_layout() -> void:
	var layout := DisplayPipeline.compute_embedded_layout(size, _video_profile,
		Vector2(VW, VH))
	_logical_scale = float(layout.get("scale", 1.0))
	_logical_origin = Vector2(layout.get("origin", Vector2.ZERO))
	queue_redraw()


func _to_logical(point: Vector2) -> Vector2:
	return (point - _logical_origin) / maxf(0.001, _logical_scale)


func _text(text: String, rect: Rect2, baseline: float, size_px: int, color: Color,
		alignment := HORIZONTAL_ALIGNMENT_LEFT, outline := 0,
		outline_color := INK) -> void:
	draw_string(TOPAZ, Vector2(rect.position.x, baseline), text,
		alignment, rect.size.x, size_px, color)
	if outline > 0:
		# Topaz-Text bleibt scharf: ein Pixel Schatten statt Font-Antialiasing.
		draw_string(TOPAZ, Vector2(rect.position.x + outline, baseline + outline),
			text, alignment, rect.size.x, size_px, Color(outline_color, 0.75))
		draw_string(TOPAZ, Vector2(rect.position.x, baseline), text,
			alignment, rect.size.x, size_px, color)


func _draw_letterbox_mask() -> void:
	var content := Rect2(_logical_origin, Vector2(VW, VH) * _logical_scale)
	if content.position.x > 0.0:
		draw_rect(Rect2(0, 0, content.position.x, size.y), INK)
	if content.end.x < size.x:
		draw_rect(Rect2(content.end.x, 0, size.x - content.end.x, size.y), INK)
	if content.position.y > 0.0:
		draw_rect(Rect2(content.position.x, 0, content.size.x, content.position.y), INK)
	if content.end.y < size.y:
		draw_rect(Rect2(content.position.x, content.end.y,
			content.size.x, size.y - content.end.y), INK)


func debug_start_park(scenario_id := "sommerwiese") -> void:
	_start_new_park(scenario_id)


func debug_snapshot() -> Dictionary:
	return {
		"screen": Screen.keys()[screen].to_lower(),
		"tool": selected_tool(),
		"speed": _speed,
		"model": model.to_dict(),
		"video": AmigaVideo.debug_contract(_video_profile),
	}
