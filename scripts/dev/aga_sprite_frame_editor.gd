@tool
extends Control
## F6-Vorschau fuer AGA-Atlanten. Rahmen, Pivot und Laufzeitskala werden direkt
## in data/aga_sprite_frames.json bearbeitet. F8 speichert den gemeinsamen
## Vertrag, den die Minispiele ohne Konvertierung verwenden.

const Catalog := preload("res://scripts/gfx/aga_sprite_catalog.gd")
const DATA_PATH := "res://data/aga_sprite_frames.json"

const BG := Color("070c14")
const PANEL := Color("0b1420")
const CYAN := Color("42d8ff")
const GREEN := Color("48f58a")
const AMBER := Color("ffb02e")
const PAPER := Color("eee8d7")

@export var atlas_id := "household_props"

var _data: Dictionary = {}
var _texture: Texture2D
var _frame_names: Array[String] = []
var _selected := ""
var _drag_mode := ""
var _drag_origin := Vector2.ZERO
var _drag_region := Rect2()
var _status := "F8 speichert · F4 Einzelansicht"
var _clean_view := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_data()
	grab_focus()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is not Dictionary:
		_status = "FEHLER · Atlasdaten konnten nicht gelesen werden"
		return
	_data = parsed as Dictionary
	var atlas_data := _atlas_data()
	var texture_path := str(atlas_data.get("texture", ""))
	_texture = load(texture_path) as Texture2D if ResourceLoader.exists(texture_path) else null
	_frame_names.clear()
	for frame_key: Variant in (atlas_data.get("frames", {}) as Dictionary).keys():
		_frame_names.append(str(frame_key))
	_frame_names.sort()
	_selected = _frame_names[0] if not _frame_names.is_empty() else ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_drag_mode = ""
		accept_event()
	elif event is InputEventMouseMotion and not _drag_mode.is_empty():
		_apply_drag(event.position)
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		accept_event()


func _begin_drag(mouse_at: Vector2) -> void:
	var hit := _frame_at(mouse_at)
	if not hit.is_empty():
		_selected = hit
	var selected_rect := _screen_rect(_selected)
	if not selected_rect.has_area() or not selected_rect.grow(5.0).has_point(mouse_at):
		queue_redraw()
		return
	_drag_mode = "resize" if mouse_at.distance_to(selected_rect.end) <= 18.0 else "move"
	_drag_origin = mouse_at
	_drag_region = _selected_region()
	queue_redraw()


func _apply_drag(mouse_at: Vector2) -> void:
	var atlas_rect := _atlas_rect()
	if not atlas_rect.has_area() or _texture == null:
		return
	var factor := atlas_rect.size.x / float(_texture.get_width())
	var delta := (mouse_at - _drag_origin) / maxf(factor, 0.001)
	var changed := _drag_region
	if _drag_mode == "move":
		changed.position = (_drag_region.position + delta).round()
	else:
		changed.size = Vector2(maxf(4.0, _drag_region.size.x + delta.x),
			maxf(4.0, _drag_region.size.y + delta.y)).round()
	changed.position.x = clampf(changed.position.x, 0.0,
		float(_texture.get_width()) - changed.size.x)
	changed.position.y = clampf(changed.position.y, 0.0,
		float(_texture.get_height()) - changed.size.y)
	changed.size.x = minf(changed.size.x, float(_texture.get_width()) - changed.position.x)
	changed.size.y = minf(changed.size.y, float(_texture.get_height()) - changed.position.y)
	_set_selected_region(changed)
	queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_F8 or (event.ctrl_pressed and event.keycode == KEY_S):
		_save()
		return
	if event.keycode == KEY_F4:
		_clean_view = not _clean_view
		queue_redraw()
		return
	if event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_adjust_scale(0.05 if event.keycode == KEY_PAGEUP else -0.05)
		return
	if event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
		_select_relative(-1 if event.keycode == KEY_BRACKETLEFT else 1)
		return
	var delta := Vector2.ZERO
	match event.keycode:
		KEY_LEFT: delta.x = -1.0
		KEY_RIGHT: delta.x = 1.0
		KEY_UP: delta.y = -1.0
		KEY_DOWN: delta.y = 1.0
		_: return
	if event.ctrl_pressed:
		_adjust_pivot(delta * 0.01)
	elif event.shift_pressed:
		var region := _selected_region()
		region.size = (region.size + delta).max(Vector2(4, 4))
		_set_selected_region(region)
	else:
		var region := _selected_region()
		region.position += delta
		_set_selected_region(region)
	queue_redraw()


func _save() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if file == null:
		_status = "FEHLER · %s" % FileAccess.get_open_error()
		queue_redraw()
		return
	file.store_string(JSON.stringify(_data, "  ", false) + "\n")
	file.close()
	Catalog.reload()
	_status = "GESPEICHERT · Laufzeitkatalog neu geladen"
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(0, 0, size.x, 62), Color("073d77"))
	_text(Vector2(22, 39), "AGA-SPRITEWERK · %s" % atlas_id.to_upper(), PAPER, 26)
	_text(Vector2(size.x - 515, 37), "F6 VORSCHAU · F8 SPEICHERN · F4 ANSICHT", AMBER, 17)
	if _texture == null:
		_text(Vector2(30, 110), "ATLAS FEHLT", Color.RED, 28)
		return
	if _clean_view:
		_draw_clean_preview()
	else:
		_draw_atlas_editor()


func _draw_atlas_editor() -> void:
	var work := _work_rect()
	draw_rect(work, PANEL)
	_draw_checker(work)
	var atlas_rect := _atlas_rect()
	draw_texture_rect(_texture, atlas_rect, false)
	for frame_name in _frame_names:
		var screen_region := _screen_rect(frame_name)
		var is_selected := frame_name == _selected
		draw_rect(screen_region, AMBER if is_selected else Color(CYAN, 0.55), false,
			3.0 if is_selected else 1.0)
		if is_selected:
			draw_rect(Rect2(screen_region.end - Vector2(8, 8), Vector2(16, 16)), GREEN)
		_text(screen_region.position + Vector2(4, 15), frame_name.to_upper(),
			AMBER if is_selected else PAPER, 13)
	_draw_inspector()


func _draw_clean_preview() -> void:
	var preview_rect := Rect2(28, 92, size.x - 56, size.y - 132)
	draw_rect(preview_rect, PANEL)
	_draw_checker(preview_rect)
	_draw_local_frame(_selected, preview_rect.get_center(), preview_rect.size * 0.72)
	_text(Vector2(48, 124), _selected.to_upper(), AMBER, 24)
	_text(Vector2(48, size.y - 24), "F4 · ZURUECK ZUM RAHMENEDITOR", CYAN, 16)


func _draw_inspector() -> void:
	var left := size.x - 350.0
	var panel := Rect2(left, 82, 330, size.y - 102)
	draw_rect(panel, Color("0a111b"))
	draw_rect(panel, CYAN.darkened(0.35), false, 2.0)
	_text(panel.position + Vector2(18, 32), "RAHMENWERKZEUG", AMBER, 21)
	_text(panel.position + Vector2(18, 63), _selected.to_upper(), PAPER, 20)
	var preview := Rect2(panel.position + Vector2(18, 82), Vector2(294, 245))
	_draw_checker(preview)
	_draw_local_frame(_selected, preview.get_center(), preview.size * 0.76)
	draw_rect(preview, Color(CYAN, 0.5), false, 1.0)
	var frame_data := _selected_data()
	var source := Catalog.source_rect(frame_data)
	var pivot_at := Catalog.pivot(frame_data)
	_text(panel.position + Vector2(18, 360), "QUELLE  %d,%d · %d×%d" % [source.position.x,
		source.position.y, source.size.x, source.size.y], GREEN, 16)
	_text(panel.position + Vector2(18, 389), "PIVOT   %.2f / %.2f" % [pivot_at.x, pivot_at.y], CYAN, 16)
	_text(panel.position + Vector2(18, 418), "SKALA   %.2f×" % float(frame_data.get("scale", 1.0)), CYAN, 16)
	_text(panel.position + Vector2(18, 468), "MAUS", AMBER, 15)
	_text(panel.position + Vector2(18, 493), "Rahmen ziehen · Ecke skaliert", PAPER, 14)
	_text(panel.position + Vector2(18, 530), "TASTATUR", AMBER, 15)
	_text(panel.position + Vector2(18, 555), "Pfeile · Rahmen verschieben", PAPER, 14)
	_text(panel.position + Vector2(18, 578), "Shift+Pfeile · Groesse", PAPER, 14)
	_text(panel.position + Vector2(18, 601), "Ctrl+Pfeile · Pivot", PAPER, 14)
	_text(panel.position + Vector2(18, 624), "Bild hoch/runter · Skala", PAPER, 14)
	_text(panel.position + Vector2(18, 647), "[ / ] · Motiv wechseln", PAPER, 14)
	_text(panel.position + Vector2(18, panel.size.y - 24), _status, GREEN, 13)


func _draw_checker(rect: Rect2) -> void:
	draw_rect(rect, Color("111925"))
	var cell := 24.0
	for row in ceili(rect.size.y / cell):
		for column in ceili(rect.size.x / cell):
			if (row + column) % 2 == 0:
				draw_rect(Rect2(rect.position + Vector2(column, row) * cell,
					Vector2(cell, cell)), Color("182331"))


func _work_rect() -> Rect2:
	return Rect2(20, 82, maxf(420.0, size.x - 390.0), maxf(380.0, size.y - 102.0))


func _atlas_rect() -> Rect2:
	if _texture == null:
		return Rect2()
	var work := _work_rect().grow(-18.0)
	var texture_size := Vector2(_texture.get_width(), _texture.get_height())
	var factor := minf(work.size.x / texture_size.x, work.size.y / texture_size.y)
	var fitted := texture_size * factor
	return Rect2((work.get_center() - fitted * 0.5).round(), fitted.round())


func _screen_rect(frame_name: String) -> Rect2:
	if _texture == null:
		return Rect2()
	var atlas_rect := _atlas_rect()
	var source := Catalog.source_rect(_frame_data(frame_name))
	var factor := atlas_rect.size.x / float(_texture.get_width())
	return Rect2(atlas_rect.position + source.position * factor, source.size * factor)


func _draw_local_frame(frame_name: String, centre: Vector2, max_size: Vector2) -> Rect2:
	var frame_data := _frame_data(frame_name)
	var source := Catalog.source_rect(frame_data)
	if _texture == null or not source.has_area():
		return Rect2()
	var fit := minf(max_size.x / source.size.x, max_size.y / source.size.y)
	fit *= float(frame_data.get("scale", 1.0))
	var draw_size := (source.size * fit).round()
	var draw_at := (centre - draw_size * Catalog.pivot(frame_data)).round()
	var destination := Rect2(draw_at, draw_size)
	draw_texture_rect_region(_texture, destination, source, Color.WHITE, false, true)
	return destination


func _frame_at(mouse_at: Vector2) -> String:
	for index in range(_frame_names.size() - 1, -1, -1):
		var frame_name := _frame_names[index]
		if _screen_rect(frame_name).has_point(mouse_at):
			return frame_name
	return ""


func _atlas_data() -> Dictionary:
	return ((_data.get("atlases", {}) as Dictionary).get(atlas_id, {}) as Dictionary)


func _frame_data(frame_name: String) -> Dictionary:
	return ((_atlas_data().get("frames", {}) as Dictionary).get(frame_name, {}) as Dictionary)


func _selected_data() -> Dictionary:
	return _frame_data(_selected)


func _selected_region() -> Rect2:
	return Catalog.source_rect(_selected_data())


func _set_selected_region(region: Rect2) -> void:
	var frame_data := _selected_data().duplicate(true)
	frame_data["region"] = [roundi(region.position.x), roundi(region.position.y),
		maxi(4, roundi(region.size.x)), maxi(4, roundi(region.size.y))]
	_set_selected_data(frame_data)


func _adjust_pivot(delta: Vector2) -> void:
	var frame_data := _selected_data().duplicate(true)
	var next_pivot := (Catalog.pivot(frame_data) + delta).clamp(Vector2.ZERO, Vector2.ONE)
	frame_data["pivot"] = [snappedf(next_pivot.x, 0.01), snappedf(next_pivot.y, 0.01)]
	_set_selected_data(frame_data)
	queue_redraw()


func _adjust_scale(delta: float) -> void:
	var frame_data := _selected_data().duplicate(true)
	frame_data["scale"] = clampf(float(frame_data.get("scale", 1.0)) + delta, 0.25, 2.5)
	_set_selected_data(frame_data)
	queue_redraw()


func _set_selected_data(frame_data: Dictionary) -> void:
	var atlases := _data.get("atlases", {}) as Dictionary
	var atlas_data := _atlas_data().duplicate(true)
	var frames := atlas_data.get("frames", {}) as Dictionary
	frames[_selected] = frame_data
	atlas_data["frames"] = frames
	atlases[atlas_id] = atlas_data
	_data["atlases"] = atlases


func _select_relative(delta: int) -> void:
	if _frame_names.is_empty():
		return
	var index := _frame_names.find(_selected)
	_selected = _frame_names[posmod(index + delta, _frame_names.size())]
	queue_redraw()


func _text(at: Vector2, value: String, color: Color, font_size: int) -> void:
	draw_string(get_theme_default_font(), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, color)
