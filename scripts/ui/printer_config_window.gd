class_name PrinterConfigApp
extends WbApp
## Drucker-Prefs im gemeinsamen Workbench-1.3-Rahmen. Die App konfiguriert
## reale Spielwerte und nutzt den Drucker weiterhin fuer Etiketten/Testseite.

const LABEL_ENERGY := 4
var _head_phase := 0.0


func _init() -> void:
	app_title = "Printer Preferences"
	app_bg = Wb13.blue()
	app_accent = Wb13.orange()


func _cfg() -> Dictionary:
	if not PlayerStats.peripherals.has("printer"):
		PlayerStats.peripherals["printer"] = {"quality": "nlq", "labels": "schmal"}
	return PlayerStats.peripherals["printer"]


func _build_app() -> void:
	_rebuild_widgets()


func _rebuild_widgets() -> void:
	clear_widgets()
	if not PlayerStats.has_printer():
		add_button("ZURUECK", Rect2(480, 344, 130, 28), close_app)
		_layout()
		return
	add_button("QUALITAET: %s" % ("NLQ" if str(_cfg().get("quality", "nlq")) == "nlq" else "ENTWURF"),
		Rect2(294, 106, 190, 28), _toggle_quality)
	add_button("ETIKETT: %s" % ("3,5 ZOLL" if str(_cfg().get("labels", "schmal")) == "schmal" else "5,25 ZOLL"),
		Rect2(294, 150, 190, 28), _toggle_labels)
	add_button("10 ETIKETTEN DRUCKEN", Rect2(294, 210, 230, 30), _print_labels)
	add_button("TESTSEITE", Rect2(294, 250, 130, 28), _test_page)
	add_button("AUSRICHTEN", Rect2(434, 250, 130, 28), _align)
	add_button("SPEICHERN", Rect2(390, 330, 180, 32), _save_and_close)
	_layout()


func _toggle_quality() -> void:
	_cfg()["quality"] = "entwurf" if str(_cfg().get("quality", "nlq")) == "nlq" else "nlq"
	_rebuild_widgets()


func _toggle_labels() -> void:
	_cfg()["labels"] = "breit" if str(_cfg().get("labels", "schmal")) == "schmal" else "schmal"
	_rebuild_widgets()


func _print_labels() -> void:
	if not PlayerStats.use_energy(LABEL_ENERGY):
		UIManager.toast(Loc.t("ui.printer_config_window.zu_muede_um_den_drucker_zu", "Zu muede, um den Drucker zu bedienen."))
		return
	InventoryManager.add_item(Loc.t("ui.printer_config_window.etiketten", "etiketten"), 10)
	_head_phase = 1.0
	AudioManager.play("printer", 0.0)
	UIManager.toast(Loc.t("ui.printer_config_window.10_diskettenetiketten_gedruckt_vorrat_d", "10 Diskettenetiketten gedruckt. Vorrat: %d.") % InventoryManager.count("etiketten"))


func _test_page() -> void:
	_head_phase = 1.0
	AudioManager.play("printer", 0.0)
	UIManager.toast(Loc.t("ui.printer_config_window.testseite_zeichensatz_linien_ausrichtung_sind_sauber", "Testseite: Zeichensatz, Linien und Ausrichtung sind sauber."))


func _align() -> void:
	close_app()
	UIManager.open_printer_align()


func _save_and_close() -> void:
	PlayerStats.stats_changed.emit()
	UIManager.toast(Loc.t("ui.printer_config_window.drucker_einstellungen_gespeichert", "Drucker-Einstellungen gespeichert."))
	close_app()


func _app_process(delta: float) -> void:
	_head_phase = maxf(0.0, _head_phase - delta * 0.5)


func _content(font: Font) -> void:
	rect(18, 34, VW - 36, VH - 54, Wb13.white())
	rect_line(18, 34, VW - 36, VH - 54, Wb13.black(), 2)
	text(font, "PRINTER.DEVICE", 34, 60, 12, Wb13.black())
	text(font, "Parallel-Port · Preferences", 34, 78, 9, Wb13.black())
	if not PlayerStats.has_printer():
		rect(52, 112, 536, 150, Wb13.blue())
		rect_line(52, 112, 536, 150, Wb13.black(), 2)
		text_c(font, "KEIN DRUCKER ANGESCHLOSSEN", 52, 588, 154, 16, Wb13.white())
		text_c(font, "Zeitgerechten Drucker kaufen und am PARALLEL-Port anschliessen.",
			52, 588, 188, 10, Wb13.white())
		text_c(font, "Danach stehen Testseite, Etikettendruck und Ausrichtung bereit.",
			52, 588, 214, 10, Wb13.orange())
		return

	# Schematische 9-/24-Nadel-Mechanik, bewusst in vier WB-Farben.
	rect(42, 98, 218, 184, Wb13.blue())
	rect_line(42, 98, 218, 184, Wb13.black(), 2)
	rect(68, 122, 166, 104, Wb13.white())
	rect_line(68, 122, 166, 104, Wb13.black(), 2)
	for y in 5:
		rect(84, 142 + y * 14, 132, 2, Wb13.black())
	var head_x := 82.0 + (112.0 * (1.0 - _head_phase))
	rect(head_x, 130, 18, 78, Wb13.orange())
	rect_line(head_x, 130, 18, 78, Wb13.black(), 1)
	text_c(font, "PAPIER", 68, 234, 248, 9, Wb13.black())
	text(font, PlayerStats.printer_name().to_upper(), 42, 306, 10, Wb13.black())
	text(font, "STATUS: BEREIT · PAPIER OK", 42, 326, 9, Wb13.black())
	text(font, "DRUCKQUALITAET", 294, 96, 9, Wb13.black())
	text(font, "ETIKETTENFORMAT", 294, 140, 9, Wb13.black())
	rect(294, 188, 270, 2, Wb13.black())
	text(font, "Selbstdruck: 4 Energie · +10 Etiketten", 294, 202, 9, Wb13.black())
	text(font, "PAR: printer.device · READY", 42, 382, 9, Wb13.black())
