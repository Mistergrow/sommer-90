extends RetroWindow
## Zeitachsenfeste Heftansicht. Das alte Fenster war dauerhaft auf den kompletten
## Jahrgang 1990 verdrahtet und zeigte damit 1991–1999 sowohl falsche Cover als
## auch mehr Ausgaben, als der Spieler physisch besass. Jetzt entstehen nur die
## bis heute erschienenen, wirklich vorhandenen Hefte; Ausgabe/Jahr sind echter
## UI-Text und koennen deshalb nie in einer alten Rastergrafik stecken bleiben.

const MagazineComposerScript := preload("res://scripts/gfx/magazine_composer.gd")
const MagazinePrograms := preload("res://scripts/data/magazine_program_catalog.gd")
const ProductionMagazines := preload("res://scripts/data/magazine_production_catalog.gd")
const PAGE_IDS := ["cover", "scene", "tech", "listing", "classifieds"]

var _issues: Array[Dictionary] = []
var _view := "rack"
var _cur := 0
var _page := 0
var _page_host: Control
var _caption: Label
var _year := 1990


func _init() -> void:
	title = Loc.t("ui.magazine_window.amiga_spass_aktueller_jahrgang", "AMIGA SPASS · AKTUELLER JAHRGANG")
	win_size = Vector2(780, 700)


func _ready() -> void:
	_year = int(TimeManager.year)
	var production_issue := ProductionMagazines.for_date(_year, clampi(int(TimeManager.month), 1, 12))
	if production_issue.is_empty():
		title = Loc.t("ui.magazine_window.amiga_spass_jahrgang_d", "AMIGA SPASS · JAHRGANG %d") % _year
	else:
		var localized_title := str(production_issue.get("title_en", "")) \
			if TranslationServer.get_locale().begins_with("en") \
			else str(production_issue.get("title_de", ""))
		var issue_suffix := " %02d/%d" % [int(production_issue.get("month", 0)), _year]
		var publication_title := localized_title.trim_suffix(issue_suffix)
		title = "%s · %d" % [publication_title.to_upper(), _year]
	super._ready()
	AudioManager.play("page_turn")
	_build_owned_issues()
	_rebuild()


## Das bisherige Inventar speichert Hefte als physische Anzahl, noch nicht als
## einzelne UID. Darum rekonstruieren wir deterministisch die letzten N bis zum
## aktuellen Monat erschienenen Ausgaben. So gibt es weder Zukunftshefte noch
## den alten Cheat „drei Magazine besitzen, zwölf lesen“.
func _build_owned_issues() -> void:
	_issues.clear()
	var published_month := clampi(int(TimeManager.month), 1, 12)
	var owned := clampi(InventoryManager.count("magazine"), 0, published_month)
	var first_month := published_month - owned + 1
	for issue_month in range(first_month, published_month + 1):
		var production_issue := ProductionMagazines.for_date(_year, issue_month)
		var issue_id := str(production_issue.get("issue_id", ""))
		var art_path := ProductionMagazines.asset_path(production_issue, "cover_front")
		if art_path.is_empty():
			art_path = MagazineComposerScript.cover_for_date(_year, issue_month)
		var program := MagazinePrograms.by_issue(issue_id) if not issue_id.is_empty() \
			else MagazinePrograms.for_year(_year)
		var has_program := not program.is_empty() and int(program.get("month", 0)) == issue_month
		_issues.append({
			"year": _year,
			"month": issue_month,
			"issue": "%02d/%02d" % [issue_month, _year % 100],
			"art": load(art_path) as Texture2D if ResourceLoader.exists(art_path) else null,
			"headline": _headline_for(_year, issue_month),
			"issue_id": issue_id if not issue_id.is_empty() else \
				str(program.get("issue_id", "")) if has_program else "",
			"listing_id": str(program.get("listing_id", "")) if has_program else "",
			"production_issue": production_issue,
			"production_art": not production_issue.is_empty(),
		})


func _headline_for(issue_year: int, issue_month: int) -> String:
	var year_data: Dictionary = TimelineManager.year_data(issue_year)
	var news: Array = year_data.get("news", [])
	if not news.is_empty():
		var news_index := posmod(issue_month - 1, news.size())
		var source := str(news[news_index])
		return Loc.t("tl.%d.news.%d" % [issue_year, news_index], source).trim_suffix(".")
	return Loc.t("ui.magazine_window.games_scene_tech", "SPIELE · SZENE · TECHNIK")


func _rebuild() -> void:
	for child: Node in content.get_children():
		child.queue_free()
	if _view == "rack":
		_build_rack()
	else:
		_build_reader()


func _build_rack() -> void:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	content.add_child(head)
	var title_label := Bezel.lcd_label(Loc.t("ui.magazine_window.deine_hefte_stand_02d_d", "DEINE HEFTE · STAND %02d/%d") % [
		TimeManager.month, _year], Palette.LCD_AMBER, 13)
	head.add_child(title_label)
	var explanation := Bezel.dim_label(
		Loc.t("ui.magazine_window.nur_bereits_erschienene_physisch_vorhandene_ausgaben", "Nur bereits erschienene und physisch vorhandene Ausgaben. Titel anklicken zum Lesen."), 10)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(explanation)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for i in _issues.size():
		grid.add_child(_rack_item(i))


func _rack_item(index: int) -> Control:
	var issue: Dictionary = _issues[index]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var button := Button.new()
	button.custom_minimum_size = Vector2(166, 222)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = Loc.t("ui.magazine_window.ausgabe_s_lesen", "Ausgabe %s lesen") % str(issue["issue"])
	button.pressed.connect(_open_reader.bind(index))
	box.add_child(button)
	var cover := MagazineCover.new()
	cover.configure(issue)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(cover)
	var label := Bezel.lcd_label(Loc.t("ui.magazine_window.ausgabe_s", "AUSGABE %s") % str(issue["issue"]), Palette.LCD_AMBER, 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


func _build_reader() -> void:
	_page_host = PanelContainer.new()
	_page_host.name = "MagazinePageHost"
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.custom_minimum_size = Vector2(0, 535)
	content.add_child(_page_host)

	_caption = Bezel.lcd_label("", Palette.LCD_AMBER, 11)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_caption)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 8)
	nav.add_child(make_button(Loc.t("ui.magazine_window.hefte", "◄ HEFTE"), _back_to_rack))
	nav.add_child(make_button(Loc.t("ui.magazine_window.zurueck", "◄ ZURUECK"), _prev_page))
	nav.add_child(make_button(Loc.t("ui.magazine_window.blaettern", "BLAETTERN ►"), _next_page))
	var issue: Dictionary = _issues[_cur]
	var listing_id := str(issue.get("listing_id", ""))
	var listing := make_button(Loc.t("ui.magazine_window.listing_abtippen", "⌨ LISTING ABTIPPEN"),
		_open_listing.bind(listing_id))
	listing.disabled = listing_id.is_empty()
	listing.tooltip_text = Loc.t("ui.magazine_window.listing_dieser_ausgabe_an_werkbank_abtippen", "Das Listing dieser Ausgabe an der Werkbank abtippen.") \
		if not listing_id.is_empty() else Loc.t("ui.magazine_window.kein_jahreslisting", "Diese Ausgabe enthaelt kein Jahreslisting.")
	nav.add_child(listing)
	content.add_child(nav)
	_show_page()


func _show_page() -> void:
	if _cur < 0 or _cur >= _issues.size() or _page_host == null:
		return
	for child: Node in _page_host.get_children():
		child.queue_free()
	var issue: Dictionary = _issues[_cur]
	var production_page := _production_page(issue, _page)
	if production_page != null:
		_page_host.add_child(production_page)
	elif _page == 0:
		var cover := MagazineCover.new()
		cover.configure(issue)
		cover.custom_minimum_size = Vector2(400, 520)
		cover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_page_host.add_child(cover)
	else:
		_page_host.add_child(_article_page(issue, _page))
	_caption.text = Loc.t("ui.magazine_window.ausgabe_s_s_seite_d_d", "AUSGABE %s · %s · SEITE %d/%d") % [
		issue["issue"], _page_name(_page).to_upper(), _page + 1, PAGE_IDS.size()]
	AudioManager.play("page_turn")


func _production_page(issue: Dictionary, page_index: int) -> Control:
	var production_issue: Variant = issue.get("production_issue", {})
	if not production_issue is Dictionary or (production_issue as Dictionary).is_empty():
		return null
	var asset_id := ProductionMagazines.page_asset_id(page_index)
	var path := ProductionMagazines.asset_path(production_issue as Dictionary, asset_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color8(7, 10, 14)
	frame_style.border_color = Color8(76, 91, 104)
	frame_style.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", frame_style)
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(image)
	return frame


func _article_page(issue: Dictionary, page: int) -> Control:
	var panel := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color8(225, 217, 185)
	paper.border_color = Color8(32, 44, 47)
	paper.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", paper)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var article_material := _article_material(int(issue["year"]), int(issue["month"]), page)
	var section := Label.new()
	section.text = str(article_material["section"])
	section.add_theme_font_size_override("font_size", 15)
	section.add_theme_color_override("font_color", Color8(145, 36, 27))
	column.add_child(section)
	var heading := Label.new()
	heading.text = str(article_material["title"])
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 25)
	heading.add_theme_color_override("font_color", Color8(20, 31, 40))
	column.add_child(heading)
	var rule := HSeparator.new()
	column.add_child(rule)
	var body := Label.new()
	body.text = str(article_material["body"])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color8(35, 40, 38))
	body.add_theme_constant_override("line_spacing", 7)
	column.add_child(body)
	var footer := Label.new()
	footer.text = Loc.t("ui.magazine_window.amiga_spass_s_seite_d", "AMIGA SPASS · %s · SEITE %d") % [issue["issue"], page + 1]
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color8(91, 86, 71))
	column.add_child(footer)
	return panel


func _article_material(issue_year: int, issue_month: int, page: int) -> Dictionary:
	var era: Dictionary = TimelineManager.year_data(issue_year)
	var news: Array = era.get("news", [])
	var themes: Array = era.get("themes", [])
	var news_index := posmod(issue_month + page - 2, news.size()) if not news.is_empty() else -1
	var news_line := Loc.t("tl.%d.news.%d" % [issue_year, news_index], str(news[news_index])) \
		if news_index >= 0 else Loc.t("ui.magazine_window.scene_keeps_moving", "Die Heimcomputer-Szene bleibt in Bewegung.")
	var theme_line := ", ".join(themes.map(func(value: Variant) -> String:
		return _theme_name(str(value))))
	match page:
		1:
			return {"section": Loc.t("ui.magazine_window.section_scene_people", "SZENE & LEUTE"), "title": news_line,
				"body": Loc.t("ui.magazine_window.article_scene_body", "Unser Monatsreport sammelt Stimmen aus Laeden, Clubs und vom Schulhof. %s\n\nEntscheidend ist nicht nur, was neu erscheint: Wer tauscht fair? Welche Gruppe sucht Hilfe? Und welche Diskette sollte vor dem ersten Start besser geprueft werden?") % news_line}
		2:
			return {"section": Loc.t("ui.magazine_window.section_tech_workshop", "TECHNIK-WERKSTATT"),
				"title": Loc.t("ui.magazine_window.what_upgrades_really_do", "Was der Ausbau wirklich bringt"),
				"body": Loc.t("ui.magazine_window.article_tech_body", "Schwerpunkte dieses Jahrgangs: %s.\n\nWir trennen Werbung von messbarer Wirkung: Speicher, Laufwerke und Bildausgabe werden mit echten Arbeitsablaeufen getestet. Vor jedem Kauf gilt: Anschluss, Baujahr, Lieferzeit und vorhandene Software pruefen.") % theme_line}
		3:
			var program := MagazinePrograms.for_year(issue_year)
			if not program.is_empty() and int(program.get("month", 0)) == issue_month:
				var program_title := str(program.get("title_en", "")) if TranslationServer.get_locale().begins_with("en") \
					else str(program.get("title_de", ""))
				return {"section": Loc.t("ui.magazine_window.section_listing_corner", "LISTING-ECKE"),
					"title": Loc.t("ui.magazine_window.sommer_basic_jahresprogramm", "Sommer-BASIC-Jahresprogramm: %s") % program_title,
					"body": Loc.t("ui.magazine_window.article_annual_listing_body", "Dieses vollstaendige Programm ist fuer die Hardware dieses Jahrgangs getestet. Tippe den kanonischen Quelltext ab; danach prueft ihn der echte Sommer-BASIC-Compiler und uebergibt ihn als editierbares Projekt an die IDE. Lange Druckzeilen werden nur optisch umbrochen — der Quelltext bleibt unveraendert.")}
			return {"section": Loc.t("ui.magazine_window.section_listing_corner", "LISTING-ECKE"),
				"title": Loc.t("ui.magazine_window.listing_to_tool", "Vom gedruckten Listing zum eigenen Werkzeug"),
				"body": Loc.t("ui.magazine_window.article_listing_body", "Tippe nie blind los. Lies zuerst die Variablen, markiere Datenzeilen und sichere nach jedem lauffaehigen Abschnitt.\n\nDie Taste LISTING ABTIPPEN unter dem Heft startet die echte Werkbank-Uebung. Erst ein fehlerfrei gespeichertes Ergebnis zaehlt — diese Seite schenkt keine Software her.")}
		_:
			return {"section": Loc.t("ui.magazine_window.section_classifieds_preview", "KLEINANZEIGEN & VORSCHAU"),
				"title": Loc.t("ui.magazine_window.trade_search_reunite", "Tauschen, suchen, wiedersehen"),
				"body": Loc.t("ui.magazine_window.article_classifieds_body", "SUCHE: gut erhaltene DD-Disketten, sauber beschriftet.\n\nTAUSCHE: eigene Grafik gegen Hilfe bei einem Tracker-Pattern.\n\nCLUBTERMINE: Nur der aktuelle Aushang am schwarzen Brett ist verbindlich.\n\nNaechste Ausgabe erscheint im kommenden Monat — nicht vorher im Regal.")}


func _open_reader(index: int) -> void:
	_cur = index
	_page = 0
	_view = "reader"
	_rebuild()


func _open_listing(selected_listing_id: String) -> void:
	if selected_listing_id.is_empty():
		return
	UIManager.open_listing_type(selected_listing_id)


func _back_to_rack() -> void:
	_view = "rack"
	_rebuild()


func _prev_page() -> void:
	_page = wrapi(_page - 1, 0, PAGE_IDS.size())
	_show_page()


func _next_page() -> void:
	_page = wrapi(_page + 1, 0, PAGE_IDS.size())
	_show_page()


func _page_name(index: int) -> String:
	match PAGE_IDS[index] if index >= 0 and index < PAGE_IDS.size() else "":
		"cover": return Loc.t("ui.magazine_window.page_cover", "Titelseite")
		"scene": return Loc.t("ui.magazine_window.page_scene", "Szene-Bericht")
		"tech": return Loc.t("ui.magazine_window.page_tech", "Technik")
		"listing": return Loc.t("ui.magazine_window.page_listing", "Listing-Ecke")
		"classifieds": return Loc.t("ui.magazine_window.page_classifieds", "Kleinanzeigen")
	return ""


func _theme_name(theme_id: String) -> String:
	match theme_id:
		"3d_hype": return Loc.t("ui.magazine_window.theme_3d_hype", "3D-Hype")
		"amiga_frage": return Loc.t("ui.magazine_window.theme_amiga_question", "Amiga-Frage")
		"amiga_gold": return Loc.t("ui.magazine_window.theme_amiga_gold", "Amiga-Goldzeit")
		"archiv": return Loc.t("ui.magazine_window.theme_archive", "Archiv")
		"bbs_ende": return Loc.t("ui.magazine_window.theme_bbs_end", "BBS-Abschied")
		"boersen": return Loc.t("ui.magazine_window.theme_markets", "Boersen")
		"cd_brenner": return Loc.t("ui.magazine_window.theme_cd_burners", "CD-Brenner")
		"cdrom_fruh": return Loc.t("ui.magazine_window.theme_early_cdrom", "fruehe CD-ROMs")
		"clubs_klein": return Loc.t("ui.magazine_window.theme_small_clubs", "kleine Clubs")
		"clubs_zentral": return Loc.t("ui.magazine_window.theme_central_clubs", "zentrale Clubs")
		"demoscene": return Loc.t("ui.magazine_window.theme_demoscene", "Demoszene")
		"demoscene_fruh": return Loc.t("ui.magazine_window.theme_early_demoscene", "fruehe Demoszene")
		"disketten": return Loc.t("ui.magazine_window.theme_floppies", "Disketten")
		"festplatten": return Loc.t("ui.magazine_window.theme_hard_drives", "Festplatten")
		"heimcomputer": return Loc.t("ui.magazine_window.theme_home_computers", "Heimcomputer")
		"internet": return Loc.t("ui.magazine_window.theme_internet", "Internet")
		"internet_geruecht": return Loc.t("ui.magazine_window.theme_internet_rumor", "Internet-Geruechte")
		"internetcafe": return Loc.t("ui.magazine_window.theme_internet_cafe", "Internetcafes")
		"lan_gross": return Loc.t("ui.magazine_window.theme_large_lan", "grosse LANs")
		"lan_partys": return Loc.t("ui.magazine_window.theme_lan_parties", "LAN-Partys")
		"magazine": return Loc.t("ui.magazine_window.theme_magazines", "Magazine")
		"modem_boom": return Loc.t("ui.magazine_window.theme_modem_boom", "Modem-Boom")
		"mp3": return Loc.t("ui.magazine_window.theme_mp3", "MP3")
		"multimedia": return Loc.t("ui.magazine_window.theme_multimedia", "Multimedia")
		"pc_aufstieg": return Loc.t("ui.magazine_window.theme_pc_rise", "PC-Aufstieg")
		"pc_boom": return Loc.t("ui.magazine_window.theme_pc_boom", "PC-Boom")
		"retro_gefuehl": return Loc.t("ui.magazine_window.theme_retro_feeling", "Retro-Gefuehl")
		"rueckblick": return Loc.t("ui.magazine_window.theme_retrospective", "Rueckblick")
		"soundkarten": return Loc.t("ui.magazine_window.theme_sound_cards", "Soundkarten")
		"win95": return Loc.t("ui.magazine_window.theme_win95", "Windows 95")
	return theme_id.replace("_", " ").capitalize()


func _unhandled_key_input(event: InputEvent) -> void:
	if _view != "reader" or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_LEFT:
		_prev_page(); accept_event()
	elif event.keycode == KEY_RIGHT:
		_next_page(); accept_event()
	elif event.keycode == KEY_ESCAPE:
		_back_to_rack(); accept_event()


class MagazineCover:
	extends Control
	var issue: Dictionary = {}
	var art: Texture2D

	func configure(next_issue: Dictionary) -> void:
		issue = next_issue.duplicate()
		art = issue.get("art") as Texture2D
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		queue_redraw()

	func _draw() -> void:
		if issue.is_empty():
			return
		var ratio := 0.75
		var height := minf(size.y, size.x / ratio)
		var width := height * ratio
		var rect := Rect2(Vector2((size.x - width) * 0.5, (size.y - height) * 0.5), Vector2(width, height))
		draw_rect(rect.grow(4), Color8(6, 9, 13))
		if art != null:
			draw_texture_rect(art, rect, false)
		else:
			draw_rect(rect, Color8(24, 37, 48))
		if bool(issue.get("production_art", false)):
			return
		var mast_height := rect.size.y * 0.22
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, mast_height)), Color(0.02, 0.025, 0.04, 0.94))
		draw_rect(Rect2(rect.position + Vector2(0, mast_height), Vector2(rect.size.x, 3)), Color8(255, 159, 23))
		var font := ThemeDB.fallback_font
		var mast_size := clampi(roundi(rect.size.x * 0.105), 12, 31)
		draw_string(font, rect.position + Vector2(8, mast_height * 0.47), Loc.t("ui.magazine_window.amiga_spass", "AMIGA SPASS"),
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, mast_size, Color8(255, 235, 74))
		var issue_text := Loc.t("ui.magazine_window.ausgabe_s", "AUSGABE %s") % str(issue.get("issue", ""))
		draw_string(font, rect.position + Vector2(8, mast_height * 0.84), issue_text,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, maxi(9, roundi(mast_size * 0.48)), Color8(109, 235, 244))
		var footer_h := maxf(26.0, rect.size.y * 0.16)
		var footer := Rect2(Vector2(rect.position.x, rect.end.y - footer_h), Vector2(rect.size.x, footer_h))
		draw_rect(footer, Color(0.03, 0.035, 0.05, 0.94))
		var headline_lines := _headline_lines(
			str(issue.get("headline", Loc.t("ui.magazine_window.games_scene_tech", "SPIELE · SZENE · TECHNIK"))).to_upper(), 23)
		var headline_size := maxi(8, roundi(mast_size * 0.37))
		var first_y := footer.position.y + footer.size.y * (0.43 if headline_lines.size() > 1 else 0.62)
		for line_index in headline_lines.size():
			draw_string(font, Vector2(footer.position.x + 7, first_y + line_index * headline_size * 1.08),
				headline_lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, footer.size.x - 14,
				headline_size, Color.WHITE)

	func _headline_lines(text: String, max_chars: int) -> Array[String]:
		var lines: Array[String] = [""]
		for word: String in text.split(" ", false):
			var candidate := word if lines[-1].is_empty() else lines[-1] + " " + word
			if candidate.length() <= max_chars:
				lines[-1] = candidate
			elif lines.size() == 1:
				lines.append(word)
			else:
				lines[-1] = (lines[-1] + " " + word).left(max_chars - 3) + "..."
				break
		if lines.size() > 2:
			lines.resize(2)
		return lines
