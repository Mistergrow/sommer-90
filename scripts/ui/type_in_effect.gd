extends RichTextEffect
## „type_in" — die zuletzt getippten Zeichen faden weich ein und sinken auf
## die Grundlinie, statt hart aufzupoppen. `progress` setzt das Dialogfenster
## pro Frame auf die aktuelle Typewriter-Grenze (sichtbare Zeichen).
## BEWUSST ohne class_name (Pfad-preload, Klassen-Cache-Race — Projektregel).

var bbcode := "type_in"
var progress := 0.0
var entrance := "settle"
var intensity := 1.0

const FADE_SPAN := 2.6   # über wie viele Zeichen der Einblend-Verlauf läuft
const RISE_PX := 3.0     # sanftes Absinken auf die Grundlinie


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var distance := progress - float(char_fx.range.x)
	if distance >= FADE_SPAN:
		return true
	var t := clampf(distance / FADE_SPAN, 0.0, 1.0)
	char_fx.color.a *= t
	var k := clampf(intensity, 0.0, 1.5)
	match entrance:
		"bounce":
			char_fx.offset.y += (1.0 - t) * 4.0 * k - sin(t * PI) * 2.0 * k
		"weight":
			char_fx.offset.y -= (1.0 - t) * 2.0 * k
			char_fx.offset.x -= (1.0 - t) * 1.2 * k
		"flow":
			char_fx.offset.x += (1.0 - t) * 4.0 * k
			char_fx.offset.y += sin(float(char_fx.range.x) * 1.7) * (1.0 - t) * k
		"terminal":
			char_fx.color.a *= 0.72 + t * 0.28
			char_fx.offset.x -= (1.0 - t) * 1.0
		"glitch":
			char_fx.offset.x += sin(float(char_fx.range.x) * 12.7) * (1.0 - t) * 2.0 * k
		"spark":
			char_fx.offset.y += (1.0 - t) * (2.0 + fmod(float(char_fx.range.x), 3.0)) * k
		"rhythm":
			char_fx.offset.y += (1.0 - t) * (2.0 if int(char_fx.range.x) % 2 == 0 else 4.0) * k
		"soft":
			char_fx.offset.y += (1.0 - t) * 1.5 * k
		"precise":
			char_fx.offset.y += (1.0 - t) * 1.0 * k
		"sly":
			char_fx.offset.x -= (1.0 - t) * 3.0 * k
		"warm":
			char_fx.offset.y += (1.0 - t) * 2.0 * k
		"resolve":
			char_fx.offset.x += (1.0 - t) * 2.0 * k
		_:
			char_fx.offset.y += (1.0 - t) * RISE_PX * k
	return true
