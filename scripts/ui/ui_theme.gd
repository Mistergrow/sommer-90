class_name UITheme
## Zentrales Sommer-UI-Theme. Die Controls sind keine Host-OS-Widgets, sondern
## eingelassene Tasten, Displays und Listen derselben dunklen Spielkonsole wie
## Top-Bar, Sidebar und Bottom-Bar. RetroWindow vererbt dieses Theme an jedes
## Kindfenster, damit auch alte Dialoge ohne Einzelfall-CSS konsistent werden.

const FONT_PATH := "res://assets/fonts/VT323_UI.ttf"
const Chrome := preload("res://scripts/ui/ui_window_chrome.gd")

static var _theme: Theme = null


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	var font: Font = load(FONT_PATH)
	if font != null:
		theme.default_font = font
	theme.default_font_size = 16
	_style_buttons(theme)
	_style_list(theme)
	_style_panels(theme)
	_style_lineedit(theme)
	_style_scrollbars(theme)
	_style_progress(theme)
	_style_tabs(theme)
	_style_editors(theme)
	_style_ranges(theme)
	_style_toggles(theme)
	_style_text(theme)
	_theme = theme
	return theme


## Kantiger Pixel-Baustein fuer Theme-Controls, die keinen spezialisierten
## Chrome-Baustein benoetigen.
static func _sb(background: Color, border: Color, width: int = 1, radius: int = 1,
		margin_x: int = 8, margin_y: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.anti_aliasing = false
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


static func _style_buttons(theme: Theme) -> void:
	var normal := Chrome.key_box("normal")
	var hover := Chrome.key_box("hover")
	var pressed := Chrome.key_box("pressed")
	var disabled := Chrome.key_box("disabled")
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, Chrome.key_box("focus"))
		theme.set_color("font_color", type, Palette.UI_TEXT)
		theme.set_color("font_hover_color", type, Palette.WHITE_SOFT)
		theme.set_color("font_pressed_color", type, Palette.LCD_AMBER)
		theme.set_color("font_disabled_color", type, Palette.UI_TEXT_DISABLED)
		theme.set_constant("outline_size", type, 1)
		theme.set_color("font_outline_color", type, Palette.BLACK)
		theme.set_font_size("font_size", type, 16)


static func _style_list(theme: Theme) -> void:
	theme.set_stylebox("panel", "ItemList", Chrome.recess_box(4.0, 4.0))
	theme.set_stylebox("focus", "ItemList",
		_sb(Color(0, 0, 0, 0), Palette.LCD_AMBER, 1, 1, 0, 0))
	var selected := Chrome.selection_box()
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList",
		_sb(Color8(18, 29, 34), Color8(18, 29, 34), 0, 1, 3, 2))
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", Palette.UI_TEXT)
	theme.set_color("font_selected_color", "ItemList", Palette.WHITE_SOFT)
	theme.set_constant("v_separation", "ItemList", 3)
	theme.set_constant("h_separation", "ItemList", 4)


static func _style_panels(theme: Theme) -> void:
	var panel := Chrome.surface_box()
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PanelContainer", panel)


static func _style_lineedit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", Chrome.recess_box())
	theme.set_stylebox("focus", "LineEdit",
		_sb(Chrome.RECESS_BG, Palette.LCD_AMBER, 1, 1, 6, 4))
	theme.set_color("font_color", "LineEdit", Palette.UI_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Palette.UI_TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", Palette.LCD_AMBER)
	theme.set_color("selection_color", "LineEdit", Color(Palette.LCD_CYAN, 0.42))


static func _style_scrollbars(theme: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type,
			_sb(Color8(5, 8, 10), Color8(35, 42, 45), 1, 1, 0, 0))
		theme.set_stylebox("scroll_focus", type,
			_sb(Color8(5, 8, 10), Palette.LCD_CYAN, 1, 1, 0, 0))
		theme.set_stylebox("grabber", type,
			_sb(Color8(57, 67, 71), Color8(94, 104, 106), 1, 1, 0, 0))
		theme.set_stylebox("grabber_highlight", type,
			_sb(Color8(20, 61, 72), Palette.LCD_CYAN, 1, 1, 0, 0))
		theme.set_stylebox("grabber_pressed", type,
			_sb(Color8(68, 43, 11), Palette.LCD_AMBER, 1, 1, 0, 0))


static func _style_progress(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar",
		_sb(Color8(5, 8, 10), Color8(43, 49, 51), 1, 1, 0, 0))
	theme.set_stylebox("fill", "ProgressBar",
		_sb(Palette.LCD_GREEN, Palette.LCD_GREEN.darkened(0.35), 1, 0, 0, 0))
	theme.set_color("font_color", "ProgressBar", Palette.UI_TEXT)


static func _style_tabs(theme: Theme) -> void:
	for type in ["TabBar", "TabContainer"]:
		theme.set_stylebox("tab_selected", type, Chrome.selection_box(Palette.LCD_AMBER))
		theme.set_stylebox("tab_unselected", type, Chrome.key_box("normal"))
		theme.set_stylebox("tab_hovered", type, Chrome.key_box("hover"))
		theme.set_color("font_selected_color", type, Palette.LCD_AMBER)
		theme.set_color("font_unselected_color", type, Palette.UI_TEXT_DIM)
		theme.set_color("font_hovered_color", type, Palette.UI_TEXT)


static func _style_editors(theme: Theme) -> void:
	for type in ["TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", type, Chrome.recess_box(7.0, 6.0))
		theme.set_stylebox("focus", type,
			_sb(Chrome.RECESS_BG, Palette.LCD_CYAN, 1, 1, 7, 6))
		theme.set_stylebox("read_only", type,
			_sb(Color8(11, 12, 14), Color8(37, 40, 42), 1, 1, 7, 6))
		theme.set_color("font_color", type, Palette.UI_TEXT)
		theme.set_color("font_readonly_color", type, Palette.UI_TEXT_DIM)
		theme.set_color("caret_color", type, Palette.LCD_AMBER)
		theme.set_color("selection_color", type, Color(Palette.LCD_CYAN, 0.38))


static func _style_ranges(theme: Theme) -> void:
	for type in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", type,
			_sb(Color8(6, 8, 10), Color8(48, 54, 56), 1, 1, 0, 0))
		theme.set_stylebox("grabber_area", type,
			_sb(Color8(12, 35, 43), Palette.LCD_CYAN, 1, 1, 0, 0))
		theme.set_stylebox("grabber_area_highlight", type,
			_sb(Color8(38, 31, 12), Palette.LCD_AMBER, 1, 1, 0, 0))


static func _style_toggles(theme: Theme) -> void:
	# Toggle-Typen erben dieselbe physische Tastenfamilie. Die funktionalen
	# Haken-/Schaltericons bleiben erhalten, sitzen aber nicht mehr auf einem
	# fremden hellgrauen Desktop-Hintergrund.
	for type in ["CheckBox", "CheckButton"]:
		theme.set_stylebox("normal", type, Chrome.key_box("normal"))
		theme.set_stylebox("hover", type, Chrome.key_box("hover"))
		theme.set_stylebox("pressed", type, Chrome.key_box("pressed"))
		theme.set_stylebox("disabled", type, Chrome.key_box("disabled"))
		theme.set_stylebox("focus", type, Chrome.key_box("focus"))
		theme.set_color("font_color", type, Palette.UI_TEXT)
		theme.set_color("font_hover_color", type, Palette.WHITE_SOFT)
		theme.set_color("font_pressed_color", type, Palette.LCD_AMBER)
		theme.set_color("font_disabled_color", type, Palette.UI_TEXT_DISABLED)


static func _style_text(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Palette.UI_TEXT)
	theme.set_constant("outline_size", "Label", 1)
	theme.set_color("font_outline_color", "Label", Palette.BLACK)
	theme.set_color("default_color", "RichTextLabel", Palette.UI_TEXT)
	theme.set_color("font_outline_color", "RichTextLabel", Palette.BLACK)
	theme.set_constant("outline_size", "RichTextLabel", 1)
	theme.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
