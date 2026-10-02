class_name SpaceLemmingArt
extends RefCounted
## Einheitliche 16-Bit-Art-Schicht. Der Generator liefert nur logische Zellen;
## hier werden daraus automatisch Stege, Kanten, Schleusen und Sprites gebaut.

const Generator := preload("res://scripts/games/space_lemming_generator.gd")
const CREW_WALK := preload("res://assets/ui/games/space_lemming/crew_walk_runtime_atlas_v02.png")
const CREW_ACTIONS := preload("res://assets/ui/games/space_lemming/crew_actions_runtime_atlas_v02.png")
const AIRLOCKS := preload("res://assets/ui/games/space_lemming/airlock_runtime_atlas_v01.png")
const CATWALK := preload("res://assets/ui/games/space_lemming/catwalk_material_v01.png")

const INK := Color8(5, 10, 17)
const DEEP := Color8(12, 23, 33)
const STEEL := Color8(39, 55, 70)
const EDGE := Color8(105, 66, 38)
const RUST := Color8(184, 85, 32)
const CREAM := Color8(237, 201, 145)
const AMBER := Color8(246, 166, 51)
const RED := Color8(224, 71, 78)
const CYAN := Color8(63, 213, 224)
const BLUE := Color8(52, 112, 191)
const GREEN := Color8(99, 205, 120)
const WHITE := Color8(237, 239, 218)

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func draw_station_backdrop(canvas: CanvasItem, sector: String, time: float,
		aga := false) -> void:
	# Kein skaliertes HD-Gemaelde im laufenden Level: Die gesamte Kulisse wird in
	# 384x216-Lowres aus festen ECS-/AGA-Farben aufgebaut. Drei Sektoren besitzen
	# eigene Silhouetten, teilen aber dieselbe industrielle Materialsprache.
	var deep := Color8(3, 8, 16)
	var upper := Color8(7, 19, 31)
	var lower := Color8(13, 31, 40)
	match sector.to_upper():
		"NACHTSEITE":
			upper = Color8(13, 14, 34)
			lower = Color8(27, 24, 48)
		"NULLPUNKT":
			upper = Color8(20, 9, 28)
			lower = Color8(40, 18, 39)
	canvas.draw_rect(Rect2(0, 0, 384, 216), deep)
	var band_step := 1 if aga else 3
	for y in range(22, 202, band_step):
		var ratio := float(y - 22) / 180.0
		var color := upper.lerp(lower, ratio)
		if not aga:
			color = Color(roundf(color.r * 15.0) / 15.0,
				roundf(color.g * 15.0) / 15.0,
				roundf(color.b * 15.0) / 15.0)
		canvas.draw_rect(Rect2(0, y, 384, band_step), color)
	_draw_parallax_space(canvas, sector, time, aga)
	_draw_station_silhouette(canvas, sector, time, aga)
	# Vorderer Deckrahmen verbindet Laufsteg und Kulisse optisch.
	canvas.draw_rect(Rect2(0, 190, 384, 12), Color8(7, 15, 21))
	canvas.draw_rect(Rect2(0, 190, 384, 2), Color8(67, 90, 96))
	canvas.draw_rect(Rect2(0, 194, 384, 1), EDGE)
	for x in range(5, 384, 16):
		canvas.draw_rect(Rect2(x, 197, 7, 2), Color8(24, 39, 47))
		canvas.draw_rect(Rect2(x + 1, 197, 1, 1), RUST)


static func _draw_parallax_space(canvas: CanvasItem, sector: String, time: float,
		aga: bool) -> void:
	var drift := time * (2.3 if sector.to_upper() == "NULLPUNKT" else 0.65)
	var layers := 3 if aga else 2
	for layer in layers:
		var count := 32 + layer * 14
		var speed := 0.16 + layer * 0.21
		for i in count:
			var noise_key := i * 41 + layer * 97 + sector.length() * 19
			var x := fposmod(float((noise_key * 17) % 389) - drift * speed, 392.0) - 4.0
			var y := 27.0 + float((noise_key * 29) % 147)
			var size := 1.0 if layer < 2 else 2.0
			var color := Color8(95, 124, 132) if layer == 0 else (
				Color8(171, 191, 177) if layer == 1 else Color8(103, 205, 216))
			canvas.draw_rect(Rect2(roundf(x), roundf(y), size, 1), color)
	if sector.to_upper() == "NULLPUNKT":
		var pulse := posmod(floori(time * 10.0), 9)
		for ray in 7:
			var y := 47.0 + ray * 18.0 + float(pulse % 3)
			canvas.draw_line(Vector2(0, y), Vector2(384, y - 7),
				Color(0.58, 0.22, 0.68, 0.09 if aga else 0.055), 1.0)


static func _draw_station_silhouette(canvas: CanvasItem, sector: String, time: float,
		aga: bool) -> void:
	var phase := floori(time * 8.0)
	match sector.to_upper():
		"NACHTSEITE":
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(0, 151), Vector2(39, 140), Vector2(81, 144),
				Vector2(118, 126), Vector2(171, 137), Vector2(218, 123),
				Vector2(269, 141), Vector2(326, 129), Vector2(384, 145),
				Vector2(384, 190), Vector2(0, 190)]), Color8(7, 13, 23))
			for x in range(18, 376, 27):
				var live := posmod(floori(float(x) / 27.0)
					+ floori(float(phase) / 5.0), 5) != 0
				canvas.draw_rect(Rect2(x, 151 + posmod(x, 17), 4, 2),
					Color8(52, 182, 194) if live else Color8(24, 49, 57))
		"NULLPUNKT":
			canvas.draw_rect(Rect2(0, 116, 384, 74), Color8(9, 11, 20))
			for x in range(-12, 396, 34):
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(x, 190), Vector2(x + 8, 128), Vector2(x + 23, 128),
					Vector2(x + 34, 190)]), Color8(19, 23, 32))
				canvas.draw_line(Vector2(x + 11, 132), Vector2(x + 25, 183),
					Color8(57, 42, 66), 1.0)
			var core := Vector2(192, 119)
			var ring_color := Color8(174, 74, 173) if phase % 4 < 2 else Color8(89, 51, 113)
			_pixel_ring(canvas, core, 18, ring_color)
			if aga:
				_pixel_ring(canvas, core, 24, Color8(48, 126, 152))
		_:
			canvas.draw_rect(Rect2(0, 141, 384, 49), Color8(8, 17, 24))
			for x in range(-8, 392, 32):
				var height := 17 + posmod(x + 40, 29)
				canvas.draw_rect(Rect2(x, 141 - height, 24, height + 49),
					Color8(13, 27, 35))
				canvas.draw_rect(Rect2(x + 3, 145 - height, 2, height + 31),
					Color8(37, 57, 62))
				canvas.draw_rect(Rect2(x + 16, 149 - height, 4, 2),
					CYAN if posmod(floori(float(x) / 8.0)
						+ floori(float(phase) / 6.0), 4) == 0 else Color8(28, 67, 72))
			canvas.draw_line(Vector2(0, 137), Vector2(384, 137), Color8(40, 62, 68), 1.0)


static func _pixel_ring(canvas: CanvasItem, center: Vector2, radius: int, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-radius + 4, -radius), center + Vector2(radius - 4, -radius),
		center + Vector2(radius, -radius + 4), center + Vector2(radius, radius - 4),
		center + Vector2(radius - 4, radius), center + Vector2(-radius + 4, radius),
		center + Vector2(-radius, radius - 4), center + Vector2(-radius, -radius + 4),
		center + Vector2(-radius + 4, -radius),
	])
	canvas.draw_polyline(points, color, 2.0, false)


static func draw_board(canvas: CanvasItem, model, origin: Vector2, cell_size: float,
		hover: Vector2i, cursor: Vector2i, selected_tool: int, hint: bool,
		time: float, visual_ticks: float, particles: Array[Dictionary]) -> void:
	var level: Dictionary = model.level
	# Tiefe zuerst: der Steg schwebt sichtbar knapp ueber dem Stationsdeck.
	for y in Generator.HEIGHT:
		for x in Generator.WIDTH:
			var cell := Vector2i(x, y)
			var tile := Generator.tile_at(level, cell)
			if tile == Generator.Tile.VOID:
				continue
			var center := _center(origin, cell_size, cell) + Vector2(1.2, 1.7)
			_draw_shape(canvas, center, _mask(level, cell), Color(0, 0, 0, 0.52), false)

	for y in Generator.HEIGHT:
		for x in Generator.WIDTH:
			var cell := Vector2i(x, y)
			var tile := Generator.tile_at(level, cell)
			if tile == Generator.Tile.VOID:
				continue
			var center := _center(origin, cell_size, cell)
			var mask := _mask(level, cell)
			var beacon := int(model.beacons.get(Generator.key(cell), -1))
			if tile == Generator.Tile.GAP and beacon != Generator.Tool.BRIDGE:
				_draw_broken_gap(canvas, center, mask, time)
			else:
				_draw_shape(canvas, center, mask, WHITE, true)
				_draw_tile_detail(canvas, tile, center, cell, beacon, time, model)
			if hint and (level.get("solution", {}) as Dictionary).has(Generator.key(cell)):
				var pulse := 0.35 + (sin(time * 5.0 + x) * 0.5 + 0.5) * 0.35
				canvas.draw_circle(center, 5.2, Color(1.0, 0.72, 0.15, pulse), false, 1.0)

	for raw_key: Variant in model.beacons:
		var parts := str(raw_key).split(":")
		if parts.size() != 2:
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		var tool := int(model.beacons[raw_key])
		if tool != Generator.Tool.BRIDGE:
			_draw_hologram(canvas, _center(origin, cell_size, cell), tool, time, 1.0)

	for member: Dictionary in model.crew:
		var status := str(member.get("status", ""))
		var resolved_age := visual_ticks - float(member.get("resolved_tick", visual_ticks))
		if status == "active" or resolved_age < 24.0:
			_draw_crew(canvas, member, model, visual_ticks, origin, cell_size)
	_draw_particles(canvas, particles)

	var focus := hover if hover.x >= 0 else cursor
	if focus.x >= 0:
		_draw_focus(canvas, _center(origin, cell_size, focus), selected_tool, time)
	# Kein rechteckiger Debugrahmen mehr: nur vier dezente Deck-Markierungen.
	var bounds := Rect2(origin, Vector2(Generator.WIDTH, Generator.HEIGHT) * cell_size)
	for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		var sx := 1.0 if corner.x == bounds.position.x else -1.0
		var sy := 1.0 if corner.y == bounds.position.y else -1.0
		canvas.draw_line(corner, corner + Vector2(sx * 9, 0), Color(0.3, 0.62, 0.7, 0.42), 1.0)
		canvas.draw_line(corner, corner + Vector2(0, sy * 9), Color(0.3, 0.62, 0.7, 0.42), 1.0)


static func draw_command_console(canvas: CanvasItem, rect: Rect2, time: float) -> void:
	# Eigenes Stationspult statt sechs generischer UI-Kaesten.
	canvas.draw_rect(rect, Color8(5, 13, 21, 245))
	canvas.draw_texture_rect(CATWALK, Rect2(rect.position, Vector2(rect.size.x, 4)), true,
		Color(0.38, 0.52, 0.58, 0.72))
	canvas.draw_line(rect.position + Vector2(0, 4), Vector2(rect.end.x, rect.position.y + 4), RUST, 1.0)
	canvas.draw_line(rect.position + Vector2(0, 5), Vector2(rect.end.x, rect.position.y + 5), EDGE, 1.0)
	canvas.draw_line(rect.position, Vector2(rect.position.x, rect.end.y), Color(0.25, 0.57, 0.65, 0.44), 1.0)
	canvas.draw_line(Vector2(rect.end.x - 1, rect.position.y), rect.end - Vector2(1, 0), Color(0, 0, 0, 0.72), 1.0)
	for y: float in [rect.position.y + 8.0, rect.end.y - 5.0]:
		canvas.draw_rect(Rect2(Vector2(rect.position.x + 3, y), Vector2.ONE), CREAM)
		canvas.draw_rect(Rect2(Vector2(rect.end.x - 4, y), Vector2.ONE), EDGE)
	var sweep := rect.position.y + 9.0 + fmod(time * 9.0, maxf(1.0, rect.size.y - 18.0))
	canvas.draw_line(Vector2(rect.position.x + 2, sweep), Vector2(rect.end.x - 2, sweep),
		Color(0.15, 0.78, 0.88, 0.055), 1.0)


static func draw_command_slot(canvas: CanvasItem, rect: Rect2, tool: int,
		selected: bool, time: float) -> void:
	var tint := Color8(17, 38, 49, 235) if selected else Color8(10, 24, 34, 225)
	canvas.draw_rect(rect, tint)
	canvas.draw_line(rect.position + Vector2(0, rect.size.y - 1), rect.end - Vector2(0, 1),
		RUST if selected else Color(0.22, 0.35, 0.42, 0.72), 1.0)
	if selected:
		canvas.draw_line(rect.position, rect.position + Vector2(5, 0), AMBER, 1.0)
		canvas.draw_line(rect.position, rect.position + Vector2(0, 5), AMBER, 1.0)
		canvas.draw_line(rect.end - Vector2(5, 1), rect.end - Vector2(0, 1), AMBER, 1.0)
		canvas.draw_line(rect.end - Vector2(1, 5), rect.end - Vector2(1, 0), AMBER, 1.0)
	var center := Vector2(rect.position.x + 9, rect.get_center().y)
	var pulse := 0.82 + sin(time * 6.0 + tool) * 0.12 if selected else 0.62
	_draw_tool_glyph(canvas, center, tool, pulse)


static func draw_intro_actor(canvas: CanvasItem, center: Vector2, frame: int,
		scale: float = 1.0, modulate: Color = Color.WHITE) -> void:
	var size := Vector2(12, 16) * scale
	canvas.draw_texture_rect_region(CREW_ACTIONS, Rect2(center - size * 0.5, size),
		Rect2(clampi(frame, 0, 15) * 24, 0, 24, 28), modulate)


static func _draw_tool_glyph(canvas: CanvasItem, center: Vector2, tool: int, alpha: float) -> void:
	var color := Color(CYAN.r, CYAN.g, CYAN.b, alpha)
	if tool <= Generator.Tool.LEFT:
		var direction := Vector2(DIRS[tool])
		var normal := Vector2(-direction.y, direction.x)
		canvas.draw_colored_polygon(PackedVector2Array([
			center + direction * 3.5, center - direction * 1.5 + normal * 2.0,
			center - direction * 1.5 - normal * 2.0]), color)
		canvas.draw_rect(Rect2(center - direction * 3.5 - Vector2.ONE * 0.5, Vector2.ONE), WHITE)
	elif tool == Generator.Tool.BRIDGE:
		canvas.draw_line(center + Vector2(-4, -2), center + Vector2(4, -2), color, 1.0)
		canvas.draw_line(center + Vector2(-4, 2), center + Vector2(4, 2), color, 1.0)
		for x in [-3.0, 0.0, 3.0]:
			canvas.draw_line(center + Vector2(x, -2), center + Vector2(x, 2), CREAM, 1.0)
	else:
		canvas.draw_arc(center, 4.0, PI, TAU, 8, color, 1.0)
		canvas.draw_line(center + Vector2(-4, 0), center + Vector2(4, 0), color, 1.0)


static func _draw_shape(canvas: CanvasItem, center: Vector2, mask: int,
		modulate: Color, textured: bool) -> void:
	var core := Rect2(center - Vector2(5, 4), Vector2(10, 8))
	_draw_plate(canvas, core, modulate, textured)
	if (mask & 1) != 0:
		_draw_plate(canvas, Rect2(center + Vector2(-4, -7), Vector2(8, 4)), modulate, textured)
	if (mask & 2) != 0:
		_draw_plate(canvas, Rect2(center + Vector2(4, -3), Vector2(4, 6)), modulate, textured)
	if (mask & 4) != 0:
		_draw_plate(canvas, Rect2(center + Vector2(-4, 3), Vector2(8, 4)), modulate, textured)
	if (mask & 8) != 0:
		_draw_plate(canvas, Rect2(center + Vector2(-7, -3), Vector2(4, 6)), modulate, textured)
	if not textured:
		return
	# Rostfarbene Sicherheitskante nur dort, wo kein Nachbarsteg anschliesst.
	if (mask & 1) == 0:
		canvas.draw_line(center + Vector2(-5, -4), center + Vector2(5, -4), RUST, 1.0)
	if (mask & 2) == 0:
		canvas.draw_line(center + Vector2(5, -4), center + Vector2(5, 4), EDGE, 1.0)
	if (mask & 4) == 0:
		canvas.draw_line(center + Vector2(-5, 4), center + Vector2(5, 4), EDGE, 1.0)
	if (mask & 8) == 0:
		canvas.draw_line(center + Vector2(-5, -4), center + Vector2(-5, 4), RUST, 1.0)
	canvas.draw_rect(Rect2(center + Vector2(-3, -1), Vector2(1, 1)), CREAM)
	canvas.draw_rect(Rect2(center + Vector2(2, 1), Vector2(1, 1)), Color(0.15, 0.78, 0.84, 0.72))


static func _draw_plate(canvas: CanvasItem, rect: Rect2, modulate: Color, textured: bool) -> void:
	if textured:
		canvas.draw_texture_rect(CATWALK, rect, false, modulate)
	else:
		canvas.draw_rect(rect, modulate)


static func _draw_tile_detail(canvas: CanvasItem, tile: int, center: Vector2,
		cell: Vector2i, beacon: int, time: float, model) -> void:
	match tile:
		Generator.Tile.SPAWN:
			_draw_airlock(canvas, center, 0, GREEN, time)
		Generator.Tile.EXIT:
			_draw_airlock(canvas, center, 1, CYAN, time)
		Generator.Tile.CRYSTAL:
			if not model.collected.has(Generator.key(cell)):
				_draw_crystal(canvas, center + Vector2(0, sin(time * 4.0 + cell.x) * 1.2), time)
		Generator.Tile.HAZARD:
			_draw_hazard(canvas, center, beacon == Generator.Tool.SHIELD, time, cell)
		Generator.Tile.GAP:
			_draw_bridge(canvas, center, _mask(model.level, cell), time)


static func _draw_airlock(canvas: CanvasItem, center: Vector2, frame: int,
		glow: Color, time: float) -> void:
	var pulse := 0.25 + (sin(time * 4.0 + frame) * 0.5 + 0.5) * 0.25
	canvas.draw_circle(center, 10.0, Color(glow.r, glow.g, glow.b, pulse * 0.22))
	canvas.draw_texture_rect_region(AIRLOCKS, Rect2(center - Vector2(10, 10), Vector2(20, 20)),
		Rect2(frame * 28, 0, 28, 28))
	canvas.draw_rect(Rect2(center + Vector2(-1, -8), Vector2(2, 1)), glow)


static func _draw_crystal(canvas: CanvasItem, center: Vector2, time: float) -> void:
	var glow := 0.18 + (sin(time * 5.0) * 0.5 + 0.5) * 0.14
	canvas.draw_circle(center, 6.0, Color(0.2, 0.9, 1.0, glow))
	canvas.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -5), center + Vector2(3, -1), center + Vector2(1, 5),
		center + Vector2(-3, 1)]), CYAN)
	canvas.draw_line(center + Vector2(0, -4), center + Vector2(0, 3), WHITE, 1.0)
	canvas.draw_rect(Rect2(center + Vector2(-1, -3), Vector2(1, 2)), Color8(220, 255, 255))


static func _draw_hazard(canvas: CanvasItem, center: Vector2, shielded: bool,
		time: float, cell: Vector2i) -> void:
	var spark := fmod(time * 8.0 + cell.x * 0.7 + cell.y, 3.0)
	canvas.draw_line(center + Vector2(-4, -2), center + Vector2(4, 2), Color8(90, 20, 24), 2.0)
	canvas.draw_line(center + Vector2(-4, 2), center + Vector2(4, -2), RED, 1.0)
	canvas.draw_rect(Rect2(center + Vector2(-4 + spark * 2.0, -3), Vector2(1, 2)), AMBER)
	if shielded:
		var radius := 6.0 + sin(time * 6.0 + cell.x) * 0.7
		canvas.draw_arc(center, radius, PI, TAU, 12, Color(0.2, 0.95, 1.0, 0.76), 1.0)
		canvas.draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(0.2, 0.8, 1.0, 0.38), 1.0)


static func _draw_broken_gap(canvas: CanvasItem, center: Vector2, mask: int, time: float) -> void:
	for i in 4:
		if (mask & (1 << i)) == 0:
			continue
		var direction := Vector2(DIRS[i])
		var normal := Vector2(-direction.y, direction.x)
		var outer := center + direction * 7.0
		var inner := center + direction * 4.2
		canvas.draw_line(outer + normal * 3, inner + normal * 3, STEEL, 4.0)
		canvas.draw_line(outer - normal * 3, inner - normal * 3, STEEL, 4.0)
		canvas.draw_line(inner + normal * 3, inner - normal * 3, RUST, 1.0)
	var blink := 0.45 + (sin(time * 8.0) * 0.5 + 0.5) * 0.45
	canvas.draw_rect(Rect2(center - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.16, 0.12, blink))


static func _draw_bridge(canvas: CanvasItem, center: Vector2, mask: int, time: float) -> void:
	var horizontal := bool(mask & 2) or bool(mask & 8)
	var rect := Rect2(center - (Vector2(7, 3) if horizontal else Vector2(3, 7)),
		Vector2(14, 6) if horizontal else Vector2(6, 14))
	canvas.draw_rect(Rect2(rect.position + Vector2.ONE, rect.size), Color(0, 0, 0, 0.55))
	canvas.draw_texture_rect(CATWALK, rect, false, Color8(205, 218, 213))
	for i in 3:
		var offset := -4.0 + i * 4.0
		if horizontal:
			canvas.draw_line(center + Vector2(offset, -3), center + Vector2(offset, 3), CREAM, 1.0)
		else:
			canvas.draw_line(center + Vector2(-3, offset), center + Vector2(3, offset), CREAM, 1.0)
	var scan := fmod(time * 6.0, 8.0) - 4.0
	if horizontal:
		canvas.draw_rect(Rect2(center + Vector2(scan, -2), Vector2(1, 4)), CYAN)
	else:
		canvas.draw_rect(Rect2(center + Vector2(-2, scan), Vector2(4, 1)), CYAN)


static func _draw_hologram(canvas: CanvasItem, center: Vector2, tool: int,
		time: float, alpha: float) -> void:
	var pulse := alpha * (0.55 + (sin(time * 6.0 + center.x) * 0.5 + 0.5) * 0.30)
	if tool <= Generator.Tool.LEFT:
		var direction := Vector2(DIRS[tool])
		var normal := Vector2(-direction.y, direction.x)
		canvas.draw_circle(center, 4.2, Color(0.1, 0.85, 1.0, pulse * 0.18))
		canvas.draw_colored_polygon(PackedVector2Array([
			center + direction * 4.5, center - direction * 2.0 + normal * 2.5,
			center - direction * 2.0 - normal * 2.5]), Color(0.25, 0.95, 1.0, pulse))
		canvas.draw_line(center - direction * 2.0, center - direction * 4.0, Color(0.25, 0.95, 1.0, pulse), 1.0)
	elif tool == Generator.Tool.SHIELD:
		canvas.draw_arc(center, 5.0, PI, TAU, 10, Color(0.25, 0.95, 1.0, pulse), 1.0)


static func _draw_crew(canvas: CanvasItem, member: Dictionary, model, ticks: float,
		origin: Vector2, cell_size: float) -> void:
	var cell: Vector2i = member.get("cell", Vector2i.ZERO)
	var previous: Vector2i = member.get("previous_cell", cell)
	var travel := clampf(fmod(ticks, float(model_tick_span())) / float(model_tick_span()), 0.0, 1.0)
	var logical_position := Vector2(previous).lerp(Vector2(cell), travel)
	var center := origin + logical_position * cell_size + Vector2.ONE * cell_size * 0.5
	var direction: Vector2i = member.get("direction", Vector2i.RIGHT)
	var status := str(member.get("status", "active"))
	if status != "active":
		_draw_resolved_crew(canvas, member, status, ticks, center, origin, cell_size)
		return
	var moving := previous != cell
	var phase := mini(3, floori(travel * 4.0)) if moving else 0
	var base := 0
	if direction == Vector2i.LEFT:
		base = 4
	elif direction == Vector2i.UP:
		base = 8
	elif direction == Vector2i.DOWN:
		base = 12
	var current_tile := Generator.tile_at(model.level, cell)
	var previous_tile := Generator.tile_at(model.level, previous)
	var crossing_bridge := moving and (current_tile == Generator.Tile.GAP or previous_tile == Generator.Tile.GAP)
	var bob := sin((ticks + int(member.get("id", 0)) * 5) * 0.55) * 0.35 if moving else \
		sin((ticks + int(member.get("id", 0)) * 3) * 0.16) * 0.12
	canvas.draw_circle(center + Vector2(0.8, 4.1), 3.3, Color(0, 0, 0, 0.46))
	if crossing_bridge:
		# Eine Brueckenzelle ist zwei Modellschritte breit: Auf- und Abstieg bilden
		# zusammen genau einen Bogen, keinen doppelten Huepfer am Zellmittelpunkt.
		var hop_progress := travel * 0.5 if current_tile == Generator.Tile.GAP else 0.5 + travel * 0.5
		var jump_height := sin(hop_progress * PI) * 4.2
		var jump_phase := mini(3, floori(hop_progress * 4.0))
		if direction.x != 0:
			var jump_frame := jump_phase + (12 if direction == Vector2i.LEFT else 0)
			_draw_action_frame(canvas, center + Vector2(0, -jump_height), jump_frame, Color.WHITE)
		else:
			canvas.draw_texture_rect_region(CREW_WALK,
				Rect2(center + Vector2(-5, -10 - jump_height), Vector2(10, 15)),
				Rect2((base + jump_phase) * 20, 0, 20, 28))
	else:
		canvas.draw_texture_rect_region(CREW_WALK,
			Rect2(center + Vector2(-5, -10 + bob), Vector2(10, 15)),
			Rect2((base + phase) * 20, 0, 20, 28))


static func _draw_resolved_crew(canvas: CanvasItem, member: Dictionary, status: String,
		ticks: float, _resolved_center: Vector2, origin: Vector2, cell_size: float) -> void:
	var resolved_tick := float(member.get("resolved_tick", ticks))
	var age := maxf(0.0, ticks - resolved_tick)
	var cell: Vector2i = member.get("cell", Vector2i.ZERO)
	var previous: Vector2i = member.get("previous_cell", cell)
	var arrival := clampf(age / float(model_tick_span()), 0.0, 1.0)
	var position := origin + Vector2(previous).lerp(Vector2(cell), arrival) * cell_size
	position += Vector2.ONE * cell_size * 0.5
	if status == "rescued":
		var frame := 3 if age < 7.0 else (9 if age < 13.0 else 10 + posmod(floori(age / 3.0), 2))
		var alpha := clampf((24.0 - age) / 5.0, 0.0, 1.0)
		canvas.draw_circle(position, 6.0, Color(0.15, 0.9, 1.0, 0.12 * alpha))
		_draw_action_frame(canvas, position, frame, Color(1, 1, 1, alpha))
	else:
		var frame := 4 + mini(3, floori(age / 2.5))
		var fall := maxf(0.0, age - 6.0)
		var alpha := clampf((20.0 - age) / 6.0, 0.0, 1.0)
		position += Vector2(0, fall * fall * 0.08)
		_draw_action_frame(canvas, position, frame, Color(1, 1, 1, alpha))


static func _draw_action_frame(canvas: CanvasItem, center: Vector2, frame: int,
		modulate: Color) -> void:
	canvas.draw_texture_rect_region(CREW_ACTIONS,
		Rect2(center + Vector2(-6, -11), Vector2(12, 16)),
		Rect2(frame * 24, 0, 24, 28), modulate)


static func model_tick_span() -> int:
	# Gleicher Wert wie SpaceLemmingModel.MOVE_TICKS, ohne zyklischen Preload.
	return 8


static func _draw_particles(canvas: CanvasItem, particles: Array[Dictionary]) -> void:
	for particle: Dictionary in particles:
		var color: Color = particle["color"]
		color.a = clampf(float(particle["life"]) / float(particle["max"]), 0.0, 1.0)
		var size := float(particle["size"])
		canvas.draw_rect(Rect2(Vector2(particle["p"]).round(), Vector2.ONE * size), color)


static func _draw_focus(canvas: CanvasItem, center: Vector2, tool: int, time: float) -> void:
	var pulse := 0.72 + sin(time * 7.0) * 0.18
	var corners: Array[Vector2] = [Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)]
	for corner: Vector2 in corners:
		var sx := 1.0 if corner.x < 0 else -1.0
		var sy := 1.0 if corner.y < 0 else -1.0
		var anchor: Vector2 = center + corner
		canvas.draw_line(anchor, anchor + Vector2(sx * 2.5, 0), Color(0.65, 0.95, 1.0, pulse), 1.0)
		canvas.draw_line(anchor, anchor + Vector2(0, sy * 2.5), Color(0.65, 0.95, 1.0, pulse), 1.0)
	_draw_hologram(canvas, center, tool, time, 0.28)


static func _mask(level: Dictionary, cell: Vector2i) -> int:
	var mask := 0
	for i in 4:
		if Generator.tile_at(level, cell + DIRS[i]) != Generator.Tile.VOID:
			mask |= 1 << i
	return mask


static func _center(origin: Vector2, cell_size: float, cell: Vector2i) -> Vector2:
	return origin + Vector2(cell) * cell_size + Vector2.ONE * cell_size * 0.5
