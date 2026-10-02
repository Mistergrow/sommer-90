class_name SoftwareInsertCatalog
extends RefCounted
## Zentrale Wahrheit fuer physische Software-Beilagen. Disketten, Inventar,
## Viewer und Kopierschutz fragen denselben Katalog statt Herkunft zu erraten.

const CODE_RED_ID := "code_red_protocol"
const CODE_RED_WORDS: Array[String] = [
	"BIRKELAND", "Z-PINCH", "FARADAY", "PARHELION",
	"INDUKTION", "EPHEMERIDE", "KOPPLUNG", "PLASMALAST",
]

const CATALOG := {
	CODE_RED_ID: [
		{
			"id": "code_red_manual",
			"kind": "manual",
			"title": "Rotes Operations-Handbuch",
			"short_title": "OPERATIONS-HANDBUCH",
			"front_art": "manual_cover",
			"back_art": "manual_back",
			"required_for_protection": true,
			"description": "Das geheime Einsatzhandbuch zu CODE RED. Seine Archivverweise werden zusammen mit der roten Bahnkarte gelesen.",
		},
		{
			"id": "code_red_orbit_chart",
			"kind": "chart",
			"title": "Rote Bahnkarte R-62",
			"short_title": "BAHNKARTE R-62",
			"front_art": "orbit_chart_front",
			"back_art": "orbit_chart_back",
			"required_for_protection": true,
			"description": "Gefaltete Referenzkarte mit Sektoren, Ringbahnen, Archivtafel und Kopplungsprotokoll.",
		},
	],
}


static func definitions(software_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in CATALOG.get(software_id, []):
		result.append((raw as Dictionary).duplicate(true))
	return result


static func all_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for software_id: Variant in CATALOG:
		for entry: Dictionary in definitions(str(software_id)):
			entry["software_id"] = str(software_id)
			result.append(entry)
	return result


static func definition(insert_id: String) -> Dictionary:
	for entry: Dictionary in all_definitions():
		if str(entry.get("id", "")) == insert_id:
			return entry
	return {}


static func has_software(software_id: String) -> bool:
	return CATALOG.has(software_id)


static func owns(insert_id: String) -> bool:
	return InventoryManager.count(insert_id) > 0


static func owns_any(software_id: String) -> bool:
	return definitions(software_id).any(func(entry: Dictionary) -> bool:
		return owns(str(entry.get("id", ""))))


static func owns_all_required(software_id: String) -> bool:
	var required := definitions(software_id).filter(func(entry: Dictionary) -> bool:
		return bool(entry.get("required_for_protection", false)))
	return not required.is_empty() and required.all(func(entry: Dictionary) -> bool:
		return owns(str(entry.get("id", ""))))


static func missing_required(software_id: String) -> Array[String]:
	var missing: Array[String] = []
	for entry: Dictionary in definitions(software_id):
		if bool(entry.get("required_for_protection", false)) \
				and not owns(str(entry.get("id", ""))):
			missing.append(str(entry.get("title", entry.get("id", "Beilage"))))
	return missing


static func status_text(software_id: String) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in definitions(software_id):
		parts.append("%s %s" % [str(entry.get("short_title", "BEILAGE")),
			"✓" if owns(str(entry.get("id", ""))) else "—"])
	return " · ".join(parts)


## Originale und Komplett-OVPs enthalten ihre deklarierten Beilagen. Eine Kopie
## erzeugt nie Papiermaterial. Jeder Gegenstand wird nur einmal inventarisiert.
static func grant_for_disk(disk: Disk) -> Array[String]:
	if disk == null or not has_software(disk.software_id) \
			or disk.provenance not in ["original", "original_box"]:
		return []
	return grant_all(disk.software_id)


static func grant_all(software_id: String) -> Array[String]:
	var granted: Array[String] = []
	for entry: Dictionary in definitions(software_id):
		var insert_id := str(entry.get("id", ""))
		if not insert_id.is_empty() and not owns(insert_id):
			InventoryManager.add_item(insert_id, 1)
			granted.append(insert_id)
	return granted


static func grant_kind(software_id: String, kind: String) -> Array[String]:
	var granted: Array[String] = []
	for entry: Dictionary in definitions(software_id):
		if str(entry.get("kind", "")) != kind:
			continue
		var insert_id := str(entry.get("id", ""))
		if not insert_id.is_empty() and not owns(insert_id):
			InventoryManager.add_item(insert_id, 1)
			granted.append(insert_id)
	return granted


## Savegame-Migration: Alte Versionen speicherten nur die Originaldiskette und
## leiteten Papierbeilagen implizit daraus ab. Beim ersten Laden werden sie echt.
static func reconcile_disks(disks: Array) -> Array[String]:
	var granted: Array[String] = []
	for value: Variant in disks:
		if value is Disk:
			for insert_id: String in grant_for_disk(value as Disk):
				if insert_id not in granted:
					granted.append(insert_id)
	return granted


## Eine reproduzierbare Archivtafel: Schutzfenster und Beilagenviewer koennen
## denselben Sektor/Ring/Spalte-Verweis unabhaengig auswerten.
static func code_red_keyword(sector: int, ring: int, column: int) -> String:
	var index := posmod((sector - 1) * 5 + (ring - 1) * 3 + column - 1,
		CODE_RED_WORDS.size())
	return CODE_RED_WORDS[index]
