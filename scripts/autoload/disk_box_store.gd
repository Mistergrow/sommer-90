extends RefCounted
## Mutierende Boxverwaltung inklusive Signalgabe.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")
const WorkbenchVersionCatalog := preload("res://scripts/ui/workbench_versions.gd")

## Diskette in die Box legen; false = Box voll (Klassiker-Problem!).
static func add_disk(mgr, disk: Disk) -> bool:
	return add_disks(mgr, [disk])


## Mehrdisketten-Saetze werden atomar eingelagert: entweder passen alle Teile
## in die Box oder kein Teil wird hinzugefuegt.
static func add_disks(mgr, new_disks: Array) -> bool:
	var valid: Array = new_disks.filter(func(d: Variant) -> bool: return d is Disk)
	if valid.is_empty():
		return false
	var loose_count := valid.filter(func(disk: Disk) -> bool:
		return not disk.is_boxed_package()).size()
	if not mgr.can_store_disks(loose_count):
		UIManager.toast(Loc.t("sys.disk_manager.diskettenbox_ist_voll_du_brauchst_weitere", "Die Diskettenbox ist voll! Du brauchst eine weitere Box."))
		return false
	for disk: Disk in valid:
		disk.enforce_master_color()
	mgr.disks.append_array(valid)
	for disk: Disk in valid:
		InsertCatalog.grant_for_disk(disk)
	mgr._apply_sort()
	mgr.disks_changed.emit()
	return true


static func remove_disk(mgr, disk: Disk) -> void:
	mgr.disks.erase(disk)
	mgr.disks_changed.emit()


## Mehrere physische Teile eines Satzes oder Handelslots werden gemeinsam
## entfernt. Ein einziges Signal verhindert Zwischenzustaende, in denen die UI
## kurz einen halben Mehrdisketten-Satz anzeigt.
static func remove_disks(mgr, removals: Array) -> void:
	var changed := false
	for candidate: Variant in removals:
		if candidate is Disk and candidate in mgr.disks:
			mgr.disks.erase(candidate)
			changed = true
	if changed:
		mgr.disks_changed.emit()


## Jedem gekauften Amiga beziehungsweise OS-Upgrade liegt sein originales
## Systemmedium bei. Die Migration ist idempotent: alte Spielstaende bekommen
## fehlende Bundles genau einmal, vorhandene oder selbst beschriftete Medien
## werden nicht veraendert.
static func ensure_bundled_system_media(mgr, hardware_id := "") -> Array:
	var hardware_ids: Array = [hardware_id] if not hardware_id.is_empty() else [
		"computer_amiga_600", "computer_amiga_1200", "amigaos_31_upgrade"]
	var granted: Array = []
	for owned_id: String in hardware_ids:
		if not PlayerStats.has_hardware(owned_id):
			continue
		for template_id: String in WorkbenchVersionCatalog.bundled_templates(owned_id):
			if template_id.is_empty() or mgr.has_template(template_id):
				continue
			var disk: Disk = mgr.create_disk(template_id,
				"Originales Systemmedium aus dem Hardwarepaket, %s" % TimeManager.date_string())
			if disk == null:
				continue
			disk.condition = 100
			disk.checked = true
			disk.write_protected = true
			disk.provenance = "original"
			mgr.disks.append(disk)
			granted.append(disk)
	if not granted.is_empty():
		mgr._apply_sort()
		mgr.disks_changed.emit()
	return granted


## Physischer Schreibschutz-Schieber. Nur echte Originale/OVPs besitzen einen
## unverrückbaren Archiv-Lock; alle Kopien (auch eigene Release-Master) dürfen
## bewusst umgeschaltet und wiederverwendet werden.
static func set_write_protected(mgr, disk: Disk, protected: bool) -> Dictionary:
	if disk == null or disk not in mgr.disks:
		return {"ok": false, "text": Loc.t("sys.disk_manager.keine_diskette_eingelegt", "Keine Diskette eingelegt.")}
	if disk.is_boxed_package():
		return {"ok": false, "text": Loc.t("sys.disk_manager.disketten_werden_als_kompletter_satz_in", "Die Disketten werden als kompletter Satz in der OVP-Vitrine verwahrt.")}
	var quest_gate: Dictionary = QuestManager.disk_requirement(disk)
	if not protected and bool(quest_gate.get("required", false)):
		return {"ok": false, "text": str(quest_gate.get("text",
			"Diese Auftragsdiskette muss schreibgeschützt bleiben."))}
	if disk.format_locked():
		disk.write_protected = true
		return {"ok": false, "text": Loc.t("sys.disk_manager.original_lock_echte_originale_ovps_bleiben", "ORIGINAL-LOCK: Echte Originale und OVPs bleiben schreibgeschützt.")}
	disk.write_protected = protected
	mgr.disks_changed.emit()
	return {"ok": true, "text": "Schreibschutz %s." % ("geschlossen" if protected else "geöffnet")}


## Formatiert das vorhandene physische Medium zu einer leeren blauen DD-Disk.
## UID, Alter und Besitzerhistorie bleiben erhalten; sämtliche Inhalts-/Release-
## Metadaten werden atomar entfernt. Formatieren repariert keinen Medienschaden.
static func format_disk(mgr, disk: Disk, filesystem := "OFS", volume_name := "Empty") -> Dictionary:
	if disk == null or disk not in mgr.disks:
		return {"ok": false, "text": Loc.t("sys.disk_manager.keine_diskette_in_df0", "Keine Diskette in DF0:.")}
	if disk.is_boxed_package():
		return {"ok": false, "text": Loc.t("sys.disk_manager.ovp_archiv_kein_datentrager_wurde_aus", "OVP-ARCHIV: Kein Datenträger wurde aus dem Karton genommen.")}
	var quest_gate: Dictionary = QuestManager.disk_requirement(disk)
	if bool(quest_gate.get("required", false)):
		return {"ok": false, "text": "AUFTRAGSDISK: %s" % str(quest_gate.get("text",
			"Diese Diskette wird noch benötigt."))}
	if disk.format_locked():
		return {"ok": false, "text": Loc.t("sys.disk_manager.abbruch_echte_original_ist_archivgeschutzt_nicht", "ABBRUCH: Das echte Original ist archivgeschützt und nicht formatierbar.")}
	if disk.write_protected:
		return {"ok": false, "text": Loc.t("sys.disk_manager.disk_write_protected_offne_zuerst_den", "DISK WRITE PROTECTED — öffne zuerst den Schreibschutz-Schieber.")}
	if not PlayerStats.use_energy(5):
		return {"ok": false, "text": Loc.t("sys.disk_manager.zu_mude_fur_80_zylinder_format", "Zu müde für 80 Zylinder Format + Verify.")}
	var old_title := disk.display_name()
	AudioManager.floppy_read()
	disk.template_id = ""
	disk.label = ""
	disk.labeled = false
	disk.sticker_data = ""
	disk.brand = "NoName"
	disk.color = "blue"
	disk.dtype = "DD"
	disk.capacity_kb = 880
	disk.content_type = "leer"
	disk.content_title = ""
	disk.program_id = ""
	disk.boot_mode = ""
	disk.rarity = "common"
	disk.checked = true
	disk.virus = false
	disk.notes = "Frisch formatiert: 80 Zylinder · 880 KB · Verify OK."
	disk.software_id = ""
	disk.software_set_id = ""
	disk.disk_number = 1
	disk.disk_count = 1
	disk.provenance = "copy"
	disk.package_condition = ""
	disk.copy_generation = 0
	disk.source_uid = ""
	disk.source_provenance = ""
	disk.patch_state = "none"
	disk.patch_seed = 0
	disk.patch_draft = {}
	disk.patch_score = 0
	disk.patch_stability = 0
	disk.cracktro = false
	disk.cracktro_seen = false
	disk.release_serial = ""
	disk.release_data = {}
	disk.patched_on = ""
	disk.release_role = ""
	disk.protection_revision = 0
	disk.patch_revision = 0
	disk.patch_steps = []
	disk.boot_faults = []
	disk.rescue_source_uid = ""
	disk.rescue_quality = 0
	disk.write_protected = false
	disk.filesystem = "FFS" if str(filesystem).to_upper() == "FFS" else "OFS"
	disk.volume_name = str(volume_name).strip_edges().left(30)
	if disk.volume_name.is_empty():
		disk.volume_name = "Empty"
	disk.memory = "%s · am %s formatiert" % [old_title, TimeManager.date_string()]
	mgr._apply_sort()
	mgr.disks_changed.emit()
	QuestManager.note_action("format_disk")
	return {"ok": true, "text": Loc.t("sys.disk_manager.initialize_complete_s_ist_jetzt_s", "INITIALIZE COMPLETE: »%s« ist jetzt %s: (%s), leer und blau.") % [
		old_title, disk.volume_name, disk.filesystem]}


# ------------------------------------------------------------------ Aktionen


## Für Ereignisse (Stromausfall etc.): zufällige Diskette beschädigen.
static func damage_random_disk(mgr, amount: int) -> void:
	var loose: Array = mgr.media_disks()
	if loose.is_empty():
		return
	var disk: Disk = loose.pick_random()
	disk.condition = maxi(0, disk.condition - amount)
	mgr.disks_changed.emit()


## Übernimmt eine Sortierpuzzle-Reihenfolge nur für lose Medien. Die intern
## persistierten OVP-Sätze bleiben als Vitrinenbestand unangetastet.
static func assign_media_order(mgr, order: Array) -> bool:
	var current: Array = mgr.media_disks()
	if order.size() != current.size():
		return false
	var expected := {}
	for disk: Disk in current:
		expected[disk.uid] = true
	for candidate: Variant in order:
		if not candidate is Disk or not expected.erase((candidate as Disk).uid):
			return false
	if not expected.is_empty():
		return false
	var boxed: Array = mgr.disks.filter(func(disk: Disk) -> bool: return disk.is_boxed_package())
	mgr.disks.assign(order)
	mgr.disks.append_array(boxed)
	mgr.disks_changed.emit()
	return true
