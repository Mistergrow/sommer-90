extends Node
## PostcardManager — Brieffreund-Korrespondenz per Postkarte (Phase D, Menschen).
##
## Wenn ein Freund wegzieht (Sven ab 1995), schreibt er Postkarten. Der Spieler
## kann ANTWORTEN — die Antwort schaltet die naechste Karte im Faden frei
## (needs_reply) und kann Sven dazu bringen, etwas zu schicken (on_arrive-Effekte,
## z. B. eine Diskette zum Tauschen). Anders als der Anrufbeantworter braucht Post
## KEIN Geraet: sie kommt an. Es wird hoechstens EINE faellige Karte pro Tag
## zugestellt, damit ein echter Hin-und-Her-Rhythmus entsteht.
##
## Daten: data/postcards.json (datengetrieben, npc-neutral ueber 'from').

const CONFIG := "res://data/postcards.json"

signal postcards_changed

var inbox: Array = []          # [{id, from, from_name, motiv, text, date, read, replies}]
var _received: Array = []       # bereits zugestellte IDs (dedupe)
var _replied: Dictionary = {}   # card_id -> {id, text}
var _last_day := -9999          # Spieltag der letzten Zustellung (Rhythmus)
var _defs: Array = []


func _ready() -> void:
	_load_defs()
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(_on_day_changed)


func unread_count() -> int:
	var c := 0
	for m in inbox:
		if not bool(m.get("read", false)):
			c += 1
	return c


func mark_read(id: String) -> void:
	for m in inbox:
		if str(m.get("id", "")) == id:
			m["read"] = true
	postcards_changed.emit()


func has_replied(card_id: String) -> bool:
	return _replied.has(card_id)


func reply_text(card_id: String) -> String:
	var r: Dictionary = _replied.get(card_id, {})
	var reply_id := str(r.get("id", ""))
	return Loc.t("card.%s.replies.%s.text" % [card_id, reply_id], str(r.get("text", "")))


## Lokalisierte Ansicht einer gespeicherten Karte. Persistiert bleiben nur die
## historischen Quelldaten; ein Sprachwechsel kann deshalb keine gemischten
## deutschen/englischen Postkarten hinterlassen.
func localized_card(card: Dictionary) -> Dictionary:
	var out := card.duplicate(true)
	var card_id := str(card.get("id", ""))
	var source := card
	for definition: Dictionary in _defs:
		if str(definition.get("id", "")) == card_id:
			source = definition
			break
	out["text"] = Loc.t("card.%s.text" % card_id, str(source.get("text", card.get("text", ""))))
	var motiv_source := str(source.get("motiv", card.get("motiv", "")))
	out["motiv"] = Loc.t("card.%s.motiv" % card_id, motiv_source) if not motiv_source.is_empty() else ""
	var replies: Array = []
	for reply_entry: Dictionary in source.get("replies", card.get("replies", [])):
		var visible := reply_entry.duplicate(true)
		var reply_id := str(reply_entry.get("id", ""))
		visible["text"] = Loc.t("card.%s.replies.%s.text" % [card_id, reply_id],
			str(reply_entry.get("text", "")))
		replies.append(visible)
	out["replies"] = replies
	return out


## Auf eine Karte antworten: Effekte anwenden; schaltet ueber needs_reply die
## naechste Karte des Fadens frei. Eine Karte wird nur EINMAL beantwortet.
func reply(card_id: String, reply_id: String) -> bool:
	if _replied.has(card_id):
		return false
	for m: Dictionary in inbox:
		if str(m.get("id", "")) != card_id:
			continue
		for rep: Dictionary in m.get("replies", []):
			if str(rep.get("id", "")) == reply_id:
				var result: Dictionary = EventManager.apply_effects(rep.get("effects", []))
				if not bool(result.get("ok", false)):
					return false
				_replied[card_id] = {"id": reply_id, "text": str(rep.get("text", ""))}
				m["read"] = true
				AchievementManager.note("replied_postcard")
				# Antwort raus → Board-Aufgabe abhaken.
				var tmgr := get_node_or_null("/root/TaskManager")
				if tmgr != null:
					tmgr.call("complete", "task_reply_" + card_id)
				AudioManager.relay()
				postcards_changed.emit()
				return true
	return false


func _on_day_changed() -> void:
	_deliver_due()


## Hoechstens EINE faellige Karte pro Tag zustellen (natuerlicher Rhythmus).
func _deliver_due() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	var year := int(tm.get("year")) if tm != null else 1990
	var day := int(tm.get("day_counter")) if tm != null else 0
	for def in _defs:
		var id := str(def.get("id", ""))
		if id == "" or id in _received:
			continue
		if year < int(def.get("year_from", 0)):
			continue
		if def.has("needs_reply") and not _replied.has(str(def["needs_reply"])):
			continue
		if def.has("needs_flag") and not _flag(str(def["needs_flag"])):
			continue
		if day < _last_day + int(def.get("gap_days", 4)):
			continue
		# Eine physische Beilage darf nicht verschwinden: Erst die gesamte
		# Ankunftstransaktion committen, dann die Karte als zugestellt markieren.
		var arrival_result: Dictionary = EventManager.apply_effects(def.get("on_arrive", []))
		if not bool(arrival_result.get("ok", false)):
			return
		_received.append(id)
		_last_day = day
		var date_str := "?"
		if tm != null and tm.has_method("date_string"):
			date_str = str(tm.call("date_string"))
		inbox.append({
			"id": id,
			"from": str(def.get("from", "")),
			"from_name": str(def.get("from_name", "?")),
			"motiv": str(def.get("motiv", "")),
			"text": str(def.get("text", "")),
			"date": date_str, "read": false,
			"replies": def.get("replies", []),
		})
		# Karte mit Antwortmöglichkeiten → Aufgabe ans Board („… beantworten").
		if not (def.get("replies", []) as Array).is_empty():
			var tmgr := get_node_or_null("/root/TaskManager")
			if tmgr != null:
				tmgr.call("add_task", {"id": "task_reply_" + id,
					"title": Loc.t("sys.postcard_manager.reply_task",
						"Postkarte von %s beantworten") % str(def.get("from_name", "?")),
					"note": Loc.t("sys.postcard_manager.mailbox_task_note",
						"Liegt direkt im POSTKASTEN der linken Navigation.")})
		var ui := get_node_or_null("/root/UIManager")
		if ui != null:
			ui.call("toast", Loc.t("sys.postcard_manager.postcard_arrived",
				"✉ Post: eine Postkarte von %s liegt im Postkasten.") % str(def.get("from_name", "?")))
		postcards_changed.emit()
		return   # nur eine Karte pro Tag


func _flag(fname: String) -> bool:
	# Robust ueber den Autoload-KNOTEN (nicht den globalen Bezeichner, der bei
	# gleichnamigem class_name auf die Klasse statt den Knoten zeigen kann).
	var gmn := get_node_or_null("/root/GameManager")
	if gmn == null:
		return false
	var flags: Dictionary = gmn.get("flags")
	return bool(flags.get(fname, false))


func to_dict() -> Dictionary:
	return {"inbox": inbox, "received": _received, "replied": _replied, "last_day": _last_day}


func from_dict(d: Dictionary) -> void:
	inbox = d.get("inbox", [])
	_received = d.get("received", [])
	_replied = d.get("replied", {})
	_last_day = int(d.get("last_day", -9999))
	postcards_changed.emit()


func reset() -> void:
	inbox = []
	_received = []
	_replied = {}
	_last_day = -9999
	postcards_changed.emit()


func _load_defs() -> void:
	if not FileAccess.file_exists(CONFIG):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if parsed is Dictionary:
		_defs = parsed.get("cards", [])
