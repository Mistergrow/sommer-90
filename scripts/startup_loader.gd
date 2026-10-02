class_name StartupLoader
extends Control
## Echter Boot-/RAM-Warmup vor dem Hauptmenü. Ressourcen werden über Godots
## Threaded Loader vorbereitet; physische Softwaregrafiken benutzen denselben
## begrenzten Composer-Cache wie Shop, Flohmarkt und Sammlervitrine.

const MAIN_SCENE := "res://scenes/Main.tscn"
const SoftwareVisualWarmupScript := preload("res://scripts/gfx/software_visual_warmup.gd")
const LoadingScreenVisualScript := preload("res://scripts/ui/loading_screen_visual.gd")
const RoomDepthMapScript := preload("res://scripts/gfx/room_depth_map.gd")

const RESOURCE_JOBS: Array[Dictionary] = [
	{"path": MAIN_SCENE, "label": "Benutzeroberfläche verbinden"},
	{"path": "res://assets/ui/loading/SOMMER90_LOADING_MASTER_V01.png", "label": "Ladebild im Arbeitsspeicher halten"},
	{"path": "res://assets/fonts/VT323_UI.ttf", "label": "Pixelschrift einsetzen"},
	{"path": "res://shaders/crt.gdshader", "label": "Bildröhre kalibrieren"},
	{"path": "res://shaders/room_depth_25d.gdshader", "label": "Raumtiefe berechnen"},
	{"path": "res://shaders/location_25d.gdshader", "label": "Perspektive vorbereiten"},
	{"path": "res://shaders/material_variants.gdshader", "label": "Materialien einlesen"},
	{"path": "res://assets/backgrounds/layers/ROOM_EMPTY_SHELVES_MASTER_V02.png", "label": "Zimmer-Master in den RAM laden"},
	{"path": "res://assets/backgrounds/layers/ROOM_DESK_MASTER_V02.png", "label": "Schreibtisch zusammensetzen"},
	{"path": "res://assets/backgrounds/layers/MONITOR_COMMODORE_1084S_V02.png", "label": "Monitor bereitstellen"},
	{"path": "res://assets/backgrounds/layers/COMPUTER_AMIGA500_V02.png", "label": "Amiga bereitstellen"},
	{"path": "res://assets/backgrounds/layers/MOUSE_AMIGA_V02.png", "label": "Maus anschließen"},
	{"path": "res://assets/backgrounds/layers/DESK_LAMP_CLASSIC_V01.png", "label": "Schreibtischlicht vorbereiten"},
	{"path": "res://assets/backgrounds/layers/JOYSTICK_COMPETITION_PRO_V01.png", "label": "Joystick prüfen"},
	{"path": "res://assets/backgrounds/layers/STEREO_COMPACT_CASSETTE_V01.png", "label": "Stereoanlage puffern"},
	{"path": "res://assets/backgrounds/layers/DISKBOX_12_SMOKED_V02.png", "label": "Diskettenbox bereitstellen"},
	{"path": "res://assets/backgrounds/layers/TELEPHONE_MASTER_V02.png", "label": "Telefon bereitstellen"},
	{"path": "res://assets/backgrounds/layers/MAGAZINE_MASTER_V02.png", "label": "Magazinmaster vorbereiten"},
	{"path": "res://assets/ui/games/turbo_kart/stunt_title_background_v01.png", "label": "Turbo-Stunt-Titelbild in den RAM laden"},
	{"path": "res://assets/ui/games/space_lemming/title_background_v01.png", "label": "Space-Lemming-Titelbild in den RAM laden"},
	{"path": "res://assets/ui/games/space_lemming/mission_background_v01.png", "label": "Space-Lemming-Missionsdeck vorbereiten"},
	{"path": "res://assets/ui/games/space_lemming/crew_walk_runtime_atlas_v02.png", "label": "Space-Lemming-Laufphasen in den RAM laden"},
	{"path": "res://assets/ui/games/space_lemming/crew_actions_runtime_atlas_v02.png", "label": "Space-Lemming-Aktionsphasen vorbereiten"},
	{"path": "res://assets/ui/games/space_lemming/intro_distress_background_v01.png", "label": "Space-Lemming-Notrufszene vorbereiten"},
	{"path": "res://assets/ui/games/space_lemming/airlock_runtime_atlas_v01.png", "label": "Space-Lemming-Luftschleusen vorbereiten"},
	{"path": "res://assets/ui/games/space_lemming/catwalk_material_v01.png", "label": "Space-Lemming-Laufstege vorbereiten"},
	{"path": "res://assets/ui/games/code_red/title_background_v02.png", "label": "CODE-RED-Titelbild in den RAM laden"},
	{"path": "res://assets/ui/games/code_red/summit_background_v01.png", "label": "CODE-RED-Gipfel vorbereiten"},
	{"path": "res://assets/ui/games/code_red/geo_dashboard_blank_v03.png", "label": "CODE-RED-GEO-Konsole vorbereiten"},
	{"path": "res://assets/ui/games/code_red/ending_victory_v01.png", "label": "CODE-RED-Endberichte puffern"},
	{"path": "res://assets/ui/games/code_red/ending_mixed_v01.png", "label": "CODE-RED-Endberichte puffern"},
	{"path": "res://assets/ui/games/code_red/ending_chaos_v01.png", "label": "CODE-RED-Endberichte puffern"},
	{"path": "res://assets/ui/games/code_red/dashboard_background_v01.png", "label": "CODE-RED-Lagezentrum laden"},
	{"path": "res://assets/ui/games/code_red/media_background_v01.png", "label": "CODE-RED-Medienzentrale laden"},
	{"path": "res://assets/ui/games/code_red/science_background_v01.png", "label": "CODE-RED-Bahnrechner laden"},
	{"path": "res://assets/ui/games/code_red/projects_background_v01.png", "label": "CODE-RED-Projekte laden"},
	{"path": "res://assets/ui/games/code_red/optics_background_v01.png", "label": "CODE-RED-Nebensonnenlabor laden"},
	{"path": "res://assets/ui/games/code_red/cabinet_background_v01.png", "label": "CODE-RED-Beraterkabinett laden"},
	{"path": "res://assets/ui/games/code_red/sky_archive_background_v01.png", "label": "CODE-RED-Himmelsarchiv laden"},
	{"path": "res://assets/ui/games/code_red/strange_sky_background_v01.png", "label": "CODE-RED-Himmelsereignisse puffern"},
	{"path": "res://assets/ui/games/code_red/squatter_sky_background_v01.png", "label": "CODE-RED-Z-Pinch-Szene puffern"},
	{"path": "res://assets/ui/games/code_red/plasma_discharge_background_v01.png", "label": "CODE-RED-Plasmafinale puffern"},
	{"path": "res://assets/backgrounds/layers/FLOPPY_35_DD_BLUE_FRONT_V01.png", "label": "Diskettenpuffer füllen"},
	{"path": "res://assets/backgrounds/layers/COFFEE_MUG_BEIGE_V01.png", "label": "Zimmerdetails laden"},
	{"path": "res://assets/backgrounds/layers/NOTEBOOK_OPEN_V01.png", "label": "Notizbuch bereitlegen"},
	{"path": "res://assets/backgrounds/layers/AMIGA_POWER_SUPPLY_MASTER_V01.png", "label": "Stromversorgung prüfen"},
	{"path": "res://assets/backgrounds/story_props/STARTER_CARTON_CLOSED_V01.png", "label": "Vaters Karton bereitstellen"},
	{"path": "res://assets/backgrounds/story_props/STARTER_CARTON_OPEN_V01.png", "label": "Quest-Requisiten puffern"},
]

const LOAD_START := 0.06
const LOAD_END := 0.54
const RENDER_END := 0.68
const SOFTWARE_END := 0.93
const MIN_SCREEN_TIME := 1.65
const RESOURCE_LOAD_TIMEOUT_MSEC := 120_000
## Der Bootscreen gibt dem verteilten Composer einen Vorsprung, wartet aber
## nicht auf das komplette, kontextabhaengige Softwarearchiv. Die unverarbeitete
## Queue wird zusammen mit ihren Caches an Main uebergeben.
const SOFTWARE_BOOT_BUDGET_MSEC := 6_000
const RAW_WARMUP_FILES: Array[String] = [
	"res://assets/software/code_red_protocol/manual_cover.png",
	"res://assets/software/code_red_protocol/manual_back.png",
	"res://assets/software/code_red_protocol/orbit_chart_front.png",
	"res://assets/software/code_red_protocol/orbit_chart_back.png",
]
## `ResourceLoader` dekodiert Texturen in den RAM, lädt sie aber noch nicht
## zwingend auf die GPU. Das große Zimmermaster verursachte deshalb erst NACH
## dem Klick auf »Neues Spiel« die teuerste Spitze. Nur die unmittelbar für den
## Startort nötigen Texturen werden einmal hinter dem Boot-Artwork gezeichnet;
## CODE-RED-/Minigame-Grafiken bleiben bewusst RAM-only, damit VRAM nicht
## unnötig mit selten gleichzeitig sichtbaren Vollbildern belegt wird.
const RENDER_WARM_PATHS: Array[String] = [
	"res://assets/backgrounds/layers/ROOM_EMPTY_SHELVES_MASTER_V02.png",
	"res://assets/backgrounds/layers/ROOM_DESK_MASTER_V02.png",
	"res://assets/backgrounds/layers/MONITOR_COMMODORE_1084S_V02.png",
	"res://assets/backgrounds/layers/COMPUTER_AMIGA500_V02.png",
	"res://assets/backgrounds/layers/MOUSE_AMIGA_V02.png",
	"res://assets/backgrounds/layers/DESK_LAMP_CLASSIC_V01.png",
	"res://assets/backgrounds/layers/JOYSTICK_COMPETITION_PRO_V01.png",
	"res://assets/backgrounds/layers/STEREO_COMPACT_CASSETTE_V01.png",
	"res://assets/backgrounds/layers/DISKBOX_12_SMOKED_V02.png",
	"res://assets/backgrounds/layers/TELEPHONE_MASTER_V02.png",
	"res://assets/backgrounds/layers/MAGAZINE_MASTER_V02.png",
	"res://assets/backgrounds/layers/FLOPPY_35_DD_BLUE_FRONT_V01.png",
	"res://assets/backgrounds/layers/COFFEE_MUG_BEIGE_V01.png",
	"res://assets/backgrounds/layers/NOTEBOOK_OPEN_V01.png",
	"res://assets/backgrounds/layers/AMIGA_POWER_SUPPLY_MASTER_V01.png",
]

var _font: Font
var _status_label: Label
var _detail_label: Label
var _counter_label: Label
var _tip_label: Label
var _target_progress := 0.0
var _shown_progress := 0.0
var _time := 0.0
var _started_msec := 0
var _resident_resources: Array[Resource] = []
var _resident_raw: Dictionary = {}
var _main_scene: PackedScene = null
var _warmer: Node = null
var _failed_paths: Array[String] = []
var _loading_visual: Control = null
var _render_warm_stage: Control = null


func _ready() -> void:
	name = "Startup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4090
	get_node("/root/CursorManager").call("hide_cursor")
	_font = load("res://assets/fonts/VT323_UI.ttf")
	_build_labels()
	_loading_visual = LoadingScreenVisualScript.new()
	_loading_visual.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_visual.z_as_relative = false
	_loading_visual.z_index = 4095
	add_child(_loading_visual)
	resized.connect(_layout_labels)
	_layout_labels()
	_started_msec = Time.get_ticks_msec()
	set_process(true)
	_run_startup.call_deferred()


func _process(delta: float) -> void:
	_time += minf(maxf(delta, 0.0), 0.1)
	# Der sichtbare Balken folgt ausschließlich dem echten Zielwert. Das Abfedern
	# glättet nur Thread-Sprünge und kann die tatsächliche Arbeit nie überholen.
	var follow := 1.0 - exp(-delta * 7.5)
	_shown_progress = minf(_target_progress,
		lerpf(_shown_progress, _target_progress, follow) + delta * 0.015)
	_counter_label.text = Loc.t("misc.startup_loader.3d", "%3d %%") % roundi(_shown_progress * 100.0)
	if _loading_visual != null:
		_loading_visual.set("progress", _shown_progress)
	queue_redraw()


func _build_labels() -> void:
	_status_label = _label("SYSTEMSTART", 30, Color(1.0, 0.73, 0.24))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_status_label)
	_detail_label = _label("Speicherprüfung …", 21, Color(0.65, 0.88, 1.0))
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_detail_label)
	_counter_label = _label("  0 %", 28, Color(1.0, 0.88, 0.46))
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_counter_label)
	_tip_label = _label("BITTE NICHT AUSSCHALTEN", 18, Color(0.46, 0.57, 0.66))
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tip_label)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025, 0.95))
	return label


func _layout_labels() -> void:
	if _status_label == null:
		return
	var frame := _virtual_frame()
	var scale_value := frame.size.x / 1440.0
	_place_label(_status_label, frame, Rect2(330, 687, 520, 38), scale_value, 30)
	_place_label(_detail_label, frame, Rect2(330, 724, 700, 30), scale_value, 21)
	_place_label(_counter_label, frame, Rect2(1010, 687, 100, 38), scale_value, 28)
	_place_label(_tip_label, frame, Rect2(330, 764, 780, 28), scale_value, 18)


func _place_label(label: Label, frame: Rect2, virtual_rect: Rect2,
		scale_value: float, base_font_size: int) -> void:
	label.position = frame.position + virtual_rect.position * scale_value
	label.size = virtual_rect.size * scale_value
	label.add_theme_font_size_override("font_size", maxi(12, roundi(base_font_size * scale_value)))


func _run_startup() -> void:
	_set_phase(0.02, "SYSTEMSTART", "Speicher und Laufwerke prüfen")
	await get_tree().process_frame
	await get_tree().process_frame
	await _load_resident_resources()
	await _warm_start_room_renderer()
	await _warm_software_visuals()
	_warm_raw_files()
	_warm_title_music()
	if OS.get_environment("DSS_BOOT_HOLD") == "1":
		_target_progress = 0.76
		_shown_progress = minf(_shown_progress, _target_progress)
		_set_phase(0.76, "RAM-PRÜFUNG", "MCP-Sichtprüfung · echter Bootscreen-Haltepunkt")
		while is_inside_tree():
			await get_tree().process_frame
		return
	_set_phase(0.975, "SYSTEMSTART", "Szenenübergang vorbereiten")
	await get_tree().process_frame
	if _main_scene == null:
		_show_fatal_error("Main.tscn konnte nicht geladen werden.")
		return
	var minimum := 0.0 if OS.get_environment("DSS_BOOT_FAST") == "1" else MIN_SCREEN_TIME
	while float(Time.get_ticks_msec() - _started_msec) / 1000.0 < minimum:
		await get_tree().process_frame
	_set_phase(1.0, "STARTKLAR", "Alle Startressourcen liegen im Arbeitsspeicher")
	while _shown_progress < 0.992:
		await get_tree().process_frame
	await get_tree().create_timer(0.12).timeout
	_enter_main_menu()


func _load_resident_resources() -> void:
	var total := RESOURCE_JOBS.size()
	var pending: Dictionary = {}
	var finished := 0
	var deadline_msec := Time.get_ticks_msec() + RESOURCE_LOAD_TIMEOUT_MSEC
	# Alle unabhängigen Imports zuerst anmelden. Godots Worker-Pool kann große
	# Texturen damit parallel dekodieren; der Fortschritt bleibt der gemittelte
	# echte Thread-Status aller Jobs statt einer seriellen 20-Dateien-Warteschlange.
	for index in total:
		var job: Dictionary = RESOURCE_JOBS[index]
		var path := str(job.get("path", ""))
		var label := str(job.get("label", path.get_file()))
		if not ResourceLoader.exists(path):
			_failed_paths.append(path)
			finished += 1
			continue
		# Die Einstiegsszene ist selbst der Abhängigkeitsgraph für nahezu alle
		# UI-Skripte. Wenn sie gleichzeitig mit ihren eigenen Texturen im selben
		# Worker-Pool geladen wird, kann Godot beim ExtResource des Main-Skripts
		# einen noch laufenden Cache-Eintrag erwischen und Main.tscn fälschlich als
		# unlesbar melden. Diesen kleinen, kritischen Graphen deshalb zuerst
		# synchron und vollständig auflösen; die schweren, unabhängigen Bilddaten
		# bleiben weiterhin parallelisiert.
		if path == MAIN_SCENE:
			var main_resource := ResourceLoader.load(path, "PackedScene",
				ResourceLoader.CACHE_MODE_REUSE)
			_remember_resource(path, main_resource)
			finished += 1
			continue
		var request_error := ResourceLoader.load_threaded_request(path, "", true,
			ResourceLoader.CACHE_MODE_REUSE)
		if request_error != OK and request_error != ERR_BUSY:
			var fallback: Resource = ResourceLoader.load(path)
			_remember_resource(path, fallback)
			finished += 1
			continue
		pending[path] = {"label": label, "index": index, "progress": [0.0]}
	while not pending.is_empty() and Time.get_ticks_msec() < deadline_msec:
		var partial_sum := 0.0
		var active_label := "Kernressourcen in den RAM laden"
		var active_index := total + 1
		var completed_paths: Array[String] = []
		for path_value: Variant in pending.keys():
			var path := str(path_value)
			var state: Dictionary = pending[path]
			var thread_progress: Array = state.get("progress", [0.0])
			var status := ResourceLoader.load_threaded_get_status(path, thread_progress)
			state["progress"] = thread_progress
			var item_progress := clampf(float(thread_progress[0]) \
				if not thread_progress.is_empty() else 0.0, 0.0, 1.0)
			partial_sum += item_progress
			if int(state.get("index", total)) < active_index:
				active_index = int(state.get("index", total))
				active_label = str(state.get("label", active_label))
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var resource: Resource = ResourceLoader.load_threaded_get(path)
				_remember_resource(path, resource)
				completed_paths.append(path)
			elif status == ResourceLoader.THREAD_LOAD_FAILED \
					or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_failed_paths.append(path)
				completed_paths.append(path)
		var aggregate := (float(finished) + partial_sum) / float(maxi(1, total))
		_set_phase(lerpf(LOAD_START, LOAD_END, clampf(aggregate, 0.0, 1.0)),
			"KERNRESSOURCEN", active_label)
		for path: String in completed_paths:
			pending.erase(path)
			finished += 1
		await get_tree().process_frame
	if not pending.is_empty():
		for path_value: Variant in pending.keys():
			var timed_out_path := str(path_value)
			_failed_paths.append(timed_out_path)
			ResourceLoader.load_threaded_get_status(timed_out_path)
		push_warning("Start-Warmup: %d Ressource(n) nach %d ms freigegeben." % [
			pending.size(), RESOURCE_LOAD_TIMEOUT_MSEC])
	_set_phase(LOAD_END, "KERNRESSOURCEN", "Kernressourcen sind resident")


## Übergibt die Startzimmer-Texturen wirklich dem Renderer. Ein bloßes
## ResourceLoader.load() hält nur die CPU-Ressource fest und verhindert keinen
## ersten GPU-Upload beim späteren add_child(). Die 8×8-Pixel-Bühne liegt hinter
## dem vollständig deckenden Ladebild, bleibt aber bis zum Main-Übergang aktiv.
func _warm_start_room_renderer() -> void:
	_set_phase(LOAD_END, "BILDPUFFER", "Kalibrierte Raumtiefe vorbereiten")
	# Die semantische 480×270-Tiefenkarte wurde früher erst beim Zimmeraufbau
	# pixelweise erzeugt. Ihre Geometrie ist statisch: einmal während des echten
	# Bootscreens erzeugen und für CPU + Shader gemeinsam resident halten.
	RoomDepthMapScript.base_texture()
	RoomDepthMapScript.desk_texture()
	await get_tree().process_frame
	_set_phase(LOAD_END + (RENDER_END - LOAD_END) * 0.10,
		"BILDPUFFER", "Startzimmer an den Renderer übertragen")
	_render_warm_stage = Control.new()
	_render_warm_stage.name = "StartRoomRenderWarmup"
	_render_warm_stage.position = Vector2.ZERO
	_render_warm_stage.size = Vector2(8, 8)
	_render_warm_stage.clip_contents = true
	_render_warm_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_render_warm_stage.z_as_relative = false
	_render_warm_stage.z_index = 4091
	add_child(_render_warm_stage)
	var resources_by_path: Dictionary = {}
	for resource: Resource in _resident_resources:
		if resource != null:
			resources_by_path[resource.resource_path] = resource
	var completed := 0
	var render_phase_start := LOAD_END + (RENDER_END - LOAD_END) * 0.10
	for path: String in RENDER_WARM_PATHS:
		var texture := resources_by_path.get(path) as Texture2D
		if texture != null:
			var rect := TextureRect.new()
			rect.texture = texture
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_SCALE
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.position = Vector2.ZERO
			rect.size = Vector2(8, 8)
			_render_warm_stage.add_child(rect)
		completed += 1
		_set_phase(lerpf(render_phase_start, RENDER_END,
			float(completed) / float(maxi(1, RENDER_WARM_PATHS.size()))),
			"BILDPUFFER", path.get_file().get_basename().capitalize())
		# Uploads werden in kleinen, sichtbaren Schritten eingereiht, statt alle
		# Renderer-Kommandos in den ersten Zimmerframe zu drücken.
		await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_sync()
	_set_phase(RENDER_END, "BILDPUFFER", "Startzimmer liegt im Videospeicher")


func _remember_resource(path: String, resource: Resource) -> void:
	if resource == null:
		_failed_paths.append(path)
		return
	_resident_resources.append(resource)
	if path == MAIN_SCENE and resource is PackedScene:
		_main_scene = resource as PackedScene


func _warm_software_visuals() -> void:
	_set_phase(RENDER_END, "SOFTWAREARCHIV", "Aktuelle OVPs und Disketten zusammensetzen")
	var deadline_msec := Time.get_ticks_msec() + SOFTWARE_BOOT_BUDGET_MSEC
	_warmer = SoftwareVisualWarmupScript.new()
	add_child(_warmer)
	# Explizit und billig enqueuen; der Composer selbst startet deferred und
	# damit nie innerhalb dieses Startup-Aufrufstacks.
	_warmer.call("request_current_context")
	var empty_frames := 0
	while (_warmer != null and is_instance_valid(_warmer)
			and Time.get_ticks_msec() < deadline_msec):
		var snapshot: Dictionary = _warmer.call("progress_snapshot")
		var completed := int(snapshot.get("completed", 0))
		var total := int(snapshot.get("total", 0))
		var running := bool(snapshot.get("running", false))
		var pending := int(snapshot.get("pending", 0))
		var ratio := float(completed) / float(maxi(1, total))
		var detail := str(snapshot.get("label", ""))
		if detail.is_empty():
			detail = "Softwaregrafiken im RAM ordnen"
		_set_phase(RENDER_END + (SOFTWARE_END - RENDER_END) * ratio,
			"SOFTWAREARCHIV", detail)
		if total == 0:
			empty_frames += 1
		else:
			empty_frames = 0
		if (total > 0 and not running and pending == 0 and completed >= total) or empty_frames >= 4:
			break
		await get_tree().process_frame
	var software_idle := _warmer == null or not is_instance_valid(_warmer) \
		or bool(_warmer.call("is_idle"))
	_set_phase(SOFTWARE_END, "SOFTWAREARCHIV",
		"Residenter Grafikcache ist bereit" if software_idle
		else "Restliche Softwaregrafiken werden verteilt vorbereitet")


func _warm_title_music() -> void:
	var track_id := str(MusicManager.title_track_id())
	var track: Dictionary = MusicManager.track(track_id)
	var path := str(track.get("file", ""))
	if not path.is_empty() and FileAccess.file_exists(path):
		# MODs sind absichtlich rohe Dateien und keine Godot-Resources. Der einmalige
		# Byte-Read wärmt OS-Dateicache und bleibt bis zum Menüübergang resident.
		_resident_raw[path] = FileAccess.get_file_as_bytes(path)


func _warm_raw_files() -> void:
	# Die vier CODE-RED-Druckbeilagen liegen wegen des riesigen Softwarearchivs
	# raw-first unter .gdignore. Ein einmaliger Byte-Read verhindert den ersten
	# sichtbaren Dateizugriff beim Aufschlagen; dekodiert wird weiter nur bei Bedarf.
	for path: String in RAW_WARMUP_FILES:
		if FileAccess.file_exists(path):
			_resident_raw[path] = FileAccess.get_file_as_bytes(path)


func _enter_main_menu() -> void:
	var main := _main_scene.instantiate() as Control
	if main == null:
		_show_fatal_error("Hauptmenü konnte nicht erzeugt werden.")
		return
	if _warmer != null and is_instance_valid(_warmer):
		remove_child(_warmer)
		_warmer.request_ready()
		main.add_child(_warmer)
	main.set_meta("startup_resident_resources", _resident_resources)
	main.set_meta("startup_raw_cache", _resident_raw)
	main.set_meta("startup_failed_paths", _failed_paths)
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	print("StartupLoader: %d Ressourcen + %d rohe Dateien resident · %d Fehler · %.2f s" % [
		_resident_resources.size(), _resident_raw.size(), _failed_paths.size(),
		float(Time.get_ticks_msec() - _started_msec) / 1000.0])
	# Startup bleibt für die kurze Überblendung als oberste Schwester sichtbar.
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.42)
	await tween.finished
	queue_free()


func _show_fatal_error(message: String) -> void:
	_target_progress = _shown_progress
	_status_label.text = Loc.t("misc.startup_loader.startfehler", "STARTFEHLER")
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.34, 0.28))
	_detail_label.text = message
	_tip_label.text = Loc.t("misc.startup_loader.bitte_installation_spieldateien_prufen", "Bitte Installation und Spieldateien prüfen.")
	get_node("/root/CursorManager").call("show_cursor")


func _set_phase(progress: float, status: String, detail: String) -> void:
	_target_progress = maxf(_target_progress, clampf(progress, 0.0, 1.0))
	_status_label.text = status
	_detail_label.text = detail
	_tip_label.text = _tip_for_progress(_target_progress)


func _tip_for_progress(progress: float) -> String:
	if progress < LOAD_START:
		return "BITTE NICHT AUSSCHALTEN"
	if progress < 0.38:
		return "CHIP-RAM · SZENEN · SCHRIFT"
	if progress < LOAD_END:
		return "ZIMMER · LICHT · PERSPEKTIVE"
	if progress < SOFTWARE_END:
		return "OVP · DISKETTEN · HANDBÜCHER"
	return "SOMMER 1990 WIRD VORBEREITET"


func _virtual_frame() -> Rect2:
	var virtual_size := Vector2(1440.0, 810.0)
	var scale_value := minf(size.x / virtual_size.x, size.y / virtual_size.y)
	var draw_size := virtual_size * scale_value
	return Rect2((size - draw_size) * 0.5, draw_size)


func _vrect(frame: Rect2, rect: Rect2) -> Rect2:
	var scale_value := frame.size.x / 1440.0
	return Rect2(frame.position + rect.position * scale_value, rect.size * scale_value)


func _vpoint(frame: Rect2, point: Vector2) -> Vector2:
	return frame.position + point * (frame.size.x / 1440.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.012, 0.024))
	var frame := _virtual_frame()
	var s := frame.size.x / 1440.0
	# Tief gestufter Pixelhimmel statt glattem Verlauf.
	for band in 18:
		var ratio := float(band) / 17.0
		var color := Color(0.018, 0.035, 0.075).lerp(Color(0.055, 0.026, 0.055), ratio)
		draw_rect(_vrect(frame, Rect2(0, band * 45, 1440, 46)), color)
	# Deterministische Datensterne/Dither: kein RNG-Flimmern zwischen Frames.
	for i in 118:
		var x := float((i * 173 + 67) % 1390 + 25)
		var y := float((i * 97 + 41) % 590 + 18)
		var pulse := 0.34 + 0.32 * sin(_time * (0.7 + float(i % 5) * 0.13) + float(i))
		var pixel_color := Color(0.30, 0.66, 0.92, pulse * 0.30) if i % 3 else Color(1.0, 0.63, 0.18, pulse * 0.34)
		draw_rect(_vrect(frame, Rect2(x, y, 2 if i % 7 else 4, 2)), pixel_color)
	# Bodenlicht und Schreibtisch-Silhouette.
	draw_colored_polygon(PackedVector2Array([
		_vpoint(frame, Vector2(280, 610)), _vpoint(frame, Vector2(1160, 610)),
		_vpoint(frame, Vector2(1330, 810)), _vpoint(frame, Vector2(110, 810))]),
		Color(0.08, 0.045, 0.035, 0.72))
	draw_rect(_vrect(frame, Rect2(310, 535, 820, 30)), Color(0.13, 0.068, 0.040))
	draw_rect(_vrect(frame, Rect2(330, 565, 55, 105)), Color(0.075, 0.040, 0.035))
	draw_rect(_vrect(frame, Rect2(1055, 565, 55, 105)), Color(0.075, 0.040, 0.035))
	# CRT-Gehäuse mit pixelgenauen Stufen und warmem Bodenschatten.
	draw_rect(_vrect(frame, Rect2(455, 100, 530, 330)), Color(0.0, 0.0, 0.0, 0.44))
	draw_rect(_vrect(frame, Rect2(468, 88, 504, 324)), Color(0.55, 0.49, 0.36))
	draw_rect(_vrect(frame, Rect2(480, 100, 480, 288)), Color(0.78, 0.70, 0.51))
	draw_rect(_vrect(frame, Rect2(507, 121, 426, 227)), Color(0.035, 0.045, 0.060))
	draw_rect(_vrect(frame, Rect2(517, 131, 406, 207)), Color(0.008, 0.035, 0.052))
	# Bildschirm-Copperbänder und Scanline.
	for band in 8:
		var y := 144.0 + float(band) * 22.0
		var c := Color(0.04 + band * 0.006, 0.16 + band * 0.012, 0.19 + band * 0.012, 0.82)
		draw_rect(_vrect(frame, Rect2(528, y, 384, 22)), c)
	var scan_y := 136.0 + fposmod(_time * 54.0, 194.0)
	draw_rect(_vrect(frame, Rect2(522, scan_y, 396, 3)), Color(0.55, 0.92, 1.0, 0.18))
	draw_string(_font, _vpoint(frame, Vector2(543, 177)), "SOMMER '90",
		HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(18, roundi(31.0 * s)),
		Color(0.67, 0.92, 1.0, 0.94))
	draw_string(_font, _vpoint(frame, Vector2(545, 203)), "WORKBENCH MEMORY LOADER",
		HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(12, roundi(15.0 * s)),
		Color(1.0, 0.69, 0.25, 0.82))
	# Pixelsonne + Stadtsilhouette als kleines erzählerisches Sommerbild.
	draw_rect(_vrect(frame, Rect2(827, 157, 30, 30)), Color(1.0, 0.72, 0.23, 0.82))
	for i in 16:
		var building_h := float(20 + (i * 17) % 62)
		draw_rect(_vrect(frame, Rect2(530 + i * 24, 328 - building_h, 20, building_h)),
			Color(0.018, 0.055, 0.072, 0.96))
	# Wandernde Diskette: Position ist direkt an echten Ladefortschritt gekoppelt.
	var disk_x := lerpf(552.0, 840.0, _shown_progress)
	var disk_y := 211.0 + sin(_time * 4.0) * 5.0
	_draw_floppy(frame, Vector2(disk_x, disk_y), s)
	# Power-LED, Laufwerk und Monitorbedienung.
	draw_rect(_vrect(frame, Rect2(514, 367, 72, 8)), Color(0.16, 0.14, 0.10))
	draw_rect(_vrect(frame, Rect2(872, 364, 9, 9)), Color(0.25, 1.0, 0.42, 0.78 + 0.2 * sin(_time * 3.0)))
	for i in 4:
		draw_rect(_vrect(frame, Rect2(894 + i * 12, 365, 8, 7)), Color(0.30, 0.27, 0.20))
	# Amiga/Keyboard-Silhouette mit einzelnen Tasten.
	draw_colored_polygon(PackedVector2Array([
		_vpoint(frame, Vector2(430, 432)), _vpoint(frame, Vector2(1010, 432)),
		_vpoint(frame, Vector2(1062, 527)), _vpoint(frame, Vector2(378, 527))]),
		Color(0.64, 0.58, 0.44))
	draw_colored_polygon(PackedVector2Array([
		_vpoint(frame, Vector2(446, 445)), _vpoint(frame, Vector2(994, 445)),
		_vpoint(frame, Vector2(1027, 507)), _vpoint(frame, Vector2(413, 507))]),
		Color(0.18, 0.17, 0.15))
	for row in 4:
		for col in 20:
			var key_x := 434.0 + col * 27.0 + (row % 2) * 5.0
			var key_y := 452.0 + row * 13.0
			draw_rect(_vrect(frame, Rect2(key_x, key_y, 19, 8)), Color(0.63, 0.59, 0.48))
	# Segmentierter, tatsächlich datengetriebener Fortschrittsbalken.
	var bar := Rect2(330, 645, 780, 25)
	draw_rect(_vrect(frame, Rect2(bar.position - Vector2(8, 8), bar.size + Vector2(16, 16))),
		Color(0.008, 0.014, 0.025, 0.94))
	draw_rect(_vrect(frame, Rect2(bar.position - Vector2(4, 4), bar.size + Vector2(8, 8))),
		Color(0.18, 0.45, 0.62, 0.74), false, maxf(1.0, 2.0 * s))
	var segments := 40
	for index in segments:
		var active := float(index + 1) / float(segments) <= _shown_progress + 0.0001
		var segment_color := Color(1.0, 0.63, 0.16) if index > 31 else Color(0.27, 0.78, 0.94)
		if not active:
			segment_color = Color(0.055, 0.095, 0.12)
		draw_rect(_vrect(frame, Rect2(bar.position.x + index * 19.5, bar.position.y,
			16.0, bar.size.y)), segment_color)
	# Dezente globale Scanlines schließen Bootscreen und Spieloptik zusammen.
	for y in range(0, 810, 4):
		draw_rect(_vrect(frame, Rect2(0, y, 1440, 1)), Color(0.0, 0.0, 0.0, 0.075))


func _draw_floppy(frame: Rect2, position_value: Vector2, scale_value: float) -> void:
	var body := Rect2(position_value, Vector2(54, 64))
	draw_rect(_vrect(frame, body), Color(0.12, 0.38, 0.72))
	draw_rect(_vrect(frame, Rect2(position_value + Vector2(8, 5), Vector2(38, 22))),
		Color(0.72, 0.79, 0.81))
	draw_rect(_vrect(frame, Rect2(position_value + Vector2(12, 34), Vector2(30, 24))),
		Color(0.91, 0.89, 0.72))
	draw_rect(_vrect(frame, Rect2(position_value + Vector2(35, 7), Vector2(7, 16))),
		Color(0.025, 0.07, 0.12))
	draw_rect(_vrect(frame, body), Color(0.50, 0.83, 1.0, 0.78), false,
		maxf(1.0, 2.0 * scale_value))
