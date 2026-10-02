class_name SceneControlWindow
extends RetroWindow
## Vollwertige Schaltzentrale fuer das obere Scene-HUD. Generation und Preset
## sind bewusst getrennt: spaetere Amigas koennen fruehere Modi authentisch
## ausfuehren, waehrend jede Generation ihre letzte Auswahl behaelt.

const SceneCatalog := preload("res://scripts/ui/scene_generation_catalog.gd")
const SceneBoard := preload("res://scripts/ui/scene_animator_board.gd")

var _preview: Control
var _status: Label
var _mode_note: Label
var _effect_header: Label
var _generation_buttons: Dictionary = {}
var _effect_buttons: Dictionary = {}
var _refreshing := false


func _init() -> void:
	title = Loc.t("ui.scene_control_window.scene_control", "SCENE CONTROL")
	win_size = Vector2(1120, 760)


func _ready() -> void:
	super._ready()
	_build_header()
	_build_preview()
	_build_generation_selector()
	_build_effect_selector()
	_build_footer()
	SettingsManager.settings_changed.connect(_refresh)
	PlayerStats.stats_changed.connect(_refresh)
	TimeManager.day_changed.connect(_refresh)
	MusicManager.presentation_changed.connect(func(_state: Dictionary) -> void: _refresh())
	SceneReleaseManager.scene_changed.connect(_refresh)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_refresh()


func _on_locale_changed(_locale: String) -> void:
	set_window_title(Loc.t("ui.scene_control_window.scene_control", "SZENE-STEUERUNG"))
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_preview = null
	_status = null
	_mode_note = null
	_effect_header = null
	_generation_buttons.clear()
	_effect_buttons.clear()
	_build_header()
	_build_preview()
	_build_generation_selector()
	_build_effect_selector()
	_build_footer()
	_refresh()


func _build_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var heading := Bezel.lcd_label(Loc.t("ui.scene_control_window.amiga_scene_engine", "AMIGA SCENE ENGINE"), Palette.LCD_AMBER, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	_status = Bezel.dim_label("", 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_status)
	content.add_child(row)


func _build_preview() -> void:
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(0, 158)
	shell.add_theme_stylebox_override("panel", Bezel.display_box())
	_preview = SceneBoard.new()
	_preview.custom_minimum_size = Vector2(0, 152)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.music_reactive = true
	_preview.interactive = false
	shell.add_child(_preview)
	content.add_child(shell)


func _build_generation_selector() -> void:
	var header := HBoxContainer.new()
	var title_label := Bezel.lcd_label(Loc.t("ui.scene_control_window.1_chipset_modus", "1 · CHIPSET-MODUS"), Palette.LCD_CYAN, 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	_mode_note = Bezel.dim_label("", 11)
	_mode_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_mode_note)
	content.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	for mode in ["auto", "ocs", "ecs", "aga"]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(_select_generation.bind(mode))
		row.add_child(button)
		_generation_buttons[mode] = button
	content.add_child(row)


func _build_effect_selector() -> void:
	_effect_header = Bezel.lcd_label(
		Loc.t("ui.scene_control_window.2_scene_preset_spatere_generationen_spielen", "2 · SCENE-PRESET · SPÄTERE GENERATIONEN SPIELEN FRÜHERE EFFEKTE"),
		Palette.LCD_CYAN, 14)
	content.add_child(_effect_header)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	scroll.add_child(grid)
	for definition: Dictionary in SceneCatalog.EFFECTS:
		var id := str(definition["id"])
		var button := Button.new()
		button.custom_minimum_size = Vector2(255, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_effect.bind(id))
		grid.add_child(button)
		_effect_buttons[id] = button


func _build_footer() -> void:
	var line := HSeparator.new()
	content.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var note := Bezel.dim_label(
		Loc.t("ui.scene_control_window.a500_ocs_a600_ocs_ecs_a1200", "A500: OCS  ·  A600: OCS + ECS  ·  A1200: OCS + ECS + AGA  ·  Auswahl wird dauerhaft gemerkt"),
		11)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	row.add_child(make_button(Loc.t("ui.scene_control_window.schliessen", "SCHLIESSEN"), queue_free))
	content.add_child(row)


func _select_generation(mode: String) -> void:
	if _refreshing:
		return
	if mode != "auto" and mode not in SceneCatalog.supported_generations():
		return
	SettingsManager.set_value("hud_scene_generation", mode)
	AudioManager.ui_click()


func _select_effect(id: String) -> void:
	if _refreshing:
		return
	var generation := SceneCatalog.effective_generation()
	var state := SceneCatalog.effect_state(id, generation)
	if not bool(state.get("unlocked", false)):
		UIManager.toast(str(state.get("reason", "Dieser Effekt ist noch gesperrt.")))
		return
	if SceneCatalog.select_effect(id, generation):
		_note_native_generation_achievement(generation)
		AudioManager.ui_click()


func _note_native_generation_achievement(generation: String) -> void:
	var model := str(PlayerStats.desk_model("computer_model"))
	var flag := str({
		"amiga_500:ocs": "scene_ocs_pioneer",
		"amiga_600:ecs": "scene_ecs_wave",
		"amiga_1200:aga": "scene_aga_chroma",
	}.get("%s:%s" % [model, generation], ""))
	if not flag.is_empty():
		AchievementManager.note(flag)


func _refresh() -> void:
	if _preview == null:
		return
	_refreshing = true
	var model := str(PlayerStats.desk_model("computer_model"))
	var machine: String = str({
		"amiga_500": "A500", "amiga_500_plus": "A500+",
		"amiga_600": "A600", "amiga_1200": "A1200",
	}.get(model, model.replace("amiga_", "A").to_upper()))
	var native := SceneCatalog.current_native_generation()
	var requested := str(SettingsManager.value("hud_scene_generation"))
	var active := SceneCatalog.effective_generation(requested, native)
	var definition := SceneCatalog.generation(active)
	var ram: Dictionary = PlayerStats.ram_breakdown()
	_status.text = Loc.t("ui.scene_control_window.s_nativ_s_d_kb_ram", "%s · NATIV %s · %d KB RAM · AKTIV %s") % [
		machine, native.to_upper(), int(ram.get("total_kb", 512)), active.to_upper()]
	var fallback_note := ""
	if requested != "auto" and requested != active:
		fallback_note = Loc.t("ui.scene_control_window.fallback",
			"FALLBACK %s > %s · ") % [
			requested.to_upper(), active.to_upper()]
	_mode_note.text = fallback_note + str(definition.get("summary", ""))
	_mode_note.tooltip_text = _mode_note.text
	_effect_header.text = Loc.t("ui.scene_control_window.effect_inventory",
		"2 · SCENE-PRESETS · %d BEREIT / %d GESAMT · %d AGA-NATIV") % [
		SceneCatalog.unlocked_effects(active).size(), SceneCatalog.effect_count(),
		SceneCatalog.effect_count("aga")]

	var supported := SceneCatalog.supported_generations(native)
	for mode in _generation_buttons:
		var button := _generation_buttons[mode] as Button
		button.disabled = mode != "auto" and mode not in supported
		button.button_pressed = (requested == "auto" and mode == "auto") \
			or (requested != "auto" and mode == active)
		button.text = _generation_button_text(mode, native, active)
		var color := Palette.LCD_GREEN if button.button_pressed else Palette.UI_TEXT
		if button.disabled:
			color = Palette.UI_TEXT_DIM
		button.add_theme_color_override("font_color", color)
		var mode_definition := SceneCatalog.generation(mode if mode != "auto" else native)
		button.tooltip_text = Loc.t("ui.scene_control_window.mode_tooltip",
			"%s\n%s\n%d-Bit-Palette · %d Register · %d Bitplanes") % [
			str(mode_definition.get("era", "")), str(mode_definition.get("display_mode", "")),
			int(mode_definition.get("palette_bits", 12)),
			int(mode_definition.get("color_registers", 32)),
			int(mode_definition.get("bitplanes", 5))]

	var selected := SceneCatalog.selected_effect(active)
	for definition_raw: Dictionary in SceneCatalog.EFFECTS:
		var id := str(definition_raw["id"])
		var button := _effect_buttons[id] as Button
		var state := SceneCatalog.effect_state(id, active)
		var unlocked := bool(state.get("unlocked", false))
		var effect_generation := str(definition_raw.get("generation", "ocs"))
		var effect_definition := SceneCatalog.generation(effect_generation)
		button.disabled = not unlocked
		button.button_pressed = id == selected
		button.text = Loc.t("ui.scene_control_window.s_s_n_s", "%s  %s\n%s") % [
			Loc.t("ui.scene_control_window.active", "AKTIV") if id == selected else effect_generation.to_upper(),
				SceneCatalog.effect_name(id),
			Loc.t("ui.scene_control_window.ready", "BEREIT") if unlocked else str(
				state.get("reason", SceneCatalog.effect_condition(id)))]
		var accent: Color = effect_definition.get("accent", Palette.UI_TEXT)
		button.add_theme_color_override("font_color",
			accent if unlocked else Palette.UI_TEXT_DIM)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.tooltip_text = ("%s · %s" % [
			effect_generation.to_upper(),
			Loc.t("ui.scene_control_window.unlocked", "freigeschaltet") if unlocked
			else str(state.get("reason", Loc.t(
				"ui.scene_control_window.locked", "gesperrt")))])

	_preview.effect = selected
	_preview.caption = Loc.t("ui.scene_control_window.preview_caption",
		"%s-SZENE") % active.to_upper()
	var music_state := MusicManager.presentation_state()
	if bool(music_state.get("playing", false)) \
			or str(music_state.get("source_kind", "")) == "external":
		_preview.presentation_override = {}
	else:
		_preview.presentation_override = {
			"active": true,
			"playing": true,
			"tracker": false,
			"title": Loc.t("ui.scene_control_window.preview_title",
				"%s SZENE-STEUERUNG") % active.to_upper(),
			"artist": str(definition.get("label", "")).to_upper(),
			"source_kind": "preview",
			"source_label": Loc.t("ui.scene_control_window.preview_source",
				"SZENE-STEUERUNG"),
		}
	_preview.queue_redraw()
	_refreshing = false


func _generation_button_text(mode: String, native: String, active: String) -> String:
	if mode == "auto":
		return "%s\n%s" % [Loc.t("ui.scene_control_window.auto_native",
			"AUTO · NATIV"), Loc.t("ui.scene_control_window.native_in_use",
			"%s WIRD VERWENDET") % native.to_upper()]
	var definition := SceneCatalog.generation(mode)
	if mode == active:
		return "%s · %s\n%s" % [mode.to_upper(), Loc.t(
			"ui.scene_control_window.active", "AKTIV"), definition.get("label", "")]
	if mode in SceneCatalog.supported_generations(native):
		return "%s · %s\n%s" % [mode.to_upper(), Loc.t(
			"ui.scene_control_window.selectable", "WÄHLBAR"), definition.get("label", "")]
	return "%s · %s\n%s" % [mode.to_upper(), Loc.t(
		"ui.scene_control_window.not_available", "NICHT VERFÜGBAR"),
		definition.get("era", "")]
