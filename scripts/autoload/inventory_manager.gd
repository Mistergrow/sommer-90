extends Node
## InventoryManager — zählbare Nicht-Disketten-Items (Etiketten,
## Reinigungsdisketten, Magazine ...). Disketten verwaltet der DiskManager,
## da jede Diskette ein Individuum ist.

signal inventory_changed

## Anzeige-Namen der Items (für UI/Lager-Leiste).
const ITEM_NAMES := {
	"etiketten": "Etiketten",
	"reinigungsdiskette": "Reinigungsdisk.",
	"magazine": "Magazine",
}

## Verzehrbare Kiosk-Ware: id → {name, energy, litter_kind, litter_target}. Wird
## am Kiosk INS INVENTAR gekauft und später verzehrt — erst dann gibt es Energie,
## und die leere Verpackung wird zu Müll (zu Hause im Zimmer, unterwegs im Eimer).
const FOODS := {
	"cola": {"name": "Cola-Dose", "energy": 8, "litter_kind": "cola_dose", "litter_target": "recycling"},
	"chips": {"name": "Chips-Tüte", "energy": 5, "litter_kind": "chips_tuete", "litter_target": "bin"},
	"eis": {"name": "Eis am Stiel", "energy": 6, "litter_kind": "eispackung", "litter_target": "bin"},
	"capri_sonne": {"name": "Capri-Sonne Orange", "energy": 7, "litter_kind": "trinkbeutel", "litter_target": "bin"},
	"punica": {"name": "Punica Fruchtgetränk", "energy": 9, "litter_kind": "pfandflasche", "litter_target": "recycling"},
	"lift_apfelschorle": {"name": "Lift Apfelschorle", "energy": 8, "litter_kind": "pfandflasche", "litter_target": "recycling"},
	"mezzo_mix": {"name": "Mezzo Mix", "energy": 8, "litter_kind": "pfandflasche", "litter_target": "recycling"},
	"raider": {"name": "Raider", "energy": 5, "litter_kind": "riegelpapier", "litter_target": "bin"},
	"twix": {"name": "Twix", "energy": 5, "litter_kind": "riegelpapier", "litter_target": "bin"},
	"banjo": {"name": "Banjo Haselnuss", "energy": 5, "litter_kind": "riegelpapier", "litter_target": "bin"},
	"balisto": {"name": "Balisto Korn-Mix", "energy": 5, "litter_kind": "riegelpapier", "litter_target": "bin"},
	"lila_pause": {"name": "Milka Lila Pause", "energy": 5, "litter_kind": "riegelpapier", "litter_target": "bin"},
	"applause": {"name": "Applause", "energy": 5, "litter_kind": "riegelpapier", "litter_target": "bin"},
	"tripple_choc": {"name": "Tripple Choc", "energy": 6, "litter_kind": "riegelpapier", "litter_target": "bin"},
	"pom_baer": {"name": "POM-BÄR Original", "energy": 5, "litter_kind": "chips_tuete", "litter_target": "bin"},
	"crunchips": {"name": "Crunchips Paprika", "energy": 5, "litter_kind": "chips_tuete", "litter_target": "bin"},
	"nicnacs": {"name": "NicNac’s", "energy": 6, "litter_kind": "chips_tuete", "litter_target": "bin"},
	"nogger": {"name": "Langnese Nogger", "energy": 7, "litter_kind": "eispackung", "litter_target": "bin"},
	"cornetto": {"name": "Cornetto Haselnuss", "energy": 8, "litter_kind": "eispackung", "litter_target": "bin"},
	"flutschfinger": {"name": "Flutschfinger", "energy": 5, "litter_kind": "eispackung", "litter_target": "bin"},
	"magnum": {"name": "Magnum Classic", "energy": 9, "litter_kind": "eispackung", "litter_target": "bin"},
	"brauner_baer": {"name": "Brauner Bär", "energy": 8, "litter_kind": "eispackung", "litter_target": "bin"},
	"pommes": {"name": "Pommes frites", "energy": 14, "litter_kind": "imbissschale", "litter_target": "bin"},
	"currywurst": {"name": "Currywurst", "energy": 20, "litter_kind": "imbissschale", "litter_target": "bin"},
	"currywurst_pommes": {"name": "Currywurst mit Pommes", "energy": 30, "litter_kind": "imbissschale", "litter_target": "bin"},
	"pommes_paprikasauce": {"name": "Pommes mit Paprikasauce", "energy": 16, "litter_kind": "imbissschale", "litter_target": "bin"},
	"pommes_ketchup": {"name": "Pommes mit Ketchup", "energy": 15, "litter_kind": "imbissschale", "litter_target": "bin"},
	"pommes_mayo": {"name": "Pommes mit Mayonnaise", "energy": 17, "litter_kind": "imbissschale", "litter_target": "bin"},
	"pommes_rot_weiss": {"name": "Pommes rot-weiß", "energy": 18, "litter_kind": "imbissschale", "litter_target": "bin"},
	"bratwurst": {"name": "Bratwurst", "energy": 16, "litter_kind": "imbissschale", "litter_target": "bin"},
	"bratwurst_pommes": {"name": "Bratwurst mit Pommes", "energy": 28, "litter_kind": "imbissschale", "litter_target": "bin"},
	"frikadelle": {"name": "Frikadelle", "energy": 15, "litter_kind": "imbissschale", "litter_target": "bin"},
	"frikadelle_pommes": {"name": "Frikadelle mit Pommes", "energy": 27, "litter_kind": "imbissschale", "litter_target": "bin"},
	"schaschlik": {"name": "Schaschlik in Sauce", "energy": 20, "litter_kind": "imbissschale", "litter_target": "bin"},
	"schaschlik_pommes": {"name": "Schaschlik mit Pommes", "energy": 32, "litter_kind": "imbissschale", "litter_target": "bin"},
	"schnitzel": {"name": "Schnitzel", "energy": 22, "litter_kind": "imbissschale", "litter_target": "bin"},
	"schnitzel_pommes": {"name": "Schnitzel mit Pommes", "energy": 35, "litter_kind": "imbissschale", "litter_target": "bin"},
	"extra_ketchup": {"name": "Extra Ketchup", "energy": 1, "litter_kind": "imbissschale", "litter_target": "bin"},
	"extra_mayonnaise": {"name": "Extra Mayonnaise", "energy": 2, "litter_kind": "imbissschale", "litter_target": "bin"},
	"extra_senf": {"name": "Extra Senf", "energy": 1, "litter_kind": "imbissschale", "litter_target": "bin"},
	"extra_currysauce": {"name": "Extra Currysauce", "energy": 2, "litter_kind": "imbissschale", "litter_target": "bin"},
	"extra_zwiebeln": {"name": "Extra Zwiebeln", "energy": 1, "litter_kind": "imbissschale", "litter_target": "bin"},
	"extra_broetchen": {"name": "Extra Brötchen", "energy": 3, "litter_kind": "brottuete", "litter_target": "bin"},
}

var items: Dictionary = {}


func is_food(id: String) -> bool:
	return FOODS.has(id)


## Sattigung ist vom kurzfristigen Energie-Kick getrennt. Vollwertige
## Imbissgerichte wirken wesentlich staerker als Getraenke, Eis oder Saucen.
## Ein optionales explizites `hunger` im Datensatz hat Vorrang; der Fallback
## haelt auch alte Kiosk-/Imbissdaten voll kompatibel.
func food_hunger_relief(id: String) -> int:
	if not FOODS.has(id):
		return 0
	var food: Dictionary = FOODS[id]
	if food.has("hunger"):
		return maxi(0, int(food["hunger"]))
	if id.begins_with("extra_"):
		return clampi(int(food.get("energy", 1)) * 2, 2, 8)
	if id in ["cola", "capri_sonne", "punica", "lift_apfelschorle", "mezzo_mix"]:
		return clampi(int(food.get("energy", 5)) * 2, 10, 20)
	if id in ["chips", "raider", "twix", "banjo", "balisto", "lila_pause",
			"applause", "tripple_choc", "pom_baer", "crunchips", "nicnacs",
			"eis", "nogger", "cornetto", "flutschfinger", "magnum", "brauner_baer"]:
		return clampi(int(food.get("energy", 5)) * 3, 14, 30)
	# Pommes, Wurst, Schnitzel und Kombinationen sind echte Mahlzeiten.
	return clampi(int(food.get("energy", 14)) * 3, 38, 92)


## Etwas Gekauftes verzehren: Energie geben, leere Verpackung als Müll. Zu Hause
## landet sie im ZIMMER (SAUBERKEIT sinkt, bis man aufräumt), unterwegs im
## öffentlichen Mülleimer. Rückgabe {ok, text}.
func consume_food(id: String) -> Dictionary:
	if not FOODS.has(id):
		return {"ok": false, "text": Loc.t("sys.inventory_manager.kann_man_nicht_verzehren", "Das kann man nicht verzehren.")}
	if count(id) <= 0:
		return {"ok": false, "text": Loc.t("sys.inventory_manager.hast_du_gar_nicht_dabei", "Hast du gar nicht dabei.")}
	var food: Dictionary = FOODS[id]
	consume(id, 1)
	PlayerStats.change_stat("energie", int(food.get("energy", 0)))
	var relief := food_hunger_relief(id)
	PlayerStats.change_stat("hunger", -relief)
	var at_home: bool = GameManager.current_location_id == "room"
	var tail := Loc.t(
		"sys.inventory_manager.packaging_at_home",
		"Die leere Verpackung liegt jetzt im Zimmer herum.") if at_home else Loc.t(
		"sys.inventory_manager.packaging_away",
		"Die Verpackung wirfst du unterwegs in den Mülleimer.")
	if at_home:
		RoomManager.add_litter(str(food.get("litter_kind", "muell")),
			str(food.get("litter_target", "bin")), "verzehr")
	AudioManager.play("bag", 0.0)
	var food_name := Loc.t("inventory.food.%s" % id, str(food.get("name", "Snack")))
	return {"ok": true,
		"text": Loc.t(
			"sys.inventory_manager.consumed",
			"%s verzehrt (+%d Energie · −%d Hunger). %s") % [food_name,
			int(food.get("energy", 0)), relief, tail]}


func reset() -> void:
	# Startausstattung laut GDD: ein paar Etiketten und Computerzeitschriften.
	items = {"etiketten": 5, "reinigungsdiskette": 0, "magazine": 3}
	inventory_changed.emit()


func count(id: String) -> int:
	return int(items.get(id, 0))


func add_item(id: String, amount: int) -> void:
	items[id] = maxi(0, count(id) + amount)
	inventory_changed.emit()


## Verbraucht amount Stück; false = nicht genug vorhanden (nichts passiert).
func consume(id: String, amount: int = 1) -> bool:
	if count(id) < amount:
		return false
	items[id] = count(id) - amount
	inventory_changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"items": items}


func from_dict(d: Dictionary) -> void:
	items = d.get("items", {})
	inventory_changed.emit()
