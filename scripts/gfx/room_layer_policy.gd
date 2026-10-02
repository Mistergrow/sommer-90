class_name RoomLayerPolicy
extends RefCounted
## Zustands- und Modellregeln des RoomCompositors. Rendering und Layout bleiben
## im Compositor; hier lebt nur die Entscheidung, welcher Layer sichtbar ist
## und welche kuratierte Geraetevariante er verwendet. Physische Sammlungsprops
## koennen dabei ebenso an echten Inventarbesitz gebunden werden.

const PREVIEW_MODELS := preload("res://scripts/gfx/room_preview_models.gd")


static func active(owner: Control, layer: Dictionary) -> bool:
	if bool(layer.get("disabled", false)):
		return false
	var preview_all := bool(owner.get("preview_all_devices"))
	if not Engine.is_editor_hint() and not preview_all:
		var required_flag := str(layer.get("requires_flag", ""))
		if not required_flag.is_empty() and not bool(GameManager.flags.get(required_flag, false)):
			return false
		var excluded_flag := str(layer.get("unless_flag", ""))
		if not excluded_flag.is_empty() and bool(GameManager.flags.get(excluded_flag, false)):
			return false
		for flag_value: Variant in layer.get("unless_any_flags", []):
			if bool(GameManager.flags.get(str(flag_value), false)):
				return false
	if layer.has("requires_model"):
		var required: Dictionary = layer["requires_model"]
		for selector: String in required:
			if selected_model(owner, selector, "") != str(required[selector]):
				return false
	if preview_all:
		if bool(layer.get("device", false)) or layer.has("requires_asset"):
			return true
		return not layer.has("requires_hardware") \
			and not layer.has("requires_any_hardware") \
			and not layer.has("requires_object")
	if Engine.is_editor_hint():
		return not layer.has("requires_hardware") \
			and not layer.has("requires_any_hardware") \
			and not layer.has("requires_object")
	if layer.has("requires_inventory"):
		var item_id := str(layer.get("requires_inventory", ""))
		var minimum := maxi(1, int(layer.get("requires_inventory_count", 1)))
		if item_id.is_empty() or InventoryManager.count(item_id) < minimum:
			return false
	if layer.has("requires_any_hardware"):
		for hardware_id: String in layer["requires_any_hardware"]:
			if PlayerStats.has_hardware(hardware_id):
				return true
		return false
	if layer.has("requires_hardware"):
		return PlayerStats.has_hardware(layer["requires_hardware"])
	if layer.has("requires_object"):
		return RoomManager.has_object(layer["requires_object"])
	return bool(layer.get("always", true))


## stats_changed feuert bei jeder Geld-/Energie-/Hungeraenderung, room_changed
## bei jedem Muellkruemel. Der volle Raum-Neuaufbau (~7 ms) lohnt nur, wenn sich
## Sichtbares aendert: Basisbild, aktive Layer samt Modellgrafik, Kabel, Hardware,
## Raumobjekte oder Flags. Direkte rebuild()-Aufrufe bleiben davon unberuehrt.
static func changed_since_build(owner: Control) -> bool:
	var plan: Array = [owner.call("find_base", owner.call("_current_year")),
		owner.get("suppress_overlays"), owner.get("preview_all_devices"),
		PlayerStats.hardware, PlayerStats.peripherals, RoomManager.to_dict(), GameManager.flags]
	var config: Dictionary = owner.call("config")
	for layer: Dictionary in config.get("layers", []):
		if active(owner, layer):
			var visual := resolve_visual(owner, layer)
			plan.append([layer.get("id", ""), visual.get("assets", visual.get("asset", ""))])
	for cable_cfg: Dictionary in config.get("cables", []):
		if active(owner, cable_cfg):
			plan.append(cable_cfg.get("id", ""))
	var signature := str(plan)
	if signature == str(owner.get_meta("_built_signature", "")):
		return false
	owner.set_meta("_built_signature", signature)
	return true


static func resolve_visual(owner: Control, source: Dictionary) -> Dictionary:
	var selector := str(source.get("model_selector", ""))
	var selected := str(source.get("default_model", ""))
	if bool(owner.get("preview_all_devices")) or not Engine.is_editor_hint():
		selected = selected_model(owner, selector, selected)
	return PREVIEW_MODELS.resolve(source, selected)


static func selected_model(owner: Control, selector: String, fallback: String) -> String:
	if bool(owner.get("preview_all_devices")):
		return PREVIEW_MODELS.active(owner.call("config"),
			owner.get("_preview_device_models"), selector, fallback)
	if not Engine.is_editor_hint() and RoomManager.has_method("active_device_model"):
		var selected := str(RoomManager.call("active_device_model", selector))
		if not selected.is_empty():
			return selected
	if not Engine.is_editor_hint() and PlayerStats.has_method("desk_model"):
		return str(PlayerStats.call("desk_model", selector))
	return fallback


static func available_models(owner: Control, selector: String) -> Array:
	return PREVIEW_MODELS.available(owner.call("config"), selector)


static func active_preview_model(owner: Control, selector: String) -> String:
	if not bool(owner.get("preview_all_devices")):
		return ""
	return PREVIEW_MODELS.active(owner.call("config"),
		owner.get("_preview_device_models"), selector)


static func validate_preview_models(owner: Control) -> void:
	var defaults: Variant = owner.get("preview_device_defaults")
	PREVIEW_MODELS.validate(owner.call("config"), owner.get("_preview_device_models"),
		defaults if defaults is Dictionary else {})


static func select_preview_model(owner: Control, selector: String, model_id: String,
		layer_id: String) -> Control:
	if not bool(owner.get("preview_all_devices")):
		return null
	if not PREVIEW_MODELS.select(owner.call("config"),
			owner.get("_preview_device_models"), selector, model_id):
		return null
	return _rebuild_and_select(owner, layer_id)


static func cycle_preview_model(owner: Control, selector: String, direction: int,
		layer_id: String) -> Control:
	if not bool(owner.get("preview_all_devices")):
		return null
	if not PREVIEW_MODELS.cycle(owner.call("config"),
			owner.get("_preview_device_models"), selector, direction):
		return null
	return _rebuild_and_select(owner, layer_id)


static func _rebuild_and_select(owner: Control, layer_id: String) -> Control:
	owner.call("rebuild")
	var selected: Control = null
	for child: Node in owner.get_children():
		if child is TextureRect and str(child.get_meta("layer_id", "")) == layer_id \
				and not bool(child.get_meta("is_shadow", false)):
			selected = child
			break
	var editor: Variant = owner.get("_editor")
	if editor != null and is_instance_valid(editor) and selected != null:
		editor.call("select_layer", selected)
	return selected
