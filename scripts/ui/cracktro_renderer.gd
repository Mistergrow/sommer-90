extends RefCounted
## Authentischer LoRes-Renderer fuer BYTEWERK-Intros. Das Bild entsteht auf
## einem festen 320x200-Amiga-Raster und wird ausschliesslich ganzzahlig
## skaliert. Dadurch bleiben Topaz-Schrift, Rasterbars, BOBs und Scroller auch
## in einem grossen Spielfenster scharf und wirken wie ein echtes Disk-Intro.

const VIRTUAL_SIZE := Vector2(320.0, 200.0)
const FONT_PATH := "res://assets/fonts/Topaz_a500_ui.ttf"

static var _font: FontFile


static func font() -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as FontFile
		if _font != null:
			_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			_font.hinting = TextServer.HINTING_NONE
			_font.generate_mipmaps = false
	return _font if _font != null else ThemeDB.fallback_font


static func draw_intro(canvas: Control, elapsed: float, state: Dictionary) -> void:
	var palette: Array = state.get("palette", [])
	if palette.size() < 5:
		return
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color("#020308"))
	var integer_scale := floorf(minf(canvas.size.x / VIRTUAL_SIZE.x,
		canvas.size.y / VIRTUAL_SIZE.y))
	integer_scale = maxf(1.0, integer_scale)
	var picture_size := VIRTUAL_SIZE * integer_scale
	var origin := ((canvas.size - picture_size) * 0.5).floor()
	canvas.draw_rect(Rect2(origin - Vector2(3, 3), picture_size + Vector2(6, 6)),
		Color("#101725"))
	canvas.draw_rect(Rect2(origin - Vector2(2, 2), picture_size + Vector2(4, 4)),
		Color(palette[1], 0.72), false, 1.0)
	canvas.draw_set_transform(origin, 0.0, Vector2(integer_scale, integer_scale))

	var area := Rect2(Vector2.ZERO, VIRTUAL_SIZE)
	_draw_backdrop(canvas, area, elapsed, palette)
	if _has_effect(state, "starfield"):
		_draw_star_tunnel(canvas, area, elapsed, palette)
	if _has_effect(state, "vectorgrid"):
		_draw_vector_grid(canvas, area, elapsed, palette)
	if _has_effect(state, "copperbars"):
		_draw_copper_bands(canvas, area, elapsed, palette)
	if _has_effect(state, "bobs"):
		_draw_bob_orbit(canvas, area, elapsed, palette)
	_draw_status_strip(canvas, state, palette)
	_draw_logo_scene(canvas, elapsed, state, palette)
	_draw_scroller(canvas, elapsed, state, palette)
	_draw_crt_finish(canvas, area, elapsed, palette)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_backdrop(c: Control, area: Rect2, elapsed: float, palette: Array) -> void:
	# Copper-faehiger Farbverlauf in echten Zwei-Pixel-Zeilen statt einer glatten
	# modernen Gradient-Textur. Leichte Ditherpunkte verhindern sterile Flaechen.
	c.draw_rect(area, palette[0])
	for y in range(16, 170, 2):
		var amount := float(y - 16) / 154.0
		var wave := 0.035 * sin(elapsed * 0.7 + float(y) * 0.11)
		var color: Color = (palette[0] as Color).lerp(palette[1], clampf(amount * 0.48 + wave, 0.0, 0.58))
		c.draw_rect(Rect2(0, y, area.size.x, 2), color)
	for i in 74:
		var x := float((i * 67 + 19) % 318) + 1.0
		var y := float((i * 43 + 11) % 164) + 3.0
		if (i + floori(elapsed * 3.0)) % 5 == 0:
			c.draw_rect(Rect2(x, y, 1, 1), Color(palette[3], 0.25))


static func _draw_star_tunnel(c: Control, _area: Rect2, elapsed: float, palette: Array) -> void:
	var center := Vector2(160, 83)
	for i in 64:
		var layer := 1 + i % 4
		var angle := float((i * 37) % 360) * PI / 180.0
		var radius := fposmod(float(i * 23) + elapsed * (9.0 + layer * 5.0), 176.0)
		var direction := Vector2(cos(angle) * 1.28, sin(angle) * 0.68)
		var point := center + direction * radius
		if point.x < 2 or point.x > 317 or point.y < 15 or point.y > 167:
			continue
		var tail := point - direction * float(layer)
		var color: Color = (palette[3] as Color).lerp(palette[4], float(layer) / 5.0)
		c.draw_line(tail.floor(), point.floor(), Color(color, 0.46 + layer * 0.12),
			1.0 if layer < 4 else 2.0, false)


static func _draw_vector_grid(c: Control, _area: Rect2, elapsed: float, palette: Array) -> void:
	var horizon := 111.0
	var floor_end := 169.0
	c.draw_rect(Rect2(0, horizon, 320, floor_end - horizon), Color(palette[0], 0.64))
	for i in 12:
		var bottom_x := float(i) * 32.0 - 16.0
		var top_x := 160.0 + (bottom_x - 160.0) * 0.09
		c.draw_line(Vector2(top_x, horizon), Vector2(bottom_x, floor_end),
			Color(palette[4], 0.30), 1.0, false)
	for row in 9:
		var phase := fposmod(float(row) / 9.0 + elapsed * 0.13, 1.0)
		var y := horizon + pow(phase, 1.85) * (floor_end - horizon)
		c.draw_line(Vector2(0, floorf(y)), Vector2(319, floorf(y)),
			Color(palette[2], 0.24 + phase * 0.28), 1.0, false)


static func _draw_copper_bands(c: Control, _area: Rect2, elapsed: float, palette: Array) -> void:
	for band in 3:
		var base_y := fposmod(elapsed * (7.0 + band * 2.0) + float(band) * 47.0, 142.0) + 18.0
		for row in 9:
			var distance := absf(float(row) - 4.0)
			var color: Color = palette[2] if band % 2 == 0 else palette[4]
			var alpha := maxf(0.06, 0.46 - distance * 0.095)
			c.draw_rect(Rect2(0, floorf(base_y + row), 320, 1), Color(color, alpha))
	# Zwei feststehende Display-Raster geben der Komposition einen klaren Rahmen.
	c.draw_rect(Rect2(0, 96, 320, 1), Color(palette[3], 0.42))
	c.draw_rect(Rect2(0, 99, 320, 1), Color(palette[2], 0.52))


static func _draw_bob_orbit(c: Control, _area: Rect2, elapsed: float, palette: Array) -> void:
	for i in 8:
		var phase := elapsed * (0.72 + float(i % 3) * 0.09) + float(i) * TAU / 8.0
		var point := Vector2(160 + cos(phase) * 132, 104 + sin(phase * 1.27) * 53).floor()
		_draw_pixel_bob(c, point, palette[2] if i % 2 == 0 else palette[4], palette[3])


static func _draw_pixel_bob(c: Control, center: Vector2, color: Color, highlight: Color) -> void:
	c.draw_rect(Rect2(center + Vector2(-3, -5), Vector2(6, 10)), Color(0, 0, 0, 0.45))
	c.draw_rect(Rect2(center + Vector2(-5, -3), Vector2(10, 6)), Color(0, 0, 0, 0.45))
	c.draw_rect(Rect2(center + Vector2(-2, -4), Vector2(4, 8)), color)
	c.draw_rect(Rect2(center + Vector2(-4, -2), Vector2(8, 4)), color)
	c.draw_rect(Rect2(center + Vector2(-2, -3), Vector2(2, 2)), highlight)
	c.draw_rect(Rect2(center + Vector2(2, 2), Vector2(1, 1)), Color(0, 0, 0, 0.7))


static func _draw_status_strip(c: Control, state: Dictionary, palette: Array) -> void:
	var topaz := font()
	c.draw_rect(Rect2(0, 0, 320, 14), Color(palette[0], 0.94))
	c.draw_rect(Rect2(0, 13, 320, 1), Color(palette[2], 0.72))
	var serial := str(state.get("serial", "BYTEWERK")).strip_edges().to_upper()
	var year := str(state.get("year", "1990"))
	_draw_text(c, topaz, Vector2(5, 10), serial.left(22), 8, palette[3])
	var right := "%s  PAL · 50 HZ · 4CH" % year
	var width := topaz.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_draw_text(c, topaz, Vector2(315 - width, 10), right, 8, palette[4])


static func _draw_logo_scene(c: Control, elapsed: float, state: Dictionary, palette: Array) -> void:
	var topaz := font()
	var group := str(state.get("group", "BYTEWERK")).strip_edges().to_upper()
	var title := str(state.get("title", "UNTITLED")).strip_edges().to_upper()
	var logo_style := str(state.get("logo_style", "chrome")).to_lower()
	var logo_size := _fit_size(topaz, group, 286.0, 30, 15)
	var logo_width := topaz.get_string_size(group, HORIZONTAL_ALIGNMENT_LEFT, -1, logo_size).x
	var logo_x := floorf((320.0 - logo_width) * 0.5)
	var bob := roundf(sin(elapsed * 1.7) * 2.0)
	var baseline := 65.0 + bob

	match logo_style:
		"outline", "vector":
			for offset in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
				_draw_text(c, topaz, Vector2(logo_x, baseline) + offset, group, logo_size, palette[2])
			_draw_text(c, topaz, Vector2(logo_x, baseline), group, logo_size, palette[0])
			_draw_text(c, topaz, Vector2(logo_x, baseline - 1), group, logo_size, palette[3])
		"raster":
			for step in range(6, 0, -1):
				var offset := Vector2(float(step), float(step) * 0.5)
				_draw_text(c, topaz, Vector2(logo_x, baseline) + offset, group, logo_size,
					Color(palette[1], 0.78))
			_draw_text(c, topaz, Vector2(logo_x - 1, baseline), group, logo_size, palette[3])
		"stamp":
			var stamp := Rect2(logo_x - 8, baseline - logo_size + 3, logo_width + 16, logo_size + 8)
			c.draw_rect(stamp, Color(palette[0], 0.76))
			c.draw_rect(stamp, palette[2], false, 2.0)
			c.draw_rect(stamp.grow(-3), Color(palette[3], 0.55), false, 1.0)
			_draw_text(c, topaz, Vector2(logo_x, baseline), group, logo_size, palette[3])
		_:
			# Mehrlagige Chromkante: dunkle Extrusion, helle Oberkante, farbiger Fuss.
			for step in range(6, 0, -1):
				_draw_text(c, topaz, Vector2(logo_x + step, baseline + step), group, logo_size,
					(palette[1] as Color).darkened(float(6 - step) * 0.055))
			_draw_text(c, topaz, Vector2(logo_x, baseline + 1), group, logo_size, palette[2])
			_draw_text(c, topaz, Vector2(logo_x, baseline - 1), group, logo_size, palette[3])

	if _has_effect(state, "rasterlogo"):
		var split := roundf(sin(elapsed * 12.0) * 3.0)
		for row in 4:
			var y := baseline - float(logo_size) + 7.0 + row * 7.0
			c.draw_line(Vector2(logo_x - 5 + split * (row % 2), y),
				Vector2(logo_x + logo_width + 5 + split * (row % 2), y),
				Color(palette[4], 0.48), 1.0, false)

	# Glint und Sternkreuz sind bewusst grobe LoRes-Pixel statt moderner Bloom.
	var glint_x := logo_x + fposmod(elapsed * 29.0, maxf(1.0, logo_width))
	c.draw_rect(Rect2(glint_x, baseline - logo_size + 7, 1, maxi(3, logo_size - 8)),
		Color(palette[3], 0.42))
	_draw_flare(c, Vector2(glint_x, baseline - logo_size * 0.45), palette[3])

	var presents := "PROUDLY PRESENTS"
	var presents_width := topaz.get_string_size(presents, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_draw_text(c, topaz, Vector2((320 - presents_width) * 0.5, 91), presents, 8, palette[2])

	var title_size := _fit_size(topaz, title, 292.0, 22, 12)
	var title_width := topaz.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	c.draw_rect(Rect2(7, 106, 306, 37), Color(palette[0], 0.80))
	c.draw_rect(Rect2(7, 106, 306, 37), Color(palette[1], 0.74), false, 1.0)
	c.draw_rect(Rect2(10, 109, 300, 1), Color(palette[4], 0.46))
	_draw_text(c, topaz, Vector2((320 - title_width) * 0.5 + 2, 133), title,
		title_size, Color(0, 0, 0, 0.75))
	_draw_text(c, topaz, Vector2((320 - title_width) * 0.5, 131), title, title_size, palette[4])

	var credits := str(state.get("credits", "")).strip_edges().to_upper()
	if not credits.is_empty():
		var credits_size := _fit_size(topaz, credits, 306.0, 8, 6)
		var credits_width := topaz.get_string_size(credits, HORIZONTAL_ALIGNMENT_LEFT, -1, credits_size).x
		_draw_text(c, topaz, Vector2((320 - credits_width) * 0.5, 160), credits,
			credits_size, palette[3])
	else:
		var solo := "CODE · PIXELS · SOUND"
		var solo_width := topaz.get_string_size(solo, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		_draw_text(c, topaz, Vector2((320 - solo_width) * 0.5, 160), solo, 7, Color(palette[3], 0.68))


static func _draw_scroller(c: Control, elapsed: float, state: Dictionary, palette: Array) -> void:
	var message := ("   " + str(state.get("scroller", "BYTEWERK PRESENTS")) + "   ").to_upper()
	if message.strip_edges().is_empty():
		return
	var topaz := font()
	var font_size := 10
	var char_width := maxf(5.0, topaz.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var text_width := maxf(char_width, float(message.length()) * char_width)
	var offset := fposmod(elapsed * 46.0, text_width)
	var sine := _has_effect(state, "sine_scroller") or not _has_effect(state, "straight_scroller")
	c.draw_rect(Rect2(0, 170, 320, 30), Color(palette[0], 0.98))
	c.draw_rect(Rect2(0, 170, 320, 1), palette[2])
	c.draw_rect(Rect2(0, 172, 320, 1), Color(palette[4], 0.62))
	for repeat in 2:
		var repeat_x := float(repeat) * text_width
		for i in message.length():
			var x := float(i) * char_width - offset + repeat_x
			if x < 4.0 or x > 310.0:
				continue
			var y := 190.0
			if sine:
				y += roundf(sin(elapsed * 4.0 + float(i) * 0.42) * 3.0)
			var color: Color = (palette[2] as Color).lerp(palette[3], float((i + repeat) % 7) / 8.0)
			c.draw_char(topaz, Vector2(floorf(x), y), message[i], font_size, color)


static func _draw_crt_finish(c: Control, area: Rect2, elapsed: float, palette: Array) -> void:
	# Scanlines und Randabdunklung liegen innerhalb des LoRes-Bildes; die Linien
	# bleiben bei ganzzahliger Skalierung stabil und flimmern nicht.
	for y in range(1, 200, 2):
		c.draw_rect(Rect2(0, y, 320, 1), Color(0, 0, 0, 0.075))
	c.draw_rect(Rect2(0, 0, 4, 200), Color(0, 0, 0, 0.28))
	c.draw_rect(Rect2(316, 0, 4, 200), Color(0, 0, 0, 0.28))
	c.draw_rect(Rect2(0, 0, 320, 3), Color(0, 0, 0, 0.24))
	c.draw_rect(Rect2(0, 197, 320, 3), Color(0, 0, 0, 0.30))
	c.draw_rect(area.grow(-1), Color(palette[1], 0.72), false, 1.0)
	var beam_y := floorf(fposmod(elapsed * 23.0, 200.0))
	c.draw_rect(Rect2(2, beam_y, 316, 1), Color(palette[3], 0.035))


static func _draw_flare(c: Control, point: Vector2, color: Color) -> void:
	var p := point.floor()
	c.draw_rect(Rect2(p - Vector2(5, 0), Vector2(11, 1)), Color(color, 0.62))
	c.draw_rect(Rect2(p - Vector2(0, 4), Vector2(1, 9)), Color(color, 0.62))
	c.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), color)


static func _draw_text(c: Control, topaz: Font, position: Vector2, text: String,
		size: int, color: Color) -> void:
	c.draw_string(topaz, position.floor(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func _fit_size(topaz: Font, text: String, max_width: float,
		preferred: int, minimum: int) -> int:
	var size := preferred
	while size > minimum and topaz.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
		size -= 1
	return size


static func _has_effect(state: Dictionary, id: String) -> bool:
	var effects: Array = state.get("effects", [])
	if id in effects:
		return true
	match id:
		"copperbars": return "copper" in effects or "rasterbars" in effects
		"starfield": return "stars" in effects
		"vectorgrid": return "grid" in effects or "vector" in effects
		"bobs": return "bob" in effects or "sprites" in effects
		"sine_scroller": return "sine" in effects or "sinescroll" in effects \
			or "sinus_scroller" in effects
		"straight_scroller": return "straight" in effects
	return false
