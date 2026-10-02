extends Node
## Lokale, datensparsame Playtest-Telemetrie fuer Kampagnen-Balancing.
##
## Erfasst ausschliesslich Spielsystem-Metadaten: aktive Sekunden, Kalender,
## Reisen, Schlaf, Questwechsel, vordefinierte Dialog-/Eventwahlen, Minispiele
## und Programmstarts. Keine Tastatureingaben, Freitexte, Dateien ausserhalb
## des Projekt-Benutzerordners oder Netzwerkdaten werden gespeichert.

signal report_changed

const SCHEMA_VERSION := 1
const MAX_TIMELINE := 4000
const MAX_SESSIONS := 96
const MAX_COLLECTION_SNAPSHOTS := 512
const IDLE_AFTER_MS := 5 * 60 * 1000
const EXPORT_DIR := "user://playtest_reports"
const LIVE_REPORT_PATH := EXPORT_DIR + "/live_playtest.json"
const DECADE_REPORT_ID := 90099
const DevelopmentGate := preload("res://scripts/core/development_gate.gd")
const REPORT_BUILDER_PATH := "res://scripts/dev/telemetry/playtest_report_builder.gd"
const REPORT_FORMATTER_PATH := "res://scripts/dev/telemetry/playtest_report_formatter.gd"
const GAME_FUNNELS_PATH := "res://scripts/dev/telemetry/playtest_game_funnels.gd"

var _state: Dictionary = {}
var _current_session: Dictionary = {}
var _last_input_ms := 0
var _checkpoint_pending := false
var _last_report_emit_second := -1
var _pending_day_seconds := 0.0


func _ready() -> void:
	_reset_state()
	if not is_enabled():
		process_mode = Node.PROCESS_MODE_DISABLED
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)
	call_deferred("_connect_runtime")


func is_enabled() -> bool:
	return DevelopmentGate.enabled() and bool(_state.get("enabled", true))


func _notification(what: int) -> void:
	if is_enabled() and what == NOTIFICATION_WM_CLOSE_REQUEST and GameManager.state == GameManager.State.PLAYING:
		write_live_checkpoint()


func _connect_runtime() -> void:
	if not is_enabled():
		return
	if not GameManager.game_started.is_connected(_on_game_started):
		GameManager.game_started.connect(_on_game_started)
	if not GameManager.returned_to_title.is_connected(_on_returned_to_title):
		GameManager.returned_to_title.connect(_on_returned_to_title)
	if not GameManager.location_changed.is_connected(_on_location_changed):
		GameManager.location_changed.connect(_on_location_changed)
	if not EventManager.event_triggered.is_connected(_on_event_triggered):
		EventManager.event_triggered.connect(_on_event_triggered)
	if not DiskManager.disks_changed.is_connected(_on_collection_changed):
		DiskManager.disks_changed.connect(_on_collection_changed)


func _input(_event: InputEvent) -> void:
	if not is_enabled():
		return
	# Nur der Zeitpunkt einer Eingabe haelt die aktive Session wach. Inhalt,
	# Taste, Mausposition und Text werden bewusst nicht gespeichert.
	_last_input_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if not _collecting_active_time():
		return
	# Debuggerstopps, Fensterverschiebungen und einzelne Frame-Stalls duerfen
	# keine Minuten in den Bericht schmuggeln.
	var seconds := minf(maxf(delta, 0.0), 1.0)
	if seconds <= 0.0:
		return
	_state["total_active_seconds"] = float(_state.get("total_active_seconds", 0.0)) + seconds
	_pending_day_seconds += seconds
	if not _current_session.is_empty():
		_current_session["active_seconds"] = float(_current_session.get("active_seconds", 0.0)) + seconds
	if _pending_day_seconds >= 1.0:
		_flush_active_time()
	var whole_second := int(float(_state.get("total_active_seconds", 0.0)))
	if whole_second != _last_report_emit_second and whole_second % 5 == 0:
		_last_report_emit_second = whole_second
		report_changed.emit()
		if whole_second > 0 and whole_second % 60 == 0:
			queue_live_checkpoint()


func _collecting_active_time() -> bool:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return false
	if get_tree().paused:
		return false
	if DisplayServer.get_name() != "headless" and not DisplayServer.window_is_focused():
		return false
	return Time.get_ticks_msec() - _last_input_ms <= IDLE_AFTER_MS


func reset() -> void:
	if not DevelopmentGate.enabled():
		_reset_state()
		return
	_end_session("new_game")
	_reset_state()
	_ensure_day()
	report_changed.emit()


func _reset_state() -> void:
	_state = {
		"schema_version": SCHEMA_VERSION,
		"enabled": DevelopmentGate.enabled(),
		# Keine Spiel-RNG verbrauchen: Telemetrie darf Zufallsereignisse und Handel
		# nicht durch eine scheinbar harmlose Lauf-ID verschieben.
		"run_id": "%d-%08x" % [int(Time.get_unix_time_from_system()),
			int(Time.get_ticks_usec()) & 0xFFFFFFFF],
		"started_at": Time.get_datetime_string_from_system(),
		"total_active_seconds": 0.0,
		"next_sequence": 1,
		"days": {},
		"years": {},
		"quests": {},
		"action_counts": {},
		"event_rolls": {"opportunities": 0, "chance_passed": 0, "with_candidates": 0},
		"collection_snapshots": [],
		"last_collection": {},
		"timeline": [],
		"sessions": [],
		"game_funnels": {},
		"last_export_path": "",
	}
	_current_session = {}
	_last_input_ms = Time.get_ticks_msec()
	_pending_day_seconds = 0.0


func _on_game_started() -> void:
	if not is_enabled():
		return
	_last_input_ms = Time.get_ticks_msec()
	var first_session := (_state.get("sessions", []) as Array).is_empty() \
		and float(_state.get("total_active_seconds", 0.0)) <= 0.0
	_begin_session()
	_ensure_day()
	# Alte Saves besitzen noch keinen Telemetrieblock. Aktive Quests werden ab
	# diesem Ladezeitpunkt beobachtet, ohne historische Zeiten zu erfinden.
	for quest: Dictionary in QuestManager.active_quests():
		var id := str(quest.get("id", ""))
		if not (_state.get("quests", {}) as Dictionary).has(id):
			note_quest_started(id, str(quest.get("title", id)), QuestManager.stage(id), true)
	_append_timeline("session_start", "", {"save_slot": SaveManager.active_slot}, false)
	_on_collection_changed()
	if first_session:
		UIManager.toast(Loc.t("sys.playtest_telemetry.playtest_messung_aktiv_lokal_automatisch_ohne", "PLAYTEST-MESSUNG aktiv: lokal, automatisch und ohne Eingabetexte. Bericht im Notizblock."))


func _on_returned_to_title() -> void:
	if not is_enabled():
		return
	_end_session("title")
	write_live_checkpoint()


func _begin_session() -> void:
	if not is_enabled():
		return
	if not _current_session.is_empty():
		_end_session("restart")
	_current_session = {
		"id": "%s-s%d" % [str(_state.get("run_id", "run")),
			(_state.get("sessions", []) as Array).size() + 1],
		"started_at": Time.get_datetime_string_from_system(),
		"started_game": _game_stamp(),
		"active_seconds": 0.0,
		"ongoing": true,
	}


func _end_session(reason: String) -> void:
	if not is_enabled():
		return
	if _current_session.is_empty():
		return
	_flush_active_time()
	var ended := _current_session.duplicate(true)
	ended["ongoing"] = false
	ended["ended_at"] = Time.get_datetime_string_from_system()
	ended["ended_game"] = _game_stamp()
	ended["ended_reason"] = reason
	var sessions: Array = _state.get("sessions", [])
	sessions.append(ended)
	if sessions.size() > MAX_SESSIONS:
		sessions = sessions.slice(sessions.size() - MAX_SESSIONS)
	_state["sessions"] = sessions
	_current_session = {}


# ------------------------------------------------------------- Laufzeithooks

func note_slots_advanced(amount: int) -> void:
	if not is_enabled() or amount <= 0 or GameManager.state != GameManager.State.PLAYING:
		return
	var day := _day_record()
	day["slots_advanced"] = int(day.get("slots_advanced", 0)) + amount
	_store_day(day)
	_increment_year("slots_advanced", amount)


func note_travel(from_id: String, to_id: String, mode: String, slots: int, dm: int,
		minutes := 0, wait_minutes := 0) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_touch_activity()
	var day := _day_record()
	day["travels"] = int(day.get("travels", 0)) + 1
	day["travel_slots"] = int(day.get("travel_slots", 0)) + maxi(0, slots)
	day["travel_minutes"] = int(day.get("travel_minutes", 0)) + maxi(0, minutes)
	day["travel_wait_minutes"] = int(day.get("travel_wait_minutes", 0)) + maxi(0, wait_minutes)
	day["travel_dm"] = int(day.get("travel_dm", 0)) + maxi(0, dm)
	_store_day(day)
	_increment_year("travels", 1)
	_increment_year("travel_slots", maxi(0, slots))
	_increment_year("travel_minutes", maxi(0, minutes))
	_increment_year("travel_wait_minutes", maxi(0, wait_minutes))
	_increment_count("travel_modes", mode, 1)
	_append_timeline("travel", to_id, {"from": from_id, "mode": mode,
		"slots": maxi(0, slots), "minutes": maxi(0, minutes),
		"wait_minutes": maxi(0, wait_minutes), "dm": maxi(0, dm)}, false)


func note_blocked(kind: String, id: String, reason: String) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_increment_day("blocked_attempts", 1, false)
	_increment_year("blocked_attempts", 1)
	_increment_count("blocked_counts", "%s:%s" % [kind, id], 1)
	_append_timeline("blocked", id, {"kind": kind, "reason": reason.left(240)}, false)


func _on_location_changed(id: String) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_increment_count("location_visits", id, 1)


func _on_collection_changed() -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	var sealed_ids := {}
	for disk: Disk in DiskManager.boxed_collection():
		if disk.package_condition == "sealed":
			sealed_ids[disk.software_id] = true
	var current := {"total_disks": DiskManager.media_count(),
		"boxed_sets": DiskManager.boxed_collection().size(),
		"unique_boxed_games": DiskManager.unique_boxed_game_count(),
		"sealed_boxed_games": sealed_ids.size()}
	var previous: Dictionary = _state.get("last_collection", {})
	if not previous.is_empty() and current == previous:
		return
	var snapshots: Array = _state.get("collection_snapshots", [])
	var snapshot := current.duplicate(true)
	snapshot["game"] = _game_stamp()
	snapshot["active_second"] = _active_second()
	snapshots.append(snapshot)
	if snapshots.size() > MAX_COLLECTION_SNAPSHOTS:
		snapshots = snapshots.slice(snapshots.size() - MAX_COLLECTION_SNAPSHOTS)
	_state["collection_snapshots"] = snapshots
	_state["last_collection"] = current
	var year := _year_record(TimeManager.year)
	if not year.has("ovp_start"):
		year["ovp_start"] = int(previous.get("unique_boxed_games", current.unique_boxed_games))
	year["ovp_end"] = int(current.unique_boxed_games)
	year["ovp_max"] = maxi(int(year.get("ovp_max", 0)), int(current.unique_boxed_games))
	year["sealed_ovp_end"] = int(current.sealed_boxed_games)
	year["disk_end"] = int(current.total_disks)
	_store_year(TimeManager.year, year)
	var gained_disks := int(current.total_disks) - int(previous.get("total_disks", current.total_disks))
	var gained_ovp := int(current.unique_boxed_games) - int(previous.get("unique_boxed_games", current.unique_boxed_games))
	if not previous.is_empty() and (gained_disks > 0 or gained_ovp > 0):
		_increment_day("collection_gains", 1, true)
	_append_timeline("collection", "", {"total_disks": int(current.total_disks),
		"unique_boxed_games": int(current.unique_boxed_games),
		"sealed_boxed_games": int(current.sealed_boxed_games),
		"delta_disks": gained_disks, "delta_ovp": gained_ovp}, gained_disks > 0 or gained_ovp > 0)


func note_sleep_start() -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_flush_active_time()
	var day := _day_record()
	day["sleep_count"] = int(day.get("sleep_count", 0)) + 1
	day["sleep_slot"] = TimeManager.slot
	var empty := int(day.get("meaningful_actions", 0)) == 0
	day["empty_sleep"] = empty
	_store_day(day)
	_increment_year("days_slept", 1)
	if empty:
		_increment_year("empty_sleeps", 1)
	_append_timeline("sleep", _date_key(), {"slot": TimeManager.slot,
		"meaningful_actions": int(day.get("meaningful_actions", 0)), "empty": empty}, false)
	queue_live_checkpoint()


func note_year_transition(next_year: int) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_flush_active_time()
	_append_timeline("year_transition", str(next_year), {"from_year": TimeManager.year}, false)
	queue_live_checkpoint()


func note_quest_action(action: String, amount: int, matched_quests: Array) -> void:
	if not is_enabled() or action.is_empty() or amount <= 0 or GameManager.state != GameManager.State.PLAYING:
		return
	_touch_activity()
	_increment_count("action_counts", action, amount)
	var day := _day_record()
	day["quest_actions"] = int(day.get("quest_actions", 0)) + amount
	day["meaningful_actions"] = int(day.get("meaningful_actions", 0)) + amount
	_store_day(day)
	_increment_year("meaningful_actions", amount)
	_append_timeline("quest_action", action, {"amount": amount,
		"matched_quests": matched_quests.duplicate()}, true)


func note_quest_started(id: String, title: String, stage_index := 0, observed_on_load := false) -> void:
	if not is_enabled() or id.is_empty():
		return
	var quests: Dictionary = _state.get("quests", {})
	if quests.has(id):
		return
	var entry := {
		"id": id,
		"title": title,
		"started_game": _game_stamp(),
		"started_active_second": _active_second(),
		"observed_on_load": observed_on_load,
		"stages": [],
		"completed": false,
	}
	entry["stages"].append(_new_stage_entry(id, stage_index))
	quests[id] = entry
	_state["quests"] = quests
	_append_timeline("quest_started", id, {"title": title,
		"stage": stage_index, "observed_on_load": observed_on_load}, false)
	report_changed.emit()


func note_quest_stage_completed(id: String, stage_index: int, description: String,
		next_stage: int, done: bool) -> void:
	if not is_enabled():
		return
	_increment_day("quest_stage_completions", 1, true)
	_increment_year("quest_stage_completions", 1)
	var quest := _quest_record(id)
	if quest.is_empty():
		var definition: Dictionary = QuestManager.def(id)
		note_quest_started(id, str(definition.get("title", id)), stage_index, true)
		quest = _quest_record(id)
	var stages: Array = quest.get("stages", [])
	var stage_entry: Dictionary = {}
	for candidate: Dictionary in stages:
		if int(candidate.get("index", -1)) == stage_index:
			stage_entry = candidate
			break
	if stage_entry.is_empty():
		stage_entry = _new_stage_entry(id, stage_index)
		stages.append(stage_entry)
	stage_entry["description"] = description
	stage_entry["completed_game"] = _game_stamp()
	stage_entry["completed_active_second"] = _active_second()
	stage_entry["active_duration_seconds"] = maxf(0.0,
		_active_second() - float(stage_entry.get("entered_active_second", _active_second())))
	if not done and not stages.any(func(item: Dictionary) -> bool:
		return int(item.get("index", -1)) == next_stage):
		stages.append(_new_stage_entry(id, next_stage))
	quest["stages"] = stages
	if done:
		quest["completed"] = true
		quest["completed_game"] = _game_stamp()
		quest["completed_active_second"] = _active_second()
		quest["active_duration_seconds"] = maxf(0.0,
			_active_second() - float(quest.get("started_active_second", _active_second())))
	_store_quest(id, quest)
	_append_timeline("quest_completed" if done else "quest_stage", id,
		{"stage": stage_index, "next_stage": next_stage, "done": done}, true)
	if done:
		queue_live_checkpoint()
	report_changed.emit()


func note_dialogue_choice(dialogue_id: String, node_id: String, npc_id: String,
		choice_text: String) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_touch_activity()
	_increment_day("dialogue_choices", 1, true)
	_increment_year("dialogue_choices", 1)
	_append_timeline("dialogue_choice", dialogue_id, {"node": node_id,
		"npc": npc_id, "choice": choice_text.left(240)}, true)


func note_event_choice(event_id: String, choice_text: String) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_touch_activity()
	_increment_day("event_choices", 1, true)
	_increment_year("event_choices", 1)
	_append_timeline("event_choice", event_id,
		{"choice": choice_text.left(240)}, true)


func _on_event_triggered(event: Dictionary) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	var id := str(event.get("id", "unknown"))
	_increment_day("events_triggered", 1, false)
	_increment_year("events_triggered", 1)
	_increment_count("event_counts", id, 1)
	_append_timeline("event_triggered", id, {"title": str(event.get("title", id)).left(160)}, false)


func note_event_roll(chance_passed: bool, candidate_count := -1) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_increment_day("event_opportunities", 1, false)
	_increment_year("event_opportunities", 1)
	if candidate_count > 0:
		_increment_day("event_candidate_opportunities", 1, false)
		_increment_year("event_candidate_opportunities", 1)
	var rolls: Dictionary = _state.get("event_rolls", {})
	rolls["opportunities"] = int(rolls.get("opportunities", 0)) + 1
	if chance_passed:
		rolls["chance_passed"] = int(rolls.get("chance_passed", 0)) + 1
	if candidate_count > 0:
		rolls["with_candidates"] = int(rolls.get("with_candidates", 0)) + 1
	_state["event_rolls"] = rolls


func note_minigame_finished(id: String, success: bool, score: int) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_touch_activity()
	_increment_day("minigames", 1, true)
	_increment_year("minigames", 1)
	if success:
		_increment_day("minigame_wins", 1, false)
	_append_timeline("minigame", id, {"success": success, "score": score}, true)


func note_game_started(id: String, details: Dictionary = {}) -> void:
	if not is_enabled():
		return
	var funnels: Script = load(GAME_FUNNELS_PATH) as Script
	if funnels != null:
		funnels.note_started(_state, id, details)
	_append_timeline("game_started", id, details, true)


func note_game_abandoned(id: String, details: Dictionary = {}) -> void:
	if not is_enabled():
		return
	var funnels: Script = load(GAME_FUNNELS_PATH) as Script
	if funnels != null:
		funnels.note_abandoned(_state, id, details)
	_append_timeline("game_abandoned", id, details, true)


func note_game_run(id: String, completed: bool, score: int, time_ms: int,
		details: Dictionary = {}) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING:
		return
	_touch_activity()
	_increment_day("game_runs", 1, true)
	_increment_year("game_runs", 1)
	var funnels: Script = load(GAME_FUNNELS_PATH) as Script
	if funnels != null:
		funnels.note_run(_state, id, completed, details)
	_append_timeline("game_run", id, {"completed": completed,
		"score": score, "time_ms": time_ms}, true)


func note_program_open(id: String) -> void:
	if not is_enabled() or GameManager.state != GameManager.State.PLAYING or id.is_empty():
		return
	_touch_activity()
	_increment_count("program_opens", id, 1)
	_increment_day("program_opens", 1, true)
	_increment_year("program_opens", 1)
	_append_timeline("program_open", id, {}, true)


func note_system(kind: String) -> void:
	if is_enabled() and GameManager.state == GameManager.State.PLAYING:
		_append_timeline("system", kind, {}, false)


# ------------------------------------------------------------- Bericht

func report(p_year := -1) -> Dictionary:
	if not is_enabled():
		return {"available": false, "development_only": true}
	_flush_active_time()
	var selector := TimeManager.year if p_year < 0 else int(p_year)
	var builder: Script = load(REPORT_BUILDER_PATH) as Script
	if builder == null:
		return {"available": false, "development_only": true, "error": "report_builder_missing"}
	return builder.build(_state, selector, _game_stamp(), _active_second())


func summary_text(p_report: Dictionary) -> String:
	if not is_enabled():
		return ""
	var formatter: Script = load(REPORT_FORMATTER_PATH) as Script
	return formatter.summary_text(p_report, TimeManager.year) if formatter != null else ""


func export_report(p_year := -1) -> Dictionary:
	if not is_enabled():
		return {"ok": false, "path": "", "absolute_path": "", "development_only": true}
	var selected_year := TimeManager.year if p_year < 0 else int(p_year)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var report_name := "decade_1990_1999" if selected_year == DECADE_REPORT_ID else str(selected_year)
	var path := "%s/playtest_%s_%s.json" % [EXPORT_DIR, report_name, stamp]
	var ok := _write_payload(path, selected_year)
	if ok:
		_state["last_export_path"] = path
		report_changed.emit()
	return {"ok": ok, "path": path if ok else "", "absolute_path":
		ProjectSettings.globalize_path(path) if ok else ""}


func write_live_checkpoint() -> bool:
	_checkpoint_pending = false
	if not is_enabled():
		return false
	# Headless-Vertragstests und Screenshot-Laeufe duerfen den echten,
	# langfristigen Playtestbericht des Spielers niemals ueberschreiben.
	if not _live_checkpoint_allowed():
		return false
	return _write_payload(LIVE_REPORT_PATH, TimeManager.year)


func queue_live_checkpoint() -> void:
	if not is_enabled() or _checkpoint_pending:
		return
	_checkpoint_pending = true
	write_live_checkpoint.call_deferred()


func report_directory_absolute() -> String:
	if not is_enabled():
		return ""
	return ProjectSettings.globalize_path(EXPORT_DIR)


func _live_checkpoint_allowed() -> bool:
	if not is_enabled():
		return false
	# Fuer bewusst headless ausgefuehrte Langzeit-Playtests bleibt ein expliziter
	# Opt-in moeglich. Manuelle Exporte sind davon unabhaengig.
	if OS.get_environment("DSS_PLAYTEST_PERSIST") == "1":
		return true
	return DisplayServer.get_name() != "headless" \
		and OS.get_environment("DSS_SHOT") != "1"


func _write_payload(path: String, selected_year: int) -> bool:
	var absolute_dir := ProjectSettings.globalize_path(EXPORT_DIR)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK and not DirAccess.dir_exists_absolute(absolute_dir):
		return false
	var payload := {
		"schema": "disk-scene-playtest-export/v1",
		"generated_at": Time.get_datetime_string_from_system(),
		"report": report(selected_year),
		"telemetry": to_dict(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()
	return true


# ------------------------------------------------------------- Analysehelfer

# ------------------------------------------------------------- Datenspeicher

func _touch_activity() -> void:
	_last_input_ms = Time.get_ticks_msec()


func _active_second() -> float:
	return float(_state.get("total_active_seconds", 0.0))


func _date_key() -> String:
	return "%04d-%02d-%02d" % [TimeManager.year, TimeManager.month, TimeManager.day]


func _game_stamp() -> Dictionary:
	var progress: Dictionary = TimeManager.campaign_progress()
	return {"year": TimeManager.year, "month": TimeManager.month, "day": TimeManager.day,
		"slot": TimeManager.slot, "slot_name": TimeManager.slot_name(),
		"day_counter": TimeManager.day_counter, "campaign_day": int(progress.get("day", 0)),
		"campaign_week": int(progress.get("week", 0)), "phase": str(progress.get("phase", ""))}


func _ensure_day() -> void:
	var day := _day_record()
	_store_day(day)
	var year := _year_record(TimeManager.year)
	var dates: Array = year.get("observed_dates", [])
	if _date_key() not in dates:
		dates.append(_date_key())
		year["observed_dates"] = dates
	_store_year(TimeManager.year, year)


func _day_record() -> Dictionary:
	var days: Dictionary = _state.get("days", {})
	if days.has(_date_key()):
		return (days[_date_key()] as Dictionary).duplicate(true)
	var progress: Dictionary = TimeManager.campaign_progress()
	return {"date": _date_key(), "year": TimeManager.year, "month": TimeManager.month,
		"day": TimeManager.day, "day_counter": TimeManager.day_counter,
		"campaign_day": int(progress.get("day", 0)), "campaign_week": int(progress.get("week", 0)),
		"phase": str(progress.get("phase", "")),
		"active_seconds": 0.0, "meaningful_actions": 0, "quest_actions": 0,
		"dialogue_choices": 0, "event_choices": 0, "events_triggered": 0,
		"event_opportunities": 0, "event_candidate_opportunities": 0,
		"minigames": 0, "minigame_wins": 0, "game_runs": 0,
		"program_opens": 0, "travels": 0, "travel_slots": 0,
		"collection_gains": 0,
		"travel_dm": 0, "travel_minutes": 0, "travel_wait_minutes": 0,
		"slots_advanced": 0, "sleep_count": 0, "empty_sleep": false}


func _store_day(day: Dictionary) -> void:
	var days: Dictionary = _state.get("days", {})
	days[str(day.get("date", _date_key()))] = day
	_state["days"] = days
	var year := _year_record(int(day.get("year", TimeManager.year)))
	var dates: Array = year.get("observed_dates", [])
	var key := str(day.get("date", _date_key()))
	if key not in dates:
		dates.append(key)
		year["observed_dates"] = dates
	_store_year(int(day.get("year", TimeManager.year)), year)


func _year_record(selected_year: int) -> Dictionary:
	var years: Dictionary = _state.get("years", {})
	return (years.get(str(selected_year), {"year": selected_year, "active_seconds": 0.0,
		"summer_active_seconds": 0.0, "non_summer_active_seconds": 0.0,
		"observed_dates": [], "meaningful_actions": 0, "slots_advanced": 0,
		"travels": 0, "travel_slots": 0, "travel_minutes": 0,
		"travel_wait_minutes": 0, "days_slept": 0, "empty_sleeps": 0,
		"events_triggered": 0, "event_choices": 0, "dialogue_choices": 0,
		"event_opportunities": 0, "event_candidate_opportunities": 0,
		"minigames": 0, "game_runs": 0, "program_opens": 0}) as Dictionary).duplicate(true)


func _store_year(selected_year: int, year: Dictionary) -> void:
	var years: Dictionary = _state.get("years", {})
	years[str(selected_year)] = year
	_state["years"] = years


func _increment_day(key: String, amount: int, meaningful: bool) -> void:
	var day := _day_record()
	day[key] = int(day.get(key, 0)) + amount
	if meaningful:
		day["meaningful_actions"] = int(day.get("meaningful_actions", 0)) + amount
		_increment_year("meaningful_actions", amount)
	_store_day(day)


func _increment_year(key: String, amount: int) -> void:
	var year := _year_record(TimeManager.year)
	year[key] = int(year.get(key, 0)) + amount
	_store_year(TimeManager.year, year)


func _increment_count(bucket: String, id: String, amount: int) -> void:
	if id.is_empty():
		return
	var target: Dictionary = _state.get(bucket, {})
	target[id] = int(target.get(id, 0)) + amount
	_state[bucket] = target


func _new_stage_entry(quest_id: String, index: int) -> Dictionary:
	var definition: Dictionary = QuestManager.def(quest_id)
	var stages: Array = definition.get("stages", [])
	var description := str(stages[index].get("desc", "")) if index >= 0 and index < stages.size() else ""
	return {"index": index, "description": description, "entered_game": _game_stamp(),
		"entered_active_second": _active_second()}


func _quest_record(id: String) -> Dictionary:
	return ((_state.get("quests", {}) as Dictionary).get(id, {}) as Dictionary).duplicate(true)


func _store_quest(id: String, quest: Dictionary) -> void:
	var quests: Dictionary = _state.get("quests", {})
	quests[id] = quest
	_state["quests"] = quests


func _append_timeline(kind: String, id: String, details: Dictionary, meaningful: bool) -> void:
	if not is_enabled():
		return
	var timeline: Array = _state.get("timeline", [])
	var sequence := int(_state.get("next_sequence", 1))
	_state["next_sequence"] = sequence + 1
	timeline.append({"sequence": sequence, "kind": kind, "id": id,
		"active_second": _active_second(), "game": _game_stamp(),
		"meaningful": meaningful, "details": details.duplicate(true)})
	if timeline.size() > MAX_TIMELINE:
		timeline = timeline.slice(timeline.size() - MAX_TIMELINE)
	_state["timeline"] = timeline


func to_dict() -> Dictionary:
	if not is_enabled():
		return {}
	_flush_active_time()
	var out := _state.duplicate(true)
	var sessions: Array = out.get("sessions", [])
	if not _current_session.is_empty():
		sessions.append(_current_session.duplicate(true))
	out["sessions"] = sessions
	out["last_checkpoint_at"] = Time.get_datetime_string_from_system()
	return out


func from_dict(data: Variant) -> void:
	_current_session = {}
	_pending_day_seconds = 0.0
	if not DevelopmentGate.enabled():
		_reset_state()
		return
	if not data is Dictionary or data.is_empty():
		_reset_state()
		return
	_state = (data as Dictionary).duplicate(true)
	_state["schema_version"] = SCHEMA_VERSION
	_state["enabled"] = bool(_state.get("enabled", true))
	for key in ["days", "years", "quests", "action_counts", "event_counts", "game_funnels",
			"travel_modes", "location_visits", "program_opens", "blocked_counts"]:
		if not _state.get(key, {}) is Dictionary:
			_state[key] = {}
	for year_key: String in (_state.get("years", {}) as Dictionary):
		var migrated_year: Dictionary = _state.years[year_key]
		if not migrated_year.has("summer_active_seconds"):
			migrated_year["summer_active_seconds"] = float(migrated_year.get("active_seconds", 0.0))
		if not migrated_year.has("non_summer_active_seconds"):
			migrated_year["non_summer_active_seconds"] = 0.0
		_state.years[year_key] = migrated_year
	if not _state.get("timeline", []) is Array:
		_state["timeline"] = []
	if not _state.get("collection_snapshots", []) is Array:
		_state["collection_snapshots"] = []
	if not _state.get("last_collection", {}) is Dictionary:
		_state["last_collection"] = {}
	var loaded_sessions: Array = []
	for raw: Variant in _state.get("sessions", []):
		if not raw is Dictionary:
			continue
		var session: Dictionary = (raw as Dictionary).duplicate(true)
		if bool(session.get("ongoing", false)):
			session["ongoing"] = false
			session["ended_reason"] = "save_checkpoint"
		loaded_sessions.append(session)
	if loaded_sessions.size() > MAX_SESSIONS:
		loaded_sessions = loaded_sessions.slice(loaded_sessions.size() - MAX_SESSIONS)
	_state["sessions"] = loaded_sessions
	_last_input_ms = Time.get_ticks_msec()
	report_changed.emit()


func _flush_active_time() -> void:
	if not is_enabled():
		_pending_day_seconds = 0.0
		return
	if _pending_day_seconds <= 0.0:
		return
	var seconds := _pending_day_seconds
	_pending_day_seconds = 0.0
	var day := _day_record()
	day["active_seconds"] = float(day.get("active_seconds", 0.0)) + seconds
	_store_day(day)
	var year := _year_record(TimeManager.year)
	year["active_seconds"] = float(year.get("active_seconds", 0.0)) + seconds
	if TimeManager.campaign_phase() == "summer":
		year["summer_active_seconds"] = float(year.get("summer_active_seconds", 0.0)) + seconds
	else:
		year["non_summer_active_seconds"] = float(year.get("non_summer_active_seconds", 0.0)) + seconds
	_store_year(TimeManager.year, year)
