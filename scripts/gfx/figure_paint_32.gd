class_name FigurePaint32
## Handgesetzte 32×48-Figur; nur ganzzahlig und mit Nearest-Neighbour vergrößern.
const Accessories := preload("res://scripts/gfx/figure_accessories_32.gd")

const Raster := preload("res://scripts/gfx/pixel_raster_32.gd")
const AvatarPalette := preload("res://scripts/gfx/avatar_palette_32.gd")
const HairCatalog := preload("res://scripts/gfx/portrait_hair_catalog_32.gd")
const W := 32
const H := 48

const OUTLINE := Accessories.OUTLINE
const EYE_DARK := Color8(39, 29, 34)
const EYE_WHITE := Accessories.EYE_WHITE
const LIP := Color8(139, 62, 63)
const METAL := Accessories.METAL
const SHOE := Color8(48, 43, 53)
const SHOE_HI := Color8(79, 72, 83)
static func figure(id: String, hints: Dictionary = {}, frame_state: Dictionary = {}) -> ImageTexture:
	return ImageTexture.create_from_image(image(id, hints, frame_state))

static func image(id: String, hints: Dictionary = {}, frame_state: Dictionary = {}) -> Image:
	var selection := PortraitGen.selection_for(id, hints, frame_state)
	return image_from_selection(selection, hints)

## Für Vorschauen mit bereits kanonischer Auswahl; Hints enthalten Setupfelder.
static func image_from_selection(raw_selection: Dictionary, hints: Dictionary = {}) -> Image:
	var sel := raw_selection.duplicate(true)
	var anatomy := _anatomy(sel)
	var skin := AvatarPalette.figure_ramp(AvatarPalette.figure_base(
		"skin", str(sel.get("skin", "beige")), Color8(216, 166, 126)))
	var hair_key := str(sel.get("hair_color", sel.get("hair", "brown")))
	var hair_base := AvatarPalette.figure_base("hair", hair_key, Color8(91, 62, 44))
	# Dieselbe Altersgrau-DNA wie im Detailportraet; Jugendhaar altert sichtbar mit.
	hair_base = hair_base.lerp(Color8(170, 169, 166), clampf(float(sel.get("grey_t", 0.0)), 0.0, 1.0))
	var hair := AvatarPalette.figure_ramp(hair_base)
	var cloth_key := str(sel.get("shirt_color", sel.get("personality", "teal")))
	var cloth := AvatarPalette.figure_ramp(AvatarPalette.figure_base(
		"cloth", cloth_key, Color8(42, 126, 133)))
	var pants := AvatarPalette.figure_ramp(AvatarPalette.figure_pants(sel, cloth_key))

	# Bodenschatten bleibt außerhalb der Kontur.
	var result := Image.create(W, H, false, Image.FORMAT_RGBA8)
	_draw_ground_shadow(result, anatomy)
	var body := Image.create(W, H, false, Image.FORMAT_RGBA8)
	_draw_hair_back(body, sel, hair, anatomy)
	_draw_legs(body, pants, anatomy)
	_draw_arms_and_torso(body, sel, hints, skin, cloth, anatomy)
	_draw_neck(body, skin, anatomy)
	_draw_ears_and_head(body, sel, skin, anatomy)
	_draw_face(body, sel, skin, hair, anatomy)
	_draw_hair_front(body, sel, hair, anatomy)
	Accessories.draw(body, sel, cloth, anatomy, _face_span)
	Raster.outline(body, OUTLINE)
	result.blend_rect(body, Rect2i(0, 0, W, H), Vector2i.ZERO)
	return result

static func _anatomy(sel: Dictionary) -> Dictionary:
	var female := str(sel.get("gender", "f" if bool(sel.get("female", false)) else "m")) == "f"
	var stage := str(sel.get("life_stage", "young_adult"))
	var youthful := stage in ["early_teen", "late_teen"]
	var build := clampi(int(sel.get("build", signi(int(sel.get("mouth_width", 0))))), -1, 1)
	var turn := clampi(int(sel.get("head_turn", sel.get("eye_asymmetry", 0))), -1, 1)
	if turn == 0:
		turn = -1 if int(sel.get("hair_sweep", -1)) < 0 else 1
	var lean := clampi(int(sel.get("mouth_shift", 0)), -1, 1)
	var stance := -1 if int(sel.get("hair_sweep", -1)) < 0 else 1
	var stance_width := 1
	var shoulder := (7 if female else 8) + (1 if build > 0 else 0)
	var chest := (6 if female else 7) + (1 if build > 0 else 0)
	var waist := (4 if female else 6) + build
	var hip := (6 if female else 5) + (1 if build > 0 else 0)
	match stage:
		"early_teen":
			# Jugendliche Silhouette bei unveränderter Gesichts-DNA.
			shoulder -= 2
			chest -= 1
			waist -= 1
			hip -= 1
			stance_width = 0
		"late_teen":
			shoulder -= 1
			chest -= 1
			if female: hip -= 1
			stance_width = 1
		"adult", "mature":
			# Gefestigte erwachsene Silhouette.
			shoulder += 1
			if not female: chest += 1
			# Drei Pixel Standweite unterscheiden den belasteten Erwachsenenstand
			# auch im kleinen HUD eindeutig vom geschlossenen Teenagerstand.
			stance_width = 3
	var body_x := 16 + lean
	return {
		"female": female,
		"youthful": youthful,
		"body_x": body_x,
		"head_x": body_x + turn,
		"turn": turn,
		"stance": stance,
		"stance_width": stance_width,
		# Sieben Pixel bleiben das lesbare Minimum inklusive Ärmel/Armkontur;
		# die Jugendwirkung entsteht weiterhin über Brust, Hüfte und Stand.
		"shoulder": clampi(shoulder, 7, 9),
		"chest": clampi(chest, 5, 8),
		"waist": clampi(waist, 4, 7),
		"hip": clampi(hip, 5, 7),
	}

# -------------------------------------------------------------- Body / pose

static func _draw_ground_shadow(img: Image, anatomy: Dictionary) -> void:
	var cx := int(anatomy["body_x"])
	var stance_width := int(anatomy.get("stance_width", 1))
	var shadow := Color(0.04, 0.035, 0.055, 0.34)
	Raster.line(img, cx - 7 - stance_width, cx + 7 + stance_width, 46, shadow)
	Raster.line(img, cx - 5 - stance_width, cx + 5 + stance_width, 47, Color(0.04, 0.035, 0.055, 0.18))


static func _draw_legs(img: Image, pants: Array[Color], anatomy: Dictionary) -> void:
	var cx := int(anatomy["body_x"])
	var hip := int(anatomy["hip"])
	var stance := int(anatomy["stance"])
	var stance_width := int(anatomy.get("stance_width", 1))
	var turn := int(anatomy["turn"])
	# Pelvis bridges torso and legs without the disconnected doll-joint gap.
	for y in range(28, 33):
		var half := hip - int(y == 32)
		Raster.line(img, cx - half, cx + half, y, pants[2])
		Raster.px(img, cx - half, y, pants[3])
		Raster.line(img, cx + half - 1, cx + half, y, pants[1])
	Raster.line(img, cx - hip + 1, cx + hip - 1, 29, pants[3])
	# The turned-away leg is painted first and one value darker.
	var far_side := turn
	var near_side := -turn
	_draw_leg(img, cx, far_side, stance, stance_width, pants, false)
	_draw_leg(img, cx, near_side, stance, stance_width, pants, true)
	# Fly/seam and waistband are readable at 6x without becoming checkerboard.
	Raster.vline(img, cx, 30, 34, OUTLINE)
	Raster.px(img, cx + turn, 30, pants[4])


static func _draw_leg(img: Image, cx: int, side: int, stance: int, stance_width: int,
		pants: Array[Color], near: bool) -> void:
	# Hips begin as one weight-bearing mass.  The legs separate below the upper
	# thigh and only the stance-side foot steps outward; this avoids two parallel
	# sticks dangling from a floating pelvis.
	var base_x := cx + side * 2
	var shade := pants[2] if near else pants[1]
	var light := pants[3] if near else pants[2]
	for y in range(31, 44):
		var t := y - 31
		var shift := 0
		if t >= 4 and stance_width >= 1:
			shift += side
		if t >= 9 and (stance_width >= 2 or (stance_width == 1 and side == stance)):
			shift += side
		var leg_x := base_x + shift
		var half := 2 if t < 8 else 1
		Raster.line(img, leg_x - half, leg_x + half, y, shade)
		Raster.px(img, leg_x - half, y, light)
		if t in [6, 7]:
			# Two-pixel knee fold gives the leg a joint instead of reading as a
			# featureless trouser column.
			Raster.line(img, leg_x - 1, leg_x + 1, y, pants[1])
			Raster.px(img, leg_x - side, y - 1, light)
	# Mindestens drei transparente Spalten vor dem Outline-Pass verhindern,
	# dass beide Schuhe zu einer dunklen Plattform zusammenwachsen.
	# Die Reifestufe braucht auch in der 32x48-Silhouette eine lesbare Haltung:
	# Jugendliche stehen enger, Erwachsene mit sichtbar breiterem Stand. Die
	# maximale Spreizung bleibt auf zwei Zusatzpixel je Seite begrenzt.
	var ankle_x := base_x + side * (1 + mini(stance_width, 2))
	# Toes point outwards.  This preserves two transparent columns between the
	# outlined shoes; centred five-pixel shoes touched into one black platform.
	var shoe_left := ankle_x - 3 if side < 0 else ankle_x - 1
	Raster.rect(img, shoe_left, 44, 5, 2, SHOE)
	Raster.line(img, shoe_left + 1, shoe_left + 3, 44, SHOE_HI)
	Raster.px(img, shoe_left - 1 if side < 0 else shoe_left + 5, 45, SHOE)
	Raster.line(img, shoe_left, shoe_left + 4, 46, OUTLINE)


static func _draw_arms_and_torso(img: Image, sel: Dictionary, hints: Dictionary,
		skin: Array[Color], cloth: Array[Color], anatomy: Dictionary) -> void:
	var cx := int(anatomy["body_x"])
	var turn := int(anatomy["turn"])
	var shoulder := int(anatomy["shoulder"])
	var hip := int(anatomy["hip"])
	var top := str(hints.get("top", sel.get("shirt", "tee"))).to_lower()
	var sleeveless := top in ["tank", "tanktop"]
	var body_pose := str(hints.get("body_pose", "idle"))
	# Far arm hangs with a slight elbow, the near arm rests toward the hip.  The
	# two poses make the outline asymmetric without an idle animation offset.
	var far := turn
	var near := -turn
	match body_pose:
		"work":
			_draw_counter_arm(img, cx, far, shoulder, skin, cloth, sleeveless)
			_draw_counter_arm(img, cx, near, shoulder, skin, cloth, sleeveless)
		"talk":
			_draw_hanging_arm(img, cx, far, shoulder, skin, cloth, sleeveless, false)
			_draw_gesture_arm(img, cx, near, shoulder, skin, cloth, sleeveless)
		_:
			_draw_hanging_arm(img, cx, far, shoulder, skin, cloth, sleeveless, false)
			_draw_bent_arm(img, cx, near, shoulder, hip, skin, cloth, sleeveless)

	for y in range(17, 30):
		var half := _torso_half(y, anatomy)
		var row_x := cx + int(y >= 22 and y <= 27 and anatomy["female"] and turn > 0)
		Raster.line(img, row_x - half, row_x + half, y, cloth[2])
		# EINE Lichtkante links, EINE Schattenkante rechts — das frühere
		# Hellst-Sprenkel fast jeder Zeile machte den Stoff zu Rauschen.
		Raster.px(img, row_x - half, y, cloth[3])
		Raster.line(img, row_x + half - 1, row_x + half, y, cloth[1])
		# Internal side seams separate shirt from same-value sleeves/arms.  They
		# stop above the hem, so the torso remains one coherent mass.
		if y >= 20 and y <= 27:
			Raster.px(img, row_x - half + 1, y, cloth[0])
			Raster.px(img, row_x + half - 1, y, cloth[0])
	# A short shoulder break makes neck, shoulder and sleeve readable as three
	# joined forms without adding any pixels to the silhouette.
	Raster.line(img, cx - shoulder + 2, cx - 3, 18, cloth[1])
	Raster.line(img, cx + 3, cx + shoulder - 2, 18, cloth[0])
	# Genau EINE dezente Stofffalte statt verteilter Einzelpixel — und ein
	# Saum als unterer Hemdabschluss (trennt Hemd sauber von der Hose).
	Raster.vline(img, cx + 2, 24, 27, cloth[1])
	var hem_half := _torso_half(29, anatomy)
	Raster.line(img, cx - hem_half + 1, cx + hem_half - 1, 29, cloth[1])
	_apply_top_details(img, cx, top, sel, cloth, anatomy)


static func _torso_half(y: int, anatomy: Dictionary) -> int:
	if y <= 18:
		return int(anatomy["shoulder"]) - int(y == 17)
	if y <= 21:
		return int(anatomy["chest"])
	if y <= 26:
		return int(anatomy["waist"])
	return int(anatomy["hip"])


static func _draw_hanging_arm(img: Image, cx: int, side: int, shoulder: int,
		skin: Array[Color], cloth: Array[Color], sleeveless: bool, _near: bool) -> void:
	var sx := cx + side * (shoulder - 1)
	var cloth_col: Color = cloth[2]
	var skin_col: Color = skin[2]
	if not sleeveless:
		Raster.segment(img, Vector2i(sx, 19), Vector2i(sx + side * 2, 22), 1, cloth_col)
	else:
		Raster.segment(img, Vector2i(sx, 18), Vector2i(sx + side * 2, 22), 1, skin_col)
	Raster.segment(img, Vector2i(sx + side * 2, 22), Vector2i(sx + side * 2, 31), 1, skin_col)
	Raster.vline(img, sx + side * 2 + side, 23, 30, skin[1])
	# Hand mit Lichtoberseite — der einheitliche Klumpen wirkte wie ein Stumpf.
	Raster.rect(img, sx + side * 2 - 1, 31, 3, 2, skin_col)
	Raster.line(img, sx + side * 2 - 1, sx + side * 2 + 1, 31, skin[3])
	Raster.px(img, sx + side * 2, 33, skin[1])
	# Ärmelsaum: eine dunkle Abschlusskante am Ärmelende.
	if not sleeveless:
		Raster.px(img, sx + side * 2, 22, cloth[1])


static func _draw_bent_arm(img: Image, cx: int, side: int, shoulder: int, hip: int,
		skin: Array[Color], cloth: Array[Color], sleeveless: bool) -> void:
	var sx := cx + side * (shoulder - 1)
	var elbow := Vector2i(sx + side * 2, 24)
	if not sleeveless:
		Raster.segment(img, Vector2i(sx, 19), elbow, 1, cloth[2])
		Raster.px(img, sx - side, 19, cloth[4])
	else:
		Raster.segment(img, Vector2i(sx, 18), elbow, 1, skin[2])
	var hand := Vector2i(cx + side * (hip + 1), 29)
	Raster.segment(img, elbow, hand, 1, skin[2])
	Raster.px(img, hand.x - side, hand.y, skin[4])
	Raster.px(img, hand.x, hand.y + 1, skin[1])


static func _draw_gesture_arm(img: Image, cx: int, side: int, shoulder: int,
		skin: Array[Color], cloth: Array[Color], sleeveless: bool) -> void:
	var sx := cx + side * (shoulder - 1)
	var elbow := Vector2i(sx + side * 2, 22)
	Raster.segment(img, Vector2i(sx, 19), elbow, 1,
		skin[2] if sleeveless else cloth[2])
	# Offene Erklaergeste: Unterarm steigt in Richtung Gespraechspartner, die
	# Hand bleibt als einzelne helle Pixelgruppe lesbar.
	var hand := Vector2i(sx + side * 4, 20)
	Raster.segment(img, elbow, hand, 1, skin[2])
	Raster.px(img, hand.x, hand.y - 1, skin[4])
	Raster.px(img, hand.x + side, hand.y, skin[2])
	Raster.px(img, hand.x, hand.y + 1, skin[1])


static func _draw_counter_arm(img: Image, cx: int, side: int, shoulder: int,
		skin: Array[Color], cloth: Array[Color], sleeveless: bool) -> void:
	var sx := cx + side * (shoulder - 1)
	var elbow := Vector2i(sx + side, 23)
	Raster.segment(img, Vector2i(sx, 19), elbow, 1,
		skin[2] if sleeveless else cloth[2])
	var hand := Vector2i(cx + side * 2, 27)
	Raster.segment(img, elbow, hand, 1, skin[2])
	Raster.line(img, hand.x - 1, hand.x + 1, hand.y, skin[3])
	Raster.px(img, hand.x, hand.y + 1, skin[1])


static func _apply_top_details(img: Image, cx: int, top: String, sel: Dictionary,
		cloth: Array[Color], anatomy: Dictionary) -> void:
	var half20 := _torso_half(20, anatomy)
	match top:
		"striped", "stripes":
			for y in [20, 24, 27]:
				var half := _torso_half(y, anatomy) - 1
				Raster.line(img, cx - half, cx + half, y, cloth[0])
				if y != 27: Raster.line(img, cx - half + 1, cx + half - 2, y + 1, cloth[3])
		"hoodie":
			Raster.line(img, cx - 4, cx + 4, 18, cloth[0])
			Raster.vline(img, cx - 2, 19, 22, cloth[1]); Raster.vline(img, cx + 2, 19, 22, cloth[1])
			Raster.px(img, cx - 2, 19, cloth[4]); Raster.px(img, cx + 2, 19, cloth[4])
			Raster.line(img, cx - 3, cx + 3, 26, cloth[1]); Raster.line(img, cx - 2, cx + 2, 27, cloth[3])
		"jacket", "flannel":
			Raster.vline(img, cx, 18, 28, cloth[0])
			Raster.segment(img, Vector2i(cx - 3, 18), Vector2i(cx, 22), 0, cloth[4])
			Raster.segment(img, Vector2i(cx + 3, 18), Vector2i(cx, 22), 0, cloth[1])
			Raster.px(img, cx - 2, 24, cloth[4]); Raster.px(img, cx + 2, 26, cloth[0])
		"polo":
			# Zwei klare Kragenflügel + kurze Knopfleiste — lesbar als Polo.
			Raster.line(img, cx - 3, cx - 1, 17, cloth[4]); Raster.px(img, cx - 3, 18, cloth[4])
			Raster.line(img, cx + 1, cx + 3, 17, cloth[4]); Raster.px(img, cx + 3, 18, cloth[4])
			Raster.px(img, cx, 18, OUTLINE); Raster.px(img, cx, 20, OUTLINE); Raster.px(img, cx, 22, cloth[1])
		"vneck", "sweater":
			# Tiefes, geschlossenes V statt loser Einzelpixel.
			Raster.line(img, cx - 2, cx - 1, 17, cloth[0]); Raster.line(img, cx + 1, cx + 2, 17, cloth[0])
			Raster.px(img, cx - 1, 18, cloth[0]); Raster.px(img, cx + 1, 18, cloth[0])
			Raster.px(img, cx, 19, cloth[0])
		"overall":
			_paint_figure_overall(img, cx, cloth, anatomy)
		"track":
			# Trainingsjacke: Reißverschluss + SEITENSTREIFEN (das Ära-Bild).
			Raster.vline(img, cx, 18, 28, cloth[4]); Raster.px(img, cx, 20, OUTLINE)
			Raster.vline(img, cx - half20 + 1, 19, 27, cloth[0])
			Raster.vline(img, cx + half20 - 2, 19, 27, cloth[0])
		"logo":
			# Five-by-four stitched badge with a bright inset.  The former 3×2
			# mark collapsed into one vertical bar at setup scale.
			Raster.rect(img, cx - 2, 20, 5, 4, cloth[0])
			Raster.rect(img, cx - 1, 20, 3, 2, cloth[4])
			Raster.px(img, cx, 22, cloth[3]); Raster.px(img, cx + 1, 23, cloth[1])
		"tank", "tanktop":
			# Träger 2 px breit — ein einzelner Pixelstrich war kein Träger.
			Raster.vline(img, cx - 4, 17, 20, cloth[0]); Raster.vline(img, cx - 5, 17, 19, cloth[1])
			Raster.vline(img, cx + 4, 17, 20, cloth[0]); Raster.vline(img, cx + 5, 17, 19, cloth[1])
			Raster.line(img, cx - 2, cx + 2, 17, cloth[0])
		_:
			# Dezenter Rundhals-Kragen — die frühere Dunkelst-Linie las sich
			# als schwebender Querbalken auf der Brust.
			Raster.line(img, cx - 2, cx + 2, 17, cloth[1])
	# Optional jacket from PortraitGen still reads as a jacket even when a shirt
	# token selected the underlying layer.
	if str(sel.get("jacket", "")) != "" and top not in ["jacket", "flannel"]:
		Raster.vline(img, cx - 1, 19, 28, cloth[0]); Raster.vline(img, cx + 1, 19, 28, cloth[1])


static func _paint_figure_overall(img: Image, cx: int, shirt: Array[Color],
		anatomy: Dictionary) -> void:
	var denim := AvatarPalette.figure_ramp(AvatarPalette.DENIM)
	var turn := int(anatomy["turn"])
	# Das Shirt bleibt als Unterlage und an den Aermeln sichtbar. Die Traeger
	# laufen von den echten Schulterankern in den Latz, statt als zwei starre
	# Vertikalen neben dem Hals zu schweben.
	Raster.segment(img, Vector2i(cx - 4, 17), Vector2i(cx - 3, 22), 0, denim[1])
	Raster.segment(img, Vector2i(cx - 3, 17), Vector2i(cx - 2, 22), 0, denim[3])
	Raster.segment(img, Vector2i(cx + 4, 17), Vector2i(cx + 3, 22), 0, denim[0])
	Raster.segment(img, Vector2i(cx + 3, 17), Vector2i(cx + 2, 22), 0, denim[2])
	# Trapezlatz: oben schmal, an Taille/Bund breiter. Jede Zeile respektiert
	# die aktuelle Teen-/Erwachsenen-Silhouette.
	for y in range(21, 29):
		var torso_half := maxi(2, _torso_half(y, anatomy) - 1)
		var bib_half := mini(torso_half, 3 + int(y >= 24) + int(y >= 27))
		var row_x := cx + int(y >= 22 and y <= 27 and anatomy["female"] and turn > 0)
		Raster.line(img, row_x - bib_half, row_x + bib_half, y, denim[2])
		Raster.px(img, row_x - bib_half, y, denim[3])
		Raster.px(img, row_x + bib_half, y, denim[1])
	# Der Denim-Bund schliesst ohne gruenen Zwischenstreifen an die bereits
	# denimfarbenen Hosenbeine an. Genau diese Luecke war im Setup sichtbar.
	for y in [28, 29]:
		var half := _torso_half(y, anatomy)
		Raster.line(img, cx - half, cx + half, y, denim[2])
		Raster.px(img, cx - half, y, denim[3]); Raster.px(img, cx + half, y, denim[1])
	Raster.px(img, cx - 3, 21, METAL); Raster.px(img, cx + 3, 21, METAL)
	Raster.rect(img, cx - 2, 23, 5, 3, denim[1])
	Raster.line(img, cx - 1, cx + 1, 23, denim[3])
	Raster.vline(img, cx + turn, 27, 34, denim[0])
	# Ein kleines Shirtdreieck am Kragen trennt Untershirt und Latz eindeutig.
	Raster.line(img, cx - 1, cx + 1, 17, shirt[4])


# --------------------------------------------------------------- Head / face

static func _draw_neck(img: Image, skin: Array[Color], anatomy: Dictionary) -> void:
	var hx := int(anatomy["head_x"])
	var bx := int(anatomy["body_x"])
	for y in range(14, 18):
		var cx := roundi(lerpf(float(hx), float(bx), float(y - 14) / 3.0))
		Raster.line(img, cx - 2, cx + 2, y, skin[2])
		Raster.px(img, cx - 2, y, skin[3]); Raster.px(img, cx + 2, y, skin[1])
	Raster.line(img, bx - 2, bx + 2, 16, skin[0])


static func _face_half(rel_y: int, shape: String) -> int:
	# Kopfvertrag V3: Die Stirn beginnt nicht mehr als schmale Spitze und die
	# Wangen wechseln nicht mitten im Gesicht mehrfach ihre Breite. Auf dem
	# kleinen Raster ist eine ruhige 7/9/11-px-Treppe lesbarer als eine groessere
	# Zahl vermeintlich anatomischer Ein-Pixel-Ausbuchtungen.
	var rows := [3, 4, 5, 5, 5, 5, 5, 5, 5, 5, 4, 3, 2]
	var half: int = rows[clampi(rel_y, 0, rows.size() - 1)]
	match shape:
		"round":
			if rel_y in [8, 9]: half += 1
		"square":
			if rel_y in [9, 10]: half += 1
		"long":
			if rel_y in [0, 10]: half -= 1
		"heart":
			# Herzform entsteht nur am Kiefer. Eine zusaetzliche Verbreiterung der
			# Schlaefen machte den Kopf im Ganzkoerperbild ballonartig.
			if rel_y in [9, 10]: half -= 1
	return maxi(2, half)


static func _face_span(y: int, sel: Dictionary, anatomy: Dictionary) -> Vector2i:
	var rel := y - 3
	var half := _face_half(rel, str(sel.get("head", sel.get("face_shape", "oval"))))
	var cx := int(anatomy["head_x"])
	var turn := int(anatomy["turn"])
	var left := cx - half
	var right := cx + half
	# Die 3/4-Drehung greift nur am unteren fernen Kiefer. Augen, Nase, Licht und
	# Ohr tragen den Rest der Perspektive. Asymmetrische Schlaefen/Wangen lesen
	# sich bei 32 px nicht als Drehung, sondern als anatomischer Fehler.
	if turn > 0:
		left += int(rel in [9, 10])
	else:
		right -= int(rel in [9, 10])
	return Vector2i(left, right)


static func _draw_ears_and_head(img: Image, sel: Dictionary, skin: Array[Color],
		anatomy: Dictionary) -> void:
	for y in range(3, 16):
		var row := _face_span(y, sel, anatomy)
		Raster.line(img, row.x, row.y, y, skin[2])
		# Pro Zeile hoechstens eine Licht- und Schattenkante. Die vorherige
		# zweispaltige Aufhellung zerlegte die Wange in grosse rechteckige Flecken.
		if y >= 5 and y <= 10:
			Raster.px(img, row.x + 1, y, skin[3])
		if y >= 5 and y <= 12:
			Raster.px(img, row.y, y, skin[1])
	# Ein einzelner Kinnakzent gibt Tiefe, ohne den dunklen Querbalken, der im
	# kleinen Bild wie Bart, offene Mundhoehle oder deformierter Kiefer wirkte.
	var chin := _face_span(14, sel, anatomy)
	Raster.px(img, clampi(int(anatomy["head_x"]) + int(anatomy["turn"]), chin.x, chin.y), 14, skin[1])
	# Das sichtbare Ohr ist ein ECHTES 1×3-Cluster mit Innenschatten auf der
	# blickabgewandten Seite (wie im Porträt) — die früheren Einzelpixel waren
	# bei 6× nicht als Ohr lesbar.
	var turn := int(anatomy["turn"])
	var span := _face_span(9, sel, anatomy)
	var ear_x := span.x - 1 if turn > 0 else span.y + 1
	var inner_x := span.x if turn > 0 else span.y
	# Ohr bleibt eine schmale Muschel. "Gross" verlaengert es nach unten, aber
	# niemals seitlich — genau die alte zweite Aussenspalte machte den Kopf breit.
	Raster.vline(img, ear_x, 8, 9, skin[2])
	Raster.px(img, ear_x, 9, skin[1])
	Raster.px(img, inner_x, 9, skin[1])
	Raster.px(img, ear_x, 8, skin[3])
	if str(sel.get("ears", "plain")) == "big":
		Raster.px(img, ear_x, 10, skin[2]); Raster.px(img, inner_x, 10, skin[1])
	# Fernes Ohr bleibt innerhalb der Kopfkontur als warmer Schatten — kein
	# zweiter seitlicher Knubbel an der Silhouette.
	Raster.px(img, span.y if turn > 0 else span.x, 9, skin[1])


static func _draw_face(img: Image, sel: Dictionary, skin: Array[Color], hair: Array[Color],
		anatomy: Dictionary) -> void:
	var cx := int(anatomy["head_x"])
	var turn := int(anatomy["turn"])
	var spacing := clampi(int(sel.get("eye_spacing", 0)), -1, 1)
	var far_distance := 2
	var near_distance := 3
	if spacing > 0:
		near_distance = 4
	elif spacing < 0:
		near_distance = 2
	var far_x := cx - turn * far_distance
	var near_x := cx + turn * near_distance
	var eye_type := str(sel.get("eye_type", "normal"))
	var eye_state := str(sel.get("eyes", "neutral"))
	if eye_state in ["", "neutral", "open"]:
		eye_state = eye_type
	var eye_y := 8 + int(eye_type == "droopy" or eye_state in ["tired", "half"])
	var iris := AvatarPalette.figure_iris(str(sel.get("eye_color", "brown")))
	var gaze := clampi(int(sel.get("gaze", 0)), -1, 1)
	_draw_figure_eye(img, far_x, turn, false, eye_y, eye_state, gaze, iris, skin)
	_draw_figure_eye(img, near_x, turn, true, eye_y, eye_state, gaze, iris, skin)
	# Nur das nahe Auge erhaelt ein kurzes Unterlid. Zwei senkrechte Lichtpixel
	# unter beiden Pupillen lasen sich bei 32 px wie herabgezogene Augen.
	if not eye_state in ["closed", "happy"]:
		Raster.px(img, near_x - turn, eye_y + 1, skin[3])
	# Brauen nur ohne Brille (die Brille ersetzt sie in dieser Größe) und in
	# hair[1], damit sie auch auf dunkler Haut nicht zu schwarzen Balken werden.
	if str(sel.get("glasses", "")) in ["", "none"]:
		var brow_y := eye_y - 1
		var mood := str(sel.get("mood", ""))
		var brow_type := str(sel.get("eyebrows", sel.get("brow", "flat")))
		if mood == "angry":
			Raster.px(img, far_x - turn, brow_y - 1, hair[1])
			Raster.px(img, far_x, brow_y, hair[1])
			Raster.px(img, near_x - turn, brow_y, hair[1])
			Raster.px(img, near_x, brow_y - 1, hair[1])
		elif mood == "sad":
			Raster.px(img, far_x - turn, brow_y, hair[1])
			Raster.px(img, far_x, brow_y - 1, hair[1])
			Raster.px(img, near_x - turn, brow_y - 1, hair[1])
			Raster.px(img, near_x, brow_y, hair[1])
		else:
			Raster.px(img, far_x, brow_y, hair[1])
			Raster.line(img, near_x - 1, near_x, brow_y, hair[1])
		if mood == "raise" or brow_type == "raised":
			Raster.px(img, near_x, brow_y - 1, hair[1])
		elif brow_type == "thick" and mood.is_empty():
			Raster.px(img, far_x - turn, brow_y, hair[1]); Raster.px(img, near_x, brow_y - 1, hair[1])
	# Nase: EIN sanfter Schattenpixel + Lichtkante — kein Doppel-Dunkelfleck
	# (skin[0] ist in dieser Rampe fast schwarz und las sich als Loch).
	var nose_x := cx + turn + clampi(int(sel.get("nose_shift", 0)), -1, 1)
	match str(sel.get("nose", "straight")):
		"small":
			Raster.px(img, nose_x, 11, skin[1])
		"wide":
			Raster.px(img, nose_x - turn, 10, skin[3]); Raster.line(img, nose_x - 1, nose_x + 1, 11, skin[1])
		"long":
			Raster.px(img, nose_x - turn, 10, skin[3]); Raster.px(img, nose_x, 11, skin[1]); Raster.px(img, nose_x, 12, skin[0])
		_:
			Raster.px(img, nose_x - turn, 10, skin[3]); Raster.px(img, nose_x, 11, skin[1])
	# Ein einzelner naher Wangenakzent schliesst die Flaeche zwischen Auge und
	# Kiefer. Er bleibt bewusst von Nase und Mund getrennt.
	Raster.px(img, cx + turn * 3, 11, skin[3])
	# Mundzeichen bleiben voneinander getrennte Posen. Neutral sind exakt zwei
	# Pixel; drei bis fuenf dunkle Pixel direkt ueber dem Kinn lasen als Klumpen.
	var mouth_x := cx + clampi(int(sel.get("mouth_shift", 0)), -1, 1)
	var mouth_col := LIP.lerp(skin[1], 0.15)
	var mouth_y := 13
	var mouth_pose := str(sel.get("mouth", "neutral"))
	if mouth_pose in ["smile", "happy"]:
		Raster.line(img, mouth_x - 1, mouth_x + 1, mouth_y, mouth_col)
		Raster.px(img, mouth_x - 1, mouth_y - 1, mouth_col)
		Raster.px(img, mouth_x + 1, mouth_y - 1, mouth_col)
	elif mouth_pose in ["laugh", "open", "ai", "talking"]:
		Raster.px(img, mouth_x, mouth_y, EYE_DARK)
		Raster.px(img, mouth_x, mouth_y + 1, mouth_col)
	elif mouth_pose == "ou":
		Raster.px(img, mouth_x, mouth_y, EYE_DARK)
		Raster.px(img, mouth_x + turn, mouth_y, mouth_col)
		Raster.px(img, mouth_x, mouth_y + 1, mouth_col)
	elif mouth_pose == "e":
		Raster.line(img, mouth_x - 1, mouth_x + 1, mouth_y, EYE_DARK)
		Raster.px(img, mouth_x, mouth_y, EYE_WHITE)
	elif mouth_pose == "fv":
		Raster.line(img, mouth_x - 1, mouth_x, mouth_y, mouth_col)
		Raster.px(img, mouth_x + 1, mouth_y + 1, skin[4])
	elif mouth_pose == "l":
		Raster.px(img, mouth_x, mouth_y, EYE_DARK)
		Raster.px(img, mouth_x, mouth_y - 1, mouth_col)
	elif mouth_pose in ["frown", "sad"]:
		Raster.line(img, mouth_x - 1, mouth_x + 1, mouth_y - 1, mouth_col)
		Raster.px(img, mouth_x - 1, mouth_y, mouth_col)
		Raster.px(img, mouth_x + 1, mouth_y, mouth_col)
	elif mouth_pose == "grit":
		Raster.line(img, mouth_x - 1, mouth_x + 1, mouth_y, EYE_DARK)
		Raster.px(img, mouth_x, mouth_y, EYE_WHITE)
	elif mouth_pose == "wavy":
		Raster.px(img, mouth_x - 1, mouth_y, mouth_col)
		Raster.px(img, mouth_x, mouth_y - 1, mouth_col)
		Raster.px(img, mouth_x + 1, mouth_y, mouth_col)
	else:
		Raster.line(img, mouth_x - 1, mouth_x, mouth_y, mouth_col)
	# Alter bleibt subtil und zusammenhaengend: kurze Augen-/Mundfalten statt
	# zufaelliger Sprenkel. Dadurch altert die Figur sichtbar mit dem Portraet.
	var age_now := int(sel.get("age_now", 20))
	if age_now >= 48:
		Raster.px(img, near_x + turn, eye_y + 1, skin[1])
		Raster.px(img, mouth_x + 2 * turn, mouth_y, skin[1])
	if age_now >= 65:
		Raster.px(img, far_x - turn, eye_y + 1, skin[1])
		Raster.px(img, mouth_x - turn, mouth_y + 1, skin[1])
	var beard := str(sel.get("beard", ""))
	if beard != "" and beard != "none":
		var s13 := _face_span(13, sel, anatomy)
		var s14 := _face_span(14, sel, anatomy)
		if beard in ["moustache", "mustache"]:
			Raster.line(img, mouth_x - 2, mouth_x + 1, 12, hair[1])
		elif beard == "handlebar":
			Raster.line(img, mouth_x - 2, mouth_x + 1, 12, hair[1])
			Raster.px(img, mouth_x - 3, 11, hair[2]); Raster.px(img, mouth_x + 2, 11, hair[2])
		elif beard == "stubble":
			Raster.px(img, s13.x + 1, 13, hair[1]); Raster.px(img, s14.x + 2, 14, hair[1])
			Raster.px(img, s14.y - 2, 14, hair[1])
		elif beard == "soulpatch":
			Raster.px(img, mouth_x, 14, hair[1]); Raster.px(img, mouth_x, 15, hair[0])
		elif beard in ["goatee", "chin"]:
			Raster.line(img, mouth_x - 1, mouth_x + 1, 14, hair[1]); Raster.line(img, mouth_x - 1, mouth_x + 1, 15, hair[0])
			if beard == "goatee": Raster.line(img, mouth_x - 2, mouth_x + 1, 12, hair[2])
		elif beard == "sideburns":
			Raster.vline(img, s13.x + 1, 10, 14, hair[1]); Raster.vline(img, s13.y - 1, 10, 14, hair[0])
		elif beard == "muttonchops":
			Raster.rect(img, s13.x, 10, 3, 5, hair[1]); Raster.rect(img, s13.y - 2, 10, 3, 5, hair[0])
		else:
			# Voll- und Langbart als offene Kiefer-U-Form; der Mund bleibt sichtbar.
			Raster.vline(img, s13.x + 1, 13, 14, hair[1])
			Raster.vline(img, s13.y - 1, 13, 14, hair[1])
			Raster.line(img, s14.x + 2, s14.y - 2, 14, hair[2])
			Raster.line(img, cx - 2, cx + 2, 15, hair[1])
			if beard in ["full", "longbeard"]:
				Raster.line(img, cx - 2, cx + 2, 16, hair[0])
			if beard == "longbeard":
				Raster.line(img, cx - 2, cx + 2, 17, hair[1]); Raster.line(img, cx - 1, cx + 1, 18, hair[0])


static func _draw_figure_eye(img: Image, center: int, turn: int, near: bool,
		y: int, state: String, gaze: int, iris: Color, skin: Array[Color]) -> void:
	# Zwei beziehungsweise drei Pixel reichen fuer klar lesbare AGA-Lider und
	# Pupillen. Emotion aendert nur diese Mikro-Silhouette, niemals die DNA.
	var left := center - turn
	# Schmale Augen bleiben zwei Pixel breit; die Normalform hat am nahen
	# Auge einen zusaetzlichen Lichtpixel. Beide behalten dieselbe Blickachse.
	var right := center + (turn if near and state != "narrow" else 0)
	var x0 := mini(left, right)
	var x1 := maxi(left, right)
	match state:
		"closed":
			Raster.line(img, x0, x1, y, EYE_DARK)
			return
		"happy":
			Raster.line(img, x0, x1, y, EYE_DARK)
			Raster.px(img, center, y - 1, skin[3])
			return
		"sad":
			Raster.px(img, x0, y - 1, EYE_DARK)
		"angry":
			Raster.px(img, x1, y - 1, EYE_DARK)
		"surprised", "wide":
			Raster.line(img, x0, x1, y + 1, EYE_WHITE)
		"tired", "half":
			Raster.line(img, x0, x1, y - 1, EYE_DARK)
		"nervous", "thinking":
			Raster.px(img, x0 if near else x1, y - 1, skin[1])
	for x in range(x0, x1 + 1):
		Raster.px(img, x, y, EYE_WHITE)
	var pupil_x := clampi(center + gaze, x0, x1)
	Raster.px(img, pupil_x, y, iris)


# ---------------------------------------------------------------------- Hair

static func _long_hair(style: String) -> bool:
	# bun/pigtails tragen KEINE offene Rückenmähne: der Dutt ist hochgesteckt,
	# die Zöpfe hängen seitlich — sonst sehen alle Hochsteck-Stile wie „lang" aus.
	return style in ["straight", "medium", "long", "bob", "mullet"]


static func _draw_hair_back(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary) -> void:
	var style := HairCatalog.style_for_back(
		str(sel.get("hair_style", sel.get("hair_front", "short"))),
		str(sel.get("hat", "")))
	if style == "bald":
		return
	var cx := int(anatomy["head_x"])
	var sweep := int(anatomy["stance"])
	if _long_hair(style):
		for y in range(5, 22 if style == "long" else 19):
			var half := 7 if y < 15 else maxi(3, 7 - floori((y - 14) / 2.0))
			Raster.line(img, cx - half, cx + half, y, hair[1])
			if y % 3 != 0: Raster.line(img, cx - half + 1, cx - half + 2, y, hair[3])
			Raster.px(img, cx + half, y, hair[0])
	if style == "ponytail":
		Raster.segment(img, Vector2i(cx + sweep * 6, 6), Vector2i(cx + sweep * 9, 17), 1, hair[1])
		Raster.px(img, cx + sweep * 7, 8, hair[3]); Raster.px(img, cx + sweep * 10, 17, hair[3])
		Raster.px(img, cx + sweep * 6, 7, OUTLINE)
	elif style == "pigtails":
		# Bilaterale gebundene Zoepfe mit sichtbaren Bindern und schmaleren Enden.
		Raster.segment(img, Vector2i(cx - 6, 7), Vector2i(cx - 9, 16), 1, hair[2])
		Raster.segment(img, Vector2i(cx + 6, 7), Vector2i(cx + 9, 16), 1, hair[1])
		Raster.px(img, cx - 7, 8, METAL); Raster.px(img, cx + 7, 8, METAL)
		Raster.px(img, cx - 9, 17, hair[3]); Raster.px(img, cx + 9, 17, hair[0])
	elif style == "bun":
		Raster.rect(img, cx - 3 - sweep, 0, 6, 4, hair[1])
		Raster.line(img, cx - 2 - sweep, cx + 1 - sweep, 0, hair[3])
		Raster.px(img, cx + 2 - sweep, 2, hair[0])
	elif style == "mullet":
		Raster.line(img, cx - 6, cx + 6, 16, hair[1]); Raster.line(img, cx - 5, cx + 5, 18, hair[0])


static func _draw_hair_front(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary) -> void:
	var style := HairCatalog.style_for_front(
		str(sel.get("hair_style", sel.get("hair_front", "short"))),
		str(sel.get("hat", "")))
	if style == "bald":
		return
	var cx := int(anatomy["head_x"])
	var sweep := int(sel.get("hair_sweep", anatomy["stance"]))
	match style:
		"bald":
			return
		"mohawk":
			# Zusammenhängender, leicht geneigter Keil mit rasierten Seiten.
			Raster.line(img, cx - 1, cx, 0, hair[2])
			Raster.line(img, cx - 2, cx + 1, 1, hair[2])
			Raster.line(img, cx - 2, cx + 1, 2, hair[2])
			Raster.line(img, cx - 3, cx + 2, 3, hair[2])
			Raster.line(img, cx - 3, cx + 2, 4, hair[1])
			Raster.line(img, cx - 2, cx + sweep, 5, hair[1])
			Raster.px(img, cx - 1, 0, hair[4]); Raster.line(img, cx - 2, cx - 1, 1, hair[3])
			Raster.px(img, cx + 2, 3, hair[0])
		"buzzcut":
			_draw_buzzcut32(img, sel, hair, anatomy)
		"flattop":
			_draw_flattop32(img, hair, cx)
		"messy":
			_draw_textured_short32(img, sel, hair, anatomy, sweep, true)
		"spiky":
			_draw_spiky32(img, sel, hair, anatomy)
		"quiff":
			_draw_quiff32(img, sel, hair, anatomy, sweep)
		"afro":
			_draw_afro32(img, hair, cx)
		"curly":
			_draw_curly32(img, hair, cx)
		"straight", "medium", "long", "bob":
			_draw_long_front32(img, sel, hair, anatomy, sweep, style)
		"ponytail", "pigtails", "bun":
			_draw_pulled32(img, sel, hair, anatomy, sweep)
		"mullet":
			_draw_textured_short32(img, sel, hair, anatomy, sweep, false)
			Raster.vline(img, cx - sweep * 6, 7, 12, hair[1])
		"parted":
			_draw_short_cap32(img, sel, hair, anatomy, sweep)
			Raster.px(img, cx + sweep, 2, hair[0])
			Raster.segment(img, Vector2i(cx + sweep, 3), Vector2i(cx + sweep * 5, 6), 0, hair[0])
			Raster.line(img, cx - sweep * 4, cx - sweep, 3, hair[3])
		_:
			_draw_short_cap32(img, sel, hair, anatomy, sweep)


static func _draw_short_cap32(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary, sweep: int) -> void:
	var cx := int(anatomy["head_x"])
	for y in range(2, 6):
		var span := _face_span(clampi(y + 1, 3, 15), sel, anatomy)
		Raster.line(img, span.x, span.y, y, hair[2])
		Raster.line(img, span.x + 1, cx - 1, y, hair[3 if y <= 3 else 2])
		Raster.line(img, cx + 2, span.y, y, hair[1])
		Raster.px(img, span.y, y, hair[0])
	Raster.line(img, cx - 5, cx + sweep, 5, hair[2])
	Raster.line(img, cx - 3, cx + sweep * 3, 6, hair[1])


static func _draw_buzzcut32(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary) -> void:
	var cx := int(anatomy["head_x"])
	for y in range(3, 6):
		var span := _face_span(y + 1, sel, anatomy)
		Raster.line(img, span.x + int(y == 3), span.y - int(y == 3), y, hair[1])
		Raster.line(img, span.x + 2, cx, y, hair[3])
		Raster.px(img, span.y - int(y == 3), y, hair[0])


static func _draw_flattop32(img: Image, hair: Array[Color], cx: int) -> void:
	Raster.line(img, cx - 5, cx + 5, 1, hair[3])
	for y in range(2, 6):
		Raster.line(img, cx - 6, cx + 6, y, hair[2])
		Raster.px(img, cx - 5, y, hair[4]); Raster.px(img, cx + 6, y, hair[0])
	Raster.line(img, cx - 5, cx + 4, 5, hair[1])


static func _draw_textured_short32(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary, sweep: int, messy: bool) -> void:
	_draw_short_cap32(img, sel, hair, anatomy, sweep)
	var cx := int(anatomy["head_x"])
	for p: Vector2i in [Vector2i(-4, 1), Vector2i(-1, 0), Vector2i(2, 1)]:
		Raster.px(img, cx + p.x, p.y, hair[2]); Raster.px(img, cx + p.x, p.y + 1, hair[1])
	Raster.px(img, cx - 3, 2, hair[4])
	if messy:
		Raster.px(img, cx + 5 * sweep, 2, hair[2]); Raster.px(img, cx + 4 * sweep, 3, hair[1])
		Raster.px(img, cx - 5, 7, hair[2]); Raster.px(img, cx + sweep * 4, 7, hair[1])


static func _draw_spiky32(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary) -> void:
	var cx := int(anatomy["head_x"])
	for y in range(3, 6):
		var span := _face_span(y, sel, anatomy)
		Raster.line(img, span.x, span.y, y, hair[2])
	for ox in [-5, -2, 2, 5]:
		Raster.px(img, cx + ox, 0 if absi(ox) == 2 else 1, hair[2])
		Raster.px(img, cx + ox, 2, hair[2]); Raster.px(img, cx + ox + signi(ox), 2, hair[1])
	Raster.line(img, cx - 4, cx + 4, 4, hair[3])


static func _draw_quiff32(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary, sweep: int) -> void:
	_draw_short_cap32(img, sel, hair, anatomy, sweep)
	var cx := int(anatomy["head_x"])
	var qx := cx + sweep * 3
	Raster.rect(img, qx - 2, 0, 5, 3, hair[2])
	Raster.line(img, qx - 1, qx + 1, 0, hair[3]); Raster.px(img, qx + 2, 2, hair[0])


static func _draw_afro32(img: Image, hair: Array[Color], cx: int) -> void:
	var halves := [5, 7, 8, 9, 9, 9, 8, 7]
	for y in halves.size():
		var half: int = halves[y]
		Raster.line(img, cx - half, cx + half, y, hair[2])
		Raster.px(img, cx - half + 1, y, hair[3]); Raster.px(img, cx + half, y, hair[0])
	for p: Vector2i in [Vector2i(-5, 1), Vector2i(0, 0), Vector2i(5, 2),
		Vector2i(-8, 4), Vector2i(8, 5), Vector2i(-6, 7)]:
		Raster.px(img, cx + p.x, p.y, hair[1])


static func _draw_curly32(img: Image, hair: Array[Color], cx: int) -> void:
	var halves := [3, 6, 7, 8, 8, 7, 7, 6]
	for y in halves.size():
		var half: int = halves[y]
		Raster.line(img, cx - half, cx + half, y, hair[2])
		Raster.px(img, cx - half, y, hair[3]); Raster.px(img, cx + half, y, hair[0])
	for p: Vector2i in [Vector2i(-4, 1), Vector2i(1, 0), Vector2i(5, 2),
		Vector2i(-7, 4), Vector2i(7, 5), Vector2i(-5, 7), Vector2i(4, 6)]:
		Raster.rect(img, cx + p.x, p.y, 2, 2, hair[1 if p.x > 0 else 3])


static func _draw_pulled32(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary, sweep: int) -> void:
	var cx := int(anatomy["head_x"])
	for y in range(2, 6):
		var span := _face_span(y + 1, sel, anatomy)
		Raster.line(img, span.x + int(y == 2), span.y - int(y == 2), y, hair[2])
		Raster.line(img, cx - 4 * sweep, cx + 2 * sweep, y, hair[3])
		Raster.px(img, span.y, y, hair[0])
	Raster.line(img, cx - 4, cx + 4, 5, hair[1])


static func _draw_long_front32(img: Image, sel: Dictionary, hair: Array[Color],
		anatomy: Dictionary, sweep: int, style: String) -> void:
	_draw_short_cap32(img, sel, hair, anatomy, sweep)
	var cx := int(anatomy["head_x"])
	var bottom := 12
	if style == "medium": bottom = 14
	elif style == "straight": bottom = 16
	elif style == "long": bottom = 18
	Raster.vline(img, cx - 6, 6, bottom, hair[3]); Raster.vline(img, cx - 7, 7, bottom - 1, hair[2])
	Raster.vline(img, cx + 6, 6, bottom + 1, hair[1]); Raster.vline(img, cx + 7, 7, bottom, hair[0])
	if style == "bob":
		Raster.line(img, cx - 7, cx - 5, bottom, hair[2]); Raster.line(img, cx + 5, cx + 7, bottom + 1, hair[1])
	elif style == "straight":
		Raster.line(img, cx - 6, cx + 3, 6, hair[3])
	elif style == "long":
		Raster.px(img, cx - 6, bottom + 1, hair[4]); Raster.px(img, cx + 6, bottom + 2, hair[0])
