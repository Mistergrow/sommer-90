class_name SpaceLemmingGame
extends Control
## SPACE LEMMING TROUBLE — eigenstaendiges Action-Puzzle mit Kampagne,
## garantiert loesbarem Levelgenerator, Maus/Keyboard/Gamepad und Rekorden.

const Generator := preload("res://scripts/games/space_lemming_generator.gd")
const Model := preload("res://scripts/games/space_lemming_model.gd")
const Art := preload("res://scripts/games/space_lemming_art.gd")
const Intro := preload("res://scripts/games/space_lemming_intro.gd")
const AmigaPresentation := preload("res://scripts/games/amiga_game_presentation.gd")
const AmigaVideo := preload("res://scripts/games/standalone_amiga_video.gd")
const DisplayPipeline := preload("res://scripts/games/amiga_display_pipeline.gd")
const FrameScheduler := preload("res://scripts/games/amiga_frame_scheduler.gd")
const Synth := preload("res://scripts/audio/space_lemming_synth.gd")
const TITLE_ART := preload("res://assets/ui/games/space_lemming/title_background_v01.png")
const MISSION_ART := preload("res://assets/ui/games/space_lemming/mission_background_v01.png")
const JUICE_SCRIPT_PATH := "res://scripts/ui/juice_layer.gd"

const GAME_ID := "space_lemming_trouble"
const VW := 384.0
const VH := 216.0
const DISK_BOOT_DURATION := 0.72
const INTRO_DURATION := DISK_BOOT_DURATION + 5.2
const GRID_ORIGIN := Vector2(8, 39)
const CELL := 14.0
const GRID_RECT := Rect2(GRID_ORIGIN, Vector2(Generator.WIDTH, Generator.HEIGHT) * CELL)

const INK := Color8(6, 10, 20)
const NAVY := Color8(15, 28, 48)
const STEEL := Color8(48, 63, 79)
const STEEL_LIT := Color8(85, 109, 122)
const WHITE := Color8(234, 238, 218)
const CREAM := Color8(236, 195, 135)
const AMBER := Color8(246, 166, 51)
const ORANGE := Color8(218, 98, 42)
const RED := Color8(224, 71, 78)
const CYAN := Color8(64, 210, 222)
const BLUE := Color8(61, 114, 199)
const GREEN := Color8(103, 205, 120)
const VIOLET := Color8(151, 101, 203)

enum Screen { BOOT, TITLE, CAMPAIGN, SIGNAL, BRIEFING, PLAY, PAUSE, RESULTS, RECORDS, EXIT_CONFIRM }

var disk: Disk = null
var model := Model.new()
var screen := Screen.BOOT
var _resume_screen := Screen.PLAY
var _boot_time := 0.0
var _intro_cue := -1
var _menu_index := 0
var _campaign_cursor := 0
var _selected_tool := Generator.Tool.RIGHT
var _cursor_cell := Vector2i(1, 5)
var _hover_cell := Vector2i(-1, -1)
var _hint := false
var _endless_seed := 199_204
var _endless_difficulty := 6
var _mode := "campaign"
var _level_index := 0
var _accumulator := 0.0
var _last_event_serial := 0
var _run_id := ""
var _run_committed := false
var _result_line := ""
var _logical_scale := 1.0
var _logical_origin := Vector2.ZERO
var _video_profile: Dictionary = {}
var _frame_scheduler := FrameScheduler.new()
var _shake := 0.0
var _flash := 0.0
var _mission_time := 0.0
var _fx_particles: Array[Dictionary] = []
var _cosmetic_rng := RandomNumberGenerator.new()
var _reduced_fx := false
var _juice_layer: CanvasItem = null
var _music: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _title_stream: AudioStreamWAV
var _mission_stream: AudioStreamWAV
var _sfx: Dictionary = {}
var TOPAZ: Font = load("res://assets/fonts/Topaz_a500_ui.ttf")


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
		push_error("SpaceLemmingGame: PAL-Scheduler konnte nicht konfiguriert werden: %s" %
			str(scheduler_result.get("errors", [])))
	_cosmetic_rng.seed = 199_204
	_build_audio()
	_juice_layer = _find_juice_layer()
	if _juice_layer != null:
		_juice_layer.visible = false
	_sync_layout()
	resized.connect(_sync_layout)
	grab_focus.call_deferred()
	set_process(true)
	set_process_input(true)
	_play_music(_title_stream)


func _build_audio() -> void:
	_title_stream = Synth.title_loop()
	_mission_stream = Synth.mission_loop()
	_sfx = {
		"move": Synth.blip(440.0), "place": Synth.blip(720.0),
		"rescue": Synth.blip(1046.5, 0.12), "crystal": Synth.blip(1318.5, 0.10),
		"launch": Synth.launch(), "lost": Synth.lost(), "victory": Synth.victory(),
		"radio": Synth.blip(780.0, 0.10), "alarm": Synth.blip(185.0, 0.16),
	}
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -12.0
	add_child(_music)
	for _i in 5:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = -7.0
		add_child(player)
		_sfx_pool.append(player)


func _find_juice_layer() -> CanvasItem:
	for candidate: Node in get_tree().root.find_children("*", "Control", true, false):
		var script := candidate.get_script() as Script
		if script != null and script.resource_path == JUICE_SCRIPT_PATH:
			return candidate as CanvasItem
	return null


func _sync_layout() -> void:
	var layout := DisplayPipeline.compute_embedded_layout(size, _video_profile,
		Vector2(VW, VH))
	_logical_scale = float(layout.get("scale", 1.0))
	_logical_origin = Vector2(layout.get("origin", Vector2.ZERO))
	queue_redraw()


func _audio_allowed() -> bool:
	var manager := get_node_or_null("/root/AudioManager")
	return manager == null or not bool(manager.get("muted"))


func _play_music(stream: AudioStream) -> void:
	if _music.stream == stream and _music.playing:
		return
	_music.stop()
	_music.stream = stream
	if _audio_allowed():
		_music.play()
	var presenter := get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("present_external"):
		presenter.call("present_external", _music, "SPACE LEMMING TROUBLE", "AMIGA · SPIEL")


func _play_sfx(id: String) -> void:
	if not _audio_allowed() or not _sfx.has(id):
		return
	var player := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = _sfx[id]
	player.play()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_frame_scheduler.begin_frame(delta)
	var pal_steps := 0
	while _frame_scheduler.consume_logic_step():
		pal_steps += 1
	var pal_delta := float(pal_steps) * FrameScheduler.PAL_STEP_SECONDS
	_mission_time += pal_delta
	_shake = maxf(0.0, _shake - pal_delta * 12.0)
	_flash = maxf(0.0, _flash - pal_delta * 2.8)
	_update_fx(pal_delta)
	if screen == Screen.BOOT:
		_boot_time += pal_delta
		var intro_time := maxf(0.0, _boot_time - DISK_BOOT_DURATION)
		var cue := 0 if intro_time < 0.85 else (
			1 if intro_time < 2.1 else (2 if intro_time < 3.2 else 3))
		if cue != _intro_cue:
			_intro_cue = cue
			if cue == 1:
				_play_sfx("radio")
			elif cue == 2:
				_play_sfx("alarm")
			elif cue == 3:
				_play_sfx("launch")
		if _boot_time >= INTRO_DURATION:
			screen = Screen.TITLE
	elif screen == Screen.PLAY and model.state == Model.State.RUNNING:
		# Das Spielmodell bleibt absichtlich 30 Hz; der gemeinsame PAL-Scheduler
		# liefert davor ein sauberes 50-Hz-Amiga-Zeitfundament.
		_accumulator = minf(0.25, _accumulator + pal_delta)
		while _accumulator >= Model.TICK_DT:
			model.tick()
			_accumulator -= Model.TICK_DT
			_consume_event()
			if model.state in [Model.State.WON, Model.State.LOST]:
				_finish_run()
				break
	queue_redraw()


func _consume_event() -> void:
	if model.event_serial == _last_event_serial:
		return
	_last_event_serial = model.event_serial
	match model.last_event:
		"rescue":
			_play_sfx("rescue")
			_flash = 0.35
			_burst(model.last_event_cell, GREEN, 12)
		"crystal":
			_play_sfx("crystal")
			_burst(model.last_event_cell, CYAN, 9)
		"lost":
			_play_sfx("lost")
			_burst(model.last_event_cell, RED, 14)
			if not _reduced_fx:
				_shake = 2.2


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A:
			_accept()
		elif event.button_index in [JOY_BUTTON_B, JOY_BUTTON_BACK]:
			_escape()
		elif event.button_index == JOY_BUTTON_START:
			if screen == Screen.PLAY and model.state == Model.State.PLANNING:
				_launch_mission()
			else:
				_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.72:
		var direction := Vector2i.ZERO
		if event.axis == JOY_AXIS_LEFT_X:
			direction.x = 1 if event.axis_value > 0 else -1
		elif event.axis == JOY_AXIS_LEFT_Y:
			direction.y = 1 if event.axis_value > 0 else -1
		_navigate(direction)
		get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if screen == Screen.PLAY:
				_place_at(_cursor_cell)
			else:
				_accept()
		KEY_SPACE:
			if screen == Screen.PLAY and model.state == Model.State.PLANNING:
				_launch_mission()
			elif screen == Screen.PLAY:
				_toggle_pause()
			else:
				_accept()
		KEY_ESCAPE: _escape()
		KEY_P: _toggle_pause()
		KEY_R:
			if screen == Screen.SIGNAL:
				_endless_seed = 100_000 + int(Time.get_ticks_msec() % 899_999)
				_play_sfx("move")
			elif screen in [Screen.PLAY, Screen.PAUSE, Screen.RESULTS]:
				_reload_current_level()
		KEY_H:
			if screen == Screen.PLAY:
				_hint = not _hint
		KEY_F3: _reduced_fx = not _reduced_fx
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if screen == Screen.PLAY:
				_selected_tool = int(event.keycode - KEY_1) as Generator.Tool
				_play_sfx("move")
		KEY_UP, KEY_W: _navigate(Vector2i.UP)
		KEY_DOWN, KEY_S: _navigate(Vector2i.DOWN)
		KEY_LEFT, KEY_A: _navigate(Vector2i.LEFT)
		KEY_RIGHT, KEY_D: _navigate(Vector2i.RIGHT)
	get_viewport().set_input_as_handled()


func _navigate(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	match screen:
		Screen.TITLE:
			if direction.y != 0:
				_menu_index = posmod(_menu_index + direction.y, 4)
		Screen.CAMPAIGN:
			var candidate := _campaign_cursor + direction.x + direction.y * 6
			if candidate >= 0 and candidate < Generator.CAMPAIGN_LEVELS:
				_campaign_cursor = candidate
		Screen.SIGNAL:
			if direction.x != 0:
				_endless_seed = clampi(_endless_seed + direction.x * 101, 1, 999_999)
			if direction.y != 0:
				_endless_difficulty = clampi(_endless_difficulty + direction.y, 0, 17)
		Screen.PLAY:
			_cursor_cell += direction
			_cursor_cell.x = clampi(_cursor_cell.x, 0, Generator.WIDTH - 1)
			_cursor_cell.y = clampi(_cursor_cell.y, 0, Generator.HEIGHT - 1)
	_play_sfx("move")


func _accept() -> void:
	match screen:
		Screen.BOOT: screen = Screen.TITLE
		Screen.TITLE:
			match _menu_index:
				0: screen = Screen.CAMPAIGN
				1: screen = Screen.SIGNAL
				2: screen = Screen.RECORDS
				3: _close_game()
		Screen.CAMPAIGN:
			if _campaign_cursor <= _unlocked_level():
				_start_level(Generator.campaign(_campaign_cursor), "campaign", _campaign_cursor)
			else:
				_play_sfx("lost")
		Screen.SIGNAL:
			_start_level(Generator.endless(_endless_seed, _endless_difficulty), "signal", -1)
		Screen.BRIEFING:
			screen = Screen.PLAY
			_play_music(_mission_stream)
		Screen.PLAY:
			_place_at(_cursor_cell)
		Screen.PAUSE: screen = Screen.PLAY
		Screen.RESULTS: _continue_after_result()
		Screen.RECORDS: screen = Screen.TITLE
		Screen.EXIT_CONFIRM:
			screen = _resume_screen
	queue_redraw()


func _escape() -> void:
	match screen:
		Screen.PLAY:
			_resume_screen = Screen.PLAY
			screen = Screen.PAUSE
		Screen.PAUSE:
			screen = Screen.BRIEFING
		Screen.BRIEFING, Screen.RESULTS:
			screen = Screen.CAMPAIGN if _mode == "campaign" else Screen.SIGNAL
			_play_music(_title_stream)
		Screen.CAMPAIGN, Screen.SIGNAL, Screen.RECORDS:
			screen = Screen.TITLE
		Screen.TITLE:
			_resume_screen = Screen.TITLE
			screen = Screen.EXIT_CONFIRM
		Screen.EXIT_CONFIRM: screen = _resume_screen
		_: screen = Screen.TITLE
	queue_redraw()


func _toggle_pause() -> void:
	if screen == Screen.PLAY:
		_resume_screen = Screen.PLAY
		screen = Screen.PAUSE
	elif screen == Screen.PAUSE:
		screen = Screen.PLAY


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var logical := _to_logical(event.position)
	_hover_cell = _cell_at(logical)
	queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	var p := _to_logical(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT and screen == Screen.PLAY:
		var remove_cell := _cell_at(p)
		if model.remove_tool(remove_cell):
			_play_sfx("place")
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(p)
	get_viewport().set_input_as_handled()


func _handle_click(p: Vector2) -> void:
	match screen:
		Screen.BOOT:
			_accept()
		Screen.TITLE:
			for i in 4:
				if Rect2(116, 137 + i * 15, 152, 13).has_point(p):
					_menu_index = i
					_accept()
					return
		Screen.CAMPAIGN:
			for i in Generator.CAMPAIGN_LEVELS:
				var rect := Rect2(45 + (i % 6) * 50,
					58 + floori(float(i) / 6.0) * 40, 42, 31)
				if rect.has_point(p):
					_campaign_cursor = i
					_accept()
					return
		Screen.BRIEFING:
			if Rect2(119, 174, 146, 22).has_point(p):
				_accept()
		Screen.PLAY:
			var cell := _cell_at(p)
			if cell.x >= 0:
				_cursor_cell = cell
				_place_at(cell)
				return
			for i in 6:
				if Rect2(296, 49 + i * 18, 80, 15).has_point(p):
					_selected_tool = i as Generator.Tool
					_play_sfx("move")
					return
			if Rect2(296, 164, 80, 22).has_point(p) and model.state == Model.State.PLANNING:
				_launch_mission()
		Screen.RESULTS, Screen.RECORDS: _accept()


func _place_at(cell: Vector2i) -> void:
	var result := model.place_tool(cell, _selected_tool)
	if bool(result.get("ok", false)):
		_play_sfx("place")
		_burst(cell, AMBER if _selected_tool < Generator.Tool.BRIDGE else CYAN, 6)
	else:
		_play_sfx("lost")


func _launch_mission() -> void:
	if model.launch():
		_accumulator = 0.0
		_last_event_serial = model.event_serial
		_play_sfx("launch")


func _cell_at(point: Vector2) -> Vector2i:
	if not GRID_RECT.has_point(point):
		return Vector2i(-1, -1)
	var local := point - GRID_ORIGIN
	return Vector2i(int(local.x / CELL), int(local.y / CELL))


func _to_logical(point: Vector2) -> Vector2:
	# InputEvents benutzen Viewport-Koordinaten, während das Spiel im eingerückten
	# Monitor-Host liegt. Die inverse Canvas-Transformation entfernt diesen Offset.
	var local_point := get_global_transform_with_canvas().affine_inverse() * point
	return (local_point - _logical_origin) / _logical_scale


func _start_level(data: Dictionary, mode: String, index: int) -> void:
	_mode = mode
	_level_index = index
	model.load_level(data)
	_cursor_cell = data.get("start", Vector2i(1, 5))
	_selected_tool = Generator.Tool.RIGHT
	_hint = false
	_last_event_serial = model.event_serial
	_run_id = "slt_%d_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec(), int(data.get("seed", 0))]
	_run_committed = false
	_result_line = ""
	_fx_particles = []
	_mission_time = 0.0
	screen = Screen.BRIEFING


func _reload_current_level() -> void:
	var data := Generator.campaign(_level_index) if _mode == "campaign" else Generator.endless(_endless_seed, _endless_difficulty)
	_start_level(data, _mode, _level_index)
	screen = Screen.PLAY
	_play_music(_mission_stream)


func _continue_after_result() -> void:
	if _mode == "campaign":
		if model.state == Model.State.WON and _level_index < Generator.CAMPAIGN_LEVELS - 1:
			_level_index += 1
			_campaign_cursor = _level_index
			_start_level(Generator.campaign(_level_index), "campaign", _level_index)
			_play_music(_title_stream)
		else:
			_campaign_cursor = clampi(_level_index, 0, Generator.CAMPAIGN_LEVELS - 1)
			screen = Screen.CAMPAIGN
			_play_music(_title_stream)
	else:
		_endless_seed = 1 + posmod(_endless_seed + 7_918, 999_999)
		_start_level(Generator.endless(_endless_seed, _endless_difficulty), "signal", -1)
		_play_music(_title_stream)


func _finish_run() -> void:
	_commit_run()
	_play_sfx("victory" if model.state == Model.State.WON else "lost")
	if model.state == Model.State.WON:
		_flash = 1.0
	screen = Screen.RESULTS


func _commit_run() -> void:
	if _run_committed:
		return
	_run_committed = true
	var completed := model.state == Model.State.WON
	var details := {
		"run_id": _run_id, "mode": _mode, "mission": str(model.level.get("name", "")),
		"seed": int(model.level.get("seed", 0)), "difficulty": int(model.level.get("difficulty", 0)),
		"rescued": model.rescued, "lost": model.lost, "stars": model.stars,
		"crystals": model.crystals,
	}
	var records := get_node_or_null("/root/AmigaGameManager")
	if records != null:
		records.call("submit_run", GAME_ID, model.score, completed, model.elapsed_ms(), details)
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager != null:
		var flags: Dictionary = game_manager.get("flags")
		flags["space_lemming_played"] = true
		if _mode == "campaign":
			var progress: Dictionary = flags.get("space_lemming_progress", {})
			var stars_by_level: Dictionary = progress.get("stars", {})
			var best_by_level: Dictionary = progress.get("best", {})
			var key := str(_level_index)
			stars_by_level[key] = maxi(int(stars_by_level.get(key, 0)), model.stars)
			best_by_level[key] = maxi(int(best_by_level.get(key, 0)), model.score)
			progress["stars"] = stars_by_level
			progress["best"] = best_by_level
			if completed:
				progress["unlocked"] = maxi(int(progress.get("unlocked", 0)), mini(Generator.CAMPAIGN_LEVELS - 1, _level_index + 1))
			flags["space_lemming_progress"] = progress
	_result_line = "MISSION GESICHERT" if completed else "RETTUNGSQUOTE VERFEHLT"


func _unlocked_level() -> int:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return 0
	var flags: Dictionary = game_manager.get("flags")
	var progress: Dictionary = flags.get("space_lemming_progress", {})
	return clampi(int(progress.get("unlocked", 0)), 0, Generator.CAMPAIGN_LEVELS - 1)


func _progress() -> Dictionary:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return {}
	var flags: Dictionary = game_manager.get("flags")
	return flags.get("space_lemming_progress", {})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	var shake_offset := Vector2.ZERO
	if _shake > 0.0 and not _reduced_fx:
		shake_offset = Vector2(round(sin(Time.get_ticks_msec() * 0.07) * _shake), round(cos(Time.get_ticks_msec() * 0.09) * _shake))
	draw_set_transform(_logical_origin + shake_offset * _logical_scale, 0.0, Vector2.ONE * _logical_scale)
	match screen:
		Screen.BOOT: _draw_boot()
		Screen.TITLE: _draw_title()
		Screen.CAMPAIGN: _draw_campaign()
		Screen.SIGNAL: _draw_signal()
		Screen.BRIEFING: _draw_briefing()
		Screen.PLAY: _draw_play()
		Screen.PAUSE:
			_draw_play()
			_draw_pause()
		Screen.RESULTS: _draw_results()
		Screen.RECORDS: _draw_records()
		Screen.EXIT_CONFIRM:
			_draw_title()
			_draw_exit_confirm()
	if _flash > 0.0 and not _reduced_fx:
		draw_rect(Rect2(0, 0, VW, VH), Color(0.45, 0.9, 1.0, _flash * 0.18))
	if screen in [Screen.PLAY, Screen.PAUSE]:
		_draw_vignette()
	AmigaVideo.draw_post_fx(self, Vector2(VW, VH), _video_profile, _mission_time,
		_reduced_fx)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_boot() -> void:
	if _boot_time < DISK_BOOT_DURATION:
		AmigaPresentation.draw_disk_boot(self, Vector2(VW, VH), _boot_time,
			DISK_BOOT_DURATION,
			CYAN, "SPACE LEMMING TROUBLE")
	else:
		Intro.draw(self, _boot_time - DISK_BOOT_DURATION, TOPAZ)


func _draw_title() -> void:
	_draw_cover(TITLE_ART, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, 63), Color(0.01, 0.02, 0.06, 0.76))
	draw_rect(Rect2(0, 128, VW, 88), Color(0.01, 0.02, 0.055, 0.86))
	_text("SPACE LEMMING", 0, 28, 25, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, INK)
	_text("TROUBLE", 0, 53, 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, BLUE)
	var entries := ["RETTUNGSKAMPAGNE", "ENDLOSSIGNAL", "MISSIONSARCHIV", "DISK AUSWERFEN"]
	for i in entries.size():
		var rect := Rect2(116, 137 + i * 15, 152, 13)
		if i == _menu_index:
			draw_rect(rect, Color(0.08, 0.18, 0.25, 0.92))
			draw_rect(rect, AMBER, false, 1.0)
		_text(("> " if i == _menu_index else "  ") + entries[i], 0, rect.position.y + 10, 8, AMBER if i == _menu_index else WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("MAUS · PFEILE · ENTER/FEUER", 0, 211, 6, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_campaign() -> void:
	_draw_space_panel("RETTUNGSKAMPAGNE", "18 GENERIERTE MISSIONEN · FORTSCHRITT WIRD GESPEICHERT")
	var unlocked := _unlocked_level()
	var stars: Dictionary = _progress().get("stars", {})
	for i in Generator.CAMPAIGN_LEVELS:
		var rect := Rect2(45 + (i % 6) * 50,
			58 + floori(float(i) / 6.0) * 40, 42, 31)
		var available := i <= unlocked
		draw_rect(rect, Color8(28, 48, 61) if available else Color8(18, 23, 30))
		draw_rect(rect, AMBER if i == _campaign_cursor else (STEEL_LIT if available else STEEL), false, 2.0 if i == _campaign_cursor else 1.0)
		_text("%02d" % (i + 1), rect.position.x, rect.position.y + 13, 10, WHITE if available else STEEL, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		var count := int(stars.get(str(i), 0))
		_text("*".repeat(count) if count > 0 else ("OPEN" if available else "LOCK"), rect.position.x, rect.position.y + 26, 6, AMBER if available else STEEL, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	var selected := Generator.campaign(_campaign_cursor)
	_text(str(selected["name"]), 0, 191, 9, CYAN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("PFEILE WAHL · ENTER START · ESC TITEL", 0, 210, 6, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_signal() -> void:
	_draw_space_panel("ENDLOSSIGNAL", "JEDER CODE ERZEUGT IMMER DIESELBE LOESBARE MISSION")
	_draw_panel(Rect2(59, 66, 266, 91), true)
	_text("SIGNAL-CODE", 0, 85, 8, CYAN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("%06d" % _endless_seed, 0, 116, 26, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, INK)
	_text("SCHWIERIGKEIT  %02d / 17" % _endless_difficulty, 0, 143, 9, WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("LINKS/RECHTS CODE · HOCH/RUNTER STUFE · R ZUFALL", 0, 181, 6, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("ENTER SIGNAL ORTEN · ESC TITEL", 0, 207, 7, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_briefing() -> void:
	_draw_cover(MISSION_ART, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, VH), Color(0.01, 0.03, 0.06, 0.72))
	_draw_panel(Rect2(43, 24, 298, 142), false)
	_text(str(model.level.get("sector", "")), 0, 47, 8, CYAN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text(str(model.level.get("name", "")), 0, 70, 17, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, INK)
	_text("RETTE MINDESTENS %d VON %d MININAUTEN" % [int(model.level.get("required", 0)), int(model.level.get("crew_total", 0))], 0, 96, 9, WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	var budgets: Dictionary = model.level.get("budgets", {})
	_text("PFEILE %d   BRUECKEN %d   SCHILDE %d" % [int(budgets.get("arrow", 0)), int(budgets.get("bridge", 0)), int(budgets.get("shield", 0))], 0, 119, 8, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("BEFEHLE VORHER ODER WAEHREND DES EINSATZES SETZEN", 0, 145, 6, STEEL_LIT, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_draw_button(Rect2(119, 174, 146, 22), "MISSION LADEN", true)
	_text("ENTER/FEUER · ESC ZURUECK", 0, 211, 6, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_play() -> void:
	# Die Missionsillustration bleibt Briefing-Art. Das laufende Spiel zeichnet
	# dagegen eine echte Lowres-Station aus Bitplane-artigen Flächen; dadurch
	# stehen Crew, Laufstege und Kulisse nun in derselben Pixelwelt.
	Art.draw_station_backdrop(self, str(model.level.get("sector", "")),
		_mission_time, AmigaVideo.is_aga(_video_profile))
	_draw_mission_ambience()
	draw_rect(Rect2(0, 0, VW, 34), Color(0.01, 0.035, 0.065, 0.95))
	_text(str(model.level.get("name", "")), 8, 14, 8, AMBER)
	_text("GERETTET %02d/%02d" % [model.rescued, int(model.level.get("required", 0))], 165, 14, 7, GREEN)
	_text("ZEIT %02d" % ceili(float(model.time_left_ticks()) / Model.TICK_RATE), 307, 14, 7, WHITE)
	_text("CREW %02d  VERLOREN %02d  KRISTALLE %02d" % [model.spawned, model.lost, model.crystals], 8, 29, 6, CREAM)
	_draw_grid()
	_draw_toolbar()
	_text("1-6 WERKZEUG · MAUS SETZT · RECHTSKLICK LOESCHT · H HINWEIS · P PAUSE", 0, 210, 5, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_grid() -> void:
	var visual_ticks := float(model.ticks)
	if model.state == Model.State.RUNNING:
		visual_ticks += clampf(_accumulator / Model.TICK_DT, 0.0, 1.0)
	Art.draw_board(self, model, GRID_ORIGIN, CELL, _hover_cell, _cursor_cell,
		_selected_tool, _hint, _mission_time, visual_ticks, _fx_particles)


func _draw_toolbar() -> void:
	Art.draw_command_console(self, Rect2(292, 39, 88, 163), _mission_time)
	_text("KOMMANDOS", 297, 48, 6, CYAN)
	var labels := ["HOCH", "RECHTS", "RUNTER", "LINKS", "BRUECKE", "SCHILD"]
	for i in 6:
		var rect := Rect2(296, 49 + i * 18, 80, 15)
		Art.draw_command_slot(self, rect, i, i == _selected_tool, _mission_time)
		_text(str(i + 1), rect.position.x + 2, rect.position.y + 10, 5,
			AMBER if i == _selected_tool else CREAM)
		_text(labels[i], rect.position.x + 16, rect.position.y + 11, 7,
			AMBER if i == _selected_tool else WHITE)
		var category := "arrow" if i < 4 else ("bridge" if i == 4 else "shield")
		_text(str(model.remaining(category)), rect.end.x - 15, rect.position.y + 11, 7, AMBER)
	if model.state == Model.State.PLANNING:
		_draw_button(Rect2(296, 164, 80, 22), "CREW LOS!", true)
	else:
		_text("EINSATZ LAEUFT", 296, 177, 7, GREEN)
	_text("SCORE %06d" % model.score, 296, 197, 7, WHITE)


func _update_fx(delta: float) -> void:
	for i in range(_fx_particles.size() - 1, -1, -1):
		var particle: Dictionary = _fx_particles[i]
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			_fx_particles.remove_at(i)
		else:
			particle["p"] = Vector2(particle["p"]) + Vector2(particle["v"]) * delta
			particle["v"] = Vector2(particle["v"]) * pow(0.06, delta)
			_fx_particles[i] = particle


func _burst(cell: Vector2i, color: Color, count: int) -> void:
	if _reduced_fx:
		return
	var center := GRID_ORIGIN + Vector2(cell) * CELL + Vector2.ONE * CELL * 0.5
	for i in count:
		var angle := TAU * float(i) / maxf(1.0, count) + _cosmetic_rng.randf_range(-0.25, 0.25)
		var speed := _cosmetic_rng.randf_range(10.0, 27.0)
		_fx_particles.append({"p": center, "v": Vector2.from_angle(angle) * speed,
			"life": _cosmetic_rng.randf_range(0.28, 0.62), "max": 0.62,
			"color": color, "size": _cosmetic_rng.randi_range(1, 2)})
	if _fx_particles.size() > 90:
		_fx_particles = _fx_particles.slice(_fx_particles.size() - 90)


func _draw_mission_ambience() -> void:
	# Animierte Stationsbeleuchtung ohne Einfluss auf Tilelogik/Kollisionen.
	var scan_y := GRID_RECT.position.y + fmod(_mission_time * 11.0, GRID_RECT.size.y)
	draw_rect(Rect2(GRID_RECT.position.x, scan_y, GRID_RECT.size.x, 1), Color(0.16, 0.75, 0.95, 0.10))
	for i in 5:
		var phase := _mission_time * (1.4 + i * 0.13) + i * 1.7
		var alpha := 0.12 + (sin(phase) * 0.5 + 0.5) * 0.12
		var lamp := Vector2(18 + i * 66, 188 - (i % 2) * 4)
		AmigaVideo.draw_ordered_dither(self, Rect2(lamp - Vector2(6, 3), Vector2(12, 6)),
			Color(1.0, 0.34, 0.08, alpha * 0.28), 0.30 + alpha)
		draw_rect(Rect2(lamp - Vector2(2, 1), Vector2(4, 2)),
			Color(1.0, 0.48, 0.12, alpha + 0.25))
		draw_rect(Rect2(lamp - Vector2(1, 1), Vector2(2, 1)), CREAM)


func _draw_vignette() -> void:
	for i in 5:
		var alpha := 0.025 + i * 0.012
		draw_rect(Rect2(i, i, VW - i * 2, VH - i * 2), Color(0, 0, 0.03, alpha), false, 1.0)


func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.68))
	_draw_panel(Rect2(90, 65, 204, 87), true)
	_text("MISSION PAUSIERT", 0, 94, 17, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("ENTER/P  WEITER", 0, 120, 8, WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("ESC  MISSION ABBRECHEN", 0, 140, 7, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_results() -> void:
	_draw_space_panel("MISSIONSBERICHT", str(model.level.get("name", "")))
	var won := model.state == Model.State.WON
	_text(_result_line, 0, 62, 15, GREEN if won else RED, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, INK)
	_draw_panel(Rect2(66, 75, 252, 86), false)
	var rows := [
		["GERETTET", "%d / %d" % [model.rescued, int(model.level.get("crew_total", 0))]],
		["VERLOREN", str(model.lost)], ["KRISTALLE", str(model.crystals)],
		["ZEIT", "%02d:%02d" % [floori(float(model.elapsed_ms()) / 60000.0),
			floori(float(model.elapsed_ms()) / 1000.0) % 60]],
		["SCORE", "%07d" % model.score], ["WERTUNG", "*".repeat(model.stars) if model.stars > 0 else "---"],
	]
	for i in rows.size():
		var y := 91.0 + i * 11.0
		_text(str(rows[i][0]), 82, y, 7, CREAM)
		_text(str(rows[i][1]), 185, y, 8, AMBER if i >= 4 else WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 116)
	var continue_label := "ENTER NAECHSTE MISSION" if _mode == "campaign" and won and _level_index < Generator.CAMPAIGN_LEVELS - 1 else (
		"ENTER MISSIONSWAHL" if _mode == "campaign" else "ENTER NEUES SIGNAL")
	_text(continue_label + " · R WIEDERHOLEN", 0, 190, 7, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("GLEICHER SEED = GLEICHE MISSION", 0, 208, 6, STEEL_LIT, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_records() -> void:
	_draw_space_panel("MISSIONSARCHIV", "PERSISTENTE REKORDE AUS ALLEN SPIELSTAENDEN")
	var manager := get_node_or_null("/root/AmigaGameManager")
	var record: Dictionary = manager.call("record", GAME_ID) if manager != null else {}
	_draw_panel(Rect2(55, 59, 274, 110), false)
	var details: Dictionary = record.get("last_details", {})
	var rows := [
		["EINSAETZE", str(record.get("plays", 0))], ["ERFOLGREICH", str(record.get("completions", 0))],
		["BESTER SCORE", "%07d" % int(record.get("best_score", 0))],
		["BESTE ZEIT", "%02d:%02d" % [
			floori(float(record.get("best_time_ms", 0)) / 60000.0),
			floori(float(record.get("best_time_ms", 0)) / 1000.0) % 60]],
		["LETZTE MISSION", str(details.get("mission", "---"))],
		["LETZTE RETTUNG", "%s / %s" % [details.get("rescued", 0), int(details.get("rescued", 0)) + int(details.get("lost", 0))]],
	]
	for i in rows.size():
		var y := 79.0 + i * 14.0
		_text(str(rows[i][0]), 70, y, 7, CREAM)
		_text(str(rows[i][1]), 185, y, 8, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 128)
	_text("ENTER/ESC ZURUECK", 0, 207, 7, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_exit_confirm() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.72))
	_draw_panel(Rect2(87, 76, 210, 65), true)
	_text("DISKETTE AUSWERFEN?", 0, 101, 14, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("ENTER = ZURUECK   ESC = ABBRUCH", 0, 129, 7, WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_space_panel(title: String, subtitle: String) -> void:
	_draw_cover(MISSION_ART, Rect2(0, 0, VW, VH))
	draw_rect(Rect2(0, 0, VW, VH), Color(0.01, 0.025, 0.055, 0.78))
	draw_rect(Rect2(0, 0, VW, 43), Color(0.01, 0.04, 0.075, 0.96))
	_text(title, 0, 22, 15, AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, INK)
	_text(subtitle, 0, 38, 6, CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_panel(rect: Rect2, selected: bool) -> void:
	draw_rect(rect, Color8(15, 30, 43, 235))
	draw_rect(rect, AMBER if selected else STEEL_LIT, false, 2.0 if selected else 1.0)


func _draw_button(rect: Rect2, label: String, selected: bool) -> void:
	draw_rect(rect, Color8(25, 53, 65) if selected else Color8(18, 32, 43))
	draw_rect(rect, AMBER if selected else STEEL, false, 1.0)
	_text(label, rect.position.x + 3, rect.position.y + 11, 7, AMBER if selected else WHITE)


func _draw_cover(texture: Texture2D, rect: Rect2) -> void:
	DisplayPipeline.draw_cover(self, texture, rect)


func _text(value: String, x: float, y: float, font_size: int, color: Color,
		alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		outline := 0, outline_color := INK) -> void:
	if outline > 0:
		draw_string_outline(TOPAZ, Vector2(x, y), value, alignment, width, font_size, outline, outline_color)
	draw_string(TOPAZ, Vector2(x, y), value, alignment, width, font_size, color)


func _close_game() -> void:
	_music.stop()
	var presenter := get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("clear_external"):
		presenter.call("clear_external", _music)
	var ui := get_node_or_null("/root/UIManager")
	if ui != null:
		ui.call("stand_up_from_computer")
	else:
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == Screen.PLAY:
		_resume_screen = Screen.PLAY
		screen = Screen.PAUSE
		queue_redraw()


func _exit_tree() -> void:
	if _music != null:
		_music.stop()
	var presenter := get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("clear_external"):
		presenter.call("clear_external", _music)
	if _juice_layer != null and is_instance_valid(_juice_layer):
		_juice_layer.visible = true


# Test-/Screenshot-Hooks: verwenden dieselben Produktionspfade wie das Spiel.
func debug_show(target: String) -> void:
	match target:
		"title": screen = Screen.TITLE
		"campaign": screen = Screen.CAMPAIGN
		"play":
			_start_level(Generator.campaign(5), "campaign", 5)
			screen = Screen.PLAY
		"results":
			_start_level(Generator.campaign(0), "campaign", 0)
			model.state = Model.State.WON
			model.rescued = int(model.level.get("crew_total", 5))
			model.stars = 3
			model.score = 12_500
			_result_line = "MISSION GESICHERT"
			screen = Screen.RESULTS
	queue_redraw()


func screen_name() -> String:
	return Screen.keys()[screen].to_lower()


func debug_video_contract() -> Dictionary:
	var report := AmigaVideo.debug_contract(_video_profile)
	report["scheduler"] = _frame_scheduler.telemetry_snapshot()
	return report
