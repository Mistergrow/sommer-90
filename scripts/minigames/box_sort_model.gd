class_name BoxSortModel
extends RefCounted

const DeterministicArray := preload("res://scripts/util/deterministic_array.gd")
## Reines deterministisches Modell des Diskettenbox-Puzzles. UI, Seitenwechsel
## und Animation kennen keine Sortierlogik; PAR, Hinweise und Undo leben hier.

const SortOrder := preload("res://scripts/autoload/disk_sort_order.gd")

var mode := 0
var run_seed := 1
var order: Array = []
var target: Array = []
var moves := 0
var par := 0
var hints := 0
var undos := 0
var _history: Array[Array] = []
var box_profile:=&"12_slot"


func configure(source: Array, sort_mode: int, round_seed: int, shuffle := true) -> void:
	mode = clampi(sort_mode, 0, 3)
	run_seed = absi(round_seed)
	box_profile=[&"12_slot",&"24_slot",&"archive",&"mixed_condition"][posmod(run_seed+mode,4)]
	target = SortOrder.sorted(source, mode)
	order = source.duplicate()
	if shuffle and order.size() > 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed
		var attempts := 0
		while attempts < 24:
			DeterministicArray.shuffle(order, rng)
			if not SortOrder.same(order, target):
				break
			attempts += 1
		if SortOrder.same(order, target):
			order.reverse()
	moves = 0
	hints = 0
	undos = 0
	_history = []
	par = minimum_swaps(order, target)


func swap_slots(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= order.size() or b >= order.size() or a == b:
		return false
	_history.append(order.duplicate())
	var temp = order[a]
	order[a] = order[b]
	order[b] = temp
	moves += 1
	return true


func undo() -> bool:
	if _history.is_empty():
		return false
	order = _history.pop_back()
	moves = maxi(0, moves - 1)
	undos += 1
	return true


func best_swap() -> Vector2i:
	for i in order.size():
		if order[i] != target[i]:
			return Vector2i(i, order.find(target[i]))
	return Vector2i(-1, -1)


func use_hint() -> Vector2i:
	hints += 1
	return best_swap()


func is_solved() -> bool:
	return SortOrder.same(order, target)


func minimum_swaps(candidate: Array = [], wanted: Array = []) -> int:
	var values: Array = order if candidate.is_empty() else candidate
	var goal: Array = target if wanted.is_empty() else wanted
	if values.size() != goal.size():
		return -1
	var work := values.duplicate()
	var swaps := 0
	for i in goal.size():
		if work[i] == goal[i]:
			continue
		var j := work.find(goal[i], i + 1)
		if j < 0:
			return -1
		var temp = work[i]
		work[i] = work[j]
		work[j] = temp
		swaps += 1
	return swaps


func score() -> int:
	var over_par := maxi(0, moves - par)
	return maxi(100, 1000 - over_par * 85 - moves * 10 - hints * 65 - undos * 15)


func details() -> Dictionary:
	return {
		"moves": moves, "par": par, "mode": mode, "hints": hints,
		"undos": undos, "score": score(), "count": order.size(), "box_profile":str(box_profile),
	}
