class_name CollectionCabinetWindow
extends RetroWindow
## Die bislang fehlende Gegenansicht des Spielerzimmers. Hintergrund, Vitrine,
## Monitorrueckseite und Boxcover bleiben getrennte Assets: Modellwechsel und
## neue OVP-Funde aktualisieren die Szene ohne neu gerendertes Vollbild.

const RuntimeImages := preload("res://scripts/gfx/runtime_image_loader.gd")
const BoxComposer := preload("res://scripts/gfx/software_box_composer.gd")
const CollectionLayout := preload("res://scripts/gfx/collection_room_layout.gd")
const ShopEra := preload("res://scripts/data/computer_shop_era.gd")

var _scene: Control
var _cabinet: TextureRect
var _monitor_rear: TextureRect
var _list: ItemList
var _box_preview: TextureRect
var _detail: RichTextLabel
var _count: Label
var _order_status: Label
var _hero_title: Label
var _hero_badge: Label
var _hero_index: Label
var _stage_title: Label
var _stage_meta: Label
var _condition_bar: ProgressBar
var _condition_label: Label
var _atmosphere: CabinetAtmosphere
var _filter: OptionButton
var _page_label: Label
var _sell_button: Button
var _car_button: Button
var _preview_buttons: Array[Button] = []
var _preview_mode := "front"
var _page := 0
var _confirm_action := ""
var _all_boxes: Array = []
var _boxes: Array = []


func _init() -> void:
	title = Loc.t("ui.collection_cabinet_window.spielerzimmer_andere_seite_sammlervitrine", "SPIELERZIMMER · ANDERE SEITE · SAMMLERVITRINE")
	win_size = Vector2(1120, 660)


func _ready() -> void:
	super._ready()
	_build()
	if not DiskManager.disks_changed.is_connected(_refresh):
		DiskManager.disks_changed.connect(_refresh)
	if not OrderManager.orders_changed.is_connected(_refresh):
		OrderManager.orders_changed.connect(_refresh)
	if not RoomManager.device_model_changed.is_connected(_on_model_changed):
		RoomManager.device_model_changed.connect(_on_model_changed)
	_refresh()


func _exit_tree() -> void:
	if DiskManager.disks_changed.is_connected(_refresh):
		DiskManager.disks_changed.disconnect(_refresh)
	if OrderManager.orders_changed.is_connected(_refresh):
		OrderManager.orders_changed.disconnect(_refresh)
	if RoomManager.device_model_changed.is_connected(_on_model_changed):
		RoomManager.device_model_changed.disconnect(_on_model_changed)


func _build() -> void:
	# Kopfbereich als kompakte Museumstafel statt als lose Textzeilen. Die
	# Kennzahlen bleiben sofort lesbar, konkurrieren aber nicht mit dem Exponat.
	var head_shell := PanelContainer.new()
	head_shell.add_theme_stylebox_override("panel",
		_panel_style(Color8(18, 20, 24), Color8(72, 74, 78), 1, 3, 10, 6))
	content.add_child(head_shell)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head_shell.add_child(head)
	var intro := VBoxContainer.new()
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.add_theme_constant_override("separation", 1)
	head.add_child(intro)
	var eyebrow := Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.private_spielesammlung_1990_99", "PRIVATE SPIELESAMMLUNG · 1990–99"), Palette.LCD_AMBER, 11)
	intro.add_child(eyebrow)
	var heading := Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.deine_original_boxen", "DEINE ORIGINAL-BOXEN"), Palette.UI_TEXT, 17)
	intro.add_child(heading)
	_order_status = Bezel.dim_label("", 11)
	_order_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_status.modulate = Palette.LCD_AMBER
	intro.add_child(_order_status)
	_count = Bezel.lcd_label("", Palette.LCD_GREEN, 11)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count)

	var tools_shell := PanelContainer.new()
	tools_shell.add_theme_stylebox_override("panel",
		_panel_style(Color8(12, 13, 16), Color8(52, 54, 60), 1, 2, 6, 3))
	content.add_child(tools_shell)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools_shell.add_child(tools)
	var archive_label := Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.archiv", "ARCHIV"), Palette.LCD_AMBER, 12)
	archive_label.custom_minimum_size.x = 54
	archive_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tools.add_child(archive_label)
	_filter = OptionButton.new()
	_filter.custom_minimum_size.x = 180
	_filter.add_item(Loc.t("ui.collection_cabinet_window.alle_original_ovps", "ALLE ORIGINAL-OVPs"))
	_filter.add_item(Loc.t("ui.collection_cabinet_window.nur_versiegelt", "NUR VERSIEGELT"))
	_filter.add_item(Loc.t("ui.collection_cabinet_window.nur_gebraucht", "NUR GEBRAUCHT"))
	_filter.item_selected.connect(func(_index: int) -> void: _page = 0; _apply_filter())
	tools.add_child(_filter)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	tools.add_child(make_button(Loc.t("ui.collection_cabinet_window.vitrine", "◀ VITRINE"), _change_page.bind(-1)))
	_page_label = Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.seite_1_1", "SEITE 1/1"), Palette.LCD_AMBER, 11)
	tools.add_child(_page_label)
	tools.add_child(make_button(Loc.t("ui.collection_cabinet_window.vitrine_ecf3", "VITRINE ▶"), _change_page.bind(1)))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	content.add_child(body)

	var stage_shell := PanelContainer.new()
	stage_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_shell.add_theme_stylebox_override("panel",
		_panel_style(Color8(6, 7, 8), Color8(102, 82, 54), 2, 2, 2, 2))
	body.add_child(stage_shell)
	_scene = Control.new()
	_scene.clip_contents = true
	_scene.custom_minimum_size = Vector2(704, 500)
	_scene.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_shell.add_child(_scene)
	var bg := TextureRect.new()
	bg.name = "ReverseRoomBackground"
	bg.texture = RuntimeImages.texture(CollectionLayout.background(), 1920)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(bg)
	_cabinet = TextureRect.new()
	_cabinet.name = "DynamicGameCabinet"
	_cabinet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cabinet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cabinet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cabinet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(_cabinet)
	_monitor_rear = TextureRect.new()
	_monitor_rear.name = "SelectedMonitorRear"
	_monitor_rear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_monitor_rear.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_monitor_rear.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_monitor_rear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(_monitor_rear)

	# Subtile, animierte Glasreflexe und ein warmer Lichtkegel binden die
	# freigestellte Vitrine glaubwürdig in die Zimmeraufnahme ein.
	_atmosphere = CabinetAtmosphere.new()
	_atmosphere.name = "CabinetAtmosphereFX"
	_atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(_atmosphere)

	var live_plate := PanelContainer.new()
	live_plate.set_anchors_preset(Control.PRESET_TOP_WIDE)
	live_plate.offset_left = 10
	live_plate.offset_top = 10
	live_plate.offset_right = -10
	live_plate.offset_bottom = 36
	live_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_plate.add_theme_stylebox_override("panel",
		_panel_style(Color(0.025, 0.03, 0.04, 0.84), Color(1.0, 0.62, 0.16, 0.52),
			1, 2, 8, 3))
	var live_row := HBoxContainer.new()
	live_plate.add_child(live_row)
	var live := Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.sammlerzimmer_vitrine_live", "● SAMMLERZIMMER · VITRINE LIVE"), Palette.LCD_AMBER, 11)
	live.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_row.add_child(live)
	var glass_note := Bezel.dim_label(Loc.t("ui.collection_cabinet_window.echtes_ovp_artwork_glas_holz_licht", "ECHTES OVP-ARTWORK · GLAS / HOLZ / LICHT"), 10)
	glass_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	live_row.add_child(glass_note)
	_scene.add_child(live_plate)

	var stage_plate := PanelContainer.new()
	stage_plate.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	stage_plate.offset_left = 12
	stage_plate.offset_top = -58
	stage_plate.offset_right = -12
	stage_plate.offset_bottom = -12
	stage_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_plate.add_theme_stylebox_override("panel",
		_panel_style(Color(0.025, 0.03, 0.04, 0.90), Color(0.96, 0.58, 0.18, 0.55),
			1, 2, 9, 4))
	var stage_copy := VBoxContainer.new()
	stage_copy.add_theme_constant_override("separation", 0)
	stage_plate.add_child(stage_copy)
	_stage_title = Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.ausstellung_wird_bestuckt", "AUSSTELLUNG WIRD BESTÜCKT"), Palette.UI_TEXT, 13)
	_stage_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stage_copy.add_child(_stage_title)
	_stage_meta = Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.fach_original_ovp", "FACH -- · ORIGINAL-OVP"), Palette.LCD_AMBER, 11)
	stage_copy.add_child(_stage_meta)
	_scene.add_child(stage_plate)
	_scene.resized.connect(_layout_scene)

	var side_shell := PanelContainer.new()
	side_shell.custom_minimum_size.x = 360
	side_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_shell.add_theme_stylebox_override("panel",
		_panel_style(Color8(14, 15, 18), Color8(68, 70, 76), 1, 2, 8, 6))
	body.add_child(side_shell)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 5)
	side_shell.add_child(side)
	var register_head := HBoxContainer.new()
	side.add_child(register_head)
	var register_title := Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.ausstellungsdeck", "AUSSTELLUNGSDECK"), Palette.LCD_AMBER, 12)
	register_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	register_head.add_child(register_title)
	_hero_index = Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.expo", "EXPO --/--"), Palette.LCD_CYAN, 11)
	_hero_index.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	register_head.add_child(_hero_index)
	var preview_modes := HBoxContainer.new()
	preview_modes.add_theme_constant_override("separation", 4)
	for definition: Dictionary in [
		{"id": "front", "label": "VORNE"},
		{"id": "back", "label": "HINTEN"},
		{"id": "disks", "label": "DISKS"},
		{"id": "manual", "label": "HANDBUCH"},
	]:
		var button := make_button(str(definition["label"]), _set_preview_mode.bind(str(definition["id"])))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview_modes.add_child(button)
		_preview_buttons.append(button)
	side.add_child(preview_modes)

	var hero_shell := PanelContainer.new()
	hero_shell.custom_minimum_size.y = 204
	hero_shell.add_theme_stylebox_override("panel",
		_panel_style(Color8(6, 8, 12), Color8(78, 92, 112), 1, 3, 7, 5))
	side.add_child(hero_shell)
	var hero := VBoxContainer.new()
	hero.add_theme_constant_override("separation", 2)
	hero_shell.add_child(hero)
	var hero_caption := HBoxContainer.new()
	hero.add_child(hero_caption)
	_hero_title = Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.noch_kein_exponat", "NOCH KEIN EXPONAT"), Palette.UI_TEXT, 14)
	_hero_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hero_caption.add_child(_hero_title)
	_hero_badge = Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.archiv", "ARCHIV"), Palette.LCD_AMBER, 11)
	_hero_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hero_caption.add_child(_hero_badge)
	_box_preview = TextureRect.new()
	_box_preview.custom_minimum_size = Vector2(330, 170)
	_box_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_box_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_box_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_box_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(_box_preview)

	var passport := PanelContainer.new()
	passport.add_theme_stylebox_override("panel",
		_panel_style(Color8(20, 21, 24), Color8(54, 57, 64), 1, 2, 7, 4))
	side.add_child(passport)
	var passport_body := VBoxContainer.new()
	passport_body.add_theme_constant_override("separation", 2)
	passport.add_child(passport_body)
	_list = ItemList.new()
	var archive_head := HBoxContainer.new()
	var archive_title := Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.archivregister", "ARCHIVREGISTER"), Palette.LCD_AMBER, 11)
	archive_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	archive_head.add_child(archive_title)
	var archive_hint := Bezel.dim_label(Loc.t("ui.collection_cabinet_window.klick_ausstellen", "KLICK = AUSSTELLEN"), 10)
	archive_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	archive_head.add_child(archive_hint)
	side.add_child(archive_head)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size.y = 72
	_list.add_theme_font_size_override("font_size", 12)
	_list.add_theme_constant_override("v_separation", 1)
	_list.item_selected.connect(func(_index: int) -> void: _refresh_detail())
	side.add_child(_list)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.custom_minimum_size.y = 55
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.add_theme_font_size_override("normal_font_size", 12)
	passport_body.add_child(_detail)
	var condition_row := HBoxContainer.new()
	condition_row.add_theme_constant_override("separation", 6)
	passport_body.add_child(condition_row)
	_condition_label = Bezel.lcd_label(Loc.t("ui.collection_cabinet_window.zustand", "ZUSTAND --"), Palette.LCD_CYAN, 10)
	_condition_label.custom_minimum_size.x = 78
	condition_row.add_child(_condition_label)
	_condition_bar = Bezel.bar(Palette.LCD_GREEN, Vector2(120, 8))
	_condition_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	condition_row.add_child(_condition_bar)
	_sell_button = make_button(Loc.t("ui.collection_cabinet_window.ausgewahlten_satz_verkaufen", "AUSGEWÄHLTEN SATZ VERKAUFEN"), _on_sell_selected)
	side.add_child(_sell_button)
	_car_button = make_button(Loc.t("ui.collection_cabinet_window.auto_fonds_prufen", "AUTO-FONDS PRÜFEN"), _on_buy_car)
	side.add_child(_car_button)


func _refresh() -> void:
	_all_boxes = DiskManager.boxed_collection()
	_refresh_order_status()
	_apply_filter()


func _refresh_order_status() -> void:
	if _order_status == null:
		return
	var software_orders: Array = OrderManager.software_orders()
	if software_orders.is_empty():
		_order_status.text = ""
		_order_status.visible = false
		return
	var notices: Array[String] = []
	for order: Dictionary in software_orders:
		var order_name := str(order.get("name", "Spiel"))
		if str(order.get("status", "")) == "ready":
			notices.append("%s: BEZAHLT & ABHOLBEREIT BEI %s" % [
				order_name.to_upper(), ShopEra.owner_name().to_upper()])
		else:
			notices.append("%s: BEZAHLT · NOCH %d TAGE" % [
				order_name.to_upper(), int(order.get("days_left", 0))])
	_order_status.text = Loc.t("ui.collection_cabinet_window.noch_nicht_in_vitrine_s_erst", "NOCH NICHT IN DER VITRINE · %s · ERST NACH ABHOLUNG") \
		% "  |  ".join(notices)
	_order_status.visible = true


func _apply_filter() -> void:
	_boxes = _all_boxes.filter(func(disk: Disk) -> bool:
		return _filter == null or _filter.selected == 0 \
			or (_filter.selected == 1 and disk.package_condition == "sealed") \
			or (_filter.selected == 2 and disk.package_condition == "used"))
	var max_page := maxi(0, ceili(float(_boxes.size()) / 8.0) - 1)
	_page = clampi(_page, 0, max_page)
	_list.clear()
	for index in _boxes.size():
		var disk: Disk = _boxes[index]
		var marker := "◆ SEALED" if disk.package_condition == "sealed" else "◇ GEBRAUCHT"
		_list.add_item("%02d  %s  ·  %s" % [index + 1, disk.content_title, marker])
	var sealed := _all_boxes.filter(func(disk: Disk) -> bool: return disk.package_condition == "sealed").size()
	_count.text = Loc.t("ui.collection_cabinet_window.d_sets_d_titel_d_sealed", "%d SETS · %d TITEL · %d SEALED · WERT %s") % [
		_all_boxes.size(), DiskManager.unique_boxed_game_count(), sealed,
		Currency.format(DiskManager.collection_value())]
	var start := _page * 8
	_cabinet.texture = BoxComposer.cabinet_texture(_boxes.slice(start, mini(start + 8, _boxes.size())), 512)
	_page_label.text = Loc.t("ui.collection_cabinet_window.seite_d_d", "SEITE %d/%d") % [_page + 1, max_page + 1]
	_stage_meta.text = Loc.t("ui.collection_cabinet_window.vitrine_02d_d_8_facher_belegt", "VITRINE %02d · %d/8 FÄCHER BELEGT · ORIGINAL-OVP") % [
		_page + 1, mini(8, maxi(0, _boxes.size() - start))]
	_refresh_monitor()
	if not _boxes.is_empty():
		_list.select(mini(start, _boxes.size() - 1))
	_confirm_action = ""
	_refresh_detail()
	_refresh_car_button()
	_layout_scene.call_deferred()


func _refresh_detail() -> void:
	var selection := _list.get_selected_items()
	if selection.is_empty() or selection[0] >= _boxes.size():
		_box_preview.texture = null
		_hero_title.text = Loc.t("ui.collection_cabinet_window.noch_kein_exponat", "NOCH KEIN EXPONAT")
		_hero_badge.text = Loc.t("ui.collection_cabinet_window.archiv_leer", "ARCHIV LEER")
		_hero_index.text = Loc.t("ui.collection_cabinet_window.expo", "EXPO --/--")
		_stage_title.text = Loc.t("ui.collection_cabinet_window.erste_original_ovp_wartet_noch", "DIE ERSTE ORIGINAL-OVP WARTET NOCH")
		_detail.text = Loc.t("ui.collection_cabinet_window.color_969692_s_verkauft_versiegelte_neuware", "[color=#969692]%s verkauft versiegelte Neuware; auf dem Trödelmarkt findest du gebrauchte Komplettboxen.[/color]") % \
			ShopEra.owner_name()
		_condition_label.text = Loc.t("ui.collection_cabinet_window.zustand", "ZUSTAND --")
		_condition_bar.value = 0
		if _atmosphere != null:
			_atmosphere.selected_slot = -1
			_atmosphere.queue_redraw()
		_sell_button.disabled = true
		return
	var disk: Disk = _boxes[selection[0]]
	var wanted_page := int(selection[0] / 8.0)
	if wanted_page != _page:
		_page = wanted_page
		var start := _page * 8
		_cabinet.texture = BoxComposer.cabinet_texture(_boxes.slice(start, mini(start + 8, _boxes.size())), 512)
		_page_label.text = Loc.t("ui.collection_cabinet_window.seite_d_d", "SEITE %d/%d") % [_page + 1, maxi(1, ceili(float(_boxes.size()) / 8.0))]
	match _preview_mode:
		"back":
			_box_preview.texture = BoxComposer.box_texture(disk.software_id, disk.package_condition,
				384, "back", disk.color, disk.disk_count)
		"disks":
			_box_preview.texture = BoxComposer.disk_set_texture(disk.software_id, disk.color,
				disk.disk_count, 384)
		"manual":
			_box_preview.texture = BoxComposer.manual_texture(disk.software_id, 384)
		_:
			_box_preview.texture = BoxComposer.box_texture(disk.software_id, disk.package_condition,
				384, "front", disk.color, disk.disk_count)
	var status := "VERSIEGELT · SAMMLERBONUS +25%" if disk.package_condition == "sealed" else "GEBRAUCHT · MIT BESITZERGESCHICHTE"
	var metadata := SoftwareBible.entry(disk.software_id)
	var culture_data := CultureManager.software(disk.software_id)
	var release_year := int(metadata.get("release_year", culture_data.get("release_year", disk.year_created)))
	var genre := str(metadata.get("genre", culture_data.get("genre", "Spiel"))).replace(" ,", ",")
	var publisher := str(metadata.get("publisher", culture_data.get("publisher", "Unbekannter Verlag")))
	var value := Currency.format(_set_value(disk.software_set_id))
	var sale := Currency.format(CollectionMarket.set_sale_value(disk))
	var disk_count_text := Loc.t_plural("ui.collection_cabinet_window.disk_count",
		"%d Diskette", "%d Disketten", disk.disk_count)
	_hero_title.text = disk.content_title.to_upper()
	_hero_badge.text = Loc.t("ui.collection_cabinet_window.sealed", "◆ SEALED") \
		if disk.package_condition == "sealed" \
		else Loc.t("ui.collection_cabinet_window.used", "◇ GEBRAUCHT")
	_hero_badge.modulate = Palette.LCD_GREEN if disk.package_condition == "sealed" else Palette.LCD_AMBER
	_hero_index.text = Loc.t("ui.collection_cabinet_window.expo_02d_02d", "EXPO %02d/%02d") % [selection[0] + 1, _boxes.size()]
	_stage_title.text = Loc.t("ui.collection_cabinet_window.ausgestellt_s", "AUSGESTELLT · %s") % disk.content_title.to_upper()
	_stage_meta.text = Loc.t("ui.collection_cabinet_window.vitrine_02d_fach_02d_s_d", "VITRINE %02d · FACH %02d · %s · %d DISK%s") % [
		_page + 1, posmod(selection[0], 8) + 1,
		Loc.t("ui.collection_cabinet_window.condition_sealed", "VERSIEGELT")
			if disk.package_condition == "sealed"
			else Loc.t("ui.collection_cabinet_window.condition_used", "GEBRAUCHT"),
		disk.disk_count, "S" if disk.disk_count != 1 else ""]
	_detail.text = Loc.t("ui.collection_cabinet_window.color_ffaa28_b_d_s_b",
		"[color=#ffaa28][b]%d · %s[/b][/color]\n[color=#40ff60]%s[/color]\n%s · %s\nWERT [color=#50c8ff]%s[/color]  ·  ANKAUF [color=#40ff60]%s[/color]") % [
			release_year, genre, status, publisher, disk_count_text, value, sale]
	_condition_label.text = Loc.t("ui.collection_cabinet_window.zustand_s", "ZUSTAND %s") % (
		"%d%%" % disk.condition if disk.checked
		else Loc.t("ui.collection_cabinet_window.unchecked", "UNGEPRÜFT"))
	_condition_bar.value = disk.condition if disk.checked else 0
	if _atmosphere != null:
		_atmosphere.selected_slot = posmod(selection[0], 8)
		_atmosphere.queue_redraw()
	_sell_button.disabled = false
	_sell_button.text = Loc.t("ui.collection_cabinet_window.ausgewahlten_satz_verkaufen", "AUSGEWÄHLTEN SATZ VERKAUFEN")
	_confirm_action = ""
	for index in _preview_buttons.size():
		_preview_buttons[index].disabled = ["front", "back", "disks", "manual"][index] == _preview_mode
	_animate_preview()


func _set_preview_mode(mode: String) -> void:
	_preview_mode = mode if mode in ["front", "back", "disks", "manual"] else "front"
	_refresh_detail()


func _change_page(delta: int) -> void:
	var pages := maxi(1, ceili(float(_boxes.size()) / 8.0))
	_page = posmod(_page + delta, pages)
	var start := _page * 8
	_cabinet.texture = BoxComposer.cabinet_texture(_boxes.slice(start, mini(start + 8, _boxes.size())), 512)
	_page_label.text = Loc.t("ui.collection_cabinet_window.seite_d_d", "SEITE %d/%d") % [_page + 1, pages]
	_stage_meta.text = Loc.t("ui.collection_cabinet_window.vitrine_02d_d_8_facher_belegt", "VITRINE %02d · %d/8 FÄCHER BELEGT · ORIGINAL-OVP") % [
		_page + 1, mini(8, maxi(0, _boxes.size() - start))]
	if start < _boxes.size():
		_list.select(start)
		_list.ensure_current_is_visible()
		_refresh_detail()


func _on_sell_selected() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] >= _boxes.size():
		return
	var disk: Disk = _boxes[selected[0]]
	if _confirm_action != disk.uid:
		_confirm_action = disk.uid
		_sell_button.text = Loc.t("ui.collection_cabinet_window.wirklich_verkaufen_s", "WIRKLICH VERKAUFEN · +%s?") % Currency.format(CollectionMarket.set_sale_value(disk))
		return
	var result := CollectionMarket.sell_set(disk)
	if not bool(result.get("ok", false)):
		UIManager.toast(str(result.get("text", "Verkauf nicht möglich.")))


func _refresh_car_button() -> void:
	if _car_button == null:
		return
	var plan := CollectionMarket.car_plan()
	if bool(plan.get("already_owned", false)):
		_car_button.text = Loc.t("ui.collection_cabinet_window.eigenes_auto", "✓ EIGENES AUTO")
		_car_button.disabled = true
		return
	if bool(plan.get("needs_license", false)):
		var intro_known := bool(GameManager.flags.get("fuehrerschein_intro", false))
		var campaign_ready := TimeManager.year > 1993 \
			or (TimeManager.year == 1993
				and int(TimeManager.campaign_progress().get("week", 0)) >= 6)
		var can_catch_up := PlayerIdentity.age() >= 17 and campaign_ready and not intro_known \
			and not QuestManager.is_active("q_fuehrerschein") \
			and not QuestManager.is_done("q_fuehrerschein")
		if can_catch_up:
			PhoneManager.ensure_story_callback("tam_mike_lappen")
			_car_button.text = Loc.t("ui.collection_cabinet_window.auto_mike_zuruckrufen", "AUTO · MIKE ZURÜCKRUFEN")
			_car_button.tooltip_text = Loc.t("ui.collection_cabinet_window.mike_fuhrerschein_rueckruf", "Mike hat den Führerschein-Tipp. Ruf ihn am Telefon zurück oder besuche ihn; danach startet der Auftrag.")
			_car_button.disabled = false
		else:
			_car_button.text = Loc.t("ui.collection_cabinet_window.auto_erst_fuhrerschein", "AUTO · ERST FÜHRERSCHEIN")
			_car_button.tooltip_text = Loc.t("ui.collection_cabinet_window.fuhrerschein_auftrag_offen", "Erledige Mikes Führerscheinauftrag. Die Sammlung bleibt bis dahin unangetastet.")
			_car_button.disabled = true
		return
	var sets: Array = plan.get("sets", [])
	_car_button.text = Loc.t("ui.collection_cabinet_window.auto_fur_d_dm_d_ovp", "AUTO FÜR %d DM · %d OVP(s)") % [int(plan.get("price", 0)), sets.size()]
	_car_button.tooltip_text = Loc.t("ui.collection_cabinet_window.verkauft_nur_so_viele_wertvollsten_vollstandigen", "Verkauft nur so viele der wertvollsten vollständigen OVP-Sätze wie zur Finanzierung fehlen.")
	_car_button.disabled = not bool(plan.get("ok", false))


func _on_buy_car() -> void:
	var plan := CollectionMarket.car_plan()
	if bool(plan.get("needs_license", false)):
		if PlayerIdentity.age() < 17:
			UIManager.toast(Loc.t("ui.collection_cabinet_window.mike_meldet_sich_ab_17", "Mike meldet sich ab 17 mit der Führerschein-Vorbereitung."))
		elif not bool(GameManager.flags.get("fuehrerschein_intro", false)) \
				and not QuestManager.is_active("q_fuehrerschein"):
			PhoneManager.ensure_story_callback("tam_mike_lappen")
			UIManager.toast(Loc.t("ui.collection_cabinet_window.mike_jetzt_zuruckrufen", "Mike wartet auf deinen Rückruf: Telefon/Kontakte öffnen oder ihn in seinem Zimmer besuchen."))
		else:
			UIManager.toast(Loc.t("ui.collection_cabinet_window.mikes_fuhrerscheinauftrag_abschliessen", "Schließe zuerst Mikes Führerscheinauftrag ab."))
		_refresh_car_button()
		return
	if not bool(plan.get("ok", false)):
		UIManager.toast(Loc.t("ui.collection_cabinet_window.fur_auto_fehlen_noch_s_aus", "Für das Auto fehlen noch %s aus Bargeld oder verkäuflichen OVP-Sätzen.") % Currency.format(maxi(0, int(plan.get("shortage", 0)) - int(plan.get("proceeds", 0)))))
		return
	if _confirm_action != "car":
		_confirm_action = "car"
		_car_button.text = Loc.t("ui.collection_cabinet_window.bestatigen_d_ovp_s_d_dm", "BESTÄTIGEN · %d OVP(s) + %d DM") % [(plan.get("sets", []) as Array).size(), int(plan.get("price", 0))]
		return
	var result := CollectionMarket.buy_car_from_collection()
	UIManager.toast(str(result.get("text", "Autokauf nicht möglich.")))
	_refresh()


func _set_value(set_id: String) -> int:
	var total := 0
	for disk: Disk in DiskManager.disks:
		if disk.software_set_id == set_id:
			total += disk.value()
	return total


func _refresh_monitor() -> void:
	var model := RoomManager.active_device_model("monitor_model")
	var path := CollectionLayout.asset("monitor_" + model)
	if path.is_empty():
		path = CollectionLayout.asset("monitor_commodore_1084s")
	_monitor_rear.texture = RuntimeImages.texture(path, 512)
	_monitor_rear.visible = bool(GameManager.flags.get("monitor_placed", false))


func _on_model_changed(selector: String, _model_id: String) -> void:
	if selector == "monitor_model":
		_refresh_monitor()


func _layout_scene() -> void:
	if _scene == null or _scene.size.x <= 1.0:
		return
	# Vitrine steht an der bewusst freigelassenen Gegenwand. Die Monitorrueckseite
	# ragt nah und unten ins Bild: sie gehoert zum Schreibtisch ausserhalb des
	# Bildausschnitts und wirkt deshalb nicht wie ein Geraet auf dem Fussboden.
	var cabinet_rect := CollectionLayout.rect("cabinet")
	var monitor_rect := CollectionLayout.rect("monitor_" + RoomManager.active_device_model("monitor_model"))
	if monitor_rect.size == Vector2.ZERO:
		monitor_rect = CollectionLayout.rect("monitor_commodore_1084s")
	_cabinet.position = cabinet_rect.position * _scene.size
	_cabinet.size = cabinet_rect.size * _scene.size
	_monitor_rear.position = monitor_rect.position * _scene.size
	_monitor_rear.size = monitor_rect.size * _scene.size
	if _atmosphere != null:
		_atmosphere.cabinet_area = Rect2(_cabinet.position, _cabinet.size)
		_atmosphere.queue_redraw()


func _animate_preview() -> void:
	if _box_preview == null or bool(SettingsManager.value("reduced_motion")):
		return
	_box_preview.pivot_offset = _box_preview.size * 0.5
	_box_preview.modulate.a = 0.52
	_box_preview.scale = Vector2(0.965, 0.965)
	var tween := create_tween().set_parallel()
	tween.tween_property(_box_preview, "modulate:a", 1.0, 0.12)
	tween.tween_property(_box_preview, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _panel_style(bg: Color, border: Color, border_width := 1, radius := 2,
		margin_x := 6, margin_y := 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	return style


## Leise Ausstellungseffekte: warmer Lichtkegel, Randabdunklung und eine über
## das Vitrinenglas wandernde Reflexlinie. Bei „Bewegung reduzieren“ bleibt ein
## statisches, ebenso lesbares Lichtbild stehen.
class CabinetAtmosphere:
	extends Control

	var cabinet_area := Rect2()
	var selected_slot := -1
	var _phase := 0.18

	func _ready() -> void:
		set_process(not bool(SettingsManager.value("reduced_motion")))

	func _process(delta: float) -> void:
		_phase = fmod(_phase + delta * 0.055, 1.0)
		queue_redraw()

	func _draw() -> void:
		if size.x <= 1.0 or size.y <= 1.0:
			return
		# Fotografische Randabdunklung hält den Blick auf Vitrine und Exponat.
		draw_rect(Rect2(0, 0, size.x, 34), Color(0.0, 0.0, 0.0, 0.20))
		draw_rect(Rect2(0, size.y - 92, size.x, 92), Color(0.0, 0.0, 0.0, 0.17))
		draw_rect(Rect2(0, 0, 42, size.y), Color(0.0, 0.0, 0.0, 0.12))
		draw_rect(Rect2(size.x - 38, 0, 38, size.y), Color(0.0, 0.0, 0.0, 0.13))
		if cabinet_area.size == Vector2.ZERO:
			return
		var center := cabinet_area.get_center() + Vector2(0, cabinet_area.size.y * 0.02)
		for ring in range(6, 0, -1):
			var radius := cabinet_area.size.x * (0.28 + float(ring) * 0.11)
			draw_circle(center, radius, Color(1.0, 0.55, 0.18, 0.006 + float(6 - ring) * 0.004))
		# Dünner Reflex statt breitem „UI-Glow“: Er liest sich als echtes Glas.
		var glass := cabinet_area.grow(-cabinet_area.size.x * 0.17)
		if glass.size.x > 8.0 and glass.size.y > 8.0:
			var sweep_x := glass.position.x + glass.size.x * _phase
			draw_line(Vector2(sweep_x, glass.position.y),
				Vector2(sweep_x - glass.size.x * 0.10, glass.end.y),
				Color(0.72, 0.92, 1.0, 0.14), 1.2, true)
			draw_line(Vector2(sweep_x + 4.0, glass.position.y),
				Vector2(sweep_x + 4.0 - glass.size.x * 0.10, glass.end.y),
				Color(1.0, 0.78, 0.38, 0.07), 3.0, true)
		_draw_selected_exhibit()

	func _draw_selected_exhibit() -> void:
		if selected_slot < 0:
			return
		# TextureRect zentriert das 2:3-Vitrinenbild proportional in seinem
		# Layout-Rechteck. Daraus wird das tatsächlich sichtbare Bildrechteck.
		var image_rect := cabinet_area
		var image_aspect := 2.0 / 3.0
		if cabinet_area.size.x / cabinet_area.size.y < image_aspect:
			image_rect.size.y = cabinet_area.size.x / image_aspect
			image_rect.position.y += (cabinet_area.size.y - image_rect.size.y) * 0.5
		else:
			image_rect.size.x = cabinet_area.size.y * image_aspect
			image_rect.position.x += (cabinet_area.size.x - image_rect.size.x) * 0.5
		var column := selected_slot % 2
		var row := floori(selected_slot / 2.0)
		var slot := Rect2(
			image_rect.position + Vector2(0.318 + float(column) * 0.226,
				0.125 + float(row) * 0.159) * image_rect.size,
			Vector2(0.132, 0.128) * image_rect.size)
		var pulse := 0.66 + sin(_phase * TAU * 2.0) * 0.18
		var amber := Color(1.0, 0.64, 0.16, pulse)
		var corner := maxf(3.0, minf(slot.size.x, slot.size.y) * 0.25)
		for offset in [Vector2(1, 1), Vector2.ZERO]:
			var color := Color(0.0, 0.0, 0.0, 0.55) if offset != Vector2.ZERO else amber
			var width := 3.0 if offset == Vector2.ZERO else 4.5
			draw_line(slot.position + offset, slot.position + Vector2(corner, 0) + offset, color, width)
			draw_line(slot.position + offset, slot.position + Vector2(0, corner) + offset, color, width)
			draw_line(Vector2(slot.end.x, slot.position.y) + offset,
				Vector2(slot.end.x - corner, slot.position.y) + offset, color, width)
			draw_line(Vector2(slot.end.x, slot.position.y) + offset,
				Vector2(slot.end.x, slot.position.y + corner) + offset, color, width)
			draw_line(slot.end + offset, slot.end - Vector2(corner, 0) + offset, color, width)
			draw_line(slot.end + offset, slot.end - Vector2(0, corner) + offset, color, width)
			draw_line(Vector2(slot.position.x, slot.end.y) + offset,
				Vector2(slot.position.x + corner, slot.end.y) + offset, color, width)
			draw_line(Vector2(slot.position.x, slot.end.y) + offset,
				Vector2(slot.position.x, slot.end.y - corner) + offset, color, width)
