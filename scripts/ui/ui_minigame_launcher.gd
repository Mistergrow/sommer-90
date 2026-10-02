extends RefCounted
## Zentrale Start- und Zugangsregeln der UI-Minispiele.
##
## UIManager bleibt die stabile öffentliche Fassade. Dieses Modul besitzt die
## eigentlichen Gates, Fenster-Schlüssel und die Übergabe der Startparameter,
## damit Sidebar, Dialoge und Tests nicht voneinander abweichende Regeln bauen.

const BoxSort := preload("res://scripts/ui/box_sort_minigame.gd")
const DriveClean := preload("res://scripts/ui/drive_clean_minigame.gd")
const JoystickRepair := preload("res://scripts/ui/joystick_repair_minigame.gd")
const ListingType := preload("res://scripts/ui/listing_type_minigame.gd")
const CableUntangle := preload("res://scripts/ui/cable_untangle_minigame.gd")
const RoomTidy := preload("res://scripts/ui/room_tidy_minigame.gd")
const MonitorTune := preload("res://scripts/ui/monitor_tune_minigame.gd")
const TrackerPattern := preload("res://scripts/ui/tracker_pattern_minigame.gd")
const HardwareAssembly := preload("res://scripts/ui/hardware_assembly_minigame.gd")
const BbsCarrier := preload("res://scripts/ui/bbs_carrier_minigame.gd")
const Bargain := preload("res://scripts/ui/bargain_minigame.gd")
const DiskRescue := preload("res://scripts/ui/disk_rescue_minigame.gd")
const DiskRepair := preload("res://scripts/ui/disk_repair_minigame.gd")
const PrinterAlign := preload("res://scripts/ui/printer_align_minigame.gd")
const Mixtape := preload("res://scripts/ui/mixtape_minigame.gd")
const CracktroOptimization := preload("res://scripts/ui/cracktro_optimization_minigame.gd")
const ShopDiagnosis := preload("res://scripts/ui/shop_diagnosis_minigame.gd")
const JobShift := preload("res://scripts/ui/job_shift_minigame.gd")
const HouseholdSprint := preload("res://scripts/ui/household_sprint_minigame.gd")


static func open_box_sort(ui: Node) -> void:
	if DiskManager.media_count() < 2:
		_toast(ui, Loc.t("sys.ui_manager.zum_sortieren_braucht_box_mindestens_zwei",
			"Zum Sortieren braucht die Box mindestens zwei Disketten."))
		return
	_replace(ui, "win_box_sort", func() -> Control: return BoxSort.new())


static func open_drive_clean(ui: Node) -> void:
	var gate: Dictionary = DriveClean.can_start()
	if not _gate_ok(ui, gate, "Der Lesekopf kann gerade nicht gereinigt werden."):
		return
	_replace(ui, "win_drive_clean", func() -> Control: return DriveClean.new())


static func open_joystick_repair(ui: Node) -> void:
	var gate: Dictionary = JoystickRepair.can_start()
	if not _gate_ok(ui, gate, "Die Joystick-Werkstatt ist noch nicht verfügbar."):
		return
	_replace(ui, "win_joystick_repair", func() -> Control: return JoystickRepair.new())


static func open_listing_type(ui: Node, listing_id := "") -> void:
	var gate: Dictionary = ListingType.can_start(str(listing_id))
	if not _gate_ok(ui, gate, "Das Listing ist noch nicht verfügbar."):
		return
	ui.call("close_window", "win_magazine")
	_toggle(ui, "win_listing_type", func() -> Control:
		var game: Control = ListingType.new()
		game.set("listing_id", str(listing_id))
		return game)


static func open_cable_untangle(ui: Node, job_id := "job_gruber_cables") -> void:
	var gate: Dictionary = CableUntangle.can_start(job_id)
	if not _gate_ok(ui, gate, "Grubers Kabelauftrag ist gerade nicht verfügbar."):
		return
	_replace(ui, "win_cable_untangle", func() -> Control:
		var game := CableUntangle.new()
		game.job_id = job_id
		return game)


static func open_room_tidy(ui: Node) -> void:
	var gate: Dictionary = RoomTidy.can_start()
	if not _gate_ok(ui, gate, "Das Zimmer kann gerade nicht aufgeräumt werden."):
		return
	_toggle(ui, "win_room_tidy", func() -> Control: return RoomTidy.new())


static func open_monitor_tune(ui: Node) -> void:
	var gate: Dictionary = MonitorTune.can_start()
	if not bool(gate.get("ok", false)):
		if not bool(GameManager.flags.get("learned_monitor_calibration", false)):
			GameManager.flags["wants_monitor_calibration"] = true
		_toast(ui, str(gate.get("reason", "Der Monitor kann gerade nicht kalibriert werden.")))
		return
	_toggle(ui, "win_monitor_tune", func() -> Control: return MonitorTune.new())


static func open_tracker_pattern(ui: Node) -> void:
	var gate: Dictionary = TrackerPattern.can_start()
	if not _gate_ok(ui, gate, "Das Tracker-Labor ist gerade nicht verfügbar."):
		return
	MusicManager.stop_disk_playback()
	_toggle(ui, "win_tracker_pattern", func() -> Control: return TrackerPattern.new())


static func open_hardware_assembly(ui: Node, job_id := "") -> void:
	var gate: Dictionary = HardwareAssembly.can_start(job_id)
	if not _gate_ok(ui, gate, "Hardware-Montage derzeit nicht verfügbar."):
		return
	_replace(ui, "win_hardware_assembly", func() -> Control:
		var game := HardwareAssembly.new()
		game.job_id = job_id
		return game)


static func open_bbs_carrier(ui: Node, file_entry: Dictionary) -> void:
	var gate: Dictionary = BbsCarrier.can_start(file_entry)
	if not _gate_ok(ui, gate, "Carrier-Test derzeit nicht verfügbar."):
		return
	_replace(ui, "win_bbs_carrier", func() -> Control:
		var game := BbsCarrier.new()
		game.file_entry = file_entry.duplicate(true)
		return game)


static func open_bargain(ui: Node, offer_id: int) -> void:
	var gate: Dictionary = Bargain.can_start(offer_id)
	if not _gate_ok(ui, gate, "Dieses Gespräch ist beendet."):
		return
	_replace(ui, "win_bargain", func() -> Control:
		var game := Bargain.new()
		game.offer_id = offer_id
		return game)


static func open_disk_rescue(ui: Node, source: Disk) -> void:
	var gate: Dictionary = DiskRescue.can_start(source)
	if not _gate_ok(ui, gate, "Datenrettung nicht möglich."):
		return
	_replace(ui, "win_disk_rescue", func() -> Control:
		var game := DiskRescue.new()
		game.source = source
		return game)


static func open_disk_repair(ui: Node, source: Disk) -> void:
	var gate: Dictionary = DiskRepair.can_start(source)
	if not _gate_ok(ui, gate, "Physische Diskettenreparatur nicht möglich."):
		return
	_replace(ui, "win_disk_repair", func() -> Control:
		var game := DiskRepair.new()
		game.source = source
		return game)


static func open_printer_align(ui: Node) -> void:
	var gate: Dictionary = PrinterAlign.can_start()
	if not _gate_ok(ui, gate, "Drucker nicht bereit."):
		return
	_replace(ui, "win_printer_align", func() -> Control: return PrinterAlign.new())


static func open_mixtape(ui: Node) -> void:
	var gate: Dictionary = Mixtape.can_start()
	if not _gate_ok(ui, gate, "Mixtape nicht möglich."):
		return
	_replace(ui, "win_mixtape", func() -> Control: return Mixtape.new())


static func open_cracktro_optimization(ui: Node, project: Dictionary = {}) -> void:
	var gate: Dictionary = CracktroOptimization.can_start()
	if not _gate_ok(ui, gate, "Profiler nicht bereit."):
		return
	_replace(ui, "win_cracktro_opt", func() -> Control:
		var game := CracktroOptimization.new()
		game.project = project.duplicate(true)
		return game)


static func open_shop_diagnosis(ui: Node, job_id := "job_gruber_diagnosis") -> void:
	var gate: Dictionary = ShopDiagnosis.can_start(job_id)
	if not _gate_ok(ui, gate, "Diagnoseauftrag nicht verfügbar."):
		return
	_replace(ui, "win_shop_diagnosis", func() -> Control:
		var game := ShopDiagnosis.new()
		game.job_id = job_id
		return game)


static func open_job_shift(ui: Node, job_id: String) -> void:
	var gate: Dictionary = JobShift.can_start(job_id)
	if not _gate_ok(ui, gate, "Diese Arbeitsschicht ist gerade nicht verfügbar."):
		return
	_replace(ui, "win_job_shift", func() -> Control:
		var game := JobShift.new()
		game.job_id = job_id
		return game)


static func open_household_sprint(ui: Node, chore_id: String) -> void:
	var gate: Dictionary = HouseholdSprint.can_start(chore_id)
	if not _gate_ok(ui, gate, "Diese Hausarbeit kann gerade nicht begonnen werden."):
		return
	_replace(ui, "win_household_sprint", func() -> Control:
		var game := HouseholdSprint.new()
		game.chore_id = chore_id
		return game)


static func _gate_ok(ui: Node, gate: Dictionary, fallback: String) -> bool:
	if bool(gate.get("ok", false)):
		return true
	_toast(ui, str(gate.get("reason", fallback)))
	return false


static func _replace(ui: Node, key: String, factory: Callable) -> void:
	ui.call("close_window", key)
	_toggle(ui, key, factory)


static func _toggle(ui: Node, key: String, factory: Callable) -> void:
	ui.call("toggle_window", key, factory)


static func _toast(ui: Node, message: String) -> void:
	ui.call("toast", message)
