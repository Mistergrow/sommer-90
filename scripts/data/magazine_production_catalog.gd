class_name MagazineProductionCatalog
extends RefCounted
## Freigegebene, durch den Produktionsimporter verwaltete Magazine. Der Katalog
## ist bewusst autoload-frei: Kiosk, Leser und Tests greifen auf denselben
## unveraenderlichen Datenbestand zu, ohne Savegames oder Editorzustand zu
## beeinflussen.

const DATA_PATH := "res://Content/Magazine/index.json"
const SCHEMA := "magazine.v1"
const APPROVED := "approved"

static var _loaded := false
static var _entries: Array[Dictionary] = []
static var _by_issue: Dictionary = {}
static var _by_date: Dictionary = {}


static func reload() -> void:
	_loaded = true
	_entries.clear()
	_by_issue.clear()
	_by_date.clear()
	if not FileAccess.file_exists(DATA_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or str((parsed as Dictionary).get("schema", "")) != SCHEMA:
		return
	var raw_entries: Variant = (parsed as Dictionary).get("entries", [])
	if not raw_entries is Array:
		return
	for raw_entry: Variant in raw_entries as Array:
		if not raw_entry is Dictionary:
			continue
		var entry := (raw_entry as Dictionary).duplicate(true)
		if str(entry.get("production_status", "")) != APPROVED \
				or str(entry.get("rights_status", "")) != APPROVED:
			continue
		var issue_id := str(entry.get("issue_id", ""))
		var year := int(entry.get("year", 0))
		var month := int(entry.get("month", 0))
		if issue_id.is_empty() or year < 1990 or month < 1 or month > 12:
			continue
		_entries.append(entry)
		_by_issue[issue_id] = entry
		var date_key := _date_key(year, month)
		if not _by_date.has(date_key):
			_by_date[date_key] = entry
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key := int(a.get("year", 0)) * 100 + int(a.get("month", 0))
		var b_key := int(b.get("year", 0)) * 100 + int(b.get("month", 0))
		return a_key < b_key)


static func _ensure_loaded() -> void:
	if not _loaded:
		reload()


static func all() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		result.append(entry.duplicate(true))
	return result


static func for_date(year: int, month: int) -> Dictionary:
	_ensure_loaded()
	return (_by_date.get(_date_key(year, month), {}) as Dictionary).duplicate(true)


static func by_issue(issue_id: String) -> Dictionary:
	_ensure_loaded()
	return (_by_issue.get(issue_id, {}) as Dictionary).duplicate(true)


static func asset_path(entry: Dictionary, asset_id: String) -> String:
	var assets: Variant = entry.get("assets", {})
	if not assets is Dictionary:
		return ""
	var asset: Variant = (assets as Dictionary).get(asset_id, {})
	if not asset is Dictionary:
		return ""
	return str((asset as Dictionary).get("path", ""))


static func page_asset_id(page_index: int) -> String:
	match page_index:
		0: return "cover_front"
		1: return "page_spread_01"
		2: return "page_spread_02"
		3: return "page_spread_03"
		4: return "cover_back"
	return ""


static func _date_key(year: int, month: int) -> String:
	return "%04d-%02d" % [year, month]
