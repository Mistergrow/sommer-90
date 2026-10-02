extends Node
## RoomManager — Zimmerausbau. Gekaufte Zimmerobjekte (weitere Diskettenboxen,
## später Regale, Poster, Neonlampe ...) werden hier registriert; die
## Zimmerszene rendert sie sichtbar, Kapazitätsboni fließen in den DiskManager.

signal room_changed
signal device_model_changed(selector: String, model_id: String)

const BASE_DISK_CAPACITY := 12  # die erste kleine Diskettenbox
const DISKBOX_CAPACITY := 12    # jede weitere gekaufte Box
const ARCHIVE_DISKBOX_CAPACITY := 80  # hohe, abschliessbare Regalbox
const DEVICE_CATALOG := preload("res://scripts/gfx/room_device_catalog.gd")
const COMPUTER_RESALE_VALUES := {
	"amiga_500": 180,
	"amiga_600": 300,
	"amiga_1200": 425,
}

var objects: Array = []  # z. B. ["diskbox", "diskbox", "poster"]

# --- ZIMMER-ORDNUNG (T1) ------------------------------------------------------
# Konsumiertes (Coladose, Eispackung, Chips-Tüte …) liegt als Müll im Zimmer, bis
# man aufräumt / den Müll rausbringt. RoomManager ist die EINZIGE Zustandsautorität
# (Vertrag mit Codex, s. docs/AGENT_SYNC.md); Codex' room_tidy-Minispiel liest
# `litter` und ruft `tidy(uids)`. Jedes Teil: {uid, kind, target, created_day, source}.
# target = semantische Zone: "bin" | "recycling" | "shelf" | "laundry".
const CLEAN_PENALTY := 7        # je Müllteil sinkt die Sauberkeit
const MAX_LITTER := 40          # Deckel (Spielstand + Bar bleiben handhabbar)
const NAG_THRESHOLD := 45       # ab dieser Sauberkeit meckern die Eltern morgens
const NAG_PENALTY := 3          # Eltern-Toleranz-Abzug bei Chaos
const CHAOS_THRESHOLD := 20     # GDD „Zimmer-Chaos": ab hier eskaliert es täglich
const CHAOS_PENALTY := 6        # doppelte Drainage — Chaos ist eine echte Gegenkraft

var litter: Array = []          # [{uid:int, kind:String, target:String, created_day:int, source:String}]
var _next_uid := 1


func _ready() -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm != null and tm.has_signal("day_changed"):
		tm.day_changed.connect(_on_day_changed)


func reset() -> void:
	objects = []
	litter = []
	_next_uid = 1
	validate_device_models()
	room_changed.emit()


# --- Raumgeraete-API ----------------------------------------------------------

## Vollstaendiger, normalisierter Katalog aller als `device` markierten Layer
## inklusive aller asset_by_model-Varianten. PlayerStats bleibt dabei alleinige
## Save-Autoritaet; RoomManager ist die validierende Laufzeit-Fassade.
func device_catalog(force_reload := false) -> Dictionary:
	return DEVICE_CATALOG.catalog(force_reload)


func device_slots(force_reload := false) -> Array:
	return DEVICE_CATALOG.slots(force_reload)


## Modelle eines Slots in der kuratierten JSON-Reihenfolge. Standardmaessig
## werden nur Startausstattung und tatsaechlich gekaufte Modelle angeboten.
func available_device_models(selector: String, owned_only := true) -> Array:
	var definition: Dictionary = DEVICE_CATALOG.definition_for_slot(selector)
	if definition.is_empty():
		return []
	var result: Array = []
	var models: Dictionary = definition.get("models", {})
	for model_value: Variant in definition.get("model_order", []):
		var model_id := str(model_value)
		if models.has(model_id) and (not owned_only or _device_model_owned(models[model_id])):
			result.append(model_id)
	return result


## Aktive, kataloggueltige Auswahl. Manipulierte/alte Save-Werte fallen fuer die
## Darstellung sicher auf das Defaultmodell zurueck; validate_device_models()
## repariert sie beim Laden auch persistent.
func active_device_model(selector: String) -> String:
	var definition: Dictionary = DEVICE_CATALOG.definition_for_slot(selector)
	if definition.is_empty():
		return ""
	var selected := str(PlayerStats.desk_model(selector)) \
		if PlayerStats.has_method("desk_model") else ""
	var models: Dictionary = definition.get("models", {})
	var selected_definition: Dictionary = models.get(selected, {})
	if not selected_definition.is_empty() and _device_model_owned(selected_definition):
		return selected
	# Auch zwischen PlayerStats.from_dict()/stats_changed und der anschliessenden
	# Save-Reparatur darf der Compositor nie kurz ein unbesessenes Modell zeigen.
	var owned := available_device_models(selector, true)
	return str(owned[0]) if not owned.is_empty() \
		else str(definition.get("default_model", ""))


## Besitzgepruefter Modellwechsel. Direkte PlayerStats-Zugriffe sind nur noch
## Low-Level-Persistenz/Tests; Spiel- und Editor-UI benutzen diese Fassade.
func select_device_model(selector: String, model_id: String) -> bool:
	var definition: Dictionary = DEVICE_CATALOG.definition_for_slot(selector)
	var models: Dictionary = definition.get("models", {})
	if not models.has(model_id) or not _device_model_owned(models[model_id]):
		return false
	if not PlayerStats.select_desk_model(selector, model_id):
		return false
	# PlayerStats.stats_changed aktualisiert den Compositor ohne doppelten Rebuild.
	device_model_changed.emit(selector, model_id)
	return true


func computer_resale_value(model_id: String) -> int:
	return int(COMPUTER_RESALE_VALUES.get(model_id, 0))


func printer_resale_value(model_id: String) -> int:
	var definition := DEVICE_CATALOG.definition_for_slot("printer_model")
	var model: Dictionary = definition.get("models", {}).get(model_id, {})
	var hardware_id := str(model.get("requires_hardware", ""))
	return ShopManager.hardware_resale_value(hardware_id)


func printer_display_name(model_id: String) -> String:
	var definition := DEVICE_CATALOG.definition_for_slot("printer_model")
	var model: Dictionary = definition.get("models", {}).get(model_id, {})
	var hardware_id := str(model.get("requires_hardware", ""))
	var item := ShopManager.item_for_hardware(hardware_id)
	return str(item.get("name", model_id.replace("_", " ").capitalize()))


## Drucker sind echte Einzelgeräte: aktive und eingelagerte Modelle können
## freiwillig verkauft werden. Bei einem aktiven Verkauf wird automatisch auf
## den nächsten besessenen Drucker umgeschaltet; ohne Restgerät verschwindet
## der Drucker-Layer vollständig aus dem Zimmer.
func sell_printer(model_id: String) -> Dictionary:
	var owned := available_device_models("printer_model", true)
	if model_id not in owned:
		return {"ok": false, "text": Loc.t("sys.room_manager.dieser_drucker_gehort_nicht_mehr_zu", "Dieser Drucker gehört nicht mehr zu deinem Inventar.")}
	var definition := DEVICE_CATALOG.definition_for_slot("printer_model")
	var model: Dictionary = definition.get("models", {}).get(model_id, {})
	var hardware_id := str(model.get("requires_hardware", ""))
	var value := printer_resale_value(model_id)
	if hardware_id.is_empty() or value <= 0:
		return {"ok": false, "text": Loc.t("sys.room_manager.fur_dieses_modell_gibt_es_kein", "Für dieses Modell gibt es kein eindeutiges Gebrauchtangebot.")}
	if not PlayerStats.remove_hardware(hardware_id):
		return {"ok": false, "text": Loc.t("sys.room_manager.druckerbesitz_konnte_nicht_eindeutig_ausgetragen_werden", "Der Druckerbesitz konnte nicht eindeutig ausgetragen werden.")}
	OrderManager.note_hardware_sold(hardware_id)
	validate_device_models()
	PlayerStats.add_money(value)
	var display_name := printer_display_name(model_id)
	MemoryManager.record("hardware", "%s bewusst gebraucht für %d DM verkauft" % [
		display_name, value])
	room_changed.emit()
	return {
		"ok": true, "payout": value, "model_id": model_id,
		"text": "%s gebraucht verkauft · +%d DM (mindestens halber Kaufpreis)." % [
			display_name, value],
	}


## Ein Rechnerverkauf ist immer optional und explizit: nur ein eingelagerter,
## wirklich besessener Rechner darf gehen, niemals der aktive oder der letzte.
func sell_computer(model_id: String) -> Dictionary:
	var owned := available_device_models("computer_model", true)
	var active := active_device_model("computer_model")
	var value := computer_resale_value(model_id)
	if model_id not in owned:
		return {"ok": false, "text": Loc.t("sys.room_manager.dieser_rechner_gehort_nicht_mehr_zu", "Dieser Rechner gehört nicht mehr zu deiner Sammlung.")}
	if model_id == active:
		return {"ok": false, "text": Loc.t("sys.room_manager.aktive_tischrechner_kann_nicht_verkauft_werden", "Der aktive Tischrechner kann nicht verkauft werden. Stell zuerst den anderen auf.")}
	if owned.size() <= 1:
		return {"ok": false, "text": Loc.t("sys.room_manager.letzte_rechner_bleibt_bei_dir_ohne", "Der letzte Rechner bleibt bei dir — ohne ihn wäre das Spiel nicht mehr bedienbar.")}
	if value <= 0:
		return {"ok": false, "text": Loc.t("sys.room_manager.fur_dieses_modell_gibt_es_kein_bf32", "Für dieses Modell gibt es kein seriöses Gebrauchtangebot.")}
	var definition := DEVICE_CATALOG.definition_for_slot("computer_model")
	var model: Dictionary = definition.get("models", {}).get(model_id, {})
	var hardware_id := str(model.get("requires_hardware", ""))
	if hardware_id.is_empty() or not PlayerStats.remove_hardware(hardware_id):
		return {"ok": false, "text": Loc.t("sys.room_manager.besitz_konnte_nicht_eindeutig_ausgetragen_werden", "Der Besitz konnte nicht eindeutig ausgetragen werden.")}
	PlayerStats.add_money(value)
	MemoryManager.record("hardware", "%s bewusst gebraucht für %d DM verkauft" % [
		model_id.replace("_", " "), value])
	validate_device_models()
	room_changed.emit()
	return {
		"ok": true, "payout": value, "model_id": model_id,
		"text": Loc.t("sys.room_manager.s_gebraucht_verkauft_d_dm_dein", "%s gebraucht verkauft · +%d DM. Dein Tischrechner bleibt angeschlossen.") % [
			model_id.replace("amiga_", "Amiga ").replace("_", " "), value],
	}


## Save-Migration/Manipulationsschutz: unbekannte oder nicht besessene Varianten
## werden auf das erste besessene (sonst das katalogisierte Default-)Modell gesetzt.
func validate_device_models() -> int:
	var repaired := 0
	for selector_value: Variant in device_slots():
		var selector := str(selector_value)
		var definition: Dictionary = DEVICE_CATALOG.definition_for_slot(selector)
		var selected := str(PlayerStats.desk_model(selector))
		var model: Dictionary = definition.get("models", {}).get(selected, {})
		if not model.is_empty() and _device_model_owned(model):
			continue
		var owned := available_device_models(selector, true)
		var fallback := str(owned[0]) if not owned.is_empty() \
			else str(definition.get("default_model", ""))
		if fallback != selected and PlayerStats.select_desk_model(selector, fallback):
			repaired += 1
	return repaired


func _device_model_owned(model: Dictionary) -> bool:
	if not bool(model.get("render_ready", true)):
		return false
	var requirement: Variant = model.get("requires_hardware", "")
	if requirement is Array:
		for hardware_id: Variant in requirement:
			if not PlayerStats.has_hardware(str(hardware_id)):
				return false
		return true
	var hardware_id := str(requirement)
	return hardware_id.is_empty() or PlayerStats.has_hardware(hardware_id)


# --- litter-API (Vertrag) -----------------------------------------------------

## Ein Müllteil hinzufügen (beim Konsum). Erzeugt die uid selbst, gibt sie zurück.
func add_litter(kind: String, target := "bin", source := "") -> int:
	var uid := _next_uid
	_next_uid += 1
	litter.append({
		"uid": uid, "kind": kind, "target": target,
		"created_day": int(TimeManager.day_counter), "source": source,
	})
	while litter.size() > MAX_LITTER:
		litter.pop_front()
	room_changed.emit()
	return uid


func litter_count() -> int:
	return litter.size()


## Zimmer-Sauberkeit 0..100 (100 = tipptopp). Speist die SAUBERKEIT-Leiste.
func cleanliness() -> int:
	return clampi(100 - litter.size() * CLEAN_PENALTY, 0, 100)


## Aufräumen. Leeres Array = ALLES weg (Hotspot „Müll rausbringen"); eine uid-Liste
## entfernt nur die tatsächlich einsortierten Teile (Codex' room_tidy-Puzzle).
func tidy(uids: Array = []) -> void:
	if uids.is_empty():
		litter = []
	else:
		litter = litter.filter(func(l: Dictionary) -> bool: return not (int(l.get("uid", 0)) in uids))
	room_changed.emit()


## Bequemer Voll-Aufräum-Pfad (Mülleimer). Rückgabe: wie viele Teile rausgebracht.
func take_out_trash() -> int:
	var n := litter.size()
	if n > 0:
		litter = []
		room_changed.emit()
	return n


## Eltern meckern morgens, wenn das Zimmer vermüllt ist (GDD: Zimmer-Chaos
## senkt die Eltern-Toleranz — zwei Stufen, damit Chaos eine echte Gegenkraft ist).
func _on_day_changed() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if cleanliness() < CHAOS_THRESHOLD:
		PlayerStats.change_stat("eltern_toleranz", -CHAOS_PENALTY)
		UIManager.toast(Loc.t("sys.room_manager.papa_steht_in_tur_ist_kein", "Papa steht in der Tür: »Das ist kein Zimmer mehr, das ist eine Müllkippe. Letzte Warnung!«"))
	elif cleanliness() < NAG_THRESHOLD:
		PlayerStats.change_stat("eltern_toleranz", -NAG_PENALTY)
		UIManager.toast(Loc.t("sys.room_manager.mama_guckt_ins_zimmer_wie_sieht", "Mama guckt ins Zimmer: »Wie sieht's denn hier aus? Räum das auf!«"))


func add_object(id: String) -> void:
	objects.append(id)
	room_changed.emit()


func has_object(id: String) -> bool:
	return id in objects


func count_object(id: String) -> int:
	var n := 0
	for obj in objects:
		if obj == id:
			n += 1
	return n


## Zusätzliche Diskettenplätze durch gekaufte Boxen.
func disk_capacity_bonus() -> int:
	return count_object("diskbox") * DISKBOX_CAPACITY \
		+ count_object("diskbox80") * ARCHIVE_DISKBOX_CAPACITY


func to_dict() -> Dictionary:
	return {"objects": objects, "litter": litter, "next_uid": _next_uid}


func from_dict(d: Dictionary) -> void:
	objects = d.get("objects", [])
	litter = d.get("litter", [])
	_next_uid = int(d.get("next_uid", 1))
	validate_device_models()
	room_changed.emit()
