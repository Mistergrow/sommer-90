class_name HistoryShopWindow
extends RetroWindow
## Gemeinsames AAA-Schaufenster fuer Kiosk und Pommesbude: Sortiment ist nach
## Kategorie/Jahr sortiert und jedes Produkt besitzt ein echtes Asset. Im Imbiss
## steht die Bestellung im Vordergrund; historischer Kontext ist nur optional.
## Geld und Wirkung werden erst nach der gewaehlten Aktion verbucht.

const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")

var shop_id := "kiosk"
var category_filter := ""
var initial_item_id := ""

var _items: Array = []
var _selected: Dictionary = {}
var _detail: VBoxContainer = null


func _init() -> void:
	title = Loc.t("ui.history_shop_window.erinnerungsladen", "ERINNERUNGSLADEN")
	win_size = Vector2(760, 590)


func _ready() -> void:
	super._ready()
	var shop := HistoryShopCatalog.shop(shop_id)
	title = str(shop.get("title", title))
	# Die RetroWindow-Titelleiste ist bereits gebaut; Text dort nachziehen.
	var labels := find_children("*", "Label", true, false)
	if not labels.is_empty():
		(labels[0] as Label).text = title
	_items = HistoryShopCatalog.items_for(shop_id, TimeManager.year, category_filter)
	if not _items.is_empty():
		_selected = _items[0]
		if initial_item_id != "":
			for entry: Dictionary in _items:
				if str(entry.get("id", "")) == initial_item_id:
					_selected = entry
					break
	_build(shop)


func _build(shop: Dictionary) -> void:
	content.add_child(Bezel.lcd_label(Loc.t("ui.history_shop_window.zeitfenster_d_s", "ZEITFENSTER %d · %s") % [
		TimeManager.year, "KIOSK" if shop_id == "kiosk" else "IMBISS"],
		Color(0.98, 0.72, 0.24), 13))
	var intro := Bezel.dim_label(str(shop.get("intro", "")), 10)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	content.add_child(main)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	if _items.is_empty():
		list.add_child(Bezel.dim_label(Loc.t("ui.history_shop_window.in_diesem_jahr_ist_hier_nichts", "In diesem Jahr ist hier nichts einsortiert."), 11))
	else:
		var last_category := ""
		for entry: Dictionary in _items:
			var category := str(entry.get("category_name", "SORTIMENT"))
			if category != last_category:
				list.add_child(Bezel.lcd_label(category, Palette.UI_TEXT_DIM, 11))
				last_category = category
			var item_copy := entry
			var button := make_button(Loc.t("ui.history_shop_window.s_s", "%s\n%s") % [
				str(entry.get("name", "Ware")), Currency.format(float(entry.get("price", 0.0)))],
				func() -> void:
					_selected = item_copy
					_render_detail())
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(240, 48)
			list.add_child(button)

	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	main.add_child(_detail)
	_render_detail()


func _render_detail() -> void:
	if _detail == null:
		return
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if _selected.is_empty():
		return
	_detail.add_child(Bezel.lcd_label(str(_selected.get("name", "WARE")),
		Color(1.0, 0.78, 0.28), 16))
	_detail.add_child(_asset_preview(_selected))
	if shop_id != "imbiss":
		_detail.add_child(Bezel.dim_label(HistoryShopCatalog.period_text(_selected), 10))

	var optional_context := bool(_selected.get("context_optional", false))
	var description := str(_selected.get("menu_text",
		"" if optional_context else _selected.get("museum_note", "")))
	var note := Bezel.dim_label(description, 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(note)
	var after := str(_selected.get("after_timeline", ""))
	if after != "" and not optional_context:
		var future := Bezel.dim_label(Loc.t("ui.history_shop_window.museumsnotiz", "MUSEUMSNOTIZ: ") + after, 10)
		future.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		future.add_theme_color_override("font_color", Color(0.58, 0.82, 1.0))
		_detail.add_child(future)
	if optional_context:
		var context_def := _selected
		var context := make_button(Loc.t("ui.history_shop_window.optional_sprachhinweis", "OPTIONAL: SPRACHHINWEIS"), func() -> void:
			_show_optional_context(context_def))
		_detail.add_child(context)

	var price := float(_selected.get("price", 0.0))
	_detail.add_child(Bezel.lcd_label(Loc.t("ui.history_shop_window.s_d_energie", "%s · +%d Energie") % [
		Currency.format(price), int(_selected.get("energy", 0))], Palette.UI_TEXT, 12))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_detail.add_child(actions)
	if bool(_selected.get("can_eat_here", false)):
		var eat_text := "HIER TRINKEN" if str(_selected.get("category", "")) == "getraenk" else "HIER ESSEN"
		var eat_def := _selected
		var eat := make_button(eat_text, func() -> void: _purchase(eat_def, false))
		eat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(eat)
	if bool(_selected.get("can_take_away", false)):
		var take_def := _selected
		var take := make_button(Loc.t("ui.history_shop_window.mitnehmen", "MITNEHMEN"), func() -> void: _purchase(take_def, true))
		take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(take)


func _asset_preview(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 205)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(15, 17, 22)
	sb.border_color = Color8(82, 76, 62)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	for key in ["asset", "secondary_asset"]:
		var path := str(entry.get(key, ""))
		if path == "" or not RuntimeImages.exists(path):
			continue
		var texture := RuntimeImages.texture(path, 1024)
		if texture == null:
			continue
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		image.custom_minimum_size = Vector2(185 if entry.has("secondary_asset") else 380, 195)
		row.add_child(image)
	return panel


func _purchase(entry: Dictionary, take_away: bool) -> void:
	var price := float(entry.get("price", 0.0))
	if not PlayerStats.spend_money(price):
		AudioManager.play("error", 0.0)
		UIManager.toast(Loc.t("ui.history_shop_window.dafuer_reicht_dein_kleingeld_nicht_s", "Dafuer reicht dein Kleingeld nicht (%s).") % Currency.format(price))
		return
	AudioManager.play("cash_register", 0.0)
	var product_name := str(entry.get("name", "Ware"))
	if take_away:
		InventoryManager.add_item(str(entry.get("item_id", entry.get("id", ""))), 1)
		UIManager.toast(Loc.t("ui.history_shop_window.s_gekauft_s_eingepackt_im_inventar", "%s gekauft (%s) — eingepackt. Im Inventar kannst du es spaeter verzehren.") % [
			product_name, Currency.format(price)])
	else:
		PlayerStats.change_stat("energie", int(entry.get("energy", 0)))
		var relief := InventoryManager.food_hunger_relief(str(entry.get("item_id", entry.get("id", ""))))
		PlayerStats.change_stat("hunger", -relief)
		AudioManager.play("bag", 0.0)
		UIManager.toast(Loc.t("ui.history_shop_window.s_hier_gegessen_getrunken_d_energie", "%s — hier gegessen/getrunken (+%d Energie · −%d Hunger). Die Verpackung landet im Eimer.") % [
			product_name, int(entry.get("energy", 0)), relief])
	GameManager.flags["history_shop_last"] = {
		"shop": shop_id, "item": str(entry.get("id", "")), "year": TimeManager.year,
		"take_away": take_away}
	MemoryManager.record("alltag", "%s im %s gekauft (%s)" % [
		product_name, "Kiosk" if shop_id == "kiosk" else "Pommes-Palast",
		"mitgenommen" if take_away else "vor Ort"])


func _show_optional_context(entry: Dictionary) -> void:
	var text := str(entry.get("museum_note", ""))
	var after := str(entry.get("after_timeline", ""))
	if after != "":
		text += "\n\nHeute: " + after
	UIManager.open_info("SPRACHHINWEIS · OPTIONAL", text,
		str(entry.get("secondary_asset", entry.get("asset", ""))))
