class_name HomepageEditorWindow
extends RetroWindow
## HOMEPAGE-STUDIO — browsernahe Live-Vorschau, klar getrennte Bereiche fuer
## Inhalt, Gestaltung und Jahresmodule. Alte Saves werden vom Manager in das
## Modulmodell migriert; der Editor arbeitet immer auf einer lokalen Kopie.

const BGS := ["stars", "bricks", "gradient"]
const COLORS := [Color8(255, 72, 160), Color8(58, 211, 229), Color8(91, 229, 124),
	Color8(244, 197, 54), Color8(174, 116, 244)]

var _preview: HomepagePreview
var _cfg: Dictionary = {}
var _bg_buttons: Dictionary = {}
var _layout_buttons: Dictionary = {}
var _status_label: Label


func _init() -> void:
	title = Loc.t("ui.homepage_editor_window.homepage_studio_private_site",
		"HOMEPAGE-STUDIO · PRIVATE SEITE")
	win_size = Vector2(1040, 700)


func _ready() -> void:
	super._ready()
	_cfg = _load_cfg()

	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 44)
	header.add_theme_stylebox_override("panel", _panel_style(Color8(20, 40, 61), Color8(38, 113, 151)))
	content.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	header.add_child(header_row)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(Bezel.lcd_label(Loc.t("ui.homepage_editor_window.webwerk_homepage_studio", "WEBWERK HOMEPAGE-STUDIO"), Palette.LCD_AMBER, 15))
	identity.add_child(Bezel.dim_label(Loc.t("ui.homepage_editor_window.inhalt_design_module_upload", "INHALT · DESIGN · MODULE · UPLOAD"), 10))
	header_row.add_child(identity)
	_status_label = Bezel.lcd_label(Loc.t("ui.homepage_editor_window.entwurf_offline", "ENTWURF · OFFLINE"), Color8(95, 210, 238), 11)
	_status_label.custom_minimum_size = Vector2(300, 0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_row.add_child(_status_label)

	var workspace := HBoxContainer.new()
	workspace.add_theme_constant_override("separation", 10)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(workspace)
	workspace.add_child(_build_browser())
	workspace.add_child(_build_inspector())

	var actions := HBoxContainer.new()
	actions.custom_minimum_size = Vector2(0, 46)
	actions.add_theme_constant_override("separation", 8)
	var save_button := make_button(Loc.t("ui.homepage_editor_window.entwurf_speichern", "ENTWURF SPEICHERN"), func() -> void:
		HomepageManager.save_cfg(_cfg)
		UIManager.toast(Loc.t("ui.homepage_editor_window.homepage_entwurf_gespeichert", "Homepage-Entwurf gespeichert.")))
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(save_button)
	var publish_button := make_button(Loc.t("ui.homepage_editor_window.pruefen_hochladen", "PRUEFEN + HOCHLADEN"), _publish)
	publish_button.name = "PublishHomepage"
	publish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(publish_button)
	content.add_child(actions)
	_update_status()


func _build_browser() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(670, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color8(12, 17, 24), Color8(52, 64, 75)))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	panel.add_child(stack)

	var browser_bar := HBoxContainer.new()
	browser_bar.custom_minimum_size = Vector2(0, 34)
	browser_bar.add_theme_constant_override("separation", 5)
	stack.add_child(browser_bar)
	for glyph in ["<", ">", "X", "R"]:
		var button := make_button(glyph, func() -> void: UIManager.toast(Loc.t("ui.homepage_editor_window.nur_vorschau_keine_externe_verbindung", "Nur Vorschau · keine externe Verbindung.")))
		button.custom_minimum_size = Vector2(34, 30)
		button.tooltip_text = _browser_tooltip(glyph)
		browser_bar.add_child(button)
	var location := LineEdit.new()
	location.name = "PreviewAddress"
	location.text = Loc.t("ui.homepage_editor_window.http_home_webwerk_de_s_index", "http://home.webwerk.de/~%s/index.html") % PlayerIdentity.player_name.to_lower()
	location.editable = false
	location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser_bar.add_child(location)

	_preview = HomepagePreview.new()
	_preview.name = "HomepageLivePreview"
	_preview.custom_minimum_size = Vector2(650, 490)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.cfg = _cfg
	stack.add_child(_preview)

	var status := HBoxContainer.new()
	status.add_child(Bezel.lcd_label(Loc.t("ui.homepage_editor_window.dokument_fertig", "DOKUMENT: FERTIG"), Color8(91, 220, 132), 11))
	var mode := Bezel.dim_label(Loc.t("ui.homepage_editor_window.800x600_256_farben_lokale_vorschau", "800x600 · 256 FARBEN · LOKALE VORSCHAU"), 11)
	mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(mode)
	stack.add_child(status)
	return panel


func _build_inspector() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color8(20, 23, 29), Color8(66, 71, 80)))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var inspector := VBoxContainer.new()
	inspector.custom_minimum_size = Vector2(305, 0)
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 7)
	scroll.add_child(inspector)

	inspector.add_child(_section(Loc.t("ui.homepage_editor_window.section_content", "INHALT"),
		Loc.t("ui.homepage_editor_window.section_content_note", "Titel und persoenliche Startseite")))
	inspector.add_child(_field(Loc.t("ui.homepage_editor_window.page_title", "SEITENTITEL"), str(_cfg.get("title", "")), 52, func(value: String) -> void:
		_cfg["title"] = value.strip_edges() if not value.strip_edges().is_empty() else Loc.t("ui.homepage_editor_window.my_homepage", "MEINE HOMEPAGE")
		_sync()))
	inspector.add_child(Bezel.dim_label(Loc.t("ui.homepage_editor_window.ueber_mich", "UEBER MICH"), 10))
	var about := TextEdit.new()
	about.text = str(_cfg.get("about", ""))
	about.custom_minimum_size = Vector2(0, 86)
	about.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	about.text_changed.connect(func() -> void:
		_cfg["about"] = about.text.left(360)
		_sync())
	inspector.add_child(about)

	inspector.add_child(HSeparator.new())
	inspector.add_child(_section(Loc.t("ui.homepage_editor_window.section_design", "DESIGN"),
		Loc.t("ui.homepage_editor_window.section_design_note", "Zeittypisch, aber lesbar")))
	var bg_grid := GridContainer.new()
	bg_grid.columns = 3
	bg_grid.add_theme_constant_override("h_separation", 5)
	for key: String in BGS:
		var button := make_button(_background_label(key), _set_bg.bind(key))
		button.custom_minimum_size = Vector2(94, 34)
		_bg_buttons[key] = button
		bg_grid.add_child(button)
	inspector.add_child(bg_grid)
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 7)
	for color in COLORS:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(48, 30)
		var normal := StyleBoxFlat.new()
		normal.bg_color = color
		normal.border_color = color.lightened(0.35)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(2)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.border_color = Color.WHITE
		swatch.add_theme_stylebox_override("normal", normal)
		swatch.add_theme_stylebox_override("hover", hover)
		swatch.tooltip_text = Loc.t("ui.homepage_editor_window.akzentfarbe", "Akzentfarbe")
		swatch.pressed.connect(func() -> void:
			_cfg["accent"] = color
			_sync())
		colors.add_child(swatch)
	inspector.add_child(colors)
	var layout_row := HBoxContainer.new()
	for key: String in ["classic", "portal"]:
		var button := make_button(_layout_label(key), _set_layout.bind(key))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_layout_buttons[key] = button
		layout_row.add_child(button)
	inspector.add_child(layout_row)

	inspector.add_child(HSeparator.new())
	inspector.add_child(_section(Loc.t("ui.homepage_editor_window.section_modules", "MODULE"),
		Loc.t("ui.homepage_editor_window.section_modules_note", "Jedes Jahr kommt ein echter Baustein hinzu")))
	var modules: Dictionary = _cfg.get("modules", {})
	var yearly := HomepageManager.yearly_module()
	for definition: Dictionary in HomepageManager.module_catalog():
		var id := str(definition.get("id", ""))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		var checkbox := CheckBox.new()
		checkbox.text = "%s%s" % [str(definition.get("label", id)),
			Loc.t("ui.homepage_editor_window.year_module_suffix", " · JAHRESMODUL") if not yearly.is_empty() and str(yearly.get("id", "")) == id else ""]
		checkbox.button_pressed = bool(modules.get(id, false))
		checkbox.toggled.connect(_toggle_module.bind(id))
		row.add_child(checkbox)
		var note := Bezel.dim_label(str(definition.get("note", "")), 11)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(note)
		inspector.add_child(row)
	var construction := CheckBox.new()
	construction.text = Loc.t("ui.homepage_editor_window.baustellen_banner_optional", "Baustellen-Banner (optional)")
	construction.button_pressed = bool((_cfg.get("features", {}) as Dictionary).get("construction", false))
	construction.toggled.connect(func(on: bool) -> void:
		var features: Dictionary = _cfg.get("features", {})
		features["construction"] = on
		_cfg["features"] = features
		_sync())
	inspector.add_child(construction)
	_set_bg(str(_cfg.get("bg", "stars")))
	_set_layout(str(_cfg.get("layout", "classic")))
	return panel


func _section(title_text: String, subtitle: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(Bezel.lcd_label(title_text, Palette.LCD_AMBER, 12))
	box.add_child(Bezel.dim_label(subtitle, 11))
	return box


func _field(label_text: String, default: String, max_length: int, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(Bezel.dim_label(label_text, 10))
	var edit := LineEdit.new()
	edit.text = default
	edit.max_length = max_length
	edit.text_changed.connect(on_change)
	box.add_child(edit)
	return box


func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(7)
	return style


func _browser_tooltip(glyph: String) -> String:
	match glyph:
		"<": return Loc.t("ui.homepage_editor_window.browser_back", "Zurueck")
		">": return Loc.t("ui.homepage_editor_window.browser_forward", "Vor")
		"X": return Loc.t("ui.homepage_editor_window.browser_stop", "Laden stoppen")
		"R": return Loc.t("ui.homepage_editor_window.browser_reload", "Neu laden")
	return glyph


func _background_label(background_id: String) -> String:
	match background_id:
		"stars": return Loc.t("ui.homepage_editor_window.background_stars", "NACHTHIMMEL")
		"bricks": return Loc.t("ui.homepage_editor_window.background_grid", "RASTER")
		"gradient": return Loc.t("ui.homepage_editor_window.background_gradient", "VERLAUF")
	return background_id.to_upper()


func _layout_label(layout_id: String) -> String:
	match layout_id:
		"classic": return Loc.t("ui.homepage_editor_window.layout_classic", "1998 KLASSISCH")
		"portal": return Loc.t("ui.homepage_editor_window.layout_portal", "1999 PORTAL")
	return layout_id.to_upper()


func _load_cfg() -> Dictionary:
	var existing := HomepageManager.get_cfg().duplicate(true)
	var defaults := {
		"title": PlayerIdentity.player_name.to_upper() + "S AMIGA-SEITE",
		"about": Loc.t("ui.homepage_preview.default_about", "Willkommen auf meiner privaten Amiga-Seite. Hier sammle ich Releases, Links und Neuigkeiten aus der Szene."),
		"bg": "stars", "accent": Color8(58, 211, 229),
		"layout": "portal" if TimeManager.year >= 1999 else "classic",
		"features": {"counter": true, "guestbook": true, "construction": false, "webring": true},
		"modules": {"counter": true, "guestbook": true, "webring": true,
			"links": true, "news": false, "downloads": false},
		"visitors": int(existing.get("visitors", 0)), "guestbook": existing.get("guestbook", []),
	}
	for key in defaults:
		if not existing.has(key):
			existing[key] = defaults[key]
	if existing.get("accent") is not Color:
		existing["accent"] = defaults["accent"]
	existing["year"] = TimeManager.year
	return existing


func _sync() -> void:
	_cfg["year"] = TimeManager.year
	_preview.cfg = _cfg
	_preview.queue_redraw()
	_update_status()


func _set_bg(key: String) -> void:
	_cfg["bg"] = key
	for id in _bg_buttons:
		(_bg_buttons[id] as Button).add_theme_color_override("font_color",
			Palette.LCD_GREEN if id == key else Palette.WHITE_SOFT)
	_sync()


func _set_layout(key: String) -> void:
	_cfg["layout"] = key
	for id in _layout_buttons:
		(_layout_buttons[id] as Button).add_theme_color_override("font_color",
			Palette.LCD_GREEN if id == key else Palette.WHITE_SOFT)
	_sync()


func _toggle_module(enabled: bool, id: String) -> void:
	var modules: Dictionary = _cfg.get("modules", {})
	modules[id] = enabled
	_cfg["modules"] = modules
	var features: Dictionary = _cfg.get("features", {})
	if id in ["counter", "guestbook", "webring"]:
		features[id] = enabled
	_cfg["features"] = features
	_sync()


func _update_status() -> void:
	if _status_label == null:
		return
	if HomepageManager.is_published():
		_status_label.text = Loc.t("ui.homepage_editor_window.online_d_besucher_update_d", "ONLINE · %d BESUCHER · UPDATE %d") % [
			HomepageManager.visitors(), TimeManager.year]
	else:
		_status_label.text = Loc.t("ui.homepage_editor_window.entwurf_noch_nicht_veroeffentlicht", "ENTWURF · NOCH NICHT VEROEFFENTLICHT")


func _publish() -> void:
	var result := HomepageManager.publish(_cfg)
	if bool(result.get("first", false)):
		UIManager.toast(Loc.t("ui.homepage_editor_window.deine_homepage_ist_online_d_ruf", "Deine Homepage ist online. +%d Ruf") % int(result.get("ruf", 0)))
	else:
		UIManager.toast(Loc.t("ui.homepage_editor_window.homepage_geprueft_aktualisiert_d_ruf", "Homepage geprueft und aktualisiert. +%d Ruf") % int(result.get("ruf", 0)))
	_update_status()
