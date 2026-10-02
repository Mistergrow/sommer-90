class_name SommerGameModuleCatalog
extends RefCounted
## Kanonischer Vertrag zwischen Quests, Sommer Game und Sommer BASIC.

const PATH := "res://data/sommer_game/modules.json"
const HARDWARE_TIERS := {
	"amiga_500_ocs_512k": 5,
	"amiga_500_ocs_1mb": 10,
	"amiga_500_ecs_1mb": 20,
	"amiga_1200_aga_2mb": 30,
	"amiga_1200_aga_hdd_4mb": 40,
}

static var _loaded := false
static var _modules: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _by_symbol: Dictionary = {}


static func all() -> Array[Dictionary]:
	_load()
	return _modules.duplicate(true)


static func module(module_id: String) -> Dictionary:
	_load()
	return (_by_id.get(module_id, {}) as Dictionary).duplicate(true)


static func module_for_symbol(symbol: String) -> Dictionary:
	_load()
	return (_by_symbol.get(symbol.to_upper(), {}) as Dictionary).duplicate(true)


static func commands() -> PackedStringArray:
	_load()
	var out := PackedStringArray()
	for entry: Dictionary in _modules:
		out.append_array(entry.get("commands", []))
	return out


static func functions() -> PackedStringArray:
	_load()
	var out := PackedStringArray()
	for entry: Dictionary in _modules:
		out.append_array(entry.get("functions", []))
	return out


static func available(module_id: String, year: int, hardware_profile: String,
		unlocked_modules: Array) -> Dictionary:
	var readiness := integration_readiness(module_id, year, hardware_profile,
		unlocked_modules)
	if not bool(readiness.get("available", false)):
		return readiness
	if not unlocked_modules.has(module_id):
		readiness["available"] = false
		readiness["reason"] = "module_not_unlocked"
	return readiness


## Prueft, ob ein gemeinsamer Beitrag jetzt eingebaut werden darf. Anders als
## available() verlangt diese Abfrage nicht, dass das Modul bereits eingebaut
## ist; sie ist damit der verbindliche Vertrag fuer die Jahresquest und die UI.
static func integration_readiness(module_id: String, year: int,
		hardware_profile: String, unlocked_modules: Array) -> Dictionary:
	var entry := module(module_id)
	if entry.is_empty():
		return {"available": false, "reason": "unknown_module", "module": {}}
	if year < int(entry.get("year", 1990)):
		return {"available": false, "reason": "not_released_yet", "module": entry,
			"required_profile": str(entry.get("hardware_profile", "")),
			"actual_profile": hardware_profile}
	var required_tier := int(HARDWARE_TIERS.get(str(entry.get("hardware_profile", "")), 10))
	var actual_tier := int(HARDWARE_TIERS.get(hardware_profile, 10))
	if actual_tier < required_tier:
		return {"available": false, "reason": "hardware_too_weak", "module": entry,
			"required_profile": str(entry.get("hardware_profile", "")),
			"actual_profile": hardware_profile}
	for dependency: Variant in entry.get("requires", []):
		if not unlocked_modules.has(str(dependency)):
			return {"available": false, "reason": "dependency_missing", "module": entry,
				"dependency": str(dependency),
				"required_profile": str(entry.get("hardware_profile", "")),
				"actual_profile": hardware_profile}
	return {"available": true, "reason": "", "module": entry,
		"required_profile": str(entry.get("hardware_profile", "")),
		"actual_profile": hardware_profile}


static func signature_for(symbol: String) -> String:
	match symbol.to_upper():
		"GAMESTART", "GAMESTOP", "DRAWWORLD", "UPDATEPLAYERS", "UPDATEPHYSICS", "AISTEP", "SIMULATE", "NETWORKSYNC", "PROFILEFRAME": return symbol.to_upper()
		"LOADMAP": return "LOADMAP Dateiname"
		"LOADSPRITES": return "LOADSPRITES Dateiname"
		"ADDPLAYER": return "ADDPLAYER X, Y [, Team]"
		"SAVEGAME", "LOADGAME": return "%s Slot" % symbol.to_upper()
		"ANIMATE": return "ANIMATE Sprite, Frame"
		"MIXSOUND": return "MIXSOUND Sample, Prioritaet [, Kanal]"
		"ADVSTATE": return "ADVSTATE Name, Wert"
		"DIALOGUE": return "DIALOGUE Knoten"
		"DEBUGBREAK": return "DEBUGBREAK [Name]"
		"DEBUGVALUE": return "DEBUGVALUE Name, Wert"
		"SETTILE": return "SETTILE X, Y, Tile"
		"MAPLAYER": return "MAPLAYER Layer"
		"DESTROYTERRAIN": return "DESTROYTERRAIN X, Y, Radius"
		"FIREPROJECTILE": return "FIREPROJECTILE X, Y, VX, VY [, Staerke]"
		"EMITPARTICLES": return "EMITPARTICLES X, Y, Anzahl"
		"CAMERA": return "CAMERA X, Y"
		"GUIWINDOW": return "GUIWINDOW X, Y, Breite, Hoehe, Titel"
		"GUITEXT": return "GUITEXT X, Y, Text"
		"ZONE": return "ZONE X, Y, Typ"
		"POWERLINK", "TRAFFICROUTE": return "%s X1, Y1, X2, Y2" % symbol.to_upper()
		"COLORPIPE": return "COLORPIPE Profil"
		"TARGETVIDEO": return "TARGETVIDEO Ziel"
		"EXPORTBUILD": return "EXPORTBUILD Ziel, Name"
	return "%s(...)" % symbol.to_upper()


static func argument_range(symbol: String) -> Vector2i:
	match symbol.to_upper():
		"GAMESTART", "GAMESTOP", "DRAWWORLD", "UPDATEPLAYERS", "UPDATEPHYSICS", "AISTEP", "SIMULATE", "NETWORKSYNC", "PROFILEFRAME": return Vector2i(0, 0)
		"LOADMAP", "LOADSPRITES", "LOADGAME", "SAVEGAME", "DIALOGUE", "DEBUGBREAK", "MAPLAYER", "COLORPIPE", "TARGETVIDEO": return Vector2i(1, 1)
		"ADDPLAYER", "MIXSOUND": return Vector2i(2, 3)
		"ANIMATE", "ADVSTATE", "DEBUGVALUE": return Vector2i(2, 2)
		"GUITEXT": return Vector2i(3, 3)
		"SETTILE", "DESTROYTERRAIN", "EMITPARTICLES": return Vector2i(3, 3)
		"FIREPROJECTILE": return Vector2i(4, 5)
		"CAMERA": return Vector2i(2, 2)
		"GUIWINDOW": return Vector2i(5, 5)
		"ZONE": return Vector2i(3, 3)
		"POWERLINK", "TRAFFICROUTE": return Vector2i(4, 4)
		"EXPORTBUILD": return Vector2i(2, 2)
	return Vector2i(0, 99)


static func validate() -> PackedStringArray:
	_load()
	var errors := PackedStringArray()
	var symbols: Dictionary = {}
	for entry: Dictionary in _modules:
		var module_id := str(entry.get("id", ""))
		if module_id.is_empty(): errors.append("Modul ohne ID")
		for dependency: Variant in entry.get("requires", []):
			if not _by_id.has(str(dependency)):
				errors.append("%s: unbekannte Abhaengigkeit %s" % [module_id, dependency])
		for symbol: Variant in entry.get("commands", []) + entry.get("functions", []):
			var key := str(symbol).to_upper()
			if symbols.has(key): errors.append("Doppeltes Engine-Symbol: %s" % key)
			symbols[key] = module_id
	return errors


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_error("Sommer-Game-Modulkatalog fehlt oder ist ungueltig.")
		return
	for raw: Variant in (parsed as Dictionary).get("modules", []):
		if not raw is Dictionary:
			continue
		var entry := (raw as Dictionary).duplicate(true)
		_modules.append(entry)
		_by_id[str(entry.get("id", ""))] = entry
		for symbol: Variant in entry.get("commands", []) + entry.get("functions", []):
			_by_symbol[str(symbol).to_upper()] = entry
