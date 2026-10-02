class_name ProgramAliases
extends RefCounted
## Stabile Bruecke fuer alte Saves und Questdaten. Neue Installationen benutzen
## die Sommer-Namen; historische interne IDs bleiben weiterhin abfragbar.

const ALIASES := {
	"amos_homage": "sommer_basic",
	"blitzbasic_homage": "sommer_basic_compiler_ii",
}


static func canonical(program_id: String) -> String:
	return str(ALIASES.get(program_id, program_id))


static func equivalent(left: String, right: String) -> bool:
	return canonical(left) == canonical(right)
