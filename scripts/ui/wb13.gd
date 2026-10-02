class_name Wb13
## Gemeinsamer Amiga-Workbench-Chromemaler. Der historische Klassenname bleibt
## fuer alte Szenen stabil; Farben und Gadgets folgen aber dem aktiven Profil:
## 1.3 ist flach und vierfarbig, 2.05/3.x nutzen die grauen 3D-Gadgets.
##
## Maler-Konvention wie UiPaint: statische Funktionen bekommen den CanvasItem
## und PHYSISCHE Rechtecke; `vy` ist die Höhe eines nativen Pixels (2 virtuelle
## Zeilen), `vx` die Breite. Topaz-Font (8×16) über font().

const FONT_PATH := "res://assets/fonts/Topaz_a500_ui.ttf"
const Versions := preload("res://scripts/ui/workbench_versions.gd")

# Original-Palette Workbench 1.3 (Farbe 0–3). "Schwarz" ist das dunkle
# Blauschwarz 0x000020 der echten Palette.
const DEF_BLUE := Color8(0, 85, 170)
const DEF_WHITE := Color8(255, 255, 255)
const DEF_BLACK := Color8(0, 0, 32)
const DEF_ORANGE := Color8(255, 136, 0)

static var _font: FontFile = null
static var _wave_tex: ImageTexture = null
static var _ghost_tex: ImageTexture = null
static var _session_colors: Array = []   # Preferences „Use“ ohne Speichern


## Palette-Farbe 0..3 (blau/weiß/schwarz/orange) — mit Preferences-Override.
static func col(i: int) -> Color:
	var cs := _session_colors
	if cs.is_empty():
		var saved: Variant = _saved_setting(Versions.settings_key())
		if saved is Array and (saved as Array).size() == 4:
			cs = saved
	if cs.size() == 4:
		return Color.html(str(cs[i]))
	var defaults := default_colors()
	return defaults[clampi(i, 0, 3)]


static func _saved_setting(key: String) -> Variant:
	# Wb13 wird auch von isolierten Vorschauen und Rendering-Tests geladen.
	# Dort kann der Settings-Autoload fehlen; die historische Standardpalette
	# ist dann der korrekte, deterministische Fallback.
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var settings := (loop as SceneTree).root.get_node_or_null("SettingsManager")
		if settings != null and settings.has_method("value"):
			return settings.call("value", key)
	return null


static func blue() -> Color: return col(0)
static func white() -> Color: return col(1)
static func black() -> Color: return col(2)
static func orange() -> Color: return col(3)


static func default_colors() -> Array:
	var values := Versions.palette()
	if values.size() != 4:
		return [DEF_BLUE, DEF_WHITE, DEF_BLACK, DEF_ORANGE]
	return values.map(func(value: Variant) -> Color: return Color.html(str(value)))


static func settings_key() -> String:
	return Versions.settings_key()


static func is_modern() -> bool:
	return Versions.is_modern()


## Sitzungs-Palette setzen ([] = zurück auf gespeicherte/Standard).
static func set_session_colors(cols: Array) -> void:
	_session_colors = cols
	_wave_tex = null
	_ghost_tex = null
	Wb13Icons.flush()


## Topaz 8×16 (TrueType-Nachbau, GPL+FE). Pixelig ohne Kantenglättung.
static func font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH)
		if _font != null:
			_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			_font.hinting = TextServer.HINTING_NONE
			_font.generate_mipmaps = false
	if _font == null:
		return ThemeDB.fallback_font
	return _font


## Fontgröße für „8×8-Zeichen“ im 640×400-Raster: 16 virtuelle Pixel hoch.
static func fsize(sy: float) -> int:
	return maxi(4, int(round(16.0 * sy)))


# ------------------------------------------------------------ Titelleisten

## Aktive Titelleiste: feine Linien über die Leistenhöhe verteilt (wie 1.3).
static func drag_stripes(ci: CanvasItem, r: Rect2, vy: float) -> void:
	if is_modern():
		ci.draw_rect(r, blue())
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, vy * 0.5))),
			white().darkened(0.05))
		ci.draw_rect(Rect2(r.position.x, r.end.y - maxf(1.0, vy * 0.5),
			r.size.x, maxf(1.0, vy * 0.5)), black())
		return
	var px := vy * 0.5   # 1 „Interlace-Zeile“
	for i in 6:
		ci.draw_rect(Rect2(r.position.x, r.position.y + (4.0 + i * 2.4) * px,
			r.size.x, maxf(1.0, px * 1.1)), black())


## Inaktive Titelleiste: Wellenmuster-Dither (das „wwww“ der 1.x-Fenster).
static func drag_wave(ci: CanvasItem, r: Rect2, vx: float, vy: float) -> void:
	if is_modern():
		ci.draw_rect(r, blue().darkened(0.35))
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, vy * 0.5))),
			white().darkened(0.25))
		ci.draw_rect(Rect2(r.position.x, r.end.y - maxf(1.0, vy * 0.5),
			r.size.x, maxf(1.0, vy * 0.5)), black())
		return
	if _wave_tex == null:
		_wave_tex = PixelArt.make_texture([
			"K...",
			".K.K",
			"..K.",
		], {"K": DEF_BLACK})
	var half := vy * 0.5
	var tile := Vector2(4.0 * vx, 3.0 * half)
	var x := r.position.x
	while x < r.end.x:
		var y := r.position.y + half * 3.0
		while y + tile.y <= r.end.y - half * 2.0:
			ci.draw_texture_rect(_wave_tex, Rect2(Vector2(x, y), Vector2(minf(tile.x, r.end.x - x), tile.y)), false, black())
			y += tile.y + half * 2.0
		x += tile.x


## Geist-Raster (ghosting) über ein Rechteck — nicht verfügbare Icons/Menüs.
static func ghost(ci: CanvasItem, r: Rect2, vx: float, vy: float, c := Color(1, 1, 1, 0)) -> void:
	if _ghost_tex == null:
		_ghost_tex = PixelArt.make_texture(["B.", ".B"], {"B": DEF_BLUE})
	var use := blue() if c.a == 0.0 else c
	var tile := Vector2(2.0 * vx, 2.0 * vy)
	var x := r.position.x
	while x < r.end.x:
		var y := r.position.y
		while y < r.end.y:
			ci.draw_texture_rect(_ghost_tex, Rect2(Vector2(x, y),
				Vector2(minf(tile.x, r.end.x - x), minf(tile.y, r.end.y - y))), false, use)
			y += tile.y
		x += tile.x


# ------------------------------------------------------------------ Gadgets

## Erhabene beziehungsweise gedrueckte Intuition-Gadgets ab Release 2.
static func bevel(ci: CanvasItem, r: Rect2, pressed := false, width := 2.0) -> void:
	var light := white()
	var dark := black()
	if pressed:
		var swap := light
		light = dark
		dark = swap
	var w := maxf(1.0, width)
	ci.draw_line(r.position, Vector2(r.end.x, r.position.y), light, w)
	ci.draw_line(r.position, Vector2(r.position.x, r.end.y), light, w)
	ci.draw_line(Vector2(r.position.x, r.end.y), r.end, dark, w)
	ci.draw_line(Vector2(r.end.x, r.position.y), r.end, dark, w)

## Schließ-Gadget (links in der Titelleiste): Kästchen mit Punkt.
static func gadget_close(ci: CanvasItem, r: Rect2, vx: float, vy: float) -> void:
	if is_modern():
		ci.draw_rect(r, blue())
		bevel(ci, r.grow(-maxf(1.0, vx)), false, maxf(1.0, vy * 0.5))
		var inner := r.grow(-minf(r.size.x, r.size.y) * 0.31)
		ci.draw_rect(inner, black(), false, maxf(1.0, vy * 0.55))
		return
	var px := vy * 0.5
	var lw := maxf(1.0, px * 1.1)
	ci.draw_rect(r, white())
	ci.draw_rect(Rect2(r.end.x - vx, r.position.y, vx, r.size.y), black())
	var box := Rect2(r.position + Vector2(5 * vx, 5 * px), Vector2(10 * vx, 10 * px))
	box.size.x = minf(box.size.x, r.size.x - 8 * vx)
	ci.draw_rect(box, black(), false, lw)
	ci.draw_rect(Rect2(box.get_center() - Vector2(1.5 * vx, 2 * px), Vector2(3 * vx, 4 * px)), black())


## Tiefen-Gadgets (rechts): „nach hinten“ (vorderes Quadrat gefüllt) und
## „nach vorn“ (weißes Quadrat vorn). is_front wählt die Variante.
static func gadget_depth(ci: CanvasItem, r: Rect2, vx: float, vy: float, is_front: bool) -> void:
	if is_modern():
		ci.draw_rect(r, blue())
		bevel(ci, r.grow(-maxf(1.0, vx)), false, maxf(1.0, vy * 0.5))
		var modern_back := Rect2(r.position + Vector2(5 * vx, 3 * vy),
			Vector2(10 * vx, 6 * vy))
		var modern_front := Rect2(r.position + Vector2(9 * vx, 6 * vy),
			Vector2(10 * vx, 6 * vy))
		ci.draw_rect(modern_back, black(), false, maxf(1.0, vy * 0.5))
		ci.draw_rect(modern_front, white() if is_front else blue())
		ci.draw_rect(modern_front, black(), false, maxf(1.0, vy * 0.5))
		return
	var px := vy * 0.5
	var lw := maxf(1.0, px * 1.1)
	ci.draw_rect(r, white())
	ci.draw_rect(Rect2(r.position.x, r.position.y, vx, r.size.y), black())
	var back := Rect2(r.position + Vector2(5 * vx, 3 * px), Vector2(10 * vx, 9 * px))
	var front := Rect2(r.position + Vector2(10 * vx, 8 * px), Vector2(10 * vx, 9 * px))
	if is_front:
		ci.draw_rect(back, black())
		ci.draw_rect(front, white())
		ci.draw_rect(front, black(), false, lw)
	else:
		ci.draw_rect(back, white())
		ci.draw_rect(back, black(), false, lw)
		ci.draw_rect(front, black())


## Pfeil-Gadget (Scrollleisten-Enden). dir: 0=↑ 1=↓ 2=← 3=→
static func gadget_arrow(ci: CanvasItem, r: Rect2, dir: int) -> void:
	ci.draw_rect(r, blue() if is_modern() else white())
	if is_modern():
		bevel(ci, r.grow(-1.0), false, 1.0)
	var c := r.get_center()
	var a := minf(r.size.x, r.size.y) * 0.30
	var pts: PackedVector2Array
	match dir:
		0: pts = PackedVector2Array([c + Vector2(0, -a * 1.2), c + Vector2(-a, 0.2 * a), c + Vector2(a, 0.2 * a)])
		1: pts = PackedVector2Array([c + Vector2(0, a * 1.2), c + Vector2(-a, -0.2 * a), c + Vector2(a, -0.2 * a)])
		2: pts = PackedVector2Array([c + Vector2(-a * 1.4, 0), c + Vector2(0.3 * a, -a), c + Vector2(0.3 * a, a)])
		_: pts = PackedVector2Array([c + Vector2(a * 1.4, 0), c + Vector2(-0.3 * a, -a), c + Vector2(-0.3 * a, a)])
	ci.draw_colored_polygon(pts, black())
	# Stiel
	if dir <= 1:
		ci.draw_rect(Rect2(c.x - a * 0.25, c.y + (0.1 * a if dir == 0 else -a * 1.1), a * 0.5, a), black())
	else:
		ci.draw_rect(Rect2(c.x + (0.0 if dir == 2 else -a), c.y - a * 0.25, a, a * 0.5), black())


## Größen-Gadget (unten rechts): kleines über großem Kästchen.
static func gadget_size(ci: CanvasItem, r: Rect2, vx: float, vy: float) -> void:
	ci.draw_rect(r, blue() if is_modern() else white())
	if is_modern():
		bevel(ci, r.grow(-1.0), false, maxf(1.0, vy * 0.45))
	var lw := maxf(1.0, vy * 0.6)
	ci.draw_rect(Rect2(r.position + Vector2(2 * vx, 1.2 * vy), Vector2(r.size.x * 0.35, r.size.y * 0.35)), black(), false, lw)
	ci.draw_rect(Rect2(r.position + Vector2(2 * vx + r.size.x * 0.2, 1.2 * vy + r.size.y * 0.25),
		Vector2(r.size.x * 0.5, r.size.y * 0.5)), black(), false, lw)


## Scroll-Trog + Knopf (vertikal oder horizontal), frac0..frac1 = Knopfbereich.
static func scrollbar(ci: CanvasItem, r: Rect2, vertical: bool, frac0: float, frac1: float, vy: float) -> void:
	ci.draw_rect(r, blue().darkened(0.18) if is_modern() else white())
	var lw := maxf(1.0, vy * 0.6)
	ci.draw_rect(r, black(), false, lw)
	var knob := r
	if vertical:
		knob.position.y = r.position.y + r.size.y * frac0
		knob.size.y = maxf(4.0, r.size.y * (frac1 - frac0))
	else:
		knob.position.x = r.position.x + r.size.x * frac0
		knob.size.x = maxf(4.0, r.size.x * (frac1 - frac0))
	knob = knob.grow(-lw * 2.0)
	ci.draw_rect(knob, blue() if is_modern() else white())
	ci.draw_rect(knob, black(), false, lw)
	if is_modern():
		bevel(ci, knob, false, lw)


## Füllstands-Tank (linker Rand der Disk-Fenster): F oben, E unten, orange Füllung.
static func fuel_gauge(ci: CanvasItem, r: Rect2, fill: float, vx: float, vy: float, sy: float) -> void:
	ci.draw_rect(r, white())
	var lw := maxf(1.0, vy * 0.6)
	var fh := 10.0 * vy
	var f := Wb13.font()
	var fs := fsize(sy)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, fh)), black())
	ci.draw_string(f, Vector2(r.position.x + 2 * vx, r.position.y + fh - 2 * vy), "F",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white())
	ci.draw_rect(Rect2(r.position.x, r.end.y - fh, r.size.x, fh), black())
	ci.draw_string(f, Vector2(r.position.x + 2 * vx, r.end.y - 2 * vy), "E",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white())
	var trough := Rect2(r.position.x + vx, r.position.y + fh + vy, r.size.x - 2 * vx, r.size.y - 2 * fh - 2 * vy)
	ci.draw_rect(trough, black(), false, lw)
	if fill > 0.0:
		ci.draw_rect(Rect2(trough.position, Vector2(trough.size.x, trough.size.y * clampf(fill, 0.0, 1.0))).grow(-lw), orange())
