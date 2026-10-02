class_name SommerBasicFeatureCatalog
extends RefCounted
## Kanonischer Produktvertrag fuer die historisch wachsende Sommer-BASIC-API.
## Interpreter, Editor und VM duerfen diesen Katalog konsumieren, aber der
## Katalog selbst kennt keine UI und fuehrt keinen Nutzer-Code aus.

const DATA_PATH := "res://data/sommer_basic/feature_catalog.json"
const SCHEMA := "sommer_basic.features.v1"
const FIRST_YEAR := 1990
const LAST_YEAR := 1999
const REQUIRED_CATEGORIES := ["core", "graphics", "audio", "input", "file", "bank"]
const SuiteCatalog := preload("res://scripts/data/sommer_suite_catalog.gd")

static var _loaded := false
static var _document: Dictionary = {}
static var _features: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _by_symbol: Dictionary = {}
static var _profiles_by_year: Dictionary = {}
static var _load_error := ""


static func load_catalog() -> bool:
	_loaded = true
	_document = {}
	_features = []
	_by_id = {}
	_by_symbol = {}
	_profiles_by_year = {}
	_load_error = ""
	if not FileAccess.file_exists(DATA_PATH):
		_load_error = "Featurekatalog fehlt: %s" % DATA_PATH
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		_load_error = "Featurekatalog ist kein gueltiges JSON-Objekt: %s" % DATA_PATH
		return false
	_document = (parsed as Dictionary).duplicate(true)
	for raw_feature: Variant in _document.get("features", []):
		if not raw_feature is Dictionary:
			continue
		var entry: Dictionary = (raw_feature as Dictionary).duplicate(true)
		_features.append(entry)
		var feature_id := str(entry.get("id", ""))
		var symbol := str(entry.get("symbol", "")).to_upper()
		if not feature_id.is_empty() and not _by_id.has(feature_id):
			_by_id[feature_id] = entry
		if not symbol.is_empty() and not _by_symbol.has(symbol):
			_by_symbol[symbol] = entry
	for raw_profile: Variant in _document.get("annual_profiles", []):
		if not raw_profile is Dictionary:
			continue
		var profile: Dictionary = (raw_profile as Dictionary).duplicate(true)
		var year := int(profile.get("year", 0))
		if not _profiles_by_year.has(year):
			_profiles_by_year[year] = profile
	return true


static func _ensure() -> void:
	if not _loaded:
		load_catalog()


static func document() -> Dictionary:
	_ensure()
	return _document.duplicate(true)


static func all_features() -> Array[Dictionary]:
	_ensure()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _features:
		result.append(entry.duplicate(true))
	return result


static func feature(feature_id: String) -> Dictionary:
	_ensure()
	return _copy_dictionary(_by_id.get(feature_id, {}))


static func feature_by_symbol(symbol: String) -> Dictionary:
	_ensure()
	return _copy_dictionary(_by_symbol.get(symbol.strip_edges().to_upper(), {}))


static func annual_profile(year: int) -> Dictionary:
	_ensure()
	return _copy_dictionary(_profiles_by_year.get(year, {}))


static func introduced_in_year(year: int) -> Array[Dictionary]:
	_ensure()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _features:
		if int(entry.get("year_from", 0)) == year:
			result.append(entry.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("symbol", "")).naturalnocasecmp_to(
			str(b.get("symbol", ""))) < 0)
	return result


static func features_in_category(category: String, year := -1,
		target_profile_id := "") -> Array[Dictionary]:
	var source := all_features() if year < FIRST_YEAR else available_in_year(
		year, target_profile_id)
	var result: Array[Dictionary] = []
	for entry: Dictionary in source:
		if str(entry.get("category", "")) == category:
			result.append(entry)
	return result


## Ohne explizites Ziel wird das fuer diesen Sommer kanonische Maschinenprofil
## verwendet. Ein kuenstlich vorgezogenes AGA-Profil gilt vor seinem
## Einfuehrungsjahr trotzdem nicht als verfuegbar.
static func available_in_year(year: int, target_profile_id := "") -> Array[Dictionary]:
	_ensure()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _features:
		if bool(availability(str(entry.get("id", "")), year,
				target_profile_id).get("available", false)):
			result.append(entry.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := int(a.get("year_from", 0))
		var by := int(b.get("year_from", 0))
		if ay != by:
			return ay < by
		return str(a.get("symbol", "")).naturalnocasecmp_to(
			str(b.get("symbol", ""))) < 0)
	return result


static func symbols_available_in_year(year: int,
		target_profile_id := "") -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in available_in_year(year, target_profile_id):
		result.append(str(entry.get("symbol", "")))
	return result


## Liefert eine maschinenlesbare Sperrursache fuer Editor, Magazin-Listing,
## Quest und Sommerbench. `feature_ref` akzeptiert stabile ID oder BASIC-Symbol.
static func availability(feature_ref: String, year: int,
		target_profile_id := "") -> Dictionary:
	_ensure()
	var entry := feature(feature_ref)
	if entry.is_empty():
		entry = feature_by_symbol(feature_ref)
	if entry.is_empty():
		return _availability_result(false, "unknown_feature", {}, year, target_profile_id)
	if year < FIRST_YEAR or year > LAST_YEAR or not _profiles_by_year.has(year):
		return _availability_result(false, "year_out_of_range", entry, year,
			target_profile_id)
	if year < int(entry.get("year_from", FIRST_YEAR)):
		return _availability_result(false, "not_released_yet", entry, year,
			target_profile_id)
	var annual: Dictionary = _profiles_by_year[year]
	var effective_profile_id := target_profile_id
	if effective_profile_id.is_empty():
		effective_profile_id = str(annual.get("hardware_profile", ""))
	var target_profile := SuiteCatalog.hardware_profile(effective_profile_id)
	if target_profile.is_empty():
		return _availability_result(false, "unknown_hardware_profile", entry, year,
			effective_profile_id)
	if year < int(target_profile.get("year_from", 9999)):
		return _availability_result(false, "hardware_not_introduced", entry, year,
			effective_profile_id)
	if not _profile_is_compatible(str(entry.get("hardware_profile", "")),
			effective_profile_id):
		return _availability_result(false, "hardware_too_weak", entry, year,
			effective_profile_id)
	if str(entry.get("module", "")) not in annual.get("installed_modules", []):
		return _availability_result(false, "module_not_installed", entry, year,
			effective_profile_id)
	return _availability_result(true, "available", entry, year, effective_profile_id)


static func supports(feature_ref: String, year: int,
		target_profile_id := "") -> bool:
	return bool(availability(feature_ref, year, target_profile_id).get("available", false))


static func _availability_result(ok: bool, reason: String, entry: Dictionary,
		year: int, profile_id: String) -> Dictionary:
	return {
		"available": ok,
		"reason": reason,
		"year": year,
		"target_hardware_profile": profile_id,
		"feature": entry.duplicate(true),
		"required_year": int(entry.get("year_from", 0)),
		"required_hardware_profile": str(entry.get("hardware_profile", "")),
	}


static func _profile_is_compatible(required_id: String, target_id: String) -> bool:
	var required := SuiteCatalog.hardware_profile(required_id)
	var target := SuiteCatalog.hardware_profile(target_id)
	return not required.is_empty() and not target.is_empty() \
		and str(required.get("platform", "")) == str(target.get("platform", "")) \
		and int(target.get("tier", -1)) >= int(required.get("tier", 9999))


static func validate() -> Array[String]:
	_ensure()
	var issues: Array[String] = []
	if not _load_error.is_empty():
		issues.append(_load_error)
		return issues
	if str(_document.get("schema", "")) != SCHEMA:
		issues.append("schema muss %s sein." % SCHEMA)
	if str(_document.get("product_id", "")) != "sommer_basic":
		issues.append("product_id muss sommer_basic sein.")
	var suite_issues := SuiteCatalog.validate()
	if not suite_issues.is_empty():
		issues.append("Sommer-Suite-Hardwarevertrag ist ungueltig: %s" % suite_issues[0])
	_validate_annual_profiles(issues)
	_validate_features(issues)
	_validate_introduction_map(issues)
	return issues


static func _validate_annual_profiles(issues: Array[String]) -> void:
	var raw_profiles: Variant = _document.get("annual_profiles", null)
	if not raw_profiles is Array:
		issues.append("annual_profiles muss ein Array sein.")
		return
	if (raw_profiles as Array).size() != LAST_YEAR - FIRST_YEAR + 1:
		issues.append("Es werden exakt zehn Jahresprofile 1990-1999 erwartet.")
	var previous_limits: Dictionary = {}
	for year in range(FIRST_YEAR, LAST_YEAR + 1):
		if not _profiles_by_year.has(year):
			issues.append("Jahresprofil %d fehlt." % year)
			continue
		var profile: Dictionary = _profiles_by_year[year]
		for key in ["version", "hardware_profile", "installed_modules", "limits",
				"introduced_symbols"]:
			if not profile.has(key):
				issues.append("Jahresprofil %d: %s fehlt." % [year, key])
		var hardware_id := str(profile.get("hardware_profile", ""))
		var hardware := SuiteCatalog.hardware_profile(hardware_id)
		if hardware.is_empty():
			issues.append("Jahresprofil %d: unbekanntes Hardwareprofil %s." % [
				year, hardware_id])
		elif year < int(hardware.get("year_from", 9999)):
			issues.append("Jahresprofil %d: Hardware %s ist noch nicht eingefuehrt." % [
				year, hardware_id])
		if not profile.get("installed_modules", null) is Array:
			issues.append("Jahresprofil %d: installed_modules muss ein Array sein." % year)
		if not profile.get("introduced_symbols", null) is Array:
			issues.append("Jahresprofil %d: introduced_symbols muss ein Array sein." % year)
		var limits: Variant = profile.get("limits", null)
		if not limits is Dictionary:
			issues.append("Jahresprofil %d: limits muss ein Dictionary sein." % year)
			continue
		for limit_key in ["max_source_lines", "max_bank_kb", "max_colors",
				"max_screen_width", "max_screen_height"]:
			var value := int((limits as Dictionary).get(limit_key, 0))
			if value <= 0:
				issues.append("Jahresprofil %d: Limit %s ist ungueltig." % [year, limit_key])
			elif not previous_limits.is_empty() \
					and value < int(previous_limits.get(limit_key, 0)):
				issues.append("Jahresprofil %d: Limit %s darf nicht schrumpfen." % [
					year, limit_key])
		previous_limits = (limits as Dictionary).duplicate(true)


static func _validate_features(issues: Array[String]) -> void:
	var raw_features: Variant = _document.get("features", null)
	if not raw_features is Array:
		issues.append("features muss ein Array sein.")
		return
	var statuses: Array = _document.get("release_status_values", [])
	var seen_ids: Dictionary = {}
	var seen_symbols: Dictionary = {}
	for index in (raw_features as Array).size():
		var raw: Variant = (raw_features as Array)[index]
		if not raw is Dictionary:
			issues.append("Feature %d ist kein Dictionary." % index)
			continue
		var entry: Dictionary = raw
		var feature_id := str(entry.get("id", ""))
		var symbol := str(entry.get("symbol", ""))
		var label := feature_id if not feature_id.is_empty() else "Feature %d" % index
		if feature_id.is_empty() or feature_id != feature_id.to_snake_case() \
				or feature_id != feature_id.to_lower():
			issues.append("%s: ID muss stabiles snake_case sein." % label)
		if seen_ids.has(feature_id):
			issues.append("Doppelte Feature-ID: %s." % feature_id)
		seen_ids[feature_id] = true
		if symbol.is_empty() or symbol != symbol.to_upper():
			issues.append("%s: BASIC-Symbol muss nichtleer und grossgeschrieben sein." % label)
		if seen_symbols.has(symbol):
			issues.append("Doppeltes BASIC-Symbol: %s." % symbol)
		seen_symbols[symbol] = true
		if str(entry.get("category", "")) not in REQUIRED_CATEGORIES:
			issues.append("%s: ungueltige Kategorie." % label)
		if str(entry.get("kind", "")).is_empty() or str(entry.get("module", "")).is_empty():
			issues.append("%s: kind/module fehlt." % label)
		var year_from := int(entry.get("year_from", 0))
		if year_from < FIRST_YEAR or year_from > LAST_YEAR:
			issues.append("%s: year_from liegt ausserhalb 1990-1999." % label)
		if SuiteCatalog.hardware_profile(str(entry.get("hardware_profile", ""))).is_empty():
			issues.append("%s: unbekanntes Hardwareprofil." % label)
		if int(entry.get("min_ram_kb", 0)) <= 0:
			issues.append("%s: min_ram_kb muss positiv sein." % label)
		var chipsets: Variant = entry.get("chipsets", null)
		if not chipsets is Array or (chipsets as Array).is_empty():
			issues.append("%s: chipsets muss ein nichtleeres Array sein." % label)
		else:
			for chipset: Variant in chipsets:
				if str(chipset) not in ["OCS", "ECS", "AGA"]:
					issues.append("%s: unbekannter Chipsatz %s." % [label, chipset])
		if not entry.get("requires_hdd", null) is bool:
			issues.append("%s: requires_hdd muss boolesch sein." % label)
		if str(entry.get("signature", "")).strip_edges().is_empty():
			issues.append("%s: Signatur fehlt." % label)
		if str(entry.get("release_status", "")) not in statuses:
			issues.append("%s: ungueltiger release_status." % label)


static func _validate_introduction_map(issues: Array[String]) -> void:
	var announced: Dictionary = {}
	for year in range(FIRST_YEAR, LAST_YEAR + 1):
		if not _profiles_by_year.has(year):
			continue
		var profile: Dictionary = _profiles_by_year[year]
		for raw_symbol: Variant in profile.get("introduced_symbols", []):
			var symbol := str(raw_symbol).to_upper()
			if announced.has(symbol):
				issues.append("Symbol %s wird in mehreren Jahren eingefuehrt." % symbol)
			announced[symbol] = year
			if not _by_symbol.has(symbol):
				issues.append("Jahresprofil %d nennt unbekanntes Symbol %s." % [year, symbol])
			elif int((_by_symbol[symbol] as Dictionary).get("year_from", 0)) != year:
				issues.append("Symbol %s widerspricht seinem Einfuehrungsjahr." % symbol)
	for entry: Dictionary in _features:
		var symbol := str(entry.get("symbol", ""))
		if not announced.has(symbol):
			issues.append("Symbol %s fehlt in den Jahresprofilen." % symbol)
		var year := int(entry.get("year_from", 0))
		if _profiles_by_year.has(year):
			var annual: Dictionary = _profiles_by_year[year]
			if str(entry.get("module", "")) not in annual.get("installed_modules", []):
				issues.append("Symbol %s: Modul ist im Einfuehrungsjahr nicht installiert." % symbol)


static func _copy_dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
