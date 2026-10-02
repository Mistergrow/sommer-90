extends RefCounted
## Persistente Handle-Zuordnung, Vorschlaege und sichere Credit-Snapshots.

const BBS_SCENE_PATH := "res://data/bbs_scene.json"
const Rules := preload("res://scripts/scene/scene_handle_rules.gd")


static func set_player_handle(manager: Node, value: String) -> Dictionary:
	var candidate := Rules.normalize(value)
	if not Rules.valid(candidate):
		return {"ok": false, "text": Loc.t("misc.scene_handle_service.handle_3_16_zeichen_nur_a", "Handle: 3–16 Zeichen, nur A–Z, 0–9, _ oder -."), "handle": ""}
	var current := str(manager.get("scene_handle"))
	var releases: Dictionary = manager.get("releases")
	if not releases.is_empty() and current != "" and candidate != current:
		return {"ok": false, "text": Loc.t("misc.scene_handle_service.nach_dem_ersten_release_bleibt_dein", "Nach dem ersten Release bleibt dein Szene-Handle fest."), "handle": current}
	if candidate != current and candidate in reserved_handles(manager):
		return {"ok": false, "text": Loc.t("misc.scene_handle_service.dieses_handle_ist_in_den_brettern", "Dieses Handle ist in den Brettern bereits vergeben."), "handle": ""}
	manager.set("scene_handle", candidate)
	var aliases: Dictionary = manager.get("alias_assignments")
	aliases["player"] = candidate
	manager.set("alias_assignments", aliases)
	manager.emit_signal("scene_changed")
	return {"ok": true, "text": "Szene-Handle gesetzt: %s" % candidate, "handle": candidate}


static func suggestions(manager: Node, seed_hint: String) -> Array:
	var config: Dictionary = manager.get("_config")
	var parts: Dictionary = config.get("handle_parts", {})
	var prefixes: Array = parts.get("prefix", ["BYTE", "NEON"])
	var suffixes: Array = parts.get("suffix", ["KID", "UNIT"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("BYTEWERK/%s/%d" % [seed_hint, int(manager.call("_day_counter"))])
	var result: Array = []
	var reserved := reserved_handles(manager)
	var attempts := 0
	while result.size() < 4 and attempts < 64:
		attempts += 1
		var suggestion := "%s-%s" % [str(prefixes[rng.randi_range(0, prefixes.size() - 1)]),
			str(suffixes[rng.randi_range(0, suffixes.size() - 1)])]
		if suggestion not in result and suggestion not in reserved:
			result.append(suggestion)
	return result


static func reserved_handles(manager: Node) -> Array:
	var out: Array = []
	var bbs := manager.get_node_or_null("/root/BBSScene")
	if bbs != null and bbs.has_method("all_handles"):
		for handle in bbs.call("all_handles"):
			var normalized := Rules.normalize(str(handle))
			if normalized != "" and normalized not in out:
				out.append(normalized)
		return out
	if FileAccess.file_exists(BBS_SCENE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BBS_SCENE_PATH))
		if parsed is Dictionary:
			for handle in (parsed as Dictionary).get("personas", {}).values():
				out.append(Rules.normalize(str(handle)))
			for group: Dictionary in (parsed as Dictionary).get("groups", []):
				for member in group.get("members", []):
					out.append(Rules.normalize(str(member)))
	return out


static func handle_for_actor(manager: Node, actor_id: String) -> String:
	if actor_id in ["player", "self"]:
		return str(manager.get("scene_handle"))
	var aliases: Dictionary = manager.get("alias_assignments")
	if aliases.has(actor_id) and Rules.valid(str(aliases[actor_id])):
		return Rules.normalize(str(aliases[actor_id]))
	var handle := ""
	var bbs := manager.get_node_or_null("/root/BBSScene")
	if bbs != null:
		if bbs.has_method("handle_for_actor"):
			handle = str(bbs.call("handle_for_actor", actor_id))
		elif bbs.has_method("pseudonym"):
			handle = str(bbs.call("pseudonym", actor_id))
	handle = Rules.normalize(handle)
	if not Rules.valid(handle):
		handle = "ANON-%04X" % (absi(hash(actor_id)) % 65536)
	aliases[actor_id] = handle
	manager.set("alias_assignments", aliases)
	return handle


static func credit_candidates(manager: Node) -> Array:
	var result: Array = []
	var player_handle := str(manager.get("scene_handle"))
	if Rules.valid(player_handle):
		result.append({"actor_id": "player", "handle_snapshot": player_handle,
			"handle": player_handle, "role": "RELEASE", "available": true, "reason": ""})
	var year := int(manager.call("_year"))
	var config: Dictionary = manager.get("_config")
	for definition: Dictionary in config.get("contributors", []):
		var actor_id := str(definition.get("actor_id", ""))
		var from_year := int(definition.get("from", 1990))
		var to_year := int(definition.get("to", 1999))
		var min_trust := int(definition.get("min_trust", 0))
		var trust := 0
		var npc := manager.get_node_or_null("/root/NPCManager")
		if npc != null and npc.has_method("get_trust"):
			trust = int(npc.call("get_trust", actor_id))
		var available := year >= from_year and year <= to_year and trust >= min_trust
		var reason := ""
		if year < from_year or year > to_year:
			reason = "In diesem Jahr nicht aktiv."
		elif trust < min_trust:
			reason = "Vertrauen %d/%d." % [trust, min_trust]
		var snapshot := handle_for_actor(manager, actor_id)
		result.append({"actor_id": actor_id, "handle_snapshot": snapshot,
			"handle": snapshot, "role": str(definition.get("role", "CREW")),
			"available": available, "reason": reason,
			"tags": (definition.get("tags", []) as Array).duplicate()})
	return result
