extends RetroWindow
## Grubers Hardware-Konfigurator. Logik/Preise bleiben vollstaendig im
## HardwareManager; dieses Fenster ist die visuelle, era-gerechte Katalogschicht:
## Kategorien, echte Master-Assets, Upgradepfade, Status und Detailkauf.

const ShopEra := preload("res://scripts/data/computer_shop_era.gd")
const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")

const PREVIEW_ASSETS := {
	"a500": "res://assets/backgrounds/layers/COMPUTER_AMIGA500_V02.png",
}

var _list: GridContainer
var _level_label: Label
var _progress_label: Label
var _progress: ProgressBar
var _system_label: Label
var _track_row: HBoxContainer
var _track_buttons: Dictionary = {}
var _detail_title: Label
var _detail_status: Label
var _detail_text: RichTextLabel
var _purchase_hint: Label
var _preview_host: PanelContainer
var _action: Button
var _selected_track := "computer"
var _selected_node := "a500"
var _refresh_pending := false


func _init() -> void:
	title = Loc.t("ui.upgrade_tree_window.s_hardware_konfigurator", "%s · HARDWARE-KONFIGURATOR") % ShopEra.business_name()
	win_size = Vector2(1120, 760)


func _ready() -> void:
	super._ready()
	_build_header()
	_build_track_tabs()
	_build_body()
	# Geld-, Bestell- und Hardware-Aenderungen koennen innerhalb eines einzigen
	# Kaufvorgangs mehrere Signale senden. Ein gebuendelter Refresh verhindert
	# doppelte Karten-Neuaufbauten mitten im gedrueckten Button-Signal.
	HardwareManager.upgrades_changed.connect(_request_refresh)
	_refresh()


func _build_header() -> void:
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", _panel_style(Color("12161d"), Color("39485a"), 1, 8))
	content.add_child(hero)
	var margin := MarginContainer.new()
	_set_margins(margin, 12, 10)
	hero.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var kicker := Bezel.lcd_label(Loc.t("ui.upgrade_tree_window.s_konfiguration_1990_99", "%s · KONFIGURATION 1990–99") % ShopEra.business_name(), Palette.LCD_AMBER, 11)
	copy.add_child(kicker)
	var intro := Bezel.dim_label(Loc.t("ui.upgrade_tree_window.nicht_irgendein_teil_richtige_teil_zur", "»Nicht irgendein Teil. Das richtige Teil zur richtigen Zeit.«"), 11)
	intro.modulate = Color(0.82, 0.85, 0.90)
	copy.add_child(intro)
	_system_label = Bezel.lcd_label("", Palette.LCD_CYAN, 12)
	_system_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_system_label.tooltip_text = Loc.t("ui.upgrade_tree_window.active_system_tooltip",
		"Aktiver Rechner · reale CPU-/I/O-Leistung · Speicher · Bildschirmmodus · Systemlaufwerk")
	copy.add_child(_system_label)
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = 300
	row.add_child(stats)
	_level_label = Bezel.lcd_label("", Palette.LCD_GREEN, 12)
	stats.add_child(_level_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(300, 8)
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background", _panel_style(Color("090b0f"), Color("303844"), 1, 3))
	_progress.add_theme_stylebox_override("fill", _panel_style(Color("d8902c"), Color("ffc35a"), 0, 3))
	stats.add_child(_progress)
	_progress_label = Bezel.dim_label("", 11)
	stats.add_child(_progress_label)


func _build_track_tabs() -> void:
	_track_row = HBoxContainer.new()
	_track_row.add_theme_constant_override("separation", 5)
	content.add_child(_track_row)
	_sync_track_tabs()


func _sync_track_tabs() -> void:
	var era_tracks: Array = HardwareManager.visible_tracks()
	var wanted: Array[String] = []
	for track: Dictionary in era_tracks:
		wanted.append(str(track.get("id", "")))
	var rebuild := wanted.size() != _track_buttons.size()
	if not rebuild:
		for id: String in wanted:
			if not _track_buttons.has(id):
				rebuild = true
				break
	if not rebuild:
		return
	_clear_children_safely(_track_row)
	_track_buttons.clear()
	for track: Dictionary in era_tracks:
		var id := str(track.get("id", ""))
		var button := make_button(str(track.get("name", id)), _select_track.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = Loc.t("ui.upgrade_tree_window.upgradepfad_anzeigen", "Upgradepfad anzeigen")
		_track_buttons[id] = button
		_track_row.add_child(button)


func _build_body() -> void:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	content.add_child(body)

	var catalog_panel := PanelContainer.new()
	catalog_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog_panel.add_theme_stylebox_override("panel", _panel_style(Color("0d1015"), Color("29313d"), 1, 7))
	body.add_child(catalog_panel)
	var catalog_margin := MarginContainer.new()
	_set_margins(catalog_margin, 10, 10)
	catalog_panel.add_child(catalog_margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalog_margin.add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 2
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_list)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.x = 330
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("12161c"), Color("516173"), 1, 7))
	body.add_child(detail_panel)
	var detail_margin := MarginContainer.new()
	_set_margins(detail_margin, 12, 12)
	detail_panel.add_child(detail_margin)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 7)
	detail_margin.add_child(detail)
	var label := Bezel.lcd_label(Loc.t("ui.upgrade_tree_window.ausgewahlte_komponente", "AUSGEWÄHLTE KOMPONENTE"), Palette.LCD_AMBER, 12)
	detail.add_child(label)
	_preview_host = PanelContainer.new()
	_preview_host.custom_minimum_size = Vector2(300, 190)
	_preview_host.add_theme_stylebox_override("panel", _panel_style(Color("090c11"), Color("303b49"), 1, 5))
	detail.add_child(_preview_host)
	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 17)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_title)
	_detail_status = Bezel.lcd_label("", Palette.LCD_GREEN, 12)
	detail.add_child(_detail_status)
	_detail_text = RichTextLabel.new()
	_detail_text.bbcode_enabled = true
	_detail_text.fit_content = false
	_detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_text.add_theme_font_size_override("normal_font_size", 13)
	_detail_text.add_theme_constant_override("line_separation", 3)
	detail.add_child(_detail_text)
	_purchase_hint = Bezel.dim_label("", 11)
	_purchase_hint.custom_minimum_size.y = 28
	_purchase_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_purchase_hint)
	_action = make_button("", _buy_selected)
	_action.custom_minimum_size.y = 42
	detail.add_child(_action)
	var tip := Bezel.dim_label(Loc.t("ui.upgrade_tree_window.karte_wahlen_details_prufen_bei_s", "Karte wählen · Details prüfen · bei %s kaufen oder bestellen") % \
		ShopEra.owner_name(), 9)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tip)


func _refresh() -> void:
	if not is_inside_tree():
		return
	_sync_track_tabs()
	var era_tracks: Array = HardwareManager.visible_tracks()
	if not era_tracks.any(func(track: Dictionary) -> bool: return str(track.get("id", "")) == _selected_track):
		_selected_track = str((era_tracks[0] as Dictionary).get("id", "")) if not era_tracks.is_empty() else ""
	var visible_ids: Array = HardwareManager.visible_node_ids()
	var total := visible_ids.size()
	var installed := 0
	for id: String in visible_ids:
		var state := HardwareManager.node_state(id)
		if bool(state.get("active", false)):
			installed += 1
	_level_label.text = Loc.t("ui.upgrade_tree_window.ausbaustufe_d_s", "AUSBAUSTUFE %d   ·   %s") % [
		PlayerStats.hardware_level(), Currency.format(PlayerStats.geld)]
	_progress.max_value = maxi(total, 1)
	_progress.value = installed
	_progress_label.text = Loc.t("ui.upgrade_tree_window.d_d_aktive_komponenten_im_ausbauplan", "%d / %d aktive Komponenten im Ausbauplan") % [installed, total]
	_refresh_system_summary()
	_refresh_tabs()
	_rebuild_cards()
	_refresh_detail()


## Die Katalogkarten erklaeren die einzelne Komponente. Diese Zeile beantwortet
## dagegen jederzeit die wichtigere Spielerfrage: Was bewirkt mein *aktiver*
## Ausbau jetzt tatsaechlich? Alle Werte kommen aus denselben Runtime-Vertraegen
## wie Workbench, SysInfo, Kopierzeiten und Szene-Renderer; keine Werbetexte.
func _refresh_system_summary() -> void:
	if _system_label == null:
		return
	var performance: Dictionary = PlayerStats.performance_profile()
	var computer := str(performance.get("computer_model", "amiga_500"))
	var computer_name := str({
		"amiga_500": "AMIGA 500", "amiga_600": "AMIGA 600", "amiga_1200": "AMIGA 1200",
	}.get(computer, computer.to_upper()))
	var ram_total_kb := int(performance.get("ram_total_kb", 512))
	var chip_kb := int(performance.get("chip_ram_kb", mini(ram_total_kb, 512)))
	var fast_kb := int(performance.get("fast_ram_kb", 0))
	var hdd: Dictionary = PlayerStats.hdd_info(computer)
	var hdd_bootable := bool(hdd.get("bootable", false)) \
		and not str(hdd.get("installed_profile", "")).is_empty()
	var workbench_id := str(hdd.get("installed_profile", "")) if hdd_bootable \
		else WorkbenchVersions.native_id(computer)
	var workbench_name := str(WorkbenchVersions.profile(workbench_id).get("name", workbench_id.to_upper()))
	var monitor_id := PlayerStats.desk_model("monitor_model")
	var workspace: Dictionary = MonitorProfile.workbench_workspace(
		workbench_id, monitor_id, computer, "auto")
	var resolution: Array = workspace.get("resolution", [640, 256])
	var resolution_text := "%d×%d" % [int(resolution[0]), int(resolution[1])] \
		if resolution.size() >= 2 else "PAL"
	var storage_text := Loc.t("ui.upgrade_tree_window.no_system_drive", "DF0: · KEIN SYSTEMLAUFWERK")
	if bool(hdd.get("available", false)):
		var capacity_mb := float(int(hdd.get("capacity_kb", 0))) / 1024.0
		storage_text = Loc.t("ui.upgrade_tree_window.system_drive_ready",
			"DH0: %.0f MB · %s · %s") % [
			capacity_mb,
			workbench_name if hdd_bootable else Loc.t("ui.upgrade_tree_window.not_bootable", "NICHT BOOTFÄHIG"),
			Loc.t("ui.upgrade_tree_window.hdd_boot", "HDD-BOOT") if hdd_bootable
				else Loc.t("ui.upgrade_tree_window.floppy_boot", "DISKETTEN-BOOT"),
		]
	_system_label.text = Loc.t("ui.upgrade_tree_window.active_system_summary",
		"AKTIV · %s · %s · CPU ×%.1f / I/O ×%.1f · RAM %.1f MB (CHIP %.1f / FAST %.1f)\nBILD · %s · %s · %s") % [
		computer_name,
		str(performance.get("chipset", "OCS · PAL 50 Hz")),
		float(performance.get("cpu_speed_multiplier", 1.0)),
		float(performance.get("io_speed_multiplier", 1.0)),
		float(ram_total_kb) / 1024.0,
		float(chip_kb) / 1024.0,
		float(fast_kb) / 1024.0,
		str(workspace.get("monitor_name", monitor_id)), resolution_text, storage_text,
	]


## Manager-Signale duerfen den Control-Baum nicht synchron waehrend eines
## pressed-Signals umbauen. Mehrere Aenderungen werden zu einem Refresh am
## Ende des aktuellen Frames zusammengefasst.
func _request_refresh() -> void:
	if not is_inside_tree() or _refresh_pending:
		return
	_refresh_pending = true
	call_deferred("_flush_refresh")


func _flush_refresh() -> void:
	# Ein Test oder ein expliziter Sofort-Flush kann vor dem bereits geplanten
	# deferred-Aufruf laufen. Der spaetere Aufruf darf dann nicht ein zweites Mal
	# denselben Baum bauen.
	if not _refresh_pending:
		return
	_refresh_pending = false
	_refresh()


func _refresh_tabs() -> void:
	for track: Dictionary in HardwareManager.visible_tracks():
		var id := str(track.get("id", ""))
		var nodes: Array = track.get("nodes", [])
		var owned_count := 0
		for node: Dictionary in nodes:
			if bool(HardwareManager.node_state(str(node.get("id", ""))).get("active", false)):
				owned_count += 1
		var button: Button = _track_buttons.get(id)
		if button == null:
			continue
		button.text = Loc.t("ui.upgrade_tree_window.s_d_d", "%s  %d/%d") % [_track_short(id, str(track.get("name", id))), owned_count, nodes.size()]
		button.modulate = Palette.ORANGE if id == _selected_track else Color.WHITE


func _rebuild_cards() -> void:
	# Sofort aus dem Layout loesen, aber erst sicher am Frame-Ende freigeben.
	# free() ist hier unzulaessig: Die gewaehlte Karte kann gerade noch ihr
	# pressed-Signal senden und ist dann von Godot gesperrt.
	_clear_children_safely(_list)
	var nodes := _track_nodes(_selected_track)
	if nodes.is_empty():
		return
	if not nodes.any(func(node: Dictionary) -> bool: return str(node.get("id", "")) == _selected_node):
		_selected_node = str((nodes[0] as Dictionary).get("id", ""))
	for node: Dictionary in nodes:
		_list.add_child(_node_card(str(node.get("id", ""))))


func _node_card(id: String) -> Control:
	var state := HardwareManager.node_state(id)
	var selected := id == _selected_node
	var accent := _state_color(state)
	var card := Button.new()
	card.text = ""
	card.custom_minimum_size = Vector2(300, 145)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	card.tooltip_text = Loc.t("ui.upgrade_tree_window.s_details_offnen", "%s — Details öffnen") % str(state.get("name", id))
	card.add_theme_stylebox_override("normal", _panel_style(Color("151a21"), Palette.LCD_AMBER if selected else accent.darkened(0.28), 3 if selected else 1, 7))
	card.add_theme_stylebox_override("hover", _panel_style(Color("1c232d"), accent, 2, 7))
	card.add_theme_stylebox_override("pressed", _panel_style(Color("10141a"), Palette.LCD_AMBER, 3, 7))
	card.pressed.connect(_select_node.bind(id))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_margins(margin, 9, 9)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	var preview := _make_preview(id, Vector2(108, 112), bool(state.get("owned", false)) or bool(state.get("available", false)))
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(preview)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var name_label := Label.new()
	name_label.text = str(state.get("name", id))
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(name_label)
	var badge := Bezel.lcd_label(_state_text(state), accent, 11)
	copy.add_child(badge)
	var effect := Bezel.dim_label(str(state.get("effect", "")), 11)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.modulate = Color(0.82, 0.85, 0.9)
	effect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(effect)
	if bool(state.get("available", false)):
		var price := Bezel.lcd_label(Currency.format(float(state.get("price", 0.0))), Palette.LCD_AMBER, 10)
		copy.add_child(price)
	return card


func _refresh_detail() -> void:
	_purchase_hint.modulate = Color.WHITE
	_action.tooltip_text = ""
	var state := HardwareManager.node_state(_selected_node)
	if state.is_empty() or not bool(state.get("visible", false)):
		_detail_title.text = Loc.t("ui.upgrade_tree_window.kein_aktuelles_modell", "Kein aktuelles Modell")
		_detail_status.text = ""
		_detail_text.text = Loc.t("ui.upgrade_tree_window.s_fuhrt_in_dieser_kategorie_derzeit", "%s führt in dieser Kategorie derzeit keine weitere Ausbaustufe.") % \
			ShopEra.owner_name()
		_purchase_hint.text = ""
		_action.text = Loc.t("ui.upgrade_tree_window.nicht_im_aktuellen_sortiment", "NICHT IM AKTUELLEN SORTIMENT")
		_action.disabled = true
		return
	_clear_children_safely(_preview_host)
	var preview := _make_preview(_selected_node, Vector2(300, 190), true)
	_preview_host.add_child(preview)
	_detail_title.text = str(state.get("name", _selected_node))
	var accent := _state_color(state)
	_detail_status.text = _state_text(state)
	_detail_status.modulate = accent
	var item: Dictionary = state.get("item", {})
	var lines: Array[String] = []
	var desc := str(item.get("desc", ""))
	if desc != "":
		lines.append(desc)
	var effect := str(state.get("effect", ""))
	if effect != "":
		lines.append("\n[color=#79D98B][b]%s[/b][/color]\n%s" % [
			Loc.t("ui.upgrade_tree_window.wirkung", "WIRKUNG"), effect])
	var requirements: Array = (state.get("node", {}) as Dictionary).get("requires", [])
	if not requirements.is_empty():
		var names: Array[String] = []
		for req: Variant in requirements:
			names.append(str(HardwareManager.node_state(str(req)).get("name", req)) \
				if HardwareManager.node_visible(str(req)) else Loc.t("ui.upgrade_tree_window.fruehere_ausbaustufe", "frühere Ausbaustufe"))
		lines.append(Loc.t("ui.upgrade_tree_window.upgrade_pfad_s", "\n[b]Upgrade-Pfad:[/b] %s") % " + ".join(names))
	var year := int(state.get("year_available", 1990))
	var order_days := int(item.get("order_days", 0))
	var delivery := Loc.t("ui.upgrade_tree_window.lieferzeit_ca_d_tage", " · Lieferzeit ca. %d Tage") % order_days \
		if order_days > 0 else Loc.t("ui.upgrade_tree_window.sofort_aus_dem_regal", " · sofort aus dem Regal")
	lines.append(Loc.t("ui.upgrade_tree_window.verfuegbar_ab_d_s", "[b]Verfügbar:[/b] ab %d%s") % [year, delivery])
	var price := float(state.get("price", 0.0))
	var base_price := float(state.get("base_price", price))
	var price_factor := float(state.get("price_factor", 1.0))
	if price > 0.0:
		var price_line := Loc.t("ui.upgrade_tree_window.heutiger_preis_s", "[b]Heutiger Preis:[/b] %s") % Currency.format(price)
		if not is_equal_approx(price, base_price):
			price_line += Loc.t("ui.upgrade_tree_window.katalogbasis_s_markt_f", "  [color=#8995A6](Katalogbasis %s · Markt ×%.2f)[/color]") % [
				Currency.format(base_price), price_factor]
		lines.append(price_line)
	var catalog: Dictionary = state.get("catalog", {})
	if not catalog.is_empty():
		# Das belegte Endjahr ist Validierungswissen, keine Information, die
		# Gruber dem Spieler Jahre im Voraus prophezeit.
		lines.append(Loc.t("ui.upgrade_tree_window.hardware_bibel_s_markteinfuehrung_d", "[color=#8995A6]Hardware-Bibel: %s · Markteinführung %d[/color]") % [
			str(catalog.get("name", "")), int(catalog.get("year_from", year))])
	_detail_text.text = "\n".join(lines)
	if bool(state.get("owned", false)):
		_action.text = Loc.t("ui.upgrade_tree_window.bereits_eingebaut", "✓ BEREITS EINGEBAUT")
		_action.disabled = true
		_purchase_hint.text = Loc.t("ui.upgrade_tree_window.workbench_sysinfo_inventar_lesen_den_eingebauten", "Workbench, SysInfo und Inventar lesen den eingebauten Zustand direkt aus der Hardwarekonfiguration.")
	elif bool(state.get("pending", false)):
		_action.text = Loc.t("ui.upgrade_tree_window.bestellt_noch_d_tage", "⧗ BESTELLT · NOCH %d TAGE") % int(state.get("days_left", 0))
		_action.disabled = true
		_purchase_hint.text = Loc.t("ui.upgrade_tree_window.bereits_bezahlt_ausbau_erscheint_erst_nach", "Bereits bezahlt. Der Ausbau erscheint erst nach Lieferung und Abholung in der Workbench.")
	elif not bool(state.get("available", false)):
		_action.text = Loc.t("ui.upgrade_tree_window.s", "🔒 %s") % str(state.get("locked_reason", Loc.t("ui.upgrade_tree_window.noch_gesperrt", "NOCH GESPERRT"))).to_upper()
		_action.disabled = true
		_purchase_hint.text = Loc.t("ui.upgrade_tree_window.diese_komponente_kann_momentan_weder_gekauft", "Diese Komponente kann momentan weder gekauft noch bestellt werden.")
	else:
		var order_only := bool(item.get("order_only", false))
		var shortfall := float(state.get("shortfall", 0.0))
		if shortfall > 0.005:
			_action.text = Loc.t("ui.upgrade_tree_window.noch_s_notig_preis_s", "NOCH %s NÖTIG · PREIS %s") % [
				Currency.format(shortfall), Currency.format(price)]
			_purchase_hint.text = Loc.t("ui.upgrade_tree_window.geldbeutel_s_es_fehlen_s_button", "Geldbeutel %s · es fehlen %s. Der Button nennt beim Klick denselben Grund.") % [
				Currency.format(PlayerStats.geld), Currency.format(shortfall)]
			_purchase_hint.modulate = Palette.LCD_AMBER
			_action.tooltip_text = Loc.t("ui.upgrade_tree_window.nicht_genug_bargeld_es_fehlen_s", "Nicht genug Bargeld: Es fehlen %s.") % Currency.format(shortfall)
		else:
			_action.text = Loc.t("ui.upgrade_tree_window.s_s", "%s · %s") % [
				Loc.t("ui.upgrade_tree_window.order", "VERBINDLICH BESTELLEN")
					if order_only
					else Loc.t("ui.upgrade_tree_window.buy_now", "DIREKT KAUFEN"),
				Currency.format(price)]
			_purchase_hint.text = Loc.t("ui.upgrade_tree_window.order_charged",
				"Der Betrag wird jetzt abgebucht; Einbau erst nach Lieferung und Abholung.") \
				if order_only else Loc.t("ui.upgrade_tree_window.purchase_charged",
					"Der Betrag wird jetzt abgebucht und die Komponente sofort angeschlossen.")
			_purchase_hint.modulate = Color.WHITE
			_action.tooltip_text = ""
		_action.disabled = false


func _make_preview(id: String, min_size: Vector2, vivid: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0a0d12"), Color("293441"), 1, 5))
	var path := str(PREVIEW_ASSETS.get(id, ""))
	if path == "":
		var state := HardwareManager.node_state(id)
		var item: Dictionary = state.get("item", {})
		path = str(item.get("preview_asset", ""))
	if path != "" and ResourceLoader.exists(path):
		var texture := TextureRect.new()
		texture.texture = load(path)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.modulate = Color.WHITE if vivid else Color(0.52, 0.55, 0.6, 0.48)
		panel.add_child(texture)
	else:
		var mark := Label.new()
		mark.text = Loc.t("ui.upgrade_tree_window.asset_nfehlt", "ASSET\nFEHLT")
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", 18 if min_size.x > 150 else 13)
		mark.add_theme_color_override("font_color", Color("d5b56a") if vivid else Color("59616d"))
		panel.add_child(mark)
	return panel


func _select_track(id: String) -> void:
	_selected_track = id
	var nodes := _track_nodes(id)
	if not nodes.is_empty():
		_selected_node = str((nodes[0] as Dictionary).get("id", ""))
	AudioManager.play("key_click", 0.0)
	_refresh()


func _select_node(id: String) -> void:
	_selected_node = id
	AudioManager.play("key_click", 0.0)
	_rebuild_cards()
	_refresh_detail()


func _buy_selected() -> void:
	var result := HardwareManager.buy(_selected_node)
	UIManager.toast(str(result.get("text", "")))
	AudioManager.play("cash_register" if bool(result.get("ok", false)) else "phone_busy", 0.0)
	_request_refresh()


## queue_free() ist auch waehrend einer Signalausgabe sicher. Das zusaetzliche
## remove_child() nimmt das alte Element sofort aus Grid/Layout und verhindert
## dadurch einen Frame mit ueberlappenden alten und neuen Karten.
func _clear_children_safely(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
		parent.remove_child(child)


func _track_nodes(id: String) -> Array:
	return HardwareManager.visible_nodes_in_track(id)


func _track_short(id: String, fallback: String) -> String:
	match id:
		"computer": return Loc.t("ui.upgrade_tree_window.track_computer", "RECHNER")
		"speicher": return Loc.t("ui.upgrade_tree_window.track_memory", "SPEICHER")
		"laufwerke": return Loc.t("ui.upgrade_tree_window.track_drives", "LAUFWERKE")
		"dfue": return Loc.t("ui.upgrade_tree_window.track_comms", "DFÜ")
		"ausgabe": return Loc.t("ui.upgrade_tree_window.track_output", "AUSGABE & BILD")
		_: return fallback


func _state_text(state: Dictionary) -> String:
	if bool(state.get("owned", false)):
		return Loc.t("ui.upgrade_tree_window.state_installed", "✓ EINGEBAUT") if bool(state.get("active", false)) \
			else Loc.t("ui.upgrade_tree_window.state_owned_not_installed", "- IM BESITZ · NICHT EINGEBAUT")
	if bool(state.get("pending", false)):
		return Loc.t("ui.upgrade_tree_window.state_ordered_days", "⧗ BESTELLT · %d TAGE") % int(state.get("days_left", 0))
	if bool(state.get("available", false)):
		if not bool(state.get("affordable", true)):
			return Loc.t("ui.upgrade_tree_window.state_orderable_missing", "● BESTELLBAR · FEHLT %s") % Currency.format(float(state.get("shortfall", 0.0)))
		return Loc.t("ui.upgrade_tree_window.state_ready", "● KAUFBEREIT")
	return Loc.t("ui.upgrade_tree_window.state_locked", "🔒 %s") % str(state.get("locked_reason", Loc.t("ui.upgrade_tree_window.gesperrt", "GESPERRT"))).to_upper()


func _state_color(state: Dictionary) -> Color:
	if bool(state.get("owned", false)):
		return Palette.LCD_GREEN
	if bool(state.get("pending", false)):
		return Palette.LCD_AMBER
	if bool(state.get("available", false)):
		return Color("6fc9ff") if bool(state.get("affordable", true)) else Palette.LCD_AMBER
	return Color("68717d")


func _panel_style(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _set_margins(margin: MarginContainer, horizontal: int, vertical: int) -> void:
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
