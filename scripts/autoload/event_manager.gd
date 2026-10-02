extends Node
## EventManager — Zufallsereignisse aus data/events.json und die zentrale
## Effekt-DSL, die auch Dialoge und Shops nutzen. Neue Ereignisse sind reine
## Datensätze; Code muss dafür nicht angefasst werden.
##
## Effekt-DSL (jeder Effekt ist ein Dictionary mit "type"):
##   stat               {stat, value}      Spielwert ändern
##   money              {value}            DM (negativ = Ausgabe)
##   item               {item, value}      Inventar-Item (negativ = verbrauchen)
##   disk_template      {id, memory}       Diskette in die Box legen
##   program            {id}               Werkbank-Programm freischalten
##   music_track        {id}               einen MOD in die Sammlung legen
##   memory_once        {id}               einmalige Erinnerung verbuchen
##   damage_random_disk {value}            zufällige Diskette beschädigen
##   virus_scare_disk   {capture_uid_flag} eindeutige verdächtige Disk binden
##   drive_dirt         {value}            Laufwerksverschmutzung ändern
##   clean_drive        {}                 Laufwerkskopf reinigen
##   flag               {flag, value}      Spielflag setzen (Quests)
##   npc_trust          {npc, value}       NPC-Vertrauen ändern
##   end_slot           {}                 Zeit-Slot vorbei
##   toast              {text}             Meldung in den Info-Ticker
##   open_shop          {}                 Shopfenster öffnen
##   open_drive_clean   {}                 Lesekopf-Reinigungsminispiel öffnen

signal event_triggered(event: Dictionary)

# Statische Kalenderhelfer über den TYP rufen (STATIC_CALLED_ON_INSTANCE-Warnung):
# TimeManager ist die Autoload-INSTANZ, date_crossed() ist static.
const TimeMgrScript := preload("res://scripts/autoload/time_manager.gd")

## Wahrscheinlichkeit, dass beim Slot-Wechsel ein Ereignis feuert.
const EVENT_CHANCE := 0.30

var events: Array = []
var cooldown_until: Dictionary = {}  # event_id -> day_counter, ab dem es wieder darf


var _calendar_fired: Dictionary = {}   # "id:jahr" -> true (einmal pro Jahr)
var _calendar_queue: Array[Dictionary] = []
## Unterdrueckt ein zweites Zufallsereignis, waehrend die Wahl des aktuell
## sichtbaren Ereignisses noch atomar verbucht wird. Besonders Mahlzeiten
## verbrauchen einen Zeitslot; ohne diese Sperre konnte slot_changed bereits
## das naechste Ereignis ziehen, obwohl das alte Fenster noch existierte.
var _resolving_effects := false


func _ready() -> void:
	_load_data()
	TimeManager.slot_changed.connect(_on_slot_changed)
	TimeManager.day_changed.connect(_on_day_changed)
	TimeManager.calendar_jumped.connect(_on_calendar_jumped)


func _load_data() -> void:
	var file := FileAccess.open("res://data/events.json", FileAccess.READ)
	if file == null:
		push_error("events.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("events.json ist kein gueltiges JSON-Objekt!")
		return
	var data: Dictionary = parsed
	events = data.get("events", [])


func reset() -> void:
	cooldown_until = {}
	_calendar_fired = {}
	_calendar_queue = []


## Ereignis-Zustand persistieren: Abklingzeiten UND welche Jahresevents (Geburtstag,
## Weihnachten …) schon dran waren — sonst feuern sie nach dem Laden erneut.
func to_dict() -> Dictionary:
	return {"cooldown_until": cooldown_until, "calendar_fired": _calendar_fired}


func from_dict(d: Dictionary) -> void:
	cooldown_until = d.get("cooldown_until", {})
	_calendar_fired = d.get("calendar_fired", {})
	_calendar_queue = []


# ------------------------------------------------- Kalender-Events (datumsfest)

## Garantierte Datums-Ereignisse (s. docs/LIFE_TIME_BIBLE.md): Geburtstag (aus
## PlayerIdentity) und Feste aus events.json mit Feld "on_date": "MM-DD"
## (z. B. Weihnachten "12-24"). Feuern EINMAL pro Jahr am Tagesbeginn.
func _on_day_changed() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	var due_events: Array[Dictionary] = []
	if PlayerIdentity.is_birthday_today() and _calendar_once("birthday"):
		MemoryManager.record("geburtstag", "%d. Geburtstag gefeiert" % PlayerIdentity.age())
		var birthday := _birthday_event()
		event_triggered.emit(birthday)
		due_events.append(birthday)
	var today := "%02d-%02d" % [TimeManager.month, TimeManager.day]
	for ev: Dictionary in events:
		if str(ev.get("on_date", "")) == today and TimelineManager.is_available(ev) \
				and _calendar_once(str(ev.get("id", ""))):
			if str(ev.get("memory", "")) != "":
				MemoryManager.record("fest", str(ev["memory"]))
			# Die Kampagne besitzt fuer den 31.12. eine eigene, groessere Sequenz.
			# Der normale Eventdialog wird deshalb verarbeitet, aber nicht daruebergelegt.
			if str(ev.get("id", "")) == "cal_silvester" and TimeManager.is_year_end_pending():
				_append_montage_line(TimeManager.year, str(ev.get("title", "Silvester")))
				continue
			event_triggered.emit(ev)
			due_events.append(ev)
	_enqueue_calendar_events(due_events)


## Mehrere echte Termine am selben Datum werden nicht mehr gegenseitig
## überschrieben. Die Fenster erscheinen nacheinander; auch ein bereits offenes
## Zufallsereignis wird erst beendet, bevor der Kalender seine Schlange fortsetzt.
func _enqueue_calendar_events(due_events: Array[Dictionary]) -> void:
	if due_events.is_empty():
		return
	_calendar_queue.append_array(due_events)
	_dispatch_next_calendar_event()


func _dispatch_next_calendar_event() -> void:
	if _calendar_queue.is_empty():
		return
	var layer: Node = UIManager.get("window_layer")
	# Isolierte Headless-Tests besitzen keine UI-Schicht. Die logischen Trigger
	# wurden oben bereits emittiert und als "fired" gespeichert.
	if layer == null:
		_calendar_queue.clear()
		return
	var existing: Node = layer.get_node_or_null("win_event")
	if existing != null and not existing.is_queued_for_deletion():
		var callback := Callable(self, "_on_calendar_window_closed")
		if not existing.tree_exited.is_connected(callback):
			existing.tree_exited.connect(callback, CONNECT_ONE_SHOT)
		return
	if existing != null:
		call_deferred("_dispatch_next_calendar_event")
		return
	var next_event: Dictionary = _calendar_queue.pop_front()
	var window: Control = UIManager.open_event(next_event)
	if window == null:
		call_deferred("_dispatch_next_calendar_event")
		return
	window.tree_exited.connect(_on_calendar_window_closed, CONNECT_ONE_SHOT)


func _on_calendar_window_closed() -> void:
	call_deferred("_dispatch_next_calendar_event")


## Grosse Spruenge verwerfen keine echten Kalendertermine. Uebersprungene Feste
## und Geburtstage werden am Originaldatum als Erinnerung verbucht und im
## Jahresrueckblick genannt; interaktive Wahl-Dialoge werden nicht erfunden.
func _on_calendar_jumped(from_date: Dictionary, to_date: Dictionary, elapsed_days: int, _reason: String) -> void:
	if elapsed_days <= 1 or GameManager.state != GameManager.State.PLAYING:
		return
	for event_year in range(int(from_date["year"]), int(to_date["year"]) + 1):
		var birthday_day := mini(PlayerIdentity.birth_day,
			TimeManager.days_in_month(event_year, PlayerIdentity.birth_month))
		if TimeMgrScript.date_crossed(from_date, to_date, event_year, PlayerIdentity.birth_month, birthday_day) \
				and not _date_matches(to_date, event_year, PlayerIdentity.birth_month, birthday_day) \
				and _calendar_once_for("birthday", event_year):
			var age := event_year - PlayerIdentity.birth_year
			var birthday_text := "%d. Geburtstag gefeiert" % age
			MemoryManager.record_historical("geburtstag", birthday_text,
				event_year, PlayerIdentity.birth_month, birthday_day)
			_append_montage_line(event_year, "%d. Geburtstag" % age)
		for ev: Dictionary in events:
			var raw := str(ev.get("on_date", ""))
			if raw.length() != 5 or not TimelineManager.is_available(ev):
				continue
			var parts := raw.split("-")
			var event_month := int(parts[0])
			var event_day := mini(int(parts[1]), TimeManager.days_in_month(event_year, event_month))
			var id := str(ev.get("id", ""))
			if TimeMgrScript.date_crossed(from_date, to_date, event_year, event_month, event_day) \
					and not _date_matches(to_date, event_year, event_month, event_day) \
					and _calendar_once_for(id, event_year):
				var memory := str(ev.get("memory", ev.get("title", id)))
				MemoryManager.record_historical("fest", memory, event_year, event_month, event_day)
				_append_montage_line(event_year, str(ev.get("title", memory)))


func _calendar_once(id: String) -> bool:
	return _calendar_once_for(id, TimeManager.year)


func _calendar_once_for(id: String, event_year: int) -> bool:
	var key := "%s:%d" % [id, event_year]
	if _calendar_fired.has(key):
		return false
	_calendar_fired[key] = true
	return true


func _append_montage_line(event_year: int, line: String) -> void:
	var key := "montage_events_%d" % event_year
	var lines: Array = GameManager.flags.get(key, [])
	if not line.is_empty() and not line in lines:
		lines.append(line)
	GameManager.flags[key] = lines


func _date_matches(date: Dictionary, event_year: int, event_month: int, event_day: int) -> bool:
	return int(date.get("year", 0)) == event_year and int(date.get("month", 0)) == event_month \
		and int(date.get("day", 0)) == event_day


## Dynamisches Geburtstags-Ereignis (Name/Alter aus PlayerIdentity; Geschenke
## wachsen leicht mit dem Alter).
func _birthday_event() -> Dictionary:
	var age := PlayerIdentity.age()
	var cash := 25 + age * 3
	# Freunde gratulieren: den ganzen Tag klingelt das Telefon. Nur wer schon
	# bekannt ist (Vertrauen ≥ 0 / überhaupt getroffen), meldet sich — jeder
	# Anruf ein kleiner Vertrauens-Schub.
	var congrats: Array = []
	var callers := ""
	for npc_id in ["npc_stefan", "npc_mike", "npc_sven"]:
		if NPCManager.get_trust(npc_id) > 0:
			congrats.append({"type": "npc_trust", "npc": npc_id, "value": 1})
			callers += ("" if callers == "" else ", ") + str(NPCManager.get_npc(npc_id).get("name", ""))
	var call_line := "Deine Freunde (%s) haben angerufen und gratuliert. " % callers if callers != "" else ""
	return {
		"id": "cal_birthday", "title": "Alles Gute, %s!" % PlayerIdentity.player_name,
		"text": Loc.t("sys.event_manager.heute_wirst_du_d_es_gibt", "Heute wirst du %d. Es gibt Kuchen, einen Umschlag von der Verwandtschaft und ein paar Päckchen. %s") % [age, call_line],
		"choices": [
			{"text": Loc.t("sys.event_manager.umschlag_offnen", "Umschlag öffnen"), "effects": [
				{"type": "money", "value": cash},
				{"type": "stat", "stat": "ruf", "value": 1},
			] + congrats + [
				{"type": "toast", "text": Loc.t("sys.event_manager.d_dm_damit_lasst_sich_was", "%d DM! Damit lässt sich was anfangen.") % cash}]},
			{"text": Loc.t("sys.event_manager.packchen_auspacken", "Päckchen auspacken"), "effects": [
				{"type": "money", "value": 10},
				{"type": "stat", "stat": "energie", "value": 15},
				{"type": "item", "item": "etiketten", "value": 5},
				{"type": "disk_template", "id": "coverdisk_amiga_kurier", "memory": "Geburtstags-Coverdisk"},
			] + congrats + [
				{"type": "toast", "text": Loc.t("sys.event_manager.leerdisketten_etiketten_coverdisk_susses_schoner_tag", "Leerdisketten, Etiketten, eine Coverdisk und Süßes. Schöner Tag!")}]},
		],
	}


# ------------------------------------------------------------- Auslösen

func _on_slot_changed(_slot: int) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	# Ein Zeitfenster, das während einer Reise überschritten wird, ist kein
	# Aufenthalt am Zielort. Der GameManager setzt den Zielkontext absichtlich
	# schon vor dem Zeitvorschub; ohne diese Schranke konnten deshalb dort bereits
	# normale Zufallsereignisse aufgehen und den garantierten Quest-Höhepunkt bei
	# der tatsächlichen Ankunft verdecken. Priorisierte Ankunftsereignisse werden
	# nach dem Ortsaufbau gezielt über trigger_priority_arrival_event() geöffnet.
	if GameManager.is_traveling():
		return
	if _resolving_effects:
		return
	if DialogueManager.is_active():
		return
	# Eligibility ist read-only und wird vor dem unveraenderten Zufallswurf
	# ermittelt, damit der Playtest auch verpasste Event-Gelegenheiten kennt.
	var candidates := _eligible_events()
	var roll := randf()
	if roll > EVENT_CHANCE:
		PlaytestTelemetry.note_event_roll(false, candidates.size())
		return
	PlaytestTelemetry.note_event_roll(true, candidates.size())
	if candidates.is_empty():
		return
	var event := _pick_weighted(candidates)
	cooldown_until[event["id"]] = TimeManager.day_counter + int(event.get("cooldown_days", 1))
	event_triggered.emit(event)
	UIManager.open_event(event)


func _eligible_events() -> Array:
	var eligible := events.filter(func(ev: Dictionary) -> bool:
		# Datumsfeste Ereignisse besitzen genau EINEN Ausloeseweg:
		# _on_day_changed() am echten Kalenderdatum. Ohne diese harte Trennung
		# konnten Heiligabend, Nikolaus oder Neujahr beim Reisen im Juli aus dem
		# normalen Zufallspool gezogen werden.
		if not str(ev.get("on_date", "")).is_empty():
			return false
		if TimeManager.day_counter < int(cooldown_until.get(ev.get("id", ""), 0)):
			return false
		# Ein bereits gestarteter Story-Hoehepunkt bleibt nach seinem historischen
		# Zeitfenster als Catch-up spielbar. Die Quest selbst bleibt laut
		# QuestManager absichtlich im Backlog; ihr einziges Event darf deshalb nicht
		# vorher verschwinden (historischer Softlock: LAN-Nacht nach 1997).
		var quest_id := str(ev.get("requires_quest_active", ""))
		var story_catchup := quest_id != "" and QuestManager.is_active(quest_id) \
			and TimeManager.year > int(ev.get("year_to", ev.get("year_obsolete", 1999)))
		if not TimelineManager.is_available(ev) and not story_catchup:
			return false
		if ev.has("requires_flag") and not bool(GameManager.flags.get(str(ev["requires_flag"]), false)):
			return false
		if ev.has("unless_flag") and bool(GameManager.flags.get(str(ev["unless_flag"]), false)):
			return false
		if ev.has("requires_hardware") and not _all_hardware_owned(ev["requires_hardware"]):
			return false
		if ev.has("unless_hardware") and _any_hardware_owned(ev["unless_hardware"]):
			return false
		if ev.has("requires_program") and not ProgramLibrary.is_installed(str(ev["requires_program"])):
			return false
		if bool(ev.get("requires_computer_on", false)) and UIManager.boot_state() != "booted":
			return false
		if bool(ev.get("requires_at_computer", false)) and not UIManager.at_computer:
			return false
		if ev.has("requires_fact") and not NarrativeManager.fact_true(str(ev["requires_fact"])):
			return false
		if quest_id != "" and not QuestManager.is_active(quest_id):
			return false
		if ev.has("requires_quest_action"):
			var qa: Dictionary = ev["requires_quest_action"]
			var action_quest_id := str(qa.get("id", qa.get("quest", "")))
			if QuestManager.action_count(action_quest_id, str(qa.get("action", ""))) < int(qa.get("min", 1)):
				return false
		var locations: Array = ev.get("locations", [])
		if not locations.is_empty() and not GameManager.current_location_id in locations:
			return false
		return true)
	# Quest-Hoehepunkte sollen nicht im Zufallspool untergehen. Sobald ein
	# passendes Priority-Ereignis moeglich ist, konkurriert es nur mit anderen
	# laufenden Story-Hoehepunkten, nicht mit Kaffee- oder Wetter-Flavour.
	var priority := eligible.filter(func(ev: Dictionary) -> bool: return bool(ev.get("priority", false)))
	return priority if not priority.is_empty() else eligible


## Ein priorisierter Story-Höhepunkt am erreichten Ort darf nicht an einem
## Zufallswurf scheitern. Normale Flavor-Events bleiben weiter zufällig; diese
## Funktion wird ausschließlich nach einer echten Ortsankunft aufgerufen.
func trigger_priority_arrival_event(location_id: String) -> bool:
	if GameManager.state != GameManager.State.PLAYING \
			or GameManager.current_location_id != location_id \
			or DialogueManager.is_active():
		return false
	var layer: Node = UIManager.get("window_layer")
	if layer == null or layer.get_node_or_null("win_event") != null:
		return false
	var candidates: Array = _eligible_events().filter(func(candidate: Dictionary) -> bool:
		var locations: Array = candidate.get("locations", [])
		return bool(candidate.get("priority", false)) and location_id in locations)
	if candidates.is_empty():
		return false
	var selected_event: Dictionary = _pick_weighted(candidates)
	cooldown_until[selected_event["id"]] = TimeManager.day_counter + int(
		selected_event.get("cooldown_days", 1))
	event_triggered.emit(selected_event)
	return UIManager.open_event(selected_event) != null


## Read-only Gegenstück zur Filterkette. Jeder Sperrgrund bleibt einzeln
## sichtbar; das Ereignis wird dabei weder gezogen noch auf Cooldown gesetzt.
func explain_event(id: String) -> Dictionary:
	var event: Dictionary = {}
	for candidate: Dictionary in events:
		if str(candidate.get("id", "")) == id:
			event = candidate
			break
	if event.is_empty(): return {"id": id, "exists": false, "eligible": false, "checks": []}
	var checks: Array = []
	var on_date := str(event.get("on_date", ""))
	if on_date != "":
		var today := "%02d-%02d" % [TimeManager.month, TimeManager.day]
		checks.append({"kind": "calendar_date", "ok": today == on_date, "actual": today, "required": on_date})
		checks.append({"kind": "calendar_once", "ok": not _calendar_fired.has("%s:%d" % [id, TimeManager.year]),
			"actual": _calendar_fired.has("%s:%d" % [id, TimeManager.year]), "required": false})
	else:
		checks.append({"kind": "random_pool", "ok": true, "actual": "slot_change"})
		checks.append({"kind": "cooldown", "ok": TimeManager.day_counter >= int(cooldown_until.get(id, 0)),
			"actual": TimeManager.day_counter, "required": int(cooldown_until.get(id, 0))})
	var active_quest := str(event.get("requires_quest_active", ""))
	var story_catchup := active_quest != "" and QuestManager.is_active(active_quest) \
		and TimeManager.year > int(event.get("year_to", event.get("year_obsolete", 1999)))
	checks.append({"kind": "timeline", "ok": TimelineManager.is_available(event) or story_catchup,
		"actual": TimeManager.year, "catchup": story_catchup})
	if event.has("requires_flag"):
		var flag := str(event["requires_flag"]); checks.append({"kind": "flag", "id": flag,
			"ok": bool(GameManager.flags.get(flag, false)), "actual": GameManager.flags.get(flag, false)})
	if event.has("unless_flag"):
		var flag := str(event["unless_flag"]); checks.append({"kind": "unless_flag", "id": flag,
			"ok": not bool(GameManager.flags.get(flag, false)), "actual": GameManager.flags.get(flag, false)})
	if event.has("requires_hardware"):
		checks.append({"kind": "hardware", "id": event["requires_hardware"],
			"ok": _all_hardware_owned(event["requires_hardware"])})
	if event.has("unless_hardware"):
		checks.append({"kind": "unless_hardware", "id": event["unless_hardware"],
			"ok": not _any_hardware_owned(event["unless_hardware"])})
	if event.has("requires_program"):
		var program_id := str(event["requires_program"])
		checks.append({"kind": "program", "id": program_id,
			"ok": ProgramLibrary.is_installed(program_id)})
	if bool(event.get("requires_computer_on", false)):
		checks.append({"kind": "computer_on", "ok": UIManager.boot_state() == "booted",
			"actual": UIManager.boot_state(), "required": "booted"})
	if bool(event.get("requires_at_computer", false)):
		checks.append({"kind": "at_computer", "ok": UIManager.at_computer,
			"actual": UIManager.at_computer, "required": true})
	if event.has("requires_fact"):
		var fact := str(event["requires_fact"]); checks.append({"kind": "fact", "id": fact,
			"ok": NarrativeManager.fact_true(fact), "actual": NarrativeManager.fact_true(fact)})
	if event.has("requires_quest_active"):
		var quest := str(event["requires_quest_active"]); checks.append({"kind": "quest_active", "id": quest,
			"ok": QuestManager.is_active(quest), "actual": QuestManager.is_active(quest)})
	if event.has("requires_quest_action"):
		var qa: Dictionary = event["requires_quest_action"]; var quest := str(qa.get("id", qa.get("quest", ""))); var action := str(qa.get("action", "")); var have := QuestManager.action_count(quest, action)
		checks.append({"kind": "quest_action", "id": "%s/%s" % [quest, action], "ok": have >= int(qa.get("min", 1)), "actual": have, "required": int(qa.get("min", 1))})
	var locations: Array = event.get("locations", [])
	if not locations.is_empty(): checks.append({"kind": "location", "ok": GameManager.current_location_id in locations, "actual": GameManager.current_location_id, "required": locations})
	return {"id": id, "exists": true, "title": str(event.get("title", id)),
		"eligible": checks.all(func(check: Dictionary) -> bool: return bool(check.get("ok", false))), "checks": checks}


func event_audit_snapshot() -> Dictionary:
	return {"event_count": events.size(), "events": events.map(
		func(event: Dictionary) -> Dictionary: return explain_event(str(event.get("id", ""))))}


func _hardware_list(value: Variant) -> Array:
	return value if value is Array else [value]


func _all_hardware_owned(value: Variant) -> bool:
	return _hardware_list(value).all(func(id: Variant) -> bool:
		return PlayerStats.has_hardware(str(id)))


func _any_hardware_owned(value: Variant) -> bool:
	return _hardware_list(value).any(func(id: Variant) -> bool:
		return PlayerStats.has_hardware(str(id)))


func _pick_weighted(candidates: Array) -> Dictionary:
	var total := 0.0
	for ev in candidates:
		total += float(ev.get("weight", 1))
	var roll := randf() * total
	for ev in candidates:
		roll -= float(ev.get("weight", 1))
		if roll <= 0.0:
			return ev
	return candidates.back()


# ------------------------------------------------------------- Auflösung

## Ist eine Wahl gerade wählbar? (Item-/Geld-Voraussetzungen)
func choice_available(choice: Dictionary) -> bool:
	if choice.has("requires_item") and InventoryManager.count(choice["requires_item"]) <= 0:
		return false
	if choice.has("requires_money") and PlayerStats.geld < int(choice["requires_money"]):
		return false
	if choice.has("requires_hardware") and not PlayerStats.has_hardware(str(choice["requires_hardware"])):
		return false
	if choice.has("requires_quest_action"):
		var qa: Dictionary = choice["requires_quest_action"]
		var quest_id := str(qa.get("id", qa.get("quest", "")))
		if QuestManager.action_count(quest_id, str(qa.get("action", ""))) < int(qa.get("min", 1)):
			return false
	return true


## Wahl eines Ereignisses auflösen. Hat die Wahl ein 'risk' und schlägt der
## Würfel zu, treten die Risiko-Folgen an Stelle der normalen Effekte ein.
## Das Ergebnis wird an das Fenster zurückgegeben: Bei einer fehlgeschlagenen
## Transaktion bleibt es offen, damit keine bezahlte/abgegebene Sache verschwindet.
func resolve_choice(choice: Dictionary, event_id := "") -> Dictionary:
	PlaytestTelemetry.note_event_choice(str(event_id), str(choice.get("text", "")))
	var risk: Dictionary = choice.get("risk", {})
	if not risk.is_empty() and randf() < float(risk.get("chance", 0.0)):
		return apply_effects(risk.get("effects", []))
	return apply_effects(choice.get("effects", []))


# ------------------------------------------------------------- Effekt-DSL

const EFFECT_TYPES := [
	"stat", "money", "spend_money", "item", "disk_template", "program",
	"music_track", "memory_once", "take_disk_template", "take_player_copy_of",
	"damage_random_disk", "virus_scare_disk",
	"drive_dirt", "clean_drive", "flag", "hardware", "npc_trust", "end_slot",
	"toast", "open_shop", "open_drive_clean", "task", "expect_call", "task_done",
	"quest_advance", "quest_action", "game_distribution",
	"sommer_game_module",
]


## Prüft alle knappen Ressourcen, ohne den Spielzustand zu verändern. Die
## virtuelle Reihenfolge entspricht der späteren Ausführung: Eine vorherige Abgabe
## kann also Platz schaffen, eine vorherige Einnahme eine folgende Ausgabe decken.
func validate_effects(effects: Array) -> Dictionary:
	var virtual_money := float(PlayerStats.geld)
	var virtual_items: Dictionary = InventoryManager.items.duplicate()
	var virtual_disks: Array[Dictionary] = []
	var stored_disks := DiskManager.media_count()
	for disk: Disk in DiskManager.media_disks():
		virtual_disks.append({
			"uid": disk.uid,
			"template_id": disk.template_id,
			"software_id": disk.software_id,
			"content_type": disk.content_type,
			"content_title": disk.content_title,
			"label": disk.label,
			"release_role": disk.release_role,
			"release_serial": disk.release_serial,
			"release_project_kind": str(disk.release_data.get("project_kind", "")),
			"usable": disk.condition > 0,
			"player_copy": disk.is_player_made_copy() and not disk.is_game_master(),
			"quest_required": bool(QuestManager.disk_requirement(disk).get("required", false)),
			"rank": _handover_rank(disk),
			"removed": false,
		})

	for effect_index in effects.size():
		var raw_effect: Variant = effects[effect_index]
		if not raw_effect is Dictionary:
			return _effect_failure(effect_index, "invalid_effect", "Ein Spieleffekt ist ungültig.")
		var effect: Dictionary = raw_effect
		var effect_type := str(effect.get("type", ""))
		if effect_type not in EFFECT_TYPES:
			return _effect_failure(effect_index, "unknown_effect",
				"Unbekannter Spieleffekt: %s" % effect_type)
		match effect_type:
			"money":
				var delta := float(effect.get("value", 0))
				if virtual_money + delta < -0.005:
					return _effect_failure(effect_index, "insufficient_money",
						"Dafür reicht dein Geld nicht.")
				virtual_money = maxf(0.0, snappedf(virtual_money + delta, 0.01))
			"game_distribution":
				if str(effect.get("mode", "club")) in ["paid", "money", "kleinserie"]:
					virtual_money += maxf(0.0, float(effect.get("value", 0)))
			"spend_money":
				var amount := float(effect.get("value", 0))
				if amount < 0.0:
					return _effect_failure(effect_index, "invalid_money",
						"Die angegebene Ausgabe ist ungültig.")
				if virtual_money + 0.005 < amount:
					return _effect_failure(effect_index, "insufficient_money",
						"Dafür fehlen dir %s." % Currency.format(amount - virtual_money))
				virtual_money = maxf(0.0, snappedf(virtual_money - amount, 0.01))
			"item":
				var item_id := str(effect.get("item", ""))
				var item_amount := int(effect.get("value", 1))
				if item_id.is_empty():
					return _effect_failure(effect_index, "invalid_item", "Ein Gegenstand hat keine ID.")
				var item_total := int(virtual_items.get(item_id, 0)) + item_amount
				if item_total < 0:
					return _effect_failure(effect_index, "missing_item",
						"Dir fehlt: %s." % str(InventoryManager.ITEM_NAMES.get(item_id, item_id)))
				virtual_items[item_id] = item_total
			"disk_template":
				var template_id := str(effect.get("id", ""))
				if not DiskManager.templates.has(template_id):
					return _effect_failure(effect_index, "unknown_disk",
						"Unbekannte Diskette: %s" % template_id)
				if stored_disks + 1 > DiskManager.capacity():
					return _effect_failure(effect_index, "disk_capacity",
						"Die Diskettenbox ist voll. Schaffe erst einen freien Platz.")
				stored_disks += 1
				var template: Dictionary = DiskManager.templates.get(template_id, {})
				virtual_disks.append({
					"uid": "",
					"template_id": template_id,
					"software_id": str(template.get("software_id", "")),
					"content_type": str(template.get("content_type", "")),
					"content_title": str(template.get("content_title", "")),
					"label": str(template.get("label", "")),
					"release_role": "",
					"release_serial": "",
					"release_project_kind": "",
					"usable": true,
					"player_copy": false,
					"quest_required": false,
					"rank": 100,
					"removed": false,
				})
			"take_disk_template":
				var count := maxi(1, int(effect.get("count", 1)))
				var candidates: Array[int] = []
				for disk_index in virtual_disks.size():
					var candidate: Dictionary = virtual_disks[disk_index]
					if not bool(candidate.get("removed", false)) \
							and _virtual_disk_matches_handover(candidate, effect):
						candidates.append(disk_index)
				if bool(effect.get("preserve_best_source", false)):
					candidates.sort_custom(func(a: int, b: int) -> bool:
						return int(virtual_disks[a].get("rank", 0)) < int(virtual_disks[b].get("rank", 0)))
				if candidates.size() < count:
					return _effect_failure(effect_index, "missing_disk",
						"Die benötigte Diskette ist nicht mehr in deiner Box: %s." \
							% str(effect.get("id", "")))
				for i in count:
					virtual_disks[candidates[i]]["removed"] = true
					stored_disks -= 1
			"take_player_copy_of":
				var wanted_software := str(effect.get("software_id", ""))
				var count := maxi(1, int(effect.get("count", 1)))
				if wanted_software.is_empty():
					return _effect_failure(effect_index, "invalid_effect",
						"Für die Übergabe fehlt die Software-ID.")
				var candidates: Array[int] = []
				for disk_index in virtual_disks.size():
					var candidate: Dictionary = virtual_disks[disk_index]
					if not bool(candidate.get("removed", false)) \
							and bool(candidate.get("usable", false)) \
							and bool(candidate.get("player_copy", false)) \
							and str(candidate.get("software_id", "")) == wanted_software:
						candidates.append(disk_index)
				if candidates.size() < count:
					return _effect_failure(effect_index, "missing_disk",
						"Die benötigte selbst erstellte Spielkopie ist nicht mehr in deiner Box.")
				for i in count:
					virtual_disks[candidates[i]]["removed"] = true
					stored_disks -= 1
			"program":
				var program_id := str(effect.get("id", ""))
				if ProgramLibrary.get_program(program_id).is_empty():
					return _effect_failure(effect_index, "unknown_program",
						"Unbekanntes Programm: %s" % program_id)
			"sommer_game_module":
				var module_id := str(effect.get("id", ""))
				if SommerGameManager.Catalog.module(module_id).is_empty():
					return _effect_failure(effect_index, "unknown_sommer_game_module",
						"Unbekanntes Sommer-Game-Modul: %s" % module_id)
			"virus_scare_disk":
				if not VirusManager.can_arm_scare_disk():
					return _effect_failure(effect_index, "missing_disk",
						"Für den Virenverdacht ist keine prüfbare Diskette in deiner Box.")
	return {"ok": true, "reason": "", "text": ""}


func _effect_failure(index: int, reason: String, text: String) -> Dictionary:
	return {"ok": false, "index": index, "reason": reason, "text": text}


## Alles-oder-nichts-Vertrag für Dialoge, Ereignisse und Questbelohnungen. Nach
## erfolgreicher Vorprüfung kann im single-threaded Spielzustand keiner der
## knappen Ressourcenpfade mehr mitten in der Kette scheitern.
func apply_effects(effects: Array, notify_failure := true) -> Dictionary:
	var validation := validate_effects(effects)
	if not bool(validation.get("ok", false)):
		# Fehlende Ressourcen sind normales Gameplay. Nur fehlerhafte Daten sollen
		# den Debug-/Testlauf mit einer Engine-Warnung markieren.
		if str(validation.get("reason", "")) in ["invalid_effect", "unknown_effect",
				"invalid_money", "invalid_item", "unknown_disk", "unknown_program",
				"unknown_sommer_game_module"]:
			push_warning("Ungültige Effekt-Transaktion [%s]: %s" % [
				str(validation.get("reason", "invalid")), str(validation.get("text", ""))])
		if notify_failure:
			UIManager.toast(str(validation.get("text", "Aktion nicht möglich.")))
		return validation
	_resolving_effects = true
	# Zeitwechsel sind ein Abschluss-Effekt. Datenfehler wie
	# [Hunger, end_slot, Toast] duerfen deshalb nie mitten in einer Transaktion
	# UI, Zufallsereignisse oder Quests auf einem halbfertigen Zustand ausloesen.
	# Auch aeltere Save-/Mod-Daten werden hier sicher normalisiert.
	var terminal_effects: Array[Dictionary] = []
	for raw_effect: Variant in effects:
		var effect := raw_effect as Dictionary
		if str(effect.get("type", "")) == "end_slot":
			terminal_effects.append(effect)
		else:
			_apply_effect(effect)
	for effect: Dictionary in terminal_effects:
		_apply_effect(effect)
	_resolving_effects = false
	# Aufträge reagieren auf JEDE Zustandsänderung (reentrant-sicher via _busy).
	var qm := get_node_or_null("/root/QuestManager")
	if qm != null:
		qm.call("evaluate")
	var acm := get_node_or_null("/root/AchievementManager")
	if acm != null:
		acm.call("evaluate")
	return {"ok": true, "reason": "", "text": ""}


func _apply_effect(effect: Dictionary) -> void:
	match effect.get("type", ""):
		"stat":
			PlayerStats.change_stat(effect.get("stat", ""), int(effect.get("value", 0)))
		"money":
			PlayerStats.add_money(float(effect.get("value", 0)))
		"spend_money":
			if not PlayerStats.spend_money(float(effect.get("value", 0))):
				push_warning("Quest-Ausgabe konnte nicht bezahlt werden: %s" % str(effect))
		"item":
			var amount := int(effect.get("value", 1))
			if amount >= 0:
				InventoryManager.add_item(effect.get("item", ""), amount)
			else:
				InventoryManager.consume(effect.get("item", ""), -amount)
		"disk_template":
			var disk := DiskManager.create_disk(effect.get("id", ""),
				effect.get("memory", "Erhalten am %s" % TimeManager.date_string()))
			if disk != null:
				if effect.has("virus"):
					disk.virus = bool(effect.get("virus", false))
				if DiskManager.add_disk(disk):
					# Quests koennen an eine konkrete physische Instanz statt nur an
					# das gemeinsame Template gebunden werden. Die UID ist bereits
					# Bestandteil des Disketten-Saveformats und bleibt daher stabil.
					var capture_flag := str(effect.get("capture_uid_flag", ""))
					if not capture_flag.is_empty():
						GameManager.flags[capture_flag] = disk.uid
		"program":
			var program_id := str(effect.get("id", ""))
			if ProgramLibrary.get_program(program_id).is_empty():
				push_warning("Programm konnte nicht freigeschaltet werden: %s" % str(effect.get("id", "")))
			elif not ProgramLibrary.is_installed(program_id):
				ProgramLibrary.install(program_id)
		"sommer_game_module":
			var module_id := str(effect.get("id", ""))
			if not SommerGameManager.is_unlocked(module_id) \
					and not SommerGameManager.unlock_module(module_id):
				push_warning("Sommer-Game-Modul konnte nicht integriert werden: %s" % module_id)
		"music_track":
			MusicManager.collect(str(effect.get("id", "")))
		"memory_once":
			MemoryManager.record_once(str(effect.get("id", "")),
				str(effect.get("text", "")), str(effect.get("title", "")))
		"take_disk_template":
			var count := maxi(1, int(effect.get("count", 1)))
			var candidates := _handover_candidates(effect)
			for i in count:
				DiskManager.remove_disk(candidates[i])
		"take_player_copy_of":
			var count := maxi(1, int(effect.get("count", 1)))
			var candidates: Array = DiskManager.player_copies_of(
				str(effect.get("software_id", "")))
			candidates.sort_custom(func(a: Disk, b: Disk) -> bool:
				return a.condition < b.condition)
			for i in count:
				DiskManager.remove_disk(candidates[i])
		"damage_random_disk":
			DiskManager.damage_random_disk(int(effect.get("value", 5)))
		"virus_scare_disk":
			var captured := VirusManager.arm_scare_disk()
			if captured == null:
				push_warning("Virus-Verdacht konnte keine konkrete Diskette binden.")
		"drive_dirt":
			PlayerStats.add_drive_dirt(float(effect.get("value", 0.1)))
		"clean_drive":
			PlayerStats.clean_drive()
		"flag":
			GameManager.flags[effect.get("flag", "")] = effect.get("value", true)
		"hardware":
			PlayerStats.add_hardware(effect.get("id", ""))  # z. B. Weihnachtsgeschenk
		"npc_trust":
			NPCManager.change_trust(effect.get("npc", ""), int(effect.get("value", 0)))
		"end_slot":
			TimeManager.advance_slot()
		"toast":
			UIManager.toast(effect.get("text", ""))
		"open_shop":
			UIManager.open_shop()
		"open_drive_clean":
			UIManager.open_drive_clean()
		"task":
			TaskManager.add_task(effect)   # Aufgabe ans Board (aus Dialogen/Events)
		"expect_call":
			# „Ruf mal X an"-Tipp (Queststart-Kanal): Aufgabe + hinterlegtes Gespräch.
			PhoneManager.expect_call(str(effect.get("npc", "")), str(effect.get("id", "")),
				str(effect.get("title", "Da war doch was — jemanden anrufen!")),
				str(effect.get("dialogue", "")))
		"task_done":
			TaskManager.complete(effect.get("id", ""))
		"quest_advance":
			QuestManager.advance(effect.get("id", ""))   # manuelle Auftrags-Stufe weiter
		"quest_action":
			QuestManager.note_action(str(effect.get("action", "")), int(effect.get("value", 1)))
		"game_distribution":
			SceneReleaseManager.start_game_distribution(
				str(effect.get("mode", "club")), int(effect.get("value", 0)))
		_:
			push_warning("Unbekannter Effekt-Typ: %s" % str(effect))


func _handover_candidates(effect: Dictionary) -> Array[Disk]:
	var candidates: Array[Disk] = DiskManager.matching_media(effect)
	# Quest-Tausch nimmt auf Wunsch zuerst die entbehrlichste Kopie. Ein
	# Original/OVP-Master bleibt so auch bei anderer Boxsortierung erhalten.
	if bool(effect.get("preserve_best_source", false)):
		candidates.sort_custom(func(a: Disk, b: Disk) -> bool:
			return _handover_rank(a) < _handover_rank(b))
	return candidates


func _virtual_disk_matches_handover(candidate: Dictionary, effect: Dictionary) -> bool:
	if not bool(candidate.get("usable", false)):
		return false
	var uid_flag := str(effect.get("uid_flag", "")).strip_edges()
	var wanted_uid := str(effect.get("uid", "")).strip_edges()
	if wanted_uid.is_empty() and not uid_flag.is_empty():
		wanted_uid = str(GameManager.flags.get(uid_flag, "")).strip_edges()
		if wanted_uid.is_empty():
			return false
	if not wanted_uid.is_empty() and str(candidate.get("uid", "")) != wanted_uid:
		return false
	var wanted_template := str(effect.get("id",
		effect.get("template_id", ""))).strip_edges()
	if not wanted_template.is_empty() \
			and str(candidate.get("template_id", "")) != wanted_template:
		return false
	var wanted_software := str(effect.get("software_id", "")).strip_edges()
	if not wanted_software.is_empty() \
			and str(candidate.get("software_id", "")) != wanted_software:
		return false
	var wanted_content_type := str(effect.get("content_type", "")).strip_edges()
	if not wanted_content_type.is_empty() \
			and str(candidate.get("content_type", "")) != wanted_content_type:
		return false
	var wanted_release_role := str(effect.get("release_role", "")).strip_edges()
	if not wanted_release_role.is_empty() \
			and str(candidate.get("release_role", "")) != wanted_release_role:
		return false
	var release_serial_prefix := str(effect.get("release_serial_prefix", "")).strip_edges()
	if not release_serial_prefix.is_empty() \
			and not str(candidate.get("release_serial", "")).begins_with(release_serial_prefix):
		return false
	var release_project_kind := str(effect.get("release_project_kind", "")).strip_edges()
	if not release_project_kind.is_empty() \
			and str(candidate.get("release_project_kind", "")) != release_project_kind:
		return false
	if bool(effect.get("player_copy_only", false)) \
			and not bool(candidate.get("player_copy", false)):
		return false
	if bool(effect.get("unresolved_mystery", false)) \
			and (str(candidate.get("content_type", "")) != "mystery" \
			or not str(candidate.get("label", "")).strip_edges().is_empty() \
			or str(candidate.get("content_title", "")).strip_edges() not in ["", "???"]):
		return false
	if bool(effect.get("exclude_quest_required", false)) \
			and bool(candidate.get("quest_required", false)):
		return false
	return true


## Niedrigster Rang wird zuerst abgegeben: eine schlechtere Kopie vor einer
## guten Kopie, jede Kopie vor losem Original, loses Original vor OVP-Master.
func _handover_rank(disk: Disk) -> int:
	var provenance_rank := 1
	match disk.provenance:
		"copy": provenance_rank = 0
		"original": provenance_rank = 2
		"original_box": provenance_rank = 3
	return provenance_rank * 10000 - disk.copy_generation * 100 + disk.condition
