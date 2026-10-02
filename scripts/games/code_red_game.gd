class_name CodeRedGame
extends "res://scripts/games/code_red_game_view.gd"

const Synth := preload("res://scripts/audio/code_red_synth.gd")

var _return_screen := Screen.TITLE
## Letzter akustisch quittierter Bildzustand (siehe _announce_screen_change).
var _last_screen := Screen.BOOT
var _archive_index := 0
var _run_id := ""
var _run_committed := false
var _juice_layer: CanvasItem = null
var _music: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _loops: Array[AudioStreamWAV] = []
var _music_level := -1
var _sfx: Dictionary = {}
var _joy_axis_latch := Vector2i.ZERO


func screen_name() -> String:
	return Screen.keys()[screen].to_lower()


func debug_show(target: String) -> void:
	var key := target.to_upper()
	var index := Screen.keys().find(key)
	if index < 0:
		return
	if model.doctrine.is_empty() and key not in ["BOOT", "TITLE", "DOCTRINE"]:
		model.choose_doctrine("technocracy")
	screen = index as Screen
	_menu_index = 0
	queue_redraw()


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
		push_error("CodeRedGame: PAL-Scheduler konnte nicht konfiguriert werden: %s" %
			str(scheduler_result.get("errors", [])))
	model.reset(1962)
	_build_audio()
	_juice_layer = _find_juice_layer()
	if _juice_layer != null:
		_juice_layer.visible = false
	_sync_layout()
	resized.connect(_sync_layout)
	grab_focus.call_deferred()
	set_process(true)
	set_process_input(true)


func _build_audio() -> void:
	for level in 4:
		_loops.append(Synth.operation_loop(level))
	# Fuenf Signale trugen bis zur AAA-Ueberarbeitung das ganze Spiel. Jetzt
	# quittiert jede Bedienebene eigenstaendig — Tastendruck, Bildwechsel,
	# verbrauchter Befehl, Messwertlauf, Eskalationsstufe, Schlussmotiv.
	_sfx = {
		"move": Synth.key_click(),
		"select": Synth.blip(),
		"confirm": Synth.confirm(),
		"failure": Synth.failure(),
		"alarm": Synth.alarm_level(1),
		"alarm_low": Synth.alarm_level(0),
		"alarm_high": Synth.alarm_level(2),
		"screen_in": Synth.screen_sweep(true),
		"screen_out": Synth.screen_sweep(false),
		"command": Synth.command_spend(),
		"readout": Synth.data_readout(),
		"region": Synth.region_select(),
		"doctrine": Synth.doctrine_chosen(),
		"plasma": Synth.plasma_surge(),
		"boot": Synth.boot_chime(),
		"end_victory": Synth.ending_motif("victory"),
		"end_mixed": Synth.ending_motif("mixed"),
		"end_chaos": Synth.ending_motif("chaos"),
	}
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -12.0
	add_child(_music)
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	_sfx_player.volume_db = -7.0
	add_child(_sfx_player)
	_update_music(true)


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


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_frame_scheduler.begin_frame(delta)
	var pal_steps := 0
	while _frame_scheduler.consume_logic_step():
		pal_steps += 1
	var pal_delta := float(pal_steps) * FrameScheduler.PAL_STEP_SECONDS
	_elapsed += pal_delta
	if screen == Screen.BOOT:
		_boot_time += pal_delta
		if _boot_time >= 3.2:
			screen = Screen.TITLE
			_menu_index = 0
	_announce_screen_change()
	_update_music()
	queue_redraw()


## Quittiert jeden Bildwechsel akustisch. Zentral statt an jeder der rund
## zwanzig Zuweisungen von `screen` — so bleibt kein Uebergang stumm, auch
## wenn spaeter Screens dazukommen.
func _announce_screen_change() -> void:
	if screen == _last_screen:
		return
	var previous := _last_screen
	_last_screen = screen
	match screen:
		Screen.TITLE:
			_play_sfx("boot" if previous == Screen.BOOT else "screen_out")
		Screen.ENDING:
			_play_sfx(_ending_sfx_id())
		Screen.EVENT:
			_play_sfx("plasma" if bool(model.pending_event.get("sky_event", false))
				else "alarm")
		Screen.DASHBOARD:
			_play_sfx("screen_out")
		Screen.BOOT:
			pass
		_:
			_play_sfx("screen_in")


func _ending_sfx_id() -> String:
	match str(model.ending):
		"victory": return "end_victory"
		"mixed": return "end_mixed"
	return "end_chaos"


func _update_music(force := false) -> void:
	var level := 0
	if not model.doctrine.is_empty():
		level = clampi(int((model.planet + model.panic + model.truth) / 75.0), 0, 3)
	if not force and level == _music_level:
		return
	_music_level = level
	_music.stop()
	_music.stream = _loops[level]
	if _audio_allowed():
		_music.play()
	var presenter := get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("present_external"):
		presenter.call("present_external", _music, "CODE RED: PROTOKOLL 2034",
			"PAULA · LAGESTUFE %d" % level)


func _audio_allowed() -> bool:
	var manager := get_node_or_null("/root/AudioManager")
	return manager == null or not bool(manager.get("muted"))


func _play_sfx(id: String) -> void:
	if not _audio_allowed() or not _sfx.has(id):
		return
	_sfx_player.stream = _sfx[id]
	_sfx_player.play()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP: _move(-1)
			KEY_DOWN: _move(1)
			KEY_LEFT: _horizontal(-1)
			KEY_RIGHT: _horizontal(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _accept()
			KEY_ESCAPE: _escape()
			KEY_TAB:
				_public_view = not _public_view
				_play_sfx("move")
				queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var point := _to_logical(event.position)
		for hit: Dictionary in _hit_rects:
			if (hit.get("rect") as Rect2).has_point(point):
				_hover_hit(hit)
				queue_redraw()
				break
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := _to_logical(event.position)
		for hit: Dictionary in _hit_rects:
			if (hit.get("rect") as Rect2).has_point(point):
				_activate_hit(hit)
				break
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP: _move(-1)
			JOY_BUTTON_DPAD_DOWN: _move(1)
			JOY_BUTTON_DPAD_LEFT: _horizontal(-1)
			JOY_BUTTON_DPAD_RIGHT: _horizontal(1)
			JOY_BUTTON_A, JOY_BUTTON_START: _accept()
			JOY_BUTTON_B, JOY_BUTTON_BACK: _escape()
			JOY_BUTTON_X:
				_public_view = not _public_view
				_play_sfx("move")
				queue_redraw()
			JOY_BUTTON_LEFT_SHOULDER: _select_region(-1)
			JOY_BUTTON_RIGHT_SHOULDER: _select_region(1)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		_handle_joy_motion(event)


func _hover_hit(hit: Dictionary) -> void:
	if str(hit.get("action", "menu")) == "region":
		_selected_region = int(hit.get("region_index", _selected_region))
	else:
		_menu_index = int(hit.get("index", _menu_index))


func _activate_hit(hit: Dictionary) -> void:
	_hover_hit(hit)
	if str(hit.get("action", "menu")) == "region":
		_play_sfx("move")
		queue_redraw()
	else:
		_accept()


func _handle_joy_motion(event: InputEventJoypadMotion) -> void:
	if event.axis == JOY_AXIS_LEFT_X:
		if absf(event.axis_value) < 0.35:
			_joy_axis_latch.x = 0
		elif absf(event.axis_value) > 0.65 and _joy_axis_latch.x == 0:
			_joy_axis_latch.x = 1 if event.axis_value > 0.0 else -1
			_horizontal(_joy_axis_latch.x)
	elif event.axis == JOY_AXIS_LEFT_Y:
		if absf(event.axis_value) < 0.35:
			_joy_axis_latch.y = 0
		elif absf(event.axis_value) > 0.65 and _joy_axis_latch.y == 0:
			_joy_axis_latch.y = 1 if event.axis_value > 0.0 else -1
			_move(_joy_axis_latch.y)


func _select_region(delta: int) -> void:
	var regions := model.region_catalog()
	_selected_region = posmod(_selected_region + delta, maxi(1, regions.size()))
	_play_sfx("region")
	queue_redraw()


func _to_logical(point: Vector2) -> Vector2:
	return (point - _logical_origin) / _logical_scale


func _item_count() -> int:
	match screen:
		Screen.TITLE: return TITLE_MENU.size()
		Screen.INTRO: return 1
		Screen.DOCTRINE: return model.doctrine_catalog().size()
		Screen.DASHBOARD: return DASH_MENU.size()
		Screen.SECTION: return model.actions_for(_section).size()
		Screen.CABINET: return model.advisor_catalog().size()
		Screen.PROJECTS: return model.project_catalog().size()
		Screen.OPTICS: return (model.current_optics().get("choices", []) as Array).size()
		Screen.ARCHIVE: return model.historical_sky_catalog().size()
		Screen.EVENT: return (model.pending_event.get("choices", []) as Array).size()
		Screen.ENDING: return 2
		Screen.EXIT_CONFIRM: return 2
		_: return 1


func _move(delta: int) -> void:
	_menu_index = posmod(_menu_index + delta, maxi(1, _item_count()))
	_play_sfx("move")
	queue_redraw()


func _horizontal(delta: int) -> void:
	if screen in [Screen.DASHBOARD, Screen.SECTION]:
		_select_region(delta)
	elif screen == Screen.MANUAL:
		_manual_page = posmod(_manual_page + delta, 4)
		_play_sfx("move")
		queue_redraw()
	else:
		_move(delta)


func _accept() -> void:
	match screen:
		Screen.BOOT:
			_boot_time = 9.0
		Screen.TITLE:
			_title_accept()
		Screen.INTRO:
			_intro_stage += 1
			_play_sfx("confirm")
			if _intro_stage >= 3:
				screen = Screen.DOCTRINE
				_menu_index = 0
		Screen.DOCTRINE:
			var doctrines := model.doctrine_catalog()
			if _menu_index < doctrines.size():
				var result := model.choose_doctrine(str(doctrines[_menu_index].get("id", "")))
				if bool(result.get("ok", false)):
					screen = Screen.DASHBOARD
					_menu_index = 0
					_play_sfx("doctrine")
		Screen.DASHBOARD:
			_dashboard_accept()
		Screen.SECTION:
			var ids := model.actions_for(_section)
			if _menu_index < ids.size():
				var region_id := _current_region_id()
				var result := model.apply_action(ids[_menu_index], region_id)
				_message = str(result.get("title", result.get("reason", "")))
				_play_sfx("command" if bool(result.get("ok", false)) else "failure")
				if bool(result.get("ok", false)):
					screen = Screen.DASHBOARD
					_menu_index = 0
		Screen.CABINET:
			var catalog := model.advisor_catalog()
			if _menu_index < catalog.size():
				var result := model.appoint_advisor(str(catalog[_menu_index].get("id", "")))
				_message = str(result.get("title", result.get("reason", "")))
				_play_sfx("command" if bool(result.get("ok", false)) else "failure")
		Screen.PROJECTS:
			var catalog := model.project_catalog()
			if _menu_index < catalog.size():
				var result := model.start_project(str(catalog[_menu_index].get("id", "")))
				_message = str(result.get("title", result.get("reason", "")))
				_play_sfx("command" if bool(result.get("ok", false)) else "failure")
				if bool(result.get("ok", false)):
					screen = Screen.DASHBOARD
					_menu_index = 0
		Screen.OPTICS:
			var choices: Array = model.current_optics().get("choices", [])
			if _menu_index < choices.size():
				var result := model.resolve_optics(str((choices[_menu_index] as Dictionary).get("id", "")))
				_message = "ERKLAERUNG PLAUSIBEL" if bool(result.get("correct", false)) else str(result.get("reason", "DATEN WIDERSPRECHEN SICH"))
				_play_sfx("command" if bool(result.get("ok", false)) else "failure")
				if bool(result.get("ok", false)):
					screen = Screen.DASHBOARD
					_menu_index = 0
		Screen.ARCHIVE:
			_archive_index = _menu_index
			_play_sfx("move")
		Screen.DEBRIEF:
			screen = Screen.EVENT if not model.pending_event.is_empty() else Screen.DASHBOARD
			_menu_index = 0
		Screen.EVENT:
			var result := model.resolve_event(_menu_index)
			if bool(result.get("ok", false)):
				_play_sfx("confirm")
				if model.ended:
					_finish_run()
				else:
					screen = Screen.DASHBOARD
					_menu_index = 0
			else:
				_message = str(result.get("reason", ""))
				_play_sfx("failure")
		Screen.MANUAL, Screen.RECORDS:
			screen = _return_screen
			_menu_index = 0
		Screen.ENDING:
			if _menu_index == 0:
				_start_new_operation()
			else:
				screen = Screen.TITLE
				_menu_index = 0
		Screen.EXIT_CONFIRM:
			if _menu_index == 0:
				_close_game()
			else:
				screen = _return_screen
				_menu_index = 0
	queue_redraw()


func _title_accept() -> void:
	match _menu_index:
		0: _start_new_operation()
		1:
			_return_screen = Screen.TITLE
			screen = Screen.MANUAL
		2:
			_return_screen = Screen.TITLE
			screen = Screen.RECORDS
		3: _open_exit(Screen.TITLE)
	_menu_index = 0


func _start_new_operation() -> void:
	var new_seed := 100000 + posmod(int(Time.get_ticks_msec()), 899999)
	model.reset(new_seed)
	_run_id = "%d:%d" % [new_seed, Time.get_ticks_usec()]
	_run_committed = false
	_elapsed = 0.0
	_public_view = false
	_intro_stage = 0
	_manual_page = 0
	_selected_region = 0
	_message = ""
	screen = Screen.INTRO
	_menu_index = 0
	var telemetry := get_node_or_null("/root/PlaytestTelemetry")
	if telemetry != null and telemetry.has_method("note_game_started"):
		telemetry.call("note_game_started", GAME_ID, {"seed": new_seed, "period": "1962"})


func _dashboard_accept() -> void:
	var entry: Dictionary = DASH_MENU[_menu_index]
	var id := str(entry.get("id", ""))
	if id == "projects":
		screen = Screen.PROJECTS
		_menu_index = 0
	elif id == "cabinet":
		screen = Screen.CABINET
		_menu_index = 0
	elif id == "optics":
		screen = Screen.OPTICS
		_menu_index = 0
	elif id == "archive":
		screen = Screen.ARCHIVE
		_menu_index = _archive_index
	elif id == "end":
		var result := model.end_year()
		if bool(result.get("ok", false)):
			_play_sfx("alarm")
			if model.ended:
				_finish_run()
			else:
				screen = Screen.DEBRIEF
				_menu_index = 0
		else:
			_message = str(result.get("reason", ""))
			_play_sfx("failure")
	else:
		_section = id
		screen = Screen.SECTION
		_menu_index = 0


func _current_region_id() -> String:
	var catalog := model.region_catalog()
	return str(catalog[_selected_region].get("id", "")) if not catalog.is_empty() else ""


func _escape() -> void:
	match screen:
		Screen.BOOT, Screen.TITLE: _open_exit(screen)
		Screen.INTRO: screen = Screen.TITLE
		Screen.DOCTRINE: screen = Screen.TITLE
		Screen.DASHBOARD: _open_exit(screen)
		Screen.SECTION, Screen.CABINET, Screen.PROJECTS, Screen.OPTICS, Screen.ARCHIVE: screen = Screen.DASHBOARD
		Screen.EVENT, Screen.DEBRIEF: pass
		Screen.MANUAL, Screen.RECORDS: screen = _return_screen
		Screen.ENDING: screen = Screen.TITLE
		Screen.EXIT_CONFIRM: screen = _return_screen
	_menu_index = 0
	queue_redraw()


func _open_exit(return_to: Screen) -> void:
	_return_screen = return_to
	screen = Screen.EXIT_CONFIRM
	_menu_index = 1


func _finish_run() -> void:
	if not model.ended:
		_message = "OPERATION LAEUFT · BIS ZUM ENDE WEITERSPIELEN"
		_play_sfx("failure")
		queue_redraw()
		return
	_commit_run()
	screen = Screen.ENDING
	_menu_index = 1
	_play_sfx("failure" if model.ending == "chaos" else "confirm")


func _commit_run() -> void:
	if _run_committed or _run_id.is_empty() or not model.ended:
		return
	_run_committed = true
	var details := {"run_id": _run_id, "ending": model.ending, "rank": model.rank(),
		"doctrine": model.doctrine, "seed": model.operation_seed, "truth_leak": snappedf(model.truth, 0.1),
		"panic": snappedf(model.panic, 0.1), "year": model.year(),
		"period": model.period_label(), "plasma_load": snappedf(model.plasma_load, 0.1),
		"action_counts": model.action_counts.duplicate(true),
		"advisor_defections": model.advisor_defections, "region_crises": model.region_crises,
		"projects_complete": model.completed_project_count(),
		"optics_correct": model.optics_correct, "optics_wrong": model.optics_wrong,
		"turning_points": model.history.slice(maxi(0, model.history.size() - 8))}
	var records := get_node_or_null("/root/AmigaGameManager")
	if records != null:
		records.call("submit_run", GAME_ID, model.score(), model.ending != "chaos",
			int(_elapsed * 1000.0), details)
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager != null:
		var flags: Dictionary = game_manager.get("flags")
		flags["code_red_played"] = true
		flags["code_red_best_leak"] = minf(float(flags.get("code_red_best_leak", 100.0)), model.truth)
		flags["code_red_seen_%s" % model.ending] = true
		if model.ending == "victory":
			flags["code_red_win_%s" % model.doctrine] = true
		if model.truth <= 10.0:
			flags["code_red_low_leak"] = true
		if int(model.action_counts.get("platform_ban", 0)) == 0 \
				and int(model.action_counts.get("network_seizure", 0)) == 0:
			flags["code_red_no_bans"] = true
		if model.completed_project_count() >= model.project_catalog().size():
			flags["code_red_all_projects"] = true
		if model.advisor_defections == 0:
			flags["code_red_loyal_cabinet"] = true
		if model.all_optics_solved_correctly():
			flags["code_red_optics_master"] = true
		if bool(flags.get("code_red_seen_victory", false)) \
				and bool(flags.get("code_red_seen_mixed", false)) \
				and bool(flags.get("code_red_seen_chaos", false)):
			flags["code_red_all_endings"] = true
	var achievements := get_node_or_null("/root/AchievementManager")
	if achievements != null:
		achievements.call("evaluate")
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null:
		quests.call("evaluate")


func _close_game() -> void:
	if not _run_committed and not _run_id.is_empty() and not model.doctrine.is_empty() and not model.ended:
		var telemetry := get_node_or_null("/root/PlaytestTelemetry")
		if telemetry != null and telemetry.has_method("note_game_abandoned"):
			telemetry.call("note_game_abandoned", GAME_ID, {"period": model.period_label(),
				"turn": model.turn, "doctrine": model.doctrine, "truth_leak": model.truth,
				"plasma_load": model.plasma_load, "action_counts": model.action_counts.duplicate(true)})
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen in [Screen.DASHBOARD, Screen.SECTION,
			Screen.CABINET, Screen.PROJECTS, Screen.OPTICS, Screen.ARCHIVE]:
		_open_exit(screen)


func _exit_tree() -> void:
	if _music != null:
		_music.stop()
	var presenter := get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("clear_external"):
		presenter.call("clear_external", _music)
	if _juice_layer != null and is_instance_valid(_juice_layer):
		_juice_layer.visible = true
