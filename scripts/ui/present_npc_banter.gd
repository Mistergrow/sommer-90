class_name PresentNpcBanter
extends Control
## Kurze, rein atmosphaerische Zweiergespraeche fuer die NPC-Leiste eines Orts.
## Verwendet dieselben 128er Portraitframes wie echte Dialoge, veraendert aber
## weder Quest-, Zeit-, Trust- noch Save-Zustand.

const CONFIG := "res://data/location_banter.json"
const VisemeScript := preload("res://scripts/gfx/portrait_viseme.gd")

const INITIAL_DELAY := 0.8
const MIN_TURN_TIME := 2.4
const MAX_TURN_TIME := 4.6
const REST_MIN := 4.5
const REST_MAX := 7.5
const MOUTH_FPS := 11.0

var _bar: HBoxContainer
var _profile_id := ""
var _npc_ids: Array[String] = []
var _portrait_buttons: Dictionary = {}
var _entries: Array[Dictionary] = []
var _entry: Dictionary = {}
var _entry_index := 0
var _reply_turn := false
var _phase := "rest"
var _phase_left := INITIAL_DELAY
var _phase_duration := INITIAL_DELAY
var _turn_text := ""
var _speaker_id := ""
var _listener_id := ""
var _speaker_emotion := "neutral"
var _listener_emotion := "neutral"
var _mouth_clock := 0.0
var _last_frame_keys: Dictionary = {}
var _bubble: PanelContainer
var _bubble_text: Label
var _rng := RandomNumberGenerator.new()
var _was_enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(430, 62)
	size = custom_minimum_size
	_build_bubble()


func setup(bar: HBoxContainer, npc_ids: Array, profile_id: String) -> void:
	_bar = bar
	_profile_id = profile_id
	_npc_ids.clear()
	for raw_id: Variant in npc_ids:
		_npc_ids.append(str(raw_id))
	_portrait_buttons.clear()
	for child: Node in _bar.get_children():
		var npc_id := str(child.get_meta("npc_id", ""))
		var portrait := child.get_node_or_null("Portrait")
		if not npc_id.is_empty() and portrait is TextureButton:
			_portrait_buttons[npc_id] = portrait
	_load_entries()
	var time_manager := get_node_or_null("/root/TimeManager")
	var current_year := int(time_manager.get("year")) if time_manager != null else 1990
	var current_day := int(time_manager.get("day_counter")) if time_manager != null else 0
	_rng.seed = hash("%s:%d:%d" % [_profile_id, current_year, current_day])
	_entry_index = posmod(int(_rng.randi()), maxi(1, _entries.size()))
	_phase_left = INITIAL_DELAY
	_phase_duration = INITIAL_DELAY
	if _entries.is_empty():
		set_process(false)


func _build_bubble() -> void:
	if _bubble != null:
		return
	_bubble = PanelContainer.new()
	_bubble.name = "SpeechBubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.custom_minimum_size = Vector2(430, 58)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.025, 0.03, 0.045, 0.94)
	panel.border_color = Color(0.34, 0.68, 0.82, 0.92)
	panel.set_border_width_all(2)
	panel.corner_radius_top_left = 3
	panel.corner_radius_top_right = 3
	panel.corner_radius_bottom_left = 3
	panel.corner_radius_bottom_right = 3
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 7
	panel.content_margin_bottom = 7
	_bubble.add_theme_stylebox_override("panel", panel)
	add_child(_bubble)

	_bubble_text = Label.new()
	_bubble_text.name = "Dialogue"
	_bubble_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.max_lines_visible = 2
	_bubble_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_bubble_text.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	_bubble_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_bubble_text.add_theme_constant_override("outline_size", 2)
	_bubble_text.add_theme_font_size_override("font_size", 12)
	_bubble.add_child(_bubble_text)
	_bubble.hide()


func _load_entries() -> void:
	_entries.clear()
	if not FileAccess.file_exists(CONFIG):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not parsed is Dictionary:
		return
	var time_manager := get_node_or_null("/root/TimeManager")
	var current_year := int(time_manager.get("year")) if time_manager != null else 1990
	for raw_entry: Variant in (parsed as Dictionary).get(_profile_id, []):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var speaker := str(entry.get("speaker", ""))
		var listener := str(entry.get("listener", ""))
		if speaker not in _npc_ids or listener not in _npc_ids:
			continue
		if current_year < int(entry.get("year_from", 1990)) \
				or current_year > int(entry.get("year_to", 9999)):
			continue
		_entries.append(entry.duplicate(true))


func _process(delta: float) -> void:
	var enabled := _ambient_enabled()
	if not enabled:
		if _was_enabled:
			_finish_exchange()
		_was_enabled = false
		return
	_was_enabled = true
	if _entries.is_empty():
		return
	_phase_left -= delta
	if _phase == "talk":
		_mouth_clock += delta
		if _mouth_clock >= 1.0 / MOUTH_FPS:
			_mouth_clock = 0.0
			_update_talking_frame()
	if _phase_left > 0.0:
		return
	match _phase:
		"rest":
			_begin_exchange(_entry_index)
		"talk":
			if not _reply_turn and not str(_entry.get("reply", "")).is_empty():
				_reply_turn = true
				_show_turn()
			else:
				_finish_exchange()


func _begin_exchange(index: int) -> void:
	if _entries.is_empty():
		return
	_entry_index = posmod(index, _entries.size())
	_entry = _entries[_entry_index]
	_entry_index = (_entry_index + 1) % _entries.size()
	_reply_turn = false
	_show_turn()


func _show_turn() -> void:
	var first_speaker := str(_entry.get("speaker", ""))
	var first_listener := str(_entry.get("listener", ""))
	if _reply_turn:
		_speaker_id = first_listener
		_listener_id = first_speaker
		_turn_text = Loc.t(str(_entry.get("reply_key", "")),
			str(_entry.get("reply", "")))
		_speaker_emotion = str(_entry.get("reply_emotion", "happy"))
		_listener_emotion = str(_entry.get("speaker_reaction", "happy"))
	else:
		_speaker_id = first_speaker
		_listener_id = first_listener
		_turn_text = Loc.t(str(_entry.get("line_key", "")),
			str(_entry.get("line", "")))
		_speaker_emotion = str(_entry.get("speaker_emotion", "talking"))
		_listener_emotion = str(_entry.get("listener_emotion", "thinking"))
	var npc_manager := get_node_or_null("/root/NPCManager")
	var speaker_data: Dictionary = npc_manager.call("get_npc", _speaker_id) \
		if npc_manager != null else {}
	var speaker_name := str(speaker_data.get("name", _speaker_id))
	_bubble_text.text = Loc.t_format("ui.present_npc_banter.s_s", "%s: »%s«",
		[speaker_name, _turn_text])
	_bubble.show()
	_phase = "talk"
	_phase_duration = clampf(1.35 + float(_turn_text.length()) / 19.0,
		MIN_TURN_TIME, MAX_TURN_TIME)
	_phase_left = _phase_duration
	_mouth_clock = 1.0
	_update_talking_frame()


func _update_talking_frame() -> void:
	var progress := clampf(1.0 - _phase_left / maxf(0.01, _phase_duration), 0.0, 1.0)
	var character_index := clampi(int(progress * maxf(1.0, float(_turn_text.length()))),
		0, maxi(0, _turn_text.length() - 1))
	var mouth_pose := VisemeScript.for_text(_turn_text, character_index)
	if _reduced_motion():
		mouth_pose = VisemeScript.REST
	var speaker_gaze := _gaze_towards(_speaker_id, _listener_id)
	var listener_gaze := _gaze_towards(_listener_id, _speaker_id)
	_set_portrait_frame(_speaker_id, _speaker_emotion, mouth_pose, speaker_gaze)
	_set_portrait_frame(_listener_id, _listener_emotion, VisemeScript.REST, listener_gaze)
	for npc_id: String in _portrait_buttons:
		var button: TextureButton = _portrait_buttons[npc_id]
		button.self_modulate = Color(1.13, 1.1, 0.94) if npc_id == _speaker_id \
			else Color(0.94, 1.04, 1.08) if npc_id == _listener_id else Color.WHITE


func _set_portrait_frame(npc_id: String, emotion: String, mouth_pose: String, gaze: int) -> void:
	if not _portrait_buttons.has(npc_id):
		return
	var frame_key := "%s|%s|%d" % [emotion, mouth_pose, gaze]
	if str(_last_frame_keys.get(npc_id, "")) == frame_key:
		return
	var npc_manager := get_node_or_null("/root/NPCManager")
	if npc_manager == null:
		return
	var button: TextureButton = _portrait_buttons[npc_id]
	button.texture_normal = npc_manager.call("portrait_frame", npc_id, {"emotion": emotion}, {
		"emotion": emotion,
		"mouth_pose": mouth_pose,
		"eye_frame": "open",
		"gaze": gaze,
	}) as Texture2D
	_last_frame_keys[npc_id] = frame_key


func _finish_exchange() -> void:
	_phase = "rest"
	_phase_duration = _rng.randf_range(REST_MIN, REST_MAX)
	_phase_left = _phase_duration
	_entry = {}
	_reply_turn = false
	_speaker_id = ""
	_listener_id = ""
	_turn_text = ""
	if _bubble != null:
		_bubble.hide()
	var npc_manager := get_node_or_null("/root/NPCManager")
	for npc_id: String in _portrait_buttons:
		var button: TextureButton = _portrait_buttons[npc_id]
		if npc_manager != null:
			button.texture_normal = npc_manager.call("portrait", npc_id) as Texture2D
		button.self_modulate = Color.WHITE
	_last_frame_keys.clear()


func _gaze_towards(from_id: String, to_id: String) -> int:
	var from_index := _npc_ids.find(from_id)
	var to_index := _npc_ids.find(to_id)
	if from_index < 0 or to_index < 0 or from_index == to_index:
		return 0
	return -1 if to_index < from_index else 1


func _ambient_enabled() -> bool:
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_method("value"):
		return settings.call("value", "ambient_life") != false
	return true


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/SettingsManager")
	return settings != null and settings.has_method("value") \
		and settings.call("value", "reduced_motion") == true


## Test-/Editor-Haken: startet reproduzierbar einen vorhandenen Dialog.
func force_entry(index := 0) -> bool:
	if _entries.is_empty():
		return false
	_begin_exchange(index)
	return true


func state_snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"speaker": _speaker_id,
		"listener": _listener_id,
		"reply": _reply_turn,
		"bubble_visible": _bubble != null and _bubble.visible,
		"entry_count": _entries.size(),
	}
