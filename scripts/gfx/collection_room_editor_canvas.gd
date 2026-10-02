class_name CollectionRoomEditorCanvas
extends Control
## Direkte Editorflaeche fuer die Zimmer-Gegenwand. Runtime und Editor lesen
## dieselben normalisierten Rechtecke aus collection_room_layout.json.

const Layout := preload("res://scripts/gfx/collection_room_layout.gd")
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const HANDLE := 11.0

var monitor_model := "commodore_1084s"
var selected := "cabinet"
var _document: Dictionary = {}
var _background: Texture2D
var _textures: Dictionary = {}
var _view := Rect2()
var _drag := false
var _resize := -1
var _grab := Vector2.ZERO
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	reload_layout()
	set_process(true)
	grab_focus.call_deferred()


func reload_layout() -> void:
	Layout.reload()
	_document = Layout.data().duplicate(true)
	_background = RuntimeImages.texture(str(_document.get("background", "")), 1920)
	_textures.clear()
	for id: String in (_document.get("objects", {}) as Dictionary):
		_textures[id] = RuntimeImages.texture(str(_document["objects"][id].get("asset", "")), 900)
	queue_redraw()


func select_monitor(model: String) -> void:
	if model in ["commodore_1084s", "commodore_1901"]:
		monitor_model = model
		selected = "monitor_" + model
		queue_redraw()


func save_layout() -> bool:
	_document["schema"] = 1
	_document["comment"] = "Sammlerwand der Zimmer-Gegenansicht. Bearbeitet mit scenes/editors/RoomEditor.tscn. Alle Rechtecke sind normalisierte x/y/w/h-Werte."
	for id: String in (_document.get("objects", {}) as Dictionary):
		var raw: Dictionary = _document["objects"][id].get("rect", {})
		for key: String in ["x", "y", "w", "h"]:
			raw[key] = snappedf(float(raw.get(key, 0.0)), 0.001)
	var ok := Layout.save(_document)
	if ok:
		_flash = 1.4
	return ok


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _compute_view() -> void:
	if _background == null:
		_view = Rect2()
		return
	var pad := Vector2(22, 22)
	var available := size - pad * 2.0
	var factor := minf(available.x / _background.get_width(), available.y / _background.get_height())
	var draw_size := Vector2(_background.get_size()) * factor
	_view = Rect2((size - draw_size) * 0.5, draw_size)


func _id() -> String:
	return selected if selected == "cabinet" else "monitor_" + monitor_model


func _raw(id := "") -> Dictionary:
	id = _id() if id.is_empty() else id
	return (_document.get("objects", {}) as Dictionary).get(id, {}).get("rect", {})


func _object_rect(id := "") -> Rect2:
	var raw := _raw(id)
	return Rect2(_view.position + Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0))) * _view.size,
		Vector2(float(raw.get("w", 0.0)), float(raw.get("h", 0.0))) * _view.size)


func _corners(r: Rect2) -> Array[Vector2]:
	return [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]


func _corner_at(point: Vector2) -> int:
	for i in 4:
		if _corners(_object_rect())[i].distance_to(point) <= HANDLE + 4.0:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_compute_view()
			# Zuerst sichtbare Objekte waehlen, dann Griff/Drag beginnen.
			for id: String in ["monitor_" + monitor_model, "cabinet"]:
				if _object_rect(id).has_point(event.position):
					selected = "cabinet" if id == "cabinet" else id
					break
			_resize = _corner_at(event.position)
			if _resize < 0 and _object_rect().has_point(event.position):
				_drag = true
				_grab = event.position - _object_rect().position
		else:
			_drag = false
			_resize = -1
	elif event is InputEventMouseMotion and _view.size.x > 1.0:
		if _resize >= 0:
			var fixed := _corners(_object_rect())[(_resize + 2) % 4]
			var next: Rect2 = Rect2(Vector2(minf(fixed.x, event.position.x), minf(fixed.y, event.position.y)),
				(event.position - fixed).abs())
			_store_rect(next)
		elif _drag:
			var raw: Dictionary = _raw()
			var p: Vector2 = (event.position - _grab - _view.position) / _view.size
			raw["x"] = clampf(p.x, -0.25, 1.0)
			raw["y"] = clampf(p.y, -0.25, 1.0)
		queue_redraw()


func _store_rect(r: Rect2) -> void:
	var raw: Dictionary = _raw()
	var p: Vector2 = (r.position - _view.position) / _view.size
	var s: Vector2 = r.size / _view.size
	raw["x"] = clampf(p.x, -0.25, 1.0)
	raw["y"] = clampf(p.y, -0.25, 1.0)
	raw["w"] = clampf(s.x, 0.03, 1.25)
	raw["h"] = clampf(s.y, 0.03, 1.25)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(14, 17, 24))
	_compute_view()
	if _background == null:
		draw_string(Wb13.font(), Vector2(20, 34), "Gegenwand-Master fehlt", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.RED)
		return
	draw_texture_rect(_background, _view, false)
	for id: String in ["cabinet", "monitor_" + monitor_model]:
		var texture := _textures.get(id) as Texture2D
		if texture != null:
			draw_texture_rect(texture, _object_rect(id), false)
	var active := _object_rect()
	var accent := Color8(80, 255, 145)
	draw_rect(active, accent, false, 3.0)
	for point: Vector2 in _corners(active):
		draw_rect(Rect2(point - Vector2.ONE * HANDLE * 0.5, Vector2.ONE * HANDLE), Color8(255, 212, 70))
	draw_string(Wb13.font(), _view.position + Vector2(9, 22),
		"SAMMLERWAND · %s · ZIEHEN = POSITION · ECKEN = GROESSE" % _id().to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, _view.size.x - 18, 16, Wb13.white())
	if _flash > 0.0:
		draw_string(Wb13.font(), Vector2(22, size.y - 8), "GESPEICHERT · collection_room_layout.json",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.35, 1.0, 0.55, _flash))
