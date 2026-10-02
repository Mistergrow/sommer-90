class_name NpcWorldFigure
extends TextureRect
## Animierte 32x48-Weltfigur fuer begehbare Orte.
##
## Die Figur bleibt ein echtes, nearest-gefiltertes Amiga-Sprite. Nur wenn sich
## Lid, Blick oder Mundpose aendern, wird ein neuer (anschliessend gecachter)
## Frame angefordert; Atmen und kleine Gewichtsverlagerungen geschehen als
## billige Canvas-Transformation. Damit leben auch mehrere anwesende NPCs,
## ohne pro Frame Bilder neu zu erzeugen.

const ROLE_SHOP_COUNTER := "shop_counter"
const ROLE_SERVICE := "service"
const ROLE_VENDOR := "vendor"
const ROLE_TEACHER := "teacher"
const ROLE_SOCIAL := "social"
const AnimationProfile := preload("res://scripts/gfx/npc_animation_profile.gd")
const FRAME_CACHE_LIMIT := 36

var npc_id := ""
var context: Dictionary = {}
var role := "idle"

var _frames: Dictionary = {}
var _frame_order: Array[String] = []
var _profile: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _phase := 0.0
var _blink := false
var _blink_until := 0.0
var _blink_repeats := 0
var _next_blink := 2.8
var _gaze := 0
var _next_gaze := 1.9
var _work_until := 0.0
var _next_work := 5.4
var _speak_until := 0.0
var _emotion := "neutral"
var _emotion_until := 0.0
var _gesture := "idle"
var _gesture_until := 0.0
var _gesture_started := 0.0
var _next_gesture := 4.0
var _hover_attention := false
var _dialogue_active := false
var _dialogue_speaking := false
var _reduced_motion := false
var _frame_key := ""


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * Vector2(0.5, 0.92)
	if not npc_id.is_empty():
		_refresh_frame(true)


func setup(id: String, state: Dictionary = {}, animation_role: String = "idle") -> void:
	npc_id = id
	context = state.duplicate(true)
	role = animation_role
	# setup() wird in LocationBase absichtlich vor dem Einhaengen in die Stage
	# aufgerufen. Der Autoload ist trotzdem bereits verfuegbar; ohne diesen Abruf
	# verloren generische NPCs ihr Persoenlichkeitsprofil und wirkten identisch.
	var npc: Dictionary = NPCManager.get_npc(npc_id)
	_profile = AnimationProfile.profile_for(npc_id, role, npc)
	_rng.seed = hash("%s|%s|%s" % [npc_id, str(context.get("location", "")), role])
	_phase = float(posmod(int(_rng.seed), 997)) / 997.0 * TAU
	_frames.clear()
	_frame_order.clear()
	_time = 0.0
	_next_blink = _rng.randf_range(1.4, float(_profile.get("blink_max", 5.3)))
	_next_gaze = _rng.randf_range(1.0, float(_profile.get("gaze_max", 4.2)))
	_next_work = _rng.randf_range(2.8, float(_profile.get("work_max", 10.5)))
	_next_gesture = _rng.randf_range(2.6, float(_profile.get("gesture_max", 8.5)))
	# setup() wird bewusst aufgerufen, bevor die Figur in den SceneTree kommt.
	# Ein absoluter get_node()-Pfad ist in diesem Zustand in Godot 4.8 ungueltig
	# und erzeugte bei jedem Ortsaufbau einen Debuggerfehler. Der Autoload ist
	# bereits als Singleton gebunden und kann ohne SceneTree-Pfad gelesen werden.
	_reduced_motion = SettingsManager.value("reduced_motion") == true
	_refresh_frame(true)


## Hover bedeutet Blickkontakt statt grelles Aufleuchten der ganzen Figur.
func set_attention(active: bool) -> void:
	_hover_attention = active
	if active:
		_gaze = 0
	self_modulate = Color(1.045, 1.035, 0.985) if active else Color.WHITE
	_refresh_frame(true)


## Kurze sichtbare Antwort, bevor das eigentliche Dialogfenster uebernimmt.
func react_to_speech(emotion: String = "talking") -> void:
	_hover_attention = true
	_gaze = 0
	_emotion = _canonical_emotion(emotion)
	_emotion_until = _time + 1.0
	_speak_until = maxf(_speak_until, _time + 0.9)
	_start_gesture("greet", 0.72)
	_refresh_frame(true)


## Der sichtbare Ortsaktor folgt dem echten Dialogknoten. Sprecher animieren
## Mund, Nicken und Ausdruck; Zuhoerer halten Blickkontakt und reagieren leise.
func set_dialogue_state(active: bool, speaking: bool = false,
		emotion: String = "neutral") -> void:
	_dialogue_active = active
	_dialogue_speaking = active and speaking
	_gaze = 0
	if active:
		_emotion = _canonical_emotion(emotion if not emotion.is_empty() else \
			("talking" if speaking else "thinking"))
		_emotion_until = INF
		_speak_until = INF if speaking else 0.0
		_start_gesture("explain" if speaking else "listen", 1.15)
	else:
		_speak_until = 0.0
		_emotion = "neutral"
		_emotion_until = 0.0
		_dialogue_speaking = false
		_gesture = "idle"
		self_modulate = Color.WHITE
		_next_gaze = _time + 1.0
	_refresh_frame(true)


func set_emotion(emotion: String, duration := 1.25) -> void:
	_emotion = _canonical_emotion(emotion)
	_emotion_until = _time + maxf(0.1, duration)
	_refresh_frame(true)


func _process(delta: float) -> void:
	if npc_id.is_empty():
		return
	_time += minf(maxf(delta, 0.0), 0.1)
	var frame_changed := false
	var attentive := _hover_attention or _dialogue_active
	if not _dialogue_active and _emotion != "neutral" and _time >= _emotion_until:
		_emotion = "neutral"
		frame_changed = true

	if _blink and _time >= _blink_until:
		_blink = false
		if _blink_repeats > 0:
			_blink_repeats -= 1
			_next_blink = _time + 0.13
		else:
			_next_blink = _time + _rng.randf_range(
				float(_profile.get("blink_min", 2.7)), float(_profile.get("blink_max", 5.3)))
		frame_changed = true
	elif not _blink and _time >= _next_blink:
		_blink = true
		_blink_until = _time + 0.09 / float(_profile.get("tempo", 1.0))
		if _rng.randf() < float(_profile.get("double_blink_chance", 0.13)):
			_blink_repeats = 1
		frame_changed = true

	if not attentive and _time >= _next_gaze and _time >= _speak_until:
		_gaze = [-1, 0, 0, 1][_rng.randi_range(0, 3)]
		_next_gaze = _time + _rng.randf_range(
			float(_profile.get("gaze_min", 1.8)), float(_profile.get("gaze_max", 4.2)))
		frame_changed = true

	if role in [ROLE_SHOP_COUNTER, ROLE_SERVICE, ROLE_VENDOR] and not attentive \
			and _time >= _next_work and _time >= _speak_until:
		_work_until = _time + _rng.randf_range(0.75, 1.25)
		_next_work = _time + _rng.randf_range(
			float(_profile.get("work_min", 5.8)), float(_profile.get("work_max", 10.5)))
		_gaze = -1 if _rng.randi_range(0, 1) == 0 else 1
		_emotion = str(_profile.get("work_emotion", "thinking"))
		_emotion_until = _work_until
		_start_gesture("work", _work_until - _time)
		frame_changed = true
	if _work_until > 0.0 and _time >= _work_until:
		_work_until = 0.0
		_gaze = 0
		_gesture = "idle"
		if not _dialogue_active:
			_emotion = "neutral"
		frame_changed = true

	if not _dialogue_active and _hover_attention and _speak_until > 0.0 \
			and _time >= _speak_until:
		_speak_until = 0.0
		_hover_attention = false
		self_modulate = Color.WHITE
		_next_gaze = _time + 1.2
		frame_changed = true

	if not attentive and _work_until <= _time and _time >= _next_gesture:
		var evening := _current_slot() >= 3
		var choices := ["shift", "nod", "glance"]
		if evening:
			choices.append("yawn")
		_start_gesture(str(choices[_rng.randi_range(0, choices.size() - 1)]),
			_rng.randf_range(0.7, 1.25))
		_next_gesture = _time + _rng.randf_range(
			float(_profile.get("gesture_min", 4.8)), float(_profile.get("gesture_max", 8.5)))
		if _gesture == "yawn":
			_emotion = "tired"
			_emotion_until = _gesture_until
		frame_changed = true
	if _gesture != "idle" and _time >= _gesture_until and _work_until <= _time:
		_gesture = "idle"
		if not _dialogue_active and _time >= _emotion_until:
			_emotion = "neutral"
		frame_changed = true

	if frame_changed or _speak_until > _time or _dialogue_speaking:
		_refresh_frame(false)

	_apply_body_motion()


func _apply_body_motion() -> void:
	# Alle Bewegungen sind in Quellpixeln gedacht. Der Fussanker bleibt ruhig;
	# auch hinter einer Theke schwebt oder rutscht keine Figur.
	var tempo := float(_profile.get("tempo", 1.0))
	var motion := float(_profile.get("motion", 1.0))
	var breath_rate := float(_profile.get("breath_rate", 1.0))
	var breath := (sin(_time * 2.0 * breath_rate + _phase) + 1.0) * 0.5
	var working := _work_until > _time
	var speaking := _dialogue_speaking or _speak_until > _time
	var gesture_t := clampf((_time - _gesture_started) /
		maxf(0.01, _gesture_until - _gesture_started), 0.0, 1.0)
	var pulse := sin(gesture_t * PI)
	var x := 0.0
	var y := -0.55 * breath * motion
	var tilt := float(_profile.get("idle_tilt", 0.004)) * sin(_time * tempo + _phase)
	if working:
		x += 0.42 * sin(_time * 3.0 * tempo) * motion
		tilt += 0.006 * sin(_time * 2.7 * tempo)
	if speaking:
		var syllable := sin(_time * float(_profile.get("talk_rate", 10.5)))
		y -= maxf(0.0, syllable) * 0.48 * float(_profile.get("nod", 1.0))
		tilt += 0.0035 * syllable * motion
	match _gesture:
		"greet", "nod": y -= pulse * 0.8 * float(_profile.get("nod", 1.0))
		"explain":
			x += pulse * 0.4 * (1.0 if _gaze >= 0 else -1.0)
			tilt += pulse * 0.008
		"listen": tilt += pulse * 0.007 * (-1.0 if _gaze >= 0 else 1.0)
		"shift": x += pulse * 0.65 * motion
		"glance": tilt += pulse * 0.006
		"yawn": y += pulse * 0.38
	if _emotion in ["happy", "laughing"]:
		y -= maxf(0.0, sin(_time * 5.5)) * 0.16 * motion
	elif _emotion in ["surprised", "shocked"]:
		y -= pulse * 0.45
	elif _emotion == "tired":
		y += 0.22
		tilt *= 0.45
	elif _emotion == "angry":
		tilt *= 0.25
	if _reduced_motion:
		x *= 0.25
		y *= 0.35
		tilt *= 0.2
	position = Vector2(x, y)
	rotation = tilt
	scale = Vector2(1.0 - breath * 0.002 * motion, 1.0 + breath * 0.0038 * motion)


func _refresh_frame(force: bool) -> void:
	if npc_id.is_empty() or not is_inside_tree():
		return
	var speaking := _speak_until > _time
	var mouth := "rest"
	if speaking:
		var visemes := ["ai", "e", "ou", "mbp", "e", "fv", "ai", "l"]
		mouth = visemes[posmod(int(floor(_time * float(_profile.get("talk_rate", 10.5)))),
			visemes.size())]
	var body_pose := _body_pose()
	var key := "%d|%d|%s|%s|%s" % [1 if _blink else 0, _gaze, mouth,
		_emotion, body_pose]
	if not force and key == _frame_key:
		return
	_frame_key = key
	if not _frames.has(key):
		var render_context := context.duplicate(true)
		render_context["emotion"] = _emotion
		render_context["body_pose"] = body_pose
		_frames[key] = NPCManager.figure(npc_id, render_context, {
			"blink": _blink,
			"gaze": _gaze,
			"mouth_pose": mouth,
			"emotion": _emotion,
		})
		_frame_order.append(key)
		while _frame_order.size() > FRAME_CACHE_LIMIT:
			var oldest: String = _frame_order.pop_front()
			_frames.erase(oldest)
	else:
		_frame_order.erase(key)
		_frame_order.append(key)
	texture = _frames[key]
	pivot_offset = size * Vector2(0.5, 0.92)


func _body_pose() -> String:
	if _work_until > _time or _gesture == "work":
		return "work"
	if _dialogue_speaking or _speak_until > _time or _gesture in ["greet", "explain"]:
		return "talk"
	if _dialogue_active or _gesture == "listen":
		return "listen"
	return "idle"


func _start_gesture(kind: String, duration: float) -> void:
	_gesture = kind
	_gesture_started = _time
	_gesture_until = _time + maxf(0.1, duration)


func _current_slot() -> int:
	var time_manager := get_node_or_null("/root/TimeManager")
	return int(time_manager.get("slot")) if time_manager != null else 1


func _canonical_emotion(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	return clean if clean in ["neutral", "happy", "laughing", "sad", "angry",
		"surprised", "shocked", "thinking", "talking", "tired", "nervous", "proud"] \
		else "neutral"


## Stabile Diagnosedaten fuer Preview, Tests und spaetere Animationsregie.
func animation_snapshot() -> Dictionary:
	return {
		"npc_id": npc_id,
		"role": role,
		"profile_id": str(_profile.get("profile_id", "balanced")),
		"emotion": _emotion,
		"gesture": _gesture,
		"body_pose": _body_pose(),
		"motion": float(_profile.get("motion", 1.0)),
		"dialogue_active": _dialogue_active,
		"dialogue_speaking": _dialogue_speaking,
		"frame_cache": _frames.size(),
	}
