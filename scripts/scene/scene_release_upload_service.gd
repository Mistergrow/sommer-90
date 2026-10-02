extends RefCounted
## Atomare Upload-Transaktion für eigene BYTEWERK- und Demo-Releases.
##
## Der Service bündelt Board-Zulassung, Idempotenz, Energie, Ruf, Gruppen-
## reaktionen und den gespeicherten Upload-Snapshot. Physische Disketten werden
## ausschließlich gelesen und niemals aus dem Inventar entfernt.

const Feedback := preload("res://scripts/scene/scene_release_feedback.gd")
const HandleRules := preload("res://scripts/scene/scene_handle_rules.gd")


static func uploadable_releases(owner: Node, disks: Array, board_id: String,
		year: int) -> Array:
	var board := Feedback.board_definition(owner, board_id)
	if not Feedback.board_available(board, year):
		return []
	var result: Array = []
	var seen_serials := {}
	for disk: Disk in disks:
		if not Feedback.upload_ready(disk):
			continue
		if seen_serials.has(disk.release_serial) \
				or Feedback.was_uploaded(owner, disk.release_serial, board_id):
			continue
		seen_serials[disk.release_serial] = true
		result.append(disk)
	return result


static func upload(owner: Node, disk: Disk, disks: Array, board_id: String,
		year: int, date: String, refresh_offers: Callable) -> Dictionary:
	var board := Feedback.board_definition(owner, board_id)
	if not Feedback.board_available(board, year):
		return Feedback.upload_error(
			"Dieses Board nimmt aktuell keine Szene-Releases an.")
	if not Feedback.upload_ready(disk):
		return Feedback.upload_error(
			"Nur ein verifiziertes BYTEWERK-Release oder ein fertiger Demo-Master kann hochgeladen werden.")
	if disk not in disks:
		return Feedback.upload_error(
			"Die Release-Diskette liegt nicht mehr in deiner Box.")
	if disk.release_role != "demo_master" and not disk.cracktro_seen:
		return Feedback.upload_error(
			"Das Intro muss vor dem Upload vollständig getestet sein.")
	if Feedback.was_uploaded(owner, disk.release_serial, board_id):
		return Feedback.upload_error("Dieses Release liegt bereits auf dem Board.")
	if not PlayerStats.use_energy(4):
		return Feedback.upload_error("Zu müde für einen sauberen Upload.")

	var quality := int(disk.release_data.get("quality", disk.patch_score))
	var releases: Dictionary = owner.get("releases")
	if not releases.has(disk.release_serial):
		releases[disk.release_serial] = _release_snapshot(
			owner, disk, quality)
		owner.set("releases", releases)

	var recognition_delta := clampi(roundi(
		float(2 + int(float(quality) / 24.0))
		* float(board.get("recognition_factor", 1.0))), 2, 7)
	owner.set("scene_recognition", clampi(
		int(owner.get("scene_recognition")) + recognition_delta, 0, 100))

	var group_result := _apply_group_reputation(owner, disk, quality, year)
	if refresh_offers.is_valid():
		refresh_offers.call()
	var upload_entry := {
		"serial": disk.release_serial,
		"board_id": board_id,
		"date": date,
		"quality": quality,
		"recognition_delta": recognition_delta,
		"group_deltas": group_result["deltas"],
		"reactions": group_result["reactions"],
		"feedback_read": false,
	}
	var uploads: Array = owner.get("uploads")
	uploads.append(upload_entry)
	owner.set("uploads", uploads)
	_mark_release_board(owner, disk.release_serial, board_id)
	owner.emit_signal("scene_changed")
	return {
		"ok": true,
		"text": "%s hochgeladen. Szene-Ruf +%d." % [
			disk.release_serial, recognition_delta],
		"recognition_delta": recognition_delta,
		"group_deltas": group_result["deltas"],
		"reactions": group_result["reactions"],
	}


static func _release_snapshot(owner: Node, disk: Disk, quality: int) -> Dictionary:
	var scene_handle := str(owner.get("scene_handle"))
	var author := HandleRules.normalize(str(disk.release_data.get(
		"author_handle", disk.release_data.get("group", scene_handle))))
	if not HandleRules.valid(author):
		author = scene_handle if HandleRules.valid(scene_handle) \
			else "ANON-%04X" % (absi(hash(disk.release_serial)) % 65536)
	return {
		"serial": disk.release_serial,
		"title": str(disk.release_data.get("title", disk.content_title)),
		"player_handle": author,
		"presenting": str(disk.release_data.get(
			"presenting", disk.release_data.get("group", author))),
		"quality": quality,
		"tags": (disk.release_data.get("tags", []) as Array).duplicate(),
		"credits": (disk.release_data.get("credits", []) as Array).duplicate(true),
		"source": "scene_studio",
	}


static func _apply_group_reputation(owner: Node, disk: Disk, quality: int,
		year: int) -> Dictionary:
	var config: Dictionary = owner.get("_config")
	var group_rep: Dictionary = owner.get("group_rep")
	var tags: Array = disk.release_data.get("tags", [])
	var deltas := {}
	var reactions: Array = []
	for group: Dictionary in config.get("groups", []):
		if year < int(group.get("from", 1990)) \
				or year > int(group.get("to", 1999)):
			continue
		var matches := 0
		for preference in group.get("preferences", []):
			if preference in tags:
				matches += 1
		var group_id := str(group.get("id", ""))
		var delta := 1 + int(float(quality) / 40.0) + matches * 2
		group_rep[group_id] = clampi(
			int(group_rep.get(group_id, 0)) + delta, 0, 100)
		deltas[group_id] = delta
		if delta >= 4:
			reactions.append(Feedback.reaction_for(
				owner, group, disk.release_serial))
	if reactions.is_empty():
		reactions.append(
			"SYSOP: %s geprüft — läuft sauber. Beim nächsten Build mehr eigene Handschrift."
			% disk.release_serial)
	owner.set("group_rep", group_rep)
	return {"deltas": deltas, "reactions": reactions}


static func _mark_release_board(owner: Node, serial: String,
		board_id: String) -> void:
	var releases: Dictionary = owner.get("releases")
	if not releases.has(serial):
		return
	var stored: Dictionary = releases[serial]
	var boards: Array = stored.get("uploaded_to", [])
	if board_id not in boards:
		boards.append(board_id)
	stored["uploaded_to"] = boards
	releases[serial] = stored
	owner.set("releases", releases)
