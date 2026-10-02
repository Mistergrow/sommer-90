extends Node
## SettingsManager — globale Einstellungen (Grafik/Ton), persistent in
## user://settings.cfg. Wird beim Start geladen und angewandt; das
## Optionen-Fenster liest/schreibt hierüber. Getrennt vom Spielstand: gilt
## sitzungs- und spielstandsübergreifend.

signal settings_changed

const PATH := "user://settings.cfg"
const DEFAULTS := {
	# Experimenteller Gesamtspiel-Look: liegt ueber Orten, HUD und Fenstern. Der
	# physische Monitor-CRT darunter bleibt ein getrenntes, automatisch geschaltetes
	# System, damit beide Varianten unabhaengig vergleichbar sind.
	# Spielsprache. Quellsprache ist Deutsch; die Auswahl ist auf Sprachen
	# begrenzt, die Topaz und VT323 darstellen koennen (siehe Loc.FULL_LOCALES).
	"locale": "de",
	"crt_global_filter": false,
	"crt_auto_monitor": true, # CRT einschalten, sobald man am eingeschalteten Monitor sitzt
	"scanlines": true,        # Scanlines in Retro-Programmen (X-COPY …)
	"wb_colors": [],          # Werkbank-Palette (4 HTML-Farben, [] = Original)
	"wb_colors_wb205": [],    # Release-2-Palette getrennt von der 1.3-Nostalgie
	"wb_colors_wb30": [],     # AGA-Workbench 3.0
	"wb_colors_wb31": [],     # AmigaOS 3.1
	"wb_screen_mode": "auto",       # auto / pal / best; Workbench 1.3
	"wb_screen_mode_wb205": "auto", # ECS Productivity nur mit passender Hardware
	"wb_screen_mode_wb30": "auto",  # AGA-Workbench 3.0
	"wb_screen_mode_wb31": "auto",  # AmigaOS 3.1
	"location_depth": true,   # dezentes 2,5D-Parallax der fotografischen Orte
	"ambient_life": true,     # Reflexe, Passantenschatten, Vögel, CRT-Lebenszeichen
	"reduced_motion": false,  # stoppt Portrait-Idle/Lip-Sync und andere Mikrobewegung
	"hud_scene_generation": "auto", # auto / ocs / ecs / aga; spätere Amigas können zurückschalten
	"hud_scene_effect": "equalizer", # Legacy-Auswahl für alte settings.cfg
	"hud_scene_effect_ocs": "",      # je Generation separat gemerkter Scene-Effekt
	"hud_scene_effect_ecs": "",
	"hud_scene_effect_aga": "",
	"hud_scene_gain": 1.0,         # FFT-Empfindlichkeit 0.65..1.75
	"hud_scene_decay": 0.62,       # Nachleuchten: 0 = direkt, 1 = lang
	"hud_scene_peaks": true,       # klassische Peak-Hold-Pixel ueber den Baendern
	"hud_scene_bands": 24,         # 12 / 24 / 32 sichtbare Frequenzbaender
	"hud_scene_palette": "sunset", # sunset / ice / phosphor / candy
	"fullscreen": false,
	"master": 0.9,            # Gesamtlautstärke (linear 0..1)
	"music": 0.7,
	"sfx": 0.8,
}

var _data: Dictionary = {}


func _ready() -> void:
	_load()
	# Fenstergröße/-modus SOFORT setzen (vor dem ersten Frame), damit die
	# Skalierungs-Transformation einmal feststeht und Eingabe- und Render-
	# Transformation nie auseinanderlaufen (sonst „verschobene" Maus auf X11).
	apply_window_mode()
	# Ton & Restliches nach dem ersten Frame anwenden.
	apply_all.call_deferred()


func value(key: String) -> Variant:
	return _data.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	_data[key] = _normalize_value(key, v)
	_apply(key)
	_save()
	settings_changed.emit()


# ----------------------------------------------------------------- Persistenz

func _load() -> void:
	_data = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	var loaded := cfg.load(PATH) == OK
	if loaded:
		for k in DEFAULTS:
			_data[k] = _normalize_value(k, cfg.get_value("settings", k, DEFAULTS[k]))
	# Erster Start ohne gespeicherte Sprache: deutschsprachige Systeme bleiben bei
	# der Quellsprache, alle anderen bekommen Englisch statt eines deutschen Spiels.
	# Nur Sprachen mit echtem Katalog; eine gespeicherte Wahl gewinnt immer.
	# Nur in Release-Exports: Editor und Tests bleiben unabhaengig von der
	# Systemsprache des Rechners deterministisch deutsch.
	if OS.has_feature("sommer90_production") \
			and not (loaded and cfg.has_section_key("settings", "locale")):
		_data["locale"] = "de" if OS.get_locale_language() == "de" else "en"


## ConfigFile accepts arbitrary Variants, including NaN and collections. Check
## types before converting so one damaged setting cannot abort startup or feed
## non-finite gain into the audio mixer. Live writes use the same contract.
func _normalize_value(key: String, candidate: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	match typeof(fallback):
		TYPE_FLOAT:
			if not (candidate is float or candidate is int) or not is_finite(float(candidate)):
				return fallback
			if key == "hud_scene_gain":
				return clampf(float(candidate), 0.65, 1.75)
			return clampf(float(candidate), 0.0, 1.0)
		TYPE_BOOL:
			return candidate if candidate is bool else fallback
		TYPE_INT:
			if not (candidate is int or candidate is float) or not is_finite(float(candidate)):
				return fallback
			return int(candidate) if candidate in [12, 24, 32] else fallback
		TYPE_ARRAY:
			if not candidate is Array or candidate.size() not in [0, 4]:
				return []
			for color: Variant in candidate:
				if not color is String or not Color.html_is_valid(color):
					return []
			return candidate.duplicate()
		TYPE_STRING:
			if not candidate is String:
				return fallback
			if key == "hud_scene_palette" and candidate not in ["sunset", "ice", "phosphor", "candy"]:
				return fallback
			if key == "hud_scene_generation" and candidate not in ["auto", "ocs", "ecs", "aga"]:
				return fallback
			if key.begins_with("wb_screen_mode") and candidate not in ["auto", "pal", "best"]:
				return fallback
			return candidate
	return fallback


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in _data:
		cfg.set_value("settings", k, _data[k])
	cfg.save(PATH)


# ----------------------------------------------------------------- Anwenden

func apply_all() -> void:
	for k in DEFAULTS:
		_apply(k)


func _apply(key: String) -> void:
	match key:
		"fullscreen":
			apply_window_mode()
		"master":
			AudioServer.set_bus_volume_db(0, _to_db(float(value("master"))))
		"music":
			MusicManager.set_music_volume(float(value("music")))
		"sfx":
			AudioManager.set_sfx_volume(float(value("sfx")))


func _to_db(linear: float) -> float:
	return -60.0 if linear <= 0.001 else linear_to_db(clampf(linear, 0.0, 1.0))


# ----------------------------------------------------- Fenster / Auflösung
## Wendet den gespeicherten Anzeigemodus dynamisch an: entweder Vollbild oder
## Fenstermodus mit einer Größe, die zum aktuellen Bildschirm passt (16:9
## erhalten, zentriert). So startet das Spiel auf jedem Monitor sinnvoll.

const DESIGN_SIZE := Vector2i(1440, 810)   # Referenz-Seitenverhältnis (16:9)
const MIN_SIZE := Vector2i(960, 540)       # kleinste sinnvolle Fenstergröße
const WINDOW_FILL := 0.9                    # max. Anteil der nutzbaren Fläche


func apply_window_mode() -> void:
	var win := get_window()
	if win == null:
		return
	win.min_size = MIN_SIZE
	if bool(value("fullscreen")):
		win.mode = Window.MODE_FULLSCREEN
	else:
		# Windowed = MAXIMIERT: füllt den Bildschirm (Taskleiste respektiert),
		# bleibt resizable/wiederherstellbar. Robuster als eigene Größenrechnung
		# (kein X11-Maus-Versatz) und der Content skaliert per canvas_items mit.
		win.mode = Window.MODE_MAXIMIZED


## Berechnet die größte 16:9-Fenstergröße, die in ~90 % der nutzbaren
## Bildschirmfläche Platz hat, setzt Mindestgröße und zentriert das Fenster.
## Wichtig: das Fenster behält exakt das 16:9-Seitenverhältnis (kein Letterbox,
## keine Maus-Verschiebung) und wird über die dekorations-bewusste
## move_to_center() der Engine platziert — nicht per Hand, das würde auf manchen
## Fenstermanagern (Linux/X11) einen Versatz zwischen sichtbarem Bild und
## echter Klickposition erzeugen.
func fit_window(win: Window) -> void:
	var screen_idx := win.current_screen
	var usable := DisplayServer.screen_get_usable_rect(screen_idx)
	if usable.size.x <= 0 or usable.size.y <= 0:
		usable = Rect2i(Vector2i.ZERO, DisplayServer.screen_get_size(screen_idx))

	# Größte einheitliche Skalierung, die in ~90 % der nutzbaren Fläche passt.
	var budget := Vector2(usable.size) * WINDOW_FILL
	var ui_scale := minf(budget.x / float(DESIGN_SIZE.x), budget.y / float(DESIGN_SIZE.y))
	# Nicht kleiner als das Minimum (auf winzigen Bildschirmen), aber die
	# 16:9-Form immer exakt erhalten.
	ui_scale = maxf(ui_scale, float(MIN_SIZE.x) / float(DESIGN_SIZE.x))
	var target := Vector2i(
		int(round(DESIGN_SIZE.x * ui_scale)),
		int(round(DESIGN_SIZE.y * ui_scale))
	)
	# Falls das Minimum das Fenster über den Bildschirm hinaus zwingen würde,
	# lieber auf die nutzbare Fläche begrenzen.
	target.x = mini(target.x, usable.size.x)
	target.y = mini(target.y, usable.size.y)

	win.min_size = MIN_SIZE
	win.size = target
	win.move_to_center()
