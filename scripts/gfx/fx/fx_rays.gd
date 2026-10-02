extends FxLayer
## Weiche Lichtschäfte + schwebende Staubpartikel aus einer konfigurierbaren
## Quelle (Fenster, Baumkrone, Deckenlampe). Additiv gezeichnet mit den weichen
## Grundtexturen aus FxLayer — Intensität/Farbe folgen der Tageszeit.
##
## Config (type "rays"):
##   "source":[u,v]      Ursprung der Schäfte (normiert), Default [0.7, 0.05]
##   "dir":[dx,dy]       Lichtrichtung, Default [-0.25, 1.0] (rechts-oben → links-unten)
##   "count":int         Zahl der Schäfte (Default 6)
##   "spread":float      seitliche Streuung der Ursprünge (Bruchteil Breite, 0.5)
##   "length":float      Schaftlänge (Bruchteil Höhe, 0.9)
##   "width":float       Schaftbreite (Bruchteil Breite, 0.06)
##   "color" / per-Slot  Strahlfarbe
##   "intensity" / Slot  0..1 Gesamtstärke (Default Tabelle)
##   "dust":int          Zahl der Staubpunkte (Default 42)

const DEF_INTENSITY := {0: 0.62, 1: 0.28, 2: 0.5, 3: 0.85, 4: 0.0}
const DEF_COLOR := {
	0: Color(0.95, 0.96, 0.98), 1: Color(1.0, 0.98, 0.92),
	2: Color(1.0, 0.93, 0.76), 3: Color(1.0, 0.76, 0.48), 4: Color(0, 0, 0),
}

var _time := 0.0
var _motes: Array = []


func _apply() -> void:
	add_material_blend(self, CanvasItemMaterial.BLEND_MODE_ADD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD0571
	var n := int(cfg("dust", 42))
	for i in n:
		_motes.append({
			"u": rng.randf_range(0.04, 0.96), "v": rng.randf_range(0.06, 0.9),
			"r": rng.randf_range(1.2, 4.0), "spd": rng.randf_range(3.0, 11.0),
			"phase": rng.randf() * TAU,
		})


func _intensity() -> float:
	var v: Variant = cfg_slot("intensity", null)
	if v != null:
		return float(v) * _weather_factor()
	return float(DEF_INTENSITY.get(_slot(), 0.4)) * _weather_factor()


func _weather_factor() -> float:
	if not bool(cfg("weather_sensitive", false)):
		return 1.0
	var manager := get_node_or_null("/root/WeatherManager")
	if manager == null or Engine.is_editor_hint():
		return 1.0
	match str(manager.call("state")):
		"clouds": return 0.42
		"rain": return 0.14
		"storm": return 0.035
		_: return 1.0


func _color() -> Color:
	var v: Variant = cfg_slot("color", null)
	if v != null:
		return to_color(v, Color(1, 0.95, 0.85))
	return DEF_COLOR.get(_slot(), Color(1.0, 0.95, 0.85))


func _process(delta: float) -> void:
	if _intensity() <= 0.001:
		if visible:
			visible = false
		return
	visible = true
	if not reduced_motion():
		_time += minf(delta, 0.08)
	queue_redraw()


func _draw() -> void:
	var strength := _intensity()
	if strength <= 0.001 or size.x <= 0.0:
		return
	var col := _color()
	var src: Array = cfg("source", [0.7, 0.05])
	var origin := px(float(src[0]), float(src[1]))
	var d: Array = cfg("dir", [-0.25, 1.0])
	var ldir := Vector2(float(d[0]), float(d[1])).normalized()
	var angle := atan2(-ldir.x, ldir.y)     # lokales +y zeigt in Lichtrichtung
	var beam := beam_texture()
	var count := int(cfg("count", 6))
	var spread := float(cfg("spread", 0.5)) * size.x
	var length := float(cfg("length", 0.9)) * size.y
	var base_w := float(cfg("width", 0.06)) * size.x

	# --- weiche Sonnenschäfte ---
	for i in count:
		var f := float(i) / float(maxi(count - 1, 1))
		var lateral := (f - 0.5) * spread
		var sway := sin(_time * 0.22 + f * 3.0) * (0.012 * size.x)
		var o := origin + Vector2(lateral + sway, 0.0)
		var wdt := base_w * (0.7 + 0.5 * sin(f * 5.0 + 1.0))
		var a := strength * (0.16 + 0.09 * sin(_time * 0.5 + f * 2.0))
		draw_set_transform(o, angle, Vector2.ONE)
		draw_texture_rect(beam, Rect2(-wdt * 0.5, 0.0, wdt, length), false,
			Color(col.r, col.g, col.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- Staubpartikel, im Lichtband heller ---
	var dot := dot_texture()
	var shaft_u := float(src[0])
	for m: Dictionary in _motes:
		var drift := Vector2(sin(_time * 0.3 + m["phase"]) * 0.012 - _time * m["spd"] * 0.00008,
			-_time * m["spd"] * 0.00028 + cos(_time * 0.4 + m["phase"]) * 0.008)
		var u: float = wrapf(m["u"] + drift.x, 0.03, 0.97)
		var v: float = wrapf(m["v"] + drift.y, 0.05, 0.92)
		var in_shaft := 1.0 if absf(u - shaft_u) < 0.28 else 0.32
		var tw := 0.5 + 0.5 * sin(_time * 1.7 + m["phase"])
		var a := strength * 0.6 * in_shaft * (0.3 + 0.7 * tw)
		var rr := float(m["r"]) * (size.x / 640.0) * 3.0
		var c := px(u, v)
		draw_texture_rect(dot, Rect2(c - Vector2(rr, rr), Vector2(rr * 2.0, rr * 2.0)),
			false, Color(col.r, col.g, col.b, a))
