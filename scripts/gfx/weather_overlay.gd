extends Control
## WeatherOverlay — Wetter-VFX über dem Zimmer (VFX-Bibel EFFECT_002/003/007).
## Als Kind des RoomCompositors bei z 20 (über den Layern, unter dem DekoEditor).
## Nutzt die vorhandenen Markierungen aus room_anchors.json:
##   fenster_links/rechts → Regen + beschlagenes Glas
##   gardine_links/rechts → sanfter Windschimmer
## Zustand/Intensität kommen vom WeatherManager. Kein eigenes Asset — reine
## prozedurale Zeichnung, bis ein OVERLAY_WEATHER_*-Bild sie ersetzt.

## Multiply-Tönung des Außenblicks je Wetter (VFX-Bibel: WindowOutside).
## clear = kein Eintrag (Fenster bleibt unangetastet).
const OUTSIDE_TINT := {
	"clouds": Color(0.72, 0.75, 0.80),
	"rain": Color(0.52, 0.57, 0.66),
	"storm": Color(0.38, 0.44, 0.55),
}
const RAIN_WINDOW_MATERIAL := preload("res://materials/weather/rain_window_aaa_material.tres")

var comp: Control = null   # der RoomCompositor (Transform + Quads)
var _time := 0.0
var _outside: Array = []   # [{node: Polygon2D, quad: String}] — an comp gehängt
var _drops: Array = []     # nasse Scheibe: Tropfen-Feld (u,v,r,run,phase)
var _floor_projection: Control = null  # Wet-Glass-Licht auf Teppich/Boden, hinter dem Tisch
var _window_shader_layers: Array[Polygon2D] = []
var _weather_state := "clear"
var _rain_intensity := 0.0
var _wind := 0.18
var _weather_poll_t := 0.0
var _geometry_dirty := true
var _last_size := Vector2(-1.0, -1.0)
var _last_depth_look := Vector2(INF, INF)
var _glass_impact_t := 0.45
var _glass_impact_burst_left := 0
var _glass_impact_rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reseed_glass_impacts()
	# Absolute Weltlage 4: über dem leeren Raum (z0), aber unter Kabeln (z5–7)
	# und dem Schreibtisch (z8). Dessen echte Alpha-Silhouette übernimmt damit
	# die physikalisch korrekte Verdeckung, ohne eine zweite Tischmaske.
	_floor_projection = _RainFloorProjection.new()
	_floor_projection.name = "RainFloorProjection"
	_floor_projection.set("comp", comp)
	_floor_projection.z_as_relative = false
	_floor_projection.z_index = 4
	_floor_projection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_floor_projection)
	_ensure_window_shader_layers()
	var weather_manager := get_node_or_null("/root/WeatherManager")
	if weather_manager != null:
		if weather_manager.has_signal("weather_changed"):
			weather_manager.weather_changed.connect(_on_weather_changed)
		_refresh_weather(str(weather_manager.call("state")))
	resized.connect(_mark_geometry_dirty)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or comp == null or comp.edit_mode:
		return
	if not bool(SettingsManager.value("reduced_motion")):
		_time += minf(delta, 0.08)
	# Save-Laden und Debug-Overrides koennen das Datum ohne day_changed setzen.
	# Vier billige Cache-Abfragen pro Sekunde halten das Overlay trotzdem synchron.
	_weather_poll_t -= delta
	if _weather_poll_t <= 0.0:
		_weather_poll_t = 0.25
		var actual := str(WeatherManager.state())
		if actual != _weather_state:
			_refresh_weather(actual)
	var depth_look: Vector2 = comp.depth_look() if comp.has_method("depth_look") else Vector2.ZERO
	if not size.is_equal_approx(_last_size) or not depth_look.is_equal_approx(_last_depth_look):
		_geometry_dirty = true
	if _geometry_dirty:
		_update_outside()
		_last_size = size
		_last_depth_look = depth_look
	_update_window_shader_layers(_geometry_dirty)
	if _floor_projection != null and is_instance_valid(_floor_projection):
		if _geometry_dirty:
			_floor_projection.position = Vector2.ZERO
			_floor_projection.size = size
		_floor_projection.set("time", _time)
		_floor_projection.set("intensity", _rain_intensity)
		_floor_projection.visible = _rain_intensity > 0.0
		if _rain_intensity > 0.0:
			_floor_projection.queue_redraw()
	_update_glass_impact_audio(delta)
	_geometry_dirty = false
	queue_redraw()


func _on_weather_changed(new_state: String) -> void:
	_refresh_weather(new_state)


func _refresh_weather(new_state: String) -> void:
	var state_changed := new_state != _weather_state
	_weather_state = new_state
	_rain_intensity = float(WeatherManager.RAIN.get(new_state, 0.0))
	_wind = float(WeatherManager.WIND.get(new_state, 0.18))
	if state_changed:
		_reseed_glass_impacts()
	_geometry_dirty = true
	queue_redraw()


func _mark_geometry_dirty() -> void:
	_geometry_dirty = true


func _reseed_glass_impacts() -> void:
	# Reproduzierbar je Spieltag, aber nicht im Takt der Shader-Loops. Zwei
	# verschiedene Zeitraster verhindern hörbare Wiederholungsschleifen.
	# Im Editor kann der @tool-Compositor vor der vollständigen Autoload-
	# Initialisierung rekonstruiert werden; get() hält auch diesen Pfad sicher.
	var day_value: Variant = TimeManager.get("day_counter") if TimeManager != null else null
	var current_day := int(day_value) if typeof(day_value) in [TYPE_INT, TYPE_FLOAT] else 0
	_glass_impact_rng.seed = 0x71A55 ^ (current_day * 2654435761) ^ hash(_weather_state)
	_glass_impact_burst_left = 0
	_glass_impact_t = _glass_impact_rng.randf_range(0.18, 0.72)


func _update_glass_impact_audio(delta: float) -> void:
	if _rain_intensity <= 0.0 or not is_visible_in_tree() \
			or GameManager.state != GameManager.State.PLAYING \
			or GameManager.current_location_id != "room":
		return
	_glass_impact_t -= delta
	if _glass_impact_t > 0.0:
		return
	var storm := _weather_state == "storm"
	var left := _glass_impact_rng.randf() < 0.5
	var heavy := storm and _glass_impact_rng.randf() < 0.48
	var sfx := "rain_glass_heavy_" if heavy else "rain_glass_"
	sfx += "left" if left else "right"
	# Der Loop bleibt das eigentliche Regenbett. Einzelkontakte liegen 10–14 dB
	# darunter und werden durch Tonhöhenstreuung nicht zum Metronom.
	AudioManager.play(sfx, 0.13, -10.5 if heavy else -13.5)
	if _glass_impact_burst_left > 0:
		_glass_impact_burst_left -= 1
		_glass_impact_t = _glass_impact_rng.randf_range(0.065, 0.18)
		return
	var burst_chance := 0.52 if storm else 0.20
	if _glass_impact_rng.randf() < burst_chance:
		_glass_impact_burst_left = _glass_impact_rng.randi_range(1, 3 if storm else 2)
		_glass_impact_t = _glass_impact_rng.randf_range(0.08, 0.21)
	else:
		_glass_impact_t = _glass_impact_rng.randf_range(0.22, 0.68) if storm \
			else _glass_impact_rng.randf_range(0.48, 1.35)


# ---------------------------------------------- Außenblick durchs Fenster

## Zeigt den Fensterbereich des Basisbildes ein zweites Mal (auf die Glas-Quads
## maskiert) und dunkelt ihn per Multiply ab — so trübt sich der Himmel draußen
## bei Regen/Gewitter ein, ganz ohne extra Außen-Asset. Genau die Idee: den
## Master-Room zweimal nutzen und die durchs Fenster sichtbare Kopie verändern.
func _update_outside() -> void:
	_ensure_outside()
	if _outside.is_empty():
		return
	var t: Dictionary = comp._master_transform()
	var scale_factor: float = t["scale"]
	var offset: Vector2 = t["offset"]
	var master_size: Vector2 = t["master"]
	var quads: Dictionary = comp._quads()
	var tint: Variant = OUTSIDE_TINT.get(_weather_state, null)
	for entry in _outside:
		var node: Polygon2D = entry["node"]
		if not is_instance_valid(node):
			continue
		if tint == null or not quads.has(entry["quad"]):
			node.visible = false
			continue
		var corners: Array = quads[entry["quad"]].get("corners", [])
		var tex_size: Vector2 = node.texture.get_size() if node.texture != null else master_size
		var uv_scale := tex_size / master_size
		var poly := PackedVector2Array()
		var uv := PackedVector2Array()
		for c in corners:
			var mp := Vector2(c[0], c[1])
			poly.append(comp.project_master_point(mp, "base") if comp.has_method("project_master_point") \
				else offset + mp * scale_factor)
			uv.append(Vector2(c[0], c[1]) * uv_scale)
		node.polygon = poly
		node.uv = uv
		node.color = tint
		node.visible = true


func _ensure_outside() -> void:
	if not _outside.is_empty() or comp == null:
		return
	var tex: Texture2D = comp.base_texture()
	if tex == null:
		return
	for wname in ["fenster_links", "fenster_rechts"]:
		var poly := Polygon2D.new()
		poly.texture = tex
		poly.z_index = 2  # über dem Basisbild (0), unter den Regenschlieren (20)
		poly.visible = false
		comp.add_child(poly)
		_outside.append({"node": poly, "quad": wname})


func _ensure_window_shader_layers() -> void:
	if not _window_shader_layers.is_empty() or comp == null:
		return
	for index in 2:
		var layer := Polygon2D.new()
		layer.name = "WetGlassShader%d" % (index + 1)
		layer.z_as_relative = false
		# Fensterglas liegt räumlich hinter Tisch/Monitor (Desk-Weltlage z8), aber
		# vor Außenblick und Basis. So verdeckt der echte CRT-Rahmen den Regen,
		# statt dass ein rechteckiges Fensterpolygon in den Monitor schneidet.
		layer.z_index = 4
		layer.visible = false
		# Gespeicherte, im Godot-Dateisystem anklickbare Materialressource. Jede
		# Fensterscheibe erhält eine eigene Kopie, weil Seed/UV/Time verschieden sind.
		var shader_material := RAIN_WINDOW_MATERIAL.duplicate(true) as ShaderMaterial
		shader_material.set_shader_parameter("seed", 2.7 + float(index) * 13.1)
		layer.material = shader_material
		comp.add_child(layer)
		_window_shader_layers.append(layer)


func _update_window_shader_layers(rebuild_geometry := true) -> void:
	_ensure_window_shader_layers()
	if _window_shader_layers.is_empty() or comp == null:
		return
	var quads: Dictionary = comp._quads() if rebuild_geometry else {}
	var raining := _rain_intensity > 0.0
	var names := ["fenster_links", "fenster_rechts"]
	var transform: Dictionary = comp._master_transform() if rebuild_geometry else {}
	var master_size: Vector2 = transform.get("master", Vector2(1920, 1080))
	var source_texture: Texture2D = comp.base_texture() if rebuild_geometry else null
	var texture_size := source_texture.get_size() if source_texture != null else master_size
	for index in _window_shader_layers.size():
		var layer := _window_shader_layers[index]
		var window_name: String = names[index]
		if not raining:
			layer.visible = false
			continue
		if rebuild_geometry:
			if not quads.has(window_name):
				layer.visible = false
				continue
			var corners: Array = quads[window_name].get("corners", [])
			if corners.size() != 4:
				layer.visible = false
				continue
			var polygon := PackedVector2Array()
			var texture_uv := PackedVector2Array()
			var uv_min := Vector2(INF, INF)
			var uv_max := Vector2(-INF, -INF)
			for corner: Variant in corners:
				var master_point := Vector2(float(corner[0]), float(corner[1]))
				polygon.append(comp.project_master_point(master_point, "base"))
				var normalized := master_point / master_size
				uv_min = uv_min.min(normalized)
				uv_max = uv_max.max(normalized)
				texture_uv.append(normalized * texture_size)
			layer.polygon = polygon
			layer.texture = source_texture
			layer.uv = texture_uv
			var geometry_material := layer.material as ShaderMaterial
			geometry_material.set_shader_parameter("uv_rect", Vector4(uv_min.x, uv_min.y,
				uv_max.x, uv_max.y))
		var shader_material := layer.material as ShaderMaterial
		shader_material.set_shader_parameter("time", _time)
		shader_material.set_shader_parameter("intensity", _rain_intensity)
		shader_material.set_shader_parameter("wind", _wind)
		shader_material.set_shader_parameter("storm_factor", 1.0 if _weather_state == "storm" else 0.0)
		shader_material.set_shader_parameter("impact_strength", 1.18 if _weather_state == "storm" else 0.92)
		layer.visible = true


func _exit_tree() -> void:
	for entry: Dictionary in _outside:
		var outside_node: Node = entry.get("node")
		if is_instance_valid(outside_node):
			outside_node.queue_free()
	for layer: Polygon2D in _window_shader_layers:
		if is_instance_valid(layer):
			layer.queue_free()


func _draw() -> void:
	if Engine.is_editor_hint() or comp == null or comp.edit_mode:
		return
	var t: Dictionary = comp._master_transform()
	var scale_factor: float = t["scale"]
	var offset: Vector2 = t["offset"]
	var quads: Dictionary = comp._quads()

	var intensity := _rain_intensity
	var wind := _wind

	# Fenster: beschlagenes Glas + Regenschlieren, streng auf die Quads maskiert.
	for wname in ["fenster_links", "fenster_rechts"]:
		if not quads.has(wname):
			continue
		var poly := _screen_poly(quads[wname].get("corners", []), offset, scale_factor)
		if poly.size() < 3:
			continue
		if intensity > 0.0:
			# GPU-Wet-Glass ersetzt die alten gleichförmigen CPU-Striche. Fallback nur,
			# falls das Shaderlayer in einer Minimal-/Testszene nicht aufgebaut wurde.
			if _window_shader_layers.is_empty():
				_draw_rain(poly, intensity, wind, scale_factor)
				_draw_wet_glass(poly, intensity, scale_factor)

	# Gardinen: sanfter Lichtschimmer, der mit dem Wind über den Stoff wandert.
	for cname in ["gardine_links", "gardine_rechts"]:
		if not quads.has(cname):
			continue
		var poly := _screen_poly(quads[cname].get("corners", []), offset, scale_factor)
		if poly.size() >= 3:
			_draw_curtain(poly, wind, float(hash(cname) % 100) * 0.063)

	if _weather_state == "storm":
		_draw_lightning()


# ------------------------------------------------------------- Fenster

func _draw_rain(poly: PackedVector2Array, intensity: float, wind: float, scale_factor: float) -> void:
	var bb := _bounds(poly)
	# Drei optische Tiefen statt gleichförmiger Striche: ferne Nieselpartikel,
	# mittlere Schlieren und wenige helle Tropfen direkt vor der Scheibe.
	var count := int(54.0 + 104.0 * intensity)
	for i in count:
		var depth := 0.18 + float(posmod(i * 47, 83)) / 100.0
		var speed := lerpf(65.0, 245.0, depth) * (0.55 + intensity * 0.75) * scale_factor
		var length := lerpf(3.5, 17.0, depth) * scale_factor * (0.76 + intensity * 0.45)
		var lean := (1.0 + wind * lerpf(2.0, 8.0, depth)) * scale_factor
		var x := bb.position.x + fposmod(float(i) * 41.77 + sin(_time * 0.7 + i * 1.91) * 5.0 + _time * wind * 19.0, bb.size.x)
		var y := bb.position.y + fposmod(float(i) * 67.13 + _time * speed, maxf(bb.size.y - length, 1.0))
		var p := Vector2(x, y)
		if Geometry2D.is_point_in_polygon(p, poly):
			var endpoint := p + Vector2(-lean, length)
			var alpha := (0.07 + depth * 0.24) * (0.45 + intensity * 0.75)
			# Dunkler Rand + schmale kalte Lichtkante erzeugen Volumen ohne Blur-Shader.
			if depth > 0.58:
				draw_line(p + Vector2(scale_factor, 0.0), endpoint + Vector2(scale_factor, 0.0),
					Color(0.18, 0.25, 0.34, alpha * 0.46), maxf(1.0, depth * 2.1 * scale_factor), true)
			draw_line(p, endpoint, Color(0.78, 0.88, 0.98, alpha),
				maxf(0.7, depth * 1.35 * scale_factor), true)
			if depth > 0.82 and i % 7 == 0:
				draw_circle(endpoint, maxf(0.7, 1.25 * scale_factor), Color(0.91, 0.96, 1.0, alpha * 0.7))


# ------------------------------------------------------------- Gardinen

## Weicher heller Streifen, der langsam über die Gardine wandert — liest sich
## als Licht durch bewegten Stoff. Amplitude/Tempo folgen dem Wind.
func _draw_curtain(poly: PackedVector2Array, wind: float, phase: float) -> void:
	var bb := _bounds(poly)
	if bb.size.x < 4.0:
		return
	var sway := sin(_time * (0.5 + 0.9 * wind) + phase)
	var cx := bb.position.x + bb.size.x * (0.5 + 0.34 * sway)
	var peak := 0.05 + 0.07 * wind
	var band := maxf(bb.size.x * 0.09, 3.0)
	# weiche Kanten durch übereinandergelegte, außen dünner werdende Streifen
	for k in range(-2, 3):
		var a := peak * (1.0 - absf(float(k)) / 3.0)
		var strip := Rect2(cx + float(k) * band - band * 0.5, bb.position.y, band, bb.size.y)
		draw_rect(_clamp_rect(strip, bb), Color(1.0, 0.98, 0.92, a))


# ------------------------------------------------------------- Gewitter

func _draw_lightning() -> void:
	if bool(SettingsManager.value("reduced_motion")):
		return
	# Gewitter-Blitz: heller, kurzer Doppel-/Dreifach-Schlag, der den GANZEN Raum
	# blau-weiß aufblitzen lässt (etwa alle 6,4 s, kein Dauerstroboskop).
	var c := fmod(_time, 6.4)
	var a := 0.0
	if c < 0.06:
		a = 0.62                      # greller Erstschlag
	elif c < 0.12:
		a = 0.20                      # kurzes Abklingen
	elif c > 0.16 and c < 0.22:
		a = 0.45                      # zweiter Schlag
	elif c > 0.30 and c < 0.35:
		a = 0.18                      # dritter, schwacher Nachschlag
	if a > 0.0:
		# ganzflächiges Aufblitzen + weicher Helligkeits-Verlauf von oben
		# (vom Fenster her), ohne harte Kante.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.91, 1.0, a))
		var bands := 14
		var band_h := size.y * 0.62 / float(bands)
		for i in bands:
			var f := float(i) / float(bands)
			draw_rect(Rect2(0.0, band_h * float(i), size.x, band_h + 1.0),
				Color(0.93, 0.96, 1.0, a * 0.5 * (1.0 - f)))


# ------------------------------------------------- Nasse Scheibe (Tropfen)

## Anhaftende, lichtbrechende Tropfen auf der Fensterscheibe + herablaufende
## Rinnsale. Positionen deterministisch je Fenster, Menge/Größe folgt der
## Regenstärke. Bilineare Abbildung ins (evtl. schräge) Fenster-Viereck.
func _ensure_drops() -> void:
	if not _drops.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x77A7E7
	for i in 112:
		_drops.append({
			"u": rng.randf(), "v": rng.randf(),
			"r": rng.randf_range(0.7, 4.6),
			"run": 0.0 if rng.randf() < 0.64 else rng.randf_range(0.018, 0.105),
			"phase": rng.randf() * TAU,
			"stretch": rng.randf_range(0.25, 1.15),
			"depth": rng.randf_range(0.25, 1.0),
		})


func _quad_point(poly: PackedVector2Array, u: float, v: float) -> Vector2:
	# poly = 4 Ecken (Reihenfolge aus der Config). Bilineare Interpolation.
	var top := poly[0].lerp(poly[1], u)
	var bot := poly[3].lerp(poly[2], u)
	return top.lerp(bot, v)


func _draw_wet_glass(poly: PackedVector2Array, intensity: float, scale_factor: float) -> void:
	if poly.size() < 4:
		return
	_ensure_drops()
	# Fast unsichtbarer Wasserfilm: kalte Lasur und wandernde, sehr weiche
	# Spiegelbänder. Das Fenster bleibt lesbar, wirkt aber wirklich nass.
	draw_colored_polygon(poly, Color(0.48, 0.59, 0.72, 0.025 + 0.035 * intensity))
	var bb := _bounds(poly)
	for band_index in 5:
		var band_u := fposmod(float(band_index) * 0.223 + _time * 0.006, 1.0)
		var a := _quad_point(poly, band_u, 0.04)
		var b := _quad_point(poly, clampf(band_u - 0.07, 0.0, 1.0), 0.96)
		draw_line(a, b, Color(0.86, 0.92, 1.0, 0.012 + 0.018 * intensity), maxf(2.0, bb.size.x * 0.018), true)

	var visible_count := int(48.0 + intensity * 64.0)
	for index in mini(visible_count, _drops.size()):
		var d: Dictionary = _drops[index]
		var u: float = d["u"]
		var run: float = d["run"]
		var v: float = d["v"]
		if run > 0.0:
			v = fposmod(v + _time * run * (0.5 + intensity), 1.0)  # läuft herab
		var wobble := sin(_time * 0.43 + float(d["phase"])) * 0.004 * float(d["stretch"])
		var p := _quad_point(poly, clampf(u + wobble, 0.0, 1.0), v)
		var depth: float = d["depth"]
		var r: float = d["r"] * scale_factor * (0.5 + 0.55 * intensity) * lerpf(0.72, 1.15, depth)
		var body_len := r * (0.45 + float(d["stretch"]) * 1.25)
		# Laufspuren bestehen aus mehreren leicht versetzten Segmenten; dadurch
		# wirken sie organisch und nicht wie exakt senkrechte Vektorlinien.
		if run > 0.0:
			var points := PackedVector2Array()
			for segment in 5:
				var segment_v := maxf(v - 0.12 + float(segment) * 0.03, 0.0)
				var segment_u := clampf(u + sin(float(segment) * 1.7 + float(d["phase"])) * 0.004, 0.0, 1.0)
				points.append(_quad_point(poly, segment_u, segment_v))
			if points.size() > 1:
				draw_polyline(points, Color(0.62, 0.73, 0.86, 0.055 + 0.075 * intensity), maxf(0.8, r * 0.42), true)
		# Tropfenkörper: längliche Silhouette, Schattenkante, Lichtkern und winziger
		# caustic highlight am unteren Rand.
		var head := p - Vector2(0.0, body_len)
		draw_line(head, p, Color(0.22, 0.29, 0.39, 0.08 + 0.08 * intensity), maxf(1.0, r * 1.55), true)
		draw_line(head + Vector2(-r * 0.18, 0.0), p + Vector2(-r * 0.12, 0.0),
			Color(0.72, 0.83, 0.94, 0.09 + 0.09 * intensity), maxf(0.7, r * 0.55), true)
		draw_circle(p, r, Color(0.66, 0.78, 0.91, (0.06 + 0.09 * depth) * intensity))
		draw_circle(p + Vector2(r * 0.18, r * 0.30), r * 0.34,
			Color(0.96, 0.99, 1.0, (0.15 + 0.11 * sin(_time * 1.7 + float(d["phase"]))) * intensity))
		draw_arc(p, r, PI * 1.05, PI * 1.94, 9, Color(0.25, 0.32, 0.42, 0.16 * intensity), maxf(0.7, r * 0.14), true)

	# Vereinzelte Auftreffer unten am Rahmen: kurze Ellipsen aus gestauchten Bögen.
	for i in int(3.0 + intensity * 5.0):
		var phase := fposmod(_time * (0.37 + i * 0.031) + i * 0.173, 1.0)
		if phase > 0.18:
			continue
		var center := _quad_point(poly, fposmod(i * 0.219, 0.92) + 0.04, 0.94)
		var radius := (2.0 + phase * 32.0) * scale_factor
		draw_arc(center, radius, PI * 1.12, PI * 1.88, 12,
			Color(0.83, 0.91, 1.0, (0.18 - phase * 0.8) * intensity), maxf(0.7, scale_factor), true)


# ------------------------------------------------------------- Helfer

func _screen_poly(corners: Array, offset: Vector2, scale_factor: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for c in corners:
		var mp := Vector2(c[0], c[1])
		poly.append(comp.project_master_point(mp, "base") if comp != null and comp.has_method("project_master_point") \
			else offset + mp * scale_factor)
	return poly


func _bounds(poly: PackedVector2Array) -> Rect2:
	var top_left := Vector2(INF, INF)
	var bottom_right := Vector2(-INF, -INF)
	for p in poly:
		top_left = top_left.min(p)
		bottom_right = bottom_right.max(p)
	return Rect2(top_left, (bottom_right - top_left).max(Vector2.ONE))


func _clamp_rect(r: Rect2, bounds: Rect2) -> Rect2:
	var left := maxf(r.position.x, bounds.position.x)
	var right := minf(r.position.x + r.size.x, bounds.position.x + bounds.size.x)
	return Rect2(left, r.position.y, maxf(right - left, 0.0), r.size.y)


## Indirekte Projektion des nassen Fensters auf den Boden. Keine Regentropfen
## im Zimmer: Das Glas bricht das kühle Außenlicht in langsame, unscharfe
## Bänder. Auf dem Hochflor-Teppich zerfallen sie zusätzlich in kurze Fasern.
## Der Node liegt hinter dem RGBA-Schreibtisch; Holz und Schubladen verdecken
## den Effekt automatisch, nur die echte Bodenöffnung bleibt sichtbar.
class _RainFloorProjection:
	extends Control

	const REFLECTION_MATERIAL := preload("res://materials/weather/rain_floor_reflection_material.tres")

	var comp: Control = null
	var time := 0.0
	var intensity := 0.0
	var reflection: Polygon2D = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		reflection = Polygon2D.new()
		reflection.name = "ActualWindowReflection"
		reflection.z_index = 1
		reflection.visible = false
		var shader_material := REFLECTION_MATERIAL.duplicate(true) as ShaderMaterial
		reflection.material = shader_material
		add_child(reflection)

	func _draw() -> void:
		if comp == null or Engine.is_editor_hint() or bool(comp.get("edit_mode")) \
				or intensity <= 0.001:
			if reflection != null:
				reflection.visible = false
			return
		var quads: Dictionary = comp.call("_quads")
		if not quads.has("rain_floor_projection"):
			return
		var corners: Array = quads["rain_floor_projection"].get("corners", [])
		if corners.size() != 4:
			return
		var poly := PackedVector2Array()
		for corner: Variant in corners:
			var master := Vector2(float(corner[0]), float(corner[1]))
			poly.append(comp.call("project_master_point", master, "base"))
		_update_reflection(poly, quads)

		# Kühler diffuser Grundbounce. Mehrere eingezogene Polygone ergeben eine
		# gefederte Kante statt eines sichtbaren Vektor-Trapezes.
		var center := Vector2.ZERO
		for point: Vector2 in poly:
			center += point
		center /= float(poly.size())

		# Lesbare perspektivische Fensterprojektion. Die beiden Scheibenfelder
		# bilden auf dem hellen Teppich einen kalten, weichen Lichtkörper; Mittel-
		# und Querholm bleiben als dunkle Unterbrechung erkennbar. Weil der gesamte
		# Node auf Weltlage z4 liegt, verdecken Tisch (z8), Beine und Kabel dieses
		# Licht weiterhin physikalisch korrekt.
		for pane_range: Vector2 in [Vector2(0.055, 0.472), Vector2(0.528, 0.945)]:
			var pane := PackedVector2Array([
				_bilerp(poly, pane_range.x, 0.055),
				_bilerp(poly, pane_range.y, 0.055),
				_bilerp(poly, pane_range.y - 0.035, 0.94),
				_bilerp(poly, pane_range.x + 0.035, 0.94),
			])
			draw_colored_polygon(pane, Color(0.14, 0.38, 0.76, intensity * 0.22))
		var center_frame := PackedVector2Array([
			_bilerp(poly, 0.482, 0.03), _bilerp(poly, 0.518, 0.03),
			_bilerp(poly, 0.525, 0.97), _bilerp(poly, 0.475, 0.97),
		])
		draw_colored_polygon(center_frame, Color(0.015, 0.035, 0.075, intensity * 0.30))
		var cross_frame := PackedVector2Array([
			_bilerp(poly, 0.05, 0.48), _bilerp(poly, 0.95, 0.48),
			_bilerp(poly, 0.95, 0.525), _bilerp(poly, 0.05, 0.525),
		])
		draw_colored_polygon(cross_frame, Color(0.02, 0.045, 0.085, intensity * 0.22))

		for ring in 9:
			var factor := lerpf(1.0, 0.64, float(ring) / 8.0)
			var inset := PackedVector2Array()
			for point: Vector2 in poly:
				inset.append(center + (point - center) * factor)
			var alpha := intensity * (0.014 + float(ring) * 0.0032)
			draw_colored_polygon(inset, Color(0.25, 0.45, 0.70, alpha))

		# Langsame Wet-Glass-Caustics. Breite dunkle Brechkante + weicher kalter
		# Kern; auf Teppich niemals als scharfer Lichtstrahl zeichnen.
		for index in 21:
			var phase := float(index) * 1.937
			var u := fposmod(float(index) * 0.173 + sin(time * 0.11 + phase) * 0.035, 1.0)
			var v := fposmod(float(index) * 0.283 + time * (0.004 + float(index % 4) * 0.0015), 1.0)
			var bend := sin(time * 0.23 + phase) * 0.028
			var a := _bilerp(poly, clampf(u - 0.055 + bend, 0.0, 1.0), clampf(v - 0.018, 0.0, 1.0))
			var b := _bilerp(poly, clampf(u + 0.055 + bend, 0.0, 1.0), clampf(v + 0.020, 0.0, 1.0))
			var pulse := 0.55 + 0.45 * sin(time * 0.37 + phase)
			draw_line(a + Vector2(0.0, 1.2), b + Vector2(0.0, 1.2),
				Color(0.04, 0.09, 0.14, intensity * 0.045 * pulse), 10.0, true)
			draw_line(a, b, Color(0.55, 0.76, 0.96, intensity * 0.22 * pulse), 5.5, true)
			draw_line(a, b, Color(0.90, 0.97, 1.0, intensity * 0.16 * pulse), 1.3, true)

		# Hochflor bricht das projizierte Licht in sehr kurze, unregelmäßige
		# Faserglints. Diese sitzen nur im unteren/nahen Teil der Bodenprojektion.
		for index in 42:
			var u := fposmod(float(index) * 0.381966 + sin(time * 0.09 + index) * 0.008, 1.0)
			var v := 0.34 + fposmod(float(index) * 0.217 + time * 0.0015, 0.66)
			var p := _bilerp(poly, u, v)
			var length := 2.0 + float(index % 5) * 0.75
			var angle := -0.65 + sin(float(index) * 2.41) * 0.55
			var dir := Vector2(cos(angle), sin(angle)) * length
			draw_line(p - dir * 0.5, p + dir * 0.5,
				Color(0.74, 0.86, 0.96, intensity * (0.038 + float(index % 3) * 0.011)), 0.9, true)

	func _bilerp(poly: PackedVector2Array, u: float, v: float) -> Vector2:
		var top := poly[0].lerp(poly[1], u)
		var bottom := poly[3].lerp(poly[2], u)
		return top.lerp(bottom, v)

	func _update_reflection(floor_poly: PackedVector2Array, quads: Dictionary) -> void:
		if reflection == null or floor_poly.size() != 4:
			return
		var source_min := Vector2(INF, INF)
		var source_max := Vector2(-INF, -INF)
		for window_name in ["fenster_links", "fenster_rechts"]:
			if not quads.has(window_name):
				continue
			for corner: Variant in quads[window_name].get("corners", []):
				var point: Vector2 = comp.call("project_master_point",
					Vector2(float(corner[0]), float(corner[1])), "base")
				source_min = source_min.min(point)
				source_max = source_max.max(point)
		if is_inf(source_min.x):
			reflection.visible = false
			return
		reflection.polygon = floor_poly
		reflection.uv = PackedVector2Array([Vector2(0, 0), Vector2(1, 0),
			Vector2(1, 1), Vector2(0, 1)])
		var viewport_size := get_viewport_rect().size
		var source_rect := Vector4(source_min.x / viewport_size.x,
			source_min.y / viewport_size.y, source_max.x / viewport_size.x,
			source_max.y / viewport_size.y)
		var shader_material := reflection.material as ShaderMaterial
		shader_material.set_shader_parameter("source_rect", source_rect)
		shader_material.set_shader_parameter("time", time)
		shader_material.set_shader_parameter("intensity", intensity)
		reflection.visible = true
