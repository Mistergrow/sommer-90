class_name EndgameStats
extends Control
## Interaktiver Dekadenabschluss von SOMMER '90.
##
## Der Bildschirm ist nicht nur eine Statistik: Er schließt die Reise 1990–1999
## visuell ab, lässt die Sammlung bewusst bewerten, öffnet den vollständigen
## Produktionsabspann und gibt danach den Weg ins Freie Spiel frei.

const CreditsScreen := preload("res://scripts/ui/credits_screen.gd")

const C_BG := Color(0.008, 0.012, 0.022, 0.985)
const C_PANEL := Color(0.025, 0.033, 0.052, 0.96)
const C_BLUE := Color8(34, 132, 211)
const C_CYAN := Color8(74, 210, 224)
const C_AMBER := Color8(255, 178, 43)
const C_GREEN := Color8(89, 235, 128)
const C_WHITE := Color8(235, 239, 231)
const C_DIM := Color8(132, 151, 164)

var _score_board: RichTextLabel
var _collector_button: Button
var _liquidate_button: Button
var _credits_button: Button
var _museum_button: Button
var _free_play_button: Button
var _submitted := false
var _fx_time := 0.0


func _ready() -> void:
	if name.is_empty():
		name = &"win_endgame"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 2100
	_build()
	set_process(true)


func _process(delta: float) -> void:
	_fx_time += delta
	queue_redraw()


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	# Copper-/Vektorfeld: ruhig genug für Lesbarkeit, lebendig genug für ein
	# echtes Millennium-Finale. Alle Linien bleiben hinter den UI-Panels.
	for index in 28:
		var phase := _fx_time * (0.22 + float(index % 3) * 0.04) + index * 0.37
		var y := size.y * (0.08 + float(index) / 31.0)
		var amplitude := 10.0 + float(index % 5) * 3.0
		var left_y := y + sin(phase) * amplitude
		var right_y := y + sin(phase + 1.35) * amplitude
		var tint := C_CYAN if index % 3 else C_AMBER
		draw_line(Vector2(0, left_y), Vector2(size.x, right_y),
			Color(tint.r, tint.g, tint.b, 0.028), 1.0)
	for index in 24:
		var x := fmod(index * 193.0 + _fx_time * (8.0 + index % 4), size.x + 40.0) - 20.0
		var y := size.y * (0.15 + float((index * 7) % 17) / 21.0)
		var pulse := 0.5 + 0.5 * sin(_fx_time * 1.4 + index)
		draw_circle(Vector2(x, y), 1.2 + pulse * 1.8,
			Color(C_BLUE.r, C_BLUE.g, C_BLUE.b, 0.12 + pulse * 0.10))


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var frame := PanelContainer.new()
	frame.name = "FinaleFrame"
	frame.add_theme_stylebox_override("panel", _panel_style(C_AMBER, 0.72, 18))
	margin.add_child(frame)

	var root := VBoxContainer.new()
	root.name = "FinaleContent"
	root.add_theme_constant_override("separation", 9)
	frame.add_child(root)
	root.add_child(_build_header())
	root.add_child(_rule(C_BLUE, 0.72, 2))
	root.add_child(_build_timeline())

	var body := HBoxContainer.new()
	body.name = "DecadeBalance"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	body.add_child(_build_journey_panel())
	body.add_child(_build_stats_panel())
	root.add_child(body)

	root.add_child(_build_collection_finale())

	var memory_line := MemoryManager.remembrance_line()
	if not memory_line.is_empty():
		var memory := _label("„%s“" % memory_line, 11, Color(0.88, 0.81, 0.59))
		memory.name = "FinalMemory"
		memory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		memory.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		root.add_child(memory)

	root.add_child(_build_footer())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.name = "FinaleHeader"
	header.add_theme_constant_override("separation", 14)

	var chapter := VBoxContainer.new()
	chapter.custom_minimum_size.x = 180
	var chapter_top := _label("KAPITEL 10", 10, C_DIM)
	chapter.add_child(chapter_top)
	var chapter_year := _label("1990  ◇  1999", 18, C_AMBER)
	chapter.add_child(chapter_year)
	header.add_child(chapter)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("DEIN JAHRZEHNT", 30, C_WHITE)
	title.name = "FinaleTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 7)
	title.add_theme_color_override("font_outline_color", Color(C_BLUE, 0.48))
	title_box.add_child(title)
	var subtitle := _label("ZEHN SOMMER · EINE SAMMLUNG · DEINE GESCHICHTE", 11, C_AMBER)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(subtitle)
	header.add_child(title_box)

	var status := VBoxContainer.new()
	status.custom_minimum_size.x = 180
	var live := _label("MILLENNIUM READY", 10, C_GREEN)
	live.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(live)
	var time := _label("31.12.1999 · 23:59", 14, C_WHITE)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(time)
	header.add_child(status)
	return header


func _build_timeline() -> Control:
	var panel := PanelContainer.new()
	panel.name = "DecadeTimeline"
	panel.add_theme_stylebox_override("panel", _panel_style(C_BLUE, 0.42, 8))
	var years := HBoxContainer.new()
	years.add_theme_constant_override("separation", 3)
	panel.add_child(years)
	for year in range(1990, 2000):
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dot_color := C_AMBER if year == 1990 or year == 1999 else C_CYAN
		var dot := _label("◆" if year == 1990 or year == 1999 else "·", 15, dot_color)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(dot)
		var year_label := _label(str(year), 10, C_WHITE if year in [1990, 1999] else C_DIM)
		year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(year_label)
		years.add_child(cell)
	return panel


func _build_journey_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "JourneyPanel"
	panel.custom_minimum_size = Vector2(500, 228)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(C_CYAN, 0.36, 12))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)

	var heading := _section_title("VOM KIND ZUM SZENEMACHER")
	column.add_child(heading)
	var avatars := HBoxContainer.new()
	avatars.alignment = BoxContainer.ALIGNMENT_CENTER
	avatars.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatars.add_theme_constant_override("separation", 24)
	avatars.add_child(_avatar_block(1990, "SOMMER 1990", "DER ERSTE AMIGA"))
	var arrow_box := VBoxContainer.new()
	arrow_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var years := _label("10 JAHRE", 10, C_DIM)
	years.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_box.add_child(years)
	var arrow := _label("==>", 27, C_AMBER)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_box.add_child(arrow)
	avatars.add_child(arrow_box)
	avatars.add_child(_avatar_block(1999, "SILVESTER 1999", "BEREIT FÜR 2000"))
	column.add_child(avatars)

	var identity := _label(
		"%s · %d JAHRE · RUF %d" % [
			PlayerIdentity.player_name.to_upper() if not PlayerIdentity.player_name.is_empty() else "SPIELER",
			PlayerIdentity.age_at_year_end(1999), PlayerStats.ruf],
		12, C_GREEN)
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(identity)
	return panel


func _build_stats_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "DecadeStats"
	panel.custom_minimum_size = Vector2(600, 228)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(C_BLUE, 0.44, 12))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(_section_title("DEKADENBILANZ"))

	var grid := GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	for raw_row: Variant in _gather_stats():
		var row := raw_row as Array
		var key := _label(str(row[0]).to_upper(), 10, C_DIM)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(key)
		var value := _label(str(row[1]), 11, C_GREEN)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
	column.add_child(grid)
	return panel


func _build_collection_finale() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CollectionFinale"
	panel.add_theme_stylebox_override("panel", _panel_style(C_AMBER, 0.46, 10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var top := HBoxContainer.new()
	var heading := _label("DAS FINALE DEINER SAMMLUNG", 14, C_AMBER)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var value := _label(
		"%d OVP-SÄTZE · ARCHIVWERT %s" % [
			DiskManager.boxed_collection().size(),
			Currency.format(DiskManager.collection_value())],
		11, C_GREEN)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(value)
	column.add_child(top)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	_collector_button = _button(Loc.t("ui.endgame_stats.behalten_sammler_highscore", "◆  BEHALTEN · SAMMLER-HIGHSCORE"), C_CYAN)
	_collector_button.name = "CollectorButton"
	_collector_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collector_button.pressed.connect(_submit_collector)
	action_row.add_child(_collector_button)
	_liquidate_button = _button(Loc.t("ui.endgame_stats.dm_alle_ovps_verkaufen_geld_highscore", "DM  ALLE OVPs VERKAUFEN · GELD-HIGHSCORE"), C_AMBER)
	_liquidate_button.name = "LiquidateButton"
	_liquidate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liquidate_button.pressed.connect(_submit_liquidator)
	action_row.add_child(_liquidate_button)
	column.add_child(action_row)

	_score_board = RichTextLabel.new()
	_score_board.name = "ScoreBoard"
	_score_board.bbcode_enabled = true
	_score_board.fit_content = true
	_score_board.custom_minimum_size.y = 42
	_score_board.add_theme_font_size_override("normal_font_size", 12)
	_score_board.add_theme_color_override("default_color", C_DIM)
	_score_board.text = Loc.t("ui.endgame_stats.center_bewerte_deinen_durchlauf_als_sammler", "[center]Bewerte deinen Durchlauf als Sammler – oder verwandle das Archiv ein letztes Mal in Geld.[/center]")
	column.add_child(_score_board)
	return panel


func _build_footer() -> Control:
	var footer := HBoxContainer.new()
	footer.name = "FinaleActions"
	footer.add_theme_constant_override("separation", 10)

	var hint := _label("DEIN SPIELSTAND BLEIBT ERHALTEN · DAS MUSEUM WÄCHST IM FREIEN SPIEL WEITER", 9, C_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)

	_museum_button = _button(Loc.t("ui.endgame_stats.retro_museum_betreten", "RETRO-MUSEUM BETRETEN"), C_CYAN)
	_museum_button.name = "MuseumButton"
	_museum_button.custom_minimum_size.x = 235
	_museum_button.pressed.connect(_enter_museum)
	footer.add_child(_museum_button)

	_credits_button = _button(Loc.t("ui.endgame_stats.produktionsabspann", "▶  PRODUKTIONSABSPANN"), C_AMBER)
	_credits_button.name = "CreditsButton"
	_credits_button.custom_minimum_size.x = 235
	_credits_button.pressed.connect(_open_credits)
	footer.add_child(_credits_button)

	_free_play_button = _button(Loc.t("ui.endgame_stats.weiterspielen_freies_spiel", "WEITERSPIELEN · FREIES SPIEL"), C_GREEN)
	_free_play_button.name = "FreePlayButton"
	_free_play_button.custom_minimum_size.x = 250
	_free_play_button.pressed.connect(queue_free)
	footer.add_child(_free_play_button)
	return footer


func _enter_museum() -> void:
	# Das Finale liegt in der Fensterebene. Erst am Frame-Ende freigeben, damit
	# prepare_location_change() nie ein halb gelöschtes Overlay vorfindet.
	queue_free()
	GameManager.call_deferred("goto_location", "retro_museum", false)


func _open_credits() -> void:
	var existing := get_node_or_null("GameCreditsScreen")
	if existing != null:
		existing.move_to_front()
		return
	var credits := CreditsScreen.new()
	credits.name = "GameCreditsScreen"
	add_child(credits)


func visual_contract() -> Dictionary:
	return {
		"period": [1990, 1999],
		"timeline_years": 10,
		"stats": _gather_stats().size(),
		"collection_decision": _collector_button != null and _liquidate_button != null,
		"museum_route": _museum_button != null,
		"credits_route": _credits_button != null,
		"free_play_route": _free_play_button != null,
		"effects": [&"copper_field", &"vector_lines", &"data_particles"],
	}


func _submit_collector() -> void:
	if _submitted:
		return
	_submitted = true
	var result := CollectionMarket.submit_highscore("collector")
	_show_scores(result, "SAMMLER")


func _submit_liquidator() -> void:
	if _submitted:
		return
	_submitted = true
	var sale := CollectionMarket.sell_all_boxed()
	var result := CollectionMarket.submit_highscore("liquidator")
	result["sale_text"] = sale.get("text", "Keine vollständigen OVP-Sätze verkauft.")
	_show_scores(result, "GELDSUMME")


func _show_scores(result: Dictionary, heading: String) -> void:
	_collector_button.disabled = true
	_liquidate_button.disabled = true
	var lines: Array[String] = []
	var rows: Array = result.get("rows", [])
	for index in mini(5, rows.size()):
		var row: Dictionary = rows[index]
		lines.append("%d. %s · %s" % [
			index + 1, str(row.get("name", "SPIELER")).to_upper(),
			Currency.format(int(row.get("score", 0)))])
	_score_board.text = Loc.t("ui.endgame_stats.center_color_f4c648_s_dein_score", "[center][color=#f4c648]%s · DEIN SCORE %s · RANG %d[/color]\n%s%s[/center]") % [
		heading, Currency.format(int(result.get("score", 0))), int(result.get("rank", 0)),
		(str(result.get("sale_text", "")) + "\n") if not str(result.get("sale_text", "")).is_empty() else "",
		"   ".join(lines)]


func _avatar_block(year: int, caption: String, note: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(150, 150)
	card.add_theme_stylebox_override("panel", _panel_style(
		C_AMBER if year == 1990 else C_GREEN, 0.34, 7))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	var portrait := TextureRect.new()
	portrait.texture = PlayerIdentity.texture({"year": year})
	portrait.custom_minimum_size = Vector2(104, 104)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(portrait)
	var caption_label := _label(caption, 11, C_WHITE)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption_label)
	var note_label := _label(note, 8, C_DIM)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note_label)
	return card


func _gather_stats() -> Array:
	var hardware_count := 0
	for key: Variant in PlayerStats.hardware:
		if PlayerStats.hardware[key] is bool and PlayerStats.hardware[key]:
			hardware_count += 1
	var friend_count := 0
	for npc_id: Variant in NPCManager.trust:
		if int(NPCManager.trust[npc_id]) >= 40:
			friend_count += 1
	var bbs_visits: Dictionary = BBSManager.get("_visited") as Dictionary
	return [
		["Erspartes", Currency.format(floori(PlayerStats.geld + BankManager.total()))],
		["Wissen", str(PlayerStats.wissen)],
		["Hardware", "%d Geräte" % hardware_count],
		["Disketten", "%d lose Medien" % DiskManager.media_count()],
		["Originalboxen", "%d Sätze · %s" % [
			DiskManager.boxed_collection().size(),
			Currency.format(DiskManager.collection_value())]],
		["MOD-Archiv", "%d Tracks" % MusicManager.owned.size()],
		["Mailboxen", "%d besucht" % bbs_visits.size()],
		["Eigene Releases", "%d Uploads" % SceneReleaseManager.uploads.size()],
		["Gute Freunde", str(friend_count)],
		["Erinnerungen", "%d Momente" % MemoryManager.memories.size()],
	]


func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 38)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 11)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.045, 0.055, 0.08, 0.98)
	normal.border_color = Color(accent, 0.52)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(7)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.98)
	hover.border_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.012, 0.016, 0.026, 1.0)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = C_WHITE
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.025, 0.028, 0.038, 0.92)
	disabled.border_color = Color(C_DIM, 0.24)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", C_WHITE)
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_focus_color", C_WHITE)
	button.add_theme_color_override("font_disabled_color", C_DIM)
	return button


func _panel_style(accent: Color, alpha: float, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = C_PANEL
	style.border_color = Color(accent, alpha)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0, 0, 0, 0.58)
	style.shadow_size = 10
	return style


func _section_title(text: String) -> Label:
	var label := _label("—  %s  —" % text, 14, C_AMBER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return label


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _rule(color: Color, alpha: float, height: int) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(color, alpha)
	rule.custom_minimum_size.y = height
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
