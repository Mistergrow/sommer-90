extends Node
## BBSScene — die lebendige Szene-Schicht der Mailboxen (D/E, AAA-Ausbau).
##
## Zwei Quellen machen die Boards lebendig:
##  1) NPC-POSTS unter PSEUDONYM: Die Spielfiguren sind in den Boards unterwegs
##     (Daniel = DATAWOLF, Mike = JOYRIDER …). Ihre Beiträge entstehen aus ihren
##     NARRATIVE-Zeilen-Pools → automatisch jahres-/faktenrichtig, null Duplikatpflege.
##  2) VIRTUELLE GRUPPEN (data/bbs_scene.json): fiktive Szene-Crews (RADIANT,
##     VECTORLORDS …) posten Releases, Compo-Ansagen, Flamewars — year-/fakten-gated.
## Dazu: Oneliner-WALL + „Wer ist online"-Liste, deterministisch pro Board+Tag.

const CONFIG := "res://data/bbs_scene.json"
const ARCHIVE_CONFIG := "res://data/bbs_archive.json"
const MUSIC_CONFIG := "res://data/music.json"
const UNRESOLVED_ARTIST := "CREDIT UNGEKLAERT"

# Nur Varianten zusammenfuehren, die entweder in den Archivquellen belegt oder
# im lokalen Katalog eindeutig als gekuerzte Schreibweise desselben Credits
# erkennbar sind. Aehnliche, aber nicht belegte Handles bleiben getrennt.
const ARTIST_ALIASES := {
	"4-mat": "4-MAT",
	"4mat": "4-MAT",
	"firefox": "FIREFOX",
	"jogeir": "JOGEIR LILJEDAHL",
	"jogeir liljedahl": "JOGEIR LILJEDAHL",
	"dr. awesome": "DR. AWESOME",
	"dr_aweso": "DR. AWESOME",
	"a_brimbl": "ALLISTER BRIMBLE",
	"allister brimble": "ALLISTER BRIMBLE",
	"lizardkg": "LIZARDKING",
	"lizardking": "LIZARDKING",
	"t_wright": "TIM WRIGHT",
	"tim wright": "TIM WRIGHT",
	"virgill": "VIRGILL",
}

var personas: Dictionary = {}        # npc_id -> Handle
var _persona_until: Dictionary = {}  # npc_id -> letztes Jahr (Sven zieht weg)
var _groups: Array = []
var _wall: Array = []
var _archive_sources: Dictionary = {}
var _archive_live_threads: Array = []
var _archive_echoes: Array = []
var _catalog_source_ids: Array = []
var _artist_catalog: Array = []


func _ready() -> void:
	if FileAccess.file_exists(CONFIG):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if d is Dictionary:
			personas = d.get("personas", {})
			_persona_until = d.get("persona_until", {})
			_groups = d.get("groups", [])
			_wall = d.get("wall", [])
	if FileAccess.file_exists(ARCHIVE_CONFIG):
		var archive_data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(ARCHIVE_CONFIG))
		if archive_data is Dictionary:
			_archive_sources = archive_data.get("sources", {})
			_archive_live_threads = archive_data.get("live_threads", [])
			_archive_echoes = archive_data.get("archive_echoes", [])
			_catalog_source_ids = archive_data.get("catalog_source_ids", [])
	_build_artist_catalog()


## Einzige zentrale Aufloesung fuer sichtbare Szene-Namen. Klar-/NPC-Namen
## duerfen nie als Fallback in Intros oder Upload-Credits rutschen: unbekannte
## Actor-IDs bekommen deshalb ein stabiles, rein technisches ANON-Handle.
func handle_for_actor(actor_id: String) -> String:
	var handle := str(personas.get(actor_id, "")).strip_edges()
	if handle != "":
		return handle
	return "ANON-%04X" % (hash(actor_id) & 0xffff)


## Abwaertskompatibler Name fuer bestehende BBS-Aufrufer.
func pseudonym(npc_id: String) -> String:
	return handle_for_actor(npc_id)


## Ist ein Text ein in der zentralen Szene-Datei eingetragenes Handle?
## Spieler-Handles werden absichtlich nicht hier hinein geraten; sie liegen im
## SceneReleaseManager und werden als validierter handle_snapshot gespeichert.
func is_known_handle(handle: String) -> bool:
	var wanted := handle.strip_edges().to_upper()
	if wanted == "":
		return false
	for value in personas.values():
		if str(value).to_upper() == wanted:
			return true
	for group in _groups:
		for member in group.get("members", []):
			if str(member).to_upper() == wanted:
				return true
	return false


func group_names() -> Array:
	var out: Array = []
	for group in _groups:
		var group_name := str(group.get("name", "")).strip_edges()
		if group_name != "":
			out.append(group_name)
	return out


## Vollstaendige Reservierungsliste fuer Handle-Wahl und Credits. Auch diese
## Liste stammt ausschliesslich aus data/bbs_scene.json.
func all_handles() -> Array:
	var out: Array = []
	for value in personas.values():
		var handle := str(value).strip_edges()
		if handle != "" and handle not in out:
			out.append(handle)
	for group in _groups:
		for value in group.get("members", []):
			var handle := str(value).strip_edges()
			if handle != "" and handle not in out:
				out.append(handle)
	return out


## Ist die Persona dieses Jahr noch aktiv? (Sven verschwindet mit dem Umzug.)
func _persona_active(npc_id: String) -> bool:
	if not personas.has(npc_id):
		return false
	if _persona_until.has(npc_id) and TimeManager.year > int(_persona_until[npc_id]):
		return false
	return true


func _rng(board_id: String, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%d/%d" % [board_id, TimeManager.day_counter, salt])
	return rng


## Szene-Nachrichten fürs Brett (Board + Tag deterministisch): 2 Gruppen-Posts
## + 2–3 NPC-Posts unter Pseudonym. Format wie BBS-Messages (from/subject/body).
func posts_for(board_id: String) -> Array:
	var out: Array = []
	var rng := _rng(board_id, 1)
	# Gruppen-Posts (Jahr-/Fakten-Fenster)
	var pool: Array = []
	for g in _groups:
		for p in g.get("posts", []):
			if _post_ok(p):
				var e: Dictionary = (p as Dictionary).duplicate()
				e["group"] = g.get("name", "?")
				e["group_id"] = g.get("id", "group")
				pool.append(e)
	for _i in mini(2, pool.size()):
		var idx := rng.randi_range(0, pool.size() - 1)
		var p: Dictionary = pool[idx]
		pool.remove_at(idx)
		var group_id := str(p.get("group_id", "group"))
		var post_id := str(p.get("id", "post"))
		out.append({
			"from": "%s / %s" % [str(p.get("author", "?")), str(p.get("group", ""))],
			"subject": Loc.t("bbs.%s.%s.subject" % [group_id, post_id], str(p.get("subject", ""))),
			"body": Loc.t("bbs.%s.%s.body" % [group_id, post_id], str(p.get("body", ""))),
		})
	# NPC-Posts: gültige Narrative-Zeile unter Pseudonym (keine mark_said —
	# das Brett „zitiert" die Figuren, ohne ihre Gespräche zu verbrauchen).
	var handles: Array = personas.keys().filter(_persona_active)
	for _j in 3:
		if handles.is_empty():
			break
		var npc: String = handles[rng.randi_range(0, handles.size() - 1)]
		handles.erase(npc)
		var lines: Array = NarrativeManager.lines.get(npc, [])
		var valid: Array = lines.filter(func(l: Dictionary) -> bool:
			return NarrativeManager.line_ok(npc, l) and not l.has("dialogue"))
		if valid.is_empty():
			continue
		var line: Dictionary = valid[rng.randi_range(0, valid.size() - 1)]
		out.append({
			"from": pseudonym(npc),
			"subject": Loc.t("sys.bbs_scene.board_subject", "(Brett %d)") % rng.randi_range(1, 5),
			"body": str(line.get("text", "")),
		})
	return out


func _post_ok(p: Dictionary) -> bool:
	var y := TimeManager.year
	if p.has("from") and y < int(p["from"]):
		return false
	if p.has("to") and y > int(p["to"]):
		return false
	for f in p.get("needs", []):
		if not NarrativeManager.fact_true(str(f)):
			return false
	return true


## Quellennahe Rekonstruktionen fuer das gerade angerufene Board. Alle Autoren
## sind fiktive Handles; reale Musiker erscheinen ausschliesslich im getrennten
## ARCHIV-ECHO. Die deterministische Auswahl verhindert Flackern beim Zurueck-
## und Wiederaufrufen der Nachrichtenliste.
func archive_live_posts_for(board_id: String) -> Array:
	var pool: Array = []
	for raw in _archive_live_threads:
		if raw is not Dictionary:
			continue
		var entry := raw as Dictionary
		if not _post_ok(entry):
			continue
		var board_ids: Array = entry.get("board_ids", [])
		if not board_ids.is_empty() and board_id not in board_ids:
			continue
		pool.append(entry)
	var rng := _rng(board_id, 41)
	var out: Array = []
	for _i in mini(2, pool.size()):
		var index := rng.randi_range(0, pool.size() - 1)
		out.append(_localized_archive_entry(pool[index], "live", "reconstructed"))
		pool.remove_at(index)
	return out


## Spaetere Interviews und Archivbefunde. Diese Eintraege sind dokumentarische
## Rueckblicke und werden nie unter die zeitgenoessischen Live-Posts gemischt.
func archive_echoes() -> Array:
	var out: Array = []
	for raw in _archive_echoes:
		if raw is Dictionary:
			out.append(_localized_archive_entry(
				raw as Dictionary, "echo", "archive_echo"))
	return out


func archive_source_count() -> int:
	return _archive_sources.size()


## Vollstaendiges Register aller physisch vorhandenen und damit im Spiel
## abspielbaren MOD-Dateien. Ein fehlendes Interview entfernt weder Musiker
## noch Track; es aendert ausschliesslich den sichtbaren Quellenstatus.
func playable_artist_catalog() -> Array:
	return _artist_catalog.duplicate(true)


func artist_catalog_track_count() -> int:
	var count := 0
	for artist in _artist_catalog:
		count += int((artist as Dictionary).get("track_count", 0))
	return count


func artist_catalog_sourced_count() -> int:
	var count := 0
	for artist in _artist_catalog:
		if bool((artist as Dictionary).get("sourced", false)):
			count += 1
	return count


func artist_catalog_unresolved_track_count() -> int:
	for artist in _artist_catalog:
		var record := artist as Dictionary
		if bool(record.get("unresolved", false)):
			return int(record.get("track_count", 0))
	return 0


func artist_catalog_sources() -> Array:
	return archive_sources_for(_catalog_source_ids)


func _canonical_artist(raw_author: String) -> String:
	var cleaned := raw_author.strip_edges()
	var lookup := cleaned.to_lower()
	if lookup.is_empty() or lookup == "unknown":
		return UNRESOLVED_ARTIST
	if ARTIST_ALIASES.has(lookup):
		return str(ARTIST_ALIASES[lookup])
	return cleaned.to_upper()


## MusicManager (frueherer Autoload) haelt music.json bereits geparst; nur ohne
## ihn — etwa in isolierten Werkzeugen — wird die 480-KB-Datei selbst gelesen.
func _music_catalog_tracks() -> Array:
	var music := get_node_or_null("/root/MusicManager")
	var loaded: Variant = music.get("tracks") if music != null else null
	if loaded is Array and not (loaded as Array).is_empty():
		return loaded
	if not FileAccess.file_exists(MUSIC_CONFIG):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_CONFIG))
	return (parsed as Dictionary).get("tracks", []) if parsed is Dictionary else []


func _build_artist_catalog() -> void:
	_artist_catalog.clear()
	var by_artist: Dictionary = {}
	for raw in _music_catalog_tracks():
		if raw is not Dictionary:
			continue
		var track := raw as Dictionary
		var file_path := str(track.get("file", ""))
		if file_path.is_empty() or not FileAccess.file_exists(file_path):
			continue
		var raw_author := str(track.get("author", "")).strip_edges()
		var artist_name := _canonical_artist(raw_author)
		if not by_artist.has(artist_name):
			by_artist[artist_name] = {
				"name": artist_name,
				"aliases": [],
				"tracks": [],
				"first_year": 9999,
				"last_year": 0,
				"verified_count": 0,
				"review_count": 0,
				"unresolved": artist_name == UNRESOLVED_ARTIST,
			}
		var record := by_artist[artist_name] as Dictionary
		var aliases := record.get("aliases", []) as Array
		var visible_alias := raw_author if not raw_author.is_empty() else "[LEERER CREDIT]"
		if visible_alias not in aliases:
			aliases.append(visible_alias)
		var year := int(track.get("year", 0))
		var verified := not bool(track.get("needs_verification", true))
		var tracks := record.get("tracks", []) as Array
		tracks.append({
			"id": str(track.get("id", "")),
			"title": str(track.get("title", track.get("id", "?"))),
			"year": year,
			"file": file_path,
			"raw_author": raw_author,
			"verified": verified,
		})
		if year > 0:
			record["first_year"] = mini(int(record.get("first_year", 9999)), year)
			record["last_year"] = maxi(int(record.get("last_year", 0)), year)
		if verified:
			record["verified_count"] = int(record.get("verified_count", 0)) + 1
		else:
			record["review_count"] = int(record.get("review_count", 0)) + 1
		by_artist[artist_name] = record

	for artist_name in by_artist:
		var record := by_artist[artist_name] as Dictionary
		var echo_indexes: Array = []
		var source_ids: Array = []
		for echo_index in _archive_echoes.size():
			var raw_echo: Variant = _archive_echoes[echo_index]
			if raw_echo is not Dictionary:
				continue
			var echo := raw_echo as Dictionary
			if str(echo.get("entry_type", "")) != "artist":
				continue
			if _canonical_artist(str(echo.get("author", ""))) != artist_name:
				continue
			echo_indexes.append(echo_index)
			for source_id in echo.get("source_ids", []):
				if source_id not in source_ids:
					source_ids.append(source_id)
		var tracks := record.get("tracks", []) as Array
		tracks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var year_compare := int(a.get("year", 0)) - int(b.get("year", 0))
			if year_compare != 0:
				return year_compare < 0
			return str(a.get("title", "")).naturalnocasecmp_to(
				str(b.get("title", ""))) < 0)
		var aliases := record.get("aliases", []) as Array
		aliases.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str(a).naturalnocasecmp_to(str(b)) < 0)
		record["track_count"] = tracks.size()
		record["echo_indexes"] = echo_indexes
		record["source_ids"] = source_ids
		record["sourced"] = not echo_indexes.is_empty()
		if int(record.get("first_year", 9999)) == 9999:
			record["first_year"] = 0
		_artist_catalog.append(record)

	_artist_catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_unresolved := bool(a.get("unresolved", false))
		var b_unresolved := bool(b.get("unresolved", false))
		if a_unresolved != b_unresolved:
			return not a_unresolved
		return str(a.get("name", "")).naturalnocasecmp_to(
			str(b.get("name", ""))) < 0)


func archive_sources_for(source_ids: Array) -> Array:
	var out: Array = []
	for value in source_ids:
		var source_id := str(value)
		if not _archive_sources.has(source_id):
			continue
		var source := (_archive_sources[source_id] as Dictionary).duplicate(true)
		source["id"] = source_id
		source["note"] = Loc.t(
			"bbsarchive.source.%s.note" % source_id,
			str(source.get("note", "")))
		out.append(source)
	return out


func _localized_archive_entry(
		entry: Dictionary, domain: String, kind: String) -> Dictionary:
	var localized := entry.duplicate(true)
	var entry_id := str(entry.get("id", "entry"))
	localized["subject"] = Loc.t(
		"bbsarchive.%s.%s.subject" % [domain, entry_id],
		str(entry.get("subject", "")))
	localized["body"] = Loc.t(
		"bbsarchive.%s.%s.body" % [domain, entry_id],
		str(entry.get("body", "")))
	localized["kind"] = kind
	localized["archive_id"] = entry_id
	var group := str(entry.get("group", "")).strip_edges()
	localized["from"] = str(entry.get("author", "?")) \
		if group.is_empty() else "%s / %s" % [entry.get("author", "?"), group]
	return localized


## Oneliner-Wall: 4 Shouts, deterministisch pro Board+Tag, jahresgefiltert.
func wall_for(board_id: String) -> Array:
	var rng := _rng(board_id, 2)
	var valid: Array = _wall.filter(_post_ok)
	var out: Array = []
	for _i in mini(4, valid.size()):
		var idx := rng.randi_range(0, valid.size() - 1)
		var entry := valid[idx] as Dictionary
		var source := str(entry.get("text", ""))
		out.append(Loc.t("bbs.wall.%s.text" % str(entry.get("id", "wall")), source))
		valid.remove_at(idx)
	return out


## „Wer ist online": Handles von NPC-Personas + Gruppen-Membern (2–5 Nutzer).
func users_for(board_id: String) -> Array:
	var rng := _rng(board_id, 3)
	var all: Array = []
	for npc in personas:
		if _persona_active(str(npc)):
			all.append(pseudonym(str(npc)))
	for g in _groups:
		for m in g.get("members", []):
			all.append(str(m))
	var out: Array = []
	var n := rng.randi_range(2, 5)
	for _i in n:
		if all.is_empty():
			break
		var idx := rng.randi_range(0, all.size() - 1)
		out.append(all[idx])
		all.remove_at(idx)
	return out
