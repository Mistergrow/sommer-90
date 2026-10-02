class_name MinigameDepthRig
extends Node
## Gemeinsamer 2,5D-Qualitaetslayer fuer fotografische Minispielbretter.
## Der komplette interaktive Control wird transformiert; dadurch bleiben Render-
## und Eingabekoordinaten deckungsgleich. Rein visuell, ohne Save-Zustand.

var target: Control
var strength := 1.0
var look := Vector2.ZERO
var _wanted := Vector2.ZERO
var _base_position := Vector2.ZERO
var _captured := false
var _test_lock := false
var _glass: Control
var _last_applied_look := Vector2(INF, INF)
var _last_enabled := false


func configure(control: Control, gain := 1.0) -> void:
	target = control
	strength = gain
	name = "MinigameDepthRig"
	call_deferred("_capture")


func _capture() -> void:
	# Container (insbesondere VBoxContainer) vergeben ihre finale Kindposition erst
	# beim naechsten Layout-Frame. Zu fruehes Capturing konserviert sonst eine
	# temporaere Offscreen-Position und verschiebt Brett samt Input dauerhaft.
	if is_inside_tree():
		await get_tree().process_frame
	if target == null or not is_instance_valid(target):
		return
	_base_position = target.position
	target.pivot_offset = target.size * 0.5
	_captured = true
	_glass = DepthGlass.new()
	_glass.name = "DepthGlass"
	_glass.rig = self
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(_glass)


func _process(delta: float) -> void:
	if not _captured or target == null or not is_instance_valid(target):
		return
	var enabled := bool(SettingsManager.value("location_depth"))
	if not enabled:
		_wanted = Vector2.ZERO
	elif not _test_lock:
		var p := target.get_local_mouse_position()
		if Rect2(Vector2.ZERO, target.size).has_point(p) and target.size.x > 1.0 and target.size.y > 1.0:
			var n := (p / target.size - Vector2(0.5, 0.5)) * 2.0
			_wanted = Vector2(clampf(n.x, -1.0, 1.0), clampf(n.y, -1.0, 1.0))
		else:
			_wanted = Vector2.ZERO
	# Ein langsamer Renderframe darf das physische Brett nicht versetzen. Die
	# Eingabe folgt derselben Control-Transformation, aber sichtbare Spruenge
	# waeren trotzdem unruhig; daher wie im Spielerraum maximal 1/30 s nachholen.
	var motion_delta := minf(maxf(delta, 0.0), 1.0 / 30.0)
	look = look.lerp(_wanted, 1.0 - exp(-motion_delta * 4.6))
	if look.length() < 0.0001:
		look = Vector2.ZERO
	# Transform und Glas nur aktualisieren, wenn sich das Ergebnis sichtbar
	# geaendert hat. Auf ruhendem Mauszeiger erzeugen 19 Minispiele dadurch
	# keine nutzlosen Canvas-Invalidierungen mehr.
	if look.distance_squared_to(_last_applied_look) < 0.00000025 and enabled == _last_enabled:
		return
	_last_applied_look = look
	_last_enabled = enabled
	var amount := strength if enabled else 0.0
	target.position = _base_position + Vector2(look.x * 3.4, look.y * 1.7) * amount
	target.rotation = deg_to_rad(look.x * 0.20 - look.y * 0.08) * amount
	var focus := 1.0 + (0.0035 + maxf(0.0, -look.y) * 0.0015) * amount
	target.scale = Vector2.ONE * focus
	if _glass != null:
		_glass.queue_redraw()


func set_test_look(value: Vector2) -> void:
	_test_lock = true
	look = value
	_wanted = value


func clear_test_look() -> void:
	_test_lock = false


func _exit_tree() -> void:
	if target != null and is_instance_valid(target):
		target.position = _base_position
		target.rotation = 0.0
		target.scale = Vector2.ONE


class DepthGlass:
	extends Control
	var rig: MinigameDepthRig

	func _draw() -> void:
		if rig == null or size.x < 4.0 or size.y < 4.0:
			return
		# Mehrere duenne Innenkanten lesen sich als Glas/Volumen, ohne das Brett
		# mit einer flachen Vignette zuzudecken.
		for i in 6:
			var a := 0.030 * (1.0 - float(i) / 6.0)
			draw_rect(Rect2(Vector2(i, i), size - Vector2(i, i) * 2.0),
				Color(0.01, 0.02, 0.035, a), false, 2.0)
		var lx := clampf(0.5 + rig.look.x * 0.16, 0.18, 0.82)
		var sheen := PackedVector2Array([
			Vector2(size.x * (lx - 0.28), 0), Vector2(size.x * (lx + 0.06), 0),
			Vector2(size.x * (lx - 0.08), size.y * 0.30), Vector2(size.x * (lx - 0.35), size.y * 0.20)])
		draw_colored_polygon(sheen, Color(0.72, 0.90, 1.0, 0.018))
