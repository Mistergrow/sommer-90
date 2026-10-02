class_name SommerSuiteCatalog
extends RefCounted
## Kanonischer, read-only Katalog des historisch wachsenden
## "Sommer '90 Development System". ProgramLibrary bleibt bewusst getrennt:
## Dieser Vertrag beschreibt die Produkt-Suite und darf spaeter schrittweise
## von Workbench/Sommerbench, Quests und Magazin-Listings konsumiert werden.

const DATA_PATH := "res://data/sommer_suite.json"
const EXPECTED_PROGRAM_COUNT := 29
const PROGRAM_GROUPS := [&"development", &"productivity"]

static var _loaded := false
static var _document: Dictionary = {}
static var _programs: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _load_error := ""


## Expliziter Ladepunkt. Der Name vermeidet absichtlich `reload`, weil dieser
## bereits auf dem GDScript-Resource selbst existiert und externe Aufrufe sonst
## stillschweigend die Engine-Methode statt des Katalog-Laders treffen.
static func load_catalog() -> bool:
	_loaded = true
	_document = {}
	_programs = []
	_by_id = {}
	_load_error = ""
	if not FileAccess.file_exists(DATA_PATH):
		_load_error = "Katalogdatei fehlt: %s" % DATA_PATH
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		_load_error = "Katalogdatei ist kein gueltiges JSON-Objekt: %s" % DATA_PATH
		return false
	_document = (parsed as Dictionary).duplicate(true)
	for raw: Variant in _document.get("programs", []):
		if not raw is Dictionary:
			continue
		var program: Dictionary = (raw as Dictionary).duplicate(true)
		_programs.append(program)
		var program_id := str(program.get("id", ""))
		if not program_id.is_empty() and not _by_id.has(program_id):
			_by_id[program_id] = program
	return true


static func _ensure() -> void:
	if not _loaded:
		load_catalog()


static func document() -> Dictionary:
	_ensure()
	return _document.duplicate(true)


static func all() -> Array[Dictionary]:
	_ensure()
	var result: Array[Dictionary] = []
	for program: Dictionary in _programs:
		result.append(program.duplicate(true))
	return result


static func in_group(group_id: StringName) -> Array[Dictionary]:
	_ensure()
	var result: Array[Dictionary] = []
	for program: Dictionary in _programs:
		if StringName(program.get("group", "")) == group_id:
			result.append(program.duplicate(true))
	return result


static func ids_in_group(group_id: StringName) -> Array[String]:
	var result: Array[String] = []
	for program: Dictionary in in_group(group_id):
		result.append(str(program.get("id", "")))
	return result


static func definition(program_id: String) -> Dictionary:
	_ensure()
	var program: Variant = _by_id.get(program_id, {})
	return (program as Dictionary).duplicate(true) if program is Dictionary else {}


static func has(program_id: String) -> bool:
	_ensure()
	return _by_id.has(program_id)


static func hardware_profile(profile_id: String) -> Dictionary:
	_ensure()
	var profile: Variant = _document.get("hardware_profiles", {}).get(profile_id, {})
	return (profile as Dictionary).duplicate(true) if profile is Dictionary else {}


## Liefert die bis zu diesem Sommer freigeschaltete Suite. Ohne Zielprofil wird
## nur die Chronologie bewertet; mit Profil muss dessen Plattform passen und
## dessen Tier mindestens den Mindestvertrag des Programms erreichen.
static func available_in_year(year: int, target_profile_id := "") -> Array[Dictionary]:
	_ensure()
	var result: Array[Dictionary] = []
	for program: Dictionary in _programs:
		if year < int(program.get("year_from", 1990)) \
				or year > int(program.get("year_to", 1999)):
			continue
		if not target_profile_id.is_empty() \
				and not _profile_is_compatible(str(program.get("hardware_profile", "")),
					target_profile_id, year):
			continue
		result.append(program.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := int(a.get("year_from", 0))
		var by := int(b.get("year_from", 0))
		if ay != by:
			return ay < by
		return str(a.get("display_name", "")).naturalnocasecmp_to(
			str(b.get("display_name", ""))) < 0)
	return result


static func ids_available_in_year(year: int, target_profile_id := "") -> Array[String]:
	var result: Array[String] = []
	for program: Dictionary in available_in_year(year, target_profile_id):
		result.append(str(program.get("id", "")))
	return result


static func is_available(program_id: String, year: int, target_profile_id := "") -> bool:
	var program := definition(program_id)
	if program.is_empty() or year < int(program.get("year_from", 1990)) \
			or year > int(program.get("year_to", 1999)):
		return false
	return target_profile_id.is_empty() or _profile_is_compatible(
		str(program.get("hardware_profile", "")), target_profile_id, year)


static func programs_with_capability(capability: String, year := -1,
		target_profile_id := "") -> Array[Dictionary]:
	var source := all() if year < 0 else available_in_year(year, target_profile_id)
	var result: Array[Dictionary] = []
	for program: Dictionary in source:
		if capability in program.get("capabilities", []):
			result.append(program)
	return result


## Topologisch sortierte transitive Abhaengigkeiten; der angefragte Baustein
## selbst ist nicht enthalten. Bei ungueltigen IDs bleibt das Ergebnis leer.
static func dependency_order(program_id: String) -> Array[String]:
	_ensure()
	if not _by_id.has(program_id):
		return []
	var result: Array[String] = []
	var visited: Dictionary = {}
	_append_dependencies(program_id, visited, result)
	return result


static func _append_dependencies(program_id: String, visited: Dictionary,
		result: Array[String]) -> void:
	var program: Dictionary = _by_id.get(program_id, {})
	for dependency_value: Variant in program.get("dependencies", []):
		var dependency_id := str(dependency_value)
		if visited.has(dependency_id) or not _by_id.has(dependency_id):
			continue
		visited[dependency_id] = true
		_append_dependencies(dependency_id, visited, result)
		result.append(dependency_id)


static func _profile_is_compatible(required_id: String, target_id: String,
		year: int) -> bool:
	var profiles: Dictionary = _document.get("hardware_profiles", {})
	var required: Variant = profiles.get(required_id, {})
	var target: Variant = profiles.get(target_id, {})
	if not required is Dictionary or not target is Dictionary:
		return false
	return str((required as Dictionary).get("platform", "")) == \
			str((target as Dictionary).get("platform", "")) \
			and int((target as Dictionary).get("tier", -1)) >= \
			int((required as Dictionary).get("tier", 999)) \
			and year >= int((target as Dictionary).get("year_from", 9999))


static func validate() -> Array[String]:
	_ensure()
	var issues: Array[String] = []
	if not _load_error.is_empty():
		issues.append(_load_error)
		return issues
	if int(_document.get("schema_version", 0)) != 1:
		issues.append("schema_version muss 1 sein.")
	if str(_document.get("suite_id", "")).is_empty():
		issues.append("suite_id fehlt.")
	var raw_programs: Variant = _document.get("programs", null)
	if not raw_programs is Array:
		issues.append("programs muss ein Array sein.")
		return issues
	if (raw_programs as Array).size() != EXPECTED_PROGRAM_COUNT:
		issues.append("Katalog braucht exakt %d Programme, gefunden: %d." % [
			EXPECTED_PROGRAM_COUNT, (raw_programs as Array).size()])

	var profiles: Dictionary = _document.get("hardware_profiles", {})
	var statuses: Array = _document.get("release_status_values", [])
	_validate_profiles(profiles, issues)
	var seen: Dictionary = {}
	for index in (raw_programs as Array).size():
		var raw: Variant = (raw_programs as Array)[index]
		if not raw is Dictionary:
			issues.append("Programmeintrag %d ist kein Dictionary." % index)
			continue
		var program: Dictionary = raw
		var program_id := str(program.get("id", ""))
		var key := program_id if not program_id.is_empty() else "Eintrag %d" % index
		if program_id.is_empty() or program_id != program_id.to_snake_case() \
				or program_id != program_id.to_lower():
			issues.append("%s: ID muss stabiles snake_case sein." % key)
		if seen.has(program_id):
			issues.append("Doppelte Programm-ID: %s." % program_id)
		seen[program_id] = true
		for text_key in ["display_name", "purpose"]:
			if str(program.get(text_key, "")).strip_edges().is_empty():
				issues.append("%s: %s fehlt." % [key, text_key])
		var group_id := StringName(program.get("group", ""))
		if group_id not in PROGRAM_GROUPS:
			issues.append("%s: group muss development oder productivity sein." % key)
		var year_from := int(program.get("year_from", 0))
		var year_to := int(program.get("year_to", -1))
		if year_from < 1990 or year_from > 1999 or year_to < year_from or year_to > 1999:
			issues.append("%s: Jahresfenster muss innerhalb 1990-1999 liegen." % key)
		var profile_id := str(program.get("hardware_profile", ""))
		if not profiles.has(profile_id):
			issues.append("%s: unbekanntes Hardwareprofil %s." % [key, profile_id])
		if str(program.get("release_status", "")) not in statuses:
			issues.append("%s: ungueltiger release_status." % key)
		for list_key in ["modules", "capabilities", "file_types", "dependencies"]:
			if not program.get(list_key, null) is Array:
				issues.append("%s: %s muss ein Array sein." % [key, list_key])
			elif list_key != "dependencies" and (program[list_key] as Array).is_empty():
				issues.append("%s: %s darf nicht leer sein." % [key, list_key])
		_validate_string_list(program, "modules", key, issues)
		_validate_string_list(program, "capabilities", key, issues)
		_validate_file_types(program, key, issues)

	for program: Dictionary in _programs:
		var program_id := str(program.get("id", ""))
		for dependency_value: Variant in program.get("dependencies", []):
			var dependency_id := str(dependency_value)
			if dependency_id == program_id:
				issues.append("%s: Selbstabhaengigkeit." % program_id)
			elif not _by_id.has(dependency_id):
				issues.append("%s: unbekannte Abhaengigkeit %s." % [program_id, dependency_id])
			elif int((_by_id[dependency_id] as Dictionary).get("year_from", 9999)) > \
					int(program.get("year_from", 0)):
				issues.append("%s: Abhaengigkeit %s erscheint erst spaeter." % [
					program_id, dependency_id])
	_validate_dependency_cycles(issues)
	return issues


static func _validate_profiles(profiles: Dictionary, issues: Array[String]) -> void:
	if profiles.is_empty():
		issues.append("hardware_profiles fehlen.")
		return
	var seen_tiers: Dictionary = {}
	for profile_id: String in profiles:
		var raw: Variant = profiles[profile_id]
		if not raw is Dictionary:
			issues.append("Hardwareprofil %s ist kein Dictionary." % profile_id)
			continue
		var profile: Dictionary = raw
		if str(profile.get("display_name", "")).is_empty() \
				or str(profile.get("platform", "")).is_empty():
			issues.append("Hardwareprofil %s ist unvollstaendig." % profile_id)
		var tier := int(profile.get("tier", -1))
		var tier_key := "%s/%d" % [str(profile.get("platform", "")), tier]
		if tier < 0 or seen_tiers.has(tier_key):
			issues.append("Hardwareprofil %s hat einen ungueltigen/doppelten Tier." % profile_id)
		seen_tiers[tier_key] = true
		var year_from := int(profile.get("year_from", 0))
		if year_from < 1990 or year_from > 1999:
			issues.append("Hardwareprofil %s liegt ausserhalb der Dekade." % profile_id)


static func _validate_string_list(program: Dictionary, list_key: String,
		program_id: String, issues: Array[String]) -> void:
	var values: Variant = program.get(list_key, null)
	if not values is Array:
		return
	var seen: Dictionary = {}
	for raw_value: Variant in values:
		var value := str(raw_value).strip_edges()
		if value.is_empty() or seen.has(value):
			issues.append("%s: %s enthaelt einen leeren/doppelten Wert." % [
				program_id, list_key])
		seen[value] = true


static func _validate_file_types(program: Dictionary, program_id: String,
		issues: Array[String]) -> void:
	var values: Variant = program.get("file_types", null)
	if not values is Array:
		return
	var seen: Dictionary = {}
	for raw_value: Variant in values:
		var extension := str(raw_value).strip_edges().to_lower()
		if extension.length() < 2 or not extension.begins_with(".") or seen.has(extension):
			issues.append("%s: ungueltiger/doppelter Dateityp %s." % [
				program_id, extension])
		seen[extension] = true


static func _validate_dependency_cycles(issues: Array[String]) -> void:
	var visited: Dictionary = {}
	var active: Dictionary = {}
	for program_id: String in _by_id:
		if _dependency_cycle_from(program_id, visited, active):
			issues.append("Abhaengigkeitszyklus bei %s." % program_id)
			return


static func _dependency_cycle_from(program_id: String, visited: Dictionary,
		active: Dictionary) -> bool:
	if bool(active.get(program_id, false)):
		return true
	if bool(visited.get(program_id, false)):
		return false
	visited[program_id] = true
	active[program_id] = true
	var program: Dictionary = _by_id.get(program_id, {})
	for dependency_value: Variant in program.get("dependencies", []):
		var dependency_id := str(dependency_value)
		if _by_id.has(dependency_id) \
				and _dependency_cycle_from(dependency_id, visited, active):
			return true
	active.erase(program_id)
	return false
