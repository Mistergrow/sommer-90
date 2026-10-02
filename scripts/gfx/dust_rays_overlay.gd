extends Control
## DustRaysOverlay — weiche Sonnenstrahlen durchs Fenster + schwebende
## Staubpartikel. Additiv gezeichnet mit vorgerenderten WEICHEN Texturen
## (gefederte Ränder + Längenverlauf), damit keine harten Polygon-Kanten
## sichtbar sind. Intensität/Farbe folgen der Tageszeit (TimeManager-Slot):
## morgens/abends bei flachem Licht am stärksten, nachts aus.
## Kind des RoomCompositors (z 22, über Layern/Wetter, unter Monitor-Glow).

# 5 Zeitfenster (SOMMER '90): Morgen, Mittag, Nachmittag, Abend, Nacht.
const RAY_INTENSITY := {0: 0.62, 1: 0.26, 2: 0.5, 3: 0.82, 4: 0.0}
const RAY_COLOR := {
	0: Color(0.95, 0.96, 0.98),
	1: Color(1.0, 0.98, 0.92),
	2: Color(1.0, 0.92, 0.74),
	3: Color(1.0, 0.74, 0.46),
	4: Color(0, 0, 0),
}
const RAY_DIR := Vector2(-0.30, 1.0)   # von rechts oben ins Zimmer (links unten)
const FxLayerBase := preload("res://scripts/gfx/fx/fx_layer.gd")

var comp: Control = null
var _time := 0.0
var _motes: Array = []   # [{u, v, r, spd, phase}] — u,v in Master-Koords


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_seed_motes()


func _intensity() -> float:
	if Engine.is_editor_hint():
		return 0.0
	# Ein nasses, überzogenes Fenster kann noch diffuses Licht projizieren, aber
	# keine goldenen Sonnenstrahlen samt tanzendem Staub. Sonst erzählen Fenster
	# und Boden gleichzeitig zwei gegensätzliche Wetterlagen.
	var weather_factor: float = float({
		"clear": 1.0,
		"clouds": 0.28,
		"rain": 0.035,
		"storm": 0.0,
	}.get(WeatherManager.state(), 1.0))
	return float(RAY_INTENSITY.get(TimeManager.slot, 0.3)) * weather_factor


func _process(delta: float) -> void:
	if comp == null or comp.edit_mode:
		return
	if _intensity() <= 0.001:
		if visible:
			visible = false
		return
	visible = true
	_time += delta
	queue_redraw()


func _window_rect() -> Rect2:
	var quads: Dictionary = comp._quads() if comp != null else {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var found := false
	for qn in ["fenster_links", "fenster_rechts"]:
		if quads.has(qn):
			for c in quads[qn].get("corners", []):
				lo = lo.min(Vector2(c[0], c[1]))
				hi = hi.max(Vector2(c[0], c[1]))
				found = true
	if not found:
		return Rect2(770, 130, 390, 330)
	return Rect2(lo, hi - lo)


func _seed_motes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD0571
	_motes.clear()
	for i in 60:
		_motes.append({
			"u": rng.randf_range(120, 1800), "v": rng.randf_range(160, 780),
			"r": rng.randf_range(1.2, 4.0), "spd": rng.randf_range(3.0, 11.0),
			"phase": rng.randf() * TAU,
		})


# --------------------------------------------------------------- Zeichnen
func _draw() -> void:
	if comp == null:
		return
	var strength := _intensity()
	if strength <= 0.001:
		return
	var t: Dictionary = comp._master_transform()
	var sc: float = t["scale"]
	var off: Vector2 = t["offset"]
	var col: Color = RAY_COLOR.get(TimeManager.slot, Color(1.0, 0.95, 0.85))
	var win := _window_rect()
	var dir := RAY_DIR.normalized()
	var angle := atan2(-dir.x, dir.y)   # lokales +y zeigt in Lichtrichtung
	var beam := FxLayerBase.beam_texture()

	# --- Weiche Sonnenstrahlen: gefederte Textur-Schächte aus dem Fenster ---
	var count := 5
	var length := 720.0 * sc
	for i in count:
		var f := float(i) / float(count - 1)
		var origin_m := Vector2(win.position.x + win.size.x * lerpf(0.12, 0.96, f),
			win.position.y + win.size.y * 0.30)
		var sway := sin(_time * 0.22 + f * 3.0) * 12.0
		var origin_with_sway := origin_m + Vector2(sway, 0)
		var o: Vector2 = comp.project_master_point(origin_with_sway, "base") \
			if comp.has_method("project_master_point") else off + origin_with_sway * sc
		var wdt := (95.0 + 45.0 * sin(f * 5.0 + 1.0)) * sc
		var a := strength * (0.16 + 0.09 * sin(_time * 0.5 + f * 2.0))
		draw_set_transform(o, angle, Vector2.ONE)
		draw_texture_rect(beam, Rect2(-wdt * 0.5, 0.0, wdt, length), false, Color(col.r, col.g, col.b, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- Staubpartikel: weiche Punkte, im Lichtband heller ---
	var dot := FxLayerBase.dot_texture()
	var shaft_lo := win.position.x - 120.0
	var shaft_hi := win.position.x + win.size.x + 260.0
	for m: Dictionary in _motes:
		var base := Vector2(m["u"], m["v"])
		var drift := Vector2(sin(_time * 0.3 + m["phase"]) * 22.0 - _time * m["spd"] * 0.15,
			-_time * m["spd"] * 0.5 + cos(_time * 0.4 + m["phase"]) * 14.0)
		var pm := base + drift
		pm.x = wrapf(pm.x, 80.0, 1840.0)
		pm.y = wrapf(pm.y, 150.0, 800.0)
		var in_shaft := 1.0 if (pm.x > shaft_lo and pm.x < shaft_hi and pm.y < 760.0) else 0.3
		var tw := 0.5 + 0.5 * sin(_time * 1.7 + m["phase"])
		var a := strength * 0.6 * in_shaft * (0.3 + 0.7 * tw)
		var rr := float(m["r"]) * sc * 3.0
		var screen_p: Vector2 = comp.project_master_point(pm, "base") \
			if comp.has_method("project_master_point") else off + pm * sc
		draw_texture_rect(dot, Rect2(screen_p - Vector2(rr, rr), Vector2(rr * 2.0, rr * 2.0)),
			false, Color(col.r, col.g, col.b, a))
