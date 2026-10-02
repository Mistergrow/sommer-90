class_name SceneAnimatorPresentationCatalog
extends RefCounted
## Zustandslose Praesentationsregeln des HUD-Scene-Animators. Der Renderer
## entscheidet weiterhin ueber Pixel und Bewegung; Generation, Titelmodus und
## technische Anzeigen besitzen hier einen einzigen kanonischen Vertrag.

const SceneCatalog := preload("res://scripts/ui/scene_generation_catalog.gd")


static func generation_visual_profile(chipset: String) -> Dictionary:
	var generation_id := chipset.to_lower()
	if generation_id not in SceneCatalog.GENERATION_ORDER:
		generation_id = str({"OCS": "ocs", "ECS": "ecs", "AGA": "aga"}.get(
			chipset.to_upper(), "ocs"))
	var definition := SceneCatalog.generation(generation_id)
	return {
		"id": generation_id,
		"title": str(definition.get("label", "OCS CLASSIC")),
		"layers": int(definition.get("layers", 1)),
		"palette_bits": int(definition.get("palette_bits", 12)),
		"color_registers": int(definition.get("color_registers", 32)),
		"bitplanes": int(definition.get("bitplanes", 5)),
		"display_mode": str(definition.get("display_mode", "")),
		"band_cap": int(definition.get("band_cap", 12)),
		"summary": str(definition.get("summary", "")),
		"backdrop": str(definition.get("backdrop", "")),
	}


static func primary_presentation(state: Dictionary, status: Dictionary) -> Dictionary:
	var source_kind := str(state.get("source_kind", ""))
	if source_kind == "external" and bool(state.get("active", true)):
		var game_title := str(state.get("title", "")).strip_edges()
		return {"kind": "game",
			"text": game_title.to_upper() if game_title != "" else Loc.t(
				"scene.presentation.amiga_game", "AMIGA-SPIEL")}
	if bool(state.get("playing", false)):
		var title := str(state.get("title", "")).strip_edges()
		var artist := str(state.get("artist", "")).strip_edges()
		var heading := title.to_upper() if title != "" else Loc.t(
			"scene.presentation.mod_signal", "MOD-SIGNAL")
		if artist != "":
			heading += " — " + artist.to_upper()
		return {"kind": "music", "text": heading}
	return {"kind": "idle", "text": Loc.t_format(
		"scene.presentation.season_year", "SOMMER '%02d",
		[int(status.get("year", 1990)) % 100])}


static func music_technical_summary(state: Dictionary) -> String:
	if bool(state.get("tracker", false)):
		var view: Dictionary = {}
		var player = MusicManager.native_player()
		if player != null:
			view = player.playback_view(1)
		return Loc.t_format("scene.presentation.channels_bpm", "4-KANAL · %03d BPM",
			[int(view.get("bpm", 125))])
	var source := str(state.get("source_label", Loc.t(
		"scene.presentation.game", "SPIEL"))).strip_edges().to_upper()
	return Loc.t("scene.presentation.audio", "AUDIO") if source == "" else source


static func title_motion_profile(upgrade_level: int, chipset: String = "OCS") -> Dictionary:
	if upgrade_level <= 0:
		return {"id": "static", "speed": 0.0, "wave": 0.0, "trails": 0}
	if chipset == "ECS":
		return {"id": "ecs_sine_scroll", "speed": 31.0 + upgrade_level * 2.0,
			"wave": 2.2 + float(upgrade_level - 2) * 0.55,
			"wave_secondary": 0.7, "beat_wave": 0.9,
			"trails": 1 + int(upgrade_level >= 3), "chroma": false}
	if chipset == "AGA":
		return {"id": "aga_dual_sine", "speed": 39.0 + upgrade_level * 2.5,
			"wave": 3.5 + float(upgrade_level - 2) * 0.6,
			"wave_secondary": 1.8, "beat_wave": 1.5,
			"trails": 3, "chroma": true}
	if upgrade_level == 1:
		return {"id": "ocs_copper_scroll", "speed": 22.0,
			"wave": 0.45, "wave_secondary": 0.0,
			"beat_wave": 0.35, "trails": 0, "chroma": false}
	if upgrade_level == 2:
		return {"id": "scene_scroll", "speed": 26.0,
			"wave": 0.75, "wave_secondary": 0.0,
			"beat_wave": 0.45, "trails": 0, "chroma": false}
	if upgrade_level == 3:
		return {"id": "raster_scroll", "speed": 34.0, "wave": 0.0, "trails": 2}
	return {"id": "sine_scroll", "speed": 42.0,
		"wave": minf(3.5, 1.8 + float(upgrade_level - 4) * 0.35), "trails": 2}


static func effect_label(id: String, visible_bands: int) -> String:
	if id == "equalizer":
		return Loc.t_format("scene.presentation.band_scene_eq", "%d-BAND SZENEN-EQ",
			[visible_bands])
	return SceneCatalog.effect_name(id)
