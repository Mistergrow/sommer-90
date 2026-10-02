class_name FirstYearDemoFinale
extends Control
## Abschluss der eigenstaendigen itch.io-Demo.
##
## Die Scene-Praesentation bildet den emotionalen Abspann. Erst danach folgt
## die ruhige, klar bedienbare Angebotsseite. Dieser Screen committed niemals
## einen Kalenderwechsel; 1991 bleibt ausschliesslich der Vollversion vorbehalten.

signal return_to_title_requested

const ScenePresentation := preload("res://scripts/ui/scene_presentation_screen.gd")
const BuildChannel := preload("res://scripts/core/build_channel.gd")

var review: Dictionary = {}
var _presentation: Control
var _offer: Control
var _backdrop: Control
var _locale := "de"


func configure(review_data: Dictionary = {}) -> FirstYearDemoFinale:
	review = review_data.duplicate(true)
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_as_relative = false
	z_index = 900
	_locale = _locale_code()
	play_scene_finale()


func play_scene_finale() -> void:
	_clear_stage()
	_presentation = ScenePresentation.new()
	_presentation.name = "DemoSceneFinale"
	_presentation.call("configure", ScenePresentation.MODE_DEMO_FINALE)
	_presentation.finished.connect(show_offer, CONNECT_ONE_SHOT)
	add_child(_presentation)
	_presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_offer() -> void:
	_clear_stage()
	_build_offer()


func _clear_stage() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_presentation = null
	_offer = null
	_backdrop = null


func _build_offer() -> void:
	_backdrop = _DemoFinaleBackdrop.new()
	_backdrop.name = "DemoFinaleBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_offer = MarginContainer.new()
	_offer.name = "DemoPurchaseOffer"
	_offer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_offer.add_theme_constant_override("margin_left", 42)
	_offer.add_theme_constant_override("margin_right", 42)
	_offer.add_theme_constant_override("margin_top", 42)
	_offer.add_theme_constant_override("margin_bottom", 42)
	add_child(_offer)

	var center := CenterContainer.new()
	_offer.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "FinalePanel"
	panel.custom_minimum_size = Vector2(900, 610)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)

	var kicker := _label(_ui("DEMO-ABSCHLUSS · SIDE A COMPLETE", "DEMO FINALE · SIDE A COMPLETE"), 14, Color8(62, 213, 232))
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(kicker)
	var title := _label(_ui("DEIN SOMMER 1990 IST KOMPLETT", "YOUR SUMMER 1990 IS COMPLETE"), 31, Color8(255, 181, 48))
	title.name = "DemoFinaleTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	body.add_child(title)
	var subtitle := _label(_ui(
		"Du hast das vollstaendige erste Kapitel gespielt. Dein Spielstand bleibt erhalten.",
		"You played the complete first chapter. Your progress remains saved."), 16, Color8(220, 232, 232))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(subtitle)

	var separator := ColorRect.new()
	separator.color = Color(0.12, 0.75, 0.86, 0.56)
	separator.custom_minimum_size.y = 2
	body.add_child(separator)

	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 12)
	body.add_child(summary)
	_add_summary_card(summary, "1990", _ui("1 SOMMER", "1 SUMMER"), Color8(255, 181, 48))
	_add_summary_card(summary, str((review.get("milestones", []) as Array).size()), _ui("ERINNERUNGEN", "MEMORIES"), Color8(73, 223, 147))
	_add_summary_card(summary, "1991–99", _ui("VOLLVERSION", "FULL VERSION"), Color8(226, 84, 199))

	var milestone_box := VBoxContainer.new()
	milestone_box.name = "DemoMilestones"
	milestone_box.add_theme_constant_override("separation", 5)
	body.add_child(milestone_box)
	var lines: Array = review.get("milestones", []) as Array
	if lines.is_empty():
		lines = [_ui("Der erste Amiga, die ersten Disketten und ein Sommer voller Geschichten.",
			"Your first Amiga, first disks and a summer full of stories.")]
	for i in mini(lines.size(), 3):
		var line := _label("◆  %s" % str(lines[i]), 14, Color8(183, 206, 207))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		milestone_box.add_child(line)

	var future := PanelContainer.new()
	future.add_theme_stylebox_override("panel", _future_style())
	body.add_child(future)
	var future_label := _label(_ui(
		"SIDE B: NEUN WEITERE SOMMER · A600/A1200 · AGA · BBS · EIGENE RELEASES · DAS JAHR 2000",
		"SIDE B: NINE MORE SUMMERS · A600/A1200 · AGA · BBS · YOUR OWN RELEASES · YEAR 2000"),
		15, Color8(246, 224, 164))
	future_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	future_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	future_label.custom_minimum_size.y = 54
	future.add_child(future_label)

	var buy := _button(_ui("VOLLVERSION ANSEHEN  ›", "GET THE FULL VERSION  ›"), Color8(255, 170, 35))
	buy.name = "GetFullVersionButton"
	buy.custom_minimum_size.y = 54
	buy.pressed.connect(_open_full_version)
	body.add_child(buy)

	var url := _label(BuildChannel.full_version_url(), 12, Color8(84, 201, 223))
	url.name = "FullVersionUrl"
	url.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(url)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	var replay := _button(_ui("SZENE NOCHMAL", "REPLAY SCENE"), Color8(62, 195, 221))
	replay.name = "ReplayDemoFinaleButton"
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replay.pressed.connect(play_scene_finale)
	actions.add_child(replay)
	var title_button := _button(_ui("ZUM HAUPTMENUE", "RETURN TO TITLE"), Color8(73, 223, 147))
	title_button.name = "ReturnToTitleButton"
	title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_button.pressed.connect(_return_to_title)
	actions.add_child(title_button)

	if not bool(_setting("reduced_motion", false)):
		_offer.modulate.a = 0.0
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_offer, "modulate:a", 1.0, 0.35)


func _add_summary_card(parent: HBoxContainer, value: String, caption: String, accent: Color) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.026, 0.05, 0.94)
	style.border_color = Color(accent, 0.68)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var column := VBoxContainer.new()
	card.add_child(column)
	var number := _label(value, 23, accent)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(number)
	var text := _label(caption, 12, Color8(188, 207, 209))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(text)


func _open_full_version() -> void:
	var target := BuildChannel.full_version_url()
	if not target.is_empty():
		OS.shell_open(target)


func _return_to_title() -> void:
	return_to_title_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if is_instance_valid(_presentation):
		show_offer()
	else:
		_return_to_title()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.004, 0.009, 0.022, 0.965)
	style.border_color = Color8(52, 204, 229)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(0, 0, 0, 0.78)
	style.shadow_size = 18
	return style


func _future_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.035, 0.008, 0.78)
	style.border_color = Color8(255, 170, 35, 180)
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	return style


func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", Wb13.font())
	button.add_theme_font_size_override("font_size", 16)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.018, 0.027, 0.047, 0.98)
	normal.border_color = Color(accent, 0.76)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(9)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.18)
	hover.border_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.09)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color8(226, 239, 239))
	button.add_theme_color_override("font_hover_color", accent)
	return button


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Wb13.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _ui(german: String, english: String) -> String:
	return english if _locale.begins_with("en") else german


func _locale_code() -> String:
	var localization := get_node_or_null("/root/Localization")
	if localization != null and localization.has_method("locale"):
		return str(localization.call("locale")).to_lower()
	return str(TranslationServer.get_locale()).to_lower()


func _setting(key: String, fallback: Variant) -> Variant:
	var settings := get_node_or_null("/root/SettingsManager")
	return settings.call("value", key) if settings != null and settings.has_method("value") else fallback


class _DemoFinaleBackdrop:
	extends Control

	var _t := 0.0
	var _stars: Array[Vector3] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x19901990
		for i in 92:
			_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.25, 1.0)))
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if size.x < 8.0 or size.y < 8.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color8(1, 3, 11))
		for star: Vector3 in _stars:
			var y := fmod(star.y * size.y + _t * (10.0 + star.z * 34.0), size.y)
			var alpha := 0.22 + 0.66 * star.z
			draw_rect(Rect2(star.x * size.x, y, 1.0 + star.z, 1.0 + star.z), Color(0.32, 0.83, 0.96, alpha))
		var horizon := size.y * 0.68
		for i in 13:
			var p := float(i) / 12.0
			var y := lerpf(horizon, size.y, p * p)
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.1, 0.62, 0.78, 0.18 + p * 0.18), 1.0)
		for i in 19:
			var x_top := size.x * 0.5 + (float(i) - 9.0) * 23.0
			var x_bottom := size.x * 0.5 + (float(i) - 9.0) * size.x * 0.095
			draw_line(Vector2(x_top, horizon), Vector2(x_bottom, size.y), Color(0.12, 0.66, 0.82, 0.2), 1.0)
		for band in 8:
			var yy := size.y * 0.15 + band * 7.0 + sin(_t * 0.8 + band) * 4.0
			var color := Color(0.92, 0.13, 0.63, 0.08 + band * 0.008) if band % 2 == 0 else Color(1.0, 0.58, 0.1, 0.09)
			draw_rect(Rect2(0, yy, size.x, 3.0), color)
		for y in range(0, int(size.y), 4):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.2), 1.0)
