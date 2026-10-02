class_name WbPrefsApp
extends WbApp
## Preferences — der Einstellungs-Bildschirm der WERKBANK 1.3, nachgebaut nach
## dem Original (dunkler Grund, blaue Tafeln, Schieberegler, RGB-Farbmischer).
## Die vier Palette-Farben sind ECHT: Regler ändern die komplette Werkbank
## (Save = dauerhaft, Use = bis zum Aufstehen, Cancel = zurück). Interlace
## schaltet die Scanlines, Change Printer/Serial öffnen die Peripherie-Konfig.

const Versions := preload("res://scripts/ui/workbench_versions.gd")

var _pal: Array = []
var _entry: Array = []
var _sel := 0            # gewählte Palette-Farbe 0..3
var _delay := 0.35       # Key Repeat (nur Optik, wie damals herumspielen)
var _speed := 0.75
var _mouse := 1          # 1/2/4
var _text80 := true
var _drag := ""          # "delay" | "speed" | "r" | "g" | "b"


func _init() -> void:
	app_title = "Preferences %s" % str(Versions.active().get(
		"workbench_revision", "34.66"))


func _build_app() -> void:
	_pal = [Wb13.col(0), Wb13.col(1), Wb13.col(2), Wb13.col(3)]
	_entry = _pal.duplicate()
	add_button("", Rect2(24, 30, 130, 22), _reset_all, Color.WHITE, false)
	add_button("", Rect2(24, 58, 130, 22), _last_saved, Color.WHITE, false)
	add_button("", Rect2(24, 130, 130, 30), UIManager.open_modem_config, Color.WHITE, false)
	add_button("", Rect2(520, 62, 52, 20), func() -> void: _set_scan(true), Color.WHITE, false)
	add_button("", Rect2(574, 62, 52, 20), func() -> void: _set_scan(false), Color.WHITE, false)
	add_button("", Rect2(230, 316, 240, 22), _reset_colors, Color.WHITE, false)
	add_button("", Rect2(472, 306, 102, 24), UIManager.open_printer_config, Color.WHITE, false)
	add_button("", Rect2(472, 336, 102, 24), func() -> void:
		UIManager.toast(Loc.t("ui.wb_prefs_app.edit_pointer_pfeil_ist_schon_perfekt", "Edit Pointer: Der Pfeil ist schon perfekt.")), Color.WHITE, false)
	add_button("", Rect2(582, 306, 54, 24), _save, Color.WHITE, false)
	add_button("", Rect2(582, 336, 54, 24), _use, Color.WHITE, false)
	add_button("", Rect2(582, 366, 54, 24), _cancel, Color.WHITE, false)
	for i in 4:
		add_button("", Rect2(30 + i * 40, 312, 36, 28), func() -> void: _sel = i, Color.WHITE, false)
	for i in 3:
		var m: int = [1, 2, 4][i]
		add_button("", Rect2(508, 120 + i * 34, 30, 26), func() -> void: _mouse = m, Color.WHITE, false)
	add_button("", Rect2(60, 286, 40, 18), func() -> void: _text80 = false, Color.WHITE, false)
	add_button("", Rect2(102, 286, 40, 18), func() -> void: _text80 = true, Color.WHITE, false)


func _set_scan(on: bool) -> void:
	SettingsManager.set_value("scanlines", on)


func _apply_live() -> void:
	Wb13.set_session_colors([_pal[0].to_html(false), _pal[1].to_html(false),
		_pal[2].to_html(false), _pal[3].to_html(false)])


func _reset_all() -> void:
	_reset_colors()
	_delay = 0.35
	_speed = 0.75
	_mouse = 1


func _reset_colors() -> void:
	_pal = Wb13.default_colors()
	_apply_live()


func _last_saved() -> void:
	var saved: Variant = SettingsManager.value(Wb13.settings_key())
	if saved is Array and (saved as Array).size() == 4:
		for i in 4:
			_pal[i] = Color.html(str(saved[i]))
	else:
		_reset_colors()
	_apply_live()


func _save() -> void:
	SettingsManager.set_value(Wb13.settings_key(), [_pal[0].to_html(false), _pal[1].to_html(false),
		_pal[2].to_html(false), _pal[3].to_html(false)])
	Wb13.set_session_colors([])
	UIManager.toast(Loc.t("ui.wb_prefs_app.preferences_gespeichert", "Preferences gespeichert."))
	close_app()


func _use() -> void:
	_apply_live()
	UIManager.toast(Loc.t("ui.wb_prefs_app.farben_gelten_bis_zum_ausschalten", "Farben gelten bis zum Ausschalten."))
	close_app()


func _cancel() -> void:
	_pal = _entry.duplicate()
	Wb13.set_session_colors([])
	close_app()


# ------------------------------------------------------------------ Schieber

func _slider_rects() -> Dictionary:
	return {
		"delay": Rect2(220, 38, 250, 16),
		"speed": Rect2(220, 78, 250, 16),
		"r": Rect2(60, 344, 410, 14),
		"g": Rect2(60, 362, 410, 14),
		"b": Rect2(60, 380, 410, 14),
	}


func _slider_value(key: String) -> float:
	match key:
		"delay": return _delay
		"speed": return _speed
		"r": return (_pal[_sel] as Color).r
		"g": return (_pal[_sel] as Color).g
		_: return (_pal[_sel] as Color).b


func _set_slider(key: String, f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	match key:
		"delay": _delay = f
		"speed": _speed = f
		"r", "g", "b":
			var c: Color = _pal[_sel]
			# 4-Bit-Raster wie die echte Amiga-Palette (0–15 je Kanal)
			var q := roundf(f * 15.0) / 15.0
			match key:
				"r": c.r = q
				"g": c.g = q
				"b": c.b = q
			_pal[_sel] = c
			_apply_live()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var v := Vector2(event.position.x / _sx(), event.position.y / _sy())
			for key in _slider_rects():
				var r: Rect2 = _slider_rects()[key]
				if r.grow(4.0).has_point(v):
					_drag = key
					_set_slider(key, (v.x - r.position.x) / r.size.x)
					accept_event()
					return
		else:
			_drag = ""
	elif event is InputEventMouseMotion and _drag != "":
		var v := Vector2(event.position.x / _sx(), event.position.y / _sy())
		var r: Rect2 = _slider_rects()[_drag]
		_set_slider(_drag, (v.x - r.position.x) / r.size.x)
		accept_event()


# ------------------------------------------------------------------ Zeichnen

func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var font := Wb13.font()
	var sy := _sy()
	var fs := Wb13.fsize(sy)
	var small := maxi(4, int(fs * 0.75))
	draw_rect(Rect2(Vector2.ZERO, size), Wb13.black().lightened(0.02))
	# Titelzeile wie ein Screen: weiß mit Streifen + Tiefen-Gadgets
	draw_rect(_R(Rect2(0, 0, VW, 20)), Wb13.white())
	Wb13.gadget_close(self, _R(Rect2(0, 0, 24, 20)), _sx(), sy * 2.0)
	draw_string(font, _V(30, 16), app_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.black())
	Wb13.drag_stripes(self, _R(Rect2(200, 0, VW - 260, 20)), sy * 2.0)
	Wb13.gadget_depth(self, _R(Rect2(VW - 52, 0, 26, 20)), _sx(), sy * 2.0, false)
	Wb13.gadget_depth(self, _R(Rect2(VW - 26, 0, 26, 20)), _sx(), sy * 2.0, true)

	_btn(font, fs, Rect2(24, 30, 130, 22), "Reset All", false)
	_btn(font, fs, Rect2(24, 58, 130, 22), "Last Saved", false)
	draw_string(font, _V(28, 100), "%02d %s %02d" % [TimeManager.day,
		["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][TimeManager.month - 1],
		TimeManager.year % 100], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
	draw_string(font, _V(28, 118), TimeManager.slot_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, small, Wb13.white())
	_btn(font, fs, Rect2(24, 130, 130, 30), "Change Serial", false)
	draw_string(font, _V(24, 300), "Text", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
	_btn(font, fs, Rect2(60, 286, 40, 18), "60", not _text80)
	_btn(font, fs, Rect2(102, 286, 40, 18), "80", _text80)

	# Key-Repeat-Schieber
	draw_string(font, _V(220, 32), "Key Repeat Delay", HORIZONTAL_ALIGNMENT_CENTER, 250 * _sx(), fs, Wb13.white())
	_slider(font, small, "delay", "Short", "Long")
	draw_string(font, _V(220, 72), "Key Repeat Speed", HORIZONTAL_ALIGNMENT_CENTER, 250 * _sx(), fs, Wb13.white())
	_slider(font, small, "speed", "Slow", "Fast")

	# Interlace (unsere Scanlines)
	draw_string(font, _V(520, 36), "Werkbank", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
	draw_string(font, _V(520, 54), "Interlace", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
	var scan := bool(SettingsManager.value("scanlines"))
	_btn(font, fs, Rect2(520, 62, 52, 20), "On", scan)
	_btn(font, fs, Rect2(574, 62, 52, 20), "Off", not scan)

	# Testfläche (zeigt die Palette in Aktion: Mini-Fenster)
	var test := Rect2(220, 110, 250, 190)
	draw_rect(_R(test), _pal[0])
	draw_rect(_R(test), Wb13.white(), false, maxf(1.0, sy))
	draw_rect(_R(Rect2(test.position.x + 20, test.position.y + 24, 150, 90)), _pal[1])
	draw_rect(_R(Rect2(test.position.x + 20, test.position.y + 24, 150, 16)), _pal[3])
	draw_rect(_R(Rect2(test.position.x + 26, test.position.y + 48, 130, 4)), _pal[2])
	draw_rect(_R(Rect2(test.position.x + 26, test.position.y + 60, 100, 4)), _pal[2])
	draw_string(font, _V(test.position.x + 8, test.position.y + 182), "Werkbank Vorschau",
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, _pal[1])

	# Mausgeschwindigkeit 1/2/4
	draw_string(font, _V(494, 114), "Maus", HORIZONTAL_ALIGNMENT_LEFT, -1, small, Wb13.white())
	for i in 3:
		var m: int = [1, 2, 4][i]
		_btn(font, fs, Rect2(508, 120 + i * 34, 30, 26), str(m), _mouse == m)

	# Palette + RGB-Regler
	for i in 4:
		var sw := Rect2(30 + i * 40, 312, 36, 28)
		draw_rect(_R(sw), _pal[i])
		draw_rect(_R(sw), Wb13.orange() if i == _sel else Wb13.white(), false,
			maxf(2.0, sy * (3.0 if i == _sel else 1.0)))
	_btn(font, fs, Rect2(230, 316, 240, 22), "Reset Colors", false)
	for k in ["r", "g", "b"]:
		var r: Rect2 = _slider_rects()[k]
		draw_string(font, _V(r.position.x - 18, r.position.y + 12), k.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
		_slider(font, small, k, "", "")

	_btn(font, fs, Rect2(472, 306, 102, 24), "Change Printer", false)
	_btn(font, fs, Rect2(472, 336, 102, 24), "Edit Pointer", false)
	_btn(font, fs, Rect2(582, 306, 54, 24), "Save", false)
	_btn(font, fs, Rect2(582, 336, 54, 24), "Use", false)
	_btn(font, fs, Rect2(582, 366, 54, 24), "Cancel", false)
	_draw_scanlines()


func _btn(font: Font, fs: int, r: Rect2, label: String, lit: bool) -> void:
	var pr := _R(r)
	draw_rect(pr, Wb13.orange() if lit else Wb13.blue())
	draw_rect(pr, Wb13.white(), false, maxf(1.0, _sy()))
	draw_string(font, Vector2(pr.position.x, pr.get_center().y + 5.0 * _sy()), label,
		HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, mini(fs, int(pr.size.y * 0.8)),
		Wb13.black() if lit else Wb13.white())


func _slider(font: Font, small: int, key: String, lo: String, hi: String) -> void:
	var r: Rect2 = _slider_rects()[key]
	var pr := _R(r)
	draw_rect(pr, Wb13.blue())
	draw_rect(pr, Wb13.white(), false, maxf(1.0, _sy()))
	var f := _slider_value(key)
	var knob := Rect2(pr.position.x + (pr.size.x - 10.0 * _sx()) * f, pr.position.y,
		10.0 * _sx(), pr.size.y)
	draw_rect(knob, Wb13.white())
	if lo != "":
		draw_string(font, Vector2(pr.position.x - 52.0 * _sx(), pr.end.y - 3.0 * _sy()), lo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, Wb13.white())
		draw_string(font, Vector2(pr.end.x + 6.0 * _sx(), pr.end.y - 3.0 * _sy()), hi,
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, Wb13.white())
