extends RefCounted
## Kleiner, UI-freier FIFO fuer Quest-Einblendungen.
##
## QuestManager kann in einem evaluate()-Durchlauf einen Auftrag aktivieren und
## sofort mehrere bereits erfuellte Stufen abhaken. Der Puffer verdichtet solche
## Burst-Ereignisse auf den letzten sinnvollen Zustand derselben Quest, behaelt
## aber die Reihenfolge verschiedener Auftraege. Er ist absichtlich fluechtig:
## Praesentationen gehoeren nie in den Spielstand.

const MAX_PENDING := 6
const MAX_SEEN := 32

var _pending: Array[Dictionary] = []
var _seen: Array[String] = []


func enqueue(event: Dictionary) -> bool:
	var normalized := _normalize(event)
	if normalized.is_empty():
		return false
	var signature := _signature(normalized)
	if signature in _seen:
		return false
	_remember(signature)

	# Mehrere Zustandswechsel derselben Quest innerhalb desselben Frames werden
	# nicht minutenlang nacheinander abgespielt. Der juengste Zustand gewinnt.
	var quest_id := str(normalized["id"])
	for index in range(_pending.size() - 1, -1, -1):
		if str(_pending[index].get("id", "")) == quest_id:
			_pending[index] = normalized
			return true

	if _pending.size() >= MAX_PENDING:
		var discard_index := _least_important_index()
		_pending.remove_at(discard_index)
	_pending.append(normalized)
	return true


func pop_next() -> Dictionary:
	if _pending.is_empty():
		return {}
	return _pending.pop_front()


func peek() -> Dictionary:
	return {} if _pending.is_empty() else _pending[0].duplicate(true)


func size() -> int:
	return _pending.size()


func is_empty() -> bool:
	return _pending.is_empty()


func clear() -> void:
	_pending.clear()
	_seen.clear()


func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in _pending:
		out.append(event.duplicate(true))
	return out


func _normalize(event: Dictionary) -> Dictionary:
	var kind := str(event.get("kind", ""))
	var quest_id := str(event.get("id", event.get("quest_id", "")))
	if kind not in ["started", "stage", "completed"] or quest_id.is_empty():
		return {}
	var out := event.duplicate(true)
	out["id"] = quest_id
	out["kind"] = kind
	out["stage_number"] = maxi(0, int(out.get("stage_number", 0)))
	out["stage_count"] = maxi(0, int(out.get("stage_count", 0)))
	return out


func _signature(event: Dictionary) -> String:
	return "%s|%s|%d" % [
		str(event.get("id", "")),
		str(event.get("kind", "")),
		int(event.get("stage_number", 0)),
	]


func _remember(signature: String) -> void:
	_seen.append(signature)
	if _seen.size() > MAX_SEEN:
		_seen.pop_front()


func _least_important_index() -> int:
	# Zwischenziele duerfen bei einem extremen Burst zuerst weichen. Starts sind
	# wichtiger; Abschluesse werden nur verworfen, wenn wirklich alles andere
	# bereits aus Abschluessen besteht.
	for index in _pending.size():
		if str(_pending[index].get("kind", "")) == "stage":
			return index
	for index in _pending.size():
		if str(_pending[index].get("kind", "")) == "started":
			return index
	return 0
