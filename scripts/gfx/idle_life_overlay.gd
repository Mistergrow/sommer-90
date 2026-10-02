extends Control
## IdleLifeOverlay — kleine Lebenszeichen im Zimmer: blinkende Geräte-LEDs
## (Modem/Computer), aufsteigender Kaffeedampf. Rein prozedural. Kind des
## RoomCompositors (z 19, über den Objekten, unter Wetter/Grading).
##
## LEDs/Dampf sitzen an den vorhandenen Ankern (room_anchors) und werden nur
## gezeigt, wenn das zugehörige Objekt tatsächlich im Raum ist.

const LED_MODELS_PATH := "res://data/device_leds.json"
static var _led_models: Dictionary = {}

var comp: Control = null
var _time := 0.0
var _drive_phase := randf() * 8.5   # entkoppelt Laufwerks-Flackern zwischen Geräten


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_led_models()


static func _load_led_models() -> void:
	if not _led_models.is_empty():
		return
	var f := FileAccess.open(LED_MODELS_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_led_models = parsed


## Modell-Schlüssel eines Objekts (Asset-Basisname ohne _Vxx).
static func model_key(asset: String) -> String:
	var base := asset.to_upper()
	var vi := base.rfind("_V")
	if vi > 0:
		base = base.substr(0, vi)
	return base


## Erster Marker eines Typs (z. B. "light" der Lampe) im Raum → Bildschirm-Punkt
## + Größe. Für andere Overlays (DayNight-Lampenpool). {} wenn keiner.
static func first_feature(room_comp: Control, type: String) -> Dictionary:
	_load_led_models()
	var models: Dictionary = _led_models.get("models", {})
	if room_comp == null:
		return {}
	for c in room_comp.get_children():
		if not (c is TextureRect) or c.get_meta("is_shadow", false):
			continue
		var key := model_key(str(c.get_meta("asset", "")))
		for led: Dictionary in models.get(key, {}).get("leds", []):
			if str(led.get("type", "led")) == type:
				return {
					"center": c.position + Vector2(float(led.get("x", 0.5)) * c.size.x,
						float(led.get("y", 0.5)) * c.size.y),
					"size": Vector2(float(led.get("w", 0.1)), float(led.get("h", 0.1))) * c.size,
				}
	return {}


## Blink-Wert 0..1 je Verhalten (Datenfeld "blink" je LED, pro Asset gesetzt).
## `powered` = ob die Stromdomäne des Geräts (power_domain) an ist.
##   power  = Betriebs-LED: an solange das Gerät mit Strom ist, sonst aus.
##   drive  = Laufwerks-/Zugriffs-LED: im Leerlauf AUS, ab und zu kurzer Zugriff.
##   rx/tx  = Modem-Daten (schnelles Flackern).  slow = langsames Pulsen.
##   steady = leichtes Dauerglühen (Standard).   off = immer aus.
func _blink(kind: String, powered: bool = true) -> float:
	if not powered:
		return 0.0   # stromlos = dunkel, egal welcher Blink-Typ (Physik vor Deko)
	match kind:
		"power":
			return 0.9 + 0.1 * sin(_time * 2.0)
		"drive":
			return _drive_access()
		"slow":
			return 0.55 + 0.45 * sin(_time * 2.0)
		"rx":
			return 0.5 + 0.5 * sign(sin(_time * 7.0 + 1.0))
		"tx":
			return 0.5 + 0.5 * sign(sin(_time * 11.0))
		"off":
			return 0.0
		_:
			return 0.85 + 0.15 * sin(_time * 2.0)   # steady (leichtes Pulsieren)


## Laufwerks-Zugriff simulieren: meist 0 (LED aus), alle ~8,5 s ein kurzer
## Schub schnellen Flackerns — wie ein gelegentlicher Diskettenzugriff.
func _drive_access() -> float:
	var cycle := fmod(_time + _drive_phase, 8.5)
	if cycle < 0.45:
		return 0.5 + 0.5 * sign(sin(_time * 34.0))
	return 0.0


func _process(delta: float) -> void:
	if comp == null or comp.edit_mode or Engine.is_editor_hint():
		return
	_time += delta
	queue_redraw()


func _anchor(anchor_name: String):
	var anchors: Dictionary = comp.config().get("anchors", {}) if comp != null else {}
	if anchors.has(anchor_name):
		var a: Array = anchors[anchor_name]
		return Vector2(a[0], a[1])
	return null





func _draw() -> void:
	if comp == null or comp.edit_mode:
		return
	var t: Dictionary = comp._master_transform()
	var sc: float = t["scale"]

	# --- Geräte-LEDs: je Objekt-Modell aus device_leds.json, Sprite-relativ ---
	var models: Dictionary = _led_models.get("models", {})
	for c in comp.get_children():
		if not (c is TextureRect) or c.get_meta("is_shadow", false):
			continue
		var key := model_key(str(c.get_meta("asset", "")))
		if not models.has(key):
			continue
		# Stromdomäne des Geräts (power_domain) → power/drive-LEDs an/aus.
		var powered: bool = UIManager.domain_on(str(models[key].get("power_domain", "mains")))
		for led: Dictionary in models[key].get("leds", []):
			var mtype := str(led.get("type", "led"))
			var center: Vector2 = c.position + Vector2(float(led.get("x", 0.5)) * c.size.x,
				float(led.get("y", 0.5)) * c.size.y)
			match mtype:
				"led":
					var col: Array = led.get("color", [1.0, 0.4, 0.35])
					var w: float = float(led.get("w", 0.04)) * c.size.x
					var h: float = float(led.get("h", 0.05)) * c.size.y
					var r := Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))
					_led_draw(r, str(led.get("shape", "rect")), Color(col[0], col[1], col[2]),
						_blink(str(led.get("blink", "steady")), powered))
				"steam":
					# Dampf-Auslass (z. B. Kaffeetasse) — Marker = Ursprung
					_steam(center, sc)
				# "light" macht das DayNightOverlay (Lampenpool), "key" ist inert


## Leuchtende LED im Rahmen: eckig (Standard, füllt den Rahmen) oder rund.
## Heller Kern + weicher Halo. `r` = LED-Rahmen (Bildschirm-Koords).
func _led_draw(r: Rect2, shape: String, col: Color, on: float) -> void:
	if on <= 0.02:
		# aus: matte Fassung
		var dim := Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.7)
		if shape == "round":
			draw_circle(r.get_center(), maxf(1.0, minf(r.size.x, r.size.y) * 0.5), dim)
		else:
			draw_rect(r, dim)
		return
	if shape == "round":
		var p := r.get_center()
		var rad := maxf(1.2, minf(r.size.x, r.size.y) * 0.5)
		draw_circle(p, rad * 2.2, Color(col.r, col.g, col.b, 0.10 * on))
		draw_circle(p, rad * 1.4, Color(col.r, col.g, col.b, 0.20 * on))
		draw_circle(p, rad, Color(col.r, col.g, col.b, 0.95 * on))
		draw_circle(p - Vector2(rad * 0.3, rad * 0.3), rad * 0.4, Color(1, 1, 1, 0.8 * on))
	else:
		var pad := minf(r.size.x, r.size.y)
		draw_rect(r.grow(pad * 0.7), Color(col.r, col.g, col.b, 0.09 * on))
		draw_rect(r.grow(pad * 0.3), Color(col.r, col.g, col.b, 0.18 * on))
		draw_rect(r, Color(col.r, col.g, col.b, 0.95 * on))
		draw_rect(Rect2(r.position + r.size * 0.2, r.size * 0.32), Color(1, 1, 1, 0.7 * on))


## Aufsteigender Dampf: mehrere langsam nach oben wandernde, verwehende Punkte.
func _steam(base: Vector2, sc: float) -> void:
	for i in 7:
		var life := fposmod(_time * 0.4 + float(i) / 7.0, 1.0)   # 0..1 Aufstieg
		var rise := life * 60.0 * sc
		var sway := sin(_time * 1.3 + float(i) * 1.7 + life * 3.0) * (6.0 + life * 12.0) * sc
		var p := base + Vector2(sway, -rise)
		# unten dicht, oben verweht + größer
		var a := (1.0 - life) * 0.14 * smoothstep(0.0, 0.2, life)
		var r := (2.0 + life * 7.0) * sc
		draw_circle(p, r, Color(0.92, 0.92, 0.9, a))
