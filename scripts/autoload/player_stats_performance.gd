extends RefCounted
## Rechenleistung, Prozessor und Schnittstellen.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

## Aktive CPU-Karte des aufgestellten Rechners. Karten bleiben im Besitz, aber
## nur die zum Gehäuse passende höchste Stufe belegt dessen lokalen CPU-Slot.
static func _active_accelerator_id(mgr) -> String:
	match mgr.desk_model("computer_model"):
		"amiga_500":
			return "a500_accel_68030" if mgr.has_hardware("a500_accel_68030") else ""
		"amiga_600":
			return "a600_accel_68030" if mgr.has_hardware("a600_accel_68030") else ""
		"amiga_1200":
			for id in ["a1200_accel_68060", "a1200_accel_68040",
					"a1200_accel_68030_50", "a1200_accel_68030"]:
				if mgr.has_hardware(id):
					return id
	return ""


static func active_accelerator_id(mgr) -> String:
	return _active_accelerator_id(mgr)


## Für UI/Programme: prüft nicht bloß Besitz, sondern ob ein internes Upgrade
## tatsächlich zum momentan aktiven Rechner gehört.
static func hardware_active(mgr, id: String) -> bool:
	if not mgr.has_hardware(id):
		return false
	# Interne Platten belegen je Rechner genau einen physischen Einbauplatz.
	# Besitzflags der kleineren Platte bleiben fuer Wiederverkauf, Saves und
	# alte Quest-Vertraege erhalten, aber nur die groesste Platte ist eingebaut.
	if id == "a600_internal_hdd":
		return mgr.desk_model("computer_model") == "amiga_600" \
			and not mgr.has_hardware("a600_internal_hdd_120mb")
	if id == "a600_internal_hdd_120mb":
		return mgr.desk_model("computer_model") == "amiga_600"
	if id == "a1200_internal_hdd":
		return mgr.desk_model("computer_model") == "amiga_1200" \
			and not mgr.has_hardware("a1200_internal_hdd_420mb") \
			and not mgr.has_hardware("a1200_internal_hdd_1200mb")
	if id == "a1200_internal_hdd_420mb":
		return mgr.desk_model("computer_model") == "amiga_1200" \
			and not mgr.has_hardware("a1200_internal_hdd_1200mb")
	if id == "a1200_internal_hdd_1200mb":
		return mgr.desk_model("computer_model") == "amiga_1200"
	var computer_slots := {
		"computer_amiga_500": "amiga_500",
		"computer_amiga_600": "amiga_600",
		"computer_amiga_1200": "amiga_1200",
	}
	if computer_slots.has(id):
		return mgr.desk_model("computer_model") == str(computer_slots[id])
	if id in ["ram_1mb", "chipram_2mb_mod", "ram_2mb", "ram_4mb",
			"harddisk", "cdrom", "a500_scsi_cdrom"]:
		return mgr.desk_model("computer_model") == "amiga_500"
	if id == "amigaos_31_upgrade":
		return mgr.desk_model("computer_model") == "amiga_1200"
	if id.begins_with("a500_"):
		return mgr.desk_model("computer_model") == "amiga_500"
	if id.begins_with("a600_"):
		return mgr.desk_model("computer_model") == "amiga_600"
	if id.begins_with("a1200_"):
		return mgr.desk_model("computer_model") == "amiga_1200"
	var model_slots := {
		"monitor_commodore_1084s": "commodore_1084s",
		"monitor_commodore_1901": "commodore_1901",
		"monitor_commodore_1942": "commodore_1942",
		"monitor_multisync_17": "multisync_17",
	}
	if model_slots.has(id):
		return mgr.desk_model("monitor_model") == str(model_slots[id])
	return true


## Modellgebundene Systemdaten. SysInfo, Inventar und andere Oberflächen
## dürfen dadurch nicht mehr aus Jahr oder allgemeinem Ausbau raten.
static func cpu_description(mgr) -> String:
	match mgr.desk_model("computer_model"):
		"amiga_1200":
			if mgr.has_hardware("a1200_accel_68060"):
				return "MC68060 · 50,00 MHz"
			if mgr.has_hardware("a1200_accel_68040"):
				return "MC68040 · 40,00 MHz"
			if mgr.has_hardware("a1200_accel_68030_50"):
				return "MC68030 · 50,00 MHz"
			if mgr.has_hardware("a1200_accel_68030"):
				return "MC68030 · 40,00 MHz"
			return "MC68EC020 · 14,19 MHz"
		"amiga_600":
			if mgr.has_hardware("a600_accel_68030"):
				return "MC68030 · 33,00 MHz"
			return "MC68000 · 7,09 MHz"
		_:
			if mgr.has_hardware("a500_accel_68030"):
				return "MC68030 · 40,00 MHz"
			return "MC68000 · 7,09 MHz"


static func cpu_clock_mhz(mgr) -> float:
	match mgr.desk_model("computer_model"):
		"amiga_1200":
			if mgr.has_hardware("a1200_accel_68060"):
				return 50.0
			if mgr.has_hardware("a1200_accel_68040"):
				return 40.0
			if mgr.has_hardware("a1200_accel_68030_50"):
				return 50.0
			return 40.0 if mgr.has_hardware("a1200_accel_68030") else 14.19
		"amiga_600":
			return 33.0 if mgr.has_hardware("a600_accel_68030") else 7.09
		_:
			return 40.0 if mgr.has_hardware("a500_accel_68030") else 7.09


## Stabile Leistungs-API für Workbench-Programme, Minispiele und Animationen.
## Alle Werte sind relativ zum serienmäßigen PAL-A500 (= 1,0). Reine
## Taktverhältnisse wären bei 020/030/040/060 irreführend; die Faktoren bilden
## deshalb auch Cache, Busbreite und vorhandenes Fast-RAM konservativ ab.
static func cpu_speed_multiplier(mgr) -> float:
	match mgr.desk_model("computer_model"):
		"amiga_1200":
			if mgr.has_hardware("a1200_accel_68060"):
				return 28.0
			if mgr.has_hardware("a1200_accel_68040"):
				return 14.0
			if mgr.has_hardware("a1200_accel_68030_50"):
				return 9.0
			if mgr.has_hardware("a1200_accel_68030"):
				return 7.2
			return 2.6
		"amiga_600":
			return 6.0 if mgr.has_hardware("a600_accel_68030") else 1.0
		_:
			return 7.2 if mgr.has_hardware("a500_accel_68030") else 1.0


## Aktive Massenspeicher-Kapazität; Besitz eines Laufwerks für einen anderen
## Rechner zählt ausdrücklich nicht.
static func active_storage_mb(mgr) -> int:
	match mgr.desk_model("computer_model"):
		"amiga_500":
			if mgr.has_hardware("a500_accel_68030"):
				return 120
			return 20 if mgr.has_hardware("harddisk") else 0
		"amiga_600":
			if mgr.has_hardware("a600_internal_hdd_120mb"):
				return 120
			return 40 if mgr.has_hardware("a600_internal_hdd") else 0
		"amiga_1200":
			if mgr.has_hardware("a1200_internal_hdd_1200mb"):
				return 1200
			if mgr.has_hardware("a1200_internal_hdd_420mb"):
				return 420
			return 80 if mgr.has_hardware("a1200_internal_hdd") else 0
	return 0


## I/O-Faktor relativ zu DF0:. Größere Platten allein erhöhen nur Kapazität;
## IDE-/SCSI-Controller und Fast-RAM machen reale Dateioperationen schneller.
static func io_speed_multiplier(mgr) -> float:
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier
	# der ausdrueckliche Typ statt :=.
	var computer: String = mgr.desk_model("computer_model")
	var value := 1.0
	if computer == "amiga_500":
		if mgr.has_hardware("a500_accel_68030"):
			value = 4.8
		elif mgr.has_hardware("harddisk"):
			value = 2.2
	elif computer == "amiga_600":
		if mgr.has_hardware("a600_internal_hdd_120mb"):
			value = 3.1
		elif mgr.has_hardware("a600_internal_hdd"):
			value = 2.6
		if mgr.has_hardware("a600_accel_68030"):
			value *= 1.25
	elif computer == "amiga_1200":
		if active_storage_mb(mgr) > 0:
			value = 3.0
		if mgr.has_hardware("a1200_internal_hdd_420mb"):
			value = 3.6
		if mgr.has_hardware("a1200_internal_hdd_1200mb"):
			value = 4.0
		if mgr.has_hardware("a1200_scsi_module"):
			value = maxf(value, 5.5)
		if cpu_speed_multiplier(mgr) >= 7.0:
			value *= 1.15
	if mgr.has_hardware("external_drive") and value <= 1.0:
		value = 1.15
	return snappedf(value, 0.01)


## Gesamtwert für zeitbasierte Programme. CPU dominiert Rendering/Kompression,
## I/O und Fast-RAM bleiben aber messbar. UI darf Einzelwerte separat anzeigen.
static func performance_multiplier(mgr) -> float:
	var fast_mb := float(int(mgr.ram_breakdown()["fast_kb"])) / 1024.0
	var memory_bonus := minf(1.8, log(1.0 + fast_mb) / log(2.0) * 0.12)
	return snappedf(cpu_speed_multiplier(mgr) * 0.68 + io_speed_multiplier(mgr) * 0.22
		+ 0.10 + memory_bonus, 0.01)


static func performance_profile(mgr) -> Dictionary:
	# 'mgr' ist untypisiert (sonst Zirkelbezug auf den Autoload), deshalb hier
	# der ausdrueckliche Typ statt :=.
	var ram: Dictionary = mgr.ram_breakdown()
	return {
		"computer_model": mgr.desk_model("computer_model"),
		"cpu": cpu_description(mgr),
		"cpu_mhz": cpu_clock_mhz(mgr),
		"chipset": chipset_description(mgr),
		"interfaces": interface_description(mgr),
		"cpu_speed_multiplier": cpu_speed_multiplier(mgr),
		"io_speed_multiplier": io_speed_multiplier(mgr),
		"performance_multiplier": performance_multiplier(mgr),
		"ram_total_kb": int(ram["total_kb"]),
		"chip_ram_kb": int(ram["chip_kb"]),
		"fast_ram_kb": int(ram["fast_kb"]),
		"storage_mb": active_storage_mb(mgr),
		"storage": mgr.active_hdd_description(),
		"scsi": mgr.desk_model("computer_model") == "amiga_1200"
			and mgr.has_hardware("a1200_scsi_module"),
		"cdrom": mgr.active_cdrom_available(),
		"hardware_level": mgr.hardware_level(),
		"expansions": mgr.expansion_summary(),
	}


static func chipset_description(mgr) -> String:
	match mgr.desk_model("computer_model"):
		"amiga_1200":
			return "AGA · PAL 50 Hz"
		"amiga_600":
			return "ECS · PAL 50 Hz"
		_:
			return "OCS · PAL 50 Hz"


static func interface_description(mgr) -> String:
	match mgr.desk_model("computer_model"):
		"amiga_1200":
			if mgr.has_hardware("a1200_scsi_module"):
				return "Fast-SCSI-II · IDE 44-Pin · PCMCIA Typ II · lokaler Erweiterungsport"
			return "IDE 44-Pin · PCMCIA Typ II · lokaler Erweiterungsport"
		"amiga_600":
			return "IDE 44-Pin · PCMCIA Typ II"
		_:
			if mgr.has_hardware("a500_accel_68030"):
				return "Fast-SCSI · A530-Seitenwagen · Erweiterungsport"
			return "Seitlicher Erweiterungsport"
