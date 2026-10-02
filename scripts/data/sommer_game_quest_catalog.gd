class_name SommerGameQuestCatalog
extends RefCounted
## Kuratierte Jahresgeschichte der gemeinsam gebauten Sommer-Game-Engine.
## Jede Stufe entspricht genau einem realen Engine-Modul und einer echten
## Integrationshandlung in der Sommer-Game-Anwendung.

const Modules := preload("res://scripts/data/sommer_game_module_catalog.gd")

const YEAR_STORIES := {
	1990: {
		"title_de": "Das erste gemeinsame Spielgeruest", "title_en": "Our First Shared Game Framework",
		"intro_de": "Daniel hat den ersten Projektordner angelegt. Lisa bringt Klangideen mit – jetzt soll aus einzelnen Routinen eine gemeinsame Engine werden.",
		"intro_en": "Daniel has created the first project folder. Lisa brings sound ideas – now the separate routines must become one shared engine.",
		"quotes_de": ["Ich habe Start, Level und Spielstand getrennt. Wenn das haelt, muessen wir nie wieder bei null anfangen.", "Die Figur braucht Masken statt Glueck. Dann merkt das Spiel wirklich, was sie beruehrt.", "Vier Kanaele reichen – wenn Musik und Treffer sich nicht dauernd gegenseitig abschneiden."],
		"quotes_en": ["I separated start-up, levels and saves. If this holds, we never have to begin from zero again.", "The character needs masks, not luck. Then the game really knows what it touches.", "Four channels are enough – if music and impacts stop cutting each other off."],
	},
	1991: {
		"title_de": "Figuren mit Geschichte", "title_en": "Characters With a Story",
		"intro_de": "Lisa will nicht nur bewegte Figuren, sondern Szenen mit Erinnerung. Daniel besteht auf einem Debugger, bevor das Projekt groesser wird.",
		"intro_en": "Lisa wants more than moving figures: scenes with memory. Daniel insists on a debugger before the project grows.",
		"quotes_de": ["Eine Figur soll wissen, was vorher gesagt wurde. Sonst ist jede Szene nur eine Kulisse.", "Kein mysterioeser Absturz mehr. Wir halten Werte und Framekosten an, bevor sie uns davonlaufen."],
		"quotes_en": ["A character should remember what was said before. Otherwise every scene is only scenery.", "No more mysterious crashes. We stop values and frame costs before they run away from us."],
	},
	1992: {"title_de": "Mehr RAM, groessere Welten", "title_en": "More RAM, Larger Worlds",
		"intro_de": "Sven bringt eine ECS-Speicherkarte und einen Plan fuer Karten-Layer mit.", "intro_en": "Sven brings an ECS memory board and a plan for layered maps.",
		"quotes_de": ["Wir laden nicht mehr die ganze Welt als ein Bild. Kacheln, Layer, Banks – dann kann die Karte endlich scrollen."],
		"quotes_en": ["We stop loading the whole world as one picture. Tiles, layers, banks – then the map can finally scroll."]},
	1993: {"title_de": "Terrain, das wirklich nachgibt", "title_en": "Terrain That Actually Gives Way",
		"intro_de": "Daniel verbindet AGA, Festplatte und Fast-RAM zu einem reproduzierbaren Physikprojekt.", "intro_en": "Daniel combines AGA, hard disk and Fast RAM into a deterministic physics project.",
		"quotes_de": ["Die Explosion darf kein gemaltes Loch sein. Sie veraendert die Maske – und danach fallen Projektile und Figuren in die neue Form."],
		"quotes_en": ["An explosion must not be a painted hole. It changes the mask – then projectiles and actors react to its new shape."]},
	1994: {"title_de": "Simulation braucht eine Oberflaeche", "title_en": "Simulation Needs an Interface",
		"intro_de": "Lisa und Sven teilen sich einen Sommer: erst lesbare Fenster, dann eine Wirtschaft, deren Zahlen wirklich zusammenhaengen.", "intro_en": "Lisa and Sven share a summer: readable windows first, then an economy whose figures truly connect.",
		"quotes_de": ["Statusanzeigen sind Teil des Spiels. Wenn niemand die Lage lesen kann, ist die beste Simulation unsichtbar.", "Bevoelkerung und Geld laufen in festen Schritten. Gleiche Eingabe, gleiches Ergebnis – auch nach dem Laden."],
		"quotes_en": ["Status displays are part of the game. If nobody can read the situation, the best simulation is invisible.", "Population and money advance in fixed steps. Same input, same result – even after loading."]},
	1995: {"title_de": "Zwei Rechner, ein Zustand", "title_en": "Two Computers, One State",
		"intro_de": "Mike will Mehrspieler – aber ohne dass jeder Rechner nach wenigen Sekunden eine andere Welt sieht.", "intro_en": "Mike wants multiplayer – without every computer seeing a different world after seconds.",
		"quotes_de": ["Wir schicken Eingaben, nicht die ganze Welt. Wenn der Takt stimmt, sehen beide Rechner dasselbe Spiel."],
		"quotes_en": ["We send inputs, not the entire world. If the tick agrees, both machines see the same game."]},
	1996: {"title_de": "Die Stadt unter der Karte", "title_en": "The City Beneath the Map",
		"intro_de": "Sven verwandelt die Tilemap in ein Netz aus Zonen, Strom und Verkehr.", "intro_en": "Sven turns the tile map into a network of zones, power and traffic.",
		"quotes_de": ["Ein Haus ist nicht nur eine Kachel. Es braucht Strom, eine Strasse und einen Grund, warum dort jemand wohnen will."],
		"quotes_en": ["A house is not just a tile. It needs power, a road and a reason why somebody would live there."]},
	1997: {"title_de": "Mehr Farben, klare Pipeline", "title_en": "More Colours, a Clear Pipeline",
		"intro_de": "Lisa baut die Grafik nicht einfach groesser, sondern als saubere Pipeline fuer AGA und VGA.", "intro_en": "Lisa does not merely make graphics larger; she builds a clean AGA and VGA pipeline.",
		"quotes_de": ["Mehr Farben helfen nur, wenn Palette, Animation und Zielmodus zusammenpassen. Sonst wird aus AGA bloss buntes Chaos."],
		"quotes_en": ["More colours only help when palette, animation and target mode agree. Otherwise AGA becomes colourful chaos."]},
	1998: {"title_de": "Ein Build fuer die Welt", "title_en": "A Build for the World",
		"intro_de": "Mike verlangt nachvollziehbare Versionen fuer Disk, CD und den ersten Internet-Upload.", "intro_en": "Mike demands traceable versions for disk, CD and the first Internet upload.",
		"quotes_de": ["Wer etwas herunterlaedt, muss wissen, welche Dateien zusammengehoeren. Jeder Build bekommt Version, Manifest und Pruefsumme."],
		"quotes_en": ["Anyone downloading it must know which files belong together. Every build gets a version, manifest and checksum."]},
	1999: {"title_de": "Sommer Game 1.0", "title_en": "Sommer Game 1.0",
		"intro_de": "Zehn Sommer spaeter passen Projekte, Assets, Debugdaten und Builds endlich in einen gemeinsamen Kern.", "intro_en": "Ten summers later, projects, assets, debug data and builds finally fit one shared core.",
		"quotes_de": ["Wir haben nicht eine fertige Engine geschenkt bekommen. Wir haben sie zusammen gebaut – jetzt muss ein sauberer 1.0-Build beweisen, dass alles traegt."],
		"quotes_en": ["Nobody handed us a finished engine. We built it together – now a clean 1.0 build must prove that it all holds."]},
}


static func quest_id(year: int) -> String:
	return "q_sommer_game_%d" % year


static func quest_definitions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for year in range(1990, 2000):
		var modules: Array[Dictionary] = []
		for entry: Dictionary in Modules.all():
			if int(entry.get("year", 0)) == year:
				modules.append(entry)
		var story: Dictionary = YEAR_STORIES.get(year, {})
		var stages: Array[Dictionary] = []
		for index in modules.size():
			var module_id := str(modules[index].get("id", ""))
			stages.append({
				"desc": str((story.get("quotes_de", []) as Array)[index]),
				"map_location": "room",
				"goal": {"action": "sommer_game_integrate:%s" % module_id},
				"reward": [{"type": "sommer_game_module", "id": module_id}],
			})
		var prereq: Dictionary = {"year_min": year,
			"not_flag": "sommer_game_year_%d_complete" % year}
		if year == 1990:
			# Die 1990 verfuegbare Projekt- und Engine-Huelle darf das
			# Karton-/Boot-Tutorial nicht beim Spielstart verdraengen. Erst der
			# wirklich gestartete Amiga installiert SOMMER GAME; die eigentlichen
			# Engine-Module bleiben ausschliesslich Belohnungen ihrer Jahresstufen.
			prereq["flag"] = "booted_amiga"
		else:
			prereq["flag"] = "sommer_game_year_%d_complete" % (year - 1)
		out.append({
			"id": quest_id(year),
			"title": str(story.get("title_de", "Sommer Game %d" % year)),
			"giver": _giver_for(str(modules[0].get("lead", "team"))) if not modules.is_empty() else "npc_daniel",
			"prereq": prereq,
			"localization_context": {
				"family": "sommer_game", "year": year,
				"title_de": str(story.get("title_de", "Sommer Game")),
				"title_en": str(story.get("title_en", "Sommer Game")),
				"intro_de": str(story.get("intro_de", "")),
				"intro_en": str(story.get("intro_en", "")),
				"quotes_de": story.get("quotes_de", []),
				"quotes_en": story.get("quotes_en", []),
				"module_ids": modules.map(func(entry: Dictionary) -> String: return str(entry.get("id", ""))),
			},
			"on_start": ([{"type": "program", "id": "sommer_game"}] if year == 1990 else []) + [{
				"type": "toast",
				"text": str(story.get("intro_de", "")),
				"text_de": str(story.get("intro_de", "")),
				"text_en": str(story.get("intro_en", ""))}],
			"stages": stages,
			"reward": [
				{"type": "flag", "flag": "sommer_game_year_%d_complete" % year, "value": true},
				{"type": "stat", "stat": "wissen", "value": 1 if year < 1993 else 2},
				{"type": "memory_once", "id": "sommer_game_%d" % year,
					"title": "Sommer Game %d" % year,
					"title_de": "Sommer Game %d" % year,
					"title_en": "Sommer Game %d" % year,
					"text": Loc.t("misc.sommer_game_quest_catalog.s_gemeinsam_in_engine_integriert", "%s – gemeinsam in die Engine integriert") % ", ".join(
						modules.map(func(entry: Dictionary) -> String: return str(entry.get("name_de", "Modul")))),
					"text_de": "%s – gemeinsam in die Engine integriert" % ", ".join(
						modules.map(func(entry: Dictionary) -> String: return str(entry.get("name_de", "Modul")))),
					"text_en": "%s – integrated into the engine together" % ", ".join(
						modules.map(func(entry: Dictionary) -> String: return str(entry.get("name_en", "module"))))},
			],
			"quest_family": "sommer_game_engine",
		})
	return out


static func localized_text(value_de: String, value_en: String) -> String:
	return value_en if TranslationServer.get_locale().begins_with("en") else value_de


static func _giver_for(lead: String) -> String:
	return {"daniel": "npc_daniel", "lisa": "npc_lisa", "sven": "npc_sven",
		"mike": "npc_mike", "team": "npc_daniel"}.get(lead, "npc_daniel")
