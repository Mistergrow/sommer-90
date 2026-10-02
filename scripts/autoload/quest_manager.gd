extends Node
## Autoritativer Questzustand und Orchestrator der ausgelagerten Ziel-, Text-,
## Präsentations- und Auditdienste. Konkrete Handlungen zählen ausschließlich
## für die aktive Stufe; `evaluate()` reagiert nach Effekten und Tageswechseln.

signal quests_changed
## Flüchtiges HUD-Ereignis; wird nur bei echtem Fortschritt emittiert.
signal quest_event(event: Dictionary)
## Presenter leeren hierüber bei Slotwechseln ihre laufenden Hinweise.
signal quest_presentation_reset

const SaveMigration := preload("res://scripts/autoload/quest_save_migration.gd")

const CAMPAIGN_STORY_CONFIG := "res://data/campaign_story.json"
const QuestDefinitions := preload("res://scripts/data/quest_definition_catalog.gd")
const StefanGames := preload("res://scripts/games/stefan_game_catalog.gd")
const DanielLessons := preload("res://scripts/data/daniel_lesson_catalog.gd")
const StefanMoments := preload("res://scripts/data/stefan_moment_catalog.gd")
const SommerGameQuests := preload("res://scripts/data/sommer_game_quest_catalog.gd")
const GoalEvaluator := preload("res://scripts/quest/quest_goal_evaluator.gd")
const EvaluationScheduler := preload("res://scripts/quest/quest_evaluation_scheduler.gd")
const CampaignSchedule := preload("res://scripts/quest/quest_campaign_schedule.gd")
const QuestText := preload("res://scripts/quest/quest_text_service.gd")
const QuestPresentation := preload("res://scripts/quest/quest_presentation_service.gd")
const QuestAudit := preload("res://scripts/quest/quest_audit_service.gd")

var _defs: Array = []
var _by_id: Dictionary = {}    # quest_id -> Definition (Index statt O(n)-Scan in def())
var _status: Dictionary = {}   # quest_id -> {stage:int, done:bool}
var _busy := false             # Reentrancy-Schutz (Belohnung → apply_effects → evaluate)
var _evaluation_scheduler: RefCounted
var _campaign_slots: Dictionary = {}  # quest_id -> {year, week}


func _ready() -> void:
	_evaluation_scheduler = EvaluationScheduler.new(evaluate)
	_load_definitions()
	_load_campaign_story()
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(func() -> void: evaluate())
	var stats := get_node_or_null("/root/PlayerStats")
	if stats != null and stats.has_signal("stats_changed"):
		stats.stats_changed.connect(_evaluation_scheduler.request)


func _load_definitions() -> void:
	_defs = []
	_by_id = {}
	_defs = QuestDefinitions.definitions()
	_defs.append_array(StefanGames.quest_definitions())
	_defs.append_array(DanielLessons.quest_definitions())
	_defs.append_array(StefanMoments.quest_definitions())
	_defs.append_array(SommerGameQuests.quest_definitions())
	for q: Dictionary in _defs:
		var id := str(q.get("id", ""))
		if id.is_empty():
			continue
		if _by_id.has(id):
			push_error("QuestManager: doppelte Quest-ID %s" % id)
			continue
		_by_id[id] = q


func _load_campaign_story() -> void:
	_campaign_slots = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_STORY_CONFIG))
	if not parsed is Dictionary:
		push_error("campaign_story.json fehlt oder ist ungueltig.")
		return
	var years: Dictionary = (parsed as Dictionary).get("years", {})
	for year_key: String in years:
		for chapter: Dictionary in years.get(year_key, []):
			for quest_id: Variant in chapter.get("quest_ids", []):
				_campaign_slots[str(quest_id)] = {"year": int(year_key), "week": int(chapter.get("week", 1))}


func campaign_slot(id: String) -> Dictionary:
	return (_campaign_slots.get(id, {}) as Dictionary).duplicate()


func _campaign_slot_open(id: String) -> bool:
	return CampaignSchedule.is_open(id, _campaign_slots, def(id),
		TimeManager.campaign_progress(), TimeManager.year, is_done)


func def(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Welche Spielfunktion ERKLÄRT diese Quest ("" = keine)? Fundament für den
## Tutorial-Core: Erklärungen/Hilfen hängen an teaches-Markern der Questpakete.
func teaches(id: String) -> String:
	return str(def(id).get("teaches", ""))


func is_tutorial(id: String) -> bool:
	return teaches(id) != ""


func is_active(id: String) -> bool:
	return _status.has(id) and not bool(_status[id].get("done", false))


func is_done(id: String) -> bool:
	return _status.has(id) and bool(_status[id].get("done", false))


func stage(id: String) -> int:
	return int(_status.get(id, {}).get("stage", 0))


## Wie oft wurde eine konkrete Aktion fuer diesen Auftrag verbucht? Oeffentlich,
## damit Dialog-/Eventbedingungen z. B. eine fertige Compo-Demo erkennen koennen.
func action_count(id: String, action: String) -> int:
	return int(_status.get(id, {}).get("actions", {}).get(action, 0))


## Eine echte Gameplay-Handlung fuer passende aktuelle Queststufen verbuchen.
## Bewusst KEIN globales Flag: Eine Kopie von 1990 erfuellt keinen Auftrag von
## 1997, und eine Demo kann nicht rueckwirkend bei einer Compo eingereicht werden.
func note_action(action: String, amount := 1, context: Dictionary = {}) -> void:
	if action.is_empty() or amount <= 0:
		return
	var changed := false
	var matched_quests: Array = []
	for q: Dictionary in active_quests():
		var qid := str(q.get("id", ""))
		var stages: Array = q.get("stages", [])
		var si := stage(qid)
		if si < 0 or si >= stages.size():
			continue
		var goal: Dictionary = stages[si].get("goal", {})
		if str(goal.get("action", "")) != action:
			continue
		# Alex verlangt drei verschiedene Archivquellen. Derselbe Titel darf
		# weiterhin mehrfach gesichert werden, zaehlt fuer diese Stufe aber nur
		# einmal. Alte direkte Test-/Dialogaufrufe ohne Kontext bleiben kompatibel.
		if action == "backup_disk" and not context.is_empty():
			var source_uid := str(context.get("source_uid", ""))
			if not source_uid.is_empty():
				var sources: Dictionary = _status[qid].get("action_sources", {})
				var seen: Array = sources.get(action, [])
				if source_uid in seen:
					continue
				seen.append(source_uid)
				sources[action] = seen
				_status[qid]["action_sources"] = sources
		var actions: Dictionary = _status[qid].get("actions", {})
		actions[action] = int(actions.get(action, 0)) + amount
		_status[qid]["actions"] = actions
		matched_quests.append(qid)
		changed = true
	PlaytestTelemetry.note_quest_action(action, amount, matched_quests)
	if changed:
		evaluate()


func active_quests() -> Array:
	var out: Array = []
	for q: Dictionary in _defs:
		if is_active(str(q.get("id", ""))):
			out.append(localized_definition(q))
	return out


## Physische Auftragsdatentraeger duerfen nicht nur als unsichtbarer Programm-
## Unlock existieren. `required_disks` in der Questdefinition ist die gemeinsame
## Wahrheit fuer Zustellung, Save-Recovery und Schutz vor einer Sackgasse.
func reconcile_required_disks(show_blocked := false) -> Array[String]:
	var delivered: Array[String] = []
	for q: Dictionary in active_quests():
		var quest_id := str(q.get("id", ""))
		for requirement: Dictionary in q.get("required_disks", []):
			if not _disk_requirement_applies(quest_id, requirement):
				continue
			var template_id := str(requirement.get("id", ""))
			var existing := _find_required_disk(requirement)
			if existing != null:
				if bool(requirement.get("grant_missing", true)):
					var template: Dictionary = DiskManager.templates.get(template_id, {})
					var expected_program := str(template.get("program_id", ""))
					var payload_lost := existing.content_type == "leer" \
						or (not expected_program.is_empty() and existing.program_id != expected_program)
					# Ein kaputtes oder geloeschtes, aber noch physisch vorhandenes
					# Pflichtmedium darf die Story nicht dauerhaft blockieren.
					if existing.condition <= 0 or payload_lost:
						var condition_range: Array = template.get("condition_range", [80, 100])
						existing.condition = maxi(1, int(condition_range[0]))
						existing.checked = true
						existing.label = str(template.get("label", existing.label))
						existing.labeled = not existing.label.is_empty()
						existing.brand = str(template.get("brand", existing.brand))
						existing.color = str(template.get("color", existing.color))
						existing.content_type = str(template.get("content_type", existing.content_type))
						existing.content_title = str(template.get("content_title", existing.content_title))
						existing.program_id = expected_program
						existing.write_protected = existing.content_type != "leer"
						existing.memory = str(requirement.get("memory", existing.memory))
						DiskManager.disks_changed.emit()
						delivered.append(template_id)
						_toast(str(requirement.get("recovery_text",
							"Die benötigte Auftragsdiskette wurde ersetzt.")))
				_apply_required_disk_state(existing, requirement)
				_capture_required_disk(existing, requirement)
				_install_program_from_disk_template(template_id)
				continue
			if not bool(requirement.get("grant_missing", true)) or template_id.is_empty():
				continue
			if not DiskManager.templates.has(template_id):
				push_warning("Quest %s verlangt unbekannte Diskette %s" % [quest_id, template_id])
				continue
			if not DiskManager.can_store_disks(1):
				if show_blocked:
					_toast(str(requirement.get("blocked_text",
						"In deiner Diskettenbox fehlt ein Platz für eine Auftragsdiskette.")))
				continue
			var replacement := DiskManager.create_disk(template_id,
				str(requirement.get("memory", "Für Auftrag »%s« erhalten" % str(q.get("title", quest_id)))))
			if replacement != null:
				_apply_required_disk_state(replacement, requirement)
			if replacement != null and DiskManager.add_disk(replacement):
				_capture_required_disk(replacement, requirement)
				_install_program_from_disk_template(template_id)
				delivered.append(template_id)
				_toast(str(requirement.get("recovery_text",
					"Die benötigte Auftragsdiskette liegt jetzt in deiner Diskettenbox.")))
	return delivered


## Manche spaete Kreativauftraege brauchen eine Mindestbibliothek. Der Auftrag
## liefert nur fehlende Titel aus seinem eigenen Materialpaket nach; vorhandene
## Sammlungen und deren Historie bleiben unangetastet. Das repariert auch Saves,
## in denen ein frueherer optionaler Club-/Flohmarkt-Fund ausgelassen wurde.
func reconcile_required_music_tracks() -> Array[String]:
	var delivered: Array[String] = []
	for q: Dictionary in active_quests():
		var quest_deliveries: Array[String] = []
		for raw_requirement: Variant in q.get("required_music_tracks", []):
			var track_id := str(raw_requirement.get("id", "")) \
				if raw_requirement is Dictionary else str(raw_requirement)
			if track_id.is_empty():
				continue
			if MusicManager.track(track_id).is_empty():
				push_warning("Quest %s verlangt unbekannten MOD-Titel %s" % [
					str(q.get("id", "")), track_id])
				continue
			if MusicManager.collect(track_id):
				delivered.append(track_id)
				quest_deliveries.append(track_id)
		if not quest_deliveries.is_empty():
			_toast(str(q.get("required_music_text",
				"Ein fehlendes Musikpaket wurde deiner MOD-Sammlung hinzugefügt.")))
	return delivered


func reconcile_required_items() -> Array[String]:
	var delivered: Array[String] = []
	for q: Dictionary in active_quests():
		var quest_id := str(q.get("id", ""))
		for requirement: Dictionary in q.get("required_items", []):
			if not _disk_requirement_applies(quest_id, requirement):
				continue
			var item_id := str(requirement.get("id", ""))
			var required_count := maxi(1, int(requirement.get("count", 1)))
			var missing := required_count - InventoryManager.count(item_id)
			if item_id.is_empty() or missing <= 0:
				continue
			InventoryManager.add_item(item_id, missing)
			delivered.append(item_id)
			_toast(str(requirement.get("recovery_text",
				"Das benötigte Verbrauchsmaterial wurde bereitgelegt.")))
	return delivered


## Software-Werkzeuge sind ebenso echte Questressourcen wie Disketten oder
## Verbrauchsmaterial. In normalen Runs installiert die zugehörige Programmdisk
## das Werkzeug. Diese zweite Sicherung heilt alte Saves, in denen die Quest
## bereits aktiv war, bevor es die physische Zustellung gab, und verhindert bei
## voller Diskettenbox eine unsichtbare Sackgasse. Die Programmdisk selbst wird
## weiterhin von `required_disks` nachgeliefert, sobald wieder Platz frei ist.
func reconcile_required_programs() -> Array[String]:
	var installed: Array[String] = []
	for q: Dictionary in active_quests():
		var quest_id := str(q.get("id", ""))
		for raw_requirement: Variant in q.get("required_programs", []):
			var requirement: Dictionary = raw_requirement if raw_requirement is Dictionary \
				else {"id": str(raw_requirement)}
			if not _disk_requirement_applies(quest_id, requirement) \
					or not bool(requirement.get("grant_missing", true)):
				continue
			var program_id := str(requirement.get("id", ""))
			if program_id.is_empty() or ProgramLibrary.is_installed(program_id):
				continue
			if ProgramLibrary.get_program(program_id).is_empty():
				push_warning("Quest %s verlangt unbekanntes Programm %s" % [
					quest_id, program_id])
				continue
			if ProgramLibrary.install(program_id):
				installed.append(program_id)
				_toast(str(requirement.get("recovery_text",
					"Ein benötigtes Auftragsprogramm wurde auf der Werkbank bereitgestellt.")))
	return installed


func reconcile_required_resources(show_blocked := false) -> bool:
	var disk_changes := reconcile_required_disks(show_blocked)
	var program_changes := reconcile_required_programs()
	var music_changes := reconcile_required_music_tracks()
	var item_changes := reconcile_required_items()
	return not disk_changes.is_empty() or not music_changes.is_empty() \
		or not item_changes.is_empty() or not program_changes.is_empty()


## Liefert den aktiven Schutzvertrag fuer eine konkrete Diskette. UI und
## Formatierer nutzen dieselbe Abfrage, statt Quest-IDs zu duplizieren.
func disk_requirement(disk: Disk) -> Dictionary:
	if disk == null:
		return {"required": false}
	# Auch konkrete Board-Aufgaben können ein physisches Medium binden. Sie
	# erhalten exakt denselben zentralen Schutz wie mehrstufige Quests.
	var task_gate: Dictionary = TaskManager.disk_requirement(disk)
	if bool(task_gate.get("required", false)):
		return task_gate
	for q: Dictionary in active_quests():
		var quest_id := str(q.get("id", ""))
		for requirement: Dictionary in q.get("required_disks", []):
			if _disk_requirement_applies(quest_id, requirement) \
					and _disk_matches_requirement(disk, requirement):
				return {
					"required": true,
					"quest_id": quest_id,
					"text": str(requirement.get("protect_text",
						"Diese Diskette wird noch für den aktiven Auftrag benötigt.")),
				}
	return {"required": false}


func _disk_requirement_applies(quest_id: String, requirement: Dictionary) -> bool:
	var current_stage := stage(quest_id)
	return current_stage >= int(requirement.get("from_stage", 0)) \
		and current_stage <= int(requirement.get("through_stage", 2147483647))


func _disk_matches_requirement(disk: Disk, requirement: Dictionary) -> bool:
	var has_selector := false
	var has_non_uid_selector := false
	var unresolved_uid_without_fallback := false
	if requirement.has("uid_flag"):
		has_selector = true
		var captured_uid := str(GameManager.flags.get(str(requirement.get("uid_flag", "")), ""))
		if not captured_uid.is_empty():
			if disk.uid != captured_uid:
				return false
		else:
			var expected_memory := str(requirement.get("memory", ""))
			if not expected_memory.is_empty() and disk.memory != expected_memory:
				return false
			unresolved_uid_without_fallback = expected_memory.is_empty()
	if requirement.has("id"):
		has_selector = true
		has_non_uid_selector = true
		if disk.template_id != str(requirement.get("id", "")):
			return false
	if requirement.has("software_id"):
		has_selector = true
		has_non_uid_selector = true
		if disk.software_id != str(requirement.get("software_id", "")):
			return false
	if requirement.has("content_type"):
		has_selector = true
		has_non_uid_selector = true
		if disk.content_type != str(requirement.get("content_type", "")):
			return false
	if requirement.has("release_role"):
		has_selector = true
		has_non_uid_selector = true
		if disk.release_role != str(requirement.get("release_role", "")):
			return false
	if requirement.has("release_serial_prefix"):
		has_selector = true
		has_non_uid_selector = true
		if not disk.release_serial.begins_with(str(requirement.get("release_serial_prefix", ""))):
			return false
	if requirement.has("release_project_kind"):
		has_selector = true
		has_non_uid_selector = true
		if str(disk.release_data.get("project_kind", "")) \
				!= str(requirement.get("release_project_kind", "")):
			return false
	if bool(requirement.get("player_copy_only", false)):
		has_selector = true
		has_non_uid_selector = true
		if not disk.is_player_made_copy() or disk.is_game_master():
			return false
	if bool(requirement.get("source_only", false)):
		has_selector = true
		has_non_uid_selector = true
		if disk.is_player_made_copy():
			return false
	return has_selector and (not unresolved_uid_without_fallback or has_non_uid_selector)


func _find_required_disk(requirement: Dictionary) -> Disk:
	var newest: Disk = null
	for disk: Disk in DiskManager.disks:
		if _disk_matches_requirement(disk, requirement):
			if not bool(requirement.get("prefer_newest_release", false)):
				return disk
			if newest == null or disk.release_serial.naturalnocasecmp_to(
					newest.release_serial) > 0:
				newest = disk
	return newest


func _apply_required_disk_state(disk: Disk, requirement: Dictionary) -> void:
	if requirement.has("memory"):
		disk.memory = str(requirement.get("memory", disk.memory))
	if requirement.has("virus"):
		disk.virus = bool(requirement.get("virus", false))
	if requirement.has("checked"):
		disk.checked = bool(requirement.get("checked", false))


func _capture_required_disk(disk: Disk, requirement: Dictionary) -> void:
	var uid_flag := str(requirement.get("uid_flag", ""))
	if not uid_flag.is_empty():
		GameManager.flags[uid_flag] = disk.uid


func _install_program_from_disk_template(template_id: String) -> void:
	var template: Dictionary = DiskManager.templates.get(template_id, {})
	var program_id := str(template.get("program_id", ""))
	if not program_id.is_empty() and not ProgramLibrary.is_installed(program_id):
		ProgramLibrary.install(program_id)


## Orte mit laufenden Missionen fuer die Stadtkarte. Stufen duerfen einen
## praezisen `map_location`/`map_locations`-Marker setzen; ohne Override zeigt
## die Karte den Stammsitz des Auftraggebers. Damit bleiben auch alte Quests
## markiert, ohne eine zweite Quest-Wahrheit zu pflegen.
func active_location_ids() -> Array:
	var out: Array = []
	for q: Dictionary in active_quests():
		var locations: Array = []
		var stages: Array = q.get("stages", [])
		var si := stage(str(q.get("id", "")))
		var current: Dictionary = stages[si] if si >= 0 and si < stages.size() else {}
		if current.has("map_locations"):
			locations.assign(current.get("map_locations", []))
		elif current.has("map_location"):
			locations.append(str(current.get("map_location", "")))
		elif q.has("map_locations"):
			locations.assign(q.get("map_locations", []))
		elif q.has("map_location"):
			locations.append(str(q.get("map_location", "")))
		else:
			var giver := str(q.get("giver", ""))
			var npc: Dictionary = NPCManager.get_npc(giver) if giver != "" else {}
			var home := str(npc.get("location", ""))
			locations.append("room" if home == "home" else home)
		for location: Variant in locations:
			var id := str(location)
			if id != "" and TownManager.location_ids().has(id) and not out.has(id):
				out.append(id)
	return out


## Bereits abgeschlossene Aufträge für den Notizblock. Nutzt denselben
## persistent gespeicherten Status; es entsteht bewusst kein zweites Questlog.
func completed_quests() -> Array:
	var out: Array = []
	for q: Dictionary in _defs:
		if is_done(str(q.get("id", ""))):
			out.append(localized_definition(q))
	return out


func total() -> int:
	return _defs.size()


## Autoritative, schreibgeschuetzte Sicht auf alle Questdefinitionen. Tests,
## Berichte und Editoren muessen dadurch nicht mehr auf `_defs` zugreifen und
## koennen ausdruecklich zwischen Rohdaten und spielerfertigem Text waehlen.
func definitions(localized := true) -> Array:
	var out: Array = []
	for q: Dictionary in _defs:
		out.append(localized_definition(q) if localized else q.duplicate(true))
	return out


func done_count() -> int:
	var n := 0
	for id in _status:
		if bool(_status[id].get("done", false)):
			n += 1
	return n


## Aktuelle Stufen-Beschreibung eines aktiven Auftrags.
func current_stage_text(id: String) -> String:
	return localized_stage_text(id, stage(id))


## Eine einzige Sprachgrenze fuer alle Quest-Oberflaechen. Manuelle Auftraege
## lesen die extrahierten quest.<id>-Schluessel; generierte Familien benutzen
## stabile Vorlagen und bleiben dadurch auch nach einem Sprachwechsel korrekt.
func localized_title(id: String) -> String:
	return QuestText.title(def(id), id)


func localized_stage_text(id: String, stage_index: int) -> String:
	return QuestText.stage_text(def(id), id, stage_index)


func localized_definition(q: Dictionary) -> Dictionary:
	return QuestText.definition(q)


func _uses_authored_quest_keys(q: Dictionary) -> bool:
	return QuestText.uses_authored_keys(q)


func _localized_effects(quest_id: String, path: String, effects: Array,
		use_authored_keys := true) -> Array:
	return QuestText.effects(quest_id, path, effects, use_authored_keys)


# ------------------------------------------------------------- Read-only Audit

## Maschinenlesbare Erklärung, warum eine Quest aktiv/gesperrt/erledigt ist.
## Diese API mutiert weder Flags noch Status und ist damit für Debug-Konsole,
## Balancing-Bericht und spätere externe Analyse geeignet.
func explain_activation(id: String) -> Dictionary:
	var q := def(id)
	var slot: Dictionary = campaign_slot(id)
	var result := QuestAudit.activation(id, q, slot, _campaign_slot_open(id),
		is_done(id), is_active(id), localized_title(id))
	if bool(result.get("exists", false)):
		result["current_stage"] = stage(id) if _status.has(id) else -1
	return result


## Erklärung der gerade aktiven Stufe mit Ist-/Sollwerten. Bei noch nicht
## aktiven Quests wird Stufe 0 erklärt, ohne sie zu starten.
func explain_current_stage(id: String) -> Dictionary:
	var q := def(id)
	var stages: Array = q.get("stages", [])
	var index := stage(id) if _status.has(id) else 0
	var checks: Array = []
	if index >= 0 and index < stages.size():
		checks = _goal_explanation((stages[index] as Dictionary).get("goal", {}), id)
	return QuestAudit.current_stage(id, q, index, is_done(id),
		localized_stage_text(id, index), checks)


func audit_snapshot() -> Dictionary:
	var quests: Array = []
	for q: Dictionary in _defs:
		var id := str(q.get("id", ""))
		quests.append({"activation": explain_activation(id), "stage": explain_current_stage(id)})
	return {"generated_at": Time.get_datetime_string_from_system(),
		"campaign": TimeManager.campaign_progress(), "quest_count": total(),
		"done_count": done_count(), "quests": quests}


func _goal_explanation(goal: Dictionary, quest_id: String) -> Array:
	return GoalEvaluator.checks(goal, quest_id, action_count, _template_goal_count)


# ------------------------------------------------------------- Kernschleife

## Alle Aufträge prüfen: neue aktivieren, erfüllte Stufen abhaken, Abschluss
## belohnen. Idempotent + reentrant-sicher (Belohnungen dürfen Effekte auslösen).
func evaluate() -> void:
	if _busy:
		return
	_busy = true
	var changed := false
	var presentation_events: Array[Dictionary] = []
	for q in _defs:
		var qid := str(q.get("id", ""))
		# 1) Aktivieren, wenn Voraussetzung erfüllt.
		if not _status.has(qid):
			if _campaign_slot_open(qid) and _cond_met(q.get("prereq", {})):
				_status[qid] = {"stage": 0, "done": false, "actions": {}}
				var start_result := _apply(_localized_effects(qid, "on_start",
					q.get("on_start", []), _uses_authored_quest_keys(q)))
				if not bool(start_result.get("ok", false)):
					_status.erase(qid)
					continue
				PlaytestTelemetry.note_quest_started(qid, localized_title(qid), 0)
				_toast(Loc.t("sys.quest_manager.neuer_auftrag_s", "📋 Neuer Auftrag: %s") % localized_title(qid))
				presentation_events.append(_presentation_event(q, "started"))
				changed = true
			else:
				continue
		var st: Dictionary = _status[qid]
		if bool(st.get("done", false)):
			continue
		# 2) Stufen abhaken, solange das jeweilige Ziel erfüllt ist.
		var stages: Array = q.get("stages", [])
		while int(st["stage"]) < stages.size():
			var completed_stage := int(st["stage"])
			var stg: Dictionary = stages[completed_stage]
			var goal: Dictionary = stg.get("goal", {})
			if bool(goal.get("manual", false)) or not _goal_met(goal, qid):
				break
			var finishes_quest := completed_stage + 1 >= stages.size()
			var rewards: Array = _localized_effects(qid,
				"stages%d.reward" % completed_stage, stg.get("reward", []),
				_uses_authored_quest_keys(q))
			if finishes_quest:
				rewards.append_array(_localized_effects(qid, "reward",
					q.get("reward", []), _uses_authored_quest_keys(q)))
			var reward_result := _apply(rewards)
			if not bool(reward_result.get("ok", false)):
				break
			st["stage"] = int(st["stage"]) + 1
			changed = true
			if int(st["stage"]) >= stages.size():
				st["done"] = true
				_toast(Loc.t("sys.quest_manager.auftrag_erfullt_s", "✅ Auftrag erfüllt: %s") % localized_title(qid))
				presentation_events.append(_presentation_event(q, "completed",
					localized_stage_text(qid, completed_stage)))
			else:
				_toast("📋 %s: %s" % [localized_title(qid), current_stage_text(qid)])
				presentation_events.append(_presentation_event(q, "stage"))
			PlaytestTelemetry.note_quest_stage_completed(qid, completed_stage,
				str(stg.get("desc", "")), int(st["stage"]), bool(st.get("done", false)))
	_busy = false
	if reconcile_required_resources(false):
		changed = true
	if changed:
		quests_changed.emit()
		for event: Dictionary in presentation_events:
			quest_event.emit(event.duplicate(true))


## Manuelle Stufe weiterschalten (Dialog/Event-Effekt {quest_advance, id}).
func advance(id: String) -> bool:
	if not is_active(id):
		return false
	var q := def(id)
	var st: Dictionary = _status[id]
	var stages: Array = q.get("stages", [])
	if int(st["stage"]) >= stages.size():
		return false
	var completed_stage := int(st["stage"])
	var completed_definition: Dictionary = stages[completed_stage]
	var finishes_quest := completed_stage + 1 >= stages.size()
	var rewards: Array = _localized_effects(id, "stages%d.reward" % completed_stage,
		completed_definition.get("reward", []), _uses_authored_quest_keys(q))
	if finishes_quest:
		rewards.append_array(_localized_effects(id, "reward", q.get("reward", []),
			_uses_authored_quest_keys(q)))
	var reward_result := _apply(rewards)
	if not bool(reward_result.get("ok", false)):
		return false
	st["stage"] = int(st["stage"]) + 1
	if int(st["stage"]) >= stages.size():
		st["done"] = true
		_toast(Loc.t("sys.quest_manager.auftrag_erfullt_s", "✅ Auftrag erfüllt: %s") % localized_title(id))
	else:
		_toast("📋 %s: %s" % [localized_title(id), current_stage_text(id)])
	PlaytestTelemetry.note_quest_stage_completed(id, completed_stage,
		str(completed_definition.get("desc", "")), int(st["stage"]), bool(st.get("done", false)))
	quests_changed.emit()
	quest_event.emit(_presentation_event(q, "completed" if bool(st.get("done", false)) else "stage",
		localized_stage_text(id, completed_stage)))
	evaluate()
	return true


## Baut das einzige UI-neutrale Ereignisformat fuer neue/fortgeschrittene/
## abgeschlossene Auftraege. Stilentscheidungen bleiben bewusst im
## QuestPresentationCatalog; der QuestManager liefert nur belastbare Semantik.
func _presentation_event(q: Dictionary, kind: String, completed_text := "") -> Dictionary:
	var qid := str(q.get("id", ""))
	return QuestPresentation.build_event(q, kind, completed_text, stage(qid),
		Callable(self, "localized_title"), Callable(self, "localized_stage_text"),
		Callable(self, "is_tutorial"), Callable(self, "_localized_effects"),
		Callable(self, "_uses_authored_quest_keys"))


## Rendert ein bereits gepuffertes Ereignis in der aktuell gewaehlten Sprache
## neu. Der Praesentationslayer benutzt das beim Live-Sprachwechsel; Queststand
## und gespeicherte Definitionen werden dabei nicht veraendert.
func presentation_event_for(event: Dictionary) -> Dictionary:
	var quest_id := str(event.get("id", event.get("quest_id", "")))
	var q := def(quest_id)
	if q.is_empty():
		return event.duplicate(true)
	var kind := str(event.get("kind", "started"))
	var completed_text := ""
	if kind == "completed":
		var completed_stage := maxi(0, int(event.get("stage_number", stage(quest_id))) - 1)
		completed_text = localized_stage_text(quest_id, completed_stage)
	return _presentation_event(q, kind, completed_text)


# ------------------------------------------------------------- Prädikate

func _flag(flag_name: String) -> bool:
	return bool(GameManager.flags.get(flag_name, false))


## Voraussetzung eines Auftrags (Aktivierung): Jahr, Flags, Welt-Fakten.
func _cond_met(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("year_min") and TimeManager.year < int(cond["year_min"]):
		return false
	if cond.has("year_max") and TimeManager.year > int(cond["year_max"]):
		return false
	if cond.has("age_min") and PlayerIdentity.age() < int(cond["age_min"]):
		return false
	if cond.has("flag") and not _flag(str(cond["flag"])):
		return false
	if cond.has("not_flag") and _flag(str(cond["not_flag"])):
		return false
	for f in cond.get("needs", []):
		if not NarrativeManager.fact_true(str(f)):
			return false
	return true


## Ziel einer Stufe erfüllt? Dockt an vorhandene Mechaniken an.
func _goal_met(goal: Dictionary, quest_id := "") -> bool:
	return GoalEvaluator.is_met(goal, quest_id, action_count, _template_goal_count)


## Alte Template-Ziele behalten exakt ihre bisherige Besitzlogik. Einzelne
## Quests koennen zusaetzlich dieselben sicheren Medienfilter wie Dialoge und
## Uebergaben verlangen; Alex' Fundsuche reagiert dadurch nicht mehr auf eine
## bereits identifizierte Diskette mit historisch gleicher Template-ID.
func _template_goal_count(goal: Dictionary) -> int:
	var template_id := str(goal.get("has_template", ""))
	if not bool(goal.get("unresolved_mystery", false)) \
			and not goal.has("content_type"):
		return DiskManager.disks.filter(func(d: Disk) -> bool:
			return d.template_id == template_id).size()
	var criteria := {
		"id": template_id,
		"unresolved_mystery": bool(goal.get("unresolved_mystery", false)),
	}
	if goal.has("content_type"):
		criteria["content_type"] = str(goal.get("content_type", ""))
	return DiskManager.matching_media(criteria).size()


func _apply(effects: Array) -> Dictionary:
	if effects.is_empty():
		return {"ok": true, "reason": "", "text": ""}
	return EventManager.apply_effects(effects)


func _toast(text: String) -> void:
	var ui := get_node_or_null("/root/UIManager")
	if ui != null:
		ui.call("toast", text)


func to_dict() -> Dictionary:
	return {"status": _status}


func from_dict(d: Dictionary) -> void:
	quest_presentation_reset.emit()
	# Questdefinitionen sind Build-Daten, nicht Save-Daten. Beim Laden wird immer
	# die aktuelle Fassung neu gelesen, damit Datenmigrationen und neue physische
	# Pflichtmedien auch in einer laufenden Editor-Session sofort greifen.
	_load_definitions()
	_load_campaign_story()
	_status = d.get("status", {})
	_backfill_completed_stage_actions()
	reconcile_required_resources(true)
	quests_changed.emit()
	# Alte Saves können bereits alle Bedingungen der gespeicherten Stufe
	# erfüllen. Nach dem vollständigen Ladeframe werden sie idempotent
	# nachgezogen, statt bis zum nächsten Tageswechsel hängen zu bleiben.
	if _evaluation_scheduler != null:
		_evaluation_scheduler.request()
	else:
		call_deferred("evaluate")


## Rekonstruiert ausschliesslich dauerhafte Fortschritts-Flags aus gespeichertem
## Queststatus. Das ist keine Belohnungswiederholung: Geld, Gegenstaende, Ruf und
## Aktionen bleiben unangetastet. Ein aktiver Auftrag beweist sein Intro und
## seine on_start-Flags; eine erreichte Stufe beweist die Flag-Belohnungen aller
## vorherigen Stufen; ein erledigter Auftrag beweist zusaetzlich seine Abschluss-
## Flags. Damit koennen alte Saves keine Folgequests oder Rueckrufe verlieren,
## nur weil eine fruehe Fassung den redundanten Meilenstein noch nicht speicherte.
func reconcile_progress_flags() -> Array[String]:
	var restored: Array[String] = []
	for quest_id: String in _status:
		var q: Dictionary = def(quest_id)
		if q.is_empty():
			continue
		var prereq_flag := str(q.get("prereq", {}).get("flag", ""))
		_restore_progress_flag(prereq_flag, true, restored)
		_restore_flags_from_effects(q.get("on_start", []), restored)
		var quest_status: Dictionary = _status[quest_id]
		var stages: Array = q.get("stages", [])
		var completed_count := stages.size() if bool(quest_status.get("done", false)) \
			else mini(int(quest_status.get("stage", 0)), stages.size())
		for stage_index in completed_count:
			_restore_flags_from_effects((stages[stage_index] as Dictionary).get("reward", []), restored)
		if bool(quest_status.get("done", false)):
			_restore_flags_from_effects(q.get("reward", []), restored)
	return restored


func _restore_flags_from_effects(effects: Array, restored: Array[String]) -> void:
	for effect: Dictionary in effects:
		if str(effect.get("type", "")) != "flag":
			continue
		_restore_progress_flag(str(effect.get("flag", "")), effect.get("value", true), restored)


func _restore_progress_flag(flag_name: String, value: Variant,
		restored: Array[String]) -> void:
	if flag_name.is_empty() or GameManager.flags.has(flag_name):
		return
	GameManager.flags[flag_name] = value
	restored.append(flag_name)


## Save-Migration für ältere Auftragsstände: Frühe Builds speicherten zwar die
## erreichte Stufe, aber noch nicht für jede bereits absolvierte Stufe deren
## Aktionszähler. Ein Auftrag auf Stufe 2 ist selbst der verbindliche Beweis,
## dass Stufe 1 erfüllt wurde. Wir rekonstruieren nur frühere/abgeschlossene
## Stufen mit dem Minimalwert 1; die aktuelle Stufe wird nie vorerfüllt.
func _backfill_completed_stage_actions() -> void:
	SaveMigration.backfill(_status, def)

func reset() -> void:
	if _evaluation_scheduler != null:
		_evaluation_scheduler.cancel()
	quest_presentation_reset.emit()
	_status = {}
	quests_changed.emit()
