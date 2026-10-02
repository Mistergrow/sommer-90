class_name HddSetupRuntime
extends RefCounted
## Testbarer Lebenszyklus einer Amiga-Festplatte. Hardwareerkennung,
## Partitionierung, Formatierung und Betriebssysteminstallation sind bewusst
## getrennte Schritte. Die UI ist nur eine Ansicht auf diesen Vertrag.

const PROFILE_MEDIA := {
	"wb13": ["disk_workbench_13"],
	"wb205": ["disk_workbench_205"],
	"wb30": ["disk_workbench_30"],
	"wb31": [
		"disk_workbench_31_install", "disk_workbench_31",
		"disk_workbench_31_extras", "disk_workbench_31_storage",
		"disk_workbench_31_locale", "disk_workbench_31_fonts",
	],
}
var selected_profile := ""
var history: Array[String] = []


func setup() -> void:
	var profiles := available_profiles()
	var stats := _autoload("PlayerStats")
	var recommended := str(stats.call("hdd_recommended_profile")) if stats != null else ""
	selected_profile = recommended if recommended in profiles else \
		(profiles.back() if not profiles.is_empty() else "")
	history = ["Controller scannt den Bus.", status_line()]


func available_profiles() -> Array[String]:
	var result: Array[String] = []
	var stats := _autoload("PlayerStats")
	if stats == null:
		return result
	for profile_id: String in stats.call("hdd_compatible_profiles"):
		if _has_install_media(profile_id):
			result.append(profile_id)
	return result


func missing_media(profile_id: String) -> Array[String]:
	var result: Array[String] = []
	var disks := _autoload("DiskManager")
	for template_id: String in PROFILE_MEDIA.get(profile_id, []):
		if disks == null or not bool(disks.call("has_template", template_id)):
			result.append(template_id)
	return result


func status_line() -> String:
	var stats := _autoload("PlayerStats")
	var info: Dictionary = stats.call("hdd_info") if stats != null else {}
	if not bool(info.get("available", false)):
		return Loc.t("ui.hdd_setup_runtime.status_no_hdd", "KEINE FESTPLATTE")
	if not bool(info.get("partitioned", false)):
		return Loc.t("ui.hdd_setup_runtime.status_raw", "ERKANNT · ROH · KEINE PARTITION")
	if not bool(info.get("formatted", false)):
		return Loc.t("ui.hdd_setup_runtime.status_ndos", "DH0 ANGELEGT · NDOS · FORMATIERUNG NÖTIG")
	if not bool(info.get("bootable", false)):
		return Loc.t("ui.hdd_setup_runtime.status_empty", "DH0 FFS · LEER · SYSTEMINSTALLATION NÖTIG")
	return Loc.t("ui.hdd_setup_runtime.status_bootable", "DH0 FFS · BOOTFÄHIG · %s") % profile_name(
		str(info.get("installed_profile", "")))


func action(action_id: String, confirm := false) -> Dictionary:
	var result: Dictionary
	var stats := _autoload("PlayerStats")
	if stats == null:
		return _result(false, "system_unavailable",
			Loc.t("ui.hdd_setup_runtime.stats_not_ready", "PlayerStats ist nicht bereit."))
	match action_id:
		"partition":
			result = stats.call("hdd_create_partition")
		"format":
			if not confirm:
				return _result(false, "confirmation_required",
					Loc.t("ui.hdd_setup_runtime.confirm_format",
						"FORMATIEREN löscht DH0:. Zum Ausführen erneut bestätigen."), true)
			result = stats.call("hdd_format")
		"select_system":
			var profiles := available_profiles()
			if profiles.is_empty():
				return _result(false, "missing_media",
					Loc.t("ui.hdd_setup_runtime.no_compatible_disk",
						"Keine kompatible Systemdiskette in der Diskettenbox."))
			var index := profiles.find(selected_profile)
			selected_profile = profiles[(index + 1) % profiles.size()]
			result = {"ok": true, "code": "ok",
				"message": Loc.t("ui.hdd_setup_runtime.target_selected",
					"%s als Installationsziel gewählt.") % profile_name(selected_profile)}
		"verify_system":
			if selected_profile.is_empty() or selected_profile not in available_profiles():
				return _result(false, "missing_media",
					Loc.t("ui.hdd_setup_runtime.no_compatible_disk",
						"Keine kompatible Systemdiskette in der Diskettenbox."))
			result = {"ok": true, "code": "ok",
				"message": Loc.t("ui.hdd_setup_runtime.target_verified",
					"%s geprüft und als Installationsziel beibehalten.") %
					profile_name(selected_profile)}
		"install":
			if selected_profile.is_empty():
				return _result(false, "missing_media",
					Loc.t("ui.hdd_setup_runtime.get_system_disk",
						"Zuerst eine kompatible Systemdiskette beschaffen."))
			var missing := missing_media(selected_profile)
			if not missing.is_empty():
				return _result(false, "missing_media",
					Loc.t("ui.hdd_setup_runtime.media_missing",
						"Installationssatz unvollständig: %d Medium/Medien fehlen.") % missing.size())
			if not confirm:
				return _result(false, "confirmation_required",
					Loc.t("ui.hdd_setup_runtime.confirm_install",
						"%s jetzt vollständig auf DH0: installieren?") %
					profile_name(selected_profile), true)
			result = stats.call("hdd_install_system", selected_profile)
			if bool(result.get("ok", false)):
				var library := _autoload("ProgramLibrary")
				if library != null and library.has_method("sync_installed_to_hdd"):
					var synced: Dictionary = library.call("sync_installed_to_hdd")
					result["message"] = "%s %s" % [
						str(result.get("message", "")),
						str(synced.get("message", ""))]
					if not bool(synced.get("ok", false)):
						result["code"] = "partial_program_sync"
						result["programs_missing_space"] = synced.get("missing_space", [])
		"boot":
			var ui := _autoload("UIManager")
			var ok := ui != null and bool(ui.call("boot_from_hdd"))
			result = {"ok": ok, "code": "ok" if ok else "not_bootable",
				"message": Loc.t("ui.hdd_setup_runtime.booting", "DH0: startet.")
					if ok else Loc.t("ui.hdd_setup_runtime.not_bootable",
						"DH0: ist noch nicht bootfähig.")}
		_:
			return _result(false, "unknown_action",
				Loc.t("ui.hdd_setup_runtime.unknown_step", "Unbekannter Einrichtungsschritt."))
	var message := str(result.get("message", ""))
	if not message.is_empty():
		history.push_front(message)
		if history.size() > 5:
			history.resize(5)
	return _result(bool(result.get("ok", false)), str(result.get("code", "")), message)


func profile_name(profile_id: String) -> String:
	match profile_id:
		"wb13": return Loc.t("ui.hdd_setup_runtime.wb13", "Workbench 1.3")
		"wb205": return Loc.t("ui.hdd_setup_runtime.wb205", "Workbench 2.05")
		"wb30": return Loc.t("ui.hdd_setup_runtime.wb30", "Workbench 3.0")
		"wb31": return Loc.t("ui.hdd_setup_runtime.wb31", "Workbench 3.1")
	return profile_id


func selected_name() -> String:
	return profile_name(selected_profile) if not selected_profile.is_empty() \
		else Loc.t("ui.hdd_setup_runtime.no_medium", "KEIN KOMPATIBLES MEDIUM")


func _has_install_media(profile_id: String) -> bool:
	return missing_media(profile_id).is_empty()


func _result(ok: bool, code: String, message: String,
		confirmation_required := false) -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"message": message,
		"confirmation_required": confirmation_required,
		"selected_profile": selected_profile,
		"status": status_line(),
	}


static func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/" + node_name)
	return null
