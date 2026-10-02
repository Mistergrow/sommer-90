class_name DialogueDefinitionCatalog
extends RefCounted
## Lädt pro NPC getrennte Dialogpakete und garantiert global eindeutige IDs.

const MANIFEST_PATH := "res://data/dialogues.json"


static func definitions() -> Dictionary:
	var manifest := _read_document(MANIFEST_PATH)
	var result: Dictionary = {}
	for package_value: Variant in manifest.get("packages", []):
		if not package_value is Dictionary:
			push_error("DialogueDefinitionCatalog: ungueltiger Paketeintrag")
			continue
		var package: Dictionary = package_value
		var path := str(package.get("path", ""))
		var owner := str(package.get("owner", ""))
		var document := _read_document(path)
		if document.is_empty():
			continue
		if str(document.get("owner", "")) != owner:
			push_error("DialogueDefinitionCatalog: Owner stimmt nicht: %s" % path)
			continue
		var entries: Dictionary = document.get("dialogues", {})
		for dialogue_id: String in entries:
			if result.has(dialogue_id):
				push_error("DialogueDefinitionCatalog: doppelte Dialog-ID %s" % dialogue_id)
				continue
			var definition: Dictionary = entries[dialogue_id]
			definition["content_owner"] = owner
			result[dialogue_id] = definition
	return result


static func source_text() -> String:
	var result := FileAccess.get_file_as_string(MANIFEST_PATH)
	var manifest := _read_document(MANIFEST_PATH)
	for package_value: Variant in manifest.get("packages", []):
		if package_value is Dictionary:
			result += "\n" + FileAccess.get_file_as_string(str(package_value.get("path", "")))
	return result


static func package_paths() -> Array[String]:
	var paths: Array[String] = []
	for package_value: Variant in _read_document(MANIFEST_PATH).get("packages", []):
		if package_value is Dictionary:
			paths.append(str(package_value.get("path", "")))
	return paths


static func _read_document(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("DialogueDefinitionCatalog: Datei fehlt: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("DialogueDefinitionCatalog: ungueltiges JSON: %s" % path)
		return {}
	return parsed


## Antwort-IDs bleiben beim Umordnen stabil. Der Index ist nur Legacy-Fallback
## fuer dynamische Dialoge, die noch keine Autoren-ID mitbringen.
static func choice_key(dialogue_id: String, node_id: String, choice: Dictionary, index: int) -> String:
	var id := str(choice.get("id", ""))
	return "dlg.%s.%s.choice.%s" % [dialogue_id, node_id, id] if not id.is_empty() \
		else "dlg.%s.%s.c%d" % [dialogue_id, node_id, index]
