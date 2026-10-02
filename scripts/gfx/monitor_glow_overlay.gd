extends Control
## MonitorGlowOverlay — zeigt auf der Zimmer-Bildröhre das Standbild des zuletzt
## am Computer genutzten Programms (`UIManager.monitor_texture`) und lässt den
## Monitor in dessen Farbe leuchten: ein farbiger Lichtwurf (Spill) fällt auf
## Tastatur/Tisch. Je Monitormodell unterschiedlich getönt & gekrümmt
## (`data/monitors.json` = die „CRT-Daten pro Monitor"). Kind des
## RoomCompositors, z 24 — ÜBER dem Tageszeit-Grading, damit der Bildschirm
## selbst leuchtet (nachts hell) statt mit abgedunkelt zu werden.

const MODELS_PATH := "res://data/monitors.json"
static var _models: Dictionary = {}
static var _glow_tex: ImageTexture = null

var comp: Control = null
var _screen: TextureRect = null   # das Standbild auf der Glasfläche
var _spill: TextureRect = null    # additiver Lichtwurf auf den Tisch
var _model: Dictionary = {}
var _screen_rect: Rect2 = Rect2()
var _edit_frac: Array = []   # aktive Bearbeitung (Deko-Editor) überschreibt das Modell


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # knackige Kickstart-Pixel
	_load_models()

	_screen = TextureRect.new()
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Monitor-LOKALER CRT-Effekt direkt auf dem Röhrenbild (Krümmung/Scanlines/
	# Phosphor/Bloom/Konvergenz), pro Modell aus monitors.json (s. VFX_BIBLE EFFECT_005).
	var crt_mat := ShaderMaterial.new()
	crt_mat.shader = preload("res://shaders/monitor_crt.gdshader")
	_screen.material = crt_mat
	add_child(_screen)

	_spill = TextureRect.new()
	_spill.texture = _glow_texture()
	_spill.stretch_mode = TextureRect.STRETCH_SCALE
	_spill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_spill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_spill.material = add
	add_child(_spill)

	if not Engine.is_editor_hint():
		if not UIManager.monitor_changed.is_connected(_refresh):
			UIManager.monitor_changed.connect(_refresh)
		if not UIManager.power_changed.is_connected(_refresh):
			UIManager.power_changed.connect(_refresh)
	# Neu layouten, wenn der Compositor den Raum (und damit den Monitor) dimensioniert
	# — sonst bleibt der Bildröhren-Bereich 0 (Spiegelung unsichtbar bei aus-Monitor).
	if comp != null and comp is Control and not comp.resized.is_connected(_refresh):
		comp.resized.connect(_refresh)
	_refresh.call_deferred()


func _refresh() -> void:
	_layout()
	queue_redraw()


## Warmlauf herunterzählen + Röhre animieren (Kickstart-Einschub, Flicker).
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if UIManager.monitor_warmup_t > 0.0:
		UIManager.monitor_warmup_t = maxf(0.0, UIManager.monitor_warmup_t - delta)
		queue_redraw()
	if not UIManager.monitor_power:
		return
	# Nur Kickstart 2.x+ animiert die Diskette. Der A500/1.3-Schirm bleibt
	# absichtlich statisch und erzeugt deshalb keine unnötigen Dauer-Redraws.
	if UIManager.boot_state() == "kickstart" and KickstartScreen.is_animated():
		queue_redraw()
	if _screen != null and _screen.visible and UIManager.monitor_on:
		var calm := bool(SettingsManager.value("reduced_motion"))
		(_screen.material as ShaderMaterial).set_shader_parameter("reduced_motion", calm)
		var ms := Time.get_ticks_msec() * 0.001
		var f := 1.0 if calm else 1.0 + 0.012 * sin(ms * 11.0) + 0.006 * sin(ms * 43.0)
		_screen.self_modulate = Color(f, f, f, 1.0)


## Modell-Schlüssel = Asset-Basisname ohne _Vxx (z. B. MONITOR_COMMODORE_1084S).
func _model_key(monitor: TextureRect) -> String:
	var asset := str(monitor.get_meta("asset", "")).to_upper()
	var base := asset
	var vi := base.rfind("_V")
	if vi > 0:
		base = base.substr(0, vi)
	return base


func _model_for(monitor: TextureRect) -> Dictionary:
	var models: Dictionary = _models.get("models", {})
	var key := _model_key(monitor)
	if models.has(key):
		return models[key]
	return models.get("default", {})


## Welche der drei "uncalibrated"-Varianten hat DIESER Spielstand? Einmal pro Spiel
## festgelegt (deterministisch stabil bis zum Kalibrieren).
func _uncal_index() -> int:
	var f: Dictionary = GameManager.flags
	if not f.has("monitor_uncal_variant"):
		f["monitor_uncal_variant"] = randi() % 3
	return int(f["monitor_uncal_variant"])


## CRT-Shader-Uniforms setzen: Basis pro Monitormodell (1084S ≠ 1901) und — solange
## nicht kalibriert — eine der drei uncalibrated-Varianten drüber. Im Deko-Editor
## neutraler Look (keine Krümmung/Defekte) zum sauberen Bearbeiten.
func _apply_crt_shader() -> void:
	var mat := _screen.material as ShaderMaterial
	if mat == null:
		return
	var ph: Array = _model.get("phosphor", [1.0, 1.0, 1.0])
	var crt: Dictionary = _model.get("crt", {})
	var p := {
		"curvature": float(_model.get("curvature", 0.06)),
		"scanline": float(_model.get("scanline", 0.30)),
		"brightness": float(_model.get("brightness", 1.15)),
		"phosphor": Vector3(float(ph[0]), float(ph[1]), float(ph[2])),
		"bloom": float(crt.get("bloom", 0.10)),
		"aberration": float(crt.get("aberration", 0.0007)),
		"vignette": float(crt.get("vignette", 0.14)),
		"tint": Vector3(1.0, 1.0, 1.0),
		"roll_strength": 0.0,
		"flicker": 0.0,
		"jitter": 0.0,
		"focus": float(crt.get("focus", 0.70)),
		"mask_strength": float(crt.get("mask_strength", 0.22)),
		"interlace_artifact": float(crt.get("interlace_artifact", 0.25)),
	}
	var editing: bool = comp != null and comp.edit_mode
	if not editing and not Engine.is_editor_hint() \
			and not bool(GameManager.flags.get("monitor_calibrated", false)):
		var variants: Array = _model.get("uncalibrated", [])
		if not variants.is_empty():
			var v: Dictionary = variants[_uncal_index() % variants.size()]
			for k: String in v:
				if k == "name":
					continue
				if k == "tint":
					var t: Array = v[k]
					p["tint"] = Vector3(float(t[0]), float(t[1]), float(t[2]))
				else:
					p[k] = float(v[k])
	if editing or Engine.is_editor_hint():
		p["curvature"] = 0.0   # Deko-Editor: unverzerrt bearbeiten
	for k: String in p:
		mat.set_shader_parameter(k, p[k])


func _monitor_node() -> TextureRect:
	if comp == null:
		return null
	for c in comp.get_children():
		if c is TextureRect and str(c.get_meta("anchor", "")) == "monitor_base" \
				and not bool(c.get_meta("is_shadow", false)):
			return c
	return null


func _layout() -> void:
	var editing: bool = comp != null and comp.edit_mode
	var powered: bool = UIManager.monitor_power
	var monitor := _monitor_node()
	if monitor == null:
		for r: TextureRect in [_screen, _spill]:
			if r != null:
				r.visible = false
		return

	_model = _model_for(monitor)
	# Im Deko-Modus die (evtl. gerade bearbeitete) Fläche live vorschauen.
	var frac: Array = editor_frac() if editing else _model.get("screen_frac", [0.2, 0.12, 0.6, 0.46])
	var mpos := monitor.position
	var msize := monitor.size
	_screen_rect = Rect2(
		mpos + Vector2(float(frac[0]) * msize.x, float(frac[1]) * msize.y),
		Vector2(float(frac[2]) * msize.x, float(frac[3]) * msize.y))

	var state := UIManager.boot_state()
	# Bildinhalt zeigen: Standbild (gebootet) ODER Live-Screen (der Amiga läuft
	# in Echtzeit weiter, z. B. eine Sounddiskette als Demoscreen).
	var show_still: bool = (state == "booted" or UIManager.monitor_live) \
		and UIManager.monitor_on and UIManager.monitor_texture != null

	# Ab hier leuchtet nur die eingeschaltete (oder im Editor vorgeschaute) Röhre.
	if not powered and not editing:
		if _screen != null:
			_screen.visible = false
		if _spill != null:
			_spill.visible = false
		return

	if show_still:
		_screen.texture = UIManager.monitor_texture
		_screen.position = _screen_rect.position
		_screen.size = _screen_rect.size
		# Phosphor/Helligkeit macht jetzt der CRT-Shader (samt Krümmung/Zeilen).
		_screen.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_apply_crt_shader()
		_screen.visible = true
	else:
		_screen.visible = false

	# Lichtwurf je Zustand: Standbild → Bildschirmfarbe · Kickstart → helles Grau
	# (das Boot-Bild erhellt den Tisch) · „kein Signal"/aus → kein Spill.
	if not (state == "kickstart" or show_still):
		_spill.visible = false
		return
	var spill_a := float(_model.get("spill", 0.85))
	var c := UIManager.monitor_color if show_still else _kickstart_spill()
	var radius := _screen_rect.size.x * 1.9
	var center := _screen_rect.get_center() + Vector2(0.0, _screen_rect.size.y * 0.9)
	_spill.size = Vector2(radius * 2.0, radius * 2.0)
	_spill.position = center - Vector2(radius, radius)
	_spill.modulate = Color(c.r, c.g, c.b, spill_a * (0.7 if not show_still else 1.0))
	_spill.visible = true


## Lichtfarbe des Kickstart-Bilds (heller Grau-Ton) für den Tisch-Lichtwurf.
func _kickstart_spill() -> Color:
	var bg: Array = KickstartScreen.config().get("bg", [0.6, 0.61, 0.66])
	return Color(bg[0], bg[1], bg[2])


func _draw() -> void:
	if Engine.is_editor_hint() or _screen_rect.size.x < 2.0:
		return
	var r := _screen_rect
	if not UIManager.monitor_power:
		# Dunkle Roehre: lokale Lichtformen auf gewoelbtem Glas statt eines
		# perspektivisch falschen, verkleinerten Bildes des leeren Master-Zimmers.
		draw_rect(r, Color(0.012, 0.018, 0.024, 0.58), true)
		_draw_local_glass_reflection(r, 0.14)
		return
	var state := UIManager.boot_state()
	# Röhreninhalt je Zustand
	if state == "kickstart":
		KickstartScreen.draw_into(self, r, Time.get_ticks_msec() * 0.001)
	elif state == "nosignal":
		draw_rect(r, Color(0.02, 0.03, 0.05))   # Monitor an, kein Eingang: dunkel
	elif not _screen.visible:
		draw_rect(r, Color(0.02, 0.03, 0.05))   # gebootet, aber (noch) kein Standbild
	if state == "nosignal" or (state != "kickstart" and not _screen.visible):
		_draw_local_glass_reflection(r, 0.075)

	# Scanlines nur für Zustände OHNE Standbild (Kickstart/kein Signal) hier zeichnen;
	# beim Standbild macht sie der Monitor-CRT-Shader (mit Krümmung) auf dem Bild selbst.
	if not _screen.visible:
		var scan := float(_model.get("scanline", 0.28))
		var step := maxf(2.0, r.size.y / 90.0)
		var y := r.position.y
		while y < r.position.y + r.size.y:
			draw_rect(Rect2(r.position.x, y, r.size.x, maxf(1.0, step * 0.42)),
				Color(0, 0, 0, 0.14 * scan / 0.28))
			y += step
	draw_rect(r, Color(0, 0, 0, 0.28), false, maxf(1.0, r.size.x * 0.02))
	var c := UIManager.monitor_color if _screen.visible else _kickstart_spill()
	draw_rect(r.grow(r.size.x * 0.015), Color(c.r, c.g, c.b, 0.20), false, maxf(1.0, r.size.x * 0.02))

	# --- Einschalt-Effekt (CRT-Warmlauf): heller Blitz + aufziehende Zeile ---
	var wu := UIManager.monitor_warmup_t
	if wu > 0.0:
		var p := 1.0 - clampf(wu / 0.9, 0.0, 1.0)   # 0 → 1 im Verlauf
		draw_rect(r, Color(1, 1, 1, 0.55 * wu / 0.9))              # kurzer Vollbild-Blitz
		var band_h := maxf(2.0, r.size.y * clampf(p * 1.6, 0.02, 1.0))
		var band := Rect2(r.position.x, r.get_center().y - band_h * 0.5, r.size.x, band_h)
		draw_rect(band, Color(0.85, 0.95, 1.0, 0.9 * (1.0 - p)))    # aufziehende Bildzeile


## Abstrakte Nahreflexion auf der konvexen Röhre: zwei verzogene Fensterkanten
## und ein kleiner Lampensaum. Keine Raumtextur, keine erkennbaren Möbel und
## dadurch kein falscher zweiter/leerer Raum im Bildschirm.
func _draw_local_glass_reflection(r: Rect2, alpha: float) -> void:
	var p := r.position
	var s := r.size
	var window_sliver := PackedVector2Array([
		p + Vector2(s.x * 0.66, s.y * 0.08), p + Vector2(s.x * 0.86, s.y * 0.12),
		p + Vector2(s.x * 0.67, s.y * 0.55), p + Vector2(s.x * 0.56, s.y * 0.43)])
	draw_colored_polygon(window_sliver, Color(0.68, 0.79, 0.88, alpha * 0.34))
	var rim := PackedVector2Array([
		p + Vector2(s.x * 0.08, s.y * 0.18), p + Vector2(s.x * 0.13, s.y * 0.10),
		p + Vector2(s.x * 0.23, s.y * 0.13), p + Vector2(s.x * 0.15, s.y * 0.22)])
	draw_colored_polygon(rim, Color(1.0, 0.82, 0.57, alpha * 0.22))
	# Konvexer Randabfall bindet die Reflexe ans Glas statt an eine flache Ebene.
	draw_rect(r.grow(-maxf(1.0, s.x * 0.035)), Color(0.55, 0.67, 0.76, alpha * 0.20), false,
		maxf(1.0, s.x * 0.018))


# ------------------------------------------------- Editor (Deko-Modus F6/F8)
## Aktuelle Bildschirmfläche als Anteil [x,y,w,h] des Monitor-Sprites.
func editor_frac() -> Array:
	if not _edit_frac.is_empty():
		return _edit_frac
	var m := _monitor_node()
	if m == null:
		return [0.2, 0.12, 0.6, 0.46]
	return (_model_for(m).get("screen_frac", [0.2, 0.12, 0.6, 0.46]) as Array).duplicate()


## Modell-Schlüssel des aktuellen Monitors (Asset-Basisname) — je Modell wird
## eine eigene Bildschirmfläche gespeichert (weitere Modelle folgen).
func editor_model_key() -> String:
	var m := _monitor_node()
	return _model_key(m) if m != null else ""


## Die Bildschirmfläche in Bildschirm-Koordinaten (für die Griffe im Editor).
func editor_screen_rect() -> Rect2:
	var m := _monitor_node()
	if m == null:
		return Rect2()
	var f := editor_frac()
	return Rect2(
		m.position + Vector2(float(f[0]) * m.size.x, float(f[1]) * m.size.y),
		Vector2(float(f[2]) * m.size.x, float(f[3]) * m.size.y))


## Neues Rechteck (Bildschirm-Koords) → als Anteil des Sprites merken + Vorschau.
func editor_set_rect(r: Rect2) -> void:
	var m := _monitor_node()
	if m == null or m.size.x <= 1.0 or m.size.y <= 1.0:
		return
	_edit_frac = [
		snappedf((r.position.x - m.position.x) / m.size.x, 0.001),
		snappedf((r.position.y - m.position.y) / m.size.y, 0.001),
		snappedf(r.size.x / m.size.x, 0.001),
		snappedf(r.size.y / m.size.y, 0.001)]
	_layout()
	queue_redraw()


## In data/monitors.json unter dem Modell-Schlüssel speichern (F8).
func editor_save() -> void:
	if _edit_frac.is_empty():
		return
	var key := editor_model_key()
	if key == "":
		return
	var data: Dictionary = {}
	var rf := FileAccess.open(MODELS_PATH, FileAccess.READ)
	if rf != null:
		var parsed: Variant = JSON.parse_string(rf.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	var models: Dictionary = data.get("models", {})
	var entry: Dictionary = models.get(key, models.get("default", {})).duplicate()
	entry["screen_frac"] = _edit_frac
	models[key] = entry
	data["models"] = models
	var wf := FileAccess.open(MODELS_PATH, FileAccess.WRITE)
	if wf != null:
		wf.store_string(JSON.stringify(data, "\t", false))
	_models = data       # statischen Cache aktualisieren
	_edit_frac = []      # Bearbeitung übernommen


# ------------------------------------------------------------- Daten & Textur
func _load_models() -> void:
	if not _models.is_empty():
		return
	var f := FileAccess.open(MODELS_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_models = parsed


## Weicher Radialverlauf (einmal erzeugt) für den Lichtwurf.
static func _glow_texture() -> ImageTexture:
	if _glow_tex != null:
		return _glow_tex
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for yy in s:
		for xx in s:
			var d := Vector2((xx - s * 0.5) / (s * 0.5), (yy - s * 0.5) / (s * 0.5)).length()
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			img.set_pixel(xx, yy, Color(1, 1, 1, a))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex
