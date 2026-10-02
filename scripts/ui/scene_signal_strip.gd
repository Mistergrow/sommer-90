class_name SceneSignalStrip
extends Control
## Skalierbarer Pixel-Szene-Signalstreifen für HUD-Flächen. Keine Videodatei:
## Copperbars, Starfield, Raster, Vektorgitter und Bobs werden pixelgenau in der
## tatsächlichen Panelgröße gezeichnet und bleiben dadurch in jedem Export scharf.

signal activated

const RedrawCadenceScript := preload("res://scripts/util/redraw_cadence.gd")

var effect := "copper":
	set(value):
		effect = value
		queue_redraw()
var caption := "SOMMER '90":
	set(value):
		caption = value
		queue_redraw()
var subtitle := "SCENE SIGNAL":
	set(value):
		subtitle = value
		queue_redraw()
var alert := false:
	set(value):
		alert = value
		queue_redraw()
var compact := false
var interactive := false
## Zeichenbudget fuer OCS/ECS/AGA-artige Nutzer. 1 bleibt grob und sparsam,
## 3 nutzt sichtbar mehr Bobs/Zellen/Abtastpunkte. Der Inhalt bleibt in allen
## Stufen derselbe; nur die historische Darstellungsdichte waechst.
var detail_level := 2
## Nicht musikreaktive Streifen muessen nicht mit der Monitorfrequenz neu
## aufgebaut werden. AGA-Karten duerfen diesen Wert gezielt auf 50 anheben.
var redraw_hz := 30.0
## Nur der breite Saisonrahmen liest den echten ProTracker-Status. Der kompakte
## Notizboard-Streifen bleibt bewusst ruhig und informationsorientiert.
var music_reactive := false
var _t := 0.0
var _redraw_cadence := RedrawCadenceScript.new()
# Fonts erst nach dem PCK-Mount laden. Ein GDScript-preload wird vom Windows-
# Release-Template bereits während der Klassenkompilierung aufgelöst, bevor der
# importierte Font-Remap zuverlässig verfügbar ist. ResourceLoader/load nutzt
# anschließend dieselbe FontFile-Ressource ohne visuellen Unterschied.
var _font: Font = load("res://assets/fonts/VT323_UI.ttf")


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if interactive else Control.CURSOR_ARROW
	set_process(not bool(SettingsManager.value("reduced_motion")))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var effective_hz := 50.0 if music_reactive else clampf(redraw_hz, 10.0, 60.0)
	if not _redraw_cadence.advance(delta, effective_hz):
		return
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if interactive and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activated.emit()
		accept_event()


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color8(7, 12, 22))
	match effect:
		"starfield": _draw_starfield()
		"raster": _draw_rasterwave()
		"vector": _draw_vectorgrid()
		"bobs": _draw_bobs()
		"plasma": _draw_plasma()
		"scope": _draw_scope()
		_: _draw_copper()
	_draw_scanlines()
	_draw_titles()
	if alert:
		_draw_alert()


func _draw_copper() -> void:
	var drive := _audio_drive()
	var rows := (6 + detail_level) if compact else (7 + detail_level * 2)
	for i in rows:
		var f := float(i) / maxf(1.0, float(rows - 1))
		var wave := 0.5 + 0.5 * sin(_t * 2.2 + f * 8.0)
		var col := Color(0.98, 0.52, 0.08).lerp(Color(0.72, 0.10, 0.56), wave)
		var y := size.y * (0.16 + f * 0.68)
		var x_pad := (0.05 + (0.04 + drive * 0.10) * sin(_t * (0.8 + drive) + i)) * size.x
		draw_rect(Rect2(x_pad, y, maxf(2.0, size.x - x_pad * 2.0), 1.0 + float(i % 3)), Color(col, 0.34 + wave * 0.26))


func _draw_starfield() -> void:
	var drive := _audio_drive()
	var count := (22 + detail_level * 6) if compact else (34 + detail_level * 11)
	var center := size * 0.5
	for i in count:
		var phase := fposmod(float(i) * 0.618033 + _t * (0.035 + drive * 0.075 + float(i % 5) * 0.006), 1.0)
		var angle := float(i * 47 % 360) * PI / 180.0
		var radius := phase * maxf(size.x, size.y) * 0.58
		var p := center + Vector2(cos(angle), sin(angle)) * radius
		var pixel := 1.0 if phase < 0.62 else 2.0
		draw_rect(Rect2(p.floor(), Vector2(pixel, pixel)), Color(0.72, 0.91, 1.0, 0.22 + phase * 0.72))


func _draw_rasterwave() -> void:
	var drive := _audio_drive()
	var rows := 9 + detail_level * 3
	for i in rows:
		var y := size.y * float(i + 1) / float(rows + 1)
		var x := sin(_t * (1.4 + drive * 2.4) + i * 0.52) * size.x * (0.07 + drive * 0.12)
		var col := Color(0.10, 0.83, 0.92).lerp(Color(0.94, 0.24, 0.68), float(i) / maxf(1.0, float(rows - 1)))
		draw_rect(Rect2(x, y, size.x, 1.0 + float(i % 4 == 0)), Color(col, 0.34))


func _draw_vectorgrid() -> void:
	var drive := _audio_drive()
	var horizon := size.y * 0.48
	var spokes := 6 + detail_level * 2
	for i in spokes:
		var x := size.x * float(i) / maxf(1.0, float(spokes - 1))
		draw_line(Vector2(size.x * 0.5, horizon), Vector2(x, size.y), Color(0.16, 0.78, 0.77, 0.29), 1.0)
	var depth_lines := 4 + detail_level * 2
	for i in depth_lines:
		var f := fposmod(float(i) / float(depth_lines) + _t * (0.10 + drive * 0.22), 1.0)
		var y := horizon + pow(f, 1.8) * (size.y - horizon)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.21, 0.88, 0.75, 0.18 + f * 0.25), 1.0)


func _draw_bobs() -> void:
	var drive := _audio_drive()
	var count := 5 + detail_level * 2
	for i in count:
		var x := fposmod(float(i) * size.x / maxf(1.0, float(count - 1)) + _t * (12.0 + i), size.x + 20.0) - 10.0
		var y := size.y * (0.50 + (0.13 + drive * 0.18) * sin(_t * (1.3 + drive) + i * 0.83))
		var radius := 2.0 + float(i % 3) + drive * 1.8
		var col: Color = [Color8(246, 158, 38), Color8(219, 66, 139), Color8(75, 210, 219)][i % 3]
		draw_circle(Vector2(x, y), radius + 2.0, Color(0, 0, 0, 0.48))
		draw_circle(Vector2(x, y), radius, Color(col, 0.78))
		draw_rect(Rect2(x - radius * 0.5, y - radius * 0.55, 1.0, 1.0), Color(1, 1, 0.86, 0.85))


## Klassische OCS-Plasma-Hommage: blockige Farbfelder, deren Phase und Kontrast
## direkt von den vier echten MOD-Kanaelen kommen.
func _draw_plasma() -> void:
	var levels := _channel_levels()
	var cell := (7.0 - detail_level) if compact else (10.0 - detail_level * 2.0)
	var cols := ceili(size.x / cell)
	var rows := ceili(size.y / cell)
	var palette := [Color8(18, 50, 112), Color8(92, 34, 132), Color8(210, 52, 116), Color8(250, 156, 42)]
	for y in rows:
		for x in cols:
			var ch := (x + y) % 4
			var v := sin(x * 0.48 + _t * (0.8 + levels[ch] * 2.8)) \
				+ cos(y * 0.61 - _t * (0.7 + levels[(ch + 1) % 4] * 2.2))
			var index := clampi(int(floor((v + 2.0) * 0.99)), 0, 3)
			draw_rect(Rect2(x * cell, y * cell, cell + 1.0, cell + 1.0), Color(palette[index], 0.38 + levels[ch] * 0.34))


## Vierkanal-Oszilloskop. Es nutzt Patternposition und Kanalpegel des nativen
## MOD-Replayers; ohne Musik wird daraus eine ruhige Null-Linie.
func _draw_scope() -> void:
	var levels := _channel_levels()
	for ch in 4:
		var points := PackedVector2Array()
		var mid := size.y * (0.21 + ch * 0.19)
		var amp := (2.0 + levels[ch] * size.y * 0.11)
		var sample_step := 7 - detail_level
		for x in range(0, int(size.x) + sample_step, sample_step):
			var wave := sin(float(x) * (0.12 + ch * 0.025) + _t * (3.0 + ch))
			points.append(Vector2(x, mid + wave * amp))
		var color: Color = [Color8(255, 146, 28), Color8(235, 55, 146),
			Color8(62, 215, 222), Color8(245, 224, 92)][ch]
		draw_polyline(points, Color(color, 0.42 + levels[ch] * 0.50), 1.0)


func _draw_scanlines() -> void:
	for y in range(1, int(size.y), 3):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.15), 1.0)


func _draw_titles() -> void:
	var main_size := clampi(int(size.y * 0.38), 18, 24) if compact else 21
	var sub_size := 10 if compact and size.y >= 42.0 else 9
	var shown_caption := caption
	var shown_subtitle := subtitle.to_upper()
	if music_reactive and MusicManager.is_playing():
		var track: Dictionary = MusicManager.playback_track(MusicManager.current)
		shown_caption = str(track.get("title", "MOD SIGNAL")).to_upper().left(30)
		var view: Dictionary = MusicManager.native_player().playback_view(1)
		shown_subtitle = "MOD %02X:%02X · %03d BPM · %s '%02d" % [
			int(view.get("order", 0)), int(view.get("row", 0)), int(view.get("bpm", 125)),
			TimeManager.season_name().to_upper(), TimeManager.year % 100]
	var baseline := clampf(size.y * 0.52, float(main_size) + 2.0, size.y - float(sub_size) - 8.0)
	# Das kleine Notizdisplay kann bei Starfield/Copper sehr kontrastreich sein.
	# Eine gemeinsame dunkle Textplatte hält beide Zeilen deutlich, ohne den
	# Effekt zu verstecken.
	draw_rect(Rect2(2, baseline - main_size + 1, size.x - 4, main_size + 3),
		Color(0.015, 0.02, 0.04, 0.70))
	var shadow := Vector2(1.0, 2.0)
	draw_string(_font, Vector2(0, baseline) + shadow, shown_caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, main_size, Color(0, 0, 0, 0.82))
	draw_string(_font, Vector2(0, baseline), shown_caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, main_size,
		Color8(255, 210, 92) if not alert else Color8(255, 244, 190))
	# Baseline bleibt mindestens vier Pixel innerhalb des Clip-Rahmens; damit
	# schneidet die HUD-Leiste die Unterlaengen nicht mehr ab.
	draw_rect(Rect2(2, size.y - sub_size - 5, size.x - 4, sub_size + 4),
		Color(0.01, 0.015, 0.03, 0.74))
	var sub_y := size.y - 4.0
	draw_string(_font, Vector2(0, sub_y), shown_subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x, sub_size, Color(0.70, 0.86, 0.92, 0.88))


func _draw_alert() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 5.2)
	var border := Color(1.0, 0.70 + pulse * 0.22, 0.16, 0.70 + pulse * 0.26)
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), border, false, 2.0)
	# Kein wandernder Balken mehr am oberen Rand: er kollidierte optisch mit dem
	# Bezel. Nur die seitlichen, vollstaendig im Rahmen liegenden Signalpfeile pulsieren.
	for side in 2:
		var x := 5.0 if side == 0 else size.x - 9.0
		var direction := 1.0 if side == 0 else -1.0
		var y := size.y * 0.5
		var chevron := PackedVector2Array([Vector2(x, y - 4), Vector2(x + direction * 4, y), Vector2(x, y + 4)])
		draw_polyline(chevron, Color(1.0, 0.84, 0.28, 0.65 + pulse * 0.35), 2.0)


func _channel_levels() -> Array[float]:
	var result: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if not music_reactive or not MusicManager.is_playing():
		return result
	var player := MusicManager.native_player()
	for channel in 4:
		result[channel] = clampf(float(player.channel_level(channel)), 0.0, 1.0)
	return result


func _audio_drive() -> float:
	var levels := _channel_levels()
	return clampf((levels[0] + levels[1] + levels[2] + levels[3]) * 0.25, 0.0, 1.0)
