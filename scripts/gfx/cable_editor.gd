extends Control
## Kabel-Editor (scenes/CableEditor.tscn) — dediziertes Werkzeug, um die Kabel-
## Endpunkte im Zimmer sauber zu setzen und Steckdosen/Mehrfachverteiler zu
## platzieren, an die die Stromkabel laufen. Mit F6 starten (oder DSS_CABLE=1).
##
## Bedienung:
##   Kabelende ziehen ........... grün = Start, rot = Ende (Offset zum Gerät)
##   nahe einer Steckdose loslassen  Kabel dockt an die Steckdose an
##   N .......................... Wandsteckdose setzen (2 Löcher)
##   M .......................... Mehrfachverteiler setzen (Leiste + Schalter)
##   Steckdose ziehen ........... verschieben · Entf löscht die gewählte
##   Mausrad = Zoom · Mitte = schieben · 0 = Ansicht · F8 / Strg+S = speichern
##
## Speichert nach data/room_anchors.json ("cables" + "sockets").

const CONFIG_PATH := "res://data/room_anchors.json"
const RoomCompositorScript := preload("res://scripts/gfx/room_compositor.gd")
const CableGizScript := preload("res://scripts/gfx/cable_giz.gd")
const DeviceCatalogScript := preload("res://scripts/gfx/room_device_catalog.gd")

var _comp: RoomCompositor = null
var _giz: Control = null
var _cfg: Dictionary = {}
var _cables: Array = []
var _sockets: Array = []
var _anchors: Dictionary = {}

# Auswahl/Ziehen: {"kind": "cable"|"socket", "idx": i, "end": "start"|"end"}
var _sel: Dictionary = {}
var _dragging := false
var _panning := false

# Geräte-Fokus (Pfeiltasten): Geräte mit Kabeln nacheinander anzeigen, um deren
# Anschlüsse gebündelt zu setzen. _focus = Index in _devices, -1 = alle zeigen.
var _devices: Array = []
var _focus := -1


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load()
	# LED-Manager-Prinzip: das Werkzeug zeigt ALLE kabelfähigen Geräte, egal was
	# der Spielstand besitzt — sonst lassen sich Kabel neuer Modelle (1901,
	# Modems, Drucker …) nie setzen. Nur im F6-Prozess; gespeichert wird hier
	# ausschließlich room_anchors.json, nie der Spielstand.
	_grant_preview_equipment()
	# Backdrop: sauberer Raum (nur Basis + Objektlagen), in einem Control-Parent,
	# damit der Compositor sich über get_parent_control() korrekt sized.
	var room := Control.new()
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(room)
	_comp = RoomCompositorScript.new()
	_comp.suppress_overlays = true
	_comp.edit_mode = true      # editor_zoom/pan greifen im _master_transform
	room.add_child(_comp)
	# Gizmo-Ebene DARÜBER: z_index MUSS über alle Raum-Objekte (z 8–11), sonst
	# liegen die Griffe hinter Telefon/Computer/Monitor und sind nicht greifbar.
	_giz = CableGizScript.new()
	_giz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_giz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_giz.z_index = 200
	add_child(_giz)


func _load() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_cfg = parsed
	_cables = _cfg.get("cables", [])
	_anchors = _cfg.get("anchors", {})
	if not _cfg.has("sockets"):
		_cfg["sockets"] = []
	_sockets = _cfg["sockets"]
	_rebuild_devices()


## Alle Geräte (Objekt-Ids) sammeln, die als Kabel-Endpunkt vorkommen.
func _rebuild_devices() -> void:
	var seen := {}
	_devices = []
	for c: Dictionary in _cables:
		for key in ["start", "end"]:
			var spec: Variant = c.get(key, {})
			if spec is Dictionary and spec.has("object"):
				var oid := str(spec["object"])
				if not seen.has(oid):
					seen[oid] = true
					_devices.append(oid)
	_devices.sort()


func _focus_device() -> String:
	return _devices[_focus] if _focus >= 0 and _focus < _devices.size() else ""


# ---------------------------------------------- Preview-Vollausstattung (F6)

func _grant_preview_equipment() -> void:
	# add_hardware AKTIVIERT gekaufte Modelle (T11-Hook) — die Slots danach
	# wiederherstellen, damit der Editor-Start den Modellzustand nicht verstellt
	# (V schaltet bewusst um, der Start nicht).
	var slots_before := {}
	for slot: Variant in PlayerStats.DESK_MODEL_OPTIONS:
		slots_before[str(slot)] = str(PlayerStats.desk_model(str(slot)))
	for hardware_id: String in preview_hardware_ids(_cfg):
		if not PlayerStats.has_hardware(hardware_id):
			PlayerStats.add_hardware(hardware_id)
	for object_id: String in preview_object_ids(_cfg):
		if not RoomManager.has_object(object_id):
			RoomManager.add_object(object_id)
	for slot: String in slots_before:
		if str(PlayerStats.desk_model(slot)) != str(slots_before[slot]):
			PlayerStats.select_desk_model(slot, str(slots_before[slot]))


## Alle Besitz-IDs, die Raum-Layer (requires_hardware/any) oder die Modell-
## kataloge (DESK_MODEL_OPTIONS je Slot) verlangen. Statisch = headless testbar.
static func preview_hardware_ids(cfg: Dictionary) -> Array:
	var ids: Array = []
	for layer: Variant in cfg.get("layers", []):
		if typeof(layer) != TYPE_DICTIONARY:
			continue
		var single := str((layer as Dictionary).get("requires_hardware", ""))
		if single != "" and not ids.has(single):
			ids.append(single)
		for any_id: Variant in (layer as Dictionary).get("requires_any_hardware", []):
			if not ids.has(str(any_id)):
				ids.append(str(any_id))
	for slot: Variant in PlayerStats.DESK_MODEL_OPTIONS:
		var models: Dictionary = DeviceCatalogScript.definition_for_slot(str(slot)).get("models", {})
		for model: Variant in models.values():
			if typeof(model) != TYPE_DICTIONARY:
				continue
			var requirement: Variant = (model as Dictionary).get("requires_hardware", "")
			var wanted: Array = requirement if requirement is Array else [requirement]
			for hardware_id: Variant in wanted:
				if str(hardware_id) != "" and not ids.has(str(hardware_id)):
					ids.append(str(hardware_id))
	return ids


static func preview_object_ids(cfg: Dictionary) -> Array:
	var ids: Array = []
	for layer: Variant in cfg.get("layers", []):
		if typeof(layer) != TYPE_DICTIONARY:
			continue
		var object_id := str((layer as Dictionary).get("requires_object", ""))
		if object_id != "" and not ids.has(object_id):
			ids.append(object_id)
	return ids


## Modellvariante des fokussierten Geräts durchschalten (1084S↔1901, A500→A600
## →A1200 …): die requires_model-Kabel des aktiven Modells werden sichtbar und
## justierbar — je Modell eigene Offsets, wie der LED-Editor je Modell arbeitet.
func _cycle_focused_model() -> void:
	var dev := _focus_device()
	if dev == "" or _comp == null:
		return
	var selector := ""
	for layer: Variant in _cfg.get("layers", []):
		if typeof(layer) == TYPE_DICTIONARY and str((layer as Dictionary).get("id", "")) == dev:
			selector = str((layer as Dictionary).get("model_selector", ""))
	if selector == "":
		return
	var options: Array = PlayerStats.DESK_MODEL_OPTIONS.get(selector, [])
	if options.size() < 2:
		return
	var current := str(PlayerStats.desk_model(selector))
	var next_model := str(options[(options.find(current) + 1) % options.size()])
	if RoomManager.has_method("select_device_model"):
		RoomManager.call("select_device_model", selector, next_model)
	else:
		PlayerStats.select_desk_model(selector, next_model)
	_comp.rebuild()
	_redraw()


## Anschlüsse (Kabel + Ende) am aktuell fokussierten Gerät.
func _focus_ports() -> Array:
	var dev := _focus_device()
	var ports: Array = []
	if dev == "":
		return ports
	for i in _cables.size():
		var c: Dictionary = _cables[i]
		for key in ["start", "end"]:
			var spec: Variant = c.get(key, {})
			if spec is Dictionary and str(spec.get("object", "")) == dev:
				ports.append({"idx": i, "end": key})
	return ports


## Ansicht auf das fokussierte Gerät zentrieren/zoomen.
func _frame_focus() -> void:
	var dev := _focus_device()
	if dev == "" or _comp == null:
		_comp.editor_reset_view()
	else:
		_comp.editor_focus(_object_anchor(dev), 2.6)
	_redraw()


# ------------------------------------------------------------- Koordinaten
func _t() -> Dictionary:
	return _comp._master_transform() if _comp != null else {"scale": 1.0, "offset": Vector2.ZERO}


func _to_screen(master: Vector2) -> Vector2:
	var t := _t()
	return t["offset"] + master * t["scale"]


func _to_master(screen: Vector2) -> Vector2:
	var t := _t()
	return (screen - t["offset"]) / maxf(0.0001, t["scale"])


## Anker-Position (Master) eines Objekt-Layers (id → anchor → anchors[anchor]).
func _object_anchor(object_id: String) -> Vector2:
	for layer: Dictionary in _cfg.get("layers", []):
		if str(layer.get("id", "")) == object_id:
			var a: Array = _anchors.get(str(layer.get("anchor", "")), [0, 0])
			return Vector2(a[0], a[1])
	return Vector2.ZERO


func _socket_by_id(sid: String) -> Dictionary:
	for s: Dictionary in _sockets:
		if str(s.get("id", "")) == sid:
			return s
	return {}


func _socket_pos(sid: String) -> Vector2:
	var s := _socket_by_id(sid)
	var p: Array = s.get("pos", [0, 0])
	return Vector2(p[0], p[1])


## Endpunkt-Spezifikation → Master-Position (Objekt+Offset · Steckdose+Offset · Anker).
func _endpoint_master(spec: Variant) -> Vector2:
	if spec is Dictionary:
		var off: Array = spec.get("offset", [0, 0])
		if spec.has("socket"):
			return _socket_pos(str(spec["socket"])) + Vector2(off[0], off[1])
		if spec.has("object"):
			return _object_anchor(str(spec["object"])) + Vector2(off[0], off[1])
	if spec is String and _anchors.has(spec):
		var a: Array = _anchors[spec]
		return Vector2(a[0], a[1])
	return Vector2.ZERO


## Neuen Master-Punkt in die Endpunkt-Spezifikation zurückschreiben (Offset zum
## Bezug = Gerät oder Steckdose).
func _set_endpoint_master(spec: Dictionary, m: Vector2) -> void:
	var base := Vector2.ZERO
	if spec.has("socket"):
		base = _socket_pos(str(spec["socket"]))
	elif spec.has("object"):
		base = _object_anchor(str(spec["object"]))
	spec["offset"] = [snappedf(m.x - base.x, 0.5), snappedf(m.y - base.y, 0.5)]


# ------------------------------------------------------------- Eingabe
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_pick(event.position)
				else:
					_release()
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_comp.editor_zoom_at(event.position, 1.15)
					_redraw()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_comp.editor_zoom_at(event.position, 0.87)
					_redraw()
	elif event is InputEventMouseMotion:
		if _panning:
			_comp.editor_pan_by(event.relative)
			_redraw()
		elif _dragging:
			_drag_to(event.position)


## Griff unter dem Zeiger wählen: erst Kabel-Enden, dann Steckdosen.
func _pick(p: Vector2) -> void:
	for i in _cables.size():
		var c: Dictionary = _cables[i]
		if _to_screen(_endpoint_master(c.get("start", {}))).distance_to(p) <= 11.0:
			_sel = {"kind": "cable", "idx": i, "end": "start"}; _dragging = true; _redraw(); return
		if _to_screen(_endpoint_master(c.get("end", {}))).distance_to(p) <= 11.0:
			_sel = {"kind": "cable", "idx": i, "end": "end"}; _dragging = true; _redraw(); return
	for i in _sockets.size():
		if _to_screen(_socket_pos(str(_sockets[i].get("id", "")))).distance_to(p) <= 16.0:
			_sel = {"kind": "socket", "idx": i}; _dragging = true; _redraw(); return
	_sel = {}; _redraw()


func _drag_to(p: Vector2) -> void:
	var m := _to_master(p)
	if _sel.get("kind") == "cable":
		var c: Dictionary = _cables[_sel["idx"]]
		_set_endpoint_master(c[_sel["end"]], m)
	elif _sel.get("kind") == "socket":
		_sockets[_sel["idx"]]["pos"] = [snappedf(m.x, 0.5), snappedf(m.y, 0.5)]
	_redraw()


## Loslassen: Kabelende nahe einer Steckdose → daran andocken.
func _release() -> void:
	if _dragging and _sel.get("kind") == "cable":
		var c: Dictionary = _cables[_sel["idx"]]
		var end_screen := _to_screen(_endpoint_master(c[_sel["end"]]))
		for s: Dictionary in _sockets:
			if _to_screen(_socket_pos(str(s.get("id", "")))).distance_to(end_screen) <= 18.0:
				c[_sel["end"]] = {"socket": str(s["id"]), "offset": [0, 0]}
				break
	_dragging = false
	_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT, KEY_PAGEUP:
			if not _devices.is_empty():
				_focus = wrapi(_focus - 1, -1, _devices.size())
				_frame_focus()
		KEY_RIGHT, KEY_PAGEDOWN:
			if not _devices.is_empty():
				_focus = wrapi(_focus + 1, -1, _devices.size())
				_frame_focus()
		KEY_A:
			_add_cable_on_focus()
		KEY_V:
			_cycle_focused_model()
		KEY_N:
			_add_socket("wall")
		KEY_M:
			_add_socket("strip")
		KEY_DELETE, KEY_BACKSPACE:
			if _sel.get("kind") == "socket":
				_sockets.remove_at(_sel["idx"]); _sel = {}; _redraw()
			elif _sel.get("kind") == "cable":
				_cables.remove_at(_sel["idx"]); _sel = {}; _rebuild_devices(); _redraw()
		KEY_0:
			_focus = -1
			_comp.editor_reset_view(); _redraw()
		KEY_F8:
			_save()
		KEY_S:
			if event.ctrl_pressed:
				_save()


## Neues Kabel am fokussierten Gerät beginnen (ein weiterer Anschluss/Port), Ende
## liegt daneben und wird gezogen. Ohne Fokus: am ersten Gerät.
func _add_cable_on_focus() -> void:
	var dev := _focus_device()
	if dev == "" and not _devices.is_empty():
		dev = _devices[0]
	if dev == "":
		return
	_cables.append({
		"id": "CABLE_%s_%02d" % [dev.to_upper(), _cables.size() + 1],
		"start": {"object": dev, "offset": [0.0, -40.0]},
		"end": {"object": dev, "offset": [50.0, -40.0]},
		"color": [0.2, 0.2, 0.2], "thickness": 3.0, "segments": 24.0,
		"slack": 1.12, "z": 7.0})
	_sel = {"kind": "cable", "idx": _cables.size() - 1, "end": "end"}
	_rebuild_devices()
	_redraw()


func _add_socket(kind: String) -> void:
	var center := _to_master(size * 0.5)
	var n := 1
	for s: Dictionary in _sockets:
		n += 1
	_sockets.append({
		"id": "SOCKET_%s_%02d" % [kind.to_upper(), n],
		"type": kind, "pos": [snappedf(center.x, 0.5), snappedf(center.y, 0.5)],
		"outlets": 4 if kind == "strip" else 2})
	_sel = {"kind": "socket", "idx": _sockets.size() - 1}
	_redraw()


func _save() -> void:
	_cfg["cables"] = _cables
	_cfg["sockets"] = _sockets
	var wf := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if wf != null:
		wf.store_string(JSON.stringify(_cfg, "\t", false))


func _redraw() -> void:
	if _giz != null:
		_giz.queue_redraw()


# ------------------------------------------------------------- Zeichnen (via CableGiz)
func paint_gizmos(ci: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	var dev := _focus_device()
	# Steckdosen zuerst (unter den Kabelenden)
	for i in _sockets.size():
		_draw_socket(ci, font, _sockets[i], i == _sel.get("idx", -1) and _sel.get("kind") == "socket")
	# Kabel als leicht durchhängende Linie + Endgriffe. Bei Gerätefokus gehören
	# die Anschlüsse des Geräts hervorgehoben, alle anderen gedimmt.
	for i in _cables.size():
		var c: Dictionary = _cables[i]
		var s_spec: Variant = c.get("start", {})
		var e_spec: Variant = c.get("end", {})
		var a := _to_screen(_endpoint_master(s_spec))
		var b := _to_screen(_endpoint_master(e_spec))
		var s_hit: bool = dev != "" and s_spec is Dictionary and str(s_spec.get("object", "")) == dev
		var e_hit: bool = dev != "" and e_spec is Dictionary and str(e_spec.get("object", "")) == dev
		var dim: float = 0.25 if (dev != "" and not (s_hit or e_hit)) else 1.0
		var rgb: Array = c.get("color", [0.8, 0.8, 0.8])
		_draw_cable(ci, a, b, Color(rgb[0], rgb[1], rgb[2], dim), float(c.get("slack", 1.15)))
		var sel_s: bool = _sel.get("kind") == "cable" and _sel.get("idx") == i and _sel.get("end") == "start"
		var sel_e: bool = _sel.get("kind") == "cable" and _sel.get("idx") == i and _sel.get("end") == "end"
		_handle(ci, a, Color(0.35, 0.95, 0.45, dim), sel_s or s_hit)
		_handle(ci, b, Color(0.95, 0.4, 0.4, dim), sel_e or e_hit)
		if dim > 0.5:
			ci.draw_string(font, (a + b) * 0.5 + Vector2(4, -4), str(c.get("id", "")),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.9, 0.95, 0.8))
	# Kopfzeile: Gesamt oder Gerätefokus mit Anschlusszahl
	var head := "KABEL-EDITOR   %d Kabel · %d Steckdosen" % [_cables.size(), _sockets.size()]
	if dev != "":
		head = "KABEL-EDITOR   ◄ %s ►   (%d/%d)  ·  %d Anschlüsse" % [
			dev, _focus + 1, _devices.size(), _focus_ports().size()]
	ci.draw_string(font, Vector2(16, 26), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color(0.4, 0.95, 0.5) if dev != "" else Color(0.95, 0.85, 0.4))
	ci.draw_string(font, Vector2(16, size.y - 14),
		"←/→ Gerät fokussieren · V Modellvariante · A neuer Anschluss · Enden ziehen · nahe Steckdose andocken · N Dose · M Verteiler · Entf löschen · Rad Zoom · Mitte schieben · F8 speichern",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))


## Kabel: quadratischer Durchhang zwischen a und b.
func _draw_cable(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, slack: float) -> void:
	var sag: float = a.distance_to(b) * (slack - 1.0) * 1.6
	var mid := (a + b) * 0.5 + Vector2(0, sag)
	var pts := PackedVector2Array()
	for i in 17:
		var s := float(i) / 16.0
		pts.append(a.lerp(mid, s).lerp(mid.lerp(b, s), s))  # quadratische Bézier
	ci.draw_polyline(pts, Color(0, 0, 0, 0.3), 4.0, true)
	ci.draw_polyline(pts, col, 3.0, true)


func _handle(ci: CanvasItem, p: Vector2, col: Color, sel: bool) -> void:
	ci.draw_circle(p, 7.0, Color(0, 0, 0, 0.5))
	ci.draw_circle(p, 5.5, col)
	if sel:
		ci.draw_arc(p, 9.0, 0, TAU, 20, Color(1, 0.95, 0.3), 2.0)


## Steckdose/Verteiler schematisch: Wand = 2 Löcher, Verteiler = Leiste + Schalter.
func _draw_socket(ci: CanvasItem, font: Font, s: Dictionary, sel: bool) -> void:
	var t := _t()
	var p := _to_screen(_socket_pos(str(s.get("id", ""))))
	var sc: float = t["scale"]
	var strip: bool = str(s.get("type", "wall")) == "strip"
	var outlets: int = int(s.get("outlets", 2))
	var w: float = (16.0 * outlets if strip else 34.0) * sc * 0.6
	var h: float = 22.0 * sc * 0.6
	var r := Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h))
	ci.draw_rect(r, Color(0.14, 0.14, 0.17))
	ci.draw_rect(r, Color(0.85, 0.85, 0.9) if not strip else Color(0.9, 0.86, 0.55), false, 2.0)
	if strip:
		for k in outlets:
			var cx := r.position.x + (float(k) + 0.5) / float(outlets) * r.size.x
			ci.draw_rect(Rect2(cx - 3, r.get_center().y - 4, 6, 8), Color(0.05, 0.05, 0.07))
		ci.draw_rect(Rect2(r.end.x - 6, r.position.y + 2, 4, 5), Color(0.9, 0.3, 0.25))  # Schalter
	else:
		for dx in [-6.0, 6.0]:
			ci.draw_circle(r.get_center() + Vector2(dx, 0), 2.5, Color(0.05, 0.05, 0.07))
	if sel:
		ci.draw_rect(r.grow(3.0), Color(1, 0.95, 0.3), false, 2.0)
	ci.draw_string(font, r.position + Vector2(0, -4),
		"Verteiler" if strip else "Steckdose", HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
		Color(1, 0.9, 0.5))
