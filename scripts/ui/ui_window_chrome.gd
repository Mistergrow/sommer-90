class_name UiWindowChrome
## Gemeinsame Materialbibliothek fuer die schwebenden Spielfenster. Der Stil
## folgt den fest eingebauten HUD-Instrumenten: schwarzes Metall, harte
## Pixelkanten, eine schmale Leuchtschiene und klar getrennte Bedienflaechen.
## Dadurch sehen JOBS, ORTE, INVENTAR usw. wie Teile derselben Spielkonsole aus
## und nicht wie Dialoge des Host-Betriebssystems.

const SHELL_BG := Color8(8, 10, 13)
const SURFACE_BG := Color8(13, 15, 18)
const RECESS_BG := Color8(5, 8, 11)
const TITLE_BG := Color8(7, 14, 19)
const EDGE_OUTER := Color8(42, 45, 49)
const EDGE_INNER := Color8(92, 96, 98)


static func alpha(color: Color, value: float) -> Color:
	return Color(color.r, color.g, color.b, value)


static func flat_box(background: Color, border: Color, width: int = 1,
		margin_x: float = 0.0, margin_y: float = 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.anti_aliasing = false
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(1)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


static func shell_box() -> StyleBoxFlat:
	var box := flat_box(SHELL_BG, EDGE_INNER, 2)
	# Die unterschiedlich schweren Kanten simulieren den eingelassenen
	# Metallrahmen der permanenten HUD-Panels ohne weiche Fensterschatten.
	box.border_width_top = 2
	box.border_width_left = 2
	box.border_width_right = 3
	box.border_width_bottom = 3
	return box


static func inner_rail_box(accent: Color, active: bool) -> StyleBoxFlat:
	var rail := accent if active else Color8(46, 55, 60)
	return flat_box(Color(0, 0, 0, 0), alpha(rail, 0.72 if active else 0.55), 1)


static func title_box(accent: Color, active: bool) -> StyleBoxFlat:
	var border := alpha(accent, 0.78) if active else Color8(50, 57, 60)
	var box := flat_box(TITLE_BG if active else Color8(11, 13, 15), border, 1)
	box.border_width_bottom = 2
	return box


static func surface_box(margin_x: float = 7.0, margin_y: float = 6.0) -> StyleBoxFlat:
	return flat_box(SURFACE_BG, EDGE_OUTER, 1, margin_x, margin_y)


static func recess_box(margin_x: float = 6.0, margin_y: float = 4.0) -> StyleBoxFlat:
	return flat_box(RECESS_BG, Color8(48, 54, 58), 1, margin_x, margin_y)


static func key_box(state: String, accent: Color = Palette.LCD_CYAN) -> StyleBoxFlat:
	var background := Color8(29, 31, 35)
	var border := Color8(68, 72, 76)
	match state:
		"hover":
			background = Color8(20, 34, 40)
			border = accent
		"pressed":
			background = Color8(7, 18, 23)
			border = Palette.LCD_AMBER
		"disabled":
			background = Color8(20, 21, 23)
			border = Color8(40, 42, 44)
		"focus":
			background = Color(0, 0, 0, 0)
			border = Palette.LCD_AMBER
	var box := flat_box(background, border, 1, 9.0, 5.0)
	# Tasten besitzen eine helle obere und eine schwere untere Kante. Das liest
	# sich als physische Bedienflaeche statt als moderner Flat-UI-Button.
	if state not in ["focus", "disabled"]:
		box.border_width_top = 1
		box.border_width_bottom = 2
	return box


static func selection_box(accent: Color = Palette.LCD_CYAN) -> StyleBoxFlat:
	var box := flat_box(Color8(14, 37, 48), accent, 1, 4.0, 2.0)
	box.border_width_left = 3
	return box


static func close_box(state: String) -> StyleBoxFlat:
	var background := Color8(35, 17, 18)
	var border := Color8(158, 54, 50)
	if state == "hover":
		background = Color8(73, 23, 23)
		border = Color8(244, 103, 87)
	elif state == "pressed":
		background = Color8(18, 8, 9)
		border = Palette.LCD_AMBER
	return flat_box(background, border, 1, 1.0, 0.0)
