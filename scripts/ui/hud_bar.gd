class_name HudBar
extends Control
## Segmentierter Statusbalken im Bezel-/LCD-Stil: dunkler Rahmen, dunkle Wanne,
## Füllung mit hellem Glanzstreifen obenauf. Von der Top-Bar (Energie, Level)
## und der Bottom-Bar (Müde/Hunger/Sauberkeit) gemeinsam genutzt — damit ALLE
## Balken exakt gleich aussehen.

var value := 100.0:
	set(v):
		var nv := clampf(v, 0.0, 100.0)
		if _inited and absf(nv - value) >= 0.5:
			_flash = 1.0                    # spürbare Änderung → kurz aufblitzen
		value = nv
		if not _inited:
			_shown = value                  # erster Wert: sofort, kein Auffahren
			_inited = true
			queue_redraw()
		else:
			set_process(true)               # danach: sanft dorthin gleiten
var fill_color := Palette.LCD_AMBER:
	set(v):
		fill_color = v
		queue_redraw()
var value_text := "":
	set(v):
		value_text = v
		queue_redraw()
var show_value_text := false
var text_color := Palette.UI_TEXT

var _shown := 100.0     # animierter Anzeigewert
var _flash := 0.0       # 1→0 nach einer Änderung (Glanz-Puls)
var _inited := false


func _process(delta: float) -> void:
	_shown = lerpf(_shown, value, minf(1.0, delta * 11.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.2)
	if absf(_shown - value) < 0.25 and _flash <= 0.0:
		_shown = value
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, Color8(5, 5, 5), true)
	draw_rect(outer, Color8(36, 36, 34), false, 1.0)
	var inner := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	draw_rect(inner, Color8(10, 10, 9), true)
	var fill := inner
	fill.size.x = floor(inner.size.x * _shown / 100.0)
	if fill.size.x > 0.0:
		var fc := fill_color.lightened(0.35 * _flash)   # Puls beim Ändern
		draw_rect(fill, fc, true)
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, maxf(1.0, fill.size.y * 0.35))),
			fc.lightened(0.18), true)
		# heller Vorderkanten-Glanz, während der Balken sich bewegt
		if absf(_shown - value) > 0.5 or _flash > 0.05:
			draw_rect(Rect2(fill.end.x - 2.0, inner.position.y, 2.0, inner.size.y),
				fill_color.lightened(0.6), true)
	if show_value_text and value_text != "":
		var font := get_theme_font("font", "Label")
		draw_string(font, Vector2(5, size.y - 3), value_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)
