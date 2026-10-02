extends FxLayer
## Tageszeit-Grading für einen Ort: multipliziert die ganze Ansicht je
## TimeManager-Slot mit einem Farbton (abdunkeln/verschieben) und blendet
## optional warme Lichtpools (Lampen, Fenster, Neon) additiv dazu.
##
## Config (data/location_fx.json, type "grading"):
##   "preset": "outdoor" | "indoor_warm" | "indoor_cool" | "overcast"
##   "tint":   optional Per-Slot-Override {"0":[r,g,b], ...}
##   "pools":  [ {"pos":[u,v], "radius":0.3, "color":[r,g,b],
##               "alpha":{"3":0.5,"4":0.8}} ]   (u,v,radius normiert auf Breite)

# Fertige Grading-Tabellen (Multiply-Farbe je Slot 0..4: Morgen..Nacht).
const ColorProfile := preload("res://scripts/gfx/scene_color_profile.gd")
const PRESETS := ColorProfile.PRESETS

var _grade: ColorRect = null
var _pools: Array = []      # [{node, alpha_spec}]
var _tween: Tween = null


func _apply() -> void:
	_grade = ColorRect.new()
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_material_blend(_grade, CanvasItemMaterial.BLEND_MODE_MUL)
	add_child(_grade)

	for p in cfg("pools", []):
		var pool := TextureRect.new()
		pool.texture = glow_texture()
		pool.stretch_mode = TextureRect.STRETCH_SCALE
		pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pool.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pool.modulate = to_color(p.get("color", [1.0, 0.82, 0.5]), Color(1.0, 0.82, 0.5))
		add_material_blend(pool, CanvasItemMaterial.BLEND_MODE_ADD)
		add_child(pool)
		_pools.append({"node": pool, "cfg": p})

	resized.connect(_layout)
	if bool(cfg("weather_sensitive", false)):
		var manager := get_node_or_null("/root/WeatherManager")
		var weather_callback := Callable(self, "_on_weather_changed")
		if manager != null and manager.has_signal("weather_changed") \
				and not manager.is_connected("weather_changed", weather_callback):
			manager.connect("weather_changed", weather_callback)
	_layout()
	_apply_slot(false)


func _on_slot(_new_slot: int) -> void:
	_apply_slot(true)


func _on_weather_changed(_state: String) -> void:
	_apply_slot(true)


func _tint() -> Color:
	var override: Variant = cfg_slot("tint", null)
	if override != null:
		return _weather_tint(to_color(override, Color(1, 1, 1)))
	var table: Dictionary = PRESETS.get(str(cfg("preset", "indoor_warm")), PRESETS["indoor_warm"])
	return _weather_tint(table.get(_slot(), table[2]))


func _weather_tint(base: Color) -> Color:
	if not bool(cfg("weather_sensitive", false)):
		return base
	var manager := get_node_or_null("/root/WeatherManager")
	if manager == null or Engine.is_editor_hint():
		return base
	match str(manager.call("state")):
		# Weather attenuates the existing time-of-day light. Interpolation to a
		# fixed daytime color previously made a storm BRIGHTER than a clear night.
		"clouds": return base * Color(0.93, 0.96, 0.99)
		"rain": return base * Color(0.85, 0.90, 0.96)
		"storm": return base * Color(0.76, 0.83, 0.92)
		_: return base


func _pool_alpha(p_cfg: Dictionary) -> float:
	var a: Variant = p_cfg.get("alpha", 0.0)
	if a is Dictionary:
		return float(a.get(str(_slot()), 0.0))
	return float(a)


func _apply_slot(animate: bool) -> void:
	var tint := _tint()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate:
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_grade, "color", tint, 1.6).set_trans(Tween.TRANS_SINE)
		for p in _pools:
			_tween.tween_property(p["node"], "self_modulate:a", _pool_alpha(p["cfg"]), 1.6) \
				.set_trans(Tween.TRANS_SINE)
	else:
		_grade.color = tint
		for p in _pools:
			p["node"].self_modulate.a = _pool_alpha(p["cfg"])


func _layout() -> void:
	if _grade != null:
		_grade.position = Vector2.ZERO
		_grade.size = size
	for p in _pools:
		var pc: Dictionary = p["cfg"]
		var pos: Array = pc.get("pos", [0.5, 0.5])
		var radius := float(pc.get("radius", 0.3)) * size.x
		var center := px(float(pos[0]), float(pos[1]))
		var node: TextureRect = p["node"]
		node.size = Vector2(radius * 2.0, radius * 2.0)
		node.position = center - Vector2(radius, radius)
