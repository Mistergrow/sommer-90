class_name WbDiskDirectoryWindow
extends Wb13Window
## Kompaktes Diskettenverzeichnis direkt im Stil der Werkbank 1.3. Das Fenster
## ist bewusst kein zweites modernes Inventar: Es zeigt nur Datentraeger mit
## Inhalt, dazu Satznummer, Sammlungs-Farbcode und Schreibschutz, und fuehrt von
## dort in die echten Systemwerkzeuge. Rohlinge bleiben in Box/X-COPY/FORMAT.

const ROWS := 8
const FILTERS := ["ALLE", "SPIELE", "SZENE", "TOOLS", "PD+HEFTE", "MUSIK", "SYSTEM"]
const FILTER_KEYS := ["alle", "spiele", "szene", "tools", "pd_hefte", "musik", "system"]
const FILTER_WIDTHS := [48.0, 61.0, 58.0, 55.0, 78.0, 57.0, 63.0]
const DiskCatalog := preload("res://scripts/ui/disk_catalog_rules.gd")

var _filter := 0
var _page := 0
var _selected_uid := ""
var _visible_disks: Array = []


func _init() -> void:
	title = Loc.t("ui.wb_disk_directory_window.diskettenbox_verzeichnis", "Diskettenbox: Verzeichnis")
	gauge_fill = 0.0
	resizable = false


func _ready() -> void:
	super._ready()
	if not DiskManager.disks_changed.is_connected(_refresh):
		DiskManager.disks_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if DiskManager.disks_changed.is_connected(_refresh):
		DiskManager.disks_changed.disconnect(_refresh)


func _refresh() -> void:
	_visible_disks = []
	for disk: Disk in DiskSortOrder.sorted(DiskManager.media_disks(), DiskManager.sort_mode):
		if DiskCatalog.is_workbench_visible(disk) and _matches_filter(disk):
			_visible_disks.append(disk)
	var pages := maxi(1, ceili(float(_visible_disks.size()) / ROWS))
	_page = clampi(_page, 0, pages - 1)
	if not _selected_uid.is_empty() and not _visible_disks.any(func(disk: Disk) -> bool:
		return disk.uid == _selected_uid):
		_selected_uid = ""
	gauge_fill = clampf(float(DiskManager.media_count()) / float(maxi(1, DiskManager.capacity())), 0.0, 1.0)
	queue_redraw()


func _matches_filter(disk: Disk) -> bool:
	var key: String = str(FILTER_KEYS[clampi(_filter, 0, FILTER_KEYS.size() - 1)])
	return DiskCatalog.matches_category(disk, key)


func _is_pd_coverdisk(disk: Disk) -> bool:
	return DiskCatalog.is_pd_coverdisk(disk)


func _disk_by_uid(uid: String) -> Disk:
	for disk: Disk in DiskManager.media_disks():
		if disk.uid == uid:
			return disk
	return null


func _category(disk: Disk) -> String:
	return DiskCatalog.category(disk)


func _color_name(disk: Disk) -> String:
	match disk.color.to_lower():
		"red": return "ROT"
		"purple", "violet": return "LILA"
		"yellow": return "GELB"
		"blue": return "BLAU"
		"black": return "SCHW."
		_: return disk.color.to_upper().left(5)


func _protection(disk: Disk) -> String:
	if disk.format_locked():
		return "ORIG"
	if disk.write_protected:
		return "SCHR"
	return "OFFEN"


func _content_draw(crp: Rect2, sx: float, sy: float) -> void:
	var font := Wb13.font()
	var fs := Wb13.fsize(sy)
	var x := 4.0
	for i in FILTERS.size():
		var w: float = FILTER_WIDTHS[i]
		_button(crp, sx, sy, Rect2(x, 4, w, 18), FILTERS[i], i == _filter, font, fs)
		x += w + 3.0

	# Tabellenkopf und klare Spalten fuer Inhalt, Farbe, Satz und Schutz.
	_fill(crp, sx, sy, Rect2(4, 27, content_rect().size.x - 8, 18), Wb13.white())
	_label(crp, sx, sy, "NAME / INHALT", 9, 41, font, fs, Wb13.black())
	_label(crp, sx, sy, "TYP", 276, 41, font, fs, Wb13.black())
	_label(crp, sx, sy, "FARBE", 335, 41, font, fs, Wb13.black())
	_label(crp, sx, sy, "SATZ", 395, 41, font, fs, Wb13.black())
	_label(crp, sx, sy, "SCHUTZ", 445, 41, font, fs, Wb13.black())

	var start := _page * ROWS
	if _visible_disks.is_empty():
		_label(crp, sx, sy, "KEINE DATENTRAEGER IN DIESER KATEGORIE", 92, 128,
			font, fs, Wb13.white())
	for row in ROWS:
		var index := start + row
		if index >= _visible_disks.size():
			break
		var disk: Disk = _visible_disks[index]
		var y := 48.0 + row * 20.0
		var selected := disk.uid == _selected_uid
		if selected:
			_fill(crp, sx, sy, Rect2(4, y, content_rect().size.x - 8, 18), Wb13.orange())
		_label(crp, sx, sy, disk.display_name().left(32), 9, y + 14, font, fs,
			Wb13.black() if selected else Wb13.white())
		_label(crp, sx, sy, _category(disk), 276, y + 14, font, fs,
			Wb13.black() if selected else Wb13.white())
		_label(crp, sx, sy, _color_name(disk), 335, y + 14, font, fs,
			Wb13.black() if selected else Wb13.white())
		var part := "%d/%d" % [disk.disk_number, disk.disk_count] if disk.disk_count > 1 else "1/1"
		_label(crp, sx, sy, part, 395, y + 14, font, fs,
			Wb13.black() if selected else Wb13.white())
		_label(crp, sx, sy, _protection(disk), 445, y + 14, font, fs,
			Wb13.black() if selected else Wb13.white())

	var selected_disk := _disk_by_uid(_selected_uid)
	var info := "Doppelklick = starten  ·  Rohlinge: X-COPY / FORMAT"
	if selected_disk != null:
		info = "%s  ·  %s  ·  %s" % [selected_disk.display_name(), selected_disk.condition_text(), selected_disk.write_protect_text()]
	_label(crp, sx, sy, info.left(67), 7, 225, font, fs, Wb13.white())
	var pages := maxi(1, ceili(float(_visible_disks.size()) / ROWS))
	_label(crp, sx, sy, "%d DATENTRAEGER  ·  SEITE %d/%d  ·  SORT: %s" % [
		_visible_disks.size(), _page + 1, pages, DiskManager.SORT_MODES[DiskManager.sort_mode].to_upper()],
		7, 243, font, fs, Wb13.orange())

	_button(crp, sx, sy, Rect2(4, 250, 62, 20), "START", false, font, fs)
	_button(crp, sx, sy, Rect2(69, 250, 68, 20), "X-COPY", false, font, fs)
	_button(crp, sx, sy, Rect2(140, 250, 68, 20), "PRUEFEN", false, font, fs)
	_button(crp, sx, sy, Rect2(211, 250, 68, 20), "BACKUP", false, font, fs)
	_button(crp, sx, sy, Rect2(282, 250, 62, 20), "FORMAT", false, font, fs)
	_button(crp, sx, sy, Rect2(347, 250, 55, 20), "SORT", false, font, fs)
	_button(crp, sx, sy, Rect2(415, 250, 35, 20), "<", false, font, fs)
	_button(crp, sx, sy, Rect2(453, 250, 35, 20), ">", false, font, fs)


func _content_press(v: Vector2, dbl: bool) -> void:
	var x := 4.0
	for i in FILTERS.size():
		var w: float = FILTER_WIDTHS[i]
		if Rect2(x, 4, w, 18).has_point(v):
			_filter = i
			_page = 0
			_selected_uid = ""
			_refresh()
			return
		x += w + 3.0
	if v.y >= 48.0 and v.y < 48.0 + ROWS * 20.0:
		var index := _page * ROWS + int((v.y - 48.0) / 20.0)
		if index >= 0 and index < _visible_disks.size():
			var disk: Disk = _visible_disks[index]
			_selected_uid = disk.uid
			queue_redraw()
			if dbl:
				_start_selected()
		return
	if Rect2(4, 250, 62, 20).has_point(v):
		_start_selected()
	elif Rect2(69, 250, 68, 20).has_point(v):
		_open_xcopy("copy")
	elif Rect2(140, 250, 68, 20).has_point(v):
		_open_xcopy("check")
	elif Rect2(211, 250, 68, 20).has_point(v):
		_open_xcopy("backup")
	elif Rect2(282, 250, 62, 20).has_point(v):
		UIManager.open_program("disk_formatter")
	elif Rect2(347, 250, 55, 20).has_point(v):
		DiskManager.cycle_sort()
		_refresh()
	elif Rect2(415, 250, 35, 20).has_point(v):
		_page_by(-1)
	elif Rect2(453, 250, 35, 20).has_point(v):
		_page_by(1)


func _start_selected() -> void:
	var disk := _disk_by_uid(_selected_uid)
	if disk == null:
		UIManager.toast(Loc.t("ui.wb_disk_directory_window.waehle_zuerst_diskette_aus", "Waehle zuerst eine Diskette aus."))
		return
	if disk.content_type == "leer":
		UIManager.toast(Loc.t("ui.wb_disk_directory_window.df0_diese_diskette_ist_leer", "DF0: Diese Diskette ist leer."))
		return
	UIManager.play_disk_flow(disk)


func _open_xcopy(operation_kind: String) -> void:
	var disk := _disk_by_uid(_selected_uid)
	if disk == null:
		UIManager.toast(Loc.t("ui.wb_disk_directory_window.waehle_zuerst_quelldiskette_aus", "Waehle zuerst eine Quelldiskette aus."))
		return
	if disk.content_type == "leer":
		UIManager.toast(Loc.t("ui.wb_disk_directory_window.leere_diskette_kann_keine_quelle_sein", "Eine leere Diskette kann keine Quelle sein."))
		return
	UIManager.open_disk_copy(disk, operation_kind)


func _page_by(delta: int) -> void:
	var pages := maxi(1, ceili(float(_visible_disks.size()) / ROWS))
	_page = posmod(_page + delta, pages)
	_selected_uid = ""
	queue_redraw()


func _fill(crp: Rect2, sx: float, sy: float, r: Rect2, color: Color) -> void:
	draw_rect(Rect2(crp.position + Vector2(r.position.x * sx, r.position.y * sy),
		Vector2(r.size.x * sx, r.size.y * sy)), color)


func _label(crp: Rect2, sx: float, sy: float, value: String, x: float, y: float,
		font: Font, fs: int, color: Color) -> void:
	draw_string(font, crp.position + Vector2(x * sx, y * sy), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _button(crp: Rect2, sx: float, sy: float, r: Rect2, value: String, pressed: bool,
		font: Font, fs: int) -> void:
	var physical := Rect2(crp.position + Vector2(r.position.x * sx, r.position.y * sy),
		Vector2(r.size.x * sx, r.size.y * sy))
	draw_rect(physical, Wb13.black() if pressed else Wb13.white())
	draw_rect(physical, Wb13.white() if pressed else Wb13.black(), false, maxf(1.0, sy))
	draw_string(font, crp.position + Vector2(r.position.x * sx, (r.position.y + 15.0) * sy), value,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x * sx, fs, Wb13.white() if pressed else Wb13.black())
