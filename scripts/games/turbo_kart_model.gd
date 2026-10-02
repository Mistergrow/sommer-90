class_name TurboKartModel
extends RefCounted
## Deterministischer 60-Hz-Kern von Turbo Kart Deluxe.
##
## Die Strecke ist in Fortschritt (Rundenanteil) + seitlichem Abstand modelliert.
## Damit bleiben Checkpoints und Runden wasserdicht, waehrend die Darstellung eine
## echte geschlossene Top-down-Kurve zeichnet. Rendering, Audio und kosmetischer
## Zufall leben bewusst ausserhalb dieses Modells.

const TICK_RATE := 60
const TICK_DT := 1.0 / float(TICK_RATE)
const LAPS := 3
const AI_COUNT := 5
const TRACK_LENGTH := 570.0
const MAX_TICKS := TICK_RATE * 60 * 12
const Track := preload("res://scripts/games/turbo_stunt_track.gd")

const TRACKS := [
	{"id": "parking", "name": "PARKPLATZ NORD", "road": 17.0, "grip": 1.0},
	{"id": "gravel", "name": "KIESGRUBE 7", "road": 19.0, "grip": 0.82},
	{"id": "freight", "name": "GUETERHOF", "road": 16.0, "grip": 0.94},
]

const SETUPS := {
	"weasel": {"name": "WIESEL", "max_speed": 96.0, "accel": 48.0, "handling": 1.13, "grip": 0.94},
	"falcon": {"name": "FALKE", "max_speed": 109.0, "accel": 40.0, "handling": 0.94, "grip": 0.88},
	"block": {"name": "KLOTZ", "max_speed": 99.0, "accel": 36.0, "handling": 1.23, "grip": 1.08},
}

const AI_NAMES := ["MIKE", "JULE", "NICO", "KAT", "RALF"]
const AI_COLORS := ["red", "blue", "yellow", "green", "violet"]

var track_id := "parking"
var setup_id := "weasel"
var mode := "race"
var run_seed := 1990
var ticks := 0
var score := 0
var combo := 1
var clean_sectors := 0
var overtakes := 0
var collisions := 0
var finished := false
var finish_tick := 0
var player_place := 6
var last_event := ""
var event_serial := 0
var track_data: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _karts: Array[Dictionary] = []
var _player_index := 0
var _previous_place := 6
var _baked_track: Array[Dictionary] = []
var _track_bounds := Rect2()
var _drive_length := TRACK_LENGTH


func start_run(new_track_id := "parking", new_setup_id := "weasel",
		new_mode := "race", new_seed := 1990, new_track_data: Dictionary = {}) -> void:
	_configure_track(new_track_id, new_track_data)
	setup_id = new_setup_id if SETUPS.has(new_setup_id) else "weasel"
	mode = new_mode if new_mode in ["race", "time_attack", "training"] else "race"
	run_seed = new_seed
	_rng.seed = run_seed
	ticks = 0
	score = 0
	combo = 1
	clean_sectors = 0
	overtakes = 0
	collisions = 0
	finished = false
	finish_tick = 0
	player_place = 1 if mode != "race" else 6
	_previous_place = player_place
	last_event = "start"
	event_serial = 1
	_karts = []
	_create_player()
	if mode == "race":
		for i in AI_COUNT:
			_create_ai(i)
	_update_places()
	_previous_place = player_place


func _configure_track(new_track_id: String, custom_data: Dictionary) -> void:
	var candidate := Track.clone(custom_data) if not custom_data.is_empty() else Track.preset(
		new_track_id if track_index(new_track_id) >= 0 else "parking")
	var validation := Track.validate(candidate)
	if not bool(validation.get("ok", false)):
		candidate = Track.preset("parking")
		validation = Track.validate(candidate)
	track_data = candidate
	track_id = str(track_data.get("id", new_track_id))
	_baked_track = Track.bake(track_data)
	# Eine Editor-Kachel entspricht fahrphysikalisch 20 Metern; die 24 Weltpixel
	# bleiben ausschliesslich fuer Geometrie und Vorschau.
	_drive_length = maxf(TRACK_LENGTH, float(validation.get("length", 24)) * 20.0)
	_calculate_track_bounds()


func _calculate_track_bounds() -> void:
	if _baked_track.is_empty():
		_track_bounds = Rect2(0, 0, 1, 1)
		return
	var first: Vector2 = _baked_track[0].get("point", Vector2.ZERO)
	var minimum := first
	var maximum := first
	for sample: Dictionary in _baked_track:
		var point: Vector2 = sample.get("point", Vector2.ZERO)
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	_track_bounds = Rect2(minimum, (maximum - minimum).max(Vector2.ONE))


func _create_player() -> void:
	var setup: Dictionary = SETUPS[setup_id]
	_karts.append({
		"id": "player", "name": "DU", "color": "cyan", "player": true,
		"progress": 0.0, "lateral": 0.0, "lateral_speed": 0.0, "speed": 0.0,
		"max_speed": float(setup["max_speed"]), "accel": float(setup["accel"]),
		"handling": float(setup["handling"]), "grip": float(setup["grip"]),
		"turbo": 36.0, "heat": 0.0, "overheat_ticks": 0, "collision_ticks": 0,
		"drifting": false, "boosting": false, "offroad": false, "drafting": false,
		"lap": 1, "checkpoint": 0, "sector_clean": true, "finished": false,
		"finish_tick": 0, "place": player_place, "ai_lane": 0.0, "ai_skill": 1.0,
		"height": 0.0, "vertical_speed": 0.0, "airborne": false, "air_ticks": 0,
		"roll": 0.0, "pitch": 0.0, "last_piece": Track.Piece.START,
		"stunts": 0, "crashed": false, "heading_error": 0.0,
	})


func _create_ai(index: int) -> void:
	# Die KI benutzt dieselbe Beschleunigungs-/Reibungsroutine. Unterschiede sind
	# kleine, deterministische Setup- und Linienwerte, kein Teleport/Gummiband.
	var setups := ["weasel", "falcon", "block"]
	var ai_setup: Dictionary = SETUPS[setups[index % setups.size()]]
	var skill := 0.82 + float(index) * 0.027 + _rng.randf_range(-0.012, 0.012)
	var lane := _rng.randf_range(-6.0, 6.0)
	_karts.append({
		"id": "ai_%d" % index, "name": AI_NAMES[index], "color": AI_COLORS[index], "player": false,
		"progress": -0.010 - float(index) * 0.010, "lateral": lane * 0.45,
		"lateral_speed": 0.0, "speed": 0.0,
		"max_speed": float(ai_setup["max_speed"]) * skill,
		"accel": float(ai_setup["accel"]) * (0.94 + skill * 0.06),
		"handling": float(ai_setup["handling"]), "grip": float(ai_setup["grip"]),
		"turbo": 22.0 + float(index) * 3.0, "heat": 0.0, "overheat_ticks": 0,
		"collision_ticks": 0, "drifting": false, "boosting": false,
		"offroad": false, "drafting": false, "lap": 1, "checkpoint": 0,
		"sector_clean": true, "finished": false, "finish_tick": 0,
		"place": index + 2, "ai_lane": lane, "ai_skill": skill,
		"height": 0.0, "vertical_speed": 0.0, "airborne": false, "air_ticks": 0,
		"roll": 0.0, "pitch": 0.0, "last_piece": Track.Piece.START,
		"stunts": 0, "crashed": false, "heading_error": 0.0,
	})


func tick(input: Dictionary = {}) -> void:
	if finished or _karts.is_empty() or ticks >= MAX_TICKS:
		return
	ticks += 1
	last_event = ""
	var player_input := _normalized_input(input)
	for i in _karts.size():
		var kart: Dictionary = _karts[i]
		if bool(kart["finished"]):
			continue
		var controls := player_input if i == _player_index else _ai_input(kart)
		_step_kart(i, controls)
	_check_collisions()
	_update_places()
	_update_player_score()
	if bool(_karts[_player_index]["finished"]):
		finished = true
		finish_tick = int(_karts[_player_index]["finish_tick"])
		var finish_bonus := 32_000 + maxi(0, 7 - player_place) * 4_000
		score += finish_bonus + clean_sectors * 1_500 + overtakes * 1_200
		_emit_event("finish")


func _normalized_input(input: Dictionary) -> Dictionary:
	return {
		"throttle": clampf(float(input.get("throttle", 0.0)), 0.0, 1.0),
		"brake": clampf(float(input.get("brake", 0.0)), 0.0, 1.0),
		"steer": clampf(float(input.get("steer", 0.0)), -1.0, 1.0),
		"drift": bool(input.get("drift", false)),
		"turbo": bool(input.get("turbo", false)),
	}


func _ai_input(kart: Dictionary) -> Dictionary:
	var progress := float(kart["progress"])
	var lane_target := float(kart["ai_lane"]) + sin(progress * TAU * 3.0 + float(run_seed % 17)) * 1.4
	var curve_direction := signed_curvature_at(progress + 0.018)
	var steer := clampf((lane_target - float(kart["lateral"])) * 0.13
		+ curve_direction * 8.5 - float(kart.get("heading_error", 0.0)) * 0.7, -1.0, 1.0)
	var curve := curvature_at(progress + 0.025)
	var caution := clampf(curve * 4.6, 0.0, 0.30)
	var target_speed := float(kart["max_speed"]) * (1.0 - caution)
	var speed := float(kart["speed"])
	var brake := 1.0 if speed > target_speed + 3.0 else 0.0
	var use_turbo := curve < 0.035 and float(kart["turbo"]) > 54.0 and float(kart["heat"]) < 70.0
	return {
		"throttle": 1.0 if brake == 0.0 else 0.15,
		"brake": brake,
		"steer": steer,
		"drift": curve > 0.055 and speed > 52.0,
		"turbo": use_turbo,
	}


func _step_kart(index: int, controls: Dictionary) -> void:
	var kart: Dictionary = _karts[index]
	var previous_progress := float(kart["progress"])
	var speed := float(kart["speed"])
	var lateral := float(kart["lateral"])
	var lateral_speed := float(kart["lateral_speed"])
	var turbo := float(kart["turbo"])
	var heat := float(kart["heat"])
	var overheat_ticks := maxi(0, int(kart["overheat_ticks"]) - 1)
	var collision_ticks := maxi(0, int(kart["collision_ticks"]) - 1)
	var heading_error := float(kart.get("heading_error", 0.0))
	var road := road_half_width()
	var offroad := absf(lateral) > road
	var track_grip := grip_at(previous_progress)
	var grip := float(kart["grip"]) * track_grip
	var drifting := bool(controls["drift"]) and absf(float(controls["steer"])) > 0.18 and speed > 38.0
	var boosting := bool(controls["turbo"]) and turbo > 0.5 and heat < 100.0 and overheat_ticks <= 0

	if overheat_ticks > 0:
		speed = maxf(0.0, speed - 38.0 * TICK_DT)
		boosting = false
	else:
		var acceleration := float(kart["accel"]) * float(controls["throttle"])
		if boosting:
			acceleration += 36.0
			turbo = maxf(0.0, turbo - 27.0 * TICK_DT)
			heat += 38.0 * TICK_DT
		elif float(controls["throttle"]) < 0.1:
			acceleration -= 10.0
		if float(controls["brake"]) > 0.0:
			acceleration -= 68.0 * float(controls["brake"])
		if offroad:
			acceleration -= 36.0 + speed * 0.12
			kart["sector_clean"] = false
		var max_speed := float(kart["max_speed"]) + (24.0 if boosting else 0.0)
		speed = clampf(speed + acceleration * TICK_DT, 0.0, max_speed)

	var steering_rate := float(controls["steer"]) * float(kart["handling"]) * (0.62 + speed * 0.014)
	heading_error = clampf(heading_error + steering_rate * TICK_DT, -1.15, 1.15)
	var steer_force := sin(heading_error) * speed * 1.7
	lateral_speed += steer_force * TICK_DT
	var damping := (2.7 if drifting else 6.0) * grip
	lateral_speed *= maxf(0.0, 1.0 - damping * TICK_DT)
	if offroad:
		lateral_speed *= 0.965
	lateral += lateral_speed * TICK_DT
	if absf(lateral) > road + 14.0:
		lateral = signf(lateral) * (road + 14.0)
		lateral_speed *= -0.22
		speed *= 0.82
		kart["sector_clean"] = false

	# Windschatten und saubere Drifts bauen Turbodruck auf.
	var drafting := _has_draft(index)
	if drafting and speed > 45.0:
		turbo += 10.0 * TICK_DT
	if drifting:
		turbo += absf(float(controls["steer"])) * speed * 0.035 * TICK_DT
	if not boosting:
		heat = maxf(0.0, heat - (18.0 if speed < 35.0 else 12.0) * TICK_DT)
	if heat >= 100.0:
		heat = 100.0
		overheat_ticks = int(1.05 * TICK_RATE)
		boosting = false
		if index == _player_index:
			combo = 1
			_emit_event("overheat")
	turbo = clampf(turbo, 0.0, 100.0)

	var speed_factor := 1.0 - minf(0.13, curvature_at(previous_progress) * speed * 0.025)
	var progress_delta := maxf(0.08, cos(heading_error)) * speed * speed_factor * TICK_DT / _drive_length
	var next_progress := previous_progress + progress_delta
	var road_rotation := wrapf(track_tangent(next_progress).angle()
		- track_tangent(previous_progress).angle(), -PI, PI)
	heading_error = wrapf(heading_error - road_rotation, -PI, PI)
	var heading_damping := (0.48 if drifting else 1.15) * grip
	heading_error *= maxf(0.0, 1.0 - heading_damping * TICK_DT)
	kart["progress"] = next_progress
	kart["lateral"] = lateral
	kart["lateral_speed"] = lateral_speed
	kart["speed"] = speed
	kart["turbo"] = turbo
	kart["heat"] = heat
	kart["overheat_ticks"] = overheat_ticks
	kart["collision_ticks"] = collision_ticks
	kart["drifting"] = drifting
	kart["boosting"] = boosting
	kart["offroad"] = offroad
	kart["drafting"] = drafting
	kart["heading_error"] = heading_error
	_step_stunts(kart, index, previous_progress)
	_update_checkpoints(kart, previous_progress)
	_karts[index] = kart


func _step_stunts(kart: Dictionary, index: int, previous_progress: float) -> void:
	var progress := float(kart["progress"])
	var piece := track_piece(progress)
	var previous_piece := int(kart.get("last_piece", Track.Piece.START))
	var speed := float(kart["speed"])
	var airborne := bool(kart.get("airborne", false))
	var air_ticks := int(kart.get("air_ticks", 0))
	var height := float(kart.get("height", 0.0))
	var vertical_speed := float(kart.get("vertical_speed", 0.0))
	var ground_height := track_height(progress)

	if piece == Track.Piece.RAMP and piece != previous_piece and speed >= 28.0:
		airborne = true
		air_ticks = 0
		height = ground_height + 0.15
		vertical_speed = 5.4 + speed * 0.036
		if index == _player_index:
			_emit_event("jump")
	if airborne:
		air_ticks += 1
		vertical_speed -= 12.5 * TICK_DT
		height += vertical_speed * TICK_DT
		if height <= ground_height and air_ticks > 8:
			height = ground_height
			airborne = false
			var hard_landing := vertical_speed < -8.4 or absf(float(kart["lateral"])) > road_half_width() + 2.0
			if hard_landing:
				kart["speed"] = speed * 0.48
				kart["sector_clean"] = false
				kart["crashed"] = true
				if index == _player_index:
					collisions += 1
					combo = 1
					_emit_event("crash")
			elif index == _player_index:
				score += 2_000 * combo
				_emit_event("land")
	else:
		height = ground_height
		vertical_speed = 0.0
		kart["crashed"] = false

	if previous_piece in [Track.Piece.LOOP, Track.Piece.CORKSCREW] and piece != previous_piece:
		kart["stunts"] = int(kart.get("stunts", 0)) + 1
		if index == _player_index:
			score += (4_500 if previous_piece == Track.Piece.LOOP else 6_000) * combo
			combo = mini(4, combo + 1)
			_emit_event("stunt")

	kart["height"] = height
	kart["vertical_speed"] = vertical_speed
	kart["airborne"] = airborne
	kart["air_ticks"] = air_ticks
	kart["roll"] = track_roll(progress)
	kart["pitch"] = clampf((track_height(progress + 0.002) - track_height(previous_progress)) * 0.12,
		-0.42, 0.42)
	kart["last_piece"] = piece


func _update_checkpoints(kart: Dictionary, previous_progress: float) -> void:
	var progress := float(kart["progress"])
	var old_sector := int(floor(maxf(0.0, previous_progress) * 4.0))
	var new_sector := int(floor(maxf(0.0, progress) * 4.0))
	if new_sector > old_sector:
		for sector in range(old_sector + 1, new_sector + 1):
			kart["checkpoint"] = sector % 4
			if bool(kart["player"]) and sector % 4 != 0:
				if bool(kart["sector_clean"]):
					clean_sectors += 1
					score += 850 * combo
					combo = mini(4, combo + 1)
				else:
					combo = 1
				kart["sector_clean"] = true
	var old_lap := maxi(0, int(floor(previous_progress)))
	var new_lap := maxi(0, int(floor(progress)))
	if new_lap > old_lap:
		kart["lap"] = mini(LAPS, new_lap + 1)
		if bool(kart["player"]):
			score += 8_000 * combo
			_emit_event("lap")
	if progress >= float(LAPS) and not bool(kart["finished"]):
		kart["finished"] = true
		kart["finish_tick"] = ticks
		kart["lap"] = LAPS


func _has_draft(index: int) -> bool:
	var kart: Dictionary = _karts[index]
	var progress := float(kart["progress"])
	for j in _karts.size():
		if j == index:
			continue
		var other: Dictionary = _karts[j]
		var gap := float(other["progress"]) - progress
		if gap > 0.003 and gap < 0.030 and absf(float(other["lateral"]) - float(kart["lateral"])) < 5.5:
			return true
	return false


func _check_collisions() -> void:
	for i in _karts.size():
		for j in range(i + 1, _karts.size()):
			var a: Dictionary = _karts[i]
			var b: Dictionary = _karts[j]
			if bool(a.get("airborne", false)) or bool(b.get("airborne", false)):
				continue
			if int(a["collision_ticks"]) > 0 or int(b["collision_ticks"]) > 0:
				continue
			if absf(float(a["progress"]) - float(b["progress"])) > 0.012:
				continue
			if absf(float(a["lateral"]) - float(b["lateral"])) > 4.8:
				continue
			var push := 3.2 if float(a["lateral"]) <= float(b["lateral"]) else -3.2
			a["lateral_speed"] = float(a["lateral_speed"]) - push
			b["lateral_speed"] = float(b["lateral_speed"]) + push
			a["speed"] = float(a["speed"]) * 0.79
			b["speed"] = float(b["speed"]) * 0.82
			a["collision_ticks"] = 30
			b["collision_ticks"] = 30
			a["sector_clean"] = false
			b["sector_clean"] = false
			_karts[i] = a
			_karts[j] = b
			if i == _player_index or j == _player_index:
				collisions += 1
				combo = 1
				_emit_event("collision")


func _update_places() -> void:
	var order: Array[int] = []
	for i in _karts.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ka: Dictionary = _karts[a]
		var kb: Dictionary = _karts[b]
		if bool(ka["finished"]) != bool(kb["finished"]):
			return bool(ka["finished"])
		if bool(ka["finished"]):
			return int(ka["finish_tick"]) < int(kb["finish_tick"])
		return float(ka["progress"]) > float(kb["progress"]))
	for place in order.size():
		var index: int = order[place]
		var kart: Dictionary = _karts[index]
		kart["place"] = place + 1
		_karts[index] = kart
	player_place = int(_karts[_player_index]["place"])
	if player_place < _previous_place and ticks > TICK_RATE:
		var gained := _previous_place - player_place
		overtakes += gained
		score += 1_400 * gained * combo
		combo = mini(4, combo + 1)
		_emit_event("overtake")
	_previous_place = player_place


func _update_player_score() -> void:
	if ticks % 6 == 0:
		var player: Dictionary = _karts[_player_index]
		score += int(float(player["speed"]) * 0.72) * combo
		if bool(player["drifting"]):
			score += int(absf(float(player["lateral_speed"])) * 12.0) * combo


func _emit_event(event_name: String) -> void:
	last_event = event_name
	event_serial += 1


func player_state() -> Dictionary:
	return _karts[_player_index].duplicate(true) if not _karts.is_empty() else {}


func kart_states() -> Array:
	return _karts.duplicate(true)


func elapsed_ms() -> int:
	return int(round(float(finish_tick if finished else ticks) * 1000.0 / TICK_RATE))


func snapshot() -> Dictionary:
	var compact: Array = []
	for kart: Dictionary in _karts:
		compact.append({
			"id": kart["id"], "progress": snappedf(float(kart["progress"]), 0.000001),
			"lateral": snappedf(float(kart["lateral"]), 0.0001),
			"speed": snappedf(float(kart["speed"]), 0.0001),
			"turbo": snappedf(float(kart["turbo"]), 0.0001),
			"heat": snappedf(float(kart["heat"]), 0.0001),
			"lap": kart["lap"], "place": kart["place"], "finished": kart["finished"],
			"height": snappedf(float(kart.get("height", 0.0)), 0.0001),
			"airborne": kart.get("airborne", false), "stunts": kart.get("stunts", 0),
			"heading_error": snappedf(float(kart.get("heading_error", 0.0)), 0.0001),
		})
	return {
		"track": track_id, "setup": setup_id, "mode": mode, "seed": run_seed,
		"ticks": ticks, "score": score, "combo": combo, "place": player_place,
		"finished": finished, "finish_tick": finish_tick, "karts": compact,
	}


func track_point(progress: float) -> Vector2:
	if _baked_track.is_empty():
		return Vector2(160, 105)
	var sample_position := fposmod(progress, 1.0) * float(_baked_track.size())
	var index := floori(sample_position) % _baked_track.size()
	var next := (index + 1) % _baked_track.size()
	var weight := sample_position - floorf(sample_position)
	var raw := Vector2(_baked_track[index].get("point", Vector2.ZERO)).lerp(
		Vector2(_baked_track[next].get("point", Vector2.ZERO)), weight)
	var scale := minf(240.0 / maxf(1.0, _track_bounds.size.x),
		145.0 / maxf(1.0, _track_bounds.size.y))
	return Vector2(160, 105) + (raw - _track_bounds.get_center()) * scale


func track_tangent(progress: float) -> Vector2:
	if _baked_track.is_empty():
		return Vector2.RIGHT
	# Ein symmetrisches Fenster ueber rund anderthalb Kacheln entfernt nicht nur
	# Stuetzpunktstufen, sondern verteilt auch eine 90-Grad-Kachelkurve ueber eine
	# physisch lesbare Einlenkphase. Das ist nicht nur Kosmetik: Strasse, Horizont,
	# KI und Lenkrueckstellung sehen dieselbe stabile Tangente. Ein fixes Fenster
	# in Samples bleibt bei kurzen und langen Generatorstrecken identisch.
	var epsilon := clampf(18.0 / float(_baked_track.size()), 0.0025, 0.062)
	var tangent := track_point(progress + epsilon) - track_point(progress - epsilon)
	return tangent.normalized() if tangent.length_squared() > 0.000001 else Vector2.RIGHT


func track_normal(progress: float) -> Vector2:
	var tangent := track_tangent(progress)
	return Vector2(-tangent.y, tangent.x)


func kart_world_position(kart: Dictionary) -> Vector2:
	var progress := float(kart.get("progress", 0.0))
	return track_point(progress) + track_normal(progress) * float(kart.get("lateral", 0.0))


func curvature_at(progress: float) -> float:
	var before := track_tangent(progress - 0.004)
	var after := track_tangent(progress + 0.004)
	return clampf(absf(before.cross(after)), 0.0, 1.0)


func signed_curvature_at(progress: float) -> float:
	var before := track_tangent(progress - 0.004)
	var after := track_tangent(progress + 0.004)
	return clampf(before.cross(after), -1.0, 1.0)


func road_half_width() -> float:
	if track_data.has("road"):
		return float(track_data["road"])
	var index := track_index(track_id)
	return float(TRACKS[index]["road"]) if index >= 0 else 17.0


func track_name() -> String:
	var index := track_index(track_id)
	return str(TRACKS[index]["name"]) if index >= 0 else str(track_data.get("title", "EIGENER KURS"))


func drive_length() -> float:
	return _drive_length


func track_sample(progress: float) -> Dictionary:
	if _baked_track.is_empty():
		return {"point": Vector2.ZERO, "height": 0.0, "roll": 0.0,
			"piece": Track.Piece.STRAIGHT, "local": 0.0}
	var index := floori(fposmod(progress, 1.0) * float(_baked_track.size())) % _baked_track.size()
	return _baked_track[index]


func track_height(progress: float) -> float:
	if _baked_track.is_empty():
		return 0.0
	var sample_position := fposmod(progress, 1.0) * float(_baked_track.size())
	var index := floori(sample_position) % _baked_track.size()
	var next := (index + 1) % _baked_track.size()
	var weight := sample_position - floorf(sample_position)
	return lerpf(float(_baked_track[index].get("height", 0.0)),
		float(_baked_track[next].get("height", 0.0)), weight)


func track_roll(progress: float) -> float:
	return float(track_sample(progress).get("roll", 0.0))


func track_piece(progress: float) -> int:
	return int(track_sample(progress).get("piece", Track.Piece.STRAIGHT))


func grip_at(progress: float) -> float:
	var index := track_index(track_id)
	var base := float(TRACKS[index]["grip"]) if index >= 0 else 0.96
	match track_piece(progress):
		Track.Piece.ICE: return base * 0.48
		Track.Piece.DIRT: return base * 0.76
		_: return base


static func track_index(id: String) -> int:
	for i in TRACKS.size():
		if str(TRACKS[i]["id"]) == id:
			return i
	return -1


func force_player_state(progress: float, lateral: float, speed: float) -> void:
	# Test-/Proof-Hook; wird von der normalen UI nicht verwendet.
	if _karts.is_empty():
		return
	var kart: Dictionary = _karts[_player_index]
	kart["progress"] = progress
	kart["lateral"] = lateral
	kart["lateral_speed"] = 0.0
	kart["heading_error"] = 0.0
	kart["speed"] = maxf(0.0, speed)
	kart["offroad"] = absf(lateral) > road_half_width()
	_karts[_player_index] = kart


func force_kart_state(index: int, progress: float, lateral: float, speed: float) -> void:
	# Erweiterter Test-/Proof-Hook fuer reproduzierbare Kollisionsfaelle.
	if index < 0 or index >= _karts.size():
		return
	var kart: Dictionary = _karts[index]
	kart["progress"] = progress
	kart["lateral"] = lateral
	kart["speed"] = maxf(0.0, speed)
	kart["collision_ticks"] = 0
	_karts[index] = kart


func force_player_resources(turbo: float, heat: float) -> void:
	if _karts.is_empty():
		return
	var kart: Dictionary = _karts[_player_index]
	kart["turbo"] = clampf(turbo, 0.0, 100.0)
	kart["heat"] = clampf(heat, 0.0, 100.0)
	kart["overheat_ticks"] = 0
	_karts[_player_index] = kart
