extends Control
## Projektweiter Editor für Architekturflächen aller fotografischen Levels.
## Öffnen: scenes/editors/SurfaceEditor.tscn, F6. F8 speichert. Die Punkte liegen als
## UV-Koordinaten 0..1 in data/location_surfaces.json und sind auflösungsfest.

const DATA_PATH := "res://data/location_surfaces.json"
const PROFILE_PATH := "res://data/location_25d.json"
const BG_DIR := "res://assets/backgrounds/locations"
const SurfaceGeometryScript := preload("res://scripts/gfx/surface_geometry.gd")

const KINDS := [&"floor", &"wall", &"ceiling", &"window"]
const KIND_LABEL := {
	&"floor": "BODEN", &"wall": "WAND", &"ceiling": "DECKE",
	&"window": "FENSTER/ÖFFNUNG",
}
const KIND_COLOR := {
	&"floor": Color(0.20, 0.84, 1.0),
	&"wall": Color(1.0, 0.70, 0.20),
	&"ceiling": Color(0.68, 0.48, 1.0),
	&"window": Color(0.30, 1.0, 0.76),
}
const TOOLBAR_H := 92.0
const FOOTER_H := 34.0
const HANDLE_RADIUS := 8.0

var _font: Font
var _data: Dictionary = {}
var _profiles: Dictionary = {}
var _keys: Array[String] = []
var _key := "ROOM_MASTER"
var _background: Texture2D = null
var _foreground: Texture2D = null
var _room_desk: Texture2D = null
var _show_foreground := false

var _location_select: OptionButton
var _kind_select: OptionButton
var _surface_select: OptionButton
var _wall_role_select: OptionButton
var _depth_label: Label
var _status: Label
var _foreground_button: Button

var _selected := -1
var _draft: Dictionary = {}
var _drawing := false
var _drag_vertex := -1
var _drag_surface := false
var _drag_start_uv := Vector2.ZERO
var _drag_points: Array = []
var _panning := false
var _zoom := 1.0
var _pan := Vector2.ZERO
var _art_rect := Rect2()
var _dirty := false
var _flash_until := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = load("res://assets/fonts/VT323_UI.ttf")
	_load_data()
	_load_profiles()
	_build_location_registry()
	_build_toolbar()
	_select_location(0)
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	if _flash_until > 0 and Time.get_ticks_msec() > _flash_until:
		_flash_until = 0
		_update_status()


func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = TOOLBAR_H
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.06, 0.98)
	style.border_color = Color(0.22, 0.72, 0.92, 0.8)
	style.border_width_bottom = 1
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 7)
	rows.add_child(top)
	top.add_child(_label("LEVEL", Color(0.50, 0.86, 1.0)))
	_location_select = OptionButton.new()
	_location_select.custom_minimum_size.x = 290
	for key: String in _keys:
		_location_select.add_item(_display_name(key))
		_location_select.set_item_metadata(_location_select.item_count - 1, key)
	_location_select.item_selected.connect(_select_location)
	top.add_child(_location_select)
	top.add_child(_button("◀", func() -> void: _cycle_location(-1), "Vorheriges Level"))
	top.add_child(_button("▶", func() -> void: _cycle_location(1), "Nächstes Level"))
	top.add_child(_label("FLÄCHE", Color(1.0, 0.78, 0.34)))
	_kind_select = OptionButton.new()
	for kind: StringName in KINDS:
		_kind_select.add_item(str(KIND_LABEL[kind]))
		_kind_select.set_item_metadata(_kind_select.item_count - 1, kind)
	_kind_select.item_selected.connect(_on_kind_selected)
	top.add_child(_kind_select)
	_wall_role_select = OptionButton.new()
	for role: String in ["AUTO", "LINKS", "RÜCKWAND", "RECHTS"]:
		_wall_role_select.add_item(role)
	_wall_role_select.set_item_metadata(0, "auto")
	_wall_role_select.set_item_metadata(1, "left")
	_wall_role_select.set_item_metadata(2, "back")
	_wall_role_select.set_item_metadata(3, "right")
	_wall_role_select.tooltip_text = Loc.t("misc.surface_editor.perspektivrolle_ausgewahlten_wand", "Perspektivrolle der ausgewählten Wand")
	_wall_role_select.item_selected.connect(_on_wall_role_selected)
	top.add_child(_wall_role_select)
	var new_button := _button(Loc.t("misc.surface_editor.neu", "＋ NEU"), _new_surface, "Neue freie Polygonfläche beginnen [N]")
	new_button.add_theme_color_override("font_color", Color(0.50, 1.0, 0.65))
	top.add_child(new_button)
	top.add_child(_button(Loc.t("misc.surface_editor.schliessen", "✓ SCHLIESSEN"), _finish_surface, "Polygon schließen [Enter/Doppelklick]"))
	top.add_child(_button(Loc.t("misc.surface_editor.punkt", "↶ PUNKT"), _undo_point, "Letzten neuen Eckpunkt entfernen [Rechtsklick]"))
	top.add_child(_button("🗑", _delete_selected, "Ausgewählte Fläche löschen [Entf]"))
	top.add_child(_button(Loc.t("misc.surface_editor.f8", "💾 F8"), _save, "Alle Level speichern [F8/Strg+S]"))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 7)
	rows.add_child(bottom)
	bottom.add_child(_label("AUSWAHL", Color(0.70, 0.76, 0.84)))
	_surface_select = OptionButton.new()
	_surface_select.custom_minimum_size.x = 245
	_surface_select.item_selected.connect(_on_surface_selected)
	bottom.add_child(_surface_select)
	bottom.add_child(_button(Loc.t("misc.surface_editor.fern", "FERN −"), func() -> void: _adjust_depth("depth_far", -0.04), "Ferne Tiefe verringern"))
	bottom.add_child(_button(Loc.t("misc.surface_editor.fern_a50c", "FERN ＋"), func() -> void: _adjust_depth("depth_far", 0.04), "Ferne Tiefe erhöhen"))
	bottom.add_child(_button(Loc.t("misc.surface_editor.nah", "NAH −"), func() -> void: _adjust_depth("depth_near", -0.04), "Nahe Tiefe verringern"))
	bottom.add_child(_button(Loc.t("misc.surface_editor.nah_97be", "NAH ＋"), func() -> void: _adjust_depth("depth_near", 0.04), "Nahe Tiefe erhöhen"))
	_depth_label = _label("FERN — · NAH —", Color(0.82, 0.92, 1.0))
	_depth_label.custom_minimum_size.x = 150
	bottom.add_child(_depth_label)
	_foreground_button = _button(Loc.t("misc.surface_editor.mobel_vordergrund_an", "MÖBEL/VORDERGRUND AN"), _toggle_foreground,
		"Vordergrund zum Markieren verdeckter Architektur ein-/ausblenden [F]")
	bottom.add_child(_foreground_button)
	bottom.add_child(_button(Loc.t("misc.surface_editor.ansicht_0", "ANSICHT 0"), _reset_view, "Zoom und Verschiebung zurücksetzen [0]"))

	_status = _label("", Color(0.76, 0.84, 0.90))
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 12
	_status.offset_right = -12
	_status.offset_top = -FOOTER_H + 5
	_status.offset_bottom = -4
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, callback: Callable, tip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	return button


func _load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) \
		if FileAccess.file_exists(DATA_PATH) else null
	_data = parsed as Dictionary if parsed is Dictionary else {
		"version": 1, "locations": {},
	}
	if not _data.get("locations", {}) is Dictionary:
		_data["locations"] = {}


func _load_profiles() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if parsed is Dictionary and (parsed as Dictionary).get("profiles", {}) is Dictionary:
		_profiles = (parsed as Dictionary)["profiles"]


func _build_location_registry() -> void:
	_keys = ["ROOM_MASTER"]
	var profile_keys: Array = _profiles.keys()
	profile_keys.sort()
	for value: Variant in profile_keys:
		_keys.append(str(value))


func _select_location(index: int) -> void:
	if index < 0 or index >= _keys.size():
		return
	_cancel_draft(false)
	_key = _keys[index]
	_location_select.select(index)
	_selected = -1
	_background = _load_background(_key)
	_foreground = _load_foreground(_key)
	_room_desk = _texture("res://assets/backgrounds/layers/ROOM_DESK_MASTER_V02.png") \
		if _key == "ROOM_MASTER" else null
	# Architekturpass: nur der nackte Master. Separierte Möbel-/Near-Plane-
	# Assets bleiben standardmäßig aus und können nur als Referenz eingeblendet
	# werden. Laufzeit-Aktoren, Props, FX und Hotspots werden nie erzeugt.
	_show_foreground = false
	_reset_view()
	_refresh_surface_list()
	_update_foreground_button()
	_sync_wall_role()
	_update_status()
	queue_redraw()


## Öffentlicher Preview-Vertrag: Orts-Previews können den gemeinsamen Editor
## direkt mit ihrem eigenen Hintergrund öffnen, ohne dass der Nutzer im
## LEVEL-Menü erneut suchen muss.
func select_location_key(location_key: String) -> bool:
	var index := _keys.find(location_key)
	if index < 0:
		return false
	_select_location(index)
	return true


func current_location_key() -> String:
	return _key


func _cycle_location(direction: int) -> void:
	_select_location(wrapi(_keys.find(_key) + direction, 0, _keys.size()))


func _load_background(key: String) -> Texture2D:
	if key == "ROOM_MASTER":
		return _texture("res://assets/backgrounds/layers/ROOM_EMPTY_SHELVES_MASTER_V02.png")
	for version in range(9, 0, -1):
		var path := "%s/%s_V%02d.png" % [BG_DIR, key, version]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _load_foreground(key: String) -> Texture2D:
	if key == "ROOM_MASTER":
		return null
	var profile: Dictionary = _profiles.get(key, {})
	var path := str(profile.get("foreground_asset", ""))
	return _texture(path)


func _texture(path: String) -> Texture2D:
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null


func _display_name(key: String) -> String:
	if key == "ROOM_MASTER":
		return "ZIMMER · ROOM MASTER"
	return key.trim_prefix("LOCATION_").trim_suffix("_MASTER").replace("_", " ")


func _location_entry(create := true) -> Dictionary:
	var locations := _data["locations"] as Dictionary
	if not locations.has(_key):
		if not create:
			return {}
		locations[_key] = {"surfaces": []}
	var entry: Variant = locations[_key]
	if not entry is Dictionary:
		if not create:
			return {}
		entry = {"surfaces": []}
		locations[_key] = entry
	if not (entry as Dictionary).get("surfaces", []) is Array:
		(entry as Dictionary)["surfaces"] = []
	return entry as Dictionary


func _surfaces() -> Array:
	return _location_entry()["surfaces"] as Array


func _current_surface() -> Dictionary:
	if _drawing:
		return _draft
	var surfaces := _surfaces()
	return surfaces[_selected] as Dictionary if _selected >= 0 and _selected < surfaces.size() else {}


func _new_surface() -> void:
	if _drawing:
		_flash("Erst die aktuelle Fläche schließen oder mit Esc abbrechen.", Color(1.0, 0.72, 0.30))
		return
	var kind := _selected_kind()
	var depths: Vector2 = SurfaceGeometryScript.default_depths(kind)
	_draft = {
		"id": _next_id(kind), "type": str(kind), "points": [],
		"depth_far": snappedf(depths.x, 0.01),
		"depth_near": snappedf(depths.y, 0.01),
	}
	if kind == &"wall":
		_draft["wall_role"] = "auto"
	_drawing = true
	_selected = -1
	_refresh_surface_list()
	_update_depth_label()
	_flash("Punkte setzen · Doppelklick/Enter schließt · Rechtsklick nimmt den letzten zurück.",
		Color(0.45, 1.0, 0.68), 5.0)
	queue_redraw()


func _next_id(kind: StringName) -> String:
	var used := {}
	for raw: Variant in _surfaces():
		if raw is Dictionary:
			used[str((raw as Dictionary).get("id", ""))] = true
	var number := 1
	while used.has("%s_%02d" % [kind, number]):
		number += 1
	return "%s_%02d" % [kind, number]


func _finish_surface() -> void:
	if not _drawing:
		return
	var error := SurfaceGeometryScript.validate_surface(_draft)
	if not error.is_empty():
		_flash("Fläche noch nicht gültig: %s." % error, Color(1.0, 0.42, 0.38), 4.0)
		return
	_surfaces().append(_draft.duplicate(true))
	_selected = _surfaces().size() - 1
	_draft = {}
	_drawing = false
	_dirty = true
	_refresh_surface_list()
	_update_depth_label()
	_flash("Fläche geschlossen. F8 speichert alle Level.", Color(0.45, 1.0, 0.68))
	queue_redraw()


func _cancel_draft(show_message := true) -> void:
	if not _drawing:
		return
	_draft = {}
	_drawing = false
	if show_message:
		_flash("Neue Fläche verworfen.", Color(0.84, 0.78, 0.62))
	_refresh_surface_list()
	queue_redraw()


func _undo_point() -> void:
	if not _drawing:
		return
	var points := _draft.get("points", []) as Array
	if not points.is_empty():
		points.pop_back()
	queue_redraw()


func _delete_selected() -> void:
	if _drawing:
		_cancel_draft()
		return
	if _selected < 0 or _selected >= _surfaces().size():
		return
	_surfaces().remove_at(_selected)
	_selected = mini(_selected, _surfaces().size() - 1)
	_dirty = true
	_refresh_surface_list()
	_update_depth_label()
	_flash("Fläche gelöscht. F8 übernimmt die Änderung.", Color(1.0, 0.65, 0.38))
	queue_redraw()


func _selected_kind() -> StringName:
	var value: Variant = _kind_select.get_item_metadata(_kind_select.selected)
	return StringName(str(value))


func _set_kind(kind: StringName) -> void:
	var idx := KINDS.find(kind)
	if idx < 0:
		return
	_kind_select.select(idx)
	_on_kind_selected(idx)


func _on_kind_selected(index: int) -> void:
	var kind := StringName(str(_kind_select.get_item_metadata(index)))
	var surface := _current_surface()
	if surface.is_empty():
		_sync_wall_role()
		queue_redraw()
		return
	surface["type"] = str(kind)
	if kind == &"wall":
		surface["wall_role"] = str(surface.get("wall_role", "auto"))
	else:
		surface.erase("wall_role")
	var depths: Vector2 = SurfaceGeometryScript.default_depths(kind)
	surface["depth_far"] = snappedf(depths.x, 0.01)
	surface["depth_near"] = snappedf(depths.y, 0.01)
	if not _drawing:
		_dirty = true
	_refresh_surface_list()
	_update_depth_label()
	_sync_wall_role()
	queue_redraw()


func _on_wall_role_selected(index: int) -> void:
	var surface := _current_surface()
	if surface.is_empty() or str(surface.get("type", "")) != "wall":
		return
	surface["wall_role"] = str(_wall_role_select.get_item_metadata(index))
	if not _drawing:
		_dirty = true
	queue_redraw()


func _sync_wall_role() -> void:
	if _wall_role_select == null:
		return
	var surface := _current_surface()
	var is_wall := not surface.is_empty() and str(surface.get("type", "")) == "wall"
	_wall_role_select.disabled = not is_wall
	_wall_role_select.visible = is_wall or _selected_kind() == &"wall"
	var roles := ["auto", "left", "back", "right"]
	var index := roles.find(str(surface.get("wall_role", "auto"))) if is_wall else 0
	_wall_role_select.select(maxi(index, 0))


func _adjust_depth(field: String, amount: float) -> void:
	var surface := _current_surface()
	if surface.is_empty():
		return
	surface[field] = snappedf(clampf(float(surface.get(field, 0.5)) + amount, 0.0, 1.0), 0.01)
	if float(surface.get("depth_far", 0.0)) > float(surface.get("depth_near", 1.0)):
		if field == "depth_far":
			surface["depth_near"] = surface["depth_far"]
		else:
			surface["depth_far"] = surface["depth_near"]
	if not _drawing:
		_dirty = true
	_update_depth_label()
	queue_redraw()


func _refresh_surface_list() -> void:
	if _surface_select == null:
		return
	_surface_select.clear()
	if _drawing:
		_surface_select.add_item(Loc.t("misc.surface_editor.neu_s", "NEU: %s") % str(_draft.get("id", "Fläche")))
		_surface_select.disabled = true
		return
	_surface_select.disabled = false
	_surface_select.add_item(Loc.t("misc.surface_editor.keine_auswahl", "— keine Auswahl —"))
	_surface_select.set_item_metadata(0, -1)
	for i in _surfaces().size():
		var surface := _surfaces()[i] as Dictionary
		var kind := StringName(str(surface.get("type", "wall")))
		_surface_select.add_item("%02d · %s · %s" % [i + 1,
			str(KIND_LABEL.get(kind, kind)), str(surface.get("id", "surface"))])
		_surface_select.set_item_metadata(_surface_select.item_count - 1, i)
	_surface_select.select(_selected + 1 if _selected >= 0 else 0)


func _on_surface_selected(item: int) -> void:
	if _drawing:
		return
	_selected = int(_surface_select.get_item_metadata(item))
	var surface := _current_surface()
	if not surface.is_empty():
		var kind := StringName(str(surface.get("type", "wall")))
		var idx := KINDS.find(kind)
		if idx >= 0:
			_kind_select.select(idx)
	_update_depth_label()
	_sync_wall_role()
	queue_redraw()


func _update_depth_label() -> void:
	if _depth_label == null:
		return
	var surface := _current_surface()
	_depth_label.text = Loc.t("misc.surface_editor.fern_nah", "FERN — · NAH —") \
		if surface.is_empty() else Loc.t("misc.surface_editor.depth_values",
			"FERN %.2f · NAH %.2f") % [
				float(surface.get("depth_far", 0.0)), float(surface.get("depth_near", 1.0))]


func _toggle_foreground() -> void:
	_show_foreground = not _show_foreground
	_update_foreground_button()
	queue_redraw()


func _update_foreground_button() -> void:
	if _foreground_button != null:
		_foreground_button.text = Loc.t("misc.surface_editor.mobel_vordergrund_s",
			"MÖBEL/VORDERGRUND %s") % (
				Loc.t("ui.common.on", "AN") if _show_foreground
				else Loc.t("ui.common.off", "AUS"))


func _reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()


func _save() -> void:
	if _drawing:
		var error := SurfaceGeometryScript.validate_surface(_draft)
		if error.is_empty():
			_finish_surface()
		else:
			_flash("F8 nicht gespeichert: offene Fläche %s." % error, Color(1.0, 0.35, 0.32), 5.0)
			return
	var errors: Array[String] = []
	var locations := _data.get("locations", {}) as Dictionary
	for location_value: Variant in locations:
		var location_key := str(location_value)
		var entry: Variant = locations[location_key]
		if not entry is Dictionary:
			continue
		var ids := {}
		var surfaces: Array = (entry as Dictionary).get("surfaces", [])
		for i in surfaces.size():
			if not surfaces[i] is Dictionary:
				errors.append("%s #%d: kein Objekt" % [location_key, i + 1])
				continue
			var surface := surfaces[i] as Dictionary
			var error := SurfaceGeometryScript.validate_surface(surface)
			var id := str(surface.get("id", "surface_%02d" % (i + 1)))
			if ids.has(id):
				error = "doppelte ID '%s'" % id
			ids[id] = true
			if not error.is_empty():
				errors.append("%s / %s: %s" % [location_key, id, error])
	if not errors.is_empty():
		_flash("NICHT GESPEICHERT · %s" % errors[0], Color(1.0, 0.30, 0.28), 6.0)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if file == null:
		_flash("NICHT GESPEICHERT · Datei nicht schreibbar (%d)." % FileAccess.get_open_error(),
			Color(1.0, 0.30, 0.28), 6.0)
		return
	file.store_string(JSON.stringify(_data, "  ", false) + "\n")
	file.close()
	SurfaceGeometryScript.reload()
	_dirty = false
	var count := 0
	for raw: Variant in locations.values():
		if raw is Dictionary:
			count += ((raw as Dictionary).get("surfaces", []) as Array).size()
	_flash("GESPEICHERT · %d Flächen in %d Leveln · %s" % [count, locations.size(), DATA_PATH],
		Color(0.38, 1.0, 0.58), 5.0)


func _flash(message: String, color: Color, seconds := 3.0) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", color)
	_flash_until = Time.get_ticks_msec() + int(seconds * 1000.0)


func _update_status() -> void:
	if _status == null or _flash_until > 0:
		return
	var count := _surfaces().size()
	_status.text = Loc.t("misc.surface_editor.s_d_flache_s_s_linksklick", "%s · %d Fläche%s%s  |  Linksklick: wählen/ziehen · Rad: Zoom · Mitte: schieben · N: neu · Enter: schließen · F8: speichern") % [
		_display_name(_key), count, "n" if count != 1 else "", " · UNGESPEICHERT" if _dirty else ""]
	_status.add_theme_color_override("font_color", Color(0.72, 0.82, 0.90))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mouse.pressed
			accept_event()
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(mouse.position, 1.14 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 0.88)
			accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed and _drawing:
			_undo_point()
			accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_left_press(mouse.position, mouse.double_click)
			else:
				_drag_vertex = -1
				_drag_surface = false
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			_pan += motion.relative
			queue_redraw()
		elif _drag_vertex >= 0:
			_move_vertex(motion.position)
		elif _drag_surface:
			_move_surface(motion.position)


func _left_press(point: Vector2, double_click: bool) -> void:
	_compute_art_rect()
	if not _art_rect.has_point(point):
		return
	var uv := _screen_to_uv(point)
	if _drawing:
		if double_click and (_draft.get("points", []) as Array).size() >= 3:
			_finish_surface()
			return
		(_draft["points"] as Array).append([snappedf(uv.x, 0.0001), snappedf(uv.y, 0.0001)])
		queue_redraw()
		return
	var handle := _handle_at(point)
	if handle >= 0:
		_drag_vertex = handle
		return
	var hit := _surface_at(uv)
	if hit >= 0:
		_selected = hit
		var surface := _surfaces()[hit] as Dictionary
		var kind := StringName(str(surface.get("type", "wall")))
		var kind_index := KINDS.find(kind)
		if kind_index >= 0:
			_kind_select.select(kind_index)
		_drag_surface = true
		_drag_start_uv = uv
		_drag_points = (surface.get("points", []) as Array).duplicate(true)
	else:
		_selected = -1
	_refresh_surface_list()
	_update_depth_label()
	queue_redraw()


func _handle_at(point: Vector2) -> int:
	var surface := _current_surface()
	if surface.is_empty():
		return -1
	var points := surface.get("points", []) as Array
	for i in points.size():
		var p := _uv_to_screen(Vector2(float(points[i][0]), float(points[i][1])))
		if p.distance_to(point) <= HANDLE_RADIUS + 3.0:
			return i
	return -1


func _surface_at(uv: Vector2) -> int:
	for i in range(_surfaces().size() - 1, -1, -1):
		var surface := _surfaces()[i] as Dictionary
		if Geometry2D.is_point_in_polygon(uv, SurfaceGeometryScript.polygon_for(surface)):
			return i
	return -1


func _move_vertex(point: Vector2) -> void:
	var surface := _current_surface()
	if surface.is_empty():
		return
	var uv := _screen_to_uv(point)
	var points := surface.get("points", []) as Array
	points[_drag_vertex] = [snappedf(uv.x, 0.0001), snappedf(uv.y, 0.0001)]
	_dirty = true
	queue_redraw()


func _move_surface(point: Vector2) -> void:
	if _selected < 0 or _selected >= _surfaces().size():
		return
	var delta := _screen_to_uv(point) - _drag_start_uv
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for raw: Variant in _drag_points:
		var p := Vector2(float(raw[0]), float(raw[1]))
		min_point = min_point.min(p)
		max_point = max_point.max(p)
	delta.x = clampf(delta.x, -min_point.x, 1.0 - max_point.x)
	delta.y = clampf(delta.y, -min_point.y, 1.0 - max_point.y)
	var points := (_surfaces()[_selected] as Dictionary).get("points", []) as Array
	for i in points.size():
		var p := Vector2(float(_drag_points[i][0]), float(_drag_points[i][1])) + delta
		points[i] = [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)]
	_dirty = true
	queue_redraw()


func _zoom_at(point: Vector2, factor: float) -> void:
	_compute_art_rect()
	var uv := _screen_to_uv(point)
	_zoom = clampf(_zoom * factor, 1.0, 8.0)
	_compute_art_rect()
	_pan += point - _uv_to_screen(uv)
	queue_redraw()


func _screen_to_uv(point: Vector2) -> Vector2:
	return Vector2(clampf((point.x - _art_rect.position.x) / maxf(_art_rect.size.x, 1.0), 0.0, 1.0),
		clampf((point.y - _art_rect.position.y) / maxf(_art_rect.size.y, 1.0), 0.0, 1.0))


func _uv_to_screen(uv: Vector2) -> Vector2:
	return _art_rect.position + uv * _art_rect.size


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_F8 or (event.ctrl_pressed and event.keycode == KEY_S):
		_save()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_N: _new_surface()
		KEY_ENTER, KEY_KP_ENTER: _finish_surface()
		KEY_ESCAPE:
			if _drawing: _cancel_draft()
			else: _selected = -1; _refresh_surface_list(); queue_redraw()
		KEY_DELETE, KEY_BACKSPACE: _delete_selected()
		KEY_1: _set_kind(&"floor")
		KEY_2: _set_kind(&"wall")
		KEY_3: _set_kind(&"ceiling")
		KEY_4: _set_kind(&"window")
		KEY_F: _toggle_foreground()
		KEY_0: _reset_view()
		KEY_PAGEUP: _cycle_location(-1)
		KEY_PAGEDOWN: _cycle_location(1)


func _compute_art_rect() -> void:
	var texture_size := Vector2(1920, 1080)
	if _background != null:
		texture_size = Vector2(_background.get_size())
	var available := Rect2(Vector2(14, TOOLBAR_H + 10),
		Vector2(maxf(1.0, size.x - 28.0), maxf(1.0, size.y - TOOLBAR_H - FOOTER_H - 18.0)))
	var aspect := texture_size.x / maxf(texture_size.y, 1.0)
	var draw_size := Vector2(available.size.x, available.size.x / aspect)
	if draw_size.y > available.size.y:
		draw_size = Vector2(available.size.y * aspect, available.size.y)
	draw_size *= _zoom
	_art_rect = Rect2(available.get_center() - draw_size * 0.5 + _pan, draw_size)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.024, 0.034))
	_compute_art_rect()
	if _background != null:
		draw_texture_rect(_background, _art_rect, false)
	else:
		draw_rect(_art_rect, Color(0.10, 0.12, 0.15))
		_text(_art_rect.position + Vector2(16, 30), "HINTERGRUND FEHLT: %s" % _key,
			22, Color(1.0, 0.45, 0.35))
	if _show_foreground:
		if _key == "ROOM_MASTER" and _room_desk != null:
			draw_texture_rect(_room_desk, _art_rect, false)
		elif _foreground != null:
			draw_texture_rect(_foreground, _art_rect, false)
	draw_rect(_art_rect, Color(0.34, 0.80, 1.0, 0.55), false, 1.0)
	for i in _surfaces().size():
		_draw_surface(_surfaces()[i] as Dictionary, i == _selected, i + 1)
	if _drawing:
		_draw_surface(_draft, true, _surfaces().size() + 1, true)
	_text(_art_rect.position + Vector2(10, 24), _display_name(_key), 20,
		Color(0.90, 0.96, 1.0), 4)


func _draw_surface(surface: Dictionary, selected: bool, number: int, draft := false) -> void:
	var uv_polygon := SurfaceGeometryScript.polygon_for(surface)
	if uv_polygon.is_empty():
		return
	var polygon := PackedVector2Array()
	for uv: Vector2 in uv_polygon:
		polygon.append(_uv_to_screen(uv))
	var kind := StringName(str(surface.get("type", "wall")))
	var color: Color = KIND_COLOR.get(kind, Color.WHITE)
	if polygon.size() >= 3:
		var valid := SurfaceGeometryScript.validate_surface(surface).is_empty()
		var fill := Color(color if valid else Color(1.0, 0.12, 0.12), 0.22 if selected else 0.12)
		draw_colored_polygon(polygon, fill)
		var closed := polygon.duplicate()
		closed.append(polygon[0])
		draw_polyline(closed, color if valid else Color(1.0, 0.18, 0.16),
			3.0 if selected else 1.5, true)
	else:
		draw_polyline(polygon, color, 2.0, true)
	for i in polygon.size():
		var radius := HANDLE_RADIUS if selected else 4.0
		draw_circle(polygon[i], radius + 2.0, Color(0, 0, 0, 0.72))
		draw_circle(polygon[i], radius, color)
		if selected:
			_text(polygon[i] + Vector2(9, -7), str(i + 1), 15, Color.WHITE, 3)
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point
	center /= float(polygon.size())
	var role := str(surface.get("wall_role", "auto")).to_upper() if kind == &"wall" else ""
	var role_text := (" · %s" % role) if not role.is_empty() else ""
	var label := "%02d · %s%s%s" % [number, str(KIND_LABEL.get(kind, kind)), role_text,
		" · NEU" if draft else ""]
	_text(center + Vector2(8, -8), label, 18, color, 4)
	if selected and polygon.size() >= 3:
		_draw_depth_arrow(surface, uv_polygon, color)


func _draw_depth_arrow(surface: Dictionary, polygon: PackedVector2Array, color: Color) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in polygon:
		lo = lo.min(p); hi = hi.max(p)
	var center := (lo + hi) * 0.5
	var kind := StringName(str(surface.get("type", "wall")))
	var far_uv: Vector2
	var near_uv: Vector2
	match kind:
		&"floor":
			far_uv = Vector2(center.x, lo.y); near_uv = Vector2(center.x, hi.y)
		&"ceiling":
			far_uv = Vector2(center.x, hi.y); near_uv = Vector2(center.x, lo.y)
		&"window":
			far_uv = Vector2(center.x, lo.y); near_uv = Vector2(center.x, hi.y)
		_:
			var wall_role := str(surface.get("wall_role", "auto"))
			if wall_role == "auto":
				wall_role = "left" if center.x < 0.42 else ("right" if center.x > 0.58 else "back")
			if wall_role == "left":
				far_uv = Vector2(hi.x, center.y); near_uv = Vector2(lo.x, center.y)
			elif wall_role == "right":
				far_uv = Vector2(lo.x, center.y); near_uv = Vector2(hi.x, center.y)
			else:
				far_uv = Vector2(center.x, lo.y); near_uv = Vector2(center.x, lerpf(lo.y, hi.y, 0.28))
	var a := _uv_to_screen(far_uv)
	var b := _uv_to_screen(near_uv)
	draw_line(a, b, Color(color, 0.9), 3.0, true)
	var direction := (b - a).normalized()
	var side := direction.rotated(PI * 0.5)
	draw_colored_polygon(PackedVector2Array([b, b - direction * 14.0 + side * 7.0,
		b - direction * 14.0 - side * 7.0]), color)
	_text(a + Vector2(6, -5), "FERN %.2f" % float(surface.get("depth_far", 0.0)), 15, color, 3)
	_text(b + Vector2(6, 16), "NAH %.2f" % float(surface.get("depth_near", 1.0)), 15, color, 3)


func _text(draw_position: Vector2, text: String, font_size: int, color: Color,
		outline := 3) -> void:
	draw_string_outline(_font, draw_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		outline, Color(0.0, 0.0, 0.0, 0.88))
	draw_string(_font, draw_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
