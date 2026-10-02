extends RefCounted
## Gemeinsamer, datengetriebener Monitorvertrag fuer Raumroehre, Live-Viewport
## und Workbench-Konsumenten. Bewusst ohne class_name: parallele Headless-Tests
## duerfen nicht vom globalen Klassen-Cache abhaengen.

const DATA_PATH := "res://data/monitors.json"
const NATIVE_WORKBENCH := {
	"amiga_500": "wb13",
	"amiga_600": "wb205",
	"amiga_1200": "wb30",
}
const WB3_PROFILES := ["wb30", "wb31"]

static var _data: Dictionary = {}


static func data(force_reload := false) -> Dictionary:
	if force_reload or _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"models": {}}
	return _data.duplicate(true)


static func active_model_id() -> String:
	if Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		var room_manager := tree.root.get_node_or_null("/root/RoomManager")
		if room_manager != null and room_manager.has_method("active_device_model"):
			var selected := str(room_manager.call("active_device_model", "monitor_model"))
			if not selected.is_empty():
				return selected
	return "commodore_1084s"


static func active_computer_model() -> String:
	if Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		var room_manager := tree.root.get_node_or_null("/root/RoomManager")
		if room_manager != null and room_manager.has_method("active_device_model"):
			var selected := str(room_manager.call("active_device_model", "computer_model"))
			if not selected.is_empty():
				return selected
	return "amiga_500"


static func profile_for_model(model_id: String) -> Dictionary:
	var models: Dictionary = data().get("models", {})
	for value: Variant in models.values():
		if value is Dictionary and str(value.get("model_id", "")) == model_id:
			return (value as Dictionary).duplicate(true)
	return (models.get("default", {}) as Dictionary).duplicate(true)


static func profile_for_asset(source_asset_stem: String) -> Dictionary:
	var key := source_asset_stem.to_upper()
	var version_at := key.rfind("_V")
	if version_at > 0:
		key = key.substr(0, version_at)
	var models: Dictionary = data().get("models", {})
	return (models.get(key, models.get("default", {})) as Dictionary).duplicate(true)


static func active_profile() -> Dictionary:
	return profile_for_model(active_model_id())


## Normalisierte, asset-relative Flaeche eines sichtbaren Monitorbestandteils.
## `screen` bleibt mit dem historischen screen_frac kompatibel; physische
## Bedienelemente liegen unter controls. Alle Raum-Hotspots und Vorschauen
## lesen damit denselben kalibrierbaren Vertrag.
static func region_frac(model_id: String, region_id: String) -> Rect2:
	var profile := profile_for_model(model_id)
	var values: Variant = profile.get("screen_frac", []) if region_id == "screen" \
		else (profile.get("controls", {}) as Dictionary).get(region_id, [])
	if not values is Array or (values as Array).size() < 4:
		return Rect2()
	var a := values as Array
	var x := clampf(float(a[0]), 0.0, 1.0)
	var y := clampf(float(a[1]), 0.0, 1.0)
	var w := clampf(float(a[2]), 0.0, 1.0 - x)
	var h := clampf(float(a[3]), 0.0, 1.0 - y)
	return Rect2(x, y, w, h)


static func region_rect(model_id: String, region_id: String,
		model_rect: Rect2) -> Rect2:
	var normalized := region_frac(model_id, region_id)
	if normalized.size.x <= 0.0 or normalized.size.y <= 0.0:
		return Rect2()
	return Rect2(model_rect.position + normalized.position * model_rect.size,
		normalized.size * model_rect.size)


static func workspace(model_id := "") -> Dictionary:
	var profile := active_profile() if model_id.is_empty() else profile_for_model(model_id)
	return (profile.get("workspace", {}) as Dictionary).duplicate(true)


## Einstellungsschluessel bleiben wie die Paletten pro Workbench-Version
## getrennt. So veraendert ein Productivity-Versuch unter 2.05 nicht spaeter
## unbemerkt die nostalgische 1.3-Ausgabe.
static func screen_mode_settings_key(profile_id: String) -> String:
	return "wb_screen_mode" if profile_id == "wb13" \
		else "wb_screen_mode_%s" % profile_id


## Historischer Workbench-Ausgabevertrag. Der Monitor allein schaltet keinen
## Modus frei: Rechner-Chipsatz, Workbench-Generation und angeforderter Modus
## muessen gemeinsam passen.
##
## requested:
##   auto/best = beste historisch gueltige Kombination verwenden
##   pal       = immer auf den sicheren 15-kHz-PAL-Arbeitsbereich begrenzen
static func workbench_workspace(profile_id: String, monitor_id := "",
		computer_model := "", requested := "auto") -> Dictionary:
	var wanted_monitor := active_model_id() if monitor_id.is_empty() else monitor_id
	var wanted_computer := active_computer_model() if computer_model.is_empty() else computer_model
	var wanted_profile := profile_id
	if wanted_profile.is_empty():
		wanted_profile = str(NATIVE_WORKBENCH.get(wanted_computer, "wb13"))
	var wanted_mode := requested.to_lower()
	if wanted_mode not in ["auto", "pal", "best"]:
		wanted_mode = "auto"

	var result := workspace(wanted_monitor)
	var monitor := profile_for_model(wanted_monitor)
	var supported: Array = monitor.get("supported_machine_models", [])
	result["compatible"] = supported.is_empty() or wanted_computer in supported
	result["computer_model"] = wanted_computer
	result["monitor_model"] = wanted_monitor
	result["monitor_id"] = wanted_monitor
	result["monitor_name"] = str(monitor.get("display_name", wanted_monitor))
	result["workbench_profile_id"] = wanted_profile
	result["profile_id"] = wanted_profile
	result["requested_screen_mode"] = wanted_mode
	result["requested"] = wanted_mode
	result["chipset"] = {
		"amiga_500": "OCS", "amiga_600": "ECS", "amiga_1200": "AGA",
	}.get(wanted_computer, "OCS")
	result["color_cap"] = 256 if wanted_computer == "amiga_1200" else 32
	result["palette_cap"] = 16777216 if wanted_computer == "amiga_1200" else 4096
	result["colors"] = 4
	result["productivity_mode"] = false
	result["display_mode"] = "pal"
	result["actual_mode"] = "pal"
	result["hires_limited_by_computer"] = false
	result["hires_limited_by_workbench"] = false
	result["limitation"] = ""

	var wants_best := wanted_mode != "pal"
	var ecs_productivity := wants_best \
		and wanted_computer == "amiga_600" \
		and wanted_profile == "wb205" \
		and wanted_monitor == "commodore_1942"
	var aga_1942 := wants_best \
		and wanted_computer == "amiga_1200" \
		and wanted_profile in WB3_PROFILES \
		and wanted_monitor == "commodore_1942"
	var aga_17 := wants_best \
		and wanted_computer == "amiga_1200" \
		and wanted_profile in WB3_PROFILES \
		and wanted_monitor == "multisync_17"

	if ecs_productivity:
		result["recommended"] = [640, 480]
		result["resolution"] = [640, 480]
		result["maximum"] = [640, 480]
		result["maximum_non_interlaced"] = [640, 480]
		result["visible_columns"] = 80
		result["visible_rows"] = 30
		result["workspace_gain"] = 1.35
		result["live_canvas"] = [640, 400]
		result["desktop_canvas"] = [640, 480]
		result["color_cap"] = 4
		result["palette_cap"] = 64
		result["colors"] = 4
		result["productivity_mode"] = true
		result["display_mode"] = "productivity"
		result["actual_mode"] = "productivity"
		result["limitation"] = "productivity_color_limit"
	elif aga_1942 or aga_17:
		var hires_resolution := [800, 600] if aga_17 else [640, 480]
		result["recommended"] = hires_resolution.duplicate()
		result["resolution"] = hires_resolution.duplicate()
		result["maximum"] = hires_resolution.duplicate()
		result["maximum_non_interlaced"] = hires_resolution.duplicate()
		result["visible_columns"] = 100 if aga_17 else 80
		result["visible_rows"] = 37 if aga_17 else 30
		result["workspace_gain"] = 1.68 if aga_17 else 1.35
		result["live_canvas"] = [640, 480] if aga_17 else [640, 400]
		result["desktop_canvas"] = hires_resolution.duplicate()
		result["color_cap"] = 256
		result["palette_cap"] = 16777216
		result["colors"] = 256
		result["productivity_mode"] = true
		result["display_mode"] = "aga_hires"
		result["actual_mode"] = "best"
	else:
		# Gemeinsamer OCS/PAL-Basispfad. Auch ein A600 an einem 1942 bleibt
		# hier, wenn Workbench 1.3 gebootet wurde.
		result["recommended"] = [640, 256]
		result["resolution"] = [640, 256]
		result["maximum"] = [640, 512]
		result["maximum_non_interlaced"] = [640, 256]
		result["visible_columns"] = 80
		result["visible_rows"] = 25
		result["workspace_gain"] = 1.0
		result["live_canvas"] = [320, 200]
		result["desktop_canvas"] = [640, 400]
		if wants_best:
			result["hires_limited_by_computer"] = (
				wanted_computer == "amiga_500" and wanted_monitor == "commodore_1942"
			) or (
				wanted_monitor == "multisync_17" and wanted_computer != "amiga_1200"
			)
			result["hires_limited_by_workbench"] = (
				wanted_computer == "amiga_600"
				and wanted_monitor == "commodore_1942"
				and wanted_profile != "wb205"
			) or (
				wanted_computer == "amiga_1200"
				and wanted_monitor in ["commodore_1942", "multisync_17"]
				and wanted_profile not in WB3_PROFILES
			)
			if not bool(result["compatible"]):
				result["limitation"] = "monitor_incompatible"
			elif bool(result["hires_limited_by_computer"]):
				result["limitation"] = "chipset_limited"
			elif bool(result["hires_limited_by_workbench"]):
				result["limitation"] = "workbench_limited"
			else:
				result["limitation"] = "best_equals_pal"
	return result


## Bestehende Raum-/Live-Monitor-Aufrufer behalten ihre Signatur. Bei explizit
## uebergebenem Rechner gilt dessen Werks-Workbench; im echten Spiel gewinnt das
## aktuell gebootete Profil und seine gespeicherte Moduswahl.
static func effective_workspace(model_id := "", computer_model := "") -> Dictionary:
	var wanted_computer := active_computer_model() if computer_model.is_empty() else computer_model
	var wanted_profile := str(NATIVE_WORKBENCH.get(wanted_computer, "wb13"))
	var requested := "auto"
	if computer_model.is_empty() and Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		var ui := tree.root.get_node_or_null("/root/UIManager")
		if ui != null:
			var active_id := str(ui.get("workbench_profile_id"))
			if not active_id.is_empty():
				wanted_profile = active_id
		var settings := tree.root.get_node_or_null("/root/SettingsManager")
		if settings != null and settings.has_method("value"):
			requested = str(settings.call(
				"value", screen_mode_settings_key(wanted_profile)))
	return workbench_workspace(wanted_profile, model_id, wanted_computer, requested)


static func quality(model_id := "") -> Dictionary:
	var profile := active_profile() if model_id.is_empty() else profile_for_model(model_id)
	return (profile.get("quality", {}) as Dictionary).duplicate(true)


static func live_canvas_size(model_id := "", computer_model := "") -> Vector2i:
	var values: Array = effective_workspace(model_id, computer_model).get(
		"live_canvas", [320, 200])
	if values.size() < 2:
		return Vector2i(320, 200)
	return Vector2i(maxi(320, int(values[0])), maxi(200, int(values[1])))


static func asset_stem(model_id := "") -> String:
	var wanted := active_model_id() if model_id.is_empty() else model_id
	match wanted:
		"commodore_1901": return "MONITOR_COMMODORE_1901"
		"commodore_1942": return "MONITOR_COMMODORE_1942"
		"multisync_17": return "MONITOR_MULTISYNC_17"
		_: return "MONITOR_COMMODORE_1084S"


static func asset_path(model_id := "") -> String:
	var stem := asset_stem(model_id)
	for version in range(9, 0, -1):
		var path := "res://assets/backgrounds/layers/%s_V%02d.png" % [stem, version]
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			return path
	return ""


static func summary(model_id := "") -> String:
	var profile := active_profile() if model_id.is_empty() else profile_for_model(model_id)
	var area := effective_workspace(model_id)
	var recommended: Array = area.get("recommended", [640, 256])
	var quality_data: Dictionary = profile.get("quality", {})
	return "%s · %s %dx%d/%d FARBEN · SCHAERFE %d%% · INTERLACE %d%%" % [
		str(profile.get("display_name", "Standard-CRT")).to_upper(),
		str(area.get("chipset", "OCS")),
		int(recommended[0]), int(recommended[1]),
		int(area.get("color_cap", 32)),
		roundi(float(quality_data.get("sharpness", 0.7)) * 100.0),
		roundi(float(quality_data.get("interlace_artifact", 0.25)) * 100.0),
	]
