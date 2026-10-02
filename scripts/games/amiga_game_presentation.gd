class_name AmigaGamePresentation
extends RefCounted
## Gemeinsamer physischer DF0:-Startmoment fuer selbstbootende Amiga-Spiele.
##
## Hardwarevertrag: Beim Amiga 500 sitzt das interne Laufwerk an der rechten
## Gehaeuseseite. Das Motiv darf deshalb niemals einen Frontschlitz zeigen.

const DISK_BOOT_ART := preload("res://assets/ui/games/shared/amiga_disk_boot_background_v02.png")
const TOPAZ: Font = preload("res://assets/fonts/Topaz_a500_ui.ttf")

const INK := Color8(2, 5, 10)
const PAPER := Color8(231, 232, 210)
const DIM := Color8(145, 161, 164)


static func draw_disk_boot(canvas: CanvasItem, target_size: Vector2, elapsed: float,
		duration: float, accent: Color, disk_title: String) -> void:
	var target := Rect2(Vector2.ZERO, target_size)
	_draw_crop(canvas, DISK_BOOT_ART, target)
	canvas.draw_rect(target, Color(0.005, 0.012, 0.025, 0.22))

	var band_height := maxf(22.0, target_size.y * 0.145)
	canvas.draw_rect(Rect2(0, 0, target_size.x, band_height), Color(0.005, 0.012, 0.022, 0.86))
	canvas.draw_rect(Rect2(0, target_size.y - band_height, target_size.x, band_height),
		Color(0.005, 0.012, 0.022, 0.90))

	var ratio := clampf(elapsed / maxf(0.01, duration), 0.0, 1.0)
	var font_size := maxi(6, roundi(target_size.y * 0.041))
	var small_size := maxi(5, roundi(target_size.y * 0.031))
	var margin := maxf(7.0, target_size.x * 0.025)
	canvas.draw_string(TOPAZ, Vector2(margin, band_height * 0.67),
		"DF0:  MEDIUM EINGELEGT", HORIZONTAL_ALIGNMENT_LEFT,
		target_size.x - margin * 2.0, font_size, accent)

	var safe_title := disk_title.to_upper().left(31)
	canvas.draw_string(TOPAZ, Vector2(margin, target_size.y - band_height * 0.54),
		safe_title, HORIZONTAL_ALIGNMENT_LEFT, target_size.x * 0.58,
		small_size, PAPER)
	var track := clampi(floori(ratio * 80.0), 0, 79)
	canvas.draw_string(TOPAZ, Vector2(target_size.x * 0.60, target_size.y - band_height * 0.54),
		"SPUR %02d/79" % track, HORIZONTAL_ALIGNMENT_RIGHT,
		target_size.x * 0.375, small_size, DIM)

	var bar := Rect2(margin, target_size.y - 4.0, target_size.x - margin * 2.0, 2.0)
	canvas.draw_rect(bar, Color8(26, 36, 43))
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), accent)

	# Das physische Bild blendet sauber in die individuelle Spielepraesentation.
	var fade := clampf((ratio - 0.82) / 0.18, 0.0, 1.0)
	if fade > 0.0:
		canvas.draw_rect(target, Color(0, 0, 0, fade))

	# CRT-Zeilen bleiben subtil, damit die generierte Pixelgrafik nicht verwascht.
	for y in range(1, roundi(target_size.y), 2):
		canvas.draw_line(Vector2(0, y), Vector2(target_size.x, y),
			Color(0, 0, 0, 0.08), 1.0)


static func _draw_crop(canvas: CanvasItem, texture: Texture2D, target: Rect2) -> void:
	var source_size := texture.get_size()
	var target_ratio := target.size.x / maxf(1.0, target.size.y)
	var source_ratio := source_size.x / maxf(1.0, source_size.y)
	var source := Rect2(Vector2.ZERO, source_size)
	if source_ratio > target_ratio:
		var width := source_size.y * target_ratio
		source.position.x = (source_size.x - width) * 0.5
		source.size.x = width
	else:
		var height := source_size.x / target_ratio
		source.position.y = (source_size.y - height) * 0.5
		source.size.y = height
	canvas.draw_texture_rect_region(texture, target, source)
