extends Node
## AmbientManager — ortsgebundene Umgebungsgeräusche (Vogelgezwitscher, Marktge-
## murmel, Raumton …), UNABHÄNGIG von der Ortsmusik (MusicManager). Läuft auf dem
## eigenen Audio-Bus "Ambient" und blendet beim Ortswechsel weich über.
##
## Datengetrieben: data/location_ambient.json bildet Orts-ID → {loop, volume} ab.
## Dateien liegen unter assets/audio/ambient/<NAME>[_V0n].ogg|mp3 — fehlt eine
## Datei, bleibt es an dem Ort still (kein Fehler). Siehe README dort.

const CONFIG_PATH := "res://data/location_ambient.json"
const AMBIENT_DIR := "res://assets/audio/ambient/"
const FADE_OUT := 0.5
const FADE_IN := 0.9
const SILENCE_DB := -50.0

var _config: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _current_loop := ""
var _location := ""
var _tween: Tween = null


func _ready() -> void:
	for _i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
		p.volume_db = SILENCE_DB
		add_child(p)
		_players.append(p)
	_load_config()
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("location_changed"):
		gm.location_changed.connect(_on_location_changed)
		# Startort (Zimmer) sofort bespielen, falls schon gesetzt.
		var cur: String = gm.get("current_location_id")
		if cur != "":
			_on_location_changed(cur)
	# Grundton-Betten (quiet_only) hören auf: sie weichen der Musik und — im
	# Spielerzimmer — dem laufenden Amiga. Bei jedem Zustandswechsel neu bewerten.
	var mm := get_node_or_null("/root/MusicManager")
	if mm != null and mm.has_signal("music_changed"):
		mm.music_changed.connect(_reevaluate)
	var ui := get_node_or_null("/root/UIManager")
	if ui != null and ui.has_signal("power_changed"):
		ui.power_changed.connect(_reevaluate)


func _on_location_changed(id: String) -> void:
	_location = id
	_reevaluate()


## Legt fest, welcher Loop am aktuellen Ort JETZT laufen soll. quiet_only-Betten
## verstummen, sobald es nicht mehr still ist; ändert sich nichts, kein Crossfade.
func _reevaluate() -> void:
	var entry: Variant = _config.get(_location, null)
	var loop := ""
	var vol_db := -16.0
	if entry is Dictionary:
		loop = str(entry.get("loop", ""))
		vol_db = float(entry.get("volume", -16.0))
		if bool(entry.get("quiet_only", false)) and not _is_quiet():
			loop = ""
	if loop == _current_loop:
		return
	_current_loop = loop
	_crossfade(_load_loop(loop) if loop != "" else null, vol_db)


## „Still" = keine Musik läuft; im Spielerzimmer zusätzlich Amiga/Monitor aus
## (dann trägt dort ohnehin das CRT-Brummen den Raum).
func _is_quiet() -> bool:
	var mm := get_node_or_null("/root/MusicManager")
	if mm != null and mm.has_method("is_playing") and mm.is_playing():
		return false
	if _location == "room":
		var ui := get_node_or_null("/root/UIManager")
		if ui != null and bool(ui.get("monitor_power")):
			return false
	return true


func _crossfade(stream: AudioStream, vol_db: float) -> void:
	var outgoing: AudioStreamPlayer = _players[_active]
	var incoming: AudioStreamPlayer = _players[1 - _active]
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(outgoing, "volume_db", SILENCE_DB, FADE_OUT).set_trans(Tween.TRANS_SINE)
	if stream != null:
		incoming.stream = stream
		incoming.volume_db = SILENCE_DB
		incoming.play()
		_tween.tween_property(incoming, "volume_db", vol_db, FADE_IN).set_trans(Tween.TRANS_SINE)
		_active = 1 - _active
	_tween.set_parallel(false)
	_tween.tween_callback(outgoing.stop)


## Loop-Datei auflösen: höchste Version, .ogg vor .mp3; Loop-Flag setzen.
func _load_loop(loop_name: String) -> AudioStream:
	var candidates: Array[String] = []
	for v in range(9, 0, -1):
		candidates.append("%s%s_V%02d.ogg" % [AMBIENT_DIR, loop_name, v])
		candidates.append("%s%s_V%02d.mp3" % [AMBIENT_DIR, loop_name, v])
	candidates.append("%s%s.ogg" % [AMBIENT_DIR, loop_name])
	candidates.append("%s%s.mp3" % [AMBIENT_DIR, loop_name])
	for path in candidates:
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			if s != null:
				# Nahtloses Loopen erzwingen (Ogg/MP3 kennen beide 'loop').
				if "loop" in s:
					s.set("loop", true)
				return s
	return null


func set_ambient_volume(linear: float) -> void:
	# Optionaler globaler Regler über den Ambient-Bus.
	var idx := AudioServer.get_bus_index("Ambient")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx,
			-60.0 if linear <= 0.001 else linear_to_db(clampf(linear, 0.0, 1.0)))


func release_audio() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.stream = null
	_current_loop = ""


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		_config = parsed
