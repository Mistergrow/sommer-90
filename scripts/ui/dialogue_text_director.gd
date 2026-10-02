class_name DialogueTextDirector
extends RefCounted
## Kompiliert Sprecherprofil + Knotenregie + unsichtbare Inline-Kommandos in
## einen gemeinsamen Vertrag fuer RichText, Reveal-Uhr und Portrait-Lipsync.

const CONFIG := "res://data/dialogue_direction.json"
const GLOBAL_TECH := ["Amiga", "Diskette", "Monitor", "Modem", "BBS", "RAM", "Code", "Pixel", "Tracker", "Hardware"]
const EFFECT_PRIORITY := {"punch": 5, "tech": 4, "em": 3, "whisper": 2}

var data: Dictionary = {}


func _init(custom_data: Dictionary = {}) -> void:
	if not custom_data.is_empty():
		data = custom_data.duplicate(true)
	elif FileAccess.file_exists(CONFIG):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		data = parsed if parsed is Dictionary else {}


func profile(speaker_id: String, direction: Variant = {}, context: Dictionary = {}) -> Dictionary:
	var result: Dictionary = data.get("default", {}).duplicate(true)
	var speakers: Dictionary = data.get("speakers", {})
	var own: Dictionary = speakers.get(speaker_id, {})
	var base := str(own.get("base", ""))
	if base != "": result.merge(data.get("archetypes", {}).get(base, {}), true)
	result.merge(own, true)
	if direction is String and str(direction) != "":
		var named: Dictionary = data.get("archetypes", {}).get(str(direction), {})
		result.merge(named, true)
	elif direction is Dictionary:
		var named_base := str(direction.get("profile", ""))
		if named_base != "": result.merge(data.get("archetypes", {}).get(named_base, {}), true)
		result.merge(direction, true)
	_apply_context(result, context)
	result["speaker_id"] = speaker_id
	return result


func compile(text: String, speaker_id: String, direction: Variant = {}, context: Dictionary = {}) -> Dictionary:
	var p := profile(speaker_id, direction, context)
	var parsed := _parse_commands(text, p)
	var clean: String = parsed.text
	var spans: Array = parsed.spans
	var occupied: Array[bool] = []
	occupied.resize(clean.length())
	occupied.fill(false)
	for span: Dictionary in spans:
		_mark(occupied, int(span.start), int(span.end))

	var keywords: Dictionary = p.get("keywords", {}).duplicate(true)
	for word: String in GLOBAL_TECH:
		if not keywords.has(word): keywords[word] = "tech"
	for word: Variant in keywords:
		_add_word_spans(clean, str(word), str(keywords[word]), spans, occupied)
	_add_caps_spans(clean, spans, occupied)
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.start) < int(b.start))

	var delivery := {
		"cps": float(p.get("cps", 27.0)),
		"comma_pause": float(p.get("comma_pause", 0.10)),
		"sentence_pause": float(p.get("sentence_pause", 0.22)),
		"dash_pause": float(p.get("dash_pause", 0.08)),
		"newline_pause": float(p.get("newline_pause", 0.14)),
		"timing_events": parsed.timing_events,
	}
	return {"text": clean, "bbcode": _render(clean, spans, p), "profile": p,
		"delivery": delivery, "spans": spans, "timing_events": parsed.timing_events}


## Legt die aktuelle Gefuehlslage ueber die unverwechselbare Grundstimme der
## Figur. Beziehung, Tageszeit und Kanal veraendern nur Nuancen; sie duerfen
## niemals die kuratierte Sprecherregie oder explizite Knotenwerte ersetzen.
func _apply_context(target: Dictionary, context: Dictionary) -> void:
	if context.is_empty():
		return
	var emotion := str(context.get("emotion", "neutral"))
	var emotion_style: Dictionary = data.get("emotions", {}).get(emotion, {})
	if not emotion_style.is_empty():
		var tempo := float(emotion_style.get("tempo", 1.0))
		var pause_scale := float(emotion_style.get("pause_scale", 1.0))
		target["cps"] = clampf(float(target.get("cps", 27.0)) * tempo, 12.0, 46.0)
		for key in ["comma_pause", "sentence_pause", "dash_pause", "newline_pause"]:
			if target.has(key):
				target[key] = clampf(float(target[key]) * pause_scale, 0.02, 0.8)
		target["intensity"] = clampf(float(target.get("intensity", 1.0)) \
			* float(emotion_style.get("intensity_scale", 1.0)), 0.35, 1.45)
		if emotion_style.has("entrance"):
			target["entrance"] = emotion_style["entrance"]
	var trust := clampi(int(context.get("trust", 50)), 0, 100)
	if trust >= 75:
		target["comma_pause"] = float(target.get("comma_pause", 0.1)) * 0.9
		target["intensity"] = minf(1.45, float(target.get("intensity", 1.0)) + 0.06)
	elif trust <= 20:
		target["comma_pause"] = float(target.get("comma_pause", 0.1)) * 1.12
	var slot := clampi(int(context.get("slot", 2)), 0, 4)
	if slot == 4:
		target["cps"] = maxf(12.0, float(target.get("cps", 27.0)) * 0.92)
	if str(context.get("channel", "in_person")) == "phone":
		target["entrance"] = "terminal"
		target["cps"] = maxf(12.0, float(target.get("cps", 27.0)) * 0.95)
	target["emotion"] = emotion


func _parse_commands(source: String, p: Dictionary) -> Dictionary:
	var clean := ""
	var spans: Array = []
	var events: Array = []
	var stack: Array[Dictionary] = []
	var i := 0
	while i < source.length():
		if source.substr(i, 1) == "{":
			var close := source.find("}", i + 1)
			if close >= 0:
				var cmd := source.substr(i + 1, close - i - 1).strip_edges().to_lower()
				if _apply_command(cmd, clean.length(), stack, spans, events, p):
					i = close + 1
					continue
		clean += source.substr(i, 1)
		i += 1
	while not stack.is_empty():
		var open: Dictionary = stack.pop_back()
		if clean.length() > int(open.start): spans.append({"start": open.start, "end": clean.length(), "effect": open.effect})
	return {"text": clean, "spans": spans, "timing_events": events}


func _apply_command(cmd: String, index: int, stack: Array[Dictionary], spans: Array,
		events: Array, p: Dictionary) -> bool:
	if cmd == "pause" or cmd.begins_with("pause="):
		var amount := 0.28 if cmd == "pause" else clampf(float(cmd.trim_prefix("pause=")), 0.0, 2.0)
		events.append({"index": index, "pause": amount})
		return true
	if cmd in ["fast", "slow", "normal"]:
		var cps := float(p.get("cps", 27.0))
		if cmd == "fast": cps *= 1.42
		if cmd == "slow": cps *= 0.68
		events.append({"index": index, "cps": clampf(cps, 4.0, 80.0)})
		return true
	if cmd in ["em", "punch", "whisper", "tech"]:
		stack.append({"effect": cmd, "start": index})
		return true
	if cmd.begins_with("/"):
		var wanted := cmd.trim_prefix("/")
		for n in range(stack.size() - 1, -1, -1):
			if str(stack[n].effect) == wanted:
				var open: Dictionary = stack[n]
				stack.remove_at(n)
				if index > int(open.start): spans.append({"start": open.start, "end": index, "effect": wanted})
				return true
	return false


func _add_word_spans(text: String, word: String, effect: String, spans: Array, occupied: Array[bool]) -> void:
	if word == "" or effect not in EFFECT_PRIORITY: return
	var lower := text.to_lower()
	var needle := word.to_lower()
	var at := lower.find(needle)
	while at >= 0:
		var end := at + needle.length()
		if _word_boundary(text, at, end) and _free(occupied, at, end):
			spans.append({"start": at, "end": end, "effect": effect})
			_mark(occupied, at, end)
		at = lower.find(needle, maxi(end, at + 1))


func _add_caps_spans(text: String, spans: Array, occupied: Array[bool]) -> void:
	var start := -1
	for i in text.length() + 1:
		var c := text.substr(i, 1) if i < text.length() else " "
		var letter := c.to_lower() != c.to_upper()
		if letter and c == c.to_upper():
			if start < 0: start = i
		elif start >= 0:
			if i - start >= 3 and _free(occupied, start, i):
				spans.append({"start": start, "end": i, "effect": "punch"})
				_mark(occupied, start, i)
			start = -1


func _render(text: String, spans: Array, p: Dictionary) -> String:
	var starts: Dictionary = {}
	var ends: Dictionary = {}
	for span: Dictionary in spans:
		starts[int(span.start)] = str(span.effect)
		ends[int(span.end)] = str(span.effect)
	var out := "[color=%s][font_size=%d]" % [str(p.get("color", "#e8edf2")), int(p.get("font_size", 18))]
	for i in text.length() + 1:
		if ends.has(i): out += _close_tag(str(ends[i]))
		if starts.has(i): out += _open_tag(str(starts[i]), p)
		if i < text.length(): out += _escape(text.substr(i, 1))
	return "[type_in]%s[/font_size][/color][/type_in]" % out


func _open_tag(effect: String, p: Dictionary) -> String:
	var accent := str(p.get("accent", "#f0c96b"))
	match effect:
		"punch": return "[color=%s][font_size=%d][shake rate=20.0 level=5]" % [accent, int(p.get("font_size", 18)) + 2]
		"tech": return "[color=#69d8ee][font_size=%d]" % (int(p.get("font_size", 18)) + 1)
		"whisper": return "[color=#aab3bf][font_size=%d]" % maxi(12, int(p.get("font_size", 18)) - 2)
		_: return "[color=%s][wave amp=7.0 freq=3.0]" % accent


func _close_tag(effect: String) -> String:
	match effect:
		"punch": return "[/shake][/font_size][/color]"
		"tech", "whisper": return "[/font_size][/color]"
		_: return "[/wave][/color]"


func _escape(c: String) -> String:
	return "[lb]" if c == "[" else c


func _word_boundary(text: String, start: int, end: int) -> bool:
	return (start == 0 or not _is_word(text.substr(start - 1, 1))) and (end >= text.length() or not _is_word(text.substr(end, 1)))


func _is_word(c: String) -> bool:
	return c.to_lower() != c.to_upper() or c >= "0" and c <= "9" or c == "_"


func _free(mask: Array[bool], start: int, end: int) -> bool:
	for i in range(maxi(0, start), mini(mask.size(), end)):
		if mask[i]: return false
	return true


func _mark(mask: Array[bool], start: int, end: int) -> void:
	for i in range(maxi(0, start), mini(mask.size(), end)): mask[i] = true
