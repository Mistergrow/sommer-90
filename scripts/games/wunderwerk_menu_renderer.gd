extends RefCounted
## Statische OCS-Menüpräsentation. Der Hauptcontroller entscheidet nur noch,
## welcher Bildschirm aktiv ist; Layout und Typografie leben hier gemeinsam.

const Catalog := preload("res://scripts/games/wunderwerk_catalog.gd")
const AmigaPresentation := preload("res://scripts/games/amiga_game_presentation.gd")
const TITLE_ART := preload(
	"res://assets/ui/games/wunderwerk_94/title_background_ocs_v01.png")
const TOPAZ: Font = preload("res://assets/fonts/Topaz_a500_ui.ttf")

const VW := 320.0
const VH := 256.0
const INK := Color8(0, 0, 17)
const NAVY := Color8(0, 17, 51)
const PANEL := Color8(0, 34, 51)
const LINE := Color8(34, 153, 187)
const WHITE := Color8(238, 238, 221)
const CREAM := Color8(255, 238, 187)
const DIM := Color8(187, 153, 102)
const AMBER := Color8(255, 204, 51)
const RED := Color8(204, 68, 34)
const GREEN := Color8(119, 153, 51)
const CYAN := Color8(51, 204, 221)


static func draw_boot(canvas: CanvasItem, boot_time: float) -> void:
	if boot_time < 0.72:
		AmigaPresentation.draw_disk_boot(canvas, Vector2(VW, VH), boot_time, 0.72,
			AMBER, "WUNDERWERK 94")
		return
	var phase := boot_time - 0.72
	canvas.draw_rect(Rect2(0, 0, VW, VH), INK)
	_text(canvas, "LICHTWERK SPIELE", Rect2(0, 72, VW, 20), 90, 14, AMBER,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "OCS · 1 MB CHIP-RAM · A600", Rect2(0, 100, VW, 12),
		110, 7, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "PARKDATEN WERDEN GELADEN", Rect2(0, 145, VW, 10),
		153, 7, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	var width := clampf(phase / 0.75, 0.0, 1.0) * 160.0
	canvas.draw_rect(Rect2(80, 166, 160, 5), PANEL)
	canvas.draw_rect(Rect2(81, 167, maxf(0.0, width - 2.0), 3), GREEN)


static func draw_title(canvas: CanvasItem, menu_index: int, has_save: bool) -> void:
	canvas.draw_texture_rect(TITLE_ART, Rect2(0, 0, VW, VH), false)
	canvas.draw_rect(Rect2(0, 0, VW, 64), Color(0, 0, 0.067, 0.78))
	canvas.draw_rect(Rect2(0, 184, VW, 72), Color(0, 0, 0.067, 0.84))
	_text(canvas, "WUNDERWERK '94", Rect2(0, 8, VW, 28), 31, 22, AMBER,
		HORIZONTAL_ALIGNMENT_CENTER, 2, RED)
	_text(canvas, "PARKDIREKTOR", Rect2(0, 37, VW, 16), 50, 11, WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, 1, NAVY)
	var entries := [
		"NEUER PARK",
		"FORTSETZEN" if has_save else "FORTSETZEN - LEER",
		"HANDBUCH", "REKORDE", "DISK AUSWERFEN",
	]
	for index in entries.size():
		var y := 194.0 + index * 11.0
		if index == menu_index:
			canvas.draw_rect(Rect2(76, y - 8, 168, 10), Color(PANEL, 0.92))
			_text(canvas, "> %s <" % entries[index], Rect2(76, y - 9, 168, 11),
				y, 8, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			_text(canvas, entries[index], Rect2(76, y - 9, 168, 11),
				y, 8, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "(C) 1994 LICHTWERK · ORIGINAL OCS", Rect2(2, 248, 316, 7),
		254, 5, DIM, HORIZONTAL_ALIGNMENT_CENTER)


static func draw_scenarios(canvas: CanvasItem, scenario_index: int) -> void:
	canvas.draw_texture_rect(TITLE_ART, Rect2(0, 0, VW, VH), false)
	canvas.draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0.067, 0.76))
	_header(canvas, "PARKVERTRAG WÄHLEN", "JEDER ORT HAT EIN EIGENES ZIEL")
	for index in Catalog.SCENARIOS.size():
		var definition: Dictionary = Catalog.SCENARIOS[index]
		var rect := Rect2(16, 48 + index * 55, 288, 46)
		var selected := index == scenario_index
		canvas.draw_rect(rect, Color(PANEL, 0.96))
		canvas.draw_rect(rect, AMBER if selected else LINE, false,
			2.0 if selected else 1.0)
		_text(canvas, ("%d  " % (index + 1)) + str(definition["name"]),
			rect.grow(-7), rect.position.y + 14, 10,
			AMBER if selected else WHITE)
		_text(canvas, str(definition["subtitle"]).to_upper(), rect.grow(-7),
			rect.position.y + 27, 6, CREAM)
		_text(canvas, "START %d DM · TAG %d · RUF %d" % [
			int(definition["start_money"]), int(definition["goal_day"]),
			int(definition["goal_reputation"])],
			rect.grow(-7), rect.position.y + 39, 6, CYAN)
	_text(canvas, "↑↓ AUSWAHL · ENTER VERTRAG UNTERSCHREIBEN · ESC ZURÜCK",
		Rect2(4, 242, 312, 10), 250, 6, DIM, HORIZONTAL_ALIGNMENT_CENTER)


static func draw_manual(canvas: CanvasItem, page: int) -> void:
	_panel_screen(canvas, "HANDBUCH · SEITE %d/4" % (page + 1))
	var pages := [
		["PARKBAU",
			"WEGE VERBINDEN DEN EINGANG MIT ALLEN BETRIEBEN.",
			"WARTEGATTER BAUEN ECHTE QUEUE-SPUREN VOR ATTRAKTIONEN.",
			"LINKSKLICK BAUT. ABRISS ENTFERNT WEGE UND GEBÄUDE.",
			"TAB ODER Q/E WECHSELT DAS BAUWERKZEUG."],
		["GÄSTE & ANIMATION",
			"JEDER GAST HAT GELD, GEDULD UND EIGENE BEDÜRFNISSE.",
			"LAUFEN, WARTEN, FAHREN, ESSEN UND JUBELN SIND ECHTE ZUSTÄNDE.",
			"KLONE GIBT ES NICHT: KÖRPER, FARBE UND TEMPO VARIIEREN.",
			"SCHLECHTE WEGE ODER PREISE MACHEN BESUCHER UNZUFRIEDEN."],
		["BETRIEB",
			"F2 ZEIGT TAGESBILANZ, KOSTEN UND SZENARIOZIELE.",
			"ANSEHEN + KLICK WÄHLT EINEN BETRIEB.",
			"+/- ÄNDERT PREISE, O SCHLIESST ODER ÖFFNET.",
			"HAUSMEISTER REINIGEN, TECHNIKER REPARIEREN DEFEKTE."],
		["STEUERUNG",
			"PFEILE: BAUCURSOR · SHIFT+PFEILE: KAMERA · B: BAUMENÜ.",
			"MAUS: MENÜ UND FELD DIREKT ANKLICKEN.",
			"F5 SPEICHERT DEN VOLLSTÄNDIGEN PARKZUSTAND.",
			"ESC PAUSIERT. REDUCED FX RESPEKTIERT DIE SPIELOPTION."],
	]
	var lines: Array = pages[page]
	_text(canvas, str(lines[0]), Rect2(18, 48, 284, 20), 64, 14, AMBER,
		HORIZONTAL_ALIGNMENT_CENTER)
	for index in range(1, lines.size()):
		_text(canvas, str(lines[index]), Rect2(22, 82 + (index - 1) * 32, 276, 24),
			95 + (index - 1) * 32, 7, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "← → SEITE · ESC ZURÜCK", Rect2(0, 240, VW, 10),
		249, 6, DIM, HORIZONTAL_ALIGNMENT_CENTER)


static func draw_finances(canvas: CanvasItem, model) -> void:
	_panel_screen(canvas, "PARKBÜRO · TAG %02d" % model.day)
	var upkeep := 0
	for object: Dictionary in model.objects:
		upkeep += int(Catalog.item(str(object["type"])).get("upkeep", 0))
	var wages := 0
	for worker: Dictionary in model.staff:
		wages += int(Catalog.item(str(worker["role"])).get("wage", 0))
	var rows := [
		["BARGELD", "%d DM" % model.money],
		["HEUTE EINGENOMMEN", "%d DM" % model.daily_revenue],
		["BETRIEBSKOSTEN/TAG", "%d DM" % upkeep],
		["LÖHNE/TAG", "%d DM" % wages],
		["BESUCHE GESAMT", str(model.total_visits)],
		["FAHRTEN GESAMT", str(model.total_rides)],
		["SAUBERKEIT", "%d%%" % model.cleanliness],
		["PARKRUF", "%d/100" % model.reputation],
	]
	for index in rows.size():
		var y := 50.0 + index * 18.0
		_text(canvas, str(rows[index][0]), Rect2(24, y, 176, 14),
			y + 10, 7, WHITE)
		_text(canvas, str(rows[index][1]), Rect2(198, y, 98, 14), y + 10, 8,
			GREEN if index < 2 else CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	var goal: Dictionary = model.scenario
	_text(canvas, "ZIEL TAG %d: %d DM · RUF %d · %d BESUCHE" % [
		int(goal.get("goal_day", 14)), int(goal.get("goal_cash", 3500)),
		int(goal.get("goal_reputation", 68)), int(goal.get("goal_visits", 120))],
		Rect2(12, 214, 296, 12), 224, 6, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "ESC ZURÜCK ZUM PARK", Rect2(0, 240, VW, 10),
		249, 6, DIM, HORIZONTAL_ALIGNMENT_CENTER)


static func draw_records(canvas: CanvasItem, record: Dictionary) -> void:
	_panel_screen(canvas, "DIREKTOREN-ARCHIV")
	var values := [
		["PARKS GELEITET", int(record.get("plays", 0))],
		["VERTRÄGE ERFÜLLT", int(record.get("completions", 0))],
		["BESTER PARKWERT", int(record.get("best_score", 0))],
		["LETZTER PARKWERT", int(record.get("last_score", 0))],
	]
	for index in values.size():
		var y := 70.0 + index * 29.0
		_text(canvas, str(values[index][0]), Rect2(35, y, 170, 16),
			y + 11, 8, WHITE)
		_text(canvas, str(values[index][1]), Rect2(205, y, 78, 16),
			y + 11, 10, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(canvas, "ESC ZURÜCK", Rect2(0, 240, VW, 10), 249, 6, DIM,
		HORIZONTAL_ALIGNMENT_CENTER)


static func draw_pause(canvas: CanvasItem) -> void:
	canvas.draw_rect(Rect2(58, 74, 204, 108), Color(INK, 0.97))
	canvas.draw_rect(Rect2(58, 74, 204, 108), AMBER, false, 2.0)
	_text(canvas, "PARK PAUSIERT", Rect2(58, 86, 204, 22), 104, 14, AMBER,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "ENTER WEITER", Rect2(58, 122, 204, 12), 132, 8, WHITE,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "F5 SPEICHERN · ESC HAUPTMENÜ", Rect2(58, 147, 204, 12),
		157, 6, CREAM, HORIZONTAL_ALIGNMENT_CENTER)


static func draw_results(canvas: CanvasItem, model) -> void:
	canvas.draw_texture_rect(TITLE_ART, Rect2(0, 0, VW, VH), false)
	canvas.draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0.067, 0.82))
	var title := "VERTRAG ERFÜLLT" if model.won else "VERTRAG BEENDET"
	_text(canvas, title, Rect2(0, 30, VW, 28), 54, 20,
		AMBER if model.won else RED, HORIZONTAL_ALIGNMENT_CENTER, 2, NAVY)
	_text(canvas, "PARKWERT %d" % model.score(), Rect2(0, 78, VW, 18),
		94, 12, WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var lines := [
		"TAG %d" % model.day,
		"%d BESUCHE · %d FAHRTEN" % [model.total_visits, model.total_rides],
		"%d DM · RUF %d · SAUBERKEIT %d" % [
			model.money, model.reputation, model.cleanliness],
	]
	for index in lines.size():
		_text(canvas, lines[index], Rect2(0, 116 + index * 20, VW, 14),
			127 + index * 20, 8, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "ENTER ZUM TITEL · F5 PARK ARCHIVIEREN",
		Rect2(0, 220, VW, 14), 232, 7, AMBER, HORIZONTAL_ALIGNMENT_CENTER)


static func draw_exit_confirm(canvas: CanvasItem) -> void:
	canvas.draw_rect(Rect2(56, 83, 208, 88), Color(INK, 0.97))
	canvas.draw_rect(Rect2(56, 83, 208, 88), RED, false, 2.0)
	_text(canvas, "DISK AUSWERFEN?", Rect2(56, 96, 208, 20), 112, 13, AMBER,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text(canvas, "ENTER JA · ESC NEIN", Rect2(56, 137, 208, 12),
		147, 7, WHITE, HORIZONTAL_ALIGNMENT_CENTER)


static func _panel_screen(canvas: CanvasItem, title: String) -> void:
	canvas.draw_rect(Rect2(0, 0, VW, VH), INK)
	for y in range(0, 256, 4):
		canvas.draw_line(Vector2(0, y), Vector2(VW, y),
			Color(0.0, 0.20, 0.20, 0.18), 1.0)
	_header(canvas, title, "WUNDERWERK '94 · PARKDIREKTOR")


static func _header(canvas: CanvasItem, title: String, subtitle: String) -> void:
	canvas.draw_rect(Rect2(0, 0, VW, 36), PANEL)
	canvas.draw_line(Vector2(0, 35), Vector2(VW, 35), LINE, 1.0)
	_text(canvas, title, Rect2(7, 5, 306, 16), 18, 11, AMBER)
	_text(canvas, subtitle, Rect2(7, 22, 306, 9), 30, 5, CYAN,
		HORIZONTAL_ALIGNMENT_RIGHT)


static func _text(canvas: CanvasItem, text: String, rect: Rect2, baseline: float,
		size_px: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT,
		outline := 0, outline_color := INK) -> void:
	if outline > 0:
		canvas.draw_string(TOPAZ,
			Vector2(rect.position.x + outline, baseline + outline), text,
			alignment, rect.size.x, size_px, Color(outline_color, 0.75))
	canvas.draw_string(TOPAZ, Vector2(rect.position.x, baseline), text,
		alignment, rect.size.x, size_px, color)
