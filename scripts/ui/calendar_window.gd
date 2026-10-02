class_name CalendarWindow
extends RetroWindow
## WANDKALENDER — hängt im Zimmer an der Wand. Monatsraster mit den wichtigsten
## Terminen im Voraus: Flohmarkt (Sa), Club-Wettbewerb (Fr), Geburtstag,
## Heiligabend, Silvester. Heute ist markiert; ◀ ▶ blättert durch die Monate.
## Terminquelle: TaskManager.events_on (dieselbe wie das Aufgaben-Board).

var _view_year := 1990
var _view_month := 7
var _grid: GridContainer = null
var _head: Label = null


func _init() -> void:
	title = Loc.t("ui.calendar_window.wandkalender", "WANDKALENDER")
	win_size = Vector2(480, 460)


func _ready() -> void:
	super._ready()
	_view_year = TimeManager.year
	_view_month = TimeManager.month
	_build()


func _build() -> void:
	for c in content.get_children():
		c.queue_free()

	# Kopf: ◀ Monat Jahr ▶
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	content.add_child(head_row)
	head_row.add_child(make_button(Loc.t("ui.calendar_window.text", "◀"), _prev_month))
	_head = Bezel.lcd_label("", Palette.UI_TEXT, 15)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_row.add_child(_head)
	head_row.add_child(make_button(Loc.t("ui.calendar_window.text_dff5", "▶"), _next_month))

	# Wochentagszeile
	var wd_row := GridContainer.new()
	wd_row.columns = 7
	content.add_child(wd_row)
	for n in ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]:
		var l := Bezel.dim_label(n, 10)
		l.custom_minimum_size = Vector2(58, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wd_row.add_child(l)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_grid)

	content.add_child(Bezel.dim_label(
		Loc.t("ui.calendar_window.f_flohmarkt_c_club_wettbewerb_geburtstag", "F Flohmarkt · C Club-Wettbewerb · ★ Geburtstag · W Heiligabend · S Silvester"), 9))

	_fill()


func _prev_month() -> void:
	_view_month -= 1
	if _view_month < 1:
		_view_month = 12
		_view_year -= 1
	_clamp_view()
	_fill()


func _next_month() -> void:
	_view_month += 1
	if _view_month > 12:
		_view_month = 1
		_view_year += 1
	_clamp_view()
	_fill()


## Der Kalender reicht von Spielstart (Juli 1990) bis Ende 1999.
func _clamp_view() -> void:
	if _view_year < 1990:
		_view_year = 1990
		_view_month = 1
	if _view_year > 1999:
		_view_year = 1999
		_view_month = 12


func _fill() -> void:
	_head.text = Loc.t("ui.calendar_window.s_d", "%s %d") % [TimeManager.localized_month_name(_view_month), _view_year]
	for c in _grid.get_children():
		c.queue_free()

	var first_wd := TaskManager.weekday_of(_view_year, _view_month, 1)
	var days: int = TimeManager.days_in_month(_view_year, _view_month)   # 29. Februar im Schaltjahr
	for _i in first_wd:
		_grid.add_child(Control.new())   # Leerzellen vor dem 1.
	for d in range(1, days + 1):
		_grid.add_child(_day_cell(d))


func _day_cell(d: int) -> Control:
	var is_today: bool = (_view_year == TimeManager.year
		and _view_month == TimeManager.month and d == TimeManager.day)
	var events: Array = TaskManager.events_on(_view_year, _view_month, d)

	var cell := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(38, 30, 22) if is_today else Color8(26, 26, 30)
	sb.border_color = Color8(240, 160, 60) if is_today else Palette.UI_BORDER_DARK
	sb.set_border_width_all(2 if is_today else 1)
	sb.content_margin_left = 4; sb.content_margin_right = 4
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	cell.add_theme_stylebox_override("panel", sb)
	cell.custom_minimum_size = Vector2(58, 46)
	cell.tooltip_text = "\n".join(events.map(func(e: Dictionary) -> String: return str(e.get("title", ""))))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	cell.add_child(box)
	var num := Bezel.lcd_label(str(d), Color(1.0, 0.85, 0.4) if is_today else Palette.UI_TEXT, 12)
	box.add_child(num)
	if not events.is_empty():
		var badges := " ".join(events.map(func(e: Dictionary) -> String: return str(e.get("badge", "·"))))
		var b := Bezel.dim_label(badges, 10)
		b.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		box.add_child(b)
	return cell
