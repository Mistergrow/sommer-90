extends WbApp
## Zentrale, ehrliche Sommerbench-Oberflaeche fuer 19 Entwicklungs- und
## 10 Produktivprogramme. Vorhandene Module werden direkt gestartet; fehlende
## Anwendungen bleiben sichtbar und erklaeren ihre Luecke, statt eine
## funktionslose Attrappe zu oeffnen.

const Catalog := preload("res://scripts/data/sommer_suite_catalog.gd")
const RuntimeCatalog := preload("res://scripts/data/sommer_suite_runtime_catalog.gd")

var _entries: Array[Dictionary] = []
var _entry_buttons: Array[Dictionary] = []
var _selected_id := "sommer_basic"
var _active_group: StringName = &"development"
var _group_buttons: Dictionary = {}
var _launch_button: Dictionary


func _init() -> void:
	app_title = "SOMMER SOFTWARE SUITE"
	app_bg = Color8(5, 11, 19)
	app_bar = Color8(20, 64, 105)
	app_accent = Color8(35, 205, 229)


func _build_app() -> void:
	app_title = _t("title", "SOMMER SOFTWARE SUITE")
	_entries = RuntimeCatalog.all_joined()
	_group_buttons[&"development"] = add_button(_t("development", "ENTWICKLUNG · 19"),
		Rect2(12, 62, 170, 25), _select_group.bind(&"development"), app_accent)
	_group_buttons[&"productivity"] = add_button(_t("productivity", "PRODUKTIVITAET · 10"),
		Rect2(190, 62, 170, 25), _select_group.bind(&"productivity"), app_accent)
	for group_button: Dictionary in _group_buttons.values():
		var group_node := group_button.get("node") as Button
		if group_node != null:
			group_node.toggle_mode = true
	var group_indices := {&"development": 0, &"productivity": 0}
	for entry: Dictionary in _entries:
		var group_id := StringName(entry.get("group", "development"))
		var group_index := int(group_indices.get(group_id, 0))
		group_indices[group_id] = group_index + 1
		var button := add_button("", _entry_rect(group_id, group_index),
			_select_program.bind(str(entry.get("id", ""))), Color.WHITE, false)
		button["entry_id"] = str(entry.get("id", ""))
		button["group_id"] = group_id
		button["group_index"] = group_index
		_entry_buttons.append(button)
	_launch_button = add_button(_t("launch", "MODUL STARTEN"),
		Rect2(402, 324, 214, 26), _launch_selected, app_accent)
	_apply_group_visibility()


func _select_group(group_id: StringName) -> void:
	if group_id not in Catalog.PROGRAM_GROUPS or group_id == _active_group:
		return
	_active_group = group_id
	var visible_entries := Catalog.in_group(group_id)
	if not visible_entries.is_empty():
		_selected_id = str(visible_entries[0].get("id", ""))
	_apply_group_visibility()
	queue_redraw()


func _apply_group_visibility() -> void:
	for group_id: StringName in _group_buttons:
		var group_node := (_group_buttons[group_id] as Dictionary).get("node") as Button
		if group_node != null:
			group_node.button_pressed = group_id == _active_group
	for button: Dictionary in _entry_buttons:
		var node := button.get("node") as Button
		if node != null:
			node.visible = StringName(button.get("group_id", "")) == _active_group


func _entry_rect(group_id: StringName, group_index: int) -> Rect2:
	var group_count := Catalog.in_group(group_id).size()
	var rows := ceili(float(group_count) / 2.0)
	var column := floori(float(group_index) / float(rows))
	var row := group_index % rows
	return Rect2(12 + column * 178, 92 + row * 25, 170, 22)


func _select_program(program_id: String) -> void:
	if Catalog.has(program_id):
		_selected_id = program_id
		queue_redraw()


func _launch_selected() -> void:
	open_tool(_selected_id)


func open_tool(program_id: String) -> bool:
	var status := RuntimeCatalog.player_status(program_id)
	if not bool(status.get("can_launch", false)):
		UIManager.toast(str(status.get("reason", _t("unavailable",
			"Dieses Modul ist noch nicht verfuegbar."))))
		return false
	var plan: Dictionary = status.get("launch_plan", {})
	var kind := str(plan.get("kind", ""))
	queue_free()
	if kind == "ui_method":
		UIManager.call_deferred(str(plan.get("method", "")))
	elif kind == "program":
		UIManager.call_deferred("open_program", str(plan.get("program_id", "")))
	else:
		return false
	return true


func entry_count() -> int:
	return _entries.size()


func active_group() -> StringName:
	return _active_group


func visible_entry_count() -> int:
	return Catalog.in_group(_active_group).size()


func selected_snapshot() -> Dictionary:
	var definition := Catalog.definition(_selected_id)
	return {"id": _selected_id, "definition": definition,
		"implementation": RuntimeCatalog.implementation(_selected_id),
		"status": RuntimeCatalog.player_status(_selected_id)}


func _content(font: Font) -> void:
	var year := RuntimeCatalog.effective_year(TimeManager.year)
	var profile_id := RuntimeCatalog.active_hardware_profile()
	var profile := Catalog.hardware_profile(profile_id)
	rect(10, 25, VW - 20, 30, Color8(7, 20, 32))
	rect_line(10, 25, VW - 20, 30, app_accent)
	text(font, "SOMMER '90 · %d" % year, 18, 42, 12, Color8(255, 179, 48))
	text(font, Loc.t("ui.sommer_suite.profile.%s" % profile_id,
		str(profile.get("display_name", "AMIGA"))), 150, 42, 9,
		Color8(151, 202, 218))
	text(font, _summary_text(), 404, 42, 9, Color8(91, 231, 131))

	rect(8, 58, 356, 298, Color8(4, 9, 15))
	rect_line(8, 58, 356, 298, Color8(34, 78, 102))
	for index in _entries.size():
		if StringName(_entries[index].get("group", "development")) == _active_group:
			_draw_entry(font, _entries[index], _entry_buttons[index])

	_draw_details(font)
	text(font, _t("footer", "19 Entwicklung · 10 Produktivitaet · Esc = zurueck"),
		14, 370, 8, Color8(110, 146, 167))


func _draw_entry(font: Font, entry: Dictionary, button: Dictionary) -> void:
	var button_rect: Rect2 = button.get("rect", Rect2())
	var x := button_rect.position.x
	var y := button_rect.position.y
	var width := button_rect.size.x
	var height := button_rect.size.y
	var program_id := str(entry.get("id", ""))
	var status := RuntimeCatalog.player_status(program_id)
	var selected := program_id == _selected_id
	var hovered := widget_hovered(button)
	var accent := _state_color(str(status.get("state", "")))
	rect(x, y, width, height, Color8(18, 31, 43) if selected or hovered else Color8(8, 15, 23))
	if selected:
		rect(x, y, 3, height, accent)
	rect_line(x, y, width, height, accent if selected else Color(accent, 0.42))
	text(font, _program_name(program_id, entry), x + 7, y + 10, 8,
		Color8(242, 244, 236) if selected else Color8(191, 207, 213))
	text(font, str(status.get("label", "")), x + 7, y + 19, 6, accent)


func _draw_details(font: Font) -> void:
	var definition := Catalog.definition(_selected_id)
	var implementation := RuntimeCatalog.implementation(_selected_id)
	var status := RuntimeCatalog.player_status(_selected_id)
	var accent := _state_color(str(status.get("state", "")))
	rect(374, 58, 258, 298, Color8(5, 12, 20))
	rect_line(374, 58, 258, 298, accent)
	text(font, _program_name(_selected_id, definition), 388, 79, 15, accent)
	text(font, "%d–%d · %s" % [int(definition.get("year_from", 1990)),
		int(definition.get("year_to", 1999)),
		str(status.get("label", ""))], 388, 94, 8, Color8(166, 193, 205))
	var y := 114.0
	for line: String in _wrapped(_program_purpose(_selected_id, definition), 36, 4):
		text(font, line, 388, y, 8, Color8(220, 229, 226)); y += 11
	y += 5
	text(font, _t("modules", "MODULE"), 388, y, 7, Color8(255, 179, 48)); y += 12
	for line: String in _wrapped(_program_modules(_selected_id, definition), 38, 3):
		text(font, line.to_upper(), 388, y, 7, Color8(130, 193, 210)); y += 10
	y += 5
	text(font, _t("status", "STATUS"), 388, y, 7, Color8(255, 179, 48)); y += 12
	for line: String in _wrapped(str(status.get("reason", "")), 38, 4):
		text(font, line, 388, y, 7, accent); y += 10
	var dependencies: Array = definition.get("dependencies", [])
	if not dependencies.is_empty():
		y += 4
		text(font, _t("requires", "BRAUCHT") + ": " + " · ".join(dependencies).to_upper(),
			388, y, 6, Color8(151, 170, 180))
	if str(implementation.get("classification", "")) == "missing":
		text(font, _t("not_fake", "KEIN SCHEIN-START · EDITOR WIRD NOCH GEBAUT"),
			388, 311, 6, Color8(255, 112, 90))
	var can_launch := bool(status.get("can_launch", false))
	var launch_node := _launch_button.get("node") as Button
	if launch_node != null:
		launch_node.disabled = not can_launch
	_launch_button["label"] = _t("launch", "MODUL STARTEN") if can_launch else \
		_t("locked", "MODUL GESPERRT")


func _summary_text() -> String:
	var native := 0
	var adapters := 0
	var missing := 0
	for entry: Dictionary in _entries:
		match str((entry.get("implementation", {}) as Dictionary).get("classification", "")):
			"native": native += 1
			"adapter": adapters += 1
			_: missing += 1
	return _t("summary", "%d NATIV · %d MODULE · %d OFFEN") % [
		native, adapters, missing]


func _program_name(program_id: String, definition: Dictionary) -> String:
	return Loc.t("ui.sommer_suite.tool.%s.name" % program_id,
		str(definition.get("display_name", program_id)))


func _program_purpose(program_id: String, definition: Dictionary) -> String:
	return Loc.t("ui.sommer_suite.tool.%s.purpose" % program_id,
		str(definition.get("purpose", "")))


func _program_modules(program_id: String, definition: Dictionary) -> String:
	var modules: Array = definition.get("modules", [])
	var fallback: Array[String] = []
	for module_value: Variant in modules:
		fallback.append(str(module_value).replace("_", " "))
	return Loc.t("ui.sommer_suite.tool.%s.modules" % program_id,
		" · ".join(fallback))


func _t(key: String, fallback: String) -> String:
	return Loc.t("ui.sommer_suite.%s" % key, fallback)


func _state_color(state: String) -> Color:
	match state:
		"native": return Color8(74, 237, 125)
		"adapter": return Color8(61, 209, 236)
		"future", "hardware", "uninstalled": return Color8(255, 181, 49)
		"missing": return Color8(255, 105, 88)
		_: return Color8(134, 145, 152)


func _wrapped(value: String, max_chars: int, max_lines: int) -> Array[String]:
	var lines: Array[String] = []
	var current := ""
	for word: String in value.replace("_", " ").split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if candidate.length() > max_chars and not current.is_empty():
			lines.append(current)
			current = word
			if lines.size() >= max_lines:
				break
		else:
			current = candidate
	if lines.size() < max_lines and not current.is_empty():
		lines.append(current)
	if lines.size() == max_lines and value.length() > 0:
		var joined := " ".join(lines)
		if joined.length() < value.length() and lines[-1].length() > 3:
			lines[-1] = lines[-1].substr(0, lines[-1].length() - 3) + "..."
	return lines
