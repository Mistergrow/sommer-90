class_name LabelPrintWindow
extends RetroWindow
## ETIKETT DRUCKEN — Kopien-Handel: 9-Nadel < 24-Nadel < Farbdruck mit
## gerastertem Artwork-Logo (höchste Gewinne). Handschrift gehoert zur separaten
## Diskettenbox-Aktion „Etikett". Vorschau zeigt
## das Druckbild; Drucken verbraucht 1 Etikett + Energie und klebt es auf.

var disk: Disk = null

var _stage := 1
var _preview: TextureRect = null
var _info: Label = null
var _stage_buttons: Dictionary = {}


func _init() -> void:
	title = Loc.t("ui.label_print_window.etikett_drucken", "ETIKETT DRUCKEN")
	win_size = Vector2(420, 400)


func _ready() -> void:
	super._ready()
	if disk == null:
		content.add_child(Bezel.dim_label(Loc.t("ui.label_print_window.keine_diskette_gewahlt", "Keine Diskette gewählt."), 11))
		return
	_stage = maxi(2, PlayerStats.best_print_stage())
	content.add_child(Bezel.lcd_label(Loc.t("ui.label_print_window.s", "»%s«") % disk.display_name(), Palette.UI_TEXT, 13))
	content.add_child(Bezel.dim_label(Loc.t("ui.label_print_window.drucker_s_etiketten_d", "Drucker: %s · Etiketten: %d") %
		[PlayerStats.printer_name(),
		InventoryManager.count("etiketten")], 10))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	# Stufenwahl links
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	row.add_child(col)
	col.add_child(Bezel.dim_label(Loc.t("ui.label_print_window.druckstufe", "Druckstufe:"), 10))
	_stage_button(col, 2, "9-Nadel-Titel", PlayerStats.best_print_stage() >= 2)
	_stage_button(col, 3, "24-Nadel-Titel", PlayerStats.best_print_stage() >= 3)
	_stage_button(col, 4, "FARBDRUCK + Logo", PlayerStats.best_print_stage() >= 4)

	# Vorschau rechts (Pixel-genau hochskaliert)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(18, 18, 22)
	sb.border_color = Palette.UI_BORDER_DARK
	sb.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", sb)
	_preview = TextureRect.new()
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(176, 104)
	frame.add_child(_preview)
	row.add_child(frame)

	_info = Bezel.dim_label("", 10)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_info)
	content.add_child(make_button(Loc.t("ui.label_print_window.drucken_1_etikett", "🖶  Drucken (1 Etikett)"), _print_now))
	_update_preview()


func _stage_button(parent: Control, stage: int, label: String, enabled: bool) -> void:
	var b := make_button(label, func() -> void:
		_stage = stage
		_update_preview())
	b.disabled = not enabled
	b.set_meta("stage_label", label)
	_stage_buttons[stage] = b
	parent.add_child(b)


func _update_preview() -> void:
	var img := LabelPrint.make(disk, _stage)
	_preview.texture = ImageTexture.create_from_image(img)
	for stage_value: Variant in _stage_buttons:
		var stage := int(stage_value)
		var button: Button = _stage_buttons[stage]
		var base := str(button.get_meta("stage_label", button.text))
		button.text = ("▶ " if stage == _stage else "  ") + base
	if _info != null:
		var gain := 1.0 + 0.22 * float(_stage)
		var process := " · CJ-300 CMY-Raster · echtes Farbartwork" if _stage == 4 else ""
		_info.text = Loc.t("ui.label_print_window.stufe_s_s_kopienwert_2f_wert", "Stufe: %s%s — Kopienwert ×%.2f. Wert danach: ~%d DM") % [
			CultureManager.label_stage_name(_stage), process, gain,
			roundi(float(CultureManager.disk_value(disk)) * gain
				/ (1.0 + 0.22 * float(disk.label_quality)))]


func _print_now() -> void:
	var r: Dictionary = CopyTradeManager.print_label(disk, _stage)
	UIManager.toast(str(r.get("text", "")))
	if bool(r.get("ok", false)):
		_update_preview()
