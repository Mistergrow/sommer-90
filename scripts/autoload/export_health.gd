extends Node

## Fast release-only sentinel check. The exhaustive check is performed by
## tools/export_windows_release.sh against the generated PCK. This lightweight
## guard prevents a broken hand export from failing silently on a player's PC.

const SENTINEL_AUDIO := "res://assets/audio/sfx/SFX_KEY_CLICK_V01.ogg"
const SENTINEL_FONT := "res://assets/fonts/VT323-Regular.ttf"
const FULL_SENTINEL_MOD := "res://assets/audio/soundtrack/sommerfenster.mod"
const DEMO_SENTINEL_MOD := FULL_SENTINEL_MOD
const FULL_SENTINEL_COVER := "res://assets/software/syndicate/box_front.png"
const DEMO_SENTINEL_COVER := "res://assets/software/air_strike_usa/box_front.png"
const SENTINEL_MAP := "res://assets/backgrounds/layers/FOLDING_TOWN_MAP_MASTER_V01.png"
const SENTINEL_SHOP := "res://assets/backgrounds/locations/LOCATION_COMPUTER_SHOP_MASTER_V01.png"
const SENTINEL_KIOSK := "res://assets/backgrounds/locations/LOCATION_KIOSK_MASTER_V02.png"
const SENTINEL_KIOSK_PRODUCT := "res://assets/backgrounds/layers/KIOSK_CAPRI_SONNE_ORANGE_1990_V01.png"
const SENTINEL_MAGAZINE := "res://assets/ui/magazines/amiga_joker/1990/amiga_joker_1990_06_07_turrican.png"
const SENTINEL_COLLECTION_BOX := "res://assets/backgrounds/layers/GAME_WHITE_BIGBOX_MASTER_V01.png"
const SENTINEL_COLLECTION_CABINET := "res://assets/backgrounds/layers/ROOM_GAME_DISPLAY_CABINET_MASTER_V01.png"
const SENTINEL_REVERSE_ROOM := "res://assets/backgrounds/layers/ROOM_REVERSE_MASTER_1992_V01.png"
const SENTINEL_1084S_REAR := "res://assets/backgrounds/layers/MONITOR_COMMODORE_1084S_REAR_V01.png"
const SENTINEL_1901_REAR := "res://assets/backgrounds/layers/MONITOR_COMMODORE_1901_REAR_V01.png"
const MANIFEST := "res://export_runtime_manifest.json"
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const BuildChannel := preload("res://scripts/core/build_channel.gd")
const FULL_MIN_SOFTWARE_FILES := 3700
const DEMO_MIN_SOFTWARE_FILES := 1700

var healthy := true
var problems: Array[String] = []


func _ready() -> void:
	if OS.has_feature("editor") and OS.get_environment("SOMMER90_RELEASE_AUDIT") != "1":
		return
	for autoload_name: String in ["GameManager", "UIManager", "RoomManager", "TownManager", "DiskManager"]:
		if get_node_or_null("/root/" + autoload_name) == null:
			problems.append("Kernsystem %s" % autoload_name)
	_check_file("Musikkatalog", "res://data/music.json")
	_check_soundtrack()
	_check_file("Tracker-Musik", _sentinel_mod())
	var sentinel_cover := _sentinel_cover()
	_check_file("Software-Cover", sentinel_cover)
	_check_file("Exportmanifest", MANIFEST)
	_check_runtime_manifest()
	if RuntimeImages.texture(SENTINEL_MAP, 1600) == null:
		problems.append("Stadtkarte")
	if RuntimeImages.texture(sentinel_cover, 512, true) == null:
		problems.append("Software-Cover-Dekoder")
	for label_and_path: Array in [
		["Computerladen-Hintergrund", SENTINEL_SHOP],
		["Kiosk-Hintergrund", SENTINEL_KIOSK],
		["Kiosk-Produktbilder", SENTINEL_KIOSK_PRODUCT],
		["Kiosk-Magazine", SENTINEL_MAGAZINE],
		["Sammler-Bigbox", SENTINEL_COLLECTION_BOX],
		["Sammlervitrine", SENTINEL_COLLECTION_CABINET],
		["Zimmer-Gegenansicht", SENTINEL_REVERSE_ROOM],
		["1084S-Rückseite", SENTINEL_1084S_REAR],
		["1901-Rückseite", SENTINEL_1901_REAR],
	]:
		if RuntimeImages.texture(str(label_and_path[1]), 1600) == null:
			problems.append(str(label_and_path[0]))
	if not ResourceLoader.exists(SENTINEL_AUDIO) or ResourceLoader.load(SENTINEL_AUDIO) == null:
		problems.append("Soundeffekte")
	if not ResourceLoader.exists(SENTINEL_FONT) or ResourceLoader.load(SENTINEL_FONT) == null:
		problems.append("Pixelschrift")
	for bus_name: String in ["Music", "Ambient", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			problems.append("Audiobus %s" % bus_name)
	healthy = problems.is_empty()
	if healthy:
		print("[Release] Paketpruefung OK | Audio: %s | %d Busse" % [
			AudioServer.get_driver_name(), AudioServer.bus_count])
		_schedule_audit_exit()
		return
	var message := "Release-Paket unvollstaendig: %s" % ", ".join(problems)
	push_error("[Release] %s" % message)
	var ui := get_node_or_null("/root/UIManager")
	if ui != null and ui.has_method("toast"):
		ui.call_deferred("toast", "FEHLER: %s. Bitte Build neu exportieren." % message)
	_schedule_audit_exit()


func _check_soundtrack() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/soundtrack.json"))
	if not manifest is Dictionary or not manifest.get("tracks", null) is Array:
		problems.append("Soundtrack-Herkunftsmanifest")
		return
	var allowed: Dictionary = {}
	for entry: Dictionary in manifest.tracks:
		var path := str(entry.get("file", ""))
		if not path.begins_with("res://assets/audio/soundtrack/") \
				or not FileAccess.file_exists(path) \
				or FileAccess.get_sha256(path) != str(entry.get("sha256", "")):
			problems.append("Soundtrack-Prüfsumme: %s" % path)
		allowed[path] = true
	if allowed.is_empty():
		problems.append("Leerer Soundtrack")
	if OS.has_feature("sommer90_production") or OS.has_feature("itch_demo"):
		var packed: Dictionary = {}
		_check_packed_music("res://", allowed, packed)
		if packed.size() != allowed.size():
			problems.append("Soundtrack-Paketinventar")
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/music.json"))
	if catalog is Dictionary:
		for entry: Dictionary in catalog.get("tracks", []):
			if not allowed.has(str(entry.get("file", ""))):
				problems.append("Nicht belegte Musikdatei: %s" % entry.get("id", ""))
	for path: String in ["res://assets/audio/music/MUS_SPACE_DEBRIS_V01.mod",
		"res://development/uncleared_music/MUS_SPACE_DEBRIS_V01.mod"]:
		if FileAccess.file_exists(path) and not OS.has_feature("editor"):
			problems.append("Ungeklärte Originalmusik im Paket")


func _check_packed_music(path: String, allowed: Dictionary, packed: Dictionary) -> void:
	for file: String in DirAccess.get_files_at(path):
		if file.get_extension().to_lower() == "mod":
			var logical := path.path_join(file)
			packed[logical] = true
			if not allowed.has(logical):
				problems.append("Nicht belegter MOD im Paket: %s" % logical)
	for directory: String in DirAccess.get_directories_at(path):
		_check_packed_music(path.path_join(directory), allowed, packed)


func _schedule_audit_exit() -> void:
	if OS.get_environment("SOMMER90_RELEASE_AUDIT_EXIT") == "1":
		_finish_audit.call_deferred()


func _finish_audit() -> void:
	# Nicht per --quit-after mitten im Aufbau abbrechen: erst Szenen und die
	# wenigen statischen GPU-Caches lösen, dann der Engine Zeit für queue_free
	# geben. Insbesondere müssen alle Thread-Loads des echten Startbildschirms
	# abgeschlossen sein; ein Abbruch währenddessen hinterlässt RefCounted-Jobs.
	var startup_deadline := Time.get_ticks_msec() + 20_000
	while Time.get_ticks_msec() < startup_deadline and _startup_still_active():
		await get_tree().process_frame
	var ui := get_node_or_null("/root/UIManager")
	if ui != null and ui.has_method("close_all_windows"):
		ui.call("close_all_windows")
	var music := get_node_or_null("/root/MusicManager")
	if music != null and music.has_method("stop"):
		music.call("stop")
	for manager_path: String in ["/root/AudioManager", "/root/AmbientManager"]:
		var audio := get_node_or_null(manager_path)
		if audio != null and audio.has_method("release_audio"):
			audio.call("release_audio")
	# Audio- und Loader-Threads quittieren ihr letztes Playback/RefCounted nicht
	# zwingend im selben (bei --headless extrem kurzen) Frame.
	await get_tree().create_timer(0.50).timeout
	var current := get_tree().current_scene
	if current != null:
		current.queue_free()
		# queue_free beendet weder _process noch laufende Warmup-Coroutinen
		# sofort. Erst den Szenenabbau abwarten, sonst können diese nach dem
		# Leeren der Caches noch einmal neue Renderer-Ressourcen erzeugen.
		await current.tree_exited
		await get_tree().process_frame
	RuntimeImages.clear_cache()
	RoomAssets.clear_runtime_cache()
	var cursor := get_node_or_null("/root/CursorManager")
	if cursor != null and cursor.has_method("release_cursor"):
		cursor.call("release_cursor")
	await get_tree().create_timer(1.00).timeout
	# Der asynchrone Audit muss erst vollständig zurückkehren; ein quit() direkt
	# aus seinem letzten Await lässt unter Godot 4.8.dev2 gelegentlich (beobachtet vor dem Wechsel auf 4.7.2) genau
	# seinen eigenen RefCounted-Funktionszustand im ObjectDB-Audit stehen.
	get_tree().call_deferred("quit", 0 if healthy else 1)


func _startup_still_active() -> bool:
	for child: Node in get_tree().root.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("/startup_loader.gd"):
			return true
	return false


func _check_file(label: String, path: String) -> void:
	if not FileAccess.file_exists(path):
		problems.append(label)


func _check_runtime_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		problems.append("Exportmanifest unlesbar")
		return
	var manifest: Dictionary = parsed
	var demo := BuildChannel.is_first_year_demo()
	var expected_channel := BuildChannel.ITCH_DEMO_CHANNEL if demo else BuildChannel.FULL_CHANNEL
	if str(manifest.get("channel", "full")) != expected_channel:
		problems.append("Exportmanifest gehoert zum falschen Buildkanal")
		return
	var packed := int(manifest.get("software_file_count", -1))
	var source := int(manifest.get("software_source_file_count", -2))
	var all_source := int(manifest.get("software_all_source_file_count", source))
	var excluded := int(manifest.get("software_excluded_file_count", 0))
	var failures: Array = manifest.get("read_failures", [])
	var minimum := DEMO_MIN_SOFTWARE_FILES if demo else FULL_MIN_SOFTWARE_FILES
	if packed < minimum or packed != source or not failures.is_empty():
		problems.append("Software-Artwork unvollständig (%d/%d)" % [packed, source])
		return
	if demo and (excluded <= 0 or source >= all_source):
		problems.append("Demo enthaelt ungefiltertes Vollversions-Artwork")
		return
	if not demo and (excluded != 0 or source != all_source):
		problems.append("Vollversion enthaelt nur Demo-Artwork")
		return
	var paths: Array = manifest.get("software_files", [])
	if paths.size() != packed:
		problems.append("Software-Manifest widersprüchlich (%d/%d)" % [paths.size(), packed])
		return
	var missing := 0
	for value: Variant in paths:
		if not FileAccess.file_exists(str(value)):
			missing += 1
	if missing > 0:
		problems.append("Software-Artwork fehlt im Paket (%d Dateien)" % missing)


func _sentinel_cover() -> String:
	return DEMO_SENTINEL_COVER if BuildChannel.is_first_year_demo() else FULL_SENTINEL_COVER


func _sentinel_mod() -> String:
	return DEMO_SENTINEL_MOD if BuildChannel.is_first_year_demo() else FULL_SENTINEL_MOD
