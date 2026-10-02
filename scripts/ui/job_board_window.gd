class_name JobBoardWindow
extends RetroWindow
## ARBEITSHEFT — kompakte, spieltypische Oberflaeche fuer bezahlte Arbeit.
##
## Links steht nur, was der Spieler am aktuellen Ort wirklich tun kann; rechts
## liegt ein kompakter Wegweiser fuer freigeschaltete Arbeit in der Stadt. Die
## Manager bleiben die einzige Autoritaet fuer Zeiten, Lohn und Quest-Gates.

const ROUTE_LIMIT := 8


func _init() -> void:
	title = Loc.t("ui.job_board_window.work_notebook_title", "ARBEITSHEFT · JOBS & HAUSARBEIT")
	win_size = Vector2(860, 570)
	chrome_accent = Palette.LCD_GREEN


func _ready() -> void:
	super._ready()
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	if not JobManager.jobs_changed.is_connected(_rebuild):
		JobManager.jobs_changed.connect(_rebuild)
	if not PlayerStats.stats_changed.is_connected(_rebuild):
		PlayerStats.stats_changed.connect(_rebuild)
	if not ChoreManager.chores_changed.is_connected(_rebuild):
		ChoreManager.chores_changed.connect(_rebuild)
	if not TimeManager.slot_changed.is_connected(_on_slot_changed):
		TimeManager.slot_changed.connect(_on_slot_changed)
	if not GameManager.location_changed.is_connected(_on_location_changed):
		GameManager.location_changed.connect(_on_location_changed)
	_rebuild()


func _on_locale_changed(_locale: String) -> void:
	set_window_title(Loc.t("ui.job_board_window.work_notebook_title",
		"ARBEITSHEFT · JOBS & HAUSARBEIT"))
	call_deferred("_rebuild")


func _on_slot_changed(_slot: int) -> void:
	_rebuild()


func _on_location_changed(_location_id: String) -> void:
	# Kurze Fahrten koennen im selben Zeitfenster enden und loesen dann bewusst
	# kein slot_changed aus. Das Arbeitsheft muss trotzdem sofort von Wegweiser
	# auf die am Ziel startbereite Schicht umschalten.
	_rebuild()


func _rebuild() -> void:
	for child: Node in content.get_children():
		child.queue_free()

	var location_id := GameManager.current_location_id
	var local_jobs: Array = JobManager.available(location_id)
	var chore_count := ChoreManager.available().size() if location_id == "room" else 0
	content.add_child(_build_dashboard(location_id, local_jobs.size() + chore_count))

	var workspace := HBoxContainer.new()
	workspace.name = "WorkPlannerColumns"
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 10)
	content.add_child(workspace)

	var local_section := _build_section(
		Loc.t("ui.job_board_window.today_here", "HEUTE & HIER"),
		GameManager.location_name(location_id), Palette.LCD_GREEN, 505.0)
	workspace.add_child(local_section.root)
	var local_list: VBoxContainer = local_section.list
	if location_id == "room":
		_add_chore_section(local_list)
		local_list.add_child(_rule(Palette.LCD_AMBER))
	_add_local_job_section(local_list, local_jobs)

	var route_section := _build_section(
		Loc.t("ui.job_board_window.work_routes", "ARBEITSWEGWEISER"),
		Loc.t("ui.job_board_window.route_subtitle", "Freigeschaltete Arbeit in der Stadt"),
		Palette.LCD_CYAN, 315.0)
	workspace.add_child(route_section.root)
	_add_route_section(route_section.list, location_id)


func _build_dashboard(location_id: String, available_count: int) -> Control:
	var panel := PanelContainer.new()
	panel.name = "WorkPlannerDashboard"
	panel.add_theme_stylebox_override("panel", _panel_style(
		Color8(13, 15, 18), Palette.UI_BORDER_DARK, 7.0, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(44, 44)
	icon_frame.add_theme_stylebox_override("panel", _panel_style(
		Color8(8, 10, 13), Palette.UI_BORDER_DARK, 4.0, 1))
	icon_frame.add_child(_icon("jobs", 32))
	row.add_child(icon_frame)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 1)
	identity.add_child(Bezel.lcd_label(
		Loc.t("ui.job_board_window.work_notebook", "ARBEITSHEFT"), Palette.LCD_AMBER, 15))
	identity.add_child(Bezel.dim_label(
		"%s · %s · %s" % [TimeManager.localized_weekday_name().to_upper(),
			TimeManager.localized_slot_name().to_upper(), GameManager.location_name(location_id).to_upper()], 9))
	row.add_child(identity)

	var energy := VBoxContainer.new()
	energy.custom_minimum_size.x = 120
	energy.add_theme_constant_override("separation", 2)
	energy.add_child(Bezel.dim_label(Loc.t("ui.job_board_window.energie_d", "ENERGIE · %d%%") % PlayerStats.energie, 10))
	var bar := Bezel.bar(Palette.LCD_AMBER, Vector2(120, 8))
	bar.value = PlayerStats.energie
	energy.add_child(bar)
	row.add_child(energy)
	row.add_child(_status_chip(Loc.t("ui.job_board_window.open_count", "%d OFFEN") % available_count,
		Palette.LCD_GREEN if available_count > 0 else Palette.UI_TEXT_DIM))
	return panel


func _build_section(title_text: String, subtitle: String, accent: Color,
		minimum_width: float) -> Dictionary:
	var root := PanelContainer.new()
	root.custom_minimum_size.x = minimum_width
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_stylebox_override("panel", _panel_style(
		Color8(12, 14, 17), Palette.UI_BORDER_DARK, 7.0, 1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	root.add_child(box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 7)
	box.add_child(title_row)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_row.add_child(title_box)
	title_box.add_child(Bezel.lcd_label(title_text, accent, 14))
	var sub := Bezel.dim_label(subtitle, 11)
	sub.clip_text = true
	title_box.add_child(sub)
	box.add_child(_rule(Palette.UI_BORDER))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)
	return {"root": root, "list": list}


func _add_chore_section(list: VBoxContainer) -> void:
	var remaining := ChoreManager.remaining_today()
	var header := HBoxContainer.new()
	header.add_child(Bezel.lcd_label(Loc.t("ui.job_board_window.home_notebook",
		"MAMAS NOTIZBUCH"), Palette.LCD_AMBER, 12))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_status_chip("%d/%d" % [remaining, ChoreManager.MAX_PER_DAY], Palette.LCD_AMBER))
	list.add_child(header)
	list.add_child(Bezel.dim_label(Loc.t("ui.job_board_window.home_notebook_hint",
		"Bezahlte Hausarbeit · direkt hier zu Hause erledigen"), 9))

	var chores: Array = ChoreManager.available()
	if chores.is_empty():
		var empty_text := Loc.t("ui.job_board_window.chores_done",
			"Für heute ist genug geholfen. Morgen liegen neue Aufgaben bereit.") if remaining <= 0 \
			else Loc.t("ui.job_board_window.no_chores", "Im Haushalt ist gerade nichts Dringendes zu tun.")
		list.add_child(_empty_card(empty_text, Palette.LCD_AMBER))
		return
	for chore: Dictionary in chores:
		list.add_child(_chore_card(chore))


func _add_local_job_section(list: VBoxContainer, jobs: Array) -> void:
	var header := HBoxContainer.new()
	header.add_child(Bezel.lcd_label(Loc.t("ui.job_board_window.local_jobs",
		"NEBENJOBS AN DIESEM ORT"), Palette.LCD_GREEN, 12))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_status_chip(str(jobs.size()), Palette.LCD_GREEN))
	list.add_child(header)
	if jobs.is_empty():
		list.add_child(_empty_card(Loc.t("ui.job_board_window.none_here",
			"Hier ist im Moment keine bezahlte Arbeit frei. Der Wegweiser zeigt passende Orte."), Palette.LCD_GREEN))
		return
	for job: Dictionary in jobs:
		list.add_child(_job_card(job))


func _add_route_section(list: VBoxContainer, current_location: String) -> void:
	list.add_child(Bezel.dim_label(Loc.t("ui.job_board_window.route_hint",
		"Nur freigeschaltete Möglichkeiten deiner aktuellen Spielphase."), 9))
	var jobs := _relevant_route_jobs(current_location)
	if jobs.is_empty():
		list.add_child(_empty_card(Loc.t("ui.job_board_window.no_routes",
			"Heute ist kein weiterer Arbeitsweg bekannt."), Palette.LCD_CYAN))
	else:
		for index: int in mini(jobs.size(), ROUTE_LIMIT):
			list.add_child(_route_card(jobs[index]))
		if jobs.size() > ROUTE_LIMIT:
			list.add_child(Bezel.dim_label(Loc.t("ui.job_board_window.more_routes",
				"%d weitere Möglichkeiten werden sichtbar, sobald sie relevant sind.") % (jobs.size() - ROUTE_LIMIT), 9))
	if current_location != "room":
		list.add_child(_rule(Palette.LCD_AMBER))
		var home := make_button(Loc.t("ui.job_board_window.chores_at_home",
			"BEZAHLTE HAUSARBEIT · ZU HAUSE"), UIManager.open_map)
		_style_action_button(home, Palette.LCD_AMBER)
		list.add_child(home)


func _relevant_route_jobs(current_location: String) -> Array:
	var result: Array = []
	for job: Dictionary in JobManager.all_jobs():
		var target := str(job.get("location", ""))
		if target.is_empty() or target == current_location:
			continue
		if TimeManager.year < int(job.get("year_from", 0)) or TimeManager.year > int(job.get("year_to", 9999)):
			continue
		if job.has("requires_flag") and not bool(GameManager.flags.get(str(job["requires_flag"]), false)):
			continue
		if job.has("requires_quest_active") and not QuestManager.is_active(str(job["requires_quest_active"])):
			continue
		if job.has("requires_quest_done") and not QuestManager.is_done(str(job["requires_quest_done"])):
			continue
		var preview: Dictionary = JobManager.route_preview(job, current_location)
		if not bool(preview.get("ok", false)):
			continue
		var routed_job := job.duplicate(true)
		routed_job["_route_preview"] = preview
		result.append(routed_job)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_minutes := int((a.get("_route_preview", {}) as Dictionary).get("minutes", 999999))
		var b_minutes := int((b.get("_route_preview", {}) as Dictionary).get("minutes", 999999))
		if a_minutes != b_minutes:
			return a_minutes < b_minutes
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	return result


func _chore_card(chore: Dictionary) -> Control:
	var card := _card_shell(Palette.LCD_AMBER, "Chore_%s" % str(chore.get("id", "")))
	var row := card.get_child(0) as HBoxContainer
	var kind := Bezel.lcd_label(Loc.t("ui.job_board_window.haus", "HAUS"), Palette.LCD_AMBER, 11)
	kind.custom_minimum_size.x = 42
	kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(kind)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	row.add_child(copy)
	copy.add_child(Bezel.lcd_label(ChoreManager.localized_field(chore, "label"), Palette.UI_TEXT, 13))
	var hint := Bezel.dim_label(ChoreManager.localized_field(chore, "hint"), 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(hint)
	copy.add_child(Bezel.dim_label(Loc.t("ui.job_board_window.energy_cost", "−%d ENERGIE") % int(chore.get("energy", 0)), 11))

	var action := VBoxContainer.new()
	action.custom_minimum_size.x = 102
	action.add_theme_constant_override("separation", 4)
	row.add_child(action)
	var reward := Bezel.lcd_label(Currency.format(float(chore.get("reward", 0.0))), Palette.LCD_AMBER, 13)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	action.add_child(reward)
	var chore_id := str(chore.get("id", ""))
	var button := make_button(Loc.t("ui.job_board_window.play_chore", "MINISPIEL STARTEN"),
		func() -> void: UIManager.open_household_sprint(chore_id))
	button.custom_minimum_size = Vector2(102, 26)
	_style_action_button(button, Palette.LCD_AMBER)
	action.add_child(button)
	return card


func _job_card(job: Dictionary) -> Control:
	var card := _card_shell(Palette.LCD_GREEN, "Job_%s" % str(job.get("id", "")))
	var row := card.get_child(0) as HBoxContainer
	var kind := Bezel.lcd_label(Loc.t("ui.job_board_window.job", "JOB"), Palette.LCD_GREEN, 11)
	kind.custom_minimum_size.x = 42
	kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(kind)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 1)
	row.add_child(copy)
	copy.add_child(Bezel.lcd_label(_job_text(job, "name", "Job"), Palette.UI_TEXT, 13))
	var description := Bezel.dim_label(_job_text(job, "desc", ""), 12)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(description)
	copy.add_child(Bezel.dim_label(Loc.t("ui.job_board_window.job_cost_minutes",
		"−%d ENERGIE · %d MINUTEN") % [int(job.get("energy", 0)), JobManager.duration_minutes(job)], 9))

	var action := VBoxContainer.new()
	action.custom_minimum_size.x = 112
	action.add_theme_constant_override("separation", 4)
	row.add_child(action)
	var pay: Array = job.get("pay", [0, 0])
	var reward := Bezel.lcd_label(Loc.t("ui.job_board_window.d_d_dm", "%d–%d DM") % [int(pay[0]), int(pay[1])], Palette.LCD_AMBER, 13)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	action.add_child(reward)
	var check: Dictionary = JobManager.can_do(job)
	if bool(check.get("ok", false)):
		var button := _job_action_button(job)
		_style_action_button(button, Palette.LCD_GREEN)
		action.add_child(button)
	else:
		var reason := Bezel.dim_label(str(check.get("reason", "")), 11)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.add_theme_color_override("font_color", Palette.LCD_AMBER)
		action.add_child(reason)
	return card


func _job_action_button(job: Dictionary) -> Button:
	var job_id := str(job.get("id", ""))
	match str(job.get("minigame", "")):
		"cable_untangle":
			return make_button(Loc.t("ui.job_board_window.open_job", "AUFTRAG STARTEN"),
				func() -> void: UIManager.open_cable_untangle(job_id))
		"hardware_assembly":
			return make_button(Loc.t("ui.job_board_window.open_job", "AUFTRAG STARTEN"),
				func() -> void: UIManager.open_hardware_assembly(job_id))
		"shop_diagnosis":
			return make_button(Loc.t("ui.job_board_window.open_job", "AUFTRAG STARTEN"),
				func() -> void: UIManager.open_shop_diagnosis(job_id))
		"job_shift":
			return make_button(Loc.t("ui.job_board_window.open_shift", "SCHICHT STARTEN"),
				func() -> void: UIManager.open_job_shift(job_id))
	return make_button(Loc.t("ui.job_board_window.do_job", "JOB ERLEDIGEN"), func() -> void:
		var result: Dictionary = JobManager.do_job(job_id)
		UIManager.toast(str(result.get("text", ""))))


func _route_card(job: Dictionary) -> Control:
	var target := str(job.get("location", ""))
	var preview: Dictionary = job.get("_route_preview", JobManager.route_preview(job,
		GameManager.current_location_id))
	var ready_on_arrival := bool(preview.get("ok", false))
	var accent := Palette.LCD_GREEN if ready_on_arrival else Palette.LCD_CYAN
	var card := PanelContainer.new()
	card.name = "Route_%s" % str(job.get("id", ""))
	card.add_theme_stylebox_override("panel", _panel_style(
		Color8(16, 18, 21), Palette.UI_BORDER_DARK, 5.0, 1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title_label := Bezel.lcd_label(_job_text(job, "name", "Job"), Palette.UI_TEXT, 11)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	head.add_child(title_label)
	var pay: Array = job.get("pay", [0, 0])
	head.add_child(Bezel.lcd_label("%d–%d" % [int(pay[0]), int(pay[1])], Palette.LCD_AMBER, 11))
	var mode := str(preview.get("mode", "bike"))
	var route_minutes := int(preview.get("travel_minutes", preview.get("minutes", 0)))
	box.add_child(Bezel.lcd_label(Loc.t("ui.job_board_window.ready_on_arrival",
		"BEI ANKUNFT VERFÜGBAR · %s · %d MIN.") % [_route_mode_name(mode), route_minutes]
		if ready_on_arrival else _schedule_text(job), accent, 10))
	var job_id := str(job.get("id", ""))
	var route := make_button(Loc.t("ui.job_board_window.karte_s", "KARTE · %s  ›") % GameManager.location_name(target).to_upper(),
		func() -> void: UIManager.open_map(target, mode, job_id))
	route.name = "OpenRoute_%s" % str(job.get("id", ""))
	route.alignment = HORIZONTAL_ALIGNMENT_LEFT
	route.custom_minimum_size.y = 26
	route.tooltip_text = Loc.t("ui.job_board_window.open_map", "Stadtkarte öffnen")
	box.add_child(route)
	return card


func _route_mode_name(mode: String) -> String:
	match mode:
		"walk": return Loc.t("ui.map_window.mode_walk_short", "ZU FUSS")
		"bike": return Loc.t("ui.map_window.mode_bike_short", "RAD")
		"bus": return Loc.t("ui.map_window.mode_bus_short", "BUS")
		"car": return Loc.t("ui.map_window.mode_car_short", "AUTO")
	return mode.to_upper()


func _job_text(job: Dictionary, field: String, fallback: String) -> String:
	var job_id := str(job.get("id", ""))
	var source := str(job.get(field, fallback))
	if job_id.is_empty():
		return source
	return Loc.t("job.%s.%s" % [job_id, field], source)


func _schedule_text(job: Dictionary) -> String:
	var parts: Array[String] = []
	var days: Array = job.get("days", [])
	for day_key: Variant in days:
		var index := JobManager.DAY_KEYS.find(str(day_key))
		if index >= 0:
			parts.append(Loc.t("calendar.weekday.%d" % index,
				TimeManager.WEEKDAYS[index]).left(2).to_upper())
	var slots: Array = job.get("slots", [])
	var slot_names: Array[String] = []
	for raw_slot: Variant in slots:
		var index := clampi(int(raw_slot), 0, TimeManager.SLOT_NAMES.size() - 1)
		slot_names.append(Loc.t("calendar.slot.%d" % index,
			TimeManager.SLOT_NAMES[index]).to_upper())
	var day_text := "/".join(parts) if not parts.is_empty() else Loc.t("ui.job_board_window.daily", "TÄGLICH")
	var slot_text := "/".join(slot_names) if not slot_names.is_empty() else Loc.t("ui.job_board_window.all_day", "GANZTÄGIG")
	return "%s · %s" % [day_text, slot_text]


func _card_shell(accent: Color = Palette.UI_BORDER_DARK, node_name: String = "WorkCard") -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.add_theme_stylebox_override("panel", _panel_style(
		Color8(18, 20, 23), accent.darkened(0.68), 5.0, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	return card


func _empty_card(text_value: String, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(
		Color8(15, 17, 20), accent.darkened(0.62), 8.0, 1))
	var label := Bezel.dim_label(text_value, 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(label)
	return card


func _status_chip(text_value: String, accent: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(
		accent.darkened(0.82), accent.darkened(0.22), 4.0, 1))
	var label := Bezel.lcd_label(text_value, accent, 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _icon(kind: String, pixels: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Sprites.ui_icon(kind)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(pixels, pixels)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _rule(color: Color) -> HSeparator:
	var rule := HSeparator.new()
	var line := StyleBoxFlat.new()
	line.bg_color = color.darkened(0.55)
	line.content_margin_top = 1.0
	line.content_margin_bottom = 1.0
	rule.add_theme_stylebox_override("separator", line)
	return rule


func _style_action_button(button: Button, accent: Color) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 26.0)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", Color.WHITE)


func _panel_style(background: Color, border: Color, margin: float,
		border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style
