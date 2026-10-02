class_name HardwareAssemblyModel
extends RefCounted
## Sichere Werkstatt-Reihenfolge. Falsche Aktionen sind nachvollziehbare
## Verfahrensfehler; kein Zufall entscheidet ueber Erfolg oder Schaden.

const ACTION_LABELS := {
	&"power_off": "NETZ TRENNEN", &"ground": "ESD-BAND ANLEGEN",
	&"open_case": "GEHAEUSE OEFFNEN", &"inspect": "SOCKEL PRUEFEN",
	&"diagnose": "MESSPUNKTE PRUEFEN",
	&"ram": "RAM EINSETZEN", &"drive": "LAUFWERK EINSETZEN",
	&"secure": "BEFESTIGEN", &"visual": "SICHTPRUEFUNG",
	&"power_test": "STROMTEST",
}
const ACTION_CODES := {
	&"power_off": "PWR", &"ground": "ESD", &"open_case": "CASE",
	&"inspect": "SOCKET", &"diagnose": "METER", &"ram": "RAM",
	&"drive": "FDD", &"secure": "LOCK", &"visual": "CHECK",
	&"power_test": "TEST",
}
const ACTION_GUIDANCE := {
	&"power_off": "Netzstecker links aus der Arbeitszone nehmen. Erst dann ist das Gehaeuse sicher.",
	&"ground": "Blaues ESD-Band rechts anlegen und Potentialausgleich herstellen.",
	&"open_case": "Gehaeuseschrauben loesen, Oberteil ohne Zug auf Flachbandkabel abheben.",
	&"inspect": "Sockel, Pins und Stecker auf verbogene Kontakte oder falsche Orientierung pruefen.",
	&"diagnose": "Versorgung und Masse an den markierten Messpunkten stromlos gegenpruefen.",
	&"ram": "Speicherkarte nur an den Kanten halten, Kerbe ausrichten und gleichmaessig einsetzen.",
	&"drive": "Laufwerk gerade einsetzen; Daten- und Stromstecker nicht versetzen oder verkanten.",
	&"secure": "Halter und Schrauben handfest ueber Kreuz anziehen. Keine Gewalt.",
	&"visual": "Kabelweg, Pinlage, Werkzeug und lose Schrauben vor dem Einschalten kontrollieren.",
	&"power_test": "Abdeckung frei, Haende weg: Netz anlegen und Funktionstest beobachten.",
}
const PLATFORMS := [&"amiga_500", &"amiga_600", &"amiga_1200", &"external_drive"]
const PLATFORM_LABELS := {&"amiga_500":"AMIGA 500 REV.6A", &"amiga_600":"AMIGA 600 REV.1.5",
	&"amiga_1200":"AMIGA 1200 REV.1D", &"external_drive":"A1011 EXTERN"}
const PLATFORM_BRIEFS := {
	&"amiga_500": "A501-SPEICHER / INTERNES DD-LAUFWERK",
	&"external_drive": "DD-MECHANIK / KABEL / CONTROLLER",
	&"amiga_600": "A601-CHIP-RAM / INTERNES DD-LAUFWERK",
	&"amiga_1200": "FAST-RAM / IDE / INTERNES DD-LAUFWERK",
}

var level := 1
var run_seed := 1
var configured_year := 1990
var sequence: Array[StringName] = []
var cursor := 0
var mistakes := 0
var esd_charge := 0.15
var damage := 0
var hints := 0
var assisted := false
var platform: StringName = &"amiga_500"


func configure(next_level: int, next_seed: int, next_year := 1990,
		forced_platform: StringName = &"") -> void:
	level = clampi(next_level, 1, 4)
	run_seed = next_seed
	configured_year = clampi(next_year, 1990, 1999)
	platform = forced_platform if forced_platform in PLATFORMS \
		else platform_for_year(configured_year)
	sequence = [&"power_off", &"ground", &"open_case", &"inspect"]
	if level >= 4:
		sequence.append(&"diagnose")
	if platform == &"external_drive":
		# Ein A1011 besitzt keinen RAM-Steckplatz. Der alte Zufallsgenerator
		# verlangte hier trotzdem "RAM einsetzen" und war fachlich unloesbar.
		sequence.append(&"drive")
	elif level == 1:
		sequence.append(&"ram")
	elif level == 2:
		sequence.append(&"drive")
	else:
		sequence.append_array([&"ram", &"drive"] if run_seed % 2 == 0 else [&"drive", &"ram"])
	sequence.append_array([&"secure", &"visual", &"power_test"])
	cursor = 0
	mistakes = 0
	esd_charge = 0.15 + level * 0.05
	damage = 0
	hints = 0
	assisted = false


static func platform_for_year(year: int) -> StringName:
	if year <= 1990:
		return &"amiga_500"
	if year == 1991:
		return &"external_drive"
	if year <= 1993:
		return &"amiga_600"
	return &"amiga_1200"


func expected() -> StringName:
	return sequence[cursor] if cursor < sequence.size() else &""


func completed_action(action: StringName) -> bool:
	var index := sequence.find(action)
	return index >= 0 and index < cursor


func action_in_job(action: StringName) -> bool:
	return action in sequence


func guidance(action: StringName = &"") -> String:
	var selected := expected() if action.is_empty() else action
	return str(ACTION_GUIDANCE.get(selected, "Arbeitskarte pruefen."))


func platform_brief() -> String:
	return str(PLATFORM_BRIEFS.get(platform, "SERVICE / FUNKTIONSPRUEFUNG"))


func perform(action: StringName) -> Dictionary:
	if complete() or failed():
		return {"ok": false, "text": Loc.t("game.hardware_assembly_model.durchgang_ist_bereits_beendet", "Der Durchgang ist bereits beendet.")}
	if action == expected():
		cursor += 1
		if action == &"ground": esd_charge = 0.0
		if action in [&"ram", &"drive"]: esd_charge = minf(1.0, esd_charge + 0.04)
		return {"ok": true, "text": "%s — sauber ausgefuehrt." % ACTION_LABELS[action],
			"complete": complete()}
	mistakes += 1
	if not action_in_job(action):
		return {"ok": false, "text": Loc.t("game.hardware_assembly_model.s_ist_bei_diesem_auftrag_nicht", "%s ist bei diesem Auftrag nicht vorgesehen.") %
			ACTION_LABELS.get(action, str(action)), "damage": damage}
	var dangerous := action in [&"ram", &"drive", &"power_test"]
	var grounded := cursor > sequence.find(&"ground")
	if dangerous and (not grounded or expected() in [&"power_off", &"ground", &"open_case"]):
		damage += 1
		esd_charge = minf(1.0, esd_charge + 0.25)
	return {"ok": false, "text": _error_text(action), "damage": damage}


func _error_text(action: StringName) -> String:
	if action in [&"ram", &"drive"] and expected() == &"power_off":
		return "STOP: Unter Spannung wird kein Bauteil beruehrt."
	if action in [&"ram", &"drive"] and expected() == &"ground":
		return "ESD-RISIKO: Erst Potentialausgleich herstellen."
	if action == &"power_test" and expected() != &"power_test":
		return "Stromtest gesperrt: Montage und Sichtpruefung fehlen."
	return "Falsche Reihenfolge — erwartet wird %s." % ACTION_LABELS[expected()]


func hint() -> StringName:
	hints += 1
	return expected()


func auto_finish() -> void:
	assisted = true
	while not complete() and not failed(): perform(expected())


func complete() -> bool:
	return cursor >= sequence.size() and damage < 2


func failed() -> bool:
	return damage >= 2


func progress() -> float:
	return float(cursor) / maxf(1.0, float(sequence.size()))


func score() -> int:
	if not complete(): return 0
	return maxi(250, 1250 + level * 140 - mistakes * 90 - hints * 110 - (450 if assisted else 0))


func details() -> Dictionary:
	return {"level": level, "mistakes": mistakes, "damage": damage,
		"hints": hints, "assisted": assisted, "steps": sequence.size(),
		"platform": str(platform), "year": configured_year, "brief": platform_brief()}
