class_name AmigaAssetCompiler
extends RefCounted
## Deterministische Offline-/Ladezeit-Pipeline fuer Amiga-Laufzeitgrafik.
##
## Sie reduziert beliebige Quellgrafik auf das Zielprofil, erzeugt ein
## indiziert wirkendes RGBA-Bild, dedupliziert 8x8-Blitter-Tiles und liefert
## belastbare Speicherwerte. Im Frame-Loop wird niemals quantisiert.

const Contract := preload("res://scripts/games/amiga_video_contract.gd")

const DEFAULT_TILE_SIZE := Vector2i(8, 8)
const MAX_KMEANS_PASSES := 8


static func compile_image(source: Image, profile: Dictionary,
		options: Dictionary = {}) -> Dictionary:
	var validation := Contract.validate_profile(profile)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "errors": validation.get("errors", [])}
	if source == null or source.is_empty():
		return {"ok": false, "errors": ["Quellbild fehlt oder ist leer."]}
	var request: Dictionary = profile.get("render_request", {})
	var max_colors := clampi(
		int(options.get("max_colors", request.get("indexed_colors", 32))), 2,
		int((Contract.limits_for(profile) as Dictionary).get("max_indexed_colors", 32)))
	var dither_strength := clampf(float(options.get("dither_strength", 0.72)), 0.0, 1.0)
	var scaled := _fit_to_logical(source, profile, bool(options.get("fit_screen", false)))
	var palette := _build_palette(scaled, max_colors, int(profile.get("chipset", 0)))
	var indexed := _remap_dithered(scaled, palette, dither_strength)
	var tiles := compile_tiles(indexed,
		Vector2i(options.get("tile_size", DEFAULT_TILE_SIZE)))
	var bitplanes := int(request.get("bitplanes", 5))
	var frame_bytes := ceili(float(indexed.get_width() * indexed.get_height() * bitplanes) / 8.0)
	return {
		"ok": true,
		"image": indexed,
		"palette": palette,
		"palette_size": palette.size(),
		"tiles": tiles,
		"frame_bytes": frame_bytes,
		"chipset": profile.get("chipset_name", "OCS"),
		"logical_size": profile.get("logical_size", indexed.get_size()),
		"errors": [],
	}


static func compile_tiles(image: Image, tile_size := DEFAULT_TILE_SIZE) -> Dictionary:
	if image == null or image.is_empty() or tile_size.x <= 0 or tile_size.y <= 0:
		return {"ok": false, "errors": ["Ungueltiges Bild oder Tile-Raster."]}
	var columns := ceili(float(image.get_width()) / float(tile_size.x))
	var rows := ceili(float(image.get_height()) / float(tile_size.y))
	var unique_signatures: Dictionary = {}
	var unique_images: Array[Image] = []
	var tile_map := PackedInt32Array()
	for tile_y in rows:
		for tile_x in columns:
			var tile := Image.create(tile_size.x, tile_size.y, false, Image.FORMAT_RGBA8)
			var signature := PackedByteArray()
			for py in tile_size.y:
				for px in tile_size.x:
					var sx := tile_x * tile_size.x + px
					var sy := tile_y * tile_size.y + py
					var color := Color(0, 0, 0, 0)
					if sx < image.get_width() and sy < image.get_height():
						color = image.get_pixel(sx, sy)
					tile.set_pixel(px, py, color)
					signature.append(clampi(roundi(color.r * 255.0), 0, 255))
					signature.append(clampi(roundi(color.g * 255.0), 0, 255))
					signature.append(clampi(roundi(color.b * 255.0), 0, 255))
					signature.append(clampi(roundi(color.a * 255.0), 0, 255))
			var key := signature.hex_encode()
			if not unique_signatures.has(key):
				unique_signatures[key] = unique_images.size()
				unique_images.append(tile)
			tile_map.append(int(unique_signatures[key]))
	var atlas_columns := mini(16, maxi(1, unique_images.size()))
	var atlas_rows := ceili(float(unique_images.size()) / float(atlas_columns))
	var atlas := Image.create(atlas_columns * tile_size.x, atlas_rows * tile_size.y,
		false, Image.FORMAT_RGBA8)
	for index in unique_images.size():
		var destination := Vector2i(
			(index % atlas_columns) * tile_size.x,
			floori(float(index) / float(atlas_columns)) * tile_size.y)
		atlas.blit_rect(unique_images[index],
			Rect2i(Vector2i.ZERO, tile_size), destination)
	return {
		"ok": true,
		"atlas": atlas,
		"map": tile_map,
		"map_size": Vector2i(columns, rows),
		"tile_size": tile_size,
		"source_tiles": columns * rows,
		"unique_tiles": unique_images.size(),
		"deduplication_ratio": 1.0 - float(unique_images.size()) /
			float(maxi(1, columns * rows)),
		"map_bytes": tile_map.size() * 2,
		"errors": [],
	}


static func validate_animation(frame_count: int, profile: Dictionary,
		actor_count := 1) -> Dictionary:
	var limits := Contract.limits_for(profile)
	var maximum := int(limits.get("animation_frames_per_actor", 1))
	var errors: Array[String] = []
	if frame_count <= 0:
		errors.append("Animation besitzt keine Frames.")
	if frame_count > maximum:
		errors.append("%d Frames ueberschreiten das %s-Limit von %d." % [
			frame_count, profile.get("chipset_name", "Amiga"), maximum])
	if actor_count <= 0:
		errors.append("actor_count muss groesser als null sein.")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"frame_count": frame_count,
		"maximum": maximum,
		"actor_count": actor_count,
	}


static func _fit_to_logical(source: Image, profile: Dictionary, fit_screen: bool) -> Image:
	var result := source.duplicate()
	result.convert(Image.FORMAT_RGBA8)
	if not fit_screen:
		return result
	var logical: Vector2i = profile.get("logical_size", result.get_size())
	if result.get_size() != logical:
		result.resize(logical.x, logical.y, Image.INTERPOLATE_NEAREST)
	return result


static func _build_palette(image: Image, max_colors: int, chipset: int) -> Array[Color]:
	var histogram: Dictionary = {}
	var step := 1 if image.get_width() * image.get_height() <= 100_000 else 2
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			var color := image.get_pixel(x, y)
			if color.a < 0.1:
				continue
			var key := _histogram_key(color)
			histogram[key] = int(histogram.get(key, 0)) + 1
	var samples: Array[Vector3] = []
	var weights: Array[int] = []
	for raw_key: Variant in histogram:
		var key := int(raw_key)
		samples.append(Vector3(
			float((key >> 10) & 31) / 31.0,
			float((key >> 5) & 31) / 31.0,
			float(key & 31) / 31.0))
		weights.append(int(histogram[key]))
	if samples.is_empty():
		return [Color(0, 0, 0, 0), Color.BLACK]
	var target := mini(max_colors, samples.size())
	var centers: Array[Vector3] = [_weighted_average(samples, weights)]
	while centers.size() < target:
		var best_index := 0
		var best_distance := -1.0
		for i in samples.size():
			var nearest := INF
			for center: Vector3 in centers:
				nearest = minf(nearest, samples[i].distance_squared_to(center))
			var score := nearest * sqrt(float(weights[i]))
			if score > best_distance:
				best_distance = score
				best_index = i
		centers.append(samples[best_index])
	for _pass in MAX_KMEANS_PASSES:
		var sums: Array[Vector3] = []
		var totals: Array[int] = []
		for _center in centers:
			sums.append(Vector3.ZERO)
			totals.append(0)
		for i in samples.size():
			var cluster := _nearest_center(samples[i], centers)
			sums[cluster] += samples[i] * float(weights[i])
			totals[cluster] += weights[i]
		for index in centers.size():
			if totals[index] > 0:
				centers[index] = sums[index] / float(totals[index])
	var palette: Array[Color] = []
	for center: Vector3 in centers:
		palette.append(_hardware_color(center, chipset))
	return palette


static func _remap_dithered(source: Image, palette: Array[Color],
		strength: float) -> Image:
	var width := source.get_width()
	var height := source.get_height()
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var current_error: Array[Vector3] = []
	var next_error: Array[Vector3] = []
	for _x in width + 2:
		current_error.append(Vector3.ZERO)
		next_error.append(Vector3.ZERO)
	for y in height:
		var left_to_right := y % 2 == 0
		var x_start := 0 if left_to_right else width - 1
		var x_end := width if left_to_right else -1
		var x_step := 1 if left_to_right else -1
		for x in range(x_start, x_end, x_step):
			var source_color := source.get_pixel(x, y)
			if source_color.a < 0.1:
				result.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var value := Vector3(source_color.r, source_color.g, source_color.b) \
				+ current_error[x + 1] * strength
			value = Vector3(
				clampf(value.x, 0.0, 1.0),
				clampf(value.y, 0.0, 1.0),
				clampf(value.z, 0.0, 1.0))
			var palette_index := _nearest_palette(value, palette)
			var chosen := palette[palette_index]
			result.set_pixel(x, y, Color(chosen.r, chosen.g, chosen.b, source_color.a))
			var error := value - Vector3(chosen.r, chosen.g, chosen.b)
			var direction := 1 if left_to_right else -1
			current_error[x + 1 + direction] += error * (7.0 / 16.0)
			next_error[x + 1 - direction] += error * (3.0 / 16.0)
			next_error[x + 1] += error * (5.0 / 16.0)
			next_error[x + 1 + direction] += error * (1.0 / 16.0)
		current_error = next_error
		next_error = []
		for _x in width + 2:
			next_error.append(Vector3.ZERO)
	return result


static func _histogram_key(color: Color) -> int:
	return clampi(roundi(color.r * 31.0), 0, 31) << 10 \
		| clampi(roundi(color.g * 31.0), 0, 31) << 5 \
		| clampi(roundi(color.b * 31.0), 0, 31)


static func _weighted_average(samples: Array[Vector3], weights: Array[int]) -> Vector3:
	var total := 0
	var sum := Vector3.ZERO
	for i in samples.size():
		sum += samples[i] * float(weights[i])
		total += weights[i]
	return sum / float(maxi(1, total))


static func _nearest_center(sample: Vector3, centers: Array[Vector3]) -> int:
	var best := 0
	var distance := INF
	for i in centers.size():
		var candidate := sample.distance_squared_to(centers[i])
		if candidate < distance:
			distance = candidate
			best = i
	return best


static func _nearest_palette(sample: Vector3, palette: Array[Color]) -> int:
	var best := 0
	var distance := INF
	for i in palette.size():
		var color := palette[i]
		var candidate := sample.distance_squared_to(Vector3(color.r, color.g, color.b))
		if candidate < distance:
			distance = candidate
			best = i
	return best


static func _hardware_color(value: Vector3, chipset: int) -> Color:
	if chipset == Contract.Chipset.AGA:
		return Color(
			roundf(value.x * 255.0) / 255.0,
			roundf(value.y * 255.0) / 255.0,
			roundf(value.z * 255.0) / 255.0)
	return Color(
		roundf(value.x * 15.0) / 15.0,
		roundf(value.y * 15.0) / 15.0,
		roundf(value.z * 15.0) / 15.0)
