extends RefCounted
## Kanonische, zustandslose Projektmodus-Metadaten des Szene-Studios.
##
## Das Fenster und sein Controller lesen dieselben IDs, Texte und Modulprofile
## aus diesem Katalog. Mutierender Projektzustand bleibt bewusst im Controller;
## dadurch behalten dessen bestehende Adaptermethoden ihren Vertrag.

const MODE_IDS: Array[String] = ["demo", "club_intro", "game"]

const RECOMMENDED_MODULES := {
	"demo": ["part_loader", "music_irq", "copperlist", "blitter", "scroller", "precalc_tables"],
	"club_intro": ["boot_init", "vblank_irq", "music_irq", "copperlist", "scroller"],
	"game": ["memory_map", "vblank_irq", "blitter", "sprite_mux", "double_buffer"],
}

const FALLBACK_TITLES := {
	"demo": "UNTITLED DEMO",
	"club_intro": "UNTITLED INTRO",
	"game": "UNTITLED GAME",
}


static func is_valid(kind: String) -> bool:
	return kind in MODE_IDS


static func normalize(kind: String) -> String:
	return kind if is_valid(kind) else "demo"


static func fallback_title(kind: String) -> String:
	return str(FALLBACK_TITLES[normalize(kind)])


static func is_module_recommended(kind: String, module_id: String) -> bool:
	return module_id in RECOMMENDED_MODULES[normalize(kind)]


static func button_definitions() -> Array[Dictionary]:
	return [
		{
			"id": "demo",
			"label": "◆  %s\nTIMELINE · FX · TRACKMO" % Loc.t(
				"ui.demo_maker_window.mode_demo_scene", "DEMO-SZENE"),
		},
		{
			"id": "club_intro",
			"label": "*  %s\nIDENT · GREETINGS · 32 SEK." % Loc.t(
				"ui.demo_maker_window.mode_club_intro", "CLUB-INTRO"),
		},
		{
			"id": "game",
			"label": "▣  %s\nREGELN · LOOP · PLAYTEST" % Loc.t(
				"ui.demo_maker_window.mode_game", "SPIEL-PROTOTYP"),
		},
	]


static func description(kind: String) -> String:
	match normalize(kind):
		"club_intro":
			return Loc.t("ui.demo_maker_window.mode_intro_desc",
				"Club-Intro: kurze Dramaturgie, sichtbare Handle-Credits und gemeinsame Abnahme.")
		"game":
			return Loc.t("ui.demo_maker_window.mode_game_desc",
				"Spiel-Prototyp: Regeln wählen, spielbaren QA-Lauf bestehen und erst dann releasen.")
		_:
			return Loc.t("ui.demo_maker_window.mode_demo_desc",
				"Freie Demoszene: Parts arrangieren, Effekte stapeln, Build testen und als Demo releasen.")


static func tab_titles(kind: String) -> Array[String]:
	match normalize(kind):
		"club_intro":
			return [
				Loc.t("ui.demo_maker_window.tab_intro_timing", "01 · INTRO & TIMING"),
				Loc.t("ui.demo_maker_window.tab_intro_code", "02 · INTRO-CODE"),
				Loc.t("ui.demo_maker_window.tab_intro_review", "03 · CLUB-ABNAHME"),
			]
		"game":
			return [
				Loc.t("ui.demo_maker_window.tab_game_intro", "01 · SPIEL-INTRO"),
				Loc.t("ui.demo_maker_window.tab_game_code", "02 · GAME-CODE"),
				Loc.t("ui.demo_maker_window.tab_game_release", "03 · SPIELTEST & RELEASE"),
			]
		_:
			return [
				Loc.t("ui.demo_maker_window.tab_demo_scene", "01 · SZENE & TIMING"),
				Loc.t("ui.demo_maker_window.tab_demo_code", "02 · CODE & BUILD"),
				Loc.t("ui.demo_maker_window.tab_demo_release", "03 · QA & RELEASE"),
			]


static func part_context(kind: String) -> String:
	match normalize(kind):
		"club_intro":
			return "INTRO-BOARD · Ident, Greetings und Absender in maximal 32 Sekunden auf den Punkt bringen."
		"game":
			return "GAME-DESIGN · Titel, spielbarer Loop und Ergebnisbild als nachvollziehbare Zustände bauen."
		_:
			return "DEMO-DESIGN · Dramaturgie, Effektlagen und Beat-Sync als durchgehende PAL-Timeline."


static func code_context(kind: String) -> String:
	match normalize(kind):
		"club_intro":
			return "INTRO-LINKER · Schneller Boot, lesbare Credits und saubere Übergabe an den Hauptinhalt."
		"game":
			return "GAME-ENGINE · Eingabe, Sprites, Kollision, Regeln und HUD zu einem testbaren Build verbinden."
		_:
			return "DEMO-ENGINE · Copper, Blitter, Scroller und Loader innerhalb des OCS-Budgets verdrahten."


static func release_context(kind: String) -> String:
	match normalize(kind):
		"club_intro":
			return Loc.t("ui.demo_maker_window.release_intro_desc",
				"INTRO · Rolle und Handle-Credits werden gemeinsam geprüft; kein Spieltest erforderlich.")
		"game":
			return Loc.t("ui.demo_maker_window.release_game_desc",
				"SPIEL · Wähle Regeln und bestehe den spielbaren Prototyp-Test vor dem Freeze.")
		_:
			return Loc.t("ui.demo_maker_window.release_demo_desc",
				"DEMO · Szenequalität, Timing, Synchronität und Credits entscheiden über den Release.")
