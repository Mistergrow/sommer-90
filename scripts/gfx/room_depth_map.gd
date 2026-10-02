class_name RoomDepthMap
extends RefCounted
## Prozedurale, kalibrierte Tiefenwahrheit des Spielerzimmers.
##
## Anders als ein reiner Y-Verlauf erkennt diese Map Fenster/Wand, Vorhaenge,
## Regale, Heizkoerper, Boden, Schrank und Bett. Shader und CPU-Projektion
## verwenden exakt dasselbe Image; Hotspots, Kabel und Artwork koennen dadurch
## nicht auseinanderlaufen. Werte 0..1 werden zwischen FAR und NEAR gemischt.

const MASTER_SIZE := Vector2(1920.0, 1080.0)
const BASE_SIZE := Vector2i(480, 270)
const DESK_SIZE := Vector2i(544, 200)
const STRENGTH := 0.0072
const FAR_GAIN := 0.08
const DESK_GAIN := 0.35
const NEAR_GAIN := 0.95
const VERTICAL_GAIN := 0.48
const POINTER_GAIN := 0.62
const IDLE_GAIN := 0.045
const DEPTH_SHADER := preload("res://shaders/room_depth_25d.gdshader")
const SurfaceGeometryScript := preload("res://scripts/gfx/surface_geometry.gd")
const ObjectGeometryScript := preload("res://scripts/gfx/object_geometry.gd")

static var _base_image: Image
static var _desk_image: Image
static var _base_texture: ImageTexture
static var _desk_texture: ImageTexture


static func base_texture() -> Texture2D:
	if _base_texture == null:
		_base_texture = ImageTexture.create_from_image(base_image())
	return _base_texture


static func desk_texture() -> Texture2D:
	if _desk_texture == null:
		_desk_texture = ImageTexture.create_from_image(desk_image())
	return _desk_texture


static func base_image() -> Image:
	if _base_image != null:
		return _base_image
	_base_image = Image.create(BASE_SIZE.x, BASE_SIZE.y, false, Image.FORMAT_RF)
	for y in BASE_SIZE.y:
		var v := (float(y) + 0.5) / float(BASE_SIZE.y)
		for x in BASE_SIZE.x:
			var u := (float(x) + 0.5) / float(BASE_SIZE.x)
			var p := Vector2(u, v)
			# Wand/Fensternische ist die ruhige Fernebene; der Boden laeuft
			# perspektivisch bis unmittelbar vor die Kamera.
			var floor_mix := smoothstep(0.47, 0.60, v)
			var floor_depth := lerpf(0.22, 0.97, smoothstep(0.48, 1.0, v))
			var depth := lerpf(0.06, floor_depth, floor_mix)

			# Fensterblick liegt am weitesten hinten.
			depth = lerpf(depth, 0.01, _box_weight(p, Rect2(0.305, -0.02, 0.39, 0.51), 0.018))
			# Vorhaenge stehen deutlich vor dem Glas, aber hinter dem Tisch.
			depth = lerpf(depth, 0.27 + v * 0.13,
				maxf(_box_weight(p, Rect2(0.15, -0.02, 0.17, 0.64), 0.012),
					_box_weight(p, Rect2(0.69, -0.02, 0.15, 0.64), 0.012)))
			# Linkes hohes Regal: nicht nach Y als ferne Wand behandeln.
			depth = lerpf(depth, clampf(0.48 + v * 0.38, 0.48, 0.84),
				_box_weight(p, Rect2(-0.02, -0.02, 0.265, 0.93), 0.014))
			# Heizkoerper sitzt hinter dem Tisch, aber vor Fenster/Wand.
			depth = lerpf(depth, 0.22 + v * 0.18,
				_box_weight(p, Rect2(0.455, 0.47, 0.20, 0.27), 0.012))
			# Rechtes Wandbrett und Unterschrank.
			depth = lerpf(depth, 0.31,
				_box_weight(p, Rect2(0.785, 0.12, 0.18, 0.12), 0.01))
			depth = lerpf(depth, clampf(0.61 + (v - 0.46) * 0.48, 0.61, 0.86),
				_box_weight(p, Rect2(0.79, 0.45, 0.19, 0.49), 0.014))
			# Bettkante rechts ist echte Nahgeometrie.
			depth = lerpf(depth, clampf(0.86 + (v - 0.56) * 0.28, 0.86, 0.99),
				_box_weight(p, Rect2(0.905, 0.55, 0.115, 0.47), 0.012))
			_base_image.set_pixel(x, y, Color(depth, 0.0, 0.0, 1.0))
	# User-kalibrierte Architekturflächen überschreiben nur ihre Polygone. Die
	# bestehende handkuratierte Raumkarte bleibt überall sonst erhalten.
	_base_image = SurfaceGeometryScript.apply_to_depth_image("ROOM_MASTER", _base_image)
	_base_image = ObjectGeometryScript.apply_to_depth_image("ROOM_MASTER", _base_image)
	return _base_image


static func desk_image() -> Image:
	if _desk_image != null:
		return _desk_image
	_desk_image = Image.create(DESK_SIZE.x, DESK_SIZE.y, false, Image.FORMAT_RF)
	for y in DESK_SIZE.y:
		var v := (float(y) + 0.5) / float(DESK_SIZE.y)
		# d≈0.31 entspricht exakt dem starren DESK_GAIN 0.35. Die Platte
		# bleibt dadurch bei allen Props; nur Schuerze/Schubladen/Beine gewinnen
		# nach unten zusaetzliche Tiefe.
		var depth := 0.31
		if v > 0.28:
			depth = lerpf(0.31, 0.48, smoothstep(0.28, 0.55, v))
		if v > 0.55:
			depth = lerpf(0.48, 0.62, smoothstep(0.55, 1.0, v))
		for x in DESK_SIZE.x:
			_desk_image.set_pixel(x, y, Color(depth, 0.0, 0.0, 1.0))
	return _desk_image


static func sample_base(master_point: Vector2) -> float:
	var uv := Vector2(master_point.x / MASTER_SIZE.x, master_point.y / MASTER_SIZE.y)
	return SurfaceGeometryScript.sample_bilinear(base_image(), uv)


static func sample_desk(uv: Vector2) -> float:
	return SurfaceGeometryScript.sample_bilinear(desk_image(), uv)


static func gain_from_depth(depth: float) -> float:
	return lerpf(FAR_GAIN, NEAR_GAIN, clampf(depth, 0.0, 1.0))


## Standardpunkte auf der Tischhoehe bleiben am starren DESK-Plateau; explizite
## Base-Samples (Wetter/Staub/Regal) lesen immer die semantische Depthmap.
static func gain_at_master(master_point: Vector2, desk_range: Vector2,
		force_base := false) -> float:
	if not force_base and master_point.y >= desk_range.x - 55.0 \
			and master_point.y <= desk_range.y + 55.0:
		return DESK_GAIN
	return gain_from_depth(sample_base(master_point))


static func attach(rect: TextureRect, kind: String) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = DEPTH_SHADER
	var node_gain := FAR_GAIN
	if kind == "desk":
		mat.set_shader_parameter("depth_tex", desk_texture())
		node_gain = DESK_GAIN
	else:
		mat.set_shader_parameter("depth_tex", base_texture())
	mat.set_shader_parameter("strength", STRENGTH)
	mat.set_shader_parameter("far_gain", FAR_GAIN)
	mat.set_shader_parameter("near_gain", NEAR_GAIN)
	mat.set_shader_parameter("node_gain", node_gain)
	mat.set_shader_parameter("vertical_gain", VERTICAL_GAIN)
	rect.material = mat
	rect.set_meta("room_depth_warp", true)
	rect.set_meta("room_depth_warp_kind", kind)


static func set_material_look(material: Material, look: Vector2) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("look", look)


static func _box_weight(point: Vector2, box: Rect2, feather: float) -> float:
	var nearest := point.clamp(box.position, box.end)
	var outside := point.distance_to(nearest)
	if outside > 0.0:
		return 1.0 - smoothstep(0.0, feather, outside)
	var inside := minf(minf(point.x - box.position.x, box.end.x - point.x),
		minf(point.y - box.position.y, box.end.y - point.y))
	return smoothstep(0.0, feather, inside)
