class_name DanielLessonCatalog
extends RefCounted
## Eine Datenquelle fuer Daniels Jahrescurriculum, Queststufen und Zimmeraktion.

const CONFIG := "res://data/daniel_lessons.json"
const FIRST_YEAR := 1991
const LAST_YEAR := 1999

static var _loaded := false
static var _years: Dictionary = {}


static func reload() -> void:
	_loaded = true
	_years = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if parsed is Dictionary:
		_years = (parsed as Dictionary).get("years", {})
	else:
		push_error("DanielLessonCatalog: %s ist ungueltig." % CONFIG)


static func _ensure() -> void:
	if not _loaded:
		reload()


static func year_definition(year: int) -> Dictionary:
	_ensure()
	return (_years.get(str(year), {}) as Dictionary).duplicate(true)


## Spielerfertige Sicht auf ein Jahresprojekt. Die JSON-Datei bleibt dabei die
## deutsche Autorenquelle; Fenster erhalten niemals rohe, sprachgebundene Texte.
static func localized_lesson(year: int, index: int, lesson: Dictionary) -> Dictionary:
	var out := lesson.duplicate(true)
	out["title"] = Loc.t("lesson.%d.p%d.title" % [year, index + 1],
		str(lesson.get("title", "Programmierprojekt")))
	out["brief"] = Loc.t("lesson.%d.p%d.brief" % [year, index + 1],
		str(lesson.get("brief", "")))
	return out


static func quest_id(year: int) -> String:
	return "q_daniel_lab_%d" % year


static func action(year: int, stage: int) -> String:
	return "daniel_lesson:%d:%d" % [year, stage + 1]


static func quest_definitions() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for year in range(FIRST_YEAR, LAST_YEAR + 1):
		var definition := year_definition(year)
		var lessons: Array = definition.get("lessons", [])
		var stages: Array[Dictionary] = []
		var lesson_titles: Array[String] = []
		for index in lessons.size():
			var lesson: Dictionary = lessons[index]
			lesson_titles.append(str(lesson.get("title", "Programmierprojekt")))
			stages.append({
				"desc": "Orte → Daniels Zimmer → Computertisch. Besuche Daniel an einem neuen Tag und bearbeite Projekt %d/3: %s." \
					% [index + 1, str(lesson.get("title", "Programmierprojekt"))],
				"map_location": "daniel_home",
				"goal": {"action": action(year, index)},
			})
		out.append({
			"id": quest_id(year),
			"title": "Daniels Jahreslabor: %s" % str(definition.get("title", year)),
			"localization_context": {"family": "daniel_lab", "year": year,
				"lesson_titles": lesson_titles},
			"giver": "npc_daniel",
			# Daniels Jahresprojekt wird im Planjahr freigeschaltet, darf aber in
			# spaeteren Sommern nachgeholt werden. Das entspricht dem globalen
			# Story-Backlog und heilt uebersprungene Altspielstaende.
			"prereq": {"year_min": year},
			"on_start": [{"type": "toast",
				"text": Loc.t("misc.daniel_lesson_catalog.daniel_hat_drei_aufeinander_aufbauende_projekte", "Daniel hat drei aufeinander aufbauende Projekte vorbereitet. Öffne Orte → Daniels Zimmer und klick dort den Computertisch an; pro neuem Tag geht ein Projekt."),
				"text_key": "quest.dynamic.daniel_lab.start",
				"text_source": "Daniel hat drei aufeinander aufbauende Projekte vorbereitet. Öffne Orte → Daniels Zimmer und klick dort den Computertisch an; pro neuem Tag geht ein Projekt."}],
			"stages": stages,
			"reward": [
				{"type": "stat", "stat": "wissen", "value": 2},
				{"type": "npc_trust", "npc": "npc_daniel", "value": 3},
				{"type": "flag", "flag": "daniel_curriculum_%d_complete" % year, "value": true},
				{"type": "memory_once", "id": "daniel_curriculum_%d" % year,
					"title": "Daniels Jahreslabor %d" % year,
					"title_key": "quest.dynamic.daniel_lab.memory_title",
					"title_source": "Daniels Jahreslabor %d", "title_args": [year],
					"text": "mit Daniel drei aufeinander aufbauende Programmierprojekte des Sommers %d abgeschlossen" % year,
					"text_key": "quest.dynamic.daniel_lab.memory_text",
					"text_source": "mit Daniel drei aufeinander aufbauende Programmierprojekte des Sommers %d abgeschlossen",
					"text_args": [year]},
				{"type": "toast",
					"text": Loc.t("misc.daniel_lesson_catalog.drei_projekttage_sauberer_ausdruck_daniels_curriculum", "Drei Projekttage, ein sauberer Ausdruck: Daniels Curriculum %d ist abgeschlossen.") % year,
					"text_key": "misc.daniel_lesson_catalog.drei_projekttage_sauberer_ausdruck_daniels_curriculum",
					"text_source": "Drei Projekttage, ein sauberer Ausdruck: Daniels Curriculum %d ist abgeschlossen.",
					"text_args": [year]},
			],
			"quest_family": "daniel_curriculum",
		})
	return out


static func _autoload(name: String) -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath("/root/" + name))


## Gerade offene Lektion. Das aktuelle Curriculum hat Vorrang, damit ein alter
## Save nicht jahrelang hinter verpassten Sommern festhaengt. Offene Vorjahre
## bleiben danach als freiwilliger Backlog erreichbar und gehen nicht verloren.
static func active_lesson() -> Dictionary:
	_ensure()
	var quests := _autoload("QuestManager")
	if quests == null:
		return {}
	var time := _autoload("TimeManager")
	var current_year := clampi(int(time.get("year")) if time != null else FIRST_YEAR,
		FIRST_YEAR, LAST_YEAR)
	var years: Array[int] = [current_year]
	for year in range(current_year - 1, FIRST_YEAR - 1, -1):
		years.append(year)
	for year in range(current_year + 1, LAST_YEAR + 1):
		years.append(year)
	for year: int in years:
		var id := quest_id(year)
		if not bool(quests.call("is_active", id)):
			continue
		var index := int(quests.call("stage", id))
		var lessons: Array = year_definition(year).get("lessons", [])
		if index < 0 or index >= lessons.size():
			continue
		var lesson: Dictionary = localized_lesson(year, index, lessons[index] as Dictionary)
		lesson["year"] = year
		lesson["stage"] = index
		lesson["quest_id"] = id
		lesson["action"] = action(year, index)
		return lesson
	return {}


static func validate() -> Array[String]:
	_ensure()
	var issues: Array[String] = []
	for year in range(FIRST_YEAR, LAST_YEAR + 1):
		var definition := year_definition(year)
		var lessons: Array = definition.get("lessons", [])
		if lessons.size() != 3:
			issues.append("%d benoetigt exakt drei Lektionen." % year)
		for lesson: Dictionary in lessons:
			if str(lesson.get("title", "")).is_empty() or str(lesson.get("brief", "")).is_empty():
				issues.append("%d enthaelt eine unvollstaendige Lektion." % year)
	return issues
