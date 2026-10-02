extends RefCounted
## Eigene Paula-Audiodomäne des Spiels: Musikpräsentation, Stimmen-Pool,
## Lautlos-Regel und sauberes Abmelden beim Verlassen.

const Synth := preload("res://scripts/audio/wunderwerk_synth.gd")

var title_stream: AudioStreamWAV
var park_stream: AudioStreamWAV
var _music: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
var _sfx: Dictionary = {}


func setup(host: Node) -> void:
	title_stream = Synth.title_loop()
	park_stream = Synth.park_loop()
	_sfx = {
		"move": Synth.blip(620.0),
		"select": Synth.blip(820.0),
		"build": Synth.build(),
		"cash": Synth.cash(),
		"alarm": Synth.alarm(),
		"cheer": Synth.cheer(),
	}
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -12.0
	host.add_child(_music)
	for _index in 5:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = -7.0
		host.add_child(player)
		_sfx_pool.append(player)


func play_music(host: Node, stream: AudioStream) -> void:
	if _music == null or (_music.stream == stream and _music.playing):
		return
	_music.stop()
	_music.stream = stream
	if _audio_allowed(host):
		_music.play()
	var presenter := host.get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("present_external"):
		presenter.call("present_external", _music, "WUNDERWERK '94",
			"AMIGA 600 · OCS · 4-KANAL")


func play_sfx(host: Node, id: String) -> void:
	if not _audio_allowed(host) or _sfx_pool.is_empty() or not _sfx.has(id):
		return
	var player := _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	player.stream = _sfx[id]
	player.play()


func cleanup(host: Node) -> void:
	if _music != null:
		_music.stop()
	var presenter := host.get_node_or_null("/root/MusicManager")
	if presenter != null and presenter.has_method("clear_external"):
		presenter.call("clear_external", _music)


func _audio_allowed(host: Node) -> bool:
	var manager := host.get_node_or_null("/root/AudioManager")
	return manager == null or not bool(manager.get("muted"))
