extends Node
## TimeManager — Kalender und Tagesrhythmus von SOMMER '90.
## PERMANENTES KERNSYSTEM, s. docs/LIFE_TIME_BIBLE.md:
## Jahre → Jahreszeiten → Wochen → Tage → 5 Zeitfenster (Morgen, Mittag,
## Nachmittag, Abend, Nacht). ERINNERUNGS-, keine Zeitsimulation: Die Struktur
## und die Zahl der Entscheidungen bleiben 1990–1999 IDENTISCH — was sich
## ändert, ist die VERFÜGBARKEIT (Schule blockiert den Morgen, Ferien geben
## ihn frei) und die Zahl der OPTIONEN (die Welt wächst mit dem Alter).
## Älterwerden nimmt NIE Zeit weg. Spielstart: Freitag, 6. Juli 1990 (letzter
## Grundschultag, Sommerferien). Hauptspiel endet 31.12.1999, 23:59 — danach
## Freies Spiel (GameManager hört auf year_changed). Der Kalender ist
## vollwertig (Wochentage, Monate, Jahreswechsel) für die Living Timeline.

signal slot_changed(slot: int)
signal day_changed
signal season_changed(season: int)
signal year_changed(year: int)
## Ein kuratierter Kalendertag kann mehrere unsichtbare Montagetage vertreten.
## Es gibt trotzdem nur EIN day_changed-Signal; elapsed_days altert Lieferungen,
## Cooldowns und Geruechte ueber day_counter korrekt weiter.
signal calendar_jumped(from_date: Dictionary, to_date: Dictionary, elapsed_days: int, reason: String)
## Feuert, nachdem der letzte Sommertag atomar auf den 31.12. montiert wurde.
## UI/Inszenierung darf darauf den Rueckblick und die Silvestersequenz oeffnen.
signal year_finale_ready(finished_year: int)

## Die 5 Zeitfenster eines Tages (permanent, s. Zeit-Bibel). Struktur ändert
## sich NIE — nur die Verfügbarkeit (Schule/Ferien) und die Optionen.
const SLOT_NAMES := ["Morgen", "Mittag", "Nachmittag", "Abend", "Nacht"]
# Eine gemeinsame Uhrzeit-Wahrheit fuer HUD, Workbench-Uhr und dynamische
# Uhren in Locations. Werte sind Minuten seit Mitternacht. Seit dem Minuten-
# Umbau stehen sie in time_clock.gd; hier bleibt nur der Verweis, damit
# job_manager.gd unveraendert TimeManager.SLOT_CLOCK_MINUTES weiterliest.
const TimeClock := preload("res://scripts/autoload/time_clock.gd")
const SLOT_CLOCK_MINUTES := TimeClock.SLOT_ANCHORS
const WEEKDAYS := ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
const MONTHS := ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
	"August", "September", "Oktober", "November", "Dezember"]
const DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const SEASON_NAMES := ["Winter", "Frühling", "Sommer", "Herbst"]

var year: int = 1990
var month: int = 7   # 1–12
var day: int = 6     # 1–31
## Minuten seit Mitternacht — seit dem Umbau die EINZIGE Zeitwahrheit des Tages.
## Das Zeitfenster wird daraus abgeleitet, nie umgekehrt gespeichert.
var minute_of_day: int = TimeClock.SLOT_ANCHORS[0]

## Zeitfenster als abgeleitete Groesse (Index in SLOT_NAMES). Lesen liefert immer
## den zur aktuellen Minute passenden Block; Schreiben springt auf dessen
## Ankerzeit. Damit kann es keinen Drift zwischen Uhr und Fenster geben, und die
## zehn Stellen, die slot direkt setzen (main.gd, Vorschau-Werkzeuge, sechs
## Tests), funktionieren unveraendert weiter. Wie bisher loest ein direktes
## Setzen KEIN slot_changed aus — das tun nur advance_* und from_dict.
var slot: int:
	get:
		return TimeClock.slot_for_minute(minute_of_day)
	set(value):
		minute_of_day = TimeClock.slot_start(value)
var day_counter: int = 0  # Tage seit Spielstart (für Cooldowns/Wochenlogik)

const CAMPAIGN_PACING_PATH := "res://data/campaign_pacing.json"
const CAMPAIGN_PACING_SCHEMA := 1
var _pacing: Dictionary = {}

## Zeitkosten der Handlungen. Alle Zahlen stehen in data/time_costs.json; im Code
## bleiben nur die Vorgabewerte fuer den Fall, dass die Datei fehlt.
const TIME_COSTS_PATH := "res://data/time_costs.json"
var _time_costs: Dictionary = {}
## Minuten, die die Nacht ab 23:10 noch hergibt. 0 laesst die Uhr am Nachtanker
## stehen — genau das Verhalten vor dem Minuten-Umbau.
var night_budget_minutes: int = 170
## Wechselkurs fuer use_energy-Aufrufe ohne eigene Kennung.
var fallback_minutes_per_energy: float = 5.0
## Globaler Regler fuer das Nachziehen nach einer Telemetrie-Messung.
var global_minute_scale: float = 1.0
# Jahr → kuratierte Spieltage. QuestManager fragt den Kalender pro evaluate für
# JEDE Quest ab; der Aufbau ist rein aus _pacing abgeleitet und damit cachebar.
# Rückgabe-Arrays gelten als NUR-LESEN (kein Aufrufer mutiert sie).
var _campaign_dates_cache: Dictionary = {}


func _ready() -> void:
	_load_campaign_pacing()
	_load_time_costs()


## Liest die Zeitkosten. Fehlt die Datei, bleiben die Vorgabewerte stehen und das
## Spiel laeuft weiter — eine fehlende Preisliste darf nie den Start verhindern.
func _load_time_costs() -> void:
	if not FileAccess.file_exists(TIME_COSTS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIME_COSTS_PATH))
	if not parsed is Dictionary:
		push_error("time_costs.json ist kein gueltiges JSON-Objekt.")
		return
	_time_costs = parsed
	night_budget_minutes = maxi(0, int(_time_costs.get("night_budget_minutes", night_budget_minutes)))
	fallback_minutes_per_energy = maxf(0.0,
		float(_time_costs.get("fallback_minutes_per_energy", fallback_minutes_per_energy)))
	global_minute_scale = maxf(0.0,
		float(_time_costs.get("global_minute_scale", global_minute_scale)))


## Zeitkosten einer benannten Handlung in Minuten. Ohne Eintrag greift der
## Energie-Wechselkurs; ohne beides kostet die Handlung nichts. Der globale
## Regler wirkt auf jeden Weg, damit ein Nachziehen nur EINE Zahl braucht.
func action_minutes(action: String, energy_cost: int = 0) -> int:
	var tabelle: Variant = _time_costs.get("action_minutes", {})
	var roh := 0.0
	if tabelle is Dictionary and (tabelle as Dictionary).has(action):
		roh = float((tabelle as Dictionary)[action])
	elif energy_cost > 0:
		roh = float(energy_cost) * fallback_minutes_per_energy
	return TimeClock.round_cost(roh * global_minute_scale)


func _load_campaign_pacing() -> void:
	_campaign_dates_cache.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN_PACING_PATH))
	if not parsed is Dictionary:
		push_error("campaign_pacing.json fehlt oder ist ungueltig; linearer Kalender bleibt aktiv.")
		_pacing = {}
		return
	_pacing = parsed
	if int(_pacing.get("schema_version", 0)) != CAMPAIGN_PACING_SCHEMA:
		push_error("campaign_pacing.json hat eine unbekannte Schema-Version.")
		_pacing = {}


## Startdatum aus timeline.json übernehmen (von GameManager.new_game gerufen).
func setup_start(p_year: int, p_month: int, p_day: int) -> void:
	year = p_year
	month = p_month
	day = p_day
	slot = 0
	day_counter = 0
	slot_changed.emit(slot)


## Wochentag 0=Montag..6=Sonntag (Zeller-Kongruenz, damit auch ein
## geänderter Startjahrgang in timeline.json korrekte Wochentage liefert).
func weekday() -> int:
	return weekday_for_date(year, month, day)


## Reine Kalenderfunktion fuer Prognosen (z. B. Oeffnungszeit bei Ankunft).
static func weekday_for_date(p_year: int, p_month: int, p_day: int) -> int:
	var m := p_month
	var y := p_year
	if m < 3:
		m += 12
		y -= 1
	var k := y % 100
	var j := int(y / 100.0)
	var h := (p_day + int(13 * (m + 1) / 5.0) + k + int(k / 4.0) + int(j / 4.0) + 5 * j) % 7
	# Zeller: 0=Samstag → auf 0=Montag umrechnen
	return (h + 5) % 7


func weekday_name() -> String:
	return WEEKDAYS[weekday()]


## Lokalisierte Anzeigevariante fuer UI-Flaechen. weekday_name() bleibt als
## stabiler interner/Legacy-Vertrag erhalten, damit Datenlogik nie von der
## aktuell gewaehlten Sprache abhaengt.
func localized_weekday_name() -> String:
	var index := weekday()
	return Loc.t("calendar.weekday.%d" % index, WEEKDAYS[index])


## Lokalisierte Anzeigevariante fuer Monatsnamen. MONTHS bleibt die stabile
## deutsche Autoren-/Datenquelle und darf nicht direkt in UI-Flaechen landen.
func localized_month_name(p_month: int = month) -> String:
	var safe_month := clampi(p_month, 1, 12)
	return Loc.t("calendar.month.%02d" % safe_month, MONTHS[safe_month - 1])


## Samstag/Sonntag? (Samstag = Erkundungstag, Sonntag = langsamer Tag.)
func is_weekend() -> bool:
	return weekday() >= 5


## Jahreszeit 0=Winter 1=Frühling 2=Sommer 3=Herbst (Dez–Feb = Winter usw.).
## Jede Jahreszeit ändert Wetter, Sortimente, NPC-Abläufe, Events (Bibel).
func season() -> int:
	return int((month % 12) / 3.0)


func season_name() -> String:
	return SEASON_NAMES[season()]


## Alle Schulferien als feste Fenster (Monat/Tag). Ostern/Pfingsten sind real
## beweglich — fürs Spiel genügen wiedererkennbare, jedes Jahr gleiche Zeiträume.
## In den Ferien ruht die Schule: der Morgen-Block ist frei, der Schulhof leert
## sich, mehr ist in der Stadt los.
const SCHOOL_HOLIDAYS := [
	{"name": "Weihnachtsferien", "from": [12, 23], "to": [12, 31]},
	{"name": "Weihnachtsferien", "from": [1, 1], "to": [1, 6]},
	{"name": "Osterferien", "from": [4, 2], "to": [4, 16]},
	{"name": "Pfingstferien", "from": [5, 21], "to": [5, 25]},
	{"name": "Sommerferien", "from": [7, 6], "to": [8, 16]},
	{"name": "Herbstferien", "from": [10, 15], "to": [10, 28]},
]


static func _in_md_range(m: int, d: int, from_md: Array, to_md: Array) -> bool:
	var cur := m * 100 + d
	return cur >= int(from_md[0]) * 100 + int(from_md[1]) and cur <= int(to_md[0]) * 100 + int(to_md[1])


## Sind gerade Schulferien (egal welche)?
func is_school_holiday() -> bool:
	for h: Dictionary in SCHOOL_HOLIDAYS:
		if _in_md_range(month, day, h["from"], h["to"]):
			return true
	return false


## Name der aktuellen Ferien ("" wenn Schulzeit) — für Anzeige/Atmosphäre.
func holiday_name() -> String:
	for h: Dictionary in SCHOOL_HOLIDAYS:
		if _in_md_range(month, day, h["from"], h["to"]):
			return str(h["name"])
	return ""


## Sommerferien: der große Block (Freibad, Sommer-Events hängen daran).
func is_summer_vacation() -> bool:
	return _in_md_range(month, day, [7, 6], [8, 16])


## Schulmorgen? Schule belegt den Morgen-Block — außer am Wochenende und in
## JEDEN Ferien (nicht nur Sommer).
func is_school_morning() -> bool:
	return slot == 0 and not is_weekend() and not is_school_holiday()


## Lebensphase des Spielers — EINE Quelle für alle Systeme (Zeit-Bibel:
## Älterwerden schaltet Möglichkeiten frei, nimmt nie Zeit). Getrieben von den
## Lebensweg-Flags der Quest-Kette (q_ausbildung/q_gesellenpruefung/q_erster_job).
func life_phase() -> String:
	var f: Dictionary = GameManager.flags
	if bool(f.get("erster_job", false)):
		return "berufstaetig"
	if bool(f.get("gesellenbrief", false)):
		return "geselle"
	if bool(f.get("ausbildung_start", false)):
		return "azubi"
	return "schueler"


## Was belegt den MORGEN-Block an Werktagen (Ferien/Urlaub + Wochenende frei)?
## "" = frei. Schüler → Schule · Azubi → Betrieb/Berufsschule · Job → Arbeit.
## Geselle ohne festen Job hat den Morgen frei (Übergangsphase, Jobsuche).
func morning_duty() -> String:
	if is_weekend() or is_school_holiday():
		return ""   # Ferien gelten in jeder Phase als Urlaub (Sommer bleibt frei!)
	match life_phase():
		"schueler":     return "Schule"
		"azubi":        return "Betrieb & Berufsschule"
		"berufstaetig": return "Arbeit"
	return ""


const NIGHT_SLOT := 4   # letzter Zeitblock (Nacht) = SLOT_NAMES.size() - 1


## Zeit um n Blöcke vorrücken — kappt in der NACHT. Der Tag rollt NICHT mehr von
## selbst in den nächsten über: die Uhr bleibt nachts stehen, und der Spieler
## beendet den Tag AKTIV im Bett (sleep()). Damit gibt es kein überraschendes
## „durchgemacht" mehr — man verliert nie ungewollt einen Tag.
## Zeit um n MINUTEN vorruecken — das neue Grundprimitiv. Kappt am Tagesende
## (Nachtanker plus Nachtbudget); der Tag rollt NICHT von selbst um.
##
## Kann nie fehlschlagen und gibt nichts zurueck: Zeit ist ein Tor VOR einer
## Handlung, niemals ein Abbruchgrund danach. Die 34 use_energy-Stellen behandeln
## "zu muede" als Abbruch — duerfte Zeit dasselbe, scheiterten Handlungen mitten
## im Vollzug.
##
## Hunger wird weiterhin an der Fenstergrenze verbucht (11 je Block). Sobald
## Handlungen Minuten kosten, schieben sie den Spieler ohnehin ueber die Grenze —
## der alte Umgehungstrick ("20 Dinge in einem Fenster") ist damit tot, ohne dass
## die Hungerkurve angefasst werden muss.
func advance_minutes(count: int) -> void:
	var before_slot := slot
	minute_of_day = mini(TimeClock.day_end(night_budget_minutes),
		minute_of_day + maxi(0, count))
	var after_slot := slot
	if after_slot != before_slot:
		PlayerStats.change_stat("hunger", (after_slot - before_slot) * 11)
		PlaytestTelemetry.note_slots_advanced(after_slot - before_slot)
		slot_changed.emit(after_slot)


## Bis zum n-ten naechsten Zeitfenster vorruecken. Bleibt als duenner Aufsatz auf
## advance_minutes erhalten, damit die bestehenden Aufrufer (Reisen, Jobs,
## Events, Internetcafe) und vier Tests unveraendert weiterlaufen.
func advance_slot(count: int = 1) -> void:
	var ziel := mini(NIGHT_SLOT, slot + maxi(0, count))
	advance_minutes(maxi(0, TimeClock.slot_start(ziel) - minute_of_day))


## Ist gerade Nacht (letzter Block)? Dann steht die Uhr — nur Schlafen bringt
## den nächsten Tag.
func is_night() -> bool:
	return slot >= NIGHT_SLOT


## Wie viele Zeitfenster bleiben heute noch (bis zur Nacht)?
func slots_left() -> int:
	return maxi(0, NIGHT_SLOT - slot)


## Passt eine Aktion mit `count` Zeitfenstern noch in den heutigen Tag, ohne die
## Nacht zu überschreiten? Nachts (slots_left()==0) ist Schluss — Zeit fürs Bett.
func fits_today(count: int) -> bool:
	return count <= 0 or slots_left() >= count


## Seiteneffektfreie Vorschau fuer Reisen/Termin-UIs. Verwendet exakt dieselbe
## Monats- und Schaltjahrlogik wie der echte Kalender, emittiert aber nichts.
func preview_after_slots(count: int) -> Dictionary:
	# Zeit kappt in der Nacht (kein automatischer Tageswechsel) — die Ankunft
	# bleibt am selben Tag. So stimmt die Reise-Vorschau mit advance_slot überein.
	var p_slot := mini(NIGHT_SLOT, slot + maxi(count, 0))
	return {"year": year, "month": month, "day": day, "slot": p_slot,
		"weekday": weekday_for_date(year, month, day)}


func slots_crossed_after_minutes(count: int) -> int:
	return maxi(0, int(preview_after_minutes(count).get("slot", slot)) - slot)


## Schlafen: Im Hauptspiel zum naechsten KURATIERTEN Ferientag. Nach dem
## letzten Sommertag folgt die Montage zum 31.12.; dort bleibt die Zeit stehen,
## bis die Silvester-UI complete_year_transition() explizit bestaetigt.
## Rueckgabe false = am Jahresende blockiert, es wurde kein Tag verbraucht.
func sleep() -> bool:
	if _campaign_year_active(year):
		if is_year_end_pending():
			return false
		var target := _next_campaign_sleep_target()
		if not target.is_empty():
			var reason := "year_finale" if _same_md(target, _year_end_md()) else "curated_day"
			PlaytestTelemetry.note_sleep_start()
			_commit_calendar_jump(target, reason)
			PlayerStats.energie = 100
			PlayerStats.hunger = clampi(PlayerStats.hunger + 12, 0, 100)
			PlayerStats.stats_changed.emit()
			slot_changed.emit(slot)
			if reason == "year_finale":
				year_finale_ready.emit(year)
			return true
	PlaytestTelemetry.note_sleep_start()
	_next_day()
	PlayerStats.energie = 100
	PlayerStats.hunger = clampi(PlayerStats.hunger + 12, 0, 100)
	PlayerStats.stats_changed.emit()
	slot_changed.emit(slot)
	return true


## Einzige autorisierte Kampagnen-Jahresgrenze. Die Silvestersequenz ruft diese
## Methode an ihrem Ende auf. 1990–1998 springen auf den 6.7. des Folgejahres;
## 1999 springt ebenso auf den 6.7.2000 und aktiviert ueber year_changed den
## bestehenden Abspann/Freies-Spiel-Pfad. Kein sleep() kann dies umgehen.
func complete_year_transition() -> bool:
	if not is_year_end_pending():
		return false
	var target_year := year + 1
	var start_md := _next_year_start_md()
	PlaytestTelemetry.note_year_transition(target_year)
	_commit_calendar_jump({"year": target_year, "month": int(start_md[0]), "day": int(start_md[1])},
		"explicit_year_transition")
	slot_changed.emit(slot)
	return true


func is_year_end_pending() -> bool:
	return _campaign_year_active(year) and month == int(_year_end_md()[0]) \
		and day == int(_year_end_md()[1])


func is_curated_campaign_day() -> bool:
	if not _campaign_year_active(year):
		return false
	for date: Dictionary in campaign_dates_for_year(year):
		if int(date["month"]) == month and int(date["day"]) == day:
			return true
	return false


func is_last_campaign_day() -> bool:
	var dates := campaign_dates_for_year(year)
	if dates.is_empty():
		return false
	var last: Dictionary = dates.back()
	return month == int(last["month"]) and day == int(last["day"])


## 1..24 am spielbaren Sommertag, sonst 0. Praktische UI-Schnittstelle fuer
## Kapitelanzeige, Quest-Pacing und Jahresrueckblick.
func campaign_day_number() -> int:
	var dates := campaign_dates_for_year(year)
	for i in range(dates.size()):
		var date: Dictionary = dates[i]
		if month == int(date["month"]) and day == int(date["day"]):
			return i + 1
	return 0


func campaign_progress() -> Dictionary:
	var total := campaign_dates_for_year(year).size() if _campaign_year_active(year) else 0
	var per_week := int(_pacing.get("summer_window", {}).get("playable_days_per_week", 4))
	var day_number := campaign_day_number()
	return {
		"phase": campaign_phase(),
		"day": day_number,
		"total_days": total,
		"week": int((day_number - 1) / float(per_week)) + 1 if day_number > 0 else 0,
		"year": year,
	}


func campaign_phase() -> String:
	if _pacing.is_empty() or year < int(_pacing.get("campaign_year_from", 1990)):
		return "pre_campaign"
	if year > int(_pacing.get("campaign_year_to", 1999)):
		return "free_play"
	if is_year_end_pending():
		return "year_end"
	if is_curated_campaign_day():
		return "summer"
	return "montage"


## Balancing-Metadaten fuer Kalender-/Rueckblick-UI und Telemetrie. Inhalt
## bleibt datengetrieben und muss nicht im UI dupliziert werden.
func campaign_pacing_target() -> Dictionary:
	var window: Dictionary = _pacing.get("summer_window", {})
	return {
		"weeks": int(window.get("weeks", 6)),
		"days_per_week": int(window.get("playable_days_per_week", 4)),
		"minutes_per_day": int(_pacing.get("target_minutes_per_playable_day", 10)),
		"hours_per_year": float(_pacing.get("target_hours_per_full_year", 4.0)),
	}


## Erzeugt die 24 Daten aus den Regeln der JSON-Datei. Jede der sechs
## Sieben-Tage-Wochen behält die erforderlichen Wochentage (Fr/Sa/So). Der
## vierte Platz ist ein Randanker: in Woche 1 hat der Kampagnenstart, in Woche 6
## das Kampagnenende Vorrang. So bleiben sowohl 6.7. als auch 16.8. erhalten,
## ohne einen festen Clubabend aus dem spielbaren Kalender zu schneiden.
func campaign_dates_for_year(p_year: int) -> Array:
	if not _campaign_year_active(p_year):
		return []
	if _campaign_dates_cache.has(p_year):
		return _campaign_dates_cache[p_year]
	var window: Dictionary = _pacing.get("summer_window", {})
	var start: Array = window.get("start", [7, 6])
	var weeks := int(window.get("weeks", 6))
	var week_days := int(window.get("calendar_days_per_week", 7))
	var playable := int(window.get("playable_days_per_week", 4))
	var selection: Dictionary = window.get("selection", {})
	var anchors: Array = selection.get("anchor_offsets", [0, 6])
	var required_weekdays: Array = selection.get("required_weekdays", [4, 5, 6])
	var fill_offsets: Array = selection.get("fill_offsets", [3, 2, 4, 1, 5, 0, 6])
	var dates: Array = []
	var summer_start := {"year": p_year, "month": int(start[0]), "day": int(start[1])}
	for week in range(weeks):
		var week_start := _date_after_days(summer_start, week * week_days)
		var offsets: Array[int] = []
		for raw_weekday: Variant in required_weekdays:
			var wanted := int(raw_weekday)
			for offset in range(week_days):
				var candidate := _date_after_days(week_start, offset)
				if weekday_for_date(int(candidate["year"]), int(candidate["month"]), int(candidate["day"])) == wanted:
					_append_unique_offset(offsets, offset, week_days)
					break
		# JSON-Zahlen kommen als float. Fuer membership/erase zuerst strikt auf
		# int normalisieren, sonst wird der priorisierte Offset 6 je nach Build
		# nicht im Array gefunden und der 16.8. faellt aus der letzten Woche.
		var ordered_anchors: Array[int] = []
		for raw_anchor: Variant in anchors:
			ordered_anchors.append(int(raw_anchor))
		var priority_anchor := week_days - 1 if week == weeks - 1 else 0
		if priority_anchor in ordered_anchors:
			ordered_anchors.erase(priority_anchor)
			ordered_anchors.push_front(priority_anchor)
		for raw: Variant in ordered_anchors:
			if offsets.size() >= playable:
				break
			_append_unique_offset(offsets, int(raw), week_days)
		for raw: Variant in fill_offsets:
			if offsets.size() >= playable:
				break
			_append_unique_offset(offsets, int(raw), week_days)
		offsets.sort()
		for i in range(mini(playable, offsets.size())):
			dates.append(_date_after_days(week_start, offsets[i]))
	_campaign_dates_cache[p_year] = dates
	return dates


func _campaign_year_active(p_year: int) -> bool:
	return not _pacing.is_empty() and p_year >= int(_pacing.get("campaign_year_from", 1990)) \
		and p_year <= int(_pacing.get("campaign_year_to", 1999))


func _next_campaign_sleep_target() -> Dictionary:
	var current_ordinal := _date_ordinal(year, month, day)
	for target: Dictionary in campaign_dates_for_year(year):
		if _date_ordinal(int(target["year"]), int(target["month"]), int(target["day"])) > current_ordinal:
			return target
	var finale := {"year": year, "month": int(_year_end_md()[0]), "day": int(_year_end_md()[1])}
	if _date_ordinal(year, int(finale["month"]), int(finale["day"])) > current_ordinal:
		return finale
	return {}


func _commit_calendar_jump(target: Dictionary, reason: String) -> void:
	var from := {"year": year, "month": month, "day": day}
	var old_year := year
	var old_season := season()
	var elapsed := maxi(1, _date_ordinal(int(target["year"]), int(target["month"]), int(target["day"])) \
		- _date_ordinal(year, month, day))
	year = int(target["year"])
	month = int(target["month"])
	day = int(target["day"])
	slot = 0
	day_counter += elapsed
	if year != old_year:
		year_changed.emit(year)
	if season() != old_season:
		season_changed.emit(season())
	calendar_jumped.emit(from, {"year": year, "month": month, "day": day}, elapsed, reason)
	day_changed.emit()


func _year_end_md() -> Array:
	return _pacing.get("year_end", [12, 31])


func _next_year_start_md() -> Array:
	return _pacing.get("next_year_start", [7, 6])


func _same_md(date: Dictionary, md: Array) -> bool:
	return int(date.get("month", 0)) == int(md[0]) and int(date.get("day", 0)) == int(md[1])


func _append_unique_offset(offsets: Array[int], offset: int, week_days: int) -> void:
	if offset >= 0 and offset < week_days and not offset in offsets:
		offsets.append(offset)


static func _date_after_days(source: Dictionary, amount: int) -> Dictionary:
	var result := {"year": int(source["year"]), "month": int(source["month"]), "day": int(source["day"])}
	for _i in range(maxi(0, amount)):
		result["day"] += 1
		if int(result["day"]) > _days_in_month_static(int(result["year"]), int(result["month"])):
			result["day"] = 1
			result["month"] += 1
			if int(result["month"]) > 12:
				result["month"] = 1
				result["year"] += 1
	return result


static func _date_ordinal(p_year: int, p_month: int, p_day: int) -> int:
	var previous_year := p_year - 1
	var total := previous_year * 365 + floori(previous_year / 4.0) \
		- floori(previous_year / 100.0) + floori(previous_year / 400.0)
	for m in range(1, p_month):
		total += _days_in_month_static(p_year, m)
	return total + p_day


## Oeffentlicher, seiteneffektfreier Montagehelfer: liegt ein echtes Datum im
## Sprungintervall (Start exklusiv, Ziel inklusiv)? Damit koennen Geburtstage,
## Feiertage und Release-Termine verarbeitet werden, ohne hunderte day_changed-
## Signale zu simulieren.
static func date_crossed(from_date: Dictionary, to_date: Dictionary,
		p_year: int, p_month: int, p_day: int) -> bool:
	var candidate := _date_ordinal(p_year, p_month, p_day)
	return candidate > _date_ordinal(int(from_date["year"]), int(from_date["month"]), int(from_date["day"])) \
		and candidate <= _date_ordinal(int(to_date["year"]), int(to_date["month"]), int(to_date["day"]))


static func _days_in_month_static(p_year: int, p_month: int) -> int:
	if p_month == 2 and is_leap_year(p_year):
		return 29
	return DAYS_IN_MONTH[p_month - 1]


## Gregorianische Schaltjahrregel (durch 4, außer volle Jahrhunderte, außer durch 400).
## Für 1990–1999 wäre `% 4` genug, aber so ist es auch im Freien Spiel (2000+) korrekt.
static func is_leap_year(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)


## Tage eines Monats mit korrektem 29. Februar. EINE Quelle für TimeManager UND
## TaskManager (Terminvorschau), damit die Kalenderrechnung nicht auseinanderläuft.
func days_in_month(y: int, m: int) -> int:
	if m == 2 and is_leap_year(y):
		return 29
	return DAYS_IN_MONTH[m - 1]


func _next_day() -> void:
	var old_season := season()
	slot = 0
	day += 1
	day_counter += 1
	var days_this_month := days_in_month(year, month)
	if day > days_this_month:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
			year_changed.emit(year)
	if season() != old_season:
		season_changed.emit(season())
	day_changed.emit()


func date_string() -> String:
	var locale := TranslationServer.get_locale().split("_")[0].to_lower()
	if locale == "en":
		return "%s, %s %d, %d" % [localized_weekday_name(), localized_month_name(), day, year]
	return "%s, %d. %s %d" % [localized_weekday_name(), day, localized_month_name(), year]


func slot_name() -> String:
	return SLOT_NAMES[slot]


## Lokalisierte Anzeigevariante fuer Fenster und HUD.
func localized_slot_name() -> String:
	return Loc.t("calendar.slot.%d" % slot, SLOT_NAMES[slot])


## Die echte Uhrzeit. Frueher sprang sie in fuenf Stufen; seit dem Umbau laeuft
## sie minutengenau — die Zeigeruhren an den Ortswaenden und der Workbench-Wecker
## lesen diese Funktion bereits und werden dadurch ohne eine Codezeile lebendig.
func clock_minutes() -> int:
	return minute_of_day


func clock_string() -> String:
	return TimeClock.format(minute_of_day)


## Wie viele Minuten gibt der heutige Tag noch her (bis Nachtanker plus Budget)?
func minutes_left() -> int:
	return maxi(0, TimeClock.day_end(night_budget_minutes) - minute_of_day)


## Passt eine Handlung dieser Dauer heute noch? Das Gegenstueck zu fits_today,
## nur in Minuten.
func fits_minutes(count: int) -> bool:
	return count <= 0 or minutes_left() >= count


## Schaffe ich das noch vor einer Deadline? Der Einzeiler fuer Ladenschluss,
## Marktende, Clubabend und Termine.
func can_finish_before(dauer: int, deadline_minute: int) -> bool:
	return minute_of_day + maxi(0, dauer) <= deadline_minute


## Seiteneffektfreie Vorschau in Minuten — fuer Ankunftszeiten und Preisanzeigen.
func preview_after_minutes(count: int) -> Dictionary:
	var ziel := mini(TimeClock.day_end(night_budget_minutes),
		minute_of_day + maxi(0, count))
	return {"year": year, "month": month, "day": day,
		"slot": TimeClock.slot_for_minute(ziel), "minute": ziel,
		"clock": TimeClock.format(ziel),
		"weekday": weekday_for_date(year, month, day)}


## "slot" bleibt im Spielstand, obwohl es abgeleitet ist: aeltere Spielstaende
## und externe Werkzeuge lesen es. "minute" kommt additiv dazu.
func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day, "slot": slot,
		"minute": minute_of_day, "day_counter": day_counter}


func from_dict(d: Dictionary) -> void:
	year = int(d.get("year", 1990))
	month = int(d.get("month", 7))
	day = int(d.get("day", 6))
	day_counter = int(d.get("day_counter", 0))
	# Ein Spielstand ohne "minute" stammt aus der Zeit vor dem Umbau. Er landet
	# exakt auf der Ankerzeit seines Zeitfensters — kein Sprung, kein Verlust.
	var gespeicherter_slot := int(d.get("slot", 0))
	minute_of_day = int(d.get("minute", TimeClock.slot_start(gespeicherter_slot)))
	slot_changed.emit(slot)
