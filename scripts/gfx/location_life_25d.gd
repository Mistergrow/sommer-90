class_name LocationLife25D
extends Control
## Sparsame, deterministische Lebenszeichen für die fotografischen Standorte.
## Rein visuell: kein Save-Zustand, keine Gameplay-Callbacks. Die Profile liegen
## gemeinsam mit der Tiefenprojektion in data/location_25d.json.

var profile: Dictionary = {}
var location_key := ""
var _time := 0.0
var _phase := 0.0
var _speed_scale := 1.8

static var _soft_dot: ImageTexture = null
static var _live_instances := 0


func _enter_tree() -> void:
	_live_instances += 1


func _exit_tree() -> void:
	_live_instances = maxi(0, _live_instances - 1)
	if _live_instances == 0:
		# Kein statisches GPU-Objekt ueber den letzten Standort hinaus halten.
		# Ein spaeterer Ort erzeugt den winzigen 64px-Punkt bei Bedarf neu.
		_soft_dot = null


func setup(key: String, p: Dictionary) -> void:
	location_key = key
	profile = p.get("life", {}).duplicate(true)
	_speed_scale = float(p.get("life_speed", 1.8))
	_phase = float(abs(hash(key)) % 1000) * 0.013
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(not profile.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	var enabled := bool(SettingsManager.value("ambient_life"))
	if visible != enabled:
		visible = enabled
	if not enabled or profile.is_empty():
		return
	_time += delta * _speed_scale
	queue_redraw()


func _draw() -> void:
	if profile.is_empty() or size.x <= 1.0 or not bool(SettingsManager.value("ambient_life")):
		return
	_draw_near_shadow(float(profile.get("near_shadow", 0.0)))
	for entry: Dictionary in profile.get("reflections", []):
		_draw_reflection(entry)
	for entry: Dictionary in profile.get("shadows", []):
		_draw_passing_shadow(entry)
	for entry: Dictionary in profile.get("screens", []):
		_draw_screen(entry)
	if bool(profile.get("birds", false)):
		_draw_birds(profile.get("sky", [0.15, 0.03, 0.7, 0.28]))


func _norm_rect(a: Array) -> Rect2:
	if a.size() < 4:
		return Rect2()
	return Rect2(float(a[0]) * size.x, float(a[1]) * size.y,
		float(a[2]) * size.x, float(a[3]) * size.y)


## Nahe Ebene: sehr weiche Bodenkante statt schwarzer Vignette. Sie lässt
## Vordergrundtische/Gras/Racks optisch näher an die Kamera rücken.
func _draw_near_shadow(amount: float) -> void:
	if amount <= 0.001:
		return
	var bands := 12
	for i in bands:
		var f := float(i) / float(bands)
		var y := lerpf(size.y * 0.72, size.y, f)
		var h := size.y * 0.3 / float(bands) + 1.0
		draw_rect(Rect2(0, y, size.x, h), Color(0.025, 0.02, 0.035, amount * f * f))


## Wandernde Glas-/Fensterreflexion. Mehrere Streifen ergeben eine weiche Kante.
func _draw_reflection(entry: Dictionary) -> void:
	var r := _norm_rect(entry.get("rect", []))
	if r.size.x <= 1.0:
		return
	r.position += _project_offset(r.get_center())
	var speed := float(entry.get("speed", 0.025))
	var alpha := float(entry.get("alpha", 0.045))
	var cycle := fposmod(_time * speed + _phase + float(entry.get("phase", 0.0)), 1.35) - 0.2
	var cx := r.position.x + r.size.x * cycle
	var band := maxf(4.0, r.size.x * float(entry.get("width", 0.11)))
	for i in range(-3, 4):
		var fade := 1.0 - absf(float(i)) / 4.0
		var strip := Rect2(cx + float(i) * band * 0.36, r.position.y, band * 0.42, r.size.y)
		strip = strip.intersection(r)
		if strip.size.x > 0.0:
			draw_rect(strip, Color(0.9, 0.95, 1.0, alpha * fade * fade))


## Nur ein diffuser Schatten läuft durch die Szene; dadurch bleibt der
## fotorealistische Master unangetastet und suggeriert trotzdem Passanten.
func _draw_passing_shadow(entry: Dictionary) -> void:
	var y := float(entry.get("y", 0.84)) * size.y
	var width := float(entry.get("width", 0.15)) * size.x
	var height := float(entry.get("height", 0.065)) * size.y
	var speed := float(entry.get("speed", 0.018))
	var alpha := float(entry.get("alpha", 0.075))
	var u := fposmod(_time * speed + _phase + float(entry.get("phase", 0.0)), 1.45) - 0.22
	var center := Vector2(u * size.x, y + sin(_time * 0.7 + _phase) * 2.0)
	center += _project_offset(center)
	draw_texture_rect(_dot(), Rect2(center - Vector2(width, height) * 0.5,
		Vector2(width, height)), false, Color(0.02, 0.018, 0.028, alpha))


## CRT/Leuchtreklame bleibt subtil: ein wandernder Scan-Glanz innerhalb der
## angegebenen Bildschirmfläche, zusätzlich zu LocationFx-Glow.
func _draw_screen(entry: Dictionary) -> void:
	var r := _norm_rect(entry.get("rect", []))
	if r.size.x <= 1.0:
		return
	r.position += _project_offset(r.get_center())
	var alpha := float(entry.get("alpha", 0.05))
	var scan := fposmod(_time * float(entry.get("speed", 0.12)) + _phase, 1.0)
	var strip := Rect2(r.position.x, r.position.y + r.size.y * scan,
		r.size.x, maxf(1.0, r.size.y * 0.08)).intersection(r)
	if strip.size.y > 0.0:
		draw_rect(strip, Color(0.55, 0.82, 1.0, alpha))


func _draw_birds(area_value: Variant) -> void:
	var area: Array = area_value if area_value is Array else [0.15, 0.03, 0.7, 0.28]
	var r := _norm_rect(area)
	for i in 3:
		var u := fposmod(_time * (0.009 + float(i) * 0.002) + _phase * 0.1 + float(i) * 0.31, 1.2) - 0.1
		var p := Vector2(r.position.x + r.size.x * u,
			r.position.y + r.size.y * (0.25 + float(i) * 0.2 + sin(_time * 0.4 + i) * 0.04))
		p += _project_offset(p)
		var wing := 4.0 + 2.0 * sin(_time * 3.0 + float(i))
		var col := Color(0.08, 0.075, 0.09, 0.42)
		draw_arc(p + Vector2(-wing, 0), wing, PI * 1.08, PI * 1.9, 8, col, 1.2)
		draw_arc(p + Vector2(wing, 0), wing, PI * 1.1, PI * 1.92, 8, col, 1.2)


func _project_offset(point: Vector2) -> Vector2:
	var stage := get_parent()
	if stage != null and stage.has_method("offset_for_point"):
		return stage.call("offset_for_point", point)
	return Vector2.ZERO


static func _dot() -> ImageTexture:
	if _soft_dot != null:
		return _soft_dot
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2((x + 0.5) / float(s) - 0.5, (y + 0.5) / float(s) - 0.5).length() * 2.0
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.2)))
	_soft_dot = ImageTexture.create_from_image(img)
	return _soft_dot
