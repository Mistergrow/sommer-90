extends Node
## NPCManager — lädt NPC-Stammdaten aus data/npcs.json und verwaltet den
## Laufzeit-Zustand (Vertrauen). Die 'timeline'-Lebenslinien der NPCs sind
## Teil des Living-Timeline-Systems (World Memory) und werden von späteren
## Phasen ausgewertet.

signal npcs_changed

const AVATAR_CATALOG := preload("res://scripts/gfx/avatar_catalog.gd")
const FIGURE_PAINTER := preload("res://scripts/gfx/figure_paint_32.gd")
const STEFAN_GAMES := preload("res://scripts/games/stefan_game_catalog.gd")
const STEFAN_MOMENTS := preload("res://scripts/data/stefan_moment_catalog.gd")

## Der Wochenplan benutzt bewusst das lesbare Token "home". Die begehbaren
## Zimmer besitzen dagegen eigene Orts-IDs. Diese eine Zuordnung verhindert,
## dass die Karte "zu Hause" meldet, im Zimmer aber kein anklickbarer Freund
## erscheint.
const PERSONAL_HOME_BY_NPC := {
	"npc_stefan": "friend_cellar",
	"npc_sven": "sven_home",
	"npc_mike": "mike_home",
	"npc_alex": "alex_home",
	"npc_daniel": "daniel_home",
	"npc_lisa": "lisa_home",
}

var npcs: Dictionary = {}        # id -> Stammdaten (aus JSON)
var trust: Dictionary = {}       # id -> aktuelles Vertrauen (Laufzeit)
var _name_to_id: Dictionary = {} # normalisierter Anzeigename -> NPC-ID


func _ready() -> void:
	_load_data()


func _load_data() -> void:
	npcs.clear()
	_name_to_id.clear()
	var file := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if file == null:
		push_error("npcs.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("npcs.json ist kein gueltiges Objekt!")
		return
	var data: Dictionary = parsed
	for raw: Variant in data.get("npcs", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = raw
		var id := str(npc.get("id", ""))
		if id == "":
			push_error("NPC ohne ID in npcs.json")
			continue
		npcs[id] = npc
		var name_key := AVATAR_CATALOG.name_key(str(npc.get("name", "")))
		if name_key != "":
			_name_to_id[name_key] = id
		var signature_errors := AVATAR_CATALOG.validate_signature(AVATAR_CATALOG.signature_from_npc(npc))
		if not signature_errors.is_empty():
			push_error("Avatar-Signatur %s: %s" % [id, "; ".join(signature_errors)])


func reset() -> void:
	trust = {}
	for id in npcs:
		trust[id] = int(npcs[id].get("trust", 0))
	npcs_changed.emit()


func get_npc(id: String) -> Dictionary:
	return npcs.get(id, {})


## Lokalisierter Anzeigename fuer UI-Texte. Eigennamen fallen auf die
## Stammdaten zurueck; Rollen wie Papa/Dad koennen gezielt uebersetzt werden.
func localized_name(id: String) -> String:
	var fallback := str(get_npc(id).get("name", "?"))
	return Loc.t("npc.%s.name" % id, fallback)


## Zeit- und Storyvertrag fuer Stammpersonen. Damit wird ein Nachfolger nicht
## schon Jahre vor seiner Einfuehrung in Kontakten/Ortslisten sichtbar und ein
## pensionierter Inhaber nicht weiter als Ladenbesetzung gemeldet.
func is_available(id: String) -> bool:
	var npc := get_npc(id)
	if npc.is_empty():
		return false
	if TimeManager.year < int(npc.get("year_from", 0)) \
			or TimeManager.year > int(npc.get("year_to", 9999)):
		return false
	var required := str(npc.get("requires_flag", ""))
	if not required.is_empty() and not bool(GameManager.flags.get(required, false)):
		return false
	var excluded := str(npc.get("unless_flag", ""))
	if not excluded.is_empty() and bool(GameManager.flags.get(excluded, false)):
		return false
	return true


## Robuste Sprecherauflösung fuer Dialoge. Akzeptiert bereits kanonische IDs,
## Anzeigenamen ohne Beachtung der Grossschreibung sowie das Telefon-Praefix.
func id_for_name(display_name: String) -> String:
	if npcs.has(display_name):
		return display_name
	return str(_name_to_id.get(AVATAR_CATALOG.name_key(display_name), ""))


# ------------------------------------------------------------- Tagesplan

## „Mal sehen, ob jemand da ist" — das Netz ohne Handy (s. Asset-DB Schulhof).
## Freunde haben einen Wochenplan (npcs.json 'schedule'), der ihren Aufenthalt
## am Nachmittag (nach der Schule) je Wochentag bestimmt. Andere Slots: nicht
## treffbar (Schule/zu Hause).
const AFTERNOON_SLOT := 2  # Zeitfenster "Nachmittag" (5-Fenster-Tag, s. LIFE_TIME_BIBLE)
const WEEKDAY_KEYS := ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


func weekday_key() -> String:
	return WEEKDAY_KEYS[TimeManager.weekday()]


## Geplanter Aufenthaltsort eines NPCs am heutigen Nachmittag ("" = kein Plan).
func scheduled_place(npc_id: String) -> String:
	var sched: Dictionary = get_npc(npc_id).get("schedule", {})
	if sched.is_empty():
		return ""
	return str(sched.get(weekday_key(), ""))


## Aufloesung des abstrakten Planwerts "home" auf das echte begehbare Zimmer.
## scheduled_place() bleibt fuer Dialogtexte/Tests abwaertskompatibel und gibt
## weiterhin das rohe Token zurueck.
func scheduled_location(npc_id: String) -> String:
	var forced := forced_location(npc_id)
	if forced != "":
		return forced
	var place := scheduled_place(npc_id)
	if place == "home":
		return str(PERSONAL_HOME_BY_NPC.get(npc_id, "home"))
	return place


## Storykritische Termine und persoenliche Uebergaben schlagen den Wochenplan
## zentral. So kann weder eine Abgabe noch ein Pruefungstermin durch einen
## Wochentag oder die kleine Tages-Unschärfe unerreichbar werden.
func forced_location(npc_id: String) -> String:
	if npc_id == "npc_voss":
		if QuestManager.is_active("q_schulabschluss") \
				and QuestManager.stage("q_schulabschluss") == 1 \
				and TimeManager.slot <= AFTERNOON_SLOT:
			return "schoolyard"
		return ""
	if npc_id == "npc_rocky":
		# Praktische Pruefung und anschliessende Abnahme sind feste Termine.
		# Rockys normale 15-%-Tagesunschaerfe darf diesen Storypfad weder aus
		# dem JobManager noch als sichtbaren Laden-Aktor verschwinden lassen.
		if QuestManager.is_active("q_gesellenpruefung") \
				and QuestManager.stage("q_gesellenpruefung") in [1, 2]:
			return "computer_shop"
		return ""
	if npc_id != "npc_stefan":
		return ""
	if QuestManager.is_active("q_stefan_space"):
		var space_stage := QuestManager.stage("q_stefan_space")
		if space_stage in [1, 2] and DiskManager.has_template("game_space_lemming"):
			return "friend_cellar"
	if QuestManager.is_active("q_stefan_turbo") \
			and QuestManager.stage("q_stefan_turbo") == 3 \
			and DiskManager.has_player_copy_of("turbo_kart_deluxe"):
		return "friend_cellar"
	if not STEFAN_GAMES.active_delivery().is_empty() \
			or not STEFAN_MOMENTS.active_moment().is_empty():
		return "friend_cellar"
	return ""


## Welche NPCs sind gerade (Nachmittag) an diesem Ort? Soziale Verabredungen
## besitzen eine kleine deterministische Tages-Unschärfe. Beschäftigte mit
## `presence_mode = fixed_shift` bleiben dagegen während ihrer geplanten Schicht
## zuverlässig ansprechbar; sonst könnten Laden und Dienstleistung sichtbar offen,
## ihr verantwortlicher NPC aber zufällig verschwunden sein.
func present_at(location_id: String) -> Array:
	var out: Array = []
	# Fest verabredete Storytermine gelten auch vormittags und mittags. Normale
	# Freundesplaene bleiben weiterhin reine Nachmittagstermine.
	for id in npcs:
		if not is_available(id):
			continue
		if forced_location(id) == location_id:
			out.append(id)
	if TimeManager.slot != AFTERNOON_SLOT:
		return out
	for id in npcs:
		if not is_available(id):
			continue
		var forced := forced_location(id)
		if forced != "":
			continue
		if (forced if forced != "" else scheduled_location(id)) != location_id:
			continue
		if forced == "" and _is_elsewhere_today(id):
			continue
		out.append(id)
	return out


func _is_elsewhere_today(id: String) -> bool:
	if str(get_npc(id).get("presence_mode", "social")) != "social":
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) ^ (TimeManager.day_counter * 2654435761)
	return rng.randf() < 0.15


## Wer ist HEUTE an diesem Ort (jeder Slot, nicht nur nachmittags) — für die
## generische Ansprechbarkeit anwesender NPCs. Mit derselben Tages-Unschärfe.
func here_today(location_id: String) -> Array:
	var out: Array = []
	for id in npcs:
		if not is_available(id):
			continue
		var forced := forced_location(id)
		var scheduled := forced if forced != "" else scheduled_location(id)
		# Feste Rollen ohne Wochenplan (Gruber im Laden, Krause am Markt …)
		# gelten an ihrem Stammsitz als anwesend. Die 15-%-Unschärfe gehört nur
		# zu Freunden mit echtem Tagesplan; ein geöffneter Laden verliert nicht
		# zufällig seinen Besitzer und seine Aufträge.
		if scheduled == "" and str(get_npc(id).get("location", "")) == location_id:
			out.append(id)
		elif scheduled == location_id and (forced != "" or not _is_elsewhere_today(id)):
			out.append(id)
	return out


func is_here_now(npc_id: String, location_id: String) -> bool:
	return npc_id in present_now(location_id)


## Reine Nachmittags-Treffpunkte (Schulhof/Wald): dort sind Freunde tagsüber in der
## Schule/unterwegs und erst nachmittags anzutreffen.
const HANGOUT_LOCATIONS := ["schoolyard", "wald"]


## Wer ist JETZT an diesem Ort — ORTS-BEWUSST, damit die KARTE dasselbe zeigt wie der
## Ort selbst: Nachmittags-Treffpunkte nur nachmittags (present_at), alle anderen
## Orte ganztags (here_today, wie die anwesenden NPC-Chips vor Ort).
func present_now(location_id: String) -> Array:
	if location_id in HANGOUT_LOCATIONS:
		return present_at(location_id)
	return here_today(location_id)


## Bester Dialog für einen NPC (aktuell: dialogue_default; Varianten folgen).
func dialogue_for(npc_id: String) -> String:
	return str(get_npc(npc_id).get("dialogue_default", ""))


## Ist der NPC ein „Tipper" (Programmierer/Coder/Sysop) — für das Tipp-Bett.
func is_coder(npc_id: String) -> bool:
	return npc_id in ["npc_daniel", "npc_tobias", "npc_sysop"]


func get_trust(id: String) -> int:
	return int(trust.get(id, 0))


func change_trust(id: String, delta: int) -> void:
	trust[id] = clampi(get_trust(id) + delta, 0, 100)
	npcs_changed.emit()


## Vollstaendige, normalisierte und vom Stammdatensatz entkoppelte Signature-DNA.
func portrait_spec(id: String) -> Dictionary:
	var npc := get_npc(id)
	if npc.is_empty():
		return {}
	return AVATAR_CATALOG.signature_from_npc(npc)


## Ein Frame des permanenten 128er-Renderers. `state` traegt Jahr/Emotion/
## Kleidung; `frame_state` traegt nur Mundpose, Lidframe und Blickrichtung.
func portrait_frame(id: String, state: Dictionary = {}, frame_state: Dictionary = {}) -> ImageTexture:
	var signature := portrait_spec(id)
	var hints := AVATAR_CATALOG.merged_hints(signature, state)
	if not hints.has("year"):
		hints["year"] = TimeManager.year
	return PortraitGen.for_npc(id, hints, AVATAR_CATALOG.canonical_frame(frame_state))


func portrait(id: String, state: Dictionary = {}) -> ImageTexture:
	return portrait_frame(id, state, {})


## Ganze 32x48-Pixel-Figur fuer Figuren, die wirklich im Raum stehen. Sie
## verwendet dieselbe kanonische Gesichts-/Kleidungs-DNA wie das Dialogportraet.
func figure(id: String, state: Dictionary = {}, frame_state: Dictionary = {}) -> ImageTexture:
	var signature := portrait_spec(id)
	var hints := AVATAR_CATALOG.merged_hints(signature, state)
	if not hints.has("year"):
		hints["year"] = TimeManager.year
	return FIGURE_PAINTER.figure(id, hints, AVATAR_CATALOG.canonical_frame(frame_state))


func to_dict() -> Dictionary:
	return {"trust": trust}


func from_dict(d: Dictionary) -> void:
	trust = d.get("trust", {})
	npcs_changed.emit()
