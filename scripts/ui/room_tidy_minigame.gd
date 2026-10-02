class_name RoomTidyMinigame
extends RetroWindow
## AAA-/Mobile-Drag-and-drop-Aufraeumen im echten Zimmer. Das Fenster arbeitet
## auf einem UID-Snapshot; RoomManager wird erst nach der letzten bestandenen
## Welle atomar veraendert. Schliessen/Abbrechen ist deshalb immer neutral.

const Model := preload("res://scripts/minigames/room_tidy_model.gd")
const ROOM_MASTER := preload("res://assets/backgrounds/layers/ROOM_MASTER_1992_V01.png")
const PROP_SHEET := preload("res://assets/ui/minigames/ROOM_TIDY_PROPS_SHEET_V01.png")
const COLA := preload("res://assets/backgrounds/layers/DRINK_GENERIC_COLA_CAN_1990_V01.png")
const ICE := preload("res://assets/backgrounds/layers/ICE_ICE_CREAM_WRAPPER_GENERIC_V01.png")
const LocationDepth := preload("res://scripts/gfx/location_stage_25d.gd")
const ENERGY_COST := 5

var _level := 1
var _wave := 0
var _waves: Array[Array] = []
var _minimum_items := 6
var _model: RoomTidyModel
var _scores: Array[int] = []
var _details: Array[Dictionary] = []
var _snapshot_uids: Array[int] = []
var _finished := false
var _transitioning := false
var _stage: TidyStage
var _round_label: Label
var _quality_label: Label
var _instruction: Label


func _init() -> void:
	title = Loc.t("ui.room_tidy_minigame.zimmer_aufraeumen_ordnung_mit_system", "ZIMMER AUFRAEUMEN · ORDNUNG MIT SYSTEM")
	win_size = Vector2(1080, 760)


static func can_start() -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.room_tidy_minigame.nur_waehrend_eines_laufenden_spiels_verfuegbar", "Nur waehrend eines laufenden Spiels verfuegbar.")}
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": Loc.t("ui.room_tidy_minigame.aufraeumen_kannst_du_nur_im_eigenen", "Aufraeumen kannst du nur im eigenen Zimmer.")}
	if RoomManager.litter_count() <= 0:
		return {"ok": false, "reason": Loc.t("ui.room_tidy_minigame.zimmer_ist_bereits_ordentlich", "Das Zimmer ist bereits ordentlich.")}
	if PlayerStats.energie < ENERGY_COST:
		return {"ok": false, "reason": "Zum gruendlichen Aufraeumen fehlen %d Energie." % ENERGY_COST}
	return {"ok": true, "reason": ""}


func _ready() -> void:
	super._ready()
	var gate := can_start()
	if not bool(gate.get("ok", false)):
		UIManager.toast(str(gate.get("reason", "Aufraeumen gerade nicht moeglich.")))
		queue_free()
		return
	var wins := int(MinigameManager.record("room_tidy").get("wins", 0))
	_level = 1 if wins == 0 else (2 if wins < 3 else (3 if wins < 6 else 4))
	_minimum_items = [6, 8, 10, 12][_level - 1]
	_build_waves(RoomManager.litter.duplicate(true))
	_build_shell()
	_begin_wave()


func _build_waves(world_items: Array) -> void:
	_waves = []
	_snapshot_uids = []
	for item in world_items:
		if item is Dictionary:
			_snapshot_uids.append(int(item.get("uid", 0)))
	var per_wave: int = [6, 8, 10, 12][_level - 1]
	var cursor := 0
	while cursor < world_items.size():
		var wave: Array = []
		for i in range(cursor, mini(cursor + per_wave, world_items.size())):
			wave.append(world_items[i].duplicate(true))
		_waves.append(wave)
		cursor += per_wave


func _build_shell() -> void:
	var intro := Bezel.dim_label(
		Loc.t("ui.room_tidy_minigame.alles_hat_seinen_platz_muell_trennen", "Alles hat seinen Platz: Muell trennen, Kassetten und Disketten ins Regal, Kleidung zur Waesche. Kein Zeitlimit."), 11)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)
	var telemetry := HBoxContainer.new()
	_round_label = Bezel.lcd_label("", Palette.LCD_AMBER, 11)
	_round_label.custom_minimum_size = Vector2(430, 22)
	telemetry.add_child(_round_label)
	_quality_label = Bezel.lcd_label("", Palette.LCD_CYAN, 11)
	_quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	telemetry.add_child(_quality_label)
	content.add_child(telemetry)
	_stage = TidyStage.new()
	_stage.custom_minimum_size = Vector2(1044, 525)
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.drop_attempted.connect(_on_drop_attempted)
	_stage.wave_complete.connect(_accept_wave)
	_stage.request_hint.connect(_hint)
	_stage.request_undo.connect(_undo)
	_stage.request_reset.connect(_reset_wave)
	content.add_child(_stage)
	_instruction = Bezel.dim_label("", 11)
	_instruction.custom_minimum_size = Vector2(0, 32)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_instruction)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 7)
	footer.add_child(make_button(Loc.t("ui.room_tidy_minigame.undo", "↶ UNDO"), _undo))
	footer.add_child(make_button(Loc.t("ui.room_tidy_minigame.neu_verteilen", "NEU VERTEILEN"), _reset_wave))
	footer.add_child(make_button(Loc.t("ui.room_tidy_minigame.hinweis", "HINWEIS"), _hint))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var energy := Bezel.lcd_label(Loc.t("ui.room_tidy_minigame.abschluss_d_energie_0_dm", "ABSCHLUSS: %d ENERGIE · 0 DM") % ENERGY_COST, Palette.LCD_GREEN, 11)
	footer.add_child(energy)
	content.add_child(footer)


func _begin_wave() -> void:
	_model = Model.new()
	var round_seed := int(hash("TIDY/%d/%d/%d/%d" % [TimeManager.day_counter, _level, _wave, _snapshot_uids.size()]))
	_model.configure(_waves[_wave], _minimum_items, round_seed, _level)
	_stage.set_model(_model)
	_transitioning = false
	_round_label.text = Loc.t("ui.room_tidy_minigame.s_level_d_korb_d_d", "%s · LEVEL %d · KORB %d/%d · %d TEILE") % [str(_model.room_scenario).to_upper(),
		_level, _wave + 1, _waves.size(), _model.items.size()]
	_instruction.text = Loc.t("ui.room_tidy_minigame.ziehe_jedes_teil_in_markierte_zone", "Ziehe jedes Teil in die markierte Zone. Falsche Ablagen springen zurueck; Schliessen veraendert das Zimmer nicht.")
	_refresh()


func _refresh() -> void:
	if _model == null:
		return
	_quality_label.text = Loc.t("ui.room_tidy_minigame.rest_02d_fehler_02d_kombo_x", "REST %02d  ·  FEHLER %02d  ·  KOMBO x%d  ·  %04d") % [
		_model.remaining(), _model.mistakes, _model.combo, _model.score()]
	_quality_label.add_theme_color_override("font_color",
		Palette.LCD_GREEN if _model.is_complete() else Palette.LCD_CYAN)
	_stage.board.queue_redraw()


func _on_drop_attempted(item_index: int, target: String, result: Dictionary) -> void:
	if _finished or _transitioning:
		return
	var item: Dictionary = _model.items[item_index]
	if bool(result.get("ok", false)):
		var combo := int(result.get("combo", 1))
		_instruction.text = Loc.t("ui.room_tidy_minigame.s_sitzt_richtig_in_s_s", "%s sitzt richtig in %s.%s") % [str(item["name"]),
			str(_model.target_def(target)["name"]), "  KOMBO x%d!" % combo if combo >= 3 else ""]
	else:
		var wanted := str(result.get("wanted", item.get("target", "bin")))
		_instruction.text = Loc.t("ui.room_tidy_minigame.s_gehoert_zu_s_es_federt", "%s gehoert zu %s — es federt sicher an seinen Platz zurueck.") % [
			str(item["name"]), str(_model.target_def(wanted)["name"])]
	_refresh()


func _hint() -> void:
	if _finished or _transitioning:
		return
	var index := _model.use_hint()
	if index < 0:
		return
	_stage.board.show_hint(index)
	var item: Dictionary = _model.items[index]
	_instruction.text = Loc.t("ui.room_tidy_minigame.tipp_s_leuchtet_zusammen_mit_s", "Tipp: %s leuchtet zusammen mit %s auf. Der Hinweis kostet nur Rekordpunkte.") % [
		str(item["name"]), str(_model.target_def(str(item["target"]))["name"])]
	AudioManager.ui_click()
	_refresh()


func _undo() -> void:
	if _finished or _transitioning:
		return
	var index := _model.undo()
	if index >= 0:
		_stage.board.restore_item(index)
		_instruction.text = Loc.t("ui.room_tidy_minigame.zuletzt_einsortierte_teil_liegt_wieder_auf", "Das zuletzt einsortierte Teil liegt wieder auf dem Tisch.")
		AudioManager.relay()
		_refresh()


func _reset_wave() -> void:
	if _finished or _transitioning:
		return
	_model.reset_placements()
	_stage.board.reset_layout()
	_instruction.text = Loc.t("ui.room_tidy_minigame.teile_wurden_neu_verteilt_fehler_hilfskosten", "Die Teile wurden neu verteilt. Fehler- und Hilfskosten bleiben fair in der Wertung.")
	_refresh()


func _accept_wave() -> void:
	if _finished or _transitioning or _model == null or not _model.is_complete():
		return
	_transitioning = true
	_scores.append(_model.score())
	_details.append(_model.details())
	AudioManager.play("continuity_ok")
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree() or _finished:
		return
	if _wave < _waves.size() - 1:
		_wave += 1
		_begin_wave()
		_instruction.text = Loc.t("ui.room_tidy_minigame.korb_geschafft_naechste_stapel_kommt_auf", "Korb geschafft. Der naechste Stapel kommt auf den Tisch.")
	else:
		_complete()


func _average_score() -> int:
	var total := 0
	for value in _scores:
		total += value
	return int(round(float(total) / maxf(1.0, _scores.size())))


func _complete() -> void:
	# Atomare Revalidierung: Wurde der Weltzustand nebenbei veraendert, wird weder
	# Energie noch Rekord verbucht. Ein erneuter Start baut einen frischen Snapshot.
	var current_uids: Array[int] = []
	for item in RoomManager.litter:
		current_uids.append(int(item.get("uid", 0)))
	for uid in _snapshot_uids:
		if not uid in current_uids:
			_transitioning = false
			_instruction.text = Loc.t("ui.room_tidy_minigame.zimmerzustand_hat_sich_geaendert_bitte_neu", "Der Zimmerzustand hat sich geaendert. Bitte neu oeffnen — nichts wurde verbucht.")
			UIManager.toast(Loc.t("ui.room_tidy_minigame.aufraeumen_abgebrochen_zimmerzustand_wurde_zwischenzeitlich_veraendert", "Aufraeumen abgebrochen: Zimmerzustand wurde zwischenzeitlich veraendert."))
			return
	if not PlayerStats.use_energy(ENERGY_COST):
		_transitioning = false
		_instruction.text = Loc.t("ui.room_tidy_minigame.zu_erschoepft_fuer_den_abschluss_zimmer", "Zu erschoepft fuer den Abschluss. Das Zimmer blieb unveraendert.")
		return
	RoomManager.tidy(_snapshot_uids)
	var score := _average_score()
	var stars := 3 if score >= 850 else (2 if score >= 620 else 1)
	var details := {
		"level": _level, "waves": _details.duplicate(true), "wave_scores": _scores.duplicate(),
		"cleaned_uids": _snapshot_uids.duplicate(), "cleaned": _snapshot_uids.size(), "stars": stars,
	}
	_finished = true
	MinigameManager.finish("room_tidy", true, score, details)
	GameManager.flags["room_tidy_last"] = details.duplicate(true)
	MemoryManager.record("alltag", "das Zimmer mit System aufgeraeumt")
	_stage.celebrate = true
	_stage.board.celebrate = true
	_stage.board.queue_redraw()
	_round_label.text = Loc.t("ui.room_tidy_minigame.zimmer_tipptopp_s", "ZIMMER TIPPTOPP  ·  %s") % "★".repeat(stars)
	_quality_label.text = Loc.t("ui.room_tidy_minigame.04d_punkte_sauberkeit_d", "%04d PUNKTE  ·  SAUBERKEIT %d%%") % [score, RoomManager.cleanliness()]
	_quality_label.add_theme_color_override("font_color", Palette.LCD_GREEN)
	_instruction.text = Loc.t("ui.room_tidy_minigame.d_echte_gegenstaende_weggeraeumt_kein_geld", "%d echte Gegenstaende weggeraeumt. Kein Geld, kein Farmen: nur Ordnung, Rekord und ein glaubwuerdiger Raumzustand.") % _snapshot_uids.size()
	AudioManager.play("bag", 0.0)
	Input.vibrate_handheld(55)


class TidyStage:
	extends Control
	signal drop_attempted(item_index: int, target: String, result: Dictionary)
	signal wave_complete
	signal request_hint
	signal request_undo
	signal request_reset

	var board: TidyBoard
	var _depth: Control
	var _board_base := Vector2.ZERO
	var celebrate := false

	func _ready() -> void:
		clip_contents = true
		var bg := TextureRect.new()
		bg.name = "EmptyRoomMaster"
		bg.texture = ROOM_MASTER
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		_depth = LocationDepth.new()
		_depth.configure(self, bg, "ROOM_TIDY_STAGE", {
			"horizon": 0.34, "strength": 0.0085, "far_gain": 0.18, "near_gain": 0.76,
			"vertical_gain": 0.32, "overscan": 0.024, "pointer": 0.68, "idle": 0.045,
		})
		add_child(_depth)
		board = TidyBoard.new()
		board.name = "InteractiveTidyBoard"
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.z_index = 3
		board.drop_attempted.connect(func(i: int, target: String, result: Dictionary) -> void:
			drop_attempted.emit(i, target, result))
		board.wave_complete.connect(func() -> void: wave_complete.emit())
		board.request_hint.connect(func() -> void: request_hint.emit())
		board.request_undo.connect(func() -> void: request_undo.emit())
		board.request_reset.connect(func() -> void: request_reset.emit())
		add_child(board)
		_board_base = board.position
		var near := RoomNearEdge.new()
		near.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		near.offset_top = -22
		near.z_index = 6
		near.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(near)

	func set_model(value: RoomTidyModel) -> void:
		if board == null:
			await ready
		board.set_model(value)

	func _process(_delta: float) -> void:
		if board == null or _depth == null:
			return
		var gain := 1.0 if bool(SettingsManager.value("location_depth")) else 0.0
		board.position = _board_base + Vector2(_depth.look.x * 7.0, _depth.look.y * 3.0) * gain


class TidyBoard:
	extends Control
	signal drop_attempted(item_index: int, target: String, result: Dictionary)
	signal wave_complete
	signal request_hint
	signal request_undo
	signal request_reset

	const REGIONS := {
		"chips": Rect2(0, 0, 512, 512), "sock": Rect2(512, 0, 512, 512),
		"tshirt": Rect2(1024, 0, 512, 512), "cassette": Rect2(0, 512, 512, 512),
		"floppy": Rect2(512, 512, 512, 512), "paper": Rect2(1024, 512, 512, 512),
	}
	const VISUAL_SIZES := {
		"chips": Vector2(112, 94), "sock": Vector2(72, 112), "tshirt": Vector2(132, 104),
		"cassette": Vector2(108, 82), "floppy": Vector2(86, 86), "paper": Vector2(90, 88),
		"cola": Vector2(54, 92), "ice": Vector2(110, 56),
	}

	var model: RoomTidyModel
	var positions: Array[Vector2] = []
	var starts: Array[Vector2] = []
	var desired: Array[Vector2] = []
	var velocities: Array[Vector2] = []
	var rotations: Array[float] = []
	var target_rotations: Array[float] = []
	var scales: Array[float] = []
	var dragging := -1
	var drag_offset := Vector2.ZERO
	var hover_target := ""
	var selected := 0
	var hint_item := -1
	var hint_t := 0.0
	var miss_target := ""
	var miss_t := 0.0
	var pop_t := 0.0
	var celebrate := false
	var _t := 0.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		set_process(true)

	func set_model(value: RoomTidyModel) -> void:
		model = value
		reset_layout(false)

	func reset_layout(count_reset := true) -> void:
		if model == null:
			return
		positions = []
		starts = []
		desired = []
		velocities = []
		rotations = []
		target_rotations = []
		scales = []
		var columns := 6
		var rng := RandomNumberGenerator.new()
		rng.seed = model.run_seed + (model.resets * 101 if count_reset else 0)
		for i in model.items.size():
			var col := i % columns
			var row := floori(float(i) / columns)
			var p := Vector2(lerpf(size.x * 0.26, size.x * 0.74, float(col) / 5.0),
				size.y * (0.59 + row * 0.12))
			p += Vector2(rng.randf_range(-12, 12), rng.randf_range(-7, 7))
			positions.append(p)
			starts.append(p)
			desired.append(p)
			velocities.append(Vector2.ZERO)
			var angle := rng.randf_range(-0.14, 0.14)
			rotations.append(angle)
			target_rotations.append(angle)
			scales.append(1.0)
		dragging = -1
		hover_target = ""
		selected = _next_unplaced(-1, 1)
		queue_redraw()

	func restore_item(index: int) -> void:
		if index < 0 or index >= starts.size():
			return
		desired[index] = starts[index]
		target_rotations[index] = 0.0
		scales[index] = 1.0
		selected = index
		queue_redraw()

	func show_hint(index: int) -> void:
		hint_item = index
		hint_t = 1.8
		selected = index
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		hint_t = maxf(0.0, hint_t - delta)
		miss_t = maxf(0.0, miss_t - delta)
		pop_t = maxf(0.0, pop_t - delta)
		if model == null or positions.size() != model.items.size():
			return
		for i in positions.size():
			if i == dragging:
				continue
			var force := (desired[i] - positions[i]) * 78.0
			velocities[i] = (velocities[i] + force * delta) * exp(-delta * 12.0)
			positions[i] += velocities[i] * delta
			rotations[i] = lerpf(rotations[i], target_rotations[i], 1.0 - exp(-delta * 9.0))
		queue_redraw()

	func _zone_rect(id: String) -> Rect2:
		match id:
			"shelf": return Rect2(size.x * 0.025, size.y * 0.18, size.x * 0.16, size.y * 0.43)
			"laundry": return Rect2(size.x * 0.835, size.y * 0.64, size.x * 0.14, size.y * 0.24)
			"recycling": return Rect2(size.x * 0.255, size.y * 0.76, size.x * 0.14, size.y * 0.17)
			_: return Rect2(size.x * 0.62, size.y * 0.76, size.x * 0.14, size.y * 0.17)

	func _zone_at(pos: Vector2) -> String:
		for id in ["shelf", "laundry", "recycling", "bin"]:
			if _zone_rect(id).grow(12.0).has_point(pos):
				return id
		return ""

	func _placed_position(index: int, target: String) -> Vector2:
		var r := _zone_rect(target).grow(-12.0)
		var col := index % 3
		var row := floori(float(index) / 3.0) % 2
		return r.position + Vector2(r.size.x * (0.25 + col * 0.25), r.size.y * (0.35 + row * 0.32))

	func _gui_input(event: InputEvent) -> void:
		if model == null or model.is_complete():
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_finish_drag(event.position)
		elif event is InputEventMouseMotion and dragging >= 0:
			_drag_to(event.position)
		elif event is InputEventScreenTouch:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_finish_drag(event.position)
		elif event is InputEventScreenDrag and dragging >= 0:
			_drag_to(event.position)
		elif event is InputEventKey and event.pressed and not event.echo:
			_handle_key(event)

	func _begin_drag(pos: Vector2) -> void:
		var index := _item_at(pos)
		if index < 0:
			return
		dragging = index
		selected = index
		drag_offset = positions[index] - pos
		velocities[index] = Vector2.ZERO
		scales[index] = 1.10
		grab_focus()
		AudioManager.play("joystick_click", 0.08)
		Input.vibrate_handheld(12)
		accept_event()

	func _drag_to(pos: Vector2) -> void:
		positions[dragging] = pos + drag_offset
		desired[dragging] = positions[dragging]
		rotations[dragging] = lerpf(rotations[dragging], 0.0, 0.28)
		hover_target = _zone_at(pos)
		accept_event()

	func _finish_drag(pos: Vector2) -> void:
		if dragging < 0:
			return
		var index := dragging
		var target := _zone_at(pos)
		dragging = -1
		scales[index] = 1.0
		hover_target = ""
		if target == "":
			desired[index] = starts[index]
			miss_t = 0.30
			Input.vibrate_handheld(28)
			accept_event()
			return
		var result := model.attempt_drop(index, target)
		if bool(result.get("ok", false)):
			desired[index] = _placed_position(index, target)
			target_rotations[index] = 0.0
			scales[index] = 0.58
			pop_t = 0.35
			AudioManager.play("floppy_insert", 0.08)
			Input.vibrate_handheld(18)
			selected = _next_unplaced(index, 1)
		else:
			desired[index] = starts[index]
			miss_target = target
			miss_t = 0.42
			AudioManager.relay()
			Input.vibrate_handheld(38)
		drop_attempted.emit(index, target, result)
		if bool(result.get("complete", false)):
			wave_complete.emit()
		accept_event()

	func _item_at(pos: Vector2) -> int:
		for i in range(model.items.size() - 1, -1, -1):
			if bool(model.items[i].get("placed", false)):
				continue
			var visual := str(model.items[i].get("visual", "paper"))
			var half: Vector2 = Vector2(VISUAL_SIZES.get(visual, Vector2(88, 88))) * 0.55
			if Rect2(positions[i] - half, half * 2.0).grow(14.0).has_point(pos):
				return i
		return -1

	func _handle_key(event: InputEventKey) -> void:
		match event.keycode:
			KEY_TAB, KEY_RIGHT, KEY_DOWN:
				selected = _next_unplaced(selected, 1)
			KEY_LEFT, KEY_UP:
				selected = _next_unplaced(selected, -1)
			KEY_1, KEY_M:
				_keyboard_drop("bin")
			KEY_2, KEY_R:
				_keyboard_drop("recycling")
			KEY_3, KEY_S:
				_keyboard_drop("shelf")
			KEY_4, KEY_W:
				_keyboard_drop("laundry")
			KEY_H:
				request_hint.emit()
			KEY_Z, KEY_BACKSPACE:
				request_undo.emit()
			KEY_N:
				request_reset.emit()
			_:
				return
		accept_event()
		queue_redraw()

	func _keyboard_drop(target: String) -> void:
		if selected < 0 or selected >= model.items.size() or bool(model.items[selected].get("placed", false)):
			return
		var index := selected
		var result := model.attempt_drop(index, target)
		if bool(result.get("ok", false)):
			desired[index] = _placed_position(index, target)
			scales[index] = 0.58
			selected = _next_unplaced(index, 1)
			Input.vibrate_handheld(18)
		else:
			miss_target = target
			miss_t = 0.42
			Input.vibrate_handheld(38)
		drop_attempted.emit(index, target, result)
		if bool(result.get("complete", false)):
			wave_complete.emit()

	func _next_unplaced(from: int, direction: int) -> int:
		if model == null or model.items.is_empty():
			return -1
		for step in range(1, model.items.size() + 1):
			var index := wrapi(from + step * direction, 0, model.items.size())
			if not bool(model.items[index].get("placed", false)):
				return index
		return -1

	var _font: Font = load("res://assets/fonts/Topaz_a500_ui.ttf")

	func _draw() -> void:
		if model == null:
			return
		for id in ["shelf", "laundry", "recycling", "bin"]:
			_draw_zone(id, _font)
		for i in model.items.size():
			if i == dragging:
				continue
			_draw_item(i, _font)
		if dragging >= 0:
			_draw_item(dragging, _font)
		if celebrate:
			for i in 18:
				var angle := _t * (0.8 + (i % 3) * 0.2) + i * TAU / 18.0
				var radius := 36.0 + fmod(_t * 95.0 + i * 17.0, 210.0)
				var p := size * 0.5 + Vector2(cos(angle), sin(angle) * 0.55) * radius
				draw_circle(p, 3.0 + i % 3, [Palette.LCD_GREEN, Palette.LCD_AMBER, Palette.LCD_CYAN][i % 3])
		draw_string(_font, Vector2(size.x * 0.22, size.y * 0.975),
			"TOUCH/MAUS ZIEHEN  ·  1 MUELL  2 WERTSTOFF  3 REGAL  4 WAESCHE  ·  H TIPP  ·  Z UNDO",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color8(236, 221, 190))

	func _draw_zone(id: String, font: Font) -> void:
		var r := _zone_rect(id)
		var def := model.target_def(id)
		var color := Color(str(def.get("color", "#ffffff")))
		var active := hover_target == id
		var pulse := 0.0
		if hint_t > 0.0 and hint_item >= 0 and str(model.items[hint_item]["target"]) == id:
			pulse = 0.5 + sin(_t * 9.0) * 0.25
		var fill := color
		fill.a = (0.075 if id == "shelf" else 0.20) + (0.17 if active else 0.0) + pulse * 0.18
		if id == "shelf":
			# Das echte Regal bleibt sichtbar; Materialkante und Boeden markieren
			# seine grosszuegige Touchflaeche ohne eine flache Debugmaske.
			draw_rect(r, fill)
			draw_rect(r, color.lightened(0.30), false, 4.0 if active else 2.0)
			for y in [0.28, 0.55, 0.82]:
				draw_line(Vector2(r.position.x + 7, r.position.y + r.size.y * y),
					Vector2(r.end.x - 7, r.position.y + r.size.y * y), Color(color, 0.38), 2.0)
		else:
			# Trapezfoermiger Korb mit Lippe, Innenraum und Rippen: lesbares
			# Volumen statt eines UI-Rechtecks auf dem Foto.
			var body := PackedVector2Array([
				r.position + Vector2(r.size.x * 0.10, r.size.y * 0.14),
				r.position + Vector2(r.size.x * 0.90, r.size.y * 0.14),
				r.position + Vector2(r.size.x * 0.82, r.size.y * 0.94),
				r.position + Vector2(r.size.x * 0.18, r.size.y * 0.94),
			])
			draw_colored_polygon(body, Color(0, 0, 0, 0.40))
			draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]),
				color.lightened(0.18), 4.0 if active else 2.5, true)
			draw_rect(Rect2(r.position + Vector2(2, 3), Vector2(r.size.x - 4, r.size.y * 0.20)), Color(0, 0, 0, 0.52))
			draw_rect(Rect2(r.position + Vector2(2, 3), Vector2(r.size.x - 4, r.size.y * 0.20)),
				color.lightened(0.32), false, 3.0)
			for x in [0.30, 0.50, 0.70]:
				draw_line(Vector2(lerpf(body[3].x, body[2].x, x), body[3].y - 4),
					Vector2(lerpf(body[0].x, body[1].x, x), body[0].y + 9), Color(color, 0.32), 2.0)
		var label := "%s  [%s]" % [str(def["name"]), str(def["symbol"])]
		draw_string(font, r.position + Vector2(9, 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		if miss_t > 0.0 and miss_target == id:
			draw_rect(r.grow(5.0 + sin(_t * 65.0) * 3.0), Color(1.0, 0.25, 0.20, miss_t), false, 5.0)

	func _draw_item(index: int, font: Font) -> void:
		if index < 0 or index >= positions.size():
			return
		var item: Dictionary = model.items[index]
		var visual := str(item.get("visual", "paper"))
		var base_size: Vector2 = VISUAL_SIZES.get(visual, Vector2(88, 88))
		var item_scale := scales[index]
		if index == hint_item and hint_t > 0.0:
			item_scale *= 1.0 + sin(_t * 10.0) * 0.06
		if index == dragging:
			item_scale *= 1.06
		var rect := Rect2(-base_size * 0.5 * item_scale, base_size * item_scale)
		draw_set_transform(positions[index], rotations[index], Vector2.ONE)
		var shadow_rect := Rect2(rect.position + Vector2(5, 7), rect.size)
		_draw_visual(visual, shadow_rect, Color(0, 0, 0, 0.40))
		_draw_visual(visual, rect, Color.WHITE)
		if index == selected and not bool(item.get("placed", false)):
			draw_rect(rect.grow(5.0), Color(1.0, 0.84, 0.30, 0.82), false, 3.0)
		if index == hint_item and hint_t > 0.0:
			var target_color := Color(str(model.target_def(str(item["target"]))["color"]))
			draw_circle(Vector2.ZERO, maxf(base_size.x, base_size.y) * 0.58, target_color, false, 4.0)
		if index == dragging:
			draw_string(font, Vector2(-base_size.x * 0.5, -base_size.y * 0.62), str(item["name"]),
				HORIZONTAL_ALIGNMENT_CENTER, base_size.x, 10, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_visual(visual: String, rect: Rect2, tint: Color) -> void:
		if visual == "cola":
			draw_texture_rect(COLA, rect, false, tint)
		elif visual == "ice":
			draw_texture_rect(ICE, rect, false, tint)
		else:
			draw_texture_rect_region(PROP_SHEET, rect, REGIONS.get(visual, REGIONS["paper"]), tint)


class RoomNearEdge:
	extends Control
	func _draw() -> void:
		draw_rect(Rect2(0, 5, size.x, size.y - 5), Color(0.035, 0.020, 0.010, 0.80))
		draw_rect(Rect2(0, 0, size.x, 7), Color(0.40, 0.22, 0.09, 0.82))
		draw_line(Vector2(0, 1), Vector2(size.x, 1), Color(0.88, 0.57, 0.28, 0.38), 2.0)
