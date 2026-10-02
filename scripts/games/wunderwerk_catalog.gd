extends RefCounted
## Datenkatalog von WUNDERWERK '94. Keine UI kennt Baukosten, Footprints oder
## Animationsvertraege aus eigener Hand; Modell und Renderer lesen dieselben Daten.

const ITEMS: Array[Dictionary] = [
	{"id": "inspect", "name": "ANSEHEN", "kind": "tool", "cost": 0, "icon": "i"},
	{"id": "path", "name": "WEG", "kind": "path", "cost": 8, "icon": "="},
	{"id": "queue_path", "name": "WARTEGATTER", "kind": "path", "cost": 16,
		"icon": "Q"},
	{"id": "carousel", "name": "KARUSSELL", "kind": "ride", "cost": 360,
		"size": Vector2i(3, 3), "capacity": 8, "duration": 72, "price": 5,
		"appeal": 18, "upkeep": 24, "moving_parts": 12},
	{"id": "wheel", "name": "HIMMELSRAD", "kind": "ride", "cost": 620,
		"size": Vector2i(3, 3), "capacity": 10, "duration": 96, "price": 7,
		"appeal": 25, "upkeep": 38, "moving_parts": 18},
	{"id": "swing", "name": "LUFTTANZ", "kind": "ride", "cost": 440,
		"size": Vector2i(2, 2), "capacity": 8, "duration": 62, "price": 6,
		"appeal": 22, "upkeep": 31, "moving_parts": 17},
	{"id": "boats", "name": "WASSERREISE", "kind": "ride", "cost": 760,
		"size": Vector2i(4, 3), "capacity": 12, "duration": 110, "price": 8,
		"appeal": 30, "upkeep": 46, "moving_parts": 15},
	{"id": "coaster", "name": "BLITZBAHN", "kind": "ride", "cost": 1380,
		"size": Vector2i(4, 3), "capacity": 12, "duration": 105, "price": 10,
		"appeal": 38, "upkeep": 72, "moving_parts": 22},
	{"id": "bumper", "name": "AUTOSCOOTER", "kind": "ride", "cost": 820,
		"size": Vector2i(3, 3), "capacity": 10, "duration": 78, "price": 7,
		"appeal": 27, "upkeep": 43, "moving_parts": 18},
	{"id": "drop_tower", "name": "WOLKENSTURZ", "kind": "ride", "cost": 1120,
		"size": Vector2i(3, 3), "capacity": 10, "duration": 72, "price": 9,
		"appeal": 35, "upkeep": 61, "moving_parts": 16},
	{"id": "octopus", "name": "STERNKRAKE", "kind": "ride", "cost": 940,
		"size": Vector2i(3, 3), "capacity": 12, "duration": 82, "price": 8,
		"appeal": 32, "upkeep": 52, "moving_parts": 24},
	{"id": "pirate_ship", "name": "STURMSCHIFF", "kind": "ride", "cost": 1050,
		"size": Vector2i(3, 3), "capacity": 14, "duration": 88, "price": 9,
		"appeal": 34, "upkeep": 58, "moving_parts": 19},
	{"id": "haunted", "name": "SPUKVILLA", "kind": "ride", "cost": 1260,
		"size": Vector2i(3, 3), "capacity": 8, "duration": 118, "price": 11,
		"appeal": 40, "upkeep": 67, "moving_parts": 13},
	{"id": "snack", "name": "KNUSPERBUDE", "kind": "shop", "cost": 190,
		"size": Vector2i(2, 1), "capacity": 2, "duration": 12, "price": 4,
		"appeal": 6, "upkeep": 14, "need": "hunger", "moving_parts": 5},
	{"id": "drinks", "name": "BRAUSESTAND", "kind": "shop", "cost": 170,
		"size": Vector2i(2, 1), "capacity": 2, "duration": 10, "price": 3,
		"appeal": 5, "upkeep": 12, "need": "thirst", "moving_parts": 6},
	{"id": "toilet", "name": "WASCHHAUS", "kind": "service", "cost": 220,
		"size": Vector2i(2, 1), "capacity": 2, "duration": 16, "price": 1,
		"appeal": 3, "upkeep": 18, "need": "toilet", "moving_parts": 4},
	{"id": "bench", "name": "PARKBANK", "kind": "service", "cost": 45,
		"size": Vector2i(1, 1), "capacity": 2, "duration": 30, "price": 0,
		"appeal": 2, "upkeep": 1, "need": "energy", "moving_parts": 2},
	{"id": "flowers", "name": "BLUMENINSEL", "kind": "decor", "cost": 65,
		"size": Vector2i(1, 1), "capacity": 0, "duration": 0, "price": 0,
		"appeal": 8, "upkeep": 2, "moving_parts": 8},
	{"id": "icecream", "name": "EISWAGEN", "kind": "shop", "cost": 210,
		"size": Vector2i(2, 1), "capacity": 2, "duration": 12, "price": 4,
		"appeal": 8, "upkeep": 14, "need": "hunger", "moving_parts": 5},
	{"id": "souvenir", "name": "ANDENKEN", "kind": "shop", "cost": 260,
		"size": Vector2i(2, 1), "capacity": 2, "duration": 14, "price": 6,
		"appeal": 10, "upkeep": 17, "need": "fun", "moving_parts": 7},
	{"id": "firstaid", "name": "SANITÄTER", "kind": "service", "cost": 300,
		"size": Vector2i(2, 1), "capacity": 2, "duration": 20, "price": 2,
		"appeal": 4, "upkeep": 24, "need": "nausea", "moving_parts": 5},
	{"id": "arcade", "name": "SPIELHALLE", "kind": "shop", "cost": 390,
		"size": Vector2i(2, 1), "capacity": 3, "duration": 24, "price": 5,
		"appeal": 14, "upkeep": 25, "need": "fun", "moving_parts": 9},
	{"id": "tree", "name": "PARKBAUM", "kind": "decor", "cost": 80,
		"size": Vector2i(1, 1), "capacity": 0, "duration": 0, "price": 0,
		"appeal": 10, "upkeep": 2, "moving_parts": 2},
	{"id": "wall", "name": "PARKMAUER", "kind": "decor", "cost": 35,
		"size": Vector2i(1, 1), "capacity": 0, "duration": 0, "price": 0,
		"appeal": 3, "upkeep": 1, "moving_parts": 2},
	{"id": "lamp", "name": "PARKLAMPE", "kind": "decor", "cost": 55,
		"size": Vector2i(1, 1), "capacity": 0, "duration": 0, "price": 0,
		"appeal": 6, "upkeep": 2, "moving_parts": 2},
	{"id": "fountain", "name": "SPRINGBRUNNEN", "kind": "decor", "cost": 180,
		"size": Vector2i(2, 2), "capacity": 0, "duration": 0, "price": 0,
		"appeal": 18, "upkeep": 9, "moving_parts": 6},
	{"id": "janitor", "name": "HAUSMEISTER", "kind": "staff", "cost": 120,
		"wage": 22, "role": "janitor", "icon": "H"},
	{"id": "mechanic", "name": "TECHNIKER", "kind": "staff", "cost": 180,
		"wage": 32, "role": "mechanic", "icon": "T"},
	{"id": "demolish", "name": "ABRISS", "kind": "tool", "cost": 0, "icon": "X"},
]

const SCENARIOS: Array[Dictionary] = [
	{
		"id": "sommerwiese",
		"name": "DIE SOMMERWIESE",
		"subtitle": "Vom Festplatz zum Lieblingspark",
		"start_money": 2800,
		"goal_day": 14,
		"goal_reputation": 68,
		"goal_cash": 3500,
		"goal_visits": 120,
		"seed": 199_406,
	},
	{
		"id": "flussbogen",
		"name": "AM FLUSSBOGEN",
		"subtitle": "Wasser, Wetter und enge Wege",
		"start_money": 2400,
		"goal_day": 18,
		"goal_reputation": 72,
		"goal_cash": 4200,
		"goal_visits": 180,
		"seed": 199_407,
	},
	{
		"id": "lichternacht",
		"name": "LICHTERNACHT",
		"subtitle": "Ein Abendpark für die ganze Stadt",
		"start_money": 3300,
		"goal_day": 21,
		"goal_reputation": 78,
		"goal_cash": 6000,
		"goal_visits": 260,
		"seed": 199_408,
	},
]

const GUEST_SHIRTS := [
	Color8(204, 68, 34), Color8(238, 102, 34), Color8(255, 204, 51),
	Color8(34, 153, 187), Color8(51, 204, 221), Color8(102, 68, 153),
	Color8(170, 85, 170), Color8(85, 136, 51),
]
const GUEST_SKINS := [
	Color8(255, 204, 153), Color8(221, 170, 119), Color8(187, 136, 85),
	Color8(153, 102, 68), Color8(102, 68, 51),
]
const GUEST_HAIR := [
	Color8(34, 17, 17), Color8(68, 34, 17), Color8(119, 68, 34),
	Color8(204, 153, 68), Color8(17, 17, 34), Color8(153, 51, 34),
]


static func item(id: String) -> Dictionary:
	for definition: Dictionary in ITEMS:
		if str(definition["id"]) == id:
			return definition.duplicate(true)
	return {}


static func item_index(id: String) -> int:
	for index in ITEMS.size():
		if str(ITEMS[index]["id"]) == id:
			return index
	return -1


static func buildable_ids() -> Array[String]:
	var ids: Array[String] = []
	for definition: Dictionary in ITEMS:
		ids.append(str(definition["id"]))
	return ids


static func scenario(id: String) -> Dictionary:
	for definition: Dictionary in SCENARIOS:
		if str(definition["id"]) == id:
			return definition.duplicate(true)
	return SCENARIOS[0].duplicate(true)


static func is_ride(id: String) -> bool:
	return str(item(id).get("kind", "")) == "ride"


static func is_venue(id: String) -> bool:
	return str(item(id).get("kind", "")) in ["ride", "shop", "service"]
