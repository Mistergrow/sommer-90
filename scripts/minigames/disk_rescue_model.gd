class_name DiskRescueModel
extends RefCounted
## Zwei Diskettenseiten als deterministisches Match-3-Datenabbild.
##
## Eine gueltige Verschiebung erzeugt mindestens eine Dreierreihe. Geloeschte
## Datenbloecke werden durch redundante Sektoren ersetzt und fuellen den
## Rekonstruktionsbalken der aktuellen Seite. Erst Seite 1 = 100 %, danach
## Seite 2 = 100 % ergibt ein verifiziertes Image. Das Original wird nie
## veraendert; der UI-Commit schreibt ausschliesslich auf eine Leerdiskette.

const WIDTH := 8
const HEIGHT := 7
const TILE_KINDS := 6
const SIDE_COUNT := 2
const SIDE_TIME_SECONDS := 30.0
const TIME_GAIN_PER_CLEARED_TILE := 1.0
const BONUS_CAP_PER_SIDE := 25
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

# Legacy-Vertrag fuer alte Tests/Saves. Im neuen Live-Spiel gibt es keine
# Lesestrategie mehr; diese Adapter duerfen deshalb keine UI mehr treiben.
const METHODS := [&"normal", &"retry", &"raw"]
const METHOD_LABELS := {&"normal": "DOS READ", &"retry": "SYNC RETRY", &"raw": "RAW FLUX"}

var level := 1
var run_seed := 1
var source_condition := 45
var disk_format := &"adf"
var rpm := 300
var azimuth_error := 0.0

var boards: Array = [[], []]
var current_side := 0
var side_progress: Array[int] = [0, 0]
var side_time_limit := SIDE_TIME_SECONDS
var side_time_left: Array[float] = [SIDE_TIME_SECONDS, SIDE_TIME_SECONDS]
var side_moves: Array[int] = [0, 0]
var side_cleared: Array[int] = [0, 0]
var side_finished: Array[bool] = [false, false]
var side_bonus_dm: Array[int] = [0, 0]
var timer_enabled := true
var failed_side := -1
var retries := 0

var moves_used := 0
var mistakes := 0
var cascades := 0
var cleared_tiles := 0
var biggest_match := 0
var hints := 0
var assisted := false

# Kompatibilitaets-/Auswertungsfelder des alten Sektormodells.
var sectors: Array[Dictionary] = []
var reads := 0
var max_reads := 0
var risk := 0.0
var directory_target := 0
var directory_choice := -1

var _rng := RandomNumberGenerator.new()


func configure(next_level: int, next_seed: int, condition := 45) -> void:
	level = clampi(next_level, 1, 5)
	run_seed = next_seed
	source_condition = clampi(condition, 1, 100)
	disk_format = [&"dd", &"adf", &"ofs", &"ffs"][posmod(run_seed + level, 4)]
	rpm = 300 + posmod(run_seed, 9) - 4
	azimuth_error = (posmod(run_seed, 21) - 10) * 0.025
	# Schneller Arcade-Vertrag: 30 Sekunden Startzeit je Diskettenseite.
	# Aufgeloeste Bloecke schenken waehrend der Rekonstruktion je eine Sekunde;
	# in der anschliessenden DM-Bonusphase verlaengern sie den Lauf nicht endlos.
	side_time_limit = SIDE_TIME_SECONDS
	_rng.seed = run_seed
	boards = [[], []]
	for side in SIDE_COUNT:
		boards[side] = _generate_stable_board()
	current_side = 0
	side_progress = [0, 0]
	side_time_left = [side_time_limit, side_time_limit]
	side_moves = [0, 0]
	side_cleared = [0, 0]
	side_finished = [false, false]
	side_bonus_dm = [0, 0]
	failed_side = -1
	retries = 0
	moves_used = 0
	mistakes = 0
	cascades = 0
	cleared_tiles = 0
	biggest_match = 0
	hints = 0
	assisted = false
	risk = 0.0
	reads = 0
	directory_choice = -1
	directory_target = posmod(run_seed + level, 4)
	_build_legacy_sectors()


func _generate_stable_board() -> Array[int]:
	for _attempt in 100:
		var candidate: Array[int] = []
		for index in WIDTH * HEIGHT:
			var kinds: Array[int] = []
			for kind in TILE_KINDS:
				if index % WIDTH >= 2 and candidate[index - 1] == kind and candidate[index - 2] == kind:
					continue
				if index >= WIDTH * 2 and candidate[index - WIDTH] == kind and candidate[index - WIDTH * 2] == kind:
					continue
				kinds.append(kind)
			candidate.append(kinds[_rng.randi_range(0, kinds.size() - 1)])
		if not _possible_moves_for(candidate).is_empty():
			return candidate
	# Sicherheitsmuster mit garantiertem Zug im Zentrum.
	var fallback: Array[int] = []
	for y in HEIGHT:
		for x in WIDTH:
			fallback.append(posmod(x * 2 + y * 3, TILE_KINDS))
	fallback[_index(Vector2i(2, 3))] = 1
	fallback[_index(Vector2i(3, 3))] = 0
	fallback[_index(Vector2i(4, 3))] = 1
	fallback[_index(Vector2i(3, 2))] = 1
	return fallback


func tile_at(cell: Vector2i, side := -1) -> int:
	var use_side := current_side if side < 0 else clampi(side, 0, SIDE_COUNT - 1)
	var board: Array = boards[use_side]
	return int(board[_index(cell)]) if valid_cell(cell) else -1


func valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT


func adjacent(a: Vector2i, b: Vector2i) -> bool:
	return valid_cell(a) and valid_cell(b) and absi(a.x - b.x) + absi(a.y - b.y) == 1


func swap_cells(a: Vector2i, b: Vector2i) -> Dictionary:
	if complete():
		return {"ok": false, "reason": Loc.t("game.disk_rescue_model.diskettenimage_ist_bereits_verifiziert", "Das Diskettenimage ist bereits verifiziert.")}
	if failed():
		return {"ok": false, "reason": Loc.t("game.disk_rescue_model.seitentimer_ist_abgelaufen_seite_neu_starten", "Der Seitentimer ist abgelaufen. Seite neu starten.")}
	if side_finished[current_side]:
		return {"ok": false, "reason": Loc.t("game.disk_rescue_model.diese_diskettenseite_ist_bereits_abgeschlossen", "Diese Diskettenseite ist bereits abgeschlossen.")}
	if not adjacent(a, b):
		return {"ok": false, "reason": Loc.t("game.disk_rescue_model.nur_direkt_benachbarte_datenbloecke_koennen_getauscht", "Nur direkt benachbarte Datenbloecke koennen getauscht werden.")}

	var was_complete := side_progress[current_side] >= 100
	var board: Array = boards[current_side]
	var before: Array = board.duplicate()
	_swap_indices(board, _index(a), _index(b))
	var matched := _find_matches_for(board)
	if matched.is_empty():
		boards[current_side] = before
		mistakes += 1
		return {"ok": false, "reason": Loc.t("game.disk_rescue_model.keine_dreierreihe_tausch_wurde_zurueckgenommen", "Keine Dreierreihe. Tausch wurde zurueckgenommen.")}

	moves_used += 1
	side_moves[current_side] += 1
	var chain := 0
	var total_gain := 0
	var total_cleared := 0
	var waves: Array[Dictionary] = []
	while not matched.is_empty() and chain < 14:
		chain += 1
		cascades += 1
		var longest := _longest_run(board)
		biggest_match = maxi(biggest_match, longest)
		var gain := 0 if was_complete else _progress_gain(matched.size(), longest, chain)
		total_gain += gain
		total_cleared += matched.size()
		waves.append({
			"cells": matched.duplicate(), "chain": chain, "longest": longest,
			"gain": gain, "special": _special_for(longest, chain),
		})
		_collapse_and_refill(board, matched)
		matched = _find_matches_for(board)
	boards[current_side] = board
	cleared_tiles += total_cleared
	side_cleared[current_side] += total_cleared
	side_progress[current_side] = mini(100, side_progress[current_side] + total_gain)
	var time_award := 0.0
	if timer_enabled and not was_complete:
		time_award = total_cleared * TIME_GAIN_PER_CLEARED_TILE
		side_time_left[current_side] += time_award
	var bonus_award := 0
	if was_complete:
		bonus_award = mini(BONUS_CAP_PER_SIDE - side_bonus_dm[current_side],
			clampi(1 + maxi(0, chain - 1) + maxi(0, biggest_match - 3), 1, 4))
		bonus_award = maxi(0, bonus_award)
		side_bonus_dm[current_side] += bonus_award
	if possible_moves().is_empty():
		_reshuffle_current()
	return {
		"ok": true, "chain": chain, "cleared": total_cleared,
		"time_gain": time_award,
		"gain": total_gain, "progress": side_progress[current_side],
		"side": current_side, "side_complete": side_progress[current_side] >= 100,
		"entered_bonus": not was_complete and side_progress[current_side] >= 100,
		"bonus_dm": bonus_award, "bonus_total": side_bonus_dm[current_side],
		"disk_complete": complete(), "waves": waves,
		"matched_cells": (waves[0].cells as Array).duplicate() if not waves.is_empty() else [],
		"special": str(waves[-1].special) if not waves.is_empty() else "",
	}


func _progress_gain(matched_count: int, longest: int, chain: int) -> int:
	# Eine reine Dreierreihe bringt zehn Prozent. Gute Planung und Kaskaden
	# verkuerzen den Lauf sichtbar, ohne dass Glueck fuer den Abschluss noetig ist.
	var gain := 4 + matched_count * 2
	gain += maxi(0, longest - 3) * 5
	gain += maxi(0, chain - 1) * 4
	return gain


func _special_for(longest: int, chain: int) -> String:
	if longest >= 5:
		return "COPPER BURST"
	if longest >= 4:
		return "BLITTER LINE"
	if chain >= 2:
		return "RASTER CASCADE"
	return "SECTOR LINK"


func _collapse_and_refill(board: Array, matched: Array[int]) -> void:
	var removed := {}
	for index: int in matched:
		removed[index] = true
	for x in WIDTH:
		var survivors: Array[int] = []
		for y in range(HEIGHT - 1, -1, -1):
			var index := _index(Vector2i(x, y))
			if not removed.has(index):
				survivors.append(int(board[index]))
		var cursor := 0
		for y in range(HEIGHT - 1, -1, -1):
			var index := _index(Vector2i(x, y))
			if cursor < survivors.size():
				board[index] = survivors[cursor]
				cursor += 1
			else:
				board[index] = _rng.randi_range(0, TILE_KINDS - 1)


func _find_matches() -> Array[int]:
	return _find_matches_for(boards[current_side])


func _find_matches_for(board: Array) -> Array[int]:
	var found := {}
	for y in HEIGHT:
		var start := 0
		while start < WIDTH:
			var finish := start + 1
			while finish < WIDTH and int(board[_index(Vector2i(finish, y))]) == int(board[_index(Vector2i(start, y))]):
				finish += 1
			if finish - start >= 3:
				for x in range(start, finish):
					found[_index(Vector2i(x, y))] = true
			start = finish
	for x in WIDTH:
		var start := 0
		while start < HEIGHT:
			var finish := start + 1
			while finish < HEIGHT and int(board[_index(Vector2i(x, finish))]) == int(board[_index(Vector2i(x, start))]):
				finish += 1
			if finish - start >= 3:
				for y in range(start, finish):
					found[_index(Vector2i(x, y))] = true
			start = finish
	var result: Array[int] = []
	for raw_index: Variant in found:
		result.append(int(raw_index))
	return result


func _longest_run(board: Array) -> int:
	var longest := 0
	for y in HEIGHT:
		var run := 1
		for x in range(1, WIDTH):
			if int(board[_index(Vector2i(x, y))]) == int(board[_index(Vector2i(x - 1, y))]):
				run += 1
			else:
				longest = maxi(longest, run)
				run = 1
		longest = maxi(longest, run)
	for x in WIDTH:
		var run := 1
		for y in range(1, HEIGHT):
			if int(board[_index(Vector2i(x, y))]) == int(board[_index(Vector2i(x, y - 1))]):
				run += 1
			else:
				longest = maxi(longest, run)
				run = 1
		longest = maxi(longest, run)
	return longest


func possible_moves() -> Array[Vector4i]:
	return _possible_moves_for(boards[current_side])


func _possible_moves_for(board: Array) -> Array[Vector4i]:
	var result: Array[Vector4i] = []
	for y in HEIGHT:
		for x in WIDTH:
			var a := Vector2i(x, y)
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var b := a + offset
				if not valid_cell(b):
					continue
				_swap_indices(board, _index(a), _index(b))
				var creates := not _find_matches_for(board).is_empty()
				_swap_indices(board, _index(a), _index(b))
				if creates:
					result.append(Vector4i(a.x, a.y, b.x, b.y))
	return result


func hint() -> Vector4i:
	hints += 1
	var moves := possible_moves()
	return moves[0] if not moves.is_empty() else Vector4i(-1, -1, -1, -1)


func _reshuffle_current() -> void:
	var values: Array = (boards[current_side] as Array).duplicate()
	for _attempt in 60:
		_shuffle(values)
		if _find_matches_for(values).is_empty() and not _possible_moves_for(values).is_empty():
			boards[current_side] = values.duplicate()
			return
	boards[current_side] = _generate_stable_board()


func tick_time(delta: float) -> bool:
	if not timer_enabled or complete() or failed() or side_finished[current_side]:
		return false
	side_time_left[current_side] = maxf(0.0, side_time_left[current_side] - maxf(0.0, delta))
	if side_time_left[current_side] <= 0.0:
		if side_progress[current_side] >= 100:
			side_finished[current_side] = true
		else:
			failed_side = current_side
		# Der Rueckgabewert bezeichnet einen aufgeloesten Timerzustand — Erfolg
		# wie Fehlschlag. Die UI nutzt ihn, um Seite zwei bzw. den Retry-Dialog
		# exakt einmal einzuleiten.
		return true
	return false


func restart_side() -> void:
	if failed_side != current_side:
		return
	retries += 1
	_rng.seed = run_seed + current_side * 7919 + retries * 104729
	boards[current_side] = _generate_stable_board()
	side_progress[current_side] = 0
	side_cleared[current_side] = 0
	side_moves[current_side] = 0
	side_time_left[current_side] = side_time_limit
	side_finished[current_side] = false
	side_bonus_dm[current_side] = 0
	failed_side = -1


func advance_side() -> bool:
	if current_side == 0 and side_finished[0]:
		current_side = 1
		return true
	return false


func finish_side_without_timer() -> void:
	if side_progress[current_side] >= 100:
		side_finished[current_side] = true


func side_complete(side := -1) -> bool:
	var use_side := current_side if side < 0 else clampi(side, 0, SIDE_COUNT - 1)
	return side_progress[use_side] >= 100


func disk_progress() -> int:
	return floori((side_progress[0] + side_progress[1]) * 0.5)


func failed() -> bool:
	return failed_side >= 0 or risk >= 100.0


func complete() -> bool:
	return side_finished[0] and side_finished[1] and not failed()


func bonus_total_dm() -> int:
	return side_bonus_dm[0] + side_bonus_dm[1]


func quality() -> int:
	var time_bonus := 0.0
	if complete():
		time_bonus = (side_time_left[0] + side_time_left[1]) / maxf(1.0, side_time_limit * 2.0) * 8.0
	return clampi(roundi(94.0 + time_bonus - mistakes * 2.0 - retries * 3.0 - hints * 0.5 - risk * 0.25), 55, 100)


func score() -> int:
	if not complete():
		return 0
	return maxi(300, 900 + level * 150 + cleared_tiles * 5 + cascades * 22
		+ biggest_match * 60 + roundi(side_time_left[0] + side_time_left[1]) * 4
		+ bonus_total_dm() * 20 - mistakes * 70 - retries * 180 - hints * 35 - (450 if assisted else 0))


func details() -> Dictionary:
	return {
		"level": level, "format": str(disk_format), "rpm": rpm,
		"azimuth_error": azimuth_error, "side_progress": side_progress.duplicate(),
		"side_moves": side_moves.duplicate(), "side_cleared": side_cleared.duplicate(),
		"side_finished": side_finished.duplicate(), "bonus_dm": side_bonus_dm.duplicate(),
		"time_left": side_time_left.duplicate(), "moves": moves_used,
		"mistakes": mistakes, "cascades": cascades, "biggest_match": biggest_match,
		"cleared": cleared_tiles, "quality": quality(), "hints": hints,
		"retries": retries, "assisted": assisted,
	}


func auto_finish() -> void:
	# Test-/Barrierefreiheitsadapter: erzeugt denselben gueltigen Abschlusszustand,
	# aber markiert die Session fuer die niedrigere Assistenzwertung.
	assisted = true
	side_progress = [100, 100]
	side_finished = [true, true]
	current_side = 1
	failed_side = -1
	for index in sectors.size():
		sectors[index].recovered = true
	reads = sectors.size()
	directory_choice = directory_target
	cleared_tiles = maxi(cleared_tiles, 42)


# ---------------------------------------------------------------------------
# Alte Sektor-API: nur fuer bestehende Tests/Saves; nicht mehr Teil der UI.

func _build_legacy_sectors() -> void:
	sectors.clear()
	var count := 12 + level * 3
	for index in count:
		var severity := posmod(run_seed + index * 7, 3)
		sectors.append({"id": index, "severity": severity, "method": METHODS[severity],
			"recovered": false, "attempts": 0})
	max_reads = count + 7 + level


func read_sector(index: int, method: StringName) -> Dictionary:
	if failed() or complete() or index < 0 or index >= sectors.size():
		return {"ok": false, "text": Loc.t("game.disk_rescue_model.kein_gueltiger_legacy_leseauftrag", "Kein gueltiger Legacy-Leseauftrag.")}
	var sector := sectors[index]
	if bool(sector.recovered):
		return {"ok": false, "text": Loc.t("game.disk_rescue_model.sektor_ist_bereits_im_image", "Sektor ist bereits im Image.")}
	reads += 1
	sector.attempts = int(sector.attempts) + 1
	var correct := method == StringName(sector.method)
	if correct:
		sector.recovered = true
	else:
		mistakes += 1
		risk += [4.0, 7.0, 12.0][int(sector.severity)] + (5.0 if method == &"raw" else 0.0)
	sectors[index] = sector
	return {"ok": correct, "text": Loc.t("game.disk_rescue_model.legacy_sector_read", "Legacy-Sektor gelesen.") if correct
		else Loc.t("game.disk_rescue_model.legacy_sync_lost", "Legacy-Sync verloren."), "risk": risk}


func repair_directory(choice: int) -> bool:
	directory_choice = clampi(choice, 0, 3)
	return directory_choice == directory_target


func image_complete() -> bool:
	return side_progress[0] >= 100 and side_progress[1] >= 100


func recovered_count() -> int:
	return mini(sectors.size(), roundi(float(disk_progress()) / 100.0 * sectors.size()))


func _index(cell: Vector2i) -> int:
	return cell.y * WIDTH + cell.x


func _swap_indices(board: Array, a: int, b: int) -> void:
	var value: Variant = board[a]
	board[a] = board[b]
	board[b] = value


func _shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[other]
		values[other] = value
