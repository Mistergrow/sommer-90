class_name HistoryShopCatalog
extends RefCounted
## Gemeinsame, rein datengetriebene Wahrheit fuer Kiosk und Pommesbude.
## Produktjahre, Museumstexte, Assets und Preise bleiben damit aus den beiden
## Location-Skripten heraus. Das Modell mutiert keinen Spielzustand.

const DATA_PATH := "res://data/history_shops.json"
const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
static var _doc: Dictionary = {}


static func document() -> Dictionary:
	if _doc.is_empty() and FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_doc = parsed
	return _doc


static func shop(shop_id: String) -> Dictionary:
	return document().get("shops", {}).get(shop_id, {})


static func items_for(shop_id: String, year: int, category := "") -> Array:
	var result: Array = []
	for raw: Variant in shop(shop_id).get("items", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if year < int(entry.get("year_from", 1990)) or year > int(entry.get("year_to", 1999)):
			continue
		if category != "" and str(entry.get("category", "")) != category:
			continue
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order := {"getraenk": 10, "suess": 20, "eis": 30, "essen": 10}
		var ac := int(order.get(str(a.get("category", "")), 999))
		var bc := int(order.get(str(b.get("category", "")), 999))
		if ac != bc:
			return ac < bc
		var ao := int(a.get("sort_order", 999))
		var bo := int(b.get("sort_order", 999))
		if ao != bo:
			return ao < bo
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	return result


static func item(shop_id: String, item_id: String, year: int) -> Dictionary:
	for entry: Dictionary in items_for(shop_id, year):
		if str(entry.get("id", "")) == item_id:
			return entry
	return {}


static func period_text(item_def: Dictionary) -> String:
	var game_from := int(item_def.get("year_from", 1990))
	var game_to := int(item_def.get("year_to", 1999))
	var within := str(game_from) if game_from == game_to else "%d–%d" % [game_from, game_to]
	var real_bits: Array[String] = []
	if item_def.has("real_from"):
		real_bits.append("seit %d" % int(item_def["real_from"]))
	if item_def.has("real_to"):
		real_bits.append("bis %d" % int(item_def["real_to"]))
	if item_def.has("hiatus_from") and item_def.has("hiatus_to"):
		real_bits.append("Pause %d–%d" % [
			int(item_def["hiatus_from"]), int(item_def["hiatus_to"])])
	var suffix := ""
	if not real_bits.is_empty():
		suffix = " · real %s" % ", ".join(real_bits)
	return "Im Spielregal: %s%s" % [within, suffix]


static func validate() -> Array[String]:
	var issues: Array[String] = []
	var seen: Dictionary = {}
	for shop_id: String in document().get("shops", {}):
		for raw: Variant in shop(shop_id).get("items", []):
			if not raw is Dictionary:
				issues.append("%s: Eintrag ist kein Dictionary" % shop_id)
				continue
			var entry: Dictionary = raw
			var id := str(entry.get("id", ""))
			var key := "%s/%s" % [shop_id, id]
			if id == "" or seen.has(key):
				issues.append("ungueltige/doppelte ID: %s" % key)
			seen[key] = true
			if int(entry.get("year_from", 0)) > int(entry.get("year_to", -1)):
				issues.append("%s: Jahresfenster invertiert" % key)
			if entry.has("hiatus_from") != entry.has("hiatus_to"):
				issues.append("%s: reale Pause braucht Anfang und Ende" % key)
			elif entry.has("hiatus_from") and int(entry["hiatus_from"]) >= int(entry["hiatus_to"]):
				issues.append("%s: reale Pause ist invertiert" % key)
			if float(entry.get("price", 0.0)) <= 0.0:
				issues.append("%s: Preis fehlt" % key)
			for asset_key in ["asset", "secondary_asset"]:
				var path := str(entry.get(asset_key, ""))
				if path != "" and not RuntimeImages.exists(path):
					issues.append("%s: Asset fehlt: %s" % [key, path])
	return issues
