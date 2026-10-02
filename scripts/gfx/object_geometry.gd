class_name ObjectGeometry
extends RefCounted
## Zweiter Kalibrierpass: fest ins RGB-Master eingebackene Objekte und manuell
## markierte Licht-/Schattenfelder. Unabhängig von location_surfaces.json.

const CONFIG_PATH := "res://data/location_objects.json"
const TYPES := [&"object", &"light_source", &"light_field", &"shadow"]
const OVERSCAN_MIN := -0.35
const OVERSCAN_MAX := 1.35
const PolygonGeometry := preload("res://scripts/gfx/polygon_geometry.gd")
const DataLoader := preload("res://scripts/gfx/geometry_data_loader.gd")

static var _data: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_data = {}
	_loaded = false


static func data() -> Dictionary:
	_load()
	return _data


static func objects_for(location_key: String) -> Array:
	_load()
	var locations: Variant = _data.get("locations", {})
	if not locations is Dictionary:
		return []
	var entry: Variant = (locations as Dictionary).get(location_key, {})
	if not entry is Dictionary:
		return []
	var objects: Variant = (entry as Dictionary).get("objects", [])
	return objects if objects is Array else []


static func depth_objects_for(location_key: String) -> Array:
	return objects_for(location_key).filter(func(raw: Variant) -> bool:
		return raw is Dictionary and str((raw as Dictionary).get("type", "")) == "object" \
		and validate_entry(raw as Dictionary).is_empty())


static func effects_for(location_key: String) -> Array:
	return objects_for(location_key).filter(func(raw: Variant) -> bool:
		return raw is Dictionary and str((raw as Dictionary).get("type", "")) in ["light_field", "shadow"] \
		and validate_entry(raw as Dictionary).is_empty())


static func has_depth_objects(location_key: String) -> bool:
	return not depth_objects_for(location_key).is_empty()


static func apply_to_depth_image(location_key: String, fallback: Image) -> Image:
	var objects := depth_objects_for(location_key)
	if objects.is_empty():
		return fallback
	var result := Image.create(fallback.get_width(), fallback.get_height(), false,
		fallback.get_format())
	result.blit_rect(fallback, Rect2i(Vector2i.ZERO, fallback.get_size()), Vector2i.ZERO)
	# Polygon, Bounds und Parameter genau einmal pro Objekt vorbereiten. Danach
	# wird nur seine Bounding-Box gerastert. Das bewahrt Überlappungsreihenfolge
	# und Feathering, vermeidet aber Millionen Dictionary-/Polygon-Neubauten.
	var prepared: Array[Dictionary] = []
	for raw: Variant in objects:
		var entry := raw as Dictionary
		var polygon := polygon_for(entry)
		prepared.append({
			"polygon": polygon,
			"bounds": PolygonGeometry.bounds(polygon),
			"far": clampf(float(entry.get("depth_far", 0.48)), 0.0, 1.0),
			"near": clampf(float(entry.get("depth_near", 0.82)), 0.0, 1.0),
			"axis": str(entry.get("depth_axis", "vertical")),
			"feather": maxf(0.0, float(entry.get("edge_feather", 2.2))),
		})
	var width := result.get_width()
	var height := result.get_height()
	var short_edge := float(mini(width, height))
	for item: Dictionary in prepared:
		var polygon: PackedVector2Array = item["polygon"]
		var bounds: Rect2 = item["bounds"]
		var x0 := clampi(floori(bounds.position.x * width), 0, width)
		var x1 := clampi(ceili(bounds.end.x * width), 0, width)
		var y0 := clampi(floori(bounds.position.y * height), 0, height)
		var y1 := clampi(ceili(bounds.end.y * height), 0, height)
		for y in range(y0, y1):
			var uv_y := (float(y) + 0.5) / float(height)
			for x in range(x0, x1):
				var uv := Vector2((float(x) + 0.5) / float(width), uv_y)
				if not Geometry2D.is_point_in_polygon(uv, polygon):
					continue
				var object_depth := _depth_for_prepared_object(item, uv)
				var feather_px := float(item["feather"])
				if feather_px > 0.0:
					var distance_px := _distance_to_edges(uv, polygon) * short_edge
					object_depth = lerpf(result.get_pixel(x, y).r, object_depth,
						smoothstep(0.0, feather_px, distance_px))
				result.set_pixel(x, y, Color(clampf(object_depth, 0.0, 1.0), 0.0, 0.0, 1.0))
	return result


static func _depth_for_prepared_object(item: Dictionary, uv: Vector2) -> float:
	var bounds: Rect2 = item["bounds"]
	var t := 0.5
	match str(item["axis"]):
		"horizontal": t = inverse_lerp(bounds.position.x, bounds.end.x, uv.x)
		"flat": t = 0.5
		_: t = inverse_lerp(bounds.position.y, bounds.end.y, uv.y)
	return lerpf(float(item["far"]), float(item["near"]), clampf(t, 0.0, 1.0))


static func polygon_for(entry: Dictionary) -> PackedVector2Array:
	return PolygonGeometry.from_entry(entry)


static func depth_for_entry(entry: Dictionary, uv: Vector2,
		polygon := PackedVector2Array()) -> float:
	if polygon.is_empty():
		polygon = polygon_for(entry)
	var bounds := PolygonGeometry.bounds(polygon)
	var far_depth := clampf(float(entry.get("depth_far", 0.48)), 0.0, 1.0)
	var near_depth := clampf(float(entry.get("depth_near", 0.82)), 0.0, 1.0)
	var axis := str(entry.get("depth_axis", "vertical"))
	var t := 0.5
	if axis == "horizontal":
		t = inverse_lerp(bounds.position.x, bounds.end.x, uv.x)
	elif axis == "flat":
		t = 0.5
	else:
		t = inverse_lerp(bounds.position.y, bounds.end.y, uv.y)
	return lerpf(far_depth, near_depth, clampf(t, 0.0, 1.0))


static func validate_entry(entry: Dictionary) -> String:
	var kind := StringName(str(entry.get("type", "")))
	if kind not in TYPES:
		return "unbekannter Typ '%s'" % kind
	var polygon := polygon_for(entry)
	if polygon.size() < 3:
		return "weniger als drei Punkte"
	for point: Vector2 in polygon:
		if point.x < OVERSCAN_MIN or point.x > OVERSCAN_MAX \
				or point.y < OVERSCAN_MIN or point.y > OVERSCAN_MAX:
			return "Punkt außerhalb des erlaubten Overscans"
	if absf(PolygonGeometry.signed_area(polygon)) < 0.00005:
		return "Fläche ist zu klein"
	if Geometry2D.triangulate_polygon(polygon).is_empty():
		return "Polygon überschneidet sich selbst"
	if kind == &"object":
		var far_depth := float(entry.get("depth_far", 0.0))
		var near_depth := float(entry.get("depth_near", 1.0))
		if far_depth < 0.0 or near_depth > 1.0 or far_depth > near_depth:
			return "ungültiger Tiefenbereich"
	else:
		var strength := float(entry.get("strength", 0.1))
		if strength < 0.0 or strength > 1.0:
			return "Stärke außerhalb 0..1"
	return ""


static func color_for(entry: Dictionary, fallback: Color) -> Color:
	var raw: Variant = entry.get("color", [])
	if raw is Array and (raw as Array).size() >= 3:
		return Color(float(raw[0]), float(raw[1]), float(raw[2]), 1.0)
	return fallback


static func entry_by_id(location_key: String, entry_id: String) -> Dictionary:
	for raw: Variant in objects_for(location_key):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == entry_id:
			return raw as Dictionary
	return {}


static func weather_factor(entry: Dictionary) -> float:
	var mode := str(entry.get("weather", "all"))
	if mode == "all":
		return 1.0
	var loop := Engine.get_main_loop()
	var weather: Node = loop.root.get_node_or_null("WeatherManager") if loop is SceneTree else null
	var state := str(weather.call("state")) if weather != null else "clear"
	if mode == state:
		return 1.0
	# Sonnenprojektionen verschwinden bei Regen; diffuse Felder können über
	# explizites weather=all unabhängig bleiben.
	return 0.0


static func _distance_to_edges(point: Vector2, polygon: PackedVector2Array) -> float:
	var distance := INF
	for i in polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, polygon[i],
			polygon[(i + 1) % polygon.size()])
		distance = minf(distance, point.distance_to(closest))
	return distance


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_data = DataLoader.load_dictionary(CONFIG_PATH, {"version": 1, "locations": {}})
