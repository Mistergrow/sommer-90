class_name RoomTidyModel
extends RefCounted
## Deterministisches Modell des Zimmer-Aufraeumspiels. RoomManager bleibt die
## einzige Weltzustandsautoritaet; dieses Modell kennt nur den Snapshot einer
## Runde und meldet am Ende die darin wirklich einsortierten positiven UIDs.

const TARGETS := {
	"bin": {"name": "RESTMUELL", "symbol": "M", "color": "#d66a58"},
	"recycling": {"name": "WERTSTOFF", "symbol": "R", "color": "#e4c54f"},
	"shelf": {"name": "REGAL", "symbol": "S", "color": "#58b9d6"},
	"laundry": {"name": "WAESCHE", "symbol": "W", "color": "#aa78d6"},
}

const ITEM_DEFS := {
	"cola_dose": {"name": "COLADOSE", "target": "recycling", "visual": "cola"},
	"eispackung": {"name": "EISPAPIER", "target": "bin", "visual": "ice"},
	"chips_tuete": {"name": "CHIPSTUETE", "target": "bin", "visual": "chips"},
	"dirty_sock": {"name": "SOCKE", "target": "laundry", "visual": "sock"},
	"tshirt": {"name": "T-SHIRT", "target": "laundry", "visual": "tshirt"},
	"cassette": {"name": "KASSETTE", "target": "shelf", "visual": "cassette"},
	"floppy": {"name": "DISKETTE", "target": "shelf", "visual": "floppy"},
	"paper": {"name": "PAPIER", "target": "bin", "visual": "paper"},
}

const PRACTICE_KINDS := ["dirty_sock", "cassette", "floppy", "paper", "tshirt", "chips_tuete"]

var level := 1
var run_seed := 1
var items: Array[Dictionary] = []
var moves := 0
var mistakes := 0
var hints := 0
var resets := 0
var undos := 0
var combo := 0
var max_combo := 0
var _history: Array[int] = []
var room_scenario:=&"school_week"


func configure(world_items: Array, minimum_count: int, round_seed: int, difficulty_level: int) -> void:
	level = clampi(difficulty_level, 1, 4)
	run_seed = absi(round_seed)
	room_scenario=[&"school_week",&"club_night",&"repair_day",&"collector_room"][posmod(run_seed+level,4)]
	items = []
	for raw in world_items:
		if not raw is Dictionary:
			continue
		var world: Dictionary = raw
		var kind := str(world.get("kind", "paper"))
		var def := definition(kind, str(world.get("target", "bin")))
		items.append({
			"uid": int(world.get("uid", 0)), "kind": kind,
			"name": str(def["name"]), "visual": str(def["visual"]),
			"target": _safe_target(str(world.get("target", def["target"]))),
			"placed": false, "world": true,
		})
	var practice_index := 0
	while items.size() < minimum_count:
		var kind: String = str(PRACTICE_KINDS[practice_index % PRACTICE_KINDS.size()])
		practice_index += 1
		var def := definition(kind)
		items.append({
			"uid": -practice_index, "kind": kind, "name": str(def["name"]),
			"visual": str(def["visual"]), "target": str(def["target"]),
			"placed": false, "world": false,
		})
	_shuffle()
	moves = 0
	mistakes = 0
	hints = 0
	resets = 0
	undos = 0
	combo = 0
	max_combo = 0
	_history = []


func definition(kind: String, fallback_target := "bin") -> Dictionary:
	if ITEM_DEFS.has(kind):
		return ITEM_DEFS[kind]
	return {"name": kind.replace("_", " ").to_upper(), "target": _safe_target(fallback_target), "visual": "paper"}


func target_def(id: String) -> Dictionary:
	return TARGETS.get(_safe_target(id), TARGETS["bin"])


func attempt_drop(item_index: int, target: String) -> Dictionary:
	if item_index < 0 or item_index >= items.size() or bool(items[item_index].get("placed", false)):
		return {"ok": false, "reason": "invalid"}
	moves += 1
	var wanted := str(items[item_index].get("target", "bin"))
	if _safe_target(target) != wanted:
		mistakes += 1
		combo = 0
		return {"ok": false, "reason": "wrong", "wanted": wanted}
	items[item_index]["placed"] = true
	_history.append(item_index)
	combo += 1
	max_combo = maxi(max_combo, combo)
	return {"ok": true, "complete": is_complete(), "combo": combo}


func undo() -> int:
	if _history.is_empty():
		return -1
	var index: int = int(_history.pop_back())
	items[index]["placed"] = false
	undos += 1
	combo = 0
	return index


func reset_placements() -> void:
	for item in items:
		item["placed"] = false
	_history = []
	combo = 0
	resets += 1


func use_hint() -> int:
	hints += 1
	for i in items.size():
		if not bool(items[i].get("placed", false)):
			return i
	return -1


func is_complete() -> bool:
	return not items.is_empty() and remaining() == 0


func remaining() -> int:
	var count := 0
	for item in items:
		if not bool(item.get("placed", false)):
			count += 1
	return count


func committed_uids() -> Array[int]:
	var result: Array[int] = []
	for item in items:
		var uid := int(item.get("uid", 0))
		if uid > 0 and bool(item.get("placed", false)):
			result.append(uid)
	return result


func score() -> int:
	return clampi(1000 - mistakes * 75 - hints * 90 - resets * 45 - undos * 15 + mini(max_combo, 8) * 8, 100, 1000)


func stars() -> int:
	var value := score()
	return 3 if value >= 850 else (2 if value >= 620 else 1)


func details() -> Dictionary:
	return {
		"level": level, "items": items.size(), "world_items": committed_uids().size(),
		"moves": moves, "mistakes": mistakes, "hints": hints, "resets": resets,
		"undos": undos, "max_combo": max_combo, "score": score(), "stars": stars(), "scenario":str(room_scenario),
	}


func _safe_target(value: String) -> String:
	return value if TARGETS.has(value) else "bin"


func _shuffle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := items[i]
		items[i] = items[j]
		items[j] = temp
