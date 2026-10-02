class_name WerkbankScreen
extends Control
## Hardwaregebundene Workbench-Hommage: 1.3, 2.05, 3.0 und 3.1 nutzen jeweils
## eigene Revisionen, Starttexte, Menues, Schubladen und Fensterchromatik.
## Menues erscheinen originalgetreu bei gehaltener rechter Maustaste.

const InfoText := preload("res://scripts/ui/workbench_info_text.gd")

const VW := 640.0
const VH := 400.0
const TB := 20.0
const FLOPPY_BOOT_SECONDS := 3.6
const FLOPPY_LINE_SECONDS := 0.55
const HDD_IO_FACTOR_MIN := 1.5
const HDD_IO_FACTOR_MAX := 4.75
const HDD_BOOT_SECONDS_MIN := 1.65
const HDD_BOOT_SECONDS_MAX := 2.45
const WbDiskDirectoryWindowScript := preload("res://scripts/ui/wb_disk_directory_window.gd")
const WbTextWindowScript := preload("res://scripts/ui/wb_text_window.gd")
const Versions := preload("res://scripts/ui/workbench_versions.gd")
const Workbench31ToolAppScript := preload("res://scripts/ui/workbench31_tool_app.gd")
const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")
const IconCatalog := preload("res://scripts/ui/workbench_icon_catalog.gd")

# Menues wie Workbench 1.3 (Geister-Eintraege bleiben optisch vorhanden).
const CLASSIC_MENUS := [
	{"title": "Werkbank", "x": 8.0, "w": 140.0, "items": [
		["Open", true], ["Close", true], ["Duplicate", false], ["Rename", false],
		["Info", true], ["Discard", false]]},
	{"title": "Disk", "x": 168.0, "w": 70.0, "items": [
		["Empty Trash", true], ["Initialize", false]]},
	{"title": "Special", "x": 258.0, "w": 110.0, "items": [
		["Clean Up", true], ["Last Error", true], ["Redraw", true],
		["Snapshot", false], ["Version", true]]},
]
const MODERN_MENUS := [
	{"title": "Workbench", "x": 8.0, "w": 98.0, "items": [
		["Backdrop", true], ["Execute Command...", true], ["Redraw All", true],
		["Update All", true], ["Last Message", true], ["About...", true],
		["Quit...", false]]},
	{"title": "Window", "x": 116.0, "w": 78.0, "items": [
		["New Drawer", false], ["Open Parent", true], ["Close", true],
		["Update", true], ["Select Contents", false], ["Clean Up", true],
		["Snapshot", false], ["Show", false], ["View By", false]]},
	{"title": "Icons", "x": 204.0, "w": 68.0, "items": [
		["Open", true], ["Copy", false], ["Rename", false], ["Information", true],
		["Snapshot", false], ["Leave Out", false], ["Put Away", false],
		["Delete", false], ["Format Disk...", true], ["Empty Trash", true]]},
	{"title": "Tools", "x": 282.0, "w": 68.0, "items": [
		["ResetWB", true]]},
]

var _phase := "desktop"          # "boot" | "desktop"
var _boot_t := 0.0
var _boot_lines := 0
var _boot_source := "floppy"
var _boot_duration := FLOPPY_BOOT_SECONDS
var _boot_line_interval := FLOPPY_LINE_SECONDS
var _wins: Control
var _overlay: Control
var _open: Dictionary = {}       # key → Wb13Window
var _builders: Dictionary = {}   # key → Callable (Icon-Listen neu bauen)
var _desk_icons: Array = []
var _sel_win: Node = null
var _sel_id := ""
var _bar_override := ""
var _bar_override_t := 0.0
var _menu := -1                  # offenes Menü (-1 = keins)
var _menu_item := -1
var _tick := 0.0
var _profile_id := "wb13"
var _profile: Dictionary = {}
var _workspace: Dictionary = {}
var _virtual_size := Vector2(VW, VH)


func _ready() -> void:
	if UIManager.workbench_profile_id.is_empty():
		UIManager.workbench_profile_id = Versions.native_id()
	_profile_id = UIManager.workbench_profile_id
	_profile = Versions.profile(_profile_id)
	_configure_workspace()
	_boot_source = UIManager.boot_source if UIManager.boot_source in ["floppy", "hdd"] \
		else "floppy"
	_configure_boot_timing()
	Wb13.set_session_colors([])
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	_sync_size.call_deferred()
	var parent := get_parent_control()
	if parent != null:
		parent.resized.connect(_sync_size)
	_wins = Control.new()
	_wins.name = "Fenster"
	_wins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wins)
	_overlay = Control.new()
	_overlay.name = "MenuOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_desk_icons()
	PlayerStats.stats_changed.connect(_on_hardware_changed)
	SettingsManager.settings_changed.connect(_on_display_settings_changed)
	var localization := get_node_or_null("/root/Localization")
	if localization != null and localization.has_signal("locale_changed"):
		localization.locale_changed.connect(_on_locale_changed)
	if bool(SettingsManager.value("crt_auto_monitor")):
		UIManager.set_crt(true)
	set_process(true)
	if not UIManager.wb_booted:
		_phase = "boot"
		if boot_uses_floppy_audio():
			AudioManager.floppy_read()
	else:
		_open_root()


func _menus() -> Array:
	var menus: Array = (MODERN_MENUS if Wb13.is_modern() else CLASSIC_MENUS).duplicate(true)
	if not menus.is_empty():
		menus[0]["title"] = Versions.localized_brand()
	var menu_names := {
		"Disk": ["ui.sommerbench.menu.disk", "Disk"],
		"Special": ["ui.sommerbench.menu.special", "Spezial"],
		"Window": ["ui.sommerbench.menu.window", "Fenster"],
		"Icons": ["ui.sommerbench.menu.icons", "Symbole"],
		"Tools": ["ui.sommerbench.menu.tools", "Werkzeuge"],
	}
	for menu: Dictionary in menus:
		var raw := str(menu.get("title", ""))
		if menu_names.has(raw):
			var spec: Array = menu_names[raw]
			menu["title"] = Loc.t(str(spec[0]), str(spec[1]))
	return menus


func _boot_text() -> Array:
	return [
		Versions.localized_name(_profile_id),
		Loc.t("ui.sommerbench.boot.copyright", "Sommer Computer Systems · Alle Rechte vorbehalten."),
		Loc.t("ui.sommerbench.boot.release", "Systemversion %s") % str(_profile.get("workbench_revision", "34.20")),
		Loc.t("ui.sommerbench.boot.kickstart", "Kickstart %s · ROM %s") % [
			str(_profile.get("kickstart_version", "1.3")),
			str(_profile.get("kickstart_revision", "34.5")),
		],
		"1> loadsb",
	]


func _configure_boot_timing() -> void:
	if _boot_source != "hdd":
		_boot_duration = FLOPPY_BOOT_SECONDS
		_boot_line_interval = FLOPPY_LINE_SECONDS
		return
	# Controller-, Fast-RAM- und Turbokartenvorteile laufen über den zentralen
	# I/O-Wert. Beide Grenzen verhindern einen kaum sichtbaren Blitzstart sowie
	# absurd lange Starts bei beschädigten/alten Daten.
	var io_factor := clampf(PlayerStats.io_speed_multiplier(),
		HDD_IO_FACTOR_MIN, HDD_IO_FACTOR_MAX)
	_boot_duration = clampf(FLOPPY_BOOT_SECONDS / sqrt(io_factor),
		HDD_BOOT_SECONDS_MIN, HDD_BOOT_SECONDS_MAX)
	_boot_line_interval = _boot_duration / float(maxi(1, _boot_text().size() + 1))


func boot_source_id() -> String:
	return _boot_source


func boot_duration_seconds() -> float:
	return _boot_duration


func boot_uses_floppy_audio() -> bool:
	return _boot_source == "floppy"


func _desktop_label() -> String:
	return Versions.localized_desktop_label(_profile_id)


func _release_name() -> String:
	return Versions.localized_name(_profile_id)


func _on_locale_changed(_locale: String) -> void:
	_build_desk_icons()
	for key: Variant in _builders:
		if _open.has(key) and is_instance_valid(_open[key]):
			(_open[key] as Wb13Window).set_icons((_builders[key] as Callable).call())
	queue_redraw()
	_overlay.queue_redraw()


func _sync_size() -> void:
	var parent := get_parent_control()
	if parent != null:
		position = Vector2.ZERO
		size = parent.size
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_wins.position = Vector2.ZERO
	_wins.size = size
	for w in _wins.get_children():
		if w is Wb13Window:
			w.sync_layout()
	queue_redraw()


func virtual_size() -> Vector2:
	return _virtual_size


func display_contract() -> Dictionary:
	return _workspace.duplicate(true)


func _configure_workspace() -> void:
	var requested := str(SettingsManager.value(
		Versions.screenmode_settings_key(_profile_id)))
	if requested not in ["auto", "pal", "best"]:
		requested = "auto"
	_workspace = MonitorProfile.workbench_workspace(
		_profile_id,
		str(PlayerStats.desk_model("monitor_model")),
		str(PlayerStats.desk_model("computer_model")),
		requested)
	var canvas: Array = _workspace.get("desktop_canvas", [int(VW), int(VH)])
	if canvas.size() < 2:
		canvas = [int(VW), int(VH)]
	_virtual_size = Vector2(maxf(VW, float(canvas[0])), maxf(VH, float(canvas[1])))


func _display_status() -> String:
	var resolution: Array = _workspace.get("resolution", [640, 256])
	var width := int(resolution[0]) if resolution.size() >= 2 else 640
	var height := int(resolution[1]) if resolution.size() >= 2 else 256
	var mode := str(_workspace.get("actual_mode", "pal")).to_upper()
	if mode == "BEST":
		mode = "HIRES"
	return "%s · %s %dx%d · %d/%dF" % [
		str(_workspace.get("chipset", "OCS")),
		mode,
		width,
		height,
		int(_workspace.get("colors", 4)),
		int(_workspace.get("color_cap", 4)),
	]


func _sx() -> float: return size.x / maxf(1.0, _virtual_size.x)
func _sy() -> float: return size.y / maxf(1.0, _virtual_size.y)


func _process(delta: float) -> void:
	_tick += delta
	if _phase == "boot":
		_boot_t += delta
		var lines := int(_boot_t / _boot_line_interval)
		if lines != _boot_lines:
			_boot_lines = lines
			if _boot_lines == 3 and boot_uses_floppy_audio():
				AudioManager.floppy_read()
			queue_redraw()
		if _boot_t > _boot_duration:
			_finish_boot()
		if int(_boot_t * 2.0) != int((_boot_t - delta) * 2.0):
			queue_redraw()  # Cursor-Blinken
		return
	if _bar_override != "" and _tick > _bar_override_t:
		_bar_override = ""
		queue_redraw()
	if int(_tick) != int(_tick - delta):
		queue_redraw()  # Speicheranzeige/Uhr im Sekundentakt


func _finish_boot() -> void:
	_phase = "desktop"
	UIManager.wb_booted = true
	_open_root()
	queue_redraw()


# ------------------------------------------------------------ Icon-Kataloge

func _build_desk_icons() -> void:
	_desk_icons = IconCatalog.desktop(self, _virtual_size, _desktop_label())


# ----------------------------------------------------------------- Fenster

func _win(key: String, wtitle: String, rect: Rect2, builder: Callable, gauge := -1.0) -> Wb13Window:
	if _open.has(key) and is_instance_valid(_open[key]):
		var ex: Wb13Window = _open[key]
		_wins.move_child(ex, -1)
		activate(ex)
		return ex
	var w := Wb13Window.new()
	w.title = wtitle
	w.vrect = rect
	w.gauge_fill = gauge
	if builder.is_valid():
		w.set_icons(builder.call())
		_builders[key] = builder
	_wins.add_child(w)
	_open[key] = w
	w.tree_exited.connect(func() -> void: _open.erase(key))
	w.sync_layout()
	activate(w)
	return w


func _open_root() -> void:
	_win("root", _desktop_label(), Rect2(14, 34, 450, 250),
		IconCatalog.root.bind(self, _profile_id), 0.85)


func _open_programs() -> void:
	_win("programs", Loc.t("ui.werkbank_screen.programs_title", "Programme"),
		Rect2(34, 54, 520, 280), IconCatalog.programs, 0.72)


func _open_utilities() -> void:
	_win("utilities", "Utilities", Rect2(50, 70, 480, 260),
		IconCatalog.utilities.bind(self, _profile_id), 0.85)


func _open_system() -> void:
	_win("system", "System", Rect2(80, 90, 470, 250),
		IconCatalog.system.bind(self, _profile_id), 0.85)


func _open_prefs() -> void:
	_win("prefs", "Prefs", Rect2(94, 92, 486, 240),
		IconCatalog.prefs.bind(self), 0.85)


func _open_tools() -> void:
	_win("tools", "Tools", Rect2(118, 78, 420, 230),
		IconCatalog.tools.bind(self, _profile_id), 0.55)


func _open_commodities() -> void:
	if _profile_id == "wb31":
		_open_os31_tool("exchange")
	else:
		UIManager.toast(Loc.t("ui.werkbank_screen.commodities_werkzeugschublade_geoffnet", "Commodities: Werkzeugschublade geöffnet."))


func _open_keyshow() -> void:
	if _profile_id == "wb31":
		_open_os31_tool("keyshow")
	else:
		UIManager.toast(Loc.t("ui.werkbank_screen.keyshow_deutsche_tastaturbelegung", "KeyShow: Deutsche Tastaturbelegung."))


func _open_storage() -> void:
	_win("storage", "Storage", Rect2(134, 98, 390, 210),
		IconCatalog.storage.bind(self), 0.45)


func _open_storage_dosdrivers() -> void:
	if _profile_id == "wb31":
		_open_dosdrivers()
	else:
		UIManager.toast(Loc.t("ui.werkbank_screen.dosdrivers_optionale_gerate_sind_bereit", "DOSDrivers: optionale Geräte sind bereit."))


func _open_wbstartup() -> void:
	_win("wbstartup", "WBStartup", Rect2(164, 128, 360, 170),
		func() -> Array: return IconCatalog.wbstartup(self, _profile_id), 0.18)


func _open_dosdrivers() -> void:
	_win("dosdrivers", "DOSDrivers", Rect2(190, 116, 330, 170),
		func() -> Array: return IconCatalog.dosdrivers(self), 0.25)


func _open_empty() -> void:
	_win("empty", "Empty", Rect2(150, 150, 300, 140), Callable())


func _open_expansion() -> void:
	_win("expansion", "Expansion", Rect2(170, 130, 300, 140), Callable())


func _open_trash() -> void:
	_win("trash", "Trashcan", Rect2(170, 160, 300, 140), Callable())


func _open_ram() -> void:
	_win("ram", "RAM DISK", Rect2(140, 60, 320, 160),
		func() -> Array: return [{"id": "t", "label": "T", "kind": "drawer",
			"cb": func() -> void: UIManager.toast(Loc.t("ui.werkbank_screen.t_nur_temporarer_kram", "T: nur temporärer Kram."))}], 0.0)


func _open_disk_directory() -> void:
	_open_custom("disk_directory", WbDiskDirectoryWindowScript, Rect2(42, 42, 550, 314))


func _hdd_title() -> String:
	var info: Dictionary = PlayerStats.hdd_info()
	if not bool(info.get("partitioned", false)):
		return Loc.t("ui.werkbank_screen.hdd_raw_title",
			"DH0:NDOS · ROH · Einrichtung nötig")
	if not bool(info.get("formatted", false)):
		return Loc.t("ui.werkbank_screen.hdd_format_title",
			"DH0:NDOS · Formatierung nötig")
	return Loc.t("ui.werkbank_screen.hdd_ready_title",
		"DH0: · %s · %s frei") % [
		_format_disk_kb(int(info.get("capacity_kb", 0))),
		_format_disk_kb(int(info.get("free_kb", 0))),
	]


func _format_disk_kb(kb: int) -> String:
	if kb >= 1024 * 1024:
		return "%.1f GB" % (float(kb) / float(1024 * 1024))
	if kb >= 1024:
		return "%.1f MB" % (float(kb) / 1024.0)
	return "%d KB" % kb


func _open_hdd() -> void:
	var info: Dictionary = PlayerStats.hdd_info()
	if not bool(info.get("available", false)):
		UIManager.toast(Loc.t("ui.werkbank_screen.hdd_missing", "DH0: nicht vorhanden."))
		return
	if not PlayerStats.hdd_is_usable():
		UIManager.open_hdd_setup()
		return
	var capacity := maxi(1, int(info.get("capacity_kb", 1)))
	_win("hdd", _hdd_title(), Rect2(76, 52, 478, 292), IconCatalog.hdd.bind(self),
		clampf(float(info.get("used_kb", 0)) / float(capacity), 0.0, 1.0))


func _show_hdd_info() -> void:
	var body := InfoText.hdd_info(_profile_id, _format_disk_kb)
	_open_text("hdd_info",
		Loc.t("ui.werkbank_screen.hdd_info_title", "DH0: Disk-Information"),
		body, Rect2(112, 58, 438, 292),
		Loc.t("ui.werkbank_screen.hdd_status", "DH0: GERÄTESTATUS"))


func _open_custom(key: String, script: GDScript, rect: Rect2) -> Wb13Window:
	if _open.has(key) and is_instance_valid(_open[key]):
		activate(_open[key])
		return _open[key]
	var c: Wb13Window = script.new()
	c.vrect = rect
	_wins.add_child(c)
	_open[key] = c
	c.tree_exited.connect(func() -> void: _open.erase(key))
	c.sync_layout()
	activate(c)
	return c


func _open_text(key: String, window_title: String, body: String, rect: Rect2,
		heading := "") -> Wb13Window:
	var window: Wb13Window = _open_custom(key, WbTextWindowScript, rect)
	window.call("configure", window_title, body, heading)
	return window


func _open_clock() -> void:
	_open_custom("clock", WbClockWindow, Rect2(380, 46, 220, 190))


func _open_clockptr() -> void:
	var w := _open_custom("clockptr", WbClockWindow, Rect2(440, 250, 150, 70))
	w.set("digital", true)
	w.title = "ClockPtr"
	w.queue_redraw()


func _open_calc() -> void:
	_open_custom("calc", WbCalcWindow, Rect2(410, 120, 180, 240))


func _open_shell() -> void:
	_open_custom("shell", WbShellWindow, Rect2(40, 60, 460, 250))


func _open_os31_tool(tool_id: String) -> void:
	if _profile_id != "wb31":
		UIManager.toast(Loc.t("ui.werkbank_screen.dieses_werkzeug_gehort_zur_workbench_3", "Dieses Werkzeug gehört zur Sommerbench 3.1."))
		return
	var host := GameManager.location_host
	if host == null:
		return
	var node_name := "WB31_" + tool_id
	var existing := host.get_node_or_null(node_name)
	if existing != null:
		existing.queue_free()
		return
	var app: Workbench31ToolApp = Workbench31ToolAppScript.new()
	app.name = node_name
	app.tool_id = tool_id
	host.add_child(app)
	UIManager._set_computer_ui(true)


func _show_more() -> void:
	var body := Loc.t("ui.sommerbench.about.system", "%s · Systemrevision %s · Kickstart %s (%s)") % [
		_release_name(), str(_profile.get("workbench_revision", "34.20")),
		str(_profile.get("kickstart_version", "1.3")),
		str(_profile.get("kickstart_revision", "34.5"))]
	body += "\n\n" + Loc.t("ui.sommerbench.about.help", "Doppelklick öffnet Disketten, Schubladen und Programme. Menüs erscheinen bei gehaltener rechter Maustaste. Esc = aufstehen. Guru Meditation? Linke Maustaste startet neu.")
	_open_text("about", Loc.t("ui.sommerbench.about.title", "Über %s") % _release_name(), body,
		Rect2(126, 82, 410, 242), Loc.t("ui.sommerbench.about.heading", "SOMMERBENCH-INFORMATION"))


func _say_gag() -> void:
	UIManager.toast(Loc.t("ui.werkbank_screen.say_s_blecherne_roboterstimme", "Say: »%s« (blecherne Roboterstimme)") % PlayerIdentity.player_name)


func _on_hardware_changed() -> void:
	_configure_workspace()
	_build_desk_icons()
	for key in _builders:
		if _open.has(key) and is_instance_valid(_open[key]):
			(_open[key] as Wb13Window).set_icons((_builders[key] as Callable).call())
	if _open.has("hdd") and is_instance_valid(_open["hdd"]):
		var info: Dictionary = PlayerStats.hdd_info()
		var hdd_window: Wb13Window = _open["hdd"]
		hdd_window.title = _hdd_title()
		hdd_window.gauge_fill = clampf(float(info.get("used_kb", 0)) /
			float(maxi(1, int(info.get("capacity_kb", 1)))), 0.0, 1.0)
	queue_redraw()


func _on_display_settings_changed() -> void:
	_configure_workspace()
	_build_desk_icons()
	for child in _wins.get_children():
		if child is Wb13Window:
			(child as Wb13Window).sync_layout()
	queue_redraw()


# ------------------------------------------------- Auswahl / Aktivierung

func select(win: Node, id: String) -> void:
	_sel_win = win
	_sel_id = id
	queue_redraw()
	for w in _wins.get_children():
		w.queue_redraw()


func is_selected(win: Node, id: String) -> bool:
	return _sel_win == win and _sel_id == id


func activate(win: Wb13Window) -> void:
	_wins.move_child(win, -1)
	refresh_active()


func refresh_active() -> void:
	var top: Wb13Window = null
	for w in _wins.get_children():
		if w is Wb13Window:
			top = w
	for w in _wins.get_children():
		if w is Wb13Window:
			w.active = (w == top)
			w.queue_redraw()


func _active_win() -> Wb13Window:
	for i in range(_wins.get_child_count() - 1, -1, -1):
		var w := _wins.get_child(i)
		if w is Wb13Window:
			return w
	return null


# ----------------------------------------------------------------- Eingabe

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		UIManager.stand_up_from_computer()
		return
	if _phase == "boot":
		if (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
			get_viewport().set_input_as_handled()
			_finish_boot()
		return
	# Menüleiste: nur solange die rechte Maustaste gehalten wird (wie damals) —
	# und nur, wenn kein Vollbild-Programm über dem Desktop liegt.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if not _menu_allowed():
				return
			_menu = 0
			_menu_item = -1
			_update_menu_hover(make_input_local(event).position)
		else:
			var exec_menu := _menu
			var exec_item := _menu_item
			_menu = -1
			_menu_item = -1
			_overlay.queue_redraw()
			queue_redraw()
			if exec_menu >= 0 and exec_item >= 0:
				_menu_action(exec_menu, exec_item)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _menu >= 0:
		_update_menu_hover(make_input_local(event).position)
		get_viewport().set_input_as_handled()


func _menu_allowed() -> bool:
	var host := get_parent_control()
	if host == null:
		return true
	for c in host.get_children():
		if c is WbApp or c is GuruScreen or String(c.name) == "XCopy":
			return false
	return true


func _gui_input(event: InputEvent) -> void:
	if _phase != "desktop":
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		var v := Vector2(event.position.x / _sx(), event.position.y / _sy())
		for ic in _desk_icons:
			if _desk_icon_rect(ic).has_point(v):
				select(self, str(ic["id"]))
				if event.double_click:
					(ic["cb"] as Callable).call()
				return
		select(null, "")


func _desk_icon_rect(ic: Dictionary) -> Rect2:
	var isz: Vector2i = Wb13Icons.icon_size(ic["kind"])
	var p: Vector2 = ic["pos"]
	return Rect2(p.x - 8.0, p.y, isz.x + 16.0, isz.y * 2.0 + 22.0)


## Menü-Hover aus der EVENT-Position (nicht der OS-Maus) — zuverlässig auch
## bei synthetischen Events (Tests) und schnellen Bewegungen.
func _update_menu_hover(m: Vector2) -> void:
	var v := Vector2(m.x / _sx(), m.y / _sy())
	var menus := _menus()
	if v.y < TB:
		for i in menus.size():
			var md: Dictionary = menus[i]
			if v.x >= md["x"] - 6.0 and v.x <= md["x"] + md["w"]:
				_menu = i
		_menu_item = -1
	elif _menu >= 0:
		var md: Dictionary = menus[_menu]
		var items: Array = md["items"]
		_menu_item = -1
		var ir := Rect2(md["x"] - 6.0, TB, 150.0, items.size() * 20.0)
		if ir.has_point(v):
			var idx := int((v.y - TB) / 20.0)
			if idx >= 0 and idx < items.size() and bool(items[idx][1]):
				_menu_item = idx
	_overlay.queue_redraw()
	queue_redraw()


func _menu_action(mi: int, ii: int) -> void:
	var label: String = _menus()[mi]["items"][ii][0]
	match label:
		"Open":
			if _sel_win == self:
				for ic in _desk_icons:
					if str(ic["id"]) == _sel_id:
						(ic["cb"] as Callable).call()
			elif _sel_win is Wb13Window and is_instance_valid(_sel_win):
				var ic: Dictionary = (_sel_win as Wb13Window).icon_by_id(_sel_id)
				if not ic.is_empty():
					(_sel_win as Wb13Window).launch_icon(ic)
		"Close":
			var aw := _active_win()
			if aw != null:
				aw.close_window()
		"Info", "Information":
			UIManager.toast(Loc.t("ui.werkbank_screen.info_s_ausgewahlt", "Info: %s ausgewählt.") % (_sel_id if _sel_id != "" else "nichts"))
		"Empty Trash":
			UIManager.toast(Loc.t("ui.werkbank_screen.trashcan_ist_schon_leer", "Trashcan ist schon leer."))
		"Clean Up", "Update", "Update All":
			var aw2 := _active_win()
			if aw2 != null:
				aw2.scroll_y = 0.0
				aw2.sync_layout()
		"Last Error", "Last Message":
			_set_bar(UIManager.info_log[0] if not UIManager.info_log.is_empty()
				else Loc.t("ui.sommerbench.no_errors", "Keine Fehler."))
		"Redraw", "Redraw All":
			queue_redraw()
			for w in _wins.get_children():
				w.queue_redraw()
		"Version", "About...":
			var kick_cfg := KickstartScreen.config()
			_set_bar("Kickstart %s · %s %s" % [
				str(kick_cfg.get("rom_revision", _profile.get("kickstart_revision", "34.5"))),
				Versions.localized_brand(),
				str(_profile.get("workbench_revision", "34.20"))])
		"Execute Command...":
			_open_shell()
		"Open Parent":
			_open_root()
		"Format Disk...":
			UIManager.open_program("disk_formatter")
		"Backdrop":
			_set_bar(Loc.t("ui.sommerbench.backdrop", "Hintergrundmodus: Die Sommerbench bleibt vorn."))
		"ResetWB":
			for w in _wins.get_children():
				w.free()
			_open.clear()
			_open_root.call_deferred()


func _set_bar(text: String) -> void:
	_bar_override = text
	_bar_override_t = _tick + 5.0
	queue_redraw()


# ----------------------------------------------------------------- Zeichnen

func _free_memory() -> int:
	var total_kb := int(PlayerStats.ram_breakdown()["total_kb"])
	var used := int(total_kb * 1024 * 0.38) + _wins.get_child_count() * 21568
	used += PlayerStats.programs.size() * 4096
	return maxi(51200, total_kb * 1024 - used)


func _draw() -> void:
	var sx := _sx()
	var sy := _sy()
	var vx := sx
	var vy := sy * 2.0
	var fs := Wb13.fsize(sy)
	var font := Wb13.font()
	draw_rect(Rect2(Vector2.ZERO, size), Wb13.blue())
	if _phase == "boot":
		_draw_boot(sx, sy, fs, font)
		return
	# Desktop-Icons (Disketten rechts)
	for ic in _desk_icons:
		var isz: Vector2i = Wb13Icons.icon_size(ic["kind"])
		var p: Vector2 = ic["pos"]
		var selected := is_selected(self, str(ic["id"]))
		draw_texture_rect(Wb13Icons.tex(ic["kind"], selected),
			Rect2(p.x * sx, p.y * sy, isz.x * sx, isz.y * 2.0 * sy), false)
		draw_string(font, Vector2((p.x + isz.x * 0.5 - 60.0) * sx, (p.y + isz.y * 2.0 + 16.0) * sy),
			str(ic["label"]), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * sx, fs, Wb13.white())
	# Titelzeile des Screens
	draw_rect(Rect2(0, 0, size.x, TB * sy), Wb13.white())
	draw_rect(Rect2(0, TB * sy - maxf(1.0, vy * 0.5), size.x, maxf(1.0, vy * 0.5)), Wb13.black())
	if _menu >= 0:
		_draw_menu_bar(sx, sy, fs, font)
	else:
		var bar := _bar_override
		if bar == "":
			bar = "%s" % _release_name()
			draw_string(font, Vector2(140.0 * sx, 16.0 * sy), _display_status(),
				HORIZONTAL_ALIGNMENT_LEFT, 300.0 * sx, fs, Wb13.black())
			draw_string(font, Vector2((_virtual_size.x - 188.0) * sx, 16.0 * sy),
				Loc.t("ui.sommerbench.free_memory", "%d Byte frei") % _free_memory(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.black())
		draw_string(font, Vector2(8.0 * sx, 16.0 * sy), bar, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.black())
	Wb13.gadget_depth(self, Rect2(size.x - 52.0 * sx, 0, 26.0 * sx, TB * sy), vx, vy, false)
	Wb13.gadget_depth(self, Rect2(size.x - 26.0 * sx, 0, 26.0 * sx, TB * sy), vx, vy, true)


func _draw_menu_bar(sx: float, sy: float, fs: int, font: Font) -> void:
	var menus := _menus()
	for i in menus.size():
		var md: Dictionary = menus[i]
		if i == _menu:
			draw_rect(Rect2((md["x"] - 6.0) * sx, 0, (md["w"] + 6.0) * sx, TB * sy), Wb13.black())
		draw_string(font, Vector2(md["x"] * sx, 16.0 * sy), md["title"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white() if i == _menu else Wb13.black())


func _draw_overlay() -> void:
	if _menu < 0:
		return
	var sx := _sx()
	var sy := _sy()
	var fs := Wb13.fsize(sy)
	var font := Wb13.font()
	var md: Dictionary = _menus()[_menu]
	var items: Array = md["items"]
	var r := Rect2((md["x"] - 6.0) * sx, TB * sy, 150.0 * sx, items.size() * 20.0 * sy)
	_overlay.draw_rect(r, Wb13.white())
	_overlay.draw_rect(r, Wb13.black(), false, maxf(1.0, sy))
	for i in items.size():
		var y := TB + i * 20.0
		var enabled: bool = items[i][1]
		if i == _menu_item:
			_overlay.draw_rect(Rect2(r.position.x, y * sy, r.size.x, 20.0 * sy), Wb13.black())
		_overlay.draw_string(font, Vector2((md["x"]) * sx, (y + 15.0) * sy), items[i][0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white() if i == _menu_item else Wb13.black())
		if not enabled:
			Wb13.ghost(_overlay, Rect2(r.position.x, y * sy + sy, r.size.x, 20.0 * sy - sy),
				sx, sy * 2.0, Wb13.white())


func _draw_boot(sx: float, sy: float, fs: int, font: Font) -> void:
	# Screen-Titel + DOS-Fenster mit Copyright-Zeilen (Boot nach dem Einschalten)
	draw_rect(Rect2(0, 0, size.x, TB * sy), Wb13.white())
	draw_string(font, Vector2(8.0 * sx, 16.0 * sy), Loc.t(
		"ui.sommerbench.boot.screen", "Sommerbench-Bildschirm · %s") % _release_name(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.black())
	var wr := Rect2(6.0 * sx, 26.0 * sy,
		(_virtual_size.x - 20.0) * sx, (_virtual_size.y - 40.0) * sy)
	draw_rect(wr, Wb13.blue())
	draw_rect(wr, Wb13.white(), false, maxf(2.0, sy * 2.0))
	draw_rect(Rect2(wr.position, Vector2(wr.size.x, 20.0 * sy)), Wb13.white())
	draw_string(font, Vector2(14.0 * sx, 42.0 * sy), "AmigaDOS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.black())
	Wb13.drag_stripes(self, Rect2(wr.position.x + 90.0 * sx, wr.position.y,
		wr.size.x - 150.0 * sx, 20.0 * sy), sy * 2.0)
	Wb13.gadget_depth(self, Rect2(wr.end.x - 52.0 * sx, wr.position.y, 26.0 * sx, 20.0 * sy), sx, sy * 2.0, false)
	Wb13.gadget_depth(self, Rect2(wr.end.x - 26.0 * sx, wr.position.y, 26.0 * sx, 20.0 * sy), sx, sy * 2.0, true)
	var boot_lines := _boot_text()
	var shown := mini(_boot_lines, boot_lines.size())
	for i in shown:
		draw_string(font, Vector2(14.0 * sx, (72.0 + i * 20.0) * sy), boot_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
	if int(_boot_t * 2.0) % 2 == 0:  # blinkender Cursor-Block
		draw_rect(Rect2(14.0 * sx, (58.0 + shown * 20.0) * sy, 8.0 * sx, 16.0 * sy), Wb13.orange())
