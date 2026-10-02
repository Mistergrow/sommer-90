extends RefCounted
## Alterung, Speichern und Laden samt Save-Migrationen.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")

static func _age_collection(mgr, days: int) -> void:
	if days <= 0:
		return
	for disk in mgr.disks:
		if disk.condition > 0:
			CultureManager.age_disk(disk, days)
	mgr.disks_changed.emit()


static func to_dict(mgr) -> Dictionary:
	return {
		"uid_counter": mgr._uid_counter,
		"set_uid_counter": mgr._set_uid_counter,
		"sort_mode": mgr.sort_mode,
		"disks": mgr.disks.map(func(d: Disk) -> Dictionary: return d.to_dict()),
	}


static func from_dict(mgr, d: Dictionary) -> void:
	mgr._load_data()
	mgr._uid_counter = maxi(0, int(d.get("uid_counter", 0)))
	mgr._set_uid_counter = maxi(0, int(d.get("set_uid_counter", 0)))
	# Alte Saves haben keine Zaehler; unterbrochene Saves koennen zurueckliegen.
	# Vor jeder Migration zuerst ALLE existierenden Kennungen reservieren. Sonst
	# bekommt eine ergaenzte Diskette die UID eines spaeter geladenen Originals,
	# und gespeicherte Quest-/Quellverweise zeigen auf die falsche Diskette.
	for disk_data: Dictionary in d.get("disks", []):
		mgr._uid_counter = maxi(mgr._uid_counter,
			_id_serial(str(disk_data.get("uid", "")), "disk_"))
		mgr._set_uid_counter = maxi(mgr._set_uid_counter,
			_id_serial(str(disk_data.get("software_set_id", "")), "software_set_"))
	mgr.sort_mode = int(d.get("sort_mode", 0))
	mgr.disks = []
	for disk_data in d.get("disks", []):
		var disk := Disk.from_dict(disk_data)
		mgr._repair_legacy_catalog_identity(disk)
		_repair_old_bytewerk_migration(mgr, disk)
		# Alte Saves repraesentierten auch Mehrdiskettenspiele als genau ein Objekt.
		# Beim ersten Laden wird daraus verlustfrei ein vollstaendiger physischer Satz.
		var legacy_multidisk := not (disk_data as Dictionary).has("disk_count") \
			and disk.software_id != "" and disk.content_type == "spiel" \
			and SoftwareBible.disk_count(disk.software_id) > 1
		if legacy_multidisk:
			var expected := SoftwareBible.disk_count(disk.software_id)
			var set_id: String = mgr._new_software_set_id()
			disk.disk_count = expected
			disk.disk_number = 1
			disk.software_set_id = set_id
			mgr.disks.append(disk)
			for number in range(2, expected + 1):
				var sibling := Disk.from_dict(disk.to_dict())
				mgr._uid_counter += 1
				sibling.uid = "disk_%06d" % mgr._uid_counter
				sibling.disk_number = number
				sibling.memory = disk.memory + (" · Aus altem Spielstand als Diskette %d/%d ergänzt." % [number, expected])
				mgr.disks.append(sibling)
		else:
			if disk.disk_count > 1 and disk.software_set_id.is_empty():
				disk.software_set_id = mgr._new_software_set_id()
			mgr.disks.append(disk)
	_ensure_unique_disk_uids(mgr)
	mgr._apply_sort()
	InsertCatalog.reconcile_disks(mgr.disks)
	# Save-Migration fuer bereits gekaufte A600/A1200 und das 3.1-Kit.
	mgr.ensure_bundled_system_media()
	mgr.disks_changed.emit()


static func _id_serial(id: String, prefix: String) -> int:
	if not id.begins_with(prefix):
		return 0
	var suffix := id.trim_prefix(prefix)
	return maxi(0, int(suffix)) if suffix.is_valid_int() else 0


## Alte oder manipulierte Saves koennen leere/doppelte UIDs tragen. Da die UID
## der letzte stabile Sortier-Tie-Breaker ist, wird sie beim Laden einmalig und
## verlustfrei repariert, bevor irgendeine kanonische Ordnung berechnet wird.
static func _ensure_unique_disk_uids(mgr) -> void:
	var seen := {}
	for disk: Disk in mgr.disks:
		if disk.uid.is_empty() or seen.has(disk.uid):
			mgr._uid_counter += 1
			var candidate := "disk_%06d" % mgr._uid_counter
			while seen.has(candidate):
				mgr._uid_counter += 1
				candidate = "disk_%06d" % mgr._uid_counter
			disk.uid = candidate
		seen[disk.uid] = true


## Eine frühere Migration hatte alle geschützten Gen-1-Kopien beim Laden
## pauschal zu BYTEWERK-Arbeitskopien erklärt. Nur diese eindeutig markierten
## Altlasten werden zurückgesetzt. Echte Arbeitskopien tragen als Quelle
## original/original_box und bleiben vollständig erhalten.
static func _repair_old_bytewerk_migration(_mgr, disk: Disk) -> void:
	if disk.patch_state == "bare" and disk.source_provenance == "legacy_unknown" \
			and disk.release_role == "work_copy":
		disk.patch_state = "none"
		disk.source_provenance = ""
		disk.release_role = ""
		disk.enforce_master_color()
