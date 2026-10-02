extends Node
## HomepageManager — die EIGENE HEIMSEITE (ab dem Internetcafé). Der Spieler baut
## im Editor eine 90er-Homepage (Titel, About, Kachel-Hintergrund, Farbe, Features)
## und stellt sie online. Danach wächst der Besucherzähler täglich und das Gästebuch
## füllt sich (Szene-Handles + Netz-Fremde). Erste Veröffentlichung = Szene-Ruf +
## Meilenstein. Zustand liegt in GameManager.flags["homepage"] (schon im Save;
## kein SaveManager-Eingriff).

signal homepage_changed

const GUEST_HANDLES := ["SIRIUS", "JOYRIDER", "DATAWOLF", "LUMEN", "PIXIE",
	"ein Surfer aus Übersee", "webmaster42", "anonym", "GameFan '98"]
const GUEST_LINES := ["cooles Design!", "sign my guestbook back!", "nette Seite, weiter so!",
	"die Under-Construction-GIFs sind der Hammer", "wo hast du das Amiga-Zeug her?",
	"Grüße aus dem Netz!", "★★★★☆ nice", "endlich mal 'ne gute HP", "bin über den Webring hier"]
const FIELDS := ["title", "about", "bg", "accent", "features", "modules", "layout"]
const MODULES := [
	{"id": "counter", "label": "Besucherzaehler", "year": 1998,
		"note": "Sechsstelliger Hit-Counter mit Tagesstatistik."},
	{"id": "guestbook", "label": "Gaestebuch", "year": 1998,
		"note": "Besucher koennen Handles und kurze Gruesse hinterlassen."},
	{"id": "webring", "label": "Amiga-Webring", "year": 1998,
		"note": "Vor/Zurueck-Navigation bringt neue Besucher aus Partnerseiten."},
	{"id": "links", "label": "Link-Rubrik", "year": 1998,
		"note": "Kuratierte BBS-, Club- und Amiga-Verweise statt Linkwueste."},
	{"id": "news", "label": "News-Ticker", "year": 1999,
		"note": "Datierte Kurzmeldungen machen die Seite zur lebenden Chronik."},
	{"id": "downloads", "label": "Download-Archiv", "year": 1999,
		"note": "Verifizierte Demos und Tools mit Groesse, Datum und Beschreibung."},
]
const YEAR_MODULES := {1998: "webring", 1999: "downloads"}


func _ready() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(_on_day_changed)
	if tm != null and tm.has_signal("calendar_jumped"):
		tm.calendar_jumped.connect(_on_calendar_jumped)


func get_cfg() -> Dictionary:
	var raw: Variant = GameManager.flags.get("homepage", {})
	if raw is not Dictionary:
		return {}
	var cfg := _migrate_cfg((raw as Dictionary).duplicate(true))
	if not cfg.is_empty():
		GameManager.flags["homepage"] = cfg
		_ensure_year_module_task(cfg)
	return cfg


func is_published() -> bool:
	return bool(get_cfg().get("published", false))


func save_cfg(cfg: Dictionary) -> void:
	var current: Variant = GameManager.flags.get("homepage", {})
	var c: Dictionary = _migrate_cfg((current as Dictionary).duplicate(true)) \
		if current is Dictionary else {}
	for k in FIELDS:
		if cfg.has(k):
			c[k] = cfg[k]
	c = _migrate_cfg(c)
	GameManager.flags["homepage"] = c
	_ensure_year_module_task(c)
	homepage_changed.emit()


## Veröffentlichen (oder aktualisieren). Rückgabe: {first, ruf}.
func publish(cfg: Dictionary) -> Dictionary:
	var current: Variant = GameManager.flags.get("homepage", {})
	var c: Dictionary = _migrate_cfg((current as Dictionary).duplicate(true)) \
		if current is Dictionary else {}
	var first := not bool(c.get("published", false))
	for k in FIELDS:
		if cfg.has(k):
			c[k] = cfg[k]
	c["published"] = true
	if not c.has("visitors"):
		c["visitors"] = 1
	if not c.has("guestbook"):
		c["guestbook"] = []
	c["last_publish_year"] = TimeManager.year
	c["last_publish_day"] = TimeManager.day_counter
	c = _migrate_cfg(c)
	GameManager.flags["homepage"] = c
	# Erst-Veröffentlichung gibt +3 Ruf; jede Aktualisierung höchstens +1 pro Tag —
	# sonst ließe sich der „Veröffentlichen"-Knopf für endlosen Ruf spammen. Beide
	# Fälle markieren den Tag, damit ein Update direkt nach dem Erst-Publish 0 gibt.
	var today := int(TimeManager.day_counter)
	var ruf := 0
	if first:
		ruf = 3
		GameManager.flags["homepage_ruf_day"] = today
	elif int(GameManager.flags.get("homepage_ruf_day", -1)) != today:
		GameManager.flags["homepage_ruf_day"] = today
		ruf = 1
	if ruf > 0:
		PlayerStats.change_stat("ruf", ruf)
	if first:
		MemoryManager.record_once("first_homepage", "erste eigene Homepage online gestellt")
		QuestManager.note_action("publish_homepage")
	else:
		QuestManager.note_action("update_homepage")
	_note_published_modules(c)
	_ensure_year_module_task(c)
	var am := get_node_or_null("/root/AchievementManager")
	if am != null:
		am.call("note", "published_homepage")
	homepage_changed.emit()
	return {"first": first, "ruf": ruf}


func visitors() -> int:
	return int(get_cfg().get("visitors", 0))


func module_catalog(year := -1) -> Array:
	var active_year := TimeManager.year if year < 0 else year
	return MODULES.filter(func(module: Dictionary) -> bool:
		return int(module.get("year", 1998)) <= active_year).map(
			func(module: Dictionary) -> Dictionary: return _localized_module(module))


func module_active(cfg: Dictionary, module_id: String) -> bool:
	var modules: Variant = cfg.get("modules", {})
	return modules is Dictionary and bool((modules as Dictionary).get(module_id, false))


func yearly_module(year := -1) -> Dictionary:
	var active_year := TimeManager.year if year < 0 else year
	var id := str(YEAR_MODULES.get(active_year, ""))
	for module: Dictionary in MODULES:
		if str(module.get("id", "")) == id:
			return _localized_module(module)
	return {}


func _on_day_changed() -> void:
	_grow_for_days(1, true)
	_ensure_year_module_task(get_cfg())


func _on_calendar_jumped(_from: Dictionary, _to: Dictionary, elapsed_days: int, _reason: String) -> void:
	_grow_for_days(maxi(0, elapsed_days - 1), false)
	_ensure_year_module_task(get_cfg())


func _grow_for_days(days: int, allow_guestbook: bool) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	var c: Dictionary = GameManager.flags.get("homepage", {})
	if not bool(c.get("published", false)):
		return
	if int(TimeManager.year) < 1996:
		return
	var feats: Dictionary = c.get("features", {})
	var modules: Dictionary = c.get("modules", {})
	if days <= 0:
		return
	var growth := randi_range(3, 12) * days
	if bool(feats.get("webring", true)):
		growth += randi_range(2, 8) * days
	if bool(modules.get("news", false)):
		growth += randi_range(1, 4) * days
	if bool(modules.get("downloads", false)):
		growth += randi_range(3, 7) * days
	c["visitors"] = int(c.get("visitors", 0)) + growth
	# Ab und zu ein neuer Gästebuch-Eintrag.
	if allow_guestbook and bool(feats.get("guestbook", true)) and randf() < 0.5:
		var gb: Array = c.get("guestbook", [])
		var who_id := randi() % GUEST_HANDLES.size()
		var line_id := randi() % GUEST_LINES.size()
		gb.append({
			"who_id": who_id, "who": GUEST_HANDLES[who_id],
			"text_id": line_id, "text": GUEST_LINES[line_id],
			"day": int(TimeManager.day_counter),
		})
		while gb.size() > 20:
			gb.pop_front()
		c["guestbook"] = gb
	GameManager.flags["homepage"] = c
	homepage_changed.emit()
	QuestManager.evaluate()


func reset() -> void:
	homepage_changed.emit()


func _migrate_cfg(cfg: Dictionary) -> Dictionary:
	if cfg.is_empty():
		return cfg
	var features: Dictionary = cfg.get("features", {}) if cfg.get("features", {}) is Dictionary else {}
	var modules: Dictionary = cfg.get("modules", {}) if cfg.get("modules", {}) is Dictionary else {}
	# Alte Saves kannten nur vier Feature-Checkboxen. Sie werden verlustfrei auf
	# das neue Modulmodell abgebildet; neue Jahresmodule bleiben bewusst aus, bis
	# der Spieler sie im Editor installiert und neu veroeffentlicht.
	for id in ["counter", "guestbook", "webring"]:
		if not modules.has(id):
			modules[id] = bool(features.get(id, true))
	if not modules.has("links"):
		modules["links"] = bool(features.get("webring", true))
	for id in ["news", "downloads"]:
		if not modules.has(id):
			modules[id] = false
	features["counter"] = bool(modules.get("counter", true))
	features["guestbook"] = bool(modules.get("guestbook", true))
	features["webring"] = bool(modules.get("webring", true))
	if not features.has("construction"):
		features["construction"] = false
	cfg["features"] = features
	cfg["modules"] = modules
	if not cfg.has("layout"):
		cfg["layout"] = "portal" if TimeManager.year >= 1999 else "classic"
	return cfg


func _note_published_modules(cfg: Dictionary) -> void:
	for module: Dictionary in module_catalog():
		var id := str(module.get("id", ""))
		if id.is_empty() or not module_active(cfg, id):
			continue
		var flag := "homepage_module_reported_" + id
		if bool(GameManager.flags.get(flag, false)):
			continue
		GameManager.flags[flag] = true
		QuestManager.note_action("homepage_module:" + id)
		var module_year := int(module.get("year", TimeManager.year))
		TaskManager.complete("task_homepage_module_%d" % module_year)


func _ensure_year_module_task(cfg: Dictionary) -> void:
	if not bool(cfg.get("published", false)):
		return
	var module := yearly_module()
	if module.is_empty():
		return
	var id := str(module.get("id", ""))
	var task_id := "task_homepage_module_%d" % TimeManager.year
	if module_active(cfg, id):
		TaskManager.complete(task_id)
		return
	TaskManager.add_task({
		"id": task_id,
		"title": Loc.t("sys.homepage_manager.add_year_module", "Homepage %d: %s ergaenzen") % [TimeManager.year, str(module.get("label", id))],
		"note": Loc.t("sys.homepage_manager.activate_module_note", "Internetcafe -> Homepage-Editor -> MODUL. %s aktivieren und die Seite neu veroeffentlichen.") % str(module.get("note", "")),
	})


func guest_name(entry: Dictionary) -> String:
	var index := int(entry.get("who_id", GUEST_HANDLES.find(str(entry.get("who", "")))))
	match index:
		0: return "SIRIUS"
		1: return "JOYRIDER"
		2: return "DATAWOLF"
		3: return "LUMEN"
		4: return "PIXIE"
		5: return Loc.t("sys.homepage_manager.guest_overseas_surfer", "ein Surfer aus Übersee")
		6: return "webmaster42"
		7: return Loc.t("sys.homepage_manager.guest_anonymous", "anonym")
		8: return "GameFan '98"
	return str(entry.get("who", Loc.t("sys.homepage_manager.guest_anonymous", "anonym")))


func guest_line(entry: Dictionary) -> String:
	var index := int(entry.get("text_id", GUEST_LINES.find(str(entry.get("text", "")))))
	match index:
		0: return Loc.t("sys.homepage_manager.guest_line_0", "cooles Design!")
		1: return Loc.t("sys.homepage_manager.guest_line_1", "sign my guestbook back!")
		2: return Loc.t("sys.homepage_manager.guest_line_2", "nette Seite, weiter so!")
		3: return Loc.t("sys.homepage_manager.guest_line_3", "die Under-Construction-GIFs sind der Hammer")
		4: return Loc.t("sys.homepage_manager.guest_line_4", "wo hast du das Amiga-Zeug her?")
		5: return Loc.t("sys.homepage_manager.guest_line_5", "Grüße aus dem Netz!")
		6: return Loc.t("sys.homepage_manager.guest_line_6", "★★★★☆ nice")
		7: return Loc.t("sys.homepage_manager.guest_line_7", "endlich mal 'ne gute HP")
		8: return Loc.t("sys.homepage_manager.guest_line_8", "bin über den Webring hier")
	return str(entry.get("text", ""))


func _localized_module(module: Dictionary) -> Dictionary:
	var result := module.duplicate(true)
	var module_id := str(module.get("id", ""))
	match module_id:
		"counter":
			result["label"] = Loc.t("sys.homepage_manager.module_counter", "Besucherzaehler")
			result["note"] = Loc.t("sys.homepage_manager.module_counter_note", "Sechsstelliger Hit-Counter mit Tagesstatistik.")
		"guestbook":
			result["label"] = Loc.t("sys.homepage_manager.module_guestbook", "Gaestebuch")
			result["note"] = Loc.t("sys.homepage_manager.module_guestbook_note", "Besucher koennen Handles und kurze Gruesse hinterlassen.")
		"webring":
			result["label"] = Loc.t("sys.homepage_manager.module_webring", "Amiga-Webring")
			result["note"] = Loc.t("sys.homepage_manager.module_webring_note", "Vor/Zurueck-Navigation bringt neue Besucher aus Partnerseiten.")
		"links":
			result["label"] = Loc.t("sys.homepage_manager.module_links", "Link-Rubrik")
			result["note"] = Loc.t("sys.homepage_manager.module_links_note", "Kuratierte BBS-, Club- und Amiga-Verweise statt Linkwueste.")
		"news":
			result["label"] = Loc.t("sys.homepage_manager.module_news", "News-Ticker")
			result["note"] = Loc.t("sys.homepage_manager.module_news_note", "Datierte Kurzmeldungen machen die Seite zur lebenden Chronik.")
		"downloads":
			result["label"] = Loc.t("sys.homepage_manager.module_downloads", "Download-Archiv")
			result["note"] = Loc.t("sys.homepage_manager.module_downloads_note", "Verifizierte Demos und Tools mit Groesse, Datum und Beschreibung.")
	return result
