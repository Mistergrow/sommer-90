class_name FxLayer
extends Control
## Basis aller Orts-Atmosphäre-Ebenen (LocationFx-Baukasten).
##
## Jede Effekt-Ebene ist ein full-rect, maus-transparentes Control, das seine
## Konfiguration (ein Dictionary aus data/location_fx.json) über setup() erhält
## und tageszeit-bewusst ist (TimeManager-Slot 0..4). Koordinaten in den Configs
## sind NORMIERT (0..1) auf die sichtbare Fläche — die Orts-Artworks sind 16:9
## wie das Fenster, also entspricht (u,v) direkt dem Bildpunkt.
##
## Unterklassen überschreiben _apply() (Aufbau) und optional _on_slot() (Retween).
## Weiche Grundtexturen (Punkt/Strahl/Glow) liegen hier einmalig als statische
## ImageTextures — geteilt von allen Ebenen und Orten.

var spec: Dictionary = {}


func setup(s: Dictionary) -> void:
	spec = s
	# Kein Anker-Preset: die Größe wird vom LocationFx-Regisseur gesetzt und
	# nachgeführt (wie LocationBase selbst) — Anker + manuelles size warnen sonst.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Engine.is_editor_hint() and TimeManager.has_signal("slot_changed") \
			and not TimeManager.slot_changed.is_connected(_on_slot):
		TimeManager.slot_changed.connect(_on_slot)
	_apply()


## Unterklassen: Kinder/Material/Partikel aufbauen.
func _apply() -> void:
	pass


## Unterklassen: bei Tageszeitwechsel sanft neu graden.
func _on_slot(_new_slot: int) -> void:
	pass


func _slot() -> int:
	if Engine.is_editor_hint():
		return 2  # Nachmittag = Original-Look für die Editor-Vorschau
	return TimeManager.slot


func reduced_motion() -> bool:
	var settings := get_node_or_null("/root/SettingsManager")
	return settings != null and bool(settings.call("value", "reduced_motion"))


## Rohwert aus spec (Skalar oder Objekt), Default wenn fehlend.
func cfg(key: String, default: Variant) -> Variant:
	return spec.get(key, default)


## Wert aus spec[key], der ENTWEDER ein Skalar/Array IST ODER ein Per-Slot-Objekt
## {"0": .., "3": ..}. Bei Per-Slot-Objekt wird der aktuelle Slot gezogen.
func cfg_slot(key: String, default: Variant) -> Variant:
	var v: Variant = spec.get(key, null)
	if v == null:
		return default
	if v is Dictionary:
		var sk := str(_slot())
		return v[sk] if v.has(sk) else default
	return v


## [r,g,b] oder [r,g,b,a] → Color; sonst Fallback.
static func to_color(v: Variant, fallback: Color) -> Color:
	if v is Array and v.size() >= 3:
		return Color(v[0], v[1], v[2], v[3] if v.size() >= 4 else 1.0)
	if v is Color:
		return v
	return fallback


## Normierter Punkt (0..1) → Pixel auf der sichtbaren Fläche.
func px(u: float, v: float) -> Vector2:
	return Vector2(u, v) * size


func add_material_blend(node: CanvasItem, mode: CanvasItemMaterial.BlendMode) -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = mode
	node.material = mat


# ------------------------------------------------- weiche Grundtexturen (einmalig)
static var _dot_tex: ImageTexture = null
static var _beam_tex: ImageTexture = null
static var _glow_tex: ImageTexture = null


## Weicher runder Punkt (Radialverlauf) — Staub, Pollen, Glanz.
static func dot_texture() -> ImageTexture:
	if _dot_tex != null:
		return _dot_tex
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2((x - s * 0.5) / (s * 0.5), (y - s * 0.5) / (s * 0.5)).length()
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


## Licht-Schacht: horizontal gefedert, vertikal auslaufend (hell an der Quelle,
## transparent am Ende) — weiche Ränder statt harter Polygonkanten.
static func beam_texture() -> ImageTexture:
	if _beam_tex != null:
		return _beam_tex
	var w := 48
	var h := 192
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var ty := float(y) / float(h - 1)
		var length_fade := pow(clampf(1.0 - ty, 0.0, 1.0), 1.35)
		length_fade *= smoothstep(0.0, 0.12, ty)
		for x in w:
			var tx := float(x) / float(w - 1)
			var edge := sin(PI * tx)
			edge = edge * edge
			img.set_pixel(x, y, Color(1, 1, 1, edge * length_fade))
	_beam_tex = ImageTexture.create_from_image(img)
	return _beam_tex


## Weicher runder Lichtpool (steilerer Rand) — Lampen-/Neon-/Schild-Glühen.
static func glow_texture() -> ImageTexture:
	if _glow_tex != null:
		return _glow_tex
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2((x - s * 0.5) / (s * 0.5), (y - s * 0.5) / (s * 0.5)).length()
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.4)))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex
