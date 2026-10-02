class_name RoomDeviceCatalog
extends RefCounted
## Gemeinsame, datengetriebene Wahrheit fuer alle austauschbaren und festen
## Geraete im Spielerzimmer. Die Darstellungsdaten bleiben in
## data/room_anchors.json; diese Klasse normalisiert sie fuer RoomManager,
## Compositor, Deko- und LED-Werkzeuge.

const CONFIG_PATH := "res://data/room_anchors.json"
const LAYER_DIR := "res://assets/backgrounds/layers/"
const MAX_VERSION := 9

static var _devices: Dictionary = {}
static var _slots: Array = []


## layer_id -> {selector, default_model, model_order, models, power_domain, ...}
## Rueckgaben sind Kopien: Editor-/UI-Code kann die gemeinsame Wahrheit nicht
## versehentlich zur Laufzeit veraendern.
static func catalog(force_reload := false) -> Dictionary:
	if force_reload or _devices.is_empty():
		_rebuild()
	return _devices.duplicate(true)


static func slots(force_reload := false) -> Array:
	if force_reload or _devices.is_empty():
		_rebuild()
	return _slots.duplicate()


static func definition_for_slot(selector: String) -> Dictionary:
	if _devices.is_empty():
		_rebuild()
	for device: Dictionary in _devices.values():
		if str(device.get("selector", "")) == selector:
			return device.duplicate(true)
	return {}


static func _rebuild() -> void:
	_devices = {}
	_slots = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary:
		push_error("RoomDeviceCatalog: %s ist kein gueltiges JSON-Dictionary" % CONFIG_PATH)
		return
	for raw: Variant in parsed.get("layers", []):
		if not raw is Dictionary:
			continue
		var layer: Dictionary = raw
		var selector := str(layer.get("model_selector", ""))
		if selector.is_empty() and not bool(layer.get("device", false)):
			continue
		var layer_id := str(layer.get("id", ""))
		if layer_id.is_empty():
			continue
		var definition := {
			"id": layer_id,
			"selector": selector,
			"default_model": str(layer.get("default_model",
				layer.get("device_model_id", layer_id))),
			"model_order": [],
			"models": {},
			"power_domain": str(layer.get("power_domain", "mains")),
			"visible_requires_hardware": str(layer.get("requires_hardware", "")),
			"visible_requires_any_hardware": layer.get("requires_any_hardware", []).duplicate(),
		}
		var requirements: Dictionary = layer.get("model_requires_hardware", {})
		var choices: Dictionary = layer.get("asset_by_model", {})
		if not selector.is_empty() and not choices.is_empty():
			for model_value: Variant in choices.keys():
				var model_id := str(model_value)
				var assets := _asset_list(choices[model_value])
				var resolved := _resolved_assets(assets)
				definition["model_order"].append(model_id)
				definition["models"][model_id] = {
					"assets": assets,
					"resolved_assets": resolved,
					"render_ready": not resolved.is_empty(),
					"requires_hardware": requirements.get(model_id, ""),
				}
			if not selector in _slots:
				_slots.append(selector)
		else:
			var model_id := str(definition["default_model"])
			var assets := _layer_assets(layer)
			var resolved := _resolved_assets(assets)
			definition["model_order"].append(model_id)
			definition["models"][model_id] = {
				"assets": assets,
				"resolved_assets": resolved,
				"render_ready": not resolved.is_empty(),
				"requires_hardware": layer.get("requires_hardware", ""),
			}
		var all_models_ready := true
		for model: Dictionary in definition["models"].values():
			if not bool(model.get("render_ready", false)):
				all_models_ready = false
				break
		definition["render_ready"] = all_models_ready
		_devices[layer_id] = definition


static func _layer_assets(layer: Dictionary) -> Array:
	var values: Variant = layer.get("assets", [])
	if values is Array and not values.is_empty():
		return values.duplicate()
	return _asset_list(layer.get("asset", ""))


static func _asset_list(value: Variant) -> Array:
	if value is Array:
		return value.duplicate()
	var stem := str(value)
	return [] if stem.is_empty() else [stem]


static func _resolved_assets(stems: Array) -> Array:
	var result: Array = []
	for stem_value: Variant in stems:
		var stem := str(stem_value)
		var found := ""
		for version in range(MAX_VERSION, 0, -1):
			var path := "%s%s_V%02d.png" % [LAYER_DIR, stem, version]
			if FileAccess.file_exists(path):
				found = path
				break
		if found.is_empty():
			var plain := LAYER_DIR + stem + ".png"
			if FileAccess.file_exists(plain):
				found = plain
		if not found.is_empty():
			result.append(found)
	return result
