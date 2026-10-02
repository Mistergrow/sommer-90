class_name RetroWindow
extends Control
## Basisklasse aller Spielfenster: dunkles Bezel-Panel mit Titelleiste,
## Schließen-Gadget und Verschieben per Titelleisten-Drag.
## Unterklassen setzen in _init() title/win_size und füllen in _ready()
## nach super._ready() den 'content'-Container.

var title: String = "FENSTER"
var win_size: Vector2 = Vector2(320, 220)
var content: VBoxContainer

var _dragging := false
var _drag_offset := Vector2.ZERO
var _minigame_id := ""
var _runtime_peak_ms := 0.0
var _title_label: Label
var _presentation_scale := 1.0
var _open_tween: Tween
var chrome_accent: Color = Palette.LCD_CYAN
var _chrome_active := true
var _background_panel: Panel
var _inner_rail: Panel
var _title_bar: Panel
var _title_marker: ColorRect

const WindowSupport := preload("res://scripts/ui/ui_window_support.gd")
const Chrome := preload("res://scripts/ui/ui_window_chrome.gd")


func _ready() -> void:
	size = win_size
	custom_minimum_size = win_size
	clip_contents = true
	pivot_offset = win_size * 0.5
	var host := get_parent() as Control
	if host != null and not has_meta("no_safe_fit"):
		_presentation_scale = WindowSupport.fit_scale(host, win_size)
		host.resized.connect(_on_host_resized)
	scale = Vector2.ONE * _presentation_scale
	theme = UITheme.get_theme()     # einheitlicher Retro-Look für alle Kind-Controls
	_build_frame()
	call_deferred("_activate_chrome")
	_watch_contract_subtree(self)
	call_deferred("_enforce_frame_contract")
	_minigame_id = _infer_minigame_id()
	if not _minigame_id.is_empty():
		MinigameManager.begin_session(_minigame_id)
		child_entered_tree.connect(_configure_accessible_child)
		call_deferred("_configure_accessibility_tree")
		set_process(true)
	# Sanftes Einblenden (alle Fenster). DSS_SHOT=1 überspringt es (Proof-Screenshots).
	if OS.get_environment("DSS_SHOT") != "1" and not bool(SettingsManager.value("reduced_motion")):
		modulate.a = 0.0
		call_deferred("_animate_open")
		var am := get_node_or_null("/root/AudioManager")
		if am != null:
			am.call("ui_click")   # dezenter Blip beim Fenster-Öffnen


func _process(delta: float) -> void:
	if _minigame_id.is_empty(): return
	var frame_ms := delta * 1000.0
	if frame_ms > _runtime_peak_ms:
		_runtime_peak_ms = frame_ms
		MinigameManager.note_runtime(_minigame_id, &"frame_ms", frame_ms)
	if delta > 1.0 / 20.0:
		MinigameManager.note_runtime(_minigame_id, &"hitch")


func _configure_accessible_child(node: Node) -> void:
	if node is Button:
		var button := node as Button
		if not button is CloseButton and not button.has_meta("aaa_configured"):
			button.set_meta("aaa_configured", true)
			button.focus_mode = Control.FOCUS_ALL
			button.focus_entered.connect(func() -> void: AudioManager.minigame_cue(_minigame_id,&"focus"))
			button.pressed.connect(func() -> void:
				var event:=&"hint"if("HINWEIS"in button.text or"HILFE"in button.text)else&"action"
				MinigameManager.note_runtime(_minigame_id,event);AudioManager.minigame_cue(_minigame_id,event))


func _configure_accessibility_tree() -> void:
	for node in find_children("*", "Button", true, false):
		_configure_accessible_child(node)


func _unhandled_key_input(event: InputEvent) -> void:
	if _minigame_id.is_empty() or not event.pressed or event.echo: return
	if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		MinigameManager.note_runtime(_minigame_id, &"input", "keyboard")
	if event.keycode == KEY_F1:
		_show_accessibility_contract()
		get_viewport().set_input_as_handled()


func _show_accessibility_contract() -> void:
	var profile := MinigameManager.aaa_profile(_minigame_id)
	var access: Array = profile.get("access", [])
	var inputs: Array = profile.get("input", [])
	UIManager.toast(Loc.t("ui.retro_window.bedienung_s_hilfen_s", "BEDIENUNG: %s · HILFEN: %s") % [", ".join(inputs), ", ".join(access)])


func _infer_minigame_id() -> String:
	var script := get_script() as Script
	var path: String = script.resource_path.get_file().trim_suffix(".gd") if script else ""
	var aliases := {"label_designer":"label_design", "paint_app":"paint",
		"bbs_carrier_minigame":"bbs_link", "cracktro_optimization_minigame":"cracktro_opt",
		"disk_repair_minigame":"disk_media_repair"}
	if aliases.has(path): return str(aliases[path])
	return path.trim_suffix("_minigame") if path.trim_suffix("_minigame") in MinigameManager.MASTER_IDS else ""


func _animate_open() -> void:
	pivot_offset = win_size / 2.0
	scale = Vector2.ONE * (_presentation_scale * 0.94)
	_open_tween = create_tween().set_parallel()
	_open_tween.tween_property(self, "modulate:a", 1.0, 0.14)
	_open_tween.tween_property(self, "scale", Vector2.ONE * _presentation_scale, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_host_resized() -> void:
	# Wait until anchors and viewport stretch have adopted the new dimensions.
	_refit_to_host.call_deferred()


func _refit_to_host() -> void:
	if not is_inside_tree() or has_meta("no_safe_fit"):
		return
	var host := get_parent() as Control
	if host == null:
		return
	if _open_tween != null and _open_tween.is_running():
		_open_tween.kill()
		modulate.a = 1.0
	_presentation_scale = WindowSupport.fit_scale(host, win_size)
	scale = Vector2.ONE * _presentation_scale
	_clamp_to_safe_area()


func _clamp_to_safe_area() -> void:
	var host := get_parent() as Control
	var safe := WindowSupport.safe_rect(host) if host != null else get_viewport_rect()
	var scaled_size := win_size * _presentation_scale
	var visual_shift := pivot_offset * (1.0 - _presentation_scale)
	var min_pos := safe.position - visual_shift
	var max_pos := safe.end - scaled_size - visual_shift
	position.x = clampf(position.x, min_pos.x, maxf(min_pos.x, max_pos.x))
	position.y = clampf(position.y, min_pos.y, maxf(min_pos.y, max_pos.y))


func _build_frame() -> void:
	# Dunkler Instrumentenrahmen wie Top-/Side-/Bottom-HUD. Er ist bewusst
	# kantig und besitzt keine OS-typische blaue Fensterflaeche oder Rundung.
	_background_panel = Panel.new()
	_background_panel.name = "WindowShell"
	_background_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_panel.clip_contents = true
	_background_panel.add_theme_stylebox_override("panel", Chrome.shell_box())
	_background_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_background_panel.gui_input.connect(_on_frame_input)
	add_child(_background_panel)

	# Titelschiene: schmaler technischer Displayrahmen statt Desktop-Chrome.
	_title_bar = Panel.new()
	_title_bar.name = "WindowTitleBar"
	_title_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_bar.offset_top = 4
	_title_bar.offset_left = 5
	_title_bar.offset_right = -5
	_title_bar.offset_bottom = 29
	_title_bar.clip_contents = true
	_title_bar.gui_input.connect(_on_title_bar_input)
	add_child(_title_bar)

	_title_marker = ColorRect.new()
	_title_marker.name = "WindowTitleMarker"
	_title_marker.position = Vector2(5, 6)
	_title_marker.size = Vector2(3, 13)
	_title_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_title_marker)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_label.offset_left = 14.0
	_title_label.offset_top = 1.0
	_title_label.offset_right = -54.0
	_title_label.offset_bottom = -1.0
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Palette.LCD_AMBER)
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_bar.add_child(_title_label)

	# Drei Statuspixel greifen die Display-Sprache des HUD auf und geben langen
	# Titelleisten auch ohne dekorative Textwiederholung einen eigenen Rhythmus.
	for index in 3:
		var led := ColorRect.new()
		led.name = "WindowActivity%d" % (index + 1)
		led.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		led.offset_left = -44.0 + index * 5.0
		led.offset_top = 11.0
		led.offset_right = -41.0 + index * 5.0
		led.offset_bottom = 14.0
		led.color = [Palette.LCD_GREEN, Palette.LCD_AMBER, chrome_accent][index]
		led.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_bar.add_child(led)

	_title_bar.add_child(_build_close_button())

	# Eine zweite, sehr feine Leuchtschiene trennt den Inhalt vom Aussenrahmen.
	_inner_rail = Panel.new()
	_inner_rail.name = "WindowInnerRail"
	_inner_rail.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inner_rail.offset_left = 5
	_inner_rail.offset_top = 33
	_inner_rail.offset_right = -5
	_inner_rail.offset_bottom = -5
	_inner_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inner_rail)
	_apply_chrome_state()

	# Inhaltsbereich
	var margin := MarginContainer.new()
	margin.name = "WindowContentMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_top = 38
	margin.offset_left = 11
	margin.offset_right = -11
	margin.offset_bottom = -11
	margin.clip_contents = true
	add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)


## AAA-Schließen-Knopf: dunkles Hardware-Gadget mit roter Warnkante und hellem
## ✕, bündig in der technischen Titelschiene.
func _build_close_button() -> Button:
	# Eigener Button, der das ✕ selbst zeichnet — so bleibt die Größe exakt
	# (ein Text-Button würde auf die Zeilenhöhe der Theme-Schrift aufblähen).
	var btn := CloseButton.new()
	btn.name = "CloseButton"
	btn.custom_minimum_size = Vector2(16, 14)
	# An der ECKE DER ECHTEN TITELLEISTE verankern, nicht an win_size. Das bleibt
	# auch korrekt, wenn ein grosses Studio beim Zentrieren oder UI-Scaling seine
	# berechnete Breite erst nach _ready() erhaelt.
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -20.0
	btn.offset_top = 4.0
	btn.offset_right = -4.0
	btn.offset_bottom = 20.0
	# Das Gadget bleibt bewusst auf derselben Canvas-Hoehe wie sein Fenster.
	# Ein hoher lokaler z_index addiert sich in Godot zur Fensterhoehe und liess
	# das X eines HINTEREN Fensters durch ein davorliegendes Fenster scheinen.
	# Die spaeter gezeichnete Fenster-Subtree-Reihenfolge ist die richtige und
	# atomare Fokusregel fuer alle RetroWindow-Instanzen.
	btn.z_index = 0
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = Loc.t("ui.common.close", "Schließen")

	btn.add_theme_stylebox_override("normal", Chrome.close_box("normal"))
	btn.add_theme_stylebox_override("hover", Chrome.close_box("hover"))
	btn.add_theme_stylebox_override("pressed", Chrome.close_box("pressed"))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color8(255, 226, 222))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color8(255, 210, 205))
	btn.add_theme_constant_override("outline_size", 1)
	btn.add_theme_color_override("font_outline_color", Color8(40, 10, 10))
	btn.pressed.connect(queue_free)
	return btn


## Aktualisiert auch eine bereits aufgebaute Titelleiste. Das wird insbesondere
## beim Sprachwechsel im laufenden Optionsfenster gebraucht.
func set_window_title(value: String) -> void:
	title = value
	if is_instance_valid(_title_label):
		_title_label.text = value


## Laufzeitvertrag fuer Layout-Regressionstests und Diagnoseansichten. Alle
## Werte liegen im Koordinatensystem des Fensterhosts, also genau dort, wo auch
## Zentrierung und Drag-Clamp arbeiten.
func frame_contract() -> Dictionary:
	var host := get_parent() as Control
	var safe := WindowSupport.safe_rect(host) if host != null else get_viewport_rect()
	var visual_shift := pivot_offset * (1.0 - _presentation_scale)
	var visual_rect := Rect2(position + visual_shift, win_size * _presentation_scale)
	return {
		"safe_rect": safe,
		"visual_rect": visual_rect,
		# Zentrierung wird fuer pixelstabile Darstellung gerundet. Ein halber
		# Pixel Toleranz bildet genau diese Rasterung ab, nicht sichtbaren Ueberlauf.
		"inside_safe_area": safe.grow(0.5).encloses(visual_rect),
		"presentation_scale": _presentation_scale,
		"clips_children": clip_contents,
		"title_clipped": is_instance_valid(_title_label) and _title_label.clip_text,
	}


## Klick irgendwo im Fenster → nach vorn holen.
func _on_frame_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_activate_chrome()


## Drag über die Titelleiste, an den Bildschirm geklemmt.
func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = get_global_mouse_position() - position
			_activate_chrome()
	elif event is InputEventMouseMotion and _dragging:
		position = get_global_mouse_position() - _drag_offset
		_clamp_to_safe_area()


## Nur das vorderste Fenster leuchtet voll. Der Fokus wird am kompletten
## RetroWindow gesetzt, damit auch das Schliessen-Gadget niemals durch ein
## davorliegendes Fenster scheint.
func _activate_chrome() -> void:
	var host := get_parent()
	if host != null:
		for sibling: Node in host.get_children():
			if sibling is RetroWindow and sibling != self:
				(sibling as RetroWindow)._set_chrome_active(false)
	move_to_front()
	_set_chrome_active(true)


func _set_chrome_active(active: bool) -> void:
	if _chrome_active == active and is_instance_valid(_title_bar):
		return
	_chrome_active = active
	_apply_chrome_state()


func _apply_chrome_state() -> void:
	if is_instance_valid(_title_bar):
		_title_bar.add_theme_stylebox_override("panel", Chrome.title_box(chrome_accent, _chrome_active))
	if is_instance_valid(_inner_rail):
		_inner_rail.add_theme_stylebox_override("panel", Chrome.inner_rail_box(chrome_accent, _chrome_active))
	if is_instance_valid(_title_marker):
		_title_marker.color = chrome_accent if _chrome_active else Color8(53, 59, 61)
	if is_instance_valid(_title_label):
		_title_label.add_theme_color_override("font_color",
			Palette.LCD_AMBER if _chrome_active else Palette.UI_TEXT_DIM)


## Hilfsfunktion für Unterklassen: Standard-Button mit Callback.
func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	_apply_button_contract(button)
	# Leerer Callable() erlaubt (Aufrufer verbindet 'pressed' selbst) — sonst
	# „Cannot connect to 'pressed': the provided callable is null".
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


## Godot 4.8 nimmt Text aus der automatischen Mindestbreite, sobald `clip_text`
## aktiv ist. Ohne eigene Untergrenze kollabierten dynamische HBox-Aktionen auf
## die 20-26 Pixel ihrer StyleBox-Raender; der Text war vorhanden, aber komplett
## weggeclippt. Dieser zentrale Vertrag gibt jedem normalen RetroWindow-Button
## eine lesbare, aus seinem laengsten Textabschnitt abgeleitete Grundflaeche.
## Aufrufer duerfen die Mindestgroesse danach weiterhin bewusst ueberschreiben.
func _apply_button_contract(button: Button) -> void:
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if button.text.is_empty():
		return
	var longest := 0
	var line_count := 0
	for line: String in button.text.split("\n"):
		longest = maxi(longest, line.length())
		line_count += 1
	if button.custom_minimum_size.x <= 0.0:
		button.custom_minimum_size.x = clampf(float(longest * 8 + 22), 44.0, 220.0)
	if button.custom_minimum_size.y <= 0.0:
		button.custom_minimum_size.y = maxf(32.0, float(line_count * 19 + 11))


## Letzte Schutzschicht des gemeinsamen Fenstervertrags. Layouts sollen ihre
## Texte weiterhin bewusst umbrechen; ein vergessenes Label darf aber nie ueber
## den Rahmen eines Fensters oder Buttons zeichnen. Diese Normalisierung laeuft
## nach dem Aufbau der Unterklasse und aendert keine mehrzeiligen Texte.
func _enforce_frame_contract() -> void:
	for node: Node in find_children("*", "Control", true, false):
		_apply_contract_to_node(node)


## Unterklassen bauen viele Seiten erst nach super._ready() oder bei einem
## Bereichswechsel auf. Der Beobachter haengt deshalb am gesamten Fensterbaum
## und gibt auch spaeter hinzugefuegten Direkt-Buttons denselben Vertrag.
func _watch_contract_subtree(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not node.has_meta("retro_contract_watch"):
		node.set_meta("retro_contract_watch", true)
		node.child_entered_tree.connect(_watch_contract_subtree)
	_apply_contract_to_node.call_deferred(node)
	for child: Node in node.get_children():
		_watch_contract_subtree(child)


func _apply_contract_to_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is Label:
		var label := node as Label
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			# Explizite Mindestbreiten sind Teil des Layout-Vertrags (Statusfelder,
			# Spaltenkoepfe) und werden deshalb bewusst nicht zurueckgesetzt.
	elif node is Button and not node is CloseButton:
		_apply_button_contract(node as Button)


## Schließen-Gadget: zeichnet ein scharfes ✕ als zwei Linien in exakter Größe,
## Farbe wechselt beim Hover (heller). Kein Text → keine Schrift-Aufblähung.
class CloseButton:
	extends Button

	func _init() -> void:
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var m := 4.0
		var col := Color(1, 1, 1) if is_hovered() else Color8(255, 224, 220)
		draw_line(Vector2(m, m), Vector2(size.x - m, size.y - m), col, 1.5, true)
		draw_line(Vector2(size.x - m, m), Vector2(m, size.y - m), col, 1.5, true)
