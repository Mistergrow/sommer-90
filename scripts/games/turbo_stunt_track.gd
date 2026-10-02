class_name TurboStuntTrack
extends RefCounted
## Kachelformat, Generator und Validierung fuer frei gebaute Stuntkurse.

const WIDTH := 24
const HEIGHT := 18
const TILE_WORLD := 24.0
# 24 Stuetzpunkte pro Kachel halten Kurven und Kameratangente auch bei hohem
# Tempo kontinuierlich. Acht Punkte liessen die Blickrichtung an jeder
# Stuetzstelle sichtbar um mehrere Bildpixel springen.
const SAMPLES_PER_TILE := 24

enum Piece {
	EMPTY, START, STRAIGHT, CURVE, RAMP, LOOP, BRIDGE, TUNNEL,
	BANK, CORKSCREW, ICE, DIRT,
}

const PIECE_NAMES := [
	"LEER", "START", "GERADE", "KURVE", "SPRUNGSCHANZE", "LOOPING",
	"BRUECKE", "TUNNEL", "STEILKURVE", "KORKENZIEHER", "EIS", "SCHOTTER",
]
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const STRAIGHT_PIECES: Array[int] = [
	Piece.START, Piece.STRAIGHT, Piece.RAMP, Piece.LOOP, Piece.BRIDGE,
	Piece.TUNNEL, Piece.BANK, Piece.CORKSCREW, Piece.ICE, Piece.DIRT,
]


static func empty(title := "NEUE STRECKE", id := "custom") -> Dictionary:
	return {
		"version": 1, "id": id, "title": title, "width": WIDTH, "height": HEIGHT,
		"cells": {}, "scenery": [], "seed": 0, "author": "SPIELER",
	}


static func preset(id: String) -> Dictionary:
	match id:
		"gravel":
			var gravel := generated(7_091, 7, "KIESGRUBE 7", "gravel")
			return gravel
		"freight":
			return generated(91_337, 10, "GUETERHOF", "freight")
		_:
			return generated(19_900, 4, "PARKPLATZ NORD", "parking")


static func generated(track_seed: int, difficulty := 6, title := "GENERIERTER KURS",
		id := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = track_seed
	var track := empty(title,
		id if id != "" else "generated_%06d" % posmod(track_seed, 1_000_000))
	track["seed"] = track_seed
	var x0 := rng.randi_range(2, 5)
	var x1 := rng.randi_range(WIDTH - 7, WIDTH - 3)
	var y0 := rng.randi_range(2, 4)
	var y1 := rng.randi_range(HEIGHT - 5, HEIGHT - 3)
	# Zwei versetzte Einbuchtungen erzeugen echte Richtungswechsel, bleiben aber
	# durch die geordnete Route garantiert geschlossen und editierbar.
	var width := x1 - x0
	var half_width := floori(float(width) / 2.0)
	var top_a := x0 + rng.randi_range(3, maxi(3, half_width - 1))
	var top_b := mini(x1 - 2, top_a + rng.randi_range(2, 4))
	var bottom_b := x1 - rng.randi_range(3, maxi(3, half_width - 1))
	var bottom_a := maxi(x0 + 2, bottom_b - rng.randi_range(2, 4))
	var top_depth := rng.randi_range(2, 3)
	var bottom_depth := rng.randi_range(2, 3)
	var route: Array[Vector2i] = [Vector2i(x0, y0)]
	_append_route_line(route, Vector2i(top_a, y0))
	_append_route_line(route, Vector2i(top_a, y0 + top_depth))
	_append_route_line(route, Vector2i(top_b, y0 + top_depth))
	_append_route_line(route, Vector2i(top_b, y0))
	_append_route_line(route, Vector2i(x1, y0))
	_append_route_line(route, Vector2i(x1, y1))
	_append_route_line(route, Vector2i(bottom_b, y1))
	_append_route_line(route, Vector2i(bottom_b, y1 - bottom_depth))
	_append_route_line(route, Vector2i(bottom_a, y1 - bottom_depth))
	_append_route_line(route, Vector2i(bottom_a, y1))
	_append_route_line(route, Vector2i(x0, y1))
	_append_route_line(route, Vector2i(x0, y0))
	route.pop_back() # Startzelle darf im Kachel-Dictionary nur einmal vorkommen.
	var start_index := -1
	for i in route.size():
		var piece_and_rotation := _route_piece(route, i)
		_put(track, route[i], int(piece_and_rotation[0]), int(piece_and_rotation[1]))
		if start_index < 0 and i > 0 and int(piece_and_rotation[0]) == Piece.STRAIGHT:
			start_index = i
	if start_index < 0:
		start_index = 0
	var start_tile := tile_at(track, route[start_index])
	_put(track, route[start_index], Piece.START, int(start_tile.get("rotation", 0)))
	var candidates: Array[Vector2i] = []
	for raw_key: Variant in (track["cells"] as Dictionary):
		var cell := parse_key(str(raw_key))
		if int((track["cells"] as Dictionary)[raw_key].get("piece", Piece.EMPTY)) == Piece.STRAIGHT:
			candidates.append(cell)
	_shuffle(candidates, rng)
	var stunt_pool: Array[int] = [Piece.RAMP, Piece.TUNNEL, Piece.ICE, Piece.DIRT]
	if difficulty >= 4:
		stunt_pool.append(Piece.BRIDGE)
	if difficulty >= 6:
		stunt_pool.append(Piece.BANK)
	if difficulty >= 8:
		stunt_pool.append(Piece.LOOP)
	if difficulty >= 10:
		stunt_pool.append(Piece.CORKSCREW)
	var stunt_count := clampi(2 + floori(float(difficulty) / 2.0), 2,
		mini(9, candidates.size()))
	for i in stunt_count:
		var cell := candidates[i]
		var old := tile_at(track, cell)
		var piece := stunt_pool[i % stunt_pool.size()]
		_put(track, cell, piece, int(old.get("rotation", 0)))
	var scenery: Array = []
	for _i in 28:
		var cell := Vector2i(rng.randi_range(0, WIDTH - 1), rng.randi_range(0, HEIGHT - 1))
		if int(tile_at(track, cell).get("piece", Piece.EMPTY)) == Piece.EMPTY:
			scenery.append({"x": cell.x, "y": cell.y, "kind": rng.randi_range(0, 3)})
	track["scenery"] = scenery
	return track


static func set_tile(track: Dictionary, cell: Vector2i, piece: int, rotation: int) -> void:
	if not in_bounds(cell):
		return
	if piece == Piece.EMPTY:
		(track.get("cells", {}) as Dictionary).erase(key(cell))
	else:
		_put(track, cell, clampi(piece, Piece.START, Piece.DIRT), posmod(rotation, 4))


static func tile_at(track: Dictionary, cell: Vector2i) -> Dictionary:
	if not in_bounds(cell):
		return {"piece": Piece.EMPTY, "rotation": 0}
	return (track.get("cells", {}) as Dictionary).get(key(cell), {"piece": Piece.EMPTY, "rotation": 0})


static func connections(tile: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var piece := int(tile.get("piece", Piece.EMPTY))
	var rotation := posmod(int(tile.get("rotation", 0)), 4)
	if piece in STRAIGHT_PIECES:
		if rotation % 2 == 0:
			result.append(0)
			result.append(2)
		else:
			result.append(1)
			result.append(3)
		return result
	if piece == Piece.CURVE:
		result.append(rotation)
		result.append(posmod(rotation + 1, 4))
	return result


static func validate(track: Dictionary) -> Dictionary:
	var cells: Dictionary = track.get("cells", {})
	var road_cells: Array[Vector2i] = []
	var starts: Array[Vector2i] = []
	for raw_key: Variant in cells:
		var cell := parse_key(str(raw_key))
		var piece := int((cells[raw_key] as Dictionary).get("piece", Piece.EMPTY))
		if piece == Piece.EMPTY:
			continue
		road_cells.append(cell)
		if piece == Piece.START:
			starts.append(cell)
	if starts.size() != 1:
		return {"ok": false, "reason": Loc.t("game.turbo_stunt_track.genau_startfeld_noetig", "GENAU EIN STARTFELD NOETIG"), "cell": starts[0] if not starts.is_empty() else Vector2i(-1, -1)}
	if road_cells.size() < 12:
		return {"ok": false, "reason": "STRECKE ZU KURZ · MINDESTENS 12 TEILE", "cell": starts[0]}
	for cell: Vector2i in road_cells:
		var adjacent := _connected_neighbors(track, cell)
		if adjacent.size() != 2:
			return {"ok": false, "reason": "OFFENE ODER FALSCH GEDREHTE VERBINDUNG", "cell": cell}
	var route := _ordered_route(track, starts[0])
	if route.size() != road_cells.size():
		return {"ok": false, "reason": Loc.t("game.turbo_stunt_track.nicht_alle_streckenteile_sind_verbunden", "NICHT ALLE STRECKENTEILE SIND VERBUNDEN"), "cell": starts[0]}
	var stunt_count := 0
	for cell: Vector2i in route:
		if int(tile_at(track, cell).get("piece", Piece.EMPTY)) in [Piece.RAMP, Piece.LOOP, Piece.BRIDGE, Piece.TUNNEL, Piece.BANK, Piece.CORKSCREW]:
			stunt_count += 1
	return {"ok": true, "reason": "KURS GEPRUEFT", "route": route, "length": route.size(), "stunts": stunt_count}


static func ordered_cells(track: Dictionary) -> Array[Vector2i]:
	var result := validate(track)
	var ordered: Array[Vector2i] = []
	if bool(result.get("ok", false)):
		for cell: Vector2i in result.get("route", []):
			ordered.append(cell)
	return ordered


static func bake(track: Dictionary) -> Array[Dictionary]:
	var route := ordered_cells(track)
	var baked: Array[Dictionary] = []
	if route.size() < 4:
		return baked
	var points: Array[Vector2] = []
	for cell: Vector2i in route:
		points.append((Vector2(cell) + Vector2.ONE * 0.5) * TILE_WORLD)
	for i in route.size():
		var p0 := points[posmod(i - 1, points.size())]
		var p1 := points[i]
		var p2 := points[(i + 1) % points.size()]
		var p3 := points[(i + 2) % points.size()]
		var tile := tile_at(track, route[i])
		var piece := int(tile.get("piece", Piece.STRAIGHT))
		for step in SAMPLES_PER_TILE:
			var t := float(step) / float(SAMPLES_PER_TILE)
			var point := _catmull_rom(p0, p1, p2, p3, t)
			var height := 0.0
			var roll := 0.0
			if piece == Piece.BRIDGE:
				height = sin(t * PI) * 6.0
			elif piece == Piece.RAMP:
				height = t * 3.5
			elif piece == Piece.LOOP:
				height = (1.0 - cos(t * TAU)) * 8.0
				roll = t * TAU
			elif piece == Piece.CORKSCREW:
				height = sin(t * PI) * 4.0
				roll = t * TAU
			elif piece == Piece.BANK:
				roll = sin(t * PI) * 0.42
			baked.append({
				"point": point, "height": height, "roll": roll, "piece": piece,
				"local": t, "cell": route[i], "route_index": i,
			})
	return baked


static func clone(track: Dictionary) -> Dictionary:
	return track.duplicate(true)


static func key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


static func parse_key(value: String) -> Vector2i:
	var parts := value.split(":")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)


static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WIDTH and cell.y < HEIGHT


static func _put(track: Dictionary, cell: Vector2i, piece: int, rotation: int) -> void:
	var cells: Dictionary = track.get("cells", {})
	cells[key(cell)] = {"piece": piece, "rotation": posmod(rotation, 4)}
	track["cells"] = cells


static func _connected_neighbors(track: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for direction: int in connections(tile_at(track, cell)):
		var neighbor := cell + DIRS[direction]
		if posmod(direction + 2, 4) in connections(tile_at(track, neighbor)):
			out.append(neighbor)
	return out


static func _ordered_route(track: Dictionary, start: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = [start]
	var neighbors := _connected_neighbors(track, start)
	if neighbors.size() != 2:
		return []
	var previous := start
	var current := neighbors[0]
	var guard := WIDTH * HEIGHT + 1
	while current != start and guard > 0:
		if current in route:
			return []
		route.append(current)
		var next_options := _connected_neighbors(track, current)
		if next_options.size() != 2:
			return []
		var next := next_options[0] if next_options[0] != previous else next_options[1]
		previous = current
		current = next
		guard -= 1
	return route if current == start else []


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _shuffle(values: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var swap := values[i]
		values[i] = values[other]
		values[other] = swap


static func _append_route_line(route: Array[Vector2i], target: Vector2i) -> void:
	var current: Vector2i = route.back()
	while current != target:
		var delta: Vector2i = target - current
		current += Vector2i(signi(delta.x), signi(delta.y))
		route.append(current)


static func _route_piece(route: Array[Vector2i], index: int) -> Array[int]:
	var cell := route[index]
	var previous := route[posmod(index - 1, route.size())]
	var next := route[(index + 1) % route.size()]
	var incoming := _direction_index(previous - cell)
	var outgoing := _direction_index(next - cell)
	var result: Array[int] = []
	if posmod(incoming + 2, 4) == outgoing:
		result.append(Piece.STRAIGHT)
		result.append(0 if incoming % 2 == 0 else 1)
		return result
	for rotation in 4:
		var curve_connections: Array[int] = [rotation, posmod(rotation + 1, 4)]
		if incoming in curve_connections and outgoing in curve_connections:
			result.append(Piece.CURVE)
			result.append(rotation)
			return result
	result.append(Piece.STRAIGHT)
	result.append(0)
	return result


static func _direction_index(delta: Vector2i) -> int:
	for i in DIRS.size():
		if DIRS[i] == delta:
			return i
	return 0
