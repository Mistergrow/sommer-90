class_name StefanGameModel
extends RefCounted
## Deterministischer Simulationskern der Stefan-Anthologie. Neun Spielmodi
## teilen Zeit, Score, Events und Save-unabhaengige Runs; Rendering und Audio
## bleiben komplett ausserhalb dieses Modells.

const FIELD := Rect2(8.0, 22.0, 304.0, 168.0)
const GRID_W := 16
const GRID_H := 9
const CIRCUIT_W := 6
const CIRCUIT_H := 5
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BITS: Array[int] = [1, 2, 4, 8]
const OPPOSITE: Array[int] = [4, 8, 1, 2]
const STEALTH_ALARM_MAX := 100
const STEALTH_DETECTION_GAIN := 34

var definition: Dictionary = {}
var mode := ""
var variant := ""
var difficulty := 1
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var time_limit := 90.0
var score := 0
var completed := false
var over := false
var result_reason := ""
var event_serial := 0
var last_event := ""
var last_event_pos := Vector2.ZERO

var player := Vector2.ZERO
var velocity := Vector2.ZERO
var health := 3
var combo := 0
var best_combo := 0
var progress := 0
var required := 3
var auxiliary_required := 0
var threshold_required := 0.0
var secondary := 0
var objects: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var platforms: Array[Rect2] = []
var grid: Array[int] = []
var grid_solution: Array[int] = []
var grid_targets: Array[int] = []
var cursor := Vector2i.ZERO
var resources: Array[int] = []
var resource_names: Array[String] = []
var turn := 0
var selected := 0
var allocation := 12
var forecast: Array[int] = []
var accuracy_hits := 0
var accuracy_misses := 0
var song_notes: Array[Dictionary] = []
var rhythm_hit_window := 0.23
var rhythm_phase_assists := 0
var distance := 0.0
var lane := 2
var base_position := Vector2(24, 106)
var grounded := false
var held := {"left": false, "right": false, "up": false, "down": false, "fire": false}

var _spawn_clock := 0.0
var _item_clock := 0.0
var _repeat_clock := 0.0
var _next_note := 0
var _arena_enemy_score := 0
var _arena_ball := Vector2.ZERO
var _arena_ball_velocity := Vector2.ZERO
var _strategy_goal := 10
var _damage_cooldown := 0.0
var _stealth_decay_clock := 0.0


func configure(game_definition: Dictionary) -> void:
	definition = game_definition.duplicate(true)
	mode = str(definition.get("mode", "shooter"))
	variant = str(definition.get("variant", ""))
	difficulty = clampi(int(definition.get("difficulty", 1)), 1, 9)
	time_limit = maxf(20.0, float(definition.get("time_limit", 90)))


func start(run_serial := 0) -> void:
	rng.seed = int(definition.get("seed", 199101)) * 1009 + run_serial * 9176
	elapsed = 0.0
	score = 0
	completed = false
	over = false
	result_reason = ""
	event_serial = 0
	last_event = ""
	player = Vector2(FIELD.position.x + 28.0, FIELD.get_center().y)
	velocity = Vector2.ZERO
	health = 3
	combo = 0
	best_combo = 0
	progress = 0
	auxiliary_required = 0
	threshold_required = 0.0
	secondary = 0
	objects = []
	shots = []
	platforms = []
	grid = []
	grid_solution = []
	grid_targets = []
	cursor = Vector2i.ZERO
	resources = []
	resource_names = []
	turn = 0
	selected = 0
	allocation = 12
	forecast = []
	accuracy_hits = 0
	accuracy_misses = 0
	song_notes = []
	rhythm_hit_window = 0.23
	rhythm_phase_assists = 0
	distance = 0.0
	lane = 2
	grounded = false
	held = {"left": false, "right": false, "up": false, "down": false, "fire": false}
	_spawn_clock = 0.0
	_item_clock = 0.0
	_repeat_clock = 0.0
	_next_note = 0
	_arena_enemy_score = 0
	_damage_cooldown = 0.0
	_stealth_decay_clock = 0.0
	match mode:
		"shooter": _setup_shooter()
		"platform": _setup_platform()
		"circuit": _setup_circuit()
		"miner": _setup_miner()
		"rescue": _setup_rescue()
		"stealth": _setup_stealth()
		"racer": _setup_racer()
		"strategy": _setup_strategy()
		"rhythm": _setup_rhythm()
		_: _setup_shooter()


func remaining() -> float:
	return maxf(0.0, time_limit - elapsed)


func set_held(action: String, pressed: bool) -> void:
	if held.has(action):
		held[action] = pressed


func tick(delta: float) -> void:
	if over:
		return
	delta = clampf(delta, 0.0, 0.05)
	elapsed += delta
	if elapsed >= time_limit:
		_finish(false, "ZEIT ABGELAUFEN")
		return
	match mode:
		"shooter": _tick_shooter(delta)
		"platform": _tick_platform(delta)
		"rescue": _tick_rescue(delta)
		"stealth": _tick_stealth(delta)
		"racer": _tick_racer(delta)
		"rhythm": _tick_rhythm(delta)
		"strategy", "circuit", "miner": pass


func press(action: String) -> void:
	if over:
		return
	match mode:
		"shooter": _press_shooter(action)
		"platform": _press_platform(action)
		"circuit": _press_circuit(action)
		"miner": _press_miner(action)
		"rescue": _press_rescue(action)
		"stealth": _press_stealth(action)
		"racer": _press_racer(action)
		"strategy": _press_strategy(action)
		"rhythm": _press_rhythm(action)


func objective_status() -> String:
	match mode:
		"shooter":
			return ("ZIELE %d/%d · HÜLLE %d" if variant == "fighter" else "FRACHT %d/%d · HÜLLE %d") \
				% [progress, required, health]
		"platform":
			if variant == "arena":
				return "TORE %d/%d · GEGNER %d" % [progress, required, _arena_enemy_score]
			return "FUNDE %d/%d · LEBEN %d%s" % [progress, required, health,
				" · IMPULS" if variant == "lava" and secondary > 0 else ""]
		"circuit": return "KERNE %d/%d · ZÜGE %d" % [connected_target_count(), required, secondary]
		"miner": return "KRISTALLE %d/%d · O2 %d" % [progress, required, health]
		"rescue": return "GERETTET %d/%d · HÜLLE %d" % [progress, required, health]
		"stealth": return "DATEN %d/%d · ALARM %d" % [progress, required, secondary]
		"racer": return "STRECKE %.1f/%d · MARKEN %d/%d" % [distance, required, progress, auxiliary_required]
		"strategy": return "ZYKLUS %d/%d · MIN %d" % [turn, _strategy_goal, _resource_min()]
		"rhythm":
			var phase_status := " · PHASE %d" % rhythm_phase_assists \
				if rhythm_phase_assists > 0 or int(definition.get("phase_assists", 0)) > 0 \
				else ""
			return "TREFFER %d · FEHLER %d · SERIE %d%s" % [
				accuracy_hits, accuracy_misses, combo, phase_status]
	return ""


func details() -> Dictionary:
	return {
		"mode": mode, "variant": variant, "difficulty": difficulty,
		"progress": progress, "required": required, "secondary": secondary,
		"auxiliary_required": auxiliary_required, "threshold_required": threshold_required,
		"combo": best_combo, "health": health, "turn": turn,
		"accuracy": accuracy(), "distance": snappedf(distance, 0.1),
		"rhythm_phase_assists": rhythm_phase_assists,
	}


func accuracy() -> float:
	var total := accuracy_hits + accuracy_misses
	return 1.0 if total <= 0 else float(accuracy_hits) / float(total)


func _emit(name: String, at := Vector2.ZERO) -> void:
	last_event = name
	last_event_pos = at
	event_serial += 1


func _finish(success: bool, reason: String) -> void:
	if over:
		return
	completed = success
	over = true
	result_reason = reason
	if success:
		score += maxi(0, roundi(remaining() * 35.0)) + health * 350 + best_combo * 40
	_emit("victory" if success else "lost", player)


func _damage(reason := "TREFFER") -> void:
	health -= 1
	combo = 0
	_emit("damage", player)
	if health <= 0:
		_finish(false, reason)


# ------------------------------------------------------------------ Shooter

func _setup_shooter() -> void:
	required = int(definition.get("goal_primary", 3 + floori(float(difficulty) / 3.0)))
	health = 4 if difficulty <= 3 else 3
	player = Vector2(45, 106)


func _tick_shooter(delta: float) -> void:
	var direction := Vector2(float(held["right"]) - float(held["left"]),
		float(held["down"]) - float(held["up"]))
	player += direction.normalized() * (92.0 + difficulty * 3.0) * delta
	player.x = clampf(player.x, FIELD.position.x + 8.0, FIELD.end.x - 12.0)
	player.y = clampf(player.y, FIELD.position.y + 8.0, FIELD.end.y - 8.0)
	_spawn_clock -= delta
	_item_clock -= delta
	if _spawn_clock <= 0.0:
		_spawn_clock = maxf(0.36, 1.18 - difficulty * 0.065) * rng.randf_range(0.72, 1.22)
		objects.append({"kind": "enemy", "pos": Vector2(FIELD.end.x + 8, rng.randf_range(32, 182)),
			"vel": Vector2(-rng.randf_range(62, 95) - difficulty * 4, rng.randf_range(-10, 10)),
			"hp": 1 + floori(float(difficulty) / 5.0)})
	if _item_clock <= 0.0 and progress < required and variant != "fighter":
		_item_clock = rng.randf_range(3.4, 5.4)
		objects.append({"kind": "cargo", "pos": Vector2(FIELD.end.x + 5, rng.randf_range(38, 178)),
			"vel": Vector2(-48 - difficulty * 2, 0), "hp": 1})
	for shot: Dictionary in shots:
		shot["pos"] = (shot["pos"] as Vector2) + (shot["vel"] as Vector2) * delta
	for object: Dictionary in objects:
		object["pos"] = (object["pos"] as Vector2) + (object["vel"] as Vector2) * delta
		var pos: Vector2 = object["pos"]
		if pos.distance_to(player) < (9.0 if object["kind"] == "enemy" else 12.0):
			if object["kind"] == "cargo":
				progress += 1; score += 900 + combo * 40; combo += 1; best_combo = maxi(best_combo, combo)
				object["dead"] = true; _emit("collect", pos)
			else:
				object["dead"] = true; _damage("HÜLLE VERLOREN")
	for shot: Dictionary in shots:
		for object: Dictionary in objects:
			if object.get("dead", false) or object["kind"] != "enemy":
				continue
			if (shot["pos"] as Vector2).distance_to(object["pos"] as Vector2) < 9.0:
				shot["dead"] = true
				object["hp"] = int(object["hp"]) - 1
				if int(object["hp"]) <= 0:
					object["dead"] = true; score += 240 + combo * 15; combo += 1
					if variant == "fighter":
						progress += 1
					best_combo = maxi(best_combo, combo); _emit("hit", object["pos"])
	shots = shots.filter(func(item: Dictionary) -> bool:
		return not bool(item.get("dead", false)) and (item["pos"] as Vector2).x < FIELD.end.x + 12)
	objects = objects.filter(func(item: Dictionary) -> bool:
		return not bool(item.get("dead", false)) and (item["pos"] as Vector2).x > FIELD.position.x - 20)
	var minimum_run := 14.0 if variant == "fighter" else minf(48.0, time_limit * 0.62)
	if progress >= required and elapsed >= minimum_run:
		_finish(true, "KOMMANDONETZ ZERSTÖRT" if variant == "fighter" else "FRACHT ZUGESTELLT")


func _press_shooter(action: String) -> void:
	if action == "fire" and shots.size() < 8:
		shots.append({"pos": player + Vector2(9, 0), "vel": Vector2(190, 0)})
		_emit("fire", player)
	elif action == "special":
		player.x = minf(FIELD.end.x - 12.0, player.x + 28.0)
		score = maxi(0, score - 25)
		_emit("boost", player)


# ---------------------------------------------------------------- Platform

func _setup_platform() -> void:
	if variant == "arena":
		required = int(definition.get("goal_primary", 6))
		player = Vector2(55, 165)
		_arena_ball = Vector2(160, 100)
		_arena_ball_velocity = Vector2(72, -18)
		platforms = [Rect2(8, 181, 304, 9), Rect2(90, 142, 62, 6), Rect2(206, 118, 54, 6)]
		return
	required = int(definition.get("goal_primary", 5 + floori(float(difficulty) / 4.0)))
	secondary = 1 if variant == "lava" else 0
	player = Vector2(22, 166)
	platforms = [Rect2(8, 181, 304, 9)]
	# Kuratierter, aber pro Titel leicht variierter Sprungpfad. Zufallsplattformen
	# konnten zuvor ausserhalb des Bildes oder in nicht erreichbarer Hoehe landen.
	var heights: Array[float] = [158.0, 136.0, 112.0, 88.0, 112.0, 136.0, 158.0, 132.0, 106.0]
	for i in 9:
		var x := 22.0 + float(i) * 32.0
		var y := heights[i] + rng.randf_range(-3.0, 3.0)
		platforms.append(Rect2(x, y, minf(46.0, FIELD.end.x - x), 6.0))
	objects = []
	for i in required:
		var route_ratio := float(i) / float(maxi(1, required - 1))
		var platform_index := 1 + roundi(route_ratio * float(platforms.size() - 2))
		var platform: Rect2 = platforms[platform_index]
		objects.append({"kind": "token", "pos": platform.position + Vector2(platform.size.x * 0.5, -8)})
	var last_platform: Rect2 = platforms.back()
	objects.append({"kind": "exit", "pos": Vector2(last_platform.end.x - 12.0,
		last_platform.position.y - 8.0)})


func _tick_platform(delta: float) -> void:
	var move := float(held["right"]) - float(held["left"])
	velocity.x = move_toward(velocity.x, move * (76.0 + difficulty * 2.0), 520.0 * delta)
	velocity.y += 250.0 * delta
	var old_y := player.y
	player += velocity * delta
	var landed := false
	for platform: Rect2 in platforms:
		if velocity.y >= 0.0 and old_y + 6.0 <= platform.position.y + 2.0 \
				and player.y + 6.0 >= platform.position.y \
				and player.x + 5.0 >= platform.position.x and player.x - 5.0 <= platform.end.x:
			player.y = platform.position.y - 6.0
			velocity.y = 0.0
			landed = true
	player.x = clampf(player.x, FIELD.position.x + 5, FIELD.end.x - 5)
	if player.y < FIELD.position.y + 6.0:
		player.y = FIELD.position.y + 6.0
		velocity.y = maxf(0.0, velocity.y)
	if player.y > FIELD.end.y + 12:
		player = Vector2(22, 166); velocity = Vector2.ZERO; _damage("IN DER TIEFE VERLOREN")
	grounded = landed
	if variant == "arena":
		_tick_arena(delta)
		return
	for object: Dictionary in objects:
		if object["kind"] == "token" and not object.get("dead", false) \
				and player.distance_to(object["pos"] as Vector2) < 11.0:
			object["dead"] = true; progress += 1; combo += 1; best_combo = maxi(best_combo, combo)
			score += 700 + combo * 60; _emit("collect", object["pos"])
		elif object["kind"] == "exit" and progress >= required \
				and player.distance_to(object["pos"] as Vector2) < 14.0:
			_finish(true, "AUSGANG ERREICHT")
	if landed and absf(move) > 0.1:
		score += 1
	if landed and variant == "lava":
		secondary = 1


func _tick_arena(delta: float) -> void:
	_arena_ball_velocity.y += 120.0 * delta
	_arena_ball += _arena_ball_velocity * delta
	if _arena_ball.y > 176:
		_arena_ball.y = 176; _arena_ball_velocity.y = -absf(_arena_ball_velocity.y) * 0.78
	if _arena_ball.y < 30:
		_arena_ball.y = 30; _arena_ball_velocity.y = absf(_arena_ball_velocity.y)
	if _arena_ball.distance_to(player) < 18.0:
		_arena_ball_velocity = (_arena_ball - player).normalized() * 122.0 + velocity * 0.65
		_emit("hit", _arena_ball)
	if _arena_ball.x > 313:
		progress += 1; score += 1400 + combo * 100; combo += 1; best_combo = maxi(best_combo, combo)
		_reset_arena_ball(-1.0); _emit("goal", Vector2(306, 104))
	elif _arena_ball.x < 7:
		# Wer rechtzeitig in die eigene Torzone zurueckkehrt, blockt. Zuvor
		# zaehlte selbst perfekte defensive Positionierung als Gegentor.
		if player.x < 62.0:
			_arena_ball.x = 8.0
			_arena_ball_velocity.x = absf(_arena_ball_velocity.x) * 0.92
			score += 120
			_emit("hit", _arena_ball)
		else:
			_arena_enemy_score += 1; combo = 0; _reset_arena_ball(1.0); _emit("damage", Vector2(14, 104))
	if progress >= required:
		_finish(true, "ARENA GEWONNEN")
	elif _arena_enemy_score >= 4:
		_finish(false, "ARENA VERLOREN")


func _reset_arena_ball(direction: float) -> void:
	_arena_ball = Vector2(160, 90)
	_arena_ball_velocity = Vector2(58.0 * direction, -31)


func _press_platform(action: String) -> void:
	if action == "fire" and grounded:
		velocity.y = -126.0 - difficulty * 1.5
		grounded = false
		_emit("jump", player)
	elif action == "special" and variant == "arena":
		if _arena_ball.distance_to(player) < 40.0:
			_arena_ball_velocity = Vector2(168, -52)
			_emit("hit", _arena_ball)
	elif action == "special" and variant == "lava" and secondary > 0:
		var direction := signf(velocity.x)
		if is_zero_approx(direction):
			direction = 1.0
		velocity = Vector2(direction * 118.0, -92.0)
		secondary = 0
		_emit("boost", player)


# ---------------------------------------------------------------- Circuit

func _setup_circuit() -> void:
	grid_solution.resize(CIRCUIT_W * CIRCUIT_H)
	grid.resize(CIRCUIT_W * CIRCUIT_H)
	var path: Array[Vector2i] = []
	for y in CIRCUIT_H:
		if y % 2 == 0:
			for x in CIRCUIT_W: path.append(Vector2i(x, y))
		else:
			for x in range(CIRCUIT_W - 1, -1, -1): path.append(Vector2i(x, y))
	for i in path.size():
		var mask := 0
		if i > 0: mask |= _bit_toward(path[i], path[i - 1])
		if i + 1 < path.size(): mask |= _bit_toward(path[i], path[i + 1])
		var index := path[i].y * CIRCUIT_W + path[i].x
		grid_solution[index] = mask
		var rotations := rng.randi_range(0, 3)
		grid[index] = _rotate_mask(mask, rotations)
	required = int(definition.get("goal_primary", 4 + floori(float(difficulty) / 3.0)))
	grid_targets = []
	for i in required:
		var spread := floori(float(i * (path.size() - 6)) / float(maxi(1, required - 1)))
		grid_targets.append(clampi(4 + spread, 1, path.size() - 2))
	# Kein bereits geloestes Brett.
	if grid == grid_solution:
		grid[3] = _rotate_mask(grid[3], 1)
	cursor = Vector2i.ZERO


func _bit_toward(from: Vector2i, to: Vector2i) -> int:
	var delta := to - from
	for i in DIRS.size():
		if DIRS[i] == delta:
			return BITS[i]
	return 0


func _rotate_mask(mask: int, rotations: int) -> int:
	var result := mask
	for _i in posmod(rotations, 4):
		result = ((result << 1) & 0xF) | ((result >> 3) & 1)
	return result


func connected_cells() -> Array[int]:
	if grid.is_empty(): return []
	var reached: Array[int] = [0]
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var index: int = int(queue.pop_front())
		var cell := Vector2i(index % CIRCUIT_W, floori(float(index) / float(CIRCUIT_W)))
		var mask := grid[index]
		for direction in DIRS.size():
			if (mask & BITS[direction]) == 0: continue
			var next: Vector2i = cell + DIRS[direction]
			if next.x < 0 or next.y < 0 or next.x >= CIRCUIT_W or next.y >= CIRCUIT_H: continue
			var ni: int = next.y * CIRCUIT_W + next.x
			if (grid[ni] & OPPOSITE[direction]) != 0 and ni not in reached:
				reached.append(ni); queue.append(ni)
	return reached


func connected_target_count() -> int:
	var reached := connected_cells()
	var count := 0
	for target: int in grid_targets:
		if target in reached: count += 1
	return count


func _press_circuit(action: String) -> void:
	match action:
		"left": cursor.x = posmod(cursor.x - 1, CIRCUIT_W)
		"right": cursor.x = posmod(cursor.x + 1, CIRCUIT_W)
		"up": cursor.y = posmod(cursor.y - 1, CIRCUIT_H)
		"down": cursor.y = posmod(cursor.y + 1, CIRCUIT_H)
		"fire":
			var index := cursor.y * CIRCUIT_W + cursor.x
			grid[index] = _rotate_mask(grid[index], 1); secondary += 1; score = maxi(0, score - 8)
			_emit("rotate", Vector2(cursor) )
		"hint", "special":
			for i in grid.size():
				if grid[i] != grid_solution[i]:
					grid[i] = _rotate_mask(grid[i], 1); score = maxi(0, score - 180); secondary += 1
					cursor = Vector2i(i % CIRCUIT_W, floori(float(i) / float(CIRCUIT_W)))
					_emit("hint", Vector2(cursor)); break
	if connected_target_count() >= required and (grid.size() - 1) in connected_cells():
		score += 5000 + difficulty * 500 - secondary * 12
		_finish(true, "SIGNALWEG STABIL")


# ---------------------------------------------------------------- Miner

func _setup_miner() -> void:
	required = int(definition.get("goal_primary", 7 + floori(float(difficulty) / 3.0)))
	health = 72 + difficulty * 4
	player = Vector2(0, 0)
	grid.resize(GRID_W * GRID_H)
	for i in grid.size():
		grid[i] = 1 if rng.randf() < 0.28 else 0
	grid[0] = 0
	objects = []
	for i in required + 3:
		var cell := Vector2i(rng.randi_range(1, GRID_W - 1), rng.randi_range(1, GRID_H - 1))
		objects.append({"kind": "crystal", "cell": cell, "dead": false})
	cursor = Vector2i.ZERO


func _press_miner(action: String) -> void:
	var delta := Vector2i.ZERO
	match action:
		"left": delta = Vector2i.LEFT
		"right": delta = Vector2i.RIGHT
		"up": delta = Vector2i.UP
		"down": delta = Vector2i.DOWN
		"fire", "special":
			health = mini(99, health + 3); score = maxi(0, score - 90); _emit("support", Vector2(cursor)); return
	if delta == Vector2i.ZERO: return
	var next := cursor + delta
	if next.x < 0 or next.y < 0 or next.x >= GRID_W or next.y >= GRID_H: return
	var index := next.y * GRID_W + next.x
	var cost := 3 if grid[index] == 1 else 1
	grid[index] = 0
	health -= cost
	cursor = next
	score += 18 * cost
	for object: Dictionary in objects:
		if not bool(object.get("dead", false)) and object["cell"] == cursor:
			object["dead"] = true; progress += 1; score += 850; _emit("collect", Vector2(cursor))
	if health <= 0:
		_finish(false, "SAUERSTOFF LEER")
	elif progress >= required and cursor == Vector2i.ZERO:
		_finish(true, "FÖRDERUNG ABGESCHLOSSEN")


# ---------------------------------------------------------------- Rescue

func _setup_rescue() -> void:
	required = int(definition.get("goal_primary", 4 + floori(float(difficulty) / 4.0)))
	health = 5 if difficulty >= 6 else 4
	player = base_position
	objects = []
	for i in required:
		objects.append({"kind": "survivor", "pos": _rescue_spawn(42.0), "dead": false})
	for i in 4 + floori(float(difficulty) / 2.0):
		objects.append({"kind": "hazard", "pos": _rescue_hazard_spawn(),
			"radius": rng.randf_range(7, 13)})


func _rescue_spawn(minimum_distance: float) -> Vector2:
	var candidate := Vector2(160, 100)
	for _attempt in 48:
		candidate = Vector2(rng.randf_range(78, 298), rng.randf_range(35, 179))
		if candidate.distance_to(base_position) < 45.0:
			continue
		var valid := true
		for object: Dictionary in objects:
			if candidate.distance_to(object.get("pos", Vector2.ZERO)) < minimum_distance:
				valid = false
				break
		if valid:
			return candidate
	return candidate


func _rescue_hazard_spawn() -> Vector2:
	var candidate := Vector2(160, 100)
	for _attempt in 96:
		candidate = Vector2(rng.randf_range(78, 298), rng.randf_range(35, 179))
		if candidate.distance_to(base_position) < 43.0:
			continue
		var valid := true
		for object: Dictionary in objects:
			var minimum := 31.0 if str(object.get("kind", "")) == "survivor" else 17.0
			if candidate.distance_to(object.get("pos", Vector2.ZERO)) < minimum:
				valid = false
				break
		if valid:
			return candidate
	return candidate


func _tick_rescue(delta: float) -> void:
	_damage_cooldown = maxf(0.0, _damage_cooldown - delta)
	if secondary > 0:
		secondary = maxi(0, secondary - 1)
	var direction := Vector2(float(held["right"]) - float(held["left"]), float(held["down"]) - float(held["up"]))
	velocity += direction.normalized() * 92.0 * delta
	velocity = velocity.limit_length(58.0 + difficulty * 1.5)
	velocity *= pow(0.88, delta * 10.0)
	player += velocity * delta
	if player.x < FIELD.position.x or player.x > FIELD.end.x:
		velocity.x *= -0.65; player.x = clampf(player.x, FIELD.position.x, FIELD.end.x)
	if player.y < FIELD.position.y or player.y > FIELD.end.y:
		velocity.y *= -0.65; player.y = clampf(player.y, FIELD.position.y, FIELD.end.y)
	for object: Dictionary in objects:
		var pos: Vector2 = object["pos"]
		if object["kind"] == "survivor" and not object.get("dead", false) and player.distance_to(pos) < 12.0:
			object["dead"] = true; progress += 1; score += 1100; _emit("collect", pos)
		elif object["kind"] == "hazard" and not object.get("cool", false) and _damage_cooldown <= 0.0 \
				and player.distance_to(pos) < float(object.get("radius", 9)) + 5.0:
			object["cool"] = true; object["cool_time"] = 1.0; _damage_cooldown = 0.9
			velocity *= -0.5; _damage("RETTUNGSFAHRZEUG VERLOREN")
		if object.get("cool", false):
			object["cool_time"] = float(object.get("cool_time", 0.0)) - delta
			if float(object["cool_time"]) <= 0.0: object["cool"] = false
	if progress >= required and player.distance_to(base_position) < 16.0:
		_finish(true, "ALLE SIGNALQUELLEN GEBORGEN")


func _press_rescue(action: String) -> void:
	if action in ["fire", "hint"]:
		secondary = 30; score = maxi(0, score - 25); _emit("sonar", player)
	elif action == "special":
		velocity *= 0.25; _emit("brake", player)


# ---------------------------------------------------------------- Stealth

func _setup_stealth() -> void:
	required = int(definition.get("goal_primary", 3 + floori(float(difficulty) / 4.0)))
	health = 3
	cursor = Vector2i(1, GRID_H - 2)
	objects = []
	for i in required:
		objects.append({"kind": "terminal", "cell": Vector2i(4 + (i * 4) % 11, 1 + (i * 3) % 6), "dead": false})
	for i in 3 + floori(float(difficulty) / 2.0):
		objects.append({"kind": "guard", "cell": Vector2i(3 + (i * 3) % 12, 1 + (i * 2) % 7),
			"dir": 1 if i % 2 == 0 else -1, "axis": i % 2})
	objects.append({"kind": "exit", "cell": Vector2i(GRID_W - 2, 1)})


func _tick_stealth(delta: float) -> void:
	# Alarm ist ein lesbarer Spielzustand, kein bildratenabhaengiger Zaehler.
	# Zuvor verschwand ein Sichtkontakt bei 50 Hz binnen einer halben Sekunde,
	# obwohl er gleichzeitig sofort ein Leben kostete. Nun klingt Alarm langsam
	# in Echtzeit ab; ein einzelner Kontakt kann den Spieler nicht mehr toeten.
	if secondary <= 0:
		_stealth_decay_clock = 0.0
		return
	_stealth_decay_clock += delta
	while _stealth_decay_clock >= 1.0:
		_stealth_decay_clock -= 1.0
		secondary = maxi(0, secondary - 2)


func _press_stealth(action: String) -> void:
	if action == "fire":
		for object: Dictionary in objects:
			if object["kind"] == "terminal" and not object.get("dead", false) and object["cell"] == cursor:
				object["dead"] = true; progress += 1; score += 1300; _emit("hack", Vector2(cursor)); return
		return
	if action in ["special", "wait"]:
		_advance_guards(12); return
	var delta := Vector2i.ZERO
	match action:
		"left": delta = Vector2i.LEFT
		"right": delta = Vector2i.RIGHT
		"up": delta = Vector2i.UP
		"down": delta = Vector2i.DOWN
	if delta == Vector2i.ZERO: return
	var next := cursor + delta
	if next.x < 0 or next.y < 0 or next.x >= GRID_W or next.y >= GRID_H: return
	cursor = next
	# Sind alle Daten gesichert, ist das Betreten des Ausgangs der eindeutige
	# Abschluss. Der alte Ablauf liess erst alle Kameras zuschlagen und pruefte
	# den Ausgang danach; ein korrekter letzter Zug konnte so im Vollalarm enden.
	for object: Dictionary in objects:
		if object["kind"] == "exit" and object["cell"] == cursor and progress >= required:
			_finish(true, "HAUPTSCHLÜSSEL EXPORTIERT" if variant == "network" else "SPUR GELÖSCHT")
			return
	_advance_guards(4)


func _advance_guards(safe_cooldown := 4) -> void:
	var detected := false
	var detection_cell := cursor
	for object: Dictionary in objects:
		if object["kind"] != "guard": continue
		var cell: Vector2i = object["cell"]
		var axis := int(object["axis"])
		var direction := int(object["dir"])
		cell[axis] += direction
		if cell[axis] <= 1 or cell[axis] >= ([GRID_W, GRID_H][axis] - 2):
			direction *= -1; cell[axis] = clampi(cell[axis], 1, [GRID_W, GRID_H][axis] - 2)
		object["cell"] = cell; object["dir"] = direction
		var sees := stealth_guard_sees(cell, axis, cursor)
		if sees:
			detected = true
			detection_cell = cursor
	if not detected:
		secondary = maxi(0, secondary - safe_cooldown)
		return
	secondary = mini(STEALTH_ALARM_MAX, secondary + STEALTH_DETECTION_GAIN)
	score = maxi(0, score - 120)
	_emit("alert", Vector2(detection_cell))
	if secondary < STEALTH_ALARM_MAX:
		return
	# Erst ein gefuellter Alarm kostet ein Leben. Danach beginnt ein klarer
	# neuer Infiltrationsversuch statt einer kaum sichtbaren Todesspirale.
	secondary = 0
	_stealth_decay_clock = 0.0
	cursor = Vector2i(1, GRID_H - 2)
	_damage("VOLLALARM")


static func stealth_guard_sees(cell: Vector2i, axis: int, target: Vector2i) -> bool:
	return (axis == 0 and cell.y == target.y and absi(cell.x - target.x) <= 4) \
		or (axis == 1 and cell.x == target.x and absi(cell.y - target.y) <= 3)


# ---------------------------------------------------------------- Racer

func _setup_racer() -> void:
	required = int(definition.get("goal_primary", 18 + (difficulty - 3) * 2))
	auxiliary_required = int(definition.get("goal_secondary", maxi(3, difficulty - 1)))
	health = 5 if difficulty >= 7 else 4
	lane = 2
	player = Vector2(_lane_x(lane), 168)


func _tick_racer(delta: float) -> void:
	_damage_cooldown = maxf(0.0, _damage_cooldown - delta)
	var speed := 0.22 + difficulty * 0.012 + (0.12 if held["up"] else 0.0) - (0.08 if held["down"] else 0.0)
	distance += speed * delta
	score += roundi(speed * 24.0)
	_spawn_clock -= delta
	_item_clock -= delta
	if _spawn_clock <= 0:
		_spawn_clock = maxf(0.42, 1.0 - difficulty * 0.045) * rng.randf_range(0.75, 1.2)
		objects.append({"kind": "traffic", "lane": rng.randi_range(0, 4), "y": 24.0, "speed": rng.randf_range(48, 78) + difficulty * 3})
	if _item_clock <= 0:
		_item_clock = rng.randf_range(2.2, 3.8)
		objects.append({"kind": "marker", "lane": rng.randi_range(0, 4), "y": 24.0, "speed": 62.0 + difficulty * 2})
	for object: Dictionary in objects:
		object["y"] = float(object["y"]) + float(object["speed"]) * delta
		if not object.get("dead", false) and int(object["lane"]) == lane and absf(float(object["y"]) - player.y) < 13.0:
			object["dead"] = true
			if object["kind"] == "marker":
				progress += 1; combo += 1; best_combo = maxi(best_combo, combo); score += 650; _emit("collect", player)
			elif _damage_cooldown <= 0.0:
				_damage_cooldown = 0.85
				_damage("MASCHINE ZERSTÖRT")
	objects = objects.filter(func(item: Dictionary) -> bool:
		return not bool(item.get("dead", false)) and float(item["y"]) < 198.0)
	if distance >= float(required) and progress >= auxiliary_required:
		_finish(true, "KONTROLLPUNKT ERREICHT")


func _lane_x(index: int) -> float:
	return 64.0 + index * 48.0


func _press_racer(action: String) -> void:
	if action == "left": lane = maxi(0, lane - 1)
	elif action == "right": lane = mini(4, lane + 1)
	elif action in ["fire", "special"]:
		distance += 0.35; score += 80; _emit("boost", player)
	player.x = _lane_x(lane)


# ---------------------------------------------------------------- Strategy

func _setup_strategy() -> void:
	match variant:
		"trade": resource_names = ["KONTO", "FRACHT", "RUF", "RUMPF"]
		"defense": resource_names = ["SCHILD", "GESCHÜTZ", "REPARATUR", "ENERGIE"]
		"tactics": resource_names = ["SPÄHER", "PANZER", "NACHSCHUB", "KONTROLLE"]
		"colony": resource_names = ["SAUERSTOFF", "ENERGIE", "MORAL", "VORRAT"]
		"exodus": resource_names = ["MENSCHEN", "WISSEN", "SAATGUT", "ENERGIE"]
		_: resource_names = ["SCHILD", "ENERGIE", "MORAL", "VORRAT"]
	resources = [58, 55, 52, 60]
	_strategy_goal = int(definition.get("goal_primary", 9 + floori(float(difficulty) / 2.0)))
	threshold_required = float(definition.get("goal_threshold", 35.0))
	turn = 0
	_make_forecast()


func _make_forecast() -> void:
	forecast = []
	for i in 4:
		# Sichtbare Prognosen muessen anspruchsvoll, aber mit dem vorhandenen
		# 12/20-Punkte-Budget wirklich beherrschbar sein. Die alte Verteilung
		# vernichtete auf hohen Stufen im Mittel mehr als das Doppelte des
		# maximalen Budgets und machte 1998/99 mathematisch unloesbar.
		var pressure := rng.randi_range(-5 - floori(float(difficulty) / 2.0), 3)
		forecast.append(pressure)
	# Mindestens eine erkennbare Chance statt viermal nur Verlust.
	forecast[rng.randi_range(0, 3)] += 6


func _press_strategy(action: String) -> void:
	match action:
		"up", "left": selected = posmod(selected - 1, resources.size())
		"down", "right": selected = posmod(selected + 1, resources.size())
		"special": allocation = 20 if allocation == 12 else 12
		"fire": _resolve_strategy_turn()


func _resolve_strategy_turn() -> void:
	resources[selected] = mini(100, resources[selected] + allocation)
	for i in resources.size():
		resources[i] = clampi(resources[i] + forecast[i], 0, 100)
	turn += 1
	progress += 1 if float(_resource_min()) >= threshold_required else 0
	score += _resource_min() * 8 + resources.reduce(func(sum: int, value: int) -> int: return sum + value, 0)
	_emit("turn", Vector2(selected, turn))
	if _resource_min() <= 0:
		_finish(false, "%s AUSGEFALLEN" % resource_names[resources.find(_resource_min())])
	elif turn >= _strategy_goal:
		if float(_resource_min()) >= threshold_required:
			_finish(true, "LAGE STABILISIERT")
		else:
			_finish(false, "SYSTEM NICHT TRAGFÄHIG")
	else:
		_make_forecast()


func _resource_min() -> int:
	return resources.min() if not resources.is_empty() else 0


# ---------------------------------------------------------------- Rhythm

func _setup_rhythm() -> void:
	required = int(definition.get("note_count", 24 + difficulty * 3))
	threshold_required = float(definition.get("goal_accuracy", 0.70 + float(difficulty - 4) * 0.025))
	auxiliary_required = int(definition.get("goal_combo", 10 + difficulty * 2))
	rhythm_hit_window = clampf(float(definition.get("hit_window", 0.23)), 0.16, 0.36)
	rhythm_phase_assists = maxi(0, int(definition.get("phase_assists", 0)))
	song_notes = []
	var beat := 1.2
	var note_interval := maxf(0.30,
		float(definition.get("note_interval", 0.44 - difficulty * 0.018)))
	for i in required:
		beat += note_interval
		song_notes.append({"time": beat, "lane": (i * 3 + rng.randi_range(0, 2)) % 4, "hit": false, "miss": false})
	time_limit = minf(time_limit, beat + 3.0)


func _tick_rhythm(_delta: float) -> void:
	while _next_note < song_notes.size() and elapsed - float(song_notes[_next_note]["time"]) > rhythm_hit_window:
		var note: Dictionary = song_notes[_next_note].duplicate(true)
		if not note["hit"]:
			note["miss"] = true
			song_notes[_next_note] = note
			accuracy_misses += 1
			combo = 0
			_emit("miss", Vector2(float(note["lane"]), 0))
		_next_note += 1
	if _next_note >= song_notes.size() and elapsed > float(song_notes.back()["time"]) + 0.8:
		if accuracy() >= threshold_required and best_combo >= auxiliary_required:
			_finish(true, "REAKTOR SYNCHRON")
		else:
			_finish(false, "TAKTUNG INSTABIL")


func _press_rhythm(action: String) -> void:
	var lane_index := ["lane0", "lane1", "lane2", "lane3"].find(action)
	if lane_index < 0:
		if action == "special" and rhythm_phase_assists > 0:
			_use_rhythm_phase_assist()
		return
	var best_index := -1
	var best_delta := 99.0
	for i in range(maxi(0, _next_note - 1), mini(song_notes.size(), _next_note + 4)):
		var note: Dictionary = song_notes[i]
		if note["hit"] or note["miss"] or int(note["lane"]) != lane_index: continue
		var timing := absf(elapsed - float(note["time"]))
		if timing < best_delta: best_delta = timing; best_index = i
	if best_index >= 0 and best_delta <= rhythm_hit_window:
		_register_rhythm_hit(best_index, best_delta)
	else:
		accuracy_misses += 1; combo = 0; score = maxi(0, score - 80); _emit("miss", Vector2(lane_index, 0))


func _use_rhythm_phase_assist() -> void:
	var best_index := -1
	var best_delta := 99.0
	for i in range(maxi(0, _next_note - 1), mini(song_notes.size(), _next_note + 4)):
		var note: Dictionary = song_notes[i]
		if note["hit"] or note["miss"]:
			continue
		var timing := absf(elapsed - float(note["time"]))
		if timing < best_delta:
			best_delta = timing
			best_index = i
	if best_index < 0 or best_delta > rhythm_hit_window + 0.12:
		_emit("hint", player)
		return
	rhythm_phase_assists -= 1
	_register_rhythm_hit(best_index, best_delta, true)


func _register_rhythm_hit(index: int, timing: float, assisted := false) -> void:
	var note: Dictionary = song_notes[index].duplicate(true)
	note["hit"] = true
	note["assisted"] = assisted
	song_notes[index] = note
	accuracy_hits += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	var quality := 350 if assisted else (
		1000 if timing <= 0.07 else (650 if timing <= 0.14 else 350))
	score += quality + combo * (20 if assisted else 25)
	_emit("hit" if assisted or timing > 0.07 else "perfect",
		Vector2(float(note["lane"]), 0))
