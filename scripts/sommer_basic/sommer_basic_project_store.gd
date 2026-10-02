class_name SommerBasicProjectStore
extends RefCounted
## Persistenter, save-kompatibler Vertrag fuer die Jahreswerkstatt.
## Ein Magazinlisting ist erst nach vier nachweisbaren Phasen fertig:
## abgetippt -> Soll-Lauf bestanden -> Aufgabe verbessert -> implementiert.

const Catalog := preload("res://scripts/data/magazine_program_catalog.gd")

const STORE_KEY := "sommer_basic_projects"
const ACTIVE_KEY := "sommer_basic_active_listing_id"
const SCHEMA_VERSION := 1
const PHASE_TYPED := "typed"
const PHASE_VERIFIED := "verified"
const PHASE_IMPROVED := "improved"
const PHASE_IMPLEMENTED := "implemented"

const PHASE_RANK := {
	PHASE_TYPED: 1,
	PHASE_VERIFIED: 2,
	PHASE_IMPROVED: 3,
	PHASE_IMPLEMENTED: 4,
}

const IMPROVEMENTS := {
	"sb_signal_eins_v1": {
		"brief_de": "ERWEITERN: Zeichne eine zweite Signalspur mit LINE.",
		"brief_en": "EXTEND: Draw a second signal trace with LINE.",
		"hint_de": "Fuege vor PRINT eine weitere LINE-Zeile ein.",
		"hint_en": "Add another LINE statement before PRINT.",
		"min_draw_op_counts": {"line": 2},
	},
	"sb_stadtlichter_v1": {
		"brief_de": "ERWEITERN: Rahme die Skyline mit BOX ein.",
		"brief_en": "EXTEND: Frame the skyline with BOX.",
		"hint_de": "Eine BOX nach NEXT genuegt; die Ausgabe muss gleich bleiben.",
		"hint_en": "One BOX after NEXT is enough; keep the output unchanged.",
		"min_draw_op_counts": {"box": 1},
	},
	"sb_kanalwache_v1": {
		"brief_de": "ERWEITERN: Setze eine runde Statuslampe mit CIRCLE.",
		"brief_en": "EXTEND: Add a round status lamp with CIRCLE.",
		"hint_de": "Zeichne den Kreis vor der PRINT-Zeile.",
		"hint_en": "Draw the circle before the PRINT line.",
		"min_draw_op_counts": {"circle": 1},
	},
	"sb_rahmenruf_v1": {
		"brief_de": "ERWEITERN: Verstaerke den Rahmen mit einer zweiten LINE.",
		"brief_en": "EXTEND: Reinforce the frame with a second LINE.",
		"hint_de": "Ergaenze die Unterroutine um eine weitere Diagonale.",
		"hint_en": "Add another diagonal to the subroutine.",
		"min_draw_op_counts": {"line": 2},
	},
	"sb_rasterwelle_v1": {
		"brief_de": "ERWEITERN: Markiere die Rastermitte mit CIRCLE.",
		"brief_en": "EXTEND: Mark the raster centre with CIRCLE.",
		"hint_de": "Der Marker gehoert nach die Schleife.",
		"hint_en": "Place the marker after the loop.",
		"min_draw_op_counts": {"circle": 1},
	},
	"sb_punktfeld_v1": {
		"brief_de": "ERWEITERN: Gib dem Punktfeld einen BOX-Rahmen.",
		"brief_en": "EXTEND: Add a BOX frame around the dot field.",
		"hint_de": "Der Rahmen darf die 18 Punkte nicht veraendern.",
		"hint_en": "The frame must not change the 18 dots.",
		"min_draw_op_counts": {"box": 1},
	},
	"sb_horizontfaecher_v1": {
		"brief_de": "ERWEITERN: Zeichne einen BOX-Rahmen um den Faecher.",
		"brief_en": "EXTEND: Draw a BOX frame around the fan.",
		"hint_de": "Fuege den Rahmen nach NEXT ein.",
		"hint_en": "Add the frame after NEXT.",
		"min_draw_op_counts": {"box": 1},
	},
	"sb_lichtschalter_v1": {
		"brief_de": "ERWEITERN: Ergaenze eine CIRCLE-Kontrollleuchte.",
		"brief_en": "EXTEND: Add a CIRCLE indicator light.",
		"hint_de": "Die acht Lichtlinien und die Textausgabe bleiben erhalten.",
		"hint_en": "Keep all eight light lines and the text output.",
		"min_draw_op_counts": {"circle": 1},
	},
	"sb_doppelstation_v1": {
		"brief_de": "ERWEITERN: Verbinde beide Stationen mit LINE.",
		"brief_en": "EXTEND: Connect both stations with LINE.",
		"hint_de": "Zeichne die Verbindung vor PRINT.",
		"hint_en": "Draw the connection before PRINT.",
		"min_draw_op_counts": {"line": 1},
	},
	"sb_zehn_sommer_v1": {
		"brief_de": "ERWEITERN: Setze mit PLOT einen Mittelpunkt.",
		"brief_en": "EXTEND: Place a centre point with PLOT.",
		"hint_de": "Ein sichtbarer PLOT vor PRINT schliesst die Serie ab.",
		"hint_en": "A visible PLOT before PRINT completes the series.",
		"min_draw_op_counts": {"plot": 1},
	},
}


static func migrate_legacy() -> void:
	var store := _store()
	var legacy_id := str(GameManager.flags.get("sommer_basic_listing_id", ""))
	if legacy_id.is_empty() or store["projects"].has(legacy_id):
		return
	var entry := Catalog.by_listing(legacy_id)
	if entry.is_empty():
		return
	var source := str(GameManager.flags.get("sommer_basic_source",
		entry.get("canonical_source", "")))
	store["projects"][legacy_id] = _new_project(entry, source, 0)
	store["active_listing_id"] = legacy_id
	_write_store(store)


static func access_status(entry: Dictionary, reject_existing := false) -> Dictionary:
	if entry.is_empty():
		return {"ok": false, "reason": _localized(
			"Dieses Heft besitzt kein Sommer-BASIC-Listing.",
			"This issue does not contain a Sommer BASIC listing.")}
	var year := int(entry.get("year", 0))
	if int(TimeManager.year) < year:
		return {"ok": false, "reason": _localized(
			"Dieses Listing erscheint erst im Sommer %d.",
			"This listing will not appear until summer %d.") % year}
	var store := _store()
	var listing_id := str(entry.get("listing_id", ""))
	if reject_existing and store["projects"].has(listing_id):
		var phase := str((store["projects"][listing_id] as Dictionary).get("phase", PHASE_TYPED))
		return {"ok": false, "reason": _localized(
			"Bereits abgetippt (%s). In Sommer BASIC fortsetzen.",
			"Already transcribed (%s). Continue in Sommer BASIC.") % phase_label(phase)}
	var chapter := int(entry.get("chapter", 1))
	# 1990 ist ein optionaler Prolog. Die erste redaktionell freigegebene
	# Produktionsausgabe im aktuellen Bestand ist Juli 1991; ein neuer
	# Spielstand darf deshalb mit Kapitel 2 in die Werkstatt einsteigen. Sobald
	# ein Vorgangerprojekt existiert (oder ab Kapitel 3), bleibt die Reihenfolge
	# strikt und kann nicht durch Direktaufrufe uebersprungen werden.
	if chapter > 2 or (chapter == 2 and not store["projects"].is_empty()):
		var previous := Catalog.for_year(year - 1)
		var previous_id := str(previous.get("listing_id", ""))
		var previous_project: Dictionary = store["projects"].get(previous_id, {})
		if rank(str(previous_project.get("phase", ""))) < rank(PHASE_IMPLEMENTED):
			return {"ok": false, "reason": _localized(
				"Zuerst Kapitel %d vollstaendig implementieren.",
				"Fully implement chapter %d first.") % (chapter - 1)}
	return {"ok": true, "reason": ""}


static func register_typed(entry: Dictionary, source: String, score: int) -> Dictionary:
	var status := access_status(entry, true)
	if not bool(status.get("ok", false)):
		return status
	var listing_id := str(entry.get("listing_id", ""))
	var store := _store()
	store["projects"][listing_id] = _new_project(entry, source, score)
	store["active_listing_id"] = listing_id
	_write_store(store)
	_sync_legacy(entry, source)
	return {"ok": true, "phase": PHASE_TYPED, "listing_id": listing_id}


static func active_project() -> Dictionary:
	migrate_legacy()
	var store := _store()
	var listing_id := str(store.get("active_listing_id", ""))
	return (store["projects"].get(listing_id, {}) as Dictionary).duplicate(true)


static func project(listing_id: String) -> Dictionary:
	migrate_legacy()
	return ((_store()["projects"] as Dictionary).get(listing_id, {}) as Dictionary).duplicate(true)


static func active_source(fallback: String) -> String:
	var current := active_project()
	return str(current.get("source", fallback)) if not current.is_empty() else fallback


static func save_active_source(source: String) -> void:
	var store := _store()
	var listing_id := str(store.get("active_listing_id", ""))
	if listing_id.is_empty() or not store["projects"].has(listing_id):
		GameManager.flags["sommer_basic_source"] = source
		return
	var current := (store["projects"][listing_id] as Dictionary).duplicate(true)
	current["source"] = source
	current["source_revision"] = int(current.get("source_revision", 1)) + 1
	store["projects"][listing_id] = current
	_write_store(store)
	GameManager.flags["sommer_basic_source"] = source


static func record_successful_run(source: String, result: Dictionary) -> Dictionary:
	var store := _store()
	var listing_id := str(store.get("active_listing_id", ""))
	if listing_id.is_empty() or not store["projects"].has(listing_id):
		return {"ok": true, "advanced": false, "free_project": true}
	var current := (store["projects"][listing_id] as Dictionary).duplicate(true)
	var entry := Catalog.by_listing(listing_id)
	var phase := str(current.get("phase", PHASE_TYPED))
	if phase == PHASE_TYPED:
		var baseline := _baseline_status(entry, result)
		if not bool(baseline.get("ok", false)):
			return baseline
		current["phase"] = PHASE_VERIFIED
		current["source"] = source
		current["baseline_verified"] = true
		store["projects"][listing_id] = current
		_write_store(store)
		return {"ok": true, "advanced": true, "phase": PHASE_VERIFIED,
			"message": _localized(
				"Soll-Lauf bestanden. Jetzt die Redaktionsaufgabe umsetzen.",
				"Reference run passed. Now complete the editorial brief.")}
	if phase == PHASE_VERIFIED:
		var improved := _improvement_status(entry, current, source, result)
		if not bool(improved.get("ok", false)):
			return improved
		current["phase"] = PHASE_IMPROVED
		current["source"] = source
		current["improvement_verified"] = true
		store["projects"][listing_id] = current
		_write_store(store)
		return {"ok": true, "advanced": true, "phase": PHASE_IMPROVED,
			"message": _localized(
				"Verbesserung laeuft fehlerfrei. Implementierung ist freigegeben.",
				"The improvement runs without errors. Implementation is unlocked.")}
	return {"ok": true, "advanced": false, "phase": phase}


static func implement_active() -> Dictionary:
	var store := _store()
	var listing_id := str(store.get("active_listing_id", ""))
	var current: Dictionary = store["projects"].get(listing_id, {})
	if current.is_empty():
		return {"ok": false, "reason": _localized(
			"Kein Magazinprojekt aktiv.", "No magazine project is active.")}
	var phase := str(current.get("phase", PHASE_TYPED))
	if phase == PHASE_IMPLEMENTED:
		return {"ok": false, "reason": _localized(
			"Dieses Kapitel ist bereits implementiert.",
			"This chapter has already been implemented.")}
	if phase != PHASE_IMPROVED:
		return {"ok": false, "reason": _localized(
			"Erst Soll-Lauf und Verbesserungsaufgabe abschliessen.",
			"Complete the reference run and improvement brief first.")}
	current = current.duplicate(true)
	current["phase"] = PHASE_IMPLEMENTED
	current["implemented_day"] = int(TimeManager.day_counter)
	store["projects"][listing_id] = current
	_write_store(store)
	GameManager.flags["sommer_basic_implemented_%s" % listing_id] = true
	return {"ok": true, "listing_id": listing_id,
		"message": _localized(
			"Kapitel %d ist im Jahresprojekt implementiert.",
			"Chapter %d has been implemented in the annual project.") % int(current.get("chapter", 1))}


static func improvement(entry: Dictionary) -> Dictionary:
	return (IMPROVEMENTS.get(str(entry.get("listing_id", "")), {}) as Dictionary).duplicate(true)


static func validate_contracts() -> Array[String]:
	var issues: Array[String] = []
	for entry: Dictionary in Catalog.all():
		var listing_id := str(entry.get("listing_id", ""))
		var task := improvement(entry)
		if task.is_empty():
			issues.append("%s: Verbesserungsaufgabe fehlt." % listing_id)
			continue
		for language_key in ["brief_de", "brief_en", "hint_de", "hint_en"]:
			if str(task.get(language_key, "")).strip_edges().is_empty():
				issues.append("%s: %s fehlt." % [listing_id, language_key])
		var minima: Variant = task.get("min_draw_op_counts", null)
		if not minima is Dictionary or (minima as Dictionary).is_empty():
			issues.append("%s: messbares Verbesserungsziel fehlt." % listing_id)
			continue
		var baseline: Dictionary = (entry.get("expected_output", {}) as Dictionary).get(
			"draw_op_counts", {})
		for raw_operation: Variant in minima as Dictionary:
			var operation := str(raw_operation)
			if int((minima as Dictionary)[raw_operation]) <= int(baseline.get(operation, 0)):
				issues.append("%s: %s verbessert den Soll-Lauf nicht messbar." % [
					listing_id, operation])
	return issues


static func phase_label(phase: String) -> String:
	var german := {
		PHASE_TYPED: "1/4 ABGETIPPT", PHASE_VERIFIED: "2/4 SOLL-LAUF",
		PHASE_IMPROVED: "3/4 VERBESSERT", PHASE_IMPLEMENTED: "4/4 IMPLEMENTIERT",
	}
	var english := {
		PHASE_TYPED: "1/4 TRANSCRIBED", PHASE_VERIFIED: "2/4 REFERENCE RUN",
		PHASE_IMPROVED: "3/4 IMPROVED", PHASE_IMPLEMENTED: "4/4 IMPLEMENTED",
	}
	return (english if TranslationServer.get_locale().begins_with("en") else german).get(
		phase, "0/4 NOT STARTED" if TranslationServer.get_locale().begins_with("en") \
		else "0/4 NICHT BEGONNEN")


static func rank(phase: String) -> int:
	return int(PHASE_RANK.get(phase, 0))


static func _baseline_status(entry: Dictionary, result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)) or bool(result.get("waiting_for_input", false)):
		return {"ok": false, "reason": _localized(
			"Das Programm wurde nicht vollstaendig beendet.",
			"The program did not finish completely.")}
	var expected: Dictionary = entry.get("expected_output", {})
	if result.get("output", []) != expected.get("console", []):
		return {"ok": false, "reason": _localized(
			"Die Konsolenausgabe entspricht noch nicht dem Heft.",
			"The console output does not yet match the magazine.")}
	if _draw_counts(result.get("draw_commands", [])) != _normalized_counts(expected.get("draw_op_counts", {})):
		return {"ok": false, "reason": _localized(
			"Die Grafik stimmt noch nicht mit dem Soll-Lauf ueberein.",
			"The graphics do not yet match the reference run.")}
	if not _variables_match(result.get("variables", {}), expected.get("final_variables", {})):
		return {"ok": false, "reason": _localized(
			"Die Endwerte des Programms sind noch falsch.",
			"The program's final values are still incorrect.")}
	return {"ok": true}


static func _improvement_status(entry: Dictionary, current: Dictionary,
		source: String, result: Dictionary) -> Dictionary:
	if source.strip_edges() == str(current.get("canonical_source", "")).strip_edges():
		return {"ok": false, "reason": _localized(
			"Der Quelltext ist noch unveraendert. Lies die Verbesserungsaufgabe.",
			"The source is still unchanged. Read the improvement brief.")}
	var expected: Dictionary = entry.get("expected_output", {})
	if not bool(result.get("ok", false)) or bool(result.get("waiting_for_input", false)):
		return {"ok": false, "reason": _localized(
			"Die Verbesserung beendet sich noch nicht sauber.",
			"The improved program does not yet finish cleanly.")}
	if result.get("output", []) != expected.get("console", []):
		return {"ok": false, "reason": _localized(
			"Die bekannte Programmausgabe muss erhalten bleiben.",
			"The known program output must be preserved.")}
	if not _variables_match(result.get("variables", {}), expected.get("final_variables", {})):
		return {"ok": false, "reason": _localized(
			"Die bekannten Endwerte duerfen nicht kaputtgehen.",
			"The known final values must not be broken.")}
	var counts := _draw_counts(result.get("draw_commands", []))
	for raw_op: Variant in (expected.get("draw_op_counts", {}) as Dictionary):
		var operation := str(raw_op)
		if int(counts.get(operation, 0)) < int(expected["draw_op_counts"][raw_op]):
			return {"ok": false, "reason": _localized(
				"Die vorhandene Grafikfunktion %s fehlt.",
				"The existing %s graphics operation is missing.") % operation.to_upper()}
	var task := improvement(entry)
	for raw_op: Variant in (task.get("min_draw_op_counts", {}) as Dictionary):
		var operation := str(raw_op)
		if int(counts.get(operation, 0)) < int(task["min_draw_op_counts"][raw_op]):
			return {"ok": false, "reason": _localized(
				"Aufgabe noch offen: mehr %s-Zeichenoperationen noetig.",
				"Brief incomplete: more %s drawing operations are required.") % operation.to_upper()}
	return {"ok": true}


static func _new_project(entry: Dictionary, source: String, score: int) -> Dictionary:
	return {
		"listing_id": str(entry.get("listing_id", "")),
		"issue_id": str(entry.get("issue_id", "")),
		"title_de": str(entry.get("title_de", "")),
		"title_en": str(entry.get("title_en", "")),
		"year": int(entry.get("year", 0)),
		"chapter": int(entry.get("chapter", 1)),
		"chapter_count": int(entry.get("count", 10)),
		"phase": PHASE_TYPED,
		"source": source,
		"canonical_source": str(entry.get("canonical_source", source)),
		"source_revision": 1,
		"typing_score": score,
		"typed_day": int(TimeManager.day_counter),
	}


static func _store() -> Dictionary:
	var raw: Variant = GameManager.flags.get(STORE_KEY, {})
	var store := (raw as Dictionary).duplicate(true) if raw is Dictionary else {}
	if int(store.get("schema_version", 0)) < SCHEMA_VERSION:
		store["schema_version"] = SCHEMA_VERSION
	if not store.get("projects", null) is Dictionary:
		store["projects"] = {}
	if not store.has("active_listing_id"):
		store["active_listing_id"] = str(GameManager.flags.get(ACTIVE_KEY, ""))
	return store


static func _write_store(store: Dictionary) -> void:
	GameManager.flags[STORE_KEY] = store.duplicate(true)
	GameManager.flags[ACTIVE_KEY] = str(store.get("active_listing_id", ""))


static func _sync_legacy(entry: Dictionary, source: String) -> void:
	GameManager.flags["sommer_basic_source"] = source
	GameManager.flags["sommer_basic_source_version"] = 2
	GameManager.flags["sommer_basic_listing_id"] = str(entry.get("listing_id", ""))
	GameManager.flags["sommer_basic_issue_id"] = str(entry.get("issue_id", ""))


static func _draw_counts(raw_commands: Variant) -> Dictionary:
	var counts: Dictionary = {}
	if raw_commands is Array:
		for raw_command: Variant in raw_commands as Array:
			if raw_command is Dictionary:
				var operation := str((raw_command as Dictionary).get("op", ""))
				counts[operation] = int(counts.get(operation, 0)) + 1
	return counts


static func _normalized_counts(raw_counts: Variant) -> Dictionary:
	var counts: Dictionary = {}
	if raw_counts is Dictionary:
		for operation: Variant in raw_counts as Dictionary:
			counts[str(operation)] = int((raw_counts as Dictionary)[operation])
	return counts


static func _variables_match(raw_actual: Variant, raw_expected: Variant) -> bool:
	if not raw_actual is Dictionary or not raw_expected is Dictionary:
		return false
	var actual := raw_actual as Dictionary
	for raw_name: Variant in raw_expected as Dictionary:
		var name := str(raw_name)
		if not actual.has(name):
			return false
		var actual_value: Variant = actual[name]
		var expected_value: Variant = (raw_expected as Dictionary)[raw_name]
		if actual_value is float or actual_value is int:
			if not is_equal_approx(float(actual_value), float(expected_value)):
				return false
		elif actual_value != expected_value:
			return false
	return true


static func _localized(german: String, english: String) -> String:
	return english if TranslationServer.get_locale().begins_with("en") else german
