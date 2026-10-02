class_name ListingTypeModel
extends RefCounted
## Deterministisches Modell fuer Magazin-Listings: Auswahl, Vergleich,
## Fehlerdiagnose und Wertung bleiben von der Darstellung getrennt testbar.

const LISTINGS := [
	{
		"id": "rasterstern", "title": "RASTERSTERN", "year_from": 1990,
		"description": "Ein kleiner Sternenhimmel mit wechselnden Farben.",
		"lines": [
			"SCREEN 320,200,16", "FOR I=1 TO 48", "X=RND(319)", "Y=RND(159)",
			"C=1+RND(14)", "PLOT X,Y,C", "NEXT I", "WAIT VBL", "GOTO 2"]
	},
	{
		"id": "diskindex", "title": "DISK-INDEX", "year_from": 1990,
		"description": "Sortiert kurze Diskettennamen fuer den Karteikasten.",
		"lines": [
			"DIM N$(8)", "FOR I=1 TO 8", "INPUT N$(I)", "NEXT I", "FOR A=1 TO 7",
			"FOR B=A+1 TO 8", "IF N$(B)<N$(A) THEN SWAP N$(A),N$(B)", "NEXT B",
			"NEXT A", "FOR I=1 TO 8:PRINT N$(I):NEXT I"]
	},
	{
		"id": "scrollgruss", "title": "SCROLL-GRUSS", "year_from": 1991,
		"description": "Laesst einen Szenegruss durch die Statuszeile laufen.",
		"lines": [
			"T$=\"GRUESSE AN DIE GANZE SZENE!   \"", "T$=T$+T$", "FOR X=1 TO 30",
			"S$=MID$(T$,X,24)", "LOCATE 2,22", "PRINT S$", "WAIT VBL",
			"NEXT X", "GOTO 3"]
	},
	{
		"id": "farbenmix", "title": "FARBENMIX", "year_from": 1992,
		"description": "Mischt eine ruhige 16-Farben-Palette fuer Pixelbilder.",
		"lines": [
			"DIM R(15),G(15),B(15)", "FOR C=0 TO 15", "R(C)=(C*3) MOD 16",
			"G(C)=(C*5) MOD 16", "B(C)=(C*7) MOD 16", "COLOR C,R(C),G(C),B(C)",
			"NEXT C", "FOR Y=0 TO 15", "BOX 20,Y*10+20,300,Y*10+28,Y", "NEXT Y"]
	},
]

var listing: Dictionary = {}
var difficulty := "lehrgang"
var run_seed := 0
var language:=&"basic"
var magazine_program := false


func configure(year: int, wins: int, round_seed: int) -> void:
	magazine_program = false
	run_seed = absi(round_seed)
	difficulty = "lehrgang" if wins == 0 else ("redaktion" if wins < 3 else "profi")
	var available: Array = LISTINGS.filter(func(d: Dictionary) -> bool:
		return year >= int(d.get("year_from", 1990)))
	if available.is_empty():
		available = LISTINGS.duplicate()
	listing = (available[run_seed % available.size()] as Dictionary).duplicate(true)
	var source:=target_text().to_upper();language=&"assembly"if("MOVE."in source or"$"in source)else(&"c"if("{"in source)else(&"amos"if"SCREEN"in source else&"basic"))
	listing["language"]=str(language)


## Bindet das Abtipp-Spiel an genau die Ausgabe, die der Spieler gerade liest.
## Der kanonische Source bleibt dabei unveraendert; nur die Papierdarstellung
## zerlegt ihn in Zeilen. Legacy-Aufrufer koennen weiter configure() verwenden.
func configure_from_magazine(entry: Dictionary, wins: int) -> void:
	magazine_program = true
	run_seed = absi(hash(str(entry.get("listing_id", "sommer_basic_listing"))))
	difficulty = "lehrgang" if wins == 0 else ("redaktion" if wins < 3 else "profi")
	var source := str(entry.get("canonical_source", "")).replace("\r\n", "\n")
	listing = {
		"id": str(entry.get("listing_id", "sommer_basic_listing")),
		"issue_id": str(entry.get("issue_id", "")),
		"title": str(entry.get("title_en", "LISTING")) if \
			TranslationServer.get_locale().begins_with("en") else str(entry.get("title_de", "LISTING")),
		"year_from": int(entry.get("year", 1990)),
		"description": "Sommer BASIC · Jahresprogramm %d/%d" % [
			int(entry.get("chapter", 1)), int(entry.get("count", 10))],
		"lines": Array(source.split("\n", true)),
		"language": "sommer basic",
		"hardware_profile": (entry.get("hardware_profile", {}) as Dictionary).duplicate(true),
	}
	language = &"sommer_basic"


func target_text() -> String:
	return "\n".join(PackedStringArray(listing.get("lines", [])))


func normalized(source: String) -> String:
	var text := source.replace("\r\n", "\n").replace("\r", "\n")
	var lines := text.split("\n", true)
	while not lines.is_empty() and str(lines[-1]).strip_edges() == "":
		lines.remove_at(lines.size() - 1)
	for i in lines.size():
		lines[i] = str(lines[i]).rstrip(" \t")
	return "\n".join(lines)


func diagnose(source: String) -> Dictionary:
	var typed := normalized(source).split("\n", true)
	var wanted := target_text().split("\n", true)
	var states: Array = []
	var errors := 0
	var chars_wrong := 0
	var first_error := -1
	var count := maxi(typed.size(), wanted.size())
	for i in count:
		var have := str(typed[i]) if i < typed.size() else ""
		var need := str(wanted[i]) if i < wanted.size() else ""
		var exact := have == need
		states.append("ok" if exact else ("missing" if have == "" else "error"))
		if not exact:
			errors += 1
			chars_wrong += _char_distance(have, need)
			if first_error < 0:
				first_error = i
	return {
		"exact": errors == 0 and typed.size() == wanted.size(),
		"errors": errors, "chars_wrong": chars_wrong, "first_error": first_error,
		"line_states": states, "line_count": wanted.size(),
	}


func assisted_copy() -> String:
	var lines: Array = listing.get("lines", []).duplicate()
	if lines.is_empty():
		return ""
	var typo_count := 2 if difficulty == "lehrgang" else 3
	for n in typo_count:
		var li := (run_seed + n * 3 + 1) % lines.size()
		var line := str(lines[li])
		var candidates: Array[int] = []
		for i in line.length():
			if line[i] != " " and line[i] != "\"":
				candidates.append(i)
		if candidates.is_empty():
			continue
		var ci: int = candidates[(run_seed + n * 5) % candidates.size()]
		var replacement := "0" if line[ci] != "0" else "O"
		lines[li] = line.substr(0, ci) + replacement + line.substr(ci + 1)
	return "\n".join(PackedStringArray(lines))


func score(checks: int, corrections: int, assisted: bool, hints: int) -> int:
	var base := 1200
	base -= maxi(0, checks - 1) * 55
	base -= corrections * 18
	base -= hints * 70
	if assisted:
		base -= 260
	return clampi(base, 100, 1200)


func _char_distance(a: String, b: String) -> int:
	var distance := absi(a.length() - b.length())
	for i in mini(a.length(), b.length()):
		if a[i] != b[i]:
			distance += 1
	return distance
