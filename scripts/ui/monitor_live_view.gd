class_name MonitorLiveView
extends Control
## MONITOR-LIVE-VIEW — was der Amiga „gerade laufen lässt", in ECHTZEIT auf der
## Zimmer-Bildröhre. Rendert in einem SubViewport (320×200) einen selbstlaufenden,
## musik-reaktiven Demoscreen: bewegte Copper-Balken, 4-Kanal-VU (echte MOD-Stimmen-
## pegel), ein hüpfender Titel und ein Sinus-Scroller in Topaz-Schrift. Wird von
## UIManager als ViewportTexture in `monitor_texture` gehängt → die Röhre lebt.

const MonitorProfile := preload("res://scripts/ui/monitor_profile.gd")

var _t := 0.0
var _canvas := Vector2(320.0, 200.0)
var _scroll := 320.0
var _title := "SOMMER '90"
var _msg := "AMIGA LÄUFT … *"
var _profile_id := "commodore_1084s"


func _ready() -> void:
	custom_minimum_size = _canvas
	size = _canvas
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_monitor_profile(model_id: String) -> void:
	_profile_id = model_id
	_canvas = Vector2(MonitorProfile.live_canvas_size(model_id))
	custom_minimum_size = _canvas
	size = _canvas
	_scroll = _canvas.x
	queue_redraw()


## Läuft ein neuer Track? Titel + Scrolltext aktualisieren.
func set_track(title: String) -> void:
	_title = title if title != "" else "SOMMER '90"
	_msg = "%s  —  JETZT AUF DEM AMIGA  *  " % _title.to_upper()
	_scroll = _canvas.x


func _process(delta: float) -> void:
	_t += delta
	_scroll -= delta * 70.0 * (_canvas.x / 320.0)
	queue_redraw()


func _draw() -> void:
	var scale_factor := _canvas.x / 320.0
	var w := _canvas.x
	var h := _canvas.y
	# --- Hintergrund: dunkel + wandernde Copper-Balken ---
	draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.02, 0.06))
	for i in 10:
		var yy := fmod(i * 26.0 * scale_factor + _t * 34.0 * scale_factor,
			h + 40.0 * scale_factor) - 20.0 * scale_factor
		var hue := fmod(0.6 + i * 0.05 + _t * 0.06, 1.0)
		var col := Color.from_hsv(hue, 0.7, 0.5, 0.5)
		draw_rect(Rect2(0, yy, w, 12.0 * scale_factor), col)

	# --- 4-Kanal-VU (echte MOD-Stimmenpegel, Fallback: Sinus) ---
	var native: Object = MusicManager.native_player()
	var playing: bool = MusicManager.is_playing()
	var bar_w := 54.0 * scale_factor
	var gap := 14.0 * scale_factor
	var total := 4.0 * bar_w + 3.0 * gap
	var x0 := (w - total) * 0.5
	var base_y := h - 46.0 * scale_factor
	for ch in 4:
		var lvl := 0.0
		if native != null and native.has_method("channel_level") and playing:
			lvl = clampf(float(native.call("channel_level", ch)), 0.0, 1.0)
		else:
			lvl = 0.35 + 0.35 * absf(sin(_t * 3.0 + ch * 1.3))
		var bh := (6.0 + lvl * 74.0) * scale_factor
		var bx := x0 + ch * (bar_w + gap)
		var bcol := Color.from_hsv(fmod(0.33 + ch * 0.12 + _t * 0.1, 1.0), 0.85, 1.0)
		draw_rect(Rect2(bx, base_y - bh, bar_w, bh), bcol)
		draw_rect(Rect2(bx, base_y - bh, bar_w, 3.0 * scale_factor), Color(1, 1, 1, 0.8))
		draw_rect(Rect2(bx, base_y, bar_w, 2.0 * scale_factor), Color(0.5, 0.5, 0.6, 0.6))

	# --- hüpfender Titel oben ---
	var font := Wb13.font()
	var ts := roundi(22.0 * scale_factor)
	var tw := font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
	var tx := (w - tw) * 0.5
	var ty := (40.0 + 10.0 * sin(_t * 2.2)) * scale_factor
	var tcol := Color.from_hsv(fmod(_t * 0.2, 1.0), 0.6, 1.0)
	draw_string(font, Vector2(tx + 2, ty + 2), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(tx, ty), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, tcol)

	# --- Sinus-Scroller unten (Topaz) ---
	var sy := h - 16.0 * scale_factor
	var cx := _scroll
	var scroll_size := roundi(16.0 * scale_factor)
	var mw := font.get_string_size(_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, scroll_size).x
	if cx < -mw:
		_scroll = w
	for i in _msg.length():
		var ch2 := _msg[i]
		var cw := font.get_string_size(ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, scroll_size).x
		if cx > -12.0 * scale_factor and cx < w:
			var wob := 6.0 * scale_factor * sin(_t * 4.0 + cx * 0.05 / scale_factor)
			var col := Color.from_hsv(fmod(cx * 0.004 + _t * 0.3, 1.0), 0.85, 1.0)
			draw_string(font, Vector2(cx, sy + wob), ch2,
				HORIZONTAL_ALIGNMENT_LEFT, -1, scroll_size, col)
		cx += cw

	# Spaete Multisync-Profile zeigen den groesseren nutzbaren Desktop auch im
	# Raum: feine Statuszeile statt eines unsichtbaren Datenbonus.
	if scale_factor > 1.0:
		var workspace: Dictionary = MonitorProfile.effective_workspace(_profile_id)
		var recommended: Array = workspace.get("recommended", [640, 400])
		var info := "MULTISYNC · %dx%d · %d ZEILEN" % [
			int(recommended[0]), int(recommended[1]),
			int(workspace.get("visible_rows", 25))]
		draw_string(font, Vector2(8.0 * scale_factor, 14.0 * scale_factor),
			info, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(8.0 * scale_factor),
			Color(0.62, 0.93, 0.86, 0.88))
