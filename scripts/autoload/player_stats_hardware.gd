extends RefCounted
## Hardwarebesitz und Speicherausbau.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

const PsDefs := preload("res://scripts/autoload/player_stats_defs.gd")

static func has_hardware(mgr, id: String) -> bool:
	return bool(mgr.hardware.get(id, false))


static func add_hardware(mgr, id: String) -> void:
	var is_new: bool = not mgr.hardware.get(id, false)
	mgr.hardware[id] = true
	match id:
		"computer_amiga_500": mgr.hardware["computer_model"] = "amiga_500"
		"computer_amiga_600":
			mgr.hardware["computer_model"] = "amiga_600"
		"computer_amiga_1200":
			mgr.hardware["computer_model"] = "amiga_1200"
		"monitor_commodore_1084s": mgr.hardware["monitor_model"] = "commodore_1084s"
		"monitor_commodore_1901": mgr.hardware["monitor_model"] = "commodore_1901"
		"monitor_commodore_1942": mgr.hardware["monitor_model"] = "commodore_1942"
		"monitor_multisync_17": mgr.hardware["monitor_model"] = "multisync_17"
		"modem": mgr.hardware["modem_model"] = "modem_2400"
		"modem_9600":
			mgr.hardware["modem"] = true
			mgr.hardware["modem_model"] = "modem_9600"
		"modem_14400":
			mgr.hardware["modem"] = true
			mgr.hardware["modem_model"] = "modem_14400"
		"dot_matrix": mgr.hardware["printer_model"] = "dot_matrix_9pin"
		"dot_matrix_24": mgr.hardware["printer_model"] = "dot_matrix_24_mono"
		"dot_matrix_24_color": mgr.hardware["printer_model"] = "dot_matrix_24_color"
		"color_printer": mgr.hardware["printer_model"] = "color_inkjet"
		"laser_printer": mgr.hardware["printer_model"] = "laser_mono"
		"stereo_component_cassette": mgr.hardware["stereo_model"] = "component_cassette"
		"stereo_compact_cd": mgr.hardware["stereo_model"] = "compact_cd"
		"stereo_dual_cd": mgr.hardware["stereo_model"] = "dual_cd"
		"ram_1mb":
			_apply_ram_profile(mgr, 1.0, 512, 512, 0, "a501_1mb")
		"chipram_2mb_mod":
			_apply_ram_profile(mgr, 2.0, 2048, 0, 0, "a500_chipram_2mb_mod")
		# Save-/Debug-Kompatibilität mit der früheren, historisch falschen ID.
		"ram_2mb":
			mgr.hardware["chipram_2mb_mod"] = true
			_apply_ram_profile(mgr, 2.0, 2048, 0, 0, "a500_chipram_2mb_mod")
		"ram_4mb":
			_apply_ram_profile(mgr, 4.0, 2048, 0, 2048, "a500_chip2_fast2")
		"a600_chipram_2mb":
			pass
		"a600_internal_hdd":
			pass
		"a600_internal_hdd_120mb":
			# Höhere Platte ersetzt die kleine physisch, wahrt aber den
			# bestehenden Boot-/Quest-Vertrag auf die Basis-ID.
			mgr.hardware["a600_internal_hdd"] = true
		# GDScript erlaubt keine mehrzeiligen match-Muster. Die Musterliste muss
		# auf einer Zeile bleiben, sonst schlaegt der Parser fehl — und
		# PlayerStats reisst als Autoload das halbe Projekt mit.
		"a600_pcmcia_sram_2mb", "a600_pcmcia_sram_4mb", "a600_accel_68030":
			pass
		"a1200_internal_hdd": pass
		"a1200_internal_hdd_420mb", "a1200_internal_hdd_1200mb":
			mgr.hardware["a1200_internal_hdd"] = true
		"a1200_fast_ram_4mb": pass
		"a1200_fast_ram_8mb": pass
		"a1200_accel_68030": pass
		"a1200_pcmcia_sram_4mb", "a1200_accel_68030_50", "a1200_accel_68040", "a1200_accel_68060", "a1200_scsi_module", "a1200_scsi_cdrom":
			pass
		"a500_accel_68030":
			# A530-Klasse: Controller und 120-MB-SCSI-Platte stecken im selben
			# Seitenwagen. Das Basisflag hält alte Boot-Prüfungen kompatibel.
			mgr.hardware["harddisk"] = true
		"a500_scsi_cdrom":
			mgr.hardware["cdrom"] = true
		"amigaos_31_upgrade": pass
	mgr.hardware["hardware_schema"] = PsDefs.HARDWARE_SCHEMA_VERSION
	if id in ["computer_amiga_500", "computer_amiga_600", "computer_amiga_1200"] \
			or id in PsDefs.RAM_HARDWARE_IDS:
		_sync_active_ram_profile(mgr)
	mgr._sync_hdd_volumes()
	mgr.stats_changed.emit()
	if is_new:
		# Memory Layer: neue Hardware ist ein Moment fürs Leben (s. Zeit-Bibel).
		MemoryManager.record("hardware", "endlich %s bekommen" % id.replace("_", " "))
		if id in PsDefs.RAM_HARDWARE_IDS:
			MemoryManager.record_once("first_ram_upgrade")


## Kontrollierter Besitzentzug fuer ausdrueckliche Wiederverkaeufe. Das aktive
## Modell wird vorher durch RoomManager abgesichert; diese Low-Level-Methode
## nimmt niemals selbst einen Ersatzrechner an oder zahlt Geld aus.
static func remove_hardware(mgr, id: String) -> bool:
	if id.is_empty() or not bool(mgr.hardware.get(id, false)):
		return false
	mgr.hardware[id] = false
	mgr.stats_changed.emit()
	return true


static func _apply_ram_profile(mgr, total_mb: float, chip_kb: int, slow_kb: int,
		fast_kb: int, profile: String) -> void:
	if float(mgr.hardware.get("ram_mb", 0.5)) > total_mb:
		return
	mgr.hardware["ram_mb"] = total_mb
	mgr.hardware["chip_ram_kb"] = chip_kb
	mgr.hardware["slow_ram_kb"] = slow_kb
	mgr.hardware["fast_ram_kb"] = fast_kb
	mgr.hardware["ram_profile"] = profile


## Liefert den durch echte Besitzflags garantierten Mindest-Ausbau. Das ist
## absichtlich getrennt vom gespeicherten ram_mb-Rohwert: Aeltere Spielstaende
## konnten das Besitzflag korrekt enthalten, waehrend eine fruehere Migration
## den Zahlenwert versehentlich wieder auf 512 KB setzte.
static func _owned_ram_entitlement(mgr) -> Dictionary:
	var computer := str(mgr.hardware.get("computer_model", "amiga_500"))
	# Rechnergebundene Erweiterungen dürfen nicht zwischen den Gehäusen
	# „mitwandern": A501/Agnus-Umbau gehören dem A500, A601 dem A600.
	if computer == "amiga_600":
		var a600_chip := 2048 if bool(mgr.hardware.get("a600_chipram_2mb", false)) else 1024
		var a600_fast := 0
		var a600_profile := "a600_a601_chip2" if a600_chip == 2048 else "a600_stock_1mb"
		if bool(mgr.hardware.get("a600_accel_68030", false)):
			a600_fast = 32768
			a600_profile = "a600_68030_fast32"
		elif bool(mgr.hardware.get("a600_pcmcia_sram_4mb", false)):
			a600_fast = 4096
			a600_profile = "a600_pcmcia_fast4"
		elif bool(mgr.hardware.get("a600_pcmcia_sram_2mb", false)):
			a600_fast = 2048
			a600_profile = "a600_pcmcia_fast2"
		return {"total_kb": a600_chip + a600_fast, "chip_kb": a600_chip,
			"slow_kb": 0, "fast_kb": a600_fast, "profile": a600_profile}
	if computer == "amiga_1200":
		var a1200_fast := 0
		var a1200_profile := "a1200_stock_2mb"
		if bool(mgr.hardware.get("a1200_accel_68060", false)):
			a1200_fast = 65536
			a1200_profile = "a1200_68060_fast64"
		elif bool(mgr.hardware.get("a1200_accel_68040", false)):
			a1200_fast = 32768
			a1200_profile = "a1200_68040_fast32"
		elif bool(mgr.hardware.get("a1200_accel_68030_50", false)):
			a1200_fast = 32768
			a1200_profile = "a1200_68030_50_fast32"
		elif bool(mgr.hardware.get("a1200_accel_68030", false)):
			a1200_fast = 16384
			a1200_profile = "a1200_68030_fast16"
		elif bool(mgr.hardware.get("a1200_fast_ram_8mb", false)):
			a1200_fast = 8192
			a1200_profile = "a1200_fast8"
		elif bool(mgr.hardware.get("a1200_fast_ram_4mb", false)):
			a1200_fast = 4096
			a1200_profile = "a1200_fast4"
		elif bool(mgr.hardware.get("a1200_pcmcia_sram_4mb", false)):
			a1200_fast = 4096
			a1200_profile = "a1200_pcmcia_fast4"
		return {"total_kb": 2048 + a1200_fast, "chip_kb": 2048,
			"slow_kb": 0, "fast_kb": a1200_fast, "profile": a1200_profile}
	var a500_chip := 512
	if bool(mgr.hardware.get("chipram_2mb_mod", false)) \
			or bool(mgr.hardware.get("ram_2mb", false)) \
			or bool(mgr.hardware.get("ram_4mb", false)):
		a500_chip = 2048
	if bool(mgr.hardware.get("a500_accel_68030", false)):
		return {"total_kb": a500_chip + 8192, "chip_kb": a500_chip,
			"slow_kb": 0, "fast_kb": 8192, "profile": "a500_68030_fast8"}
	if bool(mgr.hardware.get("ram_4mb", false)):
		return {"total_kb": 4096, "chip_kb": 2048, "slow_kb": 0,
			"fast_kb": 2048, "profile": "a500_chip2_fast2"}
	if bool(mgr.hardware.get("chipram_2mb_mod", false)) \
			or bool(mgr.hardware.get("ram_2mb", false)):
		return {"total_kb": 2048, "chip_kb": 2048, "slow_kb": 0,
			"fast_kb": 0, "profile": "a500_chipram_2mb_mod"}
	if bool(mgr.hardware.get("ram_1mb", false)):
		return {"total_kb": 1024, "chip_kb": 512, "slow_kb": 512,
			"fast_kb": 0, "profile": "a501_1mb"}
	return {"total_kb": 512, "chip_kb": 512, "slow_kb": 0,
		"fast_kb": 0, "profile": "a500_stock_512k"}


## Beim echten Rechnerwechsel wird der aktive Speicherausbau neu aus den
## rechnergebundenen Besitzflags hergestellt. So bleibt ein A600 serienmäßig
## bei 1 MB, auch wenn daneben ein aufgerüsteter A500 im Besitz ist.
static func _sync_active_ram_profile(mgr) -> void:
	var entitlement := _owned_ram_entitlement(mgr)
	mgr.hardware["ram_mb"] = float(int(entitlement["total_kb"])) / 1024.0
	mgr.hardware["chip_ram_kb"] = int(entitlement["chip_kb"])
	mgr.hardware["slow_ram_kb"] = int(entitlement["slow_kb"])
	mgr.hardware["fast_ram_kb"] = int(entitlement["fast_kb"])
	mgr.hardware["ram_profile"] = str(entitlement["profile"])


## Repariert inkonsistente Saves einmal beim Laden. Ein Besitz darf nie weniger
## RAM ergeben als die dazugehoerige Hardware. Hoehere, spaetere Ausbauten werden
## dabei niemals auf eine kleinere Stufe zurueckgesetzt.
static func _normalize_ram_from_ownership(mgr) -> bool:
	var entitlement := _owned_ram_entitlement(mgr)
	var guaranteed_kb := int(entitlement["total_kb"])
	var stored_kb := maxi(512, roundi(float(mgr.hardware.get("ram_mb", 0.5)) * 1024.0))
	var stored_sum := int(mgr.hardware.get("chip_ram_kb", 0)) \
		+ int(mgr.hardware.get("slow_ram_kb", 0)) + int(mgr.hardware.get("fast_ram_kb", 0))
	if stored_kb > guaranteed_kb:
		return false
	if stored_kb == guaranteed_kb and stored_sum == stored_kb \
			and str(mgr.hardware.get("ram_profile", "")) == str(entitlement["profile"]):
		return false
	mgr.hardware["ram_mb"] = float(guaranteed_kb) / 1024.0
	mgr.hardware["chip_ram_kb"] = int(entitlement["chip_kb"])
	mgr.hardware["slow_ram_kb"] = int(entitlement["slow_kb"])
	mgr.hardware["fast_ram_kb"] = int(entitlement["fast_kb"])
	mgr.hardware["ram_profile"] = str(entitlement["profile"])
	return true


## Einzige Anzeigequelle fuer Workbench, Shell, SysInfo und Inventar. Die
## getrennten Speicherarten sind wichtig: Die A501 liefert 512 KB sogenanntes
## Slow-/Ranger-RAM, kein echtes Fast-RAM. Alte/handeditierte Saves bekommen
## einen sicheren Restpool, ohne dass Speicher verschwindet.
static func ram_breakdown(mgr) -> Dictionary:
	var entitlement := _owned_ram_entitlement(mgr)
	if mgr.desk_model("computer_model") in ["amiga_600", "amiga_1200"]:
		return entitlement.duplicate(true)
	var stored_kb := maxi(512, roundi(float(mgr.hardware.get("ram_mb", 0.5)) * 1024.0))
	var total_kb := maxi(stored_kb, int(entitlement["total_kb"]))
	# Besitzflags sind die staerkere Wahrheit. So ist auch ein bereits geladener,
	# inkonsistenter Spielstand sofort korrekt, noch bevor er erneut gespeichert
	# und durch mgr.from_dict() dauerhaft normalisiert wird.
	if int(entitlement["total_kb"]) >= stored_kb:
		return entitlement.duplicate(true)
	var chip_kb := clampi(int(mgr.hardware.get("chip_ram_kb", mini(total_kb, 512))), 0, total_kb)
	var remaining := total_kb - chip_kb
	var slow_kb := clampi(int(mgr.hardware.get("slow_ram_kb", 0)), 0, remaining)
	remaining -= slow_kb
	var fast_kb := clampi(int(mgr.hardware.get("fast_ram_kb", 0)), 0, remaining)
	remaining -= fast_kb
	if remaining > 0:
		var profile := str(mgr.hardware.get("ram_profile", ""))
		if "a501" in profile:
			slow_kb += remaining
		elif "chip" in profile or mgr.desk_model("computer_model") in ["amiga_600", "amiga_1200"]:
			chip_kb += remaining
		else:
			fast_kb += remaining
	return {
		"total_kb": total_kb,
		"chip_kb": chip_kb,
		"slow_kb": slow_kb,
		"fast_kb": fast_kb,
		"profile": str(mgr.hardware.get("ram_profile", "")),
	}


static func ram_total_text(mgr) -> String:
	var total_kb := int(ram_breakdown(mgr)["total_kb"])
	if total_kb < 1024:
		return "%d KB" % total_kb
	if total_kb % 1024 == 0:
		return "%d MB" % floori(float(total_kb) / 1024.0)
	return "%.1f MB" % (float(total_kb) / 1024.0)


static func ram_configuration_text(mgr) -> String:
	var ram := ram_breakdown(mgr)
	var pools: Array[String] = ["%d KB Chip" % int(ram["chip_kb"])]
	if int(ram["slow_kb"]) > 0:
		pools.append("%d KB Slow" % int(ram["slow_kb"]))
	if int(ram["fast_kb"]) > 0:
		pools.append("%d KB Fast" % int(ram["fast_kb"]))
	return " + ".join(pools)
