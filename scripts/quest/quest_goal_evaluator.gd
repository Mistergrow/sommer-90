extends RefCounted
## Gemeinsame, rein lesende Auswertung einer Queststufe.
##
## Gameplay und Diagnose muessen dieselben Checks verwenden. Der QuestManager
## liefert nur seine statusabhaengigen Zaehler als Callables; Weltwerte werden
## hier gelesen, aber niemals veraendert.


static func is_met(
		goal: Dictionary,
		quest_id: String,
		action_counter: Callable,
		template_counter: Callable
) -> bool:
	return checks(goal, quest_id, action_counter, template_counter).all(
		func(check: Dictionary) -> bool: return bool(check.get("ok", false)))


static func checks(
		goal: Dictionary,
		quest_id: String,
		action_counter: Callable,
		template_counter: Callable
) -> Array:
	var result: Array = []
	if goal.is_empty():
		return [{"kind": "empty", "ok": true}]
	if bool(goal.get("manual", false)):
		result.append({"kind": "manual", "ok": false, "actual": false, "required": true})
	if goal.has("flag"):
		var flag_name := str(goal["flag"])
		var actual := bool(GameManager.flags.get(flag_name, false))
		result.append({"kind": "flag", "id": flag_name, "ok": actual,
			"actual": actual, "required": true})
	if goal.has("action"):
		var action := str(goal["action"])
		var action_required := int(goal.get("count", 1))
		var action_actual := int(action_counter.call(quest_id, action))
		result.append({"kind": "action", "id": action,
			"ok": action_actual >= action_required,
			"actual": action_actual, "required": action_required})
	if goal.has("minigame_done"):
		var minigame := str(goal["minigame_done"])
		var minigame_required := int(goal.get("count", 1))
		var minigame_actual := int(MinigameManager.record(minigame).get("wins", 0))
		result.append({"kind": "minigame_done", "id": minigame,
			"ok": minigame_actual >= minigame_required,
			"actual": minigame_actual, "required": minigame_required})
	if goal.has("creation"):
		var creation := str(goal["creation"])
		var creation_required := int(goal.get("count", 1))
		var creation_actual := (MinigameManager.creations.get(creation, []) as Array).size()
		result.append({"kind": "creation", "id": creation,
			"ok": creation_actual >= creation_required,
			"actual": creation_actual, "required": creation_required})
	if goal.has("has_template"):
		var template_id := str(goal["has_template"])
		var template_required := int(goal.get("count", 1))
		var template_actual := int(template_counter.call(goal))
		result.append({"kind": "has_template", "id": template_id,
			"ok": template_actual >= template_required,
			"actual": template_actual, "required": template_required})
	if goal.has("has_player_copy_of"):
		var software_id := str(goal["has_player_copy_of"])
		var has_copy := DiskManager.has_player_copy_of(software_id)
		result.append({"kind": "has_player_copy_of", "id": software_id,
			"ok": has_copy, "actual": has_copy, "required": true})
	if goal.has("has_item"):
		var item_id := str(goal["has_item"])
		var item_required := int(goal.get("count", 1))
		var item_actual := InventoryManager.count(item_id)
		result.append({"kind": "has_item", "id": item_id,
			"ok": item_actual >= item_required,
			"actual": item_actual, "required": item_required})
	for stat_key: String in [
		"ruf_min", "wissen_min", "money_min", "wealth_min",
		"homepage_visitors_min", "year_min", "age_min", "ram_kb_min",
	]:
		if not goal.has(stat_key):
			continue
		var stat_actual := _stat_value(stat_key)
		var stat_required := int(goal[stat_key])
		result.append({"kind": stat_key, "ok": stat_actual >= stat_required,
			"actual": stat_actual, "required": stat_required})
	if goal.has("has_hardware"):
		var hardware_id := str(goal["has_hardware"])
		var has_hardware := PlayerStats.has_hardware(hardware_id)
		result.append({"kind": "has_hardware", "id": hardware_id,
			"ok": has_hardware, "actual": has_hardware, "required": true})
	if goal.has("dealer_deals"):
		var deals_required := int(goal["dealer_deals"])
		result.append({"kind": "dealer_deals", "ok": DealerManager.deals >= deals_required,
			"actual": DealerManager.deals, "required": deals_required})
	if goal.has("trust"):
		var trust: Dictionary = goal["trust"]
		var npc_id := str(trust.get("npc", ""))
		var trust_required := int(trust.get("min", 0))
		var trust_actual := NPCManager.get_trust(npc_id)
		result.append({"kind": "trust", "id": npc_id,
			"ok": trust_actual >= trust_required,
			"actual": trust_actual, "required": trust_required})
	return result


static func _stat_value(stat_key: String) -> int:
	match stat_key:
		"ruf_min":
			return PlayerStats.ruf
		"wissen_min":
			return PlayerStats.wissen
		"money_min":
			return int(PlayerStats.geld)
		"wealth_min":
			return int(PlayerStats.geld + BankManager.total())
		"homepage_visitors_min":
			return HomepageManager.visitors()
		"age_min":
			return PlayerIdentity.age()
		"ram_kb_min":
			return int(PlayerStats.ram_breakdown().get("total_kb", 0))
		_:
			return TimeManager.year
