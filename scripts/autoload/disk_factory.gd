extends RefCounted
## Erzeugung von Disketten und Software-Saetzen.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

const Defs := preload("res://scripts/autoload/disk_manager_defs.gd")

## Neue Disk-Instanz aus einem Template; Zustand wird aus condition_range
## gewürfelt. memory = Erwerbs-Kontext (für den Rückblick 1999).
static func create_disk(mgr, template_id: String, memory: String = "") -> Disk:
	if not mgr.templates.has(template_id):
		push_warning("Unbekanntes Disk-Template: %s" % template_id)
		return null
	var tpl: Dictionary = mgr.templates[template_id]
	var disk := Disk.new()
	mgr._uid_counter += 1
	disk.uid = "disk_%06d" % mgr._uid_counter
	disk.template_id = template_id
	disk.label = tpl.get("label", "")
	disk.brand = tpl.get("brand", "NoName")
	disk.color = tpl.get("color", "blue")
	disk.dtype = tpl.get("type", "DD")
	disk.capacity_kb = int(tpl.get("capacity_kb", 880))
	disk.content_type = tpl.get("content_type", "leer")
	disk.content_title = tpl.get("content_title", "")
	disk.program_id = tpl.get("program_id", "")
	disk.boot_mode = tpl.get("boot", "")
	disk.rarity = tpl.get("rarity", "common")
	disk.read_error_chance = float(tpl.get("read_error_chance", 0.04))
	disk.write_error_chance = float(tpl.get("write_error_chance", 0.03))
	disk.notes = tpl.get("notes", "")
	var cond_range: Array = tpl.get("condition_range", [80, 100])
	disk.condition = randi_range(int(cond_range[0]), int(cond_range[1]))
	# Fabrikneue Leerdisketten müssen nicht erst geprüft werden.
	disk.checked = disk.content_type == "leer"
	disk.memory = memory
	disk.year_created = TimeManager.year
	_apply_calendar_identity(mgr, disk, TimeManager.month, TimeManager.year)
	disk.labeled = disk.label != ""
	# Kulturschicht: Herkunft und Software-Verweis aus dem Template
	disk.software_id = tpl.get("software_id", "")
	disk.disk_count = clampi(int(tpl.get("disk_count",
		SoftwareBible.disk_count(disk.software_id) if disk.software_id != "" else 1)), 1, 20)
	disk.disk_number = clampi(int(tpl.get("disk_number", 1)), 1, disk.disk_count)
	disk.software_set_id = str(tpl.get("software_set_id", ""))
	if disk.disk_count > 1 and disk.software_set_id.is_empty():
		disk.software_set_id = _new_software_set_id(mgr)
	disk.provenance = tpl.get("provenance", "copy")
	disk.write_protected = disk.content_type != "leer"
	disk.copy_generation = int(tpl.get("copy_generation", 0))
	disk.cracktro = bool(tpl.get("cracktro", false))
	# Vorgefertigte Cracktro-Templates stammen aus der alten Kulturschicht und
	# gelten als bereits gesehene Legacy-Releases (keine BYTEWERK-Payload nötig).
	if disk.cracktro:
		disk.patch_state = "legacy_scene"
		disk.cracktro_seen = true
		disk.release_role = "legacy"
	disk.enforce_master_color()
	return disk


## Heftdisketten sind Ausgaben, keine zeitlosen Templates. Der physische Name
## wird beim Erwerb aus dem laufenden Kalender eingefroren und bleibt danach
## unveraendert, auch wenn der Spieler in ein neues Jahr wechselt.
static func _apply_calendar_identity(_mgr, disk: Disk, issue_month: int, issue_year: int) -> void:
	if disk.template_id != Defs.COVERDISK_TEMPLATE_ID:
		return
	var month := clampi(issue_month, 1, 12)
	var year := maxi(0, issue_year)
	var edition := "%02d/%02d" % [month, year % 100]
	disk.label = "Amiga Kurier %s" % edition
	disk.content_title = "Amiga Kurier Coverdisk %s" % edition
	disk.notes = "Coverdisk der Ausgabe %s." % edition
	disk.year_created = year


## Diskette direkt aus einem Software-Bibel-Eintrag bauen (ohne disks.json-Template) —
## so werden echte Katalogspiele als Original-Ware greifbar. provenance:
## "original_box" (Komplett-OVP) | "original" (lose Original-Disk mit Druck-Label).
## Gedrucktes Label/Box-Art zieht die UI über SoftwareBible.acquisition_art().
static func create_from_software(mgr, software_id: String, provenance: String = "original", memory: String = "",
		disk_number: int = 1, software_set_id: String = "") -> Disk:
	var e: Dictionary = SoftwareBible.entry(software_id)
	if e.is_empty():
		push_warning("create_from_software: unbekannte software_id %s" % software_id)
		return null
	var disk := Disk.new()
	mgr._uid_counter += 1
	disk.uid = "disk_%06d" % mgr._uid_counter
	disk.template_id = ""
	disk.software_id = software_id
	disk.disk_count = SoftwareBible.disk_count(software_id)
	disk.disk_number = clampi(disk_number, 1, disk.disk_count)
	disk.software_set_id = software_set_id if not software_set_id.is_empty() else _new_software_set_id(mgr)
	disk.provenance = provenance
	disk.write_protected = true
	disk.content_type = "spiel"
	disk.content_title = str(e.get("display_name", e.get("historical_name", "Spiel")))
	disk.label = disk.content_title           # Original trägt ein echtes Etikett
	disk.labeled = true
	disk.brand = "Original"
	disk.color = "red"
	disk.dtype = "DD"
	disk.capacity_kb = 880
	disk.rarity = str(e.get("rarity", "uncommon"))
	disk.condition = randi_range(58, 92)       # Gebrauchtware
	disk.checked = false                        # erst zu Hause prüfen
	disk.memory = memory
	disk.year_created = int(e.get("release_year", TimeManager.year))
	disk.enforce_master_color()
	return disk


## Vollstaendigen physischen Satz eines Bibel-Titels erzeugen. Noch nicht in die
## Box legen; der Aufrufer kann dadurch Geld- und Kapazitaetspruefung atomar halten.
static func create_software_set(mgr, software_id: String, provenance: String = "original", memory: String = "") -> Array:
	if SoftwareBible.entry(software_id).is_empty():
		return []
	var result: Array = []
	var set_id := _new_software_set_id(mgr)
	for number in range(1, SoftwareBible.disk_count(software_id) + 1):
		var disk := create_from_software(mgr, software_id, provenance, memory, number, set_id)
		if disk == null:
			return []
		result.append(disk)
	return result


static func _new_software_set_id(mgr) -> String:
	mgr._set_uid_counter += 1
	return "software_set_%06d" % mgr._set_uid_counter


## Template-IDs eines Pools ("start", "flea", "shop").
static func template_ids_in_pool(mgr, pool: String) -> Array:
	var result: Array = []
	for id in mgr.templates:
		if pool in mgr.templates[id].get("pools", []):
			result.append(id)
	return result


# ------------------------------------------------------------------ Boxverwaltung
