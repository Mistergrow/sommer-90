class_name HomepagePreview
extends Control
## Live-Vorschau einer glaubwuerdigen privaten 1998/99-Heimseite. Die Seite
## bleibt handgebaut und zeittypisch, besitzt aber eine lesbare Hierarchie,
## echte Module und ein belastbares 800x600-Raster statt zufaelliger Gimmicks.

var cfg := {
	"title": "",
	"about": "",
	"bg": "stars", "accent": Color8(60, 210, 230), "layout": "classic",
	"features": {"construction": false},
	"modules": {"counter": true, "guestbook": true, "webring": true,
		"links": true, "news": false, "downloads": false},
	"visitors": 42, "guestbook": [], "year": 1998,
}

var _time := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _accent() -> Color:
	var value: Variant = cfg.get("accent", Color8(60, 210, 230))
	return value if value is Color else Color8(60, 210, 230)


func _modules() -> Dictionary:
	var value: Variant = cfg.get("modules", {})
	if value is Dictionary:
		return value
	var features: Variant = cfg.get("features", {})
	return features if features is Dictionary else {}


func _draw() -> void:
	if size.x < 80.0 or size.y < 80.0:
		return
	var accent := _accent()
	var year := int(cfg.get("year", 1998))
	var portal := str(cfg.get("layout", "classic")) == "portal"
	_draw_background(accent)

	# Kopf: eigenstaendiges Seitenlogo, Update-Datum und animierter Aktivitaets-
	# Streifen. Kein unlesbarer Endlos-Marquee ueber dem eigentlichen Inhalt.
	var header := Rect2(10, 10, size.x - 20, 72)
	_panel(header, Color(0.055, 0.018, 0.075, 0.94) if portal \
		else Color(0.015, 0.025, 0.065, 0.94), accent, 2.0)
	var page_title := str(cfg.get("title", "")).strip_edges()
	if page_title.is_empty():
		page_title = Loc.t("ui.homepage_preview.my_homepage", "MEINE HOMEPAGE")
	_text(page_title.to_upper(), Vector2(24, 41), 22,
		Color(1.0, 0.88, 0.36), header.size.x - 175)
	_text(Loc.t("ui.homepage_preview.private_homepage_year", "PRIVATE HOMEPAGE · %d") % year, Vector2(size.x - 190, 30), 10,
		Color(0.55, 0.76, 0.88), 160, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Loc.t("ui.homepage_preview.portal_subtitle", "NEWS · DOWNLOADS · SZENE · KONTAKT") if portal \
		else Loc.t("ui.homepage_preview.classic_subtitle", "AMIGA · DEMOS · MUSIK · FREUNDE"), Vector2(24, 64), 11,
		Color(0.7, 0.92, 1.0), header.size.x - 48)
	for i in 28:
		var wave := 2.0 + sin(_time * 2.4 + float(i) * 0.65) * 2.0
		draw_rect(Rect2(24 + i * 12, 73 - wave, 8, wave), accent.darkened(0.15), true)

	var nav := Rect2(10, 88, size.x - 20, 30)
	draw_rect(nav, Color(0.02, 0.06, 0.11, 0.96), true)
	var nav_items: Array[String] = [Loc.t("ui.homepage_preview.nav_start", "START"),
		Loc.t("ui.homepage_preview.nav_about", "UEBER MICH")]
	var modules := _modules()
	if bool(modules.get("news", false)): nav_items.append(Loc.t("ui.homepage_preview.nav_news", "NEWS"))
	if bool(modules.get("downloads", false)): nav_items.append(Loc.t("ui.homepage_preview.nav_downloads", "DOWNLOADS"))
	if bool(modules.get("guestbook", true)): nav_items.append(Loc.t("ui.homepage_preview.nav_guestbook", "GAESTEBUCH"))
	var nx := 20.0
	for item in nav_items:
		_text(item, Vector2(nx, 108), 10, accent)
		nx += ThemeDB.fallback_font.get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 22.0

	var body := Rect2(10, 124, size.x - 20, size.y - 158)
	_panel(body, Color(0.015, 0.025, 0.05, 0.92), Color(0.13, 0.26, 0.38), 1.0)
	var side_width := clampf(body.size.x * 0.26, 145.0, 190.0)
	var sidebar := Rect2(body.position + Vector2(8, 8), Vector2(side_width, body.size.y - 16))
	var main := Rect2(sidebar.end.x + 8, body.position.y + 8,
		body.end.x - sidebar.end.x - 16, body.size.y - 16)
	_draw_sidebar(sidebar, accent, year, modules)
	_draw_content(main, accent, year, modules)

	var footer_y := size.y - 26.0
	draw_rect(Rect2(10, footer_y - 7, size.x - 20, 1), accent.darkened(0.5), true)
	if bool(modules.get("webring", true)):
		_text(Loc.t("ui.homepage_preview.webring_nav", "<< ZURUECK · AMIGA WEBRING · ZUFALL · WEITER >>"), Vector2(20, footer_y + 7), 9,
			Color(0.55, 0.84, 1.0), size.x * 0.62)
	_text(Loc.t("ui.homepage_preview.optimized_for", "OPTIMIERT FUER 800x600 · 256 FARBEN"), Vector2(size.x - 300, footer_y + 7), 9,
		Color(0.45, 0.56, 0.66), 280, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_sidebar(rect: Rect2, accent: Color, year: int, modules: Dictionary) -> void:
	_panel(rect, Color(0.02, 0.055, 0.09, 0.96), accent.darkened(0.5), 1.0)
	var x := rect.position.x + 10
	var y := rect.position.y + 20
	_text(Loc.t("ui.homepage_preview.webmaster", "WEBMASTER"), Vector2(x, y), 11, accent, rect.size.x - 20)
	y += 14
	draw_rect(Rect2(x, y, rect.size.x - 20, 44), Color(0.04, 0.12, 0.16), true)
	# Zeittypischer kleiner Avatar-Platzhalter als bewusstes Seitenlogo, kein
	# fehlendes Foto-Asset: Kopf, Shirt und Pixelrahmen werden sauber gerastert.
	draw_rect(Rect2(x + 8, y + 7, 28, 28), Color8(213, 167, 120), true)
	draw_rect(Rect2(x + 6, y + 31, 32, 8), accent.darkened(0.45), true)
	_text(PlayerIdentity.player_name.to_upper(), Vector2(x + 44, y + 19), 10,
		Color(0.9, 0.94, 1.0), rect.size.x - 64)
	_text(Loc.t("ui.homepage_preview.online_since_1998", "ONLINE SEIT 1998"), Vector2(x + 44, y + 34), 8,
		Color(0.5, 0.72, 0.82), rect.size.x - 64)
	y += 58
	_text(Loc.t("ui.homepage_preview.last_update", "LETZTES UPDATE"), Vector2(x, y), 9, Color(0.55, 0.72, 0.82))
	y += 15
	_text(Loc.t("ui.homepage_preview.summer_year", "SOMMER %d") % year, Vector2(x, y), 11, Color(1.0, 0.78, 0.26))
	y += 25
	if bool(modules.get("counter", true)):
		_text(Loc.t("ui.homepage_preview.visitors", "BESUCHER"), Vector2(x, y), 9, Color(0.55, 0.72, 0.82))
		y += 8
		var digits := "%06d" % int(cfg.get("visitors", 0))
		var digit_width := (rect.size.x - 20) / 6.0
		for i in digits.length():
			var box := Rect2(x + i * digit_width, y, digit_width - 2, 22)
			draw_rect(box, Color(0.002, 0.01, 0.01), true)
			draw_rect(box, Color(0.15, 0.58, 0.32), false, 1)
			_text(digits[i], Vector2(box.position.x, box.position.y + 16), 12,
				Color(0.3, 1.0, 0.56), box.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		y += 36
	if bool(modules.get("links", true)):
		_text(Loc.t("ui.homepage_preview.my_links", "MEINE LINKS"), Vector2(x, y), 10, accent)
		y += 17
		for link in [Loc.t("ui.homepage_preview.link_computer_club", "Computerclub"),
			Loc.t("ui.homepage_preview.link_demo_scene", "Demo-Szene"),
			Loc.t("ui.homepage_preview.link_mod_archive", "MOD-Archiv"),
			Loc.t("ui.homepage_preview.link_friends", "Freunde")]:
			_text("+ " + link, Vector2(x, y), 9, Color(0.62, 0.82, 1.0), rect.size.x - 20)
			y += 14


func _draw_content(rect: Rect2, accent: Color, year: int, modules: Dictionary) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var width := rect.size.x
	_section_title(Loc.t("ui.homepage_preview.welcome", "WILLKOMMEN"), Rect2(x, y, width, 25), accent)
	y += 35
	var about_text := str(cfg.get("about", "")).strip_edges()
	if about_text.is_empty():
		about_text = Loc.t("ui.homepage_preview.default_about", "Willkommen auf meiner privaten Amiga-Seite. Hier sammle ich Releases, Links und Neuigkeiten aus der Szene.")
	for line in _wrap(about_text, 11, width - 16):
		_text(line, Vector2(x + 8, y), 11, Color(0.9, 0.94, 1.0), width - 16)
		y += 15
	y += 8

	if bool(modules.get("news", false)):
		_section_title(Loc.t("ui.homepage_preview.news_summer_year", "NEWS · SOMMER %d") % year, Rect2(x, y, width, 23), accent)
		y += 31
		for item in [Loc.t("ui.homepage_preview.news_site_online", "17.07. Neue Seite endlich online."),
			Loc.t("ui.homepage_preview.news_mod_recommendations", "12.07. Frische MOD-Empfehlungen im Archiv.")]:
			_text(Loc.t("ui.homepage_preview.new_prefix", "[NEU] ") + item, Vector2(x + 8, y), 9, Color(0.78, 0.9, 1.0), width - 16)
			y += 14
		y += 5

	if bool(modules.get("downloads", false)):
		_section_title(Loc.t("ui.homepage_preview.download_archive", "DOWNLOAD-ARCHIV"), Rect2(x, y, width, 23), accent)
		y += 31
		for entry in [["SCENE-PACK.LHA", "412 KB", "VERIFIED"],
			["MEINE-LINKS.TXT", "7 KB", "TEXT"]]:
			draw_rect(Rect2(x + 6, y - 11, width - 12, 18), Color(0.025, 0.075, 0.11), true)
			_text(str(entry[0]), Vector2(x + 12, y + 2), 9, Color(0.66, 0.9, 1.0), width - 165)
			_text("%s · %s" % [entry[1], entry[2]], Vector2(x + width - 160, y + 2), 8,
				Color(0.45, 0.82, 0.55), 145, HORIZONTAL_ALIGNMENT_RIGHT)
			y += 22
		y += 4

	if bool(modules.get("guestbook", true)) and y < rect.end.y - 44:
		_section_title(Loc.t("ui.homepage_preview.guestbook_latest", "GAESTEBUCH · LETZTE EINTRAEGE"), Rect2(x, y, width, 23), accent)
		y += 31
		var guestbook: Array = cfg.get("guestbook", [])
		if guestbook.is_empty():
			_text(Loc.t("ui.homepage_preview.no_guestbook_entry", "Noch kein Eintrag. Schreib mir!"), Vector2(x + 8, y), 10,
				Color(0.58, 0.67, 0.75), width - 16)
		else:
			for index in mini(3, guestbook.size()):
				var entry: Dictionary = guestbook[guestbook.size() - 1 - index]
				var line := "%s: %s" % [HomepageManager.guest_name(entry), HomepageManager.guest_line(entry)]
				_text(line, Vector2(x + 8, y), 9, Color(0.76, 0.87, 0.93), width - 16)
				y += 14

	var features: Variant = cfg.get("features", {})
	if features is Dictionary and bool((features as Dictionary).get("construction", false)):
		var cy := minf(rect.end.y - 24, y + 12)
		for stripe in int(width / 16.0):
			draw_rect(Rect2(x + stripe * 16, cy, 8, 18), Color(1.0, 0.75, 0.12), true)
			draw_rect(Rect2(x + stripe * 16 + 8, cy, 8, 18), Color(0.06, 0.06, 0.06), true)
		_text(Loc.t("ui.homepage_preview.under_construction", "UNDER CONSTRUCTION"), Vector2(x, cy + 14), 9, Color.WHITE, width,
		HORIZONTAL_ALIGNMENT_CENTER)


func _section_title(label: String, rect: Rect2, accent: Color) -> void:
	draw_rect(rect, Color(0.025, 0.09, 0.14), true)
	draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), accent, true)
	_text(label, rect.position + Vector2(12, 17), 10, Color(0.95, 0.86, 0.38), rect.size.x - 18)


func _panel(rect: Rect2, fill: Color, border: Color, width: float) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, width)


func _draw_background(accent: Color) -> void:
	match str(cfg.get("bg", "stars")):
		"bricks":
			draw_rect(Rect2(Vector2.ZERO, size), Color8(18, 22, 34), true)
			for row in int(size.y / 18.0) + 1:
				var offset := 18.0 if row % 2 else 0.0
				for col in int(size.x / 36.0) + 2:
					draw_rect(Rect2(col * 36.0 - offset, row * 18.0, 34, 16),
						Color(0.07, 0.11, 0.16), false, 1)
		"gradient":
			for step in 24:
				var ratio := float(step) / 23.0
				draw_rect(Rect2(0, ratio * size.y, size.x, size.y / 23.0 + 1),
					Color(0.015, 0.025, 0.07).lerp(accent.darkened(0.82), ratio), true)
		_:
			draw_rect(Rect2(Vector2.ZERO, size), Color8(4, 7, 22), true)
			var rng := RandomNumberGenerator.new()
			rng.seed = 1998
			for _index in 90:
				var point := Vector2(rng.randf() * size.x, rng.randf() * size.y)
				var alpha := 0.25 + rng.randf() * 0.5
				draw_rect(Rect2(point, Vector2(1 + rng.randi() % 2, 1 + rng.randi() % 2)),
					Color(0.65, 0.8, 1.0, alpha), true)


func _text(value: String, position: Vector2, font_size: int, color: Color,
		width := -1.0, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(ThemeDB.fallback_font, position, value, alignment, width, font_size, color)


func _wrap(value: String, font_size: int, width: float) -> Array[String]:
	var result: Array[String] = []
	var line := ""
	for word in value.replace("\n", " ").split(" "):
		var probe := (line + " " + word).strip_edges()
		if not line.is_empty() and ThemeDB.fallback_font.get_string_size(
				probe, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			result.append(line)
			line = word
		else:
			line = probe
	if not line.is_empty():
		result.append(line)
	return result
