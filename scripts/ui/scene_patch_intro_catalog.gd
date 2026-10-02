extends RefCounted
## Zustandsloser Daten- und Formatierungsbaustein fuer den BYTEWERK-Composer.
## Die App behaelt Ablauf und Eingaben; dieser Baustein normalisiert nur die
## datengetriebenen Optionen und stellt robuste Fallbacks bereit.

const FALLBACK_HANDLES := ["NIBBLE", "PHOSPHOR", "ZERO-X", "NOVA", "SIDEBAND", "KERNEL-9"]
const FALLBACK_LOGOS := [
	{"id": "slab", "name": "PIXEL-SLAB"},
	{"id": "chrome", "name": "CHROM"},
	{"id": "outline", "name": "KONTUR"},
	{"id": "neon", "name": "NEON"},
]
const FALLBACK_PALETTES := [
	{"id": "night_copper", "name": "NACHTKUPFER", "colors": ["#07111f", "#173a56", "#ef7d42", "#ffe16b", "#eef7f2"]},
	{"id": "violet_ice", "name": "VIOLETT-EIS", "colors": ["#100d25", "#42275f", "#9d5bd2", "#57d5e8", "#f1f6e8"]},
	{"id": "acid_sunset", "name": "ACID-SUNSET", "colors": ["#101b1b", "#2b6f67", "#d7e34d", "#f07838", "#fff3ba"]},
	{"id": "steel_blue", "name": "STAHLBLAU", "colors": ["#07131d", "#1e5268", "#55a8bb", "#bbcbd0", "#ffffff"]},
	{"id": "red_signal", "name": "ROTSIGNAL", "colors": ["#130b12", "#55182b", "#d54245", "#f49b55", "#ffe6a2"]},
]
const FALLBACK_EFFECTS := [
	{"id": "copperbars", "name": "COPPERBARS"},
	{"id": "starfield", "name": "STERNFELD"},
	{"id": "vectorgrid", "name": "VEKTORNETZ"},
	{"id": "bobs", "name": "BOBS"},
	{"id": "rasterlogo", "name": "RASTERLOGO"},
	{"id": "sine_scroller", "name": "SINUS-SCROLL"},
]
const FALLBACK_SCROLLERS := [
	{"id": "signal", "text": "*** {HANDLE} PRESENTS A FRESH P-8 RELEASE *** GREETINGS TO ALL NIGHT OWLS ***"},
	{"id": "midnight", "text": "MIDNIGHT TRANSFER COMPLETE — {HANDLE} SENDS RESPECT ACROSS THE LINES"},
	{"id": "clean", "text": "TESTED THREE TIMES · PACKED WITH CARE · RELEASED BY {HANDLE}"},
	{"id": "schoolyard", "text": "ONE DISK · MANY STORIES · {HANDLE} KEEPS THE SIGNAL MOVING"},
]


static func sanitize_handle(value: String) -> String:
	return HandleRules.sanitize(value)


static func normalized_options(raw) -> Dictionary:
	var options: Dictionary = raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}
	if option_array(options, "logos").is_empty():
		options["logos"] = FALLBACK_LOGOS.duplicate(true)
	if option_array(options, "palettes").is_empty():
		options["palettes"] = FALLBACK_PALETTES.duplicate(true)
	if option_array(options, "effects").is_empty():
		options["effects"] = FALLBACK_EFFECTS.duplicate(true)
	if scroller_options(options).is_empty():
		options["scrollers"] = FALLBACK_SCROLLERS.duplicate(true)
	return options


static func option_array(options: Dictionary, key: String) -> Array:
	var value = options.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


static func scroller_options(options: Dictionary) -> Array:
	var values := option_array(options, "scrollers")
	return values if not values.is_empty() else option_array(options, "scroller_texts")


static func option_id(value, fallback: String) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return str(value.get("id", value.get("key", fallback)))
	return str(value) if str(value) != "" else fallback


static func option_name(value) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		return str(value.get("name", value.get("label", value.get("id", "OPTION")))).to_upper()
	return str(value).to_upper()


static func wrap_index(value: int, count: int) -> int:
	return posmod(value, count) if count > 0 else 0


static func selected_option(values: Array, index: int, fallback: Dictionary) -> Dictionary:
	if values.is_empty():
		return fallback.duplicate(true)
	var value = values[clampi(index, 0, values.size() - 1)]
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {"id": str(value), "name": str(value)}


static func format_scroller(option: Dictionary, handle: String, presenting: String, title: String, year: String) -> String:
	var value := str(option.get("text", option.get("template", option.get("name", "{HANDLE} PRESENTS"))))
	for token in ["{HANDLE}", "%HANDLE%", "<HANDLE>"]:
		value = value.replace(token, handle)
	return value.replace("{PRESENTING}", presenting).replace("{TITLE}", title).replace("{YEAR}", year)


static func palette_colors(palette: Dictionary, fallback: Array[Color]) -> Array[Color]:
	var out: Array[Color] = []
	var raw = palette.get("colors", [])
	if typeof(raw) == TYPE_ARRAY:
		for value in raw:
			out.append(value if typeof(value) == TYPE_COLOR else Color.from_string(str(value), fallback.back()))
	while out.size() < 5:
		out.append(fallback[out.size()])
	return out
const HandleRules := preload("res://scripts/scene/scene_handle_rules.gd")
