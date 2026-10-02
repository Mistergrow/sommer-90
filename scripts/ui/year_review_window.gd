class_name YearReviewWindow
extends RetroWindow
## Jahres-Rückblick von SOMMER '90: erscheint am Jahreswechsel und zeigt die
## Erinnerungen des vergangenen Jahres — Meilensteine (★) zuerst, dann der Alltag.
## Macht aus dem stillen Vergehen der Zeit ein Ereignis: „So war dein Jahr 19XX."
## Speist sich aus MemoryManager.memories_for_year(year).

var year: int = 1990


func _init() -> void:
	title = Loc.t("ui.year_review_window.ruckblick", "RÜCKBLICK")
	win_size = Vector2(540, 460)


func _ready() -> void:
	title = Loc.t("ui.year_review_window.ruckblick_d", "RÜCKBLICK · %d") % year
	super._ready()

	# Kopf: Avatar in dem Alter dieses Jahres + Überschrift
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	content.add_child(head)
	var av := TextureRect.new()
	av.texture = PlayerIdentity.texture({"year": year})
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	av.custom_minimum_size = Vector2(74, 74)
	head.add_child(av)
	var htext := VBoxContainer.new()
	htext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	htext.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	htext.add_theme_constant_override("separation", 2)
	head.add_child(htext)
	htext.add_child(_lbl("So war dein Jahr %d." % year, 17, Palette.LCD_AMBER))
	htext.add_child(_lbl("Du warst am Jahresende %d Jahre alt." \
		% PlayerIdentity.age_at_year_end(year), 11, Palette.UI_TEXT_DIM))

	# Erinnerungen des Jahres, Meilensteine zuerst
	var mems: Array = MemoryManager.memories_for_year(year)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)

	var milestones := 0
	if mems.is_empty():
		list.add_child(_lbl("Ein ruhiges Jahr — nichts Großes, aber du warst dabei.", 12, Palette.UI_TEXT_DIM))
	for m: Dictionary in mems:
		var month: int = clampi(int(m.get("month", 1)) - 1, 0, 11)
		var mn: String = TimeManager.localized_month_name(month + 1)
		if str(m.get("kind", "")) == "meilenstein":
			milestones += 1
			list.add_child(_milestone_row(mn, str(m.get("title", "Meilenstein")), str(m.get("text", ""))))
		else:
			list.add_child(_lbl("· %s: %s" % [mn, str(m.get("text", ""))], 12, Palette.UI_TEXT))

	# Fußzeile + Weiter
	content.add_child(_lbl("%d Meilenstein%s · %d Erinnerung%s in %d" % [
		milestones, "" if milestones == 1 else "e",
		mems.size(), "" if mems.size() == 1 else "en", year], 10, Palette.UI_TEXT_DIM))
	var btn := make_button(Loc.t("ui.year_review_window.weiter", "Weiter"), queue_free)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	content.add_child(btn)


## Meilenstein-Karte: ★ Titel (bernstein) + Text (gedimmt) auf leicht abgesetztem Panel.
func _milestone_row(month: String, mtitle: String, text: String) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(38, 33, 20)
	sb.border_color = Palette.LCD_AMBER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 5; sb.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	card.add_child(v)
	v.add_child(_lbl("★ %s  (%s)" % [mtitle, month], 13, Palette.LCD_AMBER))
	v.add_child(_lbl(text, 11, Palette.UI_TEXT))
	return v.get_parent()


func _lbl(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
