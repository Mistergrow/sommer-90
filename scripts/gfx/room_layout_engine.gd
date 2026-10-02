extends RefCounted
## Deterministischer Layoutkern des 2,5D-Zimmers.
##
## Der Compositor baut und besitzt die Nodes; dieser Baustein berechnet ihre
## Bildschirmgeometrie aus Master-Ankern, Tiefenebene, Zoom und Material-Skew.
## Dadurch benutzen Laufzeit, Deko-Editor und Preview exakt denselben Pfad.

const ROOM_DEPTH := preload("res://scripts/gfx/room_depth_map.gd")
const MATERIAL_SHADER := "res://shaders/material_variants.gdshader"


static func layout(owner: Control) -> void:
	owner.call("_update_cable_pins")
	_layout_overlays(owner)
	var transform: Dictionary = owner.call("_master_transform")
	var scale_factor: float = transform["scale"]
	var offset: Vector2 = transform["offset"]
	var master_size: Vector2 = transform["master"]
	var room_config: Dictionary = owner.call("config")
	var anchors: Dictionary = room_config.get("anchors", {})
	for raw_child: Node in owner.get_children():
		if not raw_child is TextureRect:
			continue
		var child := raw_child as TextureRect
		if child.texture == null:
			continue
		var texture_size := child.texture.get_size()
		var anchor_name := str(child.get_meta("anchor", ""))
		if bool(child.get_meta("full_canvas", false)) or anchor_name == "" \
				or not anchors.has(anchor_name):
			_layout_full_canvas(child, offset, master_size, scale_factor)
		else:
			_layout_anchored(owner, child, anchors[anchor_name], texture_size,
				offset, scale_factor, room_config)
		child.set_meta("room_depth_canonical_position", child.position)
	owner.call("_apply_depth_projection")


static func _layout_overlays(owner: Control) -> void:
	var editor: Control = owner.get("_editor")
	if is_instance_valid(editor):
		editor.position = Vector2.ZERO
		editor.size = owner.size
		editor.queue_redraw()
	var weather: Control = owner.get("_weather")
	if is_instance_valid(weather):
		weather.position = Vector2.ZERO
		weather.size = owner.size
	var daynight: Control = owner.get("_daynight")
	if is_instance_valid(daynight):
		daynight.position = Vector2.ZERO
		daynight.size = owner.size
		daynight.call("_layout")
	var monitor_glow: Control = owner.get("_monitor_glow")
	if is_instance_valid(monitor_glow):
		monitor_glow.position = Vector2.ZERO
		monitor_glow.size = owner.size
		monitor_glow.call("_layout")
	for property_name: String in ["_dust_rays", "_idle_life"]:
		var overlay: Control = owner.get(property_name)
		if is_instance_valid(overlay):
			overlay.position = Vector2.ZERO
			overlay.size = owner.size
	var sockets: Control = owner.get("_sockets_ov")
	if is_instance_valid(sockets):
		sockets.position = Vector2.ZERO
		sockets.size = owner.size
		sockets.queue_redraw()
	var room_age: Control = owner.get("_room_age")
	if is_instance_valid(room_age):
		room_age.position = Vector2.ZERO
		room_age.size = owner.size
		room_age.call("refresh_year")


static func _layout_full_canvas(child: TextureRect, offset: Vector2,
		master_size: Vector2, scale_factor: float) -> void:
	var padding := 7.0 * scale_factor \
		if bool(child.get_meta("room_depth_base", false)) else 0.0
	child.position = offset - Vector2(padding, padding)
	child.size = master_size * scale_factor + Vector2(padding, padding) * 2.0
	child.set_meta("room_depth_sample",
		offset + master_size * scale_factor * Vector2(0.5, 0.28))
	child.set_meta("room_depth_gain", ROOM_DEPTH.FAR_GAIN)


static func _layout_anchored(owner: Control, child: TextureRect, anchor: Array,
		texture_size: Vector2, offset: Vector2, scale_factor: float,
		room_config: Dictionary) -> void:
	var anchor_delta: Vector2 = child.get_meta("anchor_offset", Vector2.ZERO)
	var anchor_master := Vector2(float(anchor[0]), float(anchor[1])) + anchor_delta
	var anchor_screen := offset + anchor_master * scale_factor
	var target := texture_size * scale_factor
	var width_target := float(child.get_meta("width", 0.0))
	if width_target > 0.0:
		target = texture_size * (width_target * scale_factor / texture_size.x)
	var height_target := float(child.get_meta("height", 0.0))
	if height_target > 0.0:
		target.y = height_target * scale_factor
	if bool(child.get_meta("depth_scale", false)):
		var range_y: Vector2 = owner.call("_depth_range")
		var far_scale := float(room_config.get("perspective", {}).get("far_scale", 0.78))
		var depth := clampf((anchor_master.y - range_y.x) \
			/ maxf(range_y.y - range_y.x, 1.0), 0.0, 1.0)
		target *= lerpf(far_scale, 1.0, depth)
	child.size = target
	match str(child.get_meta("pivot", "center")):
		"bottomcenter":
			child.position = (anchor_screen - Vector2(target.x / 2.0, target.y)).floor()
			child.pivot_offset = Vector2(target.x / 2.0, target.y)
		_:
			child.position = (anchor_screen - target / 2.0).floor()
			child.pivot_offset = target / 2.0
	if bool(child.get_meta("is_shadow", false)):
		var bias: Vector2 = child.get_meta("shadow_bias", Vector2.ZERO)
		child.position += (bias * scale_factor).floor()
	_apply_skew(child, target, scale_factor)
	child.rotation_degrees = float(child.get_meta("rotation", 0.0))
	child.set_meta("room_depth_sample", anchor_screen)
	var depth_group := str(child.get_meta("room_depth_group", ""))
	child.set_meta("room_depth_gain", ROOM_DEPTH.DESK_GAIN if depth_group == "desk" \
		else ROOM_DEPTH.gain_from_depth(ROOM_DEPTH.sample_base(anchor_master)))


static func _apply_skew(child: TextureRect, target: Vector2, scale_factor: float) -> void:
	var skew_pixels := float(child.get_meta("skew", 0.0)) * scale_factor
	if skew_pixels != 0.0:
		var material := child.material as ShaderMaterial
		if material == null:
			material = ShaderMaterial.new()
			material.shader = load(MATERIAL_SHADER)
			material.set_shader_parameter("recolor_strength", 0.0)
			child.material = material
		var widen_pixels := absf(skew_pixels)
		child.position.x -= maxf(-skew_pixels, 0.0)
		child.size = Vector2(target.x + widen_pixels, target.y)
		child.pivot_offset = Vector2(
			maxf(-skew_pixels, 0.0) + target.x / 2.0, target.y)
		material.set_shader_parameter("skew_top", skew_pixels / maxf(target.x, 1.0))
		material.set_shader_parameter("widen",
			(target.x + widen_pixels) / maxf(target.x, 1.0))
	elif child.material is ShaderMaterial \
			and not bool(child.get_meta("room_depth_warp", false)):
		child.material.set_shader_parameter("skew_top", 0.0)
		child.material.set_shader_parameter("widen", 1.0)
