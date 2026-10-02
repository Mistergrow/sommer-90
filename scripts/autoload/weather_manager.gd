extends Node
## WeatherManager — das Wetter draußen (VFX-Bibel EFFECT_002).
##
## Der Zustand ist eine reine Funktion des Spieltags (day_counter): stabil über
## einen Tag, ändert sich zum nächsten, überlebt Speichern/Laden ohne eigenes
## Save-Feld. Sommerbias 1990er: meist schön, ab und zu Schauer oder Gewitter.
## Treibt das WeatherOverlay am Fenster (Regen, Glas, Gardinen) und liefert den
## Text fürs Intro/den Ticker.

signal weather_changed(state: String)

const STATES := ["clear", "clouds", "rain", "storm"]

## Für Regenmenge/Glaseintrübung und Gardinen-Wind je Zustand.
const RAIN := {"clear": 0.0, "clouds": 0.0, "rain": 0.6, "storm": 1.0}
const WIND := {"clear": 0.18, "clouds": 0.32, "rain": 0.55, "storm": 1.0}

var _last_emitted := ""
var _cached_day := -2147483648
var _cached_forced := ""
var _cached_state := ""


func _ready() -> void:
	TimeManager.day_changed.connect(_on_day_changed)
	call_deferred("_on_day_changed")  # Startwetter melden, wenn alles bereit ist


func _on_day_changed() -> void:
	_invalidate_cache()
	var s := state()
	if s != _last_emitted:
		_last_emitted = s
		weather_changed.emit(s)


## Aktueller Zustand — deterministisch aus dem Spieltag (oder DSS_WEATHER-Override).
func state() -> String:
	var forced := OS.get_environment("DSS_WEATHER")
	if forced not in STATES:
		forced = ""
	var current_day := TimeManager.day_counter
	if current_day == _cached_day and forced == _cached_forced \
			and not _cached_state.is_empty():
		return _cached_state
	_cached_day = current_day
	_cached_forced = forced
	if not forced.is_empty():
		_cached_state = forced
		return _cached_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED ^ (current_day * 2654435761)
	var r := rng.randf()
	if r < 0.45:
		_cached_state = "clear"
	elif r < 0.75:
		_cached_state = "clouds"
	elif r < 0.92:
		_cached_state = "rain"
	else:
		_cached_state = "storm"
	return _cached_state


func _invalidate_cache() -> void:
	_cached_day = -2147483648
	_cached_forced = ""
	_cached_state = ""


func is_raining() -> bool:
	return state() in ["rain", "storm"]


func is_storm() -> bool:
	return state() == "storm"


## 0 (trocken) … 1 (Wolkenbruch) — steuert Regendichte und Glaseintrübung.
func rain_intensity() -> float:
	return float(RAIN.get(state(), 0.0))


## 0 (windstill) … 1 (Sturm) — steuert die Gardinen-Bewegung.
func wind() -> float:
	return float(WIND.get(state(), 0.2))


func label() -> String:
	match state():
		"clear": return "heiter"
		"clouds": return "bewölkt"
		"rain": return "Regen"
		"storm": return "Gewitter"
	return "?"


## Stimmungsvoller Satz fürs Intro / den Ticker.
func description() -> String:
	match state():
		"clear": return "Draußen scheint die Sonne. Drinnen wartet der Computer."
		"clouds": return "Draußen hängt der Himmel grau. Drinnen wartet der Computer."
		"rain": return "Draußen regnet es. Drinnen wartet der Computer."
		"storm": return "Draußen tobt ein Gewitter. Drinnen wartet der Computer."
	return "Drinnen wartet der Computer."
