class_name PortraitViseme
## Kleine, deterministische Mundform-Zuordnung fuer deutschen Bildschirmtext.
## Das ist bewusst keine Audio-Phonemerkennung: Der sichtbare Text ist die Uhr,
## Satzzeichen und Pausen schliessen den Mund zuverlässig.

const REST := "rest"
const MBP := "mbp"
const FV := "fv"
const AI := "ai"
const E := "e"
const OU := "ou"
const L := "l"
const SCH := "sch"
const ALL := [REST, MBP, FV, AI, E, OU, L, SCH]

const _REST_CHARS := " \t\r\n.,;:!?…-–—()[]{}<>/\\\"'„“‚‘»«+*=_%&@#"


static func valid(value: String) -> bool:
	return value in ALL


## Mundform fuer das Zeichen an einer Codepoint-Position. Mehrbuchstaben-Laute
## (`sch`, `ch`) werden ueber die Nachbarschaft erkannt.
static func for_text(text: String, index: int) -> String:
	if index < 0 or index >= text.length():
		return REST
	var current := text.substr(index, 1)
	var lower := text.to_lower()
	var start := maxi(0, index - 2)
	var around := lower.substr(start, mini(5, lower.length() - start))
	if "sch" in around or "ch" in around:
		var ch := current.to_lower()
		if ch in ["s", "c", "h"]:
			return SCH
	return for_grapheme(current)


static func for_grapheme(grapheme: String) -> String:
	if grapheme == "" or _is_rest(grapheme):
		return REST
	var c := grapheme.to_lower().substr(0, 1)
	if c in ["m", "b", "p"]:
		return MBP
	if c in ["f", "v", "w"]:
		return FV
	if c in ["a", "ä"]:
		return AI
	if c in ["e", "é", "è", "ê", "i", "y"]:
		return E
	if c in ["o", "ö", "u", "ü"]:
		return OU
	if c == "l":
		return L
	# Konsonanten sowie Ziffern bekommen die kleine aktive Sprechform. Damit
	# bleibt der Mund in Woertern lebendig, ohne zwischen Lauten aufzusperren.
	return SCH


static func _is_rest(grapheme: String) -> bool:
	for i in grapheme.length():
		if not (_REST_CHARS.contains(grapheme.substr(i, 1))):
			return false
	return true
