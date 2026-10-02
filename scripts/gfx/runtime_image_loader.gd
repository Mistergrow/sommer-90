class_name RuntimeImageLoader
extends RefCounted

## Cross-platform image loading for exported projects.
##
## Imported Godot images are stored as .ctex in a PCK; opening their original
## PNG path with FileAccess only works in the editor source tree. Conversely,
## software artwork below .gdignore intentionally has no imported resource and
## must be decoded from its original bytes. This loader supports both paths and
## keeps `res://` paths canonical on Windows, Linux and macOS.

## Software-Art liegt absichtlich außerhalb des Godot-Imports und war bisher bei
## jedem Krause-/Shop-/Vitrinenwechsel erneut von Platte dekodiert worden. Zwei
## begrenzte LRUs halten nur zuletzt/relevant benutzte Bilder im RAM; das ist ein
## kontrollierter Cache statt eines 883-MB-Komplettimports.
const RAW_CACHE_LIMIT := 48
const TEXTURE_CACHE_LIMIT := 144
const RAW_CACHE_BUDGET_BYTES := 256 * 1024 * 1024
const TEXTURE_CACHE_BUDGET_BYTES := 384 * 1024 * 1024
static var _raw_cache: Dictionary = {}
static var _raw_order: Array[String] = []
static var _raw_sizes: Dictionary = {}
static var _raw_bytes := 0
static var _texture_cache: Dictionary = {}
static var _texture_order: Array[String] = []
static var _texture_sizes: Dictionary = {}
static var _texture_bytes := 0


static func clear_cache() -> void:
	_raw_cache.clear()
	_raw_order.clear()
	_raw_sizes.clear()
	_raw_bytes = 0
	_texture_cache.clear()
	_texture_order.clear()
	_texture_sizes.clear()
	_texture_bytes = 0


static func cache_stats() -> Dictionary:
	return {
		"raw_images": _raw_cache.size(),
		"textures": _texture_cache.size(),
		"raw_mb": snappedf(float(_raw_bytes) / 1048576.0, 0.01),
		"texture_mb": snappedf(float(_texture_bytes) / 1048576.0, 0.01),
	}


static func canonical_path(value: String) -> String:
	var path := value.strip_edges().replace("\\", "/")
	if path.begins_with("res:/") and not path.begins_with("res://"):
		path = "res://" + path.trim_prefix("res:/").trim_prefix("/")
	if path.begins_with("res://"):
		var relative := path.trim_prefix("res://")
		while relative.contains("//"):
			relative = relative.replace("//", "/")
		return "res://" + relative.simplify_path().trim_prefix("/")
	return path.simplify_path()


static func exists(value: String) -> bool:
	var path := canonical_path(value)
	return not path.is_empty() and (ResourceLoader.exists(path) or FileAccess.file_exists(path))


## Darf unter `path` eine importierte Textur erwartet werden? ResourceLoader.exists()
## bejaht JEDE Ressource. Die explizite Erweiterungsliste verhindert deshalb,
## dass ein versehentlicher Daten-/Audio-/Szenenpfad nur fuer einen `as
## Texture2D`-Fehlgriff geladen und im Ressourcen-Cache gehalten wird.
##
## Die Prüfung bleibt bewusst versionsneutral und lädt dafür keine Ressource.
## Unbekannte Erweiterungen werden nicht pauschal abgelehnt, damit
## benutzerdefinierte Texture2D-Importer weiterhin funktionieren.
static func may_be_texture(value: String) -> bool:
	var extension := canonical_path(value).get_extension().to_lower()
	if extension in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga",
			"dds", "ktx", "exr", "hdr"]:
		return true
	if extension in ["json", "csv", "translation", "ogg", "wav", "mp3",
			"mod", "tscn", "scn", "gd", "gdshader", "ttf", "otf", "cfg"]:
		return false
	return true


## Logische Bilddateien eines Verzeichnisses. Im Quellprojekt liefert DirAccess
## oft `name.png`, im PCK kann derselbe Import als `name.png.import` auftauchen.
## Aufrufer erhalten in beiden Fällen genau einmal den ladbaren PNG/JPG-Pfad.
static func logical_files(directory_value: String, extensions: Array[String]) -> Array[String]:
	var directory := canonical_path(directory_value).trim_suffix("/")
	var output: Array[String] = []
	if directory.is_empty() or DirAccess.open(directory) == null:
		return output
	for stored_name: String in DirAccess.get_files_at(directory):
		var logical_name := stored_name.trim_suffix(".import")
		if logical_name.get_extension().to_lower() not in extensions:
			continue
		var path := directory.path_join(logical_name)
		if exists(path) and path not in output:
			output.append(path)
	output.sort()
	return output


static func texture(
	value: String,
	max_width: int = 0,
	raw_first: bool = false
) -> Texture2D:
	var path := canonical_path(value)
	if path.is_empty():
		return null
	var cache_key := "%s|%d|%s" % [path, max_width, str(raw_first)]
	if _texture_cache.has(cache_key):
		_texture_order.erase(cache_key)
		_texture_order.append(cache_key)
		return _texture_cache[cache_key] as Texture2D
	# Dasselbe bereits importierte Texture2D darf bei verschiedenen, nicht
	# wirksamen max_width-Werten weder doppelt als RAM-Verbrauch gezaehlt noch
	# vorzeitig aus dem LRU verdraengt werden.
	var imported_key := "%s|imported" % path
	if not raw_first and _texture_cache.has(imported_key):
		var cached_imported := _texture_cache[imported_key] as Texture2D
		if cached_imported != null and (max_width <= 0 or cached_imported.get_width() <= max_width):
			_texture_order.erase(imported_key)
			_texture_order.append(imported_key)
			return cached_imported

	var image: Image = null
	if raw_first:
		image = raw_image(path)
	if image == null and ResourceLoader.exists(path) and may_be_texture(path):
		var imported := ResourceLoader.load(path) as Texture2D
		if imported != null:
			if max_width <= 0 or imported.get_width() <= max_width:
				return _remember_texture(imported_key, imported)
			image = imported.get_image()
	if image == null:
		image = raw_image(path)
	if image == null:
		return null

	image.convert(Image.FORMAT_RGBA8)
	if max_width > 0 and image.get_width() > max_width:
		var target_height := maxi(1, roundi(
			float(max_width) * float(image.get_height()) / float(image.get_width())))
		image.resize(max_width, target_height, Image.INTERPOLATE_LANCZOS)
	return _remember_texture(cache_key, ImageTexture.create_from_image(image))


static func raw_image(value: String) -> Image:
	var path := canonical_path(value)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := _cached_or_load_raw(path)
	return image.duplicate() if image != null else null


## Dekodiert eine raw-first Softwarequelle in den begrenzten LRU, ohne die
## fuer einen Aufrufer sonst notwendige Vollbildkopie anzulegen. Der verteilte
## Warmup kann Dateidekodierung und eigentliche Komposition damit als zwei
## kleine, einzeln budgetierbare Jobs ausfuehren.
static func warm_raw_image(value: String) -> bool:
	var path := canonical_path(value)
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	return _cached_or_load_raw(path) != null


static func _cached_or_load_raw(path: String) -> Image:
	if _raw_cache.has(path):
		_raw_order.erase(path)
		_raw_order.append(path)
		return _raw_cache[path] as Image
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 4:
		return null
	var image := Image.new()
	var error: int
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46:
		error = image.load_webp_from_buffer(bytes)
	else:
		return null
	if error != OK:
		return null
	_raw_cache[path] = image
	_raw_order.append(path)
	var image_bytes := image.get_data_size()
	_raw_sizes[path] = image_bytes
	_raw_bytes += image_bytes
	while _raw_order.size() > RAW_CACHE_LIMIT or _raw_bytes > RAW_CACHE_BUDGET_BYTES:
		var evicted: String = str(_raw_order.pop_front())
		_raw_bytes -= int(_raw_sizes.get(evicted, 0))
		_raw_sizes.erase(evicted)
		_raw_cache.erase(evicted)
	return image


static func _remember_texture(key: String, tex: Texture2D) -> Texture2D:
	if _texture_cache.has(key):
		_texture_bytes -= int(_texture_sizes.get(key, 0))
	_texture_cache[key] = tex
	_texture_order.erase(key)
	_texture_order.append(key)
	var texture_bytes := maxi(1, tex.get_width()) * maxi(1, tex.get_height()) * 4
	_texture_sizes[key] = texture_bytes
	_texture_bytes += texture_bytes
	while _texture_order.size() > TEXTURE_CACHE_LIMIT \
			or _texture_bytes > TEXTURE_CACHE_BUDGET_BYTES:
		var evicted: String = str(_texture_order.pop_front())
		_texture_bytes -= int(_texture_sizes.get(evicted, 0))
		_texture_sizes.erase(evicted)
		_texture_cache.erase(evicted)
	return tex
