extends RetroWindow
## Projektzustand, Build-/QA-Workflow und Eingabesteuerung des Szene-Studios.
## Das konkrete Fensterlayout bleibt in demo_maker_window.gd.

const DemoUi := preload("res://scripts/ui/demo_maker_ui.gd")
const DemoReportUi := preload("res://scripts/ui/demo_maker_report_ui.gd")
const DemoCredits := preload("res://scripts/ui/demo_maker_credits.gd")
const DemoModes := preload("res://scripts/ui/demo_maker_mode_catalog.gd")
const GamePlaytestWindow := preload("res://scripts/ui/game_prototype_playtest_window.gd")

const C_GOOD := Color8(92, 220, 138)
const C_WARN := Color8(248, 196, 72)
const C_BAD := Color8(235, 92, 90)
const C_INFO := Color8(72, 184, 220)
const C_DIM := Color8(126, 144, 156)

var _project: Dictionary = {}
var _report: Dictionary = {}
var _test_report: Dictionary = {}
var _selected_part := 0
var _compiled := false
var _tested := false
var _guard := false

var _preview: DemoPlayer
var _preview_status: Label
var _timeline: HBoxContainer
var _tabs: TabContainer
var _status: Label
var _mode_buttons: Dictionary = {}
var _mode_description: Label
var _mode_badge: Label
var _workflow_label: Label
var _demo_format_option: OptionButton
var _intro_purpose_option: OptionButton
var _game_difficulty_option: OptionButton
var _game_lives_spin: SpinBox
var _game_objectives_spin: SpinBox
var _demo_profile_field: Control
var _intro_profile_field: Control
var _game_scope_field: Control
var _part_context: Label
var _code_context: Label
var _profile_choice_buttons: Dictionary = {}
var _stepper_value_labels: Dictionary = {}

var _title_edit: LineEdit
var _kind_option: OptionButton
var _role_option: OptionButton
var _game_mode_option: OptionButton
var _group_edit: LineEdit
var _bpm_spin: SpinBox
var _track_option: OptionButton

var _part_name: LineEdit
var _duration_spin: SpinBox
var _effect_option: OptionButton
var _layer_option: OptionButton
var _transition_option: OptionButton
var _palette_option: OptionButton
var _sync_toggle: CheckButton
var _intensity: HSlider
var _scroll_edit: TextEdit
var _part_budget: Label

var _module_box: GridContainer
var _module_buttons: Dictionary = {}
var _compile_log: RichTextLabel
var _code_budget: Label

var _score_label: Label
var _score_bars: Dictionary = {}
var _qa_text: RichTextLabel
var _release_button: Button
var _demos_button: Button
var _credits_box: VBoxContainer
var _presenting_option: OptionButton
var _bbs_greetings: Label
var _asset_label: Label
var _club_role_field: Control
var _game_rules_field: Control
var _game_playtest_button: Button
var _release_context: Label

var _music_changed_by_studio := false
# ------------------------------------------------------------ Projektzustand

## Explizite Modul-Schnittstellen: Report und Credits liegen in eigenen
## Darstellungsmodulen. Die Nodes werden hier gebuendelt, damit ihre Nutzung
## statisch sichtbar bleibt und die Module nicht per losem `get("_feld")` an
## private Implementierungsdetails gekoppelt sind.
func report_ui_context() -> Dictionary:
	return {
		"status": _status,
		"code_budget": _code_budget,
		"compile_log": _compile_log,
		"score_label": _score_label,
		"score_bars": _score_bars,
		"release_button": _release_button,
		"qa_text": _qa_text,
	}


func credits_ui_context() -> Dictionary:
	return {
		"credits_box": _credits_box,
		"presenting_option": _presenting_option,
		"bbs_greetings": _bbs_greetings,
	}

func _refresh_all() -> void:
	_guard = true
	_normalize_selection()
	_title_edit.text = str(_project.get("title", "UNTITLED DEMO"))
	DemoUi.select_option(_kind_option, str(_project.get("project_kind", "demo")))
	_refresh_mode_context()
	DemoUi.select_option(_role_option, str(_project.get("player_role", "code")))
	DemoUi.select_option(_game_mode_option, str(_project.get("game_mode", "collector")))
	DemoUi.select_option(_demo_format_option, str(_project.get("demo_format", "trackmo")))
	DemoUi.select_option(_intro_purpose_option, str(_project.get("intro_purpose", "group_id")))
	DemoUi.select_option(_game_difficulty_option, str(_project.get("game_difficulty", "normal")))
	_game_lives_spin.value = float(_project.get("game_lives", 3))
	_game_objectives_spin.value = float(_project.get("game_objectives", 3))
	_refresh_profile_selectors()
	_group_edit.text = str(_project.get("group", "LONE CODER"))
	_bpm_spin.value = float(_project.get("bpm", 125))
	DemoUi.select_option(_track_option, str(_project.get("track_id", "")))
	_refresh_creator_assets()
	_refresh_timeline()
	_refresh_part_editor()
	_refresh_modules()
	_refresh_credits()
	_preview.set_project(_project_for_preview())
	_preview.studio_hud = true
	_refresh_report()
	_guard = false


func _refresh_timeline() -> void:
	DemoUi.clear_children(_timeline)
	var parts: Array = _project.get("parts", [])
	for i in parts.size():
		var part: Dictionary = parts[i]
		var btn := Button.new()
		btn.name = "Part%02d" % (i + 1)
		btn.text = Loc.t("ui.demo_maker_window.02d_s_n_02_0fs_s", "%02d  %s\n%02.0fs · %s") % [i + 1, str(part.get("name", "PART")).left(13),
			float(part.get("duration", 8.0)), DemoUi.catalog_name("effects", str(part.get("effect", "starfield"))).left(12)]
		btn.custom_minimum_size = Vector2(126, 57)
		btn.add_theme_color_override("font_color", C_GOOD if i == _selected_part else Palette.UI_TEXT)
		btn.pressed.connect(_select_part.bind(i))
		_timeline.add_child(btn)

	var active := _active_part()
	_preview_status.text = Loc.t("ui.demo_maker_window.part_02d_02d_s_02_0f", "PART %02d/%02d · %s · %02.0f SEK. · %d BPM") % [
		_selected_part + 1, parts.size(), str(active.get("name", "PART")),
		float(active.get("duration", 8.0)), int(_project.get("bpm", 125))]


func _refresh_part_editor() -> void:
	var part := _active_part()
	_part_name.text = str(part.get("name", "PART"))
	_duration_spin.value = float(part.get("duration", 8.0))
	_sync_toggle.button_pressed = bool(part.get("sync", true))
	_intensity.value = float(part.get("intensity", 1.0))
	_scroll_edit.text = str(part.get("scrolltext", _project.get("scroller", "")))
	DemoUi.select_option(_effect_option, str(part.get("effect", "starfield")))
	var layers: Array = part.get("effects", part.get("layers", []))
	var secondary := ""
	for layer in layers:
		var layer_id := str(layer.get("effect", "")) if layer is Dictionary else str(layer)
		if layer_id != str(part.get("effect", "")):
			secondary = layer_id
			break
	DemoUi.select_option(_layer_option, secondary)
	DemoUi.select_option(_transition_option, str(part.get("transition", "cut")))
	DemoUi.select_option(_palette_option, str(part.get("palette", _project.get("palette", "night_copper"))))
	_refresh_part_budget()


func _refresh_modules() -> void:
	DemoUi.clear_children(_module_box)
	_module_buttons.clear()
	var selected: Array = _project.get("modules", [])
	var kind := str(_project.get("project_kind", "demo"))
	for module: Dictionary in DemoManager.catalog("modules"):
		var module_id := str(module.get("id", ""))
		var row := CheckButton.new()
		var recommended := _module_recommended(kind, module_id)
		row.text = "%s  %s\n%s · %s" % ["◆" if recommended else "◇",
			str(module.get("name", module_id)).to_upper(),
			Loc.t("ui.demo_maker_window.recommended", "EMPFOHLEN") if recommended else Loc.t("ui.demo_maker_window.optional", "OPTIONAL"),
			str(module.get("cost", "CORE"))]
		row.tooltip_text = "%s\n%s" % [
			Loc.t("ui.demo_maker_window.profile_match", "Passt zum aktuellen Produktionsprofil.") if recommended \
			else Loc.t("ui.demo_maker_window.special_build_module", "Optionales Modul für spezielle Builds."),
			str(module.get("description", ""))]
		row.custom_minimum_size = Vector2(192, 38)
		row.add_theme_font_size_override("font_size", 12)
		row.add_theme_color_override("font_color", C_INFO if recommended else Palette.UI_TEXT)
		row.button_pressed = selected.has(module_id)
		row.toggled.connect(_toggle_module.bind(module_id))
		_module_buttons[module_id] = row
		_module_box.add_child(row)


func _module_recommended(kind: String, module_id: String) -> bool:
	return DemoModes.is_module_recommended(kind, module_id)


func _refresh_credits() -> void:
	DemoCredits.refresh(self)


func _refresh_report() -> void:
	DemoReportUi.refresh(self)


func _refresh_profile_selectors() -> void:
	for property_key: String in _profile_choice_buttons:
		var selected := str(_project.get(property_key, ""))
		var choices: Dictionary = _profile_choice_buttons[property_key]
		for value: String in choices:
			var button := choices[value] as Button
			button.button_pressed = value == selected
			button.add_theme_color_override("font_color", C_GOOD if value == selected else Palette.UI_TEXT)
	for property_key: String in _stepper_value_labels:
		var label := _stepper_value_labels[property_key] as Label
		label.text = "%s  %d" % [str(label.get_meta("caption", property_key)).to_upper(), int(_project.get(property_key, 0))]


# ------------------------------------------------------------- Interaktionen

func _select_profile_choice(property_key: String, value: String) -> void:
	if _guard:
		return
	_project[property_key] = value
	if property_key == "game_difficulty":
		DemoUi.select_option(_game_difficulty_option, value)
	elif property_key == "demo_format":
		DemoUi.select_option(_demo_format_option, value)
	elif property_key == "intro_purpose":
		DemoUi.select_option(_intro_purpose_option, value)
	elif property_key == "player_role":
		DemoUi.select_option(_role_option, value)
		_note_club_role_if_ready()
	elif property_key == "game_mode":
		DemoUi.select_option(_game_mode_option, value)
		QuestManager.note_action("choose_game_direction")
	_refresh_profile_selectors()
	_mark_dirty()


func _change_profile_number(property_key: String, delta: int, minimum: int, maximum: int) -> void:
	if _guard:
		return
	_project[property_key] = clampi(int(_project.get(property_key, minimum)) + delta, minimum, maximum)
	_guard = true
	if property_key == "game_lives":
		_game_lives_spin.value = int(_project[property_key])
	elif property_key == "game_objectives":
		_game_objectives_spin.value = int(_project[property_key])
	_guard = false
	_refresh_profile_selectors()
	_mark_dirty(false)

func _set_project_title_from_editor(value: String) -> void:
	if _guard:
		return
	_project["title"] = value.to_upper().left(48)
	_mark_dirty(false)


func _finalize_project_title() -> void:
	if _guard:
		return
	var value := DemoUi.clean_title(_title_edit.text,
		DemoModes.fallback_title(str(_project.get("project_kind", "demo"))))
	_guard = true
	_title_edit.text = value
	_guard = false
	_project["title"] = value
	_mark_dirty(false)


func _set_group_from_editor(value: String) -> void:
	if _guard:
		return
	_project["group"] = value.to_upper().left(32)
	_project["author"] = _project["group"]
	_rebuild_credit_line()
	_mark_dirty(false)


func _finalize_group() -> void:
	if _guard:
		return
	var value := DemoUi.clean_title(_group_edit.text, "LONE-CODER")
	_guard = true
	_group_edit.text = value
	_guard = false
	_project["group"] = value
	_project["author"] = value
	_rebuild_credit_line()
	_mark_dirty(false)


func _set_part_name_from_editor(value: String) -> void:
	if _guard:
		return
	var parts := _parts()
	if parts.is_empty():
		return
	var part: Dictionary = parts[_selected_part]
	part["name"] = value.to_upper().left(32)
	part["title"] = part["name"]
	parts[_selected_part] = part
	_project["parts"] = parts
	_mark_dirty(false)
	_refresh_timeline()


func _finalize_part_name() -> void:
	if _guard:
		return
	var value := DemoUi.clean_title(_part_name.text, "PART %02d" % (_selected_part + 1))
	_guard = true
	_part_name.text = value
	_guard = false
	_set_part_name_from_editor(value)


func _close_studio() -> void:
	_save_draft(false)
	queue_free()

func _select_project_kind(kind: String) -> void:
	if _guard or not DemoModes.is_valid(kind):
		return
	var current_kind := str(_project.get("project_kind", "demo"))
	if current_kind == kind:
		return
	_save_draft(false)
	var target: Dictionary = DemoManager.load_draft(kind)
	_project = target if not target.is_empty() else DemoManager.create_project(-1, kind)
	_selected_part = 0
	_report = {}
	_test_report = {}
	_compiled = false
	_tested = false
	if kind == "game":
		QuestManager.note_action("choose_game_direction")
	elif kind == "club_intro":
		_note_club_role_if_ready()
	DemoManager.save_draft(_project)
	_refresh_all()


func _refresh_mode_context() -> void:
	var kind := DemoModes.normalize(str(_project.get("project_kind", "demo")))
	for id: String in _mode_buttons:
		var button := _mode_buttons[id] as Button
		button.button_pressed = id == kind
		button.add_theme_color_override(
			"font_color", C_GOOD if id == kind else Palette.UI_TEXT)
	_mode_badge.text = Loc.t("ui.demo_maker_window.workflow", "WORKFLOW")
	_mode_description.text = DemoModes.description(kind)
	_demo_profile_field.visible = kind == "demo"
	_intro_profile_field.visible = kind == "club_intro"
	_game_scope_field.visible = kind == "game"
	_club_role_field.visible = kind == "club_intro"
	_game_rules_field.visible = kind == "game"
	_game_playtest_button.visible = kind == "game"
	var names := DemoModes.tab_titles(kind)
	for i in mini(_tabs.get_tab_count(), names.size()):
		_tabs.set_tab_title(i, str(names[i]))
	_part_context.text = DemoModes.part_context(kind)
	_code_context.text = DemoModes.code_context(kind)
	var stage := 4 if _tested else (3 if _compiled else 2)
	var stages := ["01 KONZEPT", "02 SZENEN", "03 ENGINE", "04 QA", "05 MASTER"]
	var stage_text: Array[String] = []
	for i in stages.size():
		stage_text.append(("● " if i < stage else "○ ") + stages[i])
	_workflow_label.text = "  >  ".join(stage_text)
	_workflow_label.add_theme_color_override("font_color", C_GOOD if _tested else (C_INFO if _compiled else C_DIM))
	_release_context.text = DemoModes.release_context(kind)


func _select_part(index: int) -> void:
	_selected_part = clampi(index, 0, maxi(0, _parts().size() - 1))
	_refresh_all()


func _add_part() -> void:
	if _parts().size() >= 8:
		UIManager.toast(Loc.t("ui.demo_maker_window.mehr_als_acht_parts_passen_nicht", "Mehr als acht Parts passen nicht auf diese Demo-Diskette."))
		return
	var parts := _parts()
	parts.append(DemoManager.create_part(parts.size()))
	_project["parts"] = parts
	_selected_part = parts.size() - 1
	_mark_dirty()


func _duplicate_part() -> void:
	if _parts().size() >= 8:
		UIManager.toast(Loc.t("ui.demo_maker_window.timeline_ist_voll_maximal_acht_parts", "Die Timeline ist voll (maximal acht Parts)."))
		return
	var parts := _parts()
	var copy: Dictionary = _active_part().duplicate(true)
	copy["id"] = "part_%02d_%d" % [parts.size() + 1, Time.get_ticks_msec() % 100000]
	copy["name"] = "%s COPY" % str(copy.get("name", "PART")).left(14)
	parts.insert(_selected_part + 1, copy)
	_project["parts"] = parts
	_selected_part += 1
	_mark_dirty()


func _delete_part() -> void:
	var parts := _parts()
	if parts.size() <= 1:
		UIManager.toast(Loc.t("ui.demo_maker_window.demo_braucht_mindestens_einen_part", "Eine Demo braucht mindestens einen Part."))
		return
	parts.remove_at(_selected_part)
	_project["parts"] = parts
	_selected_part = mini(_selected_part, parts.size() - 1)
	_mark_dirty()


func _move_part(direction: int) -> void:
	var parts := _parts()
	var target := _selected_part + direction
	if target < 0 or target >= parts.size():
		return
	var moving: Dictionary = parts[_selected_part]
	parts[_selected_part] = parts[target]
	parts[target] = moving
	_project["parts"] = parts
	_selected_part = target
	_mark_dirty()


func _toggle_module(on: bool, module_id: String) -> void:
	if _guard:
		return
	var modules: Array = _project.get("modules", [])
	if on and not modules.has(module_id):
		modules.append(module_id)
	elif not on:
		modules.erase(module_id)
	_project["modules"] = modules
	_mark_dirty(false)


func _set_primary_effect(effect_id: String) -> void:
	var part := _active_part()
	var previous := str(part.get("effect", "starfield"))
	var extras: Array = []
	for value in part.get("effects", []):
		var candidate := str(value)
		if candidate != previous and candidate != effect_id and not extras.has(candidate):
			extras.append(candidate)
	part["effect"] = effect_id
	part["effects"] = [effect_id] + extras
	part["layers"] = extras
	_store_active(part)


func _set_secondary_effect(effect_id: String) -> void:
	var part := _active_part()
	var primary := str(part.get("effect", "starfield"))
	var layers: Array = []
	if effect_id != "" and effect_id != primary:
		layers.append(effect_id)
	part["effects"] = [primary] + layers
	part["layers"] = layers
	_store_active(part)


func _set_part(key: String, value: Variant) -> void:
	var part := _active_part()
	part[key] = value
	_store_active(part)


## TextEdit darf während des Tippens nicht durch _refresh_all() neu gesetzt
## werden: Das würde den Caret nach jedem Zeichen an Position 0 bewegen und den
## sichtbaren Text scheinbar rückwärts entstehen lassen.
func _set_scroller_text_from_editor() -> void:
	var part := _active_part()
	part["scrolltext"] = _scroll_edit.text.to_upper()
	var parts := _parts()
	if parts.is_empty():
		return
	parts[_selected_part] = part
	_project["parts"] = parts
	_mark_dirty(false)
	_refresh_timeline()
	_refresh_part_budget()


func _store_active(part: Dictionary) -> void:
	var parts := _parts()
	if parts.is_empty():
		return
	parts[_selected_part] = part
	_project["parts"] = parts
	_mark_dirty()


func _refresh_part_budget() -> void:
	var estimate: Dictionary = DemoManager.part_metrics(_project, _selected_part)
	_part_budget.text = Loc.t("ui.demo_maker_window.cpu_d_chip_d_kb_blitter", "CPU %d%% · CHIP %d KB · BLITTER %d%% · %d FARBEN") % [
		int(estimate.get("cpu", 0)), int(estimate.get("chip_kb", 0)),
		int(estimate.get("blitter", 0)), int(estimate.get("colors", 0))]
	_part_budget.add_theme_color_override(
		"font_color", C_BAD if bool(estimate.get("over_budget", false)) else C_INFO)


func _on_track_selected(index: int) -> void:
	if _guard:
		return
	var track_id := str(_track_option.get_item_metadata(index))
	_project["track_id"] = track_id
	_project["track"] = _track_option.get_item_text(index) if track_id != "" else ""
	_project["track_title_snapshot"] = _project["track"]
	_project["soundtrack"] = _project["track"]
	_music_changed_by_studio = true
	if track_id.begins_with("creation:tracker:"):
		var assets: Dictionary = _project.get("creator_assets", {}).duplicate(true)
		for creation: Dictionary in DemoManager.creator_library().get("music", []):
			if track_id.ends_with(str(creation.get("id", ""))):
				assets["music"] = creation.duplicate(true)
				_project["bpm"] = int(creation.get("bpm", 125))
				break
		_project["creator_assets"] = assets
		MusicManager.stop()
	elif track_id != "":
		MusicManager.play(track_id)
		var native := MusicManager.native_player()
		if native != null and native.has_method("playback_view"):
			var tracker: Variant = native.call("playback_view")
			if tracker is Dictionary:
				_project["bpm"] = clampi(int(tracker.get("bpm", _project.get("bpm", 125))), 60, 200)
	else:
		MusicManager.stop()
	_mark_dirty()


func _refresh_creator_assets() -> void:
	if _asset_label == null: return
	var assets: Dictionary = _project.get("creator_assets", {})
	var labels: Array[String] = []
	for key in ["music", "art", "tool"]:
		if assets.has(key): labels.append("%s: %s" % [key.to_upper(), str(assets[key].get("title", "EIGEN"))])
	var progress := DemoManager.progression()
	var rank: Dictionary = progress.get("rank", {})
	_asset_label.text = Loc.t("ui.demo_maker_window.eigene_assets_s_szene_respekt_d", "EIGENE ASSETS: %s   ·   SZENE-RESPEKT %d/100 · %s") % [
		" · ".join(labels) if not labels.is_empty() else "—", int(progress.get("respect", 0)), str(rank.get("name", "BEDROOM CODER"))]


func _toggle_credit(on: bool, candidate: Dictionary) -> void:
	DemoCredits.toggle(self, on, candidate)


func _on_presenting_selected(index: int) -> void:
	DemoCredits.select_presenting(self, index)


func _rebuild_credit_line() -> void:
	DemoCredits.rebuild_line(_project)


func _compile_project() -> void:
	_save_draft(false)
	_report = DemoManager.compile_project(_project)
	_test_report = {}
	_tested = false
	_compiled = _report.get("errors", []).is_empty()
	_tabs.current_tab = 1
	_refresh_all()
	if _compiled:
		UIManager.toast(Loc.t("ui.demo_maker_window.build_sauber_gelinkt_jetzt_den_50", "Build sauber gelinkt. Jetzt den 50-Hz-Testlauf starten."))
	else:
		UIManager.toast(Loc.t("ui.demo_maker_window.build_gestoppt_d_fehler_im_code", "Build gestoppt: %d Fehler im Code-Log.") % _report.get("errors", []).size())


func _auto_optimize() -> void:
	_project = DemoManager.auto_optimize(_project)
	_mark_dirty(false)
	_compile_project()
	UIManager.toast(Loc.t("ui.demo_maker_window.profiler_vorschlage_angewendet_build_wurde_neu", "Profiler-Vorschläge angewendet. Der Build wurde neu vermessen."))


func _test_run() -> void:
	if not _compiled or _report.is_empty():
		_compile_project()
	if not _report.get("errors", []).is_empty():
		_tabs.current_tab = 1
		return
	_test_report = DemoManager.test_build(_project, _report)
	_tested = bool(_test_report.get("ok", false))
	if _tested and str(_project.get("project_kind", "demo")) == "club_intro":
		# Alte Entwuerfe koennen CLUB-INTRO bereits vor Queststart gespeichert haben.
		# Die Rolle wird deshalb vor dem echten Beitrags-/QA-Gate nachgezogen.
		_note_club_role_if_ready()
		QuestManager.note_action("club_contribution")
	_tabs.current_tab = 2
	_refresh_all()
	UIManager.toast(Loc.t("ui.demo_maker_window.testlauf_s", "Testlauf: %s") % ("alle Systeme grün." if _tested else "Fehler gefunden — zurück ins Code-Log."))


func _note_club_role_if_ready() -> void:
	if str(_project.get("project_kind", "demo")) != "club_intro":
		return
	if str(_project.get("player_role", "")) not in ["code", "pixel", "music", "testing", "organization"]:
		return
	QuestManager.note_action("club_role_chosen")


func _open_game_playtest() -> void:
	if str(_project.get("project_kind", "demo")) != "game":
		UIManager.toast(Loc.t("ui.demo_maker_window.spielbare_qa_lauf_gehort_zum_release", "Der spielbare QA-Lauf gehört zum Release-Typ SPIEL-PROTOTYP."))
		return
	if not _compiled or _report.is_empty():
		_compile_project()
	if not _report.get("errors", []).is_empty():
		return
	var existing := UIManager.window_layer.get_node_or_null("win_game_playtest")
	if existing != null:
		existing.queue_free()
	var window: Control = GamePlaytestWindow.new()
	window.name = "win_game_playtest"
	window.project = _project.duplicate(true)
	window.playtest_completed.connect(_on_game_playtest_completed)
	UIManager.window_layer.add_child(window)
	UIManager.call("_center_window", window)


func _on_game_playtest_completed(result: Dictionary) -> void:
	var stamped := result.duplicate(true)
	stamped["build_hash"] = str(_report.get("hash", _report.get("build_id", "")))
	_project["gameplay_test"] = stamped
	DemoManager.save_draft(_project)
	QuestManager.note_action("play_game_prototype")
	if not (_project.get("creator_assets", {}) as Dictionary).is_empty():
		QuestManager.note_action("game_assets_linked")
	_test_report = DemoManager.test_build(_project, _report)
	_tested = bool(_test_report.get("ok", false))
	_refresh_all()
	UIManager.toast(Loc.t("ui.demo_maker_window.spieltest_gespeichert_regeln_ergebnis_build_hash", "Spieltest gespeichert: Regeln, Ergebnis und Build-Hash gehören jetzt zum Projekt."))


func _release() -> void:
	if not _tested:
		UIManager.toast(Loc.t("ui.demo_maker_window.vor_dem_freeze_braucht_build_einen", "Vor dem Freeze braucht der Build einen grünen Testlauf."))
		return
	var result := DemoManager.release(_project, _report)
	if not bool(result.get("ok", true)):
		UIManager.toast(str(result.get("reason", "Release wurde vom QA-Gate gestoppt.")))
		return
	_demos_button.text = Loc.t("ui.demo_maker_window.archiv_d", "ARCHIV (%d)") % DemoManager.count()
	var gain := int(result.get("ruf", 0))
	var respect := int(result.get("respect", 0))
	var suffix := " +%d Szene-Ruf" % gain if gain > 0 else " · Ruf-Tageslimit erreicht"
	UIManager.toast(Loc.t("ui.demo_maker_window.s_grade_s_auf_diskette_gefreezt", "»%s« · Grade %s auf Diskette gefreezt.%s · Respekt +%d") % [
		str(_project.get("title", "DEMO")), str(result.get("grade", "?")), suffix, respect])
	_refresh_creator_assets()
	_qa_text.text += "\n\n[color=#48b8dc]%s[/color]" % str(result.get("reception", "Release verteilt."))


func _save_draft(show_toast := false) -> void:
	_project = DemoManager.save_draft(_project)
	if show_toast:
		UIManager.toast(Loc.t("ui.demo_maker_window.projekt_draft_gespeichert_timeline_code_scroller", "Projekt-Draft gespeichert — Timeline, Code und Scroller sind im Spielstand."))


func _new_project() -> void:
	var kind := str(_project.get("project_kind", "demo"))
	_project = DemoManager.create_project(-1, kind)
	_selected_part = 0
	_report = {}
	_test_report = {}
	_compiled = false
	_tested = false
	_refresh_all()
	UIManager.toast(Loc.t("ui.demo_maker_window.neues_szene_projekt_angelegt", "Neues Szene-Projekt angelegt."))


func _show_demos() -> void:
	var lines: Array[String] = []
	for demo: Dictionary in DemoManager.demos():
		lines.append("• %s — %s · Grade %s · %d/100 · %s" % [
			str(demo.get("title", "DEMO")), str(demo.get("group", "SOLO")),
			str(demo.get("grade", "?")), int(demo.get("score", int(demo.get("quality", 1)) * 20)),
			str(demo.get("date", ""))])
	var progress := DemoManager.progression()
	var rank: Dictionary = progress.get("rank", {})
	var heading := "SZENE-RESPEKT %d/100 · %s\n%s\n\n" % [int(progress.get("respect", 0)),
		str(rank.get("name", "BEDROOM CODER")), str(rank.get("unlock", ""))]
	UIManager.open_info("SZENE-ARCHIV · %d RELEASES" % lines.size(), heading + (
		"\n".join(lines) if not lines.is_empty() else "Noch kein Release. Ein grüner Testlauf öffnet den Freeze."))


func _mark_dirty(refresh := true) -> void:
	_compiled = false
	_tested = false
	_report = {}
	_test_report = {}
	_project.erase("gameplay_test")
	DemoManager.save_draft(_project)
	if refresh:
		_refresh_all()
	else:
		_refresh_report()
		_preview.set_project(_project_for_preview())


# ---------------------------------------------------------------- Hilfen

func _parts() -> Array:
	return _project.get("parts", [])


func _active_part() -> Dictionary:
	var parts := _parts()
	if parts.is_empty():
		return DemoManager.create_part(0)
	return parts[clampi(_selected_part, 0, parts.size() - 1)]


func _normalize_selection() -> void:
	var parts := _parts()
	if parts.is_empty():
		_project["parts"] = [DemoManager.create_part(0)]
		parts = _parts()
	_selected_part = clampi(_selected_part, 0, maxi(0, parts.size() - 1))


func _project_for_preview() -> Dictionary:
	var view := _project.duplicate(true)
	if _report.is_empty():
		return view
	var reports: Array = _report.get("parts", [])
	var parts: Array = view.get("parts", [])
	for i in mini(parts.size(), reports.size()):
		if parts[i] is Dictionary and reports[i] is Dictionary:
			parts[i]["cpu"] = int(reports[i].get("cpu_pct", 0))
			parts[i]["chip_kb"] = int(reports[i].get("chip_kb", 0))
			parts[i]["blitter"] = int(reports[i].get("blitter_pct", 0))
	view["parts"] = parts
	return view


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_close_studio()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F7:
		_compile_project()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F8:
		_test_run()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S and event.ctrl_pressed:
		_save_draft(true)
		get_viewport().set_input_as_handled()
