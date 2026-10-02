class_name Loc
extends Node
## Loc — Lokalisierungsfassade von "Sommer '90".
##
## Quellsprache ist Deutsch. Der deutsche Text steht weiterhin in den
## Datendateien und im Code; die Uebersetzungskataloge liegen unter res://locale/
## und werden ueber den TranslationServer geladen.
##
## Warum eine eigene Fassade statt blossem tr():
##   1. RUECKFALL. Godots tr() gibt bei fehlendem Schluessel den SCHLUESSEL
##      zurueck — der Spieler saehe dann "ui.bank.deposit" im Fenster. Hier faellt
##      stattdessen auf den deutschen Quelltext zurueck, notfalls auf einen
##      mitgegebenen Ersatztext. Ein fehlender Schluessel ist ein Uebersetzungs-
##      rueckstand, kein sichtbarer Defekt.
##      Dazu gehoert project.godot: internationalization/locale/allow_fallback ist
##      AUS (Godot 4.8, vorher nicht abschaltbar). Sonst beantwortet der
##      TranslationServer einen in en fehlenden Schluessel selbst — still mit der
##      deutschen KATALOG-Zeile. Zwei Nachteile: die Katalogzeile kann gegenueber
##      data/ veraltet sein (genau das prueft localization_check Punkt 6/7), und
##      _missing bliebe leer, weil t() den Rueckstand nie zu sehen bekaeme. Mit
##      abgeschaltetem Engine-Rueckfall gewinnt der Quelltext AM AUFRUFORT, der
##      per Definition aktuell ist, und der Rueckstand wird protokolliert.
##      ACHTUNG seit dem Wechsel auf Godot 4.7.2-stable: Die Einstellung existiert
##      dort noch nicht und wird ignoriert, der Engine-Rueckfall ist also AN. Da
##      der en-Katalog vollstaendig ist, sehen Spieler keinen Unterschied; mit
##      4.8-stable greift die Zeile in project.godot wieder automatisch.
##   2. SPRACHWECHSEL IM LAUF. Viele Fenster setzen ihren Text nur einmal beim
##      Aufbau. locale_changed gibt ihnen das Signal, sich neu aufzubauen.
##   3. SCHRIFTGRENZE. Die Amiga-Bildschirme zeichnen mit Topaz, und Topaz kennt
##      exakt Latin-1 (221 Glyphen, U+0000..U+00FF). Sprachen mit Zeichen
##      darueber hinaus — Polnisch, Tschechisch, Tuerkisch, Russisch, Griechisch,
##      Japanisch — koennen auf diesen Schirmen physisch nicht dargestellt werden.
##      Die Sprachliste folgt deshalb aus der Schrift, nicht aus dem Wunsch.
##   4. PRUEFBARKEIT. Der Pseudo-Modus laengt jeden Text kuenstlich, damit
##      Layoutbrueche VOR der ersten echten Uebersetzung auffallen.

signal locale_changed(locale: String)

const SOURCE_LOCALE := "de"
const CATALOG_DIR := "res://locale"

## Sprachen, die BEIDE Schriften tragen (Topaz fuer die Amiga-Schirme, VT323 fuer
## die Zimmer-UI). Nur diese sind vollstaendig darstellbar.
const FULL_LOCALES := ["de", "en", "fr", "es", "it", "nl", "da", "nb", "sv", "fi"]

## Sprachen, die VT323 traegt, Topaz aber nicht. Waehlbar erst, wenn eine
## Amiga-Schrift mit erweitertem Zeichensatz vorliegt.
const UI_ONLY_LOCALES := ["pl", "cs", "hu", "tr", "ro"]

const LOCALE_NAMES := {
	"de": "Deutsch", "en": "English", "fr": "Français", "es": "Español",
	"it": "Italiano", "nl": "Nederlands", "da": "Dansk", "nb": "Norsk",
	"sv": "Svenska", "fi": "Suomi",
}

## Zeigt statt der Uebersetzung den Schluessel — findet Texte, die noch nicht
## durch Loc laufen.
static var show_keys := false
## Laengt jeden Text auf 130 % und rahmt ihn — findet Layoutbrueche, bevor eine
## echte Uebersetzung existiert.
static var pseudo := false

static var _missing: Dictionary = {}


func _ready() -> void:
	# SettingsManager bietet value()/set_value(), NICHT get_value(). Der Schluessel
	# "locale" muss zudem in dessen DEFAULTS stehen, sonst liefert value() null.
	var wanted := SOURCE_LOCALE
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_method("value"):
		var stored: Variant = settings.call("value", "locale")
		if stored != null and not str(stored).is_empty():
			wanted = str(stored)
	set_locale(wanted)


## Alle Sprachen, fuer die ein Katalog vorliegt UND die die Schrift traegt.
func available_locales() -> Array[String]:
	var out: Array[String] = [SOURCE_LOCALE]
	for code: String in TranslationServer.get_loaded_locales():
		var base := code.split("_")[0]
		if base in FULL_LOCALES and base not in out:
			out.append(base)
	return out


func locale() -> String:
	return TranslationServer.get_locale().split("_")[0]


func locale_name(code := "") -> String:
	var key := code if not code.is_empty() else locale()
	return str(LOCALE_NAMES.get(key, key.to_upper()))


## Sprache umstellen. Gibt false zurueck, wenn die Schrift sie nicht traegt —
## dann bleibt die alte Sprache stehen, statt Kaestchen anzuzeigen.
func set_locale(code: String) -> bool:
	var base := code.split("_")[0]
	if base not in FULL_LOCALES:
		push_warning("Loc: '%s' wird von den Spielschriften nicht getragen." % code)
		return false
	# Auch eine erneut gewaehlte Sprache ist ein ausdruecklicher UI-Refresh.
	# Mehrere Fenster erzeugen ihren Amiga-/Retro-Chrome dynamisch und koennen
	# noch Texte aus einer zuvor aktiven Sprache tragen. Der fruehere Early Return
	# liess genau solche halb uebersetzten Fenster dauerhaft stehen.
	if locale() != base:
		TranslationServer.set_locale(base)
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_method("set_value"):
		settings.call("set_value", "locale", base)
	else:
		push_warning("Loc: Sprachwahl konnte nicht gespeichert werden.")
	locale_changed.emit(base)
	return true


## Uebersetzt einen Schluessel. `source` ist der deutsche Quelltext und dient als
## Rueckfall — dadurch steht nie ein roher Schluessel im Bild.
static func t(key: String, source := "") -> String:
	if show_keys:
		return "«%s»" % key
	var value := str(TranslationServer.translate(key))
	if value == key or value.is_empty():
		# Kein Katalogeintrag: Rueckfall auf den Quelltext, Rueckstand vermerken.
		if not _missing.has(key):
			_missing[key] = source
		value = source if not source.is_empty() else key
	return _decorate(value)


## Uebersetzt mit Platzhaltern: t_format("ui.disk.left", "Noch %d Disketten", [3]).
## Die Argumente werden NACH der Uebersetzung eingesetzt, damit eine Sprache die
## Reihenfolge aendern darf.
static func t_format(key: String, source: String, args: Array) -> String:
	return t(key, source) % args


## Ein- oder Mehrzahl. Godots tr_n braucht eine Katalogform mit Pluralregel;
## solange die nicht existiert, entscheidet der Zaehler hier zwischen zwei
## Quelltexten. Das ist bewusst simpel — Sprachen mit mehr als zwei Pluralformen
## brauchen spaeter den echten Katalogweg.
static func t_plural(key: String, one: String, many: String, count: int) -> String:
	var chosen_key := "%s.one" % key if count == 1 else "%s.many" % key
	return t(chosen_key, one if count == 1 else many) % count


static func _decorate(value: String) -> String:
	if not pseudo:
		return value
	# Kuenstliche Laengung auf etwa 130 %, damit enge Layouts auffallen.
	var padding := "~".repeat(maxi(1, int(value.length() * 0.3)))
	return "[%s%s]" % [value, padding]


## Alle Schluessel, die zur Laufzeit angefragt wurden, aber im Katalog fehlen.
## Die Schutztests lesen das aus.
static func missing_keys() -> Dictionary:
	return _missing.duplicate()


static func clear_missing() -> void:
	_missing.clear()
