extends RefCounted
## Reine Treffer- und Klemmgeometrie fuer den Raumeditor.


static func child_at(children: Array, anchors: Dictionary, point: Vector2) -> Control:
	var best: Control = null
	for child in children:
		if not child is TextureRect or child.get_meta("is_shadow", false):
			continue
		var anchor_name: String = child.get_meta("anchor", "")
		if anchor_name == "" or not anchors.has(anchor_name):
			continue
		if Rect2(child.position, child.size).has_point(point):
			if best == null or child.z_index >= best.z_index:
				best = child
	return best


static func clamp_to_zone(anchor: Array, zone_name: String, quads: Dictionary, zones: Dictionary) -> void:
	# Stellflaechen koennen perspektivische Vierecke oder klassische Rechtecke sein.
	if quads.has(zone_name):
		var quad: Array = quads[zone_name].get("corners", [])
		if quad.size() == 4:
			clamp_to_quad(anchor, quad)
			return
	if zone_name == "" or not zones.has(zone_name):
		return
	var rect: Array = zones[zone_name].get("rect", [])
	if rect.size() != 4:
		return
	anchor[0] = clampf(float(anchor[0]), float(rect[0]), float(rect[0]) + float(rect[2]))
	anchor[1] = clampf(float(anchor[1]), float(rect[1]), float(rect[1]) + float(rect[3]))


static func clamp_to_quad(anchor: Array, quad: Array) -> void:
	var far_y := (float(quad[0][1]) + float(quad[1][1])) / 2.0
	var near_y := (float(quad[2][1]) + float(quad[3][1])) / 2.0
	anchor[1] = clampf(float(anchor[1]), far_y, near_y)
	var depth := clampf((float(anchor[1]) - far_y) / maxf(near_y - far_y, 1.0), 0.0, 1.0)
	var x_left := lerpf(float(quad[0][0]), float(quad[3][0]), depth)
	var x_right := lerpf(float(quad[1][0]), float(quad[2][0]), depth)
	anchor[0] = clampf(float(anchor[0]), x_left, x_right)
