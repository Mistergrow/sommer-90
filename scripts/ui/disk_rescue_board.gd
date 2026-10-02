class_name DiskRescueBoard
extends Control
## AGA-angelehntes Match-3-Playfield fuer den Datenretter.
##
## Die Darstellung bleibt absichtlich aus diskreten Flaechen, Rasterzeilen,
## Hardware-Sprite-Silhouetten und ungefilterten Blitter-Bloecken aufgebaut.
## Hohe Ausgabeaufloesung sorgt fuer Lesbarkeit auf heutigen Monitoren, ohne
## den Charakter einer A1200-Produktion durch weiche Mobile-Game-Grafik zu
## ersetzen.

signal swap_requested(a: Vector2i, b: Vector2i)

const Model := preload("res://scripts/minigames/disk_rescue_model.gd")
const TILE_COLORS := [
	Color8(45, 222, 224), Color8(255, 181, 45), Color8(238, 75, 137),
	Color8(101, 232, 105), Color8(130, 105, 246), Color8(63, 148, 255),
]
const TILE_DARK := [
	Color8(7, 74, 83), Color8(100, 55, 4), Color8(91, 14, 50),
	Color8(25, 84, 28), Color8(45, 27, 102), Color8(16, 48, 108),
]
const TILE_CODES := ["CRC", "MFM", "BPL", "OFS", "DIR", "SYN"]
const COPPER_TOP := Color8(8, 6, 34)
const COPPER_MID := Color8(35, 10, 67)
const COPPER_BOTTOM := Color8(4, 36, 56)

var model: DiskRescueModel
var selected := Vector2i(-1, -1)
var cursor := Vector2i(3, 3)
var locked := false

var _time := 0.0
var _hint_a := Vector2i(-1, -1)
var _hint_b := Vector2i(-1, -1)
var _hint_time := 0.0
var _action_a := Vector2i(-1, -1)
var _action_b := Vector2i(-1, -1)
var _reject_time := 0.0
var _flash_time := 0.0
var _special_time := 0.0
var _special_text := ""
var _effect_cells: Array[Vector2i] = []
var _effect_chain := 1
var _fall_time := 0.0
var _fall_offsets: Dictionary = {}
var _side_complete_time := 0.0
var _disk_complete := false
var _particles: Array[Dictionary] = []
var _bobs: Array[Dictionary] = []
var _font: Font = preload("res://assets/fonts/Topaz_a500_ui.ttf")


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_bobs()
	set_process(true)


func _build_bobs() -> void:
	_bobs.clear()
	for index in 9:
		_bobs.append({
			"phase": float(index) * 0.73,
			"lane": index % 3,
			"kind": index % TILE_COLORS.size(),
		})


func _process(delta: float) -> void:
	var step := minf(maxf(delta, 0.0), 1.0 / 30.0)
	_time += step
	_hint_time = maxf(0.0, _hint_time - delta)
	_reject_time = maxf(0.0, _reject_time - delta)
	_flash_time = maxf(0.0, _flash_time - delta)
	_fall_time = maxf(0.0, _fall_time - delta)
	_special_time = maxf(0.0, _special_time - delta)
	_side_complete_time = maxf(0.0, _side_complete_time - delta)
	_update_particles(step)
	if not bool(SettingsManager.value("reduced_motion")) or _has_active_fx():
		queue_redraw()


func _has_active_fx() -> bool:
	return _hint_time > 0.0 or _reject_time > 0.0 or _flash_time > 0.0 \
		or _fall_time > 0.0 or _special_time > 0.0 or _side_complete_time > 0.0 or not _particles.is_empty()


func _update_particles(delta: float) -> void:
	for index in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[index]
		particle["life"] = float(particle.life) - delta
		particle["position"] = Vector2(particle.position) + Vector2(particle.velocity) * delta
		particle["velocity"] = Vector2(particle.velocity) + Vector2(0.0, 52.0) * delta
		_particles[index] = particle
		if float(particle.life) <= 0.0:
			_particles.remove_at(index)


func _grid_rect() -> Rect2:
	var available := Vector2(size.x - 104.0, size.y - 122.0)
	var cell := floorf(minf(available.x / Model.WIDTH, available.y / Model.HEIGHT))
	cell = maxf(42.0, cell)
	var grid_size := Vector2(cell * Model.WIDTH, cell * Model.HEIGHT)
	return Rect2(Vector2(floorf((size.x - grid_size.x) * 0.5), 79.0), grid_size)


func _cell_rect(cell: Vector2i) -> Rect2:
	var grid := _grid_rect()
	var step := grid.size / Vector2(Model.WIDTH, Model.HEIGHT)
	return Rect2(grid.position + Vector2(cell) * step, step).grow(-4.0)


func _cell_at(pointer: Vector2) -> Vector2i:
	var grid := _grid_rect()
	if not grid.has_point(pointer):
		return Vector2i(-1, -1)
	var step := grid.size / Vector2(Model.WIDTH, Model.HEIGHT)
	return Vector2i((pointer - grid.position) / step)


func _gui_input(event: InputEvent) -> void:
	if locked or model == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		if model.valid_cell(cell):
			cursor = cell
			_choose(cell)
			accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		var cell := _cell_at(event.position)
		if model.valid_cell(cell):
			cursor = cell
			_choose(cell)
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT: cursor.x = maxi(0, cursor.x - 1)
			KEY_RIGHT: cursor.x = mini(Model.WIDTH - 1, cursor.x + 1)
			KEY_UP: cursor.y = maxi(0, cursor.y - 1)
			KEY_DOWN: cursor.y = mini(Model.HEIGHT - 1, cursor.y + 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _choose(cursor)
			KEY_ESCAPE: clear_selection()
			_: return
		queue_redraw()
		accept_event()


func _choose(cell: Vector2i) -> void:
	if selected.x < 0:
		selected = cell
		AudioManager.ui_click()
	elif selected == cell:
		clear_selection()
	elif model.adjacent(selected, cell):
		var first := selected
		selected = Vector2i(-1, -1)
		swap_requested.emit(first, cell)
	else:
		selected = cell
		AudioManager.ui_click()
	queue_redraw()


func clear_selection() -> void:
	selected = Vector2i(-1, -1)
	queue_redraw()


func show_hint(a: Vector2i, b: Vector2i) -> void:
	_hint_a = a
	_hint_b = b
	_hint_time = 2.4
	queue_redraw()


func accept_swap(a: Vector2i, b: Vector2i, result: Dictionary) -> void:
	_action_a = a
	_action_b = b
	_reject_time = 0.0
	_flash_time = 0.58 + float(result.get("chain", 1)) * 0.10
	_effect_chain = int(result.get("chain", 1))
	_special_text = str(result.get("special", "SECTOR LINK"))
	_special_time = 1.15 if _special_text != "SECTOR LINK" else 0.55
	_effect_cells.clear()
	_fall_offsets.clear()
	var removed_per_column := {}
	for raw_index: Variant in result.get("matched_cells", []):
		var effect_cell := Vector2i(int(raw_index) % Model.WIDTH, floori(float(int(raw_index)) / Model.WIDTH))
		_effect_cells.append(effect_cell)
		removed_per_column[effect_cell.x] = int(removed_per_column.get(effect_cell.x, 0)) + 1
	# Sichtbare Schwerkraft: Jede betroffene Spalte startet um die Zahl ihrer
	# geloeschten Steine nach oben versetzt und faellt in die neue Matrix ein.
	# Das bleibt auch bei Kaskaden klar lesbar und vermeidet Instant-Teleport.
	for raw_x: Variant in removed_per_column:
		var column := int(raw_x)
		var removed := int(removed_per_column[raw_x])
		for y in Model.HEIGHT:
			_fall_offsets[y * Model.WIDTH + column] = removed + maxi(
				0, 2 - floori(float(y) / 3.0))
	_fall_time = 0.46
	_spawn_match_particles(result)
	queue_redraw()


func reject_swap(a: Vector2i, b: Vector2i) -> void:
	_action_a = a
	_action_b = b
	_reject_time = 0.48
	_flash_time = 0.0
	_fall_time = 0.0
	_fall_offsets.clear()
	AudioManager.minigame_cue("disk_rescue", &"error")
	queue_redraw()


func begin_side_complete() -> void:
	locked = true
	_side_complete_time = 1.45
	_special_text = Loc.t("ui.disk_rescue_board.side_restored", "SIDE %d RESTORED") % (model.current_side + 1)
	_special_time = 1.45
	for cell_index in Model.WIDTH * Model.HEIGHT:
		var cell := Vector2i(cell_index % Model.WIDTH, floori(float(cell_index) / Model.WIDTH))
		if cell_index % 2 == 0:
			_spawn_at_cell(cell, TILE_COLORS[cell_index % TILE_COLORS.size()], 2)
	queue_redraw()


func begin_bonus_phase() -> void:
	locked = false
	_side_complete_time = 1.15
	_special_text = Loc.t("ui.disk_rescue_board.side_restored_bonus", "SIDE %d RESTORED · BONUS!") % (model.current_side + 1)
	_special_time = 1.35
	for cell_index in Model.WIDTH * Model.HEIGHT:
		if cell_index % 4 == 0:
			var cell := Vector2i(cell_index % Model.WIDTH, floori(float(cell_index) / Model.WIDTH))
			_spawn_at_cell(cell, TILE_COLORS[cell_index % TILE_COLORS.size()], 2)
	queue_redraw()


func begin_disk_complete() -> void:
	locked = true
	_disk_complete = true
	_side_complete_time = 3.0
	_special_text = Loc.t("ui.disk_rescue_board.disk_image_complete", "DISK IMAGE 100%")
	_special_time = 3.0
	for cell_index in Model.WIDTH * Model.HEIGHT:
		var cell := Vector2i(cell_index % Model.WIDTH, floori(float(cell_index) / Model.WIDTH))
		_spawn_at_cell(cell, TILE_COLORS[cell_index % TILE_COLORS.size()], 1)
	queue_redraw()


func reset_for_side() -> void:
	locked = false
	selected = Vector2i(-1, -1)
	cursor = Vector2i(3, 3)
	_hint_time = 0.0
	_reject_time = 0.0
	_flash_time = 0.0
	_special_time = 0.0
	_effect_cells.clear()
	_particles.clear()
	queue_redraw()


func _spawn_match_particles(result: Dictionary) -> void:
	var intensity := clampi(int(result.get("chain", 1)) + 1, 2, 5)
	for cell: Vector2i in _effect_cells:
		var kind := model.tile_at(cell)
		_spawn_at_cell(cell, TILE_COLORS[clampi(kind, 0, TILE_COLORS.size() - 1)], intensity)


func _spawn_at_cell(cell: Vector2i, color: Color, amount: int) -> void:
	var center := _cell_rect(cell).get_center()
	for particle_index in amount * 3:
		var angle := float(particle_index) / maxf(1.0, amount * 3.0) * TAU + cell.x * 0.29
		var speed := 42.0 + float((particle_index * 17 + cell.y * 11) % 46)
		_particles.append({
			"position": center,
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"life": 0.50 + float(particle_index % 3) * 0.11,
			"max_life": 0.72,
			"color": color,
			"size": 2 + particle_index % 3,
		})


func _draw() -> void:
	if model == null:
		return
	_draw_copper_backdrop()
	_draw_raster_tunnel()
	_draw_header_sprites()
	_draw_disk_frame()
	_draw_tiles()
	_draw_particles()
	_draw_foreground_fx()


func _draw_copper_backdrop() -> void:
	# Horizontale 2-Pixel-Baender simulieren Farbregisterwechsel des Copper.
	for y in range(0, int(size.y), 2):
		var ratio := float(y) / maxf(1.0, size.y)
		var color := COPPER_TOP.lerp(COPPER_MID, ratio * 2.0) if ratio < 0.5 \
			else COPPER_MID.lerp(COPPER_BOTTOM, (ratio - 0.5) * 2.0)
		var pulse := sin(_time * 1.7 + float(y) * 0.025) * 0.035
		color = color.lightened(maxf(0.0, pulse)).darkened(maxf(0.0, -pulse))
		draw_rect(Rect2(0, y, size.x, 2), color, true)
	# Schmale Rasterbars, klar getrennt vom Hintergrundgradienten.
	for bar_index in 4:
		var bar_y := fposmod(_time * (13.0 + bar_index * 3.0) + bar_index * 97.0, size.y + 40.0) - 20.0
		var bar_color: Color = TILE_COLORS[(bar_index + 2) % TILE_COLORS.size()]
		draw_rect(Rect2(0, floorf(bar_y), size.x, 2), Color(bar_color, 0.20), true)
		draw_rect(Rect2(0, floorf(bar_y + 3), size.x, 1), Color(bar_color, 0.10), true)


func _draw_raster_tunnel() -> void:
	var grid := _grid_rect()
	var horizon := Vector2(size.x * 0.5, 54.0)
	for lane in 11:
		var x := float(lane) / 10.0 * size.x
		draw_line(horizon, Vector2(x, size.y), Color(0.20, 0.55, 0.78, 0.10), 1.0, false)
	for band in 7:
		var y := grid.position.y + pow(float(band) / 6.0, 1.6) * (size.y - grid.position.y)
		draw_line(Vector2(0, floorf(y)), Vector2(size.x, floorf(y)), Color(0.36, 0.31, 0.74, 0.10), 1.0, false)


func _draw_header_sprites() -> void:
	# Animierter Lesekopf: vier diskrete Frame-Positionen, keine weiche Vektorfigur.
	var scan_phase := floori(_time * 8.0) % 64
	var head_x := 68.0 + float(scan_phase if scan_phase < 32 else 63 - scan_phase) / 31.0 * (size.x - 136.0)
	var head := Rect2(floorf(head_x) - 19, 29, 38, 22)
	draw_rect(Rect2(head.position + Vector2(3, 4), head.size), Color(0, 0, 0, 0.5), true)
	draw_rect(head, Color8(119, 135, 151), true)
	draw_rect(head, Color8(218, 229, 224), false, 2)
	draw_rect(Rect2(head.position + Vector2(6, 6), Vector2(26, 5)), Color8(25, 35, 57), true)
	draw_rect(Rect2(head.position + Vector2(16, 15), Vector2(7, 7)), Palette.LCD_AMBER, true)
	draw_line(Vector2(head.get_center().x, head.end.y), Vector2(head.get_center().x, 68), Color(0.45, 0.95, 1.0, 0.45), 2.0, false)

	# BOBs (Blitter Objects) transportieren Datenpakete in drei Spuren.
	for bob: Dictionary in _bobs:
		var phase := fposmod(_time * (0.12 + int(bob.lane) * 0.025) + float(bob.phase), 1.0)
		var x := floorf(24.0 + phase * (size.x - 48.0))
		var y := 12.0 + int(bob.lane) * 9.0
		var color: Color = TILE_COLORS[int(bob.kind)]
		draw_rect(Rect2(x, y, 5, 5), Color(color, 0.82), true)
		draw_rect(Rect2(x - 7, y + 1, 4, 3), Color(color, 0.32), true)


func _draw_disk_frame() -> void:
	var grid := _grid_rect()
	var outer := grid.grow(19.0)
	draw_rect(Rect2(outer.position + Vector2(8, 9), outer.size), Color(0, 0, 0, 0.55), true)
	draw_rect(outer, Color8(31, 37, 55), true)
	draw_rect(outer, Color8(109, 129, 166), false, 4.0)
	draw_rect(outer.grow(-7), Color8(8, 14, 29), false, 2.0)
	# Seitenlasche und Spurfenster lesen sich wie eine abstrahierte Diskette.
	var shutter := Rect2(outer.position.x + outer.size.x * 0.34, outer.position.y - 12, outer.size.x * 0.32, 20)
	draw_rect(shutter, Color8(123, 137, 151), true)
	draw_rect(shutter, Color8(211, 221, 218), false, 2.0)
	draw_rect(Rect2(shutter.position + Vector2(9, 5), Vector2(shutter.size.x - 18, 5)), Color8(41, 51, 70), true)
	for screw in [outer.position + Vector2(8, 8), Vector2(outer.end.x - 8, outer.position.y + 8),
		Vector2(outer.position.x + 8, outer.end.y - 8), outer.end - Vector2(8, 8)]:
		draw_circle(screw, 3.0, Color8(183, 196, 194))
		draw_line(screw - Vector2(2, 0), screw + Vector2(2, 0), Color8(56, 65, 74), 1.0, false)


func _draw_tiles() -> void:
	var reduced := bool(SettingsManager.value("reduced_motion"))
	for y in Model.HEIGHT:
		for x in Model.WIDTH:
			var cell := Vector2i(x, y)
			var kind := model.tile_at(cell)
			var rect := _cell_rect(cell)
			if _fall_time > 0.0 and _fall_offsets.has(y * Model.WIDTH + x):
				var ratio := _fall_time / 0.46
				var step_y := _grid_rect().size.y / Model.HEIGHT
				var tiles_up := float(_fall_offsets[y * Model.WIDTH + x])
				rect.position.y -= floorf(step_y * tiles_up * ratio * ratio)
			var action := cell == _action_a or cell == _action_b
			var rejected := action and _reject_time > 0.0
			var matched := cell in _effect_cells and _flash_time > 0.0
			var pulse := 0.0 if reduced else sin(_time * 6.0 + x * 0.71 + y * 0.43) * 0.035
			var color: Color = TILE_COLORS[kind].lightened(maxf(0.0, pulse)).darkened(maxf(0.0, -pulse))
			if rejected:
				color = Color8(235, 67, 65)
			elif matched:
				color = color.lightened(0.30 + 0.12 * sin(_flash_time * 25.0))
			_draw_tile(rect, kind, color, cell)
			if cell == selected:
				draw_rect(rect.grow(3), Color.WHITE, false, 3.0)
				draw_rect(rect.grow(6), Color(Palette.LCD_CYAN, 0.70), false, 1.0)
			if cell == cursor and has_focus():
				draw_rect(rect.grow(5), Palette.LCD_AMBER, false, 2.0)
			if _hint_time > 0.0 and (cell == _hint_a or cell == _hint_b):
				var hint_on := floori(_hint_time * 7.0) % 2 == 0
				draw_rect(rect.grow(4), Color8(255, 244, 110) if hint_on else Color8(74, 223, 255), false, 3.0)


func _draw_tile(rect: Rect2, kind: int, color: Color, cell: Vector2i) -> void:
	# Mehrstufige Fase wie bei geprägten AGA-GUI-Bloecken; harte Kanten sind
	# bewusst ungefiltert und ergeben auf grossen Displays ein sauberes Pixelbild.
	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.52), true)
	draw_rect(rect, TILE_DARK[kind], true)
	draw_rect(rect.grow(-2), color, true)
	draw_line(rect.position + Vector2(2, 2), Vector2(rect.end.x - 2, rect.position.y + 2), color.lightened(0.38), 2.0, false)
	draw_line(rect.position + Vector2(2, 2), Vector2(rect.position.x + 2, rect.end.y - 2), color.lightened(0.25), 2.0, false)
	draw_line(Vector2(rect.position.x + 2, rect.end.y - 2), rect.end - Vector2(2, 2), color.darkened(0.45), 2.0, false)
	draw_line(Vector2(rect.end.x - 2, rect.position.y + 2), rect.end - Vector2(2, 2), color.darkened(0.38), 2.0, false)
	var center := rect.get_center().floor()
	_draw_tile_symbol(kind, center, rect.size.x * 0.25, TILE_DARK[kind])
	draw_string(_font, rect.position + Vector2(6, rect.size.y - 7), TILE_CODES[kind],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.88))
	draw_string(_font, Vector2(rect.end.x - 20, rect.position.y + 13), "%X" % posmod(cell.x + cell.y * 3, 16),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(TILE_DARK[kind], 0.75))


func _draw_tile_symbol(kind: int, center: Vector2, radius: float, ink: Color) -> void:
	match kind:
		0: # CRC ring
			draw_arc(center, radius, 0, TAU, 12, ink, 3.0, false)
			draw_rect(Rect2(center - Vector2(2, radius + 2), Vector2(4, radius * 0.55)), ink, true)
		1: # MFM bit clock
			for offset in [-1, 0, 1]:
				draw_line(center + Vector2(-radius, offset * 5), center + Vector2(-radius * 0.35, -offset * 5), ink, 2.0, false)
				draw_line(center + Vector2(-radius * 0.35, -offset * 5), center + Vector2(radius, offset * 5), ink, 2.0, false)
		2: # Bitplanes
			for band in 4:
				draw_rect(Rect2(center + Vector2(-radius, -radius + band * radius * 0.55), Vector2(radius * 2, 3)), ink, true)
		3: # OFS cross
			draw_rect(Rect2(center - Vector2(radius, 3), Vector2(radius * 2, 6)), ink, true)
			draw_rect(Rect2(center - Vector2(3, radius), Vector2(6, radius * 2)), ink, true)
		4: # Directory diamond
			var points := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0),
				center + Vector2(0, radius), center + Vector2(-radius, 0)])
			draw_colored_polygon(points, ink)
		5: # Sync bars
			for bar in 3:
				var height := radius * (0.7 + bar * 0.35)
				draw_rect(Rect2(center + Vector2(-radius + bar * radius * 0.72, -height * 0.5), Vector2(4, height)), ink, true)


func _draw_particles() -> void:
	for particle: Dictionary in _particles:
		var ratio := clampf(float(particle.life) / maxf(0.01, float(particle.max_life)), 0.0, 1.0)
		var pixel_size := float(particle.size)
		var particle_position := Vector2(particle.position).floor()
		draw_rect(Rect2(particle_position, Vector2(pixel_size, pixel_size)), Color(particle.color, ratio), true)
		if pixel_size >= 3.0:
			draw_rect(Rect2(particle_position + Vector2(pixel_size, 0), Vector2(1, pixel_size)), Color(1, 1, 1, ratio * 0.55), true)


func _draw_foreground_fx() -> void:
	# CRT-Scanlines liegen ueber dem gesamten Playfield, bleiben aber duenn.
	for y in range(1, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.12), 1.0, false)
	if _special_time > 0.0:
		var alpha := clampf(_special_time * 1.7, 0.0, 1.0)
		var banner := Rect2(72, size.y * 0.45 - 32, size.x - 144, 64)
		if _special_text == "COPPER BURST":
			for band in 8:
				var color: Color = TILE_COLORS[band % TILE_COLORS.size()]
				draw_rect(Rect2(0, banner.position.y - 16 + band * 12, size.x, 5), Color(color, alpha * 0.28), true)
		draw_rect(banner, Color(0.01, 0.02, 0.07, alpha * 0.88), true)
		draw_rect(banner, Color(Palette.LCD_CYAN, alpha), false, 3.0)
		draw_string(_font, banner.position + Vector2(0, 41), _special_text,
			HORIZONTAL_ALIGNMENT_CENTER, banner.size.x, 24, Color(1, 1, 1, alpha))
	if _side_complete_time > 0.0:
		var sweep_x := floorf((1.0 - _side_complete_time / 1.45) * size.x)
		draw_rect(Rect2(sweep_x - 10, 0, 10, size.y), Color(0.35, 1.0, 0.80, 0.24), true)
	if _disk_complete:
		var border_color: Color = TILE_COLORS[floori(_time * 8.0) % TILE_COLORS.size()]
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), border_color, false, 4.0)
