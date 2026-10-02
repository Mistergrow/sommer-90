class_name BootSelectScreen
extends Control
## Kickstart-/DF0-Medienwahl. Sie zeigt ausschliesslich Medien, die der Amiga
## wirklich booten kann. Das physische Vollarchiv (inklusive Rohlingen, MODs und
## Datendisks) bleibt in Diskettenbox und Werkbank-Werkzeugen erreichbar.

const VW := 640.0
const VH := 400.0
const CELL := Vector2(96, 92)
const COLS := 6
const PAGE_ROWS := 3
const PAGE_SIZE := COLS * PAGE_ROWS
const GRID_ORIGIN := Vector2(32, 78)
const PREV_RECT := Rect2(548, 2, 24, 16)
const NEXT_RECT := Rect2(608, 2, 24, 16)
const EXIT_RECT := Rect2(520, 24, 108, 17)
const DiskAccessPolicy := preload("res://scripts/ui/disk_access_policy.gd")
const DiskCatalog := preload("res://scripts/ui/disk_catalog_rules.gd")
const WorkbenchVersionCatalog := preload("res://scripts/ui/workbench_versions.gd")
const FILTER_LABEL_KEYS := [
	"ui.boot_select_screen.filter_all",
	"ui.boot_select_screen.filter_games",
	"ui.boot_select_screen.filter_scene",
	"ui.boot_select_screen.filter_tools",
	"ui.boot_select_screen.filter_pd_mag",
	"ui.boot_select_screen.filter_system",
]
const FILTER_FALLBACKS := ["ALLE", "SPIELE", "SZENE", "TOOLS", "PD/HEFT", "SYSTEM"]
const FILTER_KEYS := ["alle", "spiele", "szene", "tools", "pd_hefte", "system"]
const FILTER_W := 68.0
const FILTER_GAP := 4.0
const FILTER_Y := 47.0
const FILTER_H := 17.0

var _rows: Array = []       # {disk, kind, rect}; rect nur auf aktiver Seite
var _hover := -1
var _selected := -1
var _page := 0
var _filter := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	focus_mode = Control.FOCUS_ALL
	_sync_size.call_deferred()
	var parent := get_parent_control()
	if parent != null:
		parent.resized.connect(_sync_size)
	if not DiskManager.disks_changed.is_connected(_build):
		DiskManager.disks_changed.connect(_build)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_build()
	set_process(false)
	grab_focus.call_deferred()


func _exit_tree() -> void:
	if DiskManager.disks_changed.is_connected(_build):
		DiskManager.disks_changed.disconnect(_build)
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func _on_locale_changed(_locale: String) -> void:
	queue_redraw()


func _sync_size() -> void:
	var parent := get_parent_control()
	if parent != null:
		position = Vector2.ZERO
		size = parent.size
	_layout()
	queue_redraw()


func _sx() -> float: return size.x / VW
func _sy() -> float: return size.y / VH


func _build() -> void:
	var keep_uid := ""
	if _selected >= 0 and _selected < _rows.size():
		keep_uid = str(_rows[_selected]["disk"].uid)
	_rows = []
	for disk: Disk in DiskSortOrder.sorted(DiskManager.media_disks(), DiskManager.sort_mode):
		if DiskCatalog.is_boot_selector_visible(disk) and _matches_filter(disk):
			_rows.append({"disk": disk, "kind": _kind_for(disk), "rect": Rect2(-1000, -1000, 1, 1)})
	var pages := _page_count()
	_page = clampi(_page, 0, pages - 1)
	_selected = -1
	if not keep_uid.is_empty():
		for index in _rows.size():
			if str(_rows[index]["disk"].uid) == keep_uid:
				_selected = index
				_page = floori(float(index) / float(PAGE_SIZE))
				break
	_layout()
	queue_redraw()


func _kind_for(disk: Disk) -> String:
	if disk.content_type == "system":
		return "disk_wb"
	if disk.content_type == "ram":
		return "disk_ram"
	return "disk_plain"


func _matches_filter(disk: Disk) -> bool:
	return DiskCatalog.matches_category(disk,
		str(FILTER_KEYS[clampi(_filter, 0, FILTER_KEYS.size() - 1)]))


func _filter_rect(index: int) -> Rect2:
	var total := FILTER_LABEL_KEYS.size() * FILTER_W + (FILTER_LABEL_KEYS.size() - 1) * FILTER_GAP
	var left := (VW - total) * 0.5
	return Rect2(left + index * (FILTER_W + FILTER_GAP), FILTER_Y, FILTER_W, FILTER_H)


func _set_filter(index: int) -> void:
	var next := clampi(index, 0, FILTER_LABEL_KEYS.size() - 1)
	if next == _filter:
		return
	_filter = next
	_page = 0
	_selected = -1
	_hover = -1
	_build()


func _page_count() -> int:
	return maxi(1, ceili(float(_rows.size()) / float(PAGE_SIZE)))


func _page_start() -> int:
	return _page * PAGE_SIZE


func _page_end() -> int:
	return mini(_page_start() + PAGE_SIZE, _rows.size())


func _layout() -> void:
	for row in _rows:
		row["rect"] = Rect2(-1000, -1000, 1, 1)
	for index in range(_page_start(), _page_end()):
		var local := index - _page_start()
		var col := local % COLS
		var line := floori(float(local) / float(COLS))
		_rows[index]["rect"] = Rect2(GRID_ORIGIN + Vector2(col * CELL.x, line * CELL.y), CELL)


func _set_page(value: int) -> void:
	var next := clampi(value, 0, _page_count() - 1)
	if next == _page:
		return
	_page = next
	_hover = -1
	_selected = _page_start() if _page_start() < _rows.size() else -1
	_layout()
	queue_redraw()


func _move_selection(delta: int) -> void:
	if _rows.is_empty():
		return
	if _selected < 0:
		_selected = _page_start()
	else:
		_selected = clampi(_selected + delta, 0, _rows.size() - 1)
	_page = floori(float(_selected) / float(PAGE_SIZE))
	_layout()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			exit_to_room()
		KEY_PAGEUP:
			get_viewport().set_input_as_handled(); _set_page(_page - 1)
		KEY_PAGEDOWN:
			get_viewport().set_input_as_handled(); _set_page(_page + 1)
		KEY_LEFT:
			get_viewport().set_input_as_handled(); _move_selection(-1)
		KEY_RIGHT:
			get_viewport().set_input_as_handled(); _move_selection(1)
		KEY_UP:
			get_viewport().set_input_as_handled(); _move_selection(-COLS)
		KEY_DOWN:
			get_viewport().set_input_as_handled(); _move_selection(COLS)
		KEY_HOME:
			get_viewport().set_input_as_handled(); _selected = _page_start(); queue_redraw()
		KEY_END:
			get_viewport().set_input_as_handled(); _selected = _page_end() - 1; queue_redraw()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled(); _activate(_selected)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var index := _index_at(Vector2(event.position.x / _sx(), event.position.y / _sy()))
		if index != _hover:
			_hover = index
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_page(_page - 1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_page(_page + 1)
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var v := Vector2(event.position.x / _sx(), event.position.y / _sy())
		for filter_index in FILTER_LABEL_KEYS.size():
			if _filter_rect(filter_index).has_point(v):
				_set_filter(filter_index)
				return
		if EXIT_RECT.has_point(v):
			exit_to_room()
			return
		if PREV_RECT.has_point(v):
			_set_page(_page - 1)
		elif NEXT_RECT.has_point(v):
			_set_page(_page + 1)
		else:
			_selected = _index_at(v)
			_activate(_selected)


## Der Startmedienwaehler ist kein laufendes Amiga-Programm. Er wird beim
## Aufstehen beendet, damit ein spaeterer Klick auf die Roehre nicht wieder in
## denselben Auswahlbildschirm fuehrt.
func exit_to_room() -> void:
	UIManager.stand_up_from_computer()


func _index_at(point: Vector2) -> int:
	for index in range(_page_start(), _page_end()):
		if (_rows[index]["rect"] as Rect2).has_point(point):
			return index
	return -1


func _activate(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	if not DiskAccessPolicy.require_computer(UIManager, Loc.t(
			"ui.boot_select_screen.insert_media", "DF0: Medium einlegen")):
		return
	var disk: Disk = _rows[index]["disk"]
	if not disk.is_bootable():
		UIManager.toast(Loc.t("ui.boot_select_screen.df0_s_ist_nicht_bootfaehig_kickstart", "DF0: »%s« ist nicht bootfaehig — Kickstart wartet weiter.") % disk.display_name())
		queue_redraw()
		return
	UIManager.boot_from_disk(disk)


func _draw() -> void:
	var sx := _sx()
	var sy := _sy()
	var font := Wb13.font()
	var fs := Wb13.fsize(sy)
	draw_rect(Rect2(Vector2.ZERO, size), Color8(0, 51, 119))
	draw_rect(Rect2(0, 0, size.x, 20.0 * sy), Wb13.white())
	var kick_cfg := KickstartScreen.config()
	draw_string(font, Vector2(8.0 * sx, 16.0 * sy), "Kickstart %s" % str(kick_cfg.get("rom_version", "1.3")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.black())
	draw_string(font, Vector2(220.0 * sx, 16.0 * sy), Loc.t(
		"ui.boot_select_screen.start_media_box", "STARTMEDIEN %d · BOX %d") % [
			_rows.size(), DiskManager.media_count()],
		HORIZONTAL_ALIGNMENT_CENTER, 300.0 * sx, maxi(4, int(fs * 0.82)), Wb13.black())
	_draw_page_button(PREV_RECT, "<", _page > 0, font, fs, sx, sy)
	_draw_page_button(NEXT_RECT, ">", _page + 1 < _page_count(), font, fs, sx, sy)
	draw_string(font, Vector2(572.0 * sx, 16.0 * sy), "%d/%d" % [_page + 1, _page_count()],
		HORIZONTAL_ALIGNMENT_CENTER, 36.0 * sx, maxi(4, int(fs * 0.78)), Wb13.black())
	draw_string(font, Vector2(0, 43.0 * sy), Loc.t(
		"ui.boot_select_screen.insert_media_caps", "DF0:  MEDIUM EINLEGEN"),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, int(fs * 1.12), Wb13.white())
	_draw_exit_button(font, fs, sx, sy)
	for filter_index in FILTER_LABEL_KEYS.size():
		_draw_filter_button(filter_index, font, fs, sx, sy)

	if _rows.is_empty():
		draw_string(font, Vector2(0, 196.0 * sy), Loc.t(
			"ui.boot_select_screen.no_media_category", "KEIN STARTMEDIUM IN DIESER KATEGORIE"),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Wb13.white())

	for index in range(_page_start(), _page_end()):
		var r: Rect2 = _rows[index]["rect"]
		var disk: Disk = _rows[index]["disk"]
		var pr := Rect2(r.position * Vector2(sx, sy), r.size * Vector2(sx, sy))
		if index == _hover or index == _selected:
			draw_rect(pr.grow(-2.0 * sx), Color8(0, 84, 164))
			draw_rect(pr.grow(-2.0 * sx), Wb13.orange() if index == _selected else Wb13.white(),
				false, maxf(1.0, sy))
		var kind: String = _rows[index]["kind"]
		var isz: Vector2i = Wb13Icons.icon_size(kind)
		var icon_scale := minf((CELL.x - 36.0) / isz.x, (CELL.y - 42.0) / (isz.y * 2.0)) * sx
		var icon_size := Vector2(isz.x * icon_scale, isz.y * 2.0 * icon_scale)
		var ip := Vector2(pr.position.x + (pr.size.x - icon_size.x) * 0.5, pr.position.y + 4.0 * sy)
		draw_texture_rect(Wb13Icons.tex(kind, index == _hover), Rect2(ip, icon_size), false)
		var media_color := Palette.disk_color(disk.color)
		draw_rect(Rect2(pr.position.x + 25.0 * sx, ip.y + icon_size.y - 3.0 * sy,
			46.0 * sx, 3.0 * sy), media_color)
		draw_string(font, Vector2(pr.position.x, ip.y + icon_size.y + 12.0 * sy),
			_short(_localized_disk_name(disk)), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x,
			maxi(4, int(fs * 0.76)), Wb13.white())
		draw_string(font, Vector2(pr.position.x, ip.y + icon_size.y + 24.0 * sy),
			_localized_category(disk), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x,
			maxi(4, int(fs * 0.66)), Color8(112, 226, 138))

	draw_rect(Rect2(0, 360.0 * sy, size.x, 40.0 * sy), Color8(0, 35, 88))
	var focus := _hover if _hover >= 0 else _selected
	var detail := Loc.t("ui.boot_select_screen.select_boot_medium",
		"Startmedium wählen · Enter/Klick bootet DF0:")
	var sub := Loc.t("ui.boot_select_screen.data_disks_help",
		"Rohlinge und Datendisks: Sommerbench > Diskettenbox bzw. X-COPY.")
	var hdd: Dictionary = PlayerStats.hdd_info()
	if bool(hdd.get("available", false)) and not bool(hdd.get("bootable", false)):
		sub = Loc.t("ui.boot_select_screen.hdd_no_system",
			"DH0: KEIN SYSTEM · INSTALL-/SYSTEMDISK BOOTEN > HDTOOLBOX > INSTALL.")
	if focus >= 0 and focus < _rows.size():
		var disk: Disk = _rows[focus]["disk"]
		detail = _localized_disk_name(disk)
		var boot_status := Loc.t("ui.boot_select_screen.boot_ready", "DF0: BOOT BEREIT") \
			if disk.is_bootable() else Loc.t("ui.boot_select_screen.no_bootblock", "DF0: KEIN BOOTBLOCK")
		var profile_id := WorkbenchVersionCatalog.disk_profile_id(disk)
		if not profile_id.is_empty() and not WorkbenchVersionCatalog.is_compatible(profile_id):
			boot_status = Loc.t("ui.boot_select_screen.incompatible", "NICHT KOMPATIBEL MIT DIESEM AMIGA")
		sub = "%s · %s · %s" % [_localized_category(disk), _localized_condition(disk), boot_status]
	draw_string(font, Vector2(12.0 * sx, 376.0 * sy), detail.left(76),
		HORIZONTAL_ALIGNMENT_LEFT, 616.0 * sx, maxi(4, int(fs * 0.78)), Wb13.white())
	draw_string(font, Vector2(12.0 * sx, 391.0 * sy), sub.left(78),
		HORIZONTAL_ALIGNMENT_LEFT, 492.0 * sx, maxi(4, int(fs * 0.64)), Color8(155, 190, 225))
	draw_string(font, Vector2(508.0 * sx, 391.0 * sy), Loc.t(
		"ui.boot_select_screen.esc_room", "ESC = ZIMMER"),
		HORIZONTAL_ALIGNMENT_RIGHT, 120.0 * sx, maxi(4, int(fs * 0.64)), Color8(255, 196, 82))


func _draw_exit_button(font: Font, fs: int, sx: float, sy: float) -> void:
	var physical := Rect2(EXIT_RECT.position * Vector2(sx, sy),
		EXIT_RECT.size * Vector2(sx, sy))
	draw_rect(physical, Color8(120, 35, 42))
	draw_rect(physical, Wb13.white(), false, maxf(1.0, sy))
	draw_string(font, Vector2(physical.position.x, physical.position.y + 13.0 * sy),
		Loc.t("ui.boot_select_screen.back_room", "ZURÜCK INS ZIMMER"),
		HORIZONTAL_ALIGNMENT_CENTER, physical.size.x,
		maxi(4, int(fs * 0.60)), Wb13.white())


func _draw_filter_button(index: int, font: Font, fs: int, sx: float, sy: float) -> void:
	var rect := _filter_rect(index)
	var physical := Rect2(rect.position * Vector2(sx, sy), rect.size * Vector2(sx, sy))
	var active := index == _filter
	draw_rect(physical, Wb13.orange() if active else Color8(0, 35, 88))
	draw_rect(physical, Wb13.white(), false, maxf(1.0, sy))
	draw_string(font, Vector2(physical.position.x, physical.position.y + 13.0 * sy),
		Loc.t(FILTER_LABEL_KEYS[index], FILTER_FALLBACKS[index]),
		HORIZONTAL_ALIGNMENT_CENTER, physical.size.x, maxi(4, int(fs * 0.68)),
		Wb13.black() if active else Wb13.white())


func _draw_page_button(rect: Rect2, label: String, enabled: bool, font: Font,
		fs: int, sx: float, sy: float) -> void:
	var physical := Rect2(rect.position * Vector2(sx, sy), rect.size * Vector2(sx, sy))
	draw_rect(physical, Color8(0, 51, 119) if enabled else Color8(180, 190, 205))
	draw_string(font, Vector2(physical.position.x, physical.position.y + 13.0 * sy), label,
		HORIZONTAL_ALIGNMENT_CENTER, physical.size.x, maxi(4, int(fs * 0.76)), Wb13.white())


func _short(value: String) -> String:
	return value if value.length() <= 13 else value.substr(0, 12) + "…"


func _localized_disk_name(disk: Disk) -> String:
	var value := disk.display_name()
	if value.begins_with("Workbench "):
		return "%s %s" % [Loc.t("ui.boot_select_screen.system_brand", "Sommerbench"),
			value.trim_prefix("Workbench ")]
	return value


func _localized_category(disk: Disk) -> String:
	match DiskCatalog.category(disk):
		"LEER": return Loc.t("ui.boot_select_screen.category_empty", "LEER")
		"SZENE": return Loc.t("ui.boot_select_screen.category_scene", "SZENE")
		"SPIEL": return Loc.t("ui.boot_select_screen.category_game", "SPIEL")
		"PD/HEFT": return Loc.t("ui.boot_select_screen.category_pd_mag", "PD/HEFT")
		"SYSTEM": return Loc.t("ui.boot_select_screen.category_system", "SYSTEM")
		"OVP": return Loc.t("ui.boot_select_screen.category_boxed", "OVP")
		_: return DiskCatalog.category(disk)


func _localized_condition(disk: Disk) -> String:
	if not disk.checked:
		return Loc.t("ui.boot_select_screen.condition_unknown", "ZUSTAND: ??")
	if disk.condition <= 0:
		return Loc.t("ui.boot_select_screen.condition_defective", "DEFEKT")
	return Loc.t("ui.boot_select_screen.condition_percent", "ZUSTAND: %d%%") % disk.condition
