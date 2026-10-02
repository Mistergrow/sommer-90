class_name LocationAnalogClock25D
extends Control
## Echte Zeiger fuer ein im Foto freigestelltes analoges Zifferblatt.
## Die Uhr zeigt AUSSCHLIESSLICH die diskrete TimeManager-Spielzeit des HUDs.
## Ein Echtzeit-Sekundenzeiger waere eine zweite Zeitquelle und liess 15:40 wie
## 01:40 wirken. Die komplette Zeigergruppe folgt der Tiefenprojektion des
## Wandpunkts und driftet daher nie vom Zifferblatt.

var host: Control = null
var stage: Control = null
var virtual_center := Vector2.ZERO
var virtual_radius := 40.0


func setup(p_host: Control, p_stage: Control, center: Vector2, radius: float) -> void:
	host = p_host
	stage = p_stage
	virtual_center = center
	virtual_radius = radius
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 2
	_sync_size()
	if host != null and host.has_signal("resized") and not host.resized.is_connected(_sync_size):
		host.resized.connect(_sync_size)
	if not TimeManager.slot_changed.is_connected(_on_slot_changed):
		TimeManager.slot_changed.connect(_on_slot_changed)
	queue_redraw()


func _draw() -> void:
	if host == null or host.size.x <= 1.0:
		return
	var scale_value: float = host.call("view_scale")
	var center: Vector2 = host.call("view_offset") + virtual_center * scale_value
	if stage != null and is_instance_valid(stage):
		center += stage.call("offset_for_point", center)
	var radius := virtual_radius * scale_value
	var angles := hand_angles(TimeManager.clock_minutes(), 0)
	_draw_hand(center, radius, angles.x, 0.46, maxf(1.7, radius * 0.045), 0.08,
		Color(0.055, 0.045, 0.035), true)
	_draw_hand(center, radius, angles.y, 0.69, maxf(1.15, radius * 0.030), 0.10,
		Color(0.045, 0.038, 0.032), true)
	draw_circle(center + Vector2(0.8, 0.9) * scale_value, maxf(1.8, radius * 0.050),
		Color(0.0, 0.0, 0.0, 0.30))
	draw_circle(center, maxf(1.6, radius * 0.045), Color(0.055, 0.045, 0.035))
	draw_circle(center, maxf(0.65, radius * 0.018), Color(0.68, 0.54, 0.30))


func _draw_hand(center: Vector2, radius: float, angle: float, length: float,
		width: float, tail: float, color: Color, shadow: bool) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var start := center - direction * radius * tail
	var finish := center + direction * radius * length
	if shadow:
		var offset := Vector2(1.15, 1.35) * maxf(radius / 42.0, 0.75)
		draw_line(start + offset, finish + offset, Color(0.0, 0.0, 0.0, 0.28), width + 0.7, true)
	draw_line(start, finish, color, width, true)


static func hand_angles(minutes_since_midnight: int, second: int = 0) -> Vector3:
	var minute_value := float(minutes_since_midnight % 60) + float(second) / 60.0
	var hour_value := float(floori(minutes_since_midnight / 60.0) % 12) + minute_value / 60.0
	return Vector3(
		TAU * hour_value / 12.0 - PI * 0.5,
		TAU * minute_value / 60.0 - PI * 0.5,
		TAU * float(second) / 60.0 - PI * 0.5)


func _on_slot_changed(_slot: int) -> void:
	queue_redraw()


func _sync_size() -> void:
	if host != null:
		position = Vector2.ZERO
		size = host.size
