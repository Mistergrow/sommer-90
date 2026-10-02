class_name CodeRedModel
extends RefCounted
## Deterministischer Kampagnenkern fuer CODE RED: PROTOKOLL 2025.
## Alle Behauptungen gehoeren zur fiktiven Spielwelt; das Modell verwaltet nur
## Ressourcen, Entscheidungen und Konsequenzen eines dystopischen Strategiespiels.

const Content := preload("res://scripts/games/code_red_content.gd")
const EventCatalog := preload("res://scripts/games/code_red_events.gd")
const Timeline := preload("res://scripts/games/code_red_timeline.gd")
const StateCodec := preload("res://scripts/games/code_red_state.gd")
const ActionCatalog := preload("res://scripts/games/code_red_actions.gd")
const Reports := preload("res://scripts/games/code_red_reports.gd")

const DISCOVERY_YEAR := 1962
const CATASTROPHE_YEAR := 2034
const CATASTROPHE_WINDOW := "JULI/AUGUST 2034"
const TIMELINE: Array[int] = Timeline.YEARS
const TOTAL_ROUNDS := Timeline.TOTAL_ROUNDS
const COMMANDS_PER_ROUND := 2
const SAVE_VERSION := 3

const ACTIONS: Dictionary = ActionCatalog.ACTIONS

var operation_seed := 2025
var turn := 0
var commands_left := COMMANDS_PER_ROUND
var budget := 75.0
var coalition := 58.0
var media := 45.0
var science := 42.0
var stability := 70.0
var panic := 8.0
var truth := 6.0
var burden := 5.0
var particles := 0.0
var routes := 20.0
var elite_escape := 0.0
var planet := 8.0
var induction := 12.0
var plasma_load := 3.0
var explanation := "SAHARASTAUB"
var cooldowns: Dictionary = {}
var action_counts: Dictionary = {}
var pending_event: Dictionary = {}
var history: Array[String] = []
var ended := false
var ending := ""
var doctrine := ""
var credibility := 58.0
var advisors: Dictionary = {}
var regions: Dictionary = {}
var opponents: Dictionary = {}
var projects: Dictionary = {}
var explanation_uses: Dictionary = {}
var event_flags: Dictionary = {}
var last_debrief: Dictionary = {}
var optics_done_turn := -1
var optics_correct := 0
var optics_wrong := 0
var optics_cases: Dictionary = {}
var lead_advisor_id := ""
var advisor_selected_turn := -1
var advisor_defections := 0
var region_crises := 0
var _content := Content.new()
var _round_start: Dictionary = {}


func reset(run_seed := 1962) -> void:
	_content.load_config()
	operation_seed = run_seed
	turn = 0
	commands_left = COMMANDS_PER_ROUND
	budget = 75.0
	coalition = 58.0
	media = 45.0
	science = 42.0
	stability = 70.0
	panic = 8.0
	truth = 6.0
	burden = 5.0
	particles = 0.0
	routes = 20.0
	elite_escape = 0.0
	planet = 8.0
	induction = 12.0
	plasma_load = 3.0
	explanation = "SAHARASTAUB"
	cooldowns = {}
	action_counts = {}
	pending_event = {}
	history = ["1962 · OBJEKT ENTDECKT · PROTOKOLL AKTIV"]
	ended = false
	ending = ""
	doctrine = ""
	credibility = 58.0
	advisors = {}
	for entry: Dictionary in _content.all("advisors"):
		entry["status"] = "ACTIVE"
		entry["leak_reported"] = false
		advisors[str(entry["id"])] = entry.duplicate(true)
	regions = {}
	for entry: Dictionary in _content.all("regions"):
		regions[str(entry["id"])] = entry.duplicate(true)
	opponents = {}
	for entry: Dictionary in _content.all("opponents"):
		opponents[str(entry["id"])] = entry.duplicate(true)
	projects = {}
	explanation_uses = {}
	event_flags = {}
	last_debrief = {}
	optics_done_turn = -1
	optics_correct = 0
	optics_wrong = 0
	optics_cases = {}
	lead_advisor_id = ""
	advisor_selected_turn = -1
	advisor_defections = 0
	region_crises = 0
	_round_start = _metric_snapshot()


func choose_doctrine(id: String) -> Dictionary:
	if not doctrine.is_empty() or turn != 0:
		return {"ok": false, "reason": "DOKTRIN BEREITS GESETZT"}
	var entry := _content.get_entry("doctrines", id)
	if entry.is_empty():
		return {"ok": false, "reason": "UNBEKANNTE DOKTRIN"}
	doctrine = id
	_apply_effects(entry.get("effects", {}))
	_clamp_all()
	_round_start = _metric_snapshot()
	_add_history("1962 · DOKTRIN: %s" % str(entry.get("title", id)))
	return {"ok": true, "reason": "", "title": str(entry.get("title", id))}


func doctrine_info() -> Dictionary:
	return _content.get_entry("doctrines", doctrine)


func doctrine_catalog() -> Array[Dictionary]:
	return _content.all("doctrines")


func year() -> int:
	return Timeline.year_at(turn)


func period_id() -> String:
	return Timeline.id_at(turn)


func period_label() -> String:
	return Timeline.label_at(turn)


func next_period_label() -> String:
	return Timeline.label_at(turn + 1)


func phase() -> String:
	var current := year()
	if current <= 1973:
		return "ENTDECKUNG"
	if current <= 1993:
		return "KONSOLIDIERUNG"
	if current <= 2013:
		return "WELTKONTROLLE"
	if current <= 2028:
		return "OFFENLEGUNGSDRUCK"
	if current <= 2032:
		return "NICHT MEHR VERBERGBAR"
	if current == 2033:
		return "ELEKTRISCHE ESKALATION"
	return "KATASTROPHENFENSTER"


func progress() -> float:
	return clampf(float(turn) / float(TOTAL_ROUNDS), 0.0, 1.0)


func control_index() -> float:
	return clampf(coalition * 0.25 + media * 0.25 + science * 0.15 + stability * 0.35, 0.0, 100.0)


func temperature_anomaly() -> float:
	return maxf(0.2, 0.35 + induction * 0.035 - particles * 0.012 - routes * 0.002)


func actions_for(section: String) -> Array[String]:
	var out: Array[String] = []
	for raw_id: Variant in ACTIONS:
		var id := str(raw_id)
		if str((ACTIONS[id] as Dictionary).get("section", "")) == section:
			out.append(id)
	return out


func action_info(id: String) -> Dictionary:
	var info := (ACTIONS.get(id, {}) as Dictionary).duplicate(true)
	if not info.is_empty():
		info["unlock_year"] = _action_unlock_year(id, str(info.get("section", "")))
		info["advisor_factor"] = advisor_effectiveness(str(info.get("section", "")))
	return info


func can_apply(id: String) -> Dictionary:
	if ended:
		return {"ok": false, "reason": "KAMPAGNE BEENDET"}
	if doctrine.is_empty():
		return {"ok": false, "reason": "DOKTRIN WAEHLEN"}
	if not pending_event.is_empty():
		return {"ok": false, "reason": "EREIGNIS ENTSCHEIDEN"}
	if commands_left <= 0:
		return {"ok": false, "reason": Loc.t("game.code_red_model.keine_befehle_uebrig", "KEINE BEFEHLE UEBRIG")}
	var info: Dictionary = ACTIONS.get(id, {})
	if info.is_empty():
		return {"ok": false, "reason": "UNBEKANNTER BEFEHL"}
	var unlock_year := _action_unlock_year(id, str(info.get("section", "")))
	if year() < unlock_year:
		return {"ok": false, "reason": "AB %d VERFUEGBAR" % unlock_year}
	var cost := -float(info.get("budget", 0.0))
	if cost > 0.0 and budget + 0.001 < cost:
		return {"ok": false, "reason": "BUDGET FEHLT"}
	if int(cooldowns.get(id, 0)) > 0:
		return {"ok": false, "reason": "SPERRE %dQ" % int(cooldowns[id])}
	return {"ok": true, "reason": ""}


func apply_action(id: String, region_id := "") -> Dictionary:
	var gate := can_apply(id)
	if not bool(gate.get("ok", false)):
		return gate
	var info: Dictionary = ACTIONS[id]
	budget += float(info.get("budget", 0.0))
	var section := str(info.get("section", ""))
	_apply_scaled_effects(info.get("effects", {}), advisor_effectiveness(section))
	if info.has("set_explanation"):
		explanation = str(info["set_explanation"])
		explanation_uses[explanation] = int(explanation_uses.get(explanation, 0)) + 1
		var repetition := maxi(0, int(explanation_uses[explanation]) - 2)
		if repetition > 0:
			credibility -= float(repetition) * 2.0
			truth += float(repetition)
	var risk := str(info.get("risk", ""))
	var advisor := advisor_for_section(section)
	var loyalty_risk := maxf(0.0, 55.0 - float(advisor.get("loyalty", 55.0))) * 0.006
	var doctrine_risk := float(doctrine_info().get("risk_bias", 0.0))
	var base_risk := 0.20 if risk == "leak" else (0.24 if risk == "streisand" else 0.16)
	if risk != "" and _risk_roll(id) < base_risk + loyalty_risk + doctrine_risk:
		truth += 12.0 if risk == "streisand" else (8.0 if risk == "leak" else 10.0)
		panic += 2.0
		if risk == "streisand":
			credibility -= 5.0
			_change_opponent("press", 8.0)
		_add_history("RISIKO EINGETRETEN · %s" % str(info.get("title", id)))
	var cooldown := int(info.get("cooldown", 0))
	if cooldown > 0:
		cooldowns[id] = cooldown
	commands_left -= 1
	action_counts[id] = int(action_counts.get(id, 0)) + 1
	_apply_region_action(section, id, region_id)
	_update_advisor(section, id)
	_clamp_all()
	_add_history("%d · %s" % [year(), str(info.get("title", id))])
	return {"ok": true, "reason": "", "title": str(info.get("title", id))}


func advisor_for_section(section: String) -> Dictionary:
	var target := "media" if section == "moderation" else section
	for raw: Variant in advisors.values():
		var entry: Dictionary = raw
		if str(entry.get("section", "")) == target:
			return entry
	return {}


func advisor_effectiveness(section: String) -> float:
	var entry := advisor_for_section(section)
	if entry.is_empty():
		return 1.0
	if str(entry.get("status", "ACTIVE")) == "DEFECTED":
		return 0.68
	var lead_bonus := 0.12 if str(entry.get("id", "")) == lead_advisor_id else 0.0
	return clampf(0.68 + float(entry.get("competence", 50.0)) * 0.005 + lead_bonus, 0.72, 1.34)


func advisor_catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in advisors.values():
		out.append((raw as Dictionary).duplicate(true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", "")))
	return out


func appoint_advisor(id: String) -> Dictionary:
	if ended or doctrine.is_empty() or not pending_event.is_empty():
		return {"ok": false, "reason": Loc.t("game.code_red_model.kabinett_nicht_verfuegbar", "KABINETT NICHT VERFUEGBAR")}
	if not advisors.has(id):
		return {"ok": false, "reason": "UNBEKANNTER BERATER"}
	var entry: Dictionary = advisors[id]
	if str(entry.get("status", "ACTIVE")) == "DEFECTED":
		if commands_left <= 0 or budget < 10.0:
			return {"ok": false, "reason": "INTERIM BRAUCHT 10 MRD + 1 BEFEHL"}
		budget -= 10.0
		commands_left -= 1
		entry["name"] = "INTERIM · %s" % str(entry.get("role", "RESSORT"))
		entry["competence"] = 52.0
		entry["loyalty"] = 78.0
		entry["status"] = "ACTIVE"
		entry["leak_reported"] = false
		advisors[id] = entry
		lead_advisor_id = id
		advisor_selected_turn = turn
		_add_history("%s · INTERIM ERNANNT: %s" % [period_label(), str(entry.get("role", id))])
		return {"ok": true, "reason": "", "title": "INTERIM ERNANNT"}
	if advisor_selected_turn == turn:
		return {"ok": false, "reason": "EPOCHENLEITUNG BEREITS GESETZT"}
	lead_advisor_id = id
	advisor_selected_turn = turn
	for other_id: Variant in advisors:
		var other: Dictionary = advisors[other_id]
		other["loyalty"] = clampf(float(other.get("loyalty", 50.0)) + (2.0 if str(other_id) == id else -0.4), 0.0, 100.0)
		advisors[other_id] = other
	_add_history("%s · EPOCHENLEITUNG: %s" % [period_label(), str(entry.get("name", id))])
	return {"ok": true, "reason": "", "title": "%s LEITET DIE EPOCHE" % str(entry.get("name", id))}


func advisor_recommendation(id: String) -> Dictionary:
	if not advisors.has(id):
		return {}
	var entry: Dictionary = advisors[id]
	if str(entry.get("status", "ACTIVE")) == "DEFECTED":
		return {"title": "RESSORT UNBESETZT", "detail": "Interim fuer 10 MRD und einen Befehl ernennen."}
	var section := str(entry.get("section", ""))
	var candidates := actions_for(section)
	if section == "media":
		candidates.append_array(actions_for("moderation"))
	var best_id := ""
	var best_score := -9999.0
	for action_id: String in candidates:
		var gate := can_apply(action_id)
		if not bool(gate.get("ok", false)):
			continue
		var info: Dictionary = ACTIONS[action_id]
		var effects: Dictionary = info.get("effects", {})
		var value := -float(info.get("budget", 0.0)) * 0.05
		value += -float(effects.get("truth", 0.0)) * (0.25 + truth / 100.0)
		value += -float(effects.get("panic", 0.0)) * (0.18 + panic / 120.0)
		value += float(effects.get("stability", 0.0)) * (0.15 + (100.0 - stability) / 180.0)
		if value > best_score:
			best_score = value
			best_id = action_id
	if best_id.is_empty():
		return {"title": "RESSORT BEOBACHTET", "detail": "Kein bezahlbarer Befehl verfuegbar."}
	var best: Dictionary = action_info(best_id)
	return {"id": best_id, "title": str(best.get("title", best_id)),
		"detail": str(best.get("detail", "")), "section": str(best.get("section", section))}


func all_advisors_active() -> bool:
	for raw: Variant in advisors.values():
		if str((raw as Dictionary).get("status", "ACTIVE")) == "DEFECTED":
			return false
	return true


func region_catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ["americas", "europe", "eurasia", "africa", "pacific"]:
		if regions.has(id):
			out.append((regions[id] as Dictionary).duplicate(true))
	return out


func opponent_catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in opponents.values():
		out.append((raw as Dictionary).duplicate(true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", "")))
	return out


func project_catalog() -> Array[Dictionary]:
	var out := _content.all("projects")
	for entry: Dictionary in out:
		var id := str(entry.get("id", ""))
		entry["state"] = str((projects.get(id, {}) as Dictionary).get("state", "AVAILABLE"))
		entry["progress"] = int((projects.get(id, {}) as Dictionary).get("progress", 0))
		entry["unlock_year"] = _project_unlock_year(id)
	return out


func start_project(id: String) -> Dictionary:
	if ended or not pending_event.is_empty() or commands_left <= 0:
		return {"ok": false, "reason": Loc.t("game.code_red_model.befehl_nicht_verfuegbar", "BEFEHL NICHT VERFUEGBAR")}
	if doctrine.is_empty():
		return {"ok": false, "reason": "DOKTRIN WAEHLEN"}
	var info := _content.get_entry("projects", id)
	if info.is_empty():
		return {"ok": false, "reason": "UNBEKANNTES PROJEKT"}
	if year() < _project_unlock_year(id):
		return {"ok": false, "reason": "AB %d VERFUEGBAR" % _project_unlock_year(id)}
	if projects.has(id):
		return {"ok": false, "reason": "BEREITS GESTARTET"}
	var cost := float(info.get("cost", 0.0))
	if budget < cost:
		return {"ok": false, "reason": "BUDGET FEHLT"}
	budget -= cost
	commands_left -= 1
	projects[id] = {"state": "ACTIVE", "progress": 0,
		"duration": int(info.get("duration", 1)), "title": str(info.get("title", id))}
	_add_history("%d · PROJEKTSTART: %s" % [year(), str(info.get("title", id))])
	return {"ok": true, "reason": "", "title": str(info.get("title", id))}


func current_optics() -> Dictionary:
	var catalog := _content.all("optics_scenarios")
	if catalog.is_empty():
		return {}
	return catalog[posmod(operation_seed + turn * 7, catalog.size())].duplicate(true)


func can_resolve_optics() -> bool:
	return not ended and doctrine != "" and pending_event.is_empty() \
		and commands_left > 0 and optics_done_turn != turn and year() >= 1973


func resolve_optics(choice_id: String) -> Dictionary:
	if not can_resolve_optics():
		return {"ok": false, "reason": Loc.t("game.code_red_model.optiklabor_nicht_verfuegbar", "OPTIKLABOR NICHT VERFUEGBAR")}
	var scenario := current_optics()
	for raw: Variant in scenario.get("choices", []):
		var choice: Dictionary = raw
		if str(choice.get("id", "")) != choice_id:
			continue
		credibility += float(choice.get("credibility", 0.0))
		truth += float(choice.get("truth", 0.0))
		media += 2.0 if choice_id == str(scenario.get("correct", "")) else -1.0
		commands_left -= 1
		optics_done_turn = turn
		var scenario_id := str(scenario.get("id", ""))
		var correct := choice_id == str(scenario.get("correct", ""))
		if not optics_cases.has(scenario_id):
			optics_cases[scenario_id] = correct
			if correct:
				optics_correct += 1
			else:
				optics_wrong += 1
		_clamp_all()
		_add_history("%d · OPTIK: %s / %s" % [year(), str(scenario.get("title", "")), str(choice.get("title", ""))])
		return {"ok": true, "reason": "", "correct": correct}
	return {"ok": false, "reason": "UNBEKANNTE ERKLAERUNG"}


func estimate(metric: String) -> Dictionary:
	var value := float(status_snapshot().get(metric, 0.0))
	var uncertainty := clampf(20.0 - science * 0.13, 3.0, 18.0)
	if str((projects.get("sensor_mesh", {}) as Dictionary).get("state", "")) == "COMPLETE":
		uncertainty *= 0.5
	return {"value": value, "low": maxf(0.0, value - uncertainty),
		"high": minf(100.0, value + uncertainty), "uncertainty": uncertainty}


func historical_sky_catalog() -> Array[Dictionary]:
	return _content.all("historical_sky")


func historical_sky_entry(id: String) -> Dictionary:
	return _content.get_entry("historical_sky", id)


func sky_event_for_period(target_period := "") -> Dictionary:
	var wanted := period_id() if target_period.is_empty() else target_period
	for entry: Dictionary in _content.all("sky_events"):
		if str(entry.get("period", "")) == wanted:
			return entry.duplicate(true)
	return {}


func electric_universe_snapshot() -> Dictionary:
	var stage := 0
	if plasma_load >= 18.0:
		stage = 1
	if plasma_load >= 38.0:
		stage = 2
	if plasma_load >= 64.0:
		stage = 3
	if plasma_load >= 82.0:
		stage = 4
	return {"stage": stage, "plasma_load": plasma_load, "induction": induction,
		"coupling": clampf(planet * 0.54 + induction * 0.32 + plasma_load * 0.48, 0.0, 100.0),
		"label": ["RUHEND", "FILAMENTE", "BIRKELAND-STROEME", "Z-PINCH", "ENTLADUNG"][stage]}


func completed_project_count() -> int:
	var count := 0
	for raw: Variant in projects.values():
		if str((raw as Dictionary).get("state", "")) == "COMPLETE":
			count += 1
	return count


func all_optics_solved_correctly() -> bool:
	return optics_wrong == 0 and optics_cases.size() >= _content.all("optics_scenarios").size()


func public_signal_for_year(target_year := -1) -> Dictionary:
	var current_year := year() if target_year < 0 else target_year
	var best: Dictionary = {}
	for signal_entry: Dictionary in _content.all("public_signals"):
		var signal_year := int(signal_entry.get("year", 0))
		if signal_year <= current_year and (best.is_empty() or signal_year > int(best.get("year", 0))):
			best = signal_entry
	return best.duplicate(true)


func end_year() -> Dictionary:
	if ended:
		return {"ok": false, "reason": "KAMPAGNE BEENDET"}
	if not pending_event.is_empty():
		return {"ok": false, "reason": "EREIGNIS ENTSCHEIDEN"}
	# Harte Kontrollverlust-Grenzen gelten sofort; ein bereits offengelegtes
	# Objekt darf nicht durch die normale Jahresformel wieder unter 100 % fallen.
	_clamp_all()
	_check_ending()
	if ended:
		return {"ok": true, "reason": "", "ended": true, "event": false}
	var before := _metric_snapshot()
	_tick_cooldowns()
	_tick_projects()
	var old_year := year()
	var old_period := period_label()
	var step_scale := Timeline.scale_at(turn)
	var next_progress := clampf(float(turn + 1) / float(TOTAL_ROUNDS), 0.0, 1.0)
	planet = maxf(planet, 8.0 + 91.0 * pow(next_progress, 1.52))
	var shielding := particles * 0.038 + routes * 0.012
	induction += (0.65 + planet * (0.010 + next_progress * 0.018) - shielding) * step_scale
	induction = maxf(0.0, induction)
	var faraday_complete := str((projects.get("faraday_grid", {}) as Dictionary).get("state", "")) == "COMPLETE"
	var electrical_gain := maxf(0.0, planet - 28.0) * 0.030 + induction * 0.020
	if old_year >= 2030:
		electrical_gain += 1.3
	plasma_load += electrical_gain * step_scale - (1.5 * step_scale if faraday_complete else 0.0)
	var temp := temperature_anomaly()
	var visible_pressure := planet * 0.026 + maxf(0.0, induction - 35.0) * 0.055 + particles * 0.012
	truth += (visible_pressure - media * 0.025 - science * 0.014) * step_scale
	if old_year >= 2030:
		# Ab 2030 ist die Erscheinung weltweit visuell vergleichbar. Selbst sehr
		# hohe Medienkontrolle kann die physische Evidenz nur noch abbremsen.
		truth += (4.5 + planet * 0.035) * step_scale * 0.52
		credibility -= (2.0 + planet * 0.012) * step_scale * 0.58
	panic += (temp * 0.82 + truth * 0.010 + planet * 0.018 - media * 0.021
		+ plasma_load * 0.012) * step_scale
	stability += (coalition * 0.012 - panic * 0.030 - burden * 0.016
		- maxf(0.0, plasma_load - 40.0) * 0.008) * step_scale
	coalition += (stability * 0.006 - truth * 0.014 - 0.35) * step_scale
	budget -= (1.5 + particles * 0.055 + elite_escape * 0.018) * step_scale
	burden += (0.35 + maxf(0.0, temp - 1.5) * 0.30) * step_scale
	if budget < 0.0:
		stability += budget * 0.20
		coalition += budget * 0.10
		panic += absf(budget) * 0.08
		budget = 0.0
	_tick_regions(temp, step_scale)
	_tick_opponents(old_year, step_scale)
	_tick_advisors(step_scale)
	turn += 1
	commands_left = COMMANDS_PER_ROUND
	_clamp_all()
	_add_history("%s · T+%.1f · PLASMA %.1f · SICHTBAR %.1f%%" % [old_period, temp, plasma_load, truth])
	last_debrief = _make_debrief(old_year, before, _metric_snapshot())
	last_debrief["period"] = old_period
	last_debrief["next_period"] = period_label()
	_check_ending()
	if not ended:
		pending_event = _build_event(turn - 1)
	_round_start = _metric_snapshot()
	return {"ok": true, "reason": "", "ended": ended, "event": not pending_event.is_empty()}


func resolve_event(choice_index: int) -> Dictionary:
	if pending_event.is_empty():
		return {"ok": false, "reason": Loc.t("game.code_red_model.kein_ereignis", "KEIN EREIGNIS")}
	var choices: Array = pending_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return {"ok": false, "reason": "UNGUELTIGE WAHL"}
	var choice: Dictionary = choices[choice_index]
	var cost := -float(choice.get("budget", 0.0))
	if cost > 0.0 and budget + 0.001 < cost:
		return {"ok": false, "reason": "BUDGET FEHLT"}
	budget += float(choice.get("budget", 0.0))
	_apply_effects(choice.get("effects", {}))
	var event_id := str(pending_event.get("id", ""))
	if bool(pending_event.get("sky_event", false)):
		var discharge := float(pending_event.get("plasma", 0.0))
		plasma_load += discharge * 0.35
		induction += discharge * 0.10
	event_flags["%s_%d" % [event_id, choice_index]] = true
	if str(pending_event.get("opponent", "")) != "":
		var opponent_delta := -3.0 if choice_index == 0 else -6.0
		_change_opponent(str(pending_event.get("opponent", "")), opponent_delta)
	_add_history("%s · %s: %s" % [period_label(), str(pending_event.get("title", "EREIGNIS")), str(choice.get("title", "WAHL"))])
	pending_event = {}
	_clamp_all()
	_check_ending()
	return {"ok": true, "reason": "", "ended": ended}


func score() -> int:
	return Reports.score(self)


func rank() -> String:
	return Reports.rank(self)


func ending_text() -> String:
	return Reports.ending_text(self)


func orbit_snapshot(public_view := false) -> Dictionary:
	return Reports.orbit_snapshot(self, public_view)


func status_snapshot() -> Dictionary:
	return Reports.status_snapshot(self)


func to_dict() -> Dictionary: return StateCodec.encode(self, SAVE_VERSION)

func from_dict(raw: Variant) -> bool: return StateCodec.decode(self, raw, SAVE_VERSION, TOTAL_ROUNDS, COMMANDS_PER_ROUND)


func _apply_effects(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	for key: Variant in raw:
		var property := str(key)
		if property in ["budget", "coalition", "media", "science", "stability", "panic", "truth",
				"burden", "particles", "routes", "elite_escape", "planet", "induction",
				"plasma_load", "credibility"]:
			set(property, float(get(property)) + float((raw as Dictionary)[key]))


func _apply_scaled_effects(raw: Variant, factor: float) -> void:
	if not raw is Dictionary:
		return
	var scaled: Dictionary = {}
	for key: Variant in raw:
		var value := float((raw as Dictionary)[key])
		# Kompetenz verstaerkt gewollte Verbesserungen, also auch die Senkung
		# negativer Lagewerte. Echte Nachteile wie Stabilitaetsverlust bleiben voll.
		var beneficial_reduction := value < 0.0 and str(key) in ["truth", "panic", "burden", "induction", "plasma_load"]
		scaled[key] = value * factor if value > 0.0 or beneficial_reduction else value
	_apply_effects(scaled)


func _metric_snapshot() -> Dictionary: return StateCodec.metric_snapshot(self)


func _apply_region_action(section: String, _id: String, region_id: String) -> void:
	if regions.is_empty():
		return
	var chosen := region_id
	if chosen.is_empty() or not regions.has(chosen):
		var ids: Array = regions.keys()
		ids.sort()
		chosen = str(ids[posmod(operation_seed + turn + commands_left, ids.size())])
	var region: Dictionary = regions[chosen]
	match section:
		"media", "moderation":
			region["trust"] = float(region.get("trust", 50.0)) + (2.0 if section == "media" else -0.5)
			region["exposure"] = float(region.get("exposure", 10.0)) - 3.0
		"science":
			region["exposure"] = float(region.get("exposure", 10.0)) - 2.0
		"geo":
			region["panic"] = float(region.get("panic", 10.0)) - 1.5
			region["exposure"] = float(region.get("exposure", 10.0)) + 0.5
		"economy":
			region["trust"] = float(region.get("trust", 50.0)) + 1.5
		"summit":
			region["trust"] = float(region.get("trust", 50.0)) + 1.0
	_clamp_region(region)
	regions[chosen] = region


func _update_advisor(section: String, id: String) -> void:
	for advisor_id: Variant in advisors:
		var entry: Dictionary = advisors[advisor_id]
		if str(entry.get("section", "")) != section:
			continue
		entry["competence"] = float(entry.get("competence", 50.0)) + 0.35
		entry["loyalty"] = float(entry.get("loyalty", 50.0)) \
			+ (-1.0 if id in ["suppress_astronomy", "platform_ban", "network_seizure"] else 0.25)
		entry["competence"] = clampf(float(entry["competence"]), 0.0, 100.0)
		entry["loyalty"] = clampf(float(entry["loyalty"]), 0.0, 100.0)
		advisors[advisor_id] = entry
		return


func _tick_projects() -> void:
	for id: Variant in projects.keys():
		var state: Dictionary = projects[id]
		if str(state.get("state", "")) != "ACTIVE":
			continue
		var advance := 1 + (int(doctrine_info().get("project_speed", 0)) if turn % 3 == 2 else 0)
		state["progress"] = int(state.get("progress", 0)) + advance
		if int(state["progress"]) >= int(state.get("duration", 1)):
			state["state"] = "COMPLETE"
			var info := _content.get_entry("projects", str(id))
			_apply_effects(info.get("effects", {}))
			_add_history("%d · PROJEKT FERTIG: %s" % [year(), str(state.get("title", id))])
		projects[id] = state


func _tick_regions(temp: float, step_scale: float) -> void:
	var panic_sum := 0.0
	var trust_sum := 0.0
	for id: Variant in regions:
		var region: Dictionary = regions[id]
		var heat := float(region.get("heat_factor", 1.0))
		var media_reach := float(region.get("media_factor", 1.0))
		region["panic"] = float(region.get("panic", 0.0)) + (temp * heat * 0.7 \
			+ truth * 0.014 + plasma_load * 0.008 - media * media_reach * 0.012) * step_scale
		region["exposure"] = float(region.get("exposure", 0.0)) + (planet * 0.018 \
			+ plasma_load * 0.010 - particles * 0.009) * step_scale
		region["trust"] = float(region.get("trust", 50.0)) + (credibility * 0.008 \
			- burden * 0.010 - float(region["exposure"]) * 0.006) * step_scale
		_clamp_region(region)
		if not bool(region.get("crisis_reported", false)) \
				and (float(region["panic"]) >= 75.0 or float(region["exposure"]) >= 82.0):
			region["crisis_reported"] = true
			region_crises += 1
		regions[id] = region
		panic_sum += float(region["panic"])
		trust_sum += float(region["trust"])
	if not regions.is_empty():
		panic = lerpf(panic, panic_sum / regions.size(), 0.18)
		stability = lerpf(stability, trust_sum / regions.size(), 0.08)


func _tick_opponents(round_year: int, step_scale: float) -> void:
	var pressure_sum := 0.0
	for id: Variant in opponents:
		var entry: Dictionary = opponents[id]
		var growth := float(entry.get("growth", 1.0))
		var late_multiplier := 1.0 + maxf(0.0, float(round_year - 2025)) * 0.08
		entry["pressure"] = float(entry.get("pressure", 0.0)) + (growth * late_multiplier \
			+ planet * 0.008 + plasma_load * 0.006 - science * 0.005) * step_scale
		entry["pressure"] = clampf(float(entry["pressure"]), 0.0, 100.0)
		opponents[id] = entry
		pressure_sum += float(entry["pressure"])
	if not opponents.is_empty():
		truth += pressure_sum / opponents.size() * 0.025 * step_scale


func _tick_advisors(step_scale: float) -> void:
	for id: Variant in advisors:
		var entry: Dictionary = advisors[id]
		if str(entry.get("status", "ACTIVE")) == "DEFECTED":
			continue
		entry["loyalty"] = float(entry.get("loyalty", 50.0)) \
			+ (-panic * 0.006 - truth * 0.004 + coalition * 0.003) * step_scale
		entry["loyalty"] = clampf(float(entry["loyalty"]), 0.0, 100.0)
		if float(entry["loyalty"]) < 15.0:
			entry["status"] = "DEFECTED"
			entry["leak_reported"] = true
			truth += 9.0
			panic += 3.0
			advisor_defections += 1
			if lead_advisor_id == str(id):
				lead_advisor_id = ""
			_add_history("BERATER DEFEKTIERT · %s" % str(entry.get("name", id)))
		elif float(entry["loyalty"]) < 28.0 and not bool(entry.get("leak_reported", false)) \
				and _risk_roll("advisor_%s" % str(id)) < 0.18:
			truth += 5.0
			entry["leak_reported"] = true
			_add_history("BERATERLECK · %s" % str(entry.get("name", id)))
		advisors[id] = entry


func _build_event(index: int) -> Dictionary:
	var incoming_year := year()
	var sky_event := sky_event_for_period()
	if not sky_event.is_empty():
		var archive := historical_sky_entry(str(sky_event.get("archive_ref", "")))
		var event := sky_event.duplicate(true)
		event["sky_event"] = true
		event["archive_title"] = str(archive.get("title", ""))
		event["archive_status"] = str(archive.get("status", ""))
		event["opponent"] = "observatories"
		return event
	for signal_entry: Dictionary in _content.all("public_signals"):
		if int(signal_entry.get("year", -1)) == incoming_year:
			var pressure := float(signal_entry.get("pressure", 8.0))
			return {
				"id": str(signal_entry.get("id", "public_signal")),
				"title": str(signal_entry.get("title", "OEFFENTLICHES SIGNAL")),
				"text": "%s · %s" % [str(signal_entry.get("source", "OEFFENTLICH")), str(signal_entry.get("text", ""))],
				"opponent": str(signal_entry.get("opponent", "press")),
				"choices": [
					{"title": "BEOBACHTEN UND KARTIEREN", "effects": {"science": 4.0, "truth": pressure * 0.30}},
					{"title": "GEGENNARRATIV STARTEN", "budget": -5.0,
						"effects": {"media": 5.0, "truth": -pressure * 0.24, "credibility": -1.0}},
				],
			}
	var base := EventCatalog.ALL[posmod(index + operation_seed, EventCatalog.ALL.size())].duplicate(true)
	if incoming_year >= 2030:
		base["text"] = str(base.get("text", "")) + " Unabhaengige Aufnahmen sind bereits gespiegelt."
		base["art"] = "plasma" if plasma_load >= 48.0 else "strange_sky"
	return base


func _make_debrief(old_year: int, before: Dictionary, after: Dictionary) -> Dictionary:
	var biggest := "truth"
	var biggest_delta := 0.0
	for key: String in ["truth", "panic", "coalition", "stability", "credibility", "induction", "plasma_load"]:
		var delta := float(after.get(key, 0.0)) - float(before.get(key, 0.0))
		if absf(delta) > absf(biggest_delta):
			biggest = key
			biggest_delta = delta
	var signal_entry := public_signal_for_year(old_year)
	var headline := "LAGEBLEIBT UNTER KONTROLLE"
	if plasma_load > 70.0:
		headline = "PLASMAFILAMENTE UEBER MEHREREN KONTINENTEN"
	elif truth > 60.0:
		headline = "UNABHAENGIGE AUFNAHMEN VERBREITEN SICH"
	elif panic > 45.0:
		headline = "UNRUHE NACH HIMMELSPHAENOMEN"
	elif not signal_entry.is_empty() and int(signal_entry.get("year", 0)) == old_year:
		headline = str(signal_entry.get("title", headline))
	return {"year": old_year, "next_year": year(), "headline": headline,
		"largest_metric": biggest, "largest_delta": biggest_delta,
		"truth_delta": float(after.get("truth", 0.0)) - float(before.get("truth", 0.0)),
		"panic_delta": float(after.get("panic", 0.0)) - float(before.get("panic", 0.0))}


func _change_opponent(id: String, delta: float) -> void:
	if not opponents.has(id):
		return
	var entry: Dictionary = opponents[id]
	entry["pressure"] = clampf(float(entry.get("pressure", 0.0)) + delta, 0.0, 100.0)
	opponents[id] = entry


func _clamp_region(region: Dictionary) -> void:
	for key: String in ["panic", "trust", "exposure"]:
		region[key] = clampf(float(region.get(key, 0.0)), 0.0, 100.0)


func _project_unlock_year(id: String) -> int:
	match id:
		"sensor_mesh": return 1965
		"archive_firewall": return 1978
		"aerosol_fleet": return 1983
		"ark_bunkers": return 1998
		"orbital_mirror": return 2017
		"faraday_grid": return 2028
		_: return DISCOVERY_YEAR


func _risk_roll(id: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = operation_seed ^ (turn * 2_654_435_761) ^ id.hash() ^ (int(action_counts.get(id, 0)) * 97)
	return rng.randf()


func _tick_cooldowns() -> void:
	var next: Dictionary = {}
	for id: Variant in cooldowns:
		var left := int(cooldowns[id]) - 1
		if left > 0:
			next[id] = left
	cooldowns = next


func _check_ending() -> void:
	if truth >= 99.5 or panic >= 99.5 or stability <= 0.5 or coalition <= 0.5:
		ended = true
		ending = "chaos"
		return
	if turn < TOTAL_ROUNDS:
		return
	ended = true
	if truth <= 22.0 and panic <= 38.0 and coalition >= 52.0 \
			and stability >= 42.0 and elite_escape >= 45.0:
		ending = "victory"
	elif truth < 76.0 and stability > 16.0 and coalition > 20.0 and elite_escape >= 20.0:
		ending = "mixed"
	else:
		ending = "chaos"


func _clamp_all() -> void:
	budget = clampf(budget, 0.0, 999.0)
	coalition = clampf(coalition, 0.0, 100.0)
	media = clampf(media, 0.0, 100.0)
	science = clampf(science, 0.0, 100.0)
	stability = clampf(stability, 0.0, 100.0)
	panic = clampf(panic, 0.0, 100.0)
	truth = clampf(truth, 0.0, 100.0)
	burden = clampf(burden, 0.0, 100.0)
	particles = clampf(particles, 0.0, 100.0)
	routes = clampf(routes, 0.0, 100.0)
	elite_escape = clampf(elite_escape, 0.0, 100.0)
	planet = clampf(planet, 0.0, 100.0)
	induction = clampf(induction, 0.0, 100.0)
	plasma_load = clampf(plasma_load, 0.0, 100.0)
	credibility = clampf(credibility, 0.0, 100.0)
	for id: Variant in regions:
		var region: Dictionary = regions[id]
		_clamp_region(region)
		regions[id] = region


func _add_history(line: String) -> void:
	history.append(line.substr(0, 120))
	if history.size() > 32:
		history.pop_front()


func _action_unlock_year(id: String, section: String) -> int:
	if id == "bunker":
		return 1998
	if id == "carbon_tax":
		return 2003
	if id == "manufactured_crisis":
		return 1998
	if id == "alter_satellite":
		return 1983
	if id == "agency_report":
		return 1978
	if id == "shadow_limit":
		return 1998
	if id == "platform_ban":
		return 2000
	if id == "network_seizure":
		return 2008
	match section:
		"media": return 1973
		"moderation": return 1976
		"geo": return 1978
		"economy": return 1988
		_: return DISCOVERY_YEAR
