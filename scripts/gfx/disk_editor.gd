extends Control
## Disk-Editor — legt PIXELGENAU fest, wo das Spiel-Label auf der Master-Diskette
## sitzt (wie der Zimmer-/Deko-Editor). Master + Beispiel-Label werden angezeigt,
## der Rahmen wird gezogen/skaliert, das Ergebnis landet in data/disk_layout.json.
## Öffnen: scenes/DiskEditor.tscn im Godot-Editor abspielen.
##
## Steuerung: Linksziehen im Rahmen = verschieben · Ecken ziehen = skalieren ·
## Mausrad = Zoom · Mittlere Maustaste = schwenken · ←/→ = Beispiel-Label wechseln ·
## S = speichern · R = Rahmen zurücksetzen.

const LAYOUT_PATH := "res://data/disk_layout.json"
const MASTER_PATH := "res://assets/backgrounds/layers/FLOPPY_35_DD_BLUE_FRONT_V01.png"
const HANDLE := 9.0
const SoftwareBibleCodec := preload("res://scripts/autoload/software_bible.gd")

var _master: Texture2D
var _labels: Array = []          # [{id, tex}]
var _lidx := 0
var _rect := {"x": 0.5, "y": 0.6, "w": 0.78, "h": 0.42}   # Mitte + Größe (Anteile)
var _sprite_rect := Rect2()
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _dragging := false
var _resize := -1                # gezogene Ecke 0..3, -1 = keine
var _grab := Vector2.ZERO
var _saved_flash := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_master = _load_tex(MASTER_PATH)
	_gather_labels()
	_load_layout()
	set_process(true)


func _process(delta: float) -> void:
	if _saved_flash > 0.0:
		_saved_flash = maxf(0.0, _saved_flash - delta)
		queue_redraw()


# ------------------------------------------------------------- Laden
func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := SoftwareBibleCodec.decode_image(FileAccess.get_file_as_bytes(path)) # PNG oder JPEG
	return ImageTexture.create_from_image(img) if img != null else null


func _gather_labels() -> void:
	var dir := DirAccess.open("res://assets/software")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if dir.current_is_dir() and not entry_name.begins_with("."):
			var p := "res://assets/software/%s/disk_label.png" % entry_name
			var tex := _load_tex(p)
			if tex != null:
				_labels.append({"id": entry_name, "tex": tex})
		entry_name = dir.get_next()
	dir.list_dir_end()


func _load_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if typeof(p) == TYPE_DICTIONARY and (p as Dictionary).has("label"):
		var r: Variant = (p as Dictionary)["label"]
		if typeof(r) == TYPE_DICTIONARY:
			for k in ["x", "y", "w", "h"]:
				if (r as Dictionary).has(k):
					_rect[k] = float((r as Dictionary)[k])


func _save() -> void:
	var data := {"comment": "Platzierung des Spiel-Labels auf der Master-Diskette (Single Source). Bearbeitet im Disk-Editor.",
		"master": MASTER_PATH, "label": {
			"x": snappedf(float(_rect["x"]), 0.001), "y": snappedf(float(_rect["y"]), 0.001),
			"w": snappedf(float(_rect["w"]), 0.001), "h": snappedf(float(_rect["h"]), 0.001)}}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t", false))
	_saved_flash = 1.2
	if ClassDB.class_exists("DiskComposer") or true:
		DiskComposer.reload()


# ------------------------------------------------------------- Geometrie
func _compute_sprite_rect() -> void:
	if _master == null:
		_sprite_rect = Rect2()
		return
	var ts := Vector2(_master.get_size())
	var s: float = minf(size.x * 0.66 / ts.x, size.y * 0.82 / ts.y) * _zoom
	var draw_size := ts * s
	_sprite_rect = Rect2(((size - draw_size) * 0.5 + _pan).floor(), draw_size)


func _frame_rect() -> Rect2:
	var c := _sprite_rect.position + Vector2(float(_rect["x"]), float(_rect["y"])) * _sprite_rect.size
	var sz := Vector2(float(_rect["w"]), float(_rect["h"])) * _sprite_rect.size
	return Rect2(c - sz * 0.5, sz)


func _corners(r: Rect2) -> Array:
	return [r.position, r.position + Vector2(r.size.x, 0), r.position + r.size,
		r.position + Vector2(0, r.size.y)]


func _corner_at(point: Vector2) -> int:
	var cs := _corners(_frame_rect())
	for i in 4:
		if (cs[i] as Vector2).distance_to(point) <= HANDLE + 2.0:
			return i
	return -1


# ------------------------------------------------------------- Eingabe
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_compute_sprite_rect()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_resize = _corner_at(event.position)
				if _resize >= 0:
					return
				if _frame_rect().has_point(event.position):
					_dragging = true
					_grab = event.position - _frame_rect().get_center()
			MOUSE_BUTTON_MIDDLE:
				_panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, 0.87)
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = false
			_resize = -1
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			queue_redraw()
			return
		if _sprite_rect.size.x <= 1.0:
			return
		if _resize >= 0:
			var fixed: Vector2 = _corners(_frame_rect())[(_resize + 2) % 4]
			var nr := Rect2(Vector2(minf(fixed.x, event.position.x), minf(fixed.y, event.position.y)),
				(event.position - fixed).abs())
			var center := (nr.position + nr.size * 0.5 - _sprite_rect.position) / _sprite_rect.size
			var sz := nr.size / _sprite_rect.size
			_rect["x"] = center.x
			_rect["y"] = center.y
			_rect["w"] = maxf(sz.x, 0.02)
			_rect["h"] = maxf(sz.y, 0.02)
			queue_redraw()
		elif _dragging:
			var frac: Vector2 = (event.position - _grab - _sprite_rect.position) / _sprite_rect.size
			_rect["x"] = clampf(frac.x, 0.0, 1.0)
			_rect["y"] = clampf(frac.y, 0.0, 1.0)
			queue_redraw()


func _zoom_at(p: Vector2, factor: float) -> void:
	if _master == null:
		return
	_compute_sprite_rect()
	var frac := (p - _sprite_rect.position) / _sprite_rect.size
	_zoom = clampf(_zoom * factor, 1.0, 12.0)
	var ts := Vector2(_master.get_size())
	var s: float = minf(size.x * 0.66 / ts.x, size.y * 0.82 / ts.y) * _zoom
	var draw_size := ts * s
	_pan = p - (size - draw_size) * 0.5 - frac * draw_size
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_S:
			_save()
		KEY_R:
			_rect = {"x": 0.5, "y": 0.6, "w": 0.78, "h": 0.42}
			queue_redraw()
		KEY_LEFT:
			if not _labels.is_empty():
				_lidx = wrapi(_lidx - 1, 0, _labels.size())
				queue_redraw()
		KEY_RIGHT:
			if not _labels.is_empty():
				_lidx = wrapi(_lidx + 1, 0, _labels.size())
				queue_redraw()


# ------------------------------------------------------------- Zeichnen
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.11, 0.14))
	_compute_sprite_rect()
	if _master == null:
		draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Master-Disk nicht gefunden: " + MASTER_PATH, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.RED)
		return
	# Master-Disk
	draw_texture_rect(_master, _sprite_rect, false)
	# Label-Vorschau im Rahmen (alpha-korrekt über der Disk)
	var fr := _frame_rect()
	if not _labels.is_empty():
		draw_texture_rect(_labels[_lidx]["tex"], fr, false)
	# Rahmen + Ecken
	draw_rect(fr, Color(0.2, 1.0, 0.6, 0.9), false, 2.0)
	for c: Vector2 in _corners(fr):
		draw_rect(Rect2(c - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), Color(1, 0.9, 0.3))
	# Fadenkreuz Mitte
	var mid := fr.get_center()
	draw_line(mid - Vector2(6, 0), mid + Vector2(6, 0), Color(1, 1, 1, 0.6))
	draw_line(mid - Vector2(0, 6), mid + Vector2(0, 6), Color(1, 1, 1, 0.6))
	_draw_hud()


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var lid: String = _labels[_lidx]["id"] if not _labels.is_empty() else "(keine Labels in assets/software)"
	var lines := [
		"DISK-EDITOR  —  Label auf der Master-Diskette platzieren",
		"Rahmen ziehen = verschieben · Ecken = skalieren · Rad = Zoom · Mitte = schwenken",
		"←/→ Beispiel-Label   ·   S = speichern   ·   R = Rahmen zuruecksetzen",
		"Label: x=%.3f  y=%.3f  w=%.3f  h=%.3f" % [_rect["x"], _rect["y"], _rect["w"], _rect["h"]],
		"Beispiel: %s   (%d/%d)" % [lid, _lidx + 1 if not _labels.is_empty() else 0, _labels.size()],
	]
	var y := 24.0
	for t: String in lines:
		draw_string(font, Vector2(20, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.95, 1.0))
		y += 22.0
	if _saved_flash > 0.0:
		draw_string(font, Vector2(20, y + 6), "✔ gespeichert → data/disk_layout.json", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.3, 1.0, 0.5, _saved_flash))
