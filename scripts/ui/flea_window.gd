extends RetroWindow
## Flohmarkt als echter Produktbrowser: kompakte Warenliste, begrenzte Vorschau,
## klare Herkunft/Zustandsrisiken und getrennte Aktionen fuer Kauf und Feilschen.
## Original-Artwork bestimmt niemals die Zeilenhoehe der UI.

const DISK_COLORS := {
	"blue": Color8(55, 91, 155), "grey": Color8(116, 120, 121),
	"yellow": Color8(212, 178, 55), "red": Color8(155, 55, 50),
	"green": Color8(58, 126, 77), "black": Color8(36, 38, 40),
}
const MYSTERY_CARTON_ASSET := "res://assets/backgrounds/story_props/FLEA_MYSTERY_CARTON_CLOSED_V01.png"
const BoxComposer := preload("res://scripts/gfx/software_box_composer.gd")

var _mode := "offers"
var _entries: Array = []
var _list: ItemList
var _money: Label
var _market_state: Label
var _tab_offers: Button
var _tab_boxes: Button
var _preview: TextureRect
var _preview_mark: Label
var _detail_title: Label
var _detail_meta: Label
var _detail_seller: Label
var _detail_desc: RichTextLabel
var _price: Label
var _haggle: Button
var _buy: Button
var _status: Label
var _armed_box_id := -1


func _init() -> void:
	title = Loc.t("ui.flea_window.flohmarkt_krauses_fundstuecke", "FLOHMARKT · KRAUSES FUNDSTUECKE")
	win_size = Vector2(920, 610)


func _ready() -> void:
	var vp := get_viewport_rect().size
	win_size = Vector2(minf(940.0, vp.x - 24.0), minf(640.0, vp.y - 24.0))
	super._ready()
	position = ((vp - win_size) * 0.5).floor()
	_build_header()
	_build_tabs()
	_build_browser()
	if not FleaMarketManager.flea_changed.is_connected(_refresh):
		FleaMarketManager.flea_changed.connect(_refresh)
	if not PlayerStats.stats_changed.is_connected(_refresh_header):
		PlayerStats.stats_changed.connect(_refresh_header)
	_refresh()


func _exit_tree() -> void:
	if FleaMarketManager.flea_changed.is_connected(_refresh):
		FleaMarketManager.flea_changed.disconnect(_refresh)
	if PlayerStats.stats_changed.is_connected(_refresh_header):
		PlayerStats.stats_changed.disconnect(_refresh_header)


func _build_header() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("121c22"), Color("526d70"), 1, 6))
	content.add_child(panel)
	var margin := MarginContainer.new()
	_margins(margin, 10, 7)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(Bezel.lcd_label(Loc.t("ui.flea_window.samstag_fundstuecke_kellerkisten", "SAMSTAG · FUNDSTUECKE & KELLERKISTEN"), Palette.LCD_AMBER, 11))
	_market_state = Bezel.dim_label("", 11)
	copy.add_child(_market_state)
	_money = Bezel.lcd_label("", Palette.LCD_GREEN, 13)
	row.add_child(_money)


func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	_tab_offers = make_button(Loc.t("ui.flea_window.ware_an_den_staenden", "▦  WARE AN DEN STAENDEN"), func() -> void: _set_mode("offers"))
	_tab_boxes = make_button(Loc.t("ui.flea_window.mystery_kartons", "▣  MYSTERY-KARTONS"), func() -> void: _set_mode("boxes"))
	for button: Button in [_tab_offers, _tab_boxes]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	content.add_child(row)


func _build_browser() -> void:
	var browser := HBoxContainer.new()
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.add_theme_constant_override("separation", 9)
	content.add_child(browser)

	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", _style(Color("0a0d10"), Color("30383d"), 1, 6))
	browser.add_child(list_panel)
	var list_margin := MarginContainer.new()
	_margins(list_margin, 7, 7)
	list_panel.add_child(list_margin)
	_list = ItemList.new()
	_list.name = "MarketOfferList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(58, 58)
	_list.icon_mode = ItemList.ICON_MODE_LEFT
	_list.max_columns = 1
	_list.same_column_width = true
	_list.allow_reselect = true
	_list.add_theme_font_size_override("font_size", 13)
	_list.add_theme_constant_override("h_separation", 11)
	_list.add_theme_constant_override("v_separation", 7)
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_index: int) -> void: _on_buy())
	list_margin.add_child(_list)

	var detail_panel := PanelContainer.new()
	detail_panel.name = "MarketOfferDetail"
	detail_panel.custom_minimum_size.x = 345
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _style(Color("12171b"), Color("687778"), 1, 6))
	browser.add_child(detail_panel)
	var detail_margin := MarginContainer.new()
	_margins(detail_margin, 11, 10)
	detail_panel.add_child(detail_margin)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 6)
	detail_margin.add_child(detail)
	detail.add_child(Bezel.lcd_label(Loc.t("ui.flea_window.ware_am_stand", "WARE AM STAND"), Palette.LCD_AMBER, 12))

	var visual := PanelContainer.new()
	visual.name = "ArtworkFrame"
	visual.custom_minimum_size = Vector2(320, 215)
	visual.add_theme_stylebox_override("panel", _style(Color("07090a"), Color("343f40"), 1, 5))
	detail.add_child(visual)
	_preview = TextureRect.new()
	_preview.name = "BoundedArtwork"
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual.add_child(_preview)
	_preview_mark = Label.new()
	_preview_mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_mark.add_theme_font_size_override("font_size", 22)
	_preview_mark.add_theme_color_override("font_color", Color8(216, 181, 99))
	visual.add_child(_preview_mark)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 16)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_title)
	_detail_meta = Bezel.dim_label("", 12)
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_meta)
	_detail_seller = Bezel.dim_label("", 12)
	_detail_seller.add_theme_color_override("font_color", Color8(169, 202, 184))
	detail.add_child(_detail_seller)
	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = true
	_detail_desc.fit_content = false
	_detail_desc.scroll_active = true
	_detail_desc.custom_minimum_size.y = 78
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_desc.add_theme_font_size_override("normal_font_size", 13)
	detail.add_child(_detail_desc)
	_price = Bezel.lcd_label("", Palette.LCD_AMBER, 14)
	detail.add_child(_price)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 7)
	detail.add_child(actions)
	_haggle = make_button(Loc.t("ui.flea_window.preisgespraech", "PREISGESPRAECH"), _on_haggle)
	_haggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_haggle)
	_buy = make_button(Loc.t("ui.flea_window.kaufen", "KAUFEN"), _on_buy)
	_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_buy)
	_status = Bezel.dim_label(Loc.t("ui.flea_window.angebot_auswaehlen", "Angebot auswaehlen."), 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 30
	detail.add_child(_status)


func _set_mode(mode: String) -> void:
	if _mode == mode:
		return
	_mode = mode
	_armed_box_id = -1
	AudioManager.ui_click()
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	var keep := _selected_key()
	_entries.clear()
	_list.clear()
	var source: Array = FleaMarketManager.offers if _mode == "offers" else FleaMarketManager.boxes
	for raw: Variant in source:
		if not raw is Dictionary:
			continue
		var data: Dictionary = raw
		var entry := {"kind": "offer" if _mode == "offers" else "box", "data": data}
		_entries.append(entry)
		var icon := _entry_texture(entry)
		var text := _list_text(entry)
		_list.add_item(text, icon)
		var index := _list.item_count - 1
		_list.set_item_tooltip(index, _tooltip(entry))
		_list.set_item_metadata(index, _entry_key(entry))
	if _entries.is_empty():
		_list.add_item(Loc.t("ui.flea_window.heute_nichts_mehr_da_nnaechsten_samstag", "Heute nichts mehr da.\nNaechsten Samstag frueh wiederkommen."))
		_list.set_item_disabled(0, true)
	else:
		var select_index := 0
		for i in _entries.size():
			if _entry_key(_entries[i]) == keep:
				select_index = i
				break
		_list.select(select_index)
	_refresh_header()
	_refresh_tabs()
	_refresh_detail()


func _refresh_header() -> void:
	if _money == null:
		return
	_money.text = Loc.t("ui.flea_window.geldbeutel_s", "GELDBEUTEL  %s") % Currency.format(PlayerStats.geld)
	var changes := FleaMarketManager.last_changes.size()
	var tip := " · TIPP FUER NAECHSTE WOCHE" if not FleaMarketManager.tip.is_empty() else ""
	_market_state.text = Loc.t("ui.flea_window.d_angebote_d_kartons_d_freie", "%d Angebote · %d Kartons · %d freie Diskettenplaetze%s%s") % [
		FleaMarketManager.offers.size(), FleaMarketManager.boxes.size(), DiskManager.free_slots(),
		" · %d Veraenderungen" % changes if changes > 0 else "", tip]


func _refresh_tabs() -> void:
	_tab_offers.text = Loc.t("ui.flea_window.ware_an_den_staenden_d", "▦  WARE AN DEN STAENDEN  (%d)") % FleaMarketManager.offers.size()
	_tab_boxes.text = Loc.t("ui.flea_window.mystery_kartons_d", "▣  MYSTERY-KARTONS  (%d)") % FleaMarketManager.boxes.size()
	_tab_offers.disabled = _mode == "offers"
	_tab_boxes.disabled = _mode == "boxes"


func _on_selected(_index: int) -> void:
	_armed_box_id = -1
	_refresh_detail()


func _refresh_detail() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		_detail_title.text = Loc.t("ui.flea_window.kein_angebot_ausgewaehlt", "Kein Angebot ausgewaehlt")
		_detail_meta.text = ""
		_detail_seller.text = ""
		_detail_desc.text = Loc.t("ui.flea_window.markt_leert_sich_naechsten_samstag_gibt", "Der Markt leert sich. Naechsten Samstag gibt es neue Kisten und andere Verkaeufer.")
		_preview.texture = null
		_preview_mark.text = Loc.t("ui.flea_window.flohmarkt_nausverkauft", "FLOHMARKT\nAUSVERKAUFT")
		_price.text = ""
		_haggle.visible = false
		_buy.text = Loc.t("ui.flea_window.nichts_ausgewaehlt", "NICHTS AUSGEWAEHLT")
		_buy.disabled = true
		_status.text = ""
		return
	var data: Dictionary = entry["data"]
	var price := int(data.get("price", 0))
	_preview.texture = _entry_texture(entry)
	_preview_mark.text = Loc.t("ui.flea_window.versiegelt_n", "VERSIEGELT\n? ? ?") \
		if entry["kind"] == "box" else (
			Loc.t("ui.flea_window.loose_disk", "LOSE DISKETTE")
			if _preview.texture == null else "")
	_detail_title.text = _entry_title(entry)
	_price.text = Loc.t("ui.flea_window.preis_s", "PREIS  %s") % Currency.format(price)
	_buy.disabled = PlayerStats.geld + 0.005 < price
	if entry["kind"] == "box":
		_build_box_detail(data)
	else:
		_build_offer_detail(data)


func _build_offer_detail(offer: Dictionary) -> void:
	if str(offer.get("item_kind", "")) == "diskbox":
		_detail_seller.text = Loc.t("ui.flea_window.verkaeufer_s", "VERKAEUFER  ·  %s") % str(offer.get("seller", "Unbekannt")).to_upper()
		_detail_meta.text = Loc.t("ui.flea_window.gebraucht_12_zusaetzliche_plaetze_zustand_d", "GEBRAUCHT · 12 ZUSAETZLICHE PLAETZE · ZUSTAND %d%%") % int(offer.get("condition", 70))
		_detail_desc.text = Loc.t("ui.flea_window.rauchglasbox_mit_gebrauchsspuren_sofort_mehr_platz", "Rauchglasbox mit Gebrauchsspuren. Sofort mehr Platz für Funde.\n\n[color=#d8b668]35 DM — zehn Mark teurer als dieselbe Kapazität bei Gruber.[/color]")
		_haggle.visible = true
		_haggle.disabled = bool(offer.get("haggled", false))
		_haggle.text = Loc.t("ui.flea_window.bereits_verhandelt", "BEREITS VERHANDELT") \
			if _haggle.disabled else Loc.t("ui.flea_window.haggle", "PREISGESPRAECH")
		_buy.text = Loc.t("ui.flea_window.box_kaufen_s", "BOX KAUFEN · %s") % Currency.format(float(offer.get("price", 0)))
		_status.text = Loc.t("ui.flea_window.notkauf_am_markt_sofort_verfugbar_aber", "Notkauf am Markt: sofort verfügbar, aber teurer als im Computerladen.")
		return
	var form := str(offer.get("form", "disk"))
	var form_def: Dictionary = FleaMarketManager.SW_FORMS.get(form, {})
	_detail_seller.text = Loc.t("ui.flea_window.verkaeufer_s", "VERKAEUFER  ·  %s") % str(offer.get("seller", "Unbekannt")).to_upper()
	_haggle.visible = true
	_haggle.disabled = bool(offer.get("haggled", false))
	_haggle.text = Loc.t("ui.flea_window.bereits_verhandelt", "BEREITS VERHANDELT") \
		if _haggle.disabled else Loc.t("ui.flea_window.haggle", "PREISGESPRAECH")
	_buy.text = Loc.t("ui.flea_window.kaufen_s", "KAUFEN · %s") % Currency.format(float(offer.get("price", 0)))
	var capacity_ok := true
	if offer.has("software_id"):
		var sid := str(offer["software_id"])
		var info := SoftwareBible.entry(sid)
		var disks := SoftwareBible.disk_count(sid)
		var needed := 0 if form == "manual" else (disks if form in ["box", "disk_set"] else 1)
		capacity_ok = DiskManager.free_slots() >= needed
		_detail_meta.text = Loc.t("ui.flea_window.s_s_s_s", "%s · %s · %s · %s") % [str(form_def.get("label", "Original")).to_upper(),
			info.get("platform", "Amiga"), info.get("release_year", "?"), _disk_text(disks)]
		var original_code := "LILA AAA-ORIGINALSATZ" if str(info.get("production_tier", "standard")).to_lower() == "aaa" else "ROTER MASTERSATZ"
		var used_line := ("GEBRAUCHT · VOLLSTAENDIGER %s · ZUSTAND %d%%" % [original_code, int(offer.get("condition", 70))] if form == "disk_set" else
			("GEBRAUCHT · OVP-ZUSTAND %d%%" % int(offer.get("condition", 70)) if form == "box" else "GEBRAUCHT · ZUSTAND UNGEPRUEFT"))
		_detail_desc.text = Loc.t("ui.flea_window.b_s_b_s_n_s", "[b]%s[/b] · %s\n%s\n\n[color=#d8b668]%s[/color] — Funktion erst zu Hause pruefbar.") % [
			info.get("developer", "Unbekannter Entwickler"), info.get("publisher", "Unbekannter Verlag"),
			str(info.get("genre", "Computerspiel")), used_line]
	else:
		var tpl: Dictionary = DiskManager.templates.get(str(offer.get("template_id", "")), {})
		capacity_ok = DiskManager.free_slots() >= 1
		_detail_meta.text = Loc.t("ui.flea_window.lose_diskette_s_s", "LOSE DISKETTE · %s · %s") % [str(tpl.get("type", "DD")), str(tpl.get("rarity", "common")).to_upper()]
		_detail_desc.text = Loc.t("ui.flea_window.s_n_n_color_d8b668_zustand", "%s\n\n[color=#d8b668]ZUSTAND UNGEPRUEFT[/color] — Lesefehler und Inhalt werden erst am eigenen Amiga sichtbar.") % str(tpl.get("notes", offer.get("note", "Gebrauchte Diskette vom Flohmarkt.")))
	var gate: Dictionary = FleaMarketManager.purchase_gate(offer)
	capacity_ok = bool(gate.get("ok", false))
	_buy.disabled = _buy.disabled or not capacity_ok
	_status.text = (Loc.t("ui.flea_window.no_disk_space",
		"Kein Platz in deiner Diskettenbox.") if not capacity_ok else
		(Loc.t("ui.flea_window.already_haggled_today",
			"Der Preis wurde heute bereits verhandelt.")
			if bool(offer.get("haggled", false)) else
			Loc.t("ui.flea_window.purchase_final",
				"Kaufen ist endgueltig. Technischer Zustand bleibt Flohmarktrisiko.")))


func _build_box_detail(box: Dictionary) -> void:
	_haggle.visible = false
	_detail_seller.text = Loc.t("ui.flea_window.verkaeufer_kistenstand_am_mittelgang", "VERKAEUFER  ·  KISTENSTAND AM MITTELGANG")
	_detail_meta.text = Loc.t("ui.flea_window.versiegelter_karton_inhalt_unbekannt_risikokauf", "VERSIEGELTER KARTON · INHALT UNBEKANNT · RISIKOKAUF")
	var kind := str(box.get("kind", "alles"))
	var promise: String = str({
		"disketten": Loc.t("ui.flea_window.box_disks",
			"Beschriftete und unbeschriftete Disketten, Huellen — oder nur Ausschuss."),
		"computerkram": Loc.t("ui.flea_window.box_computer_stuff",
			"Kabel, Hefte, Zubehoer und Datentraeger. Nichts wurde getestet."),
		"alles": Loc.t("ui.flea_window.box_everything",
			"Der grosse Kellerfund: mehr Teile, hoehere Schatzchance, ebenso mehr Ramsch."),
	}.get(kind, Loc.t("ui.flea_window.box_unknown",
		"Niemand weiss, was unter dem zugeklebten Deckel liegt.")))
	_detail_desc.text = Loc.t("ui.flea_window.s_n_n_color_e7a65f_erst", "%s\n\n[color=#e7a65f]Erst bezahlen, dann vor Ort oeffnen. Keine Rueckgabe.[/color]") % promise
	_buy.text = (Loc.t("ui.flea_window.really_open", "WIRKLICH OEFFNEN · %s")
		if _armed_box_id == int(box.get("id", -1))
		else Loc.t("ui.flea_window.buy_box", "KARTON KAUFEN · %s")
		) % Currency.format(float(box.get("price", 0)))
	_status.text = Loc.t("ui.flea_window.zweimal_bestaetigen_inhalt_wird_erst_nach", "Zweimal bestaetigen: Der Inhalt wird erst nach dem Kauf ausgewuerfelt.")


func _on_haggle() -> void:
	var entry := _selected_entry()
	if entry.is_empty() or entry.get("kind", "") != "offer":
		return
	var offer: Dictionary = entry["data"]
	if bool(offer.get("haggled", false)):
		UIManager.toast(Loc.t("ui.flea_window.ueber_dieses_angebot_wurde_heute_schon", "Ueber dieses Angebot wurde heute schon verhandelt."))
		return
	UIManager.open_bargain(int(offer.get("id", -1)))


func _on_buy() -> void:
	var entry := _selected_entry()
	if entry.is_empty():
		UIManager.toast(Loc.t("ui.flea_window.erst_angebot_auswaehlen", "Erst ein Angebot auswaehlen."))
		return
	var data: Dictionary = entry["data"]
	var result: Dictionary
	if entry["kind"] == "box":
		var id := int(data.get("id", -1))
		if _armed_box_id != id:
			_armed_box_id = id
			_status.text = Loc.t("ui.flea_window.letzte_kontrolle_noch_einmal_klicken_dann", "Letzte Kontrolle: Noch einmal klicken, dann wird bezahlt und der Karton geoeffnet.")
			AudioManager.minigame_cue("flea_market", &"warning")
			_refresh_detail()
			return
		result = FleaMarketManager.buy_box(id)
		_armed_box_id = -1
		if bool(result.get("ok", false)):
			var head := "VOLLTREFFER" if bool(result.get("jackpot", false)) else "KARTON GEOEFFNET"
			UIManager.open_info(head, "Gefunden:\n• " + "\n• ".join(result.get("lines", [])))
	else:
		result = FleaMarketManager.buy_offer(int(data.get("id", -1)))
	UIManager.toast(str(result.get("text", "Kauf abgeschlossen.")))
	AudioManager.play("cash_register" if bool(result.get("ok", false)) else "phone_busy", 0.0)
	_refresh()
	if bool(result.get("ok", false)) and str(result.get("tutorial", "")) == "space_copy":
		UIManager.open_copy_tutorial("acquired")


func _selected_entry() -> Dictionary:
	var selected := _list.get_selected_items()
	if selected.is_empty() or selected[0] < 0 or selected[0] >= _entries.size():
		return {}
	return _entries[selected[0]]


func _selected_key() -> String:
	var entry := _selected_entry() if _list != null else {}
	return _entry_key(entry) if not entry.is_empty() else ""


func _entry_key(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	return "%s:%d" % [entry.get("kind", ""), int((entry.get("data", {}) as Dictionary).get("id", -1))]


func _entry_title(entry: Dictionary) -> String:
	var data: Dictionary = entry["data"]
	return ("Mystery-Karton · %s" % data.get("label", "Kellerfund")) if entry["kind"] == "box" \
		else FleaMarketManager.offer_name(data)


func _list_text(entry: Dictionary) -> String:
	var data: Dictionary = entry["data"]
	var line_title := _entry_title(entry)
	if entry["kind"] == "box":
		return "%s  ·  VERSIEGELT  ·  %s" % [line_title, Currency.format(float(data.get("price", 0)))]
	var state := "VERHANDELT" if bool(data.get("haggled", false)) else "ZUSTAND ?"
	return "%s  ·  %s  ·  %s  ·  %s" % [line_title, data.get("seller", "?"), state,
		Currency.format(float(data.get("price", 0)))]


func _tooltip(entry: Dictionary) -> String:
	return "Doppelklick: kaufen · %s" % ("Inhalt bleibt bis zum Oeffnen unbekannt." if entry["kind"] == "box" \
		else "Gebrauchtware erst zu Hause pruefen.")


func _entry_texture(entry: Dictionary) -> Texture2D:
	var data: Dictionary = entry["data"]
	if entry["kind"] == "box":
		return load(MYSTERY_CARTON_ASSET) as Texture2D
	if data.has("software_id"):
		var form := str(data.get("form", "disk"))
		if form in ["disk", "disk_set"]:
			var info := SoftwareBible.entry(str(data["software_id"]))
			var collection_color := "purple" if str(info.get("production_tier", "standard")).to_lower() == "aaa" else "red"
			return DiskComposer.composed_disk(str(data["software_id"]), true, 256,
				int(data.get("disk_number", 1)), collection_color)
		if form == "box":
			return BoxComposer.box_texture(str(data["software_id"]), "used", 384)
		var art := SoftwareBible.acquisition_art(str(data["software_id"]), form)
		return art.get("texture") as Texture2D
	if str(data.get("item_kind", "")) == "diskbox":
		return load("res://assets/backgrounds/layers/DISKBOX_12_SMOKED_V02.png") as Texture2D
	var tpl: Dictionary = DiskManager.templates.get(str(data.get("template_id", "")), {})
	var color_name := "red" if str(tpl.get("content_type", "")) == "spiel" else str(tpl.get("color", "blue"))
	return Sprites.disk_icon(DISK_COLORS.get(color_name, Palette.BLUE_MID))


func _disk_text(count: int) -> String:
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
