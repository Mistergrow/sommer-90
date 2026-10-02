extends FxLayer
## Additive Flacker-Glühpunkte an festen Stellen: CRT-Monitore, Neonröhren,
## Leuchtschilder, Kerzen. Jeder Spot hat Position/Größe (normiert), Farbe und
## ein Flacker-Profil. Optional an Slots gebunden (Schild glüht nur abends).
##
## Config (type "glow"):
##   "spots": [ {
##       "pos":[u,v], "size":[w,h] (normiert; oder "radius":r),
##       "color":[r,g,b], "intensity":0.6,
##       "flicker":"steady"|"crt"|"neon"|"candle",
##       "on_slots":[3,4]   (optional; sonst immer an)
##   } ]

var _time := 0.0
var _spots: Array = []


func _apply() -> void:
	add_material_blend(self, CanvasItemMaterial.BLEND_MODE_ADD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6106
	for s in cfg("spots", []):
		_spots.append({
			"cfg": s,
			"color": to_color(s.get("color", [0.5, 0.8, 1.0]), Color(0.5, 0.8, 1.0)),
			"seed": rng.randf() * 100.0,
			"neon_off": false, "neon_t": rng.randf_range(2.0, 6.0),
		})


func _process(delta: float) -> void:
	if reduced_motion():
		queue_redraw()
		return
	_time += delta
	# Neon-Aussetzer stochastisch schalten
	for sp in _spots:
		if str(sp["cfg"].get("flicker", "steady")) == "neon":
			sp["neon_t"] -= delta
			if sp["neon_t"] <= 0.0:
				sp["neon_off"] = not sp["neon_off"]
				sp["neon_t"] = randf_range(0.04, 0.14) if sp["neon_off"] else randf_range(2.5, 7.0)
	queue_redraw()


func _spot_alpha(sp: Dictionary) -> float:
	var s: Dictionary = sp["cfg"]
	var on_slots: Variant = s.get("on_slots", null)
	if on_slots is Array and not on_slots.has(_slot()):
		return 0.0
	var base := float(s.get("intensity", 0.6))
	if reduced_motion():
		return base
	match str(s.get("flicker", "steady")):
		"crt":
			return base * (0.86 + 0.14 * sin(_time * 31.0 + sp["seed"])
				+ 0.04 * sin(_time * 7.3 + sp["seed"]))
		"neon":
			if sp["neon_off"]:
				return base * 0.25
			return base * (0.92 + 0.08 * sin(_time * 12.0 + sp["seed"]))
		"candle":
			return base * (0.7 + 0.3 * sin(_time * 5.0 + sp["seed"])
				* sin(_time * 2.3 + sp["seed"] * 0.5))
		_:
			return base


func _draw() -> void:
	if size.x <= 0.0:
		return
	var glow := glow_texture()
	for sp in _spots:
		var a := _spot_alpha(sp)
		if a <= 0.002:
			continue
		var s: Dictionary = sp["cfg"]
		var pos: Array = s.get("pos", [0.5, 0.5])
		var center := px(float(pos[0]), float(pos[1]))
		var col: Color = sp["color"]
		var rect: Rect2
		if s.has("radius"):
			var r := float(s["radius"]) * size.x
			rect = Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		else:
			var wh: Array = s.get("size", [0.1, 0.08])
			var half := Vector2(float(wh[0]), float(wh[1])) * size * 0.5
			# Glühen etwas größer als die Quelle, damit es weich ausläuft.
			half *= 1.8
			rect = Rect2(center - half, half * 2.0)
		draw_texture_rect(glow, rect, false, Color(col.r, col.g, col.b, a))
