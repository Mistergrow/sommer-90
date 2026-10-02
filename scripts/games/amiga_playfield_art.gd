class_name AmigaPlayfieldArt
extends RefCounted
## OCS-/ECS-/AGA-artige Laufzeitkulissen fuer die Stefan-Anthologie.
##
## Die Titelillustrationen duerfen wie klassische Box-/Loading-Art aussehen.
## Im eigentlichen Spiel gelten dagegen feste 320x200-Pixel, opake Paletten,
## 8/16-Pixel-Tiles und ganzzahlige Blitterkoordinaten. Jede Spielart erhaelt
## ihre eigene Bildsprache; gemeinsam ist nur die emulierte Hardwaretechnik.

const WIDTH := 320
const HEIGHT := 200
const PLAY_TOP := 22

# Gemeinsame Grundbank. OCS-Titel verwenden daraus hoechstens 32 Register,
# ECS-Titel zusaetzliche Copper-Baender und AGA-Titel weitere Schattierungen.
# Die Bank ist bewusst zentral, damit kein Spiel unbemerkt in HD-Farben kippt.
const BLACK := Color8(2, 4, 8)
const INK := Color8(5, 9, 16)
const NAVY_0 := Color8(8, 13, 27)
const NAVY_1 := Color8(13, 22, 42)
const NAVY_2 := Color8(22, 35, 58)
const SLATE_0 := Color8(28, 35, 47)
const SLATE_1 := Color8(43, 52, 63)
const SLATE_2 := Color8(66, 75, 82)
const GREY := Color8(101, 105, 102)
const SILVER := Color8(153, 157, 148)
const PAPER := Color8(224, 220, 191)
const WHITE := Color8(239, 238, 218)
const BROWN_0 := Color8(37, 24, 22)
const BROWN_1 := Color8(67, 39, 31)
const BROWN_2 := Color8(105, 63, 39)
const COPPER := Color8(154, 88, 43)
const GOLD_0 := Color8(173, 111, 37)
const GOLD_1 := Color8(229, 166, 55)
const ORANGE := Color8(232, 102, 38)
const RED_0 := Color8(112, 31, 37)
const RED_1 := Color8(199, 54, 49)
const GREEN_0 := Color8(20, 67, 48)
const GREEN_1 := Color8(42, 128, 75)
const GREEN_2 := Color8(91, 196, 103)
const TEAL_0 := Color8(13, 61, 70)
const TEAL_1 := Color8(36, 126, 131)
const CYAN := Color8(77, 207, 211)
const BLUE := Color8(49, 92, 169)
const ICE := Color8(139, 200, 213)
const VIOLET_0 := Color8(49, 29, 75)
const VIOLET_1 := Color8(111, 61, 144)
const MAGENTA := Color8(194, 69, 152)

const SUPPORTED_MODES := [
	"shooter", "platform", "circuit", "miner", "rescue",
	"stealth", "racer", "strategy", "rhythm",
]
const SUPPORTED_VARIANTS := [
	"courier", "gears", "signal", "crystal", "submarine", "laser", "bike",
	"clockwork", "trade", "defense", "reactor", "tactics", "lava", "fighter",
	"runes", "network", "ice", "colony", "arena", "magma", "traffic",
	"tunnel", "squad", "finale", "millennium", "exodus",
]

enum Chipset {
	OCS,
	ECS,
	AGA,
}


static func draw(canvas: CanvasItem, definition: Dictionary, anim: float) -> void:
	var mode := str(definition.get("mode", ""))
	var variant := str(definition.get("variant", ""))
	var software_id := str(definition.get("software_id", ""))
	var chipset := chipset_for(definition)
	match mode:
		"shooter": _draw_space(canvas, variant, software_id, anim, chipset)
		"platform": _draw_platform_world(canvas, variant, anim, chipset)
		"circuit": _draw_circuit_bed(canvas, variant, anim, chipset)
		"miner": _draw_mine(canvas, variant, anim, chipset)
		"rescue": _draw_rescue_field(canvas, variant, anim, chipset)
		"stealth": _draw_facility(canvas, variant, anim, chipset)
		"racer": _draw_racer_horizon(canvas, variant, anim, chipset)
		"strategy": _draw_command_world(canvas, variant, software_id, anim, chipset)
		"rhythm": _draw_pulse_world(canvas, variant, anim, chipset)
		_: canvas.draw_rect(Rect2(0, 0, WIDTH, HEIGHT), INK)


static func profile_contract(definition: Dictionary) -> Dictionary:
	var mode := str(definition.get("mode", ""))
	var variant := str(definition.get("variant", ""))
	var chipset := chipset_for(definition)
	return {
		"resolution": Vector2i(WIDTH, HEIGHT),
		"mode": mode,
		"variant": variant,
		"supported": mode in SUPPORTED_MODES and variant in SUPPORTED_VARIANTS,
		"chipset": chipset_name(chipset),
		"indexed_palette_limit": 32 if chipset < Chipset.AGA else 64,
		"sprite_animation_phases": 4 if chipset == Chipset.OCS else (
			6 if chipset == Chipset.ECS else 8),
		"parallax_planes": 1 if chipset == Chipset.OCS else (
			2 if chipset == Chipset.ECS else 3),
		"tile_grid": 8,
		"subpixel_rendering": false,
		"runtime_atlas_background": false,
	}


static func chipset_for(definition: Dictionary) -> Chipset:
	var explicit := str(definition.get("chipset", "")).to_upper()
	if explicit == "AGA":
		return Chipset.AGA
	if explicit == "ECS":
		return Chipset.ECS
	if explicit == "OCS":
		return Chipset.OCS
	var year := int(definition.get("year", 1991))
	if year >= 1996:
		return Chipset.AGA
	if year >= 1993:
		return Chipset.ECS
	return Chipset.OCS


static func chipset_name(chipset: Chipset) -> String:
	match chipset:
		Chipset.AGA:
			return "AGA"
		Chipset.ECS:
			return "ECS"
		_:
			return "OCS"


static func _draw_space(canvas: CanvasItem, variant: String, software_id: String,
		anim: float, chipset: Chipset) -> void:
	var bands := [NAVY_0, NAVY_1, VIOLET_0, NAVY_1]
	if variant == "fighter":
		bands = [BLACK, NAVY_0, RED_0, NAVY_0]
	elif variant == "finale":
		bands = [BLACK, VIOLET_0, NAVY_2, RED_0]
	_copper_bands(canvas, bands, PLAY_TOP, HEIGHT)
	var drift := floori(anim * (9.0 if variant == "courier" else 17.0))
	_stars(canvas, drift, 47 if variant == "finale" else 31,
		GOLD_1 if variant == "finale" else PAPER)
	if variant == "courier":
		_pixel_disc(canvas, Vector2i(262, 58), 24, BLUE, TEAL_1)
		_dither_rect(canvas, Rect2i(239, 45, 45, 19), BLUE, ICE, 3)
		# Poststation und Zielbake.
		canvas.draw_rect(Rect2(272, 101, 38, 28), SLATE_0)
		canvas.draw_rect(Rect2(276, 105, 30, 20), SLATE_2)
		for x in range(279, 305, 6):
			canvas.draw_rect(Rect2(x, 109, 3, 3), CYAN)
	elif variant == "fighter":
		# Drahtgitter und roter Kommandoplanet.
		_pixel_disc(canvas, Vector2i(264, 71), 31, RED_0, RED_1)
		for y in range(112, 196, 9):
			canvas.draw_line(Vector2(0, y), Vector2(320, y), TEAL_0, 1)
		for x in range(-100, 421, 20):
			canvas.draw_line(Vector2(160, 100), Vector2(x, 200), TEAL_0, 1)
	else:
		_pixel_disc(canvas, Vector2i(250, 64), 38, VIOLET_0, MAGENTA)
		for i in 7:
			var y := 47 + i * 7
			canvas.draw_line(Vector2(220, y), Vector2(285, y + 4), RED_1, 1)
		var seed_shift := software_id.length() % 9
		for x in range(12 + seed_shift, 310, 29):
			canvas.draw_rect(Rect2(x, 156 + (x % 3), 12, 3), SLATE_2)
	if chipset >= Chipset.ECS:
		_draw_parallax_stars(canvas, anim, 1)
	if chipset == Chipset.AGA:
		_draw_parallax_stars(canvas, anim, 2)


static func _draw_platform_world(canvas: CanvasItem, variant: String, anim: float,
		chipset: Chipset) -> void:
	match variant:
		"gears": _draw_clockwork_keep(canvas, anim, chipset)
		"lava": _draw_lava_cavern(canvas, anim, chipset)
		"arena": _draw_cyber_arena(canvas, anim, chipset)
		_: canvas.draw_rect(Rect2(0, PLAY_TOP, WIDTH, HEIGHT - PLAY_TOP), NAVY_0)


static func _draw_clockwork_keep(canvas: CanvasItem, anim: float, chipset: Chipset) -> void:
	_copper_bands(canvas, [NAVY_0, VIOLET_0, NAVY_1, BROWN_0], PLAY_TOP, 181)
	_pixel_disc(canvas, Vector2i(51, 45), 19, SLATE_2, SILVER)
	# Ferne Burgsilhouette: klare 8-Pixel-Tiles statt gemaltem Hintergrund.
	var skyline := PackedVector2Array([
		Vector2(0, 146), Vector2(0, 103), Vector2(13, 103), Vector2(13, 80),
		Vector2(21, 72), Vector2(29, 80), Vector2(29, 119), Vector2(46, 119),
		Vector2(46, 90), Vector2(55, 82), Vector2(64, 90), Vector2(64, 127),
		Vector2(82, 127), Vector2(82, 72), Vector2(91, 60), Vector2(100, 72),
		Vector2(100, 119), Vector2(121, 119), Vector2(121, 96), Vector2(130, 87),
		Vector2(139, 96), Vector2(139, 146),
	])
	canvas.draw_colored_polygon(skyline, NAVY_2)
	for x in range(6, 140, 13):
		canvas.draw_rect(Rect2(x, 118 - (x % 4) * 7, 3, 5), GOLD_0)
	# Nahe gemauerte Maschinenwand rechts.
	canvas.draw_rect(Rect2(174, 33, 146, 148), BROWN_0)
	for y in range(35, 181, 8):
		for x in range(176, 320, 16):
			var offset := 8 if floori(float(y) / 8.0) % 2 else 0
			canvas.draw_rect(Rect2(x + offset, y, 14, 6), BROWN_1)
			canvas.draw_line(Vector2(x + offset, y), Vector2(x + offset + 13, y),
				BROWN_2, 1)
	_pixel_gear(canvas, Vector2i(239, 76), 26, BROWN_2, GOLD_0, floori(anim * 2.0))
	_pixel_gear(canvas, Vector2i(287, 134), 34, BROWN_1, COPPER, -floori(anim * 2.0))
	_pixel_gear(canvas, Vector2i(213, 151), 18, BROWN_2, GOLD_1, floori(anim * 3.0))
	# Untere Bruecke und Zinnen als Teil der Kulisse.
	canvas.draw_rect(Rect2(0, 170, 320, 30), BROWN_0)
	for x in range(0, 320, 16):
		canvas.draw_rect(Rect2(x, 171, 15, 7), SLATE_0)
		canvas.draw_rect(Rect2(x + 2, 172, 11, 2), SLATE_2)
	if chipset >= Chipset.ECS:
		var cloud_shift := posmod(floori(anim * 2.0), 128)
		for x in range(-128 + cloud_shift, 384, 64):
			canvas.draw_rect(Rect2(x, 51, 31, 2), VIOLET_1)
			canvas.draw_rect(Rect2(x + 8, 49, 14, 2), NAVY_2)
	if chipset == Chipset.AGA:
		_dither_rect(canvas, Rect2i(0, 148, 174, 20), BROWN_0, VIOLET_0, 2)


static func _draw_lava_cavern(canvas: CanvasItem, anim: float, chipset: Chipset) -> void:
	_copper_bands(canvas, [BLACK, BROWN_0, RED_0, BROWN_1], PLAY_TOP, 181)
	for x in range(0, 320, 16):
		var ceiling := 29 + (x * 7 % 24)
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(x, PLAY_TOP), Vector2(x + 15, PLAY_TOP),
			Vector2(x + 11, ceiling + 18), Vector2(x + 7, ceiling),
			Vector2(x + 3, ceiling + 14),
		]), SLATE_0)
	for y in range(60, 176, 16):
		for x in range(floori(float(y) / 16.0) % 2 * 8, 320, 16):
			canvas.draw_rect(Rect2(x, y, 14, 7), BROWN_1)
			if (x + y) % 48 == 0:
				canvas.draw_rect(Rect2(x + 4, y + 2, 4, 2), RED_1)
	var wave := floori(anim * 7.0) % 8
	canvas.draw_rect(Rect2(0, 181, 320, 19), RED_0)
	for x in range(-8, 328, 8):
		var y := 183 + floori(float(x + wave) / 8.0) % 2
		canvas.draw_rect(Rect2(x + wave, y, 7, 4), ORANGE)
		canvas.draw_rect(Rect2(x + wave + 2, y, 3, 1), GOLD_1)
	if chipset >= Chipset.ECS:
		for i in 11:
			var px := posmod(i * 43 + floori(anim * (5.0 + i % 3)), 320)
			var py := 178 - posmod(i * 19 + floori(anim * 13.0), 89)
			canvas.draw_rect(Rect2(px, py, 2, 2), ORANGE)
	if chipset == Chipset.AGA:
		_dither_rect(canvas, Rect2i(0, 163, 320, 18), RED_0, BROWN_1, 3)


static func _draw_cyber_arena(canvas: CanvasItem, anim: float, chipset: Chipset) -> void:
	_copper_bands(canvas, [NAVY_0, NAVY_2, TEAL_0, VIOLET_0], PLAY_TOP, HEIGHT)
	canvas.draw_rect(Rect2(0, 35, 320, 49), SLATE_0)
	for row in 4:
		for x in range(3 + (row % 2) * 4, 318, 8):
			var c := CYAN if (x + row * 7 + floori(anim * 4.0)) % 23 == 0 else SLATE_2
			canvas.draw_rect(Rect2(x, 41 + row * 10, 3, 3), c)
	canvas.draw_line(Vector2(0, 87), Vector2(320, 87), CYAN, 2)
	for x in range(0, 321, 16):
		canvas.draw_line(Vector2(160, 87), Vector2(x, 200), TEAL_1, 1)
	for y in range(97, 200, 12):
		canvas.draw_line(Vector2(0, y), Vector2(320, y), TEAL_0, 1)
	canvas.draw_rect(Rect2(4, 93, 10, 77), BLUE)
	canvas.draw_rect(Rect2(306, 93, 10, 77), RED_1)
	if chipset == Chipset.AGA:
		for x in range(22, 302, 28):
			var pulse := (x + floori(anim * 12.0)) % 31
			canvas.draw_rect(Rect2(x, 91 + pulse % 3, 9, 2), MAGENTA)


static func _draw_circuit_bed(canvas: CanvasItem, variant: String, anim: float,
		chipset: Chipset) -> void:
	var base := TEAL_0
	var trace := TEAL_1
	var node := CYAN
	if variant == "clockwork":
		base = BROWN_0; trace = BROWN_2; node = GOLD_1
	elif variant == "runes":
		base = NAVY_2; trace = BLUE; node = ICE
	elif variant == "millennium":
		base = VIOLET_0; trace = MAGENTA; node = GREEN_2
	canvas.draw_rect(Rect2(0, PLAY_TOP, WIDTH, HEIGHT - PLAY_TOP), base)
	for y in range(26, 198, 8):
		for x in range(floori(float(y) / 8.0) % 2 * 4, 320, 8):
			if (x * 3 + y * 5) % 7 < 3:
				canvas.draw_rect(Rect2(x, y, 3, 1), trace)
	for i in 18:
		var x := 7 + (i * 47) % 307
		var y := 27 + (i * 31) % 166
		canvas.draw_rect(Rect2(x, y, 4, 4), INK)
		canvas.draw_rect(Rect2(x + 1, y + 1, 2, 2),
			PAPER if (i + floori(anim * 3.0)) % 7 == 0 else node)
	if chipset == Chipset.AGA:
		for y in range(29, 195, 16):
			canvas.draw_line(Vector2(0, y), Vector2(320, y), Color(node, 0.22), 1)


static func _draw_mine(canvas: CanvasItem, variant: String, anim: float,
		chipset: Chipset) -> void:
	var rock_a := BROWN_1 if variant == "magma" else VIOLET_0
	var rock_b := COPPER if variant == "magma" else VIOLET_1
	canvas.draw_rect(Rect2(0, PLAY_TOP, WIDTH, HEIGHT - PLAY_TOP), BLACK)
	for y in range(PLAY_TOP, HEIGHT, 8):
		for x in range(0, WIDTH, 8):
			if (x * 5 + y * 3) % 29 < 17:
				canvas.draw_rect(Rect2(x, y, 8, 8), rock_a)
				canvas.draw_rect(Rect2(x + 1, y + 1, 5, 1), rock_b)
				if (x + y) % 40 == 0:
					canvas.draw_rect(Rect2(x + 5, y + 4, 2, 2),
						ORANGE if variant == "magma" else VIOLET_1)
	if chipset >= Chipset.ECS:
		for i in 14:
			var px := 6 + (i * 67) % 307
			var py := 27 + (i * 37) % 166
			var sparkle := (i + floori(anim * 5.0)) % 4 == 0
			canvas.draw_rect(Rect2(px, py, 2 if sparkle else 1, 2 if sparkle else 1),
				GOLD_1 if variant == "magma" else ICE)
	if chipset == Chipset.AGA:
		for y in range(29, 197, 16):
			canvas.draw_line(Vector2(0, y), Vector2(320, y),
				Color(COPPER if variant == "magma" else VIOLET_1, 0.24), 1)


static func _draw_rescue_field(canvas: CanvasItem, variant: String, anim: float,
		chipset: Chipset) -> void:
	if variant == "ice":
		_copper_bands(canvas, [NAVY_1, BLUE, TEAL_1, ICE], PLAY_TOP, HEIGHT)
		for x in range(0, 320, 24):
			var drift := posmod(x + floori(anim * 8.0), 344) - 24
			canvas.draw_line(Vector2(drift, 25), Vector2(drift - 36, 190), PAPER, 1)
		for x in range(0, 320, 40):
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(x, 200), Vector2(x + 19, 149 - x % 17),
				Vector2(x + 38, 200),
			]), ICE)
	else:
		_copper_bands(canvas, [NAVY_0, TEAL_0, BLUE, NAVY_1], PLAY_TOP, HEIGHT)
		for y in range(36, 194, 12):
			var shift := posmod(floori(anim * (3.0 + y * 0.01)), 12)
			for x in range(-12 + shift, 320, 24):
				canvas.draw_rect(Rect2(x, y, 12, 1), TEAL_1)
		for x in range(12, 320, 37):
			canvas.draw_rect(Rect2(x, 176 - x % 27, 3, 12 + x % 16), NAVY_2)
	if chipset >= Chipset.ECS:
		for i in 10:
			var px := posmod(i * 47 + floori(anim * (4.0 + i % 2)), 320)
			var py := 31 + (i * 29) % 156
			canvas.draw_rect(Rect2(px, py, 2, 1), PAPER if variant == "ice" else CYAN)
	if chipset == Chipset.AGA:
		for band in 5:
			var points := PackedVector2Array()
			for x in range(0, 321, 16):
				points.append(Vector2(x,
					42 + band * 31 + floori(sin(anim + x * 0.08 + band) * 2.0)))
			canvas.draw_polyline(points, Color(ICE, 0.28), 1, false)


static func _draw_facility(canvas: CanvasItem, variant: String, anim: float,
		chipset: Chipset) -> void:
	var floor_a := NAVY_1
	var floor_b := NAVY_2
	var conduit := TEAL_1
	if variant == "laser":
		conduit = RED_0
	elif variant == "squad":
		floor_a = SLATE_0; floor_b = SLATE_1; conduit = GOLD_0
	canvas.draw_rect(Rect2(0, PLAY_TOP, WIDTH, HEIGHT - PLAY_TOP), floor_a)
	for y in range(PLAY_TOP, HEIGHT, 16):
		for x in range(0, WIDTH, 16):
			var checker := (floori(float(x) / 16.0) + floori(float(y) / 16.0)) % 2
			canvas.draw_rect(Rect2(x + 1, y + 1, 14, 14),
				floor_b if checker else floor_a)
			canvas.draw_line(Vector2(x + 2, y + 3), Vector2(x + 10, y + 3),
				conduit, 1)
	for x in range(8, 320, 48):
		canvas.draw_rect(Rect2(x, 25, 2, 171), conduit)
	if chipset >= Chipset.ECS:
		var sweep := posmod(floori(anim * 17.0), 320)
		canvas.draw_rect(Rect2(sweep, PLAY_TOP, 2, HEIGHT - PLAY_TOP), conduit)
	if chipset == Chipset.AGA:
		for i in 7:
			var px := 19 + (i * 61) % 292
			var py := 31 + (i * 43) % 151
			canvas.draw_rect(Rect2(px, py, 8, 3), MAGENTA if variant == "network" else GOLD_1)


static func _draw_racer_horizon(canvas: CanvasItem, variant: String, anim: float,
		chipset: Chipset) -> void:
	var bands := [NAVY_0, VIOLET_0, RED_0, NAVY_2]
	if variant == "traffic":
		bands = [BLACK, NAVY_1, TEAL_0, SLATE_0]
	_copper_bands(canvas, bands, PLAY_TOP, HEIGHT)
	_stars(canvas, floori(anim * 6.0), 17, PAPER)
	if chipset >= Chipset.ECS:
		var far_phase := floori(anim * 3.0)
		for x in range(-32, 352, 32):
			var px := posmod(x - far_phase, 352) - 16
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(px, 113), Vector2(px + 16, 94 + x % 13),
				Vector2(px + 32, 113),
			]), NAVY_2)
	if chipset == Chipset.AGA:
		for y in range(116, 196, 8):
			var shade := SLATE_1 if floori(float(y) / 8.0) % 2 else SLATE_0
			canvas.draw_rect(Rect2(0, y, 320, 4), shade)


static func _draw_command_world(canvas: CanvasItem, variant: String, software_id: String,
		anim: float, chipset: Chipset) -> void:
	var base := NAVY_0
	var grid := TEAL_0
	if variant == "trade":
		base = NAVY_1; grid = BLUE
	elif variant == "tactics":
		base = BROWN_0; grid = COPPER
	elif variant == "colony":
		base = RED_0; grid = GOLD_0
	elif variant == "exodus":
		base = VIOLET_0; grid = MAGENTA
	canvas.draw_rect(Rect2(0, PLAY_TOP, WIDTH, HEIGHT - PLAY_TOP), base)
	for x in range(0, 321, 16):
		canvas.draw_line(Vector2(x, PLAY_TOP), Vector2(x, HEIGHT), grid, 1)
	for y in range(PLAY_TOP, HEIGHT, 12):
		canvas.draw_line(Vector2(0, y), Vector2(WIDTH, y), grid, 1)
	var layout_seed := software_id.length() + int(
		software_id.unicode_at(0) if not software_id.is_empty() else 0)
	for i in 12:
		var x := 5 + (i * 53 + layout_seed) % 306
		var y := 27 + (i * 37 + layout_seed * 3) % 163
		canvas.draw_rect(Rect2(x, y, 5, 3),
			GREEN_2 if (i + floori(anim * 2.0)) % 5 else GOLD_1)
	if chipset == Chipset.AGA:
		for i in 8:
			var x := 9 + (i * 79 + layout_seed * 2) % 300
			var y := 30 + (i * 43 + layout_seed) % 158
			canvas.draw_rect(Rect2(x, y, 2, 7), CYAN)
			canvas.draw_rect(Rect2(x - 2, y + 2, 6, 2), BLUE)


static func _draw_pulse_world(canvas: CanvasItem, variant: String, anim: float,
		chipset: Chipset) -> void:
	var bands := [BLACK, NAVY_0, VIOLET_0, TEAL_0]
	if variant == "reactor":
		bands = [BLACK, GREEN_0, TEAL_0, NAVY_0]
	_copper_bands(canvas, bands, PLAY_TOP, HEIGHT)
	var center := Vector2(160, 111)
	for ring in 6:
		var radius := 15 + ring * 18 + floori(fmod(anim * (4.0 + ring), 9.0))
		_pixel_ring(canvas, center, radius, CYAN if ring % 2 == 0 else MAGENTA)
	for x in range(12, 320, 24):
		canvas.draw_line(Vector2(x, PLAY_TOP), center, TEAL_1, 1)
	if chipset >= Chipset.ECS:
		for x in range(0, 320, 8):
			var height := 2 + posmod(x * 3 + floori(anim * 24.0), 25)
			canvas.draw_rect(Rect2(x, 198 - height, 5, height), VIOLET_1)
	if chipset == Chipset.AGA:
		_pixel_ring(canvas, center, 74 + floori(sin(anim * 2.0) * 3.0), GOLD_1)


static func _copper_bands(canvas: CanvasItem, colors: Array, top: int, bottom: int) -> void:
	var height := maxi(1, bottom - top)
	var band_height := ceili(float(height) / float(maxi(1, colors.size())))
	for i in colors.size():
		canvas.draw_rect(Rect2(0, top + i * band_height, WIDTH,
			mini(band_height, bottom - (top + i * band_height))), colors[i])


static func _stars(canvas: CanvasItem, drift: int, count: int, color: Color) -> void:
	for i in count:
		var x := posmod(i * 73 - drift * (1 + i % 3), WIDTH)
		var y := PLAY_TOP + posmod(i * 41, HEIGHT - PLAY_TOP - 4)
		canvas.draw_rect(Rect2(x, y, 1 + int(i % 11 == 0), 1), color)


static func _draw_parallax_stars(canvas: CanvasItem, anim: float, plane: int) -> void:
	var speed := 4.0 + float(plane * 7)
	var color := SLATE_2 if plane == 1 else VIOLET_1
	for i in range(9 + plane * 3):
		var x := posmod(i * (61 + plane * 8) - floori(anim * speed), WIDTH)
		var y := 28 + posmod(i * (37 + plane * 3), 143)
		canvas.draw_rect(Rect2(x, y, plane, 1), color)


static func _dither_rect(canvas: CanvasItem, rect: Rect2i, base: Color, light: Color,
		step: int) -> void:
	canvas.draw_rect(rect, base)
	for y in range(rect.position.y, rect.end.y, step):
		for x in range(rect.position.x + (y % (step * 2)), rect.end.x, step * 2):
			canvas.draw_rect(Rect2(x, y, 1, 1), light)


static func _pixel_disc(canvas: CanvasItem, center: Vector2i, radius: int,
		dark: Color, light: Color) -> void:
	for y in range(-radius, radius + 1):
		var half := floori(sqrt(float(radius * radius - y * y)))
		canvas.draw_rect(Rect2(center.x - half, center.y + y, half * 2 + 1, 1), dark)
		if y < 0:
			@warning_ignore("integer_division")
			var lit_half := maxi(0, half - radius / 3)
			canvas.draw_rect(Rect2(center.x - half + 2, center.y + y, lit_half, 1), light)


static func _pixel_ring(canvas: CanvasItem, center: Vector2, radius: int, color: Color) -> void:
	for angle_index in 32:
		var angle := float(angle_index) * TAU / 32.0
		var point := (center + Vector2.from_angle(angle) * radius).floor()
		canvas.draw_rect(Rect2(point, Vector2(2, 2)), color)


static func _pixel_gear(canvas: CanvasItem, center: Vector2i, radius: int,
		dark: Color, light: Color, phase: int) -> void:
	# Oktagon mit eckigen Zaehnen: keine glatte Godot-Kreisgrafik.
	var points := PackedVector2Array([
		Vector2(center.x - radius + 5, center.y - radius),
		Vector2(center.x + radius - 5, center.y - radius),
		Vector2(center.x + radius, center.y - radius + 5),
		Vector2(center.x + radius, center.y + radius - 5),
		Vector2(center.x + radius - 5, center.y + radius),
		Vector2(center.x - radius + 5, center.y + radius),
		Vector2(center.x - radius, center.y + radius - 5),
		Vector2(center.x - radius, center.y - radius + 5),
	])
	canvas.draw_colored_polygon(points, dark)
	for i in 8:
		var cardinal := posmod(i + phase, 8)
		var angle := float(cardinal) * TAU / 8.0
		var p := (Vector2(center) + Vector2.from_angle(angle) * (radius + 2)).floor()
		canvas.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), light)
	@warning_ignore("integer_division")
	var inner := maxi(3, radius / 2)
	canvas.draw_rect(Rect2(center.x - inner, center.y - inner, inner * 2, inner * 2), light)
	canvas.draw_rect(Rect2(center.x - inner + 3, center.y - inner + 3,
		maxi(2, inner * 2 - 6), maxi(2, inner * 2 - 6)), INK)
