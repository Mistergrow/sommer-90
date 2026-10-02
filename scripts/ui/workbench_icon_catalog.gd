extends RefCounted
## Zustandsloser Katalog der Workbench-Desktop- und Schubladen-Icons.
##
## Der Bildschirm besitzt weiterhin Fenster, Auswahl und Eingaben. Dieses Modul
## beschreibt nur, welche Icons fuer Profil und Hardware sichtbar sind. Callbacks
## werden spaet an den Bildschirm gebunden, damit kein zweiter UI-Zustand entsteht.


static func desktop(host: Object, virtual_size: Vector2, desktop_label: String) -> Array:
	var right_x := virtual_size.x - 74.0
	var result: Array = [
		{"id": "wb", "label": desktop_label, "kind": "disk_wb", "pos": Vector2(right_x, 40),
			"cb": _callback(host, "_open_root")},
		{"id": "ram", "label": "RAM DISK", "kind": "disk_ram", "pos": Vector2(right_x, 116),
			"cb": _callback(host, "_open_ram")},
		{"id": "disks", "label": Loc.t(
			"ui.workbench_icon_catalog.disks", "Disketten"), "kind": "disk_plain",
			"pos": Vector2(right_x, 192), "cb": _callback(host, "_open_disk_directory")},
	]
	if bool(PlayerStats.hdd_info().get("available", false)):
		var hdd_label := "DH0" if PlayerStats.hdd_is_usable() else "DH0:NDOS"
		result.append({"id": "dh0", "label": hdd_label, "kind": "harddisk",
			"pos": Vector2(right_x - 4.0, 268), "cb": _callback(host, "_open_hdd")})
	return result


static func root(host: Object, profile_id: String) -> Array:
	# Die Werkbank-1.3-Diskette enthaelt nur ihre historischen Systemwerkzeuge.
	if not Wb13.is_modern():
		return [
			{"id": "programs", "label": Loc.t(
				"ui.workbench_icon_catalog.programs", "Programme"), "kind": "drawer",
				"cb": _callback(host, "_open_programs")},
			{"id": "utilities", "label": Loc.t(
				"ui.workbench_icon_catalog.utilities", "Werkzeuge"), "kind": "drawer",
				"cb": _callback(host, "_open_utilities")},
			{"id": "system", "label": Loc.t(
				"ui.workbench_icon_catalog.system", "System"), "kind": "drawer",
				"cb": _callback(host, "_open_system")},
			{"id": "expansion", "label": Loc.t(
				"ui.workbench_icon_catalog.expansion", "Erweiterung"), "kind": "drawer",
				"cb": _callback(host, "_open_expansion")},
			{"id": "empty", "label": Loc.t(
				"ui.workbench_icon_catalog.empty", "Leer"), "kind": "drawer",
				"cb": _callback(host, "_open_empty")},
			{"id": "shell", "label": "Shell", "kind": "shell",
				"cb": _callback(host, "_open_shell")},
			{"id": "prefs", "label": Loc.t(
				"ui.workbench_icon_catalog.prefs", "Voreinstellungen"), "kind": "prefs_drawer",
				"cb": _callback(host, "_open_prefs")},
			{"id": "trash", "label": Loc.t(
				"ui.workbench_icon_catalog.trashcan", "Papierkorb"), "kind": "trashcan",
				"cb": _callback(host, "_open_trash")},
		]
	var result: Array = [
		{"id": "programs", "label": Loc.t(
			"ui.workbench_icon_catalog.programs", "Programme"), "kind": "drawer",
			"cb": _callback(host, "_open_programs")},
		{"id": "system", "label": Loc.t(
			"ui.workbench_icon_catalog.system", "System"), "kind": "drawer",
			"cb": _callback(host, "_open_system")},
		{"id": "utilities", "label": Loc.t(
			"ui.workbench_icon_catalog.utilities", "Werkzeuge"), "kind": "drawer",
			"cb": _callback(host, "_open_utilities")},
		{"id": "tools", "label": Loc.t(
			"ui.workbench_icon_catalog.tools", "Hilfsprogramme"), "kind": "drawer",
			"cb": _callback(host, "_open_tools")},
		{"id": "prefs", "label": Loc.t(
			"ui.workbench_icon_catalog.prefs", "Voreinstellungen"), "kind": "prefs_drawer",
			"cb": _callback(host, "_open_prefs")},
		{"id": "wbstartup", "label": "WBStartup", "kind": "drawer",
			"cb": _callback(host, "_open_wbstartup")},
		{"id": "shell", "label": "Shell", "kind": "shell",
			"cb": _callback(host, "_open_shell")},
	]
	if profile_id in ["wb30", "wb31"]:
		result.insert(4, {"id": "storage", "label": Loc.t(
			"ui.workbench_icon_catalog.storage", "Speicher"), "kind": "drawer",
			"cb": _callback(host, "_open_storage")})
	else:
		result.append({"id": "trash", "label": Loc.t(
			"ui.workbench_icon_catalog.trashcan", "Papierkorb"), "kind": "trashcan",
			"cb": _callback(host, "_open_trash")})
	return result


## Grafischer Einstieg in alle wirklich installierten Anwendungen. Damit sind
## vorinstallierte Programme wie Sommer BASIC nicht nur ueber die Shell oder
## eine bereits eingerichtete Festplatte erreichbar. Der Katalog bleibt die
## einzige Quelle; nicht installierte beziehungsweise kuenftige Software wird
## hier bewusst nicht vorweggenommen.
static func programs() -> Array:
	var result: Array = []
	for program_value: Variant in ProgramLibrary.installed_programs():
		if not (program_value is Dictionary):
			continue
		var program: Dictionary = program_value
		var program_id := str(program.get("id", ""))
		if program_id.is_empty():
			continue
		result.append({
			"id": "program_" + program_id,
			"label": str(program.get("display_name", program_id)),
			"kind": str(program.get("icon", "tool")),
			"cb": UIManager.open_program.bind(program_id),
		})
	return result


static func utilities(host: Object, profile_id: String) -> Array:
	var has_printer := PlayerStats.has_printer()
	if Wb13.is_modern():
		var modern: Array = [
			{"id": "clock", "label": "Clock", "kind": "clock",
				"cb": _callback(host, "_open_clock")},
			{"id": "calculator", "label": "Calculator", "kind": "calculator",
				"cb": _callback(host, "_open_calc")},
			{"id": "more", "label": "MultiView" if profile_id in ["wb30", "wb31"] else "More",
				"kind": "more", "cb": _bound(host, "_open_os31_tool", "multiview")
					if profile_id == "wb31" else _callback(host, "_show_more")},
			{"id": "notepad", "label": "NotePad", "kind": "notepad",
				"cb": UIManager.open_text_editor},
			{"id": "shell", "label": "Shell", "kind": "shell",
				"cb": _callback(host, "_open_shell")},
		]
		if profile_id == "wb31":
			modern.insert(3, {"id": "amigaguide", "label": "AmigaGuide", "kind": "more",
				"cb": _bound(host, "_open_os31_tool", "amigaguide")})
			modern.insert(5, {"id": "ed", "label": "Ed", "kind": "notepad",
				"cb": _bound(host, "_open_os31_tool", "ed")})
			modern.append({"id": "commodities", "label": "Exchange", "kind": "tool",
				"cb": _bound(host, "_open_os31_tool", "exchange")})
		return modern
	return [
		{"id": "notepad", "label": "Notepad", "kind": "notepad",
			"cb": UIManager.open_text_editor},
		{"id": "more", "label": "More", "kind": "more",
			"cb": _callback(host, "_show_more")},
		{"id": "clock", "label": "Clock", "kind": "clock",
			"cb": _callback(host, "_open_clock")},
		{"id": "clockptr", "label": "ClockPtr", "kind": "clockptr",
			"cb": _callback(host, "_open_clockptr")},
		{"id": "say", "label": "Say", "kind": "say",
			"cb": _callback(host, "_say_gag")},
		{"id": "calculator", "label": "Calculator", "kind": "calculator",
			"cb": _callback(host, "_open_calc")},
		{"id": "cmd", "label": "Cmd", "kind": "cmd", "cb": func() -> void:
			UIManager.toast(Loc.t("ui.werkbank_screen.cmd_druckerausgabe_wird_in_datei_umgeleitet",
				"CMD: Druckerausgabe wird in eine Datei umgeleitet."))},
		{"id": "graphicdump", "label": "GraphicDump", "kind": "graphicdump",
			"ghost": not has_printer, "cb": func() -> void:
				UIManager.toast(Loc.t(
					"ui.werkbank_screen.graphicdump_schirm_rattert_aus_dem_nadeldrucker",
					"GraphicDump: Der Schirm rattert aus dem Nadeldrucker."))},
		{"id": "printfiles", "label": "PrintFiles", "kind": "printfiles",
			"ghost": not has_printer, "cb": func() -> void:
				UIManager.toast(Loc.t(
					"ui.werkbank_screen.printfiles_nichts_zum_drucken_ausgewahlt",
					"PrintFiles: Nichts zum Drucken ausgewählt."))},
		{"id": "installprinter", "label": "InstallPrinter", "kind": "installprinter",
			"cb": UIManager.open_printer_config},
	]


static func system(host: Object, profile_id: String) -> Array:
	if Wb13.is_modern():
		var modern: Array = [
			{"id": "shell", "label": "Shell", "kind": "shell",
				"cb": _callback(host, "_open_shell")},
			{"id": "diskcopy", "label": "DiskCopy", "kind": "diskcopy",
				"cb": UIManager.open_disk_copy},
			{"id": "format", "label": "Format", "kind": "format",
				"cb": UIManager.open_program.bind("disk_formatter")},
			{"id": "nofastmem", "label": "NoFastMem", "kind": "nofastmem",
				"cb": func() -> void:
					UIManager.toast(Loc.t("ui.workbench_icon_catalog.nofastmem_nachster_start_ohne_fast_ram", "NoFastMem: nächster Start ohne Fast-RAM."))},
			{"id": "setmap", "label": "SetMap", "kind": "setmap", "cb": func() -> void:
				UIManager.toast(Loc.t("ui.workbench_icon_catalog.setmap_tastaturbelegung_d_geladen", "SetMap: Tastaturbelegung »d« geladen."))},
			{"id": "version", "label": "Version", "kind": "more",
				"cb": _callback(host, "_show_more")},
		]
		if profile_id == "wb31":
			modern.insert(3, {"id": "diskinfo", "label": "Disk-Info", "kind": "more",
				"cb": _bound(host, "_open_os31_tool", "diskinfo")})
		if bool(PlayerStats.hdd_info().get("available", false)):
			modern.append({"id": "hdtoolbox", "label": "HDToolBox", "kind": "harddisk",
				"cb": UIManager.open_hdd_setup})
		return modern
	var classic: Array = [
		{"id": "cli", "label": "CLI", "kind": "cli",
			"cb": _callback(host, "_open_shell")},
		{"id": "diskcopy", "label": "DiskCopy", "kind": "diskcopy",
			"cb": UIManager.open_disk_copy},
		{"id": "format", "label": "Format", "kind": "format",
			"cb": UIManager.open_program.bind("disk_formatter")},
		{"id": "fastmemfirst", "label": "FastMemFirst", "kind": "fastmem",
			"cb": func() -> void:
				UIManager.toast(Loc.t(
					"ui.werkbank_screen.fastmemfirst_hase_legt_den_schnellen_speicher",
					"FastMemFirst: Der Hase legt den schnellen Speicher nach vorn."))},
		{"id": "setmap", "label": "SetMap", "kind": "setmap", "cb": func() -> void:
			UIManager.toast(Loc.t("ui.workbench_icon_catalog.setmap_tastaturbelegung_d_deutsch_geladen", "SetMap: Tastaturbelegung »d« (deutsch) geladen."))},
		{"id": "initprinter", "label": "InitPrinter", "kind": "printer",
			"cb": func() -> void:
				UIManager.toast(Loc.t("ui.werkbank_screen.initprinter_drucker_zuruckgesetzt",
					"InitPrinter: Drucker zurückgesetzt.") if PlayerStats.has_printer()
					else Loc.t("ui.workbench_icon_catalog.initprinter_no_printer",
						"InitPrinter: Kein Drucker angeschlossen."))},
		{"id": "nofastmem", "label": "NoFastMem", "kind": "nofastmem",
			"cb": func() -> void:
				UIManager.toast(Loc.t("ui.werkbank_screen.nofastmem_hase_schlaft_jetzt",
					"NoFastMem: Der Hase schläft jetzt."))},
		{"id": "mergemem", "label": "MergeMem", "kind": "mergemem",
			"cb": func() -> void:
				UIManager.toast(Loc.t(
					"ui.werkbank_screen.mergemem_speicherblocke_zusammengelegt",
					"MergeMem: Speicherblöcke zusammengelegt."))},
		{"id": "fixfonts", "label": "FixFonts", "kind": "fixfonts",
			"cb": func() -> void:
				UIManager.toast(Loc.t("ui.workbench_icon_catalog.fixfonts_alle_schriften_in_ordnung", "FixFonts: Alle Schriften in Ordnung."))},
	]
	if bool(PlayerStats.hdd_info().get("available", false)):
		classic.append({"id": "hdtoolbox", "label": "HDToolBox", "kind": "harddisk",
			"cb": UIManager.open_hdd_setup})
	return classic


static func prefs(host: Object) -> Array:
	if Wb13.is_modern():
		return [
			{"id": "font", "label": "Font", "kind": "preferences",
				"cb": UIManager.open_wb_prefs},
			{"id": "input", "label": "Input", "kind": "pointer",
				"cb": UIManager.open_wb_prefs},
			{"id": "locale", "label": "Locale", "kind": "preferences",
				"cb": func() -> void:
					UIManager.toast(Loc.t("ui.workbench_icon_catalog.locale_active",
						"Sprache: Deutsch (Deutschland)."))},
			{"id": "palette", "label": "Palette", "kind": "paint",
				"cb": UIManager.open_wb_prefs},
			{"id": "pointer", "label": "Pointer", "kind": "pointer",
				"cb": UIManager.open_wb_prefs},
			{"id": "printer", "label": "Printer", "kind": "printer",
				"ghost": not PlayerStats.has_printer(), "cb": UIManager.open_printer_config},
			{"id": "screenmode", "label": "ScreenMode", "kind": "preferences",
				"cb": UIManager.open_screenmode},
			{"id": "serial", "label": "Serial", "kind": "serial",
				"ghost": not PlayerStats.has_modem(), "cb": UIManager.open_modem_config},
			{"id": "sound", "label": "Sound", "kind": "gauge",
				"cb": UIManager.open_wb_prefs},
			{"id": "time", "label": "Time", "kind": "clock",
				"cb": _callback(host, "_open_clock")},
		]
	return [
		{"id": "preferences", "label": "Preferences", "kind": "preferences",
			"cb": UIManager.open_wb_prefs},
		{"id": "copyprefs", "label": "CopyPrefs", "kind": "copyprefs",
			"cb": func() -> void:
				UIManager.toast(Loc.t("ui.workbench_icon_catalog.copyprefs_einstellungen_auf_diskette_kopiert", "CopyPrefs: Einstellungen auf Diskette kopiert."))},
		{"id": "pointer", "label": "Pointer", "kind": "pointer",
			"cb": func() -> void:
				UIManager.toast(Loc.t("ui.werkbank_screen.pointer_pfeil_bleibt_wie_er_ist",
					"Pointer: Der Pfeil bleibt, wie er ist."))},
		{"id": "printer", "label": "Printer", "kind": "printer",
			"ghost": not PlayerStats.has_printer(), "cb": UIManager.open_printer_config},
		{"id": "serial", "label": "Serial", "kind": "serial",
			"ghost": not PlayerStats.has_modem(), "cb": UIManager.open_modem_config},
	]


static func tools(host: Object, profile_id: String) -> Array:
	var result: Array = [
		{"id": "calculator", "label": "Calculator", "kind": "calculator",
			"cb": _callback(host, "_open_calc")},
		{"id": "commodities", "label": "Commodities", "kind": "tool",
			"cb": _callback(host, "_open_commodities")},
		{"id": "iconedit", "label": "IconEdit", "kind": "paint",
			"cb": UIManager.open_program.bind("icon_editor")},
		{"id": "keyshow", "label": "KeyShow", "kind": "pointer",
			"cb": _callback(host, "_open_keyshow")},
	]
	if profile_id == "wb31":
		result.append({"id": "prepcard", "label": "PrepCard", "kind": "disk_plain",
			"cb": _bound(host, "_open_os31_tool", "prepcard")})
		result.append({"id": "installer", "label": "Installer", "kind": "tool",
			"cb": _bound(host, "_open_os31_tool", "installer")})
	return result


static func storage(host: Object) -> Array:
	return [
		{"id": "dosdrivers", "label": "DOSDrivers", "kind": "drawer",
			"cb": _callback(host, "_open_storage_dosdrivers")},
		{"id": "monitors", "label": "Monitors", "kind": "drawer",
			"cb": func() -> void:
				UIManager.toast(Loc.t("ui.workbench_icon_catalog.monitors_pal_ntsc_aga_modi", "Monitors: PAL, NTSC und AGA-Modi."))},
		{"id": "printers", "label": "Printers", "kind": "drawer",
			"cb": UIManager.open_printer_config},
	]


static func wbstartup(host: Object, profile_id: String) -> Array:
	if profile_id != "wb31":
		return []
	return [
		{"id": "wbstartup_prefs", "label": "WBStartup Prefs", "kind": "preferences",
			"cb": _bound(host, "_open_os31_tool", "wbstartup")},
		{"id": "clock", "label": "Clock", "kind": "clock",
			"cb": _callback(host, "_open_clock")},
		{"id": "exchange", "label": "Exchange", "kind": "tool",
			"cb": _bound(host, "_open_os31_tool", "exchange")},
	]


static func dosdrivers(host: Object) -> Array:
	return [
		{"id": "pc0", "label": "PC0", "kind": "disk_plain",
			"cb": _bound(host, "_open_os31_tool", "crossdos")},
		{"id": "pc1", "label": "PC1", "kind": "disk_plain",
			"cb": _bound(host, "_open_os31_tool", "crossdos")},
		{"id": "cd0", "label": "CD0", "kind": "disk_plain",
			"cb": UIManager.open_program.bind("cdfs_homage")},
	]


static func hdd(host: Object) -> Array:
	var info: Dictionary = PlayerStats.hdd_info()
	var result: Array = [
		{"id": "system", "label": "System", "kind": "drawer",
			"cb": _callback(host, "_open_system")},
		{"id": "c", "label": "C", "kind": "drawer",
			"cb": _callback(host, "_open_system")},
		{"id": "devs", "label": "Devs", "kind": "drawer",
			"cb": _callback(host, "_open_system")},
		{"id": "libs", "label": "Libs", "kind": "drawer",
			"cb": _callback(host, "_open_system")},
		{"id": "s", "label": "S", "kind": "drawer",
			"cb": _callback(host, "_open_system")},
		{"id": "utilities", "label": "Utilities", "kind": "drawer",
			"cb": _callback(host, "_open_utilities")},
	]
	var files: Dictionary = info.get("files", {})
	for path: Variant in files:
		var entry: Variant = files[path]
		if not (entry is Dictionary) or str(entry.get("kind", "")) != "program":
			continue
		var program_id := str(entry.get("program_id", ""))
		var program: Dictionary = ProgramLibrary.get_program(program_id)
		result.append({
			"id": "hdd_program_" + program_id,
			"label": str(program.get("display_name", program_id)),
			"kind": str(program.get("icon", "tool")),
			"cb": UIManager.open_program.bind(program_id),
		})
	result.append({"id": "diskinfo", "label": "Disk-Info", "kind": "more",
		"cb": _callback(host, "_show_hdd_info")})
	result.append({"id": "trash", "label": "Trashcan", "kind": "trashcan",
		"cb": _callback(host, "_open_trash")})
	return result


static func _callback(host: Object, method: StringName) -> Callable:
	return Callable(host, method)


static func _bound(host: Object, method: StringName, argument: Variant) -> Callable:
	return Callable(host, method).bind(argument)
