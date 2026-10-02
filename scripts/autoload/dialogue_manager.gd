extends Node
## DialogueManager — Dialogbäume aus den pro NPC getrennten Contentpaketen.
## Ein Dialog besteht aus Knoten mit Sprecher, Text und Wahlmöglichkeiten;
## Wahlen können Effekte (Effekt-DSL des EventManagers) auslösen.

signal node_changed
signal dialogue_ended

const DialogueDefinitions := preload("res://scripts/data/dialogue_definition_catalog.gd")

var dialogues: Dictionary = {}
var active_id: String = ""
var node_id: String = ""
var active_npc: String = ""   # für trust-Bedingungen + Gesprächs-Erinnerung
var _bark: Dictionary = {}    # transiente Einzelzeile (NarrativeManager)
var _session_serial := 0       # Fenster erkennt, ob es noch denselben Dialog zeigt


func _ready() -> void:
	_load_data()


func _load_data() -> void:
	dialogues = DialogueDefinitions.definitions()


func is_active() -> bool:
	return active_id != ""


## Transiente Gespraeche gehoeren weder in einen neuen Durchlauf noch ueber
## einen Save-Load hinweg. Der Sessionzaehler entwertet eventuell noch zum
## Frame-Ende auslaufende Fenster, bevor sie einen neuen Zustand beenden koennen.
func reset() -> void:
	var was_active := is_active()
	active_id = ""
	node_id = ""
	active_npc = ""
	_bark = {}
	_session_serial += 1
	if was_active:
		dialogue_ended.emit()


func current_session_serial() -> int:
	return _session_serial


## Dialog starten; öffnet das Dialogfenster über den UIManager. npc = für
## trust-Bedingungen und die Gesprächs-Erinnerung (Flag talked_<npc>).
func start_dialogue(id: String, npc: String = "", start_node: String = "") -> void:
	if not dialogues.has(id):
		push_warning("Unbekannter Dialog: %s" % id)
		return
	if id == "mike_orakel":
		AchievementManager.note("heard_oracle")
	active_id = id
	var nodes: Dictionary = dialogues[id].get("nodes", {})
	var requested_node := start_node.strip_edges()
	if requested_node != "" and not nodes.has(requested_node):
		push_warning("Unbekannter Dialogknoten: %s/%s" % [id, requested_node])
		requested_node = ""
	node_id = requested_node if requested_node != "" else str(dialogues[id].get("start", ""))
	active_npc = npc
	if active_npc == "":
		active_npc = str(dialogues[id].get("npc", ""))
	if active_npc == "":
		var first: Dictionary = dialogues[id].get("nodes", {}).get(node_id, {})
		active_npc = _speaker_id(first, "")
	_bark = {}
	_session_serial += 1
	_ensure_dialogue_window()
	node_changed.emit()


## Registriert einen zur Laufzeit aus Contentdaten gebauten Dialog und startet
## ihn ueber denselben typografisch getesteten Dialogpfad wie statische Baeume.
## Ausfuehrbarer Code wird dabei nie geladen; erlaubt sind nur Dialogdaten und
## die bestehende EventManager-Effekt-DSL.
func start_runtime_dialogue(id: String, npc: String, definition: Dictionary) -> void:
	if id.strip_edges().is_empty() or not definition.get("nodes", {}) is Dictionary:
		push_warning("Ungueltiger Runtime-Dialog: %s" % id)
		return
	dialogues[id] = definition.duplicate(true)
	start_dialogue(id, npc)


## Transiente Einzelzeile zeigen (NarrativeManager wählt sie aus dem Pool).
## `presentation` ist optional und damit zu allen alten 3-Argument-Aufrufen
## kompatibel. Unterstützt: emotion, delivery und channel.
func start_bark(npc: String, speaker: String, text: String,
		presentation: Variant = {}) -> void:
	var present: Dictionary = {}
	if presentation is Dictionary:
		present = presentation.duplicate(true)
	elif str(presentation) != "":
		present["emotion"] = str(presentation)
	var channel := str(present.get("channel", ""))
	if channel == "":
		channel = "phone" if speaker.strip_edges().begins_with("☎") else "in_person"
	var delivery: Variant = present.get("delivery", {})
	if channel == "phone" and not present.has("delivery"):
		delivery = "phone"
	active_id = "__bark__"
	active_npc = npc
	node_id = "n1"
	_bark = {"speaker": speaker, "speaker_id": npc, "text": text,
		"channel": channel, "emotion": str(present.get("emotion", "")),
		"delivery": delivery, "direction": present.get("direction", {}),
		"choices": [{"text": Loc.t("sys.dialogue_manager.see_you", "Bis dann!"), "next": null}]}
	_session_serial += 1
	_ensure_dialogue_window()
	node_changed.emit()


## Aktueller Knoten ({speaker, text, choices}) — Choices sind bereits nach ihren
## Bedingungen (cond) gefiltert, sodass nur passende Optionen erscheinen.
func current_node() -> Dictionary:
	if not is_active():
		return {}
	if active_id == "__bark__":
		var b := _bark.duplicate(true)
		b["choices"] = _visible_choices(b.get("choices", []))
		b["speaker_id"] = _speaker_id(b, active_npc)
		return b
	var node: Dictionary = dialogues[active_id].get("nodes", {}).get(node_id, {}).duplicate(true)
	if node.is_empty():
		return {}
	# Uebersetzung erst HIER, nicht beim Laden: so bleiben die NPC-Pakete die
	# deutsche Quelle, und ein Sprachwechsel im laufenden Spiel wirkt sofort auf
	# den naechsten Knoten. Fehlt ein Katalogeintrag, liefert Loc.t den deutschen
	# Quelltext zurueck — nie einen rohen Schluessel.
	node["text"] = Loc.t("dlg.%s.%s.text" % [active_id, node_id], str(node.get("text", "")))
	# Uebersetzt wird VOR dem Sichtbarkeitsfilter: _visible_choices() laesst
	# bedingte Antworten weg, wodurch sich die Indizes verschieben wuerden. Der
	# Katalogschluessel benutzt eine stabile Autoren-ID; alte dynamische
	# Antworten ohne ID behalten ihren Index vor dem Sichtbarkeitsfilter.
	var raw_choices: Array = node.get("choices", [])
	for index in raw_choices.size():
		var choice: Dictionary = raw_choices[index]
		choice["text"] = Loc.t(DialogueDefinitionCatalog.choice_key(active_id, node_id, choice, index),
			str(choice.get("text", "")))
	node["choices"] = _visible_choices(raw_choices)
	node["speaker_id"] = _speaker_id(node, active_npc)
	if not node.has("channel"):
		node["channel"] = "in_person"
	if not node.has("emotion"):
		node["emotion"] = ""
	if not node.has("delivery"):
		node["delivery"] = {}
	return node


## Prioritaet ist Teil des Datenvertrags: explizite Knoten-ID, aktive
## Gespraechsperson, erst danach der normalisierte Anzeigename.
func _speaker_id(node: Dictionary, fallback: String) -> String:
	var explicit := str(node.get("speaker_id", "")).strip_edges()
	if explicit != "":
		return explicit
	if fallback.strip_edges() != "":
		return fallback
	return _id_for_speaker_name(str(node.get("speaker", "")))


func _id_for_speaker_name(speaker: String) -> String:
	var wanted := _normalize_speaker_name(speaker)
	if wanted == "":
		return ""
	var npcs_node := get_node_or_null("/root/NPCManager")
	if npcs_node != null:
		if npcs_node.has_method("id_for_name"):
			var resolved := str(npcs_node.call("id_for_name", speaker))
			if resolved != "":
				return resolved
		# Kompatibilitaets-Fallback fuer isolierte Test-Harnesses/alte Manager.
		var all_npcs: Dictionary = npcs_node.get("npcs")
		for id in all_npcs:
			if _normalize_speaker_name(str(all_npcs[id].get("name", ""))) == wanted:
				return str(id)
	var player := get_node_or_null("/root/PlayerIdentity")
	if player != null and _normalize_speaker_name(str(player.get("player_name"))) == wanted:
		return "player"
	return ""


static func _normalize_speaker_name(value: String) -> String:
	var clean := value.strip_edges()
	while clean.begins_with("☎"):
		clean = clean.trim_prefix("☎").strip_edges()
	for prefix in ["telefon:", "anruf:"]:
		if clean.to_lower().begins_with(prefix):
			clean = clean.substr(prefix.length()).strip_edges()
	return clean.to_lower()


## Ein bereits sichtbares Dialogfenster wird weiterverwendet. Das verhindert
## den alten queue_free/toggle-Race; ein gerade geloeschtes Fenster wird im
## naechsten Frame frisch geoeffnet und liest dann den aktuellen Knoten.
func _ensure_dialogue_window() -> void:
	var layer: Node = UIManager.get("window_layer")
	var existing: Node = layer.get_node_or_null("win_dialogue") if layer != null else null
	if existing != null and not existing.is_queued_for_deletion():
		return
	if existing != null:
		UIManager.call_deferred("open_dialogue")
	else:
		UIManager.open_dialogue()


func _visible_choices(choices: Array) -> Array:
	var out: Array = []
	for c in choices:
		if _cond_ok(c.get("cond", null)):
			out.append(c)
	return out


## Read-only Dialog-Audit. Wichtig: Index bezieht sich hier absichtlich auf die
## Rohdaten, damit auch unsichtbare Optionen samt Bedingung diagnostizierbar sind.
func explain_choice(dialogue_id: String, wanted_node: String, choice_index: int) -> Dictionary:
	var dialogue: Dictionary = dialogues.get(dialogue_id, {})
	var node: Dictionary = dialogue.get("nodes", {}).get(wanted_node, {})
	var choices: Array = node.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return {"exists": false, "dialogue": dialogue_id, "node": wanted_node, "index": choice_index}
	var choice: Dictionary = choices[choice_index]
	return {"exists": true, "dialogue": dialogue_id, "node": wanted_node, "index": choice_index,
		"text": str(choice.get("text", "")), "visible": _cond_ok(choice.get("cond", null)),
		"condition": choice.get("cond", null)}


## Wahl treffen (Index in die SICHTBAREN Choices). Nur eine vollständig
## ausgeführte Effekt-Transaktion darf den Dialog weiterschalten oder beenden.
func choose(index: int) -> bool:
	var choices: Array = current_node().get("choices", [])
	if index < 0 or index >= choices.size():
		return false
	var choice: Dictionary = choices[index]
	var once_key := _choice_effect_once_key(choice)
	var effects: Array = choice.get("effects", [])
	if not once_key.is_empty() and bool(GameManager.flags.get(once_key, false)):
		effects = []
	var result: Dictionary = EventManager.apply_effects(effects)
	if not bool(result.get("ok", false)):
		return false
	if not once_key.is_empty() and not effects.is_empty():
		GameManager.flags[once_key] = true
	if active_id != "__bark__":
		PlaytestTelemetry.note_dialogue_choice(active_id, node_id, active_npc,
			str(choice.get("text", "")))
	var next = choice.get("next", null)
	if next == null:
		end_dialogue()
	else:
		node_id = str(next)
		node_changed.emit()
	return true


## Optionaler Datenvertrag gegen Dialog-Farming. Einzelne Choices koennen
## `effects_once` setzen; ein ganzer Baum kann mit `choice_effects_once` alle
## Belohnungen je Antwort einmalig machen. Die Antwort selbst bleibt wiederholbar,
## damit bereits gelesene Informationen nicht kuenstlich verschwinden.
func _choice_effect_once_key(choice: Dictionary) -> String:
	if active_id in ["", "__bark__"]:
		return ""
	var dialogue: Dictionary = dialogues.get(active_id, {})
	var marker: Variant = choice.get("effects_once", false)
	var marker_enabled := false
	if marker is bool:
		marker_enabled = marker
	elif marker is String:
		marker_enabled = not str(marker).strip_edges().is_empty()
	if not marker_enabled and not bool(dialogue.get("choice_effects_once", false)):
		return ""
	var token := str(marker).strip_edges() if marker is String else ""
	if token.is_empty() or token == "True" or token == "true":
		token = (node_id + ":" + str(choice.get("text", ""))).sha256_text().left(20)
	return "dialogue_effect_once:%s:%s" % [active_id, token]


func end_dialogue() -> void:
	if not is_active():
		return
	# Gesprächs-Erinnerung: Weltflags, damit Bäume auf frühere Gespräche reagieren.
	if active_id != "" and active_id != "__bark__":
		GameManager.flags["seen_" + active_id] = true
	if active_npc != "":
		GameManager.flags["talked_" + active_npc] = true
	active_id = ""
	node_id = ""
	active_npc = ""
	_bark = {}
	dialogue_ended.emit()
	QuestManager.evaluate()   # Auftraege, die auf Gespraeche warten (talked_<npc>)
	# Erst NACH den Dialogeffekten und der Quest-Auswertung darf ein weiterer
	# historischer Rueckruf derselben Person eingereiht werden. Beim blossen
	# Entnehmen des ersten Rueckrufs waere dessen Intro-Flag noch nicht gesetzt;
	# die Save-Heilung wuerde ihn sonst im naechsten Frame erneut erzeugen.
	PhoneManager.call_deferred("reconcile_story_timeline")


## Bedingungs-Auswerter für Choices (und später Knoten). cond = Dictionary mit
## Prädikaten (ALLE müssen zutreffen) oder Array solcher Dictionaries.
func _cond_ok(cond) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c in cond:
			if not _cond_ok(c):
				return false
		return true
	if not (cond is Dictionary):
		return true
	for key in cond:
		var v: Variant = cond[key]
		match key:
			"flag":                       # {"quest_x": "done", ...}
				for fn in v:
					if str(GameManager.flags.get(fn, "")) != str(v[fn]):
						return false
			"not_flag":                   # Flag NICHT gesetzt
				if GameManager.flags.get(str(v), null) not in [null, "", false]:
					return false
			"ruf_min":
				if PlayerStats.ruf < int(v):
					return false
			"ruf_max":
				if PlayerStats.ruf > int(v):
					return false
			"money_min":
				if PlayerStats.geld < int(v):
					return false
			"age_min":
				if PlayerIdentity.age() < int(v):
					return false
			"wissen_min":
				if PlayerStats.wissen < int(v):
					return false
			"day_min":
				if TimeManager.day_counter < int(v):
					return false
			"year_min":
				if TimeManager.year < int(v):
					return false
			"year_max":
				if TimeManager.year > int(v):
					return false
			"has_hardware":
				if not PlayerStats.has_hardware(str(v)):
					return false
			"no_hardware":
				if PlayerStats.has_hardware(str(v)):
					return false
			"has_item":                   # "id" (min 1) ODER {"id": min}
				if v is Dictionary:
					for it in v:
						if InventoryManager.count(it) < int(v[it]):
							return false
				elif InventoryManager.count(str(v)) < 1:
					return false
			"has_template":               # "template" ODER {id, count}
				var wanted := str(v.get("id", "")) if v is Dictionary else str(v)
				var need := int(v.get("count", 1)) if v is Dictionary else 1
				var have := 0
				for disk: Disk in DiskManager.disks:
					if disk.template_id == wanted and disk.condition > 0:
						have += 1
				if have < need:
					return false
			"has_disk_match":
				if not v is Dictionary:
					return false
				var criteria: Dictionary = v
				var need := maxi(1, int(criteria.get("count", 1)))
				if DiskManager.matching_media(criteria).size() < need:
					return false
			"not_has_disk_match":
				if not v is Dictionary:
					return false
				var criteria: Dictionary = v
				var need := maxi(1, int(criteria.get("count", 1)))
				if DiskManager.matching_media(criteria).size() >= need:
					return false
			"has_player_copy_of":
				if not DiskManager.has_player_copy_of(str(v)):
					return false
			"not_has_template":
				if DiskManager.has_template(str(v)):
					return false
			"quest_active":
				if not QuestManager.is_active(str(v)):
					return false
			"quest_done":
				if not QuestManager.is_done(str(v)):
					return false
			"quest_stage":                # {id:"q_x", stage:1}
				if not (v is Dictionary) or not QuestManager.is_active(str(v.get("id", ""))) \
						or QuestManager.stage(str(v.get("id", ""))) != int(v.get("stage", 0)):
					return false
			"quest_action":               # {id:"q_x", action:"...", min:1}
				if not (v is Dictionary) or QuestManager.action_count(str(v.get("id", "")),
						str(v.get("action", ""))) < int(v.get("min", 1)):
					return false
			"trust_min":
				if NPCManager.get_trust(active_npc) < int(v):
					return false
	return true
