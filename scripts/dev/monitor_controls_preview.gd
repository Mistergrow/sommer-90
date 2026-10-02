@tool
extends Control
## Kalibrierwerkstatt fuer Bildschirm, Service-Regler und Einschalter aller
## Raum-CRTs. Die Rechtecke werden direkt auf dem transparenten Modellasset
## bearbeitet und mit F8 in data/monitors.json gespeichert.

const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")
const MODEL_IDS := [
	"commodore_1084s", "commodore_1901", "commodore_1942", "multisync_17",
]
const REGIONS := ["screen", "service", "power"]
const REGION_LABELS := {
	"screen": "BILDSCHIRM",
	"service": "SERVICE / REGLER",
	"power": "EINSCHALTER",
}
const REGION_COLORS := {
	"screen": Color("35d9ff"),
	"service": Color("ffb12d"),
	"power": Color("41f16a"),
}

@export_category("CRT-Modell")
@export_enum("Commodore 1084S", "Commodore 1901", "Commodore 1942", "17-Zoll Multisync") \
var preview_model := 0:
	set(value):
		preview_model = clampi(value, 0, MODEL_IDS.size() - 1)
		_texture = null
		queue_redraw()

var _texture: Texture2D = null
var _selected_region := "power"
var _working: Dictionary = {}
var _drag_origin := Vector2.ZERO
var _drag_rect := Rect2()
var _drag_resize := false
var _dragging := false
var _status := "TAB waehlt · Ziehen verschiebt · Ecke skaliert · F8 speichert"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process_unhandled_key_input(true)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0a0e13"))
	var stage := _stage_rect()
	draw_rect(stage.grow(10.0), Color("111923"), true)
	draw_rect(stage.grow(10.0), Color("32718e"), false, 2.0)
	var asset_rect := _asset_rect()
	if _monitor_texture() != null:
		draw_texture_rect(_texture, asset_rect, false)
	for region_id: String in REGIONS:
		var rect := _region_screen_rect(region_id)
		if rect.size.x <= 0.0:
			continue
		var color: Color = REGION_COLORS[region_id]
		draw_rect(rect, Color(color, 0.13), true)
		draw_rect(rect, Color.WHITE if region_id == _selected_region else color,
			false, 3.0 if region_id == _selected_region else 2.0)
		if region_id == _selected_region:
			draw_rect(Rect2(rect.end - Vector2(9, 9), Vector2(18, 18)), color, true)
		_draw_label(rect.position + Vector2(4, -7), str(REGION_LABELS[region_id]), color, 13)

	var model := _model_id()
	var profile := MonitorProfile.profile_for_model(model)
	_draw_label(Vector2(36, 34), "MONITOR-ANKERWERKSTATT · %s" %
		str(profile.get("display_name", model)).to_upper(), Color("ffb12d"), 22)
	_draw_label(Vector2(36, size.y - 30), _status, Color("9dc4d1"), 14)
	var info_x := size.x - 300.0
	_draw_label(Vector2(info_x, 96), "MODELLFLAECHEN", Color("35d9ff"), 16)
	var line_y := 132.0
	for region_id: String in REGIONS:
		var r := _region_frac(region_id)
		var prefix := "> " if region_id == _selected_region else "  "
		_draw_label(Vector2(info_x, line_y), "%s%s" % [prefix, REGION_LABELS[region_id]],
			REGION_COLORS[region_id], 14)
		_draw_label(Vector2(info_x + 16, line_y + 22),
			"x %.3f  y %.3f  b %.3f  h %.3f" % [r.position.x, r.position.y,
				r.size.x, r.size.y], Color("d3d9db"), 12)
		line_y += 70.0
	_draw_label(Vector2(info_x, line_y + 18),
		"1–4 Modell · Pfeile fein\nShift+Pfeile = Groesse\nF8 = monitors.json schreiben",
		Color("83919b"), 12)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			for region_id: String in ["power", "service", "screen"]:
				var rect := _region_screen_rect(region_id)
				if rect.grow(6.0).has_point(event.position):
					_selected_region = region_id
					_drag_origin = event.position
					_drag_rect = _region_frac(region_id)
					_drag_resize = event.position.distance_to(rect.end) <= 22.0
					_dragging = true
					queue_redraw()
					accept_event()
					return
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var asset := _asset_rect()
		var pointer_delta: Vector2 = event.position - _drag_origin
		var normalized_delta := Vector2(pointer_delta.x / maxf(1.0, asset.size.x),
			pointer_delta.y / maxf(1.0, asset.size.y))
		var changed := _drag_rect
		if _drag_resize:
			changed.size += normalized_delta
		else:
			changed.position += normalized_delta
		_set_region_frac(_selected_region, changed)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		_selected_region = REGIONS[(REGIONS.find(_selected_region) + 1) % REGIONS.size()]
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_4:
		preview_model = int(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F8:
		_save_profiles()
		get_viewport().set_input_as_handled()
		return
	var direction := Vector2.ZERO
	match event.keycode:
		KEY_LEFT: direction.x = -1.0
		KEY_RIGHT: direction.x = 1.0
		KEY_UP: direction.y = -1.0
		KEY_DOWN: direction.y = 1.0
		_: return
	var changed := _region_frac(_selected_region)
	if event.shift_pressed:
		changed.size += direction * 0.002
	else:
		changed.position += direction * 0.002
	_set_region_frac(_selected_region, changed)
	get_viewport().set_input_as_handled()


func _model_id() -> String:
	return MODEL_IDS[clampi(preview_model, 0, MODEL_IDS.size() - 1)]


func _monitor_texture() -> Texture2D:
	if _texture != null:
		return _texture
	var path := MonitorProfile.asset_path(_model_id())
	if not path.is_empty():
		_texture = load(path) as Texture2D
	return _texture


func _stage_rect() -> Rect2:
	return Rect2(Vector2(36, 64), Vector2(maxf(320.0, size.x - 372.0),
		maxf(260.0, size.y - 116.0)))


func _asset_rect() -> Rect2:
	var stage := _stage_rect()
	var texture := _monitor_texture()
	if texture == null:
		return stage
	var native_size := texture.get_size()
	var factor := minf(stage.size.x / native_size.x, stage.size.y / native_size.y)
	var rendered := native_size * factor
	return Rect2(stage.position + (stage.size - rendered) * 0.5, rendered)


func _working_key(region_id: String) -> String:
	return "%s/%s" % [_model_id(), region_id]


func _region_frac(region_id: String) -> Rect2:
	var key := _working_key(region_id)
	if _working.has(key):
		return _working[key]
	return MonitorProfile.region_frac(_model_id(), region_id)


func _region_screen_rect(region_id: String) -> Rect2:
	var r := _region_frac(region_id)
	var asset := _asset_rect()
	return Rect2(asset.position + r.position * asset.size, r.size * asset.size)


func _set_region_frac(region_id: String, value: Rect2) -> void:
	var min_size := Vector2(0.012, 0.012)
	value.size = value.size.max(min_size)
	value.position.x = clampf(value.position.x, 0.0, 1.0 - value.size.x)
	value.position.y = clampf(value.position.y, 0.0, 1.0 - value.size.y)
	value.size.x = minf(value.size.x, 1.0 - value.position.x)
	value.size.y = minf(value.size.y, 1.0 - value.position.y)
	_working[_working_key(region_id)] = value
	_status = "Geaendert · F8 schreibt alle kalibrierten Flaechen"
	queue_redraw()


func _save_profiles() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		MonitorProfile.DATA_PATH))
	if not parsed is Dictionary:
		_status = "FEHLER · monitors.json konnte nicht gelesen werden"
		queue_redraw()
		return
	var models: Dictionary = parsed.get("models", {})
	for model_key: Variant in models:
		var profile: Dictionary = models[model_key]
		var model_id := str(profile.get("model_id", ""))
		for region_id: String in REGIONS:
			var key := "%s/%s" % [model_id, region_id]
			if not _working.has(key):
				continue
			var r: Rect2 = _working[key]
			var serialized := [r.position.x, r.position.y, r.size.x, r.size.y]
			if region_id == "screen":
				profile["screen_frac"] = serialized
			else:
				var controls: Dictionary = profile.get("controls", {})
				controls[region_id] = serialized
				profile["controls"] = controls
			models[model_key] = profile
	parsed["models"] = models
	var file := FileAccess.open(MonitorProfile.DATA_PATH, FileAccess.WRITE)
	if file == null:
		_status = "FEHLER · monitors.json ist nicht schreibbar"
	else:
		file.store_string(JSON.stringify(parsed, "\t", true) + "\n")
		file.close()
		MonitorProfile.data(true)
		_status = "GESPEICHERT · Raum, CRT-Licht und Hotspots nutzen dieselben Flaechen"
	queue_redraw()


func _draw_label(at: Vector2, value: String, color: Color, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	var y := at.y
	for line: String in value.split("\n"):
		draw_string(font, Vector2(at.x, y), line, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, font_size, color)
		y += font_size + 5.0
