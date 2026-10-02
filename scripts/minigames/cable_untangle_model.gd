class_name CableUntangleModel
extends RefCounted

const DeterministicArray := preload("res://scripts/util/deterministic_array.gd")

## Reines, deterministisches Modell des Gruber-Kabelauftrags. Die Reihenfolge
## der Stecker am unteren Patchfeld enthaelt genau eine freie Buchse. Pro Zug
## darf ausschliesslich ein Stecker in diese Buchse umgesetzt werden. Jede
## Inversion der Steckerordnung ist eine echte Kreuzung. Es gibt bewusst keine
## zweite, versteckte Lagen-Siegbedingung: Was der Spieler am Brett entwirrt,
## ist auch genau das, was der Durchgangspruefer bewertet.

const CABLE_DEFS := [
	{"id": "rgb", "name": "RGB", "symbol": "R", "color": "#4f78ff"},
	{"id": "serial", "name": "SER", "symbol": "S", "color": "#ef4f62"},
	{"id": "mouse", "name": "MSE", "symbol": "M", "color": "#49cf6b"},
	{"id": "power", "name": "PWR", "symbol": "P", "color": "#f0ce45"},
	{"id": "joystick", "name": "JOY", "symbol": "J", "color": "#b85ee8"},
	{"id": "printer", "name": "PRN", "symbol": "D", "color": "#42d1d1"},
	{"id": "audio", "name": "AUD", "symbol": "A", "color": "#f08b42"},
]
const EMPTY := -1
var cable_count := 5
var run_seed := 1
var order: Array[int] = []       # bottom slot -> cable id/top index oder EMPTY
var target_order: Array[int] = [] # feste farb-/symbolcodierte Zielbuchsen
var start_order: Array[int] = []
# Kompatibilitaetsansicht fuer die Seil-Zeichenreihenfolge. Sie bleibt stabil
# und ist keine zweite Puzzle-Ebene mehr.
var layer_order: Array[int] = []
var target_layer_order: Array[int] = []
var start_layer_order: Array[int] = []
var history: Array[Dictionary] = []
var moves := 0
var layer_moves := 0 # Alt-Save/Telemetrie: bleibt ab jetzt immer 0.
var strain := 0
var hints := 0


func configure(count: int, round_seed: int) -> void:
	cable_count = clampi(count, 4, CABLE_DEFS.size())
	run_seed = absi(round_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	target_order = []
	for i in cable_count:
		target_order.append(i)
	# Der schwarze Puffer liegt fest in der Mitte; nur wenn alle Farben wieder an
	# ihren Zielbuchsen sitzen, ist auch dieses Loch am Ende erneut frei.
	target_order.insert(target_empty_slot(), EMPTY)
	# Nicht irgendeine Permutation behaupten, sondern den Startzustand durch
	# echte legale Pufferzuege aus der Loesung erzeugen. Dadurch existiert fuer
	# jeden Seed konstruktiv eine Rueckroute. Mehrere Versuche dienen nur der
	# visuellen Dichte; die deterministische Umkehrung ist ein sicherer Fallback.
	order = target_order.duplicate()
	var best_candidate: Array[int] = order.duplicate()
	var best_quality := -1
	for attempt in 32:
		var candidate := _scramble_from_solution(rng, cable_count * 3 + attempt % 4)
		var crossings := crossing_count(candidate)
		var distance := minimum_moves(candidate)
		var quality := crossings * 10 + distance
		if quality > best_quality:
			best_candidate = candidate
			best_quality = quality
		if crossings >= maxi(3, cable_count - 2) and distance >= maxi(3, cable_count - 2):
			best_candidate = candidate
			break
	order = best_candidate
	if order == target_order:
		order = target_order.duplicate()
		order.reverse()
	start_order = order.duplicate()
	# Stabile Render-Reihenfolge. Sie veraendert weder Loesbarkeit noch Sieg.
	target_layer_order.clear()
	for cable_id in cable_count:
		target_layer_order.append(cable_id)
	layer_order = target_layer_order.duplicate()
	start_layer_order = layer_order.duplicate()
	history = []
	moves = 0
	layer_moves = 0
	strain = 0
	hints = 0


func _scramble_from_solution(rng: RandomNumberGenerator, step_count: int) -> Array[int]:
	var candidate: Array[int] = target_order.duplicate()
	var last_source := -1
	for _step in maxi(1, step_count):
		var empty := candidate.find(EMPTY)
		var choices: Array[int] = []
		for source in candidate.size():
			if source != empty and source != last_source:
				choices.append(source)
		# Bei zwei Positionen waere der Ausschluss unmoeglich; mit mindestens vier
		# Kabeln ist dies nur eine defensive Absicherung.
		if choices.is_empty():
			for source in candidate.size():
				if source != empty:
					choices.append(source)
		DeterministicArray.shuffle(choices, rng)
		var source := choices[0]
		candidate[empty] = candidate[source]
		candidate[source] = EMPTY
		last_source = empty
	return candidate


func cable_def(id: int) -> Dictionary:
	if id<0 or id>=cable_count:return{}
	return CABLE_DEFS[id].duplicate(true)


func slot_of_cable(cable_id: int) -> int:
	return order.find(cable_id)


func empty_slot() -> int:
	return order.find(EMPTY)


func target_empty_slot() -> int:
	return floori(cable_count / 2.0)


func misplaced_count(candidate: Array = []) -> int:
	var values: Array = order if candidate.is_empty() else candidate
	var count := 0
	for slot in mini(values.size(), target_order.size()):
		if int(values[slot]) != int(target_order[slot]):
			count += 1
	return count + absi(values.size() - target_order.size())


func crossing_count(candidate: Array = []) -> int:
	var values: Array = order if candidate.is_empty() else candidate
	var count := 0
	for a in values.size():
		if int(values[a]) == EMPTY:
			continue
		for b in range(a + 1, values.size()):
			if int(values[b]) != EMPTY and int(values[a]) > int(values[b]):
				count += 1
	return count


func is_solved() -> bool:
	if order.size() != cable_count + 1 or empty_slot() < 0:
		return false
	return plugs_solved()


func plugs_solved() -> bool:
	return order == target_order


func layers_solved() -> bool:
	# Bis Version 1 war dies eine zweite Bubble-Sort-Aufgabe. Sie war visuell
	# nicht nachvollziehbar und konnte ein korrekt entwirrtes Brett blockieren.
	return true


func layer_misplaced_count() -> int:
	return 0


func layer_inversion_count(_candidate: Array = []) -> int:
	return 0


func move_to_empty(from_slot: int) -> bool:
	var target := empty_slot()
	if from_slot < 0 or from_slot >= order.size() or order[from_slot] == EMPTY or target < 0:
		return false
	_history_snapshot()
	order[target] = order[from_slot]
	order[from_slot] = EMPTY
	moves += 1
	strain += absi(from_slot - target)
	return true


func move_layer(_cable_id: int, _direction: int) -> bool:
	return false


func _history_snapshot() -> void:
	history.append({"order": order.duplicate(), "strain": strain, "moves": moves})


func undo() -> bool:
	if history.is_empty():
		return false
	var snapshot: Dictionary = history.pop_back()
	order.assign(snapshot.get("order", []))
	strain = int(snapshot.get("strain", 0))
	moves = int(snapshot.get("moves", maxi(0, moves - 1)))
	return true


func reset_round() -> void:
	order = start_order.duplicate()
	history = []
	moves = 0
	strain = 0
	hints = 0


func best_move() -> Vector2i:
	var best := Vector2i(-1, -1)
	if plugs_solved() or not is_valid_state(order):
		return best
	var best_remaining := 999
	var best_crossings := 999
	var best_distance := 999
	var empty := empty_slot()
	for source in order.size():
		if order[source] == EMPTY:
			continue
		var candidate := order.duplicate()
		candidate[empty] = candidate[source]
		candidate[source] = EMPTY
		var crossings := crossing_count(candidate)
		var remaining := minimum_moves(candidate)
		var distance := absi(source - empty)
		if remaining < best_remaining or (remaining == best_remaining and crossings < best_crossings) \
				or (remaining == best_remaining and crossings == best_crossings and distance < best_distance):
			best_remaining = remaining
			best_crossings = crossings
			best_distance = distance
			best = Vector2i(source, empty)
	# Jeder Hinweis liegt auf einer kuerzesten Route. Einzelne Pufferzuege duerfen
	# dabei optisch kurz gleich viele Kreuzungen zeigen, fuehren aber nie in eine
	# Sackgasse oder Schleife.
	return best


func use_hint() -> Vector2i:
	hints += 1
	return best_move()


func best_layer_move() -> Vector2i:
	return Vector2i(-1, 0)


func use_layer_hint() -> Vector2i:
	hints += 1
	return best_layer_move()


func minimum_layer_moves(_candidate: Array = []) -> int:
	return 0


func minimum_moves(candidate: Array = []) -> int:
	var values: Array = start_order if candidate.is_empty() else candidate
	if not is_valid_state(values):
		return -1
	# Exakte Mindestzahl beliebiger Transpositionen mit EMPTY zum festen Ziel.
	# Ein Zyklus mit EMPTY kostet L-1, jeder andere nichttriviale Zyklus L+1.
	var target_pos := {}
	for pos in target_order.size():
		target_pos[int(target_order[pos])] = pos
	var permutation: Array[int] = []
	for pos in values.size():
		permutation.append(int(target_pos[int(values[pos])]))
	var visited: Array[bool] = []
	visited.resize(values.size())
	visited.fill(false)
	var cost := 0
	var current_empty := values.find(EMPTY)
	for start in permutation.size():
		if visited[start] or permutation[start] == start:
			visited[start] = true
			continue
		var length := 0
		var contains_empty := false
		var cursor := start
		while not visited[cursor]:
			visited[cursor] = true
			contains_empty = contains_empty or cursor == current_empty
			length += 1
			cursor = permutation[cursor]
		cost += length - 1 if contains_empty else length + 1
	return cost


func is_valid_state(candidate: Array = []) -> bool:
	var values: Array = order if candidate.is_empty() else candidate
	if values.size() != target_order.size():
		return false
	var normalized: Array[int] = []
	for value in values:
		normalized.append(int(value))
	normalized.sort()
	var expected: Array[int] = []
	for value in target_order:
		expected.append(int(value))
	expected.sort()
	return normalized == expected and normalized.count(EMPTY) == 1


func solution_route(candidate: Array = []) -> Array[int]:
	# Liefert die exakte Folge der Quellbuchsen einer kuerzesten Route. Diese
	# Funktion ist zugleich ein leicht testbares Loesbarkeitszertifikat fuer
	# Generator, Hinweise und gespeicherte Zwischenstaende.
	var source_values: Array = order if candidate.is_empty() else candidate
	var state: Array[int] = []
	for value in source_values:
		state.append(int(value))
	var route: Array[int] = []
	if not is_valid_state(state):
		return route
	var remaining := minimum_moves(state)
	while remaining > 0:
		var empty := state.find(EMPTY)
		var chosen := -1
		for source in state.size():
			if source == empty:
				continue
			var next: Array[int] = state.duplicate()
			next[empty] = next[source]
			next[source] = EMPTY
			if minimum_moves(next) == remaining - 1:
				chosen = source
				state = next
				break
		if chosen < 0:
			# Darf bei einer gueltigen Permutation mathematisch nie eintreten.
			route.clear()
			return route
		route.append(chosen)
		remaining -= 1
	if state != target_order:
		route.clear()
	return route


func score() -> int:
	var extra_moves := maxi(0, moves - minimum_moves())
	var ideal_strain := maxi(1, minimum_moves())
	return clampi(1000 - extra_moves * 70 \
		- maxi(0, strain - ideal_strain) * 9 - hints * 85, 100, 1000)


func details() -> Dictionary:
	return {
		"cables": cable_count, "moves": moves, "minimum_moves": minimum_moves(),
		"layer_moves": layer_moves, "minimum_layer_moves": minimum_layer_moves(),
		"layer_knots": layer_inversion_count(), "layer_misplaced": layer_misplaced_count(),
		"strain": strain, "hints": hints, "crossings": crossing_count(),
		"misplaced": misplaced_count(), "target_empty": target_empty_slot(),
	}
