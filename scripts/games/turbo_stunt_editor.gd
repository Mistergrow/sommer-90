class_name TurboStuntEditor
extends RefCounted
## Vollstaendiger In-Game-Kurseditor fuer Turbo Stunt Deluxe.

const Track := preload("res://scripts/games/turbo_stunt_track.gd")
const StuntRenderer := preload("res://scripts/games/turbo_stunt_renderer.gd")
const GRID_ORIGIN := Vector2(7, 23)
const CELL := 7.0
const GRID_RECT := Rect2(GRID_ORIGIN, Vector2(Track.WIDTH, Track.HEIGHT) * CELL)
const PALETTE_X := 181.0

const C_BG := Color8(16, 22, 29)
const C_GRID := Color8(35, 49, 59)
const C_ROAD := Color8(91, 102, 105)
const C_EDGE := Color8(28, 31, 39)
const C_WHITE := StuntRenderer.C_WHITE
const C_CREAM := StuntRenderer.C_CREAM
const C_AMBER := StuntRenderer.C_AMBER
const C_ORANGE := StuntRenderer.C_ORANGE
const C_RED := StuntRenderer.C_RED
const C_CYAN := StuntRenderer.C_CYAN
const C_BLUE := StuntRenderer.C_BLUE
const C_GREEN := StuntRenderer.C_GREEN

var track: Dictionary = {}
var cursor := Vector2i(4, 3)
var selected_piece: int = Track.Piece.STRAIGHT
var rotation := 1
var generation_seed := 1990
var message := "KURS BAUEN ODER G GENERIEREN"
var validation: Dictionary = {}
var dirty := false


func begin(source: Dictionary = {}) -> void:
	if source.is_empty():
		track = Track.generated(generation_seed, 7, "EIGENER KURS", "custom")
	else:
		track = Track.clone(source)
		generation_seed = int(track.get("seed", generation_seed))
	cursor = Vector2i(4, 3)
	selected_piece = Track.Piece.STRAIGHT
	rotation = 1
	dirty = false
	_check()


func current_track() -> Dictionary:
	return Track.clone(track)


func handle_key(keycode: Key) -> String:
	match keycode:
		KEY_UP, KEY_W: cursor.y = maxi(0, cursor.y - 1)
		KEY_DOWN: cursor.y = mini(Track.HEIGHT - 1, cursor.y + 1)
		KEY_LEFT, KEY_A: cursor.x = maxi(0, cursor.x - 1)
		KEY_RIGHT, KEY_D: cursor.x = mini(Track.WIDTH - 1, cursor.x + 1)
		KEY_Q:
			rotation = posmod(rotation - 1, 4)
			message = "DREHUNG %d GRAD" % (rotation * 90)
		KEY_E, KEY_R:
			rotation = posmod(rotation + 1, 4)
			message = "DREHUNG %d GRAD" % (rotation * 90)
		KEY_TAB:
			selected_piece = Track.Piece.START + posmod(selected_piece - Track.Piece.START + 1,
				Track.Piece.DIRT - Track.Piece.START + 1)
			message = "%s AUSGEWAEHLT" % Track.PIECE_NAMES[selected_piece]
		KEY_SPACE:
			_place(cursor)
		KEY_DELETE, KEY_BACKSPACE:
			_erase(cursor)
		KEY_G:
			generation_seed += 977
			track = Track.generated(generation_seed, 8, "SEED %06d" % generation_seed, "custom")
			dirty = true
			_check()
			message = "KURS AUS SEED %06d GENERIERT" % generation_seed
		KEY_N:
			track = Track.empty("NEUER KURS", "custom")
			dirty = true
			validation = {}
			message = "LEERE FLAECHE · START NICHT VERGESSEN"
		KEY_V:
			_check()
		KEY_S:
			_check()
			return "save" if bool(validation.get("ok", false)) else ""
		KEY_ENTER, KEY_KP_ENTER:
			_check()
			return "drive" if bool(validation.get("ok", false)) else ""
		KEY_ESCAPE:
			return "exit"
	return ""


func handle_click(point: Vector2, button: MouseButton) -> String:
	if GRID_RECT.has_point(point):
		cursor = Vector2i(floori((point.x - GRID_ORIGIN.x) / CELL),
			floori((point.y - GRID_ORIGIN.y) / CELL))
		if button == MOUSE_BUTTON_LEFT:
			_place(cursor)
		elif button == MOUSE_BUTTON_RIGHT:
			_erase(cursor)
		elif button == MOUSE_BUTTON_MIDDLE:
			rotation = posmod(rotation + 1, 4)
		return ""
	for piece in range(Track.Piece.START, Track.Piece.DIRT + 1):
		if _palette_rect(piece).has_point(point):
			selected_piece = piece
			message = "%s AUSGEWAEHLT" % Track.PIECE_NAMES[piece]
			return ""
	if Rect2(PALETTE_X, 137, 62, 13).has_point(point):
		_check()
	elif Rect2(PALETTE_X + 65, 137, 62, 13).has_point(point):
		generation_seed += 977
		track = Track.generated(generation_seed, 8, "SEED %06d" % generation_seed, "custom")
		dirty = true
		_check()
	elif Rect2(PALETTE_X, 153, 62, 13).has_point(point):
		_check()
		return "save" if bool(validation.get("ok", false)) else ""
	elif Rect2(PALETTE_X + 65, 153, 62, 13).has_point(point):
		_check()
		return "drive" if bool(validation.get("ok", false)) else ""
	return ""


func notify_saved(title: String) -> void:
	dirty = false
	message = "%s GESPEICHERT" % title


func draw(canvas: CanvasItem, font: Font) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 200), C_BG)
	canvas.draw_rect(Rect2(0, 0, 320, 18), Color8(7, 12, 18))
	_text(canvas, font, "MAGNETOSTAR KURSBAUKASTEN", 7, 13, 9, C_AMBER)
	_text(canvas, font, "SEED %06d" % generation_seed, 222, 12, 6, C_CYAN)
	_draw_grid(canvas)
	_draw_palette(canvas, font)
	var status_color := C_GREEN if bool(validation.get("ok", false)) else C_CREAM
	_text(canvas, font, message, 7, 164, 6, status_color, HORIZONTAL_ALIGNMENT_LEFT, 306)
	_text(canvas, font, "MAUS L SETZEN / R LOESCHEN · PFEILE CURSOR · TAB TEIL · Q/E DREHEN", 7, 177, 5, C_WHITE)
	_text(canvas, font, "SPACE SETZEN · G GENERIEREN · V PRUEFEN · S SPEICHERN · ENTER FAHREN · ESC", 7, 188, 5, C_CREAM)
	if bool(validation.get("ok", false)):
		_text(canvas, font, "%d TEILE · %d STUNTS" % [int(validation.get("length", 0)),
			int(validation.get("stunts", 0))], 7, 198, 5, C_GREEN)
	elif not validation.is_empty():
		_text(canvas, font, str(validation.get("reason", "KURS UNGUELTIG")), 7, 198, 5, C_RED)


func draw_minimap(canvas: CanvasItem, rect: Rect2, source: Dictionary,
		selected := false) -> void:
	canvas.draw_rect(rect, Color8(12, 18, 24))
	var scale := minf(rect.size.x / float(Track.WIDTH), rect.size.y / float(Track.HEIGHT))
	var origin := rect.position + (rect.size - Vector2(Track.WIDTH, Track.HEIGHT) * scale) * 0.5
	for raw_key: Variant in (source.get("cells", {}) as Dictionary):
		var cell := Track.parse_key(str(raw_key))
		var tile: Dictionary = (source.get("cells", {}) as Dictionary)[raw_key]
		var color := C_AMBER if int(tile.get("piece", 0)) == Track.Piece.START else C_WHITE
		canvas.draw_rect(Rect2(origin + Vector2(cell) * scale, Vector2.ONE * maxf(1.0, scale)), color)
	canvas.draw_rect(rect, C_AMBER if selected else C_GRID, false, 1.0)


func _draw_grid(canvas: CanvasItem) -> void:
	canvas.draw_rect(GRID_RECT, Color8(22, 43, 34))
	for y in Track.HEIGHT:
		for x in Track.WIDTH:
			var cell := Vector2i(x, y)
			var rect := Rect2(GRID_ORIGIN + Vector2(cell) * CELL, Vector2.ONE * CELL)
			canvas.draw_rect(rect, C_GRID, false, 1.0)
			var tile := Track.tile_at(track, cell)
			if int(tile.get("piece", Track.Piece.EMPTY)) != Track.Piece.EMPTY:
				_draw_tile(canvas, rect, tile)
	for item: Dictionary in track.get("scenery", []):
		var cell := Vector2i(int(item.get("x", 0)), int(item.get("y", 0)))
		var p := GRID_ORIGIN + Vector2(cell) * CELL + Vector2(3, 3)
		canvas.draw_rect(Rect2(p, Vector2(2, 2)), Color8(62, 102, 66))
	var cursor_rect := Rect2(GRID_ORIGIN + Vector2(cursor) * CELL, Vector2.ONE * CELL)
	canvas.draw_rect(cursor_rect.grow(-0.5), C_AMBER, false, 1.0)
	var bad_cell := Vector2i(validation.get("cell", Vector2i(-1, -1)))
	if Track.in_bounds(bad_cell) and not bool(validation.get("ok", false)):
		canvas.draw_rect(Rect2(GRID_ORIGIN + Vector2(bad_cell) * CELL, Vector2.ONE * CELL), C_RED, false, 1.0)


func _draw_tile(canvas: CanvasItem, rect: Rect2, tile: Dictionary) -> void:
	var piece := int(tile.get("piece", Track.Piece.EMPTY))
	var center := rect.get_center().floor()
	var connections: Array[int] = Track.connections(tile)
	var road_color := C_ROAD
	if piece == Track.Piece.ICE:
		road_color = Color8(137, 190, 202)
	elif piece == Track.Piece.DIRT:
		road_color = Color8(151, 99, 67)
	for direction: int in connections:
		var edge := center + Vector2(Track.DIRS[direction]) * 3.5
		canvas.draw_line(center, edge, C_EDGE, 5.0, false)
		canvas.draw_line(center, edge, road_color, 3.0, false)
	if piece == Track.Piece.START:
		canvas.draw_rect(Rect2(center - Vector2(2, 2), Vector2(2, 2)), C_WHITE)
		canvas.draw_rect(Rect2(center, Vector2(2, 2)), C_WHITE)
	elif piece == Track.Piece.RAMP:
		canvas.draw_line(center - Vector2(2, 1), center + Vector2(2, 1), C_AMBER, 1.0)
	elif piece == Track.Piece.LOOP:
		canvas.draw_arc(center, 2.5, 0, TAU, 10, C_CYAN, 1.0, false)
	elif piece == Track.Piece.BRIDGE:
		canvas.draw_line(center - Vector2(2, 2), center + Vector2(2, 2), C_CREAM, 1.0)
	elif piece == Track.Piece.TUNNEL:
		canvas.draw_rect(Rect2(center - Vector2(2, 2), Vector2(4, 4)), Color8(16, 22, 29), false, 1.0)
	elif piece == Track.Piece.BANK:
		canvas.draw_line(center - Vector2(2, 2), center + Vector2(2, 2), C_ORANGE, 1.0)
	elif piece == Track.Piece.CORKSCREW:
		canvas.draw_line(center - Vector2(2, 2), center + Vector2(2, 2), C_CYAN, 1.0)
		canvas.draw_line(center + Vector2(-2, 2), center + Vector2(2, -2), C_CYAN, 1.0)


func _draw_palette(canvas: CanvasItem, font: Font) -> void:
	_text(canvas, font, "BAUTEILE", PALETTE_X, 25, 7, C_CYAN)
	for piece in range(Track.Piece.START, Track.Piece.DIRT + 1):
		var rect := _palette_rect(piece)
		var active := piece == selected_piece
		canvas.draw_rect(rect, Color8(36, 52, 65) if active else Color8(23, 32, 41))
		canvas.draw_rect(rect, C_AMBER if active else C_GRID, false, 1.0)
		_text(canvas, font, Track.PIECE_NAMES[piece], rect.position.x + 3,
			rect.position.y + 10, 5, C_AMBER if active else C_WHITE)
	_button(canvas, font, Rect2(PALETTE_X, 137, 62, 13), "PRUEFEN")
	_button(canvas, font, Rect2(PALETTE_X + 65, 137, 62, 13), "GENERATOR")
	_button(canvas, font, Rect2(PALETTE_X, 153, 62, 13), "SPEICHERN")
	_button(canvas, font, Rect2(PALETTE_X + 65, 153, 62, 13), "PROBEFAHRT", true)


func _button(canvas: CanvasItem, font: Font, rect: Rect2, label: String, accent := false) -> void:
	canvas.draw_rect(rect, Color8(31, 47, 59))
	canvas.draw_rect(rect, C_AMBER if accent else C_GRID, false, 1.0)
	_text(canvas, font, label, rect.position.x, rect.position.y + 9, 5,
		C_AMBER if accent else C_WHITE, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _palette_rect(piece: int) -> Rect2:
	var index := piece - Track.Piece.START
	var column := floori(float(index) / 6.0)
	var row := index % 6
	return Rect2(PALETTE_X + column * 65, 29 + row * 17, 62, 14)


func _place(cell: Vector2i) -> void:
	Track.set_tile(track, cell, selected_piece, rotation)
	dirty = true
	validation = {}
	message = "%s GESETZT · DREHUNG %d" % [Track.PIECE_NAMES[selected_piece], rotation * 90]


func _erase(cell: Vector2i) -> void:
	Track.set_tile(track, cell, Track.Piece.EMPTY, 0)
	dirty = true
	validation = {}
	message = "FELD GELOESCHT"


func _check() -> void:
	validation = Track.validate(track)
	message = str(validation.get("reason", "KURS GEPRUEFT"))


func _text(canvas: CanvasItem, font: Font, value: String, x: float, y: float,
		font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0) -> void:
	canvas.draw_string(font, Vector2(x, y), value, alignment, width, font_size, color)
