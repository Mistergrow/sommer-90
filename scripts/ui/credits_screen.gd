class_name GameCreditsScreen
extends "res://scripts/ui/scene_presentation_screen.gd"
## Kompatibler Einstieg in den Produktionsabspann.
##
## Hauptmenue und Jahrzehntfinale erzeugen weiterhin denselben oeffentlichen
## Typ. Seine Darstellung ist jedoch keine Fensterseite mehr, sondern exakt die
## vollflaechige PAL-Szenepraesentation des Startintros.

const CREDITS_DATA_PATH := "res://data/credits.json"

var embedded_in_title := false
# Bestehender Test-/Integrationsvertrag: oeffentliche Freigabedaten bleiben
# lesbar, obwohl der fruehere Fenster- und Navigationsrahmen entfallen ist.
var _credits: Dictionary = {}


func _init() -> void:
	name = "GameCreditsScreen"
	presentation_mode = MODE_CREDITS
	_credits = _load_release_credits()
	credits_data = _credits.duplicate(true)
	finished.connect(_finish_credits, CONNECT_ONE_SHOT)


func _finish_credits() -> void:
	queue_free()


func _load_release_credits() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_DATA_PATH))
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
