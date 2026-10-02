extends Resource
## Kanonische, asset-relative Anker des AGA-Staubsaugers. Die Werte werden in
## HouseholdVacuumPreview.tscn direkt am vollstaendigen Sprite justiert. Damit
## muessen Schlauch, Rohr, Kessel und Bodenduese nie wieder aus getrennten,
## hart codierten Bildausschnitten zusammengesetzt werden.

@export_category("Darstellung")
@export var sprite_size_far := Vector2(154, 179)
@export var sprite_size_near := Vector2(218, 253)
@export_range(0.20, 0.80, 0.01) var depth_top := 0.43
@export_range(0.50, 1.00, 0.01) var depth_bottom := 0.92

@export_category("Asset-Anker · normalisiert")
@export var floor_head_anchor := Vector2(0.805, 0.925)
@export var power_socket_anchor := Vector2(0.075, 0.650)
@export var shadow_anchor := Vector2(0.475, 0.925)
@export var hose_canister_anchor := Vector2(0.455, 0.715)
@export var hose_wand_anchor := Vector2(0.735, 0.145)


func depth_for(stage_y: float, stage_height: float) -> float:
	var normalized_y := stage_y / maxf(1.0, stage_height)
	return clampf((normalized_y - depth_top) /
		maxf(0.01, depth_bottom - depth_top), 0.0, 1.0)


func sprite_size_for(stage_y: float, stage_height: float) -> Vector2:
	return sprite_size_far.lerp(sprite_size_near, depth_for(stage_y, stage_height))


func sprite_rect_for(floor_head_at: Vector2, stage_height: float,
		vertical_bob := 0.0) -> Rect2:
	var rendered_size := sprite_size_for(floor_head_at.y, stage_height)
	var top_left := floor_head_at - floor_head_anchor * rendered_size
	top_left.y += vertical_bob
	return Rect2(top_left.round(), rendered_size.round())


func point_in_rect(render_rect: Rect2, normalized_anchor: Vector2) -> Vector2:
	return render_rect.position + normalized_anchor * render_rect.size


func anchors_valid() -> bool:
	for anchor: Vector2 in [floor_head_anchor, power_socket_anchor, shadow_anchor,
			hose_canister_anchor, hose_wand_anchor]:
		if anchor.x < 0.0 or anchor.x > 1.0 or anchor.y < 0.0 or anchor.y > 1.0:
			return false
	return depth_bottom > depth_top and sprite_size_far.x > 0.0 \
		and sprite_size_far.y > 0.0 and sprite_size_near.x > 0.0 \
		and sprite_size_near.y > 0.0
