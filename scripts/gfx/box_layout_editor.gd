extends Control
## Big-Box-Layoutwerkstatt. Vorder-/Rueckcover und Diskettenanzahl-Badge liegen
## getrennt in data/software_box_layout.json. Die Diskettenvorschau kommt bewusst
## aus DiskComposer und damit aus dem bereits vorhandenen DiskEditor-Layout.

const LAYOUT_PATH := "res://data/software_box_layout.json"
const MASTER_PATH := "res://assets/backgrounds/layers/GAME_WHITE_BIGBOX_MASTER_V01.png"
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const BoxComposer := preload("res://scripts/gfx/software_box_composer.gd")
const HANDLE := 10.0

var _master: Texture2D
var _ids: Array = []
var _index := 0
var _side := "front"
var _element := "cover"
var _disk_color := "red"
var _layout: Dictionary = {}
var _master_rect := Rect2()
var _dragging := false
var _resize := -1
var _grab := Vector2.ZERO
var _drag_origin: Array[Vector2] = []
var _saved_flash := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_master = RuntimeImages.texture(MASTER_PATH, 1200)
	_load_layout()
	_ids = SoftwareBible.illustrated_games()
	_ids.sort()
	var syndicate := _ids.find("syndicate")
	_index = syndicate if syndicate >= 0 else 0
	set_process(true)
	grab_focus.call_deferred()


func _process(delta: float) -> void:
	if _saved_flash > 0.0:
		_saved_flash = maxf(0.0, _saved_flash - delta)
	queue_redraw()


func _load_layout() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH)) \
		if FileAccess.file_exists(LAYOUT_PATH) else null
	_layout = parsed if parsed is Dictionary else {
		"schema": 2, "master": MASTER_PATH,
		"front": {"cover": {"x": 0.481, "y": 0.472, "w": 0.654, "h": 0.658},
			"disk_badge": {"x": 0.694, "y": 0.778, "w": 0.255, "h": 0.072}},
		"back": {"cover": {"x": 0.481, "y": 0.472, "w": 0.654, "h": 0.658},
			"disk_badge": {"x": 0.694, "y": 0.778, "w": 0.255, "h": 0.072}},
	}
	_ensure_quads()


func _ensure_quads() -> void:
	for side: String in ["front", "back"]:
		for element: String in ["cover", "disk_badge"]:
			var raw: Dictionary = _layout[side][element]
			if raw.get("quad", []) is Array and (raw.get("quad", []) as Array).size() == 4:
				continue
			var center := Vector2(float(raw.get("x", 0.5)), float(raw.get("y", 0.5)))
			var half := Vector2(float(raw.get("w", 0.1)), float(raw.get("h", 0.1))) * 0.5
			raw["quad"] = [[center.x - half.x, center.y - half.y],
				[center.x + half.x, center.y - half.y], [center.x + half.x, center.y + half.y],
				[center.x - half.x, center.y + half.y]]


func _save() -> void:
	_layout["schema"] = 2
	_layout["master"] = MASTER_PATH
	_layout["comment"] = "Single Source fuer Big-Box-Cover und Diskettenbadge. Vierpunkt-Projektion: TL, TR, BR, BL. Bearbeitet mit scenes/editors/BoxLayoutEditor.tscn."
	for side: String in ["front", "back"]:
		for element: String in ["cover", "disk_badge"]:
			var rect: Dictionary = _layout[side][element]
			for key: String in ["x", "y", "w", "h"]:
				rect[key] = snappedf(float(rect[key]), 0.001)
			var saved_quad: Array = rect.get("quad", [])
			for index in saved_quad.size():
				saved_quad[index] = [snappedf(float(saved_quad[index][0]), 0.001),
					snappedf(float(saved_quad[index][1]), 0.001)]
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_layout, "  ", false))
		BoxComposer.reload()
		_saved_flash = 1.3


func _software_id() -> String:
	return str(_ids[_index]) if not _ids.is_empty() else ""


func _disk_count() -> int:
	return maxi(1, SoftwareBible.disk_count(_software_id()))


func _current() -> Dictionary:
	return _layout[_side][_element]


func _compute_master_rect() -> void:
	if _master == null:
		_master_rect = Rect2()
		return
	var available := Rect2(28, 108, size.x * 0.58, size.y - 142)
	var ratio := minf(available.size.x / _master.get_width(), available.size.y / _master.get_height())
	var draw_size := Vector2(_master.get_size()) * ratio
	_master_rect = Rect2(available.position + (available.size - draw_size) * 0.5, draw_size)


func _frame_rect(element := "") -> Rect2:
	var points := _frame_points(element)
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	return Rect2(min_point, max_point - min_point)


func _quad(element := "") -> Array:
	element = _element if element.is_empty() else element
	return _layout[_side][element].get("quad", [])


func _frame_points(element := "") -> Array[Vector2]:
	var points: Array[Vector2] = []
	for raw: Variant in _quad(element):
		points.append(_master_rect.position + Vector2(float(raw[0]), float(raw[1])) * _master_rect.size)
	return points


func _frame_polygon(element := "") -> PackedVector2Array:
	return PackedVector2Array(_frame_points(element))


func _corner_at(point: Vector2) -> int:
	for index in 4:
		if _frame_points()[index].distance_to(point) <= HANDLE + 3.0:
			return index
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_compute_master_rect()
			_resize = _corner_at(event.position)
			if _resize < 0 and Geometry2D.is_point_in_polygon(event.position, _frame_polygon()):
				_dragging = true
				_grab = event.position
				_drag_origin = _normalized_quad()
		else:
			_dragging = false
			_resize = -1
	elif event is InputEventMouseMotion and _master_rect.size.x > 1.0:
		if _resize >= 0:
			_store_corner(_resize, event.position)
		elif _dragging:
			var delta: Vector2 = (event.position - _grab) / _master_rect.size
			var raw_quad: Array = _quad()
			for index in 4:
				raw_quad[index] = [clampf(_drag_origin[index].x + delta.x, 0.0, 1.0),
					clampf(_drag_origin[index].y + delta.y, 0.0, 1.0)]
			_sync_legacy_rect()
		queue_redraw()


func _normalized_quad() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for raw: Variant in _quad():
		result.append(Vector2(float(raw[0]), float(raw[1])))
	return result


func _store_corner(index: int, view_point: Vector2) -> void:
	var normalized: Vector2 = (view_point - _master_rect.position) / _master_rect.size
	var raw_quad: Array = _quad()
	raw_quad[index] = [clampf(normalized.x, 0.0, 1.0), clampf(normalized.y, 0.0, 1.0)]
	_sync_legacy_rect()


func _sync_legacy_rect() -> void:
	var points := _normalized_quad()
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var raw: Dictionary = _current()
	raw["x"] = (min_point.x + max_point.x) * 0.5
	raw["y"] = (min_point.y + max_point.y) * 0.5
	raw["w"] = max_point.x - min_point.x
	raw["h"] = max_point.y - min_point.y


## TAB ist in Godot standardmaessig Fokusnavigation und erreicht den
## unhandled-Pfad deshalb nicht verlaesslich. Der Editor faengt seine globalen
## Werkstatt-Shortcuts bewusst frueh ab.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var handled := true
	match event.keycode:
		KEY_S: _save()
		KEY_TAB:
			_side = "back" if _side == "front" else "front"
		KEY_B:
			_element = "disk_badge" if _element == "cover" else "cover"
		KEY_C:
			_disk_color = "purple" if _disk_color == "red" else "red"
		KEY_LEFT:
			if not _ids.is_empty(): _index = wrapi(_index - 1, 0, _ids.size())
		KEY_RIGHT:
			if not _ids.is_empty(): _index = wrapi(_index + 1, 0, _ids.size())
		KEY_R:
			_layout[_side][_element] = ({"x": 0.481, "y": 0.472, "w": 0.654, "h": 0.658,
				"quad": [[0.154, 0.143], [0.808, 0.143], [0.808, 0.801], [0.154, 0.779]]} \
				if _element == "cover" else {"x": 0.694, "y": 0.778, "w": 0.255, "h": 0.072,
					"quad": [[0.566, 0.742], [0.821, 0.742], [0.821, 0.814], [0.566, 0.806]]})
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(20, 24, 34))
	_compute_master_rect()
	var font := Wb13.font()
	if _master == null or _ids.is_empty():
		draw_string(font, Vector2(22, 42), "Box-Master oder SoftwareBible fehlt.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.RED)
		return
	draw_texture_rect(_master, _master_rect, false)
	var cover_kind := "box_back" if _side == "back" else "box_front"
	var cover := SoftwareBible.art_texture(_software_id(), cover_kind)
	if cover != null:
		_draw_texture_quad(cover, _frame_points("cover"))
	var badge_points := _frame_points("disk_badge")
	var badge_rect := _frame_rect("disk_badge")
	var badge_color := Color8(116, 62, 145, 238) if _disk_color == "purple" else Color8(178, 48, 52, 238)
	draw_colored_polygon(PackedVector2Array(badge_points), badge_color)
	draw_polyline(PackedVector2Array(badge_points + [badge_points[0]]), Color8(255, 238, 200), 2.0)
	draw_string(font, badge_rect.position + Vector2(0, badge_rect.size.y * 0.68),
		"%d DISKETTEN" % _disk_count(), HORIZONTAL_ALIGNMENT_CENTER, badge_rect.size.x,
		maxi(8, int(badge_rect.size.y * 0.42)), Color8(255, 244, 218))
	var active_points := _frame_points()
	draw_polyline(PackedVector2Array(active_points + [active_points[0]]), Color8(70, 255, 145), 3.0)
	for corner: Vector2 in active_points:
		draw_rect(Rect2(corner - Vector2.ONE * HANDLE * 0.5, Vector2.ONE * HANDLE), Color8(255, 214, 74))

	var disk_set := BoxComposer.disk_set_texture(_software_id(), _disk_color, _disk_count(), 720)
	if disk_set != null:
		var panel := Rect2(size.x * 0.625, 130, size.x * 0.35, size.y * 0.62)
		draw_rect(panel, Color8(8, 12, 22))
		draw_rect(panel, Wb13.white(), false, 2.0)
		var ratio := minf(panel.size.x / disk_set.get_width(), panel.size.y / disk_set.get_height())
		var disk_size := Vector2(disk_set.get_size()) * ratio
		draw_texture_rect(disk_set, Rect2(panel.position + (panel.size - disk_size) * 0.5, disk_size), false)

	var title := str(SoftwareBible.entry(_software_id()).get("display_name", _software_id()))
	var lines := [
		"BIG-BOX LAYOUT EDITOR · %s · %s" % [_side.to_upper(), _element.to_upper()],
		"TAB Vorder/Rueck · B Cover/Badge · C Rot/Lila · ←/→ Titel · S Speichern · R Reset",
		"Ziehen = alles verschieben · JEDE Ecke frei ziehen = Perspektive · Disketten rechts nutzen den DiskEditor",
		"%s · %d Diskette(n) · %s" % [title, _disk_count(), _disk_color.to_upper()],
	]
	var y := 26.0
	for line: String in lines:
		draw_string(font, Vector2(20, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Wb13.white())
		y += 22.0
	if _saved_flash > 0.0:
		draw_string(font, Vector2(size.x * 0.63, size.y - 34), "GESPEICHERT · data/software_box_layout.json",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.3, 1.0, 0.55, _saved_flash))


func _draw_texture_quad(texture: Texture2D, points: Array[Vector2]) -> void:
	if texture == null or points.size() != 4:
		return
	var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	draw_primitive(PackedVector2Array([points[0], points[1], points[2]]), colors,
		PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE]), texture)
	draw_primitive(PackedVector2Array([points[0], points[2], points[3]]), colors,
		PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2(0, 1)]), texture)
