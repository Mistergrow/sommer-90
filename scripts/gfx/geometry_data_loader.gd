class_name GeometryDataLoader
extends RefCounted
## Gemeinsamer, fehlertoleranter JSON-Lader fuer die 2,5D-Geometriekataloge.


static func load_dictionary(path: String, fallback: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fallback.duplicate(true)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed as Dictionary
	return fallback.duplicate(true)
