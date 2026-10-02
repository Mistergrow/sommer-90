extends FxLayer
## Gemeinsamer 2,5D-Wetterrenderer fuer Aussenorte und markierte Fenster.
##
## Der alte Effekt legte gleich helle Linien ueber das komplette Foto. Diese
## Fassung trennt Atmosphaere, drei Regentiefe-Ebenen und Bodenreaktion. Markierte
## Wandflaechen verdecken fernen Regen; in Innenraeumen wird ausschliesslich in
## den im SurfaceEditor markierten Fenstern gezeichnet.
##
## Config (type "weather", alles optional):
##   mode: "outdoor" | "window"
##   location_key: Schluessel aus location_surfaces.json
##   density: maximale Tropfenzahl bei Gewitter
##   ground_line: Bodenbeginn ohne markierte Bodenflaeche (0..1)
##   rain_gain, mist, splash_gain: ortsspezifisches Feintuning

const SurfaceGeometryData := preload("res://scripts/gfx/surface_geometry.gd")

const STATE_TINT := {
	"clouds": Color(0.10, 0.14, 0.19, 0.13),
	"rain": Color(0.055, 0.10, 0.16, 0.24),
	"storm": Color(0.035, 0.065, 0.12, 0.34),
}

var _time := 0.0
var _state := "clear"
var _mode := "outdoor"
var _location_key := ""
var _ground_line := 0.58
var _rain_gain := 1.0
var _mist_gain := 0.18
var _splash_gain := 1.0
var _color := Color(0.63, 0.76, 0.88, 0.42)
var _drops: Array[Dictionary] = []
var _clouds: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
var _windows: Array[PackedVector2Array] = []
var _floors: Array[PackedVector2Array] = []
var _occluders: Array[PackedVector2Array] = []
var _flash := 0.0
var _flash_cooldown := 3.8
var _rng := RandomNumberGenerator.new()


func _apply() -> void:
	_mode = str(cfg("mode", "outdoor"))
	_location_key = str(cfg("location_key", ""))
	_ground_line = clampf(float(cfg("ground_line", 0.58)), 0.25, 0.94)
	_rain_gain = clampf(float(cfg("rain_gain", 1.0)), 0.2, 2.0)
	_mist_gain = clampf(float(cfg("mist", 0.18)), 0.0, 1.0)
	_splash_gain = clampf(float(cfg("splash_gain", 1.0)), 0.0, 2.0)
	_color = to_color(cfg("color", null), _color)
	_load_surface_geometry()

	_rng.seed = 0xA1B2 ^ _location_key.hash()
	_drops.clear()
	_clouds.clear()
	_impacts.clear()
	var density := clampi(int(cfg("density", 230)), 48, 480)
	for _i in density:
		# Mehr Ferne als Kameratropfen. Das verhindert den alten Vorhang-Effekt.
		var depth := pow(_rng.randf(), 1.48)
		_drops.append({
			"u": _rng.randf(),
			"v": _rng.randf_range(-0.08, 1.02),
			"length": lerpf(0.005, 0.031, depth),
			"speed": lerpf(0.36, 1.28, depth),
			"width": lerpf(0.48, 1.48, depth),
			"depth": depth,
			"phase": _rng.randf() * TAU,
		})
	for _i in 12:
		_clouds.append({
			"u": _rng.randf_range(-0.15, 0.95),
			"v": _rng.randf_range(0.02, minf(_ground_line, 0.62)),
			"w": _rng.randf_range(0.22, 0.48),
			"h": _rng.randf_range(0.055, 0.15),
			"speed": _rng.randf_range(0.003, 0.012),
			"alpha": _rng.randf_range(0.025, 0.075),
		})
	for _i in 42:
		_impacts.append({
			"u": _rng.randf(),
			"v": _rng.randf_range(_ground_line, 0.985),
			"phase": _rng.randf(),
			"scale": _rng.randf_range(0.65, 1.28),
		})
	_state = _weather_state()
	visible = _state != "clear" and (_mode != "window" or not _windows.is_empty())
	set_process(true)
	queue_redraw()


func _load_surface_geometry() -> void:
	_windows.clear()
	_floors.clear()
	_occluders.clear()
	if _location_key.is_empty():
		return
	for raw: Variant in SurfaceGeometryData.surfaces_for(_location_key):
		if not raw is Dictionary:
			continue
		var surface := raw as Dictionary
		var polygon := SurfaceGeometryData.polygon_for(surface)
		if polygon.size() < 3:
			continue
		match str(surface.get("type", "wall")):
			"window": _windows.append(polygon)
			"floor": _floors.append(polygon)
			"wall", "ceiling": _occluders.append(polygon)


func _wm() -> Node:
	return get_node_or_null("/root/WeatherManager")


func _weather_state() -> String:
	var wm := _wm()
	if wm == null or Engine.is_editor_hint():
		return str(cfg("preview_state", "clear"))
	return str(wm.call("state"))


func _rain() -> float:
	var wm := _wm()
	if wm == null or Engine.is_editor_hint():
		return 1.0 if str(cfg("preview_state", "clear")) in ["rain", "storm"] else 0.0
	return float(wm.call("rain_intensity")) * _rain_gain


func _wind() -> float:
	var wm := _wm()
	if wm == null or Engine.is_editor_hint():
		return 0.55
	return float(wm.call("wind"))


func _process(delta: float) -> void:
	_state = _weather_state()
	var active := _state != "clear" and (_mode != "window" or not _windows.is_empty())
	if not active and _flash <= 0.001:
		visible = false
		return
	visible = true
	var motion_scale := 0.0 if _reduced_motion() else 1.0
	_time += minf(delta, 0.08) * motion_scale
	if _reduced_motion():
		_flash = 0.0
	if bool(cfg("flash", true)) and _state == "storm" and not _reduced_motion():
		_flash_cooldown -= delta
		if _flash_cooldown <= 0.0:
			_flash = 1.0
			_flash_cooldown = _rng.randf_range(4.2, 9.5)
	_flash = maxf(0.0, _flash - delta * 3.8)
	queue_redraw()


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/SettingsManager")
	return settings != null and bool(settings.call("value", "reduced_motion"))


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0 or _state == "clear":
		return
	_draw_atmosphere()
	var rain := clampf(_rain(), 0.0, 1.35)
	if rain > 0.001:
		_draw_rain(rain)
		_draw_ground_response(rain)
	if _flash > 0.001:
		_draw_storm_flash()


func _draw_atmosphere() -> void:
	var tint: Color = STATE_TINT.get(_state, Color.TRANSPARENT)
	if _mode == "window":
		for polygon: PackedVector2Array in _windows:
			var pixels := _polygon_to_pixels(polygon)
			draw_colored_polygon(pixels, Color(tint.r, tint.g, tint.b, tint.a * 1.18))
		return

	# Grundtönung nimmt sonnigen Masterbildern bei Regen die Goldstimmung.
	draw_rect(Rect2(Vector2.ZERO, size), tint)
	var cloud_strength := 0.58 if _state == "clouds" else (0.86 if _state == "rain" else 1.0)
	for cloud: Dictionary in _clouds:
		var u := wrapf(float(cloud["u"]) + _time * float(cloud["speed"]) * _wind(), -0.32, 1.12)
		var center := px(u, float(cloud["v"]))
		var extent := Vector2(float(cloud["w"]) * size.x, float(cloud["h"]) * size.y)
		var rect := Rect2(center - extent * 0.5, extent)
		var alpha := float(cloud["alpha"]) * cloud_strength
		draw_texture_rect(dot_texture(), rect, false, Color(0.20, 0.27, 0.35, alpha))

	# Mehrere weiche Horizontstreifen statt einer deckenden Nebelplatte.
	if _mist_gain > 0.001:
		var mist_alpha := _mist_gain * (0.035 if _state == "clouds" else 0.075)
		for i in 5:
			var y := size.y * (_ground_line - 0.055 + i * 0.027)
			draw_rect(Rect2(0.0, y, size.x, size.y * 0.038),
				Color(0.43, 0.55, 0.63, mist_alpha * (1.0 - i * 0.13)))


func _draw_rain(rain: float) -> void:
	var wind := _wind()
	var direction := Vector2(0.075 + wind * 0.27, 1.0).normalized()
	var count := mini(_drops.size(), int(float(_drops.size()) * clampf(rain, 0.0, 1.0)))
	for i in count:
		var drop: Dictionary = _drops[i]
		var depth := float(drop["depth"])
		var v := wrapf(float(drop["v"]) + _time * float(drop["speed"]) * (0.72 + rain * 0.28), -0.08, 1.06)
		var u := wrapf(float(drop["u"]) + _time * wind * lerpf(0.010, 0.038, depth)
			+ sin(_time * 0.8 + float(drop["phase"])) * 0.0012, -0.05, 1.05)
		var length_uv := float(drop["length"]) * (0.82 + rain * 0.22)
		var a_uv := Vector2(u, v)
		var b_uv := a_uv + Vector2(direction.x * length_uv * size.y / size.x,
			direction.y * length_uv)
		if not _rain_segment_visible(a_uv, b_uv, depth):
			continue
		var alpha := _color.a * lerpf(0.15, 0.72, depth) * clampf(rain, 0.0, 1.0)
		# Kameranahe Schlieren bleiben selten und etwas kraeftiger; Ferne ist fein.
		if depth > 0.84:
			alpha *= 0.76
		var a := a_uv * size
		var b := b_uv * size
		draw_line(a, b, Color(_color.r, _color.g, _color.b, alpha),
			float(drop["width"]), true)
		if depth > 0.92:
			draw_line(a + Vector2(1.0, 0.0), b + Vector2(1.0, 0.0),
				Color(0.08, 0.15, 0.22, alpha * 0.22), float(drop["width"]) * 0.7, true)


func _rain_segment_visible(a_uv: Vector2, b_uv: Vector2, depth: float) -> bool:
	if _mode == "window":
		return _inside_same_polygon(a_uv, b_uv, _windows)
	# Nur wenige Kameratropfen duerfen ueber nahe Waende/Fassaden laufen.
	if depth < 0.82 and _point_in_any((a_uv + b_uv) * 0.5, _occluders):
		return false
	return true


func _draw_ground_response(rain: float) -> void:
	if _mode == "window" or _splash_gain <= 0.001:
		return
	var active_count := clampi(int(15.0 * rain * _splash_gain), 0, _impacts.size())
	for i in active_count:
		var impact: Dictionary = _impacts[i]
		var uv := Vector2(float(impact["u"]), float(impact["v"]))
		if not _ground_contains(uv) or _point_in_any(uv, _occluders):
			continue
		var life := fposmod(_time * (0.72 + i * 0.006) + float(impact["phase"]), 1.0)
		if life > 0.15:
			continue
		var center := uv * size
		var impact_scale := float(impact["scale"])
		var fade := (1.0 - life / 0.15) * rain
		var radius := lerpf(1.2, 9.0 * impact_scale, life / 0.15)
		draw_arc(center, radius, PI * 1.06, PI * 1.94, 10,
			Color(0.58, 0.78, 0.91, 0.22 * fade), 0.8, true)
		if life < 0.055:
			draw_line(center, center + Vector2(-2.4, -4.5) * impact_scale,
				Color(0.66, 0.82, 0.92, 0.25 * fade), 0.8, true)
			draw_line(center, center + Vector2(2.1, -3.7) * impact_scale,
				Color(0.66, 0.82, 0.92, 0.21 * fade), 0.8, true)

	# Ruhige, sehr schwache Nassreflexe erden den Regen auf fotografischem Boden.
	for i in mini(12, active_count):
		var impact: Dictionary = _impacts[_impacts.size() - 1 - i]
		var uv := Vector2(float(impact["u"]), float(impact["v"]))
		if not _ground_contains(uv) or _point_in_any(uv, _occluders):
			continue
		var center := uv * size
		var sheen_size := Vector2(size.x * 0.035 * float(impact["scale"]), size.y * 0.008)
		draw_texture_rect(dot_texture(), Rect2(center - sheen_size * 0.5, sheen_size), false,
			Color(0.42, 0.66, 0.82, 0.018 * rain))


func _draw_storm_flash() -> void:
	var strength := _flash * _flash
	if _mode == "window":
		for polygon: PackedVector2Array in _windows:
			draw_colored_polygon(_polygon_to_pixels(polygon), Color(0.72, 0.86, 1.0, strength * 0.32))
		return
	# Blitzlicht sitzt im Himmel und spiegelt nur schwach auf dem Boden.
	draw_rect(Rect2(0.0, 0.0, size.x, size.y * minf(_ground_line + 0.16, 0.8)),
		Color(0.67, 0.80, 1.0, strength * 0.28))
	draw_rect(Rect2(0.0, size.y * _ground_line, size.x, size.y * (1.0 - _ground_line)),
		Color(0.49, 0.66, 0.82, strength * 0.08))


func _ground_contains(uv: Vector2) -> bool:
	if not _floors.is_empty():
		return _point_in_any(uv, _floors)
	return uv.y >= _ground_line


func _point_in_any(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func _inside_same_polygon(a: Vector2, b: Vector2,
		polygons: Array[PackedVector2Array]) -> bool:
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(a, polygon) \
				and Geometry2D.is_point_in_polygon(b, polygon):
			return true
	return false


func _polygon_to_pixels(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		result.append(point * size)
	return result


## Diagnosevertrag fuer visuelle Tests und den SurfaceEditor.
func debug_profile() -> Dictionary:
	return {
		"mode": _mode,
		"location_key": _location_key,
		"state": _state,
		"windows": _windows.size(),
		"floors": _floors.size(),
		"occluders": _occluders.size(),
		"drops": _drops.size(),
		"ground_line": _ground_line,
	}
