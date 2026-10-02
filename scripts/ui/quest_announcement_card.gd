extends Control
## Nicht blockierende Missionskarte im Stil eines kurzen Amiga-Szene-Intros.
## Die eigentlichen Effektgeneratoren kommen aus SceneSignalStrip; diese Klasse
## verantwortet nur lesbares Layout, Raster-Reveal, Lebenszeit und Abschluss-
## Partikel. Dadurch bleibt der Look fuer alle Quests identisch wartbar.

signal finished

const SceneSignalStripScript := preload("res://scripts/ui/scene_signal_strip.gd")
const Catalog := preload("res://scripts/ui/quest_presentation_catalog.gd")

var _event: Dictionary = {}
var _style: Dictionary = {}
var _font: Font = load("res://assets/fonts/VT323_UI.ttf")
var _strip: Control
var _header: Label
var _progress: Label
var _year: Label
var _body_panel: PanelContainer
var _body: Label
var _detail: Label
var _reveal: _RasterReveal
var _t := 0.0
var _duration := 3.6
var _reduced_motion := false
var _base_position := Vector2.ZERO
var _did_finish := false


func configure(event: Dictionary, visual_style: Dictionary = {}) -> void:
	_event = event.duplicate(true)
	_style = visual_style.duplicate(true) if not visual_style.is_empty() else Catalog.style_for(event)


func set_base_position(value: Vector2) -> void:
	_base_position = value.floor()
	position = _base_position


func event_data() -> Dictionary:
	return _event.duplicate(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Auch Schatten und Raster-Reveal gehoeren zur zugeteilten Kartenflaeche.
	# Der fruehere Schatten begann innerhalb der Karte, verwendete aber nochmals
	# die volle Kartengroesse und ragte rechts/unten ueber jeden Rahmen hinaus.
	clip_contents = true
	if _style.is_empty():
		_style = Catalog.style_for(_event)
	_duration = float(_style.get("duration", 3.6))
	_reduced_motion = bool(SettingsManager.value("reduced_motion"))
	_build()
	set_process(true)
	queue_redraw()


func _build() -> void:
	_strip = SceneSignalStripScript.new()
	_strip.effect = str(_style.get("effect", "copper"))
	_strip.caption = str(_style.get("caption", Loc.t(
		"ui.quest_announcement_card.mission", "AUFTRAG")))
	_strip.subtitle = str(_style.get("subtitle", Loc.t(
		"ui.quest_announcement_card.mission_signal", "MISSIONSSIGNAL")))
	_strip.alert = true
	_strip.compact = false
	_strip.music_reactive = false
	_strip.set("detail_level", int(_style.get("detail_level", 1)))
	_strip.set("redraw_hz", float(_style.get("redraw_hz", 25.0)))
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)

	_header = _label(str(_style.get("kicker", Loc.t(
		"ui.quest_announcement_card.mission", "AUFTRAG"))), 16,
		_style.get("accent", Color8(255, 174, 42)))
	_header.name = "QuestKicker"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_header)

	_progress = _label(str(_style.get("progress", "--/--")), 16,
		Color8(230, 237, 226))
	_progress.name = "QuestProgress"
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_progress)

	var year_number := int(_style.get("year", 0))
	var generation := str(_style.get("generation", "OCS"))
	_year = _label((Loc.t("ui.quest_announcement_card.summer_generation",
		"SOMMER '%02d · %s") % [posmod(year_number, 100), generation])
		if year_number > 0 else Loc.t("ui.quest_announcement_card.scene_signal",
			"SZENE-SIGNAL"),
		13, Color8(133, 164, 178))
	_year.name = "QuestGeneration"
	_year.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_year)

	_body_panel = PanelContainer.new()
	_body_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_panel.clip_contents = true
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = Color8(8, 13, 20, 244)
	body_style.border_color = Color(_style.get("accent", Color8(255, 174, 42)), 0.56)
	body_style.set_border_width_all(1)
	body_style.content_margin_left = 14.0
	body_style.content_margin_right = 14.0
	body_style.content_margin_top = 5.0
	body_style.content_margin_bottom = 5.0
	_body_panel.add_theme_stylebox_override("panel", body_style)
	add_child(_body_panel)

	var copy_stack := VBoxContainer.new()
	copy_stack.add_theme_constant_override("separation", -2)
	copy_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_panel.add_child(copy_stack)

	_body = _label("%s %s" % [str(_style.get("delivery_marker", ">")),
		str(_style.get("body", ""))], 16, Color8(222, 231, 224))
	_body.autowrap_mode = TextServer.AUTOWRAP_OFF
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body.max_lines_visible = 1
	copy_stack.add_child(_body)

	_detail = _label(str(_style.get("detail", "")), 13,
		Color8(117, 202, 218))
	_detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail.max_lines_visible = 1
	_detail.visible = not _detail.text.is_empty()
	copy_stack.add_child(_detail)

	_reveal = _RasterReveal.new()
	_reveal.accent = _style.get("accent", Color8(255, 174, 42))
	_reveal.completed = bool(_style.get("completed", false)) and not _reduced_motion
	_reveal.spark_count = int(_style.get("spark_count", 14))
	_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reveal)
	_layout()
	SettingsManager.settings_changed.connect(_on_settings_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout()


func _layout() -> void:
	if _strip == null:
		return
	var inner_width := maxf(64.0, size.x - 14.0)
	_strip.position = Vector2(7, 28)
	_strip.size = Vector2(inner_width, 76)
	_header.position = Vector2(13, 4)
	# Feste, nicht ueberlappende Header-Spalten: Auftrag | Jahr/Chipset |
	# Fortschritt. Besonders die minimale Kartenbreite 680 px liess die alte
	# Prozentbreite unter die beiden rechten Labels laufen.
	_header.size = Vector2(maxf(80.0, size.x - 395.0), 22)
	_progress.position = Vector2(size.x - 118, 4)
	_progress.size = Vector2(105, 22)
	_year.position = Vector2(size.x - 315, 5)
	_year.size = Vector2(185, 20)
	_body_panel.position = Vector2(7, 108)
	_body_panel.size = Vector2(inner_width, 57)
	_reveal.position = Vector2.ZERO
	_reveal.size = size


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 0.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_settings_changed() -> void:
	_reduced_motion = bool(SettingsManager.value("reduced_motion"))
	if _strip != null:
		_strip.set_process(not _reduced_motion)
	_reveal.completed = bool(_style.get("completed", false)) and not _reduced_motion
	queue_redraw()


func _process(delta: float) -> void:
	# Vollbild-Amigaspiele blenden die gesamte Juice-Ebene aus. In dieser Zeit
	# bleibt die Karte stehen und erscheint erst nach Rueckkehr ins Zimmer.
	if not is_visible_in_tree():
		return
	_t += delta
	var entry_time := 0.10 if _reduced_motion else 0.34
	var exit_time := 0.12 if _reduced_motion else 0.40
	var appear := clampf(_t / entry_time, 0.0, 1.0)
	var exit := clampf((_t - (_duration - exit_time)) / exit_time, 0.0, 1.0)
	modulate.a = appear * (1.0 - exit)
	var slide: float = 0.0 if _reduced_motion else roundf((1.0 - appear) * 42.0 - exit * 34.0)
	position = _base_position + Vector2(slide, 0)
	_reveal.reveal = appear
	_reveal.exit = exit
	_reveal.time = _t
	_reveal.queue_redraw()
	queue_redraw()
	if _t >= _duration and not _did_finish:
		_did_finish = true
		set_process(false)
		finished.emit()
		queue_free()


func _draw() -> void:
	var accent: Color = _style.get("accent", Color8(255, 174, 42))
	# Zweistufiger Hardware-Bezel mit einem echten dunklen Abstand zwischen den
	# Linien; dadurch bleibt die Karte auf hellen wie dunklen Orten lesbar.
	draw_rect(Rect2(8, 9, maxf(0.0, size.x - 8.0),
		maxf(0.0, size.y - 9.0)), Color(0, 0, 0, 0.48))
	draw_rect(Rect2(Vector2.ZERO, size), Color8(10, 13, 18, 248))
	draw_rect(Rect2(Vector2.ZERO, size), Color(accent, 0.94), false, 2.0)
	draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), Color8(68, 80, 88), false, 1.0)
	draw_rect(Rect2(7, 28, size.x - 14, 2), Color(accent, 0.84))
	for index in 6:
		var x := 13.0 + index * 9.0
		draw_rect(Rect2(x, size.y - 5, 5, 2), Color(accent, 0.35 + index * 0.08))
	# Ein kurzer Copper-Sweep laeuft nur am Kartenboden und verdeckt nie Text.
	if not _reduced_motion:
		var sweep_x := fposmod(_t * 210.0, maxf(1.0, size.x + 80.0)) - 40.0
		draw_rect(Rect2(sweep_x, size.y - 3, 38, 1), Color(accent, 0.88))


## Oberste, rein zeichnende Ebene: segmentierter Raster-Reveal und bei einem
## Abschluss ein begrenzter Bob-/Pixel-Burst. Sie blockiert keinerlei Eingabe.
class _RasterReveal extends Control:
	var accent := Color8(255, 174, 42)
	var completed := false
	var spark_count := 14
	var reveal := 0.0
	var exit := 0.0
	var time := 0.0

	func _draw() -> void:
		var closed := maxf(1.0 - reveal, exit)
		var bands := 12
		var band_height := size.y / float(bands)
		for band in bands:
			var stagger := float((band * 5) % 7) * 0.018
			# Der Zeilenversatz darf nur waehrend des Ein-/Ausflugs existieren.
			# Ein konstantes `closed + stagger` liess am Ende schwarze Restkeile
			# stehen und konnte Header oder Fortschritt dauerhaft anschneiden.
			var local_closed := clampf(
				closed + stagger * sin(clampf(closed, 0.0, 1.0) * PI),
				0.0, 1.0)
			var cover_width := ceilf(size.x * 0.5 * local_closed)
			var y := floorf(band * band_height)
			draw_rect(Rect2(0, y, cover_width, ceil(band_height) + 1), Color8(3, 7, 13))
			draw_rect(Rect2(size.x - cover_width, y, cover_width, ceil(band_height) + 1), Color8(3, 7, 13))
			if cover_width > 1.0 and local_closed < 0.98:
				draw_rect(Rect2(cover_width, y, 1, ceil(band_height)), Color(accent, 0.72))
				draw_rect(Rect2(size.x - cover_width - 1, y, 1, ceil(band_height)), Color(accent, 0.72))
		# Dezente globale CRT-Zeilen binden Rahmen, Text und Effekt zusammen.
		for y in range(2, int(size.y), 4):
			draw_line(Vector2(2, y), Vector2(size.x - 2, y), Color(0, 0, 0, 0.10), 1.0)
		if completed and reveal >= 0.99 and exit <= 0.01:
			for index in spark_count:
				var phase := time * (1.8 + float(index % 4) * 0.17) + index * 1.73
				var radius := 28.0 + fposmod(time * 54.0 + index * 19.0, 118.0)
				var center := Vector2(size.x * 0.5, size.y * 0.52)
				var point := center + Vector2(cos(phase), sin(phase) * 0.42) * radius
				var alpha := 0.28 + 0.34 * (0.5 + 0.5 * sin(phase * 1.7))
				draw_rect(Rect2(point.floor(), Vector2(2 + index % 2, 2)), Color(accent, alpha))
