extends RefCounted
## Verdichtet eigenstaendige Diskettenspiele fuer den Balancing-Bericht. Die
## Detaildaten bleiben lokal und enthalten nur feste Spielsystemwerte.


static func note_started(state: Dictionary, id: String, details: Dictionary) -> void:
	var entry := _entry(state, id)
	entry["starts"] = int(entry.get("starts", 0)) + 1
	entry["last_start"] = _safe_details(details)
	_store(state, id, entry)


static func note_abandoned(state: Dictionary, id: String, details: Dictionary) -> void:
	var entry := _entry(state, id)
	entry["abandons"] = int(entry.get("abandons", 0)) + 1
	entry["last_exit_period"] = str(details.get("period", "")).left(32)
	entry["last_abandon"] = _safe_details(details)
	_merge_counts(entry, "action_counts", details.get("action_counts", {}))
	_store(state, id, entry)


static func note_run(state: Dictionary, id: String, completed: bool, details: Dictionary) -> void:
	var entry := _entry(state, id)
	entry["runs"] = int(entry.get("runs", 0)) + 1
	if completed:
		entry["completions"] = int(entry.get("completions", 0)) + 1
	_increment(entry, "ending_counts", str(details.get("ending", "unknown")))
	_increment(entry, "doctrine_counts", str(details.get("doctrine", "unknown")))
	entry["advisor_defections"] = int(entry.get("advisor_defections", 0)) \
		+ int(details.get("advisor_defections", 0))
	entry["region_crises"] = int(entry.get("region_crises", 0)) + int(details.get("region_crises", 0))
	entry["last_run"] = _safe_details(details)
	_merge_counts(entry, "action_counts", details.get("action_counts", {}))
	_store(state, id, entry)


static func _entry(state: Dictionary, id: String) -> Dictionary:
	var funnels: Dictionary = state.get("game_funnels", {})
	return (funnels.get(id, {"starts": 0, "runs": 0, "completions": 0, "abandons": 0,
		"ending_counts": {}, "doctrine_counts": {}, "action_counts": {},
		"advisor_defections": 0, "region_crises": 0}) as Dictionary).duplicate(true)


static func _store(state: Dictionary, id: String, entry: Dictionary) -> void:
	var funnels: Dictionary = state.get("game_funnels", {})
	funnels[id.left(64)] = entry
	state["game_funnels"] = funnels


static func _increment(entry: Dictionary, bucket: String, id: String) -> void:
	if id.is_empty():
		return
	var counts: Dictionary = entry.get(bucket, {})
	counts[id.left(64)] = int(counts.get(id.left(64), 0)) + 1
	entry[bucket] = counts


static func _merge_counts(entry: Dictionary, bucket: String, raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var counts: Dictionary = entry.get(bucket, {})
	for key: Variant in (raw as Dictionary):
		var id := str(key).left(64)
		counts[id] = int(counts.get(id, 0)) + clampi(int((raw as Dictionary)[key]), 0, 9999)
	entry[bucket] = counts


static func _safe_details(details: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["period", "turn", "doctrine", "ending", "truth_leak", "plasma_load",
			"advisor_defections", "region_crises", "projects_complete", "optics_correct", "optics_wrong"]:
		if details.has(key):
			out[key] = details[key]
	return out
