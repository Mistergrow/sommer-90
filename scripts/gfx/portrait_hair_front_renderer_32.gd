class_name PortraitHairFrontRenderer32
## Zustandsloser 32×32-Frontpass für Frisuren und Stirnsilhouetten.

const Raster := preload("res://scripts/gfx/pixel_raster_32.gd")
const HairCatalog := preload("res://scripts/gfx/portrait_hair_catalog_32.gd")
const OUTLINE := Color("211922")


static func draw(img: Image, sel: Dictionary, hair: Array[Color]) -> void:
	var hat := str(sel.get("hat", ""))
	var style := HairCatalog.style_for_front(str(sel.get("hair_style", "short")), hat)
	var sweep := -1 if int(sel.get("hair_sweep", -1)) < 0 else 1
	match style:
		"bald":
			if int(sel.get("age_now", 20)) >= 48:
				Raster.line(img, 8, 10, 7, hair[3]); Raster.px(img, 8, 8, hair[4])
				Raster.line(img, 22, 24, 7, hair[3]); Raster.px(img, 24, 8, hair[4])
		"mohawk":
			_draw_mohawk(img, hair)
		"afro":
			_draw_afro(img, hair)
		"curly":
			_draw_curly(img, hair)
		"buzzcut":
			_draw_buzzcut(img, hair)
		"short":
			_draw_short(img, hair)
		"flattop":
			_draw_flattop(img, hair)
		"messy":
			_draw_messy(img, hair)
		"spiky":
			_draw_spiky(img, hair)
		"quiff":
			_draw_quiff(img, hair, sweep)
		"ponytail", "pigtails", "bun":
			_draw_pulled(img, hair, sweep)
		"mullet":
			_draw_short(img, hair)
			Raster.line(img, 7, 9, 11, hair[3]); Raster.line(img, 7, 8, 12, hair[4])
		"bob":
			_draw_parted(img, hair, true, sweep)
			Raster.vline(img, 7, 14, 20, hair[2]); Raster.vline(img, 8, 16, 21, hair[3])
			Raster.vline(img, 25, 11, 20, hair[3]); Raster.vline(img, 24, 15, 21, hair[4])
			Raster.line(img, 8, 11, 21, hair[2]); Raster.line(img, 22, 25, 21, hair[3])
		"straight":
			_draw_parted(img, hair, true, sweep)
			Raster.line(img, 9, 22, 8, hair[3]); Raster.line(img, 8, 12, 9, hair[2])
		_:
			_draw_parted(img, hair, style in ["medium", "long", "straight", "mullet"], sweep)


static func _shape(img: Image, rows: Array, fill: Color, shade: Color) -> void:
	Raster.shape(img, rows, fill, shade, OUTLINE)


static func _draw_buzzcut(img: Image, hair: Array[Color]) -> void:
	var rows := [[4, 11, 21], [5, 9, 23], [6, 8, 24], [7, 8, 24], [8, 9, 23]]
	_shape(img, rows, hair[3], hair[4])
	Raster.line(img, 11, 18, 5, hair[2]); Raster.line(img, 9, 14, 6, hair[1])
	Raster.line(img, 18, 23, 7, hair[4])


static func _draw_short(img: Image, hair: Array[Color]) -> void:
	var rows := [[2, 12, 20], [3, 9, 23], [4, 8, 24], [5, 7, 25],
		[6, 7, 25], [7, 7, 24], [8, 8, 22], [9, 8, 19]]
	_shape(img, rows, hair[2], hair[4])
	Raster.line(img, 11, 18, 3, hair[0]); Raster.line(img, 9, 15, 4, hair[1])
	Raster.line(img, 17, 23, 5, hair[3]); Raster.line(img, 8, 13, 7, hair[1])


static func _draw_flattop(img: Image, hair: Array[Color]) -> void:
	var rows := [[1, 9, 23], [2, 8, 24], [3, 8, 24], [4, 8, 24],
		[5, 8, 24], [6, 9, 23], [7, 9, 22]]
	_shape(img, rows, hair[2], hair[4])
	Raster.line(img, 10, 22, 1, hair[0]); Raster.line(img, 9, 17, 2, hair[1])
	Raster.vline(img, 9, 3, 6, hair[3]); Raster.line(img, 10, 20, 7, hair[4])


static func _draw_messy(img: Image, hair: Array[Color]) -> void:
	_draw_short(img, hair)
	Raster.line(img, 9, 11, 2, hair[2]); Raster.px(img, 10, 1, hair[1])
	Raster.line(img, 14, 16, 2, hair[1]); Raster.px(img, 15, 0, hair[2]); Raster.px(img, 15, 1, hair[2])
	Raster.line(img, 19, 21, 2, hair[3]); Raster.px(img, 20, 1, hair[2])
	Raster.line(img, 23, 24, 4, hair[3]); Raster.px(img, 24, 3, hair[2])


static func _draw_spiky(img: Image, hair: Array[Color]) -> void:
	var rows := [[3, 7, 25], [4, 7, 25], [5, 7, 25], [6, 8, 24],
		[7, 8, 23], [8, 9, 21]]
	_shape(img, rows, hair[2], hair[4])
	for p: Vector2i in [Vector2i(8, 1), Vector2i(13, 0), Vector2i(18, 0), Vector2i(23, 1)]:
		Raster.px(img, p.x, p.y, OUTLINE); Raster.px(img, p.x, p.y + 1, hair[2])
		Raster.px(img, p.x + 1, p.y + 1, hair[3]); Raster.px(img, p.x, p.y + 2, hair[2])
	Raster.line(img, 9, 15, 4, hair[1]); Raster.line(img, 18, 23, 5, hair[3])


static func _draw_quiff(img: Image, hair: Array[Color], sweep: int) -> void:
	_draw_short(img, hair)
	if sweep < 0:
		_shape(img, [[0, 9, 15], [1, 8, 18], [2, 9, 21]], hair[2], hair[4])
		Raster.line(img, 10, 15, 0, hair[1]); Raster.line(img, 9, 16, 1, hair[3])
	else:
		_shape(img, [[0, 17, 23], [1, 14, 24], [2, 11, 23]], hair[2], hair[4])
		Raster.line(img, 17, 22, 0, hair[1]); Raster.line(img, 16, 23, 1, hair[3])


static func _draw_pulled(img: Image, hair: Array[Color], sweep: int) -> void:
	var rows := [[3, 12, 20], [4, 9, 23], [5, 8, 24], [6, 8, 24],
		[7, 8, 23], [8, 9, 22]]
	_shape(img, rows, hair[3], hair[4])
	if sweep < 0:
		Raster.line(img, 10, 20, 4, hair[1]); Raster.line(img, 9, 17, 5, hair[2])
	else:
		Raster.line(img, 13, 22, 4, hair[1]); Raster.line(img, 15, 23, 5, hair[2])
	Raster.line(img, 9, 22, 8, hair[4])


static func _draw_curly(img: Image, hair: Array[Color]) -> void:
	var rows := [[1, 12, 20], [2, 8, 24], [3, 6, 26], [4, 5, 27],
		[5, 5, 27], [6, 4, 27], [7, 5, 27], [8, 5, 25], [9, 6, 23], [10, 6, 11]]
	_shape(img, rows, hair[2], hair[4])
	for p: Vector2i in [Vector2i(8, 2), Vector2i(15, 1), Vector2i(22, 2),
		Vector2i(6, 5), Vector2i(25, 5), Vector2i(6, 8), Vector2i(23, 8)]:
		Raster.px(img, p.x, p.y, hair[0]); Raster.px(img, p.x + 1, p.y, hair[1])
	Raster.line(img, 11, 15, 4, hair[1]); Raster.line(img, 17, 22, 5, hair[3])


static func _draw_parted(img: Image, hair: Array[Color], long_side: bool, sweep: int) -> void:
	var crown := [[2, 12, 19], [3, 9, 22], [4, 8, 24], [5, 7, 25],
		[6, 7, 25], [7, 7, 24], [8, 8, 22], [9, 8, 19]]
	_shape(img, crown, hair[2], hair[4])
	Raster.line(img, 13, 18, 3, hair[1]); Raster.line(img, 11, 16, 4, hair[0])
	Raster.line(img, 9, 13, 5, hair[1]); Raster.line(img, 8, 12, 6, hair[2])
	Raster.line(img, 17, 23, 4, hair[3]); Raster.line(img, 19, 24, 5, hair[3])
	Raster.line(img, 16, 22, 6, hair[2]); Raster.line(img, 15, 21, 7, hair[1])
	Raster.line(img, 8, 11, 8, hair[3]); Raster.line(img, 8, 10, 9, hair[4])
	Raster.line(img, 17, 19, 8, hair[1])
	Raster.line(img, 7, 9, 10, hair[3]); Raster.line(img, 7, 9, 11, hair[2])
	Raster.line(img, 7, 8, 12, hair[3]); Raster.line(img, 7, 8, 13, hair[4])
	Raster.line(img, 23, 25, 8, hair[3]); Raster.line(img, 24, 25, 9, hair[4])
	if sweep < 0:
		Raster.px(img, 7, 9, hair[3]); Raster.px(img, 6, 10, hair[2]); Raster.px(img, 6, 11, hair[3])
	else:
		Raster.px(img, 25, 8, hair[3]); Raster.px(img, 26, 9, hair[2]); Raster.px(img, 26, 10, hair[3])
	if long_side:
		Raster.line(img, 6, 8, 14, hair[2]); Raster.line(img, 6, 8, 15, hair[3])
		Raster.line(img, 6, 7, 16, hair[4]); Raster.line(img, 24, 26, 10, hair[3])
		Raster.line(img, 25, 26, 11, hair[4])


static func _draw_afro(img: Image, hair: Array[Color]) -> void:
	var crown := [[1, 11, 20], [2, 7, 24], [3, 5, 26], [4, 4, 27],
		[5, 4, 27], [6, 3, 28], [7, 4, 28], [8, 4, 26], [9, 5, 24], [10, 5, 12]]
	_shape(img, crown, hair[2], hair[4])
	Raster.line(img, 8, 14, 2, hair[1]); Raster.line(img, 6, 11, 3, hair[0])
	Raster.line(img, 5, 9, 5, hair[1]); Raster.line(img, 13, 19, 3, hair[3])
	Raster.line(img, 18, 24, 4, hair[1]); Raster.line(img, 22, 27, 6, hair[3])
	Raster.line(img, 6, 11, 7, hair[3]); Raster.line(img, 5, 9, 9, hair[4])
	Raster.px(img, 4, 4, hair[0]); Raster.px(img, 27, 5, hair[1]); Raster.px(img, 3, 7, hair[3])
	for p: Vector2i in [Vector2i(7, 2), Vector2i(23, 3), Vector2i(5, 5),
		Vector2i(26, 7), Vector2i(4, 9), Vector2i(8, 10), Vector2i(24, 9)]:
		Raster.px(img, p.x, p.y, hair[4])
	Raster.line(img, 14, 17, 5, hair[0]); Raster.line(img, 12, 15, 6, hair[1])


static func _draw_mohawk(img: Image, hair: Array[Color]) -> void:
	var rows := [[0, 13, 17], [1, 11, 18], [2, 10, 19], [3, 11, 20],
		[4, 10, 20], [5, 11, 21], [6, 12, 21], [7, 13, 20]]
	_shape(img, rows, hair[2], hair[4])
	Raster.line(img, 14, 16, 0, hair[0]); Raster.line(img, 12, 16, 1, hair[1])
	Raster.line(img, 11, 14, 2, hair[0]); Raster.line(img, 15, 18, 3, hair[3])
	Raster.line(img, 12, 15, 4, hair[1]); Raster.line(img, 16, 19, 5, hair[3])
	Raster.px(img, 10, 3, hair[4]); Raster.px(img, 20, 4, hair[4])
