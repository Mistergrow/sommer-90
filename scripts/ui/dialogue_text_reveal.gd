class_name DialogueTextReveal
extends RefCounted
## Seiteneffektfreier Typewriter-Takt. `advance(delta)` ist die einzige Uhr und
## deshalb in Tests exakt reproduzierbar. `visible_characters` ist eine
## Codepoint-Anzahl fuer Label.visible_characters; kombinierte Grapheme werden
## immer als Einheit freigegeben.

const DEFAULT_CPS := 27.0
const DEFAULT_COMMA_PAUSE := 0.10
const DEFAULT_SENTENCE_PAUSE := 0.22
const DEFAULT_DASH_PAUSE := 0.08
const DEFAULT_NEWLINE_PAUSE := 0.14

var visible_characters := 0
var visible_graphemes := 0

var _text := ""
var _graphemes: Array = []
var _starts: Array = []
var _ends: Array = []
var _accumulator := 0.0
var _wait := 0.0
var _interval := 1.0 / DEFAULT_CPS
var _comma_pause := DEFAULT_COMMA_PAUSE
var _sentence_pause := DEFAULT_SENTENCE_PAUSE
var _dash_pause := DEFAULT_DASH_PAUSE
var _newline_pause := DEFAULT_NEWLINE_PAUSE
var _complete := true
var _timing_events: Array = []
var _timing_cursor := 0


func start(source_text: String, delivery: Variant = {}) -> void:
	_text = source_text
	_split_graphemes(source_text)
	_apply_delivery(delivery)
	visible_characters = 0
	visible_graphemes = 0
	_accumulator = 0.0
	_wait = _interval
	_timing_cursor = 0
	_apply_timing_events(0)
	_complete = _graphemes.is_empty()
	if _delivery_instant(delivery):
		skip()


## Gibt true zurueck, wenn sich die sichtbare Zeichenmenge geaendert hat.
func advance(delta: float) -> bool:
	if _complete:
		return false
	_accumulator += maxf(delta, 0.0)
	var changed := false
	while not _complete and _accumulator + 0.000001 >= _wait:
		_accumulator -= _wait
		var index := visible_graphemes
		visible_graphemes += 1
		visible_characters = int(_ends[index])
		changed = true
		if visible_graphemes >= _graphemes.size():
			_complete = true
			break
		_wait = _interval + _pause_after(str(_graphemes[index]))
		_apply_timing_events(visible_characters)
	return changed


func skip() -> bool:
	if _complete and visible_characters == _text.length():
		return false
	visible_graphemes = _graphemes.size()
	visible_characters = _text.length()
	_complete = true
	_accumulator = 0.0
	return true


func is_complete() -> bool:
	return _complete


func text() -> String:
	return _text


func revealed_text() -> String:
	return _text.substr(0, visible_characters)


func grapheme_count() -> int:
	return _graphemes.size()


func latest_grapheme() -> String:
	if visible_graphemes <= 0 or visible_graphemes > _graphemes.size():
		return ""
	return str(_graphemes[visible_graphemes - 1])


## Codepoint-Startposition des zuletzt sichtbar gewordenen Graphems.
func latest_character_index() -> int:
	if visible_graphemes <= 0 or visible_graphemes > _starts.size():
		return -1
	return int(_starts[visible_graphemes - 1])


func _apply_delivery(delivery: Variant) -> void:
	var cfg: Dictionary = {}
	var profile := ""
	if delivery is Dictionary:
		cfg = delivery
		profile = str(cfg.get("profile", ""))
	else:
		profile = str(delivery)
	var cps := DEFAULT_CPS
	match profile:
		"slow", "calm": cps = 19.0
		"fast", "excited": cps = 34.0
		"phone": cps = 24.0
		"instant": cps = 80.0
	if cfg.has("cps"):
		cps = float(cfg["cps"])
	elif cfg.has("chars_per_second"):
		cps = float(cfg["chars_per_second"])
	_interval = 1.0 / clampf(cps, 4.0, 80.0)
	_comma_pause = maxf(0.0, float(cfg.get("comma_pause", DEFAULT_COMMA_PAUSE)))
	_sentence_pause = maxf(0.0, float(cfg.get("sentence_pause", DEFAULT_SENTENCE_PAUSE)))
	_dash_pause = maxf(0.0, float(cfg.get("dash_pause", DEFAULT_DASH_PAUSE)))
	_newline_pause = maxf(0.0, float(cfg.get("newline_pause", DEFAULT_NEWLINE_PAUSE)))
	_timing_events = cfg.get("timing_events", []).duplicate(true)
	_timing_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("index", 0)) < int(b.get("index", 0)))


func _apply_timing_events(character_index: int) -> void:
	while _timing_cursor < _timing_events.size():
		var event: Dictionary = _timing_events[_timing_cursor]
		if int(event.get("index", 0)) > character_index:
			break
		if event.has("cps"):
			_interval = 1.0 / clampf(float(event["cps"]), 4.0, 80.0)
		if event.has("pause"):
			_wait += clampf(float(event["pause"]), 0.0, 2.0)
		_timing_cursor += 1


func _delivery_instant(delivery: Variant) -> bool:
	if delivery is Dictionary:
		return bool(delivery.get("instant", false)) or str(delivery.get("profile", "")) == "instant"
	return str(delivery) == "instant"


func _pause_after(grapheme: String) -> float:
	if grapheme.contains("\n"):
		return _newline_pause
	var c := grapheme.substr(0, 1)
	if c in [".", "!", "?", "…"]:
		return _sentence_pause
	if c in [",", ";", ":"]:
		return _comma_pause
	if c in ["-", "–", "—"]:
		return _dash_pause
	return 0.0


func _split_graphemes(value: String) -> void:
	_graphemes.clear()
	_starts.clear()
	_ends.clear()
	var current := ""
	var current_start := 0
	var join_next := false
	for i in value.length():
		var part := value.substr(i, 1)
		var code := value.unicode_at(i)
		var attaches := current != "" and (_is_combining(code) or code == 0xFE0F or code == 0xFE0E or join_next or code == 0x200D)
		if current == "":
			current = part
			current_start = i
		elif attaches:
			current += part
		else:
			_graphemes.append(current)
			_starts.append(current_start)
			_ends.append(i)
			current = part
			current_start = i
		join_next = code == 0x200D
	if current != "":
		_graphemes.append(current)
		_starts.append(current_start)
		_ends.append(value.length())


static func _is_combining(code: int) -> bool:
	return (code >= 0x0300 and code <= 0x036F) \
		or (code >= 0x1AB0 and code <= 0x1AFF) \
		or (code >= 0x1DC0 and code <= 0x1DFF) \
		or (code >= 0x20D0 and code <= 0x20FF) \
		or (code >= 0xFE20 and code <= 0xFE2F)
