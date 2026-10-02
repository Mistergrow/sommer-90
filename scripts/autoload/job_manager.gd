extends Node
## JobManager — Nebenjobs (Phase C, Ökonomie). Der stetige Verdienst neben
## Taschengeld und Kopien-Handel: pro Job kostet es Energie + ein Zeitfenster
## (advance_slot) und bringt Geld + Nebeneffekte (Wissen, Ruf, Eltern-Toleranz).
##
## Jobs sind orts-, tages-, zeit- und voraussetzungsgebunden (data/jobs.json) und
## haben Cooldowns/Tageslimits — so bleibt jeder Tag eine kleine Planungsfrage.

signal jobs_changed

const CONFIG := "res://data/jobs.json"
const DAY_KEYS := ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
const ROUTE_MODES := ["car", "bike", "bus", "walk"]
const CalendarClock := preload("res://scripts/autoload/time_manager.gd")

var _defs: Array = []
var _last_day: Dictionary = {}    # job_id -> Spieltag der letzten Erledigung
var _done_today: Dictionary = {}  # job_id -> Anzahl heute
var _completed_counts: Dictionary = {} # job_id -> bestandene spielbare Schichten


func _ready() -> void:
	if FileAccess.file_exists(CONFIG):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if d is Dictionary:
			_defs = d.get("jobs", [])
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(func() -> void: _done_today = {}; jobs_changed.emit())


func all_jobs() -> Array:
	return _defs


func job_by_id(id: String) -> Dictionary:
	for j in _defs:
		if str(j.get("id", "")) == id:
			return j
	return {}


## Ist der Job GRUNDSÄTZLICH gerade angeboten? (Ort, Tag, Zeitfenster, Jahr,
## Auftraggeber anwesend, Trust/Wissen) — ohne Energie/Cooldown (die trennt do_job/can_do).
func offered_here(job: Dictionary, location_id: String) -> bool:
	return offered_at(job, location_id, {
		"year": TimeManager.year,
		"weekday": TimeManager.weekday(),
		"slot": TimeManager.slot,
	})


## Seiteneffektfreie Angebotspruefung fuer Reise- und Terminprognosen. Die
## Reise bleibt innerhalb eines Spieltags; NPC-Tagesplan und Zufallsanwesenheit
## sind deshalb dieselben wie beim spaeteren echten Start, nur Jahr/Wochentag/
## Zeitfenster stammen aus der prognostizierten Ankunft.
func offered_at(job: Dictionary, location_id: String, at: Dictionary) -> bool:
	if str(job.get("location", "")) != location_id:
		return false
	var y := int(at.get("year", TimeManager.year))
	if y < int(job.get("year_from", 0)):
		return false
	# Story-Jobs duerfen als Catch-up nicht aus einer bereits aktiven Quest
	# verschwinden. Ohne diese Ausnahme blieben Praktikum/Ausbildung/Pruefung nach
	# ihrem historischen Marktfenster dauerhaft im Questlog, obwohl der Manager
	# die einzig passende Aktion nicht mehr anbot.
	var active_quest := str(job.get("requires_quest_active", ""))
	var is_story_catchup := active_quest != "" and QuestManager.is_active(active_quest)
	if y > int(job.get("year_to", 9999)) and not is_story_catchup:
		return false
	var days: Array = job.get("days", [])
	var weekday := clampi(int(at.get("weekday", TimeManager.weekday())), 0, DAY_KEYS.size() - 1)
	if not days.is_empty() and not (DAY_KEYS[weekday] in days):
		return false
	# JSON-Zahlen kommen als Float — int-sicher vergleichen.
	var slots: Array = job.get("slots", [])
	if not slots.is_empty():
		var slot_ok := false
		for sv in slots:
			if int(sv) == int(at.get("slot", TimeManager.slot)):
				slot_ok = true
				break
		if not slot_ok:
			return false
	if job.has("needs_npc"):
		# Ein bereits angenommener, aktuell verlangter Storyfall bleibt auch in
		# migrierten Saves spielbar, deren alter NPC-Tagesplan den neuen Nachfolger
		# noch nicht kennt. Ort und Zeitfenster gelten weiterhin unveraendert.
		if not _is_pending_story_job(job) \
				and not (str(job["needs_npc"]) in NPCManager.here_today(location_id)):
			return false
	if job.has("min_trust"):
		var mt: Dictionary = job["min_trust"]
		if NPCManager.get_trust(str(mt.get("npc", ""))) < int(mt.get("value", 0)):
			return false
	if job.has("min_wissen") and PlayerStats.wissen < int(job["min_wissen"]):
		return false
	# Story-/Ausbildungsfreigaben sind Autoritaet, nicht bloss ein Zahlenwert:
	# Vertrauen allein berechtigt niemanden, Grubers Werkstatt zu benutzen.
	if job.has("requires_flag") and not bool(GameManager.flags.get(str(job["requires_flag"]), false)):
		return false
	if job.has("requires_quest_active") and not QuestManager.is_active(str(job["requires_quest_active"])):
		return false
	if job.has("requires_quest_done") and not QuestManager.is_done(str(job["requires_quest_done"])):
		return false
	return true


func available(location_id: String) -> Array:
	return _defs.filter(func(j: Dictionary) -> bool: return offered_here(j, location_id))


## Einziger Startvertrag fuer alle spielbaren Jobs. Fenster, Kiosk und Tests
## benutzen damit dieselben Regeln und koennen keinen halboffenen Lauf erzeugen.
func start_gate(id: String, location_id: String = "") -> Dictionary:
	if GameManager.state != GameManager.State.PLAYING:
		return {"ok": false, "reason": Loc.t("sys.job_manager.not_playing",
			"Nur waehrend eines laufenden Spiels verfuegbar.")}
	var job := job_by_id(id)
	if job.is_empty() or str(job.get("minigame", "")) == "":
		return {"ok": false, "reason": Loc.t("sys.job_manager.no_playable_order",
			"Hier liegt gerade kein spielbarer Arbeitsauftrag vor.")}
	var actual_location := GameManager.current_location_id if location_id.is_empty() else location_id
	if not offered_here(job, actual_location):
		return {"ok": false, "reason": Loc.t("sys.job_manager.not_offered_now",
			"Auftraggeber, Ort oder Zeitfenster passen gerade nicht.")}
	var check := can_do(job)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": str(check.get("reason", "Auftrag derzeit nicht moeglich."))}
	return {"ok": true, "reason": "", "job": job}


func completion_count(id: String) -> int:
	return maxi(0, int(_completed_counts.get(id, 0)))


## Naechster kuratierter Kampagnentag, an dem ein terminierter Job angeboten
## werden kann. Das Questboard benutzt dieselbe Jobdefinition wie der Gatekeeper;
## dadurch kann im Text nie wieder ein anderer Praktikumstag stehen als im Laden.
func next_appointment(job: Dictionary) -> Dictionary:
	if job.is_empty():
		return {}
	var allowed_days: Array = job.get("days", [])
	var slots: Array = job.get("slots", [])
	var current_code := TimeManager.year * 10000 + TimeManager.month * 100 + TimeManager.day
	var max_slot := 4
	if not slots.is_empty():
		max_slot = -1
		for raw_slot: Variant in slots:
			max_slot = maxi(max_slot, int(raw_slot))
	for appointment_year in range(TimeManager.year, TimeManager.year + 3):
		for date: Dictionary in TimeManager.campaign_dates_for_year(appointment_year):
			var date_code := int(date.get("year", appointment_year)) * 10000 \
				+ int(date.get("month", 1)) * 100 + int(date.get("day", 1))
			if date_code < current_code or (date_code == current_code and TimeManager.slot > max_slot):
				continue
			var weekday := CalendarClock.weekday_for_date(int(date.get("year", appointment_year)),
				int(date.get("month", 1)), int(date.get("day", 1)))
			if not allowed_days.is_empty() and DAY_KEYS[weekday] not in allowed_days:
				continue
			var result := date.duplicate(true)
			result["weekday"] = weekday
			result["today"] = date_code == current_code
			result["slots"] = slots.duplicate()
			return result
	return {}


func appointment_text(job: Dictionary) -> String:
	var appointment := next_appointment(job)
	if appointment.is_empty():
		return "Kein weiterer Termin im aktuellen Sommerplan."
	var times: Array[String] = []
	for raw_slot: Variant in appointment.get("slots", []):
		var slot_index := clampi(int(raw_slot), 0, TimeManager.SLOT_CLOCK_MINUTES.size() - 1)
		var minutes := int(TimeManager.SLOT_CLOCK_MINUTES[slot_index])
		times.append("%02d:%02d" % [floori(minutes / 60.0), minutes % 60])
	var when := "HEUTE" if bool(appointment.get("today", false)) else "%s, %d. %s" % [
		TimeManager.WEEKDAYS[int(appointment.get("weekday", 0))].to_upper(),
		int(appointment.get("day", 1)),
		TimeManager.localized_month_name(int(appointment.get("month", 1))).to_upper(),
	]
	return "%s · %s" % [when, " ODER ".join(times)]


## Cooldown-Schlüssel: Jobs mit `group` teilen sich EINEN Slot (z. B. Grubers
## Werkstatt — man hilft pro Besuch bei EINER Aufgabe, nicht bei allen dreien).
func _cd_key(job: Dictionary) -> String:
	var g := str(job.get("group", ""))
	return g if g != "" else str(job.get("id", ""))


## Ein bereits angenommener Storyauftrag darf nicht durch eine zuvor erledigte
## freiwillige Arbeit derselben Jobgruppe blockiert werden. Entscheidend ist
## nicht irgendeine aktive Quest, sondern dass deren AKTUELLES Ziel exakt diesen
## Job verlangt; nach erfolgreichem Abschluss greift der normale Cooldown wieder.
func _is_pending_story_job(job: Dictionary) -> bool:
	var quest_id := str(job.get("requires_quest_active", ""))
	var job_id := str(job.get("id", ""))
	if quest_id.is_empty() or job_id.is_empty() or not QuestManager.is_active(quest_id):
		return false
	var stage_contract: Dictionary = QuestManager.explain_current_stage(quest_id)
	var goal: Dictionary = stage_contract.get("goal", {})
	# Aeltere Storyjobs benennen den Job als Questaktion. Neuere Auftraege
	# benennen das sichtbare, tatsaechlich zu bestehende Minispiel. Beide
	# Varianten sind derselbe verpflichtende Spielerweg und muessen daher einen
	# zuvor verbrauchten freiwilligen Gruppen-Cooldown ueberstimmen.
	if str(goal.get("action", "")) == "job:" + job_id:
		return true
	var minigame_id := str(job.get("minigame", ""))
	if minigame_id.is_empty():
		return false
	return str(goal.get("minigame_done", "")) == minigame_id \
		or str(goal.get("action", "")) == "minigame:" + minigame_id


## Kann der Job JETZT ausgeführt werden? {ok, reason} — prüft Cooldown, Tageslimit, Energie.
func can_do(job: Dictionary) -> Dictionary:
	return _can_do_with_minutes_left(job, TimeManager.minutes_left())


## Gemeinsamer Ressourcenvertrag fuer Start und Ankunftsprognose. Dadurch kann
## der Wegweiser keinen Job versprechen, dessen Dauer nach der Fahrt nicht mehr
## in den Tag passt.
func _can_do_with_minutes_left(job: Dictionary, available_minutes: int) -> Dictionary:
	var id := _cd_key(job)
	var cd := int(job.get("cooldown_days", 0))
	var pending_story_job := _is_pending_story_job(job)
	if not pending_story_job and cd > 0 and _last_day.has(id) \
			and TimeManager.day_counter - int(_last_day[id]) < cd:
		return {"ok": false, "reason": Loc.t("sys.job_manager.heute_schon_erledigt_komm_in_d", "Heute schon erledigt — komm in %d Tag(en) wieder.") % cd}
	if not pending_story_job and cd <= 0 \
			and int(_done_today.get(id, 0)) >= int(job.get("daily_limit", 1)):
		return {"ok": false, "reason": Loc.t("sys.job_manager.fur_heute_erledigt", "Für heute erledigt.")}
	if PlayerStats.energie < int(job.get("energy", 0)):
		return {"ok": false, "reason": Loc.t("sys.job_manager.zu_mude_dafur_fehlt_kraft_d", "Zu müde — dafür fehlt die Kraft (%d Energie nötig).") % int(job.get("energy", 0))}
	# Nachts steht die Uhr — kein Arbeiten mehr, der Tag will aktiv beendet werden.
	if duration_minutes(job) > maxi(0, available_minutes):
		return {"ok": false, "reason": Loc.t("sys.job_manager.es_ist_zu_spat_heute_keine", "Es ist zu spät — heute keine Arbeit mehr. Geh lieber schlafen.")}
	return {"ok": true, "reason": ""}


## Prueft denselben Job fuer den Zeitpunkt NACH einer Reise, ohne Zeit, Geld
## oder Weltzustand zu veraendern. Dieser Vertrag wird sowohl vom Wegweiser als
## auch von der Karte verwendet.
func arrival_gate(job: Dictionary, location_id: String, elapsed_minutes: int) -> Dictionary:
	var arrival: Dictionary = TimeManager.preview_after_minutes(elapsed_minutes)
	if not offered_at(job, location_id, arrival):
		return {"ok": false, "reason": Loc.t("sys.job_manager.shift_missed_on_arrival",
			"Bei deiner Ankunft ist diese Schicht nicht verfügbar."), "arrival": arrival}
	var check := _can_do_with_minutes_left(job, TimeManager.minutes_left() - elapsed_minutes)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": str(check.get("reason", "")), "arrival": arrival}
	return {"ok": true, "reason": "", "arrival": arrival}


## Schnellste verbindlich erreichbare Route zu einem Job. Ein Verkehrsmittel
## wird nur angeboten, wenn Ort, Schicht, Fahrgeld und vollstaendige Jobdauer
## bei Ankunft zusammenpassen. Bei gleicher Fahrzeit gewinnt die guenstigere
## Route.
func route_preview(job: Dictionary, from_location: String) -> Dictionary:
	var target := str(job.get("location", ""))
	if target.is_empty() or target == from_location:
		return {"ok": false, "reason": Loc.t("sys.job_manager.no_job_route",
			"Für diesen Auftrag ist kein Arbeitsweg nötig.")}
	var best: Dictionary = {}
	var fallback_reason := Loc.t("sys.job_manager.not_reachable_today",
		"Diese Schicht ist heute nicht mehr rechtzeitig erreichbar.")
	for mode: String in ROUTE_MODES:
		if not bool(TownManager.mode_unlocked(mode).get("ok", false)):
			continue
		var travel: Dictionary = TownManager.travel_preview(from_location, target, mode, true)
		if not bool(travel.get("ok", false)):
			fallback_reason = str(travel.get("reason", fallback_reason))
			continue
		var fare := int(travel.get("dm", 0))
		if fare > int(PlayerStats.geld):
			continue
		var elapsed := int(travel.get("minutes", 0))
		var arrival := arrival_gate(job, target, elapsed)
		if not bool(arrival.get("ok", false)):
			fallback_reason = str(arrival.get("reason", fallback_reason))
			continue
		var candidate := travel.duplicate(true)
		candidate["ok"] = true
		candidate["mode"] = mode
		candidate["job_id"] = str(job.get("id", ""))
		candidate["target"] = target
		candidate["arrival"] = arrival.get("arrival", {})
		if best.is_empty() or elapsed < int(best.get("minutes", 999999)) \
				or (elapsed == int(best.get("minutes", 999999)) and fare < int(best.get("dm", 999999))):
			best = candidate
	if best.is_empty():
		return {"ok": false, "reason": fallback_reason, "target": target,
			"job_id": str(job.get("id", ""))}
	return best


## Exakte Dauer statt pauschalem Fenstersprung. Alte Mod-/Save-Daten ohne
## minutes_cost behalten ueber slot_cost denselben groben Zeitwert.
func duration_minutes(job: Dictionary) -> int:
	if job.has("minutes_cost"):
		return maxi(1, int(job.get("minutes_cost", 90)))
	return maxi(1, int(job.get("slot_cost", 1))) * 120


## Job erledigen: Energie + Zeitfenster kosten, Lohn zahlen, Effekte anwenden,
## optionales Risiko würfeln. Rückgabe {ok, text}.
func do_job(id: String) -> Dictionary:
	var job := job_by_id(id)
	if job.is_empty():
		return {"ok": false, "text": Loc.t("sys.job_manager.diesen_job_gibt_es_nicht", "Diesen Job gibt es nicht.")}
	if str(job.get("minigame", "")) != "":
		return {"ok": false, "text": Loc.t("sys.job_manager.dieser_auftrag_wird_an_werkbank_gespielt", "Dieser Auftrag wird an der Werkbank gespielt.")}
	if not offered_here(job, GameManager.current_location_id):
		return {"ok": false, "text": Loc.t("sys.job_manager.dieser_auftrag_wurde_dir_hier_jetzt", "Dieser Auftrag wurde dir hier und jetzt nicht erteilt.")}
	var chk := can_do(job)
	if not chk["ok"]:
		return {"ok": false, "text": str(chk["reason"])}
	var effect_check: Dictionary = EventManager.validate_effects(job.get("effects", []))
	if not bool(effect_check.get("ok", false)):
		return {"ok": false, "text": str(effect_check.get("text", "Auftrag derzeit nicht möglich."))}
	if not PlayerStats.use_energy(int(job.get("energy", 0)), "job_commit"):
		return {"ok": false, "text": Loc.t("sys.job_manager.zu_mude", "Zu müde.")}

	var pay_range: Array = job.get("pay", [5, 10])
	var pay := randi_range(int(pay_range[0]), int(pay_range[1]))
	var text := ""
	# Risiko (z. B. Reparatur misslingt) → Teil-Lohn.
	if job.has("risk"):
		var risk: Dictionary = job["risk"]
		if randf() < float(risk.get("chance", 0.0)):
			pay = int(round(float(pay) * float(risk.get("pay_factor", 0.5))))
			text = str(risk.get("text", "")) + " "
	PlayerStats.add_money(pay)
	EventManager.apply_effects(job.get("effects", []))
	QuestManager.note_action("job:" + id)
	TimeManager.advance_minutes(duration_minutes(job))

	_last_day[_cd_key(job)] = TimeManager.day_counter
	_done_today[id] = int(_done_today.get(id, 0)) + 1
	AudioManager.play("coins")
	AchievementManager.note("did_job")
	jobs_changed.emit()
	return {"ok": true, "text": text + _completion_text(job, pay, 0)}


## Einen spielbaren Nebenjob atomar abschliessen. Oeffnen/Abbrechen zahlt nichts;
## nur das Minispiel darf diese Methode nach seiner eigenen Erfolgspruefung rufen.
## Der Lohn ist deterministisch aus dem Score statt ein zweites Zufallsrisiko.
func complete_minigame_job(id: String, score: int, details: Dictionary = {}) -> Dictionary:
	var job := job_by_id(id)
	if job.is_empty() or str(job.get("minigame", "")) == "":
		return {"ok": false, "text": Loc.t("sys.job_manager.kein_spielbarer_auftrag", "Kein spielbarer Auftrag.")}
	if not offered_here(job, GameManager.current_location_id):
		return {"ok": false, "text": Loc.t("sys.job_manager.auftraggeber_oder_zeitfenster_ist_nicht_mehr", "Der Auftraggeber oder das Zeitfenster ist nicht mehr verfuegbar.")}
	var chk := can_do(job)
	if not bool(chk.get("ok", false)):
		return {"ok": false, "text": str(chk.get("reason", "Auftrag derzeit nicht moeglich."))}
	var effect_check: Dictionary = EventManager.validate_effects(job.get("effects", []))
	if not bool(effect_check.get("ok", false)):
		return {"ok": false, "text": str(effect_check.get("text", "Auftrag derzeit nicht moeglich."))}
	var energy := int(job.get("energy", 0))
	if not PlayerStats.use_energy(energy, "job_commit"):
		return {"ok": false, "text": "Zu muede."}
	var pay_range: Array = job.get("pay", [5, 10])
	var quality := clampf(float(score) / 1000.0, 0.0, 1.0)
	var pay := int(round(lerpf(float(pay_range[0]), float(pay_range[1]), quality)))
	# Spielbare Auftraege bleiben Nebenjobs statt Geldautomaten: Wiederholungen
	# werden schwerer und zahlen nach jedem bereits gewonnenen Durchlauf etwas
	# weniger, jedoch nie unter die explizite Untergrenze des Jobs.
	# Jeder Auftrag hat seine eigene Lern-/Lohnkurve. Frueher teilten sich alle
	# job_shift-Varianten denselben globalen Zaehler: Eine Zeitungsrunde senkte
	# dadurch spaeter sogar den Lohn eines Programmierauftrags.
	var prior_wins := completion_count(id)
	var repeat_decay := float(job.get("repeat_pay_decay", 0.0))
	var min_pay_factor := clampf(float(job.get("min_pay_factor", 1.0)), 0.0, 1.0)
	var repeat_factor := maxf(min_pay_factor, 1.0 - prior_wins * repeat_decay)
	pay = maxi(1, int(round(pay * repeat_factor)))
	var bonus_max := maxi(0, int(job.get("skill_bonus_max", 0)))
	var bonus_quality := clampf((float(score) - 700.0) / 300.0, 0.0, 1.0)
	var skill_bonus := int(round(float(bonus_max) * bonus_quality))
	pay += skill_bonus
	PlayerStats.add_money(pay)
	EventManager.apply_effects(job.get("effects", []))
	QuestManager.note_action("job:" + id)
	TimeManager.advance_minutes(duration_minutes(job))
	_last_day[_cd_key(job)] = TimeManager.day_counter
	_done_today[id] = int(_done_today.get(id, 0)) + 1
	_completed_counts[id] = prior_wins + 1
	GameManager.flags["last_minigame_job"] = {
		"id": id, "score": score, "pay": pay, "repeat_factor": repeat_factor,
		"prior_wins": prior_wins, "skill_bonus": skill_bonus,
		"details": details.duplicate(true),
	}
	AudioManager.play("coins")
	AchievementManager.note("did_job")
	jobs_changed.emit()
	return {"ok": true, "text": _completion_text(job, pay, score),
		"pay": pay, "repeat_factor": repeat_factor, "skill_bonus": skill_bonus}


func _completion_text(job: Dictionary, pay: int, score: int) -> String:
	var lines: Array = job.get("success_lines", [])
	var job_id := str(job.get("id", ""))
	var line := Loc.t("ui.job_manager.clean_done", "Sauber erledigt.")
	if not lines.is_empty():
		var selector := posmod(hash("%s/%d/%d" % [job_id,
			TimeManager.day_counter, score]), lines.size())
		line = Loc.t("job.%s.success_lines.%d" % [job_id, selector], str(lines[selector]))
	var job_name := Loc.t("job.%s.name" % job_id, str(job.get("name", "Job")))
	return "%s  +%d DM · %s" % [job_name.to_upper(), pay, line]


func to_dict() -> Dictionary:
	return {"last_day": _last_day, "done_today": _done_today,
		"completed_counts": _completed_counts}


func from_dict(d: Dictionary) -> void:
	_last_day = d.get("last_day", {})
	_done_today = d.get("done_today", {})
	_completed_counts = d.get("completed_counts", {})


func reset() -> void:
	_last_day = {}
	_done_today = {}
	_completed_counts = {}
