class_name SceneAnimatorBoard
extends SceneSignalStrip
## Eigenstaendiger Saison-Scene-Animator fuer den breiten oberen HUD-Rahmen.
## Anders als der kompakte Notizboard-Strip besitzt er eine echte FFT-Analyse
## des Music-Busses, geglaettete Frequenzbaender, Beat-Transienten und mehrere
## freischaltbare Demoscene-Renderer. ProTracker-Pattern/Kanaele dienen als
## deterministischer Fallback und fuer die Metadatenanzeige.

const MAX_BANDS := 32
const SceneCatalog := preload("res://scripts/ui/scene_generation_catalog.gd")
const Presentation := preload("res://scripts/ui/scene_animator_presentation_catalog.gd")
var _spectrum: Array[float] = []
var _peaks: Array[float] = []
var _peak_timers: Array[float] = []
var _history: Array = []
var _analyzer: AudioEffectSpectrumAnalyzerInstance = null
var _bass_floor := 0.02
var _beat := 0.0
var _history_clock := 0.0
var _gain := 1.0
var _decay := 0.62
var _show_peaks := true
var _visible_bands := 24
var _palette_id := "sunset"
var presentation_override: Dictionary = {}:
	set(value):
		presentation_override = value.duplicate(true)
		queue_redraw()
var _backdrops: Dictionary = {}


func _ready() -> void:
	music_reactive = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for _i in MAX_BANDS:
		_spectrum.append(0.0)
		_peaks.append(0.0)
		_peak_timers.append(0.0)
	_load_visual_settings()
	SettingsManager.settings_changed.connect(_load_visual_settings)
	PlayerStats.stats_changed.connect(_load_visual_settings)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_bind_analyzer()
	super._ready()


func _on_locale_changed(_locale: String) -> void:
	queue_redraw()


func _load_visual_settings() -> void:
	_gain = clampf(float(SettingsManager.value("hud_scene_gain")), 0.65, 1.75)
	_decay = clampf(float(SettingsManager.value("hud_scene_decay")), 0.0, 1.0)
	_show_peaks = bool(SettingsManager.value("hud_scene_peaks"))
	var requested_bands := int(SettingsManager.value("hud_scene_bands"))
	var generation := SceneCatalog.generation(SceneCatalog.effective_generation())
	_visible_bands = mini(requested_bands, int(generation.get("band_cap", 12)))
	if _visible_bands not in [12, 24, 32]:
		_visible_bands = 24
	_palette_id = str(SettingsManager.value("hud_scene_palette"))
	queue_redraw()


func _bind_analyzer() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	var slot := -1
	for index in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) is AudioEffectSpectrumAnalyzer:
			slot = index
			break
	if slot < 0:
		var analyzer := AudioEffectSpectrumAnalyzer.new()
		analyzer.buffer_length = 0.35
		analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(bus, analyzer)
		slot = AudioServer.get_bus_effect_count(bus) - 1
	_analyzer = AudioServer.get_bus_effect_instance(bus, slot) as AudioEffectSpectrumAnalyzerInstance


func _process(delta: float) -> void:
	_sample_spectrum(delta)
	_history_clock += delta
	if _history_clock >= 0.075:
		_history_clock = fmod(_history_clock, 0.075)
		_history.push_front(_spectrum.duplicate())
		if _history.size() > 10:
			_history.pop_back()
	super._process(delta)


func _sample_spectrum(delta: float) -> void:
	var channels := _channel_levels()
	var channel_drive := (channels[0] + channels[1] + channels[2] + channels[3]) * 0.25
	var music_active := MusicManager.is_any_music_playing()
	var music_bus := AudioServer.get_bus_index("Music")
	var bus_drive := 0.0
	if music_bus >= 0 and music_active:
		var peak_db := maxf(AudioServer.get_bus_peak_volume_left_db(music_bus, 0),
			AudioServer.get_bus_peak_volume_right_db(music_bus, 0))
		bus_drive = clampf(db_to_linear(peak_db) * _gain * 1.8, 0.0, 1.0)
	for index in MAX_BANDS:
		var lo := 42.0 * pow(11000.0 / 42.0, float(index) / MAX_BANDS)
		var hi := 42.0 * pow(11000.0 / 42.0, float(index + 1) / MAX_BANDS)
		var target := 0.0
		if _analyzer != null and music_active:
			var magnitude := _analyzer.get_magnitude_for_frequency_range(lo, hi,
				AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
			target = clampf(sqrt(maxf(magnitude.x, magnitude.y)) * 3.8 * _gain, 0.0, 1.0)
		# Treiber-/Headless-Fallback: echte MOD-Kanalpegel beziehungsweise der
		# gemessene Music-Bus-Peak. Auch der Fallback bleibt damit audiogetrieben.
		var measured_fallback := channels[index % 4] * _gain if MusicManager.is_playing() else bus_drive
		measured_fallback *= 0.48 + 0.52 * absf(sin(index * 1.71 + _t * 0.8))
		target = maxf(target, clampf(measured_fallback * 0.82, 0.0, 1.0))
		var response := 18.0 if target > _spectrum[index] else lerpf(13.0, 2.2, _decay)
		_spectrum[index] = lerpf(_spectrum[index], target, 1.0 - exp(-delta * response))
		if _spectrum[index] >= _peaks[index]:
			_peaks[index] = _spectrum[index]
			_peak_timers[index] = 0.38 + _decay * 0.42
		else:
			_peak_timers[index] -= delta
			if _peak_timers[index] <= 0.0:
				_peaks[index] = move_toward(_peaks[index], _spectrum[index], delta * lerpf(1.8, 0.48, _decay))
	var bass := (_spectrum[0] + _spectrum[1] + _spectrum[2] + channel_drive) * 0.25
	_bass_floor = lerpf(_bass_floor, bass, 1.0 - exp(-delta * 1.8))
	if bass > _bass_floor * 1.34 + 0.035:
		_beat = 1.0
	else:
		_beat = maxf(0.0, _beat - delta * 4.8)


func visual_contract() -> Dictionary:
	return {"renderer": "scene_animator", "fft_bands": MAX_BANDS,
		"inputs": [&"music_bus_fft", &"mod_channel_levels", &"pattern", &"row", &"bpm", &"beat"],
		"presets": [&"equalizer", &"mirror", &"copper", &"starfield", &"raster", &"waterfall",
			&"vu", &"dots", &"vector", &"skyline", &"tunnel", &"bobs", &"plasma", &"scope",
			&"sinebars", &"chroma", &"ham_ribbons", &"sprite_multiplex", &"parallax",
			&"metaballs", &"firestorm", &"texture_tunnel", &"voxel_city", &"particle_logo"],
		"controls": [&"gain", &"decay", &"peak_hold", &"band_count", &"palette"],
		"music_sources": [&"location", &"amiga", &"preview", &"title", &"external"],
		"semantic_status": [&"scene_rank", &"scene_respect", &"computer_model",
			&"chipset_generation", &"hardware_performance", &"campaign_year",
			&"music_context"],
		"generation_backdrops": [&"ocs", &"ecs", &"aga"],
		"aga_contract": {"native_presets": 10, "color_registers": 256,
			"palette_bits": 24, "bitplanes": 8, "ham": "HAM8"},
		"backward_compatible_modes": true,
		"clipped_to_season_frame": clip_contents, "separate_from_notebook_strip": true}


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	# Mehrlagiger dunkler Signalgrund. Alles bleibt im geclippten Saisonpanel.
	for band in 8:
		var f := float(band) / 7.0
		draw_rect(Rect2(0, size.y * f, size.x, size.y / 7.0 + 1.0),
			Color("050913").lerp(Color("12213a"), f))
	var status := _scene_status()
	_draw_generation_backdrop(str(status.get("generation", "ocs")))
	var specialized := false
	match effect:
		"mirror": specialized = true; _draw_mirror_spectrum()
		"starfield": _draw_starfield()
		"raster": _draw_rasterwave()
		"waterfall": specialized = true; _draw_waterfall()
		"vu": specialized = true; _draw_vu_rack()
		"dots": specialized = true; _draw_dot_matrix()
		"vector": _draw_vectorgrid()
		"skyline": specialized = true; _draw_skyline()
		"tunnel": _draw_beat_tunnel()
		"bobs": _draw_bobs()
		"plasma": _draw_plasma()
		"scope": _draw_scope()
		"sinebars": specialized = true; _draw_ecs_sinebars()
		"chroma": specialized = true; _draw_aga_chroma()
		"ham_ribbons": specialized = true; _draw_aga_ham_ribbons()
		"sprite_multiplex": specialized = true; _draw_aga_sprite_multiplex()
		"parallax": specialized = true; _draw_aga_parallax()
		"metaballs": specialized = true; _draw_aga_metaballs()
		"firestorm": specialized = true; _draw_aga_firestorm()
		"texture_tunnel": specialized = true; _draw_aga_texture_tunnel()
		"voxel_city": specialized = true; _draw_aga_voxel_city()
		"particle_logo": specialized = true; _draw_aga_particle_logo()
		"copper": _draw_copper()
		_: pass # eigener vertikaler 24-Band-Equalizer, keine Kopie des Notiz-Coppers
	if not specialized:
		_draw_spectrum()
	var state := _presentation_state()
	if str(_primary_presentation(state, status).get("kind", "idle")) != "idle":
		_draw_generation_accents(str(status.get("chipset", "OCS")))
	_draw_pattern_clock()
	_draw_board_titles()
	_draw_frame()


func _draw_generation_backdrop(generation_id: String) -> void:
	var texture: Texture2D = _backdrops.get(generation_id)
	if texture == null:
		var path := str(SceneCatalog.generation(generation_id).get("backdrop", ""))
		texture = load(path) as Texture2D if not path.is_empty() else null
		if texture != null:
			_backdrops[generation_id] = texture
	if texture == null:
		return
	var alpha := float({"ocs": 0.30, "ecs": 0.34, "aga": 0.38}.get(generation_id, 0.30))
	draw_texture_rect(texture, Rect2(3, 3, size.x - 6, size.y - 6), false,
		Color(1.0, 1.0, 1.0, alpha))
	# Eine sehr leichte Glaslasur bindet das Asset an die prozeduralen FFT-Layer,
	# ohne die generierte Pixelstruktur oder die Laufzeitschrift zu verschlucken.
	draw_rect(Rect2(3, 3, size.x - 6, size.y - 6), Color(0.01, 0.02, 0.05, 0.16))


func _draw_spectrum() -> void:
	# Fast die komplette Glasfläche nutzen; nur drei Pixel Sicherheitsrand bleiben
	# für den technischen Rahmen. Titel und Metadaten liegen als lesbare Platten
	# darüber, deshalb dürfen die Bänder dahinter bis oben ausschlagen.
	var inner := Rect2(3, 3, size.x - 6, size.y - 6)
	var gap := 1.0
	var width := (inner.size.x - gap * (_visible_bands - 1)) / _visible_bands
	for index in _visible_bands:
		var value := _band_value(index, _visible_bands)
		var peak := _band_peak(index, _visible_bands)
		var idle := 0.10 + 0.10 * (sin(index * 1.73 + _t * 0.55) * 0.5 + 0.5) \
			if not MusicManager.is_any_music_playing() else 0.0
		var height := 2.0 + maxf(value, idle) * inner.size.y * 0.94
		var x := inner.position.x + index * (width + gap)
		var color := _band_color(float(index) / maxf(1.0, _visible_bands - 1.0))
		draw_rect(Rect2(x, inner.end.y - height, maxf(1.0, width), height), Color(color, 0.18 + value * 0.48))
		if value > 0.12:
			draw_rect(Rect2(x, inner.end.y - height, maxf(1.0, width), 1.0), Color(color, 0.82))
		if _show_peaks and peak > 0.06:
			var py := inner.end.y - 2.0 - peak * inner.size.y * 0.90
			draw_rect(Rect2(x, py, maxf(1.0, width), 1.0), Color(color, 0.88))


func _draw_pattern_clock() -> void:
	if not MusicManager.is_playing():
		return
	var view: Dictionary = MusicManager.native_player().playback_view(1)
	var row := int(view.get("row", 0))
	for marker in 16:
		var active := marker == posmod(int(row / 4.0), 16)
		var x := 7.0 + marker * (size.x - 14.0) / 16.0
		draw_rect(Rect2(x, 3, 2 if active else 1, 3 + _beat * 2.0),
			Color8(255, 218, 92) if active else Color(0.35, 0.58, 0.68, 0.38))


func _draw_board_titles() -> void:
	var display := display_snapshot(size.x - 8.0)
	var main := str(display.get("main", caption))
	var meta := str(display.get("meta", _effect_label(effect)))
	var main_size := int(display.get("main_font_size", clampi(int(size.y * 0.40), 16, 25)))
	var main_y := clampf(size.y * 0.49, main_size + 2.0, size.y - 15.0)
	# Keine gefüllte Titelplatte: Spektrum/Copper bleiben hinter dem großen
	# Titel sichtbar. Der dezente Textschatten übernimmt allein die Lesbarkeit.
	_draw_primary_title(main, main_y, main_size,
		float(display.get("main_scale_x", 1.0)), int(display.get("animation_tier", 1)),
		str(display.get("chipset", "OCS")))
	# Eigene Meta-Zeile mit garantierter Safe-Baseline; kein abgeschnittener Text.
	draw_rect(Rect2(3, size.y - 14, size.x - 6, 11), Color(0.01, 0.02, 0.04, 0.70))
	draw_string(_font, Vector2(2, size.y - 4), meta, HORIZONTAL_ALIGNMENT_CENTER,
		size.x - 4, 10, Color(0.78, 0.94, 0.97, 0.96))


## Liefert genau die Texte, die im Saisonpanel gezeichnet werden. Der Snapshot
## Zustandspriorität der großen Hauptzeile:
## 1. gestartetes Amiga-Spiel (auch bei Pause/Stumm), 2. laufender Song mit
## vollständigem Katalogtitel + Künstler, 3. SOMMER 'xx bei Stop/Leerlauf.
## Der Szene-Rang bleibt bewusst nur eine sekundäre Statusinformation.
func display_snapshot(available_width: float = -1.0, state_override: Dictionary = {}) -> Dictionary:
	var status := _scene_status()
	var state: Dictionary = state_override if not state_override.is_empty() \
		else _presentation_state()
	var primary := _primary_presentation(state, status)
	var main := str(primary.get("text", Loc.t(
		"scene.presentation.season_year", "SOMMER '90")))
	var meta_parts: Array[String] = [
		Loc.t_format("scene.presentation.build", "AUSBAU %d",
			[int(status.get("upgrade_level", 1))]),
		str(status.get("chipset", "OCS")),
		str(status.get("machine", "A500")),
		"'%02d" % (int(status.get("year", 1990)) % 100),
		Loc.t_format("scene.presentation.scene_rank", "SZENE %s",
			[str(status.get("rank", "BEDROOM CODER"))]),
	]
	if alert:
		var count := maxi(1, UIManager.notebook_attention_count)
		meta_parts.push_front(Loc.t_format(
			"scene.presentation.new_entry.one" if count == 1 \
			else "scene.presentation.new_entry.many",
			"%d NEUER EINTRAG" if count == 1 else "%d NEUE EINTRÄGE", [count]))
	if str(primary.get("kind", "idle")) == "game":
		meta_parts.append(Loc.t("scene.presentation.amiga_game", "AMIGA-SPIEL"))
	elif bool(state.get("playing", false)):
		meta_parts.append(_music_technical_summary(state))
	else:
		meta_parts.append(_effect_label(effect))
	var max_width := available_width if available_width > 0.0 else maxf(120.0, size.x - 8.0)
	# Der ruhige Jahresbanner bleibt auch mit späterer Hardware so erhalten wie
	# in den frühen Sommern. Nur ein tatsächlich laufender Song oder ein
	# geöffnetes Spiel schaltet die freigespielten Scene-Bewegungen frei.
	var animation_tier := 0 if str(primary.get("kind", "idle")) == "idle" \
		else clampi(int(status.get("upgrade_level", 1)), 1, 4)
	var title_layout := _title_layout(main, max_width, animation_tier)
	var motion := title_motion_profile(animation_tier, str(status.get("chipset", "OCS")))
	var raw_meta := " · ".join(meta_parts)
	return {
		# Die Hauptzeile wird nie ellipsiert. Bei ungewöhnlich langen MOD-Titeln
		# sinkt zuerst die Schriftgröße und erst danach die horizontale Skalierung.
		"main": main,
		"main_font_size": title_layout.get("font_size", 25),
		"main_scale_x": title_layout.get("scale_x", 1.0),
		"main_kind": primary.get("kind", "idle"),
		"presentation_mode": str(motion.get("id", "static")),
		"animation_tier": animation_tier,
		"meta": _fit_text(raw_meta, max_width, 10),
		"raw_main": main,
		"raw_meta": raw_meta,
		"tooltip": _status_tooltip(status, state),
		"rank": status.get("rank", ""),
		"respect": status.get("respect", 0),
		"chipset": status.get("chipset", ""),
		"native_chipset": status.get("native_chipset", ""),
		"generation": status.get("generation", "ocs"),
		"native_generation": status.get("native_generation", "ocs"),
		"machine": status.get("machine", ""),
		"upgrade_level": status.get("upgrade_level", 1),
		"cpu": status.get("cpu", ""),
		"performance_multiplier": status.get("performance_multiplier", 1.0),
		"io_speed_multiplier": status.get("io_speed_multiplier", 1.0),
		"motion": motion,
		"generation_fx": generation_visual_profile(str(status.get("chipset", "OCS"))),
	}


func status_tooltip() -> String:
	return str(display_snapshot(maxf(120.0, size.x - 8.0)).get("tooltip", ""))


func _presentation_state() -> Dictionary:
	return presentation_override.duplicate(true) if not presentation_override.is_empty() \
		else MusicManager.presentation_state()


func _scene_status() -> Dictionary:
	var rank: Dictionary = DemoManager.scene_rank()
	var model := str(PlayerStats.hardware.get("computer_model", "amiga_500"))
	var machine: String = str({
		"amiga_500": "A500",
		"amiga_500_plus": "A500+",
		"amiga_600": "A600",
		"amiga_1200": "A1200",
		"amiga_2000": "A2000",
	}.get(model, model.replace("amiga_", "A").to_upper()))
	var native_generation := SceneCatalog.native_generation(model, PlayerStats.hardware)
	var generation := SceneCatalog.effective_generation("", native_generation)
	var chipset := str(SceneCatalog.generation(generation).get("chipset", "OCS"))
	var base_chipset := str(SceneCatalog.generation(native_generation).get("chipset", "OCS"))
	var ram: Dictionary = PlayerStats.ram_breakdown()
	var performance := PlayerStats.performance_profile()
	return {
		"rank": str(rank.get("name", "BEDROOM CODER")),
		"respect": DemoManager.scene_respect(),
		"year": TimeManager.year,
		"machine": str(machine),
		"chipset": chipset,
		"native_chipset": base_chipset,
		"generation": generation,
		"native_generation": native_generation,
		"ram_kb": int(ram.get("total_kb", 512)),
		"upgrade_level": PlayerStats.hardware_level(),
		"cpu": str(performance.get("cpu", PlayerStats.cpu_description())),
		"performance_multiplier": float(performance.get("performance_multiplier", 1.0)),
		"io_speed_multiplier": float(performance.get("io_speed_multiplier", 1.0)),
	}


func active_chipset() -> String:
	return str(_scene_status().get("chipset", "OCS"))


func active_generation() -> String:
	return str(_scene_status().get("generation", "ocs"))


func native_chipset() -> String:
	return str(_scene_status().get("native_chipset", "OCS"))


## Sichtbarer Generationsvertrag des Saisonpanels. Der A600 ist kein schnellerer
## 68000er, erhält aber durch ECS und sein serienmäßiges Chip-RAM eine eigene
## Scroller-/Rasterstufe; der A1200 setzt mit AGA und 68020 deutlich darüber an.
func generation_visual_profile(chipset: String) -> Dictionary:
	return Presentation.generation_visual_profile(chipset)


func _primary_presentation(state: Dictionary, status: Dictionary) -> Dictionary:
	return Presentation.primary_presentation(state, status)


func _music_technical_summary(state: Dictionary) -> String:
	return Presentation.music_technical_summary(state)


func _title_layout(text: String, max_width: float, upgrade_level: int) -> Dictionary:
	# Bei laufendem Signal (Tier >= 1) scrollt der vollständige Titel durch die
	# geclippte Fläche. Nur die ruhige Jahreskarte (Tier 0) wird eingepasst.
	if upgrade_level >= 1:
		return {"font_size": 25, "scale_x": 1.0}
	var usable_width := maxf(1.0, max_width)
	for font_size in range(25, 12, -1):
		var measured := _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if measured <= usable_width:
			return {"font_size": font_size, "scale_x": 1.0}
	var fallback_size := 12
	var fallback_width := maxf(1.0, _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fallback_size).x)
	return {"font_size": fallback_size,
		"scale_x": clampf(usable_width / fallback_width, 0.20, 1.0)}


## Ausbau 1 ist bewusst eine völlig ruhige Titelkarte. Danach kommen stufenweise
## typische, aber weiterhin lesbare Scene-Intro-Bewegungen hinzu.
func title_motion_profile(upgrade_level: int, chipset := "OCS") -> Dictionary:
	return Presentation.title_motion_profile(upgrade_level, chipset)


func _draw_primary_title(text: String, baseline: float, font_size: int,
		scale_x: float, upgrade_level: int, chipset: String) -> void:
	var profile := title_motion_profile(upgrade_level, chipset)
	if bool(SettingsManager.value("reduced_motion")):
		profile = title_motion_profile(0)
		var static_layout := _title_layout(text, maxf(1.0, size.x - 8.0), 0)
		font_size = int(static_layout.get("font_size", font_size))
		scale_x = float(static_layout.get("scale_x", scale_x))
	var color := Color8(255, 218, 92)
	if upgrade_level >= 2:
		var shimmer := sin(_t * 1.7) * 0.5 + 0.5
		color = color.lerp(Color8(85, 226, 228), shimmer * minf(0.34, 0.08 * upgrade_level))
	var profile_id := str(profile.get("id", "static"))
	if profile_id != "static":
		_draw_scrolling_title(text, baseline, font_size, color, profile)
		return
	var trails := int(profile.get("trails", 0))
	for trail in range(trails, 0, -1):
		var ghost := Color(0.16, 0.78, 0.88, 0.18 / float(trail))
		_draw_centered_scaled(text, baseline + trail, font_size, ghost,
			-trail * 2.0, scale_x)
	_draw_centered_scaled(text, baseline + 2.0, font_size, Color(0, 0, 0, 0.88),
		0.0, scale_x)
	_draw_centered_scaled(text, baseline, font_size, color, 0.0, scale_x)


func _draw_centered_scaled(text: String, baseline: float, font_size: int,
		color: Color, offset_x: float, scale_x: float) -> void:
	var text_width := _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(size.x * 0.5 + offset_x - text_width * scale_x * 0.5, 0.0)
	draw_set_transform(origin, 0.0, Vector2(scale_x, 1.0))
	draw_string(_font, Vector2(0.0, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_scrolling_title(text: String, baseline: float, font_size: int,
		color: Color, profile: Dictionary) -> void:
	var total_width := _font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var gap := maxf(52.0, size.x * 0.14)
	var cycle := maxf(1.0, total_width + gap)
	var first_x := -fposmod(_t * float(profile.get("speed", 26.0)), cycle)
	var x := first_x
	while x < size.x:
		_draw_scroller_copy(text, x, baseline, font_size, color, profile)
		x += cycle


func _draw_scroller_copy(text: String, start_x: float, baseline: float,
		font_size: int, color: Color, profile: Dictionary) -> void:
	var x := start_x
	var wave := float(profile.get("wave", 0.0))
	var wave_secondary := float(profile.get("wave_secondary", 0.0))
	var beat_wave := float(profile.get("beat_wave", 0.0))
	var trails := int(profile.get("trails", 0))
	var chroma := bool(profile.get("chroma", false))
	for index in text.length():
		var glyph := text.substr(index, 1)
		var glyph_width := _font.get_string_size(
			glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var y := baseline + sin(_t * 2.5 + index * 0.42) * (wave + _beat * beat_wave) \
			+ sin(_t * 1.3 - index * 0.23) * wave_secondary
		for trail in range(trails, 0, -1):
			var trail_color := Color(0.16, 0.78, 0.88, 0.16 / float(trail))
			if chroma:
				trail_color = Color(
					0.95 if trail % 2 == 0 else 0.18,
					0.22 if trail % 2 == 0 else 0.82,
					0.66 if trail % 2 == 0 else 1.0,
					0.19 / float(trail))
			draw_string(_font, Vector2(x - trail * 1.5, y + trail), glyph,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				trail_color)
		draw_string(_font, Vector2(x, y + 2.0), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.82))
		var glyph_color := color
		if chroma:
			glyph_color = _band_color(fposmod(float(index) * 0.075 + _t * 0.06, 1.0)).lerp(color, 0.38)
		draw_string(_font, Vector2(x, y), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glyph_color)
		x += glyph_width


func _status_tooltip(status: Dictionary, state: Dictionary) -> String:
	var lines: Array[String] = [
		Loc.t("scene.status.title", "SZENENSTATUS"),
		Loc.t_format("scene.status.rank", "Rang: %s · Szenenruf %d/100", [
			str(status.get("rank", "BEDROOM CODER")), int(status.get("respect", 0))]),
		Loc.t_format("scene.status.machine", "Rechner: %s · nativ %s · %d KB RAM", [
			str(status.get("machine", "A500")), str(status.get("native_chipset", "OCS")),
			int(status.get("ram_kb", 512))]),
		Loc.t_format("scene.status.cpu", "CPU: %s · System %.2fx · I/O %.2fx", [
			str(status.get("cpu", "MC68000")),
			float(status.get("performance_multiplier", 1.0)),
			float(status.get("io_speed_multiplier", 1.0))]),
		Loc.t_format("scene.status.mode", "Szenenmodus: %s%s", [
			str(status.get("chipset", "OCS")),
			Loc.t("scene.status.backward_compatible", " · ABWÄRTSKOMPATIBEL") \
			if status.get("chipset") != status.get("native_chipset") else ""]),
		Loc.t_format("scene.status.visual", "Visual: %s", [_effect_label(effect)]),
	]
	if bool(state.get("playing", false)):
		var original_title := str(state.get("title", "")).strip_edges()
		var artist := str(state.get("artist", "")).strip_edges()
		var track_line := Loc.t_format("scene.status.audio", "Audio: %s", [
			original_title if original_title != "" else Loc.t(
				"scene.presentation.mod_signal", "MOD-Signal")])
		if artist != "":
			track_line += " · %s" % artist
		lines.append(track_line)
		var source := str(state.get("source_label", "")).strip_edges()
		if source != "":
			lines.append(Loc.t_format("scene.status.source", "Quelle: %s", [source]))
		if bool(state.get("tracker", false)):
			var player: ModPlayer = MusicManager.native_player()
			var view: Dictionary = player.playback_view(1) if player != null else {}
			lines.append(Loc.t_format("scene.status.tracker",
				"Tracker: Position %d · Zeile %d · %d BPM · vier Kanäle", [
				int(view.get("order", 0)), int(view.get("row", 0)), int(view.get("bpm", 125))]))
	return "\n".join(lines)


func _fit_text(value: String, max_width: float, font_size: int) -> String:
	if _font == null or max_width <= 1.0:
		return ""
	if _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return value
	const SUFFIX := "..."
	var suffix_width := _font.get_string_size(SUFFIX, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if suffix_width >= max_width:
		return ""
	var result := value
	while result.length() > 0:
		result = result.left(result.length() - 1).strip_edges()
		if _font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + suffix_width <= max_width:
			return result + SUFFIX
	return SUFFIX


func _draw_frame() -> void:
	var pulse := 0.35 + _beat * 0.65
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(0.20, 0.68, 0.78, 0.48 + pulse * 0.18), false, 1.0)
	# Vier technische Corner-Brackets, keine fremde Animation ober-/unterhalb.
	var c := Color(1.0, 0.70, 0.20, 0.55 + pulse * 0.35)
	for corner in [Vector2(2, 2), Vector2(size.x - 2, 2), Vector2(2, size.y - 2), Vector2(size.x - 2, size.y - 2)]:
		var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
		draw_line(corner, corner + Vector2(sx * 9, 0), c, 2.0)
		draw_line(corner, corner + Vector2(0, sy * 7), c, 2.0)
	if alert:
		for side in 2:
			var x := 5.0 if side == 0 else size.x - 9.0
			draw_circle(Vector2(x, size.y * 0.5), 2.5 + _beat * 1.5, Color8(255, 210, 70))


func _band_value(index: int, count: int) -> float:
	return _collapsed_value(_spectrum, index, count)


func _band_peak(index: int, count: int) -> float:
	return _collapsed_value(_peaks, index, count)


func _collapsed_value(values: Array, index: int, count: int) -> float:
	var first := clampi(floori(float(index) * MAX_BANDS / count), 0, MAX_BANDS - 1)
	var last := clampi(ceili(float(index + 1) * MAX_BANDS / count), first + 1, MAX_BANDS)
	var total := 0.0
	for source_index in range(first, last):
		total += float(values[source_index])
	return total / maxf(1.0, last - first)


func _band_color(f: float) -> Color:
	var colors: Array[Color]
	match _palette_id:
		"ice": colors = [Color8(38, 118, 224), Color8(60, 219, 236), Color8(225, 251, 255)]
		"phosphor": colors = [Color8(18, 103, 55), Color8(62, 224, 88), Color8(231, 255, 111)]
		"candy": colors = [Color8(240, 54, 151), Color8(125, 74, 232), Color8(48, 224, 224)]
		_: colors = [Color8(38, 199, 222), Color8(238, 76, 151), Color8(250, 168, 36)]
	if f <= 0.5:
		return colors[0].lerp(colors[1], f * 2.0)
	return colors[1].lerp(colors[2], (f - 0.5) * 2.0)


## Symmetrisches Spektrum um eine gemeinsame Mittellinie. Die niedrigen
## Frequenzen liegen innen und schlagen nach oben und unten aus.
func _draw_mirror_spectrum() -> void:
	var inner := Rect2(3, 3, size.x - 6, size.y - 6)
	var mid := inner.position.y + inner.size.y * 0.52
	var width := inner.size.x / _visible_bands
	draw_line(Vector2(inner.position.x, mid), Vector2(inner.end.x, mid), Color(0.52, 0.86, 0.92, 0.28), 1.0)
	for index in _visible_bands:
		var value := _band_value(index, _visible_bands)
		if not MusicManager.is_any_music_playing():
			value = 0.08 + 0.06 * absf(sin(_t * 0.8 + index * 1.31))
		var height := 1.0 + value * inner.size.y * 0.43
		var x := inner.position.x + index * width
		var color := _band_color(float(index) / maxf(1.0, _visible_bands - 1.0))
		draw_rect(Rect2(x + 0.5, mid - height, maxf(1.0, width - 1.0), height * 2.0), Color(color, 0.28 + value * 0.46))
		if _show_peaks:
			var peak_height := _band_peak(index, _visible_bands) * inner.size.y * 0.43
			draw_rect(Rect2(x + 0.5, mid - peak_height, maxf(1.0, width - 1.0), 1.0), Color(color, 0.85))
			draw_rect(Rect2(x + 0.5, mid + peak_height, maxf(1.0, width - 1.0), 1.0), Color(color, 0.85))


## Zehn zeitlich versetzte FFT-Zeilen ergeben ein echtes Spektrogramm statt
## einer unabhaengigen Dekor-Animation.
func _draw_waterfall() -> void:
	var rows := maxi(1, _history.size())
	var cell_w := (size.x - 6.0) / _visible_bands
	var cell_h := (size.y - 6.0) / 10.0
	for row in mini(rows, 10):
		var sample: Array = _spectrum if _history.is_empty() else _history[row]
		for index in _visible_bands:
			var value := _collapsed_value(sample, index, _visible_bands)
			var color := _band_color(float(index) / maxf(1.0, _visible_bands - 1.0))
			var alpha := 0.04 + value * (0.75 - row * 0.045)
			draw_rect(Rect2(3.0 + index * cell_w, 3.0 + row * cell_h,
				maxf(1.0, cell_w - 0.6), maxf(1.0, cell_h - 0.6)), Color(color, alpha))


func _draw_vu_rack() -> void:
	var levels := _channel_levels()
	if not MusicManager.is_playing():
		for channel in 4:
			var sum := 0.0
			for index in range(channel * 8, channel * 8 + 8):
				sum += _spectrum[index]
			levels[channel] = sum / 8.0
	var lane_h := (size.y - 8.0) / 4.0
	for channel in 4:
		var y := 4.0 + channel * lane_h
		var color := _band_color(float(channel) / 3.0)
		draw_rect(Rect2(5, y, size.x - 10, lane_h - 2), Color(0.01, 0.03, 0.05, 0.62))
		var segments := 22
		for segment in segments:
			var lit := float(segment + 1) / segments <= levels[channel]
			var x := 7.0 + segment * (size.x - 14.0) / segments
			draw_rect(Rect2(x, y + 2, maxf(1.0, (size.x - 14.0) / segments - 1.0), lane_h - 6),
				Color(color, 0.78 if lit else 0.09))


func _draw_dot_matrix() -> void:
	var rows := 9
	var cell_w := (size.x - 6.0) / _visible_bands
	var cell_h := (size.y - 6.0) / rows
	for index in _visible_bands:
		var value := _band_value(index, _visible_bands)
		if not MusicManager.is_any_music_playing():
			value = 0.06 + 0.06 * absf(sin(index * 0.9 + _t))
		var lit_rows := ceili(value * rows)
		var color := _band_color(float(index) / maxf(1.0, _visible_bands - 1.0))
		for row in rows:
			var center := Vector2(3.0 + (index + 0.5) * cell_w, size.y - 3.0 - (row + 0.5) * cell_h)
			var lit := row < lit_rows
			draw_circle(center, maxf(0.7, minf(cell_w, cell_h) * 0.28), Color(color, 0.82 if lit else 0.08))


func _draw_skyline() -> void:
	var buildings := mini(_visible_bands, 24)
	var width := (size.x - 6.0) / buildings
	for index in buildings:
		var value := _band_value(index, buildings)
		var idle := 0.12 + 0.08 * absf(sin(index * 2.1 + _t * 0.4))
		var height := 6.0 + maxf(value, idle) * (size.y - 12.0)
		var x := 3.0 + index * width
		var color := _band_color(float(index) / maxf(1.0, buildings - 1.0))
		draw_rect(Rect2(x + 0.5, size.y - 3.0 - height, maxf(2.0, width - 1.0), height), Color(color.darkened(0.58), 0.82))
		for window_y in range(int(size.y - 7.0 - height), int(size.y - 6.0), 5):
			if posmod(index * 7 + window_y, 3) != 0:
				draw_rect(Rect2(x + 2.0, window_y, 1.0, 1.0), Color(color, 0.58 + _beat * 0.28))


func _draw_beat_tunnel() -> void:
	var center := size * 0.5
	var drive := clampf((_spectrum[0] + _spectrum[1] + _spectrum[2] + _beat) * 0.25, 0.0, 1.0)
	for ring in 11:
		var phase := fposmod(float(ring) / 11.0 + _t * (0.06 + drive * 0.13), 1.0)
		var extent := Vector2(size.x * 0.48, size.y * 0.46) * pow(phase, 1.55)
		var wobble := Vector2(sin(_t * 1.4 + ring) * drive * 5.0, cos(_t + ring * 0.7) * drive * 2.0)
		var color := _band_color(phase)
		draw_rect(Rect2(center + wobble - extent, extent * 2.0), Color(color, 0.12 + phase * 0.34), false, 1.0)


## ECS-Preset: mehrere audiogetriebene, diskret abgetastete Sinusbänder. Der
## 68000 bleibt derselbe wie im A500; sichtbar mehr Spielraum kommt aus ECS und
## dem serienmäßigen 1 MB Chip-RAM, nicht aus erfundener CPU-Beschleunigung.
func _draw_ecs_sinebars() -> void:
	var step := 5
	for ribbon in 7:
		var points := PackedVector2Array()
		var center_y := 7.0 + ribbon * (size.y - 14.0) / 6.0
		for x in range(-step, ceili(size.x) + step, step):
			var band := clampi(floori(float(maxi(0, x)) / maxf(1.0, size.x) * MAX_BANDS),
				0, MAX_BANDS - 1)
			var drive := _spectrum[band]
			var amplitude := 1.6 + drive * 5.5 + _beat * 1.2
			var y := center_y + sin(float(x) * 0.035 + _t * 2.1 + ribbon * 0.72) * amplitude
			points.append(Vector2(x, roundf(y)))
		var color := _band_color(float(ribbon) / 6.0)
		draw_polyline(points, Color(color, 0.20 + float(ribbon % 2) * 0.10),
			2.0 if ribbon % 3 == 0 else 1.0)


## AGA-Preset: feineres 24-Bit-Chromafeld plus breite Dual-Sinus-Ribbons. Es
## bleibt ein musikgetriebener Scene-Effekt und kein modernes Zufallsrauschen.
func _draw_aga_chroma() -> void:
	var cols := 36
	var rows := 9
	var cell_w := (size.x - 6.0) / cols
	var cell_h := (size.y - 6.0) / rows
	for row in rows:
		for column in cols:
			var band := clampi(floori(float(column) / cols * MAX_BANDS), 0, MAX_BANDS - 1)
			var drive := _spectrum[band]
			var phase := sin(column * 0.31 + _t * 1.8) \
				+ cos(row * 0.73 - _t * 1.15) + drive * 2.4
			var hue := fposmod(float(column) / cols * 0.72 + float(row) * 0.035
				+ _t * 0.025 + phase * 0.035, 1.0)
			var color := Color.from_hsv(hue, 0.72, 0.88)
			draw_rect(Rect2(3.0 + column * cell_w, 3.0 + row * cell_h,
				cell_w + 0.5, cell_h + 0.5), Color(color, 0.12 + drive * 0.30))
	for ribbon in 3:
		var points := PackedVector2Array()
		for x in range(0, ceili(size.x) + 4, 4):
			var y := size.y * (0.30 + ribbon * 0.20) \
				+ sin(x * 0.027 + _t * (1.7 + ribbon * 0.18)) * (3.5 + _beat * 2.0) \
				+ cos(x * 0.011 - _t * 1.2) * 2.0
			points.append(Vector2(x, roundf(y)))
		draw_polyline(points, Color(Color.from_hsv(
				fposmod(_t * 0.035 + ribbon * 0.24, 1.0), 0.78, 1.0), 0.52), 1.0)


## HAM8 wird nicht als moderner Blur imitiert: diskrete Farbstreifen bilden
## acht breite, ineinander greifende Audiowellen. Segmentweise Farbaenderung
## macht die sichtbar groessere AGA-Palette unmittelbar lesbar.
func _draw_aga_ham_ribbons() -> void:
	var segments := 72
	var segment_w := size.x / float(segments)
	for ribbon in 8:
		var center_y := size.y * (0.13 + ribbon * 0.105)
		var band_offset := ribbon * 4
		for segment in segments:
			var x0 := float(segment) * segment_w
			var x1 := float(segment + 1) * segment_w + 0.5
			var band := (segment + band_offset) % MAX_BANDS
			var drive := _spectrum[band]
			var amplitude := 2.0 + drive * 8.0 + _beat * 1.8
			var phase0 := x0 * 0.024 + _t * (1.25 + ribbon * 0.07) + ribbon * 0.71
			var phase1 := x1 * 0.024 + _t * (1.25 + ribbon * 0.07) + ribbon * 0.71
			var y0 := center_y + sin(phase0) * amplitude + cos(phase0 * 0.43) * 1.8
			var y1 := center_y + sin(phase1) * amplitude + cos(phase1 * 0.43) * 1.8
			var thickness := 2.0 + drive * 3.5
			var quad := PackedVector2Array([
				Vector2(x0, y0 - thickness), Vector2(x1, y1 - thickness),
				Vector2(x1, y1 + thickness), Vector2(x0, y0 + thickness)])
			var hue := fposmod(float(segment) / segments * 0.82 + ribbon * 0.09 + _t * 0.018, 1.0)
			draw_colored_polygon(quad, Color(Color.from_hsv(hue, 0.76, 1.0), 0.18 + drive * 0.34))


## AGA-Sprites duerfen breiter sein und werden in einer Scene typischerweise
## per Multiplexing mehrfach eingesetzt. Hier laufen 48 klar abgegrenzte,
## musikgetriebene Sprite-Symbole in acht Rasterbahnen.
func _draw_aga_sprite_multiplex() -> void:
	for lane in 8:
		var y := 10.0 + lane * (size.y - 20.0) / 7.0
		draw_line(Vector2(3, y), Vector2(size.x - 3, y), Color(0.22, 0.66, 0.84, 0.07), 1.0)
	for sprite_index in 48:
		var lane := sprite_index % 8
		var band := sprite_index % MAX_BANDS
		var drive := _spectrum[band]
		var speed := 18.0 + lane * 4.0 + drive * 22.0
		var x := fposmod(sprite_index * 71.0 + _t * speed, size.x + 36.0) - 18.0
		var y := 10.0 + lane * (size.y - 20.0) / 7.0
		y += sin(_t * 2.0 + sprite_index * 0.63) * (1.2 + drive * 3.4)
		var radius := 2.2 + float(sprite_index % 3) + drive * 3.0
		var shape := PackedVector2Array([
			Vector2(x, y - radius), Vector2(x + radius * 1.55, y),
			Vector2(x, y + radius), Vector2(x - radius * 1.55, y)])
		var hue := fposmod(float(lane) / 8.0 + _t * 0.025, 1.0)
		var color := Color.from_hsv(hue, 0.74, 1.0)
		draw_colored_polygon(shape, Color(color, 0.34 + drive * 0.50))
		draw_polyline(PackedVector2Array([shape[0], shape[1], shape[2], shape[3], shape[0]]),
			Color(1.0, 1.0, 1.0, 0.20 + drive * 0.38), 1.0)


## Vier getrennte Tiefenebenen mit eigener Geschwindigkeit. Nebelwolken,
## Sternpartikel und Horizontlinien vermitteln mehr Raum als das OCS-Sternfeld.
func _draw_aga_parallax() -> void:
	for cloud in 9:
		var cloud_x := fposmod(cloud * 139.0 - _t * (5.0 + cloud % 3), size.x + 100.0) - 50.0
		var cloud_y := 15.0 + posmod(cloud * 29, maxi(1, int(size.y - 30.0)))
		var cloud_color := Color.from_hsv(fposmod(0.55 + cloud * 0.047 + _t * 0.004, 1.0), 0.68, 0.82)
		draw_circle(Vector2(cloud_x, cloud_y), 14.0 + cloud % 4 * 5.0,
			Color(cloud_color, 0.025 + _beat * 0.018))
	for layer in 4:
		var star_count := 15 + layer * 7
		for star in star_count:
			var speed := 8.0 + layer * 12.0
			var x := fposmod(star * (83.0 + layer * 17.0) - _t * speed, size.x - 6.0) + 3.0
			var y := 5.0 + fposmod(star * (37.0 + layer * 11.0), size.y - 20.0)
			var twinkle := 0.36 + 0.34 * absf(sin(_t * (1.1 + layer * 0.3) + star))
			var color := Color.from_hsv(fposmod(0.52 + layer * 0.12, 1.0), 0.40, 1.0)
			draw_circle(Vector2(x, y), 0.7 + layer * 0.34, Color(color, twinkle))
	var horizon := size.y * 0.73
	for depth in 5:
		var y := lerpf(horizon, size.y - 3.0, float(depth) / 4.0)
		draw_line(Vector2(3, y), Vector2(size.x - 3, y), Color(0.25, 0.90, 0.92, 0.10 + depth * 0.035), 1.0)


## Grobes Feldsampling erinnert an vorberechnete Metaball-Tabellen: keine
## Shader-Zufallstextur, sondern vier deterministische, audioreaktive Quellen.
func _draw_aga_metaballs() -> void:
	var columns := 48
	var rows := 12
	var cell_w := (size.x - 6.0) / columns
	var cell_h := (size.y - 6.0) / rows
	var sources: Array[Vector2] = []
	for source_index in 4:
		sources.append(Vector2(
			size.x * (0.18 + source_index * 0.21) + sin(_t * (0.71 + source_index * 0.09)) * size.x * 0.09,
			size.y * (0.34 + float(source_index % 2) * 0.32) + cos(_t * (0.93 + source_index * 0.11)) * size.y * 0.18))
	for row in rows:
		for column in columns:
			var point := Vector2(3.0 + (column + 0.5) * cell_w, 3.0 + (row + 0.5) * cell_h)
			var field := 0.0
			for source_index in sources.size():
				var distance_sq := maxf(18.0, point.distance_squared_to(sources[source_index]))
				field += (290.0 + _spectrum[source_index * 7] * 620.0) / distance_sq
			if field < 0.095:
				continue
			var level := clampf((field - 0.095) * 2.7, 0.0, 1.0)
			var hue := fposmod(0.72 - level * 0.56 + _t * 0.018, 1.0)
			var color := Color.from_hsv(hue, 0.82, 0.72 + level * 0.28)
			draw_rect(Rect2(3.0 + column * cell_w, 3.0 + row * cell_h,
				cell_w + 0.4, cell_h + 0.4), Color(color, 0.10 + level * 0.55))


## Eine diskrete AGA-Feuersimulation aus Blitter-Spalten: Bass verbreitert die
## Flammen, hohe Baender treiben Funken. Die Palette bleibt vollstaendig
## berechnet und benoetigt keine eingebrannte Animation.
func _draw_aga_firestorm() -> void:
	var columns := 72
	var width := size.x / float(columns)
	for column in columns:
		var band := column % MAX_BANDS
		var drive := maxf(_spectrum[band], 0.08 + 0.05 * absf(sin(column * 1.7 + _t)))
		var height := 5.0 + drive * size.y * 0.72 + _beat * 9.0
		var x0 := column * width
		var tip_x := x0 + width * 0.5 + sin(_t * 3.1 + column * 0.72) * width * 0.75
		var flame := PackedVector2Array([
			Vector2(x0, size.y - 3.0), Vector2(x0 + width + 0.5, size.y - 3.0),
			Vector2(tip_x, size.y - 3.0 - height)])
		var hue := 0.01 + clampf(drive, 0.0, 1.0) * 0.13
		draw_colored_polygon(flame, Color(Color.from_hsv(hue, 0.92, 1.0), 0.19 + drive * 0.48))
	for ember in 28:
		var life := fposmod(_t * (0.21 + float(ember % 4) * 0.035) + ember * 0.137, 1.0)
		var x := fposmod(ember * 97.0 + sin(ember * 2.3) * 31.0, size.x - 8.0) + 4.0
		var y := size.y - 5.0 - life * size.y * 0.88
		draw_circle(Vector2(x + sin(_t * 2.0 + ember) * 4.0, y), 0.7 + (ember % 3) * 0.35,
			Color(1.0, 0.62 + life * 0.28, 0.16, (1.0 - life) * 0.72))


## Ein texturierter Tabellen-Tunnel: elliptische Ringe rotieren gegeneinander,
## waehrend die Spektralbaender Tiefe und Segmentfarbe modulieren.
func _draw_aga_texture_tunnel() -> void:
	var center := size * 0.5 + Vector2(sin(_t * 0.7) * size.x * 0.04, cos(_t * 0.9) * size.y * 0.08)
	for ring in 15:
		var depth := fposmod(float(ring) / 15.0 + _t * 0.105, 1.0)
		var radius := pow(depth, 1.55)
		var extent := Vector2(size.x * 0.48, size.y * 0.46) * radius
		var points := PackedVector2Array()
		for segment in 28:
			var angle := TAU * float(segment) / 28.0 + _t * (0.13 + depth * 0.22) + ring * 0.11
			var band := (ring * 2 + segment) % MAX_BANDS
			var ripple := 1.0 + _spectrum[band] * 0.12
			points.append(center + Vector2(cos(angle) * extent.x, sin(angle) * extent.y) * ripple)
		points.append(points[0])
		var color := Color.from_hsv(fposmod(depth * 0.72 + _t * 0.025, 1.0), 0.78, 1.0)
		draw_polyline(points, Color(color, 0.09 + depth * 0.40), 1.0 + _beat * 0.45)


## Mehrschichtige, pseudo-isometrische Stadt statt der flachen ECS-Skyline.
## Vorder- und Seitenflaechen reagieren getrennt auf FFT und Pattern-Takt.
func _draw_aga_voxel_city() -> void:
	var horizon := size.y * 0.38
	for depth in 3:
		var count := 18 + depth * 6
		var width := size.x / float(count)
		for index in count:
			var band := (index * 3 + depth * 5) % MAX_BANDS
			var drive := maxf(_spectrum[band], 0.08 + 0.05 * absf(sin(index + _t * 0.4)))
			var building_h := 5.0 + drive * (22.0 + depth * 13.0)
			var x := index * width + depth * 4.0 - 8.0
			var base_y := horizon + depth * (size.y - horizon - 5.0) / 2.3
			var face_color := Color.from_hsv(fposmod(0.54 + index * 0.018 + depth * 0.12, 1.0), 0.72, 0.78)
			draw_rect(Rect2(x, base_y - building_h, width - 1.0, building_h),
				Color(face_color.darkened(0.48), 0.30 + depth * 0.16))
			var top := PackedVector2Array([
				Vector2(x, base_y - building_h), Vector2(x + 3.0, base_y - building_h - 2.0),
				Vector2(x + width + 2.0, base_y - building_h - 2.0),
				Vector2(x + width - 1.0, base_y - building_h)])
			draw_colored_polygon(top, Color(face_color, 0.24 + depth * 0.15))
			if drive > 0.18:
				draw_rect(Rect2(x + 2.0, base_y - building_h + 3.0, 1.0, 1.0),
					Color(1.0, 0.82, 0.38, 0.68))
	for grid_line in 9:
		var x := float(grid_line) / 8.0 * size.x
		draw_line(Vector2(size.x * 0.5, horizon), Vector2(x, size.y - 3.0),
			Color(0.18, 0.84, 0.94, 0.09), 1.0)


## Partikel sammeln sich beatgesteuert zu einer geschwungenen Logo-Signatur
## und loesen sich wieder in Orbitbahnen. Das ist ein klarer spaeter AGA-Look,
## bleibt aber deterministisch und vollstaendig innerhalb des HUD-Rahmens.
func _draw_aga_particle_logo() -> void:
	var particle_count := 84
	var resolve := 0.5 + 0.5 * sin(_t * 0.72)
	resolve = smoothstep(0.18, 0.82, resolve)
	for particle in particle_count:
		var f := float(particle) / float(particle_count - 1)
		var target := Vector2(8.0 + f * (size.x - 16.0),
			size.y * 0.51 + sin(f * TAU * 3.0) * size.y * 0.19
			+ sin(f * TAU * 7.0 + _t) * 2.0)
		var orbit_angle := f * TAU * 5.0 + _t * (0.44 + float(particle % 5) * 0.035)
		var orbit := size * 0.5 + Vector2(cos(orbit_angle) * size.x * (0.10 + f * 0.38),
			sin(orbit_angle * 1.31) * size.y * 0.38)
		var drive := _spectrum[particle % MAX_BANDS]
		var point := orbit.lerp(target, clampf(resolve + drive * 0.22 + _beat * 0.16, 0.0, 1.0))
		var hue := fposmod(f * 0.82 + _t * 0.027, 1.0)
		var color := Color.from_hsv(hue, 0.75, 1.0)
		draw_circle(point, 0.9 + float(particle % 3) * 0.38 + drive * 1.4,
			Color(color, 0.30 + resolve * 0.42 + drive * 0.20))


## Der gewählte Preset-Hintergrund erhält einen dezenten Generationsakzent,
## damit der Rechnerwechsel auch ohne manuelles Durchklicken sichtbar ist.
func _draw_generation_accents(chipset: String) -> void:
	if bool(SettingsManager.value("reduced_motion")):
		return
	if chipset == "ECS":
		for lane in 2:
			var points := PackedVector2Array()
			for x in range(0, ceili(size.x) + 8, 8):
				var y := size.y * (0.31 + lane * 0.34) \
					+ sin(x * 0.032 + _t * 2.0 + lane * 1.7) * (2.0 + _beat)
				points.append(Vector2(x, roundf(y)))
			draw_polyline(points, Color(0.18, 0.84, 0.92, 0.18), 1.0)
	elif chipset == "AGA":
		for lane in 3:
			var points := PackedVector2Array()
			for x in range(0, ceili(size.x) + 6, 6):
				var y := size.y * (0.24 + lane * 0.25) \
					+ sin(x * 0.030 + _t * 2.2 + lane) * (2.8 + _beat * 1.6) \
					+ cos(x * 0.013 - _t + lane) * 1.4
				points.append(Vector2(x, roundf(y)))
			var accent := Color.from_hsv(fposmod(_t * 0.04 + lane * 0.27, 1.0), 0.78, 1.0)
			draw_polyline(points, Color(accent, 0.23), 1.0)


func _effect_label(id: String) -> String:
	return Presentation.effect_label(id, _visible_bands)
