extends RefCounted
## Spielfeld-Renderer der Stefan-Anthologie: der Verteiler draw_play, das HUD und
## die neun Genre-Ansichten. Einziger Teil, der das Spielmodell liest.
##
## Aufgeteilt aus stefan_game_renderer.gd (Zeilenbudget). Kein class_name.

const Base := preload("res://scripts/games/stefan_game_render_base.gd")
const StefanSprites := preload("res://scripts/games/stefan_game_sprites.gd")
const Model := preload("res://scripts/games/stefan_game_model.gd")
const PlayfieldArt := preload("res://scripts/games/amiga_playfield_art.gd")


static func draw_play(canvas: CanvasItem, _texture: Texture2D, definition: Dictionary,
		model: StefanGameModel, anim: float, flash: float, particles: Array[Dictionary]) -> void:
	# Titel-/Box-Art und Gameplay sind bewusst getrennt. Das Spiel zeichnet
	# ausschliesslich eine 320x200-Tilekulisse aus der OCS-artigen Laufzeitpalette;
	# dadurch treffen keine fotorealistischen Atlasdetails mehr auf Blitter-Sprites.
	PlayfieldArt.draw(canvas, definition, anim)
	match model.mode:
		"shooter": _draw_shooter(canvas, model, anim, definition)
		"platform": _draw_platform(canvas, model, anim, definition)
		"circuit": _draw_circuit(canvas, model, anim, definition)
		"miner": _draw_miner(canvas, model, anim, definition)
		"rescue": _draw_rescue(canvas, model, anim, definition)
		"stealth": _draw_stealth(canvas, model, anim, definition)
		"racer": _draw_racer(canvas, model, anim, definition)
		"strategy": _draw_strategy(canvas, model, anim, definition)
		"rhythm": _draw_rhythm(canvas, model, anim, definition)
	_draw_hud(canvas, definition, model)
	for particle: Dictionary in particles:
		var p: Vector2 = particle.get("pos", Vector2.ZERO)
		var color: Color = particle.get("color", Base.accent(definition))
		canvas.draw_rect(Rect2(p.floor(), Vector2(2, 2)), color)
	if flash > 0.0:
		canvas.draw_rect(Rect2(0, 0, 320, 200), Color(1, 1, 1, flash * 0.25))
	Base.scanlines(canvas, 0.08)
static func _draw_hud(canvas: CanvasItem, definition: Dictionary, model: StefanGameModel) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 22), Color8(3, 6, 10))
	canvas.draw_line(Vector2(0, 21), Vector2(320, 21), Base.accent(definition), 1)
	Base.text(canvas, model.objective_status(), Vector2(5, 10), 7, Base.PAPER)
	Base.text(canvas, "%06d" % model.score, Vector2(170, 10), 7, Base.AMBER,
		HORIZONTAL_ALIGNMENT_RIGHT, 70)
	Base.text(canvas, "%02d" % ceili(model.remaining()), Vector2(245, 10), 7, Base.PAPER,
		HORIZONTAL_ALIGNMENT_RIGHT, 35)
	Base.text(canvas, str(definition.get("title", "")), Vector2(5, 19), 6, Base.accent(definition),
		HORIZONTAL_ALIGNMENT_LEFT, 245)
	Base.text(canvas, Base._hardware_label(definition), Vector2(261, 19), 6,
		Color8(132, 153, 164), HORIZONTAL_ALIGNMENT_RIGHT, 54)
static func _draw_shooter(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	var a := Base.accent(definition)
	for i in 30:
		var x := posmod(i * 47 - floori(anim * (18 + i % 3 * 8)), 320)
		var y := 28 + posmod(i * 29, 155)
		canvas.draw_rect(Rect2(x, y, 1 + i % 2, 1),
			Base.STEEL_LIT if i % 4 else Base.PAPER)
	for object: Dictionary in model.objects:
		var p: Vector2 = object.get("pos", Vector2.ZERO)
		if object.get("kind", "") == "cargo":
			StefanSprites._draw_cargo_sprite(canvas, p, a, anim)
		else:
			StefanSprites._draw_drone_sprite(canvas, p, Base.danger(definition), anim,
				int(object.get("hp", 1)) > 1)
	for shot: Dictionary in model.shots:
		var p: Vector2 = shot.get("pos", Vector2.ZERO)
		Base.pixel_rect(canvas, Rect2(p.floor(), Vector2(7, 2)), Base.PAPER)
		Base.pixel_rect(canvas, Rect2(p.floor() + Vector2(1, 0), Vector2(4, 1)), a.lightened(0.35))
	StefanSprites._draw_ship_sprite(canvas, model.player, a, anim, model.variant)
static func _draw_platform(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	for platform: Rect2 in model.platforms:
		StefanSprites._draw_platform_span(canvas, platform, model.variant, definition, anim)
	if model.variant == "lava":
		for x in range(10, 312, 11):
			var y := 187 + floori(sin(anim * 3.0 + x * 0.13) * 2.0)
			Base.pixel_rect(canvas, Rect2(x, y, 7, 3), Base.RED.darkened(0.15))
			Base.pixel_rect(canvas, Rect2(x + 2, y, 3, 1), Base.AMBER)
	elif model.variant == "arena":
		# Beide Tore sind Teil der Arena, nicht generische Quest-Ausgänge.
		for side in [-1, 1]:
			var goal_x := 10 if side < 0 else 297
			Base.pixel_rect(canvas, Rect2(goal_x, 89, 13, 43), Base.INK)
			Base.pixel_rect(canvas, Rect2(goal_x + (2 if side < 0 else 0), 92, 10, 37),
				Color8(31, 67, 91))
			for goal_y in range(94, 129, 6):
				Base.pixel_rect(canvas, Rect2(goal_x + 2, goal_y, 9, 1),
					Base.RED if side < 0 else Base.CYAN)
			if Base._hardware_tier(definition) == 2:
				var pulse_y := 94 + posmod(floori(anim * 24.0), 30)
				Base.pixel_rect(canvas, Rect2(goal_x + 2, pulse_y, 9, 1), Base.PAPER)
	for object: Dictionary in model.objects:
		if object.get("dead", false):
			continue
		var p: Vector2 = object.get("pos", Vector2.ZERO)
		if object.get("kind", "") == "token":
			StefanSprites._draw_platform_token(canvas, p, model.variant, definition, anim)
		elif object.get("kind", "") == "exit":
			StefanSprites._draw_platform_exit(canvas, p, model.variant, definition, anim,
				model.progress >= model.required)
	if model.variant == "arena":
		StefanSprites._draw_arena_ball(canvas, model._arena_ball, anim, definition)
	StefanSprites._draw_runner_sprite(canvas, model.player, Base.accent(definition), model.velocity, anim,
		model.variant, definition)
static func _draw_circuit(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	var origin := Vector2(43, 35)
	var cell_size := Vector2(39, 28)
	var reached := model.connected_cells()
	for index in model.grid.size():
		var cell := Vector2i(index % Model.CIRCUIT_W, floori(float(index) / Model.CIRCUIT_W))
		var rect := Rect2(origin + Vector2(cell) * cell_size, cell_size - Vector2(3, 3))
		var powered := index in reached
		var line_color := Base.accent(definition) if powered else Base.STEEL_LIT
		Base.bevel(canvas, rect, Color8(6, 15, 20), Base.STEEL, line_color.darkened(0.2))
		var center := rect.get_center()
		var mask: int = model.grid[index]
		for direction in Model.DIRS.size():
			if (mask & Model.BITS[direction]) != 0:
				canvas.draw_line(center, center + Vector2(Model.DIRS[direction]) * 12.0, line_color, 3)
				if powered:
					var pulse := fmod(anim * 18.0 + float(index * 7 + direction * 3), 10.0) / 10.0
					Base._pixel_disc(canvas,
						(center + Vector2(Model.DIRS[direction]) * 11.0 * pulse).floor(),
						1, Base.PAPER)
		Base._pixel_disc(canvas, center, 2,
			Base.PAPER if index in model.grid_targets else line_color,
			line_color.lightened(0.28))
		if index in model.grid_targets:
			var target_radius := 7 + (floori(anim * 4.0 + index) & 1)
			Base._pixel_diamond_outline(canvas, center, target_radius, line_color)
	var cursor_rect := Rect2(origin + Vector2(model.cursor) * cell_size - Vector2(2, 2), cell_size + Vector2(1, 1))
	canvas.draw_rect(cursor_rect, Base.AMBER, false, 2)
static func _draw_miner(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	var origin := Vector2(32, 32)
	var size := Vector2(16, 17)
	for index in model.grid.size():
		var cell := Vector2i(index % Model.GRID_W, floori(float(index) / Model.GRID_W))
		var rect := Rect2(origin + Vector2(cell) * size, size - Vector2.ONE)
		if model.grid[index] == 1:
			var rock := Color8(79, 49, 43) if model.variant == "magma" else Color8(67, 51, 67)
			Base.pixel_rect(canvas, rect, rock)
			canvas.draw_line(rect.position + Vector2(2, 4), rect.end - Vector2(3, 5),
				rock.lightened(0.25), 1)
			if (index * 7) % 11 == 0:
				Base.pixel_rect(canvas, Rect2(rect.position + Vector2(10, 3), Vector2(3, 2)),
					Base.AMBER.darkened(0.25) if model.variant == "magma" else Base.VIOLET.darkened(0.2))
		else:
			Base.pixel_rect(canvas, rect, Color8(5, 9, 15))
			if (index + floori(anim * 2.0)) % 17 == 0:
				Base.pixel_rect(canvas, Rect2(rect.position + Vector2(4, 8), Vector2(2, 1)),
					Color8(55, 75, 88))
	for object: Dictionary in model.objects:
		if not object.get("dead", false):
			var cell: Vector2i = object.get("cell", Vector2i.ZERO)
			var p := origin + Vector2(cell) * size + size * 0.5
			StefanSprites._draw_crystal_sprite(canvas, p, Base.accent(definition), anim,
				1.0 if model.variant != "magma" else 0.85)
	var player_p := origin + Vector2(model.cursor) * size + size * 0.5
	StefanSprites._draw_miner_rover(canvas, player_p, Base.AMBER, anim, model.variant)
	var base_rect := Rect2(origin + Vector2(1, 1), Vector2(14, 15))
	Base.pixel_rect(canvas, base_rect, Color8(5, 20, 15))
	canvas.draw_rect(base_rect, Base.GREEN, false, 2)
	Base.pixel_rect(canvas, Rect2(base_rect.position + Vector2(4, 5), Vector2(6, 3)), Base.GREEN)
static func _draw_rescue(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	var is_ice := model.variant == "ice"
	# Mehrere unterschiedlich laufende Strömungslinien geben dem Wasser Tiefe,
	# ohne die klaren 32-Farb-Silhouetten oder Kollisionsräume zu verwischen.
	for band in 7:
		for x in range(8, 313, 8):
			var phase := float(x) * 0.045 + anim * (0.7 + band * 0.08)
			var y := 38.0 + band * 22.0 + sin(phase + band * 1.7) * (2.0 + band * 0.18)
			if (floori(float(x) / 8.0) + band) % 2 == 0:
				Base.pixel_rect(canvas, Rect2(x, roundi(y), 3 if band % 2 == 0 else 2, 1),
					Color8(46, 115, 145) if not is_ice else Color8(102, 151, 174))
	for i in 12:
		var x := posmod(i * 37 + floori(anim * (6 if is_ice else -8)), 304) + 8
		for ray_y in range(28 + i % 4, 187, 12):
			if (ray_y + i) % 3 != 0:
				Base.pixel_rect(canvas, Rect2(x + floori(float(ray_y - 28) / 18.0), ray_y,
					1, 3), Color8(72, 130, 151) if not is_ice else Color8(144, 179, 190))
	for i in 18:
		var bx := 12 + posmod(i * 53, 294)
		var by := 30 + posmod(i * 31 - floori(anim * (13.0 + i % 3)), 151)
		Base._pixel_disc(canvas, Vector2(bx, by), 1 if i % 2 == 0 else 2,
			Color8(117, 179, 194) if not is_ice else Color8(191, 220, 223))
	for object: Dictionary in model.objects:
		var p: Vector2 = object.get("pos", Vector2.ZERO)
		if object.get("kind", "") == "survivor" and not object.get("dead", false):
			StefanSprites._draw_survivor_sprite(canvas, p, anim, is_ice)
		elif object.get("kind", "") == "hazard":
			StefanSprites._draw_hazard_sprite(canvas, p, float(object.get("radius", 8)), Base.danger(definition), is_ice)
	Base.pixel_rect(canvas, Rect2(model.base_position - Vector2(11, 8), Vector2(22, 16)), Base.INK)
	Base.pixel_rect(canvas, Rect2(model.base_position - Vector2(9, 6), Vector2(18, 12)), Base.GREEN.darkened(0.48))
	canvas.draw_rect(Rect2(model.base_position - Vector2(8, 5), Vector2(16, 10)), Base.GREEN, false, 2)
	Base.pixel_rect(canvas, Rect2(model.base_position + Vector2(-2, -10), Vector2(4, 4)), Base.PAPER)
	StefanSprites._draw_rescue_craft(canvas, model.player, Base.accent(definition), anim, is_ice)
	if model.secondary > 0:
		for ring in 3:
			var radius := 10 + (30 - model.secondary + ring * 8) * 2
			if radius < 78:
				Base._pixel_diamond_outline(canvas, model.player, radius,
					Base.accent(definition).darkened(0.12 + ring * 0.12))
static func _draw_stealth(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	var origin := Vector2(24, 32)
	var cell_size := Vector2(17, 17)
	var alert_color := Base.danger(definition)
	for y in Model.GRID_H:
		for x in Model.GRID_W:
			var dark := Color8(9, 20, 26) if (x + y) % 2 == 0 else Color8(12, 27, 31)
			var tile := Rect2(origin + Vector2(x, y) * cell_size, cell_size - Vector2.ONE)
			Base.pixel_rect(canvas, tile, dark)
			if (x * 7 + y * 11) % 13 == 0:
				Base.pixel_rect(canvas, Rect2(tile.position + Vector2(3, 3), Vector2(4, 1)), Base.STEEL.darkened(0.35))
	# Sichtachsen liegen unter Figuren und Terminals. Damit ist vor jedem Zug
	# erkennbar, welche Felder nach der naechsten Patrouillenbewegung riskant
	# werden; zuvor waren Treffer unsichtbare reine Modelllogik.
	for object: Dictionary in model.objects:
		if str(object.get("kind", "")) != "guard":
			continue
		var guard_cell: Vector2i = object.get("cell", Vector2i.ZERO)
		var axis := int(object.get("axis", 0))
		var reach := 4 if axis == 0 else 3
		for offset in range(-reach, reach + 1):
			var watched := guard_cell
			watched[axis] += offset
			if watched.x < 0 or watched.y < 0 or watched.x >= Model.GRID_W or watched.y >= Model.GRID_H:
				continue
			var watched_rect := Rect2(origin + Vector2(watched) * cell_size + Vector2(2, 2),
				cell_size - Vector2(5, 5))
			canvas.draw_rect(watched_rect, Color(alert_color, 0.12 if offset != 0 else 0.2))
			if offset != 0 and (absi(offset) + floori(anim * 4.0)) % 2 == 0:
				var center := watched_rect.get_center().floor()
				Base.pixel_rect(canvas, Rect2(center, Vector2(2, 1)), Color(alert_color, 0.58))
	for object: Dictionary in model.objects:
		var cell: Vector2i = object.get("cell", Vector2i.ZERO)
		var p := origin + Vector2(cell) * cell_size + cell_size * 0.5
		match str(object.get("kind", "")):
			"terminal":
				if not object.get("dead", false):
					Base.pixel_rect(canvas, Rect2(p - Vector2(6, 6), Vector2(12, 12)), Base.INK)
					Base.pixel_rect(canvas, Rect2(p - Vector2(5, 5), Vector2(10, 10)), Base.CYAN.darkened(0.24))
					Base.pixel_rect(canvas, Rect2(p - Vector2(3, 3), Vector2(6, 4)), Base.INK)
					Base.pixel_rect(canvas, Rect2(p + Vector2(-2, -2), Vector2(4, 1)),
						Base.PAPER if floori(anim * 5.0) % 2 == 0 else Base.GREEN)
			"guard":
				var axis := int(object.get("axis", 0))
				var dir := int(object.get("dir", 1))
				StefanSprites._draw_guard_sprite(canvas, p, Base.danger(definition), axis, dir, anim)
			"exit":
				Base.pixel_rect(canvas, Rect2(p - Vector2(7, 8), Vector2(14, 16)), Base.INK)
				var exit_color := Base.GREEN if model.progress >= model.required else Base.STEEL
				canvas.draw_rect(Rect2(p - Vector2(5, 6), Vector2(10, 12)), exit_color, false, 2)
				Base.pixel_rect(canvas, Rect2(p + Vector2(1, 0), Vector2(2, 2)), Base.PAPER)
	var player_p := origin + Vector2(model.cursor) * cell_size + cell_size * 0.5
	StefanSprites._draw_agent_sprite(canvas, player_p, Base.accent(definition), anim)
	Base.text(canvas, "ALARM", Vector2(24, 196), 6,
		alert_color if model.secondary > 0 else Base.STEEL_LIT)
	Base.pixel_rect(canvas, Rect2(58, 189, 102, 7), Base.INK)
	canvas.draw_rect(Rect2(59, 190, 100, 5), Base.STEEL, false, 1)
	var alarm_width := floori(clampf(float(model.secondary) / float(Model.STEALTH_ALARM_MAX),
		0.0, 1.0) * 98.0)
	if alarm_width > 0:
		Base.pixel_rect(canvas, Rect2(60, 191, alarm_width, 3),
			alert_color if model.secondary >= 67 else Base.AMBER)
	Base.text(canvas, "SHIFT: WARTEN / ALARM SENKEN", Vector2(166, 196), 6, Base.STEEL_LIT)
static func _draw_racer(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	var horizon := 58.0
	for i in 26:
		var x := 8 + posmod(i * 43 - floori(anim * 55.0), 304)
		Base.pixel_rect(canvas, Rect2(x, 28 + i % 4 * 5, 1, 1),
			Base.PAPER if i % 3 else Base.STEEL_LIT)
	# Eigenes Skyline-/Bergprofil je Epoche; es bleibt hinter der Fahrbahn und
	# ist bewusst blockig wie eine handgepixelte Dual-Playfield-Kulisse.
	var skyline := PackedVector2Array([Vector2(8, 58), Vector2(8, 48), Vector2(23, 48),
		Vector2(23, 40), Vector2(37, 40), Vector2(37, 52), Vector2(55, 52),
		Vector2(68, 35), Vector2(84, 52), Vector2(103, 52), Vector2(115, 43),
		Vector2(132, 52), Vector2(148, 39), Vector2(166, 52), Vector2(184, 52),
		Vector2(203, 34), Vector2(224, 52), Vector2(246, 45), Vector2(263, 52),
		Vector2(279, 38), Vector2(295, 52), Vector2(312, 52), Vector2(312, 58)])
	canvas.draw_colored_polygon(skyline,
		Color8(28, 26, 54) if model.variant == "bike" else Color8(26, 41, 50))
	for x in range(18, 306, 19):
		if (x + floori(anim * 2.0)) % 3 != 0:
			Base.pixel_rect(canvas, Rect2(x, 47 - (x % 11), 2, 1),
				Base.VIOLET if model.variant == "bike" else Base.AMBER)
	var road := PackedVector2Array([Vector2(128, horizon), Vector2(192, horizon), Vector2(300, 190), Vector2(20, 190)])
	var left_shoulder := PackedVector2Array([Vector2(123, horizon), Vector2(128, horizon),
		Vector2(20, 190), Vector2(8, 190)])
	var right_shoulder := PackedVector2Array([Vector2(192, horizon), Vector2(197, horizon),
		Vector2(312, 190), Vector2(300, 190)])
	canvas.draw_colored_polygon(left_shoulder, Color8(48, 35, 61))
	canvas.draw_colored_polygon(right_shoulder, Color8(48, 35, 61))
	canvas.draw_colored_polygon(road, Color8(31, 38, 48))
	canvas.draw_line(Vector2(128, horizon), Vector2(20, 190), Base.accent(definition), 2)
	canvas.draw_line(Vector2(192, horizon), Vector2(300, 190), Base.accent(definition), 2)
	for lane_index in range(1, 5):
		var top_x := lerpf(128.0, 192.0, float(lane_index) / 5.0)
		var bottom_x := lerpf(20.0, 300.0, float(lane_index) / 5.0)
		canvas.draw_line(Vector2(top_x, horizon), Vector2(bottom_x, 190), Base.STEEL_LIT, 1)
	for z in 9:
		var depth_phase := float(posmod(z + floori(anim * 8.0), 9)) / 8.0
		var y := horizon + pow(depth_phase, 2.0) * 128.0
		if z % 2 == 0:
			canvas.draw_line(Vector2(45 + (y - horizon) * 0.52, y),
				Vector2(275 - (y - horizon) * 0.52, y), Base.STEEL.darkened(0.28), 1)
		var edge_half := 1.0 + depth_phase * 2.0
		var left_x := lerpf(126.0, 15.0, depth_phase)
		var right_x := lerpf(194.0, 305.0, depth_phase)
		Base.pixel_rect(canvas, Rect2(Vector2(left_x - edge_half, y - edge_half),
			Vector2(edge_half * 2.0, edge_half * 2.0)), Base.AMBER)
		Base.pixel_rect(canvas, Rect2(Vector2(right_x - edge_half, y - edge_half),
			Vector2(edge_half * 2.0, edge_half * 2.0)), Base.CYAN)
	# Perspektivische Mittelliniensegmente statt einer starren Kreuzschraffur.
	for z in 8:
		var phase := fmod(float(z) / 8.0 + anim * 0.32, 1.0)
		var y0 := horizon + phase * phase * 132.0
		var y1 := horizon + minf(1.0, phase + 0.055) * minf(1.0, phase + 0.055) * 132.0
		var half0 := 2.0 + phase * 7.0
		Base.pixel_polygon(canvas, PackedVector2Array([
			Vector2(160.0 - half0, y0), Vector2(160.0 + half0, y0),
			Vector2(160.0 + half0 + 2.0, y1), Vector2(160.0 - half0 - 2.0, y1),
		]), Base.PAPER.darkened(0.18), Color(0, 0, 0, 0))
	for object: Dictionary in model.objects:
		var y := float(object.get("y", 24.0))
		var depth := clampf((y - 24.0) / 174.0, 0.0, 1.0)
		var lane_x := lerpf(145.0, 48.0 + int(object.get("lane", 0)) * 56.0, depth)
		var size := 3.0 + depth * 8.0
		if object.get("kind", "") == "marker":
			StefanSprites._draw_crystal_sprite(canvas, Vector2(lane_x, y), Base.AMBER, anim, 0.35 + depth * 0.65)
		else:
			var rect := Rect2(Vector2(lane_x, y) - Vector2(size * 0.55, size),
				Vector2(size * 1.1, size * 1.45))
			Base.pixel_rect(canvas, rect, Base.INK)
			Base.pixel_rect(canvas, rect.grow(-1.0), Base.danger(definition).darkened(depth * 0.18))
			if depth > 0.42:
				Base.pixel_rect(canvas, Rect2(rect.position + Vector2(2, rect.size.y - 3), Vector2(2, 2)), Base.RED)
				Base.pixel_rect(canvas, Rect2(rect.end - Vector2(4, 3), Vector2(2, 2)), Base.RED)
	var car := Vector2(48 + model.lane * 56, 171)
	StefanSprites._draw_vehicle_sprite(canvas, car, Base.accent(definition), anim, model.variant == "bike")
static func _draw_strategy(canvas: CanvasItem, model: StefanGameModel, _anim: float,
		definition: Dictionary) -> void:
	var a := Base.accent(definition)
	Base.text(canvas, "LAGEZENTRALE", Vector2(12, 37), 12, a)
	for i in model.resources.size():
		var rect := Rect2(16, 48 + i * 31, 190, 24)
		Base.bevel(canvas, rect, Base.PANEL if i != model.selected else Base.PANEL.lightened(0.12),
			a if i == model.selected else Base.STEEL, a if i == model.selected else Base.STEEL_LIT)
		Base.text(canvas, str(model.resource_names[i]), Vector2(23, rect.position.y + 10), 8,
			Base.PAPER if i == model.selected else Base.STEEL_LIT)
		var value := int(model.resources[i])
		canvas.draw_rect(Rect2(23, rect.position.y + 14, 150, 5), Base.INK)
		canvas.draw_rect(Rect2(24, rect.position.y + 15, 148.0 * value / 100.0, 3),
			Base.GREEN if value >= 40 else Base.danger(definition))
		Base.text(canvas, "%3d" % value, Vector2(176, rect.position.y + 17), 8, Base.PAPER,
			HORIZONTAL_ALIGNMENT_RIGHT, 23)
		var delta := int(model.forecast[i]) if i < model.forecast.size() else 0
		Base.text(canvas, "%+d" % delta, Vector2(215, rect.position.y + 16), 9,
			Base.GREEN if delta >= 0 else Base.danger(definition))
	Base.bevel(canvas, Rect2(248, 50, 57, 111), Color8(5, 10, 15), Base.STEEL, a)
	Base.text(canvas, "ZYKLUS", Vector2(252, 65), 7, Base.STEEL_LIT, HORIZONTAL_ALIGNMENT_CENTER, 49)
	Base.text(canvas, "%02d" % model.turn, Vector2(252, 91), 19, Base.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 49)
	Base.text(canvas, "BUDGET", Vector2(252, 112), 7, Base.STEEL_LIT, HORIZONTAL_ALIGNMENT_CENTER, 49)
	Base.text(canvas, "+%d" % model.allocation, Vector2(252, 137), 17, Base.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 49)
	Base.text(canvas, "FIRE: ZYKLUS · SHIFT: BUDGET", Vector2(8, 182), 7, Base.PAPER,
		HORIZONTAL_ALIGNMENT_CENTER, 304)
static func _draw_rhythm(canvas: CanvasItem, model: StefanGameModel, anim: float,
		definition: Dictionary) -> void:
	var colors := [Base.CYAN, Base.GREEN, Base.AMBER, Base.VIOLET]
	var origin := Vector2(60, 27)
	for lane_index in 4:
		var rect := Rect2(origin.x + lane_index * 51, origin.y, 44, 151)
		canvas.draw_rect(rect, Color8(6, 15, 23))
		canvas.draw_rect(rect, colors[lane_index].darkened(0.35), false, 1)
		for y in range(38, 150, 13):
			for dash_x in range(roundi(rect.position.x) + 2, roundi(rect.end.x) - 2, 6):
				Base.pixel_rect(canvas, Rect2(dash_x, y, 2, 1),
					colors[lane_index].darkened(0.74))
		Base.text(canvas, ["D", "F", "J", "K"][lane_index], Vector2(rect.position.x, 174), 9,
			colors[lane_index], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	canvas.draw_rect(Rect2(58, 149, 202, 11), Base.INK)
	canvas.draw_line(Vector2(60, 154), Vector2(258, 154), Base.PAPER, 2)
	for lane_index in 4:
		canvas.draw_rect(Rect2(origin.x + lane_index * 51 + 3, 151, 38, 7),
			colors[lane_index], false, 1)
	for note: Dictionary in model.song_notes:
		if note.get("hit", false) or note.get("miss", false):
			continue
		var dt := float(note.get("time", 0.0)) - model.elapsed
		if dt < -0.3 or dt > 2.25:
			continue
		var lane_index := int(note.get("lane", 0))
		var y := 154.0 - dt / 2.25 * 119.0
		var x := origin.x + lane_index * 51 + 5
		Base.bevel(canvas, Rect2(x, y - 4, 34, 8), colors[lane_index].darkened(0.12),
			colors[lane_index].darkened(0.35), colors[lane_index].lightened(0.35))
		Base.pixel_rect(canvas, Rect2(x + 4, y - 1, 26, 2), Base.PAPER)
	# Reaktor-/Tunnelpuls links: rein kosmetisch, aber an Songphase und Combo gekoppelt.
	var core := Vector2(30, 126)
	var core_radius := 8 + floori(sin(anim * 7.0)) + mini(4, floori(model.combo * 0.12))
	Base._pixel_diamond_outline(canvas, core, core_radius + 5, Base.accent(definition).darkened(0.68))
	Base._pixel_disc(canvas, core, 4, Base.accent(definition).darkened(0.2),
		Base.accent(definition).lightened(0.25))
	Base._pixel_disc(canvas, core, 2, Base.PAPER)
	for ring in 2:
		var ring_radius := 14 + ring * 6 + floori(fmod(anim * 8.0, 6.0))
		Base._pixel_diamond_outline(canvas, core, ring_radius,
			Base.accent(definition).darkened(0.35 + ring * 0.16))
	Base.text(canvas, "COMBO %02d" % model.combo, Vector2(8, 57), 9, Base.accent(definition))
	Base.text(canvas, "%3d%%" % roundi(model.accuracy() * 100.0), Vector2(8, 76), 11, Base.PAPER)
