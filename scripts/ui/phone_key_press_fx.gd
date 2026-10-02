class_name PhoneKeyPressFX
extends Control
## Kurzer Druckimpuls fuer eine Taste des echten Telefonbildes.
##
## Das Telefon-Asset enthaelt die vollstaendigen Tastenkappen bereits. Ein
## zweiter Bildausschnitt erzeugt bei Skalierung sichtbare Naehte. Dieser Effekt
## zeichnet deshalb nur Licht, Kontaktschatten und eine kurze AGA-Impulsflanke
## ueber der Originaltaste und verschwindet danach restlos.

var energy := 0.0
var _pulse_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	queue_redraw()


func trigger() -> void:
	if is_instance_valid(_pulse_tween):
		_pulse_tween.kill()
	energy = 1.0
	visible = true
	queue_redraw()
	var duration := 0.08 if bool(SettingsManager.value("reduced_motion")) else 0.18
	_pulse_tween = create_tween()
	_pulse_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_method(_set_energy, 1.0, 0.0, duration)
	_pulse_tween.tween_callback(_finish)


func _set_energy(value: float) -> void:
	energy = value
	queue_redraw()


func _finish() -> void:
	energy = 0.0
	visible = false
	queue_redraw()


func _draw() -> void:
	if energy <= 0.001 or size.x <= 1.0:
		return
	# Perspektivische Innenflaeche der schraeg fotografierten Tastenkappe. Sie
	# bleibt bewusst innerhalb des vorhandenen hellen Caps: keine Rechteckkante,
	# kein kopierter Hintergrund und kein zweiter Ziffernaufdruck.
	var face := PackedVector2Array([
		Vector2(size.x * 0.25, size.y * 0.27),
		Vector2(size.x * 0.76, size.y * 0.15),
		Vector2(size.x * 0.88, size.y * 0.58),
		Vector2(size.x * 0.36, size.y * 0.72),
	])
	draw_colored_polygon(face, Color(0.05, 0.11, 0.09, 0.18 * energy))
	var outline := PackedVector2Array([face[0], face[1], face[2], face[3], face[0]])
	draw_polyline(outline, Color(0.25, 0.94, 0.92, 0.72 * energy),
		maxf(1.0, size.x * 0.022), true)
	# Der kurze warme Kontaktblitz am unteren Rand vermittelt den Tastenhub, ohne
	# die bereits perfekte Originalgrafik zu verschieben.
	draw_line(
		Vector2(size.x * 0.40, size.y * 0.76),
		Vector2(size.x * 0.82, size.y * 0.65),
		Color(1.0, 0.62, 0.20, 0.80 * energy),
		maxf(1.0, size.x * 0.035), true)
