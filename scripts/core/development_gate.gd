extends RefCounted
## Eine einzige verbindliche Grenze fuer interne Entwicklungswerkzeuge.
## Produktions-Exports tragen das Feature `sommer90_production`; dort kann
## weder ein Debug-Build noch eine Umgebungsvariable die Werkzeuge aktivieren.

const PRODUCTION_FEATURE := "sommer90_production"
const FORCE_PRODUCTION_ENV := "SOMMER90_FORCE_PRODUCTION"
const FORCE_DEVELOPMENT_ENV := "SOMMER90_DEV_TOOLS"


static func enabled() -> bool:
	if OS.has_feature(PRODUCTION_FEATURE):
		return false
	if OS.get_environment(FORCE_PRODUCTION_ENV) == "1":
		return false
	if OS.get_environment(FORCE_DEVELOPMENT_ENV) == "1":
		return true
	return OS.has_feature("editor") or OS.is_debug_build()
