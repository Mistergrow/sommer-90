extends RefCounted
## Treffer, Fortschritt und Zielmarkierung der Haushaltsaktionen.

static func brackets(canvas: Control, centre: Vector2, target_size: Vector2, green: Color) -> void:
	var half := target_size * 0.5
	var corner := 7.0
	var color := Color(green, 0.82)
	for sign_x in [-1.0, 1.0]:
		for sign_y in [-1.0, 1.0]:
			var corner_at := centre + Vector2(half.x * sign_x, half.y * sign_y)
			canvas.draw_line(corner_at, corner_at - Vector2(corner * sign_x, 0), color, 2.0)
			canvas.draw_line(corner_at, corner_at - Vector2(0, corner * sign_y), color, 2.0)


static func progress(canvas: Control, cleared: int, total: int, green: Color, cyan: Color) -> void:
	var progress := float(cleared) / float(total)
	var track := Rect2(28, canvas.size.y - 24, canvas.size.x - 56.0, 9)
	canvas.draw_rect(track, Color(0.01, 0.02, 0.03, 0.92))
	canvas.draw_rect(Rect2(track.position, Vector2(track.size.x * progress, track.size.y)), green)
	canvas.draw_rect(track, cyan.darkened(0.5), false, 1.0)


static func burst(canvas: Control, _flash_at: Vector2, _flash_time: float, _burst_seed: int, burst_color: Color) -> void:
	var life := _flash_time / 0.68
	for particle in 18:
		var angle := float(particle) * TAU / 18.0 + float(_burst_seed % 13) * 0.07
		var radius := (1.0 - life) * (55.0 + float(particle % 4) * 10.0)
		var particle_at := _flash_at + Vector2(cos(angle), sin(angle)) * radius
		canvas.draw_rect(Rect2(particle_at - Vector2(2, 2), Vector2(4, 4)), Color(burst_color, life))
	canvas.draw_arc(_flash_at, (1.0 - life) * 54.0 + 12.0, 0.0, TAU, 36, burst_color, 3.0)
