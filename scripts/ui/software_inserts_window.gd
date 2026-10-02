class_name SoftwareInsertsWindow
extends RetroWindow
## Zoombares physisches Beilagenarchiv: Vorderseite, Rueckseite und die
## funktionale CODE-RED-Archivtafel werden aus denselben Besitzdaten aufgebaut.

const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")

var software_id := ""
var initial_insert_id := ""
var reference: Dictionary = {}

var _definitions: Array[Dictionary] = []
var _document_buttons: Array[Button] = []
var _view_buttons: Array[Button] = []
var _selected_index := 0
var _view := "front"
var _zoom := 1.0
var _scroll: ScrollContainer
var _preview_center: CenterContainer
var _preview: TextureRect
var _zoom_label: Label
var _caption: RichTextLabel
var _reference_panel: PanelContainer
var _reference_label: Label


func _init() -> void:
	title = Loc.t("ui.software_inserts_window.originalbeilagen_archiv", "ORIGINALBEILAGEN · ARCHIV")
	win_size = Vector2(980, 690)


func _ready() -> void:
	super._ready()
	_definitions = InsertCatalog.definitions(software_id)
	for index in _definitions.size():
		if str(_definitions[index].get("id", "")) == initial_insert_id:
			_selected_index = index
			break
	_build_header()
	_build_viewer()
	_refresh()


func _build_header() -> void:
	var entry: Dictionary = SoftwareBible.entry(software_id)
	var game_title := str(entry.get("display_name", entry.get("historical_name", software_id)))
	content.add_child(Bezel.lcd_label(game_title.to_upper(), Palette.LCD_AMBER, 13))
	var document_row := HBoxContainer.new()
	document_row.add_theme_constant_override("separation", 6)
	for index in _definitions.size():
		var definition: Dictionary = _definitions[index]
		var button := make_button(str(definition.get("short_title", "BEILAGE")),
			_select_document.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not InsertCatalog.owns(str(definition.get("id", "")))
		button.tooltip_text = Loc.t("ui.software_inserts_window.nicht_im_inventar", "Nicht im Inventar.") if button.disabled else str(definition.get("title", ""))
		document_row.add_child(button)
		_document_buttons.append(button)
	content.add_child(document_row)

	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 6)
	for definition: Dictionary in [
		{"id": "front", "label": "VORNE"},
		{"id": "back", "label": "RÜCKSEITE"},
		{"id": "archive", "label": "ARCHIVTAFEL"},
	]:
		var button := make_button(str(definition["label"]),
			_select_view.bind(str(definition["id"])))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view_row.add_child(button)
		_view_buttons.append(button)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 18
	view_row.add_child(spacer)
	view_row.add_child(make_button(Loc.t("ui.software_inserts_window.text", "−"), _change_zoom.bind(-0.25)))
	_zoom_label = Bezel.lcd_label(Loc.t("ui.software_inserts_window.100", "100 %"), Palette.LCD_GREEN, 10)
	_zoom_label.custom_minimum_size.x = 58
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	view_row.add_child(_zoom_label)
	view_row.add_child(make_button(Loc.t("ui.software_inserts_window.text_26b1", "+"), _change_zoom.bind(0.25)))
	view_row.add_child(make_button(Loc.t("ui.software_inserts_window.einpassen", "EINPASSEN"), _reset_zoom))
	content.add_child(view_row)


func _build_viewer() -> void:
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.016, 0.022, 1.0)
	style.border_color = Color(0.25, 0.34, 0.39, 1.0)
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	content.add_child(frame)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.gui_input.connect(_on_preview_input)
	frame.add_child(_scroll)
	_preview_center = CenterContainer.new()
	_preview_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_preview_center)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview_center.add_child(_preview)

	_reference_panel = PanelContainer.new()
	var reference_style := StyleBoxFlat.new()
	reference_style.bg_color = Color(0.16, 0.025, 0.02, 0.98)
	reference_style.border_color = Color(0.92, 0.24, 0.16, 1.0)
	reference_style.set_border_width_all(2)
	reference_style.set_content_margin_all(8)
	_reference_panel.add_theme_stylebox_override("panel", reference_style)
	_reference_label = Label.new()
	_reference_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reference_label.add_theme_font_size_override("font_size", 15)
	_reference_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.54))
	_reference_panel.add_child(_reference_label)
	content.add_child(_reference_panel)

	_caption = RichTextLabel.new()
	_caption.bbcode_enabled = true
	_caption.fit_content = true
	_caption.custom_minimum_size.y = 54
	_caption.add_theme_font_size_override("normal_font_size", 11)
	content.add_child(_caption)


func _select_document(index: int) -> void:
	if index < 0 or index >= _definitions.size():
		return
	if not InsertCatalog.owns(str(_definitions[index].get("id", ""))):
		return
	_selected_index = index
	_view = "front"
	_zoom = 1.0
	_refresh()


func _select_view(next_view: String) -> void:
	if next_view == "archive":
		for index in _definitions.size():
			if str(_definitions[index].get("kind", "")) == "chart" \
					and InsertCatalog.owns(str(_definitions[index].get("id", ""))):
				_selected_index = index
				break
		_view = "archive"
	else:
		_view = next_view
	_zoom = 1.0
	_refresh()


func _change_zoom(delta: float) -> void:
	_zoom = clampf(_zoom + delta, 0.5, 4.0)
	_apply_zoom()


func _reset_zoom() -> void:
	_zoom = 1.0
	_apply_zoom()


func _refresh() -> void:
	if _definitions.is_empty():
		_caption.text = Loc.t("ui.software_inserts_window.color_ff6e62_fur_diese_software_sind", "[color=#ff6e62]Für diese Software sind keine Beilagen registriert.[/color]")
		_preview.texture = null
		return
	_selected_index = clampi(_selected_index, 0, _definitions.size() - 1)
	var selected: Dictionary = _definitions[_selected_index]
	if not InsertCatalog.owns(str(selected.get("id", ""))):
		var first_owned := _definitions.find_custom(func(entry: Dictionary) -> bool:
			return InsertCatalog.owns(str(entry.get("id", ""))))
		if first_owned < 0:
			_caption.text = Loc.t("ui.software_inserts_window.color_ff6e62_keine_dieser_originalbeilagen_befindet", "[color=#ff6e62]Keine dieser Originalbeilagen befindet sich im Inventar.[/color]")
			_preview.texture = null
			return
		_selected_index = first_owned
		selected = _definitions[_selected_index]
	var art_kind := str(selected.get("front_art" if _view == "front" else "back_art", ""))
	var art_path := SoftwareBible.art_path(software_id, art_kind)
	_preview.texture = RuntimeImages.texture(art_path, 2048, true)
	for index in _document_buttons.size():
		_document_buttons[index].text = ("▶ " if index == _selected_index else "") \
			+ str(_definitions[index].get("short_title", "BEILAGE"))
	for index in _view_buttons.size():
		var active := (index == 0 and _view == "front") or (index == 1 and _view == "back") \
			or (index == 2 and _view == "archive")
		_view_buttons[index].text = ("▶ " if active else "") + [
			Loc.t("ui.software_inserts_window.front", "VORNE"),
			Loc.t("ui.software_inserts_window.back", "RÜCKSEITE"),
			Loc.t("ui.software_inserts_window.archive_board", "ARCHIVTAFEL"),
		][index]
	_caption.text = Loc.t("ui.software_inserts_window.color_ffb33b_b_s_b_color", "[color=#ffb33b][b]%s[/b][/color]\n%s  [color=#6fa5bd]Originalbeilage · nicht verbrauchbar · Kopierschutzmaterial[/color]") % [
		str(selected.get("title", "Beilage")), str(selected.get("description", ""))]
	_refresh_reference()
	call_deferred("_apply_zoom")


func _refresh_reference() -> void:
	var is_chart := not _definitions.is_empty() \
		and str(_definitions[_selected_index].get("kind", "")) == "chart" and _view == "archive"
	_reference_panel.visible = is_chart
	if not is_chart:
		return
	if reference.is_empty():
		_reference_label.text = Loc.t("ui.software_inserts_window.archivtafel_bereit_konkrete_verweis_erscheint_bei", "ARCHIVTAFEL BEREIT · Der konkrete Verweis erscheint bei der Startabfrage.")
		return
	var sector := clampi(int(reference.get("sector", 1)), 1, 8)
	var ring := clampi(int(reference.get("ring", 1)), 1, 6)
	var column := clampi(int(reference.get("column", 1)), 1, 5)
	var keyword := InsertCatalog.code_red_keyword(sector, ring, column)
	_reference_label.text = Loc.t("ui.software_inserts_window.tafel_d_ring_d_spalte_d", "TAFEL %d · RING %d · SPALTE %d   →   %s") % [sector, ring, column, keyword]


func _apply_zoom() -> void:
	if _preview == null or _preview.texture == null:
		return
	var native := Vector2(_preview.texture.get_width(), _preview.texture.get_height())
	var viewport := _scroll.size - Vector2(20, 20)
	if viewport.x <= 20 or viewport.y <= 20:
		viewport = Vector2(900, 455)
	var fit := minf(minf(viewport.x / native.x, viewport.y / native.y), 1.0)
	var display_size := (native * fit * _zoom).round()
	_preview.custom_minimum_size = display_size
	_preview_center.custom_minimum_size = Vector2(maxf(viewport.x, display_size.x),
		maxf(viewport.y, display_size.y))
	_zoom_label.text = Loc.t("ui.software_inserts_window.d", "%d %%") % roundi(_zoom * 100.0)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(0.25)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-0.25)
			accept_event()
