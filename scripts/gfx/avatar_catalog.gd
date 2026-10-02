class_name AvatarCatalog
## Gemeinsamer Datenvertrag fuer Spieler- und NPC-Portraets.
##
## Diese Klasse zeichnet nichts. Sie normalisiert gespeicherte Alt-Tokens,
## validiert die kuratierte Signature-DNA und erzeugt kanonische Runtime-Keys.
## PortraitGen, Figurenrenderer und Dialoganimation erhalten dadurch dieselben
## Namen und Werte, unabhaengig von Dictionary-Einfuegereihenfolge.

const SCHEMA_VERSION := 2
const PORTRAIT_SIZE := 128
const PORTRAIT_NATIVE_SIZE := 32
const PORTRAIT_SCALE := 4
const FIGURE_NATIVE_SIZE := Vector2i(32, 48)

const SKINS := ["beige", "sand", "tan", "pale", "brown"]
const HAIR_COLORS := ["brown", "black", "grey", "blond", "ginger", "auburn",
	"white", "platinum", "red", "blue", "pink", "green", "teal"]
const PERSONALITIES := ["teal", "red", "blue", "green", "orange", "violet", "mustard"]
const GENDERS := ["m", "f"]
const FACE_SHAPES := ["oval", "round", "square", "long", "heart"]
const EYE_TYPES := ["normal", "narrow", "wide", "droopy"]
const EYE_COLORS := ["brown", "blue", "green", "grey"]
const NOSE_TYPES := ["straight", "small", "wide", "long"]
const HAIR_STYLES := ["buzzcut", "short", "parted", "messy", "curly", "straight",
	"medium", "long", "ponytail", "mullet", "bob", "mohawk", "afro", "bun",
	"pigtails", "spiky", "quiff", "flattop", "bald"]
const BROW_TYPES := ["flat", "thick", "raised"]
const EAR_TYPES := ["plain", "big", "earring"]
const CLOTHING_STYLES := ["casual", "neat", "scene", "sporty", "artsy", "nerdy"]
const GLASSES := ["", "round", "square", "thick", "aviator", "cat", "half", "sunglasses"]
const BEARDS := ["", "stubble", "moustache", "goatee", "chin", "full", "sideburns",
	"soulpatch", "handlebar", "muttonchops", "longbeard"]
const HATS := ["", "cap", "cap_back", "beanie", "winter", "headband", "bandana",
	"bucket", "sunhat", "tophat", "fedora", "cowboy", "flatcap", "visor", "party",
	"crown", "santa", "helmet", "headphones"]
const EMOTIONS := ["neutral", "happy", "laughing", "sad", "angry", "surprised",
	"shocked", "thinking", "talking", "tired", "nervous", "proud"]
const VISEMES := ["rest", "mbp", "fv", "ai", "e", "ou", "l", "sch"]
const EYE_FRAMES := ["open", "half", "closed"]

## Pflichtfelder einer benannten Stammfigur. Optionale Accessoires bleiben
## optional, aber sobald sie gesetzt sind, muessen sie ebenfalls gueltig sein.
const SIGNATURE_FIELDS := [
	"schema_version", "skin", "hair", "age_base", "gender", "face_shape",
	"hair_style", "clothing_style", "eye_type", "eye_color", "nose", "brow",
	"ears", "personality", "eye_spacing", "eye_asymmetry", "nose_shift",
	"mouth_shift", "mouth_width", "hair_sweep",
]

const ENUMS := {
	"skin": SKINS,
	"hair": HAIR_COLORS,
	"gender": GENDERS,
	"face_shape": FACE_SHAPES,
	"hair_style": HAIR_STYLES,
	"clothing_style": CLOTHING_STYLES,
	"eye_type": EYE_TYPES,
	"eye_color": EYE_COLORS,
	"nose": NOSE_TYPES,
	"brow": BROW_TYPES,
	"ears": EAR_TYPES,
	"personality": PERSONALITIES,
	"glasses": GLASSES,
	"beard": BEARDS,
	"hat": HATS,
	"emotion": EMOTIONS,
	"viseme": VISEMES,
	"mouth_pose": VISEMES,
	"eye_frame": EYE_FRAMES,
}

const TOKEN_ALIASES := {
	"gender": {"male": "m", "man": "m", "boy": "m", "female": "f", "woman": "f", "girl": "f"},
	"eye_type": {"round": "normal", "standard": "normal"},
	"brow": {"normal": "flat", "arched": "raised"},
	"ears": {"normal": "plain", "standard": "plain"},
	"clothing_style": {"creative": "artsy", "artist": "artsy", "geek": "nerdy"},
	"beard": {"mustache": "moustache", "moustache": "moustache", "none": ""},
	"glasses": {"none": "", "no": ""},
	"hat": {"none": "", "no": ""},
	"emotion": {"laugh": "laughing", "surprise": "surprised", "shock": "shocked"},
	"viseme": {"closed": "mbp", "open": "ai", "round": "ou", "o": "ou",
		"u": "ou", "s": "sch", "ch": "sch", "silence": "rest", "idle": "rest"},
	"mouth_pose": {"closed": "mbp", "open": "ai", "round": "ou", "o": "ou",
		"u": "ou", "s": "sch", "ch": "sch", "silence": "rest", "idle": "rest"},
	"eye_frame": {"opened": "open", "blink": "closed", "shut": "closed"},
}


static func enum_values(field: String) -> Array:
	return (ENUMS.get(field, []) as Array).duplicate()


static func canonical_token(field: String, value: Variant) -> String:
	var token := str(value).strip_edges().to_lower()
	var aliases: Dictionary = TOKEN_ALIASES.get(field, {})
	return str(aliases.get(token, token))


## portrait + portrait_dna werden zu genau einer Runtime-Signatur. Das Original
## bleibt unveraendert, damit Manager-Aufrufer keine Stammdaten mutieren koennen.
static func signature_from_npc(npc: Dictionary) -> Dictionary:
	var signature: Dictionary = npc.get("portrait", {}).duplicate(true)
	for key: Variant in npc.get("portrait_dna", {}):
		signature[key] = npc["portrait_dna"][key]
	return canonical_signature(signature)


static func canonical_signature(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	if out.has("schema_version"):
		out["schema_version"] = int(out["schema_version"])
	for field: String in ENUMS:
		if out.has(field):
			out[field] = canonical_token(field, out[field])
	if out.has("age_base"):
		out["age_base"] = clampi(int(out["age_base"]), 8, 80)
	for field: String in ["eye_spacing", "eye_asymmetry", "nose_shift", "mouth_shift"]:
		if out.has(field):
			out[field] = clampi(int(out[field]), -1, 1)
	if out.has("mouth_width"):
		out["mouth_width"] = clampi(int(out["mouth_width"]), -2, 2)
	if out.has("hair_sweep"):
		out["hair_sweep"] = -1 if int(out["hair_sweep"]) < 0 else 1
	return out


## Laufzeitzustaende duerfen weitere, renderer-spezifische Keys behalten. Nur
## bekannte Vertragstokens und Zahlen werden normalisiert.
static func canonical_state(raw: Dictionary) -> Dictionary:
	var out := raw.duplicate(true)
	for field: String in ["emotion", "viseme", "mouth_pose", "eye_frame"]:
		if out.has(field):
			out[field] = canonical_token(field, out[field])
	if out.has("year"):
		out["year"] = int(out["year"])
	if out.has("gaze"):
		out["gaze"] = clampi(int(out["gaze"]), -1, 1)
	return out


static func canonical_frame(raw: Dictionary) -> Dictionary:
	var out := canonical_state(raw)
	if out.has("viseme") and not out.has("mouth_pose"):
		out["mouth_pose"] = out["viseme"]
	if out.has("blink") and bool(out["blink"]):
		out["eye_frame"] = "closed"
	if out.has("eye_left"):
		out["eye_left"] = canonical_token("eye_frame", out["eye_left"])
	if out.has("eye_right"):
		out["eye_right"] = canonical_token("eye_frame", out["eye_right"])
	return out


static func merged_hints(signature: Dictionary, state: Dictionary = {}) -> Dictionary:
	var out := canonical_signature(signature)
	var normalized_state := canonical_state(state)
	for key: Variant in normalized_state:
		out[key] = normalized_state[key]
	return out


static func validate_signature(signature: Dictionary) -> PackedStringArray:
	var spec := canonical_signature(signature)
	var errors := PackedStringArray()
	for field: String in SIGNATURE_FIELDS:
		if not spec.has(field):
			errors.append("Pflichtfeld fehlt: %s" % field)
	if int(spec.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("schema_version muss %d sein" % SCHEMA_VERSION)
	for field: String in ENUMS:
		if spec.has(field) and not spec[field] in ENUMS[field]:
			errors.append("Ungueltiges %s: %s" % [field, str(spec[field])])
	if signature.has("age_base") and (int(signature["age_base"]) < 8 or int(signature["age_base"]) > 80):
		errors.append("age_base ausserhalb 8..80")
	for field: String in ["eye_spacing", "eye_asymmetry", "nose_shift", "mouth_shift"]:
		if signature.has(field) and (int(signature[field]) < -1 or int(signature[field]) > 1):
			errors.append("%s ausserhalb -1..1" % field)
	if signature.has("mouth_width") and (int(signature["mouth_width"]) < -2 or int(signature["mouth_width"]) > 2):
		errors.append("mouth_width ausserhalb -2..2")
	if signature.has("hair_sweep") and int(signature["hair_sweep"]) not in [-1, 1]:
		errors.append("hair_sweep muss -1 oder 1 sein")
	return errors


## Stabil ueber Dictionary-Reihenfolgen hinweg. Der lesbare Praefix hilft bei
## Profiling/Fehlerberichten, der SHA-256-Teil bleibt kompakt.
static func state_key(id: String, signature: Dictionary, state: Dictionary = {}, frame: Dictionary = {}) -> String:
	var payload := {
		"frame": canonical_frame(frame),
		"signature": canonical_signature(signature),
		"state": canonical_state(state),
	}
	return "%s|v%d|%s" % [id, SCHEMA_VERSION, _canonical(payload).sha256_text()]


static func name_key(value: String) -> String:
	var key := value.strip_edges().to_lower()
	if key.begins_with("☎"):
		key = key.trim_prefix("☎").strip_edges()
	if key.ends_with(":"):
		key = key.left(-1).strip_edges()
	return key


static func _canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var keys: Array = dictionary.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			var parts := PackedStringArray()
			for key: Variant in keys:
				parts.append("%s:%s" % [JSON.stringify(str(key)), _canonical(dictionary[key])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for item: Variant in value:
				parts.append(_canonical(item))
			return "[" + ",".join(parts) + "]"
		_:
			return JSON.stringify(value)
