class_name PostcardWindow
extends RetroWindow
## POSTKASTEN — Postkarten von weggezogenen Freunden lesen und BEANTWORTEN.
## Sven schreibt ab seinem Wegzug 1995; jede Antwort schaltet die naechste Karte
## des Fadens frei. Post kommt immer an (kein Geraet noetig, anders als der AB).

const PAPER := Color8(238, 230, 208)      # vergilbtes Postkarten-Papier
const INK := Color8(40, 46, 74)           # Kugelschreiber-Blau


func _init() -> void:
	title = Loc.t("ui.postcard_window.postkasten", "POSTKASTEN")
	win_size = Vector2(460, 430)
	chrome_accent = Palette.ORANGE


func _ready() -> void:
	super._ready()
	AudioManager.play("paper")
	if not PostcardManager.postcards_changed.is_connected(_rebuild):
		PostcardManager.postcards_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()

	if PostcardManager.inbox.is_empty():
		content.add_child(Bezel.dim_label(
			Loc.t("ui.postcard_window.postkasten_ist_leer_wer_wegzieht_meldet", "Der Postkasten ist leer.\n\nWer wegzieht, meldet sich per Post — dann liegt hier eine Postkarte, die du lesen und beantworten kannst."), 12))
		return

	var n := PostcardManager.unread_count()
	content.add_child(Bezel.lcd_label(
		(Loc.t_plural("ui.postcard_window.unread_cards", "%d ungelesene Postkarte",
			"%d ungelesene Postkarten", n) if n > 0 else
		Loc.t("ui.postcard_window.all_read", "Alle Postkarten gelesen")),
		Color(0.4, 1.0, 0.5) if n > 0 else Palette.UI_TEXT, 14))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	content.add_child(scroll)

	# Neueste zuerst.
	var cards: Array = []
	for card: Dictionary in PostcardManager.inbox:
		cards.append(PostcardManager.localized_card(card))
	cards.reverse()
	for m: Dictionary in cards:
		list.add_child(_postcard(m))


func _postcard(m: Dictionary) -> Control:
	var id := str(m.get("id", ""))
	var read: bool = bool(m.get("read", false))

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color8(150, 120, 70) if read else Color8(200, 70, 60)
	sb.set_border_width_all(2 if not read else 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 9; sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	# Kopf: Poststempel-Zeile (Absender · Motiv · Datum)
	var head := HBoxContainer.new()
	var stamp := Label.new()
	stamp.text = "✉"
	stamp.add_theme_color_override("font_color", INK)
	head.add_child(stamp)
	var from_l := Label.new()
	from_l.text = Loc.t("ui.postcard_window.von_s", "  Von %s") % str(m.get("from_name", "?"))
	from_l.add_theme_color_override("font_color", INK)
	from_l.add_theme_font_size_override("font_size", 14)
	head.add_child(from_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var date_l := Label.new()
	date_l.text = str(m.get("date", ""))
	date_l.add_theme_color_override("font_color", Color8(110, 95, 60))
	date_l.add_theme_font_size_override("font_size", 12)
	head.add_child(date_l)
	box.add_child(head)

	if str(m.get("motiv", "")) != "":
		var motiv := Label.new()
		motiv.text = Loc.t("ui.postcard_window.s", "[ %s ]") % str(m.get("motiv", ""))
		motiv.add_theme_color_override("font_color", Color8(120, 100, 65))
		motiv.add_theme_font_size_override("font_size", 12)
		box.add_child(motiv)

	var sep := HSeparator.new()
	box.add_child(sep)

	# Handschriftlicher Text auf dem Papier.
	var body := Label.new()
	body.text = str(m.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", INK)
	body.add_theme_font_size_override("font_size", 13)
	box.add_child(body)

	# Ungelesen → als gelesen markieren (Klick reicht) + Antwortmoeglichkeiten.
	if not read:
		box.add_child(make_button(Loc.t("ui.postcard_window.gelesen", "Gelesen"), func() -> void: PostcardManager.mark_read(id)))

	var replies: Array = m.get("replies", [])
	if PostcardManager.has_replied(id):
		var answered := Label.new()
		answered.text = Loc.t("ui.postcard_window.deine_antwort_s", "↳ Deine Antwort: %s") % PostcardManager.reply_text(id)
		answered.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		answered.add_theme_color_override("font_color", Color8(90, 110, 80))
		answered.add_theme_font_size_override("font_size", 11)
		box.add_child(answered)
	elif not replies.is_empty():
		box.add_child(Bezel.dim_label(Loc.t("ui.postcard_window.antworten", "Antworten:"), 10))
		for rep: Dictionary in replies:
				var rid := str(rep.get("id", ""))
				var rtext := str(rep.get("text", ""))
				box.add_child(make_button(Loc.t("ui.postcard_window.text", "✎ ") + rtext, func() -> void:
					if PostcardManager.reply(id, rid):
						UIManager.toast(Loc.t("ui.postcard_window.postkarte_an_s_abgeschickt", "Postkarte an %s abgeschickt.") % str(m.get("from_name", "?")))))

	return card
