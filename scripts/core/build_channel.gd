class_name Sommer90BuildChannel
extends RefCounted
## Zentraler, unveraenderlicher Distributionsvertrag.
##
## Export-Presets setzen `itch_demo`; lokale QA kann denselben Pfad mit
## DSS_ITCH_DEMO=1 pruefen. Gameplay-Code fragt ausschliesslich diese Fassade
## ab, damit Vollversion, Demo und Tests nicht durch verstreute Schalter
## auseinanderlaufen.

const FULL_CHANNEL := "full"
const ITCH_DEMO_CHANNEL := "itch_demo_1990"
const DEMO_FEATURE := "itch_demo"
const DEMO_ENV := "DSS_ITCH_DEMO"
const FULL_VERSION_URL_SETTING := "application/config/full_version_url"
const FIRST_YEAR := 1990


static func is_first_year_demo() -> bool:
	return OS.has_feature(DEMO_FEATURE) or OS.get_environment(DEMO_ENV) == "1"


static func channel_id() -> String:
	return ITCH_DEMO_CHANNEL if is_first_year_demo() else FULL_CHANNEL


static func save_stem() -> String:
	return "demo_1990_savegame" if is_first_year_demo() else "savegame"


static func accepts_save_channel(saved_channel: String) -> bool:
	var normalized := saved_channel.strip_edges()
	if normalized.is_empty():
		normalized = FULL_CHANNEL # Spielstaende vor dem Buildkanal-Feld.
	return normalized == channel_id()


static func ends_after_year(year: int) -> bool:
	return is_first_year_demo() and year >= FIRST_YEAR


static func full_version_url() -> String:
	return str(ProjectSettings.get_setting(FULL_VERSION_URL_SETTING,
		"https://sommer90.vibechain.rocks/")).strip_edges()


static func display_name() -> String:
	return "Sommer '90 · 1990 DEMO" if is_first_year_demo() else "Sommer '90"
