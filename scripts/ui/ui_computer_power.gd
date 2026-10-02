extends RefCounted
## Stromkette und Bootpfad des Zimmercomputers; UIManager bleibt die stabile API.

const BootSelectScreenScript := preload("res://scripts/ui/boot_select_screen.gd")
const UiLiveMonitor := preload("res://scripts/ui/ui_live_monitor.gd")
const Versions := preload("res://scripts/ui/workbench_versions.gd")


static func domain_on(owner: Node, domain: String) -> bool:
	match domain:
		"strip": return bool(owner.get("strip_power"))
		"monitor": return bool(owner.get("strip_power")) and bool(owner.get("monitor_power"))
		"amiga": return bool(owner.get("strip_power")) and bool(owner.get("amiga_power"))
		_: return true


static func boot_state(owner: Node) -> String:
	if not domain_on(owner, "monitor"):
		return "off"
	if not domain_on(owner, "amiga"):
		return "nosignal"
	return "booted" if bool(owner.get("system_disk_inserted")) else "kickstart"


static func has_system_disk() -> bool:
	for disk in DiskManager.media_disks():
		if disk.content_type == "system" and disk.condition > 0:
			return true
	return false


static func open_boot_selector(owner: Node) -> void:
	var host: Control = GameManager.location_host
	if host == null or host.get_node_or_null("BootSelect") != null:
		return
	DiskManager.ensure_bundled_system_media()
	AudioManager.floppy_insert()
	var screen := BootSelectScreenScript.new()
	screen.name = "BootSelect"
	host.add_child(screen)
	owner.call("_set_computer_ui", true)


static func close_boot_selector() -> void:
	var host: Control = GameManager.location_host
	if host == null:
		return
	var screen := host.get_node_or_null("BootSelect")
	if screen != null:
		screen.queue_free()


static func boot_from_disk(owner: Node, disk) -> void:
	if not disk.is_bootable():
		owner.call("toast", Loc.t("ui.ui_computer_power.not_bootable",
			"»%s« ist nicht bootfähig — der Amiga wartet weiter auf eine Startdiskette.") % disk.display_name())
		return
	if disk.boots_workbench():
		var profile_id := Versions.disk_profile_id(disk)
		if not profile_id.is_empty() and not Versions.is_compatible(profile_id):
			var cfg := Versions.profile(profile_id)
			owner.call("toast", Loc.t("ui.ui_computer_power.system_incompatible",
				"»%s« braucht mindestens %s — diese Systemdiskette startet auf dem aktiven Rechner nicht.") % [
				disk.display_name(), str(cfg.get("minimum_machine", "einen neueren Amiga"))])
			return
		close_boot_selector()
		owner.set("boot_source", "floppy")
		AudioManager.floppy_read()
		if profile_id.is_empty():
			profile_id = Versions.native_id()
		owner.set("workbench_profile_id", profile_id)
		owner.set("system_disk_inserted", true)
		owner.emit_signal("monitor_changed")
		owner.call("toast", (Loc.t("ui.ui_computer_power.system_booting",
			"»%s« eingelegt — der Amiga bootet die Sommerbench …") if disk.content_type == "system"
			else Loc.t("ui.ui_computer_power.pd_booting",
				"»%s« bootet ihr eigenes System — die PD-Tools liegen bereit.")) % disk.display_name())
		owner.call("open_werkbank")
	elif disk.program_id != "":
		# Physische Startdisketten sind absichtlich ein eigener Bezugsweg. X-COPY
		# und andere Tools dürfen davon booten, ohne vorher auf DH0: installiert
		# worden zu sein; Jahr und Hardware werden trotzdem zentral geprüft.
		if not bool(owner.call("open_program_from_media", disk.program_id)):
			return
		close_boot_selector()
		owner.set("boot_source", "floppy")
		AudioManager.floppy_read()
		owner.call("toast", Loc.t("ui.ui_computer_power.program_booting",
			"»%s« bootet direkt von Diskette.") % disk.display_name())
	else:
		close_boot_selector()
		owner.set("boot_source", "floppy")
		AudioManager.floppy_read()
		owner.call("play_disk_flow", disk)


static func boot_from_hdd(owner: Node) -> bool:
	var info: Dictionary = PlayerStats.hdd_info()
	if not bool(info.get("available", false)):
		owner.call("toast", Loc.t("ui.ui_computer_power.no_hdd",
			"DH0: Kein passender Massenspeicher am aktiven Amiga."))
		return false
	if not PlayerStats.hdd_bootable():
		owner.call("toast", Loc.t("ui.ui_computer_power.hdd_not_bootable",
			"DH0: Nicht bootfähig — Systemdiskette einlegen und installieren."))
		return false
	var profile_id := str(info.get("installed_profile", ""))
	if profile_id.is_empty() or not Versions.is_compatible(profile_id):
		owner.call("toast", Loc.t("ui.ui_computer_power.hdd_system_incompatible",
			"DH0: Das installierte System ist mit diesem Amiga nicht kompatibel."))
		return false
	close_boot_selector()
	owner.set("workbench_profile_id", profile_id)
	owner.set("boot_source", "hdd")
	# Der historische Variablenname bleibt save-/UI-kompatibel; true bedeutet
	# inzwischen allgemein „ein Systemmedium wurde erfolgreich gebootet“.
	owner.set("system_disk_inserted", true)
	var host: Control = GameManager.location_host
	var running_workbench := host.get_node_or_null("Werkbank") if host != null else null
	if running_workbench != null:
		running_workbench.tree_exited.connect(func() -> void:
			owner.call_deferred("open_werkbank"), CONNECT_ONE_SHOT)
		running_workbench.queue_free()
		owner.set("wb_booted", false)
	owner.emit_signal("monitor_changed")
	owner.call("toast", Loc.t("ui.ui_computer_power.hdd_booting",
		"DH0: %s bootet über %s …") % [
		str(Versions.profile(profile_id).get("name", profile_id)),
		str(info.get("controller", "Controller"))])
	# Neustart nach Installation: Bei einer laufenden Disketten-Werkbank öffnet
	# der oben verbundene tree_exited-Callback erst nach ihrem Abbau das DH0-Profil.
	if running_workbench == null:
		owner.call("open_werkbank")
	return true


static func set_monitor_power(owner: Node, on: bool) -> void:
	if on and not bool(owner.get("strip_power")) or bool(owner.get("monitor_power")) == on:
		return
	owner.set("monitor_power", on)
	if on:
		owner.set("monitor_warmup_t", 0.9)
		AudioManager.start_crt_hum()
	else:
		owner.set("monitor_on", false)
		AudioManager.stop_crt_hum()
	if bool(owner.get("at_computer")):
		owner.call("set_crt", on and bool(SettingsManager.value("crt_auto_monitor")))
	owner.emit_signal("power_changed")
	owner.emit_signal("monitor_changed")


static func reset(owner: Node) -> void:
	for key in ["strip_power", "monitor_power", "amiga_power", "monitor_on", "monitor_live",
			"system_disk_inserted", "wb_booted"]:
		owner.set(key, false)
	owner.set("monitor_texture", null)
	owner.set("workbench_profile_id", "")
	owner.set("boot_source", "")
	owner.set("monitor_warmup_t", 0.0)
	var live_viewport: SubViewport = owner.get("_live_vp")
	if is_instance_valid(live_viewport):
		live_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	UiLiveMonitor.detach(owner)
	owner.call("_close_all_fullscreen")
	owner.call("_set_computer_ui", false)
	owner.call("set_crt", false)
	MusicManager.stop_disk_playback()
	AudioManager.stop_crt_hum()
	BBSManager.hang_up()
	owner.emit_signal("power_changed")
	owner.emit_signal("monitor_changed")


static func set_amiga_power(owner: Node, on: bool) -> void:
	if on and not bool(owner.get("strip_power")) or bool(owner.get("amiga_power")) == on:
		return
	owner.set("amiga_power", on)
	if not on:
		owner.set("system_disk_inserted", false)
		owner.set("wb_booted", false)
		owner.set("workbench_profile_id", "")
		owner.set("boot_source", "")
		MusicManager.stop_disk_playback()
		BBSManager.hang_up()
		owner.call("stop_live_monitor")
	owner.emit_signal("power_changed")
	owner.emit_signal("monitor_changed")


static func set_strip_power(owner: Node, on: bool) -> void:
	if bool(owner.get("strip_power")) == on:
		return
	if not on:
		set_monitor_power(owner, false)
		set_amiga_power(owner, false)
	owner.set("strip_power", on)
	owner.emit_signal("power_changed")
