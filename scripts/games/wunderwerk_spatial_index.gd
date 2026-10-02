extends RefCounted
## Laufzeitindex der Parksimulation. Persistiert werden weiterhin nur die
## autoritativen Arrays; dieser Index wird bei Reset und Save-Laden neu gebaut.

const Catalog := preload("res://scripts/games/wunderwerk_catalog.gd")
const Pathfinder := preload("res://scripts/games/wunderwerk_pathfinder.gd")

var _objects_by_id: Dictionary = {}
var _guests_by_id: Dictionary = {}
var _occupied_cells: Dictionary = {}
var _venue_queue_cells: Dictionary = {}


func clear() -> void:
	_objects_by_id.clear()
	_guests_by_id.clear()
	_occupied_cells.clear()
	_venue_queue_cells.clear()


func rebuild(objects: Array[Dictionary], guests: Array[Dictionary]) -> void:
	clear()
	for object: Dictionary in objects:
		add_object(object)
	for guest: Dictionary in guests:
		add_guest(guest)


func add_object(object: Dictionary) -> void:
	var object_id := int(object.get("id", -1))
	if object_id < 0:
		return
	_objects_by_id[object_id] = object
	var origin: Vector2i = object.get("cell", Vector2i.ZERO)
	var footprint: Vector2i = object.get("size", Vector2i.ONE)
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			_occupied_cells[Pathfinder.cell_key(Vector2i(x, y))] = object_id
	if Catalog.is_venue(str(object.get("type", ""))):
		var queue_cell: Vector2i = object.get("queue_cell", Vector2i(-99, -99))
		_venue_queue_cells[Pathfinder.cell_key(queue_cell)] = object_id


func remove_object(object: Dictionary) -> void:
	var object_id := int(object.get("id", -1))
	_objects_by_id.erase(object_id)
	var origin: Vector2i = object.get("cell", Vector2i.ZERO)
	var footprint: Vector2i = object.get("size", Vector2i.ONE)
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			var key := Pathfinder.cell_key(Vector2i(x, y))
			if int(_occupied_cells.get(key, -1)) == object_id:
				_occupied_cells.erase(key)
	var queue_cell: Vector2i = object.get("queue_cell", Vector2i(-99, -99))
	var queue_key := Pathfinder.cell_key(queue_cell)
	if int(_venue_queue_cells.get(queue_key, -1)) == object_id:
		_venue_queue_cells.erase(queue_key)


func add_guest(guest: Dictionary) -> void:
	var guest_id := int(guest.get("id", -1))
	if guest_id >= 0:
		_guests_by_id[guest_id] = guest


func remove_guest(guest_id: int) -> void:
	_guests_by_id.erase(guest_id)


func object_at(cell: Vector2i) -> Dictionary:
	return object_by_id(int(_occupied_cells.get(Pathfinder.cell_key(cell), -1)))


func object_by_id(object_id: int) -> Dictionary:
	var value: Variant = _objects_by_id.get(object_id)
	return value if value is Dictionary else {}


func guest_by_id(guest_id: int) -> Dictionary:
	var value: Variant = _guests_by_id.get(guest_id)
	return value if value is Dictionary else {}


func is_venue_queue_cell(cell: Vector2i) -> bool:
	return _venue_queue_cells.has(Pathfinder.cell_key(cell))


func stats() -> Dictionary:
	return {
		"object_ids": _objects_by_id.size(),
		"guest_ids": _guests_by_id.size(),
		"occupied_cells": _occupied_cells.size(),
		"venue_queue_cells": _venue_queue_cells.size(),
	}
