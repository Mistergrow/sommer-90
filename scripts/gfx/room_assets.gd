class_name RoomAssets
## RoomAssets — Asset-/Material-/Config-Auflösung des RoomCompositors (statisch,
## selbst-enthaltend): findet Layer-PNGs (höchste Version), lädt Texturen mit
## Direkt-Import-Fallback, löst das Basisbild je Jahr auf, baut Material-
## Varianten aus data/material_presets.json und liefert die weiche Schatten-
## Ellipse. Aus room_compositor.gd ausgelagert (Zeilen-Budget).
## RoomCompositor hält dünne Wrapper (config/find_asset/…), damit die bisherige
## öffentliche API (RoomCompositor.find_asset, comp.config() …) unverändert bleibt.

const CONFIG_PATH := "res://data/room_anchors.json"
const LAYER_DIR := "res://assets/backgrounds/layers/"
const MASK_DIR := "res://assets/masks/"
const MAX_VERSION := 9
const MATERIAL_SHADER := "res://shaders/material_variants.gdshader"
const MATERIAL_PRESETS_PATH := "res://data/material_presets.json"

static var _config: Dictionary = {}
static var _material_presets: Dictionary = {}
static var _shadow_tex: ImageTexture = null


static func clear_runtime_cache() -> void:
	_shadow_tex = null


static func config() -> Dictionary:
	if _config.is_empty():
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_config = parsed
			else:
				push_warning("RoomAssets: %s ist ungueltig" % CONFIG_PATH)
	return _config


## Höchste vorhandene Version eines Asset-Stamms ("HW_AMIGA500_BODY" →
## ".../HW_AMIGA500_BODY_V03.png"), "" wenn keine Datei existiert.
static func find_asset(asset_base: String) -> String:
	# Story-/Questprops dürfen in einem eigenen Ordner liegen; klassische
	# Geräte-IDs bleiben weiterhin über den versionierten Layer-Ordner aufgelöst.
	if asset_base.begins_with("res://") and asset_exists(asset_base):
		return asset_base
	for version in range(MAX_VERSION, 0, -1):
		var path := "%s%s_V%02d.png" % [LAYER_DIR, asset_base, version]
		if asset_exists(path):
			return path
	var plain := "%s%s.png" % [LAYER_DIR, asset_base]
	if asset_exists(plain):
		return plain
	return ""


## Auch Dateien finden, die der Editor noch nicht gescannt/importiert hat
## (Assets werden extern in den Projektordner kopiert).
static func asset_exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## Textur laden mit Fallback auf Direkt-Import von Platte, falls der
## Editor die Datei noch nicht importiert hat (sonst bliebe der Layer leer).
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## Basisbild für ein Jahr auflösen (bestes Jahr <= Spieljahr gewinnt; existiert
## keines, das NÄCHSTE verfügbare Jahr aufwärts — Kanon startet 1990, das
## Master-Artwork kann aber z. B. als _1992 benannt sein).
static func find_base(year: int) -> String:
	for pattern in config().get("base_patterns", []):
		if "{year}" in pattern:
			for y in range(year, 1989, -1):
				var path := find_asset(pattern.replace("{year}", str(y)))
				if path != "":
					return path
			for y in range(year + 1, 2001):
				var path := find_asset(pattern.replace("{year}", str(y)))
				if path != "":
					return path
		else:
			var path := find_asset(pattern)
			if path != "":
				return path
	return ""


## Gibt es überhaupt ein Basisbild?
static func base_available(year: int) -> bool:
	return find_base(year) != ""


## Weiche Schatten-Ellipse (einmal prozedural erzeugt, überall wiederverwendet).
static func shadow_texture() -> ImageTexture:
	if _shadow_tex != null:
		return _shadow_tex
	var img := Image.create(160, 80, false, Image.FORMAT_RGBA8)
	for y in 80:
		for x in 160:
			var d := Vector2((x - 79.5) / 78.0, (y - 39.5) / 38.0).length()
			# dunkler Kern, weicher Rand — erdet das Objekt sichtbar auf dem Tisch
			var alpha := pow(clampf(1.0 - d, 0.0, 1.0), 1.5) * 1.0
			img.set_pixel(x, y, Color(0.04, 0.03, 0.02, alpha))
	_shadow_tex = ImageTexture.create_from_image(img)
	return _shadow_tex


## ShaderMaterial aus Preset (data/material_presets.json) + Overrides bauen.
## Maske: assets/masks/<ASSET>_MASK.png (R=Plastik G=Metall B=Papier).
static func make_material(cfg: Dictionary, texture_path: String) -> ShaderMaterial:
	if _material_presets.is_empty():
		var file := FileAccess.open(MATERIAL_PRESETS_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			var presets: Variant = (parsed as Dictionary).get("presets", {}) if parsed is Dictionary else null
			if presets is Dictionary:
				_material_presets = presets
			else:
				push_warning("RoomAssets: %s ist ungueltig" % MATERIAL_PRESETS_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = load(MATERIAL_SHADER)
	var params: Dictionary = _material_presets.get(str(cfg.get("preset", "FactoryNew")), {}).duplicate()
	for key in cfg:
		if key in ["preset", "plastic_color"]:
			continue
		params[key] = cfg[key]
	for key in params:
		mat.set_shader_parameter(key, params[key])
	if cfg.has("plastic_color"):
		var c: Array = cfg["plastic_color"]
		mat.set_shader_parameter("plastic_color", Color(c[0], c[1], c[2]))
		mat.set_shader_parameter("recolor_strength", 1.0)
	else:
		mat.set_shader_parameter("recolor_strength", 0.0)  # Originalfarbe behalten
	var mask_path := MASK_DIR + texture_path.get_file().get_basename() + "_MASK.png"
	if asset_exists(mask_path):
		mat.set_shader_parameter("mask_tex", load_texture(mask_path))
	return mat
