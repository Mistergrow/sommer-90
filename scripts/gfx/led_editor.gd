extends Control
## LED-Editor (scenes/LedEditor.tscn) — dediziertes Werkzeug, um pro Geräte-
## Modell die LED-Positionen zu setzen. Mit F6 ("Aktuelle Szene ausführen")
## starten.
##
## Bedienung:
##   ← / →  bzw. Bild auf/ab .... Objekt wechseln
##   Linksklick auf leere Fläche  neue LED setzen
##   LED ziehen ................. verschieben (Position = Anteil des Sprites)
##   C .......................... Farbe der gewählten LED durchschalten
##   B .......................... Verhalten durchschalten (power/drive/steady/slow/rx/tx/off)
##   D .......................... Stromdomäne durchschalten (mains/strip/monitor/amiga)
##   N .......................... Modell explizit als „ohne LED“ markieren
##   Entf / Rücktaste ........... gewählte LED löschen
##   F8 / Strg+S ................ speichern nach data/device_leds.json
##
## Speichert je Modell (Asset-Basisname ohne _Vxx). Profil-Metadaten bleiben
## vollständig erhalten; Modelle ohne Leuchtmittel werden mit no_led markiert.

const CONFIG_PATH := "res://data/room_anchors.json"
const LED_PATH := "res://data/device_leds.json"
const DEVICE_CATALOG_PATH := "res://scripts/gfx/room_device_catalog.gd"
const RoomCompositorScript := preload("res://scripts/gfx/room_compositor.gd")
const IdleLifeScript := preload("res://scripts/gfx/idle_life_overlay.gd")

const PALETTE := [
	[0.4, 1.0, 0.5],   # grün
	[1.0, 0.78, 0.3],  # amber
	[1.0, 0.35, 0.35], # rot
	[0.45, 0.7, 1.0],  # blau
	[0.95, 0.95, 1.0], # weiß
]
const BLINKS := ["power", "drive", "steady", "slow", "rx", "tx", "off"]
const POWER_DOMAINS := ["mains", "strip", "monitor", "amiga"]
# Marker-Typen: led = leuchtende LED · light = Lichtquelle (z. B. Lampenbirne) ·
# steam = Dampf-Auslass (z. B. Kaffeetasse) · key = Taste/Markierung (inert).
const TYPES := ["led", "light", "steam", "key"]
const TYPE_COL := {
	"led": Color(0.3, 0.9, 1.0), "light": Color(1.0, 0.85, 0.4),
	"steam": Color(0.8, 0.9, 1.0), "key": Color(0.8, 0.8, 0.85),
}

const DEF_W := 0.05            # Standard-Rahmengröße (Anteil des Sprites)
const DEF_H := 0.06

var _assets: Array = []        # [{key, path, tex}]
var _index := 0
var _leds: Dictionary = {}     # key -> Array[{x,y,w,h,color,blink}]  x,y = Mitte
var _profiles: Dictionary = {} # key -> Profildaten OHNE leds (power_domain/no_led/…)
var _selected := -1
var _dragging := false         # Rahmen verschieben
var _resize := -1              # gezogene Ecke (0-3) beim Skalieren, -1 = keine
var _grab := Vector2.ZERO      # Griff-Versatz beim Verschieben (Anteil)
var _sprite_rect := Rect2()
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _time := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_leds()
	_gather_assets() # nach Profilen: bestehende Spezialprofile in die Auswahl übernehmen
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _key() -> String:
	return _assets[_index]["key"] if _index >= 0 and _index < _assets.size() else ""


func _cur_leds() -> Array:
	var k := _key()
	if k == "" or not _leds.has(k):
		return []
	return _leds[k]


# ------------------------------------------------------------- Laden
## Alle in einem Raum-Layer referenzierten Stems, unabhängig davon, ob der
## Layer ein festes Asset oder austauschbare asset_by_model-Varianten besitzt.
## Öffentlich/statisch gehalten, damit der Datenvertrag headless testbar bleibt.
static func asset_stems_from_layer(layer: Dictionary) -> Array:
	var stems: Array = []
	_append_stems(layer.get("asset", ""), stems)
	_append_stems(layer.get("assets", []), stems)
	var by_model: Variant = layer.get("asset_by_model", {})
	if typeof(by_model) == TYPE_DICTIONARY:
		var model_ids: Array = (by_model as Dictionary).keys()
		model_ids.sort()
		for model_id: Variant in model_ids:
			_append_stems((by_model as Dictionary)[model_id], stems)
	return stems


static func _append_stems(value: Variant, target: Array) -> void:
	if typeof(value) == TYPE_ARRAY:
		for item: Variant in value:
			_append_stems(item, target)
		return
	var stem := str(value).strip_edges()
	if stem != "" and not target.has(stem):
		target.append(stem)


## Fügt bearbeitete Marker in vorhandene Daten ein. `profiles` ist für seine
## Keys autoritativ, damit z. B. ein bewusst entferntes no_led auch verschwindet;
## Modelle außerhalb der Editor-Auswahl und unbekannte Top-Level-Felder bleiben.
static func merged_led_data(existing: Dictionary, profiles: Dictionary,
		led_lists: Dictionary) -> Dictionary:
	var data: Dictionary = existing.duplicate(true)
	var models: Dictionary = {}
	if typeof(data.get("models", {})) == TYPE_DICTIONARY:
		models = (data.get("models", {}) as Dictionary).duplicate(true)
	var keys: Array = profiles.keys()
	for k: Variant in led_lists.keys():
		if not keys.has(k):
			keys.append(k)
	for key_v: Variant in keys:
		var key := str(key_v)
		var profile: Dictionary
		if profiles.has(key):
			profile = (profiles[key] as Dictionary).duplicate(true)
		elif typeof(models.get(key, {})) == TYPE_DICTIONARY:
			profile = (models.get(key, {}) as Dictionary).duplicate(true)
		else:
			profile = {}
		profile.erase("leds")
		var markers: Array = (led_lists.get(key, []) as Array).duplicate(true)
		if markers.is_empty() and profile.is_empty():
			models.erase(key)
		else:
			profile["leds"] = markers
			models[key] = profile
	data["models"] = models
	return data


func _gather_assets() -> void:
	_assets.clear()
	var seen := {}
	_gather_catalog_assets(seen)
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# Direkter JSON-Fallback bleibt absichtlich bestehen: Der Standalone-Editor
	# funktioniert auch während Catalog-Migrationen und sieht zudem Nicht-Geräte.
	for layer: Dictionary in (parsed as Dictionary).get("layers", []):
		for stem: Variant in asset_stems_from_layer(layer):
			_append_asset(str(stem), str(layer.get("id", stem)), seen)
	# Spezialmarker (Lampe, Telefon, Tasse) und bewusst LED-lose Profile bleiben
	# auch dann editierbar, wenn sie später aus der Raumkonfiguration ausziehen.
	var profile_keys: Array = _profiles.keys()
	profile_keys.sort()
	for key: Variant in profile_keys:
		_append_asset(str(key), "Profil: " + str(key), seen)
	_assets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("key", "")) < str(b.get("key", "")))


func _gather_catalog_assets(seen: Dictionary) -> void:
	if not ResourceLoader.exists(DEVICE_CATALOG_PATH):
		return
	var catalog_script: Variant = load(DEVICE_CATALOG_PATH)
	if catalog_script == null or not catalog_script.has_method("catalog"):
		return
	var definitions: Variant = catalog_script.call("catalog", true)
	if typeof(definitions) != TYPE_DICTIONARY:
		return
	for definition_v: Variant in (definitions as Dictionary).values():
		if typeof(definition_v) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = definition_v
		for model_v: Variant in (definition.get("models", {}) as Dictionary).values():
			if typeof(model_v) != TYPE_DICTIONARY:
				continue
			for stem: Variant in (model_v as Dictionary).get("assets", []):
				_append_asset(str(stem), str(definition.get("id", stem)), seen)


func _append_asset(stem: String, layer_id: String, seen: Dictionary) -> void:
	var path := RoomCompositorScript.find_asset(stem)
	if path == "":
		return
	var key: String = IdleLifeScript.model_key(path.get_file().get_basename())
	if seen.has(key):
		return
	var tex := RoomCompositorScript.load_texture(path)
	if tex == null:
		return
	seen[key] = true
	_assets.append({"key": key, "path": path, "tex": tex, "id": layer_id})


func _load_leds() -> void:
	_leds.clear()
	_profiles.clear()
	var f := FileAccess.open(LED_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var models: Dictionary = (parsed as Dictionary).get("models", {})
	for k: String in models:
		var profile: Dictionary = (models[k] as Dictionary).duplicate(true)
		_leds[k] = (profile.get("leds", []) as Array).duplicate(true)
		profile.erase("leds")
		_profiles[k] = profile


func _save() -> void:
	var data: Dictionary = {"comment": "LED-Positionen je Geräte-Modell (Idle-Leben). Bearbeitet im LED-Editor.", "models": {}}
	# vorhandene Datei lesen, um Kommentar/andere Felder zu erhalten
	var rf := FileAccess.open(LED_PATH, FileAccess.READ)
	if rf != null:
		var parsed: Variant = JSON.parse_string(rf.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
	data = merged_led_data(data, _profiles, _leds)
	var wf := FileAccess.open(LED_PATH, FileAccess.WRITE)
	if wf != null:
		wf.store_string(JSON.stringify(data, "\t", false))


# ------------------------------------------------------------- Layout/Geometrie
func _compute_sprite_rect() -> void:
	if _index < 0 or _index >= _assets.size():
		_sprite_rect = Rect2()
		return
	var tex: Texture2D = _assets[_index]["tex"]
	var ts := Vector2(tex.get_size())
	var avail := Vector2(size.x * 0.7, size.y * 0.7)
	var s: float = minf(avail.x / ts.x, avail.y / ts.y) * _zoom
	var draw_size := ts * s
	_sprite_rect = Rect2(((size - draw_size) * 0.5 + _pan).floor(), draw_size)


## Bildschirm-Rechteck einer LED (x,y = Mitte, w,h = Größe — je Anteil des Sprites).
func _led_rect(led: Dictionary) -> Rect2:
	var c := _sprite_rect.position + Vector2(float(led.get("x", 0.5)), float(led.get("y", 0.5))) * _sprite_rect.size
	var sz := Vector2(float(led.get("w", DEF_W)), float(led.get("h", DEF_H))) * _sprite_rect.size
	return Rect2(c - sz * 0.5, sz)


func _rect_corners(r: Rect2) -> Array:
	return [r.position, r.position + Vector2(r.size.x, 0), r.position + r.size,
		r.position + Vector2(0, r.size.y)]


func _led_at(point: Vector2) -> int:
	var leds := _cur_leds()
	for i in leds.size():
		if _led_rect(leds[i]).grow(3.0).has_point(point):
			return i
	return -1


# ------------------------------------------------------------- Eingabe
func _corner_at(point: Vector2) -> int:
	var leds := _cur_leds()
	if _selected < 0 or _selected >= leds.size():
		return -1
	var cs := _rect_corners(_led_rect(leds[_selected]))
	for i in 4:
		if (cs[i] as Vector2).distance_to(point) <= 9.0:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_compute_sprite_rect()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_resize = _corner_at(event.position)          # Ecke der Auswahl?
				if _resize >= 0:
					queue_redraw(); return
				var hit := _led_at(event.position)
				if hit >= 0:
					_selected = hit
					_dragging = true
					var c := _led_rect(_cur_leds()[hit]).get_center()
					_grab = (event.position - c)
				elif _sprite_rect.has_point(event.position):
					var frac: Vector2 = (event.position - _sprite_rect.position) / _sprite_rect.size
					var k := _key()
					if k != "":
						_profile(k).erase("no_led")
						if not _leds.has(k):
							_leds[k] = []
						_leds[k].append({"type": "led", "x": snappedf(frac.x, 0.001), "y": snappedf(frac.y, 0.001),
							"w": DEF_W, "h": DEF_H, "shape": "rect",
							"color": PALETTE[0], "blink": "steady"})
						_selected = _leds[k].size() - 1
						_dragging = true
						_grab = Vector2.ZERO
				queue_redraw()
			MOUSE_BUTTON_MIDDLE:
				_panning = true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, 0.87)
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = false
			_resize = -1
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
	elif event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			queue_redraw()
			return
		if _sprite_rect.size.x <= 1.0:
			return
		var leds := _cur_leds()
		if _selected < 0 or _selected >= leds.size():
			return
		var led: Dictionary = leds[_selected]
		if _resize >= 0:
			# Rahmen skalieren: gegenüberliegende Ecke fix, Mitte/Größe neu
			var r := _led_rect(led)
			var fixed: Vector2 = _rect_corners(r)[(_resize + 2) % 4]
			var nr := Rect2(Vector2(minf(fixed.x, event.position.x), minf(fixed.y, event.position.y)),
				(event.position - fixed).abs())
			var center := (nr.position + nr.size * 0.5 - _sprite_rect.position) / _sprite_rect.size
			var sz := nr.size / _sprite_rect.size
			led["x"] = snappedf(center.x, 0.001)
			led["y"] = snappedf(center.y, 0.001)
			led["w"] = snappedf(maxf(sz.x, 0.006), 0.001)
			led["h"] = snappedf(maxf(sz.y, 0.006), 0.001)
			queue_redraw()
		elif _dragging:
			var frac: Vector2 = (event.position - _grab - _sprite_rect.position) / _sprite_rect.size
			led["x"] = snappedf(clampf(frac.x, 0.0, 1.0), 0.001)
			led["y"] = snappedf(clampf(frac.y, 0.0, 1.0), 0.001)
			queue_redraw()


## Zoom zum Zeiger (Punkt unter der Maus bleibt fix).
func _zoom_at(p: Vector2, factor: float) -> void:
	if _index < 0 or _index >= _assets.size():
		return
	_compute_sprite_rect()
	var frac := (p - _sprite_rect.position) / _sprite_rect.size
	_zoom = clampf(_zoom * factor, 1.0, 10.0)
	# Basis-Rechteck (ohne Pan) neu bestimmen und Pan so setzen, dass frac fix bleibt
	var tex: Texture2D = _assets[_index]["tex"]
	var ts := Vector2(tex.get_size())
	var s: float = minf(size.x * 0.7 / ts.x, size.y * 0.7 / ts.y) * _zoom
	var draw_size := ts * s
	var base_pos := (size - draw_size) * 0.5
	_pan = p - base_pos - frac * draw_size
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT, KEY_PAGEUP:
			_index = wrapi(_index - 1, 0, _assets.size())
			_selected = -1
			queue_redraw()
		KEY_RIGHT, KEY_PAGEDOWN:
			_index = wrapi(_index + 1, 0, _assets.size())
			_selected = -1
			queue_redraw()
		KEY_C:
			_cycle_color()
		KEY_B:
			_cycle_blink()
		KEY_D:
			_cycle_power_domain()
		KEY_N:
			_toggle_no_led()
		KEY_R:
			_toggle_shape()
		KEY_T:
			_cycle_type()
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_0:
			_zoom = 1.0
			_pan = Vector2.ZERO
			queue_redraw()
		KEY_F8:
			_save()
		KEY_S:
			if event.ctrl_pressed:
				_save()


func _cycle_color() -> void:
	var leds := _cur_leds()
	if _selected < 0 or _selected >= leds.size():
		return
	var cur: Array = leds[_selected].get("color", PALETTE[0])
	var idx := 0
	for i in PALETTE.size():
		if PALETTE[i][0] == cur[0] and PALETTE[i][1] == cur[1] and PALETTE[i][2] == cur[2]:
			idx = i
	leds[_selected]["color"] = PALETTE[(idx + 1) % PALETTE.size()]
	queue_redraw()


func _cycle_type() -> void:
	var leds := _cur_leds()
	if _selected < 0 or _selected >= leds.size():
		return
	var cur := str(leds[_selected].get("type", "led"))
	var idx := TYPES.find(cur)
	leds[_selected]["type"] = TYPES[(idx + 1) % TYPES.size()]
	queue_redraw()


func _toggle_shape() -> void:
	var leds := _cur_leds()
	if _selected < 0 or _selected >= leds.size():
		return
	leds[_selected]["shape"] = "round" if str(leds[_selected].get("shape", "rect")) == "rect" else "rect"
	queue_redraw()


func _cycle_blink() -> void:
	var leds := _cur_leds()
	if _selected < 0 or _selected >= leds.size():
		return
	var cur := str(leds[_selected].get("blink", "steady"))
	var idx := BLINKS.find(cur)
	leds[_selected]["blink"] = BLINKS[(idx + 1) % BLINKS.size()]
	queue_redraw()


func _profile(key: String) -> Dictionary:
	if key == "":
		return {}
	if not _profiles.has(key):
		_profiles[key] = {}
	return _profiles[key]


func _cycle_power_domain() -> void:
	var key := _key()
	if key == "":
		return
	var profile := _profile(key)
	var idx := POWER_DOMAINS.find(str(profile.get("power_domain", "mains")))
	profile["power_domain"] = POWER_DOMAINS[(idx + 1) % POWER_DOMAINS.size()]
	queue_redraw()


func _toggle_no_led() -> void:
	var key := _key()
	if key == "":
		return
	var profile := _profile(key)
	if bool(profile.get("no_led", false)):
		profile.erase("no_led")
	else:
		profile["no_led"] = true
		_leds[key] = []
		_selected = -1
	queue_redraw()


func _delete_selected() -> void:
	var leds := _cur_leds()
	if _selected >= 0 and _selected < leds.size():
		leds.remove_at(_selected)
		_selected = -1
		queue_redraw()


# ------------------------------------------------------------- Zeichnen
func _draw() -> void:
	if _assets.is_empty():
		return
	_compute_sprite_rect()
	var font := ThemeDB.fallback_font
	# Hintergrund
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.10, 0.13))
	# Objekt-Sprite
	var tex: Texture2D = _assets[_index]["tex"]
	draw_texture_rect(tex, _sprite_rect, false)
	draw_rect(_sprite_rect, Color(0.3, 0.9, 1.0, 0.5), false, 1.0)

	# LEDs: eckiger Rahmen (das Loch) + rundes Licht darin
	var leds := _cur_leds()
	for i in leds.size():
		var led: Dictionary = leds[i]
		var r := _led_rect(led)
		var col: Array = led.get("color", [1, 1, 1])
		var c := Color(col[0], col[1], col[2])
		var on := 0.85 + 0.15 * sin(_time * 3.0)
		if str(led.get("blink", "")) in ["rx", "tx"]:
			on = 0.5 + 0.5 * sign(sin(_time * (7.0 if led["blink"] == "rx" else 11.0)))
		var p := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.5
		var mtype := str(led.get("type", "led"))
		match mtype:
			"led":
				if str(led.get("shape", "rect")) == "rect":
					draw_rect(r.grow(minf(r.size.x, r.size.y) * 0.35), Color(c.r, c.g, c.b, 0.14 * on))
					draw_rect(r, Color(c.r, c.g, c.b, 0.95 * on))
					draw_rect(Rect2(r.position + r.size * 0.18, r.size * 0.34), Color(1, 1, 1, 0.7 * on))
				else:
					draw_circle(p, rad * 1.6, Color(c.r, c.g, c.b, 0.16 * on))
					draw_circle(p, rad, Color(c.r, c.g, c.b, 0.95 * on))
					draw_circle(p - Vector2(rad * 0.3, rad * 0.3), rad * 0.4, Color(1, 1, 1, 0.85 * on))
			"light":
				var lr := maxf(r.size.x, r.size.y)
				draw_circle(p, lr * 1.6, Color(1.0, 0.82, 0.45, 0.10))
				draw_circle(p, lr * 0.9, Color(1.0, 0.86, 0.5, 0.18))
				draw_circle(p, rad * 0.9, Color(1.0, 0.95, 0.72, 0.9))
			"steam":
				for s in 3:
					var pts := PackedVector2Array()
					for kk in 6:
						var yy := float(kk) / 5.0
						pts.append(p + Vector2(sin(_time * 2.0 + s * 2.0 + yy * 4.0) * rad + float(s - 1) * rad,
							-yy * maxf(r.size.y, rad) * 3.0))
					draw_polyline(pts, Color(0.85, 0.9, 1.0, 0.5), 2.0)
			"key":
				draw_circle(p, maxf(1.5, rad * 0.5), Color(0.85, 0.85, 0.9, 0.55))
		# Rahmen (Farbe je Typ)
		var sel: bool = i == _selected
		var fc: Color = TYPE_COL.get(mtype, Color(0.3, 0.9, 1.0))
		draw_rect(r, Color(1.0, 0.95, 0.3, 0.95) if sel else Color(fc.r, fc.g, fc.b, 0.85),
			false, 2.0 if sel else 1.0)
		if sel:
			for corner: Vector2 in _rect_corners(r):
				draw_rect(Rect2(corner - Vector2(4, 4), Vector2(8, 8)), Color(1.0, 0.95, 0.3))
		var lbl := str(led.get("blink", "steady")) if mtype == "led" else mtype
		draw_string(font, Vector2(r.position.x, r.position.y - 4), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, fc.lightened(0.2))

	# Kopf-/Fußzeile
	var a: Dictionary = _assets[_index]
	var profile: Dictionary = _profiles.get(_key(), {})
	var profile_status := "Domäne: %s%s" % [str(profile.get("power_domain", "mains")),
		" · KEINE LED" if bool(profile.get("no_led", false)) else ""]
	draw_string(font, Vector2(16, 26),
		"LED/MARKER-EDITOR   %d/%d   %s   (%s)   —   %d Marker · %s" % [
			_index + 1, _assets.size(), a["id"], a["key"], leds.size(), profile_status],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.85, 0.4))
	draw_string(font, Vector2(16, size.y - 32),
		"←/→ Objekt · Rad = Zoom · Mitte = schieben · 0 = Ansicht · T Typ (led/light/steam/key)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))
	draw_string(font, Vector2(16, size.y - 14),
		"Klick = Marker · C Farbe · B Blink · D Stromdomäne · N ohne LED · R Form · Entf · F8 speichert",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 0.9))
