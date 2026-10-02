class_name Wb13Icons
## Icon-Kunst der WERKBANK 1.3 — nachempfunden den Original-Workbench-1.3-Icons
## (Schubladen, Shell, Prefs, Mülleimer, Disketten …) in der 4-Farben-Palette.
## Icons werden als Zeichengitter gebaut (K=schwarz W=weiß O=orange B=blau,
## Punkt = durchsichtig) und zu Texturen gebacken; „ausgewählt“ = Komplement-
## Farben wie im Original (blau↔orange, weiß↔schwarz). Native Pixel: Fenster
## zeichnen die Textur doppelt hoch (640×200-Hires-Look).

static var _cache: Dictionary = {}


## Palette-Wechsel (Preferences) → Texturen neu backen.
static func flush() -> void:
	_cache = {}


## Icon-Textur; kind s. _rows(). selected = Komplementfarben.
static func tex(kind: String, selected := false) -> ImageTexture:
	var key := kind + ("!" if selected else "")
	if _cache.has(key):
		return _cache[key]
	var map := {
		"K": Wb13.col(1) if selected else Wb13.col(2),
		"W": Wb13.col(2) if selected else Wb13.col(1),
		"O": Wb13.col(0) if selected else Wb13.col(3),
		"B": Wb13.col(3) if selected else Wb13.col(0),
	}
	var t := PixelArt.make_texture(_rows(kind), map)
	_cache[key] = t
	return t


## Nativgröße (Pixel) eines Icons.
static func icon_size(kind: String) -> Vector2i:
	var rows := _rows(kind)
	var w := 0
	for r in rows:
		w = maxi(w, String(r).length())
	return Vector2i(w, rows.size())


# --------------------------------------------------------------- Zeichengitter

class Grid:
	var w: int
	var h: int
	var cells: Array = []

	func _init(width: int, height: int) -> void:
		w = width
		h = height
		for y in h:
			var row := []
			row.resize(w)
			row.fill(".")
			cells.append(row)

	func put(x: int, y: int, ch: String) -> void:
		if x >= 0 and x < w and y >= 0 and y < h:
			cells[y][x] = ch

	func fill_rect(x: int, y: int, rw: int, rh: int, ch: String) -> void:
		for yy in range(y, y + rh):
			for xx in range(x, x + rw):
				put(xx, yy, ch)

	func box(x: int, y: int, rw: int, rh: int, ch: String) -> void:
		for xx in range(x, x + rw):
			put(xx, y, ch)
			put(xx, y + rh - 1, ch)
		for yy in range(y, y + rh):
			put(x, yy, ch)
			put(x + rw - 1, yy, ch)

	func blit(x: int, y: int, src_rows: Array) -> void:
		for yy in src_rows.size():
			var s := String(src_rows[yy])
			for xx in s.length():
				if s[xx] != ".":
					put(x + xx, y + yy, s[xx])

	func rows() -> Array:
		var out := []
		for row in cells:
			out.append("".join(row))
		return out


# ------------------------------------------------------------------- Bausteine

## 3D-Schublade (Utilities/System/…): Frontfach mit Griff, Tiefe nach rechts oben.
static func _drawer(g: Grid, ox: int, oy: int) -> void:
	const FW := 36  # Frontbreite
	const FH := 10  # Fronthöhe
	const D := 4    # Tiefe
	# Deckelfläche (Parallelogramm)
	for i in range(D + 1):
		var y := oy + D - i
		var x0 := ox + i
		g.put(x0, y, "K")
		g.put(x0 + FW - 1, y, "K")
		for xx in range(x0 + 1, x0 + FW - 1):
			g.put(xx, y, "W" if i > 0 and i < D else "K")
	# rechte Seitenfläche
	for i in range(D + 1):
		g.put(ox + FW - 1 + i, oy + D - i, "K")
		for yy in range(oy + D - i + 1, oy + D - i + FH):
			if yy <= oy + D + FH - 1:
				g.put(ox + FW - 1 + i, yy, "W" if i > 0 else "K")
	for i in range(D + 1):
		g.put(ox + FW - 1 + i, oy + D - i + FH - 1, "K")
	# Front
	g.fill_rect(ox, oy + D, FW, FH, "W")
	g.box(ox, oy + D, FW, FH, "K")
	g.box(ox + 2, oy + D + 2, FW - 4, FH - 4, "K")
	g.fill_rect(ox + 3, oy + D + 3, FW - 6, FH - 6, "W")
	# Griffschlitz
	g.box(ox + floori(FW / 2.0) - 5, oy + D + floori(FH / 2.0) - 1, 10, 2, "K")


## 3,5"-Diskette: Schieber oben, Ecke rechts oben abgeschrägt, Label unten.
static func _disk(g: Grid, ox: int, oy: int, style: String) -> void:
	const DW := 26
	const DH := 20
	g.fill_rect(ox, oy, DW, DH, "W")
	g.box(ox, oy, DW, DH, "K")
	for i in range(4):  # Ecke abschrägen
		for xx in range(DW - 4 + i, DW):
			g.put(ox + xx, oy + i, "." if xx > DW - 5 + i else "K")
		g.put(ox + DW - 5 + i, oy + i, "K")
	# Metallschieber mit Fenster
	g.box(ox + 7, oy, 12, 7, "K")
	g.fill_rect(ox + 14, oy + 1, 3, 5, "K")
	match style:
		"wb":   # bunte Systemdiskette: Schräglinien + orange Ecke
			g.fill_rect(ox + 2, oy + 9, DW - 4, 9, "K")
			for d in range(0, 22, 3):
				for i in range(9):
					var xx := ox + 2 + d + i - 4
					if xx >= ox + 2 and xx < ox + DW - 2:
							g.put(xx, oy + 9 + i, "W" if floori(d / 3.0) % 2 == 0 else "O")
			g.fill_rect(ox + 2, oy + 9, 5, 3, "O")
		"ram":  # RAM-Disk: oranger Kopfbereich
			g.fill_rect(ox + 1, oy + 1, 6, 6, "O")
			g.fill_rect(ox + 19, oy + 1, 3, 6, "O")
			g.fill_rect(ox + 3, oy + 10, DW - 6, 7, "W")
			g.box(ox + 3, oy + 10, DW - 6, 7, "K")
			g.blit(ox + 6, oy + 12, ["K.KKK.K.K", "KK.K..KK.", "K..K..K.K"])
		_:      # schlichte Diskette mit Etikett
			g.box(ox + 3, oy + 9, DW - 6, 9, "K")
			g.fill_rect(ox + 4, oy + 10, DW - 8, 7, "W")
			for yy in [12, 14]:
				for xx in range(ox + 6, ox + DW - 6):
					g.put(xx, oy + yy, "K")


static func _window(g: Grid, ox: int, oy: int, w: int, h: int, interior: String) -> void:
	g.fill_rect(ox, oy, w, h, interior)
	g.box(ox, oy, w, h, "K")
	for xx in range(ox, ox + w):
		g.put(xx, oy + 4, "K")
	g.fill_rect(ox + 1, oy + 1, w - 2, 3, "W")
	g.fill_rect(ox + w - 4, oy + 1, 2, 3, "K")
	g.fill_rect(ox + w - 8, oy + 1, 2, 3, "O")


const PROMPT := [".K...K", "KK....K", ".K.....K", ".K....K", "KKK..K"]


# ------------------------------------------------------------------- Icon-Arten

static func _rows(kind: String) -> Array:
	var g: Grid
	match kind:
		"drawer", "folder":
			g = Grid.new(42, 15)
			_drawer(g, 0, 0)
		"prefs_drawer":
			g = Grid.new(42, 17)
			_drawer(g, 0, 2)
			g.blit(15, 0, ["..OOOO", ".O..OO", "....OO", "...OO", "..OO"])
		"shell", "term":
			g = Grid.new(30, 20)
			_window(g, 0, 0, 30, 18, "W")
			g.blit(3, 7, PROMPT)
			if kind == "term":
				g.blit(14, 8, ["O.O.O", "OO.OO.O", "....O.OO"])
		"cli":
			g = Grid.new(30, 20)
			_window(g, 0, 0, 30, 18, "O")
			g.blit(3, 7, PROMPT)
		"trashcan":
			g = Grid.new(26, 18)
			# Korbgeflecht-Mülleimer
			g.fill_rect(2, 3, 22, 3, "O")
			g.box(2, 3, 22, 3, "K")
			for i in range(12):
				var inset := floori(i / 4.0)
				g.put(3 + inset, 6 + i, "K")
				g.put(22 - inset, 6 + i, "K")
				for xx in range(4 + inset, 22 - inset):
					g.put(xx, 6 + i, "O" if (xx + i) % 3 != 0 else "K")
			g.blit(10, 0, ["KKKKK", "K...K"])
		"disk", "disk_plain":
			g = Grid.new(26, 20)
			_disk(g, 0, 0, "plain")
		"disk_wb":
			g = Grid.new(26, 20)
			_disk(g, 0, 0, "wb")
		"disk_ram":
			g = Grid.new(26, 20)
			_disk(g, 0, 0, "ram")
		"harddisk":
			# Frühe Workbench-Festplatte: flaches externes/interne Laufwerk mit
			# Status-LED und DH-Plakette statt eines Disketten-Piktogramms.
			g = Grid.new(34, 17)
			g.fill_rect(1, 4, 32, 12, "W")
			g.box(1, 4, 32, 12, "K")
			g.fill_rect(4, 7, 26, 5, "B")
			g.box(4, 7, 26, 5, "K")
			g.blit(10, 7, ["K.K.K.KK", "KKK.K.K.", "K.K.K.KK"])
			g.fill_rect(5, 14, 5, 1, "K")
			g.fill_rect(25, 14, 3, 1, "O")
		"clock":
			# rund AUF DEM SCHIRM: Zeilen zählen doppelt (640×200-Pixel sind hoch)
			g = Grid.new(24, 12)
			for yy in 12:
				for xx in 24:
					var d := Vector2(xx - 11.5, (yy - 5.5) * 2.0).length()
					if d <= 11.4 and d >= 9.6:
						g.put(xx, yy, "K")
					elif d < 9.6:
						g.put(xx, yy, "W")
			for p in [[11, 1], [12, 1], [20, 5], [20, 6], [11, 10], [12, 10], [3, 5], [3, 6]]:
				g.put(p[0], p[1], "K")  # Markierungen 12/3/6/9
			for i in range(4):  # Zeiger auf „10 nach 10“
					g.put(12 + i, 5 - floori(i / 2.0), "K")
					g.put(11 - i, 4 + floori(i / 4.0), "K")
			g.put(11, 5, "K")
			g.put(12, 5, "K")
		"clockptr":
			# Digitaluhr-Kästchen („1025“) wie das Original-Icon
			g = Grid.new(20, 10)
			g.fill_rect(0, 0, 20, 10, "W")
			g.box(0, 0, 20, 10, "K")
			g.blit(2, 2, [".K.", "KK.", ".K.", ".K.", "KKK"])           # 1
			g.blit(6, 2, ["KKK", "K.K", "K.K", "K.K", "KKK"])           # 0
			g.blit(10, 2, ["KKK", "..K", "KKK", "K..", "KKK"])          # 2
			g.blit(14, 2, ["KKK", "K..", "KKK", "..K", "KKK"])          # 5
		"cmd":
			# Flachbandkabel → Kästchen (Druckerausgabe umleiten)
			g = Grid.new(28, 10)
			g.fill_rect(0, 2, 10, 6, "W")
			g.box(0, 2, 10, 6, "K")
			for xx in range(2, 9, 2):
				g.put(xx, 3, "K")
				g.put(xx, 6, "K")
			g.blit(11, 3, ["..O", "OOOO", "..O"])
			g.fill_rect(17, 1, 10, 8, "W")
			g.box(17, 1, 10, 8, "K")
			g.blit(19, 3, ["KKKKK", ".....", "KKK"])
		"graphicdump":
			# Monitor → Drucker (Bildschirm drucken)
			g = Grid.new(34, 14)
			g.fill_rect(0, 0, 14, 10, "W")
			g.box(0, 0, 14, 10, "K")
			g.box(1, 1, 12, 8, "K")
			g.fill_rect(3, 3, 8, 4, "O")
			g.fill_rect(4, 10, 6, 2, "K")                               # Fuß
			g.blit(15, 4, ["..O", "OOOO", "..O"])
			g.fill_rect(20, 4, 14, 8, "W")
			g.box(20, 4, 14, 8, "K")
			g.fill_rect(23, 1, 8, 4, "W")
			g.box(23, 1, 8, 4, "K")
			g.fill_rect(22, 7, 10, 1, "K")
		"printfiles":
			# zwei Blätter → Drucker
			g = Grid.new(34, 14)
			for o in [[0, 2], [3, 0]]:
				g.fill_rect(o[0], o[1], 9, 11, "W")
				g.box(o[0], o[1], 9, 11, "K")
			for yy in [3, 5, 7]:
				for xx in range(5, 10):
					g.put(xx, yy, "K")
			g.blit(13, 5, ["..O", "OOOO", "..O"])
			g.fill_rect(18, 3, 16, 9, "W")
			g.box(18, 3, 16, 9, "K")
			g.fill_rect(20, 6, 12, 1, "K")
			g.fill_rect(28, 8, 3, 2, "O")
		"installprinter":
			# Drucker + Treiber-Diskette
			g = Grid.new(32, 15)
			g.fill_rect(8, 0, 24, 9, "W")
			g.box(8, 0, 24, 9, "K")
			g.fill_rect(10, 3, 20, 1, "K")
			g.fill_rect(25, 5, 4, 2, "O")
			g.fill_rect(0, 7, 12, 8, "W")
			g.box(0, 7, 12, 8, "K")
			g.box(3, 7, 6, 3, "K")
			g.fill_rect(2, 11, 8, 3, "K")
		"fastmem":
			# der liegende Hase (FastMemFirst)
			g = Grid.new(32, 11)
			g.blit(0, 0, [
				"..KK............................",
				".KWWK...........................",
				"..KWWK..........................",
				"...KWWKKKKKKKKKKKKKK............",
				"..KWWWWWWWWWWWWWWWWWKK......KK..",
				".KWKWWWWWWWWWWWWWWWWWWK....KWWK.",
				".KWWWWWWWWWWWWWWWWWWWWWKKKKWWK..",
				"..KWWWWWWWWWWWWWWWWWWWWWWWWWK...",
				"...KWW..KWWK......KWWK..KWWK....",
				"....KK...KK........KK....KK.....",
			])
		"nofastmem":
			# Hase im Verbotsschild (NoFastMem)
			g = Grid.new(26, 13)
			g.blit(7, 3, [
				".KK.........",
				"..KK........",
				".KWWKKKKK...",
				"KWWWWWWWWK..",
				".KWW..KWK...",
				"..KK...KK...",
			])
			for yy in 13:
				for xx in 26:
					var dd := Vector2(xx - 12.5, (yy - 6.0) * 2.0).length()
					if dd <= 12.4 and dd >= 10.6:
						g.put(xx, yy, "O")
			for i in range(16):  # Schrägstrich
				g.put(5 + i, 11 - floori(i * 0.65), "O")
		"setmap":
			# Tastatur mit Landkarte (Tastaturbelegung)
			g = Grid.new(30, 13)
			g.fill_rect(0, 5, 30, 8, "W")
			g.box(0, 5, 30, 8, "K")
			for yy in [7, 9]:
				for xx in range(2, 28, 3):
					g.put(xx, yy, "K")
			g.fill_rect(6, 11, 18, 1, "K")   # Leertaste
			g.blit(16, 0, ["..OOO....", ".OOOOOO..", "OOO.OOOO.", ".OO..OO..", "...OO...."])
		"mergemem":
			# orange Raute mit Pfeilen nach innen (MergeMem)
			g = Grid.new(24, 13)
			for yy in 13:
				for xx in 24:
					var dd := absf(xx - 11.5) + absf((yy - 6.0) * 2.0)
					if dd <= 12.2 and dd >= 10.2:
						g.put(xx, yy, "O")
			g.blit(4, 5, ["..K", "KKKK", "..K"])
			g.blit(16, 5, ["K..", "KKKK", "K.."])
		"fixfonts":
			# Blatt mit großem „a“ (FixFonts)
			g = Grid.new(22, 14)
			g.fill_rect(2, 0, 17, 14, "W")
			g.box(2, 0, 17, 14, "K")
			g.blit(6, 3, [".KKKK", "....K", ".KKKK", "K...K", ".KKKK"])
			g.fill_rect(6, 10, 10, 1, "O")
		"copyprefs":
			# Prefs-Rolle → kleinere Rolle (CopyPrefs)
			g = Grid.new(34, 12)
			g.fill_rect(1, 2, 13, 8, "W")
			g.box(1, 2, 13, 8, "K")
			g.box(0, 1, 3, 10, "K")
			g.blit(5, 3, ["OOO", "..O", ".OO", "...", ".O"])
			g.blit(15, 4, ["..O", "OOOO", "..O"])
			g.fill_rect(21, 3, 11, 6, "W")
			g.box(21, 3, 11, 6, "K")
			g.box(20, 2, 3, 8, "K")
		"notepad", "text":
			g = Grid.new(28, 19)
			g.fill_rect(0, 3, 22, 15, "W")
			g.box(0, 3, 22, 15, "K")
			for xx in range(2, 20, 3):  # Spiralbindung
				g.put(xx, 2, "K")
				g.put(xx, 3, "W")
			for yy in [7, 10, 13]:
				for xx in range(3, 17):
					g.put(xx, yy, "K")
			for i in range(8):  # Stift
					g.put(19 + 1 - floori(i / 4.0), 16 - i, "O")
					g.put(20 + 1 - floori(i / 4.0), 16 - i, "O")
			g.put(19, 17, "K")
		"calculator":
			g = Grid.new(22, 19)
			g.fill_rect(0, 0, 22, 19, "W")
			g.box(0, 0, 22, 19, "K")
			g.fill_rect(3, 2, 16, 3, "O")
			g.box(3, 2, 16, 3, "K")
			for ky in range(3):
				for kx in range(4):
					g.fill_rect(3 + kx * 4, 7 + ky * 4, 3, 2, "K")
		"more":
			g = Grid.new(22, 20)
			g.fill_rect(1, 0, 20, 20, "W")
			g.box(1, 0, 20, 20, "K")
			for yy in [3, 5, 7]:
				for xx in range(4, 18):
					g.put(xx, yy, "K")
			g.blit(7, 10, ["..OO", "..OO", "..OO", "OOOOOO", ".OOOO", "..OO"])
		"say":
			g = Grid.new(26, 18)
			g.fill_rect(1, 1, 24, 12, "W")
			g.box(1, 1, 24, 12, "K")
			g.blit(5, 14, [".KK", "KK"])  # Sprechblasen-Zipfel
			# „!?*“ wie das Original-Geplapper
			g.blit(5, 3, ["KK", "KK", "KK", "..", "KK"])
			g.blit(10, 3, ["OOOO", "...O", ".OOO", ".O..", ".O", "....", ".O"])
			g.blit(18, 4, ["K.K", ".K.", "K.K"])
		"diskcopy", "copy":
			g = Grid.new(42, 18)
			_disk(g, 0, 0, "plain")
			g.blit(28, 2, ["......KK", "..KKKKKKK", "KKKKKKKKKK", "..KKKKKKK", "......KK"])
			g.fill_rect(28, 8, 14, 10, "W")
			g.box(28, 8, 14, 10, "K")
			g.blit(33, 10, [".K", "KK", ".K", ".K", "KKK"])
		"format":
			g = Grid.new(34, 20)
			_disk(g, 0, 0, "plain")
			g.blit(28, 4, ["OOOO", "O", "OOO", "O", "O"])  # F
		"pointer":
			g = Grid.new(18, 18)
			for i in range(12):
				g.put(2, 2 + i, "K")
				var wdt := mini(i, 7)
				for xx in range(3, 3 + wdt):
					g.put(xx, 2 + i, "O" if xx > 3 else "W")
				g.put(3 + wdt, 2 + i, "K")
			g.blit(5, 12, ["KOK", ".KOK", ".KOK", "..KK"])
		"printer":
			g = Grid.new(32, 19)
			g.fill_rect(6, 0, 20, 8, "W")
			g.box(6, 0, 20, 8, "K")
			for yy in [2, 4]:
				for xx in range(8, 24):
					g.put(xx, yy, "K")
			g.fill_rect(0, 8, 32, 9, "W")
			g.box(0, 8, 32, 9, "K")
			g.fill_rect(3, 10, 26, 1, "K")  # Papierschlitz
			g.fill_rect(24, 13, 4, 2, "O")  # LED
		"serial", "modem":
			g = Grid.new(30, 18)
			# Telefon: Hörer + Sockel mit Wählscheibe
			g.blit(2, 0, ["..KKKK", ".KWWWWK", "KWWKKWWK", "KWK..KWK", "KK....KK"])
			g.blit(18, 0, ["..KKKK", ".KWWWWK", "KWWKKWWK", "KWK..KWK", "KK....KK"])
			g.fill_rect(6, 2, 16, 2, "K")
			for i in range(10):
				var inset := 4 - floori(i / 3.0)
				g.put(inset, 7 + i, "K")
				g.put(29 - inset, 7 + i, "K")
				for xx in range(inset + 1, 29 - inset):
					g.put(xx, 7 + i, "W")
			g.box(11, 9, 6, 5, "K")  # Wählscheibe
		"preferences", "gear":
			g = Grid.new(34, 18)
			# Schriftrolle mit großem Fragezeichen (Preferences 1.3)
			g.fill_rect(4, 3, 26, 12, "W")
			g.box(4, 3, 26, 12, "K")
			g.box(0, 2, 5, 14, "K")
			g.fill_rect(1, 3, 3, 12, "W")
			g.box(29, 2, 5, 14, "K")
			g.fill_rect(30, 3, 3, 12, "W")
			g.blit(13, 4, ["OOOOO", "OO..OO", "....OO", "...OO", "..OO", "..OO", "......", "..OO"])
		"project":
			g = Grid.new(26, 21)
			for xx in range(0, 26, 2):  # gestreifte Matte
				for yy in range(0, 21):
					g.put(xx, yy, "K")
			g.fill_rect(3, 2, 20, 17, "W")
			g.box(3, 2, 20, 17, "K")
			g.blit(17, 2, ["KKKKK", ".KWWK", "..KWK", "...KK"])
			for yy in [5, 7, 9, 12, 14]:
				for xx in range(5, 19 if yy != 9 else 13):
					g.put(xx, yy, "K")
		"tool", "app":
			g = Grid.new(28, 18)
			_window(g, 0, 0, 28, 16, "W")
			g.blit(4, 7, ["O", "O", "O", "O", "OOOOOO"])  # Werkzeug-L
			g.blit(13, 7, ["KKKKK", "..K", "..K", "..K", "..K"])
		"note":
			g = Grid.new(24, 20)
			g.fill_rect(0, 0, 20, 20, "W")
			g.box(0, 0, 20, 20, "K")
			for yy in [3, 16]:
				for xx in range(2, 18):
					g.put(xx, yy, "K")
			g.blit(6, 6, ["....K", "....K", "....K", "....K", ".KKKK", "KKKKK", "KKKK"])
			g.blit(13, 5, ["...O", "...O", "...O", "..OO", "OOOO", "OOO"])
		"paint":
			g = Grid.new(30, 18)
			for yy in 12:  # Palette (Ellipse grob)
				var inset := floori(absi(yy - 6) / 2.0)
				for xx in range(2 + inset, 26 - inset):
					g.put(xx, 3 + yy, "W")
				g.put(1 + inset, 3 + yy, "K")
				g.put(26 - inset, 3 + yy, "K")
			for xx in range(4, 24):
				g.put(xx, 2, "K")
				g.put(xx, 15, "K")
			g.fill_rect(6, 6, 3, 2, "O")
			g.fill_rect(12, 5, 3, 2, "B")
			g.fill_rect(18, 6, 3, 2, "K")
			g.fill_rect(9, 10, 3, 2, "K")
			for i in range(7):  # Pinsel
				g.put(22 + 1 - floori(i / 3.0), 14 - i, "O")
			g.blit(21, 14, ["KK"])
		"virus":
			g = Grid.new(26, 18)
			for yy in 10:  # Käferkörper
				var inset := floori(absi(yy - 5) / 2.0) + 1
				for xx in range(8 + inset, 19 - inset):
					g.put(xx, 4 + yy, "K")
			g.fill_rect(11, 6, 2, 2, "O")
			g.fill_rect(14, 9, 2, 2, "O")
			g.fill_rect(11, 11, 2, 1, "O")
			for i in 3:  # Beine
				g.blit(4, 5 + i * 3, ["KKKK"])
				g.blit(18, 5 + i * 3, ["KKKK"])
			g.blit(9, 1, ["K...K", ".K.K"])  # Fühler
		"chip":
			g = Grid.new(30, 16)
			g.fill_rect(2, 4, 26, 8, "W")
			g.box(2, 4, 26, 8, "K")
			g.fill_rect(2, 7, 3, 2, "K")  # Kerbe
			for xx in range(5, 26, 4):
				g.fill_rect(xx, 1, 2, 3, "K")
				g.fill_rect(xx, 12, 2, 3, "K")
			g.fill_rect(8, 6, 14, 1, "K")
			g.fill_rect(8, 9, 9, 1, "K")
		"archive":
			g = Grid.new(28, 17)
			g.fill_rect(0, 4, 28, 12, "W")
			g.box(0, 4, 28, 12, "K")
			g.box(0, 1, 28, 4, "K")
			g.fill_rect(1, 2, 26, 2, "W")
			g.fill_rect(13, 1, 2, 15, "K")  # Spanngurt
			g.fill_rect(13, 7, 2, 2, "O")
			g.fill_rect(13, 11, 2, 2, "O")
		"gauge":
			g = Grid.new(26, 16)
			for yy in 12:
				var inset := maxi(0, 6 - yy) * 2
				for xx in range(1 + floori(inset / 2.0), 25 - floori(inset / 2.0)):
					g.put(xx, 3 + yy, "W")
			g.box(0, 3, 26, 13, "K")
			for p in [[4, 6], [12, 4], [20, 6]]:
				g.put(p[0], p[1], "K")
			for i in range(7):  # Nadel Richtung rechts oben
				g.put(12 + i, 13 - i, "O")
			g.fill_rect(11, 12, 3, 3, "K")
		"code":
			g = Grid.new(26, 19)
			g.fill_rect(1, 0, 24, 19, "W")
			g.box(1, 0, 24, 19, "K")
			g.blit(4, 4, ["..KK", ".K", "K", ".K", "..KK"])
			g.blit(18, 4, ["KK", "..K", "...K", "..K", "KK"])
			g.blit(9, 13, ["OOOOOOOO"])
		"eye":
			g = Grid.new(28, 15)
			for yy in 11:
				var half := 11 - absi(yy - 5) * 2
				for xx in range(14 - half, 14 + half):
					g.put(xx, 2 + yy, "W")
				g.put(13 - half, 2 + yy, "K")
				g.put(14 + half, 2 + yy, "K")
			g.fill_rect(11, 4, 6, 7, "O")
			g.fill_rect(13, 6, 3, 3, "K")
		_:
			g = Grid.new(28, 18)
			_window(g, 0, 0, 28, 16, "W")
	return g.rows()
