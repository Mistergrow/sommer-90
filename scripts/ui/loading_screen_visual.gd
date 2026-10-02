class_name LoadingScreenVisual
extends Control
## Gemeinsames, textfreies Ladebild für Projektstart und Savegame-Laden.
## Das Artwork enthält bewusst keine UI; nur der echte In-Engine-Balken liegt
## darüber und kann sowohl determiniert als auch in kleinen Pulsen arbeiten.

const ART_PATH := "res://assets/ui/loading/SOMMER90_LOADING_MASTER_V01.png"

var progress := 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var pulse_time := 0.0
var indeterminate := false
var _art: Texture2D = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art = load(ART_PATH) as Texture2D
	set_process(true)


func _process(delta: float) -> void:
	pulse_time += minf(maxf(delta, 0.0), 0.1)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.004, 0.007, 0.012))
	if _art != null:
		var source_size := _art.get_size()
		var scale_value := maxf(size.x / source_size.x, size.y / source_size.y)
		var target_size := source_size * scale_value
		var target := Rect2((size - target_size) * 0.5, target_size)
		draw_texture_rect(_art, target, false)

	# Textfreier, scharf segmentierter Fortschritt im dafür reservierten dunklen
	# unteren Bildbereich. Die schmale Lichtkante pulsiert, der Füllstand nicht.
	var bar_width := minf(size.x * 0.58, 980.0)
	var bar_height := clampf(size.y * 0.024, 16.0, 30.0)
	var bar := Rect2(Vector2((size.x - bar_width) * 0.5, size.y * 0.905),
		Vector2(bar_width, bar_height))
	draw_rect(bar.grow(7.0), Color(0.005, 0.010, 0.016, 0.94))
	draw_rect(bar.grow(3.0), Color(0.32, 0.70, 0.88, 0.72), false, 2.0)
	var segments := maxi(24, roundi(bar_width / 20.0))
	var gap := maxf(2.0, bar_width * 0.0025)
	var segment_width := (bar_width - gap * float(segments - 1)) / float(segments)
	var visible_progress := progress
	if indeterminate:
		visible_progress = maxf(visible_progress, 0.08 + fposmod(pulse_time * 0.055, 0.74))
	for index in segments:
		var ratio := float(index + 1) / float(segments)
		var active := ratio <= visible_progress + 0.0001
		var color := Color(0.22, 0.72, 0.93)
		if ratio > 0.78:
			color = Color(1.0, 0.62, 0.16)
		if not active:
			color = Color(0.028, 0.061, 0.078, 0.90)
		elif absf(ratio - visible_progress) < 0.04:
			var glow := 0.78 + 0.22 * sin(pulse_time * 6.0)
			color = color.lerp(Color.WHITE, glow * 0.22)
		draw_rect(Rect2(bar.position.x + float(index) * (segment_width + gap), bar.position.y,
			segment_width, bar.size.y), color)

	# Sehr feine Scanline verbindet generiertes Pixelbild und bestehende CRT-Art.
	for y in range(0, roundi(size.y), 4):
		draw_rect(Rect2(0.0, float(y), size.x, 1.0), Color(0.0, 0.0, 0.0, 0.055))

