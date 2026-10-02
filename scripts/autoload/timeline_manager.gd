extends Node
## TimelineManager — das Living Timeline System (GDD Kap. 3).
## Lädt die Jahresschichten 1990–1999 aus data/timeline.json und aktiviert
## sie beim Jahreswechsel: Schlagzeilen-Event, Preisfaktor, Themen.
## Alle anderen Manager filtern ihre Inhalte über is_available() gegen
## year_available/year_obsolete — EIN Mechanismus für Shop, Events, Orte, Deko.

signal era_changed(year: int, data: Dictionary)

var start_year: int = 1990
var start_month: int = 7
var start_day: int = 6
var years: Dictionary = {}


func _ready() -> void:
	_load_data()
	TimeManager.year_changed.connect(_on_year_changed)


func _load_data() -> void:
	var file := FileAccess.open("res://data/timeline.json", FileAccess.READ)
	if file == null:
		push_error("timeline.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("timeline.json ist kein gueltiges JSON-Objekt!")
		return
	var data: Dictionary = parsed
	start_year = int(data.get("start_year", 1990))
	start_month = int(data.get("start_month", 7))
	start_day = int(data.get("start_day", 6))
	years = data.get("years", {})


## Jahresschicht als Dictionary (headline, news, price_factor, themes).
func year_data(p_year: int) -> Dictionary:
	return years.get(str(p_year), {})


func current_year_data() -> Dictionary:
	return year_data(TimeManager.year)


## Preisfaktor des aktuellen Jahres (Hardware wird über die Jahre billiger).
func price_factor() -> float:
	return float(current_year_data().get("price_factor", 1.0))


## Generischer Timeline-Filter: prüft year_available/year_obsolete eines
## beliebigen Daten-Dictionaries gegen das aktuelle Jahr.
func is_available(item: Dictionary) -> bool:
	var y := TimeManager.year
	var from := int(item.get("year_available", item.get("year_from", 1990)))
	var to := int(item.get("year_obsolete", item.get("year_to", 1999)))
	if y < from or y > to:
		return false
	# Saison-Sortiment (Zeit-Bibel): Feld "season" beschränkt auf eine Jahreszeit
	# (winter|spring/fruehling|summer/sommer|autumn/herbst) oder mehrere als Liste.
	if item.has("season"):
		var want: Variant = item["season"]
		var seasons: Array = want if want is Array else [want]
		var now := TimeManager.season_name().to_lower()
		var ok := false
		for s: String in seasons:
			var sl := str(s).to_lower()
			if sl == now or (sl in ["spring", "fruehling"] and now == "frühling") \
					or (sl == "summer" and now == "sommer") or (sl == "autumn" and now == "herbst") \
					or (sl == "winter" and now == "winter"):
				ok = true
		if not ok:
			return false
	return true


func _on_year_changed(p_year: int) -> void:
	var data := year_data(p_year)
	era_changed.emit(p_year, data)
	if data.is_empty():
		return
	# Jahreswechsel als Zeitungs-Schlagzeile präsentieren (World Memory:
	# die Welt lebt weiter, auch ohne den Spieler).
	var text := "*** %d ***\n%s\n\n" % [p_year, data.get("headline", "")]
	for line in data.get("news", []):
		text += "- %s\n" % line
	UIManager.open_info("Neues Jahr: %d" % p_year, text)
