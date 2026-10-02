extends RetroWindow
## Kopierschutz-Ritual der Ära — aus NUTZERSICHT (docs/KULTUR_LAYER.md):
## - Handbuch-Abfrage: mit Original liest man das Wort einfach ab (Ritual);
##   zur nackten Kopie gibt es kein Handbuch — raten oder Demomodus.
## - Code-Drehscheibe: mit Beilage dreht man den Ring aufs Symbol und liest
##   den Code ab; ohne Scheibe öffnet sich dieses Fenster gar nicht erst.
## Keine Umgehungs-Mechanik: Erfolg kommt vom BESITZ der Beilagen.

const WORDS := ["DISKETTENPUFFER", "PARALLAXWERT", "LADEROUTINE", "SEKTORPRUEFUNG",
	"KOPFPOSITION", "BOOTBLOCK", "TAKTFREQUENZ", "RASTERZEILE"]
const InsertCatalog := preload("res://scripts/data/software_insert_catalog.gd")
const SYMBOLS := ["☀", "☾", "★", "♦", "♣", "♠", "♥", "♪"]

var game_title := "???"
var software_id := ""
var protection := "handbuch"     # "handbuch" | "codewheel"
var has_beilagen := true         # Original: Handbuch/Drehscheibe liegt bei
var missing_beilagen: Array = [] # Bei CODE RED: echte fehlende Inventarobjekte
var on_result: Callable = Callable()

var _correct := ""
var _tries := 0
var _wheel_offset := 0           # Drehung des äußeren Rings (Index-Schritte)
var _target_symbol := 0          # Index des Symbols, das oben stehen muss
var _codes: Array = []           # 3 Code-Kandidaten (Strings)
var _status: Label
var _wheel_canvas: Control


func _init() -> void:
	title = Loc.t("ui.protection_window.kopierschutz", "KOPIERSCHUTZ")
	win_size = Vector2(460, 320)


func _ready() -> void:
	super._ready()
	if protection == "codewheel":
		_build_codewheel()
	elif software_id == "code_red_protocol":
		_build_code_red_handbuch()
	else:
		_build_handbuch()


# ------------------------------------------------------------- Handbuch

func _build_handbuch() -> void:
	var page := randi_range(12, 88)
	var line := randi_range(1, 9)
	var word := randi_range(1, 6)
	var options: Array = WORDS.duplicate()
	options.shuffle()
	options = options.slice(0, 3)
	_correct = options[randi() % 3]
	content.add_child(Bezel.dim_label(Loc.t("ui.protection_window.s_fragt_beim_start", "„%s“ fragt beim Start:") % game_title, 10))
	var ask := Label.new()
	ask.text = Loc.t("ui.protection_window.bitte_wort_von_seite_d_zeile", "»Bitte Wort von Seite %d, Zeile %d, Wort %d eingeben.«") % [page, line, word]
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(ask)
	if has_beilagen:
		var excerpt := Label.new()
		excerpt.text = Loc.t("ui.protection_window.ndu_blatterst_im_handbuch_seite_d", "\nDu blätterst im Handbuch … Seite %d, Zeile %d:\n»… über die %s wird der Puffer geleert …«\n") % [
			page, line, _correct]
		excerpt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		excerpt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
		content.add_child(excerpt)
	else:
		var no_manual := Label.new()
		no_manual.text = Loc.t("ui.protection_window.nzur_kopie_gibt_es_kein_handbuch", "\nZur Kopie gibt es kein Handbuch.\nBleibt nur: raten. Ein Versuch.\n")
		no_manual.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
		content.add_child(no_manual)
	_status = Bezel.dim_label("", 10)
	for option in options:
		content.add_child(make_button(option, _on_word.bind(option)))
	content.add_child(_status)


func _build_code_red_handbuch() -> void:
	var sector := randi_range(1, 8)
	var ring := randi_range(1, 6)
	var column := randi_range(1, 5)
	_correct = InsertCatalog.code_red_keyword(sector, ring, column)
	var options: Array = InsertCatalog.CODE_RED_WORDS.duplicate()
	options.shuffle()
	options = options.filter(func(value: String) -> bool: return value != _correct).slice(0, 2)
	options.append(_correct)
	options.shuffle()
	var heading := Label.new()
	heading.text = Loc.t("ui.protection_window.code_red_rotes_operations_handbuch", "CODE RED · ROTES OPERATIONS-HANDBUCH")
	heading.add_theme_color_override("font_color", Color(1.0, 0.32, 0.28))
	content.add_child(heading)
	var ask := Label.new()
	ask.text = Loc.t("ui.protection_window.archivtafel_d_ring_d_spalte_d", "»Archivtafel %d, Ring %d, Spalte %d: Kennwort?«") % [sector, ring, column]
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(ask)
	if has_beilagen:
		var excerpt := Label.new()
		excerpt.text = Loc.t("ui.protection_window.archive_reference",
			"\nLege die rote Bahnkarte neben das Handbuch.\nDie Antwort steht in deiner echten Archivtafel — nicht in diesem Dialog.\n")
		excerpt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		excerpt.add_theme_color_override("font_color", Color(1.0, 0.72, 0.58))
		content.add_child(excerpt)
		content.add_child(make_button(Loc.t("ui.protection_window.beilagen_aufschlagen", "BEILAGEN AUFSCHLAGEN"),
			_open_code_red_reference.bind(sector, ring, column)))
	else:
		var missing := Label.new()
		var names := ", ".join(missing_beilagen) if not missing_beilagen.is_empty() \
			else "rotes Handbuch und Bahnkarte"
		missing.text = Loc.t("ui.protection_window.nes_fehlt_s_nein_versuch_bleibt", "\nEs fehlt: %s.\nEin Versuch bleibt.\n") % names
		missing.add_theme_color_override("font_color", Color(1.0, 0.45, 0.42))
		content.add_child(missing)
	_status = Bezel.dim_label("", 10)
	for option: String in options:
		content.add_child(make_button(option, _on_word.bind(option)))
	content.add_child(_status)


func _open_code_red_reference(sector: int, ring: int, column: int) -> void:
	UIManager.open_software_inserts(software_id, "code_red_orbit_chart", {
		"sector": sector, "ring": ring, "column": column,
	})


func _on_word(word: String) -> void:
	if word == _correct:
		_finish(true)
		return
	_tries += 1
	if has_beilagen and _tries < 3:
		_status.text = Loc.t("ui.protection_window.verlesen_schau_nochmal_genau_hin_d", "Verlesen! Schau nochmal genau hin. (%d/3)") % (_tries + 1)
		return
	_finish(false)


# ------------------------------------------------------------- Drehscheibe

func _build_codewheel() -> void:
	_target_symbol = randi() % SYMBOLS.size()
	_wheel_offset = (_target_symbol + randi_range(1, 7)) % SYMBOLS.size()
	for i in 3:
		_codes.append(str(randi_range(100, 999)))
	_correct = _codes[randi() % 3]
	content.add_child(Bezel.dim_label(
		Loc.t("ui.protection_window.s_drehe_den_ausseren_ring_auf", "„%s“: »Drehe den äußeren Ring auf  %s  und gib den Code im Fenster ein.«") % [
			game_title, SYMBOLS[_target_symbol]], 10))
	_wheel_canvas = Control.new()
	_wheel_canvas.custom_minimum_size = Vector2(0, 130)
	_wheel_canvas.draw.connect(_draw_wheel)
	content.add_child(_wheel_canvas)
	var turn_row := HBoxContainer.new()
	turn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_row.add_child(make_button(Loc.t("ui.protection_window.drehen", "◀ drehen"), _turn.bind(-1)))
	turn_row.add_child(make_button(Loc.t("ui.protection_window.drehen_8a20", "drehen ▶"), _turn.bind(1)))
	content.add_child(turn_row)
	_status = Bezel.dim_label("", 10)
	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for code in _codes:
		code_row.add_child(make_button(code, _on_code.bind(code)))
	content.add_child(code_row)
	content.add_child(_status)


func _turn(direction: int) -> void:
	_wheel_offset = posmod(_wheel_offset + direction, SYMBOLS.size())
	_wheel_canvas.queue_redraw()


func _aligned() -> bool:
	return _wheel_offset == _target_symbol


func _on_code(code: String) -> void:
	if not _aligned():
		_status.text = Loc.t("ui.protection_window.fenster_zeigt_kauderwelsch_erst_den_ring", "Das Fenster zeigt Kauderwelsch — erst den Ring aufs Symbol drehen!")
		return
	if code == _correct:
		_finish(true)
		return
	_status.text = Loc.t("ui.protection_window.falscher_code_abgelesen_fenster_zeigt_s", "Falscher Code abgelesen? Das Fenster zeigt: %s") % _correct
	_tries += 1
	if _tries >= 3:
		_finish(false)


## Die Drehscheibe: äußerer Symbolring dreht, das „Fenster“ oben zeigt den
## Code des inneren Rings — nur bei richtiger Ausrichtung den echten.
func _draw_wheel() -> void:
	var c := _wheel_canvas
	var center := Vector2(c.size.x / 2.0, 68.0)
	c.draw_circle(center, 62.0, Color(0.85, 0.80, 0.68))
	c.draw_circle(center, 61.0, Color(0.10, 0.10, 0.12), false, 2.0)
	c.draw_circle(center, 40.0, Color(0.72, 0.66, 0.52))
	var font := ThemeDB.fallback_font
	for i in SYMBOLS.size():
		var angle := -PI / 2.0 + TAU * float(posmod(i - _wheel_offset, SYMBOLS.size())) / float(SYMBOLS.size())
		var p := center + Vector2(cos(angle), sin(angle)) * 51.0
		c.draw_string(font, p + Vector2(-6, 5), SYMBOLS[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.15, 0.12, 0.10))
	# Markierung + Sichtfenster oben
	c.draw_rect(Rect2(center.x - 16, center.y - 78, 32, 16), Color(0.10, 0.10, 0.12))
	c.draw_string(font, Vector2(center.x - 14, center.y - 66),
		_correct if _aligned() else "?#%", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(0.4, 1.0, 0.6) if _aligned() else Color(0.9, 0.5, 0.4))
	c.draw_string(font, Vector2(center.x - 6, center.y + 6), "▲",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.2, 0.15, 0.1))


# ------------------------------------------------------------- Abschluss

func _finish(ok: bool) -> void:
	if on_result.is_valid():
		on_result.call(ok)
	queue_free()
