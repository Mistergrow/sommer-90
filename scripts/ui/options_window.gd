extends RetroWindow
## OPTIONEN — Grafik & Ton. Liest/schreibt SettingsManager (persistent).
## Umschalter (CRT, Vollbild …) und Schieberegler (Lautstärken).

var _body: VBoxContainer
var _scroll: ScrollContainer
var _back_button: Button
var _save_hint: Label
var _current_section: VBoxContainer


func _init() -> void:
	title = Loc.t("ui.options.title", "OPTIONEN")
	# Das breite Systempult nutzt heutige Monitore, bleibt aber sicher innerhalb
	# von 1280x720. Die Scrollreserve faengt grosse UI-Schrift weiterhin ab.
	win_size = Vector2(820, 580)
	chrome_accent = Palette.PINK


func _ready() -> void:
	super._ready()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	var footer := HBoxContainer.new()
	footer.name = "OptionsFooter"
	footer.add_theme_constant_override("separation", 10)
	_save_hint = Bezel.dim_label(
		Loc.t("ui.options.saved_live", "ÄNDERUNGEN WERDEN SOFORT GESPEICHERT"), 10)
	_save_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_save_hint)
	_back_button = make_button(Loc.t("ui.common.back", "Zurück"), queue_free)
	_back_button.custom_minimum_size = Vector2(170, 34)
	footer.add_child(_back_button)
	content.add_child(footer)
	Localization.locale_changed.connect(_on_locale_changed)
	SettingsManager.settings_changed.connect(_sync_settings)
	_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.free()
	set_window_title(Loc.t("ui.options.title", "OPTIONEN"))
	_back_button.text = Loc.t("ui.common.back", "Zurück")
	_save_hint.text = Loc.t("ui.options.saved_live", "ÄNDERUNGEN WERDEN SOFORT GESPEICHERT")

	_build_system_header()
	var columns := HBoxContainer.new()
	columns.name = "OptionsColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 10)
	_body.add_child(columns)
	var left := _column("OptionsLeft")
	var right := _column("OptionsRight")
	columns.add_child(left)
	columns.add_child(right)

	_current_section = _section(left,
		Loc.t("ui.options.language.header", "SPRACHE"),
		Loc.t("ui.options.language.subtitle", "Oberfläche und Texte"), Palette.LCD_AMBER)
	_language_row()

	_current_section = _section(left,
		Loc.t("ui.options.graphics.header", "GRAFIK"),
		Loc.t("ui.options.graphics.subtitle", "Bild, Bewegung und Monitor"), Palette.LCD_CYAN)
	_toggle_row(Loc.t("ui.options.graphics.crt_global", "CRT-Gesamtfilter (experimentell)"),
		"crt_global_filter")
	_toggle_row(Loc.t("ui.options.graphics.crt_auto", "Monitor-CRT automatisch"),
		"crt_auto_monitor")
	_toggle_row(Loc.t("ui.options.graphics.scanlines", "Scanlines (Retro-Programme)"),
		"scanlines")
	_toggle_row(Loc.t("ui.options.graphics.depth", "2,5D-Tiefenbewegung"), "location_depth")
	_toggle_row(Loc.t("ui.options.graphics.ambient", "Lebendige Standorte"), "ambient_life")
	_toggle_row(Loc.t("ui.options.graphics.reduced_motion", "Reduzierte Bewegung"),
		"reduced_motion")
	_toggle_row(Loc.t("ui.options.graphics.fullscreen", "Vollbild"), "fullscreen")

	_current_section = _section(right,
		Loc.t("ui.options.hud.header", "HUD-MUSIKANZEIGE"),
		Loc.t("ui.options.hud.subtitle", "Szene-EQ im oberen Display"), Palette.LCD_CYAN)
	_slider_row(Loc.t("ui.options.hud.sensitivity", "Equalizer-Empfindlichkeit"),
		"hud_scene_gain", false, 0.65, 1.75, 0.05, "x")
	_slider_row(Loc.t("ui.options.hud.afterglow", "Nachleuchten"), "hud_scene_decay")
	_toggle_row(Loc.t("ui.options.hud.peaks", "Peak-Hold-Markierungen"), "hud_scene_peaks")
	_choice_row(Loc.t("ui.options.hud.bands", "Frequenzbänder"), "hud_scene_bands", [
		{"label": "12", "value": 12}, {"label": "24", "value": 24}, {"label": "32", "value": 32}])
	_choice_row(Loc.t("ui.options.hud.palette", "Farbprofil"), "hud_scene_palette", [
		{"label": "SUNSET", "value": "sunset"}, {"label": "ICE", "value": "ice"},
		{"label": "PHOSPHOR", "value": "phosphor"}, {"label": "CANDY", "value": "candy"}])

	_current_section = _section(right,
		Loc.t("ui.options.audio.header", "TON"),
		Loc.t("ui.options.audio.subtitle", "Mischpult und Testsignal"), Palette.LCD_AMBER)
	_slider_row(Loc.t("ui.options.audio.master", "Gesamt"), "master")
	_slider_row(Loc.t("ui.options.audio.music", "Musik"), "music")
	_slider_row(Loc.t("ui.options.audio.effects", "Effekte"), "sfx", true)
	_current_section.add_child(make_button(Loc.t("ui.mods.button", "MOD-Ordner & Soundtrack"),
		func() -> void:
			UIManager.toggle_window("win_user_mods", func() -> Control:
				return load("res://scripts/ui/mod_library_window.gd").new())))
	_current_section = null


func _build_system_header() -> void:
	var panel := PanelContainer.new()
	panel.name = "OptionsSystemHeader"
	panel.add_theme_stylebox_override("panel",
		_panel_style(Color8(10, 17, 24), Palette.WB_BLUE, 8.0, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var monogram := Label.new()
	monogram.text = Loc.t("ui.options_window.prefs", "PREFS")
	monogram.custom_minimum_size = Vector2(72, 34)
	monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	monogram.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	monogram.add_theme_font_size_override("font_size", 15)
	monogram.add_theme_color_override("font_color", Palette.WB_BLACK)
	monogram.add_theme_stylebox_override("normal",
		_panel_style(Palette.LCD_AMBER, Palette.WB_ORANGE, 4.0, 1))
	row.add_child(monogram)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	var heading := Bezel.lcd_label(
		Loc.t("ui.options.console_title", "SYSTEMEINSTELLUNGEN"), Palette.LCD_AMBER, 15)
	copy.add_child(heading)
	copy.add_child(Bezel.dim_label(Loc.t("ui.options.console_subtitle",
		"BILD · BEWEGUNG · MUSIKANZEIGE · TON"), 10))
	var state := Bezel.lcd_label(
		Loc.t("ui.options.live_state", "LIVE · PROFIL AKTIV"), Palette.LCD_GREEN, 10)
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.custom_minimum_size = Vector2(128, 0)
	row.add_child(state)
	_body.add_child(panel)


func _column(node_name: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	return column


func _section(parent: VBoxContainer, heading: String, subtitle: String,
		accent: Color) -> VBoxContainer:
	var shell := PanelContainer.new()
	shell.name = "OptionsSection_" + heading.to_snake_case()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_theme_stylebox_override("panel",
		_panel_style(Color8(17, 18, 21), Palette.UI_BORDER_DARK, 7.0, 1))
	parent.add_child(shell)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	shell.add_child(stack)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	stack.add_child(header_row)
	var marker := ColorRect.new()
	marker.color = accent
	marker.custom_minimum_size = Vector2(4, 30)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_row.add_child(marker)
	var title_label := Label.new()
	title_label.text = heading
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.custom_minimum_size.y = 30
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", accent)
	header_row.add_child(title_label)
	var sub_label := Bezel.dim_label(subtitle, 11)
	sub_label.custom_minimum_size = Vector2(152, 30)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(sub_label)
	var rule := HSeparator.new()
	var rule_style := StyleBoxFlat.new()
	rule_style.bg_color = Color(accent, 0.38)
	rule_style.content_margin_top = 1.0
	rule_style.content_margin_bottom = 0.0
	rule.add_theme_stylebox_override("separator", rule_style)
	stack.add_child(rule)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	stack.add_child(rows)
	return rows


func _language_row() -> void:
	var row := _row(Loc.t("ui.options.language.label", "Sprache"))
	var option := OptionButton.new()
	option.set_meta("setting_key", "locale")
	option.custom_minimum_size = Vector2(142, 28)
	var locales: Array[String] = Localization.available_locales()
	var selected := 0
	for index in locales.size():
		var code := locales[index]
		option.add_item(Localization.locale_name(code))
		option.set_item_metadata(index, code)
		if code == Localization.locale():
			selected = index
	option.select(selected)
	option.item_selected.connect(func(index: int) -> void:
		Localization.set_locale(str(option.get_item_metadata(index))))
	row.add_child(option)


func _on_locale_changed(_locale: String) -> void:
	# Der OptionButton, der das Signal ausgeloest hat, darf erst nach seinem
	# Callback freigegeben werden. Ein Frame spaeter ist der Wechsel dennoch
	# sichtbar und alle Texte/Titel werden aus dem neuen Katalog aufgebaut.
	call_deferred("_rebuild")


## F11 and the HUD can change settings while this window remains open. Update
## existing controls without rebuilding them and interrupting a slider drag.
func _sync_settings() -> void:
	for node: Node in _body.find_children("*", "Control", true, false):
		if not node.has_meta("setting_key"):
			continue
		var key := str(node.get_meta("setting_key"))
		var current: Variant = SettingsManager.value(key)
		if node is OptionButton:
			var choice := node as OptionButton
			for index in choice.item_count:
				if choice.get_item_metadata(index) == current:
					choice.select(index)
					break
		elif node is HSlider:
			var slider := node as HSlider
			slider.set_value_no_signal(float(current))
			var label := slider.get_meta("value_label") as Label
			label.text = Loc.t("ui.options_window.2fx", "%.2fx") % slider.value if slider.get_meta("value_suffix") == "x" \
				else "%d%%" % roundi(slider.value * 100.0)
		elif node is Button:
			_style_toggle(node as Button, bool(current), node.get_meta("toggle_led") as ColorRect)


func _row(label: String) -> HBoxContainer:
	var shell := PanelContainer.new()
	shell.add_theme_stylebox_override("panel",
		_panel_style(Color8(12, 13, 16), Color8(43, 45, 51), 5.0, 1))
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 29
	row.add_theme_constant_override("separation", 7)
	var l := Bezel.dim_label(label, 12)
	l.add_theme_color_override("font_color", Palette.UI_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = label
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	shell.add_child(row)
	if is_instance_valid(_current_section):
		_current_section.add_child(shell)
	else:
		_body.add_child(shell)
	return row


## Umschalter: Button zeigt AN/AUS und schreibt die Einstellung.
func _toggle_row(label: String, key: String) -> void:
	var row := _row(label)
	var on: bool = bool(SettingsManager.value(key))
	var led := ColorRect.new()
	led.custom_minimum_size = Vector2(5, 18)
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(led)
	var btn := make_button("", Callable())
	btn.set_meta("setting_key", key)
	btn.set_meta("toggle_led", led)
	btn.custom_minimum_size = Vector2(72, 27)
	_style_toggle(btn, on, led)
	btn.pressed.connect(func() -> void:
		var new_on: bool = not bool(SettingsManager.value(key))
		SettingsManager.set_value(key, new_on)
		_style_toggle(btn, new_on, led))
	row.add_child(btn)


func _style_toggle(btn: Button, on: bool, led: ColorRect = null) -> void:
	btn.text = Loc.t("ui.common.on", "AN") if on else Loc.t("ui.common.off", "AUS")
	btn.add_theme_color_override("font_color", Palette.LCD_GREEN if on else Palette.UI_TEXT_DIM)
	if led != null:
		led.color = Palette.LCD_GREEN if on else Color8(68, 68, 72)


## Schieberegler 0–100 %.
func _slider_row(label: String, key: String, test_sound := false, min_value := 0.0,
		max_value := 1.0, step := 0.05, suffix := "%") -> void:
	var row := _row(label)
	var slider := HSlider.new()
	slider.set_meta("setting_key", key)
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = float(SettingsManager.value(key))
	slider.custom_minimum_size = Vector2(104, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var shown := "%.2fx" % slider.value if suffix == "x" else "%d%%" % roundi(slider.value * 100.0)
	var pct := Bezel.lcd_label(shown, Palette.LCD_CYAN, 11)
	pct.custom_minimum_size = Vector2(44, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pct)
	slider.set_meta("value_label", pct)
	slider.set_meta("value_suffix", suffix)
	slider.value_changed.connect(func(v: float) -> void:
		SettingsManager.set_value(key, v)
		pct.text = Loc.t("ui.options_window.2fx", "%.2fx") % v if suffix == "x" else "%d%%" % roundi(v * 100.0))
	if test_sound:
		slider.drag_ended.connect(func(_changed: bool) -> void: AudioManager.floppy_read())


func _choice_row(label: String, key: String, choices: Array) -> void:
	var row := _row(label)
	var option := OptionButton.new()
	option.set_meta("setting_key", key)
	option.custom_minimum_size = Vector2(142, 28)
	var selected := 0
	for index in choices.size():
		var choice: Dictionary = choices[index]
		option.add_item(str(choice["label"]))
		option.set_item_metadata(index, choice["value"])
		if choice["value"] == SettingsManager.value(key):
			selected = index
	option.select(selected)
	option.item_selected.connect(func(index: int) -> void:
		SettingsManager.set_value(key, option.get_item_metadata(index)))
	row.add_child(option)


func _panel_style(background: Color, border: Color, margin: float,
		border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.anti_aliasing = false
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(2)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style
