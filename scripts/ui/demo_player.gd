class_name DemoPlayer
extends Control
## Prozeduraler PAL-Demo-Renderer fuer das Szene-Studio.
##
## Der Player versteht sowohl das alte Einzel-Effekt-API (`effect`,
## `demo_title`, `group`, `scroller`) als auch komplette Projekte mit einer
## Part-Timeline. Alles wird in diskreten, Amiga-artigen Paletten gezeichnet;
## es werden weder Shader noch externe Grafiken benoetigt.

const SCROLL_SPEED := 120.0
const SCROLL_FS := 22
const PAL_HZ := 50.0
const DEFAULT_PART_SECONDS := 10.0
const TRANSITION_SECONDS := 0.65
const MAX_LAYERS := 5

# Absichtlich kleine, fest indizierte Paletten. Effekte wechseln Register statt
# stufenlose RGB-Farbverlaeufe zu berechnen.
const PALETTE_HEX := {
	"scene": ["050515", "14145A", "3A28A8", "B23AD4", "FF4C8B", "FF9A38", "FFE66D", "F4F4FF"],
	"copper": ["09030A", "2B0714", "64111A", "A92C1E", "E85D24", "FFAD32", "FFE26A", "FFF3C0"],
	"ice": ["020A18", "071F3B", "0C4773", "138DA5", "23CBD1", "7FF5E8", "C7FFFF", "FFFFFF"],
	"violet": ["080416", "211052", "432092", "7738B8", "B84BD1", "EF69C8", "FFB4E6", "FFF1FC"],
	"phosphor": ["020A05", "092311", "105322", "17863B", "28BD55", "62E878", "B0FFA8", "EEFFE5"],
	"sunset": ["090520", "251055", "54216F", "9A315E", "D94A45", "F47A3C", "FFC45C", "FFF2B3"],
	"mono": ["030508", "10151B", "26323A", "43545D", "6D8085", "9DAEAC", "D1DAD3", "F6F4DF"],
	# Kanonische IDs des DemoProjectModel. Die Legacy-Paletten darueber
	# bleiben erhalten, damit alte Saves und der einfache Maker weiterlaufen.
	"night_copper": ["03030D", "11102A", "391339", "7B202D", "C33C29", "F47732", "FFBE55", "FFE8A6"],
	"violet_ice": ["050415", "171044", "38207C", "6837A4", "A64FC1", "4CB9CF", "98F2EA", "F2FFFF"],
	"acid_sunset": ["080515", "321052", "7B176D", "C7356E", "F35B49", "F59631", "D8E83A", "F5FFD0"],
	"steel_blue": ["03080E", "101C2A", "26394C", "3F607A", "6287A1", "8BAFC3", "BBD5DF", "EDF7F7"],
	"red_signal": ["080306", "26070C", "5A0C13", "961622", "D22931", "F05043", "FF8C67", "FFE0B5"],
	# SceneReleaseManager benutzt aeltere Bezeichnungen. Auch diese werden als
	# echte Paletten exponiert, sodass importierte Intros farbtreu bleiben.
	"amber_night": ["05030B", "1E0C15", "542018", "96391B", "D76622", "F49B32", "FFD36A", "FFF0C0"],
	"violet_cyan": ["050416", "1C0E49", "48227E", "8139A1", "C14EB5", "3DBCC4", "8AF0E5", "EEFFFF"],
	"steel_red": ["05080D", "17212B", "344654", "61717B", "A03B42", "D95049", "F28B69", "F8E0C0"],
	"green_terminal": ["010603", "051A0C", "0B3D18", "126927", "1B9A39", "36CB51", "8AF28C", "E1FFD7"],
	"sunset_disk": ["080419", "25104D", "5F1C69", "A02F61", "DD4D4B", "F57B37", "FFC45A", "FFF0AD"],
}

var effect := "stars"                    # Legacy: stars | copper | plasma
var demo_title := "MEGADEMO"
var group := "LONE CODER"
var scroller := "WILLKOMMEN ZU MEINER ERSTEN DEMO !!!   "
var studio_hud := false
var reduced_flash := true
var playback_speed := 1.0

var _project: Dictionary = {}
var _parts: Array[Dictionary] = []
var _timeline_duration := DEFAULT_PART_SECONDS
var _timeline_t := 0.0
var _part_index := 0
var _part_local_t := 0.0
var _playback_paused := false
var _t := 0.0
var _stars: Array[Vector3] = []
var _bob_seeds: Array[Vector3] = []
var _text_width_cache: Dictionary = {}
var _palette_cache: Dictionary = {}
var _tracker_view: Dictionary = {}
var _tracker_levels: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _tracker_row_key := ""
var _tracker_hit := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_build_seed_tables()
	_measure()


## Laedt ein komplettes Studio-Projekt. Unterstuetztes Kernschema:
## {title, group, scroller, palette, bpm, studio_hud, parts:[
##   {name, duration, effect oder layers/effects, palette, transition,
##    title, scroller, intensity, sync_strength}
## ]}
## Layer duerfen Strings oder Dictionaries sein, z.B.
## {effect:"vector_grid", opacity:0.7, speed:1.2, intensity:0.8}.
func set_project(project_data: Dictionary) -> void:
	_project = project_data.duplicate(true)
	demo_title = str(_project.get("title", _project.get("demo_title", demo_title))).strip_edges().to_upper()
	if demo_title.is_empty():
		demo_title = "MEGADEMO"
	group = str(_project.get("group", _project.get("handle", group))).strip_edges().to_upper()
	if group.is_empty():
		group = "LONE CODER"
	var project_scroll := str(_project.get("scroller", _project.get("scrolltext", scroller)))
	set_scroller(project_scroll)
	studio_hud = bool(_project.get("studio_hud", _project.get("show_hud", studio_hud)))
	reduced_flash = bool(_project.get("reduced_flash", reduced_flash))
	playback_speed = clampf(float(_project.get("playback_speed", 1.0)), 0.1, 3.0)

	_parts.clear()
	var raw_parts: Variant = _project.get("parts", _project.get("timeline", []))
	if raw_parts is Array:
		for raw: Variant in raw_parts:
			if raw is Dictionary:
				_parts.append((raw as Dictionary).duplicate(true))
	if not _parts.is_empty():
		var first_layers := _part_layers(_parts[0])
		if not first_layers.is_empty():
			effect = str(first_layers[0].get("effect", effect))
	elif _project.has("effect"):
		effect = str(_project["effect"])

	_rebuild_timeline()
	restart()
	_text_width_cache.clear()
	_measure()
	queue_redraw()


func project() -> Dictionary:
	return _project.duplicate(true)


func set_scroller(text: String) -> void:
	scroller = (text.strip_edges() + "   ").to_upper()
	if scroller.strip_edges().is_empty():
		scroller = "   "
	_measure()
	queue_redraw()


func set_studio_hud(enabled: bool) -> void:
	studio_hud = enabled
	queue_redraw()


func set_playback_paused(paused: bool) -> void:
	_playback_paused = paused


func is_playback_paused() -> bool:
	return _playback_paused


func restart() -> void:
	_timeline_t = 0.0
	_part_index = 0
	_part_local_t = 0.0
	_playback_paused = false
	_update_timeline_state()
	queue_redraw()


func seek(seconds: float) -> void:
	if _timeline_duration <= 0.0:
		return
	_timeline_t = clampf(seconds, 0.0, maxf(0.0, _timeline_duration - 0.0001))
	_update_timeline_state()
	queue_redraw()


func current_part_index() -> int:
	return _part_index


func current_part_progress() -> float:
	var part := _current_part()
	return clampf(_part_local_t / _part_duration(part), 0.0, 1.0)


func playback_position() -> float:
	return _timeline_t


func total_duration() -> float:
	return _timeline_duration


func available_effects() -> PackedStringArray:
	return PackedStringArray([
		"starfield", "copperbars", "plasma", "vectorgrid", "bobs", "tunnel",
		"shadebobs", "sine_scroller", "rasterbars", "rotozoomer",
		"line_twister", "moire_rings",
	])


func available_palettes() -> PackedStringArray:
	return PackedStringArray(PALETTE_HEX.keys())


func _build_seed_tables() -> void:
	if not _stars.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for _i in 128:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.22, 1.0)))
	for _i in 32:
		_bob_seeds.append(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.45, 1.0)))


func _measure() -> void:
	_text_width_cache[scroller] = _measure_text(scroller)


func _measure_text(text: String) -> float:
	var f := Wb13.font()
	var width := 0.0
	for i in text.length():
		width += f.get_char_size(text.unicode_at(i), SCROLL_FS).x
	return maxf(width, 1.0)


func _scroll_width(text: String) -> float:
	if not _text_width_cache.has(text):
		_text_width_cache[text] = _measure_text(text)
	return float(_text_width_cache[text])


func _process(dt: float) -> void:
	_update_tracker_state(dt)
	if _playback_paused:
		return
	var step := minf(dt, 0.1) * playback_speed
	_t += step
	_timeline_t += step
	if _timeline_duration > 0.0 and _timeline_t >= _timeline_duration:
		if bool(_project.get("loop", true)):
			_timeline_t = fmod(_timeline_t, _timeline_duration)
		else:
			_timeline_t = maxf(0.0, _timeline_duration - 0.0001)
			_playback_paused = true
	_update_timeline_state()
	queue_redraw()


func _rebuild_timeline() -> void:
	_timeline_duration = 0.0
	if _parts.is_empty():
		_timeline_duration = maxf(0.25, float(_project.get("duration", DEFAULT_PART_SECONDS)))
		return
	for part: Dictionary in _parts:
		_timeline_duration += _part_duration(part)
	_timeline_duration = maxf(_timeline_duration, 0.25)


func _update_timeline_state() -> void:
	if _parts.is_empty():
		_part_index = 0
		_part_local_t = _timeline_t
		return
	var cursor := 0.0
	for i in _parts.size():
		var duration := _part_duration(_parts[i])
		if _timeline_t < cursor + duration or i == _parts.size() - 1:
			_part_index = i
			_part_local_t = clampf(_timeline_t - cursor, 0.0, duration)
			return
		cursor += duration


func _part_duration(part: Dictionary) -> float:
	return clampf(float(part.get("duration", part.get("seconds", DEFAULT_PART_SECONDS))), 0.5, 120.0)


func _legacy_part() -> Dictionary:
	return {
		"name": "INTRO",
		"duration": _timeline_duration,
		"effect": effect,
		"title": demo_title,
		"group": group,
		"scroller": scroller,
		"palette": _project.get("palette", _default_palette_for_effect(effect)),
		"transition": _project.get("transition", "cut"),
	}


func _current_part() -> Dictionary:
	if _parts.is_empty():
		return _legacy_part()
	return _parts[clampi(_part_index, 0, _parts.size() - 1)]


func _draw() -> void:
	var sz := size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	var part := _current_part()
	var pal := _resolve_palette(part)
	var render_t: float = floorf(_t * PAL_HZ) / PAL_HZ
	var pulse := _sync_pulse(part, render_t, _part_local_t)
	draw_rect(Rect2(Vector2.ZERO, sz), _pal(pal, 0))

	var layers := _part_layers(part)
	if layers.is_empty():
		layers.append({"effect": effect})
	for i in mini(layers.size(), MAX_LAYERS):
		var layer := layers[i].duplicate(true)
		for inherited_key in ["opacity", "speed", "intensity"]:
			if not layer.has(inherited_key) and part.has(inherited_key):
				layer[inherited_key] = part[inherited_key]
		_draw_effect_layer(str(layer.get("effect", "stars")), sz, pal,
			layer, render_t, pulse, i)

	if bool(part.get("scanlines", _project.get("scanlines", true))):
		_draw_scanlines(sz)
	_draw_titles(sz, pal, part, render_t, pulse)
	if bool(part.get("show_scroller", true)):
		_draw_scroller(sz, pal, part, render_t, pulse)
	_draw_transition(sz, pal, part)
	_draw_sync_bezel(sz, pal, pulse)
	if studio_hud:
		_draw_studio_hud(sz, pal, part)


func _part_layers(part: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var primary := str(part.get("effect", part.get("effect_id", ""))).strip_edges()
	if not primary.is_empty():
		_append_layer(result, primary)

	# Das kanonische Modell speichert `effects` als komplette Komposition und
	# `layers` als reine Zusatzlagen. Die Editor-Vorschau kann `layers` dagegen
	# temporaer als komplette Komposition liefern. Beginnt layers mit dem
	# Primaereffekt, gewinnt deshalb dieser explizite Live-Stack; andernfalls
	# werden effects und layers vereinigt.
	var raw_layers: Variant = part.get("layers", part.get("effect_layers", []))
	var layers_are_complete := false
	if raw_layers is Array:
		for entry: Variant in raw_layers:
			var entry_id := _layer_effect_id(entry)
			if not primary.is_empty() and entry_id == primary:
				layers_are_complete = true
				break
	if not layers_are_complete:
		var raw_effects: Variant = part.get("effects", [])
		if raw_effects is Array:
			for entry: Variant in raw_effects:
				_append_layer(result, entry)
	if raw_layers is Array:
		for entry: Variant in raw_layers:
			_append_layer(result, entry)
	return result


func _layer_effect_id(entry: Variant) -> String:
	if entry is Dictionary:
		var data := entry as Dictionary
		return str(data.get("effect", data.get("type", data.get("id", "")))).strip_edges()
	if entry is String or entry is StringName:
		return str(entry).strip_edges()
	return ""


func _append_layer(target: Array[Dictionary], entry: Variant) -> void:
	var effect_id := _layer_effect_id(entry)
	if effect_id.is_empty():
		return
	var data: Dictionary = (entry as Dictionary).duplicate(true) if entry is Dictionary else {"effect": effect_id}
	data["effect"] = effect_id
	for i in target.size():
		if str(target[i].get("effect", "")) == effect_id:
			# Ein spaeteres Dictionary traegt ggf. Live-Parameter wie opacity.
			if entry is Dictionary:
				for key: Variant in data:
					target[i][key] = data[key]
			return
	target.append(data)


func _draw_effect_layer(effect_name: String, sz: Vector2, pal: Array,
		layer: Dictionary, render_t: float, pulse: float, layer_index: int) -> void:
	var normalized := effect_name.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	var opacity := clampf(float(layer.get("opacity", layer.get("alpha", 1.0))), 0.0, 1.0)
	var speed := clampf(float(layer.get("speed", 1.0)), 0.05, 5.0)
	var intensity := clampf(float(layer.get("intensity", 1.0)), 0.1, 2.0)
	var lt := render_t * speed + float(layer.get("phase", layer_index * 0.73))
	match normalized:
		"starfield", "stars":
			_draw_stars(sz, pal, lt, opacity, intensity, pulse)
		"copper", "copper_bars", "copperbars":
			_draw_copper(sz, pal, lt, opacity, intensity, pulse)
		"plasma":
			_draw_plasma(sz, pal, lt, opacity, intensity, pulse)
		"vector", "grid", "vector_grid", "vectorgrid":
			_draw_vector_grid(sz, pal, lt, opacity, intensity, pulse)
		"bobs", "shadebobs", "shade_bobs", "sprites":
			_draw_bobs(sz, pal, lt, opacity, intensity, pulse)
		"tunnel", "vector_tunnel":
			_draw_tunnel(sz, pal, lt, opacity, intensity, pulse)
		"raster", "raster_bars", "rasterbars":
			_draw_raster(sz, pal, lt, opacity, intensity, pulse)
		"rotozoom", "rotozoomer":
			_draw_rotozoomer(sz, pal, lt, opacity, intensity, pulse)
		"twister", "line_twister":
			_draw_line_twister(sz, pal, lt, opacity, intensity, pulse)
		"moire", "moire_rings":
			_draw_moire_rings(sz, pal, lt, opacity, intensity, pulse)
		"sine_scroller", "sinescroller":
			_draw_sine_ribbons(sz, pal, lt, opacity, intensity, pulse)
		_:
			_draw_stars(sz, pal, lt, opacity, intensity, pulse)


func _default_palette_for_effect(effect_name: String) -> String:
	match effect_name.to_lower():
		"copper", "copperbars", "raster", "rasterbars", "moire_rings": return "night_copper"
		"plasma", "vector_grid", "vectorgrid", "tunnel", "rotozoomer": return "violet_ice"
		"bobs", "shadebobs", "shade_bobs", "sine_scroller", "line_twister": return "acid_sunset"
		_: return "steel_blue"


func _resolve_palette(part: Dictionary) -> Array:
	var selection: Variant = part.get("palette", _project.get("palette", ""))
	if selection is Array:
		var custom: Array = []
		for entry: Variant in selection:
			if entry is Color:
				custom.append(entry)
			else:
				custom.append(Color.from_string(str(entry), Color.WHITE))
			if custom.size() >= 16:
				break
		if custom.size() >= 2:
			return custom
	var key := str(selection).to_lower()
	if key.is_empty() or not PALETTE_HEX.has(key):
		var layers := _part_layers(part)
		key = _default_palette_for_effect(str(layers[0].get("effect", effect)) if not layers.is_empty() else effect)
	if _palette_cache.has(key):
		return _palette_cache[key]
	var colors: Array = []
	for html: String in PALETTE_HEX.get(key, PALETTE_HEX["scene"]):
		colors.append(Color.from_string("#" + html, Color.WHITE))
	_palette_cache[key] = colors
	return colors


func _pal(palette: Array, index: int, alpha := 1.0) -> Color:
	if palette.is_empty():
		return Color(1.0, 1.0, 1.0, alpha)
	var c: Color = palette[posmod(index, palette.size())]
	c.a *= clampf(alpha, 0.0, 1.0)
	return c


func _sync_pulse(part: Dictionary, render_t: float, local_t: float) -> float:
	var raw_sync: Variant = part.get("sync", _project.get("sync", true))
	var enabled := bool(raw_sync)
	if not enabled:
		return 0.0
	var default_strength := float(raw_sync) if raw_sync is float or raw_sync is int else 0.55
	var strength := clampf(float(part.get("sync_strength", _project.get("sync_strength", default_strength))), 0.0, 1.0)
	var bpm := clampf(float(part.get("bpm", _project.get("bpm", 125.0))), 30.0, 260.0)
	var beat_phase := fmod(render_t * bpm / 60.0, 1.0)
	# Bei laufendem MOD gibt dessen Tracker den Puls vor. Ein zusaetzlicher
	# simulierter 125/118/...-BPM-Takt wuerde neben der Musik doppelt schlagen.
	var result := pow(1.0 - beat_phase, 7.0) * strength if _tracker_view.is_empty() else 0.0
	var markers: Variant = part.get("sync_markers", part.get("markers", []))
	if markers is Array:
		for marker: Variant in markers:
			var marker_time := -100.0
			if marker is Dictionary:
				marker_time = float((marker as Dictionary).get("time", (marker as Dictionary).get("second", -100.0)))
			elif marker is float or marker is int:
				marker_time = float(marker)
			var distance := absf(local_t - marker_time)
			if distance < 0.16:
				result = maxf(result, (1.0 - distance / 0.16) * strength)
	# Ein wirklich laufendes MOD liefert Pattern-Hits und vier Kanalpegel. Ohne
	# nativen Player bleibt die deterministische BPM-Simulation erhalten.
	var channel_peak := 0.0
	for level: float in _tracker_levels:
		channel_peak = maxf(channel_peak, level)
	result = maxf(result, maxf(_tracker_hit * strength, channel_peak * strength * 0.78))
	return clampf(result, 0.0, 1.0)


func _update_tracker_state(dt: float) -> void:
	_tracker_hit = maxf(0.0, _tracker_hit - dt * 5.5)
	_tracker_view = {}
	for i in 4:
		_tracker_levels[i] = maxf(0.0, _tracker_levels[i] - dt * 3.0)
	var music := get_node_or_null("/root/MusicManager")
	if music == null or not music.has_method("native_player"):
		return
	if music.has_method("is_playing") and not bool(music.call("is_playing")):
		return
	var native: Variant = music.call("native_player")
	if native == null:
		return
	if native.has_method("playback_view"):
		var view: Variant = native.call("playback_view")
		if view is Dictionary:
			_tracker_view = (view as Dictionary).duplicate(true)
	if native.has_method("channel_level"):
		for i in 4:
			_tracker_levels[i] = clampf(float(native.call("channel_level", i)), 0.0, 1.0)
	if _tracker_view.is_empty():
		return
	var key := "%d:%d:%d" % [int(_tracker_view.get("order", 0)),
		int(_tracker_view.get("pattern", 0)), int(_tracker_view.get("row", 0))]
	if key != _tracker_row_key:
		_tracker_row_key = key
		if int(_tracker_view.get("row", 0)) % 4 == 0:
			_tracker_hit = 1.0


func _draw_stars(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	var count := mini(_stars.size(), int(70.0 + 58.0 * minf(intensity, 1.0)))
	for i in count:
		var star := _stars[i]
		var px := fmod(star.x - t * star.z * (0.085 + pulse * 0.05), 1.0)
		if px < 0.0:
			px += 1.0
		var pos := Vector2(floor(px * sz.x), floor(star.y * sz.y))
		var r := maxf(1.0, floor(0.7 + star.z * (1.8 + pulse)))
		var color_index := 4 + int(star.z * 3.0)
		draw_rect(Rect2(pos, Vector2(r, r)), _pal(pal, color_index, opacity * (0.38 + star.z * 0.62)))
		if pulse > 0.5 and star.z > 0.72:
			draw_line(pos, pos + Vector2(-3.0 - pulse * 6.0, 0.0), _pal(pal, 7, opacity * pulse * 0.7), 1.0, false)


func _draw_copper(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	var bands := clampi(int(30.0 + intensity * 18.0), 24, 56)
	var band_h := sz.y / float(bands)
	for i in bands:
		var wave := sin(t * 1.55 + i * 0.37) + sin(t * -0.83 + i * 0.16)
		var index := posmod(floori(float(i) / 2.0) + int(round(wave * 1.8)) + int(pulse * 2.0), pal.size())
		draw_rect(Rect2(0.0, floor(i * band_h), sz.x, ceil(band_h) + 1.0), _pal(pal, index, opacity * 0.9))
		if i % 6 == 0:
			draw_line(Vector2(0.0, floor(i * band_h)), Vector2(sz.x, floor(i * band_h)), _pal(pal, index + 2, opacity * 0.7), 1.0, false)


func _draw_plasma(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	var cols := clampi(int(sz.x / 15.0), 20, 36)
	var rows := clampi(int(sz.y / 12.0), 12, 24)
	var cell := Vector2(sz.x / float(cols), sz.y / float(rows))
	var phase := t * (1.3 + intensity * 0.35)
	for yy in rows:
		for xx in cols:
			var value := sin(xx * 0.49 + phase * 1.7)
			value += sin(yy * 0.63 - phase * 1.2)
			value += sin((xx + yy) * 0.32 + phase * 0.72)
			var index := clampi(int(floor((value + 3.0) / 6.0 * float(pal.size()))), 0, pal.size() - 1)
			index += int(pulse * 2.0)
			draw_rect(Rect2(floor(xx * cell.x), floor(yy * cell.y), ceil(cell.x) + 1.0, ceil(cell.y) + 1.0), _pal(pal, index, opacity * 0.88))


func _draw_vector_grid(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	var horizon: float = floorf(sz.y * (0.39 + sin(t * 0.29) * 0.025))
	var vanish_x := sz.x * 0.5 + sin(t * 0.42) * sz.x * 0.10
	var grid_color := _pal(pal, 5 + int(pulse * 2.0), opacity * 0.78)
	var glow_color := _pal(pal, 3, opacity * 0.35)
	draw_rect(Rect2(0.0, horizon, sz.x, sz.y - horizon), _pal(pal, 0, opacity * 0.32))
	var columns := clampi(int(12.0 + intensity * 6.0), 10, 22)
	for i in columns + 1:
		var bottom_x := float(i) / float(columns) * sz.x
		draw_line(Vector2(vanish_x, horizon), Vector2(bottom_x, sz.y), glow_color, 3.0, false)
		draw_line(Vector2(vanish_x, horizon), Vector2(bottom_x, sz.y), grid_color, 1.0, false)
	var scroll := fmod(t * 0.55, 1.0)
	for row in 14:
		var z := fmod(float(row) / 14.0 + scroll, 1.0)
		var perspective := z * z
		var y: float = horizon + perspective * (sz.y - horizon)
		draw_line(Vector2(0.0, floor(y)), Vector2(sz.x, floor(y)), _pal(pal, 4 + row, opacity * (0.28 + perspective * 0.7)), 1.0, false)
	draw_line(Vector2(0.0, horizon), Vector2(sz.x, horizon), _pal(pal, 7, opacity * (0.65 + pulse * 0.3)), 1.0, false)


func _draw_bobs(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	var center := Vector2(sz.x * 0.5, sz.y * 0.47)
	var count := mini(_bob_seeds.size(), clampi(int(16.0 + intensity * 12.0), 12, 32))
	for i in count:
		var bob_seed := _bob_seeds[i]
		var radius_x := sz.x * (0.18 + bob_seed.z * 0.25)
		var radius_y := sz.y * (0.12 + bob_seed.z * 0.18)
		var pos := center + Vector2(sin(t * (0.62 + bob_seed.z * 0.3) + bob_seed.x) * radius_x,
			cos(t * (0.74 + bob_seed.z * 0.25) + bob_seed.y) * radius_y)
		var bob_size: float = floorf(3.0 + bob_seed.z * 6.0 + pulse * 2.0)
		var color := _pal(pal, 2 + i, opacity * (0.32 + bob_seed.z * 0.38))
		draw_circle(Vector2(floor(pos.x), floor(pos.y)), bob_size + 2.0, Color(0.0, 0.0, 0.0, opacity * 0.2), false, 1.0, false)
		draw_circle(Vector2(floor(pos.x), floor(pos.y)), bob_size, color, true, -1.0, false)
		draw_rect(Rect2(floor(pos.x - bob_size * 0.35), floor(pos.y - bob_size * 0.35), 2.0, 2.0), _pal(pal, 7, opacity * 0.72))


func _draw_tunnel(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	var center := Vector2(sz.x * 0.5 + sin(t * 0.47) * sz.x * 0.12,
		sz.y * 0.46 + cos(t * 0.39) * sz.y * 0.09)
	var max_radius := maxf(sz.x, sz.y) * 0.72
	var ring_count := clampi(int(8.0 + intensity * 5.0), 8, 15)
	for ring in ring_count:
		var z := fmod(float(ring) / float(ring_count) + t * 0.17, 1.0)
		var radius := 5.0 + z * z * max_radius
		var segments := 12
		for segment in segments:
			if (segment + ring) % 2 != 0:
				continue
			var a0 := float(segment) / float(segments) * TAU + t * 0.18
			var a1 := float(segment + 1) / float(segments) * TAU + t * 0.18
			var p0 := center + Vector2(cos(a0), sin(a0) * 0.63) * radius
			var p1 := center + Vector2(cos(a1), sin(a1) * 0.63) * radius
			draw_line(p0, p1, _pal(pal, ring + segment + int(pulse * 2.0), opacity * (0.3 + z * 0.6)), maxf(1.0, z * 3.0), false)
	draw_circle(center, 2.0 + pulse * 3.0, _pal(pal, 7, opacity), true, -1.0, false)


func _draw_raster(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	var bars := clampi(int(24.0 + intensity * 12.0), 20, 42)
	var band_h := sz.y / float(bars)
	for i in bars:
		var phase := t * 1.8 + i * 0.43
		var width := sz.x * (0.30 + 0.26 * (sin(phase) * 0.5 + 0.5))
		width *= 1.0 + pulse * 0.08
		var center_x := sz.x * 0.5 + sin(t * 0.83 + i * 0.22) * sz.x * 0.20
		var rect := Rect2(floor(center_x - width * 0.5), floor(i * band_h), floor(width), maxf(1.0, ceil(band_h) - 1.0))
		draw_rect(rect, _pal(pal, floori(float(i) / 2.0) + int(t * 3.0), opacity * (0.48 + float(i % 3) * 0.17)))


func _draw_rotozoomer(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	# Klassischer planar gerenderter Checker: Die zwei Basisvektoren bilden eine
	# vorberechnete Rotations-/Zoomtabelle nach, jedes Feld bleibt ein harter
	# Blitter-Quad ohne moderne Texturfilterung.
	var angle := t * (0.46 + intensity * 0.12)
	var zoom := 0.72 + (sin(t * 0.71) * 0.5 + 0.5) * (0.48 + intensity * 0.12)
	zoom *= 1.0 + pulse * 0.06
	var tile := clampf(minf(sz.x, sz.y) / 8.5 * zoom, 15.0, 48.0)
	var basis_u := Vector2(cos(angle), sin(angle)) * tile
	var basis_v := Vector2(-sin(angle), cos(angle)) * tile
	var origin := sz * 0.5 + basis_u * fmod(t * 0.35, 1.0) + basis_v * fmod(t * 0.23, 1.0)
	var extent := 14
	for yy in range(-extent, extent):
		for xx in range(-extent, extent):
			if posmod(xx + yy, 2) != 0:
				continue
			var p := origin + basis_u * xx + basis_v * yy
			var quad := PackedVector2Array([p, p + basis_u, p + basis_u + basis_v, p + basis_v])
			var center := p + (basis_u + basis_v) * 0.5
			if center.x < -tile * 2.0 or center.y < -tile * 2.0 \
					or center.x > sz.x + tile * 2.0 or center.y > sz.y + tile * 2.0:
				continue
			var color_index := 2 + posmod(xx * 3 + yy * 5 + floori(t * 2.0), 5)
			draw_colored_polygon(quad, _pal(pal, color_index, opacity * 0.78))
			draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]),
				_pal(pal, color_index + 2, opacity * 0.48), 1.0, false)


func _draw_line_twister(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	# Ein zeilenweise aufgebauter, vierseitiger Twister. Die diskreten
	# 4-Pixel-Streifen entsprechen einer PAL-Line-/Blitter-Komposition.
	var step := 4.0
	var half_width := sz.x * (0.14 + intensity * 0.025)
	var center_x := sz.x * 0.5
	var y := 0.0
	while y < sz.y:
		var phase0 := t * 2.0 + y * 0.035
		var phase1 := t * 2.0 + (y + step) * 0.035
		var sway0 := sin(t * 0.63 + y * 0.010) * sz.x * 0.12
		var sway1 := sin(t * 0.63 + (y + step) * 0.010) * sz.x * 0.12
		var left0 := center_x + sway0 + sin(phase0) * half_width
		var right0 := center_x + sway0 + sin(phase0 + PI) * half_width
		var left1 := center_x + sway1 + sin(phase1) * half_width
		var right1 := center_x + sway1 + sin(phase1 + PI) * half_width
		var min0 := minf(left0, right0)
		var max0 := maxf(left0, right0)
		var min1 := minf(left1, right1)
		var max1 := maxf(left1, right1)
		var face := posmod(floori((phase0 + PI) / (PI * 0.5)), 4)
		var quad := PackedVector2Array([
			Vector2(min0, y), Vector2(max0, y),
			Vector2(max1, y + step + 1.0), Vector2(min1, y + step + 1.0),
		])
		draw_colored_polygon(quad, _pal(pal, 2 + face * 2 + int(pulse * 2.0), opacity * 0.88))
		if int(y) % 16 == 0:
			draw_line(Vector2(min0, y), Vector2(max0, y), _pal(pal, 7, opacity * 0.65), 1.0, false)
		y += step


func _draw_moire_rings(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	# Zwei reine Linienfelder überlagern sich. Das sichtbare Moiré entsteht
	# tatsächlich aus dem PAL-Pixelraster und nicht aus einem Shader.
	var centers := [
		Vector2(sz.x * 0.39 + sin(t * 0.71) * sz.x * 0.13,
			sz.y * 0.49 + cos(t * 0.53) * sz.y * 0.13),
		Vector2(sz.x * 0.61 + cos(t * 0.67) * sz.x * 0.13,
			sz.y * 0.49 + sin(t * 0.47) * sz.y * 0.13),
	]
	var spacing := clampf(12.0 - intensity * 2.5, 7.0, 12.0)
	var rings := clampi(int(maxf(sz.x, sz.y) / spacing), 24, 52)
	for field in centers.size():
		var center: Vector2 = centers[field]
		for ring in rings:
			var radius := 3.0 + ring * spacing + fmod(t * (8.0 + field * 3.0), spacing)
			var color_index := 3 + posmod(ring + field * 2 + int(pulse * 2.0), 5)
			draw_arc(center, radius, 0.0, TAU, clampi(int(radius * 0.45), 18, 64),
				_pal(pal, color_index, opacity * (0.36 + field * 0.14)), 1.0, false)


func _draw_sine_ribbons(sz: Vector2, pal: Array, t: float, opacity: float,
		intensity: float, pulse: float) -> void:
	# Ein leichtgewichtiger Copper/Blitter-Look fuer Parts, deren Hauptmodul
	# der Sinus-Scroller ist. Der eigentliche Text wird danach von
	# _draw_scroller gezeichnet; diese drei Baender geben ihm eine Buehne.
	var step := maxf(4.0, floorf(sz.x / 96.0))
	for ribbon in 3:
		var points := PackedVector2Array()
		var x := -step
		while x <= sz.x + step:
			var wave := sin(x * (0.027 + ribbon * 0.004) + t * (1.6 + ribbon * 0.27))
			var y := sz.y * (0.30 + ribbon * 0.13) + wave * sz.y * (0.07 + intensity * 0.025)
			points.append(Vector2(floorf(x), floorf(y)))
			x += step
		if points.size() >= 2:
			draw_polyline(points, Color(0.0, 0.0, 0.0, opacity * 0.48), 5.0, false)
			draw_polyline(points, _pal(pal, 3 + ribbon * 2 + int(pulse * 2.0), opacity * 0.82), 2.0, false)


func _draw_scanlines(sz: Vector2) -> void:
	for y in range(1, int(sz.y), 4):
		draw_line(Vector2(0.0, y), Vector2(sz.x, y), Color(0.0, 0.0, 0.0, 0.10), 1.0, false)


func _draw_titles(sz: Vector2, pal: Array, part: Dictionary, t: float, pulse: float) -> void:
	if not bool(part.get("show_title", true)):
		return
	var title := str(part.get("title", demo_title)).strip_edges().to_upper()
	if title.is_empty():
		return
	var handle := str(part.get("group", part.get("handle", group))).strip_edges().to_upper()
	var f := Wb13.font()
	if str(part.get("title_style", _project.get("title_style", ""))).to_lower() == "cracktro":
		_draw_cracktro_title(sz, pal, part, t, pulse, title, handle, f)
		return
	var title_size := clampi(int(sz.y * 0.19), 22, 44)
	while title_size > 18 and f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > sz.x - 20.0:
		title_size -= 2
	var text_width := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var motion := str(part.get("title_motion", _project.get("title_motion", "bounce"))).to_lower()
	var offset := Vector2.ZERO
	match motion:
		"sine", "wave": offset.x = sin(t * 1.15) * sz.x * 0.12
		"orbit": offset = Vector2(sin(t * 1.17) * 18.0, cos(t * 1.43) * 8.0)
		"static", "none": pass
		_: offset.y = sin(t * 2.2) * (8.0 + pulse * 5.0)
	var baseline := Vector2(floor((sz.x - text_width) * 0.5 + offset.x), floor(sz.y * 0.35 + offset.y))
	var cycle := int(floor(t * 7.0 + pulse * 2.0))
	draw_string(f, baseline + Vector2(3.0, 3.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(0.0, 0.0, 0.0, 0.72))
	draw_string(f, baseline + Vector2(1.0, 1.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, _pal(pal, cycle + 2, 0.85))
	draw_string(f, baseline, title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, _pal(pal, cycle + 6))
	if not handle.is_empty() and bool(part.get("show_group", true)):
		var credit := str(part.get("credit_prefix", "A ")) + handle
		var credit_size := clampi(int(sz.y * 0.065), 11, 16)
		var credit_width := f.get_string_size(credit, HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size).x
		draw_string(f, Vector2(floor((sz.x - credit_width) * 0.5), baseline.y + title_size * 0.68), credit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, credit_size, _pal(pal, 6, 0.92))


func _draw_cracktro_title(sz: Vector2, pal: Array, part: Dictionary, t: float,
		pulse: float, title: String, handle: String, font: Font) -> void:
	# Klassische einzelne Cracktro-Buehne: breite, ruhige Wortmarke statt drei
	# wechselnder Folien. Die Tiefe entsteht aus diskreten Blitter-Lagen; Glanz,
	# Kontur und Seitenfluegel verwenden nur die aktive indizierte Palette.
	var requested_size := int(part.get("title_size", _project.get("title_size", 72)))
	var title_size := clampi(requested_size, 34, clampi(int(sz.y * 0.24), 42, 92))
	while title_size > 28 and font.get_string_size(title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > sz.x * 0.72:
		title_size -= 2
	var title_width := font.get_string_size(title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var sway := sin(t * 1.08) * minf(18.0, sz.x * 0.012)
	var bob := sin(t * 1.86) * (2.0 + pulse * 2.0)
	var baseline := Vector2(floorf((sz.x - title_width) * 0.5 + sway),
		floorf(sz.y * 0.43 + bob))
	var handle_size := clampi(int(sz.y * 0.035), 13, 20)
	while handle_size > 11 and font.get_string_size(handle,
			HORIZONTAL_ALIGNMENT_LEFT, -1, handle_size).x > sz.x * 0.72:
		handle_size -= 1
	var handle_width := font.get_string_size(handle,
		HORIZONTAL_ALIGNMENT_LEFT, -1, handle_size).x
	var handle_pos := Vector2(floorf((sz.x - handle_width) * 0.5),
		baseline.y - title_size - 28.0)
	var band_top := handle_pos.y - handle_size - 12.0
	var band_bottom := baseline.y + title_size * 0.64
	var band := Rect2(sz.x * 0.08, band_top, sz.x * 0.84, band_bottom - band_top)
	draw_rect(band, Color(0.0, 0.0, 0.02, 0.68))
	draw_line(Vector2(band.position.x, band.position.y),
		Vector2(band.end.x, band.position.y), _pal(pal, 5, 0.78), 2.0, false)
	draw_line(Vector2(band.position.x, band.end.y),
		Vector2(band.end.x, band.end.y), _pal(pal, 4, 0.72), 2.0, false)

	var center_y := baseline.y - title_size * 0.27
	var wing_gap := 34.0
	var left_end := baseline.x - wing_gap
	var right_start := baseline.x + title_width + wing_gap
	for stripe in 3:
		var y := floorf(center_y + (stripe - 1) * 6.0)
		var color := _pal(pal, 4 + stripe + int(pulse * 2.0), 0.78)
		draw_line(Vector2(band.position.x + 16.0, y), Vector2(left_end, y), color,
			2.0 if stripe == 1 else 1.0, false)
		draw_line(Vector2(right_start, y), Vector2(band.end.x - 16.0, y), color,
			2.0 if stripe == 1 else 1.0, false)

	# Dunkle Extrusion, kupferfarbene Mittellage und eine helle Pixelkante.
	for depth in range(10, 0, -1):
		var depth_color := _pal(pal, 1 + floori(float(depth) / 3.0), 0.96)
		draw_string(font, baseline + Vector2(depth, depth), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, depth_color)
	draw_string(font, baseline + Vector2(2.0, 2.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, _pal(pal, 3, 1.0))
	draw_string(font, baseline, title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size,
		_pal(pal, 7, 1.0))
	draw_string(font, baseline - Vector2(1.0, 1.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, _pal(pal, 5, 0.64))

	if not handle.is_empty() and bool(part.get("show_group", true)):
		draw_string(font, handle_pos + Vector2(2.0, 2.0), handle,
			HORIZONTAL_ALIGNMENT_LEFT, -1, handle_size, Color(0.0, 0.0, 0.0, 0.88))
		draw_string(font, handle_pos, handle,
			HORIZONTAL_ALIGNMENT_LEFT, -1, handle_size, _pal(pal, 6, 0.96))

	var tagline := str(part.get("tagline", _project.get("tagline", ""))).strip_edges().to_upper()
	if not tagline.is_empty():
		var tagline_size := clampi(int(sz.y * 0.027), 12, 17)
		while tagline_size > 10 and font.get_string_size(tagline,
				HORIZONTAL_ALIGNMENT_LEFT, -1, tagline_size).x > sz.x * 0.70:
			tagline_size -= 1
		var tagline_width := font.get_string_size(tagline,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tagline_size).x
		var tagline_pos := Vector2(floorf((sz.x - tagline_width) * 0.5),
			band_bottom - 10.0)
		draw_string(font, tagline_pos, tagline, HORIZONTAL_ALIGNMENT_LEFT, -1,
			tagline_size, _pal(pal, 6, 0.88))


func _draw_scroller(sz: Vector2, pal: Array, part: Dictionary, t: float, pulse: float) -> void:
	var text := str(part.get("scroller", part.get("scrolltext", scroller))).strip_edges().to_upper() + "   "
	if text.strip_edges().is_empty():
		return
	var f := Wb13.font()
	var band_height := minf(58.0, maxf(38.0, sz.y * 0.23))
	var band_y := sz.y - band_height
	draw_rect(Rect2(0.0, band_y, sz.x, band_height), Color(0.0, 0.0, 0.0, 0.48))
	draw_line(Vector2(0.0, band_y), Vector2(sz.x, band_y), _pal(pal, 5, 0.75), 1.0, false)
	var width := _scroll_width(text)
	var speed := clampf(float(part.get("scroll_speed", _project.get("scroll_speed", SCROLL_SPEED))), 25.0, 280.0)
	var x := sz.x - fmod(t * speed, width + sz.x)
	for i in text.length():
		var code := text.unicode_at(i)
		var char_width := f.get_char_size(code, SCROLL_FS).x
		if x > -char_width and x < sz.x:
			var wave := sin(t * 5.0 + i * 0.43)
			var y := band_y + band_height * 0.57 + wave * (7.0 + pulse * 4.0)
			var col := _pal(pal, floori(float(i) / 2.0) + int(t * 9.0), 1.0)
			draw_char(f, Vector2(floor(x + 2.0), floor(y + 2.0)), String.chr(code), SCROLL_FS, Color(0.0, 0.0, 0.0, 0.72))
			draw_char(f, Vector2(floor(x), floor(y)), String.chr(code), SCROLL_FS, col)
		x += char_width


func _transition_descriptor(part: Dictionary) -> Dictionary:
	var raw: Variant = part.get("transition", part.get("transition_in", "cut"))
	if raw is Dictionary:
		return raw as Dictionary
	return {"type": str(raw), "duration": part.get("transition_duration", TRANSITION_SECONDS)}


func _draw_transition(sz: Vector2, pal: Array, part: Dictionary) -> void:
	if _part_index == 0 and not bool(part.get("transition_on_start", false)):
		return
	var descriptor := _transition_descriptor(part)
	var kind := str(descriptor.get("type", descriptor.get("id", "cut"))).to_lower()
	if kind in ["", "cut", "none"]:
		return
	var duration := clampf(float(descriptor.get("duration", TRANSITION_SECONDS)), 0.1, 2.5)
	if _part_local_t >= duration:
		return
	var progress := clampf(_part_local_t / duration, 0.0, 1.0)
	match kind:
		"fade", "crossfade", "fade_in":
			draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.0, 0.0, 1.0 - progress))
		"wipe", "wipe_left":
			draw_rect(Rect2(progress * sz.x, 0.0, sz.x * (1.0 - progress), sz.y), _pal(pal, 0))
		"curtain", "curtains":
			var cover := (1.0 - progress) * sz.y * 0.5
			draw_rect(Rect2(0.0, 0.0, sz.x, cover), _pal(pal, 0))
			draw_rect(Rect2(0.0, sz.y - cover, sz.x, cover), _pal(pal, 0))
		"checker", "dissolve":
			var cell := maxf(8.0, floor(sz.y / 14.0))
			var threshold := int(progress * 24.0)
			for yy in int(ceil(sz.y / cell)):
				for xx in int(ceil(sz.x / cell)):
					if posmod(xx * 7 + yy * 11, 24) >= threshold:
						draw_rect(Rect2(xx * cell, yy * cell, cell + 1.0, cell + 1.0), _pal(pal, 0))
		"flash", "white_flash":
			var limit := 0.28 if reduced_flash else 0.62
			draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 1.0, 1.0, pow(1.0 - progress, 2.0) * limit))


func _draw_sync_bezel(sz: Vector2, pal: Array, pulse: float) -> void:
	if pulse <= 0.12:
		return
	var alpha := pulse * (0.18 if reduced_flash else 0.32)
	draw_rect(Rect2(Vector2.ZERO, sz).grow(-1.0), _pal(pal, 7, alpha), false, 2.0)


func _draw_studio_hud(sz: Vector2, pal: Array, part: Dictionary) -> void:
	var f := Wb13.font()
	var hud_h := 20.0
	draw_rect(Rect2(0.0, 0.0, sz.x, hud_h), Color(0.0, 0.0, 0.0, 0.82))
	var part_name := str(part.get("name", part.get("title", "PART %02d" % (_part_index + 1)))).to_upper()
	var bpm := int(round(float(part.get("bpm", _project.get("bpm", 125.0)))))
	var left := "P%02d/%02d  %s" % [_part_index + 1, maxi(_parts.size(), 1), part_name]
	draw_string(f, Vector2(5.0, 15.0), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _pal(pal, 7))
	var right := "PAL 50  %03d BPM  %05.2fs" % [bpm, _timeline_t]
	if not _tracker_view.is_empty():
		right = "PAL 50  MOD %02X:%02X  %03d BPM" % [
			int(_tracker_view.get("pattern", 0)), int(_tracker_view.get("row", 0)),
			int(_tracker_view.get("bpm", bpm))]
	var right_w := f.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(f, Vector2(sz.x - right_w - 5.0, 15.0), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _pal(pal, 5))
	var progress := _timeline_t / maxf(_timeline_duration, 0.001)
	draw_rect(Rect2(0.0, hud_h, sz.x, 2.0), _pal(pal, 1, 0.9))
	draw_rect(Rect2(0.0, hud_h, floor(sz.x * progress), 2.0), _pal(pal, 6))
	if not _tracker_view.is_empty():
		var meter_x := sz.x - 89.0
		for i in 4:
			draw_rect(Rect2(meter_x + i * 20.0, hud_h + 5.0, 15.0, 3.0), _pal(pal, 1, 0.75))
			draw_rect(Rect2(meter_x + i * 20.0, hud_h + 5.0,
				floor(15.0 * _tracker_levels[i]), 3.0), _pal(pal, 6))

	# Optionale Build-Metriken aus dem Projektmodell; fehlende Werte bleiben
	# bewusst unaufdringlich, damit alte Projekte sauber aussehen.
	var cpu: Variant = part.get("cpu", part.get("cpu_cost", null))
	var chip: Variant = part.get("chip_kb", part.get("memory_kb", null))
	if cpu != null or chip != null:
		var diagnostics := "CPU %s%%  CHIP %sK" % [str(cpu if cpu != null else "--"), str(chip if chip != null else "---")]
		var dw := f.get_string_size(diagnostics, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(sz.x - dw - 10.0, hud_h + 5.0, dw + 8.0, 16.0), Color(0.0, 0.0, 0.0, 0.68))
		draw_string(f, Vector2(sz.x - dw - 6.0, hud_h + 17.0), diagnostics,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _pal(pal, 6))
