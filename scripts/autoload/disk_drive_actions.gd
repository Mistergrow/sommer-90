extends RefCounted
## Laufwerks- und Energieaktionen mit Risikomodell.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

const Defs := preload("res://scripts/autoload/disk_manager_defs.gd")
const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")
const DiskDiagnostics := preload("res://scripts/data/disk_diagnostics.gd")

static func _drive_dirt(_mgr) -> float:
	return PlayerStats.drive_dirt()


static func _drive_misalignment(_mgr) -> float:
	return 1.0 - PlayerStats.drive_alignment()


static func _has_ext_drive(_mgr) -> bool:
	return PlayerStats.has_hardware("external_drive")


## GDD „Hardware-Ausbaustufe → schnellere/sicherere Disk-Aktionen": RAM & Ausbau
## senken die Energiekosten je Aktion (nie unter 3). Das externe Laufwerk
## wirkt zusätzlich wie bisher über die _EXT-Konstanten.
static func _action_cost(_mgr, base: int) -> int:
	return maxi(3, base - int(PlayerStats.hardware_level() / 2.0))


## GDD-Gegenstück „sicherer": jede Ausbaustufe NACH der serienmäßigen Stufe 1
## senkt die Fehlerchance um 4 % relativ, gedeckelt bei 50 % des Basiswerts.
## Dadurch ist der nackte A500 die nachvollziehbare 100-%-Basis und die erste
## A501-Aufrüstung wirkt sofort.
static func _level_error_factor(_mgr) -> float:
	return clampf(1.0 - 0.04 * float(maxi(0, PlayerStats.hardware_level() - 1)), 0.5, 1.0)


## Effektive Lesefehler-Wahrscheinlichkeit für eine Diskette. Diese zentrale
## Formel wird auch vom Wartungs-UI für nachvollziehbare Risikowerte genutzt.
static func read_error_probability(mgr, disk: Disk) -> float:
	var chance := disk.read_error_chance + _drive_dirt(mgr) * Defs.READ_DIRT_ERROR_FACTOR
	chance += _drive_misalignment(mgr) * Defs.READ_ALIGNMENT_ERROR_FACTOR
	chance += (1.0 - float(disk.condition) / 100.0) * 0.15
	if disk.virus:
		chance += VirusManager.VIRUS_READ_PENALTY   # Bootblock-Virus stört das Lesen
	if _has_ext_drive(mgr):
		chance *= Defs.EXT_DRIVE_ERROR_FACTOR
	return chance * _level_error_factor(mgr)


## Effektive Schreibfehler-Wahrscheinlichkeit der Zieldiskette.
static func write_error_probability(mgr, disk: Disk) -> float:
	var chance := disk.write_error_chance + _drive_dirt(mgr) * Defs.WRITE_DIRT_ERROR_FACTOR
	chance += _drive_misalignment(mgr) * Defs.WRITE_ALIGNMENT_ERROR_FACTOR
	if _has_ext_drive(mgr):
		chance *= Defs.EXT_DRIVE_ERROR_FACTOR
	return chance * _level_error_factor(mgr)


## Diskette prüfen: deckt den Zustand auf. Risiko eines Read Errors,
## der den Zustand beschädigt. Rückgabe: {ok: bool, text: String}.
static func check_disk(mgr, disk: Disk) -> Dictionary:
	if not mgr.is_loose_media(disk):
		return {"ok": false, "code": "sealed", "error_tracks": [],
			"text": Loc.t("sys.disk_manager.ovp_versiegelt_diese_diskette_ist_nicht", "OVP VERSIEGELT: Diese Diskette ist nicht ausgepackt.")}
	var cost := _action_cost(mgr, Defs.ENERGY_CHECK_EXT if _has_ext_drive(mgr) else Defs.ENERGY_CHECK)
	if not PlayerStats.use_energy(cost):
		return {"ok": false, "code": "no_energy", "error_tracks": [],
			"text": Loc.t("sys.disk_manager.zu_mude_erst_schlafen_oder_essen", "Zu müde. Erst schlafen oder essen.")}
	AudioManager.floppy_read()  # Laufwerk rattert beim Prüfen
	disk.checked = true
	var physical := DiskDiagnostics.inspect(disk, true)
	# Ein Medium mit 0 % kann nie per Zufallswurf zu „Verify ok" werden. Das war
	# die Ursache fuer den Widerspruch zwischen Virenwaechter und X-COPY.
	if not bool(physical.get("readable", false)):
		mgr.disks_changed.emit()
		return {"ok": false, "code": str(physical.get("code", "unreadable")),
			"error_tracks": physical.get("error_tracks", []),
			"physical_readable": false,
			"text": Loc.t("sys.disk_manager.read_error_track_0_unlesbar_diskette", "READ ERROR! Track 0 unlesbar... die Diskette ist hinüber.")}
	# Fehlerchance: Diskette + Laufwerksschmutz + schlechter Zustand
	var chance := read_error_probability(mgr, disk)
	if randf() < chance:
		var damage := randi_range(5, 15)
		disk.condition = maxi(0, disk.condition - damage)
		mgr.disks_changed.emit()
		if disk.condition <= 0:
			return {"ok": false, "code": "unreadable",
				"error_tracks": DiskDiagnostics.error_tracks(disk, "unreadable"),
				"physical_readable": false,
				"text": Loc.t("sys.disk_manager.read_error_track_0_unlesbar_diskette", "READ ERROR! Track 0 unlesbar... die Diskette ist hinüber.")}
		return {"ok": false, "code": "crc_error",
			"error_tracks": DiskDiagnostics.error_tracks(disk, "crc_error"),
			"physical_readable": true,
			"text": "CRC ERROR beim Lesen! Zustand verschlechtert (-%d%%)." % damage}
	mgr.disks_changed.emit()
	# Mystery-Disketten offenbaren beim ersten erfolgreichen Prüfen ihren Inhalt.
	if disk.content_type == "mystery":
		var reveal := _reveal_mystery(mgr, disk)
		reveal["code"] = "track_ok"
		reveal["error_tracks"] = []
		reveal["physical_readable"] = true
		reveal["virus_known"] = bool(disk.virus)
		return reveal
	return {"ok": true, "code": "track_ok", "error_tracks": [],
		"physical_readable": true, "virus_known": bool(disk.virus),
		"text": DiskDiagnostics.track_verify_text(disk, bool(disk.virus))}


## Unbeschriftete Disketten: beim Prüfen zeigt sich, was wirklich drauf ist.
static func _reveal_mystery(mgr, disk: Disk) -> Dictionary:
	var pool: Array = mgr.template_ids_in_pool("flea").filter(func(id: String) -> bool: return id != "mystery_unlabeled")
	if pool.is_empty():
		return {"ok": true, "text": Loc.t("sys.disk_manager.diskette_ist_leer_wie_enttauschend", "Die Diskette ist... leer. Wie enttäuschend.")}
	var tpl: Dictionary = mgr.templates[pool.pick_random()]
	disk.content_type = tpl.get("content_type", "tools")
	disk.content_title = tpl.get("content_title", "???")
	disk.rarity = tpl.get("rarity", "common")
	mgr.disks_changed.emit()
	return {"ok": true, "text": Loc.t("sys.disk_manager.uberraschung_auf_diskette_ist_s", "Überraschung! Auf der Diskette ist: %s") % disk.content_title}


## Etikett aufkleben/beschriften. Mit Etikettenvorrat gibt es den Wert-Bonus,
## ohne wird improvisiert (Filzstift direkt aufs Gehäuse).
static func label_disk(mgr, disk: Disk, text: String) -> Dictionary:
	if not mgr.is_loose_media(disk):
		return {"ok": false, "text": Loc.t("sys.disk_manager.versiegelte_ovp_bleibt_unangetastet_in_vitrine", "Die versiegelte OVP bleibt unangetastet in der Vitrine.")}
	disk.label = text.strip_edges()
	if disk.label != "":
		disk.label_quality = maxi(disk.label_quality, 1)
		disk.labeled = true
		MemoryManager.record_once("first_disk_label")   # Meilenstein: erstes eigenes Etikett
	if InventoryManager.consume("etiketten", 1):
		disk.labeled = true
		mgr.disks_changed.emit()
		return {"ok": true, "text": Loc.t("sys.disk_manager.etikett_sauber_beschriftet_aufgeklebt", "Etikett sauber beschriftet und aufgeklebt.")}
	mgr.disks_changed.emit()
	return {"ok": true, "text": Loc.t("sys.disk_manager.keine_etiketten_mehr_mit_filzstift_aufs", "Keine Etiketten mehr — mit Filzstift aufs Gehäuse geschrieben.")}


## Sicherheitskopie: Inhalt einer eigenen Diskette auf eine Leerdiskette
## sichern (historische Archivierungs-Mechanik). Write-Error-Risiko!
static func backup_disk(mgr, source: Disk, blank: Disk) -> Dictionary:
	if not mgr.is_loose_media(source) or not mgr.is_loose_media(blank):
		return {"ok": false, "text": Loc.t("sys.disk_manager.nur_lose_disketten_konnen_in_laufwerk", "Nur lose Disketten können in ein Laufwerk eingelegt werden.")}
	if source.content_type == "leer":
		return {"ok": false, "text": Loc.t("sys.disk_manager.da_ist_nichts_drauf_man_sichern", "Da ist nichts drauf, das man sichern könnte.")}
	if blank.content_type != "leer":
		return {"ok": false, "text": Loc.t("sys.disk_manager.zieldiskette_ist_nicht_leer", "Die Zieldiskette ist nicht leer!")}
	var cost := _action_cost(mgr, Defs.ENERGY_BACKUP_EXT if _has_ext_drive(mgr) else Defs.ENERGY_BACKUP)
	if not PlayerStats.use_energy(cost):
		return {"ok": false, "text": Loc.t("sys.disk_manager.zu_mude_fur_saubere_kopie", "Zu müde für eine saubere Kopie.")}
	AudioManager.floppy_insert()
	AudioManager.floppy_read()
	var chance := write_error_probability(mgr, blank)
	if randf() < chance:
		blank.condition = maxi(0, blank.condition - 20)
		mgr.disks_changed.emit()
		return {"ok": false, "text": Loc.t("sys.disk_manager.write_error_auf_track_d_leerdiskette", "WRITE ERROR auf Track %d! Die Leerdiskette hat gelitten.") % randi_range(1, 79)}
	# Ein Spiel-Backup mit Software-ID darf den Kultur-/Kopierschutzstatus nicht
	# verlieren. Es folgt deshalb denselben Regeln wie jede andere Kopie. So kann
	# weder der alte Backup-Dialog noch X-COPY eine nackte geschützte Kopie als
	# scheinbar ungeschützte Disk erzeugen.
	if source.software_id != "":
		CultureManager.copy_rules(source, blank)
	else:
		blank.content_type = source.content_type
		blank.content_title = source.content_title
		blank.rarity = source.rarity
		blank.program_id = source.program_id   # Backup einer Programm-Disk bleibt lauffähig/bootbar
		blank.boot_mode = source.boot_mode
	# Auch einfache Daten-/Musikdisks tragen den exakten Herkunftsbeleg. Das ist
	# fuer benannte Backup-Auftraege und drei verschiedene Archivquellen noetig.
	blank.source_uid = source.uid
	blank.source_provenance = source.provenance
	blank.label = "Backup: %s" % source.display_name()
	blank.checked = true
	blank.memory = "Sicherheitskopie, angelegt am %s" % TimeManager.date_string()
	blank.archive_backup_day = TimeManager.day_counter
	mgr._apply_sort()
	mgr.disks_changed.emit()
	TaskManager.note_action("backup_disk", {
		"day": blank.archive_backup_day,
		"disk_uid": blank.uid,
		"source_uid": source.uid,
	})
	QuestManager.note_action("backup_disk", 1, {
		"source_uid": source.uid,
		"target_uid": blank.uid,
	})
	# Y2K-Vorsorge (q_y2k_prep, 1999): ein Backup IST die Vorsorge-Handlung.
	# note_action zaehlt nur fuer die gerade aktive Stufe — vorher verpufft es.
	QuestManager.note_action("y2k_backup", 1, {
		"source_uid": source.uid,
		"target_uid": blank.uid,
	})
	return {"ok": true, "text": "Backup fertig. Rattern, klackern, Verify ok!"}


## Kopieren nach Kulturregeln (docs/KULTUR_LAYER.md): Generationen-Kette,
## Lesefehler-Zuwachs, Virusrisiko, Cracktro-Vererbung. Der Alltag der Ära —
## mit den authentischen Nachteilen gegenüber dem Original.
static func copy_disk(mgr, source: Disk, blank: Disk) -> Dictionary:
	if not mgr.is_loose_media(source) or not mgr.is_loose_media(blank):
		return {"ok": false, "text": Loc.t("sys.disk_manager.nur_lose_disketten_konnen_mit_x", "Nur lose Disketten können mit X-COPY bearbeitet werden.")}
	if source.content_type == "leer":
		return {"ok": false, "text": Loc.t("sys.disk_manager.da_ist_nichts_drauf_man_kopieren", "Da ist nichts drauf, das man kopieren könnte.")}
	if blank.content_type != "leer":
		return {"ok": false, "text": Loc.t("sys.disk_manager.zieldiskette_ist_nicht_leer", "Die Zieldiskette ist nicht leer!")}
	var cost := _action_cost(mgr, Defs.ENERGY_BACKUP_EXT if _has_ext_drive(mgr) else Defs.ENERGY_BACKUP)
	if not PlayerStats.use_energy(cost):
		return {"ok": false, "text": Loc.t("sys.disk_manager.zu_mude_fur_saubere_kopie", "Zu müde für eine saubere Kopie.")}
	AudioManager.floppy_insert()
	AudioManager.floppy_read()
	var chance := write_error_probability(mgr, blank)
	if randf() < chance:
		blank.condition = maxi(0, blank.condition - 20)
		mgr.disks_changed.emit()
		return {"ok": false, "text": Loc.t("sys.disk_manager.write_error_auf_track_d_leerdiskette", "WRITE ERROR auf Track %d! Die Leerdiskette hat gelitten.") % randi_range(1, 79)}
	var tutorial_space_copy := QuestManager.is_active("q_stefan_space") \
		and QuestManager.stage("q_stefan_space") == 1 \
		and source.software_id == "space_lemming_trouble" and source.is_game_master()
	var result: Dictionary = CultureManager.copy_rules(source, blank)
	blank.label = ""
	blank.labeled = false  # frisch kopiert = unbeschriftet (Etikett-Ritual!)
	blank.memory = "Kopie von „%s“, %s" % [source.display_name(), TimeManager.date_string()]
	mgr._apply_sort()
	mgr.disks_changed.emit()
	MemoryManager.record_once("first_copy")   # Meilenstein: erste eigene Kopie
	QuestManager.note_action("make_copy")
	# Besitz-Ziele reagieren sofort; note_action wertet nur aktionsbasierte Ziele.
	QuestManager.evaluate()
	return {"ok": true, "text": result["text"] + "  Rattern, klackern, Verify ok.",
		"tutorial_space_copy": tutorial_space_copy}


## Diskette „starten“: das Kopierschutz-Erlebnis der Ära. Liefert den
## Ablauf fürs UI: direct / cracktro / abfrage / blocked (Demomodus).
static func play_disk(mgr, disk: Disk) -> Dictionary:
	if not mgr.is_loose_media(disk):
		return {"ok": false, "flow": "none",
			"text": Loc.t("sys.disk_manager.ovp_ist_versiegelt_ihre_disketten_befinden", "Die OVP ist versiegelt. Ihre Disketten befinden sich nicht in der Diskettenbox.")}
	if disk.condition <= 0:
		return {"ok": false, "flow": "none", "text": Loc.t("sys.disk_manager.diskette_ist_defekt_da_startet_nichts", "Die Diskette ist defekt — da startet nichts mehr.")}
	if disk.content_type == "leer":
		return {"ok": false, "flow": "none", "text": Loc.t("sys.disk_manager.leerdiskette_bootet_nicht_guru_meditation_vermieden", "Eine Leerdiskette bootet nicht. Guru Meditation vermieden.")}
	if disk.content_type == "spiel" and disk.software_id != "":
		var missing: Array[int] = mgr.missing_parts_for_disk(disk)
		if not missing.is_empty():
			var labels: Array[String] = []
			for number: int in missing:
				labels.append(str(number))
			return {"ok": false, "flow": "none", "reason": "incomplete_disk_set",
				"missing_disks": missing, "text": Loc.t("sys.disk_manager.diskettensatz_unvollstandig_es_fehlen_diskette_n", "Diskettensatz unvollständig — es fehlen Diskette(n): %s.") % ", ".join(labels)}
	if not PlayerStats.use_energy(5):
		return {"ok": false, "flow": "none", "text": Loc.t("sys.disk_manager.zu_mude_um_noch_etwas_zu", "Zu müde, um noch etwas zu starten.")}
	AudioManager.floppy_insert()
	AudioManager.floppy_read()
	var title := disk.display_name()
	var check: Dictionary = CultureManager.protection_check(disk)
	var entry: Dictionary = CultureManager.software(disk.software_id)
	if disk.memory == "":
		disk.memory = "Zum ersten Mal gestartet am %s" % TimeManager.date_string()
	if not check["ok"]:
		return {"ok": true, "flow": "blocked", "text": check["reason"], "title": title}
	if disk.cracktro and disk.provenance == CultureManager.PROVENANCE_COPY:
		return {"ok": true, "flow": "cracktro", "text": Loc.t("sys.disk_manager.du_versinkst_weile_in_s", "Du versinkst eine Weile in „%s“.") % title, "title": title}
	var protection := str(entry.get("protection", "keine"))
	if check["mode"] == "abfrage" and protection in ["handbuch", "codewheel"]:
		var has_beilagen := disk.provenance != CultureManager.PROVENANCE_COPY
		var missing_beilagen: Array[String] = []
		if InsertCatalog.has_software(disk.software_id):
			has_beilagen = InsertCatalog.owns_all_required(disk.software_id)
			missing_beilagen = InsertCatalog.missing_required(disk.software_id)
		return {"ok": true, "flow": "abfrage", "protection": protection,
			"has_beilagen": has_beilagen, "missing_beilagen": missing_beilagen,
			"text": Loc.t("sys.disk_manager.du_versinkst_weile_in_s", "Du versinkst eine Weile in „%s“.") % title, "title": title}
	# Ungeschützt, Dongle steckt, o. Ä. — läuft direkt
	var prefix: String = str(check.get("reason", ""))
	if prefix != "":
		prefix += "  "
	return {"ok": true, "flow": "direct", "text": prefix + "Du versinkst eine Weile in „%s“." % title, "title": title}
