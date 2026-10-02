class_name SleepTransitionScreen
extends Control
## Verbindlicher Tagesabschluss: kurze stilisierte Schlafanimation, danach eine
## ruhige Morgenkarte. Der Kalender ist beim Oeffnen bereits atomar verarbeitet;
## WEITER gibt lediglich die Eingabe fuer die vorbereiteten Tagesereignisse frei.

signal finished
signal stage_changed(stage: StringName)

enum Stage { SLEEPING, MORNING, COMPLETE }

const _MorningFeatureArt := preload("res://scripts/ui/morning_feature_art.gd")

const _SleepTimeline := preload("res://scripts/ui/sleep_timeline.gd")

const SLEEP_SECONDS := 3.15
const REDUCED_SLEEP_SECONDS := 0.78
const SLEEP_ART_CLEAR := "res://assets/ui/transitions/SOMMER90_SLEEP_MASTER_V01.png"
const SLEEP_ART_RAIN := "res://assets/ui/transitions/SOMMER90_SLEEP_RAIN_MASTER_V02.png"
const SceneRenderer := preload("res://scripts/ui/sleep_transition_scene_renderer.gd")

var summary: Dictionary = {}
var auto_close := true
var auto_audio := true

var _stage := Stage.SLEEPING
var _elapsed := 0.0
var _complete_guard := false
var _reduced_motion_override: Variant = null
var _reduced_motion := false
var _avatar_look: Dictionary = {}
var _weather_state := "clear"
var _weather_wind := 0.18
var _settings_node: Node = null   # lazy — _draw läuft jeden Frame
var _scene_renderer := SceneRenderer.new()

var _header_label: Label
var _phase_label: Label
var _sleep_view: VBoxContainer
var _sleep_kicker: Label
var _sleep_zzz: Label
var _sleep_caption: Label
var _sleep_progress: _SleepTimeline
var _sleep_processing: Label
var _sleep_art: TextureRect
var _morning_card: PanelContainer
var _day_kicker: Label
var _weekday: Label
var _date: Label
var _jump: Label
var _morning_feature: _MorningFeatureArt
var _notice_rows: VBoxContainer
var _campaign: Label
var _continue_button: Button
var _input_hint: Label


func configure(data: Dictionary) -> SleepTransitionScreen:
	summary = data.duplicate(true)
	if is_node_ready():
		_refresh_copy()
	return self


func set_reduced_motion(value: bool) -> void:
	_reduced_motion_override = value
	_reduced_motion = value
	queue_redraw()


func clear_reduced_motion_override() -> void:
	_reduced_motion_override = null
	_reduced_motion = _settings_reduced_motion()
	queue_redraw()


func current_stage() -> StringName:
	return [&"sleeping", &"morning", &"complete"][_stage]


func visual_contract() -> Dictionary:
	var hair_key := str(_avatar_look.get("hair_color", _avatar_look.get("hair", "brown")))
	return {
		"stage": current_stage(),
		"elapsed_days": int(summary.get("elapsed_days", 1)),
		"manual_continue": true,
		"calendar_already_committed": true,
		"reduced_motion": _reduced_motion,
		"year_finale": bool(summary.get("year_finale", false)),
		"avatar_hair": hair_key,
		"avatar_hair_style": str(_avatar_look.get("hair_style", "short")),
		"avatar_skin": str(_avatar_look.get("skin", "beige")),
		"weather_window": _weather_state,
		"transition_art": SLEEP_ART_RAIN if _weather_state in ["rain", "storm"] else SLEEP_ART_CLEAR,
		"cinematic_effects": [&"authored_sleep_art", &"weather_variant",
			&"sleep_timeline", &"cinematic_vignette", &"morning_card"],
	}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 500
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.get_theme()
	_reduced_motion = bool(_reduced_motion_override) if _reduced_motion_override != null else _settings_reduced_motion()
	_resolve_cinematic_context()
	_build_interface()
	var localization := get_node_or_null("/root/Localization")
	var locale_callback := Callable(self, "_on_locale_changed")
	if localization != null and not localization.is_connected("locale_changed", locale_callback):
		localization.connect("locale_changed", locale_callback)
	_refresh_static_copy()
	_refresh_copy()
	_apply_stage()
	_emit_audio(&"sleep")
	set_process(true)


## Der Schlafende wird aus derselben vollstaendig aufgeloesten Auswahl wie das
## Spielerportraet gezeichnet. Dadurch stimmen auch Seed-Fallbacks, nicht nur
## explizit im Setup gewaehlte Farben.
func _resolve_cinematic_context() -> void:
	var identity := get_node_or_null("/root/PlayerIdentity")
	if identity != null:
		_avatar_look = PortraitGen.selection_for(
			str(identity.get("avatar_seed")), identity.call("hints"))
	else:
		_avatar_look = {"skin": "beige", "hair_color": "brown", "hair_style": "short"}
	var weather := get_node_or_null("/root/WeatherManager")
	if weather != null:
		_weather_state = str(weather.call("state"))
		_weather_wind = float(weather.call("wind"))


func _process(delta: float) -> void:
	if _stage != Stage.SLEEPING:
		return
	_elapsed += minf(maxf(delta, 0.0), 0.1)
	var duration := REDUCED_SLEEP_SECONDS if _reduced_motion else SLEEP_SECONDS
	var progress := clampf(_elapsed / duration, 0.0, 1.0)
	_sleep_progress.progress = progress
	if not _reduced_motion:
		_sleep_zzz.modulate.a = 0.86 + sin(_elapsed * 2.4) * 0.10
	_update_sleep_copy(progress)
	if _elapsed >= duration:
		_set_stage(Stage.MORNING)
	queue_redraw()


## Einziger Freigabepunkt. Doppelklick kann weder Datum noch Folgefenster
## doppelt ausloesen, denn der Kalender wurde nicht von diesem Screen veraendert.
func complete() -> void:
	if _stage != Stage.MORNING or _complete_guard:
		return
	_complete_guard = true
	_set_stage(Stage.COMPLETE)
	_emit_audio(&"continue")
	finished.emit()
	if auto_close:
		queue_free.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _stage == Stage.MORNING:
		complete()
		get_viewport().set_input_as_handled()


func _set_stage(next: Stage) -> void:
	if _stage == next:
		return
	_stage = next
	_apply_stage()
	stage_changed.emit(current_stage())
	queue_redraw()


func _apply_stage() -> void:
	if _sleep_view == null:
		return
	var sleeping := _stage == Stage.SLEEPING
	_sleep_art.visible = sleeping
	_sleep_view.visible = sleeping
	_morning_card.visible = _stage == Stage.MORNING
	_refresh_phase_copy()
	if _stage == Stage.MORNING:
		_emit_audio(&"morning")
		_continue_button.grab_focus.call_deferred()


func _build_interface() -> void:
	# Autorisiertes Vollbildmotiv statt der alten prozeduralen Bett-/ZZZ-
	# Animation. Klare Nacht und Regen (mit geschlossenem Fenster) sind getrennte
	# Artworks; alle eigentlichen Tagesdaten bleiben echte UI darüber.
	_sleep_art = TextureRect.new()
	_sleep_art.name = "SleepTransitionArtwork"
	_sleep_art.texture = load(SLEEP_ART_RAIN if _weather_state in ["rain", "storm"] else SLEEP_ART_CLEAR)
	_sleep_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sleep_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sleep_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_sleep_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sleep_art)

	var safe := MarginContainer.new()
	safe.name = "SafeArea"
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 52)
	safe.add_theme_constant_override("margin_right", 52)
	safe.add_theme_constant_override("margin_top", 34)
	safe.add_theme_constant_override("margin_bottom", 34)
	add_child(safe)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	safe.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	_header_label = _label("TAGESABSCHLUSS", 19, Palette.LCD_AMBER)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header_label)
	_phase_label = _label("SCHLAFPHASE", 14, Palette.LCD_CYAN)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_phase_label)
	var rule := ColorRect.new()
	rule.color = Color(Palette.LCD_AMBER, 0.62)
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)

	_sleep_view = VBoxContainer.new()
	_sleep_view.name = "SleepAnimation"
	_sleep_view.alignment = BoxContainer.ALIGNMENT_CENTER
	_sleep_view.custom_minimum_size = Vector2(900, 540)
	_sleep_view.add_theme_constant_override("separation", 10)
	center.add_child(_sleep_view)
	_sleep_kicker = _label("NACHTLAUF · ERHOLUNG 100 %", 15, Palette.LCD_AMBER)
	_sleep_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sleep_view.add_child(_sleep_kicker)
	var cinematic_space := Control.new()
	cinematic_space.custom_minimum_size.y = 326
	cinematic_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_view.add_child(cinematic_space)
	_sleep_zzz = _label("DU SCHLÄFST", 42, Palette.WHITE_SOFT)
	_sleep_zzz.name = "SleepZzz"
	_sleep_zzz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sleep_zzz.add_theme_constant_override("outline_size", 6)
	_sleep_zzz.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.05, 0.95))
	_sleep_view.add_child(_sleep_zzz)
	_sleep_caption = _label("LICHT AUS · DIE NACHT BEGINNT", 17, Palette.LCD_CYAN)
	_sleep_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sleep_view.add_child(_sleep_caption)
	_sleep_progress = _SleepTimeline.new()
	_sleep_progress.name = "SleepProgress"
	_sleep_progress.custom_minimum_size = Vector2(650, 36)
	_sleep_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sleep_progress.reduced_motion = _reduced_motion
	_sleep_view.add_child(_sleep_progress)
	_sleep_processing = _label("NACHT  ──  TIEFSCHLAF  ──  MORGENGRAUEN", 12, Palette.UI_TEXT_DIM)
	_sleep_processing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sleep_view.add_child(_sleep_processing)

	_morning_card = PanelContainer.new()
	_morning_card.name = "MorningCard"
	_morning_card.custom_minimum_size = Vector2(900, 545)
	_morning_card.add_theme_stylebox_override("panel", _card_style())
	center.add_child(_morning_card)
	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 28)
	card_margin.add_theme_constant_override("margin_right", 28)
	card_margin.add_theme_constant_override("margin_top", 22)
	card_margin.add_theme_constant_override("margin_bottom", 22)
	_morning_card.add_child(card_margin)
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 7)
	card_margin.add_child(card)
	_day_kicker = _label("●  NEUER TAG", 16, Palette.LCD_GREEN)
	_day_kicker.name = "DayKicker"
	_day_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_day_kicker)
	_weekday = _label("", 48, Palette.WHITE_SOFT)
	_weekday.name = "NewWeekday"
	_weekday.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_weekday)
	_date = _label("", 30, Palette.LCD_AMBER)
	_date.name = "NewDate"
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_date)
	_jump = _label("", 15, Palette.LCD_CYAN)
	_jump.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_jump)
	_morning_feature = _MorningFeatureArt.new()
	_morning_feature.name = "MorningFeature"
	_morning_feature.custom_minimum_size = Vector2(760, 126)
	_morning_feature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_morning_feature)
	var card_rule := ColorRect.new()
	card_rule.color = Color(Palette.UI_BORDER, 0.65)
	card_rule.custom_minimum_size = Vector2(0, 1)
	card.add_child(card_rule)
	_notice_rows = VBoxContainer.new()
	_notice_rows.name = "MorningNotices"
	_notice_rows.add_theme_constant_override("separation", 3)
	card.add_child(_notice_rows)
	_campaign = _label("", 14, Palette.UI_TEXT_DIM)
	_campaign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_campaign)
	_continue_button = _button(Loc.t("ui.sleep_transition_screen.weiter_in_den_tag", "WEITER IN DEN TAG"))
	_continue_button.name = "ContinueDay"
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.pressed.connect(complete)
	card.add_child(_continue_button)
	_input_hint = _label("Klicken oder Enter · Der Tageswechsel erfolgt nur einmal", 11, Palette.UI_TEXT_DIM)
	_input_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(_input_hint)


func _refresh_static_copy() -> void:
	if _header_label == null:
		return
	_header_label.text = Loc.t("ui.sleep_transition_screen.header", "TAGESABSCHLUSS")
	_sleep_kicker.text = Loc.t("ui.sleep_transition_screen.night_run", "NACHTLAUF · ERHOLUNG 100 %")
	_sleep_zzz.text = Loc.t("ui.sleep_transition_screen.sleeping", "DU SCHLÄFST")
	_sleep_processing.text = Loc.t("ui.sleep_transition_screen.phase_line",
		"NACHT  ──  TIEFSCHLAF  ──  MORGENGRAUEN")
	_input_hint.text = Loc.t("ui.sleep_transition_screen.input_hint",
		"Klicken oder Enter · Der Tageswechsel erfolgt nur einmal")
	_morning_feature.prompt = Loc.t("ui.sleep_transition_screen.feature_continue",
		"WEITER DRÜCKEN, WENN DU BEREIT BIST")
	_morning_feature.queue_redraw()


func _refresh_phase_copy() -> void:
	if _phase_label == null:
		return
	if _stage == Stage.SLEEPING:
		_update_sleep_copy(_sleep_progress.progress if _sleep_progress != null else 0.0)
	elif bool(summary.get("year_finale", false)):
		_phase_label.text = Loc.t("ui.sleep_transition_screen.year_finale_ready",
			"SAISONMONTAGE · BEREIT")
		if _sleep_caption != null:
			_sleep_caption.text = Loc.t("ui.sleep_transition_screen.year_finale_waits",
				"31. DEZEMBER · DER JAHRESABSCHLUSS WARTET")
	else:
		_phase_label.text = Loc.t("ui.sleep_transition_screen.morning_ready", "MORGEN · BEREIT")
		if _sleep_caption != null:
			_sleep_caption.text = Loc.t("ui.sleep_transition_screen.erstes_licht_nachste_tag_wartet",
				"ERSTES LICHT · DER NÄCHSTE TAG WARTET")


func _on_locale_changed(_locale: String) -> void:
	_refresh_static_copy()
	_refresh_copy()
	_refresh_phase_copy()
	queue_redraw()


func _refresh_copy() -> void:
	if _weekday == null:
		return
	var from: Dictionary = summary.get("from_date", {})
	var weekday_index := int(summary.get("weekday_index", 0))
	_weekday.text = Loc.t("calendar.weekday.%d" % weekday_index,
		str(summary.get("weekday", "Neuer Tag"))).to_upper()
	_date.text = _localized_date(int(summary.get("to_day", TimeManager.day)),
		int(summary.get("to_month", TimeManager.month)),
		int(summary.get("to_year", TimeManager.year)))
	var elapsed_days := int(summary.get("elapsed_days", 1))
	var year_finale := bool(summary.get("year_finale", false))
	if year_finale:
		_day_kicker.text = Loc.t("ui.sleep_transition_screen.summer_chapter_complete",
			"◆  SOMMERKAPITEL ABGESCHLOSSEN")
		_jump.text = Loc.t("ui.sleep_transition_screen.season_montage_days_later",
			"SAISONMONTAGE · HERBST / WINTER · %d KALENDERTAGE") % elapsed_days
	elif elapsed_days > 1:
		_day_kicker.text = Loc.t("ui.sleep_transition_screen.new_day", "●  NEUER TAG")
		_jump.text = Loc.t("ui.sleep_transition_screen.zeitsprung_d_kalendertage_spater", "ZEITSPRUNG · %d KALENDERTAGE SPÄTER") % elapsed_days
	else:
		_day_kicker.text = Loc.t("ui.sleep_transition_screen.new_day", "●  NEUER TAG")
		_jump.text = Loc.t("ui.sleep_transition_screen.nacht_spater_08_10_uhr", "EINE NACHT SPÄTER · 08:10 UHR")
	var feature: Dictionary = summary.get("feature", {})
	_morning_feature.visible = not feature.is_empty()
	if not feature.is_empty():
		_morning_feature.kind = str(feature.get("kind", "day"))
		_morning_feature.title = Loc.t(str(feature.get("title_key", "")),
			str(feature.get("title", "HEUTE WICHTIG"))) if not str(feature.get("title_key", "")).is_empty() \
			else str(feature.get("title", "HEUTE WICHTIG"))
		_morning_feature.subtitle = Loc.t(str(feature.get("subtitle_key", "")),
			str(feature.get("subtitle", ""))) if not str(feature.get("subtitle_key", "")).is_empty() \
			else str(feature.get("subtitle", ""))
		_morning_feature.queue_redraw()
	for child: Node in _notice_rows.get_children():
		child.queue_free()
	var notice_specs: Array = summary.get("notice_specs", [])
	var notices: Array = summary.get("notices", [])
	var rendered_notices: Array[String] = []
	if not notice_specs.is_empty():
		for raw_spec: Variant in notice_specs:
			if raw_spec is Dictionary:
				var localized := _localized_notice(raw_spec)
				if not localized.is_empty():
					rendered_notices.append(localized)
	else:
		for raw: Variant in notices:
			rendered_notices.append(str(raw))
	for notice: String in rendered_notices:
		var row := _label("▸  %s" % notice, 16, Palette.UI_TEXT)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_notice_rows.add_child(row)
	var campaign_day := int(summary.get("campaign_day", 0))
	var campaign_total := int(summary.get("campaign_total", 0))
	if year_finale:
		_campaign.text = Loc.t("ui.sleep_transition_screen.summer_over_year_finale_waits",
			"DER SOMMER IST BEENDET · SILVESTER UND DER JAHRESRÜCKBLICK WARTEN")
		_continue_button.text = Loc.t("ui.sleep_transition_screen.weiter_zum_jahresabschluss", "WEITER ZUM JAHRESABSCHLUSS")
	elif campaign_day > 0 and campaign_total > 0:
		_campaign.text = Loc.t("ui.sleep_transition_screen.spieltag_02d_02d_sommer_02d", "SPIELTAG %02d / %02d · SOMMER '%02d") % [campaign_day, campaign_total,
			int(summary.get("to_year", TimeManager.year)) % 100]
		_continue_button.text = Loc.t("ui.sleep_transition_screen.weiter_in_den_tag", "WEITER IN DEN TAG")
	else:
		_campaign.text = Loc.t("ui.sleep_transition_screen.erholt_energie_100", "ERHOLT · ENERGIE 100 %")
		_continue_button.text = Loc.t("ui.sleep_transition_screen.weiter_in_den_tag", "WEITER IN DEN TAG")
	var from_label := _localized_date(int(from.get("day", TimeManager.day)),
		int(from.get("month", TimeManager.month)), int(from.get("year", TimeManager.year)))
	var from_clock := str(from.get("clock", "23:10"))
	_sleep_view.tooltip_text = Loc.t("ui.sleep_transition_screen.schlaf_von_s_s_uhr", "Schlaf von %s · %s Uhr") % [from_label, from_clock]


func _localized_date(day: int, month: int, year: int) -> String:
	var month_name := Loc.t("calendar.month.%02d" % clampi(month, 1, 12),
		TimeManager.MONTHS[clampi(month, 1, 12) - 1])
	var locale := TranslationServer.get_locale().split("_")[0].to_lower()
	if locale == "en":
		return "%s %d, %d" % [month_name, day, year]
	return "%d. %s %d" % [day, month_name, year]


func _localized_notice(spec: Dictionary) -> String:
	var kind := str(spec.get("kind", ""))
	match kind:
		"weather":
			var weather_id := str(spec.get("weather", "clear"))
			var weather := Loc.t("ui.sleep_transition.weather.%s" % weather_id, weather_id).to_upper()
			return Loc.t("ui.sleep_transition.notice.weather", "WETTER · %s") % weather
		"duty":
			var duty_id := str(spec.get("duty", "free"))
			var duty := Loc.t("ui.sleep_transition.duty.%s" % duty_id, duty_id).to_upper()
			return Loc.t("ui.sleep_transition.notice.duty", "MORGENPLAN · %s") % duty
		"holiday":
			var holiday_id := str(spec.get("holiday", ""))
			return Loc.t("ui.sleep_transition.holiday.%s" % holiday_id, holiday_id).to_upper()
		"deliveries":
			return Loc.t("ui.sleep_transition.notice.deliveries", "LIEFERUNGEN · TERMINE · COOLDOWNS AKTUALISIERT")
		"club_today":
			return Loc.t("ui.sleep_transition.notice.club_today", "HEUTE MÖGLICH · COMPUTERCLUB AM ABEND")
		"flea_today":
			return Loc.t("ui.sleep_transition.notice.flea_today", "HEUTE MÖGLICH · FLOHMARKT AM VORMITTAG")
		"order":
			var order_name := str(spec.get("name", "BESTELLUNG")).to_upper()
			var additional := int(spec.get("additional", 0))
			if additional > 0:
				return Loc.t("ui.sleep_transition.notice.order_many", "ABHOLBEREIT BEI GRUBER · %s · +%d WEITERE") % [order_name, additional]
			return Loc.t("ui.sleep_transition.notice.order", "ABHOLBEREIT BEI GRUBER · %s") % order_name
		"phone":
			var phone_count := int(spec.get("count", 0))
			return Loc.t("ui.sleep_transition.notice.phone", "TELEFON · %d NEUE NACHRICHT(EN) / RÜCKRUF(E)") % phone_count
		"quest":
			var quest_count := int(spec.get("count", 0))
			var quest_title := QuestManager.localized_title(str(spec.get("quest_id", ""))).to_upper()
			return Loc.t("ui.sleep_transition.notice.quest", "AUFTRÄGE · %d OFFEN · %s") % [quest_count, quest_title]
		"tasks":
			return Loc.t("ui.sleep_transition.notice.tasks", "NOTIZBOARD · %d OFFENE AUFGABE(N)") % int(spec.get("count", 0))
		"summer_chapter":
			return Loc.t("ui.sleep_transition.notice.summer_chapter", "SOMMERKAPITEL '%02d ABGESCHLOSSEN") % (int(spec.get("year", 1990)) % 100)
		"season_montage":
			return Loc.t("ui.sleep_transition.notice.season_montage", "HERBST UND WINTER · ALS MONTAGE VERGANGEN")
	return ""


func _update_sleep_copy(progress: float) -> void:
	if _sleep_caption == null or _stage != Stage.SLEEPING:
		return
	if progress < 0.20:
		_phase_label.text = Loc.t("ui.sleep_transition_screen.einschlafen", "EINSCHLAFEN")
		_sleep_caption.text = Loc.t("ui.sleep_transition_screen.licht_aus_gerausche_werden_leiser", "LICHT AUS · DIE GERÄUSCHE WERDEN LEISER")
	elif progress < 0.72:
		_phase_label.text = Loc.t("ui.sleep_transition_screen.tiefschlaf", "TIEFSCHLAF")
		if bool(summary.get("year_finale", false)):
			_sleep_caption.text = Loc.t("ui.sleep_transition_screen.autumn_winter_montage",
				"DER SOMMER ENDET · HERBST UND WINTER VERGEHEN")
		else:
			_sleep_caption.text = Loc.t("ui.sleep_transition_screen.nacht_zieht_vorbei_du_holst_energie", "DIE NACHT ZIEHT VORBEI · DU HOLST ENERGIE ZURÜCK")
	else:
		if bool(summary.get("year_finale", false)):
			_phase_label.text = Loc.t("ui.sleep_transition_screen.silvester", "SILVESTER")
			_sleep_caption.text = Loc.t("ui.sleep_transition_screen.year_finale_waits",
				"31. DEZEMBER · DER JAHRESABSCHLUSS WARTET")
		else:
			_phase_label.text = Loc.t("ui.sleep_transition_screen.morgengrauen", "MORGENGRAUEN")
			_sleep_caption.text = Loc.t("ui.sleep_transition_screen.erstes_licht_nachste_tag_wartet", "ERSTES LICHT · DER NÄCHSTE TAG WARTET")


func _draw() -> void:
	var sz := size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	if _stage == Stage.SLEEPING and _sleep_art != null:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.004, 0.007, 0.013))
		return
	var from: Dictionary = summary.get("from_date", {})
	_scene_renderer.draw_morning(self, sz, {
		"avatar_look": _avatar_look,
		"weather_state": _weather_state,
		"weather_wind": _weather_wind,
		"elapsed": _elapsed,
		"reduced_motion": _reduced_motion,
		"from_clock": str(from.get("clock", "23:10")),
		"scanlines": _scanlines_enabled(),
	})


func _emit_audio(cue: StringName) -> void:
	if not auto_audio:
		return
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	match cue:
		&"sleep": audio.call("minigame_cue", "sleep_transition", &"focus")
		&"morning": audio.call("minigame_cue", "sleep_transition", &"success")
		&"continue": audio.call("key_enter")


func _settings_reduced_motion() -> bool:
	var settings := get_node_or_null("/root/SettingsManager")
	return settings != null and bool(settings.call("value", "reduced_motion"))


func _scanlines_enabled() -> bool:
	if _settings_node == null:
		_settings_node = get_node_or_null("/root/SettingsManager")
	return _settings_node == null or bool(_settings_node.call("value", "scanlines"))


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.78))
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 46)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 19)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("111822")
	normal.border_color = Color(Palette.LCD_AMBER, 0.68)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("35240d")
	hover.border_color = Palette.LCD_AMBER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("080a0f")
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Palette.LCD_CYAN
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_hover_color", Palette.LCD_AMBER)
	button.add_theme_color_override("font_focus_color", Palette.WHITE_SOFT)
	return button


func _card_style() -> StyleBoxFlat:
	return _SleepTimeline.card_style()
