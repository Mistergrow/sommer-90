extends Node
## Gemeinsame Meta-Schicht aller Minispiele: Katalog, Rekorde, Erschaffenes
## und faire Einmal-Belohnungen. Die einzelnen Spiele bleiben eigenständige UI,
## teilen aber Persistenz und Auswertung.

signal records_changed

const CONFIG := "res://data/minigames.json"
const AAA_CONFIG := "res://data/minigame_aaa_profiles.json"
const MASTER_IDS := [
	"label_design", "box_sort", "drive_clean", "joystick_repair", "monitor_tune",
	"cable_untangle", "bargain", "bbs_link", "tracker_pattern", "paint",
	"room_tidy", "hardware_assembly", "listing_type",
	"scene_patch", "disk_rescue", "disk_media_repair", "printer_align", "mixtape", "cracktro_opt", "shop_diagnosis",
	"job_shift", "household_sprint",
]

var _defs: Array = []
var records: Dictionary = {}
var creations: Dictionary = {}
var telemetry: Dictionary = {}
var _aaa_profiles: Dictionary = {}


func _ready() -> void:
	if FileAccess.file_exists(CONFIG):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if parsed is Dictionary:
			_defs = parsed.get("minigames", [])
	if FileAccess.file_exists(AAA_CONFIG):
		var aaa_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AAA_CONFIG))
		if aaa_parsed is Dictionary:
			_aaa_profiles = aaa_parsed.get("profiles", {})


func reset() -> void:
	records = {}
	creations = {"paint": [], "tracker": [], "listing": [], "intro": [], "mixtape": []}
	telemetry = {}
	records_changed.emit()


func all() -> Array:
	return _defs


func definition(id: String) -> Dictionary:
	for d: Dictionary in _defs:
		if str(d.get("id", "")) == id:
			return d
	return {}


func aaa_profile(id: String) -> Dictionary:
	return (_aaa_profiles.get(id, {}) as Dictionary).duplicate(true)


func begin_session(id: String) -> int:
	if id not in MASTER_IDS:
		return -1
	var data: Dictionary = telemetry.get(id, {"sessions": 0, "actions": 0, "hints": 0,
		"errors": 0, "hitches": 0, "max_frame_ms": 0.0, "input": {}})
	data["sessions"] = int(data.get("sessions", 0)) + 1
	telemetry[id] = data
	return int(data.sessions)


func note_runtime(id: String, event: StringName, value: Variant = true) -> void:
	if id not in MASTER_IDS:
		return
	var data: Dictionary = telemetry.get(id, {"sessions": 0, "actions": 0, "hints": 0,
		"errors": 0, "hitches": 0, "max_frame_ms": 0.0, "input": {}})
	match event:
		&"action", &"hint", &"error", &"hitch":
			var key := str(event) + ("es" if event == &"hitch" else "s")
			data[key] = int(data.get(key, 0)) + 1
		&"frame_ms": data["max_frame_ms"] = maxf(float(data.get("max_frame_ms", 0.0)), float(value))
		&"input":
			var inputs: Dictionary = data.get("input", {})
			var input_name := str(value)
			inputs[input_name] = int(inputs.get(input_name, 0)) + 1
			data["input"] = inputs
	telemetry[id] = data


func availability(id: String) -> Dictionary:
	var d := definition(id)
	if d.is_empty():
		return {"ok": false, "reason": "Unbekanntes Minispiel."}
	if TimeManager.year < int(d.get("year_from", 1990)):
		return {"ok": false, "reason": Loc.t("sys.minigame_manager.ab_d_verfugbar", "Ab %d verfügbar.") % int(d["year_from"])}
	var hardware := str(d.get("hardware", ""))
	if hardware != "" and not PlayerStats.has_hardware(hardware):
		return {"ok": false, "reason": Loc.t("sys.minigame_manager.benotigt_s", "Benötigt: %s.") % hardware.replace("_", " ")}
	return {"ok": true, "reason": ""}


func record(id: String) -> Dictionary:
	return records.get(id, {"plays": 0, "wins": 0, "best_score": 0, "last_score": 0})


func finish(id: String, success: bool, score: int, details: Dictionary = {}) -> Dictionary:
	var r: Dictionary = record(id).duplicate(true)
	var final_details := details.duplicate(true)
	if id in MASTER_IDS:
		final_details["aaa_contract"] = 1
		final_details["runtime"] = (telemetry.get(id, {}) as Dictionary).duplicate(true)
		final_details["content_variants"] = (aaa_profile(id).get("variants", []) as Array).size()
	var first_win := success and int(r.get("wins", 0)) == 0
	var new_record := success and score > int(r.get("best_score", 0))
	r["plays"] = int(r.get("plays", 0)) + 1
	r["last_score"] = maxi(0, score)
	if success:
		r["wins"] = int(r.get("wins", 0)) + 1
		r["best_score"] = maxi(score, int(r.get("best_score", 0)))
	if not final_details.is_empty():
		r["last_details"] = final_details
	records[id] = r
	AudioManager.minigame_cue(id,&"success"if success else&"error")
	if first_win:
		PlayerStats.change_stat("wissen", 1)
		AchievementManager.note("won_minigame")
	if success:
		QuestManager.note_action("minigame:" + id)
		QuestManager.evaluate()
	if new_record and not first_win:
		PlayerStats.change_stat("ruf", 1)
	if mastered_count() >= MASTER_IDS.size():
		AchievementManager.note("minigame_master")
	PlaytestTelemetry.note_minigame_finished(id, success, score)
	records_changed.emit()
	return {"first_win": first_win, "new_record": new_record, "record": r}


func mastered_count() -> int:
	var count := 0
	for id: String in MASTER_IDS:
		if int(record(id).get("wins", 0)) > 0:
			count += 1
	return count


func save_creation(kind: String, payload: Dictionary) -> void:
	if not creations.has(kind):
		creations[kind] = []
	var list: Array = creations[kind]
	var entry := payload.duplicate(true)
	entry["date"] = TimeManager.date_string()
	entry["year"] = TimeManager.year
	list.push_front(entry)
	if list.size() > 12:
		list.resize(12)
	creations[kind] = list
	records_changed.emit()


func latest_creation(kind: String) -> Dictionary:
	var list: Array = creations.get(kind, [])
	return {} if list.is_empty() else (list[0] as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	return {"records": records, "creations": creations, "telemetry": telemetry}


func from_dict(d: Dictionary) -> void:
	records = d.get("records", {})
	creations = d.get("creations", {"paint": [], "tracker": [], "listing": [], "intro": [], "mixtape": []})
	telemetry = d.get("telemetry", {})
	# Alte Saves erhalten neue Creation-Kategorien ohne Datenverlust.
	for kind in ["paint", "tracker", "listing", "intro", "mixtape"]:
		if not creations.has(kind):
			creations[kind] = []
	records_changed.emit()
