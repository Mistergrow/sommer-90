class_name BottomBar
extends Control
## Untere Leiste: SCHNELLAUSWAHL (wertvollste Disketten), kompaktes LAGER,
## breiter klickbarer INFOS-Ticker und ganz rechts STATUS.

var _quick_row: HBoxContainer
var _stock_row: HBoxContainer
var _tired_bar: HudBar
var _hunger_bar: HudBar
var _clean_bar: HudBar          # SAUBERKEIT = RoomManager.cleanliness() (Zimmer-Ordnung)
var _info_click: PanelContainer
const HudEventCardScript := preload("res://scripts/ui/hud_event_card.gd")
const QuestPresentationCatalog := preload("res://scripts/ui/quest_presentation_catalog.gd")

var _event_card: Control
var _stock_prev := {}         # letzte LAGER-Mengen je Zeile → Pop bei Änderung
var _stock_ready := false
var _stock_signature := ""
var _quick_prev := {}         # zuletzt gezeigte Disketten-UIDs → Glitzer bei Neuzugang
var _quick_ready := false
var _quick_signature := ""
var _notebook_seen := ""
var _notebook_ready := false
var _quest_preview: Dictionary = {}
var _quest_preview_timer: Timer
var _headers: Dictionary = {}
var _status_labels: Array[Label] = []


func _ready() -> void:
	clip_contents = true
	_build()
	_quest_preview_timer = Timer.new()
	_quest_preview_timer.one_shot = true
	_quest_preview_timer.timeout.connect(_clear_quest_preview)
	add_child(_quest_preview_timer)
	DiskManager.disks_changed.connect(refresh)
	InventoryManager.inventory_changed.connect(refresh)
	PlayerStats.stats_changed.connect(refresh)
	RoomManager.room_changed.connect(refresh)   # SAUBERKEIT aktualisiert sich mit dem Müll
	UIManager.info_logged.connect(func(_t: String) -> void: _refresh_infos())
	SettingsManager.settings_changed.connect(_refresh_infos)
	UIManager.notebook_opened.connect(_mark_notebook_seen)
	TaskManager.tasks_changed.connect(_on_notebook_changed)
	QuestManager.quests_changed.connect(_on_notebook_changed)
	QuestManager.quest_event.connect(_on_quest_event)
	QuestManager.quest_presentation_reset.connect(_reset_quest_preview)
	PhoneManager.messages_changed.connect(_on_notebook_changed)
	PhoneManager.phone_changed.connect(_on_notebook_changed)
	GameManager.game_started.connect(refresh)
	Localization.locale_changed.connect(_refresh_locale)
	refresh()
	_notebook_seen = ""  # beim neuen Spiel darf der erste Auftrag als NEU auffallen
	_notebook_ready = true
	_refresh_notebook_badge()


func _build() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 3
	row.offset_right = -3
	row.offset_top = 3
	row.offset_bottom = -3
	row.add_theme_constant_override("separation", 5)
	add_child(row)

	# --- SCHNELLAUSWAHL: die 5 wertvollsten Disketten als Icons ---
	var quick_panel := Bezel.titled_panel(Loc.t("ui.bottom_bar.quick_select", "SCHNELLAUSWAHL"))
	_headers["quick"] = quick_panel["header"]
	quick_panel["root"].custom_minimum_size = Vector2(170, 0)
	_quick_row = HBoxContainer.new()
	_quick_row.add_theme_constant_override("separation", 3)
	quick_panel["body"].add_child(_quick_row)
	row.add_child(quick_panel["root"])

	# --- LAGER: Leerdisketten, Etiketten, Reinigungsdisk., Magazine ---
	var stock_panel := Bezel.titled_panel(Loc.t("ui.bottom_bar.stock", "LAGER"))
	_headers["stock"] = stock_panel["header"]
	# Fuenf echte Vorraete brauchen keine bildschirmbreite Leerflaeche. Kompakt
	# halten; der frei werdende Platz gehoert dem getrennten INFOS-Bereich.
	stock_panel["root"].custom_minimum_size = Vector2(350, 0)
	_stock_row = HBoxContainer.new()
	_stock_row.add_theme_constant_override("separation", 3)
	stock_panel["body"].add_child(_stock_row)
	row.add_child(stock_panel["root"])

	# --- STATUS: MÜDE / HUNGER / SAUBERKEIT ---
	var status_panel := Bezel.titled_panel(Loc.t("ui.bottom_bar.status", "STATUS"))
	_headers["status"] = status_panel["header"]
	status_panel["root"].custom_minimum_size = Vector2(188, 0)
	status_panel["body"].add_theme_constant_override("separation", 4)
	_tired_bar = _status_row(status_panel["body"], Loc.t("ui.bottom_bar.tired", "MÜDE"),
		Color8(236, 111, 28))
	_hunger_bar = _status_row(status_panel["body"], Loc.t("ui.bottom_bar.hunger", "HUNGER"),
		Palette.ORANGE)
	_hunger_bar.tooltip_text = Loc.t("ui.bottom_bar.hunger_tip",
		"Hunger steigt im Tagesverlauf. Essen und Getraenke senken ihn; eine richtige Mahlzeit saettigt staerker als ein Snack.")
	# Echte Zimmer-Ordnung: Konsumiertes (Dosen, Verpackungen) liegt rum → Sauberkeit
	# sinkt; Müll rausbringen / aufräumen hebt sie. Wert kommt aus dem RoomManager.
	_clean_bar = _status_row(status_panel["body"],
		Loc.t("ui.bottom_bar.cleanliness", "SAUBERKEIT"), Palette.GREEN_LIGHT)
	_clean_bar.tooltip_text = Loc.t("ui.bottom_bar.cleanliness_tip",
		"Ordnung im Zimmer. Leere Dosen, Verpackungen & Chips-Tüten liegen rum, bis du aufräumst — bring den Müll raus (Zimmer-Hotspot).")
	# STATUS wird erst nach INFOS eingehängt: finale Reihenfolge unten ist
	# SCHNELLAUSWAHL | LAGER | INFOS | STATUS.

	# --- NOTIZBOARD: genau eine Hierarchie statt INFOS / NOTIZBLOCK OEFFNEN /
	# NOTIZBOARD dreifach untereinander. Der Paneltitel benennt die Funktion, das
	# Display darunter zeigt nur Zustand und Aktion.
	var info_panel := Bezel.titled_panel(Loc.t("ui.bottom_bar.notebook",
		"NOTIZBOARD · AUFGABEN / ANRUFE / TERMINE"))
	_headers["info"] = info_panel["header"]
	info_panel["root"].custom_minimum_size = Vector2(360, 0)
	info_panel["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_click = PanelContainer.new()
	_info_click.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_click.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_click.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_click.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_info_click.tooltip_text = Loc.t("ui.bottom_bar.notebook_tip",
		"Notizblock öffnen: offene und erledigte Aufträge, Rückrufe und Termine")
	_info_click.add_theme_stylebox_override("panel", _info_click_style(false))
	_info_click.mouse_entered.connect(func() -> void:
		_info_click.add_theme_stylebox_override("panel", _info_click_style(true)))
	_info_click.mouse_exited.connect(func() -> void:
		_info_click.add_theme_stylebox_override("panel", _info_click_style(false)))
	_info_click.gui_input.connect(_on_info_input)
	var info_content := Control.new()
	info_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_content.custom_minimum_size = Vector2(0, 51)
	info_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_click.add_child(info_content)
	_event_card = HudEventCardScript.new()
	_event_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_event_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_content.add_child(_event_card)
	info_panel["body"].add_child(_info_click)
	row.add_child(info_panel["root"])
	row.add_child(status_panel["root"])


func _status_row(parent: Control, text: String, color: Color) -> HudBar:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var label := Bezel.dim_label(text, 11)
	_status_labels.append(label)
	label.add_theme_color_override("font_color", Palette.UI_TEXT)
	label.custom_minimum_size = Vector2(82, 0)
	hbox.add_child(label)
	# Gleicher Balken wie ENERGIE oben (HudBar), damit alle Balken identisch aussehen.
	var bar := HudBar.new()
	bar.custom_minimum_size = Vector2(76, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.fill_color = color
	hbox.add_child(bar)
	parent.add_child(hbox)
	return bar


func refresh() -> void:
	_refresh_quick()
	_refresh_stock()
	_tired_bar.value = 100 - PlayerStats.energie
	_hunger_bar.value = PlayerStats.hunger
	_clean_bar.value = RoomManager.cleanliness()
	_refresh_infos()


## Die 5 wertvollsten Disketten; Klick öffnet die Diskettenbox.
func _refresh_quick() -> void:
	# refresh() laeuft auch bei jeder Geld-/Energie-/Inventaraenderung. Marktwerte
	# daher einmal je Disk berechnen (nicht je Sortiervergleich) und die Buttons
	# nur neu bauen, wenn sich die sichtbaren Top 5 wirklich geaendert haben.
	var ranked: Array = []
	for disk: Disk in DiskManager.media_disks():
		ranked.append([disk.value(), disk])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var sorted: Array = []
	var signature := TranslationServer.get_locale()
	for i in mini(5, ranked.size()):
		var top: Disk = ranked[i][1]
		sorted.append(top)
		signature += "|%s:%s:%s:%s" % [top.uid, top.color, top.display_name(), top.condition_text()]
	if _quick_ready and signature == _quick_signature:
		return
	_quick_signature = signature
	for child in _quick_row.get_children():
		child.queue_free()
	var now_uids := {}
	for i in mini(5, sorted.size()):
		var disk: Disk = sorted[i]
		now_uids[disk.uid] = true
		var slot_wrap := VBoxContainer.new()
		slot_wrap.add_theme_constant_override("separation", 0)
		var slot := Button.new()
		slot.icon = Sprites.disk_icon(Palette.disk_color(disk.color))
		slot.expand_icon = true
		slot.add_theme_constant_override("icon_max_width", 28)
		slot.custom_minimum_size = Vector2(34, 31)
		slot.tooltip_text = Loc.t("ui.bottom_bar.s_s", "%s (%s)") % [disk.display_name(), disk.condition_text()]
		slot.pressed.connect(func() -> void:
			if UIManager.at_computer:
				UIManager.open_diskbox()
			else:
				UIManager.navigate_from_hud(UIManager.open_diskbox))
		slot_wrap.add_child(slot)
		var idx := Bezel.dim_label(str(i + 1), 10)
		idx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_wrap.add_child(idx)
		_quick_row.add_child(slot_wrap)
		# Neu ins Regal gewandert? Kurzer Funken-Glanz auf dem Icon.
		if _quick_ready and not _quick_prev.has(disk.uid):
			var glint := _Glint.new()
			slot.add_child(glint)
	_quick_prev = now_uids
	_quick_ready = true


func _refresh_stock() -> void:
	var counts := [DiskManager.blank_disks().size(), DiskManager.free_slots(),
		InventoryManager.count("etiketten"), InventoryManager.count("reinigungsdiskette"),
		InventoryManager.count("magazine")]
	var signature := "%s|%s" % [TranslationServer.get_locale(), counts]
	if _stock_ready and signature == _stock_signature:
		return
	_stock_signature = signature
	for child in _stock_row.get_children():
		child.queue_free()
	# NUR echte, im Spiel verwaltete Vorräte — jeder mit eigenem Icon (PNG aus
	# assets/ui/hud/, sonst prozeduraler Fallback). Die früheren Dauernull-Typen
	# (3.5 HD, 5.25, ZIP, CD-R) gab es nirgends im Inventar → entfernt.
	_add_stock(Loc.t("ui.bottom_bar.blank_disks", "Leerdisks"), counts[0],
		Sprites.hud_icon("disk_35_dd", Sprites.disk_icon(Palette.BLUE_MID)))
	_add_stock(Loc.t("ui.bottom_bar.free_slots", "Freie Plaetze"), counts[1],
		Sprites.hud_icon("sleeve", Sprites.disk_icon(Palette.GREY_LIGHT)))
	_add_stock(Loc.t("ui.bottom_bar.labels", "Etiketten"), counts[2],
		Sprites.hud_icon("etiketten", Sprites.ui_icon("inventory")))
	_add_stock(Loc.t("ui.bottom_bar.cleaning", "Reinigung"), counts[3],
		Sprites.hud_icon("reinigung", Sprites.disk_icon(Palette.GREEN_LIGHT)))
	_add_stock(Loc.t("ui.bottom_bar.magazines", "Magazine"), counts[4],
		Sprites.hud_icon("magazine", Sprites.ui_icon("inventory")))
	_stock_ready = true


func _add_stock(text: String, amount: int, icon: Texture2D) -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(61, 0)
	vbox.add_theme_constant_override("separation", 1)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Bezel.slot_box())
	panel.add_child(vbox)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	var icon_rect := TextureRect.new()
	icon_rect.texture = icon
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # sonst = 256px der echten PNGs
	icon_rect.custom_minimum_size = Vector2(30, 28)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon_rect)
	var amount_label := Bezel.lcd_label(str(amount), Palette.UI_TEXT, 10)
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(amount_label)
	# Menge verändert? Zahl poppt auf und blitzt (grün rauf / rot runter).
	var prev: Variant = _stock_prev.get(text)
	_stock_prev[text] = amount
	if _stock_ready and prev != null and int(prev) != amount:
		_pop_amount(amount_label, amount > int(prev))
	vbox.add_child(top)
	var label := Bezel.dim_label(text, 10)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(label)
	_stock_row.add_child(panel)


func _refresh_infos() -> void:
	_refresh_event_card()


func _info_click_style(hovered: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	# Kein zweiter Rahmen im bereits gerahmten INFOS-Panel. Nur eine sehr
	# leichte Hover-Flaeche signalisiert weiterhin, dass der Ticker klickbar ist.
	box.bg_color = Color8(24, 26, 30, 210) if hovered else Color8(12, 12, 12, 0)
	box.set_border_width_all(0)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _on_info_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_open_notebook()
		accept_event()


func _open_notebook() -> void:
	UIManager.navigate_from_hud(UIManager.open_tasks)


func _mark_notebook_seen() -> void:
	_notebook_seen = _notebook_signature()
	_refresh_notebook_badge()


func _on_notebook_changed() -> void:
	if QuestManager.active_quests().is_empty() and QuestManager.completed_quests().is_empty():
		_quest_preview.clear()
		if _quest_preview_timer != null:
			_quest_preview_timer.stop()
	if _notebook_ready:
		_refresh_notebook_badge()
	_refresh_infos()


func _on_quest_event(event: Dictionary) -> void:
	_quest_preview = QuestPresentationCatalog.style_for(event)
	_quest_preview["event"] = event.duplicate(true)
	_refresh_notebook_badge()
	_quest_preview_timer.start(float(_quest_preview.get("duration", 3.4)) + 0.65)


func _reset_quest_preview() -> void:
	_quest_preview.clear()
	if _quest_preview_timer != null:
		_quest_preview_timer.stop()
	if _notebook_ready:
		_refresh_notebook_badge()


func _clear_quest_preview() -> void:
	_quest_preview.clear()
	_refresh_notebook_badge()


func _refresh_notebook_badge() -> void:
	if _event_card == null:
		return
	var active := _notebook_signature() != _notebook_seen
	var count := _notebook_item_count()
	_event_card.call("set_badge",
		Loc.t("ui.bottom_bar.d_neu", "%d NEU") % maxi(1, count), active)
	_refresh_event_card(active, count)
	UIManager.set_notebook_attention(active, count)


func _refresh_event_card(active_override: Variant = null, count_override := -1) -> void:
	if _event_card == null:
		return
	var active: bool = _notebook_signature() != _notebook_seen \
		if active_override == null else bool(active_override)
	var count: int = _notebook_item_count() if count_override < 0 else count_override
	if not _quest_preview.is_empty():
		var event: Dictionary = _quest_preview.get("event", {})
		_event_card.call("set_content",
			str(_quest_preview.get("caption", QuestPresentationCatalog.preview_caption(event))),
			str(_quest_preview.get("subtitle",
				Loc.t("ui.bottom_bar.quest_updated", "AUFTRAG AKTUALISIERT"))),
			true, _quest_preview.get("accent", Color.TRANSPARENT))
		return
	var primary := ""
	if not UIManager.info_log.is_empty():
		primary = str(UIManager.info_log[0])
	elif active:
		primary = Loc.t("ui.bottom_bar.new_entries", "%d NEUE EINTRÄGE") % maxi(1, count)
	else:
		primary = Loc.t("ui.bottom_bar.overview_ready", "ÜBERSICHT BEREIT")
	var secondary := Loc.t("ui.bottom_bar.open_history",
		"%d OFFEN · KLICK FÜR VERLAUF") % count
	_event_card.call("set_content", primary, secondary, active)


func _refresh_locale(_locale: String) -> void:
	var values := {
		"quick": Loc.t("ui.bottom_bar.quick_select", "SCHNELLAUSWAHL"),
		"stock": Loc.t("ui.bottom_bar.stock", "LAGER"),
		"status": Loc.t("ui.bottom_bar.status", "STATUS"),
		"info": Loc.t("ui.bottom_bar.notebook",
			"NOTIZBOARD · AUFGABEN / ANRUFE / TERMINE"),
	}
	for key: String in values:
		if is_instance_valid(_headers.get(key)):
			(_headers[key] as Label).text = values[key]
	if _status_labels.size() == 3:
		_status_labels[0].text = Loc.t("ui.bottom_bar.tired", "MÜDE")
		_status_labels[1].text = Loc.t("ui.bottom_bar.hunger", "HUNGER")
		_status_labels[2].text = Loc.t("ui.bottom_bar.cleanliness", "SAUBERKEIT")
	_hunger_bar.tooltip_text = Loc.t("ui.bottom_bar.hunger_tip",
		"Hunger steigt im Tagesverlauf. Essen und Getraenke senken ihn; eine richtige Mahlzeit saettigt staerker als ein Snack.")
	_clean_bar.tooltip_text = Loc.t("ui.bottom_bar.cleanliness_tip",
		"Ordnung im Zimmer. Leere Dosen, Verpackungen & Chips-Tüten liegen rum, bis du aufräumst — bring den Müll raus (Zimmer-Hotspot).")
	_info_click.tooltip_text = Loc.t("ui.bottom_bar.notebook_tip",
		"Notizblock öffnen: offene und erledigte Aufträge, Rückrufe und Termine")
	refresh()
	_refresh_notebook_badge()


func _notebook_item_count() -> int:
	var count := QuestManager.active_quests().size() + TaskManager.open_count() + PhoneManager.pending_callbacks().size()
	for message: Dictionary in PhoneManager.messages:
		if not bool(message.get("heard", false)):
			count += 1
	return count


func _notebook_signature() -> String:
	var parts: Array[String] = []
	for q: Dictionary in QuestManager.active_quests():
		var qid := str(q.get("id", ""))
		parts.append("q:%s:%d" % [qid, QuestManager.stage(qid)])
	for q: Dictionary in QuestManager.completed_quests():
		parts.append("qd:" + str(q.get("id", "")))
	for task: Dictionary in TaskManager.tasks:
		parts.append("t:%s:%s" % [str(task.get("id", "")), str(task.get("done", false))])
	for message: Dictionary in PhoneManager.messages:
		parts.append("m:%s:%s" % [str(message.get("id", "")), str(message.get("heard", false))])
	for pending: Dictionary in PhoneManager.pending_callbacks():
		parts.append("p:" + str(pending.get("id", "")))
	parts.sort()
	return "|".join(parts)


## Lässt eine LAGER-Zahl aufpoppen und kurz farbig blitzen.
func _pop_amount(label: Label, up: bool) -> void:
	label.modulate = Palette.LCD_GREEN.lightened(0.3) if up else Color(1.7, 0.7, 0.6)
	create_tween().tween_property(label, "modulate", Color.WHITE, 0.5)
	# Pivot erst nach dem Layout setzen, damit von der Mitte skaliert wird.
	var pop := func() -> void:
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2(1.45, 1.45)
		create_tween().tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.call_deferred()


## Kurzer Funken-Glanz, wenn eine neue Diskette in die Schnellauswahl rutscht.
class _Glint extends Control:
	var _t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.9:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var a: float = clampf(1.0 - _t / 0.9, 0.0, 1.0)
		var c := size * 0.5
		var r := 4.0 + 11.0 * ease(clampf(_t / 0.5, 0.0, 1.0), 0.3)
		var col := Color(1.0, 0.95, 0.7, a)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 1.6, true)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 1.6, true)
		var r2 := r * 0.6
		draw_line(c - Vector2(r2, r2), c + Vector2(r2, r2), Color(col, a * 0.5), 1.0, true)
		draw_line(c - Vector2(-r2, r2), c + Vector2(-r2, r2), Color(col, a * 0.5), 1.0, true)
