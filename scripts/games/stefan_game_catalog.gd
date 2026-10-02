class_name StefanGameCatalog
extends RefCounted
## Zentrale Wahrheit fuer die 27 wiederkehrenden Stefan-Spiele. Quest, Markt,
## Diskettenlauncher und Vollspiel lesen dieselben IDs statt eigene Tabellen zu
## pflegen. Das JSON enthaelt nur Content; ausfuehrbarer Code bleibt whitelistet.

const CONFIG := "res://data/stefan_games.json"
const EXPECTED_FIRST_YEAR := 1991
const EXPECTED_LAST_YEAR := 1999
const GAMES_PER_YEAR := 3

static var _loaded := false
static var _games: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _by_quest: Dictionary = {}


static func reload() -> void:
	_loaded = true
	_games = []
	_by_id = {}
	_by_quest = {}
	if not FileAccess.file_exists(CONFIG):
		push_error("StefanGameCatalog: %s fehlt." % CONFIG)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not parsed is Dictionary:
		push_error("StefanGameCatalog: ungueltiges JSON.")
		return
	for raw: Variant in (parsed as Dictionary).get("games", []):
		if not raw is Dictionary:
			continue
		var definition: Dictionary = (raw as Dictionary).duplicate(true)
		var id := str(definition.get("software_id", ""))
		var quest_id := str(definition.get("quest_id", ""))
		if id.is_empty() or quest_id.is_empty() or _by_id.has(id) or _by_quest.has(quest_id):
			push_warning("StefanGameCatalog: doppelte/leere ID bei %s/%s." % [id, quest_id])
			continue
		_games.append(definition)
		_by_id[id] = definition
		_by_quest[quest_id] = definition


static func _ensure() -> void:
	if not _loaded:
		reload()


static func all() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for definition: Dictionary in _games:
		out.append(definition.duplicate(true))
	return out


static func ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for definition: Dictionary in _games:
		out.append(str(definition.get("software_id", "")))
	out.sort()
	return out


static func has(software_id: String) -> bool:
	_ensure()
	return _by_id.has(software_id)


static func game(software_id: String) -> Dictionary:
	_ensure()
	return (_by_id.get(software_id, {}) as Dictionary).duplicate(true)


static func game_for_quest(quest_id: String) -> Dictionary:
	_ensure()
	return (_by_quest.get(quest_id, {}) as Dictionary).duplicate(true)


static func games_for_year(year: int) -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for definition: Dictionary in _games:
		if int(definition.get("year", 0)) == year:
			out.append(definition.duplicate(true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slot", 0)) < int(b.get("slot", 0)))
	return out


static func completion_action(software_id: String) -> String:
	return "amiga_game_completed:%s" % software_id


static func delivery_action(software_id: String) -> String:
	return "deliver_stefan_game:%s" % software_id


static func _autoload(name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath("/root/" + name))


## Aus derselben Spieldefinition entstehen die 27 Questketten. Damit koennen
## Titel-ID, physische Diskette, Startaktion und Uebergabe nie auseinanderlaufen.
## Der handkuratierte 60-Wochen-Director bestimmt weiterhin den Startzeitpunkt.
static func quest_definitions() -> Array[Dictionary]:
	_ensure()
	var quests: Array[Dictionary] = []
	for definition: Dictionary in _games:
		var software_id := str(definition.get("software_id", ""))
		var template_id := str(definition.get("disk_template_id", ""))
		var quest_id := str(definition.get("quest_id", ""))
		var title := str(definition.get("title", software_id))
		var objective := str(definition.get("objective", "Mission erfolgreich abschliessen"))
		var year := int(definition.get("year", 1991))
		var slot := int(definition.get("slot", 1))
		var payment := 10 + slot * 2 + floori(float(year - 1991) / 3.0) * 2
		var payment_source := "Stefan zahlt %d DM, ersetzt deine Leerdiskette und behaelt nur die Arbeitskopie. Das Original bleibt bei dir. Weitere eigene Kopien kannst du separat am Club-Tauschtisch oder auf deiner Flohmarktdecke verkaufen."
		var rewards: Array[Dictionary] = [
			{"type": "money", "value": payment},
			{"type": "disk_template", "id": "disk_blank_dd",
				"memory": "Von Stefan als Ersatz fuer die Arbeitskopie von %s bekommen" % title,
				"memory_key": "quest.dynamic.stefan_game.blank_memory",
				"memory_source": "Von Stefan als Ersatz fuer die Arbeitskopie von %s bekommen",
				"memory_args": [title]},
			{"type": "npc_trust", "npc": "npc_stefan", "value": 1},
			{"type": "flag", "flag": "stefan_game_delivered:%s" % software_id, "value": true},
			{"type": "toast", "text": payment_source % payment,
				"text_key": "game.stefan_game_catalog.stefan_zahlt_d_dm_ersetzt_deine",
				"text_source": payment_source, "text_args": [payment]},
		]
		var plan_source := "Stefans Plan: 1 Original am Flohmarkt finden → 2 Spielauftrag schaffen → 3 mit X-COPY eine Arbeitskopie ziehen → 4 Stefan die Kopie persoenlich bringen. %s bleibt als Original bei dir."
		var start_effects: Array[Dictionary] = [{"type": "toast",
			"text": plan_source % title,
			"text_key": "quest.dynamic.stefan_game.plan",
			"text_source": plan_source, "text_args": [title]}]
		if year == EXPECTED_FIRST_YEAR and slot == 1:
			var trilogy_source := "Stefan: »Drei Spiele pro Sommer — deine Originale bleiben bei dir. Wenn die kleine Box voll wird, hat Gruber zusaetzliche 12er-Boxen.«"
			start_effects.append({"type": "toast", "text": trilogy_source,
				"text_key": "quest.dynamic.stefan_game.trilogy_rule",
				"text_source": trilogy_source})
		if slot == GAMES_PER_YEAR:
			rewards.insert(rewards.size() - 1,
				{"type": "flag", "flag": "stefan_trilogy_%d_complete" % year, "value": true})
			rewards.insert(rewards.size() - 1, {
				"type": "memory_once", "id": "stefan_trilogy_%d" % year,
				"title": "Stefans Spiele-Sommer %d" % year,
				"title_key": "quest.dynamic.stefan_game.trilogy_title",
				"title_source": "Stefans Spiele-Sommer %d", "title_args": [year],
				"text": Loc.t("game.stefan_game_catalog.mit_stefan_alle_drei_spiele_des", "mit Stefan alle drei Spiele des Sommers %d gesucht, durchgespielt und als saubere Arbeitskopien weitergegeben") % year,
				"text_key": "game.stefan_game_catalog.mit_stefan_alle_drei_spiele_des",
				"text_source": "mit Stefan alle drei Spiele des Sommers %d gesucht, durchgespielt und als saubere Arbeitskopien weitergegeben",
				"text_args": [year],
			})
		quests.append({
			"id": quest_id,
			"title": "Stefans Spielwunsch: %s" % title,
			"localization_context": {"family": "stefan_game", "title": title,
				"software_id": software_id, "objective": objective},
			"giver": "npc_stefan",
			# Die handkuratierte Woche bestimmt den fruehesten Start. Ein einmal
			# angebotener Spielewunsch bleibt danach als Story-Backlog erhalten;
			# sonst wuerde ein Jahressprung Original, Test oder Arbeitskopie zu
			# einem unloesbaren Auftrag machen.
			"prereq": {"year_min": year},
			"on_start": start_effects,
			"required_disks": [
				{
					"id": template_id, "from_stage": 1, "through_stage": 3,
					"source_only": true, "grant_missing": false,
					"protect_text": "Diese Spielquelle brauchst du noch fuer Stefans Auftrag »%s«." % title,
					"protect_text_key": "quest.dynamic.stefan_game.source_protect",
					"protect_text_source": "Diese Spielquelle brauchst du noch fuer Stefans Auftrag »%s«.",
					"protect_text_args": [title],
				},
				{
					"id": template_id, "from_stage": 3, "through_stage": 3,
					"player_copy_only": true,
					"uid_flag": "stefan_delivery_disk:%s" % software_id,
					"grant_missing": false,
					"protect_text": "Diese konkrete Arbeitskopie ist fuer Stefan reserviert. Weitere eigene Kopien kannst du separat verkaufen.",
					"protect_text_key": "quest.dynamic.stefan_game.copy_protect",
					"protect_text_source": "Diese konkrete Arbeitskopie ist fuer Stefan reserviert. Weitere eigene Kopien kannst du separat verkaufen.",
				},
			],
			"stages": [
				{"desc": "BESORGEN — Finde das Original von %s auf dem Flohmarkt. Krause legt den Titel waehrend dieses Auftrags garantiert zurueck. Danach folgt der eigene Testlauf." % title,
					"map_location": "flea_market", "goal": {"has_template": template_id}},
				{"desc": "TESTEN — Starte %s zuhause am Amiga. SPIELZIEL: %s. Der Ergebnisbildschirm registriert den Sieg; danach verlangt Stefan eine X-COPY-Arbeitskopie." % [title, objective],
					"map_location": "room", "goal": {"action": completion_action(software_id)}},
				{"desc": "KOPIEREN — Das Original bleibt in deiner Sammlung. Starte X-COPY und erstelle auf einer Leerdiskette eine eigene Arbeitskopie von %s." % title,
					"map_location": "room", "goal": {"has_player_copy_of": software_id}},
				{"desc": "UEBERGEBEN — Bring Stefan nur die selbst erstellte Arbeitskopie von %s persoenlich in sein Zimmer. Weitere Verkaufskopien fuer Club oder Flohmarkt sind optional und gehoeren nicht in seine Hand." % title,
					"map_location": "friend_cellar", "goal": {"action": delivery_action(software_id)}},
			],
			"reward": rewards,
			"quest_family": "stefan_games",
		})
	return quests


## Aktive Stufe 0 wird am Flohmarkt garantiert angeboten. Das ist absichtlich
## read-only; FleaMarketManager entscheidet weiterhin ueber Preis und Angebot.
static func acquisition_requests() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	var quests := _autoload("QuestManager")
	if quests == null:
		return out
	for definition: Dictionary in _games:
		var quest_id := str(definition.get("quest_id", ""))
		if bool(quests.call("is_active", quest_id)) and int(quests.call("stage", quest_id)) == 0:
			out.append(definition.duplicate(true))
	return out


## Liefert die erste wirklich abgabebereite Arbeitskopie. In normalen Runs ist
## nur eine Kette offen; bei alten Backlog-Saves gewinnt chronologisch die
## aelteste. Originale/Master werden niemals als Abgabe vorgeschlagen.
static func active_delivery() -> Dictionary:
	_ensure()
	var candidates: Array[Dictionary] = []
	var quests := _autoload("QuestManager")
	var disks := _autoload("DiskManager")
	if quests == null or disks == null:
		return {}
	for definition: Dictionary in _games:
		var quest_id := str(definition.get("quest_id", ""))
		var software_id := str(definition.get("software_id", ""))
		if bool(quests.call("is_active", quest_id)) and int(quests.call("stage", quest_id)) == 3 \
				and bool(disks.call("has_player_copy_of", software_id)):
			candidates.append(definition)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := int(a.get("year", 0)); var by := int(b.get("year", 0))
		return int(a.get("slot", 0)) < int(b.get("slot", 0)) if ay == by else ay < by)
	return candidates[0].duplicate(true)


## Atomare persoenliche Uebergabe: nur eine vom Spieler erzeugte Kopie wird
## entfernt; danach erst wird die Questaktion verbucht. Ohne Kopie kein Zustand.
static func deliver_active_copy() -> Dictionary:
	var definition := active_delivery()
	if definition.is_empty():
		return {"ok": false, "text": Loc.t("game.stefan_game_catalog.du_hast_gerade_keine_fertige_arbeitskopie", "Du hast gerade keine fertige Arbeitskopie fuer Stefan dabei.")}
	var software_id := str(definition.get("software_id", ""))
	var disks := _autoload("DiskManager")
	var quests := _autoload("QuestManager")
	if disks == null or quests == null:
		return {"ok": false, "text": Loc.t("game.stefan_game_catalog.quest_oder_diskettenverwaltung_ist_nicht_verfuegbar", "Quest- oder Diskettenverwaltung ist nicht verfuegbar.")}
	var copies: Array = disks.call("player_copies_of", software_id)
	if copies.is_empty():
		return {"ok": false, "text": Loc.t("game.stefan_game_catalog.arbeitskopie_fehlt", "Die Arbeitskopie fehlt.")}
	copies.sort_custom(func(a: Disk, b: Disk) -> bool:
		if a.condition != b.condition:
			return a.condition < b.condition
		return a.uid < b.uid)
	var handed: Disk = copies[0]
	disks.call("remove_disk", handed)
	quests.call("note_action", delivery_action(software_id))
	return {
		"ok": true,
		"title": str(definition.get("title", software_id)),
		"software_id": software_id,
		"quest_id": str(definition.get("quest_id", "")),
		"condition": handed.condition,
		"text": Loc.t("game.stefan_game_catalog.stefan_nimmt_blaue_arbeitskopie_von_s", "Stefan nimmt die blaue Arbeitskopie von »%s«, prueft das Etikett und legt sie sofort ein.") \
			% str(definition.get("title", software_id)),
	}


static func atlas_region(definition: Dictionary, texture_size: Vector2) -> Rect2:
	var cell: Array = definition.get("atlas_cell", [0, 0])
	var col := clampi(int(cell[0]) if cell.size() > 0 else 0, 0, 2)
	var row := clampi(int(cell[1]) if cell.size() > 1 else 0, 0, 2)
	var cell_size := texture_size / 3.0
	# Generierte Atlanten besitzen harte schwarze Stege. Acht Pixel Abstand in
	# der Quellaufloesung verhindert, dass Nachbarzellen ins Vollbild bluten.
	var inset := Vector2(8.0, 8.0)
	return Rect2(Vector2(col, row) * cell_size + inset, cell_size - inset * 2.0)


static func validate() -> Array[String]:
	_ensure()
	var issues: Array[String] = []
	if _games.size() != (EXPECTED_LAST_YEAR - EXPECTED_FIRST_YEAR + 1) * GAMES_PER_YEAR:
		issues.append("Erwartet 27 Spiele, gefunden %d." % _games.size())
	for year in range(EXPECTED_FIRST_YEAR, EXPECTED_LAST_YEAR + 1):
		var year_games := games_for_year(year)
		if year_games.size() != GAMES_PER_YEAR:
			issues.append("%d: erwartet 3 Spiele, gefunden %d." % [year, year_games.size()])
		var slots: Array[int] = []
		for definition: Dictionary in year_games:
			slots.append(int(definition.get("slot", 0)))
			for key in ["software_id", "disk_template_id", "quest_id", "title", "mode", "atlas"]:
				if str(definition.get(key, "")).is_empty():
					issues.append("%d/%s: Feld %s fehlt." % [year, definition.get("software_id", "?"), key])
			var atlas_path := str(definition.get("atlas", ""))
			if not atlas_path.is_empty() and not ResourceLoader.exists(atlas_path):
				issues.append("%s: Atlas fehlt: %s" % [definition.get("software_id", "?"), atlas_path])
		if slots != [1, 2, 3]:
			issues.append("%d: Slots muessen 1,2,3 sein (ist %s)." % [year, str(slots)])
	return issues
