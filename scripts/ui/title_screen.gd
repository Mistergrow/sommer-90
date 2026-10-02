class_name TitleScreen
extends Control
## Hauptmenü (AAA): Artwork-Hintergrund (Menü-Slot, Fallback: Master-Raum,
## abgedunkelt), animierte FX-Ebene (treibende Daten-Partikel + Scanline-Sweep),
## Logo-Block mit Diskette und Neonrahmen, sowie die Menü-Buttons inkl. Optionen.
## Versteckt sich bei game_started und kommt über returned_to_title zurück.

const MENU_ART_PATTERNS := [
	"res://assets/ui/MENU_TITLE_V%02d.png",
]
const CreditsScreen := preload("res://scripts/ui/credits_screen.gd")
const ScenePresentation := preload("res://scripts/ui/scene_presentation_screen.gd")
const BuildChannel := preload("res://scripts/core/build_channel.gd")

var _load_button: Button
var _new_game_button: Button
var _options_button: Button
var _help_button: Button
var _credits_button: Button
var _quit_button: Button
var _rule: ColorRect
var _disk: TextureRect
var _logo: Label
var _subtitle: Label
var _footer: Label
var _main_menu: Control
var _active_page: Control
var _scanlines: Control
var _startup_intro: Control
var _fx_time := 0.0


func _ready() -> void:
	clip_contents = true
	_sync_size.call_deferred()
	var parent_control := get_parent_control()
	if parent_control != null:
		parent_control.resized.connect(_sync_size)

	# --- Hintergrund: Menü-Artwork oder Master-Raum, abgedunkelt ---
	var art_path := _find_menu_art()
	if art_path != "":
		var art := TextureRect.new()
		art.texture = RoomCompositor.load_texture(art_path)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.modulate = Color(0.5, 0.49, 0.52)  # tiefer gedimmt für den Kino-Look
		add_child(art)
	else:
		var background := ColorRect.new()
		background.color = Palette.UI_BG
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(background)

	# Vignette
	var vignette := TextureRect.new()
	vignette.texture = _vignette_texture()
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	# Animierte FX-Ebene (Partikel + Scanline-Sweep)
	var fx := _MenuFX.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fx)

	# --- Menüblock ---
	_main_menu = CenterContainer.new()
	_main_menu.name = "MainMenuPage"
	_main_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_main_menu)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.07, 0.82)
	style.border_color = Color(Palette.LCD_AMBER, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(26)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	_main_menu.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Diskette-Emblem über dem Logo
	_disk = TextureRect.new()
	_disk.texture = Sprites.disk_icon(Palette.BLUE_MID)
	_disk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_disk.custom_minimum_size = Vector2(0, 46)
	_disk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_disk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_disk)

	# Logo (weiß mit dunkler Kontur) + Neon-Trennlinie
	_logo = Label.new()
	_logo.text = Loc.t("ui.title_screen.sommer_90", "SOMMER '90")
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.add_theme_font_size_override("font_size", 38)
	_logo.add_theme_color_override("font_color", Palette.WHITE)
	_logo.add_theme_constant_override("outline_size", 5)
	_logo.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05))
	vbox.add_child(_logo)

	_rule = ColorRect.new()
	_rule.color = Color(Palette.LCD_AMBER, 0.7)
	_rule.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(_rule)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", Palette.LCD_AMBER)
	vbox.add_child(_subtitle)

	vbox.add_child(_spacer(16))

	_new_game_button = _menu_button("")
	_new_game_button.pressed.connect(_open_new_game_setup)
	vbox.add_child(_new_game_button)

	_load_button = _menu_button("")
	_load_button.pressed.connect(_open_continue_menu)
	vbox.add_child(_load_button)

	_options_button = _menu_button("")
	_options_button.pressed.connect(func() -> void: UIManager.open_options())
	vbox.add_child(_options_button)

	_help_button = _menu_button("")
	_help_button.pressed.connect(func() -> void: UIManager.open_help())
	vbox.add_child(_help_button)

	_credits_button = _menu_button("")
	_credits_button.pressed.connect(_open_credits)
	vbox.add_child(_credits_button)

	_quit_button = _menu_button("")
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(_quit_button)

	vbox.add_child(_spacer(12))

	_footer = Label.new()
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.add_theme_font_size_override("font_size", 11)
	_footer.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	vbox.add_child(_footer)

	# Feine CRT-Scanlines GANZ OBEN (über dem Menü) — sehr niedrige Deckkraft,
	# damit die Schrift scharf bleibt, aber der Röhren-Look trägt.
	_scanlines = Scanlines.new()
	_scanlines.name = "TitleScanlines"
	_scanlines.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scanlines)

	Localization.locale_changed.connect(_refresh_locale)
	_refresh_locale(Localization.locale())
	_refresh()
	# Beim Kaltstart gehoert der erste Ton dem Laufwerk. Der Titel-MOD setzt erst
	# nach dem kurzen Loader ein; ohne Intro beginnt er direkt im Hauptmenue.
	if ScenePresentation.should_show_startup_intro():
		_open_startup_scene_intro.call_deferred()
	else:
		MusicManager.play_title()
	GameManager.game_started.connect(_on_game_started)
	GameManager.returned_to_title.connect(_on_returned_to_title)
	set_process(true)


## Titel-Unterseiten sind transienter Menüzustand, kein Teil des Spielstands.
## Insbesondere darf die zum Laden verwendete Fortsetzen-Seite nicht hinter dem
## laufenden Spiel liegen bleiben und bei der späteren Rückkehr erneut erscheinen.
func _on_game_started() -> void:
	_discard_startup_scene_intro()
	_discard_active_page()
	visible = false
	set_process(false)
	MusicManager.stop()


func _on_returned_to_title() -> void:
	# Defensive zweite Bereinigung für alternative Start-/Testpfade, die nicht
	# über game_started liefen. Das Hauptmenü ist danach immer die Wurzelseite.
	_discard_startup_scene_intro()
	_discard_active_page()
	if is_instance_valid(_main_menu):
		_main_menu.visible = true
		_main_menu.modulate.a = 1.0
	_refresh()
	visible = true
	set_process(true)
	MusicManager.play_title()


## Der Godot-Splash bleibt Engine-Sache. Sobald Main wirklich bereit ist,
## uebernimmt einmalig diese originale PAL-Szenesequenz und gibt danach das
## interaktive Hauptmenue frei. Screenshot- und Headless-Laeufe werden durch
## ScenePresentation.should_show_startup_intro() automatisch ausgespart.
func _open_startup_scene_intro() -> void:
	if is_instance_valid(_startup_intro) or not is_instance_valid(_main_menu):
		return
	# Ein klassischer Custom-Loader beginnt ohne laufenden Titel-MOD. Erst die
	# fertige Decrunch-/Ladephase gibt Musik und Cracktro gemeinsam frei.
	MusicManager.stop()
	AudioManager.stop_floppy()
	AudioManager.floppy_read()
	_main_menu.visible = false
	_startup_intro = ScenePresentation.new()
	_startup_intro.name = "StartupSceneIntro"
	_startup_intro.call("configure", ScenePresentation.MODE_INTRO)
	_startup_intro.intro_started.connect(_on_startup_cracktro_started, CONNECT_ONE_SHOT)
	_startup_intro.finished.connect(_on_startup_scene_intro_finished, CONNECT_ONE_SHOT)
	add_child(_startup_intro)
	_startup_intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_startup_intro.z_as_relative = false
	# Godots CanvasItem-Grenze endet bei 4096. Zwei Stufen Reserve halten
	# Debug-/Systemoverlays weiterhin moeglich, ohne eine Engine-Warnung.
	_startup_intro.z_index = ScenePresentation.SAFE_OVERLAY_Z


func _on_startup_cracktro_started() -> void:
	AudioManager.stop_floppy()
	if visible:
		MusicManager.play_title()


func _on_startup_scene_intro_finished() -> void:
	AudioManager.stop_floppy()
	if is_instance_valid(_startup_intro):
		_startup_intro.queue_free()
	_startup_intro = null
	if not is_instance_valid(_main_menu) or not visible:
		return
	# Skip waehrend des Loaders soll nicht in ein stummes Hauptmenue fuehren.
	if not MusicManager.is_playing():
		MusicManager.play_title()
	_main_menu.visible = true
	if bool(SettingsManager.value("reduced_motion")):
		_main_menu.modulate.a = 1.0
		return
	_main_menu.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_main_menu, "modulate:a", 1.0, 0.24)


func _discard_startup_scene_intro() -> void:
	if is_instance_valid(_startup_intro):
		_startup_intro.queue_free()
	_startup_intro = null


## Entfernt eine Fortsetzen-, Credits- oder sonstige Titel-Unterseite sofort
## aus der sichtbaren Bühne. `_active_page` wird vor `remove_child()` geleert,
## damit ihr tree_exited-Callback nicht versehentlich eine zweite Rückblende
## oder einen veralteten Seitenzustand startet.
func _discard_active_page() -> void:
	if not is_instance_valid(_active_page):
		_active_page = null
		return
	var page := _active_page
	_active_page = null
	if page.get_parent() == self:
		remove_child(page)
	page.queue_free()


## Dezentes „Atmen" der Marken-Akzente: Neonlinie pulsiert weich, das Disketten-
## Emblem schimmert und wippt minimal, das Logo bekommt einen leisen Glanz.
## Nur wenn das Menü sichtbar ist (im Spiel schläft die Ebene).
func _process(delta: float) -> void:
	if not is_visible_in_tree() or bool(SettingsManager.value("reduced_motion")):
		return
	_fx_time += delta
	if _rule != null:
		_rule.color = Color(Palette.LCD_AMBER, 0.55 + 0.28 * (0.5 + 0.5 * sin(_fx_time * 1.6)))
	if _disk != null:
		var shimmer := 0.90 + 0.12 * sin(_fx_time * 0.9)
		_disk.modulate = Color(shimmer, shimmer, shimmer, 1.0)
	if _logo != null:
		var glow := 0.10 + 0.06 * (0.5 + 0.5 * sin(_fx_time * 1.2))
		_logo.add_theme_color_override("font_outline_color", Color(0.55, 0.42, 0.12, 0.35 + glow))


## „Spiel fortsetzen" und Credits sind echte Seiten des Hauptmenüs. Hintergrund,
## Musik und CRT-Layer bleiben bestehen; nur der zentrale Seiteninhalt wechselt.
## Damit entsteht weder ein zweiter Fensterrahmen noch ein Dialog über einem
## weiterhin sichtbaren Hauptmenü.
func _open_continue_menu() -> void:
	if is_instance_valid(_active_page):
		return
	var menu := SaveSlotMenu.new()
	menu.name = "SaveSlotMenu"
	menu.embedded_in_title = true
	_open_title_page(menu)


## „Neues Spiel" → Spielstart-Setup (Name, Geburtstag, Avatar) als Overlay.
## „Los geht's" darin startet dann GameManager.new_game().
func _open_new_game_setup() -> void:
	if has_node("NewGameSetup"):
		return
	var setup := NewGameSetup.new()
	setup.name = "NewGameSetup"
	setup.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(setup)


func _open_credits() -> void:
	if is_instance_valid(_active_page):
		return
	var credits := CreditsScreen.new()
	credits.embedded_in_title = true
	_open_title_page(credits)


func _open_title_page(page: Control) -> void:
	_active_page = page
	page.modulate.a = 0.0
	add_child(page)
	# `set_anchors_preset(FULL_RECT)` allein behaelt je nach Zeitpunkt die
	# bisherigen Offsets einer frisch erzeugten Control. Bei aktivem Clipping
	# konnte die Seite dadurch korrekt im Baum liegen, aber effektiv 0x0 Pixel
	# gross sein: schwarzer/leerer Bildschirm nach »Spiel fortsetzen«.
	# Anker UND Offsets werden nach dem Einhaengen verbindlich gesetzt.
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Die statischen Scanlines bleiben als gemeinsames Displayglas über allen
	# Hauptmenüseiten, fangen aber keine Eingabe ab.
	if is_instance_valid(_scanlines):
		move_child(page, _scanlines.get_index())
	if is_instance_valid(_main_menu):
		_main_menu.visible = false
	page.tree_exited.connect(_on_title_page_closed.bind(page), CONNECT_ONE_SHOT)
	if OS.get_environment("DSS_SHOT") == "1" \
			or bool(SettingsManager.value("reduced_motion")):
		page.modulate.a = 1.0
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(page, "modulate:a", 1.0, 0.18)


func _on_title_page_closed(page: Control) -> void:
	if _active_page != page:
		return
	_active_page = null
	if not is_instance_valid(_main_menu):
		return
	_main_menu.visible = true
	if OS.get_environment("DSS_SHOT") == "1" \
			or bool(SettingsManager.value("reduced_motion")):
		_main_menu.modulate.a = 1.0
		_refresh()
		return
	_main_menu.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_main_menu, "modulate:a", 1.0, 0.16)
	_refresh()


## AAA-Menü-Button: dunkles Feld, Amber-Rahmen, Hover leuchtet auf.
func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(292, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.09, 0.12, 0.9)
	normal.border_color = Color(Palette.LCD_AMBER, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.15, 0.05, 0.95)
	hover.border_color = Palette.LCD_AMBER
	hover.border_width_left = 3
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.04, 0.04, 0.05, 0.95)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.07, 0.07, 0.08, 0.7)
	disabled.border_color = Color(0.3, 0.3, 0.3, 0.4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", Palette.WHITE_SOFT)
	b.add_theme_color_override("font_hover_color", Palette.LCD_AMBER)
	b.add_theme_color_override("font_disabled_color", Palette.UI_TEXT_DIM)
	return b


func _sync_size() -> void:
	var parent_control := get_parent_control()
	if parent_control != null:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	# Auch isolierte Titel-Sichttests oder alternative Startbuehnen besitzen
	# keinen Control-Parent. Clipping darf in diesem Fall nicht die komplette
	# Oberflaeche verschlucken.
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _refresh() -> void:
	_load_button.disabled = not SaveManager.has_save()


## Der TranslationServer ersetzt bestehende Button-Literale nicht automatisch.
## Darum besitzt das dauerhaft sichtbare Hauptmenü genau einen Refresh-Pfad, den
## sowohl der Erstaufbau als auch die live geänderte Sprache verwenden.
func _refresh_locale(_locale: String) -> void:
	if BuildChannel.is_first_year_demo():
		_logo.text = Loc.t("ui.title_screen.demo_logo", "SOMMER '90 · DEMO")
		_subtitle.text = Loc.t("ui.title_screen.demo_subtitle",
			"ITCH.IO EDITION · DER KOMPLETTE SOMMER 1990")
		_new_game_button.text = Loc.t("ui.title_screen.demo_start",
			"▶  DEMO STARTEN — SOMMER 1990")
		_load_button.text = Loc.t("ui.title_screen.demo_continue", "Demo fortsetzen")
		_options_button.text = Loc.t("ui.title_screen.options", "Optionen")
		_help_button.text = Loc.t("ui.title_screen.help", "Hilfe")
		_credits_button.text = Loc.t("ui.title_screen.credits", "Credits")
		_quit_button.text = Loc.t("ui.title_screen.quit", "Beenden")
		_footer.text = Loc.t("ui.title_screen.demo_footer",
			"1990 komplett · Eigene Demo-Spielstaende · Die Vollversion geht bis 1999.\n"
			+ "F1 Hilfe · F5 Speichern · F9 Laden · F11 Vollbild")
		return
	_logo.text = Loc.t("ui.title_screen.sommer_90", "SOMMER '90")
	_subtitle.text = Loc.t("ui.title_screen.1990_1999_zeitreise_in_disketten",
		"1990–1999 · Eine Zeitreise in Disketten")
	_new_game_button.text = Loc.t_format("ui.title_screen.new_game_summer",
		"▶  Neues Spiel — Sommer %d", [TimelineManager.start_year])
	_load_button.text = Loc.t("ui.title_screen.continue_game", "Spiel fortsetzen")
	_options_button.text = Loc.t("ui.title_screen.options", "Optionen")
	_help_button.text = Loc.t("ui.title_screen.help", "Hilfe")
	_credits_button.text = Loc.t("ui.title_screen.credits", "Credits")
	_quit_button.text = Loc.t("ui.title_screen.quit", "Beenden")
	_footer.text = Loc.t("ui.title_screen.liebevolle_fiktive_erinnerung_an_heimcomputer_ara",
		"Eine liebevolle, fiktive Erinnerung an die Heimcomputer-Ära.\nF1 Hilfe · F5 Speichern · F9 Laden · F11 Vollbild · Optionen im Menü")


func _find_menu_art() -> String:
	for pattern in MENU_ART_PATTERNS:
		for version in range(9, 0, -1):
			var path: String = pattern % version
			if RoomCompositor.asset_exists(path):
				return path
	return RoomCompositor.find_base(TimelineManager.start_year)


func _vignette_texture() -> ImageTexture:
	var img := Image.create(4, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var t := absf(y - 31.5) / 31.5
		var alpha := clampf(pow(t, 2.0) * 0.92, 0.0, 0.92)
		for x in 4:
			img.set_pixel(x, y, Color(0.0, 0.0, 0.02, alpha))
	return ImageTexture.create_from_image(img)


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


## Animierte Zierebene (hinter dem Menü): Parallax-Staub mit Tiefe & Funkeln,
## eine dezente Amiga-Copper-Schimmerband-Homage und ein weicher Lichtsweep.
## Alles bewusst niedrige Deckkraft — Atmosphäre, keine Ablenkung.
class _MenuFX:
	extends Control

	var _t := 0.0
	var _motes: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x5CE7E
		for i in 96:
			var depth := rng.randf()   # 0 = fern/dunkel/langsam, 1 = nah/hell/schnell
			_motes.append({
				"x": rng.randf(),
				"y": rng.randf(),
				"depth": depth,
				"spd": lerpf(0.006, 0.028, depth),
				"sz": 1.0 if depth < 0.62 else 2.0,
				"phase": rng.randf_range(0.0, TAU),
				"drift": rng.randf_range(0.004, 0.014),
				"tw": rng.randf_range(0.6, 1.9),
				"amber": rng.randf() < 0.42,
			})
		set_process(true)

	func _process(delta: float) -> void:
		# A hidden parent does not stop Godot's child processing. Keep the title
		# decoration still both during gameplay and with reduced motion enabled.
		if not is_visible_in_tree() or bool(SettingsManager.value("reduced_motion")):
			return
		_t += delta
		for m in _motes:
			m["y"] -= m["spd"] * delta
			if m["y"] < -0.02:
				m["y"] = 1.02
				m["x"] = randf()
		queue_redraw()

	func _draw() -> void:
		if size.x < 4.0:
			return
		# 1) Copper-Schimmer: ein sanftes Farbband, das langsam nach oben zieht
		#    und zwischen Blau und Amber changiert (Demoszene-Zitat, sehr leise).
		var band_y := fmod(_t * 9.0, size.y + 200.0) - 100.0
		var hue: Color = Color(0.28, 0.52, 1.0).lerp(Color(0.95, 0.6, 0.18), 0.5 + 0.5 * sin(_t * 0.25))
		for i in 56:
			var yy := band_y + i
			if yy < 0.0 or yy >= size.y:
				continue
			var glow := sin(float(i) / 56.0 * PI)
			draw_rect(Rect2(0.0, yy, size.x, 1.0), Color(hue.r, hue.g, hue.b, glow * 0.022))

		# 2) Parallax-Staub mit organischem Seitendrift und Funkeln
		for m in _motes:
			var dx: float = sin(_t * 0.3 + m["phase"]) * float(m["drift"])
			var p := Vector2((float(m["x"]) + dx) * size.x, float(m["y"]) * size.y)
			var twinkle: float = 0.5 + 0.5 * sin(_t * float(m["tw"]) + float(m["x"]) * 18.0)
			var a: float = lerpf(0.05, 0.17, float(m["depth"])) * (0.45 + 0.55 * twinkle)
			var c: Color = Color(1.0, 0.74, 0.28, a) if m["amber"] else Color(0.5, 0.86, 1.0, a * 0.85)
			var s: float = m["sz"]
			# naher Staub bekommt einen weichen Halo → Tiefe ohne Shader
			if float(m["depth"]) > 0.74:
				draw_rect(Rect2(p - Vector2.ONE, Vector2(s + 2.0, s + 2.0)), Color(c.r, c.g, c.b, a * 0.22))
			draw_rect(Rect2(p, Vector2(s, s)), c)

		# 3) Weicher Lichtsweep (heller Kern + abklingender Nachzug)
		var sy := fmod(_t * 46.0, size.y + 130.0) - 65.0
		draw_rect(Rect2(0.0, sy, size.x, 1.0), Color(0.72, 0.86, 1.0, 0.06))
		for k in 26:
			draw_rect(Rect2(0.0, sy + 1.0 + k, size.x, 1.0),
				Color(0.4, 0.6, 1.0, 0.018 * (1.0 - float(k) / 26.0)))


## Statische CRT-Scanlines als oberste Ebene. Sehr niedrige Deckkraft (Röhren-
## Textur), zeichnet nur bei Größenänderung neu — kein Laufzeit-Overhead.
class Scanlines:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.y < 4.0:
			return
		var y := 0.0
		while y < size.y:
			draw_rect(Rect2(0.0, y, size.x, 1.0), Color(0.0, 0.0, 0.02, 0.05))
			y += 3.0
