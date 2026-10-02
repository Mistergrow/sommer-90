class_name WorkbenchVersions
extends RefCounted
## Eine gemeinsame Quelle fuer Rechner, ROM, Systemdiskette und Werkbank-Look.
## Das verhindert Mischzustaende wie "A1200 + Kickstart 3.0 + Werkbank 1.3".

const DATA_PATH := "res://data/workbench_versions.json"
const MACHINE_RANK := {
	"amiga_500": 0,
	"amiga_600": 1,
	"amiga_1200": 2,
}
static var _catalog: Dictionary = {}


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_catalog = parsed
	return _catalog


static func profile(profile_id: String) -> Dictionary:
	var profiles: Dictionary = catalog().get("profiles", {})
	var fallback := str(catalog().get("default_profile", "wb13"))
	return (profiles.get(profile_id, profiles.get(fallback, {})) as Dictionary).duplicate(true)


static func native_id(computer_model := "") -> String:
	var model := computer_model
	if model.is_empty():
		model = _active_model()
	if model == "amiga_1200" and _has_hardware("amigaos_31_upgrade"):
		return "wb31"
	var defaults: Dictionary = catalog().get("computer_defaults", {})
	return str(defaults.get(model, catalog().get("default_profile", "wb13")))


static func active_id() -> String:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var ui := (loop as SceneTree).root.get_node_or_null("/root/UIManager")
		if ui != null:
			var selected := str(ui.get("workbench_profile_id"))
			if not selected.is_empty() and catalog().get("profiles", {}).has(selected):
				return selected
	return native_id()


static func active() -> Dictionary:
	return profile(active_id())


## Die internen wb*-IDs und historischen Kompatibilitätsprofile bleiben stabil.
## Spielerisch sichtbar ist jedoch ausschließlich unsere eigene Systemmarke.
static func localized_brand() -> String:
	return Loc.t("brand.sommerbench", "Sommerbench")


static func localized_name(profile_id := "") -> String:
	var cfg := profile(profile_id if not profile_id.is_empty() else active_id())
	return Loc.t("brand.sommerbench_version", "Sommerbench %s") % str(
		cfg.get("release", "1.3"))


static func localized_desktop_label(profile_id := "") -> String:
	var cfg := profile(profile_id if not profile_id.is_empty() else active_id())
	return Loc.t("brand.sommerbench_desktop", "Sommerbench%s") % str(
		cfg.get("release", "1.3"))


static func disk_profile_id(disk: Variant) -> String:
	if disk == null:
		return ""
	var mapping: Dictionary = catalog().get("disk_profiles", {})
	return str(mapping.get(str(disk.get("template_id")), ""))


static func bundled_template(hardware_id: String) -> String:
	var templates := bundled_templates(hardware_id)
	return templates[0] if not templates.is_empty() else ""


## Ein Rechner besitzt meist eine Bootdiskette; das 3.1-Upgrade ist dagegen
## ein physischer Sechsdiskettensatz. Beide Datenformen bleiben kompatibel.
static func bundled_templates(hardware_id: String) -> Array[String]:
	var configured: Variant = catalog().get("hardware_bundles", {}).get(hardware_id, "")
	var result: Array[String] = []
	if configured is Array:
		for template_id: Variant in configured:
			if not str(template_id).is_empty():
				result.append(str(template_id))
	elif not str(configured).is_empty():
		result.append(str(configured))
	return result


static func is_compatible(profile_id: String, computer_model := "") -> bool:
	if not (catalog().get("profiles", {}) as Dictionary).has(profile_id):
		return false
	var cfg := profile(profile_id)
	if cfg.is_empty():
		return false
	var required_hardware := str(cfg.get("requires_hardware", ""))
	if not required_hardware.is_empty() and not _has_hardware(required_hardware):
		return false
	var model := computer_model if not computer_model.is_empty() else _active_model()
	return int(MACHINE_RANK.get(model, -1)) >= int(MACHINE_RANK.get(
		str(cfg.get("minimum_machine", "amiga_500")), 99))


static func style() -> String:
	return str(active().get("style", "classic"))


static func is_modern() -> bool:
	return style() != "classic"


static func palette(profile_id := "") -> Array:
	var cfg := profile(profile_id if not profile_id.is_empty() else active_id())
	return (cfg.get("palette", ["#0055AA", "#FFFFFF", "#000020", "#FF8800"]) as Array).duplicate()


static func settings_key(profile_id := "") -> String:
	var id := profile_id if not profile_id.is_empty() else active_id()
	return "wb_colors" if id == "wb13" else "wb_colors_%s" % id


## Bildschirmmodi werden je Workbench-Generation getrennt gespeichert. Dadurch
## kann eine 1.3-Diskette weiterhin im sicheren PAL-Modus starten, während die
## fest installierte 3.x-Workbench den Multisync-Arbeitsplatz nutzt.
static func screenmode_settings_key(profile_id := "") -> String:
	var id := profile_id if not profile_id.is_empty() else active_id()
	return "wb_screen_mode" if id == "wb13" else "wb_screen_mode_%s" % id


## Testbarer Leistungsumfang eines Systemprofils. Alte Profile liefern
## absichtlich eine leere Liste statt erfundener 3.1-Funktionen.
static func features(profile_id := "") -> Array[String]:
	var cfg := profile(profile_id if not profile_id.is_empty() else active_id())
	var result: Array[String] = []
	for feature in cfg.get("features", []):
		result.append(str(feature))
	return result


static func provides(feature: String, profile_id := "") -> bool:
	return feature in features(profile_id)


static func drawer_entries(drawer: String, profile_id := "") -> Array[String]:
	var cfg := profile(profile_id if not profile_id.is_empty() else active_id())
	var result: Array[String] = []
	var drawers: Dictionary = cfg.get("drawers", {})
	for entry in drawers.get(drawer, []):
		result.append(str(entry))
	return result


static func system_disks(profile_id := "") -> Array[String]:
	var cfg := profile(profile_id if not profile_id.is_empty() else active_id())
	var result: Array[String] = []
	for disk in cfg.get("system_disks", []):
		result.append(str(disk))
	return result


static func _active_model() -> String:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var stats := (loop as SceneTree).root.get_node_or_null("/root/PlayerStats")
		if stats != null and stats.has_method("desk_model"):
			return str(stats.call("desk_model", "computer_model"))
	return "amiga_500"


static func _has_hardware(hardware_id: String) -> bool:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var stats := (loop as SceneTree).root.get_node_or_null("/root/PlayerStats")
		if stats != null and stats.has_method("has_hardware"):
			return bool(stats.call("has_hardware", hardware_id))
	return false
