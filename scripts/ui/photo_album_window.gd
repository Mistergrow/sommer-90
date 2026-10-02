class_name PhotoAlbumWindow
extends RetroWindow
## FOTO-ALBUM / ERINNERUNGEN — die Schnappschüsse der Dekade als kleine Polaroids
## (Meilensteine + Erfolge werden automatisch geknipst, s. PhotoManager). Der
## Spieler kann jederzeit selbst „Moment knipsen": das Album blendet sich kurz aus,
## fängt den Bildschirm ein und zeigt sich wieder. Neueste Erinnerung zuerst.

const PHOTO_W := 176
const PHOTO_MANAGER_SCRIPT := preload("res://scripts/autoload/photo_manager.gd")


func _init() -> void:
	title = Loc.t("ui.photo_album_window.erinnerungen", "ERINNERUNGEN")
	win_size = Vector2(500, 540)


func _ready() -> void:
	super._ready()
	if not PhotoManager.photos_changed.is_connected(_rebuild):
		PhotoManager.photos_changed.connect(_rebuild)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_rebuild()


func _on_locale_changed(_locale: String) -> void:
	title = Loc.t("ui.photo_album_window.erinnerungen", "ERINNERUNGEN")
	_rebuild()


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var photo_count := PhotoManager.count()
	var count_text := Loc.t("ui.photo_album_window.one_memory", "%d Erinnerung im Album") % photo_count if photo_count == 1 else Loc.t("ui.photo_album_window.many_memories", "%d Erinnerungen im Album") % photo_count
	head.add_child(Bezel.lcd_label(count_text,
		Color(0.95, 0.85, 0.45), 14))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(make_button(Loc.t("ui.photo_album_window.moment_knipsen", "📷 Moment knipsen"), _snap))
	content.add_child(head)

	if PhotoManager.count() == 0:
		var empty := Bezel.dim_label(Loc.t("ui.photo_album_window.empty", "Noch keine Erinnerungen. Besondere Momente werden automatisch geknipst – oder halte selbst einen Moment fest."), 12)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(empty)
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	# Neueste zuerst.
	var list := PhotoManager.photos.duplicate()
	list.reverse()
	for p: Dictionary in list:
		grid.add_child(_polaroid(p))


## Ein Polaroid: weißer Rahmen, Foto oben, handschriftliche Unterschrift + Datum.
func _polaroid(p: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(232, 229, 219)           # Polaroid-Weiß
	sb.border_color = Color8(150, 146, 132)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 7; sb.content_margin_right = 7
	sb.content_margin_top = 7; sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 3; sb.shadow_offset = Vector2(1, 2)
	card.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	# Bildfläche (dunkel gerahmt) — echtes Thumbnail oder Platzhalter.
	var shot := PanelContainer.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color8(18, 20, 26)
	ss.set_border_width_all(0)
	shot.add_theme_stylebox_override("panel", ss)
	var tex := PHOTO_MANAGER_SCRIPT.decode(p)
	var ph := int(round(PHOTO_W * 0.62))
	if tex != null:
		var img_rect := TextureRect.new()
		img_rect.texture = tex
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img_rect.custom_minimum_size = Vector2(PHOTO_W, ph)
		shot.add_child(img_rect)
	else:
		var noimg := Label.new()
		noimg.text = "📷"
		noimg.custom_minimum_size = Vector2(PHOTO_W, ph)
		noimg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		noimg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		shot.add_child(noimg)
	col.add_child(shot)

	# Unterschrift (dunkel auf Polaroid-Weiß) + Datum.
	var cap := Label.new()
	var localized := _localized_photo_copy(p)
	cap.text = str(localized.get("title", ""))
	cap.add_theme_color_override("font_color", Color8(40, 38, 34))
	cap.add_theme_font_size_override("font_size", 13)
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.custom_minimum_size = Vector2(PHOTO_W, 0)
	col.add_child(cap)

	var sub := str(localized.get("caption", ""))
	var meta := Label.new()
	meta.text = ("%s · %s" % [str(p.get("date", "")), sub]) if sub != "" else str(p.get("date", ""))
	meta.add_theme_color_override("font_color", Color8(110, 104, 92))
	meta.add_theme_font_size_override("font_size", 12)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.custom_minimum_size = Vector2(PHOTO_W, 0)
	col.add_child(meta)
	return card


## Selbst knipsen: Album kurz ausblenden, damit das SPIEL im Bild ist, dann fangen.
func _snap() -> void:
	visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	PhotoManager.capture(Loc.t("ui.photo_album_window.snapshot_title", "Schnappschuss"), Loc.t("ui.photo_album_window.snapshot_caption", "selbst geknipst"), "", false)
	visible = true
	# _rebuild läuft ohnehin über das photos_changed-Signal.


func _localized_photo_copy(photo: Dictionary) -> Dictionary:
	var result := {
		"title": str(photo.get("title", "")),
		"caption": str(photo.get("caption", "")),
	}
	var photo_id := str(photo.get("id", ""))
	if photo_id.begins_with("ach_"):
		var achievement_id := photo_id.trim_prefix("ach_")
		var achievement := AchievementManager.def(achievement_id)
		result.title = "🏆 " + Loc.t("ach.%s.title" % achievement_id, str(achievement.get("title", result.title)))
		result.caption = Loc.t("ach.%s.desc" % achievement_id, str(achievement.get("desc", result.caption)))
	elif photo_id == "":
		# Alte manuelle Schnappschüsse wurden mit dem damaligen UI-Text gespeichert.
		# Beim Anzeigen werden die beiden kanonischen Texte dennoch live übersetzt.
		if str(result.title) in ["Schnappschuss", "Snapshot"]:
			result.title = Loc.t("ui.photo_album_window.snapshot_title", "Schnappschuss")
		if str(result.caption) in ["selbst geknipst", "taken by you"]:
			result.caption = Loc.t("ui.photo_album_window.snapshot_caption", "selbst geknipst")
	return result
