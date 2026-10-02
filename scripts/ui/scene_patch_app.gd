class_name ScenePatchApp
extends WbApp
## BYTEWERK P-8 — fiktive Szene-Release-Werkstatt.
##
## Das Minispiel bildet bewusst KEIN reales Entfernen eines Kopierschutzes ab:
## Es gibt weder Adressen noch Opcodes oder frei eingebbare Patch-Bytes. Die
## markierten P-8-Matrixfelder akzeptieren ausschließlich vom Spiel erzeugte
## Fantasiewerte und werden durch abstrakte Logikregeln geprüft.

enum Stage { HANDLE, ANALYSE, PATCH, TESTBOOT, INTRO, COMPLETE }
const Renderer:=preload("res://scripts/ui/scene_patch_renderer.gd")
const IntroCatalog:=preload("res://scripts/ui/scene_patch_intro_catalog.gd")

const C_BG := Color8(14, 20, 34)
const C_PANEL := Color8(31, 43, 62)
const C_PANEL_2 := Color8(43, 57, 76)
const C_INK := Color8(224, 232, 232)
const C_DIM := Color8(126, 144, 156)
const C_BLUE := Color8(72, 184, 220)
const C_GOLD := Color8(248, 196, 72)
const C_GREEN := Color8(92, 220, 138)
const C_RED := Color8(235, 92, 90)
const C_MAGENTA := Color8(222, 92, 190)

var disk: Disk

var _stage: int = Stage.ANALYSE
var _blocked := false
var _status := "BYTEWERK bereit."
var _eligibility: Dictionary = {}

var _handle_draft := ""
var _handle_suggestions: Array = []
var _difficulty := "standard"
var _analysis_running := false
var _analysis_progress := 0.0

var _puzzle: Dictionary = {}
var _answers: Dictionary = {}
var _answer_history: Array[Dictionary] = []
var _row_results: Array = []
var _patch_result: Dictionary = {}
var _verified := false
var _auto_used := false
var _hint_rows := 0

var _boot_running := false
var _boot_timer := 0.0
var _boot_step := 0
var _boot_complete := false
var _boot_log: Array[String] = []

var _intro_options: Dictionary = {}
var _logo_index := 0
var _palette_index := 0
var _scroller_index := 0
var _selected_effects: Array[String] = []
var _selected_credits: Array[String] = []
var _group_index := 0
var _credit_page := 0
var _anim_t := 0.0
var _finalized := false
var _final_result: Dictionary = {}


func _init() -> void:
	app_title = "BYTEWERK P-8   ·   SCENE RELEASE LAB"
	app_bg = C_BG
	app_bar = Color8(26, 70, 104)
	app_accent = C_BLUE


func _build_app() -> void:
	_eligibility = _disk_eligibility()
	_blocked = not bool(_eligibility.get("ok", false))
	if _blocked:
		_stage = Stage.ANALYSE
		_status = str(_eligibility.get("text", _eligibility.get("reason", "Diese Diskette ist nicht für BYTEWERK geeignet.")))
	else:
		var current_handle := _scene_handle()
		if current_handle == "":
			_stage = Stage.HANDLE
			_handle_suggestions = _suggestions()
			_handle_draft = str(_handle_suggestions[0]) if not _handle_suggestions.is_empty() else "NIBBLE"
			_status = "Dein BBS-Handle wird in Intros sichtbar — niemals dein Klarname."
		else:
			_handle_draft = current_handle
			if not _restore_patch_draft():
				_stage = Stage.ANALYSE
				_status = "Arbeitskopie erkannt. Wähle die Tiefe der P-8-Analyse."
	_rebuild_widgets()


func _disk_eligibility() -> Dictionary:
	if disk == null:
		return {"ok": false, "text": Loc.t("ui.scene_patch_app.keine_arbeitsdiskette_eingelegt", "Keine Arbeitsdiskette eingelegt.")}
	return SceneReleaseManager.eligibility(disk)


func _scene_handle() -> String:
	return _sanitize_handle(SceneReleaseManager.scene_handle)


func _suggestions() -> Array:
	var raw: Array = SceneReleaseManager.handle_suggestions()
	var out: Array = []
	for item in raw if not raw.is_empty() else IntroCatalog.FALLBACK_HANDLES:
		var handle := _sanitize_handle(str(item))
		if handle.length() >= 3 and not out.has(handle):
			out.append(handle)
	return out.slice(0, 6)


func _sanitize_handle(value: String) -> String:
	return IntroCatalog.sanitize_handle(value)


# -------------------------------------------------------------- Widget-Aufbau

func _rebuild_widgets() -> void:
	clear_widgets()
	if _blocked:
		add_button("ZURÜCK", Rect2(520, 356, 102, 26), close_app, C_INK)
		return
	match _stage:
		Stage.HANDLE:
			for i in _handle_suggestions.size():
				var col := i % 3
				var row := floori(i / 3.0)
				add_button(str(_handle_suggestions[i]), Rect2(74 + col * 164, 188 + row * 36, 148, 26),
					_select_suggestion.bind(i), C_GOLD)
			add_button("HANDLE SPEICHERN", Rect2(226, 284, 188, 30), _save_handle, C_GREEN)
		Stage.ANALYSE:
			for i in 3:
				var ids := ["entspannt", "standard", "szene"]
				var names := ["ENTSPANNT", "STANDARD", "SZENE"]
				add_button(names[i], Rect2(74 + i * 166, 166, 150, 30), _choose_difficulty.bind(ids[i]),
					C_GOLD if _difficulty == ids[i] else C_INK)
			if not _analysis_running:
				add_button("P-8 ANALYSE STARTEN", Rect2(206, 236, 228, 34), _begin_analysis, C_GREEN)
		Stage.PATCH:
			var rows := _puzzle_rows()
			var row_gap := 34.0 if rows.size() <= 6 else 27.0
			for i in rows.size():
				var answer := _answer_for_row(rows[i], i)
				add_button("WERT  %s" % (answer if answer != "" else "??"), Rect2(473, 92 + i * row_gap, 116, 24),
					_cycle_answer.bind(i), C_GOLD)
			if _verified:
				add_button("ZU DEN TESTBOOTS", Rect2(446, 332, 176, 28), _enter_testboot, C_GREEN)
			else:
				add_button("UNDO", Rect2(20, 332, 76, 28), _undo_answer, C_DIM)
				add_button("HINWEIS", Rect2(104, 332, 96, 28), _show_hint, C_BLUE)
				add_button("AUTO-HILFE", Rect2(208, 332, 112, 28), _auto_solve, C_DIM)
				add_button("MATRIX PRÜFEN", Rect2(446, 332, 176, 28), _verify_patch, C_GREEN)
		Stage.TESTBOOT:
			if not _boot_running and not _boot_complete:
				add_button("3× TESTBOOT STARTEN", Rect2(202, 300, 236, 32), _start_testboots, C_GREEN)
			elif _boot_complete:
				add_button("INTRO BAUEN", Rect2(226, 324, 188, 30), _enter_intro, C_GREEN)
		Stage.INTRO:
			add_button("◀ LOGO", Rect2(18, 94, 92, 24), _cycle_logo.bind(-1), C_INK)
			add_button("LOGO ▶", Rect2(116, 94, 92, 24), _cycle_logo.bind(1), C_INK)
			add_button("◀ PALETTE", Rect2(18, 132, 92, 24), _cycle_palette.bind(-1), C_INK)
			add_button("PALETTE ▶", Rect2(116, 132, 92, 24), _cycle_palette.bind(1), C_INK)
			var effects := _effect_options()
			for i in effects.size():
				var col := i % 2
				var row := floori(i / 2.0)
				var effect_id := IntroCatalog.option_id(effects[i], "effect_%d" % i)
				add_button(_option_name(effects[i]), Rect2(18 + col * 98, 190 + row * 27, 92, 22),
					_toggle_effect.bind(i), C_GREEN if _selected_effects.has(effect_id) else C_DIM)
			add_button("SCROLLER ▶", Rect2(18, 282, 190, 24), _cycle_scroller, C_GOLD)
			var groups := _accepted_groups()
			_group_index = clampi(_group_index, 0, maxi(0, groups.size() - 1))
			add_button("%s ▶" % str(groups[_group_index].get("name", "SOLO")).left(17), Rect2(222, 184, 158, 24),
				_cycle_group, C_GOLD)
			var candidates := _credit_page_items()
			for i in mini(3, candidates.size()):
				var key := _credit_key(candidates[i])
				add_button(_credit_button_text(candidates[i]), Rect2(222, 230 + i * 25, 158, 21),
					_toggle_credit.bind(i), C_GREEN if _selected_credits.has(key) else C_DIM)
			if _optional_credit_candidates().size() > 3:
				add_button("◀ CREW", Rect2(222, 307, 76, 19), _cycle_credit_page.bind(-1), C_DIM)
				add_button("CREW ▶", Rect2(304, 307, 76, 19), _cycle_credit_page.bind(1), C_DIM)
			add_button("RELEASE FINALISIEREN", Rect2(418, 330, 204, 30), _finalize_release, C_GREEN)
		Stage.COMPLETE:
			add_button("INTRO STARTEN", Rect2(180, 286, 150, 32), _launch_intro, C_GREEN)
			add_button("FERTIG", Rect2(342, 286, 118, 32), close_app, C_INK)
	_layout()


# --------------------------------------------------------------- Handle-Stufe

func _input(event: InputEvent) -> void:
	if _stage == Stage.HANDLE and not _blocked and event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACKSPACE:
			_handle_draft = _handle_draft.left(maxi(0, _handle_draft.length() - 1))
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_save_handle()
			get_viewport().set_input_as_handled()
			return
		if event.unicode > 0:
			var next := _sanitize_handle(_handle_draft + char(event.unicode))
			if next != _handle_draft:
				_handle_draft = next
				get_viewport().set_input_as_handled()
				return
	super._input(event)


func _select_suggestion(index: int) -> void:
	if index >= 0 and index < _handle_suggestions.size():
		_handle_draft = str(_handle_suggestions[index])
		_status = "Handle %s gewählt. Enter oder SPEICHERN bestätigt." % _handle_draft


func _save_handle() -> bool:
	_handle_draft = _sanitize_handle(_handle_draft)
	if _handle_draft.length() < 3:
		_status = "Ein Handle braucht mindestens drei Zeichen."
		return false
	var result: Dictionary = SceneReleaseManager.set_scene_handle(_handle_draft)
	var message := str(result.get("text", result.get("reason", "")))
	if not bool(result.get("ok", false)):
		_status = message if message != "" else "Dieses Handle ist nicht gültig."
		return false
	if not _restore_patch_draft():
		_stage = Stage.ANALYSE
		_status = message if message != "" else "Handle gespeichert. Keine Klarnamen im Release."
	_rebuild_widgets()
	return true


# -------------------------------------------------------------- Analyse/Puzzle

func _choose_difficulty(value: String) -> void:
	_difficulty = value
	_status = {"entspannt": "4 P-8-Signaturen, viele Hinweise.", "standard": "5 Signaturen, ausgewogene Logik.",
		"szene": "6 Signaturen, knappe Hinweise."}.get(value, "Standardanalyse.")
	_rebuild_widgets()


func _begin_analysis() -> void:
	_analysis_running = true
	_analysis_progress = 0.0
	_status = "P-8 liest abstrakte Prüfsignaturen — keine realen Programmadressen."
	_rebuild_widgets()


func _finish_analysis() -> bool:
	var result: Dictionary = SceneReleaseManager.generate_puzzle(disk, _difficulty)
	if not result.has("rows"):
		_status = "Die Analyse lieferte kein gültiges Prüfmuster."
		_analysis_running = false
		_rebuild_widgets()
		return false
	_puzzle = result
	_answers.clear()
	_answer_history.clear()
	_row_results.clear()
	_patch_result.clear()
	_verified = false
	_auto_used = false
	_hint_rows = 0
	_analysis_running = false
	_stage = Stage.PATCH
	_status = "Markierte Felder anklicken. Nur die drei erlaubten Fantasiewerte sind wählbar."
	_save_patch_draft()
	_rebuild_widgets()
	return true


func _puzzle_rows() -> Array:
	var rows = _puzzle.get("rows", [])
	return rows if typeof(rows) == TYPE_ARRAY else []


func _row_key(row: Dictionary, index: int) -> String:
	return str(row.get("id", "row_%d" % index))


func _row_cells(row: Dictionary) -> Array:
	for key in ["cells", "values", "bytes"]:
		var raw = row.get(key, [])
		if typeof(raw) == TYPE_ARRAY:
			return raw
	return []


func _row_choices(row: Dictionary) -> Array[String]:
	var raw = row.get("choices", row.get("allowed", row.get("options", [])))
	var out: Array[String] = []
	if typeof(raw) == TYPE_ARRAY:
		for value in raw:
			var token := str(value).to_upper()
			if token != "" and not out.has(token):
				out.append(token)
	return out


func _answer_for_row(row: Dictionary, index: int) -> String:
	return str(_answers.get(_row_key(row, index), ""))


func _cycle_answer(index: int) -> void:
	var rows := _puzzle_rows()
	if index < 0 or index >= rows.size():
		return
	var row: Dictionary = rows[index]
	var choices := _row_choices(row)
	if choices.is_empty():
		return
	var key := _row_key(row, index)
	var current := str(_answers.get(key, ""))
	var pos := choices.find(current)
	_answer_history.append(_answers.duplicate(true))
	_answers[key] = choices[(pos + 1) % choices.size()]
	_verified = false
	_row_results.clear()
	_status = "Zeile %d: %s ist als P-8-Fantasiewert gesetzt." % [index + 1, _answers[key]]
	_save_patch_draft()
	_rebuild_widgets()


func _undo_answer() -> bool:
	if _answer_history.is_empty():
		_status = "Noch keine Matrixänderung zum Zurücknehmen."
		return false
	_answers = _answer_history.pop_back().duplicate(true)
	_verified = false
	_row_results.clear()
	_status = "Letzte Matrixänderung zurückgenommen. Undo bleibt unbegrenzt verfügbar."
	_save_patch_draft()
	_rebuild_widgets()
	return true


func _show_hint() -> void:
	_hint_rows = mini(_puzzle_rows().size(), _hint_rows + 1)
	_status = "Hinweis %d/%d eingeblendet. Ohne Zeitlimit — denk in Ruhe nach." % [_hint_rows, _puzzle_rows().size()]


func _all_rows_answered() -> bool:
	var rows := _puzzle_rows()
	if rows.is_empty():
		return false
	for i in rows.size():
		if _answer_for_row(rows[i], i) == "":
			return false
	return true


func _auto_solve() -> bool:
	var solution: Dictionary = SceneReleaseManager.auto_solution(_puzzle)
	var rows := _puzzle_rows()
	_answer_history.append(_answers.duplicate(true))
	for i in rows.size():
		var row: Dictionary = rows[i]
		var key := _row_key(row, i)
		var selected := str(solution.get(key, solution.get(i, ""))).to_upper()
		# Selbst die Hilfe darf nur einen explizit erlaubten Fantasiewert setzen.
		if _row_choices(row).has(selected):
			_answers[key] = selected
	_auto_used = true
	_status = "Auto-Hilfe setzt eine stabile Matrix. Dafür gibt es keinen Rekordbonus."
	_save_patch_draft()
	_rebuild_widgets()
	return _verify_patch()


func _verify_patch() -> bool:
	if not _all_rows_answered():
		_status = "Noch nicht alle markierten P-8-Felder sind gesetzt."
		return false
	var result: Dictionary = SceneReleaseManager.verify_puzzle(
		_puzzle, _answers.duplicate(true), not _auto_used)
	_patch_result = result
	_patch_result["manual"] = not _auto_used
	_row_results = result.get("row_results", []) if typeof(result.get("row_results", [])) == TYPE_ARRAY else []
	_verified = bool(result.get("ok", false))
	_status = str(result.get("text", "Matrix stabil." if _verified else "Einige P-8-Regeln passen noch nicht."))
	_rebuild_widgets()
	return _verified


func _save_patch_draft() -> void:
	if disk == null:
		return
	SceneReleaseManager.save_patch_draft(disk, {
		"difficulty": _difficulty,
		"puzzle": _puzzle.duplicate(true),
		"answers": _answers.duplicate(true),
		"auto_used": _auto_used,
	})


func _restore_patch_draft() -> bool:
	if disk == null or disk.patch_state != "draft" or disk.patch_draft.is_empty():
		return false
	var draft: Dictionary = disk.patch_draft
	var puzzle = draft.get("puzzle", {})
	if typeof(puzzle) != TYPE_DICTIONARY or (puzzle as Dictionary).get("rows", []).is_empty():
		return false
	_puzzle = (puzzle as Dictionary).duplicate(true)
	_answers = (draft.get("answers", {}) as Dictionary).duplicate(true)
	_difficulty = str(draft.get("difficulty", "standard"))
	_auto_used = bool(draft.get("auto_used", false))
	_answer_history.clear()
	_verified = false
	_stage = Stage.PATCH
	_status = "Gespeicherten P-8-Entwurf fortgesetzt. Noch nichts wurde finalisiert."
	return true


# ------------------------------------------------------------------ Testboots

func _enter_testboot() -> void:
	if not _verified:
		return
	_stage = Stage.TESTBOOT
	_boot_step = 0
	_boot_complete = false
	_boot_running = false
	_boot_log.clear()
	_status = "%s: drei reproduzierbare Starts prüfen alle Schutzschritte." % _active_revision_name()
	_rebuild_widgets()


func _start_testboots() -> void:
	_boot_step = 0
	_boot_log.clear()
	_boot_complete = false
	_boot_running = true
	_boot_timer = 0.0
	_status = "Testlauf 1/3 startet …"
	_rebuild_widgets()


func _advance_testboot() -> void:
	if not _boot_running:
		return
	var revision := _active_revision()
	var labels := [
		"KALTSTART   · Signatur stabil · OK",
		("SPEICHERWECHSEL · Startimpuls-Sync stabil · OK" if revision >= 2 else "SPEICHERWECHSEL · Prüfbild stabil · OK"),
		("NEUSTART    · Schutzspiegel + Intro stabil · OK" if revision >= 3 else "NEUSTART    · Intro-Handoff stabil · OK"),
	]
	if _boot_step < labels.size():
		_boot_log.append(labels[_boot_step])
		_boot_step += 1
	if _boot_step >= 3:
		_boot_running = false
		_boot_complete = true
		_status = "3/3 Testboots grün. %s ist bereit für das Intro." % _active_revision_name()
		_rebuild_widgets()
	else:
		_status = "Testlauf %d/3 startet …" % (_boot_step + 1)


func _active_revision() -> int:
	return maxi(1, int(_patch_result.get("revision", _puzzle.get("revision", 1))))


func _active_revision_name() -> String:
	return str(_patch_result.get("revision_name", _puzzle.get("revision_name", "P-8 V%d" % _active_revision())))


# --------------------------------------------------------------- Intro-Baukasten

func _enter_intro() -> void:
	if not _boot_complete:
		return
	_load_intro_options()
	_stage = Stage.INTRO
	_status = "Live-Vorschau: maximal drei Effekte. Credits zeigen ausschließlich BBS-Handles."
	_rebuild_widgets()


func _load_intro_options() -> void:
	_intro_options = IntroCatalog.normalized_options(SceneReleaseManager.intro_options())
	_logo_index = clampi(_logo_index, 0, maxi(0, _logo_options().size() - 1))
	_palette_index = clampi(_palette_index, 0, maxi(0, _palette_options().size() - 1))
	_scroller_index = clampi(_scroller_index, 0, maxi(0, _scroller_options().size() - 1))
	if _selected_effects.is_empty():
		for i in mini(2, _effect_options().size()):
			_selected_effects.append(IntroCatalog.option_id(_effect_options()[i], "effect_%d" % i))


func _option_array(key: String) -> Array:
	return IntroCatalog.option_array(_intro_options, key)


func _logo_options() -> Array: return _option_array("logos")
func _palette_options() -> Array: return _option_array("palettes")
func _effect_options() -> Array: return _option_array("effects")
func _scroller_options() -> Array:
	return IntroCatalog.scroller_options(_intro_options)


func _option_name(value) -> String:
	return IntroCatalog.option_name(value)


func _cycle_logo(delta: int) -> void:
	_logo_index = IntroCatalog.wrap_index(_logo_index + delta, _logo_options().size())
	_status = "Logo-Stil: %s" % _option_name(_logo_options()[_logo_index])


func _cycle_palette(delta: int) -> void:
	_palette_index = IntroCatalog.wrap_index(_palette_index + delta, _palette_options().size())
	_status = "Palette: %s" % _option_name(_palette_options()[_palette_index])


func _toggle_effect(index: int) -> void:
	var effects := _effect_options()
	if index < 0 or index >= effects.size():
		return
	var id := IntroCatalog.option_id(effects[index], "effect_%d" % index)
	if _selected_effects.has(id):
		_selected_effects.erase(id)
	elif _selected_effects.size() >= 3:
		_status = "Maximal drei Effekte halten das Intro lesbar und zeittypisch."
		return
	else:
		_selected_effects.append(id)
	_status = "%d/3 Effekte aktiv." % _selected_effects.size()
	_rebuild_widgets()


func _cycle_scroller() -> void:
	_scroller_index = IntroCatalog.wrap_index(_scroller_index + 1, _scroller_options().size())
	_status = "Scrollertext gewechselt. Handles und Release-Daten werden automatisch eingesetzt."


func _accepted_groups() -> Array:
	var out: Array = [{"id": "", "name": "SOLO · %s" % _scene_handle()}]
	for group: Dictionary in SceneReleaseManager.all_group_status():
		if str(group.get("cooperation", "none")) == "accepted" and bool(group.get("active", false)):
			out.append({"id": str(group.get("id", "")), "name": str(group.get("name", group.get("id", "CREW")))})
	return out


func _cycle_group() -> void:
	var groups := _accepted_groups()
	_group_index = IntroCatalog.wrap_index(_group_index + 1, groups.size())
	_status = "Präsentiert von: %s. Nur verdiente Kooperationen erscheinen hier." % str(groups[_group_index].get("name", "SOLO"))
	_rebuild_widgets()


func _presenting_name() -> String:
	var groups := _accepted_groups()
	_group_index = clampi(_group_index, 0, maxi(0, groups.size() - 1))
	return _scene_handle() if str(groups[_group_index].get("id", "")) == "" else str(groups[_group_index].get("name", _scene_handle()))


func _credit_candidates() -> Array:
	var out: Array = []
	for candidate: Dictionary in SceneReleaseManager.credit_candidates():
		if not bool(candidate.get("available", true)):
			continue
		# Absichtlich ausschließlich Handle-Felder lesen. `name`, NPC-Daten und
		# owner_history sind für die Intro-Oberfläche unsichtbar.
		var handle := _credit_handle(candidate)
		if handle != "":
			var clean: Dictionary = {
				"actor_id": str(candidate.get("actor_id", "")),
				"handle_snapshot": handle,
				"role": str(candidate.get("role", "CONTRIBUTOR")).to_upper(),
			}
			out.append(clean)
	return out


func _optional_credit_candidates() -> Array:
	var out: Array = []
	for candidate: Dictionary in _credit_candidates():
		if str(candidate.get("actor_id", "")) not in ["player", "self"]:
			out.append(candidate)
	return out


func _credit_page_items() -> Array:
	var all := _optional_credit_candidates()
	var page_count := maxi(1, ceili(float(all.size()) / 3.0))
	_credit_page = posmod(_credit_page, page_count)
	var start := _credit_page * 3
	return all.slice(start, mini(start + 3, all.size()))


func _cycle_credit_page(delta: int) -> void:
	var count := maxi(1, ceili(float(_optional_credit_candidates().size()) / 3.0))
	_credit_page = posmod(_credit_page + delta, count)
	_status = "Contributor-Seite %d/%d · angezeigt werden ausschließlich verfügbare Handles." % [_credit_page + 1, count]
	_rebuild_widgets()


func _credit_handle(candidate: Dictionary) -> String:
	return _sanitize_handle(str(candidate.get("handle_snapshot", candidate.get("handle", ""))))


func _credit_key(candidate: Dictionary) -> String:
	var actor := str(candidate.get("actor_id", ""))
	return actor if actor != "" else _credit_handle(candidate)


func _credit_button_text(candidate: Dictionary) -> String:
	return "%s · %s" % [_credit_handle(candidate), str(candidate.get("role", "HELP"))]


func _toggle_credit(index: int) -> void:
	var candidates := _credit_page_items()
	if index < 0 or index >= candidates.size():
		return
	var key := _credit_key(candidates[index])
	if _selected_credits.has(key):
		_selected_credits.erase(key)
	else:
		_selected_credits.append(key)
	_status = "Contributor-Credits zeigen nur den unveränderlichen Handle-Snapshot."
	_rebuild_widgets()


func _scroller_text() -> String:
	var option := IntroCatalog.selected_option(_scroller_options(), _scroller_index, IntroCatalog.FALLBACK_SCROLLERS[0])
	var time := get_node_or_null("/root/TimeManager")
	return IntroCatalog.format_scroller(option, _scene_handle(), _presenting_name(),
		disk.content_title.to_upper() if disk != null else "RELEASE",
		str(time.get("year")) if time != null else "1990")


func _intro_payload() -> Dictionary:
	var logo := IntroCatalog.selected_option(_logo_options(), _logo_index, IntroCatalog.FALLBACK_LOGOS[0])
	var palette := IntroCatalog.selected_option(_palette_options(), _palette_index, IntroCatalog.FALLBACK_PALETTES[0])
	var scroller := IntroCatalog.selected_option(_scroller_options(), _scroller_index, IntroCatalog.FALLBACK_SCROLLERS[0])
	var credits: Array = []
	for candidate in _optional_credit_candidates():
		if _selected_credits.has(_credit_key(candidate)):
			credits.append({
				"actor_id": str(candidate.get("actor_id", "")),
				"handle_snapshot": _credit_handle(candidate),
				"role": str(candidate.get("role", "CONTRIBUTOR")),
			})
	var groups := _accepted_groups()
	_group_index = clampi(_group_index, 0, maxi(0, groups.size() - 1))
	return {
		"creator_handle": _scene_handle(),
		"logo": IntroCatalog.option_id(logo, "slab"),
		"logo_style": IntroCatalog.option_id(logo, "slab"),
		"palette": IntroCatalog.option_id(palette, "night_copper"),
		"palette_id": IntroCatalog.option_id(palette, "night_copper"),
		"palette_colors": palette.get("colors", []),
		"effects": _selected_effects.duplicate(),
		"scroller_id": IntroCatalog.option_id(scroller, "signal"),
		"scroller_text": _scroller_text(),
		"credits": credits,
		"group_id": str(groups[_group_index].get("id", "")),
		"manual_patch": not _auto_used,
		"difficulty": _difficulty,
		"testboots": _boot_step,
	}


func _finalize_release() -> bool:
	if not _boot_complete:
		_status = "Vor dem Release fehlen die drei Testboots."
		return false
	var result: Dictionary = SceneReleaseManager.finalize_release(
		disk, _intro_payload(), _patch_result.duplicate(true))
	_final_result = result
	_finalized = bool(result.get("ok", false))
	_status = str(result.get("text", "Release gespeichert." if _finalized else "Release konnte nicht gespeichert werden."))
	if _finalized:
		_stage = Stage.COMPLETE
	_rebuild_widgets()
	return _finalized


func _launch_intro() -> void:
	if not _finalized or disk == null:
		return
	# Der Spielstart-Flow öffnet das persistierte Cracktro. Erst dessen eigener
	# [ Spiel starten ]-Klick darf `cracktro_seen` setzen.
	close_app()
	UIManager.play_disk_flow.call_deferred(disk)


# -------------------------------------------------------------- Deterministik

## Stabile Test-Hooks; sie umgehen keine Spielregel, sondern verkürzen nur
## Animationen in automatisierten Prüfungen.
func test_select_handle(value: String) -> bool:
	_handle_draft = value
	return _save_handle()


func test_complete_analysis(difficulty := "standard") -> bool:
	_difficulty = difficulty
	_analysis_running = true
	_analysis_progress = 1.0
	return _finish_analysis()


func test_use_auto_solution() -> bool:
	return _auto_solve()


func test_undo() -> bool:
	return _undo_answer()


func test_enter_boots() -> void:
	_enter_testboot()


func test_finish_boots() -> void:
	if _stage != Stage.TESTBOOT:
		_enter_testboot()
	_start_testboots()
	while _boot_step < 3:
		_advance_testboot()


func test_enter_intro() -> void:
	_enter_intro()


func test_payload() -> Dictionary:
	return _intro_payload()


# ------------------------------------------------------------------- Prozess

func _hardware_speed() -> float:
	# Analyse/Assembler/Testboot sind echte CPU-Arbeit. Eine Turbokarte soll hier
	# spürbar helfen, ohne die Animation selbst auf einem 060 unsichtbar kurz zu
	# machen. Mechanische Diskettenzeiten bleiben davon bewusst unberührt.
	return clampf(PlayerStats.performance_multiplier(), 1.0, 4.0)


func _app_process(delta: float) -> void:
	_anim_t += delta
	var hardware_speed := _hardware_speed()
	if _analysis_running:
		_analysis_progress = minf(1.0,
			_analysis_progress + delta * 0.55 * hardware_speed)
		if _analysis_progress >= 1.0:
			_finish_analysis()
	if _boot_running:
		_boot_timer += delta * hardware_speed
		if _boot_timer >= 0.82:
			_boot_timer = 0.0
			_advance_testboot()


# ------------------------------------------------------------------ Zeichnen

func _content(font: Font) -> void:
	_draw_phase_strip(font)
	if _blocked:
		_draw_blocked(font)
	else:
		match _stage:
			Stage.HANDLE: _draw_handle(font)
			Stage.ANALYSE: _draw_analysis(font)
			Stage.PATCH: _draw_patch(font)
			Stage.TESTBOOT: _draw_testboot(font)
			Stage.INTRO: _draw_intro(font)
			Stage.COMPLETE: _draw_complete(font)
	_draw_status(font)


func _draw_phase_strip(font: Font) -> void:
	var labels := ["HANDLE", "ANALYSE", "P-8 MATRIX", "3× TESTBOOT", "INTRO"]
	for i in labels.size():
		# Rechts bleibt Platz für den globalen AUFSTEHEN-Knopf der Computerebene.
		var x := 8.0 + i * 105.0
		var reached := i <= mini(_stage, Stage.INTRO)
		var active := i == _stage
		rect(x, 24, 98, 22, C_BLUE if active else (Color8(41, 87, 105) if reached else Color8(27, 37, 52)))
		rect_line(x, 24, 98, 22, C_GOLD if active else Color8(63, 83, 98))
		text_c(font, labels[i], x, x + 98, 39, 8, C_GOLD if active else (C_INK if reached else C_DIM))


func _draw_blocked(font: Font) -> void:
	_draw_panel(Rect2(66, 92, 508, 210))
	_draw_disk_icon(Vector2(92, 124), C_RED)
	text(font, "ARBEITSKOPIE NICHT BEREIT", 174, 142, 15, C_RED)
	text(font, "BYTEWERK arbeitet nur mit einer passenden Gen-1-Arbeitskopie", 174, 172, 9, C_INK)
	text(font, "eines kuratierten, fiktiven Spieltitels. Das Original bleibt unangetastet.", 174, 190, 9, C_DIM)
	text(font, "Werkbank > Disketten > X-COPY: erst kopieren, dann die Kopie markieren.", 174, 224, 9, C_GOLD)


func _draw_handle(font: Font) -> void:
	_draw_panel(Rect2(52, 66, 536, 268))
	text_c(font, "WÄHLE DEINEN SZENE-HANDLE", 52, 588, 92, 16, C_GOLD)
	text_c(font, "Dieser Alias erscheint auf BBS-Boards und in Intros. Ein Klarname wird nie übernommen.", 52, 588, 114, 8, C_DIM)
	button3d(Rect2(158, 128, 324, 38), Color8(16, 26, 36), true)
	text_c(font, _handle_draft + ("_" if fmod(_anim_t, 1.0) < 0.55 else " "), 158, 482, 153, 15, C_GREEN)
	text_c(font, "Tastatur: A–Z · 0–9 · _ · - · Backspace", 52, 588, 177, 8, C_DIM)
	text_c(font, "Vorschläge sind zufällig und niemals aus deinem Spielernamen abgeleitet.", 52, 588, 270, 8, C_BLUE)


func _draw_analysis(font: Font) -> void:
	_draw_panel(Rect2(34, 68, 572, 250))
	_draw_disk_icon(Vector2(66, 94), C_BLUE)
	text(font, "P-8 PRÜFSIGNATUR-ANALYSE", 154, 102, 14, C_GOLD)
	text(font, disk.display_name() if disk != null else "—", 154, 124, 10, C_INK)
	text(font, "Fiktives Muster · keine Adressen · keine Opcodes · keine echten Patchdaten", 154, 144, 8, C_DIM)
	text(font, "ANALYSETIEFE", 74, 158, 9, C_BLUE)
	if _analysis_running:
		var w := 456.0
		rect(92, 224, w, 18, Color8(8, 13, 21))
		rect(94, 226, (w - 4) * _analysis_progress, 14, C_GREEN)
		rect_line(92, 224, w, 18, C_DIM)
		text_c(font, "%d%%  ·  PRÜFMUSTER WIRD SYNTHETISIERT" % roundi(_analysis_progress * 100.0), 92, 548, 266, 9, C_GREEN)
	else:
		text_c(font, "Kein Zeitlimit. Jede Schwierigkeit führt zu einem stabilen Release.", 34, 606, 218, 9, C_DIM)


func _draw_patch(font: Font) -> void:
	Renderer.draw_patch(self,font)
func _draw_testboot(font: Font) -> void:
	Renderer.draw_testboot(self,font)
func _draw_intro(font: Font) -> void:
	text(font, "INTRO-COMPOSER", 18, 70, 13, C_GOLD)
	text(font, "Logo", 18, 88, 8, C_DIM)
	text(font, _option_name(_logo_options()[_logo_index]), 222, 110, 9, C_GOLD)
	text(font, "Palette", 18, 126, 8, C_DIM)
	text(font, _option_name(_palette_options()[_palette_index]), 222, 148, 9, C_GOLD)
	text(font, "EFFEKTE  %d/3" % _selected_effects.size(), 18, 180, 8, C_DIM)
	text(font, "SCROLLER", 18, 276, 8, C_DIM)
	text(font, "PRÄSENTATION", 222, 178, 8, C_DIM)
	text(font, "HANDLE-CREDITS", 222, 220, 8, C_DIM)
	_draw_intro_preview(font, Rect2(394, 78, 228, 236))
func _draw_intro_preview(font: Font, area: Rect2) -> void:
	Renderer.draw_intro_preview(self,font,area)
func _active_colors() -> Array[Color]:
	var palette := IntroCatalog.selected_option(_palette_options(), _palette_index, IntroCatalog.FALLBACK_PALETTES[0])
	return IntroCatalog.palette_colors(palette, [C_BG, C_BLUE, C_MAGENTA, C_GOLD, C_INK])
func _draw_complete(font: Font) -> void:
	Renderer.draw_complete(self,font)
func _draw_status(font: Font) -> void:
	Renderer.draw_status(self,font)
func _draw_panel(area: Rect2) -> void:
	Renderer.draw_panel(self,area)
func _draw_disk_icon(at: Vector2, glow: Color) -> void:
	Renderer.draw_disk_icon(self,at,glow)
