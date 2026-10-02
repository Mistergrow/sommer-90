extends RefCounted
## Ein zentraler Vertrag fuer alle spielerseitigen Diskettenwege. Die Sammlung
## darf als HUD-Katalog ueberall angesehen werden; physische Arbeiten brauchen
## die Box im Zimmer, Laufwerksarbeiten zusaetzlich den eingeschalteten und
## gerade benutzten Heimcomputer. Manager-APIs bleiben fuer Simulation und Tests
## bewusst zustandsfrei — die harte Grenze liegt an der UI-/Anwendungsschicht.


static func archive_mutation() -> Dictionary:
	var base := _room_access()
	if not bool(base.get("ok", false)):
		return base
	var game: Node = _autoload("GameManager")
	var ui: Node = _autoload("UIManager")
	var active := _active_program(ui, game)
	if active != null and str(active.name) != "Werkbank":
		return {"ok": false,
			"reason": Loc.t("ui.disk_access_policy.erst_eingelegte_medium_bzw_laufende_programm", "Erst das eingelegte Medium bzw. laufende Programm beenden; die Diskettenbox bleibt solange schreibgeschuetzt.")}
	return {"ok": true, "reason": ""}


static func computer_media(ui: Node) -> Dictionary:
	var base := _room_access()
	if not bool(base.get("ok", false)):
		return base
	var game: Node = _autoload("GameManager")
	if game == null:
		return {"ok": false, "reason": Loc.t("ui.disk_access_policy.noch_kein_laufender_spielstand", "Noch kein laufender Spielstand.")}
	if not bool(ui.call("domain_on", "strip")):
		return {"ok": false, "reason": Loc.t("ui.disk_access_policy.mehrfachverteiler_unter_dem_tisch_ist_aus", "Der Mehrfachverteiler unter dem Tisch ist aus.")}
	if not bool(ui.call("domain_on", "amiga")):
		return {"ok": false, "reason": Loc.t("ui.disk_access_policy.amiga_ist_aus_netzteil_einschalten", "Der Amiga ist aus. Netzteil einschalten.")}
	if not bool(ui.call("domain_on", "monitor")):
		return {"ok": false, "reason": Loc.t("ui.disk_access_policy.monitor_ist_aus", "Der Monitor ist aus.")}
	if not bool(ui.get("at_computer")):
		return {"ok": false,
			"reason": Loc.t("ui.disk_access_policy.setz_dich_an_den_amiga_oeffne", "Setz dich an den Amiga und oeffne auf der Werkbank das Disketten-Verzeichnis.")}
	var active := _active_program(ui, game)
	if active != null and str(active.name) not in ["Werkbank", "BootSelect"]:
		return {"ok": false,
			"reason": Loc.t("ui.disk_access_policy.erst_laufende_programm_beenden_zur_werkbank", "Erst das laufende Programm beenden und zur Werkbank zurueckkehren.")}
	return {"ok": true, "reason": ""}


## Die globale HUD-Box ist nur ein Archiv. Ihre Rechner-Schaltflaechen werden
## erst freigeschaltet, wenn der Spieler wirklich in der Werkbank sitzt. Der
## Kickstart-Selektor bleibt damit ein echter Einlegeweg statt eines Shortcuts.
static func workbench_media(ui: Node) -> Dictionary:
	var gate := computer_media(ui)
	if not bool(gate.get("ok", false)):
		return gate
	var game: Node = _autoload("GameManager")
	var active := _active_program(ui, game)
	if active == null or str(active.name) != "Werkbank":
		return {"ok": false,
			"reason": Loc.t("ui.disk_access_policy.erst_workbench_disk_booten_dort_disketten", "Erst die Workbench-Disk booten und dort das Disketten-Verzeichnis oeffnen.")}
	return {"ok": true, "reason": ""}


static func require_archive(action: String) -> bool:
	var gate := archive_mutation()
	if bool(gate.get("ok", false)):
		return true
	var ui := _autoload("UIManager")
	if ui != null:
		ui.call("toast", "%s: %s" % [action, str(gate.get("reason", "Nicht verfuegbar."))])
	return false


static func require_computer(ui: Node, action: String) -> bool:
	var gate := computer_media(ui)
	if bool(gate.get("ok", false)):
		return true
	ui.call("toast", "%s: %s" % [action, str(gate.get("reason", "Nicht verfuegbar."))])
	return false


static func require_workbench(ui: Node, action: String) -> bool:
	var gate := workbench_media(ui)
	if bool(gate.get("ok", false)):
		return true
	ui.call("toast", "%s: %s" % [action, str(gate.get("reason", "Nicht verfuegbar."))])
	return false


static func _room_access() -> Dictionary:
	var game: Node = _autoload("GameManager")
	if game == null or int(game.get("state")) != 1: # GameManager.State.PLAYING
		return {"ok": false, "reason": Loc.t("ui.disk_access_policy.noch_kein_laufender_spielstand", "Noch kein laufender Spielstand.")}
	if str(game.get("current_location_id")) != "room":
		return {"ok": false,
			"reason": Loc.t("ui.disk_access_policy.physische_diskettenbox_steht_zu_hause_im", "Die physische Diskettenbox steht zu Hause im Zimmer — hier ist nur die Archivansicht verfuegbar.")}
	return {"ok": true, "reason": ""}


static func _active_program(ui: Node, game: Node) -> Control:
	if ui == null or game == null or not ui.has_method("_top_program"):
		return null
	var host: Variant = game.get("location_host")
	if not host is Control:
		return null
	var active: Variant = ui.call("_top_program", host)
	return active as Control


static func _autoload(name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath("/root/" + name))
