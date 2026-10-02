extends RefCounted
## Editor-Kamera, Moduswechsel und Weiterleitung zum DekoEditor.


static func zoom_at(owner: Control, view_point: Vector2, factor: float) -> void:
	if not bool(owner.get("edit_mode")):
		return
	var transform: Dictionary = owner.call("_master_transform")
	var master_point: Vector2 = (view_point - Vector2(transform["offset"])) / float(transform["scale"])
	var zoom := clampf(float(owner.get("editor_zoom")) * factor, 1.0, 6.0)
	owner.set("editor_zoom", zoom)
	owner.set("editor_pan", _pan_for_focus(owner, master_point, view_point, zoom))
	owner.call("_layout_all")


static func pan_by(owner: Control, delta: Vector2) -> void:
	if not bool(owner.get("edit_mode")):
		return
	owner.set("editor_pan", Vector2(owner.get("editor_pan")) + delta)
	owner.call("_layout_all")


static func reset_view(owner: Control) -> void:
	owner.set("editor_zoom", 1.0)
	owner.set("editor_pan", Vector2.ZERO)
	owner.call("_layout_all")


static func focus(owner: Control, master_point: Vector2, zoom: float) -> void:
	if not bool(owner.get("edit_mode")):
		return
	zoom = clampf(zoom, 1.0, 6.0)
	owner.set("editor_zoom", zoom)
	owner.set("editor_pan", _pan_for_focus(owner, master_point, owner.size * 0.5, zoom))
	owner.call("_layout_all")


static func set_edit_mode(owner: Control, enabled: bool, persist_changes: bool) -> void:
	owner.set("edit_mode", enabled)
	if enabled:
		owner.set("_depth_look", Vector2.ZERO)
		owner.set("_depth_target", Vector2.ZERO)
	owner.set("show_anchors", enabled)
	owner.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	var editor: Control = owner.get("_editor")
	if is_instance_valid(editor):
		editor.call("sync_mode")
		if not enabled and persist_changes:
			editor.call("save_config")
	owner.call("_layout_all" if enabled else "rebuild")
	owner.queue_redraw()


static func pick(owner: Control, local: Vector2, model_specific: bool) -> bool:
	var editor: Control = owner.get("_editor")
	return is_instance_valid(editor) and bool(editor.call("editor_pick", local, model_specific))


static func drag_to(owner: Control, local: Vector2) -> bool:
	var editor: Control = owner.get("_editor")
	return is_instance_valid(editor) and bool(editor.call("editor_drag_to", local))


static func release(owner: Control) -> void:
	var editor: Control = owner.get("_editor")
	if is_instance_valid(editor):
		editor.call("editor_release")


static func wheel(owner: Control, local: Vector2, direction: float, shift: bool,
		ctrl: bool, alt: bool) -> bool:
	var editor: Control = owner.get("_editor")
	return is_instance_valid(editor) and bool(editor.call("editor_wheel", local, direction, shift, ctrl, alt))


static func cycle_model(owner: Control, direction: int) -> bool:
	var editor: Control = owner.get("_editor")
	return is_instance_valid(editor) and bool(editor.call("_cycle_selected_model", direction))


static func _pan_for_focus(owner: Control, master_point: Vector2, view_point: Vector2,
		zoom: float) -> Vector2:
	var config: Dictionary = owner.call("config")
	var master: Array = config.get("master_size", [1920, 1080])
	var master_size := Vector2(master[0], master[1])
	var base := maxf(owner.size.x / master_size.x, owner.size.y / master_size.y) * zoom
	var centered := (owner.size - master_size * base) / 2.0
	return view_point - centered - master_point * base
