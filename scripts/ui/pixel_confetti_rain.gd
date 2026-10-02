class_name PixelConfettiRain
extends Control
## Kurzer, blockiger Ereignisregen im Stil klassischer 16-Bit-Spiele. Er wird
## nur fuer feierliche/positive Events gestartet; Stromausfall und andere
## negative Ereignisse behalten dadurch ihre passende Stimmung.

const COLORS := [
	Color8(255, 210, 62), Color8(244, 84, 143), Color8(46, 211, 222),
	Color8(121, 231, 80), Color8(255, 135, 38), Color8(167, 113, 232),
	Color8(236, 239, 222),
]

var _pieces: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _running := false
var _time := 0.0
var _spawn_left := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


static func should_celebrate(event: Dictionary) -> bool:
	if event.has("confetti"):
		return bool(event["confetti"])
	var id := str(event.get("id", "")).to_lower()
	var title := str(event.get("title", "")).to_lower()
	if id.begins_with("cal_") or "birthday" in id or "geburtstag" in title:
		return true
	for word in ["neue ", "fund", "compo", "fest", "börsen", "boersen",
		"schnaeppchen", "schnäppchen", "online", "taschengeld", "kuchen"]:
		if word in title:
			return true
	return false


func celebrate(event: Dictionary = {}) -> void:
	if not event.is_empty() and not should_celebrate(event):
		return
	_rng.seed = hash("%s/%d/%d" % [str(event.get("id", "event")),
		TimeManager.day_counter, Time.get_ticks_msec()])
	_pieces.clear()
	_time = 0.0
	_spawn_left = 1.25 if not bool(SettingsManager.value("reduced_motion")) else 0.38
	_running = true
	set_process(true)
	_spawn(42 if not bool(SettingsManager.value("reduced_motion")) else 16, true)
	queue_redraw()


func _process(delta: float) -> void:
	if not _running:
		return
	_time += delta
	_spawn_left = maxf(0.0, _spawn_left - delta)
	if _spawn_left > 0.0:
		_spawn(maxi(1, roundi(delta * 45.0)), false)
	for index in range(_pieces.size() - 1, -1, -1):
		var piece: Dictionary = _pieces[index]
		var velocity: Vector2 = piece["velocity"]
		velocity.y += float(piece["gravity"]) * delta
		velocity.x += sin(_time * float(piece["flutter"]) + float(piece["phase"])) * 12.0 * delta
		piece["velocity"] = velocity
		piece["position"] = Vector2(piece["position"]) + velocity * delta
		piece["angle"] = float(piece["angle"]) + float(piece["spin"]) * delta
		piece["life"] = float(piece["life"]) - delta
		if float(piece["life"]) <= 0.0 or Vector2(piece["position"]).y > size.y + 22.0:
			_pieces.remove_at(index)
	if _spawn_left <= 0.0 and _pieces.is_empty():
		_running = false
		set_process(false)
	queue_redraw()


func _spawn(amount: int, burst: bool) -> void:
	var width := maxf(size.x, 960.0)
	for _index in amount:
		var start_y := _rng.randf_range(-70.0, -4.0) if not burst else _rng.randf_range(-18.0, 18.0)
		_pieces.append({
			"position": Vector2(_rng.randf_range(0.0, width), start_y),
			"velocity": Vector2(_rng.randf_range(-34.0, 34.0), _rng.randf_range(88.0, 170.0)),
			"gravity": _rng.randf_range(58.0, 115.0),
			"flutter": _rng.randf_range(4.0, 9.0),
			"phase": _rng.randf_range(0.0, TAU),
			"angle": _rng.randf_range(0.0, TAU),
			"spin": _rng.randf_range(-7.0, 7.0),
			"size": Vector2(_rng.randi_range(3, 7), _rng.randi_range(2, 5)),
			"color": COLORS[_rng.randi_range(0, COLORS.size() - 1)],
			"streamer": _rng.randf() < 0.22,
			"life": _rng.randf_range(2.4, 4.3),
		})


func _draw() -> void:
	for piece: Dictionary in _pieces:
		var center: Vector2 = piece["position"]
		var extent: Vector2 = Vector2(piece["size"]) * 0.5
		var angle := float(piece["angle"])
		var axis := Vector2(cos(angle), sin(angle))
		var side := Vector2(-axis.y, axis.x)
		var color: Color = piece["color"]
		if bool(piece["streamer"]):
			var tail := PackedVector2Array([center - axis * 8.0,
				center + side * 3.0, center + axis * 8.0 - side * 2.0])
			draw_polyline(tail, Color(color, 0.92), 2.0)
		else:
			var quad := PackedVector2Array([center - axis * extent.x - side * extent.y,
				center + axis * extent.x - side * extent.y,
				center + axis * extent.x + side * extent.y,
				center - axis * extent.x + side * extent.y])
			draw_colored_polygon(quad, color)
			draw_line(quad[0], quad[1], color.lightened(0.34), 1.0)
