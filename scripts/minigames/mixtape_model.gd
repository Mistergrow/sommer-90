class_name MixtapeModel
extends RefCounted
## A/B-Seiten, Laufzeit, Reihenfolge und Pegel einer echten Trackauswahl.

var level := 1
var run_seed := 1
var library: Array[Dictionary] = []
var entries: Array[Dictionary] = []
var side_capacity := 900
var min_tracks := 4
var edits := 0
var hints := 0
var assisted := false
var tape_type := "C60 TYPE I"

func configure(next_level: int, next_seed: int, tracks: Array) -> void:
	level = clampi(next_level, 1, 5); run_seed = next_seed
	tape_type = ["C46 TYPE I","C60 TYPE I","C60 CHROME","C90 CHROME"][mini(3, floori((level - 1) / 1.5))]
	library.clear(); entries.clear()
	for raw in tracks:
		if raw is Dictionary:
			var t: Dictionary = raw
			library.append({"id": str(t.get("id", "track_%d" % library.size())), "title": str(t.get("title", "TRACK")),
				"author": str(t.get("author", "?")), "stars": clampi(int(t.get("stars", 2)), 1, 5),
				"duration": 150 + absi(hash(str(t.get("id", "")))) % 121})
	min_tracks = mini(library.size(), 4 + floori((level - 1) / 2.0))
	side_capacity = 720 + level * 60
	edits = 0; hints = 0; assisted = false

func add_track(id: String) -> bool:
	if entries.any(func(e: Dictionary) -> bool: return str(e.id) == id): return false
	for t: Dictionary in library:
		if str(t.id) == id:
			var e := t.duplicate(true); e["side"] = "A" if side_duration("A") <= side_duration("B") else "B"; e["gain"] = 0.65
			e["cue"] = 0.0; e["fade_in"] = 0.8; e["fade_out"] = 1.2
			entries.append(e); edits += 1; return true
	return false

func remove_at(index: int) -> bool:
	if index < 0 or index >= entries.size(): return false
	entries.remove_at(index); edits += 1; return true

func move(index: int, delta: int) -> bool:
	var target := index + delta
	if index < 0 or index >= entries.size() or target < 0 or target >= entries.size(): return false
	var e := entries[index]; entries.remove_at(index); entries.insert(target, e); edits += 1; return true

func toggle_side(index: int) -> bool:
	if index < 0 or index >= entries.size(): return false
	entries[index].side = "B" if str(entries[index].side) == "A" else "A"; edits += 1; return true

func set_gain(index: int, value: float) -> void:
	if index >= 0 and index < entries.size(): entries[index].gain = clampf(value, 0.0, 1.0); edits += 1

func set_cue(index: int, seconds: float) -> float:
	if index < 0 or index >= entries.size(): return 0.0
	# Simuliertes Zero-Crossing: 50-Hz-PAL-Raster verhindert harte Klicks.
	var snapped_sec := snappedf(clampf(seconds, 0.0, 12.0), 0.02)
	entries[index].cue = snapped_sec; edits += 1; return snapped_sec

func set_fade(index: int, fade_in: float, fade_out: float) -> void:
	if index < 0 or index >= entries.size(): return
	entries[index].fade_in = snappedf(clampf(fade_in, 0.0, 6.0), 0.1)
	entries[index].fade_out = snappedf(clampf(fade_out, 0.0, 6.0), 0.1); edits += 1

func waveform(index: int, samples := 64) -> PackedFloat32Array:
	var result := PackedFloat32Array(); result.resize(samples)
	if index < 0 or index >= entries.size(): return result
	var base := absi(hash(str(entries[index].id)))
	for i in samples:
		var phase := TAU * float(i) / maxf(1.0, samples - 1.0)
		result[i] = clampf(sin(phase * (2 + base % 5)) * .55 + sin(phase * (5 + base % 7)) * .25, -.95, .95)
	return result

func side_duration(side: String) -> int:
	var total := 0
	for e: Dictionary in entries:
		if str(e.side) == side: total += int(e.duration)
	return total

func evaluation() -> Dictionary:
	var a := side_duration("A"); var b := side_duration("B")
	var overload := maxi(0, a - side_capacity) + maxi(0, b - side_capacity)
	var balance: float = abs(a - b) / maxf(1.0, float(maxi(a, b)))
	var clipping := entries.filter(func(e: Dictionary) -> bool: return float(e.gain) > 0.84).size()
	var quiet := entries.filter(func(e: Dictionary) -> bool: return float(e.gain) < 0.42).size()
	var flow_penalty := 0
	for side in ["A", "B"]:
		var prev := -1
		for e: Dictionary in entries:
			if str(e.side) != side: continue
			if prev >= 0: flow_penalty += maxi(0, abs(int(e.stars) - prev) - 2)
			prev = int(e.stars)
	var valid: bool = entries.size() >= min_tracks and a > 0 and b > 0 and overload == 0 and balance <= 0.24 and clipping == 0 and quiet == 0
	return {"valid": valid, "a": a, "b": b, "overload": overload, "balance": balance,
		"clipping": clipping, "quiet": quiet, "flow_penalty": flow_penalty}

func hint() -> String:
	hints += 1; var ev := evaluation()
	if entries.size() < min_tracks:
		for t: Dictionary in library:
			if not entries.any(func(e: Dictionary) -> bool: return e.id == t.id): return "Track ergaenzen: %s" % t.title
	if int(ev.overload) > 0: return "Die vollere Seite kuerzen oder umverteilen."
	if float(ev.balance) > 0.24: return "Die Laufzeiten von A und B naeher angleichen."
	if int(ev.clipping) > 0 or int(ev.quiet) > 0: return "Pegel aller Tracks in den sicheren Bereich 42–84% bringen."
	return "Energiespruenge zwischen benachbarten Tracks klein halten."

func auto_curate() -> void:
	assisted = true; entries.clear()
	var auto_count := mini(library.size(), min_tracks + (min_tracks % 2))
	for i in auto_count:
		var e := library[i].duplicate(true); e.side = "A" if i % 2 == 0 else "B"; e.gain = 0.65; e.cue=0.0;e.fade_in=.8;e.fade_out=1.2;entries.append(e)
	# Kleine exakte Partition statt Greedy: die Assistenz darf keinen zufaellig
	# unloesbaren A/B-Schnitt erzeugen. Maximal sechs Tracks => hoechstens 64 Masken.
	var best_mask := 1; var best_diff := 1_000_000
	for mask in range(1, (1 << entries.size()) - 1):
		var a := 0; var b := 0
		for i in entries.size():
			if mask & (1 << i): a += int(entries[i].duration)
			else: b += int(entries[i].duration)
		if a <= side_capacity and b <= side_capacity and abs(a - b) < best_diff:
			best_diff = abs(a - b); best_mask = mask
	for i in entries.size(): entries[i].side = "A" if best_mask & (1 << i) else "B"

func complete() -> bool: return bool(evaluation().valid)

func score() -> int:
	if not complete(): return 0
	var ev := evaluation()
	return maxi(250, roundi(1200 + level * 100 - float(ev.balance) * 700 - int(ev.flow_penalty) * 45 - edits * 2 - hints * 90 - (420 if assisted else 0)))

func details() -> Dictionary:
	var ev := evaluation(); return {"level": level, "tracks": entries.size(), "side_a": ev.a, "side_b": ev.b,
		"balance": ev.balance, "flow_penalty": ev.flow_penalty, "hints": hints, "assisted": assisted, "tape_type":tape_type}
