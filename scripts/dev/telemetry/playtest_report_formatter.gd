extends RefCounted
## Entwicklungsinterne Textdarstellung eines berechneten Playtest-Berichts.


static func summary_text(report: Dictionary, current_year: int) -> String:
	var mode := str(report.get("mode", "campaign"))
	if mode == "decade":
		return _decade_text(report)
	if mode == "free_play":
		return _free_play_text(report, current_year)
	var summary: Dictionary = report.get("summary", {})
	var coverage: Dictionary = report.get("coverage", {})
	var lines := PackedStringArray()
	lines.append("SOMMER %d · PLAYTEST-BERICHT" % int(report.get("year", current_year)))
	lines.append("%.1f / %.0f Minuten · %.0f %% des Zeitziels" % [
		float(summary.get("active_minutes", 0.0)),
		float(report.get("target", {}).get("seconds", 14400.0)) / 60.0,
		float(summary.get("target_percent", 0.0))])
	lines.append("%d/%d Spieltage beobachtet · Ø %.1f Min. · Median %.1f Min." % [
		int(coverage.get("observed_days", 0)), int(coverage.get("expected_days", 24)),
		float(summary.get("average_seconds_per_observed_day", 0.0)) / 60.0,
		float(summary.get("median_seconds_per_observed_day", 0.0)) / 60.0])
	if not bool(coverage.get("summer_complete", false)) and int(coverage.get("observed_days", 0)) >= 4:
		lines.append("Hochrechnung beim bisherigen Tempo: %.1f Stunden" %
			float(summary.get("projected_hours_at_current_pace", 0.0)))
	lines.append("%d bedeutungsvolle Aktionen · %.1f pro Tag" % [
		int(summary.get("meaningful_actions", 0)), float(summary.get("actions_per_observed_day", 0.0))])
	lines.append("%d Reisen · %d Reiseslots von %d Slots · %d leere Schlaftage" % [
		int(summary.get("travels", 0)), int(summary.get("travel_slots", 0)),
		int(summary.get("slots_advanced", 0)), int(summary.get("empty_sleeps", 0))])
	if int(summary.get("travel_minutes", 0)) > 0:
		lines.append("%d Reiseminuten · %d Minuten bewusstes Warten auf Termine" % [
			int(summary.get("travel_minutes", 0)),
			int(summary.get("travel_wait_minutes", 0))])
	lines.append("%d Events · %d Slotchancen mit zulässigem Event" % [
		int(summary.get("events_triggered", 0)), int(summary.get("event_candidate_opportunities", 0))])
	lines.append("%d blockierte Bedienversuche (z. B. geschlossene Reiseziele)" % int(summary.get("blocked_attempts", 0)))
	lines.append("OVP: %d → %d verschiedene vollständige Titel (%+d) · %d versiegelt" % [
		int(summary.get("ovp_start", 0)), int(summary.get("ovp_end", 0)), int(summary.get("ovp_gained", 0)),
		int(summary.get("sealed_ovp_end", 0))])
	var projection: Dictionary = report.get("collection_projection", {})
	if bool(projection.get("available", false)):
		lines.append("OVP-Projektion bei gleichem Tempo: 10 in +%d, 50 in +%d, 100 in +%d Sommern" % [
			int(projection.get("additional_summers_to_10", 0)),
			int(projection.get("additional_summers_to_50", 0)),
			int(projection.get("additional_summers_to_100", 0))])
	lines.append("")
	lines.append("FERIENWOCHEN")
	for week: Dictionary in report.get("weeks", []):
		lines.append("· W%d · %d Tage · %.1f Min. · %d Aktionen · %d Reiseslots" % [
			int(week.get("week", 0)), int(week.get("observed_days", 0)),
			float(week.get("active_seconds", 0.0)) / 60.0,
			int(week.get("meaningful_actions", 0)), int(week.get("travel_slots", 0))])
	lines.append("")
	lines.append("BALANCE-BEFUNDE")
	var findings: Array = report.get("findings", [])
	if findings.is_empty():
		lines.append("· Noch kein belastbarer Befund.")
	for finding: Dictionary in findings:
		lines.append("[%s] %s" % [str(finding.get("severity", "info")).to_upper(),
			str(finding.get("message", ""))])
	lines.append("")
	lines.append("QUESTDAUER (aktive Spielzeit zwischen Start und Stand)")
	for quest: Dictionary in report.get("quests", []):
		lines.append("· %s · %.1f Min. · %s" % [str(quest.get("title", quest.get("id", "?"))),
			float(quest.get("active_duration_seconds", 0.0)) / 60.0,
			"erledigt" if bool(quest.get("completed", false)) else "offen"])
	return "\n".join(lines)


static func _decade_text(report: Dictionary) -> String:
	var summary: Dictionary = report.get("summary", {})
	var coverage: Dictionary = report.get("coverage", {})
	var target: Dictionary = report.get("target", {})
	var lines := PackedStringArray()
	lines.append("DEKADE 1990–1999 · PLAYTEST-BERICHT")
	lines.append("%.1f / %.1f Stunden · %.0f %% des Kampagnenziels" % [
		float(summary.get("active_seconds", 0.0)) / 3600.0,
		float(target.get("hours", 40.0)), float(summary.get("target_percent", 0.0))])
	lines.append("%d/10 Sommer vollständig · %d/%d Spieltage beobachtet" % [
		int(coverage.get("complete_years", 0)), int(coverage.get("observed_days", 0)),
		int(coverage.get("expected_days", 240))])
	lines.append("%d Aktionen · %.1f pro Tag · Reisen %.0f %% der Zeitfenster" % [
		int(summary.get("meaningful_actions", 0)),
		float(summary.get("actions_per_observed_day", 0.0)),
		float(summary.get("travel_slot_share", 0.0)) * 100.0])
	lines.append("OVP: %d → %d unterschiedliche Titel (%+d)" % [
		int(summary.get("ovp_start", 0)), int(summary.get("ovp_end", 0)),
		int(summary.get("ovp_gained", 0))])
	lines.append("")
	lines.append("JAHRESVERLAUF")
	for row: Dictionary in report.get("years", []):
		var row_summary: Dictionary = row.get("summary", {})
		var row_coverage: Dictionary = row.get("coverage", {})
		lines.append("· %d · %5.2f h · %2d/%2d Tage · %3d Aktionen · Reise %3.0f %% · OVP %+d" % [
			int(row.get("year", 0)), float(row_summary.get("active_seconds", 0.0)) / 3600.0,
			int(row_coverage.get("observed_days", 0)), int(row_coverage.get("expected_days", 24)),
			int(row_summary.get("meaningful_actions", 0)),
			float(row_summary.get("travel_slot_share", 0.0)) * 100.0,
			int(row_summary.get("ovp_gained", 0))])
	_append_findings(lines, report.get("findings", []))
	return "\n".join(lines)


static func _free_play_text(report: Dictionary, current_year: int) -> String:
	var summary: Dictionary = report.get("summary", {})
	var coverage: Dictionary = report.get("coverage", {})
	var lines := PackedStringArray()
	lines.append("FREIES SPIEL %d · ENTWICKLUNGSBERICHT" % int(report.get("year", current_year)))
	lines.append("%.1f aktive Minuten · %d beobachtete Kalendertage · kein Kampagnen-Zeitziel" % [
		float(summary.get("active_minutes", 0.0)), int(coverage.get("observed_days", 0))])
	lines.append("%d Aktionen · %.1f pro Tag · %d Reisen · %d leere Schlaftage" % [
		int(summary.get("meaningful_actions", 0)),
		float(summary.get("actions_per_observed_day", 0.0)),
		int(summary.get("travels", 0)), int(summary.get("empty_sleeps", 0))])
	lines.append("OVP-Bestand: %d · Disketten: %d · Minispiele: %d · Spielrunden: %d" % [
		int(summary.get("ovp_end", 0)), int(summary.get("total_disks_end", 0)),
		int(summary.get("minigames", 0)), int(summary.get("game_runs", 0))])
	_append_findings(lines, report.get("findings", []))
	lines.append("")
	lines.append("QUESTDAUER (aktive Spielzeit zwischen Start und Stand)")
	for quest: Dictionary in report.get("quests", []):
		lines.append("· %s · %.1f Min. · %s" % [str(quest.get("title", quest.get("id", "?"))),
			float(quest.get("active_duration_seconds", 0.0)) / 60.0,
			"erledigt" if bool(quest.get("completed", false)) else "offen"])
	return "\n".join(lines)


static func _append_findings(lines: PackedStringArray, findings: Array) -> void:
	lines.append("")
	lines.append("BALANCE-BEFUNDE")
	if findings.is_empty():
		lines.append("· Noch kein belastbarer Befund.")
	for finding: Dictionary in findings:
		lines.append("[%s] %s" % [str(finding.get("severity", "info")).to_upper(),
			str(finding.get("message", ""))])
