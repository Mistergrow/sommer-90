extends RetroWindow
## Entwicklungsinterne, rein lesende Sicht auf die automatisch erfasste Telemetrie.

var _year_select: OptionButton
var _report_text: RichTextLabel
var _status: Label
var _selected_year := 1990


func _init() -> void:
	title = Loc.t("ui.playtest_report_window.playtest_bericht", "PLAYTEST-BERICHT")
	win_size = Vector2(820, 640)


func _ready() -> void:
	super._ready()
	_selected_year = PlaytestTelemetry.DECADE_REPORT_ID if TimeManager.year >= 1999 else TimeManager.year
	_build_header()
	_build_report_area()
	_build_footer()
	if not PlaytestTelemetry.report_changed.is_connected(_refresh):
		PlaytestTelemetry.report_changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if PlaytestTelemetry.report_changed.is_connected(_refresh):
		PlaytestTelemetry.report_changed.disconnect(_refresh)


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)
	var heading := Bezel.lcd_label(Loc.t("ui.playtest_report_window.lokale_balance_messung", "LOKALE BALANCE-MESSUNG"), Palette.LCD_AMBER, 14)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_year_select = OptionButton.new()
	_year_select.custom_minimum_size.x = 178
	_year_select.add_item(Loc.t("misc.playtest_report_window.1990_1999_dekade", "1990–1999 · Dekade"), PlaytestTelemetry.DECADE_REPORT_ID)
	if _selected_year == PlaytestTelemetry.DECADE_REPORT_ID:
		_year_select.select(0)
	for year in range(1990, maxi(1990, TimeManager.year) + 1):
		_year_select.add_item(str(year), year)
		if year == _selected_year:
			_year_select.select(_year_select.item_count - 1)
	_year_select.item_selected.connect(func(index: int) -> void:
		_selected_year = _year_select.get_item_id(index)
		_refresh())
	header.add_child(_year_select)
	header.add_child(make_button(Loc.t("ui.playtest_report_window.aktualisieren", "Aktualisieren"), _refresh))
	header.add_child(make_button(Loc.t("ui.playtest_report_window.json_exportieren", "JSON exportieren"), _export))


func _build_report_area() -> void:
	var privacy := Label.new()
	privacy.text = Loc.t("ui.playtest_report_window.automatisch_aktiv_lokal_im_save_live", "AUTOMATISCH AKTIV · lokal im Save + Live-Checkpoint · keine Tasten/Freitexte · kein Netzwerk")
	privacy.add_theme_font_size_override("font_size", 10)
	privacy.add_theme_color_override("font_color", Palette.LCD_GREEN)
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(privacy)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(15, 21, 29)
	style.border_color = Color8(79, 105, 126)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	content.add_child(panel)
	_report_text = RichTextLabel.new()
	_report_text.fit_content = false
	_report_text.scroll_active = true
	_report_text.selection_enabled = true
	_report_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report_text.add_theme_font_override("normal_font", load("res://assets/fonts/Topaz_a500_ui.ttf"))
	_report_text.add_theme_font_size_override("normal_font_size", 13)
	_report_text.add_theme_color_override("default_color", Palette.UI_TEXT)
	panel.add_child(_report_text)


func _build_footer() -> void:
	_status = Label.new()
	_status.text = Loc.t("ui.playtest_report_window.automatischer_live_bericht_s", "Automatischer Live-Bericht: %s") % PlaytestTelemetry.report_directory_absolute()
	_status.add_theme_font_size_override("font_size", 10)
	_status.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)


func _refresh() -> void:
	if _report_text == null:
		return
	var report := PlaytestTelemetry.report(_selected_year)
	_report_text.text = PlaytestTelemetry.summary_text(report)


func _export() -> void:
	var result: Dictionary = PlaytestTelemetry.export_report(_selected_year)
	if bool(result.get("ok", false)):
		_status.text = Loc.t("ui.playtest_report_window.export_gespeichert_s", "Export gespeichert: %s") % str(result.get("absolute_path", ""))
		_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
		var selection := "1990–1999" if _selected_year == PlaytestTelemetry.DECADE_REPORT_ID else str(_selected_year)
		UIManager.toast(Loc.t("ui.playtest_report_window.playtest_bericht_s_als_json_exportiert", "Playtest-Bericht %s als JSON exportiert.") % selection)
	else:
		_status.text = Loc.t("ui.playtest_report_window.export_fehlgeschlagen_benutzerordner_ist_nicht_schreibbar", "Export fehlgeschlagen: Benutzerordner ist nicht schreibbar.")
		_status.add_theme_color_override("font_color", Color8(224, 92, 84))
