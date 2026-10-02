extends RefCounted
## Speichern und Laden.
##
## Aus disk_manager.gd ausgelagert (Zeilenbudget). Muster Wrapper-static:
## Der Autoload haelt die duennen oeffentlichen Methoden, die Rumpfe stehen
## hier als static func mit dem Manager-Knoten als erstem Parameter 'mgr'.
## 'mgr' bleibt bewusst UNTYPISIERT — sonst entstuende ein Zirkelbezug auf
## den Autoload. Kein class_name (Klassen-Cache-Race), nur Pfad-preload.

const PsDefs := preload("res://scripts/autoload/player_stats_defs.gd")

static func to_dict(mgr) -> Dictionary:
	return {
		"geld": mgr.geld, "energie": mgr.energie, "hunger": mgr.hunger, "ruf": mgr.ruf, "wissen": mgr.wissen,
		"eltern_toleranz": mgr.eltern_toleranz,
		# Save-Snapshots duerfen niemals auf den weiterlebenden Runtime-Zustand
		# zeigen. Sonst veraendern Hardwarekauf, Installation oder Dateizugriff
		# einen bereits an SaveManager uebergebenen Snapshot nachtraeglich.
		"hardware": mgr.hardware.duplicate(true),
		"peripherals": mgr.peripherals.duplicate(true),
		"programs": mgr.programs.duplicate(true),
		"hdd_volumes": mgr.hdd_volumes.duplicate(true),
	}


static func from_dict(mgr, d: Dictionary) -> void:
	mgr.geld = maxf(0.0, snappedf(float(d.get("geld", 20.0)), 0.01))
	mgr.energie = clampi(int(d.get("energie", 100)), 0, 100)
	# Alte Spielstaende hatten hinter dem HUD-Text HUNGER faelschlich die
	# Eltern-Toleranz liegen. Die Migration startet bewusst moderat statt diesen
	# sachfremden Wert zu uebernehmen.
	mgr.hunger = clampi(int(d.get("hunger", 25)), 0, 100)
	mgr.ruf = clampi(int(d.get("ruf", 0)), 0, 100)
	mgr.wissen = clampi(int(d.get("wissen", 0)), 0, 100)
	mgr.eltern_toleranz = clampi(int(d.get("eltern_toleranz", 70)), 0, 100)
	# Fehlende Legacy-Felder gehoeren zum geladenen Slot. Der noch lebende
	# Autoload kann Besitz eines voellig anderen Spielstands enthalten.
	var loaded_hardware: Dictionary = d.get("hardware", mgr._default_hardware())
	var legacy_ram_schema := not loaded_hardware.has("ram_profile")
	mgr.hardware = loaded_hardware.duplicate(true)
	# Migration alter Saves: neue Wartungswerte ergänzen, ohne Besitz/Upgrades
	# aus dem gespeicherten Dictionary zu überschreiben.
	if not mgr.hardware.has("drive_dirt"):
		mgr.hardware["drive_dirt"] = 0.0
	if not mgr.hardware.has("drive_alignment"):
		# Alte Spielstände kannten keine echte Dejustage-Mechanik. Ein fehlender
		# Wert muss deshalb als intaktes Laufwerk migriert werden.
		mgr.hardware["drive_alignment"] = 1.0
	if not mgr.hardware.has("joystick_condition"):
		mgr.hardware["joystick_condition"] = 0.45
	if not mgr.hardware.has("computer_model"):
		mgr.hardware["computer_model"] = "amiga_500"
	# Der aktive Rechner impliziert Besitz; sehr alte Zwischenstände speicherten
	# nur den Tisch-Slot und würden sonst ihre modellgebundenen Karten verlieren.
	var active_computer := str(mgr.hardware["computer_model"])
	if active_computer == "amiga_600":
		mgr.hardware["computer_amiga_600"] = true
	elif active_computer == "amiga_1200":
		mgr.hardware["computer_amiga_1200"] = true
	# Der Rechner aus dem Starterkarton war schon immer echter Besitz. Aeltere
	# Saves speicherten nur das aktive Modell und liessen den A500 nach einem
	# A600-Kauf deshalb wie einen verschwundenen Trade-in aussehen.
	if not mgr.hardware.has("computer_amiga_500"):
		mgr.hardware["computer_amiga_500"] = true
	if not mgr.hardware.has("monitor_model"):
		mgr.hardware["monitor_model"] = "commodore_1084s"
	# Kapazitäts-Upgrades ersetzen die Basisplatte, bestehende Boot-Prüfungen
	# dürfen trotzdem weiterhin ihre langjährig stabile Basis-ID verwenden.
	if mgr.hardware.get("a600_internal_hdd_120mb", false):
		mgr.hardware["a600_internal_hdd"] = true
	if mgr.hardware.get("a1200_internal_hdd_420mb", false) \
			or mgr.hardware.get("a1200_internal_hdd_1200mb", false):
		mgr.hardware["a1200_internal_hdd"] = true
	if mgr.hardware.get("a500_scsi_cdrom", false):
		mgr.hardware["cdrom"] = true
	if not mgr.hardware.has("mouse_model"):
		mgr.hardware["mouse_model"] = "amiga_mouse"
	if not mgr.hardware.has("modem_model"):
		mgr.hardware["modem_model"] = "modem_14400" if mgr.hardware.get("modem_14400", false) else \
			("modem_9600" if mgr.hardware.get("modem_9600", false) else "modem_2400")
	# Schema 1 integriert erstmals die bereits vorhandenen Inkjet-/Laser-Master
	# in denselben sichtbaren Druckerslot. Alte Saves konnten den Kauf korrekt
	# besitzen, hielten aber zwangsläufig weiter das vorige Nadeldrucker-Modell.
	if int(mgr.hardware.get("printer_visual_schema", 0)) < 1:
		mgr.hardware["printer_model"] = "dot_matrix_24_color" \
			if mgr.hardware.get("dot_matrix_24_color", false) else \
			("color_inkjet" if mgr.hardware.get("color_printer", false) else \
			("laser_mono" if mgr.hardware.get("laser_printer", false) else \
			("dot_matrix_24_mono" if mgr.hardware.get("dot_matrix_24", false) \
			else "dot_matrix_9pin")))
		mgr.hardware["printer_visual_schema"] = 1
	elif not mgr.hardware.has("printer_model"):
		mgr.hardware["printer_model"] = "dot_matrix_9pin"
	if not mgr.hardware.has("stereo_model"):
		mgr.hardware["stereo_model"] = "compact_cassette"
	# Migration vor der realistischen 512-KB-Grundausstattung: Ein altes ram_mb=1
	# ohne gekauftes RAM-Flag war nur der damalige falsche Default, kein Besitz.
	if legacy_ram_schema:
		if mgr.hardware.get("ram_4mb", false):
			mgr._apply_ram_profile(4.0, 2048, 0, 2048, "a500_chip2_fast2")
		elif mgr.hardware.get("ram_2mb", false):
			mgr.hardware["chipram_2mb_mod"] = true
			mgr._apply_ram_profile(2.0, 2048, 0, 0, "a500_chipram_2mb_mod")
		elif mgr.hardware.get("ram_1mb", false):
			mgr._apply_ram_profile(1.0, 512, 512, 0, "a501_1mb")
		else:
			mgr.hardware["ram_mb"] = 0.5
			mgr.hardware["chip_ram_kb"] = 512
			mgr.hardware["slow_ram_kb"] = 0
			mgr.hardware["fast_ram_kb"] = 0
			mgr.hardware["ram_profile"] = "a500_stock_512k"
	mgr._normalize_ram_from_ownership()
	# Seit Schema 2 ist der numerische RAM-Block nur noch Cache. Die
	# rechnergebundenen Besitzflags sind die Wahrheit und werden bei jedem
	# Laden neu auf das aktuell aufgestellte Modell projiziert.
	if int(mgr.hardware.get("hardware_schema", 0)) < PsDefs.HARDWARE_SCHEMA_VERSION \
			or mgr.desk_model("computer_model") in ["amiga_600", "amiga_1200"] \
			or mgr._active_accelerator_id() != "":
		mgr._sync_active_ram_profile()
	mgr.hardware["hardware_schema"] = PsDefs.HARDWARE_SCHEMA_VERSION
	mgr.peripherals = (d.get("peripherals", mgr._default_peripherals()) as Dictionary).duplicate(true)
	var saved_programs: Variant = d.get("programs", [])
	mgr.programs = (saved_programs as Array).duplicate(true) if saved_programs is Array \
		else []
	mgr.hdd_volumes = (d.get("hdd_volumes", {}) as Dictionary).duplicate(true)
	mgr._sync_hdd_volumes()
	mgr.stats_changed.emit()
