extends RefCounted
## Fasst mehrere Zustandsaenderungen innerhalb eines Frames zu genau einer
## Quest-Auswertung zusammen. Der Scheduler besitzt keine Questlogik und kann
## beim Slotwechsel/Reset sicher verworfen werden.

var _evaluate_callback: Callable
var _pending := false


func _init(evaluate_callback: Callable) -> void:
	_evaluate_callback = evaluate_callback


func request() -> void:
	if _pending:
		return
	_pending = true
	call_deferred("_flush")


func cancel() -> void:
	_pending = false


func _flush() -> void:
	if not _pending:
		return
	_pending = false
	if _evaluate_callback.is_valid():
		_evaluate_callback.call()
