class_name SommerBasicPreview
extends Control
## AGA-faehige Vorschau des aktuell ausgefuehrten Programms. Der Editor gibt
## ausschliesslich neutrale Zeichenbefehle weiter; Darstellung bleibt getrennt.

var commands: Array[Dictionary] = []
var palette := [
	Color8(5, 9, 18), Color8(245, 245, 230), Color8(255, 164, 42),
	Color8(55, 218, 231), Color8(255, 67, 160), Color8(78, 230, 112),
	Color8(106, 114, 255), Color8(238, 72, 62),
]
var logical_size := Vector2(320, 200)


func show_commands(value: Array) -> void:
	commands.clear()
	for command in value:
		if command is Dictionary:
			commands.append(command.duplicate(true))
			if str(command.get("op", "")) == "screen":
				var args: Array = command.get("args", [])
				if args.size() >= 2:
					logical_size = Vector2(maxf(1.0, float(args[0])), maxf(1.0, float(args[1])))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), palette[0])
	var fit := minf(size.x / logical_size.x, size.y / logical_size.y)
	var origin := (size - logical_size * fit) * 0.5
	for command in commands:
		var operation := str(command.get("op", ""))
		var args: Array = command.get("args", [])
		match operation:
			"cls": draw_rect(Rect2(Vector2.ZERO, size), palette[0])
			"screen":
				pass
			"window":
				if args.size() >= 4:
					var window_rect := Rect2(origin + Vector2(float(args[0]), float(args[1])) * fit,
						Vector2(float(args[2]), float(args[3])) * fit)
					draw_rect(window_rect, Color(0.02, 0.04, 0.08, 0.92))
					draw_rect(window_rect, palette[3], false, maxf(1.0, fit))
			"palette":
				if args.size() >= 2:
					var index := posmod(int(args[0]), palette.size())
					palette[index] = Color.from_string(str(args[1]), palette[index])
			"plot":
				if args.size() >= 2:
					draw_circle(origin + Vector2(float(args[0]), float(args[1])) * fit,
						maxf(1.0, fit), _color(args, 2))
			"line":
				if args.size() >= 4:
					draw_line(origin + Vector2(float(args[0]), float(args[1])) * fit,
						origin + Vector2(float(args[2]), float(args[3])) * fit,
						_color(args, 4), maxf(1.0, fit))
			"box":
				if args.size() >= 4:
					draw_rect(Rect2(origin + Vector2(float(args[0]), float(args[1])) * fit,
						Vector2(float(args[2]), float(args[3])) * fit), _color(args, 4), false,
						maxf(1.0, fit))
			"circle":
				if args.size() >= 3:
					draw_arc(origin + Vector2(float(args[0]), float(args[1])) * fit,
						float(args[2]) * fit, 0.0, TAU, 48, _color(args, 3), maxf(1.0, fit))
			"blit":
				if args.size() >= 7:
					var blit_rect := Rect2(origin + Vector2(float(args[5]), float(args[6])) * fit,
						Vector2(float(args[3]), float(args[4])) * fit)
					draw_rect(blit_rect, Color(palette[6], 0.38))
					draw_rect(blit_rect, palette[3], false, maxf(1.0, fit))
			"sprite", "bob":
				if args.size() >= 3:
					var center := origin + Vector2(float(args[1]), float(args[2])) * fit
					var radius := (6.0 if operation == "sprite" else 9.0) * fit
					draw_circle(center + Vector2(1, 2) * fit, radius, Color(0, 0, 0, 0.45))
					draw_circle(center, radius, palette[4] if operation == "sprite" else palette[2])
					draw_arc(center, radius, 0.0, TAU, 16, palette[1], maxf(1.0, fit))
			"tilemap":
				if args.size() >= 3:
					var tile_size := float(args[3]) if args.size() > 3 else 16.0
					for x in range(int(args[1]) + 1):
						var px := origin.x + float(x) * tile_size * fit
						draw_line(Vector2(px, origin.y), Vector2(px, origin.y + logical_size.y * fit), Color(0.1, 0.45, 0.6, 0.18), 1.0)
					for y in range(int(args[2]) + 1):
						var py := origin.y + float(y) * tile_size * fit
						draw_line(Vector2(origin.x, py), Vector2(origin.x + logical_size.x * fit, py), Color(0.1, 0.45, 0.6, 0.18), 1.0)
	for y in range(0, int(size.y), 3):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.12), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color8(62, 205, 220), false, 1.0)


func _color(args: Array, index: int) -> Color:
	return palette[posmod(int(args[index]), palette.size())] if args.size() > index else palette[1]
