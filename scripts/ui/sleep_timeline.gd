extends Control
var reduced_motion := false
var _progress := 0.0
var progress: float:
	get:
		return _progress
	set(value):
		_progress = clampf(value, 0.0, 1.0)
		queue_redraw()

func _draw() -> void:
	var width := size.x
	var start := 44.0
	var finish := width - 44.0
	var center_y := size.y * 0.50
	var track := Rect2(start, center_y - 4.0, finish - start, 8.0)
	draw_rect(track, Color(0.015, 0.025, 0.055, 0.96))
	draw_rect(track, Color(Palette.UI_BORDER, 0.55), false, 2.0)
	var fill_width := track.size.x * _progress
	if fill_width > 0.5:
		for segment in 28:
			var x0 := track.position.x + fill_width * float(segment) / 28.0
			var x1 := track.position.x + fill_width * float(segment + 1) / 28.0
			var ratio := float(segment) / 27.0
			var color := Color(Palette.LCD_CYAN).lerp(Color(Palette.LCD_AMBER), ratio)
			draw_rect(Rect2(x0, track.position.y + 1, x1 - x0 + 1.0, track.size.y - 2), Color(color, 0.82))
	for marker in [0.0, 0.33, 0.70, 1.0]:
		var mx := lerpf(start, finish, marker)
		draw_line(Vector2(mx, center_y - 9), Vector2(mx, center_y + 9), Color(Palette.UI_TEXT_DIM, 0.72), 2.0)
	var runner := Vector2(lerpf(start, finish, _progress), center_y)
	if not reduced_motion:
		draw_circle(runner, 12.0, Color(Palette.LCD_CYAN, 0.08))
	draw_circle(runner, 5.0, Color(Palette.LCD_AMBER).lerp(Color(Palette.LCD_GREEN), _progress))
	# Mond links, aufgehende Sonne rechts: ikonische Endpunkte ohne Text.
	var moon := Vector2(18, center_y)
	draw_circle(moon, 11.0, Color(0.88, 0.90, 0.72, 0.92))
	draw_circle(moon + Vector2(5, -2), 10.0, Color(0.025, 0.04, 0.09, 1.0))
	var sun := Vector2(width - 18, center_y)
	draw_circle(sun, 8.0, Color(Palette.LCD_AMBER, 0.95))
	for ray in 8:
		var direction := Vector2.from_angle(float(ray) * TAU / 8.0)
		draw_line(sun + direction * 11.0, sun + direction * 15.0, Color(Palette.LCD_AMBER, 0.72), 2.0)




static func card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.075, 0.96)
	style.border_color = Color(Palette.LCD_CYAN, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 14
	return style
