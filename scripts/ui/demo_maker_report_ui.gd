extends RefCounted
## Ausschliesslich Darstellung des Build-/QA-Berichts im Szene-Studio.

const DemoUi := preload("res://scripts/ui/demo_maker_ui.gd")
const C_GOOD := Color8(92, 220, 138)
const C_WARN := Color8(248, 196, 72)
const C_BAD := Color8(235, 92, 90)


static func refresh(owner: Control) -> void:
	var report: Dictionary = owner.get("_report")
	var ui: Dictionary = owner.call("report_ui_context")
	var status: Label = ui["status"]
	var code_budget: Label = ui["code_budget"]
	var compile_log: RichTextLabel = ui["compile_log"]
	var score_label: Label = ui["score_label"]
	var score_bars: Dictionary = ui["score_bars"]
	var release_button: Button = ui["release_button"]
	var qa_text: RichTextLabel = ui["qa_text"]
	if report.is_empty():
		status.text = Loc.t("ui.demo_maker_report_ui.edit_nicht_gebaut", "EDIT · NICHT GEBAUT")
		status.add_theme_color_override("font_color", C_WARN)
		code_budget.text = Loc.t("ui.demo_maker_report_ui.build_noch_nicht_ausgefuhrt", "BUILD NOCH NICHT AUSGEFÜHRT")
		compile_log.text = Loc.t("ui.demo_maker_report_ui.color_7e909c_f7_startet_den_ersten", "[color=#7e909c]> F7 STARTET DEN ERSTEN BUILD[/color]")
		score_label.text = Loc.t("ui.demo_maker_report_ui.unbewertet_100", "UNBEWERTET · --/100")
		for bar: ProgressBar in score_bars.values():
			bar.value = 0
		release_button.disabled = true
		return

	var errors: Array = report.get("errors", [])
	var warnings: Array = report.get("warnings", [])
	var metrics: Dictionary = report.get("metrics", {})
	var score := int(report.get("score", 0))
	var grade := str(report.get("grade", "D"))
	code_budget.text = Loc.t("ui.demo_maker_report_ui.peak_cpu_d_chip_d_512", "PEAK CPU %d%% · CHIP %d/512 KB · BLITTER %d%% · %02.1f SEK.") % [
		int(metrics.get("peak_cpu_pct", metrics.get("peak_cpu", metrics.get("cpu", 0)))),
		int(metrics.get("peak_chip_kb", metrics.get("chip_kb", 0))),
		int(metrics.get("peak_blitter_pct", metrics.get("peak_blitter", metrics.get("blitter", 0)))),
		float(metrics.get("duration_s", metrics.get("duration", 0.0)))]
	var lines: Array[String] = ["[color=#48b8dc]> BUILD %s[/color]" % str(report.get("build_id", "LOCAL"))]
	for issue in errors:
		lines.append("[color=#eb5c5a]ERROR · %s[/color]" % DemoUi.issue_text(issue))
	for issue in warnings:
		lines.append("[color=#f8c448]WARN  · %s[/color]" % DemoUi.issue_text(issue))
	if errors.is_empty():
		lines.append("[color=#5cdc8a]LINK OK · %d PARTS · PAL TARGET READY[/color]" % (owner.call("_parts") as Array).size())
	if warnings.is_empty() and errors.is_empty():
		lines.append("[color=#5cdc8a]0 WARNINGS · RELEASE CANDIDATE[/color]")
	compile_log.text = "\n".join(lines)
	var categories: Dictionary = report.get("categories", {})
	for key in score_bars:
		var bar: ProgressBar = score_bars[key]
		bar.value = float(categories.get(key, score))
	score_label.text = Loc.t("ui.demo_maker_report_ui.grade_s_d_100", "GRADE %s · %d/100") % [grade, score]
	score_label.add_theme_color_override("font_color", C_GOOD if score >= 75 else C_WARN)
	if not errors.is_empty():
		status.text = Loc.t("ui.demo_maker_report_ui.build_fehler_d", "BUILD FEHLER · %d") % errors.size()
		status.add_theme_color_override("font_color", C_BAD)
	elif not bool(owner.get("_tested")):
		status.text = Loc.t("ui.demo_maker_report_ui.build_ok_test_ausstehend", "BUILD OK · TEST AUSSTEHEND")
		status.add_theme_color_override("font_color", C_WARN)
	else:
		status.text = Loc.t("ui.demo_maker_report_ui.qa_grun_release_bereit", "QA GRÜN · RELEASE BEREIT")
		status.add_theme_color_override("font_color", C_GOOD)
	release_button.disabled = not bool(owner.get("_tested")) or not errors.is_empty()
	var test_report: Dictionary = owner.get("_test_report")
	if test_report.is_empty():
		qa_text.text = Loc.t("ui.demo_maker_report_ui.color_7e909c_build_vorhanden_f8_startet", "[color=#7e909c]Build vorhanden. F8 startet Boot-, Speicher-, Timing- und Sync-Test.[/color]")
	else:
		var qa_lines: Array[String] = []
		for check in test_report.get("checks", []):
			var ok := bool(check.get("ok", false)) if check is Dictionary else true
			var label := str(check.get("label", check.get("name", "CHECK"))) if check is Dictionary else str(check)
			qa_lines.append("[color=%s]%s %s[/color]" % ["#5cdc8a" if ok else "#eb5c5a", "✓" if ok else "✕", label])
		qa_text.text = "\n".join(qa_lines)
