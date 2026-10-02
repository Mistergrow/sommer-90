class_name LocationStage25D
extends Control
## Datengetriebene 2,5D-Kamera für alle fotografischen Nicht-Zimmer-Orte.
## Das Bild erhält einen vertikal gewichteten UV-Tiefenversatz; Hotspots lesen
## exakt dieselbe Offset-Funktion. Kein Gameplay- oder Save-Zustand.

const CONFIG_PATH := "res://data/location_25d.json"
const DEPTH_SHADER := preload("res://shaders/location_25d.gdshader")
const LifeScript := preload("res://scripts/gfx/location_life_25d.gd")
const SurfaceGeometryScript := preload("res://scripts/gfx/surface_geometry.gd")
const ObjectGeometryScript := preload("res://scripts/gfx/object_geometry.gd")
const SurfaceFxOverlayScript := preload("res://scripts/gfx/surface_fx_overlay.gd")

static var _profiles: Dictionary = {}
static var _loaded := false

var host: Control = null
var background: TextureRect = null
var profile: Dictionary = {}
var location_key := ""
var look := Vector2.ZERO
var _target := Vector2.ZERO
var _material: ShaderMaterial = null
var _life: Control = null
var _foreground: TextureRect = null
var _semantic_depth_image: Image = null
var _semantic_depth_texture: ImageTexture = null
var _surface_fx: Control = null
var _test_lock := false
var _last_projected_look := Vector2(INF, INF)
var _last_depth_enabled := false

const MAX_FRAME_DELTA := 1.0 / 30.0
const DEFAULT_RESPONSE := 2.45
const MAX_SCREEN_SPEED := 26.0  # Pixel/Sekunde inkl. verstaerkter Near-Plane


func configure(location: Control, bg: TextureRect, key: String, p: Dictionary) -> void:
	name = "LocationStage25D"
	host = location
	background = bg
	profile = p.duplicate(true)
	location_key = key
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Gleiche Basisebene wie Foto/LocationFx; die Einhaengereihenfolge lautet
	# Foto -> Stage (Life, Near-Plane) -> LocationFx -> Hotspots. So graden
	# Tageszeit/Vignette auch den Vordergrund und die Near-Plane bleibt nachts
	# nicht unnatuerlich hell.
	z_index = 0
	size = location.size


func _ready() -> void:
	if host == null or background == null or profile.is_empty():
		set_process(false)
		return
	_setup()
	if host.has_signal("resized"):
		host.resized.connect(_on_host_resized)


func _exit_tree() -> void:
	# Dynamische ImageTextures muessen vor dem RenderingServer freigegeben
	# werden. Das ist fuer normale Ortswechsel ebenso wichtig wie fuer
	# automatisierte Screenshot-Laeufe und verhindert GPU-RID-Leaks am Ende.
	release_gpu_resources()


func release_gpu_resources() -> void:
	if _material != null:
		_material.set_shader_parameter("semantic_depth", null)
		_material.set_shader_parameter("use_semantic_depth", false)
	if background != null and is_instance_valid(background):
		background.material = null
	_semantic_depth_texture = null
	_semantic_depth_image = null
	_material = null


static func profile_for(key: String) -> Dictionary:
	_load_profiles()
	var p: Variant = _profiles.get(key, null)
	return p.duplicate(true) if p is Dictionary else {}


static func all_profiles() -> Dictionary:
	_load_profiles()
	return _profiles.duplicate(true)


static func _load_profiles() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		var p: Variant = parsed.get("profiles", {})
		if p is Dictionary:
			_profiles = p


func _setup() -> void:
	_material = ShaderMaterial.new()
	_material.shader = DEPTH_SHADER
	_material.set_shader_parameter("horizon", float(profile.get("horizon", 0.44)))
	_material.set_shader_parameter("strength", float(profile.get("strength", 0.009)))
	_material.set_shader_parameter("far_gain", float(profile.get("far_gain", 0.18)))
	_material.set_shader_parameter("near_gain", float(profile.get("near_gain", 1.0)))
	_material.set_shader_parameter("vertical_gain", float(profile.get("vertical_gain", 0.45)))
	_material.set_shader_parameter("overscan", float(profile.get("overscan", 0.028)))
	if SurfaceGeometryScript.has_surfaces(location_key) or ObjectGeometryScript.has_depth_objects(location_key):
		_semantic_depth_image = SurfaceGeometryScript.location_depth_image(location_key, profile)
		_semantic_depth_image = ObjectGeometryScript.apply_to_depth_image(location_key, _semantic_depth_image)
		_semantic_depth_texture = ImageTexture.create_from_image(_semantic_depth_image)
		_material.set_shader_parameter("semantic_depth", _semantic_depth_texture)
		_material.set_shader_parameter("use_semantic_depth", true)
	else:
		_material.set_shader_parameter("use_semantic_depth", false)
	_surface_fx = SurfaceFxOverlayScript.new()
	_surface_fx.name = "SurfaceFxOverlay"
	_surface_fx.z_index = 0
	_surface_fx.call("configure", host, self, location_key)
	add_child(_surface_fx)
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.material = _material

	_life = LifeScript.new()
	_life.name = "LocationLife25D"
	_life.z_index = 0
	add_child(_life)
	_life.size = size
	_life.call("setup", location_key, profile)

	var fg_path := str(profile.get("foreground_asset", ""))
	if fg_path != "" and ResourceLoader.exists(fg_path):
		_foreground = TextureRect.new()
		_foreground.name = "LocationForeground25D"
		_foreground.texture = load(fg_path)
		_foreground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_foreground.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_foreground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_foreground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_foreground.z_index = 0
		add_child(_foreground)
		_layout_foreground(true)


func _process(delta: float) -> void:
	if host == null or background == null or not is_instance_valid(background):
		return
	var enabled := bool(SettingsManager.value("location_depth"))
	if not enabled:
		_target = Vector2.ZERO
	elif not _test_lock:
		_target = _pointer_target()
		var idle := float(profile.get("idle", 0.09))
		_target += Vector2(sin(Time.get_ticks_msec() * 0.00011 + location_key.hash()),
			cos(Time.get_ticks_msec() * 0.00009 + location_key.hash() * 0.5)) * idle
	# Große Mausbewegungen und kurze Frame-Hänger dürfen keinen einzelnen
	# Kamerasprung erzeugen. Exponentielle Dämpfung liefert die weiche Kurve;
	# das sichtbare Pixel-Tempolimit begrenzt zusätzlich ihren ersten Schritt.
	var motion_delta := minf(maxf(delta, 0.0), MAX_FRAME_DELTA)
	var response := float(profile.get("response", DEFAULT_RESPONSE))
	var desired := look.lerp(_target, 1.0 - exp(-motion_delta * response))
	var strongest_gain := float(profile.get("near_gain", 1.0)) \
		* maxf(1.0, float(profile.get("foreground_gain", 1.0)))
	var strongest_pixels_per_look := float(profile.get("strength", 0.009)) \
		* size.length() * strongest_gain
	var max_look_step := float(profile.get("max_screen_speed", MAX_SCREEN_SPEED)) \
		* motion_delta / maxf(strongest_pixels_per_look, 0.001)
	look = look.move_toward(desired, max_look_step)
	if look.length() < 0.0001:
		look = Vector2.ZERO
	var projected := look if enabled else Vector2.ZERO
	# Keine Quantisierungsschwelle: auch kleinste Subpixelbewegungen werden
	# fortgeschrieben und sammeln sich nicht zu einer sichtbaren Stufe auf.
	if not projected.is_equal_approx(_last_projected_look) or enabled != _last_depth_enabled:
		_material.set_shader_parameter("look", projected)
		_last_projected_look = projected
		_last_depth_enabled = enabled
		_layout_foreground(false)
		if host.has_method("_layout_hotspots"):
			host.call("_layout_hotspots")


func _pointer_target() -> Vector2:
	if host.size.x <= 1.0 or host.size.y <= 1.0:
		return Vector2.ZERO
	var p := host.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, host.size).has_point(p):
		return Vector2.ZERO
	var n := (p / host.size - Vector2(0.5, 0.5)) * 2.0
	var pointer := float(profile.get("pointer", 0.72))
	return Vector2(clampf(n.x, -1.0, 1.0), clampf(n.y, -1.0, 1.0) * 0.72) * pointer


## Bildschirm-Offset des sichtbaren Bildpunkts. LocationBase verwendet diese
## Funktion auch für den zugehörigen Hotspot — eine einzige Projektionswahrheit.
func offset_for_point(screen_point: Vector2) -> Vector2:
	if host == null or host.size.y <= 1.0 or not bool(SettingsManager.value("location_depth")):
		return Vector2.ZERO
	var y := clampf(screen_point.y / host.size.y, 0.0, 1.0)
	var overscan := float(profile.get("overscan", 0.028))
	# Shader sampelt den inneren UV-Bereich; dieselbe Remap-Gleichung hält
	# Weltpunkte/Hotspots mathematisch auf dem sichtbaren Motiv.
	y = (y - 0.5) * (1.0 - overscan * 2.0) + 0.5
	var horizon := float(profile.get("horizon", 0.44))
	var depth := smoothstep(horizon, 1.0, y)
	if _semantic_depth_image != null:
		var uv_x := clampf(screen_point.x / host.size.x, 0.0, 1.0)
		uv_x = (uv_x - 0.5) * (1.0 - overscan * 2.0) + 0.5
		depth = SurfaceGeometryScript.sample_bilinear(_semantic_depth_image,
			Vector2(uv_x, y))
	var gain := lerpf(float(profile.get("far_gain", 0.18)),
		float(profile.get("near_gain", 1.0)), depth)
	var sample_scale := 1.0 / maxf(1.0 - overscan * 2.0, 0.84)
	var off := look * float(profile.get("strength", 0.009)) * host.size * gain * sample_scale
	off.y *= float(profile.get("vertical_gain", 0.45))
	return off


func set_test_look(value: Vector2) -> void:
	_test_lock = true
	look = value
	_target = value
	if _material != null:
		_material.set_shader_parameter("look", look)


func clear_test_look() -> void:
	_test_lock = false


## Haengt eine sichtbare Weltfigur in die gemeinsame 2,5D-Buehne. Sie liegt
## hinter der transparenten Near-Plane, aber vor Foto/Lebenszeichen; der spaeter
## am Host eingehangene LocationFx-Stack graden und beleuchtet sie mit. Die
## eigentliche Klickflaeche bleibt als Host-Sibling ueber den Hotspots.
func add_world_visual(node: Control) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.reparent(self)
	else:
		add_child(node)
	node.z_index = 0
	if _foreground != null and is_instance_valid(_foreground):
		move_child(node, _foreground.get_index())


func _layout_foreground(full_layout: bool = false) -> void:
	if _foreground == null or not is_instance_valid(_foreground):
		return
	if full_layout:
		_foreground.pivot_offset = size * 0.5
		_foreground.size = size
		_foreground.scale = Vector2.ONE * float(profile.get("foreground_scale", 1.035))
	# Der Mittelpunkt-Pivot zentriert die Skalierung bereits; ein zusaetzlicher
	# negativer Half-Scale-Offset wuerde doppelt nach links/oben verschieben.
	_foreground.position = offset_for_point(Vector2(size.x * 0.5, size.y * 0.96)) \
		* float(profile.get("foreground_gain", 1.72))


func _on_host_resized() -> void:
	if host == null:
		return
	size = host.size
	if _life != null:
		_life.size = size
	_layout_foreground(true)
