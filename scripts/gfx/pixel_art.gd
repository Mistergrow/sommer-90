class_name PixelArt
## Erzeugt Texturen aus ASCII-Pixelkarten.
## Platzhalter-Pipeline des MVP: Jede Grafik ist ein Array von Strings,
## jedes Zeichen wird über eine Farbtabelle auf einen Palettenwert gemappt.
## Finale, handgemalte Sprites können diese Texturen später 1:1 ersetzen.


## rows: Array von Strings (Pixelzeilen), map: {Zeichen: Color}.
## Zeichen ohne Eintrag (z. B. ".") bleiben transparent.
static func make_texture(rows: Array, map: Dictionary) -> ImageTexture:
	var height := rows.size()
	var width := 0
	for row in rows:
		width = maxi(width, String(row).length())
	var img := Image.create(maxi(width, 1), maxi(height, 1), false, Image.FORMAT_RGBA8)
	for y in height:
		var row := String(rows[y])
		for x in row.length():
			var ch := row[x]
			if map.has(ch):
				img.set_pixel(x, y, map[ch])
	return ImageTexture.create_from_image(img)


## Einfarbige Textur (für Platzhalterflächen mit Textur-Slots).
static func solid(width: int, height: int, color: Color) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
