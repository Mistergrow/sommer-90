class_name QuestTextService
extends RefCounted
## Eine einzige, UI-neutrale Sprachgrenze fuer Questdefinitionen. Der Service
## besitzt keinen Questzustand und kann deshalb von Notizblock, HUD, Tests und
## Save-Heilung benutzt werden, ohne einen zweiten Textpfad zu erzeugen.

const SommerGameQuests := preload("res://scripts/data/sommer_game_quest_catalog.gd")
const TEXT_FIELDS := ["recovery_text", "protect_text", "blocked_text",
	"required_music_text", "memory"]
const TEXT_COLLECTIONS := ["required_disks", "required_items", "required_programs"]


static func title(q: Dictionary, id: String) -> String:
	if q.is_empty():
		return id
	var source := str(q.get("title", id))
	var context: Dictionary = q.get("localization_context", {})
	match str(context.get("family", "")):
		"stefan_game":
			return Loc.t("quest.dynamic.stefan_game.title", "Stefans Spielwunsch: %s") \
				% str(context.get("title", "?"))
		"daniel_lab":
			return Loc.t("quest.dynamic.daniel_lab.title", "Daniels Jahreslabor %d") \
				% int(context.get("year", TimeManager.year))
		"stefan_moment":
			var moment_id := str(context.get("moment_id", ""))
			var moment_title := Loc.t("story.stefan_moment.%s.title" % moment_id,
				source.trim_prefix("Mit Stefan: "))
			return Loc.t("quest.dynamic.stefan_moment.title", "Mit Stefan: %s") % moment_title
		"sommer_game":
			return SommerGameQuests.localized_text(str(context.get("title_de", source)),
				str(context.get("title_en", source)))
	return Loc.t("quest.%s.title" % id, source)


static func stage_text(q: Dictionary, id: String, stage_index: int) -> String:
	var stages: Array = q.get("stages", [])
	if stage_index < 0 or stage_index >= stages.size():
		return ""
	var source := str((stages[stage_index] as Dictionary).get("desc", ""))
	var context: Dictionary = q.get("localization_context", {})
	match str(context.get("family", "")):
		"stefan_game":
			var game_title := str(context.get("title", "?"))
			var software_id := str(context.get("software_id", ""))
			var objective_source := str(context.get("objective", "Mission erfolgreich abschließen"))
			var objective := Loc.t("disk.%s.objective" % software_id, objective_source)
			var templates := [
				Loc.t("quest.dynamic.stefan_game.stage0", "BESORGEN — Finde das Original von %s auf dem Flohmarkt. Krause reserviert es während dieses Auftrags für dich."),
				Loc.t("quest.dynamic.stefan_game.stage1", "TESTEN — Starte %s zu Hause am Amiga. SPIELZIEL: %s. Der Ergebnisbildschirm registriert den Sieg."),
				Loc.t("quest.dynamic.stefan_game.stage2", "KOPIEREN — Behalte das Original und erstelle mit X-COPY eine eigene Arbeitskopie von %s auf einer Leerdiskette."),
				Loc.t("quest.dynamic.stefan_game.stage3", "ÜBERGEBEN — Bring Stefan die selbst erstellte Arbeitskopie von %s persönlich in sein Zimmer."),
			]
			if stage_index >= templates.size():
				return source
			return str(templates[stage_index]) % [game_title, objective] if stage_index == 1 \
				else str(templates[stage_index]) % game_title
		"daniel_lab":
			var lesson_titles: Array = context.get("lesson_titles", [])
			var year := int(context.get("year", TimeManager.year))
			var lesson_source := str(lesson_titles[stage_index]) if stage_index < lesson_titles.size() \
				else "Programmierprojekt"
			var lesson_title := Loc.t("lesson.%d.p%d.title" % [year, stage_index + 1], lesson_source)
			return Loc.t("quest.dynamic.daniel_lab.stage", "Orte → Daniels Zimmer → Computertisch. Besuche Daniel an einem neuen Tag und bearbeite Projekt %d/3: %s.") \
				% [stage_index + 1, lesson_title]
		"stefan_moment":
			return Loc.t("quest.dynamic.stefan_moment.stage", "Besuche Stefan und entscheidet gemeinsam, was dieser Sommer für euch verändert.")
		"sommer_game":
			var quotes_de: Array = context.get("quotes_de", [])
			var quotes_en: Array = context.get("quotes_en", [])
			var quote_de := str(quotes_de[stage_index]) if stage_index < quotes_de.size() else source
			var quote_en := str(quotes_en[stage_index]) if stage_index < quotes_en.size() else source
			var module_ids: Array = context.get("module_ids", [])
			var module_id := str(module_ids[stage_index]) if stage_index < module_ids.size() else ""
			var module := SommerGameManager.Catalog.module(module_id)
			var module_name := SommerGameQuests.localized_text(str(module.get("name_de", module_id)),
				str(module.get("name_en", module_id)))
			var instruction := SommerGameQuests.localized_text(
				"Starte am Amiga SOMMER GAME, pruefe den Beitrag und integriere %s in den gemeinsamen Build.",
				"Start SOMMER GAME on the Amiga, review the contribution and integrate %s into the shared build.") % module_name
			return "„%s“\n%s" % [SommerGameQuests.localized_text(quote_de, quote_en), instruction]
	return Loc.t("quest.%s.stages%d.desc" % [id, stage_index], source)


static func definition(q: Dictionary) -> Dictionary:
	var out := q.duplicate(true)
	var id := str(q.get("id", ""))
	out["title"] = title(q, id)
	for field: String in TEXT_FIELDS:
		_localize_dictionary_field(out, field, id, field)
	for collection: String in ["on_start", "reward"]:
		out[collection] = effects(id, collection, out.get(collection, []), uses_authored_keys(q))
	for collection: String in TEXT_COLLECTIONS:
		var entries: Array = out.get(collection, [])
		for index in entries.size():
			if not entries[index] is Dictionary:
				continue
			var entry: Dictionary = entries[index]
			for field: String in TEXT_FIELDS:
				_localize_dictionary_field(entry, field, id, "%s%d.%s" % [collection, index, field])
		out[collection] = entries
	var intro: Variant = out.get("intro_via")
	if intro is Dictionary:
		_localize_dictionary_field(intro as Dictionary, "text", id, "intro_via.text")
	var stages: Array = out.get("stages", [])
	for index in stages.size():
		var stage_definition: Dictionary = stages[index]
		stage_definition["desc"] = stage_text(q, id, index)
		for field: String in ["hint", "title"]:
			_localize_dictionary_field(stage_definition, field, id, "stages%d.%s" % [index, field])
		stage_definition["reward"] = effects(id, "stages%d.reward" % index,
			stage_definition.get("reward", []), uses_authored_keys(q))
	out["stages"] = stages
	return out


static func effects(quest_id: String, path: String, source_effects: Array,
		use_authored_keys := true) -> Array:
	var out: Array = []
	for index in source_effects.size():
		if not source_effects[index] is Dictionary:
			out.append(source_effects[index])
			continue
		var effect: Dictionary = (source_effects[index] as Dictionary).duplicate(true)
		for field: String in ["text", "title", "memory"]:
			_localize_dictionary_field(effect, field, quest_id,
				"%s%d.%s" % [path, index, field], use_authored_keys)
		var risk: Variant = effect.get("risk")
		if risk is Dictionary:
			var risk_definition: Dictionary = risk
			risk_definition["effects"] = effects(quest_id, "%s%d.risk.effects" % [path, index],
				risk_definition.get("effects", []), use_authored_keys)
			effect["risk"] = risk_definition
		out.append(effect)
	return out


static func uses_authored_keys(q: Dictionary) -> bool:
	return str((q.get("localization_context", {}) as Dictionary).get("family", "")).is_empty()


static func _localize_dictionary_field(record: Dictionary, field: String, quest_id: String,
		path: String, use_authored_key := true) -> void:
	if not record.has(field) or not record[field] is String:
		return
	var source := str(record[field])
	# Dynamisch erzeugte Questfamilien werden einmal in den QuestManager geladen.
	# Ihr Spielertext darf dabei nicht in der damals aktiven Sprache einfrieren.
	# Explizite Sprachgeschwister werden deshalb bei jeder Darstellung neu
	# aufgeloest; die kanonischen Quest-/Save-IDs bleiben unveraendert.
	var german_field := field + "_de"
	var english_field := field + "_en"
	if record.has(german_field) or record.has(english_field):
		record[field] = SommerGameQuests.localized_text(
			str(record.get(german_field, source)), str(record.get(english_field, source)))
		return
	var explicit_key := str(record.get(field + "_key", ""))
	var source_template := str(record.get(field + "_source", source))
	var translated := source
	if not explicit_key.is_empty():
		translated = Loc.t(explicit_key, source_template)
	elif use_authored_key:
		translated = Loc.t("quest.%s.%s" % [quest_id, path], source)
	var args: Array = (record.get(field + "_args", []) as Array).duplicate()
	var arg_keys: Array = record.get(field + "_arg_keys", [])
	var arg_sources: Array = record.get(field + "_arg_sources", [])
	for index in mini(args.size(), arg_keys.size()):
		var arg_key := str(arg_keys[index])
		if not arg_key.is_empty():
			var arg_source := str(arg_sources[index]) if index < arg_sources.size() else str(args[index])
			args[index] = Loc.t(arg_key, arg_source)
	if not args.is_empty():
		translated = translated % args
	record[field] = translated
