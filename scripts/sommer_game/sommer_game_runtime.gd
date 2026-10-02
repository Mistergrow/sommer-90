class_name SommerGameRuntime
extends RefCounted
## Deterministische, sandboxed Referenzruntime fuer Action- und Strategiespiele.
## Sie besitzt keine Nodes, kein FileAccess und kein Netzwerk.

const Catalog := preload("res://scripts/data/sommer_game_module_catalog.gd")
const GRAVITY := 0.22
const WORLD_WIDTH := 320
const WORLD_HEIGHT := 200

var unlocked_modules: Array = []
var active := false
var tick := 0
var map_id := ""
var sprite_bank := ""
var camera := Vector2.ZERO
var terrain: PackedInt32Array = PackedInt32Array()
var players: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var tiles: Dictionary = {}
var zones: Dictionary = {}
var power_links: Array = []
var traffic_routes: Array = []
var population := 0
var city_money := 1000
var dialogue_state: Dictionary = {}
var debug_values: Dictionary = {}
var saves: Dictionary = {}
var build_version := 0
var network_players := 1
var frame_cost := 0


func reset(context: Dictionary = {}) -> void:
	unlocked_modules = (context.get("unlocked_modules", []) as Array).duplicate()
	active = false; tick = 0; map_id = ""; sprite_bank = ""; camera = Vector2.ZERO
	players.clear(); projectiles.clear(); particles.clear(); tiles.clear(); zones.clear()
	power_links.clear(); traffic_routes.clear(); dialogue_state.clear(); debug_values.clear()
	population = 0; city_money = 1000; frame_cost = 0
	build_version = 0; network_players = 1; saves.clear()
	terrain.resize(WORLD_WIDTH)
	for x in WORLD_WIDTH:
		terrain[x] = 138 + int(12.0 * sin(float(x) * 0.055))


func execute(operation: String, args: Array) -> Dictionary:
	var word := operation.to_upper()
	var module := Catalog.module_for_symbol(word)
	if module.is_empty() or str(module.get("id", "")) not in unlocked_modules:
		return {"ok": false, "error": "%s: Sommer-Game-Modul ist nicht freigeschaltet." % word}
	frame_cost += 1
	match word:
		"GAMESTART": active = true
		"GAMESTOP": active = false
		"LOADMAP": _load_map(str(args[0]))
		"LOADSPRITES": sprite_bank = str(args[0])
		"ADDPLAYER": players.append({"x": float(args[0]), "y": float(args[1]),
			"team": int(args[2]) if args.size() > 2 else 0, "vx": 0.0, "vy": 0.0,
			"frame": 0, "health": 100})
		"UPDATEPLAYERS": _update_players()
		"DRAWWORLD": return {"ok": true, "draw": _draw_world()}
		"SAVEGAME": saves[str(args[0])] = _state_snapshot()
		"LOADGAME":
			var slot := str(args[0])
			if not saves.has(slot):
				return {"ok": false, "error": "LOADGAME: Spielstand %s existiert nicht." % slot}
			_load_snapshot(saves[slot])
		"ANIMATE":
			var player_index := int(args[0])
			if player_index >= 0 and player_index < players.size():
				players[player_index]["frame"] = int(args[1])
		"MIXSOUND": return {"ok": true, "audio": [{"op": "mixsound", "args": args.duplicate(true)}]}
		"ADVSTATE": dialogue_state[str(args[0])] = args[1]
		"DIALOGUE": dialogue_state["node"] = str(args[0])
		"DEBUGBREAK": debug_values["break"] = str(args[0])
		"DEBUGVALUE": debug_values[str(args[0])] = args[1]
		"SETTILE": tiles[Vector2i(int(args[0]), int(args[1]))] = int(args[2])
		"MAPLAYER": dialogue_state["map_layer"] = int(args[0])
		"DESTROYTERRAIN": _destroy_terrain(int(args[0]), int(args[1]), int(args[2]))
		"FIREPROJECTILE": projectiles.append({"x": float(args[0]), "y": float(args[1]),
			"vx": float(args[2]), "vy": float(args[3]), "power": int(args[4]) if args.size() > 4 else 12})
		"UPDATEPHYSICS": _update_physics()
		"EMITPARTICLES": _emit_particles(float(args[0]), float(args[1]), int(args[2]))
		"CAMERA": camera = Vector2(float(args[0]), float(args[1]))
		"AISTEP": _ai_step()
		"GUIWINDOW": return {"ok": true, "draw": [{"op": "window", "args": args.duplicate(true)}]}
		"GUITEXT": return {"ok": true, "draw": [{"op": "text", "args": args.duplicate(true)}]}
		"SIMULATE": _simulate()
		"NETWORKSYNC": network_players = maxi(2, network_players); tick += 1
		"ZONE": zones[Vector2i(int(args[0]), int(args[1]))] = str(args[2]).to_upper()
		"POWERLINK": power_links.append(args.duplicate(true))
		"TRAFFICROUTE": traffic_routes.append(args.duplicate(true))
		"COLORPIPE": dialogue_state["color_profile"] = str(args[0])
		"TARGETVIDEO": dialogue_state["video_target"] = str(args[0])
		"EXPORTBUILD": build_version += 1; dialogue_state["last_build"] = [str(args[0]), str(args[1])]
		"PROFILEFRAME": debug_values["last_frame_cost"] = frame_cost; frame_cost = 0
	return {"ok": true}


func value(function_name: String, args: Array) -> Variant:
	match function_name.to_upper():
		"GAMEACTIVE": return active
		"COLLIDE":
			if args.size() < 2: return false
			var a := int(args[0]); var b := int(args[1])
			return a >= 0 and b >= 0 and a < players.size() and b < players.size() \
				and Vector2(float(players[a]["x"]), float(players[a]["y"])).distance_to(Vector2(float(players[b]["x"]), float(players[b]["y"]))) < 12.0
		"FRAMECOST": return frame_cost
		"GETTILE": return int(tiles.get(Vector2i(int(args[0]), int(args[1])), 0)) if args.size() >= 2 else 0
		"TERRAINHEIGHT": return terrain[clampi(int(args[0]), 0, WORLD_WIDTH - 1)] if not args.is_empty() else 0
		"PROJECTILECOUNT": return projectiles.size()
		"PARTICLECOUNT": return particles.size()
		"POPULATION": return population
		"CITYMONEY": return city_money
		"NETPLAYERS": return network_players
		"POWERED": return not power_links.is_empty()
		"TRAFFIC": return traffic_routes.size() * 12
		"BUILDVERSION": return build_version
	return 0


func snapshot() -> Dictionary:
	return _state_snapshot().merged({"unlocked_modules": unlocked_modules.duplicate(),
		"terrain_sample": Array(terrain).slice(0, WORLD_WIDTH, 16)}, true)


func _load_map(id: String) -> void:
	map_id = id
	if id.to_upper().contains("CITY"):
		zones.clear(); population = 0; city_money = 1000


func _update_players() -> void:
	for player: Dictionary in players:
		player["x"] = clampf(float(player["x"]) + float(player.get("vx", 0.0)), 0.0, WORLD_WIDTH - 1.0)
		player["y"] = minf(float(player["y"]), float(terrain[clampi(int(player["x"]), 0, WORLD_WIDTH - 1)] - 2))


func _update_physics() -> void:
	tick += 1
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile: Dictionary = projectiles[index]
		projectile["x"] = float(projectile["x"]) + float(projectile["vx"])
		projectile["y"] = float(projectile["y"]) + float(projectile["vy"])
		projectile["vy"] = float(projectile["vy"]) + GRAVITY
		var x := int(projectile["x"]); var y := int(projectile["y"])
		if x < 0 or x >= WORLD_WIDTH or y >= WORLD_HEIGHT or y >= terrain[x]:
			if x >= 0 and x < WORLD_WIDTH:
				_destroy_terrain(x, mini(y, terrain[x]), int(projectile["power"]))
				_emit_particles(x, mini(y, terrain[x]), 8)
			projectiles.remove_at(index)
	for index in range(particles.size() - 1, -1, -1):
		particles[index]["life"] = int(particles[index]["life"]) - 1
		if int(particles[index]["life"]) <= 0: particles.remove_at(index)


func _destroy_terrain(center_x: int, center_y: int, radius: int) -> void:
	for x in range(maxi(0, center_x - radius), mini(WORLD_WIDTH, center_x + radius + 1)):
		var dx := x - center_x
		var depth := int(sqrt(maxf(0.0, float(radius * radius - dx * dx))))
		if terrain[x] <= center_y + depth: terrain[x] = mini(WORLD_HEIGHT, center_y + depth)


func _emit_particles(x: float, y: float, count: int) -> void:
	for index in mini(count, 64):
		particles.append({"x": x, "y": y, "life": 10 + (index % 9), "color": 2 + (index % 5)})


func _ai_step() -> void:
	if players.size() < 2: return
	var direction := signf(float(players[0]["x"]) - float(players[1]["x"]))
	players[1]["vx"] = direction * 0.5


func _simulate() -> void:
	tick += 1
	var residential := zones.values().count("RESIDENTIAL") + zones.values().count("WOHNEN")
	var commercial := zones.values().count("COMMERCIAL") + zones.values().count("GEWERBE")
	var powered_bonus := 2 if not power_links.is_empty() else 0
	population = maxi(0, population + residential * (1 + powered_bonus) - commercial)
	city_money += commercial * 8 + int(float(population) / 25.0) - zones.size()


func _draw_world() -> Array:
	var draw: Array = [{"op": "screen", "args": [WORLD_WIDTH, WORLD_HEIGHT, 16]},
		{"op": "terrain", "args": [Array(terrain), camera.x, camera.y]}]
	for player: Dictionary in players:
		draw.append({"op": "sprite", "args": [0, player["x"], player["y"], player.get("frame", 0), true]})
	for projectile: Dictionary in projectiles:
		draw.append({"op": "plot", "args": [projectile["x"], projectile["y"], 3]})
	return draw


func _state_snapshot() -> Dictionary:
	return {"active": active, "tick": tick, "map_id": map_id, "sprite_bank": sprite_bank,
		"camera": [camera.x, camera.y], "players": players.duplicate(true),
		"projectiles": projectiles.duplicate(true), "particles": particles.duplicate(true),
		"tiles": tiles.duplicate(true), "zones": zones.duplicate(true),
		"power_links": power_links.duplicate(true), "traffic_routes": traffic_routes.duplicate(true),
		"population": population, "city_money": city_money, "dialogue_state": dialogue_state.duplicate(true),
		"debug_values": debug_values.duplicate(true), "build_version": build_version,
		"network_players": network_players, "frame_cost": frame_cost}


func _load_snapshot(raw: Variant) -> void:
	if not raw is Dictionary: return
	var data := raw as Dictionary
	active = bool(data.get("active", false))
	tick = int(data.get("tick", 0))
	map_id = str(data.get("map_id", ""))
	sprite_bank = str(data.get("sprite_bank", ""))
	var saved_camera: Array = data.get("camera", [0.0, 0.0])
	camera = Vector2(float(saved_camera[0]), float(saved_camera[1])) if saved_camera.size() >= 2 else Vector2.ZERO
	players = (data.get("players", []) as Array).duplicate(true)
	projectiles = (data.get("projectiles", []) as Array).duplicate(true)
	particles = (data.get("particles", []) as Array).duplicate(true)
	tiles = (data.get("tiles", {}) as Dictionary).duplicate(true)
	zones = (data.get("zones", {}) as Dictionary).duplicate(true)
	power_links = (data.get("power_links", []) as Array).duplicate(true)
	traffic_routes = (data.get("traffic_routes", []) as Array).duplicate(true)
	population = int(data.get("population", 0))
	city_money = int(data.get("city_money", 1000))
	dialogue_state = (data.get("dialogue_state", {}) as Dictionary).duplicate(true)
	debug_values = (data.get("debug_values", {}) as Dictionary).duplicate(true)
	build_version = int(data.get("build_version", 0))
	network_players = int(data.get("network_players", 1))
	frame_cost = int(data.get("frame_cost", 0))
