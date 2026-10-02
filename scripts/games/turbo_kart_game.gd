class_name TurboKartGame
extends "res://scripts/games/turbo_kart_game_view.gd"

const Track := preload("res://scripts/games/turbo_stunt_track.gd")
const DisplayPipeline := preload("res://scripts/games/amiga_display_pipeline.gd")
const Synth := preload("res://scripts/audio/turbo_kart_synth.gd")

# Controller-Zustand: Diese Felder werden ausschliesslich von der konkreten
# Spielklasse verwaltet. Die View-Basisklasse besitzt nur Darstellungzustand.
var _title_idle := 0.0
var _countdown_time := 0.0
var _replay_frames: Array[Dictionary] = []
var _last_replay: Dictionary = {}
var _replay_cursor := 0
var _held := {"up": false, "down": false, "left": false, "right": false, "fire": false}
var _joy_axis := Vector2.ZERO
var _joy_menu_direction := Vector2i.ZERO
var _music: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _title_stream: AudioStreamWAV
var _engine_stream: AudioStreamWAV
var _sfx_streams := {}
var _juice_layer: CanvasItem = null


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
		push_error("TurboKartGame: PAL-Scheduler konnte nicht konfiguriert werden: %s" %
			str(scheduler_result.get("errors", [])))
	_load_custom_tracks()
	_editor.begin()
	_build_audio()
	# Welt-Toasts duerfen nicht ueber das emulierte Vollbildspiel ragen. Der
	# INFOS-Ticker bleibt erhalten; nur die kurzlebigen Sprechblasen pausieren.
	_juice_layer = _find_juice_layer()
	if _juice_layer != null:
		_juice_layer.visible = false
	_sync_layout()
	resized.connect(_sync_layout)
	grab_focus.call_deferred()
	set_process(true)
	set_process_input(true)
	_play_music(_title_stream)


func _find_juice_layer() -> CanvasItem:
	# add_child() darf unbenannte Controls intern umbenennen; deshalb ueber das
	# konkrete Script statt ueber einen fragilen Node-Namen suchen.
	for candidate: Node in get_tree().root.find_children("*", "Control", true, false):
		var candidate_script := candidate.get_script() as Script
		if candidate_script != null and candidate_script.resource_path == JUICE_SCRIPT_PATH:
			return candidate as CanvasItem
	return null


func _load_custom_tracks() -> void:
	_custom_tracks = []
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return
	var flags: Dictionary = game_manager.get("flags")
	for raw: Variant in flags.get("turbo_stunt_tracks", []):
		if raw is Dictionary and bool(Track.validate(raw).get("ok", false)):
			_custom_tracks.append(Track.clone(raw))


func _track_catalog() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	for built_in: Dictionary in Model.TRACKS:
		catalog.append({"id": built_in["id"], "name": built_in["name"],
			"data": Track.preset(str(built_in["id"]))})
	for custom: Dictionary in _custom_tracks:
		catalog.append({"id": custom.get("id", "custom"),
			"name": custom.get("title", "EIGENER KURS"), "data": custom})
	return catalog


func _save_editor_track() -> void:
	var saved := _editor.current_track()
	var result := Track.validate(saved)
	if not bool(result.get("ok", false)):
		return
	var existing_id := str(saved.get("id", ""))
	if existing_id in ["", "custom"] or not existing_id.begins_with("custom_"):
		existing_id = "custom_%d_%d" % [int(saved.get("seed", 1990)), Time.get_ticks_msec()]
		saved["id"] = existing_id
		saved["title"] = "EIGENER KURS %02d" % mini(99, _custom_tracks.size() + 1)
	var replaced := false
	for i in _custom_tracks.size():
		if str(_custom_tracks[i].get("id", "")) == existing_id:
			_custom_tracks[i] = Track.clone(saved)
			replaced = true
			break
	if not replaced:
		_custom_tracks.append(Track.clone(saved))
	if _custom_tracks.size() > 8:
		_custom_tracks.pop_front()
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager != null:
		var flags: Dictionary = game_manager.get("flags")
		flags["turbo_stunt_tracks"] = _custom_tracks.duplicate(true)
	_editor.track = Track.clone(saved)
	_editor.notify_saved(str(saved.get("title", "EIGENER KURS")))


func _handle_editor_action(action: String) -> void:
	match action:
		"save":
			_save_editor_track()
			_play_sfx("go")
		"drive":
			_save_editor_track()
			_start_race(_editor.current_track())
		"exit":
			screen = Screen.TITLE
			_play_music(_title_stream)


func _sync_layout() -> void:
	var layout := DisplayPipeline.compute_embedded_layout(size, _video_profile,
		Vector2(VW, VH))
	_logical_scale = float(layout.get("scale", 1.0))
	_logical_origin = Vector2(layout.get("origin", Vector2.ZERO))
	queue_redraw()


func _build_audio() -> void:
	_title_stream = Synth.title_loop()
	_race_stream = Synth.race_loop()
	_engine_stream = Synth.engine_loop()
	_sfx_streams = {
		"count": Synth.countdown(false), "go": Synth.countdown(true),
		"boost": Synth.boost(), "impact": Synth.impact(), "skid": Synth.skid(),
		"finish": Synth.finish(),
	}
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -11.0
	add_child(_music)
	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	_engine.volume_db = -14.0
	_engine.stream = _engine_stream
	add_child(_engine)
	for _i in 4:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = -7.0
		add_child(player)
		_sfx_pool.append(player)


func _audio_allowed() -> bool:
	var manager := get_node_or_null("/root/AudioManager")
	return manager == null or not bool(manager.get("muted"))


func _play_music(stream: AudioStream) -> void:
	if _music == null:
		return
	if _music.stream == stream and _music.playing:
		return
	_music.stop()
	_music.stream = stream
	if _audio_allowed():
		_music.play()
	var music_manager := get_node_or_null("/root/MusicManager")
	if music_manager != null and music_manager.has_method("present_external"):
		music_manager.call("present_external", _music, "TURBO KART DELUXE", "AMIGA · SPIEL")


func _play_sfx(id: String) -> void:
	if not _audio_allowed() or _sfx_pool.is_empty() or not _sfx_streams.has(id):
		return
	var player := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = _sfx_streams[id]
	player.pitch_scale = 1.0
	player.play()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_frame_scheduler.begin_frame(delta)
	var pal_steps := 0
	while _frame_scheduler.consume_logic_step():
		pal_steps += 1
	var pal_delta := float(pal_steps) * FrameScheduler.PAL_STEP_SECONDS
	_shake = maxf(0.0, _shake - pal_delta * 16.0)
	match screen:
		Screen.BOOT:
			_boot_time += pal_delta
			if _boot_time >= 1.25:
				screen = Screen.TITLE
				_title_idle = 0.0
		Screen.TITLE:
			_title_idle += pal_delta
		Screen.COUNTDOWN:
			_update_countdown(pal_delta)
		Screen.RACE:
			_update_race(pal_delta)
		Screen.REPLAY:
			_update_replay(pal_delta)
	_update_engine()
	queue_redraw()


func _update_countdown(delta: float) -> void:
	_countdown_time -= delta
	if _countdown_time > 0.0:
		return
	_countdown -= 1
	if _countdown > 0:
		_countdown_time += 0.78
		_play_sfx("count")
	elif _countdown == 0:
		_countdown_time += 0.62
		_play_sfx("go")
	else:
		screen = Screen.RACE
		_race_accumulator = 0.0
		_play_music(_race_stream)
		if _audio_allowed():
			_engine.play()


func _update_race(delta: float) -> void:
	_race_accumulator = minf(_race_accumulator + delta, 0.25)
	while _race_accumulator >= Model.TICK_DT:
		var frame_controls := _controls()
		_replay_frames.append(frame_controls.duplicate())
		_visual_prev_karts = _visual_curr_karts.duplicate(true)
		model.tick(frame_controls)
		_visual_curr_karts = model.kart_states()
		_visual_model_tick = model.ticks
		_race_accumulator -= Model.TICK_DT
		_consume_model_event()
		if model.finished:
			_begin_name_entry()
			break


func _update_replay(delta: float) -> void:
	_race_accumulator = minf(_race_accumulator + delta, 0.25)
	while _race_accumulator >= Model.TICK_DT and _replay_cursor < _replay_frames.size():
		_visual_prev_karts = _visual_curr_karts.duplicate(true)
		model.tick(_replay_frames[_replay_cursor])
		_visual_curr_karts = model.kart_states()
		_visual_model_tick = model.ticks
		_replay_cursor += 1
		_race_accumulator -= Model.TICK_DT
	if _replay_cursor >= _replay_frames.size():
		screen = Screen.RESULTS
		_engine.stop()


func _controls() -> Dictionary:
	var left := bool(_held["left"]) or _joy_axis.x < -0.35
	var right := bool(_held["right"]) or _joy_axis.x > 0.35
	var up := bool(_held["up"]) or _joy_axis.y < -0.35 or _auto_gas
	var down := bool(_held["down"]) or _joy_axis.y > 0.35
	var steer := float(int(right) - int(left))
	if _steer_assist:
		var player: Dictionary = model.player_state()
		steer += clampf(-float(player.get("lateral", 0.0)) * 0.035, -0.28, 0.28)
	return {
		"throttle": 1.0 if up else 0.0,
		"brake": 1.0 if down else 0.0,
		"steer": clampf(steer, -1.0, 1.0),
		"drift": down and absf(steer) > 0.1,
		"turbo": bool(_held["fire"]),
	}


func _consume_model_event() -> void:
	if model.event_serial == _last_event_serial:
		return
	_last_event_serial = model.event_serial
	match model.last_event:
		"collision":
			_play_sfx("impact")
			if not _reduced_fx:
				_shake = 2.5
		"overtake": _play_sfx("go")
		"lap": _play_sfx("count")
		"overheat": _play_sfx("impact")
		"jump": _play_sfx("boost")
		"land": _play_sfx("go")
		"stunt": _play_sfx("finish")
		"crash":
			_play_sfx("impact")
			if not _reduced_fx:
				_shake = 4.0
		"finish": _play_sfx("finish")


func _update_engine() -> void:
	if _engine == null:
		return
	var should_play := screen in [Screen.RACE, Screen.REPLAY] and _audio_allowed()
	if should_play and not _engine.playing:
		_engine.play()
	elif not should_play and _engine.playing:
		_engine.stop()
	if should_play:
		var player: Dictionary = model.player_state()
		var ratio := float(player.get("speed", 0.0)) / maxf(1.0, float(player.get("max_speed", 100.0)))
		_engine.pitch_scale = 0.62 + ratio * 1.55
		_engine.volume_db = -18.0 + ratio * 6.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventJoypadMotion:
		_handle_joy_motion(event)
	elif event is InputEventJoypadButton:
		_handle_joy_button(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed or screen != Screen.TRACK_EDITOR:
		return
	# Viewport- in lokale Monitor-Koordinaten ruecktransformieren. Ohne diese
	# Stufe lagen Maus und sichtbarer Auswahlrahmen unter HUD/Seitenleiste versetzt.
	var local_point := get_global_transform_with_canvas().affine_inverse() * event.position
	var logical := (local_point - _logical_origin) / maxf(0.001, _logical_scale)
	_handle_editor_action(_editor.handle_click(logical, event.button_index))
	queue_redraw()
	get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	if event.echo:
		return
	var pressed := event.pressed
	# In der Rekordliste gehoeren alle Buchstaben dem Namen, auch WASD/P.
	# Sonst verschoben A/D den Cursor und S/W veraenderten den Buchstaben.
	if screen == Screen.NAME_ENTRY and event.keycode >= KEY_A and event.keycode <= KEY_Z:
		if pressed:
			_set_initial_from_key(event)
		get_viewport().set_input_as_handled()
		return
	if screen == Screen.TRACK_EDITOR:
		if pressed:
			_handle_editor_action(_editor.handle_key(event.keycode))
			queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if pressed and screen == Screen.RESULTS and event.keycode == KEY_R and not _last_replay.is_empty():
		_start_replay()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_UP, KEY_W: _held["up"] = pressed
		KEY_DOWN, KEY_S: _held["down"] = pressed
		KEY_LEFT, KEY_A: _held["left"] = pressed
		KEY_RIGHT, KEY_D: _held["right"] = pressed
		KEY_SPACE, KEY_CTRL:
			_held["fire"] = pressed
			if pressed and screen != Screen.RACE:
				_accept()
		KEY_ENTER, KEY_KP_ENTER:
			if pressed:
				_accept()
		KEY_ESCAPE:
			if pressed:
				_escape()
		KEY_P:
			if pressed:
				_toggle_pause()
		KEY_F1:
			if pressed:
				_auto_gas = not _auto_gas
				_result_message = "AUTO-GAS %s" % ("AN" if _auto_gas else "AUS")
		KEY_F2:
			if pressed:
				_steer_assist = not _steer_assist
				_result_message = "LENKHILFE %s" % ("AN" if _steer_assist else "AUS")
		KEY_F3:
			if pressed:
				_reduced_fx = not _reduced_fx
				_result_message = "EFFEKTE %s" % ("REDUZIERT" if _reduced_fx else "VOLL")
		KEY_BACKSPACE:
			if pressed and screen == Screen.NAME_ENTRY:
				_initial_cursor = maxi(0, _initial_cursor - 1)
		_:
			if pressed and screen == Screen.NAME_ENTRY:
				_set_initial_from_key(event)
	if pressed:
		_handle_navigation_key(event.keycode)
	get_viewport().set_input_as_handled()


func _set_initial_from_key(event: InputEventKey) -> void:
	var code := event.keycode
	if code >= KEY_A and code <= KEY_Z:
		_initials[_initial_cursor] = char(code)
		_initial_cursor = mini(2, _initial_cursor + 1)
		_play_sfx("count")


func _handle_navigation_key(keycode: Key) -> void:
	if keycode not in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_S, KEY_A, KEY_D]:
		return
	var vertical := -1 if keycode in [KEY_UP, KEY_W] else (1 if keycode in [KEY_DOWN, KEY_S] else 0)
	var horizontal := -1 if keycode in [KEY_LEFT, KEY_A] else (1 if keycode in [KEY_RIGHT, KEY_D] else 0)
	match screen:
		Screen.TITLE:
			if vertical != 0:
				_menu_index = posmod(_menu_index + vertical, 6)
				_play_sfx("count")
		Screen.GARAGE:
			if vertical != 0:
				_garage_focus = posmod(_garage_focus + vertical, 3)
				_play_sfx("count")
			if horizontal != 0:
				if _garage_focus == 0:
					_setup_index = posmod(_setup_index + horizontal, Model.SETUPS.size())
				elif _garage_focus == 1:
					_track_index = posmod(_track_index + horizontal, _track_catalog().size())
				else:
					_auto_gas = not _auto_gas
				_play_sfx("count")
		Screen.EXIT_CONFIRM:
			if vertical != 0:
				_exit_index = posmod(_exit_index + vertical, 3)
				_play_sfx("count")
		Screen.NAME_ENTRY:
			if horizontal != 0:
				_initial_cursor = posmod(_initial_cursor + horizontal, 3)
			if vertical != 0:
				var current: int = str(_initials[_initial_cursor]).unicode_at(0) - 65
				_initials[_initial_cursor] = char(65 + posmod(current - vertical, 26))


func _handle_joy_motion(event: InputEventJoypadMotion) -> void:
	if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		return
	var value := 0.0 if absf(event.axis_value) < 0.28 else event.axis_value
	var component := 0 if event.axis == JOY_AXIS_LEFT_X else 1
	if event.axis == JOY_AXIS_LEFT_X:
		_joy_axis.x = value
	elif event.axis == JOY_AXIS_LEFT_Y:
		_joy_axis.y = value
	# Menues reagieren einmal je bewusster Auslenkung; kleine Analogschwankungen
	# duerfen nicht durch mehrere Optionen springen. Zum Neuansetzen loslassen.
	if absf(value) < 0.35:
		_joy_menu_direction[component] = 0
	elif absf(value) > 0.72:
		var direction := 1 if value > 0.0 else -1
		if direction != _joy_menu_direction[component]:
			_joy_menu_direction[component] = direction
			var keycode := (KEY_RIGHT if direction > 0 else KEY_LEFT) if component == 0 \
				else (KEY_DOWN if direction > 0 else KEY_UP)
			_handle_navigation_key(keycode)
	get_viewport().set_input_as_handled()


func _handle_joy_button(event: InputEventJoypadButton) -> void:
	var directions := {
		JOY_BUTTON_DPAD_UP: ["up", KEY_UP], JOY_BUTTON_DPAD_DOWN: ["down", KEY_DOWN],
		JOY_BUTTON_DPAD_LEFT: ["left", KEY_LEFT], JOY_BUTTON_DPAD_RIGHT: ["right", KEY_RIGHT],
	}
	if directions.has(event.button_index):
		var direction: Array = directions[event.button_index]
		_held[direction[0]] = event.pressed
		if event.pressed:
			_handle_navigation_key(direction[1])
	elif event.button_index == JOY_BUTTON_A:
		_held["fire"] = event.pressed
		if event.pressed and screen != Screen.RACE:
			_accept()
	elif event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_BACK]:
		_escape()
	elif event.pressed and event.button_index == JOY_BUTTON_START:
		_toggle_pause()
	get_viewport().set_input_as_handled()


func _accept() -> void:
	_title_idle = 0.0
	match screen:
		Screen.BOOT:
			screen = Screen.TITLE
		Screen.TITLE:
			match _menu_index:
				0:
					_mode = "race"
					screen = Screen.GARAGE
				1:
					_mode = "time_attack"
					screen = Screen.GARAGE
				2:
					_mode = "training"
					screen = Screen.GARAGE
				3:
					_editor.begin(_custom_tracks.back() if not _custom_tracks.is_empty() else {})
					screen = Screen.TRACK_EDITOR
				4:
					screen = Screen.HIGHSCORES
				5:
					_close_game()
		Screen.GARAGE:
			_start_race()
		Screen.HIGHSCORES:
			screen = Screen.TITLE
		Screen.PAUSE:
			screen = _resume_screen
		Screen.EXIT_CONFIRM:
			match _exit_index:
				0: screen = _resume_screen
				1:
					screen = Screen.TITLE
					_play_music(_title_stream)
				2: _close_game()
		Screen.NAME_ENTRY:
			_commit_run()
			screen = Screen.RESULTS
		Screen.RESULTS:
			screen = Screen.GARAGE


func _escape() -> void:
	match screen:
		Screen.RACE, Screen.COUNTDOWN:
			_resume_screen = screen
			screen = Screen.PAUSE
		Screen.PAUSE:
			_exit_index = 0
			screen = Screen.EXIT_CONFIRM
		Screen.EXIT_CONFIRM:
			screen = _resume_screen
		Screen.GARAGE, Screen.TRACK_EDITOR, Screen.HIGHSCORES, Screen.RESULTS:
			screen = Screen.TITLE
		Screen.NAME_ENTRY:
			_commit_run()
			screen = Screen.RESULTS
		Screen.TITLE:
			_resume_screen = Screen.TITLE
			_exit_index = 0
			screen = Screen.EXIT_CONFIRM
		Screen.REPLAY:
			screen = Screen.RESULTS
			_engine.stop()
		_:
			screen = Screen.TITLE


func _toggle_pause() -> void:
	if screen in [Screen.RACE, Screen.COUNTDOWN]:
		_resume_screen = screen
		screen = Screen.PAUSE
	elif screen == Screen.PAUSE:
		screen = _resume_screen


func _start_race(custom_track: Dictionary = {}) -> void:
	_clear_controls()
	var setups := ["weasel", "falcon", "block"]
	var catalog := _track_catalog()
	var selected: Dictionary = catalog[clampi(_track_index, 0, catalog.size() - 1)]
	var data := Track.clone(custom_track) if not custom_track.is_empty() else Track.clone(selected["data"])
	var track := str(data.get("id", selected["id"]))
	var run_seed := 1990 + _track_index * 101 + _setup_index * 17 + int(Time.get_ticks_msec() % 997)
	model.start_run(track, setups[_setup_index], _mode, run_seed, data)
	_reset_visual_state()
	_run_id = "tkd_%d_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec(), run_seed]
	_run_committed = false
	_initials = ["A", "C", "E"]
	_initial_cursor = 0
	_countdown = 3
	_countdown_time = 0.32
	_race_accumulator = 0.0
	_last_event_serial = model.event_serial
	_replay_frames = []
	_replay_cursor = 0
	_result_message = ""
	screen = Screen.COUNTDOWN
	_play_music(_race_stream)
	_play_sfx("count")


func _begin_name_entry() -> void:
	if screen == Screen.NAME_ENTRY or screen == Screen.RESULTS:
		return
	_clear_controls()
	screen = Screen.NAME_ENTRY
	_engine.stop()
	_play_sfx("finish")
	_result_message = "NEUER LAUF — NAME IN DIE LISTE"
	_last_replay = {
		"track": Track.clone(model.track_data), "track_id": model.track_id,
		"setup": model.setup_id, "mode": model.mode, "seed": model.run_seed,
		"frames": _replay_frames.duplicate(true),
	}


func _start_replay() -> void:
	if _last_replay.is_empty():
		return
	_replay_frames = (_last_replay.get("frames", []) as Array).duplicate(true)
	_replay_cursor = 0
	model.start_run(str(_last_replay.get("track_id", "parking")),
		str(_last_replay.get("setup", "weasel")), str(_last_replay.get("mode", "race")),
		int(_last_replay.get("seed", 1990)), _last_replay.get("track", {}))
	_reset_visual_state()
	_race_accumulator = 0.0
	_result_message = "WIEDERHOLUNG · ESC ZUM BERICHT"
	screen = Screen.REPLAY
	_play_music(_race_stream)
	if _audio_allowed():
		_engine.play()


func _commit_run() -> void:
	if _run_committed or _run_id == "":
		return
	_run_committed = true
	var initials := "".join(_initials)
	var details := {
		"run_id": _run_id, "initials": initials, "track": model.track_id,
		"setup": model.setup_id, "mode": model.mode, "place": model.player_place,
		"collisions": model.collisions, "overtakes": model.overtakes,
		"clean_sectors": model.clean_sectors, "combo": model.combo,
	}
	var record_manager := get_node_or_null("/root/AmigaGameManager")
	var accepted: Dictionary = record_manager.call("submit_run", GAME_ID, model.score,
		true, model.elapsed_ms(), details) if record_manager != null else {}
	_result_message = "REKORD GESPEICHERT" if bool(accepted.get("accepted", false)) else "LAUF BEREITS GEWERTET"
	var game_manager := get_node_or_null("/root/GameManager")
	var flags: Dictionary = game_manager.get("flags") if game_manager != null else {}
	flags["turbo_kart_played"] = true
	# Ein beendetes Rennen ist ein echter Quest-Fakt. Die nächste Stufe muss
	# sofort sichtbar werden und darf nicht erst durch Schlafen, Reisen oder
	# irgendeinen späteren Effekt zufällig ausgewertet werden.
	var quest_manager := get_node_or_null("/root/QuestManager")
	if quest_manager != null:
		quest_manager.call("evaluate")
	if model.score > MIKE_SCORE and not bool(flags.get("turbo_kart_mike_beaten", false)):
		flags["turbo_kart_mike_beaten"] = true
		var npc_manager := get_node_or_null("/root/NPCManager")
		var stats := get_node_or_null("/root/PlayerStats")
		var memories := get_node_or_null("/root/MemoryManager")
		if npc_manager != null:
			npc_manager.call("change_trust", "npc_mike", 2)
		if stats != null:
			stats.call("change_stat", "ruf", 1)
		if memories != null:
			memories.call("record_once", "turbo_kart_mike_beaten",
				"Mikes Turbo-Kart-Rekord geschlagen — danach war es kurz ganz still im Zimmer")
		_result_message = "MIKES REKORD!  +2 VERTRAUEN  +1 RUF"


func _close_game() -> void:
	if _music != null:
		_music.stop()
	var music_manager := get_node_or_null("/root/MusicManager")
	if music_manager != null and music_manager.has_method("clear_external"):
		music_manager.call("clear_external", _music)
	if _engine != null:
		_engine.stop()
	var ui := get_node_or_null("/root/UIManager")
	if ui != null:
		ui.call("stand_up_from_computer")
	else:
		queue_free()


func _clear_controls() -> void:
	for action: String in _held:
		_held[action] = false
	_joy_axis = Vector2.ZERO
	_joy_menu_direction = Vector2i.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Releases ausserhalb des Fensters werden nicht verlaesslich zugestellt.
		# Ohne Reset blieben Gas/Lenkung/Turbo beim Fortsetzen dauerhaft aktiv.
		_clear_controls()
		if screen in [Screen.RACE, Screen.COUNTDOWN]:
			_resume_screen = screen
			screen = Screen.PAUSE
			queue_redraw()


func _exit_tree() -> void:
	if _music != null:
		_music.stop()
	var music_manager := get_node_or_null("/root/MusicManager")
	if music_manager != null and music_manager.has_method("clear_external"):
		music_manager.call("clear_external", _music)
	if _engine != null:
		_engine.stop()
	if _juice_layer != null and is_instance_valid(_juice_layer):
		_juice_layer.visible = true
