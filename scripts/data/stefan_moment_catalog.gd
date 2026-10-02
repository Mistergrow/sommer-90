class_name StefanMomentCatalog
extends RefCounted
## Datengetriebene, entscheidbare Sommermomente mit Stefan. Sie fuellen bewusst
## die ruhigen Kampagnenwochen und bleiben von den 27 Spielwuenschen getrennt.

const CONFIG := "res://data/stefan_moments.json"

static var _loaded := false
static var _moments: Array[Dictionary] = []


static func reload() -> void:
	_loaded = true
	_moments = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not parsed is Dictionary:
		push_error("StefanMomentCatalog: %s ist ungueltig." % CONFIG)
		return
	for raw: Variant in (parsed as Dictionary).get("moments", []):
		if raw is Dictionary:
			_moments.append((raw as Dictionary).duplicate(true))
	_moments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := int(a.get("year", 0)); var by := int(b.get("year", 0))
		return int(a.get("week", 0)) < int(b.get("week", 0)) if ay == by else ay < by)


static func _ensure() -> void:
	if not _loaded:
		reload()


static func all() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for moment: Dictionary in _moments:
		out.append(moment.duplicate(true))
	return out


static func action(moment_id: String) -> String:
	return "stefan_moment:%s" % moment_id


static func quest_definitions() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for moment: Dictionary in _moments:
		var year := int(moment.get("year", 1992))
		var moment_id := str(moment.get("id", ""))
		out.append({
			"id": str(moment.get("quest_id", "")),
			"title": "Mit Stefan: %s" % str(moment.get("title", "Sommerabend")),
			"localization_context": {"family": "stefan_moment", "moment_id": moment_id},
			"giver": "npc_stefan",
			# Der Story-Director garantiert Backlog ueber Jahresgrenzen hinweg. Ein
			# Moment darf deshalb erst ab seinem Jahr, aber nie nur in diesem einen
			# Sommer spielbar sein. Die eindeutige Quest-ID und das Abschluss-Flag
			# verhindern eine doppelte Belohnung.
			"prereq": {"year_min": year},
			"stages": [{
				"desc": "Besuche Stefan und entscheide gemeinsam, was dieser Sommer fuer euch veraendert.",
				"map_location": "friend_cellar",
				"goal": {"action": action(moment_id)},
			}],
			"reward": [
				{"type": "npc_trust", "npc": "npc_stefan", "value": 1},
				{"type": "memory_once", "id": str(moment.get("memory", moment_id)),
					"title": "Mit Stefan: %s" % str(moment.get("title", "Sommerabend")),
					"title_key": "quest.dynamic.stefan_moment.memory_title",
					"title_source": "Mit Stefan: %s",
					"title_args": [str(moment.get("title", "Sommerabend"))],
					"title_arg_keys": ["story.stefan_moment.%s.title" % moment_id],
					"title_arg_sources": [str(moment.get("title", "Sommerabend"))],
					"text": Loc.t("misc.stefan_moment_catalog.mit_stefan_lange_ueber_s_gesprochen", "mit Stefan lange ueber »%s« gesprochen und gemeinsam eine Entscheidung getroffen") % str(moment.get("title", "diesen Sommer")),
					"text_key": "misc.stefan_moment_catalog.mit_stefan_lange_ueber_s_gesprochen",
					"text_source": "mit Stefan lange ueber »%s« gesprochen und gemeinsam eine Entscheidung getroffen",
					"text_args": [str(moment.get("title", "diesen Sommer"))],
					"text_arg_keys": ["story.stefan_moment.%s.title" % moment_id],
					"text_arg_sources": [str(moment.get("title", "diesen Sommer"))]},
				{"type": "flag", "flag": "stefan_moment_done:%s" % moment_id, "value": true},
			],
			"quest_family": "stefan_moments",
		})
	return out


static func _autoload(name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath("/root/" + name))


static func active_moment() -> Dictionary:
	_ensure()
	var quests := _autoload("QuestManager")
	if quests == null:
		return {}
	for moment: Dictionary in _moments:
		if bool(quests.call("is_active", str(moment.get("quest_id", "")))):
			return moment.duplicate(true)
	return {}


static func begin_active_dialogue() -> bool:
	var moment := active_moment()
	if moment.is_empty():
		return false
	var moment_id := str(moment.get("id", ""))
	var choices: Array[Dictionary] = []
	for raw: Variant in moment.get("choices", []):
		if not raw is Dictionary:
			continue
		var source: Dictionary = raw
		var effects: Array = source.get("effects", []).duplicate(true)
		effects.append({"type": "flag", "flag": str(source.get("flag", "stefan_choice:%s" % moment_id)), "value": true})
		effects.append({"type": "quest_action", "action": action(moment_id)})
		var choice_index := choices.size()
		choices.append({"text": Loc.t("story.stefan_moment.%s.choice%d" % [moment_id, choice_index],
			str(source.get("text", "Darueber reden."))), "next": null, "effects": effects})
	var dialogue := {
		"start": "n1",
		"choice_effects_once": true,
		"nodes": {"n1": {
			"speaker": "Stefan", "speaker_id": "npc_stefan",
			"text": Loc.t("story.stefan_moment.%s.text" % moment_id,
				str(moment.get("text", "Der Sommerabend wird zu einem langen Gespraech."))),
			"choices": choices,
		}},
	}
	var manager := _autoload("DialogueManager")
	if manager == null or not manager.has_method("start_runtime_dialogue"):
		return false
	manager.call("start_runtime_dialogue", "runtime_stefan_%s" % moment_id, "npc_stefan", dialogue)
	return true


static func validate() -> Array[String]:
	_ensure()
	var issues: Array[String] = []
	var ids: Dictionary = {}
	for moment: Dictionary in _moments:
		for key in ["id", "quest_id", "title", "text"]:
			if str(moment.get(key, "")).is_empty():
				issues.append("Stefan-Moment ohne %s." % key)
		var id := str(moment.get("id", ""))
		if ids.has(id):
			issues.append("Doppelter Stefan-Moment %s." % id)
		ids[id] = true
		if (moment.get("choices", []) as Array).size() < 2:
			issues.append("%s braucht mindestens zwei Entscheidungen." % id)
	return issues
