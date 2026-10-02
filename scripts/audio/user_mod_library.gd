extends RefCounted
## Local data only: no scripts, archives, downloads or automatic copying.
## Slot matching is exact after normalization; ambiguous titles never guess.

const Parser := preload("res://scripts/audio/mod_parser.gd")
const DIRECTORY := "user://mods/music"
const MAX_FILES := 1024
const MAX_DEPTH := 4
const MAX_MAPPING_BYTES := 65536
const MAX_HASH_BYTES := 128 * 1024 * 1024
const GUIDE := "Eigene MOD-Musik / Your MOD music\n\nKopiere .mod-Dateien hierher und wähle im Spiel Optionen > MOD-Ordner > Neu einlesen.\nCopy .mod files here, then use Options > MOD folder > Rescan.\n\nProTracker, 4/6/8 Kanäle/channels, maximal 8 MiB je Datei/per file.\nID, Original-Dateiname oder eindeutiger Songtitel im MOD-Kopf werden erkannt.\nMatching: slot ID, original filename, or unique embedded MOD title.\nOhne Treffer bleibt der neue Original-Soundtrack aktiv.\nWithout a match, the new original soundtrack remains active.\n\nNicht zugeordnete Dateien erscheinen in deiner Anlage als eigene Titel.\nUnmatched files appear in your stereo as personal tracks.\n\nOptional overrides.json: {\"space_debris\": \"mein_song.mod\"}\nDie Namen sind relativ zu diesem Ordner. Keine absoluten Pfade oder ../.\nPaths are relative to this folder. No absolute paths or ../.\nBei mehreren Kandidaten eine eindeutige Zuordnung in overrides.json anlegen.\nResolve ambiguous matches with overrides.json.\n\nNur Dateien verwenden, die du rechtmäßig nutzen darfst. Dieser Ordner wird\nnicht hochgeladen, geteilt oder in den Spiel-Export übernommen.\nUse files you may lawfully use. This folder is never uploaded or included in exports.\n"

var matches: Dictionary = {}
var extras: Dictionary = {}
var issues: Array[String] = []
var scanned := 0
var _aliases: Dictionary = {}
var _catalog: Dictionary = {}
var _candidates: Dictionary = {}
var _fingerprints: Dictionary = {}
var _original_sizes: Dictionary = {}
var _hash_bytes := 0
var _visited_dirs := 0


func scan(catalog: Array, directory := DIRECTORY) -> Dictionary:
	matches.clear()
	extras.clear()
	issues.clear()
	_aliases.clear()
	_catalog.clear()
	_candidates.clear()
	_fingerprints.clear()
	_original_sizes.clear()
	_hash_bytes = 0
	_visited_dirs = 0
	scanned = 0
	for entry: Dictionary in catalog:
		var id := str(entry.get("id", ""))
		_catalog[id] = entry
		var fingerprint := str(entry.get("original_sha256", ""))
		if fingerprint.length() == 64:
			if not _fingerprints.has(fingerprint):
				_fingerprints[fingerprint] = []
			_fingerprints[fingerprint].append(id)
			_original_sizes[int(entry.get("original_bytes", 0))] = true
		for alias: String in [id, str(entry.get("title", "")),
			str(entry.get("original_filename", "")).get_basename(),
			str(entry.get("original_mod_title", "")),
			str(entry.get("title", "")) + " " + str(entry.get("author", ""))]:
			var key := normalize(alias)
			if key.is_empty():
				continue
			if not _aliases.has(key):
				_aliases[key] = []
			if id not in _aliases[key]:
				_aliases[key].append(id)
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		issues.append("MOD-Ordner konnte nicht angelegt werden: %s" % error_string(error))
		return report()
	if not FileAccess.file_exists(directory.path_join("README.txt")):
		var guide := FileAccess.open(directory.path_join("README.txt"), FileAccess.WRITE)
		if guide != null:
			guide.store_string(GUIDE)
	var files: Array[String] = []
	_collect(directory, "", 0, files)
	files.sort()
	var explicit := _mapping(directory)
	var mapped_paths: Dictionary = {}
	for id: Variant in explicit:
		var relative := str(explicit[id])
		if not _catalog.has(str(id)) or relative.is_absolute_path() or ":" in relative \
				or ".." in relative.split("/") or "\\" in relative or relative not in files:
			issues.append("Ungültige Zuordnung: %s" % str(id))
			continue
		if not mapped_paths.has(relative):
			mapped_paths[relative] = []
		mapped_paths[relative].append(str(id))
	for relative: String in files:
		var path := directory.path_join(relative)
		var info := Parser.inspect(path)
		scanned += 1
		if not bool(info.get("ok", false)):
			issues.append("%s: %s" % [relative, info.get("error", "Ungültiges MOD")])
			continue
		var record := {"file": path, "title": str(info.get("title", "")),
			"author": "", "user_mod": true, "relative_file": relative}
		if str(record.title).is_empty():
			record.title = relative.get_file().get_basename()
		var ids: Array = mapped_paths.get(relative, [])
		var priority := 3 if not ids.is_empty() else 0
		if ids.is_empty():
			# An exact slot ID or known original basename wins over its header.
			var stem := normalize(relative.get_file().get_basename())
			ids = _aliases.get(stem, [])
			priority = 2
			if ids.size() != 1:
				var exact: Array = []
				var length := int(info.get("bytes", 0))
				if _original_sizes.has(length) and _hash_bytes + length <= MAX_HASH_BYTES:
					_hash_bytes += length
					exact = _fingerprints.get(FileAccess.get_sha256(path), [])
				if exact.size() == 1:
					ids = exact
				elif ids.is_empty():
					ids = _aliases.get(normalize(str(info.get("title", ""))), [])
					priority = 1
		if ids.size() > 1 and priority != 3:
			issues.append("Mehrdeutiger Titel: %s (overrides.json verwenden)" % relative)
			ids = []
		if ids.is_empty():
			var user_id := "user_mod_" + relative.sha256_text().left(20)
			record.id = user_id
			extras[user_id] = record
		else:
			for id: String in ids:
				if not _candidates.has(id):
					_candidates[id] = []
				_candidates[id].append({"priority": priority, "record": record})
	for id: String in _candidates:
		var candidates: Array = _candidates[id]
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.priority) > int(b.priority))
		if candidates.size() > 1 and candidates[0].priority == candidates[1].priority:
			issues.append("Mehrere MODs für %s: Fallback aktiv (overrides.json verwenden)" % id)
			continue
		matches[id] = candidates[0].record
	return report()


func report() -> Dictionary:
	return {"scanned": scanned, "matched": matches.size(), "personal": extras.size(),
		"issues": issues.duplicate()}


func _mapping(directory: String) -> Dictionary:
	var path := directory.path_join("overrides.json")
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_MAPPING_BYTES:
		issues.append("overrides.json ist unlesbar oder größer als 64 KiB.")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		issues.append("overrides.json muss ein JSON-Objekt aus ID und Dateiname sein.")
		return {}
	return parsed


func _collect(directory: String, relative: String, depth: int, files: Array[String]) -> void:
	if _visited_dirs >= 128 or files.size() >= MAX_FILES:
		if "Ordnerlimit erreicht (128 Ordner / 1024 Dateien)." not in issues:
			issues.append("Ordnerlimit erreicht (128 Ordner / 1024 Dateien).")
		return
	_visited_dirs += 1
	var dir := DirAccess.open(directory.path_join(relative))
	if dir == null:
		return
	# Reject symlinks so recursion and explicit paths stay inside this library.
	var names := dir.get_files()
	names.sort()
	for name: String in names:
		if files.size() >= MAX_FILES:
			if "Maximal 1024 MOD-Dateien je Scan." not in issues:
				issues.append("Maximal 1024 MOD-Dateien je Scan.")
			return
		if name.get_extension().to_lower() == "mod" and not dir.is_link(name):
			files.append(relative.path_join(name) if relative != "" else name)
	if depth >= MAX_DEPTH:
		return
	var directories := dir.get_directories()
	directories.sort()
	for name: String in directories:
		if not name.begins_with(".") and not dir.is_link(name):
			_collect(directory, relative.path_join(name), depth + 1, files)


static func normalize(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		if character >= "a" and character <= "z" or character >= "0" and character <= "9":
			result += character
	return result
