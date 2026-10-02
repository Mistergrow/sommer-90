class_name TaskBoardWindow
extends RetroWindow
## Persönlicher Notizblock: eine organisierte, rein lesende Sicht auf die bereits
## persistent gespeicherten Daten von QuestManager, TaskManager und PhoneManager.
## Keine zweite Quest-/Aufgabenquelle und keine manuell driftenden Duplikate.

const PAPER := Color8(232, 224, 194)
const PAPER_DARK := Color8(211, 199, 160)
const INK := Color8(36, 52, 78)
const INK_DIM := Color8(83, 86, 82)
const INK_RED := Color8(151, 63, 58)
const INK_GREEN := Color8(48, 104, 70)
const PAPER_FONT := preload("res://assets/fonts/Topaz_a500_ui.ttf")
const DevelopmentGate := preload("res://scripts/core/development_gate.gd")


func _init() -> void:
	title = Loc.t("ui.task_board_window.notizblock", "NOTIZBLOCK")
	win_size = Vector2(720, 610)
	chrome_accent = Palette.LCD_AMBER


func _ready() -> void:
	super._ready()
	_connect_updates()
	_rebuild()


func _connect_updates() -> void:
	if not TaskManager.tasks_changed.is_connected(_rebuild):
		TaskManager.tasks_changed.connect(_rebuild)
	if not QuestManager.quests_changed.is_connected(_rebuild):
		QuestManager.quests_changed.connect(_rebuild)
	if not PhoneManager.messages_changed.is_connected(_rebuild):
		PhoneManager.messages_changed.connect(_rebuild)
	if not PhoneManager.phone_changed.is_connected(_rebuild):
		PhoneManager.phone_changed.connect(_rebuild)
	if not UIManager.info_logged.is_connected(_on_info_logged):
		UIManager.info_logged.connect(_on_info_logged)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)


func _on_info_logged(_text: String) -> void:
	_rebuild()


func _on_locale_changed(_locale: String) -> void:
	set_window_title(Loc.t("ui.task_board_window.notizblock", "NOTIZBLOCK"))
	call_deferred("_rebuild")


func _rebuild() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

	var summary := VBoxContainer.new()
	summary.name = "TaskBoardSummary"
	summary.add_theme_constant_override("separation", 2)
	var summary_main := HBoxContainer.new()
	summary_main.add_theme_constant_override("separation", 10)
	var season := Bezel.lcd_label(Loc.t("ui.task_board_window.notizen_sommer_02d", "NOTIZEN · SOMMER '%02d") % (TimeManager.year % 100), Palette.LCD_AMBER, 14)
	season.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_main.add_child(season)
	if DevelopmentGate.enabled():
		var playtest := make_button(Loc.t("ui.task_board_window.playtest", "PLAYTEST"), UIManager.open_playtest_report)
		playtest.custom_minimum_size.x = 92.0
		summary_main.add_child(playtest)
	summary.add_child(summary_main)
	var totals := Bezel.dim_label(Loc.t("ui.task_board_window.d_offen_d_erledigt_d_ruckruf", "%d offen · %d erledigt · %d Rückruf(e)") % [
		QuestManager.active_quests().size() + TaskManager.open_count(),
		QuestManager.done_count() + _done_tasks().size(),
		PhoneManager.pending_callbacks().size()], 10)
	totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	totals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(totals)
	content.add_child(summary)

	var paper_root := Control.new()
	paper_root.name = "TaskBoardPaper"
	paper_root.clip_contents = true
	paper_root.custom_minimum_size = Vector2(0, 482)
	paper_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(paper_root)
	var paper := _Paper.new()
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_root.add_child(paper)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	paper_root.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "TaskBoardScroll"
	scroll.clip_contents = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)

	_build_open_quests(list)
	_build_open_tasks(list)
	_build_phone_notes(list)
	_build_dates(list)
	_build_message_history(list)
	_build_done(list)

	var footer := Bezel.dim_label(Loc.t("ui.task_board_window.n_oder_klick_auf_infos_offnet", "N oder Klick auf INFOS öffnet diesen Notizblock · Änderungen werden automatisch nachgeführt"), 11)
	footer.name = "TaskBoardFooter"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(footer)


func _build_open_quests(list: VBoxContainer) -> void:
	var quests: Array = QuestManager.active_quests()
	_section(list, Loc.t("ui.task_board_window.open_quests", "OFFENE AUFTRÄGE"), quests.size(), INK_RED)
	if quests.is_empty():
		list.add_child(_paper_text(Loc.t("ui.task_board_window.no_active_quest",
			"Im Moment ist kein Auftrag aktiv."), INK_DIM, 13))
	for quest: Dictionary in quests:
		list.add_child(_quest_card(quest))


func _build_open_tasks(list: VBoxContainer) -> void:
	var open := _open_tasks()
	_section(list, Loc.t("ui.task_board_window.noted_tasks", "NOTIERTE AUFGABEN"), open.size(), INK)
	if open.is_empty():
		list.add_child(_paper_text(Loc.t("ui.task_board_window.no_noted_task",
			"Keine zusätzliche Aufgabe notiert."), INK_DIM, 13))
	for task: Dictionary in open:
		list.add_child(_task_card(task, false))


func _build_phone_notes(list: VBoxContainer) -> void:
	var pending := PhoneManager.pending_callbacks()
	var messages: Array = PhoneManager.messages
	_section(list, Loc.t("ui.task_board_window.calls_messages", "ANRUFE & NACHRICHTEN"),
		pending.size() + messages.size(), INK_RED)
	if pending.is_empty() and messages.is_empty():
		list.add_child(_paper_text(Loc.t("ui.task_board_window.no_calls_messages",
			"Keine Rückrufe oder AB-Nachrichten."), INK_DIM, 13))
	for entry: Dictionary in pending:
		var callback_title := Loc.t("ui.task_board_window.call_back", "[TEL] %s zurückrufen") \
			% str(entry.get("from", Loc.t("ui.task_board_window.unknown", "Unbekannt")))
		var note := str(entry.get("text", Loc.t("ui.task_board_window.parents_message",
			"Nachricht bei den Eltern hinterlassen.")))
		list.add_child(_note_card(callback_title, note,
			Loc.t("ui.task_board_window.callback", "RÜCKRUF"), INK_RED))
	for message: Dictionary in messages:
		var fresh := not bool(message.get("heard", false))
		var badge := Loc.t("ui.task_board_window.new_answering_machine", "NEU · AB") \
			if fresh else Loc.t("ui.task_board_window.answering_machine", "AB")
		list.add_child(_note_card("[TEL] %s" % str(message.get("from",
			Loc.t("ui.task_board_window.unknown", "Unbekannt"))),
			PhoneManager.localized_message_text(message), badge, INK_RED if fresh else INK_DIM))


func _build_dates(list: VBoxContainer) -> void:
	var dates := TaskManager.upcoming_fixed(14)
	var visible_dates: Array = []
	var seen := {}
	for event: Dictionary in dates:
		var badge := str(event.get("badge", "·"))
		if seen.has(badge) and badge in ["F", "C"]:
			continue
		seen[badge] = true
		visible_dates.append(event)
		if visible_dates.size() >= 4:
			break
	_section(list, Loc.t("ui.task_board_window.next_days", "DIE NÄCHSTEN TAGE"), visible_dates.size(), INK)
	for event: Dictionary in visible_dates:
		var badge := str(event.get("badge", "·"))
		var days := int(event.get("days", 0))
		var when := Loc.t("ui.task_board_window.today", "heute") if days == 0 else (
			Loc.t("ui.task_board_window.tomorrow", "morgen") if days == 1 else
			Loc.t("ui.task_board_window.in_days", "in %d Tagen") % days)
		list.add_child(_paper_text("[%s]  %s - %s (%d.%d.)" % [badge,
			str(event.get("title", "?")), when, int(event.get("day", 1)), int(event.get("month", 1))], INK, 13))


func _build_message_history(list: VBoxContainer) -> void:
	# Das HUD zeigt bewusst nur die neueste Meldung. Hier bleibt der komplette
	# kurze Sitzungsverlauf erreichbar, ohne wieder Kleinstschrift in die
	# permanent sichtbare Leiste zu quetschen.
	var messages: Array = UIManager.info_log
	_section(list, Loc.t("ui.task_board_window.message_history", "MELDUNGSVERLAUF"),
		messages.size(), INK)
	if messages.is_empty():
		list.add_child(_paper_text(Loc.t("ui.task_board_window.no_messages",
			"Noch keine Meldungen in dieser Sitzung."), INK_DIM, 12))
		return
	for index in messages.size():
		var prefix := "> " if index == 0 else "  "
		list.add_child(_paper_text(prefix + str(messages[index]),
			INK if index == 0 else INK_DIM, 12, true))


func _build_done(list: VBoxContainer) -> void:
	var quests := QuestManager.completed_quests()
	var tasks := _done_tasks()
	_section(list, Loc.t("ui.task_board_window.completed", "ERLEDIGT"),
		quests.size() + tasks.size(), INK_GREEN)
	if quests.is_empty() and tasks.is_empty():
		list.add_child(_paper_text(Loc.t("ui.task_board_window.completed_collect_here",
			"Hier werden abgeschlossene Aufträge gesammelt."), INK_DIM, 13))
	for quest: Dictionary in quests:
		list.add_child(_done_line(Loc.t("ui.task_board_window.completed_quest", "[X] Auftrag: %s") \
			% QuestManager.localized_title(str(quest.get("id", "")))))
	for task: Dictionary in tasks:
		list.add_child(_task_card(task, true))


func _section(parent: VBoxContainer, text: String, count: int, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := _paper_text(text, color, 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_paper_text(str(count), color, 14))
	parent.add_child(row)
	var line := HSeparator.new()
	line.add_theme_color_override("separator", Color(color, 0.35))
	parent.add_child(line)


func _quest_card(quest: Dictionary) -> Control:
	var qid := str(quest.get("id", ""))
	var stages: Array = quest.get("stages", [])
	var step := QuestManager.stage(qid)
	var badge := Loc.t("ui.task_board_window.step", "SCHRITT %d/%d") % [step + 1, stages.size()]
	if QuestManager.is_tutorial(qid):
		badge += Loc.t("ui.task_board_window.tutorial_suffix", " · TUTORIAL")
	var giver := ""
	if quest.has("giver"):
		giver = Loc.t("ui.task_board_window.from", "Von %s") % NPCManager.localized_name(str(quest["giver"]))
	var note := QuestManager.current_stage_text(qid)
	if step >= 0 and step < stages.size():
		var job_id := str((stages[step] as Dictionary).get("job_id", ""))
		if not job_id.is_empty():
			var appointment_job := JobManager.job_by_id(job_id)
			note += Loc.t("ui.task_board_window.appointment", "\nTERMIN: %s") % JobManager.appointment_text(appointment_job)
	if giver != "":
		note += "\n" + giver
	return _note_card("[>] " + QuestManager.localized_title(qid), note, badge, INK)


func _task_card(task: Dictionary, done: bool) -> Control:
	var card := _card_shell(INK_GREEN if done else INK)
	var box := card.get_child(0) as VBoxContainer
	if done:
		box.add_child(_done_line("[X] " + str(task.get("title", "?"))))
	else:
		box.add_child(_paper_text("[ ] " + str(task.get("title", "?")), INK, 14))
	var note := str(task.get("note", ""))
	if note != "":
		box.add_child(_paper_text(note, INK_DIM, 12, true))
	return card


func _note_card(title_text: String, note: String, badge: String, color: Color) -> Control:
	var card := _card_shell(color)
	var box := card.get_child(0) as VBoxContainer
	var head := HBoxContainer.new()
	var label := _paper_text(title_text, INK, 14)
	label.custom_minimum_size.x = 0.0
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(label)
	var badge_label := _paper_text(badge, color, 11)
	badge_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	badge_label.tooltip_text = badge
	head.add_child(badge_label)
	box.add_child(head)
	if note != "":
		box.add_child(_paper_text(note, INK_DIM, 12, true))
	return card


func _card_shell(color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.98, 0.88, 0.48)
	style.border_color = Color(color, 0.38)
	style.set_border_width_all(1)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	return card


func _paper_text(text: String, color: Color, size_px: int, wrap_lines := false) -> Label:
	var label := Label.new()
	label.text = _paper_safe(text)
	label.add_theme_font_override("font", PAPER_FONT)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap_lines else TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 0.0
	label.clip_text = not wrap_lines
	if not wrap_lines:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## Topaz A500 deckt bewusst nur den Amiga-/Latin-1-Zeichensatz ab. Narrative
## Texte dürfen typografisches Unicode enthalten; auf dem Papier werden bekannte
## Zeichen stilgerecht transliteriert und unbekannte Glyphen niemals als Tofu
## bzw. Hex-Code angezeigt.
func _paper_safe(text: String) -> String:
	var safe := text
	var replacements := {
		"—": "-", "–": "-", "−": "-",
		"→": "->", "➜": "->", "➔": "->",
		"←": "<-", "↔": "<->",
		"✓": "OK", "✔": "OK", "☑": "[X]", "☐": "[ ]",
		"◇": "*", "◆": "*", "□": "[ ]",
		"◁": "<", "▷": ">", "◄": "<", "►": ">",
		"★": "*", "☆": "*", "☎": "TEL",
		"„": "\"", "“": "\"", "”": "\"",
		"‚": "'", "‘": "'", "’": "'",
		"…": "...", "•": "*",
	}
	for source: String in replacements:
		safe = safe.replace(source, str(replacements[source]))
	var covered := ""
	for index in safe.length():
		var codepoint := safe.unicode_at(index)
		if codepoint == 10 or codepoint == 13 or codepoint == 9 \
				or (codepoint >= 32 and codepoint <= 255):
			covered += safe[index]
		else:
			covered += "?"
	return covered


func _done_line(text: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 0.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", PAPER_FONT)
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_color_override("default_color", INK_GREEN)
	var safe_text := _paper_safe(text)
	label.text = Loc.t("ui.task_board_window.s_s_s", "[s]%s[/s]") % safe_text.replace("[", "(").replace("]", ")")
	return label


func _open_tasks() -> Array:
	return TaskManager.tasks.filter(func(task: Dictionary) -> bool:
		return not bool(task.get("done", false)))


func _done_tasks() -> Array:
	return TaskManager.tasks.filter(func(task: Dictionary) -> bool:
		return bool(task.get("done", false)))


class _Paper extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), PAPER)
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), PAPER_DARK, false, 2.0)
		var y := 31.0
		while y < size.y - 8.0:
			draw_line(Vector2(8, y), Vector2(size.x - 8, y), Color(0.34, 0.55, 0.68, 0.20), 1.0)
			y += 24.0
		draw_line(Vector2(34, 8), Vector2(34, size.y - 8), Color(0.75, 0.24, 0.22, 0.36), 1.5)
