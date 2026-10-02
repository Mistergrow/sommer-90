class_name ActionExecutionEngine
extends RefCounted
## Kleiner, synchroner Ausführungskern für UI-gesteuerte Programmfunktionen.
##
## Er ersetzt keine Fachlogik. Er gibt bestehenden Runtime-Aktionen einen
## einheitlichen Vertrag: validierte Eingaben, Reentrancy-Schutz, exakt eine
## ausstehende Bestätigung, defensive Ergebniskopien und begrenzte Telemetrie.

const DEFAULT_HISTORY_LIMIT := 16

var _executor := Callable()
var _context_id := ""
var _pending_action := ""
var _busy := false
var _sequence := 0
var _history_limit := DEFAULT_HISTORY_LIMIT
var _last_result: Dictionary = {}
var _history: Array[Dictionary] = []
var _code_counts: Dictionary = {}


func configure(executor: Callable, context_id := "",
		history_limit := DEFAULT_HISTORY_LIMIT) -> ActionExecutionEngine:
	_executor = executor
	_context_id = context_id.strip_edges()
	_history_limit = maxi(1, history_limit)
	if _history.size() > _history_limit:
		_history.resize(_history_limit)
	return self


func execute(action_id: String, confirm := false) -> Dictionary:
	var clean_id := action_id.strip_edges()
	if clean_id.is_empty():
		return _record(_failure("invalid_action",
			"Eine leere Aktion kann nicht ausgeführt werden."),
			clean_id, confirm, 0)
	if not _executor.is_valid():
		return _record(_failure("executor_unavailable",
			"Die Programmfunktion ist noch nicht bereit."),
			clean_id, confirm, 0)
	if _busy:
		# Nicht in die normale Historie aufnehmen: Ein Listener oder fehlerhafter
		# Adapter könnte sonst während derselben Aktion eine Log-Kaskade erzeugen.
		return _decorate(_failure("action_busy",
			"Die vorherige Programmfunktion läuft noch."),
			clean_id, confirm, 0, _sequence + 1)

	_sequence += 1
	var current_sequence := _sequence
	var started_usec := Time.get_ticks_usec()
	_busy = true
	var raw_result: Variant = _executor.call(clean_id, confirm)
	_busy = false
	var elapsed_usec := maxi(0, Time.get_ticks_usec() - started_usec)
	var result := _normalize(raw_result)
	if bool(result.get("confirmation_required", false)):
		_pending_action = clean_id
	elif confirm and _pending_action == clean_id:
		# Eine Bestätigung ist ein einmaliger Entschluss. Bei einem Fachfehler
		# muss der Benutzer die Aktion bewusst erneut anstoßen.
		_pending_action = ""
	elif bool(result.get("ok", false)) and _pending_action == clean_id:
		_pending_action = ""
	return _record(result, clean_id, confirm, elapsed_usec, current_sequence)


func confirm_pending() -> Dictionary:
	if _pending_action.is_empty():
		return _record(_failure("nothing_pending",
			"Keine Aktion wartet auf Bestätigung."), "", true, 0)
	return execute(_pending_action, true)


func cancel_pending() -> bool:
	if _pending_action.is_empty():
		return false
	_pending_action = ""
	return true


func pending_action() -> String:
	return _pending_action


func is_busy() -> bool:
	return _busy


func last_result() -> Dictionary:
	return _last_result.duplicate(true)


func state_snapshot() -> Dictionary:
	return {
		"context_id": _context_id,
		"busy": _busy,
		"pending_action": _pending_action,
		"sequence": _sequence,
		"history_size": _history.size(),
		"history_limit": _history_limit,
		"code_counts": _code_counts.duplicate(true),
		"last_result": _last_result.duplicate(true),
	}


func history_snapshot() -> Array[Dictionary]:
	return _history.duplicate(true)


func _normalize(raw_result: Variant) -> Dictionary:
	if raw_result is not Dictionary:
		return _failure("invalid_result",
			"Die Programmfunktion lieferte kein gültiges Ergebnis.")
	var result: Dictionary = (raw_result as Dictionary).duplicate(true)
	var ok := bool(result.get("ok", false))
	result["ok"] = ok
	result["code"] = str(result.get("code", "ok" if ok else "action_failed"))
	result["message"] = str(result.get("message",
		"Aktion abgeschlossen." if ok else "Aktion fehlgeschlagen."))
	result["changed"] = bool(result.get("changed", false))
	result["confirmation_required"] = bool(result.get(
		"confirmation_required", false))
	return result


func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"changed": false,
		"confirmation_required": false,
	}


func _record(result: Dictionary, action_id: String, confirm: bool,
		elapsed_usec: int, sequence_override := -1) -> Dictionary:
	var sequence := _sequence if sequence_override < 0 else sequence_override
	var decorated := _decorate(result, action_id, confirm, elapsed_usec, sequence)
	_last_result = decorated.duplicate(true)
	_history.push_front(_last_result.duplicate(true))
	if _history.size() > _history_limit:
		_history.resize(_history_limit)
	var code := str(decorated.get("code", "unknown"))
	_code_counts[code] = int(_code_counts.get(code, 0)) + 1
	return decorated.duplicate(true)


func _decorate(result: Dictionary, action_id: String, confirm: bool,
		elapsed_usec: int, sequence: int) -> Dictionary:
	var decorated := result.duplicate(true)
	decorated["execution"] = {
		"context_id": _context_id,
		"action_id": action_id,
		"confirmed": confirm,
		"sequence": sequence,
		"elapsed_usec": elapsed_usec,
	}
	return decorated
