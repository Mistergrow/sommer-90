extends RetroWindow
## Grubers Computerladen: Regal und Bestellkatalog als lesbarer Produktbrowser.
## Preise, Waren und Bestelllogik bleiben in ShopManager/OrderManager; die UI
## zeigt Box-Art bzw. vorhandene Hardware-Master-Assets in einer Detailansicht.

const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const BoxComposer := preload("res://scripts/gfx/software_box_composer.gd")
const ShopEra := preload("res://scripts/data/computer_shop_era.gd")
const GAME_PAGE_SIZE := 24
const CATALOG_THUMB_SIZE := 96

var start_mode := "stock"
var _mode := "stock"
var _list: ItemList
var _money: Label
var _action: Button
var _tab_stock: Button
var _tab_catalog: Button
var _detail_title: Label
var _detail_meta: Label
var _detail_desc: RichTextLabel
var _preview: TextureRect
var _preview_mark: Label
var _rows: Array = []
var _catalog_search: LineEdit
var _catalog_page_label: Label
var _catalog_prev: Button
var _catalog_next: Button
var _catalog_tools: PanelContainer
var _browser_heading: Label
var _browser_status: Label
var _game_page := 0
var _catalog_game_total := 0
var _catalog_ids: Array = []
var _catalog_search_index: Dictionary = {}
var _catalog_filter_cache: Dictionary = {}
var _catalog_index_year := -1
var _thumbnail_jobs: Array[Dictionary] = []
var _thumbnail_drain_running := false
var _refresh_generation := 0
var _detail_generation := 0
var _select_first_catalog_game := false


func _init() -> void:
	title = Loc.t("ui.shop_window.s_regal_bestellservice", "%s · REGAL & BESTELLSERVICE") % ShopEra.business_name()
	win_size = Vector2(1180, 700)
	chrome_accent = Palette.LCD_AMBER


func _ready() -> void:
	super._ready()
	_mode = start_mode
	ShopManager.shop_changed.connect(_refresh)
	OrderManager.orders_changed.connect(_refresh)
	PlayerStats.stats_changed.connect(_on_money_changed)
	_build_header()
	_build_tabs()
	_build_catalog_tools()
	_build_browser()
	_refresh()


func _build_header() -> void:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _style(Color("10151c"), Color("3d4b5e"), 1, 7))
	content.add_child(header)
	var margin := MarginContainer.new()
	_margins(margin, 10, 7)
	header.add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(Bezel.lcd_label(ShopEra.business_name(), Palette.LCD_AMBER, 11))
	var quote := Bezel.dim_label(Loc.t("ui.shop_window.regalware_sofort_katalogware_verbindlich_bestellen_abholung", "Regalware sofort · Katalogware verbindlich bestellen · Abholung nach Lieferung"), 11)
	quote.modulate = Color(0.76, 0.81, 0.88)
	copy.add_child(quote)
	_money = Bezel.lcd_label("", Palette.LCD_GREEN, 13)
	_money.custom_minimum_size.x = 220
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_money)


func _build_tabs() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	_tab_stock = make_button(Loc.t("ui.shop_window.im_regal", "IM REGAL"), func() -> void: _set_mode("stock"))
	_tab_catalog = make_button(Loc.t("ui.shop_window.bestellkatalog", "BESTELLKATALOG"), func() -> void: _set_mode("catalog"))
	var upgrade := make_button(Loc.t("ui.shop_window.hardware_ausbau", "HARDWARE-AUSBAU"), func() -> void: UIManager.open_upgrade_tree())
	# Keine Font-Symbole als vermeintliche Icons: die historische Schrift besitzt
	# deren Glyphen nicht zuverlässig und zeigte im Laden deshalb #/@/Kästchen.
	# Echte indizierte Spielgrafik bleibt bei jeder Sprache und Auflösung stabil.
	_decorate_tab(_tab_stock, Sprites.ui_icon("inventory"))
	_decorate_tab(_tab_catalog, Sprites.disk_icon(Palette.BLUE_MID))
	_decorate_tab(upgrade, Sprites.ui_icon("options"))
	_tab_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(_tab_stock)
	tabs.add_child(_tab_catalog)
	tabs.add_child(upgrade)
	content.add_child(tabs)


func _build_catalog_tools() -> void:
	_catalog_tools = PanelContainer.new()
	_catalog_tools.add_theme_stylebox_override("panel", _style(Color("090d12"), Color("35637a"), 1, 4))
	content.add_child(_catalog_tools)
	var margin := MarginContainer.new()
	_margins(margin, 7, 5)
	_catalog_tools.add_child(margin)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	margin.add_child(bar)
	var register := Bezel.lcd_label(Loc.t("ui.shop_window.katalogindex", "KATALOGINDEX"), Palette.LCD_CYAN, 11)
	register.custom_minimum_size.x = 142
	register.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(register)
	_catalog_search = LineEdit.new()
	_catalog_search.placeholder_text = Loc.t("ui.shop_window.spiel_im_bestellkatalog_suchen",
		"OVP suchen: Titel, Jahr, Studio, Verlag oder Genre …")
	_catalog_search.clear_button_enabled = true
	_catalog_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog_search.text_changed.connect(func(_text: String) -> void:
		_game_page = 0
		_select_first_catalog_game = true
		_refresh())
	bar.add_child(_catalog_search)
	_catalog_prev = make_button(Loc.t("ui.shop_window.text", "<"), func() -> void:
		_turn_catalog_page(-1))
	_catalog_next = make_button(Loc.t("ui.shop_window.text_3770", ">"), func() -> void:
		_turn_catalog_page(1))
	_catalog_page_label = Bezel.lcd_label("", Palette.LCD_AMBER, 11)
	_catalog_page_label.custom_minimum_size.x = 132
	_catalog_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_catalog_prev)
	bar.add_child(_catalog_page_label)
	bar.add_child(_catalog_next)


func _build_browser() -> void:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 9)
	content.add_child(body)
	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", _style(Color("0b0e13"), Color("2a3441"), 1, 7))
	body.add_child(list_panel)
	var list_margin := MarginContainer.new()
	_margins(list_margin, 7, 7)
	list_panel.add_child(list_margin)
	var list_column := VBoxContainer.new()
	list_column.add_theme_constant_override("separation", 5)
	list_margin.add_child(list_column)
	var register_row := HBoxContainer.new()
	register_row.add_theme_constant_override("separation", 8)
	list_column.add_child(register_row)
	_browser_heading = Bezel.lcd_label("", Palette.LCD_CYAN, 11)
	_browser_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	register_row.add_child(_browser_heading)
	_browser_status = Bezel.lcd_label("", Palette.LCD_GREEN, 10)
	_browser_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	register_row.add_child(_browser_status)
	list_column.add_child(HSeparator.new())
	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(62, 62)
	_list.icon_mode = ItemList.ICON_MODE_LEFT
	_list.max_columns = 1
	_list.same_column_width = true
	_list.allow_reselect = true
	_list.add_theme_font_size_override("font_size", 13)
	_list.add_theme_constant_override("h_separation", 10)
	_list.add_theme_constant_override("v_separation", 5)
	_list.item_selected.connect(func(_i: int) -> void: _refresh_detail())
	_list.item_activated.connect(func(_i: int) -> void: _on_action())
	list_column.add_child(_list)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.x = 335
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _style(Color("12171e"), Color("53647a"), 1, 7))
	body.add_child(detail_panel)
	var detail_margin := MarginContainer.new()
	_margins(detail_margin, 11, 11)
	detail_panel.add_child(detail_margin)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 6)
	detail_margin.add_child(detail)
	detail.add_child(Bezel.lcd_label(Loc.t("ui.shop_window.produktdetail", "PRODUKTDETAIL"), Palette.LCD_AMBER, 12))
	var visual := PanelContainer.new()
	visual.custom_minimum_size = Vector2(310, 205)
	visual.add_theme_stylebox_override("panel", _style(Color("080b10"), Color("2b3745"), 1, 5))
	detail.add_child(visual)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visual.add_child(_preview)
	_preview_mark = Label.new()
	_preview_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_mark.add_theme_font_size_override("font_size", 19)
	_preview_mark.add_theme_color_override("font_color", Color("d8b668"))
	visual.add_child(_preview_mark)
	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 16)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_title)
	_detail_meta = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_meta)
	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = true
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_desc.add_theme_font_size_override("normal_font_size", 13)
	_detail_desc.add_theme_constant_override("line_separation", 3)
	detail.add_child(_detail_desc)
	_action = make_button("", _on_action)
	_action.custom_minimum_size.y = 42
	detail.add_child(_action)


func _set_mode(mode: String) -> void:
	_mode = mode
	_game_page = 0
	_select_first_catalog_game = mode == "catalog"
	AudioManager.play("page_turn", 0.0)
	_refresh()


func _refresh() -> void:
	_refresh_generation += 1
	_thumbnail_jobs.clear()
	var keep_key := _selected_row_key()
	_list.clear()
	_rows.clear()
	if _mode == "stock":
		_fill_stock()
	else:
		_fill_catalog()
	if not _rows.is_empty():
		var next_index := _find_row_by_key(keep_key)
		if _mode == "catalog" and _select_first_catalog_game:
			next_index = _first_catalog_game_row()
		_select_first_catalog_game = false
		_list.select(clampi(next_index, 0, _rows.size() - 1))
	_update_tabs()
	_refresh_money()
	_refresh_detail()
	_drain_catalog_thumbnails()


func _fill_stock() -> void:
	# Die Abholtheke ist Teil des realen Ladens, nicht des Spielekatalogs. So
	# bleiben auch bezahlte Hardwarepakete erreichbar, deren Kauf im separaten
	# Hardware-Ausbau begonnen wurde.
	for arrived: Dictionary in OrderManager.arrived:
		_add_row(Loc.t("ui.shop_window.pickup_paid", "%s   ·   ABHOLBEREIT   ·   BEREITS BEZAHLT") % arrived.get("name", "?"),
			_order_thumbnail(arrived), {"kind": "ready", "id": arrived.get("id", ""), "item": arrived})
		_list.set_item_custom_fg_color(_list.item_count - 1, Palette.LCD_GREEN)
	for pending: Dictionary in OrderManager.pending:
		if _is_software_order(pending):
			continue
		var days := maxi(0, int(pending.get("arrives_day", 0)) - TimeManager.day_counter)
		_add_row(Loc.t("ui.shop_window.hardware_pending_days", "%s   ·   HARDWARE UNTERWEGS   ·   NOCH %d TAGE") % [pending.get("name", "?"), days],
			_order_thumbnail(pending), {"kind": "pending", "id": pending.get("id", ""), "item": pending})
		_list.set_item_custom_fg_color(_list.item_count - 1, Palette.LCD_AMBER)
	for item: Dictionary in ShopManager.current_stock():
		_add_row(Loc.t("ui.shop_window.available_now", "%s   ·   %s   ·   SOFORT VERFÜGBAR") % [item.get("name", "?"), Currency.format(ShopManager.price_of(item))],
			_hardware_texture(item, 128), {"kind": "hw", "id": item.get("id", ""), "item": item})
	for gid: String in ShopManager.game_stock():
		var entry := SoftwareBible.entry(gid)
		var tier := ShopManager.price_tier(gid)
		var tag := Loc.t("ui.shop_window.new", "NEU") if tier == "neu" else (
			Loc.t("ui.shop_window.budget", "BUDGET") if tier == "budget"
			else Loc.t("ui.shop_window.original", "ORIGINAL"))
		_add_row("%s   ·   %s   ·   %s   ·   %s" % [entry.get("display_name", "Spiel"), tag,
			_disk_count_text(entry), Currency.format(ShopManager.game_price(gid))],
			SoftwareBible.art_thumbnail(gid, "box_front", CATALOG_THUMB_SIZE), {"kind": "game", "id": gid, "item": {}})
		if tier == "neu":
			_list.set_item_custom_fg_color(_list.item_count - 1, Palette.LCD_AMBER)


func _fill_catalog() -> void:
	for arrived: Dictionary in OrderManager.arrived:
		if not _is_software_order(arrived):
			continue
		_add_row(Loc.t("ui.shop_window.pickup_paid", "%s   ·   ABHOLBEREIT   ·   BEREITS BEZAHLT") % arrived.get("name", "?"),
			_order_thumbnail(arrived), {"kind": "ready", "id": arrived.get("id", ""), "item": arrived})
		_list.set_item_custom_fg_color(_list.item_count - 1, Palette.LCD_GREEN)
	for pending: Dictionary in OrderManager.pending:
		if not _is_software_order(pending):
			continue
		var days := maxi(0, int(pending.get("arrives_day", 0)) - TimeManager.day_counter)
		_add_row(Loc.t("ui.shop_window.pending_days", "%s   ·   UNTERWEGS   ·   NOCH %d TAGE") % [pending.get("name", "?"), days],
			_order_thumbnail(pending), {"kind": "pending", "id": pending.get("id", ""), "item": pending})
		_list.set_item_custom_fg_color(_list.item_count - 1, Palette.LCD_AMBER)
	# Der OVP-Katalog zeigt nur Spiele. Hardware hat mit HARDWARE-AUSBAU eine
	# eigene, tiefe Konfiguration; die fruehere Mischung fuehrte dazu, dass beim
	# Blaettern durch Spiele rechts ploetzlich eine RAM-Karte ausgewaehlt war.
	var games := _filtered_catalog_games()
	_catalog_game_total = games.size()
	var pages := maxi(1, ceili(float(_catalog_game_total) / GAME_PAGE_SIZE))
	_game_page = clampi(_game_page, 0, pages - 1)
	var start := _game_page * GAME_PAGE_SIZE
	var end := mini(start + GAME_PAGE_SIZE, games.size())
	var shelf: Dictionary = {}
	for shelf_id: String in ShopManager.game_stock():
		shelf[shelf_id] = true
	for index in range(start, end):
		var gid: String = games[index]
		if OrderManager.is_pending(gid) or OrderManager._is_arrived(gid):
			continue
		var entry := SoftwareBible.entry(gid)
		var on_shelf := shelf.has(gid)
		var status := Loc.t("ui.shop_window.im_regal_sofort", "IM REGAL · SOFORT") if on_shelf \
			else Loc.t("ui.shop_window.ovp_bestellbar", "OVP · BESTELLBAR")
		_add_catalog_game_row("%s   ·   %s   ·   %s   ·   %s" % [entry.get("display_name", "Spiel"),
			_year_text(entry), _disk_count_text(entry), status],
			{"kind": "game" if on_shelf else "game_order", "id": gid, "item": {}})
		if on_shelf:
			_list.set_item_custom_fg_color(_list.item_count - 1, Palette.LCD_GREEN)


func _filtered_catalog_games() -> Array:
	_ensure_catalog_index()
	var query := _catalog_search.text.strip_edges().to_lower() if _catalog_search != null else ""
	if query.is_empty():
		return _catalog_ids
	if _catalog_filter_cache.has(query):
		return _catalog_filter_cache[query]
	var filtered: Array = []
	for id: String in _catalog_ids:
		if str(_catalog_search_index.get(id, "")).contains(query):
			filtered.append(id)
	_catalog_filter_cache[query] = filtered
	return filtered


func _ensure_catalog_index() -> void:
	var year := TimeManager.year
	if _catalog_index_year == year and not _catalog_ids.is_empty():
		return
	_catalog_index_year = year
	_catalog_ids = ShopManager.game_catalog()
	_catalog_search_index.clear()
	_catalog_filter_cache.clear()
	for id: String in _catalog_ids:
		var entry := SoftwareBible.entry(id)
		_catalog_search_index[id] = ("%s %s %s %s %s %s" % [entry.get("display_name", ""),
			entry.get("historical_name", ""), entry.get("developer", ""),
			entry.get("publisher", ""), entry.get("genre", ""),
			entry.get("release_year", "")]).to_lower()


func _add_row(label: String, texture: Texture2D, row: Dictionary) -> void:
	_list.add_item(label, texture if texture != null else Sprites.ui_icon("inventory"))
	_rows.append(row)


func _add_catalog_game_row(label: String, row: Dictionary) -> void:
	var row_index := _list.item_count
	_add_row(label, Sprites.ui_icon("inventory"), row)
	_thumbnail_jobs.append({
		"generation": _refresh_generation,
		"row_index": row_index,
		"id": str(row.get("id", "")),
	})


## Kalte Cover werden ueber mehrere Frames verteilt. Auf der alten Route
## dekodierte ein Seitenklick 24 große PNGs hintereinander und liess dadurch
## den auf dem Hauptthread erzeugten MOD-Audiopuffer leer laufen.
func _drain_catalog_thumbnails() -> void:
	if _thumbnail_drain_running or _thumbnail_jobs.is_empty():
		return
	_thumbnail_drain_running = true
	while not _thumbnail_jobs.is_empty():
		var job: Dictionary = _thumbnail_jobs.pop_front()
		await get_tree().process_frame
		if not is_inside_tree():
			break
		if int(job.get("generation", -1)) != _refresh_generation:
			continue
		var row_index := int(job.get("row_index", -1))
		var id := str(job.get("id", ""))
		if row_index < 0 or row_index >= _rows.size() or row_index >= _list.item_count:
			continue
		if str((_rows[row_index] as Dictionary).get("id", "")) != id:
			continue
		var texture: Texture2D = SoftwareBible.art_thumbnail(id, "box_front", CATALOG_THUMB_SIZE)
		if texture != null and int(job.get("generation", -1)) == _refresh_generation:
			_list.set_item_icon(row_index, texture)
	_thumbnail_drain_running = false


func _update_tabs() -> void:
	var arrived_count := OrderManager.arrived.size()
	var software_ready := 0
	for arrived: Dictionary in OrderManager.arrived:
		if _is_software_order(arrived):
			software_ready += 1
	var shelf_count := ShopManager.game_stock().size()
	_ensure_catalog_index()
	var catalog_count := _catalog_ids.size()
	_tab_stock.text = Loc.t("ui.shop_window.im_regal_count", "IM REGAL · %d OVP") % shelf_count + (
		Loc.t("ui.shop_window.ready_count", "  ·  %d ABHOLBEREIT") % arrived_count
		if arrived_count > 0 else "")
	_tab_catalog.text = Loc.t("ui.shop_window.bestellkatalog_count", "OVP-KATALOG · %d") % catalog_count + (
		Loc.t("ui.shop_window.ready_count", "  ·  %d ABHOLBEREIT") % software_ready
		if software_ready > 0 else "")
	_tab_stock.disabled = _mode == "stock"
	_tab_catalog.disabled = _mode == "catalog"
	var catalog_mode := _mode == "catalog"
	_catalog_tools.visible = catalog_mode
	_catalog_search.visible = catalog_mode
	_catalog_prev.visible = catalog_mode
	_catalog_next.visible = catalog_mode
	_catalog_page_label.visible = catalog_mode
	if catalog_mode:
		var pages := maxi(1, ceili(float(_catalog_game_total) / GAME_PAGE_SIZE))
		_catalog_page_label.text = Loc.t("ui.shop_window.ovp_d_d_d", "OVP %d/%d · %d") % [_game_page + 1, pages, _catalog_game_total]
		_catalog_prev.disabled = _game_page <= 0
		_catalog_next.disabled = _game_page >= pages - 1
		_browser_heading.text = Loc.t("ui.shop_window.bestellkatalog", "BESTELLKATALOG")
		_browser_status.text = _catalog_range_text()
	else:
		_browser_heading.text = Loc.t("ui.shop_window.im_regal", "IM REGAL")
		_browser_status.text = Loc.t("ui.shop_window.ready_plain", "%d ABHOLBEREIT") % arrived_count \
			if arrived_count > 0 else Loc.t("ui.shop_window.im_regal_sofort", "IM REGAL · SOFORT")


func _refresh_money() -> void:
	if _money != null:
		_money.text = Loc.t("ui.shop_window.geldbeutel_s", "GELDBEUTEL  %s") % Currency.format(PlayerStats.geld)


func _on_money_changed() -> void:
	_refresh_money()
	# Die Preiszusage bleibt gleich, aber Fehlbetrag und Kauftext muessen sich
	# ohne Schliessen des Katalogs unmittelbar mit dem Geldbeutel aendern.
	if _action != null:
		_refresh_detail()


func _refresh_detail() -> void:
	_detail_generation += 1
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] >= _rows.size():
		_detail_title.text = Loc.t("ui.shop_window.nichts_ausgewahlt", "Nichts ausgewählt")
		_detail_meta.text = ""
		_detail_desc.text = Loc.t("ui.shop_window.s_wartet_hinter_theke", "%s wartet hinter der Theke.") % ShopEra.owner_name()
		_preview.texture = null
		_preview_mark.text = Loc.t("ui.shop_window.s_nkatalog", "%s\nKATALOG") % ("JAN GRUBER" if ShopEra.gruber_retired() else "GRUBER")
		_action.text = Loc.t("ui.shop_window.artikel_auswahlen", "ARTIKEL AUSWÄHLEN")
		_action.disabled = true
		return
	var row: Dictionary = _rows[selected[0]]
	var kind := str(row.get("kind", ""))
	var detail_title := ""
	var meta := ""
	var desc := ""
	var texture: Texture2D = null
	_action.tooltip_text = ""
	match kind:
		"hw", "order":
			var item: Dictionary = row.get("item", {})
			var quote: Dictionary = ShopManager.price_quote(item)
			var price := float(quote.get("price", 0.0))
			var shortfall := float(quote.get("shortfall", 0.0))
			detail_title = str(item.get("name", "?"))
			texture = _list.get_item_icon(selected[0])
			_load_hardware_detail(str(item.get("id", "")), item, _detail_generation)
			meta = "%s · %s" % [
				Loc.t("ui.shop_window.order_item", "BESTELLWARE")
					if bool(item.get("order_only", false))
					else Loc.t("ui.shop_window.stock_item", "REGALWARE"),
				Currency.format(price)]
			desc = str(item.get("desc", ""))
			_action.text = (
				Loc.t("ui.shop_window.order", "BESTELLEN") if kind == "order"
				else Loc.t("ui.shop_window.buy", "KAUFEN")) + " · " + Currency.format(price)
			var requirement := ShopManager.item_requirement_status(item)
			if not bool(requirement.get("ok", false)):
				desc += "\n\n[color=#ef9a78]GESPERRT · %s[/color]" % str(requirement.get("reason", "Voraussetzung fehlt")).to_upper()
			elif shortfall > 0.005:
				desc += "\n\n[color=#f2be5c]GELDBEUTEL %s · ES FEHLEN %s[/color]" % [
					Currency.format(PlayerStats.geld), Currency.format(shortfall)]
				_action.text = Loc.t("ui.shop_window.noch_s_notig_preis_s", "NOCH %s NÖTIG · PREIS %s") % [Currency.format(shortfall), Currency.format(price)]
				_action.tooltip_text = Loc.t("ui.shop_window.nicht_genug_bargeld_es_fehlen_s", "Nicht genug Bargeld: Es fehlen %s.") % Currency.format(shortfall)
			_action.disabled = not bool(requirement.get("ok", false))
		"game", "game_order":
			var game_id := str(row.get("id", ""))
			var entry := SoftwareBible.entry(game_id)
			var game_price := float(ShopManager.game_price(game_id))
			var game_shortfall := Currency.snap(maxf(0.0, game_price - PlayerStats.geld))
			detail_title = str(entry.get("display_name", "Spiel"))
			# Sofort das bereits geladene Listencover zeigen. Die aufwendige 3D-Box
			# wird danach selektionssicher aufgebaut und blockiert keinen Seitenwechsel.
			texture = _list.get_item_icon(selected[0])
			_load_detail_box(game_id, _detail_generation)
			meta = "OVP · VERSIEGELT · %s · %s · %s" % [_meta(entry, "Spiel"), entry.get("release_year", "?"), _disk_count_text(entry)]
			var publisher := str(entry.get("publisher", "")).strip_edges()
			desc = "[b]%s%s[/b]\nVersiegelte OVP mit Originalcover, vollständigem Diskettensatz und Handbuch.%s" % [
				entry.get("developer", "Unbekannter Hersteller"),
				" · " + publisher if publisher != "" else "",
				(" %s bestellt sie aus Großhandel, Restlager oder Archivverbund." % ShopEra.owner_name())
				if kind == "game_order" else " Sie steht heute im Ladenregal."]
			_action.text = (
				Loc.t("ui.shop_window.order_game", "SPIEL BESTELLEN")
				if kind == "game_order"
				else Loc.t("ui.shop_window.buy_original", "ORIGINAL KAUFEN")
				) + " · " + Currency.format(game_price)
			if game_shortfall > 0.005:
				desc += "\n\n[color=#f2be5c]GELDBEUTEL %s · ES FEHLEN %s[/color]" % [
					Currency.format(PlayerStats.geld), Currency.format(game_shortfall)]
				_action.text = Loc.t("ui.shop_window.noch_s_notig_preis_s", "NOCH %s NÖTIG · PREIS %s") % [
					Currency.format(game_shortfall), Currency.format(game_price)]
				_action.tooltip_text = Loc.t("ui.shop_window.nicht_genug_bargeld_es_fehlen_s", "Nicht genug Bargeld: Es fehlen %s.") % Currency.format(game_shortfall)
			_action.disabled = false
		"ready":
			var ready_order: Dictionary = row.get("item", {})
			detail_title = str(ready_order.get("name", "Abholbereite Bestellung"))
			texture = _list.get_item_icon(selected[0])
			_load_order_detail(ready_order, _detail_generation)
			meta = Loc.t("ui.shop_window.ready_meta", "ABHOLBEREIT · BEZAHLT")
			desc = Loc.t("ui.shop_window.reserved_behind_counter", "Liegt bezahlt und reserviert hinter der Theke.")
			_action.text = Loc.t("ui.shop_window.jetzt_abholen", "JETZT ABHOLEN")
			_action.disabled = false
		"pending":
			var order: Dictionary = row.get("item", {})
			var days := maxi(0,
				int(order.get("arrives_day", TimeManager.day_counter)) - TimeManager.day_counter)
			detail_title = str(order.get("name", "Bestellung"))
			texture = _list.get_item_icon(selected[0])
			_load_order_detail(order, _detail_generation)
			meta = Loc.t("ui.shop_window.paid_delivery_days", "BEZAHLT · UNTERWEGS · NOCH %d TAGE") % days
			desc = Loc.t("ui.shop_window.delivery_desc", "Der Großhändler liefert. Diese Ware ist noch nicht in deinem Besitz und erscheint deshalb noch nicht in der Sammlervitrine. Nach dem Anruf des Ladens hier im Laden abholen.")
			_action.text = Loc.t("ui.shop_window.bereits_bestellt", "BEREITS BESTELLT")
			_action.disabled = true
	_detail_title.text = detail_title
	_detail_meta.text = meta
	_detail_desc.text = desc
	_preview.texture = texture
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if texture != null and texture.get_width() < 256 \
		else CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_mark.text = Loc.t("ui.shop_window.hardware_nkatalog", "HARDWARE\nKATALOG") if texture == null else ""


func _load_detail_box(game_id: String, generation: int) -> void:
	# Der große 3D-Boxaufbau folgt bewusst erst nach zwei Audiopuffer-Frames.
	# Dadurch konkurrieren Seitenwechsel, erstes Thumbnail und Detailkomposition
	# nicht mehr im selben Renderframe.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _detail_generation or not is_inside_tree():
		return
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] >= _rows.size():
		return
	if str((_rows[selected[0]] as Dictionary).get("id", "")) != game_id:
		return
	var texture := BoxComposer.box_texture(game_id, "sealed", 384)
	if texture != null and generation == _detail_generation:
		_preview.texture = texture
		_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_preview_mark.text = ""


func _load_hardware_detail(item_id: String, item: Dictionary, generation: int) -> void:
	await get_tree().process_frame
	if generation != _detail_generation or not is_inside_tree() or not _selected_matches(item_id):
		return
	var texture := _hardware_texture(item, 768)
	if texture != null and generation == _detail_generation:
		_preview.texture = texture
		_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_preview_mark.text = ""


func _load_order_detail(order: Dictionary, generation: int) -> void:
	await get_tree().process_frame
	var id := str(order.get("id", ""))
	if generation != _detail_generation or not is_inside_tree() or not _selected_matches(id):
		return
	var texture := _texture_for_order(order)
	if texture != null and generation == _detail_generation:
		_preview.texture = texture
		_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_preview_mark.text = ""


func _on_action() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] >= _rows.size():
		UIManager.toast(Loc.t("ui.shop_window.erst_einen_artikel_auswahlen", "Erst einen Artikel auswählen."))
		return
	var row: Dictionary = _rows[selected[0]]
	var result: Dictionary = {"ok": false, "text": Loc.t("ui.shop_window.diese_ware_ist_schon_unterwegs", "Diese Ware ist schon unterwegs.")}
	match str(row.get("kind", "")):
		"hw": result = ShopManager.buy(str((row.get("item", {}) as Dictionary).get("id", "")))
		"game": result = ShopManager.buy_game(str(row.get("id", "")))
		"ready": result = OrderManager.pickup(str(row.get("id", "")))
		"order": result = OrderManager.place_order(str(row.get("id", "")))
		"game_order": result = OrderManager.place_game_order(str(row.get("id", "")))
	UIManager.toast(str(result.get("text", "")))
	AudioManager.play("cash_register" if bool(result.get("ok", false)) else "phone_busy", 0.0)
	_refresh()


func _hardware_texture(item: Dictionary, max_width: int = 768) -> Texture2D:
	var path := str(item.get("preview_asset", ""))
	return RuntimeImages.texture(path, max_width, true) if path != "" else null


func _order_thumbnail(order: Dictionary) -> Texture2D:
	var id := str(order.get("id", ""))
	var shop_item := ShopManager.get_item(id)
	if not shop_item.is_empty():
		return _hardware_texture(shop_item, 128)
	return SoftwareBible.art_thumbnail(id, "box_front", CATALOG_THUMB_SIZE) \
		if not SoftwareBible.entry(id).is_empty() else null


func _texture_for_order(order: Dictionary) -> Texture2D:
	var id := str(order.get("id", ""))
	var shop_item := ShopManager.get_item(id)
	if not shop_item.is_empty():
		return _hardware_texture(shop_item)
	return BoxComposer.box_texture(id, "sealed", 384) if not SoftwareBible.entry(id).is_empty() else null


func _is_software_order(order: Dictionary) -> bool:
	if bool(order.get("software", false)):
		return true
	var id := str(order.get("id", ""))
	return not id.is_empty() and not SoftwareBible.entry(id).is_empty() \
		and ShopManager.get_item(id).is_empty()


func _selected_matches(id: String) -> bool:
	var selected := _list.get_selected_items()
	return not selected.is_empty() and selected[0] < _rows.size() \
		and str((_rows[selected[0]] as Dictionary).get("id", "")) == id


func _catalog_range_text() -> String:
	var games := _filtered_catalog_games()
	if games.is_empty():
		return Loc.t("ui.shop_window.nichts_ausgewahlt", "Nichts ausgewählt").to_upper()
	var start := clampi(_game_page * GAME_PAGE_SIZE, 0, games.size() - 1)
	var end := clampi(start + GAME_PAGE_SIZE - 1, start, games.size() - 1)
	var first := str(SoftwareBible.entry(str(games[start])).get("display_name", "?")).left(1).to_upper()
	var last := str(SoftwareBible.entry(str(games[end])).get("display_name", "?")).left(1).to_upper()
	return "%s–%s · %d OVP" % [first, last, games.size()]


func _year_text(entry: Dictionary) -> String:
	var year := int(entry.get("release_year", 0))
	return str(year) if year > 0 else "?"


func _turn_catalog_page(direction: int) -> void:
	_ensure_catalog_index()
	var filtered := _filtered_catalog_games()
	var pages := maxi(1, ceili(float(filtered.size()) / GAME_PAGE_SIZE))
	var next_page := clampi(_game_page + direction, 0, pages - 1)
	if next_page == _game_page:
		return
	_game_page = next_page
	_select_first_catalog_game = true
	AudioManager.play("page_turn", 0.02, -7.0)
	_refresh()


func _decorate_tab(button: Button, icon_texture: Texture2D) -> void:
	button.icon = icon_texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 20)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _selected_row_key() -> String:
	if _list == null:
		return ""
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] >= _rows.size():
		return ""
	var row: Dictionary = _rows[selected[0]]
	return "%s:%s" % [row.get("kind", ""), row.get("id", (row.get("item", {}) as Dictionary).get("id", ""))]


func _find_row_by_key(key: String) -> int:
	if key.is_empty():
		return 0
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var row_key := "%s:%s" % [row.get("kind", ""), row.get("id", (row.get("item", {}) as Dictionary).get("id", ""))]
		if row_key == key:
			return index
	return 0


func _first_catalog_game_row() -> int:
	for index in _rows.size():
		if str((_rows[index] as Dictionary).get("kind", "")) in ["game", "game_order"]:
			return index
	return 0


func _meta(entry: Dictionary, fallback: String = "") -> String:
	var kept: Array[String] = []
	for part: String in str(entry.get("genre", "")).split(",", false):
		var value := part.strip_edges()
		if value != "" and value.to_lower() not in ["unknown", "(unknown)"]:
			kept.append(value)
	return fallback if kept.is_empty() else ", ".join(kept)


func _disk_count_text(entry: Dictionary) -> String:
	var count := clampi(int(entry.get("disk_count", 1)), 1, 20)
	return "%d Diskette" % count if count == 1 else "%d Disketten" % count


func _style(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _margins(margin: MarginContainer, horizontal: int, vertical: int) -> void:
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
