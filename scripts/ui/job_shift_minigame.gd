class_name JobShiftMinigame
extends RetroWindow
## Vier spielbare Arbeitsschichten in einer gemeinsamen Produktions-Engine:
## Route, Lager, Reparatur und Code. Keine Auszahlung beim Oeffnen/Abbrechen;
## JobManager verbucht erst eine bestandene komplette Schicht atomar.

const Model := preload("res://scripts/minigames/job_shift_model.gd")
const Stage := preload("res://scripts/ui/job_shift_stage.gd")

var job_id := ""
var _job: Dictionary = {}
var _model
var _stage: Control
var _round_label: Label
var _score_label: Label
var _instruction: Label
var _finished := false
var _stage_seconds := 0
var _stage_phase := ""
var _feedback_pending := false


func _init() -> void:
	title = Loc.t("ui.job_shift_minigame.title", "ARBEITSSCHICHT · AUFTRAG")
	win_size = Vector2(990, 720)


static func can_start(requested_job_id: String) -> Dictionary:
	var gate := JobManager.start_gate(requested_job_id)
	if not bool(gate.get("ok", false)):
		return gate
	var job: Dictionary = gate.get("job", {})
	if str(job.get("minigame", "")) != "job_shift":
		return {"ok": false, "reason": Loc.t("ui.job_shift_minigame.no_order",
			"Dieser Auftrag benutzt eine andere Arbeitsstation.")}
	return gate


func _ready() -> void:
	_job = JobManager.job_by_id(job_id)
	if _job.is_empty():
		queue_free()
		return
	var localized_job_name := Loc.t("job.%s.name" % job_id, str(_job.get("name", "AUFTRAG")))
	title = Loc.t("ui.job_shift_minigame.job_title", "ARBEITSSCHICHT · %s") % localized_job_name.to_upper()
	super._ready()
	var wins := JobManager.completion_count(job_id)
	_model = Model.new()
	_model.configure(job_id, int(hash("JOBSHIFT/%s/%d/%d" % [job_id, TimeManager.day_counter, wins])))
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(Bezel.lcd_label(_model.localized_title(), Palette.LCD_AMBER, 15))
	var brief := Bezel.dim_label(_model.localized_brief(), 10)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(brief)
	top.add_child(identity)
	_round_label = Bezel.lcd_label("", Palette.LCD_CYAN, 11)
	_round_label.custom_minimum_size.x = 200
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_round_label)
	content.add_child(top)

	_stage = Stage.new()
	_stage.custom_minimum_size = Vector2(954, 555)
	_stage.choice_selected.connect(_on_choice)
	_stage.hud_changed.connect(_on_stage_hud_changed)
	content.add_child(_stage)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	_instruction = Bezel.dim_label(_controls_for_mode(), 10)
	_instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_instruction)
	_score_label = Bezel.lcd_label(Loc.t("ui.job_shift_minigame.score", "%04d P · %d OK") % [0, 0], Palette.LCD_GREEN, 12)
	_score_label.custom_minimum_size.x = 180
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_score_label)
	content.add_child(footer)


func _on_choice(index: int) -> void:
	if _finished or _feedback_pending or _model.finished():
		return
	var result: Dictionary = _model.answer(index, float(_stage.get("last_performance")))
	if not bool(result.get("accepted", false)):
		return
	var correct := bool(result.get("correct", false))
	var feedback_text := ""
	if correct:
		AudioManager.minigame_cue("job_shift", &"action")
		feedback_text = "%s  %s" % [_success_cue(), _performance_cue(float(result.get("performance", 0.0)))]
		if _model.mode() == "repair":
			feedback_text = "%s  %s" % [feedback_text, _localized_repair_reason(result)]
	else:
		AudioManager.minigame_cue("job_shift", &"error")
		feedback_text = _repair_error_text(result) if _model.mode() == "repair" else Loc.t(
			"ui.job_shift_minigame.wrong",
			"FEHLGRIFF · Markierung lesen, dann den naechsten Arbeitsschritt sauber setzen.")
	_instruction.text = feedback_text
	_stage.feedback(correct, index, int(result.get("expected", -1)))
	if bool(result.get("finished", false)):
		_finish_shift()
	else:
		# Die alte Runde bleibt kurz sichtbar. Sonst ueberschrieb die Folgerunde
		# sofort Begruendung, Werkzeugmarkierung und Trefferimpuls.
		_feedback_pending = true
		get_tree().create_timer(1.05).timeout.connect(_advance_after_feedback)


func _advance_after_feedback() -> void:
	if not is_inside_tree() or _finished:
		return
	_feedback_pending = false
	_refresh()


func _refresh() -> void:
	_update_round_label()
	_score_label.text = Loc.t("ui.job_shift_minigame.score", "%04d P · %d OK") % [
		_model.points, _model.correct_count]
	var display_prompt: Dictionary = _model.prompt.duplicate(true)
	display_prompt["job_id"] = job_id
	display_prompt["signal"] = _model.localized_signal()
	display_prompt["choices"] = _model.localized_choices()
	display_prompt["choice_ids"] = (_model.prompt.get("choices", []) as Array).duplicate()
	if _model.mode() == "repair":
		for field: String in ["clue", "procedure", "gauge"]:
			display_prompt[field] = _model.localized_repair_field(field)
		var tool_help: Array[String] = []
		for choice: String in _model.prompt.get("choices", []):
			tool_help.append(_model.localized_tool_help(choice))
		display_prompt["tool_help"] = tool_help
	_stage.set_state(_model.mode(), display_prompt, _model.round_index, _model.total_rounds())
	_instruction.text = _controls_for_mode()


func _on_stage_hud_changed(seconds_left: int, phase_label: String) -> void:
	_stage_seconds = maxi(0, seconds_left)
	_stage_phase = phase_label
	_update_round_label()


func _update_round_label() -> void:
	if _round_label == null or _model == null:
		return
	_round_label.text = Loc.t("ui.job_shift_minigame.round_live",
		"VORGANG %02d/%02d · SERIE %02d · %02d SEK") % [
		_model.round_index + 1, _model.total_rounds(), _model.streak, _stage_seconds]


func _controls_for_mode() -> String:
	match _model.mode():
		"route": return Loc.t("ui.job_shift_minigame.controls_route",
			"ZIELEN: Maus bewegen/Pfeile · WERFEN: Klick oder Leertaste erst im cyanfarbenen Wurffenster.")
		"sort": return Loc.t("ui.job_shift_minigame.controls_sort",
			"FOERDERBAND LAEUFT · Karton greifen und vor Ablauf ins beschriftete Fach ziehen.")
		"repair": return Loc.t("ui.job_shift_minigame.controls_repair",
			"BEOBACHTUNG LESEN · Eines von drei markierten Werkzeugen waehlen · Anwendung im gruenen Bereich bestaetigen.")
		"code": return Loc.t("ui.job_shift_minigame.controls_code",
			"PATCH WAEHLEN · Karte in die markierte Codezeile ziehen oder Zahl + Enter nutzen.")
	return Loc.t("ui.job_shift_minigame.controls",
		"Maus oder Zifferntasten 1–8 · Ein Fehlgriff kostet Punkte, aber nie sofort Geld.")


func _finish_shift() -> void:
	if _finished:
		return
	if not _model.passed():
		_instruction.text = Loc.t("ui.job_shift_minigame.failed",
			"SCHICHT NICHT ABGENOMMEN · Mindestens 70 %% der Vorgaenge muessen stimmen. Fenster schliessen und neu versuchen.")
		_round_label.text = Loc.t("ui.job_shift_minigame.quality_failed", "QUALITAET %d/%d · NICHT ABGENOMMEN") % [
			_model.correct_count, _model.total_rounds()]
		_stage.finish(false, Loc.t("ui.job_shift_minigame.stage_failed", "QUALITAET NICHT ERREICHT"))
		AudioManager.minigame_cue("job_shift", &"error")
		MinigameManager.finish("job_shift", false, _model.score(), _model.details())
		return
	var details: Dictionary = _model.details()
	var result: Dictionary = JobManager.complete_minigame_job(job_id, _model.score(), details)
	if not bool(result.get("ok", false)):
		_instruction.text = str(result.get("text", "Auftrag konnte nicht verbucht werden."))
		return
	_finished = true
	MinigameManager.finish("job_shift", true, _model.score(), details)
	var localized_job_name := Loc.t("job.%s.name" % job_id,
		str(_job.get("name", "eine Arbeitsschicht")))
	MemoryManager.record("nebenjob", Loc.t("ui.job_shift_minigame.memory_record",
		"%s mit %d/%d korrekten Vorgaengen abgeschlossen") % [
		localized_job_name, _model.correct_count, _model.total_rounds()])
	_round_label.text = Loc.t("ui.job_shift_minigame.accepted", "ABGENOMMEN · %04d PUNKTE · +%d DM") % [
		_model.score(), int(result.get("pay", 0))]
	_score_label.text = Loc.t("ui.job_shift_minigame.done", "SCHICHT KOMPLETT")
	_instruction.text = str(result.get("text", "Auftrag erledigt."))
	_stage.finish(true, Loc.t("ui.job_shift_minigame.stage_passed", "SCHICHT ABGENOMMEN"))
	AudioManager.minigame_cue("job_shift", &"success")
	AudioManager.play("coins")
	UIManager.toast(str(result.get("text", "Auftrag erledigt.")))


func _success_cue() -> String:
	match _model.mode():
		"route": return Loc.t("ui.job_shift_minigame.route_ok", "TREFFER · Zeitung/Flyer sitzt, Route laeuft weiter.")
		"repair": return Loc.t("ui.job_shift_minigame.repair_ok", "SICHERER SCHRITT · Messkette bleibt nachvollziehbar.")
		"code": return Loc.t("ui.job_shift_minigame.code_ok", "PATCH GRUEN · Build laeuft bis zum naechsten Test.")
	return Loc.t("ui.job_shift_minigame.sort_ok", "FACH KORREKT · Ware erfasst und weiter zum naechsten Karton.")


func _performance_cue(value: float) -> String:
	if value >= 0.9:
		return Loc.t("ui.job_shift_minigame.performance_perfect", "BLITZSAUBER · voller Leistungswert")
	if value >= 0.72:
		return Loc.t("ui.job_shift_minigame.performance_good", "SAUBER · guter Leistungswert")
	return Loc.t("ui.job_shift_minigame.performance_safe", "ERLEDIGT · knapp im Soll")


func _localized_repair_reason(result: Dictionary) -> String:
	var signal_id := str(result.get("signal_id", "unknown"))
	return Loc.t("ui.job_shift_minigame.repair.%s.reason" % signal_id,
		str(result.get("reason", "Befund und Arbeitsschritt passen zusammen.")))


func _repair_error_text(result: Dictionary) -> String:
	var expected: String = str(_model.localized_choice_id(str(result.get("expected_choice", ""))))
	return Loc.t("ui.job_shift_minigame.repair_wrong",
		"FALSCHE REIHENFOLGE · Hier waere %s der sichere naechste Schritt. %s") % [
		expected, _localized_repair_reason(result)]
