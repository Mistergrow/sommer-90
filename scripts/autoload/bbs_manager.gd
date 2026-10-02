extends Node
## BBSManager — Mailbox-Welt der Kulturschicht (docs/KULTUR_LAYER.md Kap. 7).
## Datengetrieben aus data/bbs_boards.json, Living-Timeline-gefiltert
## (year_from/year_to). Schaltet frei, sobald der Spieler ein Modem besitzt.
##
## Einwahl -> Verbindung (Telefongebühren, Eltern-Toleranz!) -> Board mit
## Datei-Downloads (landen als Disketten in der Box), Nachrichten,
## Kleinanzeigen und News. Downloads bringen Wissen/Ruf, kosten Zeit & Geld.

signal connection_changed

const DB_PATH := "res://data/bbs_boards.json"
const AssistantEngine := preload("res://scripts/ui/bbs_assistant_engine.gd")
const FAREWELL_BOARD_ID := "bbs_nachtschicht"
const FAREWELL_ARCHIVE_ID := "bbs_farewell_archive"
const FAREWELL_ARCHIVE := {
	"quest_file_id": FAREWELL_ARCHIVE_ID,
	"mission_critical": true,
	"content_type": "archiv",
	"content_title": "NACHTSCHICHT-KOMPLETTARCHIV 1993-1996",
	"software_id": FAREWELL_ARCHIVE_ID,
	"rarity": "unique",
	"size_kb": 720,
	"note": "PFLICHTDATEI 1/1: Einziger nötiger Download. Programme darunter sind optional.",
}

var _boards: Array = []             # alle Board-Definitionen
var _phone_base := 0.12
var current_board: Dictionary = {}  # {} = offline
var _visited: Dictionary = {}       # board_id -> true (fürs Rückblick/Ruf)
var _assistant_history: Dictionary = {} # board_id -> [{role, text, day}]


func _ready() -> void:
	var file := FileAccess.open(DB_PATH, FileAccess.READ)
	if file == null:
		push_warning("BBSManager: %s fehlt" % DB_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_warning("BBSManager: %s ist ungueltig" % DB_PATH)
		return
	var data: Dictionary = parsed
	_boards = data.get("boards", [])
	_phone_base = float(data.get("phone_costs", {}).get("base", 0.12))


## Frisches Spiel: offline und ohne besuchte Boards des alten Durchlaufs
## (Autoloads überleben den Spielstart, daher explizit zurücksetzen).
func reset() -> void:
	current_board = {}
	_visited = {}
	_assistant_history = {}
	connection_changed.emit()


## Modem-Baudraten der besitzbaren Modelle (Kauf oder Bestellkatalog).
## Das 9600er ist bereits ab 1992 bestellbar. Es hier zu vergessen machte
## ausgerechnet einen technisch besser vorbereiteten 1993-Spielstand offline.
const MODEM_BAUDS := {
	"modem": 2400,
	"modem_9600": 9600,
	"modem_14400": 14400,
}

## Modem vorhanden? (Shop-Kauf oder Bestellkatalog schaltet BBS frei)
func available() -> bool:
	for hw in MODEM_BAUDS:
		if PlayerStats.has_hardware(hw):
			return true
	return false


## Schnellstes angeschlossenes Modem in Baud (0 = keins). Ein bestelltes
## 14400er lädt spürbar schneller/günstiger als das 2400er von der Stange.
func player_baud() -> int:
	var best := 0
	for hw in MODEM_BAUDS:
		if PlayerStats.has_hardware(hw):
			best = maxi(best, int(MODEM_BAUDS[hw]))
	return best


## Effektive Geschwindigkeit der aktuellen Verbindung. Ein schnelles Modem
## macht ein langsames Board nicht schneller; umgekehrt limitiert das eigene
## Modem eine modernere Mailbox. Anzeige, Kosten und Dauer verwenden damit
## dieselbe technische Wahrheit.
func connection_baud(board: Dictionary = current_board) -> int:
	if board.is_empty():
		return 0
	return mini(player_baud(), int(board.get("baud", 2400)))


## Boards, die im aktuellen Jahr erreichbar sind (Living Timeline).
func boards_for_year(year: int = -1) -> Array:
	if year < 0:
		year = TimeManager.year
	var result: Array = []
	for board: Dictionary in _boards:
		if _board_available(board, year):
			result.append(_localized_board(board))
	return result


func board_by_id(board_id: String) -> Dictionary:
	for b in _boards:
		if b.get("id", "") == board_id:
			return b
	return {}


## Der Abschiedsauftrag zeigt nicht mehr auf eine vage „letzte Mailbox“, sondern
## auf genau das Nachtschicht Board und genau eine dort eingeblendete Archivdatei.
func farewell_archive_pending() -> bool:
	return QuestManager.is_active("q_bbs_farewell") \
		and QuestManager.stage("q_bbs_farewell") == 0


func farewell_mission_active() -> bool:
	return QuestManager.is_active("q_bbs_farewell")


func farewell_board_id() -> String:
	return FAREWELL_BOARD_ID


# ------------------------------------------------------------- Verbindung

## Einwählen. Rückgabe: {ok, text}. Kostet einen Zeit-Slot-Bruchteil an
## Energie + Telefongrundgebühr; scheitert bei besetztem Board (Zufall).
func dial(board_id: String) -> Dictionary:
	if not available():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.kein_modem_angeschlossen_computerladen_hilft", "Kein Modem angeschlossen. Der Computerladen hilft.")}
	var board := board_by_id(board_id)
	if board.is_empty():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.unknown_number", "Unbekannte Nummer.")}
	if not _board_available(board, TimeManager.year):
		return {"ok": false, "text": Loc.t("sys.bbs_manager.kein_freizeichen_diese_mailbox_gibt_es", "Kein Freizeichen — diese Mailbox gibt es (noch) nicht.")}
	if not PlayerStats.use_energy(4):
		return {"ok": false, "text": Loc.t("sys.bbs_manager.zu_mude_um_noch_online_zu", "Zu müde, um noch online zu gehen.")}
	# Modem teilt sich die Leitung mit dem Telefon. Bei gesperrter Leitung
	# (unbezahlte Rechnung) geht gar nichts.
	if PhoneManager.line_locked():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.kein_freizeichen_papa_hat_telefon_gesperrt", "Kein Freizeichen — Papa hat das Telefon gesperrt, bis die Rechnung bezahlt ist (%d DM).") % PhoneManager.bill_due}
	# Besetzt? Beliebte Boards mit wenigen Nodes sind oft belegt — dann kommt KEINE
	# Verbindung zustande, also läuft auch KEINE Gebühr auf (Besetztzeichen ist gratis).
	# Das einmalige Missionsziel darf nicht hinter einem Zufalls-Besetztzeichen
	# verschwinden. Alle normalen Einwahlen behalten die zeittypischen 18 %.
	var protected_farewell_dial := farewell_mission_active() and board_id == FAREWELL_BOARD_ID
	if not protected_farewell_dial and randf() < 0.18:
		return {"ok": false, "text": Loc.t("sys.bbs_manager.tuut_tuut_besetzt_mailbox_hat_nur", "TUUT… TUUT… besetzt. Die Mailbox hat nur wenige Leitungen. Später nochmal.")}
	# Verbunden → jetzt die Modem-Grundgebühr auf die monatliche Telefonrechnung.
	PhoneManager.modem_session()
	var first_login := not bool(GameManager.flags.get("bbs_login", false))
	current_board = board
	_visited[board_id] = true
	# Elternnerv steigt mit langen Online-Nächten
	PlayerStats.change_stat("eltern_toleranz", -1)
	MemoryManager.record_once("first_bbs_login")
	AchievementManager.note("bbs_login")   # Meilenstein: erste Einwahl
	QuestManager.note_action("bbs_login")
	QuestManager.note_action("bbs_login:" + board_id)
	# Der Sysop ist jetzt wirklich Teil seiner Quest: Beim ersten CONNECT begruesst
	# er den Spieler. 1996 startet ueber denselben glaubwuerdigen Kanal der BBS-
	# Abschiedsbogen, statt als stummes Jahresflag aufzupoppen.
	# Die 1993er Regeln haben Vorrang und werden auch dann angeboten, wenn der
	# Spieler mit einem frueh gekauften Modem schon 1992 eine andere Box besucht
	# hat. Sonst konnte das globale first-login-Flag diese Quest dauerhaft sperren.
	var needs_nachtschicht_rules := board_id == "bbs_nachtschicht" \
		and QuestManager.is_active("q_ins_bbs") and QuestManager.stage("q_ins_bbs") == 1
	if needs_nachtschicht_rules:
		DialogueManager.start_dialogue("bbs_sysop_welcome", "npc_sysop")
	elif TimeManager.year >= 1996 and not bool(GameManager.flags.get("bbs_farewell_intro", false)):
		GameManager.flags["bbs_farewell_intro"] = true
		DialogueManager.start_dialogue("bbs_sysop_farewell", "npc_sysop")
	elif first_login:
		DialogueManager.start_dialogue("bbs_sysop_welcome", "npc_sysop")
	connection_changed.emit()
	return {"ok": true, "text": Loc.t("sys.bbs_manager.connect_d_carrier_erkannt_du_bist", "CONNECT %d… Carrier erkannt. Du bist drin: %s.") % [
		connection_baud(board), board.get("name", "?")]}


func hang_up() -> void:
	current_board = {}
	connection_changed.emit()


func connected() -> bool:
	return not current_board.is_empty()


# -------------------------------------------------------- SysOp-/AMI-BOT-Hilfe

## Der sichtbare Name bleibt zeittypisch: zuerst antwortet der SysOp, 1999 wird
## dasselbe lokale Hilfesystem als kleines Expertensystem vermarktet.
func assistant_name() -> String:
	var sysop := str(current_board.get("sysop", "SYSOP")).to_upper()
	return Loc.t("sys.bbs_manager.ami_bot_name", "AMI-BOT 99 / %s") % sysop \
		if TimeManager.year >= 1999 else Loc.t("sys.bbs_manager.sysop_help_name", "SYSOP-HILFE / %s") % sysop


func assistant_history(board_id := "") -> Array:
	var id := board_id if not board_id.is_empty() else str(current_board.get("id", "offline"))
	var raw: Variant = _assistant_history.get(id, [])
	return (raw as Array).duplicate(true) if raw is Array else []


## Eine Frage wird zusammen mit der Antwort begrenzt gespeichert. BBCode-
## Steuerzeichen werden entfernt, damit Nutzereingaben niemals das Terminal-
## Layout zerlegen koennen.
func assistant_send(message: String) -> Dictionary:
	if not connected():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.no_carrier_first_connect",
			"NO CARRIER. Erst mit einer Mailbox verbinden.")}
	var clean := message.strip_edges().replace("[", "(").replace("]", ")") \
		.replace("\n", " ").replace("\r", " ")
	if clean.is_empty():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.bitte_kurze_frage_eingeben", "Bitte eine kurze Frage eingeben.")}
	clean = clean.left(120)
	var id := str(current_board.get("id", "offline"))
	var history: Array = assistant_history(id)
	var response := AssistantEngine.answer(clean, _assistant_context())
	history.append({"role": "user", "text": clean, "day": TimeManager.day_counter})
	history.append({"role": "assistant", "text": response.left(420), "day": TimeManager.day_counter})
	while history.size() > 18:
		history.pop_front()
	_assistant_history[id] = history
	return {"ok": true, "text": response}


func _assistant_context() -> Dictionary:
	var mission_hint := ""
	if farewell_mission_active():
		match QuestManager.stage("q_bbs_farewell"):
			0:
				mission_hint = Loc.t("sys.bbs_manager.farewell_archive_hint",
					"AUFTRAG: Nachtschicht Board → DATEIEN → genau das NACHTSCHICHT-KOMPLETTARCHIV 1/1 herunterladen. Die Programme darunter sind optional.")
			1:
				mission_hint = Loc.t("sys.bbs_manager.farewell_release_hint",
					"AUFTRAG: Nachtschicht Board → EIGENE RELEASES → deinen verifizierten Abschiedsmaster hochladen. Die Masterdisk bleibt bei dir.")
			_:
				mission_hint = Loc.t("sys.bbs_manager.farewell_done",
					"Der Nachtschicht-Abschied ist bereits abgeschlossen.")
	return {
		"board": str(current_board.get("name", "Mailbox")),
		"sysop": str(current_board.get("sysop", "SYSOP")),
		"year": TimeManager.year,
		"baud": connection_baud(),
		"blank_disks": DiskManager.blank_disks().size(),
		"phone_bill": PhoneManager.bill_due,
		"has_hdd": PlayerStats.has_hardware("harddisk")
			or PlayerStats.has_hardware("a1200_ide_hdd"),
		"mission_hint": mission_hint,
	}


# ------------------------------------------------------------- Inhalte

func news() -> Array:
	var result: Array = []
	var board_id := str(current_board.get("id", "bbs"))
	for source: Variant in current_board.get("areas", {}).get("news", []):
		var text := str(source)
		result.append(Loc.t("bboard.%s.news.%s.text" % [board_id, _stable_text_id(text)], text))
	return result


func messages() -> Array:
	var result: Array = []
	var board_id := str(current_board.get("id", "bbs"))
	for source: Dictionary in current_board.get("areas", {}).get("messages", []):
		var entry := source.duplicate(true)
		var token := _stable_text_id(str(source.get("subject", source.get("body", "message"))))
		for field: String in ["subject", "body"]:
			var text := str(source.get(field, ""))
			entry[field] = Loc.t("bboard.%s.messages.%s.%s" % [board_id, token, field], text)
		result.append(entry)
	return result


func classifieds() -> Array:
	var result: Array = []
	var board_id := str(current_board.get("id", "bbs"))
	for source: Dictionary in current_board.get("areas", {}).get("classifieds", []):
		var entry := source.duplicate(true)
		var text := str(source.get("text", ""))
		entry["text"] = Loc.t("bboard.%s.classifieds.%s.text" % [
			board_id, _stable_text_id(text)], text)
		result.append(entry)
	return result


func files() -> Array:
	var result: Array = []
	var board_id := str(current_board.get("id", "bbs"))
	for source: Dictionary in current_board.get("areas", {}).get("files", []):
		result.append(_localized_file(board_id, source))
	if farewell_archive_pending() \
			and str(current_board.get("id", "")) == FAREWELL_BOARD_ID:
		var archive := FAREWELL_ARCHIVE.duplicate(true)
		# Der lokalisierte Anzeigename darf niemals zur persistenten Disk-ID
		# werden. Quests und Tools arbeiten sprachunabhaengig mit dieser ID.
		archive["content_type_id"] = str(FAREWELL_ARCHIVE["content_type"])
		archive["content_type"] = Loc.t("sys.bbs_manager.archive_type", "Archiv")
		archive["content_title"] = Loc.t("sys.bbs_manager.archive_title",
			"NACHTSCHICHT-KOMPLETTARCHIV 1993–1996")
		archive["note"] = Loc.t("sys.bbs_manager.archive_note",
			"PFLICHTDATEI 1/1: Einziger nötiger Download. Programme darunter sind optional.")
		result.push_front(archive)
	result.append_array(_mod_files())
	return result


func _localized_board(source: Dictionary) -> Dictionary:
	var board := source.duplicate(true)
	var board_id := str(source.get("id", "bbs"))
	var tagline := str(source.get("tagline", ""))
	board["tagline"] = Loc.t("bboard.%s.tagline" % board_id, tagline)
	return board


func _localized_file(board_id: String, source: Dictionary) -> Dictionary:
	var entry := source.duplicate(true)
	# content_type ist zugleich ein sichtbares BBS-Feld und eine semantische
	# Medien-ID. Beides muss getrennt bleiben, damit ein Sprachwechsel weder
	# Quests noch Diskettenfilter beschaedigt.
	entry["content_type_id"] = str(source.get("content_type", "tools"))
	var anchor := str(source.get("id", source.get("software_id", source.get("content_title", "file"))))
	var token := _stable_text_id(anchor)
	for field: String in ["content_type", "content_title", "note"]:
		if not source.has(field):
			continue
		var text := str(source.get(field, ""))
		entry[field] = Loc.t("bboard.%s.files.%s.%s" % [board_id, token, field], text)
	return entry


func _stable_text_id(source: String) -> String:
	return source.sha256_text().left(10)


## Eigene BYTEWERK-Releases, die auf dem aktuell verbundenen Board noch nicht
## liegen. Der SceneReleaseManager entscheidet Board-Zulassung und Idempotenz.
func scene_uploads() -> Array:
	if not connected() or not scene_upload_area():
		return []
	return SceneReleaseManager.uploadable_releases(
		str(current_board.get("id", "")))


## Nicht jede Mailbox akzeptiert Szene-Releases (das einsteigerfreundliche
## PD-Board z.B. ausdrücklich nicht). Die zentrale BYTEWERK-Config entscheidet.
func scene_upload_area() -> bool:
	if not connected():
		return false
	var board_id := str(current_board.get("id", ""))
	for definition: Dictionary in SceneReleaseManager.config().get("boards", []):
		if str(definition.get("id", "")) != board_id:
			continue
		return _scene_board_available(definition)
	return false


## Die Living Timeline bleibt historisch (alle normalen Boards schließen), aber
## Datenautobahn 2000 nimmt im freien Spiel noch genau den offenen Abschieds-/
## Millennium-Backlog an. Nach Questabschluss verschwindet auch dieser Catch-up.
func _quest_catchup_active() -> bool:
	return not QuestManager.is_done("q_bbs_farewell") or QuestManager.is_active("q_millennium_demo")


func _board_available(board: Dictionary, year: int) -> bool:
	if year >= int(board.get("year_from", 1990)) and year <= int(board.get("year_to", 1999)):
		return true
	# Ein angenommener Auftrag darf beim Jahreswechsel nie unerreichbar werden.
	# Nach dem regulaeren Sendeschluss bleibt der Nachtschicht-Knoten nur fuer
	# den offenen Abschiedsbacklog als Archivleitung sichtbar.
	if year > int(board.get("year_to", 1999)) \
			and str(board.get("id", "")) == FAREWELL_BOARD_ID \
			and farewell_mission_active():
		return true
	return year > int(board.get("year_to", 1999)) \
		and str(board.get("id", "")) == "bbs_datenautobahn" and _quest_catchup_active()


func _scene_board_available(board: Dictionary) -> bool:
	if TimeManager.year >= int(board.get("from", 1990)) and TimeManager.year <= int(board.get("to", 1999)):
		return true
	if TimeManager.year > int(board.get("to", 1999)) \
			and str(board.get("id", "")) == FAREWELL_BOARD_ID \
			and farewell_mission_active():
		return true
	return TimeManager.year > int(board.get("to", 1999)) \
		and str(board.get("id", "")) == "bbs_datenautobahn" and _quest_catchup_active()


## Upload spiegelt den Release; die physische Masterdisk bleibt in der Box.
## Energie, Ruf und Idempotenz verbucht atomar der SceneReleaseManager.
func upload_scene_release(disk: Disk) -> Dictionary:
	if not connected():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.nicht_verbunden", "Nicht verbunden.")}
	if disk == null:
		return {"ok": false, "text": Loc.t("sys.bbs_manager.keine_release_diskette_gewahlt", "Keine Release-Diskette gewählt.")}
	var allowed := false
	for candidate in scene_uploads():
		if candidate == disk or (candidate is Disk and candidate.uid == disk.uid):
			allowed = true
			break
	if not allowed:
		return {"ok": false, "text": Loc.t("sys.bbs_manager.dieses_release_liegt_hier_schon_oder", "Dieses Release liegt hier schon oder das Board nimmt keine Szene-Releases an.")}
	var result: Dictionary = SceneReleaseManager.upload_release(
		disk, str(current_board.get("id", "")))
	if bool(result.get("ok", false)):
		AudioManager.floppy_read()
		if farewell_mission_active() \
				and QuestManager.stage("q_bbs_farewell") == 1 \
				and str(current_board.get("id", "")) == FAREWELL_BOARD_ID:
			QuestManager.note_action("bbs_farewell_release_uploaded")
		QuestManager.note_action("bbs_upload")
		QuestManager.note_action("millennium_upload")
	return result


## MOD-Musik im Dateibereich (Katalog-Tracks mit Kanal "bbs", s. MOD-Bible).
## Deterministisch je Board+Jahr (2–3 Stück), damit sich Boards unterscheiden
## und das Angebot mit der Living Timeline wandert.
func _mod_files() -> Array:
	var pool: Array = MusicManager.tracks_on("bbs")
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(current_board.get("id", "")) + str(TimeManager.year))
	var out: Array = []
	for _i in mini(2 + int(rng.randf() < 0.5), pool.size()):
		var t: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if out.any(func(e: Dictionary) -> bool: return e.get("music_id", "") == t.get("id", "")):
			continue
		out.append({
			"content_type": "mod", "music_id": t.get("id", ""),
			"content_title": "%s (MOD)" % t.get("title", "?"),
			"rarity": "rare" if int(t.get("stars", 0)) >= 5 else "common",
			"size_kb": 180, "note": Loc.t("sys.bbs_manager.tracker_music_by", "Tracker-Musik von %s.") % t.get("author", "?"),
		})
	return out


## Datei herunterladen: landet als frische Kopie-Diskette in der Box.
## Größere Dateien dauern länger (Energie) und kosten mehr Telefongebühr.
func download(file_entry: Dictionary) -> Dictionary:
	if not connected():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.nicht_verbunden", "Nicht verbunden.")}
	if DiskManager.blank_disks().is_empty():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.keine_leerdiskette_in_box_ohne_ziel", "Keine Leerdiskette in der Box! Ohne Ziel kein Download.")}
	var baud := float(maxi(300, connection_baud()))
	var size_kb := float(file_entry.get("size_kb", 200))
	# Übertragungsdauer -> Energie & Telefongebühr (2400 Baud ist ZÄH)
	var minutes := size_kb * 8.0 / (baud / 1000.0) / 60.0
	var energy_cost := clampi(int(minutes * 0.6) + 2, 3, 30)
	if not PlayerStats.use_energy(energy_cost):
		return {"ok": false, "text": Loc.t("sys.bbs_manager.zu_mude_fur_einen_so_langen", "Zu müde für einen so langen Download.")}
	# Lange Downstreams sind die dicken Modem-Posten — wie die Einwahl laufen sie
	# auf die MONATLICHE Telefonrechnung (geteilte Leitung), nicht sofort bar.
	var phone_cost := int(ceil(minutes * _phone_base * 2.0))
	PhoneManager.add_phone_charge(phone_cost)
	var blank: Disk = DiskManager.blank_disks()[0]
	blank.content_type = str(file_entry.get("content_type_id",
		file_entry.get("content_type", "tools")))
	blank.content_title = file_entry.get("content_title", "Download")
	blank.rarity = file_entry.get("rarity", "common")
	blank.software_id = file_entry.get("software_id", "")
	blank.provenance = CultureManager.PROVENANCE_COPY
	blank.copy_generation = 1
	blank.checked = false  # erst Prüfen deckt Zustand/Viren auf
	# Downloads aus fremden Quellen: kleines Virusrisiko der Ära
	blank.virus = randf() < 0.06
	blank.label = ""
	blank.labeled = false
	blank.memory = Loc.t("sys.bbs_manager.download_memory",
		"Aus %s geladen, %s") % [current_board.get("name", "BBS"), TimeManager.date_string()]
	var quest_file_id := str(file_entry.get("quest_file_id", ""))
	if quest_file_id == FAREWELL_ARCHIVE_ID:
		blank.memory = Loc.t("sys.bbs_manager.farewell_archive_memory",
			"Lokaler Archivbestand der Nachtschicht Mailbox, gesichert am %s") \
			% TimeManager.date_string()
	# MOD-Download: Track wandert zusätzlich in die Musiksammlung (Anlage).
	if str(file_entry.get("music_id", "")) != "":
		MusicManager.collect(str(file_entry["music_id"]))
		MemoryManager.record("musik", Loc.t("sys.bbs_manager.music_download_memory",
			"»%s« von der Mailbox gezogen") % str(file_entry.get("content_title", "?")))
	PlayerStats.change_stat("wissen", 1)
	AudioManager.floppy_read()  # Download landet ratternd auf der Leerdiskette
	DiskManager._apply_sort()
	DiskManager.disks_changed.emit()
	# Erst die präzise Missionsaktion verbuchen. Ein beliebiger MOD- oder
	# Shareware-Download kann den Abschiedsauftrag damit nicht mehr vortäuschen.
	if quest_file_id == FAREWELL_ARCHIVE_ID:
		QuestManager.note_action("bbs_farewell_archive_downloaded")
	QuestManager.note_action("bbs_download")
	# Der sichtbare Terminal-Inhalt hängt ebenfalls vom Questfortschritt ab:
	# Nach dem Komplettarchiv verschwindet die Datei und „Eigene Releases“
	# wird zum nächsten Auftragspfad. Ohne Refresh blieb unter dem Carrier-Lab
	# ein veralteter Dateibereich mit erneut klickbarem Archivbutton liegen.
	connection_changed.emit()
	var note: String = file_entry.get("note", "")
	return {"ok": true, "text": Loc.t("sys.bbs_manager.download_fertig_d_kb_d_min", "Download fertig (%d KB, ~%d Min, %d DM Gebühr): %s.%s") % [
		int(size_kb), maxi(1, int(minutes)), phone_cost, blank.content_title,
		"  " + note if note != "" else ""]}


## Ein Bibliotheks-Programm per Modem herunterladen & installieren (landet als
## App auf der WERKBANK, keine Ziel-Diskette nötig). Prüft die Unlock-Regeln
## (ProgramLibrary) — so ist NICHT alles sofort da.
func download_program(program: Dictionary) -> Dictionary:
	if not connected():
		return {"ok": false, "text": Loc.t("sys.bbs_manager.nicht_verbunden", "Nicht verbunden.")}
	var pid: String = str(program.get("id", ""))
	var program_name: String = str(program.get("display_name", pid))
	var access: Dictionary = ProgramLibrary.install_status(pid, "bbs_download")
	if not bool(access.get("ok", false)):
		return {"ok": false, "text": str(access.get("reason",
			Loc.t("sys.bbs_manager.program_install_not_possible",
				"Dieses Programm kann nicht installiert werden.")))}
	var baud := float(maxi(300, connection_baud()))
	var size_kb := float(ProgramLibrary.install_size_kb(program))
	var minutes := size_kb * 8.0 / (baud / 1000.0) / 60.0
	var energy_cost := clampi(int(minutes * 0.6) + 2, 3, 30)
	if PlayerStats.energie < energy_cost:
		return {"ok": false, "text": Loc.t("sys.bbs_manager.zu_mude_fur_einen_so_langen", "Zu müde für einen so langen Download.")}
	# Installation zuerst committen. So bleiben Energie und Telefonrechnung bei
	# einem vollen DH0: unveraendert und der Download ist als Aktion atomar.
	if not ProgramLibrary.install(pid):
		return {"ok": false, "text": Loc.t("sys.bbs_manager.program_install_failed",
			"Installation fehlgeschlagen. Der Download wurde nicht berechnet.")}
	PlayerStats.use_energy(energy_cost)
	# Lange Downstreams sind die dicken Modem-Posten — wie die Einwahl laufen sie
	# auf die MONATLICHE Telefonrechnung (geteilte Leitung), nicht sofort bar.
	var phone_cost := int(ceil(minutes * _phone_base * 2.0))
	PhoneManager.add_phone_charge(phone_cost)
	PlayerStats.change_stat("wissen", 1)
	AudioManager.floppy_read()
	return {"ok": true, "text": Loc.t("sys.bbs_manager.installiert_s_d_dm_gebuhr_liegt", "Installiert: %s (%d DM Gebühr). Liegt auf der WERKBANK.") % [program_name, phone_cost]}


func to_dict() -> Dictionary:
	return {"visited": _visited.keys(), "assistant_history": _assistant_history.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	_visited = {}
	for id in d.get("visited", []):
		_visited[id] = true
	_assistant_history = {}
	var stored: Variant = d.get("assistant_history", {})
	if stored is Dictionary:
		for id: Variant in stored:
			var entries: Variant = stored[id]
			if entries is Array:
				_assistant_history[str(id)] = (entries as Array).slice(maxi(0, entries.size() - 18))
	current_board = {}
