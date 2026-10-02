extends RefCounted
## Deterministische Parksimulation; ein Schritt = sechs PAL-Frames/0,1 Sekunden.
signal event(kind: String, data: Dictionary)
signal day_finished(day: int, report: Dictionary)
signal state_changed
const Catalog := preload("res://scripts/games/wunderwerk_catalog.gd")
const Pathfinder := preload("res://scripts/games/wunderwerk_pathfinder.gd")
const SpatialIndex := preload("res://scripts/games/wunderwerk_spatial_index.gd")
const Navigation := preload("res://scripts/games/wunderwerk_navigation.gd")
const SAVE_VERSION := 1
const GRID_W := 48
const GRID_H := 40
const ENTRANCE := Vector2i(24, 39)
const STEP_SECONDS := 0.1
const MAX_GUESTS := 160
const MAX_STAFF := 24
const MAX_OBJECTS := 240
const MAX_LITTER := 140
var scenario_id := "sommerwiese"
var scenario: Dictionary = {}
var paths: Dictionary = {}
var queue_paths: Dictionary = {}
var objects: Array[Dictionary] = []
var guests: Array[Dictionary] = []
var staff: Array[Dictionary] = []
var litter: Array[Dictionary] = []
var money := 0
var day := 1
var minute := 9 * 60
var reputation := 28
var cleanliness := 100
var total_visits := 0
var total_rides := 0
var total_revenue := 0
var daily_revenue := 0
var daily_cost := 0
var paused := false
var finished := false
var won := false
var sim_tick := 0
var message := "BAUE EINEN WEG UND DEINE ERSTE ATTRAKTION"
var geometry_revision := 0
var _accumulator := 0.0
var _next_object_id := 1
var _next_guest_id := 1
var _next_staff_id := 1
var _rng := RandomNumberGenerator.new()
var _spatial = SpatialIndex.new()
var _navigation = Navigation.new()


func reset(new_scenario_id := "sommerwiese") -> void:
	scenario_id = new_scenario_id
	scenario = Catalog.scenario(scenario_id)
	paths = {}
	queue_paths = {}
	objects = []
	guests = []
	staff = []
	litter = []
	money = int(scenario.get("start_money", 2800))
	day = 1
	minute = 9 * 60
	reputation = 28
	cleanliness = 100
	total_visits = 0
	total_rides = 0
	total_revenue = 0
	daily_revenue = 0
	daily_cost = 0
	paused = false
	finished = false
	won = false
	sim_tick = 0
	message = "BAUE EINEN WEG UND DEINE ERSTE ATTRAKTION"
	_accumulator = 0.0
	_next_object_id = 1
	_next_guest_id = 1
	_next_staff_id = 1
	_rng.seed = int(scenario.get("seed", 199_406))
	for y in range(37, 40):
		paths[Pathfinder.cell_key(Vector2i(24, y))] = true
	_spatial.clear()
	_geometry_changed(true)
	state_changed.emit()
func advance(delta: float, speed := 1) -> void:
	if paused or finished or speed <= 0:
		return
	_accumulator = minf(_accumulator + delta * float(speed), 0.8)
	while _accumulator >= STEP_SECONDS:
		_accumulator -= STEP_SECONDS
		_step()
func _step() -> void:
	sim_tick += 1
	minute += 1
	_update_objects()
	_update_guests()
	_update_staff()
	if sim_tick % 16 == 0:
		_try_spawn_guest()
	if sim_tick % 25 == 0:
		_update_park_values()
	if minute >= 20 * 60:
		_end_day()
	if sim_tick % 5 == 0:
		state_changed.emit()
func clock_text() -> String:
	return "%02d:%02d" % [int(minute / 60.0), minute % 60]
func build(item_id: String, cell: Vector2i) -> Dictionary:
	var definition: Dictionary = Catalog.item(item_id)
	if definition.is_empty():
		return _result(false, "UNBEKANNTES BAUOBJEKT")
	var kind := str(definition.get("kind", ""))
	if kind == "tool":
		return _result(false, "WERKZEUG STATT BAUOBJEKT")
	if kind == "staff":
		return hire_staff(str(definition.get("role", "")))
	if not _inside(cell):
		return _result(false, "AUSSERHALB DES PARKS")
	var cost := int(definition.get("cost", 0))
	if money < cost:
		return _result(false, "ZU WENIG GELD")
	if kind == "path":
		var key := Pathfinder.cell_key(cell)
		if paths.has(key):
			if item_id == "queue_path" and not queue_paths.has(key):
				queue_paths[key] = true
				money -= cost
				_geometry_changed(false)
				message = "WEG ZUM WARTEGATTER AUSGEBAUT · -%d DM" % cost
				event.emit("build", {"id": item_id, "cell": cell})
				return _result(true, message)
			return _result(false, "HIER LIEGT BEREITS EIN WEG")
		if not object_at(cell).is_empty():
			return _result(false, "FELD IST BELEGT")
		paths[key] = true
		if item_id == "queue_path":
			queue_paths[key] = true
		money -= cost
		_geometry_changed(true)
		message = "%s GEBAUT · -%d DM" % [
			"WARTEGATTER" if item_id == "queue_path" else "WEG", cost]
		event.emit("build", {"id": item_id, "cell": cell})
		state_changed.emit()
		return _result(true, message)
	if objects.size() >= MAX_OBJECTS:
		return _result(false, "BAULIMIT ERREICHT")
	var footprint: Vector2i = definition.get("size", Vector2i.ONE)
	if not _footprint_free(cell, footprint):
		return _result(false, "ZU WENIG FREIE FLÄCHE")
	var queue_cell := cell + Vector2i(int(footprint.x / 2.0), footprint.y)
	# Der Eingang DARF und soll auf einem bereits gebauten Weg liegen. Nur ein
	# anderes Gebäude darf den Zugang nicht blockieren.
	if not _inside(queue_cell) or not object_at(queue_cell).is_empty():
		return _result(false, "VOR DEM EINGANG MUSS PLATZ BLEIBEN")
	var object := _new_object(item_id, cell, definition, queue_cell)
	objects.append(object)
	_spatial.add_object(object)
	_geometry_changed(false)
	money -= cost
	message = "%s ERÖFFNET · EINGANG AM WEGRAND ANSCHLIESSEN" % str(definition["name"])
	event.emit("build", {"id": item_id, "object_id": object["id"], "cell": cell})
	state_changed.emit()
	return _result(true, message)


func _new_object(item_id: String, cell: Vector2i, definition: Dictionary,
		queue_cell: Vector2i) -> Dictionary:
	var object := {
		"id": _next_object_id,
		"type": item_id,
		"cell": cell,
		"queue_cell": queue_cell,
		"size": definition.get("size", Vector2i.ONE),
		"open": true,
		"broken": false,
		"condition": 100.0,
		"price": int(definition.get("price", 0)),
		"queue": [],
		"riders": [],
		"cycle_timer": 0,
		"queue_wait": 0,
		"phase": 0.0,
		"served": 0,
		"revenue": 0,
		"animation_seed": _rng.randi_range(0, 9999),
	}
	_next_object_id += 1
	return object


func hire_staff(role: String) -> Dictionary:
	var definition: Dictionary = Catalog.item(role)
	if definition.is_empty():
		definition = Catalog.item("janitor" if role == "janitor" else "mechanic")
	if staff.size() >= MAX_STAFF:
		return _result(false, "PERSONALLIMIT ERREICHT")
	var cost := int(definition.get("cost", 0))
	if money < cost:
		return _result(false, "ZU WENIG GELD")
	var worker := {
		"id": _next_staff_id,
		"role": role,
		"cell": ENTRANCE,
		"path": [],
		"progress": 0.0,
		"speed": 0.20 if role == "mechanic" else 0.17,
		"target_kind": "",
		"target_id": -1,
		"state": "walk",
		"animation_seed": _rng.randi_range(0, 9999),
	}
	_next_staff_id += 1
	staff.append(worker)
	money -= cost
	message = "%s EINGESTELLT" % str(definition.get("name", "PERSONAL"))
	event.emit("hire", {"role": role, "staff_id": worker["id"]})
	return _result(true, message)


func demolish(cell: Vector2i) -> Dictionary:
	var object := object_at(cell)
	if not object.is_empty():
		var definition: Dictionary = Catalog.item(str(object["type"]))
		var refund := int(round(int(definition.get("cost", 0)) * 0.35))
		_remove_object(int(object["id"]))
		money += refund
		message = "ABGERISSEN · %d DM RESTWERT" % refund
		event.emit("demolish", {"cell": cell, "refund": refund})
		return _result(true, message)
	var key := Pathfinder.cell_key(cell)
	if paths.has(key) and cell != ENTRANCE:
		paths.erase(key)
		queue_paths.erase(key)
		_geometry_changed(true)
		message = "WEG ENTFERNT"
		event.emit("demolish", {"cell": cell, "refund": 0})
		return _result(true, message)
	return _result(false, "HIER STEHT NICHTS")


func _remove_object(object_id: int) -> void:
	for index in range(objects.size() - 1, -1, -1):
		if int(objects[index]["id"]) != object_id:
			continue
		for guest_id: Variant in objects[index].get("queue", []):
			var guest := guest_by_id(int(guest_id))
			if not guest.is_empty():
				guest["state"] = "walk"
				guest["target_id"] = -1
				_choose_goal(guest)
		for guest_id: Variant in objects[index].get("riders", []):
			var guest := guest_by_id(int(guest_id))
			if not guest.is_empty():
				guest["cell"] = objects[index]["queue_cell"]
				guest["state"] = "walk"
				guest["target_id"] = -1
				_choose_goal(guest)
		_spatial.remove_object(objects[index])
		objects.remove_at(index)
		_geometry_changed(false)
		return


func toggle_object(object_id: int) -> void:
	var object := object_by_id(object_id)
	if object.is_empty():
		return
	object["open"] = not bool(object["open"])
	message = "%s %s" % [
		str(Catalog.item(str(object["type"])).get("name", "BETRIEB")),
		"GEÖFFNET" if bool(object["open"]) else "GESCHLOSSEN"]


func change_price(object_id: int, amount: int) -> void:
	var object := object_by_id(object_id)
	if object.is_empty():
		return
	object["price"] = clampi(int(object["price"]) + amount, 0, 25)
	message = "PREIS: %d DM" % int(object["price"])


func _update_objects() -> void:
	for object: Dictionary in objects:
		var definition: Dictionary = Catalog.item(str(object["type"]))
		if str(definition.get("kind", "")) != "ride":
			object["phase"] = fmod(float(sim_tick + int(object["animation_seed"])) * 0.018, 1.0)
			continue
		if bool(object["broken"]) or not bool(object["open"]):
			object["phase"] = 0.0
			continue
		var timer := int(object["cycle_timer"])
		if timer > 0:
			timer -= 1
			object["cycle_timer"] = timer
			var duration := maxi(1, int(definition.get("duration", 70)))
			object["phase"] = 1.0 - float(timer) / float(duration)
			if timer <= 0:
				_finish_ride(object, definition)
			continue
		object["queue_wait"] = int(object["queue_wait"]) + 1
		var queue: Array = object["queue"]
		var capacity := int(definition.get("capacity", 4))
		if not queue.is_empty() and (queue.size() >= mini(2, capacity)
				or int(object["queue_wait"]) >= 24):
			_start_ride(object, definition)


func _start_ride(object: Dictionary, definition: Dictionary) -> void:
	var queue: Array = object["queue"]
	var riders: Array = []
	var capacity := int(definition.get("capacity", 4))
	while not queue.is_empty() and riders.size() < capacity:
		var guest_id := int(queue.pop_front())
		var guest := guest_by_id(guest_id)
		if guest.is_empty():
			continue
		var price := int(object["price"])
		if int(guest["money"]) < price:
			guest["state"] = "walk"
			guest["thought"] = "ZU TEUER"
			_choose_goal(guest)
			continue
		guest["money"] = int(guest["money"]) - price
		guest["state"] = "ride"
		guest["state_timer"] = int(definition.get("duration", 70))
		riders.append(guest_id)
		_income(object, price)
	object["queue"] = queue
	object["riders"] = riders
	object["queue_wait"] = 0
	object["cycle_timer"] = int(definition.get("duration", 70))
	object["phase"] = 0.0
	object["condition"] = maxf(0.0, float(object["condition"]) - 0.75)
	if float(object["condition"]) < 28.0 and _rng.randf() < 0.08:
		object["broken"] = true
		message = "%s: TECHNIKER BENÖTIGT" % str(definition["name"])
		event.emit("breakdown", {"object_id": object["id"]})


func _finish_ride(object: Dictionary, definition: Dictionary) -> void:
	for guest_id: Variant in object["riders"]:
		var guest := guest_by_id(int(guest_id))
		if guest.is_empty():
			continue
		guest["cell"] = object["queue_cell"]
		guest["state"] = "cheer"
		guest["state_timer"] = 10
		guest["joy"] = maxf(0.0, float(guest["joy"]) - float(definition.get("appeal", 10)))
		guest["nausea"] = minf(100.0, float(guest["nausea"])
			+ float(definition.get("appeal", 10)) * 0.32)
		guest["thought"] = "NOCH EINMAL!"
		guest["target_id"] = -1
		total_rides += 1
	object["riders"] = []
	object["phase"] = 0.0
	object["served"] = int(object["served"]) + 1


func _update_guests() -> void:
	for guest: Dictionary in guests:
		guest["hunger"] = minf(100.0, float(guest["hunger"]) + 0.055)
		guest["thirst"] = minf(100.0, float(guest["thirst"]) + 0.070)
		guest["energy"] = maxf(0.0, float(guest["energy"]) - 0.040)
		guest["joy"] = minf(100.0, float(guest["joy"]) + 0.018)
		guest["toilet"] = minf(100.0, float(guest["toilet"]) + 0.035)
		guest["nausea"] = maxf(0.0, float(guest["nausea"]) - 0.025)
		match str(guest["state"]):
			"ride":
				continue
			"queue":
				guest["patience"] = float(guest["patience"]) - 0.16
				if float(guest["patience"]) <= 0.0:
					_leave_queue(guest)
				continue
			"eat", "drink", "sit", "use", "cheer", "sick":
				guest["state_timer"] = int(guest["state_timer"]) - 1
				if int(guest["state_timer"]) <= 0:
					guest["state"] = "walk"
					_choose_goal(guest)
				continue
			"leaving", "walk":
				_move_guest(guest)
	var kept: Array[Dictionary] = []
	for guest: Dictionary in guests:
		if not bool(guest.get("remove", false)):
			kept.append(guest)
		else:
			_spatial.remove_guest(int(guest.get("id", -1)))
	guests = kept


func _move_guest(guest: Dictionary) -> void:
	var route: Array = guest["path"]
	if route.is_empty():
		if str(guest["state"]) == "leaving" and guest["cell"] == ENTRANCE:
			guest["remove"] = true
			return
		if int(guest.get("target_id", -1)) >= 0:
			_arrive_at_target(guest)
		else:
			_choose_goal(guest)
		return
	guest["progress"] = float(guest["progress"]) + float(guest["speed"])
	if float(guest["progress"]) < 1.0:
		return
	guest["progress"] = float(guest["progress"]) - 1.0
	guest["cell"] = route.pop_front()
	guest["path"] = route
	if route.is_empty():
		if str(guest["state"]) == "leaving" and guest["cell"] == ENTRANCE:
			guest["remove"] = true
		elif int(guest.get("target_id", -1)) >= 0:
			_arrive_at_target(guest)


func _arrive_at_target(guest: Dictionary) -> void:
	var object := object_by_id(int(guest.get("target_id", -1)))
	if object.is_empty() or not bool(object["open"]) or bool(object["broken"]):
		guest["target_id"] = -1
		_choose_goal(guest)
		return
	var definition: Dictionary = Catalog.item(str(object["type"]))
	var kind := str(definition.get("kind", ""))
	var price := int(object["price"])
	if int(guest["money"]) < price:
		guest["thought"] = "ZU TEUER"
		guest["target_id"] = -1
		_choose_goal(guest)
		return
	if kind == "ride":
		var queue: Array = object["queue"]
		queue.append(int(guest["id"]))
		object["queue"] = queue
		guest["state"] = "queue"
		guest["patience"] = 45.0 + float(guest["variant"]) * 3.0
		return
	guest["money"] = int(guest["money"]) - price
	_income(object, price)
	guest["state_timer"] = int(definition.get("duration", 12))
	match str(definition.get("need", "")):
		"hunger":
			guest["hunger"] = maxf(0.0, float(guest["hunger"]) - 62.0)
			guest["state"] = "eat"
			if _rng.randf() < 0.30:
				_add_litter(object["queue_cell"])
		"thirst":
			guest["thirst"] = maxf(0.0, float(guest["thirst"]) - 70.0)
			guest["state"] = "drink"
			if _rng.randf() < 0.22:
				_add_litter(object["queue_cell"])
		"energy":
			guest["energy"] = minf(100.0, float(guest["energy"]) + 58.0)
			guest["state"] = "sit"
		"toilet":
			guest["toilet"] = maxf(0.0, float(guest["toilet"]) - 82.0)
			guest["state"] = "use"
		"nausea":
			guest["nausea"] = maxf(0.0, float(guest["nausea"]) - 86.0)
			guest["state"] = "use"
		_:
			guest["state"] = "cheer"
	guest["target_id"] = -1
	object["served"] = int(object["served"]) + 1


func _leave_queue(guest: Dictionary) -> void:
	var object := object_by_id(int(guest.get("target_id", -1)))
	if not object.is_empty():
		var queue: Array = object["queue"]
		queue.erase(int(guest["id"]))
		object["queue"] = queue
	guest["state"] = "walk"
	guest["joy"] = minf(100.0, float(guest["joy"]) + 18.0)
	guest["thought"] = "ZU LANGE GEWARTET"
	guest["target_id"] = -1
	_choose_goal(guest)


func _choose_goal(guest: Dictionary) -> void:
	if float(guest["joy"]) > 84.0 or int(guest["money"]) <= 0 \
			or minute >= 19 * 60 + 30:
		_send_home(guest)
		return
	var desired := "ride"
	if float(guest["nausea"]) > 72.0:
		desired = "nausea"
	elif float(guest["toilet"]) > 70.0:
		desired = "toilet"
	elif float(guest["hunger"]) > 66.0:
		desired = "hunger"
	elif float(guest["thirst"]) > 62.0:
		desired = "thirst"
	elif float(guest["energy"]) < 28.0:
		desired = "energy"
	var candidates: Array[Dictionary] = []
	for object: Dictionary in objects:
		var type := str(object["type"])
		if not bool(object["open"]) or bool(object["broken"]) \
				or not paths.has(Pathfinder.cell_key(object["queue_cell"])):
			continue
		if desired == "ride":
			if Catalog.is_ride(type) \
					or str(Catalog.item(type).get("need", "")) == "fun":
				candidates.append(object)
		elif str(Catalog.item(type).get("need", "")) == desired:
			candidates.append(object)
	if candidates.is_empty() and desired != "ride":
		for object: Dictionary in objects:
			if Catalog.is_ride(str(object["type"])) and bool(object["open"]) \
					and not bool(object["broken"]) \
					and paths.has(Pathfinder.cell_key(object["queue_cell"])):
				candidates.append(object)
	if not candidates.is_empty():
		var chosen: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var route := _navigation.find_path(paths, guest["cell"], chosen["queue_cell"],
			GRID_W, GRID_H)
		if not route.is_empty() or guest["cell"] == chosen["queue_cell"]:
			guest["target_id"] = int(chosen["id"])
			guest["path"] = route
			guest["progress"] = 0.0
			guest["state"] = "walk"
			return
	_wander(guest)


func _wander(guest: Dictionary) -> void:
	var connected := _navigation.connected_cells(paths, guest["cell"], GRID_W, GRID_H)
	var keys: Array = connected.keys()
	if keys.is_empty():
		_send_home(guest)
		return
	keys.sort()
	var target := _cell_from_key(str(keys[_rng.randi_range(0, keys.size() - 1)]))
	guest["target_id"] = -1
	guest["path"] = _navigation.find_path(paths, guest["cell"], target, GRID_W, GRID_H)
	guest["progress"] = 0.0
	guest["state"] = "walk"


func _send_home(guest: Dictionary) -> void:
	guest["target_id"] = -1
	guest["state"] = "leaving"
	guest["path"] = _navigation.find_path(paths, guest["cell"], ENTRANCE, GRID_W, GRID_H)
	guest["progress"] = 0.0
	if guest["cell"] == ENTRANCE:
		guest["remove"] = true


func _try_spawn_guest() -> void:
	if guests.size() >= mini(MAX_GUESTS, 12 + reputation):
		return
	if not paths.has(Pathfinder.cell_key(ENTRANCE)) or objects.is_empty():
		return
	var connected := _navigation.connected_cells(paths, ENTRANCE, GRID_W, GRID_H)
	var reachable_venue := false
	for object: Dictionary in objects:
		if Catalog.is_venue(str(object["type"])) \
				and connected.has(Pathfinder.cell_key(object["queue_cell"])):
			reachable_venue = true
			break
	if not reachable_venue:
		return
	var id := _next_guest_id
	_next_guest_id += 1
	var guest := {
		"id": id,
		"cell": ENTRANCE,
		"path": [],
		"progress": 0.0,
		"speed": 0.15 + float(id % 5) * 0.012,
		"state": "walk",
		"state_timer": 0,
		"target_id": -1,
		"money": 24 + _rng.randi_range(0, 36),
		"joy": 30.0 + _rng.randf_range(0.0, 15.0),
		"hunger": _rng.randf_range(8.0, 40.0),
		"thirst": _rng.randf_range(12.0, 45.0),
		"energy": _rng.randf_range(55.0, 100.0),
		"toilet": _rng.randf_range(0.0, 30.0),
		"nausea": 0.0,
		"patience": 55.0,
		"variant": id % 6,
		"shirt": id % Catalog.GUEST_SHIRTS.size(),
		"skin": int(id * 3) % Catalog.GUEST_SKINS.size(),
		"hair": int(id * 5) % Catalog.GUEST_HAIR.size(),
		"thought": "NEUGIERIG",
		"remove": false,
	}
	guests.append(guest)
	_spatial.add_guest(guest)
	total_visits += 1
	_choose_goal(guest)
	event.emit("guest_entered", {"guest_id": id})


func _update_staff() -> void:
	for worker: Dictionary in staff:
		if (worker["path"] as Array).is_empty():
			if str(worker["target_kind"]).is_empty():
				_assign_staff_target(worker)
			else:
				_complete_staff_task(worker)
				worker["target_kind"] = ""
				worker["target_id"] = -1
				_assign_staff_target(worker)
			continue
		var route: Array = worker["path"]
		worker["progress"] = float(worker["progress"]) + float(worker["speed"])
		if float(worker["progress"]) < 1.0:
			continue
		worker["progress"] = float(worker["progress"]) - 1.0
		worker["cell"] = route.pop_front()
		worker["path"] = route


func _assign_staff_target(worker: Dictionary) -> void:
	var role := str(worker["role"])
	if role == "janitor" and not litter.is_empty():
		var target: Dictionary = litter[0]
		for candidate: Dictionary in litter:
			if int(candidate["age"]) > int(target["age"]):
				target = candidate
		var route := _navigation.find_path(paths, worker["cell"], target["cell"],
			GRID_W, GRID_H)
		if not route.is_empty() or worker["cell"] == target["cell"]:
			worker["target_kind"] = "litter"
			worker["target_id"] = int(target["id"])
			worker["path"] = route
			worker["state"] = "sweep"
			return
	elif role == "mechanic":
		for object: Dictionary in objects:
			if not bool(object["broken"]):
				continue
			var route := _navigation.find_path(paths, worker["cell"], object["queue_cell"],
				GRID_W, GRID_H)
			if not route.is_empty() or worker["cell"] == object["queue_cell"]:
				worker["target_kind"] = "repair"
				worker["target_id"] = int(object["id"])
				worker["path"] = route
				worker["state"] = "repair"
				return
	worker["state"] = "walk"
	var connected := _navigation.connected_cells(paths, worker["cell"], GRID_W, GRID_H)
	var keys: Array = connected.keys()
	if not keys.is_empty():
		keys.sort()
		var target := _cell_from_key(str(keys[(sim_tick + int(worker["id"])) % keys.size()]))
		worker["path"] = _navigation.find_path(paths, worker["cell"], target, GRID_W, GRID_H)


func _complete_staff_task(worker: Dictionary) -> void:
	match str(worker["target_kind"]):
		"litter":
			for index in range(litter.size() - 1, -1, -1):
				if int(litter[index]["id"]) == int(worker["target_id"]):
					litter.remove_at(index)
					event.emit("clean", {"staff_id": worker["id"]})
					break
		"repair":
			var object := object_by_id(int(worker["target_id"]))
			if not object.is_empty():
				object["broken"] = false
				object["condition"] = 82.0
				message = "%s REPARIERT" % str(Catalog.item(
					str(object["type"])).get("name", "ATTRAKTION"))
				event.emit("repair", {"staff_id": worker["id"],
					"object_id": object["id"]})


func _add_litter(cell: Vector2i) -> void:
	if litter.size() >= MAX_LITTER:
		return
	litter.append({"id": sim_tick * 100 + litter.size(), "cell": cell, "age": 0,
		"variant": _rng.randi_range(0, 3)})


func _update_park_values() -> void:
	for item: Dictionary in litter:
		item["age"] = int(item["age"]) + 1
	cleanliness = clampi(100 - litter.size() * 3, 0, 100)
	var happiness := 55.0
	if not guests.is_empty():
		var sum := 0.0
		for guest: Dictionary in guests:
			sum += 100.0 - float(guest["joy"])
		happiness = sum / float(guests.size())
	var variety := 0
	var types := {}
	for object: Dictionary in objects:
		types[str(object["type"])] = true
		if str(Catalog.item(str(object["type"])).get("kind", "")) == "decor":
			variety += 2
	variety += types.size() * 3
	reputation = clampi(roundi(happiness * 0.46 + cleanliness * 0.28
		+ float(variety) * 0.26), 0, 100)


func _end_day() -> void:
	var upkeep := 0
	for object: Dictionary in objects:
		var definition: Dictionary = Catalog.item(str(object["type"]))
		upkeep += int(definition.get("upkeep", 0))
		if Catalog.is_ride(str(object["type"])):
			object["condition"] = maxf(0.0, float(object["condition"]) - 0.35)
	var wages := 0
	for worker: Dictionary in staff:
		var staff_definition: Dictionary = Catalog.item(str(worker["role"]))
		wages += int(staff_definition.get("wage", 0))
	daily_cost = upkeep + wages
	money -= daily_cost
	var report := {
		"day": day,
		"revenue": daily_revenue,
		"cost": daily_cost,
		"profit": daily_revenue - daily_cost,
		"guests": guests.size(),
		"reputation": reputation,
		"cleanliness": cleanliness,
		"money": money,
	}
	day += 1
	minute = 9 * 60
	daily_revenue = 0
	for guest: Dictionary in guests:
		_send_home(guest)
	_check_goal()
	day_finished.emit(day, report)
	message = "TAG %d · BILANZ %+d DM" % [day - 1, int(report["profit"])]


func _check_goal() -> void:
	var goal_day := int(scenario.get("goal_day", 14))
	if day <= goal_day:
		return
	finished = true
	won = reputation >= int(scenario.get("goal_reputation", 68)) \
		and money >= int(scenario.get("goal_cash", 3500)) \
		and total_visits >= int(scenario.get("goal_visits", 120))
	message = "PARKZIEL ERREICHT!" if won else "DER VERTRAG WURDE NICHT VERLÄNGERT"
	event.emit("finished", {"won": won, "score": score()})


func score() -> int:
	return maxi(0, money + reputation * 100 + total_visits * 15
		+ total_rides * 8 + cleanliness * 20)


func _income(object: Dictionary, amount: int) -> void:
	money += amount
	daily_revenue += amount
	total_revenue += amount
	object["revenue"] = int(object["revenue"]) + amount


func object_at(cell: Vector2i) -> Dictionary:
	return _spatial.object_at(cell)


func object_by_id(object_id: int) -> Dictionary:
	return _spatial.object_by_id(object_id)


func guest_by_id(guest_id: int) -> Dictionary:
	return _spatial.guest_by_id(guest_id)


func is_queue_cell(cell: Vector2i) -> bool:
	return queue_paths.has(Pathfinder.cell_key(cell)) \
		or _spatial.is_venue_queue_cell(cell)


func runtime_index_stats() -> Dictionary:
	var result := _spatial.stats()
	result["geometry_revision"] = geometry_revision
	result["navigation"] = _navigation.stats()
	return result


func _footprint_free(cell: Vector2i, footprint: Vector2i) -> bool:
	for y in range(cell.y, cell.y + footprint.y):
		for x in range(cell.x, cell.x + footprint.x):
			var check := Vector2i(x, y)
			if not _inside(check) or _occupied(check):
				return false
	return true


func _occupied(cell: Vector2i) -> bool:
	return paths.has(Pathfinder.cell_key(cell)) or not object_at(cell).is_empty()


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_W and cell.y < GRID_H


func _result(ok: bool, text: String) -> Dictionary:
	if not ok:
		message = text
	return {"ok": ok, "message": text}


func _geometry_changed(paths_changed: bool) -> void:
	geometry_revision += 1
	if paths_changed:
		_navigation.invalidate()


func _cell_from_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func to_dict() -> Dictionary:
	var object_data: Array = []
	for object: Dictionary in objects:
		object_data.append(_encode_entity(object))
	var guest_data: Array = []
	for guest: Dictionary in guests:
		guest_data.append(_encode_entity(guest))
	var staff_data: Array = []
	for worker: Dictionary in staff:
		staff_data.append(_encode_entity(worker))
	var litter_data: Array = []
	for item: Dictionary in litter:
		litter_data.append(_encode_entity(item))
	var path_keys: Array = paths.keys()
	path_keys.sort()
	var queue_path_keys: Array = queue_paths.keys()
	queue_path_keys.sort()
	return {
		"version": SAVE_VERSION,
		"scenario_id": scenario_id,
		"paths": path_keys,
		"queue_paths": queue_path_keys,
		"objects": object_data,
		"guests": guest_data,
		"staff": staff_data,
		"litter": litter_data,
		"money": money,
		"day": day,
		"minute": minute,
		"reputation": reputation,
		"cleanliness": cleanliness,
		"total_visits": total_visits,
		"total_rides": total_rides,
		"total_revenue": total_revenue,
		"daily_revenue": daily_revenue,
		"daily_cost": daily_cost,
		"finished": finished,
		"won": won,
		"sim_tick": sim_tick,
		"message": message,
		"next_object_id": _next_object_id,
		"next_guest_id": _next_guest_id,
		"next_staff_id": _next_staff_id,
		"rng_state": _rng.state,
	}


func from_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != SAVE_VERSION:
		return false
	reset(str(data.get("scenario_id", "sommerwiese")))
	paths = {}
	queue_paths = {}
	for raw_key: Variant in data.get("paths", []):
		var key := str(raw_key)
		var cell := _cell_from_key(key)
		if _inside(cell):
			paths[key] = true
	for raw_key: Variant in data.get("queue_paths", []):
		var key := str(raw_key)
		if paths.has(key):
			queue_paths[key] = true
	if not paths.has(Pathfinder.cell_key(ENTRANCE)):
		paths[Pathfinder.cell_key(ENTRANCE)] = true
	objects = _decode_entities(data.get("objects", []), MAX_OBJECTS)
	guests = _decode_entities(data.get("guests", []), MAX_GUESTS)
	staff = _decode_entities(data.get("staff", []), MAX_STAFF)
	litter = _decode_entities(data.get("litter", []), MAX_LITTER)
	_spatial.rebuild(objects, guests)
	_geometry_changed(true)
	money = clampi(int(data.get("money", money)), -50_000, 5_000_000)
	day = clampi(int(data.get("day", 1)), 1, 999)
	minute = clampi(int(data.get("minute", 540)), 0, 1439)
	reputation = clampi(int(data.get("reputation", 28)), 0, 100)
	cleanliness = clampi(int(data.get("cleanliness", 100)), 0, 100)
	total_visits = maxi(0, int(data.get("total_visits", 0)))
	total_rides = maxi(0, int(data.get("total_rides", 0)))
	total_revenue = maxi(0, int(data.get("total_revenue", 0)))
	daily_revenue = maxi(0, int(data.get("daily_revenue", 0)))
	daily_cost = maxi(0, int(data.get("daily_cost", 0)))
	finished = bool(data.get("finished", false))
	won = bool(data.get("won", false))
	sim_tick = maxi(0, int(data.get("sim_tick", 0)))
	message = str(data.get("message", message)).left(80)
	_next_object_id = maxi(1, int(data.get("next_object_id", 1)))
	_next_guest_id = maxi(1, int(data.get("next_guest_id", 1)))
	_next_staff_id = maxi(1, int(data.get("next_staff_id", 1)))
	_rng.state = maxi(1, int(data.get("rng_state", _rng.state)))
	state_changed.emit()
	return true


func _encode_entity(entity: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in entity:
		var value: Variant = entity[key]
		if value is Vector2i:
			out[str(key)] = [value.x, value.y]
		elif value is Array and str(key) == "path":
			var encoded_path: Array = []
			for cell: Vector2i in value:
				encoded_path.append([cell.x, cell.y])
			out[str(key)] = encoded_path
		else:
			out[str(key)] = value
	return out


func _decode_entities(raw: Variant, limit: int) -> Array[Dictionary]:
	var decoded: Array[Dictionary] = []
	if not raw is Array:
		return decoded
	for candidate: Variant in raw:
		if decoded.size() >= limit or not candidate is Dictionary:
			break
		var entity: Dictionary = (candidate as Dictionary).duplicate(true)
		for key in ["cell", "queue_cell", "size"]:
			if entity.has(key):
				entity[key] = _decode_vec(entity[key])
		if entity.has("path"):
			var route: Array[Vector2i] = []
			for raw_cell: Variant in entity["path"]:
				route.append(_decode_vec(raw_cell))
			entity["path"] = route
		decoded.append(entity)
	return decoded


func _decode_vec(raw: Variant) -> Vector2i:
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO
