class_name SommerBasicHost
extends RefCounted
## Sichere Host-Schicht fuer Sommer BASIC. Nutzerprogramme sehen weder Godot-
## Nodes noch FileAccess oder das Betriebssystem. Grafik, Audio, Eingaben,
## Dateien und Banks laufen ausschliesslich ueber diesen reproduzierbaren
## Vertrag und koennen deshalb in Editor, Magazin-Tests und Builds gleich
## ausgefuehrt werden.

const GameRuntime := preload("res://scripts/sommer_game/sommer_game_runtime.gd")

var draw_commands: Array[Dictionary] = []
var audio_commands: Array[Dictionary] = []
var input_state: Dictionary = {}
var virtual_files: Dictionary = {}
var banks: Dictionary = {}
var _channels: Dictionary = {}
var _game_runtime: RefCounted


func reset(context: Dictionary = {}) -> void:
	draw_commands.clear()
	audio_commands.clear()
	_channels.clear()
	input_state = {
		"key": "", "mouse_x": 0, "mouse_y": 0, "mouse_button": 0,
		"joy": 0, "joy_x": 0, "joy_y": 0,
	}
	var supplied_input: Variant = context.get("input", {})
	if supplied_input is Dictionary:
		input_state.merge(supplied_input, true)
	virtual_files = {}
	var supplied_files: Variant = context.get("files", {})
	if supplied_files is Dictionary:
		virtual_files = supplied_files.duplicate(true)
	banks = {}
	var supplied_banks: Variant = context.get("banks", {})
	if supplied_banks is Dictionary:
		banks = supplied_banks.duplicate(true)
	if _game_runtime == null:
		_game_runtime = GameRuntime.new()
	_game_runtime.call("reset", context.get("game", {}))


func graphics(operation: String, args: Array) -> void:
	draw_commands.append({"op": operation.to_lower(), "args": args.duplicate(true)})


func audio(operation: String, args: Array) -> void:
	audio_commands.append({"op": operation.to_lower(), "args": args.duplicate(true)})


func game(operation: String, args: Array) -> String:
	var result: Dictionary = _game_runtime.call("execute", operation, args)
	for raw_draw: Variant in result.get("draw", []):
		if raw_draw is Dictionary:
			draw_commands.append((raw_draw as Dictionary).duplicate(true))
	for raw_audio: Variant in result.get("audio", []):
		if raw_audio is Dictionary:
			audio_commands.append((raw_audio as Dictionary).duplicate(true))
	return "" if bool(result.get("ok", false)) else str(result.get("error", "Sommer-Game-Laufzeitfehler."))


func game_value(function_name: String, args: Array) -> Variant:
	return _game_runtime.call("value", function_name, args)


func input_value(function_name: String) -> Variant:
	match function_name.to_upper():
		"KEY$": return str(input_state.get("key", ""))
		"MOUSEX": return int(input_state.get("mouse_x", 0))
		"MOUSEY": return int(input_state.get("mouse_y", 0))
		"MOUSEBUTTON": return int(input_state.get("mouse_button", 0))
		"JOY": return int(input_state.get("joy", 0))
		"JOYX": return int(input_state.get("joy_x", 0))
		"JOYY": return int(input_state.get("joy_y", 0))
	return 0


func open_file(path: String, mode: String, channel: int) -> String:
	var clean_path := path.strip_edges()
	if not _valid_virtual_path(clean_path):
		return "Ungueltiger virtueller Dateiname."
	if channel < 1 or channel > 16:
		return "Dateikanal muss zwischen 1 und 16 liegen."
	var normalized_mode := mode.to_upper()
	if normalized_mode not in ["INPUT", "OUTPUT", "APPEND", "BINARY"]:
		return "Unbekannter Dateimodus: %s" % mode
	if normalized_mode == "INPUT" and not virtual_files.has(clean_path):
		return "Datei nicht gefunden: %s" % clean_path
	if normalized_mode == "OUTPUT":
		virtual_files[clean_path] = ""
	elif not virtual_files.has(clean_path):
		virtual_files[clean_path] = ""
	var content := str(virtual_files.get(clean_path, ""))
	_channels[channel] = {
		"path": clean_path,
		"mode": normalized_mode,
		"position": content.length() if normalized_mode == "APPEND" else 0,
	}
	return ""


func close_file(channel: int) -> String:
	if not _channels.has(channel):
		return "Dateikanal #%d ist nicht offen." % channel
	_channels.erase(channel)
	return ""


func print_file(channel: int, value: Variant) -> String:
	var error := _writable_channel_error(channel)
	if not error.is_empty():
		return error
	return _write(channel, str(value) + "\n")


func input_file(channel: int) -> Dictionary:
	var error := _readable_channel_error(channel)
	if not error.is_empty():
		return {"ok": false, "error": error, "value": ""}
	var state: Dictionary = _channels[channel]
	var content := str(virtual_files.get(str(state["path"]), ""))
	var position := int(state["position"])
	var newline := content.find("\n", position)
	var end := content.length() if newline < 0 else newline
	var value := content.substr(position, end - position).trim_suffix("\r")
	state["position"] = content.length() if newline < 0 else newline + 1
	_channels[channel] = state
	return {"ok": true, "error": "", "value": value}


func get_file(channel: int) -> Dictionary:
	var error := _readable_channel_error(channel)
	if not error.is_empty():
		return {"ok": false, "error": error, "value": 0}
	var state: Dictionary = _channels[channel]
	var content := str(virtual_files.get(str(state["path"]), ""))
	var position := int(state["position"])
	if position >= content.length():
		return {"ok": true, "error": "", "value": -1}
	var value := content.unicode_at(position)
	state["position"] = position + 1
	_channels[channel] = state
	return {"ok": true, "error": "", "value": value}


func put_file(channel: int, value: Variant) -> String:
	var error := _writable_channel_error(channel)
	if not error.is_empty():
		return error
	var text := String.chr(clampi(int(value), 0, 255)) if value is int or value is float else str(value)
	return _write(channel, text)


func seek_file(channel: int, position: int) -> String:
	if not _channels.has(channel):
		return "Dateikanal #%d ist nicht offen." % channel
	var state: Dictionary = _channels[channel]
	var content := str(virtual_files.get(str(state["path"]), ""))
	state["position"] = clampi(position, 0, content.length())
	_channels[channel] = state
	return ""


func eof(channel: int) -> bool:
	if not _channels.has(channel):
		return true
	var state: Dictionary = _channels[channel]
	return int(state["position"]) >= str(virtual_files.get(str(state["path"]), "")).length()


func define_bank(bank_id: int, size: int) -> String:
	if bank_id < 0 or bank_id > 255:
		return "Banknummer muss zwischen 0 und 255 liegen."
	if size < 0 or size > 2 * 1024 * 1024:
		return "Bankgroesse liegt ausserhalb des 2-MB-Projektbudgets."
	var bytes := PackedByteArray()
	bytes.resize(size)
	banks[bank_id] = {"kind": "raw", "data": bytes}
	return ""


func load_bank(bank_id: int, path: String) -> String:
	if not virtual_files.has(path):
		return "Bankdatei nicht gefunden: %s" % path
	var bytes := str(virtual_files[path]).to_utf8_buffer()
	if bytes.size() > 2 * 1024 * 1024:
		return "Bankdatei ueberschreitet das 2-MB-Projektbudget."
	banks[bank_id] = {"kind": "raw", "data": bytes, "source": path}
	return ""


func tag_bank(bank_id: int, kind: String) -> String:
	if not banks.has(bank_id):
		return "Bank %d ist nicht angelegt." % bank_id
	var bank: Dictionary = banks[bank_id]
	bank["kind"] = kind.to_lower()
	banks[bank_id] = bank
	return ""


func snapshot() -> Dictionary:
	return {
		"draw_commands": draw_commands.duplicate(true),
		"audio_commands": audio_commands.duplicate(true),
		"files": virtual_files.duplicate(true),
		"banks": banks.duplicate(true),
		"game": _game_runtime.call("snapshot") if _game_runtime != null else {},
	}


func _write(channel: int, text: String) -> String:
	var state: Dictionary = _channels[channel]
	var path := str(state["path"])
	var content := str(virtual_files.get(path, ""))
	var position := int(state["position"])
	if position >= content.length():
		content += text
	else:
		content = content.substr(0, position) + text + content.substr(mini(content.length(), position + text.length()))
	state["position"] = position + text.length()
	virtual_files[path] = content
	_channels[channel] = state
	return ""


func _readable_channel_error(channel: int) -> String:
	if not _channels.has(channel):
		return "Dateikanal #%d ist nicht offen." % channel
	var mode := str((_channels[channel] as Dictionary).get("mode", ""))
	return "" if mode in ["INPUT", "BINARY"] else "Dateikanal #%d ist nicht lesbar." % channel


func _writable_channel_error(channel: int) -> String:
	if not _channels.has(channel):
		return "Dateikanal #%d ist nicht offen." % channel
	var mode := str((_channels[channel] as Dictionary).get("mode", ""))
	return "" if mode in ["OUTPUT", "APPEND", "BINARY"] else "Dateikanal #%d ist nicht beschreibbar." % channel


func _valid_virtual_path(path: String) -> bool:
	return not path.is_empty() and not path.contains("..") and not path.begins_with("/") \
		and not path.contains("\\") and not path.contains(":")
