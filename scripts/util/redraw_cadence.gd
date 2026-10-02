class_name RedrawCadence
extends RefCounted
## Kleine, zustandsbehaftete Taktung fuer prozedurale Canvas-Animationen.
##
## Mehrere UI-Renderer hatten denselben Accumulator-/fmod-Code lokal. Diese
## Klasse haelt den Vertrag an einer Stelle: Zeit laeuft mit der echten Delta-
## Summe weiter, aber ein teurer Canvas-Redraw wird hoechstens einmal pro Frame
## und nur in der gewuenschten Frequenz angefordert.

var _remainder := 0.0


func reset() -> void:
	_remainder = 0.0


func advance(delta: float, frequency_hz: float) -> bool:
	if delta <= 0.0 or frequency_hz <= 0.0:
		return false
	var interval := 1.0 / frequency_hz
	_remainder += delta
	if _remainder + 0.000001 < interval:
		return false
	_remainder = fmod(_remainder, interval)
	return true


func remainder() -> float:
	return _remainder
