class_name QuestPresentationService
extends RefCounted
## Baut fluechtige HUD-Ereignisse aus bereits lokalisierten Questdaten. Der
## Service besitzt keinen Save-Zustand und erfindet keine Dialogzeilen.


static func build_event(q: Dictionary, kind: String, completed_text: String,
		completed_stages: int, title_fn: Callable, stage_text_fn: Callable,
		tutorial_fn: Callable, effects_fn: Callable, authored_keys_fn: Callable) -> Dictionary:
	var qid := str(q.get("id", ""))
	var stages: Array = q.get("stages", [])
	var is_complete := kind == "completed"
	var current_index := clampi(completed_stages, 0, maxi(0, stages.size() - 1))
	var objective := ""
	if is_complete:
		objective = Loc.t("quest.presentation.all_goals_complete", "Alle Ziele dieses Auftrags sind erledigt.")
	elif current_index < stages.size():
		objective = str(stage_text_fn.call(qid, current_index))
	var giver_id := str(q.get("giver", ""))
	var giver_name := ""
	if not giver_id.is_empty():
		var npc: Dictionary = NPCManager.get_npc(giver_id)
		giver_name = str(npc.get("name", giver_id.trim_prefix("npc_").capitalize()))
	var voice_line := _voice_line(q, kind, completed_stages, effects_fn, authored_keys_fn)
	var presentation: Dictionary = (q.get("presentation", {}) as Dictionary).duplicate(true)
	var emotion := str(presentation.get("emotion", _emotion(kind, voice_line)))
	return {
		"kind": kind, "id": qid, "title": str(title_fn.call(qid)),
		"objective": objective, "completed_text": completed_text,
		"stage_index": current_index,
		"stage_number": stages.size() if is_complete else mini(current_index + 1, stages.size()),
		"completed_stages": completed_stages, "stage_count": stages.size(),
		"giver_id": giver_id, "giver_name": giver_name, "voice_line": voice_line,
		"emotion": emotion, "teaches": str(q.get("teaches", "")),
		"tutorial": bool(tutorial_fn.call(qid)),
		"family": str(q.get("quest_family", q.get("family", ""))),
		"year": TimeManager.year, "presentation": presentation,
	}


static func _voice_line(q: Dictionary, kind: String, completed_stages: int,
		effects_fn: Callable, authored_keys_fn: Callable) -> String:
	var qid := str(q.get("id", ""))
	var authored_keys := bool(authored_keys_fn.call(q))
	if kind == "started":
		return _effect_voice_line(effects_fn.call(qid, "on_start",
			q.get("on_start", []), authored_keys), false)
	var stages: Array = q.get("stages", [])
	var completed_index := clampi(completed_stages - 1, 0, maxi(0, stages.size() - 1))
	var stage_voice := ""
	if not stages.is_empty() and completed_index < stages.size():
		var stage_definition: Dictionary = stages[completed_index]
		stage_voice = _effect_voice_line(effects_fn.call(qid,
			"stages%d.reward" % completed_index,
			stage_definition.get("reward", []), authored_keys), true)
	if kind == "completed":
		var final_voice := _effect_voice_line(effects_fn.call(qid, "reward",
			q.get("reward", []), authored_keys), true)
		return final_voice if not final_voice.is_empty() else stage_voice
	return stage_voice


static func _effect_voice_line(effects: Array, reverse := false) -> String:
	var indices := range(effects.size() - 1, -1, -1) if reverse else range(effects.size())
	for index: int in indices:
		if not effects[index] is Dictionary:
			continue
		var effect: Dictionary = effects[index]
		var text := str(effect.get("text", "")).strip_edges()
		if not text.is_empty():
			return text
		var risk: Variant = effect.get("risk")
		if risk is Dictionary:
			text = _effect_voice_line((risk as Dictionary).get("effects", []), reverse)
			if not text.is_empty():
				return text
	return ""


static func _emotion(kind: String, voice_line: String) -> String:
	if kind == "completed":
		return "proud"
	if kind == "stage":
		return "thinking"
	var lower := voice_line.to_lower()
	if _contains_any(lower, ["vorsicht", "ernst", "prüfung", "pruefung",
			"noch dürfen", "noch duerfen", "aufpassen"]):
		return "nervous"
	if _contains_any(lower, ["endlich", "geschafft", "bestanden", "klasse",
			"großartig", "grossartig"]):
		return "happy"
	if _contains_any(lower, ["was?", "unglaublich", "überrasch", "ueberrasch"]):
		return "surprised"
	return "talking"


static func _contains_any(text: String, needles: Array) -> bool:
	for needle: Variant in needles:
		if str(needle) in text:
			return true
	return false
