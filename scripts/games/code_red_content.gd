class_name CodeRedContent
extends RefCounted
## Datenzugriff und defensive Validierung fuer CODE RED. Neue Berater, Regionen,
## Projekte oder Optik-Faelle koennen ueber JSON ergaenzt werden, ohne UI oder
## Simulationskern umzuschreiben.

const CONFIG_PATH := "res://data/code_red_simulation.json"
const LIST_KEYS := ["doctrines", "advisors", "regions", "opponents", "projects",
	"optics_scenarios", "historical_sky", "sky_events", "public_signals"]

var data: Dictionary = {}
var indexes: Dictionary = {}


func load_config() -> bool:
	data = {}
	indexes = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != 1:
		return false
	data = (parsed as Dictionary).duplicate(true)
	for key: String in LIST_KEYS:
		var by_id: Dictionary = {}
		for raw: Variant in data.get(key, []):
			if not raw is Dictionary:
				continue
			var entry: Dictionary = raw
			var id := str(entry.get("id", "")).strip_edges()
			if not id.is_empty() and not by_id.has(id):
				by_id[id] = entry.duplicate(true)
		indexes[key] = by_id
	return true


func all(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in data.get(kind, []):
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


func get_entry(kind: String, id: String) -> Dictionary:
	return ((indexes.get(kind, {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func ids(kind: String) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in (indexes.get(kind, {}) as Dictionary).keys():
		out.append(str(raw))
	out.sort()
	return out


func validate() -> Array[String]:
	var errors: Array[String] = []
	for key: String in LIST_KEYS:
		var seen: Dictionary = {}
		for entry: Dictionary in all(key):
			var id := str(entry.get("id", ""))
			if id.is_empty():
				errors.append("%s: Eintrag ohne ID" % key)
			elif seen.has(id):
				errors.append("%s: doppelte ID %s" % [key, id])
			else:
				seen[id] = true
	for doctrine: Dictionary in all("doctrines"):
		if not doctrine.get("effects", {}) is Dictionary:
			errors.append("Doktrin %s: effects fehlt" % str(doctrine.get("id", "?")))
	for project: Dictionary in all("projects"):
		if int(project.get("duration", 0)) <= 0 or float(project.get("cost", -1)) < 0.0:
			errors.append("Projekt %s: Dauer/Kosten ungueltig" % str(project.get("id", "?")))
	for scenario: Dictionary in all("optics_scenarios"):
		var choices: Array = scenario.get("choices", [])
		if choices.size() < 2 or str(scenario.get("correct", "")).is_empty():
			errors.append("Optik %s: Auswahl unvollstaendig" % str(scenario.get("id", "?")))
	for archive: Dictionary in all("historical_sky"):
		if int(archive.get("year", 0)) <= 0 or str(archive.get("status", "")) not in ["BELEGT", "HYPOTHESE"]:
			errors.append("Himmelsarchiv %s: Jahr/Status ungueltig" % str(archive.get("id", "?")))
	for sky_event: Dictionary in all("sky_events"):
		if str(sky_event.get("period", "")).is_empty() or (sky_event.get("choices", []) as Array).size() < 2:
			errors.append("Himmelsereignis %s: Periode/Auswahl unvollstaendig" % str(sky_event.get("id", "?")))
	for signal_entry: Dictionary in all("public_signals"):
		if int(signal_entry.get("year", 0)) < 1962 or str(signal_entry.get("title", "")).is_empty():
			errors.append("Oeffentlichkeit %s: Jahr/Titel ungueltig" % str(signal_entry.get("id", "?")))
	return errors
