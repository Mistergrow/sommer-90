extends Node
## PlayerStats — zentrale Spielwerte (Geld, Energie, Ruf, Wissen, Eltern-Toleranz)
## sowie der Hardware-Besitz. Alle Änderungen laufen über Methoden, damit die
## UI per Signal aktualisiert werden kann.

signal stats_changed

## Seit dem Zeilenbudget-Split ist dieser Autoload die Fassade. Zustand und
## Signal bleiben hier; die Rumpfe liegen nach Zustaendigkeit getrennt daneben in
## scripts/autoload/player_stats_*.gd und bekommen den Knoten als erstes Argument
## (Muster Wrapper-static). Die Teile laden sich NICHT gegenseitig — Quer-Aufrufe
## laufen ueber diese Fassade, dadurch ist kein preload-Zirkel moeglich.
##
## Die Helfer liegen bewusst FLACH in scripts/autoload/: zwei Tests bauen ihren
## Vertragstext ueber DirAccess.get_files_at("res://scripts/autoload"), und das
## ist nicht rekursiv (tests/quest_integrity_check.gd,
## tests/campaign_mission_runtime_contract_check.gd).

const PsDefs := preload("res://scripts/autoload/player_stats_defs.gd")
const PsHardware := preload("res://scripts/autoload/player_stats_hardware.gd")
const PsPerformance := preload("res://scripts/autoload/player_stats_performance.gd")
const PsStorage := preload("res://scripts/autoload/player_stats_storage.gd")
const PsDevices := preload("res://scripts/autoload/player_stats_devices.gd")
const PsPersistence := preload("res://scripts/autoload/player_stats_persistence.gd")
const ProgramIdAliases := preload("res://scripts/data/program_aliases.gd")

# Konstanten stehen in player_stats_defs.gd; hier bleiben sie als Alias sichtbar,
# damit PlayerStats.DESK_MODEL_OPTIONS und die uebrigen weiter erreichbar sind.
const CLAMPED := PsDefs.CLAMPED
const HARDWARE_SCHEMA_VERSION := PsDefs.HARDWARE_SCHEMA_VERSION
const HDD_SCHEMA_VERSION := PsDefs.HDD_SCHEMA_VERSION
const HDD_SYSTEM_KB := PsDefs.HDD_SYSTEM_KB
const RAM_HARDWARE_IDS := PsDefs.RAM_HARDWARE_IDS
const DESK_MODEL_OPTIONS := PsDefs.DESK_MODEL_OPTIONS

var geld: float = 20.0          # DM mit Pfennig; bei jeder Änderung auf 0,01 gerundet
var energie: int = 100
var hunger: int = 20            # 0 = satt, 100 = ausgehungert
var ruf: int = 0
var wissen: int = 0
var eltern_toleranz: int = 70

## Hardware-Besitz. drive_dirt (0..1) = Verschmutzung des Laufwerkskopfs,
## drive_alignment (0..1) = mechanische Spurtreue des internen DF0.
## joystick_condition (0..1) = Stabilität der vier Richtungskontakte; der alte
## Start-Joystick hat bewusst einen Wackelkontakt für Svens erste Lötstunde.
var hardware: Dictionary = _default_hardware()

## Einstellungen der angeschlossenen Peripherie (Werkbank/OS). Reine
## Konfiguration — wird gespeichert, wirkt teils aufs Spiel (Drucker → Etiketten).
var peripherals: Dictionary = _default_peripherals()

## Installierte Programme (WERKBANK-Apps). Wird beim Spielstart mit den
## vorinstallierten Workbench-Basics gefüllt (ProgramLibrary.preinstall); den
## Rest besorgt man sich per Modem/BBS, im Laden, Club oder von Freunden.
var programs: Array = []

## Persistente, rechnergebundene Festplatten. Besitzflags bestimmen, ob das
## jeweilige Volume physisch vorhanden ist; dieser Block hält den tatsächlichen
## Inhalt. Dadurch wandert eine interne A600-/A1200-Platte beim Rechnerwechsel
## nicht mit, während ein Kapazitätsupgrade dieselben Daten behält.
var hdd_volumes: Dictionary = {}

# Werte, die auf 0..100 begrenzt werden



# ------------------------------------------- Grundwerte, Geld und Programme

func reset() -> void:
	geld = 20.0
	energie = 100
	hunger = 20
	ruf = 0
	wissen = 0
	eltern_toleranz = 70
	hardware = _default_hardware()
	peripherals = _default_peripherals()
	programs = []  # ProgramLibrary.preinstall() füllt die Basics beim Spielstart
	hdd_volumes = {}
	stats_changed.emit()


## Einzige Quelle der Startausstattung: Deklaration und reset() lesen beide von
## hier, damit "neues Spiel" und frisch geladener Autoload nie auseinanderlaufen.
static func _default_hardware() -> Dictionary:
	return {
		"hardware_schema": HARDWARE_SCHEMA_VERSION,
		"computer_amiga_500": true,
		"computer_model": "amiga_500",
		"monitor_model": "commodore_1084s",
		"mouse_model": "amiga_mouse",
		"modem_model": "modem_2400",
		"printer_model": "dot_matrix_9pin",
		"printer_visual_schema": 1,
		"stereo_model": "compact_cassette",
		"external_drive": false,
		"modem": false,
		"cd_burner": false,
		"ram_mb": 0.5,
		"chip_ram_kb": 512,
		"slow_ram_kb": 0,
		"fast_ram_kb": 0,
		"ram_profile": "a500_stock_512k",
		"drive_dirt": 0.0,
		"drive_alignment": 1.0,
		"joystick_condition": 0.45,
	}


static func _default_peripherals() -> Dictionary:
	return {
		"modem": {"dial": "ton", "speaker": true, "redial": false},
		"printer": {"quality": "nlq", "labels": "schmal"},
	}


## Ist ein WERKBANK-Programm installiert?
func has_program(id: String) -> bool:
	var wanted := ProgramIdAliases.canonical(id)
	for value: Variant in programs:
		if ProgramIdAliases.canonical(str(value)) == wanted:
			return true
	return false


## Programm installieren (z. B. per BBS-Download). Meldet neu-installiert.
func add_program(id: String, install_size_kb := 0) -> bool:
	var canonical_id := ProgramIdAliases.canonical(id)
	if has_program(canonical_id):
		return false
	# Eine nur eingebaute Rohplatte ist noch kein Installationsziel. Bis DH0:
	# partitioniert und formatiert wurde, bleibt die bisherige Disketten-/
	# Bibliothekssemantik vollständig erhalten.
	if install_size_kb > 0 and hdd_is_usable():
		if not hdd_write_file("Utilities/%s" % canonical_id, install_size_kb,
				{"kind": "program", "program_id": canonical_id}):
			return false
	programs.append(canonical_id)
	stats_changed.emit()
	return true


# ------------------------------------------------------------ Peripherie-Helfer


func add_money(amount: float) -> void:
	geld = maxf(0.0, snappedf(geld + amount, 0.01))
	stats_changed.emit()


## Gibt false zurück (und bucht nichts ab), wenn das Geld nicht reicht.
## Float-Toleranz, damit Pfennig-Rundung keinen Kauf fälschlich blockiert.
func spend_money(amount: float) -> bool:
	if geld + 0.005 < amount:
		return false
	geld = maxf(0.0, snappedf(geld - amount, 0.01))
	stats_changed.emit()
	return true


## Generische Wertänderung, von der Effekt-DSL genutzt (stat-Name aus JSON).
func change_stat(stat_name: String, delta: int) -> void:
	if stat_name == "geld":
		add_money(delta)
		return
	if not (stat_name in self):
		push_warning("Unbekannter Spielwert: %s" % stat_name)
		return
	var value: int = get(stat_name) + delta
	if stat_name in CLAMPED:
		value = clampi(value, 0, 100)
	set(stat_name, value)
	stats_changed.emit()


## Energie für eine Aktion verbrauchen; false = zu müde (Aktion abbrechen).
## Energie ausgeben und dabei Zeit verbrauchen.
##
## Der zweite Parameter ist OPTIONAL und benennt die Handlung: mit Kennung gilt
## der handgepflegte Wert aus data/time_costs.json, ohne Kennung der Wechselkurs
## von 5 Minuten je Energiepunkt. Dadurch kosten alle 34 bestehenden
## Aufrufstellen ab sofort Zeit, ohne dass eine einzige angefasst werden musste.
##
## Minuten werden AUSSCHLIESSLICH bei Erfolg verbucht. "Zu muede" ist ein Abbruch
## VOR der Handlung — dann darf auch keine Zeit vergangen sein. Zeit ist nie ein
## Rueckgabewert und nie ein Abbruchgrund danach.
func use_energy(cost: int, action := "") -> bool:
	if energie < cost:
		return false
	energie -= cost
	stats_changed.emit()
	TimeManager.advance_minutes(TimeManager.action_minutes(action, cost))
	return true


# ----------------------------------------------------------- Schreibtisch
# desk_model ist die meistgerufene Grundabfrage des Pakets (Leistung,
# Festplatte, Ausbau) und bleibt deshalb hier: ein dateiuebergreifender
# Aufruf ueber das untypisierte mgr wuerde beim Aufrufer die Typableitung
# verlieren.

func desk_model(slot: String) -> String:
	var options: Array = DESK_MODEL_OPTIONS.get(slot, [])
	return str(hardware.get(slot, options[0] if not options.is_empty() else ""))


## Low-Level-Save-Setter fuer austauschbare Tischhardware. Spiel-/Editor-UI
## benutzt RoomManager.select_device_model(), damit Besitz und Raumkatalog
## geprueft werden; Hardwarekaeufe setzen ihr frisch erworbenes Modell oben.
func select_desk_model(slot: String, model_id: String) -> bool:
	var options: Array = DESK_MODEL_OPTIONS.get(slot, [])
	if not model_id in options:
		return false
	hardware[slot] = model_id
	if slot == "computer_model":
		_sync_active_ram_profile()
	stats_changed.emit()
	return true


# --------------------------------------------------------- Ausbaustufe

## Hardware-Ausbaustufe (GDD: „schnellere/sicherere Disk-Aktionen") — abgeleitet
## aus RAM + angeschlossenen Erweiterungen. Das ist ausdrücklich KEIN
## Charakter-/Quest-XP-Level: Aufträge erhöhen Wissen, Ruf, Vertrauen und Besitz.
##
## Jede echte RAM-Verdopplung ist eine sichtbare Stufe:
##   512 KB = 1 · 1 MB = 2 · 2 MB = 3 · 4 MB = 4
## Dazu kommt je eine Stufe für wichtige angeschlossene Erweiterungen. Die alte
## Formel ceil(MB) ließ ausgerechnet die erste A501-Aufrüstung von 512 KB auf
## 1 MB weiterhin als „Level 1" erscheinen und machte ihren Fortschritt im HUD
## unsichtbar.
func hardware_level() -> int:
	var total_kb := maxi(512, int(ram_breakdown()["total_kb"]))
	var level := 1
	var next_ram_tier_kb := 1024
	while total_kb >= next_ram_tier_kb:
		level += 1
		next_ram_tier_kb *= 2
	for key in ["external_drive", "modem", "cd_burner"]:
		if hardware.get(key, false):
			level += 1
	if active_storage_mb() > 0:
		level += 1
	if cpu_speed_multiplier() > (2.6 if desk_model("computer_model") == "amiga_1200" else 1.0):
		level += 1
	if active_cdrom_available():
		level += 1
	return level


# --------------------------------------------------------------------------
# Hardwarebesitz und Speicherausbau — Rumpfe in scripts/autoload/player_stats_hardware.gd


func has_hardware(id: String) -> bool:
	return PsHardware.has_hardware(self, id)


func add_hardware(id: String) -> void:
	PsHardware.add_hardware(self, id)


func remove_hardware(id: String) -> bool:
	return PsHardware.remove_hardware(self, id)


func _apply_ram_profile(total_mb: float, chip_kb: int, slow_kb: int,
		fast_kb: int, profile: String) -> void:
	PsHardware._apply_ram_profile(self, total_mb, chip_kb, slow_kb, fast_kb, profile)


func _owned_ram_entitlement() -> Dictionary:
	return PsHardware._owned_ram_entitlement(self)


func _sync_active_ram_profile() -> void:
	PsHardware._sync_active_ram_profile(self)


func _normalize_ram_from_ownership() -> bool:
	return PsHardware._normalize_ram_from_ownership(self)


func ram_breakdown() -> Dictionary:
	return PsHardware.ram_breakdown(self)


func ram_total_text() -> String:
	return PsHardware.ram_total_text(self)


func ram_configuration_text() -> String:
	return PsHardware.ram_configuration_text(self)



# --------------------------------------------------------------------------
# Rechenleistung und Schnittstellen — Rumpfe in scripts/autoload/player_stats_performance.gd


func _active_accelerator_id() -> String:
	return PsPerformance._active_accelerator_id(self)


func active_accelerator_id() -> String:
	return PsPerformance.active_accelerator_id(self)


func hardware_active(id: String) -> bool:
	return PsPerformance.hardware_active(self, id)


func cpu_description() -> String:
	return PsPerformance.cpu_description(self)


func cpu_clock_mhz() -> float:
	return PsPerformance.cpu_clock_mhz(self)


func cpu_speed_multiplier() -> float:
	return PsPerformance.cpu_speed_multiplier(self)


func active_storage_mb() -> int:
	return PsPerformance.active_storage_mb(self)


func io_speed_multiplier() -> float:
	return PsPerformance.io_speed_multiplier(self)


func performance_multiplier() -> float:
	return PsPerformance.performance_multiplier(self)


func performance_profile() -> Dictionary:
	return PsPerformance.performance_profile(self)


func chipset_description() -> String:
	return PsPerformance.chipset_description(self)


func interface_description() -> String:
	return PsPerformance.interface_description(self)



# --------------------------------------------------------------------------
# Festplatten und Ausbau-Uebersicht — Rumpfe in scripts/autoload/player_stats_storage.gd


func active_hdd_description() -> String:
	return PsStorage.active_hdd_description(self)


func _storage_mb_for_model(model: String) -> int:
	return PsStorage._storage_mb_for_model(self, model)


func _hdd_controller_for_model(model: String) -> String:
	return PsStorage._hdd_controller_for_model(self, model)


func _native_hdd_profile(model: String) -> String:
	return PsStorage._native_hdd_profile(self, model)


func _fresh_hdd_volume(model: String, capacity_kb: int) -> Dictionary:
	return PsStorage._fresh_hdd_volume(self, model, capacity_kb)


func _sync_hdd_volumes() -> void:
	PsStorage._sync_hdd_volumes(self)


func hdd_info(model := "") -> Dictionary:
	return PsStorage.hdd_info(self, model)


func hdd_is_usable() -> bool:
	return PsStorage.hdd_is_usable(self)


func hdd_bootable() -> bool:
	return PsStorage.hdd_bootable(self)


func hdd_create_partition() -> Dictionary:
	return PsStorage.hdd_create_partition(self)


func hdd_format() -> Dictionary:
	return PsStorage.hdd_format(self)


func hdd_compatible_profiles() -> Array[String]:
	return PsStorage.hdd_compatible_profiles(self)


func hdd_recommended_profile() -> String:
	return PsStorage.hdd_recommended_profile(self)


func hdd_install_system(profile_id: String) -> Dictionary:
	return PsStorage.hdd_install_system(self, profile_id)


func hdd_write_file(path: String, size_kb: int, metadata := {}) -> bool:
	return PsStorage.hdd_write_file(self, path, size_kb, metadata)


func hdd_delete_file(path: String) -> bool:
	return PsStorage.hdd_delete_file(self, path)


func active_cdrom_available() -> bool:
	return PsStorage.active_cdrom_available(self)


func expansion_summary() -> Array[String]:
	return PsStorage.expansion_summary(self)



# --------------------------------------------------------------------------
# Peripherie, Laufwerk und Joystick — Rumpfe in scripts/autoload/player_stats_devices.gd


func modem_baud() -> int:
	return PsDevices.modem_baud(self)


func has_modem() -> bool:
	return PsDevices.has_modem(self)


func has_printer() -> bool:
	return PsDevices.has_printer(self)


func printer_name() -> String:
	return PsDevices.printer_name(self)


func best_print_stage() -> int:
	return PsDevices.best_print_stage(self)


func drive_dirt() -> float:
	return PsDevices.drive_dirt(self)


func drive_cleanliness() -> float:
	return PsDevices.drive_cleanliness(self)


func drive_alignment() -> float:
	return PsDevices.drive_alignment(self)


func drive_condition() -> float:
	return PsDevices.drive_condition(self)


func set_drive_alignment(value: float) -> void:
	PsDevices.set_drive_alignment(self, value)


func add_drive_dirt(amount: float) -> void:
	PsDevices.add_drive_dirt(self, amount)


func clean_drive() -> void:
	PsDevices.clean_drive(self)


func joystick_condition() -> float:
	return PsDevices.joystick_condition(self)


func damage_joystick(amount: float) -> void:
	PsDevices.damage_joystick(self, amount)


func repair_joystick() -> void:
	PsDevices.repair_joystick(self)



# --------------------------------------------------------------------------
# Speichern und Laden — Rumpfe in scripts/autoload/player_stats_persistence.gd


func to_dict() -> Dictionary:
	return PsPersistence.to_dict(self)


func from_dict(d: Dictionary) -> void:
	PsPersistence.from_dict(self, d)
