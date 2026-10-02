class_name AnimatedPortrait
extends Control
## Gerahmte 128er-Pixelportraet-Buehne. Identitaet/Zustand kommen aus den
## Managern; dieser Knoten besitzt nur transiente Animation und einen kleinen,
## lokalen Framecache. Die Pixeltextur bleibt immer NEAREST und unverwischt.

const VisemeScript := preload("res://scripts/gfx/portrait_viseme.gd")
const ART_SIZE := 128.0
const FRAME_PAD := 4.0
const WIDGET_SIZE := Vector2(136, 136)
const MAX_CACHED_FRAMES := 24

var speaker_id := ""
var portrait_state: Dictionary = {}
var emotion := "neutral"
var speaking := false
var viseme := "rest"

var _art: TextureRect
var _frame_cache: Dictionary = {}
var _cache_order: Array = []
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _blink := false
var _blink_until := 0.0
var _next_blink := 2.8
var _gaze := 0
var _next_gaze := 2.1
var _breath_offset := 0.0
var _speaker_color := Color(0.32, 0.62, 0.72)
var _reduced_motion := false
var _idle_motion := true


func _init() -> void:
	custom_minimum_size = WIDGET_SIZE
	size = WIDGET_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	_ensure_art()
	_apply_settings()
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_signal("settings_changed"):
		settings.settings_changed.connect(_apply_settings)
	_refresh_frame()


func setup(id: String, state: Dictionary = {}) -> void:
	_ensure_art()
	var clean_state := state.duplicate(true)
	var next_emotion := str(clean_state.get("emotion", "neutral"))
	var identity_key := "%s|%s" % [id, JSON.stringify(clean_state)]
	var old_key := "%s|%s" % [speaker_id, JSON.stringify(portrait_state)]
	if identity_key != old_key:
		_frame_cache.clear()
		_cache_order.clear()
		speaker_id = id
		portrait_state = clean_state
		emotion = next_emotion
		_reset_idle_clock()
		_speaker_color = _color_for_id(id)
		queue_redraw()
	else:
		emotion = next_emotion
	_refresh_frame()


func set_emotion(value: String) -> void:
	var next := value if value != "" else "neutral"
	if emotion == next:
		return
	emotion = next
	portrait_state["emotion"] = emotion
	_refresh_frame()


func set_speaking(value: bool) -> void:
	if speaking == value:
		if not value and viseme != VisemeScript.REST:
			set_viseme(VisemeScript.REST)
		return
	speaking = value
	if not speaking:
		viseme = VisemeScript.REST
	_refresh_frame()


# Mindest-Haltezeit einer Mundform. Der Typewriter liefert 19–34 Zeichen/s —
# ungebremst wären das bis zu 34 Mundwechsel pro Sekunde (Flatter-Mund).
# Trickfilm-Praxis sind ~10–12 Wechsel/s; Zwischenlaute werden übersprungen.
const VISEME_MIN_HOLD := 0.075
var _viseme_hold := 0.0
var _viseme_pending := ""


func set_viseme(value: String) -> void:
	var next := value if VisemeScript.valid(value) else VisemeScript.REST
	if _reduced_motion:
		next = VisemeScript.REST
	if viseme == next:
		return
	viseme = next
	_viseme_hold = VISEME_MIN_HOLD
	_refresh_frame()


func speak_character(text: String, character_index: int) -> void:
	if not speaking:
		return
	var target := VisemeScript.for_text(text, character_index)
	# REST (Satzzeichen/Pause) schließt den Mund IMMER sofort — das hält die
	# Silhouette ruhig und der Satzrhythmus bleibt sichtbar. Alles andere
	# wartet die Haltezeit ab; nur das JÜNGSTE Ziel wird nachgezogen.
	if target == VisemeScript.REST or _viseme_hold <= 0.0:
		_viseme_pending = ""
		set_viseme(target)
	else:
		_viseme_pending = target


func cache_size() -> int:
	return _frame_cache.size()


func _process(delta: float) -> void:
	if speaker_id == "":
		return
	_time += delta
	if _viseme_hold > 0.0:
		_viseme_hold -= delta
		if _viseme_hold <= 0.0 and _viseme_pending != "" and _viseme_pending != viseme:
			var next := _viseme_pending
			_viseme_pending = ""
			set_viseme(next)
	var frame_changed := false
	if _idle_motion and not _reduced_motion:
		if _blink and _time >= _blink_until:
			_blink = false
			_next_blink = _time + _rng.randf_range(2.6, 5.1)
			frame_changed = true
		elif not _blink and _time >= _next_blink:
			_blink = true
			_blink_until = _time + 0.11
			frame_changed = true
		if _time >= _next_gaze:
			_gaze = [-1, 0, 0, 1][_rng.randi() % 4]
			_next_gaze = _time + _rng.randf_range(1.8, 3.7)
			frame_changed = true
		_breath_offset = 1.0 if sin(_time * 2.25) > 0.25 else 0.0
	else:
		if _blink or _gaze != 0:
			_blink = false
			_gaze = 0
			frame_changed = true
		_breath_offset = 0.0
	if _art != null:
		_art.position = Vector2(FRAME_PAD, FRAME_PAD + _breath_offset)
	if frame_changed:
		_refresh_frame()


func _draw() -> void:
	var stage := Rect2(Vector2(FRAME_PAD, FRAME_PAD), Vector2(ART_SIZE, ART_SIZE))
	# Sprecherfarbiger Aussenrahmen und dunkle, nicht-animehafte Portraitbuehne.
	draw_rect(stage.grow(2.0), _speaker_color.darkened(0.42), true)
	draw_rect(stage.grow(1.0), _speaker_color.lightened(0.12), false, 1.0)
	draw_rect(stage, Color(0.035, 0.04, 0.065), true)
	draw_rect(Rect2(stage.position + Vector2(1, 1), Vector2(5, stage.size.y - 2)),
		Color(_speaker_color.r, _speaker_color.g, _speaker_color.b, 0.22), true)
	# Dezenter Kontaktschatten unter der Bueste, bevor die Pixeltextur gezeichnet wird.
	draw_set_transform(stage.position + Vector2(64, 112), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, 39.0, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ensure_art() -> void:
	if _art != null:
		return
	_art = TextureRect.new()
	_art.name = "PixelPortrait"
	_art.position = Vector2(FRAME_PAD, FRAME_PAD)
	_art.size = Vector2(ART_SIZE, ART_SIZE)
	_art.custom_minimum_size = Vector2(ART_SIZE, ART_SIZE)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)


func _refresh_frame() -> void:
	if _art == null or speaker_id == "":
		return
	var frame_state := {
		"emotion": emotion,
		"blink": _blink,
		"gaze": _gaze,
		"viseme": VisemeScript.REST if _reduced_motion else viseme,
		"mouth_pose": VisemeScript.REST if _reduced_motion else viseme,
	}
	var key := JSON.stringify(frame_state)
	if _frame_cache.has(key):
		_art.texture = _frame_cache[key]
		return
	var texture := _request_texture(frame_state)
	if texture == null:
		return
	_frame_cache[key] = texture
	_cache_order.append(key)
	while _cache_order.size() > MAX_CACHED_FRAMES:
		var oldest: String = str(_cache_order.pop_front())
		_frame_cache.erase(oldest)
	_art.texture = texture


func _request_texture(frame_state: Dictionary) -> Texture2D:
	var state := portrait_state.duplicate(true)
	state["emotion"] = emotion
	# Autoloads über den MainLoop-Root holen: setup()/Frame-Refresh laufen auch,
	# BEVOR das Widget im Szenenbaum hängt — absolute get_node()-Pfade von außerhalb
	# des Trees sind in Godot verboten (roter Debugger-Fehler, Textur blieb null).
	var ml_root: Node = (Engine.get_main_loop() as SceneTree).root if Engine.get_main_loop() is SceneTree else null
	if ml_root == null:
		return null
	if speaker_id == "player":
		var player := ml_root.get_node_or_null("PlayerIdentity")
		if player == null:
			return null
		if player.has_method("portrait_frame"):
			return player.call("portrait_frame", state, frame_state) as Texture2D
		if player.has_method("texture"):
			return player.call("texture", state) as Texture2D
		return null
	var npcs := ml_root.get_node_or_null("NPCManager")
	if npcs == null:
		return null
	if npcs.has_method("portrait_frame"):
		return npcs.call("portrait_frame", speaker_id, state, frame_state) as Texture2D
	if npcs.has_method("portrait"):
		return npcs.call("portrait", speaker_id, state) as Texture2D
	return null


func _reset_idle_clock() -> void:
	_rng.seed = hash(speaker_id) ^ 0x51A7B11
	_time = 0.0
	_blink = false
	_gaze = 0
	_next_blink = 2.5 + _rng.randf_range(0.0, 1.6)
	_next_gaze = 1.7 + _rng.randf_range(0.0, 1.2)
	_breath_offset = 0.0


func _apply_settings() -> void:
	var settings := get_node_or_null("/root/SettingsManager")
	var reduced := false
	var ambient := true
	if settings != null and settings.has_method("value"):
		var reduced_value: Variant = settings.call("value", "reduced_motion")
		reduced = reduced_value == true
		var ambient_value: Variant = settings.call("value", "ambient_life")
		if ambient_value != null:
			ambient = ambient_value != false
	_reduced_motion = reduced or OS.get_environment("DSS_SHOT") == "1"
	_idle_motion = ambient and not _reduced_motion
	if _reduced_motion:
		viseme = VisemeScript.REST
	_refresh_frame()


static func _color_for_id(id: String) -> Color:
	var value := absi(hash(id))
	var hue := fmod(float(value % 1000) / 1000.0 + 0.47, 1.0)
	return Color.from_hsv(hue, 0.48, 0.72)
