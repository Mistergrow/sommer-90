class_name DealerWindow
extends RetroWindow
## DER HÄNDLER — ein physisches Koffergeschäft statt Datenbankliste.
## Zwei klare Wege: wenige geprüfte Stücke kaufen oder beliebige eigene
## Spielkopien verkaufen. Ein Satz liegt zur Einzelprüfung auf dem Filz; optional
## nimmt der Händler alle verkaufsfähigen Sätze als transparent bewertetes Lot.

const DEALER_ART := preload("res://assets/backgrounds/story_props/DEALER_WITH_TEST_RIG_V01.png")
const COL_GREEN := Color(0.34, 1.0, 0.49)
const COL_AMBER := Color(1.0, 0.72, 0.22)
const COL_RED := Color(1.0, 0.34, 0.27)
const COL_BLUE := Color(0.28, 0.66, 1.0)
const FELT := Color(0.025, 0.105, 0.075, 0.98)

enum TradeMode { BUY, SELL }

var _mode := TradeMode.BUY
var _selection := 0
var _last_result := ""
var _transacting := false


func _init() -> void:
	title = Loc.t("ui.dealer_window.handler_kofferverkauf", "DER HÄNDLER · KOFFERVERKAUF")
	win_size = Vector2(1020, 560)


func _ready() -> void:
	super._ready()
	if not DealerManager.dealer_changed.is_connected(_rebuild):
		DealerManager.dealer_changed.connect(_rebuild)
	if not DiskManager.disks_changed.is_connected(_rebuild):
		DiskManager.disks_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	if content == null or _transacting:
		return
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	content.add_theme_constant_override("separation", 8)
	_build_header()
	_build_mode_switch()
	if _mode == TradeMode.BUY:
		_build_buy_scene()
	else:
		_build_sell_scene()


func _build_header() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 70
	panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.025, 0.04, 0.055, 0.98), Color(0.18, 0.48, 0.73), 2, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 2)
	row.add_child(identity)
	var kicker := Bezel.dim_label(Loc.t("ui.dealer_window.diskret_barzahlung_kein_umtausch", "DISKRET · BARZAHLUNG · KEIN UMTAUSCH"), 11)
	kicker.add_theme_color_override("font_color", COL_BLUE)
	identity.add_child(kicker)
	identity.add_child(Bezel.lcd_label(DealerManager.dealer_name().to_upper(), COL_AMBER, 19))
	identity.add_child(_wrapped("»Ich nehme jeden Titel, der sauber läuft. Zustand, Etikett und Menge machen den Preis.«", 10, Palette.UI_TEXT))

	var trust_col := VBoxContainer.new()
	trust_col.custom_minimum_size.x = 220
	trust_col.add_child(Bezel.dim_label(Loc.t("ui.dealer_window.vertrauen_d_100", "VERTRAUEN  %d / 100") % DealerManager.trust, 11))
	var trust_bar := Bezel.bar(COL_GREEN, Vector2(220, 12))
	trust_bar.value = clampi(DealerManager.trust, 0, 100)
	trust_col.add_child(trust_bar)
	row.add_child(trust_col)
	row.add_child(_badge("%05.2f DM" % PlayerStats.geld, COL_GREEN))
	row.add_child(_badge("%d PLÄTZE FREI" % DiskManager.free_slots(), COL_BLUE))
	content.add_child(panel)


func _build_mode_switch() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var offers := DealerManager.stock_offers()
	var candidates := DealerManager.candidate_disks()
	var buy := _trade_tab("AUS SEINEM KOFFER  ·  %d STÜCK" % offers.size(),
		_mode == TradeMode.BUY, _set_mode.bind(TradeMode.BUY))
	var sell := _trade_tab("DEINE KOPIEN ANBIETEN  ·  %d SÄTZE" % candidates.size(),
		_mode == TradeMode.SELL, _set_mode.bind(TradeMode.SELL))
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(buy)
	row.add_child(sell)


func _build_buy_scene() -> void:
	var offers := DealerManager.stock_offers()
	if offers.is_empty():
		_build_empty_stage("DER KOFFER IST FÜR HEUTE LEER",
			"»Mehr hatte ich nicht dabei. Morgen sieht die Sache vielleicht anders aus.«", COL_AMBER)
		_build_footer(null, "NICHTS MEHR ZU KAUFEN", false, "")
		return
	_selection = clampi(_selection, 0, offers.size() - 1)
	var offer: Dictionary = offers[_selection]
	var gate := DealerManager.purchase_status(offer)
	var kind := str(offer.get("kind", "scene_source"))
	var origin := "GEBRAUCHTES ORIGINAL" if kind == "used_original" else (
		"BYTEWERK-SZENEQUELLE" if bool(offer.get("bytewerk", false)) else "GEPRÜFTE SZENEQUELLE")
	var accent := Color(0.86, 0.72, 0.25) if bool(offer.get("bytewerk", false)) else (
		Color(0.75, 0.44, 0.92) if _offer_is_aaa(offer) and kind == "used_original" else COL_GREEN)
	var speech := _last_result if not _last_result.is_empty() else \
		"»%s. Läuft auf meinem Prüfgerät. Die Quelle bleibt danach bei dir.«" % origin.capitalize()
	var details := "%s  ·  %d DISKETTE(N)  ·  GEPRÜFT %d%%" % [
		origin, int(offer.get("disk_count", 1)), int(offer.get("condition", 0))]
	_build_trade_stage(str(offer.get("title", "Unbekannter Titel")), details,
		_stock_texture(offer), accent, speech, "%d DM" % int(offer.get("price", 0)))
	_build_selector(_selection, offers.size())
	var status_text := str(gate.get("text", ""))
	_build_footer(_purchase.bind(str(offer.get("id", ""))),
		"KAUFEN · %d DM" % int(offer.get("price", 0)), bool(gate.get("ok", false)), status_text)


func _build_sell_scene() -> void:
	var candidates := DealerManager.candidate_disks()
	if candidates.is_empty():
		_build_empty_stage("KEINE SPIELKOPIE AUF DEM FILZ",
			"»Der Titel ist mir egal. Zieh mit X-COPY eine eigene lauffähige Spielkopie — dann bewerte ich Zustand und Etikett.«",
			COL_GREEN)
		_build_footer(_open_diskbox, "DISKETTENBOX ÖFFNEN", true,
			"Originale und gekaufte Quelldisks bleiben immer bei dir; verkauft werden nur eigene Kopien.")
		return
	_selection = clampi(_selection, 0, candidates.size() - 1)
	var disk: Disk = candidates[_selection]
	var status := DealerManager.delivery_status(disk)
	var deliverable := bool(status.get("ok", false))
	var pay := DealerManager.pay_breakdown(disk)
	var accent := COL_GREEN if deliverable else COL_RED
	var disk_count := int(pay.get("disk_count", maxi(1, disk.disk_count)))
	var source_text := ("EIGENER KOPIENSATZ · %d DISKETTEN" % disk_count \
		if disk_count > 1 else "EIGENE KOPIE · GENERATION %d" % maxi(1, disk.copy_generation)) if disk.is_player_made_copy() \
		else "GEKAUFTE QUELLDISK · BLEIBT BEI DIR"
	var condition := "%d%% ZUSTAND" % int(pay.get("condition_percent", disk.condition)) \
		if disk.checked else "ZUSTAND WIRD GEPRÜFT"
	var details := "%s  ·  ETIKETT %s  ·  %s" % [source_text,
		CultureManager.label_stage_name(disk.label_quality).to_upper(), condition]
	var speech := _last_result if not _last_result.is_empty() else (
		"»Saubere Kopie. Ich prüfe sie, dann liegt das Geld auf dem Tisch.«" if deliverable else
		"»Die nehme ich nicht. %s«" % str(status.get("text", "Erst vorbereiten.")))
	var price_text := "%d DM" % int(pay.get("total", 0)) if deliverable else "KEIN DEAL"
	_build_trade_stage(disk.display_name(), details, _disk_texture(disk), accent, speech, price_text)
	_build_selector(_selection, candidates.size())
	var explanation := ("%d Grund/Satz + %d Etikett + %d Zustand + %d Vertrauen" % [
			int(pay.get("base", 0)), int(pay.get("label", 0)), int(pay.get("condition", 0)),
			int(pay.get("trust", 0))]) if deliverable else str(status.get("text", "Nicht lieferbereit."))
	var bulk := DealerManager.bulk_quote()
	_build_sell_footer(_deliver.bind(disk), "SATZ ÜBERGEBEN · %d DM" % int(pay.get("total", 0)) if deliverable \
		else "NICHT VERKÄUFLICH", deliverable, explanation, bulk)


func _build_trade_stage(item_title: String, details: String, texture: Texture2D,
		accent: Color, speech: String, price_text: String) -> void:
	var stage := PanelContainer.new()
	stage.name = "PhysicalTradeStage"
	stage.custom_minimum_size.y = 278
	stage.add_theme_stylebox_override("panel", _panel_style(FELT, accent.darkened(0.35), 2, 14))
	content.add_child(stage)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	stage.add_child(row)

	var ware_frame := PanelContainer.new()
	ware_frame.custom_minimum_size = Vector2(300, 242)
	ware_frame.add_theme_stylebox_override("panel", _panel_style(
		Color(0.018, 0.025, 0.022, 0.95), accent, 3, 10))
	row.add_child(ware_frame)
	var ware := TextureRect.new()
	ware.texture = texture
	ware.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ware.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ware.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ware_frame.add_child(ware)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 10)
	row.add_child(info)
	var kicker := Bezel.dim_label(Loc.t("ui.dealer_window.auf_dem_filz_einzelstuck", "AUF DEM FILZ · EINZELSTÜCK"), 11)
	kicker.add_theme_color_override("font_color", accent)
	info.add_child(kicker)
	var title_label := Bezel.lcd_label(item_title.to_upper(), Palette.UI_TEXT, 20)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.y = 48
	info.add_child(title_label)
	info.add_child(_wrapped(details, 11, accent))
	var divider := HSeparator.new()
	info.add_child(divider)
	var quote_panel := PanelContainer.new()
	quote_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quote_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.025, 0.028, 0.032, 0.92), Color(0.23, 0.29, 0.31), 1, 10))
	var quote := _wrapped(speech, 12, Palette.UI_TEXT)
	quote.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quote_panel.add_child(quote)
	info.add_child(quote_panel)
	info.add_child(Bezel.lcd_label(price_text, COL_AMBER, 24))

	var actor_frame := PanelContainer.new()
	actor_frame.custom_minimum_size = Vector2(150, 242)
	actor_frame.add_theme_stylebox_override("panel", _panel_style(
		Color(0.018, 0.021, 0.024, 0.90), Color(0.32, 0.29, 0.36), 1, 4))
	row.add_child(actor_frame)
	var actor := TextureRect.new()
	actor.texture = DEALER_ART
	actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	actor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	actor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	actor_frame.add_child(actor)


func _build_empty_stage(headline: String, speech: String, accent: Color) -> void:
	_build_trade_stage(headline, "KEINE WARE AUF DEM FILZ", null, accent, speech, "—")


func _build_selector(index: int, amount: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var previous := make_button(Loc.t("ui.dealer_window.vorheriges_stuck", "<  VORHERIGES STÜCK"), _move_selection.bind(-1))
	previous.disabled = amount <= 1
	previous.custom_minimum_size = Vector2(190, 34)
	row.add_child(previous)
	var position_label := Bezel.lcd_label(Loc.t("ui.dealer_window.stuck_d_von_d", "STÜCK %d VON %d") % [index + 1, amount], Palette.UI_TEXT, 12)
	position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	position_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	position_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(position_label)
	var next := make_button(Loc.t("ui.dealer_window.nachstes_stuck", "NÄCHSTES STÜCK  >"), _move_selection.bind(1))
	next.disabled = amount <= 1
	next.custom_minimum_size = Vector2(190, 34)
	row.add_child(next)


func _build_footer(callback: Variant, action_text: String, enabled: bool, status_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var status := _wrapped(status_text, 10, COL_GREEN if enabled else COL_RED)
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status)
	var action := make_button(action_text, callback if callback is Callable else func() -> void: pass)
	action.name = "PrimaryTradeAction"
	action.disabled = not enabled
	action.custom_minimum_size = Vector2(330, 42)
	row.add_child(action)


func _build_sell_footer(callback: Variant, action_text: String, enabled: bool,
		status_text: String, bulk: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var status := _wrapped(status_text, 9, COL_GREEN if enabled else COL_RED)
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status)
	var quantity := int(bulk.get("quantity", 0))
	if quantity >= 2:
		var bulk_text := "ALLE %d SÄTZE · %d DM" % [quantity, int(bulk.get("total", 0))]
		var bonus := int(bulk.get("bonus", 0))
		if bonus > 0:
			bulk_text += "  (+%d)" % bonus
		var lot_action := make_button(bulk_text, _deliver_all)
		lot_action.name = "BulkTradeAction"
		lot_action.tooltip_text = Loc.t("ui.dealer_window.d_dm_einzelpreise_d_dm_mengenbonus", "%d DM Einzelpreise + %d DM Mengenbonus (%d %%)") % [
			int(bulk.get("subtotal", 0)), bonus, int(bulk.get("bonus_rate", 0))]
		lot_action.custom_minimum_size = Vector2(275, 42)
		row.add_child(lot_action)
	var action := make_button(action_text, callback if callback is Callable else func() -> void: pass)
	action.name = "PrimaryTradeAction"
	action.disabled = not enabled
	action.custom_minimum_size = Vector2(285, 42)
	row.add_child(action)


func _trade_tab(text_value: String, active: bool, callback: Callable) -> Button:
	var button := make_button(text_value, callback)
	button.custom_minimum_size.y = 40
	var normal := _panel_style(Color(0.035, 0.05, 0.065, 1.0),
		COL_AMBER if active else Color(0.20, 0.28, 0.34), 2 if active else 1, 7)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_color_override("font_color", COL_AMBER if active else Palette.UI_TEXT_DIM)
	return button


func _set_mode(mode: TradeMode) -> void:
	_mode = mode
	_selection = 0
	_last_result = ""
	AudioManager.ui_click()
	_rebuild()


func _move_selection(delta: int) -> void:
	var amount := DealerManager.stock_offers().size() if _mode == TradeMode.BUY \
		else DealerManager.candidate_disks().size()
	if amount <= 0:
		return
	_selection = posmod(_selection + delta, amount)
	_last_result = ""
	AudioManager.ui_click()
	_rebuild()


func _purchase(offer_id: String) -> void:
	_transacting = true
	var result := DealerManager.purchase(offer_id)
	_transacting = false
	_last_result = str(result.get("text", ""))
	UIManager.toast(_last_result)
	_selection = 0
	_rebuild()


func _deliver(disk: Disk) -> void:
	_transacting = true
	var result := DealerManager.deliver(disk)
	_transacting = false
	_last_result = str(result.get("text", ""))
	UIManager.toast(_last_result)
	_selection = 0
	_rebuild()


func _deliver_all() -> void:
	_transacting = true
	var result := DealerManager.deliver_all()
	_transacting = false
	_last_result = str(result.get("text", ""))
	UIManager.toast(_last_result)
	_selection = 0
	_rebuild()


func _open_diskbox() -> void:
	UIManager.open_diskbox()


func _offer_is_aaa(offer: Dictionary) -> bool:
	var info := SoftwareBible.entry(str(offer.get("software_id", "")))
	return str(info.get("production_tier", "standard")).to_lower() == "aaa"


func _stock_texture(offer: Dictionary) -> Texture2D:
	var body := "yellow" if bool(offer.get("bytewerk", false)) else (
		"purple" if str(offer.get("kind", "")) == "used_original" and _offer_is_aaa(offer) else "red")
	return DiskComposer.composed_disk(str(offer.get("software_id", "")), true, 320, 1, body)


func _disk_texture(disk: Disk) -> Texture2D:
	if not disk.sticker_data.is_empty():
		return DiskComposer.composed_custom(disk.sticker_data, 320, disk.color)
	if not disk.software_id.is_empty():
		return DiskComposer.composed_disk(disk.software_id, disk.label_quality >= 2,
			320, disk.disk_number, disk.color)
	return DiskComposer.master_texture(disk.color)


func _badge(text_value: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(
		Color(color.r, color.g, color.b, 0.08), Color(color.r, color.g, color.b, 0.62), 1, 7))
	var label := Bezel.lcd_label(text_value, color, 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _panel_style(background: Color, border: Color, width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


func _wrapped(text_value: String, font_size: int, color: Color) -> Label:
	var label := Bezel.dim_label(text_value, font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
