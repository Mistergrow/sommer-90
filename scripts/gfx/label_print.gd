class_name LabelPrint
extends RefCounted
## Etikett-DRUCK für den Kopien-Handel (rein prozedural, headless-sicher).
## Stufen (Disk.label_quality):
##   1 = handschriftlich (krakelige Linie)      — ohne Drucker
##   2 = 9-Nadel-Titel   (lückige Punktschrift) — dot_matrix
##   3 = 24-Nadel-Titel  (dichte Punktschrift)  — dot_matrix_24 / laser
##   4 = FARBDRUCK: Spiele-Artwork als CMY-Tintenraster (Filter über dem PNG)
## Ergebnis wird als Sticker (Base64-PNG) an der Diskette gespeichert und vom
## DiskComposer gerendert — gleiche Pipeline wie der Etikett-Designer.

const W := 88          # Etikett-Pixelmaß (Hochformat-Label der Composer-Pipeline)
const H := 52
const PAPER := Color8(236, 232, 218)
const INK := Color8(34, 38, 52)
const StefanCatalog := preload("res://scripts/games/stefan_game_catalog.gd")

## Winziger 5x7-Pixelfont (A–Z, 0–9, Sonderzeichen) — jede Glyphe 7 Zeilen à 5 Bit.
const FONT := {
	"A": [14, 17, 17, 31, 17, 17, 17], "B": [30, 17, 17, 30, 17, 17, 30],
	"C": [14, 17, 16, 16, 16, 17, 14], "D": [30, 17, 17, 17, 17, 17, 30],
	"E": [31, 16, 16, 30, 16, 16, 31], "F": [31, 16, 16, 30, 16, 16, 16],
	"G": [14, 17, 16, 23, 17, 17, 15], "H": [17, 17, 17, 31, 17, 17, 17],
	"I": [14, 4, 4, 4, 4, 4, 14], "J": [7, 2, 2, 2, 2, 18, 12],
	"K": [17, 18, 20, 24, 20, 18, 17], "L": [16, 16, 16, 16, 16, 16, 31],
	"M": [17, 27, 21, 21, 17, 17, 17], "N": [17, 25, 21, 19, 17, 17, 17],
	"O": [14, 17, 17, 17, 17, 17, 14], "P": [30, 17, 17, 30, 16, 16, 16],
	"Q": [14, 17, 17, 17, 21, 18, 13], "R": [30, 17, 17, 30, 20, 18, 17],
	"S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4],
	"U": [17, 17, 17, 17, 17, 17, 14], "V": [17, 17, 17, 17, 17, 10, 4],
	"W": [17, 17, 17, 21, 21, 27, 17], "X": [17, 17, 10, 4, 10, 17, 17],
	"Y": [17, 17, 10, 4, 4, 4, 4], "Z": [31, 1, 2, 4, 8, 16, 31],
	"0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14],
	"2": [14, 17, 1, 2, 4, 8, 31], "3": [14, 17, 1, 6, 1, 17, 14],
	"4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 30, 1, 1, 17, 14],
	"6": [6, 8, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8],
	"8": [14, 17, 17, 14, 17, 17, 14], "9": [14, 17, 17, 15, 1, 2, 12],
	"-": [0, 0, 0, 14, 0, 0, 0], ".": [0, 0, 0, 0, 0, 12, 12],
	"'": [4, 4, 8, 0, 0, 0, 0], "!": [4, 4, 4, 4, 4, 0, 4],
	" ": [0, 0, 0, 0, 0, 0, 0],
}


## Etikett je Stufe erzeugen. Für Stufe 4 wird das Artwork der Software geladen
## und durch den Nadel-Raster-Filter gejagt (das „Kopien-Logo").
static func make(disk: Disk, stage: int) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(PAPER)
	var title := disk.content_title if disk.content_title != "" else disk.display_name()
	match stage:
		2:
			_print_title(img, title, false)
		3:
			_print_title(img, title, true)
		4:
			if not _print_art(img, disk.software_id):
				_print_color_logo(img, title, disk.software_id)
			_color_footer(img, title)
		_:
			_handwritten(img, title)
	return img


# ------------------------------------------------------------- Stufe 1: Hand
static func _handwritten(img: Image, title: String) -> void:
	# Krakelige Beschriftung: Punktlinie mit Zufalls-Wackler + zwei „Linien".
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(title)
	for line_y in [16, 34]:
		for x in range(6, W - 6):
			img.set_pixel(x, line_y + 6, Color8(150, 150, 160, 120))
	var x := 6
	for ch in title.to_upper().substr(0, 14):
		var wob := rng.randi_range(-1, 1)
		_glyph(img, ch, x, 11 + wob, true, INK)
		x += 6
		if x > W - 10:
			break


# ------------------------------------------------------- Stufe 2/3: Nadeldruck
static func _print_title(img: Image, title: String, dense: bool) -> void:
	var t := _fit(title, 14)
	_dot_text(img, t, 2, 8, dense)
	# zweite Zeile: Typ-Vermerk wie auf echten Szene-Labels
	_dot_text(img, "AMIGA - KOPIE", 2, 24, dense)
	_dot_text(img, "%d NADELN" % (24 if dense else 9), 2, 38, dense)


## Punktschrift: 9-Nadel = jede 2. Rasterzeile fehlt (lückig), 24-Nadel = voll.
static func _dot_text(img: Image, text: String, x0: int, y0: int, dense: bool) -> void:
	var x := x0
	for ch in text.to_upper():
		_glyph(img, ch, x, y0, dense, INK)
		x += 6
		if x > W - 6:
			return


static func _glyph(img: Image, ch: String, x0: int, y0: int, dense: bool, col: Color) -> void:
	var rows: Array = FONT.get(ch, FONT[" "])
	for ry in rows.size():
		if not dense and (ry % 2 == 1):
			continue   # 9 Nadeln: Zeilenlücken — das typische lückige Druckbild
		var bits: int = rows[ry]
		for rx in 5:
			if bits & (16 >> rx):
				var px := x0 + rx
				var py := y0 + ry
				if px >= 0 and px < W and py >= 0 and py < H:
					img.set_pixel(px, py, col)


# ------------------------------------------------------- Stufe 4: Farb-Raster
## Artwork laden, aufs Etikett skalieren und wie einen frühen CMY-Tintenstrahler
## rastern: satte, grobe Farbpalette, Bayer-Dithering und dezente Druckkopf-Bahnen.
static func _print_art(img: Image, software_id: String) -> bool:
	if software_id == "":
		return false
	var art := _load_art(software_id)
	if art == null:
		return false
	art = art.duplicate()
	if art.is_compressed():
		art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	art.resize(W - 4, H - 14, Image.INTERPOLATE_NEAREST)
	const BAYER := [[0.0, 0.5], [0.75, 0.25]]
	for y in art.get_height():
		for x in art.get_width():
			var c := art.get_pixel(x, y)
			# Die kleine Vorlage braucht bewusst etwas mehr Farbabstand. Eine
			# komplett leere Rasterzeile wirkte wie Nadeldruck und verschluckte
			# ein Sechstel des Bildes; der CJ-300 druckt stattdessen vollflächig.
			var gray := (c.r + c.g + c.b) / 3.0
			c = Color(
				clampf(gray + (c.r - gray) * 1.32, 0.0, 1.0),
				clampf(gray + (c.g - gray) * 1.32, 0.0, 1.0),
				clampf(gray + (c.b - gray) * 1.32, 0.0, 1.0),
				1.0)
			var th: float = (BAYER[y % 2][x % 2] - 0.375) * 0.13
			var q := Color(
				_poster(c.r + th), _poster(c.g + th), _poster(c.b + th), 1.0)
			if y % 6 == 5:
				q = q.darkened(0.08)   # dezente Druckkopf-Bahn, kein Papierloch
			img.set_pixel(2 + x, 2 + y, q)
	return true


## Titel ohne normales Box-Art (vor allem eigene/Quest-Spiele) erhalten kein
## Schwarzweiß-24-Nadel-Etikett mehr, sondern ein stabiles, je Spiel einmaliges
## CMY-Keyvisual. Es bleibt als grob gerasterter 1993er-Tintendruck erkennbar.
static func _print_color_logo(img: Image, title: String, software_id: String) -> void:
	var palettes := [
		[Color8(19, 43, 89), Color8(36, 191, 208), Color8(246, 197, 52), Color8(226, 64, 106)],
		[Color8(48, 25, 82), Color8(196, 55, 166), Color8(43, 194, 170), Color8(248, 180, 48)],
		[Color8(18, 65, 50), Color8(91, 203, 86), Color8(238, 203, 57), Color8(205, 51, 68)],
		[Color8(69, 31, 35), Color8(225, 83, 51), Color8(244, 185, 63), Color8(47, 145, 190)],
	]
	var art_seed := absi(("%s/%s" % [software_id, title]).hash())
	var colors: Array = palettes[art_seed % palettes.size()]
	img.fill_rect(Rect2i(2, 2, W - 4, H - 14), colors[0])
	# Diagonale Rasterbänder und ein zentrales Emblem lesen sich selbst auf
	# 88×52 Pixeln als echtes Farblogo statt als eingefärbte Textzeile.
	for y in range(3, H - 13):
		for x in range(3, W - 3):
			var band := posmod(x + y * 2 + art_seed, 23)
			if band < 4:
				img.set_pixel(x, y, colors[1])
			elif band in [10, 11]:
				img.set_pixel(x, y, colors[2])
	var center := Vector2i(W >> 1, 19)
	for radius in range(12, 2, -1):
		var color: Color = colors[3] if radius % 3 else colors[2]
		for py in range(center.y - radius, center.y + radius + 1):
			for px in range(center.x - radius, center.x + radius + 1):
				if abs(px - center.x) + abs(py - center.y) in [radius, radius - 1]:
					if px >= 2 and px < W - 2 and py >= 2 and py < H - 12:
						img.set_pixel(px, py, color)
	var mark := _fit(title, 12)
	var mark_x := maxi(3, floori((W - mark.length() * 6) / 2.0))
	_dot_text_color(img, mark, mark_x, 16, Color8(252, 247, 222))


static func _color_footer(img: Image, title: String) -> void:
	img.fill_rect(Rect2i(0, H - 12, W, 12), Color8(245, 239, 218))
	img.fill_rect(Rect2i(0, H - 12, W, 1), Color8(38, 42, 54))
	_dot_text_color(img, _fit(title, 11), 2, H - 9, INK)
	# Drei klar getrennte Passermarken: Cyan, Magenta, Gelb.
	for i in 3:
		var color: Color = [Color8(20, 178, 205), Color8(210, 43, 133), Color8(232, 190, 24)][i]
		img.fill_rect(Rect2i(W - 13 + i * 4, H - 9, 3, 7), color)


static func _dot_text_color(img: Image, text: String, x0: int, y0: int, color: Color) -> void:
	var x := x0
	for ch in text.to_upper():
		_glyph(img, ch, x, y0, true, color)
		x += 6
		if x > W - 6:
			return


## Kanal auf 4 Druckstufen quantisieren (CMYK-Anmutung des Tintenstrahlers).
static func _poster(v: float) -> float:
	return clampf(roundf(clampf(v, 0.0, 1.0) * 3.0) / 3.0, 0.0, 1.0)


static func _load_art(software_id: String) -> Image:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var bible: Node = (loop as SceneTree).root.get_node_or_null("/root/SoftwareBible")
	if bible == null:
		return null
	for kind in ["disk_label", "box"]:
		var path := str(bible.call("art_path", software_id, kind))
		if path != "" and FileAccess.file_exists(path):
			var tex := load(path)
			if tex is Texture2D:
				return (tex as Texture2D).get_image()
	# Die 27 Stefan-Spiele besitzen bewusst keine erfundenen Verkaufskartons,
	# aber sehr wohl kuratierte AAA-Amiga-Szenen im Anthologie-Atlas. Für den
	# privaten Farbetikett-Druck wird exakt die zum Titel gehörige Zelle genutzt.
	var definition := StefanCatalog.game(software_id)
	var atlas_path := str(definition.get("atlas", ""))
	if not atlas_path.is_empty() and FileAccess.file_exists(atlas_path):
		var atlas_texture := load(atlas_path)
		if atlas_texture is Texture2D:
			var atlas_image := (atlas_texture as Texture2D).get_image()
			var region := StefanCatalog.atlas_region(definition, Vector2(atlas_image.get_size()))
			return atlas_image.get_region(Rect2i(
				Vector2i(roundi(region.position.x), roundi(region.position.y)),
				Vector2i(roundi(region.size.x), roundi(region.size.y))))
	return null


static func _fit(s: String, n: int) -> String:
	return s if s.length() <= n else s.substr(0, n - 1) + "."
