class_name Workbench31ToolApp
extends WbApp
## Gemeinsame AAA-Workbench-Shell fuer die fehlenden System-3.1-Werkzeuge.
## Logik und Testvertrag liegen in Workbench31Runtime.

const Runtime := preload("res://scripts/ui/workbench31_runtime.gd")
const ActionEngine := preload("res://scripts/util/action_execution_engine.gd")

var tool_id := ""
var _runtime: Workbench31Runtime
var _action_engine
var _last_result: Dictionary = {}


func _init() -> void:
	app_bg = Color8(149, 149, 149)
	app_bar = Color8(49, 90, 156)
	app_accent = Color8(240, 160, 32)


func _build_app() -> void:
	_ensure_execution()
	app_title = str(_runtime.definition.get("title", "Workbench 3.1 Tool"))
	var actions := _runtime.actions()
	for i in actions.size():
		var row: Array = actions[i]
		add_button(str(row[1]), Rect2(24 + i * 152, 326, 140, 28),
			_execute.bind(str(row[0])), app_accent)
	add_button("BESTÄTIGEN", Rect2(500, 326, 116, 28), _confirm, Color8(244, 164, 66))


func capability_contract() -> Dictionary:
	return _runtime.definition.duplicate(true) if _runtime != null else \
		Runtime.definition_for(tool_id)


func execute_action(action_id: String, confirm := false) -> Dictionary:
	_ensure_execution()
	_last_result = _action_engine.execute(action_id, confirm)
	queue_redraw()
	return _last_result.duplicate(true)


func execution_snapshot() -> Dictionary:
	_ensure_execution()
	return _action_engine.state_snapshot()


func _ensure_execution() -> void:
	if _runtime == null:
		_runtime = Runtime.new()
		_runtime.setup(tool_id)
	if _action_engine == null:
		_action_engine = ActionEngine.new().configure(
			Callable(self, "_perform_runtime_action"), "workbench31/%s" % tool_id)


func _perform_runtime_action(action_id: String, confirm: bool) -> Dictionary:
	return _runtime.action(action_id, confirm)


func _pending_action_id() -> String:
	return _action_engine.pending_action() if _action_engine != null else ""


func state_snapshot() -> Dictionary:
	return _runtime.state_snapshot() if _runtime != null else {}


func _execute(action_id: String) -> void:
	var result := execute_action(action_id)
	UIManager.toast(str(result.get("message", "Keine Rückmeldung.")))


func _confirm() -> void:
	if _pending_action_id().is_empty():
		UIManager.toast(Loc.t("ui.workbench31_tool_app.keine_schreibende_aktion_wartet_auf_bestatigung", "Keine schreibende Aktion wartet auf Bestätigung."))
		return
	var result: Dictionary = _action_engine.confirm_pending()
	_last_result = result
	queue_redraw()
	UIManager.toast(str(result.get("message", "Aktion abgebrochen.")))


func _content(font: Font) -> void:
	if _runtime == null:
		return
	text(font, str(_runtime.definition.get("summary", "")), 24, 46, 12, Color8(15, 20, 28))
	rect(24, 64, 592, 238, Color8(22, 27, 34))
	rect_line(24, 64, 592, 238, Color8(255, 255, 255))
	var state := _runtime.state_snapshot()
	text(font, "WORKBENCH 3.1 · DATATYPES · LOCALE · COMMODITIES", 38, 86, 10,
		Color8(240, 160, 32))
	var y := 112.0
	for line in _runtime.history:
		text(font, "> " + str(line), 40, y, 11, Color8(218, 226, 230))
		y += 24
	text(font, "STATUS", 40, 244, 10, Color8(120, 180, 240))
	text(font, "Aktion: %s · Revision: %d · Gesichert: %s" % [
		str(state.get("last_action", "keine")), int(state.get("revision", 0)),
		"JA" if bool(state.get("saved", false)) else "NEIN"],
		128, 244, 10, Color8(220, 230, 240))
	if not _pending_action_id().is_empty():
		text(font, "SCHREIBSCHUTZ: Aktion wartet auf BESTÄTIGEN.", 40, 278, 11,
			Color8(255, 180, 70))
	text(font, "Alle Schreiboperationen werden erst nach einer ausdrücklichen Wahl ausgeführt.",
		24, 378, 9, Color8(25, 30, 38))
