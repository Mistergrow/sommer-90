class_name HouseholdSprintMinigame
extends RetroWindow
## Controller der AGA-Hausauftrags-Spielstation. Die Buehne erzeugt nur
## Aktionen; der Regelkern bewertet sie und allein ChoreManager zahlt aus.

const Model := preload("res://scripts/minigames/household_sprint_model.gd")
const Stage := preload("res://scripts/ui/household_sprint_stage.gd")

var chore_id := ""
var _chore: Dictionary = {}
var _model
var _stage: Control
var _status: Label
var _instruction: Label
var _finished := false
var _elapsed_seconds := 0


func _init() -> void:
	title = Loc.t("ui.household_sprint.title", "HAUSAUFTRAG · AGA-SPIELSTATION")
	win_size = Vector2(1180, 800)


static func can_start(requested_id: String) -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.household_sprint.not_playing",
			"Nur waehrend eines laufenden Spiels verfuegbar.")}
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": Loc.t("ui.household_sprint.only_home",
			"Hausarbeit beginnt am Arbeitsheft im eigenen Zimmer.")}
	return ChoreManager.can_do_chore(requested_id)


func _ready() -> void:
	_chore = ChoreManager.chore_by_id(chore_id)
	if _chore.is_empty():
		queue_free()
		return
	title = Loc.t("ui.household_sprint.job_title", "HAUSAUFTRAG · %s") % \
		ChoreManager.localized_field(_chore, "label").to_upper()
	super._ready()
	_model = Model.new()
	_model.configure(chore_id, int(hash("CHORE/%s/%d" % [chore_id, TimeManager.day_counter])))
	MinigameManager.begin_session("household_sprint")
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(Bezel.lcd_label(Loc.t("ui.household_sprint.profile.%s.title" % chore_id,
		str(_model.profile.get("title", "HAUSAUFTRAG"))), Palette.LCD_AMBER, 16))
	var brief := Bezel.dim_label(ChoreManager.localized_field(_chore, "hint"), 10)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(brief)
	top.add_child(identity)
	_status = Bezel.lcd_label("", Palette.LCD_CYAN, 12)
	_status.custom_minimum_size.x = 310
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status)
	content.add_child(top)

	_stage = Stage.new()
	_stage.custom_minimum_size = Vector2(1144, 620)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.action_submitted.connect(_on_action)
	_stage.hud_changed.connect(_on_stage_hud_changed)
	content.add_child(_stage)

	_instruction = Bezel.dim_label(_controls_text(), 10)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_instruction)


## Variant haelt den alten Vector2-Testadapter absichtlich kompatibel. Die
## Produkt-UI sendet ausschliesslich die typisierten Dictionary-Aktionen.
func _on_action(action: Variant) -> void:
	if _finished:
		return
	var result: Dictionary
	if action is Dictionary:
		result = _model.apply_action(action)
	elif action is Vector2:
		result = _model.apply_at(action)
	else:
		return
	if not bool(result.get("accepted", false)):
		return
	MinigameManager.note_runtime("household_sprint", &"action")
	var good := bool(result.get("hit", false))
	_stage.feedback(good, result)
	if good:
		AudioManager.minigame_cue("household_sprint", &"action")
		_instruction.text = _hit_text(result)
	else:
		MinigameManager.note_runtime("household_sprint", &"error")
		AudioManager.minigame_cue("household_sprint", &"error")
		_instruction.text = _miss_text(result)
	_refresh()
	if bool(result.get("finished", false)):
		_finish()


func _refresh() -> void:
	_stage.set_state(chore_id, _model.mode(), _model.targets, _model.cleared,
		_model.total_targets(), _model.combo)
	_refresh_status()


func _on_stage_hud_changed(elapsed_seconds: int, _phase_label: String) -> void:
	_elapsed_seconds = elapsed_seconds
	_refresh_status()


func _refresh_status() -> void:
	_status.text = Loc.t("ui.household_sprint.progress",
		"REPARATUR %02d/%02d · KOMBO %02d · %02d:%02d") % [
		_model.completed_steps(), _model.total_steps(), _model.combo,
		floori(float(_elapsed_seconds) / 60.0), _elapsed_seconds % 60]


func _finish() -> void:
	if _finished:
		return
	var details: Dictionary = _model.details()
	details["elapsed_seconds"] = _elapsed_seconds
	var result: Dictionary = ChoreManager.complete_chore_minigame(chore_id, _model.score(), details)
	if not bool(result.get("ok", false)):
		_instruction.text = str(result.get("text", Loc.t("ui.household_sprint.finish_failed",
			"Abschluss konnte nicht verbucht werden.")))
		return
	_finished = true
	MinigameManager.finish("household_sprint", true, _model.score(), details)
	_status.text = Loc.t("ui.household_sprint.complete", "ABGENOMMEN · %04d P · +%s") % [
		_model.score(), Currency.format(float(result.get("reward", 0.0)))]
	_instruction.text = str(result.get("text", Loc.t("ui.household_sprint.finished", "Hausauftrag erledigt.")))
	_stage.finish(_instruction.text)
	AudioManager.play("coins")
	UIManager.toast(_instruction.text)


func _controls_text() -> String:
	return Loc.t("ui.household_sprint.controls.%s" % _model.mode(), _controls_fallback())


func _controls_fallback() -> String:
	match _model.mode():
		"sort": return "ZIEHEN · Abfall lesen und in den passenden Container werfen."
		"organize": return "ZIEHEN · Gegenstaende in Regal, Diskbox, Waesche oder Papierkorb legen."
		"dishes": return "ABWASCH · Jedes Teil durch Einweichen, Spuelen und Abtropfen fuehren."
		"vacuum": return "SAUGEN · Maustaste halten und jeden Kruemel zweimal abfahren."
		"shopping": return "EINKAUF · Nur die Waren vom Einkaufszettel anklicken."
		"detail": return "AUTOPFLEGE · Werkzeug 1–3 waehlen und jedes Blech in Reihenfolge behandeln."
		"mower": return "MAEHEN · Maustaste halten und alle Rasenfelder lueckenlos abfahren."
	return "AUFTRAG BEREIT"


func _hit_text(result: Dictionary) -> String:
	var suffix := ""
	if bool(result.get("removed", false)):
		suffix = Loc.t("ui.household_sprint.target_complete", " · ABSCHNITT FERTIG")
	return Loc.t("ui.household_sprint.hit.%s" % _model.mode(), _hit_fallback()) + suffix


func _hit_fallback() -> String:
	match _model.mode():
		"sort": return "TREFFER · Material richtig getrennt."
		"organize": return "ORDNUNG · Gegenstand sitzt am richtigen Platz."
		"dishes": return "SPUELTAKT · Naechste Station freigegeben."
		"vacuum": return "SAUGSPUR · Kruemel aufgenommen."
		"shopping": return "LISTE · Richtige Ware eingepackt."
		"detail": return "GLANZPASS · Werkzeugfolge stimmt."
		"mower": return "SCHNITT · Saubere Bahn ohne Luecke."
	return "TREFFER"


func _miss_text(result: Dictionary) -> String:
	var expected := int(result.get("expected", -1))
	if expected >= 0 and _model.mode() in ["dishes", "detail"]:
		return Loc.t("ui.household_sprint.miss_sequence",
			"FALSCHE REIHENFOLGE · Naechster Arbeitsschritt: %d.") % (expected + 1)
	return Loc.t("ui.household_sprint.miss",
		"FEHLGRIFF · Ziel, Material oder Einkaufszettel noch einmal pruefen.")
