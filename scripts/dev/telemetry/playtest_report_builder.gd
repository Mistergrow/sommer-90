extends RefCounted
## Baut ausschliesslich interne, read-only Berichte aus dem Telemetrie-Snapshot.

const DECADE_REPORT_ID := 90099
const DECADE_START := 1990
const DECADE_END := 1999
const BALANCE_ANALYZER_PATH := "res://scripts/dev/telemetry/playtest_balance_analyzer.gd"
const CAMPAIGN_PACING_PATH := "res://data/campaign_pacing.json"


static func build(state: Dictionary, selector: int, game_now: Dictionary,
		active_second: float) -> Dictionary:
	if selector == DECADE_REPORT_ID:
		return _build_decade(state, game_now, active_second)
	return _build_year(state, selector, game_now, active_second)


static func _build_year(state: Dictionary, selected_year: int, game_now: Dictionary,
		active_second: float) -> Dictionary:
	var campaign_mode := selected_year >= DECADE_START and selected_year <= DECADE_END
	var year := _year_record(state, selected_year)
	var days := _days_for_year(state, selected_year, campaign_mode)
	var pacing := _pacing_target()
	var expected_days := int(pacing.get("weeks", 6)) * int(pacing.get("days_per_week", 4)) \
		if campaign_mode else 0
	var target_seconds := float(pacing.get("hours_per_year", 4.0)) * 3600.0 \
		if campaign_mode else 0.0
	var total_seconds := float(year.get("summer_active_seconds", year.get("active_seconds", 0.0))) \
		if campaign_mode else float(year.get("active_seconds", 0.0))
	var real_day_seconds: Array[float] = []
	for day: Dictionary in days:
		real_day_seconds.append(float(day.get("active_seconds", 0.0)))
	real_day_seconds.sort()
	var avg_day := total_seconds / maxf(1.0, float(days.size()))
	var projected_seconds := avg_day * float(expected_days) if campaign_mode else 0.0
	var median_day := _median(real_day_seconds)
	var quest_rows := _quest_rows_for_year(state, selected_year, active_second)
	var analyzer: Script = load(BALANCE_ANALYZER_PATH) as Script
	var complete: bool = analyzer.summer_complete(selected_year, days.size(), expected_days, game_now) \
		if campaign_mode and analyzer != null else false
	var week_rows: Array = analyzer.week_rows(days) if campaign_mode and analyzer != null else []
	var ovp_start := int(year.get("ovp_start", year.get("ovp_end", 0)))
	var ovp_end := int(year.get("ovp_end", 0))
	var ovp_gained := ovp_end - ovp_start
	var projection := {"available": false,
		"reason": Loc.t("misc.playtest_report_builder.sommer_unvollstaendig_free_play_oder_kein", "Sommer unvollstaendig, Free Play oder kein positiver OVP-Zuwachs.")}
	if campaign_mode and complete and ovp_gained > 0:
		projection = {"available": true, "unique_ovp_per_summer": ovp_gained,
			"additional_summers_to_10": ceili(maxi(0, 10 - ovp_end) / float(ovp_gained)),
			"additional_summers_to_50": ceili(maxi(0, 50 - ovp_end) / float(ovp_gained)),
			"additional_summers_to_100": ceili(maxi(0, 100 - ovp_end) / float(ovp_gained))}
	var findings: Array = analyzer.findings(selected_year, days, year, target_seconds,
		expected_days, quest_rows, state.get("timeline", []), campaign_mode, game_now) \
		if analyzer != null else []
	return {
		"schema": "disk-scene-playtest-report/v2",
		"mode": "campaign" if campaign_mode else "free_play",
		"read_only_summary": true,
		"run_id": str(state.get("run_id", "")),
		"generated_at": Time.get_datetime_string_from_system(),
		"year": selected_year,
		"game_now": game_now.duplicate(true),
		"privacy": _privacy(),
		"target": {"applicable": campaign_mode, "seconds": target_seconds,
			"hours": target_seconds / 3600.0, "playable_days": expected_days},
		"coverage": {"observed_days": days.size(), "expected_days": expected_days,
			"summer_complete": complete, "campaign_mode": campaign_mode},
		"summary": {
			"active_seconds": total_seconds, "active_minutes": total_seconds / 60.0,
			"non_summer_active_seconds": float(year.get("non_summer_active_seconds", 0.0)),
			"target_percent": total_seconds / target_seconds * 100.0 if target_seconds > 0.0 else 0.0,
			"average_seconds_per_observed_day": avg_day,
			"median_seconds_per_observed_day": median_day,
			"projected_seconds_at_current_pace": projected_seconds,
			"projected_hours_at_current_pace": projected_seconds / 3600.0,
			"meaningful_actions": int(year.get("meaningful_actions", 0)),
			"actions_per_observed_day": float(year.get("meaningful_actions", 0)) / maxf(1.0, float(days.size())),
			"slots_advanced": int(year.get("slots_advanced", 0)),
			"travel_slots": int(year.get("travel_slots", 0)),
			"travel_minutes": int(year.get("travel_minutes", 0)),
			"travel_wait_minutes": int(year.get("travel_wait_minutes", 0)),
			"travel_slot_share": float(year.get("travel_slots", 0)) / maxf(1.0, float(year.get("slots_advanced", 0))),
			"travels": int(year.get("travels", 0)),
			"days_slept": int(year.get("days_slept", 0)),
			"empty_sleeps": int(year.get("empty_sleeps", 0)),
			"events_triggered": int(year.get("events_triggered", 0)),
			"event_opportunities": int(year.get("event_opportunities", 0)),
			"event_candidate_opportunities": int(year.get("event_candidate_opportunities", 0)),
			"dialogue_choices": int(year.get("dialogue_choices", 0)),
			"minigames": int(year.get("minigames", 0)),
			"game_runs": int(year.get("game_runs", 0)),
			"blocked_attempts": int(year.get("blocked_attempts", 0)),
			"ovp_start": ovp_start, "ovp_end": ovp_end, "ovp_gained": ovp_gained,
			"sealed_ovp_end": int(year.get("sealed_ovp_end", 0)),
			"total_disks_end": int(year.get("disk_end", 0)),
		},
		"days": days, "weeks": week_rows, "quests": quest_rows,
		"collection_projection": projection,
		"game_funnels": (state.get("game_funnels", {}) as Dictionary).duplicate(true),
		"findings": findings,
	}


static func _build_decade(state: Dictionary, game_now: Dictionary,
		active_second: float) -> Dictionary:
	var years: Array = []
	var total := {"active_seconds": 0.0, "observed_days": 0, "meaningful_actions": 0,
		"slots_advanced": 0, "travel_slots": 0, "travels": 0, "days_slept": 0,
		"travel_minutes": 0, "travel_wait_minutes": 0,
		"empty_sleeps": 0, "events_triggered": 0, "minigames": 0, "game_runs": 0,
		"blocked_attempts": 0, "complete_years": 0}
	var first_ovp := -1
	var last_ovp := 0
	var stagnant_years: Array[int] = []
	for selected_year in range(DECADE_START, DECADE_END + 1):
		var row := _build_year(state, selected_year, game_now, active_second)
		years.append(row)
		var summary: Dictionary = row.get("summary", {})
		var coverage: Dictionary = row.get("coverage", {})
		for key: String in ["active_seconds", "meaningful_actions", "slots_advanced",
				"travel_slots", "travel_minutes", "travel_wait_minutes", "travels",
				"days_slept", "empty_sleeps", "events_triggered",
				"minigames", "game_runs", "blocked_attempts"]:
			total[key] = float(total.get(key, 0.0)) + float(summary.get(key, 0.0))
		total["observed_days"] = int(total.observed_days) + int(coverage.get("observed_days", 0))
		if bool(coverage.get("summer_complete", false)):
			total["complete_years"] = int(total.complete_years) + 1
			if int(summary.get("ovp_gained", 0)) <= 0:
				stagnant_years.append(selected_year)
		if first_ovp < 0 and int(coverage.get("observed_days", 0)) > 0:
			first_ovp = int(summary.get("ovp_start", 0))
		if int(coverage.get("observed_days", 0)) > 0:
			last_ovp = int(summary.get("ovp_end", last_ovp))
	var target_seconds := float(_pacing_target().get("hours_per_year", 4.0)) \
		* 3600.0 * float(DECADE_END - DECADE_START + 1)
	var findings := _decade_findings(years, total, target_seconds, stagnant_years)
	var slots := int(total.slots_advanced)
	var travel_slots := int(total.travel_slots)
	return {
		"schema": "disk-scene-playtest-decade-report/v1", "mode": "decade",
		"read_only_summary": true, "run_id": str(state.get("run_id", "")),
		"generated_at": Time.get_datetime_string_from_system(),
		"period": {"from": DECADE_START, "to": DECADE_END},
		"game_now": game_now.duplicate(true), "privacy": _privacy(),
		"target": {"applicable": true, "seconds": target_seconds,
			"hours": target_seconds / 3600.0, "playable_days": 240},
		"coverage": {"observed_days": int(total.observed_days), "expected_days": 240,
			"complete_years": int(total.complete_years), "expected_years": 10,
			"decade_complete": int(total.complete_years) == 10},
		"summary": {
			"active_seconds": float(total.active_seconds),
			"active_minutes": float(total.active_seconds) / 60.0,
			"target_percent": float(total.active_seconds) / target_seconds * 100.0,
			"meaningful_actions": int(total.meaningful_actions),
			"actions_per_observed_day": float(total.meaningful_actions) / maxf(1.0, float(total.observed_days)),
			"slots_advanced": slots, "travel_slots": travel_slots,
			"travel_slot_share": float(travel_slots) / maxf(1.0, float(slots)),
			"travel_minutes": int(total.travel_minutes),
			"travel_wait_minutes": int(total.travel_wait_minutes),
			"travels": int(total.travels), "days_slept": int(total.days_slept),
			"empty_sleeps": int(total.empty_sleeps),
			"events_triggered": int(total.events_triggered),
			"minigames": int(total.minigames), "game_runs": int(total.game_runs),
			"blocked_attempts": int(total.blocked_attempts),
			"ovp_start": maxi(0, first_ovp), "ovp_end": last_ovp,
			"ovp_gained": last_ovp - maxi(0, first_ovp),
		},
		"years": years,
		"game_funnels": (state.get("game_funnels", {}) as Dictionary).duplicate(true),
		"findings": findings,
	}


static func _decade_findings(years: Array, total: Dictionary, target_seconds: float,
		stagnant_years: Array[int]) -> Array:
	var out: Array = []
	var complete_years := int(total.complete_years)
	if complete_years < 10:
		out.append(_finding("info", "DECADE_INCOMPLETE",
			"Nur %d/10 Kampagnenjahre sind vollstaendig beobachtet." % complete_years))
	elif float(total.active_seconds) < target_seconds * 0.75:
		out.append(_finding("warning", "DECADE_TOO_SHORT",
			"Die Kampagne erreicht %.1f statt %.1f Zielstunden." % [
				float(total.active_seconds) / 3600.0, target_seconds / 3600.0]))
	var slots := int(total.slots_advanced)
	if slots >= 8 and float(total.travel_slots) / float(slots) > 0.35:
		out.append(_finding("warning", "DECADE_TRAVEL_SHARE_HIGH",
			"Reisen verbraucht %.0f %% aller gemessenen Zeitfenster." %
			(float(total.travel_slots) / float(slots) * 100.0)))
	if int(total.days_slept) >= 8 and float(total.empty_sleeps) / float(total.days_slept) >= 0.20:
		out.append(_finding("warning", "DECADE_EMPTY_DAYS",
			"%d von %d Schlaftagen endeten ohne bedeutungsvolle Aktion." % [
				int(total.empty_sleeps), int(total.days_slept)]))
	var early := _period_average(years, 1990, 1996)
	var late := _period_average(years, 1997, 1998)
	if early > 0.0 and late > 0.0 and late < early * 0.70:
		out.append(_finding("warning", "LATE_GAME_CONTENT_DROP",
			"1997-98 erreichen pro Jahr nur %.0f %% der aktiven Zeit von 1990-96." %
			(late / early * 100.0)))
	if not stagnant_years.is_empty():
		out.append(_finding("info", "OVP_STAGNANT_YEARS",
			"Kein neuer unterschiedlicher OVP-Titel in: %s." % _join_ints(stagnant_years)))
	return out


static func _period_average(years: Array, first: int, last: int) -> float:
	var seconds := 0.0
	var count := 0
	for row: Dictionary in years:
		var year := int(row.get("year", 0))
		if year < first or year > last or int(row.get("coverage", {}).get("observed_days", 0)) <= 0:
			continue
		seconds += float(row.get("summary", {}).get("active_seconds", 0.0))
		count += 1
	return seconds / float(count) if count > 0 else 0.0


static func _days_for_year(state: Dictionary, selected_year: int, campaign_mode: bool) -> Array:
	var out: Array = []
	for raw: Variant in (state.get("days", {}) as Dictionary).values():
		if not raw is Dictionary:
			continue
		var day: Dictionary = raw
		if int(day.get("year", 0)) == selected_year \
				and (not campaign_mode or int(day.get("campaign_day", 0)) > 0):
			out.append(day.duplicate(true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("day_counter", 0)) < int(b.get("day_counter", 0)))
	return out


static func _quest_rows_for_year(state: Dictionary, selected_year: int,
		active_second: float) -> Array:
	var out: Array = []
	for id: String in (state.get("quests", {}) as Dictionary):
		var quest: Dictionary = state.quests[id]
		var start: Dictionary = quest.get("started_game", {})
		var complete: Dictionary = quest.get("completed_game", {})
		if int(start.get("year", 0)) != selected_year and int(complete.get("year", 0)) != selected_year:
			continue
		var duration := float(quest.get("active_duration_seconds",
			active_second - float(quest.get("started_active_second", active_second))))
		out.append({"id": id, "title": str(quest.get("title", id)),
			"completed": bool(quest.get("completed", false)),
			"current_stage": _quest_stage(id, quest),
			"active_duration_seconds": maxf(0.0, duration),
			"started_game": start.duplicate(true), "completed_game": complete.duplicate(true),
			"stages": (quest.get("stages", []) as Array).duplicate(true)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("started_game", {}).get("day_counter", 0)) \
			< float(b.get("started_game", {}).get("day_counter", 0)))
	return out


static func _year_record(state: Dictionary, selected_year: int) -> Dictionary:
	return (((state.get("years", {}) as Dictionary).get(str(selected_year), {
		"year": selected_year, "active_seconds": 0.0, "summer_active_seconds": 0.0,
		"non_summer_active_seconds": 0.0, "observed_dates": []}) as Dictionary).duplicate(true))


static func _recorded_stage(quest: Dictionary) -> int:
	var highest := -1
	for raw: Variant in quest.get("stages", []):
		if raw is Dictionary:
			highest = maxi(highest, int(raw.get("index", -1)))
	return highest + 1 if bool(quest.get("completed", false)) else highest


static func _quest_stage(id: String, quest: Dictionary) -> int:
	var manager := _autoload("QuestManager")
	if manager != null and manager.has_method("def") and manager.has_method("stage") \
			and not (manager.call("def", id) as Dictionary).is_empty():
		return int(manager.call("stage", id))
	return _recorded_stage(quest)


static func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath(node_name))


static func _pacing_target() -> Dictionary:
	var pacing := {}
	if FileAccess.file_exists(CAMPAIGN_PACING_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_PACING_PATH))
		if parsed is Dictionary:
			pacing = parsed
	var window: Dictionary = pacing.get("summer_window", {})
	return {
		"weeks": int(window.get("weeks", 6)),
		"days_per_week": int(window.get("playable_days_per_week", 4)),
		"minutes_per_day": int(pacing.get("target_minutes_per_playable_day", 10)),
		"hours_per_year": float(pacing.get("target_hours_per_full_year", 4.0)),
	}


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var middle := values.size() >> 1
	return values[middle] if values.size() % 2 == 1 \
		else (values[middle - 1] + values[middle]) / 2.0


static func _privacy() -> Dictionary:
	return {"local_only": true, "network_upload": false,
		"records_key_content": false, "records_free_text": false}


static func _finding(severity: String, code: String, message: String) -> Dictionary:
	return {"severity": severity, "code": code, "message": message}


static func _join_ints(values: Array[int]) -> String:
	var text := PackedStringArray()
	for value: int in values:
		text.append(str(value))
	return ", ".join(text)
