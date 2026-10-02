extends Control
var kind := "day"
var title := "HEUTE WICHTIG"
var subtitle := ""
var prompt := "WEITER DRUECKEN, WENN DU BEREIT BIST"
var font: Font = load("res://assets/fonts/VT323_UI.ttf")

func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size).grow(-2.0)
	draw_rect(area, Color(0.025, 0.055, 0.085, 0.98))
	draw_rect(area, Color8(55, 205, 218), false, 2.0)
	# Blockige Horizontlinien und Eckmarker erzeugen einen echten Szenekarten-Look.
	for y in range(4, int(size.y) - 4, 4):
		draw_line(Vector2(3, y), Vector2(size.x - 3, y), Color(0, 0, 0, 0.12), 1.0)
	for p in [Vector2(7, 7), Vector2(size.x - 15, 7), Vector2(7, size.y - 15), Vector2(size.x - 15, size.y - 15)]:
		draw_rect(Rect2(p, Vector2(8, 8)), Color8(246, 166, 44))
	_draw_icon(Vector2(22, 18))
	draw_string(font, Vector2(154, 55), title, HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 176, 30, Color8(255, 218, 102))
	draw_string(font, Vector2(154, 86), subtitle, HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 176, 15, Color8(210, 235, 238))
	draw_string(font, Vector2(154, 108), prompt,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 176, 12, Color8(100, 205, 150))

func _draw_icon(origin: Vector2) -> void:
	match kind:
		"flea": _flea(origin)
		"club": _club(origin)
		"birthday": _birthday(origin)
		_: _calendar(origin)

func _flea(o: Vector2) -> void:
	# Marktstand, gestreifte Markise, Kisten und rote Funddiskette.
	for i in 6:
		draw_rect(Rect2(o + Vector2(i * 18, 0), Vector2(18, 18)),
			Color8(232, 72, 66) if i % 2 == 0 else Color8(246, 222, 174))
	draw_rect(Rect2(o + Vector2(4, 18), Vector2(100, 58)), Color8(137, 82, 43))
	draw_rect(Rect2(o + Vector2(12, 45), Vector2(34, 28)), Color8(190, 126, 62))
	draw_rect(Rect2(o + Vector2(60, 36), Vector2(34, 34)), Color8(178, 48, 52))
	draw_rect(Rect2(o + Vector2(68, 39), Vector2(18, 12)), Color8(244, 230, 194))

func _club(o: Vector2) -> void:
	draw_rect(Rect2(o, Vector2(108, 76)), Color8(116, 118, 112))
	draw_rect(Rect2(o + Vector2(10, 9), Vector2(88, 49)), Color8(4, 12, 32))
	for i in 18:
		var x := 14 + (i * 37) % 78
		var y := 13 + (i * 23) % 39
		draw_rect(Rect2(o + Vector2(x, y), Vector2(2, 2)), Color8(110, 220, 240))
	draw_rect(Rect2(o + Vector2(40, 62), Vector2(28, 6)), Color8(36, 38, 42))
	draw_string(font, o + Vector2(0, 94), "CCC", HORIZONTAL_ALIGNMENT_CENTER, 108, 20, Color8(246, 166, 44))

func _birthday(o: Vector2) -> void:
	draw_rect(Rect2(o + Vector2(8, 46), Vector2(92, 34)), Color8(218, 108, 134))
	draw_rect(Rect2(o + Vector2(14, 34), Vector2(80, 16)), Color8(250, 220, 150))
	for x in [28, 54, 80]:
		draw_rect(Rect2(o + Vector2(x, 15), Vector2(5, 20)), Color8(90, 205, 220))
		draw_rect(Rect2(o + Vector2(x - 2, 8), Vector2(9, 8)), Color8(250, 166, 46))

func _calendar(o: Vector2) -> void:
	draw_rect(Rect2(o + Vector2(8, 8), Vector2(92, 78)), Color8(240, 232, 208))
	draw_rect(Rect2(o + Vector2(8, 8), Vector2(92, 20)), Color8(184, 48, 54))
	for y in 3:
		for x in 5:
			draw_rect(Rect2(o + Vector2(17 + x * 16, 38 + y * 14), Vector2(8, 7)), Color8(44, 72, 92))
