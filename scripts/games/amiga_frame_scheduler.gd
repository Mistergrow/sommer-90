class_name AmigaFrameScheduler
extends RefCounted
## Deterministische PAL-Laufzeituhr und visuelles Framebudget.
##
## Die Simulation wird ausschliesslich durch [method consume_logic_step] in
## festen 20-ms-Schritten fortgeschaltet. [method interpolation_alpha] ist nur
## fuer die Darstellung zwischen dem vorherigen und aktuellen Simulationsstand
## gedacht; der Scheduler schreibt niemals in Spiel- oder Physikzustand.
##
## Typische Nutzung:
## [codeblock]
## scheduler.begin_frame(delta)
## while scheduler.consume_logic_step():
##     model.fixed_update(AmigaFrameScheduler.PAL_STEP_SECONDS)
## renderer.draw(model.previous_state, model.current_state,
##     scheduler.interpolation_alpha())
## [/codeblock]

const Contract := preload("res://scripts/games/amiga_video_contract.gd")

signal budget_overflow(
		category: StringName, requested_units: int, remaining_units: int, frame_index: int)
signal catch_up_limited(dropped_steps: int, frame_index: int)

const PAL_HZ := 50
const PAL_STEP_SECONDS := 1.0 / float(PAL_HZ)
const PAL_STEP_NSEC := 20_000_000
const MAX_CATCH_UP_STEPS := 5
const MAX_INPUT_DELTA_NSEC := 1_000_000_000

const ANIMATION_UPDATES: StringName = &"animation_updates"
const ANIMATION_PHASES: StringName = &"animation_phases"
const PARALLAX_LAYERS: StringName = &"parallax_layers"
const FX_SPAWNS: StringName = &"fx_spawns"
const FX_UPDATES: StringName = &"fx_updates"
const BLITTER_PIXELS: StringName = &"blitter_pixels"

# Laufzeitbudgets, die nicht bereits Teil des Videovertrags sind. Phasenzahl,
# Parallax und Blitterdurchsatz werden unten direkt aus dem Contract gelesen.
# Die Abstufung ist bewusst deutlich: AGA kann mehr persistente Partikel und
# Animationsarbeit zeigen, ohne die feste PAL-Spielsimulation zu veraendern.
const GENERATION_RUNTIME_LIMITS: Dictionary = {
	Contract.Chipset.OCS: {
		"animation_updates_per_frame": 48,
		"fx_spawns_per_frame": 8,
		"fx_updates_per_frame": 64,
		"max_active_fx": 64,
	},
	Contract.Chipset.ECS: {
		"animation_updates_per_frame": 80,
		"fx_spawns_per_frame": 14,
		"fx_updates_per_frame": 104,
		"max_active_fx": 96,
	},
	Contract.Chipset.AGA: {
		"animation_updates_per_frame": 144,
		"fx_spawns_per_frame": 28,
		"fx_updates_per_frame": 208,
		"max_active_fx": 192,
	},
}

var _configured := false
var _game_id := ""
var _chipset := -1

var _accumulator_nsec := 0
var _pending_steps := 0
var _logic_tick := 0
var _frame_index := 0

var _animation_update_limit := 0
var _animation_phase_limit := 0
var _parallax_limit := 0
var _fx_spawn_limit := 0
var _fx_update_limit := 0
var _active_fx_limit := 0
var _blitter_pixel_limit := 0

var _animation_updates_used := 0
var _parallax_layers_used := 0
var _fx_spawns_used := 0
var _fx_updates_used := 0
var _blitter_pixels_used := 0

var _animation_updates_peak := 0
var _parallax_layers_peak := 0
var _fx_spawns_peak := 0
var _fx_updates_peak := 0
var _blitter_pixels_peak := 0

var _dropped_logic_steps := 0
var _dropped_time_nsec := 0
var _catch_up_limited_frames := 0
var _input_clamped_frames := 0
var _unconsumed_step_frames := 0
var _budget_overflows := 0
var _animation_overflows := 0
var _parallax_overflows := 0
var _fx_overflows := 0
var _blitter_overflows := 0


static func runtime_budget_for(profile_or_chipset: Variant) -> Dictionary:
	var chipset_id := -1
	if profile_or_chipset is Dictionary:
		chipset_id = int((profile_or_chipset as Dictionary).get("chipset", -1))
	else:
		chipset_id = int(profile_or_chipset)
	var generation: Dictionary = GENERATION_RUNTIME_LIMITS.get(chipset_id, {})
	var hardware := Contract.limits_for(chipset_id)
	if generation.is_empty() or hardware.is_empty():
		return {}
	return {
		"chipset": chipset_id,
		"chipset_name": Contract.chipset_name(chipset_id),
		"logic_hz": PAL_HZ,
		"animation_updates_per_frame":
			int(generation.get("animation_updates_per_frame", 0)),
		"animation_phases_per_actor":
			int(hardware.get("animation_frames_per_actor", 0)),
		"parallax_layers": int(hardware.get("parallax_layers", 0)),
		"fx_spawns_per_frame": int(generation.get("fx_spawns_per_frame", 0)),
		"fx_updates_per_frame": int(generation.get("fx_updates_per_frame", 0)),
		"max_active_fx": int(generation.get("max_active_fx", 0)),
		"blitter_pixels_per_frame":
			int(hardware.get("blitter_pixels_per_frame", 0)),
	}


func configure(profile: Dictionary) -> Dictionary:
	var validation := Contract.validate_profile(profile)
	if not bool(validation.get("ok", false)):
		_configured = false
		return {
			"ok": false,
			"errors": (validation.get("errors", []) as Array).duplicate(),
		}
	var budget := runtime_budget_for(profile)
	if budget.is_empty():
		_configured = false
		return {"ok": false, "errors": ["Kein Laufzeitbudget fuer Profil"]}
	_game_id = str(profile.get("game_id", ""))
	_chipset = int(profile.get("chipset", -1))
	_apply_budget(budget)
	reset_clock()
	reset_telemetry()
	_configured = true
	return {
		"ok": true,
		"game_id": _game_id,
		"chipset": _chipset,
		"budget": budget,
	}


func configure_for_game(requested_game_id: String) -> Dictionary:
	var profile := Contract.game_profile(requested_game_id)
	if profile.is_empty():
		_configured = false
		return {
			"ok": false,
			"errors": ["Unbekanntes Amiga-Spiel: %s" % requested_game_id],
		}
	return configure(profile)


func _apply_budget(budget: Dictionary) -> void:
	_animation_update_limit = int(budget.get("animation_updates_per_frame", 0))
	_animation_phase_limit = int(budget.get("animation_phases_per_actor", 0))
	_parallax_limit = int(budget.get("parallax_layers", 0))
	_fx_spawn_limit = int(budget.get("fx_spawns_per_frame", 0))
	_fx_update_limit = int(budget.get("fx_updates_per_frame", 0))
	_active_fx_limit = int(budget.get("max_active_fx", 0))
	_blitter_pixel_limit = int(budget.get("blitter_pixels_per_frame", 0))


func reset_clock() -> void:
	_accumulator_nsec = 0
	_pending_steps = 0
	_logic_tick = 0
	_frame_index = 0
	_reset_frame_usage()


func reset_telemetry() -> void:
	_animation_updates_peak = 0
	_parallax_layers_peak = 0
	_fx_spawns_peak = 0
	_fx_updates_peak = 0
	_blitter_pixels_peak = 0
	_dropped_logic_steps = 0
	_dropped_time_nsec = 0
	_catch_up_limited_frames = 0
	_input_clamped_frames = 0
	_unconsumed_step_frames = 0
	_budget_overflows = 0
	_animation_overflows = 0
	_parallax_overflows = 0
	_fx_overflows = 0
	_blitter_overflows = 0


func is_configured() -> bool:
	return _configured


func game_id() -> String:
	return _game_id


func chipset() -> int:
	return _chipset


func begin_frame(delta_seconds: float) -> int:
	return begin_frame_nsec(maxi(0, roundi(delta_seconds * 1_000_000_000.0)))


func begin_frame_nsec(delta_nsec: int) -> int:
	if not _configured:
		return 0
	if _pending_steps > 0:
		# Ein neuer Frame darf den bereits zugesagten Simulationstick nicht
		# verschlucken. Der Aufrufer bekommt dieselbe Restarbeit zurueck.
		_unconsumed_step_frames += 1
		return _pending_steps

	_frame_index += 1
	_reset_frame_usage()
	var accepted_delta := maxi(0, delta_nsec)
	if accepted_delta > MAX_INPUT_DELTA_NSEC:
		_input_clamped_frames += 1
		_dropped_time_nsec += accepted_delta - MAX_INPUT_DELTA_NSEC
		accepted_delta = MAX_INPUT_DELTA_NSEC
	_accumulator_nsec += accepted_delta

	@warning_ignore("integer_division")
	var available_steps := _accumulator_nsec / PAL_STEP_NSEC
	_pending_steps = mini(available_steps, MAX_CATCH_UP_STEPS)
	_accumulator_nsec -= _pending_steps * PAL_STEP_NSEC
	if _accumulator_nsec >= PAL_STEP_NSEC:
		@warning_ignore("integer_division")
		var dropped := _accumulator_nsec / PAL_STEP_NSEC
		_accumulator_nsec -= dropped * PAL_STEP_NSEC
		_dropped_logic_steps += dropped
		_dropped_time_nsec += dropped * PAL_STEP_NSEC
		_catch_up_limited_frames += 1
		catch_up_limited.emit(dropped, _frame_index)
	return _pending_steps


func consume_logic_step() -> bool:
	if _pending_steps <= 0:
		return false
	_pending_steps -= 1
	_logic_tick += 1
	return true


func run_frame(delta_seconds: float, fixed_update: Callable) -> int:
	if not fixed_update.is_valid():
		return 0
	var scheduled := begin_frame(delta_seconds)
	var dispatched := 0
	while consume_logic_step():
		fixed_update.call(PAL_STEP_SECONDS, _logic_tick)
		dispatched += 1
	return mini(dispatched, scheduled)


func pending_logic_steps() -> int:
	return _pending_steps


func logic_tick() -> int:
	return _logic_tick


func frame_index() -> int:
	return _frame_index


func interpolation_alpha() -> float:
	return float(_accumulator_nsec) / float(PAL_STEP_NSEC)


func interpolated_pixel(previous: Vector2, current: Vector2) -> Vector2i:
	return Contract.snap_point(previous.lerp(current, interpolation_alpha()))


func interpolated_scalar(previous: float, current: float) -> float:
	return lerpf(previous, current, interpolation_alpha())


func try_reserve_animation(actor_updates: int = 1, phases_per_actor: int = 1) -> bool:
	if actor_updates < 0 or phases_per_actor < 1:
		_record_budget_overflow(ANIMATION_UPDATES, maxi(1, actor_updates), 0)
		return false
	if phases_per_actor > _animation_phase_limit:
		_record_budget_overflow(
			ANIMATION_PHASES, phases_per_actor, _animation_phase_limit)
		return false
	return _reserve_units(
		ANIMATION_UPDATES,
		actor_updates,
		_animation_update_limit,
		_animation_updates_used,
	)


func try_reserve_parallax(layers: int = 1) -> bool:
	return _reserve_units(
		PARALLAX_LAYERS, layers, _parallax_limit, _parallax_layers_used)


func try_reserve_fx_spawn(count: int = 1) -> bool:
	return _reserve_units(FX_SPAWNS, count, _fx_spawn_limit, _fx_spawns_used)


func try_reserve_fx_update(count: int = 1) -> bool:
	return _reserve_units(FX_UPDATES, count, _fx_update_limit, _fx_updates_used)


func try_reserve_blitter_pixels(pixel_count: int) -> bool:
	return _reserve_units(
		BLITTER_PIXELS, pixel_count, _blitter_pixel_limit, _blitter_pixels_used)


func _reserve_units(category: StringName, requested: int, limit: int, used: int) -> bool:
	if requested < 0 or used + requested > limit:
		_record_budget_overflow(category, maxi(1, requested), maxi(0, limit - used))
		return false
	match category:
		ANIMATION_UPDATES:
			_animation_updates_used += requested
			_animation_updates_peak = maxi(
				_animation_updates_peak, _animation_updates_used)
		PARALLAX_LAYERS:
			_parallax_layers_used += requested
			_parallax_layers_peak = maxi(
				_parallax_layers_peak, _parallax_layers_used)
		FX_SPAWNS:
			_fx_spawns_used += requested
			_fx_spawns_peak = maxi(_fx_spawns_peak, _fx_spawns_used)
		FX_UPDATES:
			_fx_updates_used += requested
			_fx_updates_peak = maxi(_fx_updates_peak, _fx_updates_used)
		BLITTER_PIXELS:
			_blitter_pixels_used += requested
			_blitter_pixels_peak = maxi(
				_blitter_pixels_peak, _blitter_pixels_used)
	return true


func _record_budget_overflow(
		category: StringName, requested: int, remaining: int) -> void:
	_budget_overflows += 1
	match category:
		ANIMATION_UPDATES, ANIMATION_PHASES:
			_animation_overflows += 1
		PARALLAX_LAYERS:
			_parallax_overflows += 1
		FX_SPAWNS, FX_UPDATES:
			_fx_overflows += 1
		BLITTER_PIXELS:
			_blitter_overflows += 1
	budget_overflow.emit(category, requested, remaining, _frame_index)


func _reset_frame_usage() -> void:
	_animation_updates_used = 0
	_parallax_layers_used = 0
	_fx_spawns_used = 0
	_fx_updates_used = 0
	_blitter_pixels_used = 0


func budget_snapshot() -> Dictionary:
	return {
		"game_id": _game_id,
		"chipset": _chipset,
		"animation_updates": {
			"used": _animation_updates_used,
			"limit": _animation_update_limit,
			"peak": _animation_updates_peak,
		},
		"animation_phases_per_actor": _animation_phase_limit,
		"parallax_layers": {
			"used": _parallax_layers_used,
			"limit": _parallax_limit,
			"peak": _parallax_layers_peak,
		},
		"fx_spawns": {
			"used": _fx_spawns_used,
			"limit": _fx_spawn_limit,
			"peak": _fx_spawns_peak,
		},
		"fx_updates": {
			"used": _fx_updates_used,
			"limit": _fx_update_limit,
			"peak": _fx_updates_peak,
		},
		"max_active_fx": _active_fx_limit,
		"blitter_pixels": {
			"used": _blitter_pixels_used,
			"limit": _blitter_pixel_limit,
			"peak": _blitter_pixels_peak,
		},
	}


func telemetry_snapshot() -> Dictionary:
	return {
		"game_id": _game_id,
		"chipset": _chipset,
		"frame_index": _frame_index,
		"logic_tick": _logic_tick,
		"pending_logic_steps": _pending_steps,
		"interpolation_alpha": interpolation_alpha(),
		"dropped_logic_steps": _dropped_logic_steps,
		"dropped_time_nsec": _dropped_time_nsec,
		"catch_up_limited_frames": _catch_up_limited_frames,
		"input_clamped_frames": _input_clamped_frames,
		"unconsumed_step_frames": _unconsumed_step_frames,
		"budget_overflows": _budget_overflows,
		"animation_overflows": _animation_overflows,
		"parallax_overflows": _parallax_overflows,
		"fx_overflows": _fx_overflows,
		"blitter_overflows": _blitter_overflows,
		"budget": budget_snapshot(),
	}
