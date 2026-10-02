extends RefCounted
## Blitter-Sprites der Stefan-Anthologie: Figuren, Fahrzeuge, Plattform- und
## Torelemente. Reine Zeichenroutinen ohne Modellwissen.
##
## Aufgeteilt aus stefan_game_renderer.gd (Zeilenbudget). Kein class_name.

const Base := preload("res://scripts/games/stefan_game_render_base.gd")


static func _draw_gear(canvas: CanvasItem, center: Vector2, color: Color,
		anim: float, scale := 1.0) -> void:
	var p := center.floor()
	var frame := floori(anim * 8.0) & 3
	var tooth := maxi(1, roundi(scale * 2.0))
	var offsets: Array[Vector2i]
	if frame % 2 == 0:
		offsets = [Vector2i(-6, -1), Vector2i(5, -1), Vector2i(-1, -6),
			Vector2i(-1, 5), Vector2i(-5, -5), Vector2i(4, -5),
			Vector2i(-5, 4), Vector2i(4, 4)]
	else:
		offsets = [Vector2i(-6, -3), Vector2i(5, 1), Vector2i(1, -6),
			Vector2i(-3, 5), Vector2i(-5, -1), Vector2i(4, -3),
			Vector2i(-3, -5), Vector2i(2, 4)]
	for offset: Vector2i in offsets:
		Base.pixel_rect(canvas, Rect2(p + Vector2(offset) * scale,
			Vector2(tooth, tooth)), color.darkened(0.18))
	var r := 4 if scale >= 1.0 else 3
	Base._pixel_disc(canvas, p, r, color, color.lightened(0.32))
	Base._pixel_disc(canvas, p, 1, Base.INK)
static func _draw_ship_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float, variant: String) -> void:
	var center := p.floor()
	var exhaust := 4 + (floori(anim * 14.0) % 3)
	# Zweifaches Triebwerk mit heissem Kern statt des alten Dreiecks.
	Base.pixel_rect(canvas, Rect2(center + Vector2(-13 - exhaust, -5), Vector2(exhaust + 3, 3)),
		Color8(52, 132, 205))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-13 - exhaust, 3), Vector2(exhaust + 3, 3)),
		Color8(52, 132, 205))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-12 - exhaust, -4), Vector2(exhaust, 1)), Base.PAPER)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-12 - exhaust, 4), Vector2(exhaust, 1)), Base.PAPER)
	var hull := PackedVector2Array([
		center + Vector2(-12, -4), center + Vector2(-4, -6), center + Vector2(11, -2),
		center + Vector2(15, 0), center + Vector2(11, 2), center + Vector2(-4, 6),
		center + Vector2(-12, 4), center + Vector2(-8, 0),
	])
	Base.pixel_polygon(canvas, hull, color)
	Base.pixel_polygon(canvas, PackedVector2Array([
		center + Vector2(-4, -4), center + Vector2(1, -9), center + Vector2(7, -8),
		center + Vector2(5, -2),
	]), color.darkened(0.24))
	Base.pixel_polygon(canvas, PackedVector2Array([
		center + Vector2(-4, 4), center + Vector2(1, 9), center + Vector2(7, 8),
		center + Vector2(5, 2),
	]), color.darkened(0.24))
	Base.pixel_rect(canvas, Rect2(center + Vector2(3, -2), Vector2(6, 4)),
		Color8(129, 223, 239) if variant != "fighter" else Color8(248, 190, 70))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-10, -2), Vector2(3, 4)), Base.STEEL_LIT)
	if variant in ["fighter", "finale"]:
		Base.pixel_rect(canvas, Rect2(center + Vector2(4, -8), Vector2(5, 2)), Base.danger({}))
		Base.pixel_rect(canvas, Rect2(center + Vector2(4, 6), Vector2(5, 2)), Base.danger({}))
static func _draw_drone_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float, elite := false) -> void:
	var center := p.floor()
	var wing := 7 if not elite else 9
	Base.pixel_polygon(canvas, PackedVector2Array([
		center + Vector2(-wing, -5), center + Vector2(4, -3), center + Vector2(8, 0),
		center + Vector2(4, 3), center + Vector2(-wing, 5), center + Vector2(-3, 0),
	]), color)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-5, -1), Vector2(8, 3)), color.lightened(0.25))
	Base.pixel_rect(canvas, Rect2(center + Vector2(3, -1), Vector2(3, 2)), Base.PAPER)
	if floori(anim * 8.0) % 2 == 0:
		Base.pixel_rect(canvas, Rect2(center + Vector2(-wing - 3, -1), Vector2(3, 2)), Base.AMBER)
static func _draw_cargo_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float) -> void:
	var center := p.floor()
	Base.pixel_rect(canvas, Rect2(center - Vector2(6, 5), Vector2(12, 10)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center - Vector2(5, 4), Vector2(10, 8)), color.darkened(0.35))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-1, -4), Vector2(2, 8)), color)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-5, -1), Vector2(10, 2)), color)
	Base.pixel_rect(canvas, Rect2(center + Vector2(2, -3), Vector2(2, 2)), Base.PAPER)
	if floori(anim * 5.0) % 2 == 0:
		Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -3), Vector2(1, 1)), Base.GREEN)
static func _draw_runner_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		velocity: Vector2, anim: float, variant: String, definition: Dictionary) -> void:
	var center := p.floor()
	var facing := -1 if velocity.x < -1.0 else 1
	var moving := absf(velocity.x) > 5.0
	var airborne := absf(velocity.y) > 8.0
	var tier := Base._hardware_tier(definition)
	var frame_count: int = [6, 8, 12][tier]
	var phase: int = floori(anim * (8.0 + tier * 1.5)) % frame_count
	var sample := floori(float(phase) * 12.0 / float(frame_count)) % 12
	var leg_a: int = int(Base.RUN_LEG_A[sample]) if moving else -2
	var leg_b: int = int(Base.RUN_LEG_B[sample]) if moving else 2
	var arm_a: int = int(Base.RUN_ARM_A[sample]) if moving else 2
	var arm_b: int = int(Base.RUN_ARM_B[sample]) if moving else -2
	if airborne:
		leg_a = -3 * facing
		leg_b = 3 * facing
		arm_a = 4 * facing
		arm_b = -3 * facing
	# Harte, gerasterte Kontaktschatten statt Alpha-Ellipse. AGA erhaelt bei
	# hohem Tempo einen diskreten Blitter-Nachzieher, nie ein weiches Sprite.
	Base.pixel_rect(canvas, Rect2(center + Vector2(-6, 6), Vector2(12, 1)),
		Color8(4, 7, 11))
	if tier == 2 and moving and absf(velocity.x) > 52.0:
		Base.pixel_rect(canvas, Rect2(center + Vector2(-facing * 8 - 2, -5),
			Vector2(3, 8)), color.darkened(0.72))
	var skin := Color8(224, 173, 123)
	var hair := Color8(77, 43, 29)
	var suit_dark := color.darkened(0.38)
	var suit_light := color.lightened(0.22 if tier >= 1 else 0.08)
	if variant == "lava":
		skin = Color8(206, 155, 110)
		hair = Color8(224, 230, 218) # geschlossener Hitzeschutzhelm
		suit_dark = Color8(61, 62, 74)
		suit_light = Color8(232, 194, 78) if tier < 2 else Color8(245, 209, 91)
	elif variant == "arena":
		skin = Color8(185, 207, 219)
		hair = Color8(219, 230, 235)
		suit_dark = Color8(27, 47, 73)
		suit_light = Color8(112, 218, 245)
	# Beine liegen hinter dem Rumpf. Ihre zwei Segmente und getrennten Stiefel
	# machen auch bei sechs ECS-Frames die Gewichtsverlagerung lesbar.
	Base.pixel_rect(canvas, Rect2(center + Vector2(leg_a - 1, 0), Vector2(2, 5)), suit_dark)
	Base.pixel_rect(canvas, Rect2(center + Vector2(leg_b - 1, 0), Vector2(2, 5)), suit_dark)
	Base.pixel_rect(canvas, Rect2(center + Vector2(leg_a - 2 + facing, 4), Vector2(4, 2)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(leg_b - 2 + facing, 4), Vector2(4, 2)), Base.INK)
	# Gegenläufige Arme; der vordere Arm erhält Hand bzw. Handschuh.
	Base.pixel_rect(canvas, Rect2(center + Vector2(arm_b - 1, -6), Vector2(2, 6)), suit_dark)
	Base.pixel_rect(canvas, Rect2(center + Vector2(arm_a - 1, -6), Vector2(2, 6)), suit_light)
	Base.pixel_rect(canvas, Rect2(center + Vector2(arm_a - 1, -1), Vector2(2, 2)),
		skin if variant == "gears" else Base.PAPER)
	# Rumpf mit Schulter-, Gürtel- und Variantenmerkmalen.
	Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -8), Vector2(8, 9)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, -7), Vector2(6, 7)), color)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, -1), Vector2(6, 2)), suit_dark)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -6), Vector2(2, 4)), suit_light)
	if variant == "gears":
		Base.pixel_rect(canvas, Rect2(center + Vector2(-4 * facing, -7), Vector2(2, 7)),
			Color8(91, 43, 31)) # Mantelsaum
	elif variant == "lava":
		Base.pixel_rect(canvas, Rect2(center + Vector2(-4 * facing, -7), Vector2(2, 6)), Base.CYAN)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -1), Vector2(4, 1)), Base.AMBER)
	else:
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -5), Vector2(4, 2)), Base.CYAN)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -2), Vector2(1, 3)), Base.VIOLET)
	# Kopf, Haare/Helm und Blickrichtung. Keine Kreise, keine Subpixel.
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, -13), Vector2(6, 5)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -12), Vector2(5, 4)), skin)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, -13), Vector2(6, 2)), hair)
	Base.pixel_rect(canvas, Rect2(center + Vector2(facing * 2, -11), Vector2(1, 1)), Base.INK)
	if variant == "lava":
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -11), Vector2(5, 2)),
			Color8(104, 202, 220))
	elif variant == "arena":
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -11), Vector2(5, 1)), Base.CYAN)
		if tier == 2 and (phase & 1) == 0:
			Base.pixel_rect(canvas, Rect2(center + Vector2(-3 * facing, -9), Vector2(2, 1)),
				Base.VIOLET.lightened(0.18))
static func _draw_platform_span(canvas: CanvasItem, platform: Rect2, variant: String,
		definition: Dictionary, anim: float) -> void:
	var rect := Rect2(platform.position.floor(), platform.size.floor())
	var tier := Base._hardware_tier(definition)
	match variant:
		"lava":
			Base.pixel_rect(canvas, rect, Color8(51, 39, 43))
			Base.pixel_rect(canvas, Rect2(rect.position, Vector2(rect.size.x, 2)), Color8(241, 91, 47))
			Base.pixel_rect(canvas, Rect2(rect.position + Vector2(0, 2),
				Vector2(rect.size.x, 1)), Color8(126, 54, 42))
			for x in range(roundi(rect.position.x) + 4, roundi(rect.end.x), 9):
				var crack_y := roundi(rect.position.y) + 3 + floori(float(x) / 9.0) % 2
				Base.pixel_rect(canvas, Rect2(x, crack_y, 3, 1), Base.INK)
				if tier >= 1 and (floori(float(x) / 9.0) + floori(anim * 4.0)) % 4 == 0:
					Base.pixel_rect(canvas, Rect2(x + 1, rect.end.y - 1, 2, 1), Base.AMBER)
		"arena":
			Base.pixel_rect(canvas, rect, Color8(23, 44, 67))
			Base.pixel_rect(canvas, Rect2(rect.position, Vector2(rect.size.x, 1)), Base.CYAN)
			Base.pixel_rect(canvas, Rect2(rect.position + Vector2(0, 1),
				Vector2(rect.size.x, 1)), Color8(70, 128, 158))
			for x in range(roundi(rect.position.x) + 3, roundi(rect.end.x), 8):
				Base.pixel_rect(canvas, Rect2(x, rect.position.y + 3, 4, 2), Base.INK)
				Base.pixel_rect(canvas, Rect2(x + 1, rect.position.y + 3, 2, 1),
					Base.VIOLET if tier == 2 else Base.STEEL_LIT)
			if tier == 2:
				for x in range(roundi(rect.position.x) + 6, roundi(rect.end.x), 16):
					var glow := Base.CYAN if (floori(anim * 8.0) + floori(float(x) / 8.0)) % 2 == 0 else Base.VIOLET
					Base.pixel_rect(canvas, Rect2(x, rect.end.y - 1, 4, 1), glow)
		_:
			Base.pixel_rect(canvas, rect, Color8(57, 62, 67))
			Base.pixel_rect(canvas, Rect2(rect.position, Vector2(rect.size.x, 1)), Color8(231, 184, 93))
			Base.pixel_rect(canvas, Rect2(rect.position + Vector2(0, 1),
				Vector2(rect.size.x, 1)), Color8(128, 112, 75))
			for x in range(roundi(rect.position.x), roundi(rect.end.x), 8):
				var block_width := mini(7, roundi(rect.end.x) - x)
				Base.pixel_rect(canvas, Rect2(x, rect.position.y + 2, block_width,
					maxf(1.0, rect.size.y - 2)), Color8(49, 55, 61))
				Base.pixel_rect(canvas, Rect2(x + 1, rect.position.y + 3,
					maxi(1, block_width - 2), 1), Color8(83, 87, 83))
				if x + 6 < rect.end.x:
					Base.pixel_rect(canvas, Rect2(x + 6, rect.position.y + 2,
						1, maxf(1.0, rect.size.y - 2)), Base.INK)
				if tier >= 1 and block_width >= 5:
					Base.pixel_rect(canvas, Rect2(x + 2, rect.end.y - 2, 1, 1), Base.AMBER.darkened(0.25))
static func _draw_platform_token(canvas: CanvasItem, p: Vector2, variant: String,
		definition: Dictionary, anim: float) -> void:
	var center := p.floor()
	var tier := Base._hardware_tier(definition)
	if variant == "lava":
		var bob := -1 if floori(anim * (5.0 + tier)) % 4 == 0 else 0
		var q := center + Vector2(0, bob)
		Base.pixel_polygon(canvas, PackedVector2Array([
			q + Vector2(0, -7), q + Vector2(5, -2), q + Vector2(4, 5),
			q + Vector2(0, 7), q + Vector2(-4, 5), q + Vector2(-5, -2),
		]), Color8(38, 98, 123), Base.INK)
		Base.pixel_rect(canvas, Rect2(q + Vector2(-2, -5), Vector2(4, 10)), Base.CYAN)
		Base.pixel_rect(canvas, Rect2(q + Vector2(-1, -4), Vector2(2, 5)), Base.PAPER)
		if tier >= 1:
			Base.pixel_rect(canvas, Rect2(q + Vector2(-7, 0), Vector2(2, 1)), Base.CYAN.darkened(0.15))
			Base.pixel_rect(canvas, Rect2(q + Vector2(6, 0), Vector2(2, 1)), Base.CYAN.darkened(0.15))
	else:
		_draw_gear(canvas, center, Base.AMBER, anim, 0.9)
static func _draw_platform_exit(canvas: CanvasItem, p: Vector2, variant: String,
		definition: Dictionary, anim: float, active: bool) -> void:
	var center := p.floor()
	var a := Base.accent(definition)
	var tier := Base._hardware_tier(definition)
	match variant:
		"lava":
			Base.pixel_rect(canvas, Rect2(center + Vector2(-9, -17), Vector2(18, 32)), Base.INK)
			Base.pixel_rect(canvas, Rect2(center + Vector2(-7, -15), Vector2(14, 28)),
				Color8(62, 67, 69))
			Base.pixel_rect(canvas, Rect2(center + Vector2(-5, -13), Vector2(10, 22)),
				Color8(21, 29, 36))
			for y in range(-11, 9, 4):
				Base.pixel_rect(canvas, Rect2(center + Vector2(-5, y), Vector2(10, 1)),
					Color8(89, 97, 95))
			var status_light := Base.GREEN if active else Base.RED
			Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -14), Vector2(4, 2)), status_light)
			if tier >= 1 and floori(anim * 6.0) % 2 == 0:
				Base.pixel_rect(canvas, Rect2(center + Vector2(-7, 11), Vector2(14, 2)), Base.AMBER)
		_:
			# Zweistufiger Torbogen aus 8px-Steinen mit mechanischem Schloss.
			Base.pixel_rect(canvas, Rect2(center + Vector2(-10, -17), Vector2(20, 32)), Base.INK)
			Base.pixel_rect(canvas, Rect2(center + Vector2(-8, -15), Vector2(16, 30)),
				Color8(70, 64, 58))
			Base.pixel_rect(canvas, Rect2(center + Vector2(-6, -12), Vector2(12, 27)),
				Color8(14, 15, 18))
			Base.pixel_rect(canvas, Rect2(center + Vector2(-7, -15), Vector2(14, 3)),
				Color8(151, 125, 73))
			for y in range(-9, 13, 5):
				Base.pixel_rect(canvas, Rect2(center + Vector2(-8, y), Vector2(2, 3)),
					Color8(119, 96, 61))
				Base.pixel_rect(canvas, Rect2(center + Vector2(6, y), Vector2(2, 3)),
					Color8(119, 96, 61))
			_draw_gear(canvas, center + Vector2(0, -2), Base.GREEN if active else a,
				anim if active else 0.0, 0.65)
			if active and floori(anim * (4.0 + tier)) % 2 == 0:
				Base.pixel_rect(canvas, Rect2(center + Vector2(-4, 10), Vector2(8, 2)), Base.PAPER)
static func _draw_arena_ball(canvas: CanvasItem, center: Vector2, anim: float,
		definition: Dictionary) -> void:
	var p := center.floor()
	var tier := Base._hardware_tier(definition)
	Base._pixel_disc(canvas, p, 4, Color8(50, 81, 112), Base.CYAN)
	var frame := floori(anim * 12.0) % 4
	if frame % 2 == 0:
		Base.pixel_rect(canvas, Rect2(p + Vector2(-1, -4), Vector2(2, 9)), Base.PAPER)
		Base.pixel_rect(canvas, Rect2(p + Vector2(-4, -1), Vector2(9, 2)), Base.VIOLET)
	else:
		Base.pixel_rect(canvas, Rect2(p + Vector2(-3, -3), Vector2(2, 2)), Base.PAPER)
		Base.pixel_rect(canvas, Rect2(p + Vector2(2, 2), Vector2(2, 2)), Base.VIOLET)
		Base.pixel_rect(canvas, Rect2(p + Vector2(-2, 1), Vector2(4, 2)), Base.CYAN)
	if tier == 2:
		var spark_x := -7 if frame < 2 else 6
		Base.pixel_rect(canvas, Rect2(p + Vector2(spark_x, 0), Vector2(2, 1)), Base.CYAN)
static func _draw_crystal_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float, scale := 1.0) -> void:
	var center := p.floor()
	var lift := sin(anim * 4.0 + center.x * 0.1) * 1.0
	var half := maxf(3.0, 5.0 * scale)
	Base.pixel_polygon(canvas, PackedVector2Array([
		center + Vector2(0, -half + lift), center + Vector2(half, lift),
		center + Vector2(0, half + lift), center + Vector2(-half, lift),
	]), color)
	canvas.draw_line(center + Vector2(0, -half + 1 + lift),
		center + Vector2(0, half - 1 + lift), color.lightened(0.38), 1)
	canvas.draw_line(center + Vector2(-half + 1, lift), center + Vector2(0, lift), Base.PAPER, 1)
static func _draw_miner_rover(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float, variant: String) -> void:
	var center := p.floor()
	Base.pixel_rect(canvas, Rect2(center + Vector2(-7, -4), Vector2(12, 8)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-6, -3), Vector2(10, 6)), color)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, -6), Vector2(6, 3)),
		Color8(104, 211, 230))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-7, 4), Vector2(12, 2)), Base.STEEL_LIT)
	for x in [-5, 0, 5]:
		Base.pixel_rect(canvas, Rect2(center + Vector2(x - 1, 5), Vector2(3, 2)), Base.INK)
	var drill := 2 + floori(anim * 8.0) % 2
	Base.pixel_polygon(canvas, PackedVector2Array([
		center + Vector2(5, -2), center + Vector2(9 + drill, 0), center + Vector2(5, 2),
	]), Base.PAPER)
	if variant == "magma":
		Base.pixel_rect(canvas, Rect2(center + Vector2(-5, -2), Vector2(2, 2)), Base.CYAN)
static func _draw_survivor_sprite(canvas: CanvasItem, p: Vector2, anim: float,
		ice := false) -> void:
	var center := p.floor()
	var bob := floori(sin(anim * 3.0 + center.x) * 1.2)
	var suit := Color8(239, 163, 42) if not ice else Color8(218, 228, 234)
	Base._pixel_disc(canvas, center + Vector2(0, -4 + bob), 2, Color8(225, 177, 125),
		Color8(244, 206, 158))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, -1 + bob), Vector2(6, 7)), suit)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-5, 1 + bob), Vector2(2, 5)), Base.PAPER)
	Base.pixel_rect(canvas, Rect2(center + Vector2(3, 1 + bob), Vector2(2, 5)), Base.PAPER)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, 6 + bob), Vector2(2, 4)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(1, 6 + bob), Vector2(2, 4)), Base.INK)
static func _draw_rescue_craft(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float, ice := false) -> void:
	var center := p.floor()
	if ice:
		Base.pixel_polygon(canvas, PackedVector2Array([
			center + Vector2(-12, 3), center + Vector2(-8, -4), center + Vector2(7, -4),
			center + Vector2(12, 2), center + Vector2(8, 6), center + Vector2(-9, 6),
		]), color)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -8), Vector2(8, 4)), Base.PAPER)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -7), Vector2(5, 2)), Base.CYAN.darkened(0.25))
		Base.pixel_rect(canvas, Rect2(center + Vector2(-10, 7), Vector2(20, 2)), Base.INK)
	else:
		Base.pixel_polygon(canvas, PackedVector2Array([
			center + Vector2(-12, -4), center + Vector2(7, -4), center + Vector2(13, 0),
			center + Vector2(7, 5), center + Vector2(-12, 5), center + Vector2(-15, 0),
		]), color)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -8), Vector2(9, 4)), color.lightened(0.25))
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -7), Vector2(5, 2)), Base.CYAN)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-13, -1), Vector2(4, 2)), Base.PAPER)
		var propeller_span := 3 + floori(anim * 7.0) % 2
		Base.pixel_rect(canvas, Rect2(center + Vector2(-16, -propeller_span),
			Vector2(1, propeller_span * 2 + 1)), Base.STEEL_LIT)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-16 - propeller_span, 0),
			Vector2(propeller_span * 2 + 1, 1)), Base.STEEL_LIT)
static func _draw_hazard_sprite(canvas: CanvasItem, p: Vector2, radius: float,
		color: Color, ice := false) -> void:
	var center := p.floor()
	var r := roundi(radius)
	if ice:
		Base.pixel_polygon(canvas, PackedVector2Array([
			center + Vector2(-r, 2), center + Vector2(-float(r) / 2.0, -r), center + Vector2(2, -float(r) / 2.0),
			center + Vector2(r, -2), center + Vector2(float(r) / 2.0, r), center + Vector2(-float(r) / 2.0, float(r) / 2.0),
		]), Color8(127, 176, 202), Color8(213, 234, 239))
	else:
		Base.pixel_polygon(canvas, PackedVector2Array([
			center + Vector2(-r, -2), center + Vector2(-float(r) / 2.0, -r), center + Vector2(float(r) / 3.0, -r + 2),
			center + Vector2(r, -float(r) / 4.0), center + Vector2(r - 2, r), center + Vector2(-float(r) / 2.0, r - 1),
		]), color.darkened(0.35), color)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -3), Vector2(3, 2)), color.lightened(0.18))
static func _draw_agent_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float) -> void:
	var center := p.floor()
	var step := -1 if floori(anim * 7.0) % 2 == 0 else 1
	Base._pixel_disc(canvas, center + Vector2(0, -4), 2, Color8(213, 167, 121),
		Color8(238, 199, 151))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, -2), Vector2(6, 7)), color)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -3), Vector2(8, 2)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3 + step, 5), Vector2(2, 3)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(1 - step, 5), Vector2(2, 3)), Base.INK)
static func _draw_guard_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		axis: int, direction: int, anim: float) -> void:
	var center := p.floor()
	var facing := Vector2(direction, 0) if axis == 0 else Vector2(0, direction)
	var side := Vector2(-facing.y, facing.x)
	var cone := PackedVector2Array([
		center + facing * 5.0, center + facing * 55.0 + side * 17.0,
		center + facing * 55.0 - side * 17.0,
	])
	# Ein echter Amiga-Sichtkegel: dunkle Vollfläche plus geordnetes Dither,
	# keine moderne halbtransparente Vektorfläche.
	canvas.draw_colored_polygon(cone, color.darkened(0.82))
	for distance_step in range(12, 54, 8):
		var scan_center := center + facing * float(distance_step)
		var half_width := maxi(1, floori(float(distance_step) * 0.28))
		for side_offset in range(-half_width, half_width + 1, 4):
			Base.pixel_rect(canvas, Rect2((scan_center + side * float(side_offset)).floor(),
				Vector2(1, 1)), color.darkened(0.42))
	canvas.draw_line(center + facing * 4.0, center + facing * 55.0,
		color.darkened(0.25), 1)
	Base._pixel_disc(canvas, center + Vector2(0, -3), 2, Color8(223, 170, 124),
		Color8(242, 204, 158))
	Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -1), Vector2(8, 7)), Base.INK)
	Base.pixel_rect(canvas, Rect2(center + Vector2(-3, 0), Vector2(6, 5)), color)
	var lamp := Base.PAPER if floori(anim * 5.0) % 2 == 0 else color.lightened(0.2)
	Base.pixel_rect(canvas, Rect2(center + facing * 4.0 - Vector2.ONE, Vector2(2, 2)), lamp)
static func _draw_vehicle_sprite(canvas: CanvasItem, p: Vector2, color: Color,
		anim: float, bike := false) -> void:
	var center := p.floor()
	if bike:
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -11), Vector2(5, 8)), color)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-5, -4), Vector2(11, 10)), Base.INK)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-4, -3), Vector2(9, 8)), color.lightened(0.1))
		Base.pixel_rect(canvas, Rect2(center + Vector2(-2, -9), Vector2(5, 3)), Base.CYAN.darkened(0.2))
		Base.pixel_rect(canvas, Rect2(center + Vector2(-3, 6), Vector2(7, 3)), Base.INK)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-1, 5), Vector2(3, 2)), Base.RED)
	else:
		Base.pixel_polygon(canvas, PackedVector2Array([
			center + Vector2(-11, 8), center + Vector2(-8, -6), center + Vector2(-4, -11),
			center + Vector2(5, -11), center + Vector2(9, -6), center + Vector2(12, 8),
		]), color)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-5, -8), Vector2(10, 6)), Base.CYAN.darkened(0.45))
		Base.pixel_rect(canvas, Rect2(center + Vector2(-9, 5), Vector2(5, 3)), Base.RED)
		Base.pixel_rect(canvas, Rect2(center + Vector2(5, 5), Vector2(5, 3)), Base.RED)
		Base.pixel_rect(canvas, Rect2(center + Vector2(-12, 1), Vector2(3, 7)), Base.INK)
		Base.pixel_rect(canvas, Rect2(center + Vector2(10, 1), Vector2(3, 7)), Base.INK)
	if floori(anim * 12.0) % 2 == 0:
		Base.pixel_rect(canvas, Rect2(center + Vector2(-1, 9), Vector2(3, 2)), Base.AMBER)
