extends Node
## RumorSources (AUTOLOAD) — die timeline-bewussten Gerüchte-Quellen von SOMMER '90.
## PERMANENTE ARCHITEKTUR (vorausschauend): Jede Quelle liefert Kandidaten
## {id, topic, truth, texts[3], once, weight}; der RumorManager sät daraus.
## Texte sind IMMER 3 Stufen (akkurat → ausgeschmückt → entstellt) für den
## Stille-Post-Effekt der Gruppen.
##
## ZEIT-REGEL (Kern!): Gerüchte entstehen NUR aus Spieldaten, die zeitlich
## passen — Hardware/Software/Boards erst ab ihrem Jahr (oder als klar
## formulierte Vorfreude max. 1 Jahr vorher), MOD-Szene aus dem Katalogjahr.
## Neue Quellen einfach als weitere _src_*()-Funktion registrieren.
## Autoload statt class_name: -s-Tests koennen class_names mit Autoload-Refs nicht kompilieren.


## Alle Kandidaten für den heutigen Tag (RumorManager filtert seeded/aktiv).
func candidates() -> Array:
	var out: Array = []
	out.append_array(_src_timeline_news())
	out.append_array(_src_hardware_soon())
	out.append_array(_src_hardware_new())
	out.append_array(_src_software_release())
	out.append_array(_src_bbs_new())
	out.append_array(_src_mod_scene())
	return out


# ------------------------------------------------------- Quelle: Jahres-News
## Schlagzeilen/News der Living Timeline werden Pausenhof-Gespräch.
func _src_timeline_news() -> Array:
	var out: Array = []
	var news: Array = TimelineManager.year_data(TimeManager.year).get("news", [])
	for i in news.size():
		var n := str(news[i])
		out.append({
			"id": "news_%d_%d" % [TimeManager.year, i], "topic": "welt",
			"truth": true, "once": true, "weight": 1.0,
			"texts": [n,
				"Hab ich in ner Zeitschrift gelesen: %s" % n,
				"Irgendwer meinte sowas wie: %s Glaub ich zumindest." % n],
		})
	return out


# ------------------------------------------------- Quelle: Hardware kommt bald
## Shop-Artikel, die NÄCHSTES Jahr erscheinen → Vorfreude (wahr, aber vage).
func _src_hardware_soon() -> Array:
	var out: Array = []
	for item: Dictionary in ShopManager.items:
		if int(item.get("year_available", 1990)) == TimeManager.year + 1:
			var n := str(item.get("name", "?"))
			out.append({
				"id": "hw_soon_%s" % item.get("id", ""), "topic": "hardware",
				"truth": true, "once": true, "weight": 1.4,
				"texts": ["Nächstes Jahr soll es %s zu kaufen geben." % n,
					"Einer aus der Parallelklasse schwört, bald gibt's %s bei Gruber." % n,
					"Angeblich kommt bald was ganz Neues in den Laden. %s oder so?!" % n],
			})
	return out


# ------------------------------------------------- Quelle: Hardware ist NEU da
func _src_hardware_new() -> Array:
	var out: Array = []
	for item: Dictionary in ShopManager.items:
		if int(item.get("year_available", 1990)) == TimeManager.year:
			var n := str(item.get("name", "?"))
			out.append({
				"id": "hw_new_%s_%d" % [item.get("id", ""), TimeManager.year], "topic": "hardware",
				"truth": true, "once": true, "weight": 1.2,
				"texts": ["Der Computerladen hat jetzt %s im Regal." % n,
					"Bei Gruber steht neuerdings %s — hab's selbst gesehen. Fast." % n,
					"Es gibt was Neues im Laden. %s? Oder war's was anderes?" % n],
			})
	return out


# ---------------------------------------------- Quelle: Software-/Spiele-Release
## SoftwareBible: Einträge mit release_year == Spieljahr (nur echte Daten).
func _src_software_release() -> Array:
	var out: Array = []
	var rng := _rng("swrel")
	var ids: Array = SoftwareBible.all_ids()
	var hits: Array = []
	for id in ids:
		var e: Dictionary = SoftwareBible.entry(id)
		if str(e.get("release_year", "")) == str(TimeManager.year):
			hits.append(e)
	# nicht alle auf einmal: pro Tag höchstens 2 zufällige Kandidaten anbieten
	hits.shuffle()
	for e: Dictionary in hits.slice(0, mini(2, hits.size())):
		var n := str(e.get("display_name", e.get("id", "?")))
		out.append({
			"id": "sw_%s" % e.get("id", str(rng.randi())), "topic": "software",
			"truth": true, "once": true, "weight": 1.3,
			"texts": ["%s ist raus — soll richtig gut sein." % n,
				"Alle reden von %s. Einer will es schon durchgespielt haben." % n,
				"Es gibt da so ein neues Ding … %s? Soll der Wahnsinn sein!!" % n],
		})
	return out


# ------------------------------------------------------- Quelle: neue Mailbox
func _src_bbs_new() -> Array:
	var out: Array = []
	for b: Dictionary in BBSManager.boards_for_year(TimeManager.year):
		if int(b.get("year_from", 3000)) == TimeManager.year:
			var n := str(b.get("name", "?"))
			out.append({
				"id": "bbs_%s" % b.get("id", ""), "topic": "szene",
				"truth": true, "once": true, "weight": 1.2,
				"texts": ["Es gibt ne neue Mailbox: %s. Nummer kursiert schon." % n,
					"Kennst du schon %s? Da soll's die neuesten Sachen geben." % n,
					"Irgendwo gibt's ne geheime neue Nummer … %s oder so ähnlich." % n],
			})
	return out


# ----------------------------------------------------- Quelle: MOD-/Demo-Szene
## MOD-Bible + Musik-Katalog: Mailbox-Funde, Club-Abende, Flohmarkt-Disketten.
## Rotierend (id je Woche), Tracks nur ab ihrem Katalogjahr (tracks_on filtert).
func _src_mod_scene() -> Array:
	var out: Array = []
	var week := int(TimeManager.day_counter / 7.0)
	var rng := _rng("modscene_%d" % week)
	# a) Mailbox-Fund eines konkreten Tracks (erst wenn Mailboxen existieren)
	if TimeManager.year >= 1992:
		var bbs_pool: Array = MusicManager.tracks_on("bbs")
		if not bbs_pool.is_empty():
			var t: Dictionary = bbs_pool[rng.randi_range(0, bbs_pool.size() - 1)]
			var title := str(t.get("title", "?"))
			var author := str(t.get("author", "?"))
			out.append({
				"id": "mod_bbs_w%d" % week, "topic": "szene", "truth": true,
				"once": true, "weight": 1.1,
				"texts": ["In einer Mailbox ist »%s« von %s aufgetaucht." % [title, author],
					"Einer hat »%s« von der Mailbox gezogen — angeblich genial." % title,
					"Es soll da einen neuen Track geben … »%s«? Nie gehört, MUSS gut sein." % title],
			})
	# b) Club-Abend im Zeichen einer Legende (MOD-Bible)
	var legend := MODBible.artist_name(_pick(rng, MODBible.legends()))
	if legend != "":
		out.append({
			"id": "mod_club_w%d" % week, "topic": "szene", "truth": true,
			"once": true, "weight": 1.0,
			"texts": ["Im Computerclub läuft diese Woche fast nur %s." % legend,
				"Im Club sollen sie rauf und runter %s hören." % legend,
				"Im Club läuft angeblich nur noch ein einziger Musiker. %s??" % legend],
		})
	# c) Flohmarkt-Diskette mit Track-Aufschrift (Samstage besonders glaubhaft)
	var flea_pool: Array = MusicManager.tracks_on("flea")
	if not flea_pool.is_empty():
		var ft: Dictionary = flea_pool[rng.randi_range(0, flea_pool.size() - 1)]
		var ftitle := str(ft.get("title", "?"))
		out.append({
			"id": "mod_flea_w%d" % week, "topic": "szene", "truth": true,
			"once": true, "weight": 0.9,
			"texts": ["Auf dem Flohmarkt liegt ne Diskette mit der Aufschrift »%s«." % ftitle,
				"Beim Krause soll ne Kiste mit »%s« drin stehen." % ftitle,
				"Auf'm Flohmarkt gibt's ne Wunder-Diskette. »%s«, sagt man." % ftitle],
		})
	return out


# --------------------------------------------------------------- Helfer
func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return str(list[rng.randi_range(0, list.size() - 1)]) if not list.is_empty() else ""


func _rng(salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(salt) ^ (TimeManager.year * 131071)
	return rng
