extends Node
## TaskManager — das Aufgaben-Board (To-do) + Termin-Vorschau.
##
## Aufgaben kommen aus DIALOGEN & Systemen über die Effekt-DSL
## ({"type":"task", id, title, note}) und werden per {"type":"task_done", id}
## abgehakt — das Board aktualisiert sich also durch Gespräche. Zusätzlich
## berechnet upcoming_fixed() die festen Termine der Spielwelt im Voraus
## (Flohmarkt samstags, Club-Wettbewerb freitags, Geburtstag, Feiertage) —
## dieselbe Quelle nutzt der Wandkalender.

signal tasks_changed

const REAL_BACKUP_TASK_ID := "task_backup_real"
const REAL_BACKUP_MEMORY_PREFIX := "Sicherheitskopie, angelegt am "
const REAL_BACKUP_MEMORY_PREFIX_EN := "Backup created on "
const REAL_BACKUP_SOURCE_KEY := "backup_source_uid"

var tasks: Array = []   # [{id, title, note, done, day_added}]


func add_task(d: Dictionary) -> void:
	var id := str(d.get("id", ""))
	if id == "":
		return
	for existing: Dictionary in tasks:
		if str(existing.get("id", "")) != id:
			continue
		# Wiederkehrende Systemaufgaben (z. B. ein neuer Virus-Verdacht)
		# verwenden dieselbe semantische ID, werden aber nach einem früheren
		# Abschluss als frische Notiz erneut geöffnet. Eine bereits offene Instanz
		# wird niemals dupliziert oder in ihrem Fortschritt zurückgesetzt.
		if bool(existing.get("done", false)) and bool(d.get("repeatable", false)):
			existing["title"] = str(d.get("title", existing.get("title", "Aufgabe")))
			existing["note"] = str(d.get("note", existing.get("note", "")))
			existing["done"] = false
			existing["day_added"] = TimeManager.day_counter
			existing["repeatable"] = true
			_copy_optional_disk_contract(existing, d)
			_ensure_real_backup_contract(existing)
			tasks_changed.emit()
		elif _disk_contract_differs(existing, d):
			# Ein alter, bereits offener Task kann durch einen heutigen Event-
			# Datensatz nachträglich seinen Schutzvertrag erhalten.
			_copy_optional_disk_contract(existing, d)
			tasks_changed.emit()
		return
	var task := {
		"id": id,
		"title": str(d.get("title", "Aufgabe")),
		"note": str(d.get("note", "")),
		"done": false,
		"day_added": TimeManager.day_counter,
		"repeatable": bool(d.get("repeatable", false)),
	}
	_copy_optional_disk_contract(task, d)
	_ensure_real_backup_contract(task)
	tasks.append(task)
	tasks_changed.emit()


func has_task(id: String) -> bool:
	for t in tasks:
		if str(t.get("id", "")) == id:
			return true
	return false


## Read-only Gegenstück zu complete(). Systeme mit spielbaren Aufgaben müssen
## unterscheiden können, ob eine alte, bereits erledigte Notiz nur noch im
## Archiv liegt oder ob ihre Aktion wirklich noch aussteht.
func is_open(id: String) -> bool:
	for t in tasks:
		if str(t.get("id", "")) == id:
			return not bool(t.get("done", false))
	return false


## Spielbare Systemaktionen schließen normale Board-Notizen über dieselbe
## zentrale API ab wie Dialogeffekte. Ein bloßes Label oder eine normale
## X-COPY-Kopie zählt ausdrücklich nicht als Archivbackup.
func note_action(action_id: String, context: Dictionary = {}) -> bool:
	if action_id != "backup_disk":
		return false
	var task := _task_by_id(REAL_BACKUP_TASK_ID)
	if task.is_empty() or bool(task.get("done", false)):
		return false
	var action_day := int(context.get("day", TimeManager.day_counter))
	if action_day < int(task.get("day_added", 0)):
		return false
	# Die Erinnerungsaufgabe nennt genau eine Quelle. Andere Archivkopien bleiben
	# technisch gueltig, erledigen aber nicht versehentlich diesen Auftrag.
	_ensure_real_backup_contract(task)
	var required_source := str(task.get(REAL_BACKUP_SOURCE_KEY, ""))
	var actual_source := str(context.get("source_uid", ""))
	if not required_source.is_empty() and actual_source != required_source:
		return false
	task["done"] = true
	tasks_changed.emit()
	return true


## Save-Heilung für Backups, die korrekt geschrieben wurden, bevor die
## Board-Verknüpfung existierte. Neue Medien tragen einen monotonen Aktionstag.
## Für genau den betroffenen Legacy-Playtest genügt zusätzlich die vom Spiel
## selbst erzeugte, nicht editierbare Herkunftsnotiz mit dem heutigen Datum.
func reconcile_action_tasks() -> bool:
	var changed := false
	# Legacy-Spielstaende konnten Stefans Einfuehrungsdialog abschliessen, bevor
	# der Dialog die zugehoerige Besuchsnotiz abhaengte. Die Story-Flag ist hier
	# die belastbare Aktion; sie heilt den verwaisten 1997/2000-Boardeintrag.
	if is_open("visit_stefan_firma"):
		if bool(GameManager.flags.get("firma_intro", false)):
			complete("visit_stefan_firma")
			changed = true
		else:
			# Der alte Besuch erzeugte nur einen Zettel. Heute wird daraus der echte,
			# ueber Telefon ODER persoenliches Treffen spielbare Storydialog. Ist bei
			# Stefan noch ein anderer Rueckruf offen, bleibt der Zettel bis zu dessen
			# Abschluss bestehen und wird danach erneut abgeglichen.
			var queued := PhoneManager.expect_call(
				"npc_stefan", "visit_stefan_firma",
				"Stefan wegen der Teststelle sprechen", "call_stefan_firma")
			if queued:
				complete("visit_stefan_firma")
				changed = true
	var task := _task_by_id(REAL_BACKUP_TASK_ID)
	if task.is_empty() or bool(task.get("done", false)):
		return changed
	var task_day := int(task.get("day_added", 0))
	for disk: Disk in DiskManager.disks:
		if disk.archive_backup_day >= task_day and _backup_matches_task(task, disk):
			return note_action("backup_disk", {
				"day": disk.archive_backup_day,
				"disk_uid": disk.uid,
				"source_uid": disk.source_uid,
			})
		if disk.archive_backup_day < 0 and _is_legacy_backup_from_today(disk) \
				and _backup_matches_task(task, disk):
			return note_action("backup_disk", {
				"day": TimeManager.day_counter,
				"disk_uid": disk.uid,
				"source_uid": disk.source_uid,
				"legacy": true,
			})
	return changed


## Vertrag fuer die wiederkehrende Backup-Erinnerung. Er wird mit der Aufgabe
## gespeichert, damit Name und UID nach Laden/Jahreswechsel nicht springen.
func real_backup_contract() -> Dictionary:
	var task := _task_by_id(REAL_BACKUP_TASK_ID)
	if task.is_empty() or bool(task.get("done", false)):
		return {}
	_ensure_real_backup_contract(task)
	var uid := str(task.get(REAL_BACKUP_SOURCE_KEY, ""))
	return {
		"task_id": REAL_BACKUP_TASK_ID,
		"source_uid": uid,
		"source_name": str(task.get("backup_source_name", "eine belegte Diskette")),
		"required": not uid.is_empty(),
	}


func _ensure_real_backup_contract(task: Dictionary) -> void:
	if str(task.get("id", "")) != REAL_BACKUP_TASK_ID or bool(task.get("done", false)):
		return
	var uid := str(task.get(REAL_BACKUP_SOURCE_KEY, ""))
	var source := _disk_by_uid(uid)
	if source == null:
		source = _choose_backup_source()
		if source != null:
			task[REAL_BACKUP_SOURCE_KEY] = source.uid
			task["backup_source_name"] = source.display_name()
	var source_name := str(task.get("backup_source_name", "eine belegte Diskette"))
	if source != null:
		source_name = source.display_name()
		task["backup_source_name"] = source_name
	task["title"] = "Eine echte Archivkopie anlegen"
	task["note"] = ("EXAKT 1 DISK - NICHT ALLE: >>%s<<. Amiga -> Disketten -> "
		+ "Quelle waehlen -> BACKUP. In X-COPY 1 echte Leerdiskette als ZIEL "
		+ "einlegen; der vollstaendige Verify schliesst die Aufgabe ab.") % source_name


func _choose_backup_source() -> Disk:
	var candidates: Array = DiskManager.media_disks().filter(func(disk: Disk) -> bool:
		return disk != null and not disk.is_boxed_package() \
			and disk.content_type not in ["leer", "mystery", "system"] \
			and disk.condition > 0 and not disk.label.begins_with("Backup: "))
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Disk, b: Disk) -> bool:
		var a_score := a.value() * 100 + (25 if a.provenance in ["original", "original_box"] else 0)
		var b_score := b.value() * 100 + (25 if b.provenance in ["original", "original_box"] else 0)
		if a_score != b_score:
			return a_score > b_score
		return a.display_name().naturalnocasecmp_to(b.display_name()) < 0)
	return candidates[0]


func _disk_by_uid(uid: String) -> Disk:
	if uid.is_empty():
		return null
	for disk: Disk in DiskManager.disks:
		if disk.uid == uid:
			return disk
	return null


func _backup_matches_task(task: Dictionary, backup: Disk) -> bool:
	_ensure_real_backup_contract(task)
	var required_source := str(task.get(REAL_BACKUP_SOURCE_KEY, ""))
	return required_source.is_empty() or backup.source_uid == required_source


func _task_by_id(id: String) -> Dictionary:
	for task: Dictionary in tasks:
		if str(task.get("id", "")) == id:
			return task
	return {}


func _is_legacy_backup_from_today(disk: Disk) -> bool:
	# Historische Saves besitzen noch keinen `archive_backup_day`. Die damals
	# vom Spiel geschriebene Kombination aus Herkunfts-UID, Verify-Status,
	# Backup-Label und nicht editierbarer Provenienznotiz ist dennoch eindeutig.
	# Der alte Wortlaut war deutsch; neuere Saves koennen bereits den englischen
	# Prefix tragen. Ein exakter Vergleich mit dem aktuell lokalisierten Datum
	# wuerde beim Sprachwechsel oder nach Kalenderkorrekturen echte Backups
	# unheilbar machen.
	if disk == null or not disk.checked or disk.content_type == "leer":
		return false
	if not disk.label.begins_with("Backup: ") or disk.source_uid.is_empty():
		return false
	var provenance := disk.memory.strip_edges()
	return provenance.begins_with(REAL_BACKUP_MEMORY_PREFIX) \
		or provenance.begins_with(REAL_BACKUP_MEMORY_PREFIX_EN)


## Bindet eine normale Board-Aufgabe an die UID, die in einem Spielflag liegt.
## Damit greifen Formatieren, Wegwerfen, Handel und Quest-Uebergaben auf denselben
## Schutzvertrag zu, ohne die ID einer einzelnen Aufgabe kennen zu müssen.
func bind_disk_requirement(id: String, uid_flag: String, protect_text: String) -> bool:
	if id.is_empty() or uid_flag.is_empty():
		return false
	for task: Dictionary in tasks:
		if str(task.get("id", "")) != id:
			continue
		var changed := str(task.get("disk_uid_flag", "")) != uid_flag \
			or str(task.get("protect_text", "")) != protect_text
		task["disk_uid_flag"] = uid_flag
		task["protect_text"] = protect_text
		if changed:
			tasks_changed.emit()
		return true
	return false


func update_task_text(id: String, title: String, note: String) -> bool:
	for task: Dictionary in tasks:
		if str(task.get("id", "")) != id:
			continue
		var changed := str(task.get("title", "")) != title \
			or str(task.get("note", "")) != note
		task["title"] = title
		task["note"] = note
		if changed:
			tasks_changed.emit()
		return true
	return false


## Schutzvertrag einer offenen Board-Aufgabe fuer ein konkretes Medium.
func disk_requirement(disk: Disk) -> Dictionary:
	if disk == null:
		return {"required": false}
	for task: Dictionary in tasks:
		if bool(task.get("done", false)):
			continue
		var uid_flag := str(task.get("disk_uid_flag", ""))
		if uid_flag.is_empty():
			continue
		var required_uid := str(GameManager.flags.get(uid_flag, ""))
		if not required_uid.is_empty() and disk.uid == required_uid:
			return {
				"required": true,
				"task_id": str(task.get("id", "")),
				"text": str(task.get("protect_text",
					"Diese Diskette wird noch für eine offene Aufgabe benötigt.")),
			}
	return {"required": false}


func _copy_optional_disk_contract(target: Dictionary, source: Dictionary) -> void:
	if source.has("disk_uid_flag"):
		target["disk_uid_flag"] = str(source.get("disk_uid_flag", ""))
	if source.has("protect_text"):
		target["protect_text"] = str(source.get("protect_text", ""))


func _disk_contract_differs(target: Dictionary, source: Dictionary) -> bool:
	return (source.has("disk_uid_flag")
			and str(target.get("disk_uid_flag", "")) != str(source.get("disk_uid_flag", ""))) \
		or (source.has("protect_text")
			and str(target.get("protect_text", "")) != str(source.get("protect_text", "")))


func complete(id: String) -> void:
	for t in tasks:
		if str(t.get("id", "")) == id and not bool(t.get("done", false)):
			t["done"] = true
			tasks_changed.emit()
			return


func remove(id: String) -> void:
	tasks = tasks.filter(func(t: Dictionary) -> bool: return str(t.get("id", "")) != id)
	tasks_changed.emit()


func open_count() -> int:
	var n := 0
	for t in tasks:
		if not bool(t.get("done", false)):
			n += 1
	return n


# ------------------------------------------------- feste Termine (Vorschau)

## Wochentag (0=Mo..6=So) eines beliebigen Datums — Zeller, identisch zu
## TimeManager.weekday_for_date. (Bewusst lokale Kopie: weekday_for_date ist static,
## ein Aufruf über die typisierte TimeManager-Autoload-Instanz löst
## STATIC_CALLED_ON_INSTANCE aus. Einzelquelle wäre über einen preload-Const möglich.)
func weekday_of(y: int, m: int, d: int) -> int:
	if m < 3:
		m += 12
		y -= 1
	var k := y % 100
	var j := int(y / 100.0)
	var h := (d + int(13 * (m + 1) / 5.0) + k + int(k / 4.0) + int(j / 4.0) + 5 * j) % 7
	return (h + 5) % 7


## Feste Termine der nächsten `horizon` Tage (heute eingeschlossen):
## [{title, day, month, year, days, badge}] — Quelle für Board UND Wandkalender.
func upcoming_fixed(horizon := 14) -> Array:
	var out: Array = []
	var y := TimeManager.year
	var m := TimeManager.month
	var d := TimeManager.day
	for offset in horizon:
		var entries := events_on(y, m, d)
		for e: Dictionary in entries:
			e["day"] = d
			e["month"] = m
			e["year"] = y
			e["days"] = offset
			out.append(e)
		# einen Tag weiter — mit korrektem 29. Februar (dieselbe Quelle wie TimeManager),
		# sonst driftet die Vorschau in Schaltjahren (1992/1996/2000) um einen Tag.
		d += 1
		if d > TimeManager.days_in_month(y, m):
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
	return out


## Welche festen Ereignisse liegen auf diesem Datum? [{title, badge}]
func events_on(y: int, m: int, d: int) -> Array:
	var out: Array = []
	var wd := weekday_of(y, m, d)
	if wd == 5:
		out.append({"title": Loc.t("sys.task_manager.flea_market_morning",
			"Flohmarkt (vormittags)"), "badge": "F"})
	if wd == 4:
		out.append({"title": Loc.t("sys.task_manager.club_contest_evening",
			"Club-Wettbewerb (abends)"), "badge": "C"})
	var pi := get_node_or_null("/root/PlayerIdentity")
	if pi != null and d == int(pi.get("birth_day")) and m == int(pi.get("birth_month")):
		out.append({"title": Loc.t("sys.task_manager.your_birthday",
			"Dein Geburtstag!"), "badge": "★"})
	if m == 12 and d == 24:
		out.append({"title": Loc.t("event.cal_weihnachten.title", "Heiligabend"), "badge": "W"})
	if m == 12 and d == 31:
		out.append({"title": Loc.t("event.cal_silvester.title", "Silvester"), "badge": "S"})
	return out


func to_dict() -> Dictionary:
	return {"tasks": tasks}


func from_dict(d: Dictionary) -> void:
	# Fruehe Saves konnten dieselbe semantische Aufgabe mehrfach enthalten.
	# Aktuelle Produzenten verhindern das bereits in add_task(), aber ohne eine
	# Ladegrenze liefen has_task()/is_open()/complete() danach auf dem ersten
	# Treffer, waehrend open_count() alle Duplikate zaehlte. Die stabile Task-ID
	# ist deshalb beim Import die einzige Autoritaet. Der juengste Eintrag gewinnt;
	# optionale Schutzmetadaten aus aelteren Eintraegen bleiben erhalten.
	tasks = _normalize_loaded_tasks(d.get("tasks", []))
	var backup_task := _task_by_id(REAL_BACKUP_TASK_ID)
	if not backup_task.is_empty():
		_ensure_real_backup_contract(backup_task)
	tasks_changed.emit()
	reconcile_action_tasks()


func _normalize_loaded_tasks(raw_tasks: Variant) -> Array:
	var normalized: Array = []
	var index_by_id: Dictionary = {}
	if not raw_tasks is Array:
		return normalized
	for raw_task: Variant in raw_tasks:
		if not raw_task is Dictionary:
			continue
		var task: Dictionary = (raw_task as Dictionary).duplicate(true)
		var task_id := str(task.get("id", "")).strip_edges()
		if task_id.is_empty():
			continue
		task["id"] = task_id
		task["title"] = str(task.get("title", "Aufgabe"))
		task["note"] = str(task.get("note", ""))
		task["done"] = bool(task.get("done", false))
		task["day_added"] = maxi(0, int(task.get("day_added", 0)))
		task["repeatable"] = bool(task.get("repeatable", false))
		if not index_by_id.has(task_id):
			index_by_id[task_id] = normalized.size()
			normalized.append(task)
			continue
		var existing_index := int(index_by_id[task_id])
		var existing: Dictionary = normalized[existing_index]
		# Array-Reihenfolge ist fuer gleich alte Legacy-Eintraege der letzte
		# verbliebene Chronologiebeleg. Bei spaeterem oder gleich altem Eintrag
		# wird daher dessen offen/erledigt-Zustand uebernommen.
		var replacement := task if int(task["day_added"]) >= int(existing["day_added"]) \
			else existing
		var fallback := existing if replacement == task else task
		for optional_key: String in ["disk_uid_flag", "protect_text",
				REAL_BACKUP_SOURCE_KEY, "backup_source_name"]:
			if not replacement.has(optional_key) and fallback.has(optional_key):
				replacement[optional_key] = fallback[optional_key]
		normalized[existing_index] = replacement
	return normalized


func reset() -> void:
	tasks = []
	tasks_changed.emit()
