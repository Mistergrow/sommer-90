class_name BoxSortMinigame
extends RetroWindow
## Premium-Sortierbrett: echte Diskettenkarten liegen in einer gemalten
## 12-Fach-Box. Klicken oder Ziehen tauscht Fächer; Auswahl bleibt beim Wechsel
## zwischen mehreren Boxseiten erhalten. Die Sammlung wird erst beim Erfolg
## atomar übernommen.

const PAGE_SIZE := 12
const BOARD_ART := preload("res://assets/ui/minigames/box_sort_board_v02.png")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")
const Model := preload("res://scripts/minigames/box_sort_model.gd")
const SortOrder := preload("res://scripts/autoload/disk_sort_order.gd")

var _mode := 0
var _model: BoxSortModel
var _page := 0
var _page_count := 1
var _finished := false
var _hint_partner := -1
var _board: SortBoard
var _status: Label
var _selection_info: Label
var _target_strip: HBoxContainer
var _page_label: Label
var _prev_page: Button
var _next_page: Button
var _partner_button: Button
var _depth_rig: Node


func _init() -> void:
	title = Loc.t("ui.box_sort_minigame.diskettenbox_sortier_puzzle", "DISKETTENBOX · SORTIER-PUZZLE")
	win_size = Vector2(980, 720)


func _ready() -> void:
	super._ready()
	_mode = DiskManager.sort_mode
	_build_shell()
	_new_round()


func _build_shell() -> void:
	var intro := Bezel.dim_label(Loc.t("ui.box_sort_minigame.touch_maus_ziehen_oder_zwei_facher", "Touch/Maus: ziehen oder zwei Fächer wählen · Tastatur: ←/→ + Enter · Gold zeigt den kanonischen Zielplatz."), 11)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)

	var top := HBoxContainer.new()
	top.add_child(Bezel.dim_label(Loc.t("ui.box_sort_minigame.archiv_ordnung", "ARCHIV-ORDNUNG"), 10))
	var modes := OptionButton.new()
	for mode_name: String in DiskManager.SORT_MODES:
		modes.add_item(mode_name.to_upper())
	modes.select(_mode)
	modes.item_selected.connect(func(i: int) -> void:
		_mode = i
		_new_round())
	top.add_child(modes)
	var tie_rule := Bezel.dim_label(Loc.t("ui.box_sort_minigame.gleichstand_name_archiv_id", "GLEICHSTAND → NAME → ARCHIV-ID"), 11)
	tie_rule.tooltip_text = Loc.t("ui.box_sort_minigame.dieselbe_totalordnung_gilt_fuer_puzzle_ueberspringen", "Dieselbe Totalordnung gilt fuer Puzzle, Ueberspringen und System-Sort.")
	top.add_child(tie_rule)
	_status = Bezel.lcd_label("", Palette.LCD_GREEN, 12)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_status)
	content.add_child(top)

	_board = SortBoard.new()
	_board.board_texture = BOARD_ART
	_board.custom_minimum_size = Vector2(944, 470)
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.slot_activated.connect(_on_slot_activated)
	_board.selection_changed.connect(_on_selection_changed)
	_board.page_requested.connect(_change_page)
	_board.request_hint.connect(_hint)
	_board.request_undo.connect(_undo)
	content.add_child(_board)
	_depth_rig = DepthRig.new()
	add_child(_depth_rig)
	_depth_rig.configure(_board, 0.72)

	var target_head := HBoxContainer.new()
	target_head.add_child(Bezel.dim_label(Loc.t("ui.box_sort_minigame.zielreihenfolge_dieser_box", "ZIELREIHENFOLGE DIESER BOX:"), 11))
	_target_strip = HBoxContainer.new()
	_target_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_strip.add_theme_constant_override("separation", 3)
	target_head.add_child(_target_strip)
	content.add_child(target_head)

	var footer := HBoxContainer.new()
	_prev_page = make_button(Loc.t("ui.box_sort_minigame.box", "◀ BOX"), _change_page.bind(-1))
	_page_label = Bezel.lcd_label(Loc.t("ui.box_sort_minigame.box_1_1", "BOX 1/1"), Palette.LCD_AMBER, 10)
	_next_page = make_button(Loc.t("ui.box_sort_minigame.box_3b3b", "BOX ▶"), _change_page.bind(1))
	footer.add_child(_prev_page)
	footer.add_child(_page_label)
	footer.add_child(_next_page)
	_selection_info = Bezel.dim_label("", 10)
	_selection_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(_selection_info)
	_partner_button = make_button(Loc.t("ui.box_sort_minigame.zielfach", "ZIELFACH"), _show_hint_partner)
	_partner_button.disabled = true
	footer.add_child(_partner_button)
	footer.add_child(make_button(Loc.t("ui.box_sort_minigame.undo", "Undo"), _undo))
	footer.add_child(make_button(Loc.t("ui.box_sort_minigame.hinweis", "Hinweis"), _hint))
	footer.add_child(make_button(Loc.t("ui.box_sort_minigame.neu_mischen", "Neu mischen"), _new_round))
	footer.add_child(make_button(Loc.t("ui.box_sort_minigame.uberspringen", "Überspringen"), _auto_sort))
	content.add_child(footer)


func _new_round() -> void:
	_model = Model.new()
	var wins := int(MinigameManager.record("box_sort").get("wins", 0))
	var media := DiskManager.media_disks()
	var signature := SortOrder.uid_signature(media)
	var round_seed := int(hash("BOX/%d/%d/%d/%s" % [TimeManager.day_counter, _mode, wins, signature]))
	_model.configure(media, _mode, round_seed, true)
	_page = 0
	_finished = false
	_hint_partner = -1
	_page_count = maxi(1, ceili(_model.order.size() / float(PAGE_SIZE)))
	_board.selected_global = -1
	_board.hint_pair = Vector2i(-1, -1)
	_sync_board()
	if _model.order.size() <= 1:
		call_deferred("_finish_trivial")


func _sync_board() -> void:
	_board.order = _model.order
	_board.target = _model.target
	_board.mode = _mode
	_board.page = _page
	_board.page_size = PAGE_SIZE
	_board.queue_redraw()
	_status.text = Loc.t("ui.box_sort_minigame.s_zuge_02d_par_02d_hinweise", "%s · ZÜGE %02d · PAR %02d · HINWEISE %02d") % [str(_model.box_profile).to_upper(), _model.moves, _model.par, _model.hints]
	_page_label.text = Loc.t("ui.box_sort_minigame.box_d_d", "BOX %d/%d") % [_page + 1, _page_count]
	_prev_page.disabled = _page <= 0
	_next_page.disabled = _page >= _page_count - 1
	_partner_button.disabled = _hint_partner < 0
	_rebuild_target_strip()
	_on_selection_changed(_board.selected_global)


func _rebuild_target_strip() -> void:
	for child in _target_strip.get_children():
		child.queue_free()
	var target := _model.target
	var start := _page * PAGE_SIZE
	for local in PAGE_SIZE:
		var index := start + local
		var chip := Label.new()
		chip.custom_minimum_size = Vector2(48, 18)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_theme_font_size_override("font_size", 10)
		chip.add_theme_color_override("font_color", Palette.LCD_AMBER)
		if index < target.size():
			var disk: Disk = target[index]
			chip.text = Loc.t("ui.box_sort_minigame.02d_s", "%02d %s") % [index + 1, _short_name(disk, 5)]
			chip.tooltip_text = disk.display_name()
		else:
			chip.text = "—"
		_target_strip.add_child(chip)


func _on_slot_activated(from_global: int, to_global: int) -> void:
	if _finished or from_global < 0 or to_global < 0 or from_global == to_global:
		return
	if from_global >= _model.order.size() or to_global >= _model.order.size():
		return
	if not _model.swap_slots(from_global, to_global):
		return
	AudioManager.play("box_item", 0.08)
	Input.vibrate_handheld(18)
	_board.selected_global = -1
	_hint_partner = -1
	_board.hint_pair = Vector2i(-1, -1)
	if _model.is_solved():
		_complete()
	else:
		_sync_board()


func _on_selection_changed(global_index: int) -> void:
	if global_index < 0 or global_index >= _model.order.size():
		_selection_info.text = Loc.t("ui.box_sort_minigame.fach_wahlen", "FACH WÄHLEN")
		return
	var disk: Disk = _model.order[global_index]
	var desired := _model.target.find(disk) + 1
	_selection_info.text = Loc.t("ui.box_sort_minigame.s_ist_02d_ziel_02d", "%s  ·  IST %02d → ZIEL %02d") % [disk.display_name().left(24), global_index + 1, desired]


func _change_page(delta: int) -> void:
	_page = clampi(_page + delta, 0, _page_count - 1)
	_sync_board()


func _hint() -> void:
	if _finished:
		return
	var pair := _model.use_hint()
	if pair.x < 0:
		return
	_page = floori(float(pair.x) / PAGE_SIZE)
	_hint_partner = pair.y
	_board.selected_global = pair.x
	_board.hint_pair = pair
	_sync_board()
	var source_page := floori(float(pair.x) / PAGE_SIZE) + 1
	var partner_page := floori(float(pair.y) / PAGE_SIZE) + 1
	if source_page == partner_page:
		_selection_info.text = Loc.t("ui.box_sort_minigame.tipp_fach_02d_02d_beide_in", "TIPP: FACH %02d ↔ %02d  ·  BEIDE IN BOX %d") % [pair.x + 1, pair.y + 1, source_page]
	else:
		_selection_info.text = Loc.t("ui.box_sort_minigame.tipp_02d_box_d_02d_box", "TIPP: %02d (BOX %d) ↔ %02d (BOX %d)  ·  ZIELFACH DRUECKEN") % [
			pair.x + 1, source_page, pair.y + 1, partner_page]
	UIManager.toast(Loc.t("ui.box_sort_minigame.par_tipp_fach_02d_mit_fach", "PAR-Tipp: Fach %02d mit Fach %02d tauschen.") % [pair.x + 1, pair.y + 1])


func _show_hint_partner() -> void:
	if _hint_partner < 0:
		return
	_page = floori(float(_hint_partner) / PAGE_SIZE)
	_sync_board()
	_selection_info.text = Loc.t("ui.box_sort_minigame.zielfach_02d_auswahl_bleibt_auf_anderen", "ZIELFACH %02d  ·  AUSWAHL BLEIBT AUF DER ANDEREN BOX AKTIV") % [_hint_partner + 1]


func _undo() -> void:
	if _finished or not _model.undo():
		return
	_hint_partner = -1
	_board.hint_pair = Vector2i(-1, -1)
	_board.selected_global = -1
	AudioManager.relay()
	_sync_board()


func _finish_trivial() -> void:
	if _finished or _model == null or _model.order.size() > 1:
		return
	_finished = true
	DiskManager.sort_mode = _mode
	DiskManager._apply_sort()
	DiskManager.disks_changed.emit()
	UIManager.toast(Loc.t("ui.box_sort_minigame.einzelne_diskette_ist_bereits_eindeutig_archiviert", "Eine einzelne Diskette ist bereits eindeutig archiviert."))
	queue_free()


func _complete() -> void:
	_finished = true
	DiskManager.sort_mode = _mode
	if not DiskManager.assign_media_order(_model.order):
		_status.text = Loc.t("ui.box_sort_minigame.archiv_fehler_bestand_hat_sich_geaendert", "ARCHIV FEHLER · BESTAND HAT SICH GEAENDERT")
		_finished = false
		return
	var score := _model.score()
	MinigameManager.finish("box_sort", true, score, _model.details())
	AudioManager.key_enter()
	_status.text = Loc.t("ui.box_sort_minigame.archiv_perfekt_04d_punkte", "ARCHIV PERFEKT · %04d PUNKTE") % score
	_board.celebrate = true
	_board.queue_redraw()
	UIManager.toast(Loc.t("ui.box_sort_minigame.box_kanonisch_nach_s_archiviert_d", "Box kanonisch nach %s archiviert — %d Punkte.") % [DiskManager.SORT_MODES[_mode], score])
	await get_tree().create_timer(1.15).timeout
	queue_free()


func _auto_sort() -> void:
	DiskManager.sort_mode = _mode
	DiskManager._apply_sort()
	DiskManager.disks_changed.emit()
	MinigameManager.finish("box_sort", false, 0, {"auto": true})
	UIManager.toast(Loc.t("ui.box_sort_minigame.automatisch_nach_s_sortiert_bewusst_ohne", "Automatisch nach %s sortiert — bewusst ohne Rekord.") % DiskManager.SORT_MODES[_mode])
	queue_free()


static func _short_name(disk: Disk, chars: int) -> String:
	var words := disk.display_name().strip_edges().split(" ", false)
	var out := ""
	for word in words:
		if out.length() >= chars:
			break
		out += str(word).left(1)
	if out.length() < 2:
		out = disk.display_name().left(chars)
	return out.to_upper()


class SortBoard:
	extends Control
	signal slot_activated(from_global: int, to_global: int)
	signal selection_changed(global_index: int)
	signal page_requested(delta: int)
	signal request_hint
	signal request_undo

	var board_texture: Texture2D
	var order: Array = []
	var target: Array = []
	var mode := 0
	var page := 0
	var page_size := 12
	var selected_global := -1
	var celebrate := false
	var hint_pair := Vector2i(-1, -1)
	var keyboard_local := 0
	var _pressed_slot := -1
	var _dragging := false
	var _drag_offset := Vector2.ZERO
	var _press_position := Vector2.ZERO
	var _pointer := Vector2.ZERO
	var _pulse := 0.0


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		set_process(true)


	func _process(delta: float) -> void:
		_pulse += delta
		queue_redraw()


	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointer_press(event.position)
			else:
				_pointer_release(event.position)
		elif event is InputEventMouseMotion:
			_pointer_move(event.position)
		elif event is InputEventScreenTouch:
			if event.pressed:
				_pointer_press(event.position)
			else:
				_pointer_release(event.position)
		elif event is InputEventScreenDrag:
			_pointer_move(event.position)
		elif event is InputEventKey and event.pressed and not event.echo:
			_handle_key(event)
		queue_redraw()


	func _pointer_press(pos: Vector2) -> void:
		_pointer = pos
		_press_position = pos
		_pressed_slot = _slot_at(pos)
		_dragging = false
		if _pressed_slot >= 0:
			keyboard_local = _pressed_slot
			var r := _slot_rect(_pressed_slot)
			_drag_offset = pos - r.position
			grab_focus()
			Input.vibrate_handheld(10)
		else:
			selected_global = -1
			selection_changed.emit(-1)


	func _pointer_move(pos: Vector2) -> void:
		_pointer = pos
		if _pressed_slot >= 0 and pos.distance_to(_press_position) > 8.0:
			_dragging = true


	func _pointer_release(pos: Vector2) -> void:
		_pointer = pos
		var released := _slot_at(pos)
		var pressed_global := _global_index(_pressed_slot)
		if _dragging and pressed_global >= 0 and released >= 0:
			slot_activated.emit(pressed_global, _global_index(released))
		elif _pressed_slot >= 0:
			_activate(_global_index(_pressed_slot))
		_pressed_slot = -1
		_dragging = false


	func _activate(clicked: int) -> void:
		if clicked < 0:
			return
		if selected_global >= 0 and selected_global != clicked:
			slot_activated.emit(selected_global, clicked)
		else:
			selected_global = -1 if selected_global == clicked else clicked
			selection_changed.emit(selected_global)


	func _handle_key(event: InputEventKey) -> void:
		match event.keycode:
			KEY_LEFT:
				if keyboard_local <= 0:
					page_requested.emit(-1)
					keyboard_local = page_size - 1
				else:
					keyboard_local -= 1
			KEY_RIGHT:
				if keyboard_local >= page_size - 1 or _global_index(keyboard_local + 1) < 0:
					page_requested.emit(1)
					keyboard_local = 0
				else:
					keyboard_local += 1
			KEY_PAGEUP:
				page_requested.emit(-1)
			KEY_PAGEDOWN:
				page_requested.emit(1)
			KEY_ENTER, KEY_SPACE:
				_activate(_global_index(keyboard_local))
			KEY_H:
				request_hint.emit()
			KEY_Z, KEY_BACKSPACE:
				request_undo.emit()
			_:
				return
		Input.vibrate_handheld(8)
		accept_event()


	func _global_index(local_slot: int) -> int:
		if local_slot < 0:
			return -1
		var index := page * page_size + local_slot
		return index if index < order.size() else -1


	func _slot_at(p: Vector2) -> int:
		for i in page_size:
			if _slot_rect(i).has_point(p):
				return i
		return -1


	func _slot_rect(index: int) -> Rect2:
		# Koordinaten folgen exakt den zwölf Fächern des Artworks.
		var art_rect := _art_rect()
		var left := art_rect.position.x + art_rect.size.x * 0.142
		var top := art_rect.position.y + art_rect.size.y * 0.150
		var inner_width := art_rect.size.x * 0.735
		var step := inner_width / 12.0
		return Rect2(left + index * step + step * 0.10, top, step * 0.80, art_rect.size.y * 0.690)


	func _art_rect() -> Rect2:
		if board_texture == null:
			return Rect2(Vector2.ZERO, size)
		var ratio := board_texture.get_width() / float(board_texture.get_height())
		var draw_size := Vector2(size.x, size.x / ratio)
		if draw_size.y > size.y:
			draw_size = Vector2(size.y * ratio, size.y)
		return Rect2((size - draw_size) * 0.5, draw_size)


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(6, 8, 12))
		var ar := _art_rect()
		if board_texture != null:
			draw_texture_rect(board_texture, ar, false)
		for local in page_size:
			var global := _global_index(local)
			var r := _slot_rect(local)
			if global < 0:
				draw_rect(r.grow(-4), Color(0.03, 0.035, 0.04, 0.32))
				continue
			if _dragging and local == _pressed_slot:
				continue
			_draw_disk(r, order[global], global, global == selected_global)
			if _dragging and local == _slot_at(_pointer) and local != _pressed_slot:
				draw_rect(r.grow(5), Color(0.30, 1.0, 0.72, 0.88), false, 4.0)
			if global == hint_pair.y:
				draw_rect(r.grow(6), Color(0.65, 0.42, 1.0, 0.82), false, 4.0)
			if has_focus() and local == keyboard_local:
				draw_rect(r.grow(8), Color(0.30, 0.88, 1.0, 0.70), false, 2.0)
		if _dragging:
			var global_drag := _global_index(_pressed_slot)
			if global_drag >= 0:
				var rr := _slot_rect(_pressed_slot)
				rr.position = _pointer - _drag_offset
				_draw_disk(rr, order[global_drag], global_drag, true, 0.88)
		if celebrate:
			var glow := 0.55 + sin(_pulse * 7.0) * 0.25
			draw_rect(ar.grow(-5), Color(1.0, 0.78, 0.22, glow), false, 5.0)
		if hint_pair.x >= 0 and floori(float(hint_pair.x) / page_size) != floori(float(hint_pair.y) / page_size):
			var font := get_theme_default_font()
			draw_string(font, ar.position + Vector2(ar.size.x * 0.5 - 170, ar.size.y - 12),
				"SEITENWECHSEL: AUSWAHL BLEIBT AKTIV · ZIELFACH-TASTE NUTZEN",
				HORIZONTAL_ALIGNMENT_CENTER, 340, 10, Color(0.82, 0.72, 1.0, 0.95))


	func _draw_disk(r: Rect2, disk: Disk, global_index: int, selected: bool, alpha := 1.0) -> void:
		var shadow := Rect2(r.position + Vector2(4, 6), r.size)
		draw_rect(shadow, Color(0, 0, 0, 0.62 * alpha))
		var body: Color = Palette.disk_color(disk.color)
		body.a = alpha
		draw_rect(r, body)
		var outline := body.darkened(0.55)
		outline.a = alpha
		draw_rect(r, outline, false, 2.0)
		# Metallschieber und Kopföffnung
		var shutter := Rect2(r.position + Vector2(r.size.x * 0.18, 4), Vector2(r.size.x * 0.64, r.size.y * 0.22))
		draw_rect(shutter, Color(0.66, 0.69, 0.68, alpha))
		draw_rect(shutter, Color(0.22, 0.24, 0.25, alpha), false, 1.0)
		# Papierlabel mit zweizeiliger Kennung
		var label := Rect2(r.position + Vector2(4, r.size.y * 0.36), Vector2(r.size.x - 8, r.size.y * 0.42))
		draw_rect(label, Color(0.91, 0.87, 0.72, alpha))
		draw_rect(label, Color(0.30, 0.24, 0.18, alpha), false, 1.0)
		var font := get_theme_default_font()
		var short := BoxSortMinigame._short_name(disk, 5)
		draw_string(font, label.position + Vector2(3, 15), short, HORIZONTAL_ALIGNMENT_CENTER, label.size.x - 6, 9, Color(0.13, 0.12, 0.11, alpha))
		var mode_value := _mode_value(disk)
		draw_string(font, label.position + Vector2(2, 29), mode_value, HORIZONTAL_ALIGNMENT_CENTER, label.size.x - 4, 8, Color(0.25, 0.20, 0.16, alpha))
		# Goldene Zielnummer als gut lesbarer Archivaufkleber zwischen Schieber
		# und Papierlabel (unten würde sie im tiefen Boxfach verschwinden).
		var desired := target.find(disk) + 1
		var badge := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.305)
		draw_circle(badge, 12.0, Color(0.10, 0.085, 0.06, alpha))
		draw_circle(badge, 12.0, Color(1.0, 0.78, 0.25, alpha), false, 2.0)
		draw_string(font, badge + Vector2(-12, 4), "%02d" % desired,
			HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(1.0, 0.86, 0.42, alpha))
		if selected:
			var pulse := 0.72 + sin(_pulse * 8.0) * 0.22
			draw_rect(r.grow(4), Color(1.0, 0.79, 0.24, pulse), false, 3.0)
		elif global_index == target.find(disk):
			draw_rect(r.grow(2), Color(0.25, 0.95, 0.48, 0.65), false, 2.0)


	func _mode_value(disk: Disk) -> String:
		match mode:
			0: return disk.content_type.left(5).to_upper()
			1: return disk.content_type.left(5).to_upper()
			2: return "%d%%" % disk.condition
			_: return "%dDM" % disk.value()
