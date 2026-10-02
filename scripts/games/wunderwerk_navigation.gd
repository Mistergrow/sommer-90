extends RefCounted
## Revisionsgebundener BFS-Cache. Routen werden kopiert ausgegeben, weil Gäste
## und Personal sie beim Laufen mit pop_front() verbrauchen.

const Pathfinder := preload("res://scripts/games/wunderwerk_pathfinder.gd")

var revision := 0
var _route_cache: Dictionary = {}
var _connected_cache: Dictionary = {}


func invalidate() -> void:
	revision += 1
	_route_cache.clear()
	_connected_cache.clear()


func find_path(paths: Dictionary, start: Vector2i, goal: Vector2i,
		width: int, height: int) -> Array[Vector2i]:
	var cache_key := "%s>%s" % [Pathfinder.cell_key(start), Pathfinder.cell_key(goal)]
	if _route_cache.has(cache_key):
		return (_route_cache[cache_key] as Array[Vector2i]).duplicate()
	var route := Pathfinder.find_path(paths, start, goal, width, height)
	_route_cache[cache_key] = route.duplicate()
	return route


func connected_cells(paths: Dictionary, origin: Vector2i,
		width: int, height: int) -> Dictionary:
	var cache_key := Pathfinder.cell_key(origin)
	if _connected_cache.has(cache_key):
		return _connected_cache[cache_key]
	var connected := Pathfinder.connected_cells(paths, origin, width, height)
	_connected_cache[cache_key] = connected
	return connected


func stats() -> Dictionary:
	return {
		"revision": revision,
		"routes": _route_cache.size(),
		"components": _connected_cache.size(),
	}
