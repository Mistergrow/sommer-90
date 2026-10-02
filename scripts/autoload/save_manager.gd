extends Node
## SaveManager — Speichern/Laden als JSON unter user://savegame.json.
## Jedes System liefert to_dict()/from_dict(); der SaveManager kennt keine
## Systemdetails und bleibt dadurch stabil, wenn Systeme wachsen.

const SAVE_VERSION := 1
const SLOT_COUNT := 3
const LEGACY_PATH := "user://savegame.json"   # alter Einzel-Spielstand → wird zu Slot 1
const MAX_SAVE_BYTES := 32 * 1024 * 1024
const LoadGameOverlayScript := preload("res://scripts/ui/load_game_overlay.gd")
const DevelopmentGate := preload("res://scripts/core/development_gate.gd")
const BuildChannel := preload("res://scripts/core/build_channel.gd")
const StateValidator := preload("res://scripts/autoload/save_state_validator.gd")
const SlotMenu := preload("res://scripts/ui/save_slot_menu.gd")
const REQUIRED_STATE_BLOCKS := ["stats", "time", "disks", "game"]

var active_slot: int = 1   # hierhin speichert F5 / das Systemmenü
var _screen_load_active := false
var _slot_selection_active := false
## Wahr nur waehrend alle Autoload-Bloecke eines Savegames eingespielt werden.
## Reaktive Systeme (Besuche, Erfolge, Audio) duerfen diesen Zwischenzustand
## nicht als echtes Gameplay behandeln.
var _restore_active := false


func _ready() -> void:
	_migrate_legacy()
	_recover_interrupted_saves()


## Fenster schliessen / Alt+F4 beendete das Spiel bisher ohne Speichern. Godot
## stellt die Close-Anfrage allen Knoten synchron zu, bevor der Baum endet; der
## Save (~3 ms) laeuft also vollstaendig durch. Ausserhalb des Spiels (Titel,
## Laden) lehnt save_game() selbst ab.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_on_exit()


## Einziger Speicherweg beim Beenden (Fenster und Systemmenue).
func save_on_exit() -> bool:
	if GameManager.state != GameManager.State.PLAYING:
		return false
	return save_game()


## Dateipfad eines Slots (1..SLOT_COUNT).
func slot_path(slot: int) -> String:
	return "user://%s_%d.json" % [BuildChannel.save_stem(), clampi(slot, 1, SLOT_COUNT)]


func backup_path(slot: int) -> String:
	return slot_path(slot) + ".bak"


func temporary_path(slot: int) -> String:
	return slot_path(slot) + ".tmp"


## Pfad des gerade aktiven Slots (für Tests/Diagnose).
func current_save_path() -> String:
	return slot_path(active_slot)


func is_restoring_game() -> bool:
	return _restore_active


## Alten Einzel-Spielstand einmalig zu Slot 1 machen (Abwärtskompatibilität).
func _migrate_legacy() -> void:
	# Die Demo darf niemals unbemerkt einen Spielstand der Vollversion
	# uebernehmen. Ihr erster Start bleibt ein eigener, sauberer Kanal.
	if BuildChannel.is_first_year_demo():
		return
	if FileAccess.file_exists(LEGACY_PATH) and not FileAccess.file_exists(slot_path(1)):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.rename(LEGACY_PATH.get_file(), slot_path(1).get_file())


## Wenn der Prozess genau zwischen „alt → .bak“ und „.tmp → aktuell“ beendet
## wurde, ist die letzte vollständige Datei weiterhin vorhanden und wird beim
## nächsten Start automatisch zurückgeholt.
func _recover_interrupted_saves() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for slot in range(1, SLOT_COUNT + 1):
		var target := slot_path(slot)
		var backup := backup_path(slot)
		if not FileAccess.file_exists(target) and FileAccess.file_exists(backup):
			dir.rename(backup.get_file(), target.get_file())
		if FileAccess.file_exists(temporary_path(slot)):
			dir.remove(temporary_path(slot).get_file())


## Hat ein Slot einen Spielstand? slot=-1 → gibt es IRGENDEINEN (für „Fortsetzen").
func has_save(slot: int = -1) -> bool:
	if slot == -1:
		for i in range(1, SLOT_COUNT + 1):
			if FileAccess.file_exists(slot_path(i)) or FileAccess.file_exists(backup_path(i)):
				return true
		return false
	return FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(backup_path(slot))


## Liest Primärstand und Sicherung durch dasselbe semantische Gate. Parsebares JSON
## allein ist kein Spielstand: Auch Kernblöcke und ihre tragenden Felder müssen
## vorhanden und plausibel sein, bevor irgendein Autoload verändert wird.
func _candidate_for_slot(slot: int) -> Dictionary:
	var primary := _decode_save_candidate(_read_json(slot_path(slot)))
	if bool(primary.get("ok", false)):
		primary["recovered"] = false
		return primary
	var backup := _decode_save_candidate(_read_json(backup_path(slot)))
	if bool(backup.get("ok", false)):
		backup["recovered"] = true
		backup["primary_reason"] = str(primary.get("reason", "unreadable"))
		return backup
	return {
		"ok": false,
		"recovered": false,
		"reason": str(primary.get("reason", backup.get("reason", "unreadable"))),
		"text": str(primary.get("text", backup.get("text", "Spielstand beschädigt."))),
	}


func _decode_save_candidate(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _invalid_candidate("unreadable", "Spielstand beschädigt oder unplausibel groß.")
	var state: Variant = raw
	var sig_ok := true
	# Sobald eines der Umschlagfelder existiert, muss der moderne Umschlag komplett
	# sein. Reine Legacy-Stände ohne beide Felder bleiben weiterhin kompatibel.
	if raw.has("data") or raw.has("sig"):
		if not raw.has("data") or not raw.has("sig") or not raw["data"] is Dictionary:
			return _invalid_candidate("invalid_envelope", "Der Spielstand-Umschlag ist unvollständig.")
		state = raw["data"]
		sig_ok = IntegrityManager.verify_state(state, str(raw["sig"]))
	if not state is Dictionary:
		return _invalid_candidate("invalid_state", "Der Spielstand enthält keinen gültigen Zustand.")

	var raw_version: Variant = state.get("version", 0)
	if not StateValidator._integer(raw_version):
		return _invalid_candidate("invalid_version", "Die Spielstand-Version ist ungültig.")
	var version := int(raw_version)
	if version < 0 or version > SAVE_VERSION:
		return _invalid_candidate("unsupported_version", "Spielstand-Format unbekannt.")
	if not BuildChannel.accepts_save_channel(str(state.get("build_channel", ""))):
		return _invalid_candidate("wrong_build_channel",
			"Dieser Spielstand gehoert zu einer anderen Ausgabe von Sommer '90.")
	for block: String in REQUIRED_STATE_BLOCKS:
		if not state.get(block, null) is Dictionary:
			return _invalid_candidate("missing_block", "Im Spielstand fehlt der Kernbereich »%s«." % block)

	var invalid_path := StateValidator.validate(state,
		TimeManager.TimeClock.day_end(TimeManager.night_budget_minutes))
	if not invalid_path.is_empty():
		return _invalid_candidate("invalid_state_field",
			"Der Spielstand enthält einen ungültigen Bereich: %s." % invalid_path)

	var stats: Dictionary = state["stats"]
	var raw_money: Variant = stats.get("geld", null)
	if not (raw_money is int or raw_money is float):
		return _invalid_candidate("invalid_stats", "Im Spielstand fehlt der Geldwert.")
	var money := float(raw_money)
	if is_nan(money) or is_inf(money) or money < -0.005:
		return _invalid_candidate("invalid_stats", "Der gespeicherte Geldwert ist unplausibel.")

	var disk_state: Dictionary = state["disks"]
	if not disk_state.get("disks", null) is Array:
		return _invalid_candidate("invalid_disks", "Die gespeicherte Diskettensammlung ist beschädigt.")
	var game: Dictionary = state["game"]
	if not game.get("flags", null) is Dictionary \
			or (game.has("location") and not (game.get("location") is String)):
		return _invalid_candidate("invalid_game", "Der gespeicherte Weltzustand ist beschädigt.")
	return {"ok": true, "state": state, "sig_ok": sig_ok, "reason": "", "text": ""}


func _invalid_candidate(reason: String, text: String) -> Dictionary:
	return {"ok": false, "state": {}, "sig_ok": false, "reason": reason, "text": text}


## Kurzinfo eines Slots für die Auswahl: {exists, date, summary}.
func slot_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {"exists": false, "loadable": false, "date": "", "summary": ""}
	var candidate := _candidate_for_slot(slot)
	if not bool(candidate.get("ok", false)):
		return {"exists": true, "loadable": false, "date": "", "summary": "BESCHÄDIGT"}
	var data: Dictionary = candidate["state"]
	var ident: Dictionary = data.get("identity", {})
	var stats: Dictionary = data.get("stats", {})
	var tm: Dictionary = data.get("time", {})
	var nm := str(ident.get("name", ident.get("player_name", "Spieler")))
	var yr := int(tm.get("year", 1990))
	var geld := float(stats.get("geld", 0.0))
	var summary := "%s · %d · %s" % [nm, yr, Currency.format(geld)]
	if bool(candidate.get("recovered", false)):
		summary += " · SICHERUNG"
	return {"exists": true, "loadable": true, "recovered": bool(candidate.get("recovered", false)),
		"date": str(data.get("saved_at", "")), "summary": summary}


## Einen Slot löschen.
func delete_slot(slot: int) -> bool:
	var paths := [slot_path(slot), backup_path(slot), temporary_path(slot)]
	if not paths.any(func(path: String) -> bool: return FileAccess.file_exists(path)):
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	for path: String in paths:
		if FileAccess.file_exists(path):
			dir.remove(path.get_file())
	return true


## Ein neuer Lauf braucht einen freien oder bewusst ausgewaehlten Slot.
func first_free_slot() -> int:
	for slot in range(1, SLOT_COUNT + 1):
		if not has_save(slot):
			return slot
	return -1


func on_new_game(slot: int = -1) -> bool:
	var selected := first_free_slot() if slot == -1 else slot
	if selected < 1 or selected > SLOT_COUNT:
		return false
	active_slot = selected
	return true


func choose_new_game_slot() -> int:
	if _slot_selection_active:
		return -1
	var available := first_free_slot()
	if available > 0:
		return available
	_slot_selection_active = true
	var menu := SlotMenu.new()
	menu.selecting_new_game = true
	get_tree().root.add_child(menu)
	var selected: int = await menu.selection_finished
	_slot_selection_active = false
	return selected


func save_game(slot: int = -1) -> bool:
	if GameManager.state != GameManager.State.PLAYING:
		return false
	if _restore_active:
		return false
	PlaytestTelemetry.note_system("save")
	if slot == -1:
		slot = active_slot
	if slot < 1 or slot > SLOT_COUNT:
		return false
	var state := {
		"version": SAVE_VERSION,
		"build_channel": BuildChannel.channel_id(),
		"saved_at": Time.get_datetime_string_from_system(),
		"identity": PlayerIdentity.to_dict(),
		"stats": PlayerStats.to_dict(),
		"time": TimeManager.to_dict(),
		"inventory": InventoryManager.to_dict(),
		"room": RoomManager.to_dict(),
		"disks": DiskManager.to_dict(),
		"npcs": NPCManager.to_dict(),
		"bbs": BBSManager.to_dict(),
		"orders": OrderManager.to_dict(),
		"rumors": RumorManager.to_dict(),
		"flea": FleaMarketManager.to_dict(),
		"dealer": DealerManager.to_dict(),
		"raid": RaidManager.to_dict(),
		"music": MusicManager.to_dict(),
		"memories": MemoryManager.to_dict(),
		"phone": PhoneManager.to_dict(),
		"narrative": NarrativeManager.to_dict(),
		"postcards": PostcardManager.to_dict(),
		"bank": BankManager.to_dict(),
		"tasks": TaskManager.to_dict(),
		"copytrade": CopyTradeManager.to_dict(),
		"scene_release": SceneReleaseManager.to_dict(),
		"jobs": JobManager.to_dict(),
		"quests": QuestManager.to_dict(),
		"achievements": AchievementManager.to_dict(),
		"minigames": MinigameManager.to_dict(),
		"events": EventManager.to_dict(),
		"amiga_games": AmigaGameManager.to_dict(),
		"photos": PhotoManager.to_dict(),
		"integrity": IntegrityManager.to_dict(),
		"game": GameManager.to_dict(),
		"sommer_game": SommerGameManager.to_dict(),
	}
	# Interne Messdaten gehoeren weder in Produktions-Saves noch in deren
	# Signatur. Alte Debug-Saves bleiben trotzdem abwaertskompatibel ladbar.
	if DevelopmentGate.enabled():
		state["playtest"] = PlaytestTelemetry.to_dict()
	var target := slot_path(slot)
	var temporary := temporary_path(slot)
	var backup := backup_path(slot)
	var encoded := JSON.stringify({"data": state, "sig": IntegrityManager.sign_state(state)}, "\t")
	if encoded.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		UIManager.toast(Loc.t("sys.save_manager.speichern_abgebrochen_spielstand_ist_unplausibel_gross", "Speichern abgebrochen: Spielstand ist unplausibel groß."))
		return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		UIManager.toast(Loc.t("sys.save_manager.speichern_fehlgeschlagen_datei_nicht_schreibbar", "Speichern fehlgeschlagen (Datei nicht schreibbar)."))
		return false
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(temporary) != encoded:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		UIManager.toast(Loc.t("sys.save_manager.write_incomplete", "Speichern fehlgeschlagen: Die Datei wurde nicht vollständig geschrieben."))
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		UIManager.toast(Loc.t("sys.save_manager.speichern_fehlgeschlagen_benutzerordner_nicht_erreichbar", "Speichern fehlgeschlagen (Benutzerordner nicht erreichbar)."))
		return false
	if FileAccess.file_exists(backup):
		dir.remove(backup.get_file())
	if FileAccess.file_exists(target) and dir.rename(target.get_file(), backup.get_file()) != OK:
		dir.remove(temporary.get_file())
		UIManager.toast(Loc.t("sys.save_manager.speichern_fehlgeschlagen_vorige_stand_blieb_erhalten", "Speichern fehlgeschlagen; der vorige Stand blieb erhalten."))
		return false
	if dir.rename(temporary.get_file(), target.get_file()) != OK:
		if FileAccess.file_exists(backup):
			dir.rename(backup.get_file(), target.get_file())
		UIManager.toast(Loc.t("sys.save_manager.speichern_fehlgeschlagen_sicherung_wurde_wiederhergestellt", "Speichern fehlgeschlagen; Sicherung wurde wiederhergestellt."))
		return false
	active_slot = slot
	UIManager.toast(Loc.t("sys.save_manager.gespeichert_in_slot_d_f9_zum", "Gespeichert in Slot %d. (F9 zum Laden)") % slot)
	return true


## Sichtbarer UI-Pfad: zeichnet denselben textfreien Sommer-Ladescreen für zwei
## Frames, bevor das synchrone Save-Einspielen den Main Thread kurz belegt.
## Direkte Tests/Migrationen behalten load_game() als deterministische API.
func load_game_with_screen(slot: int = -1) -> bool:
	if _screen_load_active:
		return false
	var selected_slot := active_slot if slot == -1 else slot
	if not has_save(selected_slot):
		UIManager.toast(Loc.t("sys.save_manager.kein_spielstand_gefunden", "Kein Spielstand gefunden."))
		return false
	_screen_load_active = true
	var overlay := LoadGameOverlayScript.new()
	overlay.name = "LoadGameOverlay"
	get_tree().root.add_child(overlay)
	await overlay.call("show_before_blocking_load")
	var success := load_game(selected_slot)
	if success:
		await overlay.call("stabilize_runtime")
	await overlay.call("finish", success)
	_screen_load_active = false
	return success


## UI-Einstieg für ein frisches Spiel. Die deterministische new_game()-API bleibt
## für Tests erhalten; Spieler sehen Reset, Zimmerbau und Renderer-Warmup unter
## demselben echten Ladebild wie beim Laden eines Spielstands.
func start_new_game_with_screen(slot: int = -1) -> bool:
	if _screen_load_active:
		return false
	_screen_load_active = true
	var selected := await choose_new_game_slot() if slot == -1 else slot
	if selected < 1 or selected > SLOT_COUNT:
		_screen_load_active = false
		return false
	var overlay := LoadGameOverlayScript.new()
	overlay.name = "LoadGameOverlay"
	get_tree().root.add_child(overlay)
	await overlay.call("show_before_blocking_load")
	GameManager.new_game(selected)
	await overlay.call("stabilize_runtime")
	await overlay.call("finish", true)
	_screen_load_active = false
	return true


func load_game(slot: int = -1) -> bool:
	if slot == -1:
		slot = active_slot
	if not has_save(slot):
		UIManager.toast(Loc.t("sys.save_manager.kein_spielstand_gefunden", "Kein Spielstand gefunden."))
		return false
	var candidate := _candidate_for_slot(slot)
	if not bool(candidate.get("ok", false)):
		UIManager.toast(str(candidate.get("text", "Spielstand beschädigt.")))
		return false
	var state: Dictionary = candidate["state"]
	var sig_ok := bool(candidate.get("sig_ok", true))
	var recovered := bool(candidate.get("recovered", false))
	_restore_active = true
	AchievementManager.begin_restore()
	# Dialog/Reveal/Portraetframes sind rein transient. Vor dem Einspielen alle
	# alten Sessions und Fenster entwerten, damit kein unsichtbarer Dialog aus
	# dem vorherigen Spielstand aktiv bleibt.
	DialogueManager.reset()
	UIManager.close_all_windows()
	# Reihenfolge: erst Werte, dann abgeleitete Systeme, zuletzt Spielzustand.
	PlayerIdentity.from_dict(state.get("identity", {}))
	PlayerStats.from_dict(state.get("stats", {}))
	TimeManager.from_dict(state.get("time", {}))
	# Additive Save-Heilung: neue vorinstallierte Sommerbench-Werkzeuge werden
	# auch in alten Spielstaenden sichtbar, ohne vorhandene Programme zu loeschen.
	ProgramLibrary.preinstall()
	InventoryManager.from_dict(state.get("inventory", {}))
	RoomManager.from_dict(state.get("room", {}))
	DiskManager.from_dict(state.get("disks", {}))
	NPCManager.from_dict(state.get("npcs", {}))
	BBSManager.from_dict(state.get("bbs", {}))
	OrderManager.from_dict(state.get("orders", {}))
	RumorManager.from_dict(state.get("rumors", {}))
	FleaMarketManager.from_dict(state.get("flea", {}))
	DealerManager.from_dict(state.get("dealer", {}))
	RaidManager.from_dict(state.get("raid", {}))
	MusicManager.from_dict(state.get("music", {}))
	MemoryManager.from_dict(state.get("memories", {}))
	PhoneManager.from_dict(state.get("phone", {}))
	NarrativeManager.from_dict(state.get("narrative", {}))
	PostcardManager.from_dict(state.get("postcards", {}))
	BankManager.from_dict(state.get("bank", {}))
	TaskManager.from_dict(state.get("tasks", {}))
	CopyTradeManager.from_dict(state.get("copytrade", {}))
	SceneReleaseManager.from_dict(state.get("scene_release", {}))
	JobManager.from_dict(state.get("jobs", {}))
	QuestManager.from_dict(state.get("quests", {}))
	AchievementManager.from_dict(state.get("achievements", {}))
	MinigameManager.from_dict(state.get("minigames", {}))
	EventManager.from_dict(state.get("events", {}))
	AmigaGameManager.from_dict(state.get("amiga_games", {}))
	PhotoManager.from_dict(state.get("photos", {}))
	if DevelopmentGate.enabled():
		PlaytestTelemetry.from_dict(state.get("playtest", {}))
	IntegrityManager.from_dict(state.get("integrity", {}))
	GameManager.from_dict(state.get("game", {}))
	# Optionaler, additiver Block: alte Spielstaende rekonstruieren vergangene
	# Engine-Jahre, ohne den Beitrag des aktuellen Sommers zu verschenken.
	SommerGameManager.from_dict(state.get("sommer_game", {}))
	# Erst hier sind Queststatus UND Weltflags geladen. Alte 1992-Saves hatten
	# zwar die Kleinserien-Entscheidung, aber keinen persistenten Umsatzvertrag.
	SceneReleaseManager.reconcile_game_distribution()
	# TaskManager wird absichtlich vor GameManager geladen. Erst jetzt stehen
	# sowohl Disketten als auch persistente Ziel-UIDs bereit, um alte
	# Virus-Verdacht-Aufgaben ohne neue Infektion korrekt abzugleichen.
	VirusManager.reconcile_scare_task()
	PlaytestTelemetry.note_system("load")
	# Signatur-Flag NACH from_dict setzen, sonst überschreibt der (manipulierte)
	# integrity-Block das Flag wieder auf „sauber".
	if not sig_ok:
		IntegrityManager.flag("savegame_signatur")
	UIManager.reset_computer()   # zurück am ausgeschalteten Amiga (Power-Zustand wird nicht gespeichert)
	AchievementManager.end_restore()
	_restore_active = false
	if recovered:
		_promote_backup(slot)
	active_slot = slot
	UIManager.toast(_load_notice(slot, recovered))
	return true


## Ladehinweise werden erst im Moment der Anzeige lokalisiert. Ein englischer
## Spielstand uebernimmt dadurch keinen zuvor in Deutsch erzeugten Klartext in
## die primaere Ereigniskarte des HUD.
func _load_notice(slot: int, recovered: bool) -> String:
	var key := "sys.save_manager.backup_slot_restored" if recovered else \
		"sys.save_manager.slot_loaded_welcome"
	var fallback := "Sicherung von Slot %d wiederhergestellt." if recovered else \
		"Spielstand (Slot %d) geladen. Willkommen zurück in den 90ern!"
	return Loc.t(key, fallback) % slot


## Nach erfolgreichem Laden der Sicherung wird sie wieder zum Primärstand. Sonst
## könnte der nächste Speichervorgang die einzige gute .bak-Datei durch den
## beschädigten Primärstand ersetzen.
func _promote_backup(slot: int) -> void:
	var backup := backup_path(slot)
	if not FileAccess.file_exists(backup):
		return
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var target := slot_path(slot)
	if FileAccess.file_exists(target) and dir.remove(target.get_file()) != OK:
		push_warning("Beschädigter Primärstand konnte nicht entfernt werden: Slot %d" % slot)
		return
	if dir.rename(backup.get_file(), target.get_file()) != OK:
		push_warning("Sicherung konnte nicht zum Primärstand werden: Slot %d" % slot)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_SAVE_BYTES:
		if file != null:
			file.close()
		return null
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	return parser.data if error == OK else null
