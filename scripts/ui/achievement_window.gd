class_name AchievementWindow
extends RetroWindow
## ERFOLGE — Steam-Erfolge-Übersicht. Zeigt jeden Erfolg mit Icon (256×256-PNG,
## sobald in assets/ui/achievements/ vorhanden), Titel, Beschreibung und Status.
## Gesperrte Erfolge: graues Platzhalter-/_locked-Icon + gedimmter Text.

const ICON_DIR := "res://assets/ui/achievements"
const ICON := 40


func _init() -> void:
	title = Loc.t("ui.achievement_window.erfolge", "ERFOLGE")
	win_size = Vector2(480, 460)


func _ready() -> void:
	super._ready()
	if not AchievementManager.achievements_changed.is_connected(_rebuild):
		AchievementManager.achievements_changed.connect(_rebuild)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_rebuild()


func _on_locale_changed(_locale: String) -> void:
	title = Loc.t("ui.achievement_window.erfolge", "ERFOLGE")
	_rebuild()


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()
	content.add_child(Bezel.lcd_label(Loc.t("ui.achievement_window.d_d_freigeschaltet", "%d / %d freigeschaltet") %
		[AchievementManager.unlocked_count(), AchievementManager.total()],
		Color(0.95, 0.8, 0.3), 15))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)

	for a: Dictionary in AchievementManager.all():
		list.add_child(_row(a))


func _row(a: Dictionary) -> Control:
	var id := str(a.get("id", ""))
	var got := AchievementManager.is_unlocked(id)

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(30, 30, 34) if got else Color8(22, 22, 26)
	sb.border_color = Color8(210, 170, 70) if got else Palette.UI_BORDER_DARK
	sb.set_border_width_all(1)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 5; sb.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	# Icon: echtes PNG, sonst Platzhalter (Pokal / graues Schloss)
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color8(16, 16, 18)
	fs.border_color = Palette.UI_BORDER_DARK
	fs.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", fs)
	var icon_path := "%s/%s%s.png" % [ICON_DIR, id, "" if got else "_locked"]
	var locked_fallback := false
	# Künftige Erfolge bleiben auch dann lesbar, wenn ihre Locked-Variante beim
	# Import noch fehlt: zunächst dieselbe Silhouette gedimmt zeigen, erst bei
	# komplett fehlendem Artwork auf das Unicode-Schloss zurückfallen.
	if not got and not ResourceLoader.exists(icon_path):
		var unlocked_path := "%s/%s.png" % [ICON_DIR, id]
		if ResourceLoader.exists(unlocked_path):
			icon_path = unlocked_path
			locked_fallback = true
	if ResourceLoader.exists(icon_path):
		var tex := TextureRect.new()
		tex.texture = load(icon_path)
		if locked_fallback:
			tex.modulate = Color(0.46, 0.48, 0.52, 1.0)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # 256px-Icon auf ICON begrenzen
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(ICON, ICON)
		frame.add_child(tex)
	else:
		var ph := Label.new()
		ph.text = "🏆" if got else "🔒"
		ph.custom_minimum_size = Vector2(ICON, ICON)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(ph)
	row.add_child(frame)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(Bezel.lcd_label(Loc.t("ach.%s.title" % id, str(a.get("title", "?"))),
		Color(0.95, 0.82, 0.35) if got else Color(0.5, 0.52, 0.56), 13))
	# Gesperrte: Beschreibung als Hinweis; freigeschaltet: als Erfolg.
	col.add_child(Bezel.dim_label(Loc.t("ach.%s.desc" % id, str(a.get("desc", ""))), 10))
	row.add_child(col)
	return card
