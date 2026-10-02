extends Node
## PlayerIdentity — wer der Spieler ist: Name, Geburtstag und der prozedurale
## Avatar (PortraitGen). Wird im Spielstart-Setup (NewGameSetup) gesetzt und ist
## Teil des Spielstands. Der Avatar ist wie alle Porträts permanent & prozedural
## (s. [[portrait-engine-principles]]): kein festes Bild, sondern Seed + Hints.
##
## Alters-Trick: age_base wird als (1990 − Geburtsjahr) in die Hints gelegt.
## PortraitGen rechnet age = age_base + (Jahr − 1990) = Jahr − Geburtsjahr, der
## Avatar altert also über das Jahrzehnt genau mit dem Spieler mit.

signal identity_changed

const AVATAR_CATALOG := preload("res://scripts/gfx/avatar_catalog.gd")

## Start-Alter im Sommer 1990. Der Spieler gibt nur Tag+Monat ein; das Geburtsjahr
## wird daraus abgeleitet, damit die 10 Jahre gut passen (Coming-of-Age: ~14 → ~23).
## Eine Zahl zum Tunen.
const START_AGE := 14

var player_name := "Kevin"
var birth_day := 12
var birth_month := 5
var birth_year := 1990 - START_AGE
var avatar_seed := "player"     # Basis-DNA; "Würfeln" wechselt den Seed
var avatar_hints: Dictionary = {}   # Merkmals-Overrides (skin, hair_style …)


func reset() -> void:
	player_name = "Kevin"
	birth_day = 12
	birth_month = 5
	birth_year = 1990 - START_AGE
	avatar_seed = "player"
	avatar_hints = {}
	identity_changed.emit()


## Geburtstag setzen — nur Tag+Monat vom Spieler; Jahr aus START_AGE abgeleitet.
func set_birthday(d: int, m: int) -> void:
	birth_day = clampi(d, 1, 31)
	birth_month = clampi(m, 1, 12)
	birth_year = 1990 - START_AGE


## Alter im gegebenen Jahr (Standard: aktuelles Spieljahr), Geburtstag
## berücksichtigt.
func age(in_year: int = -1) -> int:
	var y: int = TimeManager.year if in_year < 0 else in_year
	return age_at(y, TimeManager.month, TimeManager.day)


## Alter an einem konkreten historischen Datum. Anders als age(year) hängt ein
## Rückblick damit nicht vom Monat/Tag des gerade geladenen Spielstands ab.
func age_at(year: int, month: int, day: int) -> int:
	month = clampi(month, 1, 12)
	day = clampi(day, 1, TimeManager.days_in_month(year, month))
	var a := year - birth_year
	# Geburtstag im laufenden Jahr noch nicht gewesen? dann ein Jahr jünger. Der
	# effektive Tag ist auf den letzten gültigen Monatstag geklemmt (29.2.-Geborene,
	# damit das Alter am tatsächlich gefeierten Geburtstag stimmt — wie is_birthday_today).
	var eff_bday := mini(birth_day, TimeManager.days_in_month(year, birth_month))
	if month < birth_month or (month == birth_month and day < eff_bday):
		a -= 1
	return maxi(0, a)


func age_at_year_end(year: int) -> int:
	return age_at(year, 12, 31)


## Ist heute Geburtstag? (Hook für das Geburtstags-Event, s. Zeit-Bibel.) Ein am
## 29.2. Geborener (oder ein ungültiges Datum wie 31.4.) feiert am letzten gültigen
## Tag des Geburtsmonats — sonst gäbe es in Nicht-Schaltjahren nie Geburtstag.
func is_birthday_today() -> bool:
	if TimeManager.month != birth_month:
		return false
	var last := TimeManager.days_in_month(TimeManager.year, birth_month)
	return TimeManager.day == mini(birth_day, last)


func birthday_string() -> String:
	var month_name := TimeManager.localized_month_name(birth_month)
	if TranslationServer.get_locale().split("_")[0].to_lower() == "en":
		return "%s %d" % [month_name, birth_day]
	return "%d. %s" % [birth_day, month_name]


## Vollständige Porträt-Hints: gewählte Merkmale + korrektes Alter/Jahr + Extras
## (z. B. {"emotion":"happy"} oder ein festes {"year":1990} fürs Setup).
func hints(extra: Dictionary = {}) -> Dictionary:
	var h := avatar_hints.duplicate(true)
	h["age_base"] = 1990 - birth_year         # lässt den Avatar mitaltern
	h["year"] = TimeManager.year
	# Das Portrait soll am echten Geburtstag altern, nicht pauschal am 1. Januar.
	# NPCs ohne Geburtstag bleiben beim historischen Jahresmodell; der Spieler
	# besitzt dagegen ein exaktes Datum und liefert deshalb sein aktuelles Alter.
	h["age_now"] = age()
	for k in extra:
		h[k] = extra[k]
	return AVATAR_CATALOG.canonical_state(AVATAR_CATALOG.canonical_signature(h))


## Spieler und NPCs verwenden denselben nativen 32er-Renderer mit 128er Ausgabe.
func texture(extra: Dictionary = {}) -> ImageTexture:
	return texture_frame(extra, {})


## Animierter Spielerframe mit demselben Mund-/Lid-/Blickvertrag wie NPCs.
func texture_frame(state: Dictionary = {}, frame_state: Dictionary = {}) -> ImageTexture:
	return PortraitGen.for_npc(avatar_seed, hints(state), AVATAR_CATALOG.canonical_frame(frame_state))


## Gemeinsamer Managervertrag mit NPCManager. AnimatedPortrait ruft fuer beide
## Sprecherarten dieselbe Methode auf, damit auch der Spieler Viseme, Blick und
## Blinzeln statt eines statischen Fallbackbilds erhaelt.
func portrait_frame(state: Dictionary = {}, frame_state: Dictionary = {}) -> ImageTexture:
	return texture_frame(state, frame_state)


func texture_state_key(state: Dictionary = {}, frame_state: Dictionary = {}) -> String:
	return AVATAR_CATALOG.state_key(avatar_seed, hints(), state, frame_state)


func to_dict() -> Dictionary:
	return {
		"name": player_name, "bd": birth_day, "bm": birth_month, "by": birth_year,
		"seed": avatar_seed, "hints": avatar_hints,
	}


func from_dict(d: Dictionary) -> void:
	player_name = str(d.get("name", "Kevin"))
	birth_day = int(d.get("bd", 12))
	birth_month = int(d.get("bm", 5))
	birth_year = int(d.get("by", 1990 - START_AGE))
	avatar_seed = str(d.get("seed", "player"))
	var stored_hints: Variant = d.get("hints", {})
	avatar_hints = AVATAR_CATALOG.canonical_signature(stored_hints if typeof(stored_hints) == TYPE_DICTIONARY else {})
	identity_changed.emit()
