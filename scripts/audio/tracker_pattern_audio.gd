class_name TrackerPatternAudio
extends Node
## Fensterlokaler Voice-Pool fuer das Pattern-Labor. Er laeuft bewusst ueber
## den Music-Bus, folgt dem Musikregler und cached die prozeduralen Samples.

const Synth := preload("res://scripts/audio/tracker_pattern_synth.gd")
const VOICE_COUNT := 8

var _voices: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next_voice := 0
var triggered_hits := 0


func _ready() -> void:
	for _index in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = "Music"
		add_child(voice)
		_voices.append(voice)
	_apply_volume()
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_apply_volume):
		SettingsManager.settings_changed.connect(_apply_volume)


func trigger(track: int, sample_name: StringName, effect: int, step: int, preview := false) -> bool:
	if track < 0 or track > 3 or _voices.is_empty():
		return false
	var pitch_step := posmod(step, 8) if track == 3 else 0
	var key := "%d/%s/%d/%d" % [track, sample_name, clampi(effect, 0, 3), pitch_step]
	var stream: AudioStream = _cache.get(key)
	if stream == null:
		stream = Synth.make_hit(track, sample_name, effect, pitch_step)
		if stream == null:
			return false
		_cache[key] = stream
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = 1.0
	voice.volume_db = _music_volume_db() + (1.5 if preview else 0.0)
	voice.play()
	triggered_hits += 1
	return true


func stop_all() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()


func cache_size() -> int:
	return _cache.size()


func _apply_volume() -> void:
	var db := _music_volume_db()
	for voice: AudioStreamPlayer in _voices:
		voice.volume_db = db


func _music_volume_db() -> float:
	var linear := clampf(float(SettingsManager.value("music")), 0.0, 1.0) if SettingsManager != null else 0.7
	return -60.0 if linear <= 0.001 else linear_to_db(linear)


func _exit_tree() -> void:
	stop_all()
