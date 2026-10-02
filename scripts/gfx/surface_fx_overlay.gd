class_name SurfaceFxOverlay
extends Control
## Zeichnet die im Objektpass markierten Lichtfelder/Schatten weich auf ihre
## Empfänger. Der Host liefert die vorhandene 2,5D-Projektion.

const ObjectGeometryScript := preload("res://scripts/gfx/object_geometry.gd")

var host: Control = null
var stage: Control = null
var location_key := ""
var _time := 0.0


func configure(p_host: Control, p_stage: Control, key: String) -> void:
	host = p_host
	stage = p_stage
	location_key = key
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if host == null:
		return
	_time += minf(maxf(delta, 0.0), 1.0 / 20.0)
	position = Vector2.ZERO
	size = host.size
	queue_redraw()


func _draw() -> void:
	if host == null or Engine.is_editor_hint():
		return
	# Erst das sehr dezente Quellleuchten, dann Projektionen, zuletzt enge
	# Kontaktschatten. Die Reihenfolge verhindert, dass Sonnenlicht Möbel vom
	# Boden löst oder ein Schatten die Fensterquelle abdunkelt.
	for raw: Variant in ObjectGeometryScript.objects_for(location_key):
		if raw is Dictionary and str((raw as Dictionary).get("type", "")) == "light_source":
			_draw_source_glow(raw as Dictionary)
	for raw: Variant in ObjectGeometryScript.effects_for(location_key):
		var entry := raw as Dictionary
		var weather: float = ObjectGeometryScript.weather_factor(entry)
		if weather <= 0.001:
			continue
		var polygon := PackedVector2Array()
		for uv: Vector2 in ObjectGeometryScript.polygon_for(entry):
			polygon.append(_project_uv(uv))
		if polygon.size() < 3:
			continue
		var source: Dictionary = ObjectGeometryScript.entry_by_id(location_key,
			str(entry.get("source_id", "")))
		var source_strength := float(source.get("strength", 1.0)) if not source.is_empty() else 1.0
		var strength: float = float(entry.get("strength", 0.10)) * weather \
			* _time_factor(entry) * source_strength
		var softness := clampf(float(entry.get("softness", 0.72)), 0.0, 1.0)
		var kind := str(entry.get("type", "shadow"))
		var fallback := Color(1.0, 0.78, 0.42) if kind == "light_field" else Color(0.12, 0.11, 0.10)
		var color: Color = ObjectGeometryScript.color_for(entry, fallback)
		_draw_soft_polygon(polygon, color, strength, softness, kind == "light_field")
		match str(entry.get("pattern", "")):
			"window_projection": _draw_window_projection(polygon, strength)
			"curtain_penumbra": _draw_curtain_penumbra(polygon, strength)
	for raw: Variant in ObjectGeometryScript.depth_objects_for(location_key):
		var entry := raw as Dictionary
		if bool(entry.get("contact_shadow", false)):
			_draw_contact_shadow(entry)


func _project_uv(uv: Vector2) -> Vector2:
	if location_key == "ROOM_MASTER" and stage != null and stage.has_method("project_master_point"):
		return stage.call("project_master_point", uv * Vector2(1920.0, 1080.0), "base")
	var point := uv * host.size
	if stage != null and stage.has_method("offset_for_point"):
		point += stage.call("offset_for_point", point)
	return point


func _draw_soft_polygon(polygon: PackedVector2Array, color: Color, strength: float,
		softness: float, is_light: bool) -> void:
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point
	center /= float(polygon.size())
	var rings := 8
	for ring in rings:
		var ratio := float(ring) / float(rings - 1)
		var factor := lerpf(1.0, lerpf(0.82, 0.55, softness), ratio)
		var inset := PackedVector2Array()
		for point: Vector2 in polygon:
			inset.append(center + (point - center) * factor)
		var alpha := strength * (0.035 + ratio * (0.022 if is_light else 0.018))
		draw_colored_polygon(inset, Color(color, alpha))


func _draw_source_glow(entry: Dictionary) -> void:
	var weather: float = ObjectGeometryScript.weather_factor(entry)
	if weather <= 0.001:
		return
	var polygon := PackedVector2Array()
	for uv: Vector2 in ObjectGeometryScript.polygon_for(entry):
		polygon.append(_project_uv(uv))
	if polygon.size() < 3:
		return
	polygon.append(polygon[0])
	var color: Color = ObjectGeometryScript.color_for(entry, Color(0.90, 0.95, 1.0))
	var alpha: float = float(entry.get("strength", 0.5)) * weather * _time_factor(entry)
	for ring in 4:
		draw_polyline(polygon, Color(color, alpha * (0.010 - float(ring) * 0.0017)),
			2.0 + float(ring) * 3.4, true)


## Der Fensterrahmen wird nicht als heller Teppichaufkleber gezeichnet: breite
## Penumbra plus zwei sehr schwache, im Trapez bleibende Sprossenschatten lassen
## die Projektion aus der realen Fenstergeometrie entstehen.
func _draw_window_projection(polygon: PackedVector2Array, strength: float) -> void:
	if polygon.size() != 4 or strength <= 0.001:
		return
	var drift := sin(_time * 0.035) * 0.012
	for definition: Array in [[0.49 + drift, 8.0, 0.20], [0.16 + drift, 3.2, 0.08],
			[0.82 + drift, 3.2, 0.08]]:
		var u := clampf(float(definition[0]), 0.03, 0.97)
		var a := _bilerp(polygon, u, 0.02)
		var b := _bilerp(polygon, u, 0.98)
		draw_line(a, b, Color(0.11, 0.09, 0.07, strength * float(definition[2])),
			float(definition[1]), true)
	# Teppichfasern brechen das Licht in vereinzelte warme Mikrokanten.
	for i in 22:
		var u := fposmod(float(i) * 0.381966, 1.0)
		var v := 0.28 + fposmod(float(i) * 0.217, 0.69)
		var p := _bilerp(polygon, u, v)
		var direction := Vector2(3.0 + float(i % 4), -1.2 - float(i % 3) * 0.4)
		draw_line(p - direction * 0.5, p + direction * 0.5,
			Color(1.0, 0.88, 0.61, strength * 0.11), 0.8, true)


func _draw_curtain_penumbra(polygon: PackedVector2Array, strength: float) -> void:
	if polygon.size() != 4 or strength <= 0.001:
		return
	# Unregelmäßige Stofffalten statt eines geometrisch perfekten dunklen Balkens.
	for i in 9:
		var u := (float(i) + 0.5) / 9.0
		var wave := sin(float(i) * 2.13 + _time * 0.07) * 0.018
		var a := _bilerp(polygon, clampf(u + wave, 0.0, 1.0), 0.08)
		var b := _bilerp(polygon, clampf(u - wave, 0.0, 1.0), 0.92)
		draw_line(a, b, Color(0.08, 0.07, 0.065, strength * (0.035 + float(i % 3) * 0.012)),
			4.0 + float(i % 2) * 3.0, true)


func _draw_contact_shadow(entry: Dictionary) -> void:
	var polygon_uv: PackedVector2Array = ObjectGeometryScript.polygon_for(entry)
	var edge: Array = entry.get("contact_edge", [])
	if edge.size() != 2 or polygon_uv.size() < 3:
		return
	var a_index := clampi(int(edge[0]), 0, polygon_uv.size() - 1)
	var b_index := clampi(int(edge[1]), 0, polygon_uv.size() - 1)
	var a := _project_uv(polygon_uv[a_index])
	var b := _project_uv(polygon_uv[b_index])
	var strength := clampf(float(entry.get("contact_strength", 0.14)), 0.0, 0.5)
	# Engster Kern direkt am Fuß, nach vorn weich auslaufend. Mehrere Linien
	# funktionieren auf Holz und Hochflor stabiler als ein großer Blur-Viewport.
	for ring in 7:
		var ratio := float(ring) / 6.0
		var offset := Vector2(0.0, 1.0 + ratio * 8.0)
		var alpha := strength * lerpf(0.36, 0.025, ratio)
		draw_line(a + offset, b + offset, Color(0.025, 0.020, 0.017, alpha),
			lerpf(5.5, 1.0, ratio), true)


func _time_factor(entry: Dictionary) -> float:
	if str(entry.get("time_curve", "")) != "daylight" \
			and str(entry.get("source_id", "")) != "window_light" \
			and str(entry.get("id", "")) != "window_light":
		return 1.0
	var loop := Engine.get_main_loop()
	var manager: Node = loop.root.get_node_or_null("TimeManager") if loop is SceneTree else null
	var slot := int(manager.get("slot")) if manager != null else 1
	return float({0: 0.58, 1: 1.0, 2: 0.82, 3: 0.34, 4: 0.0}.get(slot, 0.75))


func _bilerp(polygon: PackedVector2Array, u: float, v: float) -> Vector2:
	var top := polygon[0].lerp(polygon[1], u)
	var bottom := polygon[3].lerp(polygon[2], u)
	return top.lerp(bottom, v)
