class_name CopyTutorialWindow
extends RetroWindow
## Diegetische Bruecke zwischen Flohmarkt-Fund und Stefans Uebergabe:
## Farbcodierter, persistenter Drei-Schritt-Plan statt eines fluechtigen Toasts.

var phase := "acquired"  # acquired | complete


func _init() -> void:
	title = Loc.t("ui.copy_tutorial_window.tutorial_masterdisk_sichern", "TUTORIAL · MASTERDISK SICHERN")
	win_size = Vector2(760, 420)


func _ready() -> void:
	super._ready()
	_build_header()
	_build_flow()
	_build_status()
	_build_actions()


func _build_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var step := Bezel.lcd_label(Loc.t("ui.copy_tutorial_window.schritt_s_3", "SCHRITT %s/3") % ("3" if phase == "complete" else "2"),
		Palette.LCD_GREEN if phase == "complete" else Palette.LCD_AMBER, 15)
	row.add_child(step)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(Bezel.lcd_label(
		Loc.t("ui.copy_tutorial_window.kopie_fertig_jetzt_zu_stefan", "KOPIE FERTIG · JETZT ZU STEFAN") if phase == "complete" else
		"FUND GESICHERT · JETZT KOPIEREN", Palette.UI_TEXT, 14))
	var sub := Bezel.dim_label(
		Loc.t("ui.copy_tutorial_window.stefan_bekommt_folgegeneration_deine_quelle_bleibt", "Stefan bekommt die Folgegeneration. Deine Quelle bleibt jederzeit erhalten.") if phase == "complete" else
		"Die rote Disk ist deine einzige Quelle. Gib sie niemals aus der Hand.", 10)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(sub)
	row.add_child(copy)
	content.add_child(row)


func _build_flow() -> void:
	var shell := PanelContainer.new()
	shell.name = "CopyTutorialFlow"
	shell.custom_minimum_size.y = 235
	shell.add_theme_stylebox_override("panel", _style(Color("0b0e12"), Color("58616a"), 2, 7, 12))
	content.add_child(shell)
	var flow := HBoxContainer.new()
	flow.alignment = BoxContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("separation", 13)
	shell.add_child(flow)
	flow.add_child(_disk_card("MasterCard", "1 · QUELLE", "ROT · MASTER",
		"BLEIBT BEI DIR", "red", true))
	flow.add_child(_arrow("LESEN"))
	flow.add_child(_xcopy_card())
	flow.add_child(_arrow("SCHREIBEN"))
	flow.add_child(_disk_card("CopyCard", "3 · ZIEL", "BLAU · KOPIE",
		"→ ZU STEFAN" if phase == "complete" else "LEERDISKETTE", "blue", false))


func _disk_card(node_name: String, kicker: String, headline: String, footer: String,
		color_name: String, printed: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.custom_minimum_size = Vector2(170, 205)
	var accent := Palette.disk_color(color_name)
	panel.add_theme_stylebox_override("panel", _style(Color("15181d"), accent, 2, 6, 9))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var top := Bezel.dim_label(kicker, 11)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(top)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(145, 125)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.texture = DiskComposer.composed_disk("space_lemming_trouble", printed, 180, 1, color_name)
	if art.texture == null:
		art.texture = Sprites.disk_icon(accent)
	col.add_child(art)
	var head := Bezel.lcd_label(headline, accent.lightened(0.2), 11)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var foot := Bezel.dim_label(footer, 11)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)
	return panel


func _xcopy_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "XCopyCard"
	panel.custom_minimum_size = Vector2(150, 150)
	panel.add_theme_stylebox_override("panel", _style(Color("16121d"), Palette.WB_ORANGE, 2, 5, 10))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)
	var step := Bezel.dim_label(Loc.t("ui.copy_tutorial_window.2_werkzeug", "2 · WERKZEUG"), 11)
	step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(step)
	var logo := Bezel.lcd_label(Loc.t("ui.copy_tutorial_window.x_copy", "X-COPY"), Palette.LCD_AMBER, 22)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(logo)
	for line in ["QUELLE: ROT", "ZIEL: BLAU", "VERIFY: OK"]:
		var label := Bezel.lcd_label(line, Palette.LCD_GREEN, 11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(label)
	return panel


func _arrow(caption: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var arrow := Bezel.lcd_label(Loc.t("ui.copy_tutorial_window.text", "▶"), Palette.LCD_AMBER, 25)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(arrow)
	var label := Bezel.dim_label(caption, 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)
	return col


func _build_status() -> void:
	var master_ok := DiskManager.media_disks().any(func(d: Disk) -> bool:
		return d.software_id == "space_lemming_trouble" and d.is_game_master() and d.condition > 0)
	var xcopy_ok := DiskManager.media_disks().any(func(d: Disk) -> bool: return d.program_id == "xcopy" and d.condition > 0)
	var blanks := DiskManager.blank_disks().size()
	var copy_ok := DiskManager.has_player_copy_of("space_lemming_trouble")
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("111a17"),
		Palette.GREEN_DARK if (copy_ok or (master_ok and xcopy_ok and blanks > 0)) else Palette.RED_DARK,
		1, 5, 8))
	content.add_child(panel)
	var status := Label.new()
	status.name = "TutorialStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 11)
	status.text = (Loc.t("ui.copy_tutorial.complete",
		"✓ Kopie erkannt  ·  ✓ rote Masterdisk bewahrt\nNächstes Ziel: Stefan in seinem Zimmer die BLAUE KOPIE geben.")
		if phase == "complete" else
		Loc.t("ui.copy_tutorial.instructions",
			"%s Rote Masterdisk   %s X-COPY   %s Blaue Leerdiskette (%d vorhanden)\nZuhause: Amiga starten → X-COPY-Disk booten → START → Quelle ROT → Ziel BLAU.") % [
		"✓" if master_ok else "✗", "✓" if xcopy_ok else "✗", "✓" if blanks > 0 else "✗", blanks])
	panel.add_child(status)


func _build_actions() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	var notes := make_button(Loc.t("ui.copy_tutorial.note", "IM NOTIZBLOCK MERKEN"), func() -> void:
		queue_free()
		UIManager.open_tasks())
	row.add_child(notes)
	if phase == "complete":
		row.add_child(make_button(Loc.t("ui.copy_tutorial.stefan_on_map",
			"STEFAN AUF DER KARTE"), func() -> void:
			queue_free()
			UIManager.open_map()))
	else:
		row.add_child(make_button(Loc.t("ui.copy_tutorial.understood",
			"VERSTANDEN · MASTER BLEIBT"), queue_free))
	content.add_child(row)


func _style(bg: Color, border: Color, width: int, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
