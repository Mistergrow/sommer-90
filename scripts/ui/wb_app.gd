class_name WbApp
extends Control
## Basis ALLER Werkbank-Programme (Vollbild-Apps „auf dem Monitor"). Der
## Shell-Code steht EINMAL hier: füllt die Zimmeransicht, liegt z50 über der
## Werkbank, Esc/Schließen-Gadget, virtuelles 640×400-Raster mit Skalierung,
## Standard-Rahmen + Titelleiste, Zeichen-/Button-Helfer, Scanlines. Konkrete
## Apps überschreiben nur `_build_app()` (Buttons anmelden) und `_content(font)`
## (Inhalt zeichnen); optional `_app_process(delta)`.
##
## So ist eine neue App = eine Datei mit ~Inhalt, kein neuer Shell-Code.

const VW := 640.0
const VH := 400.0
const TB := 18.0    # Titelleistenhöhe (virtuell)

# von Unterklassen in _init/_build_app gesetzt
var app_title := "PROGRAMM"
var app_bg := Color8(26, 32, 50)
var app_bar := Color8(40, 74, 96)
var app_accent := Color8(120, 180, 240)

var _widgets: Array = []   # {label, rect, cb, color, node, hover}
var _close_btn: Button
var _minigame_id:=""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	focus_mode = Control.FOCUS_ALL
	var parent := get_parent_control()
	if parent != null:
		parent.resized.connect(_sync_size)
	_sync_size.call_deferred()
	_minigame_id=_infer_minigame_id()
	if not _minigame_id.is_empty():MinigameManager.begin_session(_minigame_id)
	_make_close()
	_build_app()
	resized.connect(_layout)
	call_deferred("_layout")
	set_process(true)
	grab_focus.call_deferred()


func _sync_size() -> void:
	var parent := get_parent_control()
	if parent != null:
		position = Vector2.ZERO
		size = parent.size
		_layout()


# ----------------------------------------------------------------- Skalierung

func _sx() -> float: return size.x / VW
func _sy() -> float: return size.y / VH
func _V(x: float, y: float) -> Vector2: return Vector2(x * _sx(), y * _sy())
func _R(r: Rect2) -> Rect2: return Rect2(_V(r.position.x, r.position.y), Vector2(r.size.x * _sx(), r.size.y * _sy()))


# ----------------------------------------------------------------- Widgets

## Klickbarer Button in virtuellen Koordinaten. Das Framework zeichnet ihn (3D)
## und ruft beim Klick `cb`. Apps müssen sich um Position/Hover nicht kümmern.
## auto_draw=false → nur Klickfläche (App zeichnet die Zeile/Fläche selbst,
## z. B. Listeneinträge mit eigener Hover-Hervorhebung).
func add_button(label: String, button_rect: Rect2, cb: Callable, color := Color.WHITE, auto_draw := true) -> Dictionary:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.pressed.connect(cb)
	b.focus_entered.connect(func() -> void:if not _minigame_id.is_empty():AudioManager.minigame_cue(_minigame_id,&"focus"))
	b.pressed.connect(func()->void:
		if not _minigame_id.is_empty():MinigameManager.note_runtime(_minigame_id,&"action");AudioManager.minigame_cue(_minigame_id,&"action"))
	add_child(b)
	var w := {"label": label, "rect": button_rect, "cb": cb, "color": color, "node": b, "auto_draw": auto_draw}
	_widgets.append(w)
	return w


## Ob ein angemeldeter Button gerade überfahren wird (für eigene Zeichnung).
func widget_hovered(w: Dictionary) -> bool:
	return w["node"].is_hovered()


func clear_widgets() -> void:
	for w in _widgets:
		w["node"].queue_free()
	_widgets = []


func _make_close() -> void:
	_close_btn = Button.new()
	_close_btn.flat = true
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in ["normal", "hover", "pressed", "focus"]:
		_close_btn.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	_close_btn.pressed.connect(close_app)
	add_child(_close_btn)


func _layout() -> void:
	for w in _widgets:
		var r: Rect2 = _R(w["rect"])
		w["node"].position = r.position
		w["node"].size = r.size
	if _close_btn != null:
		# Workbench 1.3: Schliess-Gadget sitzt links in der weissen Titelleiste.
		_close_btn.position = _V(0, 0)
		_close_btn.size = Vector2(24 * _sx(), 20 * _sy())
	_layout_app()
	queue_redraw()


func close_app() -> void:
	queue_free()

func _infer_minigame_id()->String:
	var script:=get_script()as Script;var file:=script.resource_path.get_file().trim_suffix(".gd")if script else""
	var aliases:={"paint_app":"paint","scene_patch_app":"scene_patch"};return str(aliases.get(file,""))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled();close_app()
		elif event.keycode == KEY_F1 and not _minigame_id.is_empty():
			var profile:=MinigameManager.aaa_profile(_minigame_id);UIManager.toast(Loc.t("ui.wb_app.bedienung_s_hilfen_s", "BEDIENUNG: %s · HILFEN: %s")%[", ".join(profile.get("input",[])),", ".join(profile.get("access",[]))]);get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_app_process(delta)
	queue_redraw()


# ----------------------------------------------------------------- Zeichnen

func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var font := Wb13.font()
	# Alle startbaren Programme teilen denselben echten Workbench-Desktop und
	# dieselbe Fensterchromatik. App-Farben bleiben nur im Innenraum Akzente.
	draw_rect(Rect2(Vector2.ZERO, size), Wb13.blue())
	draw_rect(_R(Rect2(4, 22, VW - 8, VH - 26)), app_bg)
	draw_rect(_R(Rect2(4, 22, VW - 8, VH - 26)), Wb13.white(), false, maxf(1.0, _sy()))
	# Inhalt der App
	_content(font)
	# angemeldete Buttons (Listenzeilen zeichnet die App selbst)
	for w in _widgets:
		if w.get("auto_draw", true):
			_draw_button(font, w)
	_draw_workbench_chrome(font)
	_draw_scanlines()


## Gemeinsame Shell auch fuer historisch eigenstaendig gezeichnete Apps
## (SysInfo/Preferences). Titel, Gadget und Tiefenknopf bleiben identisch.
func _draw_workbench_chrome(font: Font = Wb13.font()) -> void:
	var sy := _sy()
	var title_rect := _R(Rect2(0, 0, VW, 20))
	draw_rect(title_rect, Wb13.white())
	Wb13.drag_stripes(self, _R(Rect2(24, 0, VW - 76, 20)), sy * 2.0)
	# Eine weisse Textinsel verhindert, dass die Streifen durch den Titel laufen.
	var title_width := clampf(float(app_title.length()) * 9.0 + 20.0, 100.0, 430.0)
	var title_x := (VW - title_width) * 0.5
	draw_rect(_R(Rect2(title_x, 0, title_width, 20)), Wb13.white())
	draw_string(font, _V(title_x, 16), app_title, HORIZONTAL_ALIGNMENT_CENTER,
		title_width * _sx(), Wb13.fsize(sy), Wb13.black())
	Wb13.gadget_close(self, _R(Rect2(0, 0, 24, 20)), _sx(), sy * 2.0)
	Wb13.gadget_depth(self, _R(Rect2(VW - 52, 0, 26, 20)), _sx(), sy * 2.0, false)
	Wb13.gadget_depth(self, _R(Rect2(VW - 26, 0, 26, 20)), _sx(), sy * 2.0, true)
	draw_rect(_R(Rect2(0, 0, VW, VH)), Wb13.black(), false, maxf(1.0, sy))


func _draw_button(font: Font, w: Dictionary) -> void:
	var r: Rect2 = w["rect"]
	var highlighted: bool = w["node"].is_hovered() or w["node"].has_focus()
	var physical := _R(r)
	draw_rect(physical, Wb13.orange() if highlighted else Wb13.blue())
	draw_rect(physical, Wb13.white(), false, maxf(1.0, _sy()))
	if w["node"].button_pressed:
		draw_rect(physical.grow(-2.0 * _sy()), Wb13.black(), false, maxf(1.0, _sy()))
	text_c(font, w["label"], r.position.x, r.position.x + r.size.x,
		r.position.y + r.size.y * 0.68, 10, Wb13.black() if highlighted else Wb13.white())


func _draw_scanlines() -> void:
	if not bool(SettingsManager.value("scanlines")):
		return
	var step := maxf(2.0, round(_sy() * 3.0))
	var y := 0.0
	while y < size.y:
		draw_rect(Rect2(0, y, size.x, maxf(1.0, step * 0.34)), Color(0, 0, 0, 0.13))
		y += step


# ------------------------------------------- Zeichen-Helfer (virtuelle Koords)

func text(font: Font, s: String, x: float, y: float, fsize: int, col: Color) -> void:
	draw_string(font, _V(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, int(fsize * _sy())), col)


func text_c(font: Font, s: String, x0: float, x1: float, y: float, fsize: int, col: Color) -> void:
	draw_string(font, _V(x0, y), s, HORIZONTAL_ALIGNMENT_CENTER, (x1 - x0) * _sx(), maxi(1, int(fsize * _sy())), col)


func rect(x: float, y: float, w: float, h: float, col: Color) -> void:
	draw_rect(_R(Rect2(x, y, w, h)), col)


func rect_line(x: float, y: float, w: float, h: float, col: Color, width := 1.0) -> void:
	draw_rect(_R(Rect2(x, y, w, h)), col, false, width)


func button3d(r: Rect2, base: Color, down: bool) -> void:
	UiPaint.button3d(self, _R, r, base, down)


# ----------------------------------------------------------------- Überschreiben

func _build_app() -> void: pass
func _layout_app() -> void: pass
func _content(_font: Font) -> void: pass
func _app_process(_delta: float) -> void: pass
