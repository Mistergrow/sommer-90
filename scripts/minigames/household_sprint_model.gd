class_name HouseholdSprintModel
extends RefCounted
## Regelkern fuer sieben eigenstaendige Hausauftraege. Die Profile teilen nur
## Auswertung und Save-Vertrag; jede Aufgabe besitzt eine andere, konkrete
## Handlung. Geld, Energie und Raumwirkung bleiben beim ChoreManager.

const PROFILES := {
	"muell": {"mode": "sort", "targets": 9, "title": "CONTAINER-KOMMANDO", "benchmark": 55.0},
	"aufraeumen": {"mode": "organize", "targets": 8, "title": "ZIMMER-RESET", "benchmark": 60.0},
	"spuelen": {"mode": "dishes", "targets": 5, "phases": 3, "title": "SPUELWERK 1200", "benchmark": 70.0},
	"staubsaugen": {"mode": "vacuum", "targets": 14, "hits": 2, "title": "TEPPICH-PATROL", "benchmark": 65.0},
	"einkauf": {"mode": "shopping", "targets": 6, "title": "MAMAS EINKAUFSLISTE", "benchmark": 55.0},
	"auto_waschen": {"mode": "detail", "targets": 6, "phases": 3, "title": "GARAGEN-GLANZ", "benchmark": 85.0},
	"rasen": {"mode": "mower", "targets": 18, "hits": 1, "title": "RASENMEISTER", "benchmark": 75.0},
}

const SORT_POSITIONS := [
	Vector2(0.10, 0.72), Vector2(0.19, 0.82), Vector2(0.29, 0.70),
	Vector2(0.39, 0.82), Vector2(0.51, 0.73), Vector2(0.62, 0.83),
	Vector2(0.72, 0.72), Vector2(0.82, 0.82), Vector2(0.91, 0.70),
]
const FLOOR_POSITIONS := [
	Vector2(0.17, 0.75), Vector2(0.28, 0.65), Vector2(0.39, 0.80),
	Vector2(0.50, 0.69), Vector2(0.61, 0.81), Vector2(0.72, 0.66),
	Vector2(0.82, 0.78), Vector2(0.44, 0.56),
]
# Perspektivische Teppichzonen der Wohnzimmer-Kulisse. Ein eigener Satz ist
# notwendig, weil der generische Pfad mehrere Krümel an Wand und Möbel setzte.
const VACUUM_POSITIONS := [
	Vector2(0.29, 0.58), Vector2(0.40, 0.57), Vector2(0.52, 0.56),
	Vector2(0.64, 0.57), Vector2(0.76, 0.59),
	Vector2(0.22, 0.69), Vector2(0.34, 0.68), Vector2(0.47, 0.67),
	Vector2(0.60, 0.68), Vector2(0.73, 0.69), Vector2(0.84, 0.70),
	Vector2(0.28, 0.81), Vector2(0.48, 0.80), Vector2(0.68, 0.81),
]
# Vier perspektivische Maehbahnen innerhalb der tatsaechlichen Rasenflaeche.
# Der alte gemeinsame Saug-/Maehpfad setzte mehrere Ziele auf Blumen, Teich und
# Gehweg. Diese Punkte folgen bewusst der trapezfoermigen Wiese der AGA-Kulisse.
const MOWER_POSITIONS := [
	Vector2(0.38, 0.31), Vector2(0.48, 0.31), Vector2(0.58, 0.31),
	Vector2(0.68, 0.31), Vector2(0.78, 0.31),
	Vector2(0.30, 0.43), Vector2(0.41, 0.43), Vector2(0.52, 0.43),
	Vector2(0.63, 0.43), Vector2(0.74, 0.43),
	Vector2(0.23, 0.55), Vector2(0.37, 0.55), Vector2(0.51, 0.55),
	Vector2(0.65, 0.55),
	Vector2(0.16, 0.67), Vector2(0.33, 0.67), Vector2(0.50, 0.67),
	Vector2(0.67, 0.67),
]
const CAR_POSITIONS := [
	Vector2(0.28, 0.40), Vector2(0.47, 0.34), Vector2(0.62, 0.37),
	Vector2(0.76, 0.47), Vector2(0.39, 0.60), Vector2(0.66, 0.61),
]
const PRODUCT_NAMES := [
	"MILCH", "BROT", "SAFT", "ERBSEN", "NUDELN", "SEIFE",
	"MEHL", "AEPFEL", "KAKAO", "BUTTER", "REIS", "TEE",
]

var chore_id := ""
var profile: Dictionary = {}
var targets: Array[Dictionary] = []
var actions := 0
var mistakes := 0
var combo := 0
var best_combo := 0
var cleared := 0
var precision_total := 0.0
var successful_steps := 0
var _rng := RandomNumberGenerator.new()


func configure(next_chore_id: String, run_seed: int) -> void:
	chore_id = next_chore_id
	profile = (PROFILES.get(chore_id, PROFILES["spuelen"]) as Dictionary).duplicate(true)
	_rng.seed = run_seed
	actions = 0
	mistakes = 0
	combo = 0
	best_combo = 0
	cleared = 0
	precision_total = 0.0
	successful_steps = 0
	targets.clear()
	match mode():
		"sort": _configure_sort()
		"organize": _configure_organize()
		"dishes": _configure_dishes()
		"vacuum", "mower": _configure_path()
		"shopping": _configure_shopping()
		"detail": _configure_detail()


func _configure_sort() -> void:
	for index in int(profile.get("targets", 9)):
		targets.append(_target(index, SORT_POSITIONS[index], index % 4, 1, index % 3))


func _configure_organize() -> void:
	for index in int(profile.get("targets", 8)):
		var variant := index % 4
		targets.append(_target(index, FLOOR_POSITIONS[index], variant, 1, variant))


func _configure_dishes() -> void:
	var positions := [Vector2(0.24, 0.58), Vector2(0.29, 0.64), Vector2(0.34, 0.54),
		Vector2(0.39, 0.67), Vector2(0.44, 0.58)]
	for index in int(profile.get("targets", 5)):
		var target := _target(index, positions[index], index % 4, int(profile.get("phases", 3)), 0)
		target["phase"] = 0
		targets.append(target)


func _configure_path() -> void:
	var count := int(profile.get("targets", 14))
	var durability := int(profile.get("hits", 1))
	for index in count:
		var source_positions := MOWER_POSITIONS if mode() == "mower" else VACUUM_POSITIONS
		var source_index: int = index % source_positions.size()
		var position := Vector2(source_positions[source_index])
		var jitter := 0.004 if mode() == "mower" else 0.012
		position += Vector2(_rng.randf_range(-jitter, jitter),
			_rng.randf_range(-jitter * 0.75, jitter * 0.75))
		targets.append(_target(index, position, index % 4, durability, 0))


func _configure_shopping() -> void:
	var available: Array[int] = []
	for index in PRODUCT_NAMES.size():
		available.append(index)
	for unused in int(profile.get("targets", 6)):
		var pick := _rng.randi_range(0, available.size() - 1)
		var product := int(available.pop_at(pick))
		targets.append(_target(targets.size(), _product_position(product), product, 1, 0))


func _configure_detail() -> void:
	for index in int(profile.get("targets", 6)):
		var target := _target(index, CAR_POSITIONS[index], index % 3, int(profile.get("phases", 3)), 0)
		target["phase"] = 0
		targets.append(target)


func _target(index: int, position: Vector2, variant: int, hits: int, destination: int) -> Dictionary:
	return {"id": index, "position": position, "variant": variant,
		"hits": hits, "max_hits": hits, "destination": destination}


func _product_position(product: int) -> Vector2:
	var row := floori(float(product) / 4.0)
	return Vector2(0.13 + float(product % 4) * 0.16, 0.26 + float(row) * 0.17)


func mode() -> String:
	return str(profile.get("mode", "dishes"))


func total_targets() -> int:
	return targets.size()


func total_steps() -> int:
	var result := 0
	for target in targets:
		result += int(target.get("max_hits", 1))
	return result


func completed_steps() -> int:
	var result := 0
	for target in targets:
		result += int(target.get("max_hits", 1)) - int(target.get("hits", 0))
	return result


func finished() -> bool:
	return cleared >= targets.size() and not targets.is_empty()


func apply_action(action: Dictionary) -> Dictionary:
	if finished():
		return {"accepted": false}
	actions += 1
	var result: Dictionary
	match mode():
		"sort", "organize": result = _apply_drop(action)
		"dishes": result = _apply_sequence(action, "station")
		"vacuum", "mower": result = _apply_path(action)
		"shopping": result = _apply_shopping(action)
		"detail": result = _apply_sequence(action, "tool")
		_: result = {"accepted": false}
	if bool(result.get("accepted", false)) and bool(result.get("hit", false)):
		combo += 1
		best_combo = maxi(best_combo, combo)
		precision_total += clampf(float(action.get("performance", 1.0)), 0.0, 1.0)
		successful_steps += 1
	elif bool(result.get("accepted", false)):
		mistakes += 1
		combo = 0
	result["finished"] = finished()
	result["cleared"] = cleared
	result["steps"] = completed_steps()
	return result


func _apply_drop(action: Dictionary) -> Dictionary:
	var index := int(action.get("target", -1))
	if not _alive(index):
		return {"accepted": false}
	var expected := int(targets[index].get("destination", -1))
	var selected := int(action.get("destination", -2))
	if expected != selected:
		return {"accepted": true, "hit": false, "target": index, "expected": expected}
	_clear_target(index)
	return {"accepted": true, "hit": true, "removed": true, "target": index}


func _apply_sequence(action: Dictionary, action_field: String) -> Dictionary:
	var index := int(action.get("target", -1))
	if not _alive(index):
		return {"accepted": false}
	var target := targets[index]
	var phase := int(target.get("phase", 0))
	var selected := int(action.get(action_field, -1))
	if selected != phase:
		return {"accepted": true, "hit": false, "target": index, "expected": phase}
	target["phase"] = phase + 1
	target["hits"] = maxi(0, int(target.get("hits", 1)) - 1)
	targets[index] = target
	var removed := int(target.get("hits", 0)) <= 0
	if removed:
		cleared += 1
	return {"accepted": true, "hit": true, "removed": removed, "target": index, "phase": phase}


func _apply_path(action: Dictionary) -> Dictionary:
	if str(action.get("kind", "path")) == "obstacle":
		return {"accepted": true, "hit": false, "obstacle": true}
	var position := Vector2(action.get("position", Vector2(-1, -1)))
	var nearest := _nearest_alive(position, 0.075 if mode() == "vacuum" else 0.065)
	if nearest < 0:
		return {"accepted": false}
	var target := targets[nearest]
	target["hits"] = maxi(0, int(target.get("hits", 1)) - 1)
	targets[nearest] = target
	var removed := int(target.get("hits", 0)) <= 0
	if removed:
		cleared += 1
	return {"accepted": true, "hit": true, "removed": removed, "target": nearest}


func _apply_shopping(action: Dictionary) -> Dictionary:
	var product := int(action.get("product", -1))
	for index in targets.size():
		if _alive(index) and int(targets[index].get("variant", -2)) == product:
			_clear_target(index)
			return {"accepted": true, "hit": true, "removed": true, "target": index}
	return {"accepted": true, "hit": false, "product": product}


func _alive(index: int) -> bool:
	return index >= 0 and index < targets.size() and int(targets[index].get("hits", 0)) > 0


func _clear_target(index: int) -> void:
	var target := targets[index]
	target["hits"] = 0
	targets[index] = target
	cleared += 1


func _nearest_alive(position: Vector2, radius: float) -> int:
	var nearest := -1
	var distance_best := radius
	for index in targets.size():
		if not _alive(index):
			continue
		var distance := position.distance_to(Vector2(targets[index].get("position", Vector2.ZERO)))
		if distance < distance_best:
			nearest = index
			distance_best = distance
	return nearest


## Adapter fuer bestehende Tests und gespeicherte direkte Zeigeraktionen.
func apply_at(normalized_position: Vector2) -> Dictionary:
	match mode():
		"vacuum", "mower": return apply_action({"kind": "path", "position": normalized_position})
		"shopping":
			var product := _product_at(normalized_position)
			return apply_action({"kind": "pick", "product": product})
	var index := _nearest_alive(normalized_position, 0.09)
	if index < 0:
		return {"accepted": false}
	match mode():
		"sort", "organize": return apply_action({"kind": "drop", "target": index,
			"destination": int(targets[index].get("destination", 0))})
		"dishes": return apply_action({"kind": "dish", "target": index,
			"station": int(targets[index].get("phase", 0))})
		"detail": return apply_action({"kind": "panel", "target": index,
			"tool": int(targets[index].get("phase", 0))})
	return {"accepted": false}


func _product_at(position: Vector2) -> int:
	var best := -1
	var best_distance := 0.12
	for product in PRODUCT_NAMES.size():
		var distance := position.distance_to(_product_position(product))
		if distance < best_distance:
			best = product
			best_distance = distance
	return best


func score() -> int:
	if not finished():
		return 0
	var accuracy := float(successful_steps) / maxf(1.0, float(successful_steps + mistakes))
	var precision := precision_total / maxf(1.0, float(successful_steps))
	return clampi(roundi(560.0 + accuracy * 250.0 + precision * 110.0 + mini(80, best_combo * 4)), 0, 1000)


func details() -> Dictionary:
	return {"chore": chore_id, "mode": mode(), "targets": total_targets(),
		"cleared": cleared, "steps": completed_steps(), "total_steps": total_steps(),
		"actions": actions, "mistakes": mistakes, "best_combo": best_combo,
		"precision": precision_total / maxf(1.0, float(successful_steps)), "score": score()}
