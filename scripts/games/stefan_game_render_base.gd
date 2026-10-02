extends RefCounted
## Zeichen-Grundlage der Stefan-Anthologie: Palette, Topaz-Schrift, Lauf-Tabellen
## und die Primitive, auf denen alle anderen Renderer-Teile aufsetzen.
##
## Aufgeteilt aus stefan_game_renderer.gd (Zeilenbudget). Diese Datei laedt
## bewusst NICHTS aus dem eigenen Paket, damit die preload-Kette linear bleibt:
##   Base -> Sprites -> Modes/Screens -> stefan_game_renderer (Fassade).
## Kein class_name: Pfad-preload vermeidet das Klassen-Cache-Race mit dem
## laufenden Editor.

const Catalog := preload("res://scripts/games/stefan_game_catalog.gd")

const INK := Color8(4, 8, 16)
const NIGHT := Color8(8, 17, 30)
const PANEL := Color8(17, 32, 48)
const STEEL := Color8(50, 70, 84)
const STEEL_LIT := Color8(96, 119, 126)
const PAPER := Color8(231, 229, 199)
const AMBER := Color8(245, 170, 52)
const RED := Color8(226, 70, 69)
const GREEN := Color8(91, 217, 121)
const CYAN := Color8(70, 213, 225)
const BLUE := Color8(68, 111, 197)
const VIOLET := Color8(162, 97, 206)
const TOPAZ: Font = preload("res://assets/fonts/Topaz_a500_ui.ttf")

# Zwölf handgesetzte Samples eines vollständigen Schritts. Frühe ECS-Titel
# verwenden sechs davon, die EHB-Phase acht und AGA alle zwölf. So bleibt die
# Animation dieselbe Bewegung, gewinnt über die Kampagnenjahre aber sichtbar
# an Zwischenphasen statt einfach nur schneller abgespielt zu werden.
const RUN_LEG_A := [-4, -4, -3, -1, 1, 3, 4, 4, 3, 1, -1, -3]
const RUN_LEG_B := [4, 4, 3, 1, -1, -3, -4, -4, -3, -1, 1, 3]
const RUN_ARM_A := [3, 4, 4, 3, 1, -2, -3, -4, -4, -3, -1, 2]
const RUN_ARM_B := [-3, -4, -4, -3, -1, 2, 3, 4, 4, 3, 1, -2]


static func accent(definition: Dictionary) -> Color:
	return Color.from_string(str(definition.get("accent", "#63d8e8")), CYAN)
static func danger(definition: Dictionary) -> Color:
	return Color.from_string(str(definition.get("danger", "#ef6658")), RED)
static func text(canvas: CanvasItem, value: String, position: Vector2, size: int,
		color := PAPER, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		outline := 1) -> void:
	var p := position.floor()
	if outline > 0:
		canvas.draw_string_outline(TOPAZ, p, value, align, width, size, outline, INK)
	canvas.draw_string(TOPAZ, p, value, align, width, size, color)
static func wrapped(canvas: CanvasItem, value: String, rect: Rect2, size: int,
		color := PAPER, line_height := 11.0, max_lines := 8) -> void:
	var words := value.replace("\n", " \n ").split(" ", false)
	var line := ""
	var y := rect.position.y + size
	var lines := 0
	for raw: String in words:
		if raw == "\n":
			text(canvas, line, Vector2(rect.position.x, y), size, color)
			line = ""; y += line_height; lines += 1
			continue
		var candidate := raw if line.is_empty() else line + " " + raw
		if TOPAZ.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x:
			text(canvas, line, Vector2(rect.position.x, y), size, color)
			line = raw; y += line_height; lines += 1
			if lines >= max_lines:
				break
		else:
			line = candidate
	if not line.is_empty() and lines < max_lines:
		text(canvas, line, Vector2(rect.position.x, y), size, color)
static func draw_atlas(canvas: CanvasItem, texture: Texture2D, definition: Dictionary,
		rect: Rect2, modulate := Color.WHITE) -> void:
	if texture == null:
		canvas.draw_rect(rect, NIGHT)
		return
	var source := Catalog.atlas_region(definition, texture.get_size())
	var source_ratio := source.size.x / maxf(1.0, source.size.y)
	var target_ratio := rect.size.x / maxf(1.0, rect.size.y)
	if source_ratio > target_ratio:
		var width := source.size.y * target_ratio
		source.position.x += (source.size.x - width) * 0.5
		source.size.x = width
	else:
		var height := source.size.x / target_ratio
		source.position.y += (source.size.y - height) * 0.5
		source.size.y = height
	canvas.draw_texture_rect_region(texture, rect, source, modulate)
static func bevel(canvas: CanvasItem, rect: Rect2, fill: Color, edge := STEEL,
		bright := STEEL_LIT) -> void:
	canvas.draw_rect(rect, fill)
	canvas.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), bright, 1)
	canvas.draw_line(rect.position, Vector2(rect.position.x, rect.end.y), bright, 1)
	canvas.draw_line(Vector2(rect.position.x, rect.end.y), rect.end, edge.darkened(0.45), 1)
	canvas.draw_line(Vector2(rect.end.x, rect.position.y), rect.end, edge.darkened(0.45), 1)
static func pixel_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	## Alle Laufzeit-Sprites bleiben auf dem logischen Pixelraster. Dadurch gibt
	## es beim Skalieren im Amiga-Monitor weder Subpixel-Flimmern noch weiche
	## Kanten, selbst wenn die Simulation mit Float-Koordinaten arbeitet.
	canvas.draw_rect(Rect2(rect.position.floor(), rect.size.floor()), color)
static func pixel_polygon(canvas: CanvasItem, points: PackedVector2Array, fill: Color,
		outline := INK) -> void:
	var pixel_points := PackedVector2Array()
	for point: Vector2 in points:
		pixel_points.append(point.floor())
	canvas.draw_colored_polygon(pixel_points, fill)
	if pixel_points.size() > 1:
		var closed := pixel_points.duplicate()
		closed.append(pixel_points[0])
		canvas.draw_polyline(closed, outline, 1.0, false)
static func _hardware_tier(definition: Dictionary) -> int:
	var year := int(definition.get("year", 1991))
	if year >= 1996:
		return 2 # AGA: mehr Farbabstufungen, Parallax und Animationsphasen
	if year >= 1993:
		return 1 # ECS: zusaetzliche Scrolling-/Overscan-Freiheit
	return 0 # OCS: strenge 32-Farb-Sprache
static func _hardware_label(definition: Dictionary) -> String:
	match _hardware_tier(definition):
		2: return "AGA 128"
		1: return "ECS 32"
		_: return "OCS 32"
static func _pixel_disc(canvas: CanvasItem, center: Vector2, radius: int,
		fill: Color, highlight := Color(-1, -1, -1, -1)) -> void:
	var p := center.floor()
	var rows: Array[Vector2i]
	match radius:
		1: rows = [Vector2i(-1, 3), Vector2i(-1, 3), Vector2i(-1, 3)]
		2: rows = [Vector2i(-1, 3), Vector2i(-2, 5), Vector2i(-2, 5),
			Vector2i(-2, 5), Vector2i(-1, 3)]
		3: rows = [Vector2i(-1, 3), Vector2i(-2, 5), Vector2i(-3, 7),
			Vector2i(-3, 7), Vector2i(-3, 7), Vector2i(-2, 5), Vector2i(-1, 3)]
		_:
			rows = [Vector2i(-2, 5), Vector2i(-3, 7), Vector2i(-4, 9),
				Vector2i(-4, 9), Vector2i(-4, 9), Vector2i(-4, 9),
				Vector2i(-4, 9), Vector2i(-3, 7), Vector2i(-2, 5)]
	var y0 := -floori(float(rows.size()) * 0.5)
	for row_index in rows.size():
		var row := rows[row_index]
		pixel_rect(canvas, Rect2(p + Vector2(row.x, y0 + row_index),
			Vector2(row.y, 1)), fill)
	if highlight.a >= 0.0:
		pixel_rect(canvas, Rect2(p + Vector2(-1, y0 + 1), Vector2(2, 1)), highlight)
		pixel_rect(canvas, Rect2(p + Vector2(-2, y0 + 2), Vector2(1, 2)), highlight)
static func _pixel_diamond_outline(canvas: CanvasItem, center: Vector2, radius: int,
		color: Color) -> void:
	var p := center.floor()
	for offset in radius:
		var span := radius - offset
		pixel_rect(canvas, Rect2(p + Vector2(-span, -offset), Vector2(1, 1)), color)
		pixel_rect(canvas, Rect2(p + Vector2(span, -offset), Vector2(1, 1)), color)
		pixel_rect(canvas, Rect2(p + Vector2(-span, offset), Vector2(1, 1)), color)
		pixel_rect(canvas, Rect2(p + Vector2(span, offset), Vector2(1, 1)), color)
static func scanlines(canvas: CanvasItem, alpha := 0.10) -> void:
	for y in range(1, 200, 2):
		canvas.draw_line(Vector2(0, y), Vector2(320, y), Color(0, 0, 0, alpha), 1)
