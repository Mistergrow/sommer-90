class_name CodeRedState
extends RefCounted
## Save-Codec und Momentaufnahme fuer den deterministischen Kampagnenkern.


static func encode(model, save_version: int) -> Dictionary:
	return {
		"version": save_version, "seed": model.operation_seed, "turn": model.turn,
		"commands_left": model.commands_left, "budget": model.budget,
		"coalition": model.coalition, "media": model.media, "science": model.science,
		"stability": model.stability, "panic": model.panic, "truth": model.truth,
		"burden": model.burden, "particles": model.particles, "routes": model.routes,
		"elite_escape": model.elite_escape, "planet": model.planet,
		"induction": model.induction, "plasma_load": model.plasma_load,
		"explanation": model.explanation, "cooldowns": model.cooldowns.duplicate(true),
		"action_counts": model.action_counts.duplicate(true),
		"pending_event": model.pending_event.duplicate(true), "history": model.history.duplicate(),
		"ended": model.ended, "ending": model.ending, "doctrine": model.doctrine,
		"credibility": model.credibility, "advisors": model.advisors.duplicate(true),
		"regions": model.regions.duplicate(true), "opponents": model.opponents.duplicate(true),
		"projects": model.projects.duplicate(true),
		"explanation_uses": model.explanation_uses.duplicate(true),
		"event_flags": model.event_flags.duplicate(true),
		"last_debrief": model.last_debrief.duplicate(true),
		"optics_done_turn": model.optics_done_turn, "optics_correct": model.optics_correct,
		"optics_wrong": model.optics_wrong, "optics_cases": model.optics_cases.duplicate(true),
		"lead_advisor_id": model.lead_advisor_id,
		"advisor_selected_turn": model.advisor_selected_turn,
		"advisor_defections": model.advisor_defections, "region_crises": model.region_crises,
	}


static func decode(model, raw: Variant, save_version: int, total_rounds: int,
		commands_per_round: int) -> bool:
	if not raw is Dictionary:
		return false
	var data: Dictionary = raw
	if int(data.get("version", 0)) != save_version:
		return false
	model.reset(int(data.get("seed", 2025)))
	model.turn = clampi(int(data.get("turn", 0)), 0, total_rounds)
	model.commands_left = clampi(int(data.get("commands_left", commands_per_round)), 0,
		commands_per_round)
	for key in ["budget", "coalition", "media", "science", "stability", "panic", "truth",
			"burden", "particles", "routes", "elite_escape", "planet", "induction", "plasma_load"]:
		model.set(key, float(data.get(key, model.get(key))))
	model.explanation = str(data.get("explanation", "SAHARASTAUB"))
	for key in ["cooldowns", "action_counts", "pending_event", "advisors", "regions",
			"opponents", "projects", "explanation_uses", "event_flags", "last_debrief",
			"optics_cases"]:
		model.set(key, (data.get(key, model.get(key)) as Dictionary).duplicate(true))
	var restored_history: Array[String] = []
	for line: Variant in data.get("history", []):
		restored_history.append(str(line).substr(0, 120))
	model.history = restored_history
	model.ended = bool(data.get("ended", false))
	model.ending = str(data.get("ending", "")) if model.ended else ""
	model.doctrine = str(data.get("doctrine", ""))
	model.credibility = float(data.get("credibility", model.credibility))
	model.optics_done_turn = int(data.get("optics_done_turn", -1))
	model.optics_correct = int(data.get("optics_correct", 0))
	model.optics_wrong = int(data.get("optics_wrong", 0))
	model.lead_advisor_id = str(data.get("lead_advisor_id", ""))
	model.advisor_selected_turn = int(data.get("advisor_selected_turn", -1))
	model.advisor_defections = int(data.get("advisor_defections", 0))
	model.region_crises = int(data.get("region_crises", 0))
	model._round_start = metric_snapshot(model)
	model._clamp_all()
	return true


static func metric_snapshot(model) -> Dictionary:
	return {
		"budget": model.budget, "coalition": model.coalition, "media": model.media,
		"science": model.science, "stability": model.stability, "panic": model.panic,
		"truth": model.truth, "burden": model.burden, "particles": model.particles,
		"routes": model.routes, "elite_escape": model.elite_escape, "planet": model.planet,
		"induction": model.induction, "plasma_load": model.plasma_load,
		"credibility": model.credibility,
	}
