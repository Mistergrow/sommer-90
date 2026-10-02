extends RefCounted
## Kleine Tick-Historie fuer die Darstellung bereits verbrauchter Audioframes.
## Der Mixer bleibt unveraendert. Der Generatorpuffer wird kompensiert; die
## nachgelagerte Geraete-/Treiberlatenz ist keine samplegenaue Hardware-Uhr.

const NOTE_NAMES := ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
const PERIODS := [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,
	428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,
	214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113]

var submitted_frames := 0
var _ticks: Array[Dictionary] = []


func reset() -> void:
	submitted_frames = 0
	_ticks.clear()


func record(frame: int, order: int, row: int, tick: int, speed: int,
		bpm: int, channels: Array) -> void:
	var levels := PackedFloat32Array()
	for channel: Dictionary in channels:
		levels.append(clampf(float(channel.get("vol", 0)) / 64.0, 0.0, 1.0)
			if bool(channel.get("active", false)) else 0.0)
	_ticks.append({"frame": frame, "order": order, "row": row, "tick": tick,
		"speed": speed, "bpm": bpm, "levels": levels})


func state_at(consumed_frame: int) -> Dictionary:
	# Auch ohne offene Tracker-UI wird vor jeder Generatorfuellung gekuerzt.
	# Nur der letzte verbrauchte Tick und die gepufferten Zukunftsticks bleiben.
	while _ticks.size() > 1 and int(_ticks[1]["frame"]) <= consumed_frame:
		_ticks.pop_front()
	return _ticks[0] if not _ticks.is_empty() else {}


static func note_name(period: int) -> String:
	if period <= 0:
		return "---"
	var best := 0
	var best_d := 99999
	for i in PERIODS.size():
		var distance := absi(PERIODS[i] - period)
		if distance < best_d:
			best_d = distance
			best = i
	return "%s%d" % [NOTE_NAMES[best % 12], floori(float(best) / 12.0) + 1]


static func format_view(state: Dictionary, order: Array, patterns: Array,
		song_len: int, channels: int, rows: int) -> Dictionary:
	var last_order := mini(song_len, order.size()) - 1
	if last_order < 0:
		return {"ok": false}
	var current_order := int(state.get("order", 0))
	var current_row := int(state.get("row", 0))
	var patt := int(order[clampi(current_order, 0, last_order)])
	if patt < 0 or patt >= patterns.size():
		return {"ok": false}
	var pattern: Array = patterns[patt]
	var half := floori(float(rows) / 2.0)
	var out_rows: Array = []
	for off in range(-half, rows - half):
		var row := current_row + off
		if row < 0 or row >= pattern.size():
			var empty_cells: Array[String] = []
			empty_cells.resize(channels)
			empty_cells.fill("")
			out_rows.append({"row": -1, "cells": empty_cells})
			continue
		var cells: Array = []
		for channel in channels:
			var cell: Dictionary = pattern[row][channel]
			cells.append("%s %02X %X%02X" % [note_name(int(cell["period"])),
				int(cell["sample"]), int(cell["eff"]), int(cell["param"])])
		out_rows.append({"row": row, "cells": cells})
	return {"ok": true, "order": current_order, "orders": song_len, "pattern": patt,
		"row": current_row, "speed": int(state.get("speed", 6)),
		"bpm": int(state.get("bpm", 125)), "tick": int(state.get("tick", 0)),
		"channels": channels, "rows": out_rows}
