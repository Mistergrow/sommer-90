class_name AmigaVideoContract
extends RefCounted
## Gemeinsamer, datengetriebener Videovertrag fuer alle spielbaren Amiga-Disketten.
##
## Das ist keine allgemeine "Pixel-Art"-Plakette: Jedes Spiel wird gegen eine
## konkrete Amiga-Generation, einen echten logischen Videomodus und endliche
## Chip-RAM-nahe Zeichenbudgets geprueft. OCS, ECS und AGA teilen dieselbe API,
## besitzen aber sichtbar verschiedene Obergrenzen fuer Farben, Bitplanes,
## Copper, Blitter, Hardware-Sprites, Animation und Parallax.

const StefanCatalog := preload("res://scripts/games/stefan_game_catalog.gd")

enum Chipset {
	OCS,
	ECS,
	AGA,
}

enum VideoMode {
	LORES_320X200,
	PAL_320X256,
	WIDE_OVERSCAN_384X216,
}

const MODE_SIZES: Dictionary = {
	VideoMode.LORES_320X200: Vector2i(320, 200),
	VideoMode.PAL_320X256: Vector2i(320, 256),
	VideoMode.WIDE_OVERSCAN_384X216: Vector2i(384, 216),
}

# Harte Hardware-/Stilobergrenzen. Die Pixelbudgets sind absichtlich als
# "pro Frame" modelliert: Sie zwingen Laufzeitgrafik zu Tiles, Dirty-Rects und
# wiederverwendbaren Blitter-Objekten, ohne heutige Animationen auszubremsen.
const CHIPSET_LIMITS: Dictionary = {
	Chipset.OCS: {
		"name": "OCS",
		"color_registers": 32,
		"palette_source_colors": 4096,
		"max_indexed_colors": 32,
		"max_bitplanes": 5,
		"hardware_sprites": 8,
		"sprite_width": 16,
		"copper_instructions": 384,
		"blitter_pixels_per_frame": 64_000,
		"parallax_layers": 2,
		"animation_frames_per_actor": 6,
		"dual_playfield": true,
		"ham": "HAM6",
	},
	Chipset.ECS: {
		"name": "ECS",
		"color_registers": 32,
		"palette_source_colors": 4096,
		"max_indexed_colors": 64,
		"max_bitplanes": 6,
		"hardware_sprites": 8,
		"sprite_width": 16,
		"copper_instructions": 640,
		"blitter_pixels_per_frame": 88_000,
		"parallax_layers": 3,
		"animation_frames_per_actor": 8,
		"dual_playfield": true,
		"ham": "HAM6/EHB",
	},
	Chipset.AGA: {
		"name": "AGA",
		"color_registers": 256,
		"palette_source_colors": 16_777_216,
		"max_indexed_colors": 256,
		"max_bitplanes": 8,
		"hardware_sprites": 8,
		"sprite_width": 64,
		"copper_instructions": 1_024,
		"blitter_pixels_per_frame": 160_000,
		"parallax_layers": 5,
		"animation_frames_per_actor": 12,
		"dual_playfield": true,
		"ham": "HAM8",
	},
}

const BUILTIN_PROFILES: Dictionary = {
	"space_lemming_trouble": {
		"year": 1990,
		"chipset": Chipset.OCS,
		"video_mode": VideoMode.WIDE_OVERSCAN_384X216,
		"genre": "action_puzzle",
		"art_direction": "friendly_industrial_space",
	},
	"turbo_kart_deluxe": {
		"year": 1990,
		"chipset": Chipset.OCS,
		"video_mode": VideoMode.LORES_320X200,
		"genre": "racing",
		"art_direction": "flat_polygon_stunt_racing",
	},
	"code_red_protocol": {
		"year": 1990,
		"chipset": Chipset.OCS,
		"video_mode": VideoMode.PAL_320X256,
		"genre": "management",
		"art_direction": "serious_copper_gradient_strategy",
	},
	"wunderwerk_94": {
		"year": 1994,
		# Zielrechner A600, bewusst im vollständig kompatiblen OCS-Bildmodus.
		"chipset": Chipset.OCS,
		"video_mode": VideoMode.PAL_320X256,
		"genre": "amusement_park_management",
		"art_direction": "european_summer_festival_ocs_isometric",
	},
}


static func chipset_name(chipset: int) -> String:
	return str((CHIPSET_LIMITS.get(chipset, {}) as Dictionary).get("name", "INVALID"))


static func mode_name(video_mode: int) -> String:
	match video_mode:
		VideoMode.LORES_320X200:
			return "LORES 320x200"
		VideoMode.PAL_320X256:
			return "PAL 320x256"
		VideoMode.WIDE_OVERSCAN_384X216:
			return "WIDE OVERSCAN 384x216"
	return "INVALID"


static func logical_size(video_mode: int) -> Vector2i:
	return MODE_SIZES.get(video_mode, Vector2i.ZERO) as Vector2i


static func generation_for_year(year: int) -> int:
	if year <= 1992:
		return Chipset.OCS
	if year <= 1995:
		return Chipset.ECS
	return Chipset.AGA


static func _default_request(chipset: int) -> Dictionary:
	match chipset:
		Chipset.OCS:
			return {
				"bitplanes": 5,
				"indexed_colors": 32,
				"hardware_sprites": 6,
				"copper_instructions": 288,
				"blitter_pixels_per_frame": 52_000,
				"parallax_layers": 2,
				"animation_frames_per_actor": 6,
			}
		Chipset.ECS:
			return {
				"bitplanes": 6,
				"indexed_colors": 64,
				"hardware_sprites": 8,
				"copper_instructions": 512,
				"blitter_pixels_per_frame": 76_000,
				"parallax_layers": 3,
				"animation_frames_per_actor": 8,
			}
		Chipset.AGA:
			return {
				"bitplanes": 8,
				"indexed_colors": 128,
				"hardware_sprites": 8,
				"copper_instructions": 896,
				"blitter_pixels_per_frame": 132_000,
				"parallax_layers": 5,
				"animation_frames_per_actor": 12,
			}
	return {}


static func _profile(game_id: String, year: int, chipset: int, video_mode: int,
		genre: String, art_direction: String) -> Dictionary:
	return {
		"game_id": game_id,
		"year": year,
		"chipset": chipset,
		"chipset_name": chipset_name(chipset),
		"video_mode": video_mode,
		"video_mode_name": mode_name(video_mode),
		"logical_size": logical_size(video_mode),
		"genre": genre,
		"art_direction": art_direction,
		"render_request": _default_request(chipset),
		"pixel_grid": Vector2i(1, 1),
		"tile_grid": Vector2i(8, 8),
		"subpixel_world_rendering": false,
		"texture_filter": "nearest",
		"integer_output_scale": true,
		"crt_scope": "output_only",
	}


static func game_profile(game_id: String) -> Dictionary:
	if BUILTIN_PROFILES.has(game_id):
		var raw: Dictionary = BUILTIN_PROFILES[game_id]
		return _profile(
			game_id,
			int(raw.get("year", 1990)),
			int(raw.get("chipset", Chipset.OCS)),
			int(raw.get("video_mode", VideoMode.LORES_320X200)),
			str(raw.get("genre", "game")),
			str(raw.get("art_direction", "amiga")),
		)
	if not StefanCatalog.has(game_id):
		return {}
	var definition := StefanCatalog.game(game_id)
	var year := int(definition.get("year", 1991))
	return _profile(
		game_id,
		year,
		generation_for_year(year),
		VideoMode.LORES_320X200,
		str(definition.get("mode", "anthology")),
		str(definition.get("variant", "amiga_%d" % year)),
	)


static func registered_profiles() -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	var ids: Array[String] = []
	for raw_id: Variant in BUILTIN_PROFILES.keys():
		ids.append(str(raw_id))
	for id: String in StefanCatalog.ids():
		if id not in ids:
			ids.append(id)
	ids.sort()
	for id: String in ids:
		profiles.append(game_profile(id))
	return profiles


static func limits_for(profile_or_chipset: Variant) -> Dictionary:
	var chipset := -1
	if profile_or_chipset is Dictionary:
		chipset = int((profile_or_chipset as Dictionary).get("chipset", -1))
	else:
		chipset = int(profile_or_chipset)
	return (CHIPSET_LIMITS.get(chipset, {}) as Dictionary).duplicate(true)


static func validate_profile(profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var game_id := str(profile.get("game_id", ""))
	var chipset := int(profile.get("chipset", -1))
	var video_mode := int(profile.get("video_mode", -1))
	var expected_size := logical_size(video_mode)
	var request: Dictionary = profile.get("render_request", {})
	var limits := limits_for(chipset)
	if game_id.is_empty():
		errors.append("game_id fehlt")
	if limits.is_empty():
		errors.append("unbekannter Chipsatz")
	if expected_size == Vector2i.ZERO:
		errors.append("unbekannter Videomodus")
	elif profile.get("logical_size", Vector2i.ZERO) != expected_size:
		errors.append("logical_size passt nicht zu %s" % mode_name(video_mode))
	if str(profile.get("texture_filter", "")) != "nearest":
		errors.append("Texturfilter muss nearest sein")
	if not bool(profile.get("integer_output_scale", false)):
		errors.append("Ausgabeskalierung muss ganzzahlig sein")
	if bool(profile.get("subpixel_world_rendering", true)):
		errors.append("Weltkoordinaten muessen am logischen Pixelraster einrasten")
	if str(profile.get("crt_scope", "")) != "output_only":
		errors.append("CRT darf nur den fertigen Output bearbeiten")
	if not limits.is_empty():
		_check_budget(request, limits, "bitplanes", errors, "max_bitplanes")
		_check_budget(request, limits, "indexed_colors", errors, "max_indexed_colors")
		_check_budget(request, limits, "hardware_sprites", errors)
		_check_budget(request, limits, "copper_instructions", errors)
		_check_budget(request, limits, "blitter_pixels_per_frame", errors)
		_check_budget(request, limits, "parallax_layers", errors)
		_check_budget(request, limits, "animation_frames_per_actor", errors)
		if int(request.get("indexed_colors", 0)) < 16:
			warnings.append("Palette nutzt weniger als 16 Farben")
		if int(request.get("copper_instructions", 0)) == 0:
			warnings.append("Copper bleibt ungenutzt")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"profile": profile.duplicate(true),
		"limits": limits,
	}


static func _check_budget(request: Dictionary, limits: Dictionary, request_key: String,
		errors: Array[String], limit_key := "") -> void:
	var actual_limit_key := limit_key if not limit_key.is_empty() else request_key
	var used := int(request.get(request_key, -1))
	var available := int(limits.get(actual_limit_key, -1))
	if used < 0:
		errors.append("%s fehlt" % request_key)
	elif available < 0 or used > available:
		errors.append("%s: %d > %d" % [request_key, used, available])


static func validate_registered_games(expected_ids: Array[String] = []) -> Dictionary:
	var errors: Array[String] = []
	var profiles := registered_profiles()
	var seen: Dictionary = {}
	for profile: Dictionary in profiles:
		var id := str(profile.get("game_id", ""))
		if seen.has(id):
			errors.append("doppeltes Profil: %s" % id)
		seen[id] = true
		var result := validate_profile(profile)
		for error: String in result.get("errors", []):
			errors.append("%s: %s" % [id, error])
	for expected_id: String in expected_ids:
		if not seen.has(expected_id):
			errors.append("Profil fehlt: %s" % expected_id)
	for raw_id: Variant in seen.keys():
		var id := str(raw_id)
		if not expected_ids.is_empty() and id not in expected_ids:
			errors.append("verwaistes Profil: %s" % id)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"profile_count": profiles.size(),
	}


static func visual_generation_signature(chipset: int) -> Dictionary:
	var limits := limits_for(chipset)
	if limits.is_empty():
		return {}
	return {
		"label": str(limits.get("name", "")),
		"register_colors": int(limits.get("color_registers", 0)),
		"source_palette": int(limits.get("palette_source_colors", 0)),
		"bitplanes": int(limits.get("max_bitplanes", 0)),
		"copper": int(limits.get("copper_instructions", 0)),
		"blitter": int(limits.get("blitter_pixels_per_frame", 0)),
		"sprite_width": int(limits.get("sprite_width", 0)),
		"parallax": int(limits.get("parallax_layers", 0)),
		"animation": int(limits.get("animation_frames_per_actor", 0)),
	}


static func quantize_color(color: Color, profile_or_chipset: Variant) -> Color:
	var chipset := Chipset.OCS
	if profile_or_chipset is Dictionary:
		chipset = int((profile_or_chipset as Dictionary).get(
			"chipset", Chipset.OCS)) as Chipset
	else:
		chipset = int(profile_or_chipset) as Chipset
	# OCS/ECS schreiben RGB4 in die Farbregister, AGA RGB8. Das absichtliche
	# Quantisieren verhindert weiche "Fast-Pixel-Art"-Verlaeufe im Spielbild.
	var levels := 255.0 if chipset == Chipset.AGA else 15.0
	return Color(
		roundf(color.r * levels) / levels,
		roundf(color.g * levels) / levels,
		roundf(color.b * levels) / levels,
		roundf(color.a * 255.0) / 255.0,
	)


static func validate_palette(colors: Array[Color], profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var request: Dictionary = profile.get("render_request", {})
	var maximum := int(request.get("indexed_colors", 0))
	var unique: Dictionary = {}
	for color: Color in colors:
		var quantized := quantize_color(color, profile)
		if not color.is_equal_approx(quantized):
			errors.append("Farbe %s liegt nicht auf dem %s-Registerraster" % [
				color.to_html(), chipset_name(int(profile.get("chipset", -1)))])
		unique[quantized.to_html()] = true
	if unique.size() > maximum:
		errors.append("Palette nutzt %d statt maximal %d Farben" % [unique.size(), maximum])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"unique_colors": unique.size(),
		"maximum_colors": maximum,
	}


static func snap_point(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x), floori(point.y))


static func snap_rect(rect: Rect2) -> Rect2i:
	return Rect2i(
		floori(rect.position.x),
		floori(rect.position.y),
		maxi(0, ceili(rect.size.x)),
		maxi(0, ceili(rect.size.y)),
	)


static func validate_sprite_spec(spec: Dictionary, profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var limits := limits_for(profile)
	var hardware := bool(spec.get("hardware_sprite", false))
	var width := int(spec.get("width", 0))
	var height := int(spec.get("height", 0))
	var frames := int(spec.get("frames", 0))
	var colors := int(spec.get("colors", 0))
	var attached := bool(spec.get("attached", false))
	var slots := 2 if attached else 1
	if width <= 0 or height <= 0:
		errors.append("Spritegroesse muss positiv sein")
	if frames <= 0:
		errors.append("Sprite braucht mindestens einen Animationsframe")
	elif frames > int(limits.get("animation_frames_per_actor", 0)):
		errors.append("Animation nutzt %d statt maximal %d Frames" % [
			frames, int(limits.get("animation_frames_per_actor", 0))])
	if colors <= 0:
		errors.append("Spritepalette fehlt")
	elif hardware and colors > (16 if attached else 4):
		errors.append("Hardware-Sprite nutzt zu viele Farben")
	if hardware and width > int(limits.get("sprite_width", 0)):
		errors.append("Hardware-Sprite ist %d statt maximal %d Pixel breit" % [
			width, int(limits.get("sprite_width", 0))])
	if hardware and slots > int(limits.get("hardware_sprites", 0)):
		errors.append("Nicht genug Hardware-Spritekanaele")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"sprite_slots": slots,
		"blitter_object": not hardware,
	}


static func validate_copper_program(program: Array[Dictionary],
		profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var limits := limits_for(profile)
	var logical: Vector2i = profile.get("logical_size", Vector2i.ZERO)
	var max_instructions := int(limits.get("copper_instructions", 0))
	var max_registers := int(limits.get("color_registers", 0))
	if program.size() > max_instructions:
		errors.append("Copperliste nutzt %d statt maximal %d Instruktionen" % [
			program.size(), max_instructions])
	var previous_scanline := -1
	for instruction: Dictionary in program:
		var scanline := int(instruction.get("scanline", -1))
		var register := int(instruction.get("color_register", -1))
		if scanline < 0 or scanline >= logical.y:
			errors.append("Copper-Scanline %d liegt ausserhalb des Bildes" % scanline)
		if scanline < previous_scanline:
			errors.append("Copperliste ist nicht nach Rasterzeile sortiert")
		if register < 0 or register >= max_registers:
			errors.append("Farbregister %d existiert auf %s nicht" % [
				register, chipset_name(int(profile.get("chipset", -1)))])
		if instruction.has("color") \
				and not (instruction["color"] as Color).is_equal_approx(
					quantize_color(instruction["color"] as Color, profile)):
			errors.append("Copperfarbe liegt nicht auf dem Registerraster")
		previous_scanline = scanline
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"instructions": program.size(),
		"budget": max_instructions,
	}


static func copper_gradient(profile: Dictionary, color_register: int,
		top: int, bottom: int, start_color: Color, end_color: Color,
		steps: int) -> Array[Dictionary]:
	var program: Array[Dictionary] = []
	var safe_steps := maxi(1, steps)
	for index in safe_steps:
		var ratio := float(index) / float(maxi(1, safe_steps - 1))
		program.append({
			"scanline": clampi(
				roundi(lerpf(float(top), float(bottom), ratio)),
				top,
				bottom,
			),
			"color_register": color_register,
			"color": quantize_color(start_color.lerp(end_color, ratio), profile),
		})
	return program
