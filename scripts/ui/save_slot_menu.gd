class_name SaveSlotMenu
extends Control
## Untermenü „Spiel fortsetzen" im Hauptmenü-Stil: drei Speicher-Slots mit
## Kurzinfo (Name · Jahr · Geld), Laden per Klick und Löschen (🗑) je Slot.
## Im TitleScreen ist es eine eingebettete Seite; außerhalb bleibt der bisherige
## Overlay-Modus für mögliche Szenen-/Testaufrufe erhalten.

signal selection_finished(slot: int)

var selecting_new_game := false
var _armed_slot := -1
var _selection_done := false
var embedded_in_title := false
var _vbox: VBoxContainer = null
var _loading := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true

	if not embedded_in_title:
		var dim := ColorRect.new()
		dim.name = "OverlayDim"
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.07, 0.88 if embedded_in_title else 0.92)
	style.border_color = Color(Palette.LCD_AMBER, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(26)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 0 if embedded_in_title else 12
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 9)
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_vbox)

	_rebuild()


func _rebuild() -> void:
	for child in _vbox.get_children():
		child.queue_free()

	var heading := Label.new()
	heading.text = Loc.t("ui.save_slot_menu.new_game_slot", "PLATZ FÜR EINEN NEUEN SOMMER") if selecting_new_game else Loc.t("ui.save_slot_menu.spiel_fortsetzen", "SPIEL FORTSETZEN")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Palette.WHITE)
	heading.add_theme_constant_override("outline_size", 4)
	heading.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05))
	_vbox.add_child(heading)

	var rule := ColorRect.new()
	rule.color = Color(Palette.LCD_AMBER, 0.7)
	rule.custom_minimum_size = Vector2(0, 2)
	_vbox.add_child(rule)

	var hint := Label.new()
	hint.text = Loc.t("ui.save_slot_menu.all_occupied", "Alle Slots sind belegt. Wähle bewusst, welchen Lauf du ersetzen möchtest.") if selecting_new_game else Loc.t("ui.save_slot_menu.wahle_einen_spielstand", "Wähle einen Spielstand.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Palette.LCD_AMBER)
	_vbox.add_child(hint)

	_vbox.add_child(_spacer(10))

	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var info: Dictionary = SaveManager.slot_info(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var label := "SLOT %d   —   %s" % [slot, str(info["summary"]) if info["exists"] else "leer"]
		if selecting_new_game and _armed_slot == slot:
			label = Loc.t("ui.save_slot_menu.confirm_replace", "SLOT %d WIRKLICH ERSETZEN?") % slot
		var load_btn := _menu_button(label)
		load_btn.custom_minimum_size = Vector2(300, 40)
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.disabled = not selecting_new_game and (not bool(info["exists"]) or not bool(info.get("loadable", true)))
		var s := slot
		load_btn.pressed.connect(func() -> void:
			if selecting_new_game:
				_select_slot(s)
			else:
				_load(s))
		row.add_child(load_btn)

		if bool(info["exists"]) and not selecting_new_game:
			var del := _menu_button("🗑")
			del.custom_minimum_size = Vector2(44, 40)
			del.pressed.connect(func() -> void: _delete(s))
			row.add_child(del)

		_vbox.add_child(row)

	_vbox.add_child(_spacer(10))

	var back := _menu_button(Loc.t(
		"ui.save_slot_menu.back_to_main_menu", "‹  ZURÜCK ZUM HAUPTMENÜ"))
	back.custom_minimum_size = Vector2(300, 38)
	if selecting_new_game:
		back.text = Loc.t("ui.save_slot_menu.cancel", "ABBRECHEN · SPIELSTÄNDE BEHALTEN")
	back.pressed.connect(func() -> void: queue_free())
	_vbox.add_child(back)


func _select_slot(slot: int) -> void:
	if _selection_done:
		return
	if SaveManager.has_save(slot) and _armed_slot != slot:
		_armed_slot = slot
		_rebuild()
		return
	_selection_done = true
	selection_finished.emit(slot)
	queue_free()


func _exit_tree() -> void:
	if selecting_new_game and not _selection_done:
		selection_finished.emit(-1)


func _load(slot: int) -> void:
	if _loading:
		return
	_loading = true
	var success := await SaveManager.load_game_with_screen(slot)
	if is_instance_valid(self) and not success:
		_loading = false


func _delete(slot: int) -> void:
	SaveManager.delete_slot(slot)
	AudioManager.play("ui_blip", 0.0)
	_rebuild()


## Menü-Button im exakten Hauptmenü-Stil (dunkles Feld, Amber-Rahmen, Hover leuchtet).
func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.09, 0.12, 0.9)
	normal.border_color = Color(Palette.LCD_AMBER, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.15, 0.05, 0.95)
	hover.border_color = Palette.LCD_AMBER
	hover.border_width_left = 3
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.04, 0.04, 0.05, 0.95)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.07, 0.07, 0.08, 0.7)
	disabled.border_color = Color(0.3, 0.3, 0.3, 0.4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", Palette.WHITE_SOFT)
	b.add_theme_color_override("font_hover_color", Palette.LCD_AMBER)
	b.add_theme_color_override("font_disabled_color", Palette.UI_TEXT_DIM)
	return b


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
