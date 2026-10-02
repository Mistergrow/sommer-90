extends FxLayer
## Musik-reaktives Pulsieren (z. B. Lautsprecher im Musikladen). Liest den
## Spitzenpegel des Audio-Busses (standard "Master"), glättet ihn mit schnellem
## Attack / langsamem Decay (VU-Charakter) und lässt konfigurierte Glühpunkte
## in Helligkeit UND Größe zum Beat atmen. Additiv gezeichnet.
##
## Entkoppelt vom MOD-Interna: reagiert auf die tatsächliche Lautheit. Ohne
## laufende Musik (MusicManager.is_playing()==false) fällt der Puls auf 0.
##
## Config (type "beat"):
##   "targets":[ {"pos":[u,v], "radius":0.06, "color":[r,g,b], "gain":0.6, "base":0.05} ]
##   "bus":"Master"            Audio-Bus für die Pegelmessung
##   "range_db":[-42,-6]       Pegelfenster (dB) → 0..1
##
## Verifikation: OS-Env DSS_BEAT_DEMO=1 speist einen Sinus-Pegel ein (für Shots).

var _time := 0.0
var _level := 0.0
var _bus_idx := 0
var _min_db := -42.0
var _max_db := -6.0
var _demo := false


func _apply() -> void:
	add_material_blend(self, CanvasItemMaterial.BLEND_MODE_ADD)
	_bus_idx = AudioServer.get_bus_index(str(cfg("bus", "Music")))
	if _bus_idx < 0:
		_bus_idx = 0  # Fallback Master, falls Bus-Layout fehlt
	var rng: Array = cfg("range_db", [-42.0, -6.0])
	_min_db = float(rng[0])
	_max_db = float(rng[1])
	_demo = OS.get_environment("DSS_BEAT_DEMO") != ""


func _target_level() -> float:
	if reduced_motion():
		return 0.0
	if _demo:
		return 0.8  # deterministischer Peak für Kontroll-Shots
	if Engine.is_editor_hint():
		return 0.0
	var mm := get_node_or_null("/root/MusicManager")
	if mm == null or not mm.is_playing():
		return 0.0
	var peak := AudioServer.get_bus_peak_volume_left_db(_bus_idx, 0)
	return clampf((peak - _min_db) / maxf(_max_db - _min_db, 1.0), 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var target := _target_level()
	# Schneller Attack, langsamer Decay → knackiger Box-Puls.
	if target >= _level:
		_level = target
	else:
		_level = maxf(target, _level - delta * 2.6)
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0:
		return
	var glow := glow_texture()
	for t in cfg("targets", []):
		var pos: Array = t.get("pos", [0.5, 0.5])
		var col := to_color(t.get("color", [0.6, 0.82, 1.0]), Color(0.6, 0.82, 1.0))
		var base := float(t.get("base", 0.05))
		var gain := float(t.get("gain", 0.6))
		var radius := float(t.get("radius", 0.06)) * size.x
		var a := base + _level * gain
		var r := radius * (1.0 + _level * 0.28)   # Membran „atmet" mit
		var center := px(float(pos[0]), float(pos[1]))
		draw_texture_rect(glow, Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
			false, Color(col.r, col.g, col.b, a))
