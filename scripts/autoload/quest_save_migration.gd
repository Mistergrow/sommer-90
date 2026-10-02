extends RefCounted
## Rekonstruiert Aktionszaehler ausschliesslich fuer bereits erreichte Stufen.

static func backfill(status: Dictionary, definition: Callable) -> void:
	for quest_id: String in status:
		var queststatus: Dictionary = status[quest_id]
		var stages: Array = definition.call(quest_id).get("stages", [])
		var completed_stage_count := stages.size() if bool(queststatus.get("done", false)) \
			else mini(int(queststatus.get("stage", 0)), stages.size())
		var actions: Dictionary = queststatus.get("actions", {})
		for stage_index in completed_stage_count:
			var goal: Dictionary = stages[stage_index].get("goal", {})
			var action := str(goal.get("action", ""))
			if not action.is_empty() and int(actions.get(action, 0)) < 1:
				actions[action] = 1
		queststatus["actions"] = actions
		status[quest_id] = queststatus

