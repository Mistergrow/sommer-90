class_name PhoneConsoleFX
extends Control
## Code-native Unterlage fuer den Telefonplatz: Holzmaserung, Anschlusskabel,
## Impulsleitung und dezentes AGA-Copper-Leuchten. Keine Eingabe wird abgefangen.

var phase := "dialtone"
var pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func set_phase(value: String) -> void:
	phase = value
	queue_redraw()


func _process(delta: float) -> void:
	if bool(SettingsManager.value("reduced_motion")):
		return
	if phase in ["checking", "ringing", "connected"]:
		pulse = fmod(pulse + delta * (2.7 if phase == "ringing" else 1.5), 1.0)
		queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color8(44, 34, 27), true)
	# Warmes, bewusst niedrig aufgeloestes Holzraster statt Fototextur.
	for y: int in range(8, int(size.y), 13):
		var wobble := sin(float(y) * 0.073) * 9.0
		draw_line(Vector2(0, y), Vector2(size.x, y + wobble),
			Color(0.34, 0.23, 0.16, 0.24), 2.0)
	for x: int in range(18, int(size.x), 47):
		draw_line(Vector2(x, 0), Vector2(x + 24, size.y),
			Color(0.08, 0.06, 0.05, 0.12), 1.0)

	# Telefonkabel: dicke dunkle Seele plus kaltes AGA-Kantenlicht.
	var cable: PackedVector2Array = []
	for index: int in 37:
		var t := float(index) / 36.0
		var x := lerpf(size.x * 0.035, size.x * 0.43, t)
		var y := size.y * 0.83 + sin(t * TAU * 4.5) * 9.0 + t * 20.0
		cable.append(Vector2(x, y))
	if cable.size() > 1:
		draw_polyline(cable, Color8(8, 10, 12), 7.0, true)
		draw_polyline(cable, Color8(58, 92, 112), 2.0, true)

	# Anschlussdose und Leitungssignal rechts unten.
	var jack := Rect2(size.x - 78.0, size.y - 54.0, 48.0, 28.0)
	draw_rect(jack, Color8(25, 27, 27), true)
	draw_rect(jack, Color8(116, 105, 86), false, 2.0)
	draw_rect(Rect2(jack.position + Vector2(14, 8), Vector2(20, 10)), Color8(4, 8, 9), true)

	var signal_color := _signal_color()
	var y_signal := size.y - 18.0
	draw_line(Vector2(size.x * 0.47, y_signal), Vector2(size.x - 88.0, y_signal),
		signal_color.darkened(0.45), 1.0)
	for index: int in 12:
		var x := lerpf(size.x * 0.48, size.x - 94.0, float(index) / 11.0)
		var strength := 4.0
		if phase in ["checking", "ringing", "connected"]:
			strength += sin((float(index) / 11.0 + pulse) * TAU * 2.0) * 4.0
		draw_line(Vector2(x, y_signal - strength), Vector2(x, y_signal + strength), signal_color, 2.0)

	# Kupferartige obere/untere Kanten geben dem Panel eine AGA-Signatur.
	for band: int in 3:
		var color: Color = [Color8(41, 184, 224, 95), Color8(151, 70, 199, 75),
			Color8(246, 151, 47, 85)][band]
		draw_line(Vector2(6, 5 + band * 2), Vector2(size.x - 6, 5 + band * 2), color, 1.0)


func _signal_color() -> Color:
	match phase:
		"connected": return Palette.LCD_GREEN
		"checking", "ringing": return Palette.LCD_CYAN
		"error", "busy": return Palette.LCD_AMBER
	return Color8(73, 119, 95)
