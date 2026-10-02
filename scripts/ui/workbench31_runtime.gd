class_name Workbench31Runtime
extends RefCounted
## Funktionskern der Workbench-3.1-Ergaenzungen. Bestehende vollwertige Apps
## (Shell, Calculator, Clock, Preferences, DiskCopy und Format) bleiben deren
## einzige Implementierung; hier liegen nur die zuvor fehlenden 3.1-Werkzeuge.

const DEFINITIONS := {
	"multiview": {
		"title": "MultiView 40.8",
		"summary": "Datatypes-Viewer für Text, Bild, AmigaGuide, Klang und Animation.",
		"actions": [
			["cycle_datatype", "DATENTYP", false],
			["open_document", "ÖFFNEN", false],
			["play_media", "ABSPIELEN", false]]},
	"amigaguide": {
		"title": "AmigaGuide 40.4",
		"summary": "Hypertext-Navigation mit Inhalt, Zurück, Weiter und Index.",
		"actions": [
			["guide_next", "WEITER", false],
			["guide_back", "ZURÜCK", false],
			["guide_index", "INHALT", false]]},
	"crossdos": {
		"title": "CrossDOS 40.1",
		"summary": "PC0:/PC1: als PC-formatierte Disketten lesen und schreiben.",
		"actions": [
			["mount_pc0", "PC0: MOUNT", false],
			["read_pc", "LESEN", false],
			["write_pc", "SCHREIBEN", true]]},
	"ed": {
		"title": "Ed 40.1",
		"summary": "Zeilenorientierter Texteditor mit Undo und sicherem Speichern.",
		"actions": [
			["edit_line", "ZEILE ÄNDERN", false],
			["undo_edit", "UNDO", false],
			["save_text", "SPEICHERN", false]]},
	"exchange": {
		"title": "Exchange 40.2",
		"summary": "Commodities ein-/ausschalten und Prioritäten kontrollieren.",
		"actions": [
			["next_commodity", "NÄCHSTE", false],
			["toggle_commodity", "AN/AUS", false],
			["commodity_priority", "PRIORITÄT", false]]},
	"wbstartup": {
		"title": "WBStartup",
		"summary": "Startprogramme mit WAIT und STARTPRI verwalten.",
		"actions": [
			["next_startup", "NÄCHSTE", false],
			["toggle_startup", "AN/AUS", false],
			["save_startup", "SICHERN", false]]},
	"diskinfo": {
		"title": "Disk-Information",
		"summary": "Geometrie, Dateisystem, Belegung und Schreibschutz auslesen.",
		"actions": [
			["inspect_df0", "DF0: INFO", false],
			["inspect_dh0", "DH0: INFO", false],
			["inspect_ram", "RAM: INFO", false],
			["verify_volume", "PRÜFSUMME", false]]},
	"installer": {
		"title": "Installer 43.3",
		"summary": "Paket prüfen, Ziel wählen und erst nach Bestätigung installieren.",
		"actions": [
			["inspect_package", "PAKET PRÜFEN", false],
			["choose_target", "ZIEL WÄHLEN", false],
			["install_package", "INSTALLIEREN", true]]},
	"prepcard": {
		"title": "PrepCard 40.1",
		"summary": "PCMCIA-Karte identifizieren und sichere Geometrie vorbereiten.",
		"actions": [
			["inspect_card", "KARTE PRÜFEN", false],
			["prepare_card", "VORBEREITEN", true]]},
	"keyshow": {
		"title": "KeyShow 40.1",
		"summary": "Aktuelle Tastaturmatrix anzeigen und Tasten testen.",
		"actions": [
			["cycle_keymap", "KEYMAP", false],
			["test_key", "TASTE TESTEN", false]]},
}

const DATATYPES := ["TEXT", "ILBM-BILD", "AMIGAGUIDE", "8SVX-KLANG", "ANIM"]
const COMMODITIES := ["AutoPoint", "Blanker", "ClickToFront", "CrossDOS"]
const STARTUP_ITEMS := ["Clock", "Exchange", "ToolManager"]

var tool_id := ""
var definition: Dictionary = {}
var state: Dictionary = {}
var history: Array[String] = []


func setup(id: String) -> void:
	tool_id = id
	definition = definition_for(id)
	state = {
		"datatype": 0,
		"document_open": false,
		"playing": false,
		"guide_node": 0,
		"guide_history": [],
		"pc0_mounted": false,
		"dirty": false,
		"revision": 0,
		"selection": 0,
		"enabled": {},
		"priority": 0,
		"package_ok": false,
		"target_selected": false,
		"saved": false,
	}
	history = ["%s bereit." % str(definition.get("title", id))]


static func definition_for(id: String) -> Dictionary:
	return (DEFINITIONS.get(id, {}) as Dictionary).duplicate(true)


static func tool_ids() -> Array[String]:
	var result: Array[String] = []
	for id in DEFINITIONS:
		result.append(str(id))
	result.sort()
	return result


func actions() -> Array:
	return (definition.get("actions", []) as Array).duplicate(true)


func action(action_id: String, confirm := false) -> Dictionary:
	var spec := _find_action(action_id)
	if spec.is_empty():
		return _result(false, "unknown_action", "Unbekannte Werkzeugfunktion.")
	if bool(spec[2]) and not confirm:
		return _result(false, "confirmation_required",
			"»%s« verändert Daten und wartet auf Bestätigung." % str(spec[1]), true)
	var message := ""
	match action_id:
		"cycle_datatype":
			state["datatype"] = (int(state["datatype"]) + 1) % DATATYPES.size()
			state["document_open"] = false
			state["playing"] = false
			message = "Datatype gewählt: %s." % DATATYPES[int(state["datatype"])]
		"open_document":
			state["document_open"] = true
			message = "%s über datatypes.library geöffnet." % DATATYPES[int(state["datatype"])]
		"play_media":
			if not bool(state["document_open"]):
				return _result(false, "nothing_open", "Zuerst ein Dokument öffnen.")
			var kind: String = str(DATATYPES[int(state["datatype"])])
			if kind not in ["8SVX-KLANG", "ANIM"]:
				return _result(false, "not_playable", "%s ist statisch; Blättern bleibt möglich." % kind)
			state["playing"] = not bool(state["playing"])
			message = "%s %s." % [kind, "läuft" if bool(state["playing"]) else "pausiert"]
		"guide_next":
			var stack: Array = state["guide_history"]
			stack.append(int(state["guide_node"]))
			state["guide_history"] = stack
			state["guide_node"] = mini(5, int(state["guide_node"]) + 1)
			message = "Guide-Knoten %d: Nächste Seite." % int(state["guide_node"])
		"guide_back":
			var stack: Array = state["guide_history"]
			if stack.is_empty():
				return _result(false, "at_start", "Kein vorheriger Guide-Knoten.")
			state["guide_node"] = int(stack.pop_back())
			state["guide_history"] = stack
			message = "Zurück zu Guide-Knoten %d." % int(state["guide_node"])
		"guide_index":
			state["guide_node"] = 0
			state["guide_history"] = []
			message = "Guide-Inhalt geöffnet."
		"mount_pc0":
			state["pc0_mounted"] = not bool(state["pc0_mounted"])
			message = "PC0: %s." % ("bereit (FAT12)" if bool(state["pc0_mounted"]) else "ausgehängt")
		"read_pc":
			if not bool(state["pc0_mounted"]):
				return _result(false, "not_mounted", "Zuerst PC0: mounten.")
			message = "PC0: 14 Dateien gelesen; Original unverändert."
		"write_pc":
			if not bool(state["pc0_mounted"]):
				return _result(false, "not_mounted", "Zuerst PC0: mounten.")
			state["revision"] = int(state["revision"]) + 1
			message = "PC0: Datei geschrieben und FAT-Kopie verifiziert."
		"edit_line":
			state["dirty"] = true
			state["revision"] = int(state["revision"]) + 1
			message = "Zeile %d geändert; Puffer ist ungesichert." % (int(state["revision"]) + 1)
		"undo_edit":
			if not bool(state["dirty"]):
				return _result(false, "nothing_to_undo", "Keine ungesicherte Änderung.")
			state["revision"] = maxi(0, int(state["revision"]) - 1)
			state["dirty"] = int(state["revision"]) > 0
			message = "Letzte Änderung zurückgenommen."
		"save_text":
			if not bool(state["dirty"]):
				return _result(false, "nothing_changed", "Text ist bereits unverändert.")
			if not _persist_to_hdd("Documents/Ed-Text", 24, "document"):
				return _result(false, "disk_full", Loc.t(
					"ui.workbench31_runtime.hdd_text_save_failed",
					"DH0: Text konnte nicht gespeichert werden."))
			state["dirty"] = false
			state["saved"] = true
			message = "Text atomar in eine neue Datei geschrieben" + _hdd_suffix() + "."
		"next_commodity":
			state["selection"] = (int(state["selection"]) + 1) % COMMODITIES.size()
			message = "%s ausgewählt." % COMMODITIES[int(state["selection"])]
		"toggle_commodity":
			var name: String = str(COMMODITIES[int(state["selection"])])
			var enabled: Dictionary = state["enabled"]
			enabled[name] = not bool(enabled.get(name, false))
			state["enabled"] = enabled
			message = "%s %s." % [name, "aktiv" if bool(enabled[name]) else "inaktiv"]
		"commodity_priority":
			state["priority"] = wrapi(int(state["priority"]) + 1, -2, 3)
			message = "Commodity-Priorität: %d." % int(state["priority"])
		"next_startup":
			state["selection"] = (int(state["selection"]) + 1) % STARTUP_ITEMS.size()
			message = "%s ausgewählt." % STARTUP_ITEMS[int(state["selection"])]
		"toggle_startup":
			var name: String = str(STARTUP_ITEMS[int(state["selection"])])
			var enabled: Dictionary = state["enabled"]
			enabled[name] = not bool(enabled.get(name, false))
			state["enabled"] = enabled
			state["dirty"] = true
			message = "%s %s WBStartup." % [name, "in" if bool(enabled[name]) else "aus"]
		"save_startup":
			if not _persist_to_hdd("S/WBStartup.prefs", 8, "preferences"):
				return _result(false, "disk_full", Loc.t(
					"ui.workbench31_runtime.hdd_wbstartup_save_failed",
					"DH0: WBStartup konnte nicht gesichert werden."))
			state["dirty"] = false
			state["saved"] = true
			message = "WBStartup-Konfiguration gesichert" + _hdd_suffix() + "."
		"inspect_df0":
			message = "DF0: 80 Zylinder · 2 Seiten · 880 KB · OFS/FFS erkannt."
		"inspect_dh0":
			var info := _hdd_info()
			if not bool(info.get("available", false)):
				message = Loc.t("ui.workbench31_runtime.hdd_missing",
					"DH0: kein Volume vorhanden; DF0: bleibt Systemmedium.")
			else:
				message = Loc.t("ui.workbench31_runtime.hdd_info",
					"DH0: %d KB belegt · %d KB frei · %s.") % [
					int(info.get("used_kb", 0)), int(info.get("free_kb", 0)),
					str(info.get("controller", "Controller"))]
		"inspect_ram":
			message = "RAM: temporär · beim Neustart gelöscht · beschreibbar."
		"verify_volume":
			message = "Dateisystem gelesen: Bitmap und Rootblock sind konsistent."
		"inspect_package":
			state["package_ok"] = true
			message = "Installationsskript geprüft: 0 unbekannte Befehle."
		"choose_target":
			state["target_selected"] = true
			var target := _hdd_info()
			message = Loc.t("ui.workbench31_runtime.hdd_target",
				"Ziel SYS:Utilities gewählt; %d KB frei.") % int(
				target.get("free_kb", 640))
		"install_package":
			if not bool(state["package_ok"]) or not bool(state["target_selected"]):
				return _result(false, "prerequisite", "Zuerst Paket prüfen und Ziel wählen.")
			if not _persist_to_hdd("Utilities/Installer-Paket", 420, "program"):
				return _result(false, "disk_full", Loc.t(
					"ui.workbench31_runtime.hdd_package_no_space",
					"DH0: Paket passt nicht auf das Zielvolume."))
			state["saved"] = true
			message = "Paket installiert" + _hdd_suffix() + "; Undo-Protokoll wurde angelegt."
		"inspect_card":
			state["package_ok"] = true
			message = "PCMCIA SRAM · 2 MB · Schreibschutz aus."
		"prepare_card":
			if not bool(state["package_ok"]):
				return _result(false, "prerequisite", "Zuerst Karte prüfen.")
			state["saved"] = true
			message = "Karte vorbereitet; Geometrie erneut gelesen."
		"cycle_keymap":
			state["selection"] = (int(state["selection"]) + 1) % 3
			message = "Keymap: %s." % ["Deutsch", "USA", "Britisch"][int(state["selection"])]
		"test_key":
			state["revision"] = int(state["revision"]) + 1
			message = "Taste %s liefert RawKey $%02X." % [
				["A", "Y", "Z"][int(state["selection"])],
				0x20 + int(state["selection"])]
	state["last_action"] = action_id
	history.push_front(message)
	if history.size() > 5:
		history.resize(5)
	return _result(true, "ok", message)


func _hdd_info() -> Dictionary:
	var stats := _autoload("PlayerStats")
	if stats != null and stats.has_method("hdd_info"):
		return (stats.call("hdd_info") as Dictionary).duplicate(true)
	return {"available": false, "free_kb": 640}


## Ohne Festplatte bleiben die historischen Disketten-/RAM:-Arbeitswege
## funktionsfähig. Ist DH0: vorhanden, muss jeder persistente Schreibvorgang
## dagegen dort Platz belegen und darf bei vollem Volume nicht Erfolg melden.
func _persist_to_hdd(path: String, size_kb: int, kind: String) -> bool:
	var stats := _autoload("PlayerStats")
	if stats == null or not stats.has_method("hdd_info"):
		return true
	var info := _hdd_info()
	if not bool(info.get("available", false)):
		return true
	if not stats.has_method("hdd_write_file"):
		return false
	return bool(stats.call("hdd_write_file", path, size_kb,
		{"kind": kind, "tool_id": tool_id}))


func _hdd_suffix() -> String:
	return Loc.t("ui.workbench31_runtime.on_dh0", " auf DH0:") \
		if bool(_hdd_info().get("available", false)) else ""


static func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/" + node_name)
	return null


func state_snapshot() -> Dictionary:
	return state.duplicate(true)


func _find_action(id: String) -> Array:
	for row: Array in actions():
		if str(row[0]) == id:
			return row
	return []


func _result(ok: bool, code: String, message: String,
		confirmation_required := false) -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"message": message,
		"confirmation_required": confirmation_required,
		"tool_id": tool_id,
		"state": state_snapshot(),
	}
