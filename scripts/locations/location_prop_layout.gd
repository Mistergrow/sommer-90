extends RefCounted
## Gemeinsame Projektion der Hotspots, Story-Requisiten und Kontaktschatten.

static func story_props(owner: Control) -> void:
	var _depth_props: Array = owner.get("_depth_props")
	var _stage_25d: Control = owner.get("_stage_25d")
	# Props koennen waehrend einer Ortsaktion verschwinden (z. B. nachdem
	# Gruber ein Laufwerk oder Sven den CRT repariert hat). queue_free() macht
	# den im Dictionary verbliebenen Verweis im naechsten Frame zu einer
	# "freed instance". Ein direkter `as TextureRect`-Cast wirft dann bereits
	# vor der anschliessenden Gueltigkeitspruefung einen Laufzeitfehler.
	# Rueckwaerts iterieren erlaubt, solche verwaisten Eintraege samt
	# Kontaktschatten atomar aus der 2,5D-Liste zu entfernen.
	for index in range(_depth_props.size() - 1, -1, -1):
		var raw_entry: Variant = _depth_props[index]
		if not raw_entry is Dictionary:
			_depth_props.remove_at(index)
			continue
		var entry: Dictionary = raw_entry
		var raw_prop: Variant = entry.get("node")
		if not is_instance_valid(raw_prop):
			var orphan_shadow: Variant = entry.get("shadow")
			if is_instance_valid(orphan_shadow):
				(orphan_shadow as Node).queue_free()
			_depth_props.remove_at(index)
			continue
		if not raw_prop is TextureRect:
			_depth_props.remove_at(index)
			continue
		var prop: TextureRect = raw_prop
		var rect: Rect2 = owner.call("vrect", entry["rect"])
		var center := rect.get_center()
		if _stage_25d != null and is_instance_valid(_stage_25d):
			center += _stage_25d.call("offset_for_point", center)
		prop.size = rect.size
		prop.position = center - rect.size * .5
		var raw_shadow: Variant = entry.get("shadow")
		if is_instance_valid(raw_shadow) and raw_shadow is TextureRect:
			var shadow: TextureRect = raw_shadow
			var shadow_size := Vector2(rect.size.x * .68, maxf(5.0, rect.size.y * .075))
			shadow.size = shadow_size
			shadow.position = Vector2(center.x - shadow_size.x * .5,
				center.y + rect.size.y * .5 - shadow_size.y * .64)
		elif entry.has("shadow"):
			# Auch einen separat entfernten Schatten nicht bei jedem
			# Parallaxen-Frame erneut als freigegebene Instanz anfassen.
			entry["shadow"] = null
	owner.call("_prune_editable_actor_defs")


static func hotspots(owner: Control) -> void:
	var _hotspot_defs: Array = owner.get("_hotspot_defs")
	var _stage_25d: Control = owner.get("_stage_25d")
	var s: float = owner.call("view_scale")
	var off: Vector2 = owner.call("view_offset")
	for def in _hotspot_defs:
		var button: Button = def["button"]
		if def.has("corners"):
			# Bounding-Box positioniert den Button; das normierte Polygon
			# übernimmt Treffertest und Hover-Umriss.
			var screen_pts: Array[Vector2] = []
			var top_left := Vector2(INF, INF)
			var bottom_right := Vector2(-INF, -INF)
			for c in def["corners"]:
				var p: Vector2 = off + Vector2(c[0], c[1]) * s
				if _stage_25d != null and is_instance_valid(_stage_25d):
					p += _stage_25d.call("offset_for_point", p)
				screen_pts.append(p)
				top_left = top_left.min(p)
				bottom_right = bottom_right.max(p)
			var box := (bottom_right - top_left).max(Vector2.ONE)
			button.position = top_left
			button.size = box
			var poly := PackedVector2Array()
			for p in screen_pts:
				poly.append((p - top_left) / box)
			button.polygon_norm = poly
		else:
			var rect: Rect2 = owner.call("vrect", def["rect"])
			button.position = rect.position
			button.size = rect.size
		if not def.has("corners") and _stage_25d != null and is_instance_valid(_stage_25d):
			button.position += _stage_25d.call("offset_for_point", button.position + button.size * 0.5)
	owner.call("_layout_depth_actors")

