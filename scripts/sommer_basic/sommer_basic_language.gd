class_name SommerBasicLanguage
extends RefCounted
## Gemeinsame Sprachdefinition fuer Editor, Compiler und Zeitschriften-Listings.
## Die Analyse ist absichtlich zustandsfrei: derselbe Quelltext liefert im
## Editor, in Tests und beim Build dieselben Meldungen.

const FeatureCatalog := preload("res://scripts/data/sommer_basic_feature_catalog.gd")
const GameCatalog := preload("res://scripts/data/sommer_game_module_catalog.gd")

const CORE_COMMANDS := [
	"PRINT", "INPUT", "LET", "IF", "FOR", "NEXT", "WHILE", "WEND",
	"GOTO", "GOSUB", "RETURN", "CALL", "FUNCTION", "SUB", "DIM", "TYPE",
	"DATA", "READ", "RESTORE", "END", "STOP", "REM", "CLS", "WAIT",
]
const GRAPHICS_COMMANDS := [
	"SCREEN", "WINDOW", "PALETTE", "PLOT", "LINE", "BOX", "CIRCLE",
	"BLIT", "SPRITE", "BOB", "TILEMAP", "SCROLL", "FLIP",
]
const AUDIO_COMMANDS := [
	"SAMPLE", "PLAY", "CHANNEL", "VOLUME", "PAN", "MODPLAY", "MODSTOP",
]
const FILE_COMMANDS := [
	"OPEN", "CLOSE", "GET", "PUT", "SEEK", "BANK", "LOADBANK",
	"SPRITEBANK", "SAMPLEBANK", "MAPBANK", "PRINT#", "INPUT#",
]
const ENGINE_COMMANDS := [
	"GAMESTART", "GAMESTOP", "LOADMAP", "LOADSPRITES", "ADDPLAYER",
	"UPDATEPLAYERS", "DRAWWORLD", "SAVEGAME", "LOADGAME", "ANIMATE",
	"MIXSOUND", "ADVSTATE", "DIALOGUE", "DEBUGBREAK", "DEBUGVALUE",
	"SETTILE", "MAPLAYER", "DESTROYTERRAIN", "FIREPROJECTILE",
	"UPDATEPHYSICS", "EMITPARTICLES", "CAMERA", "AISTEP", "GUIWINDOW",
	"GUITEXT", "SIMULATE", "NETWORKSYNC", "ZONE", "POWERLINK",
	"TRAFFICROUTE", "COLORPIPE", "TARGETVIDEO", "EXPORTBUILD", "PROFILEFRAME",
]
const FUNCTIONS := [
	"ABS", "ASC", "CHR$", "COS", "EOF", "INT", "JOY", "JOYX", "JOYY",
	"KEY$", "LEFT$", "LEN", "MID$", "MOUSEBUTTON", "MOUSEX", "MOUSEY",
	"RND", "RIGHT$", "SIN", "SQR", "STR$", "TAN", "VAL",
	"GAMEACTIVE", "COLLIDE", "FRAMECOST", "GETTILE", "TERRAINHEIGHT",
	"PROJECTILECOUNT", "PARTICLECOUNT", "POPULATION", "CITYMONEY",
	"NETPLAYERS", "POWERED", "TRAFFIC", "BUILDVERSION",
]
const KEYWORDS := [
	"THEN", "ELSE", "TO", "STEP", "AS", "AND", "OR", "NOT", "MOD",
	"TRUE", "FALSE",
]
const TYPES := [
	"INTEGER", "FLOAT", "STRING", "BOOLEAN", "BYTE", "WORD", "LONG",
]
## Der Enterprise-Kern besitzt fuer jeden oeffentlich beworbenen Befehl eine
## echte Laufzeitsemantik. Ein spaeter gesperrtes Hardwareprofil wird nicht
## durch stilles Ignorieren simuliert, sondern separat als Featurediagnose
## gemeldet.
const IMPLEMENTED_COMMANDS := CORE_COMMANDS + GRAPHICS_COMMANDS + AUDIO_COMMANDS + FILE_COMMANDS + ENGINE_COMMANDS

static func commands() -> PackedStringArray:
	var result := PackedStringArray()
	result.append_array(CORE_COMMANDS)
	result.append_array(GRAPHICS_COMMANDS)
	result.append_array(AUDIO_COMMANDS)
	result.append_array(FILE_COMMANDS)
	result.append_array(ENGINE_COMMANDS)
	return result


static func signature_for(word: String) -> String:
	var signature := str({
		"PRINT": "PRINT Ausdruck [; Ausdruck ...]",
		"INPUT": "INPUT [\"Frage\";] Variable [, Variable ...]",
		"LET": "LET Variable = Ausdruck",
		"IF": "IF Bedingung THEN Anweisung [ELSE Anweisung]",
		"FOR": "FOR Variable = Start TO Ende [STEP Schritt]",
		"NEXT": "NEXT [Variable]",
		"WHILE": "WHILE Bedingung  ...  WEND",
		"GOTO": "GOTO Zeilennummer",
		"GOSUB": "GOSUB Zeilennummer  ...  RETURN",
		"CALL": "CALL Unterprogramm [(Argumente)]",
		"FUNCTION": "FUNCTION Name(Parameter) ... RETURN Ausdruck ... END FUNCTION",
		"SUB": "SUB Name ... END SUB",
		"DIM": "DIM Feld(Groesse) | Variable AS Datentyp",
		"TYPE": "TYPE Name ... Feld AS Datentyp ... END TYPE",
		"DATA": "DATA Wert [, Wert ...]",
		"READ": "READ Variable [, Variable ...]",
		"RESTORE": "RESTORE [Zeilennummer]",
		"SCREEN": "SCREEN Breite, Hoehe [, Farben]",
		"WINDOW": "WINDOW X, Y, Breite, Hoehe [, Titel]",
		"PALETTE": "PALETTE Index, Farbe",
		"PLOT": "PLOT X, Y [, Farbe]",
		"LINE": "LINE X1, Y1, X2, Y2 [, Farbe]",
		"BOX": "BOX X, Y, Breite, Hoehe [, Farbe]",
		"CIRCLE": "CIRCLE X, Y, Radius [, Farbe]",
		"BLIT": "BLIT Bank, QuelleX, QuelleY, Breite, Hoehe, ZielX, ZielY",
		"SPRITE": "SPRITE Nummer, X, Y, Bild [, Sichtbar]",
		"BOB": "BOB Nummer, X, Y, Bild",
		"TILEMAP": "TILEMAP Bank, Breite, Hoehe [, Tilegroesse]",
		"SCROLL": "SCROLL X, Y",
		"MODPLAY": "MODPLAY Dateiname",
		"OPEN": "OPEN Dateiname FOR Modus AS Kanal",
		"BANK": "BANK Nummer, Bytes",
		"LOADBANK": "LOADBANK Nummer, Dateiname",
	}.get(word.to_upper(), ""))
	if signature.is_empty():
		signature = str(FeatureCatalog.feature_by_symbol(word).get("signature", ""))
	if signature.is_empty() and not GameCatalog.module_for_symbol(word).is_empty():
		signature = GameCatalog.signature_for(word)
	return signature


static func is_runtime_supported(word: String) -> bool:
	return IMPLEMENTED_COMMANDS.has(word.to_upper())


static func analyze(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var numbered_lines: Dictionary = {}
	var jumps: Array[Dictionary] = []
	var block_stack: Array[Dictionary] = []
	var lines := source.split("\n", true)
	for line_index in lines.size():
		var original := str(lines[line_index])
		var body := original.strip_edges()
		if body.is_empty():
			continue
		if _has_open_string(body):
			_add(diagnostics, line_index, maxi(1, original.length()), "E101",
				"Zeichenkette ist nicht geschlossen.", "error")
			continue
		body = _without_comment(body)
		if body.is_empty():
			continue
		var numbered := _take_line_number(body)
		var line_number := int(numbered.get("number", -1))
		body = str(numbered.get("body", body)).strip_edges()
		if line_number >= 0:
			if numbered_lines.has(line_number):
				_add(diagnostics, line_index, 1, "E102",
					"Zeilennummer %d ist doppelt vergeben." % line_number, "error")
			else:
				numbered_lines[line_number] = line_index
		if body.is_empty():
			continue
		for raw_statement in _split_statements(body):
			_analyze_statement(str(raw_statement).strip_edges(), line_index,
				diagnostics, jumps, block_stack)

	for jump in jumps:
		var target := int(jump["target"])
		if not numbered_lines.has(target):
			_add(diagnostics, int(jump["line"]), int(jump["column"]), "E220",
				"Sprungziel %d existiert nicht." % target, "error")
	while not block_stack.is_empty():
		var opening: Dictionary = block_stack.pop_back()
		_add(diagnostics, int(opening["line"]), 1, "E310",
			"%s wurde nicht abgeschlossen." % str(opening["word"]), "error")
	diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["line"]) < int(b["line"]) or \
			(int(a["line"]) == int(b["line"]) and int(a["column"]) < int(b["column"])))
	var errors := diagnostics.filter(func(d: Dictionary) -> bool:
		return str(d.get("severity", "")) == "error").size()
	return {
		"ok": errors == 0,
		"errors": errors,
		"warnings": diagnostics.size() - errors,
		"diagnostics": diagnostics,
		"line_count": lines.size(),
		"numbered_lines": numbered_lines,
	}


## Kombiniert die zustandsfreie Sprachpruefung mit dem historischen
## Jahres-/Hardwarevertrag. Editor, RUN und Build erhalten dadurch dieselben
## harten Sperren statt spaetere Befehle still auf alter Hardware auszufuehren.
static func analyze_for_profile(source: String, year: int,
		target_profile_id := "", unlocked_game_modules: Array = []) -> Dictionary:
	var result := analyze(source)
	var diagnostics: Array[Dictionary] = []
	for raw_diagnostic: Variant in result.get("diagnostics", []):
		if raw_diagnostic is Dictionary:
			diagnostics.append((raw_diagnostic as Dictionary).duplicate(true))
	for usage: Dictionary in _feature_usages(source):
		var state := FeatureCatalog.availability(str(usage.get("symbol", "")),
			year, target_profile_id)
		if bool(state.get("available", false)):
			continue
		var feature: Dictionary = state.get("feature", {})
		_add(diagnostics, int(usage.get("line", 0)), int(usage.get("column", 1)),
			"E420", _availability_message(state, feature), "error")
	for usage: Dictionary in _game_feature_usages(source):
		var game_state := GameCatalog.available(str((usage.get("module", {}) as Dictionary).get("id", "")),
			year, target_profile_id, unlocked_game_modules)
		if bool(game_state.get("available", false)):
			continue
		_add(diagnostics, int(usage.get("line", 0)), int(usage.get("column", 1)),
			"E440", _game_availability_message(str(usage.get("symbol", "")), game_state), "error")
	_append_profile_limit_diagnostics(source, year, diagnostics)
	diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["line"]) < int(b["line"]) or \
			(int(a["line"]) == int(b["line"]) and int(a["column"]) < int(b["column"])))
	var errors := diagnostics.filter(func(d: Dictionary) -> bool:
		return str(d.get("severity", "")) == "error").size()
	result["ok"] = errors == 0
	result["errors"] = errors
	result["warnings"] = diagnostics.size() - errors
	result["diagnostics"] = diagnostics
	result["year"] = year
	var annual := FeatureCatalog.annual_profile(year)
	result["version"] = str(annual.get("version", "?"))
	result["hardware_profile"] = target_profile_id if not target_profile_id.is_empty() \
		else str(annual.get("hardware_profile", ""))
	return result


static func _game_feature_usages(source: String) -> Array[Dictionary]:
	var usages: Array[Dictionary] = []
	var seen: Dictionary = {}
	var lines := source.split("\n", true)
	for line_index in lines.size():
		var body := _without_comment(str(lines[line_index]))
		body = str(_take_line_number(body.strip_edges()).get("body", body))
		if body.strip_edges().to_upper().begins_with("REM"):
			continue
		var quoted := false
		var token := ""
		var token_start := 0
		for index in range(body.length() + 1):
			var character := body[index] if index < body.length() else " "
			if character == "\"":
				if not token.is_empty():
					_append_game_usage(token, line_index, token_start, seen, usages)
					token = ""
				quoted = not quoted
				continue
			if quoted:
				continue
			if _is_feature_token_character(character):
				if token.is_empty():
					token_start = index
				token += character
			elif not token.is_empty():
				_append_game_usage(token, line_index, token_start, seen, usages)
				token = ""
	return usages


static func _append_game_usage(token: String, line_index: int, column: int,
		seen: Dictionary, usages: Array[Dictionary]) -> void:
	var symbol := token.to_upper()
	var module := GameCatalog.module_for_symbol(symbol)
	if module.is_empty():
		return
	var key := "%d:%s" % [line_index, symbol]
	if seen.has(key):
		return
	seen[key] = true
	usages.append({"symbol": symbol, "module": module, "line": line_index,
		"column": column + 1})


static func _feature_usages(source: String) -> Array[Dictionary]:
	var usages: Array[Dictionary] = []
	var seen: Dictionary = {}
	var lines := source.split("\n", true)
	for line_index in lines.size():
		var original := str(lines[line_index])
		var body := _without_comment(original)
		var numbered := _take_line_number(body.strip_edges())
		body = str(numbered.get("body", body))
		if body.strip_edges().to_upper().begins_with("REM"):
			continue
		var quoted := false
		var token := ""
		var token_start := 0
		for index in range(body.length() + 1):
			var character := body[index] if index < body.length() else " "
			if character == "\"":
				if not token.is_empty():
					_append_feature_usage(token, line_index, token_start, seen, usages)
					token = ""
				quoted = not quoted
				continue
			if quoted:
				continue
			if _is_feature_token_character(character):
				if token.is_empty():
					token_start = index
				token += character
			elif not token.is_empty():
				_append_feature_usage(token, line_index, token_start, seen, usages)
				token = ""
	return usages


static func _append_feature_usage(token: String, line_index: int, column: int,
		seen: Dictionary, usages: Array[Dictionary]) -> void:
	var symbol := token.to_upper()
	if FeatureCatalog.feature_by_symbol(symbol).is_empty():
		return
	var key := "%d:%s" % [line_index, symbol]
	if seen.has(key):
		return
	seen[key] = true
	usages.append({"symbol": symbol, "line": line_index, "column": column + 1})


static func _is_feature_token_character(character: String) -> bool:
	return character == "_" or character == "$" or character == "#" \
		or (character >= "A" and character <= "Z") \
		or (character >= "a" and character <= "z") \
		or (character >= "0" and character <= "9")


static func _availability_message(state: Dictionary, feature: Dictionary) -> String:
	var symbol := str(feature.get("symbol", "Feature"))
	match str(state.get("reason", "")):
		"not_released_yet":
			return "%s wird erst im Sommer %d freigeschaltet." % [symbol,
				int(state.get("required_year", 0))]
		"hardware_too_weak":
			return "%s braucht ein staerkeres Zielsystem (%s)." % [symbol,
				str(state.get("required_hardware_profile", ""))]
		"hardware_not_introduced":
			return "Das Zielsystem fuer %s existiert in diesem Jahr noch nicht." % symbol
		"module_not_installed":
			return "%s gehoert zu einem noch nicht installierten Modul." % symbol
		"year_out_of_range":
			return "Sommer BASIC unterstuetzt den angegebenen Sommer nicht."
		_:
			return "%s ist fuer dieses Jahr/Zielsystem nicht verfuegbar." % symbol


static func _game_availability_message(symbol: String, state: Dictionary) -> String:
	var module: Dictionary = state.get("module", {})
	var module_name := str(module.get("name_de", module.get("id", "Sommer Game")))
	match str(state.get("reason", "")):
		"not_released_yet":
			return "%s wird mit %s erst im Sommer %d entwickelt." % [symbol,
				module_name, int(module.get("year", 1990))]
		"hardware_too_weak":
			return "%s braucht fuer %s das Zielprofil %s." % [symbol, module_name,
				str(module.get("hardware_profile", ""))]
		"module_not_unlocked":
			return "%s gehoert zu %s. Entwickle und integriere das Modul zuerst in Sommer Game." % [symbol, module_name]
		"dependency_missing":
			return "%s wartet noch auf das Modul %s." % [symbol,
				str(state.get("dependency", ""))]
		_:
			return "%s ist in Sommer Game noch nicht einsatzbereit." % symbol


static func _append_profile_limit_diagnostics(source: String, year: int,
		diagnostics: Array[Dictionary]) -> void:
	var annual := FeatureCatalog.annual_profile(year)
	if annual.is_empty():
		return
	var limits: Dictionary = annual.get("limits", {})
	var lines := source.split("\n", true)
	var max_lines := int(limits.get("max_source_lines", 0))
	if max_lines > 0 and lines.size() > max_lines:
		_add(diagnostics, max_lines, 1, "E430",
			"Das Projekt hat %d Zeilen; Sommer BASIC %s erlaubt %d." % [
			lines.size(), str(annual.get("version", "?")), max_lines], "error")
	for line_index in lines.size():
		var body := _without_comment(str(lines[line_index])).strip_edges()
		body = str(_take_line_number(body).get("body", body)).strip_edges()
		for raw_statement: String in _split_statements(body):
			var statement := raw_statement.strip_edges()
			var word := _first_word(statement)
			var arguments := _split_arguments(statement.substr(word.length()).strip_edges())
			if word == "SCREEN" and arguments.size() >= 2:
				_check_literal_limit(arguments[0], int(limits.get("max_screen_width", 0)),
					"Bildbreite", line_index, diagnostics)
				_check_literal_limit(arguments[1], int(limits.get("max_screen_height", 0)),
					"Bildhoehe", line_index, diagnostics)
				if arguments.size() >= 3:
					_check_literal_limit(arguments[2], int(limits.get("max_colors", 0)),
						"Farben", line_index, diagnostics)
			elif word == "BANK" and arguments.size() >= 2:
				_check_literal_limit(arguments[1], int(limits.get("max_bank_kb", 0)) * 1024,
					"Bankgroesse in Bytes", line_index, diagnostics)


static func _check_literal_limit(value_text: String, maximum: int, label: String,
		line_index: int, diagnostics: Array[Dictionary]) -> void:
	if maximum <= 0 or not value_text.strip_edges().is_valid_int():
		return
	var value := int(value_text.strip_edges())
	if value > maximum:
		_add(diagnostics, line_index, 1, "E431",
			"%s %d ueberschreitet das Profilmaximum %d." % [label, value, maximum],
			"error")


static func _analyze_statement(statement: String, line_index: int,
		diagnostics: Array[Dictionary], jumps: Array[Dictionary],
		block_stack: Array[Dictionary]) -> void:
	if statement.is_empty():
		return
	var upper := statement.to_upper()
	if upper.begins_with("REM ") or upper == "REM":
		return
	var word := _first_word(upper)
	if word.is_empty():
		return
	var active_block := "" if block_stack.is_empty() else str(block_stack.back().get("word", ""))
	if active_block == "TYPE" and word != "END":
		if upper.find(" AS ") < 1:
			_add(diagnostics, line_index, 1, "E234",
				"TYPE-Feld braucht Name AS Datentyp.", "error")
		return
	if not commands().has(word):
		if statement.contains("=") and _is_lvalue(statement.get_slice("=", 0)):
			return
		_add(diagnostics, line_index, 1, "E200",
			"Unbekannter Befehl: %s" % word, "error")
		return
	if not is_runtime_supported(word):
		_add(diagnostics, line_index, 1, "E410",
			"%s ist bekannt, aber das benötigte Sommer-BASIC-Modul ist noch nicht installiert." % word,
			"error")
		return

	match word:
		"GOTO", "GOSUB":
			var target_text := statement.substr(word.length()).strip_edges()
			if not target_text.is_valid_int():
				_add(diagnostics, line_index, word.length() + 2, "E210",
					"%s erwartet eine Zeilennummer." % word, "error")
			else:
				jumps.append({"line": line_index, "column": word.length() + 2,
					"target": int(target_text)})
		"FOR":
			if not statement.contains("=") or upper.find(" TO ") < 0:
				_add(diagnostics, line_index, 1, "E230",
					"FOR braucht Variable = Start TO Ende.", "error")
			else:
				block_stack.append({"word": "FOR", "line": line_index})
		"NEXT":
			_close_block("FOR", "NEXT", line_index, diagnostics, block_stack)
		"WHILE":
			if statement.substr(5).strip_edges().is_empty():
				_add(diagnostics, line_index, 1, "E231",
					"WHILE braucht eine Bedingung.", "error")
			else:
				block_stack.append({"word": "WHILE", "line": line_index})
		"WEND":
			_close_block("WHILE", "WEND", line_index, diagnostics, block_stack)
		"FUNCTION", "SUB", "TYPE":
			var name := statement.substr(word.length()).strip_edges().get_slice("(", 0).strip_edges()
			if not _is_identifier(name):
				_add(diagnostics, line_index, word.length() + 2, "E235",
					"%s braucht einen gueltigen Namen." % word, "error")
			else:
				block_stack.append({"word": word, "line": line_index})
		"END":
			var closing := statement.substr(3).strip_edges().to_upper()
			if closing in ["FUNCTION", "SUB", "TYPE"]:
				_close_block(closing, "END %s" % closing, line_index, diagnostics, block_stack)
		"CALL":
			if not _is_identifier(statement.substr(4).strip_edges().get_slice("(", 0)):
				_add(diagnostics, line_index, 5, "E236", "CALL braucht ein Unterprogramm.", "error")
		"IF":
			if upper.find(" THEN ") < 0:
				_add(diagnostics, line_index, 1, "E232",
					"IF braucht THEN und eine folgende Anweisung.", "error")
		"LET":
			if not statement.contains("="):
				_add(diagnostics, line_index, 1, "E233",
					"LET braucht Variable = Ausdruck.", "error")
		"INPUT", "READ":
			if statement.substr(word.length()).strip_edges().is_empty():
				_add(diagnostics, line_index, word.length() + 2, "E237",
					"%s braucht mindestens eine Variable." % word, "error")
		"DIM":
			var declaration := statement.substr(3).strip_edges()
			if declaration.is_empty() or (not declaration.contains("(") and declaration.to_upper().find(" AS ") < 1):
				_add(diagnostics, line_index, 5, "E238",
					"DIM braucht Feld(Groesse) oder Variable AS Typ.", "error")
		"DATA":
			if statement.substr(4).strip_edges().is_empty():
				_add(diagnostics, line_index, 6, "E239", "DATA braucht mindestens einen Wert.", "error")
		"SCREEN": _check_args(statement, word, 2, 3, line_index, diagnostics)
		"WINDOW": _check_args(statement, word, 4, 5, line_index, diagnostics)
		"PALETTE": _check_args(statement, word, 2, 2, line_index, diagnostics)
		"PLOT": _check_args(statement, word, 2, 3, line_index, diagnostics)
		"LINE", "BOX": _check_args(statement, word, 4, 5, line_index, diagnostics)
		"CIRCLE": _check_args(statement, word, 3, 4, line_index, diagnostics)
		"BLIT": _check_args(statement, word, 7, 7, line_index, diagnostics)
		"SPRITE": _check_args(statement, word, 4, 5, line_index, diagnostics)
		"BOB": _check_args(statement, word, 4, 4, line_index, diagnostics)
		"TILEMAP": _check_args(statement, word, 3, 4, line_index, diagnostics)
		"SCROLL": _check_args(statement, word, 2, 2, line_index, diagnostics)
		"SAMPLE": _check_args(statement, word, 2, 2, line_index, diagnostics)
		"PLAY": _check_args(statement, word, 1, 2, line_index, diagnostics)
		"CHANNEL", "VOLUME", "PAN": _check_args(statement, word, 2, 2, line_index, diagnostics)
		"MODPLAY": _check_args(statement, word, 1, 1, line_index, diagnostics)
		"BANK", "LOADBANK": _check_args(statement, word, 2, 2, line_index, diagnostics)
		"SPRITEBANK", "SAMPLEBANK", "MAPBANK": _check_args(statement, word, 1, 1, line_index, diagnostics)
		_:
			if word in ENGINE_COMMANDS:
				var argument_range := GameCatalog.argument_range(word)
				_check_args(statement, word, argument_range.x, argument_range.y,
					line_index, diagnostics)


static func _check_args(statement: String, word: String, minimum: int,
		maximum: int, line_index: int, diagnostics: Array[Dictionary]) -> void:
	var tail := statement.substr(word.length()).strip_edges()
	var count := _split_arguments(tail).size() if not tail.is_empty() else 0
	if count < minimum or count > maximum:
		_add(diagnostics, line_index, word.length() + 2, "E240",
			"%s erwartet %s Parameter; gefunden: %d." % [word,
			str(minimum) if minimum == maximum else "%d-%d" % [minimum, maximum], count],
			"error")


static func _close_block(expected: String, closing: String, line_index: int,
		diagnostics: Array[Dictionary], block_stack: Array[Dictionary]) -> void:
	if block_stack.is_empty() or str(block_stack.back()["word"]) != expected:
		_add(diagnostics, line_index, 1, "E300",
			"%s ohne passendes %s." % [closing, expected], "error")
		return
	block_stack.pop_back()


static func _take_line_number(line: String) -> Dictionary:
	var split_at := 0
	while split_at < line.length() and line[split_at].is_valid_int():
		split_at += 1
	if split_at == 0 or (split_at < line.length() and not line[split_at] in [" ", "\t"]):
		return {"number": -1, "body": line}
	return {"number": int(line.substr(0, split_at)), "body": line.substr(split_at)}


static func _first_word(text: String) -> String:
	var clean := text.strip_edges()
	var end := 0
	while end < clean.length() and (clean[end].is_valid_identifier() or clean[end] in ["#", "$"]):
		end += 1
	return clean.substr(0, end).to_upper()


static func _is_identifier(text: String) -> bool:
	var clean := text.strip_edges().trim_suffix("$")
	return not clean.is_empty() and clean.is_valid_identifier()


static func _is_lvalue(text: String) -> bool:
	var clean := text.strip_edges()
	if clean.to_upper().begins_with("LET "):
		clean = clean.substr(4).strip_edges()
	var base := clean.get_slice("(", 0).get_slice(".", 0).trim_suffix("$")
	return _is_identifier(base)


static func _has_open_string(text: String) -> bool:
	var quotes := 0
	for character in text:
		if character == "\"":
			quotes += 1
	return quotes % 2 != 0


static func _without_comment(text: String) -> String:
	var quoted := false
	for index in text.length():
		var character := text[index]
		if character == "\"":
			quoted = not quoted
		elif character == "'" and not quoted:
			return text.substr(0, index).strip_edges()
	return text


static func _split_statements(text: String) -> Array[String]:
	return _split_quoted(text, ":")


static func _split_arguments(text: String) -> Array[String]:
	return _split_quoted(text, ",")


static func _split_quoted(text: String, delimiter: String) -> Array[String]:
	var result: Array[String] = []
	var current := ""
	var quoted := false
	var parentheses := 0
	for character in text:
		if character == "\"":
			quoted = not quoted
		elif not quoted and character == "(":
			parentheses += 1
		elif not quoted and character == ")":
			parentheses = maxi(0, parentheses - 1)
		if character == delimiter and not quoted and parentheses == 0:
			result.append(current.strip_edges())
			current = ""
		else:
			current += character
	result.append(current.strip_edges())
	return result


static func _add(diagnostics: Array[Dictionary], line_index: int, column: int,
		code: String, message: String, severity: String) -> void:
	diagnostics.append({
		"line": line_index,
		"column": column,
		"code": code,
		"message": message,
		"severity": severity,
	})
