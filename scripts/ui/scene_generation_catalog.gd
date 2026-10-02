class_name SceneGenerationCatalog
extends RefCounted
## Single Source of Truth fuer Scene-Generationen, abwaertskompatible Rechner
## und die 24 musikreaktiven Presets des oberen HUD-Studios. AGA ist dabei die
## sichtbar umfangreichste Stufe: zehn eigene Renderer plus alle OCS/ECS-Modi.

const GENERATION_ORDER: Array[String] = ["ocs", "ecs", "aga"]
const GENERATIONS := {
	"ocs": {
		"label": "OCS CLASSIC",
		"chipset": "OCS",
		"era": "A500 · 1985–1991",
		"backdrop": "res://assets/ui/scene/SCENE_BACKDROP_OCS_V01.png",
		"accent": Color8(244, 174, 48),
		"layers": 1,
		"palette_bits": 12,
		"color_registers": 32,
		"bitplanes": 5,
		"display_mode": "32 Farben · Copper · Blitter",
		"band_cap": 12,
		"summary": "Copper-Takt · klassischer Scrolltext · 12-Band-Signal",
	},
	"ecs": {
		"label": "ECS ENHANCED",
		"chipset": "ECS",
		"era": "A600 · 1992–1993",
		"backdrop": "res://assets/ui/scene/SCENE_BACKDROP_ECS_V01.png",
		"accent": Color8(57, 222, 232),
		"layers": 2,
		"palette_bits": 12,
		"color_registers": 32,
		"bitplanes": 6,
		"display_mode": "EHB · Super-Hires · Dual-Playfield",
		"band_cap": 24,
		"summary": "Sinus-Schrift · doppelte Rasterlage · 24-Band-Signal",
	},
	"aga": {
		"label": "AGA ADVANCED",
		"chipset": "AGA",
		"era": "A1200 · ab 1992",
		"backdrop": "res://assets/ui/scene/SCENE_BACKDROP_AGA_V01.png",
		"accent": Color8(241, 88, 194),
		"layers": 8,
		"palette_bits": 24,
		"color_registers": 256,
		"bitplanes": 8,
		"display_mode": "256 Farben · HAM8 · 64px-Sprites",
		"band_cap": 32,
		"summary": "256 Register · HAM8 · 8 Bitplanes · 32-Band-Signal",
	},
}

const EFFECTS := [
	{"id": "equalizer", "name": "KLASSISCHER SCENE EQ", "generation": "ocs",
		"condition": "Startstil"},
	{"id": "mirror", "name": "SPIEGEL-SPEKTRUM", "generation": "ocs",
		"condition": "Startstil"},
	{"id": "copper", "name": "COPPERBARS", "generation": "ocs",
		"condition": "Hardware-Ausbau 3"},
	{"id": "starfield", "name": "STERNENFLUG", "generation": "ocs",
		"condition": "Hardware-Ausbau 2"},
	{"id": "raster", "name": "RASTERWELLE", "generation": "ocs",
		"condition": "Ruf 10"},
	{"id": "vu", "name": "4-KANAL VU-RACK", "generation": "ocs",
		"condition": "Ruf 5"},
	{"id": "vector", "name": "VEKTORGITTER", "generation": "ocs",
		"condition": "erstes BYTEWERK-Release"},
	{"id": "plasma", "name": "OCS-PLASMA", "generation": "ocs",
		"condition": "Computerclub-Mitglied"},
	{"id": "scope", "name": "4-KANAL-SCOPE", "generation": "ocs",
		"condition": "erster eigener MOD"},
	{"id": "waterfall", "name": "SPEKTRAL-WASSERFALL", "generation": "ecs",
		"condition": "Hardware-Ausbau 2"},
	{"id": "dots", "name": "DOT-MATRIX", "generation": "ecs",
		"condition": "drei MODs gesammelt"},
	{"id": "skyline", "name": "NEON-SKYLINE", "generation": "ecs",
		"condition": "ab 1992"},
	{"id": "tunnel", "name": "BEAT-TUNNEL", "generation": "ecs",
		"condition": "drei Scene-Releases · Ausbau 3"},
	{"id": "sinebars", "name": "ECS-SINUSBÄNDER", "generation": "ecs",
		"condition": "ECS-Modus"},
	{"id": "bobs", "name": "AGA SHADE-BOBS", "generation": "aga",
		"condition": "ab 1994 · Ausbau 4"},
	{"id": "chroma", "name": "AGA-CHROMAFELD", "generation": "aga",
		"condition": "AGA-Modus"},
	{"id": "ham_ribbons", "name": "HAM8-REGENBOGEN", "generation": "aga",
		"condition": "AGA-Modus"},
	{"id": "sprite_multiplex", "name": "SPRITE-MULTIPLEX", "generation": "aga",
		"condition": "AGA-Modus · 2 MB Chip-RAM"},
	{"id": "parallax", "name": "PARALLAX-NEBEL", "generation": "aga",
		"condition": "ab 1993"},
	{"id": "metaballs", "name": "METABALL-LABOR", "generation": "aga",
		"condition": "ab 1994 · Ausbau 4"},
	{"id": "firestorm", "name": "FIRESTORM", "generation": "aga",
		"condition": "ab 1994 · Ruf 40"},
	{"id": "texture_tunnel", "name": "TEXTURE-TUNNEL", "generation": "aga",
		"condition": "ab 1995 · Ausbau 5"},
	{"id": "voxel_city", "name": "VOXEL-CITY", "generation": "aga",
		"condition": "ab 1995 · drei Releases"},
	{"id": "particle_logo", "name": "PARTIKEL-LOGO", "generation": "aga",
		"condition": "ab 1996 · Ausbau 6"},
]


static func generation_rank(id: String) -> int:
	return GENERATION_ORDER.find(id.to_lower())


static func generation(id: String) -> Dictionary:
	var generation_id := id.to_lower()
	if not GENERATIONS.has(generation_id):
		generation_id = "ocs"
	var result := (GENERATIONS[generation_id] as Dictionary).duplicate(true)
	for field in ["label", "era", "display_mode", "summary"]:
		result[field] = Loc.t("scene.generation.%s.%s" % [generation_id, field],
			str(result.get(field, "")))
	return result


static func native_generation(model: String, hardware: Dictionary = {}) -> String:
	if model == "amiga_1200":
		return "aga"
	if model in ["amiga_600", "amiga_500_plus"]:
		return "ecs"
	if bool(hardware.get("chipram_2mb_mod", false)) \
			or str(hardware.get("agnus_model", "")) == "agnus_ecs":
		return "ecs"
	return "ocs"


static func current_native_generation() -> String:
	return native_generation(
		str(PlayerStats.desk_model("computer_model")),
		PlayerStats.hardware)


static func supported_generations(native_id := "") -> Array[String]:
	var maximum := native_id if not native_id.is_empty() else current_native_generation()
	var rank := maxi(0, generation_rank(maximum))
	return GENERATION_ORDER.slice(0, rank + 1)


static func effective_generation(requested := "", native_id := "") -> String:
	var maximum := native_id if not native_id.is_empty() else current_native_generation()
	var wanted := requested if not requested.is_empty() \
		else str(SettingsManager.value("hud_scene_generation"))
	if wanted == "auto" or generation_rank(wanted) < 0:
		return maximum
	return wanted if generation_rank(wanted) <= generation_rank(maximum) else maximum


static func effect_definition(id: String) -> Dictionary:
	for definition: Dictionary in EFFECTS:
		if str(definition["id"]) == id:
			return definition.duplicate(true)
	return {}


static func effect_name(id: String) -> String:
	return Loc.t("scene.effect.%s.name" % id,
		str(effect_definition(id).get("name", id.to_upper())))


static func effect_condition(id: String) -> String:
	return Loc.t("scene.effect.%s.condition" % id,
		str(effect_definition(id).get("condition", Loc.t(
			"scene.effect.locked", "noch gesperrt"))))


static func effect_generation(id: String) -> String:
	return str(effect_definition(id).get("generation", "ocs"))


static func effect_state(id: String, active_generation := "") -> Dictionary:
	var definition := effect_definition(id)
	if definition.is_empty():
		return {"unlocked": false, "reason": Loc.t(
			"scene.effect.unknown", "Unbekannter Szene-Effekt")}
	var generation_id := effective_generation() if active_generation.is_empty() \
		else active_generation
	var required := str(definition.get("generation", "ocs"))
	if generation_rank(required) > generation_rank(generation_id):
		return {"unlocked": false,
			"reason": Loc.t("scene.effect.requires_generation",
				"%s-Modus erforderlich") % required.to_upper(),
			"generation_locked": true}
	var progress := _progress_state(id)
	if not bool(progress.get("unlocked", false)):
		return progress
	return {"unlocked": true, "reason": "", "generation_locked": false}


static func _progress_state(id: String) -> Dictionary:
	var unlocked := true
	match id:
		"copper": unlocked = PlayerStats.hardware_level() >= 3
		"starfield", "waterfall": unlocked = PlayerStats.hardware_level() >= 2
		"raster": unlocked = PlayerStats.ruf >= 10
		"vu": unlocked = PlayerStats.ruf >= 5
		"dots": unlocked = MusicManager.owned.size() >= 3
		"vector": unlocked = not SceneReleaseManager.releases.is_empty()
		"skyline": unlocked = TimeManager.year >= 1992
		"tunnel":
			unlocked = SceneReleaseManager.releases.size() >= 3 \
				and PlayerStats.hardware_level() >= 3
		"bobs":
			unlocked = TimeManager.year >= 1994 and PlayerStats.hardware_level() >= 4
		"ham_ribbons": unlocked = true
		"sprite_multiplex":
			unlocked = int(PlayerStats.ram_breakdown().get("chip_kb", 0)) >= 2048
		"parallax": unlocked = TimeManager.year >= 1993
		"metaballs":
			unlocked = TimeManager.year >= 1994 and PlayerStats.hardware_level() >= 4
		"firestorm": unlocked = TimeManager.year >= 1994 and PlayerStats.ruf >= 40
		"texture_tunnel":
			unlocked = TimeManager.year >= 1995 and PlayerStats.hardware_level() >= 5
		"voxel_city":
			unlocked = TimeManager.year >= 1995 and SceneReleaseManager.releases.size() >= 3
		"particle_logo":
			unlocked = TimeManager.year >= 1996 and PlayerStats.hardware_level() >= 6
		"plasma": unlocked = bool(GameManager.flags.get("club_member", false))
		"scope": unlocked = not MusicManager.owned.is_empty()
		_: unlocked = true
	return {"unlocked": unlocked,
		"reason": "" if unlocked else effect_condition(id),
		"generation_locked": false}


static func unlocked_effects(active_generation := "") -> Array[String]:
	var result: Array[String] = []
	var generation_id := effective_generation() if active_generation.is_empty() \
		else active_generation
	for definition: Dictionary in EFFECTS:
		var id := str(definition["id"])
		if bool(effect_state(id, generation_id).get("unlocked", false)):
			result.append(id)
	return result


static func effect_count(generation_id := "") -> int:
	if generation_id.is_empty():
		return EFFECTS.size()
	var count := 0
	for definition: Dictionary in EFFECTS:
		if str(definition.get("generation", "ocs")) == generation_id:
			count += 1
	return count


static func effect_setting_key(generation_id: String) -> String:
	return "hud_scene_effect_%s" % generation_id


static func selected_effect(generation_id := "") -> String:
	var effective := effective_generation() if generation_id.is_empty() else generation_id
	var selected := str(SettingsManager.value(effect_setting_key(effective)))
	if selected.is_empty():
		# Das alte globale Feld bleibt fuer echte Alt-Auswahlen kompatibel.
		# Sein historischer Standard "equalizer" darf ECS/AGA jedoch nicht um
		# ihren sichtbaren Generationssprung bringen.
		var legacy := str(SettingsManager.value("hud_scene_effect"))
		if effective == "ocs" or legacy != "equalizer":
			selected = legacy
	if bool(effect_state(selected, effective).get("unlocked", false)):
		return selected
	var fallback := str({"ocs": "equalizer", "ecs": "sinebars", "aga": "chroma"}.get(
		effective, "equalizer"))
	if bool(effect_state(fallback, effective).get("unlocked", false)):
		return fallback
	var unlocked := unlocked_effects(effective)
	return unlocked[0] if not unlocked.is_empty() else "equalizer"


static func select_effect(id: String, generation_id := "") -> bool:
	var effective := effective_generation() if generation_id.is_empty() else generation_id
	if not bool(effect_state(id, effective).get("unlocked", false)):
		return false
	SettingsManager.set_value(effect_setting_key(effective), id)
	return true
