class_name BargainMinigame
extends RetroWindow
## Kompaktes Preisgespräch für genau ein persistentes Flohmarktangebot.
## Ware, Verkäufer und Ergebnis stammen aus dem echten Marktbestand; die Bühne
## enthält keine generischen Platzhalter mehr.

const Model := preload("res://scripts/minigames/bargain_model.gd")
const DepthRig := preload("res://scripts/ui/minigame_depth_rig.gd")

const ARCHETYPE_LABELS := {
	&"collector": "SAMMLER",
	&"parent": "KELLERFUND",
	&"dealer": "PROFIHÄNDLER",
	&"casual_seller": "PRIVATVERKÄUFER",
}
const CARD_HELP := {
	&"inspect": "Ungeprüften Zustand und dein Kaufrisiko ansprechen.",
	&"rapport": "Wirkt erst, wenn du auf dem Markt bereits einen Namen hast.",
	&"bundle": "Interesse an mehreren Fundstücken signalisiert einen schnellen Abschluss.",
	&"silence": "Nach einem guten Einstieg kann bewusstes Schweigen Druck erzeugen.",
	&"cash": "Bargeld überzeugt besonders nach dem ersten Argument.",
	&"pressure": "Ein harter Preis braucht hohen Ruf und ausreichend Geduld.",
}

var offer_id := -1
var _offer: Dictionary
var _model: BargainModel
var _table: BargainTable
var _status: Label
var _price: Label
var _patience: Label
var _mood: Label
var _context_title: Label
var _context_meta: Label
var _hint_button: Button
var _accept_button: Button
var _leave_button: Button
var _buttons: Dictionary = {}
var _recommended: StringName = &""
var _finished := false


func _init() -> void:
	title = Loc.t("ui.bargain_minigame.flohmarkt_preisgesprach", "FLOHMARKT · PREISGESPRÄCH")
	win_size = Vector2(920, 515)


static func can_start(id: int) -> Dictionary:
	var offer := FleaMarketManager.offer_by_id(id)
	if offer.is_empty():
		return {"ok": false, "reason": Loc.t("ui.bargain_minigame.angebot_ist_nicht_mehr_da", "Das Angebot ist nicht mehr da.")}
	if bool(offer.get("haggled", false)):
		return {"ok": false, "reason": Loc.t("ui.bargain_minigame.uber_dieses_angebot_wurde_heute_bereits", "Über dieses Angebot wurde heute bereits verhandelt.")}
	return {"ok": true, "reason": ""}


func _ready() -> void:
	super._ready()
	_offer = FleaMarketManager.offer_by_id(offer_id)
	if _offer.is_empty():
		queue_free()
		return
	var wins := int(MinigameManager.record("bargain").get("wins", 0))
	_model = Model.new()
	_model.configure(clampi(1 + floori(wins / 2.0), 1, 5),
		hash("FLEA/%d/%d" % [TimeManager.day_counter, offer_id]),
		str(_offer.get("seller", "Unbekannt")), int(_offer.get("price", 1)),
		PlayerStats.ruf, not bool(_offer.get("checked", false)))
	_build_ui()


func _build_ui() -> void:
	var context := PanelContainer.new()
	context.name = "NegotiationContext"
	context.custom_minimum_size.y = 40
	context.add_theme_stylebox_override("panel", _panel_style(
		Color8(12, 24, 27), Color8(62, 83, 84), 8))
	content.add_child(context)
	var context_row := HBoxContainer.new()
	context_row.add_theme_constant_override("separation", 12)
	context.add_child(context_row)
	var context_text := VBoxContainer.new()
	context_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_text.add_theme_constant_override("separation", 0)
	context_row.add_child(context_text)
	_context_title = Bezel.lcd_label(_offer_title().to_upper(), Palette.LCD_AMBER, 13)
	context_text.add_child(_context_title)
	_context_meta = Bezel.dim_label(_offer_meta(), 11)
	context_text.add_child(_context_meta)
	var risk := Bezel.lcd_label(Loc.t("ui.bargain_minigame.zustand_ungepruft", "ZUSTAND UNGEPRÜFT"), Color8(232, 166, 91), 10)
	risk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	context_row.add_child(risk)

	_table = BargainTable.new()
	_table.name = "BargainTable25D"
	_table.model = _model
	_table.seller_portrait = _seller_portrait()
	_table.ware_texture = _offer_texture()
	_table.offer_title = _offer_title()
	_table.offer_subtitle = _offer_visual_subtitle()
	_table.custom_minimum_size = Vector2(884, 218)
	content.add_child(_table)
	var rig := DepthRig.new()
	_table.add_child(rig)
	rig.configure(_table, 0.48)

	var cards := GridContainer.new()
	cards.name = "ArgumentCards"
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 6)
	content.add_child(cards)
	for card: StringName in Model.CARDS:
		var button := make_button(str(Model.LABELS[card]), _play.bind(card))
		button.name = "Argument_%s" % card
		button.custom_minimum_size = Vector2(286, 38)
		button.tooltip_text = str(CARD_HELP[card])
		cards.add_child(button)
		_buttons[card] = button

	var decision := HBoxContainer.new()
	decision.name = "NegotiationDecision"
	decision.custom_minimum_size.y = 44
	decision.add_theme_constant_override("separation", 8)
	content.add_child(decision)
	var telemetry := PanelContainer.new()
	telemetry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry.add_theme_stylebox_override("panel", _panel_style(
		Color8(9, 14, 15), Color8(48, 60, 60), 7))
	decision.add_child(telemetry)
	var telemetry_col := VBoxContainer.new()
	telemetry_col.add_theme_constant_override("separation", 0)
	telemetry.add_child(telemetry_col)
	_price = Bezel.lcd_label("", Palette.LCD_AMBER, 11)
	telemetry_col.add_child(_price)
	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 14)
	telemetry_col.add_child(state_row)
	_patience = Bezel.dim_label("", 11)
	_patience.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_row.add_child(_patience)
	_mood = Bezel.dim_label("", 11)
	state_row.add_child(_mood)

	_leave_button = make_button(Loc.t("ui.bargain_minigame.ohne_deal_raus", "OHNE DEAL RAUS"), queue_free)
	_leave_button.custom_minimum_size = Vector2(132, 44)
	_leave_button.tooltip_text = Loc.t("ui.bargain_minigame.preisgesprach_ohne_kauf_verlassen", "Preisgespräch ohne Kauf verlassen.")
	decision.add_child(_leave_button)
	_hint_button = make_button(Loc.t("ui.bargain_minigame.handler_lesen_100_p", "HÄNDLER LESEN  (-100 P.)"), _hint)
	_hint_button.custom_minimum_size = Vector2(170, 44)
	_hint_button.tooltip_text = Loc.t("ui.bargain_minigame.markiert_momentan_starkste_argument_kostet_100", "Markiert das momentan stärkste Argument. Kostet 100 Wertungspunkte.")
	decision.add_child(_hint_button)
	_accept_button = make_button(Loc.t("ui.bargain_minigame.deal_abschliessen_zahlen", "DEAL ABSCHLIESSEN & ZAHLEN"), _accept)
	_accept_button.custom_minimum_size = Vector2(245, 44)
	decision.add_child(_accept_button)

	var status_panel := PanelContainer.new()
	status_panel.name = "NegotiationFeedback"
	status_panel.custom_minimum_size.y = 46
	status_panel.add_theme_stylebox_override("panel", _panel_style(
		Color8(6, 13, 14), Color8(46, 73, 69), 8))
	content.add_child(status_panel)
	_status = Bezel.lcd_label(
		Loc.t("ui.bargain_minigame.wahle_argument_oder_akzeptiere_den_aktuellen", "Wähle ein Argument oder akzeptiere den aktuellen Preis. Kein Zeitdruck."),
		Palette.LCD_GREEN, 10)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_panel.add_child(_status)
	_refresh()


func _panel_style(background: Color, border: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _play(card: StringName) -> void:
	if _finished or _model.closed:
		return
	_recommended = &""
	var result := _model.play(card)
	_status.text = str(result.get("text", ""))
	_status.add_theme_color_override("font_color",
		Palette.LCD_GREEN if bool(result.get("ok", false)) else Color8(238, 156, 89))
	_refresh()
	AudioManager.play("haggle", 0.0)
	if _model.closed and _model.patience <= 0:
		_status.text += "  Das Angebot bleibt beim bisherigen Preis."
		_status.add_theme_color_override("font_color", Palette.RED)


func _hint() -> void:
	if _finished or _model.closed:
		return
	_recommended = _model.hint()
	_status.text = Loc.t("ui.bargain_minigame.beobachtung_s_passt_gerade_am_besten", "Beobachtung: „%s“ passt gerade am besten. Eine Hilfe kostet 100 Punkte.") \
		% Model.LABELS[_recommended]
	_status.add_theme_color_override("font_color", Color8(135, 205, 229))
	_refresh()


func _accept() -> void:
	if _finished or _model.closed:
		return
	var run_id := "%d:%d:%d" % [TimeManager.day_counter, offer_id, _model.run_seed]
	var result := FleaMarketManager.settle_negotiation(
		offer_id, run_id, _model.price, _model.details())
	if not bool(result.get("ok", false)):
		_status.text = str(result.get("text", "Deal und Übergabe konnten nicht abgeschlossen werden."))
		_status.add_theme_color_override("font_color", Palette.RED)
		_refresh()
		return
	_model.accept()
	_finished = true
	var score := _model.score()
	MinigameManager.finish("bargain", true, score, _model.details())
	AudioManager.play("cash_register", 0.0)
	# Die Übergabe ist bereits Teil dieses Handschlags. Nach einem erfolgreichen
	# Commit gibt es in diesem Fenster nichts mehr zu bestätigen.
	UIManager.close_window("win_bargain")
	if str(result.get("tutorial", "")) == "space_copy":
		UIManager.call_deferred("open_copy_tutorial", "acquired")


func _refresh() -> void:
	var savings := _model.original_price - _model.price
	var profile := str(ARCHETYPE_LABELS.get(_model.archetype, "VERKÄUFER"))
	_price.text = Loc.t("ui.bargain_minigame.s_start_d_dm_jetzt_d", "%s · START %d DM  →  JETZT %d DM  ·  ERSPARNIS %d DM") % [
		profile, _model.original_price, _model.price, savings]
	var patience_now := maxi(0, _model.patience)
	_patience.text = Loc.t("ui.bargain_minigame.geduld_s_s_d", "GEDULD  %s%s  %d") % [
		"■".repeat(patience_now), "□".repeat(maxi(0, 7 - patience_now)), patience_now]
	_mood.text = Loc.t("ui.bargain_minigame.stimmung_s_d", "STIMMUNG  %s  %+d") % [_mood_word(_model.mood), _model.mood]
	_context_meta.text = _offer_meta() + "  ·  GEGENANGEBOT %d DM" % _model.price
	for card: StringName in Model.CARDS:
		var button := _buttons[card] as Button
		var used := card in _model.used
		button.disabled = used or _model.closed or _finished
		button.text = ("✓  " if used else ("★  " if card == _recommended else "")) \
			+ str(Model.LABELS[card])
	_hint_button.disabled = _model.closed or _finished
	var purchase_gate := FleaMarketManager.negotiated_purchase_gate(offer_id, _model.price) \
		if not _finished and not _model.closed else {"ok": false}
	_accept_button.disabled = _model.closed or _finished or not bool(purchase_gate.get("ok", false))
	_accept_button.text = (Loc.t("ui.bargain_minigame.paid", "BEZAHLT · %d DM")
		if _finished else Loc.t("ui.bargain_minigame.deal_and_pay",
			"DEAL & ZAHLEN · %d DM")) % _model.price
	_accept_button.tooltip_text = Loc.t("ui.bargain_minigame.ware_sofort_bezahlen_ubernehmen", "Ware sofort bezahlen und übernehmen.") if bool(purchase_gate.get("ok", false)) \
		else str(purchase_gate.get("text", "Abschluss derzeit nicht möglich."))
	_leave_button.disabled = _finished
	_table.queue_redraw()


func _mood_word(value: int) -> String:
	if value >= 2:
		return "OFFEN"
	if value == 1:
		return "INTERESSIERT"
	if value <= -2:
		return "GENERVT"
	if value == -1:
		return "SKEPTISCH"
	return "NEUTRAL"


func _offer_title() -> String:
	if _offer.has("software_id"):
		var info := SoftwareBible.entry(str(_offer.get("software_id", "")))
		return str(info.get("display_name", info.get("historical_name", "Computerspiel")))
	var template := DiskManager.templates.get(str(_offer.get("template_id", "")), {}) as Dictionary
	return str(template.get("content_title", template.get("label", "Gebrauchte Diskette")))


func _offer_meta() -> String:
	return "VERKÄUFER  %s  ·  %s  ·  BARZAHLUNG" % [
		str(_offer.get("seller", "Unbekannt")).to_upper(), _offer_visual_subtitle()]


func _offer_visual_subtitle() -> String:
	if _offer.has("software_id"):
		var form := str(_offer.get("form", "disk"))
		return str(FleaMarketManager.SW_FORMS.get(form, {}).get("label", "Original")).to_upper()
	var template := DiskManager.templates.get(str(_offer.get("template_id", "")), {}) as Dictionary
	return "%s-DISKETTE · %s" % [
		str(template.get("type", "DD")), str(template.get("rarity", "GEBRAUCHT")).to_upper()]


func _offer_texture() -> Texture2D:
	if _offer.has("software_id"):
		var offer_software := str(_offer.get("software_id", ""))
		var form := str(_offer.get("form", "disk"))
		if form == "disk":
			return DiskComposer.composed_disk(offer_software, true, 320,
				int(_offer.get("disk_number", 1)), "red")
		var art := SoftwareBible.acquisition_art(offer_software, form)
		return art.get("texture") as Texture2D
	var template_id := str(_offer.get("template_id", ""))
	var template := DiskManager.templates.get(template_id, {}) as Dictionary
	var software_id := str(template.get("software_id", ""))
	var body_color := "red" if str(template.get("content_type", "")) == "spiel" \
		else str(template.get("color", "blue"))
	if not software_id.is_empty():
		return DiskComposer.composed_disk(software_id, true, 320, 1, body_color)
	# Auch unbekannte Labor-/Legacy-Angebote zeigen eine echte Diskette statt
	# eines grauen Platzhalterbalkens.
	return DiskComposer.master_texture("red" if "game" in template_id else body_color)


func _seller_portrait() -> Texture2D:
	# Identitaet und Merkmale kommen aus der Verkaeufer-ID, nicht aus dem
	# Anzeigenamen. Frueher wurde beides per Teilstringsuche geraten
	# ("oma" -> weiblich/68) und die Portraet-ID aus dem kleingeschriebenen
	# deutschen Namen gebaut — eine Uebersetzung haette demselben Verkaeufer
	# lautlos ein anderes Gesicht und ein anderes Alter gegeben.
	var seller := str(_offer.get("seller", "Unbekannt"))
	var seller_id := str(_offer.get("seller_id", ""))
	if seller_id.is_empty():
		# Altspielstand ohne ID: aus dem gespeicherten Namen zurueckgewinnen.
		for entry: Dictionary in FleaMarketManager.SELLERS:
			if str(entry.get("name", "")) == seller:
				seller_id = str(entry.get("id", ""))
				break
	if seller_id == "krause":
		return NPCManager.portrait("npc_krause", {"emotion": "thinking"})
	var traits := FleaMarketManager.seller_traits(seller_id)
	var hints := {
		"emotion": "thinking",
		"age": int(traits.get("age", 44)),
		"gender": str(traits.get("gender", "m")),
		"location": "flea_market",
	}
	var stable_id := "flea_seller_%s" % (seller_id if not seller_id.is_empty()
		else seller.to_lower().replace(" ", "_").replace(".", ""))
	return PortraitGen.for_npc(stable_id, hints)


class BargainTable:
	extends Control

	const ART := preload("res://assets/minigames/FLEA_BARGAIN_TABLE_V01.png")

	var model: BargainModel
	var seller_portrait: Texture2D
	var ware_texture: Texture2D
	var offer_title := "FUNDSTÜCK"
	var offer_subtitle := "GEBRAUCHTWARE"


	func _draw() -> void:
		if size.x < 4.0 or size.y < 4.0:
			return
		var source_size := ART.get_size()
		var source_height := source_size.x * size.y / size.x
		var source_y := clampf(76.0, 0.0, source_size.y - source_height)
		draw_texture_rect_region(ART, Rect2(Vector2.ZERO, size),
			Rect2(0, source_y, source_size.x, source_height))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.012, 0.01, 0.10), true)

		var ware_panel := Rect2(34, 43, 270, 143)
		draw_rect(ware_panel, Color(0.015, 0.018, 0.017, 0.84), true)
		draw_rect(ware_panel, Color8(224, 190, 112), false, 2.5)
		if ware_texture != null:
			_draw_texture_fitted(ware_texture, ware_panel.grow(-11))
		var ware_label := Rect2(34, 12, 405, 25)
		draw_rect(ware_label, Color(0.015, 0.012, 0.01, 0.84), true)
		draw_string(ThemeDB.fallback_font, ware_label.position + Vector2(10, 18),
			offer_title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			ware_label.size.x - 20, 13, Color8(247, 220, 164))
		draw_string(ThemeDB.fallback_font, ware_panel.position + Vector2(8, ware_panel.size.y + 20),
			offer_subtitle + " · ZUSTAND UNGEPRÜFT", HORIZONTAL_ALIGNMENT_LEFT,
			ware_panel.size.x, 10, Color8(221, 193, 139))

		var portrait_rect := Rect2(size.x - 198, 25, 132, 132)
		draw_rect(portrait_rect.grow(6), Color8(28, 22, 18), true)
		draw_rect(portrait_rect.grow(6), Color8(180, 139, 77), false, 2.0)
		if seller_portrait != null:
			draw_texture_rect(seller_portrait, portrait_rect, false)
		var mood_color := Color8(154, 218, 166) if model.mood > 0 else (
			Color8(232, 154, 102) if model.mood < 0 else Color8(235, 211, 166))
		var seller_label := Rect2(size.x - 286, 169, 252, 30)
		draw_rect(seller_label, Color(0.015, 0.012, 0.01, 0.86), true)
		draw_string(ThemeDB.fallback_font, seller_label.position + Vector2(9, 20),
			"%s  ·  STIMMUNG %+d" % [model.seller.to_upper(), model.mood],
			HORIZONTAL_ALIGNMENT_LEFT, seller_label.size.x - 18, 11, mood_color)


	func _draw_texture_fitted(texture: Texture2D, bounds: Rect2) -> void:
		var texture_size := texture.get_size()
		if texture_size.x <= 0.0 or texture_size.y <= 0.0:
			return
		var factor := minf(bounds.size.x / texture_size.x, bounds.size.y / texture_size.y)
		var fitted_size := texture_size * factor
		var fitted := Rect2(bounds.get_center() - fitted_size * 0.5, fitted_size)
		draw_texture_rect(texture, fitted, false)
