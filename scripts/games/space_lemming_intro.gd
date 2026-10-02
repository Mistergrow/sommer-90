class_name SpaceLemmingIntro
extends RefCounted
## Rein visuelle, ueberspringbare Notrufsequenz vor dem Titelbild.

const Art := preload("res://scripts/games/space_lemming_art.gd")
const BACKGROUND := preload("res://assets/ui/games/space_lemming/intro_distress_background_v01.png")
const VW := 384.0
const VH := 216.0
const INK := Color8(6, 10, 20)
const WHITE := Color8(234, 238, 218)
const CREAM := Color8(236, 195, 135)
const AMBER := Color8(246, 166, 51)
const CYAN := Color8(64, 210, 222)


static func draw(canvas: CanvasItem, boot_time: float, font: Font) -> void:
	if boot_time < 0.85:
		canvas.draw_rect(Rect2(0, 0, VW, VH), INK)
		var reveal := clampi(floori(boot_time * 24.0), 0, 17)
		_text(canvas, font, "VOIDWALK SOFTWARE".substr(0, reveal), 0, 82, 14, CYAN,
			HORIZONTAL_ALIGNMENT_CENTER, VW)
		_text(canvas, font, "PRESENTS", 0, 105, 8, WHITE, HORIZONTAL_ALIGNMENT_CENTER, VW)
		var scan := fmod(boot_time * 95.0, VW)
		canvas.draw_rect(Rect2(scan, 122, 28, 1), Color(0.2, 0.9, 1.0, 0.38))
		return
	_cover(canvas)
	var scene_time := boot_time - 0.85
	canvas.draw_rect(Rect2(0, 0, VW, VH), Color(0.0, 0.015, 0.035, 0.18))
	var route_end := clampf(scene_time / 2.2, 0.0, 1.0)
	var route_from := Vector2(77, 103)
	var route_to := Vector2(282, 111)
	for i in 18:
		var phase := float(i) / 17.0
		if phase > route_end or (i + floori(scene_time * 10.0)) % 3 == 0:
			continue
		var point := route_from.lerp(route_to, phase)
		canvas.draw_rect(Rect2(point.round(), Vector2(2, 1)), Color(0.25, 0.9, 1.0, 0.74))
	var alarm := 0.25 + (sin(scene_time * 9.0) * 0.5 + 0.5) * 0.55
	canvas.draw_circle(Vector2(319, 83), 11.0, Color(1.0, 0.18, 0.08, alarm * 0.12))
	canvas.draw_circle(Vector2(319, 83), 2.0, Color(1.0, 0.35, 0.12, alarm))
	for i in 4:
		var flame_x := 32.0 - fmod(scene_time * (26.0 + i * 3.0) + i * 7.0, 29.0)
		canvas.draw_rect(Rect2(Vector2(flame_x, 107 + i * 2), Vector2(3 + i % 2, 1)),
			Color(0.25, 0.75 + i * 0.05, 1.0, 0.65))
	if scene_time > 2.25:
		var eva_t := clampf((scene_time - 2.25) / 1.25, 0.0, 1.0)
		var eva_pos := Vector2(205, 117).lerp(Vector2(278, 112), eva_t)
		Art.draw_intro_actor(canvas, eva_pos + Vector2(0, -sin(eva_t * PI) * 7.0), 2, 0.9)
	_radio(canvas, font, scene_time)
	_text(canvas, font, "ENTER UEBERSPRINGT", 281, 210, 5, Color(0.72, 0.8, 0.78, 0.72))
	var fade := clampf((boot_time - 4.75) / 0.45, 0.0, 1.0)
	if fade > 0.0:
		canvas.draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, fade))


static func _radio(canvas: CanvasItem, font: Font, scene_time: float) -> void:
	canvas.draw_rect(Rect2(0, 0, VW, 21), Color(0.01, 0.025, 0.055, 0.90))
	canvas.draw_rect(Rect2(0, 168, VW, 48), Color(0.01, 0.025, 0.05, 0.91))
	canvas.draw_line(Vector2(0, 168), Vector2(VW, 168), CYAN, 1.0)
	for i in 32:
		var height := 1.0 + absf(sin(scene_time * 8.0 + i * 1.7)) * 5.0
		canvas.draw_line(Vector2(9 + i * 4, 189 - height), Vector2(9 + i * 4, 189 + height),
			Color(0.25, 0.85, 0.95, 0.48), 1.0)
	var headline := "NOTRUF EMPFANGEN" if scene_time < 1.25 else (
		"AUSSENPOSTEN K-7" if scene_time < 2.35 else "RETTUNGSTEAM IM ANFLUG")
	var detail := "FUENF ARBEITER EINGESCHLOSSEN" if scene_time < 2.35 else (
		"STEGNETZ BESCHAEDIGT" if scene_time < 3.35 else "KOMMANDOSIGNAL BEREIT")
	_text(canvas, font, headline, 8, 15, 8, AMBER)
	_text(canvas, font, detail, 145, 187, 7, WHITE)
	var typed := clampi(floori(scene_time * 24.0), 0, detail.length())
	canvas.draw_rect(Rect2(145 + typed * 4.1, 190, 4, 1), CYAN)
	_text(canvas, font, "EINSATZ 01 · ORBITALE NACHTSEITE", 145, 204, 6, CREAM)


static func _cover(canvas: CanvasItem) -> void:
	var source_size := BACKGROUND.get_size()
	var target_ratio := VW / VH
	var source_ratio := source_size.x / source_size.y
	var source_rect := Rect2(Vector2.ZERO, source_size)
	if source_ratio > target_ratio:
		var width := source_size.y * target_ratio
		source_rect.position.x = (source_size.x - width) * 0.5
		source_rect.size.x = width
	else:
		var height := source_size.x / target_ratio
		source_rect.position.y = (source_size.y - height) * 0.5
		source_rect.size.y = height
	canvas.draw_texture_rect_region(BACKGROUND, Rect2(0, 0, VW, VH), source_rect)


static func _text(canvas: CanvasItem, font: Font, value: String, x: float, y: float,
		size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0) -> void:
	canvas.draw_string(font, Vector2(x, y), value, alignment, width, size, color)
