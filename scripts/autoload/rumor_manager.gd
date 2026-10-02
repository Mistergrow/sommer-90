extends Node
## RumorManager — das Gesprächsnetzwerk des Schulhofs (das „soziale Netz" der
## frühen 90er, lange vor Messengern).
##
## Jede Info startet als Gerücht bei wenigen und breitet sich über Tage aus
## (reach 0→1). Jede Gruppe kennt nur, was ihre Ausbreitung überschritten hat,
## und erzählt es in ihrer eigenen Zuverlässigkeit weiter: Freunde recht genau,
## Ältere ausgeschmückt, Jüngere völlig entstellt (Stille Post). Gerüchte werden
## aus echten Ereignissen geboren (Flohmarkt naht, Bestellung im Laden da,
## Jahres-Themen) — dazu etwas erfundener Pausenhof-Hype.

signal rumors_changed

const DATA_PATH := "res://data/rumors.json"

var groups: Array = []      # aus rumors.json
var _templates: Array = []
var active: Array = []       # [{id, topic, truth, born_day, reach, texts}]
var resolved: Array = []     # [{text, truth}] — Ausgang fürs Schwarze Brett
var _seeded: Dictionary = {} # einmalige Trigger (Jahr, Bestellung) nicht doppelt


func _ready() -> void:
	_load()
	TimeManager.day_changed.connect(_on_day_changed)
	call_deferred("_seed_initial")


func _load() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("rumors.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("rumors.json ist kein gueltiges JSON-Objekt!")
		return
	var data: Dictionary = parsed
	groups = data.get("groups", [])
	_templates = data.get("templates", [])


func reset() -> void:
	active.clear()
	resolved.clear()
	_seeded.clear()
	_seed_initial()


## Beim Spielstart soll der Hof nicht leer sein: ein ambientes Gerücht + die
## fälligen Trigger fürs aktuelle Datum.
func _seed_initial() -> void:
	_seed_ambient(true)
	_check_triggers()
	_seed_from_sources()
	rumors_changed.emit()


# --------------------------------------------------------------- Tageslauf

func _on_day_changed() -> void:
	_spread()
	_check_triggers()
	_seed_from_sources()
	_seed_ambient(false)
	rumors_changed.emit()


## Timeline-bewusste Quellen (RumorSources): Jahres-News, Hardware bald/neu,
## Software-Releases, neue Mailboxen, MOD-/Demo-Szene. Max. 2 neue pro Tag,
## gewichtet — der Hof soll leben, nicht überschwemmt werden.
func _seed_from_sources() -> void:
	var rng := _rng("sources")
	var pool: Array = RumorSources.candidates().filter(func(c: Dictionary) -> bool:
		return not _is_active(c["id"]) and not _seeded.has(c["id"]))
	var planted := 0
	while planted < 2 and not pool.is_empty():
		# gewichtete Auswahl (weight = wie heiß das Thema ist)
		var total := 0.0
		for c: Dictionary in pool:
			total += float(c.get("weight", 1.0))
		var roll := rng.randf() * total
		var chosen: Dictionary = pool[0]
		for c: Dictionary in pool:
			roll -= float(c.get("weight", 1.0))
			if roll <= 0.0:
				chosen = c
				break
		pool.erase(chosen)
		if bool(chosen.get("once", false)):
			_seeded[chosen["id"]] = true
		_seed_custom(chosen["id"], str(chosen.get("topic", "")),
			bool(chosen.get("truth", true)), chosen.get("texts", []))
		planted += 1


## Ausbreitung + Alterung. Ausgelaufene Gerüchte landen (wenn sie Fahrt
## aufgenommen haben) als Ergebnis am Schwarzen Brett.
func _spread() -> void:
	var rng := _rng("spread")
	var survivors: Array = []
	for r in active:
		r["reach"] = minf(1.0, float(r["reach"]) + 0.15 + rng.randf() * 0.12)
		var age: int = TimeManager.day_counter - int(r["born_day"])
		var done: bool = age > 9 or (r["reach"] >= 1.0 and age > 4)
		if done:
			if float(r["reach"]) >= 0.55:
				_resolve(r)
		else:
			survivors.append(r)
	active = survivors


func _resolve(r: Dictionary) -> void:
	var accurate: String = r["texts"][0] if not r["texts"].is_empty() else "?"
	resolved.push_front({"text": accurate, "truth": bool(r["truth"])})
	if resolved.size() > 6:
		resolved.resize(6)


# --------------------------------------------------------------- Aussaat

func _check_triggers() -> void:
	var wd := TimeManager.weekday()
	# Flohmarkt (Samstag): Mi–Fr macht das Gerücht die Runde, Sonntag ist es weg.
	if wd in [2, 3, 4]:
		_seed_template_by_id("flohmarkt")
	elif wd == 6:
		_drop_active("flohmarkt")
	# Jahres-Themen (einmalig, sobald das Jahr erreicht ist).
	for tpl in _templates:
		if tpl.get("trigger", "") == "jahr" and TimeManager.year >= int(tpl.get("year", 3000)):
			if not _seeded.has(tpl["id"]):
				_seed(tpl)
				_seeded[tpl["id"]] = true
	# Bestellung im Laden eingetroffen → wird zum Tagesgespräch.
	for a in OrderManager.arrived:
			var rid := "best_%s" % a.get("id", "")
			if not _seeded.has(rid):
				_seeded[rid] = true
				var item_name: String = a.get("name", "etwas")
				_seed_custom(rid, "hardware", true, [
					"Im Computerladen ist ein %s reingekommen — hab ich vom Verkäufer." % item_name,
					"Bei Gruber soll ein %s eingetroffen sein, sagt einer." % item_name,
					"Angeblich gibt's jetzt so ein %s im Laden. Oder war's woanders?" % item_name,
				])


## Ab und zu ein neues erfundenes Hof-Gerücht (max. 2 gleichzeitig aktiv).
func _seed_ambient(force: bool) -> void:
	var ambient_active := active.filter(func(r: Dictionary) -> bool:
		return r.get("topic", "") == "hype" or r.get("topic", "") == "klub")
	if ambient_active.size() >= 2:
		return
	var rng := _rng("ambient")
	if not force and rng.randf() > 0.34:
		return
	var pool := _templates.filter(func(t: Dictionary) -> bool:
		return t.get("trigger", "") == "ambient" and not _is_active(t["id"]))
	if pool.is_empty():
		return
	_seed(pool[rng.randi() % pool.size()])


# --------------------------------------------------------------- Seed-Helfer

func _seed_template_by_id(id: String) -> void:
	for tpl in _templates:
		if tpl.get("id", "") == id:
			_seed(tpl)
			return


func _seed(tpl: Dictionary) -> void:
	if _is_active(tpl.get("id", "")):
		return
	active.append({
		"id": tpl["id"], "topic": tpl.get("topic", ""), "truth": bool(tpl.get("truth", false)),
		"born_day": TimeManager.day_counter, "reach": 0.06, "texts": tpl.get("texts", []).duplicate(),
	})


func _seed_custom(id: String, topic: String, truth: bool, texts: Array) -> void:
	if _is_active(id):
		return
	active.append({"id": id, "topic": topic, "truth": truth,
		"born_day": TimeManager.day_counter, "reach": 0.06, "texts": texts})


func _is_active(id: String) -> bool:
	for r in active:
		if r.get("id", "") == id:
			return true
	return false


func _drop_active(id: String) -> void:
	active = active.filter(func(r: Dictionary) -> bool: return r.get("id", "") != id)


## Deterministischer Tages-RNG (kein globaler seed()-Nebeneffekt).
func _rng(salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(salt) ^ (TimeManager.day_counter * 2654435761)
	return rng


# --------------------------------------------------------------- Abfrage (UI)

func group_by_id(id: String) -> Dictionary:
	for g in groups:
		if g.get("id", "") == id:
			return g
	return {}


## Was diese Gruppe gerade weiß — als fertige Sätze in IHRER Verzerrung.
func rumors_for_group(group_id: String) -> Array:
	var g := group_by_id(group_id)
	if g.is_empty():
		return []
	var known := active.filter(func(r: Dictionary) -> bool:
		return float(r["reach"]) >= float(g.get("pickup", 0.3)))
	known.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["reach"]) > float(b["reach"]))
	var out: Array = []
	for r in known.slice(0, int(g.get("share", 2))):
		out.append(phrase(r, g))
	return out


## Ein Gerücht in der Färbung einer Gruppe: viel Ausbreitung + unzuverlässige
## Gruppe → entstelltere Variante (Stille-Post-Effekt).
func phrase(rumor: Dictionary, group: Dictionary) -> String:
	var texts: Array = rumor.get("texts", [])
	if texts.is_empty():
		return "…"
	var distortion := clampf(float(group.get("distort", 0.3)) + float(rumor["reach"]) * 0.45, 0.0, 1.0)
	var idx := int(round(distortion * float(texts.size() - 1)))
	return texts[clampi(idx, 0, texts.size() - 1)]


## Schwarzes Brett: was sich bestätigt hat bzw. bloß Gerücht war.
func notice_board() -> Array:
	return resolved


func has_fresh() -> bool:
	return not active.is_empty()


# --------------------------------------------------------------- Speichern

func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "resolved": resolved.duplicate(true),
		"seeded": _seeded.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", []).duplicate(true)
	resolved = d.get("resolved", []).duplicate(true)
	_seeded = d.get("seeded", {}).duplicate(true)
	rumors_changed.emit()
