class_name ShopDiagnosisModel
extends RefCounted
## Hypothesenbasierte Laden-Diagnose statt Teile-Raten.
##
## Messwerte werden als kanonische Resultate gespeichert. Die UI darf daraus
## Kandidaten ausschliessen, ohne den geheimen Fehler direkt offenzulegen.

const FAULTS := [&"power", &"cable", &"ram", &"drive", &"monitor", &"user"]
const FAULT_LABELS := {
	&"power": "NETZTEIL",
	&"cable": "SIGNALKABEL",
	&"ram": "RAM/KONTAKT",
	&"drive": "LAUFWERK",
	&"monitor": "MONITOR",
	&"user": "BEDIENFEHLER",
}
const TESTS := [&"visual", &"voltage", &"signal", &"memory", &"disk", &"known_good"]
const TEST_LABELS := {
	&"visual": "SICHTPRUEFUNG",
	&"voltage": "SPANNUNG MESSEN",
	&"signal": "SIGNALWEG PRUEFEN",
	&"memory": "RAM-TEST",
	&"disk": "LAUFWERK-TEST",
	&"known_good": "BEKANNT-GUT-TAUSCH",
}
const RELEVANT := {
	&"power": [&"visual", &"voltage"],
	&"cable": [&"visual", &"signal"],
	&"ram": [&"memory", &"known_good"],
	&"drive": [&"disk", &"known_good"],
	&"monitor": [&"signal", &"known_good"],
	&"user": [&"visual", &"disk"],
}
const PLATFORM_LABELS := {
	&"amiga_500": "AMIGA 500 REV.6A",
	&"amiga_600": "AMIGA 600 REV.1.5",
	&"amiga_1200": "AMIGA 1200 REV.1D",
}

var level := 1
var run_seed := 1
var configured_year := 1996
var platform: StringName = &"amiga_1200"
var case_number := 1
var fault: StringName = &"power"
var tested: Array[StringName] = []
var diagnoses: Array[StringName] = []
var max_diagnoses := 2
var hints := 0
var assisted := false
var solved := false
var distractor: StringName = &""
var readings: Dictionary = {}
var result_states: Dictionary = {}


func configure(next_level: int, next_seed: int, next_year := 1996) -> void:
	level = clampi(next_level, 1, 5)
	run_seed = next_seed
	configured_year = clampi(next_year, 1990, 1999)
	platform = platform_for_year(configured_year)
	case_number = 100 + posmod(run_seed, 900)
	fault = FAULTS[absi(run_seed) % mini(FAULTS.size(), 2 + level)]
	tested.clear()
	diagnoses.clear()
	readings.clear()
	result_states.clear()
	max_diagnoses = 3 if level <= 2 else 2
	hints = 0
	assisted = false
	solved = false
	var irrelevant := TESTS.filter(
		func(test: StringName) -> bool: return test not in RELEVANT[fault])
	distractor = irrelevant[posmod(run_seed, irrelevant.size())] if level >= 3 else &""


static func platform_for_year(year: int) -> StringName:
	if year <= 1991:
		return &"amiga_500"
	if year <= 1993:
		return &"amiga_600"
	return &"amiga_1200"


func device_label() -> String:
	return str(PLATFORM_LABELS.get(platform, "AMIGA SERVICEGERAET"))


func symptom() -> String:
	match fault:
		&"power":
			return "Tot nach Transport; Power-LED bleibt dunkel."
		&"cable":
			return "Rechner laeuft, Bildschirm meldet kein Signal."
		&"ram":
			return "Startet sporadisch, bunte Guru-Bloecke nach Minuten."
		&"drive":
			return "Kickstart erscheint, jede Diskette klickt und bricht ab."
		&"monitor":
			return "Ton ist da, Bild bleibt dunkel und schmal."
		_:
			return "Seit der neuen Diskette startet nichts mehr."


func run_test(test: StringName) -> Dictionary:
	if test not in TESTS or solved:
		return {"ok": false, "text": Loc.t(
			"game.shop_diagnosis_model.test_nicht_verfuegbar",
			"Test nicht verfuegbar.")}
	if test in tested:
		return {"ok": false, "text": "Test bereits dokumentiert."}
	tested.append(test)
	var relevant: bool = test in RELEVANT[fault]
	var ambiguous := test == distractor
	var state := &"positive" if relevant else (&"ambiguous" if ambiguous else &"reference")
	result_states[test] = state
	var text := "Messwert innerhalb Referenz — Fehlerpfad ausgeschlossen."
	if relevant:
		text = "ABWEICHUNG: Messwert bestaetigt einen relevanten Fehlerpfad."
	elif ambiguous:
		text = "GRENZWERTIG: Messwert schwankt, Gegenprobe erforderlich."
	var value := _reading_for(test, relevant, ambiguous)
	readings[test] = value
	return {
		"ok": true,
		"positive": relevant,
		"ambiguous": ambiguous,
		"value": value,
		"text": "%s  [%s]" % [text, value],
		"remaining": remaining_hypotheses(),
	}


func _reading_for(test: StringName, relevant: bool, ambiguous: bool) -> String:
	match test:
		&"voltage":
			return "4.42 V" if relevant else ("4.83 V" if ambiguous else "5.02 V")
		&"signal":
			return "0.18 Vpp" if relevant else ("0.74 Vpp" if ambiguous else "1.00 Vpp")
		&"memory":
			return "BIT %02X FAIL" % posmod(run_seed, 16) \
				if relevant else ("1 RETRY" if ambiguous else "PASS 64K")
		&"disk":
			return "18 RETRIES" if relevant else ("3 RETRIES" if ambiguous else "0 RETRIES")
		&"known_good":
			return "FEHLER WANDERT" if relevant \
				else ("INSTABIL" if ambiguous else "UNVERAENDERT")
		_:
			return "KORROSION" if relevant else ("STAUBSPUR" if ambiguous else "SAUBER")


func evidence_required() -> int:
	return 1 if level <= 2 else 2


func evidence_count() -> int:
	var count := 0
	for test: StringName in tested:
		if test in RELEVANT[fault]:
			count += 1
	return count


func enough_evidence() -> bool:
	return evidence_count() >= evidence_required()


func remaining_hypotheses() -> Array[StringName]:
	var remaining: Array[StringName] = []
	for candidate: StringName in FAULTS:
		var compatible := true
		for test: StringName in tested:
			var state := StringName(result_states.get(test, &""))
			if state == &"ambiguous":
				continue
			var expected_positive: bool = test in RELEVANT[candidate]
			var measured_positive: bool = state == &"positive"
			if expected_positive != measured_positive:
				compatible = false
				break
		if compatible:
			remaining.append(candidate)
	return remaining


func candidate_state(candidate: StringName) -> StringName:
	if candidate in diagnoses and not solved:
		return &"rejected"
	if tested.is_empty():
		return &"open"
	return &"plausible" if candidate in remaining_hypotheses() else &"excluded"


func diagnose(candidate: StringName) -> bool:
	if candidate not in FAULTS or solved or diagnoses.size() >= max_diagnoses:
		return false
	diagnoses.append(candidate)
	if candidate == fault and enough_evidence():
		solved = true
		return true
	return false


func failed() -> bool:
	return not solved and diagnoses.size() >= max_diagnoses


func hint() -> StringName:
	hints += 1
	for test: StringName in RELEVANT[fault]:
		if test not in tested:
			return test
	return &""


func auto_solve() -> void:
	assisted = true
	for test: StringName in RELEVANT[fault]:
		if test not in tested:
			run_test(test)
	diagnose(fault)


func score() -> int:
	if not solved:
		return 0
	return maxi(250,
		1050 + level * 120 + evidence_count() * 90
		- tested.size() * 25 - (diagnoses.size() - 1) * 180
		- hints * 90 - (420 if assisted else 0))


func details() -> Dictionary:
	return {
		"level": level,
		"fault": str(fault),
		"tests": Array(tested),
		"diagnoses": Array(diagnoses),
		"hints": hints,
		"assisted": assisted,
		"readings": readings.duplicate(true),
		"result_states": result_states.duplicate(true),
		"distractor": str(distractor),
		"platform": str(platform),
		"year": configured_year,
		"case_number": case_number,
	}
