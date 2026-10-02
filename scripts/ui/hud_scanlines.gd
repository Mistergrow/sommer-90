class_name HudScanlines
extends Control
## Dezente CRT-Scanlines über einer HUD-Leiste: feine dunkle Zeilen plus ein langsam
## rollendes Helligkeitsband (Bildröhren-Gefühl). An/aus über SettingsManager "scanlines".

const LINE_GAP := 3.0                       # Abstand der Scanlines in px
const LINE_COL := Color(0.0, 0.0, 0.0, 0.22)
const BAND_COL := Color(0.6, 0.88, 1.0, 0.09)   # kühles Rollband
const REDRAW_HZ := 30.0
const RedrawCadenceScript := preload("res://scripts/util/redraw_cadence.gd")


var _t := 0.0
var _redraw_cadence := RedrawCadenceScript.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_setting()
	SettingsManager.settings_changed.connect(_apply_setting)


func _apply_setting() -> void:
	var on := bool(SettingsManager.value("scanlines"))
	visible = on
	_redraw_cadence.reset()
	set_process(on)


func _process(delta: float) -> void:
	_t += delta
	if not _redraw_cadence.advance(delta, REDRAW_HZ):
		return
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# feine, gleichmäßige Scanlines
	var y := 0.0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), LINE_COL, 1.0)
		y += LINE_GAP
	# langsam von oben nach unten wanderndes, weiches Helligkeitsband
	var band_y: float = fmod(_t * 26.0, h + 40.0) - 20.0
	for i in 9:
		var yy := band_y + float(i) - 4.0
		if yy < 0.0 or yy > h:
			continue
		var falloff: float = 1.0 - absf(float(i) - 4.0) / 4.0
		draw_line(Vector2(0, yy), Vector2(w, yy), Color(BAND_COL, BAND_COL.a * falloff), 1.0)
