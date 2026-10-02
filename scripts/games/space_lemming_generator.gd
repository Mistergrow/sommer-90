class_name SpaceLemmingGenerator
extends RefCounted
## Deterministischer, garantiert loesbarer Missionsgenerator fuer Space Lemming.
## Erst wird eine eindeutige Rettungsroute gebaut; danach werden nur auf dieser
## Route Aufgaben verteilt und die exakt passende Werkzeugreserve berechnet.

const WIDTH := 20
const HEIGHT := 10

enum Tile { VOID, FLOOR, GAP, HAZARD, CRYSTAL, SPAWN, EXIT }
enum Tool { UP, RIGHT, DOWN, LEFT, BRIDGE, SHIELD }

const CAMPAIGN_LEVELS := 18
const SECTORS := ["ORBITALWERFT", "NACHTSEITE", "NULLPUNKT"]
const MISSION_NAMES := [
	"ERSTER KONTAKT", "LECK IM RING", "KALTE SCHLEUSE", "BLAUES ECHO",
	"FUNKENFLUG", "AUSSENPOSTEN", "SCHATTENDECK", "STILLE ANTENNE",
	"PLASMAKANAL", "VERLASSENE WACHE", "SIGNAL 404", "DRIFTENDE STADT",
	"ROTER ALARM", "EREIGNISHORIZONT", "DUNKLE BRUECKE", "LETZTE BAHN",
	"KEIN ZURUECK", "HEIMWAERTS",
]


static func campaign(level_index: int) -> Dictionary:
	var index := clampi(level_index, 0, CAMPAIGN_LEVELS - 1)
	return generate(901_990 + index * 7_919, index, index)


static func endless(level_seed: int, difficulty: int = 8) -> Dictionary:
	return generate(maxi(1, level_seed), clampi(difficulty, 0, 24), -1)


static func generate(level_seed: int, difficulty: int, campaign_index: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(1, level_seed)
	var tiles := PackedInt32Array()
	tiles.resize(WIDTH * HEIGHT)
	tiles.fill(Tile.VOID)

	var start := Vector2i(1, rng.randi_range(2, HEIGHT - 3))
	var route: Array[Vector2i] = [start]
	var direction_changes: Dictionary = {}
	var current := start
	var bends := clampi(1 + floori(float(difficulty) / 4.0), 1, 4)
	for bend in bends:
		var remaining_bends := bends - bend - 1
		var max_target_x := (WIDTH - 3) - remaining_bends * 3
		var target_x := mini(max_target_x, current.x + rng.randi_range(3, 5))
		while current.x < target_x:
			current += Vector2i.RIGHT
			route.append(current)
		var old_y := current.y
		var target_y := rng.randi_range(1, HEIGHT - 2)
		if abs(target_y - old_y) < 2:
			target_y = clampi(old_y + (2 if old_y < HEIGHT * 0.5 else -2), 1, HEIGHT - 2)
		var vertical := Vector2i.DOWN if target_y > old_y else Vector2i.UP
		direction_changes[_key(current)] = _tool_for_direction(vertical)
		while current.y != target_y:
			current += vertical
			route.append(current)
		direction_changes[_key(current)] = Tool.RIGHT
	while current.x < WIDTH - 2:
		current += Vector2i.RIGHT
		route.append(current)
	var exit := current

	for cell: Vector2i in route:
		_set_tile(tiles, cell, Tile.FLOOR)
	_set_tile(tiles, start, Tile.SPAWN)
	_set_tile(tiles, exit, Tile.EXIT)

	# Kurze Sackgaenge machen das Lesen der Route interessanter, veraendern aber
	# nie die garantierte Loesung. Sie enden mindestens eine Zelle vor dem Rand.
	var branch_attempts := 1 + floori(float(difficulty) / 5.0)
	for _attempt in branch_attempts:
		var anchor: Vector2i = route[rng.randi_range(3, route.size() - 4)]
		var branch_dir := Vector2i.UP if rng.randf() < 0.5 else Vector2i.DOWN
		for length in rng.randi_range(1, 2):
			var branch := anchor + branch_dir * (length + 1)
			if branch.y > 0 and branch.y < HEIGHT - 1 and _tile(tiles, branch) == Tile.VOID:
				_set_tile(tiles, branch, Tile.FLOOR)

	var reserved: Dictionary = direction_changes.duplicate()
	reserved[_key(start)] = true
	reserved[_key(exit)] = true
	var candidates: Array[Vector2i] = []
	for i in range(2, route.size() - 2):
		var candidate := route[i]
		if not reserved.has(_key(candidate)):
			candidates.append(candidate)
	_shuffle_cells(candidates, rng)

	var gap_count := clampi(floori(float(difficulty + 1) / 4.0), 0, 2)
	var hazard_count := clampi(floori(float(difficulty - 1) / 4.0), 0, 2)
	var solution: Dictionary = direction_changes.duplicate()
	for _i in gap_count:
		if candidates.is_empty():
			break
		var cell: Vector2i = candidates.pop_back()
		_set_tile(tiles, cell, Tile.GAP)
		solution[_key(cell)] = Tool.BRIDGE
	for _i in hazard_count:
		if candidates.is_empty():
			break
		var cell: Vector2i = candidates.pop_back()
		_set_tile(tiles, cell, Tile.HAZARD)
		solution[_key(cell)] = Tool.SHIELD

	var crystal_count := clampi(2 + floori(float(difficulty) / 3.0), 2, 7)
	for _i in crystal_count:
		if candidates.is_empty():
			break
		_set_tile(tiles, candidates.pop_back(), Tile.CRYSTAL)

	var arrow_count := 0
	var actual_gaps := 0
	var actual_hazards := 0
	for tool: Variant in solution.values():
		match int(tool):
			Tool.BRIDGE: actual_gaps += 1
			Tool.SHIELD: actual_hazards += 1
			_: arrow_count += 1
	var crew_total := clampi(5 + floori(float(difficulty) / 2.0), 5, 14)
	var required := ceili(crew_total * (0.60 + minf(0.25, difficulty * 0.015)))
	var campaign_name: String = str(MISSION_NAMES[campaign_index]) if campaign_index >= 0 else "SIGNAL %06d" % (level_seed % 1_000_000)
	var sector_index := floori(float(maxi(0, campaign_index)) / 6.0)
	var sector: String = str(SECTORS[mini(SECTORS.size() - 1, sector_index)]) if campaign_index >= 0 else "ENDLOSSIGNAL"
	return {
		"seed": level_seed, "difficulty": difficulty, "campaign_index": campaign_index,
		"name": campaign_name, "sector": sector, "width": WIDTH, "height": HEIGHT,
		"tiles": tiles, "route": route, "start": start, "exit": exit,
		"solution": solution,
		"budgets": {"arrow": arrow_count + 1, "bridge": actual_gaps, "shield": actual_hazards},
		"crew_total": crew_total, "required": required,
		"time_limit_ticks": (65 + difficulty * 2) * 30,
	}


static func tile_at(level: Dictionary, cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(level.get("width", WIDTH)) \
			or cell.y >= int(level.get("height", HEIGHT)):
		return Tile.VOID
	var tiles: PackedInt32Array = level.get("tiles", PackedInt32Array())
	var index := cell.y * int(level.get("width", WIDTH)) + cell.x
	return tiles[index] if index >= 0 and index < tiles.size() else Tile.VOID


static func key(cell: Vector2i) -> String:
	return _key(cell)


static func _key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


static func _tile(tiles: PackedInt32Array, cell: Vector2i) -> int:
	return tiles[cell.y * WIDTH + cell.x]


static func _set_tile(tiles: PackedInt32Array, cell: Vector2i, tile: int) -> void:
	tiles[cell.y * WIDTH + cell.x] = tile


static func _tool_for_direction(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return Tool.UP
	if direction == Vector2i.DOWN:
		return Tool.DOWN
	if direction == Vector2i.LEFT:
		return Tool.LEFT
	return Tool.RIGHT


static func _shuffle_cells(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cells[i]
		cells[i] = cells[j]
		cells[j] = swap
