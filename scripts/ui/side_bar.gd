class_name SideBar
extends Control
## Linke Navigationsleiste: ZIMMER, INVENTAR, DISKETTEN, KONTAKTE, POSTKASTEN,
## AUFGABEN, ORTE, MODEM, JOBS und OPTIONEN — mit einer geschlossenen
## AGA-Pixelicon-Familie. Ganz oben
## erscheint kontextuell der AUFSTEHEN-Knopf, wenn man am Computer sitzt.

var _standup_btn: Button = null
var _nav_buttons: Dictionary = {}
var _job_badge: Label = null
var _seen_job_keys: Dictionary = {}
var _job_alert_active := false
var _job_alert_time := 0.0


func _ready() -> void:
	clip_contents = true
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Bezel.panel_box())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6
	vbox.offset_right = -6
	vbox.offset_top = 28
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Kontextueller AUFSTEHEN-Knopf ganz oben — nur sichtbar, wenn man am Computer
	# sitzt (Vollbild-Programm läuft). Ersetzt das frühere schwebende Overlay.
	_standup_btn = Button.new()
	_standup_btn.name = "StandUpButton"
	_standup_btn.text = Loc.t("ui.side_bar.aufstehen", "↑  AUFSTEHEN")
	_standup_btn.add_theme_font_size_override("font_size", 12)
	_standup_btn.add_theme_color_override("font_color", Color8(244, 226, 168))
	_standup_btn.add_theme_color_override("font_hover_color", Color8(255, 244, 200))
	_standup_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_standup_btn.clip_text = true
	_standup_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_standup_btn.custom_minimum_size = Vector2(0, 38)
	_standup_btn.focus_mode = Control.FOCUS_NONE
	_standup_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var su_norm := StyleBoxFlat.new()
	su_norm.bg_color = Color8(40, 36, 22, 235)
	su_norm.set_border_width_all(2)
	su_norm.border_color = Color8(232, 196, 110)
	su_norm.set_corner_radius_all(4)
	su_norm.content_margin_left = 8
	su_norm.content_margin_right = 8
	su_norm.content_margin_top = 4
	su_norm.content_margin_bottom = 4
	var su_hover := su_norm.duplicate() as StyleBoxFlat
	su_hover.bg_color = Color8(58, 52, 30, 245)
	su_hover.border_color = Color8(255, 224, 150)
	_standup_btn.add_theme_stylebox_override("normal", su_norm)
	_standup_btn.add_theme_stylebox_override("hover", su_hover)
	_standup_btn.add_theme_stylebox_override("pressed", su_hover)
	_standup_btn.pressed.connect(func() -> void: UIManager.stand_up_from_computer())
	_standup_btn.visible = UIManager.at_computer
	vbox.add_child(_standup_btn)
	UIManager.seat_changed.connect(func(seated: bool) -> void:
		if is_instance_valid(_standup_btn):
			_standup_btn.visible = seated)

	_add_nav(vbox, "room", "ZIMMER", _go_home)
	_add_nav(vbox, "inventory", "INVENTAR", UIManager.open_inventory)
	_add_nav(vbox, "disk", "DISKETTEN", UIManager.open_diskbox, true)
	_add_nav(vbox, "contacts", "KONTAKTE", UIManager.open_contacts)
	_add_nav(vbox, "post", "POSTKASTEN", UIManager.open_postcards)
	_add_nav(vbox, "calendar", "AUFGABEN", UIManager.open_tasks)
	_add_nav(vbox, "map", "ORTE", UIManager.open_map)
	_add_nav(vbox, "modem", "MODEM", UIManager.open_bbs)
	_add_nav(vbox, "jobs", "JOBS", UIManager.open_jobs)
	_add_nav(vbox, "options", "OPTIONEN", UIManager.open_system_menu)
	_build_job_badge()
	Localization.locale_changed.connect(_refresh_locale)
	PostcardManager.postcards_changed.connect(_refresh_post_label)
	UIManager.jobs_opened.connect(_mark_jobs_seen)
	JobManager.jobs_changed.connect(_refresh_job_alert)
	ChoreManager.chores_changed.connect(_refresh_job_alert)
	TimeManager.slot_changed.connect(func(_slot: int) -> void: _refresh_job_alert())
	TimeManager.day_changed.connect(_refresh_job_alert)
	TimeManager.year_changed.connect(func(_year: int) -> void: _refresh_job_alert())
	GameManager.location_changed.connect(func(_location: String) -> void: _refresh_job_alert())
	GameManager.game_started.connect(_reset_job_attention)
	NPCManager.npcs_changed.connect(_refresh_job_alert)
	_refresh_locale("")
	_refresh_job_alert.call_deferred()


func _add_nav(parent: Control, icon_kind: String, text: String, callback: Callable,
		keep_computer_seat := false) -> void:
	var button := Button.new()
	button.text = text
	button.icon = Sprites.disk_icon(Palette.BLUE_MID) if icon_kind == "disk" else Sprites.ui_icon(icon_kind)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	button.add_theme_font_size_override("font_size", 12)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(0, 38)
	button.pressed.connect(func() -> void:
		if keep_computer_seat and UIManager.at_computer:
			callback.call()
		else:
			UIManager.navigate_from_hud(callback))
	parent.add_child(button)
	_nav_buttons[icon_kind] = button


func _refresh_locale(_locale: String) -> void:
	_standup_btn.text = Loc.t("ui.side_bar.aufstehen", "↑  AUFSTEHEN")
	var labels := {
		"room": Loc.t("ui.side_bar.room", "ZIMMER"),
		"inventory": Loc.t("ui.side_bar.inventory", "INVENTAR"),
		"disk": Loc.t("ui.side_bar.disks", "DISKETTEN"),
		"contacts": Loc.t("ui.side_bar.contacts", "KONTAKTE"),
		"post": Loc.t("ui.side_bar.post", "POSTKASTEN"),
		"calendar": Loc.t("ui.side_bar.tasks", "AUFGABEN"),
		"map": Loc.t("ui.side_bar.places", "ORTE"),
		"modem": Loc.t("ui.side_bar.modem", "MODEM"),
		"jobs": Loc.t("ui.side_bar.jobs", "JOBS"),
		"options": Loc.t("ui.side_bar.options", "OPTIONEN"),
	}
	for key: String in labels:
		if is_instance_valid(_nav_buttons.get(key)):
			(_nav_buttons[key] as Button).text = labels[key]
	_refresh_post_label()
	_refresh_job_alert()


## Kompakter AGA-Badge statt Textsalat im schmalen HUD. Der ganze Button pulst
## dezent, der Zaehler bleibt auch bei reduzierter Bewegung eindeutig sichtbar.
func _build_job_badge() -> void:
	var button := _nav_buttons.get("jobs") as Button
	if not is_instance_valid(button):
		return
	_job_badge = Label.new()
	_job_badge.name = "NewJobsBadge"
	_job_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_job_badge.offset_left = -25.0
	_job_badge.offset_top = 3.0
	_job_badge.offset_right = -3.0
	_job_badge.offset_bottom = 18.0
	_job_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_job_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_job_badge.add_theme_font_size_override("font_size", 10)
	_job_badge.add_theme_color_override("font_color", Color8(20, 17, 10))
	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = Palette.LCD_AMBER
	badge_box.border_color = Color8(255, 235, 150)
	badge_box.set_border_width_all(1)
	badge_box.set_corner_radius_all(4)
	_job_badge.add_theme_stylebox_override("normal", badge_box)
	_job_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_job_badge.visible = false
	button.add_child(_job_badge)
	set_process(true)


## Angebote werden pro Spieltag identifiziert. Ein bereits betrachteter Job
## blinkt beim blossen Ortswechsel nicht erneut; am naechsten Tag darf ein neuer
## bezahlter Einsatz dagegen wieder auffallen.
func _current_job_keys() -> Array[String]:
	var keys: Array[String] = []
	var day := int(TimeManager.day_counter)
	for job: Dictionary in JobManager.all_jobs():
		var location_id := str(job.get("location", ""))
		if location_id.is_empty() or not JobManager.offered_here(job, location_id):
			continue
		if not bool(JobManager.can_do(job).get("ok", false)):
			continue
		keys.append("job:%s:%d" % [str(job.get("id", "")), day])
	for chore: Dictionary in ChoreManager.available():
		keys.append("chore:%s:%d" % [str(chore.get("id", "")), day])
	keys.sort()
	return keys


func _refresh_job_alert() -> void:
	if not is_instance_valid(_job_badge):
		return
	var unseen := 0
	for key: String in _current_job_keys():
		if not _seen_job_keys.has(key):
			unseen += 1
	_job_alert_active = unseen > 0
	_job_badge.visible = _job_alert_active
	_job_badge.text = str(unseen) if unseen < 10 else "9+"
	var button := _nav_buttons.get("jobs") as Button
	if is_instance_valid(button):
		if _job_alert_active:
			button.tooltip_text = Loc.t("ui.side_bar.jobs_new", "%d neue bezahlte Aufgabe(n) · öffnen, um sie anzusehen") % unseen
		else:
			button.tooltip_text = Loc.t("ui.side_bar.jobs_seen", "Nebenjobs und bezahlte Hausarbeit")
	if not _job_alert_active:
		_job_alert_time = 0.0
		if is_instance_valid(button):
			button.modulate = Color.WHITE


func _mark_jobs_seen() -> void:
	for key: String in _current_job_keys():
		_seen_job_keys[key] = true
	_refresh_job_alert()


func _reset_job_attention() -> void:
	_seen_job_keys.clear()
	_refresh_job_alert.call_deferred()


func _process(delta: float) -> void:
	if not _job_alert_active:
		return
	var button := _nav_buttons.get("jobs") as Button
	if not is_instance_valid(button):
		return
	if bool(SettingsManager.value("reduced_motion")):
		button.modulate = Color8(255, 224, 142)
		return
	_job_alert_time += delta
	var glow := 0.5 + 0.5 * sin(_job_alert_time * 5.0)
	button.modulate = Color(1.0, lerpf(0.78, 1.0, glow), lerpf(0.42, 0.82, glow), 1.0)


## Der Postkasten ist eine Hauptfunktion, kein versteckter Kontakt-Unterpunkt.
## Neue Karten werden direkt in der Navigation lesbar, ohne ein zweites Fenster
## oeffnen zu muessen.
func _refresh_post_label() -> void:
	var button := _nav_buttons.get("post") as Button
	if not is_instance_valid(button):
		return
	var unread := PostcardManager.unread_count()
	var base := Loc.t("ui.side_bar.post", "POSTKASTEN")
	button.text = "%s  · %d" % [base, unread] if unread > 0 else base
	button.tooltip_text = (Loc.t(
		"ui.side_bar.post_unread",
		"%d ungelesene Postkarte(n)") % unread) if unread > 0 else Loc.t(
		"ui.side_bar.post_empty",
		"Postkarten lesen und beantworten")


func _go_home() -> void:
	GameManager.goto_location("room")
