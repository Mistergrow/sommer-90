extends FxLayer
## Treibende Partikel über der Szene: Blätter, Pollen, Schnee oder Staub.
## Deterministisch (fester Seed), mit Wind-Drift + Seitwärts-Sway + Rotation,
## am Rand umlaufend (wrap). Blätter fallen deckend (Alpha-Blend), Pollen/Schnee
## glimmen additiv.
##
## Config (type "particles"):
##   "kind": "leaf" | "pollen" | "snow" | "dust"   (Default "leaf")
##   "count":int          Default 20
##   "colors":[[r,g,b],..] Palette (Default je kind)
##   "size":float          Basisgröße in px bei 640er-Breite (Default je kind)
##   "speed":float         Fallgeschwindigkeit-Faktor (Default 1.0)
##   "wind":float          horizontale Grunddrift (Default je kind)
##   "fade_by_slot":{"4":0.0}  Sichtbarkeit je Slot (Default 1)

const KIND_DEFAULTS := {
	"leaf":   {"size": 9.0, "wind": 0.35, "speed": 1.0, "add": false,
		"colors": [[0.55, 0.42, 0.18], [0.68, 0.5, 0.2], [0.4, 0.46, 0.2], [0.6, 0.34, 0.14]]},
	"pollen": {"size": 3.0, "wind": 0.12, "speed": 0.4, "add": true,
		"colors": [[1.0, 0.95, 0.7], [0.95, 0.9, 0.6]]},
	"snow":   {"size": 4.0, "wind": 0.18, "speed": 0.7, "add": true,
		"colors": [[1.0, 1.0, 1.0], [0.9, 0.94, 1.0]]},
	"dust":   {"size": 2.5, "wind": 0.05, "speed": 0.3, "add": true,
		"colors": [[0.9, 0.86, 0.78]]},
}

var _time := 0.0
var _parts: Array = []
var _kind := "leaf"
var _size := 9.0
var _add := false


func _apply() -> void:
	_kind = str(cfg("kind", "leaf"))
	var kd: Dictionary = KIND_DEFAULTS.get(_kind, KIND_DEFAULTS["leaf"])
	_size = float(cfg("size", kd["size"]))
	_add = bool(kd["add"])
	if _add:
		add_material_blend(self, CanvasItemMaterial.BLEND_MODE_ADD)
	var colors: Array = cfg("colors", kd["colors"])
	var wind := float(cfg("wind", kd["wind"]))
	var speed := float(cfg("speed", kd["speed"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1EA5 + _kind.hash()
	var n := int(cfg("count", 20))
	for i in n:
		var c: Array = colors[rng.randi() % colors.size()]
		_parts.append({
			"u": rng.randf(), "v": rng.randf(),
			"vspd": (0.02 + rng.randf() * 0.03) * speed,
			"wind": wind * (0.6 + rng.randf() * 0.8),
			"sway": rng.randf_range(0.006, 0.02),
			"swf": rng.randf_range(0.5, 1.4),
			"phase": rng.randf() * TAU,
			"rot": rng.randf() * TAU, "rspd": rng.randf_range(-1.4, 1.4),
			"scale": rng.randf_range(0.7, 1.3),
			"col": to_color(c, Color(0.6, 0.45, 0.2)),
		})


func _fade() -> float:
	var f: Variant = cfg("fade_by_slot", null)
	var result := 1.0
	if f is Dictionary:
		result = float(f.get(str(_slot()), 1.0))
	return result * _weather_fade()


func _weather_fade() -> float:
	var manager := get_node_or_null("/root/WeatherManager")
	if manager == null or Engine.is_editor_hint():
		return 1.0
	var state := str(manager.call("state"))
	if state not in ["rain", "storm"]:
		return 1.0
	# Trockener Staub und Pollen verschwinden bei Niederschlag. Einzelne nasse
	# Blaetter duerfen bei Wind weiter durchs Bild treiben, aber deutlich seltener.
	match _kind:
		"dust", "pollen": return 0.02
		"leaf": return 0.32 if state == "rain" else 0.48
		_: return 1.0


func _process(delta: float) -> void:
	if _fade() <= 0.001:
		if visible:
			visible = false
		return
	visible = true
	if not reduced_motion():
		_time += minf(delta, 0.08)
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0:
		return
	var fade := _fade()
	var dot := dot_texture()
	var base_px := _size * (size.x / 640.0)
	for p: Dictionary in _parts:
		var u: float = wrapf(p["u"] + p["wind"] * _time * 0.02
			+ sin(_time * p["swf"] + p["phase"]) * p["sway"], -0.05, 1.05)
		var v: float = wrapf(p["v"] + p["vspd"] * _time, -0.05, 1.05)
		var c := px(u, v)
		var col: Color = p["col"]
		var a: float = fade * (0.55 if _add else 0.85)
		var r := base_px * float(p["scale"])
		if _kind == "leaf":
			# Blatt als kleine gedrehte Ellipse (zwei überlagerte Rechtecke).
			var ang: float = p["rot"] + _time * p["rspd"]
			draw_set_transform(c, ang, Vector2.ONE)
			draw_texture_rect(dot, Rect2(-r, -r * 0.5, r * 2.0, r), false, Color(col.r, col.g, col.b, a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var tw := 0.6 + 0.4 * sin(_time * 2.0 + p["phase"])
			draw_texture_rect(dot, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false,
				Color(col.r, col.g, col.b, a * tw))
