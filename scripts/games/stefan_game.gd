class_name StefanAnthologyGame
extends Control
## Selbstbootende Vollspiel-Huelle fuer die 27 Stefan-Disketten. Jede Diskette
## konfiguriert denselben getesteten Monitor-/Rekord-Lifecycle mit einer eigenen
## Definition, Grafikzelle, Musik, Schwierigkeit und einer von neun Mechaniken.

const Catalog := preload("res://scripts/games/stefan_game_catalog.gd")
const Model := preload("res://scripts/games/stefan_game_model.gd")
const Renderer := preload("res://scripts/games/stefan_game_renderer.gd")
const AmigaPresentation := preload("res://scripts/games/amiga_game_presentation.gd")
const VideoContract := preload("res://scripts/games/amiga_video_contract.gd")
const DisplayPipeline := preload("res://scripts/games/amiga_display_pipeline.gd")
const FrameScheduler := preload("res://scripts/games/amiga_frame_scheduler.gd")
const Synth := preload("res://scripts/audio/stefan_anthology_synth.gd")
const JUICE_SCRIPT_PATH := "res://scripts/ui/juice_layer.gd"

const VW := 320.0
const VH := 200.0
const BOOT_DURATION := 2.65

enum Screen { BOOT, TITLE, BRIEFING, PLAY, PAUSE, RESULTS, RECORDS, HELP, EXIT_CONFIRM }

var disk: Disk = null
var game_id := ""
var definition: Dictionary = {}
var _video_profile: Dictionary = {}
var model := Model.new()
var _frame_scheduler := FrameScheduler.new()
var screen := Screen.BOOT
var _resume_screen := Screen.TITLE
var _texture: Texture2D = null
var _boot_time := 0.0
var _anim := 0.0
var _logical_scale := 1.0
var _logical_origin := Vector2.ZERO
var _menu_index := 0
var _result_index := 0
var _exit_index := 0
var _last_event_serial := 0
var _run_serial := 0
var _run_id := ""
var _run_committed := false
var _shake := 0.0
var _flash := 0.0
var _particles: Array[Dictionary] = []
var _cosmetic_rng := RandomNumberGenerator.new()
var _mouse_logical := Vector2(-1, -1)
var _juice_layer: CanvasItem = null

var _music: AudioStreamPlayer = null
var _title_stream: AudioStreamWAV = null
var _game_stream: AudioStreamWAV = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _sfx: Dictionary = {}


func configure_game(software_id: String) -> void:
	game_id = software_id
	definition = Catalog.game(game_id)
	if definition.is_empty():
		push_error("StefanAnthologyGame: unbekannte software_id %s" % game_id)
		return
	model.configure(definition)
	_video_profile = VideoContract.game_profile(game_id)
	var video_validation := VideoContract.validate_profile(_video_profile)
	if not bool(video_validation.get("ok", false)):
		push_error("StefanAnthologyGame: ungueltiges Amiga-Videoprofil fuer %s: %s" % [
			game_id, str(video_validation.get("errors", []))])
	var scheduler_result := _frame_scheduler.configure(_video_profile)
	if not bool(scheduler_result.get("ok", false)):
		push_error("StefanAnthologyGame: PAL-Scheduler konnte nicht konfiguriert werden: %s" %
			str(scheduler_result.get("errors", [])))
	var atlas_path := str(definition.get("atlas", ""))
	if ResourceLoader.exists(atlas_path):
		_texture = load(atlas_path) as Texture2D


func _ready() -> void:
	if definition.is_empty() and not game_id.is_empty():
		configure_game(game_id)
	if definition.is_empty():
		push_error("StefanAnthologyGame wurde ohne gueltige Definition gestartet.")
		queue_free()
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	z_index = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_cosmetic_rng.seed = int(definition.get("seed", 199101)) * 17
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
	var seed_value := int(definition.get("seed", 199101))
	var difficulty := int(definition.get("difficulty", 1))
	_title_stream = Synth.title_loop(seed_value, difficulty)
	_game_stream = Synth.game_loop(str(definition.get("mode", "shooter")), seed_value, difficulty)
	_sfx = {
		"move": Synth.blip(390.0, 0.045), "select": Synth.blip(690.0, 0.065),
		"fire": Synth.blip(920.0, 0.05), "collect": Synth.sweep(true, 0.14),
		"hit": Synth.blip(1_180.0, 0.055), "damage": Synth.noise_hit(0.16),
		"lost": Synth.sweep(false, 0.34), "victory": Synth.victory(),
		"rotate": Synth.blip(520.0, 0.06), "jump": Synth.sweep(true, 0.11),
		"turn": Synth.blip(310.0, 0.11), "perfect": Synth.blip(1_420.0, 0.08),
		"miss": Synth.noise_hit(0.075), "boot": Synth.blip(175.0, 0.06),
	}
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -13.0
	add_child(_music)
	for _i in 6:
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
	if _video_profile.is_empty():
		_logical_scale = maxf(0.01, minf(size.x / VW, size.y / VH))
		_logical_origin = ((size - Vector2(VW, VH) * _logical_scale) * 0.5).floor()
	else:
		var layout := DisplayPipeline.compute_layout(size, _video_profile, true)
		if bool(layout.get("ok", false)):
			_logical_scale = float(layout.get("scale", 1.0))
			_logical_origin = Vector2(layout.get("origin", Vector2.ZERO))
	queue_redraw()


func _audio_allowed() -> bool:
	var manager := get_node_or_null("/root/AudioManager")
	return manager == null or not bool(manager.get("muted"))


func _play_music(stream: AudioStream) -> void:
	if _music == null or stream == null or (_music.stream == stream and _music.playing):
		return
	_music.stop()
	_music.stream = stream
	if _audio_allowed():
		_music.play()
	var presenter := get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("present_external"):
		presenter.call("present_external", _music,
			str(definition.get("title", "STEFAN SOFT")), "AMIGA · DISKETTENSPIEL")


func _play_sfx(id: String) -> void:
	if not _audio_allowed() or not _sfx.has(id) or _sfx_pool.is_empty():
		return
	var player := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = _sfx[id]
	player.play()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_anim += delta
	_shake = maxf(0.0, _shake - delta * 10.0)
	_flash = maxf(0.0, _flash - delta * 2.7)
	_update_particles(delta)
	if screen == Screen.BOOT:
		var old_track := floori(_boot_time * 7.0)
		_boot_time += delta
		if floori(_boot_time * 7.0) != old_track:
			_play_sfx("boot")
		if _boot_time >= BOOT_DURATION:
			screen = Screen.TITLE
	elif screen == Screen.PLAY:
		# Einige der rundenbasierten Spiele (besonders CIRCUIT MIND) koennen
		# unmittelbar im Eingabe-Callback enden. Dann ist ``model.over`` schon
		# vor dem naechsten Frame gesetzt und der alte ``and not model.over``-
		# Guard hat den Ergebnis-/Quest-Commit fuer immer uebersprungen.
		if model.over:
			_consume_event()
			_finish_run()
		else:
			_frame_scheduler.begin_frame(delta)
			while _frame_scheduler.consume_logic_step():
				model.tick(FrameScheduler.PAL_STEP_SECONDS)
				_consume_event()
				if model.over:
					_finish_run()
					break
	queue_redraw()


func _consume_event() -> void:
	if model.event_serial == _last_event_serial:
		return
	_last_event_serial = model.event_serial
	var id := model.last_event
	match id:
		"victory":
			_play_sfx("victory"); _flash = 1.0; _burst(_event_screen_pos(), Renderer.GREEN, 26)
		"lost":
			_play_sfx("lost"); _shake = 3.0; _burst(_event_screen_pos(), Renderer.RED, 22)
		"damage", "miss":
			_play_sfx(id); _shake = 2.2; _flash = 0.42; _burst(_event_screen_pos(), Renderer.RED, 12)
		"alert":
			_play_sfx("damage"); _shake = 0.8; _flash = 0.16
			_burst(_event_screen_pos(), Renderer.RED, 6)
		"collect", "goal", "hack":
			_play_sfx("collect"); _burst(_event_screen_pos(), Renderer.accent(definition), 14)
		"hit", "fire", "boost":
			_play_sfx("fire" if id == "fire" else "hit")
		"jump": _play_sfx("jump")
		"rotate", "hint", "support": _play_sfx("rotate")
		"turn": _play_sfx("turn")
		"perfect": _play_sfx("perfect")
		_: _play_sfx("select")


func _event_screen_pos() -> Vector2:
	var p := model.last_event_pos
	if p.x <= 20.0 and p.y <= 20.0:
		match model.mode:
			"circuit": return Vector2(62, 49) + p * Vector2(39, 28)
			"miner": return Vector2(40, 40) + p * Vector2(16, 17)
			"stealth": return Vector2(32, 40) + p * Vector2(17, 17)
			"rhythm": return Vector2(82 + p.x * 51, 154)
			"strategy": return Vector2(112, 60 + p.x * 31)
	return p if Rect2(0, 0, VW, VH).has_point(p) else Vector2(160, 105)


func _burst(burst_position: Vector2, color: Color, count: int) -> void:
	for _i in count:
		var angle := _cosmetic_rng.randf_range(0.0, TAU)
		var speed := _cosmetic_rng.randf_range(12.0, 54.0)
		_particles.append({"pos": burst_position, "vel": Vector2.from_angle(angle) * speed,
			"life": _cosmetic_rng.randf_range(0.25, 0.65), "color": color})


func _update_particles(delta: float) -> void:
	for particle: Dictionary in _particles:
		particle["pos"] = (particle.get("pos", Vector2.ZERO) as Vector2) \
			+ (particle.get("vel", Vector2.ZERO) as Vector2) * delta
		particle["vel"] = (particle.get("vel", Vector2.ZERO) as Vector2) * pow(0.84, delta * 10.0)
		particle["life"] = float(particle.get("life", 0.0)) - delta
	_particles = _particles.filter(func(particle: Dictionary) -> bool:
		return float(particle.get("life", 0.0)) > 0.0)


func _start_run() -> void:
	var record := _record()
	_run_serial = int(record.get("plays", 0)) + 1
	_run_id = "%s-%d-%d" % [game_id, Time.get_ticks_usec(), _run_serial]
	_run_committed = false
	model.configure(definition)
	model.start(_run_serial)
	_last_event_serial = model.event_serial
	_frame_scheduler.reset_clock()
	_particles.clear()
	_result_index = 0
	screen = Screen.PLAY
	_play_music(_game_stream)
	_play_sfx("select")


func _finish_run() -> void:
	_commit_run()
	_result_index = 0
	screen = Screen.RESULTS
	_play_music(_title_stream)


func _commit_run() -> void:
	if _run_committed or _run_id.is_empty():
		return
	_run_committed = true
	var details := model.details()
	details["run_id"] = _run_id
	details["title"] = str(definition.get("title", game_id))
	details["year"] = int(definition.get("year", 0))
	var records := get_node_or_null("/root/AmigaGameManager")
	if records != null:
		records.call("submit_run", game_id, model.score, model.completed,
			roundi(model.elapsed * 1_000.0), details)
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager != null:
		var flags: Dictionary = game_manager.get("flags")
		flags["stefan_game_played:%s" % game_id] = true
		if model.completed:
			flags["stefan_game_completed:%s" % game_id] = true
	if model.completed:
		var quests := get_node_or_null("/root/QuestManager")
		if quests != null:
			quests.call("note_action", Catalog.completion_action(game_id))


func _record() -> Dictionary:
	var records := get_node_or_null("/root/AmigaGameManager")
	return records.call("record", game_id) if records != null else {}


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventMouseMotion:
		_mouse_logical = _to_logical(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_mouse_click(_to_logical(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		_handle_joy_button(event)
	elif event is InputEventJoypadMotion:
		_handle_joy_motion(event)


func _handle_key(event: InputEventKey) -> void:
	# D/F/J/K gehoeren im Rhythmusspiel exklusiv zu den vier Spuren. Die
	# allgemeine WASD-Auswertung darf D hier nicht vorher als "rechts" schlucken.
	if screen == Screen.PLAY and model.mode == "rhythm":
		var lane_action := _rhythm_action(event.keycode)
		if not lane_action.is_empty():
			if event.pressed and not event.echo:
				model.press(lane_action)
				_consume_event()
			get_viewport().set_input_as_handled()
			return
	var action := _direction_action(event.keycode)
	if not action.is_empty() and (screen == Screen.PLAY or not event.pressed):
		model.set_held(action, event.pressed)
		if event.pressed and not event.echo:
			model.press(action); _consume_event()
		get_viewport().set_input_as_handled()
		return
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_P:
		_toggle_pause(); get_viewport().set_input_as_handled(); return
	if event.keycode == KEY_H and screen == Screen.PLAY:
		model.press("hint"); _consume_event(); get_viewport().set_input_as_handled(); return
	if event.keycode == KEY_H and screen in [Screen.TITLE, Screen.BRIEFING]:
		_resume_screen = screen; screen = Screen.HELP; _play_sfx("select"); queue_redraw()
		get_viewport().set_input_as_handled(); return
	if event.keycode == KEY_ESCAPE:
		_escape(); get_viewport().set_input_as_handled(); return
	var horizontal := -1 if event.keycode in [KEY_LEFT, KEY_A] else (1 if event.keycode in [KEY_RIGHT, KEY_D] else 0)
	var vertical := -1 if event.keycode in [KEY_UP, KEY_W] else (1 if event.keycode in [KEY_DOWN, KEY_S] else 0)
	if horizontal != 0 or vertical != 0:
		_navigate(horizontal if horizontal != 0 else vertical)
		get_viewport().set_input_as_handled(); return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_CTRL]:
		_accept(); get_viewport().set_input_as_handled(); return
	if screen == Screen.PLAY and event.keycode in [KEY_SHIFT, KEY_TAB]:
		model.press("special"); _consume_event(); get_viewport().set_input_as_handled()


func _direction_action(keycode: Key) -> String:
	match keycode:
		KEY_LEFT, KEY_A: return "left"
		KEY_RIGHT, KEY_D: return "right"
		KEY_UP, KEY_W: return "up"
		KEY_DOWN, KEY_S: return "down"
	return ""


func _rhythm_action(keycode: Key) -> String:
	match keycode:
		KEY_D: return "lane0"
		KEY_F: return "lane1"
		KEY_J: return "lane2"
		KEY_K: return "lane3"
	return ""


func _navigate(direction: int) -> void:
	match screen:
		Screen.BOOT:
			_boot_time = BOOT_DURATION
		Screen.TITLE:
			_menu_index = posmod(_menu_index + direction, 4)
		Screen.RESULTS:
			_result_index = posmod(_result_index + direction, 2)
		Screen.EXIT_CONFIRM:
			_exit_index = posmod(_exit_index + direction, 2)
		_:
			return
	_play_sfx("move")
	queue_redraw()


func _accept() -> void:
	match screen:
		Screen.BOOT:
			if _boot_time > 0.55:
				_boot_time = BOOT_DURATION
		Screen.TITLE:
			match _menu_index:
				0: screen = Screen.BRIEFING
				1: screen = Screen.BRIEFING
				2: screen = Screen.RECORDS
				3: _open_exit(Screen.TITLE)
		Screen.BRIEFING:
			_start_run()
		Screen.PLAY:
			model.press("fire"); _consume_event()
		Screen.PAUSE:
			screen = Screen.PLAY; _play_music(_game_stream)
		Screen.RESULTS:
			if _result_index == 0:
				screen = Screen.TITLE
			else:
				screen = Screen.RECORDS
		Screen.RECORDS, Screen.HELP:
			screen = _resume_screen if screen == Screen.HELP else Screen.TITLE
		Screen.EXIT_CONFIRM:
			if _exit_index == 1:
				_close_game(); return
			screen = _resume_screen
	_play_sfx("select")
	queue_redraw()


func _escape() -> void:
	match screen:
		Screen.BOOT: _open_exit(Screen.BOOT)
		Screen.TITLE: _open_exit(Screen.TITLE)
		Screen.BRIEFING, Screen.RECORDS: screen = Screen.TITLE
		Screen.HELP: screen = _resume_screen
		Screen.PLAY: _pause_game()
		Screen.PAUSE:
			screen = Screen.TITLE; _play_music(_title_stream)
		Screen.RESULTS: screen = Screen.TITLE
		Screen.EXIT_CONFIRM: screen = _resume_screen
	_play_sfx("select")
	queue_redraw()


func _toggle_pause() -> void:
	if screen == Screen.PLAY:
		_pause_game()
	elif screen == Screen.PAUSE:
		screen = Screen.PLAY
	queue_redraw()


func _pause_game() -> void:
	screen = Screen.PAUSE
	# Ein Release kann waehrend Pause oder ausserhalb des Fensters eintreffen.
	# Der naechste Spielabschnitt beginnt deshalb ohne haengende Richtungen.
	for action: String in model.held:
		model.set_held(action, false)


func _open_exit(from: Screen) -> void:
	_resume_screen = from
	_exit_index = 0
	screen = Screen.EXIT_CONFIRM


func _to_logical(view_position: Vector2) -> Vector2:
	# _input() liefert Viewport-Koordinaten. Das Spiel sitzt jedoch im Monitor-
	# Host unter HUD und Seitenleiste; ohne inverse Canvas-Transformation lag der
	# sichtbare Mauszeiger mehrere Circuit-Felder neben dem orangenen Auswahlrahmen.
	var local_point := get_global_transform_with_canvas().affine_inverse() * view_position
	return (local_point - _logical_origin) / maxf(0.001, _logical_scale)


func _handle_mouse_click(p: Vector2) -> void:
	if not Rect2(0, 0, VW, VH).has_point(p):
		return
	match screen:
		Screen.TITLE:
			if p.y >= 156 and p.y <= 184:
				_menu_index = clampi(floori((p.x - 10.0) / 75.0), 0, 3); _accept()
		Screen.BRIEFING, Screen.RECORDS, Screen.HELP, Screen.BOOT:
			_accept()
		Screen.PLAY:
			_mouse_play(p)
		Screen.PAUSE:
			_accept()
		Screen.RESULTS:
			if p.y >= 147 and p.y <= 180:
				_result_index = 0 if p.x < 160 else 1; _accept()
		Screen.EXIT_CONFIRM:
			if p.y >= 100 and p.y <= 134:
				_exit_index = 0 if p.x < 160 else 1; _accept()


func _mouse_play(p: Vector2) -> void:
	match model.mode:
		"circuit":
			# Nur echte Kacheltreffer drehen eine Leitung. Klicks auf Titel/HUD
			# duerfen nicht heimlich die naechste Randkachel veraendern.
			var circuit_rect := Rect2(43.0, 35.0,
				Model.CIRCUIT_W * 39.0 - 3.0, Model.CIRCUIT_H * 28.0 - 3.0)
			if not circuit_rect.has_point(p):
				return
			model.cursor = Vector2i(floori((p.x - 43.0) / 39.0),
				floori((p.y - 35.0) / 28.0))
			model.press("fire")
		"strategy":
			model.selected = clampi(floori((p.y - 48.0) / 31.0), 0, 3)
			model.press("fire")
		"rhythm":
			model.press("lane%d" % clampi(floori((p.x - 60.0) / 51.0), 0, 3))
		_:
			model.press("fire")
	_consume_event()


func _handle_joy_button(event: InputEventJoypadButton) -> void:
	if not event.pressed:
		return
	match event.button_index:
		JOY_BUTTON_A: _accept()
		JOY_BUTTON_B, JOY_BUTTON_BACK: _escape()
		JOY_BUTTON_START: _toggle_pause()
		JOY_BUTTON_X:
			if screen == Screen.PLAY: model.press("special"); _consume_event()
	get_viewport().set_input_as_handled()


func _handle_joy_motion(event: InputEventJoypadMotion) -> void:
	if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		return
	var negative := "left" if event.axis == JOY_AXIS_LEFT_X else "up"
	var positive := "right" if event.axis == JOY_AXIS_LEFT_X else "down"
	if screen == Screen.PLAY:
		model.set_held(negative, event.axis_value < -0.35)
		model.set_held(positive, event.axis_value > 0.35)
	elif absf(event.axis_value) > 0.72:
		_navigate(1 if event.axis_value > 0.0 else -1)
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if definition.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color8(2, 5, 10))
	var shake_offset := Vector2.ZERO
	if _shake > 0.0:
		shake_offset = Vector2(_cosmetic_rng.randf_range(-_shake, _shake),
			_cosmetic_rng.randf_range(-_shake, _shake)).round()
	draw_set_transform(_logical_origin + shake_offset * _logical_scale, 0.0,
		Vector2(_logical_scale, _logical_scale))
	match screen:
		Screen.BOOT:
			if _boot_time < 0.72:
				AmigaPresentation.draw_disk_boot(self, Vector2(VW, VH), _boot_time, 0.72,
					Renderer.accent(definition), str(definition.get("title", "AMIGA GAME")))
			else:
				Renderer.draw_boot(self, definition,
					clampf((_boot_time - 0.72) / (BOOT_DURATION - 0.72), 0.0, 1.0))
		Screen.TITLE:
			Renderer.draw_title(self, _texture, definition, ["START", "AUFTRAG", "REKORDE", "ENDE"],
				_menu_index, _anim, _record())
		Screen.BRIEFING:
			Renderer.draw_briefing(self, _texture, definition)
		Screen.PLAY:
			Renderer.draw_play(self, _texture, definition, model, _anim, _flash, _particles)
		Screen.PAUSE:
			Renderer.draw_play(self, _texture, definition, model, _anim, _flash, _particles)
			Renderer.draw_pause(self, definition)
		Screen.RESULTS:
			Renderer.draw_results(self, _texture, definition, model, _record(), _result_index)
		Screen.RECORDS:
			Renderer.draw_records(self, definition, _record())
		Screen.HELP:
			Renderer.draw_help(self, definition)
		Screen.EXIT_CONFIRM:
			if _resume_screen == Screen.PLAY:
				Renderer.draw_play(self, _texture, definition, model, _anim, _flash, _particles)
			else:
				Renderer.draw_title(self, _texture, definition, ["START", "AUFTRAG", "REKORDE", "ENDE"],
					_menu_index, _anim, _record())
			Renderer.draw_exit_confirm(self, definition, _exit_index)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _close_game() -> void:
	if _music != null:
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
		_pause_game()
		queue_redraw()


func _exit_tree() -> void:
	if _music != null:
		_music.stop()
	var presenter := get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("clear_external"):
		presenter.call("clear_external", _music)
	if _juice_layer != null and is_instance_valid(_juice_layer):
		_juice_layer.visible = true


func screen_name() -> String:
	return Screen.keys()[screen].to_lower()


## Produktionstreuer Screenshot-/Test-Hook.
func debug_show(target: String) -> void:
	match target:
		"title": screen = Screen.TITLE
		"briefing": screen = Screen.BRIEFING
		"play": _start_run()
		"results":
			_start_run(); model.completed = true; model.over = true; model.score = 12_500
			model.result_reason = "TESTMISSION GESICHERT"; screen = Screen.RESULTS
	queue_redraw()
