class_name RoomPreviewModels
extends RefCounted
## Reine Modellvarianten-Logik der Raum-Werkstatt. Der Compositor behaelt
## Rendering/Rebuild; diese Klasse normalisiert Auswahl und Modellfelder.


static func available(config: Dictionary, selector: String) -> Array:
	var result: Array = []
	for raw: Variant in config.get("layers", []):
		if not raw is Dictionary:
			continue
		var layer: Dictionary = raw
		if bool(layer.get("disabled", false)) \
				or str(layer.get("model_selector", "")) != selector:
			continue
		var choices: Dictionary = layer.get("asset_by_model", {})
		for model_value: Variant in choices.keys():
			var stems: Variant = choices[model_value]
			var candidates: Array = stems if stems is Array else [stems]
			for stem_value: Variant in candidates:
				if not RoomAssets.find_asset(str(stem_value)).is_empty():
					result.append(str(model_value))
					break
		break
	return result


static func default_for(config: Dictionary, selector: String) -> String:
	for raw: Variant in config.get("layers", []):
		if raw is Dictionary and str(raw.get("model_selector", "")) == selector:
			return str(raw.get("default_model", ""))
	return ""


static func active(config: Dictionary, state: Dictionary, selector: String,
		fallback := "") -> String:
	var models := available(config, selector)
	if models.is_empty():
		return ""
	var wanted := str(state.get(selector,
		fallback if not fallback.is_empty() else default_for(config, selector)))
	return wanted if wanted in models else str(models[0])


static func validate(config: Dictionary, state: Dictionary, defaults: Dictionary = {}) -> void:
	for raw: Variant in config.get("layers", []):
		if not raw is Dictionary:
			continue
		var selector := str(raw.get("model_selector", ""))
		if selector.is_empty() or bool(raw.get("disabled", false)):
			continue
		var fallback := str(defaults.get(selector, raw.get("default_model", "")))
		var selected := active(config, state, selector, fallback)
		if selected.is_empty():
			state.erase(selector)
		else:
			state[selector] = selected


static func select(config: Dictionary, state: Dictionary, selector: String,
		model_id: String) -> bool:
	var models := available(config, selector)
	if model_id not in models:
		return false
	state[selector] = model_id
	return true


static func cycle(config: Dictionary, state: Dictionary, selector: String,
		direction: int) -> bool:
	var models := available(config, selector)
	if models.size() < 2:
		return false
	var index := models.find(active(config, state, selector))
	if index < 0:
		index = 0
	state[selector] = str(models[posmod(index + (1 if direction >= 0 else -1),
		models.size())])
	return true


static func resolve(source: Dictionary, selected: String) -> Dictionary:
	var layer := source.duplicate(true)
	var choices: Dictionary = layer.get("asset_by_model", {})
	if choices.is_empty():
		return layer
	if not choices.has(selected):
		selected = str(layer.get("default_model",
			choices.keys()[0] if not choices.is_empty() else ""))
	var chosen: Variant = choices.get(selected, [])
	layer["assets"] = chosen if chosen is Array else [chosen]
	layer["active_model"] = selected
	for field: String in ["width", "height", "rotation", "skew"]:
		var values: Dictionary = layer.get(field + "_by_model", {})
		if values.has(selected):
			layer[field] = float(values[selected])
	if not (layer.get("height_by_model", {}) as Dictionary).has(selected) \
			and layer.has("height") and bool(layer.get("preserve_aspect_by_model", true)):
		layer.erase("height")
	var offsets: Dictionary = layer.get("anchor_offset_by_model", {})
	if offsets.has(selected) and offsets[selected] is Array \
			and (offsets[selected] as Array).size() >= 2:
		layer["anchor_offset"] = (offsets[selected] as Array).duplicate()
	return layer
