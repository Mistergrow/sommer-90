extends Control
## Kiosk-Magazin-Editor als eigene Szene: lädt den Kiosk (Hintergrund) und legt
## die Magazin-Ebene im EDIT-Modus darüber. Mit „+ Magazin platzieren" stellst du
## aufrecht stehende Hefte in die Regale, ziehst/skalierst sie und speicherst mit
## F8 nach data/kiosk_magazines.json. Das Cover ist das der aktuellen Ausgabe
## (Monat) — je nach Datum wird automatisch ein anderes geladen.
##
## Öffnen: scenes/KioskMagEditor.tscn im Godot-Editor mit F6 ausführen.

@export var year: int = 1990
@export var month: int = 7   # Juli → Ausgabe 06/07 liegt „neu" im Kiosk

var _location: LocationBase


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	TimeManager.year = year
	TimeManager.month = month
	var def: Dictionary = GameManager.LOCATION_DEFS.get("kiosk", {})
	if def.is_empty() or not def.has("script"):
		push_error("KioskMagEditor: Ort 'kiosk' unbekannt.")
		return
	_location = def["script"].new()
	add_child(_location)
	await get_tree().process_frame
	await get_tree().process_frame
	# Die vom Kiosk selbst hinzugefügte (nur-Anzeige-)Ebene entfernen, damit im
	# Editor keine Doppel-/Geisterdarstellung entsteht.
	for n in _location.find_children("", "KioskMagazineLayer", true, false):
		n.queue_free()
	var editor := KioskMagazineLayer.new()
	editor.location = _location
	editor.edit_mode = true
	add_child(editor)
