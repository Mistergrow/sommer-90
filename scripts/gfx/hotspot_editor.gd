class_name HotspotEditor
extends Control
## Layout-Editor für Orts-Hotspots — die "Deko-Werkstatt" der Orte, aber in einer
## EIGENEN Editor-Szene (scenes/previews/<Ort>Preview.tscn). Öffnen und mit F6 starten:
## der Ort wird geladen, alle klickbaren Bereiche erscheinen als verschiebbare
## Rechtecke. Kein In-Game-Umschalten — der Editor ist hier immer aktiv, F8
## SPEICHERT nur (schließt nicht).
##
## Steuerung: Ziehen = verschieben · Ecken-Griffe / Mausrad = Größe ·
## Pfeiltasten = fein (Shift = grob) · Tab = nächster Hotspot · H = Hilfe ·
## A = nächster sichtbarer Akteur · F8 / Strg+S = alles speichern.

const SAVE_PATH := "res://data/location_hotspots.json"
const HANDLE := 10.0   # Griffgröße (Bildschirm-Pixel)
const MIN_V := 12.0    # kleinste Hotspot-Kantenlänge (virtuelle Pixel)

var location: LocationBase

var _sel := 0
var _actor_sel := -1
var _mode := ""        # "" | "move" | "nw"|"ne"|"sw"|"se"
var _grab := Vector2.ZERO
var _start := Rect2()
var _help := true
var _flash := 0.0      # kurzes "Gespeichert"-Aufblinken


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 45
	focus_mode = Control.FOCUS_ALL
	grab_focus.call_deferred()
	# Anker UND Offsets atomar setzen: das füllt auch einen Nicht-Container-Parent,
	# ohne Godots Anchor/Size-Warnung zu erzeugen.
	_fit_parent()
	if location != null:
		location.set_hotspots_interactive(false)  # Klicks gehören dem Editor
		# Bei Orten mit sichtbaren Laufzeit-Aktoren wird sofort die Figur gewählt.
		# Der Nutzer muss sie nicht erst zwischen großflächigen Hotspots suchen.
		if not _actors().is_empty():
			_actor_sel = 0
			_sel = -1
	set_process(true)


## Füllt den (Nicht-Container-)Eltern-Control, damit der Editor die ganze
## Klickfläche abdeckt.
func _fit_parent() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	queue_redraw()  # folgt Layout-/Größenänderungen live


func _defs() -> Array:
	return location.rect_hotspots() if location != null else []


func _actors() -> Array:
	return location.editable_depth_actors() if location != null else []


func _screen_rect(def: Dictionary) -> Rect2:
	var local_rect := location.vrect(def["rect"])
	var into_editor := get_global_transform().affine_inverse() * location.get_global_transform()
	var top_left: Vector2 = into_editor * local_rect.position
	var bottom_right: Vector2 = into_editor * local_rect.end
	return Rect2(top_left.min(bottom_right), (bottom_right - top_left).abs())


## Der Akteur-Rechteckrahmen wird vom tatsächlich gerenderten Laufzeit-Control
## gelesen. Damit ist die Editoransicht WYSIWYG inklusive Cover-Skalierung und
## neutraler 2,5D-Projektion.
func _control_screen_rect(control: Control) -> Rect2:
	if control == null or not is_instance_valid(control):
		return Rect2()
	var into_editor := get_global_transform().affine_inverse() * control.get_global_transform()
	var top_left: Vector2 = into_editor * Vector2.ZERO
	var bottom_right: Vector2 = into_editor * control.size
	return Rect2(top_left.min(bottom_right), (bottom_right - top_left).abs())


func _actor_screen_rect(def: Dictionary) -> Rect2:
	return _control_screen_rect(def.get("node") as Control)


func _editor_to_virtual(point: Vector2) -> Vector2:
	var into_location := location.get_global_transform().affine_inverse() * get_global_transform()
	return location.to_virtual(into_location * point)


# ---------------------------------------------------------------- Eingabe

func _gui_input(event: InputEvent) -> void:
	var defs := _defs()
	if defs.is_empty() and _actors().is_empty():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_mode = ""
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scale_selected(1.06); accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scale_selected(1.0 / 1.06); accept_event()
	elif event is InputEventMouseMotion and _mode != "":
		_drag_to(event.position)
		accept_event()


func _begin_drag(pos: Vector2) -> void:
	var defs := _defs()
	var actors := _actors()
	# Sichtbare Laufzeit-Aktoren haben Vorrang vor großen Markt-Hotspots. So kann
	# der Händler direkt an seiner Figur gegriffen werden.
	if _actor_sel >= 0 and _actor_sel < actors.size():
		var selected_actor_rect := _actor_screen_rect(actors[_actor_sel])
		var actor_corner := _corner_at(selected_actor_rect, pos)
		if actor_corner != "":
			_begin_actor_drag(_actor_sel, actor_corner, pos)
			return
		if selected_actor_rect.has_point(pos):
			_begin_actor_drag(_actor_sel, "move", pos)
			return
	for i in range(actors.size() - 1, -1, -1):
		var actor_rect := _actor_screen_rect(actors[i])
		var actor_corner := _corner_at(actor_rect, pos)
		if actor_corner != "" or actor_rect.has_point(pos):
			_begin_actor_drag(i, actor_corner if actor_corner != "" else "move", pos)
			return
	# Der AUSGEWÄHLTE Hotspot hat Vorrang: erst seine Ecken (Größe), dann sein
	# Körper (Verschieben) — auch wenn er unter einem anderen liegt. So ist ein
	# per Tab gewählter, verdeckter Rahmen immer mit der Maus greifbar.
	if _sel >= 0 and _sel < defs.size():
		var r := _screen_rect(defs[_sel])
		var corner := _corner_at(r, pos)
		if corner != "":
			_actor_sel = -1
			_mode = corner
			_grab = pos
			_start = defs[_sel]["rect"]
			return
		if r.has_point(pos):
			_actor_sel = -1
			_mode = "move"
			_grab = pos
			_start = defs[_sel]["rect"]
			return
	# sonst den obersten Hotspot unter dem Cursor auswählen und verschieben
	for i in range(defs.size() - 1, -1, -1):
		if _screen_rect(defs[i]).has_point(pos):
			_sel = i
			_actor_sel = -1
			_mode = "move"
			_grab = pos
			_start = defs[i]["rect"]
			return
	_mode = ""


func _begin_actor_drag(index: int, mode: String, pos: Vector2) -> void:
	var actors := _actors()
	if index < 0 or index >= actors.size():
		return
	_actor_sel = index
	_sel = -1
	_mode = mode
	_grab = pos
	_start = actors[index].get("rect", Rect2())


func _corner_at(r: Rect2, p: Vector2) -> String:
	var h := HANDLE
	if Rect2(r.position - Vector2(h, h) * 0.5, Vector2(h, h)).has_point(p): return "nw"
	if Rect2(Vector2(r.end.x, r.position.y) - Vector2(h, h) * 0.5, Vector2(h, h)).has_point(p): return "ne"
	if Rect2(Vector2(r.position.x, r.end.y) - Vector2(h, h) * 0.5, Vector2(h, h)).has_point(p): return "sw"
	if Rect2(r.end - Vector2(h, h) * 0.5, Vector2(h, h)).has_point(p): return "se"
	return ""


func _drag_to(pos: Vector2) -> void:
	var defs := _defs()
	var actors := _actors()
	if (_actor_sel < 0 or _actor_sel >= actors.size()) \
			and (_sel < 0 or _sel >= defs.size()):
		return
	var dv: Vector2 = _editor_to_virtual(pos) - _editor_to_virtual(_grab)
	var r := _start
	match _mode:
		"move": r.position += dv
		"nw": r.position += dv; r.size -= dv
		"ne": r.position.y += dv.y; r.size += Vector2(dv.x, -dv.y)
		"sw": r.position.x += dv.x; r.size += Vector2(-dv.x, dv.y)
		"se": r.size += dv
	if _actor_sel >= 0 and _actor_sel < actors.size():
		location.set_editable_actor_rect(actors[_actor_sel], _sanitize(r))
	else:
		location.set_hotspot_rect(defs[_sel], _sanitize(r))


func _scale_selected(f: float) -> void:
	var actors := _actors()
	if _actor_sel >= 0 and _actor_sel < actors.size():
		var actor_rect: Rect2 = actors[_actor_sel].get("rect", Rect2())
		var actor_center := actor_rect.get_center()
		actor_rect.size *= f
		actor_rect.position = actor_center - actor_rect.size * 0.5
		location.set_editable_actor_rect(actors[_actor_sel], _sanitize(actor_rect))
		return
	var defs := _defs()
	if _sel < 0 or _sel >= defs.size():
		return
	var r: Rect2 = defs[_sel]["rect"]
	var c := r.get_center()
	r.size *= f
	r.position = c - r.size * 0.5
	location.set_hotspot_rect(defs[_sel], _sanitize(r))


func _sanitize(r: Rect2) -> Rect2:
	if r.size.x < MIN_V: r.size.x = MIN_V
	if r.size.y < MIN_V: r.size.y = MIN_V
	return r


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var defs := _defs()
	match event.keycode:
		KEY_F8:
			_save(); accept_event()
		KEY_S:
			if event.ctrl_pressed:
				_save(); accept_event()
		KEY_TAB:
			if not defs.is_empty():
				_actor_sel = -1
				_sel = (_sel + 1) % defs.size()
			accept_event()
		KEY_A:
			var actors := _actors()
			if not actors.is_empty():
				_sel = -1
				_actor_sel = (_actor_sel + 1) % actors.size()
			accept_event()
		KEY_R:
			var actors := _actors()
			if _actor_sel >= 0 and _actor_sel < actors.size():
				location.reset_editable_actor_rect(actors[_actor_sel])
			accept_event()
		KEY_H:
			_help = not _help
			accept_event()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var actors := _actors()
			if _actor_sel >= 0 and _actor_sel < actors.size():
				var actor_step: float = 10.0 if event.shift_pressed else 1.0
				var actor_delta := Vector2.ZERO
				if event.keycode == KEY_LEFT: actor_delta.x = -actor_step
				elif event.keycode == KEY_RIGHT: actor_delta.x = actor_step
				elif event.keycode == KEY_UP: actor_delta.y = -actor_step
				else: actor_delta.y = actor_step
				var actor_rect: Rect2 = actors[_actor_sel].get("rect", Rect2())
				actor_rect.position += actor_delta
				location.set_editable_actor_rect(actors[_actor_sel], actor_rect)
			elif _sel >= 0 and _sel < defs.size():
				var step: float = 10.0 if event.shift_pressed else 1.0
				var d := Vector2.ZERO
				if event.keycode == KEY_LEFT: d.x = -step
				elif event.keycode == KEY_RIGHT: d.x = step
				elif event.keycode == KEY_UP: d.y = -step
				else: d.y = step
				var r: Rect2 = defs[_sel]["rect"]
				r.position += d
				location.set_hotspot_rect(defs[_sel], r)
			accept_event()


func _save() -> void:
	if location == null:
		return
	var data := LocationBase._read_overrides()
	var rects: Array = []
	for def in _defs():
		var r: Rect2 = def["rect"]
		rects.append([roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)])
	data[location.location_key()] = rects
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  ", false))
	var actors_saved := location.save_editable_actor_layouts()
	_flash = 1.2
	print("[HotspotEditor] gespeichert → %s + %s  (%s: %d Hotspots, %d Akteure, actor_ok=%s)" % [
		SAVE_PATH, LocationBase.ACTOR_LAYOUT_OVERRIDES, location.location_key(),
		rects.size(), _actors().size(), actors_saved,
	])


# ---------------------------------------------------------------- Zeichnen

func _draw() -> void:
	var defs := _defs()
	var actors := _actors()
	var font := get_theme_default_font()
	for i in defs.size():
		var r := _screen_rect(defs[i])
		var selected := i == _sel
		var col: Color = Color(1.0, 0.75, 0.2) if selected else Color(0.5, 0.8, 1.0)
		draw_rect(r, Color(col.r, col.g, col.b, 0.16), true)
		draw_rect(r, col, false, 2.0 if selected else 1.0)
		draw_string(font, r.position + Vector2(4, 14),
			"%d  %s" % [i + 1, location.hotspot_label(defs[i])],
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 6, 12, Color(1, 1, 1, 0.95))
		var vr: Rect2 = defs[i]["rect"]
		draw_string(font, r.position + Vector2(4, r.size.y - 5),
			"%d×%d" % [int(vr.size.x), int(vr.size.y)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
	# Sichtbare Akteure erhalten einen eigenen grünen Rahmen. Er liegt über den
	# großflächigen Markt-Hotspots und entspricht dem echten Spawn-Rechteck.
	for i in actors.size():
		var actor_rect := _actor_screen_rect(actors[i])
		var actor_selected := i == _actor_sel
		var actor_color := Color(0.45, 1.0, 0.55) if actor_selected else Color(0.35, 0.82, 0.48, 0.82)
		draw_rect(actor_rect, Color(actor_color.r, actor_color.g, actor_color.b, 0.10), true)
		draw_rect(actor_rect, actor_color, false, 3.0 if actor_selected else 1.5)
		draw_string(font, actor_rect.position + Vector2(4, -5),
			"AKTEUR · %s" % str(actors[i].get("label", "?")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, actor_color)
	# Ausgewählte Elemente ZULETZT (über allen anderen) zeichnen — Umriss + Griffe
	# bleiben sichtbar/greifbar, auch wenn er unter einem anderen Rahmen liegt.
	if _sel >= 0 and _sel < defs.size():
		var r := _screen_rect(defs[_sel])
		var col := Color(1.0, 0.75, 0.2)
		draw_rect(r, Color(col.r, col.g, col.b, 0.16), true)
		draw_rect(r, col, false, 2.0)
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y),
				Vector2(r.position.x, r.end.y), r.end]:
			draw_rect(Rect2(c - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), col, true)
			draw_rect(Rect2(c - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), Color.BLACK, false, 1.0)
	if _actor_sel >= 0 and _actor_sel < actors.size():
		var actor := actors[_actor_sel] as Dictionary
		var actor_rect := _actor_screen_rect(actor)
		var actor_color := Color(0.45, 1.0, 0.55)
		var hotspot_def: Dictionary = actor.get("hotspot_def", {})
		var hotspot_button := hotspot_def.get("button") as Control
		if hotspot_button != null:
			var hotspot_rect := _control_screen_rect(hotspot_button)
			draw_rect(hotspot_rect, Color(0.9, 0.35, 1.0, 0.10), true)
			draw_rect(hotspot_rect, Color(0.9, 0.35, 1.0, 0.72), false, 1.5)
			draw_string(font, hotspot_rect.position + Vector2(4, 14), "KLICKZONE · FOLGT AUTOMATISCH",
				HORIZONTAL_ALIGNMENT_LEFT, hotspot_rect.size.x - 8, 10, Color(1.0, 0.65, 1.0))
		draw_rect(actor_rect, actor_color, false, 3.0)
		for c: Vector2 in [actor_rect.position, Vector2(actor_rect.end.x, actor_rect.position.y),
				Vector2(actor_rect.position.x, actor_rect.end.y), actor_rect.end]:
			draw_rect(Rect2(c - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), actor_color, true)
			draw_rect(Rect2(c - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), Color.BLACK, false, 1.0)
	if _help:
		_draw_help(font)
	if _flash > 0.0:
		var s := "✔ GESPEICHERT — Hotspots + Akteur-Layout"
		draw_string(font, Vector2(18, size.y - 22), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.5, 1.0, 0.5, clampf(_flash, 0.0, 1.0)))


func _draw_help(font: Font) -> void:
	var lines := [
		"LAYOUT-EDITOR — %s" % location.location_key(),
		"GRÜN = echter Spiel-Akteur   BLAU/GELB = Hotspot",
		"Figur anklicken/ziehen · Ecken/Mausrad = Skalierung",
		"A = Akteur wählen   R = Akteur zurücksetzen",
		"Pfeile = fein (Shift grob)   Tab = nächster Hotspot",
		"H = Hilfe aus   F8 / Strg+S = SPEICHERN",
	]
	var box := Rect2(Vector2(10, 10), Vector2(470, 16.0 * lines.size() + 10.0))
	draw_rect(box, Color(0, 0, 0, 0.72), true)
	draw_rect(box, Color(1, 0.75, 0.2, 0.8), false, 1.0)
	for i in lines.size():
		var c: Color = Color(1, 0.82, 0.4) if i == 0 else Color(0.9, 0.9, 0.9)
		draw_string(font, Vector2(18, 28 + i * 16), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12 if i == 0 else 11, c)
