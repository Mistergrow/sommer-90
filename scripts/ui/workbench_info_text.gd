extends RefCounted
const Versions := preload("res://scripts/ui/workbench_versions.gd")

static func hdd_info(profile_id: String, format_kb: Callable) -> String:
	var info: Dictionary = PlayerStats.hdd_info()
	var compatible_profiles: Array[String] = PlayerStats.hdd_compatible_profiles()
	var profile_compatible := profile_id in compatible_profiles
	var installed_profile := str(info.get("installed_profile", ""))
	var installed_name := Loc.t("ui.werkbank_screen.no_system", "kein System")
	if not installed_profile.is_empty():
		installed_name = Versions.localized_name(installed_profile)
	var bootable_here := bool(info.get("bootable", false)) and profile_compatible
	var compatibility := Loc.t("ui.werkbank_screen.hdd_compatible",
		"mit dieser Sommerbench verwendbar")
	var recommendation := ""
	if not profile_compatible:
		compatibility = Loc.t("ui.werkbank_screen.hdd_not_compatible",
			"NICHT HDD-KOMPATIBEL")
		if PlayerStats.desk_model("computer_model") == "amiga_1200":
			recommendation = "\n\n" + Loc.t("ui.werkbank_screen.hdd_a1200_recommendation",
				"Empfehlung: Sommerbench 3.0 starten oder auf Kickstart/Sommerbench 3.1 aktualisieren.")
		else:
			var recommended_id := PlayerStats.hdd_recommended_profile()
			recommendation = "\n\n" + Loc.t("ui.werkbank_screen.hdd_recommendation",
				"Empfehlung: %s starten.") % str(
					Versions.localized_name(recommended_id))
	var body := Loc.t("ui.werkbank_screen.hdd_info_body_v2",
		"Gerät: DH0:\nController: %s\nKompatibilität: %s\nPartition: %s\nDateisystem: %s\nSystem auf Platte: %s\n\nRohkapazität: %s\nBelegt: %s\nFrei: %s\nBootfähig: %s") % [
		str(info.get("controller", "")),
		compatibility,
		Loc.t("ui.werkbank_screen.present", "vorhanden") if bool(info.get("partitioned", false))
			else Loc.t("ui.werkbank_screen.not_created", "nicht angelegt"),
		"Amiga FFS" if bool(info.get("formatted", false)) else "NDOS",
		installed_name,
		format_kb.call(int(info.get("capacity_kb", 0))),
		format_kb.call(int(info.get("used_kb", 0))),
		format_kb.call(int(info.get("free_kb", 0))),
		Loc.t("common.yes", "ja") if bootable_here else Loc.t("common.no", "nein"),
	]
	body += recommendation
	return body
