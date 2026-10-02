class_name ScenePresentationScreen
extends Control
## Vollbild-Praesentation fuer Startintro und Produktionsabspann.
##
## Die Choreografien verwenden ausschliesslich den eigenen PAL-DemoPlayer und
## originale Texte. Sie zitieren die Technik der Amiga-Demoszene, uebernehmen
## aber keine fremden Cracktro-Logos, Scrolltexte oder ungeklärte Musik.

signal finished
signal intro_started

const MODE_INTRO := "intro"
const MODE_CREDITS := "credits"
const MODE_DEMO_FINALE := "demo_finale"
const SAFE_OVERLAY_Z := 4094
const PRESENTATION_DATA := "res://data/scene_presentations.json"
const DemoPlayerScript := preload("res://scripts/ui/demo_player.gd")
const StartupLoadPreludeScript := preload("res://scripts/ui/startup_load_prelude.gd")
const StartupCracktroOverlayScript := preload("res://scripts/ui/startup_cracktro_overlay.gd")

static var _startup_intro_consumed := false
static var _last_preset_by_mode: Dictionary = {}

var presentation_mode := MODE_INTRO
var credits_data: Dictionary = {}
var forced_preset_id := ""
var _pool: Array = []
var _preset_index := 0
var _demo: Control
var _roll: Control
var _chrome: Control
var _primary_button: Button
var _pause_button: Button
var _load_prelude: Control
var _release_overlay: Control
var _elapsed := 0.0
var _intro_duration := 16.0
var _intro_playing := true
var _finished_once := false
var _reduced_motion := false


static func should_show_startup_intro() -> bool:
	if _startup_intro_consumed:
		return false
	if OS.get_environment("DSS_SKIP_SCENE_INTRO") == "1":
		return false
	var explicitly_requested := OS.get_environment("DSS_SCENE_INTRO") == "1"
	if OS.get_environment("DSS_SHOT") == "1" and not explicitly_requested:
		return false
	if DisplayServer.get_name() == "headless" and not explicitly_requested:
		return false
	_startup_intro_consumed = true
	return true


func configure(mode: String, data: Dictionary = {}, preset_id: String = "") -> void:
	presentation_mode = mode if mode in [MODE_INTRO, MODE_CREDITS, MODE_DEMO_FINALE] else MODE_INTRO
	credits_data = data.duplicate(true)
	forced_preset_id = preset_id
	if is_node_ready():
		_rebuild_presentation()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_reduced_motion = _setting_bool("reduced_motion", false)
	_rebuild_presentation()
	set_process(true)


func _rebuild_presentation() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_demo = null
	_roll = null
	_chrome = null
	_primary_button = null
	_pause_button = null
	_load_prelude = null
	_release_overlay = null
	_intro_playing = presentation_mode != MODE_INTRO
	_finished_once = false
	_load_pool()
	_build_surface()
	_select_initial_preset()
	_apply_preset()


func _load_pool() -> void:
	_pool.clear()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESENTATION_DATA))
	if not raw is Dictionary:
		return
	var entries: Variant = (raw as Dictionary).get(presentation_mode, [])
	if entries is Array:
		for entry: Variant in entries:
			if entry is Dictionary:
				_pool.append((entry as Dictionary).duplicate(true))


func _build_surface() -> void:
	var black := ColorRect.new()
	black.name = "PresentationBlack"
	black.color = Color(0.002, 0.003, 0.008, 1.0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)

	_demo = DemoPlayerScript.new()
	_demo.name = "CreditsHero" if presentation_mode == MODE_CREDITS else "SceneDemoPlayer"
	_demo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_demo)

	if presentation_mode == MODE_CREDITS:
		_roll = _CreditsRoll.new()
		_roll.name = "ProductionCredits"
		_roll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_roll.call("configure", credits_data, _locale_code())
		add_child(_roll)

	# Intro und Abspann sind keine normalen Fenster. Beide laufen als reine
	# PAL-Szenepraesentation mit einem dezenten FIRE-Hinweis direkt im Bild.
	# Nur das interaktive Demo-Finale behaelt seine Bedienleiste.
	if presentation_mode in [MODE_INTRO, MODE_CREDITS]:
		var prompt := _CracktroPrompt.new()
		prompt.name = "SceneCreditsPrompt" if presentation_mode == MODE_CREDITS \
			else "SceneFirePrompt"
		prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		prompt.call("configure", _ui(
			"ESC · SPACE · KLICK  —  ZURUECK",
			"ESC · SPACE · CLICK  —  BACK") if presentation_mode == MODE_CREDITS else _ui(
			"FIRE · SPACE · KLICK  —  WEITER ZUM SPIEL",
			"FIRE · SPACE · CLICK  —  CONTINUE TO GAME"))
		add_child(prompt)
		if presentation_mode == MODE_INTRO:
			_release_overlay = StartupCracktroOverlayScript.new()
			_release_overlay.name = "StartupCracktroReleaseOverlay"
			_release_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_release_overlay.visible = false
			add_child(_release_overlay)

			_load_prelude = StartupLoadPreludeScript.new()
			_load_prelude.name = "StartupPalLoadPrelude"
			_load_prelude.call("configure", _reduced_motion, "DF0:",
				_ui("LADE INTRO", "LOADING INTRO"))
			_load_prelude.completed.connect(_on_load_prelude_completed, CONNECT_ONE_SHOT)
			_load_prelude.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(_load_prelude)
	else:
		_chrome = _PresentationChrome.new()
		_chrome.name = "ScenePresentationChrome"
		_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_chrome)

		_primary_button = _retro_button("")
		_primary_button.name = "ContinueDemoFinaleButton"
		_primary_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_primary_button.position = Vector2(-238.0, 18.0)
		_primary_button.size = Vector2(220.0, 36.0)
		_primary_button.pressed.connect(dismiss)
		add_child(_primary_button)

		_pause_button = _retro_button("")
		_pause_button.name = "PauseCreditsButton"
		_pause_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_pause_button.position = Vector2(18.0, 18.0)
		_pause_button.size = Vector2(176.0, 36.0)
		_pause_button.visible = false
		_pause_button.pressed.connect(_toggle_pause)
		add_child(_pause_button)
	_refresh_buttons()


func _select_initial_preset() -> void:
	_preset_index = 0
	if _pool.is_empty():
		return
	# Alle Praesentationsarten teilen denselben Auswahlvertrag: Tests und
	# Screenshots koennen ein Preset erzwingen, im Spiel rotiert die Sammlung
	# zufaellig und vermeidet eine direkte Wiederholung.
	var requested := forced_preset_id.strip_edges()
	if requested.is_empty():
		requested = OS.get_environment("DSS_SCENE_PRESET").strip_edges()
	var selected_by_id := false
	if not requested.is_empty():
		for i in _pool.size():
			if str((_pool[i] as Dictionary).get("id", "")) == requested:
				_preset_index = i
				selected_by_id = true
				break
	if not selected_by_id:
		var rng := RandomNumberGenerator.new()
		rng.seed = Time.get_ticks_usec() ^ int(get_instance_id()) ^ presentation_mode.hash()
		_preset_index = rng.randi_range(0, _pool.size() - 1)
		var previous := str(_last_preset_by_mode.get(presentation_mode, ""))
		if _pool.size() > 1 \
				and str((_pool[_preset_index] as Dictionary).get("id", "")) == previous:
			_preset_index = (_preset_index + 1 + rng.randi_range(0, _pool.size() - 2)) \
				% _pool.size()
	_last_preset_by_mode[presentation_mode] = str(
		(_pool[_preset_index] as Dictionary).get("id", ""))


func _apply_preset() -> void:
	if _pool.is_empty() or not is_instance_valid(_demo):
		return
	_preset_index = posmod(_preset_index, _pool.size())
	var preset := _pool[_preset_index] as Dictionary
	var project_raw: Variant = preset.get("project", {})
	var project := _localized_project(project_raw as Dictionary if project_raw is Dictionary else {})
	if presentation_mode == MODE_CREDITS:
		# Der Abspanntext ist der Held; Titelgrafiken der Demo bleiben als ruhige
		# Kulisse hinter dem echten, lesbaren Rollenlauf.
		var parts: Array = project.get("parts", []) as Array
		for raw_part: Variant in parts:
			if raw_part is Dictionary:
				(raw_part as Dictionary)["show_title"] = false
				(raw_part as Dictionary)["show_group"] = false
	project["reduced_flash"] = true
	_demo.call("set_project", project)
	_intro_duration = float(_demo.call("total_duration")) + 0.35
	if _reduced_motion:
		_demo.call("seek", minf(2.0, _intro_duration * 0.25))
		_demo.call("set_playback_paused", true)
	if presentation_mode == MODE_INTRO:
		_demo.call("set_playback_paused", true)
		if is_instance_valid(_release_overlay):
			_release_overlay.call("configure",
				str(project.get("group", "NIGHTSHIFT CREW")),
				str(project.get("release_id", "S90-001")),
				str(project.get("release_status", _ui(
					"GEPRUEFT · ENTCRUNCHT · STARTKLAR",
					"CHECKED · DECRUNCHED · READY"))),
				str(project.get("authenticity", _ui(
					"FIKTIVE SZENEFASSUNG · EIGENER CODE",
					"FICTIONAL SCENE EDITION · ORIGINAL CODE"))),
				str(project.get("machine", "A500 · OCS · PAL · DF0: · 4CH")))
	_elapsed = 0.0
	_last_preset_by_mode[presentation_mode] = str(preset.get("id", ""))
	if is_instance_valid(_roll):
		_roll.call("restart")
		_roll.call("set_paused", false)
	if is_instance_valid(_chrome):
		_chrome.call("configure", presentation_mode, _localized(preset.get("label", "")),
			_preset_index + 1, _pool.size())
	_refresh_buttons()


func _localized_project(source: Dictionary) -> Dictionary:
	var project := source.duplicate(true)
	for key in ["title", "group", "scroller", "scrolltext", "tagline",
			"release_status", "authenticity", "machine"]:
		if project.has(key):
			project[key] = _localized(project[key])
	var parts: Array = project.get("parts", []) as Array
	for raw_part: Variant in parts:
		if not raw_part is Dictionary:
			continue
		var part := raw_part as Dictionary
		for key in ["title", "group", "handle", "scroller", "scrolltext", "name", "tagline"]:
			if part.has(key):
				part[key] = _localized(part[key])
	return project


func _process(delta: float) -> void:
	if presentation_mode == MODE_INTRO and not _intro_playing:
		return
	_elapsed += delta
	if _finished_once:
		return
	if presentation_mode == MODE_CREDITS:
		if is_instance_valid(_roll) and bool(_roll.call("is_finished")):
			dismiss()
		return
	if presentation_mode not in [MODE_INTRO, MODE_DEMO_FINALE]:
		return
	var limit := 4.2 if _reduced_motion else _intro_duration
	if _elapsed >= limit:
		dismiss()


func _on_load_prelude_completed() -> void:
	if is_instance_valid(_load_prelude):
		_load_prelude.queue_free()
	_load_prelude = null
	_intro_playing = true
	_elapsed = 0.0
	if is_instance_valid(_release_overlay):
		_release_overlay.visible = true
	if is_instance_valid(_demo):
		_demo.call("restart")
		_demo.call("set_playback_paused", _reduced_motion)
	intro_started.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if presentation_mode in [MODE_INTRO, MODE_CREDITS, MODE_DEMO_FINALE] \
			and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		dismiss()


func _gui_input(event: InputEvent) -> void:
	if presentation_mode in [MODE_INTRO, MODE_CREDITS] and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		dismiss()
		return


func dismiss() -> void:
	if _finished_once:
		return
	_finished_once = true
	finished.emit()


func next_variation() -> void:
	if _pool.size() < 2:
		return
	_preset_index = (_preset_index + 1) % _pool.size()
	_apply_preset()


func set_auto_roll(enabled: bool) -> void:
	if not is_instance_valid(_roll):
		return
	_roll.call("set_paused", not enabled)
	if is_instance_valid(_demo):
		_demo.call("set_playback_paused", not enabled or _reduced_motion)
	_refresh_buttons()


func _toggle_pause() -> void:
	if not is_instance_valid(_roll):
		return
	var paused := not bool(_roll.call("is_paused"))
	_roll.call("set_paused", paused)
	if is_instance_valid(_demo):
		_demo.call("set_playback_paused", paused or _reduced_motion)
	_refresh_buttons()


func _refresh_buttons() -> void:
	if is_instance_valid(_primary_button):
		if presentation_mode == MODE_DEMO_FINALE:
			_primary_button.text = _ui("WEITER ZUM FINALE  ›", "CONTINUE TO FINALE  ›")
		else:
			_primary_button.text = _ui("INTRO UEBERSPRINGEN  ›", "SKIP INTRO  ›")
	if is_instance_valid(_pause_button) and is_instance_valid(_roll):
		_pause_button.text = _ui("WEITER  ▶", "RESUME  ▶") if bool(_roll.call("is_paused")) \
			else _ui("PAUSE  II", "PAUSE  II")


func _localized(value: Variant) -> String:
	if value is Dictionary:
		var variants := value as Dictionary
		var language := _locale_code().substr(0, 2)
		return str(variants.get(language, variants.get("de", variants.get("en", ""))))
	return str(value)


func _ui(german: String, english: String) -> String:
	return english if _locale_code().begins_with("en") else german


func _locale_code() -> String:
	var localization := get_node_or_null("/root/Localization")
	if localization != null and localization.has_method("locale"):
		return str(localization.call("locale")).to_lower()
	return str(TranslationServer.get_locale()).to_lower()


func _setting_bool(key: String, fallback: bool) -> bool:
	# Tests und einzelne Vorschauszenen koennen diese Praesentation ohne die
	# komplette Main-Szene instanziieren. Der Autoload wird deshalb bewusst
	# zur Laufzeit aufgeloest statt als globales Skript-Symbol vorausgesetzt.
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_method("value"):
		return bool(settings.call("value", key))
	return fallback


func _retro_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", Wb13.font())
	button.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.005, 0.012, 0.025, 0.88)
	normal.border_color = Color8(54, 195, 222, 190)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(7)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.08, 0.02, 0.94)
	hover.border_color = Color8(255, 174, 42)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.02, 0.03, 0.05, 0.98)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_color_override("font_color", Color8(220, 244, 244))
	button.add_theme_color_override("font_hover_color", Color8(255, 190, 70))
	return button


class _CracktroPrompt:
	extends Control

	var _text := "FIRE · SPACE · CLICK"
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func configure(value: String) -> void:
		_text = value.to_upper()
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if size.x < 16.0 or size.y < 100.0:
			return
		var font := Wb13.font()
		var font_size := clampi(int(size.y * 0.022), 14, 21)
		var width := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x := floorf((size.x - width) * 0.5)
		var baseline := floorf(size.y - minf(73.0, size.y * 0.085))
		var blink := 0.72 + 0.28 * (0.5 + 0.5 * sin(_t * 5.2))
		var panel := Rect2(x - 22.0, baseline - font_size - 8.0, width + 44.0, font_size + 18.0)
		draw_rect(panel, Color(0.0, 0.0, 0.018, 0.76))
		draw_line(panel.position, Vector2(panel.end.x, panel.position.y),
			Color(0.24, 0.86, 0.93, 0.72), 1.0)
		draw_line(Vector2(panel.position.x, panel.end.y), panel.end,
			Color(1.0, 0.46, 0.76, 0.72), 1.0)
		draw_string(font, Vector2(x + 2.0, baseline + 2.0), _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.9))
		draw_string(font, Vector2(x, baseline), _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.76, 1.0, 0.96, blink))
		var marker := "◆" if int(_t * 3.0) % 2 == 0 else "◇"
		draw_string(font, Vector2(panel.position.x + 6.0, baseline), marker,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.70, 0.20, blink))


class _PresentationChrome:
	extends Control

	var _mode := MODE_INTRO
	var _label := ""
	var _index := 1
	var _count := 1
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func configure(mode: String, label: String, index: int, count: int) -> void:
		_mode = mode
		_label = label.to_upper()
		_index = index
		_count = count
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if size.x < 8.0 or size.y < 8.0:
			return
		var font := Wb13.font()
		var cyan := Color8(64, 210, 232)
		var amber := Color8(255, 174, 42)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.0), false, 0.0)
		draw_rect(Rect2(7.0, 7.0, size.x - 14.0, size.y - 14.0), Color(cyan, 0.48), false, 1.0)
		draw_rect(Rect2(10.0, 10.0, size.x - 20.0, size.y - 20.0), Color(amber, 0.24), false, 1.0)
		var status := "PAL · 50 HZ · 4CH  //  %s  %02d/%02d" % [_label, _index, _count]
		var prefix := "CREDITS SEQUENCE" if _mode == MODE_CREDITS else \
			("DEMO FINALE" if _mode == MODE_DEMO_FINALE else "SCENE INTRO")
		# Die zweite Kopfzeile bleibt frei von Titeln und Lauftext. Unten gehoert
		# die volle Buehne dem klassischen Sinus-Scroller.
		var status_y := 73.0
		draw_rect(Rect2(10.0, 57.0, size.x - 20.0, 24.0), Color(0.0, 0.0, 0.025, 0.66))
		draw_line(Vector2(10.0, 81.0), Vector2(size.x - 10.0, 81.0), Color(cyan, 0.34), 1.0)
		draw_string(font, Vector2(18.0, status_y), prefix,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cyan)
		var width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(size.x - width - 18.0, status_y), status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, amber)
		var sweep_x := fmod(_t * 82.0, maxf(size.x - 28.0, 1.0)) + 14.0
		draw_rect(Rect2(sweep_x, 10.0, 1.0, 5.0), Color(cyan, 0.8))


class _CreditsRoll:
	extends Control

	const WHITE := Color8(236, 242, 230)
	const CYAN := Color8(67, 218, 236)
	const AMBER := Color8(255, 178, 48)
	const GREEN := Color8(98, 238, 132)
	const DIM := Color8(134, 158, 164)

	var _lines: Array[Dictionary] = []
	var _offset := 0.0
	var _paused := false
	var _finished := false
	var _total_height := 800.0
	var _locale := "de"

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hero := Control.new()
		hero.name = "CreditsHeroMarker"
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hero)
		var closing := Control.new()
		closing.name = "CreditsClosing"
		closing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(closing)
		set_process(true)

	func configure(data: Dictionary, locale: String) -> void:
		_locale = locale.substr(0, 2)
		_lines.clear()
		_add_line(str(data.get("title", "SOMMER '90")), "hero")
		_add_line(_local(data.get("subtitle", "")), "subtitle")
		_add_line("", "space")
		var release: Dictionary = data.get("release", {}) as Dictionary
		_add_line(str(release.get("studio", "")), "studio")
		_add_line(str(release.get("creator", "")), "name")
		_add_line(str(release.get("period", "1990 - 1999")), "dim")
		_add_line("", "space")
		for raw_section: Variant in data.get("sections", []):
			if not raw_section is Dictionary:
				continue
			var section := raw_section as Dictionary
			_add_line(_local(section.get("title", "")), "section")
			for raw_entry: Variant in section.get("entries", []):
				if not raw_entry is Dictionary:
					continue
				var entry := raw_entry as Dictionary
				_add_line(_local(entry.get("role", "")), "role")
				_add_line(_local(entry.get("name", "")), "name")
			_add_line("", "space")
		var licenses: Array = data.get("licenses", []) as Array
		if not licenses.is_empty():
			_add_line("QUELLEN & LIZENZEN" if _locale == "de" else "SOURCES & LICENSES", "section")
			for raw_license: Variant in licenses:
				if not raw_license is Dictionary:
					continue
				var license := raw_license as Dictionary
				_add_line(_local(license.get("name", "")), "name")
				_add_line(_local(license.get("credit", "")), "dim")
			_add_line("", "space")
		_add_line("1990  ◇  1999", "section")
		_add_line(_local(data.get("closing", "")), "closing")
		_add_line(str(release.get("copyright", "")), "dim")
		_total_height = 0.0
		for line: Dictionary in _lines:
			_total_height += _line_height(str(line.get("kind", "role")))
		restart()

	func restart() -> void:
		# Der erste Credit ist beim Oeffnen bereits sichtbar und faehrt dann wie
		# ein echter Szene-Abspann durch das Raster. Kein mehrsekündiger Leerraum.
		_offset = maxf(size.y * 0.08, 46.0)
		_finished = false
		_paused = false
		queue_redraw()

	func set_paused(value: bool) -> void:
		_paused = value

	func is_paused() -> bool:
		return _paused

	func is_finished() -> bool:
		return _finished

	func nudge(pixels: float) -> void:
		_offset = clampf(_offset + pixels, -size.y * 0.25, _total_height + size.y)
		queue_redraw()

	func _process(delta: float) -> void:
		if _paused or _finished:
			return
		_offset += delta * 31.0
		if _offset > _total_height + size.y * 0.68:
			_offset = _total_height + size.y * 0.68
			_finished = true
		queue_redraw()

	func _draw() -> void:
		if size.x < 8.0 or size.y < 8.0:
			return
		var panel := Rect2(size.x * 0.16, 62.0, size.x * 0.68, maxf(80.0, size.y - 136.0))
		draw_rect(panel, Color(0.002, 0.006, 0.014, 0.70))
		draw_rect(panel, Color(CYAN, 0.42), false, 1.0)
		draw_line(Vector2(panel.position.x + 4.0, panel.position.y + 4.0),
			Vector2(panel.end.x - 4.0, panel.position.y + 4.0), Color(AMBER, 0.54), 1.0)
		var y := panel.end.y - _offset
		for line: Dictionary in _lines:
			var kind := str(line.get("kind", "role"))
			var height := _line_height(kind)
			if y > panel.position.y - height and y < panel.end.y + height:
				_draw_line_centered(str(line.get("text", "")), kind, y, panel)
			y += height

	func _draw_line_centered(text: String, kind: String, y: float, clip_rect: Rect2) -> void:
		if text.is_empty():
			return
		var font := Wb13.font()
		var font_size := 15
		var color := DIM
		match kind:
			"hero": font_size = 39; color = WHITE
			"subtitle": font_size = 16; color = AMBER
			"studio": font_size = 21; color = CYAN
			"section": font_size = 21; color = AMBER
			"name": font_size = 19; color = WHITE
			"closing": font_size = 28; color = GREEN
			"dim": font_size = 13; color = DIM
			_: font_size = 14; color = DIM
		var upper := text.to_upper()
		while font_size > 10 and font.get_string_size(upper, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > clip_rect.size.x - 40.0:
			font_size -= 1
		var width := font.get_string_size(upper, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x := floorf(clip_rect.position.x + (clip_rect.size.x - width) * 0.5)
		draw_string(font, Vector2(x + 2.0, y + 2.0), upper,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.78))
		draw_string(font, Vector2(x, y), upper,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

	func _add_line(text: String, kind: String) -> void:
		_lines.append({"text": text.strip_edges(), "kind": kind})

	func _line_height(kind: String) -> float:
		match kind:
			"hero": return 70.0
			"subtitle": return 38.0
			"studio": return 42.0
			"section": return 52.0
			"name": return 34.0
			"closing": return 62.0
			"space": return 38.0
			_: return 28.0

	func _local(value: Variant) -> String:
		if value is Dictionary:
			var options := value as Dictionary
			return str(options.get(_locale, options.get("de", options.get("en", ""))))
		return str(value)
