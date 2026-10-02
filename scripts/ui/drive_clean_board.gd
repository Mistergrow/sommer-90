extends Control

## Interaktives Reinigungsbrett: Vorbereitung, Einlegen, Kopfbewegung und Rendering.
const SAFE_WET_MIN := 0.42
const SAFE_WET_MAX := 0.72
signal prep_changed(values: Array)
signal insert_started
signal disk_inserted
signal clean_changed(cleanliness: float, pressure: float, passes: int, abrasion: float)
signal clean_complete
signal dry_complete

const PREP := 0
const INSERT := 1
const CLEAN := 2
const DRY := 3
const DONE := 4
const DIRT_TRACKS := [0.08, 0.20, 0.34, 0.48, 0.62, 0.76, 0.91]

var board_texture: Texture2D
var stage := PREP
var prep_tool := 1
var prep_deviation := 0.0
var assisted := false
var celebrate := false
var abrasion := 0.0
var passes := 0

var _wetness: Array[float] = [0.18, 0.29, 0.23, 0.34]
var _held := false
var _active_pad := -1
var _disk_position := Vector2.ZERO
var _disk_drag_offset := Vector2.ZERO
var _disk_dragging := false
var _disk_snapping := false
var _snap_from := Vector2.ZERO
var _snap_time := 0.0
var _insert_emitted := false
var _track_t := 0.08
var _last_track_t := 0.08
var _velocity := 0.0
var _pressure := 0.56
var _head_dragging := false
var _pointer_x := 0.0
var _direction := 1.0
var _last_direction := 1.0
var _knowledge := 0.0
var _dirt: Array[float] = []
var _coverage: Array[bool] = []
var _clean_emitted := false
var _dry_left := 0.0
var _dry_emitted := false
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func begin_prep() -> void:
	stage = PREP
	_wetness = [0.18, 0.29, 0.23, 0.34]
	prep_deviation = 0.0
	_emit_prep()
	queue_redraw()


func begin_insert() -> void:
	stage = INSERT
	_disk_position = _disk_start_rect().position
	_disk_dragging = false
	_disk_snapping = false
	_insert_emitted = false
	queue_redraw()


func begin_clean(knowledge: float) -> void:
	stage = CLEAN
	_knowledge = clampf(knowledge, 0.0, 1.0)
	_track_t = 0.08
	_last_track_t = _track_t
	_velocity = 0.0
	_pressure = 0.56
	passes = 0
	abrasion = 0.0
	_dirt.clear()
	for _i in DIRT_TRACKS.size():
		_dirt.append(0.0)
	_coverage.clear()
	for _i in 18:
		_coverage.append(false)
	_clean_emitted = false
	queue_redraw()


func begin_dry() -> void:
	stage = DRY
	_head_dragging = false
	assisted = false
	_dry_left = 3.4
	_dry_emitted = false
	queue_redraw()


func ready_pad_count() -> int:
	var count := 0
	for wet: float in _wetness:
		if wet >= SAFE_WET_MIN and wet <= SAFE_WET_MAX:
			count += 1
	return count


func prep_is_ready() -> bool:
	return ready_pad_count() == _wetness.size()


func safe_pressure_min() -> float:
	return 0.36 - _knowledge * 0.08


func safe_pressure_max() -> float:
	return 0.72 + _knowledge * 0.08


func cleanliness() -> float:
	if _dirt.is_empty():
		return 0.0
	var sum := 0.0
	for progress: float in _dirt:
		sum += progress
	return sum / _dirt.size()


func coverage_ratio() -> float:
	if _coverage.is_empty():
		return 0.0
	var count := 0
	for covered: bool in _coverage:
		if covered:
			count += 1
	return count / float(_coverage.size())


func auto_insert() -> void:
	if stage != INSERT or _disk_snapping:
		return
	_start_disk_snap()


func _process(delta: float) -> void:
	_pulse += delta
	match stage:
		PREP:
			if _held and _active_pad >= 0:
				_adjust_pad(_active_pad, prep_tool * delta * (0.34 if prep_tool > 0 else 0.42))
		INSERT:
			_process_insert(delta)
		CLEAN:
			_process_clean(delta)
		DRY:
			_process_dry(delta)
	queue_redraw()


func _process_insert(delta: float) -> void:
	if not _disk_snapping:
		return
	_snap_time = minf(1.0, _snap_time + delta / 0.58)
	var eased := 1.0 - pow(1.0 - _snap_time, 3.0)
	_disk_position = _snap_from.lerp(_disk_target_rect().position, eased)
	if _snap_time >= 1.0 and not _insert_emitted:
		_insert_emitted = true
		disk_inserted.emit()


func _process_clean(delta: float) -> void:
	# Pointer-Ereignisse aktualisieren _track_t zwischen zwei Frames. Deshalb
	# muss die Geschwindigkeit gegen die zuletzt verarbeitete Position laufen
	# (nicht gegen den bereits aktualisierten Wert dieses Frames).
	var previous_t := _last_track_t
	if assisted:
		_track_t += _direction * delta * 0.27
		_pressure = 0.56
		if _track_t >= 0.96:
			_track_t = 0.96
			_direction = -1.0
		elif _track_t <= 0.04:
			_track_t = 0.04
			_direction = 1.0
	elif not _head_dragging:
		_velocity = move_toward(_velocity, 0.0, delta * 1.8)
		return

	var raw_velocity := absf(_track_t - previous_t) / maxf(delta, 0.001)
	_velocity = lerpf(_velocity, raw_velocity, minf(1.0, delta * 8.0))
	var movement := _track_t - previous_t
	if absf(movement) > 0.0005:
		_direction = signf(movement)
		if _direction != _last_direction and (_track_t < 0.12 or _track_t > 0.88):
			passes += 1
		_last_direction = _direction
	_last_track_t = _track_t

	var coverage_index := clampi(int(_track_t * _coverage.size()), 0, _coverage.size() - 1)
	_coverage[coverage_index] = true
	var pressure_quality := _pressure_quality(_pressure)
	var speed_quality := _speed_quality(_velocity)
	var quality := pressure_quality * speed_quality
	if _velocity < 0.035 and _head_dragging:
		abrasion = minf(1.5, abrasion + delta * 0.045 * maxf(0.3, _pressure))
	if _pressure > safe_pressure_max():
		abrasion = minf(1.5, abrasion + delta * (_pressure - safe_pressure_max()) * 0.22)
	for i in _dirt.size():
		var distance := absf(_track_t - float(DIRT_TRACKS[i]))
		if distance < 0.105 and quality > 0.02:
			var contact := 1.0 - distance / 0.105
			_dirt[i] = minf(1.0, _dirt[i] + delta * contact * quality * 0.95)
	clean_changed.emit(cleanliness(), _pressure, passes, abrasion)
	if cleanliness() >= 0.985 and coverage_ratio() >= 0.83 and not _clean_emitted:
		_clean_emitted = true
		clean_complete.emit()


func _process_dry(delta: float) -> void:
	_dry_left = maxf(0.0, _dry_left - delta)
	if _dry_left <= 0.0 and not _dry_emitted:
		_dry_emitted = true
		dry_complete.emit()


func _pressure_quality(value: float) -> float:
	if value < safe_pressure_min():
		return clampf(value / maxf(0.01, safe_pressure_min()), 0.12, 1.0)
	if value <= safe_pressure_max():
		return 1.0
	return clampf(1.0 - (value - safe_pressure_max()) * 2.2, 0.12, 1.0)


func _speed_quality(value: float) -> float:
	if value < 0.04:
		return 0.0
	if value < 0.12:
		return lerpf(0.25, 1.0, (value - 0.04) / 0.08)
	if value <= 0.62:
		return 1.0
	return clampf(1.0 - (value - 0.62) * 0.9, 0.18, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_x = event.position.x
			match stage:
				PREP:
					_active_pad = _pad_at(event.position)
					_held = _active_pad >= 0
					if _held:
						_adjust_pad(_active_pad, prep_tool * 0.045)
				INSERT:
					var disk_rect := Rect2(_disk_position, _disk_size())
					if disk_rect.has_point(event.position) and not _disk_snapping:
						_disk_dragging = true
						_disk_drag_offset = event.position - _disk_position
				CLEAN:
					if _head_hit_rect().has_point(event.position):
						_head_dragging = true
						_set_head_from_pointer(event.position)
		else:
			_held = false
			_active_pad = -1
			if stage == INSERT and _disk_dragging:
				_disk_dragging = false
				if _disk_target_rect().grow(48).has_point(event.position):
					_start_disk_snap()
			if stage == CLEAN:
				_head_dragging = false
	elif event is InputEventMouseMotion:
		_pointer_x = event.position.x
		if stage == PREP and _held:
			var new_pad := _pad_at(event.position)
			if new_pad >= 0:
				_active_pad = new_pad
		elif stage == INSERT and _disk_dragging:
			_disk_position = event.position - _disk_drag_offset
			var bounds := Rect2(Vector2(8, 8), size - Vector2(16, 16) - _disk_size())
			_disk_position.x = clampf(_disk_position.x, bounds.position.x, bounds.end.x)
			_disk_position.y = clampf(_disk_position.y, bounds.position.y, bounds.end.y)
		elif stage == CLEAN and _head_dragging:
			_set_head_from_pointer(event.position)
	queue_redraw()


func _adjust_pad(index: int, amount: float) -> void:
	if index < 0 or index >= _wetness.size():
		return
	_wetness[index] = clampf(_wetness[index] + amount, 0.0, 1.0)
	_emit_prep()


func _emit_prep() -> void:
	prep_changed.emit(_wetness.duplicate())


func _start_disk_snap() -> void:
	if _disk_snapping:
		return
	_disk_dragging = false
	_disk_snapping = true
	_snap_from = _disk_position
	_snap_time = 0.0
	insert_started.emit()


func _set_head_from_pointer(pointer: Vector2) -> void:
	var track := _track_rect()
	_track_t = clampf(inverse_lerp(track.position.y, track.end.y, pointer.y), 0.0, 1.0)
	var offset := (pointer.x - track.get_center().x) / 105.0
	_pressure = clampf(0.56 + offset, 0.0, 1.0)


func _art_rect() -> Rect2:
	if board_texture == null:
		return Rect2(Vector2.ZERO, size)
	var ratio := board_texture.get_width() / float(board_texture.get_height())
	var draw_size := Vector2(size.x, size.x / ratio)
	if draw_size.y > size.y:
		draw_size = Vector2(size.y * ratio, size.y)
	return Rect2((size - draw_size) * 0.5, draw_size)


func _disk_size() -> Vector2:
	var ar := _art_rect()
	return Vector2(ar.size.y * 0.265, ar.size.y * 0.235)


func _disk_start_rect() -> Rect2:
	var ar := _art_rect()
	return Rect2(ar.position + Vector2(ar.size.x * 0.055, ar.size.y * 0.675), _disk_size())


func _disk_target_rect() -> Rect2:
	var ar := _art_rect()
	var disk_size := _disk_size()
	return Rect2(Vector2(ar.get_center().x - disk_size.x * 0.5, ar.position.y + ar.size.y * 0.745), disk_size)


func _prep_disk_rect() -> Rect2:
	var ar := _art_rect()
	var prep_size := Vector2(ar.size.y * 0.39, ar.size.y * 0.35)
	return Rect2(ar.position + Vector2(ar.size.x * 0.075, ar.size.y * 0.54), prep_size)


func _pad_rect(index: int) -> Rect2:
	var disk := _prep_disk_rect()
	var field := Rect2(disk.position + Vector2(disk.size.x * 0.17, disk.size.y * 0.33),
		Vector2(disk.size.x * 0.66, disk.size.y * 0.48))
	var col := index % 2
	var row := int(index / 2.0)
	var gap := 5.0
	var pad_size := Vector2((field.size.x - gap) * 0.5, (field.size.y - gap) * 0.5)
	return Rect2(field.position + Vector2(col * (pad_size.x + gap), row * (pad_size.y + gap)), pad_size)


func _pad_at(point: Vector2) -> int:
	for i in _wetness.size():
		if _pad_rect(i).grow(5).has_point(point):
			return i
	return -1


func _track_rect() -> Rect2:
	var ar := _art_rect()
	return Rect2(Vector2(ar.get_center().x - ar.size.x * 0.018, ar.position.y + ar.size.y * 0.14),
		Vector2(ar.size.x * 0.036, ar.size.y * 0.43))


func _head_position() -> Vector2:
	var track := _track_rect()
	return Vector2(track.get_center().x, lerpf(track.position.y, track.end.y, _track_t))


func _head_hit_rect() -> Rect2:
	return Rect2(_head_position() - Vector2(72, 31), Vector2(144, 62))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(5, 7, 10))
	var ar := _art_rect()
	if board_texture != null:
		draw_texture_rect(board_texture, ar, false)
	match stage:
		PREP:
			_draw_prep(ar)
		INSERT:
			_draw_insert(ar)
		CLEAN:
			_draw_clean(ar)
		DRY:
			_draw_dry(ar)
		DONE:
			pass
	if celebrate:
		var glow := 0.52 + sin(_pulse * 7.0) * 0.22
		draw_rect(ar.grow(-5), Color(1.0, 0.72, 0.20, glow), false, 5.0)


func _draw_prep(ar: Rect2) -> void:
	draw_rect(ar, Color(0.01, 0.02, 0.03, 0.46))
	var mat := Rect2(ar.position + Vector2(ar.size.x * 0.035, ar.size.y * 0.48),
		Vector2(ar.size.x * 0.48, ar.size.y * 0.47))
	draw_rect(mat, Color(0.035, 0.055, 0.065, 0.92))
	draw_rect(mat, Color8(74, 102, 112), false, 2.0)
	_draw_cleaning_disk(_prep_disk_rect(), 1.0)
	for i in _wetness.size():
		var pad := _pad_rect(i)
		var wet := _wetness[i]
		var color := Color8(105, 143, 125)
		if wet < SAFE_WET_MIN:
			color = Color8(184, 176, 142)
		elif wet > SAFE_WET_MAX:
			color = Color8(64, 137, 168)
		draw_rect(pad, color)
		draw_rect(pad, Color8(24, 42, 46), false, 2.0)
		var fill := Rect2(pad.position + Vector2(4, pad.size.y - 8), Vector2((pad.size.x - 8) * wet, 4))
		draw_rect(fill, Palette.LCD_GREEN if wet >= SAFE_WET_MIN and wet <= SAFE_WET_MAX else Palette.LCD_CYAN)
		for grain in 5:
			var px := pad.position.x + 7 + fmod(float(grain * 17 + i * 9), maxf(8.0, pad.size.x - 14))
			var py := pad.position.y + 6 + fmod(float(grain * 11 + i * 13), maxf(8.0, pad.size.y - 15))
			draw_rect(Rect2(Vector2(px, py), Vector2(3, 2)), Color(0.18, 0.25, 0.23, 0.34))
	var tool_center := ar.position + Vector2(ar.size.x * 0.76, ar.size.y * 0.70)
	if prep_tool > 0:
		draw_circle(tool_center, 28, Color8(42, 112, 142))
		draw_circle(tool_center, 28, Palette.LCD_CYAN, false, 3)
		draw_circle(tool_center - Vector2(8, 9), 7, Color(0.65, 0.9, 1.0, 0.65))
	else:
		draw_rect(Rect2(tool_center - Vector2(31, 22), Vector2(62, 44)), Color8(210, 198, 166))
		draw_rect(Rect2(tool_center - Vector2(31, 22), Vector2(62, 44)), Palette.LCD_AMBER, false, 3)


func _draw_insert(_ar: Rect2) -> void:
	var slot := _disk_target_rect()
	var pulse := 0.58 + sin(_pulse * 5.5) * 0.22
	draw_rect(slot.grow(12), Color(0.25, 0.82, 1.0, pulse), false, 4.0)
	draw_line(Vector2(slot.get_center().x, slot.end.y + 28), Vector2(slot.get_center().x, slot.end.y + 5),
		Color(0.35, 0.85, 1.0, pulse), 4.0)
	_draw_cleaning_disk(Rect2(_disk_position, _disk_size()), 0.25 if _disk_snapping and _snap_time > 0.72 else 1.0)


func _draw_clean(_ar: Rect2) -> void:
	var track := _track_rect()
	draw_rect(track.grow(8), Color(0.03, 0.07, 0.08, 0.60))
	draw_line(Vector2(track.get_center().x, track.position.y), Vector2(track.get_center().x, track.end.y),
		Color8(92, 134, 146), 3.0)
	for i in _dirt.size():
		var y := lerpf(track.position.y, track.end.y, float(DIRT_TRACKS[i]))
		var side := -1.0 if i % 2 == 0 else 1.0
		var center := Vector2(track.get_center().x + side * (14.0 + (i % 3) * 4.0), y)
		var remaining := 1.0 - _dirt[i]
		if remaining > 0.015:
			# Kleine, kantige Oxid-/Staubablagerung statt glatter Marker-Kugel.
			var radius := 4.0 + remaining * 4.0
			var grime := PackedVector2Array([
				center + Vector2(-radius, -radius * 0.20),
				center + Vector2(-radius * 0.42, -radius),
				center + Vector2(radius * 0.55, -radius * 0.72),
				center + Vector2(radius, radius * 0.18),
				center + Vector2(radius * 0.32, radius),
				center + Vector2(-radius * 0.72, radius * 0.58),
			])
			draw_colored_polygon(grime, Color(0.43, 0.24, 0.09, 0.52 + remaining * 0.42))
			draw_rect(Rect2(center + Vector2(-2, -1), Vector2(5, 3)), Color(0.12, 0.075, 0.035, remaining))
			draw_rect(Rect2(center + Vector2(side * 5, -5), Vector2(3, 3)), Color(0.67, 0.40, 0.14, remaining))
	var head := _head_position()
	var pressure_color := Palette.LCD_GREEN
	if _pressure < safe_pressure_min():
		pressure_color = Palette.LCD_CYAN
	elif _pressure > safe_pressure_max():
		pressure_color = Palette.LCD_AMBER
	var handle := Rect2(head - Vector2(42, 17), Vector2(84, 34))
	draw_rect(handle, Color(0.07, 0.08, 0.08, 0.88))
	draw_rect(handle, Color8(74, 78, 76), false, 3.0)
	draw_rect(handle.grow(-3), pressure_color, false, 2.0)
	draw_line(head - Vector2(29, 0), head + Vector2(29, 0), Color8(178, 178, 162), 2.0)
	draw_circle(head, 7.0 + _pressure * 3.0, pressure_color, false, 2.0)
	draw_circle(handle.position + Vector2(8, 8), 2.0, Color8(184, 160, 104))
	draw_circle(handle.end - Vector2(8, 8), 2.0, Color8(184, 160, 104))
	var coverage_y := track.end.y + 17
	var segment_w := 7.0
	var coverage_x := track.get_center().x - _coverage.size() * segment_w * 0.5
	for i in _coverage.size():
		draw_rect(Rect2(Vector2(coverage_x + i * segment_w, coverage_y), Vector2(5, 6)),
			Palette.LCD_GREEN if _coverage[i] else Color8(55, 58, 57))


func _draw_dry(ar: Rect2) -> void:
	draw_rect(ar, Color(0.01, 0.02, 0.025, 0.48))
	var center := ar.get_center()
	var progress := 1.0 - _dry_left / 3.4
	for ring in 4:
		var radius := 35.0 + ring * 25.0 + fmod(_pulse * 18.0, 25.0)
		var alpha := clampf(0.34 - ring * 0.055 - progress * 0.08, 0.05, 0.34)
		draw_arc(center, radius, PI * 1.08, PI * 1.92, 32, Color(0.45, 0.85, 0.92, alpha), 3.0)
	var panel := Rect2(center - Vector2(150, 46), Vector2(300, 92))
	draw_rect(panel, Color(0.025, 0.035, 0.04, 0.93))
	draw_rect(panel, Palette.LCD_AMBER, false, 3.0)
	var font := get_theme_default_font()
	draw_string(font, panel.position + Vector2(10, 30), "VERDUNSTEN LASSEN", HORIZONTAL_ALIGNMENT_CENTER,
		panel.size.x - 20, 18, Palette.LCD_AMBER)
	draw_string(font, panel.position + Vector2(10, 62), "%d%%" % int(round(progress * 100.0)),
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 20, 15, Palette.LCD_GREEN)


func _draw_cleaning_disk(rect: Rect2, alpha: float) -> void:
	var shadow := Rect2(rect.position + Vector2(5, 7), rect.size)
	draw_rect(shadow, Color(0, 0, 0, 0.62 * alpha))
	var body := Color(0.19, 0.39, 0.47, alpha)
	draw_rect(rect, body)
	draw_rect(rect, Color(0.04, 0.10, 0.13, alpha), false, 3.0)
	# Harte Pixel-Bevels übernehmen die grün-blaue Silhouette des HUD-Items.
	draw_line(rect.position + Vector2(4, 4), Vector2(rect.end.x - 5, rect.position.y + 4),
		Color(0.39, 0.64, 0.68, alpha), 3.0)
	draw_line(rect.position + Vector2(4, 4), Vector2(rect.position.x + 4, rect.end.y - 5),
		Color(0.31, 0.57, 0.60, alpha), 3.0)
	draw_line(Vector2(rect.position.x + 5, rect.end.y - 4), rect.end - Vector2(5, 4),
		Color(0.035, 0.09, 0.11, alpha), 4.0)
	var notch := Rect2(rect.position + Vector2(rect.size.x * 0.78, 0), Vector2(rect.size.x * 0.13, rect.size.y * 0.10))
	draw_rect(notch, Color(0.025, 0.04, 0.045, alpha))
	var shutter := Rect2(rect.position + Vector2(rect.size.x * 0.22, rect.size.y * 0.04),
		Vector2(rect.size.x * 0.56, rect.size.y * 0.22))
	draw_rect(shutter, Color(0.63, 0.69, 0.66, alpha))
	draw_rect(shutter, Color(0.12, 0.18, 0.18, alpha), false, 2.0)
	for stripe in 4:
		var sx := shutter.position.x + 6 + stripe * maxf(5.0, (shutter.size.x - 12) / 4.0)
		draw_line(Vector2(sx, shutter.position.y + 4), Vector2(sx, shutter.end.y - 4),
			Color(0.82, 0.84, 0.78, 0.36 * alpha), 1.0)
	var window := Rect2(rect.position + Vector2(rect.size.x * 0.14, rect.size.y * 0.33),
		Vector2(rect.size.x * 0.72, rect.size.y * 0.49))
	draw_rect(window, Color(0.35, 0.59, 0.45, alpha))
	draw_rect(window, Color(0.06, 0.16, 0.15, alpha), false, 2.0)
	for fiber in 8:
		var fx := window.position.x + 5 + fmod(float(fiber * 19), maxf(7.0, window.size.x - 10))
		var fy := window.position.y + 5 + fmod(float(fiber * 13), maxf(7.0, window.size.y - 10))
		draw_rect(Rect2(Vector2(fx, fy), Vector2(3, 2)), Color(0.70, 0.76, 0.61, 0.34 * alpha))
	var hub := rect.position + Vector2(rect.size.x * 0.50, rect.size.y * 0.57)
	draw_circle(hub, rect.size.y * 0.075, Color(0.72, 0.72, 0.64, alpha))
	draw_circle(hub, rect.size.y * 0.035, Color(0.08, 0.12, 0.12, alpha))

