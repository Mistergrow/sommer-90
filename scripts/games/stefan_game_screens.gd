extends RefCounted
## Vollbild-Masken der Stefan-Anthologie ausserhalb des Spielfelds: Boot, Titel,
## Briefing, Pause, Ergebnis, Rekorde, Hilfe und Auswurf-Abfrage.
##
## Aufgeteilt aus stefan_game_renderer.gd (Zeilenbudget). Kein class_name.

const Base := preload("res://scripts/games/stefan_game_render_base.gd")


static func draw_boot(canvas: CanvasItem, definition: Dictionary, phase: float) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 200), Color8(3, 6, 11))
	var a := Base.accent(definition)
	for i in 42:
		var x := posmod(i * 71 + int(phase * 13), 320)
		var y := posmod(i * 37, 166)
		canvas.draw_rect(Rect2(x, y, 1, 1), Base.PAPER if i % 5 else a)
	Base.text(canvas, "STEFAN SOFT PRESENTS", Vector2(0, 40), 12, a,
		HORIZONTAL_ALIGNMENT_CENTER, 320)
	Base.text(canvas, str(definition.get("title", "AMIGA GAME")), Vector2(0, 83), 23, Base.PAPER,
		HORIZONTAL_ALIGNMENT_CENTER, 320, 2)
	var blocks := clampi(floori(phase * 18.0), 0, 18)
	Base.bevel(canvas, Rect2(68, 119, 184, 13), Base.INK, Base.STEEL, Base.STEEL_LIT)
	for i in blocks:
		canvas.draw_rect(Rect2(71 + i * 10, 122, 7, 7), a if i < 14 else Base.AMBER)
	Base.text(canvas, "DF0: TRACK %02d" % clampi(floori(phase * 80), 0, 79), Vector2(0, 151), 9,
		Base.STEEL_LIT, HORIZONTAL_ALIGNMENT_CENTER, 320)
	# Das Build-Profil benennt den Grafikvertrag der Diskette. Das konkrete
	# Rechner-/Speicherinventar bleibt Aufgabe des umgebenden Amiga-Systems.
	var build_text := {
		0: "PAL · OCS BUILD · 32 FARBEN",
		1: "PAL · ECS BUILD · DUAL PLAYFIELD",
		2: "PAL · AGA BUILD · 128-FARB PALETTE",
	}[Base._hardware_tier(definition)] as String
	Base.text(canvas, build_text, Vector2(0, 181), 8, Color8(170, 170, 170),
		HORIZONTAL_ALIGNMENT_CENTER, 320)
	Base.scanlines(canvas, 0.13)
static func draw_title(canvas: CanvasItem, texture: Texture2D, definition: Dictionary,
		menu: Array[String], selected: int, pulse: float, record: Dictionary) -> void:
	Base.draw_atlas(canvas, texture, definition, Rect2(0, 0, 320, 200), Color(0.72, 0.72, 0.76))
	canvas.draw_rect(Rect2(0, 0, 320, 200), Color(0.01, 0.025, 0.05, 0.36))
	canvas.draw_rect(Rect2(0, 0, 320, 49), Color(0.01, 0.02, 0.04, 0.88))
	canvas.draw_rect(Rect2(0, 155, 320, 45), Color(0.01, 0.02, 0.04, 0.92))
	var a := Base.accent(definition)
	Base.text(canvas, str(definition.get("title", "")), Vector2(8, 23), 21, Base.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 304, 2)
	Base.text(canvas, str(definition.get("subtitle", "")), Vector2(8, 41), 8, a, HORIZONTAL_ALIGNMENT_CENTER, 304)
	for i in menu.size():
		var rect := Rect2(10 + i * 75, 160, 70, 20)
		Base.bevel(canvas, rect, Base.PANEL.lightened(0.08) if i == selected else Color(0.03, 0.06, 0.09, 0.9),
			a if i == selected else Base.STEEL, a.lightened(0.25) if i == selected else Base.STEEL_LIT)
		Base.text(canvas, menu[i], Vector2(rect.position.x, rect.position.y + 14), 8,
			Base.PAPER if i == selected else Base.STEEL_LIT, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	var blink := a if fmod(pulse, 1.0) < 0.72 else Base.PAPER
	Base.text(canvas, "FIRE / ENTER", Vector2(8, 194), 7, blink)
	Base.text(canvas, "HI %07d" % int(record.get("best_score", 0)), Vector2(175, 194), 7, Base.PAPER,
		HORIZONTAL_ALIGNMENT_RIGHT, 136)
	Base.scanlines(canvas)
static func draw_briefing(canvas: CanvasItem, texture: Texture2D, definition: Dictionary) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 200), Base.INK)
	var a := Base.accent(definition)
	Base.draw_atlas(canvas, texture, definition, Rect2(8, 25, 128, 91), Color(0.88, 0.88, 0.88))
	canvas.draw_rect(Rect2(8, 25, 128, 91), a, false, 1)
	Base.text(canvas, "MISSIONSAKTE %d-%d" % [definition.get("year", 1991), definition.get("slot", 1)],
		Vector2(8, 15), 10, Base.AMBER, HORIZONTAL_ALIGNMENT_LEFT, 210)
	Base.text(canvas, Base._hardware_label(definition), Vector2(238, 15), 7, Base.STEEL_LIT,
		HORIZONTAL_ALIGNMENT_RIGHT, 74)
	Base.text(canvas, str(definition.get("title", "")), Vector2(146, 37), 14, Base.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 166, 1)
	Base.wrapped(canvas, str(definition.get("briefing", "")), Rect2(146, 46, 166, 68), 8, Base.PAPER, 10, 7)
	Base.bevel(canvas, Rect2(8, 124, 304, 37), Base.NIGHT, Base.STEEL, a)
	Base.text(canvas, "AUFTRAG", Vector2(15, 138), 8, a)
	Base.wrapped(canvas, str(definition.get("objective", "")), Rect2(15, 141, 290, 17), 8, Base.PAPER, 9, 2)
	Base.text(canvas, str(definition.get("controls", "")), Vector2(8, 177), 7, Base.STEEL_LIT,
		HORIZONTAL_ALIGNMENT_CENTER, 304)
	Base.text(canvas, "FIRE / ENTER: EINSATZ STARTEN", Vector2(8, 193), 8, Base.AMBER,
		HORIZONTAL_ALIGNMENT_CENTER, 304)
	Base.scanlines(canvas)
static func draw_pause(canvas: CanvasItem, definition: Dictionary) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 200), Color(0, 0, 0, 0.68))
	Base.bevel(canvas, Rect2(62, 60, 196, 76), Color(0.025, 0.05, 0.075, 0.98), Base.STEEL, Base.accent(definition))
	Base.text(canvas, "PAUSE", Vector2(62, 84), 20, Base.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 196, 2)
	Base.text(canvas, "P / FIRE  WEITER", Vector2(62, 108), 9, Base.accent(definition), HORIZONTAL_ALIGNMENT_CENTER, 196)
	Base.text(canvas, "ESC  ZUM TITEL", Vector2(62, 125), 8, Base.STEEL_LIT, HORIZONTAL_ALIGNMENT_CENTER, 196)
static func draw_results(canvas: CanvasItem, texture: Texture2D, definition: Dictionary,
		model: StefanGameModel, record: Dictionary, selected: int) -> void:
	Base.draw_atlas(canvas, texture, definition, Rect2(0, 0, 320, 200), Color(0.42, 0.42, 0.45))
	canvas.draw_rect(Rect2(0, 0, 320, 200), Color(0.01, 0.02, 0.035, 0.74))
	var color := Base.GREEN if model.completed else Base.danger(definition)
	Base.text(canvas, "AUFTRAG ERFUELLT" if model.completed else "EINSATZ BEENDET",
		Vector2(8, 34), 20, color, HORIZONTAL_ALIGNMENT_CENTER, 304, 2)
	Base.text(canvas, model.result_reason, Vector2(8, 55), 9, Base.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 304)
	Base.bevel(canvas, Rect2(48, 67, 224, 67), Color(0.02, 0.045, 0.065, 0.94), Base.STEEL, color)
	Base.text(canvas, "PUNKTE", Vector2(62, 83), 8, Base.STEEL_LIT)
	Base.text(canvas, "%07d" % model.score, Vector2(126, 88), 17, Base.AMBER)
	Base.text(canvas, "BESTWERT  %07d" % int(record.get("best_score", model.score)), Vector2(62, 108), 8, Base.PAPER)
	Base.text(canvas, "ZEIT      %02d:%02d" % [floori(model.elapsed / 60.0), floori(fmod(model.elapsed, 60.0))],
		Vector2(62, 123), 8, Base.PAPER)
	var buttons := ["ZUM TITEL", "REKORDE"]
	for i in 2:
		var rect := Rect2(46 + i * 116, 151, 108, 23)
		Base.bevel(canvas, rect, Base.PANEL.lightened(0.1) if selected == i else Base.PANEL,
			Base.accent(definition) if selected == i else Base.STEEL,
			Base.accent(definition) if selected == i else Base.STEEL_LIT)
		Base.text(canvas, buttons[i], Vector2(rect.position.x, rect.position.y + 16), 9,
			Base.PAPER, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	Base.text(canvas, "ENTER WAELT · KEIN SOFORTIGER NEUSTART", Vector2(8, 193), 7, Base.STEEL_LIT,
		HORIZONTAL_ALIGNMENT_CENTER, 304)
	Base.scanlines(canvas)
static func draw_records(canvas: CanvasItem, definition: Dictionary, record: Dictionary) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 200), Base.INK)
	var a := Base.accent(definition)
	Base.text(canvas, "HALL OF MEMORY", Vector2(8, 25), 18, a, HORIZONTAL_ALIGNMENT_CENTER, 304, 2)
	Base.bevel(canvas, Rect2(34, 43, 252, 107), Base.NIGHT, Base.STEEL, a)
	var rows := [
		["GESTARTET", int(record.get("plays", 0))],
		["GESCHAFFT", int(record.get("completions", 0))],
		["BESTWERT", int(record.get("best_score", 0))],
		["LETZTER LAUF", int(record.get("last_score", 0))],
	]
	for i in rows.size():
		Base.text(canvas, str(rows[i][0]), Vector2(49, 64 + i * 20), 9, Base.STEEL_LIT)
		Base.text(canvas, "%07d" % int(rows[i][1]), Vector2(165, 64 + i * 20), 11,
			Base.AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 103)
	var best_time := int(record.get("best_time_ms", 0))
	Base.text(canvas, "BESTZEIT", Vector2(49, 144), 9, Base.STEEL_LIT)
	Base.text(canvas, "--:--" if best_time <= 0 else "%02d:%02d" % [
		floori(float(best_time) / 60_000.0), floori(float(best_time) / 1_000.0) % 60],
		Vector2(165, 144), 11, Base.PAPER, HORIZONTAL_ALIGNMENT_RIGHT, 103)
	Base.text(canvas, "ESC / FIRE ZURUECK", Vector2(8, 185), 8, a, HORIZONTAL_ALIGNMENT_CENTER, 304)
	Base.scanlines(canvas)
static func draw_help(canvas: CanvasItem, definition: Dictionary) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 200), Base.INK)
	var a := Base.accent(definition)
	Base.text(canvas, "BEDIENUNG", Vector2(8, 24), 18, a, HORIZONTAL_ALIGNMENT_CENTER, 304, 2)
	Base.bevel(canvas, Rect2(20, 39, 280, 113), Base.NIGHT, Base.STEEL, a)
	var lines := [
		"PFEILE / WASD        BEWEGEN / AUSWAHL",
		"SPACE / CTRL / FIRE  AKTION",
		"SHIFT                 SPEZIAL / WARTEN",
		"H                     HINWEIS / SONAR",
		"D F J K               RHYTHMUS-KANAELE",
		"P / ESC               PAUSE / ZURUECK",
	]
	for i in lines.size():
		Base.text(canvas, lines[i], Vector2(31, 58 + i * 15), 8, Base.PAPER if i % 2 == 0 else Base.STEEL_LIT)
	Base.text(canvas, "MAUS UND GAMEPAD WERDEN EBENFALLS UNTERSTUETZT", Vector2(8, 173), 7, Base.AMBER,
		HORIZONTAL_ALIGNMENT_CENTER, 304)
	Base.text(canvas, "ESC / FIRE ZURUECK", Vector2(8, 190), 8, a, HORIZONTAL_ALIGNMENT_CENTER, 304)
static func draw_exit_confirm(canvas: CanvasItem, definition: Dictionary, selected: int) -> void:
	canvas.draw_rect(Rect2(0, 0, 320, 200), Color(0, 0, 0, 0.70))
	Base.bevel(canvas, Rect2(48, 61, 224, 78), Color(0.025, 0.045, 0.065, 0.98), Base.STEEL, Base.danger(definition))
	Base.text(canvas, "DISKETTE AUSWERFEN?", Vector2(48, 86), 14, Base.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 224, 2)
	var options := ["NEIN", "JA"]
	for i in 2:
		var rect := Rect2(69 + i * 102, 105, 80, 22)
		Base.bevel(canvas, rect, Base.PANEL if selected != i else Base.PANEL.lightened(0.12),
			Base.STEEL if selected != i else Base.accent(definition), Base.STEEL_LIT)
		Base.text(canvas, options[i], Vector2(rect.position.x, rect.position.y + 15), 9,
			Base.PAPER, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
