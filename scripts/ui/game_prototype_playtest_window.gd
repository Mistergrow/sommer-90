class_name GamePrototypePlaytestWindow
extends RetroWindow
## Spielbarer QA-Lauf fuer selbst gebaute Spiel-Prototypen.
##
## Kein Etikettenwechsel im Demo-Studio: Der Spieler muss die aus seinem Projekt-
## Seed erzeugte kleine Spielfeldregel wirklich beherrschen. Erst eingesammelte
## Datenchips plus erreichter Ausgang ergeben den persistierten Gameplay-Stempel.

signal playtest_completed(report: Dictionary)

const GRID := 7
const START := Vector2i(0, GRID - 1)
const EXIT := Vector2i(GRID - 1, 0)

var project: Dictionary = {}
var _player := START
var _chips: Array[Vector2i] = []
var _hazards: Array[Vector2i] = []
var _collected := 0
var _steps := 0
var _lives := 3
var _finished := false
var _cells: Array[Button] = []
var _status: Label
var _grid: GridContainer
var _briefing: Label


func _init() -> void:
	title = Loc.t("ui.game_prototype_playtest_window.spiel_prototyp_echter_qa_lauf", "SPIEL-PROTOTYP · ECHTER QA-LAUF")
	win_size = Vector2(660, 620)


func _ready() -> void:
	super._ready()
	_build_ui()
	_reset_board()


func _build_ui() -> void:
	_briefing = Label.new()
	_briefing.name = "GameBriefing"
	_briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_briefing.custom_minimum_size.y = 62
	content.add_child(_briefing)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	content.add_child(_status)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.columns = GRID
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	center.add_child(_grid)
	content.add_child(center)
	for y in GRID:
		for x in GRID:
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(58, 50)
			cell.focus_mode = Control.FOCUS_NONE
			cell.pressed.connect(_click_cell.bind(Vector2i(x, y)))
			_cells.append(cell)
			_grid.add_child(cell)

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 5)
	controls.add_child(make_button(Loc.t("ui.game_prototype_playtest_window.text", "←"), _move.bind(Vector2i.LEFT)))
	controls.add_child(make_button(Loc.t("ui.game_prototype_playtest_window.text_fa1b", "↑"), _move.bind(Vector2i.UP)))
	controls.add_child(make_button(Loc.t("ui.game_prototype_playtest_window.text_a014", "↓"), _move.bind(Vector2i.DOWN)))
	controls.add_child(make_button(Loc.t("ui.game_prototype_playtest_window.text_0616", "→"), _move.bind(Vector2i.RIGHT)))
	controls.add_child(make_button(Loc.t("ui.game_prototype_playtest_window.neustart", "NEUSTART"), _reset_board))
	content.add_child(controls)


func _reset_board() -> void:
	_player = START
	_chips = []
	_hazards = []
	_collected = 0
	_steps = 0
	_lives = clampi(int(project.get("game_lives", 3)), 1, 9)
	_finished = false
	var mode := str(project.get("game_mode", "collector"))
	var difficulty := str(project.get("game_difficulty", "normal"))
	var objective_count := clampi(int(project.get("game_objectives", 3)), 1, 8)
	var seed_value := int(project.get("seed", 1992)) + mode.hash() + difficulty.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var occupied := {START: true, EXIT: true}
	var chip_count := objective_count
	var hazard_count: int = int({"easy": 2, "normal": 4, "hard": 6}.get(difficulty, 4))
	if mode == "survival":
		hazard_count += 2
	elif mode == "puzzle":
		hazard_count = maxi(1, hazard_count - 1)
	elif mode == "courier":
		hazard_count += 1
	_briefing.text = "%s · %s\n%s" % [
		str(project.get("title", "GAME PROTOTYPE")).to_upper(), difficulty.to_upper(),
		_mode_briefing(mode, chip_count)]
	while _chips.size() < chip_count:
		var p := Vector2i(rng.randi_range(0, GRID - 1), rng.randi_range(0, GRID - 1))
		if not occupied.has(p):
			occupied[p] = true
			_chips.append(p)
	while _hazards.size() < hazard_count:
		var p := Vector2i(rng.randi_range(0, GRID - 1), rng.randi_range(0, GRID - 1))
		if not occupied.has(p):
			occupied[p] = true
			_hazards.append(p)
	_refresh()


func _click_cell(pos: Vector2i) -> void:
	var delta := pos - _player
	if absi(delta.x) + absi(delta.y) == 1:
		_move(delta)


func _move(delta: Vector2i) -> void:
	if _finished:
		return
	var target := _player + delta
	if target.x < 0 or target.y < 0 or target.x >= GRID or target.y >= GRID:
		return
	_player = target
	_steps += 1
	if _player in _hazards:
		_lives -= 1
		_player = START
		if _lives <= 0:
			_finished = true
			_status.text = Loc.t("ui.game_prototype_playtest_window.qa_fehlgeschlagen_neustart_route_verbessern", "QA FEHLGESCHLAGEN · NEUSTART UND ROUTE VERBESSERN")
			_refresh()
			return
	if _player in _chips:
		_chips.erase(_player)
		_collected += 1
	if _player == EXIT and _chips.is_empty():
		_finished = true
		var report := {
			"passed": true, "mode": str(project.get("game_mode", "collector")),
			"difficulty": str(project.get("game_difficulty", "normal")),
			"objectives": int(project.get("game_objectives", 3)),
			"starting_lives": int(project.get("game_lives", 3)),
			"steps": _steps, "lives_left": _lives, "chips": _collected,
			"score": maxi(1, 100 - _steps + _lives * 8),
		}
		_status.text = Loc.t("ui.game_prototype_playtest_window.qa_grun_regeln_spielbar_d_schritte", "QA GRÜN · REGELN SPIELBAR · %d SCHRITTE") % _steps
		playtest_completed.emit(report)
	_refresh()


func _refresh() -> void:
	if not _finished:
		_status.text = Loc.t("ui.game_prototype_playtest_window.chips_d_leben_d_schritte_d", "CHIPS %d · LEBEN %d · SCHRITTE %d") % [_chips.size(), _lives, _steps]
	for y in GRID:
		for x in GRID:
			var pos := Vector2i(x, y)
			var cell: Button = _cells[y * GRID + x]
			cell.text = ""
			cell.tooltip_text = Loc.t("ui.game_prototype_playtest_window.leeres_feld", "Leeres Feld")
			if pos == EXIT:
				cell.text = Loc.t("ui.game_prototype_playtest_window.exit", "EXIT")
				cell.tooltip_text = Loc.t("ui.game_prototype_playtest_window.ausgang_offnet_erst_nach_allen_chips", "Ausgang — öffnet erst nach allen Chips")
			if pos in _hazards:
				cell.text = Loc.t("ui.game_prototype_playtest_window.virus", "VIRUS")
				cell.tooltip_text = Loc.t("ui.game_prototype_playtest_window.fehlerfeld_kostet_einen_versuch", "Fehlerfeld: kostet einen Versuch")
			if pos in _chips:
				cell.text = "◆"
				cell.tooltip_text = Loc.t("ui.game_prototype_playtest_window.datenchip", "Datenchip")
			if pos == _player:
				cell.text = Loc.t("ui.game_prototype_playtest_window.you", "YOU")
				cell.tooltip_text = Loc.t("ui.game_prototype_playtest_window.deine_spielfigur", "Deine Spielfigur")


func _mode_briefing(mode: String, objectives: int) -> String:
	match mode:
		"courier":
			return "KURIER-ROUTE · %d Pakete sichern, dann ohne Datenverlust zum EXIT." % objectives
		"survival":
			return "SURVIVAL · %d Energiekapseln bergen; Virenfelder setzen dich zum Start zurück." % objectives
		"puzzle":
			return "LOGIK-PUZZLE · %d Schalter finden und den sicheren Pfad zum EXIT lesen." % objectives
		_:
			return "COLLECTOR · %d Datenchips sammeln, danach öffnet sich EXIT." % objectives


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var delta := Vector2i.ZERO
	match event.keycode:
		KEY_LEFT, KEY_A: delta = Vector2i.LEFT
		KEY_RIGHT, KEY_D: delta = Vector2i.RIGHT
		KEY_UP, KEY_W: delta = Vector2i.UP
		KEY_DOWN, KEY_S: delta = Vector2i.DOWN
	if delta != Vector2i.ZERO:
		_move(delta)
		get_viewport().set_input_as_handled()
