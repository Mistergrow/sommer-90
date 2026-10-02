class_name PortraitPaint32
## Handkuratiertes 32x32-Adventure-Portraet. Die Formen entstehen aus festen
## Scanlines und bewusst gesetzten Pixelclustern; es gibt keine Ellipsen,
## Distanzfelder, Vektor-Skalierung oder Downsampling aus einem groesseren Bild.
##
## Blickrichtung ist eine klare 3/4-Ansicht nach rechts: schmales fernes Auge,
## breiteres nahes Auge, linkes Ohr, versetzter Nasenruecken und asymmetrischer
## Kiefer. `render()` ist die einzige oeffentliche Zeichenwahrheit.

const Raster := preload("res://scripts/gfx/pixel_raster_32.gd")
const AvatarPalette := preload("res://scripts/gfx/avatar_palette_32.gd")
const HairCatalog := preload("res://scripts/gfx/portrait_hair_catalog_32.gd")
const HairFrontRenderer := preload("res://scripts/gfx/portrait_hair_front_renderer_32.gd")
const FaceCatalog := preload("res://scripts/gfx/portrait_face_catalog_32.gd")
const SIZE := 32
const OUTLINE := Color("211922")
const INK_SOFT := Color("49333a")
const SCLERA := Color("eee4d5")
const TOOTH := Color("f4eadb")
const MOUTH_DARK := Color("5b2730")
const TONGUE := Color("b95b62")
const GOLD := Color("d3b34d")

## Oeffentlicher Kompositionsvertrag fuer Regressionstests und Editor-Preview.
## Die Reihenfolge entspricht exakt render(); neue Paesse werden hier und dort
## gemeinsam ergaenzt. Brille bleibt hinter Ausdruck, Hut bleibt letzter Pass.
const COMPOSITION_PASSES := [
	"torso", "neck", "hair_back", "ear", "face", "hair_front", "face_planes",
	"glasses", "brows", "eyes", "nose", "age", "mouth", "beard",
	"accessories", "hat",
]
const MOUTH_ANCHORS := [Vector2i(16, 20), Vector2i(21, 20)]
const EYE_PIXEL_WIDTHS := {"far": 4, "near": 5}

static func render(sel: Dictionary) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var skin := AvatarPalette.portrait_skin(str(sel.get("skin", "beige")))
	var hair := AvatarPalette.portrait_hair(sel)
	var cloth := AvatarPalette.portrait_cloth(str(sel.get("shirt_color", "teal")))
	_draw_torso(img, sel, cloth)
	_draw_neck(img, sel, skin)
	_draw_hair_back(img, sel, hair)
	_draw_ear(img, sel, skin)
	_draw_face(img, sel, skin)
	_draw_hair_front(img, sel, hair)
	_draw_face_planes(img, sel, skin)
	# Brillenrahmen liegt konstruktiv HINTER Brauen/Augen/Nase. Dadurch bleiben
	# Blick und Ausdruck erhalten; der alte spaete Overlay-Pass maskierte beides.
	_draw_glasses(img, sel)
	_draw_brows(img, sel, hair)
	_draw_eyes(img, sel)
	_draw_nose(img, sel, skin)
	_draw_age(img, sel, skin)
	_draw_mouth(img, sel)
	_draw_beard(img, sel, hair)
	_draw_accessories(img, sel)
	_draw_hat(img, sel, hair)
	return img

## Kleine Integrationsschnittstelle fuer Selection-Code; der Renderer selbst
## liest immer `hair_style` und braucht keinen vorgelagerten Layer-Entscheid.
static func hair_has_back(style: String) -> bool:
	return HairCatalog.has_back(style)

# -------------------------------------------------------------- Pixelhelfer
static func _shape(img: Image, rows: Array, fill: Color, shade: Color) -> void:
	Raster.shape(img, rows, fill, shade, OUTLINE)

# --------------------------------------------------------------- Grundform
static func _draw_torso(img: Image, sel: Dictionary, cloth: Array[Color]) -> void:
	var female := bool(sel.get("female", false))
	var rows := _torso_rows(sel)
	_shape(img, rows, cloth[2], cloth[3])
	# Stofffalten und Kragen bleiben kurze, zusammenhaengende Cluster.
	Raster.line(img, 5, 10, 29, cloth[1]); Raster.line(img, 6, 9, 30, cloth[1])
	Raster.line(img, 24, 27, 29, cloth[4]); Raster.line(img, 25, 28, 30, cloth[4])
	if female:
		Raster.px(img, 13, 26, cloth[0]); Raster.px(img, 12, 27, cloth[1])
		Raster.line(img, 14, 16, 27, OUTLINE); Raster.line(img, 17, 19, 27, OUTLINE)
	else:
		Raster.line(img, 11, 15, 27, cloth[1]); Raster.line(img, 19, 23, 27, cloth[4])
		Raster.line(img, 15, 18, 28, OUTLINE)
	# Epoche, Saison und Ort bleiben auch im kleinen Raster lesbar: Shirtmuster
	# und Jacke belegen feste kurze Cluster, ohne die Buesstensilhouette zu
	# veraendern (wichtig fuer Mund-/Lidframes).
	var shirt := str(sel.get("shirt", "tee"))
	match shirt:
		"striped", "stripes":
			# Breite, ruhige Ringel statt zweier zufaelliger Striche. Die Reihen
			# folgen der Brustsilhouette und bleiben auch als 128er Inset sauber.
			_paint_torso_row(img, rows, 28, cloth[4], 2)
			_paint_torso_row(img, rows, 30, cloth[0], 2)
		"flannel":
			_paint_torso_row(img, rows, 29, cloth[4], 2)
			Raster.vline(img, 17, 27, 31, cloth[0])
			Raster.vline(img, 20, 28, 31, cloth[4])
			Raster.px(img, 14, 28, cloth[0]); Raster.px(img, 23, 30, cloth[4])
		"hoodie":
			# Kapuzenring, zwei Kordeln und Bauchtasche: drei verbundene Formen,
			# kein schwebender Querbalken mehr.
			Raster.line(img, 12, 21, 26, cloth[4])
			Raster.line(img, 13, 20, 27, cloth[1])
			Raster.vline(img, 15, 27, 29, cloth[0]); Raster.vline(img, 19, 27, 29, cloth[0])
			Raster.px(img, 15, 30, GOLD); Raster.px(img, 19, 30, GOLD)
			Raster.line(img, 12, 22, 31, cloth[1])
		"polo":
			Raster.segment(img, Vector2i(13, 26), Vector2i(16, 29), 0, cloth[0])
			Raster.segment(img, Vector2i(21, 26), Vector2i(18, 29), 0, cloth[4])
			Raster.vline(img, 17, 28, 31, cloth[1]); Raster.px(img, 17, 29, GOLD)
		"sweater":
			Raster.segment(img, Vector2i(13, 26), Vector2i(17, 29), 0, cloth[4])
			Raster.segment(img, Vector2i(21, 26), Vector2i(17, 29), 0, cloth[1])
			_paint_torso_row(img, rows, 31, cloth[0], 1)
		"track":
			Raster.vline(img, 17, 26, 31, cloth[4])
			Raster.px(img, 17, 28, GOLD)
			Raster.segment(img, Vector2i(8, 28), Vector2i(5, 31), 0, cloth[0])
			Raster.segment(img, Vector2i(25, 28), Vector2i(28, 31), 0, cloth[0])
		"jacket":
			Raster.segment(img, Vector2i(11, 26), Vector2i(16, 31), 0, cloth[0])
			Raster.segment(img, Vector2i(22, 26), Vector2i(18, 31), 0, cloth[4])
			Raster.vline(img, 17, 27, 31, OUTLINE)
			Raster.px(img, 15, 29, GOLD); Raster.px(img, 20, 30, GOLD)
		"tank", "tanktop":
			_paint_tank_shoulders(img, rows, sel, cloth)
		"vneck":
			Raster.segment(img, Vector2i(13, 26), Vector2i(17, 30), 0, cloth[0])
			Raster.segment(img, Vector2i(21, 26), Vector2i(17, 30), 0, cloth[4])
			Raster.px(img, 17, 31, cloth[1])
		"overall":
			_paint_portrait_overall(img, rows)
		"logo":
			Raster.rect(img, 14, 28, 7, 4, cloth[4])
			Raster.line(img, 15, 19, 28, cloth[0]); Raster.line(img, 16, 18, 29, cloth[3])
			Raster.line(img, 17, 19, 30, cloth[1])
	var jacket := str(sel.get("jacket", ""))
	if jacket != "":
		var edge := cloth[4] if jacket == "leather" else cloth[3]
		Raster.line(img, 4, 10, 28, edge); Raster.line(img, 24, 29, 28, edge)
		Raster.line(img, 3, 11, 30, edge); Raster.line(img, 23, 30, 30, edge)
		Raster.line(img, 12, 15, 27, cloth[0]); Raster.line(img, 19, 22, 27, cloth[4])
	_clip_to_torso(img, rows)


## Eine einzige Koerpersilhouette ist Zeichen- und Testwahrheit. Kleidung,
## Accessoires und visuelle Regressionen muessen dieselben Reihen verwenden;
## kopierte Alters-/Geschlechtskoordinaten driften sonst unweigerlich auseinander.
static func _torso_rows(sel: Dictionary) -> Array:
	var female := bool(sel.get("female", false))
	var stage := str(sel.get("life_stage", "young_adult"))
	var rows: Array
	if stage == "early_teen":
		# Vierzehnjährige haben eine schmalere Büste und weniger Schultermasse.
		# Der Kopf bleibt dieselbe DNA; die Altersstufe liest sich bereits als
		# Silhouette, selbst wenn Bart und Accessoires zufällig ausbleiben.
		rows = [[25, 13, 20, 19], [26, 11, 22, 20], [27, 9, 24, 21],
			[28, 7, 26, 22], [29, 6, 27, 23], [30, 5, 28, 24], [31, 4, 29, 25]]
	elif stage == "late_teen":
		rows = [[25, 12, 21, 19], [26, 10, 23, 20], [27, 7, 26, 22],
			[28, 5, 28, 24], [29, 4, 29, 25], [30, 3, 30, 26], [31, 2, 30, 26]]
	elif stage == "young_adult" and not female:
		# Mit 18 ist der Wachstumsschub sichtbar, aber die erwachsene Schulter-
		# und Brustmasse ist noch nicht voll erreicht. Das trennt 18 klar von 21,
		# ohne Kleidung oder Identitaet auszutauschen.
		rows = [[25, 12, 21, 19], [26, 9, 23, 20], [27, 6, 26, 22],
			[28, 4, 28, 24], [29, 3, 29, 25], [30, 2, 30, 26], [31, 2, 30, 26]]
	elif female:
		rows = [[25, 13, 20, 19], [26, 10, 22, 20], [27, 8, 24, 21],
			[28, 6, 26, 22], [29, 5, 27, 23], [30, 4, 28, 24], [31, 3, 29, 24]]
	else:
		rows = [[25, 11, 21, 19], [26, 8, 24, 21], [27, 5, 27, 23],
			[28, 3, 29, 25], [29, 2, 30, 26], [30, 1, 31, 27], [31, 1, 31, 27]]
	return rows


static func _row_span(rows: Array, y: int) -> Vector2i:
	for raw: Variant in rows:
		var row: Array = raw
		if int(row[0]) == y:
			return Vector2i(int(row[1]), int(row[2]))
	return Vector2i(-1, -1)


static func _paint_torso_row(img: Image, rows: Array, y: int, color: Color,
		inset: int = 1) -> void:
	var span := _row_span(rows, y)
	if span.x < 0:
		return
	Raster.line(img, span.x + inset, span.y - inset, y, color)


static func _paint_tank_shoulders(img: Image, rows: Array, sel: Dictionary,
		cloth: Array[Color]) -> void:
	var skin := AvatarPalette.portrait_skin(str(sel.get("skin", "beige")))
	# Das Tanktop gibt die aeusseren Schulterkeile wirklich frei. Die alten
	# dunklen Vertikalen lagen nur auf einem weiterhin vollflaechigen T-Shirt.
	for y in range(25, 29):
		var span := _row_span(rows, y)
		if span.x < 0:
			continue
		var cut := 2 if y <= 26 else 3
		Raster.line(img, span.x + 1, mini(span.x + cut, span.y), y, skin[2])
		Raster.line(img, maxi(span.y - cut, span.x), span.y - 1, y, skin[3])
	Raster.segment(img, Vector2i(13, 25), Vector2i(14, 30), 0, cloth[0])
	Raster.segment(img, Vector2i(21, 25), Vector2i(20, 30), 0, cloth[4])
	Raster.line(img, 15, 19, 27, cloth[1])


static func _paint_portrait_overall(img: Image, rows: Array) -> void:
	var denim := AvatarPalette.portrait_denim()
	# Zwei echte, leicht perspektivische Traeger verbinden Schulter und Latz.
	# Der rechte (nahe) Traeger ist heller und einen Pixel breiter lesbar.
	Raster.segment(img, Vector2i(12, 26), Vector2i(14, 29), 0, denim[1])
	Raster.segment(img, Vector2i(13, 26), Vector2i(15, 29), 0, denim[3])
	Raster.segment(img, Vector2i(22, 26), Vector2i(20, 29), 0, denim[4])
	Raster.segment(img, Vector2i(21, 26), Vector2i(19, 29), 0, denim[2])
	# Trapezlatz und Bund folgen dem aktiven Torso; damit passen sie bei
	# Teenagern, Erwachsenen und weiblichen Silhouetten gleichermassen.
	for y in range(28, 32):
		var span := _row_span(rows, y)
		if span.x < 0:
			continue
		var half := 4 + (y - 28) * 2
		var left := maxi(span.x + 1, 17 - half)
		var right := mini(span.y - 1, 17 + half)
		Raster.line(img, left, right, y, denim[2])
		Raster.px(img, left, y, denim[3]); Raster.px(img, right, y, denim[4])
	var waist := _row_span(rows, 31)
	if waist.x >= 0:
		Raster.line(img, waist.x + 1, waist.y - 1, 31, denim[1])
		Raster.line(img, waist.x + 2, waist.y - 2, 30, denim[2])
	Raster.px(img, 14, 28, GOLD); Raster.px(img, 20, 28, GOLD)
	Raster.rect(img, 15, 29, 5, 3, denim[1])
	Raster.line(img, 16, 18, 29, denim[3]); Raster.px(img, 19, 31, denim[4])


## Kleidungsdetails werden bislang als handgesetzte Pixelcluster gezeichnet.
## Diese letzte Maske bindet sie an die tatsächlich aktive Teen-/Erwachsenen-
## Silhouette. Damit können weder Jackenkanten noch Muster neben den schmaleren
## Schultern schweben – ein häufiger Fehler kombinatorischer Avatar-Generatoren.
static func _clip_to_torso(img: Image, rows: Array) -> void:
	var bounds := {}
	for raw: Variant in rows:
		var row: Array = raw
		bounds[int(row[0])] = Vector2i(int(row[1]), int(row[2]))
	for y in range(25, SIZE):
		if not bounds.has(y):
			for x in SIZE:
				img.set_pixel(x, y, Color.TRANSPARENT)
			continue
		var span: Vector2i = bounds[y]
		for x in SIZE:
			if x < span.x or x > span.y:
				img.set_pixel(x, y, Color.TRANSPARENT)

static func _draw_neck(img: Image, sel: Dictionary, skin: Array[Color]) -> void:
	var female := bool(sel.get("female", false))
	var youthful := str(sel.get("life_stage", "young_adult")) in ["early_teen", "late_teen"]
	var left := 15 if female or youthful else 14
	var right := 20 if female or youthful else 21
	var hem_left := 15 if female else (14 if youthful else 13)
	var rows := [[22, left, right, 20], [23, left, right, 20],
		[24, left, right, 20], [25, hem_left, right, 20], [26, hem_left, right, 20]]
	_shape(img, rows, skin[2], skin[3])
	Raster.line(img, 15, 20, 23, skin[4])
	Raster.px(img, 15, 24, skin[1])

static func _face_rows(sel: Dictionary) -> Array:
	var rows: Array = FaceCatalog.rows_for(str(sel.get("head", "oval")))
	# Teenager behalten rundere Wangen und einen kürzeren, weicheren Kiefer.
	# Ab 18 gilt wieder exakt die gewählte Gesichtsform; die Person bleibt also
	# wiedererkennbar und „wechselt“ nicht ihr genetisches Preset.
	var stage := str(sel.get("life_stage", "young_adult"))
	var adjusted: Array = []
	for raw: Variant in rows:
		var row: Array = (raw as Array).duplicate()
		var y := int(row[0])
		if stage == "early_teen" and y >= 17 and y <= 21:
			row[1] = maxi(7, int(row[1]) - 1)
			row[2] = mini(26, int(row[2]) + 1)
		if stage == "early_teen" and y >= 24:
			continue
		if stage == "late_teen" and y >= 19 and y <= 21:
			row[1] = maxi(8, int(row[1]) - 1)
		if stage in ["adult", "mature"] and y >= 19 and y <= 22:
			# Anfang zwanzig setzt sich der Kiefer derselben Gesichtsform. Zwei
			# ruhige Randpixel sind auf dem 32er Raster lesbarer als Bartstoppeln
			# oder zufaellige Falten und veraendern keine DNA-Merkmale.
			row[1] = maxi(8, int(row[1]) - 1)
			row[2] = mini(25, int(row[2]) + 1)
			row[3] = mini(int(row[2]), int(row[3]) + int(y >= 21))
		adjusted.append(row)
	return adjusted

static func _draw_face(img: Image, sel: Dictionary, skin: Array[Color]) -> void:
	_shape(img, _face_rows(sel), skin[2], skin[3])
	# Die Nahseite lebt von HELLEN Platten (Stirn/Wange); dunkle Töne liegen nur
	# als VERTIKALE Kante an der Schattenseite. Dunkle Querstreifen mitten im
	# Gesicht lesen sich bei 32 px als Narben — deshalb gibt es hier keine.
	Raster.line(img, 11, 16, 8, skin[1]); Raster.line(img, 10, 15, 9, skin[1])
	Raster.line(img, 10, 13, 15, skin[0]); Raster.line(img, 10, 14, 16, skin[1])
	Raster.line(img, 11, 14, 17, skin[1])
	Raster.px(img, 22, 17, skin[3]); Raster.px(img, 22, 18, skin[3]); Raster.px(img, 22, 19, skin[3])
	Raster.line(img, 17, 19, 22, skin[3]); Raster.line(img, 16, 19, 23, skin[1])

static func _draw_ear(img: Image, sel: Dictionary, skin: Array[Color]) -> void:
	# Nur das ferne Ohr ist in dieser Blickrichtung voll sichtbar.
	var big := str(sel.get("ears", "plain")) == "big"
	Raster.px(img, 7, 13, OUTLINE); Raster.px(img, 7, 14, skin[2]); Raster.px(img, 7, 15, skin[2])
	Raster.px(img, 7, 16, OUTLINE); Raster.px(img, 8, 14, skin[4]); Raster.px(img, 8, 15, skin[3])
	if big:
		Raster.px(img, 6, 13, OUTLINE); Raster.px(img, 6, 14, skin[2]); Raster.px(img, 6, 15, skin[3]); Raster.px(img, 6, 16, OUTLINE)

static func _draw_face_planes(img: Image, sel: Dictionary, skin: Array[Color]) -> void:
	# Brauenplatte (hell, kurz) und ein vertikaler Nasen-Wangen-Schatten an der
	# Schattenseite. Bewusst KEINE skin[3]/[4]-Querlinien im Innengesicht.
	Raster.material_line(img, 11, 13, 11, skin, skin[1])
	Raster.material_line(img, 17, 21, 10, skin, skin[1])
	# Nasenflanke: nur die Konturkante — Einzel-Sprenkel neben der Nase
	# verschmolzen mit ihr zu dunklem Gewusel.
	Raster.material_px(img, 23, 14, skin, skin[3]); Raster.material_px(img, 23, 15, skin, skin[3])
	if not bool(sel.get("female", false)):
		Raster.material_line(img, 10, 13, 18, skin, skin[1])
		Raster.material_line(img, 21, 22, 20, skin, skin[3])
	else:
		Raster.material_line(img, 10, 13, 18, skin, skin[0])
		Raster.material_px(img, 21, 19, skin, skin[1])
	var stage := str(sel.get("life_stage", "young_adult"))
	if stage == "early_teen":
		# Jugendliche Flaeche: ein zusammenhaengendes hohes Wangenlicht und
		# weniger harter Mundwinkelbereich; die Silhouette/Face-Shape bleibt gleich.
		Raster.material_line(img, 11, 14, 17, skin, skin[0])
		Raster.material_px(img, 20, 18, skin, skin[1])
	elif stage == "late_teen":
		Raster.material_line(img, 12, 14, 17, skin, skin[0])
		Raster.material_px(img, 21, 19, skin, skin[2])
	elif stage in ["adult", "mature"]:
		# Erwachsener Kiefer: kurze verbundene Ebenen statt künstlicher Falten.
		Raster.material_line(img, 11, 14, 21, skin, skin[3])
		Raster.material_line(img, 20, 22, 21, skin, skin[4])
		Raster.material_line(img, 16, 20, 23, skin, skin[3])

# -------------------------------------------------------------------- Haar
static func _draw_hair_back(img: Image, sel: Dictionary, hair: Array[Color]) -> void:
	var hat := str(sel.get("hat", ""))
	var covered := HairCatalog.is_covering_hat(hat)
	var style := HairCatalog.style_for_back(str(sel.get("hair_style", "short")), hat)
	var rows: Array = HairCatalog.SHORT_BACK
	if style in ["bob", "medium"]:
		rows = HairCatalog.BOB_BACK
	elif style in ["long", "straight", "mullet"]:
		# Lange Mähne: unterhalb des Kinns NUR Seitensträhnen — die volle Breite
		# flutete die Halssäule zu und der Kopf saß „halslos" auf dem Torso.
		rows = []
		var side_left := []
		var side_right := []
		for raw: Variant in HairCatalog.LONG_BACK:
			var row: Array = raw
			if int(row[0]) < 22:
				rows.append(row)
			else:
				side_left.append([row[0], row[1], 12])
				side_right.append([row[0], 23, row[2]])
		_shape(img, side_left, hair[3], hair[4])
		_shape(img, side_right, hair[3], hair[4])
	elif style == "curly":
		# Locken bleiben kopfnah und gestuft. Das volle Afro-Volumen gehoert nur
		# dem Afro; vorher waren beide Stile bis auf wenige Pixel identisch.
		rows = [[2, 11, 21], [3, 8, 24], [4, 6, 26], [5, 5, 27],
			[6, 5, 27], [7, 4, 27], [8, 5, 28], [9, 4, 27],
			[10, 5, 27], [11, 5, 26], [12, 6, 26], [13, 6, 25],
			[14, 7, 25], [15, 7, 24], [16, 8, 24], [17, 8, 23]]
	elif style == "afro":
		rows = HairCatalog.AFRO_BACK
	elif style == "bald":
		return
	elif style == "mohawk":
		# Rasierte Schlaefen statt einer geschlossenen Helmform.
		Raster.line(img, 8, 10, 8, hair[4]); Raster.line(img, 8, 9, 9, hair[3])
		Raster.line(img, 8, 9, 10, hair[4])
		return
	_shape(img, rows, hair[3], hair[4])
	# Hinterkopf-Glanz ist unterbrochen, damit kein glatter Plastikhelm entsteht.
	Raster.material_line(img, 7, 9, 8, hair, hair[1])
	Raster.material_line(img, 6, 8, 11, hair, hair[2])
	Raster.material_line(img, 25, 27, 12, hair, hair[4])
	if style == "ponytail":
		# Sichtbarer gebundener Schweif mit schmaler Basis und breitem Ende.
		_shape(img, [[11, 25, 28], [12, 25, 29], [13, 26, 30],
			[14, 26, 31], [15, 27, 31], [16, 27, 31], [17, 28, 31],
			[18, 28, 30], [19, 29, 30]], hair[2], hair[4])
	if style == "pigtails":
		_shape(img, [[12, 3, 7], [13, 2, 7], [14, 1, 6], [15, 1, 6],
			[16, 2, 6], [17, 2, 5], [18, 3, 5]], hair[2], hair[4])
		_shape(img, [[12, 25, 29], [13, 25, 30], [14, 26, 31], [15, 26, 31],
			[16, 26, 30], [17, 27, 30], [18, 28, 29]], hair[2], hair[4])
		Raster.px(img, 6, 12, hair[0]); Raster.px(img, 26, 12, hair[0])
	if style == "bun" and not covered:
		_shape(img, [[0, 17, 22], [1, 15, 24], [2, 14, 24],
			[3, 15, 24], [4, 17, 23]], hair[2], hair[4])
		Raster.line(img, 17, 21, 1, hair[1])

static func _draw_hair_front(img: Image, sel: Dictionary, hair: Array[Color]) -> void:
	HairFrontRenderer.draw(img, sel, hair)

# -------------------------------------------------------------- Merkmale
static func _draw_brows(img: Image, sel: Dictionary, hair: Array[Color]) -> void:
	var female := bool(sel.get("female", false))
	var brow := hair[4] if str(sel.get("hair_style", "")) != "bald" else INK_SOFT
	var brow_type := str(sel.get("eyebrows", "flat"))
	# Mit Brille rutschen die Brauen eine Zeile nach oben, sonst verschmelzen
	# Braue und Rahmen zu einem dunklen Klumpen (einäugiger Eindruck).
	var lift := 1 if str(sel.get("glasses", "")) != "" else 0
	# Fernbraue ist kuerzer und tiefer: erste Lesestufe der 3/4-Perspektive.
	# Emotionen veraendern nur diese wenigen Ausdruckspixel, nie Kopf oder Haar.
	var mood := str(sel.get("mood", ""))
	if mood == "angry":
		Raster.line(img, 10, 13, 9 - lift, brow); Raster.line(img, 13, 15, 10 - lift, brow)
		Raster.line(img, 17, 19, 10 - lift, brow); Raster.line(img, 20, 22, 9 - lift, brow)
	elif mood == "sad":
		Raster.line(img, 10, 12, 10 - lift, brow); Raster.line(img, 13, 15, 9 - lift, brow)
		Raster.line(img, 17, 19, 9 - lift, brow); Raster.line(img, 20, 22, 10 - lift, brow)
	elif mood == "raise":
		Raster.line(img, 11, 14, 9 - lift, brow); Raster.line(img, 18, 21, 8 - lift, brow)
	else:
		var raised := brow_type == "raised"
		var by_far := 9 - lift if raised else 10 - lift
		var by_near := 8 - lift if raised else ((9 if female else 10) - lift)
		Raster.line(img, 11 if female else 10, 14 if female else 15, by_far, brow)
		Raster.line(img, 18 if female else 17, 21 if female else 22, by_near, brow)
		if brow_type == "thick":
			Raster.line(img, 11, 14, by_far - 1, brow)
			Raster.line(img, 18, 21, by_near - 1, brow)
		elif not female and str(sel.get("life_stage", "young_adult")) in ["adult", "mature"]:
			# Anfang 20 wird die Brauen-/Stirnpartie markanter, ohne den gewählten
			# Brauentyp in eine andere Variante umzudeuten.
			Raster.px(img, 10, by_far, brow)
			Raster.px(img, 22, by_near, brow)

static func _draw_eyes(img: Image, sel: Dictionary) -> void:
	var state := str(sel.get("eyes", ""))
	# Neutral/open ist nur der Animationsframe. Die eigentliche Augenform aus
	# dem Editor bleibt darunter erhalten; zuvor ueberschrieb der neutrale
	# Emotionslayer die Typen Normal/Schmal/Gross/Vertraeumt vollstaendig.
	if state in ["", "neutral", "open"]:
		state = str(sel.get("eye_type", "normal"))
	var left_state := str(sel.get("eye_left_frame", state))
	var right_state := str(sel.get("eye_right_frame", state))
	var gaze := clampi(int(sel.get("gaze", 0)), -1, 1)
	_draw_eye_far(img, left_state, gaze, sel)
	_draw_eye_near(img, right_state, gaze, sel)

static func _eye_closed(state: String) -> bool:
	return state in ["closed", "blink", "happy"]

static func _eye_half(state: String) -> bool:
	return state in ["half", "narrow", "tired"]

static func _draw_eye_far(img: Image, state: String, gaze: int, sel: Dictionary) -> void:
	var y := 12
	if _eye_closed(state):
		Raster.line(img, 11, 14, y + 1, INK_SOFT); Raster.px(img, 12, y + 2, OUTLINE)
		return
	if _eye_half(state):
		Raster.line(img, 11, 14, y, OUTLINE); Raster.line(img, 12, 14, y + 1, SCLERA)
		Raster.px(img, 14, y + 1, OUTLINE)
		var half_iris_x := clampi(13 + gaze, 12, 13)
		Raster.px(img, half_iris_x, y + 1, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown"))))
		return
	if state == "droopy":
		Raster.line(img, 11, 13, y, OUTLINE); Raster.line(img, 13, 14, y + 1, OUTLINE)
		Raster.line(img, 12, 13, y + 1, SCLERA); Raster.px(img, 12, y + 2, OUTLINE)
		Raster.px(img, clampi(13 + gaze, 12, 13), y + 1, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown")))); return
	if state == "wide":
		Raster.line(img, 11, 14, y - 1, OUTLINE); Raster.px(img, 11, y, OUTLINE)
		Raster.line(img, 12, 14, y, SCLERA); Raster.line(img, 12, 14, y + 1, INK_SOFT)
		Raster.px(img, 12, y + 2, OUTLINE); Raster.px(img, 14, y + 1, OUTLINE)
		var wide_iris_x := clampi(13 + gaze, 12, 13)
		Raster.px(img, wide_iris_x, y, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown"))))
		Raster.px(img, wide_iris_x, y + 1, OUTLINE); return
	Raster.line(img, 11, 14, y, OUTLINE)
	Raster.px(img, 11, y + 1, OUTLINE); Raster.line(img, 12, 14, y + 1, SCLERA)
	Raster.px(img, 12, y + 2, OUTLINE); Raster.line(img, 13, 14, y + 2, INK_SOFT)
	var iris_x := clampi(13 + gaze, 12, 14)
	Raster.px(img, iris_x, y + 1, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown"))))
	Raster.px(img, iris_x, y + 2, OUTLINE)

static func _draw_eye_near(img: Image, state: String, gaze: int, sel: Dictionary) -> void:
	var female := bool(sel.get("female", false))
	# Beide Augen liegen auf DERSELBEN Zeile: der frühere 1-px-Hochversatz des
	# nahen Frauen-Auges las sich als Schielen, nicht als Perspektive. Die
	# 3/4-Ansicht kommt allein aus Breite (4 vs. 5 px) und Wimpernakzent.
	var y := 12
	if _eye_closed(state):
		Raster.line(img, 17, 21, y + 1, INK_SOFT); Raster.px(img, 20, y + 2, OUTLINE)
		return
	if _eye_half(state):
		Raster.line(img, 17, 21, y, OUTLINE); Raster.line(img, 18, 20, y + 1, SCLERA)
		Raster.px(img, 21, y + 1, OUTLINE)
		var half_iris_x := clampi(19 + gaze, 18, 20)
		Raster.px(img, half_iris_x, y + 1, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown"))))
		return
	if state == "droopy":
		Raster.line(img, 17, 20, y, OUTLINE); Raster.line(img, 20, 21, y + 1, OUTLINE)
		Raster.line(img, 18, 20, y + 1, SCLERA); Raster.px(img, 18, y + 2, OUTLINE)
		Raster.px(img, clampi(19 + gaze, 18, 20), y + 1, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown")))); return
	if state == "wide":
		Raster.line(img, 17, 21, y - 1, OUTLINE); Raster.px(img, 17, y, OUTLINE)
		Raster.line(img, 18, 21, y, SCLERA); Raster.line(img, 18, 21, y + 1, INK_SOFT)
		Raster.px(img, 18, y + 2, OUTLINE); Raster.px(img, 21, y + 1, OUTLINE)
		var wide_iris_x := clampi(20 + gaze, 18, 20)
		Raster.px(img, wide_iris_x, y, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown"))))
		Raster.px(img, wide_iris_x, y + 1, OUTLINE)
		if female: Raster.px(img, 22, y - 1, OUTLINE)
		return
	Raster.line(img, 17, 21, y, OUTLINE)
	Raster.px(img, 17, y + 1, OUTLINE); Raster.line(img, 18, 21, y + 1, SCLERA)
	Raster.px(img, 18, y + 2, OUTLINE); Raster.line(img, 19, 21, y + 2, INK_SOFT)
	var iris_x := clampi(20 + gaze, 18, 21)
	Raster.px(img, iris_x, y + 1, AvatarPalette.portrait_iris(str(sel.get("eye_color", "brown"))))
	Raster.px(img, iris_x, y + 2, OUTLINE)
	if female:
		Raster.px(img, 22, y, OUTLINE); Raster.px(img, 21, y - 1, OUTLINE)

static func _draw_nose(img: Image, sel: Dictionary, skin: Array[Color]) -> void:
	# Kompakte Nase: EIN Lichtruecken + EIN Schattenfuss — die frueheren sieben
	# verstreuten Pixel samt schwarzer Spitze lasen sich als Schmutz im Gesicht.
	var nose_kind := str(sel.get("nose", "straight"))
	if str(sel.get("life_stage", "young_adult")) == "early_teen" and nose_kind == "long":
		nose_kind = "straight"
	match nose_kind:
		"small":
			Raster.px(img, 21, 15, skin[1]); Raster.px(img, 22, 16, skin[3])
		"wide":
			Raster.px(img, 21, 14, skin[1]); Raster.px(img, 21, 15, skin[1])
			Raster.line(img, 20, 23, 16, skin[3]); Raster.px(img, 20, 17, skin[4]); Raster.px(img, 23, 17, skin[4])
		"long":
			Raster.vline(img, 21, 13, 16, skin[1]); Raster.px(img, 20, 15, skin[0])
			Raster.line(img, 21, 23, 17, skin[3]); Raster.px(img, 23, 16, skin[4])
		_:
			Raster.px(img, 21, 14, skin[1]); Raster.px(img, 21, 15, skin[1])
			Raster.px(img, 20, 15, skin[0]); Raster.px(img, 22, 16, skin[3]); Raster.px(img, 21, 17, skin[3])

static func _draw_age(img: Image, sel: Dictionary, skin: Array[Color]) -> void:
	var age := int(sel.get("age_now", 20))
	var stage := str(sel.get("life_stage", "young_adult"))
	if stage == "early_teen":
		# Helles, weiches Mittelgesicht; diese Cluster verschwinden mit 16.
		Raster.line(img, 12, 14, 16, skin[0])
		Raster.line(img, 18, 20, 17, skin[1])
		return
	if stage == "late_teen":
		Raster.line(img, 12, 14, 17, skin[1])
		return
	if stage == "young_adult":
		Raster.line(img, 20, 22, 21, skin[3])
		return
	if age < 48:
		return
	# Alter als KURZE Akzente an Auge/Nasolabial — keine Querstreifen über die
	# Wangen (die lasen sich als Narben/Flecken statt als Falten).
	Raster.line(img, 15, 16, 15, skin[3])
	Raster.px(img, 22, 13, skin[3]); Raster.px(img, 22, 14, skin[3])
	Raster.px(img, 15, 18, skin[3]); Raster.px(img, 15, 19, skin[3])
	if age >= 65:
		Raster.line(img, 13, 16, 9, skin[3]); Raster.px(img, 11, 19, skin[3])

static func _draw_mouth(img: Image, sel: Dictionary) -> void:
	var pose := str(sel.get("mouth", "rest"))
	if pose not in ["rest", "mbp", "fv", "ai", "e", "ou", "l", "sch"]:
		if pose in ["smile", "happy", "grin"]: pose = "e"
		elif pose in ["open", "surprised", "laugh"]: pose = "ai"
		elif pose == "talking": pose = "sch"
		elif pose == "grit":
			Raster.line(img, 16, 22, 19, OUTLINE); Raster.line(img, 17, 21, 20, TOOTH)
			Raster.line(img, 17, 21, 21, OUTLINE); return
		elif pose == "wavy":
			Raster.px(img, 16, 20, OUTLINE); Raster.px(img, 17, 19, MOUTH_DARK); Raster.px(img, 18, 20, MOUTH_DARK)
			Raster.px(img, 19, 19, MOUTH_DARK); Raster.px(img, 20, 20, MOUTH_DARK); Raster.px(img, 21, 19, OUTLINE); return
		elif pose in ["frown", "sad"]:
			Raster.line(img, 16, 20, 21, MOUTH_DARK); Raster.px(img, 16, 20, OUTLINE); Raster.px(img, 20, 20, OUTLINE); return
		else: pose = "rest"
	# MUND-ANKER-VERTRAG: Alle acht Visemes teilen dieselben Mundwinkel
	# (16,20) und (21,20) und dieselbe Grundlinie y=20. Nur der Öffnungsgrad
	# (y19/y21/y22) ändert sich — der Mund bleibt beim Sprechen an Ort und
	# Stelle, statt im Gesicht zu wandern.
	match pose:
		"rest":
			if bool(sel.get("female", false)):
				# Vollere Unterlippe als EIN dezenter Pixel — die frühere
				# TONGUE-Zeile las sich als herausgestreckte Zunge.
				Raster.px(img, 16, 20, OUTLINE); Raster.line(img, 17, 20, 20, MOUTH_DARK)
				Raster.px(img, 21, 20, OUTLINE); Raster.px(img, 19, 21, TONGUE.darkened(0.30))
			else:
				Raster.px(img, 16, 20, OUTLINE); Raster.line(img, 17, 20, 20, MOUTH_DARK); Raster.px(img, 21, 20, OUTLINE)
				Raster.line(img, 18, 19, 21, INK_SOFT)
		"mbp":
			Raster.line(img, 16, 21, 20, OUTLINE); Raster.line(img, 17, 20, 19, TONGUE.darkened(0.10))
			Raster.line(img, 17, 20, 21, TONGUE)
		"fv":
			# Unterlippe an den Zähnen: schmaler, gedeckter Zahnstreifen statt
			# des früheren 4-px-Weißbalkens (der hellste Fleck im ganzen Gesicht).
			Raster.px(img, 16, 20, OUTLINE); Raster.line(img, 17, 19, 20, TOOTH.darkened(0.10))
			Raster.px(img, 20, 20, MOUTH_DARK); Raster.px(img, 21, 20, OUTLINE)
			Raster.line(img, 18, 20, 21, TONGUE)
		"ai":
			Raster.px(img, 16, 20, OUTLINE); Raster.px(img, 21, 20, OUTLINE)
			Raster.line(img, 17, 20, 19, OUTLINE); Raster.line(img, 17, 20, 20, MOUTH_DARK)
			Raster.line(img, 17, 20, 21, TONGUE); Raster.line(img, 18, 20, 22, OUTLINE)
		"e":
			Raster.line(img, 16, 21, 19, OUTLINE); Raster.px(img, 16, 20, OUTLINE)
			Raster.line(img, 17, 20, 20, TOOTH.darkened(0.06)); Raster.px(img, 21, 20, OUTLINE)
			Raster.line(img, 17, 20, 21, MOUTH_DARK)
		"ou":
			# Kleine gerundete Form um die Mundmitte (x18/19) — kompakt, ohne das
			# frühere große Dunkel-Loch über vier Zeilen.
			Raster.px(img, 16, 20, OUTLINE); Raster.px(img, 21, 20, OUTLINE)
			Raster.line(img, 18, 19, 19, OUTLINE); Raster.px(img, 17, 20, OUTLINE)
			Raster.line(img, 18, 19, 20, TONGUE.darkened(0.12)); Raster.px(img, 20, 20, OUTLINE)
			Raster.line(img, 18, 19, 21, OUTLINE)
		"l":
			Raster.line(img, 16, 21, 19, OUTLINE); Raster.px(img, 16, 20, OUTLINE)
			Raster.line(img, 17, 19, 20, TOOTH.darkened(0.10)); Raster.px(img, 20, 20, TONGUE)
			Raster.px(img, 21, 20, OUTLINE); Raster.line(img, 18, 20, 21, TONGUE.darkened(0.10))
		"sch":
			Raster.px(img, 16, 20, OUTLINE); Raster.line(img, 17, 20, 20, TONGUE.darkened(0.10))
			Raster.px(img, 21, 20, OUTLINE); Raster.line(img, 18, 20, 21, MOUTH_DARK)
			Raster.px(img, 17, 21, OUTLINE); Raster.px(img, 21, 21, OUTLINE)

static func _draw_beard(img: Image, sel: Dictionary, hair: Array[Color]) -> void:
	var beard := str(sel.get("beard", ""))
	if beard == "": return
	if beard in ["mustache", "moustache"]:
		Raster.line(img, 16, 21, 19, hair[3]); Raster.px(img, 16, 20, hair[4]); Raster.px(img, 21, 20, hair[4])
		return
	if beard == "handlebar":
		Raster.line(img, 16, 21, 19, hair[3]); Raster.px(img, 15, 18, hair[4]); Raster.px(img, 22, 18, hair[4])
		Raster.px(img, 15, 20, hair[3]); Raster.px(img, 22, 20, hair[3])
		return
	if beard == "stubble":
		# Drei kompakte Schattencluster am Kiefer statt sechs Streupixeln.
		Raster.line(img, 12, 13, 20, hair[4])
		Raster.line(img, 16, 18, 22, hair[4])
		Raster.line(img, 20, 21, 20, hair[4])
		return
	if beard == "soulpatch":
		Raster.line(img, 18, 19, 22, hair[3]); Raster.px(img, 19, 23, hair[4]); return
	if beard in ["goatee", "chin"]:
		Raster.line(img, 17, 20, 22, hair[3]); Raster.line(img, 17, 20, 23, hair[4])
		if beard == "goatee": Raster.line(img, 16, 21, 19, hair[4])
		return
	if beard == "sideburns":
		Raster.vline(img, 10, 15, 20, hair[3]); Raster.vline(img, 23, 15, 20, hair[4]); return
	if beard == "muttonchops":
		Raster.rect(img, 9, 16, 3, 6, hair[3]); Raster.rect(img, 22, 16, 3, 6, hair[4]); return
	# Voll- und Rauschebart rahmen den Mund frei ein; kein dunkler Mundschutz.
	Raster.line(img, 11, 13, 20, hair[3]); Raster.line(img, 21, 23, 20, hair[4])
	Raster.line(img, 12, 14, 22, hair[3]); Raster.line(img, 21, 23, 22, hair[4])
	Raster.line(img, 14, 21, 23, hair[3]); Raster.line(img, 15, 20, 24, hair[4])
	if beard == "longbeard":
		Raster.line(img, 14, 21, 25, hair[3]); Raster.line(img, 15, 20, 26, hair[4])

static func _draw_glasses(img: Image, sel: Dictionary) -> void:
	var kind := str(sel.get("glasses", ""))
	if kind == "": return
	# Warmer, leichter Rahmen statt schwarzer Doppelbox. Die Augen bleiben bei
	# allen Sehbrillen sichtbar; Sorte entsteht aus wenigen Randclustern.
	var frame := Color("745b5b")
	var hi := Color("aa8980")
	var far := Rect2i(10, 10, 6, 5)
	var near := Rect2i(17, 10, 7, 5)
	if kind == "sunglasses":
		var lens := Color("303a4a")
		Raster.rect(img, 11, 11, 4, 3, lens); Raster.rect(img, 18, 11, 5, 3, lens)
		Raster.line(img, 10, 15, 10, frame); Raster.line(img, 17, 23, 10, frame)
		Raster.line(img, 10, 15, 14, frame); Raster.line(img, 17, 23, 14, frame)
	else:
		_draw_lens_frame(img, far, kind, frame, hi, false)
		_draw_lens_frame(img, near, kind, frame, hi, true)
	# Kurzer Nasensteg und duenne Buegel, nie ein Balken ueber beide Brauen.
	Raster.px(img, 16, 12, frame); Raster.px(img, 9, 11, frame); Raster.line(img, 24, 25, 11, frame)

static func _draw_lens_frame(img: Image, r: Rect2i, kind: String, frame: Color, hi: Color, near: bool) -> void:
	var x0 := r.position.x; var x1 := r.end.x - 1
	var y0 := r.position.y; var y1 := r.end.y - 1
	match kind:
		"round":
			Raster.line(img, x0 + 2, x1 - 2, y0, hi); Raster.line(img, x0 + 2, x1 - 2, y1, frame)
			Raster.px(img, x0, y0 + 1, frame); Raster.px(img, x0, y1 - 1, frame)
			Raster.px(img, x1, y0 + 1, frame); Raster.px(img, x1, y1 - 1, frame)
		"square":
			Raster.px(img, x0 + 1, y0, hi); Raster.px(img, x1 - 1, y0, hi)
			Raster.px(img, x0 + 1, y1, frame); Raster.px(img, x1 - 1, y1, frame)
			Raster.px(img, x0, y0 + 1, frame); Raster.px(img, x0, y1 - 1, frame)
			Raster.px(img, x1, y0 + 1, frame); Raster.px(img, x1, y1 - 1, frame)
		"thick":
			Raster.line(img, x0, x1, y0, frame); Raster.line(img, x0, x1, y0 + 1, hi)
			Raster.line(img, x0, x1, y1, frame); Raster.vline(img, x0, y0 + 1, y1, frame); Raster.vline(img, x1, y0 + 1, y1, frame)
		"aviator":
			Raster.line(img, x0 + 1, x1 - 1, y0, hi); Raster.px(img, x0, y0 + 1, frame); Raster.px(img, x1, y0 + 1, frame)
			Raster.line(img, x0 + 1, x1 - 1, y1, frame); Raster.px(img, x1 - (1 if near else 2), y1 + 1, frame)
		"cat":
			Raster.line(img, x0 + 1, x1 - 1, y0, hi); Raster.px(img, x0, y0 - 1, frame); Raster.px(img, x1, y0 - 1, frame)
			Raster.px(img, x0, y0 + 1, frame); Raster.px(img, x1, y0 + 1, frame); Raster.line(img, x0 + 1, x1 - 1, y1, frame)
		"half":
			Raster.px(img, x0, y1 - 1, frame); Raster.line(img, x0 + 1, x1 - 1, y1, frame); Raster.px(img, x1, y1 - 1, frame)
		_:
			Raster.line(img, x0 + 1, x1 - 1, y0, hi); Raster.line(img, x0 + 1, x1 - 1, y1, frame)

static func _draw_accessories(img: Image, sel: Dictionary) -> void:
	var earring := str(sel.get("earring", ""))
	if earring != "":
		var metal := Color("d3b34d") if "gold" in earring else Color("bdc6ce")
		Raster.px(img, 7, 17, metal)
		if "hoop" in earring: Raster.px(img, 6, 18, metal); Raster.px(img, 7, 19, metal)
	var necklace := str(sel.get("necklace", ""))
	if necklace != "":
		var metal := Color("c5b15a")
		Raster.px(img, 13, 27, metal); Raster.px(img, 14, 28, metal); Raster.px(img, 20, 28, metal); Raster.px(img, 21, 27, metal)

static func _draw_hat(img: Image, sel: Dictionary, _hair: Array[Color]) -> void:
	var hat := str(sel.get("hat", ""))
	if hat in ["", "none"]:
		return
	# Hutfarbe = Kleidungsfarbe, exakt wie bei der Figur — Porträt und
	# Ganzkörper müssen als DIESELBE Person mit DEMSELBEN Hut lesbar sein.
	var cloth := AvatarPalette.portrait_cloth(str(sel.get("shirt_color", "teal")))
	if hat in ["cap", "cap_back"]:
		var crown := [[2, 11, 21], [3, 8, 24], [4, 7, 25], [5, 8, 25], [6, 9, 24]]
		_shape(img, crown, cloth[2], cloth[4])
		Raster.line(img, 9, 18, 3, cloth[1]); Raster.line(img, 8, 14, 4, cloth[0])
		if hat == "cap_back":
			Raster.line(img, 6, 14, 6, OUTLINE); Raster.line(img, 6, 12, 5, cloth[3])
		else:
			Raster.line(img, 14, 27, 6, OUTLINE); Raster.line(img, 17, 27, 5, cloth[3])
	elif hat == "flatcap":
		_shape(img, [[3, 11, 21], [4, 8, 24], [5, 7, 25]], cloth[2], cloth[4])
		Raster.line(img, 6, 26, 6, cloth[1]); Raster.line(img, 17, 27, 5, cloth[3])
	elif hat in ["beanie", "winter"]:
		_shape(img, [[1, 13, 19], [2, 10, 22], [3, 8, 24], [4, 7, 25],
			[5, 7, 25], [6, 7, 25]], cloth[2], cloth[4])
		Raster.line(img, 8, 24, 6, OUTLINE); Raster.line(img, 10, 22, 3, cloth[1])
		if hat == "winter":
			Raster.px(img, 15, 0, cloth[3]); Raster.px(img, 16, 0, cloth[4])
	elif hat == "bucket":
		_shape(img, [[2, 11, 21], [3, 9, 23], [4, 8, 24], [5, 8, 24]], cloth[2], cloth[4])
		# Krempe rundum eine Stufe breiter als die Krone.
		Raster.line(img, 6, 27, 5, cloth[1]); Raster.line(img, 6, 27, 6, cloth[0])
	elif hat == "sunhat":
		_shape(img, [[2, 12, 20], [3, 10, 22], [4, 9, 23], [5, 9, 23]], cloth[2], cloth[4])
		Raster.line(img, 3, 29, 6, cloth[1]); Raster.line(img, 5, 27, 7, cloth[0])
	elif hat == "tophat":
		Raster.rect(img, 10, 0, 14, 6, cloth[2]); Raster.line(img, 11, 22, 1, cloth[4])
		Raster.line(img, 9, 24, 5, cloth[1]); Raster.line(img, 6, 27, 6, cloth[0])
	elif hat == "fedora":
		_shape(img, [[1, 12, 21], [2, 9, 24], [3, 8, 24], [4, 8, 24]], cloth[2], cloth[4])
		Raster.line(img, 12, 15, 1, cloth[0]); Raster.line(img, 8, 24, 4, cloth[0]); Raster.line(img, 5, 28, 5, cloth[1])
	elif hat == "cowboy":
		_shape(img, [[0, 13, 20], [1, 10, 23], [2, 9, 24], [3, 9, 24], [4, 10, 23]], cloth[2], cloth[4])
		Raster.line(img, 9, 24, 4, cloth[0]); Raster.line(img, 4, 28, 6, cloth[1])
		Raster.px(img, 3, 5, cloth[3]); Raster.px(img, 29, 5, cloth[3])
	elif hat == "visor":
		Raster.line(img, 8, 25, 7, cloth[2]); Raster.line(img, 8, 25, 8, cloth[4])
		Raster.line(img, 20, 28, 9, cloth[0])
	elif hat == "headphones":
		Raster.line(img, 11, 21, 1, cloth[4])
		Raster.px(img, 10, 2, cloth[4]); Raster.px(img, 22, 2, cloth[4])
		Raster.line(img, 4, 6, 13, OUTLINE); Raster.line(img, 4, 6, 14, cloth[2])
		Raster.line(img, 4, 6, 15, cloth[1]); Raster.line(img, 4, 6, 16, OUTLINE)
		Raster.line(img, 26, 28, 13, OUTLINE); Raster.line(img, 26, 28, 14, cloth[1]); Raster.line(img, 26, 28, 16, OUTLINE)
	elif hat in ["headband", "bandana"]:
		# Band über der Stirn — konsistent zur Figur (dort dieselbe Lesart).
		Raster.line(img, 8, 25, 7, cloth[2]); Raster.line(img, 8, 25, 8, cloth[4])
		Raster.px(img, 8, 7, cloth[1]); Raster.px(img, 25, 7, cloth[1])
		if hat == "bandana": Raster.px(img, 6, 8, cloth[1]); Raster.px(img, 5, 9, cloth[0])
	elif hat == "party":
		for y in range(0, 7): Raster.line(img, 16 - y, 16 + y, y, cloth[2 if y % 2 == 0 else 3])
		Raster.px(img, 16, 0, cloth[4]); Raster.line(img, 9, 23, 7, cloth[0])
	elif hat == "crown":
		Raster.line(img, 8, 24, 6, GOLD); Raster.line(img, 9, 23, 5, GOLD)
		for x in [9, 13, 17, 21, 23]: Raster.vline(img, x, 2 + floori(absi(x - 17) / 4.0), 5, GOLD)
		for x in [9, 17, 23]: Raster.px(img, x, 2 + floori(absi(x - 17) / 4.0), Color("f4d66a"))
	elif hat == "santa":
		_shape(img, [[1, 12, 20], [2, 9, 23], [3, 8, 24], [4, 8, 24], [5, 7, 25]], Color("b63d48"), Color("e46a6e"))
		Raster.line(img, 7, 25, 6, Color("eee4d5")); Raster.line(img, 9, 23, 7, Color("d8d2c8"))
		Raster.px(img, 7, 1, Color("eee4d5")); Raster.px(img, 6, 2, Color("d8d2c8"))
	elif hat == "helmet":
		_shape(img, [[1, 13, 19], [2, 10, 22], [3, 8, 24], [4, 7, 25], [5, 7, 25], [6, 7, 25], [7, 8, 24]], cloth[1], cloth[3])
		Raster.line(img, 8, 24, 7, cloth[0]); Raster.vline(img, 8, 8, 14, cloth[0]); Raster.px(img, 9, 15, cloth[0])
	else:
		# Vorwaertskompatibler, kleiner Era-Hut fuer noch unbekannte Tokens.
		_shape(img, [[3, 10, 22], [4, 8, 24], [5, 8, 24], [6, 9, 23]], cloth[2], cloth[4])
		Raster.line(img, 10, 18, 4, cloth[1])
