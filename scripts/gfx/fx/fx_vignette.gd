extends FxLayer
## Dezente Vignette (Multiply): dunkelt die Bildränder weich ab, lenkt den Blick
## zur Mitte und vereinheitlicht alle Orte zu einem kohärenten, filmischen Look.
## Wird vom LocationFx-Regisseur automatisch als oberste Ebene ergänzt (außer die
## Ort-Config setzt "vignette": false).
##
## Config (type "vignette", optional):
##   "strength": 0.30   Abdunklung an den Ecken (0..1)
##   "start":    0.55   normierter Radius, ab dem die Vignette einsetzt

var _rect: TextureRect = null

static var _tex_key := ""
static var _tex: ImageTexture = null


func _apply() -> void:
	var strength := clampf(float(cfg("strength", 0.18)), 0.0, 0.6)
	var start := clampf(float(cfg("start", 0.55)), 0.0, 0.95)
	_rect = TextureRect.new()
	_rect.texture = _vignette_texture(strength, start)
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_material_blend(_rect, CanvasItemMaterial.BLEND_MODE_MUL)
	add_child(_rect)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if _rect != null:
		_rect.position = Vector2.ZERO
		_rect.size = size


## Radiale Multiply-Maske: Mitte = 1 (unverändert), Ecken = 1-strength.
## Wird zur Rechteckgröße gestreckt → elliptische Vignette (passt zu 16:9).
static func _vignette_texture(strength: float, start: float) -> ImageTexture:
	var key := "%0.3f_%0.3f" % [strength, start]
	if _tex != null and _tex_key == key:
		return _tex
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2((x - s * 0.5) / (s * 0.5), (y - s * 0.5) / (s * 0.5)).length()
			var t := smoothstep(start, 1.0, clampf(d, 0.0, 1.0))
			var v := 1.0 - strength * t
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_tex = ImageTexture.create_from_image(img)
	_tex_key = key
	return _tex
