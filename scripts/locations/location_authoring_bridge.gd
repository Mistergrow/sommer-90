extends RefCounted
## Persistenz- und Authoring-Logik fuer LocationBase.
##
## LocationBase behaelt seine oeffentliche API als stabilen Adapter fuer
## Vorschau-Szenen und HotspotEditor. Dieses Modul kapselt die Dateiformate und
## die Synchronisation von sichtbarem Akteur, Tiefendefinition und Klickzone.


static func location_key(owner: Control) -> String:
	var base := str(owner.call("background_base"))
	if base != "":
		return base
	var script: Script = owner.get_script()
	return script.resource_path.get_file().get_basename() if script != null else str(owner.name)


static func rect_hotspots(owner: Control) -> Array:
	var result: Array = []
	var definitions: Array = owner.get("_hotspot_defs")
	for raw_definition: Variant in definitions:
		if not raw_definition is Dictionary:
			continue
		var definition := raw_definition as Dictionary
		if definition.has("rect") and not bool(definition.get("actor_managed", false)):
			result.append(definition)
	return result


static func set_hotspot_rect(owner: Control, definition: Dictionary, rect: Rect2) -> void:
	definition["rect"] = rect
	owner.call("_layout_hotspots")


static func hotspot_label(definition: Dictionary) -> String:
	var button: Button = definition.get("button")
	return button.tooltip_text if button != null else "?"


static func mark_hotspot_actor_managed(definition: Dictionary) -> void:
	definition["actor_managed"] = true


static func editable_actor_rect(owner: Control, actor_id: String, default_rect: Rect2,
		overrides_path: String) -> Rect2:
	var mine: Variant = _read_dictionary(overrides_path).get(location_key(owner), {})
	if not mine is Dictionary:
		return default_rect
	var raw: Variant = (mine as Dictionary).get(actor_id, [])
	if raw is Array and raw.size() == 4:
		var rect := Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			return rect
	return default_rect


static func register_editable_depth_actor(owner: Control, actor_id: String, label: String,
		prop: TextureRect, current_rect: Rect2, default_rect: Rect2,
		hotspot_definition: Dictionary, default_hotspot_rect: Rect2) -> void:
	if prop == null or default_rect.size.x <= 0.0 or default_rect.size.y <= 0.0:
		return
	mark_hotspot_actor_managed(hotspot_definition)
	var relative_hotspot := Rect2(
		(default_hotspot_rect.position - default_rect.position) / default_rect.size,
		default_hotspot_rect.size / default_rect.size
	)
	var definitions: Array = owner.get("_editable_actor_defs")
	definitions.append({
		"id": actor_id,
		"label": label,
		"node": prop,
		"rect": current_rect,
		"default_rect": default_rect,
		"hotspot_def": hotspot_definition,
		"relative_hotspot": relative_hotspot,
	})


static func editable_depth_actors(owner: Control) -> Array:
	_prune_editable_actor_definitions(owner)
	return owner.get("_editable_actor_defs")


static func set_editable_actor_rect(owner: Control, definition: Dictionary, rect: Rect2) -> void:
	definition["rect"] = rect
	var raw_prop: Variant = definition.get("node")
	if not is_instance_valid(raw_prop) or not raw_prop is Control:
		_prune_editable_actor_definitions(owner)
		return
	var prop := raw_prop as Control
	var depth_definitions: Array = owner.get("_depth_props")
	for depth_definition: Dictionary in depth_definitions:
		if depth_definition.get("node") == prop:
			depth_definition["rect"] = rect
			break
	var npc_definitions: Array = owner.get("_npc_actor_defs")
	for npc_definition: Dictionary in npc_definitions:
		if npc_definition.get("node") == prop:
			npc_definition["rect"] = rect
			break
	var hotspot_definition: Dictionary = definition.get("hotspot_def", {})
	var relative: Rect2 = definition.get("relative_hotspot", Rect2(0, 0, 1, 1))
	if not hotspot_definition.is_empty():
		hotspot_definition["rect"] = Rect2(
			rect.position + relative.position * rect.size,
			relative.size * rect.size
		)
	owner.call("_layout_hotspots")


static func reset_editable_actor_rect(owner: Control, definition: Dictionary) -> void:
	set_editable_actor_rect(owner, definition,
		definition.get("default_rect", definition.get("rect", Rect2())))


static func save_editable_actor_layouts(owner: Control, overrides_path: String) -> bool:
	_prune_editable_actor_definitions(owner)
	var definitions: Array = owner.get("_editable_actor_defs")
	if definitions.is_empty():
		return true
	var all := _read_dictionary(overrides_path)
	var key := location_key(owner)
	var raw_mine: Variant = all.get(key, {})
	var mine: Dictionary = raw_mine if raw_mine is Dictionary else {}
	for definition: Dictionary in definitions:
		var actor_id := str(definition.get("id", "actor"))
		var stored := _rounded_rect(definition.get("rect", Rect2()))
		if stored == _rounded_rect(definition.get("default_rect", Rect2())):
			mine.erase(actor_id)
			continue
		mine[actor_id] = stored
	if mine.is_empty():
		all.erase(key)
	else:
		all[key] = mine
	var file := FileAccess.open(overrides_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(all, "  ", false))
	return true


static func apply_hotspot_overrides(owner: Control, overrides_path: String) -> void:
	var mine: Array = _read_dictionary(overrides_path).get(location_key(owner), [])
	if mine.is_empty():
		return
	var index := 0
	for definition: Dictionary in rect_hotspots(owner):
		if index < mine.size():
			var raw_rect: Variant = mine[index]
			if raw_rect is Array and raw_rect.size() == 4:
				definition["rect"] = Rect2(
					float(raw_rect[0]), float(raw_rect[1]),
					float(raw_rect[2]), float(raw_rect[3]))
		index += 1


static func set_hotspots_interactive(owner: Control, active: bool) -> void:
	var definitions: Array = owner.get("_hotspot_defs")
	for raw_definition: Variant in definitions:
		if not raw_definition is Dictionary:
			continue
		var button: Button = (raw_definition as Dictionary).get("button")
		if button != null:
			button.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE


static func prune_editable_actor_definitions(owner: Control) -> void:
	_prune_editable_actor_definitions(owner)


static func read_overrides(path: String) -> Dictionary:
	return _read_dictionary(path)


static func _prune_editable_actor_definitions(owner: Control) -> void:
	var definitions: Array = owner.get("_editable_actor_defs")
	for index in range(definitions.size() - 1, -1, -1):
		var raw_definition: Variant = definitions[index]
		if not raw_definition is Dictionary:
			definitions.remove_at(index)
			continue
		var raw_node: Variant = (raw_definition as Dictionary).get("node")
		if not is_instance_valid(raw_node) or not raw_node is Control:
			definitions.remove_at(index)


static func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _rounded_rect(rect: Rect2) -> Array:
	return [roundi(rect.position.x), roundi(rect.position.y),
		roundi(rect.size.x), roundi(rect.size.y)]
