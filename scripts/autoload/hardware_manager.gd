extends Node
## HardwareManager — der Upgrade-Baum aus GDD §7 („Hardware & Zimmer") über den
## bestehenden Kaufwegen. Struktur/Abhängigkeiten: data/hardware_upgrades.json;
## Namen/Preise/Jahre bleiben Single Source in data/shop.json (shop_item);
## Katalog-Fakten (Marktjahre/Original-Preis) liefert die HardwareBible über das
## db_name-Feld der Artikel. Käufe laufen ausschließlich über ShopManager.buy()
## bzw. OrderManager.place_order() — dadurch greifen Duplikat-Schutz, Geldprüfung
## und der T11-Hook (add_hardware aktiviert Zimmer-Modelle) unverändert.

const PATH := "res://data/hardware_upgrades.json"

signal upgrades_changed

var tracks: Array = []
var _nodes: Dictionary = {}   # node_id -> {node, track_id}
var load_issues: Array = []


func _ready() -> void:
	reload()
	PlayerStats.stats_changed.connect(func() -> void: upgrades_changed.emit())
	OrderManager.orders_changed.connect(func() -> void: upgrades_changed.emit())
	TimeManager.year_changed.connect(func(_year: int) -> void: upgrades_changed.emit())


func reload() -> void:
	tracks = []
	_nodes = {}
	load_issues = []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		load_issues.append("hardware_upgrades.json fehlt")
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		load_issues.append("hardware_upgrades.json ist kein JSON-Objekt")
		return
	tracks = (data as Dictionary).get("tracks", [])
	for track: Dictionary in tracks:
		for node: Dictionary in track.get("nodes", []):
			var id := str(node.get("id", ""))
			if id.is_empty() or _nodes.has(id):
				load_issues.append("Knoten-ID fehlt/doppelt: '%s'" % id)
				continue
			_nodes[id] = {"node": node, "track": str(track.get("id", ""))}
	_validate()


## Drift-Guard (town.json-Muster): jeder shop_item existiert im Shop, jede
## requires-Referenz ist ein echter Knoten. Läuft beim Laden + im Test.
func _validate() -> void:
	for id: String in _nodes:
		var node: Dictionary = _nodes[id]["node"]
		var shop_item := str(node.get("shop_item", ""))
		if not bool(node.get("builtin", false)) and ShopManager.get_item(shop_item).is_empty():
			load_issues.append("Knoten '%s': Shop-Artikel '%s' fehlt" % [id, shop_item])
		for req: Variant in node.get("requires", []):
			if not _nodes.has(str(req)):
				load_issues.append("Knoten '%s': requires '%s' existiert nicht" % [id, req])
	for issue: String in load_issues:
		push_warning("HardwareManager: " + issue)


func node_ids() -> Array:
	return _nodes.keys()


## Sichtbarkeit ist absichtlich strenger als node_state(): Der interne Baum
## kennt die ganze Dekade, Grubers UI aber nur aktuell gefuehrte Modelle.
## Bereits eingebaute/bestellte Altgeraete bleiben im aktuellen Ausbauplan
## sichtbar; eine historische Vorschau (year >= 0) ist dagegen zustandsneutral.
func node_visible(id: String, year: int = -1) -> bool:
	if not _nodes.has(id):
		return false
	var node: Dictionary = _nodes[id]["node"]
	if bool(node.get("builtin", false)):
		return true
	if year < 0 and (owned(id) or OrderManager.is_pending(str(node.get("shop_item", ""))) \
			or OrderManager.is_arrived(str(node.get("shop_item", "")))):
		return true
	var item := ShopManager.get_item(str(node.get("shop_item", "")))
	return ShopManager.is_item_available(item, year)


func visible_node_ids(year: int = -1) -> Array:
	var result: Array = []
	for id: String in _nodes:
		if node_visible(id, year):
			result.append(id)
	return result


## UI-sichere Tracks: Knoten ausserhalb ihrer Marktzeit werden nicht als
## Silhouette, Zaehler oder Pfad-Vorschau transportiert.
func visible_tracks(year: int = -1) -> Array:
	var result: Array = []
	for track: Dictionary in tracks:
		var visible_nodes: Array = []
		for node: Dictionary in track.get("nodes", []):
			if node_visible(str(node.get("id", "")), year):
				visible_nodes.append(node.duplicate(true))
		if visible_nodes.is_empty():
			continue
		var safe_track := track.duplicate(true)
		var track_id := str(track.get("id", ""))
		safe_track["name"] = Loc.t("hw.%s.name" % track_id, str(track.get("name", track_id)))
		safe_track["nodes"] = visible_nodes
		result.append(safe_track)
	return result


func visible_nodes_in_track(track_id: String, year: int = -1) -> Array:
	for track: Dictionary in visible_tracks(year):
		if str(track.get("id", "")) == track_id:
			return track.get("nodes", [])
	return []


func _hardware_id(node: Dictionary) -> String:
	var item: Dictionary = ShopManager.get_item(str(node.get("shop_item", "")))
	return str((item.get("payload", {}) as Dictionary).get("hardware", ""))


func owned(id: String) -> bool:
	if not _nodes.has(id):
		return false
	var node: Dictionary = _nodes[id]["node"]
	if bool(node.get("builtin", false)):
		return true
	var hardware_id := _hardware_id(node)
	return hardware_id != "" and PlayerStats.has_hardware(hardware_id)


## Vollstatus eines Knotens für UI/Tests: besitzt/bestellt/kaufbar/gesperrt,
## mit Grund und den Shop-/Katalogdaten (Preis, Jahr, HardwareBible-Eintrag).
func node_state(id: String) -> Dictionary:
	if not _nodes.has(id):
		return {}
	var node: Dictionary = _nodes[id]["node"]
	var track_id := str(_nodes[id].get("track", ""))
	var item: Dictionary = ShopManager.get_item(str(node.get("shop_item", "")))
	var quote: Dictionary = ShopManager.price_quote(item)
	var market := ShopManager.market_years(item) if not item.is_empty() else Vector2i(1990, 1999)
	var fallback_name := str(node.get("name", item.get("name", id)))
	var display_name := Loc.t("hw.%s.nodes.%s.name" % [track_id, id], fallback_name) \
		if node.has("name") else fallback_name
	var fallback_effect := str(node.get("effect", ""))
	var display_effect := Loc.t("hw.%s.nodes.%s.effect" % [track_id, id], fallback_effect) \
		if not fallback_effect.is_empty() else ""
	var state := {
		"id": id, "node": node, "item": item,
		"name": display_name,
		"effect": display_effect,
		"models": node.get("models", []),
		"base_price": float(quote.get("base_price", 0.0)),
		"price_factor": float(quote.get("factor", 1.0)),
		"price": float(quote.get("price", 0.0)),
		"affordable": bool(quote.get("affordable", true)),
		"shortfall": float(quote.get("shortfall", 0.0)),
		"year_available": market.x, "year_obsolete": market.y,
		"owned": owned(id), "active": false, "pending": false, "days_left": 0,
		"available": false, "visible": node_visible(id), "locked_reason": "",
		"catalog": {},
	}
	var db_name := str(item.get("db_name", ""))
	if db_name != "" and HardwareBible.has_device(db_name):
		state["catalog"] = HardwareBible.device(db_name)
	if state["owned"]:
		var hardware_id := _hardware_id(node)
		if hardware_id != "":
			state["active"] = PlayerStats.hardware_active(hardware_id)
		elif bool(node.get("builtin", false)):
			state["active"] = PlayerStats.desk_model("computer_model") == "amiga_500"
		return state
	var item_id := str(item.get("id", ""))
	if item_id != "" and OrderManager.is_pending(item_id):
		state["pending"] = true
		state["days_left"] = OrderManager.days_left(item_id)
		return state
	if TimeManager.year < state["year_available"]:
		state["locked_reason"] = Loc.t("sys.hardware_manager.ab_d", "ab %d") % state["year_available"]
		return state
	if TimeManager.year > state["year_obsolete"]:
		state["locked_reason"] = Loc.t("sys.hardware_manager.nicht_mehr_im_sortiment", "nicht mehr im Sortiment")
		return state
	for req: Variant in node.get("requires", []):
		if not owned(str(req)):
			var req_state := node_state(str(req))
			state["locked_reason"] = Loc.t("sys.hardware_manager.braucht_s", "braucht %s") % (str(req_state.get("name", req)) \
				if node_visible(str(req)) else Loc.t("sys.hardware_manager.eine_fruehere_ausbaustufe", "eine frühere Ausbaustufe"))
			return state
	var shop_requirement: Dictionary = ShopManager.item_requirement_status(item)
	if not bool(shop_requirement.get("ok", true)):
		state["locked_reason"] = str(shop_requirement.get("reason", Loc.t("sys.hardware_manager.voraussetzung_fehlt", "Voraussetzung fehlt")))
		return state
	state["available"] = true
	return state


## Kauf/Bestellung über die bestehenden Pfade — ein Kaufweg, keine Sonderkasse.
func buy(id: String) -> Dictionary:
	var state := node_state(id)
	if state.is_empty():
		return {"ok": false, "text": Loc.t("sys.hardware_manager.unbekanntes_upgrade", "Unbekanntes Upgrade.")}
	if bool(state["owned"]):
		return {"ok": false, "text": Loc.t("sys.hardware_manager.hast_du_schon_eingebaut", "Hast du schon eingebaut.")}
	if bool(state["pending"]):
		return {"ok": false, "text": Loc.t("sys.hardware_manager.schon_bestellt_kommt_in_d_tag", "Schon bestellt — kommt in %d Tag(en).") % int(state["days_left"])}
	if not ShopManager.is_item_available(state["item"]):
		return {"ok": false, "text": Loc.t("sys.hardware_manager.dieses_modell_fuhrt_herr_gruber_in", "Dieses Modell führt Herr Gruber in diesem Jahr nicht.")}
	if not bool(state["available"]):
		return {"ok": false, "text": Loc.t("sys.hardware_manager.noch_nicht_moglich_s", "Noch nicht möglich (%s).") % str(state["locked_reason"])}
	var item: Dictionary = state["item"]
	if bool(item.get("order_only", false)):
		return OrderManager.place_order(str(item.get("id", "")))
	return ShopManager.buy(str(item.get("id", "")))
