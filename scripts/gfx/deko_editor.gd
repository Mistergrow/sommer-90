@tool
class_name DekoEditor
extends Control
## Deko-Werkstatt: das Bearbeitungs-Overlay des RoomCompositors (z 60).
## Zeichnet alle Hilfslinien ÜBER den Layern und verarbeitet die Eingaben
## des Deko-Modus (F8/F6): Objekte ziehen/skalieren/neigen/scheren,
## Flächen-Vierecke und Klickflächen-Polygone per Griff anpassen,
## Zonen aufziehen — und speichert feld-genau nach data/room_anchors.json.
##
## Der Compositor erzeugt diese Ebene bei jedem rebuild() neu und
## delegiert seine öffentliche API (set_edit_mode, editor_*) hierher.

var comp: Control = null           # der RoomCompositor (Duck-Typing)

var _drag_child: Control = null
var _drag_anchor := ""
var _drag_model_specific := false  # Strg+Drag: nur aktive Modellvariante
var _selected: Control = null      # bleibt nach Klick gewählt (Pfeiltasten etc.)
var _editor_grab := Vector2.ZERO   # Griff-Versatz beim Editor-Plugin-Drag
var _active_zone := ""
var _zone_dragging := false
var _zone_start := Vector2.ZERO    # Master-Koordinaten
var _zone_current := Vector2.ZERO
var _corner_drag := -1             # gezogener Quad-Eckpunkt (0-3)
var _corner_quad := ""             # zu welchem Viereck der Eckpunkt gehört
var _hs_drag := ""                 # gezogener Hotspot (Name)
var _hs_corner := -2               # -1 = Mittelgriff (verschieben), 0-3 = Ecke
var _hs_grab := Vector2.ZERO       # Startpunkt beim Verschieben (Master-Px)
var _hs_start: Array = []          # Ecken-Kopie beim Verschiebe-Start
var _help_visible := false         # H-Taste: Befehlsübersicht
var _help_hide_at := 0             # Auto-Ausblenden (msec-Ticks)
var _quads_visible := true         # Q-Taste: Flächen-Rahmen ein/aus
var _hotspots_visible := true      # T-Taste: Klickflächen-Rahmen ein/aus
var _mon_drag := -2                # Monitor-Fenster: -2 nichts, -1 verschieben, 0-3 Ecke
var _mon_grab := Vector2.ZERO      # Startpunkt beim Verschieben (Bildschirm-Px)
var _mon_start := Rect2()          # Rechteck beim Ziehstart
var _panning := false              # Mittlere Maustaste: Ansicht schieben
var _hidden_layers := {}           # layer_id -> true (temporär ausgeblendet, V-Taste)
var _dirty_sections := {}          # section -> {entry:true}
var _dirty_layer_fields := {}      # layer_id -> {field:true|{model_id:true}}


func _ready() -> void:
	z_index = 60
	sync_mode()


## Eingabe-Durchlass an den Modus koppeln (Compositor hält edit_mode).
func sync_mode() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if _edit_mode() else Control.MOUSE_FILTER_IGNORE
	_drag_child = null
	queue_redraw()


func _edit_mode() -> bool:
	return comp != null and comp.edit_mode


func _cfg() -> Dictionary:
	return comp.config()


func _quads() -> Dictionary:
	return _cfg().get("quads", {})


func _hotspots() -> Dictionary:
	return _cfg().get("hotspots", {})


func _to_master(view_point: Vector2) -> Vector2:
	var t: Dictionary = comp._master_transform()
	return (view_point - t["offset"]) / t["scale"]


func _process(_delta: float) -> void:
	# Hilfe-Panel blendet sich nach kurzer Zeit von selbst aus
	if _help_visible and Time.get_ticks_msec() > _help_hide_at:
		_help_visible = false
		queue_redraw()


# ------------------------------------------------------------- Speichern

func _mark_section_entry(section: String, entry: String) -> void:
	var entries: Dictionary = _dirty_sections.get(section, {})
	entries[entry] = true
	_dirty_sections[section] = entries


func _mark_layer_field(layer_id: String, field: String, model_id := "") -> void:
	var fields: Dictionary = _dirty_layer_fields.get(layer_id, {})
	if model_id.is_empty():
		fields[field] = true
	else:
		var models: Dictionary = fields.get(field, {}) \
			if fields.get(field, {}) is Dictionary else {}
		models[model_id] = true
		fields[field] = models
	_dirty_layer_fields[layer_id] = fields


func _room_dirty() -> bool:
	return not _dirty_sections.is_empty() or not _dirty_layer_fields.is_empty()


func _layer_by_id(layers: Array, layer_id: String) -> Dictionary:
	for raw: Variant in layers:
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == layer_id:
			return raw as Dictionary
	return {}


func _clone(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value

func save_config() -> void:
	# Exakter Three-Way-Merge: Nur Pfade, die diese Editorinstanz wirklich
	# angefasst hat, werden aus dem Memory-Snapshot in die aktuelle Plattenfassung
	# uebernommen. Parallel geaenderte Layer/Modelle bleiben unangetastet.
	if _room_dirty():
		var override: Variant = comp.get("editor_config_path")
		var config_path: String = str(override) if override is String else comp.CONFIG_PATH
		var reader := FileAccess.open(config_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(reader.get_as_text()) if reader != null else null
		if not parsed is Dictionary:
			push_error("DekoEditor: %s kann nicht sicher gemergt werden" % config_path)
			return
		var disk := parsed as Dictionary
		var mem := _cfg()
		for section_value: Variant in _dirty_sections:
			var section_name := str(section_value)
			var disk_section: Dictionary = disk.get(section_name, {})
			var mem_section: Dictionary = mem.get(section_name, {})
			for entry_value: Variant in (_dirty_sections[section_name] as Dictionary):
				var entry := str(entry_value)
				if mem_section.has(entry):
					disk_section[entry] = _clone(mem_section[entry])
				else:
					disk_section.erase(entry)
			disk[section_name] = disk_section
		var disk_layers: Array = disk.get("layers", [])
		var mem_layers: Array = mem.get("layers", [])
		for layer_value: Variant in _dirty_layer_fields:
			var layer_id := str(layer_value)
			var mem_layer := _layer_by_id(mem_layers, layer_id)
			if mem_layer.is_empty():
				continue
			var disk_layer := _layer_by_id(disk_layers, layer_id)
			if disk_layer.is_empty():
				disk_layer = {"id": layer_id}
				disk_layers.append(disk_layer)
			var dirty_fields: Dictionary = _dirty_layer_fields[layer_id]
			for field_value: Variant in dirty_fields:
				var field := str(field_value)
				var marker: Variant = dirty_fields[field]
				if marker is Dictionary:
					var disk_map: Dictionary = disk_layer.get(field, {}).duplicate(true)
					var mem_map: Dictionary = mem_layer.get(field, {})
					for model_value: Variant in marker:
						var model_id := str(model_value)
						if mem_map.has(model_id):
							disk_map[model_id] = _clone(mem_map[model_id])
						else:
							disk_map.erase(model_id)
					disk_layer[field] = disk_map
				elif mem_layer.has(field):
					disk_layer[field] = _clone(mem_layer[field])
				else:
					disk_layer.erase(field)
		disk["layers"] = disk_layers
		var file := FileAccess.open(config_path, FileAccess.WRITE)
		if file == null:
			push_error("DekoEditor: %s kann nicht geschrieben werden" % config_path)
			return
		file.store_string(JSON.stringify(disk, "  ", false))
		_dirty_sections.clear()
		_dirty_layer_fields.clear()
	# Monitor-Bildschirmfläche gehört in data/monitors.json (je Modell) — separat.
	var mg: Object = _mon()
	if mg != null:
		mg.editor_save()


# ------------------------------------------------------------- Treffer-Tests

## Eckpunkt eines Flächen-Vierecks unter dem Mauszeiger (Radius 10 px).
func _corner_at(point: Vector2) -> int:
	if not _quads_visible:
		_corner_quad = ""
		return -1
	var t: Dictionary = comp._master_transform()
	for quad_name in _quads():
		var quad: Array = _quads()[quad_name].get("corners", [])
		if quad.size() != 4:
			continue
		for i in 4:
			var p: Vector2 = t["offset"] + Vector2(quad[i][0], quad[i][1]) * t["scale"]
			if p.distance_to(point) <= 10.0:
				_corner_quad = quad_name
				return i
	_corner_quad = ""
	return -1


# ---------------------------------------------- Monitor-Fenster (Bildschirm)

## Das MonitorGlowOverlay des Compositors (oder null im Editor/Vorschau).
func _mon() -> Object:
	return comp.get("_monitor_glow") if comp != null else null


func _mon_rect() -> Rect2:
	var mg: Object = _mon()
	return mg.editor_screen_rect() if mg != null else Rect2()


func _mon_corners(r: Rect2) -> Array:
	return [r.position, r.position + Vector2(r.size.x, 0), r.position + r.size,
		r.position + Vector2(0, r.size.y)]


## Griff der Monitor-Bildschirmfläche unter dem Zeiger: 0-3 Ecke, -1 Fläche
## (verschieben), -2 kein Treffer.
func _mon_handle_at(point: Vector2) -> int:
	var r := _mon_rect()
	if r.size.x < 4.0:
		return -2
	var cs := _mon_corners(r)
	for i in 4:
		if (cs[i] as Vector2).distance_to(point) <= 11.0:
			return i
	return -1 if r.has_point(point) else -2


func _mon_drag_to(point: Vector2) -> void:
	var mg: Object = _mon()
	if mg == null:
		return
	var r := _mon_start
	if _mon_drag == -1:
		r.position += point - _mon_grab
	else:
		var cs := _mon_corners(_mon_start)
		var fixed: Vector2 = cs[(_mon_drag + 2) % 4]  # gegenüberliegende Ecke bleibt
		r = Rect2(Vector2(minf(fixed.x, point.x), minf(fixed.y, point.y)),
			(point - fixed).abs())
	mg.editor_set_rect(r)
	queue_redraw()


## Hotspot-Griff: eine der 4 Ecken = Form ändern (auch schräg/vertikal),
## Mittelgriff = ganzes Polygon verschieben.
func _hotspot_handle_at(point: Vector2) -> bool:
	if not _hotspots_visible:
		return false
	var t: Dictionary = comp._master_transform()
	for hotspot_name in _hotspots():
		var pts: Array = _hotspots()[hotspot_name].get("corners", [])
		if pts.size() != 4:
			continue
		var center := Vector2.ZERO
		for i in 4:
			var p: Vector2 = t["offset"] + Vector2(pts[i][0], pts[i][1]) * t["scale"]
			center += p
			if p.distance_to(point) <= 10.0:
				_hs_drag = hotspot_name
				_hs_corner = i
				return true
		if (center / 4.0).distance_to(point) <= 12.0:
			_hs_drag = hotspot_name
			_hs_corner = -1
			_hs_grab = _to_master(point)
			_hs_start = pts.duplicate(true)
			return true
	return false


# ------------------------------------------------------------- Bearbeiten

func _hotspot_drag_to(point: Vector2) -> void:
	var pts: Array = _hotspots()[_hs_drag]["corners"]
	var m := _to_master(point)
	if _hs_corner >= 0:
		pts[_hs_corner][0] = clampf(m.x, 0.0, 1920.0)
		pts[_hs_corner][1] = clampf(m.y, 0.0, 1080.0)
	else:
		var delta := m - _hs_grab
		for i in 4:
			pts[i][0] = clampf(float(_hs_start[i][0]) + delta.x, 0.0, 1920.0)
			pts[i][1] = clampf(float(_hs_start[i][1]) + delta.y, 0.0, 1080.0)
	_mark_section_entry("hotspots", _hs_drag)
	queue_redraw()


func _quad_corner_drag_to(point: Vector2) -> void:
	var corner: Array = _quads()[_corner_quad]["corners"][_corner_drag]
	var m := _to_master(point)
	corner[0] = clampf(m.x, 0.0, 1920.0)
	corner[1] = clampf(m.y, 0.0, 1080.0)
	_mark_section_entry("quads", _corner_quad)
	comp._layout_all()  # Tiefenskalierung folgt dem Tisch-Quad live
	queue_redraw()


func _commit_zone_rect() -> void:
	var zones: Dictionary = _cfg().get("zones", {})
	if not zones.has(_active_zone):
		return
	var top_left := Vector2(minf(_zone_start.x, _zone_current.x), minf(_zone_start.y, _zone_current.y))
	var size_m := (_zone_current - _zone_start).abs()
	if size_m.x < 20.0 or size_m.y < 20.0:
		return  # Versehen — zu klein
	zones[_active_zone]["rect"] = [roundf(top_left.x), roundf(top_left.y), roundf(size_m.x), roundf(size_m.y)]
	_mark_section_entry("zones", _active_zone)
	queue_redraw()


func _model_position_editable(child: Control) -> bool:
	return not str(child.get_meta("model_selector", "")).is_empty() \
		and not _active_model(child).is_empty()


func _model_anchor_offset(child: Control) -> Vector2:
	return child.get_meta("anchor_offset", Vector2.ZERO)


func _set_model_anchor_offset(child: Control, value: Vector2) -> void:
	var layer_id := str(child.get_meta("layer_id", ""))
	var model_id := _active_model(child)
	if layer_id.is_empty() or model_id.is_empty():
		return
	for layer in _cfg().get("layers", []):
		if str(layer.get("id", "")) != layer_id:
			continue
		var offsets: Dictionary = layer.get("anchor_offset_by_model", {}).duplicate(true)
		var stored := Vector2(snappedf(value.x, 0.01), snappedf(value.y, 0.01))
		# Nullversatz darf entfallen; so bleibt die Raumdatei kompakt. Das explizite
		# Entfernen wird ebenfalls modellgenau als Dirty-Pfad markiert.
		if stored.length_squared() < 0.0001:
			offsets.erase(model_id)
			stored = Vector2.ZERO
		else:
			offsets[model_id] = [stored.x, stored.y]
		if offsets.is_empty():
			layer.erase("anchor_offset_by_model")
		else:
			layer["anchor_offset_by_model"] = offsets
		_mark_layer_field(layer_id, "anchor_offset_by_model", model_id)
		child.set_meta("anchor_offset", stored)
		# Der zugehoerige Kontaktschatten teilt denselben Modellversatz.
		for sibling in comp.get_children():
			if sibling is TextureRect \
					and str(sibling.get_meta("layer_id", "")) == layer_id + "_schatten":
				sibling.set_meta("anchor_offset", stored)
		return


func _set_model_visual_anchor(child: Control, visual_anchor: Vector2) -> void:
	var anchor_name := str(child.get_meta("anchor", ""))
	var base: Array = _cfg().get("anchors", {}).get(anchor_name, [])
	if base.size() < 2:
		return
	var clamped := [visual_anchor.x, visual_anchor.y]
	comp._clamp_to_zone(clamped, child.get_meta("zone", ""))
	_set_model_anchor_offset(child,
		Vector2(float(clamped[0]) - float(base[0]), float(clamped[1]) - float(base[1])))


func _set_shared_visual_anchor(child: Control, visual_anchor: Vector2) -> void:
	var anchor_name := str(child.get_meta("anchor", ""))
	var a: Array = _cfg().get("anchors", {}).get(anchor_name, [])
	if a.size() < 2:
		return
	var model_offset := _model_anchor_offset(child)
	var clamped := [visual_anchor.x, visual_anchor.y]
	comp._clamp_to_zone(clamped, child.get_meta("zone", ""))
	a[0] = clampf(float(clamped[0]) - model_offset.x, 0.0, 1920.0)
	a[1] = clampf(float(clamped[1]) - model_offset.y, 0.0, 1080.0)
	_mark_section_entry("anchors", anchor_name)


func _nudge_selected(dx: float, dy: float, model_specific := false) -> void:
	var anchor_name: String = _selected.get_meta("anchor", "")
	if anchor_name == "" or not _cfg()["anchors"].has(anchor_name):
		return
	var a: Array = _cfg()["anchors"][anchor_name]
	var visual := Vector2(float(a[0]), float(a[1])) + _model_anchor_offset(_selected) \
		+ Vector2(dx, dy)
	if model_specific and _model_position_editable(_selected):
		_set_model_visual_anchor(_selected, visual)
	else:
		_set_shared_visual_anchor(_selected, visual)
	comp._layout_all()
	queue_redraw()


## V-Taste: die gewählte Lage temporär aus-/einblenden (Editier-Hilfe, um
## hinter überlappende Objekte zu sehen — nicht persistiert).
func _toggle_selected_visibility() -> void:
	if _selected == null or not is_instance_valid(_selected):
		return
	var id: String = _selected.get_meta("layer_id", "")
	var vis := not _selected.visible
	_selected.visible = vis
	for c in comp.get_children():
		if c is TextureRect and str(c.get_meta("layer_id", "")) == id + "_schatten":
			c.visible = vis
	if vis:
		_hidden_layers.erase(id)
	else:
		_hidden_layers[id] = true
	queue_redraw()


func _shift_selected_z(delta: int) -> void:
	var layer_id: String = _selected.get_meta("layer_id", "")
	for layer in _cfg().get("layers", []):
		if str(layer.get("id", "")) == layer_id:
			layer["z"] = int(layer.get("z", 1)) + delta
			_mark_layer_field(layer_id, "z")
			_selected.z_index = layer["z"]
			queue_redraw()
			return


func _active_model(child: Control) -> String:
	return str(child.get_meta("active_model", ""))


## Variantenmaße bleiben am konkreten Modell. So veraendert das Einpassen eines
## schmalen A600 weder den A500 noch den breiteren A1200 desselben Layers.
func _set_layer_dimension(layer: Dictionary, child: Control, field: String, value: float) -> void:
	var selector := str(child.get_meta("model_selector", ""))
	var model_id := _active_model(child)
	if not selector.is_empty() and not model_id.is_empty():
		var map_field := field + "_by_model"
		var values: Dictionary = layer.get(map_field, {}).duplicate()
		values[model_id] = value
		layer[map_field] = values
		_mark_layer_field(str(layer.get("id", "")), map_field, model_id)
	else:
		layer[field] = value
		_mark_layer_field(str(layer.get("id", "")), field)
	child.set_meta(field, value)


## M/Shift+M: Varianten des gewaehlten Geraets vorwaerts/rueckwaerts.
## RoomPreview benutzt dafuer den rein lokalen Vorschauzustand des Compositors
## (alle renderbaren Modelle, kein Save-/Besitz-Eingriff). Im echten Spielraum
## bleiben Auswahl und Besitzpruefung bei RoomManager.
func _cycle_selected_model(direction := 1) -> bool:
	if _selected == null or not is_instance_valid(_selected):
		return false
	var selector := str(_selected.get_meta("model_selector", ""))
	if selector.is_empty():
		return false
	# Vor jedem Neuaufbau nur die tatsaechlich angefassten Modellfelder mergen.
	# Dadurch bleiben Parallel-Aenderungen und Schwestermodelle erhalten.
	if _room_dirty():
		save_config()
		if _room_dirty():
			return false  # Merge fehlgeschlagen: Editorinstanz nicht verwerfen.
	if bool(comp.get("preview_all_devices")) \
			and comp.has_method("preview_cycle_device_model"):
		var layer_id := str(_selected.get_meta("layer_id", ""))
		return comp.call("preview_cycle_device_model", selector, direction, layer_id) != null
	if not RoomManager.has_method("available_device_models"):
		return false
	var models: Array = RoomManager.call("available_device_models", selector, true)
	if models.size() < 2:
		return false
	var current := str(RoomManager.call("active_device_model", selector))
	var index := models.find(current)
	if index < 0:
		index = 0
	var next_index := posmod(index + (1 if direction >= 0 else -1), models.size())
	return bool(RoomManager.call("select_device_model", selector, str(models[next_index])))


## Auswahl nach einem Compositor-Rebuild wiederherstellen. Nur eine Referenz auf
## den bereits neu erzeugten Layer wird uebernommen; kein Konfig-/Save-Zustand.
func select_layer(child: Control) -> void:
	_selected = child
	_drag_child = null
	_drag_anchor = ""
	_drag_model_specific = false
	queue_redraw()


## Alt+Mausrad: schräger Versatz — Fuß bleibt, Oberkante wandert seitlich.
func _skew_layer(child: Control, delta: float) -> void:
	var layer_id: String = child.get_meta("layer_id", "")
	for layer in _cfg().get("layers", []):
		if str(layer.get("id", "")) == layer_id:
			var limit := maxf(float(layer.get("width", 100.0)) * 0.5, 10.0)
			var new_skew := clampf(float(child.get_meta("skew", layer.get("skew", 0.0))) \
				+ delta, -limit, limit)
			if not str(child.get_meta("model_selector", "")).is_empty() \
					and not _active_model(child).is_empty():
				_set_layer_dimension(layer, child, "skew", 0.0 if absf(new_skew) < 0.01 else new_skew)
			elif absf(new_skew) < 0.01:
				layer.erase("skew")
				new_skew = 0.0
				_mark_layer_field(layer_id, "skew")
			else:
				layer["skew"] = new_skew
				_mark_layer_field(layer_id, "skew")
			child.set_meta("skew", new_skew)
			comp._layout_all()
			queue_redraw()
			return


## Strg+Mausrad: Neigung in Grad (um den Fußpunkt, ±45° begrenzt).
func _rotate_layer(child: Control, delta: float) -> void:
	var layer_id: String = child.get_meta("layer_id", "")
	for layer in _cfg().get("layers", []):
		if str(layer.get("id", "")) == layer_id:
			var new_rot := clampf(float(child.get_meta("rotation", layer.get("rotation", 0.0))) \
				+ delta, -45.0, 45.0)
			if not str(child.get_meta("model_selector", "")).is_empty() \
					and not _active_model(child).is_empty():
				_set_layer_dimension(layer, child, "rotation", 0.0 if absf(new_rot) < 0.01 else new_rot)
			elif absf(new_rot) < 0.01:
				layer.erase("rotation")  # 0° nicht persistieren
				new_rot = 0.0
				_mark_layer_field(layer_id, "rotation")
			else:
				layer["rotation"] = new_rot
				_mark_layer_field(layer_id, "rotation")
			child.set_meta("rotation", new_rot)
			comp._layout_all()
			queue_redraw()
			return


## Shift+Mausrad: Zielhöhe — perspektivische Stauchung flacher Objekte.
func _resize_layer_height(child: Control, delta: float) -> void:
	var layer_id: String = child.get_meta("layer_id", "")
	for layer in _cfg().get("layers", []):
		if str(layer.get("id", "")) == layer_id:
			var current: float = float(child.get_meta("height", layer.get("height", 0.0)))
			if current <= 0.0 and child.texture != null:
				var tex_size: Vector2 = child.texture.get_size()
				current = float(child.get_meta("width", layer.get("width", 100.0))) \
					* tex_size.y / tex_size.x
			_set_layer_dimension(layer, child, "height", maxf(6.0, current + delta))
			comp._layout_all()
			queue_redraw()
			return


## Mausrad: width des Layers ändern; Kontaktschatten skaliert mit.
func _resize_layer(child: Control, delta: float) -> void:
	var layer_id: String = child.get_meta("layer_id", "")
	for layer in _cfg().get("layers", []):
		if str(layer.get("id", "")) == layer_id:
			var current := float(child.get_meta("width", layer.get("width", 100.0)))
			var new_width := maxf(10.0, current + delta)
			_set_layer_dimension(layer, child, "width", new_width)
			var factor := float(layer.get("shadow_scale", 1.0))
			for sibling in comp.get_children():
				if sibling is TextureRect and sibling.get_meta("layer_id", "") == layer_id + "_schatten":
					sibling.set_meta("width", new_width * 1.28 * factor)
					sibling.set_meta("height", new_width * 0.22 * factor)
			comp._layout_all()
			queue_redraw()
			return


# ------------------------------------------------------------- Eingabe

func _gui_input(event: InputEvent) -> void:
	if not _edit_mode():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Monitor-Bildschirmfläche hat Vorrang (liegt über dem Monitor)
			_mon_drag = _mon_handle_at(event.position)
			if _mon_drag != -2:
				_mon_grab = event.position
				_mon_start = _mon_rect()
				queue_redraw()
				accept_event()
				return
			_corner_drag = _corner_at(event.position)
			if _corner_drag < 0 and not _hotspot_handle_at(event.position):
				_drag_child = comp._child_at(event.position)
				_drag_anchor = _drag_child.get_meta("anchor", "") if _drag_child != null else ""
				_selected = _drag_child  # Klick ins Leere = Auswahl aufheben
				_drag_model_specific = _drag_child != null and event.ctrl_pressed \
					and _model_position_editable(_drag_child)
			queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _active_zone != "":
			_zone_dragging = true
			_zone_start = _to_master(event.position)
			_zone_current = _zone_start
			accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = true
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
			var child: Control = comp._child_at(event.position)
			if child != null:
				var direction := 1.0 if up else -1.0
				if event.alt_pressed:
					_skew_layer(child, direction * 3.0)           # schräger Versatz
				elif event.ctrl_pressed:
					_rotate_layer(child, direction * 2.0)         # Neigen
				elif event.shift_pressed:
					_resize_layer_height(child, direction * 3.0)  # Höhe/Stauchung
				else:
					_resize_layer(child, direction * 5.0)         # Breite
			else:
				# Über leerer Fläche: hinein-/herauszoomen (zum Zeiger)
				comp.editor_zoom_at(event.position, 1.15 if up else 0.87)
			accept_event()
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and _zone_dragging:
			_commit_zone_rect()
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
		_release_drags()
	elif event is InputEventMouseMotion and _panning:
		comp.editor_pan_by(event.relative)
	elif event is InputEventMouseMotion and _mon_drag != -2:
		_mon_drag_to(event.position)
	elif event is InputEventMouseMotion and _hs_drag != "":
		_hotspot_drag_to(event.position)
	elif event is InputEventMouseMotion and _corner_drag >= 0 and _corner_quad != "":
		_quad_corner_drag_to(event.position)
	elif event is InputEventMouseMotion and _zone_dragging:
		_zone_current = _to_master(event.position)
		queue_redraw()
	elif event is InputEventMouseMotion and _drag_child != null and _drag_anchor != "":
		var t: Dictionary = comp._master_transform()
		var a: Array = _cfg()["anchors"][_drag_anchor]
		var visual: Vector2 = Vector2(float(a[0]), float(a[1])) \
			+ _model_anchor_offset(_drag_child) \
			+ (event as InputEventMouseMotion).relative / float(t["scale"])
		if _drag_model_specific:
			_set_model_visual_anchor(_drag_child, visual)
		else:
			_set_shared_visual_anchor(_drag_child, visual)
		comp._layout_all()
		queue_redraw()


func _release_drags() -> void:
	_drag_child = null
	_drag_model_specific = false
	_zone_dragging = false
	_corner_drag = -1
	_hs_drag = ""
	_hs_corner = -2
	_mon_drag = -2


## Deko-Tastatur: H Hilfe, Q/T Rahmen, M Geraetemodell, 1-9 Zone,
## Pfeile = Familienanker, Strg+Pfeile = aktive Modellvariante,
## Bild auf/ab = Ebene der Auswahl.
func _unhandled_key_input(event: InputEvent) -> void:
	if not _edit_mode() or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_H and not event.echo:
		_help_visible = not _help_visible
		_help_hide_at = Time.get_ticks_msec() + 12000  # nach 12 s von selbst weg
		queue_redraw()
		return
	if event.keycode == KEY_Q and not event.echo:
		_quads_visible = not _quads_visible
		queue_redraw()
		return
	if event.keycode == KEY_T and not event.echo:
		_hotspots_visible = not _hotspots_visible
		queue_redraw()
		return
	if event.keycode == KEY_V and not event.echo:
		_toggle_selected_visibility()
		return
	if event.keycode == KEY_0 and not event.echo:
		comp.editor_reset_view()  # Zoom/Pan zurücksetzen
		return
	var idx: int = event.keycode - KEY_1
	var names: Array = _cfg().get("zones", {}).keys()
	if idx >= 0 and idx < names.size() and not event.echo:
		_active_zone = names[idx]
		queue_redraw()
		return
	if _selected == null or not is_instance_valid(_selected):
		return
	if event.keycode == KEY_M and not event.echo:
		_cycle_selected_model(-1 if event.shift_pressed else 1)
		return
	var step := 5.0 if event.shift_pressed else 1.0
	match event.keycode:
		KEY_LEFT:
			_nudge_selected(-step, 0.0, event.ctrl_pressed)
		KEY_RIGHT:
			_nudge_selected(step, 0.0, event.ctrl_pressed)
		KEY_UP:
			_nudge_selected(0.0, -step, event.ctrl_pressed)
		KEY_DOWN:
			_nudge_selected(0.0, step, event.ctrl_pressed)
		KEY_PAGEUP:
			_shift_selected_z(1)
		KEY_PAGEDOWN:
			_shift_selected_z(-1)


# --------------------------------------------- Editor-Plugin (Viewport-Drag)

func editor_pick(local: Vector2, model_specific := false) -> bool:
	_corner_drag = _corner_at(local)
	if _corner_drag >= 0:
		return true
	if _hotspot_handle_at(local):
		return true
	_drag_child = comp._child_at(local)
	if _drag_child == null:
		return false
	_drag_anchor = _drag_child.get_meta("anchor", "")
	_selected = _drag_child
	_drag_model_specific = model_specific and _model_position_editable(_drag_child)
	var a: Array = _cfg()["anchors"].get(_drag_anchor, [0, 0])
	_editor_grab = Vector2(a[0], a[1]) + _model_anchor_offset(_drag_child) \
		- _to_master(local)
	queue_redraw()
	return true


func editor_drag_to(local: Vector2) -> bool:
	if _hs_drag != "":
		_hotspot_drag_to(local)
		return true
	if _corner_drag >= 0 and _corner_quad != "":
		_quad_corner_drag_to(local)
		return true
	if _drag_child == null or _drag_anchor == "":
		return false
	var m := _to_master(local) + _editor_grab
	if _drag_model_specific:
		_set_model_visual_anchor(_drag_child, m)
	else:
		_set_shared_visual_anchor(_drag_child, m)
	comp._layout_all()
	queue_redraw()
	return true


func editor_release() -> void:
	if _drag_child != null or _corner_drag >= 0 or _hs_drag != "":
		save_config()
	_release_drags()


func editor_wheel(local: Vector2, direction: float, shift: bool, ctrl: bool = false, alt: bool = false) -> bool:
	var child: Control = comp._child_at(local)
	if child == null:
		return false
	if alt:
		_skew_layer(child, direction * 3.0)
	elif ctrl:
		_rotate_layer(child, direction * 2.0)
	elif shift:
		_resize_layer_height(child, direction * 3.0)
	else:
		_resize_layer(child, direction * 5.0)
	save_config()
	return true



# ------------------------------------------------------------- Zeichnen
func _draw() -> void:
	DekoDraw.render(self)
