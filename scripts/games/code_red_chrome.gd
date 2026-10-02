extends RefCounted
## CODE RED — Instrumententafel-Baukasten im OCS-Stil.
##
## Bis zur AAA-Ueberarbeitung besass nur der GEO-Screen echtes Amiga-Chrome
## (gefaste Bedienplatten, segmentierte LED-Balken, Eckwinkel, Gefahrenfeld);
## alle anderen Screens zeichneten flache Kaesten mit 1px-Rand. Dieses Modul
## hebt die GEO-Bausteine auf die Allgemeinheit, damit jeder Screen dieselbe
## Konsole benutzt.
##
## Alle Farben liegen auf dem 12-Bit-OCS-Registerraster (siehe quantise()) und
## bleiben damit innerhalb des Chipsatzvertrags. Gezeichnet wird ausschliesslich
## mit Rechtecken und Linien — kein Alpha-Verlauf, kein Weichzeichner, nichts,
## was ein Amiga 500 nicht in den Bildspeicher blitten koennte.
##
## BEWUSST ohne class_name (Pfad-preload, Klassen-Cache-Race — Projektregel).

const Contract := preload("res://scripts/games/amiga_video_contract.gd")

# --- Konsolenblech (erhabene Flaechen) -------------------------------------
const FACE := Color8(34, 51, 68)
const FACE_LIT := Color8(85, 119, 136)
const FACE_SHADE := Color8(17, 34, 34)

# --- Vertiefte Anzeigemulden (Messwerte, Listen) ---------------------------
# Bewusst blau statt teal: ueber der Bildkunst las die fruehere gruenstichige
# Mulde als eigene Flaeche mit, statt Text zu tragen.
const WELL := Color8(17, 17, 34)
const WELL_LIT := Color8(51, 68, 85)
const WELL_SHADE := Color8(0, 0, 17)

# --- Beschriftungsplatte (die orangen Schilder des GEO-Screens) ------------
const PLATE := Color8(136, 85, 34)
const PLATE_LIT := Color8(187, 136, 68)
const PLATE_SHADE := Color8(68, 34, 0)

const RIVET_LIT := Color8(136, 153, 170)
const RIVET_SHADE := Color8(17, 17, 34)

const LED_OFF := Color8(34, 51, 51)
const LED_WELL := Color8(0, 17, 17)


## Legt eine Farbe auf das Hardwareraster des Profils. Jede Farbe, die dieses
## Modul zeichnet, laeuft hierdurch — sonst kippt code_red_palette_check.
static func quantise(color: Color, profile: Dictionary) -> Color:
	return Contract.quantize_color(color, profile)


# ---------------------------------------------------------------- Copper

## Zeichnet ein echtes Copper-Programm als Rasterbaender. Die Instruktionen
## kommen aus dem Vertrag (hardwarequantisiert, nach Rasterzeile sortiert) und
## werden hier eins zu eins in Zeilenbaender uebersetzt — genau das, was der
## Copper eines Amiga pro Scanline in das Hintergrundregister schreibt.
static func copper_backdrop(canvas: CanvasItem, profile: Dictionary, rect: Rect2,
		top_color: Color, bottom_color: Color, steps := 24) -> Array[Dictionary]:
	var program: Array[Dictionary] = Contract.copper_gradient(
		profile, 0, int(rect.position.y), int(rect.end.y - 1.0),
		top_color, bottom_color, steps)
	for index in program.size():
		var instruction: Dictionary = program[index]
		var band_top := float(instruction.get("scanline", 0))
		var band_bottom := rect.end.y
		if index + 1 < program.size():
			band_bottom = float((program[index + 1] as Dictionary).get("scanline", 0))
		if band_bottom <= band_top:
			continue
		canvas.draw_rect(
			Rect2(rect.position.x, band_top, rect.size.x, band_bottom - band_top),
			instruction.get("color", top_color))
	return program


# ---------------------------------------------------------------- Flaechen

## Erhabene Bedienplatte: hell oben/links, dunkel unten/rechts. Zwei Pixel
## Fase, wie es die Amiga-Oberflaechen dieser Jahre durchweg hielten.
static func bevel_panel(canvas: CanvasItem, rect: Rect2, profile: Dictionary,
		face := FACE, lit := FACE_LIT, shade := FACE_SHADE) -> void:
	canvas.draw_rect(rect, quantise(face, profile))
	_bevel_edges(canvas, rect, quantise(lit, profile), quantise(shade, profile))


## Vertiefte Mulde fuer Messwerte und Listen — dieselbe Fase, nur invertiert.
static func inset_well(canvas: CanvasItem, rect: Rect2, profile: Dictionary,
		face := WELL, lit := WELL_LIT, shade := WELL_SHADE) -> void:
	canvas.draw_rect(rect, quantise(face, profile))
	_bevel_edges(canvas, rect, quantise(shade, profile), quantise(lit, profile))


static func _bevel_edges(canvas: CanvasItem, rect: Rect2, lit: Color, shade: Color) -> void:
	var right := rect.end.x - 1.0
	var bottom := rect.end.y - 1.0
	# Oben und links
	canvas.draw_line(rect.position, Vector2(right, rect.position.y), lit, 1.0)
	canvas.draw_line(rect.position, Vector2(rect.position.x, bottom), lit, 1.0)
	# Unten und rechts
	canvas.draw_line(Vector2(rect.position.x, bottom), Vector2(right, bottom), shade, 1.0)
	canvas.draw_line(Vector2(right, rect.position.y), Vector2(right, bottom), shade, 1.0)


## Niete: zwei Pixel, hell oben links, dunkel unten rechts. Das Detail, das
## flaches Blech zu einer Konsole macht.
static func rivet(canvas: CanvasItem, centre: Vector2, profile: Dictionary) -> void:
	canvas.draw_rect(Rect2(centre.x, centre.y, 1, 1), quantise(RIVET_LIT, profile))
	canvas.draw_rect(Rect2(centre.x + 1.0, centre.y + 1.0, 1, 1),
		quantise(RIVET_SHADE, profile))


## Setzt Nieten in alle vier Ecken einer Platte.
static func rivet_corners(canvas: CanvasItem, rect: Rect2, profile: Dictionary,
		margin := 2.0) -> void:
	rivet(canvas, rect.position + Vector2(margin, margin), profile)
	rivet(canvas, Vector2(rect.end.x - margin - 2.0, rect.position.y + margin), profile)
	rivet(canvas, Vector2(rect.position.x + margin, rect.end.y - margin - 2.0), profile)
	rivet(canvas, rect.end - Vector2(margin + 2.0, margin + 2.0), profile)


# ---------------------------------------------------------------- Anzeigen

## Segmentierter LED-Balken (verallgemeinert aus dem GEO-Screen). Ein Amiga
## zeigte Messwerte als diskrete Blocks, nicht als glatten Farbstreifen.
static func segment_bar(canvas: CanvasItem, rect: Rect2, profile: Dictionary,
		value: float, color: Color, segments := 12) -> void:
	canvas.draw_rect(rect, quantise(LED_WELL, profile))
	var count := maxi(1, segments)
	var width := (rect.size.x - float(count - 1)) / float(count)
	if width <= 0.0:
		return
	var active := int(ceil(clampf(value, 0.0, 100.0) / 100.0 * float(count)))
	var lit := quantise(color, profile)
	var off := quantise(LED_OFF, profile)
	for i in count:
		canvas.draw_rect(
			Rect2(rect.position.x + float(i) * (width + 1.0), rect.position.y,
				width, rect.size.y),
			lit if i < active else off)


## Eckwinkel — die Zielmarkierung des GEO-Screens, jetzt fuer jede Auswahl.
static func corner_brackets(canvas: CanvasItem, rect: Rect2, color: Color,
		length := 5.0) -> void:
	var right := rect.end.x
	var bottom := rect.end.y
	canvas.draw_line(rect.position, rect.position + Vector2(length, 0), color, 1.0)
	canvas.draw_line(rect.position, rect.position + Vector2(0, length), color, 1.0)
	canvas.draw_line(Vector2(right, rect.position.y),
		Vector2(right - length, rect.position.y), color, 1.0)
	canvas.draw_line(Vector2(right, rect.position.y),
		Vector2(right, rect.position.y + length), color, 1.0)
	canvas.draw_line(Vector2(rect.position.x, bottom),
		Vector2(rect.position.x + length, bottom), color, 1.0)
	canvas.draw_line(Vector2(rect.position.x, bottom),
		Vector2(rect.position.x, bottom - length), color, 1.0)
	canvas.draw_line(rect.end, rect.end - Vector2(length, 0), color, 1.0)
	canvas.draw_line(rect.end, rect.end - Vector2(0, length), color, 1.0)


## Diagonale Gefahrenstreifen — der rot-schwarze Rand des Warnfeldes.
static func hazard_stripes(canvas: CanvasItem, rect: Rect2, profile: Dictionary,
		color: Color, spacing := 4.0) -> void:
	var stripe := quantise(color, profile)
	var span := rect.size.x + rect.size.y
	var x := -rect.size.y
	while x < span:
		var from := Vector2(rect.position.x + x, rect.end.y)
		var to := Vector2(rect.position.x + x + rect.size.y, rect.position.y)
		# Auf das Rechteck begrenzen, damit die Streifen nicht ausbrechen.
		if from.x < rect.position.x:
			from = Vector2(rect.position.x, rect.end.y - (rect.position.x - from.x))
		if to.x > rect.end.x:
			to = Vector2(rect.end.x, rect.position.y + (to.x - rect.end.x))
		if from.y > rect.position.y and to.y < rect.end.y:
			canvas.draw_line(from, to, stripe, 1.0)
		x += spacing


## Fuellt ein Polygon mit zwei Registerfarben im Rasterzeilen-Dither.
##
## Ein OCS-Bild kennt keine Alphamischung: Zwischentoene entstanden, indem der
## Blitter zwei Register zeilenweise verschraenkte. Genau das passiert hier —
## die Grundfarbe deckt flaechig, die Deckfarbe liegt in jeder n-ten Rasterzeile
## darueber. Bei ratio 0 bleibt die Grundfarbe, bei 1 deckt die zweite voll.
##
## Die Zeilenspannen werden je Zeile aus den Polygonkanten geschnitten — bei
## acht Ecken und 70 Zeilen sind das ein paar hundert Rechenschritte, also
## billig genug fuer den Frame-Loop.
static func dither_polygon(canvas: CanvasItem, points: PackedVector2Array,
		base: Color, top: Color, ratio: float, profile: Dictionary) -> void:
	if points.size() < 3:
		return
	var solid_base := quantise(base, profile)
	canvas.draw_colored_polygon(points, solid_base)
	var mix := clampf(ratio, 0.0, 1.0)
	if mix <= 0.02:
		return
	var solid_top := quantise(top, profile)
	if mix >= 0.98:
		canvas.draw_colored_polygon(points, solid_top)
		return
	# 1 von 4, 1 von 2 oder 3 von 4 Zeilen — die drei Stufen, die ein
	# 32-Register-Bild sauber traegt.
	var period := 4
	var lit_rows := 1
	if mix >= 0.66:
		lit_rows = 3
	elif mix >= 0.33:
		lit_rows = 2
	var top_y := INF
	var bottom_y := -INF
	for p: Vector2 in points:
		top_y = minf(top_y, p.y)
		bottom_y = maxf(bottom_y, p.y)
	var y := floorf(top_y)
	while y <= bottom_y:
		if fposmod(y, float(period)) < float(lit_rows):
			var centre := y + 0.5
			var crossings: Array[float] = []
			for i in points.size():
				var a := points[i]
				var b := points[(i + 1) % points.size()]
				if (a.y <= centre and b.y > centre) or (b.y <= centre and a.y > centre):
					crossings.append(a.x + (centre - a.y) / (b.y - a.y) * (b.x - a.x))
			crossings.sort()
			var span := 0
			while span + 1 < crossings.size():
				canvas.draw_rect(Rect2(crossings[span], y,
					maxf(1.0, crossings[span + 1] - crossings[span]), 1.0), solid_top)
				span += 2
		y += 1.0


## Lochraster-Lueftungsgitter — fuellt tote Blechflaechen, statt sie leer zu
## lassen. Genau das taten die Kuenstler dieser Aera mit Restflaechen.
static func vent_grille(canvas: CanvasItem, rect: Rect2, profile: Dictionary,
		spacing := 3.0) -> void:
	var hole := quantise(FACE_SHADE, profile)
	var gleam := quantise(FACE_LIT, profile)
	var y := rect.position.y + 1.0
	while y < rect.end.y - 1.0:
		var x := rect.position.x + 1.0
		while x < rect.end.x - 1.0:
			canvas.draw_rect(Rect2(x, y, 1, 1), hole)
			canvas.draw_rect(Rect2(x + 1.0, y + 1.0, 1, 1), gleam)
			x += spacing
		y += spacing
