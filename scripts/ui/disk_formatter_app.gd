class_name DiskFormatterApp
extends WbApp
## Workbench 1.3 „Disk / Initialize“ als echter Datenträger-Vorgang:
## physisches Medium nach DF0: wählen, Schreibschutz prüfen, OFS/FFS festlegen,
## zwei Systemwarnungen bestätigen und 80 Zylinder schreiben. Erst nach dem
## vollständigen Lauf werden die Inhaltsdaten atomar gelöscht.

const ROWS := 7
const C_BLUE := Color8(0, 85, 170)
const C_WHITE := Color8(255, 255, 255)
const C_BLACK := Color8(0, 0, 0)
const C_ORANGE := Color8(255, 136, 0)

var _selected := 0
var _page := 0
var _phase := "choose" # choose / warning_one / warning_two / formatting / complete
var _filesystem := "OFS"
var _progress := 0.0
var _cylinder := 0
var _audio_cylinder := -1
var _format_uid := ""
var _status := "Select a disk, then choose INITIALIZE."


func _init() -> void:
	app_title = "Initialize Disk   ·   Workbench 1.3"
	app_bg = C_BLUE
	app_bar = C_WHITE
	app_accent = C_ORANGE


func _build_app() -> void:
	_rebuild_widgets()
	if not DiskManager.disks_changed.is_connected(_on_disks_changed):
		DiskManager.disks_changed.connect(_on_disks_changed)


func _exit_tree() -> void:
	if DiskManager.disks_changed.is_connected(_on_disks_changed):
		DiskManager.disks_changed.disconnect(_on_disks_changed)


func has_active_operation() -> bool:
	return _phase == "formatting"


func active_operation_message() -> String:
	return "DF0: wird gerade formatiert. Warte bis Zylinder 79; der Ortswechsel ist gesperrt."


func close_app() -> void:
	if has_active_operation():
		_status = active_operation_message()
		queue_redraw()
		return
	super.close_app()


func _rebuild_widgets() -> void:
	clear_widgets()
	var locked := _phase == "formatting"
	var media := DiskManager.media_disks()
	var max_page := maxi(0, ceili(float(media.size()) / ROWS) - 1)
	_page = clampi(_page, 0, max_page)
	var start := _page * ROWS
	for row in ROWS:
		var index := start + row
		if index >= media.size():
			break
		var widget := add_button("", Rect2(18, 70 + row * 36, 340, 31), _select.bind(index), C_WHITE, false)
		(widget["node"] as Button).disabled = locked
	var previous := add_button("<", Rect2(18, 332, 42, 28), _page_by.bind(-1), C_WHITE)
	var next := add_button(">", Rect2(66, 332, 42, 28), _page_by.bind(1), C_WHITE)
	(previous["node"] as Button).disabled = locked or max_page == 0
	(next["node"] as Button).disabled = locked or max_page == 0

	if _phase == "choose" or _phase == "complete":
		add_button("WRITE PROTECT", Rect2(390, 126, 224, 36), _toggle_protect, C_WHITE)
		add_button("FILESYSTEM: %s" % _filesystem, Rect2(390, 172, 224, 36), _toggle_filesystem, C_WHITE)
		add_button("INITIALIZE...", Rect2(390, 232, 224, 46), _begin_warning, C_WHITE)
	elif _phase in ["warning_one", "warning_two"]:
		add_button("CANCEL", Rect2(392, 295, 96, 38), _cancel_warning, C_WHITE)
		add_button("CONTINUE", Rect2(500, 295, 114, 38), _continue_warning, C_WHITE)
	_layout()


func _selected_disk() -> Disk:
	var media := DiskManager.media_disks()
	return media[_selected] if _selected >= 0 and _selected < media.size() else null


func _select(index: int) -> void:
	if _phase == "formatting":
		return
	_selected = index
	_phase = "choose"
	_progress = 0.0
	var disk := _selected_disk()
	if disk != null:
		AudioManager.floppy_eject()
		AudioManager.floppy_insert()
		_status = "DF0: %s  ·  %s" % [disk.display_name(), disk.write_protect_text()]
	_rebuild_widgets()


func _page_by(delta: int) -> void:
	var media := DiskManager.media_disks()
	var pages := maxi(1, ceili(float(media.size()) / ROWS))
	_page = posmod(_page + delta, pages)
	_selected = mini(_page * ROWS, maxi(0, media.size() - 1))
	_phase = "choose"
	_rebuild_widgets()


func _toggle_protect() -> void:
	var disk := _selected_disk()
	if disk == null:
		_status = "No disk present in device DF0:"
		return
	var result := DiskManager.set_write_protected(disk, not disk.write_protected)
	_status = str(result.get("text", "Write-protect unchanged."))


func _toggle_filesystem() -> void:
	_filesystem = "FFS" if _filesystem == "OFS" else "OFS"
	_status = ("FFS selected. Workbench 1.3 supports it; older systems may not." if _filesystem == "FFS" else
		"OFS selected. Standard compatible floppy format for 1990.")
	_rebuild_widgets()


func _begin_warning() -> void:
	var disk := _selected_disk()
	if disk == null:
		_status = "No disk present in device DF0:"
		return
	if disk.format_locked():
		_status = "ORIGINAL LOCK: This disk remains in the archive."
		return
	if disk.write_protected:
		_status = "Disk is write protected. Open the physical slider first."
		return
	_phase = "warning_one"
	_status = "Initializing will destroy every file on this disk."
	_rebuild_widgets()


func _continue_warning() -> void:
	if _phase == "warning_one":
		_phase = "warning_two"
		_status = "Last chance: the old contents cannot be restored."
		_rebuild_widgets()
		return
	if _phase == "warning_two":
		_start_format()


func _cancel_warning() -> void:
	_phase = "choose"
	_status = "Initialize cancelled. The disk was not changed."
	_rebuild_widgets()


func _start_format() -> void:
	var disk := _selected_disk()
	if disk == null or disk.format_locked() or disk.write_protected:
		_phase = "choose"
		_status = "DF0: is no longer ready. Nothing was changed."
		_rebuild_widgets()
		return
	if PlayerStats.energie < 5:
		_phase = "choose"
		_status = "Too tired for a full 80-cylinder format."
		_rebuild_widgets()
		return
	_phase = "formatting"
	_progress = 0.0
	_cylinder = 0
	_audio_cylinder = -1
	_format_uid = disk.uid
	_status = "Drive DF0: active. Do not remove the disk."
	AudioManager.floppy_read()
	_rebuild_widgets()


func _app_process(delta: float) -> void:
	if _phase != "formatting":
		return
	# Rund acht reale Sekunden vermitteln die mechanische Arbeit, ohne einen
	# zehnminütigen Spieltag mit der historischen ~80-Sekunden-Wartezeit zu sprengen.
	_progress = minf(1.0, _progress + delta / 8.0)
	_cylinder = mini(79, floori(_progress * 80.0))
	if int(_cylinder / 8.0) != int(_audio_cylinder / 8.0):
		_audio_cylinder = _cylinder
		AudioManager.floppy_read()
	if _progress < 1.0:
		return
	var disk := _selected_disk()
	if disk == null or disk.uid != _format_uid:
		_phase = "choose"
		_status = "Disk changed during initialize. Operation aborted safely."
		_rebuild_widgets()
		return
	var result := DiskManager.format_disk(disk, _filesystem, "Empty")
	_phase = "complete" if bool(result.get("ok", false)) else "choose"
	_status = str(result.get("text", "Initialize failed."))
	AudioManager.floppy_eject()
	_rebuild_widgets()


func _on_disks_changed() -> void:
	_selected = clampi(_selected, 0, maxi(0, DiskManager.media_count() - 1))
	queue_redraw()


func _content(font: Font) -> void:
	# Vierfarbige 1.3-Oberfläche: keine moderne Karte, keine Neon-Telemetrie.
	rect(10, 34, 358, 340, C_WHITE)
	rect(12, 36, 354, 336, C_BLUE)
	text(font, "DISKETTENBOX  ·  SELECT MEDIA FOR DF0:", 18, 54, 10, C_WHITE)
	var start := _page * ROWS
	var media := DiskManager.media_disks()
	for row in ROWS:
		var index := start + row
		if index >= media.size():
			break
		var row_disk: Disk = media[index]
		var y := 70.0 + row * 36.0
		var selected := index == _selected
		rect(18, y, 340, 31, C_ORANGE if selected else C_WHITE)
		rect(20, y + 2, 336, 27, C_BLACK if selected else C_BLUE)
		text(font, row_disk.display_name().left(31), 27, y + 13, 9, C_WHITE)
		var protection_text := "ORIGINAL LOCK" if row_disk.format_locked() else ("WRITE PROTECTED" if row_disk.write_protected else "WRITE ENABLED")
		text(font, "%s  ·  %s" % [row_disk.content_type.to_upper(), protection_text], 27, y + 25, 7,
			C_ORANGE if row_disk.write_protected or row_disk.format_locked() else C_WHITE)
	text(font, "PAGE %d/%d" % [_page + 1, maxi(1, ceili(float(media.size()) / ROWS))], 120, 351, 8, C_WHITE)

	# Rechter Workbench-Requester / DF0:-Status.
	rect(380, 50, 246, 310, C_WHITE)
	rect(383, 53, 240, 304, C_BLUE)
	var disk := _selected_disk()
	text_c(font, "DF0:", 390, 614, 76, 14, C_WHITE)
	if disk != null:
		text_c(font, disk.display_name().left(28), 390, 614, 98, 10, C_WHITE)
		text_c(font, disk.write_protect_text(), 390, 614, 113, 7,
			C_ORANGE if disk.write_protected else C_WHITE)

	if _phase in ["warning_one", "warning_two"]:
		_draw_warning(font, disk)
	elif _phase == "formatting":
		_draw_format_progress(font)
	else:
		text(font, "80 CYLINDERS · 2 SIDES", 397, 294, 8, C_WHITE)
		text(font, "11 SECTORS × 512 BYTES", 397, 309, 8, C_WHITE)
		text(font, "VOLUME: Empty", 397, 324, 8, C_WHITE)
		text(font, "MODE: %s · FULL FORMAT" % _filesystem, 397, 339, 8, C_ORANGE)

	# Workbench-Statuszeile. Der tatsächliche Inhalt wird erst nach Zylinder 79
	# gelöscht; bis dahin bleibt das Disk-Objekt nachweislich unverändert.
	rect(10, 376, 616, 16, C_WHITE)
	text(font, _status.left(94), 16, 388, 8, C_BLACK)


func _draw_warning(font: Font, disk: Disk) -> void:
	rect(392, 126, 222, 162, C_BLACK)
	rect(395, 129, 216, 156, C_WHITE)
	text_c(font, "SYSTEM REQUEST", 402, 604, 151, 10, C_BLACK)
	var title := disk.display_name().left(25) if disk != null else "DF0:"
	if _phase == "warning_one":
		text_c(font, "ALL DATA ON", 402, 604, 180, 9, C_BLACK)
		text_c(font, title, 402, 604, 196, 9, C_BLACK)
		text_c(font, "WILL BE DESTROYED.", 402, 604, 212, 9, C_BLACK)
	else:
		text_c(font, "LAST CHANCE.", 402, 604, 180, 9, C_BLACK)
		text_c(font, "THIS CANNOT BE UNDONE.", 402, 604, 200, 9, C_BLACK)
		text_c(font, "CONTINUE?", 402, 604, 220, 9, C_BLACK)


func _draw_format_progress(font: Font) -> void:
	rect(392, 126, 222, 207, C_BLACK)
	text(font, "System:Format", 401, 146, 9, C_WHITE)
	text(font, "Formatting cylinder %02d" % _cylinder, 401, 166, 9, C_WHITE)
	text(font, "DF0: Empty  %s" % _filesystem, 401, 184, 8, C_WHITE)
	for index in 80:
		var col := index % 10
		var row := floori(float(index) / 10.0)
		var done := index <= _cylinder
		rect(402 + col * 20, 202 + row * 12, 15, 8, C_ORANGE if done else C_BLUE)
	text(font, "%d%%  ·  DRIVE LED ON" % floori(_progress * 100.0), 401, 318, 8, C_WHITE)
