class_name BbsCarrierMinigame
extends RetroWindow
## Analoges Carrier-Pult vor einem konkreten, noch nicht verbuchten Download.
##
## Die Leitung startet nicht mehr beim Oeffnen des Fensters. Der Spieler darf
## zuerst am stehenden Signal lernen, GAIN und FILTER an zwei grossen Reglern
## abstimmen und uebernimmt den Carrier anschliessend bewusst. Das bildet ein
## echtes Instrumenten-Spiel statt zweier nackter UI-Slider.

const Model := preload("res://scripts/minigames/bbs_carrier_model.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")

var file_entry: Dictionary = {}
var _model: BbsCarrierModel
var _scope: CarrierScope
var _gain: CarrierKnob
var _filter: CarrierKnob
var _status: Label
var _telemetry: Label
var _start_button: Button
var _retry_button: Button
var _hint_button: Button
var _integrity_bar: ProgressBar
var _transfer_bar: ProgressBar
var _running := false
var _finished := false
var _hint_flash := 0.0


func _init() -> void:
	title = Loc.t("ui.bbs_carrier_minigame.modem_line_lab_carrier_hold",
		"MODEM LINE LAB · CARRIER HOLD")
	win_size = Vector2(980, 680)


static func can_start(file: Dictionary) -> Dictionary:
	if file.is_empty():
		return {"ok": false, "reason": Loc.t(
			"ui.bbs_carrier_minigame.keine_datei_gewaehlt", "Keine Datei gewaehlt.")}
	if not BBSManager.connected():
		return {"ok": false, "reason": Loc.t(
			"ui.bbs_carrier_minigame.keine_bbs_verbindung", "Keine BBS-Verbindung.")}
	if DiskManager.blank_disks().is_empty():
		return {"ok": false, "reason": Loc.t(
			"ui.bbs_carrier_minigame.keine_leerdiskette_als_ziel",
			"Keine Leerdiskette als Ziel.")}
	return {"ok": true, "reason": ""}


func _ready() -> void:
	super._ready()
	set_process(true)
	var wins := int(MinigameManager.record("bbs_link").get("wins", 0))
	var baud := int(BBSManager.current_board.get("baud", 2400))
	var baud_level := 1 if baud <= 2400 else (3 if baud <= 9600 else 5)
	_model = Model.new()
	_model.configure(clampi(maxi(baud_level, 1 + floori(wins / 2.0)), 1, 5),
		hash("BBS/%s/%s/%d" % [BBSManager.current_board.get("id", ""),
			file_entry.get("content_title", ""), TimeManager.day_counter]))
	_build_ui()
	_sync_controls_from_model()
	_refresh()


func _build_ui() -> void:
	var briefing := HBoxContainer.new()
	briefing.name = "CarrierBriefing"
	briefing.custom_minimum_size.y = 30
	briefing.add_theme_constant_override("separation", 12)
	content.add_child(briefing)
	var objective := Bezel.dim_label(Loc.t(
		"ui.bbs_carrier_minigame.instrumente_abgleichen",
		"INSTRUMENTE ABGLEICHEN · MARGIN IM GRUENEN BAND HALTEN · DANN VERBINDUNG UEBERNEHMEN"), 11)
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	briefing.add_child(objective)
	var payload := Bezel.lcd_label(Loc.t("ui.bbs_carrier_minigame.s_d_kb", "%s · %d KB") % [
		str(file_entry.get("content_title", "DOWNLOAD")).to_upper(),
		int(file_entry.get("size_kb", 0))], Palette.LCD_AMBER, 10)
	payload.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	payload.custom_minimum_size.x = 220
	briefing.add_child(payload)

	var panel := HBoxContainer.new()
	panel.name = "CarrierPanel25D"
	panel.custom_minimum_size = Vector2(944, 500)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 10)
	content.add_child(panel)
	var rig := DepthRig.new()
	panel.add_child(rig)
	rig.configure(panel, 0.38)

	_scope = CarrierScope.new()
	_scope.name = "CarrierScope"
	_scope.model = _model
	_scope.custom_minimum_size = Vector2(642, 500)
	_scope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_scope)

	var controls := PanelContainer.new()
	controls.name = "LineControlRack"
	controls.custom_minimum_size = Vector2(292, 500)
	controls.add_theme_stylebox_override("panel", _rack_style())
	panel.add_child(controls)
	var rack := VBoxContainer.new()
	rack.add_theme_constant_override("separation", 8)
	controls.add_child(rack)

	var rack_title := Bezel.lcd_label(Loc.t("ui.bbs_carrier_minigame.line_control_v_32", "LINE CONTROL / V.32"), Palette.LCD_AMBER, 13)
	rack_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rack_title.custom_minimum_size.y = 25
	rack.add_child(rack_title)

	_telemetry = Bezel.lcd_label("", Palette.LCD_GREEN, 10)
	_telemetry.name = "CarrierTelemetry"
	_telemetry.custom_minimum_size.y = 76
	_telemetry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_telemetry.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_telemetry.add_theme_stylebox_override("normal", _display_style())
	rack.add_child(_telemetry)

	var knobs := HBoxContainer.new()
	knobs.name = "CarrierKnobs"
	knobs.add_theme_constant_override("separation", 8)
	knobs.alignment = BoxContainer.ALIGNMENT_CENTER
	rack.add_child(knobs)
	_gain = CarrierKnob.new()
	_gain.name = "GainKnob"
	_gain.configure(Loc.t("ui.bbs_carrier_minigame.rx_gain", "RX GAIN"),
		_model.gain, Palette.LCD_CYAN)
	_gain.tooltip_text = Loc.t("ui.bbs_carrier_minigame.rx_gain_ziehen_mausrad_oder_pfeiltasten", "RX GAIN · Ziehen, Mausrad oder Pfeiltasten")
	_gain.value_changed.connect(_on_gain_changed)
	knobs.add_child(_gain)
	_filter = CarrierKnob.new()
	_filter.name = "FilterKnob"
	_filter.configure(Loc.t("ui.bbs_carrier_minigame.noise_filter", "NOISE FILTER"),
		_model.filter, Palette.LCD_GREEN)
	_filter.tooltip_text = Loc.t("ui.bbs_carrier_minigame.noise_filter_ziehen_mausrad_oder_pfeiltasten", "NOISE FILTER · Ziehen, Mausrad oder Pfeiltasten")
	_filter.value_changed.connect(_on_filter_changed)
	knobs.add_child(_filter)

	var meter_label := Bezel.dim_label(Loc.t("ui.bbs_carrier_minigame.transfer_leitungsintegritaet", "TRANSFER / LEITUNGSINTEGRITAET"), 11)
	rack.add_child(meter_label)
	_transfer_bar = Bezel.bar(Palette.LCD_CYAN, Vector2(0, 12))
	_transfer_bar.name = "TransferProgress"
	rack.add_child(_transfer_bar)
	_integrity_bar = Bezel.bar(Palette.LCD_GREEN, Vector2(0, 12))
	_integrity_bar.name = "CarrierIntegrity"
	rack.add_child(_integrity_bar)

	_start_button = make_button(Loc.t("ui.bbs_carrier_minigame.verbindung_uebernehmen", "VERBINDUNG UEBERNEHMEN"), _start_transfer)
	_start_button.name = "CarrierStartButton"
	_start_button.custom_minimum_size = Vector2(0, 42)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rack.add_child(_start_button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	rack.add_child(actions)
	_retry_button = make_button(Loc.t("ui.bbs_carrier_minigame.retrain", "RETRAIN"), _retry)
	_retry_button.name = "CarrierRetryButton"
	_retry_button.custom_minimum_size = Vector2(0, 38)
	_retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry_button.disabled = true
	actions.add_child(_retry_button)
	_hint_button = make_button(Loc.t("ui.bbs_carrier_minigame.mess_tipp", "MESS-TIPP"), _hint)
	_hint_button.name = "CarrierHintButton"
	_hint_button.custom_minimum_size = Vector2(0, 38)
	_hint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_hint_button)

	var keyboard_help := Bezel.dim_label(
		Loc.t("ui.bbs_carrier_minigame.keyboard_help",
			"MAUS: REGLER ZIEHEN / RAD\nTASTATUR: TAB · PFEILE · ENTER START"), 9)
	keyboard_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keyboard_help.custom_minimum_size.y = 34
	rack.add_child(keyboard_help)

	_status = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_status.name = "CarrierStatus"
	_status.custom_minimum_size.y = 62
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_stylebox_override("normal", _status_style())
	content.add_child(_status)


func _process(delta: float) -> void:
	if _model == null or _finished:
		return
	_hint_flash = maxf(0.0, _hint_flash - delta)
	if _running and not _model.finished():
		_model.step(delta, _gain.value, _filter.value)
	_scope.running = _running
	_scope.hint_flash = _hint_flash
	_scope.queue_redraw()
	_refresh()
	if _running and _model.finished():
		_running = false
		_finish_run()


func _on_gain_changed(value: float) -> void:
	if _model == null:
		return
	_model.gain = value
	_note_manual_tune()


func _on_filter_changed(value: float) -> void:
	if _model == null:
		return
	_model.filter = value
	_note_manual_tune()


func _note_manual_tune() -> void:
	if _scope != null:
		_scope.queue_redraw()
	_refresh()


func _start_transfer() -> void:
	if _finished:
		return
	if _model.finished():
		_reset_run()
	var sample := _model.line_sample()
	if not bool(sample.safe):
		_hint_flash = 1.5
		_status.text = Loc.t("ui.bbs_carrier_minigame.noch_kein_lock_margin_ins_gruene", "NOCH KEIN LOCK · MARGIN INS GRUENE ZIELBAND DREHEN.")
		_status.add_theme_color_override("font_color", Palette.LCD_AMBER)
		_scope.queue_redraw()
		AudioManager.minigame_cue("bbs_link", &"error")
		return
	_running = true
	_start_button.disabled = true
	_start_button.text = Loc.t("ui.bbs_carrier_minigame.carrier_wird_gehalten", "CARRIER WIRD GEHALTEN")
	_retry_button.disabled = false
	AudioManager.modem_dial()
	AudioManager.minigame_cue("bbs_link", &"action")
	_refresh()


func _refresh() -> void:
	if _model == null or _status == null:
		return
	var sample := _model.line_sample()
	var margin := float(sample.margin)
	var margin_percent := roundi(margin * 100.0)
	var lock_text := Loc.t("ui.bbs_carrier_minigame.lock", "LOCK") if bool(sample.safe) else (
		Loc.t("ui.bbs_carrier_minigame.signal_too_weak", "SIGNAL ZU SCHWACH")
		if margin < 0.28 else Loc.t("ui.bbs_carrier_minigame.overdriven", "UEBERSTEUERT"))
	_telemetry.text = Loc.t("ui.bbs_carrier_minigame.s_s_nmargin_03d_s_nretry", "%s · %s\nMARGIN %+03d · %s\nRETRY %d · LEVEL %d") % [
		str(_model.protocol).to_upper(), str(_model.phase).to_upper(),
		margin_percent, lock_text, _model.retries, _model.level]
	_telemetry.add_theme_color_override("font_color",
		Palette.LCD_GREEN if bool(sample.safe) else Palette.LCD_AMBER)
	_transfer_bar.value = clampf(_model.elapsed / maxf(_model.duration, 0.01) * 100.0, 0.0, 100.0)
	_integrity_bar.value = clampf(_model.integrity * 100.0, 0.0, 100.0)

	if _model.finished() and not _model.success():
		_status.text = Loc.t("ui.bbs_carrier_minigame.no_carrier_transfer_nicht_gestartet_diskette",
			"NO CARRIER · Nichts verbraucht. Regler nachstellen und NEUER VERSUCH starten.")
		_status.add_theme_color_override("font_color", Palette.RED)
		_start_button.disabled = false
		_start_button.text = Loc.t("ui.bbs_carrier_minigame.neuer_versuch", "NEUER VERSUCH")
		_retry_button.disabled = true
		return
	if not _running:
		_status.text = (Loc.t("ui.bbs_carrier_minigame.lock_ready",
			"LOCK BEREIT · Regler reagieren sofort. Jetzt VERBINDUNG UEBERNEHMEN.")
			if bool(sample.safe) else Loc.t("ui.bbs_carrier_minigame.pretune",
			"VORABGLEICH · RX GAIN und NOISE FILTER drehen, bis MARGIN gruen leuchtet."))
		_status.add_theme_color_override("font_color",
			Palette.LCD_GREEN if bool(sample.safe) else Palette.LCD_AMBER)
		return
	_status.text = Loc.t("ui.bbs_carrier_minigame.s_s_s_daten_02d_integritaet", "%s · %s · %s · DATEN %02d%% · INTEGRITAET %02d%%") % [
		str(_model.protocol).to_upper(), str(_model.phase).to_upper(), lock_text,
		roundi(_model.elapsed / _model.duration * 100.0), roundi(_model.integrity * 100.0)]
	_status.add_theme_color_override("font_color",
		Palette.LCD_GREEN if bool(sample.safe) else Palette.RED)


func _retry() -> void:
	if _model.finished() and not _model.success():
		_reset_run()
		_status.text = Loc.t("ui.bbs_carrier_minigame.carrier_retrain_vorabgleich_wieder_bereit", "CARRIER RETRAIN · Vorabgleich wieder bereit.")
		AudioManager.modem_dial()
		return
	if not _running:
		return
	if _model.retry():
		AudioManager.modem_dial()
		_hint_flash = 0.65
		_refresh()


func _hint() -> void:
	if _model == null or _finished:
		return
	var hint := _model.hint()
	_gain.set_value(clampf(_gain.value + float(hint.gain_delta), 0.0, 1.0))
	_filter.set_value(clampf(_filter.value + float(hint.filter_delta), 0.0, 1.0))
	_hint_flash = 1.4
	var sample := _model.line_sample()
	_status.text = (Loc.t("ui.bbs_carrier_minigame.hint_locked",
		"MESS-TIPP · Lock steht. Kleine Korrekturen reichen.")
		if bool(sample.safe) else Loc.t("ui.bbs_carrier_minigame.hint_adjusted",
		"MESS-TIPP · Die Regler wurden einen Rastschritt in Richtung Lock bewegt."))
	_status.add_theme_color_override("font_color", Palette.LCD_AMBER)
	AudioManager.minigame_cue("bbs_link", &"hint")
	_scope.queue_redraw()


func _reset_run() -> void:
	var gain_value := _gain.value
	var filter_value := _filter.value
	_model.configure(_model.level, _model.run_seed)
	_model.gain = gain_value
	_model.filter = filter_value
	_running = false
	_sync_controls_from_model()
	_start_button.disabled = false
	_start_button.text = Loc.t("ui.bbs_carrier_minigame.verbindung_uebernehmen", "VERBINDUNG UEBERNEHMEN")
	_retry_button.disabled = true
	_refresh()


func _sync_controls_from_model() -> void:
	if _gain != null:
		_gain.set_value(_model.gain, false)
	if _filter != null:
		_filter.set_value(_model.filter, false)


func _finish_run() -> void:
	if _finished:
		return
	if not _model.success():
		_refresh()
		AudioManager.minigame_cue("bbs_link", &"error")
		return
	var result := BBSManager.download(file_entry)
	if not bool(result.get("ok", false)):
		_status.text = str(result.get("text", Loc.t("ui.bbs_carrier_minigame.transfer_not_recorded",
			"Transfer konnte nicht verbucht werden.")))
		_status.add_theme_color_override("font_color", Palette.RED)
		if _start_button != null:
			_start_button.disabled = false
		return
	_finished = true
	var score := _model.score()
	MinigameManager.finish("bbs_link", true, score, _model.details())
	_status.text = Loc.t("ui.bbs_carrier_minigame.transfer_complete_04d_punkte_s",
		"TRANSFER COMPLETE · %04d PUNKTE · %s") % [score, result.get("text", "")]
	_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	if _start_button != null:
		_start_button.text = Loc.t("ui.bbs_carrier_minigame.transfer_abgeschlossen", "TRANSFER ABGESCHLOSSEN")
		_start_button.disabled = true
	if _retry_button != null:
		_retry_button.disabled = true
	if _hint_button != null:
		_hint_button.disabled = true
	AudioManager.key_enter()
	UIManager.toast(str(result.text))


func _unhandled_key_input(event: InputEvent) -> void:
	super._unhandled_key_input(event)
	if event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if not _running and not _finished:
			_start_transfer()
			get_viewport().set_input_as_handled()


static func _rack_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(10, 15, 16)
	box.border_color = Color8(63, 92, 82)
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box


static func _display_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(0, 21, 14)
	box.border_color = Color8(31, 92, 65)
	box.set_border_width_all(2)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box


static func _status_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(4, 8, 10)
	box.border_color = Color8(42, 66, 70)
	box.set_border_width_all(2)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box


class CarrierKnob:
	extends Control
	signal value_changed(value: float)

	var label_text := "KNOB"
	var value := 0.5
	var accent := Color.WHITE
	var _dragging := false
	var _hot := false
	var _pulse := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(126, 158)
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hot = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hot = false; queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		set_process(true)

	func configure(next_label: String, next_value: float, next_accent: Color) -> void:
		label_text = next_label
		accent = next_accent
		set_value(next_value, false)

	func set_value(next_value: float, notify := true) -> void:
		var clamped := clampf(snappedf(next_value, 0.01), 0.0, 1.0)
		if is_equal_approx(value, clamped):
			return
		value = clamped
		_pulse = 1.0
		queue_redraw()
		if notify:
			value_changed.emit(value)

	func _process(delta: float) -> void:
		if _pulse <= 0.0:
			return
		_pulse = maxf(0.0, _pulse - delta * 3.5)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
				set_value(value + 0.03)
				accept_event()
			elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
				set_value(value - 0.03)
				accept_event()
			elif mouse.button_index == MOUSE_BUTTON_LEFT:
				_dragging = mouse.pressed
				if mouse.pressed:
					grab_focus()
				accept_event()
		elif event is InputEventMouseMotion and _dragging:
			var motion := event as InputEventMouseMotion
			set_value(value + (motion.relative.x - motion.relative.y) * 0.0045)
			accept_event()
		elif event is InputEventKey:
			var key := event as InputEventKey
			if not key.pressed or key.echo:
				return
			if key.keycode in [KEY_LEFT, KEY_DOWN, KEY_A, KEY_S]:
				set_value(value - (0.01 if key.shift_pressed else 0.03))
				accept_event()
			elif key.keycode in [KEY_RIGHT, KEY_UP, KEY_D, KEY_W]:
				set_value(value + (0.01 if key.shift_pressed else 0.03))
				accept_event()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var face := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		draw_rect(face, Color8(24, 27, 26), true)
		draw_rect(face, accent.darkened(0.55) if not (_hot or has_focus()) else accent,
			false, 2.0)
		draw_string(font, Vector2(0, 20), label_text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 11, Color8(220, 225, 212))
		var center := Vector2(size.x * 0.5, 82)
		var radius := minf(43.0, size.x * 0.36)
		var start := deg_to_rad(135.0)
		var sweep := deg_to_rad(270.0)
		for tick in 11:
			var tick_angle := start + sweep * float(tick) / 10.0
			var outer := center + Vector2.from_angle(tick_angle) * (radius + 9.0)
			var inner := center + Vector2.from_angle(tick_angle) * (radius + (3.0 if tick % 5 else 1.0))
			draw_line(inner, outer, accent if tick % 5 == 0 else Color8(118, 125, 116),
				2.0 if tick % 5 == 0 else 1.0)
		draw_circle(center + Vector2(2, 4), radius + 3, Color(0, 0, 0, 0.58))
		draw_circle(center, radius + 2, Color8(74, 76, 68))
		draw_circle(center, radius - 3, Color8(26, 29, 27))
		for ring in 4:
			draw_arc(center, radius - 7.0 - ring * 4.0, 0, TAU, 36,
				Color(0.35, 0.38, 0.34, 0.34), 1.0)
		var knob_angle := start + sweep * value
		var pointer := Vector2.from_angle(knob_angle)
		draw_line(center - pointer * 4.0, center + pointer * (radius - 8.0), accent, 4.0)
		draw_circle(center, 7.0, Color8(12, 14, 13))
		if _pulse > 0.0:
			draw_arc(center, radius + 5.0 + _pulse * 3.0, 0, TAU, 36,
				Color(accent, _pulse * 0.55), 2.0)
		var value_text := "%03d" % roundi(value * 100.0)
		draw_rect(Rect2(Vector2(30, 133), Vector2(size.x - 60, 19)), Color8(0, 18, 11), true)
		draw_string(font, Vector2(30, 147), value_text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x - 60, 11, accent)


class CarrierScope:
	extends Control
	const ART := preload("res://assets/minigames/BBS_CARRIER_LAB_V01.png")
	var model: BbsCarrierModel
	var running := false
	var hint_flash := 0.0

	func _draw() -> void:
		if model == null:
			return
		var source_size := ART.get_size()
		var source_height := source_size.x * size.y / size.x
		var source := Rect2(0, (source_size.y - source_height) * 0.40,
			source_size.x, source_height)
		draw_texture_rect_region(ART, Rect2(Vector2.ZERO, size), source)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.012, 0.26), true)

		var plot := Rect2(size.x * 0.055, size.y * 0.075, size.x * 0.69, size.y * 0.57)
		draw_rect(plot.grow(8), Color(0.015, 0.02, 0.018, 0.92), true)
		draw_rect(plot, Color(0.002, 0.035, 0.025, 0.94), true)
		draw_rect(plot, Color8(45, 130, 92), false, 2)
		for i in 11:
			var x := plot.position.x + plot.size.x * i / 10.0
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y),
				Color(0.25, 0.65, 0.5, 0.13))
		for i in 7:
			var y := plot.position.y + plot.size.y * i / 6.0
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y),
				Color(0.25, 0.65, 0.5, 0.13))

		var safe_top := plot.end.y - 0.62 * plot.size.y
		var safe_bottom := plot.end.y - 0.28 * plot.size.y
		var safe_color := Color(0.2, 0.95, 0.45, 0.16 + hint_flash * 0.12)
		draw_rect(Rect2(plot.position.x, safe_top, plot.size.x,
			safe_bottom - safe_top), safe_color, true)
		draw_line(Vector2(plot.position.x, safe_top), Vector2(plot.end.x, safe_top),
			Color(0.4, 1.0, 0.58, 0.7), 1.0)
		draw_line(Vector2(plot.position.x, safe_bottom), Vector2(plot.end.x, safe_bottom),
			Color(0.4, 1.0, 0.58, 0.7), 1.0)

		var signal_points := PackedVector2Array()
		var noise_points := PackedVector2Array()
		var margin_points := PackedVector2Array()
		for i in 150:
			var t := maxf(0.0, model.elapsed - 4.0) + i / 149.0 * 4.0
			var sample := model.line_sample(t)
			var x := plot.position.x + plot.size.x * i / 149.0
			signal_points.append(Vector2(x,
				plot.end.y - float(sample.signal) * plot.size.y))
			noise_points.append(Vector2(x,
				plot.end.y - float(sample.noise) * plot.size.y))
			margin_points.append(Vector2(x,
				plot.end.y - clampf(float(sample.margin), 0, 1) * plot.size.y))
		draw_polyline(signal_points, Color8(80, 205, 255), 2.0)
		draw_polyline(noise_points, Color8(255, 105, 75), 2.0)
		draw_polyline(margin_points, Color8(115, 255, 140), 3.0)

		var current := model.line_sample()
		var cursor_y := plot.end.y - clampf(float(current.margin), 0, 1) * plot.size.y
		draw_line(Vector2(plot.end.x - 12, cursor_y), Vector2(plot.end.x + 10, cursor_y),
			Color.WHITE, 3.0)
		draw_string(ThemeDB.fallback_font, plot.position + Vector2(10, 20),
			Loc.t("ui.bbs_carrier_minigame.scope_legend", "RX  /  NOISE  /  MARGIN"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color8(150, 235, 190))
		draw_string(ThemeDB.fallback_font,
			Vector2(plot.end.x - 168, safe_top + 17),
			Loc.t("ui.bbs_carrier_minigame.lock_target_band", "LOCK-ZIELBAND"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color8(125, 255, 150))

		_draw_vu(Rect2(size.x * 0.775, size.y * 0.10, size.x * 0.19, 92),
			Loc.t("ui.bbs_carrier_minigame.rx_level", "RX LEVEL"),
			float(current.signal), Palette.LCD_CYAN)
		_draw_vu(Rect2(size.x * 0.775, size.y * 0.35, size.x * 0.19, 92),
			Loc.t("ui.bbs_carrier_minigame.noise", "NOISE"),
			float(current.noise), Color8(255, 110, 76))

		var state_panel := Rect2(size.x * 0.055, size.y * 0.69,
			size.x * 0.91, size.y * 0.24)
		draw_rect(state_panel, Color(0.015, 0.02, 0.018, 0.92), true)
		draw_rect(state_panel, Color8(64, 88, 76), false, 2.0)
		var safe := bool(current.safe)
		var lamp_color := Palette.LCD_GREEN if safe else Palette.RED
		var pulse := 0.72 + sin(Time.get_ticks_msec() * 0.009) * 0.18 if running else 0.82
		draw_circle(state_panel.position + Vector2(28, 31), 9,
			Color(lamp_color, pulse))
		draw_string(ThemeDB.fallback_font, state_panel.position + Vector2(48, 36),
			Loc.t("ui.bbs_carrier_minigame.carrier_lock", "CARRIER LOCK") if safe else
			Loc.t("ui.bbs_carrier_minigame.search_tune", "SEARCH / TUNE"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, lamp_color)
		draw_string(ThemeDB.fallback_font, state_panel.position + Vector2(18, 70),
			(Loc.t("ui.bbs_carrier_minigame.line_active",
				"LEITUNG AKTIV · KURVEN BEOBACHTEN UND NACHREGELN") if running else
			Loc.t("ui.bbs_carrier_minigame.time_not_running",
				"VORABGLEICH · REGLER REAGIEREN, ZEIT LAEUFT NOCH NICHT")),
			HORIZONTAL_ALIGNMENT_LEFT, state_panel.size.x - 36, 11,
			Color8(205, 214, 198))
		for index in 8:
			var active := index <= floori(model.elapsed / maxf(model.duration, 0.01) * 7.0)
			var led := state_panel.position + Vector2(22 + index * 31, state_panel.size.y - 20)
			draw_rect(Rect2(led, Vector2(21, 6)),
				Color8(80, 225, 130) if active else Color8(29, 55, 42), true)

	func _draw_vu(rect: Rect2, label_text: String, value: float, color: Color) -> void:
		draw_rect(rect, Color(0.025, 0.03, 0.025, 0.92), true)
		draw_rect(rect, Color8(86, 82, 65), false, 2.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 17), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 9, Color8(210, 205, 180))
		var center := Vector2(rect.get_center().x, rect.end.y - 15)
		draw_arc(center, rect.size.x * 0.34, PI, TAU, 24, Color8(118, 112, 88), 2.0)
		for tick in 6:
			var angle := PI + PI * tick / 5.0
			var outer := center + Vector2.from_angle(angle) * rect.size.x * 0.34
			var inner := center + Vector2.from_angle(angle) * rect.size.x * 0.28
			draw_line(inner, outer, Color8(165, 158, 126), 1.0)
		var needle_angle := PI + PI * clampf(value, 0.0, 1.0)
		draw_line(center, center + Vector2.from_angle(needle_angle) * rect.size.x * 0.31,
			color, 2.5)
		draw_circle(center, 4.0, Color8(30, 29, 25))
