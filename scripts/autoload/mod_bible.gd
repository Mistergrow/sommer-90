extends Node
## MODBible — die Musik-Kultur-Wissensbasis von SOMMER '90 (permanent, ENGINE
## FIRST, wie die Software Bible). Lädt Künstler/Gruppen/Tracks aus
## data/mod_bible/ und liefert (a) Abfragen und (b) authentische Szene-„Flavor"-
## Zeilen für Computerclub, Mailbox/BBS, Flohmarkt und Freund-Empfehlungen.
##
## WICHTIG: enthält NUR bestätigte Namen/Zuordnungen; unbekannte Metadaten sind
## needs_verification. Die Flavor-Zeilen nutzen echte Namen/Titel als kulturelle
## Farbe (kein Anspruch auf konkrete Release-Fakten). Validierung: tests/mod_bible_check.gd.

const DIR := "res://data/mod_bible/"

var artists: Dictionary = {}
var groups: Dictionary = {}
var tracks: Dictionary = {}
var styles: Array = []
var trackers: Array = []


func _ready() -> void:
	var a := _load("artists.json")
	artists = a.get("artists", {})
	styles = a.get("styles", [])
	trackers = a.get("trackers", [])
	groups = _load("groups.json").get("groups", {})
	tracks = _load("tracks.json").get("tracks", {})
	# Kultur-Atmosphäre: beim Betreten des Clubs eine Szene-Zeile in den Ticker.
	GameManager.location_changed.connect(_on_location_changed)


func _on_location_changed(id: String) -> void:
	if id == "computer_club":
		UIManager.toast(club_now_playing())


func _load(file: String) -> Dictionary:
	var f := FileAccess.open(DIR + file, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# ------------------------------------------------------------- Abfragen
func artist(id: String) -> Dictionary:
	return artists.get(id, {})


func group(id: String) -> Dictionary:
	return groups.get(id, {})


func track(id: String) -> Dictionary:
	return tracks.get(id, {})


func artist_name(id: String) -> String:
	return str(artists.get(id, {}).get("name", id))


func legends() -> Array:
	return artists.keys().filter(func(k: String) -> bool: return artists[k].get("tier", "") == "legend")


## Tracks, die an einem Kanal (club|bbs|flea|magazine|friend_rec) auftauchen können
## und (year==0 = unbekannt/immer) bis zum aktuellen Jahr existieren.
func tracks_at(channel: String) -> Array:
	return tracks.keys().filter(func(k: String) -> bool:
		var t: Dictionary = tracks[k]
		var y := int(t.get("year", 0))
		return bool(t.get("availability", {}).get(channel, false)) and (y == 0 or y <= TimeManager.year))


func _rand(list: Array) -> String:
	return str(list[randi() % list.size()]) if not list.is_empty() else ""


# ------------------------------------------------------------- Szene-Flavor
## Authentische Kultur-Zeilen (echte Namen/Titel als Farbe). Für RumorManager,
## NPC-Dialoge, Computerclub-„läuft gerade", Flohmarkt-Diskettenlabels, BBS.

## Was heute im Computerclub läuft.
func club_now_playing() -> String:
	var artist_label := artist_name(_rand(legends()))
	return "Im Computerclub läuft heute nur %s." % artist_label if artist_label != "" else ""


## Neuer Fund auf der Mailbox (BBS).
func mailbox_find() -> String:
	var artist_label := artist_name(_rand(legends()))
	return "Auf der Mailbox ist ein neuer %s-Track aufgetaucht." % artist_label if artist_label != "" else ""


## Diskettenlabel auf dem Flohmarkt.
func flea_disk_label() -> String:
	var tid := _rand(tracks_at("flea"))
	if tid == "":
		return ""
	return "Eine Diskette mit der Aufschrift »%s«." % str(tracks[tid].get("title", tid))


## Freund-Empfehlung (Name des Freundes vom Aufrufer einsetzbar über %s).
func friend_recommendation() -> String:
	var artist_label := artist_name(_rand(legends()))
	return "Kennst du schon %s? Absoluter Kult." % artist_label if artist_label != "" else ""


## Eine zufällige Szene-Zeile (für den INFOS-Ticker o. Ä.).
func scene_line() -> String:
	var opts := [club_now_playing(), mailbox_find(), flea_disk_label(), friend_recommendation()]
	opts = opts.filter(func(s: String) -> bool: return s != "")
	return _rand(opts)
