class_name CracktroOptimizationModel
extends RefCounted
## Profiler-Puzzle fuer PAL-CPU, Chip-RAM, Blitter und Farb-/Qualitaetsbudget.

const CARDS := [&"precalc", &"delta_pack", &"reuse_buffers", &"dirty_rects", &"half_res", &"palette_reduce"]
const LABELS := {&"precalc": "PRECALC TABLES", &"delta_pack": "DELTA PACK", &"reuse_buffers": "BUFFER REUSE",
	&"dirty_rects": "DIRTY RECTS", &"half_res": "HALF RES", &"palette_reduce": "PALETTE REDUCE"}
const EFFECTS := {
	&"precalc": {"cpu": -25, "chip": 48, "blitter": 0, "colors": 0, "quality": 0},
	&"delta_pack": {"cpu": 8, "chip": -72, "blitter": 0, "colors": 0, "quality": -2},
	&"reuse_buffers": {"cpu": 4, "chip": -92, "blitter": 8, "colors": 0, "quality": -3},
	&"dirty_rects": {"cpu": 6, "chip": 0, "blitter": -34, "colors": 0, "quality": -2},
	&"half_res": {"cpu": -34, "chip": -46, "blitter": -20, "colors": 0, "quality": -16},
	&"palette_reduce": {"cpu": -3, "chip": -18, "blitter": -4, "colors": -16, "quality": -8},
}
var level := 1
var run_seed := 1
var base := {}
var selected: Array[StringName] = []
var budget := 4
var toggles := 0
var hints := 0
var assisted := false
var hardware_target:=&"a500_512k"

func configure(next_level: int, next_seed: int, input_metrics: Dictionary = {}) -> void:
	level = clampi(next_level, 1, 5); run_seed = next_seed
	hardware_target=[&"a500_512k",&"a500_1m",&"a1200",&"slow_chip"][posmod(run_seed+level,4)]
	base = {"cpu": maxi(int(input_metrics.get("cpu", 0)), 104 + level * 9),
		"chip": maxi(int(input_metrics.get("chip", 0)), 438 + level * 24),
		"blitter": maxi(int(input_metrics.get("blitter", 0)), 88 + level * 7),
		"colors": maxi(int(input_metrics.get("colors", 0)), 32 + (16 if level >= 3 else 0)), "quality": 100}
	budget = 3 + floori((level + 1) / 2.0); selected.clear(); toggles = 0; hints = 0; assisted = false

func toggle(card: StringName) -> bool:
	if card not in CARDS: return false
	if card in selected: selected.erase(card); toggles += 1; return true
	if selected.size() >= budget: return false
	selected.append(card); toggles += 1; return true

func metrics() -> Dictionary:
	var out := base.duplicate(true)
	for card in selected:
		for key in ["cpu", "chip", "blitter", "colors", "quality"]: out[key] = int(out[key]) + int(EFFECTS[card][key])
	return out

func valid() -> bool:
	var m := metrics(); return int(m.cpu) <= 100 and int(m.chip) <= 512 and int(m.blitter) <= 100 and int(m.colors) <= 32 and int(m.quality) >= 65

func hint() -> StringName:
	hints += 1; var m := metrics(); var candidates: Array[StringName] = []
	if int(m.chip) > 512: candidates.append_array([&"reuse_buffers", &"delta_pack", &"half_res"])
	if int(m.blitter) > 100: candidates.append_array([&"dirty_rects", &"half_res"])
	if int(m.colors) > 32: candidates.append(&"palette_reduce")
	if int(m.cpu) > 100: candidates.append_array([&"precalc", &"half_res", &"palette_reduce"])
	for wanted in candidates:
		if wanted not in selected: return wanted
	for card in CARDS:
		if card not in selected: return card
	return &"precalc"

func auto_optimize() -> void:
	assisted = true
	var guard := 0
	while not valid() and selected.size() < budget and guard < 12:
		var card := hint(); if card not in selected: toggle(card)
		guard += 1

func score() -> int:
	if not valid(): return 0
	var m := metrics(); var reserve := (100 - int(m.cpu)) + floori((512 - int(m.chip)) / 8.0) + (100 - int(m.blitter))
	return maxi(250, 1050 + level * 130 + reserve * 3 + int(m.quality) * 2 - toggles * 4 - hints * 90 - (430 if assisted else 0))

func details() -> Dictionary:
	return {"level": level, "cards": Array(selected), "metrics": metrics(), "budget": budget,"hardware_target":str(hardware_target),
		"toggles": toggles, "hints": hints, "assisted": assisted}
