extends Node
## DemoManager — persistenter Kern des Szene-Studios.
##
## Das alte Einzeleffekt-Formular bleibt als Save-/API-Migration erhalten. Neue
## Projekte durchlaufen dagegen Timeline, Modul-Linker, A500-Budgets, Testlauf
## und einen unveränderlichen Release-Snapshot. Drafts und Releases liegen in
## GameManager.flags und sind damit ohne zusätzlichen Save-Block versioniert.

signal demos_changed
signal draft_changed

const ProjectModelScript := preload("res://scripts/demos/demo_project_model.gd")
const RELEASE_ENERGY := 6
const RESPECT_DAILY_CAP := 12
const RESPECT_RANKS := [
	{"min": 0, "id": "bedroom", "name": "BEDROOM CODER", "unlock": "Drei-Part-Studio"},
	{"min": 10, "id": "local", "name": "LOCAL SIGNAL", "unlock": "Detailkritik und Asset-Bonus"},
	{"min": 25, "id": "regular", "name": "CLUB REGULAR", "unlock": "Kooperations-Credits"},
	{"min": 45, "id": "coder", "name": "SCENE CODER", "unlock": "BBS-Feature-Platzierung"},
	{"min": 70, "id": "elite", "name": "ELITE CREW", "unlock": "Elite-Distribution"},
	{"min": 90, "id": "legend", "name": "SCENE LEGEND", "unlock": "Legendärer Abspann"},
]

const EFFECTS := [
	{"id": "starfield", "name": "Sternenfeld", "cpu": 18, "chip_kb": 36, "blitter": 8, "colors": 8},
	{"id": "copperbars", "name": "Copper-Balken", "cpu": 12, "chip_kb": 20, "blitter": 4, "colors": 32},
	{"id": "plasma", "name": "Plasma", "cpu": 38, "chip_kb": 92, "blitter": 42, "colors": 32},
	{"id": "vectorgrid", "name": "Vektor-Netz", "cpu": 31, "chip_kb": 54, "blitter": 38, "colors": 16},
	{"id": "bobs", "name": "Bob-Feld", "cpu": 34, "chip_kb": 118, "blitter": 62, "colors": 16},
	{"id": "tunnel", "name": "Raster-Tunnel", "cpu": 43, "chip_kb": 86, "blitter": 48, "colors": 16},
	{"id": "shadebobs", "name": "Shadebobs", "cpu": 45, "chip_kb": 132, "blitter": 70, "colors": 16},
	{"id": "sine_scroller", "name": "Sinus-Scroller", "cpu": 21, "chip_kb": 44, "blitter": 26, "colors": 16},
	{"id": "rasterbars", "name": "Raster-Balken", "cpu": 10, "chip_kb": 10, "blitter": 0, "colors": 32},
	{"id": "rotozoomer", "name": "Rotozoomer", "cpu": 66, "chip_kb": 128, "blitter": 58, "colors": 16},
	{"id": "line_twister", "name": "Line-Twister", "cpu": 42, "chip_kb": 64, "blitter": 30, "colors": 16},
	{"id": "moire_rings", "name": "Moiré-Ringe", "cpu": 34, "chip_kb": 42, "blitter": 4, "colors": 8},
]

const MODULES := [
	{"id": "boot_init", "name": "BOOT / INIT", "cost": "6 KB", "description": "Startvektor und Hardware-Initialisierung."},
	{"id": "memory_map", "name": "MEMORY MAP", "cost": "4 KB", "description": "Reserviert Chip-RAM ohne Überschneidungen."},
	{"id": "vblank_irq", "name": "VBLANK IRQ", "cost": "8 KB", "description": "Stabiler PAL-50-Hz-Takt."},
	{"id": "part_loader", "name": "PART LOADER", "cost": "18 KB", "description": "Wechselt Timeline-Parts und Übergänge."},
	{"id": "music_irq", "name": "MUSIC IRQ", "cost": "24 KB", "description": "Vierkanal-MOD und Beat-Marker."},
	{"id": "copperlist", "name": "COPPERLIST", "cost": "12 KB", "description": "Rastergenaue Farb- und Displaywechsel."},
	{"id": "blitter", "name": "BLITTER KERNEL", "cost": "22 KB", "description": "Hardware-Blits für Bobs, Plasma und Netze."},
	{"id": "scroller", "name": "SCROLLER", "cost": "16 KB", "description": "Glyphen, Sine-Tabelle und Textpuffer."},
	{"id": "sprite_mux", "name": "SPRITE MUX", "cost": "14 KB", "description": "Mehr Objekte aus acht Hardware-Sprites."},
	{"id": "double_buffer", "name": "DOUBLE BUFFER", "cost": "80 KB", "description": "Ruhiges Bild gegen höheren Chip-RAM-Verbrauch."},
	{"id": "precalc_tables", "name": "PRECALC TABLES", "cost": "48 KB", "description": "CPU sparen, Tabellen im RAM halten."},
	{"id": "delta_pack", "name": "DELTA PACKER", "cost": "10 KB", "description": "Grafikdaten packen; kleine CPU-Kosten beim Laden."},
]

const PALETTES := [
	{"id": "night_copper", "name": "Nachtkupfer"},
	{"id": "violet_ice", "name": "Violett-Eis"},
	{"id": "acid_sunset", "name": "Acid-Sunset"},
	{"id": "steel_blue", "name": "Stahlblau"},
	{"id": "red_signal", "name": "Rotsignal"},
]

const TRANSITIONS := [
	{"id": "cut", "name": "Hard Cut"},
	{"id": "fade", "name": "Palette Fade"},
	{"id": "wipe", "name": "Raster Wipe"},
	{"id": "checker", "name": "Checker Dissolve"},
	{"id": "curtain", "name": "Split Curtain"},
	{"id": "flash", "name": "White Flash"},
]

var _model: RefCounted
var _bbs_boards_cache: Array = []


func _ready() -> void:
	_model = ProjectModelScript.new()


func _project_model() -> RefCounted:
	if _model == null:
		_model = ProjectModelScript.new()
	return _model


# ---------------------------------------------------------------- Kataloge

func catalog(kind: String) -> Array:
	match kind:
		"effects": return EFFECTS.duplicate(true)
		"modules": return MODULES.duplicate(true)
		"palettes": return PALETTES.duplicate(true)
		"transitions": return TRANSITIONS.duplicate(true)
		_: return []


## Boarddefinitionen einmal lesen; Demo-Credits fragen sie bei jedem Build ab.
func _bbs_board_defs() -> Array:
	if _bbs_boards_cache.is_empty() and FileAccess.file_exists("res://data/bbs_boards.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/bbs_boards.json"))
		if parsed is Dictionary:
			_bbs_boards_cache = (parsed as Dictionary).get("boards", [])
	return _bbs_boards_cache


func active_bbs_names() -> Array[String]:
	var names: Array[String] = []
	var year := int(TimeManager.year)
	for board: Dictionary in _bbs_board_defs():
		if year >= int(board.get("year_from", 1990)) and year <= int(board.get("year_to", 1999)):
			names.append(str(board.get("name", "BBS")).to_upper())
	return names


func available_credits() -> Array:
	var scene := get_node_or_null("/root/SceneReleaseManager")
	if scene != null and scene.has_method("credit_candidates"):
		var candidates: Variant = scene.call("credit_candidates")
		if candidates is Array:
			return (candidates as Array).duplicate(true)
	return []


func accepted_groups() -> Array:
	var result: Array = []
	var scene := get_node_or_null("/root/SceneReleaseManager")
	if scene == null or not scene.has_method("all_group_status"):
		return result
	for status: Dictionary in scene.call("all_group_status"):
		if bool(status.get("active", false)) and str(status.get("cooperation", "none")) == "accepted":
			result.append(status.duplicate(true))
	return result


# --------------------------------------------------------------- Projekte

func create_project(project_seed := -1, project_kind := "demo") -> Dictionary:
	var chosen_seed := int(project_seed)
	if chosen_seed < 0:
		chosen_seed = 90210 + int(TimeManager.day_counter) * 97 + count() * 701
	var project: Dictionary = _project_model().call("default_project", chosen_seed)
	var handle := _preferred_handle()
	project["group"] = handle
	project["author"] = handle
	project["title"] = "SIGNAL %02d" % (count() + 1)
	project["palette"] = "night_copper"
	project["track_id"] = ""
	project["soundtrack"] = ""
	_attach_creator_assets(project)
	var boards := active_bbs_names()
	var bbs_line := " · ".join(boards.slice(0, 3)) if not boards.is_empty() else "ALL LOCAL BOARDS"
	project["scroller"] = "WELCOME TO A FRESH RELEASE ... GREETINGS TO %s ... KEEP THE SIGNAL ALIVE ..." % bbs_line
	project["credits"] = "CODE: %s" % handle
	project["credit_entries"] = [{"actor_id": "player", "handle_snapshot": handle, "handle": handle, "role": "CODE"}]
	var parts: Array = project.get("parts", [])
	for i in parts.size():
		var part: Dictionary = parts[i]
		if i == parts.size() - 1:
			part["scrolltext"] = str(project["scroller"])
		parts[i] = part
	project["parts"] = parts
	_apply_kind_blueprint(project, project_kind)
	return _with_ui_fields(_project_model().call("sanitize_project", project), project)


func create_part(index: int, effect := "starfield") -> Dictionary:
	var raw := {
		"id": "part_%02d" % (index + 1), "name": "PART %02d" % (index + 1),
		"title": "PART %02d" % (index + 1), "duration": 8.0,
		"effect": effect, "effects": [effect], "layers": [effect],
		"transition": "fade", "palette": PALETTES[index % PALETTES.size()]["id"],
		"scrolltext": "", "intensity": 1.0, "sync": true, "optimizations": [],
	}
	return _project_model().call("sanitize_part", raw, index)


func save_draft(project: Dictionary) -> Dictionary:
	var clean: Dictionary = _with_ui_fields(_project_model().call("sanitize_project", project), project)
	var kind := str(clean.get("project_kind", "demo"))
	var drafts: Dictionary = GameManager.flags.get("demo_drafts", {}).duplicate(true)
	drafts[kind] = clean.duplicate(true)
	GameManager.flags["demo_drafts"] = drafts
	GameManager.flags["demo_active_kind"] = kind
	# Legacy-Zeiger bleibt fuer alte Saves, Tests und externe Adapter erhalten.
	GameManager.flags["demo_draft"] = clean.duplicate(true)
	draft_changed.emit()
	return clean


func load_draft(project_kind := "") -> Dictionary:
	var requested := str(project_kind)
	if requested != "":
		var drafts: Variant = GameManager.flags.get("demo_drafts", {})
		if drafts is Dictionary:
			var saved: Variant = drafts.get(requested, {})
			if saved is Dictionary and not saved.is_empty():
				return _with_ui_fields(_project_model().call("sanitize_project", saved), saved)
	var raw: Variant = GameManager.flags.get("demo_draft", {})
	if not raw is Dictionary or raw.is_empty():
		return {}
	if requested != "" and str(raw.get("project_kind", "demo")) != requested:
		return {}
	return _with_ui_fields(_project_model().call("sanitize_project", raw), raw)


func clear_draft(project_kind := "") -> void:
	var requested := str(project_kind)
	if requested == "":
		GameManager.flags.erase("demo_drafts")
		GameManager.flags.erase("demo_draft")
		GameManager.flags.erase("demo_active_kind")
	else:
		_clear_kind_draft(requested)
	draft_changed.emit()


func _clear_kind_draft(kind: String) -> void:
	var drafts: Dictionary = GameManager.flags.get("demo_drafts", {}).duplicate(true)
	drafts.erase(kind)
	if drafts.is_empty():
		GameManager.flags.erase("demo_drafts")
	else:
		GameManager.flags["demo_drafts"] = drafts
	var legacy: Variant = GameManager.flags.get("demo_draft", {})
	if legacy is Dictionary and str(legacy.get("project_kind", "demo")) == kind:
		GameManager.flags.erase("demo_draft")
	if str(GameManager.flags.get("demo_active_kind", "")) == kind:
		GameManager.flags.erase("demo_active_kind")


## Drei echte Produktionsvorlagen statt eines Projekts mit drei Etiketten.
## Gemeinsame Technik bleibt kompatibel, Dramaturgie und Regeln sind getrennt.
func _apply_kind_blueprint(project: Dictionary, requested_kind: String) -> void:
	var kind := requested_kind if requested_kind in ["demo", "club_intro", "game"] else "demo"
	project["project_kind"] = kind
	match kind:
		"club_intro":
			project["title"] = "CLUB SIGNAL %02d" % (count() + 1)
			project["intro_purpose"] = "group_id"
			project["player_role"] = "code"
			project["scroller"] = "PRESENTED BY %s ... GREETINGS TO THE LOCAL SCENE ..." % str(project.get("group", "CREW"))
			project["parts"] = [
				_blueprint_part(0, "CREW IDENT", "copperbars", "sine_scroller", 8.0, "cut", "acid_sunset", ""),
				_blueprint_part(1, "GREETINGS", "starfield", "sine_scroller", 10.0, "fade", "violet_ice", str(project["scroller"])),
			]
		"game":
			project["title"] = "PIXEL PROTOTYPE %02d" % (count() + 1)
			project["game_mode"] = "collector"
			project["game_difficulty"] = "normal"
			project["game_lives"] = 3
			project["game_objectives"] = 3
			project["parts"] = [
				_blueprint_part(0, "TITLE SCREEN", "starfield", "copperbars", 6.0, "cut", "night_copper", "PRESS FIRE TO START"),
				_blueprint_part(1, "LEVEL LOOP", "bobs", "vectorgrid", 12.0, "wipe", "steel_blue", ""),
				_blueprint_part(2, "SCORE & EXIT", "copperbars", "sine_scroller", 7.0, "fade", "acid_sunset", "MISSION COMPLETE"),
			]
			var modules: Array = project.get("modules", [])
			if not modules.has("sprite_mux"):
				modules.append("sprite_mux")
			project["modules"] = modules
		_:
			project["demo_format"] = "trackmo"


func _blueprint_part(index: int, part_name: String, primary: String, secondary: String,
		duration: float, transition: String, palette: String, scrolltext: String) -> Dictionary:
	var part := create_part(index, primary)
	part["name"] = part_name
	part["title"] = part_name
	part["duration"] = duration
	part["effects"] = [primary, secondary]
	part["layers"] = [secondary]
	part["transition"] = transition
	part["palette"] = palette
	part["scrolltext"] = scrolltext
	return _project_model().call("sanitize_part", part, index)


func compile_project(project: Dictionary) -> Dictionary:
	var clean := _with_ui_fields(_project_model().call("sanitize_project", project), project)
	var report: Dictionary = _project_model().call("compile_report", clean)
	var quality_data: Dictionary = _project_model().call("quality_report", clean, report)
	_merge_quality(report, quality_data)
	_apply_creator_bonus(report, clean)
	return report


## Eigene Musik, Grafik und Tools aus den drei Creator-Programmen. Die Daten
## werden als kleine immutable Snapshots ins Projekt uebernommen; ein spaeteres
## Ueberschreiben der Leinwand oder des Patterns veraendert den Build nicht.
func creator_library() -> Dictionary:
	return {
		"music": (MinigameManager.creations.get("tracker", []) as Array).duplicate(true),
		"art": (MinigameManager.creations.get("paint", []) as Array).duplicate(true),
		"tools": (MinigameManager.creations.get("listing", []) as Array).duplicate(true),
	}


func scene_respect() -> int:
	return clampi(int(GameManager.flags.get("demo_scene_respect", 0)), 0, 100)


func scene_rank() -> Dictionary:
	var rank: Dictionary = RESPECT_RANKS[0].duplicate(true)
	for candidate: Dictionary in RESPECT_RANKS:
		if scene_respect() >= int(candidate["min"]): rank = candidate.duplicate(true)
	return rank


func progression() -> Dictionary:
	var current := scene_rank()
	var next: Dictionary = {}
	for candidate: Dictionary in RESPECT_RANKS:
		if int(candidate["min"]) > scene_respect():
			next = candidate.duplicate(true)
			break
	return {"respect": scene_respect(), "rank": current, "next": next,
		"unlocks": RESPECT_RANKS.filter(func(r: Dictionary) -> bool: return int(r["min"]) <= scene_respect())}


func auto_optimize(project: Dictionary) -> Dictionary:
	var clean := _with_ui_fields(_project_model().call("sanitize_project", project), project)
	var optimized: Dictionary = _project_model().call("optimize_project", clean, "balanced")
	optimized["assisted"] = true
	optimized["track_id"] = str(project.get("track_id", ""))
	return _with_ui_fields(_project_model().call("sanitize_project", optimized), optimized)


func part_metrics(project: Dictionary, index: int) -> Dictionary:
	var report := compile_project(project)
	var part_reports: Array = report.get("parts", [])
	if index >= 0 and index < part_reports.size() and part_reports[index] is Dictionary:
		var value: Dictionary = part_reports[index]
		return {
			"cpu": int(value.get("cpu_pct", value.get("cpu", value.get("cpu_percent", 0)))),
			"chip_kb": int(value.get("chip_kb", value.get("memory_kb", 0))),
			"blitter": int(value.get("blitter_pct", value.get("blitter", value.get("blitter_percent", 0)))),
			"colors": int(value.get("colors", 0)),
			"over_budget": bool(value.get("over_budget", false)) or not value.get("errors", []).is_empty(),
		}
	# Toleranter Fallback für ältere Model-Saves.
	var parts: Array = project.get("parts", [])
	if index < 0 or index >= parts.size():
		return {}
	var part: Dictionary = parts[index]
	var cpu := 8
	var chip := 28
	var blitter := 3
	var colors := 4
	for layer in part.get("layers", [part.get("effect", "starfield")]):
		var effect_id := str(layer.get("effect", "")) if layer is Dictionary else str(layer)
		for definition: Dictionary in EFFECTS:
			if str(definition["id"]) == effect_id:
				cpu += int(definition["cpu"])
				chip += int(definition["chip_kb"])
				blitter += int(definition["blitter"])
				colors = maxi(colors, int(definition["colors"]))
	return {"cpu": cpu, "chip_kb": chip, "blitter": blitter, "colors": colors,
		"over_budget": cpu > 100 or chip > 512 or blitter > 100 or colors > 32}


func test_build(project: Dictionary, report: Dictionary = {}) -> Dictionary:
	var build := report if not report.is_empty() else compile_project(project)
	var metrics: Dictionary = build.get("metrics", {})
	var errors: Array = build.get("errors", [])
	var checks: Array = [
		{"id": "link", "label": "LINKER · alle Module und Abhängigkeiten aufgelöst", "ok": errors.is_empty()},
		{"id": "boot", "label": "BOOT · Init-Vektor erreicht den ersten Part", "ok": project.get("modules", []).has("boot_init")},
		{"id": "memory", "label": "CHIP RAM · Peak bleibt innerhalb 512 KB", "ok": float(metrics.get("peak_chip_kb", metrics.get("chip_kb", 999))) <= 512.0},
		{"id": "pal", "label": "PAL 50 HZ · CPU-Peak bleibt im Frame-Budget", "ok": float(metrics.get("peak_cpu_pct", metrics.get("peak_cpu", 999))) <= 100.0},
		{"id": "blitter", "label": "BLITTER · keine Rasterzeile wird überzogen", "ok": float(metrics.get("peak_blitter_pct", metrics.get("peak_blitter", 999))) <= 100.0},
		{"id": "timeline", "label": "TIMELINE · jeder Part ist 4–30 Sekunden lang", "ok": _timeline_valid(project)},
		{"id": "sync", "label": "MUSIC IRQ · Beat-Marker und VBlank laufen deterministisch", "ok": _sync_valid(project)},
		{"id": "credits", "label": "CREDITS · sichtbare Namen sind Szene-Handles", "ok": _credits_safe(project)},
	]
	var kind := str(project.get("project_kind", "demo"))
	if kind == "club_intro":
		var club_contract := club_project_contract(project)
		checks.append({"id": "club_role", "label": "CLUB · Rolle gewählt und eigener Beitrag vorhanden",
			"ok": bool(club_contract.get("ok", false)), "reason": str(club_contract.get("reason", ""))})
		checks.append({"id": "club_credits", "label": "CLUB · mindestens ein Freund steht in den Credits",
			"ok": bool(club_contract.get("has_friend_credit", false))})
	elif kind == "game":
		var gameplay: Dictionary = project.get("gameplay_test", {})
		var expected_hash := str(build.get("hash", build.get("build_id", "")))
		# Migration alter Spieltest-Stempel: Vor Schema 5 gab es nur mode/hash.
		# Sie bleiben fuer exakt das damalige Default-Regelset gueltig.
		var rules_match := false
		if gameplay.has("difficulty"):
			rules_match = str(gameplay.get("mode", "")) == str(project.get("game_mode", "collector")) \
				and str(gameplay.get("difficulty", "")) == str(project.get("game_difficulty", "normal")) \
				and int(gameplay.get("objectives", 0)) == int(project.get("game_objectives", 3)) \
				and int(gameplay.get("starting_lives", 0)) == int(project.get("game_lives", 3))
		else:
			rules_match = str(project.get("game_mode", "collector")) == str(gameplay.get("mode", "collector")) \
				and str(project.get("game_difficulty", "normal")) == "normal" \
				and int(project.get("game_objectives", 3)) == 3 \
				and int(project.get("game_lives", 3)) == 3
		checks.append({"id": "gameplay", "label": "SPIELTEST · Regeln selbst gespielt und Ziel erreicht",
			"ok": bool(gameplay.get("passed", false))
				and str(gameplay.get("build_hash", "")) == expected_hash
				and rules_match})
	var ok := true
	for check: Dictionary in checks:
		ok = ok and bool(check["ok"])
	return {"ok": ok, "checks": checks, "build_hash": str(build.get("hash", "")),
		"failed": checks.filter(func(check: Dictionary) -> bool: return not bool(check.get("ok", false))).size()}


## Vertrag des 1991er Gruppenintros. Das Studio prüft damit nicht nur einen
## Release-Typ, sondern eine gewählte Rolle, einen echten eigenen Beitrag und
## mindestens einen gespeicherten Handle-Snapshot eines Freundes.
func club_project_contract(project: Dictionary) -> Dictionary:
	var role := str(project.get("player_role", ""))
	var valid_roles := ["code", "pixel", "music", "testing", "organization"]
	var friend_credits := 0
	for entry: Variant in project.get("credit_entries", []):
		if entry is Dictionary and str(entry.get("actor_id", "")) not in ["", "player", "self"]:
			friend_credits += 1
	var contribution := false
	match role:
		"code": contribution = not (MinigameManager.creations.get("listing", []) as Array).is_empty()
		"pixel": contribution = not (MinigameManager.creations.get("paint", []) as Array).is_empty()
		"music": contribution = not (MinigameManager.creations.get("tracker", []) as Array).is_empty()
		"testing": contribution = true  # Der grüne QA-Lauf IST der Rollenbeitrag.
		"organization": contribution = friend_credits >= 2
	var reason := ""
	if role not in valid_roles:
		reason = "Wähle deine Rolle im Club-Projekt."
	elif not contribution:
		reason = "Für diese Rolle fehlt noch ein eigener Beitrag."
	elif friend_credits < 1:
		reason = "Nimm mindestens einen Freund mit Handle in die Credits auf."
	return {"ok": role in valid_roles and contribution and friend_credits >= 1,
		"role": role, "has_contribution": contribution,
		"has_friend_credit": friend_credits >= 1, "friend_credits": friend_credits,
		"reason": reason}


# --------------------------------------------------------------- Releases

func demos() -> Array:
	var value: Variant = GameManager.flags.get("demos", [])
	return value if value is Array else []


func count() -> int:
	return demos().size()


## Rückwärtskompatible 1..5-Wertung. Neue Projekte werden aus 0..100 abgeleitet.
func quality(data: Dictionary) -> int:
	if data.has("parts"):
		var report := compile_project(data)
		return clampi(ceili(float(report.get("score", 0)) / 20.0), 1, 5)
	var q := 1
	var scroller := str(data.get("scroller", "")).to_lower()
	if scroller.length() >= 30: q += 1
	if scroller.length() >= 80: q += 1
	# Der Scrolltext stammt vom Spieler. Die Wortliste deckt daher Deutsch UND
	# Englisch ab; die Pfeilformen sind ohnehin sprachunabhaengig. Bei weiteren
	# Sprachen gehoert hier je Sprache ein Gruss-Wort ergaenzt — die Bewertung
	# darf nicht davon abhaengen, in welcher Sprache jemand seine Demo schreibt.
	if "gruss" in scroller or "grüß" in scroller or "greet" in scroller \
			or "salut" in scroller or "saludos" in scroller or "->" in scroller \
			or "→" in scroller: q += 1
	if str(data.get("effect", "")) in ["copper", "copperbars", "plasma"]: q += 1
	return clampi(q, 1, 5)


func reception(value: int) -> String:
	var score := value * 20 if value <= 5 else value
	if score >= 90:
		return "Die Nightline explodiert: Sysops spiegeln den Release, andere Gruppen fragen nach einem Co-Part."
	if score >= 75:
		return "Starker Release — die Szene diskutiert Timing, Look und sauberen 50-Hz-Lauf auf mehreren Boards."
	if score >= 55:
		return "Solide Arbeit. Einige Sysops nehmen die Demo ins File-Area auf; das nächste Projekt wird beobachtet."
	return "Ein ehrlicher erster Build. Die Boards nennen konkrete Bugs — zurück ins Studio, nicht aufgeben."


## Release eines neuen Projekts oder Migration eines alten Flat-Datensatzes.
func release(data: Dictionary, supplied_report: Dictionary = {}) -> Dictionary:
	if not data.has("parts"):
		return _release_legacy(data)
	var project := _with_ui_fields(_project_model().call("sanitize_project", data), data)
	var report := supplied_report if not supplied_report.is_empty() else compile_project(project)
	var qa := test_build(project, report)
	if not bool(qa.get("ok", false)):
		return {"ok": false, "reason": Loc.t("sys.demo_manager.release_kandidat_besteht_den_testlauf_noch", "Der Release-Kandidat besteht den Testlauf noch nicht."),
			"errors": report.get("errors", []), "qa": qa}
	var score := int(report.get("score", 0))
	var grade := str(report.get("grade", _grade(score)))
	var q := clampi(ceili(float(score) / 20.0), 1, 5)
	var first := count() == 0
	var handle := _release_handle(project)
	if handle == "":
		return {"ok": false, "reason": Loc.t("sys.demo_manager.handle_ungultig_3_16_zeichen_nur", "Handle ungültig: 3–16 Zeichen, nur A–Z, 0–9, _ oder -.")}
	project["group"] = handle
	project["author"] = handle
	var blank := _release_blank_candidate()
	if blank == null:
		return {"ok": false, "reason": Loc.t("sys.demo_manager.keine_leere_dd_diskette_fuer_den", "Keine leere DD-Diskette fuer den Release in der Box.")}
	if PlayerStats.energie < RELEASE_ENERGY:
		return {"ok": false, "reason": Loc.t("sys.demo_manager.zu_muede_fuer_build_verify_disk", "Zu muede fuer Build, Verify und Disk-Freeze (%d Energie noetig).") % RELEASE_ENERGY}
	var list := demos()
	var kind := str(project.get("project_kind", "demo"))
	var serial_prefix := "GAME" if kind == "game" else ("INTRO" if kind == "club_intro" else "DEMO")
	var serial := "%s-%d-%04d" % [serial_prefix, int(TimeManager.year), list.size() + 1]
	var presenting := _accepted_presenting(str(data.get("presenting", "")), handle)
	var release_snapshot := {
		"release_id": serial, "title": str(project.get("title", "DEMO")),
		"project_kind": str(project.get("project_kind", "demo")),
		"group": presenting, "author_handle": handle,
		"credits": _safe_credit_snapshots(data.get("credit_entries", project.get("credit_entries", [])), handle),
		"scroller": str(project.get("scroller", "")), "palette": str(project.get("palette", "night_copper")),
		"track": str(data.get("track_title_snapshot", project.get("soundtrack", project.get("track", "")))),
		"track_id": str(data.get("track_id", "")), "bpm": int(project.get("bpm", 125)),
		"parts": project.get("parts", []).duplicate(true), "modules": project.get("modules", []).duplicate(),
		"quality": q, "score": score, "grade": grade,
		"build_hash": str(report.get("hash", report.get("build_id", ""))),
		"date": TimeManager.date_string(), "year": int(TimeManager.year),
		"presenting": presenting,
		"bbs_greetings": active_bbs_names().slice(0, 3), "assisted": bool(data.get("assisted", false)),
		"creator_assets": project.get("creator_assets", {}).duplicate(true),
		"player_role": str(project.get("player_role", "")),
		"demo_format": str(project.get("demo_format", "trackmo")),
		"intro_purpose": str(project.get("intro_purpose", "group_id")),
		"game_mode": str(project.get("game_mode", "collector")),
		"game_difficulty": str(project.get("game_difficulty", "normal")),
		"game_lives": int(project.get("game_lives", 3)),
		"game_objectives": int(project.get("game_objectives", 3)),
		"gameplay_test": (project.get("gameplay_test", {}) as Dictionary).duplicate(true),
	}
	if not PlayerStats.use_energy(RELEASE_ENERGY):
		return {"ok": false, "reason": "Energie hat sich vor dem Freeze veraendert."}
	_write_release_disk(blank, release_snapshot)
	release_snapshot["disk_uid"] = blank.uid
	list.append(release_snapshot)
	GameManager.flags["demos"] = list
	_clear_kind_draft(kind)
	var gain := _grant_daily_reputation(q)
	var respect_gain := _grant_scene_respect(release_snapshot)
	_note_release(release_snapshot)
	_note_quest_release(release_snapshot)
	demos_changed.emit()
	return {"ok": true, "quality": q, "score": score, "grade": grade, "ruf": gain,
		"respect": respect_gain, "scene_respect": scene_respect(), "rank": scene_rank(),
		"disk_uid": blank.uid,
		"reception": reception(score), "first": first, "release": release_snapshot.duplicate(true)}


func _release_legacy(data: Dictionary) -> Dictionary:
	var q := quality(data)
	var first := count() == 0
	var release_snapshot := {
		"release_id": "LEGACY-%d-%04d" % [int(TimeManager.year), count() + 1],
		"project_kind": "demo",
		"title": str(data.get("title", "MEGADEMO")), "group": str(data.get("group", "LONE CODER")),
		"scroller": str(data.get("scroller", "")), "effect": str(data.get("effect", "stars")),
		"track": str(data.get("track", "")), "quality": q, "score": q * 20,
		"grade": _grade(q * 20), "date": TimeManager.date_string(), "year": int(TimeManager.year),
	}
	var list := demos()
	list.append(release_snapshot)
	GameManager.flags["demos"] = list
	var gain := _grant_daily_reputation(q)
	_note_release(release_snapshot)
	_note_quest_release(release_snapshot)
	demos_changed.emit()
	return {"ok": true, "quality": q, "score": q * 20, "grade": release_snapshot["grade"],
		"ruf": gain, "reception": reception(q), "first": first}


func reset() -> void:
	demos_changed.emit()
	draft_changed.emit()


# ---------------------------------------------------------------- Interna

func _with_ui_fields(clean: Dictionary, source: Dictionary) -> Dictionary:
	clean["track_id"] = str(source.get("track_id", clean.get("track_id", "")))
	clean["track"] = str(source.get("track", clean.get("track", "")))
	clean["track_title_snapshot"] = str(source.get("track_title_snapshot", clean.get("soundtrack", "")))
	var raw_credits: Variant = source.get("credit_entries", [])
	clean["credit_entries"] = (raw_credits as Array).duplicate(true) if raw_credits is Array else []
	clean["presenting"] = str(source.get("presenting", ""))
	clean["assisted"] = bool(source.get("assisted", clean.get("assisted", false)))
	clean["creator_assets"] = (source.get("creator_assets", {}) as Dictionary).duplicate(true)
	clean["player_role"] = str(source.get("player_role", "code"))
	clean["demo_format"] = str(source.get("demo_format", clean.get("demo_format", "trackmo")))
	clean["intro_purpose"] = str(source.get("intro_purpose", clean.get("intro_purpose", "group_id")))
	clean["game_mode"] = str(source.get("game_mode", "collector"))
	clean["game_difficulty"] = str(source.get("game_difficulty", clean.get("game_difficulty", "normal")))
	clean["game_lives"] = int(source.get("game_lives", clean.get("game_lives", 3)))
	clean["game_objectives"] = int(source.get("game_objectives", clean.get("game_objectives", 3)))
	clean["gameplay_test"] = (source.get("gameplay_test", {}) as Dictionary).duplicate(true)
	return clean


func _attach_creator_assets(project: Dictionary) -> void:
	var library := creator_library()
	var assets: Dictionary = {}
	for pair in [["music", "music"], ["art", "art"], ["tools", "tool"]]:
		var list: Array = library.get(pair[0], [])
		if not list.is_empty(): assets[pair[1]] = (list[0] as Dictionary).duplicate(true)
	project["creator_assets"] = assets
	if assets.has("music"):
		var music: Dictionary = assets["music"]
		project["track_id"] = "creation:tracker:%s" % str(music.get("id", "pattern"))
		project["track"] = str(music.get("title", "EIGENES PATTERN"))
		project["track_title_snapshot"] = project["track"]
		project["soundtrack"] = project["track"]
		project["bpm"] = int(music.get("bpm", 125))


func _apply_creator_bonus(report: Dictionary, project: Dictionary) -> void:
	if not report.get("errors", []).is_empty(): return
	var assets: Dictionary = project.get("creator_assets", {})
	var bonus := mini(12, assets.size() * 4)
	if bonus <= 0: return
	report["creator_bonus"] = bonus
	report["score"] = mini(100, int(report.get("score", 0)) + bonus)
	report["grade"] = _grade(int(report["score"]))
	var categories: Dictionary = report.get("categories", {}).duplicate(true)
	categories["originality"] = mini(100, int(categories.get("originality", 0)) + bonus * 2)
	report["categories"] = categories
	report["creator_assets"] = assets.keys()


func _merge_quality(report: Dictionary, quality_report: Dictionary) -> void:
	var score := int(quality_report.get("score", quality_report.get("total", report.get("score", 0))))
	report["score"] = clampi(score, 0, 100)
	report["grade"] = str(quality_report.get("grade", _grade(score)))
	var categories: Dictionary = quality_report.get("categories", {})
	var components: Dictionary = quality_report.get("components", {})
	if categories.is_empty() and not components.is_empty():
		categories = {
			"craft": clampi(int(round(float(components.get("craft", 0.0)) / 12.0 * 100.0)), 0, 100),
			"performance": clampi(int(round(float(components.get("technical", 0.0)) / 30.0 * 100.0)), 0, 100),
			"sync": clampi(int(round(float(components.get("sync", 0.0)) / 15.0 * 100.0)), 0, 100),
			"originality": clampi(int(round((float(components.get("creative", 0.0)) + float(components.get("scene", 0.0))) / 43.0 * 100.0)), 0, 100),
		}
	if categories.is_empty():
		categories = {
			"craft": int(quality_report.get("craft", score)),
			"performance": int(quality_report.get("performance", score)),
			"sync": int(quality_report.get("sync", score)),
			"originality": int(quality_report.get("originality", score)),
		}
	report["categories"] = categories
	report["build_id"] = str(report.get("hash", "LOCAL")).left(10).to_upper()


func _grade(score: int) -> String:
	if score >= 92: return "S"
	if score >= 82: return "A"
	if score >= 70: return "B"
	if score >= 55: return "C"
	if score >= 40: return "D"
	return "E"


func _preferred_handle() -> String:
	var scene := get_node_or_null("/root/SceneReleaseManager")
	if scene != null:
		var current := str(scene.get("scene_handle"))
		if scene.has_method("handle_valid") and bool(scene.call("handle_valid", current)):
			return current
		if scene.has_method("handle_suggestions"):
			var suggestions: Variant = scene.call("handle_suggestions", "DEMO-STUDIO")
			if suggestions is Array and not suggestions.is_empty():
				return str(suggestions[0])
	return "LONE-CODER"


func _release_handle(project: Dictionary) -> String:
	var candidate := str(project.get("group", project.get("author", ""))).strip_edges().to_upper()
	var scene := get_node_or_null("/root/SceneReleaseManager")
	if scene == null:
		return candidate if _simple_handle_valid(candidate) else ""
	if scene.has_method("handle_valid") and not bool(scene.call("handle_valid", candidate)):
		return ""
	var current := str(scene.get("scene_handle"))
	if current == "" and scene.has_method("set_scene_handle"):
		var set_result: Dictionary = scene.call("set_scene_handle", candidate)
		if not bool(set_result.get("ok", false)):
			return ""
		current = str(set_result.get("handle", candidate))
	# Hat BYTEWERK das Handle bereits festgeschrieben, darf ein Demo-Release nicht
	# unter einem Klar- oder Fremdnamen daran vorbeischreiben.
	return current if current == candidate else ""


func _simple_handle_valid(candidate: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Z0-9][A-Z0-9_-]{2,15}$")
	return regex.search(candidate) != null


func _safe_credit_snapshots(raw: Variant, author: String) -> Array:
	var result: Array = [{"actor_id": "player", "handle_snapshot": author, "handle": author, "role": "CODE"}]
	if not raw is Array:
		return result
	for entry in raw:
		if not entry is Dictionary:
			continue
		var handle := str(entry.get("handle_snapshot", entry.get("handle", ""))).strip_edges().to_upper()
		if not _simple_handle_valid(handle) or handle == author:
			continue
		result.append({"actor_id": str(entry.get("actor_id", "guest")), "handle_snapshot": handle,
			"handle": handle, "role": str(entry.get("role", "CREW")).to_upper().left(18)})
		if result.size() >= 4:
			break
	return result


func _accepted_presenting(requested: String, fallback: String) -> String:
	for group: Dictionary in accepted_groups():
		if str(group.get("name", "")) == requested or str(group.get("id", "")) == requested:
			return str(group.get("name", fallback))
	return fallback


func _timeline_valid(project: Dictionary) -> bool:
	var parts: Array = project.get("parts", [])
	if parts.is_empty() or parts.size() > 8:
		return false
	for part: Dictionary in parts:
		var duration := float(part.get("duration", 0.0))
		if duration < 4.0 or duration > 30.0:
			return false
	return true


func _sync_valid(project: Dictionary) -> bool:
	var needs_music_irq := false
	for part: Dictionary in project.get("parts", []):
		needs_music_irq = needs_music_irq or bool(part.get("sync", false))
	return not needs_music_irq or project.get("modules", []).has("music_irq")


func _credits_safe(project: Dictionary) -> bool:
	var credits: Variant = project.get("credit_entries", [])
	if not credits is Array:
		return _simple_handle_valid(str(project.get("group", "")).to_upper())
	for entry in credits:
		if entry is Dictionary:
			var handle := str(entry.get("handle_snapshot", entry.get("handle", ""))).to_upper()
			if handle != "" and not _simple_handle_valid(handle):
				return false
	return _simple_handle_valid(str(project.get("group", "")).to_upper())


func _grant_daily_reputation(amount: int) -> int:
	var day := int(TimeManager.day_counter)
	if int(GameManager.flags.get("demo_ruf_day", -1)) == day:
		return 0
	GameManager.flags["demo_ruf_day"] = day
	PlayerStats.change_stat("ruf", amount)
	GameManager.flags["demo_scene_recognition"] = int(GameManager.flags.get("demo_scene_recognition", 0)) + amount
	return amount


func _release_blank_candidate() -> Disk:
	var best: Disk = null
	for disk: Disk in DiskManager.blank_disks():
		if disk.dtype != "DD": continue
		if best == null or disk.condition > best.condition or (disk.condition == best.condition and disk.uid < best.uid):
			best = disk
	return best


func _write_release_disk(disk: Disk, snapshot: Dictionary) -> void:
	var kind := str(snapshot.get("project_kind", "demo"))
	disk.content_type = "spiel" if kind == "game" else "demo"
	disk.content_title = str(snapshot.get("title", "EIGENE DEMO"))
	disk.label = str(snapshot.get("title", "DEMO")).left(24)
	disk.labeled = true
	disk.checked = true
	disk.rarity = "rare" if int(snapshot.get("score", 0)) >= 82 else "uncommon"
	disk.memory = "Eigener Szene-Release, gefreezt am %s" % TimeManager.date_string()
	disk.release_serial = str(snapshot.get("release_id", ""))
	disk.release_data = snapshot.duplicate(true)
	disk.release_role = "demo_master"
	disk.cracktro = kind == "demo"
	disk.cracktro_seen = kind != "demo" or disk.cracktro
	DiskManager.disks_changed.emit()


func _grant_scene_respect(snapshot: Dictionary) -> int:
	var fingerprint := "%s|%s" % [snapshot.get("build_hash", ""), str(snapshot.get("creator_assets", {}))]
	var seen: Array = GameManager.flags.get("demo_respect_builds", [])
	if fingerprint in seen:
		return 0
	var day := int(TimeManager.day_counter)
	var used := int(GameManager.flags.get("demo_respect_today", 0)) if int(GameManager.flags.get("demo_respect_day", -1)) == day else 0
	var room := maxi(0, RESPECT_DAILY_CAP - used)
	if room <= 0: return 0
	var score := int(snapshot.get("score", 0))
	var gain := 2 + maxi(0, floori((score - 50) / 8.0))
	gain += mini(3, (snapshot.get("creator_assets", {}) as Dictionary).size())
	if bool(snapshot.get("assisted", false)): gain = ceili(gain * 0.5)
	gain = mini(room, maxi(1, gain))
	var before := scene_respect()
	GameManager.flags["demo_scene_respect"] = mini(100, before + gain)
	GameManager.flags["demo_respect_day"] = day
	GameManager.flags["demo_respect_today"] = used + gain
	seen.append(fingerprint)
	if seen.size() > 64: seen = seen.slice(seen.size() - 64)
	GameManager.flags["demo_respect_builds"] = seen
	return scene_respect() - before


func _note_release(release_snapshot: Dictionary) -> void:
	MemoryManager.record_once("first_demo", "erste eigene Demo released: %s" % str(release_snapshot.get("title", "DEMO")))
	var achievements := get_node_or_null("/root/AchievementManager")
	if achievements != null:
		achievements.call("note", "released_demo")
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call("play", "coins", 0.0)


## Questfortschritt wird am unveraenderlichen Release-Snapshot festgemacht.
## Dadurch unterscheiden sich Demo und Spiel-Prototyp wirklich, und nur ein
## Release waehrend der jeweils aktiven Queststufe zaehlt.
func _note_quest_release(release_snapshot: Dictionary) -> void:
	var kind := str(release_snapshot.get("project_kind", "demo"))
	if kind == "game":
		QuestManager.note_action("release_game")
		QuestManager.note_action("firma_prototype")
	elif kind == "club_intro":
		QuestManager.note_action("release_club_intro")
	else:
		QuestManager.note_action("release_demo")
		if QuestManager.is_active("q_compo") and QuestManager.stage("q_compo") == 0:
			GameManager.flags["q_compo_release_disk_uid"] = str(
				release_snapshot.get("disk_uid", ""))
		QuestManager.note_action("compo_release")
		QuestManager.note_action("millennium_release")
