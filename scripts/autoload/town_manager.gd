extends Node
## TownManager — die Stadt als Single Source of Truth (data/town.json).
##
## Öffnungszeiten, Bezirke, Verkehr und der Straßen-Graph leben AUSSCHLIESSLICH
## hier bzw. in town.json. GameManager baut seine LOCATION_DEFS daraus; so kann
## nichts mehr driften. Das einzige Code↔Daten-Band ist SCRIPTS: welche
## Orts-ID welche Location-Szene rendert (JSON kann keine Skripte referenzieren).
## Orte ohne Skript sind "geplant"/"künftig" — auf der Karte sichtbar, aber noch
## nicht begehbar.

const TOWN_PATH := "res://data/town.json"

## Das einzige, was in Code stehen MUSS: ID -> Location-Skript. Jeder Eintrag
## hier braucht in town.json einen Ort mit status "live" (und umgekehrt) —
## der Drift-Check erzwingt das.
const SCRIPTS := {
	"room": preload("res://scripts/locations/room_location.gd"),
	"friend_cellar": preload("res://scripts/locations/friend_location.gd"),
	"computer_shop": preload("res://scripts/locations/shop_location.gd"),
	"flea_market": preload("res://scripts/locations/flea_location.gd"),
	"schoolyard": preload("res://scripts/locations/schoolyard_location.gd"),
	"computer_club": preload("res://scripts/locations/club_location.gd"),
	"postamt": preload("res://scripts/locations/postamt_location.gd"),
	"stadtbank": preload("res://scripts/locations/stadtbank_location.gd"),
	"musikladen": preload("res://scripts/locations/musikladen_location.gd"),
	"musikladen_computer_music": preload("res://scripts/locations/musikladen_computer_music_location.gd"),
	"musikladen_keller": preload("res://scripts/locations/musikladen_keller_location.gd"),
	"kiosk": preload("res://scripts/locations/kiosk_location.gd"),
	"imbiss": preload("res://scripts/locations/imbiss_location.gd"),
	"wald": preload("res://scripts/locations/wald_location.gd"),
	"dealer_clearing": preload("res://scripts/locations/dealer_clearing_location.gd"),
	"sven_home": preload("res://scripts/locations/sven_home_location.gd"),
	"mike_home": preload("res://scripts/locations/mike_home_location.gd"),
	"alex_home": preload("res://scripts/locations/alex_home_location.gd"),
	"daniel_home": preload("res://scripts/locations/daniel_home_location.gd"),
	"lisa_home": preload("res://scripts/locations/lisa_home_location.gd"),
	"lan_keller": preload("res://scripts/locations/lan_keller_location.gd"),
	"internetcafe": preload("res://scripts/locations/internetcafe_location.gd"),
	"retro_museum": preload("res://scripts/locations/retro_museum_location.gd"),
}

var _town: Dictionary = {}
var _locs: Dictionary = {}
var _districts: Dictionary = {}
var _dist_cache: Dictionary = {}   # "a|b" → Bezirks-Distanz; roads sind statisch, _load() leert.


func _ready() -> void:
	_load()
	_check_drift()


func _load() -> void:
	if not FileAccess.file_exists(TOWN_PATH):
		push_error("TownManager: %s fehlt." % TOWN_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TOWN_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TownManager: town.json ist kein gültiges JSON-Objekt.")
		return
	_town = parsed
	_locs = _town.get("locations", {})
	_districts = _town.get("districts", {})
	_dist_cache.clear()
	# JSON liefert Zahlen als float — weekdays/slots zu int normalisieren, sonst
	# schlägt "weekday() in weekdays" fehl (5 in [5.0] == false in GDScript).
	for id: String in _locs:
		var l: Dictionary = _locs[id]
		for key in ["weekdays", "slots"]:
			if l.has(key):
				l[key] = (l[key] as Array).map(func(v: Variant) -> int: return int(v))


## Startup-Wächter gegen Drift: live-Orte in town.json ⟺ SCRIPTS.
func _check_drift() -> void:
	for id: String in SCRIPTS:
		if not _locs.has(id):
			push_warning("TownManager-Drift: Skript '%s' hat keinen Ort in town.json." % id)
		elif str(_locs[id].get("status", "")) != "live":
			push_warning("TownManager-Drift: '%s' hat ein Skript, ist in town.json aber nicht 'live'." % id)
	for id: String in _locs:
		if str(_locs[id].get("status", "")) == "live" and not SCRIPTS.has(id):
			push_warning("TownManager-Drift: Ort '%s' ist 'live', hat aber kein Skript in SCRIPTS." % id)
		var dist: String = str(_locs[id].get("district", ""))
		if dist != "" and not _districts.has(dist):
			push_warning("TownManager-Drift: Ort '%s' verweist auf unbekannten Bezirk '%s'." % [id, dist])


# ----------------------------------------------------------------- Abfragen

func has_location(id: String) -> bool:
	return _locs.has(id)


func is_live(id: String) -> bool:
	return SCRIPTS.has(id) and str(_locs.get(id, {}).get("status", "")) == "live" and _year_ok(id)


## Liegt das aktuelle Jahr im Öffnungsfenster des Orts? (Orte OHNE year_available/
## year_obsolete sind immer offen; damit „öffnen/schließen" Orte über die Dekade:
## LAN-Keller ab 1996, Internetcafé ab 1998 …)
func _year_ok(id: String) -> bool:
	return _year_ok_at(id, TimeManager.year)


func _year_ok_at(id: String, y: int) -> bool:
	var l: Dictionary = _locs.get(id, {})
	if l.has("year_available") and y < int(l["year_available"]):
		return false
	if l.has("year_obsolete") and y > int(l["year_obsolete"]):
		return false
	return true


## Soll der Ort JETZT auf der Karte auftauchen? Jahr-gebundene Orte erscheinen
## erst in ihrem Jahr (und verschwinden danach) — so „öffnet" die Stadt sichtbar.
func map_visible(id: String) -> bool:
	if not _locs.has(id):
		return false
	var l: Dictionary = _locs[id]
	if bool(l.get("map_hidden", false)):
		return false
	if l.has("year_available") or l.has("year_obsolete"):
		return _year_ok(id)
	return true


func location(id: String) -> Dictionary:
	return _locs.get(id, {})


func display_name(id: String) -> String:
	var fallback := str(_locs.get(id, {}).get("name", id))
	return Loc.t("town.location.%s.name" % id, fallback)


## Spielerlesbarer Kurztext fuer Karte/Tooltip. Wie beim Ortsnamen bleibt die
## JSON-Zeichenkette nur ein deutscher Fallback; sichtbar ist immer die aktive
## Sprache. Damit ziehen Kartenfenster keine fertig gerenderten Daten aus
## town.json in einen spaeter umgeschalteten Sprachzustand.
func display_hint(id: String) -> String:
	var fallback := str(_locs.get(id, {}).get("hint", ""))
	if fallback.is_empty():
		return ""
	return Loc.t("town.location.%s.hint" % id, fallback)


func district_of(id: String) -> String:
	return str(_locs.get(id, {}).get("district", ""))


func district_name(dist_id: String) -> String:
	var fallback := str(_districts.get(dist_id, {}).get("name", dist_id))
	return Loc.t("town.district.%s.name" % dist_id, fallback)


func district_color(dist_id: String) -> Color:
	return Color.from_string(str(_districts.get(dist_id, {}).get("color", "#888888")), Color(0.5, 0.5, 0.5))


func location_ids() -> Array:
	return _locs.keys()


func live_ids() -> Array:
	return _locs.keys().filter(func(id: String) -> bool: return is_live(id))


func districts() -> Dictionary:
	return _districts


func locations() -> Dictionary:
	return _locs


func transport() -> Dictionary:
	return _town.get("transport", {})


func data_grid() -> Dictionary:
	return _town.get("meta", {}).get("grid", {"cols": 10, "rows": 8})


## Pfad der Karten-Grafik (Vogelperspektive). Kann fehlen (Asset noch nicht da).
func map_art_path() -> String:
	return str(_town.get("meta", {}).get("map_art_path", ""))


## Pixelgenaue Pin-Position eines Orts als Anteil 0..1 der Karten-Grafik, oder
## Vector2(-1,-1) wenn (noch) nicht im Map-Editor gesetzt.
func map_pos(id: String) -> Vector2:
	var loc: Dictionary = location(id)
	var p: Variant = loc.get("map_pos", null)
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2(-1, -1)


func has_map_pos(id: String) -> bool:
	return map_pos(id).x >= 0.0


# ------------------------------------------------------ Wegpunkt-Netz / Routen
## Wegpunkte (Straßenknoten) als Array[Vector2] (Anteile 0..1) — gesetzt im Map-Editor.
func waypoints() -> Array:
	var out: Array = []
	for w: Variant in _town.get("meta", {}).get("waypoints", []):
		if typeof(w) == TYPE_ARRAY and (w as Array).size() >= 2:
			out.append(Vector2(float(w[0]), float(w[1])))
	return out


## Kanten als Array[[i, j, layer]] — layer ∈ all|foot|bike|bus (Alt-Format [i,j] = all).
func edges() -> Array:
	var out: Array = []
	for e: Variant in _town.get("meta", {}).get("edges", []):
		if typeof(e) == TYPE_ARRAY and (e as Array).size() >= 2:
			out.append([int(e[0]), int(e[1]), str(e[2]) if (e as Array).size() >= 3 else "all"])
	return out


## Bushaltestellen als Array[int] (Indizes in waypoints()).
func bus_stops() -> Array:
	var out: Array = []
	for s: Variant in _town.get("meta", {}).get("stops", []):
		out.append(int(s))
	return out


## Verkehrsmittel → gültige Wegpunkt-Ebenen. "all" gilt immer (geteilte Wege);
## der Bus nutzt BEIDE Linien (bus1+bus2), das Auto fährt auf denselben Straßen.
func _mode_layers(mode: String) -> Array:
	match mode:
		"walk": return ["all", "foot"]
		"bike": return ["all", "bike", "foot"]   # Rad nutzt Fußwege + eigene Abkürzungen
		"bus": return ["all", "bus1", "bus2"]
		"car": return ["all", "bus1", "bus2"]
	return ["all", "bike", "foot"]


## Nächster Wegpunkt zu p. allowed (optional): nur diese Indizes zulassen
## (für den Bus: nur Haltestellen).
func _nearest_wp(wps: Array, p: Vector2, allowed: Array = []) -> int:
	var best := -1
	var bd := INF
	var pool: Array = allowed if not allowed.is_empty() else range(wps.size())
	for i: int in pool:
		if i < 0 or i >= wps.size():
			continue
		var d: float = (wps[i] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d; best = i
	return best


## Kanten, die für ein Verkehrsmittel gelten (all + Modus-Ebenen). So teilen sich
## die Ebenen ein Netz, können aber eigene Wege haben (Fußweg ≠ Straße ≠ Buslinie).
func edges_for(mode: String) -> Array:
	var lays := _mode_layers(mode)
	var out: Array = []
	for e: Array in edges():
		if e[2] in lays:
			out.append(e)
	return out


## Geordnete Punktfolge (Array[Vector2], 0..1) einer Buslinie/Ebene — für die
## fahrenden Busse: von einem Endpunkt die Kette entlang bis zum anderen Ende.
## (Erwartet einen einfachen Linienzug; verzweigt sich die Ebene, wird ein Ast
## abgelaufen.) Leer, wenn die Ebene keine Kanten hat.
func line_waypoints(layer: String) -> Array:
	var wps := waypoints()
	var adj: Dictionary = {}
	for e: Array in edges():
		if e[2] != layer:
			continue
		adj.get_or_add(e[0], []).append(e[1])
		adj.get_or_add(e[1], []).append(e[0])
	if adj.is_empty():
		return []
	var start := -1                                    # bevorzugt ein Endpunkt (Grad 1)
	for k: int in adj:
		if (adj[k] as Array).size() == 1:
			start = k; break
	if start == -1:
		start = (adj.keys() as Array).min()
	var order: Array = [start]
	var seen: Dictionary = {start: true}
	var cur := start
	while true:
		var nxt := -1
		for v: int in adj[cur]:
			if not seen.has(v):
				nxt = v; break
		if nxt == -1:
			break
		seen[nxt] = true
		order.append(nxt)
		cur = nxt
	var pts: Array = []
	for i: int in order:
		if i < wps.size():
			pts.append(wps[i])
	return pts


## Route zwischen zwei Orten als Polylinie (Array[Vector2], Anteile 0..1) für die
## Reise-Animation, je Verkehrsmittel unterschiedlich: Start-Ort → nächster
## (erlaubter) Wegpunkt → kürzester Pfad über das Modus-Netz → Ziel-Ort. Der Bus
## fährt von Haltestelle zu Haltestelle. Ohne Netz: direkte Linie.
func route_points(from_id: String, to_id: String, mode: String = "bike") -> Array:
	var a := map_pos(from_id)
	var b := map_pos(to_id)
	if a.x < 0.0: a = _grid_pos(from_id)
	if b.x < 0.0: b = _grid_pos(to_id)
	var wps := waypoints()
	if wps.size() < 2:
		return [a, b]
	var es := edges_for(mode)
	if es.is_empty():
		return [a, b]
	# Nur auf Knoten schnappen, die AUCH eine Kante dieses Verkehrsmittels haben —
	# sonst landet man auf einem reinen Bus-Knoten und kommt zu Fuß nicht weiter.
	# Der Bus steigt zusätzlich nur an Haltestellen zu/ab.
	var in_net: Dictionary = {}
	for e: Array in es:
		in_net[e[0]] = true; in_net[e[1]] = true
	var entry: Array = bus_stops() if mode == "bus" else in_net.keys()
	var sa := _nearest_wp(wps, a, entry)
	var sb := _nearest_wp(wps, b, entry)
	if sa < 0 or sb < 0:
		return [a, b]
	var idx_path := _dijkstra(wps, es, sa, sb)
	if idx_path.is_empty():
		return [a, b]
	var pts: Array = [a]
	for i: int in idx_path:
		pts.append(wps[i])
	pts.append(b)
	return pts


func _grid_pos(id: String) -> Vector2:
	var g := data_grid()
	var p: Array = location(id).get("pos", [5, 4])
	return Vector2((float(p[0]) + 0.5) / float(g.get("cols", 10)), (float(p[1]) + 0.5) / float(g.get("rows", 8)))


## Kürzester Pfad (Indizes) im Wegpunkt-Graph von a nach b, Kantengewicht = Distanz.
func _dijkstra(wps: Array, es: Array, a: int, b: int) -> Array:
	var adj: Dictionary = {}
	for e: Array in es:
		adj.get_or_add(e[0], []).append(e[1])
		adj.get_or_add(e[1], []).append(e[0])
	var dist: Dictionary = {a: 0.0}
	var prev: Dictionary = {}
	var open: Array = [a]
	while not open.is_empty():
		# Knoten mit kleinster Distanz herausnehmen
		var u := -1
		var ud := INF
		for k: int in open:
			if float(dist[k]) < ud:
				ud = float(dist[k]); u = k
		open.erase(u)
		if u == b:
			break
		for v: int in adj.get(u, []):
			var nd: float = ud + (wps[u] as Vector2).distance_to(wps[v])
			if nd < float(dist.get(v, INF)):
				dist[v] = nd; prev[v] = u
				if not open.has(v):
					open.append(v)
	if not prev.has(b) and a != b:
		return []
	var path: Array = [b]
	var cur := b
	while cur != a and prev.has(cur):
		cur = prev[cur]; path.push_front(cur)
	return path


## Merge aus town.json + SCRIPTS — genau das, was GameManager als LOCATION_DEFS
## braucht (nur begehbare Orte).
func live_defs() -> Dictionary:
	var out: Dictionary = {}
	for id: String in live_ids():
		var l: Dictionary = _locs[id]
		var def: Dictionary = {"name": l.get("name", id), "script": SCRIPTS[id]}
		if l.has("weekdays"):
			def["weekdays"] = l["weekdays"]
		if l.has("slots"):
			def["slots"] = l["slots"]
		if l.has("hint"):
			def["hint"] = l["hint"]
		out[id] = def
	return out


## Ist der Ort JETZT erreichbar? {ok, reason}. Nicht-live-Orte sind sichtbar,
## aber (noch) nicht betretbar.
func available(id: String) -> Dictionary:
	return _available_at(id, TimeManager.year, TimeManager.weekday(), TimeManager.slot)


## Erreichbarkeit nach einer Reise, ohne den Kalender oder Signale anzufassen.
func available_after(id: String, slot_steps: int) -> Dictionary:
	var arrival: Dictionary = TimeManager.preview_after_slots(slot_steps)
	return _available_at(id, int(arrival["year"]), int(arrival["weekday"]), int(arrival["slot"]))


func available_after_minutes(id: String, minutes: int) -> Dictionary:
	var arrival: Dictionary = TimeManager.preview_after_minutes(minutes)
	return _available_at(id, int(arrival["year"]), int(arrival["weekday"]), int(arrival["slot"]))


## Verbindliche Reise-Vorschau fuer Karte UND Ortswechsel. Ein Ziel wird bei
## zeitkostender Reise ausschliesslich fuer den Ankunftszeitpunkt bewertet. So
## darf ein morgens noch geschlossener Laden angefahren werden, wenn er bei der
## Ankunft oeffnet, waehrend eine Fahrt vor Ladenschluss sauber blockiert wird.
## Rueckgabe: {ok, minutes, travel_minutes, wait_minutes, slots, dm, reason}.
func travel_preview(from_id: String, to_id: String, mode: String, costs_time: bool = true) -> Dictionary:
	if not costs_time:
		var now := available(to_id)
		return {"ok": bool(now["ok"]), "minutes": 0, "travel_minutes": 0,
			"wait_minutes": 0, "slots": 0, "travel_slots": 0, "dm": 0,
			"reason": str(now["reason"])}
	var cost := travel_cost(from_id, to_id, mode)
	if not bool(cost["ok"]):
		return cost
	var travel_minutes := int(cost.get("minutes", 0))
	var remaining_minutes: int = TimeManager.minutes_left()
	var night_story_trip: bool = TimeManager.is_night() and _is_night_story_destination(to_id)
	# Nachts bleibt die Uhr absichtlich stehen. Ohne dieses Gate konnte man
	# deshalb beliebig oft weiterreisen, obwohl kein einziges Zeitfenster mehr
	# verging. Der Heimweg sowie ein ausdrücklich laufender Nachtauftrag bleiben
	# als sichere, eng begrenzte Ausnahmen moeglich.
	if TimeManager.is_night() and to_id != "room" and not night_story_trip:
		return {"ok": false, "minutes": travel_minutes, "travel_minutes": travel_minutes,
			"wait_minutes": 0, "slots": 0, "travel_slots": 0, "dm": int(cost["dm"]),
			"reason": Loc.t("sys.town_manager.es_ist_nacht_jetzt_geht_es", "Es ist Nacht. Jetzt geht es nur noch nach Hause und ins Bett.")}
	if travel_minutes > remaining_minutes and to_id != "room" and not night_story_trip:
		return {"ok": false, "minutes": travel_minutes, "travel_minutes": travel_minutes,
			"wait_minutes": 0, "slots": TimeManager.slots_crossed_after_minutes(travel_minutes),
			"travel_slots": TimeManager.slots_crossed_after_minutes(travel_minutes), "dm": int(cost["dm"]),
			"reason": Loc.t("sys.town_manager.fur_diese_strecke_ist_es_heute", "Für diese Strecke ist es heute zu spät. Fahr erst nach Hause.")}
	# Ein spaeter Heimweg verbraucht exakt die noch vorhandene Tageszeit. Danach
	# darf ein frueh erreichter Termin bis zum naechsten erlaubten Fenster warten;
	# diese Minuten sind Wartezeit und werden nicht als Reisezeit verbucht.
	var effective_travel := mini(travel_minutes, remaining_minutes)
	var wait_minutes := _wait_until_open_minutes(to_id, effective_travel)
	var total_minutes := effective_travel + wait_minutes
	if total_minutes > remaining_minutes and to_id != "room" and not night_story_trip:
		return {"ok": false, "minutes": total_minutes, "travel_minutes": effective_travel,
			"wait_minutes": wait_minutes, "slots": TimeManager.slots_crossed_after_minutes(total_minutes),
			"travel_slots": TimeManager.slots_crossed_after_minutes(effective_travel),
			"dm": int(cost["dm"]), "reason": Loc.t("sys.town_manager.on_arrival_too_late",
			"Der Termin wäre erst nach dem heutigen Tagesende erreichbar.")}
	var arrival := available_after_minutes(to_id, total_minutes)
	if not bool(arrival["ok"]):
		return {"ok": false, "minutes": total_minutes, "travel_minutes": effective_travel,
			"wait_minutes": wait_minutes, "slots": TimeManager.slots_crossed_after_minutes(total_minutes),
			"travel_slots": TimeManager.slots_crossed_after_minutes(effective_travel), "dm": int(cost["dm"]),
			"reason": Loc.t("sys.town_manager.on_arrival", "Bei deiner Ankunft: %s") % str(arrival["reason"])}
	return {"ok": true, "minutes": total_minutes, "travel_minutes": effective_travel,
		"wait_minutes": wait_minutes, "slots": TimeManager.slots_crossed_after_minutes(total_minutes),
		"travel_slots": TimeManager.slots_crossed_after_minutes(effective_travel),
		"dm": int(cost["dm"]), "reason": "", "night_return": TimeManager.is_night(),
		"night_story_trip": night_story_trip}


## Wenn nur das Zeitfenster den Ort sperrt, darf eine bewusst fruehe Anreise bis
## zum naechsten Oeffnungsfenster warten. Wochentage, Story-Gates und Jahre werden
## nicht umgangen; fuer sie bleibt die normale Fehlermeldung bestehen.
func _wait_until_open_minutes(id: String, travel_minutes: int) -> int:
	if not _locs.has(id):
		return 0
	var l: Dictionary = _locs[id]
	if not l.has("slots"):
		return 0
	var arrival: Dictionary = TimeManager.preview_after_minutes(travel_minutes)
	var at_year := int(arrival.get("year", TimeManager.year))
	var at_weekday := int(arrival.get("weekday", TimeManager.weekday()))
	if not _year_ok_at(id, at_year) or (l.has("weekdays") and at_weekday not in l["weekdays"]):
		return 0
	if not bool(story_access(id).get("ok", false)):
		return 0
	var arrival_minute := int(arrival.get("minute", TimeManager.minute_of_day))
	for raw_slot: Variant in l.get("slots", []):
		var opening: int = TimeManager.TimeClock.slot_start(int(raw_slot))
		if opening >= arrival_minute:
			return opening - arrival_minute
	return 0


## Nachtaufträge dürfen die allgemeine „nur noch heim“-Grenze ausschließlich
## für ihr konkretes Ziel öffnen. So bleibt die Uhr nicht als kostenloses
## Reisenetz missbrauchbar und eine alte/erledigte Quest gewährt keinen Zugang.
func _is_night_story_destination(to_id: String) -> bool:
	return to_id == "mike_home" \
		and QuestManager.is_active("q_lan_nacht") \
		and QuestManager.stage("q_lan_nacht") == 1 \
		and QuestManager.action_count("q_lan_nacht", "make_copy") >= 1


## Reine Story-Sperre eines Orts, getrennt von Wochentag und Oeffnungszeit.
## Damit koennen Karte, Save-Migration und Laufzeitzugriff dieselbe Wahrheit
## verwenden. Eine erledigte Quest behaelt den Ort dauerhaft offen.
func story_access(id: String) -> Dictionary:
	if not _locs.has(id):
		return {"ok": false, "reason": Loc.t("sys.town_manager.unknown_location", "Unbekannter Ort.")}
	var location_def: Dictionary = _locs[id]
	var quest_id := str(location_def.get("requires_quest_access", ""))
	if quest_id != "" and not QuestManager.is_active(quest_id) and not QuestManager.is_done(quest_id):
		return {"ok": false, "reason": str(location_def.get("locked_hint",
			Loc.t("sys.town_manager.location_not_unlocked", "Diesen Ort hast du noch nicht freigeschaltet.")))}
	return {"ok": true, "reason": ""}


func _available_at(id: String, at_year: int, at_weekday: int, at_slot: int) -> Dictionary:
	if not _locs.has(id):
		return {"ok": false, "reason": Loc.t("sys.town_manager.unknown_location", "Unbekannter Ort.")}
	if not SCRIPTS.has(id) or str(_locs[id].get("status", "")) != "live" or not _year_ok_at(id, at_year):
		var status: String = str(_locs[id].get("status", "planned"))
		return {"ok": false, "reason": Loc.t("sys.town_manager.noch_nicht_auf_deinem_stadtplan_verzeichnet", "Noch nicht auf deinem Stadtplan verzeichnet.") if status == "planned"
			else Loc.t("sys.town_manager.available_later", "Wird in einem späteren Kalenderabschnitt zugänglich.")}
	var story_gate := story_access(id)
	if not bool(story_gate["ok"]):
		return story_gate
	var l: Dictionary = _locs[id]
	if l.has("weekdays") and not at_weekday in l["weekdays"]:
		return {"ok": false, "reason": Loc.t("sys.town_manager.closed_today", "Heute geschlossen (%s).") % l.get("hint", "")}
	if l.has("slots") and not at_slot in l["slots"]:
		return {"ok": false, "reason": Loc.t("sys.town_manager.jetzt_nicht_offen_s", "Jetzt nicht offen (%s).") % l.get("hint", "")}
	return {"ok": true, "reason": ""}


# ------------------------------------------------------------- Verkehr / Reise

## Ist ein Verkehrsmittel freigeschaltet? {ok, reason}.
## walk/bike/bus ab Start; car (Führerschein) erst später — Living Timeline.
func mode_unlocked(mode: String) -> Dictionary:
	match mode:
		"walk", "bike", "bus":
			return {"ok": true, "reason": ""}
		"car":
			# Neue Durchläufe trennen Führerschein und eigenes Auto. Alte Saves ohne
			# collection_car_system behalten ihre bisherige Freischaltung.
			var licensed := bool(GameManager.flags.get("has_license", false))
			var legacy_owned := licensed and not GameManager.flags.has("collection_car_system")
			if licensed and (bool(GameManager.flags.get("owns_car", false)) or legacy_owned):
				return {"ok": true, "reason": ""}
			if licensed:
				return {"ok": false, "reason": Loc.t("sys.town_manager.fuhrerschein_geschafft_jetzt_fehlt_eigene_auto", "Führerschein geschafft — jetzt fehlt das eigene Auto. Die Sammlervitrine zeigt einen Finanzierungsplan.")}
			if TimeManager.year >= 1996:
				return {"ok": false, "reason": Loc.t("sys.town_manager.ohne_fuhrerschein_kein_auto_mike_weiss", "Ohne Führerschein kein Auto — Mike weiß, wo man den Lappen macht.")}
			return {"ok": false, "reason": Loc.t("sys.town_manager.fuhrerschein_hast_du_noch_nicht_kommt", "Führerschein hast du noch nicht (kommt später).")}
	return {"ok": false, "reason": Loc.t("sys.town_manager.unknown_transport", "Unbekanntes Verkehrsmittel.")}


## Reisekosten von A nach B mit einem Verkehrsmittel.
## {ok, minutes, slots, dm, reason}. Grundlage: Bezirks-Distanz im Straßen-Graph.
## `slots` bleibt nur als alter Adapter bestehen; die verbindliche Vorschau
## berechnet echte Fensteruebertritte relativ zur aktuellen Uhrzeit.
func travel_cost(from_id: String, to_id: String, mode: String) -> Dictionary:
	var unlock := mode_unlocked(mode)
	if not unlock["ok"]:
		return {"ok": false, "slots": 0, "dm": 0, "reason": unlock["reason"]}
	var a := district_of(from_id)
	var b := district_of(to_id)
	var dist := _district_distance(a, b)
	var mode_data: Dictionary = transport().get(mode, {})
	var units := maxi(1, dist)
	var minutes: int = TimeManager.TimeClock.round_cost(
		float(units) * float(mode_data.get("minutes_per_cell", 10.0))
		+ float(mode_data.get("boarding_minutes", 0.0)))
	match mode:
		"walk":
			return {"ok": true, "minutes": minutes, "slots": 0, "dm": 0, "reason": ""}
		"bike":
			return {"ok": true, "minutes": minutes, "slots": 0, "dm": 0, "reason": ""}
		"bus":
			var line: Array = transport().get("bus", {}).get("line", [])
			if not (a in line and b in line):
				return {"ok": false, "minutes": 0, "slots": 0, "dm": 0, "reason": Loc.t("sys.town_manager.keine_buslinie_dorthin", "Keine Buslinie dorthin.")}
			var fare: int = int(transport().get("bus", {}).get("cost_dm", 2))
			return {"ok": true, "minutes": minutes, "slots": 0, "dm": fare, "reason": ""}
		"car":
			return {"ok": true, "minutes": minutes, "slots": 0, "dm": 0, "reason": ""}
	return {"ok": false, "minutes": 0, "slots": 0, "dm": 0, "reason": Loc.t("sys.town_manager.unknown_transport", "Unbekanntes Verkehrsmittel.")}


## Kürzeste Bezirks-Distanz über roads (Dijkstra, ungerichtet). -1 = unerreichbar.
func _district_distance(a: String, b: String) -> int:
	if a == "" or b == "":
		return 1
	if a == b:
		return 0
	# Die Karte fragt alle Orte × Verkehrsmittel ab — Graphaufbau + Suche lohnen
	# sich nur einmal pro Bezirkspaar (ungerichtet, daher normalisierter Key).
	var cache_key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
	if _dist_cache.has(cache_key):
		return int(_dist_cache[cache_key])
	var adj: Dictionary = {}
	for edge: Array in _town.get("roads", []):
		var x: String = edge[0]
		var y: String = edge[1]
		var w: int = int(edge[2])
		adj.get_or_add(x, []).append([y, w])
		adj.get_or_add(y, []).append([x, w])
	var dist: Dictionary = {a: 0}
	var queue: Array = [a]
	while not queue.is_empty():
		# einfache Prioritätswahl (kleine Graphen)
		queue.sort_custom(func(p: String, q: String) -> bool: return dist[p] < dist[q])
		var cur: String = queue.pop_front()
		if cur == b:
			_dist_cache[cache_key] = dist[b]
			return dist[b]
		for pair: Array in adj.get(cur, []):
			var nxt: String = pair[0]
			var nd: int = dist[cur] + int(pair[1])
			if not dist.has(nxt) or nd < dist[nxt]:
				dist[nxt] = nd
				queue.append(nxt)
	_dist_cache[cache_key] = dist.get(b, -1)
	return dist.get(b, -1)
