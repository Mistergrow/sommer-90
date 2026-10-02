class_name RetroMuseumArchiveWindow
extends RetroWindow
## Datengetriebenes Privatarchiv des begehbaren 1999-Museums.
##
## Keine erfundene Abschlussstatistik: Jahreskarten lesen MemoryManager,
## Hardware liest den echten Schreibtisch-/HDD-Zustand und Kultur liest die
## tatsächlich aufgebaute Sammlung. Dadurch bleibt das Museum auch im freien
## Spiel ein ehrlicher, aktualisierter Rückblick auf genau diesen Spielstand.

const C_AMBER := Color8(255, 179, 42)
const C_CYAN := Color8(75, 209, 224)
const C_GREEN := Color8(91, 235, 128)
const C_WHITE := Color8(232, 236, 228)
const C_DIM := Color8(132, 150, 160)

var initial_section := "years"
var _section := "years"
var _year := 1990
var _section_buttons: Dictionary = {}
var _year_buttons: Dictionary = {}
var _portrait: TextureRect
var _heading: Label
var _subheading: Label
var _body: RichTextLabel
var _facts: RichTextLabel
## Sprachunabhaengiger Vertrag fuer Tests, Accessibility und spaetere Exporte.
## Die sichtbaren Texte duerfen lokalisiert werden, die inhaltlichen Felder nicht.
var _fact_keys: Array[String] = []


func _init() -> void:
	title = Loc.t("ui.retro_museum_archive_window.privatarchiv_1990_1999", "PRIVATARCHIV · 1990–1999")
	win_size = Vector2(980, 620)


func _ready() -> void:
	super._ready()
	_section = initial_section if initial_section in ["years", "hardware", "culture"] else "years"
	_build_archive()
	_refresh()


func _build_archive() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(Bezel.lcd_label(Loc.t("ui.retro_museum_archive_window.dein_jahrzehnt_originaler_spielstand", "DEIN JAHRZEHNT · ORIGINALER SPIELSTAND"), C_AMBER, 15))
	identity.add_child(Bezel.dim_label(
		Loc.t("ui.retro_museum_archive_window.exhibits_from_save",
			"Jedes Exponat stammt aus deinem Besitz, deinen Erfolgen oder deinen Erinnerungen."), 10))
	header.add_child(identity)
	var live := Bezel.lcd_label(Loc.t("ui.retro_museum_archive_window.archiv_online", "ARCHIV ONLINE"), C_GREEN, 12)
	live.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(live)
	content.add_child(header)
	content.add_child(_rule(C_AMBER, 1))

	var tabs := HBoxContainer.new()
	tabs.name = "ArchiveSections"
	tabs.add_theme_constant_override("separation", 7)
	for section_id: String in ["years", "hardware", "culture"]:
		var label: String = {
			"years": "JAHRE & ERINNERUNGEN",
			"hardware": "HARDWARECHRONIK",
			"culture": "SZENE & SAMMLUNG",
		}[section_id]
		var button := make_button(label, func() -> void: _select_section(section_id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34
		_section_buttons[section_id] = button
		tabs.add_child(button)
	content.add_child(tabs)

	var timeline := HBoxContainer.new()
	timeline.name = "DecadeTimeline"
	timeline.add_theme_constant_override("separation", 3)
	for year in range(1990, 2000):
		var button := make_button(str(year), func() -> void: _select_year(year))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 30
		_year_buttons[year] = button
		timeline.add_child(button)
	content.add_child(timeline)

	var body_row := HBoxContainer.new()
	body_row.name = "ArchiveBody"
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_theme_constant_override("separation", 9)

	var exhibit := PanelContainer.new()
	exhibit.name = "ExhibitCard"
	exhibit.custom_minimum_size.x = 620
	exhibit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exhibit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	exhibit.add_theme_stylebox_override("panel", _panel_style(C_CYAN))
	var exhibit_col := VBoxContainer.new()
	exhibit_col.add_theme_constant_override("separation", 6)
	exhibit.add_child(exhibit_col)

	var exhibit_head := HBoxContainer.new()
	exhibit_head.add_theme_constant_override("separation", 12)
	_portrait = TextureRect.new()
	_portrait.name = "YearPortrait"
	_portrait.custom_minimum_size = Vector2(112, 112)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exhibit_head.add_child(_portrait)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	_heading = Bezel.lcd_label("", C_AMBER, 21)
	titles.add_child(_heading)
	_subheading = Bezel.dim_label("", 11)
	_subheading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subheading)
	exhibit_head.add_child(titles)
	exhibit_col.add_child(exhibit_head)
	exhibit_col.add_child(_rule(C_CYAN, 1))
	_body = RichTextLabel.new()
	_body.name = "ArchiveNarrative"
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 12)
	_body.add_theme_color_override("default_color", C_WHITE)
	exhibit_col.add_child(_body)
	body_row.add_child(exhibit)

	var ledger := PanelContainer.new()
	ledger.name = "ArchiveLedger"
	ledger.custom_minimum_size.x = 315
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ledger.add_theme_stylebox_override("panel", _panel_style(C_AMBER))
	var ledger_col := VBoxContainer.new()
	ledger_col.add_theme_constant_override("separation", 7)
	ledger.add_child(ledger_col)
	ledger_col.add_child(Bezel.lcd_label(Loc.t("ui.retro_museum_archive_window.archivkarte", "ARCHIVKARTE"), C_AMBER, 13))
	ledger_col.add_child(_rule(C_AMBER, 1))
	_facts = RichTextLabel.new()
	_facts.name = "ArchiveFacts"
	_facts.bbcode_enabled = true
	_facts.fit_content = false
	_facts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_facts.add_theme_font_size_override("normal_font_size", 11)
	_facts.add_theme_color_override("default_color", C_WHITE)
	ledger_col.add_child(_facts)
	var photos := make_button(Loc.t("ui.retro_museum_archive_window.fotoalbum_offnen", "FOTOALBUM ÖFFNEN"), UIManager.open_photos)
	photos.custom_minimum_size.y = 34
	ledger_col.add_child(photos)
	body_row.add_child(ledger)
	content.add_child(body_row)

	var footer := Bezel.dim_label(
		Loc.t("ui.retro_museum_archive_window.archive_grows_with_save",
			"1990–1999 · PRIVATARCHIV · DIE AUSSTELLUNG WÄCHST MIT DEINEM SPIELSTAND"), 9)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(footer)


func _select_section(section_id: String) -> void:
	_section = section_id
	_refresh()


func _select_year(year: int) -> void:
	_year = clampi(year, 1990, 1999)
	_section = "years"
	_refresh()


func _refresh() -> void:
	for section_id: String in _section_buttons:
		var button: Button = _section_buttons[section_id]
		button.disabled = section_id == _section
	for year: int in _year_buttons:
		var year_button: Button = _year_buttons[year]
		year_button.disabled = _section == "years" and year == _year
		year_button.modulate = Color.WHITE if year == _year else Color(0.78, 0.82, 0.86)
	match _section:
		"hardware":
			_show_hardware()
		"culture":
			_show_culture()
		_:
			_show_year()


func _show_year() -> void:
	var memories: Array = MemoryManager.memories_for_year(_year)
	_portrait.visible = true
	_portrait.texture = PlayerIdentity.texture({"year": _year})
	_heading.text = Loc.t("ui.retro_museum_archive_window.sommer_d", "SOMMER %d") % _year
	_subheading.text = Loc.t("ui.retro_museum_archive_window.d_festgehaltene_momente_alter_d", "%d festgehaltene Momente · Alter %d") % [
		memories.size(), PlayerIdentity.age_at_year_end(_year)]
	var rows: Array[String] = []
	if memories.is_empty():
		rows.append("[color=#8496a0]Für dieses Jahr wurde noch kein persönlicher Moment festgehalten.[/color]")
	else:
		for index in mini(memories.size(), 18):
			var memory: Dictionary = memories[index]
			var marker := "*" if str(memory.get("kind", "")) == "meilenstein" else "-"
			var memory_title := str(memory.get("title", memory.get("text", "Erinnerung")))
			var detail := str(memory.get("text", ""))
			if detail == memory_title:
				detail = ""
			rows.append("[color=#4bd1e0]%s %02d.%02d.[/color] [b]%s[/b]%s" % [
				marker, int(memory.get("day", 1)), int(memory.get("month", 1)),
				memory_title, ("\n    " + detail) if not detail.is_empty() else ""])
	_body.text = "\n\n".join(rows)
	var milestones := 0
	var kinds: Dictionary = {}
	for memory: Dictionary in memories:
		var kind := str(memory.get("kind", "moment"))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if kind == "meilenstein":
			milestones += 1
	_facts.text = _facts_markup([
		["JAHR", str(_year)],
		["ALTER", "%d Jahre" % PlayerIdentity.age_at_year_end(_year)],
		["MOMENTE", str(memories.size())],
		["MEILENSTEINE", str(milestones)],
		["KATEGORIEN", str(kinds.size())],
		["SPIELZEIT", "Sommer %d" % _year],
	])


func _show_hardware() -> void:
	_portrait.visible = false
	var computer := _device_name("computer_model")
	var monitor := _device_name("monitor_model")
	var printer := _device_name("printer_model")
	var hdd: Dictionary = PlayerStats.hdd_info()
	var expansions: Array[String] = PlayerStats.expansion_summary()
	_heading.text = Loc.t("ui.retro_museum_archive_window.deine_hardwarechronik", "DEINE HARDWARECHRONIK")
	_subheading.text = Loc.t("ui.retro_museum_archive_window.s_s_hardware_level_d", "%s · %s · Hardware-Level %d") % [
		computer, PlayerStats.chipset_description(), PlayerStats.hardware_level()]
	var lines: Array[String] = [
		"[color=#4bd1e0]AKTIVER RECHNER[/color]\n[b]%s[/b]" % computer,
		"[color=#4bd1e0]BILD & AUDIO[/color]\n%s\n%s" % [monitor, _device_name("stereo_model")],
		"[color=#4bd1e0]SPEICHER[/color]\n%s" % PlayerStats.ram_configuration_text(),
		"[color=#4bd1e0]MASSENSPEICHER[/color]\n%s" % (
			PlayerStats.active_hdd_description() if bool(hdd.get("available", false))
			else "Kein aktives Festplattenvolume"),
	]
	if not expansions.is_empty():
		lines.append("[color=#4bd1e0]EINGEBAUTE ERWEITERUNGEN[/color]\n• %s" %
			"\n• ".join(expansions))
	_body.text = "\n\n".join(lines)
	_facts.text = _facts_markup([
		["CPU", PlayerStats.cpu_description()],
		["TAKT", "%.1f MHz" % PlayerStats.cpu_clock_mhz()],
		["CHIPSATZ", PlayerStats.chipset_description()],
		["RAM", PlayerStats.ram_total_text()],
		["HDD", ("%.1f MB" % (float(hdd.get("capacity_kb", 0)) / 1024.0))
			if bool(hdd.get("available", false)) else "—"],
		["BOOTFÄHIG", "JA" if PlayerStats.hdd_bootable() else "NEIN"],
		["DRUCKER", printer],
	])


func _show_culture() -> void:
	_portrait.visible = false
	var visits: Dictionary = BBSManager.get("_visited") as Dictionary
	var boxed := DiskManager.boxed_collection().size()
	var achievements := AchievementManager.unlocked_count()
	_heading.text = Loc.t("ui.retro_museum_archive_window.szene_musik_sammlung", "SZENE · MUSIK · SAMMLUNG")
	_subheading.text = Loc.t("ui.retro_museum_archive_window.was_du_entdeckt_bewahrt_selbst_veroffentlicht", "Was du entdeckt, bewahrt und selbst veröffentlicht hast.")
	_body.text = "\n\n".join([
		"[color=#4bd1e0]DEINE ORIGINALBOXEN[/color]\n[b]%d vollständige Sätze[/b] · Archivwert %s" %
			[boxed, Currency.format(DiskManager.collection_value())],
		"[color=#4bd1e0]DEIN MOD-ARCHIV[/color]\n[b]%d Tracks[/b] am Hörplatz verfügbar" %
			MusicManager.owned.size(),
		"[color=#4bd1e0]DEINE SZENE-SPUR[/color]\n[b]%d eigene Releases[/b] · %d Mailboxen besucht" %
			[SceneReleaseManager.uploads.size(), visits.size()],
		"[color=#4bd1e0]DEINE ERINNERUNGEN[/color]\n[b]%d Momente[/b] · %d Fotos · %d/%d Trophäen" %
			[MemoryManager.memories.size(), PhotoManager.count(), achievements,
			AchievementManager.total()],
	])
	_facts.text = _facts_markup([
		["LOSE DISKS", str(DiskManager.media_count())],
		["OVP-SÄTZE", str(boxed)],
		["SAMMLERWERT", Currency.format(DiskManager.collection_value())],
		["MODS", str(MusicManager.owned.size())],
		["UPLOADS", str(SceneReleaseManager.uploads.size())],
		["MAILBOXEN", str(visits.size())],
		["TROPHÄEN", "%d/%d" % [achievements, AchievementManager.total()]],
		["FOTOS", str(PhotoManager.count())],
	])


func _device_name(selector: String) -> String:
	var model_id := RoomManager.active_device_model(selector)
	if model_id.is_empty():
		model_id = PlayerStats.desk_model(selector)
	return model_id.replace("amiga_", "Amiga ").replace("commodore_", "Commodore ") \
		.replace("dot_matrix_", "Nadeldrucker ").replace("inkjet_", "Tintenstrahler ") \
		.replace("_", " ").capitalize()


func _facts_markup(rows: Array) -> String:
	var result: Array[String] = []
	_fact_keys.clear()
	for raw_row: Variant in rows:
		var row := raw_row as Array
		_fact_keys.append(str(row[0]))
		result.append("[color=#8496a0]%s[/color]\n[color=#5beb80]%s[/color]" % [
			str(row[0]), str(row[1])])
	return "\n\n".join(result)


func _panel_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.032, 0.045, 0.98)
	style.border_color = Color(accent, 0.52)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(10)
	return style


func _rule(color: Color, height: int) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(color, 0.55)
	rule.custom_minimum_size.y = height
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
