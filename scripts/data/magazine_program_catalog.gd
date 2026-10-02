class_name MagazineProgramCatalog
extends RefCounted
## Kuratierter, autoload-freier Katalog der zehn originalen
## Sommer-BASIC-Abtippfolgen. UI und Questlogik erhalten ausschliesslich tiefe
## Kopien, damit der kanonische Datenbestand nie versehentlich veraendert wird.

const DATA_PATH := "res://data/sommer_basic/magazine_programs.json"
const SCHEMA := "sommer_basic.magazine_programs.v1"
const SERIES_ID := "sommer_basic_jahreswerkstatt"
const CONTENT_ORIGIN := "original_in_world"
const PRODUCTION_STATUS := "approved"
const FIRST_YEAR := 1990
const LAST_YEAR := 1999
const ENTRY_COUNT := 10
const MAX_SOURCE_LINE_LENGTH := 96
const BasicLanguage := preload("res://scripts/sommer_basic/sommer_basic_language.gd")
const SommerSuite := preload("res://scripts/data/sommer_suite_catalog.gd")

const REQUIRED_FIELDS := [
	"issue_id", "article_id", "listing_id", "title_de", "title_en",
	"year", "month", "chapter", "count", "canonical_source",
	"required_commands", "required_suite_apps", "hardware_profile", "expected_output",
	"production_status",
]
const REQUIRED_HARDWARE_FIELDS := [
	"machine_family", "chipset", "min_ram_kb", "runtime_profile", "display_mode",
]

static var _loaded := false
static var _root: Dictionary = {}
static var _entries: Array[Dictionary] = []
static var _by_year: Dictionary = {}
static var _by_issue: Dictionary = {}
static var _by_listing: Dictionary = {}


static func reload() -> void:
	_loaded = true
	_root = {}
	_entries.clear()
	_by_year.clear()
	_by_issue.clear()
	_by_listing.clear()
	if not FileAccess.file_exists(DATA_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		return
	_root = (parsed as Dictionary).duplicate(true)
	var raw_entries: Variant = _root.get("entries", [])
	if not raw_entries is Array:
		return
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			continue
		var entry := (raw_entry as Dictionary).duplicate(true)
		_entries.append(entry)
		_by_year[int(entry.get("year", -1))] = entry
		_by_issue[str(entry.get("issue_id", ""))] = entry
		_by_listing[str(entry.get("listing_id", ""))] = entry
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("year", 0)) < int(b.get("year", 0)))


static func _ensure_loaded() -> void:
	if not _loaded:
		reload()


static func all() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		result.append(entry.duplicate(true))
	return result


static func for_year(year: int) -> Dictionary:
	_ensure_loaded()
	return (_by_year.get(year, {}) as Dictionary).duplicate(true)


static func by_issue(issue_id: String) -> Dictionary:
	_ensure_loaded()
	return (_by_issue.get(issue_id, {}) as Dictionary).duplicate(true)


static func by_listing(listing_id: String) -> Dictionary:
	_ensure_loaded()
	return (_by_listing.get(listing_id, {}) as Dictionary).duplicate(true)


static func production_entries() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if str(entry.get("production_status", "")) == PRODUCTION_STATUS:
			result.append(entry.duplicate(true))
	return result


static func required_apps_for_year(year: int) -> PackedStringArray:
	var result := PackedStringArray()
	var entry := for_year(year)
	for app_id: Variant in entry.get("required_suite_apps", []):
		result.append(str(app_id))
	return result


static func validate() -> Array[String]:
	_ensure_loaded()
	var issues: Array[String] = []
	if _root.is_empty():
		return ["Katalog fehlt oder ist kein gueltiges JSON: %s" % DATA_PATH]
	if str(_root.get("schema", "")) != SCHEMA:
		issues.append("Unerwartetes Katalogschema.")
	if str(_root.get("series_id", "")) != SERIES_ID:
		issues.append("Die stabile Serien-ID fehlt.")
	if str(_root.get("content_origin", "")) != CONTENT_ORIGIN:
		issues.append("Der Katalog ist nicht als originaler In-World-Inhalt markiert.")
	if _entries.size() != ENTRY_COUNT:
		issues.append("Erwartet werden %d Folgen; gefunden: %d." % [ENTRY_COUNT, _entries.size()])

	var issue_ids: Dictionary = {}
	var article_ids: Dictionary = {}
	var listing_ids: Dictionary = {}
	var years: Dictionary = {}
	for entry: Dictionary in _entries:
		_validate_entry(entry, issues, issue_ids, article_ids, listing_ids, years)

	for year in range(FIRST_YEAR, LAST_YEAR + 1):
		if not years.has(year):
			issues.append("Fuer %d fehlt eine Jahresfolge." % year)
	return issues


static func _validate_entry(entry: Dictionary, issues: Array[String],
		issue_ids: Dictionary, article_ids: Dictionary,
		listing_ids: Dictionary, years: Dictionary) -> void:
	var label := str(entry.get("listing_id", "<ohne listing_id>"))
	for field: String in REQUIRED_FIELDS:
		if not entry.has(field):
			issues.append("%s: Pflichtfeld %s fehlt." % [label, field])

	_validate_unique_id("issue_id", entry, issue_ids, issues, label)
	_validate_unique_id("article_id", entry, article_ids, issues, label)
	_validate_unique_id("listing_id", entry, listing_ids, issues, label)
	if str(entry.get("title_de", "")).strip_edges().is_empty():
		issues.append("%s: Deutscher Titel fehlt." % label)
	if str(entry.get("title_en", "")).strip_edges().is_empty():
		issues.append("%s: Englischer Titel fehlt." % label)

	var year := int(entry.get("year", -1))
	if year < FIRST_YEAR or year > LAST_YEAR:
		issues.append("%s: Jahr %d liegt ausserhalb der Serie." % [label, year])
	elif years.has(year):
		issues.append("%s: Jahr %d ist doppelt belegt." % [label, year])
	else:
		years[year] = true
	var month := int(entry.get("month", 0))
	if month < 1 or month > 12:
		issues.append("%s: Monat muss zwischen 1 und 12 liegen." % label)
	var chapter := int(entry.get("chapter", 0))
	if chapter != year - FIRST_YEAR + 1:
		issues.append("%s: Kapitel passt nicht zum Erscheinungsjahr." % label)
	if int(entry.get("count", 0)) != ENTRY_COUNT:
		issues.append("%s: Serienumfang muss %d betragen." % [label, ENTRY_COUNT])
	if str(entry.get("production_status", "")) != PRODUCTION_STATUS:
		issues.append("%s: Folge ist nicht fuer die Produktion freigegeben." % label)

	_validate_apps(entry, issues, label)
	_validate_commands(entry, issues, label)
	_validate_hardware(entry, issues, label)
	_validate_expected_output(entry, issues, label)
	_validate_source(entry, issues, label)


static func _validate_unique_id(field: String, entry: Dictionary,
		seen: Dictionary, issues: Array[String], label: String) -> void:
	var identifier := str(entry.get(field, ""))
	if identifier.is_empty() or not identifier.is_valid_identifier():
		issues.append("%s: %s ist keine stabile technische ID." % [label, field])
	elif seen.has(identifier):
		issues.append("%s: %s %s ist doppelt." % [label, field, identifier])
	else:
		seen[identifier] = true


static func _validate_apps(entry: Dictionary, issues: Array[String], label: String) -> void:
	var apps: Variant = entry.get("required_suite_apps", null)
	if not apps is Array or (apps as Array).is_empty():
		issues.append("%s: Mindestens eine Suite-App wird benoetigt." % label)
		return
	var seen: Dictionary = {}
	for raw_app: Variant in apps as Array:
		var app_id := str(raw_app)
		if app_id.is_empty() or not app_id.is_valid_identifier():
			issues.append("%s: Ungueltige Suite-App-ID." % label)
		elif SommerSuite.definition(app_id).is_empty():
			issues.append("%s: Unbekannte Sommer-Suite-App %s." % [label, app_id])
		elif int(SommerSuite.definition(app_id).get("year_from", LAST_YEAR + 1)) > \
				int(entry.get("year", FIRST_YEAR)):
			issues.append("%s: Suite-App %s ist in diesem Jahr noch nicht erschienen." % [
				label, app_id])
		elif seen.has(app_id):
			issues.append("%s: Suite-App %s ist doppelt." % [label, app_id])
		else:
			seen[app_id] = true


static func _validate_commands(entry: Dictionary, issues: Array[String], label: String) -> void:
	var raw_commands: Variant = entry.get("required_commands", null)
	if not raw_commands is Array or (raw_commands as Array).is_empty():
		issues.append("%s: Vollstaendige Befehlsanforderungen fehlen." % label)
		return
	var declared: Dictionary = {}
	for raw_command: Variant in raw_commands as Array:
		var command := str(raw_command).to_upper()
		if command.is_empty() or not BasicLanguage.commands().has(command):
			issues.append("%s: Unbekannte Befehlsanforderung %s." % [label, command])
		elif not BasicLanguage.is_runtime_supported(command):
			issues.append("%s: %s ist im Laufzeitprofil noch nicht implementiert." % [
				label, command])
		elif declared.has(command):
			issues.append("%s: Befehl %s ist doppelt deklariert." % [label, command])
		else:
			declared[command] = true
	for command: String in _source_commands(str(entry.get("canonical_source", ""))):
		if not declared.has(command):
			issues.append("%s: Im Listing verwendeter Befehl %s fehlt in required_commands." % [
				label, command])
	for command: Variant in declared:
		if not _source_commands(str(entry.get("canonical_source", ""))).has(str(command)):
			issues.append("%s: Deklarierter Befehl %s kommt im Listing nicht vor." % [
				label, str(command)])


static func _source_commands(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	for source_line: String in source.split("\n", true):
		var numbered: Dictionary = BasicLanguage._take_line_number(source_line.strip_edges())
		var body := BasicLanguage._without_comment(str(numbered.get("body", "")))
		for raw_statement: String in BasicLanguage._split_statements(body):
			_collect_statement_commands(raw_statement.strip_edges(), found)
	return found


static func _collect_statement_commands(statement: String, found: PackedStringArray) -> void:
	var command := BasicLanguage._first_word(statement)
	if command.is_empty() or not BasicLanguage.commands().has(command):
		return
	if not found.has(command):
		found.append(command)
	if command != "IF":
		return
	var upper := statement.to_upper()
	var then_at := upper.find(" THEN ")
	if then_at < 0:
		return
	var branches := statement.substr(then_at + 6).strip_edges()
	var else_at := branches.to_upper().find(" ELSE ")
	_collect_statement_commands(
		branches if else_at < 0 else branches.substr(0, else_at).strip_edges(), found)
	if else_at >= 0:
		_collect_statement_commands(branches.substr(else_at + 6).strip_edges(), found)


static func _validate_hardware(entry: Dictionary, issues: Array[String], label: String) -> void:
	var raw_profile: Variant = entry.get("hardware_profile", null)
	if not raw_profile is Dictionary:
		issues.append("%s: Hardwareprofil fehlt." % label)
		return
	var profile := raw_profile as Dictionary
	for field: String in REQUIRED_HARDWARE_FIELDS:
		if not profile.has(field):
			issues.append("%s: Hardwarefeld %s fehlt." % [label, field])
	if str(profile.get("machine_family", "")).is_empty():
		issues.append("%s: Rechnerfamilie fehlt." % label)
	if str(profile.get("chipset", "")) not in ["OCS", "ECS", "AGA"]:
		issues.append("%s: Unbekannter Chipsatz." % label)
	if int(profile.get("min_ram_kb", 0)) < 512:
		issues.append("%s: Mindest-RAM ist unplausibel." % label)
	if str(profile.get("runtime_profile", "")) != "sommer_basic_vm_v1":
		issues.append("%s: Listing verweist nicht auf den getesteten Laufzeitkern." % label)
	if str(profile.get("display_mode", "")).is_empty():
		issues.append("%s: Bildschirmmodus fehlt." % label)
	if str(profile.get("display_mode", "")).ends_with("_32") and \
			str(profile.get("chipset", "")) != "AGA":
		issues.append("%s: 32-Farben-Profil benoetigt AGA." % label)


static func _validate_expected_output(entry: Dictionary,
		issues: Array[String], label: String) -> void:
	var raw_expected: Variant = entry.get("expected_output", null)
	if not raw_expected is Dictionary:
		issues.append("%s: Erwartete Ausgabe fehlt." % label)
		return
	var expected := raw_expected as Dictionary
	if not expected.get("console", null) is Array:
		issues.append("%s: Konsolenausgabe muss eine Liste sein." % label)
	if not expected.get("draw_op_counts", null) is Dictionary:
		issues.append("%s: Zeichenoperationen muessen gezaehlt sein." % label)
	else:
		for operation: Variant in (expected.get("draw_op_counts", {}) as Dictionary):
			if int((expected.get("draw_op_counts", {}) as Dictionary)[operation]) < 0:
				issues.append("%s: Negative Anzahl fuer %s." % [label, str(operation)])
	if not expected.get("final_variables", null) is Dictionary:
		issues.append("%s: Endvariablen muessen ein Dictionary sein." % label)


static func _validate_source(entry: Dictionary, issues: Array[String], label: String) -> void:
	var source := str(entry.get("canonical_source", ""))
	if source.strip_edges().is_empty():
		issues.append("%s: Kanonisches Listing fehlt." % label)
		return
	if source.contains("\r") or source.contains("\t"):
		issues.append("%s: Listing enthaelt nicht-kanonische Steuerzeichen." % label)
	for source_line: String in source.split("\n", true):
		if source_line.length() > MAX_SOURCE_LINE_LENGTH:
			issues.append("%s: Listingzeile ist laenger als %d Zeichen." % [
				label, MAX_SOURCE_LINE_LENGTH])
	var analysis: Dictionary = BasicLanguage.analyze(source)
	if not bool(analysis.get("ok", false)):
		issues.append("%s: Kanonisches Listing kompiliert nicht." % label)
