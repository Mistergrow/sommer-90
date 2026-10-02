extends RefCounted
## Gemeinsame semantische Farbquelle. Die unterschiedlichen Rampenrhythmen von
## Ganzkörperfigur und Detailporträt bleiben bewusst erhalten.

const DENIM := Color8(55, 73, 108)
const FIGURE_SKIN := {
	"pale": Color8(229, 190, 158), "beige": Color8(216, 166, 126),
	"sand": Color8(196, 140, 101), "tan": Color8(169, 108, 76),
	"brown": Color8(117, 73, 56),
}
const FIGURE_HAIR := {
	"black": Color8(47, 43, 50), "brown": Color8(91, 62, 44),
	"auburn": Color8(121, 55, 45), "ginger": Color8(180, 75, 42),
	"blond": Color8(194, 154, 76), "grey": Color8(124, 124, 130),
	"white": Color8(201, 198, 190), "platinum": Color8(216, 205, 173),
	"red": Color8(177, 48, 52), "blue": Color8(47, 78, 151),
	"pink": Color8(178, 68, 121), "green": Color8(54, 119, 72),
	"teal": Color8(40, 121, 125),
}
const FIGURE_CLOTH := {
	"teal": Color8(42, 126, 133), "red": Color8(172, 54, 56),
	"blue": Color8(57, 89, 153), "green": Color8(63, 122, 70),
	"orange": Color8(190, 102, 46), "violet": Color8(113, 73, 144),
	"mustard": Color8(174, 137, 45),
}


static func figure_base(group: String, key: String, fallback: Color) -> Color:
	var table: Dictionary = {
		"skin": FIGURE_SKIN, "hair": FIGURE_HAIR, "cloth": FIGURE_CLOTH,
	}.get(group, {})
	var value: Variant = table.get(key.to_lower(), fallback)
	return value if value is Color else fallback


static func figure_ramp(base: Color) -> Array[Color]:
	return [
		base.darkened(0.43), base.darkened(0.24), base,
		base.lightened(0.18), base.lightened(0.33),
	]


static func figure_pants(selection: Dictionary, cloth_key: String) -> Color:
	var shirt := str(selection.get("shirt", "tee"))
	if shirt == "track":
		return figure_base("cloth", cloth_key, DENIM).darkened(0.22)
	if shirt in ["overall", "denim"] \
			or str(selection.get("jacket", "")) == "denim":
		return DENIM
	return [DENIM, Color8(61, 57, 77), Color8(58, 66, 68)][
		posmod(cloth_key.hash(), 3)]


static func figure_iris(name: String) -> Color:
	match name:
		"blue": return Color8(67, 107, 153)
		"green": return Color8(67, 119, 75)
		"grey": return Color8(108, 113, 122)
		_: return Color8(104, 66, 42)


static func portrait_skin(name: String) -> Array[Color]:
	var base: Color
	match name:
		"pale": base = Color("e8c2ad")
		"sand": base = Color("d39b72")
		"tan": base = Color("b87855")
		"brown": base = Color("81543d")
		_: base = Color("dcb18b")
	return [base.lightened(0.19), base.lightened(0.08), base,
		base.darkened(0.17), base.darkened(0.32)]


static func portrait_hair(selection: Dictionary) -> Array[Color]:
	var base: Color
	match str(selection.get("hair_color", "brown")):
		"black": base = Color("292a33")
		"grey": base = Color("87868b")
		"white": base = Color("c8c5bd")
		"blond": base = Color("c99c47")
		"platinum": base = Color("d8cdae")
		"ginger": base = Color("ad4d28")
		"auburn": base = Color("753726")
		"red": base = Color("bb3039")
		"blue": base = Color("315bb2")
		"pink": base = Color("bb4d81")
		"green": base = Color("397c47")
		"teal": base = Color("2f777b")
		_: base = Color("68432e")
	base = base.lerp(Color("aaa9aa"),
		clampf(float(selection.get("grey_t", 0.0)), 0.0, 1.0))
	return [base.lightened(0.28), base.lightened(0.13), base,
		base.darkened(0.22), base.darkened(0.40)]


static func portrait_cloth(name: String) -> Array[Color]:
	var base: Color
	match name:
		"red": base = Color("9e3540")
		"blue": base = Color("355a9a")
		"green": base = Color("397348")
		"orange": base = Color("b7652c")
		"violet": base = Color("6c477d")
		"mustard": base = Color("ad8431")
		_: base = Color("32777b")
	return [base.lightened(0.20), base.lightened(0.08), base,
		base.darkened(0.19), base.darkened(0.34)]


## Latzhose ist ein eigenes Material und keine dunklere Variante der gewaehlten
## Shirtfarbe.  Beide Avatar-Renderer nutzen dadurch dieselbe Denim-Identitaet:
## warmes Indigo, klare Nahtlichter und genug Abstand zu Gruen/Tuerkis.
static func portrait_denim() -> Array[Color]:
	var base := Color8(55, 73, 108)
	return [base.lightened(0.24), base.lightened(0.11), base,
		base.darkened(0.20), base.darkened(0.38)]


static func portrait_iris(name: String) -> Color:
	match name:
		"blue": return Color("4d83b7")
		"green": return Color("4f8052")
		"grey": return Color("747b83")
		_: return Color("704a2d")
