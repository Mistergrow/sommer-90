class_name Sprites
## Kleine, prozedural erzeugte Pixel-Sprites (Platzhalter-Pipeline, s. GDD 13).
## Alle Grafiken sind ASCII-Pixelkarten → per PixelArt.make_texture zu Texturen.
## Texturen werden gecacht, damit Icons nicht pro Frame neu gebaut werden.

static var _cache: Dictionary = {}


## Workbench-inspirierter Mauszeiger (Orange/Weiß mit schwarzer Kontur).
static func cursor() -> ImageTexture:
	if _cache.has("cursor"):
		return _cache["cursor"]
	var rows := [
		"K........",
		"KK.......",
		"KOK......",
		"KOOK.....",
		"KOWOK....",
		"KOWWOK...",
		"KOWWWOK..",
		"KOWOOOK..",
		"KOKKOWK..",
		"KK...KK..",
		"K........",
	]
	var tex := PixelArt.make_texture(rows, {
		"K": Palette.WB_BLACK, "O": Palette.WB_ORANGE, "W": Palette.WB_WHITE,
	})
	_cache["cursor"] = tex
	return tex


## 3,5"-Diskettensymbol in der Gehäusefarbe der Diskette (12x11 Pixel).
static func disk_icon(body: Color) -> ImageTexture:
	var key := "disk_%s" % body.to_html()
	if _cache.has(key):
		return _cache[key]
	var rows := [
		"KKKKKKKKKKKK",
		"KBBBSWWSBBBK",  # Metallschieber oben
		"KBBBSWWSBBBK",
		"KBBBSSSSBBBK",
		"KBBBBBBBBBBK",
		"KBWWWWWWWWBK",  # Etikettenfeld
		"KBWWWWWWWWBK",
		"KBWWWWWWWWBK",
		"KBWWWWWWWWBK",
		"KBBBBBBBBBBK",
		"KKKKKKKKKKKK",
	]
	var tex := PixelArt.make_texture(rows, {
		"K": Palette.BLACK, "B": body,
		"W": Palette.WHITE_SOFT, "S": Palette.GREY_LIGHT,
	})
	_cache[key] = tex
	return tex


## HUD-Icon aus PNG laden (assets/ui/hud/<name>.png), sonst prozedurale Fallback-
## Textur. So erscheinen vom User gelieferte, größere Icons automatisch, ohne dass
## die untere Leiste bis dahin leer wäre. Ergebnis wird gecacht (Name → Textur).
static func hud_icon(name: String, fallback: Texture2D) -> Texture2D:
	var key := "hud_%s" % name
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/ui/hud/%s.png" % name
	# Typ VOR dem Laden prüfen: liegt dort keine Textur, bliebe `as Texture2D` null
	# und würde als null gecacht — das Icon fehlte dann bis zum Neustart, statt auf
	# die prozedurale Fallback-Textur zurückzufallen.
	var loaded: Texture2D = null
	if ResourceLoader.exists(path) and RuntimeImageLoader.may_be_texture(path):
		loaded = load(path) as Texture2D
	var tex: Texture2D = loaded if loaded != null else fallback
	_cache[key] = tex
	return tex


## Geschlossene AGA-Sidebarfamilie. Jedes 11x11-Sprite besitzt eine schwarze
## Silhouette, zwei bis drei echte Amiga-Farbstufen und ein helles Glanzpixel.
## Damit lesen sich die Symbole wie kleine Workbench-Icons statt wie weisse
## Font-/Wireframe-Platzhalter.
static func ui_icon(kind: String) -> ImageTexture:
	var key := "icon_%s" % kind
	if _cache.has(key):
		return _cache[key]
	var definitions := {
		"room": {
			"accent": Color8(238, 133, 45), "mid": Color8(181, 70, 51),
			"rows": ["....KKK....", "...KAAAK...", "..KAAAAAK..", ".KBBBBBBBK.",
				"KBBBBBBBBBK", "KBBKKKKKBBK", "KBBKWWWKBBK", "KBBKWAWKBBK",
				"KBBKWAWKBBK", "KBBKWWWKBBK", "KKKKKKKKKKK"]},
		"inventory": {
			"accent": Color8(232, 171, 61), "mid": Color8(132, 76, 34),
			"rows": ["KKKKKKKKKKK", "KAAAAAAAAAK", "KAKKKKKKKAK", "KABBBBBBBAK",
				"KABBBKBBBAK", "KABBBKBBBAK", "KABBBWWWBAK", "KABBBKBBBAK",
				"KABBBBBBBAK", "KAAAAAAAAAK", "KKKKKKKKKKK"]},
		"contacts": {
			"accent": Color8(55, 184, 180), "mid": Color8(128, 89, 190),
			"rows": [".KKK...KKK.", "KAAAK.KBBBK", "KAWAK.KBWBK", "KAAAK.KBBBK",
				".KKK...KKK.", "..K.....K..", ".AAA...BBB.", "AAAAA.BBBBB",
				"AAAAA.BBBBB", "AAAAA.BBBBB", "KKKKK.KKKKK"]},
		"post": {
			"accent": Color8(218, 76, 63), "mid": Color8(236, 166, 54),
			"rows": ["KKKKKKKKKKK", "KWWWWWWWWWK", "KWAAWWWAAWK", "KWWAAWAAWWK",
				"KWWWAAAWWWK", "KWWWWAWWWWK", "KWBBBBBBBWK", "KWBBBBBBBWK",
				"KWWWWWWWWWK", "KAAAAAAAAAK", "KKKKKKKKKKK"]},
		"calendar": {
			"accent": Color8(240, 126, 43), "mid": Color8(114, 42, 44),
			"rows": [".KKKKKKKKK.", "KAAAKKAAAK", "KAKAKKAKAK", "KAAAAAAAAAK",
				"KWWWWWWWWWK", "KWKWWKWWKWK", "KWWWWWWWWWK", "KWWKWWWKWWK",
				"KWWWWWWWWWK", "KWKWWKWWKWK", ".KKKKKKKKK."]},
		"map": {
			"accent": Color8(91, 194, 101), "mid": Color8(33, 113, 88),
			"rows": ["....KK.....", "...KAAK....", "..KAAAAK...", ".KAAAAAAK..",
				"KAAAAAAAAK.", "KKKKAAKKKK.", "....BB.....", "....BB.....",
				"...KBBK....", "...KBBK....", "...KKKK...."]},
		"modem": {
			"accent": Color8(67, 199, 223), "mid": Color8(53, 91, 178),
			"rows": ["...........", ".KKKKKKKKK.", "KCCCCCCCCCK", "KCDDDDDDDCK",
				"KCCCCCCCCCK", "KCAWAWAWACK", "KCCCCCCCCCK", ".KBBBBBBBK.",
				"..K.....K..", ".KK.....KK.", "..........."]},
		"jobs": {
			"accent": Color8(244, 158, 49), "mid": Color8(68, 126, 190),
			"rows": [".KKKKK.....", "KAAAAAK....", "KABBBBAK...", ".KKKAAK....",
				"....AA.....", "....KAK....", ".....KAK...", "......KAK..",
				".......KAK.", "........KAK", ".........KK"]},
		"options": {
			"accent": Color8(204, 91, 199), "mid": Color8(60, 177, 206),
			"rows": ["..K.K.K.K..", ".KKBBBBBKK.", "KBBCCCCCBBK", ".BCKKKKKB..",
				"KCKAAAAAKCK", ".CKAAWAAKC.", "KCKAAAAAKCK", ".BCKKKKKB..",
				"KBBCCCCCBBK", ".KKBBBBBKK.", "..K.K.K.K.."]},
	}
	if not definitions.has(kind):
		return disk_icon(Palette.BLUE_MID)
	var definition: Dictionary = definitions[kind]
	var icon_tex := PixelArt.make_texture(definition["rows"], {
		"K": Color8(12, 14, 20),
		"A": definition["accent"],
		"B": definition["mid"],
		"C": Color8(179, 224, 231),
		"D": Color8(25, 47, 78),
		"W": Color8(246, 239, 204),
	})
	_cache[key] = icon_tex
	return icon_tex


## Simples NPC-Porträt (16x16): Hautton + Haarfarbe parametrisierbar.
static func face(skin: Color, hair: Color) -> ImageTexture:
	var key := "face_%s_%s" % [skin.to_html(), hair.to_html()]
	if _cache.has(key):
		return _cache[key]
	var rows := [
		"....HHHHHHHH....",
		"...HHHHHHHHHH...",
		"..HHHHHHHHHHHH..",
		"..HHSSSSSSSSHH..",
		"..HSSSSSSSSSSH..",
		"..HSSKSSSSKSSH..",  # Augen
		"..HSSKSSSSKSSH..",
		"..HSSSSSSSSSSH..",
		"..HSSSSKKSSSSH..",  # Nase
		"...SSSSSSSSSS...",
		"...SSKKKKKKSS...",  # Mund
		"....SSSSSSSS....",
		".....SSSSSS.....",
		"....TTTTTTTT....",  # T-Shirt-Ansatz
		"...TTTTTTTTTT...",
		"..TTTTTTTTTTTT..",
	]
	var tex := PixelArt.make_texture(rows, {
		"H": hair, "S": skin, "K": Palette.BLACK, "T": Palette.TEAL,
	})
	_cache[key] = tex
	return tex
