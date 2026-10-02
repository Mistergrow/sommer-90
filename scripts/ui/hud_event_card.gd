class_name HudEventCard
extends Control
## Ruhige, gut lesbare Ereigniskarte fuer das untere HUD.
##
## Der Text bleibt auf genau zwei Hierarchieebenen begrenzt: eine primaere
## Meldung und eine kurze Handlungs-/Statuszeile. Die kleine Szenegrafik dahinter
## folgt dem wirklich aktiven OCS-/ECS-/AGA-Modus, ohne die Lesbarkeit des Textes
## oder die Einstellung "Reduzierte Bewegung" zu umgehen.

const SceneCatalog := preload("res://scripts/ui/scene_generation_catalog.gd")
const RedrawCadenceScript := preload("res://scripts/util/redraw_cadence.gd")
const UI_FONT := preload("res://assets/fonts/VT323_UI.ttf")
const CONTENT_INSET_X := 12
const CONTENT_INSET_Y := 4
const BADGE_GAP := 8

var _primary_label: Label
var _secondary_label: Label
var _badge_label: Label
var _primary_text := ""
var _secondary_text := ""
var _badge_text := ""
var _chipset := "OCS"
var _attention := false
var _accent := Color8(244, 174, 48)
var _motion_enabled := true
var _elapsed := 0.0
var _redraw_cadence := RedrawCadenceScript.new()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 51)
	_build_labels()
	if not SettingsManager.settings_changed.is_connected(_refresh_profile):
		SettingsManager.settings_changed.connect(_refresh_profile)
	_refresh_profile()


func _build_labels() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", CONTENT_INSET_X)
	margin.add_theme_constant_override("margin_right", CONTENT_INSET_X)
	margin.add_theme_constant_override("margin_top", CONTENT_INSET_Y)
	margin.add_theme_constant_override("margin_bottom", CONTENT_INSET_Y)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)

	# Meldung und Zaehler teilen sich eine echte Layout-Zeile. Der Zaehler ist
	# damit kein frei positioniertes Overlay mehr: Er bleibt bei jeder Breite
	# innerhalb des Karten-Insets und der Meldung wird sein Platz abgezogen.
	var primary_row := HBoxContainer.new()
	primary_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	primary_row.add_theme_constant_override("separation", BADGE_GAP)
	primary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(primary_row)

	_primary_label = Label.new()
	_primary_label.add_theme_font_override("font", UI_FONT)
	_primary_label.add_theme_font_size_override("font_size", 17)
	_primary_label.add_theme_color_override("font_color", Color8(255, 230, 150))
	_primary_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	_primary_label.add_theme_constant_override("outline_size", 3)
	_primary_label.clip_text = true
	_primary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_primary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_primary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_primary_label.custom_minimum_size.x = 0.0
	primary_row.add_child(_primary_label)

	_badge_label = Label.new()
	_badge_label.add_theme_font_override("font", UI_FONT)
	_badge_label.add_theme_font_size_override("font_size", 10)
	_badge_label.add_theme_color_override("font_color", Color8(255, 220, 126))
	_badge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.96))
	_badge_label.add_theme_constant_override("outline_size", 2)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_badge_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label.visible = false
	primary_row.add_child(_badge_label)

	_secondary_label = Label.new()
	_secondary_label.add_theme_font_override("font", UI_FONT)
	_secondary_label.add_theme_font_size_override("font_size", 11)
	_secondary_label.add_theme_color_override("font_color", Color8(190, 214, 222))
	_secondary_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.96))
	_secondary_label.add_theme_constant_override("outline_size", 2)
	_secondary_label.clip_text = true
	_secondary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_secondary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_secondary_label)


func set_content(primary: String, secondary: String, attention := false,
		accent := Color.TRANSPARENT) -> void:
	var changed := primary != _primary_text or secondary != _secondary_text
	_primary_text = primary.strip_edges()
	_secondary_text = secondary.strip_edges()
	_attention = attention
	_sync_generation()
	_accent = accent if accent.a > 0.0 else _profile_for_chipset(_chipset)["accent"]
	if _primary_label != null:
		_primary_label.text = _primary_text
		_primary_label.add_theme_color_override("font_color",
			Color8(255, 244, 194) if _attention else Color8(255, 220, 126))
	if _secondary_label != null:
		_secondary_label.text = _secondary_text
	if changed:
		_reveal_message()
	queue_redraw()


func set_badge(text: String, show_badge := true) -> void:
	_badge_text = text.strip_edges()
	if _badge_label == null:
		return
	_badge_label.text = _badge_text
	_badge_label.visible = show_badge and not _badge_text.is_empty()


func _refresh_profile() -> void:
	_sync_generation()
	_motion_enabled = not bool(SettingsManager.value("reduced_motion"))
	set_process(_motion_enabled)
	_redraw_cadence.reset()
	if not _motion_enabled:
		_elapsed = 0.0
	queue_redraw()


func _sync_generation() -> void:
	var generation := SceneCatalog.effective_generation()
	_chipset = str(SceneCatalog.generation(generation).get("chipset", "OCS")).to_upper()


func _reveal_message() -> void:
	if not _motion_enabled or _primary_label == null or _secondary_label == null:
		return
	_primary_label.modulate.a = 0.0
	_secondary_label.modulate.a = 0.0
	_primary_label.position.x = 6.0
	_secondary_label.position.x = 3.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_primary_label, "modulate:a", 1.0, 0.18)
	tween.tween_property(_secondary_label, "modulate:a", 1.0, 0.24)
	tween.tween_property(_primary_label, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_secondary_label, "position:x", 0.0, 0.24).set_trans(Tween.TRANS_QUAD)


func _process(delta: float) -> void:
	_elapsed += delta
	var hz := float(_profile_for_chipset(_chipset)["redraw_hz"])
	if not _redraw_cadence.advance(delta, hz):
		return
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color8(5, 9, 16))
	match _chipset:
		"ECS":
			_draw_ecs()
		"AGA":
			_draw_aga()
		_:
			_draw_ocs()
	# Eine feste dunkle Textplatte trennt Inhalt und Dekoration. Damit bleiben
	# auch die reicheren AGA-Farben eine Randakzentuierung statt Texttapete.
	draw_rect(Rect2(5, 4, size.x - 10, size.y - 8), Color(0.01, 0.015, 0.025, 0.79))
	var border_alpha := 0.90 if _attention else 0.42
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(_accent, border_alpha),
		false, 1.0 if not _attention else 2.0)


func _draw_ocs() -> void:
	# OCS: feste Rasterpositionen; nur die 12-Bit-Copperfarben atmen dezent.
	var colors := [
		Color8(244, 174, 48), Color8(224, 93, 45),
		Color8(157, 48, 112), Color8(49, 126, 153),
	]
	for index in colors.size():
		var shimmer := 0.0 if not _motion_enabled else sin(_elapsed * 1.2 + index) * 0.05
		var y := size.y * (0.16 + float(index) * 0.22)
		draw_line(Vector2(0, y), Vector2(size.x, y),
			Color(colors[index], 0.16 + shimmer), 1.0)


func _draw_ecs() -> void:
	# ECS: zwei sanfte Sinuslagen und sichtbar weiterlaufende Palettenregister.
	var palette := [Color8(42, 198, 213), Color8(91, 110, 205), Color8(218, 71, 158)]
	for band in 3:
		var points := PackedVector2Array()
		var phase := _elapsed * (0.55 + band * 0.10)
		for x in range(0, int(size.x) + 12, 12):
			var y := size.y * (0.25 + band * 0.25) \
				+ sin(float(x) * 0.031 + phase + band * 1.7) * (2.0 + band)
			points.append(Vector2(x, y))
		var next_color: Color = palette[(band + 1) % palette.size()]
		var color: Color = palette[band].lerp(next_color,
			0.5 + sin(_elapsed * 0.35 + band) * 0.5)
		draw_polyline(points, Color(color, 0.23), 1.0)


func _draw_aga() -> void:
	# AGA: ECS-Baender bleiben abwaertskompatibel, dazu kommen mehr Farbstufen
	# und wenige subpixel-freie Bobs am Rand der Textplatte.
	_draw_ecs()
	var palette := [
		Color8(255, 83, 184), Color8(77, 223, 230), Color8(255, 190, 59),
		Color8(137, 100, 239), Color8(93, 224, 139),
	]
	for index in 14:
		var travel := fposmod(float(index) * 0.173 + _elapsed * (0.025 + (index % 4) * 0.006), 1.0)
		var x := roundf(travel * size.x)
		var y := roundf(size.y * (0.10 + fposmod(float(index) * 0.381, 0.80)))
		var radius := 1.0 + float(index % 2)
		draw_circle(Vector2(x, y), radius, Color(palette[index % palette.size()], 0.28))


func visual_profile(chipset: String) -> Dictionary:
	return _profile_for_chipset(chipset.to_upper()).duplicate(true)


func presentation_contract() -> Dictionary:
	return {
		"primary": _primary_text,
		"secondary": _secondary_text,
		"badge": _badge_text,
		"badge_visible": _badge_label != null and _badge_label.visible,
		"visible_text_lines": 2,
		"chipset": _chipset,
		"reduced_motion": not _motion_enabled,
	}


func layout_contract() -> Dictionary:
	var card_rect := Rect2(Vector2.ZERO, size)
	var inner_rect := Rect2(
		Vector2(CONTENT_INSET_X, CONTENT_INSET_Y),
		Vector2(maxf(0.0, size.x - CONTENT_INSET_X * 2.0),
			maxf(0.0, size.y - CONTENT_INSET_Y * 2.0)))
	var primary_rect := _rect_in_card(_primary_label)
	var badge_rect := _rect_in_card(_badge_label)
	return {
		"card_rect": card_rect,
		"inner_rect": inner_rect,
		"primary_rect": primary_rect,
		"badge_rect": badge_rect,
		"badge_visible": _badge_label != null and _badge_label.visible,
		"badge_inside_inner": inner_rect.encloses(badge_rect),
		"badge_overlaps_primary": badge_rect.intersects(primary_rect),
	}


func _rect_in_card(control: Control) -> Rect2:
	if control == null or not is_instance_valid(control):
		return Rect2()
	var card_origin := get_global_rect().position
	var control_rect := control.get_global_rect()
	return Rect2(control_rect.position - card_origin, control_rect.size)


func _profile_for_chipset(chipset: String) -> Dictionary:
	match chipset:
		"ECS":
			return {"effect": "sine_palette", "redraw_hz": 20.0,
				"particles": 0, "accent": Color8(57, 222, 232)}
		"AGA":
			return {"effect": "chroma_particles", "redraw_hz": 30.0,
				"particles": 14, "accent": Color8(241, 88, 194)}
		_:
			return {"effect": "fixed_copper_raster", "redraw_hz": 12.0,
				"particles": 0, "accent": Color8(244, 174, 48)}
