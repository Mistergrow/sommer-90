extends RefCounted
## Brillen, Schmuck und Kopfbedeckungen fuer die gemeinsame 32x48-Figur.
const Raster := preload("res://scripts/gfx/pixel_raster_32.gd")
const AvatarPalette := preload("res://scripts/gfx/avatar_palette_32.gd")
const OUTLINE := Color8(28, 24, 31)
const EYE_WHITE := Color8(205, 194, 176)
const METAL := Color8(224, 179, 65)

# --------------------------------------------------------------- Accessories

static func draw(img: Image, sel: Dictionary, cloth: Array[Color],
		anatomy: Dictionary, face_span: Callable) -> void:
	var cx := int(anatomy["head_x"])
	var turn := int(anatomy["turn"])
	var glasses := str(sel.get("glasses", ""))
	if glasses != "" and glasses != "none":
		var far_x := cx - turn * 2
		var near_x := cx + turn * 3
		var eye_y := 8 + int(str(sel.get("eye_type", "normal")) == "droopy")
		# In der 10px-Kopfbreite darf eine Sehbrille nie zur schwarzen Maske
		# werden. Ein warmer 1px-Rahmen markiert Form, Augen bleiben frei.
		var frame := Color8(78, 61, 61)
		var frame_hi := Color8(137, 104, 91)
		for ex in [far_x, near_x]:
			match glasses:
				"half":
					Raster.line(img, ex - 1, ex + 1, 9, frame)
				"square":
					Raster.line(img, ex - 1, ex + 1, 7, frame_hi); Raster.line(img, ex - 1, ex + 1, 9, frame)
					Raster.px(img, ex - 1, 8, frame); Raster.px(img, ex + 1, 8, frame)
				"thick":
					Raster.line(img, ex - 1, ex + 1, 7, frame); Raster.line(img, ex - 1, ex + 1, 9, frame)
					if glasses == "thick":
						Raster.px(img, ex - 1, 8, frame); Raster.px(img, ex + 1, 8, frame)
				"cat":
					Raster.px(img, ex - 1, 7, frame_hi); Raster.px(img, ex + 1, 6, frame)
					Raster.line(img, ex - 1, ex + 1, 9, frame)
				"aviator":
					Raster.line(img, ex - 1, ex + 1, 7, frame_hi); Raster.px(img, ex - 1, 8, frame); Raster.px(img, ex + 1, 8, frame)
					Raster.line(img, ex, ex + 1, 9, frame)
				"sunglasses":
					Raster.px(img, ex, 7, Color8(52, 57, 66)); Raster.px(img, ex, 8, Color8(52, 57, 66))
					Raster.px(img, ex - 1, 7, frame); Raster.px(img, ex + 1, 7, frame); Raster.line(img, ex - 1, ex + 1, 9, frame)
				_:
					Raster.px(img, ex, 7, frame_hi); Raster.px(img, ex - 1, 8, frame); Raster.px(img, ex + 1, 8, frame); Raster.px(img, ex, 9, frame)
		# Steg zwischen den Gläsern + Bügel zum sichtbaren Ohr.
		Raster.line(img, mini(far_x, near_x) + 1, maxi(far_x, near_x) - 1, 8, frame)
		var span9: Vector2i = face_span.call(9, sel, anatomy)
		var temple_x := (span9.x) if turn > 0 else (span9.y)
		Raster.px(img, temple_x, 8, frame)
		# Expression back on top: frames may surround but never replace eyes.
		var iris := AvatarPalette.figure_iris(str(sel.get("eye_color", "brown")))
		Raster.px(img, far_x - turn, eye_y, EYE_WHITE); Raster.px(img, far_x, eye_y, iris)
		Raster.px(img, near_x - turn, eye_y, EYE_WHITE); Raster.px(img, near_x, eye_y, iris)
	var earring := str(sel.get("earring", ""))
	if earring != "":
		var span: Vector2i = face_span.call(10, sel, anatomy)
		var ear_x := span.x - 1 if turn > 0 else span.y + 1   # am SICHTBAREN Ohr
		var metal := Color8(196, 203, 210) if "silver" in earring else METAL
		Raster.px(img, ear_x, 11, metal)
		if "hoop" in earring:
			Raster.px(img, ear_x + (-1 if turn > 0 else 1), 12, metal)
			Raster.px(img, ear_x, 12, metal)
		elif "drop" in earring:
			Raster.px(img, ear_x, 12, metal); Raster.px(img, ear_x, 13, metal)
	if str(sel.get("necklace", "")) != "":
		# Kette als Bogen am Kragen + Anhänger statt eines Einzelpixels.
		var bx := int(anatomy["body_x"])
		Raster.px(img, bx - 2, 18, METAL); Raster.px(img, bx - 1, 19, METAL)
		Raster.px(img, bx + 1, 19, METAL); Raster.px(img, bx + 2, 18, METAL)
		Raster.px(img, bx, 20, METAL)
	var hat := str(sel.get("hat", ""))
	if hat != "" and hat != "none":
		_draw_hat(img, cx, turn, hat, cloth)


static func _draw_hat(img: Image, cx: int, turn: int, hat: String, cloth: Array[Color]) -> void:
	match hat:
		"cap", "cap_back":
			Raster.line(img, cx - 7, cx + 7, 1, cloth[3]); Raster.line(img, cx - 8, cx + 8, 2, cloth[2])
			Raster.line(img, cx - 8, cx + 8, 3, cloth[1])
			# Der Schirm folgt der BLICKRICHTUNG (3/4-Kopf), Rückwärts-Cap andersrum.
			var bill := turn if hat == "cap" else -turn
			Raster.line(img, cx + bill * 3, cx + bill * 9, 4, cloth[0])
			Raster.line(img, cx + bill * 4, cx + bill * 8, 3, cloth[1])
		"flatcap":
			Raster.line(img, cx - 7, cx + 7, 2, cloth[2]); Raster.line(img, cx - 6, cx + 6, 1, cloth[3])
			Raster.line(img, cx - 8, cx + 8, 3, cloth[1])
			Raster.line(img, cx + turn * 4, cx + turn * 7, 4, cloth[0])   # kurzer Schirm
		"visor":
			Raster.line(img, cx - 6, cx + 6, 4, cloth[2])                  # nur Band …
			Raster.line(img, cx + turn * 3, cx + turn * 8, 5, cloth[0])    # … plus Schirm
		"bucket":
			Raster.line(img, cx - 6, cx + 6, 0, cloth[2]); Raster.line(img, cx - 7, cx + 7, 1, cloth[2])
			Raster.line(img, cx - 7, cx + 7, 2, cloth[1])
			Raster.line(img, cx - 9, cx + 9, 3, cloth[0])                  # Krempe rundum
		"sunhat":
			Raster.line(img, cx - 5, cx + 5, 0, cloth[3]); Raster.line(img, cx - 7, cx + 7, 1, cloth[2])
			Raster.line(img, cx - 8, cx + 8, 2, cloth[1]); Raster.line(img, cx - 11, cx + 11, 3, cloth[0])
		"tophat":
			Raster.rect(img, cx - 5, 0, 11, 4, cloth[2]); Raster.line(img, cx - 4, cx + 4, 0, cloth[4])
			Raster.line(img, cx - 7, cx + 7, 4, cloth[0])
		"fedora":
			Raster.line(img, cx - 4, cx + 4, 0, cloth[3]); Raster.line(img, cx - 6, cx + 6, 1, cloth[2])
			Raster.line(img, cx - 7, cx + 7, 2, cloth[1]); Raster.line(img, cx - 9, cx + 9, 3, cloth[0])
			Raster.px(img, cx - turn * 3, 0, cloth[0])
		"cowboy":
			Raster.line(img, cx - 4, cx + 4, 0, cloth[3]); Raster.line(img, cx - 6, cx + 6, 1, cloth[2])
			Raster.line(img, cx - 7, cx + 7, 2, cloth[1]); Raster.line(img, cx - 10, cx + 10, 4, cloth[0])
			Raster.px(img, cx - 11, 3, cloth[3]); Raster.px(img, cx + 11, 3, cloth[3])
		"beanie", "winter":
			Raster.line(img, cx - 6, cx + 6, 0, cloth[3]); Raster.line(img, cx - 7, cx + 7, 1, cloth[3])
			Raster.line(img, cx - 8, cx + 8, 2, cloth[2]); Raster.line(img, cx - 8, cx + 8, 3, cloth[2])
			Raster.line(img, cx - 8, cx + 8, 4, cloth[0])
			if hat == "winter": Raster.rect(img, cx - 1, -1, 3, 2, cloth[4])
		"headband", "bandana":
			# EIN Band über der Stirn (nicht der frühere zweifarbige Streifen-
			# stapel oben auf dem Kopf) + Knoten an der Blickrichtungs-Seite.
			Raster.line(img, cx - 6, cx + 6, 5, cloth[2])
			Raster.px(img, cx - 6, 5, cloth[1]); Raster.px(img, cx + 6, 5, cloth[1])
			if hat == "bandana":
				Raster.px(img, cx - turn * 7, 6, cloth[1]); Raster.px(img, cx - turn * 7, 7, cloth[0])
		"headphones":
			Raster.line(img, cx - 6, cx + 6, 1, OUTLINE); Raster.rect(img, cx - 8, 6, 2, 5, cloth[2]); Raster.rect(img, cx + 7, 6, 2, 5, cloth[1])
		"party":
			Raster.px(img, cx, 0, cloth[4]); Raster.line(img, cx - 1, cx + 1, 1, cloth[3])
			Raster.line(img, cx - 2, cx + 2, 2, cloth[2]); Raster.line(img, cx - 3, cx + 3, 3, cloth[1])
			Raster.line(img, cx - 5, cx + 5, 4, cloth[0])
		"crown":
			Raster.line(img, cx - 7, cx + 7, 4, METAL); Raster.line(img, cx - 6, cx + 6, 3, METAL)
			for ox in [-6, -3, 0, 3, 6]:
				Raster.vline(img, cx + ox, 1 + floori(absi(ox) / 3.0), 3, METAL)
				Raster.px(img, cx + ox, 1 + floori(absi(ox) / 3.0), Color8(255, 220, 96))
		"santa":
			Raster.line(img, cx - 4, cx + 4, 0, Color8(211, 65, 72)); Raster.line(img, cx - 6, cx + 6, 1, Color8(190, 49, 58))
			Raster.line(img, cx - 8, cx + 8, 3, Color8(232, 224, 211)); Raster.line(img, cx - 7, cx + 7, 4, Color8(201, 194, 184))
			Raster.px(img, cx - 6, 0, Color8(240, 232, 220)); Raster.px(img, cx - 7, 1, Color8(218, 210, 201))
		"helmet":
			Raster.line(img, cx - 4, cx + 4, 0, cloth[3]); Raster.line(img, cx - 7, cx + 7, 1, cloth[2])
			Raster.line(img, cx - 8, cx + 8, 2, cloth[1]); Raster.line(img, cx - 8, cx + 8, 3, cloth[1])
			Raster.vline(img, cx - turn * 8, 4, 10, cloth[0]); Raster.px(img, cx - turn * 7, 11, cloth[0])
		_:
			# Unknown future hats degrade to a small era-neutral cap instead of a
			# giant geometric placeholder.
			Raster.line(img, cx - 6, cx + 6, 2, cloth[2]); Raster.line(img, cx - 5, cx + 5, 1, cloth[3])
