class_name AmigaDisplayPipeline
extends RefCounted
## Ausgabe-Pipeline fuer die Amiga-Videoprofile.
##
## Die Spielwelt bleibt ungefiltert auf ihrer logischen Aufloesung. Erst ein
## SubViewport wird ganzzahlig und per Nearest-Neighbor in die moderne
## Monitorflaeche gesetzt. Der optionale CRT-Look liegt ausschliesslich auf dem
## finalen TextureRect und veraendert weder Spielpixel noch Eingabekoordinaten.

const Contract := preload("res://scripts/games/amiga_video_contract.gd")
const CRT_OUTPUT_SHADER := preload("res://shaders/amiga_crt_output.gdshader")


static func compute_layout(container_size: Vector2, profile: Dictionary,
		allow_downscale := false) -> Dictionary:
	var validation := Contract.validate_profile(profile)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"errors": validation.get("errors", []),
			"scale": 0,
			"origin": Vector2.ZERO,
			"output_size": Vector2.ZERO,
		}
	var logical_i: Vector2i = profile.get("logical_size", Vector2i.ZERO)
	var logical := Vector2(logical_i)
	var available := minf(container_size.x / logical.x, container_size.y / logical.y)
	var scale := floori(available)
	if scale < 1:
		if not allow_downscale:
			return {
				"ok": false,
				"errors": ["Ausgabeflaeche ist kleiner als die logische Amiga-Aufloesung"],
				"scale": 0,
				"origin": Vector2.ZERO,
				"output_size": Vector2.ZERO,
			}
		# Nur fuer kleine Debug-/Editorvorschauen. Das eigentliche Spielprofil
		# bleibt integer; der Aufrufer erhaelt die Ausnahme explizit markiert.
		var downscale := maxf(0.01, available)
		var downscaled_size := (logical * downscale).floor()
		return {
			"ok": true,
			"integer": false,
			"debug_downscale": true,
			"scale": downscale,
			"origin": ((container_size - downscaled_size) * 0.5).floor(),
			"output_size": downscaled_size,
			"logical_size": logical,
		}
	var output_size := logical * float(scale)
	return {
		"ok": true,
		"integer": true,
		"debug_downscale": false,
		"scale": scale,
		"origin": ((container_size - output_size) * 0.5).floor(),
		"output_size": output_size,
		"logical_size": logical,
	}


## Gemeinsamer Layoutvertrag fuer Spiele, die auch in variablen Zimmermonitoren
## laufen. Integer-Skalierung gewinnt; nur ein zu kleiner oder nicht normierter
## Host erhaelt den expliziten proportionalen Nearest-Fallback.
static func compute_embedded_layout(container_size: Vector2, profile: Dictionary,
		logical_size: Vector2) -> Dictionary:
	var layout := compute_layout(container_size, profile, true)
	var output_size := Vector2(layout.get("output_size", Vector2.ZERO))
	if not bool(layout.get("ok", false)) \
			or minf(absf(output_size.x - container_size.x),
				absf(output_size.y - container_size.y)) > 1.0:
		var scale := maxf(0.01, minf(container_size.x / logical_size.x,
			container_size.y / logical_size.y))
		var origin := ((container_size - logical_size * scale) * 0.5).round()
		layout = {
			"ok": true,
			"integer": is_equal_approx(scale, floorf(scale)),
			"embedded_fallback": true,
			"scale": scale,
			"origin": origin,
			"output_size": logical_size * scale,
			"logical_size": logical_size,
		}
	return layout


## Aspect-fill ohne Stretching fuer vollflaechige Titel-/Missionsgrafik.
static func draw_cover(canvas: CanvasItem, texture: Texture2D, rect: Rect2) -> void:
	var source_size := texture.get_size()
	var target_ratio := rect.size.x / rect.size.y
	var source_ratio := source_size.x / source_size.y
	var source_rect := Rect2(Vector2.ZERO, source_size)
	if source_ratio > target_ratio:
		var width := source_size.y * target_ratio
		source_rect.position.x = (source_size.x - width) * 0.5
		source_rect.size.x = width
	else:
		var height := source_size.x / target_ratio
		source_rect.position.y = (source_size.y - height) * 0.5
		source_rect.size.y = height
	canvas.draw_texture_rect_region(texture, rect, source_rect)


static func logical_to_screen(logical_position: Vector2, layout: Dictionary) -> Vector2:
	return Vector2(layout.get("origin", Vector2.ZERO)) \
		+ logical_position * float(layout.get("scale", 1.0))


static func screen_to_logical(screen_position: Vector2, layout: Dictionary,
		snap_to_pixel := true) -> Vector2:
	var scale := maxf(0.0001, float(layout.get("scale", 1.0)))
	var logical := (screen_position - Vector2(layout.get("origin", Vector2.ZERO))) / scale
	return logical.floor() if snap_to_pixel else logical


static func configure_canvas_item(item: CanvasItem) -> void:
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED


static func configure_subviewport(viewport: SubViewport, profile: Dictionary) -> Dictionary:
	var validation := Contract.validate_profile(profile)
	if not bool(validation.get("ok", false)):
		return validation
	viewport.size = profile.get("logical_size", Vector2i(320, 200))
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.snap_2d_transforms_to_pixel = true
	viewport.snap_2d_vertices_to_pixel = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	return {"ok": true, "errors": []}


static func configure_output_rect(output: TextureRect, layout: Dictionary,
		crt_material: ShaderMaterial = null) -> void:
	configure_canvas_item(output)
	output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	output.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	output.position = Vector2(layout.get("origin", Vector2.ZERO))
	output.size = Vector2(layout.get("output_size", Vector2.ZERO))
	output.material = crt_material


static func create_crt_output_material(profile: Dictionary,
		options: Dictionary = {}) -> ShaderMaterial:
	var validation := Contract.validate_profile(profile)
	if not bool(validation.get("ok", false)):
		return null
	var material := ShaderMaterial.new()
	material.shader = CRT_OUTPUT_SHADER
	var logical_i: Vector2i = profile.get("logical_size", Vector2i(320, 200))
	material.set_shader_parameter("logical_size", Vector2(logical_i))
	material.set_shader_parameter(
		"scanline_strength", float(options.get("scanline_strength", 0.10)))
	material.set_shader_parameter(
		"shadow_mask_strength", float(options.get("shadow_mask_strength", 0.035)))
	material.set_shader_parameter(
		"glow_strength", float(options.get("glow_strength", 0.025)))
	material.set_shader_parameter(
		"curvature", float(options.get("curvature", 0.0)))
	return material


static func output_contract() -> Dictionary:
	return {
		"world_filter": "nearest",
		"world_coordinates": "integer_logical_pixels",
		"scale": "integer",
		"letterbox": true,
		"crt_stage": "final_texture_rect_only",
		"crt_affects_input": false,
		"crt_default_curvature": 0.0,
	}
