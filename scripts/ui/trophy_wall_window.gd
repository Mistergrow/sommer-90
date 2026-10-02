class_name TrophyWallWindow
extends RetroWindow
## POSTER-/TROPHÄENWAND — die Wand im Zimmer, die mit dem Spieler WÄCHST: jede
## freigeschaltete Trophäe (Erfolg) hängt als gerahmtes Icon, jeder erlebte
## Meilenstein als angepinnte Notiz mit Datum. Zeigt auf einen Blick, was man
## geschafft und erlebt hat (füttert später das begehbare 1999-Museum). Zugang:
## Hotspot an der Zimmerwand.

const ICON_DIR := "res://assets/ui/achievements"
const TROPHY := 46


func _init() -> void:
	title = Loc.t("ui.trophy_wall_window.deine_wand", "DEINE WAND")
	win_size = Vector2(540, 560)


func _ready() -> void:
	super._ready()
	if not AchievementManager.achievements_changed.is_connected(_rebuild):
		AchievementManager.achievements_changed.connect(_rebuild)
	var mm := get_node_or_null("/root/MemoryManager")
	if mm != null and mm.has_signal("memory_recorded") \
			and not mm.memory_recorded.is_connected(_on_memory):
		mm.memory_recorded.connect(_on_memory)
	_rebuild()


func _on_memory(_m: Dictionary) -> void:
	_rebuild()


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()

	var got := AchievementManager.unlocked_count()
	var tot := AchievementManager.total()
	var head := Bezel.lcd_label(Loc.t("ui.trophy_wall_window.d_d_trophaen_ruf_d", "🏆 %d/%d Trophäen   ·   Ruf %d") %
		[got, tot, int(PlayerStats.ruf)], Color(0.95, 0.82, 0.35), 15)
	content.add_child(head)
	if TimeManager.year >= 1999:
		var museum := make_button(Loc.t("ui.trophy_wall_window.dein_retro_museum_betreten", "DEIN RETRO-MUSEUM BETRETEN"), func() -> void:
			queue_free()
			GameManager.call_deferred("goto_location", "retro_museum", false))
		museum.name = "MuseumEntryButton"
		museum.custom_minimum_size.y = 36
		museum.tooltip_text = Loc.t("ui.trophy_wall_window.deine_sammlung_hardware_erinnerungen_als_begehbare", "Deine Sammlung, Hardware und Erinnerungen als begehbare Ausstellung.")
		content.add_child(museum)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	# --- Trophäen (Erfolge): erledigte zuerst, gesperrte als leere Rahmen ---
	col.add_child(_section("ERRUNGENSCHAFTEN"))
	if tot == 0:
		col.add_child(Bezel.dim_label(Loc.t("ui.trophy_wall_window.noch_keine_erfolge_definiert", "Noch keine Erfolge definiert."), 11))
	else:
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		var list := AchievementManager.all().duplicate()
		var definition_order := {}
		for index in list.size():
			definition_order[str(list[index].get("id", ""))] = index
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ua := AchievementManager.is_unlocked(str(a.get("id", "")))
			var ub := AchievementManager.is_unlocked(str(b.get("id", "")))
			if ua != ub:
				return ua and not ub
			return int(definition_order.get(str(a.get("id", "")), 0)) \
				< int(definition_order.get(str(b.get("id", "")), 0)))
		for a: Dictionary in list:
			grid.add_child(_trophy(a))
		col.add_child(grid)

	# --- Erinnerungen (Meilensteine) als angepinnte Notizen ---
	col.add_child(_section("ERINNERUNGEN AN DER WAND"))
	var notes := _milestones()
	if notes.is_empty():
		col.add_child(Bezel.dim_label(
			Loc.t("ui.trophy_wall_window.noch_nichts_angepinnt_besondere_momente_meilensteine", "Noch nichts angepinnt. Besondere Momente (Meilensteine) landen automatisch hier."), 11))
	else:
		for m: Dictionary in notes:
			col.add_child(_poster(m))


func _section(text: String) -> Control:
	var l := Bezel.lcd_label(text, Color(0.55, 0.75, 0.95), 12)
	l.add_theme_constant_override("margin_top", 6)
	return l


## Ein gerahmtes Trophäen-Icon (freigeschaltet farbig + Goldrahmen, sonst dunkel/🔒).
func _trophy(a: Dictionary) -> Control:
	var id := str(a.get("id", ""))
	var got := AchievementManager.is_unlocked(id)
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(28, 24, 16) if got else Color8(18, 18, 20)
	sb.border_color = Color8(210, 170, 70) if got else Palette.UI_BORDER_DARK
	sb.set_border_width_all(2 if got else 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3; sb.content_margin_right = 3
	sb.content_margin_top = 3; sb.content_margin_bottom = 3
	frame.add_theme_stylebox_override("panel", sb)
	frame.tooltip_text = Loc.t("ui.trophy_wall_window.s_s", "%s — %s") % [str(a.get("title", "?")), str(a.get("desc", ""))]

	var icon_path := "%s/%s%s.png" % [ICON_DIR, id, "" if got else "_locked"]
	var locked_fallback := false
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
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # nicht die 256px-Textur als Mindestmaß
		tex.custom_minimum_size = Vector2(TROPHY, TROPHY)
		frame.add_child(tex)
	else:
		var ph := Label.new()
		ph.text = "🏆" if got else "🔒"
		ph.custom_minimum_size = Vector2(TROPHY, TROPHY)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(ph)
	return frame


## Eine angepinnte Erinnerungs-Notiz (Zettel-Optik) mit Titel + Datum.
func _poster(m: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(228, 224, 206)          # Notizzettel
	sb.border_color = Color8(150, 146, 128)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 9; sb.content_margin_right = 9
	sb.content_margin_top = 5; sb.content_margin_bottom = 5
	sb.shadow_color = Color(0, 0, 0, 0.28); sb.shadow_size = 2; sb.shadow_offset = Vector2(1, 1)
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var pin := Label.new()
	pin.text = "📌"
	row.add_child(pin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	var title_label := Label.new()
	title_label.text = str(m.get("title", m.get("text", "Erinnerung")))
	title_label.add_theme_color_override("font_color", Color8(40, 38, 30))
	title_label.add_theme_font_size_override("font_size", 13)
	box.add_child(title_label)
	var date := Label.new()
	date.text = Loc.t("ui.trophy_wall_window.d_d_d", "%d.%d.%d") % [int(m.get("day", 1)), int(m.get("month", 1)), int(m.get("year", 1990))]
	date.add_theme_color_override("font_color", Color8(110, 104, 88))
	date.add_theme_font_size_override("font_size", 12)
	box.add_child(date)
	row.add_child(box)
	return card


## Meilenstein-Erinnerungen (neueste zuerst).
func _milestones() -> Array:
	var mm := get_node_or_null("/root/MemoryManager")
	if mm == null:
		return []
	var out: Array = []
	for m in mm.get("memories"):
		if str(m.get("kind", "")) == "meilenstein":
			out.append(m)
	out.reverse()
	return out
