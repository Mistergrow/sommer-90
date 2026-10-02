extends Control
## Zweiter, strikt getrennter F6-Editor für eingebettete Objekte sowie
## Licht-/Schattenprojektionen. F8 schreibt nur location_objects.json.

const DATA_PATH := "res://data/location_objects.json"
const PROFILE_PATH := "res://data/location_25d.json"
const BG_DIR := "res://assets/backgrounds/locations"
const ObjectGeometryScript := preload("res://scripts/gfx/object_geometry.gd")
const SurfaceGeometryScript := preload("res://scripts/gfx/surface_geometry.gd")

const TYPES := ObjectGeometryScript.TYPES
const LABELS := {
	&"object": "OBJEKT", &"light_source": "LICHTQUELLE",
	&"light_field": "LICHTFELD", &"shadow": "SCHATTEN",
}
const COLORS := {
	&"object": Color(1.0, 0.58, 0.20), &"light_source": Color(1.0, 0.95, 0.50),
	&"light_field": Color(1.0, 0.76, 0.32), &"shadow": Color(0.70, 0.52, 1.0),
}
const TOOLBAR_H := 94.0
const FOOTER_H := 34.0
const HANDLE := 8.0

var _font: Font
var _data: Dictionary = {}
var _profiles: Dictionary = {}
var _keys: Array[String] = []
var _key := "ROOM_MASTER"
var _background: Texture2D
var _reference: Texture2D
var _show_reference := false

var _location_select: OptionButton
var _type_select: OptionButton
var _entry_select: OptionButton
var _source_select: OptionButton
var _receiver_select: OptionButton
var _weather_select: OptionButton
var _parameter_label: Label
var _status: Label
var _reference_button: Button

var _selected := -1
var _draft: Dictionary = {}
var _drawing := false
var _drag_vertex := -1
var _drag_entry := false
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
	_load_documents()
	_build_registry()
	_build_toolbar()
	_select_location(0)
	set_process(true)


func _process(_delta: float) -> void:
	if _flash_until > 0 and Time.get_ticks_msec() > _flash_until:
		_flash_until = 0
		_update_status()


func _load_documents() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) \
		if FileAccess.file_exists(DATA_PATH) else null
	_data = parsed as Dictionary if parsed is Dictionary else {"version": 1, "locations": {}}
	if not _data.get("locations", {}) is Dictionary:
		_data["locations"] = {}
	var profiles_doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if profiles_doc is Dictionary and (profiles_doc as Dictionary).get("profiles", {}) is Dictionary:
		_profiles = (profiles_doc as Dictionary)["profiles"]


func _build_registry() -> void:
	_keys = ["ROOM_MASTER"]
	var rest: Array = _profiles.keys()
	rest.sort()
	for raw: Variant in rest:
		_keys.append(str(raw))


func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = TOOLBAR_H
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.06, 0.98)
	style.border_color = Color(1.0, 0.55, 0.20, 0.76)
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
	_location_select.custom_minimum_size.x = 275
	for key: String in _keys:
		_location_select.add_item(_display_name(key))
		_location_select.set_item_metadata(_location_select.item_count - 1, key)
	_location_select.item_selected.connect(_select_location)
	top.add_child(_location_select)
	top.add_child(_button("◀", func() -> void: _cycle_location(-1)))
	top.add_child(_button("▶", func() -> void: _cycle_location(1)))
	top.add_child(_label("PASS", Color(1.0, 0.72, 0.32)))
	_type_select = OptionButton.new()
	for kind: StringName in TYPES:
		_type_select.add_item(str(LABELS[kind]))
		_type_select.set_item_metadata(_type_select.item_count - 1, kind)
	_type_select.item_selected.connect(_on_type_selected)
	top.add_child(_type_select)
	top.add_child(_button(Loc.t("misc.object_editor.neu", "＋ NEU"), _new_entry))
	top.add_child(_button(Loc.t("misc.object_editor.schliessen", "✓ SCHLIESSEN"), _finish_entry))
	top.add_child(_button(Loc.t("misc.object_editor.punkt", "↶ PUNKT"), _undo_point))
	top.add_child(_button("🗑", _delete_selected))
	top.add_child(_button(Loc.t("misc.object_editor.f8", "💾 F8"), _save))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 7)
	rows.add_child(bottom)
	bottom.add_child(_label("AUSWAHL", Color(0.72, 0.78, 0.86)))
	_entry_select = OptionButton.new()
	_entry_select.custom_minimum_size.x = 230
	_entry_select.item_selected.connect(_on_entry_selected)
	bottom.add_child(_entry_select)
	bottom.add_child(_button(Loc.t("misc.object_editor.wert", "WERT −"), func() -> void: _adjust_value(-0.04)))
	bottom.add_child(_button(Loc.t("misc.object_editor.wert_772d", "WERT ＋"), func() -> void: _adjust_value(0.04)))
	_parameter_label = _label("—", Color(0.86, 0.92, 1.0))
	_parameter_label.custom_minimum_size.x = 150
	bottom.add_child(_parameter_label)
	_source_select = OptionButton.new()
	_source_select.custom_minimum_size.x = 135
	_source_select.item_selected.connect(_on_source_selected)
	bottom.add_child(_source_select)
	_receiver_select = OptionButton.new()
	_receiver_select.custom_minimum_size.x = 135
	_receiver_select.item_selected.connect(_on_receiver_selected)
	bottom.add_child(_receiver_select)
	_weather_select = OptionButton.new()
	for weather: String in ["ALLE WETTER", "SONNE", "WOLKEN", "REGEN", "STURM"]:
		_weather_select.add_item(weather)
	_weather_select.item_selected.connect(_on_weather_selected)
	bottom.add_child(_weather_select)
	_reference_button = _button(Loc.t("misc.object_editor.rgba_referenz_aus", "RGBA-REFERENZ AUS"), _toggle_reference)
	bottom.add_child(_reference_button)

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


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	return button


func _select_location(index: int) -> void:
	if index < 0 or index >= _keys.size():
		return
	_cancel_draft(false)
	_key = _keys[index]
	_location_select.select(index)
	_selected = -1
	_background = _load_background(_key)
	_reference = _load_reference(_key)
	_show_reference = false
	_zoom = 1.0
	_pan = Vector2.ZERO
	_refresh_lists()
	_update_reference_button()
	_update_status()
	queue_redraw()


## Öffentlicher Preview-Vertrag; siehe SurfaceEditor.select_location_key().
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
		return load("res://assets/backgrounds/layers/ROOM_EMPTY_SHELVES_MASTER_V02.png")
	for version in range(9, 0, -1):
		var path := "%s/%s_V%02d.png" % [BG_DIR, key, version]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _load_reference(key: String) -> Texture2D:
	if key == "ROOM_MASTER":
		return load("res://assets/backgrounds/layers/ROOM_DESK_MASTER_V02.png")
	var path := str((_profiles.get(key, {}) as Dictionary).get("foreground_asset", ""))
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null


func _display_name(key: String) -> String:
	return "ZIMMER · ROOM MASTER" if key == "ROOM_MASTER" else key.trim_prefix("LOCATION_").trim_suffix("_MASTER").replace("_", " ")


func _location_entry() -> Dictionary:
	var locations := _data["locations"] as Dictionary
	if not locations.has(_key) or not locations[_key] is Dictionary:
		locations[_key] = {"objects": []}
	var entry := locations[_key] as Dictionary
	if not entry.get("objects", []) is Array:
		entry["objects"] = []
	return entry


func _entries() -> Array:
	return _location_entry()["objects"] as Array


func _current() -> Dictionary:
	if _drawing:
		return _draft
	return _entries()[_selected] as Dictionary \
		if _selected >= 0 and _selected < _entries().size() else {}


func _selected_type() -> StringName:
	return StringName(str(_type_select.get_item_metadata(_type_select.selected)))


func _new_entry() -> void:
	if _drawing:
		_flash("Erst das offene Polygon schließen oder mit Esc verwerfen.", Color(1.0, 0.65, 0.3))
		return
	var kind := _selected_type()
	var index := 1
	var ids := {}
	for raw: Variant in _entries():
		if raw is Dictionary:
			ids[str((raw as Dictionary).get("id", ""))] = true
	while ids.has("%s_%02d" % [kind, index]):
		index += 1
	_draft = {"id": "%s_%02d" % [kind, index], "type": str(kind), "label": str(LABELS[kind]), "points": []}
	if kind == &"object":
		_draft.merge({"depth_far": 0.48, "depth_near": 0.82, "depth_axis": "vertical"})
	else:
		_draft.merge({"strength": 0.12, "softness": 0.72,
			"color": [1.0, 0.78, 0.42] if kind != &"shadow" else [0.13, 0.12, 0.11],
			"weather": "all"})
	_drawing = true
	_selected = -1
	_refresh_lists()
	_flash("Polygon setzen · Doppelklick/Enter schließen · Rechtsklick nimmt einen Punkt zurück.", Color(0.48, 1.0, 0.68), 5.0)
	queue_redraw()


func _finish_entry() -> void:
	if not _drawing:
		return
	var error := ObjectGeometryScript.validate_entry(_draft)
	if not error.is_empty():
		_flash("Noch nicht gültig: %s." % error, Color(1.0, 0.34, 0.30), 4.0)
		return
	_entries().append(_draft.duplicate(true))
	_selected = _entries().size() - 1
	_draft = {}
	_drawing = false
	_dirty = true
	_refresh_lists()
	queue_redraw()


func _cancel_draft(show_message := true) -> void:
	if not _drawing:
		return
	_draft = {}
	_drawing = false
	_refresh_lists()
	if show_message:
		_flash("Offenes Polygon verworfen.", Color(0.85, 0.77, 0.60))
	queue_redraw()


func _undo_point() -> void:
	if _drawing and not (_draft.get("points", []) as Array).is_empty():
		(_draft["points"] as Array).pop_back()
		queue_redraw()


func _delete_selected() -> void:
	if _drawing:
		_cancel_draft()
		return
	if _selected < 0 or _selected >= _entries().size():
		return
	_entries().remove_at(_selected)
	_selected = mini(_selected, _entries().size() - 1)
	_dirty = true
	_refresh_lists()
	queue_redraw()


func _on_type_selected(index: int) -> void:
	var current := _current()
	if current.is_empty():
		return
	var kind := StringName(str(_type_select.get_item_metadata(index)))
	current["type"] = str(kind)
	if kind == &"object":
		current["depth_far"] = float(current.get("depth_far", 0.48))
		current["depth_near"] = float(current.get("depth_near", 0.82))
	else:
		current["strength"] = float(current.get("strength", 0.12))
		current["softness"] = float(current.get("softness", 0.72))
		current["weather"] = str(current.get("weather", "all"))
	if not _drawing:
		_dirty = true
	_refresh_lists()
	queue_redraw()


func _adjust_value(amount: float) -> void:
	var current := _current()
	if current.is_empty():
		return
	if str(current.get("type", "")) == "object":
		current["depth_near"] = snappedf(clampf(float(current.get("depth_near", 0.82)) + amount, 0.0, 1.0), 0.01)
		current["depth_far"] = minf(float(current.get("depth_far", 0.48)), float(current["depth_near"]))
	else:
		current["strength"] = snappedf(clampf(float(current.get("strength", 0.12)) + amount, 0.0, 1.0), 0.01)
	if not _drawing:
		_dirty = true
	_update_controls()
	queue_redraw()


func _refresh_lists() -> void:
	if _entry_select == null:
		return
	_entry_select.clear()
	if _drawing:
		_entry_select.add_item(Loc.t("misc.object_editor.neu_s", "NEU · %s") % _draft.get("id", ""))
		_entry_select.disabled = true
	else:
		_entry_select.disabled = false
		_entry_select.add_item(Loc.t("misc.object_editor.keine_auswahl", "— keine Auswahl —"))
		_entry_select.set_item_metadata(0, -1)
		for i in _entries().size():
			var entry := _entries()[i] as Dictionary
			var kind := StringName(str(entry.get("type", "object")))
			_entry_select.add_item("%02d · %s · %s" % [i + 1, LABELS.get(kind, kind), entry.get("label", entry.get("id", ""))])
			_entry_select.set_item_metadata(_entry_select.item_count - 1, i)
		_entry_select.select(_selected + 1 if _selected >= 0 else 0)
	_refresh_link_lists()
	_update_controls()


func _refresh_link_lists() -> void:
	_source_select.clear()
	_source_select.add_item(Loc.t("misc.object_editor.quelle", "QUELLE —"))
	_source_select.set_item_metadata(0, "")
	for raw: Variant in _entries():
		if raw is Dictionary and str((raw as Dictionary).get("type", "")) == "light_source":
			_source_select.add_item(Loc.t("misc.object_editor.q_s", "Q: %s") % (raw as Dictionary).get("label", (raw as Dictionary).get("id", "")))
			_source_select.set_item_metadata(_source_select.item_count - 1, str((raw as Dictionary).get("id", "")))
	_receiver_select.clear()
	_receiver_select.add_item(Loc.t("misc.object_editor.empfanger", "EMPFÄNGER —"))
	_receiver_select.set_item_metadata(0, "")
	for raw: Variant in SurfaceGeometryScript.surfaces_for(_key):
		if raw is Dictionary:
			_receiver_select.add_item(Loc.t("misc.object_editor.e_s", "E: %s") % (raw as Dictionary).get("id", "surface"))
			_receiver_select.set_item_metadata(_receiver_select.item_count - 1, str((raw as Dictionary).get("id", "")))


func _on_entry_selected(item: int) -> void:
	if _drawing:
		return
	_selected = int(_entry_select.get_item_metadata(item))
	var current := _current()
	if not current.is_empty():
		var idx := TYPES.find(StringName(str(current.get("type", "object"))))
		if idx >= 0:
			_type_select.select(idx)
	_update_controls()
	queue_redraw()


func _update_controls() -> void:
	if _parameter_label == null:
		return
	var current := _current()
	var kind := str(current.get("type", ""))
	_parameter_label.text = "—" if current.is_empty() else (
		"FERN %.2f · NAH %.2f" % [current.get("depth_far", 0.48), current.get("depth_near", 0.82)]
		if kind == "object" else "STÄRKE %.2f" % current.get("strength", 0.12))
	var linkable := kind in ["light_field", "shadow"]
	_source_select.visible = linkable
	_receiver_select.visible = linkable
	_weather_select.visible = kind in ["light_source", "light_field", "shadow"]
	if linkable:
		_select_metadata(_source_select, str(current.get("source_id", "")))
		_select_metadata(_receiver_select, str(current.get("receiver_surface", "")))
	var weathers := ["all", "clear", "clouds", "rain", "storm"]
	_weather_select.select(maxi(0, weathers.find(str(current.get("weather", "all")))))


func _select_metadata(option: OptionButton, value: String) -> void:
	for i in option.item_count:
		if str(option.get_item_metadata(i)) == value:
			option.select(i)
			return
	option.select(0)


func _on_source_selected(item: int) -> void:
	var current := _current()
	if not current.is_empty():
		current["source_id"] = str(_source_select.get_item_metadata(item))
		_dirty = true


func _on_receiver_selected(item: int) -> void:
	var current := _current()
	if not current.is_empty():
		current["receiver_surface"] = str(_receiver_select.get_item_metadata(item))
		_dirty = true


func _on_weather_selected(item: int) -> void:
	var current := _current()
	if current.is_empty():
		return
	current["weather"] = ["all", "clear", "clouds", "rain", "storm"][item]
	if not _drawing:
		_dirty = true


func _toggle_reference() -> void:
	_show_reference = not _show_reference
	_update_reference_button()
	queue_redraw()


func _update_reference_button() -> void:
	if _reference_button != null:
		_reference_button.text = Loc.t("misc.object_editor.rgba_referenz_s",
			"RGBA-REFERENZ %s") % (
				Loc.t("ui.common.on", "AN") if _show_reference
				else Loc.t("ui.common.off", "AUS"))
		_reference_button.disabled = _reference == null


func _save() -> void:
	if _drawing:
		var error := ObjectGeometryScript.validate_entry(_draft)
		if not error.is_empty():
			_flash("Nicht gespeichert: offenes Polygon %s." % error, Color(1.0, 0.30, 0.27), 5.0)
			return
		_finish_entry()
	var errors: Array[String] = []
	for location_value: Variant in (_data.get("locations", {}) as Dictionary):
		var location_key := str(location_value)
		var entry: Dictionary = _data["locations"][location_key]
		var ids := {}
		for raw: Variant in entry.get("objects", []):
			if not raw is Dictionary:
				continue
			var object := raw as Dictionary
			var id := str(object.get("id", ""))
			var error := ObjectGeometryScript.validate_entry(object)
			if ids.has(id):
				error = "doppelte ID %s" % id
			ids[id] = true
			if not error.is_empty():
				errors.append("%s/%s: %s" % [location_key, id, error])
	if not errors.is_empty():
		_flash("NICHT GESPEICHERT · %s" % errors[0], Color(1.0, 0.30, 0.27), 6.0)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if file == null:
		_flash("Datei nicht schreibbar.", Color(1.0, 0.30, 0.27), 5.0)
		return
	file.store_string(JSON.stringify(_data, "  ", false) + "\n")
	file.close()
	ObjectGeometryScript.reload()
	_dirty = false
	_flash("GESPEICHERT · Objekt-, Licht- und Schattenpass · %s" % DATA_PATH, Color(0.38, 1.0, 0.58), 5.0)


func _flash(message: String, color: Color, seconds := 3.0) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", color)
	_flash_until = Time.get_ticks_msec() + roundi(seconds * 1000.0)


func _update_status() -> void:
	if _status == null or _flash_until > 0:
		return
	_status.text = Loc.t("misc.object_editor.s_d_objekt_lichtflachen_s_n", "%s · %d Objekt-/Lichtflächen%s | N neu · Enter schließen · Entf löschen · F8 speichert nur den Objektpass") % [
		_display_name(_key), _entries().size(), " · UNGESPEICHERT" if _dirty else ""]
	_status.add_theme_color_override("font_color", Color(0.74, 0.83, 0.91))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mouse.pressed
			return
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(mouse.position, 1.14 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 0.88)
			return
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT and _drawing:
			_undo_point()
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_left_press(mouse.position, mouse.double_click)
			else:
				_drag_vertex = -1
				_drag_entry = false
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			_pan += motion.relative
			queue_redraw()
		elif _drag_vertex >= 0:
			_move_vertex(motion.position)
		elif _drag_entry:
			_move_entry(motion.position)


func _left_press(point: Vector2, double_click: bool) -> void:
	_compute_art_rect()
	# Unterhalb der Toolbar ist auch der schwarze Overscan Arbeitsfläche. So kann
	# man Bett-/Möbelfluchten außerhalb des sichtbaren Masters anklicken/ziehen.
	if point.y < TOOLBAR_H or point.y > size.y - FOOTER_H:
		return
	var uv := _screen_to_uv(point)
	if _drawing:
		if double_click and (_draft.get("points", []) as Array).size() >= 3:
			_finish_entry()
		else:
			(_draft["points"] as Array).append([snappedf(uv.x, 0.0001), snappedf(uv.y, 0.0001)])
			queue_redraw()
		return
	var handle := _handle_at(point)
	if handle >= 0:
		_drag_vertex = handle
		return
	_selected = _entry_at(uv)
	if _selected >= 0:
		var current := _entries()[_selected] as Dictionary
		var idx := TYPES.find(StringName(str(current.get("type", "object"))))
		if idx >= 0:
			_type_select.select(idx)
		_drag_entry = true
		_drag_start_uv = uv
		_drag_points = (current.get("points", []) as Array).duplicate(true)
	_refresh_lists()
	queue_redraw()


func _handle_at(point: Vector2) -> int:
	var current := _current()
	for i in (current.get("points", []) as Array).size():
		var raw: Array = current["points"][i]
		if _uv_to_screen(Vector2(float(raw[0]), float(raw[1]))).distance_to(point) <= HANDLE + 3.0:
			return i
	return -1


func _entry_at(uv: Vector2) -> int:
	for i in range(_entries().size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(uv, ObjectGeometryScript.polygon_for(_entries()[i] as Dictionary)):
			return i
	return -1


func _move_vertex(point: Vector2) -> void:
	var current := _current()
	if current.is_empty():
		return
	var uv := _screen_to_uv(point)
	(current["points"] as Array)[_drag_vertex] = [snappedf(uv.x, 0.0001), snappedf(uv.y, 0.0001)]
	_dirty = true
	queue_redraw()


func _move_entry(point: Vector2) -> void:
	if _selected < 0:
		return
	var delta := _screen_to_uv(point) - _drag_start_uv
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for raw: Variant in _drag_points:
		var p := Vector2(float(raw[0]), float(raw[1]))
		lo = lo.min(p); hi = hi.max(p)
	delta.x = clampf(delta.x, ObjectGeometryScript.OVERSCAN_MIN - lo.x,
		ObjectGeometryScript.OVERSCAN_MAX - hi.x)
	delta.y = clampf(delta.y, ObjectGeometryScript.OVERSCAN_MIN - lo.y,
		ObjectGeometryScript.OVERSCAN_MAX - hi.y)
	var points := (_entries()[_selected] as Dictionary)["points"] as Array
	for i in points.size():
		var p := Vector2(float(_drag_points[i][0]), float(_drag_points[i][1])) + delta
		points[i] = [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)]
	_dirty = true
	queue_redraw()


func _zoom_at(point: Vector2, factor: float) -> void:
	_compute_art_rect()
	var uv := _screen_to_uv(point)
	# Auszoomen schafft schwarzen Overscan um das Masterbild. Objektgriffe dürfen
	# dort bis ±35 % liegen – nötig für Bett-/Schrankfluchten außerhalb des Fotos.
	_zoom = clampf(_zoom * factor, 0.72, 8.0)
	_compute_art_rect()
	_pan += point - _uv_to_screen(uv)
	queue_redraw()


func _screen_to_uv(point: Vector2) -> Vector2:
	return Vector2(clampf((point.x - _art_rect.position.x) / maxf(_art_rect.size.x, 1.0),
		ObjectGeometryScript.OVERSCAN_MIN, ObjectGeometryScript.OVERSCAN_MAX),
		clampf((point.y - _art_rect.position.y) / maxf(_art_rect.size.y, 1.0),
		ObjectGeometryScript.OVERSCAN_MIN, ObjectGeometryScript.OVERSCAN_MAX))


func _uv_to_screen(uv: Vector2) -> Vector2:
	return _art_rect.position + uv * _art_rect.size


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_F8 or (event.ctrl_pressed and event.keycode == KEY_S):
		_save()
		return
	match event.keycode:
		KEY_N: _new_entry()
		KEY_ENTER, KEY_KP_ENTER: _finish_entry()
		KEY_ESCAPE:
			if _drawing: _cancel_draft()
		KEY_DELETE, KEY_BACKSPACE: _delete_selected()
		KEY_1: _type_select.select(0); _on_type_selected(0)
		KEY_2: _type_select.select(1); _on_type_selected(1)
		KEY_3: _type_select.select(2); _on_type_selected(2)
		KEY_4: _type_select.select(3); _on_type_selected(3)
		KEY_F: _toggle_reference()
		KEY_0: _zoom = 1.0; _pan = Vector2.ZERO; queue_redraw()
		KEY_PAGEUP: _cycle_location(-1)
		KEY_PAGEDOWN: _cycle_location(1)


func _compute_art_rect() -> void:
	var texture_size := Vector2(_background.get_size()) if _background != null else Vector2(1920, 1080)
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
	if _show_reference and _reference != null:
		draw_texture_rect(_reference, _art_rect, false)
	draw_rect(_art_rect, Color(1.0, 0.60, 0.22, 0.62), false, 1.0)
	# Architektur ist nur eine ruhige, nicht bearbeitbare Referenz.
	for raw: Variant in SurfaceGeometryScript.surfaces_for(_key):
		if not raw is Dictionary:
			continue
		var poly := PackedVector2Array()
		for uv: Vector2 in SurfaceGeometryScript.polygon_for(raw as Dictionary):
			poly.append(_uv_to_screen(uv))
		if poly.size() >= 3:
			poly.append(poly[0])
			draw_polyline(poly, Color(0.35, 0.78, 0.95, 0.35), 1.0, true)
	for i in _entries().size():
		_draw_entry(_entries()[i] as Dictionary, i == _selected, i + 1)
	if _drawing:
		_draw_entry(_draft, true, _entries().size() + 1)
	_text(_art_rect.position + Vector2(10, 24), "%s · OBJEKT-/LICHTPASS" % _display_name(_key), 20, Color(1.0, 0.90, 0.72), 4)


func _draw_entry(entry: Dictionary, selected: bool, number: int) -> void:
	var polygon := PackedVector2Array()
	for uv: Vector2 in ObjectGeometryScript.polygon_for(entry):
		polygon.append(_uv_to_screen(uv))
	if polygon.is_empty():
		return
	var kind := StringName(str(entry.get("type", "object")))
	var color: Color = COLORS.get(kind, Color.WHITE)
	if polygon.size() >= 3:
		draw_colored_polygon(polygon, Color(color, 0.22 if selected else 0.11))
		var closed := polygon.duplicate(); closed.append(polygon[0])
		draw_polyline(closed, color, 3.0 if selected else 1.5, true)
	else:
		draw_polyline(polygon, color, 2.0, true)
	var center := Vector2.ZERO
	for i in polygon.size():
		center += polygon[i]
		draw_circle(polygon[i], HANDLE if selected else 4.0, color)
	center /= float(polygon.size())
	_text(center + Vector2(8, -7), "%02d · %s · %s" % [number, LABELS.get(kind, kind), entry.get("label", entry.get("id", ""))], 17, color, 4)


func _text(draw_position: Vector2, text: String, font_size: int, color: Color,
		outline := 3) -> void:
	draw_string_outline(_font, draw_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, outline, Color(0,0,0,.88))
	draw_string(_font, draw_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
