extends Control
## Live-Werkstatt fuer den echten globalen Vollbild-CRT-Shader. PageUp/PageDown
## schalten reale Spielorte; alle Regler werden je Location in
## data/crt_game_profiles.json gespeichert und von main.gd direkt verwendet.

const Profiles := preload("res://scripts/gfx/crt_profile_store.gd")
const TownData := preload("res://scripts/autoload/town_manager.gd")
const CRT_SHADER := preload("res://shaders/crt.gdshader")
const PREVIEW_SIZE := Vector2i(960, 540)

var _levels: Array = []
var _level_index := 0
var _level_select: OptionButton
var _preview: SubViewport
var _stage: Control
var _location_node: Control
var _crt_overlay: ColorRect
var _material: ShaderMaterial
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _params: Dictionary = {}
var _status: Label
var _loading := false


func _ready() -> void:
	theme = RetroTheme.build()
	_levels = Profiles.levels()
	_build()
	_select_level(0)
	grab_focus.call_deferred()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color8(8, 10, 14)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 10.0
	page.offset_top = 8.0
	page.offset_right = -10.0
	page.offset_bottom = -8.0
	page.add_theme_constant_override("separation", 8)
	add_child(page)

	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 40.0
	toolbar.add_theme_constant_override("separation", 7)
	toolbar.add_child(_button(Loc.t("misc.crt_game_editor.location", "◀ LOCATION"), _step_level.bind(-1)))
	_level_select = OptionButton.new()
	_level_select.custom_minimum_size.x = 260.0
	for definition: Dictionary in _levels:
		_level_select.add_item(str(definition.get("name", definition.get("id", "LEVEL"))))
	_level_select.item_selected.connect(_select_level)
	toolbar.add_child(_level_select)
	toolbar.add_child(_button(Loc.t("misc.crt_game_editor.location_a637", "LOCATION ▶"), _step_level.bind(1)))
	toolbar.add_child(_button(Loc.t("misc.crt_game_editor.filter_an_aus_leertaste", "FILTER AN/AUS  [LEERTASTE]"), _toggle_filter))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	toolbar.add_child(_button(Loc.t("misc.crt_game_editor.reset", "RESET"), _reset_current))
	toolbar.add_child(_button(Loc.t("misc.crt_game_editor.vorheriges_kopieren", "VORHERIGES KOPIEREN"), _copy_previous))
	toolbar.add_child(_button(Loc.t("misc.crt_game_editor.speichern_s", "SPEICHERN  [S]"), _save_current))
	page.add_child(toolbar)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 900
	page.add_child(split)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", Bezel.display_box())
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 3)
	preview_panel.add_child(preview_column)
	var preview_title := Bezel.dim_label(Loc.t("misc.crt_game_editor.echte_location_globaler_runtime_shader_960", "ECHTE LOCATION · GLOBALER RUNTIME-SHADER · 960 × 540"), 13)
	preview_title.add_theme_color_override("font_color", Palette.LCD_AMBER)
	preview_column.add_child(preview_title)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 16.0 / 9.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(aspect)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(620, 350)
	aspect.add_child(container)
	_preview = SubViewport.new()
	_preview.size = PREVIEW_SIZE
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview.gui_disable_input = true
	container.add_child(_preview)
	# Kein nachgebautes Testbild: In diesem Host laeuft exakt dasselbe Location-
	# Skript wie spaeter im Spiel, inklusive Artwork, 2,5D und Atmosphaere.
	_stage = Control.new()
	_stage.name = "RuntimeLocationPreview"
	_stage.position = Vector2.ZERO
	_stage.size = Vector2(PREVIEW_SIZE)
	_preview.add_child(_stage)
	_crt_overlay = ColorRect.new()
	_crt_overlay.position = Vector2.ZERO
	_crt_overlay.size = Vector2(PREVIEW_SIZE)
	_crt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = CRT_SHADER
	_crt_overlay.material = _material
	_preview.add_child(_crt_overlay)
	_preview.size_changed.connect(_resize_preview_content)
	_resize_preview_content.call_deferred()
	split.add_child(preview_panel)

	var controls_panel := PanelContainer.new()
	controls_panel.custom_minimum_size.x = 420.0
	controls_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_panel.add_theme_stylebox_override("panel", Bezel.panel_box())
	var controls_column := VBoxContainer.new()
	controls_column.add_theme_constant_override("separation", 5)
	controls_panel.add_child(controls_column)
	var controls_title := Bezel.lcd_label(Loc.t("misc.crt_game_editor.crt_filter_alle_d_parameter", "CRT-FILTER · ALLE %d PARAMETER") % Profiles.PARAMETERS.size(), Palette.LCD_CYAN, 15)
	controls_column.add_child(controls_title)
	var help := Bezel.dim_label(Loc.t("misc.crt_game_editor.regler_andern_echte_location_live_jeder", "Regler ändern die echte Location live. Jeder Ort besitzt ein eigenes Gesamtfilter-Profil."), 10)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_column.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	scroll.add_child(rows)
	for spec: Dictionary in Profiles.PARAMETERS:
		_add_parameter(rows, spec)
	_status = Bezel.dim_label(Loc.t("misc.crt_game_editor.bereit", "BEREIT"), 11)
	_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	controls_column.add_child(_status)
	split.add_child(controls_panel)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _resize_preview_content() -> void:
	if _preview == null or _stage == null or _crt_overlay == null:
		return
	var viewport_size := Vector2(_preview.size)
	_stage.size = Vector2(PREVIEW_SIZE)
	_stage.scale = viewport_size / Vector2(PREVIEW_SIZE)
	_crt_overlay.size = viewport_size


func _add_parameter(parent: VBoxContainer, spec: Dictionary) -> void:
	var key := str(spec["id"])
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	var name_label := Bezel.dim_label(str(spec["name"]), 11)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := Bezel.lcd_label(Loc.t("misc.crt_game_editor.0_000", "0.000"), Palette.LCD_AMBER, 10)
	value_label.custom_minimum_size.x = 68.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(value_label)
	block.add_child(head)
	var slider := HSlider.new()
	slider.min_value = float(spec["min"])
	slider.max_value = float(spec["max"])
	slider.step = float(spec["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_parameter_changed.bind(key))
	block.add_child(slider)
	parent.add_child(block)
	_sliders[key] = slider
	_value_labels[key] = value_label


func _select_level(index: int) -> void:
	if _levels.is_empty():
		return
	_level_index = posmod(index, _levels.size())
	_loading = true
	_level_select.select(_level_index)
	var definition: Dictionary = _levels[_level_index]
	var id := str(definition.get("id", "room"))
	_params = Profiles.params_for(id)
	for spec: Dictionary in Profiles.PARAMETERS:
		var key := str(spec["id"])
		var value := float(_params.get(key, 0.0))
		(_sliders[key] as HSlider).value = value
		_update_value_label(key, value)
	_loading = false
	_load_runtime_location(id, definition)
	_apply_material()
	_status.text = Loc.t("misc.crt_game_editor.s_echte_location_geladen", "%s · ECHTE LOCATION GELADEN") % str(definition.get("name", id.to_upper()))


func _load_runtime_location(id: String, definition: Dictionary) -> void:
	if _location_node != null and is_instance_valid(_location_node):
		_stage.remove_child(_location_node)
		_location_node.free()
		_location_node = null
	var script: GDScript = TownData.SCRIPTS.get(id)
	if script == null:
		_status.text = Loc.t("misc.crt_game_editor.fehler_kein_runtime_skript_fur_s", "FEHLER · KEIN RUNTIME-SKRIPT FÜR %s") % id
		return
	TimeManager.year = int(definition.get("preview_year", 1990))
	TimeManager.month = 7
	TimeManager.day = 7
	TimeManager.slot = 0
	GameManager.state = GameManager.State.PLAYING
	GameManager.current_location_id = id
	GameManager.LOCATION_DEFS = TownManager.live_defs()
	_location_node = script.new()
	_location_node.set("location_id", id)
	_location_node.position = Vector2.ZERO
	_location_node.size = Vector2(PREVIEW_SIZE)
	_stage.add_child(_location_node)


func _step_level(direction: int) -> void:
	_select_level(_level_index + direction)


func _on_parameter_changed(value: float, key: String) -> void:
	if _loading:
		return
	_params[key] = value
	_update_value_label(key, value)
	_material.set_shader_parameter(key, value)
	_status.text = Loc.t("misc.crt_game_editor.live_geandert_noch_nicht_gespeichert", "LIVE GEÄNDERT · NOCH NICHT GESPEICHERT")
	_status.add_theme_color_override("font_color", Palette.LCD_AMBER)


func _update_value_label(key: String, value: float) -> void:
	var decimals := 5 if value < 0.01 and value > 0.0 else 3
	(_value_labels[key] as Label).text = ("%.*f" % [decimals, value])


func _apply_material() -> void:
	for spec: Dictionary in Profiles.PARAMETERS:
		var key := str(spec["id"])
		_material.set_shader_parameter(key, float(_params.get(key, 0.0)))


func _toggle_filter() -> void:
	_crt_overlay.visible = not _crt_overlay.visible
	_status.text = Loc.t("misc.crt_game_editor.filter_s_leertaste_zum_vergleich",
		"FILTER %s · LEERTASTE ZUM VERGLEICH") % (
			Loc.t("ui.common.on", "AN") if _crt_overlay.visible
			else Loc.t("ui.common.off", "AUS"))


func _reset_current() -> void:
	_params = Profiles.defaults()
	_loading = true
	for spec: Dictionary in Profiles.PARAMETERS:
		var key := str(spec["id"])
		var value := float(_params.get(key, 0.0))
		(_sliders[key] as HSlider).value = value
		_update_value_label(key, value)
	_loading = false
	_apply_material()
	_status.text = Loc.t("misc.crt_game_editor.werksstandard_geladen_s_zum_speichern", "WERKSSTANDARD GELADEN · S ZUM SPEICHERN")


func _copy_previous() -> void:
	if _levels.is_empty():
		return
	var previous := posmod(_level_index - 1, _levels.size())
	var id := str((_levels[previous] as Dictionary).get("id", "room"))
	_params = Profiles.params_for(id)
	_loading = true
	for spec: Dictionary in Profiles.PARAMETERS:
		var key := str(spec["id"])
		var value := float(_params.get(key, 0.0))
		(_sliders[key] as HSlider).value = value
		_update_value_label(key, value)
	_loading = false
	_apply_material()
	_status.text = Loc.t("misc.crt_game_editor.s_kopiert_s_zum_speichern", "%s KOPIERT · S ZUM SPEICHERN") % Profiles.level_name(id)


func _save_current() -> void:
	if _levels.is_empty():
		return
	var id := str((_levels[_level_index] as Dictionary).get("id", "room"))
	var ok := Profiles.set_level_params(id, _params)
	_status.text = (Loc.t("misc.crt_game_editor.saved_profile",
		"GESPEICHERT · %s · data/crt_game_profiles.json") % Profiles.level_name(id)) \
		if ok else Loc.t("misc.crt_game_editor.save_failed",
			"FEHLER · PROFIL KONNTE NICHT GESPEICHERT WERDEN")
	_status.add_theme_color_override("font_color", Palette.LCD_GREEN if ok else Color8(255, 85, 72))


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_PAGEUP, KEY_LEFT:
			_step_level(-1)
		KEY_PAGEDOWN, KEY_RIGHT, KEY_TAB:
			_step_level(1)
		KEY_SPACE:
			_toggle_filter()
		KEY_R:
			_reset_current()
		KEY_S:
			_save_current()
		_:
			return
	get_viewport().set_input_as_handled()


class _CrtSampleStage extends Control:
	var level_id := "boot"
	var _time := 0.0
	var _font: Font = load("res://assets/fonts/VT323_UI.ttf")

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(7, 10, 18))
		match level_id:
			"workbench": _draw_workbench()
			"xcopy": _draw_xcopy()
			"demos": _draw_demo()
			"games": _draw_game()
			_: _draw_boot()
		_draw_reference_grid()

	func _draw_boot() -> void:
		draw_rect(Rect2(0, 0, size.x, size.y), Color8(92, 102, 160))
		draw_rect(Rect2(292, 122, 376, 266), Color8(225, 225, 221))
		draw_rect(Rect2(312, 142, 336, 226), Color8(96, 106, 164))
		draw_rect(Rect2(421, 218, 118, 88), Color8(236, 238, 231))
		draw_rect(Rect2(438, 238, 84, 46), Color8(38, 45, 64))
		draw_string(_font, Vector2(0, 92), "BOOT / KICKSTART · DISKETTE EINLEGEN", HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, Color.WHITE)

	func _draw_workbench() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(63, 101, 190))
		draw_rect(Rect2(0, 0, size.x, 28), Color8(238, 238, 238))
		draw_string(_font, Vector2(12, 21), "Workbench 1.3    879K frei", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color8(18, 18, 18))
		for index in 5:
			var p := Vector2(55 + index * 112, 62 + (index % 2) * 80)
			draw_rect(Rect2(p, Vector2(50, 34)), Color8(225, 225, 225))
			draw_rect(Rect2(p + Vector2(5, 8), Vector2(40, 5)), Color8(20, 25, 34))
		draw_rect(Rect2(238, 178, 540, 278), Color8(232, 232, 232))
		draw_rect(Rect2(238, 178, 540, 26), Color8(24, 32, 42))
		draw_string(_font, Vector2(250, 198), "SYSTEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
		for y in 5:
			draw_line(Vector2(268, 242 + y * 37), Vector2(738, 242 + y * 37), Color8(72, 82, 98), 2.0)

	func _draw_xcopy() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(22, 24, 28))
		draw_rect(Rect2(18, 18, size.x - 36, 52), Color8(20, 71, 133))
		draw_string(_font, Vector2(0, 56), "X-COPY PROFESSIONAL · TRACK ANALYSER", HORIZONTAL_ALIGNMENT_CENTER, size.x, 29, Color8(255, 188, 44))
		for side in 2:
			var x := 54.0 + side * 482.0
			draw_rect(Rect2(x, 112, 370, 316), Color8(8, 11, 14))
			for track in 11:
				var color := Color8(68, 230, 104) if (track + side) % 4 else Color8(255, 177, 45)
				draw_rect(Rect2(x + 20, 138 + track * 23, 330 * (0.35 + 0.6 * absf(sin(track + _time))), 8), color)
		draw_string(_font, Vector2(0, 493), "SOURCE 00–79     VERIFY     TARGET 00–79", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color8(210, 220, 210))

	func _draw_demo() -> void:
		for y in 14:
			var color := Color8(22, 38, 83).lerp(Color8(126, 30, 123), float(y) / 13.0)
			draw_rect(Rect2(0, y * size.y / 14.0, size.x, size.y / 14.0 + 1), color)
		for index in 80:
			var x := fposmod(index * 127.0 + _time * (12 + index % 7), size.x)
			var y := fposmod(index * 71.0 + _time * (5 + index % 3), size.y)
			draw_rect(Rect2(x, y, 2 + index % 3, 2 + index % 3), Color.WHITE)
		for bar in 9:
			var yy := 318.0 + bar * 12.0
			var pad := 70.0 + sin(_time * 1.8 + bar) * 52.0
			draw_rect(Rect2(pad, yy, size.x - pad * 2.0, 7), Color8(255, 77 + bar * 13, 44 + bar * 18))
		draw_string(_font, Vector2(0, 168), "SCENE SIGNAL", HORIZONTAL_ALIGNMENT_CENTER, size.x, 56, Color8(255, 226, 108))

	func _draw_game() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(45, 153, 207))
		draw_circle(Vector2(790, 92), 52, Color8(255, 229, 101))
		for cloud in 4:
			var x := fposmod(cloud * 270.0 - _time * (11 + cloud), size.x + 150.0) - 75.0
			draw_rect(Rect2(x, 82 + cloud * 42, 108, 22), Color8(225, 241, 242))
		draw_rect(Rect2(0, 374, size.x, 166), Color8(36, 112, 68))
		for tile in 16:
			draw_rect(Rect2(tile * 64, 374, 60, 31), Color8(105, 176, 68) if tile % 2 else Color8(82, 151, 58))
		var hero_x := 154.0 + sin(_time * 1.6) * 28.0
		draw_rect(Rect2(hero_x, 314, 28, 60), Color8(241, 206, 83))
		draw_rect(Rect2(hero_x + 4, 324, 7, 7), Color8(25, 28, 34))
		draw_string(_font, Vector2(18, 38), "SCORE 001250     LIVES 3     LEVEL 04", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

	func _draw_reference_grid() -> void:
		# Referenzen an allen vier Kanten machen Krümmung, Vignette, Farbsäume und
		# Randweichheit sofort beurteilbar.
		var color := Color(0.92, 0.96, 0.92, 0.38)
		for x in range(0, int(size.x) + 1, 64):
			draw_line(Vector2(x, 0), Vector2(x, size.y), color, 1.0)
		for y in range(0, int(size.y) + 1, 54):
			draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), Color.WHITE, false, 3.0)
