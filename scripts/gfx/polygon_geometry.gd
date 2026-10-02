extends RefCounted
## Gemeinsame normalisierte Polygon-Grundoperationen fuer Surface/Object-Maps.


static func from_entry(entry: Dictionary) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for raw: Variant in entry.get("points", []):
		if raw is Array and (raw as Array).size() >= 2:
			polygon.append(Vector2(float(raw[0]), float(raw[1])))
	return polygon


static func bounds(polygon: PackedVector2Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for point: Vector2 in polygon:
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, (hi - lo).max(Vector2(0.0001, 0.0001)))


static func signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
