@tool
class_name RoomProjection
extends RefCounted
## Gemeinsame Master-/Tiefenprojektion des Raum-Compositors. RGBA-Layer,
## Hotspots und Kabel delegieren über dieselben dünnen Compositor-Methoden
## hierher und können dadurch nicht mehr schleichend unterschiedliche
## Transformationsformeln entwickeln.

const DepthMap := preload("res://scripts/gfx/room_depth_map.gd")


static func master_transform(owner: Control) -> Dictionary:
	var master: Array = owner.call("config").get("master_size", [1920, 1080])
	var master_size := Vector2(master[0], master[1])
	var scale_factor := maxf(owner.size.x / master_size.x,
		owner.size.y / master_size.y)
	var editing := bool(owner.get("edit_mode"))
	if editing:
		scale_factor *= float(owner.get("editor_zoom"))
	var free_space := owner.size - master_size * scale_factor
	var cover_anchor := Vector2(0.5, 0.5)
	if not editing:
		var anchor_data: Array = owner.call("config").get(
			"gameplay_cover_anchor", [0.5, 0.5])
		if anchor_data.size() >= 2:
			cover_anchor = Vector2(
				clampf(float(anchor_data[0]), 0.0, 1.0),
				clampf(float(anchor_data[1]), 0.0, 1.0))
	var offset := free_space * cover_anchor
	if editing:
		offset += Vector2(owner.get("editor_pan"))
	return {"scale": scale_factor, "offset": offset, "master": master_size}


static func depth_offset(owner: Control, screen_point: Vector2,
		gain_override := -1.0) -> Vector2:
	if not bool(owner.call("_depth_enabled")) \
			or owner.size.x <= 1.0 or owner.size.y <= 1.0:
		return Vector2.ZERO
	var gain := gain_override if gain_override >= 0.0 \
		else surface_gain(owner, screen_point)
	var offset := Vector2(owner.get("_depth_look")) \
		* DepthMap.STRENGTH * owner.size * gain
	offset.y *= DepthMap.VERTICAL_GAIN
	return offset


static func surface_gain(owner: Control, screen_point: Vector2) -> float:
	var transform := master_transform(owner)
	var master := (screen_point - Vector2(transform["offset"])) \
		/ maxf(float(transform["scale"]), 0.001)
	return DepthMap.gain_at_master(master, owner.call("_depth_range"))


static func project_master_point(owner: Control, master_point: Vector2,
		depth_group := "") -> Vector2:
	var transform := master_transform(owner)
	var canonical: Vector2 = transform["offset"] \
		+ master_point * float(transform["scale"])
	return canonical + depth_offset(owner, canonical,
		_gain_for_master(owner, master_point, depth_group))


static func depth_offset_for_master(owner: Control, master_point: Vector2,
		depth_group := "") -> Vector2:
	var transform := master_transform(owner)
	var canonical: Vector2 = transform["offset"] \
		+ master_point * float(transform["scale"])
	return depth_offset(owner, canonical,
		_gain_for_master(owner, master_point, depth_group))


static func _gain_for_master(owner: Control, master_point: Vector2,
		depth_group: String) -> float:
	if depth_group == "desk":
		return DepthMap.DESK_GAIN
	return DepthMap.gain_at_master(master_point, owner.call("_depth_range"),
		depth_group == "base")


## Nur die gecachten kanonischen Positionen verschieben; keine Anker-, Größen-
## oder Materialberechnung pro Frame. Overlays werden aus denselben finalen
## Positionen bzw. project_master_point() neu gezeichnet.
static func apply_depth(owner: Control) -> void:
	for child in owner.get_children():
		if not child is TextureRect or not child.has_meta("room_depth_canonical_position"):
			continue
		var canonical: Vector2 = child.get_meta("room_depth_canonical_position")
		if bool(child.get_meta("room_depth_warp", false)):
			DepthMap.set_material_look(child.material,
				Vector2(owner.get("_depth_look")) if owner.call("_depth_enabled") else Vector2.ZERO)
		if not bool(child.get_meta("room_depth_world", false)):
			child.position = canonical
			continue
		var sample: Vector2 = child.get_meta("room_depth_sample", canonical + child.size * 0.5)
		var gain := float(child.get_meta("room_depth_gain", -1.0))
		child.position = canonical + depth_offset(owner, sample, gain)
	for overlay: Control in [owner.get("_sockets_ov"), owner.get("_surface_fx"), owner.get("_room_age"), owner.get("_weather"),
			owner.get("_dust_rays"), owner.get("_idle_life")]:
		if overlay != null and is_instance_valid(overlay):
			overlay.queue_redraw()
	if owner.get("_daynight") != null and is_instance_valid(owner.get("_daynight")):
		owner.get("_daynight").call("_layout")
	if owner.get("_monitor_glow") != null and is_instance_valid(owner.get("_monitor_glow")):
		owner.get("_monitor_glow").call("_layout")
	var room := owner.get_parent_control()
	if room != null and room.has_method("_layout_hotspots"):
		room.call("_layout_hotspots")


static func depth_range(owner: Control) -> Vector2:
	var quad: Array = owner.call("_quads").get("tisch", {}).get("corners", owner.call("config").get("desk_quad", []))
	if quad.size() == 4:
		return Vector2((float(quad[0][1]) + float(quad[1][1])) / 2.0,
			(float(quad[2][1]) + float(quad[3][1])) / 2.0)
	var persp: Dictionary = owner.call("config").get("perspective", {})
	return Vector2(float(persp.get("far_y", 590.0)), float(persp.get("near_y", 775.0)))
