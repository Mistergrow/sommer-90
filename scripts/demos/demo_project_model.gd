class_name DemoProjectModel
extends RefCounted
## Deterministisches Autorenmodell fuer das Szene-Studio.
##
## Das Modell bildet keine echte Assembler-Toolchain nach. Es simuliert den
## kreativen A500-Workflow als pruefbares System aus Timeline-Parts, Effektlagen,
## Code-Modulen, Abhaengigkeiten und knappen PAL-Ressourcen. UI, Animation, Audio
## und Weltzustand bleiben absichtlich ausserhalb dieser Datei.

const SCHEMA_VERSION := 5
const MAX_PARTS := 8
const MAX_EFFECTS_PER_PART := 3
const MIN_PART_DURATION := 2.0
const MAX_PART_DURATION := 32.0
const PAL_FPS := 50.0
const PAL_FRAME_MS := 20.0
const CPU_BUDGET := 100.0
const BLITTER_BUDGET := 100.0
const CHIP_RAM_KB := 512.0
const COLOR_BUDGET := 32

const EFFECT_IDS := [
	"starfield", "copperbars", "plasma", "vectorgrid",
	"bobs", "tunnel", "shadebobs", "sine_scroller",
	"rasterbars", "rotozoomer", "line_twister", "moire_rings",
]
const PALETTE_IDS := [
	"night_copper", "violet_ice", "acid_sunset", "steel_blue", "red_signal",
]
const TRANSITION_IDS := ["cut", "fade", "wipe", "checker", "curtain", "flash"]
const PROJECT_KINDS := ["demo", "club_intro", "game"]
const DEMO_FORMATS := ["trackmo", "megademo", "dentro"]
const INTRO_PURPOSES := ["group_id", "invitation", "cracktro"]
const GAME_MODES := ["collector", "courier", "survival", "puzzle"]
const GAME_DIFFICULTIES := ["easy", "normal", "hard"]
const OPTIMIZATION_IDS := [
	"precalc_tables", "delta_pack", "reuse_buffers", "dirty_rects",
	"half_res", "palette_reduce",
]
const OPTIMIZATION_PROFILES := ["balanced", "speed", "memory", "compatibility"]

## Aufwand eines Effekts bei Intensitaet 1.0. Zweite und dritte Effektlage werden
## in compile_report() mit realistischen Kompositionsfaktoren gewichtet.
const EFFECTS := {
	"starfield": {
		"name": "3D STARFIELD", "cpu": 18.0, "chip_kb": 20.0,
		"blitter": 4.0, "colors": 8, "modules": [],
	},
	"copperbars": {
		"name": "COPPER BARS", "cpu": 12.0, "chip_kb": 12.0,
		"blitter": 2.0, "colors": 32, "modules": ["copperlist"],
	},
	"plasma": {
		"name": "PLASMA", "cpu": 58.0, "chip_kb": 76.0,
		"blitter": 12.0, "colors": 32,
		"modules": ["copperlist", "precalc_tables"],
	},
	"vectorgrid": {
		"name": "VECTOR GRID", "cpu": 70.0, "chip_kb": 70.0,
		"blitter": 38.0, "colors": 8,
		"modules": ["blitter", "precalc_tables"],
	},
	"bobs": {
		"name": "BOB FIELD", "cpu": 32.0, "chip_kb": 150.0,
		"blitter": 78.0, "colors": 16,
		"modules": ["blitter", "sprite_mux"],
	},
	"tunnel": {
		"name": "TABLE TUNNEL", "cpu": 74.0, "chip_kb": 116.0,
		"blitter": 30.0, "colors": 32,
		"modules": ["copperlist", "precalc_tables"],
	},
	"shadebobs": {
		"name": "SHADEBOBS", "cpu": 52.0, "chip_kb": 210.0,
		"blitter": 96.0, "colors": 32,
		"modules": ["blitter", "double_buffer"],
	},
	"sine_scroller": {
		"name": "SINE SCROLLER", "cpu": 24.0, "chip_kb": 52.0,
		"blitter": 38.0, "colors": 8,
		"modules": ["scroller", "precalc_tables"],
	},
	"rasterbars": {
		"name": "RASTER BARS", "cpu": 10.0, "chip_kb": 10.0,
		"blitter": 0.0, "colors": 32,
		"modules": ["copperlist"],
	},
	"rotozoomer": {
		"name": "ROTOZOOMER", "cpu": 66.0, "chip_kb": 128.0,
		"blitter": 58.0, "colors": 16,
		"modules": ["blitter", "double_buffer", "precalc_tables"],
	},
	"line_twister": {
		"name": "LINE TWISTER", "cpu": 42.0, "chip_kb": 64.0,
		"blitter": 30.0, "colors": 16,
		"modules": ["blitter", "precalc_tables"],
	},
	"moire_rings": {
		"name": "MOIRE RINGS", "cpu": 34.0, "chip_kb": 42.0,
		"blitter": 4.0, "colors": 8,
		"modules": ["copperlist", "precalc_tables"],
	},
}

## Code-Module belegen gemeinsamen Chip-RAM und koennen voneinander abhaengen.
## Die Reihenfolge ist zugleich die stabile Reihenfolge in Saves und Build-Logs.
const MODULE_IDS := [
	"boot_init", "memory_map", "vblank_irq", "part_loader", "music_irq",
	"copperlist", "blitter", "scroller", "sprite_mux", "double_buffer",
	"precalc_tables", "delta_pack",
]
const MODULES := {
	"boot_init": {"name": "BOOT / INIT", "chip_kb": 10.0, "deps": []},
	"memory_map": {"name": "MEMORY MAP", "chip_kb": 4.0, "deps": ["boot_init"]},
	"vblank_irq": {"name": "VBLANK IRQ", "chip_kb": 5.0, "deps": ["boot_init"]},
	"part_loader": {
		"name": "PART LOADER", "chip_kb": 16.0,
		"deps": ["memory_map", "vblank_irq"],
	},
	"music_irq": {"name": "MUSIC IRQ", "chip_kb": 12.0, "deps": ["vblank_irq"]},
	"copperlist": {"name": "COPPERLIST", "chip_kb": 8.0, "deps": ["vblank_irq"]},
	"blitter": {
		"name": "BLITTER DRIVER", "chip_kb": 10.0,
		"deps": ["memory_map", "vblank_irq"],
	},
	"scroller": {"name": "SCROLLER", "chip_kb": 18.0, "deps": ["blitter"]},
	"sprite_mux": {"name": "SPRITE MUX", "chip_kb": 14.0, "deps": ["vblank_irq"]},
	"double_buffer": {"name": "DOUBLE BUFFER", "chip_kb": 64.0, "deps": ["blitter"]},
	"precalc_tables": {"name": "PRECALC TABLES", "chip_kb": 48.0, "deps": ["memory_map"]},
	"delta_pack": {"name": "DELTA PACKER", "chip_kb": 10.0, "deps": ["part_loader"]},
}

const TRANSITIONS := {
	"cut": {
		"cpu": 0.0, "chip_kb": 0.0, "blitter": 0.0, "modules": [],
	},
	"fade": {
		"cpu": 5.0, "chip_kb": 4.0, "blitter": 1.0, "modules": ["copperlist"],
	},
	"wipe": {
		"cpu": 8.0, "chip_kb": 12.0, "blitter": 20.0, "modules": ["blitter"],
	},
	"checker": {
		"cpu": 12.0, "chip_kb": 18.0, "blitter": 34.0, "modules": ["blitter"],
	},
	"curtain": {
		"cpu": 5.0, "chip_kb": 8.0, "blitter": 16.0, "modules": ["blitter"],
	},
	"flash": {
		"cpu": 3.0, "chip_kb": 2.0, "blitter": 0.0, "modules": ["copperlist"],
	},
}


## Ein direkt kompilierbares, aber noch verbesserbares Drei-Part-Projekt.
static func default_project(project_seed: int = 1990) -> Dictionary:
	var safe_seed := clampi(absi(project_seed), 1, 2_147_483_647)
	return {
		"schema_version": SCHEMA_VERSION,
		"project_kind": "demo",
		"demo_format": "trackmo",
		"intro_purpose": "group_id",
		"game_mode": "collector",
		"game_difficulty": "normal",
		"game_lives": 3,
		"game_objectives": 3,
		"seed": safe_seed,
		"title": "MIDNIGHT CIRCUIT",
		"group": "BYTEWERK",
		"author": "LONE CODER",
		"scroller": "WELCOME TO OUR NEW DEMO -- GREETINGS TO ALL SCENERS AND SYSOPS!",
		"credits": "CODE: LONE CODER  ART: LISA  MUSIC: DANIEL",
		"soundtrack": "night_shift.mod",
		"bpm": 125,
		"palette": "night_copper",
		"studio_hud": true,
		"modules": [
			"boot_init", "memory_map", "vblank_irq", "part_loader", "music_irq",
			"copperlist", "blitter", "scroller", "precalc_tables",
		],
		"parts": [
			{
				"id": "part_01", "name": "BOOT VECTOR", "title": "MIDNIGHT CIRCUIT",
				"duration": 7.0, "effect": "starfield",
				"effects": ["starfield", "copperbars"], "layers": ["copperbars"],
				"transition": "cut", "palette": "night_copper",
				"scrolltext": "", "intensity": 0.86, "sync": 0.30,
				"optimizations": [],
			},
			{
				"id": "part_02", "name": "PLASMA LINK", "title": "BYTEWERK",
				"duration": 11.0, "effect": "plasma",
				"effects": ["plasma", "sine_scroller"], "layers": ["sine_scroller"],
				"transition": "fade", "palette": "violet_ice",
				"scrolltext": "GREETINGS TO THE NIGHT SHIFT", "intensity": 0.90, "sync": 0.55,
				"optimizations": ["palette_reduce"],
			},
			{
				"id": "part_03", "name": "FINAL GRID", "title": "SEE YOU ON THE BOARDS",
				"duration": 9.0, "effect": "vectorgrid",
				"effects": ["vectorgrid", "starfield"], "layers": ["starfield"],
				"transition": "wipe", "palette": "red_signal",
				"scrolltext": "CALL OUR BBS -- KEEP THE SCENE ALIVE", "intensity": 0.82, "sync": 0.75,
				"optimizations": [],
			},
		],
		"revision": 1,
	}


## Normalisiert fremde/alte Save-Daten auf ein begrenztes kanonisches Schema.
## Fehlende Felder erhalten Defaults; explizit leere Titel/Module/Parts bleiben
## leer, damit compile_report() daraus hilfreiche Build-Fehler erzeugen kann.
static func sanitize_project(raw: Dictionary) -> Dictionary:
	var defaults := default_project(int(raw.get("seed", 1990)))
	var modules_source: Variant = raw.get("modules", defaults["modules"])
	var modules: Array[String] = []
	if modules_source is Array:
		for value: Variant in modules_source:
			var module_id := str(value)
			if module_id in MODULE_IDS and module_id not in modules:
				modules.append(module_id)
	modules = _ordered_ids(modules, MODULE_IDS)

	var parts_source: Variant = raw.get("parts", defaults["parts"])
	var parts: Array[Dictionary] = []
	if parts_source is Array:
		for i in mini(parts_source.size(), MAX_PARTS):
			var value: Variant = parts_source[i]
			parts.append(sanitize_part(value if value is Dictionary else {}, i))
	_make_part_ids_unique(parts)

	return {
		"schema_version": SCHEMA_VERSION,
		"project_kind": _valid_id(str(raw.get("project_kind", defaults["project_kind"])), PROJECT_KINDS, "demo"),
		"demo_format": _valid_id(str(raw.get("demo_format", defaults["demo_format"])), DEMO_FORMATS, "trackmo"),
		"intro_purpose": _valid_id(str(raw.get("intro_purpose", defaults["intro_purpose"])), INTRO_PURPOSES, "group_id"),
		"game_mode": _valid_id(str(raw.get("game_mode", defaults["game_mode"])), GAME_MODES, "collector"),
		"game_difficulty": _valid_id(str(raw.get("game_difficulty", defaults["game_difficulty"])), GAME_DIFFICULTIES, "normal"),
		"game_lives": clampi(int(raw.get("game_lives", defaults["game_lives"])), 1, 9),
		"game_objectives": clampi(int(raw.get("game_objectives", defaults["game_objectives"])), 1, 8),
		"seed": clampi(absi(int(raw.get("seed", defaults["seed"]))), 1, 2_147_483_647),
		"title": _safe_text(raw.get("title", defaults["title"]), 48, true),
		"group": _safe_text(raw.get("group", defaults["group"]), 32, true),
		"author": _safe_text(raw.get("author", defaults["author"]), 32, true),
		"scroller": _safe_text(raw.get("scroller", defaults["scroller"]), 512, false),
		"credits": _safe_text(raw.get("credits", defaults["credits"]), 256, false),
		"soundtrack": _safe_text(raw.get("soundtrack", defaults["soundtrack"]), 64, true),
		"bpm": clampi(int(raw.get("bpm", defaults["bpm"])), 60, 200),
		"palette": _valid_id(str(raw.get("palette", defaults["palette"])), PALETTE_IDS, "night_copper"),
		"studio_hud": bool(raw.get("studio_hud", defaults["studio_hud"])),
		"modules": modules,
		"parts": parts,
		"revision": clampi(int(raw.get("revision", defaults["revision"])), 1, 9999),
	}


## Normalisiert einen Timeline-Part. `effects` enthaelt immer den Primaereffekt;
## `layers` ist das Alias nur fuer zusaetzliche Lagen und erleichtert Renderer,
## die noch das fruehe Studio-Schema lesen.
static func sanitize_part(raw: Dictionary, index: int = 0) -> Dictionary:
	var primary := _canonical_effect_id(str(raw.get("effect", "starfield")))
	var effects: Array[String] = [primary]
	var effect_source: Variant = raw.get("effects", [])
	if effect_source is Array:
		for value: Variant in effect_source:
			var effect_id := _canonical_effect_id(str(value))
			if effect_id in EFFECT_IDS and effect_id not in effects and effects.size() < MAX_EFFECTS_PER_PART:
				effects.append(effect_id)
	var layer_source: Variant = raw.get("layers", [])
	if layer_source is Array:
		for value: Variant in layer_source:
			var effect_id := _canonical_effect_id(str(value))
			if effect_id in EFFECT_IDS and effect_id not in effects and effects.size() < MAX_EFFECTS_PER_PART:
				effects.append(effect_id)
	var optimizations: Array[String] = []
	var optimization_source: Variant = raw.get("optimizations", [])
	if optimization_source is Array:
		for value: Variant in optimization_source:
			var optimization_id := str(value)
			if optimization_id in OPTIMIZATION_IDS and optimization_id not in optimizations:
				optimizations.append(optimization_id)
	optimizations = _ordered_ids(optimizations, OPTIMIZATION_IDS)
	var part_number := maxi(1, index + 1)
	var fallback_id := "part_%02d" % part_number
	var clean_id := _safe_id(str(raw.get("id", fallback_id)))
	if clean_id.is_empty():
		clean_id = fallback_id
	var name := _safe_text(raw.get("name", "PART %02d" % part_number), 32, true)
	return {
		"id": clean_id,
		"name": name,
		"title": _safe_text(raw.get("title", name), 48, true),
		"duration": clampf(float(raw.get("duration", 8.0)), MIN_PART_DURATION, MAX_PART_DURATION),
		"effect": effects[0],
		"effects": effects,
		"layers": effects.slice(1),
		"transition": _canonical_transition_id(str(raw.get("transition", "cut"))),
		"palette": _valid_id(str(raw.get("palette", "night_copper")), PALETTE_IDS, "night_copper"),
		"scrolltext": _safe_text(raw.get("scrolltext", ""), 256, false),
		"intensity": clampf(float(raw.get("intensity", 1.0)), 0.50, 1.50),
		"sync": clampf(float(raw.get("sync", 0.0)), 0.0, 1.0),
		"optimizations": optimizations,
	}


## Vollstaendiger, deterministischer Build-Report. Ressourcen sind Peaks pro PAL-
## Frame; Chip-RAM enthaelt Code + Daten des jeweils aktiven Parts.
static func compile_report(project: Dictionary) -> Dictionary:
	var clean := sanitize_project(project)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var installed: Array[String] = []
	installed.assign(clean["modules"])
	var parts: Array[Dictionary] = []
	parts.assign(clean["parts"])

	if str(clean["title"]).is_empty():
		errors.append("E001: Projekttitel fehlt.")
	if str(clean["group"]).is_empty():
		errors.append("E002: Gruppenname fehlt.")
	if parts.is_empty():
		errors.append("E003: Timeline enthaelt keinen Part.")
	elif parts.size() == 1 and str(clean["project_kind"]) != "club_intro":
		warnings.append("W101: Ein einzelner Part wirkt eher wie ein Intro als eine Demo.")
	match str(clean["project_kind"]):
		"demo":
			var expected_parts: int = int({"dentro": 2, "trackmo": 3, "megademo": 4}.get(
				str(clean["demo_format"]), 3))
			if parts.size() < expected_parts:
				warnings.append("W102: %s wirkt erst ab %d Parts vollstaendig." % [
					str(clean["demo_format"]).to_upper(), expected_parts])
		"club_intro":
			if parts.size() > 3:
				warnings.append("W103: Ein Club-Intro mit mehr als drei Parts verliert seine Praegnanz.")
		"game":
			if parts.size() < 3:
				warnings.append("W104: Dem Spiel fehlen sichtbare TITLE-, LEVEL- oder RESULT-Phasen.")

	var required := _required_modules(clean)
	var missing: Array[String] = []
	for module_id in required:
		if module_id not in installed:
			missing.append(module_id)
			errors.append("E110: Pflichtmodul fehlt: %s." % str(MODULES[module_id]["name"]))
	for module_id in installed:
		var deps: Array = MODULES[module_id]["deps"]
		for dependency: String in deps:
			if dependency not in installed:
				errors.append("E111: %s benoetigt %s." % [
					str(MODULES[module_id]["name"]), str(MODULES[dependency]["name"]),
				])

	var shared_chip := _shared_chip_kb(installed)
	var part_reports: Array[Dictionary] = []
	var peak_cpu := 0.0
	var peak_blitter := 0.0
	var peak_chip := shared_chip
	var peak_colors := 0
	var min_fps := PAL_FPS
	var duration := 0.0
	var all_effects: Array[String] = []
	var all_palettes: Array[String] = []
	var all_transitions: Array[String] = []
	var optimization_count := 0
	for i in parts.size():
		var part: Dictionary = parts[i]
		var part_metrics := _part_metrics(part, shared_chip)
		part_reports.append(part_metrics)
		peak_cpu = maxf(peak_cpu, float(part_metrics["cpu_pct"]))
		peak_blitter = maxf(peak_blitter, float(part_metrics["blitter_pct"]))
		peak_chip = maxf(peak_chip, float(part_metrics["chip_kb"]))
		peak_colors = maxi(peak_colors, int(part_metrics["colors"]))
		min_fps = minf(min_fps, float(part_metrics["estimated_fps"]))
		duration += float(part["duration"])
		optimization_count += part["optimizations"].size()
		for effect_id: String in part["effects"]:
			if effect_id not in all_effects:
				all_effects.append(effect_id)
		if str(part["palette"]) not in all_palettes:
			all_palettes.append(str(part["palette"]))
		if str(part["transition"]) not in all_transitions:
			all_transitions.append(str(part["transition"]))

		var label := str(part["name"])
		if float(part_metrics["cpu_pct"]) > CPU_BUDGET:
			errors.append("E201: %s sprengt das CPU-Budget (%.1f%%)." % [label, part_metrics["cpu_pct"]])
		elif float(part_metrics["cpu_pct"]) > 85.0:
			warnings.append("W201: %s hat wenig CPU-Reserve (%.1f%%)." % [label, part_metrics["cpu_pct"]])
		if float(part_metrics["blitter_pct"]) > BLITTER_BUDGET:
			errors.append("E202: %s blockiert den Blitter (%.1f%%)." % [label, part_metrics["blitter_pct"]])
		elif float(part_metrics["blitter_pct"]) > 85.0:
			warnings.append("W202: %s hat wenig Blitter-Reserve (%.1f%%)." % [label, part_metrics["blitter_pct"]])
		if float(part_metrics["chip_kb"]) > CHIP_RAM_KB:
			errors.append("E203: %s passt nicht in 512 KB Chip-RAM (%.0f KB)." % [label, part_metrics["chip_kb"]])
		elif float(part_metrics["chip_kb"]) > 440.0:
			warnings.append("W203: %s laesst kaum Chip-RAM frei (%.0f KB)." % [label, part_metrics["chip_kb"]])
		if int(part_metrics["colors"]) > COLOR_BUDGET:
			errors.append("E204: %s fordert %d Farben in einer 32-Farben-Pipeline." % [label, part_metrics["colors"]])
		elif int(part_metrics["colors"]) > 28:
			warnings.append("W204: %s nutzt die Palette nahezu voll aus." % label)
		if str(part["transition"]) == "flash":
			warnings.append("W205: %s nutzt einen Flash-Uebergang; Photosensitivitaetsoption beachten." % label)

	if duration < 18.0 and not parts.is_empty() and str(clean["project_kind"]) != "club_intro":
		warnings.append("W301: Gesamtlaufzeit unter 18 Sekunden.")
	elif duration > 120.0:
		warnings.append("W302: Gesamtlaufzeit ueber zwei Minuten erhoeht Ladepausenrisiko.")
	if str(clean["project_kind"]) == "club_intro" and duration > 32.0:
		warnings.append("W308: Club-Intro laenger als 32 Sekunden — Botschaft kuerzen.")
	if all_effects.size() < mini(3, parts.size()) and parts.size() > 1:
		warnings.append("W303: Zu wenig Effektvariation zwischen den Parts.")
	if str(clean["scroller"]).length() < 24:
		warnings.append("W304: Globaler Scrolltext ist sehr kurz.")
	if not _contains_greeting(str(clean["scroller"])):
		warnings.append("W305: Keine Szene-Greetings im globalen Scrolltext erkannt.")
	if str(clean["credits"]).length() < 12:
		warnings.append("W306: Credits sind unvollstaendig.")

	var unused: Array[String] = []
	for module_id in installed:
		if module_id not in required:
			unused.append(module_id)
	if unused.size() > 2:
		warnings.append("W307: %d ungenutzte Code-Module belegen Chip-RAM." % unused.size())

	var metrics := {
		"target_fps": PAL_FPS,
		"frame_budget_ms": PAL_FRAME_MS,
		"estimated_fps": snappedf(min_fps, 0.1),
		"peak_cpu_pct": snappedf(peak_cpu, 0.1),
		"peak_blitter_pct": snappedf(peak_blitter, 0.1),
		"peak_chip_kb": snappedf(peak_chip, 0.1),
		"peak_colors": peak_colors,
		"shared_chip_kb": snappedf(shared_chip, 0.1),
		"duration_s": snappedf(duration, 0.1),
		"part_count": parts.size(),
		"effect_variety": all_effects.size(),
		"palette_variety": all_palettes.size(),
		"transition_variety": all_transitions.size(),
		"optimization_count": optimization_count,
	}
	var build_hash := _stable_hash(clean)
	return {
		"success": errors.is_empty(),
		"can_release": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"metrics": metrics,
		"parts": part_reports,
		"required_modules": required,
		"missing_modules": missing,
		"unused_modules": unused,
		"project": clean,
		"hash": build_hash,
		"build_label": "PAL-%s-R%04d" % [build_hash.left(8).to_upper(), int(clean["revision"])],
	}


## Wendet reproduzierbare Ressourcen-Trades an und installiert nur die fuer diese
## Optimierungen benoetigten Modul-Abhaengigkeiten. Das Eingabeprojekt bleibt
## unveraendert. Profile: balanced, speed, memory, compatibility.
static func optimize_project(project: Dictionary, profile: String = "balanced") -> Dictionary:
	var clean := sanitize_project(project)
	var selected_profile := profile if profile in OPTIMIZATION_PROFILES else "balanced"
	var parts: Array[Dictionary] = []
	parts.assign(clean["parts"])
	var installed: Array[String] = []
	installed.assign(clean["modules"])
	var shared_chip := _shared_chip_kb(installed)
	for i in parts.size():
		var part: Dictionary = parts[i].duplicate(true)
		var opts: Array[String] = []
		opts.assign(part["optimizations"])
		var metrics := _part_metrics(part, shared_chip)
		match selected_profile:
			"speed":
				_add_unique(opts, "precalc_tables")
				if float(metrics["blitter_pct"]) > 72.0:
					_add_unique(opts, "dirty_rects")
			"memory":
				_add_unique(opts, "delta_pack")
				_add_unique(opts, "reuse_buffers")
				if int(metrics["colors"]) > 24:
					_add_unique(opts, "palette_reduce")
			"compatibility":
				_add_unique(opts, "delta_pack")
				_add_unique(opts, "reuse_buffers")
				_add_unique(opts, "dirty_rects")
				_add_unique(opts, "palette_reduce")
				if float(metrics["cpu_pct"]) > 100.0 or float(metrics["blitter_pct"]) > 100.0 or float(metrics["chip_kb"]) > CHIP_RAM_KB:
					_add_unique(opts, "half_res")
			_:
				if float(metrics["cpu_pct"]) > 82.0:
					_add_unique(opts, "precalc_tables")
				if float(metrics["chip_kb"]) > 420.0:
					_add_unique(opts, "delta_pack")
					_add_unique(opts, "reuse_buffers")
				if float(metrics["blitter_pct"]) > 82.0:
					_add_unique(opts, "dirty_rects")
				if int(metrics["colors"]) > 28:
					_add_unique(opts, "palette_reduce")
		part["optimizations"] = _ordered_ids(opts, OPTIMIZATION_IDS)
		parts[i] = part
		if "precalc_tables" in opts:
			_install_module_with_dependencies(installed, "precalc_tables")
		if "delta_pack" in opts:
			_install_module_with_dependencies(installed, "delta_pack")
	clean["parts"] = parts
	clean["modules"] = _ordered_ids(installed, MODULE_IDS)
	clean["revision"] = mini(9999, int(clean["revision"]) + 1)
	return sanitize_project(clean)


## Fuegt einen Part ohne Seiteneffekte hinzu. Benoetigte Module bleiben eine
## bewusste Coding-Aufgabe und werden vom anschliessenden Build-Report benannt.
static func add_part(project: Dictionary, effect_id: String = "starfield") -> Dictionary:
	var clean := sanitize_project(project)
	var parts: Array[Dictionary] = []
	parts.assign(clean["parts"])
	if parts.size() >= MAX_PARTS:
		return clean
	var index := parts.size()
	var valid_effect := _valid_id(effect_id, EFFECT_IDS, "starfield")
	parts.append(sanitize_part({
		"id": "part_%02d" % (index + 1),
		"name": "PART %02d" % (index + 1),
		"effect": valid_effect,
		"effects": [valid_effect],
		"palette": clean["palette"],
	}, index))
	clean["parts"] = parts
	clean["revision"] = mini(9999, int(clean["revision"]) + 1)
	return clean


static func remove_part(project: Dictionary, index: int) -> Dictionary:
	var clean := sanitize_project(project)
	var parts: Array[Dictionary] = []
	parts.assign(clean["parts"])
	if index < 0 or index >= parts.size():
		return clean
	parts.remove_at(index)
	clean["parts"] = parts
	clean["revision"] = mini(9999, int(clean["revision"]) + 1)
	return clean


static func move_part(project: Dictionary, from_index: int, to_index: int) -> Dictionary:
	var clean := sanitize_project(project)
	var parts: Array[Dictionary] = []
	parts.assign(clean["parts"])
	if from_index < 0 or from_index >= parts.size() or to_index < 0 or to_index >= parts.size() or from_index == to_index:
		return clean
	var moved: Dictionary = parts[from_index]
	parts.remove_at(from_index)
	parts.insert(to_index, moved)
	clean["parts"] = parts
	clean["revision"] = mini(9999, int(clean["revision"]) + 1)
	return clean


## Installiert alle aktuell benoetigten Module samt transitiven Abhaengigkeiten.
## Diese explizite Hilfe ist fuer Tutorial/Assistenzmodus gedacht.
static func install_required_modules(project: Dictionary) -> Dictionary:
	var clean := sanitize_project(project)
	var installed: Array[String] = []
	installed.assign(clean["modules"])
	for module_id in _required_modules(clean):
		_install_module_with_dependencies(installed, module_id)
	clean["modules"] = _ordered_ids(installed, MODULE_IDS)
	clean["revision"] = mini(9999, int(clean["revision"]) + 1)
	return clean


## Qualitätsprofil 0..100. Build-Fehler deckeln die Note bewusst unter Release-
## Niveau, waehrend Komponenten transparent machen, wo Punkte fehlen.
static func quality_report(project: Dictionary, build: Dictionary = {}) -> Dictionary:
	var report := build if not build.is_empty() else compile_report(project)
	var clean: Dictionary = report.get("project", sanitize_project(project))
	var metrics: Dictionary = report.get("metrics", {})
	var parts: Array = clean.get("parts", [])
	var technical := 0.0
	if bool(report.get("success", false)):
		technical += 16.0
	else:
		technical += maxf(0.0, 16.0 - float(report.get("errors", []).size()) * 5.0)
	technical += _headroom_points(float(metrics.get("peak_cpu_pct", 999.0)), 82.0, CPU_BUDGET, 3.5)
	technical += _headroom_points(float(metrics.get("peak_blitter_pct", 999.0)), 82.0, BLITTER_BUDGET, 3.5)
	technical += _headroom_points(float(metrics.get("peak_chip_kb", 999.0)), 420.0, CHIP_RAM_KB, 3.5)
	technical += _headroom_points(float(metrics.get("peak_colors", 99)), 28.0, float(COLOR_BUDGET), 3.5)
	technical = clampf(technical, 0.0, 30.0)

	var creative := 0.0
	creative += minf(1.0, float(parts.size()) / 3.0) * 6.0
	creative += minf(1.0, float(metrics.get("effect_variety", 0)) / 4.0) * 10.0
	creative += minf(1.0, float(metrics.get("transition_variety", 0)) / 3.0) * 4.0
	creative += minf(1.0, float(metrics.get("palette_variety", 0)) / 3.0) * 5.0

	var sync_average := 0.0
	for value: Variant in parts:
		if value is Dictionary:
			sync_average += float(value.get("sync", 0.0))
	if not parts.is_empty():
		sync_average /= float(parts.size())
	var sync_score := sync_average * 9.0
	if not str(clean.get("soundtrack", "")).is_empty():
		sync_score += 3.0
	if int(clean.get("bpm", 0)) >= 80 and int(clean.get("bpm", 0)) <= 170:
		sync_score += 3.0
	sync_score = clampf(sync_score, 0.0, 15.0)

	var scene := 0.0
	if not str(clean.get("title", "")).is_empty():
		scene += 2.0
	if not str(clean.get("group", "")).is_empty():
		scene += 2.0
	var scroll_length := str(clean.get("scroller", "")).length()
	scene += minf(6.0, float(scroll_length) / 10.0)
	if _contains_greeting(str(clean.get("scroller", ""))):
		scene += 4.0
	if str(clean.get("credits", "")).length() >= 12:
		scene += 4.0

	var craft := minf(6.0, float(metrics.get("optimization_count", 0)) * 2.0)
	if report.get("unused_modules", []).size() <= 1:
		craft += 3.0
	var duration := float(metrics.get("duration_s", 0.0))
	if duration >= 20.0 and duration <= 120.0:
		craft += 3.0
	var score := clampi(int(round(technical + creative + sync_score + scene + craft)), 0, 100)
	if not bool(report.get("success", false)):
		score = mini(score, 49)
	var grade := "E"
	if score >= 92:
		grade = "S"
	elif score >= 82:
		grade = "A"
	elif score >= 70:
		grade = "B"
	elif score >= 55:
		grade = "C"
	elif score >= 40:
		grade = "D"
	return {
		"score": score,
		"grade": grade,
		"release_ready": bool(report.get("success", false)) and score >= 55,
		"components": {
			"technical": snappedf(technical, 0.1),
			"creative": snappedf(creative, 0.1),
			"sync": snappedf(sync_score, 0.1),
			"scene": snappedf(scene, 0.1),
			"craft": snappedf(craft, 0.1),
		},
		"build_hash": str(report.get("hash", _stable_hash(clean))),
	}


static func serialize(project: Dictionary) -> String:
	return JSON.stringify(sanitize_project(project))


static func deserialize(data: Variant) -> Dictionary:
	if data is Dictionary:
		return sanitize_project(data)
	if data is String:
		var parser := JSON.new()
		if parser.parse(data) == OK and parser.data is Dictionary:
			return sanitize_project(parser.data)
	return default_project()


static func _required_modules(project: Dictionary) -> Array[String]:
	var required: Array[String] = ["boot_init", "memory_map", "vblank_irq", "part_loader"]
	if not str(project.get("soundtrack", "")).is_empty():
		_add_unique(required, "music_irq")
	if not str(project.get("scroller", "")).is_empty():
		_add_unique(required, "scroller")
	for part_value: Variant in project.get("parts", []):
		if not part_value is Dictionary:
			continue
		var part: Dictionary = part_value
		if not str(part.get("scrolltext", "")).is_empty():
			_add_unique(required, "scroller")
		for effect_id: String in part.get("effects", []):
			for module_id: String in EFFECTS[effect_id]["modules"]:
				_add_unique(required, module_id)
		var transition := str(part.get("transition", "cut"))
		for module_id: String in TRANSITIONS[transition]["modules"]:
			_add_unique(required, module_id)
		for optimization_id: String in part.get("optimizations", []):
			if optimization_id in ["precalc_tables", "delta_pack"]:
				_add_unique(required, optimization_id)
	# Auch transitive Abhaengigkeiten sind Pflicht, in stabiler Modulreihenfolge.
	var expanded: Array[String] = []
	for module_id in required:
		_collect_module_dependencies(expanded, module_id)
	return _ordered_ids(expanded, MODULE_IDS)


static func _collect_module_dependencies(output: Array[String], module_id: String) -> void:
	for dependency: String in MODULES[module_id]["deps"]:
		_collect_module_dependencies(output, dependency)
	_add_unique(output, module_id)


static func _install_module_with_dependencies(installed: Array[String], module_id: String) -> void:
	for dependency: String in MODULES[module_id]["deps"]:
		_install_module_with_dependencies(installed, dependency)
	_add_unique(installed, module_id)


static func _shared_chip_kb(installed: Array[String]) -> float:
	var total := 0.0
	for module_id in installed:
		total += float(MODULES[module_id]["chip_kb"])
	return total


static func _part_metrics(part: Dictionary, shared_chip: float) -> Dictionary:
	var cpu := 0.0
	var chip := 0.0
	var blitter := 0.0
	var colors := 0.0
	var layer_factors := [1.0, 0.62, 0.45]
	var intensity := float(part.get("intensity", 1.0))
	var effects: Array = part.get("effects", ["starfield"])
	for i in effects.size():
		var effect: Dictionary = EFFECTS[str(effects[i])]
		var factor: float = float(layer_factors[mini(i, layer_factors.size() - 1)])
		cpu += float(effect["cpu"]) * factor * intensity
		chip += float(effect["chip_kb"]) * factor
		blitter += float(effect["blitter"]) * factor * intensity
		colors += float(effect["colors"]) * factor
	var transition: Dictionary = TRANSITIONS[str(part.get("transition", "cut"))]
	cpu += float(transition["cpu"])
	chip += float(transition["chip_kb"])
	blitter += float(transition["blitter"])
	for optimization_id: String in part.get("optimizations", []):
		match optimization_id:
			"precalc_tables":
				cpu *= 0.78
				chip *= 1.08
			"delta_pack":
				chip *= 0.70
				cpu *= 1.10
			"reuse_buffers":
				chip *= 0.75
				blitter *= 1.10
			"dirty_rects":
				blitter *= 0.76
				cpu *= 1.06
			"half_res":
				cpu *= 0.72
				chip *= 0.72
				blitter *= 0.68
			"palette_reduce":
				colors = minf(colors, 16.0)
				cpu *= 1.02
	var cpu_ratio := cpu / CPU_BUDGET
	var blitter_ratio := blitter / BLITTER_BUDGET
	var frame_ratio := maxf(1.0, maxf(cpu_ratio, blitter_ratio))
	return {
		"id": str(part.get("id", "part")),
		"name": str(part.get("name", "PART")),
		"cpu_pct": snappedf(cpu, 0.1),
		"blitter_pct": snappedf(blitter, 0.1),
		"chip_kb": snappedf(shared_chip + chip, 0.1),
		"colors": int(ceil(colors)),
		"estimated_fps": snappedf(PAL_FPS / frame_ratio, 0.1),
		"frame_ms": snappedf(PAL_FRAME_MS * frame_ratio, 0.1),
	}


static func _headroom_points(value: float, soft_limit: float, hard_limit: float, points: float) -> float:
	if value <= soft_limit:
		return points
	if value >= hard_limit:
		return 0.0
	return points * (hard_limit - value) / (hard_limit - soft_limit)


static func _contains_greeting(text: String) -> bool:
	var lower := text.to_lower()
	return "greet" in lower or "gruss" in lower or "grüß" in lower or "greets" in lower or "hello to" in lower


static func _safe_text(value: Variant, limit: int, single_line: bool) -> String:
	var text := str(value).strip_edges()
	# Ohne NUL-Stringliteral filtern: Schon das Konstruieren eines Strings mit
	# Codepoint 0 erzeugt in Godots UTF-8-Diagnostik eine Warnung.
	var without_nul := ""
	for index in text.length():
		if text.unicode_at(index) != 0:
			without_nul += text[index]
	text = without_nul
	if single_line:
		text = text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	else:
		text = text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while "  " in text:
		text = text.replace("  ", " ")
	return text.left(limit)


static func _safe_id(value: String) -> String:
	var clean := ""
	var lower := value.to_lower()
	for i in lower.length():
		var character := lower.substr(i, 1)
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			clean += character
		elif character in " -":
			clean += "_"
	while "__" in clean:
		clean = clean.replace("__", "_")
	return clean.trim_prefix("_").trim_suffix("_").left(32)


static func _make_part_ids_unique(parts: Array[Dictionary]) -> void:
	var used: Array[String] = []
	for i in parts.size():
		var base := str(parts[i].get("id", "part_%02d" % (i + 1)))
		var candidate := base
		var suffix := 2
		while candidate in used:
			candidate = "%s_%d" % [base.left(27), suffix]
			suffix += 1
		parts[i]["id"] = candidate
		used.append(candidate)


static func _valid_id(value: String, valid: Array, fallback: String) -> String:
	return value if value in valid else fallback


## Alte Studio-/Player-Bezeichnungen werden beim Laden auf die stabilen IDs
## abgebildet. So bleiben bereits gespeicherte Drafts erhalten, ohne dass neue
## Projekte mehrere Namen fuer denselben Effekt mitschleppen.
static func _canonical_effect_id(value: String) -> String:
	var key := value.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	match key:
		"stars": return "starfield"
		"copper", "copper_bars": return "copperbars"
		"vector", "grid", "vector_grid": return "vectorgrid"
		"shade_bobs": return "shadebobs"
		"sinescroller", "sinus_scroller": return "sine_scroller"
		"raster", "raster_bars", "rasterbars": return "rasterbars"
		"rotozoom", "roto_zoom", "rotozoomer": return "rotozoomer"
		"twister", "line_twist", "line_twister": return "line_twister"
		"moire", "moiré", "moire_rings": return "moire_rings"
		_: return _valid_id(key, EFFECT_IDS, "starfield")


static func _canonical_transition_id(value: String) -> String:
	var key := value.to_lower().strip_edges().replace("-", "_").replace(" ", "_")
	match key:
		"crossfade", "fade_in": return "fade"
		"wipe_left": return "wipe"
		"dissolve": return "checker"
		"curtains": return "curtain"
		"white_flash": return "flash"
		"none": return "cut"
		_: return _valid_id(key, TRANSITION_IDS, "cut")


static func _ordered_ids(values: Array[String], order: Array) -> Array[String]:
	var result: Array[String] = []
	for value: String in order:
		if value in values:
			result.append(value)
	return result


static func _add_unique(values: Array[String], value: String) -> void:
	if value not in values:
		values.append(value)


static func _stable_hash(project: Dictionary) -> String:
	return JSON.stringify(project).sha256_text().left(16)
