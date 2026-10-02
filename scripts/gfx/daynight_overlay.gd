extends Control
## DayNightOverlay — prozedurales Tageszeit-Grading des Zimmers (EFFECT_001,
## füllt den Slot OVERLAY_LIGHT_WARM_EVENING ohne eigenes Asset).
##
## Multipliziert die ganze Zimmeransicht je TimeManager-Slot (Morgen..Nacht)
## mit einem Farbton (das Basisbild ist warm nachmittäglich belichtet, die
## Morgen-Töne kühlen es also ab, Abend/Nacht dunkeln + färben)
## und blendet abends/nachts einen warmen Lichtpool der Schreibtischlampe
## additiv dazu — so „lebt" der Raum mit der Tageszeit, statt immer gleich hell
## zu sein. Kind des RoomCompositors (z 23, über den Layern, unter Wetter/CRT).

# tint = Multiply-Farbe (≤1 pro Kanal: nur abdunkeln/verschieben, nie
# überstrahlen — Helligkeit kommt bei Bedarf additiv vom Lampenpool).
# lamp = Alpha des warmen Lampen-Lichtpools.
# window = Multiply-Farbe (mit Alpha) auf dem Fensterglas. Das Basisbild zeigt
# einen festen Tagesblick; die Multiplikation erhält Häuser, Bäume und Reflexe,
# statt sie mit zwei flachen Farb-Rechtecken zuzudecken.
# 5 Zeitfenster (SOMMER '90, docs/LIFE_TIME_BIBLE.md) — Indizes = TimeManager.SLOT_NAMES.
const ColorProfile := preload("res://scripts/gfx/scene_color_profile.gd")
const GRADE := {
	0: {"tint": Color(0.88, 0.94, 1.00), "lamp": 0.00, "window": Color(0.80, 0.86, 1.00, 0.10), "curtain": Color(0.82, 0.90, 1.00, 0.05)}, # Morgen — kühl-hell
	1: {"tint": Color(1.00, 1.00, 0.97), "lamp": 0.00, "window": Color(1.00, 1.00, 1.00, 0.00), "curtain": Color(1.00, 1.00, 1.00, 0.00)}, # Mittag — voll Tag
	2: {"tint": ColorProfile.PRESETS["indoor_warm"][2], "lamp": 0.10, "window": Color(1.00, 0.95, 0.84, 0.10), "curtain": Color(1.00, 0.94, 0.82, 0.05)}, # Nachmittag — golden
	3: {"tint": ColorProfile.PRESETS["indoor_warm"][3], "lamp": 0.50, "window": Color(0.82, 0.60, 0.40, 0.45), "curtain": Color(0.66, 0.56, 0.46, 0.22)}, # Abend — warme Lichter, neutrale Geräte
	4: {"tint": Color(0.48, 0.56, 0.78), "lamp": 1.00, "window": Color(0.05, 0.07, 0.16, 0.90), "curtain": Color(0.22, 0.32, 0.55, 0.52)}, # Nacht — dunkles Fenster
}
const LAMP_COLOR := Color(1.0, 0.85, 0.62)   # warmes Glühlampenlicht mit erhaltener Materialfarbe
## Absolute Raumtiefe: über Basis + Wetter-Außenbild, aber sicher hinter
## Schreibtisch (z 8) und allen Geräten. Der alte relative z=23-Tint lag auf dem
## Monitor und erzeugte die im Nachtbild sichtbare blaue Abdeckung.
const WINDOW_WORLD_Z := 3
const CURTAIN_WORLD_Z := 4
const IdleLifeScript := preload("res://scripts/gfx/idle_life_overlay.gd")

var comp: Control = null           # der RoomCompositor (Transform + Anker)
var _grade: ColorRect = null       # Multiply-Tönung über der ganzen Szene
var _lamp: TextureRect = null      # additiver Lichtpool an der Lampe
var _lamp_cone: TextureRect = null # gerichteter Lichtkegel vom Schirm zur Platte
var _window: Control = null        # deckt das Tageslicht-Fenster abends/nachts ab
var _curtain: Control = null       # nimmt den Gardinen das eingebrannte Tageslicht
var _tween: Tween = null

static var _glow_tex: ImageTexture = null
static var _cone_tex: ImageTexture = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Fenstertönung als absolute Weltlage: Sie bleibt Kind dieses Controllers,
	# wird aber nicht auf dessen Overlay-z=23 addiert. So steht Hardware wirklich
	# vor dem Fenster und kann nie von der Glasmaske übermalt werden.
	_window = _MaskedTint.new()
	_window.set("comp", comp)
	_window.set("quad_names", ["fenster_links", "fenster_rechts"])
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.z_as_relative = false
	_window.z_index = WINDOW_WORLD_Z
	var glass_mul := CanvasItemMaterial.new()
	glass_mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_window.material = glass_mul
	_window.self_modulate = Color(1, 1, 1, 0)
	add_child(_window)

	# Die transparenten Gardinen sind im Tages-Basisbild sehr hell. Eine eigene,
	# mildere Multiply-Lage macht sie nachts blau-grau, ohne Stoffzeichnung oder
	# Falten zu übermalen. Der additive Lampenpool liegt später darüber und darf
	# die linke Gardine wieder warm aufhellen.
	_curtain = _MaskedTint.new()
	_curtain.set("comp", comp)
	_curtain.set("quad_names", ["gardine_links", "gardine_rechts"])
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.z_as_relative = false
	_curtain.z_index = CURTAIN_WORLD_Z
	var curtain_mul := CanvasItemMaterial.new()
	curtain_mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_curtain.material = curtain_mul
	_curtain.self_modulate = Color(1, 1, 1, 0)
	add_child(_curtain)

	_grade = ColorRect.new()
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_grade.material = mul
	_grade.z_index = 0
	add_child(_grade)

	_lamp = TextureRect.new()
	_lamp.texture = _glow_texture()
	_lamp.stretch_mode = TextureRect.STRETCH_SCALE
	_lamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lamp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lamp.material = add
	_lamp.modulate = LAMP_COLOR
	_lamp.z_index = 1
	add_child(_lamp)

	# Ein zweiter, gerichteter Verlauf macht aus dem bloßen Leuchtfleck eine
	# lesbare Tischlampe. Die Form bleibt weich und liegt im selben additiven
	# Lichtverbund; Geräte und Tischdetails werden deshalb aufgehellt, nicht
	# mit einer deckenden Polygonfläche übermalt.
	_lamp_cone = TextureRect.new()
	_lamp_cone.texture = _cone_texture()
	_lamp_cone.stretch_mode = TextureRect.STRETCH_SCALE
	_lamp_cone.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lamp_cone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_lamp_cone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cone_add := CanvasItemMaterial.new()
	cone_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lamp_cone.material = cone_add
	_lamp_cone.modulate = LAMP_COLOR
	_lamp_cone.z_index = 1
	add_child(_lamp_cone)
	# Vor dem radialen Pool einsortieren: Der Schirmansatz bleibt weich, der
	# Pool auf der Tischplatte bildet den hellsten Abschluss.
	move_child(_lamp_cone, _lamp.get_index())

	if not Engine.is_editor_hint() and not TimeManager.slot_changed.is_connected(_on_slot):
		TimeManager.slot_changed.connect(_on_slot)
	_apply_slot(false)


## Sanfter Übergang beim Zeitwechsel.
func _on_slot(_slot: int) -> void:
	_apply_slot(true)


func _current_grade() -> Dictionary:
	# Editor-Vorschau: neutrales Licht, damit man Objekte sauber platzieren kann.
	if Engine.is_editor_hint():
		return {"tint": Color(1, 1, 1), "lamp": 0.0}
	return GRADE.get(TimeManager.slot, GRADE[2])  # Fallback: Nachmittag (Original-Look)


func _apply_slot(animate: bool) -> void:
	var g := _current_grade()
	var tint: Color = g["tint"]
	var lamp_a: float = float(g["lamp"])
	var win: Color = g.get("window", Color(1, 1, 1, 0))
	var curtain_tint: Color = g.get("curtain", Color(1, 1, 1, 0))
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate:
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_grade, "color", tint, 1.6).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(_lamp, "self_modulate:a", lamp_a, 1.6).set_trans(Tween.TRANS_SINE)
		_tween.tween_property(_lamp_cone, "self_modulate:a", lamp_a * 0.58, 1.6) \
			.set_trans(Tween.TRANS_SINE)
		if _window != null:
			_tween.tween_property(_window, "self_modulate", win, 1.6).set_trans(Tween.TRANS_SINE)
		if _curtain != null:
			_tween.tween_property(_curtain, "self_modulate", curtain_tint, 1.6).set_trans(Tween.TRANS_SINE)
	else:
		_grade.color = tint
		_lamp.self_modulate.a = lamp_a
		_lamp_cone.self_modulate.a = lamp_a * 0.58
		if _window != null:
			_window.self_modulate = win
		if _curtain != null:
			_curtain.self_modulate = curtain_tint


func _layout() -> void:
	if _window != null:
		_window.position = Vector2.ZERO
		_window.size = size
		_window.queue_redraw()   # Fenster-Quads folgen der Ansicht (Zoom/Pan)
	if _curtain != null:
		_curtain.position = Vector2.ZERO
		_curtain.size = size
		_curtain.queue_redraw()
	if _grade != null:
		_grade.position = Vector2.ZERO
		_grade.size = size
	if _lamp != null and comp != null:
		# Lichtpool an den Lampen-Anker setzen (leicht nach unten, wo das Licht
		# auf die Tischplatte fällt). Größe skaliert mit der Ansicht.
		var t: Dictionary = comp._master_transform()
		var scale_factor: float = t["scale"]
		var offset: Vector2 = t["offset"]
		var radius := 300.0 * scale_factor
		var center := size * 0.5
		# Bevorzugt: der im LED-Editor gesetzte „light"-Marker (die Birne).
		var lit: Dictionary = IdleLifeScript.first_feature(comp, "light")
		if not lit.is_empty():
			center = lit["center"]
		else:
			var a: Variant = config_anchors().get("lamp_slot", null)
			if a != null:
				var mp := Vector2(a[0], a[1] + 40.0)
				center = comp.project_master_point(mp) if comp.has_method("project_master_point") \
					else offset + mp * scale_factor
		_lamp.size = Vector2(radius * 2.0, radius * 2.0)
		_lamp.position = center - Vector2(radius, radius)
		if _lamp_cone != null:
			# Der klassische Schirm zeigt leicht nach rechts unten. Der Verlauf
			# trägt diese Richtung bereits in seiner Alphamaske; dadurch ist kein
			# rotierter Rechteckrand sichtbar.
			_lamp_cone.size = Vector2(330.0, 250.0) * scale_factor
			_lamp_cone.position = center + Vector2(-82.0, -8.0) * scale_factor


func config_anchors() -> Dictionary:
	if comp == null:
		return {}
	return comp.config().get("anchors", {})


## Tönt nur das sichtbare Glas mit der Tageszeit-Farbe (Alpha aus GRADE.window).
## Zeichnet die Scheiben in WEISS; die eigentliche Multiply-Farbe kommt per
## self_modulate (getweent). Fensterrahmen, Gardinen und Hardware bleiben frei.
class _MaskedTint:
	extends Control

	var comp: Control = null
	var quad_names: Array = []

	func _draw() -> void:
		if comp == null or Engine.is_editor_hint():
			return
		if comp.get("edit_mode"):
			return
		var t: Dictionary = comp._master_transform()
		var offset: Vector2 = t["offset"]
		var scale_factor: float = t["scale"]
		var quads: Dictionary = comp._quads()
		for wname: String in quad_names:
			if not quads.has(wname):
				continue
			var corners: Array = quads[wname].get("corners", [])
			var poly := PackedVector2Array()
			for c in corners:
				var mp := Vector2(c[0], c[1])
				poly.append(comp.project_master_point(mp, "base") if comp.has_method("project_master_point") \
					else offset + mp * scale_factor)
			if poly.size() >= 3:
				draw_colored_polygon(poly, Color.WHITE)


## Weicher, warmer Radialverlauf (einmal erzeugt) für den Lampen-Lichtpool.
static func _glow_texture() -> ImageTexture:
	if _glow_tex != null:
		return _glow_tex
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2((x - s * 0.5) / (s * 0.5), (y - s * 0.5) / (s * 0.5)).length()
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.4)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


## Weicher asymmetrischer Lichtkegel: schmal am Lampenschirm, nach rechts unten
## geöffnet und an allen Kanten ausgefedert. Prozedural, damit keine weitere
## Auflösungsvariante oder ein unscharf skaliertes Platzhalterbild nötig ist.
static func _cone_texture() -> ImageTexture:
	if _cone_tex != null:
		return _cone_tex
	var w := 112
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var ty := float(y) / float(h - 1)
		var center_x := lerpf(0.26, 0.58, ty)
		var half_width := lerpf(0.025, 0.47, pow(ty, 0.78))
		var length_fade := smoothstep(0.0, 0.09, ty) \
			* pow(clampf(1.0 - ty, 0.0, 1.0), 0.72)
		for x in w:
			var tx := float(x) / float(w - 1)
			var side := clampf(1.0 - absf(tx - center_x) \
				/ maxf(half_width, 0.001), 0.0, 1.0)
			var alpha := smoothstep(0.0, 0.36, side) * side * length_fade
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	_cone_tex = ImageTexture.create_from_image(img)
	return _cone_tex
