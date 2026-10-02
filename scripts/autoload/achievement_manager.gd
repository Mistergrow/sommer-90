extends Node
## AchievementManager — Steam-Erfolge (freigegebenes Wunsch-Paket).
##
## Bedingungsbasiert (wie QuestManager): jeder Erfolg hat eine cond, die
## `evaluate()` nach jedem Effekt, Tageswechsel und Gespräch prüft. Manche
## Auslöser setzen zusätzlich ein Flag direkt am Ort des Geschehens (note()).
## Freischalten ist idempotent: Toast + Sound + Speichern, einmalig.
## Icons (256×256 RGBA): assets/ui/achievements/<id>.png + <id>_locked.png.
## Der vollständige Satz wird durch achievement_art_check.gd abgesichert.
##
## Daten: data/achievements.json. Basis für die spätere Steamworks-Anbindung.

signal achievement_unlocked(id: String)
signal achievements_changed

const CONFIG := "res://data/achievements.json"

var _defs: Array = []
var _unlocked: Dictionary = {}   # id -> true
var _busy := false
## Save-Hydration kann absichtlich mehrere reaktive Signale ausloesen
## (Disketten, Zeit, Quests). Dabei darf ein bereits gespeicherter Erfolg nicht
## kurz erneut Toast, Foto und Muenzklang erzeugen, bevor sein eigener Block
## geladen wurde. Verschachtelbar, damit Migrationen denselben Vertrag nutzen.
var _restore_depth := 0
var _restore_changed := false


func _ready() -> void:
	if FileAccess.file_exists(CONFIG):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if d is Dictionary:
			_defs = d.get("achievements", [])
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(func() -> void: evaluate())
	var dm := get_node_or_null("/root/DiskManager")
	if dm != null and dm.has_signal("disks_changed"):
		dm.disks_changed.connect(func() -> void: evaluate())


func all() -> Array:
	return _defs


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func unlocked_count() -> int:
	return _unlocked.size()


func total() -> int:
	return _defs.size()


func def(id: String) -> Dictionary:
	for a in _defs:
		if str(a.get("id", "")) == id:
			return a
	return {}


## Direkt freischalten (falls ein Auslöser einfacher direkt ruft als über cond).
func unlock(id: String, silent: bool = false) -> void:
	if _unlocked.has(id):
		return
	# Anti-Cheat: manipulierte Spielstände schalten keine Erfolge mehr frei.
	var ig := get_node_or_null("/root/IntegrityManager")
	if ig != null and not bool(ig.call("ok")):
		return
	var a := def(id)
	if a.is_empty():
		return
	_unlocked[id] = true
	if silent or _restore_depth > 0:
		_restore_changed = true
		return
	achievement_unlocked.emit(id)
	achievements_changed.emit()
	var localized_title := Loc.t("ach.%s.title" % id, str(a.get("title", id)))
	var localized_desc := Loc.t("ach.%s.desc" % id, str(a.get("desc", "")))
	var ui := get_node_or_null("/root/UIManager")
	if ui != null:
		ui.call("toast", Loc.t_format("ui.achievement.unlocked", "🏆 Erfolg freigeschaltet: %s", [localized_title]))
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("play", "coins", 0.0)
	# Jeder Erfolg wandert als Schnappschuss ins Foto-Album (einmalig).
	var pm := get_node_or_null("/root/PhotoManager")
	if pm != null:
		pm.call("capture", "🏆 " + localized_title, localized_desc, "ach_" + id, true)


## Ein Auslöser-Flag setzen UND sofort prüfen (aus Gameplay-Code aufgerufen).
func note(flag: String) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.get("flags")[flag] = true
	# Gameplay-Flags sind zugleich Questziele. Ohne die sofortige Auswertung
	# wurde der Karton-Auftrag nach dem echten Amiga-Boot erst beim Schlafen als
	# erledigt markiert — der Spieler landete dazwischen in einem leeren Zustand.
	var qm := get_node_or_null("/root/QuestManager")
	if qm != null:
		qm.call("evaluate")
	evaluate()


## Alle noch nicht erreichten Erfolge prüfen (reentrant-sicher).
func evaluate(silent: bool = false) -> void:
	if _busy:
		return
	_busy = true
	for a in _defs:
		var id := str(a.get("id", ""))
		if not _unlocked.has(id) and _cond_met(a.get("cond", {})):
			unlock(id, silent)
	_busy = false


## Klammer um das vollstaendige Einspielen eines Savegames. Reaktive
## Zwischenergebnisse werden logisch uebernommen, bleiben aber akustisch und
## visuell stumm. Nach dem letzten Block folgt genau ein stiller Abgleich.
func begin_restore() -> void:
	_restore_depth += 1


func end_restore() -> void:
	if _restore_depth <= 0:
		return
	_restore_depth -= 1
	if _restore_depth > 0:
		return
	evaluate(true)
	if _restore_changed:
		_restore_changed = false
		achievements_changed.emit()


# ------------------------------------------------------------- Bedingungen

func _flag(flag_name: String) -> bool:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return false
	return bool(gm.get("flags").get(flag_name, false))


func _cond_met(cond: Dictionary) -> bool:
	if cond.is_empty():
		return false
	if cond.has("flag") and not _flag(str(cond["flag"])):
		return false
	if cond.has("year_min") and TimeManager.year < int(cond["year_min"]):
		return false
	if cond.has("money_min") and PlayerStats.geld < int(cond["money_min"]):
		return false
	if cond.has("disks_min") and DiskManager.media_count() < int(cond["disks_min"]):
		return false
	if cond.has("boxed_games_min") and _unique_boxed_games() < int(cond["boxed_games_min"]):
		return false
	if cond.has("tracks_min") and MusicManager.owned.size() < int(cond["tracks_min"]):
		return false
	if cond.has("quest_done") and not QuestManager.is_done(str(cond["quest_done"])):
		return false
	if cond.has("quests_done_min") and QuestManager.done_count() < int(cond["quests_done_min"]):
		return false
	if cond.has("all_quests") and QuestManager.done_count() < QuestManager.total():
		return false
	if cond.has("account_open"):
		var bm := get_node_or_null("/root/BankManager")
		if bm == null or not bool(bm.get("account_open")):
			return false
	if cond.has("talked_all"):
		for npc in cond["talked_all"]:
			if not _flag("talked_" + str(npc)):
				return false
	if cond.has("disk_checked"):
		var found := false
		for dsk in DiskManager.media_disks():
			if dsk.checked and dsk.content_type != "leer":
				found = true
				break
		if not found:
			return false
	return true


## Vollstaendige OVP-Saetze, pro Softwaretitel genau einmal. Doppelte Budgetboxen
## sind weiter wertvoll, farmen aber nicht die 50er-/100er-Sammlerleiter.
func _unique_boxed_games() -> int:
	return DiskManager.unique_boxed_game_count()


func to_dict() -> Dictionary:
	return {"unlocked": _unlocked}


func from_dict(d: Dictionary) -> void:
	var restored: Variant = d.get("unlocked", {})
	_unlocked = (restored as Dictionary).duplicate(true) if restored is Dictionary else {}
	if _restore_depth > 0:
		_restore_changed = true
	else:
		achievements_changed.emit()


func reset() -> void:
	_unlocked = {}
	_restore_depth = 0
	_restore_changed = false
	achievements_changed.emit()
