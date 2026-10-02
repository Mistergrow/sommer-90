extends Node
## SceneReleaseManager — persistenter Kern der fiktiven BYTEWERK-Pipeline.
##
## Sicherheits-/Stilregel: P-8 ist ein erfundenes Logiksystem. Keine reale
## Adresse, kein Opcode und kein Patch-Byte verlässt diesen Manager. Sichtbare
## Personen-Credits werden ausschließlich als BBS-Handle-Snapshots gespeichert.

signal scene_changed

const CONFIG_PATH := "res://data/scene_release.json"
const PATCH_STATES := ["none", "bare", "draft", "verified", "legacy_scene"]
const ReleaseFeedback := preload("res://scripts/scene/scene_release_feedback.gd")
const HandleRules := preload("res://scripts/scene/scene_handle_rules.gd")
const HandleService := preload("res://scripts/scene/scene_handle_service.gd")
const PuzzleEngine := preload("res://scripts/scene/scene_patch_puzzle_engine.gd")
const OwnGameDistributionService := preload("res://scripts/scene/own_game_distribution.gd")
const ReleaseUploadService := preload("res://scripts/scene/scene_release_upload_service.gd")

var _config: Dictionary = {}

var scene_handle: String = ""
var releases: Dictionary = {}             # release_serial -> bereinigte Zusammenfassung
var uploads: Array = []                   # idempotente Serial/Board-Einträge
var scene_recognition: int = 0            # global, getrennt von Gruppenruf
var group_rep: Dictionary = {}            # group_id -> 0..100
var cooperation_offers: Array = []        # sichtbare, persistente Angebote
var cooperation_status: Dictionary = {}   # group_id -> none/offered/accepted
var school_attention: int = 0             # transparenter, milder Schulhof-Risikowert
var school_attempts: Dictionary = {}      # day/disk -> fortlaufender, savefester Versuch
var school_interruptions: Dictionary = {} # day/disk -> Nebenfolge bereits verbucht
var alias_assignments: Dictionary = {}    # actor_id -> letzter sicherer Handle-Snapshot
var sales: Array = []
var _release_counter: int = 0
var game_distribution: Dictionary = {}


func _ready() -> void:
	_load_config()
	_ensure_group_state()
	var time := get_node_or_null("/root/TimeManager")
	if time != null and time.has_signal("day_changed") and not time.day_changed.is_connected(_on_day_changed):
		time.day_changed.connect(_on_day_changed)


func _on_day_changed() -> void:
	var before := school_attention
	school_attention = maxi(0, school_attention - 8)
	school_attempts = {}
	school_interruptions = {}
	var royalty_paid := OwnGameDistributionService.settle(self)
	if school_attention != before or royalty_paid > 0:
		scene_changed.emit()


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("SceneReleaseManager: %s fehlt" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if parsed is Dictionary:
		_config = parsed
	else:
		push_error("SceneReleaseManager: ungültiges JSON in %s" % CONFIG_PATH)


func config() -> Dictionary:
	return _config.duplicate(true)


func reset() -> void:
	scene_handle = ""
	releases = {}
	uploads = []
	scene_recognition = 0
	group_rep = {}
	cooperation_offers = []
	cooperation_status = {}
	school_attention = 0
	school_attempts = {}
	school_interruptions = {}
	alias_assignments = {}
	sales = []
	game_distribution = {}
	_release_counter = 0
	_ensure_group_state()
	scene_changed.emit()


func _ensure_group_state() -> void:
	for group: Dictionary in _config.get("groups", []):
		var id := str(group.get("id", ""))
		if id == "":
			continue
		if not group_rep.has(id):
			group_rep[id] = 0
		if not cooperation_status.has(id):
			cooperation_status[id] = "none"


# --------------------------------------------------------------- Handles

func normalize_handle(value: String) -> String:
	return HandleRules.normalize(value)


## Reines Szenen-Handle: 3..16 ASCII-Zeichen, beginnt alphanumerisch.
func handle_valid(value: String) -> bool:
	return HandleRules.valid(value)


func set_scene_handle(value: String) -> Dictionary:
	return HandleService.set_player_handle(self, value)


## Deterministische Vorschläge — ausdrücklich NICHT aus PlayerIdentity/Klarnamen.
func handle_suggestions(seed_hint: String = "") -> Array:
	return HandleService.suggestions(self, seed_hint)


## Einzige Zuordnung von Spielfiguren zu sichtbaren Credits. Kein Zugriff auf
## NPCManager.name, PlayerIdentity.player_name oder Message-Autoren.
func handle_for_actor(actor_id: String) -> String:
	return HandleService.handle_for_actor(self, actor_id)


func credit_candidates() -> Array:
	return HandleService.credit_candidates(self)


# --------------------------------------------------------------- Eignung

func eligibility(disk: Disk) -> Dictionary:
	if disk == null:
		return _eligibility_result(false, "Keine Diskette eingelegt.")
	if disk.condition <= 0:
		return _eligibility_result(false, "Die Diskette ist defekt.")
	if disk.virus and disk.checked:
		return _eligibility_result(false, "Bekannter Virusfund: erst eine saubere Arbeitskopie anlegen.")
	var entry := CultureManager.software(disk.software_id)
	if entry.is_empty():
		return _eligibility_result(false, "BYTEWERK V1 kennt nur die kuratierten fiktiven Titel.")
	if str(entry.get("protection", "keine")) == "keine":
		return _eligibility_result(false, "Dieser Titel ist ungeschützt und braucht kein P-8-Release.")
	if disk.provenance != CultureManager.PROVENANCE_COPY:
		return _eligibility_result(false, "Zuerst eine Gen-1-Arbeitskopie des Originals anlegen.")
	if disk.copy_generation != 1:
		return _eligibility_result(false, "BYTEWERK akzeptiert nur Gen-1-Kopien direkt vom Original.")
	var required_revision := CultureManager.bytewerk_protection_revision(disk.software_id)
	if disk.patch_state == "verified":
		var installed_revision := maxi(1, disk.patch_revision)
		if installed_revision < required_revision:
			var revision := PuzzleEngine.revision_definition(_config, required_revision)
			return _eligibility_result(true,
				"Der alte P-8-Patch V%d passt nicht mehr. %s benötigt eine neue Analyse."
				% [installed_revision, str(revision.get("name", "P-8 V%d" % required_revision))],
				required_revision, true)
		return _eligibility_result(false, "Dieses Release ist bereits mit der aktuellen P-8-Revision verifiziert.")
	if disk.patch_state == "legacy_scene":
		return _eligibility_result(false, "Legacy-Szene-Release: kein erneuter P-8-Lauf nötig.")
	if disk.patch_state == "none":
		if not CultureManager.bytewerk_introduced():
			return _eligibility_result(false, "BYTEWERK wurde noch nicht eingeführt. Diese Diskette bleibt unverändert.")
		if CultureManager.bytewerk_title_selected(disk.software_id):
			return _eligibility_result(false, "Diese Diskette entstand ohne BYTEWERK-Profil und bleibt unverändert. Lege vom Original eine neue Gen-1-Kopie an.")
		return _eligibility_result(false, "Für diesen Titel existiert kein BYTEWERK-Profil.")
	if disk.patch_state not in ["bare", "draft"]:
		return _eligibility_result(false, "Keine gültige rohe BYTEWERK-Arbeitskopie.")
	if disk.source_provenance not in [CultureManager.PROVENANCE_ORIGINAL, CultureManager.PROVENANCE_ORIGINAL_BOX, "legacy_unknown"]:
		return _eligibility_result(false, "Die Quelle ist nicht als Original belegt.")
	return _eligibility_result(true, "Gen-1-Arbeitskopie bereit für die fiktive P-8-Analyse.", required_revision)


func _eligibility_result(ok: bool, message: String, revision: int = 0, update: bool = false) -> Dictionary:
	return {
		"ok": ok, "reason": "" if ok else message, "text": message,
		"revision": revision, "update": update,
	}


func eligible_disks() -> Array:
	var result: Array = []
	for disk: Disk in DiskManager.disks:
		if eligibility(disk)["ok"]:
			result.append(disk)
	return result


# --------------------------------------------------------------- P-8 Puzzle

func generate_puzzle(disk: Disk, difficulty: String = "standard") -> Dictionary:
	var allowed := eligibility(disk)
	if not allowed["ok"]:
		return {"ok": false, "text": allowed["text"], "rows": [], "rules": []}
	var revision := maxi(1, int(allowed.get("revision", CultureManager.bytewerk_protection_revision(disk.software_id))))
	if disk.patch_seed == 0:
		disk.patch_seed = absi(hash("P8/%s/%s/%d" % [disk.uid, disk.software_id, disk.copy_generation]))
	var puzzle := PuzzleEngine.generate(_config, disk.patch_seed, difficulty, revision)
	disk.patch_state = "draft"
	disk.patch_draft = {
		"difficulty": str(puzzle.get("difficulty", "standard")),
		"answers": {},
		"revision": revision,
	}
	scene_changed.emit()
	return puzzle


func auto_solution(puzzle: Dictionary) -> Dictionary:
	return PuzzleEngine.auto_solution(puzzle)


func verify_puzzle(puzzle: Dictionary, answers: Variant, manual: bool = true) -> Dictionary:
	return PuzzleEngine.verify(_config, puzzle, answers, manual)


func save_patch_draft(disk: Disk, draft: Dictionary) -> void:
	if disk == null or disk.patch_state not in ["bare", "draft"]:
		return
	disk.patch_state = "draft"
	disk.patch_draft = draft.duplicate(true)
	scene_changed.emit()


# --------------------------------------------------------------- Intro/Release

func intro_options() -> Dictionary:
	var year := _year()
	var scrollers: Array = []
	for entry: Dictionary in _config.get("scrollers", []):
		if year >= int(entry.get("from", 1990)) and year <= int(entry.get("to", 1999)):
			scrollers.append(entry.duplicate(true))
	return {
		"logos": (_config.get("logos", []) as Array).duplicate(true),
		"palettes": (_config.get("palettes", []) as Array).duplicate(true),
		"effects": (_config.get("effects", []) as Array).duplicate(true),
		"scrollers": scrollers,
	}


func finalize_release(disk: Disk, payload: Dictionary, patch_result: Dictionary) -> Dictionary:
	var allowed := eligibility(disk)
	if not allowed["ok"]:
		return {"ok": false, "text": allowed["text"]}
	if not handle_valid(scene_handle):
		return {"ok": false, "text": Loc.t("sys.scene_release_manager.zuerst_gultiges_bbs_handle_wahlen", "Zuerst ein gültiges BBS-Handle wählen.")}
	if not bool(patch_result.get("ok", false)):
		return {"ok": false, "text": Loc.t("sys.scene_release_manager.p_8_ist_noch_nicht_in", "P-8 ist noch nicht in allen drei Testboots stabil.")}
	var boots: Array = patch_result.get("boot_results", [true, true, true])
	if boots.size() < 3 or not bool(boots[0]) or not bool(boots[1]) or not bool(boots[2]):
		return {"ok": false, "text": Loc.t("sys.scene_release_manager.release_braucht_drei_erfolgreiche_testboots", "Das Release braucht drei erfolgreiche Testboots.")}

	var options := intro_options()
	var logo := _valid_option_id(payload.get("logo", payload.get("logo_id", "")), options["logos"])
	var palette := _valid_option_id(payload.get("palette", payload.get("palette_id", "")), options["palettes"])
	var scroller_id := _valid_option_id(payload.get("scroller_id", payload.get("scroller", "")), options["scrollers"])
	if logo == "" or palette == "" or scroller_id == "":
		return {"ok": false, "text": Loc.t("sys.scene_release_manager.logo_palette_oder_scroller_ist_in", "Logo, Palette oder Scroller ist in diesem Jahr nicht verfügbar.")}
	var effects := _sanitize_effects(payload.get("effects", []), options["effects"])
	if effects.is_empty():
		return {"ok": false, "text": Loc.t("sys.scene_release_manager.mindestens_einen_passenden_intro_effekt_wahlen", "Mindestens einen passenden Intro-Effekt wählen.")}

	var selected_group := str(payload.get("group_id", ""))
	if str(cooperation_status.get(selected_group, "none")) != "accepted" or not _group_active(selected_group):
		selected_group = ""
	var presenting := scene_handle
	if selected_group != "":
		presenting = str(_group_definition(selected_group).get("name", scene_handle))
	var credits := _sanitize_credits(payload)
	var serial := _next_serial()
	var scroller := _option_by_id(scroller_id, options["scrollers"])
	var rendered_text := _render_scroller(str(scroller.get("text", "")), disk, presenting)
	var patch_score := clampi(int(patch_result.get("score", 70)), 0, 100)
	var stability := clampi(int(patch_result.get("stability", 80)), 0, 100)
	var style_score := 55 + mini(3, effects.size()) * 8 + mini(2, credits.size() - 1) * 4
	if effects.size() == 2:
		style_score += 5
	var quality := clampi(roundi(float(patch_score) * 0.68 + float(style_score) * 0.32), 1, 100)
	var release := {
		"serial": serial, "title": disk.content_title, "software_id": disk.software_id,
		"year": _year(), "player_handle": scene_handle, "presenting": presenting,
		"group_id": selected_group, "logo": logo, "palette": palette,
		"effects": effects, "scroller_id": scroller_id, "scroller_text": rendered_text,
		"credits": credits, "quality": quality, "stability": stability,
		"protection_revision": maxi(1, int(patch_result.get("revision", CultureManager.bytewerk_protection_revision(disk.software_id)))),
		"patch_steps": (patch_result.get("completed_steps", []) as Array).duplicate(),
		"tags": _release_tags(logo, palette, effects, options),
	}

	# Atomarer Zustandswechsel: erst nach vollständiger Validierung mutieren.
	disk.patch_state = "verified"
	disk.patch_draft = {}
	disk.patch_score = patch_score
	disk.patch_stability = stability
	disk.patch_revision = int(release["protection_revision"])
	disk.protection_revision = disk.patch_revision
	disk.patch_steps = (release["patch_steps"] as Array).duplicate()
	disk.boot_faults = []
	disk.cracktro = true
	disk.cracktro_seen = false
	disk.release_serial = serial
	disk.release_data = release.duplicate(true)
	disk.patched_on = _date_string()
	disk.release_role = "master"
	disk.enforce_master_color()
	releases[serial] = release.duplicate(true)
	var manual_run := bool(payload.get("manual_patch", patch_result.get("manual", true)))
	if manual_run:
		MinigameManager.finish("scene_patch", true, quality, {"serial": serial, "difficulty": payload.get("difficulty", "standard")})
	MinigameManager.save_creation("intro", release)
	if disk in DiskManager.disks:
		DiskManager.disks_changed.emit()
	scene_changed.emit()
	return {"ok": true, "text": Loc.t("sys.scene_release_manager.s_verifiziert_drei_testboots_grun", "%s verifiziert — drei Testboots grün.") % serial, "serial": serial, "release": release}


func _valid_option_id(value: Variant, options: Array) -> String:
	var id := str(value)
	if id == "" and not options.is_empty():
		id = str((options[0] as Dictionary).get("id", ""))
	return id if not _option_by_id(id, options).is_empty() else ""


func _option_by_id(id: String, options: Array) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("id", "")) == id:
			return option
	return {}


func _sanitize_effects(raw: Variant, options: Array) -> Array:
	var allowed: Array = options.map(func(e: Dictionary) -> String: return str(e.get("id", "")))
	var result: Array = []
	if raw is Array:
		for value in raw:
			var id := str(value)
			if value is Dictionary:
				id = str((value as Dictionary).get("id", ""))
			if id in allowed and id not in result:
				result.append(id)
			if result.size() >= 3:
				break
	return result


func _sanitize_credits(payload: Dictionary) -> Array:
	var result: Array = [{"actor_id": "player", "handle_snapshot": scene_handle, "role": "RELEASE"}]
	var candidates := {}
	for candidate: Dictionary in credit_candidates():
		candidates[str(candidate.get("actor_id", ""))] = candidate
	var raw: Variant = payload.get("credits", payload.get("contributors", []))
	if not raw is Array:
		return result
	for requested in raw:
		var actor_id := str(requested)
		if requested is Dictionary:
			actor_id = str((requested as Dictionary).get("actor_id", ""))
		if actor_id in ["", "player", "self"] or not candidates.has(actor_id):
			continue
		var candidate: Dictionary = candidates[actor_id]
		if not bool(candidate.get("available", false)):
			continue
		var snapshot := handle_for_actor(actor_id)
		# Nur der Snapshot aus BBSScene ist erlaubt; eventuell mitgelieferte freie
		# Texte (auch versehentliche Klarnamen) werden komplett ignoriert.
		result.append({
			"actor_id": actor_id, "handle_snapshot": snapshot,
			"role": str(candidate.get("role", "CREW")),
		})
		alias_assignments[actor_id] = snapshot
	return result


func _render_scroller(template: String, disk: Disk, presenting: String) -> String:
	return template.replace("{HANDLE}", scene_handle) \
		.replace("{PRESENTING}", presenting) \
		.replace("{TITLE}", disk.content_title.to_upper()) \
		.replace("{YEAR}", str(_year()))


func _release_tags(logo_id: String, palette_id: String, effects: Array, options: Dictionary) -> Array:
	var tags: Array = []
	var selections: Array = [
		_option_by_id(logo_id, options["logos"]),
		_option_by_id(palette_id, options["palettes"]),
	]
	for effect_id in effects:
		selections.append(_option_by_id(str(effect_id), options["effects"]))
	for selected: Dictionary in selections:
		for tag in selected.get("tags", []):
			if tag not in tags:
				tags.append(tag)
	return tags


func _next_serial() -> String:
	_release_counter += 1
	return "BW-%04d-%03d" % [_year(), _release_counter]


func mark_intro_seen(disk: Disk) -> Dictionary:
	if disk == null or not disk.cracktro:
		return {"ok": false, "text": Loc.t("sys.scene_release_manager.diese_diskette_hat_kein_szene_intro", "Diese Diskette hat kein Szene-Intro.")}
	disk.cracktro_seen = true
	if releases.has(disk.release_serial):
		var release: Dictionary = releases[disk.release_serial]
		release["intro_seen"] = true
		releases[disk.release_serial] = release
	if disk in DiskManager.disks:
		DiskManager.disks_changed.emit()
	scene_changed.emit()
	return {"ok": true, "text": Loc.t("sys.scene_release_manager.intro_vollstandig_angesehen", "Intro vollständig angesehen.")}


# --------------------------------------------------------------- Distribution

func sale_allowed(disk: Disk, _location_id: String = "") -> Dictionary:
	if disk == null or disk.provenance != CultureManager.PROVENANCE_COPY or disk.content_type == "leer" or disk.condition <= 0:
		return {"ok": false, "reason": "Keine verkäufliche Kopie.", "text": Loc.t("sys.scene_release_manager.keine_verkaufliche_kopie", "Keine verkäufliche Kopie.")}
	if disk.release_role in ["master", "demo_master"] or disk.is_game_master():
		return {"ok": false, "reason": "Der eigene Master bleibt im Archiv; verkaufe nur eine Arbeits- oder Distributionskopie.", "text": Loc.t("sys.scene_release_manager.eigene_master_bleibt_im_archiv_verkaufe", "Der eigene Master bleibt im Archiv; verkaufe nur eine Arbeits- oder Distributionskopie.")}
	# Kopienhandel bleibt ein klarer Spiel-Loop: keine System-, Werkzeug-, PD-,
	# Musik- oder Programmdisks als versehentlich lukrative Ware.
	if disk.content_type != "spiel":
		return {"ok": false, "reason": "Nur Spielkopien gehören in diesen Verkaufskanal.", "text": Loc.t("sys.scene_release_manager.nur_spielkopien_gehoren_in_diesen_verkaufskanal", "Nur Spielkopien gehören in diesen Verkaufskanal.")}
	if disk.virus and disk.checked:
		return {"ok": false, "reason": "Bekannter Virusfund.", "text": "Bekannter Virusfund."}
	var entry := CultureManager.software(disk.software_id)
	if entry.is_empty() and disk.patch_state != "legacy_scene":
		return {"ok": false, "reason": "Unbekannter Titel: Schutzstatus nicht verlässlich.", "text": Loc.t("sys.scene_release_manager.unbekannter_titel_schutzstatus_nicht_verlasslich", "Unbekannter Titel: Schutzstatus nicht verlässlich.")}
	if CultureManager.has_protection(disk.software_id):
		if disk.patch_state == "none":
			return {"ok": true, "reason": "", "text": Loc.t("sys.scene_release_manager.historische_kopie_ohne_bytewerk_profil_ist", "Historische Kopie ohne BYTEWERK-Profil ist freigegeben; keine rückwirkende Nachrüstung.")}
		if disk.patch_state == "legacy_scene" and disk.cracktro:
			return {"ok": true, "reason": "", "text": Loc.t("sys.scene_release_manager.legacy_szene_kopie_ist_freigegeben", "Legacy-Szene-Kopie ist freigegeben.")}
		if disk.patch_state != "verified" or not disk.cracktro:
			return {"ok": false, "reason": "Rohe geschützte Kopien laufen nicht und werden nicht angeboten.", "text": Loc.t("sys.scene_release_manager.rohe_geschutzte_kopien_laufen_nicht_werden", "Rohe geschützte Kopien laufen nicht und werden nicht angeboten.")}
		if not disk.cracktro_seen:
			return {"ok": false, "reason": "Intro erst vollständig testen.", "text": Loc.t("sys.scene_release_manager.intro_erst_vollstandig_testen", "Intro erst vollständig testen.")}
	return {"ok": true, "reason": "", "text": Loc.t("sys.scene_release_manager.kopie_ist_freigegeben", "Kopie ist freigegeben.")}


func note_sale(disk: Disk, location_id: String = "schoolyard", price: int = 0) -> Dictionary:
	var allowed := sale_allowed(disk, location_id)
	if not allowed["ok"]:
		return {"ok": false, "recognition_delta": 0, "attention_delta": 0, "text": allowed["text"]}
	var sale_key := disk.uid
	if sale_key == "":
		sale_key = "%s/%d" % [disk.release_serial, sales.size()]
	if sales.any(func(entry: Dictionary) -> bool: return str(entry.get("disk_uid", "")) == sale_key):
		return {"ok": true, "recognition_delta": 0, "attention_delta": 0, "text": "Dieser Verkauf wurde bereits verbucht."}
	var recognition_delta := 0
	var attention_delta := 0
	if disk.patch_state == "verified":
		recognition_delta = 1 if location_id != "schoolyard" else 2
	if location_id == "schoolyard":
		attention_delta = 2 + int(float(disk.release_data.get("quality", 50)) / 30.0)
		school_attention = clampi(school_attention + attention_delta, 0, 100)
	scene_recognition = clampi(scene_recognition + recognition_delta, 0, 100)
	sales.append({
		"disk_uid": sale_key, "serial": disk.release_serial, "location": location_id,
		"price": price, "date": _date_string(),
	})
	scene_changed.emit()
	return {
		"ok": true, "recognition_delta": recognition_delta,
		"attention_delta": attention_delta,
		"text": "Release weitergegeben: Ruf +%d, Aufmerksamkeit +%d." % [recognition_delta, attention_delta],
	}


# ------------------------------------------------------- Eigenes Spiel / Umsatz

func start_game_distribution(mode: String, initial_payout := 0) -> Dictionary:
	return OwnGameDistributionService.start(self, mode, initial_payout)


func reconcile_game_distribution() -> bool:
	return OwnGameDistributionService.reconcile(self)


func game_distribution_status() -> Dictionary:
	return OwnGameDistributionService.status(self)


func school_risk(disk: Disk = null) -> Dictionary:
	var chance := clampf(0.02 + float(school_attention) * 0.003, 0.02, 0.32)
	var level := "RUHIG"
	if school_attention >= 60:
		level = "AUFFÄLLIG"
	elif school_attention >= 25:
		level = "BEOBACHTET"
	var interrupted := false
	if disk != null:
		# Jeder Retry bekommt einen neuen, aber über Save/Load reproduzierbaren
		# Versuch. Eine Unterbrechung darf den Spieler weder in einer identischen
		# Endlosschleife festhalten noch durch Klick-Spam Aufmerksamkeit stapeln.
		var attempt_key := "%d/%s" % [_day_counter(), disk.uid]
		var attempt := int(school_attempts.get(attempt_key, 0))
		school_attempts[attempt_key] = attempt + 1
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("SCHOOL/%s/%d/%d" % [disk.uid, _day_counter(), attempt])
		interrupted = rng.randf() < chance
		if interrupted and not school_interruptions.has(attempt_key):
			school_interruptions[attempt_key] = true
			school_attention = clampi(school_attention + 1, 0, 100)
		scene_changed.emit()
	var message := "Alles ruhig auf dem Hof."
	if interrupted:
		message = "Eine Aufsicht kommt näher. Kein Verkauf; die Diskette bleibt bei dir."
	return {
		"interrupted": interrupted, "text": message,
		"chance": chance, "percent": roundi(chance * 100.0),
		"level": level, "attention": school_attention,
	}


func uploadable_releases(board_id: String) -> Array:
	return ReleaseUploadService.uploadable_releases(
		self, DiskManager.disks, board_id, _year())


func upload_release(disk: Disk, board_id: String) -> Dictionary:
	return ReleaseUploadService.upload(
		self, disk, DiskManager.disks, board_id, _year(), _date_string(),
		_refresh_cooperation_offers)


## Dynamische BBS-Beiträge aus dem eigenen Release-Verlauf. Alle sichtbaren
## Autoren sind gespeicherte Handles oder konfigurierte Gruppen-Handles.
func dynamic_posts(board_id: String) -> Array:
	return ReleaseFeedback.dynamic_posts(self, board_id)


## Reine Abfrage plus explizites Lesen: Feedback zählt erst, wenn der Spieler
## nach dem Upload tatsächlich den Nachrichtenbereich dieser Mailbox öffnet.
func unread_feedback_count(board_id: String) -> int:
	return ReleaseFeedback.unread_count(self, board_id)


func mark_feedback_read(board_id: String) -> int:
	return ReleaseFeedback.mark_read(self, board_id)


# --------------------------------------------------------------- Gruppen/Ruf

func _group_definition(group_id: String) -> Dictionary:
	for group: Dictionary in _config.get("groups", []):
		if str(group.get("id", "")) == group_id:
			return group
	return {}


func _group_active(group_id: String) -> bool:
	var group := _group_definition(group_id)
	return not group.is_empty() and _year() >= int(group.get("from", 1990)) and _year() <= int(group.get("to", 1999))


func _tier_for(reputation: int) -> Dictionary:
	var chosen: Dictionary = {"min": 0, "id": "unknown", "name": "UNBEKANNT"}
	for tier: Dictionary in _config.get("tiers", []):
		if reputation >= int(tier.get("min", 0)):
			chosen = tier
	return chosen


func group_status(group_id: String) -> Dictionary:
	var group := _group_definition(group_id)
	if group.is_empty():
		return {}
	var reputation := int(group_rep.get(group_id, 0))
	var tier := _tier_for(reputation)
	var next_threshold := -1
	for candidate: Dictionary in _config.get("tiers", []):
		if int(candidate.get("min", 0)) > reputation:
			next_threshold = int(candidate.get("min", 0))
			break
	var status := str(cooperation_status.get(group_id, "none"))
	return {
		"id": group_id, "name": str(group.get("name", group_id)),
		"reputation": reputation, "tier": str(tier.get("id", "unknown")),
		"tier_name": str(tier.get("name", "UNBEKANNT")),
		"next_threshold": next_threshold, "cooperation": status,
		"can_accept": status == "offered" and reputation >= 50,
		"active": _group_active(group_id),
	}


func all_group_status() -> Array:
	var result: Array = []
	for group: Dictionary in _config.get("groups", []):
		result.append(group_status(str(group.get("id", ""))))
	return result


func scene_status() -> Dictionary:
	return {
		"handle": scene_handle, "recognition": scene_recognition,
		"groups": all_group_status(), "offers": cooperation_offers.duplicate(true),
		"releases": releases.size(), "uploads": uploads.size(),
		"school_risk": school_risk(),
	}


func _refresh_cooperation_offers() -> void:
	for group: Dictionary in _config.get("groups", []):
		var id := str(group.get("id", ""))
		# 30–49 = anerkannter Gastbeitrag/Reaktionen. Ein sichtbares Co-Release
		# mit Gruppennamen wird erst ab Partnerstatus (50) angeboten.
		if not _group_active(id) or int(group_rep.get(id, 0)) < 50:
			continue
		var status := str(cooperation_status.get(id, "none"))
		if status != "none":
			continue
		cooperation_status[id] = "offered"
		cooperation_offers.append({
			"group_id": id, "group_name": str(group.get("name", id)),
			"from_handle": str(group.get("representative", "ANON")),
			"text": str(group.get("offer_text", "Kooperation angeboten.")),
			"status": "offered", "year": _year(),
		})


func accept_cooperation(group_id: String) -> Dictionary:
	var status := group_status(group_id)
	if status.is_empty():
		return {"ok": false, "text": "Unbekannte Szene-Gruppe.", "status": "none"}
	if str(cooperation_status.get(group_id, "none")) == "accepted":
		return {"ok": true, "text": "Kooperation besteht bereits.", "status": "accepted"}
	if str(cooperation_status.get(group_id, "none")) != "offered" or int(group_rep.get(group_id, 0)) < 50:
		return {"ok": false, "text": Loc.t("sys.scene_release_manager.noch_kein_verdientes_kooperationsangebot", "Noch kein verdientes Kooperationsangebot."), "status": str(cooperation_status.get(group_id, "none"))}
	cooperation_status[group_id] = "accepted"
	for i in cooperation_offers.size():
		if str((cooperation_offers[i] as Dictionary).get("group_id", "")) == group_id:
			cooperation_offers[i]["status"] = "accepted"
	scene_changed.emit()
	return {"ok": true, "text": "Kooperation mit %s angenommen." % status["name"], "status": "accepted"}


# --------------------------------------------------------------- Persistenz

func to_dict() -> Dictionary:
	return {
		"scene_handle": scene_handle,
		"releases": releases.duplicate(true), "uploads": uploads.duplicate(true),
		"scene_recognition": scene_recognition, "group_rep": group_rep.duplicate(true),
		"cooperation_offers": cooperation_offers.duplicate(true),
		"cooperation_status": cooperation_status.duplicate(true),
		"school_attention": school_attention,
		"school_attempts": school_attempts.duplicate(true),
		"school_interruptions": school_interruptions.duplicate(true),
		"alias_assignments": alias_assignments.duplicate(true),
		"sales": sales.duplicate(true), "release_counter": _release_counter,
		"game_distribution": game_distribution.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	var loaded_handle := normalize_handle(str(d.get("scene_handle", "")))
	scene_handle = loaded_handle if handle_valid(loaded_handle) else ""
	releases = (d.get("releases", {}) as Dictionary).duplicate(true)
	uploads = (d.get("uploads", []) as Array).duplicate(true)
	scene_recognition = clampi(int(d.get("scene_recognition", 0)), 0, 100)
	group_rep = (d.get("group_rep", {}) as Dictionary).duplicate(true)
	cooperation_status = (d.get("cooperation_status", {}) as Dictionary).duplicate(true)
	var raw_offers: Variant = d.get("cooperation_offers", [])
	cooperation_offers = (raw_offers as Array).duplicate(true) if raw_offers is Array else []
	school_attention = clampi(int(d.get("school_attention", 0)), 0, 100)
	school_attempts = (d.get("school_attempts", {}) as Dictionary).duplicate(true)
	school_interruptions = (d.get("school_interruptions", {}) as Dictionary).duplicate(true)
	alias_assignments = (d.get("alias_assignments", {}) as Dictionary).duplicate(true)
	sales = (d.get("sales", []) as Array).duplicate(true)
	var raw_distribution: Variant = d.get("game_distribution", {})
	game_distribution = (raw_distribution as Dictionary).duplicate(true) \
		if raw_distribution is Dictionary else {}
	_release_counter = maxi(0, int(d.get("release_counter", releases.size())))
	_ensure_group_state()
	_refresh_cooperation_offers()
	scene_changed.emit()


func _year() -> int:
	var manager := get_node_or_null("/root/TimeManager")
	return int(manager.get("year")) if manager != null else 1990


func _day_counter() -> int:
	var manager := get_node_or_null("/root/TimeManager")
	return int(manager.get("day_counter")) if manager != null else 0


func _date_string() -> String:
	var manager := get_node_or_null("/root/TimeManager")
	if manager != null and manager.has_method("date_string"):
		return str(manager.call("date_string"))
	return str(_year())
