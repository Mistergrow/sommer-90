extends RefCounted
## Persistente BBS-Posts und Lesestatus fuer Szene-Releases.

const HandleRules := preload("res://scripts/scene/scene_handle_rules.gd")


static func dynamic_posts(manager: Node, board_id: String) -> Array:
	var result: Array = []
	var uploads: Array = manager.get("uploads")
	var releases: Dictionary = manager.get("releases")
	for i in range(uploads.size() - 1, -1, -1):
		var upload: Dictionary = uploads[i]
		if str(upload.get("board_id", "")) != board_id:
			continue
		var serial := str(upload.get("serial", ""))
		var release: Dictionary = releases.get(serial, {})
		if release.is_empty():
			continue
		var author := HandleRules.normalize(str(release.get("player_handle", "")))
		if not HandleRules.valid(author):
			author = "ANON-%04X" % (absi(hash(serial)) % 65536)
		result.append({
			"from": author,
			"subject": "NEW RELEASE: %s" % serial,
			"body": "%s / %s / QUALITY %d. CREDITS IN INTRO." % [
				str(release.get("title", "BYTEWERK RELEASE")).to_upper(),
				str(release.get("presenting", author)), int(release.get("quality", 0))],
		})
		var feedback: Array = upload.get("reactions", [])
		if not feedback.is_empty():
			result.append({"from": "SYSOP", "subject": "RE: %s" % serial, "body": "\n".join(feedback)})
		if result.size() >= 4:
			break
	var cooperation_offers: Array = manager.get("cooperation_offers")
	for offer in cooperation_offers:
		var entry: Dictionary = offer
		if str(entry.get("status", "")) not in ["offered", "accepted"]:
			continue
		result.append({
			"from": "%s / %s" % [str(entry.get("from_handle", "ANON")), str(entry.get("group_name", "SCENE"))],
			"subject": "COOPERATION: %s" % str(entry.get("status", "offered")).to_upper(),
			"body": str(entry.get("text", "Kooperation angeboten.")),
		})
	return result


static func unread_count(manager: Node, board_id: String) -> int:
	var count := 0
	for upload: Dictionary in manager.get("uploads"):
		if str(upload.get("board_id", "")) == board_id \
				and not bool(upload.get("feedback_read", false)) \
				and not (upload.get("reactions", []) as Array).is_empty():
			count += 1
	return count


static func mark_read(manager: Node, board_id: String) -> int:
	var uploads: Array = manager.get("uploads")
	var marked := 0
	for i in uploads.size():
		var upload: Dictionary = uploads[i]
		if str(upload.get("board_id", "")) != board_id \
				or bool(upload.get("feedback_read", false)) \
				or (upload.get("reactions", []) as Array).is_empty():
			continue
		upload["feedback_read"] = true
		uploads[i] = upload
		marked += 1
	manager.set("uploads", uploads)
	if marked > 0:
		manager.emit_signal("scene_changed")
	return marked


static func reaction_for(manager: Node, group: Dictionary, serial: String) -> String:
	var config: Dictionary = manager.get("_config")
	var templates: Array = config.get("reactions", [])
	if templates.is_empty():
		return ""
	var index := absi(hash("%s/%s" % [serial, group.get("id", "")])) % templates.size()
	return str(templates[index]) \
		.replace("{REP}", str(group.get("representative", "ANON"))) \
		.replace("{GROUP}", str(group.get("name", "SCENE")))


static func upload_error(message: String) -> Dictionary:
	return {"ok": false, "text": message, "recognition_delta": 0, "group_deltas": {}, "reactions": []}


static func was_uploaded(manager: Node, serial: String, board_id: String) -> bool:
	var uploads: Array = manager.get("uploads")
	return uploads.any(func(entry: Dictionary) -> bool:
		return str(entry.get("serial", "")) == serial and str(entry.get("board_id", "")) == board_id)


static func upload_ready(disk: Disk) -> bool:
	if disk == null or disk.release_serial.is_empty():
		return false
	if disk.release_role == "demo_master":
		return disk.content_type in ["demo", "spiel"]
	return disk.patch_state == "verified" and disk.cracktro_seen


static func board_definition(manager: Node, board_id: String) -> Dictionary:
	var config: Dictionary = manager.get("_config")
	for board: Dictionary in config.get("boards", []):
		if str(board.get("id", "")) == board_id:
			return board
	return {}


static func board_available(board: Dictionary, year: int) -> bool:
	if board.is_empty():
		return false
	if year >= int(board.get("from", 1990)) and year <= int(board.get("to", 1999)):
		return true
	if year <= int(board.get("to", 1999)):
		return false
	var board_id := str(board.get("id", ""))
	if board_id == "bbs_nachtschicht" and QuestManager.is_active("q_bbs_farewell"):
		return true
	return board_id == "bbs_datenautobahn" \
		and (QuestManager.is_active("q_bbs_farewell") or QuestManager.is_active("q_millennium_demo"))
