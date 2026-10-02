class_name CableGiz
extends Control
## Dünne Zeichenebene über dem Backdrop-Compositor des Kabel-Editors: liegt als
## letztes Kind über dem Raum und ruft zum Zeichnen in den CableEditor zurück
## (der die ganze Logik/den Zustand hält). Eingaben behandelt der CableEditor.


func _draw() -> void:
	var ed := get_parent()
	if ed != null and ed.has_method("paint_gizmos"):
		ed.paint_gizmos(self)
