extends Control
## TURBO KART DELUXE — vollstaendiges, selbstbootendes In-Universe-Amiga-Spiel.
## Eigene Mechanik, Grafik und prozedurale Klangwelt; keine fremden Spielassets.

const Model := preload("res://scripts/games/turbo_kart_model.gd")
const StuntEditor := preload("res://scripts/games/turbo_stunt_editor.gd")
const StuntRenderer := preload("res://scripts/games/turbo_stunt_renderer.gd")
const AmigaPresentation := preload("res://scripts/games/amiga_game_presentation.gd")
const AmigaVideo := preload("res://scripts/games/standalone_amiga_video.gd")
const FrameScheduler := preload("res://scripts/games/amiga_frame_scheduler.gd")
const TITLE_BACKGROUND := preload("res://assets/ui/games/turbo_kart/stunt_title_background_v01.png")
var TOPAZ: Font = load("res://assets/fonts/Topaz_a500_ui.ttf")
const JUICE_SCRIPT_PATH := "res://scripts/ui/juice_layer.gd"

const VW := 320.0
const VH := 200.0
const MIKE_SCORE := 72_500
const GAME_ID := "turbo_kart_deluxe"

const C_BLACK := Color8(0, 0, 0)
const C_INK := Color8(34, 32, 52)
const C_ROAD_LIGHT := Color8(105, 106, 106)
const C_WHITE := StuntRenderer.C_WHITE
const C_CREAM := StuntRenderer.C_CREAM
const C_AMBER := StuntRenderer.C_AMBER
const C_ORANGE := StuntRenderer.C_ORANGE
const C_RED := StuntRenderer.C_RED
const C_RED_DARK := Color8(172, 50, 50)
const C_CYAN := StuntRenderer.C_CYAN
const C_GREEN := StuntRenderer.C_GREEN

enum Screen {
	BOOT, TITLE, GARAGE, TRACK_EDITOR, HIGHSCORES, COUNTDOWN, RACE,
	REPLAY, PAUSE, EXIT_CONFIRM, NAME_ENTRY, RESULTS,
}

var disk: Disk = null
var model := Model.new()
var _editor := StuntEditor.new()
var _renderer := StuntRenderer.new()
var screen := Screen.BOOT
var _resume_screen := Screen.RACE
var _boot_time := 0.0
var _menu_index := 0
var _garage_focus := 0
var _setup_index := 0
var _track_index := 0
var _mode := "race"
var _countdown := 3
var _race_accumulator := 0.0
var _last_event_serial := 0
var _run_id := ""
var _run_committed := false
var _initials := ["A", "C", "E"]
var _initial_cursor := 0
var _result_message := ""
var _exit_index := 0
var _auto_gas := false
var _steer_assist := false
var _reduced_fx := false
var _custom_tracks: Array[Dictionary] = []
var _visual_prev_karts: Array = []
var _visual_curr_karts: Array = []
var _visual_model_tick := -1

var _logical_scale := 1.0
var _logical_origin := Vector2.ZERO
var _video_profile: Dictionary = {}
var _frame_scheduler := FrameScheduler.new()
var _shake := 0.0

var _race_stream: AudioStreamWAV


# Vom Controller bereitgestellte Schnittstellen. Die View bleibt separat
# kompilierbar; die abgeleitete Spielklasse liefert Katalog und Audiowechsel.
func _track_catalog() -> Array[Dictionary]:
	return []


func _play_music(_stream: AudioStream) -> void:
	pass


func debug_video_contract() -> Dictionary:
	var report := AmigaVideo.debug_contract(_video_profile)
	report["scheduler"] = _frame_scheduler.telemetry_snapshot()
	return report


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BLACK)
	var shake_offset := Vector2.ZERO
	if _shake > 0.0 and not _reduced_fx:
		shake_offset = Vector2(round(sin(Time.get_ticks_msec() * 0.08) * _shake),
			round(cos(Time.get_ticks_msec() * 0.11) * _shake * 0.6))
	draw_set_transform(_logical_origin + shake_offset * _logical_scale, 0.0, Vector2.ONE * _logical_scale)
	draw_rect(Rect2(0, 0, VW, VH), C_INK)
	match screen:
		Screen.BOOT: _draw_boot()
		Screen.TITLE: _draw_title()
		Screen.GARAGE: _draw_garage()
		Screen.TRACK_EDITOR: _editor.draw(self, TOPAZ)
		Screen.HIGHSCORES: _draw_highscores()
		Screen.COUNTDOWN, Screen.RACE, Screen.REPLAY: _draw_race()
		Screen.PAUSE:
			_draw_race()
			_draw_pause()
		Screen.EXIT_CONFIRM:
			if _resume_screen in [Screen.RACE, Screen.COUNTDOWN]:
				_draw_race()
			else:
				_draw_title()
			_draw_exit_confirm()
		Screen.NAME_ENTRY: _draw_name_entry()
		Screen.RESULTS: _draw_results()
	AmigaVideo.draw_post_fx(self, Vector2(VW, VH), _video_profile,
		float(Time.get_ticks_msec()) * 0.001, _reduced_fx)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_letterbox_mask()


func _draw_letterbox_mask() -> void:
	# Prozedurale Polygone duerfen weder in die schwarzen Pixelränder noch in die
	# umgebende Zimmer-UI bluten. Die Maske liegt bewusst nach dem Logical-Draw.
	var content := Rect2(_logical_origin, Vector2(VW, VH) * _logical_scale)
	if content.position.x > 0.0:
		draw_rect(Rect2(0, 0, content.position.x, size.y), C_BLACK)
	if content.end.x < size.x:
		draw_rect(Rect2(content.end.x, 0, size.x - content.end.x, size.y), C_BLACK)
	if content.position.y > 0.0:
		draw_rect(Rect2(content.position.x, 0, content.size.x, content.position.y), C_BLACK)
	if content.end.y < size.y:
		draw_rect(Rect2(content.position.x, content.end.y, content.size.x,
			size.y - content.end.y), C_BLACK)


func _draw_boot() -> void:
	if _boot_time < 0.72:
		AmigaPresentation.draw_disk_boot(self, Vector2(VW, VH), _boot_time, 0.72,
			C_ORANGE, "TURBO STUNT DELUXE")
		return
	draw_rect(Rect2(0, 0, VW, VH), C_BLACK)
	var phase := _boot_time - 0.72
	var blink := int(phase * 5.0) % 2 == 0
	_text("MAGNETOSTAR SOFTWARE", 0, 66, 12, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("PRESENTS", 0, 87, 8, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	if blink:
		_text("LOADING TRACK DATA...", 0, 127, 7, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)
	var width := clampf(phase / 0.48, 0.0, 1.0) * 140.0
	draw_rect(Rect2(90, 143, 140, 5), C_INK)
	draw_rect(Rect2(91, 144, width - 2.0, 3), C_ORANGE)


func _draw_title() -> void:
	# Projektgebundenes 1586x992-Motiv; nahezu exakt 8:5, Importfilter Nearest.
	draw_texture_rect_region(TITLE_BACKGROUND, Rect2(0, 0, VW, VH), Rect2(0, 0, 1586, 992))
	draw_rect(Rect2(0, 0, VW, 56), Color(0.04, 0.03, 0.08, 0.78))
	draw_rect(Rect2(0, 142, VW, 58), Color(0.03, 0.025, 0.05, 0.82))
	_text("TURBO", 0, 24, 24, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, C_RED_DARK)
	_text("STUNT DELUXE", 0, 48, 17, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, C_INK)
	var entries := ["MEISTERSCHAFT", "ZEITJAGD", "TRAINING", "KURS BAUEN", "HIGHSCORES", "DISK AUSWERFEN"]
	for i in entries.size():
		var y := 147.0 + i * 8.2
		if i == _menu_index:
			draw_rect(Rect2(96, y - 7, 128, 9), Color(0.1, 0.08, 0.12, 0.82))
			_text("> " + entries[i] + " <", 0, y, 7, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)
		else:
			_text(entries[i], 0, y, 7, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("PFEILE/JOYSTICK · FEUER/ENTER · F1-F3 HILFEN", 0, 199, 5, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_garage() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color8(25, 27, 31))
	_draw_checker(Rect2(0, 0, VW, 18), C_RED_DARK, C_CREAM, 8)
	_text("BOXENGASSE", 10, 14, 12, C_WHITE, HORIZONTAL_ALIGNMENT_LEFT, 180)
	_text("%s" % ("MEISTERSCHAFT" if _mode == "race" else ("ZEITJAGD" if _mode == "time_attack" else "TRAINING")),
		178, 14, 8, C_AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 132)
	var setups := ["weasel", "falcon", "block"]
	var setup: Dictionary = Model.SETUPS[setups[_setup_index]]
	var catalog := _track_catalog()
	var track: Dictionary = catalog[clampi(_track_index, 0, catalog.size() - 1)]
	_draw_panel(Rect2(14, 30, 138, 72), _garage_focus == 0)
	_text("KART-SETUP", 22, 43, 7, C_CYAN)
	_text("<  %s  >" % str(setup["name"]), 16, 63, 13, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, 134)
	_stat_bar("TEMPO", 26, 77, float(setup["max_speed"]) / 110.0, C_RED)
	_stat_bar("ANZUG", 26, 87, float(setup["accel"]) / 50.0, C_ORANGE)
	_stat_bar("GRIP", 26, 97, float(setup["handling"]) / 1.25, C_GREEN)
	_draw_panel(Rect2(168, 30, 138, 72), _garage_focus == 1)
	_text("KURS", 176, 43, 7, C_CYAN)
	_text("< %s >" % str(track["name"]), 170, 63, 9, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, 134)
	_editor.draw_minimap(self, Rect2(186, 68, 100, 28), track["data"])
	_draw_panel(Rect2(14, 112, 292, 48), _garage_focus == 2)
	_text("FAHRHILFEN", 22, 125, 7, C_CYAN)
	_text("AUTO-GAS: %s" % ("AN" if _auto_gas else "AUS"), 24, 140, 8, C_WHITE)
	_text("LENKHILFE F2: %s" % ("AN" if _steer_assist else "AUS"), 128, 140, 8, C_WHITE)
	_text("FX F3: %s" % ("RED." if _reduced_fx else "VOLL"), 246, 140, 8, C_WHITE)
	_text("^v BEREICH   «» WAHL   FEUER/ENTER START   ESC ZURUECK", 0, 178, 6, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("DRIFT: RUNTER + LENKEN   TURBO: FEUER", 0, 192, 7, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_highscores() -> void:
	draw_rect(Rect2(0, 0, VW, VH), C_INK)
	_draw_checker(Rect2(0, 0, VW, 20), C_RED_DARK, C_WHITE, 10)
	_text("HALL OF RUBBER", 0, 44, 18, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, C_BLACK)
	var manager := get_node_or_null("/root/AmigaGameManager")
	var rec: Dictionary = manager.call("record", GAME_ID) if manager != null else {}
	var player_score := int(rec.get("best_score", 0))
	var player_time := int(rec.get("best_time_ms", 0))
	var initials := "DU"
	var details: Dictionary = rec.get("last_details", {})
	if not details.is_empty():
		initials = str(details.get("initials", "DU"))
	var rows := [
		["1", "MIK", MIKE_SCORE, "PARKPLATZ"],
		["2", initials, player_score, str(details.get("track", "---")).to_upper()],
		["3", "JUL", 58_400, "KIESGRUBE"],
		["4", "NCO", 51_900, "GUETERHOF"],
	]
	for i in rows.size():
		var y := 72.0 + i * 22.0
		draw_rect(Rect2(36, y - 13, 248, 18), Color8(48, 52, 72) if i % 2 == 0 else Color8(35, 38, 56))
		_text(str(rows[i][0]), 44, y, 10, C_CYAN)
		_text(str(rows[i][1]), 74, y, 10, C_WHITE)
		_text("%07d" % int(rows[i][2]), 124, y, 10, C_AMBER)
		_text(str(rows[i][3]), 208, y, 7, C_CREAM)
	if player_time > 0:
		_text("DEINE BESTZEIT  %s" % _format_time(player_time), 0, 171, 8, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("FEUER/ENTER/ESC ZURUECK", 0, 193, 6, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_race() -> void:
	_renderer.draw(self, TOPAZ, model, _countdown, screen == Screen.COUNTDOWN,
		_result_message, _reduced_fx, _visual_snapshot(), _video_profile)


func _reset_visual_state() -> void:
	_visual_curr_karts = model.kart_states()
	_visual_prev_karts = _visual_curr_karts.duplicate(true)
	_visual_model_tick = model.ticks
	_renderer.reset_camera()


func _visual_snapshot() -> Dictionary:
	# Debug-/Proof-Hooks duerfen das Modell direkt vorspulen. Dann ist ein roher
	# aktueller Snapshot besser als eine veraltete Interpolation vom Rennstart.
	if _visual_model_tick != model.ticks or _visual_curr_karts.size() != model.kart_states().size():
		_visual_curr_karts = model.kart_states()
		_visual_prev_karts = _visual_curr_karts.duplicate(true)
		_visual_model_tick = model.ticks
	var alpha := clampf(_race_accumulator / Model.TICK_DT, 0.0, 1.0)
	if screen == Screen.COUNTDOWN:
		alpha = 1.0
	var rendered: Array[Dictionary] = []
	for i in _visual_curr_karts.size():
		var current: Dictionary = _visual_curr_karts[i]
		var previous: Dictionary = _visual_prev_karts[i] if i < _visual_prev_karts.size() \
			else current
		rendered.append(_interpolate_kart(previous, current, alpha))
	var player: Dictionary = {}
	for kart: Dictionary in rendered:
		if bool(kart.get("player", false)):
			player = kart
			break
	return {"player": player, "karts": rendered, "alpha": alpha}


func _interpolate_kart(previous: Dictionary, current: Dictionary, alpha: float) -> Dictionary:
	var result := current.duplicate(true)
	for key in ["progress", "lateral", "lateral_speed", "speed", "turbo", "heat",
			"height", "vertical_speed", "pitch"]:
		result[key] = lerpf(float(previous.get(key, current.get(key, 0.0))),
			float(current.get(key, 0.0)), alpha)
	for key in ["heading_error", "roll"]:
		result[key] = lerp_angle(float(previous.get(key, current.get(key, 0.0))),
			float(current.get(key, 0.0)), alpha)
	return result


func _draw_pause() -> void:
	draw_rect(Rect2(56, 54, 208, 92), Color(0.03, 0.025, 0.07, 0.95))
	draw_rect(Rect2(56, 54, 208, 92), C_CYAN, false, 2.0)
	_text("PAUSE", 0, 81, 20, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, C_BLACK)
	_text("FEUER / P  WEITER", 0, 105, 8, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("ESC  RENNEN VERLASSEN", 0, 120, 7, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("F1 AUTO-GAS · F2 LENKHILFE · F3 FX", 0, 137, 6, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_exit_confirm() -> void:
	draw_rect(Rect2(46, 48, 228, 108), Color(0.02, 0.02, 0.04, 0.97))
	draw_rect(Rect2(46, 48, 228, 108), C_AMBER, false, 2.0)
	_text("BOXENFUNK", 0, 69, 13, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("LAUFENDE RUNDE WIRD NICHT GEWERTET", 0, 86, 6, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)
	var options := ["WEITERFAHREN", "ZUM TITEL", "DISK AUSWERFEN"]
	for i in options.size():
		var y := 106.0 + i * 14.0
		_text(("> " if i == _exit_index else "  ") + options[i], 86, y, 8,
			C_AMBER if i == _exit_index else C_WHITE)


func _draw_name_entry() -> void:
	draw_rect(Rect2(0, 0, VW, VH), C_INK)
	_draw_checker(Rect2(0, 0, VW, 20), C_RED_DARK, C_WHITE, 10)
	_text("ZIEL!", 0, 50, 24, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, C_BLACK)
	_text("PLATZ %d   ZEIT %s   SCORE %07d" % [model.player_place, _format_time(model.elapsed_ms()), model.score],
		0, 72, 8, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
	if model.score > MIKE_SCORE:
		_text("MIKES %07d IST GESCHLAGEN!" % MIKE_SCORE, 0, 90, 8, C_GREEN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("DEIN KUERZEL", 0, 113, 8, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	for i in 3:
		var x := 121.0 + i * 28.0
		draw_rect(Rect2(x, 122, 22, 27), C_AMBER if i == _initial_cursor else C_ROAD_LIGHT, false, 2.0)
		_text(_initials[i], x, 143, 17, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, 22)
	_text("BUCHSTABEN ODER PFEILE · ENTER SPEICHERT", 0, 174, 6, C_CREAM, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("ESC = ACE/AKTUELLES KUERZEL UEBERNEHMEN", 0, 190, 6, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_results() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color8(29, 31, 43))
	_draw_checker(Rect2(0, 0, VW, 20), C_RED_DARK, C_WHITE, 10)
	_text("RENNBERICHT", 0, 44, 18, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW, 2, C_BLACK)
	_draw_panel(Rect2(30, 57, 260, 86), false)
	var rows := [
		["PLATZ", "%d / %d" % [model.player_place, model.kart_states().size()]],
		["ZEIT", _format_time(model.elapsed_ms())],
		["UEBERHOLT", str(model.overtakes)],
		["SAUBERE SEKTOREN", str(model.clean_sectors)],
		["KONTAKTE", str(model.collisions)],
		["SCORE", "%07d" % model.score],
	]
	for i in rows.size():
		var y := 72.0 + i * 11.0
		_text(str(rows[i][0]), 42, y, 7, C_CREAM)
		_text(str(rows[i][1]), 175, y, 8, C_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 100)
	_text(_result_message, 0, 159, 8, C_GREEN if model.score > MIKE_SCORE else C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("FEUER/ENTER: NOCH EIN RENNEN · R: WIEDERHOLUNG", 0, 181, 6, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, VW)
	_text("ESC: TITEL", 0, 194, 6, C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)


func _draw_panel(rect: Rect2, selected: bool) -> void:
	draw_rect(rect, Color8(39, 42, 55))
	draw_rect(rect, C_AMBER if selected else Color8(105, 106, 106), false, 2.0 if selected else 1.0)


func _draw_checker(rect: Rect2, a: Color, b: Color, cell: int) -> void:
	for y in range(int(rect.position.y), int(rect.end.y), cell):
		for x in range(int(rect.position.x), int(rect.end.x), cell):
			var even := (int(x / float(cell)) + int(y / float(cell))) % 2 == 0
			draw_rect(Rect2(x, y, cell, cell), a if even else b)


func _stat_bar(label: String, x: float, y: float, value: float, color: Color) -> void:
	_text(label, x, y, 6, C_CREAM)
	draw_rect(Rect2(x + 38, y - 5, 76, 5), C_BLACK)
	draw_rect(Rect2(x + 39, y - 4, 74.0 * clampf(value, 0.0, 1.0), 3), color)


func _format_time(milliseconds: int) -> String:
	var total_centiseconds := floori(float(maxi(0, milliseconds)) / 10.0)
	var minutes := floori(float(total_centiseconds) / 6000.0)
	var seconds := floori(float(total_centiseconds) / 100.0) % 60
	var centiseconds := total_centiseconds % 100
	return "%02d:%02d.%02d" % [minutes, seconds, centiseconds]


func _text(value: String, x: float, y: float, font_size: int, color: Color,
		alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		outline := 0, outline_color := C_BLACK) -> void:
	if outline > 0:
		draw_string_outline(TOPAZ, Vector2(x, y), value, alignment, width,
			font_size, outline, outline_color)
	draw_string(TOPAZ, Vector2(x, y), value, alignment, width, font_size, color)


# ---------------------------------------------------------------- Debug/Proof

func debug_start_race(track := "parking", setup := "weasel", run_seed := 1990) -> void:
	var setups := ["weasel", "falcon", "block"]
	_setup_index = maxi(0, setups.find(setup))
	_track_index = maxi(0, Model.track_index(track))
	_mode = "race"
	model.start_run(track, setup, "race", run_seed)
	_run_id = "tkd_proof_%d_%d" % [run_seed, Time.get_ticks_msec()]
	_run_committed = false
	_last_event_serial = model.event_serial
	screen = Screen.RACE
	_play_music(_race_stream)


func debug_show(target_screen: String) -> void:
	match target_screen:
		"title": screen = Screen.TITLE
		"garage": screen = Screen.GARAGE
		"editor":
			_editor.begin(_custom_tracks.back() if not _custom_tracks.is_empty() else {})
			screen = Screen.TRACK_EDITOR
		"pause":
			_resume_screen = Screen.RACE
			screen = Screen.PAUSE
		"name": screen = Screen.NAME_ENTRY
		"results": screen = Screen.RESULTS
	queue_redraw()


func screen_name() -> String:
	return Screen.keys()[screen].to_lower()
