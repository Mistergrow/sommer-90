class_name StartupCracktroOverlay
extends Control
## Authentische, aber vollstaendig fiktive Release-Statuslage des Startintros.
## Sie behauptet keine reale Crackgruppe und kopiert kein historisches Logo.

const CYAN := Color8(75, 224, 228)
const MAGENTA := Color8(242, 78, 179)
const AMBER := Color8(255, 182, 48)
const WHITE := Color8(230, 248, 242)
const DIM := Color8(112, 151, 157)

var _t := 0.0
var _crew := "NIGHTSHIFT CREW"
var _release := "S90-001"
var _status := "TRAINED · FIXED · CRUNCHED"
var _authenticity := "FICTIONAL SCENE RELEASE · ORIGINAL CODE"
var _machine := "A500 · OCS · PAL · DF0: · 4CH"


func configure(crew: String, release_id: String, status: String,
		authenticity: String, machine: String = "A500 · OCS · PAL · DF0: · 4CH") -> void:
	_crew = crew.strip_edges().to_upper()
	_release = release_id.strip_edges().to_upper()
	_status = status.strip_edges().to_upper()
	_authenticity = authenticity.strip_edges().to_upper()
	_machine = machine.strip_edges().to_upper()
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if size.x < 320.0 or size.y < 180.0:
		return
	var font := Wb13.font()
	var margin := maxf(14.0, floorf(size.x * 0.018))
	var strip_h := clampf(size.y * 0.092, 54.0, 78.0)
	var strip := Rect2(margin, margin, size.x - margin * 2.0, strip_h)
	draw_rect(strip, Color(0.0, 0.0, 0.018, 0.86))
	draw_line(strip.position, Vector2(strip.end.x, strip.position.y), CYAN, 2.0)
	draw_line(Vector2(strip.position.x, strip.end.y), strip.end, MAGENTA, 2.0)

	var main_size := clampi(int(size.y * 0.024), 13, 20)
	var sub_size := clampi(main_size - 3, 10, 15)
	draw_string(font, strip.position + Vector2(12.0, 24.0),
		"%s  ·  RELEASE %s" % [_crew, _release],
		HORIZONTAL_ALIGNMENT_LEFT, -1, main_size, WHITE)
	draw_string(font, strip.position + Vector2(12.0, 45.0), _status,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, AMBER)

	var machine_width := font.get_string_size(_machine,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
	draw_string(font, Vector2(strip.end.x - machine_width - 12.0, strip.position.y + 24.0),
		_machine, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, CYAN)

	# Vier diskrete Paula-Kanaele statt eines modernen Audio-Waveforms.
	var meter_width := minf(210.0, strip.size.x * 0.24)
	var meter_x := strip.end.x - meter_width - 12.0
	var meter_y := strip.position.y + 36.0
	for channel in 4:
		var level := 3 + posmod(floori(_t * (8.0 + channel)) + channel * 3, 8)
		var channel_x := meter_x + channel * (meter_width / 4.0)
		for segment in 8:
			var color := CYAN if segment < 5 else (AMBER if segment < 7 else MAGENTA)
			color.a = 0.95 if segment < level else 0.16
			draw_rect(Rect2(channel_x + segment * 5.0, meter_y, 3.0, 9.0), color)

	var authenticity_width := font.get_string_size(_authenticity,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
	var auth_x := floorf((size.x - authenticity_width) * 0.5)
	var auth_y := strip.end.y + clampf(size.y * 0.035, 18.0, 32.0)
	draw_string(font, Vector2(auth_x + 1.0, auth_y + 1.0), _authenticity,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, Color(0.0, 0.0, 0.0, 0.9))
	draw_string(font, Vector2(auth_x, auth_y), _authenticity,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, Color(DIM, 0.88))
