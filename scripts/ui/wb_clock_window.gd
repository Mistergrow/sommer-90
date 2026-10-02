class_name WbClockWindow
extends Wb13Window
## Clock V2.22 — die analoge Werkbank-Uhr wie im Original: weißes Zifferblatt,
## Rauten bei 12/3/6/9, Punkte dazwischen, schwarze Zeiger, AM/PM rechts oben.
## Die Zeit kommt aus dem Zeitfenster des Spiels (TimeManager.slot); der
## Sekundenzeiger läuft in Echtzeit weiter — die Uhr soll leben. Im 3.1-Modus
## ergänzt die untere Bedienzeile Datum und einen zustandsbasierten Alarm.

var digital := false   # ClockPtr-Modus: kleine Digitalanzeige statt Zifferblatt
var _t := 0.0
var _date_view := false
var _alarm_minutes := 8 * 60
var _alarm_enabled := false
var _alarm_fired := false

signal alarm_triggered(minutes: int)


func _init() -> void:
	title = Loc.t("ui.wb_clock_window.clock_v2_22", "Clock  V2.22")
	resizable = false


func _ready() -> void:
	super()
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_check_alarm()
	if int(_t) != int(_t - delta):
		queue_redraw()


func set_alarm(minutes: int, enabled := true) -> void:
	_alarm_minutes = wrapi(minutes, 0, 24 * 60)
	_alarm_enabled = enabled
	_alarm_fired = false
	queue_redraw()


func alarm_state() -> Dictionary:
	return {
		"enabled": _alarm_enabled,
		"minutes": _alarm_minutes,
		"fired": _alarm_fired,
		"date_view": _date_view,
	}


func _check_alarm() -> void:
	if not _alarm_enabled or _alarm_fired:
		return
	if TimeManager.clock_minutes() >= _alarm_minutes:
		_alarm_fired = true
		alarm_triggered.emit(_alarm_minutes)
		UIManager.toast(Loc.t("ui.wb_clock_window.clock_alarm_02d_02d", "CLOCK: Alarm %02d:%02d.") % [
			floori(float(_alarm_minutes) / 60.0), _alarm_minutes % 60])


func _content_draw(crp: Rect2, sx: float, sy: float) -> void:
	var font := Wb13.font()
	var fs := Wb13.fsize(sy)
	var hour: float = float(TimeManager.clock_minutes()) / 60.0
	if digital:
		var minute_d := int(fmod(hour, 1.0) * 60.0)
		var h12 := int(fmod(hour, 12.0))
		draw_string(font, Vector2(crp.position.x, crp.get_center().y + 8.0 * sy),
			"%d:%02d %s" % [12 if h12 == 0 else h12, minute_d, "AM" if hour < 12.0 else "PM"],
			HORIZONTAL_ALIGNMENT_CENTER, crp.size.x, int(fs * 1.4), Wb13.white())
		return
	var controls_h := 24.0 * sy
	var clock_area := Rect2(crp.position, Vector2(crp.size.x, crp.size.y - controls_h))
	if _date_view:
		_draw_date(clock_area, sx, sy, font, fs)
		_draw_controls(crp, sx, sy, font, fs)
		return
	draw_string(font, Vector2(crp.end.x - 40.0 * sx, crp.position.y + 18.0 * sy),
		"AM" if hour < 12.0 else "PM", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Wb13.white())
	var c := clock_area.get_center() + Vector2(0, 2.0 * sy)
	var rad := minf(clock_area.size.x, clock_area.size.y) * 0.39
	draw_circle(c, rad, Wb13.white())
	draw_arc(c, rad, 0.0, TAU, 48, Wb13.black(), maxf(1.5, sy * 1.5))
	for i in 12:
		var a := TAU * i / 12.0 - PI * 0.5
		var p := c + Vector2(cos(a), sin(a)) * rad * 0.86
		if i % 3 == 0:
			# Raute
			var d := 4.0 * sy
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -d), p + Vector2(d * 0.6, 0), p + Vector2(0, d), p + Vector2(-d * 0.6, 0)]),
				Wb13.black())
		else:
			draw_circle(p, maxf(1.5, sy * 1.4), Wb13.black())
	var minute := fmod(hour, 1.0) * 60.0 + fmod(_t, 60.0) / 60.0
	var ha := TAU * fmod(hour, 12.0) / 12.0 - PI * 0.5
	var ma := TAU * minute / 60.0 - PI * 0.5
	var sa := TAU * fmod(_t, 60.0) / 60.0 - PI * 0.5
	draw_line(c, c + Vector2(cos(ha), sin(ha)) * rad * 0.5, Wb13.black(), maxf(2.5, sy * 3.0))
	draw_line(c, c + Vector2(cos(ma), sin(ma)) * rad * 0.74, Wb13.black(), maxf(1.8, sy * 2.0))
	draw_line(c, c + Vector2(cos(sa), sin(sa)) * rad * 0.78, Wb13.orange(), maxf(1.0, sy))
	draw_circle(c, maxf(2.0, sy * 2.2), Wb13.black())
	_draw_controls(crp, sx, sy, font, fs)


func _draw_date(area: Rect2, _unused_scale_x: float, sy: float, font: Font, fs: int) -> void:
	var center_y := area.get_center().y
	draw_string(font, Vector2(area.position.x, center_y - 16.0 * sy),
		TimeManager.localized_weekday_name().to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
		area.size.x, fs, Wb13.orange())
	draw_string(font, Vector2(area.position.x, center_y + 12.0 * sy),
		"%02d.%02d.%04d" % [TimeManager.day, TimeManager.month, TimeManager.year],
		HORIZONTAL_ALIGNMENT_CENTER, area.size.x, int(fs * 1.25), Wb13.white())
	var minutes := TimeManager.clock_minutes()
	draw_string(font, Vector2(area.position.x, center_y + 34.0 * sy),
		"%02d:%02d" % [floori(float(minutes) / 60.0), minutes % 60],
		HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, Wb13.white())


func _draw_controls(crp: Rect2, sx: float, sy: float, font: Font, fs: int) -> void:
	var y := crp.end.y - 22.0 * sy
	var w := crp.size.x / 3.0
	var labels := ["UHR" if _date_view else "DATUM",
		"AL +15", "AL %s" % ("AN" if _alarm_enabled else "AUS")]
	for i in 3:
		var r := Rect2(crp.position.x + i * w, y, w - sx, 20.0 * sy)
		draw_rect(r, Wb13.white())
		draw_rect(r, Wb13.black(), false, maxf(1.0, sy))
		draw_string(font, Vector2(r.position.x, r.end.y - 5.0 * sy), labels[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Wb13.black())
	if _alarm_enabled:
		draw_string(font, Vector2(crp.position.x, y - 3.0 * sy),
			"ALARM %02d:%02d" % [
				floori(float(_alarm_minutes) / 60.0), _alarm_minutes % 60],
			HORIZONTAL_ALIGNMENT_CENTER, crp.size.x, fs, Wb13.orange())


func _content_press(v: Vector2, _dbl: bool) -> void:
	if digital:
		return
	var cr := content_rect()
	if v.y < cr.size.y - 24.0:
		return
	var third := cr.size.x / 3.0
	var section := clampi(floori(v.x / third), 0, 2)
	match section:
		0:
			_date_view = not _date_view
		1:
			set_alarm(_alarm_minutes + 15, _alarm_enabled)
		2:
			set_alarm(_alarm_minutes, not _alarm_enabled)
	queue_redraw()
