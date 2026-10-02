extends Node
## NarrativeManager — der Story-/Kontinuitäts-Core (AAA). Verhindert Logik- und
## Erzählfehler über 10 Spieljahre, indem NPC-Zeilen aus zeit- & fakten-bedingten
## POOLS gewählt werden statt aus festen Bäumen:
##  - `facts`: WANN etwas wahr wird (Jahr / Weltflag) — die Wahrheit der Welt.
##  - Jede Zeile trägt needs/forbids (Fakten), from/to (Jahr), trust_min, once.
##  - pick_line() wählt eine GÜLTIGE, nicht kürzlich gesagte Zeile → Abwechslung.
## Anachronismen ("PC-Zeile" vor 1995, Demo-Zeile nachdem Stefan einen PC hat …)
## sind so strukturell unmöglich; der Linter tests/narrative_check.gd fängt Rest-
## fehler VOR dem Spiel ab. Daten MODULAR: data/narrative/facts.json +
## data/narrative/lines/<npc>.json (je NPC eine Datei, AAA-wartbar).

const FACTS_PATH := "res://data/narrative/facts.json"
const LINES_DIR := "res://data/narrative/lines"
const RECENT_MAX := 5

var facts_def: Dictionary = {}       # id -> {from, flag}
var lines: Dictionary = {}           # npc_id -> [line]
var _recent: Dictionary = {}         # npc_id -> [line_id] (Ring gegen Wiederholung)
var _once: Dictionary = {}           # npc_id -> {line_id: true}


func _ready() -> void:
	_load()


func _load() -> void:
	# Welt-Fakten.
	if FileAccess.file_exists(FACTS_PATH):
		var f: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACTS_PATH))
		if f is Dictionary:
			facts_def = f.get("facts", {})
	# Zeilen-Pools: jede data/narrative/lines/*.json ist ein NPC.
	lines = {}
	var dir := DirAccess.open(LINES_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(LINES_DIR + "/" + file))
		if d is Dictionary and d.has("lines"):
			lines[str(d.get("npc", file.get_basename()))] = d["lines"]


# ------------------------------------------------------------- Welt-Fakten
func fact_true(id: String) -> bool:
	var f: Variant = facts_def.get(id, null)
	if not (f is Dictionary):
		return false
	if TimeManager.year < int(f.get("from", 0)):
		return false
	if f.has("flag") and not _flag_set(str(f["flag"])):
		return false
	return true


func _flag_set(flag_name: String) -> bool:
	# bool()-Cast statt Vergleichskette: `true != ""` wertet in GDScript zu
	# false aus und wuerde Bool-Flags (z. B. club_mitglied) faelschlich verwerfen.
	return bool(GameManager.flags.get(flag_name, false))


# ------------------------------------------------------------- Zeilen-Auswahl
## Ist die Zeile jetzt gültig? (Jahr-Fenster, needs/forbids-Fakten, trust, once)
func line_ok(npc_id: String, line: Dictionary) -> bool:
	var year := TimeManager.year
	if line.has("from") and year < int(line["from"]):
		return false
	if line.has("to") and year > int(line["to"]):
		return false
	for nf in line.get("needs", []):
		if not fact_true(str(nf)):
			return false
	for ff in line.get("forbids", []):
		if fact_true(str(ff)):
			return false
	if line.has("trust_min") and NPCManager.get_trust(npc_id) < int(line["trust_min"]):
		return false
	if bool(line.get("once", false)) and _once.get(npc_id, {}).has(str(line.get("id", ""))):
		return false
	return true


## Beste Zeile: gültig + möglichst nicht kürzlich gesagt. Leer, wenn kein Pool.
func pick_line(npc_id: String) -> Dictionary:
	var pool: Array = lines.get(npc_id, [])
	var valid: Array = pool.filter(func(l: Dictionary) -> bool: return line_ok(npc_id, l))
	if valid.is_empty():
		return {}
	var recent: Array = _recent.get(npc_id, [])
	var fresh: Array = valid.filter(func(l: Dictionary) -> bool: return not (str(l.get("id", "")) in recent))
	var candidates: Array = fresh if not fresh.is_empty() else valid
	# Gewichtete Zufallsauswahl (weight, Default 1).
	var total := 0.0
	for l: Dictionary in candidates:
		total += float(l.get("weight", 1.0))
	var pick := randf() * total
	for l: Dictionary in candidates:
		pick -= float(l.get("weight", 1.0))
		if pick <= 0.0:
			return l
	return candidates[0]


## Merkt eine gesagte Zeile (Ring + once-Set).
func mark_said(npc_id: String, line_id: String) -> void:
	var recent: Array = _recent.get(npc_id, [])
	recent.append(line_id)
	while recent.size() > RECENT_MAX:
		recent.pop_front()
	_recent[npc_id] = recent
	for l: Dictionary in lines.get(npc_id, []):
		if str(l.get("id", "")) == line_id and bool(l.get("once", false)):
			var o: Dictionary = _once.get(npc_id, {})
			o[line_id] = true
			_once[npc_id] = o


## NPC ansprechen: frische Pool-Zeile zeigen; sonst Fallback auf den Default-Baum.
## Trägt die Zeile ein "dialogue"-Feld, öffnet sie statt eines Barks einen ganzen
## GESPRÄCHSBAUM (z. B. Mikes Zukunfts-Orakel) — so mischen sich unter die
## Einzeiler immer wieder echte, verzweigte Dialoge.
func talk(npc_id: String) -> void:
	# Aktive persoenliche Uebergaben haben Vorrang vor zufaelligen Barks. Sonst
	# kann Alex direkt vor dem Spieler stehen und trotzdem nur einen Spruch aus
	# dem Pool sagen, waehrend die benoetigte Diskette unangetastet bleibt.
	if npc_id == "npc_achim" and QuestManager.is_active("q_compo") \
			and QuestManager.stage("q_compo") == 1:
		DialogueManager.start_dialogue("achim_default", npc_id)
		return
	if npc_id == "npc_alex" and alex_archive_handoff_ready():
		# Die dokumentierte Dreier-Sicherung ist bereits vollbracht. Direkt in
		# den bestaetigenden Uebergabeknoten springen; ein zufaelliger Bark oder
		# eine alte Mystery-Disk darf diesen Abschluss nicht verdecken.
		DialogueManager.start_dialogue("alex_default", npc_id, "n_archive_handover")
		return
	if npc_id == "npc_alex" and alex_mystery_handoff_ready():
		DialogueManager.start_dialogue("alex_default", npc_id)
		return
	# Offener Rückruf (Elternnotiz oder abgehörte AB-Nachricht)? Trifft man die
	# Person unterwegs, holt sie den vollständigen Storydialog von sich aus nach.
	var pending: Dictionary = PhoneManager.take_pending_entry(npc_id)
	if not pending.is_empty():
		# Ein alter Mike-Rückruf ist nach dem Queststart nur noch ein Duplikat.
		# Verbrauche ihn, aber öffne direkt den aktuellen Missionsdialog.
		if npc_id == "npc_mike" \
				and str(pending.get("id", "")) == "tam_mike_lappen" \
				and QuestManager.is_active("q_fuehrerschein"):
			DialogueManager.start_dialogue("mike_default", npc_id)
			return
		var pending_dialogue := str(pending.get("dialogue", ""))
		if pending_dialogue != "":
			DialogueManager.start_dialogue(pending_dialogue, npc_id)
			return
		var pspeaker := str(NPCManager.get_npc(npc_id).get("name", "?"))
		DialogueManager.start_bark(npc_id, pspeaker,
			"Da bist du ja! Ich hatte bei dir angerufen, aber keinen erreicht. Also: %s" \
				% str(pending.get("text", "")))
		return
	# Solange Mikes Führerschein-Auftrag offen ist, hat der kompakte
	# Missionsdialog Vorrang vor seinen zufälligen Sprüchen. Dadurch ist die
	# Prüfung bei jedem Besuch zuverlässig erreichbar.
	if npc_id == "npc_mike" and QuestManager.is_active("q_fuehrerschein"):
		DialogueManager.start_dialogue("mike_default", npc_id)
		return
	# Der Führerschein darf nicht von einem verpassten Telefonanruf abhängen.
	# Ab 17 spricht Mike das Thema beim persönlichen Besuch selbst an; das
	# anschließende Intro-Flag startet den altersgebundenen Auftrag unmittelbar.
	if npc_id == "npc_mike" and PlayerIdentity.age() >= 17 \
			and not bool(GameManager.flags.get("fuehrerschein_intro", false)) \
			and not QuestManager.is_active("q_fuehrerschein") \
			and not QuestManager.is_done("q_fuehrerschein"):
		DialogueManager.start_dialogue("call_mike_lappen", npc_id)
		return
	var line := pick_line(npc_id)
	if line.is_empty():
		var did := NPCManager.dialogue_for(npc_id)
		if did != "":
			DialogueManager.start_dialogue(did, npc_id)
		return
	mark_said(npc_id, str(line.get("id", "")))
	if line.has("dialogue"):
		DialogueManager.start_dialogue(str(line["dialogue"]), npc_id)
		return
	var speaker := str(NPCManager.get_npc(npc_id).get("name", "?"))
	var line_id := str(line.get("id", ""))
	var bark_key := "bark.%s.%s" % [npc_id.trim_prefix("npc_"), line_id]
	DialogueManager.start_bark(npc_id, speaker,
		Loc.t(bark_key, str(line.get("text", ""))),
		_line_presentation(line))


## Alex bleibt nach seiner Einfuehrungsquest ein echter Abgabekanal. Das
## Praedikat ist zugleich sein Dialog- und Anwesenheitsvertrag: Bereits
## identifizierte Inhalte und aktive Questdisketten zaehlen ausdruecklich nicht.
func alex_mystery_handoff_ready() -> bool:
	var quest_ready := (QuestManager.is_active("q_alex_find") \
		and QuestManager.stage("q_alex_find") == 1) \
		or QuestManager.is_done("q_alex_find")
	if not quest_ready:
		return false
	return not DiskManager.matching_media({
		"id": "mystery_unlabeled",
		"content_type": "mystery",
		"unresolved_mystery": true,
		"exclude_quest_required": true,
	}).is_empty()


## Storykritischer Markttermin nach drei verschiedenen, verifizierten Backups.
## Dieses Praedikat wird sowohl von Alex' Dialogprioritaet als auch von der
## Flohmarkt-Anwesenheit benutzt, damit Darstellung und Questlogik nie driften.
func alex_archive_handoff_ready() -> bool:
	return QuestManager.is_active("q_disk_archive") \
		and QuestManager.stage("q_disk_archive") == 1


func alex_market_handoff_ready() -> bool:
	return alex_archive_handoff_ready() or alex_mystery_handoff_ready()


## Praesentations-Metadaten bleiben optional und getrennt von Storybedingungen.
## Dadurch koennen einzelne wichtige Zeilen spaeter kuratiert werden, ohne die
## bestehenden 1.100+ Poolzeilen massenhaft anzufassen.
func _line_presentation(line: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in ["emotion", "delivery", "channel", "direction"]:
		if line.has(key):
			out[key] = line[key]
	return out


func has_pool(npc_id: String) -> bool:
	return lines.has(npc_id) and not lines[npc_id].is_empty()


func to_dict() -> Dictionary:
	return {"recent": _recent, "once": _once}


func from_dict(d: Dictionary) -> void:
	_recent = d.get("recent", {})
	_once = d.get("once", {})


func reset() -> void:
	_recent = {}
	_once = {}
