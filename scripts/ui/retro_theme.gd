class_name RetroTheme
## Baut das dunkle Bezel-Theme (Referenz: Mockup — dunkle Panels, helle
## Kanten, LCD-Farbwerte). Wird in main.gd der Wurzel zugewiesen und
## vererbt sich auf alle Controls.


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 12
	var ui_font := load("res://assets/fonts/VT323_UI.ttf") as Font
	if ui_font != null:
		theme.default_font = ui_font
		for type_name in ["Label", "Button", "LineEdit", "ItemList", "TooltipLabel"]:
			theme.set_font("font", type_name, ui_font)

	# --- Buttons: dunkle Slots mit heller Kante bei Hover ---
	theme.set_stylebox("normal", "Button", _box(Color8(20, 20, 20), Color8(58, 58, 56), 2, 7.0, 5.0))
	theme.set_stylebox("hover", "Button", _box(Color8(31, 31, 30), Color8(132, 132, 124), 2, 7.0, 5.0))
	theme.set_stylebox("pressed", "Button", _box(Color8(8, 8, 9), Palette.LCD_AMBER, 2, 7.0, 5.0))
	theme.set_stylebox("disabled", "Button", _box(Color8(15, 15, 15), Palette.UI_BORDER_DARK, 2, 7.0, 5.0))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Palette.UI_TEXT)
	theme.set_color("font_hover_color", "Button", Palette.WHITE)
	theme.set_color("font_pressed_color", "Button", Palette.LCD_AMBER)
	theme.set_color("font_disabled_color", "Button", Palette.UI_TEXT_DISABLED)
	theme.set_constant("outline_size", "Button", 1)
	theme.set_color("font_outline_color", "Button", Palette.BLACK)

	# --- Panels ---
	theme.set_stylebox("panel", "Panel", _box(Color8(16, 16, 16), Color8(57, 57, 54), 2, 8.0, 5.0))
	theme.set_stylebox("panel", "PanelContainer", _box(Color8(16, 16, 16), Color8(57, 57, 54), 2, 8.0, 5.0))

	# --- Labels ---
	theme.set_color("font_color", "Label", Palette.UI_TEXT)
	theme.set_constant("outline_size", "Label", 1)
	theme.set_color("font_outline_color", "Label", Palette.BLACK)

	# --- Eingabefelder ---
	theme.set_stylebox("normal", "LineEdit", _box(Palette.UI_BG, Palette.UI_BORDER_DARK, 2))
	theme.set_stylebox("focus", "LineEdit", _box(Palette.UI_BG, Palette.LCD_AMBER, 2))
	theme.set_color("font_color", "LineEdit", Palette.UI_TEXT)
	theme.set_color("caret_color", "LineEdit", Palette.LCD_AMBER)

	# --- Listen ---
	theme.set_stylebox("panel", "ItemList", _box(Palette.UI_BG, Palette.UI_BORDER_DARK, 2))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("selected", "ItemList", _box(Palette.UI_PANEL_LIGHT, Palette.UI_BORDER, 2))
	theme.set_stylebox("selected_focus", "ItemList", _box(Palette.UI_PANEL_LIGHT, Palette.UI_BORDER, 2))
	theme.set_stylebox("hovered", "ItemList", _box(Palette.UI_PANEL, Palette.UI_BORDER_DARK, 2))
	theme.set_color("font_color", "ItemList", Palette.UI_TEXT)
	theme.set_color("font_selected_color", "ItemList", Palette.WHITE)

	# --- Fortschrittsbalken (Farbe pro Instanz überschreibbar) ---
	theme.set_stylebox("background", "ProgressBar", _box(Color8(8, 8, 8), Color8(37, 37, 36), 1, 1.0, 1.0))
	theme.set_stylebox("fill", "ProgressBar", _box(Palette.LCD_AMBER, Palette.LCD_AMBER, 0, 1.0, 1.0))

	# --- Tooltips im 90er-Stil ---
	theme.set_stylebox("panel", "TooltipPanel", _box(Palette.UI_BG, Palette.UI_BORDER, 2))
	theme.set_color("font_color", "TooltipLabel", Palette.UI_TEXT)

	# --- Scrollbalken schmal ---
	theme.set_stylebox("scroll", "VScrollBar", _box(Palette.UI_BG, Palette.UI_BORDER_DARK, 1))
	theme.set_stylebox("grabber", "VScrollBar", _box(Palette.UI_PANEL_LIGHT, Palette.UI_BORDER_DARK, 1))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(Palette.UI_BORDER, Palette.UI_BORDER, 1))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _box(Palette.UI_BORDER, Palette.UI_BORDER, 1))

	return theme


static func _box(bg: Color, border: Color, border_width: int = 1,
		h_margin: float = 6.0, v_margin: float = 3.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	# Wie in UITheme._sb(): keine Kantenglättung im Pixel-Look. Der Bezel
	# (bezel.gd) behält sie bewusst — dort ahmt der Radius rundes Gehäuseplastik nach.
	box.anti_aliasing = false
	box.corner_radius_top_left = 1
	box.corner_radius_top_right = 1
	box.corner_radius_bottom_left = 1
	box.corner_radius_bottom_right = 1
	box.set_border_width_all(border_width)
	box.content_margin_left = h_margin
	box.content_margin_right = h_margin
	box.content_margin_top = v_margin
	box.content_margin_bottom = v_margin
	return box
