extends Node
## VirusManager — Bootblock-Viren der Amiga-Ära als ECHTES System (Homage an
## SCA, Byte Bandit, Lamer Exterminator). Der latente `Disk.virus` bekommt Leben:
##
##  QUELLEN (bereits vorhanden): BBS-Downloads (~6 %), Kopien höherer Generation
##    (CultureManager). Diese setzen `disk.virus`.
##  VERBREITUNG: Ein residenter Bootblockvirus kann bei der taeglichen Amiga-
##    Nutzung hoechstens EINE weitere eingelegte Diskette infizieren. Medien
##    stecken einander nicht allein durch gemeinsames Lagern in der Box an.
##  DATENVERLUST (neu): alter, ungesäuberter Befall frisst die Diskette an
##    (condition sinkt; bei 0 ist sie tot) — Lamer-Exterminator-Homage.
##  FOLGE (neu): infizierte Disketten haben ein höheres Lesefehler-Risiko
##    (DiskManager.read_error_probability).
##  ERKENNEN/HEILEN (neu): der Virus-Checker prüft (setzt `checked`), zeigt den
##    Virusnamen und ENTFERNT ihn (clean → `virus=false`). Das ist die Gegenwehr.
##
## Kein eigener Speicher — arbeitet auf den (gespeicherten) Disketten. Reiner
## Zeitkolorit-Spaß, keine echten Viren.

const VIRUS_COUNT := 8
const SPREAD_CHANCE := 0.08     # ein gemeinsamer Expositionswurf pro Tag
const CORRUPT_CHANCE := 0.025   # je infizierter Disk/Tag, Datenschaden
const CORRUPT_HIT := 15         # condition-Verlust bei Datenschaden
const VIRUS_READ_PENALTY := 0.14  # zusätzliches Lesefehler-Risiko infizierter Disks
const SCARE_TASK_ID := "task_viruscheck_real"
const SCARE_UID_FLAG := "virus_scare_disk_uid"
const SCARE_STARTED_FLAG := "virus_scare_event_started"
const SCARE_PENDING_FLAG := "virus_scare_pending"
const SCARE_SCANNED_FLAG := "virus_scare_scan_completed"

signal virus_activity(spread: int, killed: int)


func _ready() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(_on_day_changed)


## Stabiler Virusname je Diskette (aus der uid abgeleitet — kein neues Feld nötig).
func virus_name(disk) -> String:
	var index := 0 if disk == null else absi(hash(str(disk.uid))) % VIRUS_COUNT
	match index:
		0: return Loc.t("sys.virus_manager.virus_sca_worm", "SCA-Wurm")
		1: return Loc.t("sys.virus_manager.virus_byte_bandit", "Byte-Bandit")
		2: return Loc.t("sys.virus_manager.virus_lamer_scare", "Lamer-Schreck")
		3: return Loc.t("sys.virus_manager.virus_boot_ghost", "Boot-Gespenst")
		4: return Loc.t("sys.virus_manager.virus_track_thief", "Track-Dieb")
		5: return Loc.t("sys.virus_manager.virus_disk_moth", "Disketten-Motte")
		6: return Loc.t("sys.virus_manager.virus_copy_devil", "Kopier-Teufel")
		_: return Loc.t("sys.virus_manager.virus_guru_ghost", "Guru-Geist")


func is_infected(disk) -> bool:
	return disk != null and bool(disk.virus)


## SCA-Homage: der berüchtigte Bootblock-Gruß beim Auffliegen.
func reveal_line(disk) -> String:
	return Loc.t("sys.virus_manager.reveal_line", "»Something wonderful has happened — dein Amiga lebt!« … von wegen: der %s hockt im Bootblock.") % virus_name(disk)


func infect(disk) -> void:
	if disk != null and not disk.is_boxed_package() and not disk.virus:
		disk.virus = true


## Materialisiert das Zufallsereignis „Virus-Verdacht“ an genau EINEM physischen
## Medium. Vorher existierte nur eine Notiz ohne Ziel; dadurch konnte kein Scan
## sie je abschließen. Quest-/Originalquellen werden nach Möglichkeit geschont.
func arm_scare_disk() -> Disk:
	var candidates := _scare_candidates()
	if candidates.is_empty():
		return null
	var disk: Disk = candidates.pick_random()
	disk.virus = true
	disk.checked = false
	var marker := Loc.t("sys.virus_manager.suspicion_marker", "Virus-Verdacht am %s") % TimeManager.date_string()
	if marker not in disk.memory:
		disk.memory += ("" if disk.memory.is_empty() else " · ") + marker
	GameManager.flags[SCARE_UID_FLAG] = disk.uid
	GameManager.flags[SCARE_STARTED_FLAG] = true
	GameManager.flags[SCARE_PENDING_FLAG] = true
	GameManager.flags[SCARE_SCANNED_FLAG] = false
	DiskManager.disks_changed.emit()
	return disk


func can_arm_scare_disk() -> bool:
	return not _scare_candidates().is_empty()


## Der Scanner meldet jede tatsächlich gelesene Diskette hier an. Nur die
## gebundene Ereignis-Diskette schließt die konkrete Aufgabe; Alex' separate
## 1992-Quest behält weiterhin ihren eigenen UID-Vertrag.
func note_disk_scanned(disk: Disk) -> bool:
	if disk == null or disk not in DiskManager.disks or disk.is_boxed_package() \
			or disk.condition <= 0 or not TaskManager.is_open(SCARE_TASK_ID):
		return false
	var target_uid := str(GameManager.flags.get(SCARE_UID_FLAG, ""))
	if target_uid.is_empty() or str(disk.uid) != target_uid:
		return false
	_complete_scare_task()
	return true


## Ein vollständiger „ALLE PRÜFEN“-Lauf ist für alte Saves der belastbare
## Abschlussbeleg: Diese Versionen besaßen noch keine Ziel-UID. Ein Nullfund ist
## dabei ein gültiges Prüfergebnis und darf die Aufgabe nicht endlos offenhalten.
func finish_full_scan() -> bool:
	if not TaskManager.is_open(SCARE_TASK_ID):
		return false
	# Neue Aufgaben besitzen eine UID. Deren Abschluss wird ausschließlich von
	# note_disk_scanned() bestätigt — `checked` kann auch durch DF0/X-COPY gesetzt
	# worden sein und ist deshalb kein belastbarer Virenwächter-Nachweis.
	var target_uid := str(GameManager.flags.get(SCARE_UID_FLAG, ""))
	if not target_uid.is_empty():
		return false
	var media := _scannable_media()
	if media.is_empty() or media.any(func(d: Disk) -> bool: return not d.checked):
		return false
	_complete_scare_task()
	return true


## Lade-/Hotreload-Reparatur:
## - bereits komplett geprüfte Legacy-Saves werden ohne neuen Virus abgehakt;
## - ein noch ungescannter Altauftrag erhält jetzt ein echtes, markiertes Ziel;
## - eine verlorene Ziel-Diskette wird ersetzt, statt den Spielstand zu blockieren.
func reconcile_scare_task() -> bool:
	if not TaskManager.is_open(SCARE_TASK_ID):
		return false
	TaskManager.update_task_text(SCARE_TASK_ID,
		Loc.t("sys.virus_manager.scare_task_title", "Verdächtige Diskette wirklich prüfen"),
		Loc.t("sys.virus_manager.scare_task_note", "Amiga einschalten, Werkbank-Disk booten → Shell doppelklicken → VIRUSCHECKER eingeben → die gelb markierte Auftragsdiskette anklicken."))
	TaskManager.bind_disk_requirement(SCARE_TASK_ID, SCARE_UID_FLAG,
		Loc.t("sys.virus_manager.scare_protect_text", "Diese verdächtige Diskette muss erst im Virenwächter geprüft werden."))
	var target_uid := str(GameManager.flags.get(SCARE_UID_FLAG, ""))
	var target := scare_disk()
	if target != null:
		# `checked` allein beweist keinen Scan im Virenwächter. Das Medium bleibt
		# gebunden und sichtbar, bis der Checker genau diese UID meldet.
		target.virus = true
		GameManager.flags[SCARE_STARTED_FLAG] = true
		GameManager.flags[SCARE_PENDING_FLAG] = true
		GameManager.flags[SCARE_SCANNED_FLAG] = false
		return false
	# Eine vorhandene, aber verlorene/zerstörte Ziel-UID ist kein Legacy-Save:
	# Ersatz binden, statt den Auftrag aufgrund anderer geprüfter Medien abzuhaken.
	if not target_uid.is_empty():
		GameManager.flags.erase(SCARE_UID_FLAG)
		return arm_scare_disk() != null
	var media := _scannable_media()
	if not media.is_empty() and media.all(func(d: Disk) -> bool: return d.checked):
		_complete_scare_task()
		return true
	return arm_scare_disk() != null


func scare_disk() -> Disk:
	var target_uid := str(GameManager.flags.get(SCARE_UID_FLAG, ""))
	if target_uid.is_empty():
		return null
	for disk: Disk in DiskManager.media_disks():
		if disk.uid == target_uid and disk.condition > 0:
			return disk
	return null


func is_scare_disk(disk: Disk) -> bool:
	return disk != null and TaskManager.is_open(SCARE_TASK_ID) \
		and str(disk.uid) == str(GameManager.flags.get(SCARE_UID_FLAG, ""))


func _complete_scare_task() -> void:
	TaskManager.complete(SCARE_TASK_ID)
	GameManager.flags[SCARE_STARTED_FLAG] = true
	GameManager.flags[SCARE_PENDING_FLAG] = false
	GameManager.flags[SCARE_SCANNED_FLAG] = true


func _scannable_media() -> Array[Disk]:
	var media: Array[Disk] = []
	for disk: Disk in DiskManager.media_disks():
		if disk.condition > 0:
			media.append(disk)
	return media


func _scare_candidates() -> Array[Disk]:
	var media := _scannable_media()
	if media.is_empty():
		return media
	# Bevorzugt wird echte Tauschware: keine Rohlinge, System-/Programmdisks,
	# Originale, Spielmaster oder aktuell benötigte Questgegenstände.
	var safe := media.filter(func(disk: Disk) -> bool:
		return disk.content_type not in ["leer", "system"] \
			and disk.program_id.is_empty() \
			and not disk.format_locked() \
			and not disk.is_game_master() \
			and not bool(QuestManager.disk_requirement(disk).get("required", false)))
	if not safe.is_empty():
		return safe
	# Defensive Rückfallebene für ungewöhnliche/alte Inventare. Ein lösbarer
	# Auftrag ist wichtiger als die Präferenz, Kernmedien bleiben aber tabu,
	# solange irgendein anderes belegtes Medium existiert.
	var occupied := media.filter(func(disk: Disk) -> bool:
		return disk.content_type != "leer" \
			and not bool(QuestManager.disk_requirement(disk).get("required", false)))
	return occupied if not occupied.is_empty() else media


## Virus entfernen (Bootblock neu schreiben). Setzt zugleich checked=true.
func clean(disk) -> bool:
	if disk == null or disk.is_boxed_package() or not disk.virus:
		return false
	disk.virus = false
	disk.checked = true
	var am := get_node_or_null("/root/AchievementManager")
	if am != null:
		am.call("note", "cleaned_virus")
	DiskManager.disks_changed.emit()
	return true


func infected_disks() -> Array:
	return DiskManager.media_disks().filter(func(d) -> bool: return bool(d.virus))


## Zusätzliches Lesefehler-Risiko (DiskManager fragt das ab).
func read_penalty(disk) -> float:
	return VIRUS_READ_PENALTY if is_infected(disk) else 0.0


# ------------------------------------------------- Verbreitung & Datenverlust

func _on_day_changed() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	var disks: Array = DiskManager.media_disks()
	var infected := disks.filter(func(d) -> bool: return bool(d.virus))
	if infected.is_empty():
		return
	var spread := 0
	var killed := 0
	# Disketten stecken einander nicht magisch im Kasten an. Der Tageswurf steht
	# fuer eine unbemerkte gemeinsame Amiga-Sitzung mit residentem Bootblockvirus;
	# hoechstens EIN neues Medium wird dadurch pro Tag infiziert.
	if randf() < SPREAD_CHANCE:
		var pool := disks.filter(func(x) -> bool: return not bool(x.virus))
		if not pool.is_empty():
			var victim = pool[randi() % pool.size()]
			victim.virus = true
			spread = 1
	for d in infected:
		# Datenverlust: alter Befall frisst die Diskette an.
		if randf() < CORRUPT_CHANCE and int(d.condition) > 0:
			d.condition = maxi(0, int(d.condition) - CORRUPT_HIT)
			if int(d.condition) <= 0:
				killed += 1
	if spread > 0 or killed > 0:
		DiskManager.disks_changed.emit()
		var parts: Array = []
		if spread > 0:
			parts.append(Loc.t("sys.virus_manager.spread_alert", "ein Bootblock-Virus breitet sich in deiner Box aus"))
		if killed > 0:
			parts.append(Loc.t_plural("sys.virus_manager.destroyed_disks",
				"%d Diskette ist ihm erlegen", "%d Disketten sind ihm erlegen", killed) % killed)
		UIManager.toast(Loc.t("sys.virus_manager.virenalarm_s_ran_an_den_virus", "⚠ Virenalarm: %s. Ran an den Virus-Checker!") % " — ".join(parts))
	virus_activity.emit(spread, killed)


func reset() -> void:
	pass
