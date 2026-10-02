extends Node
## Persistente Rekordschicht fuer eigenstaendige, von Diskette gestartete Spiele.
## Eine Runde wird erst mit submit_run() finalisiert. Der vom Spiel gelieferte
## run_id macht den Commit auch ueber Save/Load hinweg genau-einmalig.

signal records_changed(game_id: String)

const SAVE_VERSION := 1
const MAX_SCORE := 2_000_000_000
const MAX_TIME_MS := 86_400_000       # 24 Stunden pro finalisiertem Lauf
const MAX_COUNTER := 1_000_000
const MAX_GAMES := 128
const MAX_RUN_IDS_PER_GAME := 100_000
const MAX_GAME_ID_LENGTH := 64
const MAX_RUN_ID_LENGTH := 128
const MAX_DETAIL_DEPTH := 4
const MAX_DETAIL_ENTRIES := 64
const MAX_DETAIL_STRING := 512

var _records: Dictionary = {}
var _seen_runs: Dictionary = {}       # game_id -> {run_id: true}


func reset() -> void:
	_records = {}
	_seen_runs = {}
	records_changed.emit("")


## Liefert immer eine tiefe Kopie. Aufrufer koennen den internen Rekord dadurch
## nicht versehentlich veraendern.
func record(game_id: String) -> Dictionary:
	var id := _valid_id(game_id, MAX_GAME_ID_LENGTH)
	if id.is_empty() or not _records.has(id):
		return _empty_record()
	return _normalize_record(_records[id])


## Finalisiert genau eine Runde. `completed` bezeichnet einen gewonnenen bzw.
## vollstaendig abgeschlossenen Lauf; auch ein reguläres Game Over ist ein
## finalisierter Play und darf einen Highscore setzen. Bestzeiten zaehlen nur
## fuer completed=true und positive Laufzeiten.
##
## details muss einen stabilen, pro Spiel eindeutigen `run_id` enthalten.
## Rueckgabe: {accepted, duplicate, reason, record}.
func submit_run(game_id: String, score: int, completed: bool, time_ms: int,
		details: Dictionary = {}) -> Dictionary:
	var id := _valid_id(game_id, MAX_GAME_ID_LENGTH)
	if id.is_empty():
		return _result(false, false, "ungueltige game_id", _empty_record())
	var run_id := _valid_id(str(details.get("run_id", "")), MAX_RUN_ID_LENGTH)
	if run_id.is_empty():
		return _result(false, false, "run_id fehlt oder ist ungueltig", record(id))

	var seen: Dictionary = _seen_runs.get(id, {})
	if seen.has(run_id):
		return _result(false, true, "run_id bereits finalisiert", record(id))
	if not _records.has(id) and not _seen_runs.has(id) and _known_game_count() >= MAX_GAMES:
		return _result(false, false, "zu viele Spiel-IDs", _empty_record())
	if seen.size() >= MAX_RUN_IDS_PER_GAME:
		return _result(false, false, "Run-ID-Limit erreicht", record(id))

	var safe_score := clampi(score, 0, MAX_SCORE)
	var safe_time := clampi(time_ms, 0, MAX_TIME_MS)
	var current := record(id)
	current["plays"] = mini(MAX_COUNTER, int(current["plays"]) + 1)
	if completed:
		current["completions"] = mini(MAX_COUNTER, int(current["completions"]) + 1)
	current["best_score"] = maxi(int(current["best_score"]), safe_score)
	if completed and safe_time > 0:
		var previous_best_time := int(current["best_time_ms"])
		if previous_best_time <= 0 or safe_time < previous_best_time:
			current["best_time_ms"] = safe_time
	current["last_score"] = safe_score
	current["last_completed"] = completed
	current["last_time_ms"] = safe_time
	current["last_run_id"] = run_id
	var safe_details := _sanitize_details(details)
	safe_details["run_id"] = run_id
	current["last_details"] = safe_details

	# Run-ID und Rekord werden synchron in demselben Commit geschrieben.
	seen[run_id] = true
	_seen_runs[id] = seen
	_records[id] = current
	PlaytestTelemetry.note_game_run(id, completed, safe_score, safe_time, safe_details)
	records_changed.emit(id)
	return _result(true, false, "", current)


func to_dict() -> Dictionary:
	var records_out := {}
	var record_ids: Array = _records.keys()
	record_ids.sort()
	for id: Variant in record_ids:
		records_out[str(id)] = _normalize_record(_records[id])

	var seen_out := {}
	var seen_ids: Array = _seen_runs.keys()
	seen_ids.sort()
	for id: Variant in seen_ids:
		var run_ids: Array = (_seen_runs[id] as Dictionary).keys()
		run_ids.sort()
		seen_out[str(id)] = run_ids
	return {"version": SAVE_VERSION, "records": records_out, "seen_runs": seen_out}


## Fehlende, alte oder teilweise beschaedigte Save-Bloecke werden defensiv auf
## einen konsistenten Zustand normalisiert. Ein fehlender Block entspricht reset.
func from_dict(data: Variant) -> void:
	_records = {}
	_seen_runs = {}
	if typeof(data) != TYPE_DICTIONARY:
		records_changed.emit("")
		return
	var state: Dictionary = data
	var raw_records: Variant = state.get("records", {})
	if typeof(raw_records) == TYPE_DICTIONARY:
		for raw_id: Variant in (raw_records as Dictionary):
			if _records.size() >= MAX_GAMES:
				break
			var id := _valid_id(str(raw_id), MAX_GAME_ID_LENGTH)
			if id.is_empty():
				continue
			var normalized := _normalize_record((raw_records as Dictionary)[raw_id])
			if int(normalized["plays"]) > 0:
				_records[id] = normalized

	var raw_seen: Variant = state.get("seen_runs", {})
	if typeof(raw_seen) == TYPE_DICTIONARY:
		for raw_id: Variant in (raw_seen as Dictionary):
			var id := _valid_id(str(raw_id), MAX_GAME_ID_LENGTH)
			if id.is_empty():
				continue
			if not _records.has(id) and not _seen_runs.has(id) and _known_game_count() >= MAX_GAMES:
				continue
			var ids_value: Variant = (raw_seen as Dictionary)[raw_id]
			var seen: Dictionary = {}
			if typeof(ids_value) == TYPE_ARRAY:
				for candidate: Variant in (ids_value as Array):
					_add_loaded_run_id(seen, candidate)
			elif typeof(ids_value) == TYPE_DICTIONARY:
				# Vorwaertskompatibel mit einer moeglichen Set-Darstellung.
				for candidate: Variant in (ids_value as Dictionary):
					if bool((ids_value as Dictionary)[candidate]):
						_add_loaded_run_id(seen, candidate)
			if not seen.is_empty():
				_seen_runs[id] = seen
	records_changed.emit("")


func _empty_record() -> Dictionary:
	return {
		"plays": 0,
		"completions": 0,
		"best_score": 0,
		"best_time_ms": 0,
		"last_score": 0,
		"last_completed": false,
		"last_time_ms": 0,
		"last_run_id": "",
		"last_details": {},
	}


func _normalize_record(raw: Variant) -> Dictionary:
	var out := _empty_record()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var source: Dictionary = raw
	out["plays"] = _safe_int(source.get("plays", 0), 0, MAX_COUNTER)
	if int(out["plays"]) <= 0:
		return _empty_record()
	out["completions"] = mini(int(out["plays"]),
		_safe_int(source.get("completions", 0), 0, MAX_COUNTER))
	out["best_score"] = _safe_int(source.get("best_score", 0), 0, MAX_SCORE)
	out["best_time_ms"] = _safe_int(source.get("best_time_ms", 0), 0, MAX_TIME_MS)
	if int(out["completions"]) == 0:
		out["best_time_ms"] = 0
	out["last_score"] = _safe_int(source.get("last_score", 0), 0, MAX_SCORE)
	out["last_completed"] = bool(source.get("last_completed", false))
	out["last_time_ms"] = _safe_int(source.get("last_time_ms", 0), 0, MAX_TIME_MS)
	out["last_run_id"] = _valid_id(str(source.get("last_run_id", "")), MAX_RUN_ID_LENGTH)
	var details: Variant = source.get("last_details", {})
	out["last_details"] = _sanitize_details(details if details is Dictionary else {})
	return out


func _safe_int(value: Variant, minimum: int, maximum: int) -> int:
	var parsed := minimum
	match typeof(value):
		TYPE_INT:
			parsed = int(value)
		TYPE_FLOAT:
			var number := float(value)
			if is_nan(number) or is_inf(number):
				return minimum
			parsed = int(clampf(number, float(minimum), float(maximum)))
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value)
			if not text.is_valid_int():
				return minimum
			parsed = int(text)
		_:
			return minimum
	return clampi(parsed, minimum, maximum)


func _valid_id(raw: String, max_length: int) -> String:
	var id := raw.strip_edges()
	if id.is_empty() or id.length() > max_length:
		return ""
	for i in id.length():
		var code := id.unicode_at(i)
		var alpha_numeric := (code >= 48 and code <= 57) \
			or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if not alpha_numeric and not id[i] in ["_", "-", ".", ":"]:
			return ""
	return id


func _sanitize_details(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var value: Variant = _sanitize_value(raw, 0)
	return value if value is Dictionary else {}


func _sanitize_value(value: Variant, depth: int) -> Variant:
	if depth > MAX_DETAIL_DEPTH:
		return null
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return value
		TYPE_INT:
			return clampi(int(value), -MAX_SCORE, MAX_SCORE)
		TYPE_FLOAT:
			var number := float(value)
			return 0.0 if is_nan(number) or is_inf(number) \
				else clampf(number, -float(MAX_SCORE), float(MAX_SCORE))
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).substr(0, MAX_DETAIL_STRING)
		TYPE_ARRAY:
			var out_array: Array = []
			var source_array: Array = value
			for i in mini(source_array.size(), MAX_DETAIL_ENTRIES):
				out_array.append(_sanitize_value(source_array[i], depth + 1))
			return out_array
		TYPE_DICTIONARY:
			var out_dict := {}
			var source_dict: Dictionary = value
			var keys: Array = source_dict.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			for i in mini(keys.size(), MAX_DETAIL_ENTRIES):
				var key := str(keys[i]).substr(0, MAX_GAME_ID_LENGTH)
				if not key.is_empty():
					out_dict[key] = _sanitize_value(source_dict[keys[i]], depth + 1)
			return out_dict
		_:
			# Fremdtypen nie bis in JSON/Signatur durchsickern lassen.
			return str(value).substr(0, MAX_DETAIL_STRING)


func _add_loaded_run_id(seen: Dictionary, candidate: Variant) -> void:
	if seen.size() >= MAX_RUN_IDS_PER_GAME:
		return
	var run_id := _valid_id(str(candidate), MAX_RUN_ID_LENGTH)
	if not run_id.is_empty():
		seen[run_id] = true


func _known_game_count() -> int:
	var ids: Dictionary = {}
	for id: Variant in _records:
		ids[id] = true
	for id: Variant in _seen_runs:
		ids[id] = true
	return ids.size()


func _result(accepted: bool, is_duplicate: bool, reason: String,
		current_record: Dictionary) -> Dictionary:
	return {
		"accepted": accepted,
		"duplicate": is_duplicate,
		"reason": reason,
		"record": current_record.duplicate(true),
	}
