extends RetroWindow
## INVENTAR-Fenster: Verbrauchsmaterial, Hardware und Laufwerkszustand.

const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")

var _pending_computer_sale := ""
var _pending_printer_sale := ""


func _init() -> void:
	title = Loc.t("ui.inventory_window.inventar_hardware", "INVENTAR & HARDWARE")
	win_size = Vector2(720, 700)
	chrome_accent = Palette.LCD_AMBER


func _ready() -> void:
	super._ready()
	# Das Hardwarefenster enthaelt Wartung, Rechnerbestand und die abgesicherte
	# Verkaufsaktion. Ein echter Scrollbereich haelt alle Schalter auch bei
	# kleinen Aufloesungen erreichbar, statt sie unter dem Fenster abzuschneiden.
	var margin := content.get_parent()
	margin.remove_child(content)
	var scroll := ScrollContainer.new()
	scroll.name = "InventoryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	InventoryManager.inventory_changed.connect(_refresh)
	PlayerStats.stats_changed.connect(_refresh)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_refresh()


## Ein Stück Proviant verzehren (Energie + Verpackung wird Müll). Das Fenster
## aktualisiert sich über inventory_changed/stats_changed selbst.
func _eat(id: String) -> void:
	var result: Dictionary = InventoryManager.consume_food(id)
	UIManager.toast(str(result.get("text", "")))


func _refresh() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.verbrauchsmaterial", "VERBRAUCHSMATERIAL"), Palette.LCD_AMBER))
	for id in InventoryManager.ITEM_NAMES:
		content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.s_d", "  %s: %d") % [
			_item_name(str(id)), InventoryManager.count(id)]))

	var owned_inserts := InsertCatalog.all_definitions().filter(func(entry: Dictionary) -> bool:
		return InsertCatalog.owns(str(entry.get("id", ""))))
	if not owned_inserts.is_empty():
		content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.sammlerbeilagen", "SAMMLERBEILAGEN")))
		for entry: Dictionary in owned_inserts:
			var row := HBoxContainer.new()
			var label := Bezel.body_label(Loc.t("ui.inventory_window.s_original", "  %s · ORIGINAL") % str(entry.get("title", "Beilage")))
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var software_id := str(entry.get("software_id", ""))
			var insert_id := str(entry.get("id", ""))
			var view_button := make_button(Loc.t("ui.inventory_window.ansehen", "ANSEHEN"), _open_insert.bind(software_id, insert_id))
			view_button.custom_minimum_size = Vector2(88, 24)
			row.add_child(view_button)
			content.add_child(row)

	# Proviant vom Kiosk — hier wird verzehrt (Energie; Verpackung wird zu Müll).
	var has_food := false
	for fid in InventoryManager.FOODS:
		if InventoryManager.count(fid) > 0:
			has_food = true
			break
	if has_food:
		content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.proviant_verzehren", "PROVIANT (verzehren)")))
		for fid in InventoryManager.FOODS:
			var owned := InventoryManager.count(fid)
			if owned <= 0:
				continue
			var food: Dictionary = InventoryManager.FOODS[fid]
			var row := HBoxContainer.new()
			row.add_child(Bezel.body_label(Loc.t("ui.inventory_window.s_d_d_energie", "  %s: %d  (+%d Energie)") % [
				_food_name(str(fid), str(food["name"])), owned, int(food["energy"])]))
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spacer)
			var eat_id := str(fid)
			var eat_btn := make_button(Loc.t("ui.inventory_window.verzehren", "Verzehren"), func() -> void: _eat(eat_id))
			eat_btn.custom_minimum_size = Vector2(96, 24)
			row.add_child(eat_btn)
			content.add_child(row)

	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.hardware", "HARDWARE"), Palette.LCD_CYAN))
	var drive_text := Loc.t("ui.inventory_window.drive_count.many", "%d Laufwerke") % 2 \
		if PlayerStats.has_hardware("external_drive") \
		else Loc.t("ui.inventory_window.drive_count.one", "1 Laufwerk")
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.aktiver_tischrechner_s_s_ram_s", "  Aktiver Tischrechner: %s (%s RAM, %s)") % [
		_computer_name(PlayerStats.desk_model("computer_model")),
		PlayerStats.ram_total_text(), drive_text]))
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.speicheraufteilung_s", "  Speicheraufteilung: %s") % PlayerStats.ram_configuration_text()))
	content.add_child(Bezel.body_label(Loc.t(
		"ui.inventory_window.cpu_chipsatz_s_s",
		"  CPU/Chipsatz: %s · %s") % [
			PlayerStats.cpu_description(), PlayerStats.chipset_description()]))
	content.add_child(Bezel.body_label(Loc.t(
		"ui.inventory_window.anschluesse_s",
		"  Anschlüsse: %s") % PlayerStats.interface_description()))
	var active_expansions: Array[String] = PlayerStats.expansion_summary()
	if not active_expansions.is_empty():
		content.add_child(Bezel.section_label(Loc.t(
			"ui.inventory_window.aktiver_rechnerausbau",
			"AKTIVER RECHNERAUSBAU")))
		for expansion: String in active_expansions:
			content.add_child(Bezel.body_label("  ✓ %s" % expansion))
	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.rechner_sammlung_nicht_eingetauscht", "RECHNER-SAMMLUNG · NICHT EINGETAUSCHT")))
	for model_value: Variant in RoomManager.available_device_models("computer_model", true):
		var model_id := str(model_value)
		var active := model_id == PlayerStats.desk_model("computer_model")
		var computer_row := HBoxContainer.new()
		var computer_label := Bezel.body_label(Loc.t("ui.inventory_window.s_s", "  %s · %s") % [
			_computer_name(model_id),
			Loc.t("ui.inventory_window.on_desk", "AUF DEM TISCH") if active \
			else Loc.t("ui.inventory_window.stored", "EINGELAGERT")])
		computer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		computer_row.add_child(computer_label)
		var use_button := make_button(Loc.t("ui.inventory_window.aktiv", "AKTIV") if active \
			else Loc.t("ui.inventory_window.set_up", "AUFSTELLEN"),
			_use_computer.bind(model_id))
		use_button.custom_minimum_size = Vector2(96, 24)
		use_button.disabled = active or GameManager.current_location_id != "room"
		if GameManager.current_location_id != "room":
			use_button.tooltip_text = Loc.t("ui.inventory_window.rechner_lassen_sich_nur_zu_hause", "Rechner lassen sich nur zu Hause im Zimmer umstellen.")
		else:
			use_button.tooltip_text = Loc.t("ui.inventory_window.andere_rechner_bleibt_eingelagert_geht_nicht", "Der andere Rechner bleibt eingelagert und geht nicht verloren.")
		computer_row.add_child(use_button)
		if not active:
			var resale := RoomManager.computer_resale_value(model_id)
			var sell_button := make_button(
				(Loc.t("ui.inventory_window.confirm_sale", "BESTÄTIGEN · +%d DM") % resale)
					if _pending_computer_sale == model_id
					else Loc.t("ui.inventory_window.sell", "VERKAUFEN · %d DM") % resale,
				_confirm_computer_sale.bind(model_id))
			sell_button.custom_minimum_size = Vector2(142, 24)
			sell_button.disabled = GameManager.current_location_id != "room" \
				or resale <= 0
			sell_button.tooltip_text = (Loc.t("ui.inventory_window.confirm_stored_computer_sale", "Noch einmal klicken: Der eingelagerte Rechner wird dauerhaft verkauft.")
				if _pending_computer_sale == model_id
				else Loc.t("ui.inventory_window.optional_computer_sale", "Optionaler Gebrauchtverkauf. Der aktive Rechner bleibt erhalten."))
			computer_row.add_child(sell_button)
		content.add_child(computer_row)

	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.drucker_sammlung_umschaltbar", "DRUCKER-SAMMLUNG · UMSCHALTBAR")))
	var owned_printers := RoomManager.available_device_models("printer_model", true)
	var active_printer := RoomManager.active_device_model("printer_model")
	if owned_printers.is_empty():
		content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.kein_drucker_im_besitz", "  Kein Drucker im Besitz.")))
	for model_value: Variant in owned_printers:
		var model_id := str(model_value)
		var active := model_id == active_printer
		var printer_row := HBoxContainer.new()
		var printer_label := Bezel.body_label(Loc.t("ui.inventory_window.s_s", "  %s · %s") % [
			RoomManager.printer_display_name(model_id),
			Loc.t("ui.inventory_window.connected", "ANGESCHLOSSEN") if active \
			else Loc.t("ui.inventory_window.stored", "EINGELAGERT")])
		printer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		printer_row.add_child(printer_label)
		var use_button := make_button(Loc.t("ui.inventory_window.aktiv", "AKTIV") if active \
			else Loc.t("ui.inventory_window.connect", "ANSCHLIESSEN"),
			_use_printer.bind(model_id))
		use_button.custom_minimum_size = Vector2(104, 24)
		use_button.disabled = active or GameManager.current_location_id != "room"
		use_button.tooltip_text = (Loc.t("ui.inventory_window.printer_home_only", "Drucker lassen sich nur zu Hause anschließen.")
			if GameManager.current_location_id != "room" else
			Loc.t("ui.inventory_window.previous_printer_stored", "Der bisherige Drucker bleibt sicher eingelagert."))
		printer_row.add_child(use_button)
		var resale := RoomManager.printer_resale_value(model_id)
		var sell_button := make_button(
			(Loc.t("ui.inventory_window.confirm_sale", "BESTÄTIGEN · +%d DM") % resale)
				if _pending_printer_sale == model_id
				else Loc.t("ui.inventory_window.sell", "VERKAUFEN · %d DM") % resale,
			_confirm_printer_sale.bind(model_id))
		sell_button.custom_minimum_size = Vector2(142, 24)
		sell_button.disabled = GameManager.current_location_id != "room" or resale <= 0
		sell_button.tooltip_text = (Loc.t("ui.inventory_window.confirm_printer_sale", "Noch einmal klicken: Dieser Drucker wird dauerhaft verkauft.")
			if _pending_printer_sale == model_id else
			Loc.t("ui.inventory_window.optional_printer_sale", "Optionaler Gebrauchtverkauf · mindestens die Hälfte des möglichen Kaufpreises."))
		printer_row.add_child(sell_button)
		content.add_child(printer_row)

	if PlayerStats.has_hardware("external_drive"):
		content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.externes_laufwerk_df1_schneller_sicherer", "  Externes Laufwerk DF1 (schneller, sicherer)")))
	if PlayerStats.has_hardware("modem"):
		content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.modem_2400_baud_bbs_uber_nacht", "  Modem 2400 Baud · BBS über NACHT-COMM")))
	if PlayerStats.has_hardware("cd_burner"):
		content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.cd_brenner_angeschlossen", "  CD-Brenner · angeschlossen")))

	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.laufwerk", "LAUFWERK"), Palette.LCD_CYAN))
	var dirt := PlayerStats.drive_dirt()
	var cleanliness := PlayerStats.drive_cleanliness()
	var alignment := PlayerStats.drive_alignment()
	var condition := PlayerStats.drive_condition()
	var dirt_text := Loc.t("ui.inventory_window.clean", "sauber")
	if dirt > 0.6:
		dirt_text = Loc.t("ui.inventory_window.heavily_dirty", "STARK VERSCHMUTZT!")
	elif dirt > 0.25:
		dirt_text = Loc.t("ui.inventory_window.dirty", "verschmutzt")
	elif dirt > 0.001:
		dirt_text = Loc.t("ui.inventory_window.slightly_dirty", "leicht verschmutzt")
	var condition_text := Loc.t("ui.inventory_window.operational", "EINSATZBEREIT")
	if condition < 0.50:
		condition_text = Loc.t("ui.inventory_window.maintenance_required", "WARTUNG NÖTIG!")
	elif condition < 0.80:
		condition_text = Loc.t("ui.inventory_window.limited", "EINGESCHRÄNKT")
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.gesamtzustand_d_s", "  Gesamtzustand: %d %% · %s") % [
		roundi(condition * 100.0), condition_text]))
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.spurtreue_d_s", "  Spurtreue: %d %% · %s") % [
		roundi(alignment * 100.0),
		Loc.t("ui.inventory_window.aligned", "justiert") if alignment >= 0.999 \
		else Loc.t("ui.inventory_window.misaligned", "DEJUSTIERT")]))
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.sauberkeit_d_s_d_verschmutzung", "  Sauberkeit: %d %% · %s (%d %% Verschmutzung)") % [
		roundi(cleanliness * 100.0), dirt_text, roundi(dirt * 100.0)]))

	# Angezeigt wird der echte, von DF0 verursachte Zusatz aus Schmutz UND
	# Dejustage. DF1 senkt wie in DiskManager beide Anteile auf 60 Prozent.
	var drive_factor := DiskManager.EXT_DRIVE_ERROR_FACTOR \
		if PlayerStats.has_hardware("external_drive") else 1.0
	var misalignment := 1.0 - alignment
	var read_extra := (dirt * DiskManager.READ_DIRT_ERROR_FACTOR \
		+ misalignment * DiskManager.READ_ALIGNMENT_ERROR_FACTOR) * drive_factor * 100.0
	var write_extra := (dirt * DiskManager.WRITE_DIRT_ERROR_FACTOR \
		+ misalignment * DiskManager.WRITE_ALIGNMENT_ERROR_FACTOR) * drive_factor * 100.0
	var read_text := ("%.1f" % read_extra).replace(".", ",")
	var write_text := ("%.1f" % write_extra).replace(".", ",")
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.zusatzrisiko_lesen_s_schreiben_s", "  Zusatzrisiko: Lesen +%s %% · Schreiben +%s %%") % [
		read_text, write_text]))

	var clean_button := make_button(
		Loc.t("ui.inventory_window.lesekopf_reinigen", "LESEKOPF REINIGEN") if dirt > 0.001 \
		else Loc.t("ui.inventory_window.read_head_clean", "✓ LESEKOPF SAUBER"),
		UIManager.open_drive_clean)
	clean_button.custom_minimum_size = Vector2(0, 30)
	clean_button.disabled = dirt <= 0.001 or InventoryManager.count("reinigungsdiskette") <= 0
	if dirt <= 0.001:
		clean_button.tooltip_text = Loc.t("ui.inventory_window.lesekopf_ist_bereits_sauber", "Der Lesekopf ist bereits sauber.")
	elif InventoryManager.count("reinigungsdiskette") <= 0:
		clean_button.tooltip_text = Loc.t("ui.inventory_window.keine_reinigungsdiskette_im_inventar", "Keine Reinigungsdiskette im Inventar.")
	else:
		clean_button.tooltip_text = Loc.t("ui.inventory_window.reinigungsdiskette_vorbereiten_lesekopf_warten", "Reinigungsdiskette vorbereiten und Lesekopf warten.")
	content.add_child(clean_button)

	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.joystick", "JOYSTICK"), Palette.LCD_CYAN))
	var joy_condition := PlayerStats.joystick_condition()
	var joy_text := Loc.t("ui.inventory_window.stable", "stabil")
	if joy_condition < 0.35:
		joy_text = Loc.t("ui.inventory_window.direction_failing", "RICHTUNG FÄLLT AUS!")
	elif joy_condition < 0.70:
		joy_text = Loc.t("ui.inventory_window.loose_contact", "Wackelkontakt")
	elif joy_condition < 0.999:
		joy_text = Loc.t("ui.inventory_window.intermittent_faults", "gelegentliche Aussetzer")
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.4_kanal_stick_d_s", "  4-Kanal-Stick: %d %% · %s") % [roundi(joy_condition * 100.0), joy_text]))
	var repair_button := make_button(
		Loc.t("ui.inventory_window.joystick_loten", "JOYSTICK LÖTEN") if joy_condition < 0.999 \
		else Loc.t("ui.inventory_window.joystick_repaired", "✓ JOYSTICK REPARIERT"), UIManager.open_joystick_repair)
	repair_button.custom_minimum_size = Vector2(0, 30)
	var knowledge := int(GameManager.flags.get("hardware_knowledge", 0))
	repair_button.disabled = joy_condition >= 0.999 or knowledge < 1 or PlayerStats.energie < 6
	if joy_condition >= 0.999:
		repair_button.tooltip_text = Loc.t("ui.inventory_window.alle_vier_richtungen_sind_stabil_bei", "Alle vier Richtungen sind stabil. Bei einem neuen Wackelkontakt wird die Werkstatt wieder verfügbar.")
	elif knowledge < 1:
		repair_button.tooltip_text = Loc.t("ui.inventory_window.lass_dir_loten_zuerst_an_svens", "Lass dir das Löten zuerst an Svens Werkbank zeigen.")
	elif PlayerStats.energie < 6:
		repair_button.tooltip_text = Loc.t("ui.inventory_window.zu_mude_fur_ruhige_lotarbeit_6", "Zu müde für ruhige Lötarbeit (6 Energie nötig).")
	else:
		repair_button.tooltip_text = Loc.t("ui.inventory_window.vier_richtungsleitungen_verbinden_loten_prufen", "Vier Richtungsleitungen verbinden, löten und prüfen.")
	content.add_child(repair_button)

	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.monitor_service", "MONITOR-SERVICE"), Palette.LCD_CYAN))
	var monitor_state := Loc.t("ui.inventory_window.calibrated", "kalibriert") \
		if bool(GameManager.flags.get("monitor_calibrated", false)) \
		else Loc.t("ui.inventory_window.not_calibrated", "Testbild noch nicht abgeglichen")
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.crt_bild_s", "  CRT-Bild: %s") % monitor_state))
	var tune_button := make_button(Loc.t("ui.inventory_window.testbild_bewusst_justieren", "TESTBILD BEWUSST JUSTIEREN"), UIManager.open_monitor_tune)
	tune_button.custom_minimum_size = Vector2(0, 30)
	tune_button.disabled = GameManager.current_location_id != "room" or not UIManager.monitor_power \
		or not bool(GameManager.flags.get("learned_monitor_calibration", false))
	if GameManager.current_location_id != "room":
		tune_button.tooltip_text = Loc.t("ui.inventory_window.service_ist_nur_am_eigenen_monitor", "Service ist nur am eigenen Monitor im Zimmer moeglich.")
	elif not UIManager.monitor_power:
		tune_button.tooltip_text = Loc.t("ui.inventory_window.monitor_mehrfachverteiler_muessen_eingeschaltet_sein", "Monitor und Mehrfachverteiler muessen eingeschaltet sein.")
	elif not bool(GameManager.flags.get("learned_monitor_calibration", false)):
		tune_button.tooltip_text = Loc.t("ui.inventory_window.lass_dir_sichere_justage_zuerst_von", "Lass dir die sichere Justage zuerst von Gruber oder einem bastelnden Freund zeigen.")
	else:
		tune_button.tooltip_text = Loc.t("ui.inventory_window.oeffnet_den_crt_service_absichtlich_normale", "Oeffnet den CRT-Service absichtlich; der normale Monitorklick startet den Rechner.")
	content.add_child(tune_button)

	content.add_child(Bezel.section_label(Loc.t("ui.inventory_window.spielwerte", "SPIELWERTE"), Palette.LCD_CYAN))
	content.add_child(Bezel.body_label(Loc.t("ui.inventory_window.wissen_d_eltern_toleranz_d", "  Wissen: %d · Eltern-Toleranz: %d") % [
		PlayerStats.wissen, PlayerStats.eltern_toleranz]))


func _open_insert(software_id: String, insert_id: String) -> void:
	UIManager.open_software_inserts(software_id, insert_id)


func _computer_name(model_id: String) -> String:
	return str({
		"amiga_500": "Amiga 500",
		"amiga_600": "Amiga 600",
		"amiga_1200": "Amiga 1200",
	}.get(model_id, model_id.replace("_", " ").capitalize()))


func _item_name(item_id: String) -> String:
	return Loc.t("inventory.item.%s" % item_id, str(InventoryManager.ITEM_NAMES.get(item_id, item_id)))


func _food_name(food_id: String, fallback: String) -> String:
	return Loc.t("inventory.food.%s" % food_id, fallback)


func _on_locale_changed(_locale: String) -> void:
	title = Loc.t("ui.inventory_window.inventar_hardware", "INVENTAR & HARDWARE")
	_refresh()


func _use_computer(model_id: String) -> void:
	if GameManager.current_location_id != "room":
		UIManager.toast(Loc.t("ui.inventory_window.den_tischrechner_kannst_du_nur_zu", "Den Tischrechner kannst du nur zu Hause umstellen."))
		return
	var previous := PlayerStats.desk_model("computer_model")
	if previous == model_id:
		return
	_pending_computer_sale = ""
	if not RoomManager.select_device_model("computer_model", model_id):
		UIManager.toast(Loc.t("ui.inventory_window.dieser_rechner_gehort_noch_nicht_zu", "Dieser Rechner gehört noch nicht zu deiner Sammlung."))
		return
	UIManager.reset_computer()
	UIManager.toast(Loc.t("ui.inventory_window.s_steht_jetzt_auf_dem_tisch", "%s steht jetzt auf dem Tisch. %s bleibt sicher eingelagert.") % [
		_computer_name(model_id), _computer_name(previous)])


func _use_printer(model_id: String) -> void:
	if GameManager.current_location_id != "room":
		UIManager.toast(Loc.t("ui.inventory_window.den_drucker_kannst_du_nur_zu", "Den Drucker kannst du nur zu Hause umstellen."))
		return
	var previous := RoomManager.active_device_model("printer_model")
	if previous == model_id:
		return
	_pending_printer_sale = ""
	if not RoomManager.select_device_model("printer_model", model_id):
		UIManager.toast(Loc.t("ui.inventory_window.dieser_drucker_gehort_noch_nicht_zu", "Dieser Drucker gehört noch nicht zu deinem Inventar."))
		return
	UIManager.toast(Loc.t("ui.inventory_window.s_ist_jetzt_angeschlossen_s_bleibt", "%s ist jetzt angeschlossen. %s bleibt eingelagert.") % [
		RoomManager.printer_display_name(model_id),
		RoomManager.printer_display_name(previous)])


func _confirm_computer_sale(model_id: String) -> void:
	if _pending_computer_sale != model_id:
		_pending_computer_sale = model_id
		_refresh()
		UIManager.toast(Loc.t("ui.inventory_window.s_wirklich_verkaufen_klicke_bestatigen_verkauf", "%s wirklich verkaufen? Klicke BESTÄTIGEN; der Verkauf ist dauerhaft.") \
			% _computer_name(model_id))
		return
	_pending_computer_sale = ""
	var result := RoomManager.sell_computer(model_id)
	UIManager.toast(str(result.get("text", Loc.t("ui.common.sale_not_possible", "Verkauf nicht möglich."))))
	_refresh()


func _confirm_printer_sale(model_id: String) -> void:
	if _pending_printer_sale != model_id:
		_pending_printer_sale = model_id
		_refresh()
		UIManager.toast(Loc.t("ui.inventory_window.s_wirklich_verkaufen_klicke_bestatigen_verkauf", "%s wirklich verkaufen? Klicke BESTÄTIGEN; der Verkauf ist dauerhaft.") \
			% RoomManager.printer_display_name(model_id))
		return
	_pending_printer_sale = ""
	var result := RoomManager.sell_printer(model_id)
	UIManager.toast(str(result.get("text", Loc.t("ui.common.sale_not_possible", "Verkauf nicht möglich."))))
	_refresh()
