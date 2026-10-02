extends RefCounted
## Kleine deterministische BFS fuer das Parkwegenetz. Alle Nachbarn besitzen
## gleiche Kosten; sortierte Richtungen machen Saves und Tests reproduzierbar.

const DIRECTIONS := [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func find_path(paths: Dictionary, start: Vector2i, goal: Vector2i,
		width: int, height: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal:
		return result
	if not paths.has(cell_key(start)) or not paths.has(cell_key(goal)):
		return result
	var frontier: Array[Vector2i] = [start]
	var cursor := 0
	var previous := {cell_key(start): Vector2i(-999, -999)}
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if current == goal:
			break
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			var key := cell_key(next)
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if previous.has(key) or not paths.has(key):
				continue
			previous[key] = current
			frontier.append(next)
	if not previous.has(cell_key(goal)):
		return result
	var step := goal
	while step != start:
		result.push_front(step)
		step = previous[cell_key(step)] as Vector2i
	return result


static func connected_cells(paths: Dictionary, origin: Vector2i,
		width: int, height: int) -> Dictionary:
	var found := {}
	if not paths.has(cell_key(origin)):
		return found
	var frontier: Array[Vector2i] = [origin]
	found[cell_key(origin)] = true
	var cursor := 0
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			var key := cell_key(next)
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if found.has(key) or not paths.has(key):
				continue
			found[key] = true
			frontier.append(next)
	return found
