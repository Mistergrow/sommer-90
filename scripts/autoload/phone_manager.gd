extends Node
## PhoneManager — Telefon/Anrufbeantworter (Phase D, Telefonsystem-Fundament).
##
## REALISTISCH: Ein Anruf kommt so oder so (Bedingungen wie bei Events). Nur mit
## GEKAUFTEM + ANGESCHLOSSENEM Anrufbeantworter wird die Nachricht aufgezeichnet.
## OHNE Gerät nehmen die Eltern ab: Man weiß, WER angerufen hat (Board-Aufgabe),
## aber nicht was — die Info holt man per Rückruf (Telefon/Telefonzelle) oder
## beim persönlichen Treffen nach (_pending → take_pending).
##
## Nachrichten-Definitionen: data/phone_messages.json (datengetrieben).

const CONFIG := "res://data/phone_messages.json"
const BOOTH_COST := 1          # DM pro Gespräch aus der Telefonzelle

signal messages_changed
signal phone_changed

var machine_connected := false
var messages: Array = []      # [{id, from, text, heard, day, npc?, dialogue?}]
var player_number := ""        # eigener Anschluss im Format "XX XX XX"

var _received: Array = []      # bereits eingegangene/verpasste IDs (dedupe)
var _pending: Dictionary = {}  # npc_id -> {id, from, text}: aktuellster spielbarer Rueckruf
var _defs: Array = []
## Das Notizbuch ist kein allwissendes Adressverzeichnis. Eine Nummer erscheint
## erst, wenn die Person schon bekannt ist, selbst angerufen hat oder ein Kontakt
## ausdrücklich vermittelt wurde. Stefan ist als bester Freund die einzige
## garantierte Startnummer.
var known_contacts: Array = []

# ---- Telefonrechnung: Gespräche & Modem-Sessions kosten; monatlich kommt die
# Rechnung (Task + Toast). Bleibt sie über der Sperrgrenze offen, sperrt Papa
# das Telefon (kein Wählen, kein Modem) bis bezahlt ist. Zahlen: Postamt/Bank.
const CALL_COST := 1           # DM je Ortsgespräch (eigene Leitung)
const CALL_COST_FERN := 3      # DM je Ferngespräch (mit Vorwahl)
const BBS_COST := 2            # DM je Modem-Einwahl
const BILL_LOCK_LIMIT := 40    # ab dieser offenen Summe sperrt Papa die Leitung

var bill_open := 0             # aufgelaufene, noch nicht in Rechnung gestellte DM
var bill_due := 0              # offene Rechnung (fällig, zu bezahlen)
var _bill_month := -1          # Monat der letzten Rechnungsstellung
var _last_from_booth := false  # kam der laufende Wählversuch aus der Zelle?


func _ready() -> void:
	_load_defs()
	_ensure_number()
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(_on_day_changed)
	if tm != null and tm.has_signal("slot_changed"):
		tm.slot_changed.connect(func(_slot: int) -> void: _on_slot_incoming())


## Eigene Rufnummer einmalig auswürfeln (erste Ziffer nie 0 — das ist die Amtsnull).
func _ensure_number() -> void:
	if player_number == "":
		player_number = "%d%d %d%d %d%d" % [randi_range(2, 9), randi_range(0, 9),
			randi_range(0, 9), randi_range(0, 9), randi_range(0, 9), randi_range(0, 9)]


func owns_machine() -> bool:
	return PlayerStats.has_hardware("answering_machine")


func is_ready() -> bool:
	return owns_machine() and machine_connected


## Gerät ans Telefon anschließen (einmalig, nachdem es gekauft wurde).
func connect_machine() -> void:
	if owns_machine() and not machine_connected:
		machine_connected = true
		messages_changed.emit()


func unheard_count() -> int:
	var c := 0
	for m in messages:
		if not bool(m.get("heard", false)):
			c += 1
	return c


## Offene Rückrufhinweise für den Notizblock. Kopien verhindern, dass die UI
## versehentlich den persistenten Telefonzustand verändert.
func pending_callbacks() -> Array:
	var out: Array = []
	for npc_id: String in _pending:
		var entry: Dictionary = (_pending[npc_id] as Dictionary).duplicate(true)
		entry["npc_id"] = npc_id
		entry["text"] = localized_message_text(entry)
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("from", "")).naturalnocasecmp_to(str(b.get("from", ""))) < 0)
	return out


## Telefontexte bleiben im Save als deutsche Quelldaten erhalten. Jede UI liest
## sie anhand der stabilen Nachrichten-ID in der aktuell gewaehlten Sprache.
func localized_message_text(message: Dictionary) -> String:
	var id := str(message.get("id", ""))
	var source := str(message.get("text", ""))
	var definition := _call_definition(id)
	if not definition.is_empty():
		source = str(definition.get("text", source))
	return Loc.t("phone.%s.text" % id, source) if not id.is_empty() else source


func known_contact_ids() -> Array:
	var out: Array = []
	for npc_id: Variant in known_contacts:
		var id := str(npc_id)
		if NPCManager.get_npc(id).has("phone") and not out.has(id):
			out.append(id)
	return out


func knows_contact(npc_id: String) -> bool:
	return npc_id in known_contacts


func learn_contact(npc_id: String) -> void:
	if npc_id == "" or not NPCManager.get_npc(npc_id).has("phone") or npc_id in known_contacts:
		return
	known_contacts.append(npc_id)
	phone_changed.emit()


func mark_heard(id: String) -> void:
	for m: Dictionary in messages:
		if str(m.get("id", "")) == id:
			if bool(m.get("heard", false)):
				continue
			m["heard"] = true
			_activate_recorded_story_call(m)
	messages_changed.emit()


## Ein Skript-Anruf auf Band ist nicht dasselbe wie ein erledigtes Gespräch:
## Nach dem Abhören wird ein garantierter Rückruf angelegt. Damit gehen
## Dialogeffekte (Quest-Intro, Flags, Entscheidungen) nicht verloren.
func _activate_recorded_story_call(message: Dictionary) -> void:
	var def := _call_definition(str(message.get("id", "")))
	var dialogue := str(message.get("dialogue", def.get("dialogue", "")))
	var npc_id := str(message.get("npc", def.get("npc", "")))
	if dialogue == "" or npc_id == "":
		return
	_queue_callback(
		npc_id,
		str(message.get("id", def.get("id", ""))),
		str(message.get("from", def.get("from", "?"))),
		str(message.get("text", def.get("text", ""))),
		dialogue,
		true)


func _call_definition(id: String) -> Dictionary:
	for def: Dictionary in _defs:
		if str(def.get("id", "")) == id:
			return def
	return {}


func delete_message(id: String) -> void:
	messages = messages.filter(func(m: Dictionary) -> bool: return str(m.get("id", "")) != id)
	messages_changed.emit()


func _on_day_changed() -> void:
	_check_calls()
	_check_bill()


## Monatswechsel → Rechnung stellen. Offene Rechnung über der Grenze = Sperre.
func _check_bill() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm == null:
		return
	var month := int(tm.get("month"))
	if _bill_month < 0:
		_bill_month = month
		return
	if month == _bill_month:
		return
	_bill_month = month
	if bill_open <= 0:
		return
	bill_due += bill_open
	bill_open = 0
	var tmgr := get_node_or_null("/root/TaskManager")
	if tmgr != null:
		tmgr.call("add_task", {"id": "task_phone_bill_%d" % int(tm.get("day_counter")),
			"title": Loc.t("sys.phone_manager.pay_phone_bill_task",
				"Telefonrechnung bezahlen (%d DM)") % bill_due,
			"note": Loc.t("sys.phone_manager.phone_bill_task_note",
				"Am Postamt oder bei der Bank. Ab %d DM offen sperrt Papa das Telefon!") % BILL_LOCK_LIMIT})
	var ui := get_node_or_null("/root/UIManager")
	if ui != null:
		ui.call("toast", Loc.t("sys.phone_manager.phone_bill_arrived",
			"☎ Telefonrechnung ist da: %d DM. %s") % [bill_due,
			Loc.t("sys.phone_manager.line_locked_angry", "PAPA TOBT — Leitung gesperrt!")
			if line_locked() else Loc.t("sys.phone_manager.dad_watching", "Papa guckt schon streng.")])


func line_locked() -> bool:
	return bill_due >= BILL_LOCK_LIMIT


## Modem-Einwahl (BBS) auf die Rechnung. false = Leitung gesperrt.
func modem_session() -> bool:
	if line_locked():
		return false
	bill_open += BBS_COST
	return true


## Zusätzliche Modem-Gebühr auf die MONATLICHE Telefonrechnung buchen (z.B. lange
## Downloads über die geteilte Leitung) — damit alle Modem-Kosten gleich behandelt
## werden (Papa sieht sie am Monatsersten, statt sofort bar).
func add_phone_charge(dm: int) -> void:
	bill_open += maxi(0, dm)


## Rechnung bezahlen (bar). true = bezahlt (auch Teilzahlung ausgeschlossen — ganz oder gar nicht).
func pay_bill() -> bool:
	if bill_due <= 0:
		return false
	if not PlayerStats.spend_money(bill_due):
		return false
	bill_due = 0
	AchievementManager.note("paid_bill")
	phone_changed.emit()
	var tmgr := get_node_or_null("/root/TaskManager")
	if tmgr != null:
		for t in tmgr.get("tasks"):
			var tid := str(t.get("id", ""))
			if tid.begins_with("task_phone_bill_"):
				tmgr.call("complete", tid)
	return true


## Fällige Anrufe prüfen (Abwesenheits-/Catch-up-Pfad): aufzeichnen bei AB, sonst
## Eltern-Notiz. (Das LIVE-Klingeln zu Hause macht _on_slot_incoming.)
func _check_calls() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	var year := int(tm.get("year")) if tm != null else 1992
	var day := int(tm.get("day_counter")) if tm != null else 0
	for def in _defs:
		if _call_due(def, year, day):
			var is_story := str(def.get("dialogue", "")) != ""
			if is_story and not GameManager.claim_story_beat("call:" + str(def.get("id", ""))):
				continue
			_received.append(str(def.get("id", "")))
			_deliver_call(def, day)


## Ist dieser Anruf jetzt fällig (Jahr/Tag) und noch nicht abgehandelt?
func _call_due(def: Dictionary, year: int, day: int) -> bool:
	var id := str(def.get("id", ""))
	if id == "" or id in _received:
		return false
	if day < int(def.get("day_from", 0)):
		return false
	if year < int(def.get("year_from", 0)):
		return false
	if def.has("year_to") and year > int(def["year_to"]):
		return false
	if not _age_gate_open(def, year):
		return false
	# Der Quest-Director teilt jeden Sommer in sechs dramaturgische Wochen. Ein
	# Story-Anruf darf diese Planung nicht umgehen: Genau das ließ Herr Voss
	# früher bereits am ersten 1992er Ferientag von der Abschlussprüfung reden,
	# obwohl die Schulabschluss-Quest erst für Woche 5 vorgesehen ist. Das
	# optionale `campaign_quest` bindet den Anruf an denselben Slot wie die Quest;
	# ältere, rein kalendarische/flavour Anrufe bleiben unverändert.
	if not _campaign_gate_open(def, year):
		return false
	# Flag-Gates: ein Anruf kann statt/zusätzlich zum Datum an einen Spielzustand
	# hängen (z. B. Stefan ruft an, SOBALD der Amiga läuft: requires_flag booted_amiga).
	if def.has("requires_flag") and not _flag_truthy(GameManager.flags.get(str(def["requires_flag"]), false)):
		return false
	if def.has("unless_flag") and _flag_truthy(GameManager.flags.get(str(def["unless_flag"]), false)):
		return false
	# Fakten-Gate: Welt-Fakten (facts.json, z. B. sven_weg/internet_normal) als Auslöser.
	if def.has("requires_fact") and not NarrativeManager.fact_true(str(def["requires_fact"])):
		return false
	# Sammel-Meilenstein (Pacing!): erst ab N Spielen in der Box — der Spieler soll
	# zwischen den Beats SAMMELN/KOPIEREN statt Quest auf Quest zu bekommen.
	if def.has("requires_games"):
		var games := 0
		for disk in DiskManager.disks:
			if str(disk.content_type) == "spiel":
				games += 1
		if games < int(def["requires_games"]):
			return false
	return true


## Gemeinsames Wochen-Gate für Quest und zugehörigen Einführungsanruf. Bei einem
## späteren Jahr bleibt der Anruf als Backlog nachholbar; vor seinem historischen
## Jahr oder vor der geplanten Sommerwoche ist er dagegen unsichtbar.
func _campaign_gate_open(def: Dictionary, at_year: int) -> bool:
	var quest_id := str(def.get("campaign_quest", ""))
	if quest_id.is_empty():
		return true
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null or not quests.has_method("campaign_slot"):
		return false
	var gate: Dictionary = quests.call("campaign_slot", quest_id)
	if gate.is_empty():
		return false
	var planned_year := int(gate.get("year", 0))
	if at_year < planned_year:
		return false
	if at_year > planned_year:
		return true
	if TimeManager.year != at_year:
		return false
	var progress: Dictionary = TimeManager.campaign_progress()
	return str(progress.get("phase", "")) == "summer" \
		and int(progress.get("week", 0)) >= int(gate.get("week", 1))


func _age_gate_open(def: Dictionary, at_year: int) -> bool:
	if not def.has("age_min"):
		return true
	return PlayerIdentity.age_at(at_year, TimeManager.month, TimeManager.day) >= int(def["age_min"])


func _flag_truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		return not value.strip_edges().is_empty() and value.to_lower() not in ["false", "0", "none"]
	return value != null


## Anruf im NICHT-abgehoben-Fall: Anrufbeantworter (wenn bereit) ODER Eltern-Notiz
## + Rückruf-Aufgabe (_pending, nachholbar).
func _deliver_call(def: Dictionary, day: int) -> void:
	var id := str(def.get("id", ""))
	var npc_id := str(def.get("npc", ""))
	var caller := str(def.get("from", "?"))
	var dialogue := str(def.get("dialogue", ""))
	learn_contact(npc_id)
	if is_ready():
		messages.append({
			"id": id, "from": caller,
			"text": str(def.get("text", "")), "heard": false, "day": day,
			"npc": npc_id, "dialogue": dialogue,
		})
		messages_changed.emit()
		return
	_queue_callback(
		npc_id if npc_id != "" else caller,
		id,
		caller,
		str(def.get("text", "")),
		dialogue,
		false)
	var ui := get_node_or_null("/root/UIManager")
	if ui != null:
		ui.call("toast", Loc.t("sys.phone_manager.missed_call_mom",
			"Mama ruft: »Der %s hat für dich angerufen — meld dich mal!«") % caller)


func _queue_callback(npc_id: String, id: String, caller: String,
		text: String, dialogue: String, from_machine: bool) -> bool:
	if npc_id == "":
		return false
	if _pending.has(npc_id):
		var existing: Dictionary = _pending[npc_id]
		if str(existing.get("id", "")) == id:
			return true
		# Ein NPC kann in einem nachgeholten Spielstand mehrere historische
		# Story-Anrufe besitzen. Der spaetere darf den aktuell spielbaren Rueckruf
		# niemals ueberschreiben: Sonst bleibt dessen Board-Zeile ohne Dialog zurueck.
		# Die empfangene ID bleibt erhalten; reconcile_story_timeline() stellt sie
		# nach Verbrauch des aelteren Rueckrufs in Definitionsreihenfolge wieder her.
		return false
	_pending[npc_id] = {
		"id": id,
		"from": caller,
		"text": text,
		"dialogue": dialogue,
	}
	var tmgr := get_node_or_null("/root/TaskManager")
	if tmgr != null:
		tmgr.call("add_task", {"id": "task_callback_" + id,
			"title": Loc.t("sys.phone_manager.callback_task", "%s%s — zurückrufen!") % [
				Loc.t("sys.phone_manager.message_from", "Nachricht von ") if from_machine else "",
				caller],
			# Save-Reparaturen duerfen eine frueher faelschlich abgeschlossene
			# Rueckrufnotiz wieder oeffnen, ohne eine zweite Zeile anzulegen.
			"repeatable": true,
			"note": (
				Loc.t("sys.phone_manager.heard_callback_note", "Du hast die Nachricht abgehört. Ruf zurück (Telefon/Telefonzelle) oder triff %s.") % caller
				if from_machine
				else Loc.t("sys.phone_manager.mom_callback_note", "Mama hat abgenommen. Ruf zurück (Telefon/Telefonzelle) oder triff %s unterwegs.") % caller)})
	if from_machine:
		var ui := get_node_or_null("/root/UIManager")
		if ui != null:
			ui.call("toast", Loc.t("sys.phone_manager.message_heard_callback",
				"Nachricht abgehört: %s bittet um Rückruf.") % caller)
	phone_changed.emit()
	return true


## Slot-Wechsel: bist du ZU HAUSE (Zimmer), klingelt ein faelliger Anruf LIVE —
## du kannst selbst rangehen (Gespraech) statt AB/verpasst.
func _on_slot_incoming() -> void:
	ring_due_at_home()


## Öffentlich: einen jetzt fälligen Anruf zu Hause klingeln lassen (Live-Gespräch).
## Auch außerhalb des Slot-Wechsels nutzbar — z. B. direkt NACH dem ersten Boot, damit
## Stefans Amiga-Anruf prompt kommt statt erst beim nächsten Zeitfenster.
func ring_due_at_home() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or str(gm.get("current_location_id")) != "room":
		return
	var dm := get_node_or_null("/root/DialogueManager")
	if dm != null and dm.has_method("is_active") and bool(dm.call("is_active")):
		return
	var ui := get_node_or_null("/root/UIManager")
	if ui == null:
		return
	var layer: Variant = ui.get("window_layer")
	if layer == null or layer.get_node_or_null("win_incoming") != null:
		return   # keine Fensterebene / es klingelt schon
	var tm := get_node_or_null("/root/TimeManager")
	var year := int(tm.get("year")) if tm != null else 1992
	var day := int(tm.get("day_counter")) if tm != null else 0
	for def in _defs:
		if _call_due(def, year, day):
			var is_story := str(def.get("dialogue", "")) != ""
			if is_story and not GameManager.claim_story_beat("call:" + str(def.get("id", ""))):
				continue
			_received.append(str(def.get("id", "")))
			ui.call("open_incoming_call", def)
			return


## Live rangehen: kurzes Gespraech mit dem Anrufer (+ Vertrauen, Rueckruf entfaellt).
func answer_call(def: Dictionary) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("stop_sfx", "phone_ring")
		am.call("play", "phone_pickup", 0.0)
	var npc_id := str(def.get("npc", ""))
	var caller := str(def.get("from", "?"))
	learn_contact(npc_id)
	if npc_id != "":
		NPCManager.change_trust(npc_id, 1)
	# Skript-Anruf: ein `dialogue`-Feld öffnet ein VOLLES verzweigtes Gespräch
	# (z. B. Stefans Amiga-Anruf, aus dem die Weltraumspiel-Quest entsteht).
	var dlg := str(def.get("dialogue", ""))
	if dlg != "":
		DialogueManager.start_dialogue(dlg, npc_id)
	else:
		DialogueManager.start_bark(npc_id, "☎ " + caller,
			Loc.t("phone.%s.text" % str(def.get("id", "")), str(def.get("text", ""))))
	var tmgr := get_node_or_null("/root/TaskManager")
	if tmgr != null:
		tmgr.call("complete", "task_callback_" + str(def.get("id", "")))
	phone_changed.emit()


## Nicht abheben → wie verpasst behandeln (AB oder Eltern-Notiz).
func decline_call(def: Dictionary) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("stop_sfx", "phone_ring")
	var tm := get_node_or_null("/root/TimeManager")
	var day := int(tm.get("day_counter")) if tm != null else 0
	_deliver_call(def, day)


# ===================================================== Aktiv telefonieren (D.4)

## Wartet für diesen NPC eine verpasste Nachricht? Holt sie ab (einmalig),
## hakt die Board-Aufgabe ab. Nutzt der Rückruf UND das persönliche Treffen.
## „Ey, ruf mal X an!" — jemand gibt dir unterwegs einen Tipp: legt einen
## Anruf-Auftrag an (Aufgabe am Board + pending). Rufst du X dann an (zu Hause
## oder Telefonzelle), kommt das VOLLE Gespräch (dialogue) — Queststart-Kanal.
func expect_call(npc_id: String, id: String, title: String, dialogue: String) -> bool:
	learn_contact(npc_id)
	if _pending.has(npc_id):
		# Derselbe Story-Hinweis ist idempotent. Ein anderer wartender Anruf wird
		# niemals ueberschrieben; TaskManager versucht die Save-Migration erneut,
		# sobald der aeltere Rueckruf abgearbeitet wurde.
		var queued: Dictionary = _pending[npc_id]
		if str(queued.get("id", "")) == id:
			return true
		return false
	_pending[npc_id] = {"id": id, "from": str(NPCManager.get_npc(npc_id).get("name", "?")),
		"text": "", "dialogue": dialogue}
	var tmgr := get_node_or_null("/root/TaskManager")
	if tmgr != null:
		tmgr.call("add_task", {"id": "task_callback_" + id, "title": title,
			"note": Loc.t("sys.phone_manager.call_at_home_or_booth",
				"Anrufen: zu Hause am Telefon oder unterwegs an der Telefonzelle.")})
	phone_changed.emit()
	return true


func take_pending_entry(npc_id: String) -> Dictionary:
	if not _pending.has(npc_id):
		return {}
	var p: Dictionary = (_pending[npc_id] as Dictionary).duplicate(true)
	p["text"] = localized_message_text(p)
	_pending.erase(npc_id)
	var tmgr := get_node_or_null("/root/TaskManager")
	if tmgr != null:
		tmgr.call("complete", "task_callback_" + str(p.get("id", "")))
		# Aktionsnotizen duerfen bereits auf den verbrauchten Rueckruf reagieren;
		# der naechste Story-Rueckruf folgt dagegen erst nach Dialogende.
		if tmgr.has_method("reconcile_action_tasks"):
			tmgr.call_deferred("reconcile_action_tasks")
	phone_changed.emit()
	return p


func take_pending(npc_id: String) -> String:
	var p := take_pending_entry(npc_id)
	return str(p.get("text", ""))


func has_pending(npc_id: String) -> bool:
	return _pending.has(npc_id)


## Rettungsnetz fuer verpasste Kampagnenanrufe in alten/lange laufenden Saves.
## Ein empfangener Anruf ohne Nachricht, Rueckruf und Intro-Flag darf eine Quest
## nicht fuer immer verschlucken. Die Methode ist idempotent und wird auch von
## konkreten Progressions-UIs (z. B. der Sammlervitrine) genutzt.
func ensure_story_callback(id: String) -> bool:
	var def := _call_definition(id)
	if def.is_empty() or str(def.get("dialogue", "")).is_empty():
		return false
	var quest_id := str(def.get("campaign_quest", ""))
	if not quest_id.is_empty() \
			and (QuestManager.is_active(quest_id) or QuestManager.is_done(quest_id)):
		return false
	var year := TimeManager.year
	if year < int(def.get("year_from", 0)) \
			or (def.has("year_to") and year > int(def["year_to"])) \
			or not _campaign_gate_open(def, year) \
			or not _age_gate_open(def, year):
		return false
	if def.has("requires_flag") \
			and not _flag_truthy(GameManager.flags.get(str(def["requires_flag"]), false)):
		return false
	if def.has("unless_flag") \
			and _flag_truthy(GameManager.flags.get(str(def["unless_flag"]), false)):
		return false
	var npc_id := str(def.get("npc", ""))
	if npc_id.is_empty():
		return false
	if _pending.has(npc_id):
		if str((_pending[npc_id] as Dictionary).get("id", "")) != id:
			return false
		# Auch eine inkonsistente alte, bereits abgehakte Board-Zeile wieder
		# oeffnen. _queue_callback bleibt dank TaskManager-Dedupe idempotent.
		if TaskManager.is_open("task_callback_" + id):
			return true
		_queue_callback(npc_id, id, str(def.get("from", "?")), str(def.get("text", "")),
			str(def.get("dialogue", "")), false)
		return true
	if messages.any(func(message: Dictionary) -> bool:
			return str(message.get("id", "")) == id and not bool(message.get("heard", false))):
		return true
	if id not in _received:
		_received.append(id)
	learn_contact(npc_id)
	_queue_callback(npc_id, id, str(def.get("from", "?")), str(def.get("text", "")),
		str(def.get("dialogue", "")), false)
	return true


## Nummer eines NPCs als Anzeige-String — nach Svens Umzug MIT Vorwahl davor.
func display_number(npc_id: String) -> String:
	var npc: Dictionary = NPCManager.get_npc(npc_id)
	if not npc.has("phone"):
		return ""
	if _has_moved(npc_id):
		return "%s · %s" % [str(npc.get("vorwahl", "")), str(npc.get("phone_moved", ""))]
	return str(npc.get("phone", ""))


## Ist der Kontakt umgezogen? (Sven ab 1995 — Fakt sven_weg; datengetrieben:
## jeder NPC mit phone_moved + erfülltem Umzugs-Fakt.)
func _has_moved(npc_id: String) -> bool:
	if not NPCManager.get_npc(npc_id).has("phone_moved"):
		return false
	# Umzugsjahr steckt im Narrative-Fakt (sven_weg ab 1995).
	if npc_id == "npc_sven":
		return NarrativeManager.fact_true("sven_weg")
	return false


func _digits(s: String) -> String:
	var out := ""
	for c in s:
		if c >= "0" and c <= "9":
			out += c
	return out


## Ist die eigene Leitung frei? Das Modem teilt sich die Leitung mit dem Telefon.
func line_free() -> bool:
	var bbs := get_node_or_null("/root/BBSManager")
	return bbs == null or not bool(bbs.call("connected"))


## Nummer wählen. from_booth = Telefonzelle (kostet BOOTH_COST, eigene Leitung egal).
## Ergebnis: {ok, text, npc} — Sounds/Gesprächszeile löst der Aufrufer aus.
func dial(raw: String, from_booth := false) -> Dictionary:
	var number := _digits(raw)
	if number.length() < 6:
		return {"ok": false, "text": Loc.t("sys.phone_manager.nummer_ist_zu_kurz_sechs_ziffern", "Die Nummer ist zu kurz — sechs Ziffern, bei Ferngesprächen mit Vorwahl davor."), "npc": ""}
	if not from_booth and line_locked():
		return {"ok": false, "text": Loc.t("sys.phone_manager.papa_hat_telefon_gesperrt_bis_rechnung", "Papa hat das Telefon GESPERRT, bis die Rechnung (%d DM) bezahlt ist. Postamt oder Bank!") % bill_due, "npc": ""}
	if not from_booth and not line_free():
		return {"ok": false, "text": Loc.t("sys.phone_manager.leitung_ist_belegt_modem_hangt_gerade", "Die Leitung ist belegt — das Modem hängt gerade in der Mailbox."), "npc": ""}
	_last_from_booth = from_booth
	if from_booth and not PlayerStats.spend_money(BOOTH_COST):
		return {"ok": false, "text": Loc.t("sys.phone_manager.kein_kleingeld_telefonzelle_will_d_dm", "Kein Kleingeld — die Telefonzelle will %d DM.") % BOOTH_COST, "npc": ""}
	if number == _digits(player_number):
		return {"ok": false, "text": Loc.t("sys.phone_manager.besetztzeichen_du_rufst_deinen_eigenen_anschluss", "Besetztzeichen — du rufst deinen eigenen Anschluss an."), "npc": ""}

	for id in NPCManager.npcs:
		var npc: Dictionary = NPCManager.npcs[id]
		if not npc.has("phone"):
			continue
		var moved := _has_moved(str(id))
		var local := _digits(str(npc.get("phone", "")))
		var far := _digits(str(npc.get("vorwahl", ""))) + _digits(str(npc.get("phone_moved", "")))
		if moved:
			if number == _digits(str(npc.get("phone_moved", ""))):
				return {"ok": false, "npc": "",
					"text": Loc.t("sys.phone_manager.kein_anschluss_unter_dieser_nummer_s", "»Kein Anschluss unter dieser Nummer.« — %s wohnt jetzt auswärts: erst die Vorwahl %s wählen!") % [str(npc.get("name", "?")), str(npc.get("vorwahl", ""))]}
			if number == far:
				return _connect(str(id), npc)
			if number == local:
				return {"ok": false, "npc": "", "text": Loc.t("sys.phone_manager.fremde_stimme_hier_ist_kein_s", "Eine fremde Stimme: »Hier ist kein %s, Sie haben sich verwählt.« Die Nummer gilt nicht mehr.") % str(npc.get("name", "?"))}
		elif number == local:
			return _connect(str(id), npc)
	return {"ok": false, "text": Loc.t("sys.phone_manager.kein_anschluss_unter_dieser_nummer", "»Kein Anschluss unter dieser Nummer.«"), "npc": ""}


## Verbindungsversuch zu einem bekannten Anschluss: Sysop-Nummer kreischt (Modem!),
## sonst entscheidet der Wochenplan, ob jemand abhebt; kleine Besetzt-Chance.
func _connect(npc_id: String, npc: Dictionary) -> Dictionary:
	if npc_id == "npc_sysop":
		return {"ok": false, "npc": npc_id, "sound": "fax",
			"text": Loc.t("sys.phone_manager.modem_kreischt_dir_ins_ohr_ist", "Ein Modem KREISCHT dir ins Ohr — das ist die Datenleitung der Mailbox. Da wählt man sich mit dem Modem ein, nicht mit dem Mund.")}
	# Verpasster SKRIPT-Anruf (Def mit `dialogue`, z. B. Stefans Amiga-Anruf) → beim
	# Zurückrufen das VOLLE Gespräch nachholen. GARANTIERT verbunden — ein Tutorial-Beat
	# darf nicht an Besetztzeichen/Wochenplan scheitern.
	if _pending.has(npc_id) and str((_pending[npc_id] as Dictionary).get("dialogue", "")) != "":
		var dlg := str((_pending[npc_id] as Dictionary)["dialogue"])
		take_pending(npc_id)   # konsumiert Pending + hakt die Rückruf-Aufgabe ab
		NPCManager.change_trust(npc_id, 1)
		if not _last_from_booth:
			bill_open += CALL_COST_FERN if _has_moved(npc_id) else CALL_COST
		phone_changed.emit()
		return {"ok": true, "npc": npc_id, "dialogue": dlg}
	if randf() < 0.15:
		return {"ok": false, "npc": npc_id, "sound": "besetzt",
			"text": Loc.t("sys.phone_manager.busy_tone",
				"Tuut… tuut… — besetzt. %s quatscht wohl gerade mit wem anders.") % str(npc.get("name", "?"))}
	if not _reachable_today(npc_id, npc):
		return {"ok": false, "npc": npc_id, "sound": "klingeln",
			"text": Loc.t("sys.phone_manager.es_klingelt_klingelt_niemand_hebt_ab", "Es klingelt und klingelt … niemand hebt ab. %s ist wohl nicht da.") % str(npc.get("name", "?"))}
	# Verbunden! Wartet eine VERPASSTE Nachricht (kein AB), wird sie zuerst
	# nachgeholt; sonst liefert der Narrative-Core die Gesprächszeile.
	var text := ""
	var pending := take_pending(npc_id)
	if pending != "":
		text = Loc.t("sys.phone_manager.good_you_called",
			"Gut, dass du dich meldest — ich hatte's schon bei dir probiert! %s") % pending
	else:
		var line: Dictionary = NarrativeManager.pick_line(npc_id)
		text = str(line.get("text", Loc.t("sys.phone_manager.nice_you_called", "Schön, dass du anrufst!")))
		if not line.is_empty():
			NarrativeManager.mark_said(npc_id, str(line.get("id", "")))
	NPCManager.change_trust(npc_id, 1)
	# Gesprächskosten auf die Rechnung (Zellen-Gespräche zahlt man bar beim Wählen).
	if not _last_from_booth:
		bill_open += CALL_COST_FERN if _has_moved(npc_id) else CALL_COST
	phone_changed.emit()
	return {"ok": true, "npc": npc_id, "text": text}


## Hebt heute jemand ab? Ladenleute sind zu Geschäftszeiten am Laden-Anschluss,
## Freunde am Familienanschluss, wenn ihr Tagesplan sie zu Hause vorsieht.
## Umgezogene (Sven) sind abends grundsätzlich erreichbar — deshalb ruft man ja an.
func _reachable_today(npc_id: String, npc: Dictionary) -> bool:
	if _has_moved(npc_id):
		return true
	var sched: Dictionary = npc.get("schedule", {})
	if sched.is_empty():
		return true
	var keys := ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
	var today := str(sched.get(keys[TimeManager.weekday()], "home"))
	var base := str(npc.get("location", "home"))
	# Erreichbar, wenn heute zu Hause ODER am eigenen Stammort (Laden mit
	# Geschäftsanschluss, Stefans Bastelkeller, der Club des Leiters …).
	return today == "home" or today == base


func to_dict() -> Dictionary:
	return {"connected": machine_connected, "messages": messages, "received": _received,
		"number": player_number, "pending": _pending,
		"known_contacts": known_contacts.duplicate(),
		"bill_open": bill_open, "bill_due": bill_due, "bill_month": _bill_month}


func from_dict(d: Dictionary) -> void:
	machine_connected = bool(d.get("connected", false))
	messages = d.get("messages", [])
	_received = d.get("received", [])
	player_number = str(d.get("number", ""))
	_pending = d.get("pending", {})
	if d.has("known_contacts"):
		known_contacts = d.get("known_contacts", []).duplicate()
	else:
		# Kompatibilitaet fuer alte Saves: keine bereits sichtbaren Nummern
		# wegnehmen. Neue Spiele laufen dagegen ueber reset() mit Stefan allein.
		known_contacts = []
		for npc_id: String in NPCManager.npcs:
			if NPCManager.get_npc(npc_id).has("phone"):
				known_contacts.append(npc_id)
	bill_open = int(d.get("bill_open", 0))
	bill_due = int(d.get("bill_due", 0))
	_bill_month = int(d.get("bill_month", -1))
	_ensure_number()
	messages_changed.emit()
	phone_changed.emit()
	# SaveManager lädt GameManager/TaskManager/QuestManager erst nach dem Telefon.
	# Deferred sieht die vollständig eingespielten Flags und kann alte, durch den
	# früher fehlenden Wochen-Gate entstandene Rückrufe sicher zurückrollen.
	call_deferred("reconcile_story_timeline")


## Repariert die beiden Timeline-Fehler alter Saves: zu frueh empfangene
## Story-Anrufe werden bis zu ihrer Kampagnenwoche zurueckgerollt; bereits als
## empfangen markierte, danach aber verlorene Dialoge werden als Rueckruf
## rekonstruiert. Normale Kontakte bleiben unveraendert. Die Methode ist
## oeffentlich, damit Save-Migration und QA denselben idempotenten Vertrag nutzen.
func reconcile_story_timeline() -> Array[String]:
	var repaired: Array[String] = []
	# 1991 führt Herr Voss als Mathe- und Klassenlehrer über die unterschriebene
	# Praktikumsbescheinigung ein. Alte Saves erhalten diesen Kontext ebenfalls.
	if _flag_truthy(GameManager.flags.get("praktikum_done", false)):
		GameManager.flags["voss_known"] = true
	for def: Dictionary in _defs:
		var quest_id := str(def.get("campaign_quest", ""))
		if quest_id.is_empty() \
				or (_campaign_gate_open(def, TimeManager.year)
					and _age_gate_open(def, TimeManager.year)):
			continue
		var id := str(def.get("id", ""))
		var touched := false
		while id in _received:
			_received.erase(id)
			touched = true
		var old_message_count := messages.size()
		messages = messages.filter(func(message: Dictionary) -> bool:
			return str(message.get("id", "")) != id)
		touched = touched or messages.size() != old_message_count
		for pending_key: Variant in _pending.keys():
			var pending: Dictionary = _pending.get(pending_key, {})
			if str(pending.get("id", "")) == id:
				_pending.erase(pending_key)
				touched = true
		# Wurde der verfrühte Dialog bereits beantwortet, darf sein Intro-Flag die
		# Quest nicht heimlich vorziehen. Erledigte/aktive Quests sind dagegen
		# autoritativ und werden niemals zurückgesetzt. `touched` ist wichtig:
		# Ein auf anderem Weg gesetztes Flag darf die Migration nicht löschen,
		# wenn dieser konkrete Anruf den alten Save nie berührt hat.
		var intro_flag := str(def.get("unless_flag", ""))
		if touched and not intro_flag.is_empty() \
				and not QuestManager.is_active(quest_id) and not QuestManager.is_done(quest_id) \
				and _flag_truthy(GameManager.flags.get(intro_flag, false)):
			GameManager.flags.erase(intro_flag)
		var tasks := get_node_or_null("/root/TaskManager")
		if tasks != null and tasks.has_method("remove") and tasks.has_method("has_task") \
				and bool(tasks.call("has_task", "task_callback_" + id)):
			tasks.call("remove", "task_callback_" + id)
			touched = true
		if touched:
			repaired.append(id)
	# Umgekehrte Cache-Falle: Manche alte Saves hatten den Story-Anruf bereits
	# als empfangen gespeichert, aber weder Bandnachricht noch Rueckruf noch das
	# Intro-Flag. Sobald der Kampagnenslot offen ist, stellen wir genau diesen
	# verlorenen Dialog als Rueckruf wieder her.
	for def: Dictionary in _defs:
		var id := str(def.get("id", ""))
		var quest_id := str(def.get("campaign_quest", ""))
		var intro_flag := str(def.get("unless_flag", ""))
		if id.is_empty() or quest_id.is_empty() or id not in _received \
				or not _campaign_gate_open(def, TimeManager.year) \
				or not _age_gate_open(def, TimeManager.year) \
				or QuestManager.is_active(quest_id) or QuestManager.is_done(quest_id) \
				or (not intro_flag.is_empty()
					and _flag_truthy(GameManager.flags.get(intro_flag, false))):
			continue
		var has_message := messages.any(func(message: Dictionary) -> bool:
			return str(message.get("id", "")) == id \
				and not bool(message.get("heard", false)))
		var has_callback := _pending.values().any(func(entry: Variant) -> bool:
			return entry is Dictionary and str((entry as Dictionary).get("id", "")) == id)
		if not has_message and not has_callback and ensure_story_callback(id):
			repaired.append(id)
	if not repaired.is_empty():
		messages_changed.emit()
		phone_changed.emit()
	return repaired


func reset() -> void:
	machine_connected = false
	messages = []
	_received = []
	player_number = ""
	_pending = {}
	known_contacts = ["npc_stefan"]
	bill_open = 0
	bill_due = 0
	_bill_month = -1
	_ensure_number()
	messages_changed.emit()
	phone_changed.emit()


func _load_defs() -> void:
	if not FileAccess.file_exists(CONFIG):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if parsed is Dictionary:
		_defs = parsed.get("messages", [])
