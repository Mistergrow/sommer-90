class_name PhoneWindow
extends RetroWindow
## TELEFON — glaubwuerdige 90er-Bedienung auf dem echten Apparat.
##
## Die Zifferntasten sind Hotspots auf dem freigestellten Telefon-Asset. Dadurch
## bleibt die Bedienung eindeutig, ohne wie ein Taschenrechner auszusehen. Die
## eigentliche Verbindungs-, Gebuehren- und Questlogik liegt weiter zentral im
## PhoneManager; dieses Fenster visualisiert nur den aktuellen Leitungszustand.

const PHONE_ART := preload("res://assets/backgrounds/layers/TELEPHONE_A1200_BASE_V03.png")
const PHONE_CRADLED_ART := preload("res://assets/backgrounds/layers/TELEPHONE_A1200_AGA_V03.png")
const HANDSET_ART := preload("res://assets/backgrounds/layers/TELEPHONE_A1200_HANDHELD_V03.png")
const PhoneConsoleFXScript := preload("res://scripts/ui/phone_console_fx.gd")
const PhoneKeyPressFXScript := preload("res://scripts/ui/phone_key_press_fx.gd")
const OUTGOING_RING_MIN := 5.0
const OUTGOING_RING_MAX := 10.0
const RING_CADENCE := 2.2
const MAX_DIGITS := 12

# Normierte Mittelpunkte der sichtbaren Tasten im 1510x1042-Master. Die Hotspots
# skalieren mit dem Telefon, bleiben also auch bei UI-Skalierung deckungsgleich.
const PHONE_KEY_CENTERS := {
	"1": Vector2(0.4934, 0.3685), "2": Vector2(0.5781, 0.3426),
	"3": Vector2(0.6576, 0.3186), "4": Vector2(0.5344, 0.4453),
	"5": Vector2(0.6166, 0.4194), "6": Vector2(0.6907, 0.3935),
	"7": Vector2(0.5735, 0.5307), "8": Vector2(0.6510, 0.5020),
	"9": Vector2(0.7225, 0.4730), "*": Vector2(0.6106, 0.6161),
	"0": Vector2(0.6848, 0.5806), "#": Vector2(0.7523, 0.5461),
}
const PHONE_KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
const PHONE_KEY_AREA_SOURCE_SIZE := Vector2(116.0, 86.0)

var booth := false # true = Telefonzelle (1 DM pro Gespraech)

var _dialed := ""
var _result := ""
var _display: Label
var _result_label: Label
var _state_label: Label
var _line_label: Label
var _call_button: Button
var _hangup_button: Button
var _phone_art: TextureRect
var _phone_surface: Control
var _number_display_panel: PanelContainer
var _handset_art: TextureRect
var _console_fx: Control
var _signal_lamps: Dictionary = {}
var _key_buttons: Dictionary = {}
var _key_press_fx: Dictionary = {}
var _visual_phase := "dialtone"
var _receiver_lifted := true
var _calling := false
var _call_serial := 0


func _init() -> void:
	title = Loc.t("ui.phone_window.telephone_station", "FERNSPRECHPLATZ · TELEFON & KARTEI")
	win_size = Vector2(1040, 660)


func _ready() -> void:
	super._ready()
	AudioManager.play("phone_pickup")
	_build()
	call_deferred("_animate_receiver_lift")


func _exit_tree() -> void:
	_call_serial += 1
	AudioManager.stop_sfx("phone_ringback")
	if _receiver_lifted:
		AudioManager.play("phone_hangup")


func _build() -> void:
	for child: Node in content.get_children():
		child.queue_free()

	content.add_child(_build_line_header())

	var main := HBoxContainer.new()
	main.name = "PhoneWorkspace"
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)
	content.add_child(main)

	var apparatus := VBoxContainer.new()
	apparatus.name = "ApparatusColumn"
	apparatus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apparatus.size_flags_vertical = Control.SIZE_EXPAND_FILL
	apparatus.add_theme_constant_override("separation", 5)
	main.add_child(apparatus)
	apparatus.add_child(_build_phone_stage())

	var input_hint := Bezel.dim_label(
		Loc.t("ui.phone_window.input_hint", "ZIFFERN AM TELEFON DRUECKEN  ·  TASTATUR 0-9  ·  * LOESCHT  ·  # KORRIGIERT"), 10)
	input_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	apparatus.add_child(input_hint)
	apparatus.add_child(_build_actions())

	_result_label = Bezel.dim_label("", 11)
	_result_label.name = "CallResult"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.custom_minimum_size = Vector2(0, 42)
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apparatus.add_child(_result_label)

	main.add_child(_build_directory())
	_update_display()
	_refresh_line_state()


func _build_line_header() -> Control:
	var panel := PanelContainer.new()
	panel.name = "LineHeader"
	panel.add_theme_stylebox_override("panel", _panel_style(Color8(12, 17, 18), Color8(62, 106, 92), 7.0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	var mode_text := Loc.t("ui.phone_window.gelbe_telefonzelle", "GELBE TELEFONZELLE") if booth else Loc.t("ui.phone_window.dein_anschluss", "DEIN ANSCHLUSS")
	identity.add_child(Bezel.lcd_label(mode_text, Palette.LCD_AMBER if booth else Palette.UI_TEXT, 13))
	var number_text := Loc.t("ui.phone_window.muenzapparat", "MUENZAPPARAT · 1 DM BEREITHALTEN") if booth else PhoneManager.player_number
	identity.add_child(Bezel.dim_label(number_text, 12))

	_state_label = Bezel.lcd_label("", Palette.LCD_GREEN, 13)
	_state_label.name = "LineState"
	_state_label.custom_minimum_size = Vector2(230, 0)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_state_label)

	var tariff := VBoxContainer.new()
	tariff.custom_minimum_size = Vector2(220, 0)
	row.add_child(tariff)
	var tariff_title := Bezel.dim_label(Loc.t("ui.phone_window.tarif", "TARIF / LEITUNG"), 11)
	tariff_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tariff.add_child(tariff_title)
	_line_label = Bezel.lcd_label("", Palette.LCD_CYAN, 12)
	_line_label.name = "TariffStatus"
	_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tariff.add_child(_line_label)
	return panel


func _build_phone_stage() -> Control:
	var shell := PanelContainer.new()
	shell.name = "PhoneStageShell"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_stylebox_override("panel", _panel_style(Color8(27, 24, 22), Color8(128, 96, 58), 6.0))

	var stage := Control.new()
	stage.name = "PhoneStage"
	stage.custom_minimum_size = Vector2(640, 420)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	shell.add_child(stage)

	_console_fx = PhoneConsoleFXScript.new()
	_console_fx.name = "PhoneConsoleFX"
	_console_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_console_fx)
	stage.add_child(_build_signal_rail())

	# Das Geraet sitzt auf einer eigenen Flaeche unterhalb der Leitungsanzeige.
	# Hotspots und ausgeschnittene Tastenkappen leben in diesem Koordinatenraum,
	# damit sie bei jeder UI-Skalierung deckungsgleich bleiben.
	var art_surface := Control.new()
	art_surface.name = "PhoneArtSurface"
	art_surface.anchor_left = 0.015
	art_surface.anchor_top = 0.12
	art_surface.anchor_right = 0.985
	art_surface.anchor_bottom = 0.98
	art_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	stage.add_child(art_surface)
	_phone_surface = art_surface

	var shadow := Panel.new()
	shadow.name = "PhoneDropShadow"
	shadow.anchor_left = 0.035
	shadow.anchor_top = 0.055
	shadow.anchor_right = 0.985
	shadow.anchor_bottom = 0.985
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0.0, 0.0, 0.0, 0.42)
	shadow_style.set_corner_radius_all(20)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_surface.add_child(shadow)

	_phone_art = TextureRect.new()
	_phone_art.name = "PhoneBodyArt"
	# Beim Oeffnen ist der Apparat fuer einen kurzen Moment vollstaendig zu
	# sehen. Die Abnehmbewegung tauscht ihn gegen die leere Basis aus.
	_phone_art.texture = PHONE_CRADLED_ART
	_phone_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_phone_art.stretch_mode = TextureRect.STRETCH_SCALE
	_phone_art.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_phone_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_phone_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phone_art.modulate = Color(1.0, 0.93, 0.70) if booth else Color.WHITE
	art_surface.add_child(_phone_art)

	_handset_art = TextureRect.new()
	_handset_art.name = "LiftedHandset"
	_handset_art.texture = HANDSET_ART
	_handset_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_handset_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_handset_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_handset_art.anchor_left = -0.015
	_handset_art.anchor_top = 0.015
	_handset_art.anchor_right = 0.34
	_handset_art.anchor_bottom = 0.99
	_handset_art.modulate = Color(1, 1, 1, 0)
	_handset_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_surface.add_child(_handset_art)

	# Die Nummernanzeige ist wie ein spaeter nachgeruestetes Impulswahl-Modul in
	# die freie Gehaeuseflaeche eingelassen, kein zweites Taschenrechnerfeld.
	var display_panel := PanelContainer.new()
	display_panel.name = "NumberDisplayPanel"
	display_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	display_panel.add_theme_stylebox_override("panel", _panel_style(Color8(8, 19, 13, 235), Color8(61, 120, 78), 5.0))
	art_surface.add_child(display_panel)
	_number_display_panel = display_panel
	var display_box := VBoxContainer.new()
	display_box.add_theme_constant_override("separation", 0)
	display_panel.add_child(display_box)
	var display_caption := Bezel.dim_label(Loc.t("ui.phone_window.selected_number", "GEWAEHLTE NUMMER"), 10)
	display_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display_box.add_child(display_caption)
	_display = Bezel.segment_label(Loc.t("ui.phone_window.text", "_"), Color8(110, 242, 130), 18)
	_display.name = "DialDisplay"
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_display.clip_text = true
	display_box.add_child(_display)

	_key_buttons.clear()
	_key_press_fx.clear()
	for digit: String in PHONE_KEYS:
		_add_phone_hotspot(art_surface, digit)
	art_surface.resized.connect(_layout_phone_surface)
	call_deferred("_layout_phone_surface")
	return shell


func _build_signal_rail() -> Control:
	var rail := PanelContainer.new()
	rail.name = "LineLampStrip"
	rail.anchor_left = 0.025
	rail.anchor_top = 0.018
	rail.anchor_right = 0.975
	rail.anchor_bottom = 0.108
	rail.add_theme_stylebox_override("panel", _panel_style(
		Color8(8, 13, 16, 242), Color8(48, 113, 145), 5.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	rail.add_child(row)
	var identity := Bezel.lcd_label(Loc.t("ui.phone_window.line_monitor", "LEITUNGSMONITOR 90"), Palette.LCD_AMBER, 10)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	_signal_lamps.clear()
	for lamp_id: String in ["dialtone", "ready", "ringing", "connected"]:
		var lamp := Label.new()
		lamp.name = "Lamp_%s" % lamp_id.capitalize()
		lamp.text = "● %s" % _lamp_caption(lamp_id)
		lamp.add_theme_font_size_override("font_size", 10)
		lamp.add_theme_color_override("font_color", Color8(66, 69, 68))
		row.add_child(lamp)
		_signal_lamps[lamp_id] = lamp
	_update_signal_lamps()
	return rail


func _add_phone_hotspot(stage: Control, digit: String) -> void:
	# Das Asset selbst bleibt die einzige Tastengrafik. Ein kurzer transparenter
	# Impuls vermittelt den Hub, ohne einen rechteckigen Bildausschnitt ueber das
	# schraeg fotografierte Gehaeuse zu legen.
	var press_fx := PhoneKeyPressFXScript.new() as Control
	press_fx.name = "KeyPressFX_%s" % _key_name(digit)
	press_fx.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stage.add_child(press_fx)
	_key_press_fx[digit] = press_fx

	var button := Button.new()
	button.name = "PhoneKey_%s" % _key_name(digit)
	button.text = ""
	button.tooltip_text = _key_tooltip(digit)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Nur der echte, ausgeschnittene Tastenkopf ist sichtbar. Besonders der
	# deaktivierte Zustand darf nie den schwarzen globalen Buttonstil erben.
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, _hotspot_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	button.pressed.connect(_phone_key_pressed.bind(digit, button))
	stage.add_child(button)
	_key_buttons[digit] = button

func _phone_art_rect() -> Rect2:
	if not is_instance_valid(_phone_surface):
		return Rect2()
	var source_size := Vector2(PHONE_ART.get_width(), PHONE_ART.get_height())
	if source_size.x <= 0.0 or source_size.y <= 0.0 \
			or _phone_surface.size.x <= 0.0 or _phone_surface.size.y <= 0.0:
		return Rect2()
	var fit_scale := minf(_phone_surface.size.x / source_size.x, _phone_surface.size.y / source_size.y)
	var draw_size := source_size * fit_scale
	return Rect2((_phone_surface.size - draw_size) * 0.5, draw_size)


func _layout_phone_surface() -> void:
	var art_rect := _phone_art_rect()
	if art_rect.size.x <= 1.0:
		return
	_phone_art.position = art_rect.position
	_phone_art.size = art_rect.size
	var image_scale := art_rect.size.x / float(PHONE_ART.get_width())
	var key_area_size := PHONE_KEY_AREA_SOURCE_SIZE * image_scale
	for digit: String in PHONE_KEYS:
		var normalized_center: Vector2 = PHONE_KEY_CENTERS[digit]
		var center: Vector2 = art_rect.position + normalized_center * art_rect.size
		var press_fx := _key_press_fx.get(digit) as Control
		if is_instance_valid(press_fx):
			press_fx.position = center - key_area_size * 0.5
			press_fx.size = key_area_size
			press_fx.pivot_offset = key_area_size * 0.5
			press_fx.rotation = 0.0
		var hotspot := _key_buttons.get(digit) as Button
		if is_instance_valid(hotspot):
			# Grosszuegige, aber nicht ueberlappende Trefferflaeche.
			hotspot.position = center - key_area_size * 0.48
			hotspot.size = key_area_size * 0.96
			hotspot.rotation = 0.0
	if is_instance_valid(_number_display_panel):
		_number_display_panel.position = art_rect.position + art_rect.size * Vector2(0.37, 0.69)
		_number_display_panel.size = art_rect.size * Vector2(0.28, 0.12)

func _build_actions() -> Control:
	var row := HBoxContainer.new()
	row.name = "CallActions"
	row.add_theme_constant_override("separation", 7)

	_call_button = make_button(Loc.t("ui.phone_window.anruf_starten", "ANRUF STARTEN"), _dial_now)
	_call_button.name = "CallButton"
	_call_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_call_button.custom_minimum_size.y = 38
	_style_phone_action(_call_button, Palette.LCD_GREEN)
	_call_button.tooltip_text = Loc.t("ui.phone_window.enter_hint", "Enter startet den Anruf")
	row.add_child(_call_button)

	var correction := make_button(Loc.t("ui.phone_window.korrektur", "KORREKTUR"), _backspace)
	correction.name = "CorrectionButton"
	correction.custom_minimum_size = Vector2(130, 38)
	_style_phone_action(correction, Palette.LCD_CYAN)
	row.add_child(correction)

	var clear := make_button(Loc.t("ui.phone_window.loeschen", "LOESCHEN"), _clear)
	clear.name = "ClearButton"
	clear.custom_minimum_size = Vector2(115, 38)
	_style_phone_action(clear, Palette.LCD_AMBER)
	row.add_child(clear)

	_hangup_button = make_button(Loc.t("ui.phone_window.auflegen", "AUFLEGEN"), _hang_up)
	_hangup_button.name = "HangupButton"
	_hangup_button.custom_minimum_size = Vector2(110, 38)
	_style_phone_action(_hangup_button, Color8(239, 105, 91))
	row.add_child(_hangup_button)
	return row


func _build_directory() -> Control:
	var panel := PanelContainer.new()
	panel.name = "PhoneDirectoryPanel"
	panel.custom_minimum_size.x = 330
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color8(14, 14, 16), Color8(74, 74, 78), 8.0))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 5)
	panel.add_child(right)

	var head := HBoxContainer.new()
	right.add_child(head)
	var title_label := Bezel.lcd_label(Loc.t("ui.phone_window.telefonbuch", "TELEFONBUCH"), Palette.LCD_AMBER, 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var known_count := PhoneManager.known_contact_ids().size()
	head.add_child(Bezel.dim_label(Loc.t("ui.phone_window.eintraege", "%d EINTRAEGE") % known_count, 11))

	var hint := Bezel.dim_label(
		Loc.t("ui.phone_window.directory_hint", "Ein Eintrag uebernimmt die Ortsnummer. Nach einem Umzug muss die Vorwahl selbst gewaehlt werden."), 9)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint)

	var separator := HSeparator.new()
	right.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.name = "DirectoryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "DirectoryList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)

	for npc_id: String in PhoneManager.known_contact_ids():
		var number := PhoneManager.display_number(npc_id)
		if not number.is_empty():
			list.add_child(_contact_row(npc_id, number))
	if list.get_child_count() == 0:
		var empty := Bezel.dim_label(Loc.t("ui.phone_window.keine_nummern", "Noch keine Nummern notiert."), 11)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(empty)
	return panel


func _contact_row(npc_id: String, number: String) -> Control:
	var npc: Dictionary = NPCManager.get_npc(npc_id)
	var moved := PhoneManager._has_moved(npc_id)
	var status := Loc.t("ui.phone_window.vorwahl_noetig", "FERN · VORWAHL SELBST WAEHLEN") if moved else Loc.t("ui.phone_window.ortsanschluss", "ORTSANSCHLUSS · NUMMER UEBERNEHMEN")
	var button := make_button("%s\n%s\n%s" % [str(npc.get("name", "?")).to_upper(), number, status], func() -> void:
		if _calling or not _receiver_lifted:
			return
		if moved:
			_result = Loc.t("ui.phone_window.moved_hint", "Auswaertiger Anschluss: Vorwahl und Nummer am Apparat selbst waehlen.")
			_set_state(Loc.t("ui.phone_window.vorwahl", "VORWAHL NOETIG"), Palette.LCD_AMBER, "error")
			AudioManager.key_click()
			_update_display()
		else:
			_dialed = _digits_only(number)
			_result = Loc.t("ui.phone_window.number_ready", "Nummer aus dem Telefonbuch uebernommen.")
			_set_state(Loc.t("ui.phone_window.waehlbereit", "WAEHLBEREIT"), Palette.LCD_GREEN, "ready")
			AudioManager.key_click()
			_update_display())
	button.name = "Contact_%s" % npc_id
	button.icon = NPCManager.portrait(npc_id)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 48)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 72
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Palette.LCD_AMBER if moved else Palette.UI_TEXT)
	var normal := _panel_style(Color8(22, 23, 27),
		Palette.LCD_AMBER.darkened(0.55) if moved else Color8(58, 76, 88), 6.0)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color8(31, 42, 49)
	hover.border_color = Palette.LCD_CYAN
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.tooltip_text = Loc.t("ui.phone_window.contact_tooltip", "Nummer ins Waehlfeld uebernehmen") if not moved else Loc.t("ui.phone_window.moved_tooltip", "Vorwahl am Telefon selbst waehlen")
	return button


func _phone_key_pressed(digit: String, button: Button = null) -> void:
	if _calling or not _receiver_lifted:
		return
	_animate_key_press(digit, button)
	if digit == "*":
		_clear()
	elif digit == "#":
		_backspace()
	elif _dialed.length() < MAX_DIGITS:
		_dialed += digit
		_result = ""
		_set_state(Loc.t("ui.phone_window.waehlbereit", "WAEHLBEREIT"), Palette.LCD_GREEN, "ready")
		AudioManager.key_click()
		_update_display()


func _animate_key_press(digit: String, button: Button = null) -> void:
	var press_fx := _key_press_fx.get(digit) as Control
	if is_instance_valid(press_fx):
		press_fx.call("trigger")
	if is_instance_valid(button):
		button.modulate = Color(1.32, 1.12, 0.62, 1.0)
		var hit_tween := create_tween()
		hit_tween.tween_property(button, "modulate", Color.WHITE, 0.14)
	if is_instance_valid(_console_fx):
		_console_fx.call("set_phase", "ready")


func _clear() -> void:
	if _calling or not _receiver_lifted:
		return
	_dialed = ""
	_result = ""
	_set_state(Loc.t("ui.phone_window.waehlton", "WAEHLTON"), Palette.LCD_GREEN, "dialtone")
	AudioManager.key_click()
	_update_display()


func _backspace() -> void:
	if _calling or not _receiver_lifted:
		return
	_dialed = _dialed.substr(0, maxi(0, _dialed.length() - 1))
	_result = ""
	_set_state(Loc.t("ui.phone_window.waehlbereit", "WAEHLBEREIT") if not _dialed.is_empty() else Loc.t("ui.phone_window.waehlton", "WAEHLTON"), Palette.LCD_GREEN,
		"ready" if not _dialed.is_empty() else "dialtone")
	AudioManager.key_click()
	_update_display()


func _hang_up() -> void:
	if not _receiver_lifted:
		_lift_receiver()
		return
	_call_serial += 1
	AudioManager.stop_sfx("phone_ringback")
	AudioManager.play("phone_hangup")
	_calling = false
	_receiver_lifted = false
	_dialed = ""
	_result = Loc.t("ui.phone_window.hoerer_aufgelegt", "Hörer liegt auf. Erneut abnehmen oder Fenster schließen.")
	_set_dial_controls_disabled(true)
	_hangup_button.disabled = false
	_hangup_button.text = Loc.t("ui.phone_window.pick_up", "HÖRER ABNEHMEN")
	_set_state(Loc.t("ui.phone_window.aufgelegt", "AUFGELEGT"), Palette.UI_TEXT_DIM, "idle")
	_animate_receiver_down()
	_update_display()


func _lift_receiver() -> void:
	_receiver_lifted = true
	AudioManager.play("phone_pickup")
	_set_dial_controls_disabled(false)
	_hangup_button.text = Loc.t("ui.phone_window.auflegen", "AUFLEGEN")
	_result = Loc.t("ui.phone_window.receiver_ready", "Hörer in der Hand. Du kannst wählen.")
	_set_state(Loc.t("ui.phone_window.waehlton", "WAEHLTON"), Palette.LCD_GREEN, "dialtone")
	_animate_receiver_lift()
	_update_display()


func _animate_receiver_lift() -> void:
	if not is_instance_valid(_handset_art) or not is_instance_valid(_phone_art):
		return
	if _handset_art.size.x <= 1.0:
		call_deferred("_animate_receiver_lift")
		return
	if not _handset_art.has_meta("held_position"):
		_handset_art.set_meta("held_position", _handset_art.position)
	var held_position := _handset_art.get_meta("held_position") as Vector2
	_handset_art.pivot_offset = _handset_art.size * Vector2(0.48, 0.52)
	_phone_art.texture = PHONE_ART
	_handset_art.visible = true
	_handset_art.position = held_position + Vector2(176, 56)
	_handset_art.rotation_degrees = 48.0
	_handset_art.scale = Vector2(0.56, 0.56)
	_handset_art.modulate = Color(1.0, 0.92, 0.72, 0.45)
	if bool(SettingsManager.value("reduced_motion")):
		_handset_art.position = held_position
		_handset_art.rotation_degrees = 0.0
		_handset_art.scale = Vector2.ONE
		_handset_art.modulate = Color.WHITE
		return
	var tween := create_tween()
	tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_handset_art, "position", held_position, 0.32)
	tween.tween_property(_handset_art, "rotation_degrees", 0.0, 0.32)
	tween.tween_property(_handset_art, "scale", Vector2.ONE, 0.32)
	tween.tween_property(_handset_art, "modulate", Color.WHITE, 0.22)


func _animate_receiver_down() -> void:
	if not is_instance_valid(_handset_art) or not is_instance_valid(_phone_art):
		return
	if not _handset_art.has_meta("held_position") or bool(SettingsManager.value("reduced_motion")):
		_complete_receiver_down()
		return
	var held_position := _handset_art.get_meta("held_position") as Vector2
	var tween := create_tween()
	tween.set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_handset_art, "position", held_position + Vector2(176, 56), 0.22)
	tween.tween_property(_handset_art, "rotation_degrees", 48.0, 0.22)
	tween.tween_property(_handset_art, "scale", Vector2(0.56, 0.56), 0.22)
	tween.tween_property(_handset_art, "modulate", Color(1, 1, 1, 0), 0.18)
	tween.chain().tween_callback(_complete_receiver_down)


func _complete_receiver_down() -> void:
	if is_instance_valid(_handset_art):
		_handset_art.visible = false
	if is_instance_valid(_phone_art):
		_phone_art.texture = PHONE_CRADLED_ART


## Ortsnummer XX XX XX; laengere Nummern erhalten einen Vorwahlblock.
func _format(digits: String) -> String:
	if digits.is_empty():
		return "_"
	var rest := digits
	var head := ""
	if digits.length() > 6:
		head = digits.substr(0, digits.length() - 6) + "  "
		rest = digits.substr(digits.length() - 6)
	var formatted := ""
	for index: int in rest.length():
		if index > 0 and index % 2 == 0:
			formatted += " "
		formatted += rest[index]
	return head + formatted


func _update_display() -> void:
	if is_instance_valid(_display):
		_display.text = _format(_dialed)
	if is_instance_valid(_result_label):
		_result_label.text = _result
	if is_instance_valid(_call_button):
		_call_button.disabled = _calling or not _receiver_lifted or _dialed.is_empty()


func _refresh_line_state() -> void:
	if not _receiver_lifted:
		_set_state(Loc.t("ui.phone_window.aufgelegt", "AUFGELEGT"), Palette.UI_TEXT_DIM, "idle")
		return
	if booth:
		_line_label.text = Loc.t("ui.phone_window.booth_tariff", "%d DM SOFORT · KEINE HAUSLEITUNG") % PhoneManager.BOOTH_COST
		_set_state(Loc.t("ui.phone_window.muenzbereit", "MUENZBEREIT"), Palette.LCD_AMBER, "dialtone")
	elif PhoneManager.line_locked():
		_line_label.text = Loc.t("ui.phone_window.locked_bill", "GESPERRT · RECHNUNG %d DM") % PhoneManager.bill_due
		_set_state(Loc.t("ui.phone_window.gesperrt", "LEITUNG GESPERRT"), Color8(239, 91, 79), "error")
	elif not PhoneManager.line_free():
		_line_label.text = Loc.t("ui.phone_window.modem_online", "MODEM ONLINE · LEITUNG BELEGT")
		_set_state(Loc.t("ui.phone_window.besetzt", "BESETZT"), Palette.LCD_AMBER, "busy")
	else:
		_line_label.text = Loc.t("ui.phone_window.home_tariff", "ORT %d DM · FERN %d DM") % [PhoneManager.CALL_COST, PhoneManager.CALL_COST_FERN]
		_set_state(Loc.t("ui.phone_window.waehlton", "WAEHLTON"), Palette.LCD_GREEN, "dialtone")


func _dial_now() -> void:
	if _calling or not _receiver_lifted:
		return
	if _dialed.is_empty():
		_result = Loc.t("ui.phone_window.no_number", "Noch keine Nummer gewaehlt.")
		_set_state(Loc.t("ui.phone_window.waehlton", "WAEHLTON"), Palette.LCD_AMBER, "error")
		_update_display()
		return
	_set_state(Loc.t("ui.phone_window.verbindung_pruefen", "VERBINDUNG PRUEFEN"), Palette.LCD_CYAN, "checking")
	var result: Dictionary = PhoneManager.dial(_dialed, booth)
	_dialed = ""
	var sound := str(result.get("sound", ""))
	if bool(result.get("ok", false)) or sound == "klingeln":
		_ring_then_finish(result)
		return
	_result = str(result.get("text", ""))
	match sound:
		"fax":
			AudioManager.play("fax", 0.0)
			_set_state(Loc.t("ui.phone_window.datenleitung", "DATENLEITUNG"), Palette.LCD_CYAN, "checking")
		"besetzt":
			AudioManager.play("phone_busy")
			_set_state(Loc.t("ui.phone_window.besetzt", "BESETZT"), Palette.LCD_AMBER, "busy")
		_:
			AudioManager.phone_dialtone()
			_set_state(Loc.t("ui.phone_window.kein_anschluss", "KEIN ANSCHLUSS"), Color8(239, 105, 91), "error")
	_update_display()


func _ring_then_finish(result: Dictionary) -> void:
	_calling = true
	_call_serial += 1
	var serial := _call_serial
	_set_dial_controls_disabled(true)
	var duration := randf_range(OUTGOING_RING_MIN, OUTGOING_RING_MAX)
	var elapsed := 0.0
	var rings := 0
	while elapsed < duration:
		rings += 1
		_result = Loc.t("ui.phone_window.ringing", "Rufaufbau ... KLINGELN %s") % ".".repeat(mini(rings, 4))
		_set_state(Loc.t("ui.phone_window.rufaufbau", "RUFAUFBAU"), Palette.LCD_CYAN, "ringing")
		_update_display()
		AudioManager.stop_sfx("phone_ringback")
		AudioManager.phone_ringback()
		var wait_time := minf(RING_CADENCE, duration - elapsed)
		await get_tree().create_timer(wait_time).timeout
		if serial != _call_serial or not is_inside_tree():
			return
		elapsed += wait_time
	AudioManager.stop_sfx("phone_ringback")
	_calling = false
	_set_dial_controls_disabled(false)
	if not bool(result.get("ok", false)):
		_result = str(result.get("text", Loc.t("ui.phone_window.no_answer", "Niemand hebt ab.")))
		_set_state(Loc.t("ui.phone_window.keine_antwort", "KEINE ANTWORT"), Palette.LCD_AMBER, "error")
		_update_display()
		return
	_finish_connected_call(result)


func _finish_connected_call(result: Dictionary) -> void:
	var npc_id := str(result.get("npc", ""))
	var dialogue := str(result.get("dialogue", ""))
	AudioManager.play("phone_pickup", 0.0)
	_result = Loc.t("ui.phone_window.connected", "Verbunden mit %s.") % PhoneManager.display_number(npc_id)
	_set_state(Loc.t("ui.phone_window.verbunden", "VERBUNDEN"), Palette.LCD_GREEN, "connected")
	_update_display()
	if not dialogue.is_empty():
		DialogueManager.start_dialogue(dialogue, npc_id)
	else:
		var speaker := "TEL. %s" % str(NPCManager.get_npc(npc_id).get("name", "?"))
		DialogueManager.start_bark(npc_id, speaker, str(result.get("text", "")))


func _set_dial_controls_disabled(disabled: bool) -> void:
	for node: Node in content.find_children("*", "Button", true, false):
		var button := node as Button
		button.disabled = disabled and button != _hangup_button
	_update_display()


func _set_state(text: String, color: Color, phase: String = "") -> void:
	if not phase.is_empty():
		_visual_phase = phase
	if is_instance_valid(_state_label):
		_state_label.text = text
		_state_label.add_theme_color_override("font_color", color)
	if is_instance_valid(_console_fx):
		_console_fx.call("set_phase", _visual_phase)
	_update_signal_lamps()


func _lamp_caption(lamp_id: String) -> String:
	match lamp_id:
		"dialtone": return Loc.t("ui.phone_window.lamp_dialtone", "WAEHLTON")
		"ready": return Loc.t("ui.phone_window.lamp_number", "NUMMER")
		"ringing": return Loc.t("ui.phone_window.lamp_ringing", "RUF")
		"connected": return Loc.t("ui.phone_window.lamp_connected", "GESPR.")
	return lamp_id.to_upper()


func _update_signal_lamps() -> void:
	for lamp_id: String in _signal_lamps:
		var lamp := _signal_lamps[lamp_id] as Label
		if not is_instance_valid(lamp):
			continue
		var active := lamp_id == _visual_phase \
			or lamp_id == "ringing" and _visual_phase == "checking"
		var color := Color8(66, 69, 68)
		if active:
			color = Palette.LCD_CYAN if lamp_id == "ringing" else Palette.LCD_GREEN
		if _visual_phase in ["error", "busy"] and lamp_id == "ringing":
			color = Palette.LCD_AMBER
		lamp.add_theme_color_override("font_color", color)
		lamp.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.55) if active else Color.TRANSPARENT)
		lamp.add_theme_constant_override("shadow_offset_x", 1)
		lamp.add_theme_constant_override("shadow_offset_y", 1)


func _digits_only(value: String) -> String:
	var digits := ""
	for character: String in value:
		if character >= "0" and character <= "9":
			digits += character
	return digits


func _key_name(digit: String) -> String:
	if digit == "*":
		return "Star"
	if digit == "#":
		return "Hash"
	return digit


func _key_tooltip(digit: String) -> String:
	if digit == "*":
		return Loc.t("ui.phone_window.clear_all", "Stern: Nummer loeschen")
	if digit == "#":
		return Loc.t("ui.phone_window.delete_last", "Raute: letzte Ziffer loeschen")
	return Loc.t("ui.phone_window.digit", "Ziffer %s") % digit


func _panel_style(background: Color, border: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


func _style_phone_action(button: Button, accent: Color) -> void:
	var normal := _panel_style(Color8(20, 23, 27), accent.darkened(0.55), 8.0)
	normal.border_width_bottom = 3
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color8(28, 38, 43)
	hover.border_color = accent
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.darkened(0.72)
	pressed.content_margin_top = 10.0
	pressed.content_margin_bottom = 6.0
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Palette.UI_TEXT)
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color8(83, 84, 84))
	button.add_theme_font_size_override("font_size", 11)


func _hotspot_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	return style


func _unhandled_key_input(event: InputEvent) -> void:
	super._unhandled_key_input(event)
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	if key_event.unicode >= 48 and key_event.unicode <= 57:
		_phone_key_pressed(String.chr(key_event.unicode))
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_BACKSPACE:
		_backspace()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_DELETE:
		_clear()
		get_viewport().set_input_as_handled()
	elif key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_dial_now()
		get_viewport().set_input_as_handled()
