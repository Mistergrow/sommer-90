class_name TopBar
extends Control
## Obere Statusleiste (Mockup-Layout): Datumsblock, GELD, ENERGIE, RUF,
## Logo, AUSBAU mit getrennt bezeichnetem Archivwert, NÄCHSTES EVENT.

const COLLECTION_TARGET := 2000  # DM Sammlungswert für "Sammlung komplett"
const COMPACT_PANEL_HEIGHT := 70.0
const LEVEL_PANEL_WIDTH := 166.0
const SceneAnimatorBoardScript := preload("res://scripts/ui/scene_animator_board.gd")
const SceneCatalog := preload("res://scripts/ui/scene_generation_catalog.gd")
const SceneControlWindowScript := preload("res://scripts/ui/scene_control_window.gd")

var _avatar_fig: MiniFigure
var _avatar_panel_root: Control
var _age_badge: Label
var _avatar_key := ""
var _age_shown := -1
var _date_panel_root: Control
var _year_label: Label
var _date_label: Label
var _clock_label: Label
var _slot_shown := -1         # für Uhr-Flip + Tag/Nacht-Tönung
var _money_label: Label
var _energy_bar: HudBar
var _ruf_label: Label
var _level_label: Label
var _level_bar: HudBar
var _event_label: Label
var _calendar: TextureRect
var _event_pulse: _EventPulse
var _scene_logo: Control
var _wiggle_tween: Tween
var _money_shown := -1        # für Zähl-Animation
var _ruf_shown := -1
var _level_shown := -1
var _money_tween: Tween
var _ruf_tween: Tween
var _headers: Dictionary = {}
var _level_panel_root: Control


func _ready() -> void:
	clip_contents = true
	_build()
	PlayerStats.stats_changed.connect(refresh)
	TimeManager.slot_changed.connect(func(_s: int) -> void: refresh())
	TimeManager.day_changed.connect(refresh)
	DiskManager.disks_changed.connect(refresh)
	GameManager.game_started.connect(refresh)
	PlayerIdentity.identity_changed.connect(refresh)
	UIManager.notebook_attention_changed.connect(_on_notebook_attention)
	SceneReleaseManager.scene_changed.connect(refresh)
	DemoManager.demos_changed.connect(refresh)
	SettingsManager.settings_changed.connect(_refresh_scene_logo)
	MusicManager.presentation_changed.connect(func(_state: Dictionary) -> void: _refresh_scene_logo())
	Localization.locale_changed.connect(_refresh_locale)
	refresh()


func _build() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 3
	row.offset_right = -3
	row.offset_top = 3
	row.offset_bottom = -3
	row.add_theme_constant_override("separation", 5)
	add_child(row)

	# --- Avatar des Spielers (altert mit; erstellt im Spielstart-Setup) ---
	var avatar_panel := PanelContainer.new()
	avatar_panel.name = "PlayerAvatarPanel"
	avatar_panel.custom_minimum_size = Vector2(76, COMPACT_PANEL_HEIGHT)
	avatar_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	avatar_panel.add_theme_stylebox_override("panel", Bezel.display_box())
	_avatar_panel_root = avatar_panel
	var avatar_stage := Control.new()
	avatar_stage.name = "CenteredAvatarStage"
	avatar_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_panel.add_child(avatar_stage)
	# Lebendiger Avatar (chunky, aus derselben Identität): blinzelt, sieht sich um,
	# gähnt/grinst/zwinkert gelegentlich (Idle-Leben, MiniFigure im Kopf-Modus).
	_avatar_fig = MiniFigure.new()
	_avatar_fig.bob = false
	_avatar_fig.custom_minimum_size = Vector2(64, 64)
	_avatar_fig.set_anchors_preset(Control.PRESET_CENTER)
	_avatar_fig.offset_left = -32
	_avatar_fig.offset_top = -32
	_avatar_fig.offset_right = 32
	_avatar_fig.offset_bottom = 32
	avatar_stage.add_child(_avatar_fig)
	_age_badge = Label.new()
	_age_badge.name = "PlayerAgeBadge"
	_age_badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_age_badge.offset_left = -26
	_age_badge.offset_top = -18
	_age_badge.offset_right = -2
	_age_badge.offset_bottom = -2
	_age_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_age_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_age_badge.add_theme_font_size_override("font_size", 12)
	_age_badge.add_theme_color_override("font_color", Color8(235, 244, 220))
	_age_badge.add_theme_constant_override("outline_size", 1)
	_age_badge.add_theme_color_override("font_outline_color", Color8(7, 9, 12))
	var age_box := StyleBoxFlat.new()
	age_box.bg_color = Color8(23, 86, 105, 235)
	age_box.border_color = Color8(73, 222, 218)
	age_box.set_border_width_all(1)
	age_box.corner_radius_top_left = 2
	age_box.corner_radius_bottom_right = 2
	_age_badge.add_theme_stylebox_override("normal", age_box)
	avatar_stage.add_child(_age_badge)
	row.add_child(avatar_panel)

	# --- Datumsblock: Jahr groß, darunter Datum + Wochentag/Uhrzeit ---
	var date_panel := Bezel.titled_panel("")
	date_panel["root"].custom_minimum_size = Vector2(132, COMPACT_PANEL_HEIGHT)
	date_panel["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_date_panel_root = date_panel["root"]
	_year_label = Bezel.lcd_label(Loc.t("ui.top_bar.1992", "1992"), Palette.UI_TEXT, 27)
	date_panel["body"].add_child(_year_label)
	var date_meta := HBoxContainer.new()
	date_meta.add_theme_constant_override("separation", 5)
	_date_label = Bezel.dim_label(Loc.t("ui.top_bar.apr_24", "APR 24"), 10)
	_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_meta.add_child(_date_label)
	_clock_label = Bezel.dim_label(Loc.t("ui.top_bar.sa_20_45", "SA 20:45"), 10)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_meta.add_child(_clock_label)
	date_panel["body"].add_child(date_meta)
	row.add_child(date_panel["root"])

	# --- GELD ---
	var money_panel := Bezel.titled_panel(Loc.t("ui.top_bar.money", "GELD"))
	_headers["money"] = money_panel["header"]
	money_panel["root"].custom_minimum_size = Vector2(108, COMPACT_PANEL_HEIGHT)
	money_panel["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_money_label = Bezel.segment_label(Loc.t("ui.top_bar.20_00_dm", "20,00 DM"), Palette.LCD_GREEN, 13)
	money_panel["body"].add_child(_money_label)
	row.add_child(money_panel["root"])

	# --- ENERGIE ---
	var energy_panel := Bezel.titled_panel(Loc.t("ui.top_bar.energy", "ENERGIE"))
	_headers["energy"] = energy_panel["header"]
	energy_panel["root"].custom_minimum_size = Vector2(104, COMPACT_PANEL_HEIGHT)
	energy_panel["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_energy_bar = HudBar.new()
	_energy_bar.custom_minimum_size = Vector2(86, 11)
	_energy_bar.fill_color = Color8(236, 111, 28)
	_energy_bar.show_value_text = true
	_energy_bar.text_color = Palette.WHITE_SOFT
	energy_panel["body"].add_child(_energy_bar)
	row.add_child(energy_panel["root"])

	# --- RUF ---
	var ruf_panel := Bezel.titled_panel(Loc.t("ui.top_bar.reputation", "RUF"))
	_headers["reputation"] = ruf_panel["header"]
	ruf_panel["root"].custom_minimum_size = Vector2(78, COMPACT_PANEL_HEIGHT)
	ruf_panel["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_ruf_label = Bezel.lcd_label(Loc.t("ui.top_bar.0", "0"), Palette.LCD_CYAN, 16)
	ruf_panel["body"].add_child(_ruf_label)
	row.add_child(ruf_panel["root"])

	# --- Logo (füllt die Mitte) ---
	var logo_panel := PanelContainer.new()
	logo_panel.custom_minimum_size = Vector2(170, COMPACT_PANEL_HEIGHT)
	logo_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logo_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# Der Animator besitzt seinen eigenen technischen Innenrahmen. Die normale
	# Panelbox würde ihn ein zweites Mal um neun Pixel einrücken und dadurch die
	# wertvollste HUD-Fläche künstlich verkleinern.
	logo_panel.add_theme_stylebox_override("panel", Bezel.display_box())
	_scene_logo = SceneAnimatorBoardScript.new()
	_scene_logo.interactive = true
	_scene_logo.music_reactive = true
	_scene_logo.custom_minimum_size = Vector2(170, COMPACT_PANEL_HEIGHT)
	_scene_logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_logo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_logo.activated.connect(_on_scene_logo_activated)
	logo_panel.add_child(_scene_logo)
	row.add_child(logo_panel)

	# --- AUSBAU + ARCHIV: zwei verschiedene Fortschritte, klar benannt. ---
	# Früher stand hier nur „LEVEL", obwohl die Zahl die Hardware-Ausbaustufe
	# und der Balken den Sammlungswert zeigte. Das sah wie 653/2000 XP auf
	# Spielerlevel 1 aus, obwohl das Spiel überhaupt kein XP-System besitzt.
	var level_panel := Bezel.titled_panel(Loc.t("ui.top_bar.upgrade_archive", "AUSBAU · ARCHIV"))
	_headers["level"] = level_panel["header"]
	_level_panel_root = level_panel["root"]
	level_panel["root"].custom_minimum_size = Vector2(LEVEL_PANEL_WIDTH, COMPACT_PANEL_HEIGHT)
	level_panel["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	level_panel["root"].tooltip_text = Loc.t("ui.top_bar.upgrade_archive_tip",
		"AUSBAU = RAM UND PERIPHERIE · ARCHIV = SAMMLUNGSWERT IN DM")
	_add_level_header_dot(level_panel)
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	_level_label = Bezel.lcd_label(Loc.t("ui.top_bar.1", "1"), Palette.LCD_GREEN, 17)
	level_row.add_child(_level_label)
	_level_bar = HudBar.new()
	_level_bar.custom_minimum_size = Vector2(108, 13)
	_level_bar.fill_color = Color8(116, 141, 45)
	_level_bar.text_color = Palette.WHITE_SOFT
	_level_bar.show_value_text = true
	level_row.add_child(_level_bar)
	level_panel["body"].add_child(level_row)
	row.add_child(level_panel["root"])

	# --- NÄCHSTES EVENT ---
	var event_panel := Bezel.titled_panel(Loc.t("ui.top_bar.next_event", "NÄCHSTES EVENT"))
	_headers["event"] = event_panel["header"]
	event_panel["root"].custom_minimum_size = Vector2(LEVEL_PANEL_WIDTH, COMPACT_PANEL_HEIGHT)
	event_panel["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var event_row := HBoxContainer.new()
	event_row.add_theme_constant_override("separation", 8)
	_event_label = Label.new()
	_event_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_label.add_theme_font_size_override("font_size", 12)
	event_row.add_child(_event_label)
	_calendar = TextureRect.new()
	_calendar.texture = Sprites.ui_icon("calendar")
	_calendar.custom_minimum_size = Vector2(24, 24)
	_calendar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_calendar.pivot_offset = Vector2(12, 12)
	event_row.add_child(_calendar)
	event_panel["body"].add_child(event_row)
	# Pulsierender Warn-Rahmen, wenn heute ein Termin ansteht (liegt über dem Panel).
	_event_pulse = _EventPulse.new()
	_event_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_panel["root"].add_child(_event_pulse)
	row.add_child(event_panel["root"])


func refresh() -> void:
	if _avatar_fig != null:
		# Identität nur bei echter Änderung neu setzen (setup leert den Frame-Cache);
		# die Idle-Animation läuft selbstständig in MiniFigure._process weiter.
		var avatar_hints := _hud_avatar_hints()
		var key := "%s|%s" % [PlayerIdentity.avatar_seed, JSON.stringify(avatar_hints)]
		if key != _avatar_key:
			_avatar_key = key
			_avatar_fig.setup(PlayerIdentity.avatar_seed, avatar_hints, false)
		var player_age := PlayerIdentity.age()
		if is_instance_valid(_age_badge):
			_age_badge.text = str(player_age)
			_age_badge.tooltip_text = Loc.t("ui.top_bar.s_d_jahre_s", "%s · %d JAHRE · %s") % [
				PlayerIdentity.player_name.to_upper(), player_age, _age_stage_label(player_age)]
		if is_instance_valid(_avatar_panel_root):
			_avatar_panel_root.tooltip_text = Loc.t("ui.top_bar.s_d_jahre_n_s_n", "%s · %d JAHRE\n%s\n%s") % [
				PlayerIdentity.player_name.to_upper(), player_age, _age_stage_label(player_age),
				_avatar_expression_label(str(avatar_hints.get("emotion", "neutral")))]
		if _age_shown >= 0 and player_age > _age_shown:
			_pop(_age_badge, 1.45)
			_flash_label(_avatar_panel_root, Color(1.25, 1.15, 0.72))
		_age_shown = player_age
	_year_label.text = str(TimeManager.year)
	var campaign: Dictionary = TimeManager.campaign_progress()
	var chapter := " · W%d/6" % int(campaign.get("week", 0)) if str(campaign.get("phase", "")) == "summer" else ""
	_date_label.text = Loc.t("ui.top_bar.s_d_s", "%s %d%s") % [
		_month_name(TimeManager.month).substr(0, 3).to_upper(), TimeManager.day, chapter]
	_date_label.tooltip_text = (Loc.t("ui.top_bar.summer_day_week",
		"Sommer %d · Spieltag %d/%d · Ferienwoche %d/6") % [
		TimeManager.year, int(campaign.get("day", 0)), int(campaign.get("total_days", 0)), int(campaign.get("week", 0))
	]) if str(campaign.get("phase", "")) == "summer" else TimeManager.date_string()
	_clock_label.text = Loc.t("ui.top_bar.s_s", "%s  %s") % [
		_weekday_name(TimeManager.weekday()).substr(0, 2).to_upper(),
		TimeManager.clock_string()]
	if TimeManager.slot != _slot_shown:
		var first := _slot_shown < 0
		_apply_daynight(TimeManager.slot, not first)
		if not first:
			_flip_clock()
		_slot_shown = TimeManager.slot
	_animate_money(Currency.to_pf(PlayerStats.geld))   # Zähler rechnet in ganzen Pfennig
	_energy_bar.value = PlayerStats.energie
	_energy_bar.value_text = "%d" % int(round(PlayerStats.energie))
	_animate_ruf(PlayerStats.ruf)
	var lvl := PlayerStats.hardware_level()
	_level_label.text = str(lvl)
	if _level_shown >= 0 and lvl > _level_shown:
		_pop(_level_label, 1.5)             # Level-Up: Zahl springt auf
		_flash_label(_level_label, Palette.LCD_GREEN.lightened(0.6))
	_level_shown = lvl
	_level_label.tooltip_text = Loc.t("ui.top_bar.hardware_level",
		"HARDWARE-AUSBAUSTUFE %d") % lvl
	var value := DiskManager.collection_value()
	_level_bar.value = clampf(float(value) / float(COLLECTION_TARGET) * 100.0, 0.0, 100.0)
	_level_bar.value_text = "%s / %s DM" % [_format_dm(value), _format_dm(COLLECTION_TARGET)]
	_level_bar.tooltip_text = Loc.t("ui.top_bar.archive_value_goal",
		"ARCHIVWERT: %s DM VON %s DM LANGZEITZIEL") % [
		_format_dm(value), _format_dm(COLLECTION_TARGET)]
	var event_text := GameManager.next_event_text()
	_event_label.text = event_text
	_set_event_urgent(GameManager.next_event_is_today())
	_refresh_scene_logo()


## Das HUD zeigt nicht rund um die Uhr denselben eingefrorenen Gesichtsausdruck.
## Die Grundemotion kommt aus Tageszeit und Energie; MiniFigure legt Blinzeln,
## Blick und kurze Idle-Aktionen weiterhin als nicht-destruktive Frames darüber.
func _hud_avatar_hints() -> Dictionary:
	var emotion := "neutral"
	match TimeManager.slot:
		0:
			emotion = "tired"
		1, 2:
			emotion = "proud" if PlayerStats.ruf >= 75 else "neutral"
		3:
			emotion = "happy" if PlayerStats.energie >= 45 else "tired"
		_:
			emotion = "tired" if PlayerStats.energie < 70 else "thinking"
	if PlayerStats.energie <= 18:
		emotion = "tired"
	return PlayerIdentity.hints({"emotion": emotion})


func _age_stage_label(player_age: int) -> String:
	if player_age <= 15:
		return Loc.t("ui.top_bar.age_early_teen", "FRUEHE JUGEND")
	if player_age <= 17:
		return Loc.t("ui.top_bar.age_late_teen", "SPAETE JUGEND")
	if player_age <= 20:
		return Loc.t("ui.top_bar.age_young_adult", "JUNGER ERWACHSENER")
	return Loc.t("ui.top_bar.age_adult", "ERWACHSENER")


func _avatar_expression_label(emotion: String) -> String:
	match emotion:
		"tired": return Loc.t("ui.top_bar.expression_tired", "MUEDER TAGESAUSDRUCK")
		"happy": return Loc.t("ui.top_bar.expression_happy", "ENTSPANNTER ABENDAUSDRUCK")
		"proud": return Loc.t("ui.top_bar.expression_proud", "SELBSTSICHERER TAGESAUSDRUCK")
		"thinking": return Loc.t("ui.top_bar.expression_thinking", "RUHIGER NACHTAUSDRUCK")
		_: return Loc.t("ui.top_bar.expression_neutral", "AUFMERKSAMER TAGESAUSDRUCK")


func _refresh_locale(_locale: String) -> void:
	var values := {
		"money": Loc.t("ui.top_bar.money", "GELD"),
		"energy": Loc.t("ui.top_bar.energy", "ENERGIE"),
		"reputation": Loc.t("ui.top_bar.reputation", "RUF"),
		"level": Loc.t("ui.top_bar.upgrade_archive", "AUSBAU · ARCHIV"),
		"event": Loc.t("ui.top_bar.next_event", "NÄCHSTES EVENT"),
	}
	for key: String in values:
		if is_instance_valid(_headers.get(key)):
			(_headers[key] as Label).text = values[key]
	if is_instance_valid(_level_panel_root):
		_level_panel_root.tooltip_text = Loc.t("ui.top_bar.upgrade_archive_tip",
			"AUSBAU = RAM UND PERIPHERIE · ARCHIV = SAMMLUNGSWERT IN DM")
	refresh()


func _month_name(month: int) -> String:
	var months := [
		Loc.t("calendar.month.01", "Januar"), Loc.t("calendar.month.02", "Februar"),
		Loc.t("calendar.month.03", "März"), Loc.t("calendar.month.04", "April"),
		Loc.t("calendar.month.05", "Mai"), Loc.t("calendar.month.06", "Juni"),
		Loc.t("calendar.month.07", "Juli"), Loc.t("calendar.month.08", "August"),
		Loc.t("calendar.month.09", "September"), Loc.t("calendar.month.10", "Oktober"),
		Loc.t("calendar.month.11", "November"), Loc.t("calendar.month.12", "Dezember"),
	]
	return months[clampi(month - 1, 0, 11)]


func _weekday_name(weekday: int) -> String:
	var weekdays := [
		Loc.t("calendar.weekday.0", "Montag"), Loc.t("calendar.weekday.1", "Dienstag"),
		Loc.t("calendar.weekday.2", "Mittwoch"), Loc.t("calendar.weekday.3", "Donnerstag"),
		Loc.t("calendar.weekday.4", "Freitag"), Loc.t("calendar.weekday.5", "Samstag"),
		Loc.t("calendar.weekday.6", "Sonntag"),
	]
	return weekdays[clampi(weekday, 0, 6)]


func _active_scene_generation() -> String:
	if _scene_logo != null and _scene_logo.has_method("active_generation"):
		return str(_scene_logo.call("active_generation"))
	return SceneCatalog.effective_generation()


func _refresh_scene_logo() -> void:
	if _scene_logo == null:
		return
	var generation := _active_scene_generation()
	var selected := SceneCatalog.selected_effect(generation)
	_scene_logo.effect = selected
	_scene_logo.caption = "%s '%02d" % [TimeManager.season_name().to_upper(), TimeManager.year % 100]
	_scene_logo.alert = UIManager.notebook_attention
	var music_state: Dictionary = MusicManager.presentation_state()
	_scene_logo.subtitle = ("NEUES SIGNAL · %d · KLICK" % UIManager.notebook_attention_count) if UIManager.notebook_attention else (
		"♪ %s · %s · %s" % [
			str(music_state.get("source_label", "MUSIK")),
			generation.to_upper(), _scene_effect_name(selected)]
		if bool(music_state.get("playing", false))
		else "%s · %s · KLICK: SCENE CONTROL" % [
			generation.to_upper(), _scene_effect_name(selected)])
	var status_help := str(_scene_logo.call("status_tooltip"))
	_scene_logo.tooltip_text = status_help \
		+ "\n\nKlick: Generation, Preset und Live-Vorschau öffnen"


func _scene_effect_name(id: String) -> String:
	return SceneCatalog.effect_name(id)


func _on_scene_logo_activated() -> void:
	UIManager.navigate_from_hud(func() -> void:
		UIManager.toggle_window("win_scene_control", func() -> Control:
			return SceneControlWindowScript.new()))


func _on_notebook_attention(_active: bool, _count: int) -> void:
	_refresh_scene_logo()


# ------------------------------------------------------------- Juice
# Tag/Nacht-Tönung des Datumsblocks je Zeitfenster (Morgen→Nacht).
const SLOT_TINT := [
	Color(1.0, 0.95, 0.82),   # Morgen — warmes Gold
	Color(1.0, 1.0, 0.97),    # Mittag — hell/neutral
	Color(1.0, 0.94, 0.84),   # Nachmittag — warm
	Color(1.0, 0.82, 0.66),   # Abend — Dämmerungsorange
	Color(0.68, 0.75, 1.0),   # Nacht — Mondlicht, kühl + dunkler
]


## Färbt den Datumsblock je nach Zeitfenster; beim Wechsel weich übergeblendet.
func _apply_daynight(slot: int, animate: bool) -> void:
	if _date_panel_root == null:
		return
	var tint: Color = SLOT_TINT[clampi(slot, 0, SLOT_TINT.size() - 1)]
	if slot == 4:
		tint = tint.darkened(0.12)   # Nacht etwas dunkler
	if animate:
		create_tween().tween_property(_date_panel_root, "modulate", tint, 0.5).set_trans(Tween.TRANS_SINE)
	else:
		_date_panel_root.modulate = tint


## Uhr „klappt" beim Zeitfenster-Wechsel um (vertikaler Flip).
func _flip_clock() -> void:
	_clock_label.pivot_offset = _clock_label.size * 0.5
	_clock_label.scale = Vector2(1.0, 0.0)
	create_tween().tween_property(_clock_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Steht heute ein Termin an, pulsiert der Rahmen rot und der Kalender wackelt.
func _set_event_urgent(urgent: bool) -> void:
	if _event_pulse == null:
		return
	if _event_pulse.active == urgent:
		return
	_event_pulse.active = urgent
	if _wiggle_tween != null and _wiggle_tween.is_valid():
		_wiggle_tween.kill()
	if urgent:
		_wiggle_tween = create_tween().set_loops()
		_wiggle_tween.tween_property(_calendar, "rotation", 0.22, 0.10).set_trans(Tween.TRANS_SINE)
		_wiggle_tween.tween_property(_calendar, "rotation", -0.22, 0.20).set_trans(Tween.TRANS_SINE)
		_wiggle_tween.tween_property(_calendar, "rotation", 0.0, 0.10).set_trans(Tween.TRANS_SINE)
		_wiggle_tween.tween_interval(1.3)
	else:
		_calendar.rotation = 0.0

## Geld zählt hoch/runter statt zu springen, mit kurzem Aufblitzen + Pop.
## target ist in ganzen PFENNIG (Geld ist DM mit Pfennig).
func _animate_money(target: int) -> void:
	if _money_shown < 0:
		_money_shown = target
		_money_label.text = _money_text(target)
		return
	if target == _money_shown:
		return
	if _money_tween != null and _money_tween.is_valid():
		_money_tween.kill()
	var from := _money_shown
	_money_shown = target
	_money_tween = create_tween()
	_money_tween.tween_method(func(v: float) -> void: _money_label.text = _money_text(int(round(v))), float(from), float(target), 0.45).set_trans(Tween.TRANS_QUAD)
	_pop(_money_label, 1.12)
	_flash_label(_money_label, Color(1.8, 1.8, 1.8) if target > from else Color(1.8, 0.7, 0.55))


func _animate_ruf(target: int) -> void:
	if _ruf_shown < 0:
		_ruf_shown = target
		_ruf_label.text = str(target)
		return
	if target == _ruf_shown:
		return
	if _ruf_tween != null and _ruf_tween.is_valid():
		_ruf_tween.kill()
	var from := _ruf_shown
	_ruf_shown = target
	_ruf_tween = create_tween()
	_ruf_tween.tween_method(func(v: float) -> void: _ruf_label.text = str(int(round(v))), float(from), float(target), 0.4)
	_pop(_ruf_label, 1.2)
	_flash_label(_ruf_label, Color(1.8, 1.8, 1.8))


func _flash_label(l: Control, col: Color) -> void:
	l.modulate = col
	create_tween().tween_property(l, "modulate", Color.WHITE, 0.45)


func _pop(l: Control, amt: float) -> void:
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(amt, amt)
	create_tween().tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Animierter Spiel-Schriftzug: geprägter VT323-Text + Copper-Streifen + Puls.
class _Logo extends Control:
	var _t := 0.0
	var _font: Font = load("res://assets/fonts/VT323_UI.ttf")

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := Loc.t("ui.title_screen.sommer_90", "SOMMER '90")
		var fs := 26
		var tw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2((size.x - tw.x) * 0.5, size.y * 0.5 + fs * 0.34)
		# schmaler Copper-Streifen unter dem Schriftzug (Amiga-Gruß)
		var n := 60
		for i in n:
			var f := float(i) / n
			var ph := 0.5 + 0.5 * sin(TAU * (f * 1.6 - _t * 0.35))
			var c := Color(0.98, 0.62, 0.16).lerp(Color(0.82, 0.22, 0.5), ph)
			draw_rect(Rect2(pos.x + tw.x * f, pos.y + 5.0, tw.x / n + 1.0, 3.0), Color(c, 0.7))
		# geprägter Text: Schatten · Basis (pulsierend) · Glanzkante
		draw_string(_font, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		var pulse := 0.5 + 0.5 * sin(_t * 1.6)
		var main := Color(0.96, 0.66, 0.22).lerp(Color(1.0, 0.82, 0.42), pulse * 0.6)
		draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, main)
		draw_string(_font, pos + Vector2(0, -1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.72, 0.45))


func _add_level_header_dot(panel: Dictionary) -> void:
	var vbox := panel["root"].get_child(0) as VBoxContainer
	var header := vbox.get_child(0) as Label
	vbox.remove_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_child(header)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	var dot := HudDot.new()
	dot.custom_minimum_size = Vector2(8, 8)
	header_row.add_child(dot)
	vbox.add_child(header_row)
	vbox.move_child(header_row, 0)


func _format_dm(amount: int) -> String:
	var digits := str(amount)
	var formatted := ""
	while digits.length() > 3:
		formatted = ".%s%s" % [digits.right(3), formatted]
		digits = digits.left(digits.length() - 3)
	return "%s%s" % [digits, formatted]


## Ganze Pfennig → „1.234,56 DM" (Tausenderpunkte für den DM-Teil, Pfennig hinten).
func _money_text(pf: int) -> String:
	var neg := pf < 0
	pf = absi(pf)
	@warning_ignore("integer_division")  # DM-Teil per Ganzzahl-Division ist gewollt (exakt)
	var s := "%s,%02d DM" % [_format_dm(int(pf / 100.0)), pf % 100]
	return ("-" + s) if neg else s


class HudDot:
	extends Control

	func _draw() -> void:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.45, Palette.BLACK)


## Pulsierender roter Warn-Rahmen über dem „NÄCHSTES EVENT"-Panel (nur bei „heute").
class _EventPulse extends Control:
	var active := false:
		set(v):
			if v == active:
				return
			active = v
			set_process(v)
			queue_redraw()
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		set_process(false)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var p := 0.5 + 0.5 * sin(_t * 4.8)
		var edge := Color(0.95, 0.26, 0.2, 0.45 + 0.5 * p)
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), edge, false, 2.0 + 1.6 * p)
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)),
			Color(0.98, 0.34, 0.26, 0.12 * p), false, 2.0)
