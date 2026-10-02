class_name CollectionRoomLayout
extends RefCounted
## Single Source fuer die Sammlerwand/Gegenansicht. Runtime und RoomEditor lesen
## dieselbe normalisierte Geometrie; dadurch kann die Editor-Szene keine nur dort
## sichtbare Sonderposition erzeugen.

const PATH := "res://data/collection_room_layout.json"
const DEFAULT_BACKGROUND := "res://assets/backgrounds/layers/ROOM_REVERSE_MASTER_1992_V01.png"
const DEFAULT_OBJECTS := {
	"cabinet": {
		"asset": "res://assets/backgrounds/layers/ROOM_GAME_DISPLAY_CABINET_MASTER_V01.png",
		"rect": {"x": 0.590, "y": 0.055, "w": 0.255, "h": 0.880},
	},
	"monitor_commodore_1084s": {
		"asset": "res://assets/backgrounds/layers/MONITOR_COMMODORE_1084S_REAR_V01.png",
		"rect": {"x": 0.250, "y": 0.790, "w": 0.280, "h": 0.330},
	},
	"monitor_commodore_1901": {
		"asset": "res://assets/backgrounds/layers/MONITOR_COMMODORE_1901_REAR_V01.png",
		"rect": {"x": 0.250, "y": 0.790, "w": 0.280, "h": 0.330},
	},
}

static var _data: Dictionary = {}


static func reload() -> void:
	_data = {}
	_ensure()


static func data() -> Dictionary:
	_ensure()
	return _data


static func background() -> String:
	_ensure()
	return str(_data.get("background", DEFAULT_BACKGROUND))


static func object_data(id: String) -> Dictionary:
	_ensure()
	var objects: Dictionary = _data.get("objects", {})
	return objects.get(id, DEFAULT_OBJECTS.get(id, {}))


static func rect(id: String) -> Rect2:
	var raw: Dictionary = object_data(id).get("rect", {})
	return Rect2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)),
		float(raw.get("w", 0.0)), float(raw.get("h", 0.0)))


static func asset(id: String) -> String:
	return str(object_data(id).get("asset", ""))


static func save(document: Dictionary) -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "  ", false))
	_data = document.duplicate(true)
	return true


static func _ensure() -> void:
	if not _data.is_empty():
		return
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = (parsed as Dictionary).duplicate(true)
	if _data.is_empty():
		_data = {"schema": 1, "background": DEFAULT_BACKGROUND,
			"objects": DEFAULT_OBJECTS.duplicate(true)}
