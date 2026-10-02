extends RefCounted
## Zustandsloser P-8-Rätselkern.
##
## Die Engine kennt weder Autoloads noch Inventar- oder Savegame-Zustand. Sie
## erzeugt und bewertet ausschließlich die fiktiven Lichtwert-Matrizen aus
## expliziter Konfiguration, Seed, Schwierigkeit und Schutzrevision.

const DeterministicArray := preload("res://scripts/util/deterministic_array.gd")


static func generate(config: Dictionary, puzzle_seed: int, difficulty: String,
		revision: int) -> Dictionary:
	var normalized_difficulty := _normalize_difficulty(config, difficulty)
	var difficulties: Dictionary = config.get("difficulties", {})
	var difficulty_data: Dictionary = difficulties.get(normalized_difficulty, {})
	var revision_data := revision_definition(config, revision)
	var rng := RandomNumberGenerator.new()
	rng.seed = puzzle_seed ^ hash(normalized_difficulty) ^ hash("REVISION/%d" % revision)
	var base_rows := int(difficulty_data.get("rows", 5))
	var row_count := base_rows + int(revision_data.get("extra_rows", 0))
	var rows: Array = []
	var rules: Array = []
	for i in row_count:
		var left := rng.randi_range(0, 255)
		var right := rng.randi_range(0, 255)
		var token := rng.randi_range(1, 15)
		var kind := i % 3
		var expected := 0
		var hint := ""
		match kind:
			0:
				expected = (left + right + token) & 0xFF
				hint = "P-8-Regel: beide Leuchtwerte plus Phasenmarker %X ergeben den Mittelwert." % token
			1:
				expected = ((left & 0xF0) | ((right + token) & 0x0F)) & 0xFF
				hint = "P-8-Regel: oberes Farbfeld links, untere Phase rechts plus %X." % token
			_:
				expected = ((((right & 0x0F) << 4) | (left & 0x0F)) ^ token) & 0xFF
				hint = "P-8-Regel: die beiden unteren Lichtnibbles spiegeln, dann Marker %X beachten." % token
		var mutable_index := 2 + (i % 2)
		var cells: Array = [
			_hex(left),
			_hex((left + token * 3) & 0xFF),
			_hex((left ^ right ^ token) & 0xFF),
			_hex((right - token) & 0xFF),
			_hex(right),
		]
		cells[mutable_index] = "??"
		var choices: Array = [_hex(expected)]
		while choices.size() < 3:
			var decoy := _hex((expected + rng.randi_range(7, 73)) & 0xFF)
			if decoy not in choices:
				choices.append(decoy)
		DeterministicArray.shuffle(choices, rng)
		var row_label := "P-8 PHASENZEILE %s" % char(65 + i)
		if i >= base_rows:
			var steps: Array = revision_data.get("steps", [])
			var step_index := clampi(i - base_rows + 1, 0, maxi(0, steps.size() - 1))
			row_label = "P-8 ZUSATZ · %s" % str(
				steps[step_index] if not steps.is_empty() else "REVISIONSSYNC")
		rows.append({
			"id": "phase_%02d" % (i + 1),
			"label": row_label,
			"cells": cells,
			"mutable_index": mutable_index,
			"choices": choices,
			"hint": hint,
			"rule_kind": kind,
			"marker": "%X" % token,
			"_solution": _hex(expected),
		})
		rules.append(hint)
	return {
		"ok": true,
		"id": "p8-%08X" % (puzzle_seed & 0xFFFFFFFF),
		"seed": puzzle_seed,
		"difficulty": normalized_difficulty,
		"revision": revision,
		"revision_name": str(revision_data.get("name", "P-8 V%d" % revision)),
		"revision_steps": (revision_data.get("steps", []) as Array).duplicate(),
		"rows": rows,
		"rules": rules,
		"fictional": true,
		"notice": "Abstrakte P-8-Lichtwerte — keine realen Programmdaten.",
	}


static func auto_solution(puzzle: Dictionary) -> Dictionary:
	var result := {}
	for row: Dictionary in puzzle.get("rows", []):
		result[str(row.get("id", ""))] = str(row.get("_solution", ""))
	return result


static func verify(config: Dictionary, puzzle: Dictionary, answers: Variant,
		manual: bool = true) -> Dictionary:
	if not puzzle.get("ok", false) or not puzzle.get("fictional", false):
		return {
			"ok": false,
			"score": 0,
			"stability": 0,
			"text": Loc.t("sys.scene_release_manager.ungultiger_p_8_lauf",
				"Ungültiger P-8-Lauf."),
			"row_results": [],
		}
	var rows: Array = puzzle.get("rows", [])
	var row_results: Array = []
	var correct := 0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var answer := ""
		if answers is Dictionary:
			answer = str((answers as Dictionary).get(str(row.get("id", "")), ""))
		elif answers is Array and i < (answers as Array).size():
			answer = str((answers as Array)[i])
		answer = answer.strip_edges().to_upper()
		var is_correct := answer == str(row.get("_solution", ""))
		if is_correct:
			correct += 1
		row_results.append({
			"id": row.get("id", ""),
			"ok": is_correct,
			"answer": answer,
		})
	var all_correct := not rows.is_empty() and correct == rows.size()
	var difficulty := str(puzzle.get("difficulty", "standard"))
	var difficulty_data: Dictionary = config.get("difficulties", {}).get(difficulty, {})
	var score := int(round(float(correct) / maxf(1.0, float(rows.size()))
		* float(difficulty_data.get("score", 86))))
	var stability := int(round(float(correct) / maxf(1.0, float(rows.size()))
		* float(difficulty_data.get("stability", 91))))
	var revision := maxi(1, int(puzzle.get("revision", 1)))
	var revision_data := revision_definition(config, revision)
	var boot_results: Array = [all_correct, all_correct, all_correct]
	var boot_diagnostics: Array = []
	if not all_correct:
		var ratio := float(correct) / maxf(1.0, float(rows.size()))
		boot_results = [ratio >= 0.72, ratio >= 0.86, false]
		var faults: Array = revision_data.get("boot_faults", [])
		if faults.is_empty():
			faults = ["PHASE UNSTABLE"]
		for i in 3:
			boot_diagnostics.append(
				"OK" if bool(boot_results[i]) else str(faults[i % faults.size()]))
	return {
		"ok": all_correct,
		"score": score,
		"stability": stability,
		"text": "Drei Testboots stabil — P-8 verifiziert." if all_correct \
			else "%d/%d Phasen stimmen noch nicht." % [correct, rows.size()],
		"row_results": row_results,
		"boot_results": boot_results,
		"boot_diagnostics": boot_diagnostics,
		"revision": revision,
		"revision_name": str(revision_data.get("name", "P-8 V%d" % revision)),
		"completed_steps": (revision_data.get("steps", []) as Array).duplicate() \
			if all_correct else [],
		"manual": manual,
	}


static func revision_definition(config: Dictionary, revision: int) -> Dictionary:
	var definitions: Dictionary = config.get("protection_revisions", {})
	var value: Variant = definitions.get(str(maxi(1, revision)), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _normalize_difficulty(config: Dictionary, value: String) -> String:
	var difficulty := value.to_lower()
	difficulty = {"relaxed": "entspannt", "scene": "szene"}.get(difficulty, difficulty)
	var difficulties: Dictionary = config.get("difficulties", {})
	return difficulty if difficulties.has(difficulty) else "standard"


static func _hex(value: int) -> String:
	return "%02X" % (value & 0xFF)
