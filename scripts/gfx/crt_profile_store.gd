class_name CrtProfileStore
extends RefCounted
## Single Source fuer den CRT-Game-Editor und den Vollbildshader in main.gd.

const PATH := "res://data/crt_game_profiles.json"
## Eine globale Post-Process-Kruemmung verschiebt nur das gezeichnete Bild;
## Godots Control-Hitboxen und der native Mauszeiger bleiben unverzerrt. Bei
## interaktiven Monitoransichten muessen diese Parameter deshalb neutral sein,
## sonst liegt besonders ein sichtbares Schliessen-Gadget am Bildrand neben
## seiner echten Klickflaeche. Die analogen Signalparameter bleiben erhalten.
const INTERACTIVE_GEOMETRY_PARAMETERS: PackedStringArray = [
	"curvature", "pincushion", "overscan", "rotation", "vertical_hold",
]
const PARAMETERS := [
	{"id": "curvature", "name": "RÖHRENKRÜMMUNG", "min": 0.0, "max": 0.30, "step": 0.001},
	{"id": "pincushion", "name": "KISSENVERZERRUNG", "min": -0.12, "max": 0.12, "step": 0.001},
	{"id": "overscan", "name": "OVERSCAN / BILDRAND", "min": 0.0, "max": 0.12, "step": 0.001},
	{"id": "rotation", "name": "BILDRÖHREN-ROTATION", "min": -0.025, "max": 0.025, "step": 0.0005},
	{"id": "vertical_hold", "name": "VERTIKALER HALT", "min": -0.04, "max": 0.04, "step": 0.0005},
	{"id": "scanline_strength", "name": "SCANLINES", "min": 0.0, "max": 1.0, "step": 0.01},
	{"id": "interlace_strength", "name": "INTERLACE-FELD", "min": 0.0, "max": 0.50, "step": 0.01},
	{"id": "vignette_strength", "name": "VIGNETTE", "min": 0.0, "max": 1.0, "step": 0.01},
	{"id": "rgb_mask_strength", "name": "RGB-LOCHMASKE", "min": 0.0, "max": 1.0, "step": 0.01},
	{"id": "mask_pitch", "name": "LOCHMASKEN-TEILUNG", "min": 120.0, "max": 720.0, "step": 1.0},
	{"id": "flicker_strength", "name": "50-HZ-FLACKERN", "min": 0.0, "max": 0.20, "step": 0.001},
	{"id": "aberration", "name": "FARBSAUM / KONVERGENZ", "min": 0.0, "max": 0.004, "step": 0.00005},
	{"id": "vertical_aberration", "name": "VERTIKALE KONVERGENZ", "min": 0.0, "max": 0.004, "step": 0.00005},
	{"id": "color_bleed", "name": "CHROMA-BLEED", "min": 0.0, "max": 0.01, "step": 0.00005},
	{"id": "jitter", "name": "SIGNAL-ZITTERN", "min": 0.0, "max": 0.004, "step": 0.00005},
	{"id": "noise_strength", "name": "HF-SIGNALRAUSCHEN", "min": 0.0, "max": 0.20, "step": 0.001},
	{"id": "hum_bar_strength", "name": "NETZBRUMM-BAND", "min": 0.0, "max": 0.30, "step": 0.001},
	{"id": "hum_bar_speed", "name": "NETZBRUMM-TEMPO", "min": 0.0, "max": 2.0, "step": 0.01},
	{"id": "roll_speed", "name": "ROLLBAND-TEMPO", "min": 0.0, "max": 1.0, "step": 0.01},
	{"id": "roll_width", "name": "ROLLBAND-BREITE", "min": 0.01, "max": 0.50, "step": 0.01},
	{"id": "roll_strength", "name": "ROLLBAND-STÄRKE", "min": 0.0, "max": 0.60, "step": 0.01},
	{"id": "bloom", "name": "PHOSPHOR-BLOOM", "min": 0.0, "max": 0.60, "step": 0.01},
	{"id": "ghosting", "name": "PHOSPHOR-GEISTERBILD", "min": 0.0, "max": 0.40, "step": 0.01},
	{"id": "sharpness", "name": "BEAM-SCHÄRFE", "min": 0.0, "max": 1.0, "step": 0.01},
	{"id": "saturation", "name": "FARBSÄTTIGUNG", "min": 0.0, "max": 1.50, "step": 0.01},
	{"id": "gamma", "name": "PHOSPHOR-GAMMA", "min": 0.60, "max": 1.60, "step": 0.01},
	{"id": "black_level", "name": "SCHWARZWERT", "min": 0.0, "max": 0.20, "step": 0.001},
	{"id": "white_level", "name": "WEISSPEGEL", "min": 0.80, "max": 1.40, "step": 0.01},
	{"id": "text_boost", "name": "TEXT / KONTRAST", "min": 0.0, "max": 0.60, "step": 0.01},
	{"id": "corner_radius", "name": "RÖHRENRUNDUNG", "min": 0.0, "max": 0.15, "step": 0.001},
	{"id": "edge_softness", "name": "GLASRAND-WEICHE", "min": 0.001, "max": 0.05, "step": 0.001},
	{"id": "reflection", "name": "GLASREFLEXION", "min": 0.0, "max": 0.20, "step": 0.001},
]

static var _document: Dictionary = {}


static func reload() -> void:
	_document = {}


static func document() -> Dictionary:
	if not _document.is_empty():
		return _document
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_document = parsed
	if _document.is_empty():
		_document = {"schema": 1, "defaults": {}, "levels": []}
	return _document


static func levels() -> Array:
	return document().get("levels", [])


static func level_index(id: String) -> int:
	var list := levels()
	for index in list.size():
		if str(list[index].get("id", "")) == id:
			return index
	return 0


static func has_level(id: String) -> bool:
	if id == "default":
		return true
	for definition: Dictionary in levels():
		if str(definition.get("id", "")) == id:
			return true
	return false


static func level_name(id: String) -> String:
	var list := levels()
	for definition: Dictionary in list:
		if str(definition.get("id", "")) == id:
			return str(definition.get("name", id.to_upper()))
	return id.to_upper()


static func params_for(id: String) -> Dictionary:
	var result: Dictionary = document().get("defaults", {}).duplicate(true)
	for definition: Dictionary in levels():
		if str(definition.get("id", "")) == id:
			result.merge(definition.get("profile", {}), true)
			break
	return result


## Laufzeitprofil fuer bedienbare CRT-Oberflaechen. Scanlines, Lochmaske,
## Konvergenz, Bloom, Nachleuchten, Rauschen und Glasreflex bleiben unangetastet;
## nur die nicht hit-testbare Bildverschiebung wird entfernt. Der CRT-Editor
## nutzt weiterhin params_for() und zeigt damit die volle analoge Geometrie.
static func interactive_params_for(id: String) -> Dictionary:
	var result := params_for(id)
	for key: String in INTERACTIVE_GEOMETRY_PARAMETERS:
		result[key] = 0.0
	# Eine abgerundete Vollbildmaske kann kleine Eck-Gadgets zwar nicht
	# verschieben, aber teilweise verdecken. In einer bedienbaren Ansicht bleibt
	# der Rand deshalb voll sichtbar; Vignette und Reflexion erzeugen weiterhin
	# den Eindruck von Glas.
	result["corner_radius"] = 0.0
	result["edge_softness"] = 0.001
	return result


static func defaults() -> Dictionary:
	return document().get("defaults", {}).duplicate(true)


static func set_level_params(id: String, params: Dictionary) -> bool:
	var list := levels()
	for index in list.size():
		var definition: Dictionary = list[index]
		if str(definition.get("id", "")) != id:
			continue
		var clean := {}
		for spec: Dictionary in PARAMETERS:
			var key := str(spec["id"])
			clean[key] = snappedf(clampf(float(params.get(key, 0.0)),
				float(spec["min"]), float(spec["max"])), float(spec["step"]))
		definition["profile"] = clean
		list[index] = definition
		_document["levels"] = list
		return _write()
	return false


static func _write() -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_document, "  ", false))
	return true
