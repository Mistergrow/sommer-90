class_name StartupLoadPrelude
extends Control
## Kurzer, rein visueller PAL-Ladeimpuls vor dem Start-Cracktro.
##
## Historische Custom-Loader machten ihren Disk-/Decrunch-Zustand oft ueber
## harte Registerfarben im Rand sichtbar. Diese Inszenierung zitiert das mit
## diskreten 25-Hz-Schritten, bleibt aber absichtlich dunkel und kurz, damit
## daraus kein aggressives Vollbildflackern wird.

signal completed

const NORMAL_DURATION := 1.08
const REDUCED_DURATION := 0.18
const COLORS := [
	Color8(9, 7, 28),
	Color8(49, 24, 111),
	Color8(116, 38, 155),
	Color8(223, 56, 132),
	Color8(248, 111, 44),
	Color8(255, 190, 66),
	Color8(54, 204, 210),
	Color8(118, 246, 217),
]

var _elapsed := 0.0
var _reduced_motion := false
var _completed_once := false
var _drive_label := "DF0:"
var _load_label := "LOADING"


func configure(reduced_motion: bool, drive_label: String = "DF0:",
		load_label: String = "LOADING") -> void:
	_reduced_motion = reduced_motion
	_drive_label = drive_label.strip_edges().to_upper()
	_load_label = load_label.strip_edges().to_upper()
	if is_node_ready():
		_elapsed = 0.0
		_completed_once = false
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _completed_once:
		return
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration():
		_complete()


func duration() -> float:
	return REDUCED_DURATION if _reduced_motion else NORMAL_DURATION


func progress() -> float:
	return clampf(_elapsed / maxf(duration(), 0.001), 0.0, 1.0)


func _complete() -> void:
	if _completed_once:
		return
	_completed_once = true
	set_process(false)
	completed.emit()


func _draw() -> void:
	if size.x < 16.0 or size.y < 16.0:
		return
	var p := progress()
	var step := floori(_elapsed * (12.0 if _reduced_motion else 25.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.001, 0.001, 0.006, 1.0))

	# Die breiten Registerbaender stehen nur ganz kurz voll im Bild. Gegen Ende
	# ziehen sie sich in den PAL-Rand zurueck; dahinter beginnt das Intro schwarz.
	var collapse := smoothstep(0.58, 0.94, p)
	var band_height := maxf(5.0, ceilf(size.y / 15.0))
	for band in 15:
		var y := band * band_height
		var phase := posmod(step + band * 3, COLORS.size())
		var color: Color = COLORS[phase]
		var alternate := 0.58 + 0.30 * float(posmod(step + band, 3)) / 2.0
		color.a = alternate * (1.0 - collapse * 0.64)
		var edge_width := lerpf(size.x, maxf(18.0, size.x * 0.055), collapse)
		var offset := float(posmod(step * 17 + band * 43, 73)) - 36.0
		if band % 2 == 0:
			draw_rect(Rect2(-42.0 + offset * (1.0 - collapse), y,
				edge_width + 84.0, band_height + 1.0), color)
		else:
			draw_rect(Rect2(size.x - edge_width - 42.0 - offset * (1.0 - collapse), y,
				edge_width + 84.0, band_height + 1.0), color)

	# Schwarzer Decrunch-Schlitz: bewusst asymmetrisch und in groben Schritten,
	# wie ein Custom-Loader und nicht wie ein moderner Fortschrittsbalken.
	var slit_h := lerpf(size.y * 0.12, size.y * 0.72, smoothstep(0.12, 0.78, p))
	var slit := Rect2(size.x * 0.115, (size.y - slit_h) * 0.5, size.x * 0.77, slit_h)
	draw_rect(slit, Color(0.0, 0.0, 0.008, 0.96))
	draw_line(slit.position, Vector2(slit.end.x, slit.position.y),
		COLORS[posmod(step + 5, COLORS.size())], 1.0, false)
	draw_line(Vector2(slit.position.x, slit.end.y), slit.end,
		COLORS[posmod(step + 2, COLORS.size())], 1.0, false)

	if p > 0.16 and p < 0.92:
		var font := Wb13.font()
		var font_size := clampi(int(size.y * 0.025), 13, 20)
		var track := clampi(floori(p * 80.0), 0, 79)
		var status := "%s  TRACK %02d  ·  %s" % [_drive_label, track, _load_label]
		var width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(floorf((size.x - width) * 0.5), floorf(size.y * 0.53))
		draw_string(font, pos + Vector2(2.0, 2.0), status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.9))
		draw_string(font, pos, status, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			COLORS[posmod(step + 6, COLORS.size())])

	# Feine PAL-Zeilen verbinden Loader und nachfolgende Demo optisch.
	for y in range(1, int(size.y), 4):
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.0, 0.0, 0.0, 0.13), 1.0)
