extends Node
## VisitManager — Freunde besuchen dich ZU HAUSE. Es klopft, ein Freund steht in
## der Tür (wie Stefan im Intro) und bringt eine Diskette, eine Neuigkeit oder eine
## kleine Aufgabe. Realistisch gegated: nur im Zimmer, nachmittags/abends, abhängig
## von Vertrauen (trust_min) und Ära (year_from/year_to). Max. 1 Besuch pro Tag.
##
## Zustand (letzter Besuchstag, erledigte Einmal-Besuche) liegt in
## GameManager.flags → schon im Save, kein SaveManager-Eingriff.

const CONFIG := "res://data/visits.json"
const VISIT_SLOTS := [2, 3]       # Nachmittag, Abend (TimeManager.SLOT_NAMES)
const VISIT_CHANCE := 0.30

var _defs: Array = []


func _ready() -> void:
	if FileAccess.file_exists(CONFIG):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if parsed is Dictionary:
			_defs = parsed.get("visits", [])
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("slot_changed"):
		tm.slot_changed.connect(func(_slot: int) -> void: _maybe_visit())
	var game := get_node_or_null("/root/GameManager")
	if game != null and game.has_signal("game_started"):
		game.game_started.connect(func() -> void: call_deferred("reconcile_story_timeline"))


func _maybe_visit() -> void:
	if not _can_visit():
		return
	if randf() > VISIT_CHANCE:
		return
	var v := _pick()
	if v.is_empty():
		return
	if str(v.get("dialogue", "")) != "" \
			and not GameManager.claim_story_beat("visit:" + str(v.get("id", ""))):
		return
	GameManager.flags["visit_last_day"] = int(TimeManager.day_counter)
	UIManager.toggle_window("win_visitor", func() -> Control:
		var w := VisitorWindow.new()
		w.visit = v
		return w)


## Darf jetzt jemand klingeln? Zu Hause, richtige Tageszeit, kein Dialog/Besuch/
## Anruf offen, höchstens 1 Besuch pro Tag.
func _can_visit() -> bool:
	if GameManager.state != GameManager.State.PLAYING:
		return false
	# TimeManager emittiert auch waehrend Save-Hydration und Reisezeit. Beides
	# sind technische Zeitwechsel, kein Moment, in dem der Spieler bereits im
	# Zimmer sitzt und ein echter Haustuerbesuch beginnen darf.
	if SaveManager.is_restoring_game() or GameManager.is_traveling():
		return false
	if GameManager.current_location_id != "room":
		return false
	if not (int(TimeManager.slot) in VISIT_SLOTS):
		return false
	if int(GameManager.flags.get("visit_last_day", -1)) == int(TimeManager.day_counter):
		return false
	if DialogueManager.is_active():
		return false
	var layer: Variant = UIManager.window_layer
	if layer != null and (layer.get_node_or_null("win_visitor") != null \
			or layer.get_node_or_null("win_incoming") != null):
		return false
	return true


## Aktuell passende Besuche (Ära + Vertrauen + Fakt + Einmal-Sperre).
func _eligible() -> Array:
	var year := int(TimeManager.year)
	var done: Array = GameManager.flags.get("visits_done", [])
	var pool: Array = []
	for v: Dictionary in _defs:
		if TimeManager.day_counter < int(v.get("day_from", 0)):
			continue
		if year < int(v.get("year_from", 1990)):
			continue
		if v.has("year_to") and year > int(v["year_to"]):
			continue
		if not _campaign_gate_open(v):
			continue
		var needs := str(v.get("needs", ""))
		if needs != "" and not NarrativeManager.fact_true(needs):
			continue
		# Flag-Gates (wie bei Anrufen): Story-Besuche hängen am Spielzustand,
		# z. B. Daniel klingelt erst, wenn der Amiga läuft (requires_flag).
		if v.has("requires_flag") and not bool(GameManager.flags.get(str(v["requires_flag"]), false)):
			continue
		if v.has("unless_flag") and bool(GameManager.flags.get(str(v["unless_flag"]), false)):
			continue
		if NPCManager.get_trust(str(v.get("npc", ""))) < int(v.get("trust_min", 0)):
			continue
		if bool(v.get("once", false)) and str(v.get("id", "")) in done:
			continue
		if str(v.get("dialogue", "")) != "" and not GameManager.story_beat_available():
			continue
		pool.append(v)
	return pool


## Questtragende Haustuerbesuche folgen demselben 60-Wochen-Director wie ihr
## Auftrag. Ein blosses year_from reichte nicht: Nach dem Jahreswechsel ist der
## globale day_counter laengst groesser als jedes historische day_from und liess
## dadurch spaete Kapitel schon am ersten Ferientag klingeln.
func _campaign_gate_open(visit: Dictionary) -> bool:
	var quest_id := str(visit.get("campaign_quest", ""))
	if quest_id.is_empty():
		return true
	var gate: Dictionary = QuestManager.campaign_slot(quest_id)
	if gate.is_empty():
		return false
	var planned_year := int(gate.get("year", int(visit.get("year_from", 1990))))
	if TimeManager.year < planned_year:
		return false
	if TimeManager.year > planned_year:
		return true
	var progress: Dictionary = TimeManager.campaign_progress()
	return str(progress.get("phase", "")) == "summer" \
		and int(progress.get("week", 0)) >= int(gate.get("week", 1))


## Alte Saves koennen einen priorisierten Besuch bereits vor seiner vorgesehenen
## Woche angenommen haben. Solange dessen Quest weder aktiv noch erledigt ist,
## wird ausschliesslich dieser verfruehte Intro-Merker zurueckgenommen; Inventar,
## Vertrauen und echte Questfortschritte bleiben unangetastet. Der Besuch kann
## dann in seinem richtigen Kapitel erneut stattfinden.
func reconcile_story_timeline() -> Array[String]:
	var repaired: Array[String] = []
	var done: Array = GameManager.flags.get("visits_done", [])
	for visit: Dictionary in _defs:
		var quest_id := str(visit.get("campaign_quest", ""))
		if quest_id.is_empty() or _campaign_gate_open(visit) \
				or QuestManager.is_active(quest_id) or QuestManager.is_done(quest_id):
			continue
		var visit_id := str(visit.get("id", ""))
		var intro_flag := str(visit.get("unless_flag", ""))
		var touched := false
		while visit_id in done:
			done.erase(visit_id)
			touched = true
		if not intro_flag.is_empty() and bool(GameManager.flags.get(intro_flag, false)):
			GameManager.flags.erase(intro_flag)
			touched = true
		if touched:
			repaired.append(visit_id)
	if not repaired.is_empty():
		GameManager.flags["visits_done"] = done
		QuestManager.evaluate()
	return repaired


## IDs der aktuell möglichen Besuche (Debug/Test).
func eligible_ids() -> Array:
	var out: Array = []
	for v in _eligible():
		out.append(str(v.get("id", "")))
	return out


## Passenden Besuch wählen (gewichtet über die möglichen). Story-Besuche mit
## `priority` (Queststarts) gehen IMMER vor Zufalls-Besuchen — so kommen die
## Tutorial-Übergänge zuverlässig nacheinander statt im Losglück unterzugehen.
func _pick() -> Dictionary:
	var pool := _eligible()
	if pool.is_empty():
		return {}
	for v: Dictionary in pool:
		if bool(v.get("priority", false)):
			return v
	var total := 0.0
	for v in pool:
		total += float(v.get("weight", 1))
	var roll := randf() * total
	for v in pool:
		roll -= float(v.get("weight", 1))
		if roll <= 0.0:
			return v
	return pool.back()


## Reinlassen: kurzes Gespräch + Geschenk/Neuigkeit/Aufgabe (Effekt-DSL).
## Story-Besuche mit `dialogue` öffnen ein VOLLES verzweigtes Gespräch (Queststart).
func accept(visit: Dictionary) -> bool:
	# Geschenke zuerst atomar einlagern. Ist etwa die Diskettenbox voll, bleibt der
	# Besuch vor der Tür und kann nach dem Aufräumen erneut angenommen werden.
	var result: Dictionary = EventManager.apply_effects(visit.get("effects", []))
	if not bool(result.get("ok", false)):
		return false
	var npc := str(visit.get("npc", ""))
	var dlg := str(visit.get("dialogue", ""))
	if dlg != "":
		DialogueManager.start_dialogue(dlg, npc)
	else:
		DialogueManager.start_bark(npc, str(visit.get("speaker", "?")), str(visit.get("text", "")))
	_mark_done(visit)
	return true


## Nicht reinlassen: der Freund zieht (etwas gekränkt) wieder ab.
func decline(visit: Dictionary) -> void:
	NPCManager.change_trust(str(visit.get("npc", "")), -1)
	UIManager.toast(Loc.t("sys.visit_manager.s_zieht_enttauscht_wieder_ab", "%s zieht enttäuscht wieder ab.") % str(visit.get("speaker", "Der Besuch")))


func _mark_done(visit: Dictionary) -> void:
	if not bool(visit.get("once", false)):
		return
	var done: Array = GameManager.flags.get("visits_done", [])
	var id := str(visit.get("id", ""))
	if not (id in done):
		done.append(id)
		GameManager.flags["visits_done"] = done
