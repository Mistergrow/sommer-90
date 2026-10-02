class_name YearTransitionScreen
extends Control
## Vollbild-Silvestersequenz zwischen zwei Kampagnenjahren.
##
## WICHTIG: Dieses UI veraendert TimeManager absichtlich NICHT. Der aufrufende
## Kampagnenkalender zeigt erst den Bildschirm und committed den Jahreswechsel
## im `finished`-Signal. So koennen Lieferungen, Rechnungen und Questfolgen
## atomar nach der bestaetigten Sequenz verarbeitet werden.

signal finished(from_year: int, to_year: int, animation_skipped: bool)
signal stage_changed(stage: StringName)
signal audio_cue(cue: StringName)

enum Stage { COUNTDOWN, REVEAL, REVIEW, COMPLETE }

const COUNTDOWN_SECONDS := 3.45
const REVEAL_SECONDS := 1.45
const FINAL_REVEAL_SECONDS := 2.15
const ERA_COPPER := &"copper"
const ERA_NETWORK := &"network"
const ERA_WEB := &"web"
const ERA_MILLENNIUM := &"millennium"

var from_year := 1990
var to_year := 1991
var review: Dictionary = {}
var auto_close := true
var auto_audio := true

var _stage := Stage.COUNTDOWN
var _elapsed := 0.0
var _skipped := false
var _settings_node: Node = null   # lazy — _draw läuft jeden Frame
var _reduced_motion_override: Variant = null
var _reduced_motion := false
var _last_count := 4
var _complete_guard := false

var _kicker: Label
var _countdown: Label
var _old_year: Label
var _arrow: Label
var _new_year: Label
var _era_label: Label
var _review_panel: PanelContainer
var _review_title: Label
var _review_lines: VBoxContainer
var _skip_button: Button
var _continue_button: Button


## Konfiguration vor oder nach add_child moeglich. `review_data` ist bewusst
## datengetrieben und akzeptiert `milestones`, `decisions`, `consequences` sowie
## optionale `headline`/`footer`-Texte. Das UI kennt keine Questmanager-Details.
func configure(p_from_year: int, p_to_year: int, review_data: Dictionary = {}) -> YearTransitionScreen:
	from_year = p_from_year
	to_year = p_to_year
	review = review_data.duplicate(true)
	if is_node_ready():
		_restart()
	return self


## Test-/Accessibility-Hook. `null` bzw. clear_reduced_motion_override() nutzt
## wieder die globale Option aus SettingsManager.
func set_reduced_motion(value: bool) -> void:
	_reduced_motion_override = value
	_reduced_motion = value
	queue_redraw()


func clear_reduced_motion_override() -> void:
	_reduced_motion_override = null
	_reduced_motion = _settings_reduced_motion()
	queue_redraw()


func current_stage() -> StringName:
	return [&"countdown", &"reveal", &"review", &"complete"][_stage]


func is_final_transition() -> bool:
	return from_year == 1999 and to_year == 2000


## Stabile Design-API fuer Kampagnenplaner, Tests und spaetere Art-Direction.
static func era_for_year(year: int) -> StringName:
	if year >= 1999:
		return ERA_MILLENNIUM
	if year >= 1996:
		return ERA_WEB
	if year >= 1993:
		return ERA_NETWORK
	return ERA_COPPER


func visual_contract() -> Dictionary:
	var era := era_for_year(from_year)
	return {
		"from_year": from_year,
		"to_year": to_year,
		"era": era,
		"finale": is_final_transition(),
		"effects": _effect_names(era),
		"reduced_motion": _reduced_motion,
		"stage": current_stage(),
		"commit_policy": "finished_signal_only",
	}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.get_theme()
	_build_interface()
	_restart()


func _restart() -> void:
	_stage = Stage.COUNTDOWN
	_elapsed = 0.0
	_skipped = false
	_complete_guard = false
	_last_count = 4
	_reduced_motion = bool(_reduced_motion_override) if _reduced_motion_override != null else _settings_reduced_motion()
	if _kicker != null:
		_refresh_copy()
		_apply_stage()
	stage_changed.emit(&"countdown")
	_emit_audio(&"start")
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _stage >= Stage.REVIEW:
		return
	_elapsed += minf(maxf(delta, 0.0), 0.1)
	if _stage == Stage.COUNTDOWN:
		var count := maxi(1, 3 - floori(_elapsed / 1.0))
		if count != _last_count:
			_last_count = count
			_countdown.text = str(count)
			_emit_audio(&"countdown")
		if _elapsed >= COUNTDOWN_SECONDS:
			_set_stage(Stage.REVEAL)
			_emit_audio(&"year_reveal")
	elif _stage == Stage.REVEAL:
		var hold := FINAL_REVEAL_SECONDS if is_final_transition() else REVEAL_SECONDS
		if _elapsed >= COUNTDOWN_SECONDS + hold:
			_set_stage(Stage.REVIEW)
	queue_redraw()


func skip_animation() -> void:
	if _stage >= Stage.REVIEW:
		return
	_skipped = true
	_elapsed = COUNTDOWN_SECONDS + (FINAL_REVEAL_SECONDS if is_final_transition() else REVEAL_SECONDS)
	_emit_audio(&"skip")
	_set_stage(Stage.REVIEW)


## Einziger Commit-Punkt. Zweifaches Klicken kann das Signal nicht duplizieren.
func complete() -> void:
	if _stage != Stage.REVIEW or _complete_guard:
		return
	_complete_guard = true
	_set_stage(Stage.COMPLETE)
	_emit_audio(&"complete")
	finished.emit(from_year, to_year, _skipped)
	if auto_close:
		queue_free.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and _stage < Stage.REVIEW:
		skip_animation()
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _stage == Stage.REVIEW:
		complete()
		get_viewport().set_input_as_handled()


func _set_stage(next: Stage) -> void:
	if _stage == next:
		return
	_stage = next
	_apply_stage()
	stage_changed.emit(current_stage())
	queue_redraw()


func _apply_stage() -> void:
	if _countdown == null:
		return
	var countdown_on := _stage == Stage.COUNTDOWN
	var revealed := _stage >= Stage.REVEAL
	_countdown.visible = countdown_on
	_old_year.visible = not countdown_on
	_arrow.visible = revealed
	_new_year.visible = revealed
	_review_panel.visible = _stage == Stage.REVIEW
	_continue_button.visible = _stage == Stage.REVIEW
	_skip_button.visible = _stage < Stage.REVIEW
	if _stage == Stage.REVEAL:
		_kicker.text = Loc.t("ui.year_transition_screen.frohes_neues_jahr", "FROHES NEUES JAHR") \
			if not is_final_transition() \
			else Loc.t("ui.year_transition_screen.millennium_begins",
				"DAS NEUE JAHRTAUSEND BEGINNT")
	elif _stage == Stage.REVIEW:
		_kicker.text = Loc.t("ui.year_transition_screen.dein_jahr_d", "DEIN JAHR %d") % from_year
	if _stage == Stage.REVIEW:
		_continue_button.grab_focus.call_deferred()


func _build_interface() -> void:
	# Die eigene _draw()-Ebene malt CRT, Demoscene und Feuerwerk. Darueber liegt
	# eine klare, skalierende Safe-Area fuer 16:9 und kleinere Fenster.
	var safe := MarginContainer.new()
	safe.name = "SafeArea"
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 56)
	safe.add_theme_constant_override("margin_right", 56)
	safe.add_theme_constant_override("margin_top", 32)
	safe.add_theme_constant_override("margin_bottom", 32)
	add_child(safe)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	safe.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	_kicker = _label("", 19, Palette.LCD_AMBER)
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_kicker)
	_era_label = _label("", 13, Palette.LCD_CYAN)
	_era_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_era_label)

	var rule := ColorRect.new()
	rule.color = Color(Palette.LCD_AMBER, 0.72)
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)

	var hero := CenterContainer.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.custom_minimum_size = Vector2(0, 260)
	column.add_child(hero)
	var years := HBoxContainer.new()
	years.alignment = BoxContainer.ALIGNMENT_CENTER
	years.add_theme_constant_override("separation", 28)
	hero.add_child(years)
	_old_year = _hero_label(78, Palette.WHITE_SOFT)
	years.add_child(_old_year)
	_arrow = _hero_label(48, Palette.LCD_AMBER)
	_arrow.text = "→"
	years.add_child(_arrow)
	_new_year = _hero_label(96, Palette.LCD_GREEN)
	years.add_child(_new_year)
	_countdown = _hero_label(154, Palette.LCD_AMBER)
	years.add_child(_countdown)

	_review_panel = PanelContainer.new()
	_review_panel.name = "YearReviewPanel"
	_review_panel.custom_minimum_size = Vector2(680, 150)
	_review_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_review_panel.add_theme_stylebox_override("panel", _review_style())
	column.add_child(_review_panel)
	var review_margin := MarginContainer.new()
	review_margin.add_theme_constant_override("margin_left", 18)
	review_margin.add_theme_constant_override("margin_right", 18)
	review_margin.add_theme_constant_override("margin_top", 12)
	review_margin.add_theme_constant_override("margin_bottom", 12)
	_review_panel.add_child(review_margin)
	var review_column := VBoxContainer.new()
	review_column.add_theme_constant_override("separation", 4)
	review_margin.add_child(review_column)
	_review_title = _label("", 20, Palette.LCD_AMBER)
	_review_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	review_column.add_child(_review_title)
	_review_lines = VBoxContainer.new()
	_review_lines.add_theme_constant_override("separation", 2)
	review_column.add_child(_review_lines)

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	column.add_child(controls)
	_skip_button = _button(Loc.t("ui.year_transition_screen.animation_uberspringen_esc", "ANIMATION ÜBERSPRINGEN  [ESC]"))
	_skip_button.name = "SkipAnimation"
	_skip_button.pressed.connect(skip_animation)
	controls.add_child(_skip_button)
	_continue_button = _button(Loc.t("ui.year_transition_screen.weiter", "WEITER"))
	_continue_button.name = "CommitYearTransition"
	_continue_button.pressed.connect(complete)
	controls.add_child(_continue_button)

	var access := _label("Reduzierte Bewegung wird aus den Optionen übernommen · Enter: weiter", 11, Palette.UI_TEXT_DIM)
	access.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(access)


func _refresh_copy() -> void:
	var era := era_for_year(from_year)
	_kicker.text = Loc.t("ui.year_transition_screen.silvester_31_12_d", "SILVESTER · 31.12.%d") % from_year
	_old_year.text = str(from_year)
	_new_year.text = str(to_year)
	_countdown.text = "3"
	_era_label.text = _era_name(era)
	_review_title.text = str(review.get("headline", "SO WAR DEIN JAHR %d" % from_year))
	_continue_button.text = (
		Loc.t("ui.year_transition_screen.to_finale", "ZUM FINALE · 2000")
		if is_final_transition()
		else Loc.t("ui.year_transition_screen.continue_summer",
			"WEITER IN DEN SOMMER '%02d") % (to_year % 100))
	for child in _review_lines.get_children():
		child.queue_free()
	var lines := _review_copy()
	for line: String in lines:
		var label := _label(line, 15, Palette.UI_TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_review_lines.add_child(label)


func _review_copy() -> Array[String]:
	var out: Array[String] = []
	_append_review_group(out, "★", review.get("milestones", []), "Meilensteine")
	_append_review_group(out, "◆", review.get("decisions", []), "Entscheidungen")
	_append_review_group(out, "…", review.get("consequences", []), "Offene Folgen")
	if out.is_empty():
		out.append("Ein Sommer voller kleiner Geschichten — und alles liegt noch vor dir.")
	var footer := str(review.get("footer", "")).strip_edges()
	if not footer.is_empty():
		out.append(footer)
	return out.slice(0, 4)


func _append_review_group(out: Array[String], icon: String, raw: Variant, fallback: String) -> void:
	if raw is Array and not raw.is_empty():
		var first := str(raw[0])
		out.append("%s %s" % [icon, first])
	elif raw is int and int(raw) > 0:
		out.append("%s %d %s" % [icon, int(raw), fallback])


func _draw() -> void:
	var sz := size
	if sz.x < 1.0 or sz.y < 1.0:
		return
	_draw_crt_background(sz)
	var era := era_for_year(from_year)
	match era:
		ERA_COPPER: _draw_copper(sz)
		ERA_NETWORK: _draw_network(sz)
		ERA_WEB: _draw_web(sz)
		ERA_MILLENNIUM: _draw_millennium(sz)
	_draw_fireworks(sz, era)
	_draw_scanlines(sz)
	_draw_bezel(sz)


func _draw_crt_background(sz: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, sz), Color("05050a"))
	# Zeilenweise Farbvertiefung statt Shader: deterministisch und headless-sicher.
	for i in 12:
		var inset := float(i) * minf(sz.x, sz.y) * 0.008
		var alpha := 0.035 + float(i) * 0.004
		draw_rect(Rect2(Vector2(inset, inset), sz - Vector2(inset, inset) * 2.0),
			Color(0.02, 0.035, 0.075, alpha), false, 3.0)
	if _stage == Stage.REVEAL and not _reduced_motion:
		var reveal_t := clampf((_elapsed - COUNTDOWN_SECONDS) / 0.34, 0.0, 1.0)
		var flash := (1.0 - reveal_t) * 0.22
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.7, 0.86, 1.0, flash))


func _draw_copper(sz: Vector2) -> void:
	var t := 0.0 if _reduced_motion else _elapsed
	var colors := [Palette.WB_BLUE_DARK, Palette.WB_BLUE, Palette.VIOLET, Palette.LCD_AMBER, Palette.RED]
	for i in 10:
		var y := sz.y * (0.16 + float(i) * 0.066) + sin(t * 1.3 + i * 0.62) * 12.0
		var h := 3.0 + float(i % 3) * 2.0
		var color: Color = colors[i % colors.size()]
		color.a = 0.20 + float(i % 4) * 0.035
		draw_rect(Rect2(0, y, sz.x, h), color)
	# Klassischer Raster-Horizont.
	var horizon := sz.y * 0.68
	for i in 7:
		var yy := horizon + pow(float(i) / 6.0, 1.7) * sz.y * 0.27
		draw_line(Vector2(0, yy), Vector2(sz.x, yy), Color(Palette.BLUE_MID, 0.16), 1.0)
	for i in 15:
		var x := sz.x * float(i) / 14.0
		draw_line(Vector2(sz.x * 0.5, horizon), Vector2(x, sz.y), Color(Palette.BLUE_MID, 0.12), 1.0)


func _draw_network(sz: Vector2) -> void:
	_draw_copper(sz)
	var nodes := [Vector2(.10,.68), Vector2(.22,.79), Vector2(.34,.63), Vector2(.48,.82),
		Vector2(.62,.69), Vector2(.76,.81), Vector2(.90,.65)]
	for i in nodes.size() - 1:
		var a: Vector2 = nodes[i] * sz
		var b: Vector2 = nodes[i + 1] * sz
		draw_line(a, b, Color(Palette.LCD_CYAN, 0.34), 2.0)
		if not _reduced_motion:
			var p := a.lerp(b, fposmod(_elapsed * 0.34 + i * 0.17, 1.0))
			draw_rect(Rect2(p - Vector2(5, 3), Vector2(10, 6)), Color(Palette.LCD_GREEN, 0.82))
	for p: Vector2 in nodes:
		var pos := p * sz
		draw_rect(Rect2(pos - Vector2(8, 6), Vector2(16, 12)), Color("111923"))
		draw_rect(Rect2(pos - Vector2(8, 6), Vector2(16, 12)), Color(Palette.LCD_CYAN, 0.66), false, 2.0)


func _draw_web(sz: Vector2) -> void:
	var t := 0.0 if _reduced_motion else _elapsed
	for i in 4:
		var x := sz.x * (0.08 + i * 0.245) + sin(t * .45 + i) * 6.0
		var y := sz.y * (0.65 + (i % 2) * .12)
		var card := Rect2(x, y, sz.x * .17, sz.y * .13)
		draw_rect(card, Color(0.02, 0.06, 0.11, .72))
		draw_rect(card, Color(Palette.LCD_CYAN, .35), false, 2.0)
		draw_rect(Rect2(card.position, Vector2(card.size.x, 10)), Color(Palette.WB_BLUE, .55))
		for line in 3:
			draw_line(card.position + Vector2(12, 28 + line * 15),
				card.position + Vector2(card.size.x - 12 - line * 12, 28 + line * 15),
				Color(Palette.WHITE_SOFT, .24), 2.0)
		if i > 0:
			var prev_x := sz.x * (0.08 + (i - 1) * .245)
			draw_dashed_line(Vector2(prev_x + sz.x * .17, y + 30), Vector2(x, y + 30),
				Color(Palette.LCD_AMBER, .36), 2.0, 7.0)


func _draw_millennium(sz: Vector2) -> void:
	_draw_copper(sz)
	_draw_network(sz)
	_draw_web(sz)
	var center := sz * Vector2(.5, .48)
	for ring in 5:
		var pulse := 0.0 if _reduced_motion else fposmod(_elapsed * .12 + ring * .16, 1.0)
		var radius := 70.0 + ring * 58.0 + pulse * 45.0
		draw_arc(center, radius, 0, TAU, 64, Color(Palette.LCD_GREEN, .08 + ring * .018), 2.0)


func _draw_fireworks(sz: Vector2, era: StringName) -> void:
	var centers := [Vector2(.16,.25), Vector2(.83,.23), Vector2(.28,.48), Vector2(.72,.48)]
	var extra := 2 if era == ERA_MILLENNIUM else 0
	for f in centers.size() + extra:
		var base: Vector2 = centers[f % centers.size()]
		if f >= centers.size():
			base = Vector2(.42 + .16 * (f - centers.size()), .18)
		var age := .58 if _reduced_motion else fposmod(_elapsed * .28 + f * .23, 1.0)
		var radius := 18.0 + age * (78.0 if era == ERA_MILLENNIUM else 58.0)
		var firework_colors: Array[Color] = [
			Color(Palette.LCD_AMBER),
			Color(Palette.LCD_CYAN),
			Color(Palette.LCD_GREEN),
			Color(Palette.PINK),
		]
		var color: Color = firework_colors[f % firework_colors.size()]
		for ray in 12:
			var angle := TAU * float(ray) / 12.0 + f * .31
			var p := base * sz + Vector2.from_angle(angle) * radius
			var pixel := 5.0 if era == ERA_MILLENNIUM else 4.0
			var alpha := .16 if _stage == Stage.COUNTDOWN else (.78 * (1.0 - age) + .12)
			draw_rect(Rect2(p.snapped(Vector2(3, 3)) - Vector2.ONE * pixel * .5,
				Vector2.ONE * pixel), Color(color, alpha))


func _draw_scanlines(sz: Vector2) -> void:
	if _settings_node == null:
		_settings_node = get_node_or_null("/root/SettingsManager")
	if _settings_node != null and not bool(_settings_node.call("value", "scanlines")):
		return
	for y in range(1, int(sz.y), 4):
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color(0, 0, 0, .18), 1.0)


func _draw_bezel(sz: Vector2) -> void:
	draw_rect(Rect2(6, 6, sz.x - 12, sz.y - 12), Color(Palette.UI_BORDER_DARK, .9), false, 6.0)
	draw_rect(Rect2(16, 16, sz.x - 32, sz.y - 32), Color(Palette.LCD_AMBER, .30), false, 2.0)
	# Kleine Status-LED unten rechts, passend zu den Geraeten im Zimmer.
	draw_circle(Vector2(sz.x - 31, sz.y - 24), 4.0, Palette.LCD_GREEN if _stage >= Stage.REVEAL else Palette.LCD_AMBER)


func _emit_audio(cue: StringName) -> void:
	audio_cue.emit(cue)
	if not auto_audio:
		return
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	match cue:
		&"start": audio.call("relay")
		&"countdown": audio.call("play_toned", "ui_blip", 0.78 + float(4 - _last_count) * .12)
		&"year_reveal": audio.call("key_enter")
		&"complete": audio.call("minigame_cue", "year_transition", &"success")
		&"skip": audio.call("ui_click")


func _settings_reduced_motion() -> bool:
	var settings := get_node_or_null("/root/SettingsManager")
	return settings != null and bool(settings.call("value", "reduced_motion"))


static func _effect_names(era: StringName) -> Array[StringName]:
	match era:
		ERA_COPPER: return [&"pixel_fireworks", &"copper_bars", &"perspective_grid", &"crt_scanlines"]
		ERA_NETWORK: return [&"pixel_fireworks", &"copper_bars", &"packet_network", &"crt_scanlines"]
		ERA_WEB: return [&"pixel_fireworks", &"web_windows", &"hyperlinks", &"crt_scanlines"]
		_: return [&"pixel_fireworks_plus", &"copper_bars", &"packet_network", &"web_windows", &"millennium_rings", &"crt_scanlines"]


static func _era_name(era: StringName) -> String:
	match era:
		ERA_COPPER: return "AMIGA · COPPER ERA"
		ERA_NETWORK: return "BBS · NETZWERK ERA"
		ERA_WEB: return "MODEM · WEB ERA"
		_: return "1999 · MILLENNIUM FINALE"


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .8))
	return label


func _hero_label(font_size: int, color: Color) -> Label:
	var label := _label("", font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.01, .02, .05, .95))
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(290, 42)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 17)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("11141b")
	normal.border_color = Color(Palette.LCD_AMBER, .62)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(7)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("30240d")
	hover.border_color = Palette.LCD_AMBER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("07080b")
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Palette.LCD_CYAN
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_hover_color", Palette.LCD_AMBER)
	button.add_theme_color_override("font_focus_color", Palette.WHITE)
	return button


func _review_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, .045, .065, .92)
	style.border_color = Color(Palette.LCD_CYAN, .48)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, .55)
	style.shadow_size = 12
	return style
