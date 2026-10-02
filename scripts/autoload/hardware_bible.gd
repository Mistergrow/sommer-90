extends Node
## HardwareBible — lädt data/hardware_db.json als EINZIGE Wahrheitsquelle für
## Geräte-Katalogdaten (Name, Marktjahre, Preis, Rarität) der Ära 1990–1999.
## Konsumenten: ShopManager (db_name-Drift-Guard), Tests; kommende Features
## (Drucker-Details, Flohmarkt-Gebrauchtgeräte, Sammlung) docken hier an.
## Politik wie SoftwareBible: nie Fakten erfinden — nur echte Katalogdaten.

const PATH := "res://data/hardware_db.json"

var categories: Dictionary = {}      # kategorie -> Array[Dictionary]
var _by_name: Dictionary = {}        # exakter Gerätename -> Eintrag
var loaded: bool = false


func _ready() -> void:
	reload()


func reload() -> void:
	categories = {}
	_by_name = {}
	loaded = false
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("HardwareBible: %s nicht lesbar." % PATH)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("HardwareBible: %s ist kein JSON-Objekt." % PATH)
		return
	categories = (data as Dictionary).get("categories", {})
	for cat: String in categories:
		for entry: Variant in categories[cat]:
			# software_kategorien/zimmerobjekte sind reine Namenslisten (Strings),
			# nur Geräte-Kategorien tragen volle Katalog-Dictionaries.
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var device_name := str((entry as Dictionary).get("name", "")).strip_edges()
			if device_name.is_empty():
				continue
			var enriched: Dictionary = (entry as Dictionary).duplicate()
			enriched["category"] = cat
			_by_name[device_name] = enriched
	loaded = true


func count() -> int:
	return _by_name.size()


func has_device(device_name: String) -> bool:
	return _by_name.has(device_name)


## Kompletter Katalog-Eintrag (inkl. "category") oder {}.
func device(device_name: String) -> Dictionary:
	return (_by_name.get(device_name, {}) as Dictionary).duplicate()


func category(cat: String) -> Array:
	return (categories.get(cat, []) as Array).duplicate()


func year_from(device_name: String) -> int:
	return int((_by_name.get(device_name, {}) as Dictionary).get("year_from", 0))


func year_to(device_name: String) -> int:
	return int((_by_name.get(device_name, {}) as Dictionary).get("year_to", 0))


func price(device_name: String) -> int:
	return int((_by_name.get(device_name, {}) as Dictionary).get("price", 0))
