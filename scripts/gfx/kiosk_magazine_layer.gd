class_name KioskMagazineLayer
extends Control
## Aufrecht stehende Magazine im Kiosk. Rendert die in data/kiosk_magazines.json
## platzierten Hefte mit dem Cover der AKTUELLEN Ausgabe (nach Spielmonat) — das
## Cover wird auf das aufrechte Master-Asset gebacken (MagazineComposer).
##
## Zwei Betriebsarten:
##  • In-Game (edit_mode=false): nur Anzeige, keine Maus.
##  • Editor (edit_mode=true): „+ Magazin"-Knopf platziert Hefte, ziehen =
##    verschieben, Mausrad = Größe, Entf/Rechtsklick = löschen, F8 = speichern.
##
## Positionen in VIRTUELLEN Kiosk-Pixeln (location.virtual_size, aktuell 1672×941),
## x/y = Mittelpunkt, w = Breite. `location` liefert die Virtuell→Bildschirm-
## Abbildung (vrect), damit die Hefte exakt zum Kiosk-Hintergrund passen.

const DATA_PATH := "res://data/kiosk_magazines.json"
const SHELF_FRAME_PATH := "res://assets/backgrounds/layers/KIOSK_MAGAZINE_SHELF_FRAME_V01.png"
## Ausschnitt des generierten Vollbild-Assets, der wirklich Metall enthaelt.
## Das Ziel liegt in denselben virtuellen 1672x941-Koordinaten wie die Hefte.
const SHELF_FRAME_SOURCE := Rect2(64.0, 486.0, 1170.0, 332.0)
const SHELF_FRAME_VRECT := Rect2(276.0, 582.0, 824.0, 276.0)

var location: LocationBase             # für vrect / virtual_size
var edit_mode := false

var _entries: Array = []               # [{x, y, w}]  (virtuelle Pixel)
var _tex: Texture2D                     # fertiges aufrechtes Heft (Cover gebacken)
var _frame_tex: Texture2D               # Regalfront mit echten Alpha-Oeffnungen
var _frame_visible := true
var _sel := -1
var _drag := false
var _resize := -1                       # gezogene Ecke 0..3 (-1 = keine)
var _grab := Vector2.ZERO              # Offset Maus→Mittelpunkt (virtuell)
var _last_w := 150.0                    # zuletzt benutzte Breite (für neue Hefte)
var _add_btn: Button
var _frame_btn: Button
var _saved_flash := 0.0
var _last_depth_offset := Vector2(INF, INF)
const HANDLE := 9.0                     # Griffgröße (Bildschirm-Pixel)


func _ready() -> void:
	# Zur Laufzeit in einen Nicht-Container gehängt → Größe explizit nachführen,
	# sonst 0×0 und keine Klicks (Falle wie beim Hotspot-Editor).
	_fit_parent()
	var p := get_parent()
	if p is Control:
		(p as Control).resized.connect(_fit_parent)
	mouse_filter = Control.MOUSE_FILTER_STOP if edit_mode else Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # gegen Alias beim Verkleinern
	z_index = 30
	_load()
	_frame_tex = load(SHELF_FRAME_PATH) as Texture2D
	_bake_cover()
	set_process(true)
	if edit_mode:
		_build_add_button()


func _fit_parent() -> void:
	var p := get_parent()
	if p is Control:
		position = Vector2.ZERO
		size = (p as Control).size
	queue_redraw()


func _process(delta: float) -> void:
	var depth_offset := _depth_offset(_frame_screen_without_depth().get_center())
	if depth_offset.distance_to(_last_depth_offset) > 0.05:
		_last_depth_offset = depth_offset
		queue_redraw()
	if _saved_flash > 0.0:
		_saved_flash = maxf(0.0, _saved_flash - delta)
		queue_redraw()


func _bake_cover() -> void:
	var cover := MagazineComposer.cover_for_month(int(TimeManager.month))
	MagazineComposer.compose_upright(self, cover, func(tex: Texture2D) -> void:
		_tex = tex
		queue_redraw())


# ----------------------------------------------------------------- Daten

func _load() -> void:
	_entries = []
	if not FileAccess.file_exists(DATA_PATH):
		return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(p) == TYPE_DICTIONARY and (p as Dictionary).has("magazines"):
		var fallback_center := location.virtual_size * 0.5 if location != null \
			else Vector2(836.0, 470.5)
		for m: Variant in (p as Dictionary)["magazines"]:
			if m is Dictionary:
				_entries.append({"x": float(m.get("x", fallback_center.x)), "y": float(m.get("y", fallback_center.y)),
					"w": float(m.get("w", 150.0))})


func _save() -> void:
	var mags: Array = []
	for e in _entries:
		mags.append({"x": roundi(e["x"]), "y": roundi(e["y"]), "w": roundi(e["w"])})
	var data := {
		"comment": "Aufrecht stehende Magazine im Kiosk (Editor scenes/KioskMagEditor.tscn). "
			+ "Virtuelle Kiosk-Pixel, x/y = Mittelpunkt, w = Breite. Cover je nach Spielmonat.",
		"magazines": mags,
	}
	var f := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t", false))
	_saved_flash = 1.4


# ------------------------------------------------------------ Geometrie

## Virtuelles Rechteck eines Hefts (Mittelpunkt x/y, Breite w, Höhe aus Seitenverh.).
func _mag_vrect(e: Dictionary) -> Rect2:
	var ar := 1.34   # Fallback-Seitenverhältnis (Höhe/Breite)
	if _tex != null and _tex.get_size().x > 0.0:
		ar = _tex.get_size().y / _tex.get_size().x
	var w: float = e["w"]
	var h := w * ar
	return Rect2(float(e["x"]) - w * 0.5, float(e["y"]) - h * 0.5, w, h)


## Bildschirm-Rechteck eines Hefts.
func _mag_screen(e: Dictionary) -> Rect2:
	if location != null:
		return _with_depth(location.vrect(_mag_vrect(e)))
	return _mag_vrect(e)


func _with_depth(rect: Rect2) -> Rect2:
	rect.position += _depth_offset(rect.get_center())
	return rect


func _depth_offset(screen_point: Vector2) -> Vector2:
	if location == null:
		return Vector2.ZERO
	var stage := location.depth_stage_25d()
	if stage != null and is_instance_valid(stage) and stage.has_method("offset_for_point"):
		return Vector2(stage.call("offset_for_point", screen_point))
	return Vector2.ZERO


func _frame_screen_without_depth() -> Rect2:
	return location.vrect(SHELF_FRAME_VRECT) if location != null else SHELF_FRAME_VRECT


func _frame_screen() -> Rect2:
	return _with_depth(_frame_screen_without_depth())


# ------------------------------------------------------------------- Zeichnen

func _draw() -> void:
	# 1. Regalhintergrund ist Teil des Location-Masters.
	# 2. Dynamische Hefte liegen davor.
	for i in _entries.size():
		var r := _mag_screen(_entries[i])
		if _tex != null:
			draw_texture_rect(_tex, r, false)
		else:
			# Platzhalter, solange der Cover-Bake noch läuft
			draw_rect(r, Color(0.9, 0.9, 0.86, 0.9))
			draw_rect(r, Color(0.4, 0.4, 0.4), false, 2.0)
	# 3. Die echte Regalfront liegt VOR den Heften. Die Alpha-Oeffnungen lassen
	#    die Cover sichtbar; nur Metallkanten und schmale Stege verdecken sie.
	if _frame_visible and _frame_tex != null:
		draw_texture_rect_region(_frame_tex, _frame_screen(), SHELF_FRAME_SOURCE,
			Color.WHITE, false, true)
	# 4. Editor-Auswahl zuletzt: Rahmen darf Griffe und Feedback nie verdecken.
	if edit_mode and _sel >= 0 and _sel < _entries.size():
		var r := _mag_screen(_entries[_sel])
		if r.size.x > 0.0 and r.size.y > 0.0:
			draw_rect(r, Color(1.0, 0.7, 0.2), false, 3.0)
			for c: Vector2 in _corners(r):
				draw_rect(Rect2(c - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)),
					Color(1.0, 0.7, 0.2))
				draw_rect(Rect2(c - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)),
					Color.BLACK, false, 1.0)
	if edit_mode:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(16, size.y - 40),
			"KIOSK-MAGAZINE: + platzieren · ziehen = verschieben · Ecken/Mausrad = Größe · F = Regalfront · Entf = löschen · F8 = speichern (%d Hefte)" % _entries.size(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.9, 1.0))
		if _saved_flash > 0.0:
			draw_string(font, Vector2(16, size.y - 18), "✔ gespeichert → data/kiosk_magazines.json",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.3, 1.0, 0.5, _saved_flash))


# -------------------------------------------------------------------- Editor

func _build_add_button() -> void:
	_add_btn = Button.new()
	_add_btn.text = Loc.t("misc.kiosk_magazine_layer.magazin_platzieren", "+ Magazin platzieren")
	_add_btn.position = Vector2(16, 16)
	_add_btn.focus_mode = Control.FOCUS_NONE
	_add_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_add_btn.pressed.connect(_add_magazine)
	add_child(_add_btn)
	_frame_btn = Button.new()
	_frame_btn.text = Loc.t("misc.kiosk_magazine_layer.regalfront_an", "Regalfront: AN")
	_frame_btn.position = Vector2(190, 16)
	_frame_btn.focus_mode = Control.FOCUS_NONE
	_frame_btn.tooltip_text = Loc.t("misc.kiosk_magazine_layer.vorderes_metall_ausblenden_um_verdeckte_cover", "Vorderes Metall ein-/ausblenden, um verdeckte Cover bequem auszurichten")
	_frame_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_frame_btn.pressed.connect(_toggle_frame)
	add_child(_frame_btn)


func _toggle_frame() -> void:
	_frame_visible = not _frame_visible
	if _frame_btn != null:
		_frame_btn.text = Loc.t("misc.kiosk_magazine_layer.regalfront_s",
			"Regalfront: %s") % (
				Loc.t("ui.common.on", "AN") if _frame_visible
				else Loc.t("ui.common.off", "AUS"))
	queue_redraw()


func _add_magazine() -> void:
	# neues Heft in die Mitte des sichtbaren Kiosk-Raums, in der ZULETZT
	# benutzten Größe (so bleibt die Bestückung gleichmäßig).
	var vs := location.virtual_size if location != null else Vector2(1920, 1080)
	_entries.append({"x": vs.x * 0.5, "y": vs.y * 0.5, "w": _last_w})
	_sel = _entries.size() - 1
	queue_redraw()


## Vier Eck-Griffe eines Bildschirm-Rechtecks (TL,TR,SW? → TL,TR,BR,BL Reihenfolge).
func _corners(r: Rect2) -> Array:
	return [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]


## Ecke der AUSGEWÄHLTEN Karte unter dem Bildschirmpunkt (-1 = keine).
func _corner_at(screen: Vector2) -> int:
	if _sel < 0 or _sel >= _entries.size():
		return -1
	var cs := _corners(_mag_screen(_entries[_sel]))
	for i in 4:
		if (cs[i] as Vector2).distance_to(screen) <= HANDLE + 3.0:
			return i
	return -1


func _to_virtual(screen: Vector2) -> Vector2:
	if location == null:
		return screen
	# Naeherungsweise Umkehrung derselben Tiefenprojektion, die beim Zeichnen
	# benutzt wird. Verhindert den kleinen Sprung beim ersten Drag-Frame.
	var unprojected := screen - _depth_offset(screen)
	return location.to_virtual(unprojected)


func _gui_input(event: InputEvent) -> void:
	if not edit_mode:
		return
	if event is InputEventMouseButton:
		var pos: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Erst prüfen, ob ein ECK-GRIFF der Auswahl gepackt wird (Größe).
				_resize = _corner_at(pos)
				if _resize >= 0:
					_drag = false
				else:
					_sel = _pick(pos)
					if _sel >= 0:
						_drag = true
						_grab = _to_virtual(pos) - Vector2(_entries[_sel]["x"], _entries[_sel]["y"])
				queue_redraw()
			else:
				_drag = false
				_resize = -1
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var hit := _pick(pos)
			if hit >= 0:
				_entries.remove_at(hit)
				_sel = -1
				queue_redraw()
		elif event.pressed and _sel >= 0 and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_w(_sel, float(_entries[_sel]["w"]) * 1.08)
		elif event.pressed and _sel >= 0 and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_w(_sel, float(_entries[_sel]["w"]) / 1.08)
	elif event is InputEventMouseMotion:
		if _resize >= 0 and _sel >= 0:
			# Proportional um den Mittelpunkt skalieren: neue Breite aus dem Abstand
			# Maus↔Mittelpunkt (Seitenverhältnis des Hefts bleibt erhalten).
			var e: Dictionary = _entries[_sel]
			var cen := Vector2(float(e["x"]), float(e["y"]))
			var d := (_to_virtual(event.position) - cen).abs()   # halbe Ausdehnung
			var ar := 1.34
			if _tex != null and _tex.get_size().x > 0.0:
				ar = _tex.get_size().y / _tex.get_size().x
			# Breite so, dass die gezogene Ecke die Maus erreicht (dominante Achse).
			_set_w(_sel, maxf(d.x * 2.0, d.y * 2.0 / ar))
		elif _drag and _sel >= 0:
			var v := _to_virtual(event.position) - _grab
			_entries[_sel]["x"] = v.x
			_entries[_sel]["y"] = v.y
			queue_redraw()


## Breite eines Hefts setzen (geklemmt) und als „letzte Größe" merken.
func _set_w(i: int, w: float) -> void:
	_entries[i]["w"] = clampf(w, 30.0, 900.0)
	_last_w = float(_entries[i]["w"])
	queue_redraw()


## Oberstes Heft unter dem Bildschirmpunkt (höchster Index zuerst).
func _pick(screen: Vector2) -> int:
	for i in range(_entries.size() - 1, -1, -1):
		if _mag_screen(_entries[i]).has_point(screen):
			return i
	return -1


func _unhandled_key_input(event: InputEvent) -> void:
	if not edit_mode or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F8:
			_save(); accept_event()
		KEY_S:
			if event.ctrl_pressed:
				_save(); accept_event()
		KEY_F:
			_toggle_frame(); accept_event()
		KEY_DELETE, KEY_BACKSPACE:
			if _sel >= 0:
				_entries.remove_at(_sel); _sel = -1; queue_redraw(); accept_event()
