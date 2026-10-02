class_name ScreenModeApp
extends WbApp
## Native Workbench-ScreenMode-Voreinstellung. Sie verwendet denselben
## Monitorvertrag wie Raumröhre, Live-Viewport und laufender Desktop.

const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")
const Versions := preload("res://scripts/ui/workbench_versions.gd")

var _profile_id := "wb13"
var _monitor_id := "commodore_1084s"
var _computer_model := "amiga_500"
var _selected := "pal"
var _workspace: Dictionary = {}


func _init() -> void:
	app_title = Loc.t("ui.screenmode_app.title", "ScreenMode")
	app_bg = Color8(30, 33, 38)
	app_bar = Color8(48, 82, 126)
	app_accent = Color8(245, 164, 48)


func _build_app() -> void:
	_profile_id = Versions.active_id()
	_monitor_id = str(PlayerStats.desk_model("monitor_model"))
	_computer_model = str(PlayerStats.desk_model("computer_model"))
	_selected = str(SettingsManager.value(settings_key()))
	if _selected not in ["auto", "pal", "best"]:
		_selected = "auto"
	_refresh_workspace()
	add_button(Loc.t("ui.screenmode_app.pal", "PAL ORIGINAL"),
		Rect2(28, 304, 150, 34), select_mode.bind("pal"), app_accent)
	add_button(Loc.t("ui.screenmode_app.best", "BESTMÖGLICH"),
		Rect2(188, 304, 150, 34), select_mode.bind("best"), app_accent)
	add_button(Loc.t("ui.screenmode_app.save", "SPEICHERN"),
		Rect2(430, 304, 90, 34), save_selection, Color8(74, 158, 92))
	add_button(Loc.t("ui.screenmode_app.cancel", "ABBRECHEN"),
		Rect2(530, 304, 82, 34), close_app, Color8(114, 120, 130))


func settings_key() -> String:
	return Versions.screenmode_settings_key(_profile_id)


func selected_mode() -> String:
	return _selected


func current_workspace() -> Dictionary:
	return _workspace.duplicate(true)


func select_mode(mode_id: String) -> void:
	if mode_id not in ["pal", "best"]:
		return
	_selected = mode_id
	_refresh_workspace()
	queue_redraw()


func save_selection() -> void:
	SettingsManager.set_value(settings_key(), _selected)
	UIManager.toast(Loc.t("ui.screenmode_app.saved",
		"ScreenMode gespeichert: %s.") % _mode_label())
	close_app()


func _refresh_workspace() -> void:
	_workspace = MonitorProfile.workbench_workspace(
		_profile_id, _monitor_id, _computer_model, _selected)


func _mode_label() -> String:
	match str(_workspace.get("actual_mode", "pal")):
		"productivity":
			return Loc.t("ui.screenmode_app.mode_productivity", "Productivity")
		"best":
			return Loc.t("ui.screenmode_app.mode_best", "Best Non-Interlaced")
	return Loc.t("ui.screenmode_app.mode_pal", "PAL: High Res")


func _resolution(values: Variant) -> String:
	if values is Array and (values as Array).size() >= 2:
		return "%d × %d" % [int(values[0]), int(values[1])]
	return "640 × 256"


func _limitation_text() -> String:
	match str(_workspace.get("limitation", "")):
		"monitor_incompatible":
			return Loc.t("ui.screenmode_app.limit_monitor",
				"Der Monitor ist für diesen Rechner nicht freigegeben; PAL bleibt sicher.")
		"chipset_limited":
			return Loc.t("ui.screenmode_app.limit_chipset",
				"Das Chipset begrenzt den angeschlossenen Monitor auf PAL.")
		"workbench_limited":
			return Loc.t("ui.screenmode_app.limit_workbench",
				"Diese Workbench-Version unterstützt den besten Monitormodus noch nicht.")
		"best_equals_pal":
			match str(_workspace.get("chipset", "OCS")):
				"ECS":
					return Loc.t("ui.screenmode_app.limit_same_ecs",
						"ECS-Vorteil: mit 1942-Multisync Productivity 640 × 480.")
				"AGA":
					return Loc.t("ui.screenmode_app.limit_same_aga",
						"AGA-Vorteil: mit 1942/17-Zoll bis 800 × 600 und 256 Farben.")
				_:
					return Loc.t("ui.screenmode_app.limit_same_ocs",
						"OCS bleibt PAL; ECS-/AGA-Bildschirmmodi sind nicht verfügbar.")
		"productivity_color_limit":
			return Loc.t("ui.screenmode_app.limit_colors",
				"ECS-Productivity erreicht mehr Zeilen, aber höchstens vier Farben.")
	if str(_workspace.get("chipset", "OCS")) == "AGA":
		return Loc.t("ui.screenmode_app.limit_none_aga",
			"AGA aktiv: größere Arbeitsfläche und bis zu 256 Bildschirmfarben.")
	return Loc.t("ui.screenmode_app.limit_none",
		"Monitor und Chipset liefern den gewählten Modus ohne Fallback.")


func _content(font: Font) -> void:
	text(font, Loc.t("ui.screenmode_app.heading", "BILDSCHIRMMODUS"),
		28, 52, 15, Color8(245, 164, 48))
	text(font, "%s · %s · %s" % [
		str(_workspace.get("chipset", "OCS")),
		str(_workspace.get("monitor_name", _monitor_id)),
		_profile_id.to_upper()],
		28, 76, 10, Color8(215, 225, 234))

	rect(28, 92, 584, 76, Color8(12, 17, 23))
	rect_line(28, 92, 584, 76, Color8(112, 160, 208))
	text(font, Loc.t("ui.screenmode_app.active", "AKTIV: %s") % _mode_label(),
		44, 119, 13, Color8(112, 232, 132))
	text(font, "%s · %d %s · %d × %d %s" % [
		_resolution(_workspace.get("resolution", [640, 256])),
		int(_workspace.get("colors", 4)),
		Loc.t("ui.screenmode_app.colors", "Farben"),
		int(_workspace.get("visible_columns", 80)),
		int(_workspace.get("visible_rows", 25)),
		Loc.t("ui.screenmode_app.characters", "Zeichen")],
		44, 148, 11, Color8(238, 240, 244))

	text(font, Loc.t("ui.screenmode_app.limits", "HARDWARE-GRENZEN"),
		28, 194, 10, Color8(112, 180, 236))
	text(font, Loc.t("ui.screenmode_app.non_interlaced", "Flimmerfrei maximal: %s") %
		_resolution(_workspace.get("maximum_non_interlaced", [640, 256])),
		44, 218, 10, Color8(222, 228, 234))
	text(font, Loc.t("ui.screenmode_app.absolute", "Monitor absolut: %s") %
		_resolution(_workspace.get("maximum", [640, 512])),
		44, 238, 10, Color8(222, 228, 234))
	text(font, Loc.t("ui.screenmode_app.color_limit", "Chipset-/Bandbreitenlimit: %d Farben") %
		int(_workspace.get("color_cap", 4)),
		44, 258, 10, Color8(222, 228, 234))
	text(font, _limitation_text(), 44, 282, 9,
		Color8(255, 198, 92) if not str(_workspace.get("limitation", "")).is_empty()
			else Color8(126, 218, 148))
	text(font, Loc.t("ui.screenmode_app.footer",
		"Mehr Fläche statt Skin-Wechsel; die historische Workbench-Palette bleibt erhalten."),
		28, 374, 9, Color8(190, 198, 206))
