class_name TrackerPatternMinigame
extends RetroWindow
## Acht-Step-Tracker als echtes Creator-Spiel: Pattern setzen, laufend hoeren,
## musikalisch pruefen und erst danach dauerhaft in der MOD-Sammlung sichern.

const Model := preload("res://scripts/minigames/tracker_pattern_model.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const PatternAudio := preload("res://scripts/audio/tracker_pattern_audio.gd")
const ENERGY_COST := 4
const TRACK_NAMES := ["KICK  BD", "SNARE SD", "HI-HAT HH", "BASS  BA"]

var _model: TrackerPatternModel
var _grid: PatternGrid
var _status: Label
var _play_button: Button
var _pattern_label: Label
var _audio: TrackerPatternAudio
var _finished := false


func _init() -> void:
	title = Loc.t("ui.tracker_pattern_minigame.tracker_labor_eigenes_8_step_pattern", "TRACKER-LABOR · EIGENES 8-STEP-PATTERN")
	win_size = Vector2(960, 700)


static func can_start() -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("ui.tracker_pattern_minigame.nur_waehrend_eines_laufenden_spiels_verfuegbar", "Nur waehrend eines laufenden Spiels verfuegbar.")}
	if GameManager.current_location_id != "room":
		return {"ok": false, "reason": "Tracker-Patterns entstehen am eigenen Amiga im Zimmer."}
	if not PlayerStats.has_program("protracker") and not PlayerStats.has_program("noisetracker_homage"):
		return {"ok": false, "reason": Loc.t("ui.tracker_pattern_minigame.dafuer_brauchst_du_pro_tracker_oder", "Dafuer brauchst du PRO-TRACKER oder Krach-Tracker.")}
	if PlayerStats.energie < ENERGY_COST:
		return {"ok": false, "reason": Loc.t("ui.tracker_pattern_minigame.zu_muede_fuer_konzentrierte_tracker_session", "Zu muede fuer eine konzentrierte Tracker-Session (%d Energie noetig).") % ENERGY_COST}
	return {"ok": true, "reason": ""}


func _ready() -> void:
	super._ready()
	var wins := int(MinigameManager.record("tracker_pattern").get("wins", 0))
	_model = Model.new()
	_model.configure(clampi(1 + floori(wins / 2.0), 1, 4), hash("PATTERN/%d/%d" % [TimeManager.day_counter, wins]))
	_audio = PatternAudio.new()
	add_child(_audio)
	_build_ui()


func _build_ui() -> void:
	var header := HBoxContainer.new()
	var intro := Bezel.dim_label(Loc.t("ui.tracker_pattern_minigame.vier_kanaele_acht_steps_space_spielt", "Vier Kanaele · acht Steps · Space spielt/stoppt · Pfeile navigieren · Enter setzt Event."), 11)
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(intro)
	_pattern_label = Bezel.lcd_label(Loc.t("ui.tracker_pattern_minigame.pat_00_01", "PAT 00/01"), Palette.LCD_GREEN, 10); header.add_child(_pattern_label)
	header.add_child(Bezel.lcd_label(Loc.t("ui.tracker_pattern_minigame.125_bpm_level_d", "125 BPM · LEVEL %d") % _model.level, Palette.LCD_AMBER, 11))
	content.add_child(header)

	var workbench := PanelContainer.new()
	workbench.name = "TrackerCrtWorkbench"
	workbench.custom_minimum_size = Vector2(924, 470)
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(31, 36, 48)
	style.border_color = Color8(112, 104, 82)
	style.set_border_width_all(8)
	style.set_corner_radius_all(14)
	workbench.add_theme_stylebox_override("panel", style)
	content.add_child(workbench)
	var rig := DepthRig.new()
	workbench.add_child(rig)
	rig.configure(workbench, 0.48)

	_grid = PatternGrid.new()
	_grid.model = _model
	_grid.audio = _audio
	_grid.track_names = TRACK_NAMES
	_grid.cell_toggled.connect(_on_cell)
	_grid.play_changed.connect(_on_play_changed)
	_grid.focus_mode = Control.FOCUS_ALL
	workbench.add_child(_grid)

	_status = Bezel.lcd_label(Loc.t("ui.tracker_pattern_minigame.pattern_leer_setze_zuerst_kick_snare", "Pattern leer · setze zuerst Kick, Snare, Hi-Hat und Bass."), Palette.LCD_GREEN, 11)
	_status.custom_minimum_size = Vector2(0, 32)
	content.add_child(_status)
	var footer := VBoxContainer.new()
	var toolbar:=HBoxContainer.new();toolbar.add_theme_constant_override("separation",7);footer.add_child(toolbar)
	_play_button = make_button(Loc.t("ui.tracker_pattern_minigame.abspielen", "▶ ABSPIELEN"), _toggle_play)
	toolbar.add_child(_play_button);toolbar.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.hinweis", "HINWEIS"), _hint));toolbar.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.pat", "PAT −"), _pattern_delta.bind(-1)));toolbar.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.pat_2672", "PAT +"), _pattern_delta.bind(1)));toolbar.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.neues_pat", "NEUES PAT"), _new_pattern));toolbar.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.sample", "SAMPLE"), _cycle_sample));toolbar.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.fx", "FX"), _cycle_effect))
	if not MinigameManager.latest_creation("tracker").is_empty(): toolbar.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.letztes_laden", "LETZTES LADEN"), _load_last))
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",7);footer.add_child(actions);actions.add_child(make_button(Loc.t("ui.tracker_pattern_minigame.demo_pattern_punkteabzug", "DEMO-PATTERN (PUNKTEABZUG)"), _demo))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	var save := make_button(Loc.t("ui.tracker_pattern_minigame.pruefen_als_mod_idee_sichern", "■ PRUEFEN & ALS MOD-IDEE SICHERN"), _save)
	save.custom_minimum_size = Vector2(280, 40)
	actions.add_child(save)
	content.add_child(footer)
	_grid.grab_focus.call_deferred()
	_refresh_pattern_header()

func _pattern_delta(delta: int) -> void:
	if _model.select_pattern(posmod(_model.current_pattern + delta, _model.patterns.size())):
		_refresh_pattern_header(); _grid.queue_redraw()
func _new_pattern() -> void:
	if _model.add_pattern(true): _refresh_pattern_header(); _grid.queue_redraw(); _status.text=Loc.t("ui.tracker_pattern_minigame.pattern_dupliziert_orderliste_erweitert", "Pattern dupliziert · Orderliste erweitert.")
	else: _status.text=Loc.t("ui.tracker_pattern_minigame.maximal_vier_patterns_in_diesem_modul", "Maximal vier Patterns in diesem Modul.")
func _cycle_sample() -> void:
	var track := _grid.cursor.x
	var sample_name := _model.cycle_sample(track)
	_audio.trigger(track, sample_name, _model.effects[track], _grid.cursor.y, true)
	_status.text=Loc.t("ui.tracker_pattern_minigame.kanal_d_sample_s_vorhoeren_aktiv", "Kanal %d Sample: %s · Vorhoeren aktiv")%[track+1,str(sample_name).to_upper()]
func _cycle_effect() -> void:
	var track := _grid.cursor.x
	var fx := _model.cycle_effect(track)
	_audio.trigger(track, _model.samples[track], fx, _grid.cursor.y, true)
	_status.text=Loc.t("ui.tracker_pattern_minigame.kanal_d_effekt_02x_vorhoeren_aktiv", "Kanal %d Effekt: %02X · Vorhoeren aktiv")%[track+1,fx]
func _load_last() -> void:
	var last := MinigameManager.latest_creation("tracker")
	if _model.load_snapshot(last.get("song", {})):_refresh_pattern_header();_grid.queue_redraw();_status.text=Loc.t("ui.tracker_pattern_minigame.gespeicherten_song_zur_weiterbearbeitung_geladen", "Gespeicherten Song zur Weiterbearbeitung geladen.")
func _refresh_pattern_header() -> void:
	if _pattern_label:_pattern_label.text=Loc.t("ui.tracker_pattern_minigame.pat_02d_02d_ord_s", "PAT %02d/%02d · ORD %s")%[_model.current_pattern,_model.patterns.size(),str(_model.order)]


func _on_cell(track: int, step: int) -> void:
	if _finished: return
	_model.toggle(track, step)
	_grid.queue_redraw()
	_status.text = Loc.t("ui.tracker_pattern_minigame.s_step_d_s_d_events", "%s Step %d %s · %d Events") % [TRACK_NAMES[track], step + 1,
		("gesetzt" if _model.active(track, step) else "geloescht"), int(_model.evaluation().events)]
	if _model.active(track, step):
		_audio.trigger(track, _model.samples[track], _model.effects[track], step, true)
	else:
		AudioManager.key_click()


func _toggle_play() -> void:
	_grid.set_playback(not _grid.playing)


func _on_play_changed(playing: bool) -> void:
	_play_button.text = Loc.t("ui.tracker_pattern_minigame.stopp", "■ STOPP") if playing \
		else Loc.t("ui.tracker_pattern_minigame.play", "▶ ABSPIELEN")
	_status.text = Loc.t("ui.tracker_pattern_minigame.pattern_laeuft_bei_125_bpm_kanalpegel", "Pattern laeuft bei 125 BPM — Kanalpegel und Playhead lesen.") if playing \
		else Loc.t("ui.tracker_pattern_minigame.playback_stopped", "Wiedergabe gestoppt.")


func _hint() -> void:
	if _finished: return
	var cell := _model.apply_hint()
	_grid.cursor = cell if cell.x >= 0 else _grid.cursor
	_grid.queue_redraw()
	_status.text = Loc.t("ui.tracker_pattern_minigame.hinweis_setzt_s_auf_step_d", "Hinweis setzt %s auf Step %d. Du kannst das Event weiter variieren.") % [TRACK_NAMES[cell.x], cell.y + 1] if cell.x >= 0 \
		else Loc.t("ui.tracker_pattern_minigame.base_ready", "Grundstruktur steht — variiere sparsam.")


func _demo() -> void:
	if _finished: return
	_model.load_demo()
	_grid.queue_redraw()
	_status.text = Loc.t("ui.tracker_pattern_minigame.demo_groove_geladen_veraendere_ihn_oder", "Demo-Groove geladen. Veraendere ihn oder sichere ihn mit Assistenzabzug.")


func _save() -> void:
	if _finished: return
	var result := _model.evaluation()
	if not bool(result.valid):
		var faults: Array = result.faults
		_status.text = Loc.t("ui.tracker_pattern_minigame.check", "CHECK: ") + (
			str(faults[0]) if not faults.is_empty()
			else Loc.t("ui.tracker_pattern_minigame.pattern_incomplete", "Pattern unvollstaendig."))
		_grid.error_flash = 1.0
		AudioManager.floppy_rattle()
		return
	_commit_success(_model.score())


func _commit_success(score: int) -> bool:
	if _finished or _model == null or not bool(_model.evaluation().valid) or not PlayerStats.use_energy(ENERGY_COST):
		return false
	_finished = true
	if _grid != null:
		_grid.set_playback(false)
	var pattern_name := "PATTERN %02d-%02d" % [TimeManager.month, (TimeManager.day_counter % 99) + 1]
	var details := {"level": _model.level, "events": int(_model.evaluation().events),
		"syncopation": _model.syncopation(), "hints": _model.hints,
		"assisted": _model.assisted, "signature": _model.signature(), "song_signature":_model.song_signature(), "patterns":_model.patterns.size(), "energy": ENERGY_COST}
	MinigameManager.save_creation("tracker", {"id": "pattern_%d" % TimeManager.day_counter,
		"title": pattern_name, "pattern": _model.signature(), "song":_model.snapshot(), "score": score, "bpm": 125})
	MinigameManager.finish("tracker_pattern", true, score, details)
	GameManager.flags["tracker_pattern_saved"] = true
	GameManager.flags["tracker_pattern_last"] = details
	if _status != null:
		_status.text = Loc.t("ui.tracker_pattern_minigame.gespeichert_s_04d_punkte", "GESPEICHERT · %s · %04d PUNKTE") % [pattern_name, score]
		_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	if _grid != null:
		_grid.success = true
		_grid.queue_redraw()
	AudioManager.key_enter()
	UIManager.toast(Loc.t("ui.tracker_pattern_minigame.eigenes_tracker_pattern_gesichert_d_punkte", "Eigenes Tracker-Pattern gesichert — %d Punkte.") % score)
	return true


class PatternGrid:
	extends Control
	signal cell_toggled(track: int, step: int)
	signal play_changed(playing: bool)

	var model: TrackerPatternModel
	var audio: TrackerPatternAudio
	var track_names: Array = []
	var cursor := Vector2i(0, 0)
	var playing := false
	var playhead := 0
	var error_flash := 0.0
	var success := false
	var _accum := 0.0
	var _channel_levels := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	const STEP_SECONDS := 60.0 / 125.0 / 2.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(true)

	func _process(delta: float) -> void:
		var meters_active := false
		for track in _channel_levels.size():
			_channel_levels[track] = maxf(0.0, _channel_levels[track] - delta * 3.8)
			meters_active = meters_active or _channel_levels[track] > 0.001
		if playing:
			_accum += delta
			while _accum >= STEP_SECONDS:
				_accum -= STEP_SECONDS
				playhead = (playhead + 1) % Model.STEPS
				_trigger_step(playhead)
			meters_active = true
		if error_flash > 0.0:
			error_flash = maxf(0.0, error_flash - delta * 2.2)
			meters_active = true
		if meters_active:
			queue_redraw()

	func set_playback(enabled: bool) -> void:
		if playing == enabled:
			return
		playing = enabled
		_accum = 0.0
		if playing:
			# Ein Tracker beginnt auf Row 00. Die alte Version wartete erst einen
			# Tick und uebersprang dadurch gerade den wichtigen Downbeat.
			playhead = 0
			_trigger_step(playhead)
		elif audio != null:
			audio.stop_all()
		play_changed.emit(playing)
		queue_redraw()

	func _trigger_step(step: int) -> void:
		if model == null or audio == null:
			return
		for track in Model.TRACKS.size():
			if model.active(track, step):
				audio.trigger(track, model.samples[track], model.effects[track], step)
				_channel_levels[track] = 1.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var c := _cell_at(event.position)
			if c.x >= 0:
				cursor = c
				cell_toggled.emit(c.x, c.y)
				accept_event()
		elif event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_LEFT: cursor.y = posmod(cursor.y - 1, Model.STEPS)
				KEY_RIGHT: cursor.y = posmod(cursor.y + 1, Model.STEPS)
				KEY_UP: cursor.x = posmod(cursor.x - 1, Model.TRACKS.size())
				KEY_DOWN: cursor.x = posmod(cursor.x + 1, Model.TRACKS.size())
				KEY_ENTER, KEY_KP_ENTER: cell_toggled.emit(cursor.x, cursor.y)
				KEY_SPACE:
					set_playback(not playing)
				_: return
			queue_redraw()
			accept_event()

	func _layout() -> Dictionary:
		return {"origin": Vector2(178, 94), "cell": Vector2((size.x - 215) / 8.0, 72.0)}

	func _cell_at(p: Vector2) -> Vector2i:
		var l := _layout()
		var local := p - Vector2(l.origin)
		if local.x < 0 or local.y < 0: return Vector2i(-1, -1)
		var step := floori(local.x / float(l.cell.x))
		var track := floori(local.y / float(l.cell.y))
		return Vector2i(track, step) if track < 4 and step < 8 else Vector2i(-1, -1)

	func _draw() -> void:
		if model == null: return
		draw_rect(Rect2(12, 12, size.x - 24, size.y - 24), Color8(7, 16, 23), true)
		draw_rect(Rect2(22, 24, size.x - 44, 48), Color8(18, 52, 64), true)
		draw_string(ThemeDB.fallback_font, Vector2(38, 55), "P-8 TRACKER | POS %02d PAT %02d LEN 08 BPM 125"%[playhead,model.current_pattern], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color8(126, 246, 218))
		var l := _layout()
		for step in Model.STEPS:
			var x := float(l.origin.x) + step * float(l.cell.x)
			draw_string(ThemeDB.fallback_font, Vector2(x + 20, 88), "%02X" % step, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color8(150, 190, 190))
		for track in Model.TRACKS.size():
			var y := float(l.origin.y) + track * float(l.cell.y)
			draw_string(ThemeDB.fallback_font, Vector2(38, y + 32), str(track_names[track]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color8(235, 218, 126))
			draw_string(ThemeDB.fallback_font, Vector2(38, y + 50), "%s  FX%02X"%[str(model.samples[track]).left(9),model.effects[track]], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color8(130,190,185))
			draw_rect(Rect2(38, y + 57, 104, 4), Color8(15, 32, 38), true)
			draw_rect(Rect2(38, y + 57, 104.0 * _channel_levels[track], 4),
				[Color8(244, 104, 72), Color8(100, 196, 244), Color8(240, 213, 92), Color8(154, 235, 126)][track], true)
			for step in Model.STEPS:
				var r := Rect2(float(l.origin.x) + step * float(l.cell.x) + 4, y + 5, float(l.cell.x) - 8, float(l.cell.y) - 10)
				var on := model.active(track, step)
				var col: Color = [Color8(244, 104, 72), Color8(100, 196, 244), Color8(240, 213, 92), Color8(154, 235, 126)][track]
				draw_rect(r, col if on else Color8(19, 39, 48), true)
				draw_rect(r, Color8(180, 225, 220) if cursor == Vector2i(track, step) else Color8(50, 88, 94), false, 3.0 if cursor == Vector2i(track, step) else 1.0)
				draw_string(ThemeDB.fallback_font, r.position + Vector2(12, 34), ("%s%02X" % [str(Model.TRACKS[track]).left(2).to_upper(), step] if on else "---"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color8(8, 18, 22) if on else Color8(80, 112, 116))
		if playing:
			var px := float(l.origin.x) + playhead * float(l.cell.x)
			draw_rect(Rect2(px + 1, float(l.origin.y), 3, float(l.cell.y) * 4), Color(0.5, 1.0, 0.7, 0.8), true)
		for y in range(15, int(size.y - 15), 3): draw_line(Vector2(15, y), Vector2(size.x - 15, y), Color(0, 0, 0, 0.10), 1.0)
		if error_flash > 0.0: draw_rect(Rect2(14, 14, size.x - 28, size.y - 28), Color(1, 0.1, 0.08, error_flash * 0.12), true)
		if success: draw_rect(Rect2(14, 14, size.x - 28, size.y - 28), Color(0.2, 1, 0.55, 0.08), true)
