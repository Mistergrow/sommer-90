class_name QuestAuditService
extends RefCounted
## Read-only-Diagnose fuer Aktivierungs- und Stufenbedingungen. Das Modul darf
## Questzustand erklaeren, aber niemals aktivieren, belohnen oder speichern.


static func activation(id: String, q: Dictionary, slot: Dictionary, slot_open: bool,
		is_done: bool, is_active: bool, localized_title: String) -> Dictionary:
	if q.is_empty():
		return {"id": id, "exists": false, "state": "missing", "eligible": false, "checks": []}
	var checks: Array = [{"kind": "campaign_slot", "ok": slot_open, "required": slot,
		"actual": TimeManager.campaign_progress()}]
	var prereq: Dictionary = q.get("prereq", {})
	if prereq.has("year_min"):
		checks.append({"kind": "year_min", "ok": TimeManager.year >= int(prereq["year_min"]),
			"required": int(prereq["year_min"]), "actual": TimeManager.year})
	if prereq.has("year_max"):
		checks.append({"kind": "year_max", "ok": TimeManager.year <= int(prereq["year_max"]),
			"required": int(prereq["year_max"]), "actual": TimeManager.year})
	if prereq.has("age_min"):
		checks.append({"kind": "age_min", "ok": PlayerIdentity.age() >= int(prereq["age_min"]),
			"required": int(prereq["age_min"]), "actual": PlayerIdentity.age()})
	if prereq.has("flag"):
		var flag_name := str(prereq["flag"])
		checks.append({"kind": "flag", "id": flag_name,
			"ok": bool(GameManager.flags.get(flag_name, false)), "required": true,
			"actual": GameManager.flags.get(flag_name, false)})
	if prereq.has("not_flag"):
		var flag_name := str(prereq["not_flag"])
		checks.append({"kind": "not_flag", "id": flag_name,
			"ok": not bool(GameManager.flags.get(flag_name, false)), "required": false,
			"actual": GameManager.flags.get(flag_name, false)})
	for fact: Variant in prereq.get("needs", []):
		checks.append({"kind": "fact", "id": str(fact),
			"ok": NarrativeManager.fact_true(str(fact)), "required": true,
			"actual": NarrativeManager.fact_true(str(fact))})
	var eligible := checks.all(func(check: Dictionary) -> bool: return bool(check.get("ok", false)))
	var state := "eligible" if eligible else "locked"
	if is_done:
		state = "done"
	elif is_active:
		state = "active"
	return {"id": id, "exists": true, "title": localized_title, "state": state,
		"eligible": eligible, "checks": checks, "campaign_slot": slot}


static func current_stage(id: String, q: Dictionary, stage_index: int, done: bool,
		description: String, checks: Array) -> Dictionary:
	if q.is_empty():
		return {"id": id, "exists": false, "met": false, "checks": []}
	var stages: Array = q.get("stages", [])
	if stage_index < 0 or stage_index >= stages.size():
		return {"id": id, "exists": true, "stage": stage_index, "met": done, "checks": []}
	var stage_def: Dictionary = stages[stage_index]
	return {"id": id, "exists": true, "stage": stage_index, "description": description,
		"goal": (stage_def.get("goal", {}) as Dictionary).duplicate(true),
		"met": checks.all(func(check: Dictionary) -> bool: return bool(check.get("ok", false))),
		"checks": checks}
