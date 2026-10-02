class_name DemoMakerWindow
extends "res://scripts/ui/demo_maker_controller.gd"
## SZENE-STUDIO 2 — ein kleines, aber vollständiges Demoscene-Authoring-Spiel.
##
## Statt eines Einzeleffekt-Generators baut der Spieler eine Timeline aus Parts,
## verdrahtet die benötigten Code-Module, hält A500-artige Budgets ein und führt
## vor dem Release einen Build sowie einen 50-Hz-Testlauf aus. Die Darstellung
## bleibt bewusst innerhalb der fiktionalen Spielsysteme: Es wird kein echter
## Maschinencode erzeugt oder ausgeführt.
var _previous_track_id := ""


func _init() -> void:
	title = Loc.t("ui.demo_maker_window.szene_studio_ii_release_bauen", "SZENE-STUDIO II · RELEASE BAUEN")
	win_size = Vector2(1180, 720)


func _ready() -> void:
	super._ready()
	_previous_track_id = str(MusicManager.current)
	_project = DemoManager.load_draft()
	if _project.is_empty():
		_project = DemoManager.create_project()
	_build_header()
	_build_mode_switcher()
	_build_workspace()
	_build_footer()
	_refresh_all()


func _exit_tree() -> void:
	if not _music_changed_by_studio:
		return
	if _previous_track_id != "" and MusicManager.has_track(_previous_track_id):
		MusicManager.play(_previous_track_id)
	else:
		MusicManager.stop()


# ------------------------------------------------------------------ Aufbau

func _build_header() -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 42
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)

	_title_edit = DemoUi.line_edit("ProjectTitle", 210, 24)
	_title_edit.placeholder_text = Loc.t("ui.demo_maker_window.demo_titel", "Demo-Titel")
	_title_edit.text_changed.connect(_set_project_title_from_editor)
	_title_edit.focus_exited.connect(_finalize_project_title)
	header.add_child(DemoUi.labeled("PROJEKT", _title_edit, 11))

	_kind_option = OptionButton.new()
	_kind_option.name = "ProjectKind"
	_kind_option.custom_minimum_size.x = 112
	_kind_option.add_item("DEMO")
	_kind_option.set_item_metadata(0, "demo")
	_kind_option.add_item(Loc.t("ui.demo_maker_window.spiel_prototyp", "SPIEL-PROTOTYP"))
	_kind_option.set_item_metadata(1, "game")
	_kind_option.add_item(Loc.t("ui.demo_maker_window.club_intro", "CLUB-INTRO"))
	_kind_option.set_item_metadata(2, "club_intro")
	_kind_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_select_project_kind(str(_kind_option.get_item_metadata(index))))
	# Unsichtbarer Kompatibilitätsadapter für alte Tests/Szenenaufrufe. Die
	# sichtbare Auswahl liegt in der großen Modusleiste darunter.
	_kind_option.visible = false
	header.add_child(_kind_option)

	_group_edit = DemoUi.line_edit("GroupEdit", 150, 20)
	_group_edit.placeholder_text = Loc.t("ui.demo_maker_window.handle_gruppe", "Handle / Gruppe")
	_group_edit.text_changed.connect(_set_group_from_editor)
	_group_edit.focus_exited.connect(_finalize_group)
	header.add_child(DemoUi.labeled("HANDLE / GRUPPE", _group_edit, 11))

	_bpm_spin = SpinBox.new()
	_bpm_spin.name = "BpmSpin"
	_bpm_spin.min_value = 70
	_bpm_spin.max_value = 190
	_bpm_spin.step = 1
	_bpm_spin.custom_minimum_size.x = 76
	_bpm_spin.value_changed.connect(func(value: float) -> void:
		if not _guard:
			_project["bpm"] = int(value)
			_mark_dirty())
	header.add_child(DemoUi.labeled("BPM", _bpm_spin, 11))

	_track_option = OptionButton.new()
	_track_option.name = "TrackOption"
	_track_option.custom_minimum_size.x = 190
	_track_option.add_item(Loc.t("ui.demo_maker_window.silent_build", "— SILENT BUILD —"))
	_track_option.set_item_metadata(0, "")
	for track: Dictionary in MusicManager.owned_tracks():
		var idx := _track_option.item_count
		_track_option.add_item(str(track.get("title", track.get("id", "MOD"))).to_upper())
		_track_option.set_item_metadata(idx, str(track.get("id", "")))
	for creation: Dictionary in DemoManager.creator_library().get("music", []):
		var idx := _track_option.item_count
		_track_option.add_item("★ %s" % str(creation.get("title", "EIGENES PATTERN")).to_upper())
		_track_option.set_item_metadata(idx, "creation:tracker:%s" % str(creation.get("id", idx)))
	_track_option.item_selected.connect(_on_track_selected)
	header.add_child(DemoUi.labeled("4-KANAL-MOD", _track_option, 11))

	_status = Bezel.lcd_label(Loc.t("ui.demo_maker_window.edit_nicht_gebaut", "EDIT · NICHT GEBAUT"), C_WARN, 14)
	_status.name = "BuildStatus"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_status)


func _build_mode_switcher() -> void:
	var panel := PanelContainer.new()
	panel.name = "ProjectModeDeck"
	panel.custom_minimum_size.y = 94
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.032, 0.045, 0.96)
	style.border_color = Color(C_INFO, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	content.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	panel.add_child(root)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	root.add_child(row)
	_mode_badge = Bezel.lcd_label(
		Loc.t("ui.demo_maker_window.workflow", "WORKFLOW"), C_INFO, 11)
	_mode_badge.custom_minimum_size.x = 92
	_mode_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_mode_badge)
	var group := ButtonGroup.new()
	for definition: Dictionary in DemoModes.button_definitions():
		var kind := str(definition["id"])
		var button := make_button(str(definition["label"]), _select_project_kind.bind(kind))
		button.name = "Mode_%s" % kind
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38
		button.add_theme_font_size_override("font_size", 12)
		_mode_buttons[kind] = button
		row.add_child(button)
	_mode_description = Bezel.dim_label("", 10)
	_mode_description.name = "ModeDescription"
	_mode_description.clip_text = true
	_mode_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_mode_description)

	var profile_row := HBoxContainer.new()
	profile_row.name = "ModeProductionProfile"
	profile_row.add_theme_constant_override("separation", 6)
	root.add_child(profile_row)
	_demo_format_option = _make_metadata_option([
		["TRACKMO · DURCHLAUF", "trackmo"], ["MEGADEMO · MENÜ", "megademo"], ["DENTRO · KOMPAKT", "dentro"]])
	_demo_format_option.name = "DemoFormat"
	_demo_format_option.visible = false
	_demo_format_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_project["demo_format"] = str(_demo_format_option.get_item_metadata(index))
			_mark_dirty())
	var demo_choices := _make_choice_strip("demo_format", [
		["TRACKMO\nDURCHLAUF", "trackmo"], ["MEGADEMO\nMENÜ", "megademo"], ["DENTRO\nKOMPAKT", "dentro"]])
	demo_choices.add_child(_demo_format_option)
	_demo_profile_field = DemoUi.labeled("DEMO-FORMAT", demo_choices, 9)
	profile_row.add_child(_demo_profile_field)
	_intro_purpose_option = _make_metadata_option([
		["GRUPPEN-ID", "group_id"], ["PARTY-EINLADUNG", "invitation"], ["CRACKTRO", "cracktro"]])
	_intro_purpose_option.name = "IntroPurpose"
	_intro_purpose_option.visible = false
	_intro_purpose_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_project["intro_purpose"] = str(_intro_purpose_option.get_item_metadata(index))
			_mark_dirty())
	var intro_choices := _make_choice_strip("intro_purpose", [
		["GRUPPEN-ID\nVISITENKARTE", "group_id"], ["PARTY\nEINLADUNG", "invitation"], ["CRACKTRO\nSIGNATUR", "cracktro"]])
	intro_choices.add_child(_intro_purpose_option)
	_intro_profile_field = DemoUi.labeled("INTRO-AUFTRAG", intro_choices, 9)
	profile_row.add_child(_intro_profile_field)
	_game_difficulty_option = _make_metadata_option([
		["EASY · REVIEW", "easy"], ["NORMAL · RELEASE", "normal"], ["HARD · ARCADE", "hard"]])
	_game_difficulty_option.name = "GameDifficulty"
	_game_difficulty_option.visible = false
	_game_difficulty_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_project["game_difficulty"] = str(_game_difficulty_option.get_item_metadata(index))
			_mark_dirty())
	_game_lives_spin = _compact_spin(1, 9, 3)
	_game_lives_spin.name = "GameLives"
	_game_lives_spin.visible = false
	_game_lives_spin.value_changed.connect(func(value: float) -> void:
		if not _guard:
			_project["game_lives"] = int(value)
			_mark_dirty())
	_game_objectives_spin = _compact_spin(1, 8, 3)
	_game_objectives_spin.name = "GameObjectives"
	_game_objectives_spin.visible = false
	_game_objectives_spin.value_changed.connect(func(value: float) -> void:
		if not _guard:
			_project["game_objectives"] = int(value)
			_mark_dirty())
	var game_scope := HBoxContainer.new()
	game_scope.add_theme_constant_override("separation", 5)
	var difficulty_choices := _make_choice_strip("game_difficulty", [
		["EASY", "easy"], ["NORMAL", "normal"], ["HARD", "hard"]])
	difficulty_choices.add_child(_game_difficulty_option)
	game_scope.add_child(difficulty_choices)
	var lives_card := _make_stepper_card("game_lives", "LEBEN", 1, 9)
	lives_card.add_child(_game_lives_spin)
	game_scope.add_child(lives_card)
	var objectives_card := _make_stepper_card("game_objectives", "ZIELE", 1, 8)
	objectives_card.add_child(_game_objectives_spin)
	game_scope.add_child(objectives_card)
	_game_scope_field = DemoUi.labeled("SPIEL-SCOPE", game_scope, 9)
	profile_row.add_child(_game_scope_field)
	_workflow_label = Bezel.lcd_label(Loc.t("ui.demo_maker_window.01_konzept_02_szenen_03_engine", "01 KONZEPT  >  02 SZENEN  >  03 ENGINE  >  04 QA  >  05 MASTER"), C_DIM, 10)
	_workflow_label.name = "ProductionPipeline"
	_workflow_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(_workflow_label)


func _make_metadata_option(definitions: Array) -> OptionButton:
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for definition: Array in definitions:
		option.add_item(str(definition[0]))
		option.set_item_metadata(option.item_count - 1, str(definition[1]))
	return option


func _make_choice_strip(property_key: String, definitions: Array) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 3)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	var choices: Dictionary = {}
	for definition: Array in definitions:
		var value := str(definition[1])
		var button := make_button(str(definition[0]), _select_profile_choice.bind(property_key, value))
		button.name = "Choice_%s_%s" % [property_key, value]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(78, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		choices[value] = button
		strip.add_child(button)
	_profile_choice_buttons[property_key] = choices
	return strip


func _make_stepper_card(property_key: String, label_text: String, minimum: int, maximum: int) -> HBoxContainer:
	var card := HBoxContainer.new()
	card.name = "Stepper_%s" % property_key
	card.set_meta("minimum", minimum)
	card.set_meta("maximum", maximum)
	card.add_theme_constant_override("separation", 2)
	var minus := make_button(Loc.t("ui.demo_maker_window.text", "−"), _change_profile_number.bind(property_key, -1, minimum, maximum))
	minus.custom_minimum_size = Vector2(28, 28)
	card.add_child(minus)
	var value_label := Bezel.lcd_label("%s  --" % label_text, C_INFO, 10)
	value_label.custom_minimum_size = Vector2(70, 28)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.set_meta("caption", label_text)
	_stepper_value_labels[property_key] = value_label
	card.add_child(value_label)
	var plus := make_button("+", _change_profile_number.bind(property_key, 1, minimum, maximum))
	plus.custom_minimum_size = Vector2(28, 28)
	card.add_child(plus)
	return card


func _compact_spin(minimum: int, maximum: int, initial: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = initial
	spin.custom_minimum_size.x = 62
	return spin


func _build_workspace() -> void:
	var split := HSplitContainer.new()
	split.name = "StudioWorkspace"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.set_deferred("split_offset", 700)
	content.add_child(split)

	var left_panel := Bezel.titled_panel(Loc.t("ui.demo_maker_window.live_monitor_pal_320_200_timeline", "LIVE-MONITOR · PAL 320×200 · TIMELINE"))
	var left: VBoxContainer = left_panel["body"]
	left.add_theme_constant_override("separation", 5)
	split.add_child(left_panel["root"])

	_preview = DemoPlayer.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = Vector2(680, 286)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.studio_hud = true
	left.add_child(_preview)

	_preview_status = Bezel.dim_label(Loc.t("ui.demo_maker_window.part_01_00_00_50_hz", "PART 01 · 00:00 · 50 HZ"), 12)
	_preview_status.name = "PreviewStatus"
	left.add_child(_preview_status)

	var timeline_scroll := ScrollContainer.new()
	timeline_scroll.name = "TimelineScroll"
	timeline_scroll.custom_minimum_size.y = 62
	timeline_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	timeline_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_timeline = HBoxContainer.new()
	_timeline.name = "Timeline"
	_timeline.add_theme_constant_override("separation", 5)
	timeline_scroll.add_child(_timeline)
	left.add_child(timeline_scroll)

	var timeline_actions := HBoxContainer.new()
	timeline_actions.add_theme_constant_override("separation", 5)
	timeline_actions.add_child(make_button(Loc.t("ui.demo_maker_window.part", "+ PART"), _add_part))
	timeline_actions.add_child(make_button(Loc.t("ui.demo_maker_window.duplizieren", "DUPLIZIEREN"), _duplicate_part))
	timeline_actions.add_child(make_button("◀", _move_part.bind(-1)))
	timeline_actions.add_child(make_button(Loc.t("ui.demo_maker_window.text_dff5", "▶"), _move_part.bind(1)))
	timeline_actions.add_child(make_button(Loc.t("ui.demo_maker_window.loschen", "LÖSCHEN"), _delete_part))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_actions.add_child(spacer)
	var hint := Bezel.dim_label(Loc.t("ui.demo_maker_window.1_8_parts_klick_wahlt_den", "1–8 Parts · Klick wählt den Abschnitt"), 11)
	timeline_actions.add_child(hint)
	left.add_child(timeline_actions)

	_tabs = TabContainer.new()
	_tabs.name = "StudioTabs"
	_tabs.custom_minimum_size = Vector2(430, 0)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_contents = true
	split.add_child(_tabs)
	_build_part_tab()
	_build_code_tab()
	_build_release_tab()


func _build_part_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "PART & TIMING"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 7)
	scroll.add_child(box)

	_part_context = DemoUi.wrapped_dim("", 12)
	_part_context.name = "PartContext"
	box.add_child(_part_context)
	_part_name = DemoUi.line_edit("PartName", 0, 20)
	_part_name.text_changed.connect(_set_part_name_from_editor)
	_part_name.focus_exited.connect(_finalize_part_name)
	box.add_child(DemoUi.labeled("PART-NAME", _part_name))

	var timing := HBoxContainer.new()
	_duration_spin = SpinBox.new()
	_duration_spin.name = "DurationSpin"
	_duration_spin.min_value = 4
	_duration_spin.max_value = 30
	_duration_spin.step = 1
	_duration_spin.custom_minimum_size.x = 100
	_duration_spin.value_changed.connect(func(value: float) -> void:
		if not _guard:
			_set_part("duration", value))
	timing.add_child(DemoUi.labeled("DAUER (SEK.)", _duration_spin))
	_sync_toggle = CheckButton.new()
	_sync_toggle.name = "SyncToggle"
	_sync_toggle.text = Loc.t("ui.demo_maker_window.beat_sync", "BEAT-SYNC")
	_sync_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sync_toggle.toggled.connect(func(on: bool) -> void:
		if not _guard:
			_set_part("sync", on))
	timing.add_child(DemoUi.labeled("MUSIK-IRQ", _sync_toggle))
	box.add_child(timing)

	_effect_option = OptionButton.new()
	_effect_option.name = "EffectOption"
	DemoUi.fill_option(_effect_option, DemoManager.catalog("effects"))
	_effect_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_set_primary_effect(str(_effect_option.get_item_metadata(index))))
	box.add_child(DemoUi.labeled("HAUPTEFFEKT", _effect_option))

	_layer_option = OptionButton.new()
	_layer_option.name = "LayerOption"
	_layer_option.add_item(Loc.t("ui.demo_maker_window.kein_zweites_layer", "— KEIN ZWEITES LAYER —"))
	_layer_option.set_item_metadata(0, "")
	DemoUi.fill_option(_layer_option, DemoManager.catalog("effects"), false)
	_layer_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_set_secondary_effect(str(_layer_option.get_item_metadata(index))))
	box.add_child(DemoUi.labeled("COMPOSITE-LAYER", _layer_option))

	var look := HBoxContainer.new()
	_transition_option = OptionButton.new()
	_transition_option.name = "TransitionOption"
	DemoUi.fill_option(_transition_option, DemoManager.catalog("transitions"))
	_transition_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_set_part("transition", str(_transition_option.get_item_metadata(index))))
	look.add_child(DemoUi.labeled("ÜBERGANG", _transition_option))
	_palette_option = OptionButton.new()
	_palette_option.name = "PaletteOption"
	DemoUi.fill_option(_palette_option, DemoManager.catalog("palettes"))
	_palette_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_set_part("palette", str(_palette_option.get_item_metadata(index))))
	look.add_child(DemoUi.labeled("PALETTE", _palette_option))
	box.add_child(look)

	_intensity = HSlider.new()
	_intensity.name = "IntensitySlider"
	_intensity.min_value = 0.55
	_intensity.max_value = 1.35
	_intensity.step = 0.05
	_intensity.value_changed.connect(func(value: float) -> void:
		if not _guard:
			_set_part("intensity", value))
	box.add_child(DemoUi.labeled("LAST / INTENSITÄT", _intensity))

	_scroll_edit = TextEdit.new()
	_scroll_edit.name = "ScrollerEdit"
	_scroll_edit.custom_minimum_size.y = 94
	_scroll_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_scroll_edit.placeholder_text = Loc.t("ui.demo_maker_window.scrolltext_greetings_credits", "SCROLLTEXT, GREETINGS UND CREDITS …")
	_scroll_edit.text_changed.connect(func() -> void:
		if not _guard:
			_set_scroller_text_from_editor())
	box.add_child(DemoUi.labeled("PART-SCROLLER", _scroll_edit))

	_part_budget = Bezel.lcd_label(Loc.t("ui.demo_maker_window.cpu_chip_kb_blitter", "CPU --% · CHIP --- KB · BLITTER --%"), C_INFO, 13)
	_part_budget.name = "PartBudget"
	box.add_child(_part_budget)


func _build_code_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "CODE & BUILD"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tabs.add_child(scroll)
	var root := VBoxContainer.new()
	root.name = "CodeBuildContent"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)
	_code_context = DemoUi.wrapped_dim("", 12)
	_code_context.name = "CodeContext"
	root.add_child(_code_context)

	var module_scroll := ScrollContainer.new()
	module_scroll.name = "ModuleScroll"
	module_scroll.custom_minimum_size.y = 220
	module_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_module_box = GridContainer.new()
	_module_box.name = "ModuleList"
	_module_box.columns = 2
	_module_box.add_theme_constant_override("h_separation", 5)
	_module_box.add_theme_constant_override("v_separation", 3)
	_module_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	module_scroll.add_child(_module_box)
	root.add_child(module_scroll)

	_code_budget = Bezel.lcd_label(Loc.t("ui.demo_maker_window.build_noch_nicht_ausgefuhrt", "BUILD NOCH NICHT AUSGEFÜHRT"), C_WARN, 13)
	_code_budget.name = "CodeBudget"
	root.add_child(_code_budget)

	_compile_log = RichTextLabel.new()
	_compile_log.name = "CompileLog"
	_compile_log.bbcode_enabled = true
	_compile_log.custom_minimum_size.y = 175
	_compile_log.scroll_active = true
	_compile_log.text = Loc.t("ui.demo_maker_window.color_7e909c_wartet_auf_build_color", "[color=#7e909c]> WARTET AUF BUILD[/color]")
	root.add_child(_compile_log)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	actions.add_child(make_button(Loc.t("ui.demo_maker_window.f7_kompilieren", "F7 · KOMPILIEREN"), _compile_project))
	actions.add_child(make_button(Loc.t("ui.demo_maker_window.auto_opt", "AUTO-OPT"), _auto_optimize))
	actions.add_child(make_button(Loc.t("ui.demo_maker_window.profiler_lab", "PROFILER-LAB"), func() -> void: UIManager.open_cracktro_optimization(_project)))
	actions.add_child(make_button(Loc.t("ui.demo_maker_window.f8_test_run", "F8 · TEST RUN"), _test_run))
	root.add_child(actions)


func _build_release_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "QA & RELEASE"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tabs.add_child(scroll)
	var root := VBoxContainer.new()
	root.name = "ReleaseContent"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 7)
	scroll.add_child(root)
	root.add_child(DemoUi.wrapped_dim(
		"Ein Release ist ein eingefrorener Build. Gute Technik allein reicht nicht: Dramaturgie, Sync und Credits zählen.", 12))

	var contract_row := HBoxContainer.new()
	contract_row.add_theme_constant_override("separation", 8)
	_role_option = OptionButton.new()
	for role in [["CODE / LISTING", "code"], ["PIXELGRAFIK", "pixel"], ["MUSIK", "music"],
			["TESTING", "testing"], ["ORGANISATION", "organization"]]:
		_role_option.add_item(role[0])
		_role_option.set_item_metadata(_role_option.item_count - 1, role[1])
	_role_option.visible = false
	_role_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_project["player_role"] = str(_role_option.get_item_metadata(index))
			_note_club_role_if_ready()
			_mark_dirty())
	var role_choices := _make_choice_strip("player_role", [
		["CODE", "code"], ["PIXEL", "pixel"], ["MUSIK", "music"],
		["TEST", "testing"], ["ORGA", "organization"]])
	role_choices.add_child(_role_option)
	_club_role_field = DemoUi.labeled("DEINE ROLLE IM CLUB-PROJEKT", role_choices, 10)
	_club_role_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contract_row.add_child(_club_role_field)
	_game_mode_option = OptionButton.new()
	for mode in [
		[Loc.t("ui.demo_maker_window.game_mode_collector", "SAMMELN & AUSGANG"), "collector"],
		[Loc.t("ui.demo_maker_window.game_mode_courier", "KURIER-ROUTE"), "courier"],
		[Loc.t("ui.demo_maker_window.game_mode_survival", "ÜBERLEBEN"), "survival"],
		["LOGIK-PUZZLE", "puzzle"],
	]:
		_game_mode_option.add_item(mode[0])
		_game_mode_option.set_item_metadata(_game_mode_option.item_count - 1, mode[1])
	_game_mode_option.visible = false
	_game_mode_option.item_selected.connect(func(index: int) -> void:
		if not _guard:
			_project["game_mode"] = str(_game_mode_option.get_item_metadata(index))
			QuestManager.note_action("choose_game_direction")
			_mark_dirty())
	var mode_choices := _make_choice_strip("game_mode", [
		["SAMMELN", "collector"], ["KURIER", "courier"], ["SURVIVAL", "survival"], ["PUZZLE", "puzzle"]])
	mode_choices.add_child(_game_mode_option)
	_game_rules_field = DemoUi.labeled(
		Loc.t("ui.demo_maker_window.game_rules", "SPIELIDEE / REGELN"),
		mode_choices, 10)
	_game_rules_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contract_row.add_child(_game_rules_field)
	root.add_child(contract_row)
	_release_context = DemoUi.wrapped_dim("", 11)
	_release_context.name = "ReleaseContext"
	root.add_child(_release_context)

	_score_label = Bezel.lcd_label(Loc.t("ui.demo_maker_window.unbewertet_100", "UNBEWERTET · --/100"), C_WARN, 24)
	_score_label.name = "ScoreLabel"
	root.add_child(_score_label)
	_asset_label = Bezel.dim_label(Loc.t("ui.demo_maker_window.eigene_assets", "EIGENE ASSETS: —"), 10)
	_asset_label.name = "CreatorAssets"
	root.add_child(_asset_label)
	for key in ["craft", "performance", "sync", "originality"]:
		var row := HBoxContainer.new()
		var label := Bezel.dim_label(str(key).to_upper(), 11)
		label.custom_minimum_size.x = 92
		row.add_child(label)
		var bar := Bezel.bar(C_INFO, Vector2(150, 12))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_score_bars[key] = bar
		row.add_child(bar)
		root.add_child(row)

	_qa_text = RichTextLabel.new()
	_qa_text.name = "QaReport"
	_qa_text.bbcode_enabled = true
	_qa_text.custom_minimum_size.y = 135
	_qa_text.scroll_active = true
	_qa_text.text = Loc.t("ui.demo_maker_window.color_7e909c_noch_kein_testlauf_color", "[color=#7e909c]Noch kein Testlauf.[/color]")
	root.add_child(_qa_text)

	var credit_header := HBoxContainer.new()
	credit_header.add_child(Bezel.dim_label(Loc.t("ui.demo_maker_window.credits_nur_szene_handle_snapshots", "CREDITS · NUR SZENE-HANDLE-SNAPSHOTS"), 11))
	root.add_child(credit_header)
	_bbs_greetings = Bezel.dim_label(Loc.t("ui.demo_maker_window.bbs_greetings", "BBS GREETINGS: —"), 10)
	_bbs_greetings.clip_text = true
	_bbs_greetings.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_bbs_greetings.tooltip_text = Loc.t("ui.demo_maker_window.aktive_mailboxen_werden_automatisch_in_greetings", "Aktive Mailboxen werden automatisch in die Greetings übernommen.")
	root.add_child(_bbs_greetings)
	var credit_scroll := ScrollContainer.new()
	credit_scroll.custom_minimum_size.y = 78
	credit_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_credits_box = VBoxContainer.new()
	_credits_box.name = "CreditHandles"
	_credits_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credit_scroll.add_child(_credits_box)
	root.add_child(credit_scroll)

	_presenting_option = OptionButton.new()
	_presenting_option.name = "PresentingGroup"
	_presenting_option.item_selected.connect(_on_presenting_selected)
	root.add_child(DemoUi.labeled("PRESENTING / AKZEPTIERTE KOOPERATION", _presenting_option, 10))

	var actions := HBoxContainer.new()
	_game_playtest_button = make_button(
		Loc.t("ui.demo_maker_window.spiel_prototyp_testen", "SPIEL-PROTOTYP TESTEN"),
		_open_game_playtest)
	_game_playtest_button.name = "GamePlaytestButton"
	actions.add_child(_game_playtest_button)
	_release_button = make_button(Loc.t("ui.demo_maker_window.release_freezen_senden", "RELEASE FREEZEN & SENDEN"), _release)
	_release_button.name = "ReleaseButton"
	actions.add_child(_release_button)
	_demos_button = make_button(Loc.t("ui.demo_maker_window.archiv_d", "ARCHIV (%d)") % DemoManager.count(), _show_demos)
	_demos_button.name = "ArchiveButton"
	actions.add_child(_demos_button)
	root.add_child(actions)


func _build_footer() -> void:
	var footer_panel := PanelContainer.new()
	footer_panel.name = "StudioFooter"
	footer_panel.custom_minimum_size.y = 42
	footer_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer_style := StyleBoxFlat.new()
	footer_style.bg_color = Color8(8, 12, 16, 248)
	footer_style.border_color = Color(C_INFO, 0.72)
	footer_style.border_width_top = 2
	footer_style.set_content_margin_all(5)
	footer_panel.add_theme_stylebox_override("panel", footer_style)
	var footer := HBoxContainer.new()
	footer.name = "StudioFooterActions"
	footer.custom_minimum_size.y = 32
	footer.add_theme_constant_override("separation", 7)
	footer_panel.add_child(footer)
	footer.add_child(make_button(Loc.t("ui.demo_maker_window.neues_projekt", "NEUES PROJEKT"), _new_project))
	footer.add_child(make_button(Loc.t("ui.demo_maker_window.draft_speichern", "DRAFT SPEICHERN"), _save_draft.bind(true)))
	var build_button := make_button(Loc.t("ui.demo_maker_window.f7_build", "F7 BUILD"), _compile_project)
	build_button.name = "FooterBuild"
	DemoUi.accent_command(build_button, C_WARN)
	footer.add_child(build_button)
	var test_button := make_button(Loc.t("ui.demo_maker_window.f8_test", "F8 TEST"), _test_run)
	test_button.name = "FooterTest"
	DemoUi.accent_command(test_button, C_INFO)
	footer.add_child(test_button)
	var close_button := make_button(Loc.t("ui.demo_maker_window.studio_schliessen", "STUDIO SCHLIESSEN"), _close_studio)
	close_button.name = "CloseStudioButton"
	footer.add_child(close_button)
	# Die Legende nimmt nur den Restplatz, ihre Textbreite vergroessert nie das Fenster.
	var legend := Bezel.dim_label(Loc.t("ui.demo_maker_window.shortcuts_f7_build_f8_test_strg", "Shortcuts: F7 Build · F8 Test · Strg+S Draft"), 11)
	legend.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	legend.clip_text = true
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(legend)
	content.add_child(footer_panel)
