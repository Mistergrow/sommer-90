class_name MonitorTuneModel
extends RefCounted
## Deterministische, UI-unabhaengige CRT-Kalibrierung. Alle Werte sind
## normiert; nur dieses Modell entscheidet ueber Toleranz, PAR und Wertung.

const PARAMS := [&"h_pos", &"v_pos", &"brightness", &"focus", &"convergence"]
const PROFILES := [&"commodore_1084s", &"commodore_1901", &"philips_cm8833", &"aged_crt"]

var level := 1
var run_seed := 1
var target: Dictionary = {}
var values: Dictionary = {}
var moves := 0
var hints := 0
var assisted := false
var profile:StringName=&"commodore_1084s"
var age_hours:=0


func configure(next_level: int, next_seed: int) -> void:
	level = clampi(next_level, 1, 4)
	run_seed = next_seed
	profile=PROFILES[posmod(run_seed+level,PROFILES.size())];age_hours=1500+posmod(run_seed,18500)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	target.clear()
	values.clear()
	for key: StringName in PARAMS:
		# Die sichtbare Testkarte selbst ist die Wahrheit: geometrische Mitte,
		# neutraler Pegel, scharfer Fokus und deckende RGB-Strahlen liegen bei 0.
		# Nur die Defektseite/-staerke wird pro Durchgang deterministisch variiert.
		target[key] = 0.0
		var offset := rng.randf_range(0.30 + level * 0.025, 0.62)
		if rng.randi() % 2 == 0:
			offset = -offset
		values[key] = offset
	if profile==&"commodore_1901":values[&"h_pos"]=float(values.h_pos)*.78
	elif profile==&"philips_cm8833":values[&"convergence"]=float(values.convergence)*1.12
	elif profile==&"aged_crt":values[&"focus"]=clampf(float(values.focus)*1.25,-1,1)
	moves = 0
	hints = 0
	assisted = false


func tolerance() -> float:
	return [0.0, 0.105, 0.082, 0.062, 0.048][level]


func set_value(key: StringName, value: float, count_move := true) -> void:
	if key not in PARAMS:
		return
	values[key] = clampf(value, -1.0, 1.0)
	if count_move:
		moves += 1


func parameter_error(key: StringName) -> float:
	return absf(float(values.get(key, 0.0)) - float(target.get(key, 0.0)))


func total_error() -> float:
	var total := 0.0
	for key: StringName in PARAMS:
		total += parameter_error(key)
	return total / float(PARAMS.size())


func locked_count() -> int:
	var count := 0
	for key: StringName in PARAMS:
		if parameter_error(key) <= tolerance():
			count += 1
	return count


func is_calibrated() -> bool:
	return locked_count() == PARAMS.size()


func worst_parameter() -> StringName:
	var worst: StringName = PARAMS[0]
	for key: StringName in PARAMS:
		if parameter_error(key) > parameter_error(worst):
			worst = key
	return worst


func apply_hint() -> StringName:
	var key := worst_parameter()
	set_value(key, float(target[key]), false)
	hints += 1
	return key


func auto_calibrate() -> void:
	for key: StringName in PARAMS:
		values[key] = target[key]
	assisted = true


func score() -> int:
	if not is_calibrated():
		return 0
	return maxi(250, 1300 + level * 110 - moves * 3 - hints * 120 - (500 if assisted else 0))

func details()->Dictionary:
	return{"level":level,"profile":str(profile),"age_hours":age_hours,"moves":moves,"hints":hints,"assisted":assisted,"mean_error":total_error()}
