class_name LabelDesigner
extends RetroWindow
## Diegetisches 44×26-Labelstudio: physische Arbeitsflaeche, professionelle
## Pixelwerkzeuge, Live-Disk, Design-Brief und atomarer Druck-/Klebecommit.

const Model := preload("res://scripts/minigames/label_design_model.gd")
const DiskComposerScript := preload("res://scripts/gfx/disk_composer.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const W := Model.W
const H := Model.H
const CELL := 10
const PALETTE: Array[Color] = [
	Color(0.94, 0.91, 0.82), Color(0.12, 0.10, 0.13),
	Color(0.80, 0.22, 0.22), Color(0.24, 0.38, 0.68),
	Color(0.26, 0.52, 0.32), Color(0.90, 0.78, 0.28),
	Color(0.86, 0.52, 0.20), Color(0.98, 0.97, 0.94),
]
const TOOLS := {
	&"pencil": "STIFT [P]", &"line": "LINIE [L]",
	&"rect": "RAHMEN [R]", &"fill": "FUELLEN [F]",
}

var disk: Disk
var _model: LabelDesignModel
var _grid: LabelGrid
var _preview: TextureRect
var _title_edit: LineEdit
var _status: Label
var _brief_label: Label
var _quality: QualityPanel
var _swatches: Swatches
var _tool_buttons: Dictionary = {}
var _tool: StringName = &"pencil"
var _initial_cells := PackedInt32Array()
var _initial_title := ""
var _finished := false

func _init() -> void:
	title = Loc.t("ui.label_designer.label_works_1_0_disketten_etikett", "LABEL WORKS 1.0 · DISKETTEN-ETIKETT")
	win_size = Vector2(980, 650)

func _ready() -> void:
	super._ready()
	var wins := int(MinigameManager.record("label_design").get("wins", 0))
	_initial_cells = _sticker_cells()
	_initial_title = disk.label if disk else ""
	_model = Model.new()
	_model.configure(clampi(1 + floori(wins / 2.0), 1, 5), hash("LABEL/%s/%d/%d" % [disk.uid if disk else "none", TimeManager.day_counter, wins]), _initial_cells)
	_build_ui()
	_refresh("Studio bereit · Brief lesen, dann bewusst gestalten.")

func _build_ui() -> void:
	content.add_child(Bezel.dim_label(Loc.t("ui.label_designer.originalraster_44_26_rechtsklick_radiert_kein", "Originalraster 44×26 · Rechtsklick radiert · kein Zeitlimit · Druck erst nach deiner Freigabe."), 11))
	var main := HBoxContainer.new()
	main.name = "LabelStudio25D"
	main.custom_minimum_size = Vector2(944, 475)
	main.add_theme_constant_override("separation", 14)
	content.add_child(main)
	var rig := DepthRig.new()
	main.add_child(rig)
	rig.configure(main, 0.62)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 624
	left.add_theme_constant_override("separation", 6)
	main.add_child(left)
	var bench := LabelBench.new()
	bench.custom_minimum_size = Vector2(624, 340)
	left.add_child(bench)
	_grid = LabelGrid.new()
	_grid.model = _model
	_grid.palette = PALETTE
	_grid.cell = CELL
	_grid.custom_minimum_size = Vector2(W * CELL, H * CELL)
	_grid.position = Vector2(86, 42)
	_grid.changed.connect(_on_grid_changed)
	bench.add_child(_grid)
	var tools := GridContainer.new()
	tools.columns = 4
	tools.add_theme_constant_override("h_separation", 6)
	for id: StringName in TOOLS:
		var button := make_button(str(TOOLS[id]), _select_tool.bind(id))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(148, 32)
		tools.add_child(button)
		_tool_buttons[id] = button
	left.add_child(tools)
	var palette_row := HBoxContainer.new()
	_swatches = Swatches.new()
	_swatches.palette = PALETTE
	_swatches.selected = 1
	_swatches.color_selected.connect(_select_color)
	_swatches.custom_minimum_size = Vector2(352, 38)
	palette_row.add_child(_swatches)
	var mirror := make_button(Loc.t("ui.label_designer.spiegel_x_m", "SPIEGEL X [M]"), _toggle_mirror)
	mirror.toggle_mode = true
	mirror.name = "MirrorButton"
	palette_row.add_child(mirror)
	palette_row.add_child(make_button(Loc.t("ui.label_designer.undo", "UNDO"), _undo_edit))
	palette_row.add_child(make_button(Loc.t("ui.label_designer.redo", "REDO"), _redo_edit))
	left.add_child(palette_row)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	right.add_theme_constant_override("separation", 7)
	main.add_child(right)
	right.add_child(Bezel.lcd_label(Loc.t("ui.label_designer.live_master_disk", "LIVE MASTER DISK"), Palette.LCD_AMBER, 10))
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(286, 225)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	right.add_child(_preview)
	_brief_label = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_brief_label.custom_minimum_size.y = 48
	_brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_brief_label)
	_quality = QualityPanel.new()
	_quality.model = _model
	_quality.custom_minimum_size = Vector2(286, 100)
	right.add_child(_quality)
	var stamps := GridContainer.new()
	stamps.columns = 3
	stamps.add_child(make_button(Loc.t("ui.label_designer.blitz", "⚡ BLITZ"), _stamp.bind(&"bolt")))
	stamps.add_child(make_button(Loc.t("ui.label_designer.disk", "▣ DISK"), _stamp.bind(&"disk")))
	stamps.add_child(make_button(Loc.t("ui.label_designer.stern", "★ STERN"), _stamp.bind(&"star")))
	stamps.add_child(make_button(Loc.t("ui.label_designer.raster", "▒ RASTER"), _stamp.bind(&"checker")))
	stamps.add_child(make_button(Loc.t("ui.label_designer.abc_pixeltext", "ABC PIXELTEXT"), _stamp_title))
	stamps.add_child(make_button(Loc.t("ui.label_designer.leeren", "LEEREN"), _clear))
	stamps.add_child(make_button(Loc.t("ui.label_designer.motiv", "← MOTIV"), _move_content.bind(Vector2i.LEFT)))
	stamps.add_child(make_button(Loc.t("ui.label_designer.motiv_5720", "MOTIV →"), _move_content.bind(Vector2i.RIGHT)))
	stamps.add_child(make_button(Loc.t("ui.label_designer.flip", "↔ FLIP"), _flip_content))
	right.add_child(stamps)

	var title_row := HBoxContainer.new()
	title_row.add_child(Bezel.dim_label(Loc.t("ui.label_designer.titel", "TITEL"), 10))
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = Loc.t("ui.label_designer.meine_megademo", "MEINE MEGADEMO")
	_title_edit.max_length = 22
	_title_edit.text = _initial_title
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.text_changed.connect(func(_text: String) -> void: _refresh("Titel aktualisiert."))
	title_row.add_child(_title_edit)
	title_row.add_child(make_button(Loc.t("ui.label_designer.text_ins_bild", "TEXT INS BILD"), _stamp_title))
	content.add_child(title_row)
	var footer := HBoxContainer.new()
	_status = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.custom_minimum_size.y = 42
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status)
	var apply := make_button(Loc.t("ui.label_designer.drucken_aufkleben", "▣ DRUCKEN & AUFKLEBEN"), _apply)
	apply.custom_minimum_size = Vector2(245, 42)
	footer.add_child(apply)
	content.add_child(footer)
	_select_tool(&"pencil")

func _select_tool(tool: StringName) -> void:
	_tool = tool
	_grid.tool = tool
	_grid.cancel_anchor()
	for id in _tool_buttons:
		(_tool_buttons[id] as Button).button_pressed = id == tool
	_refresh("Werkzeug: %s" % TOOLS[tool])

func _select_color(index: int) -> void:
	_model.set_color(index)
	_refresh("Farbe %d gewaehlt." % (index + 1))

func _toggle_mirror() -> void:
	_model.mirror_x = not _model.mirror_x
	var button := find_child("MirrorButton", true, false) as Button
	if button: button.button_pressed = _model.mirror_x
	_grid.queue_redraw()
	_refresh("Spiegelmodus %s." % ("AKTIV" if _model.mirror_x else "AUS"))

func _on_grid_changed(message: String) -> void:
	_refresh(message)

func _undo_edit() -> void:
	if _model.undo(): _grid.cancel_anchor(); _refresh("Letzte Aktion zurueckgenommen.")

func _redo_edit() -> void:
	if _model.redo(): _grid.cancel_anchor(); _refresh("Aktion wiederhergestellt.")

func _move_content(delta:Vector2i)->void:
	if _model.move_content(delta):_grid.cancel_anchor();_refresh("Motiv pixelgenau verschoben.")

func _flip_content()->void:
	if _model.flip_content_x():_grid.cancel_anchor();_refresh("Motiv horizontal gespiegelt.")

func _clear() -> void:
	_model.clear()
	_grid.cancel_anchor()
	_refresh("Papierbogen geleert.")

func _stamp(kind: StringName) -> void:
	if _model.stamp(kind): _refresh("Schablone gesetzt · Assistenz wird in der Wertung markiert.")

func _stamp_title() -> void:
	if _model.stamp_text(_title_edit.text): _refresh("3×5-Pixeltext gesetzt · Assistenz markiert.")
	else: _refresh("Titel enthaelt noch keine darstellbaren Zeichen.")

func _refresh(message: String) -> void:
	if _model == null: return
	_grid.queue_redraw()
	var image := _rasterize()
	_preview.texture = DiskComposerScript.composed_custom(DiskComposerScript.encode_sticker(image), 384,
		disk.color if disk != null else "blue")
	var title_text := _title_edit.text if _title_edit else _initial_title
	var metrics := _model.metrics(title_text)
	var fit := roundi(_model.brief_fit(title_text) * 100.0)
	_brief_label.text = Loc.t("ui.label_designer.level_d_s_fit_02d_n", "LEVEL %d · %s · FIT %02d%%\n%s") % [_model.level, Model.BRIEF_NAMES[_model.brief], fit, Model.BRIEF_TEXT[_model.brief]]
	_quality.title_text = title_text
	_quality.queue_redraw()
	_status.text = Loc.t("ui.label_designer.s_nink_02d_d_farben_balance", "%s\nINK %02d%% · %d FARBEN · BALANCE %02d%% · SCORE %04d%s") % [message,
		roundi(float(metrics.coverage) * 100.0), int(metrics.colors), roundi(float(metrics.balance) * 100.0),
		_model.score(title_text), " · ASSIST" if _model.assisted else ""]

func _apply() -> bool:
	if _finished or disk == null: return false
	var title_text := _title_edit.text.strip_edges()
	if not _model.print_ready(title_text):
		_refresh("NICHT DRUCKREIF · Titel und mindestens 24 Motivpixel benoetigt.")
		return false
	if not _is_changed(title_text):
		_refresh("UNVERAENDERT · identische Fassung verbraucht kein Etikett und gibt keinen Rekord.")
		return false
	if InventoryManager.count("etiketten") <= 0:
		_refresh("KEIN MATERIAL · im Laden Etiketten nachkaufen.")
		return false
	var encoded := DiskComposerScript.encode_sticker(_rasterize())
	if encoded.is_empty() or not InventoryManager.consume("etiketten"): return false
	_finished = true
	disk.sticker_data = encoded
	disk.label = title_text
	disk.labeled = true
	var details := _model.details(title_text)
	details["disk_uid"] = disk.uid
	MinigameManager.finish("label_design", true, _model.score(title_text), details)
	DiskManager.disks_changed.emit()
	AudioManager.relay()
	_status.text = Loc.t("ui.label_designer.master_label_fixiert_04d_punkte_d", "MASTER LABEL FIXIERT · %04d PUNKTE · %d ETIKETTEN UEBRIG") % [_model.score(title_text), InventoryManager.count("etiketten")]
	UIManager.toast(Loc.t("ui.label_designer.label_gedruckt_blasenfrei_aufgeklebt", "Label gedruckt und blasenfrei aufgeklebt."))
	return true

func _is_changed(title_text: String) -> bool:
	return title_text != _initial_title or _model.cells != _initial_cells

func _rasterize() -> Image:
	var image := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W: image.set_pixel(x, y, PALETTE[_model.at(x, y)])
	return image

func _update_preview() -> void:
	# Kompatibilitaets-Hook fuer bestehende Proofs/Editor-Werkzeuge.
	_refresh("Vorschau aktualisiert.")

func _sticker_cells() -> PackedInt32Array:
	var result := PackedInt32Array(); result.resize(W * H); result.fill(0)
	if disk == null or disk.sticker_data.is_empty(): return result
	var image := DiskComposerScript.decode_sticker(disk.sticker_data)
	if image == null or image.get_size() != Vector2i(W, H): return result
	for y in H:
		for x in W: result[y * W + x] = _nearest_index(image.get_pixel(x, y))
	return result

func _nearest_index(color: Color) -> int:
	var best := 0; var distance := INF
	for i in PALETTE.size():
		var candidate := PALETTE[i]
		var next := absf(candidate.r - color.r) + absf(candidate.g - color.g) + absf(candidate.b - color.b)
		if next < distance: distance = next; best = i
	return best

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed and event.keycode == KEY_Z: _undo_edit(); return
	if event.ctrl_pressed and event.keycode == KEY_Y: _redo_edit(); return
	if event.keycode >= KEY_1 and event.keycode <= KEY_8: _select_color(int(event.keycode - KEY_1)); return
	match event.keycode:
		KEY_P: _select_tool(&"pencil")
		KEY_L: _select_tool(&"line")
		KEY_R: _select_tool(&"rect")
		KEY_F: _select_tool(&"fill")
		KEY_M: _toggle_mirror()

class LabelBench:
	extends Control
	const ART := preload("res://assets/ui/minigames/LISTING_DESK_EMPTY_MASTER_V01.png")
	func _draw() -> void:
		var source_size := ART.get_size()
		var source_height := source_size.x * size.y / size.x
		var source := Rect2(0, (source_size.y - source_height) * .55, source_size.x, source_height)
		draw_texture_rect_region(ART, Rect2(Vector2.ZERO, size), source)
		var mat := Rect2(52, 20, 520, 304)
		draw_rect(Rect2(mat.position + Vector2(6, 8), mat.size), Color(0, 0, 0, .52), true)
		draw_rect(mat, Color8(31, 47, 43), true)
		for x in range(int(mat.position.x), int(mat.end.x), 20): draw_line(Vector2(x, mat.position.y), Vector2(x, mat.end.y), Color(0.35, .62, .52, .10))
		for y in range(int(mat.position.y), int(mat.end.y), 20): draw_line(Vector2(mat.position.x, y), Vector2(mat.end.x, y), Color(0.35, .62, .52, .10))
		draw_rect(Rect2(75, 32, 462, 280), Color(0, 0, 0, .45), true)

class LabelGrid:
	extends Control
	signal changed(message: String)
	var model: LabelDesignModel
	var palette: Array[Color]
	var cell := 10
	var tool: StringName = &"pencil"
	var anchor := Vector2i(-1, -1)
	var hover := Vector2i(-1, -1)
	var painting := false
	var erase := false
	var cells: PackedInt32Array:
		get: return model.cells
		set(value): model.cells = value; queue_redraw()

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_CROSS

	func cancel_anchor() -> void:
		anchor = Vector2i(-1, -1); queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			hover = _point(event.position)
			if painting and tool == &"pencil": model.paint(hover, 0 if erase else -1); changed.emit("Freihandlinie gezeichnet.")
			queue_redraw()
		elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			erase = event.button_index == MOUSE_BUTTON_RIGHT
			if event.pressed:
				grab_focus(); var point := _point(event.position)
				match tool:
					&"pencil": model.begin_action(); painting = true; model.paint(point, 0 if erase else -1); changed.emit("Pixel gesetzt.")
					&"fill": model.flood(point, 0 if erase else -1); changed.emit("Flaeche gefuellt.")
					&"line", &"rect":
						if anchor.x < 0: anchor = point; changed.emit("Startpunkt gesetzt · Endpunkt waehlen.")
						elif tool == &"line": model.line(anchor, point, 0 if erase else -1); cancel_anchor(); changed.emit("Praezisionslinie gesetzt.")
						else: model.rectangle(anchor, point, 0 if erase else -1); cancel_anchor(); changed.emit("Rahmen gesetzt.")
			else: painting = false
			queue_redraw()

	func _point(p: Vector2) -> Vector2i:
		return Vector2i(clampi(int(p.x / cell), 0, Model.W - 1), clampi(int(p.y / cell), 0, Model.H - 1))

	func _draw() -> void:
		draw_rect(Rect2(Vector2(-8, -8), size + Vector2(16, 16)), Color(0,0,0,.55), true)
		for y in Model.H:
			for x in Model.W:
				var rect := Rect2(x * cell, y * cell, cell, cell)
				draw_rect(rect, palette[model.at(x, y)], true)
				draw_rect(rect, Color(0,0,0,.055), false, 1)
		if model.mirror_x: draw_line(Vector2(size.x * .5, 0), Vector2(size.x * .5, size.y), Color(1,.65,.18,.72), 2)
		if hover.x >= 0:
			var hover_rect := Rect2(hover.x * cell, hover.y * cell, cell, cell)
			draw_rect(hover_rect.grow(1), Color(1,.72,.20,.92), false, 2)
		if anchor.x >= 0:
			var a := Vector2(anchor.x * cell + cell * .5, anchor.y * cell + cell * .5)
			var b := Vector2(hover.x * cell + cell * .5, hover.y * cell + cell * .5)
			if tool == &"line": draw_line(a, b, Color(1,.72,.20,.72), 2)
			else: draw_rect(Rect2(a, b - a), Color(1,.72,.20,.72), false, 2)
		draw_rect(Rect2(Vector2.ZERO, size), Color8(34, 30, 25), false, 3)

class Swatches:
	extends Control
	signal color_selected(index: int)
	var palette: Array[Color]
	var selected := 1
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			selected = clampi(int(event.position.x / 44.0), 0, palette.size() - 1)
			color_selected.emit(selected); queue_redraw()
	func _draw() -> void:
		for i in palette.size():
			var rect := Rect2(i * 44 + 3, 3, 38, 32)
			draw_rect(rect, palette[i], true)
			draw_rect(rect, Color8(255, 174, 47) if i == selected else Color8(45, 48, 55), false, 3 if i == selected else 1)
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(15, 23), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE if i in [1,2,3,4] else Color.BLACK)

class QualityPanel:
	extends Control
	var model: LabelDesignModel
	var title_text := ""
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(8, 17, 16), true)
		var metrics := model.metrics(title_text)
		var rows := [["INK", float(metrics.coverage) / .65], ["KONTRAST", float(metrics.contrast) / .24], ["BALANCE", float(metrics.balance)], ["BRIEF", model.brief_fit(title_text)]]
		for i in rows.size():
			var y := 8 + i * 22
			draw_string(ThemeDB.fallback_font, Vector2(8, y + 10), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, 72, 9, Color8(156, 220, 192))
			var bar := Rect2(78, y, size.x - 88, 12)
			draw_rect(bar, Color8(18, 39, 35), true)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(rows[i][1], 0, 1), bar.size.y)), Color8(70, 219, 125) if rows[i][1] >= .55 else Color8(255, 177, 53), true)
			draw_rect(bar, Color8(58, 101, 88), false, 1)
