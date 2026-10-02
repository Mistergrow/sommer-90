class_name ChunkyVehicles
## ChunkyVehicles — kleine Reise-Sprites (Fahrrad, Auto, Bus) im Chunky-Pixel-Stil.
## Aus chunky_avatar.gd ausgelagert (eine Datei = ein Job); nutzt dessen
## Zeichen-Helfer (_px/_rect/_outline) als statische Aufrufe.

const FIGURE_PAINT := preload("res://scripts/gfx/figure_paint_32.gd")

static func _ring(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for a in 24:
		var t := float(a) / 24.0 * TAU
		ChunkyAvatar._px(img, cx + int(round(cos(t) * r)), cy + int(round(sin(t) * r)), c)


static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		ChunkyAvatar._px(img, x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy: err += dy; x0 += sx
		if e2 <= dx: err += dx; y0 += sy


## Kleines Fahrrad (Seitenansicht) — Overlay unter die Figur für die Rad-Reise.
static func bike(px: int = 24) -> ImageTexture:
	var img := Image.create(px, 14, false, Image.FORMAT_RGBA8)
	var d := Color(0.12, 0.12, 0.15)
	var m := Color(0.55, 0.12, 0.12)      # Rahmen (rot)
	var wl := 4
	var lx := wl + 1
	var rx := px - wl - 2
	_ring(img, lx, 9, wl, d); _ring(img, lx, 9, wl - 2, d)
	_ring(img, rx, 9, wl, d); _ring(img, rx, 9, wl - 2, d)
	ChunkyAvatar._px(img, lx, 9, d); ChunkyAvatar._px(img, rx, 9, d)                 # Naben
	var seat := floori(px / 2.0)
	_line(img, lx, 9, seat, 3, m); _line(img, seat, 3, rx, 9, m)  # Rahmen-Dreieck
	_line(img, seat, 3, lx + 2, 9, m)
	_line(img, rx, 9, rx, 3, d)                            # Lenker-Vorbau
	ChunkyAvatar._rect(img, rx - 1, 2, 4, 1, d)                         # Lenker
	ChunkyAvatar._rect(img, seat - 1, 2, 3, 1, d)                       # Sattel
	ChunkyAvatar._outline(img)
	return ImageTexture.create_from_image(img)


## Gemeinsames Fahrer/Fahrrad-Sprite fuer die Stadtkarte. Der alte Aufbau legte
## eine stehende 32x48-Figur ueber ein separates Fahrrad. Hier entstehen Kopf,
## sitzender Rumpf, angewinkelte Arme und pedalierende Beine auf EINEM nativen
## 48x42-Raster. Kopf/Haar/Brille kommen weiterhin aus derselben Avatar-DNA.
static func cyclist(id: String, hints: Dictionary = {}, pedal_frame: int = 0,
		faces_right: bool = true) -> ImageTexture:
	var img := Image.create(48, 42, false, Image.FORMAT_RGBA8)
	var dna: Dictionary = ChunkyAvatar.dna(id, hints)
	var skin: Color = dna.get("skin", Color8(216, 166, 126))
	var shirt: Color = dna.get("shirt", Color8(42, 126, 133))
	var pants: Color = dna.get("shorts", Color8(55, 68, 102))
	var metal := Color8(196, 204, 214)
	var tyre := Color8(28, 27, 33)
	var frame := Color8(202, 54, 48)
	var outline := Color8(28, 24, 31)

	# Fahrrad und Schatten liegen hinter der Figur.
	ChunkyAvatar._rect(img, 5, 39, 38, 2, Color(0.03, 0.03, 0.04, 0.28))
	_ring(img, 11, 34, 6, tyre)
	_ring(img, 37, 34, 6, tyre)
	_ring(img, 11, 34, 4, metal.darkened(0.24))
	_ring(img, 37, 34, 4, metal.darkened(0.24))
	ChunkyAvatar._px(img, 11, 34, metal)
	ChunkyAvatar._px(img, 37, 34, metal)
	var crank := Vector2i(24, 33)
	var seat := Vector2i(21, 24)
	var stem := Vector2i(35, 21)
	_line(img, 11, 34, seat.x, seat.y, frame)
	_line(img, seat.x, seat.y, crank.x, crank.y, frame)
	_line(img, crank.x, crank.y, 11, 34, frame)
	_line(img, crank.x, crank.y, 37, 34, frame)
	_line(img, seat.x, seat.y, 37, 34, frame)
	_line(img, 37, 34, stem.x, stem.y, metal.darkened(0.52))
	_line(img, stem.x - 1, stem.y, 40, stem.y, tyre)
	ChunkyAvatar._rect(img, seat.x - 3, seat.y - 1, 6, 2, tyre)

	# Vier Pedalphasen: Knie/Fuss bewegen sich gegensinnig, ohne dass der Fahrer
	# vom Sattel springt. So liest sich die Bewegung auch auf dem kleinen Raster.
	var phase := posmod(pedal_frame, 4)
	var pedal_offsets := [Vector2i(4, 0), Vector2i(0, 3), Vector2i(-4, 0), Vector2i(0, -3)]
	var near_pedal: Vector2i = crank + pedal_offsets[phase]
	var far_pedal: Vector2i = crank - pedal_offsets[phase]
	var hip := Vector2i(22, 23)
	var far_knee := Vector2i(18, 28)
	var near_knee := Vector2i(28, 27)
	_line(img, hip.x, hip.y, far_knee.x, far_knee.y, pants.darkened(0.25))
	_line(img, far_knee.x, far_knee.y, far_pedal.x, far_pedal.y, pants.darkened(0.25))
	_line(img, hip.x + 1, hip.y, near_knee.x, near_knee.y, pants)
	_line(img, near_knee.x, near_knee.y, near_pedal.x, near_pedal.y, pants)
	ChunkyAvatar._rect(img, far_pedal.x - 2, far_pedal.y, 4, 2, outline)
	ChunkyAvatar._rect(img, near_pedal.x - 1, near_pedal.y, 5, 2, outline)

	# Nach vorn geneigter Oberkoerper mit echten Griffarmen.
	for y in range(15, 25):
		var left := 18 + int((y - 15) * 0.20)
		var right := 27 + int((y - 15) * 0.12)
		ChunkyAvatar._rect(img, left, y, right - left + 1, 1, shirt)
		ChunkyAvatar._px(img, left, y, shirt.lightened(0.18))
		ChunkyAvatar._px(img, right, y, shirt.darkened(0.28))
	_line(img, 26, 17, 31, 20, shirt.darkened(0.18))
	_line(img, 31, 20, 36, 21, skin)
	ChunkyAvatar._rect(img, 35, 20, 3, 2, skin.lightened(0.12))
	_line(img, 24, 18, 29, 21, shirt)
	_line(img, 29, 21, 34, 22, skin.darkened(0.08))

	# Identischer Kopf wie die stehende Figur. Nur der native Kopfbereich wird
	# uebernommen; damit bleiben Alter, Frisur, Brille und Gesicht erhalten.
	var figure := FIGURE_PAINT.image(id, hints, {"blink": false, "gaze": 1})
	img.blit_rect(figure, Rect2i(4, 0, 24, 17), Vector2i(10, 0))
	ChunkyAvatar._outline(img)
	if not faces_right:
		img.flip_x()
	return ImageTexture.create_from_image(img)


## Kompakter 90er-Jahre-Hatchback für die Stadtkarte. Karosserie, Verglasung,
## Fahrer und rotierende Räder liegen auf einem gemeinsamen 64×36-Raster, damit
## weder Perspektive noch Layer beim Richtungswechsel auseinanderfallen.
static func car(id: String, hints: Dictionary = {}, wheel_frame: int = 0,
		faces_right: bool = true) -> ImageTexture:
	var img := Image.create(64, 36, false, Image.FORMAT_RGBA8)
	var dna: Dictionary = ChunkyAvatar.dna(id, hints)
	var skin: Color = dna.get("skin", Color8(216, 166, 126))
	var shirt: Color = dna.get("shirt", Color8(42, 126, 133))
	var hair: Color = dna.get("hair", Color8(82, 48, 34))
	var body := Color8(178, 42, 49)
	var body_light := Color8(228, 72, 64)
	var body_dark := Color8(104, 31, 43)
	var glass := Color8(90, 142, 164)
	var glass_light := Color8(164, 207, 215)
	var rubber := Color8(25, 25, 31)
	var metal := Color8(190, 199, 205)
	var outline := Color8(28, 24, 31)

	# Fahrbahnschatten und geschlossene Grundsilhouette.
	ChunkyAvatar._rect(img, 4, 31, 56, 3, Color(0.02, 0.02, 0.03, 0.28))
	ChunkyAvatar._rect(img, 5, 18, 54, 11, body)
	ChunkyAvatar._rect(img, 8, 15, 47, 9, body)
	ChunkyAvatar._rect(img, 15, 9, 31, 10, body)
	ChunkyAvatar._rect(img, 20, 6, 20, 5, body)
	ChunkyAvatar._rect(img, 7, 18, 49, 2, body_light)
	ChunkyAvatar._rect(img, 6, 27, 52, 2, body_dark)
	ChunkyAvatar._rect(img, 2, 21, 5, 6, body_dark)
	ChunkyAvatar._rect(img, 58, 20, 4, 7, body_dark)

	# Fensterband mit B-Säule. Der Fahrer sitzt vorne (rechts in der
	# ungespiegelten Fassung) und bleibt durch Haut/Haar/Shirt lesbar.
	ChunkyAvatar._rect(img, 19, 9, 20, 8, glass)
	ChunkyAvatar._rect(img, 41, 13, 10, 5, glass)
	ChunkyAvatar._rect(img, 30, 9, 2, 9, body_dark)
	ChunkyAvatar._rect(img, 19, 9, 20, 1, glass_light)
	ChunkyAvatar._rect(img, 42, 13, 8, 1, glass_light)
	ChunkyAvatar._rect(img, 35, 12, 5, 5, shirt.darkened(0.12))
	ChunkyAvatar._rect(img, 36, 9, 4, 4, skin)
	ChunkyAvatar._rect(img, 35, 8, 5, 2, hair)
	ChunkyAvatar._px(img, 39, 11, outline)
	ChunkyAvatar._rect(img, 42, 16, 4, 1, outline) # Lenkradkante

	# Stoßfänger, Leuchten, Türfugen und Griff schaffen auch bei 1:1 eine
	# erkennbare Fahrtrichtung und vermeiden die alte generische Bus-Silhouette.
	ChunkyAvatar._rect(img, 2, 26, 7, 2, metal.darkened(0.25))
	ChunkyAvatar._rect(img, 56, 26, 7, 2, metal.darkened(0.25))
	ChunkyAvatar._rect(img, 59, 20, 3, 3, Color8(255, 225, 118))
	ChunkyAvatar._rect(img, 3, 20, 2, 3, Color8(185, 35, 38))
	_line(img, 31, 18, 31, 27, body_dark)
	ChunkyAvatar._rect(img, 35, 20, 5, 1, metal)

	# Vier klar unterscheidbare Radphasen. Speichen werden nicht weich rotiert,
	# sondern bleiben bewusst im AGA-Sprite-Raster.
	var phase := posmod(wheel_frame, 4)
	var wheel_centres := [Vector2i(15, 28), Vector2i(50, 28)]
	for centre: Vector2i in wheel_centres:
		_ring(img, centre.x, centre.y, 6, rubber)
		_ring(img, centre.x, centre.y, 4, metal.darkened(0.22))
		ChunkyAvatar._px(img, centre.x, centre.y, metal.lightened(0.18))
		match phase:
			0, 2:
				_line(img, centre.x - 3, centre.y, centre.x + 3, centre.y, outline)
				_line(img, centre.x, centre.y - 3, centre.x, centre.y + 3, outline)
			_:
				_line(img, centre.x - 2, centre.y - 2, centre.x + 2, centre.y + 2, outline)
				_line(img, centre.x + 2, centre.y - 2, centre.x - 2, centre.y + 2, outline)

	ChunkyAvatar._outline(img)
	if not faces_right:
		img.flip_x()
	return ImageTexture.create_from_image(img)


## Kleiner Stadtbus (Seitenansicht) für die Bus-Reise.
static func bus(w: int = 42, h: int = 22, col: Color = Color(0.86, 0.66, 0.16)) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var body := col
	var dark := col.darkened(0.28)
	var glass := Color(0.55, 0.72, 0.82)
	ChunkyAvatar._rect(img, 1, 2, w - 2, h - 6, body)                  # Karosserie
	ChunkyAvatar._rect(img, 1, 2, w - 2, 2, col.lightened(0.12))       # Dachkante hell
	ChunkyAvatar._rect(img, 1, h - 8, w - 2, 1, dark)                  # Zierstreifen
	for i in range(floori((w - 8) / 6.0)):                 # Fenster
		ChunkyAvatar._rect(img, 5 + i * 6, 5, 4, 5, glass)
	ChunkyAvatar._rect(img, w - 7, 5, 3, 7, glass)                     # Frontscheibe
	ChunkyAvatar._rect(img, 3, 11, 3, 3, Color(0.15, 0.15, 0.18))      # Tür
	var wy := h - 4
	_ring(img, 9, wy, 3, Color(0.1, 0.1, 0.12)); ChunkyAvatar._px(img, 9, wy, Color(0.4, 0.4, 0.44))
	_ring(img, w - 10, wy, 3, Color(0.1, 0.1, 0.12)); ChunkyAvatar._px(img, w - 10, wy, Color(0.4, 0.4, 0.44))
	ChunkyAvatar._px(img, 0, 6, Color(0.95, 0.85, 0.4))                # Scheinwerfer
	ChunkyAvatar._outline(img)
	return ImageTexture.create_from_image(img)
