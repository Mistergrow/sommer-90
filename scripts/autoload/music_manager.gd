extends Node
## MusicManager — die MOD-Sammlung, ihre Wiedergabe und die Standort-Musik.
##
## Gespielt wird nativ vom ModPlayer (kein Konvertieren). Man besitzt nur, was
## man im Spiel wirklich erhalten hat. Der erste MOD kommt erzählerisch von
## Stefan; der Rest ist die Computerclub-Bibliothek, die per Living Timeline
## über die Jahre wächst (year <= aktuelles
## Jahr). Am Club kopiert man Mods auf Diskette → daheim laufen sie auf der
## Anlage. Zusätzlich hat jeder passende Ort ein Ambient-Thema (Flohmarkt,
## Schulhof, Computerclub), das beim Betreten automatisch spielt.

signal music_changed
signal now_playing(track_id: String)
signal presentation_changed(state: Dictionary)

const ModPlayerScript := preload("res://scripts/audio/mod_player.gd")
const UserMods := preload("res://scripts/audio/user_mod_library.gd")

var tracks: Array = []
## Wie viele Stuecke an einem Ort hoechstens rotieren. Der Ortseintrag ist ein
## Pool ueber die ganze Dekade; hoerbar sind daraus stets nur die juengsten
## PLAYLIST_SIZE bereits erschienenen — so behaelt der Ort seine Klangidentitaet
## und bekommt trotzdem ueber die Jahre neue Musik.
const PLAYLIST_SIZE := 5
## Ab der Internet-/Archivphase wird bei ausbleibendem datiertem Neuzugang ein
## anderes Fenster des bereits erschienenen Ortspools hörbar. Das erzeugt auch
## 1998/99 eine echte, reproduzierbare Veränderung, ohne ältere MODs auf ein
## erfundenes Erscheinungsjahr umzudatieren.
const ARCHIVE_ROTATION_YEAR := 1998

var themes: Dictionary = {}     # location_id -> Pool von track_ids (jahresgefiltert)
var owned: Array = []
## Laufzeitindizes: 700+ MODs duerfen weder Track-Lookups noch Kanalbibliotheken
## bei jedem UI-Refresh erneut linear durchsuchen.
var _track_by_id: Dictionary = {}
var _club_tracks: Array = []
var _tracks_by_channel: Dictionary = {}
var _location_playlist_cache: Dictionary = {}
var current := ""
var _ambient := false           # true = Standort-Thema (kein manueller Titel)
var _loc_playlist: Array = []   # aktuelle Orts-Playlist (rotiert beim Loop)
var _loc_index := 0
var _source_kind := ""
var _source_id := ""
var _source_label := ""
var _external_player: WeakRef = null
var _external_title := ""
var _external_source := ""

var _mod: ModPlayer
var _music_db := 0.0   # aktuelle Musik-Lautstärke (dB)
var _user_mods := UserMods.new()
var _soundtrack_by_file: Dictionary = {}
var _playing_record: Dictionary = {}


func _ready() -> void:
	_load_catalog()
	_mod = ModPlayerScript.new()
	# Playlists, Einzelthemen und manuelle Titel besitzen ihre Loop-/Weiter-
	# Policy hier im MusicManager. Der Replayer muss deshalb ein echtes
	# Songende melden, statt denselben MOD intern unsichtbar neu zu starten.
	_mod.loop_song = false
	_mod.finished.connect(_on_track_finished)
	add_child(_mod)
	_apply_volume()
	if not TimeManager.year_changed.is_connected(_on_year_changed):
		TimeManager.year_changed.connect(_on_year_changed)
	reset()


## Musik-Lautstärke setzen (linear 0..1). Wirkt sofort auf den laufenden Titel.
## Zugriff auf den nativen Player (Tracker-UI: Pattern-Hex, Kanalpegel).
func native_player() -> ModPlayer:
	return _mod


func set_music_volume(linear: float) -> void:
	_music_db = -60.0 if linear <= 0.001 else linear_to_db(clampf(linear, 0.0, 1.0))
	_apply_volume()


func _apply_volume() -> void:
	if _mod != null and _mod._player != null:
		_mod._player.volume_db = _music_db


func _load_catalog() -> void:
	tracks = []
	themes = {}
	_track_by_id.clear()
	_club_tracks.clear()
	_tracks_by_channel.clear()
	_location_playlist_cache.clear()
	var file := FileAccess.open("res://data/music.json", FileAccess.READ)
	if file == null:
		push_error("music.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("music.json ist kein gueltiges JSON-Objekt!")
		return
	var data := parsed as Dictionary
	themes = data.get("themes", {})
	for raw_track: Variant in data.get("tracks", []):
		if not raw_track is Dictionary:
			continue
		var entry := raw_track as Dictionary
		var id := str(entry.get("id", "")).strip_edges()
		if id.is_empty():
			push_warning("MusicManager: Katalogeintrag ohne ID uebersprungen.")
			continue
		if _track_by_id.has(id):
			push_warning("MusicManager: doppelte Track-ID '%s' uebersprungen." % id)
			continue
		tracks.append(entry)
		_track_by_id[id] = entry
		if str(entry.get("pool", "")) == "club":
			_club_tracks.append(entry)
		for raw_channel: Variant in entry.get("channels", []):
			var channel := str(raw_channel)
			if not _tracks_by_channel.has(channel):
				_tracks_by_channel[channel] = []
			(_tracks_by_channel[channel] as Array).append(entry)
	_soundtrack_by_file.clear()
	var soundtrack: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/soundtrack.json"))
	if soundtrack is Dictionary:
		for entry: Dictionary in soundtrack.get("tracks", []):
			_soundtrack_by_file[str(entry.get("file", ""))] = entry
	_user_mods.scan(tracks)


func reset() -> void:
	stop()
	owned.clear()
	music_changed.emit()


# --------------------------------------------------------------- Katalog

func track(id: String) -> Dictionary:
	return _track_by_id.get(id, _user_mods.extras.get(id, {}))


## The catalog describes collectible historical slots. Playback credits always
## describe the file actually playing, including a fallback after file removal.
func playback_track(id: String) -> Dictionary:
	if id == current and not _playing_record.is_empty():
		return _playing_record.duplicate()
	if _user_mods.extras.has(id):
		return _user_mods.extras[id].duplicate()
	if _user_mods.matches.has(id):
		return _user_mods.matches[id].duplicate()
	return _fallback_track(id)


func _fallback_track(id: String) -> Dictionary:
	var slot := track(id)
	if slot.is_empty():
		return {}
	var path := str(slot.get("file", ""))
	var result: Dictionary = _soundtrack_by_file.get(path, {}).duplicate()
	# No historical catalog author is ever attributed to replacement music.
	if not result.is_empty():
		result["fallback"] = true
		result["slot_title"] = str(slot.get("title", ""))
	return result


func mod_folder() -> String:
	return ProjectSettings.globalize_path(UserMods.DIRECTORY)


func mod_library_status() -> Dictionary:
	return _user_mods.report()


func rescan_mods() -> Dictionary:
	var resume := current if is_playing() else ""
	var result := _user_mods.scan(tracks)
	if not resume.is_empty():
		if not _start(resume):
			stop()
	music_changed.emit()
	return result


func owned_tracks() -> Array:
	var result := tracks.filter(func(t: Dictionary) -> bool: return owned.has(t.get("id", "")))
	result.append_array(_user_mods.extras.values())
	return result


func has_track(id: String) -> bool:
	return owned.has(id)


## Computerclub-Bibliothek: sammelbare Mods, die es im aktuellen Jahr schon
## gibt und die man noch nicht hat (Living Timeline).
func club_library() -> Array:
	return _club_tracks.filter(func(t: Dictionary) -> bool:
		return int(t.get("year", 3000)) <= TimeManager.year \
			and not owned.has(t.get("id", "")))


## Noch nicht gesammelte Tracks eines Verbreitungskanals ("bbs" | "flea" | …).
## Tracks ohne channels-Feld gelten nur für den Club (Alt-Bestand).
func tracks_on(channel: String) -> Array:
	var channel_tracks: Array = _tracks_by_channel.get(channel, [])
	return channel_tracks.filter(func(t: Dictionary) -> bool:
		return int(t.get("year", 3000)) <= TimeManager.year \
			and not owned.has(t.get("id", "")))


## Einen Mod in die Sammlung übernehmen (am Club auf Diskette kopiert).
func collect(id: String) -> bool:
	if track(id).is_empty() or owned.has(id):
		return false
	owned.append(id)
	music_changed.emit()
	return true


# --------------------------------------------------------------- Wiedergabe

## Manuell auf der Anlage abspielen (nur Besitz). Beendet ggf. das Ambient-Thema.
func play(id: String) -> bool:
	if not owned.has(id) and not _user_mods.extras.has(id):
		return false
	_ambient = false
	_set_source("amiga", "room", "AMIGA")
	return _start(id)


## Vorhören am Club (auch ohne Besitz) — hilft bei der Auswahl.
func preview(id: String) -> bool:
	_ambient = false
	var location := str(GameManager.current_location_id)
	_set_source("preview", location, "VORHÖREN · %s" % _location_label(location))
	return _start(id)


## Titelmelodie fürs Hauptmenü. Läuft als Einzelthema in Dauerschleife (wie ein
## Ortsthema, daher `_ambient` = true: kein „erster MOD"-Meilenstein, und der
## Spieler muss den Track nicht besitzen). Datengesteuert: bevorzugt einen Track
## mit `"title": true`, sonst den benannten Klassiker, sonst ein start-Highlight.
func title_track_id() -> String:
	for t in tracks:
		# `title` ist bereits der Songname (String). Das alte Flag kollidierte mit
		# diesem Feld und versuchte einen String per bool()-Konstruktor zu lesen.
		if t.get("is_title", false) == true or (t.get("title", null) is bool and t.get("title") == true):
			return str(t.get("id", ""))
	if not track("space_debris").is_empty():
		return "space_debris"
	for t in tracks:
		if t.get("pool", "") == "start" and bool(t.get("highlight", false)):
			return str(t.get("id", ""))
	return ""


func play_title() -> bool:
	var id := title_track_id()
	if id == "":
		return false
	_ambient = true
	_loc_playlist = []
	_loc_index = 0
	_set_source("title", "title", "TITELBILD")
	return _start(id)


func _start(id: String) -> bool:
	_playing_record = {}
	var t := playback_track(id)
	var path := str(t.get("file", ""))
	var valid := not t.is_empty()
	if valid and bool(t.get("user_mod", false)):
		valid = bool(UserMods.Parser.inspect(path).get("ok", false))
	var loaded := valid and _mod.load_mod(path)
	if not loaded and bool(t.get("user_mod", false)):
		# A file can disappear or change after a scan; retry the original score.
		t = _fallback_track(id)
		loaded = not t.is_empty() and _mod.load_mod(str(t.get("file", "")))
	if not loaded:
		_mod.stop()
		current = ""
		now_playing.emit("")
		music_changed.emit()
		_emit_presentation()
		return false
	_mod.play()
	_playing_record = t.duplicate()
	current = id
	now_playing.emit(id)
	music_changed.emit()
	_emit_presentation()
	if not _ambient:
		MemoryManager.record_once("first_mod_song")   # Meilenstein: erster bewusst gehörter MOD
	return true


func stop() -> void:
	if _mod != null:
		_mod.stop()
	current = ""
	_playing_record = {}
	_ambient = false
	_set_source("", "", "")
	now_playing.emit("")
	music_changed.emit()
	_emit_presentation()


## Nur die vom Spieler auf dem AMIGA gestartete MOD stoppen (z.B. beim Strom-Aus) —
## das Orts-Ambiente (_ambient) läuft weiter, das kommt nicht aus dem Rechner.
func stop_disk_playback() -> void:
	if is_playing() and not _ambient:
		stop()


func is_playing() -> bool:
	return current != "" and _mod != null and _mod.playing


## Einheitlicher Wiedergabestatus fuer das HUD. Neben dem nativen MOD-Replayer
## koennen eigenstaendige Spiele ihren Music-Bus-Player anmelden; der Saison-
## Animator reagiert dadurch auf jede tatsaechlich laufende Musikquelle.
func is_any_music_playing() -> bool:
	return _external_is_playing() or is_playing()


func presentation_state() -> Dictionary:
	# Ein gestartetes Amiga-Spiel bleibt die aktive Präsentation, auch wenn
	# dessen Paula-Loop pausiert oder Audio global stumm ist. Das Spiel meldet
	# sich beim Öffnen an und beim Schließen explizit wieder ab.
	if _external_is_registered():
		var external_player: AudioStreamPlayer = _external_player.get_ref() as AudioStreamPlayer
		return {
			"active": true, "playing": external_player.playing,
			"tracker": false, "track_id": "external",
			"title": _external_title, "artist": "", "source_kind": "external",
			"source_id": "external", "source_label": _external_source,
			"ambient": false,
		}
	var data := playback_track(current) if is_playing() else {}
	return {
		"active": is_playing(), "playing": is_playing(),
		"tracker": is_playing(), "track_id": current,
		"title": str(data.get("title", "")),
		# Der importierte MOD-Katalog verwendet historisch überwiegend
		# ``author``. Die HUD-Präsentation erwartete dagegen nur ``artist`` und
		# zeigte dadurch bei generisch benannten Modulen wie „Game 2“ keinerlei
		# hilfreichen Urheberkontext.
		"artist": str(data.get("artist", data.get("author", ""))),
		"source_kind": _source_kind, "source_id": _source_id,
		"source_label": _source_label, "ambient": _ambient,
		"fallback": bool(data.get("fallback", false)),
		"user_mod": bool(data.get("user_mod", false)),
	}


func present_external(player: AudioStreamPlayer, title: String, source: String) -> void:
	if player == null:
		return
	_external_player = weakref(player)
	_external_title = title.strip_edges() if title.strip_edges() != "" else "MUSIKSIGNAL"
	_external_source = source.strip_edges() if source.strip_edges() != "" else "SPIEL"
	_emit_presentation()


func clear_external(player: AudioStreamPlayer = null) -> void:
	if _external_player == null:
		return
	var registered: Object = _external_player.get_ref()
	if player != null and registered != player:
		return
	_external_player = null
	_external_title = ""
	_external_source = ""
	_emit_presentation()


func _external_is_playing() -> bool:
	if not _external_is_registered():
		return false
	var player: AudioStreamPlayer = _external_player.get_ref() as AudioStreamPlayer
	return player.playing


func _external_is_registered() -> bool:
	if _external_player == null:
		return false
	var player: Object = _external_player.get_ref()
	return player is AudioStreamPlayer and is_instance_valid(player)


func _set_source(kind: String, id: String, label: String) -> void:
	_source_kind = kind
	_source_id = id
	_source_label = label


func _emit_presentation() -> void:
	presentation_changed.emit(presentation_state())


func _location_label(id: String) -> String:
	if id == "":
		return "ORT"
	var label := GameManager.location_name(id)
	return label.to_upper() if label != "" else id.replace("_", " ").to_upper()


func play_next() -> void:
	var list := owned_tracks()
	if list.is_empty():
		stop()
		return
	var idx := 0
	for i in list.size():
		if list[i].get("id", "") == current:
			idx = i + 1
			break
	play(list[idx % list.size()].get("id", ""))


func _on_track_finished() -> void:
	if _ambient:
		if _source_kind == "location" and not _loc_playlist.is_empty():
			# durch die Orts-Playlist rotieren (3–5 Songs je Ort)
			_loc_index = (_loc_index + 1) % _loc_playlist.size()
			if not _start_location_playlist(_source_id, _loc_playlist, _loc_index):
				stop()
		else:
			# Titelbild und andere Einzelthemen loopen kontrolliert.
			if current.is_empty() or not _start(current):
				stop()
	elif _source_kind == "amiga":
		play_next()
	else:
		# Vorhoeren ist ein einzelner Titel. Ein Ende darf nicht unbemerkt in
		# die private Sammlung springen.
		stop()


# --------------------------------------------------------------- Standort-Musik

## Die im aktuellen Spieljahr hoerbare Playlist eines Ortes.
##
## Der Ortseintrag ist ein POOL (data/music.json "themes"), aus dem nur die
## bereits erschienenen Stuecke gespielt werden. Dadurch waechst die Musik eines
## Ortes ueber die zehn Spieljahre mit: 1990 laeuft dort anderes als 1996.
##
## Vorher war der Eintrag eine feste Liste ohne Jahresfilter — 70 von 88
## Zuordnungen waren dadurch vor ihrem Erscheinungsjahr hoerbar, und kein Ort
## bekam jemals neue Musik.
func location_playlist(id: String, year := -1) -> Array:
	var limit := year if year > 0 else TimeManager.year
	var cache_key := "%s:%d" % [id, limit]
	if _location_playlist_cache.has(cache_key):
		return (_location_playlist_cache[cache_key] as Array).duplicate()
	var entry: Variant = themes.get(id, "")
	var pool: Array = []
	if entry is Array:
		pool = entry
	elif entry is String and entry != "":
		pool = [entry]
	if pool.is_empty():
		return []
	var available: Array = []
	for track_id: Variant in pool:
		var entry_data := track(str(track_id))
		# Unbekannte IDs fliegen raus, statt still einen stummen Slot zu belegen.
		if entry_data.is_empty():
			continue
		if int(entry_data.get("year", 3000)) <= limit:
			available.append(track_id)
	if not available.is_empty():
		# Ein Ort soll eine erkennbare Klangidentitaet haben, keine Jukebox: es
		# laufen immer hoechstens PLAYLIST_SIZE Stuecke. Gespielt werden die
		# JUENGSTEN verfuegbaren, wodurch die Auswahl ueber die Dekade wandert
		# statt bloss anzuwachsen — alte Stuecke treten ab, neue ruecken nach.
		available.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ya := int(track(str(a)).get("year", 0))
			var yb := int(track(str(b)).get("year", 0))
			if ya != yb:
				return ya > yb
			return str(a) < str(b))
		var newest_year := int(track(str(available[0])).get("year", 0))
		if limit >= ARCHIVE_ROTATION_YEAR and newest_year < limit \
				and available.size() > PLAYLIST_SIZE:
			# Zyklisches Archivfenster: 1998 und 1999 bekommen eine neue
			# Kuratierung, aber sämtliche Titel behalten ihr belegtes/altes Jahr.
			var archive_offset := posmod(limit - newest_year, available.size())
			var rotated: Array = []
			for index in available.size():
				rotated.append(available[(archive_offset + index) % available.size()])
			available = rotated
		if available.size() > PLAYLIST_SIZE:
			available = available.slice(0, PLAYLIST_SIZE)
		# Stabile Reihenfolge fuer die Rotation (aeltestes zuerst).
		available.reverse()
		_location_playlist_cache[cache_key] = available.duplicate()
		return available
	# Kein Zukunfts-MOD als Notnagel: Ein spaeter eroeffnender Ort muss in den
	# Daten zum Eroeffnungsjahr einen echten Track besitzen.
	_location_playlist_cache[cache_key] = []
	return []


## Beim Ortswechsel: passendes Ambient-Thema starten — oder (Zimmer u. a.) die
## Ambient-Musik beenden, sodass dort die Anlage das Sagen hat.
func enter_location(id: String) -> void:
	var playlist := location_playlist(id)

	if not playlist.is_empty():
		# Nicht neu starten, wenn dieselbe Playlist schon läuft.
		if _ambient and _loc_playlist == playlist and is_playing():
			return
		var start_index := randi() % playlist.size()
		if not _start_location_playlist(id, playlist, start_index):
			stop()
	elif _source_kind == "location" or _source_kind == "preview" \
			or (_source_kind == "amiga" and id != "room"):
		# Standortmusik, Vorhoeren und die heimische Anlage sind physische
		# Quellen. Sie duerfen nicht unbemerkt in einen anderen Ort
		# "mitreisen". Nur ein bereits im Zimmer laufender eigener MOD bleibt
		# beim erneuten Zimmeraufbau erhalten.
		_loc_playlist = []
		stop()


## Startet eine Ortsliste ab einem gewuenschten Index und probiert bei einer
## defekten Datei die weiteren Eintraege. Ein einzelner Importfehler darf einen
## ganzen Ort nicht stumm schalten.
func _start_location_playlist(id: String, playlist: Array, start_index: int) -> bool:
	if playlist.is_empty():
		return false
	_loc_playlist = playlist.duplicate()
	_ambient = true
	_set_source("location", id, _location_label(id))
	for offset in playlist.size():
		_loc_index = posmod(start_index + offset, playlist.size())
		if _start(str(playlist[_loc_index])):
			_emit_presentation()
			return true
	return false


func _on_year_changed(_year: int) -> void:
	# Bleibt der Spieler ueber Silvester an einem Musikort, wird die neue
	# Jahrgangsauswahl trotzdem sofort aktiv.
	if _source_kind == "location":
		enter_location(_source_id)


# --------------------------------------------------------------- Speichern

func to_dict() -> Dictionary:
	return {"owned": owned.duplicate()}


func from_dict(d: Dictionary) -> void:
	var restored: Array = []
	for raw_id: Variant in d.get("owned", []):
		var id := str(raw_id)
		if _track_by_id.has(id) and id not in restored:
			restored.append(id)
	owned = restored
	if _source_kind == "amiga" and current not in owned:
		stop()
	music_changed.emit()
