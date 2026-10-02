class_name WbShellWindow
extends Wb13Window
## Shell/CLI — das AmigaDOS-Gefühl: „1>“-Prompt, weiße Schrift auf blau,
## blinkender oranger Cursor. Kleine, echte Befehlspalette der Ära; `guru`
## ist das Easter Egg (Software Failure … wie damals). Programme lassen sich
## per Namen starten.

var _lines: Array = []
var _input := ""
var _t := 0.0

const ALEX_RISKY_QUEST := "q_alex_risky_1992"
const WorkbenchVersionCatalog := preload("res://scripts/ui/workbench_versions.gd")


func _init() -> void:
	title = Loc.t("ui.wb_shell_window.werkbank_shell", "Werkbank Shell")


func _ready() -> void:
	super()
	focus_mode = Control.FOCUS_ALL
	set_process(true)
	Localization.locale_changed.connect(_on_locale_changed)
	_reset_localized_lines()
	grab_focus.call_deferred()


func _reset_localized_lines() -> void:
	_lines.clear()
	_lines.append(Loc.t("ui.wb_shell_window.process", "Neuer Shell-Prozess 1"))
	if (QuestManager.is_active(ALEX_RISKY_QUEST) \
			or TaskManager.is_open(VirusManager.SCARE_TASK_ID)) \
			and ProgramLibrary.is_installed("viruschecker"):
		_lines.append(Loc.t("ui.wb_shell_window.quest_ready", "Auftragsprogramm bereit: VIRUSCHECKER"))
		_lines.append(Loc.t("ui.wb_shell_window.enter_return", "Eingeben und RETURN drücken."))


func _on_locale_changed(_locale: String) -> void:
	title = Loc.t("ui.wb_shell_window.werkbank_shell", "Sommerbench-Shell")
	_reset_localized_lines()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if int(_t * 2.0) != int((_t - delta) * 2.0):
		queue_redraw()


func _content_draw(crp: Rect2, sx: float, sy: float) -> void:
	var font := Wb13.font()
	var fs := Wb13.fsize(sy)
	var lh := 18.0 * sy
	var max_lines := maxi(1, int(crp.size.y / lh) - 1)
	var start := maxi(0, _lines.size() - max_lines)
	var y := crp.position.y + 16.0 * sy
	for i in range(start, _lines.size()):
		draw_string(font, Vector2(crp.position.x + 6.0 * sx, y), str(_lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
		y += lh
	var prompt := "1> " + _input
	draw_string(font, Vector2(crp.position.x + 6.0 * sx, y), prompt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
	if int(_t * 2.0) % 2 == 0 and has_focus():
		var w := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(crp.position.x + 6.0 * sx + w, y - 14.0 * sy, 8.0 * sx, 16.0 * sy), Wb13.orange())


func _content_press(_v: Vector2, _dbl: bool) -> void:
	grab_focus()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			return  # global: aufstehen
		accept_event()
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_run_line()
		elif event.keycode == KEY_BACKSPACE:
			_input = _input.substr(0, maxi(0, _input.length() - 1))
		elif event.unicode >= 32:
			_input += char(event.unicode)
		queue_redraw()
		return
	super(event)


func _print(s: String) -> void:
	_lines.append(s)
	if _lines.size() > 200:
		_lines = _lines.slice(_lines.size() - 200)


func _run_line() -> void:
	var line := _input.strip_edges()
	_print("1> " + _input)
	_input = ""
	if line == "":
		return
	var parts := line.split(" ", false)
	var cmd := parts[0].to_lower()
	var arg := line.substr(parts[0].length()).strip_edges()
	match cmd:
		"help", "?":
			_print("dir avail date echo version why cls loadwb endshell guru")
			_print(Loc.t("ui.wb_shell_window.help_programs", "Programme über ihren Namen starten, z. B. protracker"))
		"dir":
			_print(Loc.t("ui.wb_shell_window.drawers", "Werkzeuge (dir)   System (dir)   Voreinstellungen (dir)   Leer (dir)"))
			var names := PackedStringArray()
			for p: Dictionary in ProgramLibrary.installed_programs():
				names.append(str(p["id"]))
			_print("  ".join(names) if not names.is_empty() else Loc.t("ui.wb_shell_window.none_installed", "(keine Programme installiert)"))
		"avail":
			var memory := PlayerStats.ram_breakdown()
			var chip := int(memory["chip_kb"]) * 1024
			var slow := int(memory["slow_kb"]) * 1024
			var fast := int(memory["fast_kb"]) * 1024
			var total := chip + slow + fast
			_print(Loc.t("ui.wb_shell_window.memory_header", "Typ    Verfügbar    Belegt    Maximum"))
			_print("chip     %7d   %7d    %7d" % [int(chip * 0.6), int(chip * 0.4), chip])
			if slow > 0:
				_print("slow     %7d   %7d    %7d" % [int(slow * 0.65), int(slow * 0.35), slow])
			if fast > 0:
				_print("fast     %7d   %7d    %7d" % [int(fast * 0.7), int(fast * 0.3), fast])
			_print("total    %7d   %7d    %7d" % [int(total * 0.62),
				int(total * 0.38), total])
		"date":
			const M := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
			_print("%s %02d-%s-%02d" % [TimeManager.localized_weekday_name(), TimeManager.day,
				M[TimeManager.month - 1], TimeManager.year % 100])
		"echo":
			_print(arg)
		"version":
			var kick_cfg := KickstartScreen.config()
			var wb_cfg := WorkbenchVersionCatalog.active()
			_print(Loc.t("ui.wb_shell_window.version", "Kickstart-Version %s.  Sommerbench-Version %s") % [
				str(kick_cfg.get("rom_revision", wb_cfg.get("rom_revision", "34.5"))),
				str(wb_cfg.get("workbench_revision", "34.20")),
			])
		"why":
			_print(Loc.t("ui.wb_shell_window.no_return_value", "Der letzte Befehl hat keinen Rückgabewert gesetzt."))
		"cls", "clear":
			_lines = []
		"loadwb":
			_print(Loc.t("ui.wb_shell_window.already_running", "Sommerbench läuft bereits."))
		"endshell", "endcli", "exit":
			close_window()
		"guru":
			UIManager.show_guru("#00000004.0000AAC0")
		_:
			# Programm per Name/Id starten?
			for p: Dictionary in ProgramLibrary.installed_programs():
				if str(p["id"]).to_lower() == cmd \
						or str(p.get("display_name", "")).to_lower() == line.to_lower():
					_print(Loc.t("ui.wb_shell_window.starting", "Starte %s …") % p.get("display_name", cmd))
					UIManager.open_program(str(p["id"]))
					return
			_print(Loc.t("ui.wb_shell_window.unknown_command", "%s: Unbekannter Befehl") % cmd)
	queue_redraw()
