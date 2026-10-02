class_name SpaceLemmingModel
extends RefCounted
## Reines 30-Hz-Spielmodell. Keine Nodes, keine Bilder, kein Wallclock-Zugriff:
## dieselbe Mission laeuft bei identischem Seed und denselben Befehlen identisch.

const Generator := preload("res://scripts/games/space_lemming_generator.gd")
const TICK_RATE := 30
const TICK_DT := 1.0 / TICK_RATE
const MOVE_TICKS := 8
const SPAWN_TICKS := 18

enum State { PLANNING, RUNNING, WON, LOST }

var level: Dictionary = {}
var state := State.PLANNING
var beacons: Dictionary = {}
var crew: Array[Dictionary] = []
var collected: Dictionary = {}
var ticks := 0
var spawned := 0
var rescued := 0
var lost := 0
var crystals := 0
var score := 0
var stars := 0
var event_serial := 0
var last_event := ""
var last_event_cell := Vector2i.ZERO
var _next_crew_id := 1


func load_level(data: Dictionary) -> void:
	level = data.duplicate(true)
	state = State.PLANNING
	beacons = {}
	crew = []
	collected = {}
	ticks = 0
	spawned = 0
	rescued = 0
	lost = 0
	crystals = 0
	score = 0
	stars = 0
	_next_crew_id = 1
	_emit("level_ready")


func launch() -> bool:
	if state != State.PLANNING or level.is_empty():
		return false
	state = State.RUNNING
	_spawn_one()
	_emit("launch")
	return true


func place_tool(cell: Vector2i, tool: int) -> Dictionary:
	if state not in [State.PLANNING, State.RUNNING]:
		return {"ok": false, "reason": "mission_beendet"}
	var tile := Generator.tile_at(level, cell)
	if not _tool_fits(tile, tool):
		return {"ok": false, "reason": "falsche_flaeche"}
	var key := Generator.key(cell)
	var old := int(beacons.get(key, -1))
	if old == tool:
		beacons.erase(key)
		_emit("remove")
		return {"ok": true, "removed": true}
	var category := _category(tool)
	var old_category := _category(old)
	if old_category != category and remaining(category) <= 0:
		return {"ok": false, "reason": "kein_werkzeug"}
	beacons[key] = tool
	_emit("place")
	return {"ok": true, "removed": false}


func remove_tool(cell: Vector2i) -> bool:
	var key := Generator.key(cell)
	if not beacons.has(key):
		return false
	beacons.erase(key)
	_emit("remove")
	return true


func remaining(category: String) -> int:
	var budgets: Dictionary = level.get("budgets", {})
	return maxi(0, int(budgets.get(category, 0)) - used(category))


func used(category: String) -> int:
	var count := 0
	for raw_tool: Variant in beacons.values():
		if _category(int(raw_tool)) == category:
			count += 1
	return count


func tick() -> void:
	if state != State.RUNNING:
		return
	ticks += 1
	if spawned < int(level.get("crew_total", 0)) and ticks % SPAWN_TICKS == 0:
		_spawn_one()
	if ticks % MOVE_TICKS == 0:
		_move_crew()
	if ticks >= int(level.get("time_limit_ticks", 1)):
		for member: Dictionary in crew:
			if str(member.get("status", "")) == "active":
				member["status"] = "lost"
				member["resolved_tick"] = ticks
				lost += 1
		_finish_if_ready(true)


func elapsed_ms() -> int:
	return int(float(ticks) * 1000.0 / TICK_RATE)


func time_left_ticks() -> int:
	return maxi(0, int(level.get("time_limit_ticks", 0)) - ticks)


func active_crew() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for member: Dictionary in crew:
		if str(member.get("status", "")) == "active":
			out.append(member)
	return out


func solution_complete() -> bool:
	var solution: Dictionary = level.get("solution", {})
	for key: Variant in solution:
		if int(beacons.get(key, -1)) != int(solution[key]):
			return false
	return true


func _spawn_one() -> void:
	if spawned >= int(level.get("crew_total", 0)):
		return
	crew.append({
		"id": _next_crew_id, "cell": level.get("start", Vector2i.ZERO),
		"previous_cell": level.get("start", Vector2i.ZERO),
		"direction": Vector2i.RIGHT, "status": "active", "phase": 0,
	})
	_next_crew_id += 1
	spawned += 1
	_emit("spawn")


func _move_crew() -> void:
	for member: Dictionary in crew:
		if str(member.get("status", "")) != "active":
			continue
		var cell: Vector2i = member.get("cell", Vector2i.ZERO)
		var tool := int(beacons.get(Generator.key(cell), -1))
		if tool >= Generator.Tool.UP and tool <= Generator.Tool.LEFT:
			member["direction"] = _direction_for_tool(tool)
		var next: Vector2i = cell + Vector2i(member.get("direction", Vector2i.RIGHT))
		var tile := Generator.tile_at(level, next)
		member["previous_cell"] = cell
		if tile == Generator.Tile.EXIT:
			member["cell"] = next
			member["status"] = "rescued"
			member["resolved_tick"] = ticks
			rescued += 1
			_emit_at("rescue", next)
			continue
		if not _can_enter(next, tile):
			member["cell"] = next
			member["status"] = "lost"
			member["resolved_tick"] = ticks
			lost += 1
			_emit_at("lost", next)
			continue
		member["cell"] = next
		member["phase"] = int(member.get("phase", 0)) + 1
		if tile == Generator.Tile.CRYSTAL:
			var key := Generator.key(next)
			if not collected.has(key):
				collected[key] = true
				crystals += 1
				_emit_at("crystal", next)
	_finish_if_ready(false)


func _can_enter(cell: Vector2i, tile: int) -> bool:
	if tile in [Generator.Tile.FLOOR, Generator.Tile.CRYSTAL, Generator.Tile.SPAWN]:
		return true
	var tool := int(beacons.get(Generator.key(cell), -1))
	if tile == Generator.Tile.GAP:
		return tool == Generator.Tool.BRIDGE
	if tile == Generator.Tile.HAZARD:
		return tool == Generator.Tool.SHIELD
	return false


func _finish_if_ready(timed_out: bool) -> void:
	if state != State.RUNNING:
		return
	var everyone_spawned := spawned >= int(level.get("crew_total", 0))
	if not timed_out and (not everyone_spawned or not active_crew().is_empty()):
		return
	var required := int(level.get("required", 1))
	state = State.WON if rescued >= required else State.LOST
	var remaining_seconds := int(float(time_left_ticks()) / TICK_RATE)
	score = rescued * 1_000 + crystals * 300 + remaining_seconds * 15 - lost * 100
	score = maxi(0, score)
	if state == State.WON:
		stars = 1
		if rescued == int(level.get("crew_total", 0)):
			stars += 1
		if solution_complete() and lost == 0:
			stars += 1
	_emit("won" if state == State.WON else "lost_run")


func _tool_fits(tile: int, tool: int) -> bool:
	if tool >= Generator.Tool.UP and tool <= Generator.Tool.LEFT:
		return tile in [Generator.Tile.FLOOR, Generator.Tile.CRYSTAL, Generator.Tile.SPAWN]
	if tool == Generator.Tool.BRIDGE:
		return tile == Generator.Tile.GAP
	if tool == Generator.Tool.SHIELD:
		return tile == Generator.Tile.HAZARD
	return false


func _category(tool: int) -> String:
	if tool >= Generator.Tool.UP and tool <= Generator.Tool.LEFT:
		return "arrow"
	if tool == Generator.Tool.BRIDGE:
		return "bridge"
	if tool == Generator.Tool.SHIELD:
		return "shield"
	return ""


func _direction_for_tool(tool: int) -> Vector2i:
	match tool:
		Generator.Tool.UP: return Vector2i.UP
		Generator.Tool.DOWN: return Vector2i.DOWN
		Generator.Tool.LEFT: return Vector2i.LEFT
		_: return Vector2i.RIGHT


func _emit(event: String) -> void:
	last_event = event
	event_serial += 1


func _emit_at(event: String, cell: Vector2i) -> void:
	last_event_cell = cell
	_emit(event)
