class_name AgaSpriteCatalog
extends RefCounted
## Gemeinsamer Vertrag fuer justierbare AGA-Atlasrahmen. Laufzeit, Tests und
## Preview-Szenen beziehen Ausschnitt, Pivot und Darstellungsskala aus derselben
## Datei. So kann kein im Editor korrigierter Rahmen im Spiel erneut abweichen.

const DATA_PATH := "res://data/aga_sprite_frames.json"

static var _data: Dictionary = {}
static var _textures: Dictionary = {}


static func reload() -> void:
	_data.clear()
	_textures.clear()
	_ensure_loaded()


static func atlas(atlas_id: String) -> Dictionary:
	_ensure_loaded()
	return (_data.get("atlases", {}) as Dictionary).get(atlas_id, {}) as Dictionary


static func frame(frame_id: String) -> Dictionary:
	var parts := frame_id.split(".", false, 1)
	if parts.size() != 2:
		return {}
	var atlas_data := atlas(parts[0])
	var frames := atlas_data.get("frames", {}) as Dictionary
	if not frames.has(parts[1]):
		return {}
	var result := (frames[parts[1]] as Dictionary).duplicate(true)
	result["atlas_id"] = parts[0]
	result["frame_name"] = parts[1]
	result["texture_path"] = str(atlas_data.get("texture", ""))
	return result


static func has_frame(frame_id: String) -> bool:
	return not frame(frame_id).is_empty()


static func texture_for_atlas(atlas_id: String) -> Texture2D:
	if _textures.has(atlas_id):
		return _textures[atlas_id] as Texture2D
	var atlas_data := atlas(atlas_id)
	var texture_path := str(atlas_data.get("texture", ""))
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return null
	var texture := load(texture_path) as Texture2D
	_textures[atlas_id] = texture
	return texture


static func source_rect(frame_data: Dictionary) -> Rect2:
	var values := frame_data.get("region", []) as Array
	if values.size() != 4:
		return Rect2()
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


static func pivot(frame_data: Dictionary) -> Vector2:
	var values := frame_data.get("pivot", [0.5, 0.5]) as Array
	if values.size() != 2:
		return Vector2(0.5, 0.5)
	return Vector2(float(values[0]), float(values[1]))


static func draw_frame(canvas: CanvasItem, frame_id: String, centre: Vector2,
		max_size: Vector2, modulate: Color = Color.WHITE) -> Rect2:
	var frame_data := frame(frame_id)
	if frame_data.is_empty():
		return Rect2()
	var texture := texture_for_atlas(str(frame_data.get("atlas_id", "")))
	var source := source_rect(frame_data)
	if texture == null or source.size.x <= 0.0 or source.size.y <= 0.0:
		return Rect2()
	var fit := minf(max_size.x / source.size.x, max_size.y / source.size.y)
	fit *= float(frame_data.get("scale", 1.0))
	var draw_size := (source.size * fit).round()
	var draw_at := (centre - draw_size * pivot(frame_data)).round()
	var destination := Rect2(draw_at, draw_size)
	canvas.draw_texture_rect_region(texture, destination, source, modulate, false, true)
	return destination


static func _ensure_loaded() -> void:
	if not _data.is_empty():
		return
	if not FileAccess.file_exists(DATA_PATH):
		push_error("AGA-Sprite-Katalog fehlt: " + DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is not Dictionary:
		push_error("AGA-Sprite-Katalog ist kein gueltiges JSON-Objekt: " + DATA_PATH)
		return
	_data = parsed as Dictionary
