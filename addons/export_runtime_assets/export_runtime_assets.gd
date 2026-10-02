@tool
extends EditorExportPlugin

## The software artwork is deliberately below a .gdignore file. A release needs
## the logical paths, but not 740 MiB of source-resolution scans: every picture is
## decoded by magic bytes, bounded to the largest in-game presentation size and
## packed as WebP while retaining its logical path. RuntimeImageLoader therefore
## resolves the same path on Linux and Windows without duplicate .ctex resources.

const RAW_TREES: Array[String] = ["res://assets/software"]
const MANIFEST_PATH := "res://export_runtime_manifest.json"
const SOFTWARE_CATALOG_ROOT := "res://Content/Software"
const MUSIC_CATALOG_PATH := "res://data/music.json"
const DEMO_FEATURE := "itch_demo"
const DEMO_MAX_YEAR := 1990
const DEMO_YEAR_SCOPED_ROOTS: Array[String] = [
	"res://assets/ui/magazines/",
	"res://assets/ui/newspapers/",
	"res://Content/Magazine/assets/",
]
const MAX_ART_EDGE := 768
const MAX_LABEL_EDGE := 512
const COVER_QUALITY := 0.86

var _demo_export := false
var _demo_software_roots: Dictionary = {}
var _demo_future_music_paths: Dictionary = {}
var _demo_skipped_files := 0
var _allowed_music: Dictionary = {}


func _get_name() -> String:
	return "Sommer90RuntimeAssets"


func _export_begin(
	features: PackedStringArray,
	_is_debug: bool,
	_path: String,
	_flags: int
) -> void:
	_demo_export = DEMO_FEATURE in features
	_allowed_music.clear()
	var soundtrack: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/soundtrack.json"))
	if soundtrack is Dictionary:
		for entry: Dictionary in soundtrack.get("tracks", []):
			var music_path := str(entry.get("file", ""))
			if music_path.begins_with("res://assets/audio/soundtrack/") \
					and FileAccess.get_sha256(music_path) == str(entry.get("sha256", "")):
				_allowed_music[music_path] = true
	_demo_skipped_files = 0
	_demo_software_roots = _demo_software_art_roots() if _demo_export else {}
	_demo_future_music_paths = _future_music_paths() if _demo_export else {}
	var paths: Array[String] = []
	for root: String in RAW_TREES:
		_collect_tree(root, paths)
	paths.sort()
	var all_source_file_count := paths.size()
	if _demo_export:
		paths = paths.filter(_demo_software_path_allowed)

	var packed_paths: Array[String] = []
	var total_bytes := 0
	var source_bytes := 0
	var optimized_files := 0
	var failures: Array[String] = []
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append(path)
			continue
		var length := file.get_length()
		var bytes := file.get_buffer(length)
		file.close()
		if bytes.size() != length:
			failures.append(path)
			continue
		source_bytes += bytes.size()
		var packed := _runtime_bytes(path, bytes)
		if packed.is_empty():
			failures.append(path)
			continue
		if packed.size() < bytes.size():
			optimized_files += 1
		# Auch bereits kleine bzw. inkompressible Bilder müssen in das PCK. Die
		# frühere Bedingung auf „kleiner als Quelle“ ließ genau solche Dateien aus.
		add_file(path, packed, false)
		packed_paths.append(path)
		total_bytes += packed.size()

	var manifest := {
		"schema": 1,
		"generator": _get_name(),
		"channel": "itch_demo_1990" if _demo_export else "full",
		"max_release_year": DEMO_MAX_YEAR if _demo_export else 0,
		"software_files": packed_paths,
		"software_source_file_count": paths.size(),
		"software_all_source_file_count": all_source_file_count,
		"software_excluded_file_count": all_source_file_count - paths.size(),
		"software_file_count": packed_paths.size(),
		"software_bytes": total_bytes,
		"software_source_bytes": source_bytes,
		"optimized_files": optimized_files,
		"read_failures": failures,
	}
	add_file(MANIFEST_PATH, JSON.stringify(manifest).to_utf8_buffer(), false)

	if paths.is_empty():
		push_error("[Export] assets/software is empty; the release would have no software artwork.")
	if not failures.is_empty():
		push_error("[Export] Could not pack %d runtime artwork files: %s" % [
			failures.size(), ", ".join(failures.slice(0, 8))])
	print(("[Export] Runtime assets [%s]: %d/%d files, %.1f -> %.1f MiB " \
		+ "(%d optimized; %d im Vollkatalog)") % [
		"DEMO 1990" if _demo_export else "FULL",
		packed_paths.size(), paths.size(), float(source_bytes) / 1048576.0,
		float(total_bytes) / 1048576.0, optimized_files, all_source_file_count])


func _export_file(path: String, _type: String, features: PackedStringArray) -> void:
	# Hand exports must also exclude private and uncleared modules.
	if path.get_extension().to_lower() == "mod" and not _allowed_music.has(path):
		skip()
		push_warning("[Export] Nicht belegter MOD ausgeschlossen: %s" % path)
		return
	if DEMO_FEATURE not in features:
		return
	if _demo_future_music_paths.has(path) or _is_future_year_asset(path):
		_demo_skipped_files += 1
		skip()


func _export_end() -> void:
	if _demo_export:
		print("[Export] Demo-Pruning: %d spaetere Musik-/Presseassets ausgelassen." % \
			_demo_skipped_files)
	_demo_export = false
	_demo_software_roots.clear()
	_demo_future_music_paths.clear()


func _runtime_bytes(path: String, source: PackedByteArray) -> PackedByteArray:
	if source.size() < 8:
		return source
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if source[0] == 0xFF and source[1] == 0xD8:
		error = image.load_jpg_from_buffer(source)
	elif source[0] == 0x89 and source[1] == 0x50:
		error = image.load_png_from_buffer(source)
	elif source[0] == 0x52 and source[1] == 0x49 and source[2] == 0x46 and source[3] == 0x46:
		error = image.load_webp_from_buffer(source)
	if error != OK or image.is_empty():
		return source
	var file_name := path.get_file().to_lower()
	var label := file_name.begins_with("disk_label")
	var max_edge := MAX_LABEL_EDGE if label else MAX_ART_EDGE
	var largest := maxi(image.get_width(), image.get_height())
	if largest > max_edge:
		var scale := float(max_edge) / float(largest)
		image.resize(maxi(1, roundi(image.get_width() * scale)),
			maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	# Diskettenlabels bleiben verlustfrei; Cover/Handbücher erhalten eine hohe
	# visuelle Qualität bei wesentlich kleinerem Distributionsvolumen.
	var result := image.save_webp_to_buffer(not label, COVER_QUALITY)
	return result if not result.is_empty() and result.size() < source.size() else source


func _collect_tree(root: String, output: Array[String]) -> void:
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var directory: String = pending.pop_back()
		var dir := DirAccess.open(directory)
		if dir == null:
			push_error("[Export] Runtime asset directory not readable: %s" % directory)
			continue
		for subdirectory: String in DirAccess.get_directories_at(directory):
			pending.append(directory.path_join(subdirectory))
		for file_name: String in DirAccess.get_files_at(directory):
			if file_name == ".gdignore" or file_name.ends_with(".import"):
				continue
			output.append(directory.path_join(file_name))


func _demo_software_path_allowed(path_value: Variant) -> bool:
	var path := str(path_value)
	for root_value: Variant in _demo_software_roots.keys():
		var root := str(root_value).trim_suffix("/") + "/"
		if path.begins_with(root):
			return true
	return false


func _demo_software_art_roots() -> Dictionary:
	var roots: Dictionary = {}
	var json_paths: Array[String] = []
	_collect_files_with_extension(SOFTWARE_CATALOG_ROOT, "json", json_paths)
	for path: String in json_paths:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			continue
		for raw_entry: Variant in (parsed as Dictionary).get("entries", []):
			if not raw_entry is Dictionary:
				continue
			var entry := raw_entry as Dictionary
			var year_value: Variant = entry.get("release_year")
			if not year_value is float and not year_value is int:
				continue
			if int(year_value) > DEMO_MAX_YEAR:
				continue
			var art_root := str(entry.get("art_dir", "")).trim_suffix("/")
			if art_root.begins_with("res://assets/software/"):
				roots[art_root] = true
	if roots.is_empty():
		push_error("[Export] Demo-Softwarekatalog ist leer; der Demo-Shop haette keine Cover.")
	return roots


func _future_music_paths() -> Dictionary:
	var result: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("[Export] music.json ist unlesbar; Demo-Musik kann nicht sicher beschnitten werden.")
		return result
	for raw_track: Variant in (parsed as Dictionary).get("tracks", []):
		if not raw_track is Dictionary:
			continue
		var track := raw_track as Dictionary
		if int(track.get("year", 3000)) <= DEMO_MAX_YEAR:
			continue
		var path := str(track.get("file", ""))
		if path.begins_with("res://assets/audio/music/"):
			result[path] = true
	return result


func _is_future_year_asset(path: String) -> bool:
	var scoped := false
	for root: String in DEMO_YEAR_SCOPED_ROOTS:
		if path.begins_with(root):
			scoped = true
			break
	if not scoped:
		return false
	for year in range(DEMO_MAX_YEAR + 1, 2100):
		if "/%d/" % year in path:
			return true
	return false


func _collect_files_with_extension(root: String, extension: String, output: Array[String]) -> void:
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var directory: String = pending.pop_back()
		if not DirAccess.dir_exists_absolute(directory):
			continue
		for subdirectory: String in DirAccess.get_directories_at(directory):
			pending.append(directory.path_join(subdirectory))
		for file_name: String in DirAccess.get_files_at(directory):
			if file_name.get_extension().to_lower() == extension:
				output.append(directory.path_join(file_name))
