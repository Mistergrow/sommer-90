extends Control
## Kartenzeichnung, Fahrzeuganimation und interaktive Pins.
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const Vehicles := preload("res://scripts/gfx/chunky_vehicles.gd")
signal pin_selected(id: String)

const PAD := 8.0

var selected_id := ""
var travel_mode := "bike"
var _reachable_ids: Array = []
var _mission_ids: Array = []
var show_net := ""                 # ""=aus · foot|bike|bus|all: welches Wegenetz zeigen
var _cols := 10
var _rows := 8
var _pins: Array = []  # {id, button, status, live, loc}
var _map_tex: Texture2D            # Karten-Grafik (oder null → schematisch)
var _map_rect := Rect2()           # wohin die Karte gezeichnet wird
var _player: MiniFigure            # animierter Spielermarker
var _cyclist_frames: Dictionary = {}
var _car_frames: Dictionary = {}
# Reise-Animation entlang der Straßen — mit Ease-In/Out, Blickrichtung, Bob,
# rollenden Rädern. Fahrzeuge werden prozedural in _draw gezeichnet.
var _travel := false
var _route: Array = []             # Bildschirmpunkte der Route
var _cum: Array = []               # kumulierte Längen je Punkt
var _total := 0.0
var _tpos := 0.0                   # zurückgelegte Strecke (px) — treibt Radlauf
var _t01 := 0.0                    # Fortschritt 0..1 (wird geglättet)
var _dur := 1.6                    # Reisedauer (s)
var _tmode := "bike"
var _arrive: Callable
var _dash := 0.0                   # laufende Strichel-Phase der Route
# Lebende Linienbusse (bus1/bus2): fahren ihre Linie ab, kehren am Ende um,
# bremsen an den Enden ab — prozedural gezeichnet (rollende Räder, Blickrichtung).
var _ambient: Array = []           # {poly, cum, total, d, dir, tint, roll}
var _sb := StyleBoxFlat.new()      # wiederverwendet fürs Bus-Zeichnen

const TRAVEL_TIME := {"walk": 3.4, "bike": 2.3, "bus": 1.8, "car": 1.5}
const AMBIENT_SPEED := 0.06        # Karten-Anteile pro Sekunde


## Reise-Animation starten: Marker läuft/fährt die Straßen-Route ab, dann arrive().
func start_travel(from_id: String, to_id: String, mode: String, arrive: Callable) -> void:
	_compute_map_rect()
	_tmode = mode
	_arrive = arrive
	var pts: Array = TownManager.route_points(from_id, to_id, mode)
	_route.clear(); _cum.clear(); _total = 0.0
	for p: Vector2 in pts:
		_route.append(_map_point(p))
	_cum.append(0.0)
	for i in range(1, _route.size()):
		_total += (_route[i] as Vector2).distance_to(_route[i - 1])
		_cum.append(_total)
	_tpos = 0.0
	_t01 = 0.0
	_dur = maxf(0.5, float(TRAVEL_TIME.get(mode, 2.0)))
	if _player != null:
		# Fahrzeugfahrten besitzen eine gemeinsame sitzende/geschlossene
		# Silhouette. Nur zu Fuss bleibt die stehende Kartenfigur sichtbar.
		_player.visible = (mode == "walk")
	_travel = true
	set_process(true)


func _process(delta: float) -> void:
	_dash += delta
	_update_ambient(delta)
	if not _travel:
		queue_redraw()
		return
	_t01 = minf(_t01 + delta / _dur, 1.0)
	_tpos = _smooth(_t01) * _total                   # Ease-In/Out
	var p := _point_along(_tpos)
	if _player != null and _player.visible:
		# Sanftes Auf-und-Ab fuer die echte Gehfigur.
		var bob := -absf(sin(_tpos * 0.12)) * 3.0
		_player.position = p - Vector2(_player.size.x * 0.5, _player.size.y - 4) + Vector2(0, bob)
	queue_redraw()
	if _t01 >= 1.0:
		_travel = false
		if _player != null:
			_player.visible = true
		if _arrive.is_valid(): _arrive.call()


## Sanfte Beschleunigung/Abbremsung (smootherstep).
func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func _point_along(d: float) -> Vector2:
	if _route.size() < 2:
		return _route[0] if _route.size() == 1 else Vector2.ZERO
	for i in range(1, _route.size()):
		if d <= _cum[i]:
			var seg: float = _cum[i] - _cum[i - 1]
			var t: float = 0.0 if seg <= 0.001 else (d - _cum[i - 1]) / seg
			return (_route[i - 1] as Vector2).lerp(_route[i], t)
	return _route[_route.size() - 1]


## Fahrtrichtung (Einheitsvektor) an Bogenlänge d auf der Route.
func _heading_along(d: float) -> Vector2:
	if _route.size() < 2:
		return Vector2.RIGHT
	for i in range(1, _route.size()):
		if d <= _cum[i] + 0.01:
			return ((_route[i] as Vector2) - _route[i - 1]).normalized()
	return ((_route[_route.size() - 1] as Vector2) - _route[_route.size() - 2]).normalized()


func _ready() -> void:
	var grid: Dictionary = TownManager.data_grid()
	_cols = int(grid.get("cols", 10))
	_rows = int(grid.get("rows", 8))
	_map_tex = _load_map(TownManager.map_art_path())
	_build_pins()
	refresh_markers()
	# Animierter Spielermarker (blinzelt/sieht sich um) am aktuellen Ort.
	_player = MiniFigure.new()
	_player.bob = false
	# Das native 32×48-Raster darf nicht in einem 26×40-Control beschnitten
	# werden; die Kartenposition verankert weiterhin die Fuesse am Ort.
	_player.custom_minimum_size = Vector2(32, 48)
	_player.size = Vector2(32, 48)
	_player.setup(PlayerIdentity.avatar_seed, PlayerIdentity.hints(), true)
	add_child(_player)
	_build_ambient_buses()
	resized.connect(_layout)
	_layout()
	set_process(true)


# Sichtbares Papier innerhalb der FOLDING-Textur (gemessen). Der Renderer
# zeigt nur diesen Ausschnitt; die transparenten Studiobereiche der PNG
# verkleinern die Karte dadurch nicht mehr.
const PAPER := Rect2(0.19, 0.065, 0.62, 0.87)

## Papier-Rechteck in Bildschirmkoordinaten (Grenze für Linien/Busse).
func _paper_rect() -> Rect2:
	return _map_rect.grow(-4.0)


## Für jede Buslinie mit Kanten einen Bus: geordnete Polylinie, Dauerbetrieb.
func _build_ambient_buses() -> void:
	var tints := {"bus1": Color(1.0, 0.72, 0.22), "bus2": Color(1.0, 0.5, 0.78)}
	for line: String in ["bus1", "bus2"]:
		var pts: Array = TownManager.line_waypoints(line)
		if pts.size() < 2:
			continue
		var cum: Array = [0.0]
		var total := 0.0
		for i in range(1, pts.size()):
			total += (pts[i] as Vector2).distance_to(pts[i - 1])
			cum.append(total)
		if total <= 0.001:
			continue
		_ambient.append({"poly": pts, "cum": cum, "total": total,
			"d": randf() * total, "dir": 1, "tint": tints[line], "roll": 0.0})


## Alle Linienbusse ein Stück weiterfahren; an den Linien-Enden abbremsen & umkehren.
func _update_ambient(delta: float) -> void:
	for b: Dictionary in _ambient:
		var total: float = b["total"]
		# Sanftes Anfahren/Abbremsen an den Enden (Terminus-Gefühl).
		var edge: float = minf(float(b["d"]), total - float(b["d"]))
		var factor: float = clampf(0.25 + edge / (total * 0.18), 0.25, 1.0)
		var step: float = int(b["dir"]) * AMBIENT_SPEED * factor * delta
		b["d"] = float(b["d"]) + step
		b["roll"] = float(b["roll"]) + absf(step)
		if b["d"] >= total:
			b["d"] = total; b["dir"] = -1
		elif b["d"] <= 0.0:
			b["d"] = 0.0; b["dir"] = 1


## Punkt (0..1) entlang einer normalisierten Polylinie bei Bogenlänge d.
func _along_norm(poly: Array, cum: Array, d: float) -> Vector2:
	if poly.size() < 2:
		return poly[0] if poly.size() == 1 else Vector2.ZERO
	for i in range(1, poly.size()):
		if d <= float(cum[i]):
			var seg: float = float(cum[i]) - float(cum[i - 1])
			var t: float = 0.0 if seg <= 0.0001 else (d - float(cum[i - 1])) / seg
			return (poly[i - 1] as Vector2).lerp(poly[i], t)
	return poly[poly.size() - 1]


## Fahrtrichtung entlang einer normalisierten Polylinie bei d.
func _heading_norm(poly: Array, cum: Array, d: float) -> Vector2:
	if poly.size() < 2:
		return Vector2.RIGHT
	for i in range(1, poly.size()):
		if d <= float(cum[i]) + 0.0001:
			return ((poly[i] as Vector2) - poly[i - 1]).normalized()
	return ((poly[poly.size() - 1] as Vector2) - poly[poly.size() - 2]).normalized()


func _load_map(path: String) -> Texture2D:
	return RuntimeImages.texture(path, 1600)


## Bereich, in dem die Karten-Grafik gezeichnet wird (Seitenverhältnis erhalten);
## ohne Grafik = der volle gepolsterte Bereich (schematisch).
func _compute_map_rect() -> void:
	if _map_tex == null:
		_map_rect = Rect2(Vector2(PAD, PAD), size - Vector2(PAD, PAD) * 2.0)
		return
	var ts := Vector2(_map_tex.get_size()) * PAPER.size
	var avail := size - Vector2(PAD, PAD) * 2.0
	var s: float = minf(avail.x / ts.x, avail.y / ts.y)
	var ds := ts * s
	_map_rect = Rect2(((size - ds) * 0.5).floor(), ds)


## Datenpunkte bleiben im unveraenderten 0..1-Koordinatensystem des
## Original-Assets. Fuer die vergroesserte Papieransicht werden sie exakt in
## den ausgeschnittenen sichtbaren Bereich umgerechnet.
func _map_point(p: Vector2) -> Vector2:
	if _map_tex == null:
		return _map_rect.position + p * _map_rect.size
	var cropped := (p - PAPER.position) / PAPER.size
	return _map_rect.position + cropped * _map_rect.size


func _build_pins() -> void:
	for id: String in TownManager.location_ids():
		var loc: Dictionary = TownManager.location(id)
		if bool(loc.get("hide_on_map", false)):
			continue                          # Hinterzimmer etc. — nicht auf der Karte
		if not TownManager.map_visible(id):
			continue                          # jahr-gebunden: erscheint erst in seiner Ära
		var status: String = str(loc.get("status", "planned"))
		var btn := Button.new()
		btn.flat = true
		btn.modulate = Color(1, 1, 1, 0)  # unsichtbar, nur Klickfläche
		# 54×62 ist auch auf hochauflösenden Displays ein verlässliches Ziel;
		# der sichtbare Pin bleibt darunter zentriert.
		btn.custom_minimum_size = Vector2(54, 62)
		btn.size = Vector2(54, 62)
		btn.tooltip_text = _tooltip(id, loc)
		btn.pressed.connect(func() -> void: pin_selected.emit(id))
		add_child(btn)
		_pins.append({"id": id, "button": btn, "status": status,
			"live": TownManager.is_live(id), "loc": loc})


func _tooltip(id: String, loc: Dictionary) -> String:
	var t: String = TownManager.display_name(id)
	var hint: String = TownManager.display_hint(id)
	if not hint.is_empty():
		t += "\n" + hint
	if not TownManager.is_live(id):
		t += "\n" + (Loc.t("ui.map_window.tooltip_not_discovered", "(noch nicht entdeckt)") \
			if str(loc.get("status", "")) == "planned" else \
			Loc.t("ui.map_window.tooltip_available_later", "(später zugänglich)"))
	return t


## Pin-Mitte im Karten-Rechteck: pixelgenaues map_pos (0..1) wenn gesetzt, sonst
## schematisch aus dem Grid-pos. Beides relativ zu _map_rect (Asset ODER Platzhalter).
func _center_of(loc: Dictionary) -> Vector2:
	if loc.has("map_pos") and typeof(loc["map_pos"]) == TYPE_ARRAY and (loc["map_pos"] as Array).size() >= 2:
		var mp: Array = loc["map_pos"]
		return _map_point(Vector2(float(mp[0]), float(mp[1])))
	var p: Array = loc.get("pos", [0, 0])
	return _map_point(Vector2((float(p[0]) + 0.5) / _cols, (float(p[1]) + 0.5) / _rows))


func _layout() -> void:
	_compute_map_rect()
	for pin in _pins:
		var ctr: Vector2 = _center_of(pin["loc"])
		var b: Button = pin["button"]
		b.position = ctr - Vector2(b.size.x * 0.5, b.size.y - 6.0)  # Spitze = Ort, Kopf darüber
	if _player != null:
		var here: Dictionary = TownManager.location(GameManager.current_location_id)
		if not here.is_empty():
			var c: Vector2 = _center_of(here)
			_player.position = c - Vector2(_player.size.x * 0.5, _player.size.y - 5)  # Füße am Ort
	queue_redraw()


## Wegenetz-Ansicht umschalten (""=aus, foot|bike|bus|all).
func set_net(v: String) -> void:
	show_net = v
	queue_redraw()


func set_travel_mode(v: String) -> void:
	travel_mode = v
	if is_inside_tree():
		refresh_markers()
	queue_redraw()


## Marker nur bei Zeit-, Quest- oder Moduswechsel neu berechnen; die lebende
## Karte zeichnet zwar mit 60 FPS, erzeugt dabei aber keine Reiseabfragen.
func refresh_markers() -> void:
	_mission_ids = QuestManager.active_location_ids()
	_reachable_ids.clear()
	for pin: Dictionary in _pins:
		var id := str(pin["id"])
		if not bool(pin["live"]) or id == GameManager.current_location_id:
			continue
		var trip: Dictionary = TownManager.travel_preview(GameManager.current_location_id,
			id, travel_mode, true)
		if bool(trip.get("ok", false)) and int(trip.get("dm", 0)) <= int(PlayerStats.geld):
			_reachable_ids.append(id)
	queue_redraw()


## Ein bereits geoeffnetes Kartenblatt bleibt bei DE/EN-Umschaltung live:
## sichtbare Draw-Labels werden neu gezeichnet und die unsichtbaren
## Klickflaechen erhalten passende, aktuelle Tooltips.
func refresh_locale() -> void:
	for pin: Dictionary in _pins:
		var button: Button = pin["button"]
		button.tooltip_text = _tooltip(str(pin["id"]), pin["loc"])
	queue_redraw()


const NET_COL := {
	"all": Color(0.80, 0.82, 0.90),
	"foot": Color(0.45, 0.95, 0.55),
	"bike": Color(0.40, 0.72, 1.00),
	"bus1": Color(1.00, 0.66, 0.22),
	"bus2": Color(1.00, 0.42, 0.72),
}


## Welche Ebenen die Ansicht zeigt (Bus zeigt beide Linien + geteilte Straßen).
func _view_layers(v: String) -> Array:
	match v:
		"foot": return ["all", "foot"]
		"bike": return ["all", "bike"]
		"bus": return ["all", "bus1", "bus2"]
		"all": return ["all", "foot", "bike", "bus1", "bus2"]
	return []


## Straßen/Wege der gewählten Ebene(n) unter die Pins zeichnen — so sieht man
## Fuß-, Rad- und Buswege einzeln oder alle zusammen. Bushaltestellen als Ringe.
func _draw_network() -> void:
	if show_net == "":
		return
	var wps: Array = TownManager.waypoints()
	if wps.size() < 2:
		return
	var lays := _view_layers(show_net)
	for e: Array in TownManager.edges():
		var lay: String = str(e[2])
		if not lays.has(lay):
			continue
		if e[0] >= wps.size() or e[1] >= wps.size():
			continue
		var a: Vector2 = _map_point(wps[e[0]])
		var b: Vector2 = _map_point(wps[e[1]])
		var seg := _clip(a, b)                       # nichts außerhalb der Karte zeigen
		if seg.is_empty():
			continue
		var c: Color = NET_COL.get(lay, NET_COL["all"])
		draw_line(seg[0], seg[1], Color(c, 0.75), 2.5)
	if show_net == "all" or show_net == "bus":
		for si: int in TownManager.bus_stops():
			if si < 0 or si >= wps.size():
				continue
			var sp: Vector2 = _map_point(wps[si])
			var sa := _edge_alpha(sp)
			if sa <= 0.0:
				continue
			draw_circle(sp, 4.0, _fa(Color(1.0, 0.85, 0.3), sa))
			draw_arc(sp, 7.5, 0, TAU, 18, _fa(Color(1.0, 0.85, 0.3), sa), 2.0)


func _draw() -> void:
	_compute_map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.10, 0.12))
	var font := get_theme_default_font()

	# Echte Karten-Grafik, falls vorhanden — dann KEINE Bezirks-Boxen (nur Pins).
	if _map_tex != null:
		var texture_size := Vector2(_map_tex.get_size())
		var source := Rect2(PAPER.position * texture_size, PAPER.size * texture_size)
		# Weicher Kartenschatten, dann nur das echte Papier statt der breiten
		# transparenten PNG-Raender.
		var shadow_rect := _map_rect.grow(7.0)
		shadow_rect.position += Vector2(0, 5)
		draw_rect(shadow_rect, Color(0, 0, 0, 0.34))
		draw_texture_rect_region(_map_tex, _map_rect, source)
		draw_rect(_map_rect, Color(0.80, 0.72, 0.54, 0.72), false, 2.0)
	else:
		# Schematisch: Bezirks-Flächen = Bounding-Box ihrer Orte, in Bezirksfarbe getönt
		var by_district: Dictionary = {}
		for pin in _pins:
			var d: String = str(pin["loc"].get("district", ""))
			by_district.get_or_add(d, []).append(_center_of(pin["loc"]))
		for d: String in by_district:
			var pts: Array = by_district[d]
			var mn: Vector2 = pts[0]
			var mx: Vector2 = pts[0]
			for pt: Vector2 in pts:
				mn = mn.min(pt)
				mx = mx.max(pt)
			var pad := Vector2(20, 18)
			var rect := Rect2(mn - pad, (mx - mn) + pad * 2.0)
			var col: Color = TownManager.district_color(d)
			draw_rect(rect, Color(col, 0.16))
			draw_rect(rect, Color(col, 0.5), false, 1.0)
			draw_string(font, rect.position + Vector2(6, 13), TownManager.district_name(d),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.9))

	_draw_network()   # Wege/Straßen der gewählten Ebene unter die Pins
	_draw_ambient()   # lebende Linienbusse — UNTER den Pins (verdecken keine Orte!)
	if _travel and _route.size() >= 2:
		_draw_route()

	# Pins als klar sichtbare Teardrop-Marker (Spitze = Ort). Der aktuelle Ort
	# trägt die Spielerfigur (kein Pin), damit man sich sofort findet.
	var label_boxes: Array[Rect2] = []
	if _travel and _route.size() >= 2 and _tmode == "bike":
		# Ortsnamen weichen dem animierten Fahrer aus, statt hinter Kopf oder
		# Fahrrad zu verschwinden.
		label_boxes.append(Rect2(_point_along(_tpos) - Vector2(27, 44),
			Vector2(54, 48)))
	for pin in _pins:
		var ctr: Vector2 = _center_of(pin["loc"])
		var live: bool = pin["live"]
		var is_here: bool = pin["id"] == GameManager.current_location_id
		var mission: bool = _mission_ids.has(pin["id"])
		var reachable: bool = _reachable_ids.has(pin["id"])
		var col: Color = TownManager.district_color(str(pin["loc"].get("district", "")))
		var sel: bool = pin["id"] == selected_id
		if is_here:
			# „Du bist hier": sanft pulsierender Doppelring unter der Figur
			var pr := 14.0 + sin(_dash * 2.6) * 2.0
			draw_arc(ctr, pr, 0, TAU, 28, Color(0.95, 0.55, 0.2, 0.9), 2.0)
			draw_arc(ctr, pr + 5.0, 0, TAU, 28, Color(0.95, 0.55, 0.2, 0.25 + 0.15 * sin(_dash * 2.6)), 1.5)
			if mission:
				draw_arc(ctr, pr + 9.0, 0, TAU, 32, Color(1.0, 0.78, 0.22, 0.95), 3.0)
		else:
			_draw_pin(ctr, 12.0 if live else 10.0, col if live else Color(col, 0.55), live, sel,
				sin(_dash * 4.0) * 1.4 if sel else 0.0, reachable, mission)
		# Label nur für begehbare Orte + aktuellen Ort (mit Outline auf dem Papier).
		if live or is_here:
			var nm := TownManager.display_name(str(pin["id"]))
			var label_size := clampi(roundi(_map_rect.size.y / 44.0), 16, 20)
			var label_width := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT,
				-1, label_size).x
			var lp := _label_origin(ctr, label_width, label_size, label_boxes)
			label_boxes.append(Rect2(lp + Vector2(-3, -label_size),
				Vector2(label_width + 6, label_size + 4)))
			draw_string_outline(font, lp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, 4, Color(0, 0, 0, 0.9))
			draw_string(font, lp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size,
				Color(1, 1, 1) if live else Color(1, 0.87, 0.62))
	# Der aktive Fahrer liegt über Wegen und statischen Markern. Dadurch bleibt
	# die Sitzhaltung auch an dicht belegten Kreuzungen klar lesbar.
	if _travel and _route.size() >= 2:
		_draw_travel_vehicle()


## Labels suchen sich rund um den Pin die erste freie Seite und bleiben auf
## dem Papier. Das verhindert abgeschnittene Namen und die alten Textstapel
## bei den dicht beieinanderliegenden Wohnorten.
func _label_origin(ctr: Vector2, width: float, font_size: int,
		occupied: Array[Rect2]) -> Vector2:
	var candidates: Array[Vector2] = [
		ctr + Vector2(12, -7),
		ctr + Vector2(12, font_size + 5),
		ctr + Vector2(-12 - width, -7),
		ctr + Vector2(-12 - width, font_size + 5),
	]
	var bounds := _paper_rect().grow(-4.0)
	for origin: Vector2 in candidates:
		var box := Rect2(origin + Vector2(-3, -font_size),
			Vector2(width + 6, font_size + 4))
		if not bounds.encloses(box):
			continue
		var blocked := false
		for old_box: Rect2 in occupied:
			if box.intersects(old_box, true):
				blocked = true
				break
		if not blocked:
			return origin
	# Extrem dicht belegte Punkte bleiben zumindest vollständig im Papier.
	return Vector2(clampf(ctr.x + 12.0, bounds.position.x + 3.0,
		bounds.end.x - width - 3.0),
		clampf(ctr.y - 7.0, bounds.position.y + font_size,
		bounds.end.y - 4.0))


# ---------------------------------------------------------- AAA-Reise-Grafik

## Alpha fürs „am Kartenrand auflösen": 1 tief drin, 0 am Papierrand / außerhalb.
func _edge_alpha(p: Vector2) -> float:
	var r := _paper_rect()
	var fade := 30.0
	var dx := minf(p.x - r.position.x, r.end.x - p.x)
	var dy := minf(p.y - r.position.y, r.end.y - p.y)
	return clampf(minf(dx, dy) / fade, 0.0, 1.0)


## Segment aufs Papier-Rechteck beschneiden (Liang-Barsky). [] = ganz außerhalb.
func _clip(a: Vector2, b: Vector2) -> Array:
	var pr := _paper_rect()
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - pr.position.x, pr.end.x - a.x,
		a.y - pr.position.y, pr.end.y - a.y]
	for i in 4:
		if absf(p[i]) < 0.0001:
			if q[i] < 0.0:
				return []
		else:
			var r: float = q[i] / p[i]
			if p[i] < 0.0:
				if r > t1: return []
				if r > t0: t0 = r
			else:
				if r < t0: return []
				if r < t1: t1 = r
	return [a + d * t0, a + d * t1]


## Farbe mit zusätzlichem Alpha-Faktor.
func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

## Route: dunkles Casing, gedämpfter Restweg, warm hervorgehobener Fahrtweg,
## glühender Kopf, pulsierendes Ziel — beschnitten aufs Kartenrechteck.
func _draw_route() -> void:
	for i in range(1, _route.size()):
		var s0 := _clip(_route[i - 1], _route[i])
		if s0.is_empty():
			continue
		draw_line(s0[0], s0[1], Color(0, 0, 0, 0.35), 6.0, true)
		draw_line(s0[0], s0[1], Color(0.55, 0.70, 0.98, 0.5), 3.0, true)
	for i in range(1, _route.size() - 1):
		if _edge_alpha(_route[i]) > 0.0:
			draw_circle(_route[i], 2.2, Color(0.55, 0.70, 0.98, 0.6))   # weiche Ecken
	var prev: Vector2 = _route[0]
	var head := _point_along(_tpos)
	for i in range(1, _route.size()):
		var to: Vector2 = _route[i] if _cum[i] <= _tpos else head
		var s := _clip(prev, to)
		if not s.is_empty():
			draw_line(s[0], s[1], Color(1.0, 0.70, 0.22), 4.0, true)
		if _cum[i] <= _tpos:
			prev = _route[i]
		else:
			break
	var ha := _edge_alpha(head)
	draw_circle(head, 6.0, _fa(Color(1.0, 0.85, 0.4, 0.30), ha))        # Kopf-Glühen
	draw_circle(head, 2.6, _fa(Color(1.0, 0.96, 0.75), ha))
	var dest: Vector2 = _route[_route.size() - 1]
	if _edge_alpha(dest) > 0.0:
		draw_arc(dest, 6.0 + sin(_dash * 4.0) * 2.0, 0, TAU, 22, Color(1.0, 0.72, 0.2, 0.75), 2.0)


## Reise-Fahrzeug passend zum Modus (Figur ist ein eigener Node, bobt separat).
func _draw_travel_vehicle() -> void:
	var p := _point_along(_tpos)
	var h := _heading_along(_tpos)
	var a := _edge_alpha(p)
	if a <= 0.0:
		return
	match _tmode:
		"bus":
			_draw_bus(p - Vector2(0, 6), h, _tpos * 0.35, Color(1.0, 0.85, 0.3), a)
		"car":
			_draw_car(p, h, a)
		"bike":
			_draw_cyclist(p, h, a)
		_:
			draw_rect(Rect2(p.x - 5, p.y + 1, 10, 3), _fa(Color(0, 0, 0, 0.22), a))  # Fuß-Schatten


## Alle lebenden Linienbusse zeichnen — außerhalb der Karte lösen sie sich auf.
func _draw_ambient() -> void:
	for b: Dictionary in _ambient:
		var pn: Vector2 = _along_norm(b["poly"], b["cum"], b["d"])
		var c: Vector2 = _map_point(pn)
		var a := _edge_alpha(c)
		if a <= 0.0:
			continue                                  # off-map → unsichtbar (löst sich auf)
		var th: Vector2 = _heading_norm(b["poly"], b["cum"], b["d"]) * int(b["dir"])
		_draw_bus(c - Vector2(0, 5), th, float(b["roll"]) * 60.0, b["tint"], a)


## Prozeduraler Seiten-Bus: Schatten, gerundeter Körper, Fensterband, Scheinwerfer,
## zwei rollende Räder, Federungs-Bob. spin = Radwinkel-Basis, a = Sichtbarkeit.
func _draw_bus(c: Vector2, head: Vector2, spin: float, tint: Color, a: float = 1.0) -> void:
	var fx := 1.0 if head.x >= 0.0 else -1.0
	var w := 42.0
	var h := 17.0
	var cc := c + Vector2(0, sin(spin * 0.7) * 0.8)               # Federungs-Bob
	draw_rect(Rect2(cc.x - w * 0.5, c.y + h * 0.5 + 1.0, w, 3.0), _fa(Color(0, 0, 0, 0.22), a))
	_sb.bg_color = _fa(tint, a)
	_sb.border_color = _fa(tint.darkened(0.45), a)
	_sb.set_border_width_all(1)
	_sb.set_corner_radius_all(4)
	draw_style_box(_sb, Rect2(cc.x - w * 0.5, cc.y - h * 0.5, w, h))
	var win := Rect2(cc.x - w * 0.5 + 4.0, cc.y - h * 0.5 + 3.0, w - 13.0, h * 0.4)
	draw_rect(win, _fa(Color(0.78, 0.9, 1.0, 0.88), a))
	for k in range(1, 4):
		var wx: float = win.position.x + win.size.x * k / 4.0
		draw_line(Vector2(wx, win.position.y), Vector2(wx, win.end.y), _fa(tint.darkened(0.35), a), 1.0)
	draw_circle(Vector2(cc.x + fx * (w * 0.5 - 2.5), cc.y + 3.0), 1.7, _fa(Color(1.0, 0.95, 0.6), a))
	var wy := cc.y + h * 0.5 - 1.0
	_wheel(Vector2(cc.x - w * 0.28, wy), 4.0, spin * fx, a)
	_wheel(Vector2(cc.x + w * 0.28, wy), 4.0, spin * fx, a)


## Echte sitzende Fahrpose als gemeinsames Sprite. Vier Pedalphasen werden
## gecacht; die Bewegungsrichtung spiegelt das komplette Motiv und kann
## deshalb nie wieder Fahrer und Fahrrad gegeneinander verdrehen.
func _draw_cyclist(c: Vector2, head: Vector2, a: float = 1.0) -> void:
	var frame := posmod(floori(_tpos / 5.0), 4)
	var right := head.x >= 0.0
	var key := "%d_%s" % [frame, "r" if right else "l"]
	if not _cyclist_frames.has(key):
		_cyclist_frames[key] = Vehicles.cyclist(PlayerIdentity.avatar_seed,
			PlayerIdentity.hints(), frame, right)
	var texture: Texture2D = _cyclist_frames[key]
	var bob := -1.0 if frame in [1, 2] else 0.0
	var at := Vector2(roundf(c.x - texture.get_width() * 0.5),
		roundf(c.y - texture.get_height() + 2.0 + bob))
	draw_texture(texture, at, Color(1, 1, 1, a))


## Eigenes Auto-Sprite statt des früheren gelben Ersatzbusses. Vier Radphasen,
## leichtes Einfedern und der Avatar hinter der Seitenscheibe verbinden die
## Animation sichtbar mit der Fahrradfahrt und mit der Spieleridentität.
func _draw_car(c: Vector2, head: Vector2, a: float = 1.0) -> void:
	var frame := posmod(floori(_tpos / 4.0), 4)
	var right := head.x >= 0.0
	var key := "%d_%s" % [frame, "r" if right else "l"]
	if not _car_frames.has(key):
		_car_frames[key] = Vehicles.car(PlayerIdentity.avatar_seed,
			PlayerIdentity.hints(), frame, right)
	var texture: Texture2D = _car_frames[key]
	var suspension := -1.0 if frame in [1, 2] else 0.0
	var at := Vector2(roundf(c.x - texture.get_width() * 0.5),
		roundf(c.y - texture.get_height() + 4.0 + suspension))
	draw_texture(texture, at, Color(1, 1, 1, a))


## Ein rollendes Rad: Reifen, Nabe, drei Speichen (Winkel = ang, a = Sichtbarkeit).
func _wheel(c: Vector2, r: float, ang: float, a: float = 1.0) -> void:
	draw_circle(c, r, _fa(Color(0.11, 0.11, 0.13), a))
	draw_circle(c, r * 0.5, _fa(Color(0.72, 0.72, 0.75), a))
	for s in 3:
		var sa := ang + s * TAU / 3.0
		draw_line(c, c + Vector2(cos(sa), sin(sa)) * (r * 0.82), _fa(Color(0.32, 0.32, 0.35), a), 1.0)


## Klassischer Karten-Pin: farbiger Kopf mit weißem Rand + Spitze am Ort.
## pulse = zusätzlicher Radius des Auswahlrings (animiert die Auswahl).
func _draw_pin(tip: Vector2, r: float, fill: Color, solid: bool, sel: bool,
	pulse: float = 0.0, reachable: bool = false, mission: bool = false) -> void:
	var head := tip - Vector2(0, r * 1.6)
	var tri := PackedVector2Array([head + Vector2(-r * 0.72, r * 0.55), head + Vector2(r * 0.72, r * 0.55), tip])
	draw_colored_polygon(tri, fill)
	draw_circle(head, r, fill)
	draw_arc(head, r, 0, TAU, 32, Color(1, 1, 1, 0.95), 2.0)          # weißer Rand
	draw_circle(head, r * 0.42, Color(1, 1, 1, 0.95) if solid else Color(1, 1, 1, 0.5))  # Kern
	if reachable:
		draw_arc(head, r + 2.5, 0, TAU, 32, Color(0.36, 0.95, 0.52, 0.95), 2.0)
		draw_circle(head + Vector2(r * 0.75, -r * 0.75), 2.5, Color(0.48, 1.0, 0.58))
	if mission:
		var mr := r + 7.0 + sin(_dash * 3.2) * 1.0
		draw_arc(head, mr, 0, TAU, 36, Color(1.0, 0.72, 0.16, 0.98), 3.0)
	if sel:
		draw_arc(head, r + 4.0 + pulse, 0, TAU, 32, Color(1, 0.92, 0.3), 2.5)
