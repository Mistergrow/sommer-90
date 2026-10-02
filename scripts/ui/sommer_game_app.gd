extends WbApp
## Native Sommer-Game-Oberflaeche. Der Spieler bekommt die Engine nicht
## geschenkt: jeder Eintrag stammt aus einer Jahresquest und wird hier bewusst
## geprueft und in den gemeinsamen Projektkern integriert.

const Catalog := preload("res://scripts/data/sommer_game_module_catalog.gd")

var _modules: Array[Dictionary] = []
var _module_buttons: Array[Dictionary] = []
var _selected_id := "project_core"
var _integrate_button: Dictionary


func _init() -> void:
	app_title = "SOMMER GAME · ENGINE LAB"
	app_bg = Color8(4, 9, 15)
	app_bar = Color8(12, 58, 96)
	app_accent = Color8(53, 215, 238)


func _build_app() -> void:
	_modules = Catalog.all()
	var contribution: Dictionary = SommerGameManager.active_contribution()
	if not contribution.is_empty():
		_selected_id = str(contribution.get("module_id", _selected_id))
	for index in _modules.size():
		var column := 0 if index < 7 else 1
		var row := index if index < 7 else index - 7
		var hitbox := Rect2(12 + column * 177, 72 + row * 39, 169, 34)
		_module_buttons.append(add_button("", hitbox,
			_select_module.bind(str(_modules[index].get("id", ""))), Color.WHITE, false))
	_integrate_button = add_button(_t("IN BUILD INTEGRIEREN", "INTEGRATE INTO BUILD"),
		Rect2(390, 322, 224, 27), _integrate_contribution, app_accent)
	if not SommerGameManager.engine_changed.is_connected(_engine_changed):
		SommerGameManager.engine_changed.connect(_engine_changed)


func _exit_tree() -> void:
	if SommerGameManager.engine_changed.is_connected(_engine_changed):
		SommerGameManager.engine_changed.disconnect(_engine_changed)


func _select_module(module_id: String) -> void:
	if Catalog.module(module_id).is_empty():
		return
	var contribution := SommerGameManager.active_contribution()
	var selectable := SommerGameManager.is_unlocked(module_id) or \
		str(contribution.get("module_id", "")) == module_id
	if not selectable:
		UIManager.toast(_t("Dieses Modul wartet auf seine Jahresaufgabe.",
			"This module is waiting for its annual task."))
		return
	_selected_id = module_id
	queue_redraw()


func _integrate_contribution() -> void:
	var result := SommerGameManager.integrate_active_contribution()
	UIManager.toast(str(result.get("message", "")))
	if bool(result.get("ok", false)):
		_selected_id = str(result.get("module_id", _selected_id))
	queue_redraw()


func _engine_changed() -> void:
	queue_redraw()


func _content(font: Font) -> void:
	var project: Dictionary = SommerGameManager.projects.get(
		SommerGameManager.active_project_id, {})
	var unlocked_count := SommerGameManager.unlocked_ids().size()
	var contribution := SommerGameManager.active_contribution()

	# Klare Projektkopfzeile statt generischer Tool-Wand.
	rect(8, 25, 624, 38, Color8(7, 20, 31))
	rect_line(8, 25, 624, 38, Color8(31, 106, 137))
	text(font, _t("GEMEINSAMER ENGINE-BUILD", "SHARED ENGINE BUILD"), 18, 40, 8,
		Color8(255, 177, 44))
	text(font, str(project.get("name", "MEIN SPIEL")), 18, 55, 14, Color8(239, 245, 239))
	text(font, _t("REVISION", "REVISION") + " %02d" % int(project.get("revision", 1)),
		278, 40, 8, Color8(133, 184, 204))
	text(font, "%02d / %02d MODULE" % [unlocked_count, _modules.size()], 278, 55, 10,
		Color8(75, 232, 129))
	text(font, _hardware_label(), 438, 40, 7, Color8(89, 208, 235))
	text(font, _t("JAHR", "YEAR") + " %d" % TimeManager.year, 438, 55, 10,
		Color8(245, 218, 119))

	# Zehn Jahre als kompakte, bedienbare Modulpipeline.
	rect(8, 67, 350, 290, Color8(3, 8, 13))
	rect_line(8, 67, 350, 290, Color8(25, 78, 102))
	text(font, _t("ENGINE-FAHRPLAN 1990–1999", "ENGINE ROADMAP 1990–1999"),
		16, 69, 7, Color8(114, 202, 223))
	for index in _modules.size():
		_draw_module(font, index, _modules[index], _module_buttons[index], contribution)

	_draw_details(font, Catalog.module(_selected_id), contribution)
	text(font, _t("Daniel · Lisa · Sven · Mike · dein gemeinsamer Code",
		"Daniel · Lisa · Sven · Mike · your shared code"), 14, 371, 7,
		Color8(107, 145, 160))


func _draw_module(font: Font, index: int, entry: Dictionary,
		button: Dictionary, contribution: Dictionary) -> void:
	var column := 0 if index < 7 else 1
	var row := index if index < 7 else index - 7
	var x := 12.0 + column * 177.0
	var y := 72.0 + row * 39.0
	var module_id := str(entry.get("id", ""))
	var unlocked := SommerGameManager.is_unlocked(module_id)
	var active := str(contribution.get("module_id", "")) == module_id
	var node := button.get("node") as Button
	if node != null:
		node.disabled = not unlocked and not active
	var selected := module_id == _selected_id
	var hovered := widget_hovered(button)
	var color := Color8(71, 232, 126) if unlocked else \
		(Color8(255, 177, 44) if active else Color8(76, 126, 145))
	rect(x, y, 169, 34, Color8(15, 29, 39) if selected or hovered else Color8(7, 14, 21))
	if selected:
		rect(x, y, 3, 34, color)
	rect_line(x, y, 169, 34, color if selected or active else Color(color, 0.42))
	text(font, "%d" % int(entry.get("year", 1990)), x + 8, y + 12, 7, color)
	text(font, _module_name(entry), x + 40, y + 13, 8,
		Color8(239, 243, 235) if selected else Color8(186, 204, 210))
	text(font, _lead_label(str(entry.get("lead", "team"))), x + 40, y + 26, 6,
		Color8(111, 157, 174))
	text(font, "X" if unlocked else (">" if active else "·"), x + 153, y + 22, 8, color)


func _draw_details(font: Font, entry: Dictionary, contribution: Dictionary) -> void:
	rect(366, 67, 266, 290, Color8(5, 12, 19))
	rect_line(366, 67, 266, 290, Color8(35, 96, 119))
	if entry.is_empty():
		return
	var module_id := str(entry.get("id", ""))
	var unlocked := SommerGameManager.is_unlocked(module_id)
	var active := str(contribution.get("module_id", "")) == module_id
	var readiness := SommerGameManager.contribution_readiness(module_id)
	var is_ready := bool(readiness.get("available", false))
	var status_color := Color8(71, 232, 126) if unlocked else \
		(Color8(255, 177, 44) if active and is_ready else Color8(111, 151, 164))
	text(font, _module_name(entry), 379, 85, 13, status_color)
	text(font, "%d · %s" % [int(entry.get("year", 1990)),
		_lead_label(str(entry.get("lead", "team")))], 379, 99, 7, Color8(137, 183, 199))
	if active:
		text(font, _t("AKTIVE AUFGABE", "ACTIVE TASK") + " %d/%d" % [
			int(contribution.get("stage", 0)) + 1,
			maxi(1, int(contribution.get("stage_count", 1)))],
			493, 99, 7, Color8(255, 177, 44))
	var y := 116.0
	for line: String in _wrap(_localized(entry, "description"), 39, 4):
		text(font, line, 379, y, 7, Color8(217, 226, 223)); y += 10
	y += 4
	text(font, _t("SYSTEME", "SYSTEMS"), 379, y, 7, Color8(255, 177, 44)); y += 11
	for line: String in _wrap(" · ".join(entry.get("systems", [])).replace("_", " ").to_upper(), 42, 3):
		text(font, line, 379, y, 6, Color8(108, 197, 219)); y += 9
	y += 5
	text(font, _t("SOMMER-BASIC-BRUECKE", "SOMMER BASIC BRIDGE"), 379, y, 7,
		Color8(255, 177, 44)); y += 11
	for line: String in _sample_code(module_id):
		text(font, line, 379, y, 6, Color8(108, 236, 151)); y += 9

	var reason := _status_text(entry, unlocked, active, readiness)
	text(font, reason, 379, 309, 6, status_color)
	var node := _integrate_button.get("node") as Button
	if node != null:
		node.disabled = not active or unlocked or not is_ready
	_integrate_button["label"] = _t("IN BUILD INTEGRIEREN", "INTEGRATE INTO BUILD") \
		if active and not unlocked and is_ready else (_t("BEREITS INTEGRIERT", "ALREADY INTEGRATED") \
		if unlocked else _t("BEITRAG NOCH NICHT DA", "CONTRIBUTION NOT READY"))


func _status_text(entry: Dictionary, unlocked: bool, active: bool,
		readiness: Dictionary) -> String:
	if unlocked:
		return _t("X MODUL IST IM GEMEINSAMEN BUILD", "X MODULE IS IN THE SHARED BUILD")
	if active:
		if str(readiness.get("reason", "")) == "hardware_too_weak":
			return _t("BRAUCHT: ", "REQUIRES: ") + \
				_profile_label(str(readiness.get("required_profile", "")))
		if str(readiness.get("reason", "")) == "dependency_missing":
			var dependency := Catalog.module(str(readiness.get("dependency", "")))
			return _t("ZUERST: ", "FIRST: ") + _module_name(dependency).to_upper()
		return _t("> BEITRAG PRUEFEN UND INTEGRIEREN", "> REVIEW AND INTEGRATE CONTRIBUTION")
	if TimeManager.year < int(entry.get("year", 1990)):
		return _t("ERSCHEINT IM SOMMER", "ARRIVES IN SUMMER") + " %d" % int(entry.get("year", 1990))
	return _t("WARTET AUF DIE PASSENDE JAHRESQUEST", "WAITING FOR ITS YEAR QUEST")


func _sample_code(module_id: String) -> Array[String]:
	match module_id:
		"physics_engine": return ["LOADMAP \"CRATER01\"", "FIREPROJECTILE 80,40,2,-3", "UPDATEPHYSICS", "DRAWWORLD · FLIP"]
		"strategy_grid_engine": return ["ZONE 4,5,\"WOHNEN\"", "POWERLINK 1,1,4,5", "TRAFFICROUTE 2,5,12,5", "SIMULATE"]
		"network_engine": return ["WHILE GAMEACTIVE", "  NETWORKSYNC", "  UPDATEPLAYERS", "WEND"]
		"integrated_engine": return ["PROFILEFRAME", "EXPORTBUILD \"DISK\",\"GAME1\"", "PRINT BUILDVERSION"]
	var entry := Catalog.module(module_id)
	var symbols: Array[String] = []
	for symbol: Variant in entry.get("commands", []):
		symbols.append(str(symbol))
	for symbol: Variant in entry.get("functions", []):
		symbols.append(str(symbol) + "()")
	return _wrap(" · ".join(symbols), 40, 4)


func _hardware_label() -> String:
	var profile := str(SommerGameManager.runtime_context().get(
		"hardware_profile", "amiga_500_ocs_1mb"))
	var computer_model := PlayerStats.desk_model("computer_model")
	if computer_model == "amiga_600":
		return "A600 · ECS · 1 MB"
	return _profile_label(profile).to_upper()


func _profile_label(profile: String) -> String:
	return {
		"amiga_500_ocs_1mb": "A500 · OCS · 1 MB",
		"amiga_500_ecs_1mb": "A600 · ECS · 1 MB",
		"amiga_1200_aga_2mb": "A1200 · AGA · 2 MB",
		"amiga_1200_aga_hdd_4mb": "A1200 · AGA · 4 MB · DH0:",
	}.get(profile, profile)


func _module_name(entry: Dictionary) -> String:
	return _localized(entry, "name")


func _localized(entry: Dictionary, stem: String) -> String:
	var suffix := "en" if TranslationServer.get_locale().begins_with("en") else "de"
	return str(entry.get(stem + "_" + suffix, entry.get(stem + "_de", "")))


func _lead_label(lead: String) -> String:
	return {"daniel": "DANIEL", "lisa": "LISA", "sven": "SVEN",
		"mike": "MIKE", "team": _t("TEAM", "TEAM")}.get(lead, lead.to_upper())


func _t(de: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else de


func _wrap(value: String, max_chars: int, max_lines: int) -> Array[String]:
	var lines: Array[String] = []
	var current := ""
	for word: String in value.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if candidate.length() > max_chars and not current.is_empty():
			lines.append(current); current = word
			if lines.size() >= max_lines: break
		else: current = candidate
	if lines.size() < max_lines and not current.is_empty(): lines.append(current)
	return lines
