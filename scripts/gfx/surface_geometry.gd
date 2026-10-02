class_name SurfaceGeometry
extends RefCounted
## Gemeinsame Geometriewahrheit für den SurfaceEditor und die 2,5D-Laufzeit.
## Flächen liegen normalisiert im sichtbaren Masterbild. Dadurch funktionieren
## dieselben Daten bei jeder Auflösung und bei Jahres-/Assetvarianten.

const CONFIG_PATH := "res://data/location_surfaces.json"
const DEFAULT_MAP_SIZE := Vector2i(320, 180)
const TYPES := [&"floor", &"wall", &"ceiling", &"window"]
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


static func surfaces_for(location_key: String) -> Array:
	_load()
	var locations: Variant = _data.get("locations", {})
	if not locations is Dictionary:
		return []
	var entry: Variant = (locations as Dictionary).get(location_key, {})
	if not entry is Dictionary:
		return []
	var surfaces: Variant = (entry as Dictionary).get("surfaces", [])
	return surfaces if surfaces is Array else []


static func has_surfaces(location_key: String) -> bool:
	for raw: Variant in surfaces_for(location_key):
		if raw is Dictionary and _valid_surface(raw as Dictionary):
			return true
	return false


## Erzeugt den alten vertikalen Tiefenverlauf und überschreibt ausschließlich
## markierte Polygone. Noch nicht bearbeitete Bildteile behalten ihr Verhalten.
static func location_depth_image(location_key: String, profile: Dictionary,
		map_size := DEFAULT_MAP_SIZE) -> Image:
	var image := Image.create(map_size.x, map_size.y, false, Image.FORMAT_RF)
	var horizon := float(profile.get("horizon", 0.44))
	for y in map_size.y:
		var v := (float(y) + 0.5) / float(map_size.y)
		var depth := smoothstep(horizon, 1.0, v)
		for x in map_size.x:
			image.set_pixel(x, y, Color(depth, 0.0, 0.0, 1.0))
	return apply_to_depth_image(location_key, image)


## Markierte Flächen in eine vorhandene semantische Depthmap einblenden.
## Spätere Polygone gewinnen bei Überlappung; das entspricht der Reihenfolge im
## Editor und erlaubt einen Occluder über Boden/Wand zu legen.
static func apply_to_depth_image(location_key: String, fallback: Image) -> Image:
	var result := Image.create(fallback.get_width(), fallback.get_height(), false,
		fallback.get_format())
	result.blit_rect(fallback, Rect2i(Vector2i.ZERO, fallback.get_size()), Vector2i.ZERO)
	var surfaces := surfaces_for(location_key)
	if surfaces.is_empty():
		return result
	# Früher wurden Validierung, Triangulation, Polygonaufbau und Bounds für
	# JEDES Pixel erneut ausgeführt (bei 480×270 und fünf Flächen hunderttausende
	# Male). Einmal vorbereiten und nur das Pixel-Rechteck des Polygons rastert
	# dieselbe Tiefenkarte in einem Bruchteil der Zeit. Die Reihenfolge bleibt
	# erhalten: spätere Editorflächen überschreiben frühere.
	var prepared: Array[Dictionary] = []
	for raw: Variant in surfaces:
		if not raw is Dictionary:
			continue
		var surface := raw as Dictionary
		if not _valid_surface(surface):
			continue
		var polygon := polygon_for(surface)
		var bounds := PolygonGeometry.bounds(polygon)
		var kind := StringName(str(surface.get("type", "wall")))
		var defaults := default_depths(kind)
		var wall_role := str(surface.get("wall_role", "auto"))
		if kind == &"wall" and wall_role == "auto":
			wall_role = "left" if bounds.get_center().x < 0.42 else (
				"right" if bounds.get_center().x > 0.58 else "back")
		prepared.append({
			"polygon": polygon,
			"bounds": bounds,
			"kind": kind,
			"far": clampf(float(surface.get("depth_far", defaults.x)), 0.0, 1.0),
			"near": clampf(float(surface.get("depth_near", defaults.y)), 0.0, 1.0),
			"wall_role": wall_role,
		})
	var width := result.get_width()
	var height := result.get_height()
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
				if Geometry2D.is_point_in_polygon(uv, polygon):
					var depth := _depth_for_prepared_surface(item, uv)
					result.set_pixel(x, y, Color(depth, 0.0, 0.0, 1.0))
	return result


static func _depth_for_prepared_surface(item: Dictionary, uv: Vector2) -> float:
	var bounds: Rect2 = item["bounds"]
	var kind: StringName = item["kind"]
	var t := 0.0
	match kind:
		&"floor":
			t = inverse_lerp(bounds.position.y, bounds.end.y, uv.y)
		&"ceiling":
			t = 1.0 - inverse_lerp(bounds.position.y, bounds.end.y, uv.y)
		&"window":
			t = 0.0
		_:
			match str(item["wall_role"]):
				"left": t = 1.0 - inverse_lerp(bounds.position.x, bounds.end.x, uv.x)
				"right": t = inverse_lerp(bounds.position.x, bounds.end.x, uv.x)
				_: t = inverse_lerp(bounds.position.y, bounds.end.y, uv.y) * 0.28
	return clampf(lerpf(float(item["far"]), float(item["near"]),
		clampf(t, 0.0, 1.0)), 0.0, 1.0)


static func polygon_for(surface: Dictionary) -> PackedVector2Array:
	return PolygonGeometry.from_entry(surface)


static func depth_for_surface(surface: Dictionary, uv: Vector2,
		polygon := PackedVector2Array()) -> float:
	if polygon.is_empty():
		polygon = polygon_for(surface)
	if polygon.size() < 3:
		return 0.0
	var bounds := PolygonGeometry.bounds(polygon)
	var kind := StringName(str(surface.get("type", "wall")))
	var far_depth := clampf(float(surface.get("depth_far", default_depths(kind).x)), 0.0, 1.0)
	var near_depth := clampf(float(surface.get("depth_near", default_depths(kind).y)), 0.0, 1.0)
	var t := 0.0
	match kind:
		&"floor":
			t = inverse_lerp(bounds.position.y, bounds.end.y, uv.y)
		&"ceiling":
			# Die Decke trifft hinten unten auf die Wand; der obere Bildrand liegt
			# näher an der gedachten Kamera.
			t = 1.0 - inverse_lerp(bounds.position.y, bounds.end.y, uv.y)
		&"window":
			# Eine Öffnung ist eine ruhige Fernebene. Die Tiefe der Außenwelt
			# innerhalb des Fensters soll nicht wie Zimmerwand/Boden reagieren.
			t = 0.0
		_:
			# Seitenwände laufen zum jeweiligen äußeren Bildrand auf die Kamera zu.
			# Die explizite Editorrolle gewinnt; "auto" leitet sie aus der
			# Bildposition ab. Eine Rückwand bleibt weitgehend plan.
			var center_x := bounds.get_center().x
			var wall_role := str(surface.get("wall_role", "auto"))
			if wall_role == "auto":
				wall_role = "left" if center_x < 0.42 else ("right" if center_x > 0.58 else "back")
			if wall_role == "left":
				t = 1.0 - inverse_lerp(bounds.position.x, bounds.end.x, uv.x)
			elif wall_role == "right":
				t = inverse_lerp(bounds.position.x, bounds.end.x, uv.x)
			else:
				t = inverse_lerp(bounds.position.y, bounds.end.y, uv.y) * 0.28
	return lerpf(far_depth, near_depth, clampf(t, 0.0, 1.0))


static func default_depths(kind: StringName) -> Vector2:
	match kind:
		&"floor": return Vector2(0.20, 0.98)
		&"ceiling": return Vector2(0.10, 0.48)
		&"window": return Vector2(0.01, 0.05)
		_: return Vector2(0.12, 0.58)


static func validate_surface(surface: Dictionary) -> String:
	var kind := StringName(str(surface.get("type", "")))
	if kind not in TYPES:
		return "unbekannter Flächentyp '%s'" % kind
	if kind == &"wall" and str(surface.get("wall_role", "auto")) \
			not in ["auto", "left", "back", "right"]:
		return "unbekannte Wandrolle"
	var polygon := polygon_for(surface)
	if polygon.size() < 3:
		return "weniger als drei Punkte"
	for point: Vector2 in polygon:
		if point.x < 0.0 or point.x > 1.0 or point.y < 0.0 or point.y > 1.0:
			return "Punkt außerhalb des Bildes"
	if absf(PolygonGeometry.signed_area(polygon)) < 0.00005:
		return "Fläche ist zu klein oder liegt auf einer Linie"
	if Geometry2D.triangulate_polygon(polygon).is_empty():
		return "Polygon überschneidet sich selbst"
	return ""


static func sample_bilinear(image: Image, uv: Vector2) -> float:
	var p := Vector2(clampf(uv.x, 0.0, 1.0) * float(image.get_width() - 1),
		clampf(uv.y, 0.0, 1.0) * float(image.get_height() - 1))
	var p0 := Vector2i(floori(p.x), floori(p.y))
	var p1 := Vector2i(mini(p0.x + 1, image.get_width() - 1),
		mini(p0.y + 1, image.get_height() - 1))
	var fx := p.x - float(p0.x)
	var fy := p.y - float(p0.y)
	var a := lerpf(image.get_pixel(p0.x, p0.y).r, image.get_pixel(p1.x, p0.y).r, fx)
	var b := lerpf(image.get_pixel(p0.x, p1.y).r, image.get_pixel(p1.x, p1.y).r, fx)
	return lerpf(a, b, fy)


static func _valid_surface(surface: Dictionary) -> bool:
	return validate_surface(surface).is_empty()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_data = DataLoader.load_dictionary(CONFIG_PATH, {"version": 1, "locations": {}})
