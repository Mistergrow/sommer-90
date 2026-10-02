@tool
class_name RoomCompositor
extends Control
## Setzt das Jugendzimmer aus Layern zusammen (Art-Bible-System):
## ROOM_BASE + Hardware-/Prop-/Overlay-Layer aus assets/backgrounds/layers/,
## gesteuert über data/room_anchors.json.
##
## - Full-Canvas-Layer (1920x1080) werden deckungsgleich gestapelt.
## - Freigestellte Ausschnitte werden am Anchor-Punkt platziert; width/height
##   in Master-Pixeln, Tiefenskalierung folgt dem Tischplatten-Viereck.
## - Bedingungen: always / requires_hardware / requires_object / disabled.
## - Fehlende Dateien werden übersprungen → Assets können einzeln
##   nachgeliefert werden; Hardwarekäufe blenden Layer live ein.
##
## Die Deko-Werkstatt (Eingaben, Hilfslinien, Speichern) lebt getrennt in
## scripts/gfx/deko_editor.gd und wird als Overlay-Kind (z 60) erzeugt.

# Asset-/Material-Auflösung liegt in RoomAssets (statisch); hier bleiben nur die
# beiden Pfade, die der Compositor selbst braucht (comp.CONFIG_PATH extern, der
# Shader für Skew/Szenenlicht). Der Rest wird über dünne Wrapper delegiert.
const CONFIG_PATH := "res://data/room_anchors.json"
const MATERIAL_SHADER := "res://shaders/material_variants.gdshader"
const DEKO_EDITOR := preload("res://scripts/gfx/deko_editor.gd")
const WEATHER_OVERLAY := preload("res://scripts/gfx/weather_overlay.gd")
const DAYNIGHT_OVERLAY := preload("res://scripts/gfx/daynight_overlay.gd")
const MONITOR_GLOW_OVERLAY := preload("res://scripts/gfx/monitor_glow_overlay.gd")
const DUST_RAYS_OVERLAY := preload("res://scripts/gfx/dust_rays_overlay.gd")
const ROOM_AGE_OVERLAY := preload("res://scripts/gfx/room_age_overlay.gd")
const IDLE_LIFE_OVERLAY := preload("res://scripts/gfx/idle_life_overlay.gd")
const SOCKET_OVERLAY := preload("res://scripts/gfx/socket_overlay.gd")
const MagComposer := preload("res://scripts/gfx/magazine_composer.gd")
const LAYER_POLICY := preload("res://scripts/gfx/room_layer_policy.gd")
const ROOM_DEPTH := preload("res://scripts/gfx/room_depth_map.gd")
const SURFACE_FX_OVERLAY := preload("res://scripts/gfx/surface_fx_overlay.gd")
const EditorGeometry := preload("res://scripts/gfx/room_editor_geometry.gd")
const EditorBridge := preload("res://scripts/gfx/room_editor_bridge.gd")
const RoomProjectionUtil := preload("res://scripts/gfx/room_projection.gd")
const RoomLayoutEngine := preload("res://scripts/gfx/room_layout_engine.gd")
const PreviewModels := preload("res://scripts/gfx/room_preview_models.gd")
const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")

## Editor-Vorschau (scenes/previews/RoomPreview.tscn): Anker-Kreuze einblenden.
@export var show_anchors := false:
	set(value):
		show_anchors = value
		queue_redraw()
## Raum-Werkstatt: alle tatsaechlich renderbaren Geraete zeigen, auch wenn der
## aktuelle Spielstand sie noch nicht besitzt. Die Modellwahl bleibt dabei rein
## lokal in diesem Compositor und veraendert weder PlayerStats noch einen Save.
@export var preview_all_devices := false:
	set(value):
		preview_all_devices = value
		if not value:
			_preview_device_models.clear()
		if is_inside_tree():
			rebuild()
## Startvarianten fuer eine konkrete Werkstattszene. Das gemeinsame Raum-JSON
## behaelt weiterhin die echten Spieldefaults; RoomEditor kann z. B. direkt den
## A600 zeigen, ohne Besitz oder Save des Spielers anzufassen.
@export var preview_device_defaults: Dictionary = {}:
	set(value):
		preview_device_defaults = value.duplicate(true)
		_preview_device_models.clear()
		if is_inside_tree() and preview_all_devices:
			rebuild()
## Im Editor anhaken, um JSON-Änderungen neu einzulesen (springt zurück).
@export var refresh := false:
	set(_value):
		RoomAssets._config = {}
		if is_inside_tree():
			rebuild()
		queue_redraw()

## Deko-Modus (F8 im Spiel, F6-Vorschau): Zustand hält der Compositor,
## die Bearbeitung übernimmt der DekoEditor.
## Abweichendes Schreibziel fuer isolierte Editor-Tests.
var editor_config_path := CONFIG_PATH
var edit_mode := false

## Kabel-Editor: nur Basis + Objektlagen zeigen (keine Overlays/Deko/Physik-Kabel).
var suppress_overlays := false
var _editor: Control = null    # DekoEditor-Overlay (z 60)
var _weather: Control = null   # WeatherOverlay (z 20, über den Layern)
var _daynight: Control = null  # DayNightOverlay (z 23, Tageszeit-Grading)
var _monitor_glow: Control = null  # MonitorGlowOverlay (z 24, Bildschirm-Leuchten)
var _dust_rays: Control = null     # DustRaysOverlay (z 22, Sonnenstrahlen + Staub)
var _room_age: Control = null      # RoomAgeOverlay (z 5, Dekadenpatina unter Hardware)
var _idle_life: Control = null     # IdleLifeOverlay (z 19, LEDs + Kaffeedampf)
var _sockets_ov: Control = null    # SocketOverlay (z 2, Steckdosen/Verteiler)
var _surface_fx: Control = null     # Objekteditor-Licht/Schatten (z 3, hinter Tisch)

# Bewegte Raumtiefe: zusammenhaengende Flaechen bewegen sich als starre Ebenen.
# Insbesondere teilen Tischmaster, Tischobjekte und deren Kontaktschatten exakt
# dieselbe Projektion. Ein eigener Y-Faktor pro Prop erzeugt sonst den sichtbaren
# "Clipart-Schiebeeffekt", weil die Objekte von der Tischplatte wegrutschen.
var _depth_look := Vector2.ZERO
var _depth_target := Vector2.ZERO
var _depth_test_lock := false
var _depth_was_active := false
## Die Kamera folgt der Maus weich, darf aber selbst bei einem abrupten Sprung
## von Bildschirmrand zu Bildschirmrand nur eine begrenzte sichtbare Strecke
## pro Sekunde zurücklegen. Nur exponentielles lerp reicht nicht: dessen erster
## Schritt wird bei einer großen Zieländerung sichtbar groß.
const DEPTH_RESPONSE := 2.65
const DEPTH_MAX_FRAME_DELTA := 1.0 / 30.0
const DEPTH_MAX_SCREEN_SPEED := 26.0  # Pixel/Sekunde auf der staerksten Raumebene
## selector -> model_id, ausschliesslich fuer RoomPreview/Deko-Werkstatt.
## Absichtlich nicht serialisiert und nie an RoomManager/PlayerStats gereicht.
var _preview_device_models: Dictionary = {}

# ---------------------------- statische API (dünne Wrapper → RoomAssets)
# Bewahrt die bisherige Schnittstelle (RoomCompositor.find_asset, comp.config() …)
# unverändert; die Logik liegt in scripts/gfx/room_assets.gd.

static func config() -> Dictionary: return RoomAssets.config()
static func find_asset(asset_base: String) -> String: return RoomAssets.find_asset(asset_base)
static func asset_exists(path: String) -> bool: return RoomAssets.asset_exists(path)
static func load_texture(path: String) -> Texture2D: return RoomAssets.load_texture(path)
static func find_base(year: int) -> String: return RoomAssets.find_base(year)
static func base_available(year: int) -> bool: return RoomAssets.base_available(year)

## Master-Raum-Rechteck (1920×1080-Koordinaten, VOR der Tiefen-Projektion) eines
## verankerten Prop-Layers — der Bereich, den das Prop tatsächlich einnimmt.
## Hotspots laufen durch dieselbe Projektion (offset_for_point), daher kann ein
## Klickfeld über dieses Rect gelegt werden, das dem Prop folgt — auch wenn es im
## Deko-Editor verschoben wird. Leeres Rect2, wenn der Anker unbekannt ist.
static func layer_master_rect(layer_id: String, pad := 0.0) -> Rect2:
	var anchors: Dictionary = config().get("anchors", {})
	for source: Dictionary in config().get("layers", []):
		if str(source.get("id", "")) != layer_id:
			continue
		var selector := str(source.get("model_selector", ""))
		var selected := str(source.get("default_model", ""))
		if selector == "monitor_model":
			selected = MonitorProfile.active_model_id()
		elif not selector.is_empty() and Engine.get_main_loop() is SceneTree:
			var tree := Engine.get_main_loop() as SceneTree
			var room_manager := tree.root.get_node_or_null("/root/RoomManager")
			if room_manager != null and room_manager.has_method("active_device_model"):
				var runtime_selected := str(room_manager.call("active_device_model", selector))
				if not runtime_selected.is_empty():
					selected = runtime_selected
		var layer := PreviewModels.resolve(source, selected)
		var anchor_name := str(layer.get("anchor", ""))
		if not anchors.has(anchor_name):
			return Rect2()
		var a: Array = anchors[anchor_name]
		var pos := Vector2(float(a[0]), float(a[1]))
		var off: Array = layer.get("anchor_offset", [0.0, 0.0])
		if off.size() >= 2:
			pos += Vector2(float(off[0]), float(off[1]))
		var w := float(layer.get("width", 0.0))
		var h := float(layer.get("height", 0.0))
		if w <= 0.0 or h <= 0.0:
			var tex: Texture2D = null
			for stem: String in layer.get("assets", [layer.get("asset", "")]):
				var p := find_asset(str(stem))
				if p != "":
					tex = load_texture(p)
					break
			if tex != null:
				var ts := tex.get_size()
				if w <= 0.0 and h <= 0.0:
					w = ts.x
					h = ts.y
				elif h <= 0.0:
					h = w * ts.y / ts.x
				elif w <= 0.0:
					w = h * ts.x / ts.y
		if w <= 0.0 or h <= 0.0:
			return Rect2()
		var pivot := str(layer.get("pivot", "center")).to_lower().replace("_", "")
		var top_left: Vector2
		match pivot:
			"bottomcenter":
				top_left = Vector2(pos.x - w * 0.5, pos.y - h)
			"bottomleft":
				top_left = Vector2(pos.x, pos.y - h)
			_:
				top_left = Vector2(pos.x - w * 0.5, pos.y - h * 0.5)
		return Rect2(top_left - Vector2(pad, pad), Vector2(w + pad * 2.0, h + pad * 2.0))
	return Rect2()


## Modellgenaue Bedienflaeche relativ zum tatsaechlich gerenderten CRT-Layer.
## Die Deko-Position, Modellbreite und das Seitenverhaeltnis werden zuerst vom
## Compositor aufgeloest; danach wird die asset-relative Kalibrierung angewandt.
static func monitor_control_master_rect(region_id: String, pad := 0.0) -> Rect2:
	var model_rect := layer_master_rect("monitor")
	if model_rect.size.x <= 0.0 or model_rect.size.y <= 0.0:
		return Rect2()
	var result := MonitorProfile.region_rect(
		MonitorProfile.active_model_id(), region_id, model_rect)
	if result.size.x <= 0.0 or result.size.y <= 0.0:
		return Rect2()
	return result.grow(pad)

# ------------------------------------------------------------- Aufbau

func _ready() -> void:
	# Keine Anker: Größe wird explizit vom Parent gespiegelt (deferred, damit
	# der Parent seine eigene Größe schon hat; plus resized-Abo für später).
	# Anker + manuelles size-Setzen zusammen erzeugen Layout-Warnungen.
	_sync_size.call_deferred()
	var parent_control := get_parent_control()
	if parent_control != null:
		parent_control.resized.connect(_sync_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if Engine.is_editor_hint():
		# Editor: Node gegen versehentliches Verschieben sperren — Objekte
		# bewegt das Deko-Werkstatt-Plugin (addons/deko_werkstatt).
		set_meta("_edit_lock_", true)
	if not Engine.is_editor_hint():
		# Hardwarekäufe/Zimmerausbau blenden Layer live ein
		PlayerStats.stats_changed.connect(_rebuild_if_changed)
		RoomManager.room_changed.connect(_rebuild_if_changed)
		if not TimeManager.year_changed.is_connected(_on_year_changed):
			TimeManager.year_changed.connect(_on_year_changed)
	resized.connect(_layout_all)
	rebuild()


func _on_year_changed(_year: int) -> void:
	# Raumalterung und jahresspezifische Basisvarianten werden sofort sichtbar;
	# der Spieler muss den Ort nicht erst verlassen und erneut betreten.
	rebuild()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var active := _depth_enabled()
	if not active:
		_depth_target = Vector2.ZERO
	elif not _depth_test_lock:
		_depth_target = _pointer_depth_target()
		var ms := Time.get_ticks_msec()
		_depth_target += Vector2(sin(ms * 0.00011 + 1.7), cos(ms * 0.00009 + 0.4)) \
			* ROOM_DEPTH.IDLE_GAIN
	# Jede noch so kleine Bewegung muss in den Zustand eingehen. Die fruehere
	# 0,045-px-Schwelle verwarf Subpixel-Schritte in jedem Frame erneut: erst
	# bei einer groesseren Mausbewegung sprang die ganze Desk-Gruppe sichtbar.
	# Ein Delta-Cap verhindert ausserdem einen Kamerasprung nach einem Frame-Hitch.
	var motion_delta := minf(maxf(delta, 0.0), DEPTH_MAX_FRAME_DELTA)
	var desired := _depth_look.lerp(_depth_target,
		1.0 - exp(-motion_delta * DEPTH_RESPONSE))
	# In Blickraum umgerechnetes Tempolimit. `size.length()` entspricht derselben
	# Projektion wie depth_offset_for_screen_point(); dadurch bleibt das sichtbare
	# Tempo bei verschiedenen Auflösungen und Seitenverhältnissen stabil.
	var strongest_pixels_per_look := ROOM_DEPTH.STRENGTH * size.length() * ROOM_DEPTH.NEAR_GAIN
	var max_look_step := DEPTH_MAX_SCREEN_SPEED * motion_delta \
		/ maxf(strongest_pixels_per_look, 0.001)
	var next := _depth_look.move_toward(desired, max_look_step)
	if next.length() < 0.0001:
		next = Vector2.ZERO
	var changed := not next.is_equal_approx(_depth_look)
	_depth_look = next
	var active_changed := active != _depth_was_active
	_depth_was_active = active
	if (active and changed) or active_changed:
		_apply_depth_projection()

func _depth_enabled() -> bool:
	return not Engine.is_editor_hint() and not edit_mode and not suppress_overlays \
		and bool(SettingsManager.value("location_depth"))

func _pointer_depth_target() -> Vector2:
	if size.x <= 1.0 or size.y <= 1.0:
		return Vector2.ZERO
	var p := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(p):
		return Vector2.ZERO
	var n := (p / size - Vector2(0.5, 0.5)) * 2.0
	return Vector2(clampf(n.x, -1.0, 1.0), clampf(n.y, -1.0, 1.0) * 0.72) \
		* ROOM_DEPTH.POINTER_GAIN

## Wetter zeichnet das WeatherOverlay selbst (eigener _process); hier nichts nötig.

## Größe dem Parent nachführen (liest zur Ausführungszeit, nie stale).
func _sync_size() -> void:
	var parent_control := get_parent_control()
	if parent_control != null:
		position = Vector2.ZERO
		size = parent_control.size

## Spieljahr; im Editor (keine Autoloads) fest 1992er-Vorschau.
func _current_year() -> int:
	if Engine.is_editor_hint():
		return 1992
	return TimeManager.year

## Alle Layer neu aufbauen (Kauf, Laden, Jahreswechsel beim Betreten).
func rebuild() -> void:
	var perf_trace := OS.get_environment("DSS_PERF_TRACE") == "1"
	var rebuild_started := Time.get_ticks_usec()
	var perf_tick := rebuild_started
	# Alte Layer sofort aushängen (queue_free allein ließe sie bis zum
	# Frame-Ende doppelt im Baum — sichtbares Stapeln beim Live-Rebuild).
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if preview_all_devices:
		_validate_preview_models()
	var base_path := find_base(_current_year())
	if base_path != "":
		var base_started := Time.get_ticks_usec()
		_add_layer(base_path, {"z": 0})
		if perf_trace:
			print("ROOM_LAYER %.3f ms · BASIS · %s" % [
				float(Time.get_ticks_usec() - base_started) / 1000.0, base_path])
	for layer in config().get("layers", []):
		var layer_started := Time.get_ticks_usec()
		if not _layer_active(layer):
			continue
		var visual_layer := _resolve_visual_layer(layer)
		# Mehrere Namensstämme erlaubt (Asset-Registry-IDs + Alt-Namen)
		var path := ""
		for stem in visual_layer.get("assets", [visual_layer.get("asset", "")]):
			path = find_asset(stem)
			if path != "":
				break
		if path == "":
			continue  # Asset noch nicht produziert — still überspringen
		_add_layer(path, visual_layer)
		# Dynamischer Kontaktschatten: wandert/skaliert mit dem Objekt
		if bool(visual_layer.get("depth_scale", false)) and visual_layer.has("width") \
				and bool(visual_layer.get("contact_shadow", true)):
			_add_contact_shadow(visual_layer)
		var layer_ms := float(Time.get_ticks_usec() - layer_started) / 1000.0
		if perf_trace and layer_ms >= 1.0:
			print("ROOM_LAYER %.3f ms · %s · %s" % [layer_ms,
				str(visual_layer.get("id", "?")), path])
	perf_tick = _trace_rebuild_phase(perf_trace, "Raumlagen", perf_tick)
	# Kabel-Editor blendet Physik-Kabel, Atmosphäre-Overlays und Deko-Gizmos aus
	# (sauberer Hintergrund; er zeichnet seine eigenen Kabel-Griffe darüber).
	if not suppress_overlays:
		_build_cables()
		perf_tick = _trace_rebuild_phase(perf_trace, "Kabel", perf_tick)
		# Steckdosen/Verteiler (z 2, hinter den Möbeln/Geräten).
		_sockets_ov = SOCKET_OVERLAY.new()
		_sockets_ov.comp = self
		_sockets_ov.z_index = 2
		add_child(_sockets_ov)
		perf_tick = _trace_rebuild_phase(perf_trace, "Steckdosen", perf_tick)
		_surface_fx = SURFACE_FX_OVERLAY.new()
		_surface_fx.name = "SurfaceFxOverlay"
		_surface_fx.z_index = 3
		_surface_fx.call("configure", self, self, "ROOM_MASTER")
		add_child(_surface_fx)
		perf_tick = _trace_rebuild_phase(perf_trace, "Oberflächen-FX", perf_tick)
		_room_age = ROOM_AGE_OVERLAY.new()
		_room_age.name = "RoomAgeOverlay"
		_room_age.comp = self
		_room_age.z_index = 5
		add_child(_room_age)
		perf_tick = _trace_rebuild_phase(perf_trace, "Raumalterung", perf_tick)
		_weather = WEATHER_OVERLAY.new()
		_weather.comp = self
		_weather.z_index = 20  # über den Raum-Layern (0–8), unter dem DekoEditor (60)
		add_child(_weather)
		perf_tick = _trace_rebuild_phase(perf_trace, "Wetter", perf_tick)

		# Idle-Leben (Geräte-LEDs, Kaffeedampf) — über den Objekten.
		if not Engine.is_editor_hint():
			_idle_life = IDLE_LIFE_OVERLAY.new()
			_idle_life.comp = self
			_idle_life.z_index = 19
			add_child(_idle_life)
			perf_tick = _trace_rebuild_phase(perf_trace, "Idle-Leben", perf_tick)

		# Sonnenstrahlen + Staub (additiv) — über Layern/Wetter, unter dem Grading.
		if not Engine.is_editor_hint():
			_dust_rays = DUST_RAYS_OVERLAY.new()
			_dust_rays.comp = self
			_dust_rays.z_index = 22
			add_child(_dust_rays)
			perf_tick = _trace_rebuild_phase(perf_trace, "Staubstrahlen", perf_tick)

		# Tageszeit-Grading (multipliziert die ganze Szene) — über Layern & Wetter.
		_daynight = DAYNIGHT_OVERLAY.new()
		_daynight.comp = self
		_daynight.z_index = 23
		add_child(_daynight)
		perf_tick = _trace_rebuild_phase(perf_trace, "Tag/Nacht", perf_tick)

		# Monitor-Leuchten (Standbild + Lichtwurf) — ÜBER dem Grading, damit die
		# Röhre selbst leuchtet. Nur zur Laufzeit (kein Standbild im Editor).
		if not Engine.is_editor_hint():
			_monitor_glow = MONITOR_GLOW_OVERLAY.new()
			_monitor_glow.comp = self
			_monitor_glow.z_index = 24
			add_child(_monitor_glow)
			perf_tick = _trace_rebuild_phase(perf_trace, "Monitorlicht", perf_tick)
		_editor = DEKO_EDITOR.new()
		_editor.comp = self
		_editor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_editor)
		perf_tick = _trace_rebuild_phase(perf_trace, "Editorbrücke", perf_tick)
	_layout_all()
	_trace_rebuild_phase(perf_trace, "Layout", perf_tick)
	if perf_trace:
		print("ROOM_REBUILD total %.3f ms · %d Nodes" % [
			float(Time.get_ticks_usec() - rebuild_started) / 1000.0, get_child_count()])
	if OS.get_environment("DSS_DEBUG") == "1":
		print("[Compositor] rebuild: size=", size, " base=", base_path,
			" kinder=", get_child_count())


func _trace_rebuild_phase(enabled: bool, label: String, previous_usec: int) -> int:
	var now := Time.get_ticks_usec()
	if enabled:
		print("ROOM_PHASE %s %.3f ms" % [label, float(now - previous_usec) / 1000.0])
	return now

func _rebuild_if_changed() -> void:
	if LAYER_POLICY.changed_since_build(self): rebuild()

func _layer_active(layer: Dictionary) -> bool:
	return LAYER_POLICY.active(self, layer)

## Rechner/Monitor bleiben echte Einzellayer, ihre konkrete Grafik kommt aber
## aus dem save-festen, durch RoomManager validierten Modellslot. Neue Modelle
## benoetigen damit nur Daten + Asset, keinen neuen Compositor-Zweig.
func _resolve_visual_layer(source: Dictionary) -> Dictionary:
	return LAYER_POLICY.resolve_visual(self, source)

## Nur renderbare, nicht deaktivierte Varianten in kuratierter JSON-Reihenfolge.
func preview_device_models(selector: String) -> Array: return LAYER_POLICY.available_models(self, selector)
func preview_active_model(selector: String) -> String: return LAYER_POLICY.active_preview_model(self, selector)
func _validate_preview_models() -> void: LAYER_POLICY.validate_preview_models(self)
## Lokaler Werkstatt-Wechsel. Gibt den neu gebauten Layer zurueck, damit M auch
## mehrfach hintereinander funktioniert, obwohl rebuild() den DekoEditor ersetzt.
func preview_cycle_device_model(selector: String, direction := 1, layer_id := "") -> Control:
	return LAYER_POLICY.cycle_preview_model(self, selector, direction, layer_id)
## Direkte Werkstattwahl fuer sichtbare Toolbar-Schalter. Wie der M-Pfad bleibt
## sie lokal und schreibt weder PlayerStats noch einen Spielstand.
func preview_select_device_model(selector: String, model_id: String,
		layer_id := "") -> Control:
	return LAYER_POLICY.select_preview_model(self, selector, model_id, layer_id)

func _add_layer(path: String, layer: Dictionary) -> void:
	var rect := TextureRect.new()
	var load_started := Time.get_ticks_usec()
	rect.texture = load_texture(path)
	var load_ms := float(Time.get_ticks_usec() - load_started) / 1000.0
	if OS.get_environment("DSS_PERF_TRACE") == "1" and load_ms >= 1.0:
		print("ROOM_TEXTURE %.3f ms · %s" % [load_ms, path])
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Ohne IGNORE_SIZE erzwingt TextureRect die Texturgröße als Minimum —
	# herunterskalierte Layer (Master → Ansicht) wären sonst zu groß.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fotografische Layer weich filtern (Projekt-Default ist Nearest für die
	# Pixel-UI) — Linear OHNE Mipmaps: Mip-Wechsel verschieben beim
	# Skalieren sonst sichtbar Farbe/Kontrast.
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# CLAMP statt Wiederholung: sonst „wrappt" der Schräg-Versatz (skew) die
	# rechte Kante als vertikalen Geister-Streifen (Material-Shader sampelt UV).
	rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	rect.z_index = int(layer.get("z", 1))
	rect.set_meta("anchor", layer.get("anchor", ""))
	# Pivot: "center" (Standard) oder "bottom_center" (steht auf dem Anker);
	# Schreibweisen wie "BottomCenter" werden normalisiert.
	rect.set_meta("pivot", str(layer.get("pivot", "center")).to_lower().replace("_", ""))
	rect.set_meta("width", float(layer.get("width", 0.0)))
	rect.set_meta("height", float(layer.get("height", 0.0)))
	rect.set_meta("full_canvas", bool(layer.get("full_canvas", false)))
	rect.set_meta("depth_scale", bool(layer.get("depth_scale", false)))
	rect.set_meta("rotation", float(layer.get("rotation", 0.0)))
	rect.set_meta("skew", float(layer.get("skew", 0.0)))
	rect.set_meta("layer_id", str(layer.get("id", "")))
	rect.set_meta("active_model", str(layer.get("active_model", "")))
	rect.set_meta("model_selector", str(layer.get("model_selector", "")))
	var anchor_offset: Array = layer.get("anchor_offset", [0.0, 0.0])
	rect.set_meta("anchor_offset", Vector2(float(anchor_offset[0]), float(anchor_offset[1])) \
		if anchor_offset.size() >= 2 else Vector2.ZERO)
	rect.set_meta("zone", str(layer.get("zone", "")))
	rect.set_meta("room_depth_group", str(layer.get("depth_group",
		"desk" if str(layer.get("zone", "")) == "tisch" else "")))
	rect.set_meta("asset", path.get_file().get_basename())  # Modell-Zuordnung (Monitor …)
	var layer_z := int(layer.get("z", 1))
	var depth_anchor := str(layer.get("anchor", ""))
	# Verankerte Requisiten sind Weltobjekte. Von Full-Canvas-Lagen bewegt sich
	# nur Basis/Fensterwelt; Grading/Glow/Wetter bleiben bildschirmfest.
	rect.set_meta("room_depth_world", depth_anchor != "" or layer_z <= 2)
	rect.set_meta("room_depth_base", layer_z == 0 and depth_anchor == "")
	# Prozedurale Material-Variante (Farbe/Alterung im Shader statt
	# Textur-Duplikat, s. docs/MATERIAL_SYSTEM.md)
	if layer.has("material"):
		rect.material = _make_material(layer["material"], path)
	if bool(rect.get_meta("room_depth_base", false)):
		ROOM_DEPTH.attach(rect, "base")
	elif str(layer.get("id", "")) == "desk_surface":
		ROOM_DEPTH.attach(rect, "desk")
	# Szenen-Licht für physische Tisch-Objekte (nicht Overlays/FX): fängt das
	# Fensterlicht ein — Volumen-Schattierung + warmes Kantenlicht (gegen den
	# „platten" Ausschnitt-Look). depth_scale markiert reale Objekte.
	if bool(layer.get("depth_scale", false)) and bool(layer.get("scene_light", true)):
		_enable_scene_light(rect, float(layer.get("light_gain", 1.0)))
	# Blend-Modus je Layer ("blend": add|mul|sub|mix) — schaltet Effekt-Lagen frei:
	# add = Glühen/Lichtwurf/Reflexe · mul = Schatten/Schmutz/Gobo · sub = Abzug.
	# Nur für reine Effekt-Layer (kein Skew/Szenenlicht-Shader).
	if layer.has("blend") and rect.material == null:
		var cm := CanvasItemMaterial.new()
		cm.blend_mode = _blend_mode(str(layer["blend"]))
		rect.material = cm
	if layer.has("modulate"):
		var m: Array = layer["modulate"]
		if m.size() >= 3:
			rect.modulate = Color(float(m[0]), float(m[1]), float(m[2]),
				float(m[3]) if m.size() > 3 else 1.0)
	add_child(rect)
	# Auf dem Schreibtisch liegt eine echte Amiga-Joker-Ausgabe: das Cover des
	# aktuellen Monats ins Master-Heft einbacken (Ecken aus dem Magazin-Editor).
	if str(layer.get("id", "")) == "magazines":
		var month := 7 if Engine.is_editor_hint() else int(TimeManager.month)
		var cover_path: String = MagComposer.cover_for_month(month)
		MagComposer.compose(self, cover_path, func(tex: Texture2D) -> void:
			if is_instance_valid(rect):
				rect.texture = tex
				# Mipmap-Filter gegen Alias-„Doppelschrift" beim Verkleinern.
				rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)

## Blend-Modus-Name → CanvasItemMaterial-Konstante (Godot-Canvas kennt kein
## „screen"/„overlay" — das bräuchte einen Shader; add/mul/sub/mix decken die
## meisten Zimmer-Effekte ab).
func _blend_mode(blend_name: String) -> CanvasItemMaterial.BlendMode:
	match blend_name.to_lower():
		"add", "additive": return CanvasItemMaterial.BLEND_MODE_ADD
		"mul", "multiply": return CanvasItemMaterial.BLEND_MODE_MUL
		"sub", "subtract": return CanvasItemMaterial.BLEND_MODE_SUB
		_: return CanvasItemMaterial.BLEND_MODE_MIX

## Szenen-Licht auf einem Layer aktivieren. Nutzt denselben Material-Shader
## (ggf. schon für Skew/Material vorhanden) und schaltet nur die Licht-
## Integration ein — so bleibt es bei EINEM Material pro Node.
func _enable_scene_light(rect: TextureRect, gain: float) -> void:
	var mat := rect.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = load(MATERIAL_SHADER)
		mat.set_shader_parameter("recolor_strength", 0.0)  # Sampler-Default ist weiß!
		rect.material = mat
	mat.set_shader_parameter("scene_light", clampf(gain, 0.0, 1.0))

## Weiche Schatten-Ellipse — liegt in RoomAssets (Wrapper).
static func _shadow_texture() -> ImageTexture:
	return RoomAssets.shadow_texture()

## Kontaktschatten-Layer unter einem Tischobjekt (teilt dessen Anker —
## folgt damit automatisch jedem Verschieben im Deko-Modus).
func _add_contact_shadow(layer: Dictionary) -> void:
	var rect := TextureRect.new()
	rect.texture = _shadow_texture()
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 8
	var factor := float(layer.get("shadow_scale", 1.0))
	var w := float(layer.get("width", 100.0))
	rect.set_meta("anchor", layer.get("anchor", ""))
	var anchor_offset: Array = layer.get("anchor_offset", [0.0, 0.0])
	rect.set_meta("anchor_offset", Vector2(float(anchor_offset[0]), float(anchor_offset[1])) \
		if anchor_offset.size() >= 2 else Vector2.ZERO)
	rect.set_meta("pivot", "center")
	rect.set_meta("width", w * 1.28 * factor)
	rect.set_meta("height", w * 0.22 * factor)
	rect.set_meta("depth_scale", true)
	# Gerichteter Wurf: das Fensterlicht kommt von rechts oben, der Schatten
	# fällt also nach links (und minimal nach vorn) — das liest sich als 3D.
	rect.set_meta("shadow_bias", Vector2(-w * 0.13, w * 0.03) * factor)
	rect.set_meta("layer_id", str(layer.get("id", "")) + "_schatten")
	rect.set_meta("is_shadow", true)
	rect.set_meta("zone", str(layer.get("zone", "")))
	rect.set_meta("room_depth_group", str(layer.get("depth_group",
		"desk" if str(layer.get("zone", "")) == "tisch" else "")))
	rect.set_meta("room_depth_world", true)
	rect.set_meta("room_depth_base", false)
	add_child(rect)

## ShaderMaterial aus Preset — liegt in RoomAssets (Wrapper).
static func _make_material(cfg: Dictionary, texture_path: String) -> ShaderMaterial:
	return RoomAssets.make_material(cfg, texture_path)

# ------------------------------------------------------------- Kabel

## Dynamische Kabel (CableRenderer) zwischen Anker-Paaren erzeugen.
func _build_cables() -> void:
	if Engine.is_editor_hint():
		return  # Kabelphysik nur zur Laufzeit (Vorschau zeigt Layer + Anker)
	var anchors: Dictionary = config().get("anchors", {})
	for cable_cfg in config().get("cables", []):
		if not _layer_active(cable_cfg):
			continue
		# Nur verkabeln, wenn das zugehörige Gerät als Asset existiert
		var device: String = cable_cfg.get("requires_asset", "")
		if device != "" and find_asset(device) == "":
			continue
		# Endpunkte: Anker-Name ODER objektrelativ {"object": layer_id,
		# "offset": [dx, dy]} — Ports gehören zum Gerät und wandern mit.
		var start_spec: Variant = cable_cfg.get("start", cable_cfg.get("start_anchor", ""))
		var end_spec: Variant = cable_cfg.get("end", cable_cfg.get("end_anchor", ""))
		var start_point := _cable_point(start_spec, anchors)
		var end_point := _cable_point(end_spec, anchors)
		if start_point == Vector2.INF or end_point == Vector2.INF:
			continue
		var cable := CableRenderer.new()
		cable.cable_id = str(cable_cfg.get("id", ""))
		cable.set_meta("start_spec", start_spec)
		cable.set_meta("end_spec", end_spec)
		cable.start_master = start_point
		cable.end_master = end_point
		cable.segments = int(cable_cfg.get("segments", 24))
		cable.slack = float(cable_cfg.get("slack", 1.3))
		cable.thickness = float(cable_cfg.get("thickness", 4.0))
		cable.style = str(cable_cfg.get("style", "smooth"))
		cable.coils = int(cable_cfg.get("coils", 18))
		cable.floor_contact = bool(cable_cfg.get("floor_contact", false))
		cable.floor_y = float(cable_cfg.get("floor_y", 965.0))
		cable.floor_roughness = float(cable_cfg.get("floor_roughness", 4.0))
		cable.floor_surface = str(cable_cfg.get("floor_surface", "carpet"))
		var rgb: Array = cable_cfg.get("color", [0.75, 0.74, 0.71])
		cable.color = Color(rgb[0], rgb[1], rgb[2])
		cable.z_index = int(cable_cfg.get("z", 7))
		add_child(cable)

## Kabel-Endpunkt auflösen: Anker-Name oder {"object", "offset", "at_y"}.
func _cable_point(spec: Variant, anchors: Dictionary) -> Vector2:
	if spec is String and anchors.has(spec):
		var a: Array = anchors[spec]
		return Vector2(a[0], a[1])
	if spec is Dictionary and spec.has("socket"):
		# Endpunkt an einer Steckdose/Verteiler (Kabel-Editor)
		for s: Dictionary in config().get("sockets", []):
			if str(s.get("id", "")) == str(spec["socket"]):
				var sp: Array = s.get("pos", [0, 0])
				var so: Array = spec.get("offset", [0, 0])
				return Vector2(float(sp[0]) + float(so[0]), float(sp[1]) + float(so[1]))
		return Vector2.INF
	if spec is Dictionary:
		var object_id := str(spec.get("object", ""))
		var layer := _layer_by_id(object_id)
		var anchor_name: String = layer.get("anchor", "")
		if anchors.has(anchor_name):
			var a: Array = anchors[anchor_name]
			var off: Array = spec.get("offset", [0, 0])
			var model_offset := _live_anchor_offset(object_id)
			var p := Vector2(float(a[0]) + float(off[0]), float(a[1]) + float(off[1])) \
				+ model_offset
			if spec.has("at_y"):
				p.y = float(spec["at_y"])  # z. B. hinter die Tisch-Hinterkante
			return p
	return Vector2.INF

func _layer_by_id(layer_id: String) -> Dictionary:
	for layer in config().get("layers", []):
		if str(layer.get("id", "")) == layer_id:
			return layer
	return {}

## Modellversatz des aktuell gerenderten Layers. Kabelports bleiben dadurch am
## Gehaeuse, wenn eine Drucker-/Stereo-Variante separat feinpositioniert wird.
func _live_anchor_offset(layer_id: String) -> Vector2:
	for child in get_children():
		if child is TextureRect and str(child.get_meta("layer_id", "")) == layer_id \
				and not bool(child.get_meta("is_shadow", false)):
			return child.get_meta("anchor_offset", Vector2.ZERO)
	return Vector2.ZERO

## Kabel-Pins an die aktuellen Anker/Objekte anpassen (läuft bei jedem
## Layout — Kabel folgen so live, wenn Geräte im Deko-Modus wandern).
func _update_cable_pins() -> void:
	var anchors: Dictionary = config().get("anchors", {})
	for child in get_children():
		if child.has_method("poke"):
			var s := _cable_point(child.get_meta("start_spec", ""), anchors)
			var e := _cable_point(child.get_meta("end_spec", ""), anchors)
			if s != Vector2.INF:
				child.start_master = s
			if e != Vector2.INF:
				child.end_master = e

# ------------------------------------------------------------- Layout

## Master-Bild (1920x1080) formatfüllend einpassen. Im Spiel schützt der
## datengetriebene Cover-Anker den oberen Wandbereich; im Deko-Modus bleibt die
## Projektion zentriert. Alle Layer, Kabel und Hotspots teilen exakt dieselbe
## Transformation.
func _master_transform() -> Dictionary:
	return RoomProjectionUtil.master_transform(self)

## Einheitliche Raumprojektion fuer RGBA-Layer, Hotspots, Kabel und Overlays.
## `screen_point` ist die kanonische (nicht bereits verschobene) Position.
func depth_offset_for_screen_point(screen_point: Vector2, gain_override: float = -1.0) -> Vector2:
	return RoomProjectionUtil.depth_offset(self, screen_point, gain_override)

## LocationBase erwartet diese Signatur fuer Hotspots.
func offset_for_point(screen_point: Vector2) -> Vector2:
	return depth_offset_for_screen_point(screen_point)

func project_master_point(master_point: Vector2, depth_group := "") -> Vector2:
	return RoomProjectionUtil.project_master_point(self, master_point, depth_group)

func depth_offset_for_master_point(master_point: Vector2, depth_group := "") -> Vector2:
	return RoomProjectionUtil.depth_offset_for_master(self, master_point, depth_group)

func set_test_look(value: Vector2) -> void:
	_depth_test_lock = true
	_depth_look = value
	_depth_target = value
	_apply_depth_projection()

func clear_test_look() -> void:
	_depth_test_lock = false

func depth_look() -> Vector2:
	return _depth_look

# ------------------------------------------------- Editor-Zoom/Pan (Deko-Modus)
var editor_zoom := 1.0
var editor_pan := Vector2.ZERO

## Auf einen Punkt zoomen (der Punkt unter dem Zeiger bleibt fix).
func editor_zoom_at(view_point: Vector2, factor: float) -> void:
	EditorBridge.zoom_at(self, view_point, factor)

func editor_pan_by(delta: Vector2) -> void:
	EditorBridge.pan_by(self, delta)

func editor_reset_view() -> void:
	EditorBridge.reset_view(self)

## Ansicht auf einen Master-Punkt zentrieren + zoomen (Kabel-Editor: Gerätefokus).
func editor_focus(master_point: Vector2, zoom: float) -> void:
	EditorBridge.focus(self, master_point, zoom)

## Editierbare Flächen-Vierecke ("quads": {name: {corners, color}}).
func _quads() -> Dictionary:
	return config().get("quads", {})

## Textur des Basis-Layers (z 0) — das WeatherOverlay zeigt den Fensterbereich
## davon ein zweites Mal (nur durchs Glas maskiert) und dunkelt ihn wetterab-
## hängig ab: „draußen wird es trüb", ohne ein extra Außen-Bild.
func base_texture() -> Texture2D:
	for child in get_children():
		if child is TextureRect and child.z_index == 0 and child.texture != null:
			return child.texture
	return null

## Tiefenbereich (far_y, near_y) — aus der markierten Tischplatte, sonst
## aus dem perspective-Block (die Bewegungsgeometrie folgt dem Quad).
func _depth_range() -> Vector2:
	return RoomProjectionUtil.depth_range(self)

func _layout_all() -> void:
	RoomLayoutEngine.layout(self)

func _apply_depth_projection() -> void:
	RoomProjectionUtil.apply_depth(self)

# ---------------------------------------------------- Abfragen & Klemmen

## Oberstes verschiebbares Objekt unter dem Zeiger (höchster z_index).
func _child_at(point: Vector2) -> Control:
	return EditorGeometry.child_at(get_children(), config().get("anchors", {}), point)

func _clamp_to_zone(a: Array, zone_name: String) -> void:
	EditorGeometry.clamp_to_zone(a, zone_name, _quads(), config().get("zones", {}))

# ------------------------------------------- Deko-API (delegiert an Editor)

## F8: Deko-Modus an/aus; beim Ausschalten speichert der DekoEditor die
## JSON und der Raum wird neu aufgebaut.
func set_edit_mode(enabled: bool, persist_changes: bool = true) -> void:
	EditorBridge.set_edit_mode(self, enabled, persist_changes)

func editor_pick(local: Vector2, model_specific := false) -> bool:
	return EditorBridge.pick(self, local, model_specific)

func editor_drag_to(local: Vector2) -> bool:
	return EditorBridge.drag_to(self, local)

func editor_release() -> void:
	EditorBridge.release(self)

func editor_wheel(local: Vector2, direction: float, shift: bool, ctrl: bool = false, alt: bool = false) -> bool:
	return EditorBridge.wheel(self, local, direction, shift, ctrl, alt)

## EditorPlugin-Tastaturpfad (M/Shift+M) zur aktuellen Layer-Auswahl.
func editor_cycle_model(direction := 1) -> bool:
	return EditorBridge.cycle_model(self, direction)

# ------------------------------------------------------------- Zeichnung

## Wetter zeichnet das WeatherOverlay (z 20), Hilfslinien der DekoEditor (z 60).
func _draw() -> void:
	if _editor != null and is_instance_valid(_editor):
		_editor.queue_redraw()
