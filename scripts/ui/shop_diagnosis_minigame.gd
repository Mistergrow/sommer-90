class_name ShopDiagnosisMinigame
extends RetroWindow
## Grubers evidenzbasierter Diagnoseauftrag mit jahrgenauer Servicebench.

const Model := preload("res://scripts/minigames/shop_diagnosis_model.gd")
const Bench := preload("res://scripts/ui/shop_diagnosis_bench.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")

var job_id := "job_gruber_diagnosis"
var _model: ShopDiagnosisModel
var _log: RichTextLabel
var _status: Label
var _evidence: Label
var _customer_state: Label
var _test_buttons: Dictionary = {}
var _fault_buttons: Dictionary = {}
var _bench: Control
var _finished := false


func _init() -> void:
	title = Loc.t("ui.shop_diagnosis_minigame.gruber_service_laden_diagnose", "GRUBER SERVICE · LADEN-DIAGNOSE")
	win_size = Vector2(1040, 680)


static func can_start(next_job_id := "job_gruber_diagnosis") -> Dictionary:
	var job := JobManager.job_by_id(next_job_id)
	if job.is_empty() or str(job.get("minigame", "")) != "shop_diagnosis":
		return {"ok": false, "reason": Loc.t(
			"ui.shop_diagnosis_minigame.kein_diagnoseauftrag",
			"Kein Diagnoseauftrag.")}
	if not JobManager.offered_here(job, GameManager.current_location_id):
		return {"ok": false, "reason": Loc.t(
			"ui.shop_diagnosis_minigame.auftrag_ist_gerade_nicht_verfuegbar",
			"Auftrag ist gerade nicht verfuegbar.")}
	return JobManager.can_do(job)


func _ready() -> void:
	super._ready()
	var wins := int(MinigameManager.record("shop_diagnosis").get("wins", 0))
	_model = Model.new()
	_model.configure(clampi(1 + floori(wins / 2.0), 1, 5),
		hash("DIAG/%d/%d" % [TimeManager.day_counter, wins]), TimeManager.year)
	_build_ui()


func _build_ui() -> void:
	_build_case_header()
	var split := HBoxContainer.new()
	split.name = "DiagnosisBench25D"
	split.custom_minimum_size = Vector2(1004, 520)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	content.add_child(split)
	var rig := DepthRig.new()
	split.add_child(rig)
	rig.configure(split, 0.58)
	_bench = Bench.new()
	_bench.name = "AnimatedServiceBench"
	_bench.set("model", _model)
	_bench.custom_minimum_size = Vector2(604, 520)
	_bench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench.connect("test_requested", _test)
	split.add_child(_bench)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(382, 0)
	controls.add_theme_constant_override("separation", 5)
	split.add_child(controls)
	_build_customer_card(controls)
	_build_log(controls)
	_build_test_buttons(controls)
	_build_fault_buttons(controls)
	_build_assistance(controls)
	_status = Bezel.lcd_label("", Palette.LCD_GREEN, 10)
	_status.custom_minimum_size.y = 42
	content.add_child(_status)
	_refresh()


func _build_case_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var workflow := Bezel.dim_label(Loc.t(
		"ui.shop_diagnosis_minigame.kundenbericht_sichere_messung_hypothese_befund_unnoetiger",
		"Kundenbericht → sichere Messung → Hypothese → Befund. "
		+ "Unnoetiger Teiletausch kostet Vertrauen."), 11)
	workflow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(workflow)
	row.add_child(Bezel.lcd_label(Loc.t("ui.shop_diagnosis_minigame.fall_03d_s", "FALL %03d · %s") % [
		_model.case_number, _model.device_label()], Palette.LCD_AMBER, 10))


func _build_customer_card(parent: VBoxContainer) -> void:
	var card := PanelContainer.new()
	var panel := Bezel.panel_box()
	panel.bg_color = Color8(11, 18, 19)
	panel.border_color = Color8(75, 112, 101)
	card.add_theme_stylebox_override("panel", panel)
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	card.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	top.add_child(Bezel.lcd_label(Loc.t("ui.shop_diagnosis_minigame.kundenannahme", "KUNDENANNAHME"), Palette.LCD_AMBER, 10))
	_customer_state = Bezel.lcd_label(Loc.t("ui.shop_diagnosis_minigame.besorgt", "BESORGT"), Color8(245, 190, 70), 10)
	_customer_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_customer_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_customer_state)
	var symptom := Label.new()
	symptom.text = "»%s«" % _model.symptom()
	symptom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	symptom.custom_minimum_size.y = 42
	symptom.add_theme_font_size_override("font_size", 12)
	symptom.add_theme_color_override("font_color", Color8(229, 231, 216))
	body.add_child(symptom)
	_evidence = Bezel.dim_label("", 11)
	body.add_child(_evidence)


func _build_log(parent: VBoxContainer) -> void:
	_log = RichTextLabel.new()
	_log.name = "ServiceProtocol"
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.custom_minimum_size.y = 104
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.text = Loc.t("ui.shop_diagnosis_minigame.color_8fd_serviceprotokoll_bereit_messpunkt_oder", "[color=#8fd]Serviceprotokoll bereit. Messpunkt oder Taste 1–6 waehlen.[/color]")
	parent.add_child(_log)


func _build_test_buttons(parent: VBoxContainer) -> void:
	var caption := Bezel.dim_label(Loc.t("ui.shop_diagnosis_minigame.messungen_tasten_1_6", "MESSUNGEN · TASTEN 1–6"), 11)
	caption.add_theme_color_override("font_color", Palette.LCD_AMBER)
	parent.add_child(caption)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for index in Model.TESTS.size():
		var test: StringName = Model.TESTS[index]
		var button := make_button("%d  %s" % [index + 1, Model.TEST_LABELS[test]],
			_test.bind(test))
		button.custom_minimum_size = Vector2(185, 30)
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = Loc.t("ui.shop_diagnosis_minigame.messung_dokumentieren_fehlerhypothese_eingrenzen", "Messung dokumentieren und Fehlerhypothese eingrenzen")
		grid.add_child(button)
		_test_buttons[test] = button


func _build_fault_buttons(parent: VBoxContainer) -> void:
	var caption := Bezel.dim_label(Loc.t("ui.shop_diagnosis_minigame.befund_kostenvoranschlag", "BEFUND / KOSTENVORANSCHLAG"), 11)
	caption.add_theme_color_override("font_color", Palette.LCD_AMBER)
	parent.add_child(caption)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for fault: StringName in Model.FAULTS:
		var button := make_button(str(Model.FAULT_LABELS[fault]), _diagnose.bind(fault))
		button.custom_minimum_size = Vector2(185, 30)
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = Loc.t("ui.shop_diagnosis_minigame.befund_verbindlich_abgeben", "Befund verbindlich abgeben")
		grid.add_child(button)
		_fault_buttons[fault] = button


func _build_assistance(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var hint := make_button(Loc.t("ui.shop_diagnosis_minigame.handbuch_hinweis", "HANDBUCH-HINWEIS"), _hint)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	var auto := make_button(Loc.t("ui.shop_diagnosis_minigame.meister_diagnose", "MEISTER-DIAGNOSE"), _auto)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(auto)


func _test(test: StringName) -> void:
	if _finished:
		return
	var result := _model.run_test(test)
	if not bool(result.get("ok", false)):
		_status.text = str(result.get("text", "Messung nicht verfuegbar."))
		AudioManager.minigame_cue("shop_diagnosis", &"error")
		return
	var marker := "[color=#fd6]■ ABWEICHUNG[/color]" \
		if bool(result.get("positive", false)) \
		else ("[color=#fc6]◆ GRENZWERT[/color]" \
			if bool(result.get("ambiguous", false)) \
			else "[color=#7b9]✓ REFERENZ[/color]")
	_log.text += "\n%s %s" % [marker, result.get("text", "")]
	if _bench != null:
		_bench.call("show_reading", test, str(result.get("value", "—")),
			bool(result.get("positive", false)), bool(result.get("ambiguous", false)))
	AudioManager.minigame_cue("shop_diagnosis", &"action")
	_refresh()


func _diagnose(fault: StringName) -> void:
	if _finished:
		return
	var had_evidence := _model.enough_evidence()
	if _model.diagnose(fault):
		_log.text += "\n[color=#6f9]BEFUND BESTAETIGT: %s[/color]" \
			% Model.FAULT_LABELS[fault]
		if _bench != null:
			_bench.call("show_solved")
		_commit()
		return
	if fault == _model.fault and not had_evidence:
		_log.text += "\n[color=#fc6]Befund noch nicht belastbar: zweite Messung fehlt.[/color]"
	else:
		_log.text += "\n[color=#f86]Fehldiagnose: %s passt nicht zum Protokoll.[/color]" \
			% Model.FAULT_LABELS[fault]
	AudioManager.minigame_cue("shop_diagnosis", &"error")
	_refresh()


func _hint() -> void:
	if _finished:
		return
	var test := _model.hint()
	_status.text = Loc.t("ui.shop_diagnosis_minigame.werkstatthandbuch_empfiehlt_s", "Werkstatthandbuch empfiehlt: %s") \
		% Model.TEST_LABELS.get(test, "Befund abgeben")
	if not test.is_empty() and _bench != null:
		_bench.call("show_reading", test, "PRUEFPUNKT MARKIERT", false, true)


func _auto() -> void:
	if _finished:
		return
	_model.auto_solve()
	_log.text += "\n[color=#6f9]Meisterdiagnose: %s · Gegenprobe dokumentiert.[/color]" \
		% Model.FAULT_LABELS[_model.fault]
	if _bench != null:
		_bench.call("show_solved")
	_commit()


func _refresh() -> void:
	for test: StringName in _test_buttons:
		var button := _test_buttons[test] as Button
		button.disabled = test in _model.tested or _finished
		var marker := "✓" if test in _model.tested \
			else str(Model.TESTS.find(test) + 1)
		button.text = "%s %s" % [marker, str(Model.TEST_LABELS[test])]
	for fault: StringName in _fault_buttons:
		var button := _fault_buttons[fault] as Button
		var state := _model.candidate_state(fault)
		button.disabled = _finished or _model.failed() or state in [&"excluded", &"rejected"]
		button.add_theme_color_override("font_color",
			Color8(113, 231, 158) if state == &"plausible" else Palette.WHITE_SOFT)
		button.add_theme_color_override("font_disabled_color", Color8(78, 86, 82))
	_evidence.text = Loc.t("ui.shop_diagnosis_minigame.evidenz_d_d_d_hypothesen_verbleiben", "EVIDENZ %d/%d · %d HYPOTHESEN VERBLEIBEN") % [
		_model.evidence_count(), _model.evidence_required(),
		_model.remaining_hypotheses().size()]
	_status.text = Loc.t("ui.shop_diagnosis_minigame.level_d_d_messungen_d_d", "LEVEL %d · %d MESSUNGEN · %d/%d BEFUNDE") % [
		_model.level, _model.tested.size(), _model.diagnoses.size(),
		_model.max_diagnoses]
	if _model.tested.size() > 0:
		_customer_state.text = Loc.t("ui.shop_diagnosis_minigame.wartet_auf_befund", "WARTET AUF BEFUND")
		_customer_state.add_theme_color_override("font_color", Color8(110, 205, 238))
	if _model.failed():
		_status.text = Loc.t("ui.shop_diagnosis_minigame.auftrag_abgebrochen_keine_zahlung_keine_energie", "AUFTRAG ABGEBROCHEN · keine Zahlung, keine Energie verbraucht.")
		_customer_state.text = Loc.t("ui.shop_diagnosis_minigame.vertrauen_verloren", "VERTRAUEN VERLOREN")
		_customer_state.add_theme_color_override("font_color", Color8(245, 91, 70))


func _commit() -> bool:
	if _finished or not _model.solved:
		return false
	var score := _model.score()
	var details := _model.details()
	var result := JobManager.complete_minigame_job(job_id, score, details)
	if not bool(result.get("ok", false)):
		if _status != null:
			_status.text = str(result.get("text", "Commit fehlgeschlagen."))
		return false
	_finished = true
	details["pay"] = int(result.get("pay", 0))
	MinigameManager.finish("shop_diagnosis", true, score, details)
	GameManager.flags["last_shop_diagnosis"] = details
	if _status != null:
		_status.text = Loc.t("ui.shop_diagnosis_minigame.auftrag_bestanden_d_dm_04d_punkte", "AUFTRAG BESTANDEN · +%d DM · %04d PUNKTE") % [
			details.pay, score]
		_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	if _customer_state != null:
		_customer_state.text = Loc.t("ui.shop_diagnosis_minigame.erleichtert", "ERLEICHTERT")
		_customer_state.add_theme_color_override("font_color", Color8(92, 244, 155))
	for button: Button in _test_buttons.values():
		button.disabled = true
	for button: Button in _fault_buttons.values():
		button.disabled = true
	AudioManager.minigame_cue("shop_diagnosis", &"success")
	AudioManager.key_enter()
	return true
