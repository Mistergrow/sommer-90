extends RefCounted
## Gemeinsame, integergenaue Rasterprimitive für 32er Porträts und Figuren.
## Alle Grenzen stammen aus dem Zielbild, daher funktioniert derselbe Code für
## 32×32 und 32×48 ohne versteckte globale Größenannahmen.


static func px(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height():
		image.set_pixel(x, y, color)


static func line(image: Image, x0: int, x1: int, y: int, color: Color) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		px(image, x, y, color)


static func vline(image: Image, x: int, y0: int, y1: int, color: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		px(image, x, y, color)


static func rect(image: Image, x: int, y: int, width: int, height: int,
		color: Color) -> void:
	for row in range(y, y + height):
		line(image, x, x + width - 1, row, color)


static func segment(image: Image, start: Vector2i, finish: Vector2i,
		radius: int, color: Color) -> void:
	var steps := maxi(absi(finish.x - start.x), absi(finish.y - start.y))
	if steps == 0:
		rect(image, start.x - radius, start.y - radius,
			radius * 2 + 1, radius * 2 + 1, color)
		return
	for index in range(steps + 1):
		var weight := float(index) / float(steps)
		var point := Vector2i(
			roundi(lerpf(start.x, finish.x, weight)),
			roundi(lerpf(start.y, finish.y, weight)))
		rect(image, point.x - radius, point.y - radius,
			radius * 2 + 1, radius * 2 + 1, color)


static func outline(image: Image, color: Color, alpha_threshold := 0.4) -> void:
	var source := image.duplicate()
	for y in image.get_height():
		for x in image.get_width():
			if source.get_pixel(x, y).a > alpha_threshold:
				continue
			for direction: Vector2i in [
				Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			]:
				var next := Vector2i(x, y) + direction
				if next.x >= 0 and next.x < image.get_width() \
						and next.y >= 0 and next.y < image.get_height() \
						and source.get_pixelv(next).a > alpha_threshold:
					image.set_pixel(x, y, color)
					break


static func shape(image: Image, rows: Array, fill: Color, shade: Color,
		outline_color: Color) -> void:
	for raw: Variant in rows:
		var row: Array = raw
		var y := int(row[0])
		var x0 := int(row[1])
		var x1 := int(row[2])
		line(image, x0, x1, y, outline_color)
		if x1 - x0 > 1:
			line(image, x0 + 1, x1 - 1, y, fill)
			if row.size() >= 4:
				line(image, maxi(x0 + 1, int(row[3])), x1 - 1, y, shade)


static func material_px(image: Image, x: int, y: int,
		source_colors: Array[Color], color: Color) -> void:
	if x < 0 or x >= image.get_width() or y < 0 or y >= image.get_height():
		return
	var current := image.get_pixel(x, y)
	for sample: Color in source_colors:
		if current.is_equal_approx(sample):
			image.set_pixel(x, y, color)
			return


static func material_line(image: Image, x0: int, x1: int, y: int,
		source_colors: Array[Color], color: Color) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		material_px(image, x, y, source_colors, color)
