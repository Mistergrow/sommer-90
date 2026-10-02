extends RefCounted
## Robuster Parser für ProTracker-/FastTracker-MODs. Er liefert ausschließlich
## validierte Laufzeitdaten und verändert keinen Playerzustand.

const SIGNATURE_CHANNELS := {
	"M.K.": 4, "M!K!": 4, "M&K!": 4, "N.T.": 4,
	"FLT4": 4, "4CHN": 4, "TDZ4": 4, "FA04": 4,
	"6CHN": 6, "8CHN": 8,
}
const MAX_FILE_BYTES := 8 * 1024 * 1024


## Bounded header inspection for user libraries, without allocating patterns.
## External files must contain their complete declared sample payload.
static func inspect(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("MOD-Datei konnte nicht geöffnet werden.")
	var length := file.get_length()
	if length < 1084 or length > MAX_FILE_BYTES:
		return _failure("MOD-Dateigröße außerhalb von 1084 Bytes bis 8 MiB.")
	var header := file.get_buffer(1084)
	var signature := header.slice(1080, 1084).get_string_from_ascii()
	if not SIGNATURE_CHANNELS.has(signature):
		return _failure("Unterstützt werden ProTracker-MODs mit 4, 6 oder 8 Kanälen.")
	var orders := int(header[950])
	if orders < 1 or orders > 128:
		return _failure("Ungültige MOD-Abspielliste.")
	var max_pattern := 0
	for index in orders:
		max_pattern = maxi(max_pattern, header[952 + index])
	var required := 1084 + (max_pattern + 1) * 256 * int(SIGNATURE_CHANNELS[signature])
	var sample_bytes := 0
	for index in 31:
		var offset := 20 + index * 30 + 22
		sample_bytes += (header[offset] << 8 | header[offset + 1]) * 2
	if required + sample_bytes > length or sample_bytes == 0:
		return _failure("MOD enthält abgeschnittene oder fehlende Sampledaten.")
	return {"ok": true, "title": _cstr(header, 0, 20), "bytes": length,
		"channel_count": int(SIGNATURE_CHANNELS[signature]), "orders": orders}


static func parse(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("MOD-Datei konnte nicht geöffnet werden.")
	if file.get_length() > MAX_FILE_BYTES:
		return _failure("MOD-Datei überschreitet 8 MiB.")
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 1084:
		return _failure("Datei ist zu kurz fuer ein ProTracker-Modul.")
	var signature := bytes.slice(1080, 1084).get_string_from_ascii()
	if not SIGNATURE_CHANNELS.has(signature):
		return _failure(
			"Nicht unterstuetztes MOD-Format '%s' (unterstuetzt: 4/6/8 Kanaele)." %
			signature)
	var channels := int(SIGNATURE_CHANNELS[signature])
	var title := _cstr(bytes, 0, 20)
	var samples: Array = []
	var offset := 20
	for _index in 31:
		var sample_length := (bytes[offset + 22] << 8 | bytes[offset + 23]) * 2
		var finetune := bytes[offset + 24] & 0x0F
		if finetune >= 8:
			finetune -= 16
		samples.append({
			"len": sample_length,
			"finetune": finetune,
			"vol": clampi(int(bytes[offset + 25]), 0, 64),
			"loop_start": (bytes[offset + 26] << 8 | bytes[offset + 27]) * 2,
			"loop_len": (bytes[offset + 28] << 8 | bytes[offset + 29]) * 2,
			"data": PackedByteArray(),
		})
		offset += 30
	var song_length := clampi(int(bytes[950]), 0, 128)
	if song_length <= 0:
		return _failure("MOD enthaelt keine gueltige Abspielliste.")
	var raw_restart := int(bytes[951])
	var restart_position := raw_restart \
		if raw_restart >= 0 and raw_restart < song_length else 0
	var order: Array = []
	var max_pattern := 0
	for index in 128:
		var pattern_index := int(bytes[952 + index])
		order.append(pattern_index)
		if index < song_length:
			max_pattern = maxi(max_pattern, pattern_index)
	var pattern_offset := 1084
	var pattern_end := pattern_offset + (max_pattern + 1) * 64 * channels * 4
	if pattern_end > bytes.size():
		return _failure("MOD-Patterndaten sind abgeschnitten.")
	var patterns: Array = []
	for _pattern_index in max_pattern + 1:
		var pattern: Array = []
		for _row_index in 64:
			var row: Array = []
			for _channel_index in channels:
				var byte_0 := int(bytes[pattern_offset])
				var byte_1 := int(bytes[pattern_offset + 1])
				var byte_2 := int(bytes[pattern_offset + 2])
				var byte_3 := int(bytes[pattern_offset + 3])
				row.append({
					"period": ((byte_0 & 0x0F) << 8) | byte_1,
					"sample": (byte_0 & 0xF0) | ((byte_2 & 0xF0) >> 4),
					"eff": byte_2 & 0x0F,
					"param": byte_3,
				})
				pattern_offset += 4
			pattern.append(row)
		patterns.append(pattern)
	for sample: Dictionary in samples:
		var declared_length := int(sample["len"])
		var available := clampi(bytes.size() - pattern_offset, 0, declared_length)
		var data := bytes.slice(pattern_offset, pattern_offset + available) \
			if available > 0 else PackedByteArray()
		sample["data"] = data
		sample["len"] = data.size()
		var loop_start := clampi(int(sample["loop_start"]), 0, data.size())
		var loop_length := clampi(int(sample["loop_len"]), 0,
			data.size() - loop_start)
		if loop_length <= 2 or loop_start >= data.size():
			loop_start = 0
			loop_length = 0
		sample["loop_start"] = loop_start
		sample["loop_len"] = loop_length
		# Der Dateioffset folgt der deklarierten Länge; fehlende Bytes eines
		# beschädigten Samples dürfen spätere Sampleköpfe nicht verschieben.
		pattern_offset += declared_length
	return {
		"ok": true,
		"title": title,
		"channel_count": channels,
		"samples": samples,
		"patterns": patterns,
		"order": order,
		"song_len": song_length,
		"restart_position": restart_position,
		"legacy_pattern_break_zero": title.to_lower().begins_with("2-3song"),
	}


static func _cstr(bytes: PackedByteArray, start: int, length: int) -> String:
	var result := ""
	for index in length:
		var character := bytes[start + index]
		if character == 0:
			break
		result += char(character) if character >= 32 else " "
	return result.strip_edges()


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
