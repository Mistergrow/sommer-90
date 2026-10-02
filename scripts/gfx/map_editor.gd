extends Control
## Map-Editor — markiert PIXELGENAU, wo jeder Ort auf der Stadtkarte sitzt (wie der
## Zimmer-/Disk-Editor). Lädt das Karten-Asset (meta.map_art_path aus town.json),
## zeigt pro Ort einen ziehbaren Pin und speichert die Position als Anteil 0..1
## (`map_pos`) zurück in data/town.json — Single Source. Läuft auch OHNE Asset
## (Raster-Platzhalter), damit du sofort loslegen kannst; sobald das PNG da ist,
## erscheint es automatisch.
##
## Öffnen: scenes/MapEditor.tscn im Godot-Editor abspielen.
## Steuerung: Pin ziehen = verschieben · Klick = auswählen · Mausrad = Zoom ·
## mittlere Maustaste = schwenken · Tab/→ nächster · ← vorheriger ·
## H = geplante Orte ein/aus · R = auf Raster zurück · S = speichern.

const TOWN_PATH := "res://data/town.json"
const HANDLE := 7.0
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")

## Wegpunkt-Ebenen: eigenes Netz je Verkehrsmittel (Fuß ≠ Rad ≠ zwei Buslinien),
## plus "all" (gilt für alle — geteilte Straßen). Kanten tragen ihre Ebene, Farben
## unterscheiden sie im Editor. Zwei Buslinien: BUS 1 (orange), BUS 2 (pink).
const LAYERS := ["all", "foot", "bike", "bus1", "bus2"]
const LAYER_NAME := {"all": "ALLE", "foot": "FUSS", "bike": "RAD", "bus1": "BUS 1", "bus2": "BUS 2"}
const LAYER_COL := {
	"all": Color(0.78, 0.80, 0.88),
	"foot": Color(0.45, 0.95, 0.55),
	"bike": Color(0.40, 0.72, 1.00),
	"bus1": Color(1.00, 0.66, 0.22),
	"bus2": Color(1.00, 0.42, 0.72),
}
## Bushaltestelle: knalliges Gelb (unabhängig von der Buslinie).
const STOP_COL := Color(1.0, 0.85, 0.3)
## Wegpunkte dürfen leicht über den Kartenrand hinaus — so „fahren" Busse aus dem
## Bild und wieder zurück. Orts-Pins bleiben strikt 0..1.
const WP_MIN := -0.12
const WP_MAX := 1.12

var _town: Dictionary = {}
var _pins: Array = []            # [{id, name, dist, col, x, y, status}]  x,y = Anteil 0..1
var _map_tex: Texture2D
var _grid := {"cols": 10, "rows": 8}
var _sel := -1
var _dragging := false
var _show_planned := true
# Wegpunkt-Netz (Straßen): Knoten + Kanten (Indizes), Anteile 0..1.
var _mode := "locs"              # "locs" = Orte platzieren · "wp" = Wegpunkte/Straßen
var _waypoints: Array = []       # [{x, y}]
var _edges: Array = []           # [[i, j, layer], …]  layer ∈ all|foot|bike|bus
var _stops: Array = []           # Bushaltestellen (Wegpunkt-Indizes)
var _layer := "all"              # Ebene für NEUE Kanten (Werkzeug)
var _view := "all"               # Ansichtsfilter: welche Ebene(n) anzeigen
var _wp_sel := -1
var _wp_drag := false
var _btn_mode: Button
var _btn_layer: Button
var _btn_view: Button
var _btn_stop: Button
var _sprite_rect := Rect2()
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _saved_flash := 0.0
var _flash := ""
var _flash_col := Color(0.3, 1.0, 0.5)
var _font: Font
var _btn_save: Button
var _btn_plan: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = load("res://assets/fonts/VT323_UI.ttf")   # Spiel-Schrift
	_load_town()
	_build_toolbar()
	set_process(true)


## Echte Buttons (klick-sicher) — kein Rätsel, ob die Taste ankam.
func _build_toolbar() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(18, 150)
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_btn_save = _mk_button(Loc.t("misc.map_editor.speichern", "💾  SPEICHERN"))
	_btn_save.pressed.connect(_save)
	row.add_child(_btn_save)
	_btn_mode = _mk_button(Loc.t("misc.map_editor.modus_orte", "Modus: ORTE"))
	_btn_mode.pressed.connect(_toggle_mode)
	row.add_child(_btn_mode)
	_btn_plan = _mk_button(Loc.t("misc.map_editor.geplante_an", "Geplante: an"))
	_btn_plan.pressed.connect(func() -> void:
		_show_planned = not _show_planned
		_btn_plan.text = Loc.t("misc.map_editor.geplante_an", "Geplante: an") \
			if _show_planned else Loc.t("misc.map_editor.planned_off", "Geplante: aus")
		queue_redraw())
	row.add_child(_btn_plan)
	# Wegpunkt-Werkzeuge (nur im WP-Modus wirksam)
	_btn_layer = _mk_button(Loc.t("misc.map_editor.ebene_alle", "Ebene: ALLE"))
	_btn_layer.pressed.connect(_cycle_layer)
	row.add_child(_btn_layer)
	_btn_view = _mk_button(Loc.t("misc.map_editor.ansicht_alle", "Ansicht: ALLE"))
	_btn_view.pressed.connect(_cycle_view)
	row.add_child(_btn_view)
	_btn_stop = _mk_button(Loc.t("misc.map_editor.haltestelle", "＋Haltestelle"))
	_btn_stop.pressed.connect(_toggle_stop)
	row.add_child(_btn_stop)


## Werkzeug-Ebene für neue Kanten weiterschalten (all→foot→bike→bus).
func _cycle_layer() -> void:
	_set_layer(LAYERS[(LAYERS.find(_layer) + 1) % LAYERS.size()])


func _set_layer(lay: String) -> void:
	_layer = lay
	_btn_layer.text = Loc.t("misc.map_editor.ebene_s", "Ebene: %s") % LAYER_NAME[_layer]
	if _view != "all" and _view != _layer:   # was man malt, soll man auch sehen
		_view = _layer
		_btn_view.text = Loc.t("misc.map_editor.ansicht_s", "Ansicht: %s") % LAYER_NAME[_view]
	queue_redraw()


## Ansichtsfilter weiterschalten — so sieht man Fuß / Rad / Bus einzeln, dann alles.
func _cycle_view() -> void:
	_view = LAYERS[(LAYERS.find(_view) + 1) % LAYERS.size()]
	_btn_view.text = Loc.t("misc.map_editor.ansicht_s", "Ansicht: %s") % LAYER_NAME[_view]
	queue_redraw()


## Ausgewählten Wegpunkt als Bushaltestelle setzen/entfernen.
func _toggle_stop() -> void:
	if _mode != "wp" or _wp_sel < 0:
		_flash = "Erst im WP-Modus einen Wegpunkt wählen, dann Haltestelle."
		_flash_col = Color(1, 0.72, 0.3); _saved_flash = 2.0
		queue_redraw()
		return
	if _stops.has(_wp_sel):
		_stops.erase(_wp_sel)
	else:
		_stops.append(_wp_sel)
	queue_redraw()


func _toggle_mode() -> void:
	_mode = "wp" if _mode == "locs" else "locs"
	_btn_mode.text = Loc.t("misc.map_editor.modus_wegpunkte", "Modus: WEGPUNKTE") \
		if _mode == "wp" else Loc.t("misc.map_editor.mode_places", "Modus: ORTE")
	_sel = -1
	_wp_sel = -1
	queue_redraw()


func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.96)
	sb.border_color = Color(0.9, 0.72, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.22, 0.18, 0.06, 0.96)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	return b


## Text mit dunkler Outline — überall lesbar (auch auf dem hellen Kartenpapier).
func _txt(pos: Vector2, s: String, font_size: int, col: Color, outline: int = 4) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _process(delta: float) -> void:
	if _saved_flash > 0.0:
		_saved_flash = maxf(0.0, _saved_flash - delta)
		queue_redraw()


# ------------------------------------------------------------- Laden
func _load_town() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TOWN_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_town = parsed
	_grid = _town.get("meta", {}).get("grid", _grid)
	_map_tex = _load_map(str(_town.get("meta", {}).get("map_art_path", "")))
	var districts: Dictionary = _town.get("districts", {})
	var locs: Dictionary = _town.get("locations", {})
	for id: String in locs:
		var loc: Dictionary = locs[id]
		var x: float
		var y: float
		if loc.has("map_pos") and typeof(loc["map_pos"]) == TYPE_ARRAY:
			x = float(loc["map_pos"][0]); y = float(loc["map_pos"][1])
		else:                                        # Startschätzung aus dem Grid
			var p: Array = loc.get("pos", [5, 4])
			x = (float(p[0]) + 0.5) / float(_grid.get("cols", 10))
			y = (float(p[1]) + 0.5) / float(_grid.get("rows", 8))
		var dist := str(loc.get("district", ""))
		_pins.append({"id": id, "name": str(loc.get("name", id)), "dist": dist,
			"col": _col(str(districts.get(dist, {}).get("color", "#cccccc"))),
			"x": x, "y": y, "status": str(loc.get("status", "planned"))})
	# Wegpunkt-Netz laden
	var meta: Dictionary = _town.get("meta", {})
	for wp: Variant in meta.get("waypoints", []):
		if typeof(wp) == TYPE_ARRAY and (wp as Array).size() >= 2:
			_waypoints.append({"x": float(wp[0]), "y": float(wp[1])})
	for e: Variant in meta.get("edges", []):
		if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2:
			var lay := str(e[2]) if (e as Array).size() >= 3 else "all"
			_edges.append([int(e[0]), int(e[1]), lay])
	for s: Variant in meta.get("stops", []):
		_stops.append(int(s))


func _load_map(path: String) -> Texture2D:
	return RuntimeImages.texture(path, 1600)


func _col(hex: String) -> Color:
	return Color.from_string(hex, Color(0.8, 0.8, 0.8))


func _save() -> void:
	var locs: Dictionary = _town.get("locations", {})
	var n := 0
	for pin: Dictionary in _pins:
		if locs.has(pin["id"]):
			(locs[pin["id"]] as Dictionary)["map_pos"] = [snappedf(pin["x"], 0.0001), snappedf(pin["y"], 0.0001)]
			n += 1
	# Wegpunkt-Netz mitschreiben
	var meta: Dictionary = _town.get("meta", {})
	var wps: Array = []
	for w: Dictionary in _waypoints:
		wps.append([snappedf(w["x"], 0.0001), snappedf(w["y"], 0.0001)])
	meta["waypoints"] = wps
	meta["edges"] = _edges
	meta["stops"] = _stops.duplicate()
	_town["meta"] = meta
	var f := FileAccess.open(TOWN_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Map-Editor: town.json NICHT schreibbar (err %d)" % FileAccess.get_open_error())
		_flash = "✗ SPEICHERN FEHLGESCHLAGEN — Konsole prüfen"
		_flash_col = Color(1, 0.4, 0.35)
		_saved_flash = 2.5
		return
	f.store_string(JSON.stringify(_town, "\t", false))
	f.close()
	print("Map-Editor: %d Orte + %d Wegpunkte / %d Kanten / %d Haltestellen gespeichert → %s" % [
		n, _waypoints.size(), _edges.size(), _stops.size(), ProjectSettings.globalize_path(TOWN_PATH)])
	_flash = "✔ %d Orte · %d Wegpunkte · %d Kanten · %d Haltestellen" % [
		n, _waypoints.size(), _edges.size(), _stops.size()]
	_flash_col = Color(0.3, 1.0, 0.5)
	_saved_flash = 2.5


# ------------------------------------------------------------- Geometrie
func _compute_sprite_rect() -> void:
	var aspect := 1.6
	if _map_tex != null:
		var ts := Vector2(_map_tex.get_size())
		aspect = ts.x / ts.y
	else:
		aspect = float(_grid.get("cols", 10)) / float(_grid.get("rows", 8))
	var avail := Vector2(size.x * 0.82, size.y * 0.82)
	var draw_size := Vector2(avail.x, avail.x / aspect)
	if draw_size.y > avail.y:
		draw_size = Vector2(avail.y * aspect, avail.y)
	draw_size *= _zoom
	_sprite_rect = Rect2(((size - draw_size) * 0.5 + _pan).floor(), draw_size)


func _pin_screen(pin: Dictionary) -> Vector2:
	return _sprite_rect.position + Vector2(float(pin["x"]), float(pin["y"])) * _sprite_rect.size


func _visible(pin: Dictionary) -> bool:
	return _show_planned or pin["status"] == "live"


func _pin_at(point: Vector2) -> int:
	for i in _pins.size():
		if _visible(_pins[i]) and _pin_screen(_pins[i]).distance_to(point) <= HANDLE + 3.0:
			return i
	return -1


# ---------------- Wegpunkte
func _wp_screen(i: int) -> Vector2:
	var w: Dictionary = _waypoints[i]
	return _sprite_rect.position + Vector2(float(w["x"]), float(w["y"])) * _sprite_rect.size


func _wp_at(point: Vector2) -> int:
	for i in _waypoints.size():
		if _wp_screen(i).distance_to(point) <= HANDLE + 2.0:
			return i
	return -1


## Kante unter dem Cursor (nur sichtbare Ebenen) — für Rechtsklick-Löschen.
func _edge_at(point: Vector2) -> int:
	var best := -1
	var bd := 7.0
	for k in _edges.size():
		var e: Array = _edges[k]
		var lay := str(e[2]) if e.size() >= 3 else "all"
		if _view != "all" and lay != "all" and lay != _view:
			continue
		if e[0] >= _waypoints.size() or e[1] >= _waypoints.size():
			continue
		var cp := Geometry2D.get_closest_point_to_segment(point, _wp_screen(e[0]), _wp_screen(e[1]))
		var d := cp.distance_to(point)
		if d < bd:
			bd = d; best = k
	return best


## Rechtsklick im WP-Modus: Knoten unter dem Cursor löschen, sonst die Kante.
func _wp_delete_at(pos: Vector2) -> void:
	var hit := _wp_at(pos)
	if hit >= 0:
		_delete_wp(hit)
		queue_redraw()
		return
	var ei := _edge_at(pos)
	if ei >= 0:
		_edges.remove_at(ei)
		queue_redraw()


## Kante a–b auf der AKTUELLEN Ebene umschalten. Kanten verschiedener Ebenen
## zwischen denselben Knoten können nebeneinander bestehen (Fußweg ≠ Straße).
func _toggle_edge(a: int, b: int) -> void:
	if a == b:
		return
	for k in _edges.size():
		var e: Array = _edges[k]
		var lay := str(e[2]) if e.size() >= 3 else "all"
		if lay == _layer and ((e[0] == a and e[1] == b) or (e[0] == b and e[1] == a)):
			_edges.remove_at(k)
			return
	_edges.append([a, b, _layer])


func _delete_wp(idx: int) -> void:
	if idx < 0 or idx >= _waypoints.size():
		return
	_waypoints.remove_at(idx)
	var kept: Array = []
	for e: Array in _edges:
		if e[0] == idx or e[1] == idx:
			continue                                  # Kanten am gelöschten Knoten weg
		var lay := str(e[2]) if e.size() >= 3 else "all"
		kept.append([e[0] - (1 if e[0] > idx else 0), e[1] - (1 if e[1] > idx else 0), lay])
	_edges = kept
	var kstops: Array = []                             # Haltestellen mit-reindizieren
	for s: int in _stops:
		if s == idx:
			continue
		kstops.append(s - (1 if s > idx else 0))
	_stops = kstops
	_wp_sel = -1


# ------------------------------------------------------------- Eingabe
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_compute_sprite_rect()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _mode == "wp": _wp_click(event.position)
				else: _locs_click(event.position)
			MOUSE_BUTTON_RIGHT:
				if _mode == "wp": _wp_delete_at(event.position)
			MOUSE_BUTTON_MIDDLE:
				_panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, 0.87)
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = false
			_wp_drag = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			queue_redraw()
		elif _sprite_rect.size.x > 1.0:
			var f: Vector2 = (event.position - _sprite_rect.position) / _sprite_rect.size
			if _dragging and _sel >= 0:
				_pins[_sel]["x"] = clampf(f.x, 0.0, 1.0); _pins[_sel]["y"] = clampf(f.y, 0.0, 1.0)
				queue_redraw()
			elif _wp_drag and _wp_sel >= 0:
				_waypoints[_wp_sel]["x"] = clampf(f.x, WP_MIN, WP_MAX); _waypoints[_wp_sel]["y"] = clampf(f.y, WP_MIN, WP_MAX)
				queue_redraw()


func _locs_click(pos: Vector2) -> void:
	var hit := _pin_at(pos)
	_sel = hit
	_dragging = hit >= 0
	queue_redraw()


## Wegpunkt-Klick: auf Knoten = wählen (+ Kante zum vorher gewählten). Auf leere
## Straße = neuen Knoten setzen (+ Kante vom gewählten) → schnelles „Straße klicken".
func _wp_click(pos: Vector2) -> void:
	var hit := _wp_at(pos)
	if hit >= 0:
		if _wp_sel >= 0 and hit != _wp_sel:
			_toggle_edge(_wp_sel, hit)
		_wp_sel = hit
		_wp_drag = true
	else:
		var f: Vector2 = (pos - _sprite_rect.position) / _sprite_rect.size
		_waypoints.append({"x": clampf(f.x, WP_MIN, WP_MAX), "y": clampf(f.y, WP_MIN, WP_MAX)})
		var ni := _waypoints.size() - 1
		if _wp_sel >= 0:
			_edges.append([_wp_sel, ni, _layer])      # Kette: automatisch verbinden (aktuelle Ebene)
		_wp_sel = ni
		_wp_drag = true
	queue_redraw()


func _zoom_at(p: Vector2, factor: float) -> void:
	_compute_sprite_rect()
	var frac := (p - _sprite_rect.position) / _sprite_rect.size
	_zoom = clampf(_zoom * factor, 1.0, 12.0)
	_compute_sprite_rect()   # base neu (mit altem pan) — dann pan korrigieren
	_pan += p - (_sprite_rect.position + frac * _sprite_rect.size)
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_S:
			_save()
		KEY_M:
			_toggle_mode()
		KEY_H:
			_show_planned = not _show_planned
			queue_redraw()
		KEY_V:
			_cycle_view()
		KEY_B:
			_toggle_stop()
		KEY_1:
			_set_layer("all")
		KEY_2:
			_set_layer("foot")
		KEY_3:
			_set_layer("bike")
		KEY_4:
			_set_layer("bus1")
		KEY_5:
			_set_layer("bus2")
		KEY_DELETE, KEY_BACKSPACE:
			if _mode == "wp" and _wp_sel >= 0:
				_delete_wp(_wp_sel)
				queue_redraw()
		KEY_ESCAPE:
			_wp_sel = -1; _sel = -1
			queue_redraw()
		KEY_TAB, KEY_RIGHT:
			if _mode == "locs": _cycle(1)
		KEY_LEFT:
			if _mode == "locs": _cycle(-1)
		KEY_R:
			if _mode == "locs" and _sel >= 0:
				var loc: Dictionary = _town.get("locations", {}).get(_pins[_sel]["id"], {})
				var p: Array = loc.get("pos", [5, 4])
				_pins[_sel]["x"] = (float(p[0]) + 0.5) / float(_grid.get("cols", 10))
				_pins[_sel]["y"] = (float(p[1]) + 0.5) / float(_grid.get("rows", 8))
				queue_redraw()


func _cycle(dir: int) -> void:
	if _pins.is_empty():
		return
	var n := _pins.size()
	for _i in n:
		_sel = wrapi(_sel + dir, 0, n)
		if _visible(_pins[_sel]):
			break
	queue_redraw()


# ------------------------------------------------------------- Zeichnen
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.11))
	_compute_sprite_rect()
	if _map_tex != null:
		draw_texture_rect(_map_tex, _sprite_rect, false)
	else:
		draw_rect(_sprite_rect, Color(0.14, 0.16, 0.20))
		var c := _cols()
		var r := _rows()
		for i in range(c + 1):
			var x := _sprite_rect.position.x + i * _sprite_rect.size.x / c
			draw_line(Vector2(x, _sprite_rect.position.y), Vector2(x, _sprite_rect.end.y), Color(1, 1, 1, 0.06))
		for j in range(r + 1):
			var y := _sprite_rect.position.y + j * _sprite_rect.size.y / r
			draw_line(Vector2(_sprite_rect.position.x, y), Vector2(_sprite_rect.end.x, y), Color(1, 1, 1, 0.06))
		_txt(_sprite_rect.position + Vector2(10, 26), "Karten-Asset fehlt — lege es ab unter:", 20, Color(1, 0.82, 0.4))
		_txt(_sprite_rect.position + Vector2(10, 50), str(_town.get("meta", {}).get("map_art_path", "")), 18, Color(0.85, 0.9, 1.0))
	draw_rect(_sprite_rect, Color(0.9, 0.72, 0.3, 0.5), false, 1.0)

	# Wegpunkt-Netz je Ebene farbig: Kanten + Knoten. Ansichtsfilter blendet Ebenen aus.
	var wp_edit := _mode == "wp"
	for e: Array in _edges:
		if e[0] >= _waypoints.size() or e[1] >= _waypoints.size():
			continue
		var lay := str(e[2]) if e.size() >= 3 else "all"
		if _view != "all" and lay != "all" and lay != _view:
			continue                                   # ausgeblendete Ebene
		var base: Color = LAYER_COL.get(lay, LAYER_COL["all"])
		var col := Color(base, 0.95 if wp_edit else 0.5)
		var wide := 1.5
		if wp_edit:
			wide = 3.0 if lay == _layer else 2.0       # aktive Werkzeug-Ebene betont
		draw_line(_wp_screen(e[0]), _wp_screen(e[1]), col, wide)
	for i in _waypoints.size():
		var wc := _wp_screen(i)
		var r := 4.0 if wp_edit else 2.5
		var is_stop: bool = _stops.has(i)
		draw_circle(wc, r + 1.0, Color(0, 0, 0, 0.5))
		draw_circle(wc, r, STOP_COL if is_stop else (Color(0.35, 0.9, 1.0) if wp_edit else Color(0.4, 0.85, 1.0, 0.6)))
		if is_stop:                                    # Bushaltestelle: gelber H-Ring
			draw_arc(wc, r + 5.0, 0, TAU, 18, STOP_COL, 2.0)
			if wp_edit:
				_txt(wc + Vector2(r + 6.0, -r - 4.0), "H", 16, STOP_COL, 3)
		if wp_edit and i == _wp_sel:
			draw_arc(wc, r + 4.0, 0, TAU, 20, Color(1, 0.95, 0.4), 2.0)

	# Pins
	for i in _pins.size():
		var pin: Dictionary = _pins[i]
		if not _visible(pin):
			continue
		var ctr := _pin_screen(pin)
		var live: bool = pin["status"] == "live"
		var col: Color = pin["col"]
		draw_circle(ctr, 7.0, Color(0, 0, 0, 0.6))
		draw_circle(ctr, 5.0, col if live else Color(col, 0.55))
		if not live:
			draw_arc(ctr, 5.0, 0, TAU, 16, Color(col, 0.9), 1.0)
		if i == _sel:
			draw_arc(ctr, 10.0, 0, TAU, 24, Color(1, 0.95, 0.4, 1.0), 2.0)
		_txt(ctr + Vector2(10, 6), str(pin["name"]), 18,
			Color(1, 1, 1) if live else Color(1, 0.9, 0.66))

	_draw_hud()


func _cols() -> int: return int(_grid.get("cols", 10))
func _rows() -> int: return int(_grid.get("rows", 8))


func _draw_hud() -> void:
	var placed := 0
	for pin: Dictionary in _pins:
		if _town.get("locations", {}).get(pin["id"], {}).has("map_pos"):
			placed += 1
	var lines: Array
	if _mode == "wp":
		var per := {"all": 0, "foot": 0, "bike": 0, "bus1": 0, "bus2": 0}
		for e: Array in _edges:
			var lay := str(e[2]) if e.size() >= 3 else "all"
			per[lay] = int(per.get(lay, 0)) + 1
		lines = [
			"MAP-EDITOR · WEGPUNKTE — Ebene (neue Linien): %s   ·   Ansicht: %s   ·   [M] zu Orten" % [
				LAYER_NAME[_layer], LAYER_NAME[_view]],
			"Leere Stelle klicken = Knoten setzen (+ Linie vom letzten) · Knoten klicken = wählen/verbinden",
			"[1] ALLE  [2] FUSS  [3] RAD  [4] BUS 1  [5] BUS 2 wählt die Ebene · [V] Ansicht · [B] Haltestelle",
			"Rechtsklick = Knoten/Kante löschen · Entf = gewählten Knoten · Knoten ziehen = verschieben · [S] speichern",
			"WP: %d · Kanten alle:%d fuss:%d rad:%d bus1:%d bus2:%d · Haltestellen: %d · (WP dürfen über den Rand → Bus fährt raus)" % [
				_waypoints.size(), per["all"], per["foot"], per["bike"], per["bus1"], per["bus2"], _stops.size()],
		]
	else:
		var sel_txt := "—"
		if _sel >= 0:
			sel_txt = "%s   x=%.3f  y=%.3f" % [_pins[_sel]["name"], _pins[_sel]["x"], _pins[_sel]["y"]]
		lines = [
			"MAP-EDITOR · MODUS: ORTE — [M] zu Wegpunkten (Straßen)",
			"Pin ziehen = verschieben · Klick = wählen · Rad = Zoom · Mitte = schwenken",
			"Tab/→ nächster · ← vorheriger · H geplante ein/aus · R aufs Raster · S speichern",
			"Ausgewählt: %s" % sel_txt,
			"Orte: %d  ·  gespeichert: %d  ·  Wegpunkte: %d  ·  geplante: %s" % [
				_pins.size(), placed, _waypoints.size(), "an" if _show_planned else "aus"],
		]
	draw_rect(Rect2(0, 0, size.x, 26 + lines.size() * 22), Color(0.05, 0.06, 0.08, 0.72))  # lesbarer Balken
	var y := 26.0
	for t: String in lines:
		_txt(Vector2(18, y), t, 18, Color(0.92, 0.96, 1.0))
		y += 22.0
	if _saved_flash > 0.0 and _flash != "":
		_txt(Vector2(18, y + 6), _flash, 20, Color(_flash_col, minf(1.0, _saved_flash)))
