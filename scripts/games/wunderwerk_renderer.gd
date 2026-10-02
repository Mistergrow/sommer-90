extends RefCounted
## OCS-Isometrierenderer aus festen Tiles und maskierten Blitter-Objekten.
## Die Spielwelt verwendet keine prozedural gezeichneten Ersatzobjekte:
## Boden, Wege, Grenzen, Szenerie, Figuren und Betriebe stammen aus 32-Farb-
## Atlanten. Linien/Polygone bleiben ausschliesslich Interaktionsmarkierungen.

const Catalog := preload("res://scripts/games/wunderwerk_catalog.gd")
const Pathfinder := preload("res://scripts/games/wunderwerk_pathfinder.gd")
const RIDES_PATH := "res://assets/ui/games/wunderwerk_94/sprites/rides_shops_ocs_v01.png"
const CHARACTERS_PATH := "res://assets/ui/games/wunderwerk_94/sprites/characters_ocs_v01.png"
const TERRAIN_PATH := "res://assets/ui/games/wunderwerk_94/sprites/terrain_ocs_v01.png"
const SCENERY_PATH := "res://assets/ui/games/wunderwerk_94/sprites/scenery_ocs_v01.png"
const SERVICES_PATH := "res://assets/ui/games/wunderwerk_94/sprites/services_ocs_v01.png"
const PATHS_PATH := "res://assets/ui/games/wunderwerk_94/sprites/paths_ocs_v01.png"
const RIDES_EXTRA_PATH := "res://assets/ui/games/wunderwerk_94/sprites/rides_extra_ocs_v01.png"

const TILE_W := 16.0
const TILE_H := 8.0
const HALF_W := TILE_W * 0.5
const HALF_H := TILE_H * 0.5
const RIDE_CELL := Vector2(72, 64)
const CHARACTER_CELL := Vector2(20, 26)
const TERRAIN_CELL := Vector2(32, 28)
const SCENERY_CELL := Vector2(40, 44)
const SERVICE_CELL := Vector2(48, 52)
const PATH_CELL := Vector2(16, 8)

const INK := Color8(0, 0, 17)
const RED := Color8(204, 68, 34)
const CYAN := Color8(51, 204, 221)
const AMBER := Color8(255, 204, 51)
const WHITE := Color8(238, 238, 221)

var _rides: Texture2D = _texture_from_png(RIDES_PATH)
var _characters: Texture2D = _texture_from_png(CHARACTERS_PATH)
var _terrain: Texture2D = _texture_from_png(TERRAIN_PATH)
var _scenery: Texture2D = _texture_from_png(SCENERY_PATH)
var _services: Texture2D = _texture_from_png(SERVICES_PATH)
var _paths: Texture2D = _texture_from_png(PATHS_PATH)
var _rides_extra: Texture2D = _texture_from_png(RIDES_EXTRA_PATH)
var _environment_revision := -1
var _environment_origin := Vector2(1.0e20, 1.0e20)
var _environment_cache: Array[Dictionary] = []
var _visible_origin := Vector2(1.0e20, 1.0e20)
var _visible_ground_cache: Array[Vector2i] = []


func cell_to_screen(cell: Vector2, origin: Vector2) -> Vector2:
	return origin + Vector2((cell.x - cell.y) * HALF_W,
		(cell.x + cell.y) * HALF_H)


func screen_to_cell(point: Vector2, origin: Vector2) -> Vector2i:
	var local := point - origin
	var x := local.y / TILE_H + local.x / TILE_W
	var y := local.y / TILE_H - local.x / TILE_W
	return Vector2i(floori(x), floori(y))


func draw_world(canvas: CanvasItem, model, origin: Vector2, cursor: Vector2i,
		selected_tool: String, selected_object_id: int, time_seconds: float) -> void:
	_draw_ground_tiles(canvas, model, origin, time_seconds)
	var drawables: Array[Dictionary] = _environment_drawables(model, origin)
	for object: Dictionary in model.objects:
		var cell: Vector2i = object["cell"]
		var footprint: Vector2i = object["size"]
		drawables.append({"kind": "object", "data": object,
			"depth": cell.x + cell.y + footprint.x + footprint.y})
	for guest: Dictionary in model.guests:
		if str(guest["state"]) == "ride":
			continue
		var position := _entity_cell(guest)
		drawables.append({"kind": "guest", "data": guest,
			"depth": position.x + position.y + 0.45})
	for worker: Dictionary in model.staff:
		var position := _entity_cell(worker)
		drawables.append({"kind": "staff", "data": worker,
			"depth": position.x + position.y + 0.48})
	drawables.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["depth"]) - float(b["depth"])) < 0.01:
			return str(a["kind"]) < str(b["kind"])
		return float(a["depth"]) < float(b["depth"]))
	for drawable: Dictionary in drawables:
		match str(drawable["kind"]):
			"object":
				_draw_object(canvas, model, drawable["data"], origin, time_seconds,
					int(drawable["data"]["id"]) == selected_object_id)
			"guest":
				_draw_guest(canvas, drawable["data"], origin, model.sim_tick)
			"staff":
				_draw_staff(canvas, drawable["data"], origin, model.sim_tick)
			"tree":
				_draw_tree(canvas, drawable, origin, time_seconds)
			"fence":
				_draw_fence(canvas, drawable, origin)
	_draw_entrance(canvas, model, origin, time_seconds)
	_draw_cursor(canvas, model, origin, cursor, selected_tool)


func _draw_ground_tiles(canvas: CanvasItem, model, origin: Vector2,
		time_seconds: float) -> void:
	for cell: Vector2i in _visible_ground_cells(model, origin):
		var p := cell_to_screen(cell, origin) + Vector2(0, HALF_H)
		var path_key := Pathfinder.cell_key(cell)
		if model.paths.has(path_key):
			var path_mask := _path_mask(model, cell)
			_draw_bob(canvas, _paths, PATH_CELL, path_mask % 4,
				int(path_mask / 4.0), p)
			if model.is_queue_cell(cell):
				_draw_bob(canvas, _terrain, TERRAIN_CELL, 5, 1, p)
		else:
			var code := absi(cell.x * 19 + cell.y * 37)
			var variation := 1 if code % 17 == 0 else 0
			_draw_bob(canvas, _terrain, TERRAIN_CELL, variation, 0, p)
	for item: Dictionary in model.litter:
		var p := cell_to_screen(item["cell"], origin) + Vector2(0, 2)
		_draw_bob(canvas, _scenery, SCENERY_CELL,
			int(item["variant"]) % 2, 3, p)
	# Ein begrenzter Zweiframezyklus vermittelt Pfuetzen-/Wasserbewegung.
	if not bool(model.litter.is_empty()):
		var wet_cell: Vector2i = model.litter[0]["cell"]
		var wet := cell_to_screen(wet_cell, origin) + Vector2(6, 3)
		_draw_bob(canvas, _scenery, SCENERY_CELL,
			2 + (int(time_seconds * 2.0) & 1), 3, wet)


func _path_mask(model, cell: Vector2i) -> int:
	var left: bool = model.paths.has(Pathfinder.cell_key(cell + Vector2i(-1, 0)))
	var right: bool = model.paths.has(Pathfinder.cell_key(cell + Vector2i(1, 0)))
	var up: bool = model.paths.has(Pathfinder.cell_key(cell + Vector2i(0, -1)))
	var down: bool = model.paths.has(Pathfinder.cell_key(cell + Vector2i(0, 1)))
	return int(up) | (int(right) << 1) | (int(down) << 2) | (int(left) << 3)


func _visible_ground_cells(model, origin: Vector2) -> Array[Vector2i]:
	if origin == _visible_origin and not _visible_ground_cache.is_empty():
		return _visible_ground_cache
	_visible_origin = origin
	_visible_ground_cache.clear()
	for diagonal in range(model.GRID_W + model.GRID_H - 1):
		for x in range(model.GRID_W):
			var y := diagonal - x
			if y < 0 or y >= model.GRID_H:
				continue
			var cell := Vector2i(x, y)
			var p := cell_to_screen(cell, origin) + Vector2(0, HALF_H)
			if p.x >= -40.0 and p.x <= 360.0 and p.y >= -24.0 and p.y <= 268.0:
				_visible_ground_cache.append(cell)
	return _visible_ground_cache


func _environment_drawables(model, origin: Vector2) -> Array[Dictionary]:
	if model.geometry_revision == _environment_revision \
			and origin == _environment_origin:
		return _environment_cache.duplicate()
	_environment_revision = model.geometry_revision
	_environment_origin = origin
	var result: Array[Dictionary] = []
	for y in model.GRID_H:
		for x in model.GRID_W:
			var cell := Vector2i(x, y)
			var screen_position := cell_to_screen(cell, origin)
			if screen_position.x < -48.0 or screen_position.x > 368.0 \
					or screen_position.y < -48.0 or screen_position.y > 268.0:
				continue
			var edge: bool = x == 0 or y == 0 or x == model.GRID_W - 1 \
				or y == model.GRID_H - 1
			if not edge or cell.distance_to(model.ENTRANCE) < 2.5:
				continue
			if not model.object_at(cell).is_empty() \
					or model.paths.has(Pathfinder.cell_key(cell)):
				continue
			var code := absi(x * 29 + y * 43)
			if code % 7 == 0:
				result.append({"kind": "tree", "cell": cell, "variant": code % 2,
					"depth": x + y + 0.52})
			elif code % 2 == 0:
				result.append({"kind": "fence", "cell": cell,
					"corner": (x in [0, model.GRID_W - 1]) \
						and (y in [0, model.GRID_H - 1]),
					"depth": x + y + 0.25})
	_environment_cache = result
	return _environment_cache.duplicate()


func _draw_tree(canvas: CanvasItem, data: Dictionary, origin: Vector2,
		time_seconds: float) -> void:
	var p := cell_to_screen(data["cell"], origin) + Vector2(0, 4)
	var pair := 0 if int(data["variant"]) == 0 else 2
	var frame := pair + (int(time_seconds * 1.6 + int(data["cell"].x)) & 1)
	_draw_bob(canvas, _scenery, SCENERY_CELL, frame, 0, p)


func _draw_fence(canvas: CanvasItem, data: Dictionary, origin: Vector2) -> void:
	var p := cell_to_screen(data["cell"], origin) + Vector2(0, 4)
	_draw_bob(canvas, _terrain, TERRAIN_CELL, 3 if bool(data["corner"]) else 2, 2, p)


func _draw_entrance(canvas: CanvasItem, model, origin: Vector2,
		time_seconds: float) -> void:
	var p := cell_to_screen(Vector2(model.ENTRANCE), origin) + Vector2(0, 5)
	_draw_bob(canvas, _terrain, TERRAIN_CELL,
		4 + (int(time_seconds * 2.5) & 1), 3, p)


func _draw_object(canvas: CanvasItem, model, object: Dictionary, origin: Vector2,
		time_seconds: float, selected: bool) -> void:
	var type := str(object["type"])
	var frame := _object_frame(object, time_seconds)
	var anchor := _object_anchor(object, origin)
	match type:
		"carousel":
			_draw_bob(canvas, _rides, RIDE_CELL, frame, 0, anchor)
		"wheel":
			_draw_bob(canvas, _rides, RIDE_CELL, 2 + frame, 0, anchor)
		"swing":
			_draw_bob(canvas, _rides, RIDE_CELL, frame, 1, anchor)
		"boats":
			_draw_bob(canvas, _rides, RIDE_CELL, 2 + frame, 1, anchor)
		"coaster":
			_draw_bob(canvas, _rides_extra, RIDE_CELL, frame, 0, anchor)
		"bumper":
			_draw_bob(canvas, _rides_extra, RIDE_CELL, 2 + frame, 0, anchor)
		"drop_tower":
			_draw_bob(canvas, _rides_extra, RIDE_CELL, frame, 1, anchor)
		"octopus":
			_draw_bob(canvas, _rides_extra, RIDE_CELL, 2 + frame, 1, anchor)
		"pirate_ship":
			_draw_bob(canvas, _rides_extra, RIDE_CELL, frame, 2, anchor)
		"haunted":
			_draw_bob(canvas, _rides_extra, RIDE_CELL, 2 + frame, 2, anchor)
		"snack":
			_draw_bob(canvas, _rides, RIDE_CELL, frame, 2, anchor)
		"drinks":
			_draw_bob(canvas, _rides, RIDE_CELL, 2 + frame, 2, anchor)
		"toilet":
			_draw_bob(canvas, _services, SERVICE_CELL, frame, 0, anchor)
		"firstaid":
			_draw_bob(canvas, _services, SERVICE_CELL, 2 + frame, 0, anchor)
		"icecream":
			_draw_bob(canvas, _services, SERVICE_CELL, frame, 1, anchor)
		"souvenir":
			_draw_bob(canvas, _services, SERVICE_CELL, 2 + frame, 1, anchor)
		"arcade":
			_draw_bob(canvas, _services, SERVICE_CELL, frame, 2, anchor)
		"bench":
			_draw_bob(canvas, _scenery, SCENERY_CELL, frame, 1, anchor)
		"flowers":
			_draw_bob(canvas, _scenery, SCENERY_CELL, frame, 2, anchor)
		"tree":
			_draw_bob(canvas, _scenery, SCENERY_CELL, frame, 0, anchor)
		"wall":
			_draw_bob(canvas, _terrain, TERRAIN_CELL, frame, 2, anchor)
		"lamp":
			_draw_bob(canvas, _scenery, SCENERY_CELL, 2 + frame, 1, anchor)
		"fountain":
			_draw_bob(canvas, _scenery, SCENERY_CELL, 2 + frame, 2, anchor)
	_draw_riders(canvas, model, object, origin, time_seconds)
	if bool(object.get("broken", false)):
		_draw_bob(canvas, _scenery, SCENERY_CELL,
			4 + (int(time_seconds * 4.0) & 1), 3, anchor)
	elif not bool(object.get("open", true)):
		_draw_bob(canvas, _scenery, SCENERY_CELL, 4, 3, anchor)
	if selected:
		_draw_selection(canvas, object, origin, time_seconds)


func _object_frame(object: Dictionary, time_seconds: float) -> int:
	var active := int(object.get("cycle_timer", 0)) > 0
	var rate := 7.0 if active else 1.3
	var phase := time_seconds * rate + int(object.get("animation_seed", 0)) * 0.31
	if str(object["type"]) in ["snack", "drinks", "toilet"]:
		phase += int(object.get("served", 0))
	return int(phase) & 1


func _object_anchor(object: Dictionary, origin: Vector2) -> Vector2:
	var cell: Vector2i = object["cell"]
	var footprint: Vector2i = object["size"]
	var center := cell_to_screen(Vector2(cell) + Vector2(footprint) * 0.5, origin)
	return center + Vector2(0, float(footprint.x + footprint.y) * 2.0)


func _draw_riders(canvas: CanvasItem, model, object: Dictionary, origin: Vector2,
		time_seconds: float) -> void:
	var riders: Array = object.get("riders", [])
	if riders.is_empty() or int(object.get("cycle_timer", 0)) <= 0:
		return
	var center := _object_anchor(object, origin)
	var phase := float(object.get("phase", 0.0)) * TAU
	var ride_type := str(object["type"])
	for index in mini(riders.size(), 8):
		var offset := Vector2.ZERO
		match ride_type:
			"carousel":
				var angle := phase + float(index) / 8.0 * TAU
				offset = Vector2(cos(angle) * 10.0, sin(angle) * 3.0 - 20)
			"wheel":
				var angle := phase + float(index) / 8.0 * TAU
				offset = Vector2(cos(angle) * 15.0, sin(angle) * 15.0 - 31)
			"swing":
				var angle := phase * 2.0 + float(index) / 8.0 * TAU
				offset = Vector2(cos(angle) * 12.0, sin(angle) * 4.0 - 18)
			"boats":
				var angle := phase + floorf(float(index) / 2.0) / 4.0 * TAU
				offset = Vector2(cos(angle) * 15.0 + (index % 2) * 3.0,
					sin(angle) * 5.0 - 8)
			_:
				continue
		var guest: Dictionary = model.guest_by_id(int(riders[index]))
		var variant := int(guest.get("variant", index)) % 8
		_draw_character(canvas, variant, int(time_seconds * 8.0) & 1,
			center + offset, false, Vector2(0.55, 0.55))


func _draw_guest(canvas: CanvasItem, guest: Dictionary, origin: Vector2,
		sim_tick: int) -> void:
	var cell := _entity_cell(guest)
	var p := cell_to_screen(cell, origin) + Vector2(0, 3)
	var state := str(guest["state"])
	if state == "queue":
		var id := int(guest["id"])
		p += Vector2(float(id % 3 - 1) * 2.0, -float(id % 5) * 1.2)
	var state_column := _state_column(state)
	if state_column >= 0:
		_draw_bob(canvas, _characters, CHARACTER_CELL, state_column, 3, p)
		return
	var route: Array = guest.get("path", [])
	var flip := false
	if not route.is_empty():
		var delta := Vector2(route[0]) - Vector2(guest["cell"])
		flip = delta.x < 0.0 or delta.y < 0.0
	var frame := (int(float(sim_tick) * float(guest["speed"]) * 0.34)
		+ int(guest["id"])) & 1
	_draw_character(canvas, int(guest["variant"]) % 8, frame, p, flip)


func _state_column(state: String) -> int:
	match state:
		"queue", "wait":
			return 0
		"eat":
			return 1
		"drink":
			return 2
		"sit":
			return 3
		"cheer":
			return 4
		"angry":
			return 5
		"sick":
			return 6
		"use", "pay":
			return 7
	return -1


func _draw_staff(canvas: CanvasItem, worker: Dictionary, origin: Vector2,
		sim_tick: int) -> void:
	var p := cell_to_screen(_entity_cell(worker), origin) + Vector2(0, 3)
	var janitor := str(worker["role"]) == "janitor"
	var acting := str(worker["state"]) in ["sweep", "repair"]
	var column := (0 if janitor else 2) + int(acting)
	if not acting:
		p.y -= (int(sim_tick * 0.25 + int(worker["animation_seed"])) & 1)
	_draw_bob(canvas, _characters, CHARACTER_CELL, column, 2, p)


func _draw_character(canvas: CanvasItem, variant: int, frame: int,
		anchor: Vector2, flip: bool, scale := Vector2.ONE) -> void:
	_draw_bob(canvas, _characters, CHARACTER_CELL, variant, frame, anchor,
		flip, scale)


func _entity_cell(entity: Dictionary) -> Vector2:
	var cell := Vector2(entity["cell"])
	var route: Array = entity.get("path", [])
	if route.is_empty():
		return cell
	var next := Vector2(route[0])
	return cell.lerp(next, clampf(float(entity.get("progress", 0.0)), 0.0, 1.0))


func _draw_selection(canvas: CanvasItem, object: Dictionary, origin: Vector2,
		time_seconds: float) -> void:
	var p := _object_anchor(object, origin) - Vector2(0, 14)
	var pulse := 0.55 + sin(time_seconds * 6.0) * 0.35
	canvas.draw_arc(p, 22.0, 0.0, TAU, 24, Color(CYAN, pulse), 1.0)


func _draw_cursor(canvas: CanvasItem, model, origin: Vector2, cursor: Vector2i,
		selected_tool: String) -> void:
	if cursor.x < 0 or cursor.y < 0 or cursor.x >= model.GRID_W \
			or cursor.y >= model.GRID_H:
		return
	var definition: Dictionary = Catalog.item(selected_tool)
	var footprint: Vector2i = definition.get("size", Vector2i.ONE)
	if selected_tool in ["inspect", "path", "demolish"] \
			or str(definition.get("kind", "")) == "staff":
		footprint = Vector2i.ONE
	var valid := true
	for y in range(cursor.y, cursor.y + footprint.y):
		for x in range(cursor.x, cursor.x + footprint.x):
			if x < 0 or y < 0 or x >= model.GRID_W or y >= model.GRID_H:
				valid = false
				continue
			var p := cell_to_screen(Vector2i(x, y), origin)
			_diamond_overlay(canvas, p, Color(CYAN, 0.34) if valid \
				else Color(RED, 0.44), CYAN if valid else RED)


func draw_minimap(canvas: CanvasItem, model, rect: Rect2, cursor: Vector2i) -> void:
	canvas.draw_rect(rect, INK)
	canvas.draw_rect(rect, CYAN, false, 1.0)
	var inner := rect.grow(-2.0)
	var scale := Vector2(inner.size.x / model.GRID_W, inner.size.y / model.GRID_H)
	for key: Variant in model.paths:
		var cell := _cell_from_key(str(key))
		canvas.draw_rect(Rect2(inner.position + Vector2(cell) * scale,
			Vector2(maxf(1.0, scale.x), maxf(1.0, scale.y))), WHITE)
	for object: Dictionary in model.objects:
		var cell: Vector2i = object["cell"]
		var footprint: Vector2i = object["size"]
		var kind := str(Catalog.item(str(object["type"])).get("kind", ""))
		var color := AMBER if kind == "ride" else (
			CYAN if kind in ["shop", "service"] else Color8(119, 153, 51))
		canvas.draw_rect(Rect2(inner.position + Vector2(cell) * scale,
			Vector2(footprint) * scale), color)
	var marker := inner.position + (Vector2(cursor) + Vector2(0.5, 0.5)) * scale
	canvas.draw_rect(Rect2(marker - Vector2.ONE, Vector2(3, 3)), RED, false, 1.0)


func _draw_bob(canvas: CanvasItem, texture: Texture2D, cell_size: Vector2,
		column: int, row: int, anchor: Vector2, flip := false,
		scale := Vector2.ONE) -> void:
	var size := cell_size * scale
	var destination := Rect2(anchor - Vector2(size.x * 0.5, size.y), size)
	if flip:
		destination.position.x += destination.size.x
		destination.size.x = -destination.size.x
	var source := Rect2(Vector2(column, row) * cell_size, cell_size)
	canvas.draw_texture_rect_region(texture, destination, source, WHITE,
		false, true)


func _texture_from_png(path: String) -> Texture2D:
	var imported := load(path) as Texture2D
	if imported == null:
		push_error("WUNDERWERK-OCS-Atlas fehlt: %s" % path)
		return ImageTexture.new()
	return imported


func _cell_from_key(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 \
		else Vector2i.ZERO


func _diamond_overlay(canvas: CanvasItem, center: Vector2, fill: Color,
		line: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -HALF_H), center + Vector2(HALF_W, 0),
		center + Vector2(0, HALF_H), center + Vector2(-HALF_W, 0),
	])
	canvas.draw_colored_polygon(points, fill)
	canvas.draw_polyline(PackedVector2Array([
		points[0], points[1], points[2], points[3], points[0]]), line, 1.0)
