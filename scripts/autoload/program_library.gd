extends Node
## ProgramLibrary — die Workbench-Software-Bibliothek. Lädt data/programs.json,
## verwaltet Besitz (PlayerStats.programs) und die Unlock-Regeln: NICHT alles ist
## sofort da. Ein Programm ist erst verfügbar, wenn Jahr, Hardware/RAM,
## Freundes-Vertrauen, Modem/BBS-Zugang bzw. Club-Mitgliedschaft passen — und man
## es aus einer seiner Quellen (BBS, Laden, Club, Freund, Heft-CD, Flohmarkt)
## bezogen hat. Werkbank/BBS lesen alles hierüber.

const PATH := "res://data/programs.json"
const Aliases := preload("res://scripts/data/program_aliases.gd")

var _all: Array = []
var _by_id: Dictionary = {}


func _ready() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("programs.json fehlt!")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_all = parsed.get("programs", [])
		for p: Dictionary in _all:
			_by_id[Aliases.canonical(str(p["id"]))] = p


func all() -> Array:
	return _all


func get_program(id: String) -> Dictionary:
	return _by_id.get(Aliases.canonical(id), {})


func is_installed(id: String) -> bool:
	return PlayerStats.has_program(id)


## Autoritativer Startvertrag fuer alle Eintraege aus programs.json.
## `known` ist absichtlich getrennt von `ok`: Andere Launcher duerfen statische
## Vollspiele oder Disk-Software mit eigenen IDs weiterhin selbst behandeln.
## Nur ein BEKANNTER Bibliothekseintrag wird hier verbindlich gesperrt.
func launch_status(id: String) -> Dictionary:
	var canonical_id := Aliases.canonical(id)
	var program := get_program(canonical_id)
	if program.is_empty():
		return _status(false, false, "unknown_program", "", canonical_id, {})
	var program_name := str(program.get("display_name", canonical_id))
	if not is_installed(canonical_id):
		return _status(true, false, "not_installed",
			Loc.t("sys.program_library.not_installed",
				"»%s« ist nicht installiert.") % program_name,
			canonical_id, program)
	var access := requirement_status(program)
	if not bool(access.get("ok", false)):
		return _status(true, false, str(access.get("code", "requirements")),
			Loc.t("sys.program_library.cannot_launch_reason",
				"»%s« kann nicht gestartet werden: %s.") % [
				program_name, str(access.get("reason", ""))], canonical_id, program)
	return _status(true, true, "ready", "", canonical_id, program)


## Autoritativer Startvertrag fuer eine physisch eingelegte Programmdiskette.
## Das Medium ist fuer diesen Start selbst der Besitznachweis: Es installiert
## die Software nicht heimlich auf Sommerbench, muss aber weiterhin Jahr und
## Hardwareanforderungen erfuellen. Damit bleiben X-COPY-Disketten wirklich
## selbstbootend, waehrend das Schubladen-Icon nur nach Installation startet.
func launch_from_media_status(id: String) -> Dictionary:
	var canonical_id := Aliases.canonical(id)
	var program := get_program(canonical_id)
	if program.is_empty():
		return _status(false, false, "unknown_program", "", canonical_id, {})
	var access := requirement_status(program)
	if not bool(access.get("ok", false)):
		var program_name := str(program.get("display_name", canonical_id))
		return _status(true, false, str(access.get("code", "requirements")),
			Loc.t("sys.program_library.cannot_boot_media_reason",
				"»%s« kann von Diskette nicht gestartet werden: %s.") % [
				program_name, str(access.get("reason", ""))], canonical_id, program)
	return _status(true, true, "media_ready", "", canonical_id, program)


## Vorpruefung fuer Erwerbswege. `source` ist optional, damit Laden, BBS,
## Questbelohnungen und Save-Recovery denselben Regelkern abfragen koennen,
## ohne den historischen install(id)-Mutationsvertrag zu veraendern.
func install_status(id: String, source := "") -> Dictionary:
	var canonical_id := Aliases.canonical(id)
	var program := get_program(canonical_id)
	if program.is_empty():
		return _status(false, false, "unknown_program",
			Loc.t("sys.program_library.unknown_program",
				"Dieses Programm ist nicht in der Software-Bibliothek."),
			canonical_id, {})
	var program_name := str(program.get("display_name", canonical_id))
	if is_installed(canonical_id):
		return _status(true, false, "already_installed",
			Loc.t("sys.program_library.already_installed",
				"»%s« ist bereits installiert.") % program_name,
			canonical_id, program)
	var access := requirement_status(program)
	if not bool(access.get("ok", false)):
		return _status(true, false, str(access.get("code", "requirements")),
			Loc.t("sys.program_library.cannot_install_reason",
				"»%s« kann nicht installiert werden: %s.") % [
				program_name, str(access.get("reason", ""))], canonical_id, program)
	var source_id := str(source)
	if not source_id.is_empty() and source_id not in program.get("source", []):
		return _status(true, false, "source_unavailable",
			Loc.t("sys.program_library.source_unavailable",
				"»%s« ist nicht ueber %s erhaeltlich.") % [
				program_name, _source_label(source_id)], canonical_id, program)
	if PlayerStats.hdd_is_usable():
		var size_kb := install_size_kb(program)
		var free_kb := int(PlayerStats.hdd_info().get("free_kb", 0))
		if free_kb < size_kb:
			return _status(true, false, "not_enough_hdd_space",
				Loc.t("sys.program_library.not_enough_hdd_space",
					"Auf DH0: fehlen %d KB fuer »%s«.") % [
						size_kb - free_kb, program_name], canonical_id, program)
	return _status(true, true, "ready", "", canonical_id, program)


func install(id: String) -> bool:
	var program := get_program(id)
	if program.is_empty():
		return false
	return PlayerStats.add_program(Aliases.canonical(id), install_size_kb(program))


## Reale, konservative Installationsgröße für die damaligen Programme. Der
## Katalog bleibt damit kompakt; einzelne Programme können den Wert bei Bedarf
## mit `install_size_kb` präzise überschreiben.
func install_size_kb(program: Dictionary) -> int:
	if program.has("install_size_kb"):
		return maxi(1, int(program["install_size_kb"]))
	var by_category := {
		"system": 220, "file": 180, "disk": 240, "music": 420,
		"graphics": 760, "text": 520, "code": 680, "comm": 260,
		"scene": 540, "cd": 900, "media": 620,
	}
	var size := int(by_category.get(str(program.get("category", "system")), 256))
	match str(program.get("rarity", "common")):
		"rare": size = roundi(size * 1.35)
		"uncommon": size = roundi(size * 1.15)
	return size


## Nach der erstmaligen DH0-Einrichtung werden Programme aus älteren Saves
## einmalig als echte Dateien materialisiert. Besitz bleibt die Wahrheit; der
## Sync ist idempotent und meldet Platzmangel, statt Einträge zu verlieren.
func sync_installed_to_hdd() -> Dictionary:
	if not PlayerStats.hdd_is_usable():
		return {"ok": false, "copied": 0, "skipped": 0,
			"missing_space": [], "message": Loc.t("sys.program_library.dh0_not_usable",
				"DH0: ist noch nicht nutzbar.")}
	var copied := 0
	var skipped := 0
	var missing_space: Array[String] = []
	var info: Dictionary = PlayerStats.hdd_info()
	var files: Dictionary = info.get("files", {})
	for value: Variant in PlayerStats.programs:
		var program_id := Aliases.canonical(str(value))
		var target := "Utilities/%s" % program_id
		if files.has(target):
			skipped += 1
			continue
		var program := get_program(program_id)
		var size_kb := install_size_kb(program)
		if PlayerStats.hdd_write_file(target, size_kb,
				{"kind": "program", "program_id": program_id}):
			copied += 1
			files[target] = {"size_kb": size_kb, "kind": "program",
				"program_id": program_id}
		else:
			missing_space.append(program_id)
	return {
		"ok": missing_space.is_empty(),
		"copied": copied,
		"skipped": skipped,
		"missing_space": missing_space,
		"message": Loc.t("sys.program_library.hdd_program_sync",
			"%d Programme nach DH0: übernommen%s.") % [
			copied,
			"" if missing_space.is_empty() else
				Loc.t("sys.program_library.hdd_program_sync_no_space",
					"; %d passen nicht mehr auf die Platte") % missing_space.size(),
		],
	}


## Installierte Programme (für die Werkbank-Icons), in Katalogreihenfolge.
func installed_programs() -> Array:
	return _all.filter(func(p: Dictionary) -> bool: return is_installed(p["id"]))


## Programme, die aus einer Quelle beziehbar SIND (Jahr passt) — z. B. für die
## BBS-Liste (source "bbs_download"). Voraussetzungen prüft requirement_status().
func available_from(src: String) -> Array:
	return _all.filter(func(p: Dictionary) -> bool:
		return src in p.get("source", []) and _year_ok(p) and not is_installed(p["id"]))


func _year_ok(p: Dictionary) -> bool:
	var y := TimeManager.year
	return y >= int(p.get("year_from", 0)) and y <= int(p.get("year_to", 9999))


## Voraussetzungen eines Programms gegen den aktuellen Stand. {ok, reason}.
func requirement_status(p: Dictionary) -> Dictionary:
	var year_from := int(p.get("year_from", 0))
	var year_to := int(p.get("year_to", 9999))
	if TimeManager.year < year_from:
		return {"ok": false, "code": "future_year", "reason":
			Loc.t("sys.program_library.available_from_year", "erst ab %d verfuegbar") % year_from}
	if TimeManager.year > year_to:
		return {"ok": false, "code": "past_year", "reason":
			Loc.t("sys.program_library.available_until_year", "nur bis %d verfuegbar") % year_to}
	var req: Dictionary = p.get("requirements", {})
	if bool(req.get("modem", false)) and not PlayerStats.has_modem():
		return {"ok": false, "code": "missing_modem", "reason": Loc.t("sys.program_library.braucht_modem", "braucht ein Modem")}
	if bool(req.get("external_drive", false)) and not PlayerStats.has_hardware("external_drive"):
		return {"ok": false, "code": "missing_external_drive", "reason": Loc.t("sys.program_library.braucht_externe_laufwerk_df1", "braucht das externe Laufwerk (DF1:)")}
	if bool(req.get("printer", false)) and not PlayerStats.has_printer():
		return {"ok": false, "code": "missing_printer", "reason":
			Loc.t("sys.program_library.needs_printer", "braucht einen Drucker")}
	var need_ram := float(req.get("ram_mb", 0))
	var installed_ram_mb := float(int(PlayerStats.ram_breakdown()["total_kb"])) / 1024.0
	if need_ram > 0.0 and installed_ram_mb < need_ram:
		# Godots %-Formatter kennt kein C/Python-%g. Dieser Fehler trat erst beim
		# echten Oeffnen des BBS-Dateibereichs auf, sobald dessen Programmliste
		# eine RAM-Anforderung pruefte, und liess DATEIEN wie einen toten Button
		# wirken.
		var ram_label := str(int(need_ram)) if is_equal_approx(need_ram, floorf(need_ram)) \
			else "%.1f" % need_ram
		return {"ok": false, "code": "missing_ram", "reason":
			Loc.t("sys.program_library.needs_ram", "braucht %s MB RAM (Speichererweiterung)") % ram_label}
	var need_trust := int(req.get("friend_trust", 0))
	if need_trust > 0 and _max_trust() < need_trust:
		return {"ok": false, "code": "missing_friend_trust", "reason": Loc.t("sys.program_library.freund_muss_dir_mehr_vertrauen_d", "ein Freund muss dir mehr vertrauen (%d)") % need_trust}
	if bool(req.get("bbs_access", false)) and not BBSManager.available():
		return {"ok": false, "code": "missing_bbs_access", "reason":
			Loc.t("sys.program_library.needs_bbs_access", "braucht einen funktionierenden Mailbox-Zugang")}
	if bool(req.get("club_membership", false)) and not bool(GameManager.flags.get("club_member", false)):
		return {"ok": false, "code": "missing_club_membership", "reason": Loc.t("sys.program_library.nur_uber_den_computerclub", "nur über den Computerclub")}
	return {"ok": true, "code": "ready", "reason": ""}


func _status(known: bool, ok: bool, code: String, reason: String,
		canonical_id: String, program: Dictionary) -> Dictionary:
	return {
		"known": known,
		"ok": ok,
		"code": code,
		"reason": reason,
		"id": canonical_id,
		"program": program,
	}


func _source_label(source_id: String) -> String:
	match source_id:
		"preinstalled": return Loc.t("sys.program_library.source_preinstalled", "der Vorinstallation")
		"computer_shop": return Loc.t("sys.program_library.source_computer_shop", "den Computerladen")
		"bbs_download": return Loc.t("sys.program_library.source_bbs", "die Mailbox")
		"computer_club": return Loc.t("sys.program_library.source_computer_club", "den Computerclub")
		"friend": return Loc.t("sys.program_library.source_friend", "einen Freund")
		"magazine_coverdisk": return Loc.t("sys.program_library.source_magazine", "eine Heftdiskette")
		"flea_market": return Loc.t("sys.program_library.source_flea_market", "den Flohmarkt")
		_: return source_id


func _max_trust() -> int:
	var mx := 0
	for id in NPCManager.npcs:
		mx = maxi(mx, NPCManager.get_trust(id))
	return mx


## Beim Spielstart: die vorinstallierten Werkbank-Basics einrichten (Programme
## mit Quelle "preinstalled", deren Startjahr erreicht ist).
func preinstall() -> void:
	for p: Dictionary in _all:
		if "preinstalled" in p.get("source", []) and TimeManager.year >= int(p.get("year_from", 0)):
			PlayerStats.add_program(Aliases.canonical(str(p["id"])))
