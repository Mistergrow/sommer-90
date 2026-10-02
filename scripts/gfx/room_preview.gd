extends Control
## Deko-Werkstatt (scenes/previews/RoomPreview.tscn):
## - Im EDITOR geöffnet: zeigt Raum, Anker-Kreuze und Zonen-Rahmen (nur ansehen).
## - Mit F6 GESTARTET ("Aktuelle Szene spielen"): Deko-Modus ist sofort aktiv —
##   alle renderbaren Raumgeräte werden unabhängig vom Besitz gezeigt,
##   ziehen = Familienanker, Strg+ziehen = aktive Variante feinpositionieren,
##   Mausrad = Größe, M/Shift+M = Gerätemodell,
##   Taste 1-3 = Zone wählen,
##   Rechtsklick-ziehen = Zonen-Rahmen neu aufziehen,
##   F8 = speichern nach data/room_anchors.json (und Modus an/aus).

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	await get_tree().process_frame  # Compositor erst aufbauen lassen
	_set_deco(true)


func _set_deco(enabled: bool, persist_changes: bool = true) -> void:
	for child in get_children():
		if child.has_method("set_edit_mode"):
			child.set_edit_mode(enabled, persist_changes)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		for child in get_children():
			if child.has_method("set_edit_mode"):
				child.set_edit_mode(not child.edit_mode)  # Aus = speichert JSON
