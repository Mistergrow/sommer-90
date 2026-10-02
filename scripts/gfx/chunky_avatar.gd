class_name ChunkyAvatar
## LEGACY-Kompatibilität des früheren 32²-Prototyps. Produktionsporträts laufen
## ausschließlich über PortraitGen/PortraitPaint32, Ganzkörper über
## FigurePaint32 (32×48). Die Primitive bleiben vorerst für ChunkyVehicles und
## alte Proofs verfügbar; neue UI darf face()/portrait()/figure() nicht verwenden.

const OUTLINE := Color(0.10, 0.08, 0.11)
const PALETTE32 := preload("res://scripts/gfx/avatar_palette_32.gd")

const SKINS := ["beige", "sand", "tan", "pale", "brown"]
const HAIRS := ["brown", "black", "blond", "ginger", "auburn", "grey"]
const SHORTS := [Color(0.30, 0.24, 0.52), Color(0.22, 0.30, 0.48), Color(0.30, 0.30, 0.33),
	Color(0.45, 0.40, 0.26), Color(0.16, 0.15, 0.18)]
const CHIBI_EYE := Color(0.17, 0.13, 0.16)   # dunkles Auge (Pixel-Stil)
const RIBBON := Color(0.86, 0.28, 0.32)      # Haarschleife (Mädchen)
# Porträt-Emotion (Dialog-Zustand) → Chunky-Ausdruck.
const EMOTION_ACT := {
	"happy": "grin", "proud": "grin", "surprised": "surprised",
	"tired": "yawn", "nervous": "wink",
}
# Frisuren-Rezepte (fringe/side in „Kopf-Px" bei 21er-Höhe; skaliert für die Figur).
const HAIR_CHUNK := {
	"bald": {},
	"buzzcut": {"fringe": 3, "flat": true},
	"short": {"fringe": 6},
	"flattop": {"fringe": 5, "flat": true},
	"parted": {"fringe": 6, "side": 2, "part": true},
	"quiff": {"fringe": 4, "quiff": true},
	"messy": {"fringe": 6, "side": 2, "spiky": 1},
	"spiky": {"fringe": 4, "spiky": 2},
	"mohawk": {"mohawk": true},
	"curly": {"fringe": 6, "side": 3, "curl": true},
	"afro": {"afro": true},
	"straight": {"fringe": 7, "side": 6},
	"medium": {"fringe": 6, "side": 9},
	"bob": {"fringe": 6, "side": 12, "wide": true},
	"long": {"fringe": 6, "side": 24},
	"ponytail": {"fringe": 6, "side": 2, "tail": true},
	"pigtails": {"fringe": 6, "side": 3, "pigtails": true},
	"bun": {"fringe": 5, "side": 2, "bun": true},
	"mullet": {"fringe": 6, "side": 3, "mullet": true},
}
# Brillen-, Hut- und Bart-Sorten stehen als einzige Quelle in AvatarCatalog
# (GLASSES/HATS/BEARDS) — hier lagen bis zuletzt abgedriftete Kopien.
const HAT_COLORS := [Color(0.66, 0.20, 0.20), Color(0.20, 0.34, 0.60), Color(0.22, 0.42, 0.30),
	Color(0.80, 0.52, 0.18), Color(0.30, 0.28, 0.34), Color(0.86, 0.82, 0.30), Color(0.16, 0.16, 0.20)]


## Chunky-Kompatibilitäts-DNA aus derselben Identität wie der 128er-Generator,
## damit chunky Avatar/Figur exakt zum Detail-Porträt passen (gleicher Hautton,
## Haar-, Shirt-Farbe, Brille). Shorts/Frisur-Chunk deterministisch aus der id.
static func dna(id: String, hints: Dictionary = {}) -> Dictionary:
	var sel: Dictionary = PortraitGen.selection_for(id, hints)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var style := 0
	match str(sel.get("hair_style", "short")):
		"messy", "curly": style = 1
		"parted", "side", "long", "medium": style = 2
	var g := str(sel.get("glasses", ""))
	var e := str(sel.get("earring", ""))
	var female: bool = str(sel.get("gender", "m")) == "f"
	var shorts_c: Color = SHORTS[rng.randi() % SHORTS.size()]
	var grin: bool = str(sel.get("mouth", "")) in ["smile", "laugh"] or rng.randf() < 0.55
	var ribbon: bool = female and rng.randf() < 0.7   # dezente Haarschleife
	var freckles: bool = rng.randf() < 0.22
	var hat_col: Color = HAT_COLORS[rng.randi() % HAT_COLORS.size()]
	var ekind := e.split("_")[0] if e != "" else ""   # stud | hoop | drop
	var tops := ["plain", "plain", "stripes", "hoodie", "jacket", "tanktop", "polo", "vneck", "overall", "logo"]
	var top_style := str(hints.get("top", ""))
	if top_style == "":
		top_style = tops[rng.randi() % tops.size()]
	return {
		"skin": PALETTE32.portrait_skin(str(sel.get("skin", "beige")))[2],
		"hair": PALETTE32.portrait_hair(sel)[2],
		"shirt": PALETTE32.portrait_cloth(str(sel.get("shirt_color", "teal")))[2],
		"shorts": shorts_c,
		"glasses": g,               # "" | round | square | thick | sunglasses
		"earring": e != "",
		"earring_gold": e.ends_with("gold"),
		"necklace": str(sel.get("necklace", "")) != "",
		"gender": "f" if female else "m",
		"hairstyle": 2 if (female and style == 0) else style,  # (Alt) grobe Frisur-Klasse
		"hair_style": str(sel.get("hair_style", "short")),     # exakte Frisur (viele Varianten)
		"grin": grin,
		"ribbon": ribbon,
		"top": top_style,                                    # Kleidungs-Stil (Oberteil)
		"face_shape": str(sel.get("head", "oval")),          # Gesichtsform
		"ears": str(sel.get("ears", "plain")),               # plain | big
		"eye_type": str(sel.get("eye_type", "round")),       # round | narrow | wide
		"eye_col": PALETTE32.portrait_iris(str(sel.get("eye_color", "brown"))),
		"hat": str(sel.get("hat", "")),                      # Kopfbedeckung
		"hat_col": hat_col,
		"beard": str(sel.get("beard", "")),                  # Gesichtsbehaarung
		"brow": str(sel.get("eyebrows", "flat")),            # flat | thick | raised
		"earring_kind": ekind,                               # stud | hoop | drop
		"freckles": freckles,
		"age_now": int(sel.get("age_now", 20)),              # Alterung (Falten, Ecken)
		"recede": bool(sel.get("recede", false)),            # Geheimratsecken ab 45
	}


# ------------------------------------------------------------- Zeichen-Helfer
static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


## Dicke Kontur (1px) rund um alles Opake — der Comic-Look.
static func _outline(img: Image) -> void:
	var src := img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.4:
				continue
			for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + dv.x
				var ny := y + dv.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h and src.get_pixel(nx, ny).a > 0.4:
					img.set_pixel(x, y, OUTLINE)
					break


# ------------------------------------------------------ Frisuren & Brillen
## Halbe Kopfbreite in Zeile y (Ellipse); unterhalb des Kopfes = volle Breite.
static func _hw_at(y: int, hcy: float, hry: float, hh: int, flat: float, hbot: int) -> int:
	if y > hbot:
		return hh
	var ny := (float(y) - hcy) / hry
	return int(round(hh * sqrt(maxf(1.0 - ny * ny * flat, 0.0))))


## Zeichnet eine Frisur — für Kopf-Avatar UND Figur (skaliert über die Kopfhöhe).
## recede = hohe Stirn + Geheimratsecken (Alterung, wie im 128er-Porträt).
static func _hair(img: Image, cx: int, htop: int, hbot: int, hh: int, hcy: float, hry: float, flat: float, hair: Color, hair_hi: Color, style: String, ribbon: bool, recede: bool = false) -> void:
	if style == "bald":
		return
	var p: Dictionary = HAIR_CHUNK.get(style, HAIR_CHUNK["short"])
	var sc := float(hbot - htop) / 21.0
	var hsh := hair.darkened(0.16)
	if p.get("mohawk", false):
		for y in range(htop - int(round(4.0 * sc)) - 1, htop + int(round(7.0 * sc))):
			_rect(img, cx - 1, y, 3, 1, hair if (y - htop) % 2 == 0 else hsh)
		return
	if p.get("afro", false):
		var r := hh + 2
		for y in range(htop - int(round(4.0 * sc)), htop + int(round(9.0 * sc))):
			var dy := float(y - (htop + int(round(2.0 * sc)))) / float(r)
			var half := int(round(r * sqrt(maxf(1.0 - dy * dy, 0.0))))
			for x in range(cx - half, cx + half + 1):
				_px(img, x, y, hair_hi if (x < cx - 2 and dy < 0.0) else (hair if (x + y) % 3 != 0 else hsh))
		return
	# Kappe (folgt der Ellipse)
	var fringe := htop + maxi(1, int(round(float(p.get("fringe", 6)) * sc)))
	if recede:
		fringe = htop + maxi(1, int(round(2.0 * sc)))    # hohe Stirn im Alter
	var top := htop - (2 if int(p.get("spiky", 0)) > 0 else 1)
	for y in range(top, fringe + 1):
		# Die Kappe folgt der Kopf-Ellipse EXAKT (gleiche Formel wie der Schädel),
		# damit oben keine Kopfhaut durchscheint. Nur die Zeile ÜBER dem Kopf
		# (y < htop) darf schmaler sein — dort ist ohnehin keine Haut.
		var half := _hw_at(y, hcy, hry, hh, flat, hbot)
		if y < htop: half = maxi(half, 3)
		if p.get("flat", false) and y < htop: half = maxi(half - 1, 3)
		for x in range(cx - half, cx + half + 1):
			if p.get("part", false) and y >= fringe - 1 and x == cx:
				continue
			if recede and absi(x - cx) < hh - 3:
				continue                                  # Halbglatze: nur Seitenhaar
			_px(img, x, y, hair_hi if (x < cx - 3 and y < htop + 2) else hair)
	var sp := int(p.get("spiky", 0))
	if sp > 0:
		for sx in range(-hh + 1, hh, 3):
			_px(img, cx + sx, top - 1, hair)
			if sp > 1: _px(img, cx + sx, top - 2, hair)
	if p.get("quiff", false):
		_rect(img, cx - 3, top - 1, 6, 1, hair); _rect(img, cx - 2, top - 2, 4, 1, hair_hi)
	# Seiten-Strähnen an den Kopfkanten hinunter
	var side := htop + int(round(float(p.get("side", 0)) * sc))
	var wide: bool = p.get("wide", false) or (side - fringe) > int(round(6.0 * sc))
	for y in range(fringe, side + 1):
		var half := _hw_at(y, hcy, hry, hh, flat, hbot)
		_px(img, cx - half, y, hair); _px(img, cx + half, y, hsh)
		if wide:
			_px(img, cx - half + 1, y, hair); _px(img, cx + half - 1, y, hsh)
		if p.get("curl", false) and y % 2 == 0:
			_px(img, cx - half - 1, y, hair); _px(img, cx + half + 1, y, hsh)
	# Zöpfe / Dutt / Vokuhila
	if p.get("tail", false):
		_rect(img, cx + hh + 1, htop + int(round(3.0 * sc)), 2, int(round(9.0 * sc)), hair)
	if p.get("pigtails", false):
		for sgn in [-1, 1]:
			_rect(img, cx + sgn * (hh + 1) - (1 if sgn < 0 else 0), htop + int(round(5.0 * sc)), 2, int(round(7.0 * sc)), hair)
	if p.get("bun", false):
		_rect(img, cx - 2, top - int(round(3.0 * sc)), 5, maxi(2, int(round(4.0 * sc))), hair)
	if p.get("mullet", false):
		for y in range(hbot - int(round(2.0 * sc)), hbot + int(round(4.0 * sc))):
			_rect(img, cx - hh + 1, y, 3, 1, hair); _rect(img, cx + hh - 3, y, 3, 1, hsh)
	if ribbon and side > fringe:
		_rect(img, cx + hh - 1, fringe, 2, 2, RIBBON)


## Zeichnet eine Brille um zwei Augen (lx/rx = Augenmitte, cy = Höhe, r = Radius).
static func _glasses(img: Image, lx: int, rx: int, cy: int, r: int, kind: String) -> void:
	if kind == "" or kind == "none":
		return
	var fr := OUTLINE
	var shade := kind == "sunglasses"
	for xc in [lx, rx]:
		match kind:
			"square", "thick":
				var t := 1 if kind == "thick" else 0
				var rr := r + t
				_rect(img, xc - rr, cy - rr, 2 * rr + 1, 1, fr)
				_rect(img, xc - rr, cy + rr, 2 * rr + 1, 1, fr)
				_rect(img, xc - rr, cy - rr, 1, 2 * rr + 1, fr)
				_rect(img, xc + rr, cy - rr, 1, 2 * rr + 1, fr)
			"cat":
				for dx in range(-r, r + 1):
					_px(img, xc + dx, cy + r, fr)
				_px(img, xc - r, cy, fr); _px(img, xc + r, cy, fr)
				_px(img, xc - r - 1, cy - r, fr)
				_rect(img, xc - r, cy - r, r + 1, 1, fr)
			"half":
				for dx in range(-r, r + 1):
					_px(img, xc + dx, cy + r, fr)
				_px(img, xc - r, cy, fr); _px(img, xc + r, cy, fr)
			"aviator":
				for dx in range(-r, r + 1):
					_px(img, xc + dx, cy - r, fr)
				_px(img, xc - r, cy, fr); _px(img, xc + r, cy, fr)
				_rect(img, xc - r + 1, cy + r, 2 * r - 1, 1, fr)
			_:  # round
				for dx in range(-r, r + 1):
					_px(img, xc + dx, cy - r, fr); _px(img, xc + dx, cy + r, fr)
				for dy in range(-r + 1, r):
					_px(img, xc - r, cy + dy, fr); _px(img, xc + r, cy + dy, fr)
		if shade:
			_rect(img, xc - r + 1, cy - r + 1, 2 * r - 1, 2 * r - 1, Color(0.24, 0.26, 0.30))
			_px(img, xc - r + 1, cy - r + 1, Color(0.55, 0.60, 0.66))
	# Steg zwischen den Gläsern
	_rect(img, mini(lx, rx) + r, cy, maxi(lx, rx) - mini(lx, rx) - 2 * r + 1, 1, fr)


## Kopfbedeckung über dem Haar (Kopf UND Figur). col = Hutfarbe.
static func _hat(img: Image, cx: int, htop: int, hbot: int, hh: int, hcy: float, hry: float, flat: float, kind: String, col: Color) -> void:
	if kind == "" or kind == "none":
		return
	var dark := col.darkened(0.22)
	var hi := col.lightened(0.12)
	match kind:
		"cap", "cap_back":
			for y in range(htop - 2, htop + 4):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				if y < htop: half = maxi(half - 2, 3)
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, hi if (x < cx - 2 and y < htop + 1) else col)
			if kind == "cap":
				_rect(img, cx - hh - 2, htop + 4, hh + 3, 1, dark)          # Schild vorne
				_rect(img, cx - hh - 2, htop + 5, hh, 1, col.darkened(0.34))
			else:
				_rect(img, cx + hh - 1, htop + 2, 2, 1, dark)               # Schnalle hinten
		"beanie", "winter":
			for y in range(htop - 2, htop + 6):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				if y < htop: half = maxi(half - 1, 3)
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, hi if (x < cx - 2 and y < htop + 1) else col)
			var hwb := _hw_at(htop + 5, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hwb, htop + 5, 2 * hwb + 1, 1, dark)            # Umschlag-Bund
			if kind == "winter":
				_rect(img, cx - 1, htop - 4, 3, 3, hi)                     # Bommel
		"headband":
			var hwb := _hw_at(htop + 4, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hwb, htop + 4, 2 * hwb + 1, 2, col)
			_rect(img, cx - hwb, htop + 4, 2 * hwb + 1, 1, hi)
		"bandana":
			for y in range(htop - 1, htop + 5):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, col if (x + y) % 2 == 0 else dark)
			_rect(img, cx + hh - 1, htop + 3, 2, 2, col)                    # Knoten
		"bucket", "sunhat":
			var straw := Color(0.82, 0.68, 0.40) if kind == "sunhat" else col
			var brim := 2 if kind == "bucket" else 4
			for y in range(htop, htop + 3):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, straw)
			var hwb := _hw_at(htop + 3, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hwb - brim, htop + 3, 2 * (hwb + brim) + 1, 1, straw.darkened(0.10))
			_rect(img, cx - hwb - brim + 1, htop + 4, 2 * (hwb + brim) - 1, 1, straw.darkened(0.28))
		"tophat":
			var hw3 := _hw_at(htop + 2, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hw3 - 2, htop + 2, 2 * hw3 + 5, 1, dark)          # Krempe
			_rect(img, cx - hw3 + 1, htop - 6, 2 * hw3 - 1, 8, col)           # Zylinder
			_rect(img, cx - hw3 + 1, htop - 2, 2 * hw3 - 1, 1, Color(0.7, 0.2, 0.2))  # Band
		"fedora":
			for y in range(htop - 1, htop + 3):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, hi if x < cx - 2 else col)
			var hwf := _hw_at(htop + 3, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hwf - 2, htop + 3, 2 * hwf + 5, 1, dark)          # Krempe
			_rect(img, cx - hwf + 1, htop + 2, 2 * hwf - 1, 1, col.darkened(0.4))  # Band
			_rect(img, cx - 2, htop - 1, 4, 1, dark)                         # Delle
		"cowboy":
			for y in range(htop - 2, htop + 3):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot) - (2 if y < htop else 0)
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, col)
			var hwc := _hw_at(htop + 3, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hwc - 3, htop + 2, 2 * hwc + 7, 2, col.darkened(0.12))  # geschwungene Krempe
		"flatcap":
			for y in range(htop - 1, htop + 3):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, hi if x < cx - 2 else col)
			_rect(img, cx - hh - 3, htop + 3, hh + 3, 1, dark)               # kleiner Schirm
		"visor":
			var hwv := _hw_at(htop + 4, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hwv, htop + 3, 2 * hwv + 1, 1, col)              # Band
			_rect(img, cx - hwv - 3, htop + 4, hwv + 4, 1, col.darkened(0.15))  # Schirm
		"party":
			for i in 7:
				var w := 7 - i
				_rect(img, cx - floori(w / 2.0), htop - i, w + 1, 1, HAT_COLORS[i % HAT_COLORS.size()])
			_rect(img, cx - 1, htop - 7, 3, 1, Color(0.95, 0.9, 0.4))        # Bommel
		"crown":
			var g := Color(0.95, 0.82, 0.30)
			_rect(img, cx - 5, htop, 11, 2, g)
			for sx in [-5, -2, 1, 4]:
				_rect(img, cx + sx, htop - 2, 2, 2, g)
			_px(img, cx - 2, htop, Color(0.9, 0.2, 0.3)); _px(img, cx + 2, htop, Color(0.3, 0.4, 0.9))  # Juwelen
		"santa":
			for i in 6:
				var w := 6 - i
				_rect(img, cx - floori(w / 2.0) - floori(i / 3.0), htop - i, w + 1, 1, Color(0.75, 0.18, 0.18))
			var hws := _hw_at(htop + 1, hcy, hry, hh, flat, hbot)
			_rect(img, cx - hws, htop + 1, 2 * hws + 1, 1, Color(0.95, 0.95, 0.96))  # Fell-Rand
			_rect(img, cx + 2, htop - 6, 3, 2, Color(0.95, 0.95, 0.96))      # Bommel
		"helmet":
			for y in range(htop - 2, htop + 5):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot) + 1
				for x in range(cx - half, cx + half + 1):
					_px(img, x, y, hi if (x < cx - 2 and y < htop + 1) else col)
			_rect(img, cx - 1, htop - 2, 2, 6, col.lightened(0.2))          # Grat
		"headphones":
			var hwh := _hw_at(htop + 4, hcy, hry, hh, flat, hbot)
			for y in range(htop - 2, htop + 1):                              # Bügel oben
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				_px(img, cx - half - 1, y, dark); _px(img, cx + half + 1, y, dark)
			_rect(img, cx - hh, htop - 3, 2 * hh + 1, 1, dark)
			_rect(img, cx - hwh - 2, htop + 3, 2, 3, col)                    # Ohrmuscheln
			_rect(img, cx + hwh + 1, htop + 3, 2, 3, col)


## Gesichtsbehaarung im unteren Gesicht (vor dem Mund gezeichnet). col = Haarfarbe.
static func _beard(img: Image, cx: int, hbot: int, hh: int, hcy: float, hry: float, flat: float, ey: int, my: int, kind: String, col: Color) -> void:
	if kind == "" or kind == "none":
		return
	var sh := col.darkened(0.12)
	match kind:
		"stubble":
			for y in range(my - 1, hbot + 1):
				var half := maxi(0, _hw_at(y, hcy, hry, hh, flat, hbot) - 1)
				for x in range(cx - half, cx + half + 1):
					if (x * 5 + y * 3) % 3 == 0:
						_px(img, x, y, sh)
		"mustache":
			_rect(img, cx - 3, my - 1, 7, 1, col)
		"goatee":
			_rect(img, cx - 3, my - 1, 7, 1, col)
			_rect(img, cx - 1, my + 1, 3, 2, col)
		"chin":
			_rect(img, cx - 1, my + 1, 3, 2, col)
		"full":
			for y in range(my - 1, hbot + 1):
				if y <= my:
					_rect(img, cx - 3, y, 7, 1, col)          # Schnauzer
				else:
					var half := _hw_at(y, hcy, hry, hh, flat, hbot)
					for x in range(cx - half, cx + half + 1):
						_px(img, x, y, col if x < cx else sh)
		"sideburns":
			for y in range(ey, my + 1):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				_px(img, cx - half, y, col); _px(img, cx + half, y, sh)
		"soulpatch":
			_rect(img, cx - 1, my + 1, 2, 1, col)
		"handlebar":
			_rect(img, cx - 3, my - 1, 7, 1, col)
			_px(img, cx - 4, my - 2, col); _px(img, cx + 4, my - 2, col)     # gezwirbelte Enden
		"muttonchops":
			for y in range(ey, my + 2):
				var half := _hw_at(y, hcy, hry, hh, flat, hbot)
				_px(img, cx - half, y, col); _px(img, cx - half + 1, y, col)
				_px(img, cx + half, y, sh); _px(img, cx + half - 1, y, sh)
		"longbeard":
			for y in range(my - 1, hbot + 3):
				if y <= my:
					_rect(img, cx - 3, y, 7, 1, col)
				else:
					var half := _hw_at(y, hcy, hry, hh, flat, hbot)
					if y > hbot: half = maxi(2, half - (y - hbot))       # spitz zulaufend
					for x in range(cx - half, cx + half + 1):
						_px(img, x, y, col if x < cx else sh)


## Kleidungs-Stil aufs Oberteil legen (Figur; schlanker Torso bei `top`, 9 breit).
static func _top(img: Image, cx: int, top: int, _cloth: Color, cloth_hi: Color, cloth_sh: Color, skin: Color, pants: Color, style: String) -> void:
	match style:
		"stripes":
			for yy in range(top + 1, top + 10, 2):
				_rect(img, cx - 4, yy, 9, 1, cloth_sh)
		"hoodie":
			_rect(img, cx - 4, top, 9, 2, cloth_sh)                     # Kapuzenkragen
			_px(img, cx - 1, top + 2, cloth_hi); _px(img, cx + 1, top + 2, cloth_hi)  # Kordeln
			_rect(img, cx - 2, top + 6, 5, 3, cloth_sh)                 # Bauchtasche
		"jacket":
			_rect(img, cx - 2, top, 5, 10, cloth_hi)                    # inneres Shirt (heller)
			_rect(img, cx, top, 1, 10, cloth_sh)                        # Reißverschluss
			_px(img, cx - 3, top, cloth_sh); _px(img, cx + 3, top, cloth_sh)  # Revers
		"tanktop":
			_rect(img, cx - 4, top, 2, 3, skin); _rect(img, cx + 3, top, 2, 3, skin)  # Schultern frei
		"polo":
			_rect(img, cx - 3, top, 3, 1, cloth_hi); _rect(img, cx + 1, top, 3, 1, cloth_hi)  # Kragen
			_px(img, cx, top + 1, cloth_sh); _px(img, cx, top + 3, cloth_sh)  # Knöpfe
		"vneck":
			_px(img, cx, top, skin); _rect(img, cx - 1, top + 1, 3, 1, skin); _px(img, cx, top + 2, skin)  # V-Ausschnitt
		"overall":
			_rect(img, cx - 4, top, 2, 10, pants); _rect(img, cx + 3, top, 2, 10, pants)  # Latzträger
			_rect(img, cx - 2, top + 4, 5, 6, pants)                    # Latz
			_px(img, cx - 3, top + 1, Color(0.9, 0.8, 0.3)); _px(img, cx + 4, top + 1, Color(0.9, 0.8, 0.3))  # Schnallen
		"logo":
			_rect(img, cx - 1, top + 3, 4, 3, cloth_hi)                 # Logo-Feld
			_px(img, cx, top + 4, cloth_sh)


# --------------------------------------------------------- Öffentliche API
## Kopf-Avatar (Bust) im GLEICHEN klaren Pixel-Stil wie die Figur: großer, sauber
## gerundeter Kopf mit Licht/Schatten, simple Augen, Haar, Brille, Schultern in
## Kleidungsfarbe. Ausdruck via blink/gaze/act (blinzeln/umsehen/gähnen/…).
static func face(id: String, px: int = 32, hints: Dictionary = {}, blink: bool = false, gaze: int = 0, act: String = "") -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var d := dna(id, hints)
	var cx := floori(px / 2.0)
	var skin: Color = d["skin"]
	var skin_hi := skin.lightened(0.10)
	var hair: Color = d["hair"]
	var hair_hi := hair.lightened(0.16)
	var cloth: Color = d["shirt"]
	var cloth_sh := cloth.darkened(0.20)
	var female: bool = str(d.get("gender", "m")) == "f"
	var fshape := str(d.get("face_shape", "oval"))
	var skin_sh := skin.darkened(0.15)
	var brow_col := hair.darkened(0.20)
	var htop := 3
	var hh := 11          # halbe Kopfbreite
	var hgt := 21         # Kopfhöhe
	match fshape:
		"round": hh = 12; hgt = 19
		"long": hh = 10; hgt = 23
		"heart": hh = 11; hgt = 20
		"square": hh = 12; hgt = 21
	var hbot := htop + hgt
	var hcy := float(htop + hbot) * 0.5
	var hry := float(hbot - htop) * 0.5
	var flat := 0.58 if fshape == "square" else 0.80   # square = flachere Wangen
	# ---- Kopf (elliptisch, Licht links / Schatten rechts) ----
	for y in range(htop, hbot + 1):
		var ny := (float(y) - hcy) / hry
		var half := int(round(hh * sqrt(maxf(1.0 - ny * ny * flat, 0.0))))
		if half < 2:
			continue
		for x in range(cx - half, cx + half + 1):
			var c := skin
			if x >= cx + half - 1: c = skin_sh
			elif x <= cx - half + 1 and float(y) < hbot - hry * 0.4: c = skin_hi
			_px(img, x, y, c)
	# Augen tiefer setzen (57 % der Kopfhöhe) → Gesicht sitzt richtig, nicht zu hoch
	var ey := htop + int(round(hgt * 0.55))
	var face_hw := int(round(hh * sqrt(maxf(1.0 - pow((float(ey) - hcy) / hry, 2) * flat, 0.0))))
	# ---- Ohren (seitlich, auf Augenhöhe) — bei langem Mädchenhaar verdeckt ----
	if not female:
		var esz := 3 if str(d.get("ears", "plain")) == "big" else 2
		_rect(img, cx - face_hw - 1, ey, 1, esz, skin)
		_rect(img, cx + face_hw + 1, ey, 1, esz, skin_sh)
		if d.get("earring", false):
			var m := Color(0.95, 0.82, 0.30) if d.get("earring_gold", true) else Color(0.86, 0.88, 0.92)
			var ly := ey + esz
			match str(d.get("earring_kind", "stud")):
				"hoop":
					_rect(img, cx + face_hw + 1, ly, 2, 2, m); _px(img, cx + face_hw + 2, ly, OUTLINE)
				"drop":
					_px(img, cx + face_hw + 1, ly, m); _px(img, cx + face_hw + 1, ly + 2, m)
				_:
					_px(img, cx + face_hw + 1, ly, m)
	# ---- Haar (viele Frisuren) + Kopfbedeckung ----
	_hair(img, cx, htop, hbot, hh, hcy, hry, flat, hair, hair_hi,
		str(d.get("hair_style", "short")), female and bool(d.get("ribbon", false)),
		bool(d.get("recede", false)))
	_hat(img, cx, htop, hbot, hh, hcy, hry, flat, str(d.get("hat", "")), d.get("hat_col", Color(0.4, 0.4, 0.5)))
	# ---- Gesicht: Brauen, Augen, Nase, Brille, Mund ----
	var etype := str(d.get("eye_type", "round"))
	var ecol: Color = d.get("eye_col", Color(0.3, 0.2, 0.15))
	var l_shut := blink or act == "yawn" or act == "sleep"
	var r_shut := l_shut or act == "wink"
	# Brauen über den Augen (Typ: flat/thick/raised) — bei Gähnen weggelassen
	if act != "yawn":
		var bt := str(d.get("brow", "flat"))
		var by := ey - 2
		if act == "surprised" or bt == "raised": by = ey - 3
		_rect(img, cx - 6, by, 3, 1, brow_col)
		_rect(img, cx + 4, by, 3, 1, brow_col)
		if bt == "thick":
			_rect(img, cx - 6, by + 1, 3, 1, brow_col); _rect(img, cx + 4, by + 1, 3, 1, brow_col)
	_clean_eye(img, cx - 5, ey, l_shut, gaze, etype, ecol)
	_clean_eye(img, cx + 4, ey, r_shut, gaze, etype, ecol)
	# Nase (zwischen Augen und Mund — füllt die Gesichtsmitte)
	_px(img, cx, ey + 2, skin_hi)
	_px(img, cx, ey + 3, skin_sh)
	_px(img, cx - 1, ey + 3, skin.darkened(0.08))
	# Sommersprossen (optional)
	if bool(d.get("freckles", false)):
		var fc := skin.darkened(0.16)
		_px(img, cx - 4, ey + 3, fc); _px(img, cx - 2, ey + 4, fc)
		_px(img, cx + 3, ey + 3, fc); _px(img, cx + 5, ey + 4, fc)
	# Alterung in Chunky-Qualität: Falten wachsen stufig, Kinder kriegen Wangenrot.
	# (Alles unterhalb der Ponyzone — wird nie vom Haar überdeckt.)
	var age_now := int(d.get("age_now", 20))
	if age_now <= 12:
		var blush := skin.lerp(Color(0.9, 0.45, 0.45), 0.35)
		_px(img, cx - 5, ey + 4, blush); _px(img, cx + 4, ey + 4, blush)
	if age_now >= 38:                                    # Nasolabialfalten (my-2 = ey+4)
		_px(img, cx - 4, ey + 4, skin_sh); _px(img, cx + 4, ey + 4, skin_sh)
	if age_now >= 50:                                    # Tränensäcke + Krähenfüße
		_px(img, cx - 5, ey + 2, skin_sh); _px(img, cx + 4, ey + 2, skin_sh)
		_px(img, cx - face_hw + 1, ey, skin_sh); _px(img, cx + face_hw - 1, ey, skin_sh)
	if age_now >= 62:                                    # Wangenlinien + Mundfalten (my+1 = ey+7)
		_px(img, cx - 5, ey + 7, skin_sh); _px(img, cx + 5, ey + 7, skin_sh)
		_px(img, cx - 6, ey + 5, skin_sh); _px(img, cx + 6, ey + 5, skin_sh)
	# Brille (viele Sorten: round/square/thick/aviator/cat/half/sunglasses)
	_glasses(img, cx - 4, cx + 5, ey + 1, 2, str(d.get("glasses", "")))
	# Gesichtsbehaarung (vor dem Mund; nur Jungen/Männer)
	var my := ey + 6
	if not female:
		_beard(img, cx, hbot, hh, hcy, hry, flat, ey, my, str(d.get("beard", "")), hair.darkened(0.05))
	# Mund
	match act:
		"yawn":
			_rect(img, cx - 2, my - 1, 5, 5, OUTLINE); _rect(img, cx - 1, my + 1, 3, 2, Color(0.76, 0.36, 0.38))
		"surprised":
			_rect(img, cx - 1, my, 3, 3, OUTLINE)
		"grin", "tongue":
			_rect(img, cx - 3, my, 7, 1, OUTLINE); _px(img, cx - 3, my + 1, OUTLINE); _px(img, cx + 3, my + 1, OUTLINE)
			_rect(img, cx - 2, my + 1, 5, 1, Color(0.96, 0.96, 0.92))
			if act == "tongue": _rect(img, cx - 1, my + 2, 3, 1, Color(0.86, 0.38, 0.42))
		"wink":
			_rect(img, cx - 2, my + 1, 5, 1, OUTLINE); _px(img, cx + 3, my, OUTLINE)
		_:
			if d["grin"]:
				_rect(img, cx - 3, my, 7, 1, OUTLINE); _px(img, cx - 3, my + 1, OUTLINE); _px(img, cx + 3, my + 1, OUTLINE)
			else:
				_rect(img, cx - 2, my, 4, 1, skin.darkened(0.30))
	# ---- Hals + Schultern (Bust) in Kleidungsfarbe ----
	_rect(img, cx - 2, hbot, 5, 2, skin)
	var sy := hbot + 2
	for y in range(sy, px):
		var half := mini((y - sy) + 6, cx)
		_rect(img, cx - half, y, 2 * half + 1, 1, cloth)
		_px(img, cx + half - 1, y, cloth_sh)
	_outline(img)
	return ImageTexture.create_from_image(img)


## „Porträt"-Ersatz fürs alte 128er: der klare Kopf-Avatar, crisp (nearest) auf px
## hochskaliert; Emotion → Ausdruck. Von NPCManager.portrait / PlayerIdentity.texture.
static func portrait(id: String, hints: Dictionary = {}, px: int = 128) -> ImageTexture:
	var act := str(EMOTION_ACT.get(str(hints.get("emotion", "")), ""))
	var img := face(id, 32, hints, false, 0, act).get_image()
	img.resize(px, px, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


## Kopf-Avatar-Auge mit Iris-Farbe + Typ (round/narrow/wide). Geschlossen = Strich.
static func _clean_eye(img: Image, xc: int, ey: int, shut: bool, gaze: int, etype: String = "round", ecol: Color = Color(0.3, 0.2, 0.15)) -> void:
	if shut:
		_rect(img, xc, ey + 1, 2, 1, CHIBI_EYE)
		return
	var ew := 3 if etype == "wide" else 2
	var eh := 2 if etype == "narrow" else 3
	var gx := clampi(xc + gaze, xc - 1, xc + 1)
	_rect(img, gx, ey, ew, eh, CHIBI_EYE)                       # Augen-Weiß/Rahmen dunkel
	_px(img, gx + maxi(0, gaze) + (1 if ew == 3 else 0), ey + eh - 2, ecol)  # Iris (Augenfarbe)
	_px(img, gx, ey, Color(1, 1, 1, 0.9))                      # Glanzpunkt


## Saubere, simple Pixel-Figur im „Pixel Characters"-Stil: klare Silhouette, flache
## Farben, dicke Kontur, kleines Outfit (Hemd+Hose bzw. Kleid). Kopf moderat groß
## (NICHT Chibi). Deterministisch aus derselben Identität wie das Porträt; NPCs
## können später ein Rollen-Kostüm (hints["outfit"]) bekommen.
static func figure(id: String, w: int = 32, h: int = 48, hints: Dictionary = {}, blink: bool = false, gaze: int = 0, act: String = "") -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var d := dna(id, hints)
	var cx := floori(w / 2.0)
	var skin: Color = d["skin"]
	var hair: Color = d["hair"]
	var hair_hi := hair.lightened(0.16)
	var cloth: Color = d["shirt"]
	var cloth_sh := cloth.darkened(0.20)
	var cloth_hi := cloth.lightened(0.12)
	var pants: Color = d["shorts"]
	var female: bool = str(d.get("gender", "m")) == "f"
	var shoe := Color(0.26, 0.24, 0.28)
	# Bodenschatten (direkt unter den Füßen)
	_rect(img, cx - 6, h - 4, 13, 1, Color(0, 0, 0, 0.16))
	_rect(img, cx - 5, h - 3, 11, 1, Color(0, 0, 0, 0.10))

	# ---------- Kopf (moderat, gerundet; Form variiert Breite/Höhe) ----------
	var fshape := str(d.get("face_shape", "oval"))
	var skin_hi := skin.lightened(0.10)
	var skin_sh := skin.darkened(0.15)
	var hw := 7
	var htop := 3
	var hbot := 17
	match fshape:
		"round": hw = 8; hbot = 16
		"square": hw = 8
		"long": hw = 6; hbot = 18
	var hcy := float(htop + hbot) * 0.5
	var hry := float(hbot - htop) * 0.5
	var flat := 0.58 if fshape == "square" else 0.80
	# Kopf elliptisch (GLEICHE Geometrie wie das Haar → Frisuren sitzen exakt)
	for y in range(htop, hbot + 1):
		var half := _hw_at(y, hcy, hry, hw, flat, hbot)
		if half < 2:
			continue
		for x in range(cx - half, cx + half + 1):
			var c := skin
			if x >= cx + half - 1: c = skin_sh                     # Schattenseite (rechts)
			elif x <= cx - half + 1 and float(y) < hbot - hry * 0.4: c = skin_hi  # Lichtseite
			_px(img, x, y, c)
	# Augen tiefer (≈57 % der Kopfhöhe) + Brauen/Nase/Ohren → Gesicht sitzt richtig
	var ey := htop + int(round((hbot - htop) * 0.57))
	var fhw := _hw_at(ey, hcy, hry, hw, flat, hbot)
	if not female:                                                # Ohren (bei langem Haar verdeckt)
		var esz := 2 if str(d.get("ears", "plain")) == "big" else 1
		_rect(img, cx - fhw - 1, ey, 1, esz + 1, skin)
		_rect(img, cx + fhw + 1, ey, 1, esz + 1, skin_sh)
	if act != "yawn":                                             # Brauen
		var by := ey - 2 if act == "surprised" else ey - 1
		_px(img, cx - 4, by, hair); _px(img, cx - 3, by, hair)
		_px(img, cx + 2, by, hair); _px(img, cx + 3, by, hair)
	var l_shut := blink or act == "yawn" or act == "sleep"
	var r_shut := blink or act == "yawn" or act == "sleep" or act == "wink"
	_pixel_eye(img, cx - 3, ey, l_shut, gaze)
	_pixel_eye(img, cx + 2, ey, r_shut, gaze)
	_px(img, cx, ey + 1, skin_sh)                                 # Nase
	_px(img, cx, ey, skin_hi)
	var my := ey + 4
	match act:
		"yawn": _rect(img, cx - 1, my, 3, 2, OUTLINE)
		"surprised": _rect(img, cx, my, 1, 2, OUTLINE)
		_:
			if d["grin"] or act == "grin" or act == "tongue":
				_px(img, cx - 1, my, OUTLINE); _px(img, cx + 1, my, OUTLINE); _px(img, cx, my + 1, OUTLINE)
				if act == "tongue": _px(img, cx, my + 1, Color(0.87, 0.40, 0.44))
			else:
				_px(img, cx, my, skin.darkened(0.30))
	# Brille (viele Sorten) — kleiner Radius für die Figur
	_glasses(img, cx - 3, cx + 2, ey, 1, str(d.get("glasses", "")))

	# ---------- Haar (viele Frisuren, skaliert) + Kopfbedeckung ----------
	_hair(img, cx, htop, hbot, hw, hcy, hry, flat,
		hair, hair_hi, str(d.get("hair_style", "short")), female and bool(d.get("ribbon", false)),
		bool(d.get("recede", false)))
	_hat(img, cx, htop, hbot, hw, hcy, hry, flat, str(d.get("hat", "")), d.get("hat_col", Color(0.4, 0.4, 0.5)))

	# ---------- Körper (Referenz-Pixel-Art statt Chibi: schlanker Torso, hängende
	# Arme, lange Beine mit Lücke, Cel-Schattenkante, Innen-Konturen) ----------
	var sep := OUTLINE.lerp(cloth, 0.25)                 # weiche Innen-Kontur
	var skin_dk := skin.darkened(0.15)
	_rect(img, cx - 1, hbot + 1, 3, 1, skin)             # Hals
	_rect(img, cx - 1, hbot + 1, 3, 1, Color(skin_dk.r, skin_dk.g, skin_dk.b, 0.55))  # Kinnschatten
	if d.get("necklace", false):
		_rect(img, cx - 1, hbot + 2, 3, 1, Color(0.95, 0.82, 0.30))
	var top := hbot + 2
	if female:
		# Kleid: schmalere A-Linie, Saum höher → längere Beine
		var hem := 33
		for y in range(top, hem + 1):
			var t := float(y - top) / float(hem - top)
			var half := int(round(lerp(3.0, 7.0, t)))
			for x in range(cx - half, cx + half + 1):
				var c := cloth
				if x >= cx + half - 1: c = cloth_sh                 # Schattenkante rechts
				elif x <= cx - half + 1: c = cloth_hi               # Lichtkante links
				_px(img, x, y, c)
		_rect(img, cx - 2, top, 5, 1, sep)                   # Kragen-Kontur
		_rect(img, cx - 7, hem, 15, 1, cloth_sh.darkened(0.20))  # Saum
		if str(d.get("top", "")) in ["stripes", "logo", "vneck", "polo"]:
			_top(img, cx, top, cloth, cloth_hi, cloth_sh, skin, pants, str(d["top"]))
		for sgn: int in [-1, 1]:  # Arme direkt am Kleid: Ärmel → Haut → Hand
			var ax := cx + sgn * 4 - (1 if sgn < 0 else 0)
			_rect(img, ax, top + 1, 2, 2, cloth_sh if sgn > 0 else cloth)   # Ärmel
			_rect(img, ax, top + 3, 2, 5, skin if sgn < 0 else skin_sh)     # Arm
			_rect(img, ax, top + 8, 2, 1, skin_dk)                          # Hand
		# Beine mit Lücke + Schuhe
		_rect(img, cx - 3, hem + 1, 2, 8, skin)
		_rect(img, cx + 2, hem + 1, 2, 8, skin_sh)
		_rect(img, cx - 4, hem + 9, 4, 2, shoe); _px(img, cx - 4, hem + 9, shoe.lightened(0.25))
		_rect(img, cx + 1, hem + 9, 4, 2, shoe); _px(img, cx + 1, hem + 9, shoe.lightened(0.25))
	else:
		# Hemd (schlank) + lange Hose mit Beinlücke
		var tor := 10                                        # Torso-Höhe
		_rect(img, cx - 4, top, 9, tor, cloth)
		_rect(img, cx + 3, top, 2, tor, cloth_sh)            # Schattenkante rechts
		_rect(img, cx - 4, top, 1, tor - 1, cloth_hi)        # Lichtkante links
		_rect(img, cx - 2, top, 5, 1, sep)                   # Kragen-Kontur
		_top(img, cx, top, cloth, cloth_hi, cloth_sh, skin, pants, str(d.get("top", "plain")))
		# Hängende Arme außen am Torso: Ärmel → Haut → Hand
		for sgn: int in [-1, 1]:
			var ax := cx + sgn * 5 - (1 if sgn < 0 else 0)
			_rect(img, ax, top + 1, 2, 3, cloth_sh if sgn > 0 else cloth)   # kurzer Ärmel
			_rect(img, ax, top + 4, 2, 5, skin if sgn < 0 else skin_sh)     # Unterarm
			_rect(img, ax, top + 9, 2, 1, skin_dk)                          # Hand
		var py := top + tor
		_rect(img, cx - 4, py, 9, 1, pants.darkened(0.35))   # Bund (Innen-Kontur)
		_rect(img, cx - 4, py + 1, 9, 12, pants)             # lange Beine
		_rect(img, cx - 4, py + 1, 1, 12, pants.lightened(0.10))  # Lichtkante
		_rect(img, cx + 2, py + 1, 3, 12, pants.darkened(0.14))   # Schattenseite
		_rect(img, cx, py + 3, 1, 10, pants.darkened(0.30))  # Beinlücke
		_rect(img, cx - 5, py + 13, 5, 2, shoe); _px(img, cx - 5, py + 13, shoe.lightened(0.25))
		_rect(img, cx + 1, py + 13, 5, 2, shoe); _px(img, cx + 1, py + 13, shoe.lightened(0.25))

	_outline(img)
	return ImageTexture.create_from_image(img)


## Simples Pixel-Auge: 1×2 dunkel (offen), 1px (geschlossen), Blick verschiebt ±1.
static func _pixel_eye(img: Image, x: int, ey: int, shut: bool, gaze: int) -> void:
	if shut:
		_px(img, x, ey + 1, CHIBI_EYE)
		return
	var gx := clampi(x + gaze, x - 1, x + 1)
	_px(img, gx, ey, CHIBI_EYE)
	_px(img, gx, ey + 1, CHIBI_EYE)
