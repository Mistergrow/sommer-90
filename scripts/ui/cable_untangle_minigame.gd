class_name CableUntangleMinigame
extends RetroWindow
## Grubers spielbarer Nebenjob: drei echte Kabelbuendel aus der Kiste nehmen,
## Stecker unter Seilphysik neu ordnen und per Durchgangspruefer abnehmen.
## Kein Zeitlimit; Auszahlung/Energie/Zeit werden erst am finalen Erfolg verbucht.

const Model := preload("res://scripts/minigames/cable_untangle_model.gd")
const BENCH := preload("res://assets/ui/minigames/CABLE_UNTANGLE_GRUBER_BENCH_MASTER_V01.png")
const LocationDepth := preload("res://scripts/gfx/location_stage_25d.gd")
const JOB_ID := "job_gruber_cables"

var job_id := JOB_ID
var _model: CableUntangleModel
var _round := 0
var _counts: Array[int] = [4, 5, 6]
var _level := 1
var _scores: Array[int] = []
var _details: Array[Dictionary] = []
var _finished := false
var _testing := false
var _stage: CableStage
var _round_label: Label
var _quality_label: Label
var _instruction: Label
var _test_button: Button


func _init() -> void:
	title = Loc.t("ui.cable_untangle_minigame.grubers_kabelkiste_reparatur_auftrag", "GRUBERS KABELKISTE · REPARATUR-AUFTRAG")
	win_size = Vector2(1010, 740)


static func can_start(requested_job_id := JOB_ID) -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.cable_untangle_minigame.nur_waehrend_eines_laufenden_spiels_verfuegbar", "Nur waehrend eines laufenden Spiels verfuegbar.")}
	if GameManager.current_location_id != "computer_shop":
		return {"ok": false, "reason": Loc.t("ui.cable_untangle_minigame.kabelkiste_steht_bei_gruber_im_computerladen", "Die Kabelkiste steht bei Gruber im Computerladen.")}
	var job: Dictionary = JobManager.job_by_id(requested_job_id)
	if job.is_empty() or str(job.get("minigame", "")) != "cable_untangle":
		return {"ok": false, "reason": "Gruber hat gerade keinen Kabelauftrag."}
	if not JobManager.offered_here(job, GameManager.current_location_id):
		return {"ok": false, "reason": Loc.t("ui.cable_untangle_minigame.gruber_ist_nicht_da_oder_nimmt", "Gruber ist nicht da oder nimmt jetzt keine Reparaturhilfe an.")}
	var chk: Dictionary = JobManager.can_do(job)
	if not bool(chk.get("ok", false)):
		return {"ok": false, "reason": str(chk.get("reason", "Auftrag gerade nicht moeglich."))}
	return {"ok": true, "reason": "", "job": job}


func _ready() -> void:
	if job_id == "job_praktikum_shift":
		title = Loc.t("ui.cable_untangle_minigame.grubers_praktikum_steckerpruefung", "GRUBERS PRAKTIKUM · STECKERPRUEFUNG")
	super._ready()
	var wins := int(MinigameManager.record("cable_untangle").get("wins", 0))
	_level = 1 if wins == 0 else (2 if wins < 2 else (3 if wins < 4 else 4))
	var configured_counts: Array = [[4, 5, 6], [5, 6, 7], [6, 7, 7], [7, 7, 7]][_level - 1]
	_counts.clear()
	for count in configured_counts:
		_counts.append(int(count))
	_build_shell()
	_begin_bundle()


func _build_shell() -> void:
	var intro := Bezel.dim_label(Loc.t("ui.cable_untangle_minigame.gruber_instructions",
		"Gruber: »Ordne jeden farbigen Stecker seiner gleich markierten Zielbuchse zu. Klicke einen Stecker an oder zieh ihn in die freie schwarze Pufferbuchse.«"), 11)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)

	var telemetry := HBoxContainer.new()
	_round_label = Bezel.lcd_label("", Palette.LCD_AMBER, 11)
	_round_label.custom_minimum_size = Vector2(300, 22)
	telemetry.add_child(_round_label)
	_quality_label = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	telemetry.add_child(_quality_label)
	content.add_child(telemetry)

	_stage = CableStage.new()
	_stage.custom_minimum_size = Vector2(974, 540)
	_stage.move_requested.connect(_on_move)
	_stage.request_hint.connect(_hint)
	_stage.request_undo.connect(_undo)
	_stage.request_reset.connect(_reset_bundle)
	_stage.request_test.connect(_test_bundle)
	content.add_child(_stage)

	_instruction = Bezel.dim_label("", 11)
	_instruction.custom_minimum_size = Vector2(0, 38)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_instruction)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 7)
	footer.add_child(make_button(Loc.t("ui.cable_untangle_minigame.undo", "↶ UNDO"), _undo))
	footer.add_child(make_button(Loc.t("ui.cable_untangle_minigame.neu_auslegen", "NEU AUSLEGEN"), _reset_bundle))
	footer.add_child(make_button(Loc.t("ui.cable_untangle_minigame.hinweis", "HINWEIS"), _hint))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_test_button = make_button(Loc.t("ui.cable_untangle_minigame.durchgang_pruefen", "⚡ DURCHGANG PRUEFEN"), _test_bundle)
	_test_button.custom_minimum_size = Vector2(220, 38)
	footer.add_child(_test_button)
	content.add_child(footer)


func _begin_bundle() -> void:
	_model = Model.new()
	var round_seed := int(hash("GRUBER/%d/%d/%d" % [TimeManager.day_counter, _round, _counts[_round]]))
	_model.configure(_counts[_round], round_seed)
	_stage.set_model(_model)
	_stage.testing = false
	_stage.celebrate = false
	_stage.board.testing = false
	_testing = false
	_round_label.text = Loc.t("ui.cable_untangle_minigame.level_d_kiste_d_3_d", "LEVEL %d  ·  KISTE %d/3  ·  %d KABEL") % [_level, _round + 1, _model.cable_count]
	_instruction.text = Loc.t("ui.cable_untangle_minigame.klicke_einen_farbigen_stecker_er_wechselt", "Klicke einen farbigen Stecker: Er wechselt direkt in die leuchtende freie Pufferbuchse. Ziehen funktioniert ebenfalls.")
	_refresh()
	_stage.board.grab_focus.call_deferred()


func _correct_plug_count() -> int:
	if _model == null:
		return 0
	var correct := 0
	for slot in _model.order.size():
		var cable_id := int(_model.order[slot])
		if cable_id != Model.EMPTY and cable_id == int(_model.target_order[slot]):
			correct += 1
	return correct


func _refresh() -> void:
	if _model == null:
		return
	var correct := _correct_plug_count()
	var remaining := _model.cable_count - correct
	_quality_label.text = Loc.t("ui.cable_untangle_minigame.zuge_02d_noch_02d_richtig_d", "ZÜGE %02d  ·  NOCH %02d  ·  RICHTIG %d/%d") % [
		_model.moves, remaining, correct, _model.cable_count]
	_quality_label.add_theme_color_override("font_color", Palette.LCD_GREEN if _model.is_solved() else Palette.LCD_CYAN)
	_test_button.disabled = not _model.is_solved() or _testing or _finished
	_test_button.text = (Loc.t("ui.cable_untangle_minigame.test_now",
		"⚡ JETZT DURCHGANG PRÜFEN") if _model.is_solved()
		else Loc.t("ui.cable_untangle_minigame.test_remaining",
			"⚡ DURCHGANG · NOCH %d") % remaining)
	_test_button.self_modulate = Color(0.62, 1.0, 0.72) if _model.is_solved() else Color.WHITE
	_stage.board.queue_redraw()


func _on_move(source_slot: int) -> void:
	if _testing or _finished or not _model.move_to_empty(source_slot):
		return
	AudioManager.play("joystick_click")
	_stage.board.model_changed()
	_instruction.text = (Loc.t("ui.cable_untangle_minigame.all_correct",
		"Alle Stecker sitzen richtig. Der grüne Durchgangsprüfer ist jetzt bereit.")
		if _model.is_solved()
		else Loc.t("ui.cable_untangle_minigame.move_done",
			"Zug ausgeführt. Der frei gewordene schwarze Puffer ist das nächste Ziel."))
	_refresh()


func _hint() -> void:
	if _testing or _finished:
		return
	var pair := _model.use_hint()
	if pair.x < 0:
		_instruction.text = Loc.t("ui.cable_untangle_minigame.alle_ziele_stimmen_durchgangspruefer_ist_bereit", "Alle Ziele stimmen — der Durchgangspruefer ist bereit.")
		return
	_stage.board.highlight_slots(pair.x, pair.y)
	var cable_id := int(_model.order[pair.x])
	var symbol := str(_model.cable_def(cable_id).get("symbol", "?"))
	_instruction.text = Loc.t("ui.cable_untangle_minigame.hinweis_klicke_jetzt_den_leuchtenden_s", "Hinweis: Klicke jetzt den leuchtenden %s-Stecker. Er wechselt direkt in den schwarzen Puffer.") % symbol
	AudioManager.ui_click()
	_refresh()


func _undo() -> void:
	if _testing or _finished:
		return
	if _model.undo():
		_stage.board.model_changed()
		_instruction.text = Loc.t("ui.cable_untangle_minigame.letzten_umsteckzug_zurueckgenommen", "Letzten Umsteckzug zurueckgenommen.")
		AudioManager.relay()
		_refresh()


func _reset_bundle() -> void:
	if _testing or _finished:
		return
	_model.reset_round()
	_stage.board.reset_physics()
	_instruction.text = Loc.t("ui.cable_untangle_minigame.buendel_wieder_wie_aus_kiste_ausgelegt", "Buendel wieder wie aus der Kiste ausgelegt. Kein Zustand ausserhalb des Bretts wurde veraendert.")
	_refresh()


func _test_bundle() -> void:
	if _testing or _finished:
		return
	if not _model.is_solved():
		UIManager.toast(Loc.t("ui.cable_untangle_minigame.pruefer_meldet_falsche_buchse_farbe_buchstabe", "Der Pruefer meldet eine falsche Buchse — Farbe und Buchstabe muessen stimmen."))
		return
	_testing = true
	_test_button.disabled = true
	_stage.testing = true
	_stage.board.testing = true
	_instruction.text = Loc.t("ui.cable_untangle_minigame.durchgangspruefung_rgb_ser_mse_pwr_joy", "Durchgangspruefung: RGB · SER · MSE · PWR · JOY …")
	AudioManager.relay()
	await get_tree().create_timer(0.85).timeout
	if not is_inside_tree() or _finished:
		return
	_accept_bundle()


func _accept_bundle() -> void:
	if _model == null or not _model.is_solved():
		return
	var score := _model.score()
	_scores.append(score)
	_details.append(_model.details())
	AudioManager.play("continuity_ok")
	if _round < _counts.size() - 1:
		_round += 1
		_begin_bundle()
		_instruction.text = Loc.t("ui.cable_untangle_minigame.buendel_bestanden_d_punkte_gruber_stellt", "Buendel bestanden (%d Punkte). Gruber stellt die naechste, dichtere Kiste auf den Tisch.") % score
	else:
		_complete_job()


func _average_score() -> int:
	if _scores.is_empty():
		return 0
	var total := 0
	for value in _scores:
		total += value
	return int(round(float(total) / _scores.size()))


func _commit_success(score: int, details: Dictionary = {}) -> Dictionary:
	if _finished:
		return {"ok": false, "text": "Auftrag bereits verbucht."}
	var job_result: Dictionary = JobManager.complete_minigame_job(job_id, score, details)
	if not bool(job_result.get("ok", false)):
		return job_result
	_finished = true
	MinigameManager.finish("cable_untangle", true, score, details)
	MemoryManager.record("nebenjob", "bei Gruber drei Kabelbuendel entwirrt und durchgemessen")
	return job_result


func _complete_job() -> void:
	var score := _average_score()
	var details := {"bundles": _details.duplicate(true), "bundle_scores": _scores.duplicate(), "job": job_id, "level": _level}
	var result := _commit_success(score, details)
	if not bool(result.get("ok", false)):
		UIManager.toast(str(result.get("text", "Auftrag konnte nicht verbucht werden.")))
		_testing = false
		_stage.testing = false
		_stage.board.testing = false
		_refresh()
		return
	_stage.celebrate = true
	_stage.board.testing = false
	_stage.board.queue_redraw()
	_round_label.text = Loc.t("ui.cable_untangle_minigame.auftrag_abgenommen_gruber_ist_zufrieden", "AUFTRAG ABGENOMMEN  ·  GRUBER IST ZUFRIEDEN")
	_quality_label.text = Loc.t("ui.cable_untangle_minigame.04d_punkte_d_dm", "%04d PUNKTE  ·  +%d DM") % [score, int(result.get("pay", 0))]
	_quality_label.add_theme_color_override("font_color", Palette.LCD_GREEN)
	_instruction.text = Loc.t("ui.cable_untangle_minigame.alle_drei_buendel_sind_parallel_beschriftet", "Alle drei Buendel sind parallel, beschriftet und elektrisch in Ordnung. Lohn, Energie und Zeitfenster wurden jetzt atomar verbucht.")
	AudioManager.play("coins")
	UIManager.toast(str(result.get("text", "Kabelauftrag erledigt.")))


class CableStage:
	extends Control
	signal move_requested(source_slot: int)
	signal request_hint
	signal request_undo
	signal request_reset
	signal request_test

	var board: CableBoard
	var _depth: Control
	var _board_base := Vector2.ZERO
	var testing := false
	var celebrate := false

	func _ready() -> void:
		clip_contents = true
		var bg := TextureRect.new()
		bg.name = "GruberBenchMaster"
		bg.texture = BENCH
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		_depth = LocationDepth.new()
		_depth.configure(self, bg, "GRUBER_CABLE_BENCH", {
			"horizon": 0.32, "strength": 0.0095, "far_gain": 0.16, "near_gain": 0.78,
			"vertical_gain": 0.34, "overscan": 0.026, "pointer": 0.74, "idle": 0.055,
		})
		add_child(_depth)
		board = CableBoard.new()
		board.name = "PhysicalCableBoard"
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.z_index = 3
		board.move_requested.connect(func(source_slot: int) -> void: move_requested.emit(source_slot))
		board.request_hint.connect(func() -> void: request_hint.emit())
		board.request_undo.connect(func() -> void: request_undo.emit())
		board.request_reset.connect(func() -> void: request_reset.emit())
		board.request_test.connect(func() -> void: request_test.emit())
		add_child(board)
		_board_base = board.position
		var near := BenchNearEdge.new()
		near.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		near.offset_top = -26
		near.mouse_filter = Control.MOUSE_FILTER_IGNORE
		near.z_index = 6
		add_child(near)

	func set_model(value: CableUntangleModel) -> void:
		if board == null:
			await ready
		testing = false
		celebrate = false
		board.set_model(value)

	func _process(_delta: float) -> void:
		if board == null or _depth == null:
			return
		var look: Vector2 = _depth.look
		var gain := 1.0 if bool(SettingsManager.value("location_depth")) else 0.0
		board.position = _board_base + Vector2(look.x * 7.5, look.y * 3.0) * gain


class CableBoard:
	extends Control
	signal move_requested(source_slot: int)
	signal request_hint
	signal request_undo
	signal request_reset
	signal request_test

	const POINT_COUNT := 18
	var model: CableUntangleModel
	var ropes: Array[PackedVector2Array] = []
	var previous: Array[PackedVector2Array] = []
	var dragging_cable := -1
	var drag_from_slot := -1
	var drag_target := Vector2.ZERO
	var drag_visual := Vector2.ZERO
	var drag_velocity := Vector2.ZERO
	var drag_press_position := Vector2.ZERO
	var selected_slot := 0
	var hint_pair := Vector2i(-1, -1)
	var hint_t := 0.0
	var miss_t := 0.0
	var empty_hover := false
	var testing := false
	var _t := 0.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		set_process(true)

	func set_model(value: CableUntangleModel) -> void:
		model = value
		testing = false
		dragging_cable = -1
		drag_from_slot = -1
		selected_slot = 0
		hint_pair = Vector2i(-1, -1)
		hint_t = 0.0
		miss_t = 0.0
		empty_hover = false
		drag_velocity = Vector2.ZERO
		reset_physics()

	func reset_physics() -> void:
		ropes = []
		previous = []
		if model == null or size.x < 10.0:
			return
		for cable in model.cable_count:
			var points := PackedVector2Array()
			var prev := PackedVector2Array()
			var a := _top_port(cable)
			var b := _bottom_port(model.slot_of_cable(cable))
			for i in POINT_COUNT:
				var u := float(i) / (POINT_COUNT - 1)
				var p := a.lerp(b, u) + Vector2(sin(u * PI) * sin(cable * 1.71) * 22.0, sin(u * PI) * 25.0)
				points.append(p)
				prev.append(p)
			ropes.append(points)
			previous.append(prev)
		queue_redraw()

	func model_changed(reset_drag := true) -> void:
		if reset_drag:
			dragging_cable = -1
			hint_pair = Vector2i(-1, -1)
		queue_redraw()

	func highlight_slots(a: int, b: int) -> void:
		hint_pair = Vector2i(a, b)
		hint_t = 1.4
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if hint_t > 0.0:
			hint_t = maxf(0.0, hint_t - delta)
		if miss_t > 0.0:
			miss_t = maxf(0.0, miss_t - delta)
		if dragging_cable >= 0:
			drag_velocity += (drag_target - drag_visual) * 65.0 * delta
			drag_velocity *= exp(-delta * 10.0)
			drag_visual += drag_velocity * delta
		_simulate(minf(delta, 1.0 / 30.0))
		queue_redraw()

	func _simulate(delta: float) -> void:
		if model == null or ropes.size() != model.cable_count:
			return
		var gravity := Vector2(0, 88.0 * delta * delta)
		for cable in model.cable_count:
			var pts := ropes[cable]
			var prev := previous[cable]
			var end := drag_visual if cable == dragging_cable else _bottom_port(model.slot_of_cable(cable))
			for i in range(1, POINT_COUNT - 1):
				var current := pts[i]
				var velocity := (current - prev[i]) * 0.982
				prev[i] = current
				pts[i] = current + velocity + gravity + Vector2(sin(_t * 1.3 + cable * 2.1 + i) * 0.018, 0)
			var start := _top_port(cable)
			var rest := (start.distance_to(end) * 1.10 + 34.0) / (POINT_COUNT - 1)
			for _iteration in 5:
				pts[0] = start
				pts[POINT_COUNT - 1] = end
				for i in POINT_COUNT - 1:
					var delta_p := pts[i + 1] - pts[i]
					var distance := maxf(delta_p.length(), 0.001)
					var correction := delta_p * ((distance - rest) / distance) * 0.5
					if i > 0:
						pts[i] += correction
					if i + 1 < POINT_COUNT - 1:
						pts[i + 1] -= correction
			pts[0] = start
			pts[POINT_COUNT - 1] = end
			ropes[cable] = pts
			previous[cable] = prev
		# Milde Seil-Seil-Abstossung: Kreuzungen bleiben sichtbar, kleben aber
		# nicht pixelgenau ineinander und lesen sich als getrennte Gummikabel.
		for a in model.cable_count:
			for b in range(a + 1, model.cable_count):
				for i in range(3, POINT_COUNT - 3):
					var d := ropes[a][i] - ropes[b][i]
					if d.length_squared() > 0.01 and d.length() < 7.0:
						var push := d.normalized() * (7.0 - d.length()) * 0.08
						ropes[a][i] += push
						ropes[b][i] -= push

	func _top_port(index: int) -> Vector2:
		return Vector2(_top_port_x(index), size.y * 0.31)

	func _bottom_port(index: int) -> Vector2:
		return Vector2(_bottom_port_x(index), size.y * 0.76)

	func _top_port_x(index: int) -> float:
		if model == null or model.cable_count <= 1:
			return size.x * 0.5
		return lerpf(size.x * 0.14, size.x * 0.86, float(index) / (model.cable_count - 1))

	func _bottom_port_x(index: int) -> float:
		if model == null or model.cable_count < 1:
			return size.x * 0.5
		return lerpf(size.x * 0.12, size.x * 0.88, float(index) / model.cable_count)

	func _slot_at(pos: Vector2, max_distance := 42.0) -> int:
		if model == null:
			return -1
		var best := -1
		var best_distance := max_distance
		for slot in model.order.size():
			var d := pos.distance_to(_bottom_port(slot))
			if d < best_distance:
				best = slot
				best_distance = d
		return best

	func _gui_input(event: InputEvent) -> void:
		if model == null or testing:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_finish_drag(event.position)
		elif event is InputEventMouseMotion:
			if dragging_cable >= 0:
				drag_target = event.position
				empty_hover = event.position.distance_to(_bottom_port(model.empty_slot())) <= 70.0
				accept_event()
			else:
				var hover_slot := _slot_at(event.position, 48.0)
				if hover_slot >= 0:
					selected_slot = hover_slot
					queue_redraw()
		elif event is InputEventScreenTouch:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_finish_drag(event.position)
		elif event is InputEventScreenDrag and dragging_cable >= 0:
			drag_target = event.position
			empty_hover = event.position.distance_to(_bottom_port(model.empty_slot())) <= 78.0
			accept_event()
		elif event is InputEventKey and event.pressed and not event.echo:
			_handle_key(event)

	func _begin_drag(pos: Vector2) -> void:
		var slot := _slot_at(pos, 44.0)
		if slot < 0 or model.order[slot] == Model.EMPTY:
			return
		drag_from_slot = slot
		dragging_cable = model.order[slot]
		drag_target = pos
		drag_visual = _bottom_port(slot)
		drag_velocity = Vector2.ZERO
		drag_press_position = pos
		selected_slot = slot
		empty_hover = false
		grab_focus()
		accept_event()

	func _finish_drag(pos: Vector2) -> void:
		if dragging_cable < 0:
			return
		var target_slot := _slot_at(pos, 70.0)
		var source_slot := drag_from_slot
		var was_click := pos.distance_to(drag_press_position) <= 12.0
		dragging_cable = -1
		drag_from_slot = -1
		if (target_slot == model.empty_slot() and target_slot != source_slot) or was_click:
			move_requested.emit(source_slot)
			Input.vibrate_handheld(18)
		else:
			miss_t = 0.34
			Input.vibrate_handheld(35)
		empty_hover = false
		accept_event()

	func _handle_key(event: InputEventKey) -> void:
		match event.keycode:
			KEY_LEFT:
				selected_slot = wrapi(selected_slot - 1, 0, model.order.size())
			KEY_RIGHT:
				selected_slot = wrapi(selected_slot + 1, 0, model.order.size())
			KEY_ENTER, KEY_SPACE:
				if model.order[selected_slot] != Model.EMPTY:
					move_requested.emit(selected_slot)
			KEY_H:
				request_hint.emit()
			KEY_Z, KEY_BACKSPACE:
				request_undo.emit()
			KEY_R:
				request_reset.emit()
			KEY_T:
				request_test.emit()
			_:
				return
		accept_event()
		queue_redraw()

	var _font: Font = load("res://assets/fonts/Topaz_a500_ui.ttf")

	func _draw() -> void:
		if model == null:
			return
		var top_y := size.y * 0.31
		var bottom_y := size.y * 0.76
		# Rails besitzen Volumen, Kontaktschatten und Messingkante.
		for y in [top_y, bottom_y]:
			draw_rect(Rect2(size.x * 0.09 + 5, y - 23 + 7, size.x * 0.82, 46), Color(0, 0, 0, 0.34))
			draw_rect(Rect2(size.x * 0.09, y - 23, size.x * 0.82, 46), Color8(76, 72, 66))
			draw_rect(Rect2(size.x * 0.09, y - 23, size.x * 0.82, 46), Color8(163, 132, 82), false, 2)
		# Gummiseile: Schatten, dunkle Mantelkante, Farbe, Lichtsaum.
		for cable in model.layer_order:
			if cable >= ropes.size():
				continue
			var color := Color(str(model.cable_def(cable).get("color", "#ffffff")))
			var smooth := _smooth_rope(ropes[cable])
			var shadow := PackedVector2Array()
			for p in smooth:
				shadow.append(p + Vector2(4, 6))
			draw_polyline(shadow, Color(0, 0, 0, 0.38), 12.0, true)
			draw_polyline(smooth, color.darkened(0.48), 11.0, true)
			draw_polyline(smooth, color, 7.0, true)
			draw_polyline(smooth, color.lightened(0.42), 2.0, true)
		# Die Zonenbezeichnungen liegen bewusst vor den Kabeln: Sie bleiben auch
		# bei stark gekreuzten Startzuständen vollständig lesbar.
		draw_rect(Rect2(size.x * 0.085, top_y - 70.0, 205, 28), Color(0.02, 0.02, 0.018, 0.72))
		draw_string(_font, Vector2(size.x * 0.09, top_y - 51.0),
			"FESTE KABELAUSGÄNGE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color8(244, 190, 74))
		draw_rect(Rect2(size.x * 0.085, bottom_y - 68.0, 410, 28), Color(0.02, 0.02, 0.018, 0.76))
		draw_string(_font, Vector2(size.x * 0.09, bottom_y - 49.0),
			"ZIELBUCHSEN  ·  FARBE UND BUCHSTABE MÜSSEN PASSEN",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color8(244, 190, 74))
		# Zielbuchsen oben und feste, farb-/symbolcodierte Ziele unten. Der schwarze
		# Puffer ist ein echtes Ziel und muss am Ende wieder frei sein.
		for slot in model.cable_count:
			var def := model.cable_def(slot)
			var color := Color(str(def.get("color", "#ffffff")))
			_draw_socket(_top_port(slot), color, str(def.get("symbol", "?")), _font, false)
			draw_string(_font, _top_port(slot) + Vector2(-24, -25),
				str(def.get("name", "?")), HORIZONTAL_ALIGNMENT_CENTER, 48, 9,
				color.lightened(0.35))
		for slot in model.order.size():
			var cable_id := model.order[slot]
			var is_empty := cable_id == Model.EMPTY
			var target_id := model.target_order[slot]
			var target_def := model.cable_def(target_id)
			var target_color := Color8(26, 25, 23) if target_id == Model.EMPTY \
				else Color(str(target_def.get("color", "#ffffff"))).darkened(0.25)
			var target_symbol := "·" if target_id == Model.EMPTY else str(target_def.get("symbol", "?"))
			_draw_socket(_bottom_port(slot),
				Color8(27, 26, 24) if is_empty else target_color,
				"○" if is_empty else target_symbol, _font, true)
			if is_empty:
				var drop_radius := (31.0 if empty_hover else 24.0) + sin(_t * 4.0) * 1.5
				var drop_color := Color(0.35, 1.0, 0.65, 0.92) if empty_hover else Color(0.25, 0.95, 0.72, 0.66)
				draw_circle(_bottom_port(slot), drop_radius, drop_color, false, 3.0 if empty_hover else 2.0)
				var empty_label := ("FREI · PUFFER" if target_id == Model.EMPTY
					else "FREI → %s" % str(target_def.get("name", "?")))
				draw_string(_font, _bottom_port(slot) + Vector2(-38, 42), empty_label,
					HORIZONTAL_ALIGNMENT_CENTER, 76, 9, Color(0.55, 1.0, 0.78, 0.98))
			else:
				var cable_def := model.cable_def(cable_id)
				var plug_color := Color(str(cable_def.get("color", "#ffffff")))
				var plug_pos := drag_visual if cable_id == dragging_cable else _bottom_port(slot)
				_draw_plug(plug_pos, plug_color, str(cable_def.get("symbol", "?")), _font,
					slot == selected_slot or cable_id == dragging_cable)
				var correct := cable_id == target_id
				var target_label := "✓ RICHTIG" if correct \
					else ("ZIEL %s" % ("PUFFER" if target_id == Model.EMPTY else str(target_def.get("name", "?"))))
				draw_string(_font, _bottom_port(slot) + Vector2(-38, 42), target_label,
					HORIZONTAL_ALIGNMENT_CENTER, 76, 9,
					Color(0.48, 1.0, 0.62, 0.98) if correct else Color(1.0, 0.73, 0.30, 0.98))
			if hint_t > 0.0 and slot in [hint_pair.x, hint_pair.y]:
				draw_circle(_bottom_port(slot), 31.0 + sin(_t * 8.0) * 3.0, Color(1.0, 0.78, 0.22, 0.72), false, 4.0)
			if miss_t > 0.0 and slot == model.empty_slot():
				draw_circle(_bottom_port(slot) + Vector2(sin(_t * 70.0) * 4.0, 0),
					34.0, Color(1.0, 0.30, 0.25, miss_t * 1.8), false, 4.0)
		if testing:
			var sweep_x := lerpf(size.x * 0.12, size.x * 0.88, fmod(_t * 0.8, 1.0))
			draw_line(Vector2(sweep_x, top_y - 34), Vector2(sweep_x, bottom_y + 34), Color(0.35, 1.0, 0.58, 0.72), 3.0)

	func _draw_socket(pos: Vector2, color: Color, symbol: String, font: Font, target: bool) -> void:
		draw_circle(pos, 17.0, Color(0, 0, 0, 0.75))
		draw_circle(pos, 13.0, Color8(43, 42, 39))
		draw_circle(pos, 11.0, color, false, 3.0 if target else 2.0)
		draw_string(font, pos + Vector2(-4, 4), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	func _smooth_rope(points: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		if points.size() < 2:
			return points
		const SUBSTEPS := 4
		for i in points.size() - 1:
			var p0 := points[maxi(0, i - 1)]
			var p1 := points[i]
			var p2 := points[i + 1]
			var p3 := points[mini(points.size() - 1, i + 2)]
			for step in SUBSTEPS:
				var t := float(step) / SUBSTEPS
				var t2 := t * t
				var t3 := t2 * t
				out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
					+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
		out.append(points[-1])
		return out

	func _draw_plug(pos: Vector2, color: Color, symbol: String, font: Font, selected: bool) -> void:
		draw_circle(pos + Vector2(3, 4), 16.0, Color(0, 0, 0, 0.42))
		draw_circle(pos, 15.0, color.darkened(0.38))
		draw_circle(pos, 11.0, color)
		if selected:
			draw_circle(pos, 19.0, Color(1.0, 0.86, 0.35, 0.85), false, 3.0)
		draw_string(font, pos + Vector2(-4, 4), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


class BenchNearEdge:
	extends Control
	func _draw() -> void:
		draw_rect(Rect2(0, 5, size.x, size.y - 5), Color(0.035, 0.022, 0.012, 0.78))
		draw_rect(Rect2(0, 0, size.x, 7), Color(0.40, 0.23, 0.10, 0.78))
		draw_line(Vector2(0, 1), Vector2(size.x, 1), Color(0.82, 0.52, 0.24, 0.36), 2.0)
