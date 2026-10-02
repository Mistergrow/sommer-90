class_name UiProgramLauncher
extends RefCounted
## Eine Verantwortung: Vollbild-Programme auf dem Heimcomputer starten,
## umschalten und beenden. UIManager behält die öffentliche API, während die
## Programm-Bibliothek und ihre konkreten Skripte hier gekapselt bleiben.

const WerkbankScreenScript := preload("res://scripts/ui/werkbank_screen.gd")
const GuruScreenScript := preload("res://scripts/ui/guru_screen.gd")
const XCopyScreenScript := preload("res://scripts/ui/xcopy_screen.gd")
const GenericProgramScript := preload("res://scripts/ui/generic_program_app.gd")
const DiskAccessPolicy := preload("res://scripts/ui/disk_access_policy.gd")
const APP_SCRIPTS := {
	"modem": preload("res://scripts/ui/modem_config_window.gd"),
	"printer": preload("res://scripts/ui/printer_config_window.gd"),
	"mod_player": preload("res://scripts/ui/mod_player_app.gd"),
	"virus": preload("res://scripts/ui/virus_checker_app.gd"),
	"paint": preload("res://scripts/ui/paint_app.gd"),
	"sysinfo": preload("res://scripts/ui/sysinfo_app.gd"),
	"prefs": preload("res://scripts/ui/wb_prefs_app.gd"),
	"text": preload("res://scripts/ui/text_editor_app.gd"),
	"format": preload("res://scripts/ui/disk_formatter_app.gd"),
	"hdd_setup": preload("res://scripts/ui/hdd_setup_app.gd"),
	"screenmode": preload("res://scripts/ui/screenmode_app.gd"),
	"sommer_basic": preload("res://scripts/ui/sommer_basic_app.gd"),
	"sommer_suite": preload("res://scripts/ui/sommer_suite_app.gd"),
	"sommer_game": preload("res://scripts/ui/sommer_game_app.gd"),
}


static func open_werkbank(ui: Node) -> void:
	AchievementManager.note("booted_amiga")
	var host: Control = GameManager.location_host
	if host == null:
		return
	var existing := host.get_node_or_null("Werkbank")
	if existing != null:
		ui.call("stand_up_from_computer")
		return
	var workbench: Control = WerkbankScreenScript.new()
	workbench.name = "Werkbank"
	host.add_child(workbench)
	ui.call("_set_computer_ui", true)


static func open_named(ui: Node, node_name: String, script_id: String) -> void:
	var script: GDScript = APP_SCRIPTS.get(script_id)
	if script != null:
		open_app(ui, node_name, script)


static func open_program(ui: Node, id: String) -> bool:
	var status: Dictionary = ProgramLibrary.launch_status(id)
	# Unbekannte IDs gehoeren nicht automatisch zur ProgramLibrary. Insbesondere
	# statische Vollspiele besitzen ihren eigenen Registry-/Disk-Boot-Pfad und
	# duerfen hier keine falsche "nicht installiert"-Meldung bekommen.
	if not bool(status.get("known", false)):
		return false
	if not bool(status.get("ok", false)):
		if ui.has_method("toast"):
			ui.call("toast", str(status.get("reason", "")))
		return false
	return _launch_authorized(ui, str(status.get("id", id)), status.get("program", {}))


## Startet ein Programm direkt von einem physischen Datentraeger. Anders als
## Sommerbench verlangt dieser Weg keine Installation; ProgramLibrary prueft
## trotzdem dieselben Zeit- und Hardwaregrenzen.
static func open_program_from_media(ui: Node, id: String) -> bool:
	var status: Dictionary = ProgramLibrary.launch_from_media_status(id)
	if not bool(status.get("known", false)):
		return false
	if not bool(status.get("ok", false)):
		if ui.has_method("toast"):
			ui.call("toast", str(status.get("reason", "")))
		return false
	return _launch_authorized(ui, str(status.get("id", id)), status.get("program", {}))


## Gemeinsamer, bereits autorisierter Router. Kein konkreter App-Start darf
## nochmals Besitz annehmen oder den Datentraeger ungefragt installieren.
static func _launch_authorized(ui: Node, id: String, program: Dictionary) -> bool:
	if id == "disk_formatter":
		open_named(ui, "app_disk_formatter", "format")
		return true
	var app_key := str(program.get("app_key", ""))
	if app_key != "" and app_key != "generic" and ui.has_method(app_key):
		ui.call(app_key)
		return true
	var host: Control = GameManager.location_host
	if host == null:
		return false
	var node_name := "app_" + id
	var existing := host.get_node_or_null(node_name)
	if existing != null:
		existing.queue_free()
		return true
	var app: Control = GenericProgramScript.new()
	app.name = node_name
	app.program = program
	host.add_child(app)
	return true


static func open_app(ui: Node, key: String, script: GDScript) -> void:
	var host: Control = GameManager.location_host
	if host == null:
		return
	var existing := host.get_node_or_null(key)
	if existing != null:
		existing.queue_free()
		return
	var app: Control = script.new()
	app.name = key
	host.add_child(app)
	ui.call("_set_computer_ui", true)


static func open_xcopy(ui: Node, professional: bool, source: Disk = null,
		operation_kind := "copy", edition := "") -> void:
	var resolved_edition := str(edition)
	if resolved_edition.is_empty():
		resolved_edition = "professional" if professional else "classic"
	var program_name := "Sommer Copy 92" if resolved_edition == "sommer" else "X-COPY"
	if not DiskAccessPolicy.require_computer(ui, program_name):
		return
	var host: Control = GameManager.location_host
	if host == null:
		return
	var existing := host.get_node_or_null("XCopy")
	if existing != null:
		var same := str(existing.get("edition")) == resolved_edition
		existing.queue_free()
		if same:
			return
	var screen: Control = XCopyScreenScript.new()
	screen.name = "XCopy"
	screen.pro = professional
	screen.edition = resolved_edition
	screen.initial_source = source
	screen.operation_kind = str(operation_kind)
	ui.call("close_window", "win_diskbox")
	host.add_child(screen)
	ui.call("_set_computer_ui", true)


static func show_guru(ui: Node, code: String) -> void:
	var host: Control = GameManager.location_host
	if host == null or host.get_node_or_null("Guru") != null:
		return
	var guru: Control = GuruScreenScript.new()
	guru.name = "Guru"
	guru.code = "#%08X.%08X" % [[3, 4, 0xB][randi() % 3], randi()] if code.is_empty() else code
	host.add_child(guru)
	ui.call("_set_computer_ui", true)


static func reboot_from_guru(ui: Node) -> void:
	ui.set("wb_booted", false)
	ui.call("_close_all_fullscreen")
	await ui.get_tree().create_timer(0.5).timeout
	if bool(ui.get("amiga_power")) and bool(ui.get("monitor_power")):
		ui.call("open_werkbank")
