class_name HddSetupApp
extends WbApp
## Geführtes HDToolBox-/Installer-Hommagefenster. Jeder Button entspricht einem
## echten, persistenten Schritt; Formatieren und Installieren verlangen einen
## zweiten, ausdrücklichen Klick auf BESTÄTIGEN.

const Runtime := preload("res://scripts/ui/hdd_setup_runtime.gd")
const ActionEngine := preload("res://scripts/util/action_execution_engine.gd")

var _runtime: HddSetupRuntime
var _action_engine
var _last_result: Dictionary = {}


func _init() -> void:
	app_bg = Color8(30, 34, 38)
	app_bar = Color8(42, 68, 112)
	app_accent = Color8(244, 164, 48)


func _build_app() -> void:
	app_title = Loc.t("ui.hdd_setup_app.title", "HDToolBox · DH0: EINRICHTUNG")
	_ensure_execution()
	_add_action_button("partition", Loc.t("ui.hdd_setup_app.partition", "1 PARTITION"),
		Rect2(18, 326, 108, 30), _execute.bind("partition"), app_accent)
	_add_action_button("format", Loc.t("ui.hdd_setup_app.format", "2 FORMAT"),
		Rect2(130, 326, 98, 30), _execute.bind("format"), app_accent)
	_add_action_button("verify_system",
		Loc.t("ui.hdd_setup_app.system_next", "3 SYSTEM PRÜFEN"),
		Rect2(232, 326, 134, 30), _execute.bind("verify_system"), app_accent)
	_add_action_button("install", Loc.t("ui.hdd_setup_app.install", "4 INSTALL"),
		Rect2(370, 326, 90, 30), _execute.bind("install"), app_accent)
	_add_action_button("confirm", Loc.t("ui.hdd_setup_app.confirm", "BESTÄTIGEN"),
		Rect2(464, 326, 96, 30), _confirm, Color8(200, 82, 48))
	_add_action_button("boot_dh0", Loc.t("ui.hdd_setup_app.boot_dh0", "BOOT DH0"),
		Rect2(564, 326, 60, 30), _execute.bind("boot"), Color8(78, 164, 92))
	_add_action_button("select_system",
		Loc.t("ui.hdd_setup_app.switch_system", "SYSTEM WECHSELN (OPT.)"),
		Rect2(352, 44, 144, 26), _execute.bind("select_system"), Color8(92, 104, 126))
	_add_action_button("boot_df0", Loc.t("ui.hdd_setup_app.boot_df0", "DF0: STARTDISK"),
		Rect2(500, 44, 116, 26), _boot_df0, Color8(80, 126, 190))


func _add_action_button(action_id: String, label: String, button_rect: Rect2,
		callback: Callable, color: Color) -> void:
	var widget := add_button(label, button_rect, callback, color)
	widget["action_id"] = action_id


func action_button(action_id: String) -> Button:
	for widget: Dictionary in _widgets:
		if str(widget.get("action_id", "")) == action_id:
			return widget.get("node") as Button
	return null


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
		_runtime.setup()
	if _action_engine == null:
		_action_engine = ActionEngine.new().configure(
			Callable(self, "_perform_runtime_action"), "hdd_setup")


func _perform_runtime_action(action_id: String, confirm: bool) -> Dictionary:
	return _runtime.action(action_id, confirm)


func _pending_action_id() -> String:
	return _action_engine.pending_action() if _action_engine != null else ""


func setup_state() -> Dictionary:
	return {
		"pending_action": _pending_action_id(),
		"selected_profile": _runtime.selected_profile if _runtime != null else "",
		"status": _runtime.status_line() if _runtime != null else "",
	}


func _execute(action_id: String) -> void:
	var result := execute_action(action_id)
	UIManager.toast(str(result.get("message", "")))
	if action_id == "boot" and bool(result.get("ok", false)):
		queue_free()


func _confirm() -> void:
	if _pending_action_id().is_empty():
		UIManager.toast(Loc.t("ui.hdd_setup_app.nothing_to_confirm",
			"Kein gefährlicher Schritt wartet auf Bestätigung."))
		return
	var result: Dictionary = _action_engine.confirm_pending()
	_last_result = result
	queue_redraw()
	UIManager.toast(str(result.get("message", "")))


func _boot_df0() -> void:
	UIManager.open_boot_selector()
	queue_free()


func _content(font: Font) -> void:
	if _runtime == null:
		return
	var info: Dictionary = PlayerStats.hdd_info()
	text(font, Loc.t("ui.hdd_setup_app.heading", "AMIGA-FESTPLATTEN-EINRICHTUNG"),
		24, 48, 13, Color8(244, 164, 48))
	text(font, "%s · %s" % [
		str(info.get("model", "")).to_upper().replace("_", " "),
		str(info.get("controller", "kein Controller"))],
		24, 72, 10, Color8(214, 224, 232))
	rect(24, 88, 592, 52, Color8(10, 15, 20))
	rect_line(24, 88, 592, 52, Color8(125, 170, 215))
	text(font, _runtime.status_line(), 38, 120, 12,
		Color8(106, 232, 132) if bool(info.get("bootable", false)) else Color8(255, 190, 72))
	text(font, Loc.t("ui.hdd_setup_app.capacity",
		"RAW: %d MB · NUTZBAR/FREI: %d KB · SYSTEM: %s") % [
		floori(float(info.get("capacity_kb", 0)) / 1024.0),
		int(info.get("free_kb", 0)),
		_runtime.selected_name()],
		24, 164, 10, Color8(255, 220, 116))
	text(font, Loc.t("ui.hdd_setup_app.flow", "ABLAUF"),
		24, 194, 10, Color8(112, 180, 236))
	text(font, Loc.t("ui.hdd_setup_app.step_partition",
		"1  DH0-Partition über den ganzen Datenträger anlegen"), 42, 216, 10, Color8(225, 230, 235))
	text(font, Loc.t("ui.hdd_setup_app.step_format",
		"2  DH0: als FastFileSystem formatieren (löscht den Inhalt)"), 42, 236, 10, Color8(225, 230, 235))
	text(font, Loc.t("ui.hdd_setup_app.step_media",
		"3  System prüfen; Wechsel oben ist optional"), 42, 256, 10, Color8(225, 230, 235))
	text(font, Loc.t("ui.hdd_setup_app.step_install",
		"4  Systemdateien kopieren und Bootblock verifizieren"), 42, 276, 10, Color8(225, 230, 235))
	if not _pending_action_id().is_empty():
		text(font, Loc.t("ui.hdd_setup_app.safety_stop",
			"SICHERHEITSSTOPP: %s wartet auf BESTÄTIGEN.") %
			_pending_action_id().to_upper(), 24, 306, 10, Color8(255, 106, 72))
	text(font, Loc.t("ui.hdd_setup_app.footer",
		"Die Platte bootet erst nach allen drei Einrichtungsschritten."),
		24, 382, 9, Color8(210, 218, 224))
