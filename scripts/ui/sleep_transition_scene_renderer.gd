extends RefCounted
## Reiner Szenenmaler fuer den Morgenhintergrund des Tageswechsels.
##
## Die Schlafphase selbst ist ein authored Vollbildmotiv. Dieser Renderer besitzt
## deshalb weder Phasenlogik noch Kalender-/UI-Zustand und bekommt alle visuellen
## Eingaben pro Aufruf ueber einen expliziten Kontext.

const FONT_PATH := "res://assets/fonts/VT323_UI.ttf"
const AVATAR_PALETTE := preload("res://scripts/gfx/avatar_palette_32.gd")

var _canvas: CanvasItem
var _font: Font = load(FONT_PATH)
var _avatar_look: Dictionary = {}
var _weather_state := "clear"
var _weather_wind := 0.18
var _elapsed := 0.0
var _reduced_motion := false
var _from_clock := "23:10"
var _scanlines := true


func draw_morning(canvas: CanvasItem, viewport_size: Vector2, context: Dictionary) -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_canvas = canvas
	_avatar_look = (context.get("avatar_look", {}) as Dictionary).duplicate()
	_weather_state = str(context.get("weather_state", "clear"))
	_weather_wind = float(context.get("weather_wind", 0.18))
	_elapsed = float(context.get("elapsed", 0.0))
	_reduced_motion = bool(context.get("reduced_motion", false))
	_from_clock = str(context.get("from_clock", "23:10"))
	_scanlines = bool(context.get("scanlines", true))
	_draw_background(viewport_size, 1.0, 1.0)


func _draw_background(sz: Vector2, progress: float, dawn: float) -> void:
	var top_color := Color("030611").lerp(Color("193b5a"), dawn)
	var bottom_color := Color("17152b").lerp(Color("c57a55"), dawn)
	for band in 48:
		var ratio := float(band) / 47.0
		var y0 := sz.y * ratio
		var y1 := sz.y * float(band + 1) / 47.0
		_canvas.draw_rect(Rect2(0, y0, sz.x, y1 - y0 + 1.0),
			top_color.lerp(bottom_color, ratio))
	_draw_cinematic_room(sz, progress, dawn)
	_draw_dawn_exposure(sz, dawn)
	_draw_vignette(sz, dawn)
	_draw_scanlines(sz)
	_canvas.draw_rect(Rect2(7, 7, sz.x - 14, sz.y - 14),
		Color(Palette.UI_BORDER_DARK, 0.92), false, 6.0)
	_canvas.draw_rect(Rect2(17, 17, sz.x - 34, sz.y - 34),
		Color(Palette.LCD_CYAN, 0.23), false, 2.0)


func _draw_cinematic_room(sz: Vector2, progress: float, dawn: float) -> void:
	var floor_y := sz.y * 0.735
	_canvas.draw_rect(Rect2(0, sz.y * 0.10, sz.x, floor_y - sz.y * 0.10),
		Color(0.065 + dawn * 0.10, 0.055 + dawn * 0.07, 0.11 + dawn * 0.06, 0.82))
	for stripe in 12:
		var sy := sz.y * 0.12 + stripe * (floor_y - sz.y * 0.12) / 12.0
		_canvas.draw_line(Vector2(0, sy), Vector2(sz.x, sy),
			Color(0.30, 0.24, 0.38, 0.035), 1.0)
	_canvas.draw_rect(Rect2(0, floor_y, sz.x, sz.y - floor_y),
		Color(0.018, 0.017, 0.031, 0.94))
	for plank in 9:
		var py := floor_y + float(plank) * (sz.y - floor_y) / 9.0
		_canvas.draw_line(Vector2(0, py), Vector2(sz.x, py),
			Color(0.20, 0.12, 0.09, 0.12 + dawn * 0.08), 2.0)

	var window_rect := Rect2(sz.x * 0.105, sz.y * 0.17, sz.x * 0.285, sz.y * 0.43)
	_draw_window_time_lapse(window_rect, progress, dawn)
	_draw_window_light(window_rect, sz, dawn)
	_draw_curtains(window_rect, dawn)

	var table := Rect2(sz.x * 0.405, floor_y - sz.y * 0.13, sz.x * 0.10, sz.y * 0.14)
	_canvas.draw_rect(table, Color(0.12, 0.075, 0.055, 0.96))
	_canvas.draw_rect(Rect2(table.position, Vector2(table.size.x, 9)),
		Color(0.25, 0.14, 0.08, 0.96))
	var clock := Rect2(table.position + Vector2(table.size.x * 0.17, 16),
		Vector2(table.size.x * 0.66, 34))
	_canvas.draw_rect(clock, Color(0.015, 0.012, 0.018, 0.98))
	_canvas.draw_rect(clock, Color(0.45, 0.14, 0.12, 0.44), false, 2.0)
	_canvas.draw_string(_font, clock.position + Vector2(13, 25),
		_time_lapse_clock(_from_clock, progress), HORIZONTAL_ALIGNMENT_LEFT,
		-1, 22, Color(1.0, 0.22, 0.18, 0.92))
	var lamp_base := Vector2(table.get_center().x, table.position.y - 8)
	_canvas.draw_line(lamp_base, lamp_base - Vector2(0, 72),
		Color(0.12, 0.12, 0.16), 7.0)
	_canvas.draw_colored_polygon(PackedVector2Array([
		lamp_base - Vector2(38, 66), lamp_base + Vector2(38, -66),
		lamp_base + Vector2(23, -98), lamp_base + Vector2(-23, -98),
	]), Color(0.11, 0.10, 0.13))

	var bed := Rect2(sz.x * 0.485, floor_y - sz.y * 0.18, sz.x * 0.425, sz.y * 0.19)
	_draw_bed_and_sleeper(bed, dawn)


func _time_lapse_clock(start_text: String, progress: float) -> String:
	var parts := start_text.split(":")
	var start_minutes := 23 * 60 + 10
	if parts.size() >= 2 and str(parts[0]).is_valid_int() and str(parts[1]).is_valid_int():
		start_minutes = int(parts[0]) * 60 + int(parts[1])
	var current := posmod(start_minutes + roundi(progress * 540.0), 24 * 60)
	return "%02d:%02d" % [floori(current / 60.0), current % 60]


func _draw_window_time_lapse(rect: Rect2, progress: float, dawn: float) -> void:
	var sky_top := Color("071225").lerp(Color("47769a"), dawn)
	var sky_bottom := Color("17234a").lerp(Color("ef9b64"), dawn)
	_canvas.draw_rect(rect.grow(8.0), Color(0.018, 0.021, 0.032, 0.98))
	for band in 20:
		var ratio := float(band) / 19.0
		var y0 := rect.position.y + rect.size.y * ratio
		var y1 := rect.position.y + rect.size.y * float(band + 1) / 19.0
		_canvas.draw_rect(Rect2(rect.position.x, y0, rect.size.x, y1 - y0 + 1.0),
			sky_top.lerp(sky_bottom, ratio))
	var motion := 0.0 if _reduced_motion else _elapsed * 7.0
	for i in 34:
		var px := rect.position.x + fposmod(float(i * 79 + 31)
			+ motion * float(1 + i % 3), rect.size.x)
		var py := rect.position.y + fposmod(float(i * 47 + 19), rect.size.y * 0.72)
		var twinkle := 0.70 if _reduced_motion else 0.58 + sin(_elapsed * 3.0 + i * 1.7) * 0.30
		_canvas.draw_circle(Vector2(px, py), 1.0 + float(i % 3) * 0.55,
			Color(0.78, 0.88, 1.0, (1.0 - dawn) * twinkle))
	_draw_window_weather(rect, progress, dawn)
	var moon_x := lerpf(rect.end.x - rect.size.x * 0.18,
		rect.position.x + rect.size.x * 0.22, progress)
	var moon_y := rect.position.y + rect.size.y * (0.28 - sin(progress * PI) * 0.13)
	var moon_pos := Vector2(moon_x, moon_y)
	_canvas.draw_circle(moon_pos, 31.0, Color(0.94, 0.94, 0.76, (1.0 - dawn) * 0.96))
	_canvas.draw_circle(moon_pos + Vector2(12, -5), 29.5,
		Color(sky_top, (1.0 - dawn) * 0.98))
	var skyline_y := rect.end.y - rect.size.y * 0.20
	for building in 11:
		var bw := rect.size.x / 11.0 + 2.0
		var bh := rect.size.y * (0.10 + float((building * 7) % 9) * 0.012)
		var bx := rect.position.x + building * rect.size.x / 11.0
		_canvas.draw_rect(Rect2(bx, skyline_y - bh, bw, bh + rect.end.y - skyline_y),
			Color(0.025, 0.035, 0.065, 0.94))
		if building % 2 == 0:
			_canvas.draw_rect(Rect2(bx + bw * 0.32, skyline_y - bh * 0.55, 4, 4),
				Color(1.0, 0.72, 0.30, (1.0 - dawn) * 0.55))
	_canvas.draw_line(Vector2(rect.get_center().x, rect.position.y),
		Vector2(rect.get_center().x, rect.end.y), Color(0.18, 0.25, 0.38, 0.92), 6.0)
	_canvas.draw_line(Vector2(rect.position.x, rect.get_center().y),
		Vector2(rect.end.x, rect.get_center().y), Color(0.18, 0.25, 0.38, 0.92), 5.0)
	_canvas.draw_rect(rect, Color(0.50, 0.66, 0.82, 0.40 + dawn * 0.20), false, 3.0)


func _draw_window_weather(rect: Rect2, progress: float, dawn: float) -> void:
	if _weather_state == "clear":
		return
	var cloud_alpha := (0.34 if _weather_state == "clouds" else 0.52) \
		* (1.0 - dawn * 0.30)
	var drift := progress * rect.size.x * (0.18 + _weather_wind * 0.14)
	for cloud_i in 3:
		var cx := rect.position.x + fposmod(38.0 + cloud_i * 137.0 + drift,
			rect.size.x - 76.0)
		var cy := rect.position.y + 52.0 + cloud_i * 43.0
		var cloud_color := Color(0.17, 0.22, 0.32, cloud_alpha)
		_canvas.draw_circle(Vector2(cx, cy), 24.0, cloud_color)
		_canvas.draw_circle(Vector2(cx + 27, cy + 5), 31.0, cloud_color)
		_canvas.draw_circle(Vector2(cx + 58, cy + 9), 21.0, cloud_color)
		_canvas.draw_rect(Rect2(cx - 7, cy + 6, 72, 21), cloud_color)
	if _weather_state not in ["rain", "storm"]:
		return
	var density := 24 if _weather_state == "rain" else 38
	var rain_alpha := (0.34 if _weather_state == "rain" else 0.52) \
		* (1.0 - dawn * 0.22)
	for i in density:
		var x := rect.position.x + 9.0 + fposmod(float(i * 71 + 17)
			+ _elapsed * (78.0 + i % 4 * 13.0), rect.size.x - 24.0)
		var y := rect.position.y + 7.0 + fposmod(float(i * 43 + 11)
			+ _elapsed * (126.0 + i % 3 * 18.0), rect.size.y - 35.0)
		var length := 13.0 + float(i % 4) * 3.0
		_canvas.draw_line(Vector2(x, y), Vector2(x - 5.0 * _weather_wind, y + length),
			Color(0.58, 0.76, 0.96, rain_alpha), 1.5)
	if _weather_state == "storm":
		var pulse := pow(maxf(0.0, sin(progress * TAU * 2.0 - 0.8)), 12.0)
		_canvas.draw_rect(rect.grow(-3.0), Color(0.74, 0.82, 1.0, pulse * 0.13))


func _draw_window_light(rect: Rect2, sz: Vector2, dawn: float) -> void:
	if dawn <= 0.01:
		return
	_canvas.draw_colored_polygon(PackedVector2Array([
		rect.end - Vector2(rect.size.x * 0.12, 0), rect.end,
		Vector2(sz.x * 0.88, sz.y * 0.89), Vector2(sz.x * 0.48, sz.y * 0.89),
	]), Color(1.0, 0.72, 0.42, dawn * 0.18))
	for ray in 4:
		var offset := float(ray) * rect.size.x * 0.17
		_canvas.draw_line(rect.position + Vector2(offset + 18, rect.size.y),
			Vector2(sz.x * (0.50 + ray * 0.09), sz.y * 0.88),
			Color(1.0, 0.80, 0.55, dawn * 0.09), 10.0)
	for dust in 16:
		var life := fposmod(float(dust * 37) + _elapsed * (7.0 + dust % 3), 100.0) / 100.0
		var x := lerpf(rect.get_center().x, sz.x * 0.76, life) \
			+ sin(float(dust) * 2.7) * 24.0
		var y := lerpf(rect.end.y, sz.y * 0.86, life) \
			+ cos(float(dust) * 1.9) * 16.0
		_canvas.draw_circle(Vector2(x, y), 1.0 + dust % 2,
			Color(1.0, 0.82, 0.55, dawn * 0.18))


func _draw_curtains(rect: Rect2, dawn: float) -> void:
	var sway := 0.0 if _reduced_motion else sin(_elapsed * (1.45 + _weather_wind)) \
		* (3.0 + _weather_wind * 7.0)
	var fabric := Color(0.075 + dawn * 0.09, 0.065 + dawn * 0.06,
		0.13 + dawn * 0.04, 0.98)
	_canvas.draw_colored_polygon(PackedVector2Array([
		rect.position - Vector2(48, 15), rect.position + Vector2(32, -15),
		rect.position + Vector2(20 + sway, rect.size.y + 25),
		rect.position + Vector2(-61 + sway * 0.4, rect.size.y + 25),
	]), fabric)
	_canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(rect.end.x - 32, rect.position.y - 15),
		rect.end + Vector2(48, -rect.size.y - 15),
		rect.end + Vector2(61 - sway * 0.4, 25), rect.end + Vector2(-20 - sway, 25),
	]), fabric)
	for fold in 4:
		var fy := rect.position.y
		var lx := rect.position.x - 42 + fold * 19
		var rx := rect.end.x + 42 - fold * 19
		_canvas.draw_line(Vector2(lx, fy), Vector2(lx + sway * 0.35, rect.end.y + 22),
			Color(0.32, 0.28, 0.43, 0.16), 3.0)
		_canvas.draw_line(Vector2(rx, fy), Vector2(rx - sway * 0.35, rect.end.y + 22),
			Color(0.32, 0.28, 0.43, 0.16), 3.0)
	_canvas.draw_line(rect.position - Vector2(62, 18),
		Vector2(rect.end.x + 62, rect.position.y - 18), Color(0.18, 0.14, 0.10), 7.0)
	_canvas.draw_circle(rect.position - Vector2(64, 18), 7.0, Color(0.24, 0.17, 0.10))
	_canvas.draw_circle(Vector2(rect.end.x + 64, rect.position.y - 18),
		7.0, Color(0.24, 0.17, 0.10))


func _draw_bed_and_sleeper(bed: Rect2, dawn: float) -> void:
	var breath := 0.0 if _reduced_motion else sin(_elapsed * 2.35) * 4.0
	_canvas.draw_rect(Rect2(bed.position + Vector2(18, bed.size.y - 3),
		Vector2(bed.size.x, 18)), Color(0, 0, 0, 0.45))
	_canvas.draw_rect(Rect2(bed.position - Vector2(15, 18),
		Vector2(18, bed.size.y + 28)), Color(0.18, 0.095, 0.055, 0.98))
	_canvas.draw_rect(Rect2(bed.position + Vector2(0, bed.size.y - 12),
		Vector2(bed.size.x, 24)), Color(0.22, 0.115, 0.06, 0.98))
	_canvas.draw_rect(Rect2(bed.position, Vector2(bed.size.x, bed.size.y * 0.52)),
		Color(0.24, 0.25, 0.34, 0.98))
	var pillow := Rect2(bed.position + Vector2(24, 11),
		Vector2(bed.size.x * 0.25, bed.size.y * 0.34))
	var pillow_color := Color(0.46 + dawn * 0.13, 0.49 + dawn * 0.11,
		0.60 + dawn * 0.07, 0.94)
	_canvas.draw_colored_polygon(PackedVector2Array([
		pillow.position + Vector2(7, 0), pillow.end - Vector2(7, pillow.size.y),
		pillow.end - Vector2(0, 7), pillow.end - Vector2(pillow.size.x, 5),
	]), pillow_color)
	_canvas.draw_polyline(PackedVector2Array([
		pillow.position + Vector2(9, 5), pillow.end - Vector2(11, pillow.size.y - 5),
		pillow.end - Vector2(5, 10),
	]), Color(0.75, 0.78, 0.86, 0.28), 2.0)
	var head := pillow.position + Vector2(pillow.size.x * 0.62, pillow.size.y * 0.36)
	_draw_avatar_sleeper(head, dawn)
	var cloth_key := str(_avatar_look.get("shirt_color",
		_avatar_look.get("personality", "teal")))
	var cloth_base := AVATAR_PALETTE.figure_base(
		"cloth", cloth_key, Color8(42, 126, 133))
	var night_cloth := cloth_base.darkened(0.34).lerp(cloth_base.darkened(0.10), dawn)
	_canvas.draw_circle(head + Vector2(40, 24), 27.0, night_cloth)
	_canvas.draw_arc(head + Vector2(40, 24), 25.0, PI, TAU, 16,
		night_cloth.lightened(0.18), 3.0)
	var blanket_top := bed.position.y + bed.size.y * 0.26 - breath
	var blanket := PackedVector2Array([
		Vector2(bed.position.x + bed.size.x * 0.23, blanket_top + 9),
		Vector2(bed.position.x + bed.size.x * 0.40, blanket_top - 10),
		Vector2(bed.position.x + bed.size.x * 0.62, blanket_top + breath * 0.4),
		Vector2(bed.end.x, blanket_top + 8), bed.end,
		Vector2(bed.position.x + bed.size.x * 0.20, bed.end.y),
	])
	_canvas.draw_colored_polygon(blanket,
		Color(0.10 + dawn * 0.05, 0.19 + dawn * 0.07, 0.34 + dawn * 0.06, 0.98))
	_canvas.draw_colored_polygon(PackedVector2Array([
		blanket[0] + Vector2(0, 9), blanket[1] + Vector2(0, 11),
		blanket[2] + Vector2(0, 13), blanket[3] + Vector2(0, 10),
	]), Color(0.015, 0.025, 0.06, 0.20))
	_canvas.draw_polyline(PackedVector2Array([blanket[0], blanket[1], blanket[2], blanket[3]]),
		Color(0.35, 0.52, 0.72, 0.46), 3.0, true)
	_canvas.draw_polyline(PackedVector2Array([
		blanket[0] + Vector2(10, 9), blanket[1] + Vector2(17, 8),
		blanket[2] + Vector2(25, 11), blanket[3] + Vector2(-20, 10),
	]), Color(0.52, 0.65, 0.82, 0.16 + dawn * 0.10), 2.0, true)
	for stripe in 4:
		var sx := bed.position.x + bed.size.x * (0.42 + stripe * 0.12)
		_canvas.draw_line(Vector2(sx, blanket_top), Vector2(sx + 8, bed.end.y),
			Color(0.35, 0.47, 0.66, 0.13), 2.0)


func _draw_avatar_sleeper(head: Vector2, dawn: float) -> void:
	var skin_key := str(_avatar_look.get("skin", "beige"))
	var hair_key := str(_avatar_look.get("hair_color", _avatar_look.get("hair", "brown")))
	var hair_style := str(_avatar_look.get("hair_style", "short"))
	var skin_base := AVATAR_PALETTE.figure_base(
		"skin", skin_key, Color8(216, 166, 126))
	var hair_base := AVATAR_PALETTE.figure_base(
		"hair", hair_key, Color8(91, 62, 44))
	var skin := skin_base.darkened(0.34).lerp(skin_base.darkened(0.05), dawn)
	var hair := hair_base.darkened(0.20).lerp(hair_base.lightened(0.05), dawn)
	var hair_shadow := hair.darkened(0.34)
	_draw_avatar_hair_back(head, hair_style, hair_shadow)
	_canvas.draw_circle(head - Vector2(20, 0), 8.0, skin.darkened(0.10))
	_canvas.draw_circle(head, 25.0, skin)
	_canvas.draw_colored_polygon(PackedVector2Array([
		head + Vector2(20, -5), head + Vector2(31, 2), head + Vector2(20, 6),
	]), skin)
	_canvas.draw_line(head + Vector2(9, 3), head + Vector2(17, 3),
		hair_shadow.darkened(0.24), 2.4)
	_canvas.draw_line(head + Vector2(10, 4), head + Vector2(15, 5),
		Color(0.72, 0.49, 0.42, 0.46), 1.2)
	_canvas.draw_line(head + Vector2(24, 11), head + Vector2(18, 12),
		Color(0.30, 0.08, 0.09, 0.60), 1.6)
	_canvas.draw_circle(head + Vector2(14, 10), 4.0,
		Color(0.92, 0.48, 0.42, 0.07 + dawn * 0.05))
	_draw_avatar_hair_front(head, hair_style, hair, hair_shadow)


func _draw_avatar_hair_back(head: Vector2, style: String, hair: Color) -> void:
	if style in ["long", "straight", "medium", "mullet", "bob", "ponytail", "bun", "pigtails"]:
		_canvas.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-25, -15), head + Vector2(-31, 4),
			head + Vector2(-25, 31), head + Vector2(-7, 28),
			head + Vector2(-5, -12),
		]), hair)
	if style == "ponytail":
		_canvas.draw_line(head + Vector2(-21, -6), head + Vector2(-43, 17), hair, 11.0)
		_canvas.draw_circle(head + Vector2(-47, 23), 10.0, hair)
	elif style == "bun":
		_canvas.draw_circle(head + Vector2(-25, -20), 13.0, hair)
	elif style == "pigtails":
		_canvas.draw_line(head + Vector2(-21, -4), head + Vector2(-43, 17), hair, 8.0)
		_canvas.draw_circle(head + Vector2(-46, 21), 8.0, hair)
	elif style == "mullet":
		_canvas.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-22, 5), head + Vector2(-28, 32),
			head + Vector2(-8, 35), head + Vector2(-5, 2),
		]), hair)
	elif style == "afro":
		for offset in [
			Vector2(-25, -13), Vector2(-17, -27), Vector2(0, -32),
			Vector2(18, -25), Vector2(25, -8), Vector2(-28, 4),
		]:
			_canvas.draw_circle(head + offset, 15.0, hair)


func _draw_avatar_hair_front(
		head: Vector2,
		style: String,
		hair: Color,
		shadow: Color
) -> void:
	if style == "bald":
		_canvas.draw_arc(head - Vector2(2, 2), 22.0, 3.45, 5.72, 12,
			Color(hair, 0.18), 2.0)
		return
	if style == "afro":
		for offset in [
			Vector2(-19, -18), Vector2(-5, -27), Vector2(11, -25), Vector2(21, -13),
		]:
			_canvas.draw_circle(head + offset, 13.0, hair)
		return
	var cap := PackedVector2Array([
		head + Vector2(-23, -2), head + Vector2(-20, -17),
		head + Vector2(-9, -27), head + Vector2(8, -28),
		head + Vector2(23, -16), head + Vector2(21, -5),
		head + Vector2(10, -10), head + Vector2(-4, -7),
	])
	if style == "buzzcut":
		_canvas.draw_arc(head - Vector2(1, 3), 23.0, PI, TAU, 18, hair, 6.0)
		return
	_canvas.draw_colored_polygon(cap, hair)
	_canvas.draw_arc(head - Vector2(1, 4), 24.0, PI, TAU, 18, shadow, 3.0)
	match style:
		"curly":
			for offset in [
				Vector2(-18, -18), Vector2(-6, -27),
				Vector2(8, -27), Vector2(20, -17),
			]:
				_canvas.draw_circle(head + offset, 8.0, hair.lightened(0.06))
		"mohawk":
			_canvas.draw_colored_polygon(PackedVector2Array([
				head + Vector2(-15, -22), head + Vector2(-8, -39),
				head + Vector2(0, -26), head + Vector2(8, -43),
				head + Vector2(15, -23),
			]), hair)
		"spiky":
			_canvas.draw_colored_polygon(PackedVector2Array([
				head + Vector2(-19, -17), head + Vector2(-14, -36),
				head + Vector2(-5, -25), head + Vector2(2, -42),
				head + Vector2(9, -25), head + Vector2(18, -36),
				head + Vector2(22, -15),
			]), hair)
		"quiff":
			_canvas.draw_circle(head + Vector2(13, -27), 11.0, hair.lightened(0.05))
		"flattop":
			_canvas.draw_rect(Rect2(head + Vector2(-16, -32), Vector2(34, 13)), hair)
		"parted":
			_canvas.draw_line(head + Vector2(1, -29), head + Vector2(-4, -8), shadow, 2.2)
		"messy":
			_canvas.draw_polyline(PackedVector2Array([
				head + Vector2(-17, -20), head + Vector2(-9, -34),
				head + Vector2(-2, -25), head + Vector2(8, -35),
				head + Vector2(18, -20),
			]), hair.lightened(0.10), 5.0)


func _draw_dawn_exposure(sz: Vector2, dawn: float) -> void:
	if dawn <= 0.01:
		return
	for band in 8:
		var ratio := float(band) / 7.0
		var width := sz.x * (0.18 + ratio * 0.46)
		var alpha := dawn * (1.0 - ratio) * 0.018
		_canvas.draw_rect(Rect2(sz.x * 0.24 - width * 0.5, 0, width, sz.y),
			Color(1.0, 0.70, 0.42, alpha))
	var reveal := sin(clampf(dawn, 0.0, 1.0) * PI) * 0.055
	_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.95, 0.58, 0.34, reveal))


func _draw_vignette(sz: Vector2, dawn: float) -> void:
	for band in 18:
		var width := float(18 - band) * 7.0
		var alpha := float(18 - band) / 18.0 * (0.035 + (1.0 - dawn) * 0.025)
		_canvas.draw_rect(Rect2(band * 7.0, 0, width, sz.y), Color(0, 0, 0, alpha))
		_canvas.draw_rect(Rect2(sz.x - band * 7.0 - width, 0, width, sz.y),
			Color(0, 0, 0, alpha))
		_canvas.draw_rect(Rect2(0, band * 5.0, sz.x, float(18 - band) * 5.0),
			Color(0, 0, 0, alpha * 0.72))
		_canvas.draw_rect(Rect2(0,
			sz.y - band * 5.0 - float(18 - band) * 5.0,
			sz.x, float(18 - band) * 5.0), Color(0, 0, 0, alpha * 0.72))


func _draw_scanlines(sz: Vector2) -> void:
	if not _scanlines:
		return
	for y in range(1, int(sz.y), 4):
		_canvas.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(0, 0, 0, 0.15), 1.0)
