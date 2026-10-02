extends RefCounted
## Festplatten, Volumes und Ausbau-Uebersicht.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

const PsDefs := preload("res://scripts/autoload/player_stats_defs.gd")

static func active_hdd_description(mgr) -> String:
	match mgr.desk_model("computer_model"):
		"amiga_600":
			if mgr.has_hardware("a600_internal_hdd_120mb"):
				return "DH0: 120 MB IDE [intern]"
			return "DH0: 40 MB IDE [intern]" if mgr.has_hardware("a600_internal_hdd") else ""
		"amiga_1200":
			if mgr.has_hardware("a1200_internal_hdd_1200mb"):
				return "DH0: 1,2 GB IDE [intern]"
			if mgr.has_hardware("a1200_internal_hdd_420mb"):
				return "DH0: 420 MB IDE [intern]"
			return "DH0: 80 MB IDE [intern]" if mgr.has_hardware("a1200_internal_hdd") else ""
		_:
			if mgr.has_hardware("a500_accel_68030"):
				return "DH0: 120 MB SCSI [A530-Seitenwagen]"
			return "DH0: 20 MB A590 [extern]" if mgr.has_hardware("harddisk") else ""


## Festplattenzustand ---------------------------------------------------------


static func _storage_mb_for_model(mgr, model: String) -> int:
	match model:
		"amiga_500":
			if bool(mgr.hardware.get("a500_accel_68030", false)):
				return 120
			return 20 if bool(mgr.hardware.get("harddisk", false)) else 0
		"amiga_600":
			if bool(mgr.hardware.get("a600_internal_hdd_120mb", false)):
				return 120
			return 40 if bool(mgr.hardware.get("a600_internal_hdd", false)) else 0
		"amiga_1200":
			if bool(mgr.hardware.get("a1200_internal_hdd_1200mb", false)):
				return 1200
			if bool(mgr.hardware.get("a1200_internal_hdd_420mb", false)):
				return 420
			return 80 if bool(mgr.hardware.get("a1200_internal_hdd", false)) else 0
	return 0


static func _hdd_controller_for_model(mgr, model: String) -> String:
	match model:
		"amiga_500":
			return "Fast-SCSI (A530)" if bool(mgr.hardware.get("a500_accel_68030", false)) \
				else "XT-SCSI (A590)"
		"amiga_600":
			return "IDE 44-Pin intern"
		"amiga_1200":
			return "IDE 44-Pin intern · Fast-SCSI-II verfügbar" \
				if bool(mgr.hardware.get("a1200_scsi_module", false)) else "IDE 44-Pin intern"
	return ""


static func _native_hdd_profile(mgr, model: String) -> String:
	if model == "amiga_1200":
		return "wb31" if bool(mgr.hardware.get("amigaos_31_upgrade", false)) else "wb30"
	if model == "amiga_600":
		return "wb205"
	return "wb13"


static func _fresh_hdd_volume(mgr, model: String, capacity_kb: int) -> Dictionary:
	return {
		"schema": PsDefs.HDD_SCHEMA_VERSION,
		"device": "DH0",
		"model": model,
		"controller": _hdd_controller_for_model(mgr, model),
		"capacity_kb": capacity_kb,
		"partitioned": false,
		"formatted": false,
		"bootable": false,
		"user_configured": false,
		"installed_profile": "",
		"files": {},
	}


static func _sync_hdd_volumes(mgr) -> void:
	for model in ["amiga_500", "amiga_600", "amiga_1200"]:
		var capacity_kb := _storage_mb_for_model(mgr, model) * 1024
		if capacity_kb <= 0:
			continue
		var volume: Dictionary = mgr.hdd_volumes.get(model, {})
		if volume.is_empty():
			volume = _fresh_hdd_volume(mgr, model, capacity_kb)
		else:
			# Schema 1 existierte nur kurz in einer Zwischenversion und legte
			# Platten ungewollt automatisch formatiert/bootfähig an. Solche
			# Zustände dürfen auch aus einer noch laufenden Playtest-Session
			# nicht konserviert werden. Nur ein expliziter Abschlussmarker ist
			# eine belastbare Einrichtung.
			if int(volume.get("schema", 0)) < PsDefs.HDD_SCHEMA_VERSION \
					and not bool(volume.get("user_configured", false)):
				volume = _fresh_hdd_volume(mgr, model, capacity_kb)
			volume["schema"] = PsDefs.HDD_SCHEMA_VERSION
			volume["device"] = "DH0"
			volume["model"] = model
			volume["controller"] = _hdd_controller_for_model(mgr, model)
			# Ein Plattenupgrade vergrößert das bestehende Dateisystem. Es darf
			# weder Dateien noch den belegten Platz zurücksetzen.
			volume["capacity_kb"] = maxi(capacity_kb, int(volume.get("capacity_kb", 0)))
			if not (volume.get("files", {}) is Dictionary):
				volume["files"] = {}
			# Schema-0/erste DH0-Version hatte noch kein explizites
			# Partitionierungsflag. Ein bereits formatiertes, gespeichertes
			# Volume ist eingerichtet; eine bloße Hardwaremigration ist es nicht.
			if not volume.has("partitioned"):
				volume["partitioned"] = bool(volume.get("formatted", false))
		mgr.hdd_volumes[model] = volume


static func hdd_info(mgr, model := "") -> Dictionary:
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier der
	# ausdrueckliche Typ statt :=.
	var target: String = model if not model.is_empty() else mgr.desk_model("computer_model")
	if _storage_mb_for_model(mgr, target) <= 0:
		return {
			"available": false, "device": "DH0", "model": target,
			"capacity_kb": 0, "used_kb": 0, "free_kb": 0,
			"formatted": false, "bootable": false, "installed_profile": "",
			"controller": "",
		}
	_sync_hdd_volumes(mgr)
	var volume: Dictionary = mgr.hdd_volumes.get(target, {})
	var used := 0
	for entry: Variant in (volume.get("files", {}) as Dictionary).values():
		if entry is Dictionary:
			used += maxi(0, int(entry.get("size_kb", 0)))
	var capacity := int(volume.get("capacity_kb", _storage_mb_for_model(mgr, target) * 1024))
	var result := volume.duplicate(true)
	result["available"] = true
	result["used_kb"] = mini(used, capacity)
	result["free_kb"] = maxi(0, capacity - used) \
		if bool(volume.get("partitioned", false)) and bool(volume.get("formatted", false)) \
		else 0
	return result


static func hdd_is_usable(mgr) -> bool:
	var info := hdd_info(mgr)
	return bool(info.get("available", false)) \
		and bool(info.get("partitioned", false)) \
		and bool(info.get("formatted", false))


static func hdd_bootable(mgr) -> bool:
	var info := hdd_info(mgr)
	return bool(info.get("available", false)) and bool(info.get("partitioned", false)) \
		and bool(info.get("formatted", false)) \
		and bool(info.get("user_configured", false)) \
		and bool(info.get("bootable", false)) \
		and not str(info.get("installed_profile", "")).is_empty()


static func hdd_create_partition(mgr) -> Dictionary:
	_sync_hdd_volumes(mgr)
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier der
	# ausdrueckliche Typ statt :=.
	var model: String = mgr.desk_model("computer_model")
	var volume: Dictionary = mgr.hdd_volumes.get(model, {})
	if volume.is_empty():
		return {"ok": false, "code": "no_hdd", "message":
			Loc.t("sys.player_stats.hdd_not_detected", "Keine Festplatte erkannt.")}
	if bool(volume.get("partitioned", false)):
		return {"ok": false, "code": "already_partitioned",
			"message": Loc.t("sys.player_stats.hdd_already_partitioned",
				"DH0: ist bereits partitioniert.")}
	volume["partitioned"] = true
	volume["formatted"] = false
	volume["bootable"] = false
	volume["user_configured"] = false
	volume["installed_profile"] = ""
	volume["files"] = {}
	mgr.hdd_volumes[model] = volume
	mgr.stats_changed.emit()
	return {"ok": true, "code": "ok",
		"message": Loc.t("sys.player_stats.hdd_partition_created",
			"DH0: über die gesamte Platte angelegt; Neustart der Geometrie abgeschlossen.")}


static func hdd_format(mgr) -> Dictionary:
	_sync_hdd_volumes(mgr)
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier der
	# ausdrueckliche Typ statt :=.
	var model: String = mgr.desk_model("computer_model")
	var volume: Dictionary = mgr.hdd_volumes.get(model, {})
	if volume.is_empty():
		return {"ok": false, "code": "no_hdd", "message":
			Loc.t("sys.player_stats.hdd_not_detected", "Keine Festplatte erkannt.")}
	if not bool(volume.get("partitioned", false)):
		return {"ok": false, "code": "partition_required",
			"message": Loc.t("sys.player_stats.hdd_partition_required",
				"Zuerst die Partition DH0: anlegen.")}
	# Format ist absichtlich destruktiv: ein erneutes Formatieren entfernt
	# Programme und ein eventuell installiertes System.
	volume["formatted"] = true
	volume["bootable"] = false
	volume["user_configured"] = false
	volume["installed_profile"] = ""
	volume["files"] = {
		"Trashcan": {"size_kb": 8, "kind": "drawer"},
	}
	mgr.hdd_volumes[model] = volume
	mgr.stats_changed.emit()
	return {"ok": true, "code": "ok",
		"message": Loc.t("sys.player_stats.hdd_formatted",
			"DH0: mit FastFileSystem formatiert und als leer geprüft.")}


static func hdd_compatible_profiles(mgr) -> Array[String]:
	match mgr.desk_model("computer_model"):
		"amiga_500":
			return ["wb13"]
		"amiga_600":
			return ["wb205"]
		"amiga_1200":
			var result: Array[String] = ["wb30"]
			if mgr.has_hardware("amigaos_31_upgrade"):
				result.append("wb31")
			return result
	return []


static func hdd_recommended_profile(mgr) -> String:
	return _native_hdd_profile(mgr, mgr.desk_model("computer_model"))


static func hdd_install_system(mgr, profile_id: String) -> Dictionary:
	if profile_id not in hdd_compatible_profiles(mgr):
		return {"ok": false, "code": "incompatible",
			"message": Loc.t("sys.player_stats.hdd_system_incompatible",
				"%s ist mit diesem Amiga bzw. seinem ROM nicht kompatibel.") % profile_id}
	_sync_hdd_volumes(mgr)
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier der
	# ausdrueckliche Typ statt :=.
	var model: String = mgr.desk_model("computer_model")
	var volume: Dictionary = mgr.hdd_volumes.get(model, {})
	if not bool(volume.get("partitioned", false)) \
			or not bool(volume.get("formatted", false)):
		return {"ok": false, "code": "format_required",
			"message": Loc.t("sys.player_stats.hdd_format_required",
				"DH0: muss zuerst partitioniert und formatiert werden.")}
	var files: Dictionary = volume.get("files", {})
	var old_profile := str(volume.get("installed_profile", ""))
	var old_path := "System/%s" % old_profile
	var old_size := 0
	if files.get(old_path) is Dictionary:
		old_size = int((files[old_path] as Dictionary).get("size_kb", 0))
	var required := int(PsDefs.HDD_SYSTEM_KB.get(profile_id, 1700))
	var info := hdd_info(mgr, model)
	if int(info.get("free_kb", 0)) + old_size < required + 672:
		return {"ok": false, "code": "disk_full",
			"message": Loc.t("sys.player_stats.hdd_system_no_space",
				"DH0: hat nicht genug freien Platz für das System.")}
	if not old_profile.is_empty():
		files.erase(old_path)
	for drawer in ["S", "C", "Devs", "Libs", "Prefs", "Utilities"]:
		files[drawer] = {"size_kb": 64 if drawer in ["S", "Prefs"] else 128,
			"kind": "drawer"}
	files["System/%s" % profile_id] = {"size_kb": required, "kind": "system"}
	volume["files"] = files
	volume["installed_profile"] = profile_id
	volume["bootable"] = true
	volume["user_configured"] = true
	volume["schema"] = PsDefs.HDD_SCHEMA_VERSION
	mgr.hdd_volumes[model] = volume
	mgr.stats_changed.emit()
	return {"ok": true, "code": "ok",
		"message": Loc.t("sys.player_stats.hdd_system_installed",
			"%s vollständig auf DH0: installiert; Bootblock geprüft.") % profile_id}


static func hdd_write_file(mgr, path: String, size_kb: int, metadata := {}) -> bool:
	if path.strip_edges().is_empty() or size_kb < 0 or not hdd_is_usable(mgr):
		return false
	_sync_hdd_volumes(mgr)
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier der
	# ausdrueckliche Typ statt :=.
	var model: String = mgr.desk_model("computer_model")
	var volume: Dictionary = mgr.hdd_volumes.get(model, {})
	var files: Dictionary = volume.get("files", {})
	var old_size := 0
	if files.get(path) is Dictionary:
		old_size = maxi(0, int((files[path] as Dictionary).get("size_kb", 0)))
	var info := hdd_info(mgr, model)
	if int(info.get("free_kb", 0)) + old_size < size_kb:
		return false
	var entry: Dictionary = (metadata as Dictionary).duplicate(true)
	entry["size_kb"] = size_kb
	files[path] = entry
	volume["files"] = files
	mgr.hdd_volumes[model] = volume
	mgr.stats_changed.emit()
	return true


static func hdd_delete_file(mgr, path: String) -> bool:
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier der
	# ausdrueckliche Typ statt :=.
	var model: String = mgr.desk_model("computer_model")
	var volume: Dictionary = mgr.hdd_volumes.get(model, {})
	var files: Dictionary = volume.get("files", {})
	if not files.has(path) or str((files[path] as Dictionary).get("kind", "")) == "system":
		return false
	files.erase(path)
	volume["files"] = files
	mgr.hdd_volumes[model] = volume
	mgr.stats_changed.emit()
	return true


static func active_cdrom_available(mgr) -> bool:
	match mgr.desk_model("computer_model"):
		"amiga_500":
			return mgr.has_hardware("cdrom") or mgr.has_hardware("a500_scsi_cdrom")
		"amiga_1200":
			return mgr.has_hardware("a1200_scsi_module") \
				and mgr.has_hardware("a1200_scsi_cdrom")
	return false


static func expansion_summary(mgr) -> Array[String]:
	var result: Array[String] = []
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier der
	# ausdrueckliche Typ statt :=.
	var computer: String = mgr.desk_model("computer_model")
	if computer == "amiga_1200":
		if mgr.has_hardware("a1200_accel_68060"):
			result.append("68060/50 + 64 MB Fast-RAM")
		elif mgr.has_hardware("a1200_accel_68040"):
			result.append("68040/40 + 32 MB Fast-RAM")
		elif mgr.has_hardware("a1200_accel_68030_50"):
			result.append("68030/50 + 32 MB Fast-RAM")
		elif mgr.has_hardware("a1200_accel_68030"):
			result.append("68030/40 + 16 MB Fast-RAM")
		elif mgr.has_hardware("a1200_fast_ram_8mb"):
			result.append("8 MB Fast-RAM + RTC")
		elif mgr.has_hardware("a1200_fast_ram_4mb"):
			result.append("4 MB Fast-RAM + RTC")
		elif mgr.has_hardware("a1200_pcmcia_sram_4mb"):
			result.append("4 MB PCMCIA-SRAM")
		if mgr.active_storage_mb() > 0:
			result.append(active_hdd_description(mgr).trim_prefix("DH0: "))
		if mgr.has_hardware("a1200_scsi_module"):
			result.append("Fast-SCSI-II-Modul")
		if active_cdrom_available(mgr):
			result.append("4× SCSI-CD-ROM")
		if mgr.has_hardware("amigaos_31_upgrade"):
			result.append("Kickstart/Workbench 3.1")
	elif computer == "amiga_600":
		if mgr.has_hardware("a600_accel_68030"):
			result.append("68030/33 + 32 MB Fast-RAM")
		elif mgr.has_hardware("a600_pcmcia_sram_4mb"):
			result.append("4 MB PCMCIA-SRAM")
		elif mgr.has_hardware("a600_pcmcia_sram_2mb"):
			result.append("2 MB PCMCIA-SRAM")
		if mgr.has_hardware("a600_chipram_2mb"):
			result.append("A601 · 2 MB Chip-RAM")
		if mgr.active_storage_mb() > 0:
			result.append(active_hdd_description(mgr).trim_prefix("DH0: "))
	else:
		if mgr.has_hardware("a500_accel_68030"):
			result.append("68030/40 + 8 MB Fast-RAM")
		elif mgr.has_hardware("ram_4mb"):
			result.append("4-MB-Speicherausbau")
		elif mgr.has_hardware("chipram_2mb_mod"):
			result.append("2-MB-Chip-RAM-Umbau")
		elif mgr.has_hardware("ram_1mb"):
			result.append("A501 · 512 KB Slow-RAM")
		if mgr.active_storage_mb() > 0:
			result.append(active_hdd_description(mgr).trim_prefix("DH0: "))
		if active_cdrom_available(mgr):
			result.append("SCSI-/A570-CD-ROM")
	if mgr.has_hardware("external_drive"):
		result.append("DF1: extern")
	return result
