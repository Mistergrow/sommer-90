class_name JobShiftModel
extends RefCounted
## Gemeinsamer, deterministischer Regelkern der spielbaren Nebenjobs.
## Die Oberflaeche darf anders inszenieren; Lohn und Fortschritt entstehen nur
## aus diesen Antworten und werden erst nach einer bestandenen Schicht verbucht.

const PROFILES := {
	"job_newspapers": {"mode": "route", "rounds": 10, "title": "MORGENROUTE",
		"brief": "Briefkasten erkennen und die Zeitung in die richtige Spur werfen."},
	"job_club_flyer": {"mode": "route", "rounds": 9, "title": "FLYER-RUNDE",
		"brief": "Nur passende Treffpunkte anfahren; keine Flyer in Sperrzonen."},
	"job_gruber_help": {"mode": "sort", "rounds": 10, "title": "WARENEINGANG",
		"brief": "Neue Ware anhand des Etiketts in das richtige Regalfach sortieren."},
	"job_shop_help": {"mode": "sort", "rounds": 12, "title": "LADENSCHLUSS",
		"brief": "PC- und Amiga-Ware sauber trennen, bevor die Kasse schliesst."},
	"job_rocky_repair": {"mode": "repair", "rounds": 8, "title": "FEHLERBANK",
		"brief": "Messwert lesen und das sichere Werkzeug fuer den naechsten Schritt waehlen."},
	"job_code_gig": {"mode": "code", "rounds": 10, "title": "BUILD-NACHT",
		"brief": "Fehlerstelle lesen, kleinsten korrekten Patch waehlen und den Build halten."},
}

const NEWSPAPER_ROUTE_TASKS := [
	["ROTE TUER · NR. 12", "LINKS", "red_door_12"],
	["BLAUER KASTEN · NR. 7", "MITTE-L", "blue_box_7"],
	["DOPPELHAUS · NR. 24", "MITTE-R", "semi_detached_24"],
	["ECKHAUS · NR. 3", "RECHTS", "corner_house_3"],
	["GARTENTOR · NR. 18", "LINKS", "garden_gate_18"],
	["WOHNBLOCK B · NR. 41", "MITTE-L", "apartment_b_41"],
	["WEISSER KASTEN · NR. 9", "MITTE-R", "white_box_9"],
	["HINTERHAUS · NR. 15", "RECHTS", "back_house_15"],
]
const FLYER_ROUTE_TASKS := [
	["KIOSK · AUSHANG", "LINKS", "kiosk_notice"],
	["PLATTENLADEN · BRETT", "MITTE-R", "record_shop_board"],
	["CLUB · ABENDKASSE", "RECHTS", "club_evening_desk"],
	["SCHULHOF · INFOBRETT", "MITTE-L", "school_noticeboard"],
	["JUGENDZENTRUM · TUER", "LINKS", "youth_centre_door"],
	["LAN-KELLER · TREPPE", "MITTE-L", "lan_cellar_stairs"],
	["FLOHMARKT · SZENETISCH", "MITTE-R", "flea_scene_table"],
	["POMMES-PALAST · KASSE", "RECHTS", "snack_bar_counter"],
]
const GRUBER_SORT_TASKS := [
	["A500-NETZTEIL", "STROM", "a500_power_supply"],
	["SCART/RGB-KABEL", "KABEL", "scart_rgb_cable"],
	["LEERDISK 3,5 ZOLL", "MEDIEN", "blank_disk"],
	["512-KB-RAM", "CHIPS", "ram_512k"],
	["IDE-FESTPLATTE", "LAUFWERK", "ide_hard_drive"],
	["JOYSTICK-ADAPTER", "KABEL", "joystick_adapter"],
	["DRUCKERPAPIER", "MEDIEN", "printer_paper"],
	["68030-KARTE", "CHIPS", "card_68030"],
]
const SHOP_SORT_TASKS := [
	["AT-NETZTEIL", "STROM", "at_power_supply"],
	["SERIELLE MAUS", "KABEL", "serial_mouse"],
	["CD-ROHLING", "MEDIEN", "blank_cd"],
	["VGA-KARTE", "CHIPS", "vga_card"],
	["IDE-CD-ROM", "LAUFWERK", "ide_cdrom"],
	["DRUCKERKABEL", "KABEL", "printer_cable"],
	["ZIP-MEDIUM", "MEDIEN", "zip_media"],
	["486-DX-BOARD", "CHIPS", "board_486dx"],
]
const REPAIR_TASKS := [
	["5-V-SCHIENE: 0,0 V", "MULTIMETER", "rail_5v_zero",
		"Das Geraet bleibt aus; am Referenzpunkt fehlt die Versorgung.",
		"Erst die Spannung gegen Masse messen. Noch nichts ausloeten.",
		"MESSKONTAKT", "Die Messung klaert, ob Netzteil oder Board die Spannung verliert."],
	["KALTE LOETSTELLE", "LOETSTATION", "cold_solder_joint",
		"Das Signal bricht bei leichtem Druck auf die matte Loetstelle ab.",
		"Die alte Stelle mit Flussmittel sauber nacharbeiten, ohne das Pad zu ueberhitzen.",
		"LOETTEMPERATUR", "Eine kontrollierte Nachloetung stellt den Kontakt wieder her."],
	["VERSCHMUTZTER LESEKOPF", "ISOPROPANOL", "dirty_read_head",
		"Lesefehler wandern; Mechanik und Drehzahl bleiben stabil.",
		"Den Kopf sparsam reinigen. Die Laufwerksjustage bleibt unangetastet.",
		"REINIGUNGSDRUCK", "Isopropanol entfernt den Film, ohne Kopf oder Spurlage zu veraendern."],
	["LOCKERER SOCKEL", "IC-ZIEHER", "loose_socket",
		"Der Chip reagiert auf Druck; Sockel und Pins sind optisch intakt.",
		"Stromlos und gleichmaessig ausheben, Pins pruefen und neu einsetzen.",
		"HEBELKRAFT", "Der IC-Zieher belastet Gehaeuse und Pins gleichmaessig."],
	["KURZSCHLUSSVERDACHT", "STROMLIMIT", "suspected_short",
		"Das Netzteil geht beim Einschalten sofort in Schutz.",
		"Den Strom begrenzen, bevor erneut Spannung angelegt wird.",
		"STROMGRENZE", "Die Begrenzung schuetzt Leiterbahnen, waehrend der Kurzschluss gesucht wird."],
	["GEBROCHENE LEITERBAHN", "DURCHGANG", "broken_trace",
		"Zwischen zwei Messpunkten fehlt die elektrische Verbindung.",
		"Die Strecke stromlos durchklingeln und die Unterbrechung markieren.",
		"PRUEFSCHWELLE", "Die Durchgangspruefung lokalisiert die Unterbrechung vor jeder Bruecke."],
	["THERMISCHER FEHLER", "KAELTESPRAY", "thermal_fault",
		"Der Fehler erscheint erst warm und verschwindet nach einer Pause.",
		"Verdaechtige Bauteile einzeln kuehlen und die Reaktion beobachten.",
		"KUEHLDOSIS", "Gezieltes Kaeltespray macht das temperaturempfindliche Bauteil sichtbar."],
	["FALSCHE POLARITAET", "SCHALTPLAN", "wrong_polarity",
		"Ein getauschtes Bauteil widerspricht der Markierung auf dem Board.",
		"Bestueckungsplan und Pinbelegung abgleichen, bevor Strom fliesst.",
		"PRUEFPUNKT", "Der Schaltplan klaert die Polaritaet ohne riskanten Einschaltversuch."],
]

const REPAIR_TOOL_ORDER := [
	"MULTIMETER", "LOETSTATION", "ISOPROPANOL", "IC-ZIEHER",
	"STROMLIMIT", "DURCHGANG", "KAELTESPRAY", "SCHALTPLAN",
]

const REPAIR_DECOYS := {
	"MULTIMETER": ["STROMLIMIT", "SCHALTPLAN"],
	"LOETSTATION": ["DURCHGANG", "IC-ZIEHER"],
	"ISOPROPANOL": ["KAELTESPRAY", "LOETSTATION"],
	"IC-ZIEHER": ["ISOPROPANOL", "LOETSTATION"],
	"STROMLIMIT": ["MULTIMETER", "SCHALTPLAN"],
	"DURCHGANG": ["MULTIMETER", "SCHALTPLAN"],
	"KAELTESPRAY": ["ISOPROPANOL", "MULTIMETER"],
	"SCHALTPLAN": ["MULTIMETER", "STROMLIMIT"],
}

const REPAIR_TOOL_HELP := {
	"MULTIMETER": "Messspitzen an Masse und Testpunkt setzen.",
	"LOETSTATION": "Spitze reinigen, Flussmittel dosieren und Kontakt kurz erwaermen.",
	"ISOPROPANOL": "Reinigungsstab leicht benetzen und den Kopf ohne Druck abziehen.",
	"IC-ZIEHER": "Beide Greifer ansetzen und den Chip gerade aus dem Sockel heben.",
	"STROMLIMIT": "Grenzwert niedrig setzen und die Spannung kontrolliert anheben.",
	"DURCHGANG": "Stromlos an beiden Enden der Leiterbahn pruefen.",
	"KAELTESPRAY": "Nur ein Bauteil kurz kuehlen und die Fehlerreaktion beobachten.",
	"SCHALTPLAN": "Bauteilkennung, Pin 1 und Versorgungspfad vergleichen.",
}
const CODE_TASKS := [
	["ARRAY INDEX = SIZE", "< SIZE", "array_index_size"],
	["LOOP OHNE EXIT", "BREAK-BEDINGUNG", "loop_without_exit"],
	["NULL VOR ZUGRIFF", "GUARD CLAUSE", "null_before_access"],
	["FRAME > BUDGET", "CACHE SPRITES", "frame_over_budget"],
	["DATEI NIE GESCHLOSSEN", "CLOSE IM CLEANUP", "file_never_closed"],
	["SCORE DOPPELT", "COMMIT-FLAG", "duplicate_score"],
	["INPUT ECHO", "EVENT.ECHO PRUEFEN", "input_echo"],
	["SAVE ALT", "MIGRATION VOR LOAD", "old_save"],
]

const CHOICE_KEYS := {
	"LINKS": "left", "MITTE-L": "centre_left", "MITTE-R": "centre_right", "RECHTS": "right",
	"STROM": "power", "KABEL": "cables", "MEDIEN": "media", "CHIPS": "chips", "LAUFWERK": "drives",
	"MULTIMETER": "multimeter", "LOETSTATION": "soldering_station",
	"ISOPROPANOL": "isopropyl", "IC-ZIEHER": "ic_puller", "STROMLIMIT": "current_limit",
	"DURCHGANG": "continuity", "KAELTESPRAY": "freeze_spray", "SCHALTPLAN": "schematic",
	"< SIZE": "less_than_size", "BREAK-BEDINGUNG": "break_condition",
	"GUARD CLAUSE": "guard_clause", "CACHE SPRITES": "cache_sprites",
	"CLOSE IM CLEANUP": "close_in_cleanup", "COMMIT-FLAG": "commit_flag",
	"EVENT.ECHO PRUEFEN": "check_event_echo", "MIGRATION VOR LOAD": "migrate_before_load",
}

var job_id := ""
var profile: Dictionary = {}
var round_index := 0
var correct_count := 0
var mistakes := 0
var streak := 0
var best_streak := 0
var points := 0
var performance_sum := 0.0
var fast_actions := 0
var prompt: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _last_task_index := -1


func configure(next_job_id: String, run_seed: int) -> void:
	job_id = next_job_id
	profile = (PROFILES.get(job_id, {"mode": "sort", "rounds": 8,
		"title": "ARBEITSSCHICHT", "brief": "Auftraege sauber abarbeiten."}) as Dictionary).duplicate(true)
	_rng.seed = run_seed
	round_index = 0
	correct_count = 0
	mistakes = 0
	streak = 0
	best_streak = 0
	points = 0
	performance_sum = 0.0
	fast_actions = 0
	_last_task_index = -1
	_next_prompt()


func mode() -> String:
	return str(profile.get("mode", "sort"))


func interaction() -> String:
	match mode():
		"route": return "lane_delivery"
		"sort": return "drag_to_bin"
		"repair": return "tool_diagnosis"
		"code": return "patch_console"
	return "work_order"


func total_rounds() -> int:
	return int(profile.get("rounds", 8))


func finished() -> bool:
	return round_index >= total_rounds()


func passed() -> bool:
	return finished() and correct_count >= ceili(total_rounds() * 0.7)


func answer(choice_index: int, performance: float = 1.0) -> Dictionary:
	if finished() or prompt.is_empty():
		return {"accepted": false}
	var choices: Array = prompt.get("choices", [])
	var expected_index := int(prompt.get("correct", -1))
	var expected_choice := str(choices[expected_index]) if expected_index >= 0 and expected_index < choices.size() else ""
	var resolved_signal_id := str(prompt.get("signal_id", ""))
	var resolved_reason := str(prompt.get("reason", ""))
	var correct := choice_index == int(prompt.get("correct", -1))
	var action_quality := clampf(performance, 0.0, 1.0)
	if correct:
		correct_count += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		performance_sum += action_quality
		if action_quality >= 0.84:
			fast_actions += 1
		points += 70 + mini(80, streak * 10) + int(round(action_quality * 50.0))
	else:
		mistakes += 1
		streak = 0
		points = maxi(0, points - 25)
	round_index += 1
	var result := {"accepted": true, "correct": correct, "performance": action_quality,
		"expected": expected_index, "expected_choice": expected_choice,
		"signal_id": resolved_signal_id, "reason": resolved_reason, "finished": finished()}
	if not finished():
		_next_prompt()
	return result


func score() -> int:
	var accuracy := float(correct_count) / maxf(1.0, total_rounds())
	var streak_bonus := float(best_streak) / maxf(1.0, total_rounds())
	var execution := performance_sum / maxf(1.0, float(correct_count))
	return clampi(int(round(accuracy * 730.0 + streak_bonus * 150.0 + execution * 120.0)), 0, 1000)


func details() -> Dictionary:
	return {"job": job_id, "mode": mode(), "rounds": total_rounds(),
		"correct": correct_count, "mistakes": mistakes, "best_streak": best_streak,
		"fast_actions": fast_actions,
		"timing_precision": performance_sum / maxf(1.0, float(correct_count)),
		"raw_points": points, "score": score()}


func localized_title() -> String:
	return Loc.t("ui.job_shift_minigame.profile.%s.title" % job_id,
		str(profile.get("title", "ARBEITSSCHICHT")))


func localized_brief() -> String:
	return Loc.t("ui.job_shift_minigame.profile.%s.brief" % job_id,
		str(profile.get("brief", "Auftraege sauber abarbeiten.")))


func localized_signal() -> String:
	return Loc.t("ui.job_shift_minigame.signal.%s" % str(prompt.get("signal_id", "unknown")),
		str(prompt.get("signal", "")))


func localized_choices() -> Array[String]:
	var translated: Array[String] = []
	for choice: String in prompt.get("choices", []):
		translated.append(Loc.t("ui.job_shift_minigame.choice.%s" % str(CHOICE_KEYS.get(choice, "unknown")), choice))
	return translated


func localized_choice_id(choice: String) -> String:
	return Loc.t("ui.job_shift_minigame.choice.%s" % str(CHOICE_KEYS.get(choice, "unknown")), choice)


func localized_repair_field(field: String) -> String:
	if mode() != "repair":
		return ""
	var signal_id := str(prompt.get("signal_id", "unknown"))
	return Loc.t("ui.job_shift_minigame.repair.%s.%s" % [signal_id, field],
		str(prompt.get(field, "")))


func localized_tool_help(choice: String) -> String:
	return Loc.t("ui.job_shift_minigame.tool_help.%s" % str(CHOICE_KEYS.get(choice, "unknown")),
		str(REPAIR_TOOL_HELP.get(choice, "Werkzeug kontrolliert anwenden.")))


func _next_prompt() -> void:
	var source: Array = _tasks_for_mode()
	var task_index := _rng.randi_range(0, source.size() - 1)
	if source.size() > 1 and task_index == _last_task_index:
		task_index = (task_index + 1 + _rng.randi_range(0, source.size() - 2)) % source.size()
	_last_task_index = task_index
	var raw: Array = source[task_index]
	var expected := str(raw[1])
	var choices := _repair_choices(expected) if mode() == "repair" else _choices_for_mode()
	# Spuren und Lagerfaecher bleiben raeumlich stabil: Der Spieler lernt eine
	# Strecke beziehungsweise ein Lager statt pro Runde umsortierte Antwortkarten.
	# Nur Werkzeug- und Patch-Saetze rotieren reproduzierbar gegen Auswendigklicken.
	if mode() == "code":
		choices.sort()
		var rotate_by := _rng.randi_range(0, choices.size() - 1)
		for unused: int in rotate_by:
			choices.push_back(choices.pop_front())
	prompt = {"signal": str(raw[0]), "signal_id": str(raw[2]), "choices": choices,
		"correct": choices.find(expected), "round": round_index + 1}
	if mode() == "repair":
		prompt["clue"] = str(raw[3])
		prompt["procedure"] = str(raw[4])
		prompt["gauge"] = str(raw[5])
		prompt["reason"] = str(raw[6])


func _tasks_for_mode() -> Array:
	match mode():
		"route": return FLYER_ROUTE_TASKS if job_id == "job_club_flyer" else NEWSPAPER_ROUTE_TASKS
		"repair": return REPAIR_TASKS
		"code": return CODE_TASKS
	return SHOP_SORT_TASKS if job_id == "job_shop_help" else GRUBER_SORT_TASKS


func _choices_for_mode() -> Array:
	match mode():
		"route": return ["LINKS", "MITTE-L", "MITTE-R", "RECHTS"]
		"repair": return ["MULTIMETER", "LOETSTATION", "ISOPROPANOL", "IC-ZIEHER",
			"STROMLIMIT", "DURCHGANG", "KAELTESPRAY", "SCHALTPLAN"]
		"code": return ["< SIZE", "BREAK-BEDINGUNG", "GUARD CLAUSE", "CACHE SPRITES",
			"CLOSE IM CLEANUP", "COMMIT-FLAG", "EVENT.ECHO PRUEFEN", "MIGRATION VOR LOAD"]
	return ["STROM", "KABEL", "MEDIEN", "CHIPS", "LAUFWERK"]


func _repair_choices(expected: String) -> Array:
	var choices: Array = [expected]
	for decoy: String in REPAIR_DECOYS.get(expected, []):
		choices.append(decoy)
	choices.sort_custom(func(a: String, b: String) -> bool:
		return REPAIR_TOOL_ORDER.find(a) < REPAIR_TOOL_ORDER.find(b))
	return choices
