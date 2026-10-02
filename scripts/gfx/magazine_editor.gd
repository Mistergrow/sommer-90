extends Control
## Magazin-Cover-Editor — richtet ein Cover PIXELGENAU auf das Master-Magazin
## (MAGAZINE_MASTER_V02, leeres Heft in Schräglage) aus, wie der Monitor auf die
## Bildröhre. Vier Ecken werden einzeln gezogen → das Cover wird perspektivisch
## (2 texturierte Dreiecke) in die Titelfläche eingepasst. Das Ergebnis (Ecken
## als Anteile 0..1 der Masterfläche) landet in data/magazine_layout.json und
## gilt für ALLE Cover (alle 3:4). Öffnen: scenes/MagazineEditor.tscn abspielen.
##
## Steuerung: Ecke ziehen = Perspektive · in der Fläche ziehen = ganzes Cover
## verschieben · Mausrad = Zoom · mittlere Maustaste = schwenken ·
## ←/→ = Cover wechseln · G = Cover-Gitter an/aus · R = zurücksetzen ·
## F8 / Strg+S = SPEICHERN.

const LAYOUT_PATH := "res://data/magazine_layout.json"
const MASTER_PATH := "res://assets/backgrounds/layers/MAGAZINE_MASTER_V02.png"
const COVERS_DIR := "res://assets/ui/magazines/amiga_joker/1990"
const HANDLE := 10.0

var _master: Texture2D
var _covers: Array = []            # [{id, tex}]
var _cidx := 0
# Cover-Ecken als Anteile der Masterfläche (TL, TR, BR, BL). Startwerte grob auf
# die Titelfläche des schrägen Hefts gelegt — im Editor feinjustieren.
var _quad: Array = [Vector2(0.14, 0.06), Vector2(0.92, 0.16),
	Vector2(0.86, 0.95), Vector2(0.06, 0.83)]
var _sprite_rect := Rect2()
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _drag_corner := -1             # gezogene Ecke 0..3
var _drag_all := false             # ganzes Cover verschieben
var _grab := Vector2.ZERO
var _show_grid := false
var _saved_flash := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_master = _load_tex(MASTER_PATH)
	_gather_covers()
	_load_layout()
	set_process(true)
	grab_focus.call_deferred()


func _process(delta: float) -> void:
	if _saved_flash > 0.0:
		_saved_flash = maxf(0.0, _saved_flash - delta)
		queue_redraw()


# ------------------------------------------------------------------- Laden

func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	return load(path) as Texture2D


func _gather_covers() -> void:
	var dir := DirAccess.open(COVERS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	var names: Array = []
	while f != "":
		# Nur VORDERSEITEN in die Cover-Auswahl — Rückseiten (_back) und
		# Berichts-Innenseiten (_bericht_N, Querformat) gehören nicht auf den
		# Titel-Slot des Masters.
		if f.ends_with(".png") and not f.contains("_back") and not f.contains("_bericht_"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var tex := _load_tex(COVERS_DIR + "/" + n)
		if tex != null:
			_covers.append({"id": n.get_basename(), "tex": tex})


func _load_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if typeof(p) != TYPE_DICTIONARY:
		return
	var corners: Variant = (p as Dictionary).get("cover_quad", [])
	if corners is Array and (corners as Array).size() == 4:
		for i in 4:
			var c: Variant = corners[i]
			if c is Array and (c as Array).size() == 2:
				_quad[i] = Vector2(float(c[0]), float(c[1]))


func _save() -> void:
	var corners: Array = []
	for v: Vector2 in _quad:
		corners.append([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)])
	var data := {
		"comment": "Perspektivische Cover-Platzierung auf MAGAZINE_MASTER_V02 (Single Source). "
			+ "Ecken TL,TR,BR,BL als Anteile 0..1 der Masterfläche. Bearbeitet im Magazin-Editor.",
		"master": MASTER_PATH,
		"cover_quad": corners,
	}
	var fp := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if fp != null:
		fp.store_string(JSON.stringify(data, "\t", false))
	_saved_flash = 1.4


# ------------------------------------------------------------------- Geometrie

func _compute_sprite_rect() -> void:
	if _master == null:
		_sprite_rect = Rect2(Vector2.ZERO, Vector2.ZERO)
		return
	var ts := Vector2(_master.get_size())
	var s: float = minf(size.x * 0.62 / ts.x, size.y * 0.82 / ts.y) * _zoom
	var draw_size := ts * s
	_sprite_rect = Rect2(((size - draw_size) * 0.5 + _pan).floor(), draw_size)


## Bildschirm-Position einer Quad-Ecke (aus dem Anteil).
func _corner_pos(i: int) -> Vector2:
	return _sprite_rect.position + (_quad[i] as Vector2) * _sprite_rect.size


func _corner_at(point: Vector2) -> int:
	for i in 4:
		if _corner_pos(i).distance_to(point) <= HANDLE + 3.0:
			return i
	return -1


## Liegt der Punkt im Cover-Viereck? (Für Ganz-Cover-Verschiebung.)
func _inside_quad(point: Vector2) -> bool:
	var poly := PackedVector2Array([_corner_pos(0), _corner_pos(1), _corner_pos(2), _corner_pos(3)])
	return Geometry2D.is_point_in_polygon(point, poly)


func _quad_center_px() -> Vector2:
	return (_corner_pos(0) + _corner_pos(1) + _corner_pos(2) + _corner_pos(3)) / 4.0


## Cover-Viereck um seinen Mittelpunkt drehen. Gerechnet in MASTER-PIXELN (nicht
## im 0..1-Anteil), damit die Drehung bei nicht-quadratischem Master nicht schert.
func _rotate_quad(deg: float) -> void:
	if _master == null:
		return
	var ms := Vector2(_master.get_size())
	var px: Array = []
	for v: Vector2 in _quad:
		px.append(Vector2(v.x * ms.x, v.y * ms.y))
	var cen: Vector2 = (px[0] + px[1] + px[2] + px[3]) / 4.0
	var rad := deg_to_rad(deg)
	for i in 4:
		var d: Vector2 = (px[i] - cen).rotated(rad)
		_quad[i] = Vector2((cen.x + d.x) / ms.x, (cen.y + d.y) / ms.y)
	queue_redraw()


## Cover-Zuordnung der Ecken um 90° weiterdrehen (Hochformat ↔ Querformat), ohne
## die Viereck-Fläche zu ändern — rotiert nur, welche Ecke welche Cover-Ecke ist.
func _rotate_uv_90() -> void:
	_quad = [_quad[3], _quad[0], _quad[1], _quad[2]]
	queue_redraw()


# -------------------------------------------------------------------- Eingabe

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_compute_sprite_rect()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_drag_corner = _corner_at(event.position)
				if _drag_corner >= 0:
					accept_event()
					return
				if _sprite_rect.size.x > 1.0 and _inside_quad(event.position):
					_drag_all = true
					_grab = event.position - _quad_center_px()
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_panning = true
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, 0.89)
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag_corner = -1
			_drag_all = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			queue_redraw()
			return
		if _sprite_rect.size.x <= 1.0:
			return
		if _drag_corner >= 0:
			var frac: Vector2 = (event.position - _sprite_rect.position) / _sprite_rect.size
			_quad[_drag_corner] = Vector2(clampf(frac.x, -0.2, 1.2), clampf(frac.y, -0.2, 1.2))
			queue_redraw()
		elif _drag_all:
			var target: Vector2 = event.position - _grab
			var delta: Vector2 = (target - _quad_center_px()) / _sprite_rect.size
			for i in 4:
				_quad[i] = (_quad[i] as Vector2) + delta
			queue_redraw()


func _zoom_at(p: Vector2, factor: float) -> void:
	if _master == null:
		return
	_compute_sprite_rect()
	var frac: Vector2 = (p - _sprite_rect.position) / _sprite_rect.size
	_zoom = clampf(_zoom * factor, 0.5, 8.0)
	var ts := Vector2(_master.get_size())
	var s: float = minf(size.x * 0.62 / ts.x, size.y * 0.82 / ts.y) * _zoom
	var draw_size := ts * s
	_pan = p - (size - draw_size) * 0.5 - frac * draw_size
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F8:
			_save(); accept_event()
		KEY_S:
			if event.ctrl_pressed:
				_save(); accept_event()
		KEY_LEFT:
			if not _covers.is_empty():
				_cidx = wrapi(_cidx - 1, 0, _covers.size()); queue_redraw()
		KEY_RIGHT:
			if not _covers.is_empty():
				_cidx = wrapi(_cidx + 1, 0, _covers.size()); queue_redraw()
		KEY_G:
			_show_grid = not _show_grid; queue_redraw()
		KEY_Q:
			_rotate_quad(-1.0 if event.shift_pressed else -5.0)   # gegen Uhrzeigersinn
		KEY_E:
			_rotate_quad(1.0 if event.shift_pressed else 5.0)     # im Uhrzeigersinn
		KEY_T:
			_rotate_uv_90()                                       # Hoch- ↔ Querformat (90°)
		KEY_R:
			_quad = [Vector2(0.14, 0.06), Vector2(0.92, 0.16),
				Vector2(0.86, 0.95), Vector2(0.06, 0.83)]
			queue_redraw()


# ------------------------------------------------------------------- Zeichnen

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.11, 0.12, 0.15))
	_compute_sprite_rect()
	var font := ThemeDB.fallback_font
	if _master == null:
		draw_string(font, Vector2(24, 44), "Master fehlt: " + MASTER_PATH,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.RED)
		return
	# Karo-Hintergrund hinter dem (transparenten) Master
	_draw_checker()
	draw_texture_rect(_master, _sprite_rect, false)
	# Cover perspektivisch in die vier Ecken einpassen
	if not _covers.is_empty():
		_draw_cover_warped()
	# Quad-Umriss + Ecken
	var pts := PackedVector2Array([_corner_pos(0), _corner_pos(1), _corner_pos(2), _corner_pos(3)])
	for i in 4:
		draw_line(pts[i], pts[(i + 1) % 4], Color(0.3, 1.0, 0.5, 0.9), 2.0)
	const LABEL := ["TL", "TR", "BR", "BL"]
	for i in 4:
		var col: Color = Color(1.0, 0.7, 0.2) if i == _drag_corner else Color(0.3, 1.0, 0.5)
		draw_circle(pts[i], HANDLE, Color(0, 0, 0, 0.6))
		draw_circle(pts[i], HANDLE - 2.0, col)
		draw_string(font, pts[i] + Vector2(12, 4), LABEL[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	_draw_hud(font)


## Cover als zwei texturierte Dreiecke in das Quad (TL,TR,BR,BL) zeichnen.
func _draw_cover_warped() -> void:
	var tex: Texture2D = _covers[_cidx]["tex"]
	var p0 := _corner_pos(0)
	var p1 := _corner_pos(1)
	var p2 := _corner_pos(2)
	var p3 := _corner_pos(3)
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var pts := PackedVector2Array([p0, p1, p2, p3])
	# draw_polygon mit 4 Punkten + UVs (Godot trianguliert das Viereck)
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uv, tex)
	if _show_grid:
		# Hilfsgitter im Cover-Raum (bilinear) zur Feinjustage
		for k in range(1, 4):
			var t := float(k) / 4.0
			var a := p0.lerp(p3, t)
			var b := p1.lerp(p2, t)
			draw_line(a, b, Color(1, 1, 1, 0.25), 1.0)
			var c := p0.lerp(p1, t)
			var d := p3.lerp(p2, t)
			draw_line(c, d, Color(1, 1, 1, 0.25), 1.0)


func _draw_checker() -> void:
	var step := 16.0
	var y := _sprite_rect.position.y
	var row := 0
	while y < _sprite_rect.end.y:
		var x := _sprite_rect.position.x
		var col := row
		while x < _sprite_rect.end.x:
			var shade := 0.16 if (col % 2 == 0) else 0.22
			draw_rect(Rect2(x, y, minf(step, _sprite_rect.end.x - x), minf(step, _sprite_rect.end.y - y)),
				Color(shade, shade, shade + 0.02))
			x += step
			col += 1
		y += step
		row += 1


func _draw_hud(font: Font) -> void:
	var cover_id := "—" if _covers.is_empty() else str(_covers[_cidx]["id"])
	draw_rect(Rect2(0, 0, size.x, 30), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(16, 20),
		"MAGAZIN-EDITOR   Cover: %s  (%d/%d)   Ecke/Fläche ziehen · Q/E drehen (Shift fein) · T 90° Hoch/Quer · Mausrad Zoom · ←/→ Cover · G Gitter · R Reset · F8 speichern"
			% [cover_id, _cidx + 1, maxi(1, _covers.size())],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1.0))
	if _saved_flash > 0.0:
		draw_string(font, Vector2(16, size.y - 16),
			"✔ gespeichert → data/magazine_layout.json", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(0.3, 1.0, 0.5, _saved_flash))
