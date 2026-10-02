extends Node
## MemoryManager — der MEMORY LAYER von SOMMER '90 (permanent, s.
## docs/LIFE_TIME_BIBLE.md): Das Spiel zeichnet besondere Momente als
## Erinnerungen auf (erste Hardware, Flohmarkt-Funde, besondere Tage) und lässt
## sie JAHRE SPÄTER wieder auftauchen — im INFOS-Ticker („Weißt du noch …?")
## und als Dialogzeilen von Freunden. Zeit wird dadurch emotional erfahrbar:
## Sommer '90 ist keine Simulation, sondern eine spielbare Erinnerung.

signal memory_recorded(memory: Dictionary)

const MAX_MEMORIES := 400          # älteste Alltags-Erinnerungen fallen raus
const RESURFACE_MIN_YEARS := 1     # erst ab 1 Jahr Abstand wieder auftauchen
const RESURFACE_CHANCE := 0.14     # Chance pro neuem Tag
const RESURFACE_COOLDOWN_DAYS := 3

var memories: Array = []           # {kind, text, year, month, day, season, (id, title)}
var _last_resurface_day := -99
var _milestones: Dictionary = {}   # id → true: Meilensteine nur EINMAL festhalten
var _catalog: Dictionary = {}      # id → {title, text} aus data/memory_events.json


func _ready() -> void:
	_load_catalog()
	TimeManager.day_changed.connect(_on_day_changed)
	TimeManager.year_changed.connect(_on_year_changed)


## Jahreswechsel → Rückblick aufs gerade vergangene Jahr (nur im Spiel, nur wenn es
## Erinnerungen gibt; das Dekaden-Ende 2000 übernimmt die Abspann-Statistik).
func _on_year_changed(new_year: int) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if new_year > 1999:
		return
	var finished := new_year - 1
	if bool(GameManager.flags.get("year_transition_reviewed_%d" % finished, false)):
		return
	if memories_for_year(finished).is_empty():
		return
	UIManager.open_year_review(finished)


func _load_catalog() -> void:
	var txt := FileAccess.get_file_as_string("res://data/memory_events.json")
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		_catalog = (parsed as Dictionary).get("events", {})


func reset() -> void:
	memories = []
	_last_resurface_day = -99
	_milestones = {}


## Einen Moment festhalten. kind: "hardware" | "flohmarkt" | "disk" | "musik" |
## "freund" | "ereignis" … (frei erweiterbar). text in Vergangenheitsform,
## damit er später als Erinnerung funktioniert („…gekauft", „…gefunden").
func record(kind: String, text: String) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return  # Sichttests/Proof-Hooks erzeugen keine Erinnerungen
	memories.append({
		"kind": kind, "text": text,
		"year": TimeManager.year, "month": TimeManager.month,
		"day": TimeManager.day, "season": TimeManager.season(),
	})
	if memories.size() > MAX_MEMORIES:
		memories.pop_front()
	memory_recorded.emit(memories.back())


## Montagen duerfen einen uebersprungenen, aber real stattgefundenen Termin an
## seinem echten Kalenderdatum festhalten. Das aktuelle TimeManager-Datum bleibt
## dabei unangetastet; der Rueckblick sortiert die Erinnerung korrekt ein.
func record_historical(kind: String, text: String, at_year: int, at_month: int, at_day: int) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	memories.append({
		"kind": kind, "text": text,
		"year": at_year, "month": at_month, "day": at_day,
		"season": int(at_month % 12 / 3.0),
	})
	if memories.size() > MAX_MEMORIES:
		memories.pop_front()
	memory_recorded.emit(memories.back())


## MEILENSTEIN einmalig festhalten (erste Kopie, erste Lötstunde …). Dedupe per id;
## Text sonst aus dem Katalog. Kurzer „★"-Toast + wird zur dauerhaften Erinnerung.
## Rückgabe: true, wenn es NEU war (Aufrufer kann daran eine Sonderreaktion hängen).
func record_once(id: String, text: String = "", title_override: String = "") -> bool:
	if _milestones.has(id):
		return false
	if GameManager.state != GameManager.State.PLAYING:
		return false   # Proof-Hooks/Sichttests halten keine Meilensteine fest
	_milestones[id] = true
	var cat: Dictionary = _catalog.get(id, {})
	# Dynamisch erzeugte Questfamilien (z. B. die neun Stefan-Trilogien) duerfen
	# ihren lesbaren Rueckblick direkt mitliefern. Fehlt beides, wird die ID
	# wenigstens menschenlesbar statt als interner Debug-Schluessel angezeigt.
	var fallback := id.replace("_", " ").capitalize()
	var txt := text if text != "" else str(cat.get("text", fallback))
	var title := title_override if title_override != "" else str(cat.get("title", fallback))
	memories.append({
		"kind": "meilenstein", "id": id, "title": title, "text": txt,
		"year": TimeManager.year, "month": TimeManager.month,
		"day": TimeManager.day, "season": TimeManager.season(),
	})
	if memories.size() > MAX_MEMORIES:
		memories.pop_front()
	memory_recorded.emit(memories.back())
	UIManager.toast("★ %s" % title)
	return true


func has_milestone(id: String) -> bool:
	return _milestones.has(id)


func milestone_count() -> int:
	return _milestones.size()


## Alle Erinnerungen eines Jahres (für den Jahres-Rückblick), Meilensteine zuerst.
func memories_for_year(year: int) -> Array:
	var out: Array = []
	for m: Dictionary in memories:
		if int(m.get("year", 0)) == year:
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var am := 1 if a.get("kind") == "meilenstein" else 0
		var bm := 1 if b.get("kind") == "meilenstein" else 0
		if am != bm:
			return am > bm
		return int(a.get("month", 0)) < int(b.get("month", 0)))
	return out


## Erinnerungen, die alt genug sind, um wieder aufzutauchen.
func resurfaceable() -> Array:
	var out: Array = []
	for m: Dictionary in memories:
		if TimeManager.year - int(m["year"]) >= RESURFACE_MIN_YEARS:
			out.append(m)
	return out


## Eine zufällige alte Erinnerung als Satz („Weißt du noch? 1991: …").
## Für Ticker UND Freund-Dialoge („Weißt du noch, als wir …?").
func remembrance_line() -> String:
	var pool := resurfaceable()
	if pool.is_empty():
		return ""
	var m: Dictionary = pool[randi() % pool.size()]
	return "Weißt du noch? %s %d: %s" % [
		TimeManager.SEASON_NAMES[int(m.get("season", 0))], int(m["year"]), str(m["text"])]


## Pro neuem Tag eine kleine Chance, dass eine alte Erinnerung im
## INFOS-Ticker auftaucht (nie aufdringlich, mit Abklingzeit).
func _on_day_changed() -> void:
	if TimeManager.day_counter - _last_resurface_day < RESURFACE_COOLDOWN_DAYS:
		return
	if randf() > RESURFACE_CHANCE:
		return
	var line := remembrance_line()
	if line == "":
		return
	_last_resurface_day = TimeManager.day_counter
	UIManager.toast(line)


func to_dict() -> Dictionary:
	return {"memories": memories, "last_resurface": _last_resurface_day,
		"milestones": _milestones.keys()}


func from_dict(d: Dictionary) -> void:
	memories = d.get("memories", [])
	_last_resurface_day = int(d.get("last_resurface", -99))
	_milestones = {}
	for id: Variant in d.get("milestones", []):
		_milestones[str(id)] = true
