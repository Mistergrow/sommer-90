class_name MonitorTuneMinigame
extends RetroWindow
## Physische CRT-Kalibrierung: Regler und Testbild leben auf derselben
## interaktiven 2,5D-Ebene; Assistenz verbucht nie vor dem finalen Test.

const Model := preload("res://scripts/minigames/monitor_tune_model.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")
const ENERGY_COST := 4
const LABELS := {
	&"h_pos": "BILDLAGE X", &"v_pos": "BILDLAGE Y", &"brightness": "HELLIGKEIT",
	&"focus": "FOKUS", &"convergence": "KONVERGENZ",
}

var _model: MonitorTuneModel
var _screen: CrtTestScreen
var _status: Label
var _sliders: Dictionary = {}
var _finished := false


func _init() -> void:
	title = Loc.t("ui.monitor_tune_minigame.crt_service_monitor_einstellen", "CRT-SERVICE · MONITOR EINSTELLEN")
	win_size = Vector2(920, 690)


static func can_start() -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.monitor_tune_minigame.nur_waehrend_eines_laufenden_spiels_verfuegbar", "Nur waehrend eines laufenden Spiels verfuegbar.")}
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": Loc.t("ui.monitor_tune_minigame.den_eigenen_monitor_kannst_du_nur", "Den eigenen Monitor kannst du nur im Zimmer kalibrieren.")}
	if not UIManager.monitor_power:
		# Stromketten-Vertrag: eine stromlose Roehre zeigt kein Testbild.
		return {"ok": false, "reason": Loc.t("ui.monitor_tune_minigame.roehre_ist_stromlos_erst_den_monitor", "Die Roehre ist stromlos — erst den Monitor ans Netz (Verteiler + Netzschalter).")}
	if not bool(GameManager.flags.get("learned_monitor_calibration", false)):
		# Kalibrieren muss man erst gezeigt bekommen (Gruber oder ein Freund).
		return {"ok": false, "reason": Loc.t("ui.monitor_tune_minigame.testbild_einstellen_muss_dir_erst_jemand", "Das Testbild einstellen muss dir erst jemand zeigen — frag Herrn Gruber im Computerladen oder einen bastelnden Freund.")}
	if PlayerStats.energie < ENERGY_COST:
		return {"ok": false, "reason": Loc.t("ui.monitor_tune_minigame.zu_muede_fuer_crt_kalibrierung_d", "Zu muede fuer die CRT-Kalibrierung (%d Energie noetig).") % ENERGY_COST}
	return {"ok": true, "reason": ""}


func _ready() -> void:
	super._ready()
	var wins := int(MinigameManager.record("monitor_tune").get("wins", 0))
	_model = Model.new()
	_model.configure(clampi(1 + floori(wins / 2.0), 1, 4), hash("CRT/%d/%d" % [TimeManager.day_counter, wins]))
	_build_ui()


func _build_ui() -> void:
	var intro := Bezel.dim_label(Loc.t("ui.monitor_tune_minigame.smpte_testkarte_lesen_geometrie_pegel_strahlenbuendel", "SMPTE-Testkarte lesen · Geometrie, Pegel und Strahlenbuendel sauber abgleichen · kein Zeitlimit."), 11)
	content.add_child(intro)
	content.add_child(Bezel.lcd_label(MonitorProfile.summary(), Palette.LCD_GREEN, 10))
	var board := HBoxContainer.new()
	board.name = "InteractiveCrtBoard"
	board.custom_minimum_size = Vector2(884, 535)
	board.add_theme_constant_override("separation", 16)
	content.add_child(board)
	var rig := DepthRig.new()
	board.add_child(rig)
	rig.configure(board, 0.72)

	_screen = CrtTestScreen.new()
	_screen.model = _model
	_screen.configure_monitor(MonitorProfile.active_model_id())
	_screen.custom_minimum_size = Vector2(610, 530)
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_child(_screen)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(252, 0)
	controls.add_theme_constant_override("separation", 5)
	board.add_child(controls)
	for key: StringName in Model.PARAMS:
		var label := Bezel.lcd_label(str(LABELS[key]), Palette.LCD_AMBER, 10)
		controls.add_child(label)
		var slider := HSlider.new()
		slider.name = str(key)
		slider.min_value = -1.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = float(_model.values[key])
		slider.custom_minimum_size = Vector2(240, 28)
		slider.tooltip_text = Loc.t("ui.monitor_tune_minigame.s_pfeiltasten_fuer_feineinstellung", "%s · Pfeiltasten fuer Feineinstellung") % LABELS[key]
		slider.value_changed.connect(_on_value.bind(key))
		controls.add_child(slider)
		_sliders[key] = slider
	controls.add_child(HSeparator.new())
	controls.add_child(make_button(Loc.t("ui.monitor_tune_minigame.hinweis_schwaechster_regler", "HINWEIS: SCHWAECHSTER REGLER"), _hint))
	controls.add_child(make_button(Loc.t("ui.monitor_tune_minigame.service_automatik_punkteabzug", "SERVICE-AUTOMATIK (PUNKTEABZUG)"), _auto))
	var test := make_button(Loc.t("ui.monitor_tune_minigame.testlauf_uebernehmen", "▶ TESTLAUF / UEBERNEHMEN"), _test)
	test.custom_minimum_size = Vector2(0, 42)
	controls.add_child(test)
	_status = Bezel.lcd_label(Loc.t("ui.monitor_tune_minigame.s_dh_0_d_kreise_level", "%s · %dh · 0/%d KREISE · LEVEL %d") % [str(_model.profile).to_upper(),_model.age_hours,Model.PARAMS.size(), _model.level], Palette.LCD_GREEN, 10)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 48)
	controls.add_child(_status)


func _on_value(value: float, key: StringName) -> void:
	if _finished: return
	_model.set_value(key, value)
	_refresh()
	AudioManager.ui_click()


func _refresh() -> void:
	_screen.queue_redraw()
	_status.text = Loc.t("ui.monitor_tune_minigame.d_d_kreise_verriegelt_mittlerer_fehler", "%d/%d KREISE VERRIEGELT · MITTLERER FEHLER %02d%%") % [
		_model.locked_count(), Model.PARAMS.size(), roundi(_model.total_error() * 100.0)]


func _sync_sliders() -> void:
	for key: StringName in Model.PARAMS:
		(_sliders[key] as HSlider).set_value_no_signal(float(_model.values[key]))
	_refresh()


func _hint() -> void:
	if _finished: return
	var key := _model.apply_hint()
	_sync_sliders()
	_status.text = Loc.t("ui.monitor_tune_minigame.s_wurde_mit_dem_oszilloskop_verriegelt", "%s wurde mit dem Oszilloskop verriegelt.") % LABELS[key]


func _auto() -> void:
	if _finished: return
	_model.auto_calibrate()
	_sync_sliders()
	_status.text = Loc.t("ui.monitor_tune_minigame.service_automatik_bereit_testlauf_bestaetigt_werte", "SERVICE-AUTOMATIK bereit · Testlauf bestaetigt die Werte.")


func _test() -> void:
	if _finished: return
	if not _model.is_calibrated():
		var key := _model.worst_parameter()
		_status.text = Loc.t("ui.monitor_tune_minigame.nicht_bestanden_s_liegt_ausserhalb_toleranz", "NICHT BESTANDEN · %s liegt ausserhalb der Toleranz.") % LABELS[key]
		_screen.flash_error = 1.0
		_screen.queue_redraw()
		AudioManager.floppy_rattle()
		return
	_commit_success(_model.score())


func _commit_success(score: int) -> bool:
	if _finished or _model == null or not _model.is_calibrated() or not PlayerStats.use_energy(ENERGY_COST):
		return false
	_finished = true
	var details := _model.details(); details["energy"] = ENERGY_COST
	MinigameManager.finish("monitor_tune", true, score, details)
	GameManager.flags["monitor_calibrated"] = true
	GameManager.flags["monitor_tune_last"] = details
	if _status != null:
		_status.text = Loc.t("ui.monitor_tune_minigame.bestanden_04d_punkte_testbild_rastet_sauber", "BESTANDEN · %04d PUNKTE · TESTBILD RASTET SAUBER EIN") % score
		_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	if _screen != null:
		_screen.success = true
		_screen.queue_redraw()
	AudioManager.key_enter()
	UIManager.toast(Loc.t("ui.monitor_tune_minigame.monitor_sauber_kalibriert_d_punkte", "Monitor sauber kalibriert — %d Punkte.") % score)
	return true


class CrtTestScreen:
	extends Control
	const Profile := preload("res://scripts/ui/monitor_profile.gd")
	var model: MonitorTuneModel
	var success := false
	var flash_error := 0.0
	var monitor_model := "commodore_1084s"
	var monitor_profile: Dictionary = {}
	var monitor_art: Texture2D = null

	func configure_monitor(model_id: String) -> void:
		monitor_model = model_id
		monitor_profile = Profile.profile_for_model(model_id)
		var path := Profile.asset_path(model_id)
		monitor_art = null
		if not path.is_empty():
			monitor_art = load(path) as Texture2D
		queue_redraw()

	func _process(delta: float) -> void:
		if flash_error > 0.0:
			flash_error = maxf(0.0, flash_error - delta * 2.5)
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _draw() -> void:
		if model == null: return
		var outer := Rect2(8, 8, size.x - 16, size.y - 16)
		# Das frontale V2-Masterasset liefert Gehaeuse, Woelbung, Lautsprecher und
		# Bedientasten. Die Live-Testkarte sitzt ausschliesslich in seiner Roehre.
		if monitor_art != null:
			draw_texture_rect(monitor_art, outer, false)
		else:
			draw_rect(outer, Color8(205, 198, 177), true)
		var frac: Array = monitor_profile.get("screen_frac", [0.105, 0.145, 0.79, 0.605])
		var glass := Rect2(
			outer.position + Vector2(outer.size.x * float(frac[0]), outer.size.y * float(frac[1])),
			Vector2(outer.size.x * float(frac[2]), outer.size.y * float(frac[3])))
		draw_rect(glass, Color8(5, 10, 12), true)
		var dx := float(model.values.h_pos) * 28.0
		var dy := float(model.values.v_pos) * 20.0
		var base_inner: Rect2 = glass.grow(-18)
		var inner := Rect2(base_inner.position + Vector2(dx, dy), base_inner.size)
		var bright := clampf(0.48 + float(model.values.brightness) * 0.28, 0.12, 0.9)
		var base := Color(0.08, 0.11, 0.10).lerp(Color(0.55, 0.60, 0.52), bright)
		draw_rect(inner, base, true)
		var conv := float(model.values.convergence) * 8.0
		var focus := absf(float(model.values.focus) - float(model.target.focus))
		var width := 1.0 + focus * 7.0
		for color_value: Color in [Color(1, 0.18, 0.18, 0.72), Color(0.2, 1, 0.35, 0.72), Color(0.2, 0.5, 1, 0.72)]:
			var off: float = (color_value.r - color_value.b) * conv
			var inset: Rect2 = inner.grow(-30)
			draw_rect(Rect2(inset.position + Vector2(off, 0), inset.size), color_value, false, width)
		for i in 9:
			var x: float = inner.position.x + inner.size.x * float(i) / 8.0
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0.04, 0.06, 0.05, 0.65), 1.0)
		for i in 7:
			var y: float = inner.position.y + inner.size.y * float(i) / 6.0
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0.04, 0.06, 0.05, 0.65), 1.0)
		var center: Vector2 = inner.get_center()
		draw_circle(center, minf(inner.size.x, inner.size.y) * 0.25, Color.WHITE, false, width)
		draw_line(Vector2(center.x, inner.position.y), Vector2(center.x, inner.end.y), Color.WHITE, width)
		draw_line(Vector2(inner.position.x, center.y), Vector2(inner.end.x, center.y), Color.WHITE, width)
		var quality_data: Dictionary = monitor_profile.get("quality", {})
		var scan_step := 5 if int(quality_data.get("tier", 1)) >= 3 else 3
		for y in range(int(glass.position.y), int(glass.end.y), scan_step):
			draw_line(Vector2(glass.position.x, y), Vector2(glass.end.x, y), Color(0, 0, 0, 0.13), 1.0)
		if success: draw_rect(glass, Color(0.2, 1.0, 0.55, 0.10), true)
		if flash_error > 0.0: draw_rect(glass, Color(1.0, 0.12, 0.08, flash_error * 0.16), true)
		draw_string(ThemeDB.fallback_font, glass.position + Vector2(12, 20), "CRT SERVICE · CROSSHATCH / COLOR ALIGN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color8(220, 235, 215))
