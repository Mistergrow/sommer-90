class_name Wb13Window
extends Control
## Fenster der WERKBANK 1.3 — Chrome pixelgenau nach Workbench 1.3: Schließ-
## Gadget links, Titel + Drag-Muster (aktiv: Doppellinien, inaktiv: Welle),
## Tiefen-Gadgets rechts, Scrollleisten mit Pfeilen, Größen-Gadget, optional
## Füllstands-Tank am linken Rand (Disk-Fenster). Lebt als Kind des Desktops
## (WerkbankScreen) und rechnet in dessen virtuellem 640×400-Raster.
##
## Standard-Inhalt: Icon-Raster (set_icons) mit Auswahl/Doppelklick wie damals.
## Unterklassen (Clock, Calculator, Shell) überschreiben _content_draw/_input.

const TB := 20.0      # Titelleiste (virtuell; 10 native Zeilen)
const BW := 6.0       # schmale Ränder
const GAUGE_W := 22.0 # linker Rand mit Tank
const SCROLL_W := 18.0
const BOTTOM_H := 16.0

var vrect := Rect2(60, 40, 380, 220)   # Fensterlage im 640×400-Raster
var title := "Fenster"
var gauge_fill := -1.0                 # ≥0 → Tank am linken Rand
var closable := true
var resizable := true
var active := false
var on_close: Callable = Callable()

var icons: Array = []                  # {id,label,kind,cb,ghost}
var scroll_y := 0.0                    # virtueller Inhalts-Scroll
var _content_h := 0.0
var _drag_mode := ""                   # "move" | "size" | "vscroll"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func desktop() -> WerkbankScreen:
	var n: Node = get_parent()
	while n != null and not (n is WerkbankScreen):
		n = n.get_parent()
	return n


func set_icons(list: Array) -> void:
	icons = list
	_layout_icons()
	queue_redraw()


# ------------------------------------------------------------------ Geometrie

func _sx() -> float:
	var d := desktop()
	var virtual_size: Vector2 = d.virtual_size() if d != null else Vector2(640.0, 400.0)
	return d.size.x / maxf(1.0, virtual_size.x) if d != null else 1.0


func _sy() -> float:
	var d := desktop()
	var virtual_size: Vector2 = d.virtual_size() if d != null else Vector2(640.0, 400.0)
	return d.size.y / maxf(1.0, virtual_size.y) if d != null else 1.0


## Layout nachführen (vom Desktop bei Resize aufgerufen).
func sync_layout() -> void:
	position = Vector2(vrect.position.x * _sx(), vrect.position.y * _sy())
	size = Vector2(vrect.size.x * _sx(), vrect.size.y * _sy())
	_layout_icons()
	queue_redraw()


func _left_w() -> float:
	return GAUGE_W if gauge_fill >= 0.0 else BW


## Inhaltsbereich in virtuellen Fensterkoordinaten.
func content_rect() -> Rect2:
	return Rect2(_left_w(), TB, vrect.size.x - _left_w() - SCROLL_W, vrect.size.y - TB - BOTTOM_H)


func _layout_icons() -> void:
	var cr := content_rect()
	var x := 14.0
	var y := 10.0
	var row_h := 0.0
	for ic in icons:
		var isz: Vector2i = Wb13Icons.icon_size(ic["kind"])
		# Zelle mindestens so breit wie das Label (Topaz: 8 px pro Zeichen)
		var cell_w := maxf(maxf(76.0, isz.x + 34.0), str(ic.get("label", "")).length() * 8.0 + 10.0)
		var cell_h := isz.y * 2.0 + 26.0
		if x + cell_w > cr.size.x and x > 15.0:
			x = 14.0
			y += row_h + 8.0
			row_h = 0.0
		ic["cell"] = Rect2(x, y, cell_w, cell_h)
		row_h = maxf(row_h, cell_h)
		x += cell_w + 6.0
	_content_h = y + row_h + 10.0
	scroll_y = clampf(scroll_y, 0.0, maxf(0.0, _content_h - cr.size.y))


# ------------------------------------------------------------------- Zeichnen

func _draw() -> void:
	var sx := _sx()
	var sy := _sy()
	var vx := sx
	var vy := sy * 2.0
	var fs := Wb13.fsize(sy)
	var font := Wb13.font()
	var w := vrect.size.x
	var h := vrect.size.y
	var lw := maxf(1.0, vy * 0.5)

	# Rahmen + Innenfläche
	draw_rect(Rect2(0, 0, w * sx, h * sy), Wb13.white())
	draw_rect(Rect2(Vector2.ZERO, Vector2(w * sx, h * sy)), Wb13.black(), false, lw)
	var cr := content_rect()
	var crp := Rect2(cr.position.x * sx, cr.position.y * sy, cr.size.x * sx, cr.size.y * sy)
	draw_rect(crp, Wb13.blue())

	# Titelleiste
	var bar := Rect2(0, 0, w * sx, TB * sy)
	draw_rect(bar, Wb13.white())
	var tx := 6.0
	if closable:
		Wb13.gadget_close(self, Rect2(0, 0, 20 * sx, TB * sy), vx, vy)
		tx = 26.0
	var ts := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(tx * sx, (TB - 4.0) * sy), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.black())
	var pat := Rect2((tx + 4) * sx + ts.x, 0, (w - 52 - tx) * sx - ts.x, TB * sy)
	if pat.size.x > 8.0:
		if active:
			Wb13.drag_stripes(self, pat, vy)
		else:
			Wb13.drag_wave(self, pat, vx, vy)
	Wb13.gadget_depth(self, Rect2((w - 52) * sx, 0, 26 * sx, TB * sy), vx, vy, false)
	Wb13.gadget_depth(self, Rect2((w - 26) * sx, 0, 26 * sx, TB * sy), vx, vy, true)
	draw_rect(Rect2(0, TB * sy - lw, w * sx, lw), Wb13.black())

	# Tank links
	if gauge_fill >= 0.0:
		Wb13.fuel_gauge(self, Rect2(0, TB * sy, GAUGE_W * sx, (h - TB - BOTTOM_H) * sy),
			gauge_fill, vx, vy, sy)
	# rechte Leiste: ↑, Trog, ↓, darunter Größen-Gadget
	var rx := (w - SCROLL_W) * sx
	var arrow_h := 16.0 * sy
	Wb13.gadget_arrow(self, Rect2(rx, TB * sy, SCROLL_W * sx, arrow_h), 0)
	var trough := Rect2(rx, TB * sy + arrow_h, SCROLL_W * sx, (h - TB - BOTTOM_H) * sy - arrow_h * 2.0)
	var view_h := cr.size.y
	var f0 := 0.0
	var f1 := 1.0
	if _content_h > view_h:
		f0 = scroll_y / _content_h
		f1 = (scroll_y + view_h) / _content_h
	Wb13.scrollbar(self, trough, true, f0, f1, vy)
	Wb13.gadget_arrow(self, Rect2(rx, TB * sy + arrow_h + trough.size.y, SCROLL_W * sx, arrow_h), 1)
	# untere Leiste: ←, Trog, →
	var by := (h - BOTTOM_H) * sy
	var bx0 := _left_w() * sx
	Wb13.gadget_arrow(self, Rect2(0, by, 20 * sx, BOTTOM_H * sy), 2)
	Wb13.scrollbar(self, Rect2(20 * sx, by, (w - SCROLL_W - 40) * sx, BOTTOM_H * sy), false, 0.0, 1.0, vy)
	Wb13.gadget_arrow(self, Rect2((w - SCROLL_W - 20) * sx, by, 20 * sx, BOTTOM_H * sy), 3)
	if resizable:
		Wb13.gadget_size(self, Rect2(rx, by, SCROLL_W * sx, BOTTOM_H * sy), vx, vy)
	else:
		draw_rect(Rect2(rx, by, SCROLL_W * sx, BOTTOM_H * sy), Wb13.white())
	if bx0 > 0.0:
		pass  # linker Rand unter dem Tank ist schon weiß

	# Inhalt (geclippt aufs Innenrechteck)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_icons(crp, sx, sy, fs, font)
	_content_draw(crp, sx, sy)


func _draw_icons(crp: Rect2, sx: float, sy: float, fs: int, font: Font) -> void:
	if icons.is_empty():
		return
	var d := desktop()
	for ic in icons:
		var cell: Rect2 = ic["cell"]
		var isz: Vector2i = Wb13Icons.icon_size(ic["kind"])
		var pos := crp.position + Vector2(cell.position.x * sx, (cell.position.y - scroll_y) * sy)
		var cell_screen_rect := Rect2(pos, Vector2(cell.size.x * sx, cell.size.y * sy))
		if not cell_screen_rect.intersects(crp):
			continue
		var selected: bool = d != null and d.is_selected(self, str(ic["id"]))
		var t := Wb13Icons.tex(ic["kind"], selected)
		var ir := Rect2(pos + Vector2((cell.size.x - isz.x) * 0.5 * sx, 2.0 * sy),
			Vector2(isz.x * sx, isz.y * 2.0 * sy))
		_draw_texture_clipped(t, ir, crp)
		if bool(ic.get("ghost", false)):
			var ghost_rect := ir.intersection(crp)
			if ghost_rect.has_area():
				Wb13.ghost(self, ghost_rect, sx, sy * 2.0)
		var label_baseline := pos.y + (isz.y * 2.0 + 18.0) * sy
		# CanvasItem besitzt keinen beliebigen Scissor-Stack fuer einzelne
		# Draw-Aufrufe. Eine angebrochene Rasterzeile zeigt ihr Label daher erst,
		# wenn es vollstaendig oberhalb der unteren Fensterleiste liegt.
		if label_baseline - fs >= crp.position.y and label_baseline <= crp.end.y:
			draw_string(font, Vector2(pos.x, label_baseline), str(ic["label"]),
				HORIZONTAL_ALIGNMENT_CENTER, cell.size.x * sx, fs, Wb13.white())


## Schneidet Icontexturen am blauen Schubladeninhalt ab. Ohne diesen expliziten
## Ausschnitt wurden teilweise sichtbare letzte Rasterzeilen nach dem Chrome
## gezeichnet und lagen dadurch auf der horizontalen Scrollleiste.
func _draw_texture_clipped(texture: Texture2D, target: Rect2, clip_rect: Rect2) -> void:
	var clipped := target.intersection(clip_rect)
	if not clipped.has_area() or target.size.x <= 0.0 or target.size.y <= 0.0:
		return
	var texture_size := Vector2(texture.get_width(), texture.get_height())
	var source_position := (clipped.position - target.position) / target.size * texture_size
	var source_size := clipped.size / target.size * texture_size
	draw_texture_rect_region(texture, clipped, Rect2(source_position, source_size))


# -------------------------------------------------------------------- Eingabe

func _gui_input(event: InputEvent) -> void:
	var sx := _sx()
	var sy := _sy()
	if event is InputEventMouseButton:
		var v := Vector2(event.position.x / sx, event.position.y / sy)  # virtuell
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			var d := desktop()
			if d != null:
				d.activate(self)
			_on_press(v, event.double_click)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_drag_mode = ""
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_scroll_by(-24.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_scroll_by(24.0)
	elif event is InputEventMouseMotion and _drag_mode != "":
		var dv := Vector2(event.relative.x / sx, event.relative.y / sy)
		var desk := desktop()
		var virtual_size: Vector2 = desk.virtual_size() if desk != null \
			else Vector2(640.0, 400.0)
		match _drag_mode:
			"move":
				vrect.position += dv
				vrect.position.x = clampf(vrect.position.x, -vrect.size.x + 60.0,
					virtual_size.x - 20.0)
				vrect.position.y = clampf(vrect.position.y, 20.0,
					virtual_size.y - 20.0)
			"size":
				vrect.size.x = clampf(vrect.size.x + dv.x, 150.0, virtual_size.x)
				vrect.size.y = clampf(vrect.size.y + dv.y, 90.0,
					virtual_size.y - 20.0)
			"vscroll":
				if _content_h > 0.0:
					_scroll_by(dv.y * _content_h / maxf(1.0, vrect.size.y - TB - BOTTOM_H))
		sync_layout()


func _on_press(v: Vector2, dbl: bool) -> void:
	var w := vrect.size.x
	var h := vrect.size.y
	# Titelleiste
	if v.y < TB:
		if closable and v.x < 20.0:
			close_window()
		elif v.x >= w - 52.0 and v.x < w - 26.0:
			get_parent().move_child(self, 0)          # nach hinten
			var d := desktop()
			if d != null:
				d.refresh_active()
		elif v.x >= w - 26.0:
			get_parent().move_child(self, -1)         # nach vorn
		else:
			_drag_mode = "move"
		return
	# rechte Leiste
	if v.x >= w - SCROLL_W:
		if v.y >= h - BOTTOM_H:
			if resizable:
				_drag_mode = "size"
		elif v.y < TB + 16.0:
			_scroll_by(-40.0)
		elif v.y >= h - BOTTOM_H - 16.0:
			_scroll_by(40.0)
		else:
			_drag_mode = "vscroll"
		return
	if v.y >= h - BOTTOM_H:
		return
	# Icon-Klick
	var cr := content_rect()
	var local := Vector2(v.x - cr.position.x, v.y - cr.position.y + scroll_y)
	for ic in icons:
		if (ic["cell"] as Rect2).has_point(local):
			var d := desktop()
			if d != null:
				d.select(self, str(ic["id"]))
			if dbl:
				launch_icon(ic)
			return
	var dd := desktop()
	if dd != null:
		dd.select(null, "")
	_content_press(local, dbl)


func launch_icon(ic: Dictionary) -> void:
	if bool(ic.get("ghost", false)):
		UIManager.toast(Loc.t("ui.wb13_window.s_ist_nicht_angeschlossen_verfugbar", "„%s“ ist nicht angeschlossen/verfügbar.") % ic["label"])
		return
	# Ganz selten stürzt ein Programmstart ab — so war das damals (Neustart
	# kostet nur die Boot-Sequenz).
	if bool(ic.get("prog", false)) and randf() < 0.02:
		UIManager.show_guru()
		return
	var cb: Callable = ic.get("cb", Callable())
	if cb.is_valid():
		cb.call()


## Icon-Dictionary zur aktuellen Auswahl (fürs Menü „Open“).
func icon_by_id(id: String) -> Dictionary:
	for ic in icons:
		if str(ic["id"]) == id:
			return ic
	return {}


func _scroll_by(dy: float) -> void:
	scroll_y = clampf(scroll_y + dy, 0.0, maxf(0.0, _content_h - content_rect().size.y))
	queue_redraw()


func close_window() -> void:
	if on_close.is_valid():
		on_close.call()
	var d := desktop()
	queue_free()
	if d != null:
		d.refresh_active.call_deferred()


# ------------------------------------------------- Hooks für Unterklassen

## Eigener Inhalt (physisches Innenrechteck + Skalen).
func _content_draw(_crp: Rect2, _sx2: float, _sy2: float) -> void:
	pass


## Klick in den Inhalt (virtuelle Inhaltskoordinaten inkl. Scroll).
func _content_press(_v: Vector2, _dbl: bool) -> void:
	pass
