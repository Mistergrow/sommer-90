extends RefCounted
## Entwicklungsinterne Auswertung; schreibt weder Quests noch Telemetrie.


static func findings(selected_year: int, days: Array, year: Dictionary,
		target_seconds: float, expected_days: int, quest_rows: Array, timeline: Array,
		campaign_mode := true, game_now: Dictionary = {}) -> Array:
	var out: Array = []
	var complete := summer_complete(selected_year, days.size(), expected_days, game_now) if campaign_mode else false
	var active_seconds := float(year.get("summer_active_seconds", year.get("active_seconds", 0.0)))
	if campaign_mode and not complete:
		out.append(_finding("info", "INCOMPLETE_SAMPLE",
			"Der Sommer ist noch nicht vollständig beobachtet (%d/%d Spieltage). Zeiturteile bleiben vorläufig." % [days.size(), expected_days]))
		if days.size() >= 4:
			var projected_seconds := active_seconds / float(days.size()) * float(expected_days)
			if projected_seconds < target_seconds * 0.75:
				out.append(_finding("warning", "PROJECTED_YEAR_SHORT",
					"Beim bisherigen Tagestempo landet der Sommer voraussichtlich bei %.1f statt 4 Stunden." % (projected_seconds / 3600.0)))
	elif campaign_mode and active_seconds < target_seconds * 0.75:
		out.append(_finding("warning", "YEAR_TOO_SHORT",
			"Der vollständige Sommer liegt mit %.1f Stunden deutlich unter dem 4-Stunden-Ziel." % (active_seconds / 3600.0)))
	elif campaign_mode and active_seconds > target_seconds * 1.35:
		out.append(_finding("warning", "YEAR_TOO_LONG",
			"Der vollständige Sommer liegt mit %.1f Stunden deutlich über dem 4-Stunden-Ziel." % (active_seconds / 3600.0)))
	elif campaign_mode:
		out.append(_finding("ok", "YEAR_TARGET_RANGE", "Die gemessene Sommerdauer liegt im vorgesehenen Zielkorridor."))
	if campaign_mode and selected_year == int(game_now.get("year", -1)) \
			and str(game_now.get("phase", "")) == "summer" and days.size() >= 1 \
			and _active_quests_are_empty():
		out.append(_finding("warning", "NO_ACTIVE_QUEST_GAP",
			"Im laufenden Sommer ist keine Quest aktiv. Falls das kein bewusst erklärter Freiraum ist, fehlt der Übergang zum nächsten Storybeat."))
	var slept := int(year.get("days_slept", 0))
	var empty := int(year.get("empty_sleeps", 0))
	if slept >= 4 and float(empty) / float(slept) >= 0.25:
		out.append(_finding("warning", "EMPTY_DAYS", "%d von %d beendeten Tagen hatten keine bedeutungsvolle Aktion." % [empty, slept]))
	var all_slots := int(year.get("slots_advanced", 0))
	var travel_slots := int(year.get("travel_slots", 0))
	if travel_slots > all_slots:
		out.append(_finding("warning", "TRAVEL_TIME_CLAMPED",
			"Reisen meldeten %d Zeitfenster, die Uhr rückte aber insgesamt nur %d vor. Wahrscheinlich wurden Wege an der Nachtgrenze gekappt." % [travel_slots, all_slots]))
	elif all_slots >= 8 and float(travel_slots) / float(all_slots) > 0.35:
		out.append(_finding("warning", "TRAVEL_SHARE_HIGH", "Reisen verbraucht %.0f %% aller vergangenen Zeitfenster." % (float(travel_slots) / float(all_slots) * 100.0)))
	var actions := int(year.get("meaningful_actions", 0))
	if days.size() >= 4 and float(actions) / float(days.size()) < 2.0:
		out.append(_finding("warning", "ACTION_DENSITY_LOW", "Im Mittel wurden weniger als zwei bedeutungsvolle Aktionen pro beobachtetem Tag erfasst."))
	if days.size() >= 4 and int(year.get("game_runs", 0)) == 0:
		out.append(_finding("warning", "NO_GAME_RUNS", "In %d beobachteten Spieltagen wurde kein einziges Spiel gestartet; der frühe Loop besteht damit vor allem aus Wegen, Dialogen und Werkzeugen." % days.size()))
	var candidate_opportunities := int(year.get("event_candidate_opportunities", 0))
	var triggered_events := int(year.get("events_triggered", 0))
	if candidate_opportunities >= 12 and float(triggered_events) / float(candidate_opportunities) < 0.10:
		out.append(_finding("warning", "EVENT_STARVATION", "Nur %d Events erschienen bei %d Slotwechseln mit mindestens einem zulässigen Kandidaten." % [triggered_events, candidate_opportunities]))
	if int(year.get("blocked_attempts", 0)) >= 5:
		out.append(_finding("info", "REPEATED_BLOCKS", "%d Bedienversuche wurden durch Anforderungen oder Verfügbarkeit blockiert; die Timeline zeigt die Gründe." % int(year.get("blocked_attempts", 0))))
	if campaign_mode and complete and int(year.get("ovp_end", 0)) - int(year.get("ovp_start", year.get("ovp_end", 0))) <= 0:
		out.append(_finding("info", "OVP_NO_PROGRESS", "Im vollständigen Sommer kam kein neuer verschiedener vollständiger OVP-Titel hinzu; 10/50/100 sind so nicht planbar."))
	for week: Dictionary in (week_rows(days) if campaign_mode else []):
		if int(week.get("observed_days", 0)) >= 4 and int(week.get("meaningful_actions", 0)) < 4:
			out.append(_finding("warning", "WEEK_THIN", "Ferienwoche %d besitzt über vier beobachtete Tage weniger als vier bedeutungsvolle Aktionen." % int(week.get("week", 0))))
	for quest: Dictionary in quest_rows:
		var unmatched_action := _unmatched_current_goal_action(quest, timeline)
		if unmatched_action != "":
			out.append(_finding("warning", "QUEST_ACTION_WITHOUT_MATCH",
				"„%s“ wartet auf „%s“, obwohl diese Aktion zuvor bereits ohne passende Quest registriert wurde. Das ist eine mögliche Ablauf-Sackgasse." % [str(quest.get("title", quest.get("id", "?"))), unmatched_action]))
		if not bool(quest.get("completed", false)) and float(quest.get("active_duration_seconds", 0.0)) >= 30.0 * 60.0:
			out.append(_finding("warning", "QUEST_STALLED", "„%s“ ist seit mindestens 30 aktiven Minuten offen (Stufe %d)." % [str(quest.get("title", quest.get("id", "?"))), int(quest.get("current_stage", 0))]))
	return out


static func week_rows(days: Array) -> Array:
	var by_week := {}
	for day: Dictionary in days:
		var week := int(day.get("campaign_week", 0))
		if week <= 0:
			continue
		var row: Dictionary = by_week.get(str(week), {"week": week, "observed_days": 0,
			"active_seconds": 0.0, "meaningful_actions": 0, "travels": 0,
			"travel_slots": 0, "empty_sleeps": 0})
		row["observed_days"] = int(row.get("observed_days", 0)) + 1
		row["active_seconds"] = float(row.get("active_seconds", 0.0)) + float(day.get("active_seconds", 0.0))
		row["meaningful_actions"] = int(row.get("meaningful_actions", 0)) + int(day.get("meaningful_actions", 0))
		row["travels"] = int(row.get("travels", 0)) + int(day.get("travels", 0))
		row["travel_slots"] = int(row.get("travel_slots", 0)) + int(day.get("travel_slots", 0))
		if bool(day.get("empty_sleep", false)):
			row["empty_sleeps"] = int(row.get("empty_sleeps", 0)) + 1
		by_week[str(week)] = row
	var out: Array = by_week.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("week", 0)) < int(b.get("week", 0)))
	return out


static func summer_complete(selected_year: int, observed_days: int, expected_days: int,
		game_now: Dictionary = {}) -> bool:
	var current_year := int(game_now.get("year", selected_year))
	var current_phase := str(game_now.get("phase", ""))
	if selected_year < current_year:
		return true
	if selected_year > current_year:
		return false
	return observed_days >= expected_days or current_phase in ["year_end", "free_play"]


static func _unmatched_current_goal_action(quest: Dictionary, timeline: Array) -> String:
	if bool(quest.get("completed", false)):
		return ""
	var quest_id := str(quest.get("id", ""))
	var manager := _autoload("QuestManager")
	if manager == null or not manager.has_method("def"):
		return ""
	var definition: Dictionary = manager.call("def", quest_id)
	var stages: Array = definition.get("stages", [])
	var stage_index := int(quest.get("current_stage", -1))
	if stage_index < 0 or stage_index >= stages.size():
		return ""
	var action := str((stages[stage_index].get("goal", {}) as Dictionary).get("action", ""))
	if action == "":
		return ""
	for raw: Variant in timeline:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if str(entry.get("kind", "")) != "quest_action" or str(entry.get("id", "")) != action:
			continue
		var matched: Array = (entry.get("details", {}) as Dictionary).get("matched_quests", [])
		if quest_id not in matched:
			return action
	return ""


static func _active_quests_are_empty() -> bool:
	var manager := _autoload("QuestManager")
	return manager == null or not manager.has_method("active_quests") \
		or (manager.call("active_quests") as Array).is_empty()


static func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath(node_name))


static func _finding(severity: String, code: String, message: String) -> Dictionary:
	return {"severity": severity, "code": code, "message": message}
