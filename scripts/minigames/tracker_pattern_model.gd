class_name TrackerPatternModel
extends RefCounted
## Reines 4-Kanal/8-Step-Groove-Modell. Kein Zeitdruck: musikalische Struktur,
## Variation und Lesbarkeit entscheiden, nicht Klickgeschwindigkeit.

const TRACKS := [&"kick", &"snare", &"hat", &"bass"]
const STEPS := 8

var level := 1
var run_seed := 1
var cells: Array = []
var patterns: Array = []
var current_pattern := 0
var order: Array[int] = [0]
var samples: Array[StringName] = [&"bd_909", &"sd_noise", &"hh_closed", &"bass_square"]
var effects: Array[int] = [0, 0, 0, 0]
var edits := 0
var hints := 0
var assisted := false


func configure(next_level: int, next_seed: int) -> void:
	level = clampi(next_level, 1, 4)
	run_seed = next_seed
	patterns = [_empty_pattern()]
	current_pattern = 0
	cells = patterns[0]
	order = [0]
	samples = [&"bd_909", &"sd_noise", &"hh_closed", &"bass_square"]
	effects = [0, 0, 0, 0]
	edits = 0
	hints = 0
	assisted = false

func _empty_pattern() -> Array:
	var pattern: Array = []
	for _track in TRACKS:
		var row: Array = []; row.resize(STEPS); row.fill(false); pattern.append(row)
	return pattern

func add_pattern(copy_current := false) -> bool:
	if patterns.size() >= 4: return false
	patterns.append(cells.duplicate(true) if copy_current else _empty_pattern())
	order.append(patterns.size() - 1)
	select_pattern(patterns.size() - 1); edits += 1; return true

func select_pattern(index: int) -> bool:
	if index < 0 or index >= patterns.size(): return false
	current_pattern = index; cells = patterns[index]; return true

func cycle_sample(track: int) -> StringName:
	if track < 0 or track >= TRACKS.size(): return &""
	var banks := [[&"bd_909",&"bd_deep",&"bd_click"],[&"sd_noise",&"sd_tight",&"sd_clap"],
		[&"hh_closed",&"hh_open",&"hh_metal"],[&"bass_square",&"bass_saw",&"bass_pulse"]]
	var bank: Array = banks[track]; samples[track] = bank[(bank.find(samples[track]) + 1) % bank.size()]; edits += 1; return samples[track]

func cycle_effect(track: int) -> int:
	if track < 0 or track >= TRACKS.size(): return 0
	effects[track] = (effects[track] + 1) % 4; edits += 1; return effects[track]


func toggle(track: int, step: int) -> void:
	if track < 0 or track >= TRACKS.size() or step < 0 or step >= STEPS:
		return
	cells[track][step] = not bool(cells[track][step])
	edits += 1


func active(track: int, step: int) -> bool:
	return track >= 0 and track < cells.size() and step >= 0 and step < STEPS and bool(cells[track][step])


func count_track(track: int) -> int:
	var count := 0
	for step in STEPS:
		if active(track, step):
			count += 1
	return count


func syncopation() -> int:
	var count := 0
	for step in [1, 3, 5, 7]:
		if active(0, step) or active(3, step):
			count += 1
	return count


func evaluation() -> Dictionary:
	var faults: Array[String] = []
	if not active(0, 0): faults.append("Kick auf Step 1 setzt den Downbeat.")
	if count_track(0) < 2: faults.append("Mindestens zwei Kicks setzen.")
	if not active(1, 2) or not active(1, 6): faults.append("Snare auf 3 und 7 stabilisiert den Backbeat.")
	if count_track(2) < 4: faults.append("Mindestens vier Hi-Hats halten den Puls.")
	if count_track(3) < 2: faults.append("Der Bass braucht mindestens zwei Noten.")
	if level >= 2 and syncopation() < 1: faults.append("Eine Kick- oder Bass-Synkope auf einem Zwischenstep fehlt.")
	if level >= 3 and count_track(2) < 6: faults.append("Fortgeschritten: mindestens sechs Hi-Hats.")
	if level >= 4 and syncopation() < 2: faults.append("Profi: zwei Synkopen geben dem Pattern Bewegung.")
	var total := 0
	for track in TRACKS.size(): total += count_track(track)
	if total > 19: faults.append("Zu voll: maximal 19 Events lassen Luft im Mix.")
	return {"valid": faults.is_empty(), "faults": faults, "events": total,
		"syncopation": syncopation()}


func apply_hint() -> Vector2i:
	var hint_order := [Vector2i(0, 0), Vector2i(1, 2), Vector2i(1, 6), Vector2i(0, 4),
		Vector2i(2, 0), Vector2i(2, 2), Vector2i(2, 4), Vector2i(2, 6),
		Vector2i(3, 0), Vector2i(3, 4), Vector2i(3, 3), Vector2i(0, 5),
		Vector2i(2, 1), Vector2i(2, 3)]
	for cell: Vector2i in hint_order:
		if not active(cell.x, cell.y):
			cells[cell.x][cell.y] = true
			hints += 1
			return cell
	return Vector2i(-1, -1)


func load_demo() -> void:
	configure(level, run_seed)
	for cell in [Vector2i(0, 0), Vector2i(0, 4), Vector2i(0, 5), Vector2i(1, 2),
		Vector2i(1, 6), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
		Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 6), Vector2i(3, 0),
		Vector2i(3, 3), Vector2i(3, 4)]:
		cells[cell.x][cell.y] = true
	assisted = true


func signature() -> String:
	var rows: Array[String] = []
	for track in TRACKS.size():
		var row := ""
		for step in STEPS: row += "x" if active(track, step) else "-"
		rows.append(row)
	return "/".join(rows)

func song_signature() -> String:
	var previous := current_pattern
	var signatures: Array[String] = []
	for index in patterns.size(): select_pattern(index); signatures.append(signature())
	select_pattern(previous)
	return "|".join(signatures) + "#" + ",".join(order.map(func(i: int) -> String: return str(i)))

func snapshot() -> Dictionary:
	return {"patterns": patterns.duplicate(true), "order": order.duplicate(), "samples": samples.duplicate(),
		"effects": effects.duplicate(), "current_pattern": current_pattern, "song_signature": song_signature()}

func load_snapshot(data: Dictionary) -> bool:
	var raw: Array = data.get("patterns", [])
	if raw.is_empty() or raw.size() > 4: return false
	for pattern in raw:
		if not pattern is Array or pattern.size() != TRACKS.size(): return false
	patterns = raw.duplicate(true)
	order.assign(data.get("order", [0])); samples.assign(data.get("samples", samples)); effects.assign(data.get("effects", effects))
	return select_pattern(clampi(int(data.get("current_pattern", 0)), 0, patterns.size() - 1))


func score() -> int:
	var result := evaluation()
	if not bool(result.valid): return 0
	return maxi(300, 1100 + level * 130 + int(result.syncopation) * 35 - hints * 90
		- (420 if assisted else 0) - maxi(0, edits - 18) * 3)
