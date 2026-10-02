class_name UiPaint
## UiPaint — gemeinsame UI-Zeichenprimitive für die virtuellen Programm-
## bildschirme (Werkbank, X-COPY). Bislang war button3d in wb_app.gd und
## xcopy_screen.gd Zeile für Zeile doppelt; hier einmal, koordinaten-neutral:
## `xf` ist die Virtuell→Bildschirm-Abbildung des jeweiligen Screens (_R).


## Plastischer 3D-Knopf (heller Rahmen oben/links, dunkler unten/rechts;
## gedrückt = invertiert). Rechtecke in Virtual-Koordinaten, `xf` bildet ab,
## `ci` ist der CanvasItem, auf dem gezeichnet wird.
static func button3d(ci: CanvasItem, xf: Callable, r: Rect2, base: Color, down: bool) -> void:
	ci.draw_rect(xf.call(r), base.darkened(0.12) if down else base)
	var light: Color = base.lightened(0.55)
	var dark: Color = base.darkened(0.55)
	var tl: Color = dark if down else light
	var br: Color = light if down else dark
	ci.draw_rect(xf.call(Rect2(r.position.x, r.position.y, r.size.x, 1)), tl)
	ci.draw_rect(xf.call(Rect2(r.position.x, r.position.y, 1, r.size.y)), tl)
	ci.draw_rect(xf.call(Rect2(r.position.x, r.position.y + r.size.y - 1, r.size.x, 1)), br)
	ci.draw_rect(xf.call(Rect2(r.position.x + r.size.x - 1, r.position.y, 1, r.size.y)), br)
