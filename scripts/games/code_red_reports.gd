class_name CodeRedReports
extends RefCounted
## Read-only Auswertungen fuer UI, Save-Diagnose und Operationsabschluss.

const CATASTROPHE_WINDOW := "JULI/AUGUST 2034"


static func score(model) -> int:
	var value: float = (100.0 - model.truth) * 310.0 + (100.0 - model.panic) * 170.0
	value += model.coalition * 130.0 + model.science * 80.0 + model.media * 100.0
	value += model.stability * 150.0 + model.elite_escape * 95.0 + float(model.turn) * 250.0
	value -= model.burden * 45.0
	return maxi(0, roundi(value))


static func rank(model) -> String:
	var value := score(model)
	if model.ending == "victory" and value >= 70_000:
		return "SCHATTENARCHITEKT"
	if model.ending == "victory":
		return "KOORDINATOR"
	if model.ending == "mixed":
		return "ZEITKAEUFER"
	return "GESTUERZTER VERWALTER"


static func ending_text(model) -> String:
	match model.ending:
		"victory":
			return "Die Menschheit hat nichts bemerkt.\nDie Elite ist in den Bunkern und auf dem Weg zu neuen Welten.\nDu hast die groesste Luege der Geschichte erfolgreich verteidigt."
		"mixed":
			return "Der Zerstoerer kommt naeher.\nEin Teil der Wahrheit sickerte durch.\nDu hast Zeit erkauft - aber nicht fuer alle."
		_:
			return "Der Himmel konnte nicht laenger versteckt werden.\nDie Menschen haben die Wahrheit gesehen.\nDeine Herrschaft ist beendet."


static func orbit_snapshot(model, public_view: bool) -> Dictionary:
	var p: float = model.progress()
	var distance_au: float = lerpf(8.4, 0.17, pow(p, 1.32))
	var apparent: float = lerpf(0.02, 31.0, pow(p, 2.15))
	var confidence: float = clampf(model.science * 0.82 + (18.0 if model.projects.has("sensor_mesh")
		else 0.0), 12.0, 99.0)
	if public_view:
		return {"designation": "KEIN BESTAETIGTES OBJEKT", "distance_au": 0.0,
			"apparent_deg": 0.0, "periapsis": "KEINE GEFAHR", "confidence": model.credibility,
			"note": "HALO-/NEBENSONNEN-DATEN WERDEN METEOROLOGISCH ERKLAERT"}
	var electric: Dictionary = model.electric_universe_snapshot()
	return {"designation": "OBJEKT R-62 / CODE RED", "distance_au": distance_au,
		"apparent_deg": apparent, "periapsis": CATASTROPHE_WINDOW, "confidence": confidence,
		"inclination": 17.4, "eccentricity": 0.982,
		"electrical_coupling": electric.get("coupling", 0.0),
		"plasma_stage": electric.get("label", "RUHEND"),
		"note": "FIKTIVE GEHEIMMESSUNG · BAHNLOESUNG %s" % (
			"STABIL" if confidence >= 70.0 else "UNSICHER")}


static func status_snapshot(model) -> Dictionary:
	return {"year": model.year(), "phase": model.phase(), "turn": model.turn,
		"progress": model.progress(), "commands": model.commands_left, "budget": model.budget,
		"coalition": model.coalition, "media": model.media, "science": model.science,
		"stability": model.stability, "panic": model.panic, "truth": model.truth,
		"burden": model.burden, "particles": model.particles, "routes": model.routes,
		"elite_escape": model.elite_escape, "planet": model.planet, "induction": model.induction,
		"plasma_load": model.plasma_load, "temperature": model.temperature_anomaly(),
		"control": model.control_index(), "explanation": model.explanation, "ended": model.ended,
		"ending": model.ending, "score": score(model), "rank": rank(model),
		"doctrine": model.doctrine, "credibility": model.credibility,
		"regions": model.regions.duplicate(true), "advisors": model.advisors.duplicate(true),
		"opponents": model.opponents.duplicate(true), "projects": model.projects.duplicate(true),
		"last_debrief": model.last_debrief.duplicate(true), "period_id": model.period_id(),
		"period_label": model.period_label(), "lead_advisor_id": model.lead_advisor_id,
		"advisor_defections": model.advisor_defections, "region_crises": model.region_crises,
		"optics_correct": model.optics_correct, "optics_wrong": model.optics_wrong,
		"electric_universe": model.electric_universe_snapshot(),
		"public_signal": model.public_signal_for_year(), "orbit": orbit_snapshot(model, false)}
