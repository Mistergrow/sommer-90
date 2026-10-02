extends Control
## RoomAgeOverlay — sichtbare, zurückhaltende Dekadenentwicklung des Zimmers.
##
## Das Basisfoto bleibt unverändert. Wandpatina, entfernte Posterabdrücke,
## kleine Stecknadellöcher und Gebrauchsspuren auf der Tischplatte werden als
## eigene Weltlage zwischen Fernplatte und Hardware gezeichnet. Dadurch altern
## weder Amiga noch Monitor künstlich mit, und alle Spuren folgen derselben
## 2,5D-Projektion wie der Raum.

const ERA_FRESH := "fresh"
const ERA_LIVED_IN := "lived_in"
const ERA_STUDIO := "studio"
const ERA_ARCHIVE := "archive"

const ERA_BY_YEAR := {
	1990: ERA_FRESH,
	1991: ERA_FRESH,
	1992: ERA_FRESH,
	1993: ERA_LIVED_IN,
	1994: ERA_LIVED_IN,
	1995: ERA_LIVED_IN,
	1996: ERA_STUDIO,
	1997: ERA_STUDIO,
	1998: ERA_ARCHIVE,
	1999: ERA_ARCHIVE,
}

var comp: Control = null
var _year := 1992


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_year()


func refresh_year(explicit_year := -1) -> void:
	_year = explicit_year if explicit_year >= 1990 else _current_year()
	queue_redraw()


func _current_year() -> int:
	if Engine.is_editor_hint() or not is_instance_valid(comp):
		return 1992
	return int(TimeManager.year)


static func era_for_year(year: int) -> String:
	return str(ERA_BY_YEAR.get(clampi(year, 1990, 1999), ERA_ARCHIVE))


## Stabiler Datenvertrag für Preview, Regression und spätere handgemalte
## AGE_*-Texturen. Die Werte steuern nur die Intensität, nie den Besitzstand.
static func visual_contract_for_year(year: int) -> Dictionary:
	var era := era_for_year(year)
	match era:
		ERA_LIVED_IN:
			return {"era": era, "wall_fade": 0.035, "pin_marks": 3,
				"poster_ghosts": 0, "desk_wear": 1}
		ERA_STUDIO:
			return {"era": era, "wall_fade": 0.065, "pin_marks": 6,
				"poster_ghosts": 1, "desk_wear": 2}
		ERA_ARCHIVE:
			return {"era": era, "wall_fade": 0.09, "pin_marks": 9,
				"poster_ghosts": 2, "desk_wear": 3}
		_:
			return {"era": ERA_FRESH, "wall_fade": 0.0, "pin_marks": 0,
				"poster_ghosts": 0, "desk_wear": 0}


func _draw() -> void:
	if comp == null or bool(comp.get("edit_mode")):
		return
	var contract := visual_contract_for_year(_year)
	var fade := float(contract["wall_fade"])
	if fade <= 0.0:
		return

	# Sonnengebleichte Wandflächen. Die großen Polygone sind extrem transparent;
	# erst die Kombination mit Gebrauchsspuren macht den Fortschritt lesbar.
	_draw_master_polygon([
		Vector2(195, 150), Vector2(745, 150),
		Vector2(715, 600), Vector2(215, 620),
	], Color(0.72, 0.60, 0.43, fade))
	_draw_master_polygon([
		Vector2(1260, 175), Vector2(1810, 175),
		Vector2(1790, 600), Vector2(1285, 590),
	], Color(0.67, 0.55, 0.39, fade * 0.8))

	var pin_positions := [
		Vector2(392, 318), Vector2(420, 347), Vector2(447, 316),
		Vector2(1320, 332), Vector2(1354, 354), Vector2(1390, 326),
		Vector2(1525, 404), Vector2(1560, 390), Vector2(1592, 418),
	]
	for i in int(contract["pin_marks"]):
		var p := _project(pin_positions[i], "base")
		var radius := maxf(1.0, _scale() * (1.8 if i % 3 == 0 else 1.25))
		draw_circle(p, radius, Color(0.20, 0.13, 0.08, 0.34))

	var poster_ghosts := int(contract["poster_ghosts"])
	if poster_ghosts >= 1:
		_draw_ghost_rect(Rect2(1275, 286, 138, 178), fade * 1.75)
	if poster_ghosts >= 2:
		_draw_ghost_rect(Rect2(304, 248, 122, 154), fade * 1.45)

	# Tischringe und feine Gebrauchslinien liegen in derselben Weltlage unter
	# allen Geräten. Freie Holzbereiche altern, Hardware bleibt sauber lesbar.
	var wear := int(contract["desk_wear"])
	if wear >= 1:
		_draw_desk_ring(Vector2(690, 758), 22.0, fade * 2.4)
	if wear >= 2:
		_draw_scratch(Vector2(1370, 768), Vector2(1465, 754), fade * 2.6)
	if wear >= 3:
		_draw_desk_ring(Vector2(1510, 786), 16.0, fade * 2.1)
		_draw_scratch(Vector2(760, 805), Vector2(838, 811), fade * 2.2)


func _draw_master_polygon(points: Array, color: Color) -> void:
	var screen := PackedVector2Array()
	for point: Vector2 in points:
		screen.append(_project(point, "base"))
	if screen.size() >= 3:
		draw_colored_polygon(screen, color)


func _draw_ghost_rect(master_rect: Rect2, alpha: float) -> void:
	# Keine perfekte Kontur: Ein abgenommenes Poster hinterlässt eine leicht
	# ungleichmäßig hellere Tapete und nur einzelne Klebespuren, keinen UI-Rahmen.
	var master_points := [
		master_rect.position + Vector2(2, 4),
		Vector2(master_rect.end.x - 4, master_rect.position.y + 1),
		master_rect.end - Vector2(1, 5),
		Vector2(master_rect.position.x + 5, master_rect.end.y - 2),
	]
	var screen := PackedVector2Array()
	for point: Vector2 in master_points:
		screen.append(_project(point, "base"))
	var top_left := screen[0]
	var top_right := screen[1]
	var bottom_right := screen[2]
	var bottom_left := screen[3]
	var width := top_right.x - top_left.x
	var line_width := maxf(1.0, _scale() * 2.0)
	var trace := Color(0.73, 0.61, 0.43, alpha * 0.28)
	# Nur vier kurze, versetzte Fragmente der staubigen Kante bleiben stehen.
	draw_line(top_left.lerp(top_right, 0.10), top_left.lerp(top_right, 0.29),
		trace, line_width, true)
	draw_line(top_left.lerp(top_right, 0.68), top_left.lerp(top_right, 0.82),
		trace, line_width * 1.4, true)
	draw_line(bottom_left, bottom_left + Vector2(width * 0.12, -1),
		trace, line_width, true)
	draw_line(bottom_right - Vector2(width * 0.08, 0), bottom_right,
		trace, line_width, true)


func _draw_desk_ring(master_center: Vector2, master_radius: float, alpha: float) -> void:
	var center := _project(master_center, "desk")
	var radius := master_radius * _scale()
	draw_arc(center, radius, 0.18, TAU - 0.42, 40,
		Color(0.28, 0.16, 0.08, alpha), maxf(1.0, _scale() * 1.45), true)


func _draw_scratch(master_from: Vector2, master_to: Vector2, alpha: float) -> void:
	var start := _project(master_from, "desk")
	var finish := _project(master_to, "desk")
	draw_line(start, finish, Color(0.30, 0.18, 0.09, alpha),
		maxf(1.0, _scale()), true)
	draw_line(start + Vector2(0, 3) * _scale(),
		finish + Vector2(0, 2) * _scale(),
		Color(0.88, 0.70, 0.44, alpha * 0.45), maxf(1.0, _scale()), true)


func _project(master_point: Vector2, depth_group: String) -> Vector2:
	if comp != null and comp.has_method("project_master_point"):
		return comp.project_master_point(master_point, depth_group)
	var transform: Dictionary = comp._master_transform()
	return Vector2(transform["offset"]) + master_point * float(transform["scale"])


func _scale() -> float:
	if comp == null:
		return 1.0
	return float(comp._master_transform()["scale"])
