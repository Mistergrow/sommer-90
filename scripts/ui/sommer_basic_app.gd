extends WbApp
## Sommer BASIC 1.0: echter Quelltexteditor, Live-Lexer, Compilerdiagnostik
## und ausfuehrbarer 1990er Sprachkern. Spaetere Module docken an Language/VM an.

const Language := preload("res://scripts/sommer_basic/sommer_basic_language.gd")
const VM := preload("res://scripts/sommer_basic/sommer_basic_vm.gd")
const Preview := preload("res://scripts/ui/sommer_basic_preview.gd")
const FeatureCatalog := preload("res://scripts/data/sommer_basic_feature_catalog.gd")
const GameCatalog := preload("res://scripts/data/sommer_game_module_catalog.gd")
const MagazineCatalog := preload("res://scripts/data/magazine_program_catalog.gd")
const ProjectStore := preload("res://scripts/sommer_basic/sommer_basic_project_store.gd")

var _editor: CodeEdit
var _diagnostics: RichTextLabel
var _console: RichTextLabel
var _preview: Control
var _input_line: LineEdit
var _analysis: Dictionary = {}
var _signature := ""
var _vm: RefCounted
var _dirty := false
var _completion_entry_count := 0
var _queued_inputs: Array = []
var _runtime_files: Dictionary = {}
var _runtime_banks: Dictionary = {}
var _implement_button: Dictionary = {}
var _new_button: Dictionary = {}


func _init() -> void:
	app_title = Loc.t("ui.sommer_basic.title", "SOMMER BASIC  ·  ENTERPRISE IDE")
	app_bg = Color8(8, 14, 25)
	app_bar = Color8(22, 61, 91)
	app_accent = Color8(50, 220, 232)


func _build_app() -> void:
	ProjectStore.migrate_legacy()
	_editor = CodeEdit.new()
	_editor.name = "SourceEditor"
	_editor.text = ProjectStore.active_source(
		str(GameManager.flags.get("sommer_basic_source", _starter_source())))
	_editor.placeholder_text = Loc.t("ui.sommer_basic.placeholder.source", "10 PRINT \"HALLO SOMMER '90\"")
	_editor.gutters_draw_line_numbers = true
	_editor.gutters_zero_pad_line_numbers = true
	_editor.minimap_draw = true
	_editor.line_folding = true
	_editor.auto_brace_completion_enabled = true
	_editor.code_completion_enabled = true
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_editor.add_theme_font_override("font", Wb13.font())
	_editor.add_theme_font_size_override("font_size", 13)
	_style_editor()
	_editor.syntax_highlighter = _make_highlighter()
	_editor.text_changed.connect(_on_source_changed)
	_editor.caret_changed.connect(_on_caret_changed)
	_editor.code_completion_requested.connect(_offer_code_completion)
	add_child(_editor)

	_preview = Preview.new()
	_preview.name = "ProgramPreview"
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview)

	_console = _make_readout()
	_console.name = "Console"
	add_child(_console)
	_input_line = LineEdit.new()
	_input_line.name = "ProgramInput"
	_input_line.placeholder_text = Loc.t("ui.sommer_basic.placeholder.input", "PROGRAMMEINGABE · RETURN")
	_input_line.add_theme_font_override("font", Wb13.font())
	_input_line.add_theme_font_size_override("font_size", 10)
	_input_line.text_submitted.connect(_submit_program_input)
	var input_box := StyleBoxFlat.new()
	input_box.bg_color = Color8(5, 16, 22)
	input_box.border_color = app_accent
	input_box.set_border_width_all(1)
	input_box.set_content_margin_all(4)
	_input_line.add_theme_stylebox_override("normal", input_box)
	_input_line.add_theme_stylebox_override("focus", input_box)
	add_child(_input_line)
	_diagnostics = _make_readout()
	_diagnostics.name = "Diagnostics"
	add_child(_diagnostics)

	add_button(Loc.t("ui.sommer_basic.action.run", "▶ START"), Rect2(18, VH - 30, 76, 20), _run_program, Color8(75, 235, 125))
	add_button(Loc.t("ui.sommer_basic.action.stop", "■ STOP"), Rect2(100, VH - 30, 60, 20), _stop_program, Color8(245, 92, 82))
	add_button(Loc.t("ui.sommer_basic.action.check", "PRÜFEN"), Rect2(166, VH - 30, 72, 20), _compile, app_accent)
	add_button(Loc.t("ui.sommer_basic.action.save", "SICHERN"), Rect2(244, VH - 30, 72, 20), _save_source, Color8(255, 174, 48))
	_implement_button = add_button(Loc.t("ui.sommer_basic.action.implement", "IMPLEMENTIEREN"),
		Rect2(322, VH - 30, 116, 20), _implement_project, Color8(75, 235, 125))
	_new_button = add_button(Loc.t("ui.sommer_basic.action.new", "NEU"), Rect2(444, VH - 30, 54, 20), _new_source, app_accent)
	add_button(Loc.t("ui.sommer_basic.action.help", "HILFE"), Rect2(504, VH - 30, 58, 20), _show_help, app_accent)
	_vm = VM.new()
	_analyze_live()
	_refresh_project_ui()


func _layout_app() -> void:
	if _editor == null:
		return
	_place(_editor, Rect2(12, 72, 382, VH - 110))
	_place(_preview, Rect2(402, 72, 226, 112))
	_place(_console, Rect2(402, 190, 226, 68))
	_place(_input_line, Rect2(402, 263, 226, 22))
	_place(_diagnostics, Rect2(402, 290, 226, 72))


func _content(font: Font) -> void:
	rect(12, 24, VW - 24, 20, Color8(11, 26, 42))
	rect_line(12, 24, VW - 24, 20, app_accent)
	text(font, Loc.t("ui.sommer_basic.header.source", "QUELLE · MAIN.SB"), 20, 38, 10, Color8(242, 174, 48))
	var error_count := int(_analysis.get("errors", 0))
	var state_text := Loc.t("ui.sommer_basic.header.clean", "LIVE · FEHLERFREI") if error_count == 0 else \
		Loc.t("ui.sommer_basic.header.errors", "LIVE · %d FEHLER") % error_count
	text(font, state_text, 268, 38, 10,
		Color8(80, 235, 125) if error_count == 0 else Color8(255, 82, 92))
	var annual := FeatureCatalog.annual_profile(_current_year())
	text(font, "V%s · %s" % [str(annual.get("version", "?")), _chipset_label()],
		502, 38, 9, app_accent)
	_draw_project_contract(font)
	text(font, _signature if not _signature.is_empty() else
		Loc.t("ui.sommer_basic.hint.editor", "F1 Hilfe · Strg+Leertaste Befehle · Fehler werden beim Tippen geprüft"),
		16, VH - 36, 8, Color8(144, 184, 208))


func _style_editor() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(4, 9, 17)
	box.border_color = Color8(38, 104, 132)
	box.set_border_width_all(1)
	box.set_content_margin_all(7)
	for state in ["normal", "focus", "read_only"]:
		_editor.add_theme_stylebox_override(state, box)
	_editor.add_theme_color_override("font_color", Color8(205, 220, 230))
	_editor.add_theme_color_override("caret_color", Color8(255, 188, 42))
	_editor.add_theme_color_override("selection_color", Color8(33, 80, 108))
	_editor.add_theme_color_override("line_number_color", Color8(72, 118, 140))
	_editor.add_theme_color_override("current_line_color", Color(0.06, 0.18, 0.23, 0.72))


func _make_highlighter() -> CodeHighlighter:
	var highlighter := CodeHighlighter.new()
	highlighter.number_color = Color8(255, 191, 64)
	highlighter.symbol_color = Color8(178, 194, 210)
	highlighter.function_color = Color8(255, 92, 181)
	highlighter.member_variable_color = Color8(131, 218, 255)
	for command in Language.CORE_COMMANDS:
		_add_keyword_pair(highlighter, command, Color8(73, 232, 130))
	for command in Language.GRAPHICS_COMMANDS:
		_add_keyword_pair(highlighter, command, Color8(48, 218, 238))
	for command in Language.AUDIO_COMMANDS:
		_add_keyword_pair(highlighter, command, Color8(255, 105, 194))
	for command in Language.FILE_COMMANDS:
		_add_keyword_pair(highlighter, command, Color8(186, 127, 255))
	for command in Language.ENGINE_COMMANDS:
		_add_keyword_pair(highlighter, command, Color8(255, 170, 48))
	for keyword in Language.KEYWORDS:
		_add_keyword_pair(highlighter, keyword, Color8(255, 145, 54))
	for type_name in Language.TYPES:
		_add_keyword_pair(highlighter, type_name, Color8(121, 187, 255))
	for function_name in Language.FUNCTIONS:
		_add_keyword_pair(highlighter, function_name, Color8(255, 227, 80))
	highlighter.add_color_region("\"", "\"", Color8(245, 228, 155))
	highlighter.add_color_region("'", "", Color8(98, 150, 112), true)
	return highlighter


func _add_keyword_pair(highlighter: CodeHighlighter, word: String, color: Color) -> void:
	highlighter.add_keyword_color(word, color)
	highlighter.add_keyword_color(word.to_lower(), color)


func _offer_code_completion() -> void:
	_completion_entry_count = 0
	for word in Language.commands():
		var command := str(word)
		var feature := FeatureCatalog.feature_by_symbol(command)
		if not feature.is_empty() and not FeatureCatalog.supports(command,
				_current_year(), _target_hardware_profile()):
			continue
		var game_module := GameCatalog.module_for_symbol(command)
		if not game_module.is_empty() and not bool(GameCatalog.available(
				str(game_module.get("id", "")), _current_year(),
				_target_hardware_profile(), _unlocked_game_modules()).get("available", false)):
			continue
		_editor.add_code_completion_option(CodeEdit.KIND_FUNCTION, command,
			command + " ", _completion_color(command))
		_completion_entry_count += 1
	for function_name in Language.FUNCTIONS:
		var function_word := str(function_name)
		var feature := FeatureCatalog.feature_by_symbol(function_word)
		if not feature.is_empty() and not FeatureCatalog.supports(function_word,
				_current_year(), _target_hardware_profile()):
			continue
		var game_module := GameCatalog.module_for_symbol(function_word)
		if not game_module.is_empty() and not bool(GameCatalog.available(
				str(game_module.get("id", "")), _current_year(),
				_target_hardware_profile(), _unlocked_game_modules()).get("available", false)):
			continue
		_editor.add_code_completion_option(CodeEdit.KIND_FUNCTION, function_word,
			function_word, Color8(255, 227, 80))
		_completion_entry_count += 1
	for type_name in Language.TYPES:
		var type_word := str(type_name)
		_editor.add_code_completion_option(CodeEdit.KIND_CONSTANT, type_word,
			type_word, Color8(121, 187, 255))
		_completion_entry_count += 1
	_editor.update_code_completion_options(true)


func _completion_color(command: String) -> Color:
	if command in Language.GRAPHICS_COMMANDS:
		return Color8(48, 218, 238)
	if command in Language.AUDIO_COMMANDS:
		return Color8(255, 105, 194)
	if command in Language.FILE_COMMANDS:
		return Color8(186, 127, 255)
	if command in Language.ENGINE_COMMANDS:
		return Color8(255, 170, 48)
	return Color8(73, 232, 130)


func _make_readout() -> RichTextLabel:
	var readout := RichTextLabel.new()
	readout.bbcode_enabled = true
	readout.fit_content = false
	readout.scroll_active = true
	readout.add_theme_font_override("normal_font", Wb13.font())
	readout.add_theme_font_size_override("normal_font_size", 10)
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(3, 8, 14)
	box.border_color = Color8(34, 78, 102)
	box.set_border_width_all(1)
	box.set_content_margin_all(5)
	readout.add_theme_stylebox_override("normal", box)
	return readout


func _place(control: Control, virtual_rect: Rect2) -> void:
	var physical := _R(virtual_rect)
	control.position = physical.position
	control.size = physical.size


func _on_source_changed() -> void:
	_dirty = true
	_queued_inputs.clear()
	_analyze_live()


func _on_caret_changed() -> void:
	var line := _editor.get_line(_editor.get_caret_line()).strip_edges()
	var numbered := Language._take_line_number(line)
	_signature = Language.signature_for(Language._first_word(str(numbered.get("body", line))))
	queue_redraw()


func _analyze_live() -> void:
	_analysis = Language.analyze_for_profile(_editor.text, _current_year(),
		_target_hardware_profile(), _unlocked_game_modules())
	for line_index in _editor.get_line_count():
		_editor.set_line_background_color(line_index, Color(0, 0, 0, 0))
	var rows: Array[String] = []
	for value in _analysis.get("diagnostics", []):
		var diagnostic: Dictionary = value
		var line_index := int(diagnostic.get("line", 0))
		_editor.set_line_background_color(line_index, Color(0.42, 0.04, 0.07, 0.45))
		rows.append("[color=#ff6672]Z%d · %s[/color]  %s" % [line_index + 1,
			str(diagnostic.get("code", "E")), str(diagnostic.get("message", ""))])
	if rows.is_empty():
		rows.append(_localized_lines("ui.sommer_basic.diagnostics.clean", "[color=#50eb82]✓ 0 Fehler[/color]\nLexer und Strukturprüfung sind aktuell."))
	_diagnostics.text = "\n".join(rows)
	_on_caret_changed()
	queue_redraw()


func _compile() -> void:
	_analyze_live()
	if bool(_analysis.get("ok", false)):
		_console.text = _localized_lines("ui.sommer_basic.build.ok", "[color=#50eb82]BUILD OK[/color]\n%d Zeilen · Sommer BASIC %s · %s") % [
			int(_analysis.get("line_count", 0)), str(_analysis.get("version", "?")),
			_chipset_label()]
	else:
		_console.text = _localized_lines("ui.sommer_basic.build.blocked", "[color=#ff6672]BUILD GESTOPPT[/color]\n%d Fehler zuerst beheben.") % int(_analysis.get("errors", 0))


func _run_program() -> void:
	_analyze_live()
	if not bool(_analysis.get("ok", false)):
		_compile()
		return
	var result: Dictionary = _vm.call("run", _editor.text, {
		"inputs": _queued_inputs,
		"files": _runtime_files,
		"banks": _runtime_banks,
		"seed": int(GameManager.flags.get("sommer_basic_seed", 1990)),
		"year": _current_year(),
		"hardware_profile": _target_hardware_profile(),
		"game": _game_context(),
	})
	var output_lines: Array = result.get("output", [])
	_console.text = _localized_lines("ui.sommer_basic.output.title", "[color=#55ddff]AUSGABE[/color]\n") + "\n".join(output_lines)
	_preview.call("show_commands", result.get("draw_commands", []))
	_runtime_files = result.get("files", {}).duplicate(true)
	_runtime_banks = result.get("banks", {}).duplicate(true)
	if bool(result.get("waiting_for_input", false)):
		_input_line.placeholder_text = str(result.get("input_request", Loc.t("ui.sommer_basic.placeholder.waiting", "EINGABE ERWARTET")))
		_input_line.grab_focus()
	if not bool(result.get("ok", false)):
		_console.text += "\n[color=#ff6672]%s[/color]" % str(result.get("message", Loc.t("ui.sommer_basic.runtime.error", "Laufzeitfehler")))
	elif not bool(result.get("waiting_for_input", false)):
		var progress := ProjectStore.record_successful_run(_editor.text, result)
		if not bool(progress.get("ok", false)):
			_console.text += "\n[color=#ffae30]AUFGABE[/color]\n%s" % str(progress.get("reason", ""))
		elif bool(progress.get("advanced", false)):
			_console.text += "\n[color=#50eb82]MEILENSTEIN[/color]\n%s" % str(progress.get("message", ""))
			var phase := str(progress.get("phase", ""))
			if phase == ProjectStore.PHASE_VERIFIED:
				_note_project_action("sommer_basic_verify")
			elif phase == ProjectStore.PHASE_IMPROVED:
				_note_project_action("sommer_basic_improve")
			ProjectStore.save_active_source(_editor.text)
		_refresh_project_ui()


func _submit_program_input(value: String) -> void:
	_queued_inputs.append(value)
	_input_line.clear()
	_input_line.placeholder_text = Loc.t("ui.sommer_basic.placeholder.input", "PROGRAMMEINGABE · RETURN")
	_run_program()


func _stop_program() -> void:
	_vm.call("reset")
	_console.text = _localized_lines("ui.sommer_basic.runtime.stopped", "[color=#ffae30]STOP[/color]\nProgramm angehalten.")


func _save_source() -> void:
	GameManager.flags["sommer_basic_source"] = _editor.text
	GameManager.flags["sommer_basic_source_version"] = 2
	ProjectStore.save_active_source(_editor.text)
	_dirty = false
	_console.text = _localized_lines("ui.sommer_basic.save.done", "[color=#50eb82]GESICHERT[/color]\nMAIN.SB liegt im Projektordner.")


func _new_source() -> void:
	var current := ProjectStore.active_project()
	_editor.text = str(current.get("canonical_source", _starter_source())) \
		if not current.is_empty() else _starter_source()
	_editor.set_caret_line(0)
	_dirty = true
	_console.text = _localized_lines("ui.sommer_basic.reset.done",
		"[color=#ffae30]VORLAGE WIEDERHERGESTELLT[/color]\nDer Magazinstand ist wieder im Editor.") \
		if not current.is_empty() else ""


func _implement_project() -> void:
	var result := ProjectStore.implement_active()
	if not bool(result.get("ok", false)):
		_console.text = _localized_lines("ui.sommer_basic.implement.blocked",
			"[color=#ff6672]IMPLEMENTIERUNG GESPERRT[/color]\n%s") % str(result.get("reason", ""))
		_refresh_project_ui()
		return
	var listing_id := str(result.get("listing_id", ""))
	_note_project_action("sommer_basic_implement")
	_note_project_action("sommer_basic_implement:%s" % listing_id)
	MemoryManager.record("kreativ", "das Sommer-BASIC-Kapitel %s implementiert" % listing_id)
	_console.text = _localized_lines("ui.sommer_basic.implement.done",
		"[color=#50eb82]IMPLEMENTIERT[/color]\n%s") % str(result.get("message", ""))
	UIManager.toast(str(result.get("message", "")))
	_refresh_project_ui()


func _note_project_action(action_id: String) -> void:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null:
		return
	var current := ProjectStore.active_project()
	quests.call("note_action", action_id, 1, {
		"listing_id": str(current.get("listing_id", "")),
		"issue_id": str(current.get("issue_id", "")),
		"chapter": int(current.get("chapter", 0)),
	})


func _refresh_project_ui() -> void:
	var current := ProjectStore.active_project()
	var phase := str(current.get("phase", ""))
	var implement_node := _implement_button.get("node") as Button
	if implement_node != null:
		implement_node.disabled = phase != ProjectStore.PHASE_IMPROVED
		_implement_button["label"] = Loc.t("ui.sommer_basic.action.implemented", "IMPLEMENTIERT") \
			if phase == ProjectStore.PHASE_IMPLEMENTED else Loc.t(
				"ui.sommer_basic.action.implement", "IMPLEMENTIEREN")
	var new_node := _new_button.get("node") as Button
	if new_node != null:
		_new_button["label"] = Loc.t("ui.sommer_basic.action.template", "VORLAGE") \
			if not current.is_empty() else Loc.t("ui.sommer_basic.action.new", "NEU")
	queue_redraw()


func _draw_project_contract(font: Font) -> void:
	var current := ProjectStore.active_project()
	rect(12, 47, VW - 24, 21, Color8(5, 18, 28))
	rect_line(12, 47, VW - 24, 21, Color8(38, 104, 132))
	if current.is_empty():
		text(font, Loc.t("ui.sommer_basic.project.free", "FREIES PROJEKT · KEIN MAGAZINKAPITEL AKTIV"),
			20, 61, 8, Color8(133, 184, 204))
		return
	var entry := MagazineCatalog.by_listing(str(current.get("listing_id", "")))
	var title_key := "title_en" if TranslationServer.get_locale().begins_with("en") else "title_de"
	var task := ProjectStore.improvement(entry)
	var brief_key := "brief_en" if TranslationServer.get_locale().begins_with("en") else "brief_de"
	var phase := str(current.get("phase", ProjectStore.PHASE_TYPED))
	text(font, "KAPITEL %02d/%02d · %s · %s" % [int(current.get("chapter", 1)),
		int(current.get("chapter_count", 10)), str(entry.get(title_key, "PROJEKT")),
		ProjectStore.phase_label(phase)], 20, 55, 7, Color8(255, 174, 48))
	var instruction := str(task.get(brief_key, "")) if ProjectStore.rank(phase) >= \
		ProjectStore.rank(ProjectStore.PHASE_VERIFIED) else Loc.t(
			"ui.sommer_basic.project.run_first", "ZUERST: Original unveraendert starten und Soll-Lauf bestehen.")
	text(font, instruction, 20, 65, 7, Color8(80, 225, 235))


func _show_help() -> void:
	var year := _current_year()
	var symbols := FeatureCatalog.symbols_available_in_year(year,
		_target_hardware_profile())
	var introduced: Array[String] = []
	for entry: Dictionary in FeatureCatalog.introduced_in_year(year):
		introduced.append(str(entry.get("symbol", "")))
	var game_modules: Array[String] = []
	for module_id: Variant in _unlocked_game_modules():
		var module := GameCatalog.module(str(module_id))
		game_modules.append(str(module.get("name_de", module_id)))
	_console.text = _localized_lines("ui.sommer_basic.help.title", "[color=#ffae30]SOMMER BASIC · ENTERPRISE[/color]\n") + \
		_localized_lines("ui.sommer_basic.help.profile", "Sommer %d · %s · %d Features\n") % [year, _chipset_label(), symbols.size()] + \
		(_localized_lines("ui.sommer_basic.help.new", "NEU   %s\n") % " ".join(introduced) if not introduced.is_empty() else "") + \
		(Loc.t("ui.sommer_basic.help.engine", "SOMMER GAME   %s\n") % ", ".join(game_modules) if not game_modules.is_empty() else "") + \
		Loc.t("ui.sommer_basic.help.completion", "Strg+Leertaste zeigt nur Befehle, die auf dem aktuellen Rechner laufen.")


func _game_context() -> Dictionary:
	var manager := get_node_or_null("/root/SommerGameManager")
	return manager.call("runtime_context") if manager != null else {
		"unlocked_modules": [], "hardware_profile": _target_hardware_profile()}


func _unlocked_game_modules() -> Array:
	return (_game_context().get("unlocked_modules", []) as Array).duplicate()


func _localized_lines(key: String, fallback: String) -> String:
	return Loc.t(key, fallback).replace("\\n", "\n")


func _starter_source() -> String:
	return "10 REM SOMMER BASIC · ERSTES PROGRAMM\n" + \
		"20 SCREEN 320, 200, 16\n" + \
		"30 CLS\n" + \
		"40 FOR X = 20 TO 280 STEP 20\n" + \
		"50 LINE 160, 100, X, 180, 2\n" + \
		"60 NEXT X\n" + \
		"70 CIRCLE 160, 82, 34, 4\n" + \
		"80 PRINT \"SOMMER '90 BEREIT\"\n" + \
		"90 END"


func _current_year() -> int:
	return clampi(int(TimeManager.year), FeatureCatalog.FIRST_YEAR,
		FeatureCatalog.LAST_YEAR)


func _target_hardware_profile() -> String:
	match str(PlayerStats.desk_model("computer_model")):
		"amiga_1200":
			return "amiga_1200_aga_hdd_4mb" if PlayerStats.hdd_is_usable() \
				and float(PlayerStats.hardware.get("ram_mb", 0.0)) >= 4.0 \
				else "amiga_1200_aga_2mb"
		"amiga_600":
			return "amiga_500_ecs_1mb"
		_:
			return "amiga_500_ocs_1mb"


func _chipset_label() -> String:
	match _target_hardware_profile():
		"amiga_1200_aga_2mb", "amiga_1200_aga_hdd_4mb": return "AGA"
		"amiga_500_ecs_1mb": return "ECS"
		_: return "OCS"
