class_name CodeRedScreenRenderer
extends RefCounted
## Zeichenlogik der dichten Unterseiten. Eingabe, Zustand und Trefferverwaltung
## bleiben beim CodeRedGame; dieser Baustein rendert ausschliesslich.

const Chrome := preload("res://scripts/games/code_red_chrome.gd")

## Gefahrenrampe der Weltkarte. Bewusst kleinschrittig: benachbarte Stufen
## liegen nah beieinander, damit der Rasterzeilen-Dither zwischen ihnen als
## Zwischenton liest und nicht als Muster.
const DANGER_RAMP: Array[Color] = [
	Color8(82, 222, 114),   # ruhig
	Color8(150, 214, 85),
	Color8(214, 200, 60),
	Color8(246, 168, 48),   # angespannt
	Color8(240, 110, 45),
	Color8(226, 67, 53),    # kritisch
]
const PROJECTS_ART := preload("res://assets/ui/games/code_red/projects_background_v02.png")
const OPTICS_ART := preload("res://assets/ui/games/code_red/optics_background_v02.png")
const CABINET_ART := preload("res://assets/ui/games/code_red/cabinet_background_v02.png")
const SKY_ARCHIVE_ART := preload("res://assets/ui/games/code_red/sky_archive_background_v02.png")

const WHITE := Color8(229, 232, 207)
const DIM := Color8(129, 157, 160)
const AMBER := Color8(246, 168, 48)
const RED := Color8(226, 67, 53)
const GREEN := Color8(82, 222, 114)
const CYAN := Color8(63, 210, 222)


static func draw_cabinet(canvas, model, menu_index: int) -> void:
	canvas._draw_cover(CABINET_ART, Rect2(0, 0, 320, 256))
	canvas.draw_rect(Rect2(0, 0, 320, 256), Color(0, 0, 0, 0.68))
	canvas._header("BERATERKABINETT", "%s · %d BEFEHLE" % [model.period_label(), model.commands_left])
	var catalog: Array = model.advisor_catalog()
	for i in catalog.size():
		var advisor: Dictionary = catalog[i]
		var advisor_status := str(advisor.get("status", "ACTIVE"))
		var lead: bool = str(advisor.get("id", "")) == model.lead_advisor_id
		# Ressort und Name gehoeren auf dieselbe Karte. Vorher schwebte der Name
		# als freier Text unter der Taste auf der Bildkunst — auf 32 Registern
		# war er dort kaum lesbar und lag optisch auf der Rahmenlinie.
		canvas._menu_card(Rect2(8, 45 + i * 30, 112, 27),
			"%s%s" % ["* " if lead else "", str(advisor.get("role", ""))],
			str(advisor.get("name", "")), i, i == menu_index,
			advisor_status != "DEFECTED", 8, 6)
	if catalog.is_empty():
		return
	var selected: Dictionary = catalog[clampi(menu_index, 0, catalog.size() - 1)]
	canvas._panel(Rect2(128, 45, 184, 159))
	canvas._text(str(selected.get("name", "")), 137, 63, 11, AMBER)
	canvas._text("%s · RISIKO %s" % [str(selected.get("role", "")),
		str(selected.get("risk", ""))], 137, 76, 7, DIM)
	canvas._text("KOMPETENZ", 137, 94, 7, WHITE)
	canvas._bar(Rect2(202, 87, 98, 7), float(selected.get("competence", 0.0)), CYAN)
	canvas._text("LOYALITAET", 137, 110, 7, WHITE)
	canvas._bar(Rect2(202, 103, 98, 7), float(selected.get("loyalty", 0.0)), GREEN)
	var selected_status := str(selected.get("status", "ACTIVE"))
	canvas._text("STATUS: %s" % selected_status, 137, 127, 8,
		RED if selected_status == "DEFECTED" else GREEN)
	var advice: Dictionary = model.advisor_recommendation(str(selected.get("id", "")))
	canvas._text("EMPFEHLUNG", 137, 145, 7, DIM)
	canvas._text(canvas._short(str(advice.get("title", "KEINE")), 31), 137, 159, 8, WHITE)
	canvas._draw_wrapped(str(advice.get("detail", "")), Rect2(137, 164, 163, 31), 6, DIM)
	var instruction := "ENTER/A: EPOCHENLEITUNG SETZEN (KOSTENLOS)"
	if selected_status == "DEFECTED":
		instruction = "ENTER/A: INTERIM · 10 MRD + 1 BEFEHL"
	elif model.advisor_selected_turn == model.turn:
		instruction = "EPOCHENLEITUNG IST BEREITS GESETZT"
	canvas._text(instruction, 8, 214, 7, AMBER)
	# Gegendruck als drei abgesetzte Messanzeigen statt einer Zeile, in der drei
	# Gegnernamen auf je neun Zeichen verstuemmelt wurden ("FREIE OB... 16").
	# Jeder Gegner bekommt volle Beschriftung und einen LED-Balken.
	var opponents: Array = model.opponent_catalog()
	for i in mini(opponents.size(), 3):
		var opponent: Dictionary = opponents[i]
		var cell := Rect2(8 + i * 102, 222, 98, 26)
		Chrome.inset_well(canvas, cell, canvas._video_profile)
		canvas._text_fit(str(opponent.get("title", "")),
			Rect2(cell.position + Vector2(3, 1), Vector2(cell.size.x - 6, 10)),
			cell.position.y + 9, 6, DIM)
		Chrome.segment_bar(canvas, Rect2(cell.position.x + 3, cell.position.y + 13, 68, 6),
			canvas._video_profile, float(opponent.get("pressure", 0)), RED, 10)
		canvas._text("%02d" % int(opponent.get("pressure", 0)),
			cell.end.x - 20, cell.position.y + 19, 7, RED)


static func draw_projects(canvas, model, menu_index: int) -> void:
	canvas._draw_cover(PROJECTS_ART, Rect2(0, 0, 320, 256))
	canvas.draw_rect(Rect2(0, 0, 320, 256), Color(0, 0, 0, 0.58))
	canvas._header("PROJEKTLEISTE", "%s · %s" % [model.period_label(), model.phase()])
	var catalog: Array = model.project_catalog()
	for i in catalog.size():
		var entry: Dictionary = catalog[i]
		var state := str(entry.get("state", "AVAILABLE"))
		var project_status := state
		if state == "ACTIVE":
			project_status = "%d/%d" % [int(entry.get("progress", 0)), int(entry.get("duration", 1))]
		elif model.year() < int(entry.get("unlock_year", 1962)):
			project_status = "AB %d" % int(entry.get("unlock_year", 1962))
		canvas._menu_card(Rect2(10, 44 + i * 31, 300, 27), "%s   [%s]" % [
			str(entry.get("title", "")), project_status], "%d MRD · %s" % [
			int(entry.get("cost", 0)), str(entry.get("description", ""))], i, i == menu_index,
			true, 7, 6)
	canvas._text("PROJEKTSTART VERBRAUCHT EINEN BEFEHL", 10, 244, 7, AMBER)


static func draw_archive(canvas, model, menu_index: int) -> void:
	canvas._draw_cover(SKY_ARCHIVE_ART, Rect2(0, 0, 320, 256))
	canvas.draw_rect(Rect2(0, 0, 320, 256), Color(0, 0, 0, 0.72))
	canvas._header("HIMMELSARCHIV", "BEOBACHTUNG ≠ SPIELPHYSIK")
	var catalog: Array = model.historical_sky_catalog()
	for i in catalog.size():
		var entry: Dictionary = catalog[i]
		canvas._button(Rect2(8, 48 + i * 35, 124, 29), "%d · %s" % [
			int(entry.get("year", 0)), canvas._short(str(entry.get("title", "")), 18)],
			i, i == menu_index)
	if catalog.is_empty():
		return
	var selected: Dictionary = catalog[clampi(menu_index, 0, catalog.size() - 1)]
	canvas._panel(Rect2(140, 48, 172, 156))
	canvas._text(str(selected.get("title", "")), 149, 67, 10, AMBER)
	var hypothesis := str(selected.get("status", "")) == "HYPOTHESE"
	canvas._text("STATUS · %s" % str(selected.get("status", "")), 149, 82, 8,
		RED if hypothesis else GREEN)
	canvas._draw_wrapped(str(selected.get("summary", "")), Rect2(149, 92, 154, 52), 7, WHITE)
	canvas._text("UEBERTRAGUNG INS SPIEL", 149, 153, 7, CYAN)
	canvas._draw_wrapped(str(selected.get("game_link", "")), Rect2(149, 160, 154, 36), 6, DIM)
	canvas._text("ARCHIVREGEL: BELEGT UND HYPOTHESE BLEIBEN GETRENNT", 8, 220, 6, AMBER)
	canvas._text("STEUERKREUZ/MAUS: AKTE · ESC/B: LAGEZENTRUM", 8, 239, 7, WHITE)


static func draw_optics(canvas, model, menu_index: int, public_view: bool) -> void:
	canvas._draw_cover(OPTICS_ART, Rect2(0, 0, 320, 256))
	canvas.draw_rect(Rect2(0, 0, 320, 256), Color(0, 0, 0, 0.43))
	canvas._header("OPTIKLABOR", "%s · %s" % [model.period_label(), model.phase()])
	var scenario: Dictionary = model.current_optics()
	canvas._draw_sundog_scene(Rect2(10, 43, 145, 92), str(scenario.get("id", "")))
	# Befundmulde rechts neben der Optikszene. Vorher lief der Text als EINE
	# Zeile ab x=164 — auf 47 Zeichen gekuerzt, aber nur 156 Pixel breit, also
	# rechts aus dem Bild heraus. Jetzt bricht er in einer vertieften Akte um.
	var file_rect := Rect2(160, 43, 150, 92)
	Chrome.inset_well(canvas, file_rect, canvas._video_profile)
	canvas._text_fit(str(scenario.get("title", "")),
		Rect2(file_rect.position + Vector2(4, 2), Vector2(file_rect.size.x - 8, 14)),
		file_rect.position.y + 13, 10, AMBER)
	canvas.draw_line(Vector2(file_rect.position.x + 4, file_rect.position.y + 18),
		Vector2(file_rect.end.x - 4, file_rect.position.y + 18), DIM, 1)
	canvas._draw_wrapped(
		str(scenario.get("secret" if not public_view else "public", "")),
		Rect2(file_rect.position + Vector2(4, 21),
			Vector2(file_rect.size.x - 8, file_rect.size.y - 25)), 7, WHITE)
	var choices: Array = scenario.get("choices", [])
	for i in choices.size():
		canvas._button(Rect2(10, 145 + i * 27, 300, 22),
			str((choices[i] as Dictionary).get("title", "")), i, i == menu_index,
			model.can_resolve_optics())
	canvas._text("EINE ANALYSE = EIN BEFEHL · TAB WECHSELT AKTENEBENE", 10, 238, 7, DIM)


static func draw_event(canvas, model, menu_index: int) -> void:
	canvas._draw_cover(canvas._event_texture(str(model.pending_event.get("art", ""))),
		Rect2(0, 0, 320, 256))
	canvas.draw_rect(Rect2(0, 0, 320, 256), Color(0, 0, 0, 0.72))
	canvas._header("EREIGNIS · %s" % model.period_label(),
		str(model.pending_event.get("title", "ALARM")))
	canvas._panel(Rect2(12, 54, 296, 72))
	canvas._draw_wrapped(str(model.pending_event.get("text", "")), Rect2(20, 64, 280, 43), 8, WHITE)
	if bool(model.pending_event.get("sky_event", false)):
		canvas._text("ARCHIV: %s · %s" % [str(model.pending_event.get("archive_title", "")),
			str(model.pending_event.get("archive_status", ""))], 20, 119, 6,
			RED if str(model.pending_event.get("archive_status", "")) == "HYPOTHESE" else CYAN)
	var choices: Array = model.pending_event.get("choices", [])
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var row_y := 137 + i * 46
		canvas._button(Rect2(18, row_y, 284, 28), str(choice.get("title", "")), i,
			i == menu_index)
		canvas._text(canvas._effects_line(choice.get("effects", {})), 25, row_y + 39, 6, DIM)
	canvas._text("ENTSCHEIDUNG ERFORDERLICH", 12, 239, 8, RED)


static func draw_manual(canvas, manual_page: int) -> void:
	canvas._draw_terminal_background("ROTES GEHEIMHANDBUCH · %d/4" % (manual_page + 1))
	var pages := [
		["STEUERUNG", "PFEILE / STEUERKREUZ: MENUE UND REGION",
			"ENTER / A: BESTAETIGEN    ESC / B: ZURUECK",
			"TAB / X: OEFFENTLICHE UND GEHEIME AKTE",
			"SCHULTERTASTEN: REGION DIREKT WECHSELN", "LINKS/RECHTS: HANDBUCHSEITEN",
			"JE PERIODE STEHEN ZWEI BEFEHLE BEREIT."],
		["FIKTIVE PHYSIK · ELEKTRISCHES UNIVERSUM",
			"OBJEKT, SONNE UND ERDE KOPPELN ELEKTRISCH.", "INDUKTION SPEIST DIE PLASMALAST.",
			"FILAMENTE -> BIRKELAND-STROEME -> Z-PINCH", "-> GLOBALE ENTLADUNG IM SOMMER 2034.",
			"FARADAY-WELTNETZ UND SEGMENTIERUNG DROSSELN",
			"FOLGEN, KOENNEN DAS FENSTER ABER NICHT LOESCHEN."],
		["OPERATIONSSYSTEME", "KABINETT: LEITUNG GIBT EINEM RESSORT BONUS.",
			"NIEDRIGE LOYALITAET KANN LECK ODER DEFEKTION",
			"AUSLOESEN. INTERIM KOSTET 10 MRD + 1 BEFEHL.",
			"WELTKARTE: PANIK, VERTRAUEN UND SICHTBARKEIT",
			"SIND REGIONAL. PROJEKTE LAUFEN UEBER PERIODEN.",
			"SPERREN HELFEN KURZ, STREISAND BLEIBT MOEGLICH."],
		["HIMMELSARCHIV", "CARRINGTON, NACHTWOLKEN UND SPRITES: BELEGT.",
			"PERATTS PETROGLYPH-/Z-PINCH-VERGLEICH:",
			"VEROEFFENTLICHTE HYPOTHESE, NICHT GESICHERT.",
			"DAS SPIEL UEBERNIMMT DIE FORM ALS FIKTIONALES",
			"SPAETWARNZEICHEN: DEN SQUATTER MAN AM HIMMEL.",
			"HALOS UND NEBENSONNEN BLEIBEN REALE EISOPTIK."],
	]
	var lines: Array = pages[manual_page]
	for i in lines.size():
		canvas._text(str(lines[i]), 14, 60 + i * 20, 9 if i == 0 else 8,
			AMBER if i == 0 else WHITE)
	canvas._text("«/» SEITE · ENTER/A ZURUECK", 75, 231, 8, DIM)


## Untere Bedienleiste des Lagezentrums. Vorher lagen hier zwei nackte
## Textzeilen auf 46 Pixeln toter Flaeche; jetzt traegt der Platz die Zielregion
## als Schaltplatte, den Geheim-/Oeffentlich-Schalter als Kontrollleuchte und
## die Meldung in einer vertieften Laufschriftmulde.
static func draw_status_console(canvas, model, rect: Rect2, region: Dictionary,
		public_view: bool, message: String) -> void:
	var profile: Dictionary = canvas._video_profile
	Chrome.bevel_panel(canvas, rect, profile)
	Chrome.rivet_corners(canvas, rect, profile)

	var plate := Rect2(rect.position.x + 4, rect.position.y + 4, 150, 15)
	Chrome.bevel_panel(canvas, plate, profile,
		Chrome.PLATE, Chrome.PLATE_LIT, Chrome.PLATE_SHADE)
	canvas._text_fit("« %s »" % str(region.get("title", "GLOBAL")),
		plate.grow(-3.0), plate.position.y + 11.0, 8, WHITE)

	# Kontrollleuchte: der Zustand ist an der Lampe ablesbar, nicht nur am Wort.
	var lamp := Rect2(rect.end.x - 96, rect.position.y + 4, 92, 15)
	Chrome.inset_well(canvas, lamp, profile)
	var live := not public_view
	canvas.draw_rect(Rect2(lamp.position.x + 3, lamp.position.y + 4, 7, 7),
		Chrome.quantise(RED if live else GREEN, profile))
	canvas._text(("GEHEIM" if live else "OEFFENTLICH"), lamp.position.x + 14,
		lamp.position.y + 11, 7, WHITE)

	var signal_entry: Dictionary = model.public_signal_for_year()
	var ticker := message
	if ticker.is_empty() and not signal_entry.is_empty():
		ticker = "OEFFENTLICHE SPUR: %d · %s" % [
			int(signal_entry.get("year", 0)), str(signal_entry.get("source", ""))]
	var well := Rect2(rect.position.x + 4, rect.position.y + 23,
		rect.size.x - 8, rect.size.y - 27)
	Chrome.inset_well(canvas, well, profile)
	canvas._draw_wrapped(ticker, well.grow(-3.0), 7, AMBER)


static func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		bounds = bounds.expand(p)
	return bounds


static func draw_world_map(canvas, model, rect: Rect2, selected_region: int,
		hit_rects: Array[Dictionary]) -> void:
	canvas._panel(rect)
	var catalog: Array = model.region_catalog()
	var shapes: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(13, 14), Vector2(36, 10), Vector2(52, 22), Vector2(43, 34), Vector2(49, 48), Vector2(35, 70), Vector2(27, 48), Vector2(18, 37)]),
		PackedVector2Array([Vector2(65, 19), Vector2(83, 15), Vector2(91, 25), Vector2(80, 34), Vector2(67, 29)]),
		PackedVector2Array([Vector2(86, 13), Vector2(125, 12), Vector2(137, 26), Vector2(127, 39), Vector2(100, 36), Vector2(88, 27)]),
		PackedVector2Array([Vector2(70, 35), Vector2(94, 36), Vector2(99, 51), Vector2(86, 72), Vector2(73, 58)]),
		PackedVector2Array([Vector2(116, 49), Vector2(136, 45), Vector2(140, 62), Vector2(124, 70), Vector2(110, 61)]),
	]
	var hotspots := [Rect2(10, 8, 45, 66), Rect2(62, 11, 31, 26), Rect2(85, 8, 57, 34),
		Rect2(67, 32, 36, 44), Rect2(107, 42, 36, 35)]
	for i in mini(catalog.size(), shapes.size()):
		var region: Dictionary = catalog[i]
		var danger := maxf(float(region.get("panic", 0.0)), float(region.get("exposure", 0.0)))
		var points := PackedVector2Array()
		for point: Vector2 in shapes[i]:
			points.append(rect.position + point)
		# Gefahr laeuft ueber eine feste Fuenfstufen-Rampe. Gedithert wird immer
		# nur zwischen zwei BENACHBARTEN Stufen — so las ein Amiga-Bild als
		# Schattierung statt als Streifenmuster. Ein Dither ueber die halbe
		# Palette hinweg (gruen direkt auf amber) wirkt dagegen wie ein Gitter.
		var span := clampf(danger / 100.0, 0.0, 1.0) * float(DANGER_RAMP.size() - 1)
		var step := clampi(int(floor(span)), 0, DANGER_RAMP.size() - 2)
		Chrome.dither_polygon(canvas, points, DANGER_RAMP[step], DANGER_RAMP[step + 1],
			span - float(step), canvas._video_profile)
		# Konturlinie immer — auf 32 Registern traegt die Kante die Lesbarkeit.
		var edge: Color = WHITE if i == selected_region else Color8(17, 34, 34)
		for p in points.size():
			canvas.draw_line(points[p], points[(p + 1) % points.size()], edge, 1)
		if i == selected_region:
			Chrome.corner_brackets(canvas, _polygon_bounds(points).grow(1.0), WHITE, 3.0)
		hit_rects.append({"rect": Rect2(rect.position + hotspots[i].position, hotspots[i].size),
			"action": "region", "region_index": i})
	var selected: Dictionary = catalog[clampi(selected_region, 0, catalog.size() - 1)] \
		if not catalog.is_empty() else {}
	canvas._text("P%02d T%02d E%02d" % [int(selected.get("panic", 0)),
		int(selected.get("trust", 0)), int(selected.get("exposure", 0))],
		rect.position.x + 5, rect.end.y - 4, 6, WHITE)
	var electric: Dictionary = model.electric_universe_snapshot()
	canvas._text("E:%s" % canvas._short(str(electric.get("label", "")), 11),
		rect.position.x + 79, rect.end.y - 4, 6,
		RED if int(electric.get("stage", 0)) >= 3 else CYAN)
