extends Node
## GameManager — Spielzustand, Orte, Quest-Flags, Spielstart.
## Orchestriert die übrigen Systeme; Orte sind Code-Szenen (LocationBase),
## die in den von main.gd registrierten Host eingehängt werden.

signal location_changed(id: String)
signal game_started
signal returned_to_title

const BuildChannel := preload("res://scripts/core/build_channel.gd")

enum State { TITLE, PLAYING }

var state: State = State.TITLE
var flags: Dictionary = {}          # Quest-/Weltflags (Effekt-DSL: "flag")
var current_location_id: String = ""
var location_host: Control = null   # Zimmeransicht-Container (aus main.gd)
var _intro_timer: Timer = null
## Der Zielort wird vor dem Zeitvorschub gesetzt, damit Tageslicht und
## Oeffnungszeiten die Ankunft lesen. Dieser Merker verhindert dabei, dass
## slot_changed den noch laufenden Heimweg als Aufenthalt im Zimmer deutet.
var _travel_clock_active := false


func is_traveling() -> bool:
	return _travel_clock_active


## Story-Director: pro Kalendertag hoechstens ein grosser, questtragender Beat
## (Anruf oder Besuch). Sandbox, Handel und normale Gespräche bleiben frei.
## Der Merker lebt in flags und ist damit automatisch savegame-kompatibel.
func story_beat_available() -> bool:
	return int(flags.get("story_beat_day", -1)) != TimeManager.day_counter


func claim_story_beat(source: String) -> bool:
	if not story_beat_available():
		return false
	flags["story_beat_day"] = TimeManager.day_counter
	flags["story_beat_source"] = source
	return true

## Begehbare Orte (ID -> {name, script, weekdays, slots, hint}). Wird zur
## Laufzeit aus TownManager/town.json abgeleitet — town.json ist die EINZIGE
## Quelle für Namen & Öffnungszeiten (kein Drift). In _ready() befüllt.
var LOCATION_DEFS: Dictionary = {}

## Persönliche Räume mit „echter" Wohnungstür (Türklang beim Betreten). Läden haben
## stattdessen ihre eigene Türglocke (shop_bell) in der jeweiligen Location.
const HOME_LOCATIONS := ["room", "sven_home", "mike_home", "alex_home",
	"daniel_home", "lisa_home"]


func register_location_host(host: Control) -> void:
	location_host = host


# ------------------------------------------------------------- Spielstart

func new_game(slot: int = -1) -> bool:
	var trace_startup := OS.get_environment("DSS_PERF_TRACE") == "1"
	var trace_tick := Time.get_ticks_usec()
	if not SaveManager.on_new_game(slot):
		return false
	flags = {"collection_car_system": true}
	PlayerStats.reset()
	TimeManager.setup_start(TimelineManager.start_year,
		TimelineManager.start_month, TimelineManager.start_day)
	InventoryManager.reset()
	RoomManager.reset()
	DiskManager.reset()
	NPCManager.reset()
	DialogueManager.reset()
	EventManager.reset()
	RumorManager.reset()
	FleaMarketManager.reset()
	DealerManager.reset()
	RaidManager.reset()
	MusicManager.reset()
	MemoryManager.reset()
	SommerGameManager.reset()
	trace_tick = _trace_start_phase(trace_startup, "Grundsysteme zurücksetzen", trace_tick)
	# Neuere Systeme ebenfalls frisch aufsetzen (sonst schleppt ein neues Spiel
	# altes Konto/Quests/Postkarten/Rechnungen mit).
	BBSManager.reset()      # offline, keine besuchten Boards aus altem Durchlauf
	OrderManager.reset()    # keine alten offenen/abholbereiten Bestellungen
	PhoneManager.reset()
	PostcardManager.reset()
	BankManager.reset()
	TaskManager.reset()
	CopyTradeManager.reset()
	SceneReleaseManager.reset()
	JobManager.reset()
	NarrativeManager.reset()
	QuestManager.reset()
	AchievementManager.reset()
	MinigameManager.reset()
	AmigaGameManager.reset()
	DemoManager.reset()
	PhotoManager.reset()
	IntegrityManager.reset()
	PlaytestTelemetry.reset()
	trace_tick = _trace_start_phase(trace_startup, "Spielsysteme zurücksetzen", trace_tick)
	ProgramLibrary.preinstall()  # vorinstallierte Workbench-Basics einrichten
	UIManager.close_all_windows()
	UIManager.reset_computer()   # frisch: Amiga aus, keine Diskette drin, Röhre still
	trace_tick = _trace_start_phase(trace_startup, "Programme und UI vorbereiten", trace_tick)
	state = State.PLAYING
	_enter_location("room")
	trace_tick = _trace_start_phase(trace_startup, "Startzimmer aufbauen", trace_tick)
	QuestManager.evaluate()   # Startaufträge (1990) sofort aktivieren
	AchievementManager.evaluate()
	game_started.emit()
	_trace_start_phase(trace_startup, "Quests und Startsignale", trace_tick)
	UIManager.toast(Loc.t("sys.game_manager.sommerferien_d_s", "Sommerferien %d. %s") % [TimeManager.year, WeatherManager.description()])
	# Die erste Szene: Papa stellt den Karton mit dem gebrauchten Amiga ab — der
	# leere Schreibtisch und das Auspacken sind das Tutorial. Nach dem ersten Boot
	# darf Stefan bereits den Ausblick auf Kapitel 2 geben; der explizite
	# early_after_quest-Vertrag verhindert dabei einen leeren Zwangsschlaf.
	_ensure_intro_timer()
	_intro_timer.start(1.2)
	return true


func _ensure_intro_timer() -> void:
	if _intro_timer != null and is_instance_valid(_intro_timer):
		return
	_intro_timer = Timer.new()
	_intro_timer.name = "IntroDelay"
	_intro_timer.one_shot = true
	_intro_timer.timeout.connect(_show_intro_if_needed)
	add_child(_intro_timer)


func _show_intro_if_needed() -> void:
	if state == State.PLAYING and not bool(flags.get("intro_vater_done", false)):
		DialogueManager.start_dialogue("intro_vater", "npc_vater")


## Opt-in-Messpunkte für den realen Startpfad. Im normalen Spiel entsteht außer
## den billigen Zeitstempeln kein Log-Spam; QA startet mit DSS_PERF_TRACE=1.
func _trace_start_phase(enabled: bool, label: String, previous_usec: int) -> int:
	var now := Time.get_ticks_usec()
	if enabled:
		print("STARTUP_PHASE %s %.3f ms" % [label, float(now - previous_usec) / 1000.0])
	return now


## Zurück ins Hauptmenü (Systemmenü). Speichern übernimmt der Aufrufer.
func return_to_title() -> void:
	state = State.TITLE
	if _intro_timer != null:
		_intro_timer.stop()
	DialogueManager.reset()
	MusicManager.stop()          # keine Zimmer-/Amiga-Musik im Hauptmenü
	UIManager.reset_computer()   # Röhre aus (kein Phantom-Brummen), Strom aus, Modem getrennt
	UIManager.close_all_windows()
	if location_host != null:
		for child in location_host.get_children():
			child.queue_free()
	current_location_id = ""
	returned_to_title.emit()


func _ready() -> void:
	_ensure_intro_timer()
	LOCATION_DEFS = TownManager.live_defs()  # Öffnungszeiten & Namen aus town.json
	TimeManager.day_changed.connect(_on_day_changed)
	TimeManager.year_changed.connect(_on_year_changed)
	TimeManager.slot_changed.connect(_on_slot_changed)
	TimeManager.year_finale_ready.connect(_on_year_finale_ready)


## Der Kalender bleibt am 31.12. stehen. Erst der explizite Abschluss des
## Silvesterbildschirms darf das neue Jahr und den naechsten Sommer committen.
func _on_year_finale_ready(finished_year: int) -> void:
	if state != State.PLAYING or not TimeManager.is_year_end_pending():
		return
	var milestones: Array[String] = []
	for memory: Dictionary in MemoryManager.memories_for_year(finished_year):
		var line := str(memory.get("text", "")).strip_edges()
		if not line.is_empty() and not line in milestones:
			milestones.append(line)
		if milestones.size() >= 3:
			break
	var review := {
		"headline": "SO WAR DEIN JAHR %d" % finished_year,
		"milestones": milestones,
		"consequences": _montage_review_lines(finished_year),
		"footer": "31.12.%d · Ein Kapitel endet. Der naechste Sommer wartet." % finished_year,
	}
	if BuildChannel.ends_after_year(finished_year):
		review["demo_finale"] = true
		review["footer"] = "31.12.1990 · Side A complete · Die Geschichte geht in der Vollversion weiter."
		flags["itch_demo_1990_complete"] = true
		# Der Stand bleibt am letzten Abend 1990 erhalten. Beim Laden erscheint das
		# Finale erneut; ein Vollversions-Save wird wegen des Buildkanals nie beruehrt.
		SaveManager.save_game()
		var demo_screen := UIManager.open_first_year_demo_finale(review)
		var return_callback := Callable(self, "_on_demo_finale_return_to_title")
		if demo_screen != null and demo_screen.has_signal("return_to_title_requested") \
				and not demo_screen.is_connected("return_to_title_requested", return_callback):
			demo_screen.connect("return_to_title_requested", return_callback)
		return
	var screen := UIManager.open_year_transition(finished_year, finished_year + 1, review)
	var callback := Callable(self, "_on_year_transition_finished")
	if screen != null and screen.has_signal("finished") and not screen.is_connected("finished", callback):
		screen.connect("finished", callback)


func _on_demo_finale_return_to_title() -> void:
	return_to_title()


func _on_year_transition_finished(from_year: int, _to_year: int, _skipped: bool) -> void:
	if TimeManager.year != from_year or not TimeManager.is_year_end_pending():
		return
	# Vor year_changed markieren, damit MemoryManager keinen zweiten Rueckblick
	# ueber den neuen Vollbildabschluss legt.
	flags["year_transition_reviewed_%d" % from_year] = true
	TimeManager.complete_year_transition()


func _montage_review_lines(review_year: int) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in flags.get("montage_events_%d" % review_year, []):
		var text := str(entry).strip_edges()
		if not text.is_empty() and not text in out:
			out.append(text)
	return out.slice(0, 3)


func _resume_year_finale_if_needed() -> void:
	if state == State.PLAYING and TimeManager.is_year_end_pending():
		_on_year_finale_ready(TimeManager.year)


## Sobald es Nacht wird, steht die Uhr — der Spieler beendet den Tag AKTIV im
## Bett. Ein einmaliger Hinweis erklärt das, sobald die Nacht beginnt.
func _on_slot_changed(new_slot: int) -> void:
	if state != State.PLAYING:
		return
	if new_slot == TimeManager.NIGHT_SLOT and not bool(flags.get("night_hint_shown_today", false)):
		flags["night_hint_shown_today"] = true
		UIManager.toast(Loc.t("sys.game_manager.es_ist_nacht_uhr_steht_still", "Es ist Nacht — die Uhr steht still. Zeit, schlafen zu gehen (Bett im Zimmer)."))


## Dekaden-Ende (s. docs/LIFE_TIME_BIBLE.md): Das Hauptspiel endet am
## 31.12.1999, 23:59 — ab dem Jahr 2000 beginnt das Freie Spiel. Nichts wird
## weggenommen; der interaktive Statistik-Abspann öffnet anschließend die
## Release-Credits und den optionalen Sammlungs-Highscore.
func _on_year_changed(new_year: int) -> void:
	if state != State.PLAYING:
		return
	# Orte oeffnen/schliessen mit der Aera (LAN-Keller ab 1996, Internetcafe ab 1998).
	LOCATION_DEFS = TownManager.live_defs()
	if new_year >= 2000 and not flags.get("free_play", false):
		flags["free_play"] = true
		UIManager.toast(Loc.t("sys.game_manager.silvester_1999_23_59_jahrzehnt_ist", "Silvester 1999, 23:59 — das Jahrzehnt ist vorbei. FREIES SPIEL beginnt!"))
		UIManager.open_endgame_stats()  # Abspann: Vergleich 1990 ↔ 1999 + Bilanz


# GDD-Gegenkräfte: unter diesen Eltern-Toleranz-Schwellen zieht Papa Konsequenzen.
const PLUG_PULL_TOLERANCE := 25      # „Stecker-gezogen-Event": Verteiler wird abgeschaltet
const ALLOWANCE_MIN_TOLERANCE := 10  # darunter fällt das Sonntags-Taschengeld aus


## Sonntags gibt es Taschengeld — die Wirtschafts-Grundversorgung des MVP.
## Dazu die GDD-Gegenkräfte: bei niedriger Eltern-Toleranz fällt Taschengeld aus,
## und Papa zieht den Stecker (kappt den Mehrfachverteiler — Stromkette!).
## Monatslohn je Lebensphase (Zeit-Bibel: Älterwerden = mehr OPTIONEN):
## Azubi = Lehrlingsgeld, Berufstätiger = Gehalt (jeweils am Monatsersten).
## Geselle ohne festen Job verdient nichts Festes — Anreiz für q_erster_job.
const AZUBI_LOHN := 110
const JOB_GEHALT := 700

func _on_day_changed() -> void:
	if state != State.PLAYING:
		return
	flags["night_hint_shown_today"] = false   # Nacht-Hinweis pro Tag einmal
	var tolerance := int(PlayerStats.eltern_toleranz)
	var phase: String = TimeManager.life_phase()
	if TimeManager.weekday() == 6 and phase == "schueler":
		# Taschengeld gibt's nur für Schüler — wer verdient, kriegt keins mehr.
		if tolerance < ALLOWANCE_MIN_TOLERANCE:
			UIManager.toast(Loc.t("sys.game_manager.papa_schuttelt_den_kopf_taschengeld_erst", "Papa schüttelt den Kopf: »Taschengeld? Erst benimmst du dich wieder.« (Eltern-Toleranz zu niedrig)"))
		else:
			PlayerStats.add_money(10)
			UIManager.toast(Loc.t("sys.game_manager.taschengeld_10_dm_sonntag", "Taschengeld! +10 DM. (Sonntag)"))
	# Zahltag je ÜBERSCHRITTENEM Monatswechsel. Der AAA-Zeitrahmen springt zwischen
	# kuratierten Sommertagen und über den Winter (calendar_jump) — ein "day == 1"
	# wird dabei fast nie getroffen. Deshalb: Monatsdifferenz seit letzter Prüfung
	# zählen und rückwirkend auszahlen (Silvester-Sprung = Winterlohn auf einmal).
	var ym := TimeManager.year * 12 + TimeManager.month
	var last_ym := int(flags.get("last_pay_ym", 0))
	if last_ym <= 0:
		flags["last_pay_ym"] = ym   # Erstlauf: nur verankern, nichts nachzahlen
	elif ym > last_ym:
		var months := ym - last_ym
		flags["last_pay_ym"] = ym
		var wage := AZUBI_LOHN if phase == "azubi" else (JOB_GEHALT if phase == "berufstaetig" else 0)
		if wage > 0:
			PlayerStats.add_money(wage * months)
			var what := "Lehrlingsgeld" if phase == "azubi" else "Gehalt"
			if months == 1:
				UIManager.toast(Loc.t("sys.game_manager.zahltag_s_d_dm", "Zahltag: %s, %d DM.") % [what, wage])
			else:
				UIManager.toast(Loc.t("sys.game_manager.s_fur_d_monate_nachgezahlt_d", "%s für %d Monate nachgezahlt: %d DM. (Der Winter war fleißig.)") % [what, months, wage * months])
	if tolerance < PLUG_PULL_TOLERANCE and UIManager.strip_power:
		UIManager.set_strip_power(false)
		UIManager.toast(Loc.t("sys.game_manager.papa_war_im_zimmer_bei_dem", "Papa war im Zimmer: »Bei DEM Betragen bleibt die Kiste aus!« — der Verteiler ist abgeschaltet."))


# ------------------------------------------------------------- Orte

## Ist ein Ort gerade erreichbar? Rückgabe {ok, reason} — Quelle: town.json.
func location_available(id: String) -> Dictionary:
	return TownManager.available(id)


## Ortswechsel mit Verkehrsmittel (walk/bike/bus/car). Kostet Zeit-Slots und
## ggf. Geld (Bus) je nach Bezirks-Distanz — TownManager rechnet, town.json ist
## die Grundlage. Rückwärtskompatibel: ohne Argumente = Fahrrad, ein Slot.
func goto_location(id: String, costs_time: bool = true, mode: String = "bike") -> void:
	if id == current_location_id:
		PlaytestTelemetry.note_blocked("travel", id, "already_there")
		UIManager.toast(Loc.t("sys.game_manager.da_bist_du_doch_schon", "Da bist du doch schon."))
		return
	var cost: Dictionary = TownManager.travel_preview(current_location_id, id, mode, costs_time)
	if not cost["ok"]:
		PlaytestTelemetry.note_blocked("travel", id, str(cost.get("reason", "unavailable")))
		UIManager.toast(cost["reason"])
		return
	# Sämtliche ablehnbaren Prüfungen laufen VOR der ersten UI-Mutation. So bleibt
	# der Arbeitsplatz bei fehlendem Busticket oder laufender Medienoperation exakt
	# erhalten; erst eine vollständig validierte Reise schließt den Computer.
	var operation_blocker := UIManager.computer_operation_blocker()
	if not operation_blocker.is_empty():
		PlaytestTelemetry.note_blocked("travel", id, "computer_action_in_progress")
		UIManager.toast(operation_blocker)
		return
	var fare := int(cost["dm"])
	if fare > 0 and PlayerStats.geld + 0.005 < float(fare):
		PlaytestTelemetry.note_blocked("travel", id, "insufficient_money")
		UIManager.toast(Loc.t("sys.game_manager.kein_geld_furs_ticket_d_dm", "Kein Geld fürs Ticket (%d DM).") % fare)
		return
	if not UIManager.prepare_location_change():
		PlaytestTelemetry.note_blocked("travel", id, "computer_action_in_progress")
		return
	if fare > 0 and not PlayerStats.spend_money(fare):
		# Single-threaded nach erfolgreicher Vorprüfung unerreichbar; schützt gegen
		# spätere Seiteneffekte in prepare_location_change().
		push_error("Reisepreis änderte sich während der bestätigten Reise: %d DM" % fare)
		return
	PlaytestTelemetry.note_travel(current_location_id, id, mode,
		int(cost.get("travel_slots", 0)) if costs_time else 0, int(cost.get("dm", 0)),
		int(cost.get("travel_minutes", 0)) if costs_time else 0,
		int(cost.get("wait_minutes", 0)) if costs_time else 0)
	# Erst die Reisezeit verbuchen, dann den Zielort bauen. Standortvarianten,
	# Tageslicht und NPC-Praesenz lesen damit den echten ANKUNFTS-Slot statt
	# noch den alten Abfahrts-Slot (z. B. voller/leerer Schulhof).
	if costs_time and int(cost.get("minutes", 0)) > 0:
		# Slot-/Tag-Signale muessen bereits den Zielkontext sehen. Sonst koennen
		# beim Verlassen des Zimmers noch Telefon/Haustuer-Ereignisse ausloesen.
		_travel_clock_active = true
		current_location_id = id
		TimeManager.advance_minutes(int(cost["minutes"]))
	_enter_location(id)
	_travel_clock_active = false
	# Priorisierte ortsgebundene Quest-Höhepunkte öffnen bei der Ankunft
	# deterministisch. Das ist besonders für Nachtmissionen nötig: Dort steht die
	# Uhr bereits und es wird absichtlich kein weiteres slot_changed emittiert.
	EventManager.trigger_priority_arrival_event(id)
	# Ankunfts-Klang: du bist gelaufen (Schritte). In persönliche Räume kommt eine
	# Tür dazu; Läden haben ihre eigene Türglocke (shop_bell) in der Location.
	AudioManager.play("footsteps", 0.08)
	if id in HOME_LOCATIONS:
		AudioManager.play("door", 0.0)
	UIManager.toast(Loc.t("sys.game_manager.du_bist_jetzt_hier_s", "Du bist jetzt hier: %s") % location_name(id))


func _enter_location(id: String) -> void:
	if location_host == null:
		return
	if not LOCATION_DEFS.has(id):
		UIManager.toast(Loc.t("sys.game_manager.dorthin_kommst_du_noch_nicht_weg", "Dorthin kommst du noch nicht — der Weg zu %s ist dir noch nicht bekannt.") % location_name(id))
		return
	var fade := _ensure_fade_overlay()
	# Der Tausch bleibt SYNCHRON (Node sofort da wie bisher). Das schwarze
	# Overlay deckt den Tausch-Frame ab und blendet danach auf → sauberer
	# Dip-to-Black-Übergang beim Ortswechsel, ohne Verhalten zu ändern.
	for child in location_host.get_children():
		if child != fade:
			child.queue_free()
	var def: Dictionary = LOCATION_DEFS[id]
	var location: Control = def["script"].new()
	location.set("location_id", id)   # LocationBase kennt so seinen Ort (Anwesende)
	location_host.add_child(location)
	current_location_id = id
	MusicManager.enter_location(id)  # Standort-Ambient (oder Stille im Zimmer)
	location_changed.emit(id)
	_play_location_fade(fade)


var _fade_overlay: ColorRect = null
var _fade_tween: Tween = null


## Schwarzes Übergangs-Overlay im location_host (einmalig, bleibt erhalten).
func _ensure_fade_overlay() -> ColorRect:
	if _fade_overlay != null and is_instance_valid(_fade_overlay):
		return _fade_overlay
	var rect := ColorRect.new()
	rect.name = "LocationFade"
	rect.color = Color(0, 0, 0, 0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 100
	location_host.add_child(rect)
	_fade_overlay = rect
	return rect


## Deckt den Tausch mit Schwarz ab und blendet weich auf.
func _play_location_fade(fade: ColorRect) -> void:
	location_host.move_child(fade, location_host.get_child_count() - 1)  # ganz oben halten
	fade.color.a = 1.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "color:a", 0.0, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Anzeigename — deckt ALLE Stadt-Orte ab (auch geplante), Quelle: town.json.
func location_name(id: String) -> String:
	return TownManager.display_name(id)


## Text für das "NÄCHSTES EVENT"-Panel der Top-Bar: der nächste feste Termin.
## Ist das naechste Ereignis noch heute? Die Leiste faerbte das frueher ein,
## indem sie im ANZEIGETEXT nach dem Wort "heute" suchte — was jede Uebersetzung
## lautlos gebrochen haette. Die Dringlichkeit gehoert zum Zustand, nicht zum Text.
func next_event_is_today() -> bool:
	return (5 - TimeManager.weekday() + 7) % 7 == 0 and TimeManager.slot == 0


func next_event_text() -> String:
	var wd := TimeManager.weekday()
	var days_to_flea := (5 - wd + 7) % 7   # Samstag
	var days_to_money := (6 - wd + 7) % 7  # Sonntag
	if days_to_flea == 0 and TimeManager.slot == 0:
		return "Flohmarkt\nheute Morgen!"
	if days_to_flea == 0:
		days_to_flea = 7
	if days_to_money == 0:
		days_to_money = 7
	if days_to_flea <= days_to_money:
		return "Flohmarkt\nSa (%d Tg.)" % days_to_flea
	return "Taschengeld\nSo (%d Tg.)" % days_to_money


func to_dict() -> Dictionary:
	return {"flags": flags, "location": current_location_id}


func from_dict(d: Dictionary) -> void:
	if _intro_timer != null:
		_intro_timer.stop()
	flags = d.get("flags", {})
	# Alte Fassungen verliehen die Clubmitgliedschaft bereits beim blossen
	# Betreten des Vereinsheims. Die Aufnahmequest ist die einzige Autoritaet.
	if bool(flags.get("club_member", false)) and not QuestManager.is_done("q_club_member"):
		flags.erase("club_member")
	# Queststatus ist bei Save-Versionen stabiler als die historisch gewachsenen
	# redundanten Meilenstein-Flags. Fehlende positive Flags werden daraus
	# rekonstruiert, bevor Telefon, Besuche und Folgequests ihre Gates auswerten.
	QuestManager.reconcile_progress_flags()
	# Migration fuer alte Spielstaende: BankManager wurde vor den globalen Flags
	# geladen und kann bestehende Giro-/Kartenfortschritte jetzt nachtragen.
	BankManager.sync_progress_flags()
	state = State.PLAYING
	LOCATION_DEFS = TownManager.live_defs()   # aera-korrekt (Zeit ist schon geladen)
	UIManager.close_all_windows()
	var restored_location := str(d.get("location", "room"))
	if not LOCATION_DEFS.has(restored_location):
		restored_location = "room"
	if restored_location == "computer_club" and not bool(TownManager.story_access(restored_location)["ok"]):
		restored_location = "room"
	_enter_location(restored_location)
	QuestManager.evaluate()   # Auftragslage nach dem Laden neu bewerten
	AchievementManager.evaluate()
	game_started.emit()
	_resume_year_finale_if_needed.call_deferred()
