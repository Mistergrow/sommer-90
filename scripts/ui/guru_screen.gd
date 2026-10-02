class_name GuruScreen
extends Control
## Guru Meditation — der legendäre Amiga-Absturzbildschirm, originalgetreu:
## schwarzer Schirm, oben ein rot umrandeter Kasten (Rahmen BLINKT), roter
## Topaz-Text „Software Failure.  Press left mouse button to continue." und
## die Guru-Nummer. Linke Maustaste = Neustart (zurück über die Boot-Sequenz).

const RED := Color8(255, 48, 32)
const VW := 640.0
const VH := 400.0

var code := "#00000004.0000AAC0"
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	focus_mode = Control.FOCUS_ALL
	var parent := get_parent_control()
	if parent != null:
		parent.resized.connect(_sync_size)
	_sync_size.call_deferred()
	set_process(true)
	grab_focus.call_deferred()
	AudioManager.floppy_insert()   # das Klack beim Wegkippen


func _sync_size() -> void:
	var parent := get_parent_control()
	if parent != null:
		position = Vector2.ZERO
		size = parent.size
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if int(_t * 1.5) != int((_t - delta) * 1.5):
		queue_redraw()   # Rahmen blinkt ~1x/Sekunde


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		UIManager.reboot_from_guru()


func _draw() -> void:
	var sx := size.x / VW
	var sy := size.y / VH
	var fs := Wb13.fsize(sy)
	var font := Wb13.font()
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var box := Rect2(10.0 * sx, 8.0 * sy, (VW - 20.0) * sx, 76.0 * sy)
	if int(_t * 1.5) % 2 == 0:
		var bw := maxf(2.0, 3.0 * sy)
		draw_rect(box, RED, false, bw)
		draw_rect(box.grow(-bw * 2.0), RED, false, maxf(1.0, sy))
	draw_string(font, Vector2(0, 36.0 * sy),
		"Software Failure.    Press left mouse button to continue.",
		HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, RED)
	draw_string(font, Vector2(0, 64.0 * sy), "Guru Meditation %s" % code,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, RED)
