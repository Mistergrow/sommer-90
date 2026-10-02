class_name SommerSuiteRuntimeCatalog
extends RefCounted
## Verbindet den kanonischen 29-Programme-Katalog mit der geprueften
## Implementierungs-Map. Diese Klasse ist absichtlich die einzige Stelle, an
## der Spielerstatus, Installationsstand und sichere Startplaene zusammenkommen.

const SuiteCatalog := preload("res://scripts/data/sommer_suite_catalog.gd")
const IMPLEMENTATION_PATH := "res://data/sommer_suite_implementation_map.json"

static var _loaded := false
static var _implementations: Dictionary = {}
static var _load_error := ""


static func load_catalog() -> bool:
	_loaded = true
	_implementations = {}
	_load_error = ""
	if not SuiteCatalog.load_catalog():
		_load_error = "Sommer-Suite-Katalog konnte nicht geladen werden."
		return false
	if not FileAccess.file_exists(IMPLEMENTATION_PATH):
		_load_error = "Implementierungs-Map fehlt: %s" % IMPLEMENTATION_PATH
		return false
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(IMPLEMENTATION_PATH))
	if not parsed is Dictionary:
		_load_error = "Implementierungs-Map ist kein gueltiges JSON-Objekt."
		return false
	for raw: Variant in (parsed as Dictionary).get("entries", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = (raw as Dictionary).duplicate(true)
		var program_id := str(entry.get("id", ""))
		if not program_id.is_empty():
			_implementations[program_id] = entry
	return true


static func _ensure() -> void:
	if not _loaded:
		load_catalog()


static func implementation(program_id: String) -> Dictionary:
	_ensure()
	var value: Variant = _implementations.get(program_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func all_joined() -> Array[Dictionary]:
	_ensure()
	var result: Array[Dictionary] = []
	for definition: Dictionary in SuiteCatalog.all():
		var joined := definition.duplicate(true)
		joined["implementation"] = implementation(str(definition.get("id", "")))
		result.append(joined)
	return result


## Das freie Spiel nach 1999 behaelt den letzten Entwicklungsstand. Dadurch
## verschwinden Werkzeuge nicht ausgerechnet nach dem Kampagnenfinale.
static func effective_year(year: int) -> int:
	return clampi(year, 1990, 1999)


static func active_hardware_profile() -> String:
	var stats := _root_node("PlayerStats")
	if stats == null:
		return "amiga_500_ocs_1mb"
	match str(stats.call("desk_model", "computer_model")):
		"amiga_1200":
			var hardware: Dictionary = stats.get("hardware")
			return "amiga_1200_aga_hdd_4mb" if bool(stats.call("hdd_is_usable")) \
				and float(hardware.get("ram_mb", 0.0)) >= 4.0 \
				else "amiga_1200_aga_2mb"
		"amiga_600":
			return "amiga_500_ecs_1mb"
		_:
			return "amiga_500_ocs_1mb"


static func player_status(program_id: String, year := -1,
		hardware_profile := "") -> Dictionary:
	_ensure()
	var definition := SuiteCatalog.definition(program_id)
	var implementation_entry := implementation(program_id)
	if definition.is_empty() or implementation_entry.is_empty():
		return _status("invalid", false,
			_loc("unknown", "UNBEKANNT"),
			_loc("reason_incomplete", "Der Programmeintrag ist unvollstaendig."))
	var time := _root_node("TimeManager")
	var current_year := int(time.get("year")) if time != null else 1990
	var wanted_year := effective_year(current_year if year < 0 else year)
	var wanted_profile := active_hardware_profile() if hardware_profile.is_empty() \
		else hardware_profile
	var first_year := int(definition.get("year_from", 1990))
	if wanted_year < first_year:
		return _status("future", false,
			_loc("from_year", "AB %d") % first_year,
			_loc("reason_future", "Dieses Modul erscheint im Sommer %d.") % first_year)
	if not SuiteCatalog.is_available(program_id, wanted_year, wanted_profile):
		var required := SuiteCatalog.hardware_profile(
			str(definition.get("hardware_profile", "")))
		var required_id := str(definition.get("hardware_profile", ""))
		var required_name := Loc.t("ui.sommer_suite.profile.%s" % required_id,
			str(required.get("display_name", "anderes System")))
		return _status("hardware", false,
			_loc("hardware", "HARDWARE"),
			_loc("reason_hardware", "Benoetigt: %s") % required_name)
	var classification := str(implementation_entry.get("classification", "missing"))
	if classification == "missing":
		return _status("missing", false,
			_loc("missing", "MODUL FEHLT"),
			_first_gap(implementation_entry))
	var plan := launch_plan(program_id)
	if plan.is_empty():
		return _status("uninstalled", false,
			_loc("not_installed", "NICHT INSTALLIERT"),
			_loc("reason_not_installed",
				"Das passende Programmmodul muss zuerst installiert oder freigeschaltet werden."))
	return _status("native" if classification == "native" else "adapter", true,
		_loc("native", "NATIV") if classification == "native" else
			_loc("compatible", "KOMPATIBEL"),
		_loc("reason_native", "Eigene Sommer-Anwendung.") if classification == "native" else
			_loc("reason_adapter", "Startet den vorhandenen kompatiblen Werkzeugpfad."), plan)


## Liefert nur Startplaene, die durch eine wirklich installierte Programm-ID
## belegt sind. Ein `missing`-Eintrag kann hier niemals versehentlich starten.
static func launch_plan(program_id: String) -> Dictionary:
	_ensure()
	var library := _root_node("ProgramLibrary")
	var ui := _root_node("UIManager")
	if library == null or ui == null:
		return {}
	var entry := implementation(program_id)
	var classification := str(entry.get("classification", "missing"))
	if classification == "missing":
		return {}
	if classification == "native":
		var native_id := str(entry.get("native_program_id", ""))
		if native_id.is_empty() or not bool(library.call("is_installed", native_id)):
			return {}
		for key_value: Variant in entry.get("launch_app_keys", []):
			var key := str(key_value)
			if key != "" and key != "generic" and ui.has_method(key):
				return {"kind": "ui_method", "method": key,
					"program_id": native_id}
		return {}

	var allowed_keys: Array = entry.get("launch_app_keys", [])
	for legacy_value: Variant in entry.get("legacy_program_ids", []):
		var legacy_id := str(legacy_value)
		if not bool(library.call("is_installed", legacy_id)):
			continue
		var program: Dictionary = library.call("get_program", legacy_id)
		var app_key := str(program.get("app_key", ""))
		if app_key == "generic" and allowed_keys.has("generic"):
			return {"kind": "program", "program_id": legacy_id}
		if app_key != "" and app_key != "generic" and allowed_keys.has(app_key) \
				and ui.has_method(app_key):
			return {"kind": "ui_method", "method": app_key,
				"program_id": legacy_id}
	return {}


static func validate() -> Array[String]:
	_ensure()
	var issues: Array[String] = []
	if not _load_error.is_empty():
		issues.append(_load_error)
	for definition: Dictionary in SuiteCatalog.all():
		var program_id := str(definition.get("id", ""))
		if not _implementations.has(program_id):
			issues.append("Implementierungsstatus fehlt: %s" % program_id)
	return issues


static func _first_gap(entry: Dictionary) -> String:
	var gaps: Array = entry.get("capability_gaps", [])
	var program_id := str(entry.get("id", ""))
	var fallback := str(gaps[0]) if not gaps.is_empty() else \
		"Fuer dieses Werkzeug existiert noch kein spielbarer Editor."
	return Loc.t("ui.sommer_suite.tool.%s.gap" % program_id, fallback)


static func _loc(key: String, fallback: String) -> String:
	return Loc.t("ui.sommer_suite.status.%s" % key, fallback)


static func _root_node(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree != null else null


static func _status(state: String, can_launch: bool, label: String,
		reason: String, plan: Dictionary = {}) -> Dictionary:
	return {"state": state, "can_launch": can_launch, "label": label,
		"reason": reason, "launch_plan": plan.duplicate(true)}
