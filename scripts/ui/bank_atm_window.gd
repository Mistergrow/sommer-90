class_name BankAtmWindow
extends RetroWindow
## Fruehe-90er-Geldausgabeautomat: Magnetstreifenkarte, vierstellige Geheimzahl,
## monochromes Textdisplay, feste Betragswahl, 400-DM-Tageslimit und die reale
## Ausgabereihenfolge KARTE -> GELD -> BELEG. Kein Touchscreen, kein Online-Look.

const SCREEN_GREEN := Color8(126, 218, 143)
const SCREEN_DIM := Color8(70, 135, 82)
const SCREEN_BG := Color8(4, 22, 9)

var _stage := "welcome"
var _pin_input := ""
var _message := ""
var _pending_kind := ""
var _pending_amount := 0.0
var _receipt: Dictionary = {}


func _init() -> void:
	title = Loc.t("ui.bank_atm_window.stadtbank_geldausgabeautomat_gaa_90", "STADTBANK · GELDAUSGABEAUTOMAT GAA 90")
	win_size = Vector2(720, 560)


func _ready() -> void:
	var vp := get_viewport_rect().size
	win_size = Vector2(minf(760.0, vp.x - 28.0), minf(570.0, vp.y - 28.0))
	super._ready()
	position = ((vp - win_size) * 0.5).floor()
	_rebuild()


func _rebuild() -> void:
	if content == null:
		return
	_resize_for_stage()
	for child in content.get_children():
		child.queue_free()
	content.add_child(_machine_header())
	var shell := PanelContainer.new()
	var shell_style := StyleBoxFlat.new()
	shell_style.bg_color = Color8(45, 48, 43)
	shell_style.border_color = Color8(102, 106, 94)
	shell_style.set_border_width_all(3)
	shell_style.content_margin_left = 18.0
	shell_style.content_margin_right = 18.0
	shell_style.content_margin_top = 14.0
	shell_style.content_margin_bottom = 14.0
	shell.add_theme_stylebox_override("panel", shell_style)
	var machine := VBoxContainer.new()
	machine.add_theme_constant_override("separation", 10)
	shell.add_child(machine)
	machine.add_child(_display_panel())
	_build_stage_controls(machine)
	content.add_child(shell)
	content.add_child(_footer())


## Die echte Bedienblende bleibt kompakt. Nur fuer die physische Zifferntastatur
## waechst das Fenster nach unten; dadurch entsteht in den Menues keine leere,
## schwarze Halbseite und auf kleinen Viewports wird trotzdem nichts abgeschnitten.
func _resize_for_stage() -> void:
	var vp := get_viewport_rect().size
	var wanted_height := 570.0 if _stage == "pin" else 445.0
	win_size.y = minf(wanted_height, vp.y - 28.0)
	custom_minimum_size = win_size
	size = win_size
	position = ((vp - win_size) * 0.5).floor()


func _machine_header() -> Control:
	var row := HBoxContainer.new()
	row.add_child(_label("STADTBANK", Color8(239, 194, 84), 16))
	row.add_child(_spacer())
	row.add_child(_label("ec  ·  MAGNETSTREIFEN", Color8(180, 186, 173), 11))
	row.add_child(_label("BETRIEB 24 STUNDEN", Color8(112, 225, 139), 11))
	return row


func _display_panel() -> Control:
	var bezel := PanelContainer.new()
	bezel.custom_minimum_size = Vector2(0, 235)
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color8(13, 15, 12)
	outer.border_color = Color8(86, 91, 78)
	outer.set_border_width_all(8)
	outer.corner_radius_top_left = 8
	outer.corner_radius_top_right = 8
	outer.corner_radius_bottom_left = 8
	outer.corner_radius_bottom_right = 8
	outer.content_margin_left = 18.0
	outer.content_margin_right = 18.0
	outer.content_margin_top = 15.0
	outer.content_margin_bottom = 15.0
	bezel.add_theme_stylebox_override("panel", outer)
	var screen := PanelContainer.new()
	var screen_style := StyleBoxFlat.new()
	screen_style.bg_color = SCREEN_BG
	screen_style.border_color = Color8(38, 75, 45)
	screen_style.set_border_width_all(2)
	screen_style.content_margin_left = 18.0
	screen_style.content_margin_right = 18.0
	screen_style.content_margin_top = 14.0
	screen_style.content_margin_bottom = 14.0
	screen.add_theme_stylebox_override("panel", screen_style)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	lines.add_child(_screen_label("STADTBANK  GAA/90     %s  %s" % [
		"%02d.%02d.%02d" % [TimeManager.day, TimeManager.month, TimeManager.year % 100],
		TimeManager.clock_string()], 11, SCREEN_DIM))
	lines.add_child(HSeparator.new())
	for line: String in _screen_lines():
		lines.add_child(_screen_label(line, 15 if line == _screen_lines()[0] else 12,
			SCREEN_GREEN if not line.begins_with("!") else Color8(239, 194, 84)))
	screen.add_child(lines)
	bezel.add_child(screen)
	return bezel


func _screen_lines() -> Array[String]:
	match _stage:
		"welcome":
			if not BankManager.account_open:
				return ["GUTEN TAG", "Fuer diesen Automaten benoetigen Sie", "ein Girokonto und eine EC-Karte."]
			if BankManager.card_locked:
				return ["! KARTE GESPERRT", "Bitte wenden Sie sich waehrend", "der Oeffnungszeiten an den Schalter."]
			if not BankManager.card_issued:
				return ["GUTEN TAG", "Bitte EC-Karte am Schalter bestellen.", "Das Sparbuch gilt nicht am Automaten."]
			return ["GUTEN TAG", "Bitte EC-Karte einschieben.", "Magnetstreifen nach unten rechts."]
		"pin":
			return ["PERSOENLICHE GEHEIMZAHL", "Bitte vier Ziffern eingeben:", _pin_bullets(), _message]
		"retained":
			return ["! KARTE EINBEHALTEN", "Dreimal falsche Geheimzahl.", "Bitte mit Ausweis zum Schalter gehen."]
		"menu":
			return ["BITTE WAEHLEN", "Bargeldauszahlung  ·  Einzahlung", "Kontostand          ·  Vorgang beenden", _message]
		"withdraw":
			var availability := BankManager.atm_availability()
			var lines: Array[String] = [
				"BARGELDAUSZAHLUNG",
				"Girokonto: %s" % Currency.format(float(availability.get("giro", 0.0))),
				"Tageslimit: %s  ·  AUSZAHLBAR: %s" % [
					Currency.format(float(availability.get("daily_limit", 0.0))),
					Currency.format(float(availability.get("available", 0.0)))],
			]
			if float(availability.get("available", 0.0)) < 20.0:
				if float(availability.get("savings", 0.0)) >= 20.0:
					lines.append("! GIROKONTO ZU NIEDRIG")
					lines.append("Sparbuch %s · Umbuchung nur am Schalter." % Currency.format(float(availability.get("savings", 0.0))))
				else:
					lines.append("! KEIN AUSZAHLBARER BETRAG")
			else:
				lines.append("Bitte Betrag waehlen.")
			if not _message.is_empty():
				lines.append(_message)
			return lines
		"deposit":
			return ["BELEGEINZAHLUNG", "Scheine mit Beleg in den Umschlag legen.", "Bargeld in der Tasche: %s" % Currency.format(PlayerStats.geld), _message]
		"balance":
			return ["KONTOSTAND", "Girokonto:  %s" % Currency.format(BankManager.balance), "Verfuegbar am GAA: %s" % Currency.format(minf(BankManager.balance, BankManager.atm_limit_remaining()))]
		"card_return":
			return ["BITTE KARTE ENTNEHMEN", "Nehmen Sie zuerst Ihre EC-Karte.", "Danach folgt %s." % ("das Bargeld" if _pending_kind == "withdrawal" else "die Belegfrage")]
		"cash_take":
			return ["BITTE GELD ENTNEHMEN", "%s liegen im Ausgabefach." % Currency.format(_pending_amount), "Bitte Banknoten nachzaehlen."]
		"receipt_offer":
			return ["WUENSCHEN SIE EINEN BELEG?", "Der Vorgang ist bereits gebucht.", "JA                         NEIN"]
		"receipt_take":
			return ["BITTE BELEG ENTNEHMEN", "%s  %s" % [_receipt.get("date", ""), _receipt.get("time", "")],
				str(_receipt.get("text", "Buchung")), "NEUER SALDO: %s" % Currency.format(float(_receipt.get("balance", 0.0)))]
		"done":
			return ["VIELEN DANK", "Bitte Karte, Geld und Beleg mitnehmen.", "Die Stadtbank wuenscht einen guten Tag."]
	return ["BITTE WARTEN"]


func _build_stage_controls(machine: VBoxContainer) -> void:
	match _stage:
		"welcome": _build_welcome(machine)
		"pin": _build_keypad(machine)
		"retained": _build_retained(machine)
		"menu": _build_menu(machine)
		"withdraw": _build_amounts(machine, true)
		"deposit": _build_amounts(machine, false)
		"balance":
			machine.add_child(_wide_button("ZURUECK ZUR AUSWAHL", func() -> void: _goto("menu")))
		"card_return":
			machine.add_child(_slot_label("KARTENSCHLITZ  ◀  EC-KARTE LIEGT BEREIT", Color8(239, 194, 84)))
			machine.add_child(_wide_button("EC-KARTE ENTNEHMEN", _take_card))
		"cash_take":
			machine.add_child(_slot_label("GELDAUSGABEFACH  ▼  KLAPPE GEOEFFNET", Color8(112, 225, 139)))
			machine.add_child(_wide_button("BANKNOTEN ENTNEHMEN", _take_cash))
		"receipt_offer":
			var row := HBoxContainer.new()
			row.add_child(_function_button("JA · BELEG DRUCKEN", func() -> void:
				AudioManager.play("paper", 0.0)
				_goto("receipt_take")))
			row.add_child(_function_button("NEIN · BEENDEN", func() -> void: _goto("done")))
			machine.add_child(row)
		"receipt_take":
			machine.add_child(_slot_label("BELEGAUSGABE  ▼  DRUCKSTREIFEN", Color8(180, 186, 173)))
			machine.add_child(_wide_button("BELEG ENTNEHMEN", func() -> void:
				AudioManager.play("paper", 0.0)
				_goto("done")))
		"done":
			machine.add_child(_wide_button("NEUER VORGANG", _new_session))


func _build_welcome(machine: VBoxContainer) -> void:
	machine.add_child(_slot_label("KARTENSCHLITZ  ▶  MAGNETSTREIFENKARTE", Color8(180, 186, 173)))
	if BankManager.card_issued and not BankManager.card_locked:
		machine.add_child(_wide_button("EC-KARTE EINSCHIEBEN", _insert_card))
	elif BankManager.counter_open():
		machine.add_child(_wide_button("ZUM SCHALTER", func() -> void:
			queue_free()
			UIManager.open_bank("giro")))


func _insert_card() -> void:
	AudioManager.play("atm_card", 0.0)
	_pin_input = ""
	_message = ""
	_goto("pin")


func _build_keypad(machine: VBoxContainer) -> void:
	var keypad_shell := PanelContainer.new()
	keypad_shell.add_theme_stylebox_override("panel", Bezel.panel_box())
	var keypad := GridContainer.new()
	keypad.columns = 3
	keypad.add_theme_constant_override("h_separation", 8)
	keypad.add_theme_constant_override("v_separation", 6)
	for key: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "KORR", "0", "OK"]:
		var callback := _press_digit.bind(key) if key.length() == 1 else (_correct_pin if key == "KORR" else _submit_pin)
		var button := make_button(key, callback)
		button.custom_minimum_size = Vector2(0, 38)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keypad.add_child(button)
	keypad_shell.add_child(keypad)
	machine.add_child(keypad_shell)
	machine.add_child(_wide_button("ABBRUCH · KARTE ZURUECK", func() -> void:
		_pending_kind = ""
		_goto("card_return")))


func _press_digit(digit: String) -> void:
	if _pin_input.length() >= 4:
		return
	_pin_input += digit
	_message = ""
	AudioManager.key_click()
	_rebuild()


func _correct_pin() -> void:
	if not _pin_input.is_empty():
		_pin_input = _pin_input.left(_pin_input.length() - 1)
	AudioManager.key_click()
	_rebuild()


func _submit_pin() -> void:
	if _pin_input.length() != 4:
		_message = "! VIER ZIFFERN ERFORDERLICH"
		AudioManager.minigame_cue("bank_atm", &"error")
		_rebuild()
		return
	if BankManager.verify_pin(_pin_input):
		_message = "GEHEIMZAHL RICHTIG"
		AudioManager.relay()
		_goto("menu")
		return
	_pin_input = ""
	if BankManager.card_locked:
		AudioManager.minigame_cue("bank_atm", &"error")
		_goto("retained")
	else:
		_message = "! GEHEIMZAHL FALSCH · NOCH %d VERSUCHE" % (3 - BankManager.pin_failures)
		AudioManager.minigame_cue("bank_atm", &"error")
		_rebuild()


func _build_retained(machine: VBoxContainer) -> void:
	machine.add_child(_slot_label("KARTENSCHLITZ VERRIEGELT", Color8(236, 100, 83)))
	if BankManager.counter_open():
		machine.add_child(_wide_button("MIT AUSWEIS ZUM SCHALTER", func() -> void:
			queue_free()
			UIManager.open_bank("giro")))


func _build_menu(machine: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(_function_button("◀ BARGELDAUSZAHLUNG", func() -> void: _goto("withdraw")))
	grid.add_child(_function_button("BELEGEINZAHLUNG ▶", func() -> void: _goto("deposit")))
	grid.add_child(_function_button("◀ KONTOSTAND", func() -> void: _goto("balance")))
	grid.add_child(_function_button("VORGANG BEENDEN ▶", func() -> void:
		_pending_kind = ""
		_goto("card_return")))
	machine.add_child(grid)


func _build_amounts(machine: VBoxContainer, withdrawal: bool) -> void:
	var values := [20.0, 50.0, 100.0, 200.0, 400.0] if withdrawal else [5.0, 20.0, 50.0, 100.0]
	var availability := BankManager.atm_availability() if withdrawal else {}
	var available := float(availability.get("available", 0.0)) if withdrawal else PlayerStats.geld
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for amount: float in values:
		var button := make_button(Loc.t("ui.bank_atm_window.d_dm", "%d DM") % int(amount), _choose_amount.bind(amount, withdrawal))
		button.disabled = amount > available + 0.005
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	if not withdrawal:
		var all := make_button(Loc.t("ui.bank_atm_window.alles", "ALLES"), _choose_amount.bind(Currency.snap(available), false))
		all.disabled = available <= 0.0
		all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(all)
	machine.add_child(row)
	if withdrawal and available < 20.0 and BankManager.savings >= 20.0:
		var transfer_text := "SPARBUCH → GIRO AM SCHALTER"
		if not BankManager.counter_open():
			transfer_text = "SPARBUCH → GIRO · SCHALTER GESCHLOSSEN"
		var transfer := _wide_button(transfer_text, _open_transfer_or_explain)
		transfer.name = "SavingsTransferGuide"
		machine.add_child(transfer)
	machine.add_child(_wide_button("ZURUECK", func() -> void:
		_message = ""
		_goto("menu")))


func _open_transfer_or_explain() -> void:
	if not BankManager.counter_open():
		_message = "! SCHALTER GESCHLOSSEN · %s" % BankManager.counter_hours_text().to_upper()
		AudioManager.minigame_cue("bank_atm", &"error")
		_rebuild()
		return
	queue_free()
	UIManager.open_bank("giro")


func _choose_amount(amount: float, withdrawal: bool) -> void:
	var result: Dictionary = BankManager.atm_withdraw(amount) if withdrawal else BankManager.atm_deposit(amount)
	if not bool(result.get("ok", false)):
		_message = "! " + str(result.get("text", "VORGANG NICHT MOEGLICH"))
		AudioManager.minigame_cue("bank_atm", &"error")
		_rebuild()
		return
	_pending_kind = "withdrawal" if withdrawal else "deposit"
	_pending_amount = amount
	_receipt = {
		"date": "%02d.%02d.%02d" % [TimeManager.day, TimeManager.month, TimeManager.year % 100],
		"time": TimeManager.clock_string(),
		"text": ("AUSZAHLUNG  -" if withdrawal else "EINZAHLUNG +") + Currency.amount(amount) + " DM",
		"balance": BankManager.balance,
	}
	AudioManager.play("atm_dispense" if withdrawal else "paper", 0.0)
	_goto("card_return")


func _take_card() -> void:
	AudioManager.play("atm_card", 0.0)
	if _pending_kind == "withdrawal":
		_goto("cash_take")
	else:
		_goto("receipt_offer" if _pending_kind == "deposit" else "done")


func _take_cash() -> void:
	AudioManager.play("cash_count", 0.0)
	_goto("receipt_offer")


func _new_session() -> void:
	_stage = "welcome"
	_pin_input = ""
	_message = ""
	_pending_kind = ""
	_pending_amount = 0.0
	_receipt = {}
	_rebuild()


func _goto(stage: String) -> void:
	_stage = stage
	_rebuild()


func _pin_bullets() -> String:
	var result := ""
	for i in 4:
		result += "●  " if i < _pin_input.length() else "_  "
	return result.strip_edges()


func _footer() -> Control:
	var label := _label("SICHERHEIT: Geheimzahl verdeckt eingeben · Karte zuerst entnehmen · Bei Stoerung Schalterruf", Color8(143, 151, 137), 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _slot_label(text: String, color: Color) -> Label:
	var label := _label(text, color, 11)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(22, 23, 21)
	style.border_color = Color8(90, 92, 83)
	style.set_border_width_all(2)
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	label.add_theme_stylebox_override("normal", style)
	return label


func _wide_button(text: String, callback: Callable) -> Button:
	var button := make_button(text, callback)
	button.custom_minimum_size.y = 38
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _function_button(text: String, callback: Callable) -> Button:
	var button := _wide_button(text, callback)
	button.custom_minimum_size.x = 290
	return button


func _screen_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, color, font_size)
	label.add_theme_font_override("font", load("res://assets/fonts/DSEG14Classic-Regular.ttf"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer
