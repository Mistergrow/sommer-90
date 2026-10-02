class_name DiskPickerScreen
extends Control
## Disketten-Auswahl als modales Overlay (wie der Kickstart-Boot-Wähler, aber
## für X-COPY): zeigt eine gefilterte Liste der Disketten — z. B. bespielte für
## die QUELLE oder nur LEERdisketten fürs ZIEL — und liefert die gewählte
## Diskette per Callback zurück. Legt sich über das aufrufende Programm.
##
## Verwendung:
##   var p := DiskPickerScreen.new()
##   p.title = "Quelle einlegen"; p.disks = [...]; p.on_pick = func(d): ...
##   add_child(p)

const VW := 640.0
const VH := 400.0
const CELL := Vector2(90, 86)
const COLS := 6
const PAGE_SIZE := 18
const GRID_ORIGIN := Vector2(50, 84)
const PREV_RECT := Rect2(548, 20, 24, 16)
const NEXT_RECT := Rect2(608, 20, 24, 16)

var title := "Diskette wählen"
var subtitle := ""
var disks: Array = []          # vorgefilterte Disk-Liste
var on_pick: Callable = Callable()
var on_cancel: Callable = Callable()
var recommended_uid := ""     # gefuehrtes Tutorial: klarer, nicht exklusiver Tipp

var _rows: Array = []          # {disk, kind, rect}
var _hover := -1
var _page := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 70
	_fit_parent()
	var p := get_parent_control()
	if p != null:
		p.resized.connect(_fit_parent)
	_build()
	AudioManager.floppy_insert()


func _fit_parent() -> void:
	var p := get_parent_control()
	if p != null:
		position = Vector2.ZERO
		size = p.size
	_layout()
	queue_redraw()


func _sx() -> float: return size.x / VW
func _sy() -> float: return size.y / VH


func _build() -> void:
	_rows = []
	for d in disks:
		if d == null or d.is_boxed_package():
			continue
		_rows.append({"disk": d, "kind": _kind_for(d), "rect": Rect2()})
	if not recommended_uid.is_empty():
		for index in _rows.size():
			if str(_rows[index]["disk"].uid) == recommended_uid:
				_page = floori(float(index) / float(PAGE_SIZE))
				break
	_layout()


func _kind_for(d) -> String:
	if d.content_type == "system":
		return "disk_wb"
	return "disk_plain"


func _layout() -> void:
	for row in _rows:
		row["rect"] = Rect2(-1000, -1000, 1, 1)
	for index in range(_page_start(), _page_end()):
		var local := index - _page_start()
		var col := local % COLS
		var line := floori(float(local) / float(COLS))
		_rows[index]["rect"] = Rect2(GRID_ORIGIN + Vector2(col * CELL.x, line * CELL.y), CELL)


func _page_count() -> int:
	return maxi(1, ceili(float(_rows.size()) / float(PAGE_SIZE)))


func _page_start() -> int:
	return _page * PAGE_SIZE


func _page_end() -> int:
	return mini(_page_start() + PAGE_SIZE, _rows.size())


func _set_page(value: int) -> void:
	var next := clampi(value, 0, _page_count() - 1)
	if next == _page:
		return
	_page = next
	_hover = -1
	_layout()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel()
		elif event.keycode == KEY_PAGEUP:
			get_viewport().set_input_as_handled()
			_set_page(_page - 1)
		elif event.keycode == KEY_PAGEDOWN:
			get_viewport().set_input_as_handled()
			_set_page(_page + 1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var v := Vector2(event.position.x / _sx(), event.position.y / _sy())
		var h := -1
		for i in range(_page_start(), _page_end()):
			if (_rows[i]["rect"] as Rect2).has_point(v):
				h = i
		if h != _hover:
			_hover = h
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
		if PREV_RECT.has_point(v):
			_set_page(_page - 1)
			return
		if NEXT_RECT.has_point(v):
			_set_page(_page + 1)
			return
		for index in range(_page_start(), _page_end()):
			if (_rows[index]["rect"] as Rect2).has_point(v):
				_pick(_rows[index]["disk"])
				return


func _pick(disk) -> void:
	AudioManager.stop_floppy()      # laufendes Rattern beenden, sauberes Einlegen
	AudioManager.floppy_insert()
	var cb := on_pick
	queue_free()
	if cb.is_valid():
		cb.call(disk)


func _cancel() -> void:
	var cb := on_cancel
	queue_free()
	if cb.is_valid():
		cb.call()


func _draw() -> void:
	var sx := _sx()
	var sy := _sy()
	var font := Wb13.font()
	var fs := Wb13.fsize(sy)
	# Abdunkeln + Rahmen
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 20.0 / 255.0, 0.82))
	draw_rect(Rect2(16.0 * sx, 16.0 * sy, size.x - 32.0 * sx, size.y - 32.0 * sy),
		Color8(0, 85, 170), false, maxf(2.0, sy * 2.0))
	draw_string(font, Vector2(0, 44.0 * sy), title, HORIZONTAL_ALIGNMENT_CENTER, size.x,
		int(fs * 1.15), Wb13.white())
	_draw_page_button(PREV_RECT, "<", _page > 0, font, fs, sx, sy)
	_draw_page_button(NEXT_RECT, ">", _page + 1 < _page_count(), font, fs, sx, sy)
	draw_string(font, Vector2(572.0 * sx, 34.0 * sy), "%d/%d" % [_page + 1, _page_count()],
		HORIZONTAL_ALIGNMENT_CENTER, 36.0 * sx, maxi(4, int(fs * 0.7)), Wb13.white())
	if subtitle != "":
		draw_string(font, Vector2(0, 64.0 * sy), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x,
			maxi(4, int(fs * 0.8)), Color8(150, 190, 230))
	if _rows.is_empty():
		draw_string(font, Vector2(0, size.y * 0.5), "Keine passende Diskette vorhanden.",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color8(240, 180, 90))
	for i in range(_page_start(), _page_end()):
		var r: Rect2 = _rows[i]["rect"]
		var d = _rows[i]["disk"]
		var pr := Rect2(r.position.x * sx, r.position.y * sy, r.size.x * sx, r.size.y * sy)
		var recommended := recommended_uid != "" and str(d.uid) == recommended_uid
		if recommended:
			draw_rect(pr.grow(-2.0 * sx), Color(0.12, 0.34, 0.18, 0.34), true)
			draw_rect(pr.grow(-2.0 * sx), Color8(96, 226, 116), false, maxf(2.0, sy * 2.0))
		if i == _hover:
			draw_rect(pr, Color8(0, 85, 170))
			draw_rect(pr, Wb13.orange(), false, maxf(1.0, sy))
		# Physische Farbe statt generischem Disk-Icon: Rot/Blau ist Teil der
		# Kopiergrammatik und muss schon im Einlege-Dialog lesbar sein.
		var disk_tex := Sprites.disk_icon(Palette.disk_color(str(d.color)))
		var isz := disk_tex.get_size()
		var icon_scale := minf((CELL.x - 42.0) / isz.x, (CELL.y - 46.0) / isz.y) * sx
		var iw := isz.x * icon_scale
		var ih := isz.y * icon_scale
		var ip := Vector2(pr.position.x + (pr.size.x - iw) * 0.5, pr.position.y + 4.0 * sy)
		draw_texture_rect(disk_tex, Rect2(ip, Vector2(iw, ih)), false)
		draw_string(font, Vector2(pr.position.x, ip.y + ih + 12.0 * sy), _short(d.display_name()),
			HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, maxi(4, int(fs * 0.8)), Wb13.white())
		var condition := "%d%%" % d.condition if d.checked else "???"
		var media := _media_code(d, condition)
		draw_string(font, Vector2(pr.position.x, ip.y + ih + 23.0 * sy), media,
			HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, maxi(4, int(fs * 0.7)), Color8(150, 200, 160))
	draw_rect(Rect2(16.0 * sx, 350.0 * sy, size.x - 32.0 * sx, 34.0 * sy), Color(0, 0.05, 0.12, 0.88))
	var detail := "Diskette anklicken · Rad/Bild auf-ab = Seite · Esc = abbrechen"
	if _hover >= 0 and _hover < _rows.size():
		var disk: Disk = _rows[_hover]["disk"]
		detail = "%s · %s" % [disk.display_name(), disk.condition_text()]
	draw_string(font, Vector2(24.0 * sx, 371.0 * sy), detail.left(86),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 48.0 * sx, maxi(4, int(fs * 0.72)), Color8(170, 198, 226))


func _draw_page_button(rect: Rect2, label: String, enabled: bool, font: Font,
		fs: int, sx: float, sy: float) -> void:
	var physical := Rect2(rect.position * Vector2(sx, sy), rect.size * Vector2(sx, sy))
	draw_rect(physical, Color8(0, 85, 170) if enabled else Color8(48, 62, 82))
	draw_rect(physical, Wb13.white(), false, maxf(1.0, sy))
	draw_string(font, Vector2(physical.position.x, physical.position.y + 13.0 * sy), label,
		HORIZONTAL_ALIGNMENT_CENTER, physical.size.x, maxi(4, int(fs * 0.72)), Wb13.white())


func _short(s: String) -> String:
	return s if s.length() <= 12 else s.substr(0, 11) + "…"


func _media_code(d: Disk, condition: String) -> String:
	match str(d.color):
		"yellow": return "GELB · BYTEWERK"
		"purple": return "LILA · AAA-ORIGINAL"
		"red": return "ROT · MASTER"
		"blue":
			if d.content_type == "leer":
				return "LEER · BLAU"
	return "KOPIE · G%d" % maxi(1, d.copy_generation) if d.is_player_made_copy() else condition
