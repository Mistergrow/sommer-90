extends Node
## SoftwareBible — der permanente Motor über der Software-Content-Bibel
## (Content/Software/A-Z/*.json). EINZIGE Wahrheitsquelle für Software im
## gesamten Spiel: jeder Titel existiert genau einmal, alles referenziert nur
## die `software_id`.
##
## ENGINE FIRST, CONTENT SECOND: Dieser Motor ändert sich nie wieder. Er wächst
## ausschließlich durch neue JSON-Einträge in der Bibel. Kein Gameplay-System
## darf Software hart verdrahten — es fragt hier ab.
##
## Der Motor ist bewusst additiv: er ersetzt bestehende Systeme (ProgramLibrary,
## Shop, BBS) NICHT, sondern stellt die Abfrage-Schicht bereit, gegen die sie
## nach und nach referenzieren können.
##
## Skaliert auf zehntausende Einträge: einmaliges Einlesen + Indizes beim Start.

const ROOT := "res://Content/Software"
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")

# Pflichtfelder (fehlen sie, ist der Eintrag ungültig).
const REQUIRED_FIELDS := ["software_id", "historical_name", "category"]
# Für „vollständige" Metadaten empfohlene Felder (fehlen sie → Warnung).
const RECOMMENDED_FIELDS := [
	"display_name", "release_year", "developer", "publisher",
	"platform", "category", "subcategory",
]
const TIMELINE_YEARS := [1990, 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000]
const MAX_DISK_COUNT := 20

var _by_id: Dictionary = {}          # software_id -> entry (Dictionary)
var _order: Array[String] = []       # Reihenfolge des Einlesens
var _by_category: Dictionary = {}    # category -> Array[String] (ids)
var _by_letter: Dictionary = {}      # "A".."Z" -> Array[String] (ids)
var _load_issues: Array[String] = [] # Parse-/Struktur-/Duplikat-Probleme
var _art_cache: Dictionary = {}      # "id/kind" -> ImageTexture | null (gecacht)
var _art_cache_order: Array[String] = []
var _thumbnail_cache: Dictionary = {} # kleine Katalogcover, getrennt von Detail-Art
var _thumbnail_cache_order: Array[String] = []
var _illustrated_cache: Array = []
var _shop_title_cache: Dictionary = {}
var _catalog_title_cache: Dictionary = {}
const ART_CACHE_LIMIT := 48
const THUMBNAIL_CACHE_LIMIT := 192

var loaded: bool = false

# Welche Artwork-Sorte gehört zu welcher Erwerbsform? Kernregel:
#   Karton (Original mit Box) → Box-Front · lose Original-Disk → gedrucktes
#   Disk-Label · Handbuch-Fund → Handbuch-Cover · Kopie → KEIN gedrucktes Artwork.
const ART_FOR_FORM := {
	"box": "box_front", "original_box": "box_front",
	"disk": "disk_label", "original": "disk_label",
	"manual": "manual_cover", "cover": "cover_front", "back": "cover_back",
}


func _ready() -> void:
	reload()


# --------------------------------------------------------------- Einlesen
func reload() -> void:
	_by_id.clear()
	_order.clear()
	_by_category.clear()
	_by_letter.clear()
	_load_issues.clear()
	_art_cache.clear()
	_art_cache_order.clear()
	_thumbnail_cache.clear()
	_thumbnail_cache_order.clear()
	_illustrated_cache.clear()
	_shop_title_cache.clear()
	_catalog_title_cache.clear()
	_scan_dir(ROOT)
	loaded = true
	if not _load_issues.is_empty():
		push_warning("SoftwareBible: %d Ladeprobleme (siehe validate())." % _load_issues.size())


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		var full := path.path_join(entry_name)
		if dir.current_is_dir():
			if not entry_name.begins_with("."):
				_scan_dir(full)
		elif entry_name.ends_with(".json") and not entry_name.begins_with("_"):
			_load_file(full)
		entry_name = dir.get_next()
	dir.list_dir_end()


func _load_file(file: String) -> void:
	var txt := FileAccess.get_file_as_string(file)
	if txt.strip_edges().is_empty():
		_load_issues.append("%s: leere Datei" % file)
		return
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_issues.append("%s: kein JSON-Objekt an der Wurzel" % file)
		return
	var data: Dictionary = parsed
	var raw_entries: Variant = data.get("entries", [])
	if typeof(raw_entries) != TYPE_ARRAY:
		_load_issues.append("%s: 'entries' ist kein Array" % file)
		return
	var default_letter: String = str(data.get("letter", ""))
	for e: Variant in raw_entries:
		_ingest(e, file, default_letter)


func _ingest(raw_entry: Variant, file: String, default_letter: String) -> void:
	if typeof(raw_entry) != TYPE_DICTIONARY:
		_load_issues.append("%s: Eintrag ist kein Objekt" % file)
		return
	var d: Dictionary = raw_entry
	var id: String = str(d.get("software_id", "")).strip_edges()
	if id.is_empty():
		_load_issues.append("%s: Eintrag ohne software_id" % file)
		return
	if _by_id.has(id):
		var other: String = str((_by_id[id] as Dictionary).get("_source_file", "?"))
		_load_issues.append("Doppelte software_id '%s' in %s (bereits in %s)" % [id, file, other])
		return
	# Herkunft merken (nur zur Diagnose, nicht Teil des Contents).
	d["_source_file"] = file

	_by_id[id] = d
	_order.append(id)

	var cat: String = str(d.get("category", "unsortiert"))
	if not _by_category.has(cat):
		_by_category[cat] = []
	(_by_category[cat] as Array).append(id)

	var letter := default_letter
	if letter.is_empty():
		letter = id.substr(0, 1).to_upper()
	if not _by_letter.has(letter):
		_by_letter[letter] = []
	(_by_letter[letter] as Array).append(id)


# --------------------------------------------------------------- Abfragen
func count() -> int:
	return _order.size()


func has_software(id: String) -> bool:
	return _by_id.has(id)


## Gibt eine Kopie des Eintrags zurück (nie die interne Referenz verändern).
func entry(id: String) -> Dictionary:
	if not _by_id.has(id):
		return {}
	return (_by_id[id] as Dictionary).duplicate(true)


## Physische Diskettenzahl eines Titels. Contentfehler bleiben lokal begrenzt:
## unbekannt/ungueltig wird als Ein-Disketten-Titel behandelt, nie als 0.
func disk_count(id: String) -> int:
	if not _by_id.has(id):
		return 1
	var raw: Variant = (_by_id[id] as Dictionary).get("disk_count", 1)
	var dc := int(raw) if raw is int or raw is float or str(raw).is_valid_int() else 1
	return clampi(dc, 1, MAX_DISK_COUNT)


func all_ids() -> Array:
	return _order.duplicate()


func by_category(cat: String) -> Array:
	return (_by_category.get(cat, []) as Array).duplicate()


func by_letter(letter: String) -> Array:
	return (_by_letter.get(letter.to_upper(), []) as Array).duplicate()


func categories() -> Array:
	return _by_category.keys()


## Freitextsuche über Name, Alternativnamen, Keywords und Tags.
func search(query: String) -> Array:
	var q := query.strip_edges().to_lower()
	var hits: Array = []
	if q.is_empty():
		return hits
	for id: String in _order:
		var d: Dictionary = _by_id[id]
		var hay := "%s %s %s %s" % [
			str(d.get("historical_name", "")),
			str(d.get("display_name", "")),
			" ".join(_as_string_array(d.get("keywords", []))),
			" ".join(_as_string_array(d.get("tags", []))),
		]
		if hay.to_lower().contains(q):
			hits.append(id)
	return hits


# --------------------------------------------------------------- Timeline
## Die Jahres-Scheibe eines Titels ({available, shop, bbs, price, ...}) oder {}.
func timeline_for(id: String, year: int) -> Dictionary:
	if not _by_id.has(id):
		return {}
	var tl: Variant = (_by_id[id] as Dictionary).get("timeline", {})
	if typeof(tl) != TYPE_DICTIONARY:
		return {}
	var key := str(year)
	var slice: Variant = (tl as Dictionary).get(key, {})
	if typeof(slice) != TYPE_DICTIONARY:
		return {}
	return (slice as Dictionary).duplicate(true)


## Ist der Titel in diesem Jahr über den genannten Kanal verfügbar?
## channel: "" (grundsätzlich available) | "shop" | "bbs" | "friend" |
## "magazine" | "coverdisk".
func available_in_year(year: int, channel: String = "") -> Array:
	var out: Array = []
	for id: String in _order:
		var slice := timeline_for(id, year)
		if slice.is_empty():
			continue
		if channel.is_empty():
			if bool(slice.get("available", false)):
				out.append(id)
		elif bool(slice.get(channel, false)):
			out.append(id)
	return out


# --------------------------------------------------------------- Validierung
## Vollständiger Prüflauf. Gibt Meldungen mit Präfix „ERROR"/„WARN"/„INFO"
## zurück; leere Liste = alles sauber. Deckt Duplikate, Jahres-Sanity, fehlende
## Pflicht-/Empfehlungsfelder und als unvollständig markierte Einträge ab.
func validate() -> Array[String]:
	var issues: Array[String] = []
	# Beim Laden gefundene Struktur-/Duplikatprobleme sind harte Fehler.
	for li: String in _load_issues:
		issues.append("ERROR  " + li)

	var seen_hist: Dictionary = {}  # historical_name(lower) -> id
	for id: String in _order:
		var d: Dictionary = _by_id[id]

		for field: String in REQUIRED_FIELDS:
			if not d.has(field) or str(d[field]).strip_edges().is_empty():
				issues.append("ERROR  %s: Pflichtfeld '%s' fehlt" % [id, field])

		var hist := str(d.get("historical_name", "")).strip_edges().to_lower()
		if not hist.is_empty():
			if seen_hist.has(hist):
				issues.append("ERROR  Doppelter historical_name '%s' (%s und %s)"
					% [d.get("historical_name", ""), seen_hist[hist], id])
			else:
				seen_hist[hist] = id

		# Jahres-Plausibilität (Szene 1990-2000, kleiner Puffer erlaubt).
		if d.has("release_year") and str(d["release_year"]).strip_edges() != "":
			var yr := int(d["release_year"])
			if yr < 1975 or yr > 2005:
				issues.append("WARN   %s: release_year %d außerhalb 1975-2005" % [id, yr])

		if str(d.get("category", "")) == "games":
			var raw_disk_count: Variant = d.get("disk_count", null)
			var valid_disk_count := (raw_disk_count is int or raw_disk_count is float) \
				and float(raw_disk_count) == floorf(float(raw_disk_count)) \
				and int(raw_disk_count) >= 1 and int(raw_disk_count) <= MAX_DISK_COUNT
			if not valid_disk_count:
				issues.append("WARN   %s: disk_count fehlt oder liegt nicht zwischen 1 und %d" % [id, MAX_DISK_COUNT])

		# Timeline-Jahre müssen bekannte Schlüssel sein.
		var tl: Variant = d.get("timeline", {})
		if typeof(tl) == TYPE_DICTIONARY:
			for ykey: Variant in (tl as Dictionary).keys():
				if not TIMELINE_YEARS.has(int(ykey)):
					issues.append("WARN   %s: Timeline-Jahr '%s' unbekannt" % [id, str(ykey)])

		# Als prüfbedürftig markiert oder unvollständige Metadaten.
		if bool(d.get("needs_verification", false)):
			issues.append("INFO   %s: als 'needs_verification' markiert" % id)
		for field: String in RECOMMENDED_FIELDS:
			if not d.has(field) or str(d[field]).strip_edges().is_empty():
				issues.append("WARN   %s: empfohlenes Feld '%s' fehlt" % [id, field])

	return issues


# --------------------------------------------------------------- Artwork
## Verlinkter Artwork-Pfad (res://…) einer Sorte (box_front/disk_label/…) oder "".
func art_path(id: String, kind: String) -> String:
	if not _by_id.has(id):
		return ""
	var d: Dictionary = _by_id[id]
	var art: Variant = d.get("art", {})
	if typeof(art) != TYPE_DICTIONARY:
		return ""
	var fname := str((art as Dictionary).get(kind, ""))
	var dir := str(d.get("art_dir", ""))
	if fname.is_empty() or dir.is_empty():
		return ""
	return RuntimeImages.canonical_path("%s/%s" % [dir, fname])


func has_art(id: String, kind: String) -> bool:
	var p := art_path(id, kind)
	return RuntimeImages.exists(p)


## Artwork-Textur (gecacht). Lädt das PNG per FileAccess (funktioniert auch OHNE
## Godot-Import) und verkleinert große Vorlagen auf max. 512px Kantenlänge.
func art_texture(id: String, kind: String) -> Texture2D:
	var key := "%s/%s" % [id, kind]
	if _art_cache.has(key):
		_art_cache_order.erase(key)
		_art_cache_order.append(key)
		return _art_cache[key]
	var path := art_path(id, kind)
	# .gdignore artwork is raw-first; imported resources remain a valid fallback.
	var tex: Texture2D = RuntimeImages.texture(path, 512, true)
	_art_cache[key] = tex
	_art_cache_order.append(key)
	while _art_cache_order.size() > ART_CACHE_LIMIT:
		_art_cache.erase(_art_cache_order.pop_front())
	return tex


## Kleine, dauerhaft wiederverwendbare Cover fuer Kataloglisten. Diese Texturen
## liegen bewusst in einem eigenen LRU: Beim Blaettern durch hunderte OVPs darf
## eine 62-Pixel-Zeile weder 512-Pixel-Detailbilder laden noch die wertvolleren
## Box-/Handbuchtexturen aus deren Cache draengen.
func art_thumbnail(id: String, kind: String = "box_front", max_width: int = 96) -> Texture2D:
	var bounded_width := clampi(max_width, 32, 192)
	var key := "%s/%s/%d" % [id, kind, bounded_width]
	if _thumbnail_cache.has(key):
		_thumbnail_cache_order.erase(key)
		_thumbnail_cache_order.append(key)
		return _thumbnail_cache[key]
	var path := art_path(id, kind)
	var tex: Texture2D = RuntimeImages.texture(path, bounded_width, true)
	_thumbnail_cache[key] = tex
	_thumbnail_cache_order.append(key)
	while _thumbnail_cache_order.size() > THUMBNAIL_CACHE_LIMIT:
		_thumbnail_cache.erase(_thumbnail_cache_order.pop_front())
	return tex


## Bild aus Bytes dekodieren — PNG ODER JPEG (der Scraper exportiert teils JPEG
## mit .png-Endung). Erkennt das Format an den Magic-Bytes. RGBA8. null bei Fehler.
static func decode_image(bytes: PackedByteArray) -> Image:
	if bytes.size() < 4:
		return null
	var img := Image.new()
	var ok: int
	if bytes[0] == 0xFF and bytes[1] == 0xD8:                 # JPEG (FF D8)
		ok = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:              # PNG (89 50 4E 47)
		ok = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49 \
			and bytes[2] == 0x46 and bytes[3] == 0x46:           # WebP (RIFF)
		ok = img.load_webp_from_buffer(bytes)
	else:                                                     # Fallback: beides probieren
		ok = img.load_png_from_buffer(bytes)
		if ok != OK:
			ok = img.load_jpg_from_buffer(bytes)
	if ok != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## Das zur Erwerbsform passende Artwork: {kind, texture} oder {} (z. B. Kopie hat
## kein gedrucktes Artwork). form: box/original_box · disk/original · manual · cover.
func acquisition_art(id: String, form: String) -> Dictionary:
	var kind := str(ART_FOR_FORM.get(form, ""))
	if kind.is_empty():
		return {}
	var tex := art_texture(id, kind)
	if tex == null:
		return {}
	return {"kind": kind, "texture": tex}


## Alle Bibel-IDs (Kategorie 'games'), die vollständiges Box+Disk+Manual-Artwork
## haben — die Grundlage für „echte" Flohmarkt-/Laden-Ware.
func illustrated_games() -> Array:
	if not _illustrated_cache.is_empty():
		return _illustrated_cache.duplicate()
	var out: Array = []
	for id: String in by_category("games"):
		if has_art(id, "box_front") and has_art(id, "disk_label"):
			out.append(id)
	_illustrated_cache = out
	return out.duplicate()


## Spiele, die in `year` NEU im Laden-Regal stehen (mit Box-Art): vom Erscheinungs-
## jahr bis last_supported_year (Regal-Lebensdauer; Default release+2). So tauchen
## importierte Titel automatisch im richtigen Jahr auf. Alphabetisch sortiert.
func shop_titles(year: int) -> Array:
	if _shop_title_cache.has(year):
		return (_shop_title_cache[year] as Array).duplicate()
	var out: Array = []
	for id: String in illustrated_games():
		var e: Dictionary = _by_id[id]
		var ry := int(e.get("release_year", 0))
		if ry <= 0:
			continue
		var ly := int(e.get("last_supported_year", ry + 2))
		if ly < ry:
			ly = ry + 2
		# Timeline-Override: ein explizit als shop:true markiertes Jahr zählt immer.
		var tl_shop := false
		var tl: Variant = e.get("timeline", {})
		if typeof(tl) == TYPE_DICTIONARY and (tl as Dictionary).has(str(year)):
			var shop_value: Variant = (tl as Dictionary)[str(year)].get("shop", false)
			tl_shop = shop_value is bool and shop_value
		if (ry <= year and year <= ly) or tl_shop:
			out.append(id)
	out.sort()
	_shop_title_cache[year] = out
	return out.duplicate()


## Vollständiger OVP-Bestellkatalog bis zu einem Jahr. Anders als `shop_titles`
## bildet diese Liste nicht nur die zwei bis drei Jahre aktuelle Regalphase ab:
## Jeder bereits erschienene Titel mit vollständigem Box-/Disk-Artwork bleibt
## als Restlager-, Großhandels- oder Archivbestellung auffindbar. Das kleine
## Ladenregal bleibt davon getrennt und rotiert weiterhin glaubwürdig.
func catalog_titles(year: int) -> Array:
	if _catalog_title_cache.has(year):
		return (_catalog_title_cache[year] as Array).duplicate()
	var out: Array = []
	for id: String in illustrated_games():
		var release_year := int((_by_id[id] as Dictionary).get("release_year", 0))
		if release_year > 0 and release_year <= year:
			out.append(id)
	# Ein großer Katalog muss vorhersagbar durchsuchbar bleiben. Das UI kann
	# Jahr/Status separat hervorheben; die Grundreihenfolge bleibt alphabetisch.
	out.sort_custom(func(a: String, b: String) -> bool:
		var entry_a: Dictionary = _by_id[a]
		var entry_b: Dictionary = _by_id[b]
		var name_a := str(entry_a.get("display_name", entry_a.get("historical_name", a)))
		var name_b := str(entry_b.get("display_name", entry_b.get("historical_name", b)))
		return name_a.naturalnocasecmp_to(name_b) < 0)
	_catalog_title_cache[year] = out
	return out.duplicate()


## Kuratiertes LADENSORTIMENT: eine begrenzte, wechselnde Auswahl aus den in diesem
## Jahr verfügbaren Titeln (shop_titles) — ein kleiner Laden führt nicht den ganzen
## Jahrgang. Neuere Spiele werden bevorzugt, die Auswahl ist deterministisch nach
## `seed` (z.B. Jahr+Woche → das Regal rotiert wöchentlich, bleibt aber pro Woche
## stabil). `count` = Regalgröße. Anzeige: neueste zuerst, dann alphabetisch.
func shop_stock(year: int, stock_seed: int, max_count: int = 14) -> Array:
	var stock_pool := shop_titles(year)
	if stock_pool.size() <= max_count:
		return stock_pool
	var scored: Array = []
	for id: String in stock_pool:
		var ry := int(_by_id[id].get("release_year", year))
		var age: int = maxi(0, year - ry)
		var rnd := float(absi(("%s#%d" % [id, stock_seed]).hash()) % 100003) / 100003.0
		scored.append([rnd + age * 0.12, id])   # neuer (age 0) = kleiner = eher im Regal
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for i in max_count:
		out.append(scored[i][1])
	out.sort_custom(func(a: String, b: String) -> bool:
		var ra := int(_by_id[a].get("release_year", 0))
		var rb := int(_by_id[b].get("release_year", 0))
		if ra != rb:
			return ra > rb
		return a < b)
	return out


# --------------------------------------------------------------- intern
func _as_string_array(v: Variant) -> Array:
	if typeof(v) != TYPE_ARRAY:
		return []
	var out: Array = []
	for x: Variant in (v as Array):
		out.append(str(x))
	return out
