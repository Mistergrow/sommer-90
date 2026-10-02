class_name SommerBasicVM
extends RefCounted
## Deterministische, kooperative Sommer-BASIC-VM. Der Quelltext wird vor dem
## Lauf vollstaendig analysiert; alle Hardwarezugriffe gehen durch den
## sandboxed Host. Dadurch kann Nutzer-Code weder Godot noch das Dateisystem
## erreichen und eine Endlosschleife friert das Spiel nicht ein.

const Language := preload("res://scripts/sommer_basic/sommer_basic_language.gd")
const Host := preload("res://scripts/sommer_basic/sommer_basic_host.gd")
const GameCatalog := preload("res://scripts/data/sommer_game_module_catalog.gd")
const MAX_STEPS := 50000

var variables: Dictionary = {}
var output: Array[String] = []
var draw_commands: Array[Dictionary] = []
var audio_commands: Array[Dictionary] = []
var _host: RefCounted
var _lines: Array[String] = []
var _source_line_numbers: Array[int] = []
var _line_numbers: Dictionary = {}
var _loops: Array[Dictionary] = []
var _while_loops: Array[Dictionary] = []
var _return_stack: Array[Dictionary] = []
var _arrays: Dictionary = {}
var _types: Dictionary = {}
var _subroutines: Dictionary = {}
var _functions: Dictionary = {}
var _definition_ends: Dictionary = {}
var _data: Array = []
var _data_offsets: Dictionary = {}
var _data_index := 0
var _input_values: Array = []
var _input_index := 0
var _input_request := ""
var _runtime_errors: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _pc := 0
var _ended := false
var _waiting_for_input := false


func run(source: String, context: Dictionary = {}) -> Dictionary:
	reset()
	_host.call("reset", context)
	_rng.seed = int(context.get("seed", 1990))
	var supplied_inputs: Variant = context.get("inputs", [])
	if supplied_inputs is Array:
		_input_values = supplied_inputs.duplicate(true)
	var analysis := Language.analyze_for_profile(source, int(context.get("year", 1990)),
		str(context.get("hardware_profile", "")),
		(context.get("game", {}) as Dictionary).get("unlocked_modules", [])) if context.has("year") \
		else Language.analyze(source)
	if not bool(analysis.get("ok", false)):
		return _result(false, "Compilerfehler", analysis, 0)
	_load(source)
	var steps := 0
	while _pc < _lines.size() and not _ended and steps < MAX_STEPS:
		var current := _pc
		_pc += 1
		_execute_line(_lines[current])
		steps += 1
	draw_commands = _host.get("draw_commands").duplicate(true)
	audio_commands = _host.get("audio_commands").duplicate(true)
	if steps >= MAX_STEPS:
		_runtime_errors.append("Lauf abgebrochen: Endlosschleifen-Schutz nach %d Schritten." % MAX_STEPS)
	if _waiting_for_input:
		return _result(false, "Eingabe erwartet.", analysis, steps)
	if not _runtime_errors.is_empty():
		return _result(false, _runtime_errors[0], analysis, steps)
	return _result(true, "Programm beendet.", analysis, steps)


func reset() -> void:
	variables.clear()
	output.clear()
	draw_commands.clear()
	audio_commands.clear()
	_lines.clear()
	_source_line_numbers.clear()
	_line_numbers.clear()
	_loops.clear()
	_while_loops.clear()
	_return_stack.clear()
	_arrays.clear()
	_types.clear()
	_subroutines.clear()
	_functions.clear()
	_definition_ends.clear()
	_data.clear()
	_data_offsets.clear()
	_input_values.clear()
	_runtime_errors.clear()
	_data_index = 0
	_input_index = 0
	_input_request = ""
	_pc = 0
	_ended = false
	_waiting_for_input = false
	if _host == null:
		_host = Host.new()
	_host.call("reset", {})


func _result(ok: bool, message: String, analysis: Dictionary, steps: int) -> Dictionary:
	var snapshot: Dictionary = _host.call("snapshot")
	return {
		"ok": ok,
		"message": message,
		"analysis": analysis,
		"output": output.duplicate(),
		"draw_commands": snapshot.get("draw_commands", []),
		"audio_commands": snapshot.get("audio_commands", []),
		"files": snapshot.get("files", {}),
		"banks": snapshot.get("banks", {}),
		"game": snapshot.get("game", {}),
		"steps": steps,
		"variables": variables.duplicate(true),
		"arrays": _arrays.duplicate(true),
		"waiting_for_input": _waiting_for_input,
		"input_request": _input_request,
		"runtime_errors": _runtime_errors.duplicate(),
	}


func _load(source: String) -> void:
	for raw in source.split("\n", true):
		var body := str(raw).strip_edges()
		if body.is_empty():
			continue
		var numbered := Language._take_line_number(body)
		var line_number := int(numbered.get("number", -1))
		body = str(numbered.get("body", body)).strip_edges()
		if line_number >= 0:
			_line_numbers[line_number] = _lines.size()
		_lines.append(body)
		_source_line_numbers.append(line_number)
	_index_definitions_and_data()


func _index_definitions_and_data() -> void:
	var index := 0
	while index < _lines.size():
		var statement := _first_statement(_lines[index])
		var word := Language._first_word(statement)
		var tail := statement.substr(word.length()).strip_edges()
		if word == "DATA":
			var source_line := _source_line_numbers[index]
			if source_line >= 0:
				_data_offsets[source_line] = _data.size()
			for token in Language._split_arguments(tail):
				_data.append(_data_literal(str(token)))
		elif word in ["SUB", "FUNCTION", "TYPE"]:
			var end_index := _find_definition_end(index, word)
			if end_index < 0:
				index += 1
				continue
			_definition_ends[index] = end_index
			var declaration := _parse_declaration(tail)
			var name := str(declaration.get("name", ""))
			if word == "SUB":
				_subroutines[name] = {"start": index + 1, "end": end_index,
					"params": declaration.get("params", [])}
			elif word == "FUNCTION":
				var return_expression := ""
				for body_index in range(index + 1, end_index):
					var body_statement := _first_statement(_lines[body_index])
					if Language._first_word(body_statement) == "RETURN":
						return_expression = body_statement.substr(6).strip_edges()
						break
				_functions[name] = {"params": declaration.get("params", []),
					"expression": return_expression}
			else:
				var fields: Dictionary = {}
				for body_index in range(index + 1, end_index):
					var field := _lines[body_index].strip_edges()
					var as_at := field.to_upper().find(" AS ")
					if as_at > 0:
						fields[field.substr(0, as_at).strip_edges().to_upper()] = \
							field.substr(as_at + 4).strip_edges().to_upper()
				_types[name] = fields
			index = end_index
		index += 1


func _execute_line(line: String) -> void:
	for statement in Language._split_statements(Language._without_comment(line)):
		if _ended:
			return
		_execute_statement(str(statement).strip_edges())


func _execute_statement(statement: String) -> void:
	if statement.is_empty():
		return
	var word := Language._first_word(statement)
	var tail := statement.substr(word.length()).strip_edges()
	if word == "REM":
		return
	match word:
		"PRINT": _print(tail)
		"INPUT": _input(tail)
		"LET": _assign(tail)
		"DIM": _dim(tail)
		"DATA": pass
		"READ": _read(tail)
		"RESTORE": _restore(tail)
		"CLS": output.clear(); _host.call("graphics", "cls", [])
		"GOTO": _jump(int(tail))
		"GOSUB": _return_stack.append({"pc": _pc, "restore": {}}); _jump(int(tail))
		"CALL": _call_sub(tail)
		"RETURN": _return_from_call()
		"IF": _if_statement(tail)
		"FOR": _for_statement(tail)
		"NEXT": _next_statement(tail)
		"WHILE": _while_statement(tail)
		"WEND": _wend_statement()
		"SUB", "FUNCTION", "TYPE":
			var declaration_pc := _pc - 1
			if _definition_ends.has(declaration_pc):
				_pc = int(_definition_ends[declaration_pc]) + 1
		"END":
			if tail.to_upper() == "SUB":
				_return_from_call()
			elif tail.is_empty():
				_ended = true
		"SCREEN", "WINDOW", "PALETTE", "PLOT", "LINE", "BOX", "CIRCLE", \
		"BLIT", "SPRITE", "BOB", "TILEMAP", "SCROLL": _graphics(word, tail)
		"WAIT", "FLIP": _host.call("graphics", word.to_lower(), _arguments(tail))
		"SAMPLE", "PLAY", "CHANNEL", "VOLUME", "PAN", "MODPLAY", "MODSTOP":
			_host.call("audio", word.to_lower(), _arguments(tail))
		"OPEN": _open(tail)
		"CLOSE": _close(tail)
		"PRINT#": _print_file(tail)
		"INPUT#": _input_file(tail)
		"GET": _get_file(tail)
		"PUT": _put_file(tail)
		"SEEK": _seek_file(tail)
		"BANK", "LOADBANK", "SPRITEBANK", "SAMPLEBANK", "MAPBANK": _bank(word, tail)
		"STOP": _ended = true
		_:
			if word in Language.ENGINE_COMMANDS:
				_host_error(_host.call("game", word, _arguments(tail)))
			elif statement.contains("="):
				_assign(statement)


func _print(tail: String) -> void:
	var chunks := Language._split_quoted(tail, ";")
	var line := ""
	for chunk in chunks:
		line += _display_value(_value(str(chunk)))
	output.append(line)


func _input(tail: String) -> void:
	var variable_text := tail
	var prompt := "? "
	if tail.begins_with("\""):
		var close_quote := tail.find("\"", 1)
		if close_quote > 0:
			prompt = str(_value(tail.substr(0, close_quote + 1)))
			variable_text = tail.substr(close_quote + 1).trim_prefix(";").strip_edges()
	var targets := Language._split_arguments(variable_text)
	if _input_index + targets.size() > _input_values.size():
		_input_request = prompt + "  " + ", ".join(targets)
		output.append(_input_request)
		_waiting_for_input = true
		_ended = true
		return
	for target in targets:
		_assign_value(str(target).strip_edges(), _input_values[_input_index])
		_input_index += 1


func _display_value(value: Variant) -> String:
	if value is float and is_equal_approx(float(value), floorf(float(value))):
		return str(int(value))
	return str(value)


func _assign(expression: String) -> void:
	var equal := expression.find("=")
	if equal < 1:
		return
	_assign_value(expression.substr(0, equal).strip_edges(),
		_value(expression.substr(equal + 1).strip_edges()))


func _assign_value(target: String, value: Variant) -> void:
	var clean := target.strip_edges().to_upper()
	if clean.contains("(") and clean.ends_with(")"):
		var name := clean.get_slice("(", 0)
		var inside := clean.substr(clean.find("(") + 1).trim_suffix(")")
		_array_set(name, _integer_arguments(inside), value)
		return
	if clean.contains("."):
		var owner_name := clean.get_slice(".", 0)
		var field_name := clean.substr(clean.find(".") + 1)
		var record: Dictionary = variables.get(owner_name, {})
		record[field_name] = value
		variables[owner_name] = record
		return
	variables[clean] = value


func _dim(tail: String) -> void:
	var upper := tail.to_upper()
	var as_at := upper.find(" AS ")
	if as_at > 0 and not tail.contains("("):
		var variable_name := tail.substr(0, as_at).strip_edges().to_upper()
		var type_name := tail.substr(as_at + 4).strip_edges().to_upper()
		if _types.has(type_name):
			var record: Dictionary = {}
			for field_name in (_types[type_name] as Dictionary):
				if str((_types[type_name] as Dictionary)[field_name]) == "STRING":
					record[field_name] = ""
				else:
					record[field_name] = 0
			variables[variable_name] = record
		else:
			if type_name == "STRING":
				variables[variable_name] = ""
			else:
				variables[variable_name] = 0
		return
	var open := tail.find("(")
	if open < 1 or not tail.ends_with(")"):
		_runtime_error("DIM-Deklaration ist ungueltig.")
		return
	var name := tail.substr(0, open).strip_edges().to_upper()
	var dimensions := _integer_arguments(tail.substr(open + 1).trim_suffix(")"))
	var total := 1
	for dimension in dimensions:
		total *= maxi(1, int(dimension) + 1)
	if total > 262144:
		_runtime_error("DIM ueberschreitet das Array-Budget von 262144 Elementen.")
		return
	var values: Array = []
	values.resize(total)
	values.fill(0)
	_arrays[name] = {"dims": dimensions, "values": values}


func _read(tail: String) -> void:
	for target in Language._split_arguments(tail):
		if _data_index >= _data.size():
			_runtime_error("READ hat das Ende der DATA-Werte erreicht.")
			return
		_assign_value(str(target), _data[_data_index])
		_data_index += 1


func _restore(tail: String) -> void:
	if tail.is_empty():
		_data_index = 0
		return
	var target := int(_value(tail))
	if not _data_offsets.has(target):
		_runtime_error("RESTORE-Zeile %d enthaelt keine DATA-Werte." % target)
		return
	_data_index = int(_data_offsets[target])


func _if_statement(tail: String) -> void:
	var then_at := _find_unquoted_phrase(tail.to_upper(), " THEN ")
	if then_at < 0:
		return
	var condition := tail.substr(0, then_at)
	var branches := tail.substr(then_at + 6).strip_edges()
	var else_at := _find_unquoted_phrase(branches.to_upper(), " ELSE ")
	var true_action := branches if else_at < 0 else branches.substr(0, else_at).strip_edges()
	var false_action := "" if else_at < 0 else branches.substr(else_at + 6).strip_edges()
	var action := true_action if bool(_value(_condition_expression(condition))) else false_action
	if not action.is_empty():
		if action.is_valid_int(): _jump(int(action))
		else: _execute_statement(action)


func _for_statement(tail: String) -> void:
	var upper := tail.to_upper()
	var equal := tail.find("=")
	var to_at := upper.find(" TO ")
	if equal < 1 or to_at < 0:
		return
	var variable := tail.substr(0, equal).strip_edges().to_upper()
	var step_at := upper.find(" STEP ")
	var end_text := tail.substr(to_at + 4) if step_at < 0 else tail.substr(to_at + 4, step_at - to_at - 4)
	var step_value := 1.0 if step_at < 0 else float(_value(tail.substr(step_at + 6)))
	variables[variable] = _value(tail.substr(equal + 1, to_at - equal - 1))
	_loops.append({"variable": variable, "end": float(_value(end_text)), "step": step_value, "pc": _pc})


func _next_statement(variable_text: String) -> void:
	if _loops.is_empty(): return
	var loop: Dictionary = _loops.back()
	var variable := str(loop["variable"])
	if not variable_text.is_empty() and variable_text.to_upper() != variable: return
	variables[variable] = float(variables.get(variable, 0.0)) + float(loop["step"])
	var current := float(variables[variable])
	var step_value := float(loop["step"])
	if (step_value >= 0.0 and current <= float(loop["end"])) or (step_value < 0.0 and current >= float(loop["end"])):
		_pc = int(loop["pc"])
	else: _loops.pop_back()


func _while_statement(condition: String) -> void:
	var opening_line := _pc - 1
	if bool(_value(_condition_expression(condition))):
		if _while_loops.is_empty() or int(_while_loops.back().get("line", -1)) != opening_line:
			_while_loops.append({"line": opening_line})
		return
	if not _while_loops.is_empty() and int(_while_loops.back().get("line", -1)) == opening_line:
		_while_loops.pop_back()
	var closing_line := _matching_wend(opening_line)
	if closing_line >= 0: _pc = closing_line + 1


func _wend_statement() -> void:
	if not _while_loops.is_empty(): _pc = int(_while_loops.back().get("line", _pc))


func _matching_wend(opening_line: int) -> int:
	var depth := 0
	for line_index in range(opening_line, _lines.size()):
		for raw_statement in Language._split_statements(Language._without_comment(_lines[line_index])):
			var word := Language._first_word(str(raw_statement).strip_edges())
			if word == "WHILE": depth += 1
			elif word == "WEND":
				depth -= 1
				if depth == 0: return line_index
	return -1


func _call_sub(tail: String) -> void:
	var declaration := _parse_declaration(tail)
	var name := str(declaration.get("name", ""))
	if not _subroutines.has(name):
		_runtime_error("Unterprogramm %s ist nicht definiert." % name)
		return
	var sub: Dictionary = _subroutines[name]
	var params: Array = sub.get("params", [])
	var argument_values := _arguments(str(declaration.get("argument_source", "")))
	var restore: Dictionary = {}
	for index in mini(params.size(), argument_values.size()):
		var parameter := str(params[index]).to_upper()
		restore[parameter] = {"exists": variables.has(parameter), "value": variables.get(parameter)}
		variables[parameter] = argument_values[index]
	_return_stack.append({"pc": _pc, "restore": restore})
	_pc = int(sub["start"])


func _return_from_call() -> void:
	if _return_stack.is_empty(): return
	var frame: Dictionary = _return_stack.pop_back()
	for parameter in (frame.get("restore", {}) as Dictionary):
		var old: Dictionary = frame["restore"][parameter]
		if bool(old.get("exists", false)): variables[parameter] = old.get("value")
		else: variables.erase(parameter)
	_pc = int(frame.get("pc", _pc))


func _graphics(word: String, tail: String) -> void:
	_host.call("graphics", word.to_lower(), _arguments(tail))


func _open(tail: String) -> void:
	var upper := tail.to_upper()
	var for_at := _find_unquoted_phrase(upper, " FOR ")
	var as_at := _find_unquoted_phrase(upper, " AS ")
	if for_at < 0 or as_at < for_at:
		_runtime_error("OPEN erwartet Dateiname FOR Modus AS #Kanal.")
		return
	var path := str(_value(tail.substr(0, for_at)))
	var mode := tail.substr(for_at + 5, as_at - for_at - 5).strip_edges()
	var channel := _channel_number(tail.substr(as_at + 4))
	_host_error(_host.call("open_file", path, mode, channel))


func _close(tail: String) -> void:
	for value in Language._split_arguments(tail): _host_error(_host.call("close_file", _channel_number(str(value))))


func _print_file(tail: String) -> void:
	var args := Language._split_arguments(tail)
	if args.size() < 2: _runtime_error("PRINT# erwartet Kanal und Ausdruck."); return
	_host_error(_host.call("print_file", _channel_number(args[0]), _value(args[1])))


func _input_file(tail: String) -> void:
	var args := Language._split_arguments(tail)
	if args.size() < 2: _runtime_error("INPUT# erwartet Kanal und Variable."); return
	var result: Dictionary = _host.call("input_file", _channel_number(args[0]))
	if not bool(result.get("ok", false)): _runtime_error(str(result.get("error", "Dateifehler"))); return
	_assign_value(args[1], result.get("value"))


func _get_file(tail: String) -> void:
	var args := Language._split_arguments(tail)
	if args.size() < 2: _runtime_error("GET erwartet Kanal und Variable."); return
	var result: Dictionary = _host.call("get_file", _channel_number(args[0]))
	if not bool(result.get("ok", false)): _runtime_error(str(result.get("error", "Dateifehler"))); return
	_assign_value(args[1], result.get("value"))


func _put_file(tail: String) -> void:
	var args := Language._split_arguments(tail)
	if args.size() < 2: _runtime_error("PUT erwartet Kanal und Wert."); return
	_host_error(_host.call("put_file", _channel_number(args[0]), _value(args[1])))


func _seek_file(tail: String) -> void:
	var args := Language._split_arguments(tail)
	if args.size() < 2: _runtime_error("SEEK erwartet Kanal und Position."); return
	_host_error(_host.call("seek_file", _channel_number(args[0]), int(_value(args[1]))))


func _bank(word: String, tail: String) -> void:
	var args := _arguments(tail)
	match word:
		"BANK": _host_error(_host.call("define_bank", int(args[0]), int(args[1])))
		"LOADBANK": _host_error(_host.call("load_bank", int(args[0]), str(args[1])))
		"SPRITEBANK": _host_error(_host.call("tag_bank", int(args[0]), "sprite"))
		"SAMPLEBANK": _host_error(_host.call("tag_bank", int(args[0]), "sample"))
		"MAPBANK": _host_error(_host.call("tag_bank", int(args[0]), "map"))


func _jump(line_number: int) -> void:
	if _line_numbers.has(line_number): _pc = int(_line_numbers[line_number])


func _condition_expression(source: String) -> String:
	var result := source.replace("<>", "!=")
	var equal := result.find("=")
	if equal >= 0 and (equal == 0 or result[equal - 1] not in ["<", ">", "!"]) and \
			(equal + 1 >= result.length() or result[equal + 1] != "="):
		result = result.substr(0, equal) + "==" + result.substr(equal + 1)
	return result


func _value(source: String) -> Variant:
	var clean := source.strip_edges()
	if _is_single_string_literal(clean):
		return clean.substr(1, clean.length() - 2)
	if clean.to_upper() in variables: return variables[clean.to_upper()]
	clean = _expand_user_functions(clean)
	clean = _expand_arrays_and_fields(clean)
	clean = _expand_host_functions(clean)
	clean = _expand_random(clean)
	clean = _expand_intrinsic_functions(clean)
	var names: Array[String] = []
	var values: Array = []
	var normalized := clean
	var counter := 0
	var keys := variables.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a).length() > str(b).length())
	for key in keys:
		if variables[key] is Dictionary: continue
		var safe_name := "SBV%d" % counter
		normalized = _replace_identifier(normalized, str(key), safe_name)
		names.append(safe_name)
		values.append(variables[key])
		counter += 1
	normalized = normalized.replace(" AND ", " and ").replace(" OR ", " or ").replace(" NOT ", " not ")
	var expression := Expression.new()
	if expression.parse(normalized, names) == OK:
		var value: Variant = expression.execute(values, null, false)
		if not expression.has_execute_failed(): return value
	if clean.is_valid_int(): return int(clean)
	if clean.is_valid_float(): return float(clean)
	return clean


func _expand_host_functions(source: String) -> String:
	var result := source
	for function_name in ["MOUSEBUTTON", "MOUSEX", "MOUSEY", "JOYX", "JOYY", "JOY", "KEY$"]:
		var literal := _literal(_host.call("input_value", function_name))
		result = _replace_identifier(result, function_name, literal, true)
	while true:
		var call_info := _find_function_call(result, "EOF")
		if call_info.is_empty(): break
		var channel_text := str(call_info.get("arguments", "")).strip_edges().trim_prefix("#")
		var replacement := "true" if bool(_host.call("eof", int(_value(channel_text)))) else "false"
		result = _replace_call(result, call_info, replacement)
	for function_name: String in GameCatalog.functions():
		while true:
			var game_call := _find_function_call(result, function_name)
			if game_call.is_empty():
				break
			var values := _arguments(str(game_call.get("arguments", "")))
			result = _replace_call(result, game_call,
				_literal(_host.call("game_value", function_name, values)))
	for function_name in ["GAMEACTIVE", "FRAMECOST", "PROJECTILECOUNT",
			"PARTICLECOUNT", "POPULATION", "CITYMONEY", "NETPLAYERS",
			"POWERED", "TRAFFIC", "BUILDVERSION"]:
		result = _replace_identifier(result, function_name,
			_literal(_host.call("game_value", function_name, [])), true)
	return result


func _expand_random(source: String) -> String:
	var result := source
	while true:
		var call_info := _find_function_call(result, "RND")
		if call_info.is_empty(): break
		var maximum := maxi(1, int(_value(str(call_info.get("arguments", "")))))
		var replacement := str(_rng.randi_range(0, maximum - 1))
		result = _replace_call(result, call_info, replacement)
	result = _replace_identifier(result, "RND", str(_rng.randf()))
	return result


func _expand_intrinsic_functions(source: String) -> String:
	var result := source
	for function_name in ["ASC", "CHR$", "LEFT$", "LEN", "MID$", "RIGHT$", "STR$", "VAL",
			"ABS", "INT", "SQR", "SIN", "COS", "TAN"]:
		while true:
			var call_info := _find_function_call(result, function_name)
			if call_info.is_empty(): break
			var values := _arguments(str(call_info.get("arguments", "")))
			var evaluated := _intrinsic_value(function_name, values)
			if evaluated.get("error", false):
				_runtime_error("%s besitzt ungueltige Parameter." % function_name)
				return result
			result = _replace_call(result, call_info, _literal(evaluated.get("value")))
	return result


func _intrinsic_value(function_name: String, args: Array) -> Dictionary:
	var name := function_name.to_upper()
	match name:
		"ASC":
			var text := str(args[0]) if not args.is_empty() else ""
			return {"value": -1 if text.is_empty() else text.unicode_at(0)}
		"CHR$": return {"value": String.chr(clampi(int(args[0]), 0, 0x10ffff))} if args.size() == 1 else {"error": true}
		"LEFT$": return {"value": str(args[0]).left(maxi(0, int(args[1])))} if args.size() == 2 else {"error": true}
		"LEN": return {"value": str(args[0]).length()} if args.size() == 1 else {"error": true}
		"MID$":
			if args.size() not in [2, 3]: return {"error": true}
			var source_text := str(args[0])
			var start := maxi(0, int(args[1]) - 1)
			return {"value": source_text.substr(start) if args.size() == 2 else source_text.substr(start, maxi(0, int(args[2])))}
		"RIGHT$": return {"value": str(args[0]).right(maxi(0, int(args[1])))} if args.size() == 2 else {"error": true}
		"STR$": return {"value": _display_value(args[0])} if args.size() == 1 else {"error": true}
		"VAL":
			if args.size() != 1: return {"error": true}
			var number_text := str(args[0]).strip_edges()
			return {"value": int(number_text)} if number_text.is_valid_int() else \
				({"value": float(number_text)} if number_text.is_valid_float() else {"value": 0})
		"ABS": return {"value": absf(float(args[0]))} if args.size() == 1 else {"error": true}
		"INT": return {"value": floori(float(args[0]))} if args.size() == 1 else {"error": true}
		"SQR": return {"value": sqrt(maxf(0.0, float(args[0])))} if args.size() == 1 else {"error": true}
		"SIN": return {"value": sin(float(args[0]))} if args.size() == 1 else {"error": true}
		"COS": return {"value": cos(float(args[0]))} if args.size() == 1 else {"error": true}
		"TAN": return {"value": tan(float(args[0]))} if args.size() == 1 else {"error": true}
	return {"error": true}


func _expand_arrays_and_fields(source: String) -> String:
	var result := source
	for array_name in _arrays:
		var regex := RegEx.new()
		regex.compile("(?i)\\b%s\\s*\\(([^()]*)\\)" % _regex_escape(str(array_name)))
		while true:
			var regex_match := regex.search(result)
			if regex_match == null: break
			var value: Variant = _array_get(str(array_name), _integer_arguments(regex_match.get_string(1)))
			result = result.substr(0, regex_match.get_start()) + _literal(value) + result.substr(regex_match.get_end())
	for variable_name in variables:
		if not variables[variable_name] is Dictionary: continue
		for field_name in (variables[variable_name] as Dictionary):
			result = result.replace("%s.%s" % [variable_name, field_name], _literal(variables[variable_name][field_name]))
	return result


func _expand_user_functions(source: String) -> String:
	var result := source
	for function_name in _functions:
		var regex := RegEx.new()
		regex.compile("(?i)\\b%s\\s*\\(([^()]*)\\)" % _regex_escape(str(function_name)))
		var regex_match := regex.search(result)
		while regex_match != null:
			var definition: Dictionary = _functions[function_name]
			var params: Array = definition.get("params", [])
			var args := _arguments(regex_match.get_string(1))
			var restore: Dictionary = {}
			for index in mini(params.size(), args.size()):
				var parameter := str(params[index]).to_upper()
				restore[parameter] = {"exists": variables.has(parameter), "value": variables.get(parameter)}
				variables[parameter] = args[index]
			var value: Variant = _value(str(definition.get("expression", "0")))
			for parameter in restore:
				if bool(restore[parameter]["exists"]): variables[parameter] = restore[parameter]["value"]
				else: variables.erase(parameter)
			result = result.substr(0, regex_match.get_start()) + _literal(value) + result.substr(regex_match.get_end())
			regex_match = regex.search(result)
	return result


func _array_set(name: String, indices: Array[int], value: Variant) -> void:
	if not _arrays.has(name): _runtime_error("Feld %s wurde nicht mit DIM angelegt." % name); return
	var array: Dictionary = _arrays[name]
	var offset := _array_offset(array.get("dims", []), indices)
	if offset < 0: _runtime_error("Index fuer Feld %s liegt ausserhalb des Bereichs." % name); return
	var values: Array = array["values"]
	values[offset] = value
	array["values"] = values
	_arrays[name] = array


func _array_get(name: String, indices: Array[int]) -> Variant:
	if not _arrays.has(name): return 0
	var array: Dictionary = _arrays[name]
	var offset := _array_offset(array.get("dims", []), indices)
	return 0 if offset < 0 else (array["values"] as Array)[offset]


func _array_offset(dimensions: Array, indices: Array[int]) -> int:
	if dimensions.size() != indices.size(): return -1
	var offset := 0
	var stride := 1
	for index in range(dimensions.size() - 1, -1, -1):
		var size := int(dimensions[index]) + 1
		if indices[index] < 0 or indices[index] >= size: return -1
		offset += indices[index] * stride
		stride *= size
	return offset


func _arguments(tail: String) -> Array:
	var result: Array = []
	if tail.strip_edges().is_empty(): return result
	for argument in Language._split_arguments(tail): result.append(_value(str(argument)))
	return result


func _integer_arguments(tail: String) -> Array[int]:
	var result: Array[int] = []
	for value in _arguments(tail): result.append(int(value))
	return result


func _data_literal(token: String) -> Variant:
	var clean := token.strip_edges()
	if clean.begins_with("\"") and clean.ends_with("\""): return clean.substr(1, clean.length() - 2)
	if clean.is_valid_int(): return int(clean)
	if clean.is_valid_float(): return float(clean)
	return clean


func _parse_declaration(text: String) -> Dictionary:
	var clean := text.strip_edges()
	var open := clean.find("(")
	var name := clean if open < 0 else clean.substr(0, open)
	var argument_source := "" if open < 0 else clean.substr(open + 1).trim_suffix(")")
	var params: Array[String] = []
	if not argument_source.is_empty():
		for param in Language._split_arguments(argument_source): params.append(str(param).strip_edges().get_slice(" ", 0).to_upper())
	return {"name": name.strip_edges().to_upper(), "params": params, "argument_source": argument_source}


func _find_definition_end(start: int, kind: String) -> int:
	for index in range(start + 1, _lines.size()):
		if _first_statement(_lines[index]).to_upper() == "END %s" % kind: return index
	return -1


func _first_statement(line: String) -> String:
	var statements := Language._split_statements(Language._without_comment(line))
	return "" if statements.is_empty() else str(statements[0]).strip_edges()


func _channel_number(text: String) -> int:
	return int(str(text).strip_edges().trim_prefix("#"))


func _find_unquoted_phrase(text: String, phrase: String) -> int:
	var quoted := false
	var index := 0
	while index <= text.length() - phrase.length():
		if text[index] == "\"": quoted = not quoted
		if not quoted and text.substr(index, phrase.length()) == phrase: return index
		index += 1
	return -1


func _find_function_call(source: String, function_name: String) -> Dictionary:
	var upper := source.to_upper()
	var needle := function_name.to_upper()
	var quoted := false
	var index := 0
	while index <= source.length() - needle.length():
		if source[index] == "\"":
			quoted = not quoted
			index += 1
			continue
		if quoted or upper.substr(index, needle.length()) != needle or \
				not _identifier_boundary(source, index - 1) or \
				not _identifier_boundary(source, index + needle.length()):
			index += 1
			continue
		var open := index + needle.length()
		while open < source.length() and source[open] in [" ", "\t"]: open += 1
		if open >= source.length() or source[open] != "(":
			index += needle.length()
			continue
		var depth := 1
		var inner_quoted := false
		var close := open + 1
		while close < source.length() and depth > 0:
			if source[close] == "\"": inner_quoted = not inner_quoted
			elif not inner_quoted and source[close] == "(": depth += 1
			elif not inner_quoted and source[close] == ")": depth -= 1
			close += 1
		if depth == 0:
			return {"start": index, "end": close, "arguments": source.substr(open + 1, close - open - 2)}
		return {}
	return {}


func _replace_call(source: String, call_info: Dictionary, replacement: String) -> String:
	return source.substr(0, int(call_info["start"])) + replacement + \
		source.substr(int(call_info["end"]))


func _replace_identifier(source: String, identifier: String, replacement: String,
		allow_empty_call: bool = false) -> String:
	var result := source
	var upper_identifier := identifier.to_upper()
	var from := 0
	var quoted := false
	while from <= result.length() - upper_identifier.length():
		if result[from] == "\"":
			quoted = not quoted
			from += 1
			continue
		if quoted or result.to_upper().substr(from, upper_identifier.length()) != upper_identifier or \
				not _identifier_boundary(result, from - 1) or \
				not _identifier_boundary(result, from + upper_identifier.length()):
			from += 1
			continue
		var replace_end := from + upper_identifier.length()
		if allow_empty_call:
			var probe := replace_end
			while probe < result.length() and result[probe] in [" ", "\t"]: probe += 1
			if probe + 1 < result.length() and result.substr(probe, 2) == "()": replace_end = probe + 2
		result = result.substr(0, from) + replacement + result.substr(replace_end)
		from += replacement.length()
	return result


func _identifier_boundary(source: String, index: int) -> bool:
	if index < 0 or index >= source.length(): return true
	return not (source[index].is_valid_identifier() or source[index] == "$")


func _is_single_string_literal(source: String) -> bool:
	if source.length() < 2 or not source.begins_with("\"") or not source.ends_with("\""):
		return false
	var quoted := false
	for index in source.length():
		if source[index] != "\"": continue
		quoted = not quoted
		if not quoted and index != source.length() - 1: return false
	return not quoted


func _literal(value: Variant) -> String:
	if value is String: return "\"%s\"" % str(value).replace("\\", "\\\\").replace("\"", "\\\"")
	if value is bool: return "true" if value else "false"
	return str(value)


func _regex_escape(value: String) -> String:
	var result := value
	for symbol in ["\\", ".", "+", "*", "?", "[", "]", "(", ")", "{", "}", "^", "$", "|"]:
		result = result.replace(symbol, "\\" + symbol)
	return result


func _host_error(value: Variant) -> void:
	var message := str(value)
	if not message.is_empty(): _runtime_error(message)


func _runtime_error(message: String) -> void:
	_runtime_errors.append(message)
	_ended = true
