extends RefCounted
## Handle-only-Credits und Presenting-Auswahl des Szene-Studios.

const DemoUi := preload("res://scripts/ui/demo_maker_ui.gd")


static func refresh(owner: Control) -> void:
	var ui: Dictionary = owner.call("credits_ui_context")
	var credits_box: VBoxContainer = ui["credits_box"]
	var presenting: OptionButton = ui["presenting_option"]
	var greetings: Label = ui["bbs_greetings"]
	var project: Dictionary = owner.get("_project")
	DemoUi.clear_children(credits_box)
	var selected: Array = project.get("credit_entries", [])
	var author := str(project.get("group", "LONE-CODER")).to_upper()
	var candidates: Array = [{"actor_id": "player", "handle_snapshot": author,
		"handle": author, "role": "CODE", "available": true, "reason": ""}]
	for candidate: Dictionary in DemoManager.available_credits():
		if str(candidate.get("actor_id", "")) != "player":
			candidates.append(candidate)
	for candidate: Dictionary in candidates:
		var actor_id := str(candidate.get("actor_id", "guest"))
		var handle := str(candidate.get("handle_snapshot", candidate.get("handle", "ANON"))).to_upper()
		var role := str(candidate.get("role", "CREW")).to_upper()
		var available := bool(candidate.get("available", true))
		var row := CheckButton.new()
		row.text = Loc.t("ui.demo_maker_credits.s_s_s", "%s · %s%s") % [role, handle, "  [LOCKED]" if not available else ""]
		row.tooltip_text = str(candidate.get("reason", ""))
		row.disabled = not available or actor_id == "player"
		row.button_pressed = actor_id == "player" or selected_entry(selected, actor_id, handle)
		row.toggled.connect(Callable(owner, "_toggle_credit").bind(candidate))
		credits_box.add_child(row)
	presenting.clear()
	presenting.add_item(Loc.t("ui.demo_maker_credits.solo_s", "SOLO · %s") % author)
	presenting.set_item_metadata(0, "")
	for group: Dictionary in DemoManager.accepted_groups():
		var index := presenting.item_count
		presenting.add_item(Loc.t("ui.demo_maker_credits.co_release_s", "CO-RELEASE · %s") % str(group.get("name", group.get("id", "GROUP"))).to_upper())
		presenting.set_item_metadata(index, str(group.get("name", group.get("id", ""))))
	DemoUi.select_option(presenting, str(project.get("presenting", "")))
	var boards := DemoManager.active_bbs_names()
	greetings.text = Loc.t("ui.demo_maker_credits.bbs_greetings_s", "BBS GREETINGS: %s") % (" · ".join(boards.slice(0, 3)) if not boards.is_empty() else "NO PUBLIC BOARD YET")
	greetings.tooltip_text = greetings.text


static func selected_entry(selected: Array, actor_id: String, handle: String) -> bool:
	for entry in selected:
		if entry is Dictionary and (str(entry.get("actor_id", "")) == actor_id \
				or str(entry.get("handle_snapshot", entry.get("handle", ""))).to_upper() == handle):
			return true
	return false


static func toggle(owner: Control, on: bool, candidate: Dictionary) -> void:
	if bool(owner.get("_guard")) or str(candidate.get("actor_id", "")) == "player":
		return
	var project: Dictionary = owner.get("_project")
	var entries: Array = project.get("credit_entries", [])
	var actor_id := str(candidate.get("actor_id", "guest"))
	for i in range(entries.size() - 1, -1, -1):
		if entries[i] is Dictionary and str(entries[i].get("actor_id", "")) == actor_id:
			entries.remove_at(i)
	if on:
		if entries.size() >= 4:
			UIManager.toast(Loc.t("ui.demo_maker_credits.maximal_vier_sichtbare_credits_pro_release", "Maximal vier sichtbare Credits pro Release."))
			owner.call("_refresh_all")
			return
		var handle := str(candidate.get("handle_snapshot", candidate.get("handle", "ANON"))).to_upper()
		entries.append({"actor_id": actor_id, "handle_snapshot": handle, "handle": handle,
			"role": str(candidate.get("role", "CREW")).to_upper()})
	project["credit_entries"] = entries
	rebuild_line(project)
	owner.set("_project", project)
	owner.call("_mark_dirty")


static func select_presenting(owner: Control, index: int) -> void:
	if bool(owner.get("_guard")):
		return
	var project: Dictionary = owner.get("_project")
	var ui: Dictionary = owner.call("credits_ui_context")
	var presenting: OptionButton = ui["presenting_option"]
	project["presenting"] = str(presenting.get_item_metadata(index))
	owner.set("_project", project)
	owner.call("_mark_dirty")


static func rebuild_line(project: Dictionary) -> void:
	var lines: Array[String] = ["CODE: %s" % str(project.get("group", "LONE-CODER")).to_upper()]
	for entry in project.get("credit_entries", []):
		if not entry is Dictionary or str(entry.get("actor_id", "")) == "player":
			continue
		lines.append("%s: %s" % [str(entry.get("role", "CREW")).to_upper(),
			str(entry.get("handle_snapshot", entry.get("handle", "ANON"))).to_upper()])
	project["credits"] = " · ".join(lines)
