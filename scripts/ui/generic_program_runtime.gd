class_name GenericProgramRuntime
extends RefCounted
## Zustandskern fuer die Programme, die keine eigene Vollbild-App benoetigen.
##
## WICHTIG: Diese Klasse ist keine Attrappen-Sammlung. Jede Program-ID besitzt
## konkrete, testbare Faehigkeiten. Aktionen liefern ein stabiles Ergebnisobjekt
## und aendern erst danach den lokalen Programmlauf-Zustand. Potenziell
## destruktive Aktionen verlangen immer ein ausdrueckliches `confirm`.

const DEFINITIONS := {
	"memory_monitor": {"noun": "Speicherpools", "actions": [
		["sample_memory", "NEU MESSEN", "inspect"],
		["compact_memory", "SPEICHER ORDNEN", "transform"]]},
	"icon_editor": {"noun": "Workbench-Icon", "actions": [
		["paint_icon_pixel", "PIXEL SETZEN", "edit"],
		["save_icon", "ICON SICHERN", "save"]]},
	"disk_formatter": {"noun": "Leerdiskette", "actions": [
		["inspect_disk", "DISK PRÜFEN", "inspect"],
		["format_disk", "FORMATIEREN", "destructive"]]},
	"file_manager_opus_homage": {"noun": "Dateiauswahl", "actions": [
		["select_next_file", "NÄCHSTE DATEI", "select"],
		["copy_selected_file", "KOPIEREN", "copy"]]},
	"diskmaster_homage": {"noun": "Verzeichnis", "actions": [
		["sort_directory", "SORTIEREN", "transform"],
		["copy_selected_file", "KOPIEREN", "copy"]]},
	"filemaster_homage": {"noun": "Datei", "actions": [
		["rename_selected_file", "UMBENENNEN", "edit"],
		["delete_selected_file", "LÖSCHEN", "destructive"]]},
	"lha_unpacker": {"noun": "LHA-Archiv", "actions": [
		["test_archive", "ARCHIV TESTEN", "inspect"],
		["unpack_archive", "ENTPACKEN", "extract"]]},
	"lzx_unpacker": {"noun": "LZX-Archiv", "actions": [
		["test_archive", "ARCHIV TESTEN", "inspect"],
		["pack_archive", "NEU PACKEN", "archive"]]},
	"dms_unpacker": {"noun": "DMS-Abbild", "actions": [
		["test_disk_image", "IMAGE TESTEN", "inspect"],
		["write_disk_image", "AUF DISK SCHREIBEN", "destructive"]]},
	"powerpacker_homage": {"noun": "Programmdatei", "actions": [
		["analyze_compression", "DATEI ANALYSIEREN", "inspect"],
		["pack_executable", "PROGRAMM PACKEN", "archive"]]},
	"disksalv_homage": {"noun": "beschädigte Disk", "actions": [
		["scan_bad_blocks", "BLÖCKE SCANNEN", "inspect"],
		["recover_files", "DATEIEN RETTEN", "recover"]]},
	"quarterback_homage": {"noun": "Sicherungssatz", "actions": [
		["verify_backup", "BACKUP PRÜFEN", "inspect"],
		["create_backup", "BACKUP ERSTELLEN", "archive"]]},
	"disk_repair": {"noun": "Disk-Geometrie", "actions": [
		["scan_bad_blocks", "SEKTOREN PRÜFEN", "inspect"],
		["repair_bad_blocks", "SEKTOREN REPARIEREN", "destructive"]]},
	"sample_editor": {"noun": "8-Bit-Sample", "actions": [
		["trim_sample", "SAMPLE TRIMMEN", "edit"],
		["normalize_sample", "NORMALISIEREN", "transform"]]},
	"brilliance_homage": {"noun": "24-Bit-Bild", "actions": [
		["paint_canvas", "PINSELSTRICH", "edit"],
		["quantize_image", "AGA-VORSCHAU", "transform"]]},
	"label_designer": {"noun": "Farbetikett", "actions": [
		["design_label", "LAYOUT ÄNDERN", "edit"],
		["print_label", "ETIKETT DRUCKEN", "print"]]},
	"cover_designer": {"noun": "Inlay/Cover", "actions": [
		["design_cover", "COVER SETZEN", "edit"],
		["print_cover", "COVER DRUCKEN", "print"]]},
	"finalwriter_homage": {"noun": "Dokument", "actions": [
		["edit_document", "ABSATZ EINFÜGEN", "edit"],
		["print_document", "DOKUMENT DRUCKEN", "print"]]},
	"devpac_homage": {"noun": "68000-Quelle", "actions": [
		["assemble_source", "ASSEMBLIEREN", "compile"],
		["run_binary", "TESTLAUF", "execute"]]},
	"bbs_mail": {"noun": "Offline-Postfach", "actions": [
		["fetch_mail_headers", "POST HOLEN", "network"],
		["mark_mail_read", "NACHRICHT LESEN", "select"]]},
	"download_manager": {"noun": "Transferliste", "actions": [
		["queue_download", "TRANSFER MERKEN", "network"],
		["resume_download", "DOWNLOAD FORTSETZEN", "network"]]},
	"scout_homage": {"noun": "Exec-Taskliste", "actions": [
		["scan_tasks", "TASKS SCANNEN", "inspect"],
		["inspect_ports", "PORTS PRÜFEN", "inspect"]]},
	"snoop_monitor": {"noun": "DOS-Aufrufe", "actions": [
		["start_trace", "TRACE STARTEN", "monitor"],
		["capture_dos_call", "AUFRUF AUFZEICHNEN", "monitor"]]},
	"mcp_homage": {"noun": "System-Patches", "actions": [
		["toggle_patch", "PATCH UMSCHALTEN", "toggle"],
		["benchmark_patch", "PATCH MESSEN", "inspect"]]},
	"magicwb_homage": {"noun": "8-Farben-Icons", "actions": [
		["preview_theme", "THEMA ANSEHEN", "inspect"],
		["toggle_theme", "THEMA UMSCHALTEN", "toggle"]]},
	"nfo_viewer": {"noun": "ASCII-Dokument", "actions": [
		["next_nfo_page", "NÄCHSTE SEITE", "navigate"],
		["toggle_ansi_colors", "ANSI-FARBEN", "toggle"]]},
	"scroller_viewer": {"noun": "Gruß-Scroller", "actions": [
		["change_scroll_speed", "TEMPO ÄNDERN", "transform"],
		["pause_scroller", "PAUSE/WEITER", "toggle"]]},
	"makecd_homage": {"noun": "CD-Projekt", "actions": [
		["build_iso", "IMAGE ERSTELLEN", "archive"],
		["burn_cd", "CD BRENNEN", "destructive"]]},
	"cdfs_homage": {"noun": "CD0:", "actions": [
		["mount_cd", "CD0: MOUNTEN", "toggle"],
		["read_cd_directory", "INHALT LESEN", "inspect"]]},
}

var program_id := ""
var capability: Dictionary = {}
var state: Dictionary = {}
var history: Array[String] = []


func setup(id: String) -> void:
	program_id = id
	capability = capability_for(id)
	state = {
		"revision": 0,
		"selection": 0,
		"processed": 0,
		"saved": false,
		"compiled": false,
		"mounted": false,
		"enabled": false,
		"paused": false,
		"progress": 0,
		"messages": 3,
	}
	history = ["%s bereit." % str(capability.get("noun", "Programm"))]


static func capability_for(id: String) -> Dictionary:
	return (DEFINITIONS.get(id, {}) as Dictionary).duplicate(true)


static func supported_ids() -> Array[String]:
	var result: Array[String] = []
	for id in DEFINITIONS:
		result.append(str(id))
	result.sort()
	return result


func available_actions() -> Array:
	return (capability.get("actions", []) as Array).duplicate(true)


func action(action_id: String, payload := {}) -> Dictionary:
	var spec := _action_spec(action_id)
	if spec.is_empty():
		return _result(false, "unknown_action", "Diese Funktion gehört nicht zu %s." % program_id)
	var kind := str(spec[2])
	var requirement := _requirement_failure(kind)
	if not requirement.is_empty():
		return requirement
	if kind == "destructive" and not bool(payload.get("confirm", false)):
		return _result(false, "confirmation_required",
			"Sicherheitsabfrage: »%s« erst nach Bestätigung ausführen." % str(spec[1]),
			false, true)
	var artifact_size := _artifact_size_kb(kind)
	if artifact_size > 0 and not _hdd_has_space(artifact_size):
		return _result(false, "disk_full",
			Loc.t("ui.generic_program_runtime.hdd_no_space",
				"DH0: Nicht genug freier Platz für diese Datei."))

	var changed := true
	var message := ""
	match action_id:
		"sample_memory":
			var ram := _ram_snapshot()
			state["memory"] = ram
			message = "%d KB gesamt · %d KB Chip · %d KB Fast." % [
				int(ram["total_kb"]), int(ram["chip_kb"]), int(ram["fast_kb"])]
		"select_next_file", "mark_mail_read":
			state["selection"] = (int(state["selection"]) + 1) % 8
			message = "Auswahl %d ist jetzt aktiv." % (int(state["selection"]) + 1)
		"start_trace":
			state["enabled"] = true
			message = "DOS-Trace läuft; nur Dateizugriffe werden protokolliert."
		"capture_dos_call":
			if not bool(state["enabled"]):
				return _result(false, "not_running", "Zuerst TRACE STARTEN.")
			state["processed"] = int(state["processed"]) + 1
			message = "Open(\"SYS:Libs/dos.library\") aufgezeichnet."
		"run_binary", "profile_binary", "run_listing":
			if not bool(state["compiled"]) and action_id != "run_listing":
				return _result(false, "not_compiled", "Zuerst fehlerfrei kompilieren.")
			state["processed"] = int(state["processed"]) + 1
			message = "Testlauf beendet: Rückgabewert 0."
		"compile_basic", "assemble_source", "check_listing":
			state["compiled"] = true
			state["revision"] = int(state["revision"]) + 1
			message = "Build %d: 0 Fehler, 0 Warnungen." % int(state["revision"])
		"mount_cd":
			state["mounted"] = not bool(state["mounted"])
			message = "CD0: %s." % ("eingebunden" if bool(state["mounted"]) else "ausgehängt")
		"read_cd_directory":
			if not bool(state["mounted"]):
				return _result(false, "not_mounted", "Zuerst CD0: MOUNTEN.")
			state["processed"] = int(state["processed"]) + 12
			message = "12 Einträge von CD0: gelesen."
		"pause_scroller":
			state["paused"] = not bool(state["paused"])
			message = "Scroller %s." % ("pausiert" if bool(state["paused"]) else "läuft weiter")
		"toggle_patch", "toggle_theme", "toggle_ansi_colors":
			state["enabled"] = not bool(state["enabled"])
			message = "%s." % ("Aktiviert" if bool(state["enabled"]) else "Deaktiviert")
		"save_icon":
			if int(state["revision"]) == 0:
				return _result(false, "nothing_changed", "Noch kein Pixel geändert.")
			state["saved"] = true
			message = "Icon-Revision %d lokal gesichert." % int(state["revision"])
		_:
			state["processed"] = int(state["processed"]) + 1
			state["progress"] = mini(100, int(state["progress"]) + 25)
			if kind in ["edit", "transform"]:
				state["revision"] = int(state["revision"]) + 1
			if kind in ["archive", "copy", "extract", "recover", "save", "print"]:
				state["saved"] = true
			if kind == "compile":
				state["compiled"] = true
			message = _default_message(action_id, kind)
	if artifact_size > 0 and _write_hdd_artifact(action_id, kind, artifact_size):
		message += Loc.t("ui.generic_program_runtime.saved_to_dh0",
			" · auf DH0: gesichert.")
	var ticks := operation_ticks(kind)
	state["last_action"] = action_id
	state["last_ticks"] = ticks
	history.push_front(message)
	if history.size() > 4:
		history.resize(4)
	return _result(true, "ok", message, changed, false, ticks)


func operation_ticks(kind: String) -> int:
	var base: int = int({
		"inspect": 18, "select": 6, "edit": 22, "transform": 48,
		"copy": 80, "archive": 110, "extract": 88, "recover": 160,
		"save": 40, "print": 120, "compile": 150, "execute": 42,
		"network": 180, "monitor": 16, "toggle": 8, "navigate": 8,
		"destructive": 180,
	}.get(kind, 40))
	return maxi(1, ceili(float(base) / performance_factor()))


static func performance_factor() -> float:
	var stats := _autoload("PlayerStats")
	if stats == null:
		return 1.0
	# Neuere Hardware-Stränge können ein reichhaltiges Profil bereitstellen.
	# Wir lesen es nur und bleiben mit älteren Spielständen/API-Ständen kompatibel.
	if stats.has_method("performance_profile"):
		var profile: Variant = stats.call("performance_profile")
		if profile is Dictionary:
			for key in ["performance_multiplier", "program_speed", "speed_multiplier", "cpu_factor"]:
				if (profile as Dictionary).has(key):
					return clampf(float((profile as Dictionary)[key]), 0.5, 12.0)
	if stats.has_method("cpu_clock_mhz"):
		return clampf(float(stats.call("cpu_clock_mhz")) / 7.09, 0.5, 12.0)
	return 1.0


func state_snapshot() -> Dictionary:
	return state.duplicate(true)


func _action_spec(action_id: String) -> Array:
	for row: Array in available_actions():
		if str(row[0]) == action_id:
			return row
	return []


func _requirement_failure(kind: String) -> Dictionary:
	var stats := _autoload("PlayerStats")
	if kind == "print" and stats != null and stats.has_method("has_printer") \
			and not bool(stats.call("has_printer")):
		return _result(false, "printer_required", "Kein Drucker angeschlossen.")
	if kind == "network" and stats != null and stats.has_method("has_modem") \
			and not bool(stats.call("has_modem")):
		return _result(false, "modem_required", "Kein Modem angeschlossen.")
	return {}


func _ram_snapshot() -> Dictionary:
	var stats := _autoload("PlayerStats")
	if stats != null and stats.has_method("ram_breakdown"):
		return (stats.call("ram_breakdown") as Dictionary).duplicate(true)
	return {"total_kb": 512, "chip_kb": 512, "slow_kb": 0, "fast_kb": 0}


func _artifact_size_kb(kind: String) -> int:
	return int({
		"save": 18, "copy": 96, "archive": 72, "extract": 144,
		"recover": 128, "compile": 84,
	}.get(kind, 0))


func _hdd_has_space(size_kb: int) -> bool:
	var stats := _autoload("PlayerStats")
	if stats == null or not stats.has_method("hdd_info"):
		return true
	var info: Variant = stats.call("hdd_info")
	if not (info is Dictionary) or not bool(info.get("available", false)):
		return true
	return int(info.get("free_kb", 0)) >= size_kb


func _write_hdd_artifact(action_id: String, kind: String, size_kb: int) -> bool:
	var stats := _autoload("PlayerStats")
	if stats == null or not stats.has_method("hdd_info") \
			or not stats.has_method("hdd_write_file"):
		return false
	var info: Variant = stats.call("hdd_info")
	if not (info is Dictionary) or not bool(info.get("available", false)):
		return false
	return bool(stats.call("hdd_write_file",
		"Work/%s/%s" % [program_id, action_id], size_kb,
		{"kind": kind, "program_id": program_id}))


func _default_message(action_id: String, kind: String) -> String:
	var subject := str(capability.get("noun", "Daten"))
	match kind:
		"inspect": return "%s geprüft: keine kritischen Fehler." % subject
		"edit": return "%s geändert (Revision %d)." % [subject, int(state["revision"])]
		"transform": return "%s verarbeitet; Original bleibt erhalten." % subject
		"copy": return "%s kopiert und verifiziert." % subject
		"archive": return "%s gepackt; Prüfsumme stimmt." % subject
		"extract": return "%s in ein neues Ziel entpackt." % subject
		"recover": return "%s gelesen; rettbare Daten separat gesichert." % subject
		"print": return "%s an die Druckerwarteschlange übergeben." % subject
		"network": return "%s: Transferzustand lokal aktualisiert." % subject
		"navigate": return "%s: nächste Ansicht." % subject
		"destructive": return "%s nach Bestätigung bearbeitet und verifiziert." % subject
		_: return "%s: %s abgeschlossen." % [subject, action_id]


func _result(ok: bool, code: String, message: String, changed := false,
		confirmation_required := false, ticks := 0) -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"message": message,
		"changed": changed,
		"confirmation_required": confirmation_required,
		"ticks": ticks,
		"program_id": program_id,
		"state": state_snapshot(),
	}


static func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/" + node_name)
	return null
