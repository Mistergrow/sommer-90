extends WbApp
## Gemeinsame interaktive App fuer kleinere Workbench-Programme. Darstellung und
## Bedienung werden geteilt, die Faehigkeiten sind jedoch pro Program-ID konkret
## in GenericProgramRuntime definiert. Dadurch besitzt jedes Programm echte,
## testbare Zustandswechsel statt einer blossen animierten Vorschau.

const Runtime := preload("res://scripts/ui/generic_program_runtime.gd")
const ActionEngine := preload("res://scripts/util/action_execution_engine.gd")
var program: Dictionary = {}
var _t := 0.0
var _runtime: GenericProgramRuntime
var _action_engine
var _last_result: Dictionary = {}


func _init() -> void:
	app_bg = Color8(24, 30, 44)
	app_bar = Color8(40, 66, 96)
	app_accent = Color8(120, 180, 240)


func _build_app() -> void:
	app_title = "%s   ·   %s" % [str(program.get("display_name", "PROGRAMM")),
		_cat_name(str(program.get("category", "")))]
	app_bar = _cat_color(str(program.get("category", "")))
	_ensure_execution()
	var actions := _runtime.available_actions()
	for i in mini(2, actions.size()):
		var row: Array = actions[i]
		add_button(str(row[1]), Rect2(20 + i * 178, VH - 46, 166, 24),
			_execute.bind(str(row[0])), app_accent)
	add_button("BESTÄTIGEN", Rect2(376, VH - 46, 116, 24), _confirm_pending,
		Color8(244, 164, 66))
	add_button("ÜBER", Rect2(506, VH - 46, 110, 24), _about, app_accent)


func _about() -> void:
	UIManager.toast("%s — %s" % [str(program.get("display_name", "")),
		str(program.get("description", ""))])


## Testbarer Programmvertrag fuer Launcher, QA und spaetere Bespoke-UIs.
func capability_contract() -> Dictionary:
	return _runtime.capability.duplicate(true) if _runtime != null else \
		Runtime.capability_for(str(program.get("id", "")))


func execute_action(action_id: String, confirm := false) -> Dictionary:
	_ensure_execution()
	_last_result = _action_engine.execute(action_id, confirm)
	queue_redraw()
	return _last_result.duplicate(true)


func execution_snapshot() -> Dictionary:
	_ensure_execution()
	return _action_engine.state_snapshot()


func _ensure_execution() -> void:
	if _runtime == null:
		_runtime = Runtime.new()
		_runtime.setup(str(program.get("id", "")))
	if _action_engine == null:
		_action_engine = ActionEngine.new().configure(
			Callable(self, "_perform_runtime_action"),
			"generic/%s" % str(program.get("id", "")))


func _perform_runtime_action(action_id: String, confirm: bool) -> Dictionary:
	return _runtime.action(action_id, {"confirm": confirm})


func _pending_action_id() -> String:
	return _action_engine.pending_action() if _action_engine != null else ""


func state_snapshot() -> Dictionary:
	return _runtime.state_snapshot() if _runtime != null else {}


func _execute(action_id: String) -> void:
	var result := execute_action(action_id)
	UIManager.toast(str(result.get("message", "Keine Rückmeldung.")))


func _confirm_pending() -> void:
	if _pending_action_id().is_empty():
		UIManager.toast(Loc.t("ui.generic_program_app.keine_sicherheitskritische_aktion_wartet_auf_bestatigung", "Keine sicherheitskritische Aktion wartet auf Bestätigung."))
		return
	var result: Dictionary = _action_engine.confirm_pending()
	_last_result = result
	queue_redraw()
	UIManager.toast(str(result.get("message", "Aktion abgebrochen.")))


func _app_process(delta: float) -> void:
	_t += delta


func _content(font: Font) -> void:
	var cat := str(program.get("category", ""))
	# Kopf: Beschreibung
	rect(14, 24, VW - 28, 40, Color8(12, 18, 30))
	rect_line(14, 24, VW - 28, 40, app_accent)
	text(font, str(program.get("description", "")), 24, 42, 12, Color8(220, 232, 244))
	text(font, "Kategorie: %s · Seltenheit: %s" % [_cat_name(cat), str(program.get("rarity", "common"))],
		24, 58, 9, Color8(140, 170, 210))
	# Kategorieansicht visualisiert den echten Laufzeitzustand.
	_mock(font, cat)
	_draw_runtime_status(font)
	text(font, "Esc = zurück · Orange BESTÄTIGEN schützt schreibende Disk-Aktionen.",
		24, VH - 8, 9, Color8(120, 150, 190))


func _draw_runtime_status(font: Font) -> void:
	if _runtime == null:
		return
	var state := _runtime.state_snapshot()
	var y := VH - 78.0
	rect(20, y - 14, VW - 40, 28, Color8(13, 20, 29))
	rect_line(20, y - 14, VW - 40, 28,
		Color8(220, 150, 60) if not _pending_action_id().is_empty() else app_accent)
	var line := str(_last_result.get("message",
		_runtime.history[0] if not _runtime.history.is_empty() else "Bereit."))
	if line.length() > 78:
		line = line.substr(0, 75) + "..."
	text(font, line, 28, y + 2, 9, Color8(225, 232, 240))
	text(font, "REV %d · VORGÄNGE %d · TEMPO %.2fx" % [
		int(state.get("revision", 0)), int(state.get("processed", 0)),
		Runtime.performance_factor()], 420, y + 2, 8, Color8(140, 180, 210))


func _mock(font: Font, cat: String) -> void:
	var x := 20.0
	var y := 78.0
	var w := VW - 40.0
	var h := VH - 162.0
	rect(x, y, w, h, Color8(10, 14, 24))
	rect_line(x, y, w, h, Color8(60, 76, 100))
	match cat:
		"file":
			# Zwei Fenster mit Datei-/Diskettenliste
			for pane in 2:
				var px := x + 8 + pane * floori(w / 2.0)
				text(font, "DF%d:  >" % pane, px, y + 14, 10, app_accent)
				var names := ["System", "Utilities", "c/", "Spiele", "readme.txt", "s/", "libs/", "MODs"]
				for i in names.size():
					var hl := int(_t * 2.0) % names.size() == i and pane == 0
					if hl:
						rect(px - 2, y + 20 + i * 14, floori(w / 2.0) - 12, 12, Color8(28, 50, 78))
					text(font, "[DIR] " + names[i] if i % 3 == 2 else "      " + names[i],
						px, y + 30 + i * 14, 10, Color8(210, 222, 234))
		"disk", "cd":
			# Zylinder-Raster (Format/Reparatur/Backup)
			var done := int(_t * 30.0) % 80
			text(font, "Zylinder 0–79:", x + 10, y + 16, 10, app_accent)
			for c in 80:
				var cx := x + 12 + (c % 40) * floori((w - 24) / 40.0)
				var cy := y + 28 + floori(c / 40.0) * 16
				rect(cx, cy, floori((w - 24) / 40.0) - 1, 14, Color8(90, 210, 120) if c < done else Color8(30, 40, 30))
			text(font, "laeuft ... %d%%" % int(done / 80.0 * 100), x + 10, y + h - 10, 10, Color8(120, 220, 140))
		"music":
			# Tracker-Pattern
			for r in 12:
				var col: Color = Color8(240, 220, 90) if r == int(_t * 6.0) % 12 else Color8(150, 200, 160)
				text(font, "%02d | C-2 A#3 --- G-1 | 0F0 C40 --- ---" % r, x + 10, y + 18 + r * 14, 10, col)
		"graphics":
			# Farbraster + Pinselvorschau
			for i in 16:
				var col: Color = Color.from_hsv(float(i) / 16.0, 0.6, 0.9)
				rect(x + 10 + i * 18, y + 12, 16, 16, col)
			rect(x + 10, y + 40, w - 20, h - 52, Color8(40, 40, 48))
			draw_circle(_V(x + w * 0.4 + sin(_t) * 30, y + h * 0.6), 8.0 * _sy(), Color8(230, 120, 60))
		"code":
			var code := ["move.l d0,-(sp)", "moveq  #0,d1", "loop:  add.l  d1,d0", "       dbra   d1,loop", "       rts", "; assembliert. 0 Fehler."]
			for i in code.size():
				text(font, code[i], x + 10, y + 18 + i * 15, 11, Color8(140, 230, 150))
		"text":
			text(font, "Liebes Tagebuch,", x + 12, y + 20, 12, Color8(230, 230, 220))
			text(font, "heute in der Mailbox ein neues Programm gezogen ...", x + 12, y + 38, 11, Color8(200, 200, 190))
			rect(x + 12, y + 44, 1, 12, Color8(230, 230, 220) if int(_t * 2) % 2 == 0 else Color8(10, 14, 24))
		"comm":
			var lines := ["ATDT 0201-334455", "CONNECT 2400", "Willkommen, User!",
				"> DOWNLOAD gestartet ...", "[######----] 62%"]
			for i in lines.size():
				text(font, lines[i], x + 12, y + 20 + i * 16, 11, Color8(120, 230, 130))
		"scene":
			text(font, ".:*:. present .:*:.", x + w * 0.5 - 60, y + 20, 12, Color8(240, 200, 90))
			var scroll := "...GRUESSE GEHEN RAUS AN ALLE IN DER SZENE...BLEIBT ELITE..."
			var off := int(_t * 20.0) % scroll.length()
			text(font, (scroll + scroll).substr(off, 46), x + 12, y + h * 0.6, 12, Color8(120, 220, 240))
		_:
			# system: Info-Zeilen
			var state := _runtime.state_snapshot() if _runtime != null else {}
			var rows := [["STATUS", "aktiv"], ["VERSION", "1.0"],
				["LETZTE AKTION", str(state.get("last_action", "keine"))],
				["LAUFZEIT", "%d Ticks" % int(state.get("last_ticks", 0))]]
			for i in rows.size():
				text(font, rows[i][0], x + 12, y + 22 + i * 18, 11, app_accent)
				text(font, rows[i][1], x + 160, y + 22 + i * 18, 11, Color8(220, 230, 240))


func _cat_name(c: String) -> String:
	return {"system": "System", "file": "Datei/Archiv", "disk": "Disketten",
		"music": "Musik", "graphics": "Grafik", "text": "Text", "code": "Code",
		"comm": "Kommunikation", "scene": "Szene", "cd": "CD"}.get(c, "Programm")


func _cat_color(c: String) -> Color:
	return {"system": Color8(40, 66, 96), "file": Color8(60, 60, 90), "disk": Color8(40, 74, 70),
		"music": Color8(70, 50, 96), "graphics": Color8(80, 56, 40), "text": Color8(80, 74, 60),
		"code": Color8(40, 74, 50), "comm": Color8(30, 70, 80), "scene": Color8(74, 40, 70),
		"cd": Color8(50, 60, 90)}.get(c, Color8(40, 66, 96))
