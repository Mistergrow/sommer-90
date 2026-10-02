class_name JoystickRepairModel
extends RefCounted
## Deterministischer Kern der 4-Kanal-Joystick-Werkstatt. Das Modell kennt
## weder Pixelkoordinaten noch Weltzustand: UI und Persistenz bleiben dadurch
## sauber getrennt und alle Fehlerbilder sind headless reproduzierbar.

const CHANNEL_COUNT := 4
const CHANNEL_KEYS := ["N", "O", "S", "W"]
const CHANNEL_SYMBOLS := ["△", "○", "□", "◇"]
const MODELS := [&"competition_pro",&"zipstik",&"quickshot",&"generic_db9"]

var difficulty := "lehrgang"
var assisted := false
var _seed := 0
var joystick_model:StringName=&"competition_pro"
var fault_family:StringName=&"broken_lead"
var source_order: Array[int] = []
var wire_targets: Array[int] = []
var joint_states: Array[Dictionary] = []

var mistakes := 0
var cold_joints := 0
var overheats := 0
var bridges := 0
var reflows := 0
var hints_used := 0
var undos_used := 0
var resets_used := 0
var diagnostics := 0
var first_pass := true

var _history: Array[Dictionary] = []


func _init() -> void:
	configure()


func configure(p_difficulty := "lehrgang", p_assisted := false, p_seed := 0) -> void:
	difficulty = p_difficulty if p_difficulty in ["lehrgang", "werkbank", "profi"] else "lehrgang"
	assisted = p_assisted
	_seed = p_seed if p_seed != 0 else 9041990
	joystick_model=MODELS[posmod(_seed,MODELS.size())]
	fault_family=[&"broken_lead",&"cold_joint",&"oxidized_contact",&"cable_strain"][posmod(_seed+1,4)]
	source_order = [0, 1, 2, 3]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	for i in range(source_order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := source_order[i]
		source_order[i] = source_order[j]
		source_order[j] = swap
	_reset_board_state()
	mistakes = 0
	cold_joints = 0
	overheats = 0
	bridges = 0
	reflows = 0
	hints_used = 0
	undos_used = 0
	resets_used = 0
	diagnostics = 0
	first_pass = true
	_history.clear()


func set_assisted(value: bool) -> void:
	assisted = value


func safe_heat_min() -> float:
	var value := 0.38
	match difficulty:
		"werkbank": value = 0.42
		"profi": value = 0.47
	if assisted:
		value -= 0.08
	return value


func safe_heat_max() -> float:
	var value := 0.78
	match difficulty:
		"werkbank": value = 0.72
		"profi": value = 0.68
	if assisted:
		value += 0.08
	return value


func safe_tin_min() -> float:
	return 0.30 if assisted else 0.36


func safe_tin_max() -> float:
	return 0.76 if assisted else 0.68


func connect_wire(source: int, target: int) -> bool:
	if not _valid_channel(source) or not _valid_channel(target):
		return false
	var occupied_by := -1
	for other in CHANNEL_COUNT:
		if other != source and wire_targets[other] == target:
			occupied_by = other
			break
	if wire_targets[source] == target:
		return true
	_push_history()
	var previous_target := wire_targets[source]
	if previous_target >= 0:
		reflows += 1
	# Eine belegte Öse tauscht die beiden Drahtenden atomar. So kann eine
	# falsche Kreuzung niemals zu einem unauflösbaren Zwei-Kanal-Deadlock führen.
	if occupied_by >= 0:
		wire_targets[occupied_by] = previous_target
		joint_states[occupied_by] = _empty_joint()
		mistakes += 1
	wire_targets[source] = target
	joint_states[source] = _empty_joint()
	if source != target:
		mistakes += 1
	return true


func disconnect_wire(source: int) -> bool:
	if not _valid_channel(source) or wire_targets[source] < 0:
		return false
	_push_history()
	wire_targets[source] = -1
	joint_states[source] = _empty_joint()
	reflows += 1
	return true


func heat_joint(source: int, heat: float, tin: float, disturbed := false) -> String:
	if not _valid_channel(source) or wire_targets[source] < 0:
		return "open"
	_push_history()
	var previous := str(joint_states[source].get("state", "open"))
	if previous != "open":
		reflows += 1
	var state := "good"
	if tin > safe_tin_max():
		state = "bridge"
		bridges += 1
	elif heat > safe_heat_max():
		state = "overheated"
		overheats += 1
	elif heat < safe_heat_min() or tin < safe_tin_min() or disturbed:
		state = "cold"
		cold_joints += 1
	var quality := _joint_quality(heat, tin, disturbed, state)
	joint_states[source] = {
		"state": state,
		"heat": clampf(heat, 0.0, 1.25),
		"tin": clampf(tin, 0.0, 1.25),
		"disturbed": disturbed,
		"quality": quality,
	}
	return state


func desolder(source: int) -> bool:
	if not _valid_channel(source) or str(joint_states[source].get("state", "open")) == "open":
		return false
	_push_history()
	joint_states[source] = _empty_joint()
	reflows += 1
	return true


func undo() -> bool:
	if _history.is_empty():
		return false
	var snap: Dictionary = _history.pop_back()
	wire_targets.assign(snap.get("wire_targets", [-1, -1, -1, -1]))
	joint_states.assign(snap.get("joint_states", []))
	undos_used += 1
	return true


func reset_round() -> void:
	_push_history()
	_reset_board_state()
	resets_used += 1


func next_hint() -> Dictionary:
	hints_used += 1
	assisted = true
	for source in CHANNEL_COUNT:
		if wire_targets[source] != source:
			return {"source": source, "target": source, "kind": "wire"}
		if str(joint_states[source].get("state", "open")) != "good":
			return {
				"source": source,
				"target": source,
				"kind": "joint",
				"heat_min": safe_heat_min(),
				"heat_max": safe_heat_max(),
			}
	return {}


func diagnose() -> Dictionary:
	diagnostics += 1
	var channels: Array[Dictionary] = []
	var success := true
	for source in CHANNEL_COUNT:
		var status := "ok"
		var target := wire_targets[source]
		if target < 0:
			status = "open"
		elif target != source:
			status = "swapped"
		else:
			status = str(joint_states[source].get("state", "open"))
		if status != "good" and status != "ok":
			success = false
		channels.append({
			"source": source,
			"target": target,
			"key": CHANNEL_KEYS[source],
			"symbol": CHANNEL_SYMBOLS[source],
			"status": "ok" if status == "good" else status,
		})
	if not success:
		first_pass = false
	return {"success": success, "channels": channels, "attempt": diagnostics}


func all_wired() -> bool:
	for target in wire_targets:
		if target < 0:
			return false
	return true


func all_joints_closed() -> bool:
	for source in CHANNEL_COUNT:
		if str(joint_states[source].get("state", "open")) == "open":
			return false
	return true


func all_ready() -> bool:
	for source in CHANNEL_COUNT:
		if wire_targets[source] != source:
			return false
		if str(joint_states[source].get("state", "open")) != "good":
			return false
	return true


func connected_count() -> int:
	var count := 0
	for target in wire_targets:
		if target >= 0:
			count += 1
	return count


func good_joint_count() -> int:
	var count := 0
	for joint in joint_states:
		if str(joint.get("state", "open")) == "good":
			count += 1
	return count


func average_quality() -> float:
	var sum := 0.0
	for joint in joint_states:
		sum += float(joint.get("quality", 0.0))
	return sum / float(CHANNEL_COUNT)


func score() -> int:
	var value := 1000
	value -= mistakes * 35
	value -= cold_joints * 55
	value -= overheats * 80
	value -= bridges * 70
	value -= reflows * 30
	value -= hints_used * 55
	value -= undos_used * 15
	value -= resets_used * 100
	value -= maxi(0, diagnostics - 1) * 25
	if assisted:
		value -= 120
	return clampi(value, 100, 1000)


func details() -> Dictionary:
	var qualities: Array[float] = []
	var states: Array[String] = []
	for joint in joint_states:
		qualities.append(float(joint.get("quality", 0.0)))
		states.append(str(joint.get("state", "open")))
	return {
		"seed": _seed,
		"difficulty": difficulty,
		"joystick_model":str(joystick_model),"fault_family":str(fault_family),
		"mistakes": mistakes,
		"cold_joints": cold_joints,
		"overheated": overheats,
		"bridges": bridges,
		"reflows": reflows,
		"hints": hints_used,
		"undos": undos_used,
		"resets": resets_used,
		"diagnostics": diagnostics,
		"first_pass": first_pass,
		"assisted": assisted,
		"joint_quality": qualities,
		"joint_states": states,
		"quality": roundi(average_quality() * 100.0),
	}


func state_snapshot() -> Dictionary:
	return {
		"wire_targets": wire_targets.duplicate(),
		"joint_states": joint_states.duplicate(true),
		"source_order": source_order.duplicate(),
		"score": score(),
		"details": details(),
	}


func _reset_board_state() -> void:
	wire_targets = [-1, -1, -1, -1]
	joint_states.clear()
	for _i in CHANNEL_COUNT:
		joint_states.append(_empty_joint())


func _empty_joint() -> Dictionary:
	return {"state": "open", "heat": 0.0, "tin": 0.0, "disturbed": false, "quality": 0.0}


func _push_history() -> void:
	_history.append({
		"wire_targets": wire_targets.duplicate(),
		"joint_states": joint_states.duplicate(true),
	})
	if _history.size() > 32:
		_history.pop_front()


func _joint_quality(heat: float, tin: float, disturbed: bool, state: String) -> float:
	if state != "good":
		return 0.20 if state == "cold" else 0.08
	var heat_mid := (safe_heat_min() + safe_heat_max()) * 0.5
	var tin_mid := (safe_tin_min() + safe_tin_max()) * 0.5
	var heat_span := maxf(0.01, (safe_heat_max() - safe_heat_min()) * 0.5)
	var tin_span := maxf(0.01, (safe_tin_max() - safe_tin_min()) * 0.5)
	var heat_fit := 1.0 - clampf(absf(heat - heat_mid) / heat_span, 0.0, 1.0)
	var tin_fit := 1.0 - clampf(absf(tin - tin_mid) / tin_span, 0.0, 1.0)
	return clampf(0.72 + heat_fit * 0.14 + tin_fit * 0.14 - (0.25 if disturbed else 0.0), 0.0, 1.0)


func _valid_channel(index: int) -> bool:
	return index >= 0 and index < CHANNEL_COUNT
