class_name QuestDefinitionCatalog
extends RefCounted
## Lädt die nach Auftraggeber getrennten Questpakete in stabiler Manifest-Reihenfolge.
## Das Manifest ist die einzige Liste von Contentquellen; QuestManager und Tests
## verwenden dadurch exakt denselben Katalogvertrag.

const MANIFEST_PATH := "res://data/quests.json"


static func definitions() -> Array:
	var manifest := _read_document(MANIFEST_PATH)
	var result: Array = []
	var ids: Dictionary = {}
	for package_value: Variant in manifest.get("packages", []):
		if not package_value is Dictionary:
			push_error("QuestDefinitionCatalog: ungueltiger Paketeintrag")
			continue
		var package: Dictionary = package_value
		var path := str(package.get("path", ""))
		var owner := str(package.get("owner", ""))
		var document := _read_document(path)
		if document.is_empty():
			continue
		if str(document.get("owner", "")) != owner:
			push_error("QuestDefinitionCatalog: Owner stimmt nicht: %s" % path)
			continue
		for quest_value: Variant in document.get("quests", []):
			if not quest_value is Dictionary:
				push_error("QuestDefinitionCatalog: ungueltige Quest in %s" % path)
				continue
			var quest: Dictionary = quest_value
			var quest_id := str(quest.get("id", ""))
			if quest_id.is_empty():
				push_error("QuestDefinitionCatalog: Quest ohne ID in %s" % path)
				continue
			if ids.has(quest_id):
				push_error("QuestDefinitionCatalog: doppelte Quest-ID %s" % quest_id)
				continue
			if str(quest.get("giver", "")) != owner:
				push_error("QuestDefinitionCatalog: falscher Geber fuer %s" % quest_id)
				continue
			ids[quest_id] = path
			result.append(quest)
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
		push_error("QuestDefinitionCatalog: Datei fehlt: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("QuestDefinitionCatalog: ungueltiges JSON: %s" % path)
		return {}
	return parsed
