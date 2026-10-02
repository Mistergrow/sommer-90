extends RefCounted
## Whitelist der wirklich spielbaren, selbstbootenden Vollspiele.
##
## Die Diskette bleibt ueber ihre bestehende software_id die Wahrheitsquelle.
## ProgramLibrary/program_id gehoeren zu Werkbank-Apps und werden hier bewusst
## nicht verwendet, damit Kopierschutz- und Cracktro-Ablauf erhalten bleiben.

const StefanCatalog := preload("res://scripts/games/stefan_game_catalog.gd")
const StefanGame := preload("res://scripts/games/stefan_game.gd")

const GAME_SCRIPTS: Dictionary = {
	"space_lemming_trouble": preload("res://scripts/games/space_lemming_game.gd"),
	"turbo_kart_deluxe": preload("res://scripts/games/turbo_kart_game.gd"),
	"code_red_protocol": preload("res://scripts/games/code_red_game.gd"),
	"wunderwerk_94": preload("res://scripts/games/wunderwerk_game.gd"),
}


static func is_registered(software_id: String) -> bool:
	return GAME_SCRIPTS.has(software_id) or StefanCatalog.has(software_id)


static func registered_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in GAME_SCRIPTS.keys():
		ids.append(str(id))
	for id: String in StefanCatalog.ids():
		if id not in ids:
			ids.append(id)
	ids.sort()
	return ids


static func node_name_for(software_id: String) -> String:
	if not is_registered(software_id):
		return ""
	return "app_game_%s" % software_id


static func instantiate(software_id: String) -> Control:
	if not is_registered(software_id):
		return null
	if GAME_SCRIPTS.has(software_id):
		var game_script: GDScript = GAME_SCRIPTS[software_id]
		var instance: Object = game_script.new()
		return instance as Control
	var anthology: Control = StefanGame.new()
	anthology.call("configure_game", software_id)
	return anthology
