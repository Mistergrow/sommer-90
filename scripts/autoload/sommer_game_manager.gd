extends Node
## Persistenter Fortschritt der gemeinsam entwickelten Sommer-Game-Engine.

signal module_unlocked(module_id: String)
signal engine_changed

const Catalog := preload("res://scripts/data/sommer_game_module_catalog.gd")

var unlocked: Dictionary = {}
var projects: Dictionary = {}
var active_project_id := "main"


func reset() -> void:
	unlocked.clear()
	projects = {"main": {"name": "MEIN SPIEL", "revision": 1, "modules": []}}
	active_project_id = "main"
	engine_changed.emit()


func unlock_module(module_id: String) -> bool:
	var entry := Catalog.module(module_id)
	if entry.is_empty() or unlocked.has(module_id):
		return false
	for dependency: Variant in entry.get("requires", []):
		if not unlocked.has(str(dependency)):
			return false
	unlocked[module_id] = {
		"year": TimeManager.year,
		"lead": str(entry.get("lead", "team")),
		"revision": 1,
	}
	GameManager.flags["sommer_game_module_" + module_id] = true
	var project: Dictionary = projects.get(active_project_id, {})
	var modules: Array = project.get("modules", [])
	if module_id not in modules:
		modules.append(module_id)
	project["modules"] = modules
	project["revision"] = int(project.get("revision", 0)) + 1
	projects[active_project_id] = project
	module_unlocked.emit(module_id)
	engine_changed.emit()
	return true


func is_unlocked(module_id: String) -> bool:
	return unlocked.has(module_id)


func unlocked_ids() -> Array:
	var out: Array = unlocked.keys()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var left := Catalog.module(str(a)); var right := Catalog.module(str(b))
		return int(left.get("year", 0)) < int(right.get("year", 0)) or \
			(int(left.get("year", 0)) == int(right.get("year", 0)) and str(a) < str(b)))
	return out


func availability(module_id: String, year := -1, hardware_profile := "") -> Dictionary:
	var target_year := TimeManager.year if year < 0 else year
	var profile := hardware_profile if not hardware_profile.is_empty() else _hardware_profile()
	return Catalog.available(module_id, target_year, profile, unlocked_ids())


func contribution_readiness(module_id: String, year := -1,
		hardware_profile := "") -> Dictionary:
	var target_year := TimeManager.year if year < 0 else year
	var profile := hardware_profile if not hardware_profile.is_empty() else _hardware_profile()
	return Catalog.integration_readiness(module_id, target_year, profile,
		unlocked_ids())


func runtime_context() -> Dictionary:
	return {
		"unlocked_modules": unlocked_ids(),
		"hardware_profile": _hardware_profile(),
		"project_id": active_project_id,
		"project": (projects.get(active_project_id, {}) as Dictionary).duplicate(true),
	}


func active_contribution() -> Dictionary:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null:
		return {}
	for quest: Dictionary in quests.call("active_quests"):
		var quest_id := str(quest.get("id", ""))
		if not quest_id.begins_with("q_sommer_game_"):
			continue
		var stages: Array = quest.get("stages", [])
		var stage_index := int(quests.call("stage", quest_id))
		if stage_index < 0 or stage_index >= stages.size():
			continue
		var action := str((stages[stage_index] as Dictionary).get("goal", {}).get("action", ""))
		if action.begins_with("sommer_game_integrate:"):
			return {"quest_id": quest_id, "module_id": action.trim_prefix("sommer_game_integrate:"),
				"action": action, "stage": stage_index, "stage_count": stages.size()}
	return {}


func integrate_active_contribution() -> Dictionary:
	var contribution := active_contribution()
	if contribution.is_empty():
		return {"ok": false, "message": Loc.t("ui.sommer_game.no_contribution", "Kein gemeinsamer Modulbeitrag wartet auf Integration.")}
	var module_id := str(contribution.get("module_id", ""))
	var readiness := contribution_readiness(module_id)
	if not bool(readiness.get("available", false)):
		return {"ok": false, "message": _readiness_message(readiness),
			"reason": str(readiness.get("reason", ""))}
	get_node("/root/QuestManager").call("note_action", str(contribution["action"]))
	return {"ok": true, "message": Loc.t("ui.sommer_game.integrated", "Beitrag geprüft und in den gemeinsamen Build integriert."), "module_id": module_id}


func to_dict() -> Dictionary:
	return {"schema_version": 1, "unlocked": unlocked, "projects": projects,
		"active_project_id": active_project_id}


func from_dict(data: Variant) -> void:
	if data is Dictionary and int((data as Dictionary).get("schema_version", 0)) >= 1:
		unlocked = (data as Dictionary).get("unlocked", {}).duplicate(true)
		projects = (data as Dictionary).get("projects", {}).duplicate(true)
		active_project_id = str((data as Dictionary).get("active_project_id", "main"))
	else:
		_heal_legacy_save()
	if projects.is_empty():
		projects = {"main": {"name": "MEIN SPIEL", "revision": 1, "modules": unlocked_ids()}}
	for module_id: String in unlocked:
		GameManager.flags["sommer_game_module_" + module_id] = true
	engine_changed.emit()


func _heal_legacy_save() -> void:
	unlocked.clear()
	# Vergangene Sommer werden rekonstruiert. Der aktuelle Sommer bleibt als
	# spielbare Quest erhalten und wird nicht automatisch verschenkt.
	for entry: Dictionary in Catalog.all():
		if int(entry.get("year", 1990)) < TimeManager.year:
			unlocked[str(entry.get("id", ""))] = {"year": int(entry.get("year", 1990)),
				"lead": str(entry.get("lead", "team")), "revision": 1, "migrated": true}
	for past_year in range(1990, mini(TimeManager.year, 2000)):
		GameManager.flags["sommer_game_year_%d_complete" % past_year] = true


func _hardware_profile() -> String:
	var computer_model := PlayerStats.desk_model("computer_model")
	var installed_ram_kb := int(PlayerStats.ram_breakdown().get("total_kb", 0))
	if computer_model == "amiga_1200":
		if PlayerStats.hdd_is_usable() and installed_ram_kb >= 4096:
			return "amiga_1200_aga_hdd_4mb"
		return "amiga_1200_aga_2mb"
	if computer_model == "amiga_600":
		return "amiga_500_ecs_1mb"
	return "amiga_500_ocs_1mb" if installed_ram_kb >= 1024 else "amiga_500_ocs_512k"


func _readiness_message(readiness: Dictionary) -> String:
	match str(readiness.get("reason", "")):
		"hardware_too_weak":
			return Loc.t("ui.sommer_game.hardware_required",
				"Der Beitrag braucht zuerst die passende Hardware: %s") % \
				_profile_label(str(readiness.get("required_profile", "")))
		"dependency_missing":
			var dependency := Catalog.module(str(readiness.get("dependency", "")))
			var dependency_name := str(dependency.get("name_de",
				readiness.get("dependency", "")))
			return Loc.t("ui.sommer_game.dependency_required",
				"Zuerst muss dieses Modul in den Build: %s") % dependency_name
		"not_released_yet":
			return Loc.t("ui.sommer_game.not_released",
				"Dieser Beitrag ist in diesem Jahr noch nicht fertig.")
	return Loc.t("ui.sommer_game.not_ready",
		"Der Beitrag kann noch nicht integriert werden.")


func _profile_label(profile: String) -> String:
	return {
		"amiga_500_ocs_512k": "Amiga 500 · OCS · 512 KB",
		"amiga_500_ocs_1mb": "Amiga 500 · OCS · 1 MB",
		"amiga_500_ecs_1mb": "Amiga 600 · ECS · 1 MB",
		"amiga_1200_aga_2mb": "Amiga 1200 · AGA · 2 MB",
		"amiga_1200_aga_hdd_4mb": "Amiga 1200 · AGA · 4 MB · DH0:",
	}.get(profile, profile)
