class_name ModemConfigApp
extends WbApp
## Serielle Einstellungen als echte Workbench-1.3-App. Keine fremde RetroWindow-
## Chromatik: Topaz, Vierfarbenpalette, Gadgets und Bedienlogik kommen aus WbApp.

var _pulse := 0.0


func _init() -> void:
	app_title = Loc.t("ui.modem_config_window.app_title", "Serial Preferences · MODEM")
	app_bg = Wb13.blue()
	app_accent = Wb13.orange()


func _cfg() -> Dictionary:
	if not PlayerStats.peripherals.has("modem"):
		PlayerStats.peripherals["modem"] = {"dial": "ton", "speaker": true, "redial": false}
	return PlayerStats.peripherals["modem"]


func _build_app() -> void:
	_rebuild_widgets()


func _rebuild_widgets() -> void:
	clear_widgets()
	if not PlayerStats.has_modem():
		add_button(Loc.t("ui.modem_config_window.back", "ZURUECK"),
			Rect2(480, 344, 130, 28), close_app)
		_layout()
		return
	add_button(Loc.t("ui.modem_config_window.dial_mode", "WAHL: %s") % (
		Loc.t("ui.modem_config_window.tone", "TON") if str(_cfg().get("dial", "ton")) == "ton"
		else Loc.t("ui.modem_config_window.pulse", "PULS")),
		Rect2(280, 108, 150, 28), _toggle_dial)
	add_button(Loc.t("ui.modem_config_window.speaker", "LAUTSPRECHER: %s") % (
		Loc.t("ui.modem_config_window.on", "AN") if bool(_cfg().get("speaker", true))
		else Loc.t("ui.modem_config_window.off", "AUS")),
		Rect2(280, 150, 190, 28), _toggle_bool.bind("speaker"))
	add_button(Loc.t("ui.modem_config_window.redial", "WIEDERWAHL: %s") % (
		Loc.t("ui.modem_config_window.on", "AN") if bool(_cfg().get("redial", false))
		else Loc.t("ui.modem_config_window.off", "AUS")),
		Rect2(280, 192, 190, 28), _toggle_bool.bind("redial"))
	add_button(Loc.t("ui.modem_config_window.go_online", "ONLINE GEHEN"),
		Rect2(390, 330, 180, 32), _go_online)
	add_button(Loc.t("ui.modem_config_window.save", "SPEICHERN"),
		Rect2(170, 330, 150, 32), _save_and_close)
	_layout()


func _toggle_dial() -> void:
	_cfg()["dial"] = "puls" if str(_cfg().get("dial", "ton")) == "ton" else "ton"
	_rebuild_widgets()


func _toggle_bool(key: String) -> void:
	_cfg()[key] = not bool(_cfg().get(key, false))
	_rebuild_widgets()


func _save_and_close() -> void:
	PlayerStats.stats_changed.emit()
	UIManager.toast(Loc.t("ui.modem_config_window.modem_einstellungen_gespeichert", "Modem-Einstellungen gespeichert."))
	close_app()


func _go_online() -> void:
	PlayerStats.stats_changed.emit()
	close_app()
	UIManager.open_bbs()


func _app_process(delta: float) -> void:
	_pulse += delta


func _content(font: Font) -> void:
	# Arbeitsflaeche und zwei klassische WB-Gruppenrahmen.
	rect(18, 34, VW - 36, VH - 54, Wb13.white())
	rect_line(18, 34, VW - 36, VH - 54, Wb13.black(), 2)
	text(font, "SERIAL.DEVICE", 34, 60, 12, Wb13.black())
	text(font, Loc.t("ui.modem_config_window.serial_interface",
		"Amiga Workbench 1.3 · serielle Schnittstelle"), 34, 78, 9, Wb13.black())
	if not PlayerStats.has_modem():
		rect(52, 112, 536, 150, Wb13.blue())
		rect_line(52, 112, 536, 150, Wb13.black(), 2)
		text_c(font, Loc.t("ui.modem_config_window.no_modem", "KEIN MODEM ANGESCHLOSSEN"),
			52, 588, 154, 16, Wb13.white())
		text_c(font, Loc.t("ui.modem_config_window.buy_modem",
			"2400-Baud-Modem bei Gruber kaufen und am SERIAL-Port anschliessen."),
			52, 588, 188, 10, Wb13.white())
		text_c(font, Loc.t("ui.modem_config_window.settings_unlock",
			"Die Einstellungen werden danach automatisch freigeschaltet."),
			52, 588, 214, 10, Wb13.orange())
		return

	var baud := PlayerStats.modem_baud()
	# Linke Hardwaretafel: zeittypische RS-232-/Hayes-Anzeige.
	rect(42, 96, 208, 174, Wb13.blue())
	rect_line(42, 96, 208, 174, Wb13.black(), 2)
	text(font, Loc.t("ui.modem_config_window.external_modem", "EXTERNES MODEM"),
		58, 120, 11, Wb13.white())
	text(font, "%d BAUD · 8N1" % baud, 58, 145, 14, Wb13.orange())
	text(font, "SER:  serial.device", 58, 170, 9, Wb13.white())
	text(font, Loc.t("ui.modem_config_window.status", "STATUS: %s") % (
		"CONNECT" if BBSManager.connected() else "READY"),
		58, 194, 10, Wb13.white())
	for index in 4:
		var lit := BBSManager.connected() or (index == int(_pulse * 2.0) % 4 and MusicManager.is_playing())
		rect(60 + index * 42, 218, 24, 13, Wb13.orange() if lit else Wb13.black())
		text(font, ["MR", "TR", "SD", "RD"][index], 61 + index * 42, 251, 8, Wb13.black())

	text(font, Loc.t("ui.modem_config_window.dial_method", "WAEHLVERFAHREN"), 280, 98, 9, Wb13.black())
	text(font, Loc.t("ui.modem_config_window.modem_speaker", "MODEM-LAUTSPRECHER"), 280, 140, 9, Wb13.black())
	text(font, Loc.t("ui.modem_config_window.auto_redial", "AUTO-WIEDERWAHL"), 280, 182, 9, Wb13.black())
	rect(42, 286, 546, 24, Wb13.blue())
	text_c(font, "AT&F · %s · %s" % ["ATDT" if str(_cfg().get("dial", "ton")) == "ton" else "ATDP",
		"M1" if bool(_cfg().get("speaker", true)) else "M0"], 42, 588, 303, 10, Wb13.white())
	text(font, Loc.t("ui.modem_config_window.line_costs",
		"Leitungskosten erscheinen auf der monatlichen Telefonrechnung."),
		42, 382, 9, Wb13.black())
