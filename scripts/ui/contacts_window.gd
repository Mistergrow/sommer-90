extends RetroWindow
## KONTAKTE-Fenster: alle bekannten NPCs mit Rolle, Ort und Vertrauen.
## Das Kontakt-Netzwerk ist eine der Kern-Ressourcen der Szene.


const PORTRAIT := 56


func _init() -> void:
	title = Loc.t("ui.contacts_window.kontakte", "KONTAKTE")
	win_size = Vector2(470, 360)
	chrome_accent = Palette.CYAN


func _ready() -> void:
	super._ready()
	# Scrollbereich → beliebig viele Kontakte bleiben im Fenster.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for id in NPCManager.npcs:
		if not NPCManager.is_available(id):
			continue
		list.add_child(_contact_card(id, NPCManager.npcs[id]))

	# Anrufbeantworter-Zugang (zeigt neue Nachrichten an).
	var n := PhoneManager.unheard_count()
	var tam := make_button(
		Loc.t("ui.contacts_window.anrufbeantworter", "☏ Anrufbeantworter") + (
			Loc.t("ui.contacts_window.new_count", " · %d neu") % n if n > 0 else ""),
		UIManager.open_answering_machine)
	content.add_child(tam)

	content.add_child(Bezel.dim_label(
		Loc.t("ui.contacts_window.weitere_kontakte_findest_du_im_club", "Weitere Kontakte findest du im Club, in Mailboxen und bei Demoscene-Treffen."), 9))


## Eine Kontakt-Karte: gerahmtes Porträt (feste Größe) + Name/Rolle + Vertrauen.
func _contact_card(id: String, npc: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(30, 30, 34)
	sb.border_color = Palette.UI_BORDER_DARK
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	# Porträt in festem, gerahmtem Rahmen — Bild wird NICHT nativ groß.
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color8(16, 16, 18)
	fs.border_color = Palette.UI_BORDER_DARK
	fs.set_border_width_all(1)
	fs.set_corner_radius_all(2)
	frame.add_theme_stylebox_override("panel", fs)
	var portrait := TextureRect.new()
	portrait.texture = NPCManager.portrait(id)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # feste Größe erzwingen
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	frame.add_child(portrait)
	row.add_child(frame)

	# Name + Rolle · Ort
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.add_child(Bezel.lcd_label(str(npc.get("name", "?")), Palette.UI_TEXT, 15))
	var localized_role := Loc.t("npc.%s.role" % str(npc.get("id", "")), str(npc.get("role", "")))
	col.add_child(Bezel.dim_label(Loc.t("ui.contacts_window.s_s", "%s · %s") % [localized_role,
		GameManager.location_name(npc.get("location", ""))], 10))
	# Rufnummer (Notizbuch) — nach einem Umzug steht die Vorwahl mit dabei.
	var number := PhoneManager.display_number(id)
	if number != "":
		col.add_child(Bezel.dim_label(Loc.t("ui.contacts_window.s", "☏ %s") % number, 12))
	row.add_child(col)

	# Vertrauen rechtsbündig
	var trust_col := VBoxContainer.new()
	trust_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trust_col.add_theme_constant_override("separation", 2)
	trust_col.add_child(Bezel.dim_label(Loc.t("ui.contacts_window.vertrauen", "Vertrauen"), 11))
	var bar := Bezel.bar(Palette.LCD_CYAN, Vector2(96, 10))
	bar.value = NPCManager.get_trust(id)
	trust_col.add_child(bar)
	row.add_child(trust_col)

	return card
