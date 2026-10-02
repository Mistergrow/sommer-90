extends RefCounted
## Ein einziger Zeitvertrag fuer Computerladen, Werkstatt und Flohmarkt. Alte
## Spielstaende besitzen bereits `gruber_legacy`; neue erreichen denselben
## Zustand ueber den abgeschlossenen Abschiedsauftrag.

const GRUBER_ID := "npc_gruber"
const SUCCESSOR_ID := "npc_jan_gruber"


static func gruber_retired() -> bool:
	var game := _autoload("GameManager")
	var quests := _autoload("QuestManager")
	var flags: Dictionary = game.get("flags") if game != null else {}
	return bool(flags.get("gruber_legacy", false)) \
		or (quests != null and bool(quests.call("is_done", "q_gruber_abschied")))


static func owner_id() -> String:
	return SUCCESSOR_ID if gruber_retired() else GRUBER_ID


static func owner_name() -> String:
	return "Jan Gruber" if gruber_retired() else "Herr Gruber"


static func business_name() -> String:
	return "JAN GRUBER COMPUTERTECHNIK" if gruber_retired() \
		else "GRUBER COMPUTERTECHNIK"


static func market_visit(day_counter: int) -> bool:
	# Flohmaerkte finden wochenweise statt. Zwei Besuche Pause zwischen Grubers
	# Rundgaengen halten den Ruhestand sichtbar, ohne ihn ganz verschwinden zu
	# lassen oder ausgerechnet wieder zum festen Haendler zu machen.
	return gruber_retired() and posmod(floori(float(day_counter) / 7.0), 3) == 1


static func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/" + node_name)
	return null
