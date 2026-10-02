class_name PrinterAlignModel
extends RefCounted
## Modellgebundene Traktor-, Kopf- und Bidirektional-Kalibrierung.

const LABELS := {&"tractor_l": "TRAKTOR L", &"tractor_r": "TRAKTOR R", &"head_gap": "KOPFSPALT",
	&"bidir": "BIDIR OFFSET", &"density": "NADELDRUCK", &"cyan": "CYAN", &"magenta": "MAGENTA", &"yellow": "YELLOW"}
var level := 1
var run_seed := 1
var printer_model := "dot_matrix_9pin"
var params: Array[StringName] = []
var values: Dictionary = {}
var moves := 0
var hints := 0
var assisted := false
var media:=&"continuous"
var paper_advance:=0.0
var jam_risk:=0.0

func configure(next_level: int, next_seed: int, model: String) -> void:
	level = clampi(next_level, 1, 5); run_seed = next_seed; printer_model = model
	media=[&"continuous",&"labels",&"carbon_copy",&"heavy_stock"][posmod(run_seed+level,4)]
	paper_advance=(posmod(run_seed,17)-8)*.04;jam_risk=0.08+level*.025+(0.12 if media==&"heavy_stock"else 0.0)
	params = [&"tractor_l", &"tractor_r", &"head_gap", &"bidir"]
	if model != "dot_matrix_9pin": params.append(&"density")
	if model in ["dot_matrix_24_color", "color_inkjet"]:
		params.append_array([&"cyan", &"magenta", &"yellow"])
	var rng := RandomNumberGenerator.new(); rng.seed = run_seed; values.clear()
	for key in params:
		var v := rng.randf_range(0.26, 0.70); values[key] = -v if rng.randi() % 2 == 0 else v
	moves = 0; hints = 0; assisted = false

func set_value(key: StringName, value: float, count := true) -> void:
	if key not in params: return
	values[key] = clampf(value, -1.0, 1.0)
	if count: moves += 1

func tolerance() -> float:
	return [0.0, 0.11, 0.09, 0.072, 0.058, 0.046][level]

func error(key: StringName) -> float:
	return absf(float(values.get(key, 0.0)))

func total_error() -> float:
	var sum := 0.0
	for key in params: sum += error(key)
	return sum / maxf(1.0, params.size())

func worst() -> StringName:
	var key := params[0]
	for candidate in params:
		if error(candidate) > error(key): key = candidate
	return key

func hint() -> StringName:
	var key := worst(); set_value(key, 0.0, false); hints += 1; return key

func auto_align() -> void:
	assisted = true
	for key in params: values[key] = 0.0

func calibrated() -> bool:
	return params.all(func(key: StringName) -> bool: return error(key) <= tolerance())

func score() -> int:
	if not calibrated(): return 0
	return maxi(250, 1200 + level * 125 + params.size() * 40 - moves * 3 - hints * 100 - (450 if assisted else 0))

func details() -> Dictionary:
	return {"level": level, "model": printer_model, "parameters": params.size(), "moves": moves,
		"mean_error": total_error(), "hints": hints, "assisted": assisted,"media":str(media),
		"paper_advance":paper_advance,"jam_risk":jam_risk}
