class_name BankWindow
extends RetroWindow
## Vollwertiger Stadtbank-Schalter: Jugendsparbuch, Giro/EC-Karte, Belege und
## lueckenloses Journal. Der Schalter ist die menschliche, papierbasierte Seite
## der Bank; der Geldautomat besitzt bewusst eine eigene Bedienoberflaeche.

const STEPS := [5.0, 20.0, 50.0, 100.0]
const TABS := [
	{"id": "sparbuch", "label": "SPARBUCH"},
	{"id": "giro", "label": "GIRO & EC-KARTE"},
	{"id": "journal", "label": "BUCHUNGEN"},
	{"id": "service", "label": "SERVICE"},
]

var start_tab := "sparbuch"
var _tab := "sparbuch"


func _init() -> void:
	title = Loc.t("ui.bank_window.stadtbank_schalter_2", "STADTBANK — SCHALTER 2")
	win_size = Vector2(900, 660)


func _ready() -> void:
	var vp := get_viewport_rect().size
	win_size = Vector2(minf(920.0, vp.x - 24.0), minf(690.0, vp.y - 24.0))
	_tab = start_tab if TABS.any(func(t: Dictionary) -> bool: return t["id"] == start_tab) else "sparbuch"
	super._ready()
	position = ((vp - win_size) * 0.5).floor()
	if not BankManager.bank_changed.is_connected(_rebuild):
		BankManager.bank_changed.connect(_rebuild)
	if not PlayerStats.stats_changed.is_connected(_rebuild):
		PlayerStats.stats_changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	if BankManager.bank_changed.is_connected(_rebuild):
		BankManager.bank_changed.disconnect(_rebuild)
	if PlayerStats.stats_changed.is_connected(_rebuild):
		PlayerStats.stats_changed.disconnect(_rebuild)


func _rebuild() -> void:
	if content == null:
		return
	_resize_for_tab()
	for child in content.get_children():
		child.queue_free()
	_build_identity_strip()
	_build_summary()
	_build_tabs()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	match _tab:
		"giro": _build_giro(body)
		"journal": _build_journal(body)
		"service": _build_service(body)
		_: _build_savings(body)


## Ein papierarmer Schaltervorgang soll nicht in einer halbleeren Vollbildbox
## schweben. Umfangreiche Giro-/Journalansichten erhalten mehr Hoehe; alle
## Bereiche bleiben scrollbar und auf kleinen Viewports sicher erreichbar.
func _resize_for_tab() -> void:
	var vp := get_viewport_rect().size
	var wanted_height := 480.0
	match _tab:
		"giro":
			wanted_height = 630.0 if BankManager.account_open else 470.0
		"journal":
			wanted_height = 650.0
		"service":
			wanted_height = 470.0
		_:
			wanted_height = 530.0 if BankManager.savings_ledger().size() > 3 else 480.0
	win_size.y = minf(wanted_height, vp.y - 24.0)
	custom_minimum_size = win_size
	size = win_size
	position = ((vp - win_size) * 0.5).floor()


func _build_identity_strip() -> void:
	var strip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(17, 35, 47)
	style.border_color = Color8(79, 125, 142)
	style.set_border_width_all(1)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	strip.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_child(_label("STADTBANK BYTENBERG", Color8(239, 194, 84), 15))
	row.add_child(_spacer())
	row.add_child(_label("KUNDE  %s  ·  %d JAHRE" % [PlayerIdentity.player_name.to_upper(),
		PlayerIdentity.age()], Color8(196, 218, 221), 11))
	row.add_child(_label("%s · %s" % [TimeManager.date_string(), TimeManager.clock_string()],
		Color8(139, 183, 171), 11))
	strip.add_child(row)
	content.add_child(strip)


func _build_summary() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_summary_card("BARGELD", PlayerStats.geld, Color8(103, 231, 131), "TASCHE"))
	row.add_child(_summary_card("SPARBUCH", BankManager.savings, Color8(107, 193, 239),
		"%.2f %% P.A." % (BankManager.SAVINGS_RATE * 100.0)))
	row.add_child(_summary_card("GIROKONTO", BankManager.balance, Color8(243, 190, 79),
		"AKTIV" if BankManager.account_open else ("AB 1994" if not BankManager.giro_available() else "NICHT EROEFFNET")))
	content.add_child(row)


func _summary_card(label_text: String, amount: float, color: Color, foot: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Bezel.panel_box())
	var box := VBoxContainer.new()
	box.add_child(_label(label_text, Palette.WHITE_SOFT, 10))
	box.add_child(Bezel.segment_label(Currency.format(amount), color, 17))
	box.add_child(_label(foot, Palette.UI_TEXT_DIM, 9))
	panel.add_child(box)
	return panel


func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for def: Dictionary in TABS:
		var id := str(def["id"])
		var button := make_button(str(def["label"]), _select_tab.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.modulate = Color.WHITE if id == _tab else Color(0.62, 0.65, 0.67)
		button.disabled = id == _tab
		row.add_child(button)
	content.add_child(row)


func _select_tab(id: String) -> void:
	_tab = id
	AudioManager.ui_click()
	_rebuild()


# -------------------------------------------------------------- Sparbuch

func _build_savings(body: VBoxContainer) -> void:
	var hero := _paper_panel()
	var book: VBoxContainer = hero.get_child(0)
	book.add_child(_paper_label("STADTBANK BYTENBERG · JUGENDSPARBUCH", 15, Color8(45, 68, 86)))
	book.add_child(_paper_label("Sparbuch-Nr. 90-%04d  ·  Inhaber: %s" % [1000 + posmod(hash(PlayerIdentity.player_name), 9000),
		PlayerIdentity.player_name], 11, Color8(68, 68, 62)))
	book.add_child(_paper_label("Naechste Zinsgutschrift: Sommer %d  ·  Zinssatz: %.2f %% p.a." % [
		BankManager.next_interest_year(), BankManager.SAVINGS_RATE * 100.0], 11, Color8(107, 74, 43)))
	body.add_child(hero)

	body.add_child(_section("BAREINZAHLUNG — ALTERSUNABHAENGIG"))
	body.add_child(_paragraph("Herr Wolf zaehlt die Scheine, stempelt das Sparbuch und traegt die neue Summe sofort ein. Dafuer brauchst du weder ein Girokonto noch eine EC-Karte."))
	body.add_child(_amount_row("AUFS SPARBUCH", _deposit_savings, PlayerStats.geld))
	body.add_child(_amount_row("VOM SPARBUCH AUSZAHLEN", _withdraw_savings, BankManager.savings))
	body.add_child(_section("LETZTE SPARBUCHZEILEN"))
	body.add_child(_ledger_table(BankManager.savings_ledger(), 9))


func _deposit_savings(amount: float) -> void:
	if BankManager.deposit_to_savings(amount):
		UIManager.toast(Loc.t("ui.bank_window.herr_wolf_stempelt_einzahlung_ins_sparbuch", "Herr Wolf stempelt die Einzahlung ins Sparbuch."))
	else:
		UIManager.toast(Loc.t("ui.bank_window.so_viel_bargeld_hast_du_nicht", "So viel Bargeld hast du nicht in der Tasche."))


func _withdraw_savings(amount: float) -> void:
	if BankManager.withdraw_from_savings(amount):
		UIManager.toast(Loc.t("ui.bank_window.auszahlung_eingetragen_bitte_nachzaehlen", "Auszahlung eingetragen. Bitte nachzaehlen."))
	else:
		UIManager.toast(Loc.t("ui.bank_window.sparbuchguthaben_reicht_dafuer_nicht", "Das Sparbuchguthaben reicht dafuer nicht."))


# ------------------------------------------------------------ Giro / Karte

func _build_giro(body: VBoxContainer) -> void:
	body.add_child(_section("GIROKONTO & EUROCHEQUE-KARTE"))
	if not BankManager.giro_available():
		var locked := _info_panel(Color8(78, 99, 118))
		var box: VBoxContainer = locked.get_child(0)
		box.add_child(_label("NOCH PAPIERZEIT", Color8(155, 204, 230), 15))
		box.add_child(_paragraph("Bis Sommer 1994 fuehrst du dein Geld klassisch im Sparbuch. Dann bietet Herr Wolf ein Girokonto mit Magnetstreifen-EC-Karte und persoenlicher Geheimzahl an. Das Sparbuch bleibt trotzdem erhalten."))
		box.add_child(_label("Freischaltung: Sommer 1994", Color8(239, 194, 84), 12))
		body.add_child(locked)
		return
	if not BankManager.account_open:
		_build_account_opening(body)
		return

	body.add_child(_amount_row("BARGELD AUFS GIROKONTO", _deposit_giro, PlayerStats.geld))
	body.add_child(_amount_row("BARGELD VOM GIROKONTO", _withdraw_giro, BankManager.balance))
	body.add_child(_section("UMBUCHEN"))
	body.add_child(_amount_row("GIRO → SPARBUCH", _to_savings, BankManager.balance))
	body.add_child(_amount_row("SPARBUCH → GIRO", _to_giro, BankManager.savings))
	body.add_child(_section("EC-KARTE / GELDAUTOMAT"))
	_build_card_status(body)


func _build_account_opening(body: VBoxContainer) -> void:
	var panel := _info_panel(Color8(79, 125, 142))
	var box: VBoxContainer = panel.get_child(0)
	box.add_child(_label("DEIN ERSTES GIROKONTO", Color8(239, 194, 84), 16))
	box.add_child(_paragraph("Geldeingaenge, Uebertraege und die spaetere EC-Karte laufen ueber dieses Konto. Das Jugendsparbuch bleibt separat und wird weiter verzinst."))
	if BankManager.needs_parent_signature():
		if not BankManager.parents_asked():
			box.add_child(_paragraph("Da du noch nicht volljaehrig bist, braucht die Bank einmal die Unterschrift deiner Eltern."))
			box.add_child(make_button(Loc.t("ui.bank_window.eltern_um_unterschrift_bitten", "ELTERN UM UNTERSCHRIFT BITTEN"), func() -> void:
				BankManager.ask_parents()
				UIManager.toast(Loc.t("ui.bank_window.deine_eltern_kommen_bei_einem_spaeteren", "Deine Eltern kommen bei einem spaeteren Bankbesuch mit."))))
		elif BankManager.can_open():
			box.add_child(make_button(Loc.t("ui.bank_window.girokonto_mit_elternunterschrift_eroeffnen", "GIROKONTO MIT ELTERNUNTERSCHRIFT EROEFFNEN"), _open_account))
		else:
			box.add_child(_label("Eltern gefragt · gemeinsamer Termin ab dem naechsten Tag", Color8(157, 187, 196), 11))
	else:
		box.add_child(_paragraph("Du bist volljaehrig und kannst den Antrag selbst unterschreiben."))
		box.add_child(make_button(Loc.t("ui.bank_window.girokonto_eroeffnen", "GIROKONTO EROEFFNEN"), _open_account))
	body.add_child(panel)


func _open_account() -> void:
	if BankManager.open_account():
		UIManager.toast(Loc.t("ui.bank_window.herr_wolf_reicht_dir_kontounterlagen_girokonto", "Herr Wolf reicht dir die Kontounterlagen. Girokonto eroeffnet."))


func _deposit_giro(amount: float) -> void:
	if not BankManager.deposit(amount): UIManager.toast(Loc.t("ui.bank_window.nicht_genug_bargeld", "Nicht genug Bargeld."))


func _withdraw_giro(amount: float) -> void:
	if not BankManager.withdraw(amount): UIManager.toast(Loc.t("ui.bank_window.nicht_genug_guthaben_auf_dem_girokonto", "Nicht genug Guthaben auf dem Girokonto."))


func _to_savings(amount: float) -> void:
	if not BankManager.save_to_savings(amount): UIManager.toast(Loc.t("ui.bank_window.umbuchung_nicht_moeglich", "Umbuchung nicht moeglich."))


func _to_giro(amount: float) -> void:
	if not BankManager.take_from_savings(amount): UIManager.toast(Loc.t("ui.bank_window.umbuchung_nicht_moeglich", "Umbuchung nicht moeglich."))


func _build_card_status(body: VBoxContainer) -> void:
	var card := _info_panel(Color8(59, 122, 91))
	var box: VBoxContainer = card.get_child(0)
	if BankManager.card_locked:
		box.add_child(_label("EC-KARTE EINBEHALTEN", Color8(236, 100, 83), 15))
		box.add_child(_paragraph("Nach drei falschen Geheimzahlen hat der Automat die Karte gesperrt. Herr Wolf prueft deinen Ausweis und gibt sie wieder frei."))
		box.add_child(make_button(Loc.t("ui.bank_window.karte_am_schalter_entsperren", "KARTE AM SCHALTER ENTSPERREN"), func() -> void:
			if BankManager.unlock_card(): UIManager.toast(Loc.t("ui.bank_window.karte_entsperrt_pin_bleibt_unveraendert", "Karte entsperrt. Die PIN bleibt unveraendert."))))
	elif BankManager.card_issued:
		box.add_child(_label("EC-KARTE AKTIV · MAGNETSTREIFEN", Color8(112, 225, 139), 14))
		box.add_child(_paragraph("Die Karte funktioniert am Stadtbank-Geldautomaten. Drei falsche PIN-Eingaben sperren sie; das Tageslimit fuer Auszahlungen betraegt %s." % Currency.format(BankManager.ATM_DAILY_LIMIT)))
		var pin_row := HBoxContainer.new()
		pin_row.add_child(_label("PIN-BRIEF (getrennt aufbewahren):", Palette.UI_TEXT_DIM, 11))
		pin_row.add_child(Bezel.segment_label(BankManager.pin_letter_text(), Palette.LCD_GREEN, 17))
		box.add_child(pin_row)
		box.add_child(make_button(Loc.t("ui.bank_window.zum_geldautomaten", "ZUM GELDAUTOMATEN"), func() -> void: UIManager.open_bank_atm()))
	elif BankManager.card_requested_day < 0:
		box.add_child(_label("EC-KARTE BESTELLEN", Color8(239, 194, 84), 14))
		box.add_child(_paragraph("Die Karte und der PIN-Brief werden getrennt vorbereitet. Lieferzeit: etwa %d Kalendertage." % BankManager.CARD_DELIVERY_DAYS))
		box.add_child(make_button(Loc.t("ui.bank_window.magnetstreifen_ec_karte_bestellen", "MAGNETSTREIFEN-EC-KARTE BESTELLEN"), func() -> void:
			if BankManager.request_card(): UIManager.toast(Loc.t("ui.bank_window.karte_bestellt_herr_wolf_notiert_den", "Karte bestellt. Herr Wolf notiert den Abholtermin."))))
	elif BankManager.can_collect_card():
		box.add_child(_label("KARTE & PIN-BRIEF LIEGEN BEREIT", Color8(112, 225, 139), 14))
		box.add_child(make_button(Loc.t("ui.bank_window.beides_getrennt_entgegennehmen", "BEIDES GETRENNT ENTGEGENNEHMEN"), func() -> void:
			if BankManager.collect_card(): UIManager.toast(Loc.t("ui.bank_window.ec_karte_erhalten_den_pin_brief", "EC-Karte erhalten. Den PIN-Brief nicht bei der Karte tragen!"))))
	else:
		box.add_child(_label("KARTE IN BEARBEITUNG", Color8(157, 187, 196), 14))
		box.add_child(_paragraph("Noch etwa %d Kalendertage. Karte und Geheimzahl werden getrennt vorbereitet." % BankManager.card_days_remaining()))
	body.add_child(card)


# --------------------------------------------------------------- Journal

func _build_journal(body: VBoxContainer) -> void:
	body.add_child(_section("VOLLSTAENDIGES BUCHUNGSJOURNAL"))
	body.add_child(_paragraph("Jede Zeile bleibt im Spielstand erhalten: Datum, Uhrzeit, Konto, Kanal, Betrag und Saldo nach der Buchung. Zinszeilen werden beim Start des naechsten Sommers automatisch eingetragen."))
	body.add_child(_ledger_table(BankManager.ledger(), 0))


# --------------------------------------------------------------- Service

func _build_service(body: VBoxContainer) -> void:
	body.add_child(_section("SCHALTERSERVICE"))
	var status := "GEÖFFNET" if BankManager.counter_open() else "GESCHLOSSEN"
	body.add_child(_paragraph("Schalter: %s · %s. Der Automatenraum ist rund um die Uhr zugaenglich." % [status, BankManager.counter_hours_text()]))
	if PhoneManager.bill_due > 0:
		var warn := _info_panel(Color8(156, 75, 53))
		var box: VBoxContainer = warn.get_child(0)
		box.add_child(_label("TELEFONRECHNUNG: %s" % Currency.format(PhoneManager.bill_due), Color8(247, 146, 98), 14))
		box.add_child(_paragraph("Die Rechnung kann hier bar beglichen werden. Reicht das Bargeld nicht, kannst du vorher aus Sparbuch oder Giro abheben."))
		box.add_child(make_button(Loc.t("ui.bank_window.rechnung_bar_bezahlen", "RECHNUNG BAR BEZAHLEN"), func() -> void:
			if PhoneManager.pay_bill(): UIManager.toast(Loc.t("ui.bank_window.rechnung_bezahlt_leitung_ist_wieder_frei", "Rechnung bezahlt — die Leitung ist wieder frei."))
			else: UIManager.toast(Loc.t("ui.bank_window.nicht_genug_bargeld_in_tasche", "Nicht genug Bargeld in der Tasche."))
			_rebuild()))
		body.add_child(warn)
	else:
		body.add_child(_label("Keine offene Telefonrechnung.", Color8(112, 225, 139), 12))
	body.add_child(_section("VERMOEGENSAUSKUNFT"))
	body.add_child(_paragraph("Bargeld %s  +  Bankguthaben %s  =  Gesamt %s" % [
		Currency.format(PlayerStats.geld), Currency.format(BankManager.total()),
		Currency.format(PlayerStats.geld + BankManager.total())]))
	body.add_child(_section("HERR WOLFS HINWEIS"))
	body.add_child(_paragraph("»Das Sparbuch ist kein Museumsstueck. Es ist dein Notgroschen. Die EC-Karte macht Wege kuerzer — aber ausgeben kannst du jede Mark nur einmal.«"))


# --------------------------------------------------------------- Bausteine

func _amount_row(label_text: String, action: Callable, available: float) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Bezel.panel_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var label := _label(label_text, Palette.WHITE_SOFT, 11)
	label.custom_minimum_size.x = 220
	row.add_child(label)
	for step: float in STEPS:
		var button := make_button(Loc.t("ui.bank_window.d_dm", "%d DM") % int(step), action.bind(step))
		button.disabled = available + 0.005 < step
		row.add_child(button)
	var all_button := make_button(Loc.t("ui.bank_window.alles_s", "ALLES (%s)") % Currency.amount(available), action.bind(Currency.snap(available)))
	all_button.disabled = available <= 0.0
	row.add_child(all_button)
	panel.add_child(row)
	return panel


func _ledger_table(rows: Array, max_rows: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Bezel.panel_box())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_child(_fixed_label("DATUM / ZEIT", 126, Color8(136, 165, 173), 9))
	head.add_child(_fixed_label("KONTO", 72, Color8(136, 165, 173), 9))
	head.add_child(_fixed_label("BUCHUNG", 270, Color8(136, 165, 173), 9))
	head.add_child(_fixed_label("BETRAG", 105, Color8(136, 165, 173), 9, HORIZONTAL_ALIGNMENT_RIGHT))
	head.add_child(_fixed_label("SALDO", 105, Color8(136, 165, 173), 9, HORIZONTAL_ALIGNMENT_RIGHT))
	box.add_child(head)
	box.add_child(HSeparator.new())
	if rows.is_empty():
		box.add_child(_label("Noch keine Buchung. Die erste Einzahlung wird hier dauerhaft eingetragen.", Palette.UI_TEXT_DIM, 11))
		return panel
	var begin := maxi(0, rows.size() - max_rows) if max_rows > 0 else 0
	for index in range(rows.size() - 1, begin - 1, -1):
		var entry: Dictionary = rows[index]
		var line := HBoxContainer.new()
		line.add_child(_fixed_label("%s  %s" % [entry.get("date", "--"), entry.get("time", "--")], 126, Palette.UI_TEXT_DIM, 9))
		line.add_child(_fixed_label("SPAR" if entry.get("account", "") == "sparbuch" else "GIRO", 72,
			Color8(107, 193, 239) if entry.get("account", "") == "sparbuch" else Color8(243, 190, 79), 10))
		line.add_child(_fixed_label(str(entry.get("note", "Buchung")), 270, Palette.WHITE_SOFT, 10))
		var amount := float(entry.get("amount", 0.0))
		var amount_text := ("+" if amount > 0.0 else "") + Currency.format(amount)
		line.add_child(_fixed_label(amount_text, 105, Color8(112, 225, 139) if amount > 0.0 else (Color8(236, 100, 83) if amount < 0.0 else Palette.UI_TEXT_DIM), 10, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(_fixed_label(Currency.format(float(entry.get("balance_after", 0.0))), 105, Palette.WHITE_SOFT, 10, HORIZONTAL_ALIGNMENT_RIGHT))
		box.add_child(line)
	return panel


func _section(text: String) -> Label:
	var label := _label(text, Color8(239, 194, 84), 13)
	label.add_theme_constant_override("outline_size", 2)
	return label


func _paragraph(text: String) -> Label:
	var label := _label(text, Palette.UI_TEXT_DIM, 11)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _fixed_label(text: String, width: float, color: Color, font_size: int,
		alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := _label(text, color, font_size)
	label.custom_minimum_size.x = width
	label.clip_text = true
	label.horizontal_alignment = alignment
	return label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _paper_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(218, 210, 180)
	style.border_color = Color8(116, 86, 54)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return panel


func _paper_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, color, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _info_panel(border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := Bezel.panel_box()
	style.border_color = border
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return panel
