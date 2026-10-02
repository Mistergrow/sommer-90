extends RefCounted
## Reine, zustandslose Zeitplanung fuer Kampagnenauftraege. Der QuestManager
## besitzt weiterhin Definitionen und Status; dieses Modul beantwortet nur,
## ob ein Kapitel im aktuellen Kampagnenfenster bereits geoeffnet ist.


static func is_open(
		quest_id: String,
		slots: Dictionary,
		quest_def: Dictionary,
		campaign_progress: Dictionary,
		current_year: int,
		is_done: Callable
	) -> bool:
	var gate: Dictionary = slots.get(quest_id, {})
	if gate.is_empty():
		return true
	# Eine ausdrueckliche Spielerzusage darf nicht durch den dramaturgischen
	# Wochenplatz erneut gesperrt werden; die Prerequisites prueft der Manager.
	if str(quest_def.get("activation_policy", "scheduled")) == "prereq_immediate":
		return true
	var planned_year := int(gate.get("year", 1990))
	if current_year != planned_year:
		return current_year > planned_year # Backlog verschwindet nie fuer immer.
	if str(campaign_progress.get("phase", "")) != "summer":
		return false
	var planned_week := int(gate.get("week", 1))
	var current_week := int(campaign_progress.get("week", 0))
	if current_week >= planned_week:
		return true
	# Ein expliziter Ausblick kann genau eine Woche frueher beginnen, nachdem
	# die benannte Vorgaengerquest abgeschlossen wurde.
	var early_after := str(quest_def.get("early_after_quest", ""))
	return (early_after != "" and current_week == planned_week - 1
		and bool(is_done.call(early_after)))
