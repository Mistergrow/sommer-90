extends WbApp
## TextKraft — kleine Textverarbeitung im Stil der Amiga-Schreibprogramme
## (Homage). Echtes Tippfeld (TextEdit) auf „Papier", Zeilen-/Wortzähler,
## NEU/GROSS-Werkzeuge. Ins Klare geschrieben, nicht gespeichert — reines
## Zeitkolorit.

var _edit: TextEdit


func _init() -> void:
	app_title = "TextKraft   ·   Textverarbeitung"
	app_bg = Color8(46, 44, 40)
	app_bar = Color8(80, 74, 64)
	app_accent = Color8(230, 210, 160)


func _build_app() -> void:
	_edit = TextEdit.new()
	_edit.placeholder_text = Loc.t("ui.text_editor_app.liebes_tagebuch_heute_habe_ich_am", "Liebes Tagebuch, heute habe ich am Flohmarkt ein Weltraumspiel gefunden …")
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.add_theme_font_size_override("font_size", 13)
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(244, 240, 228)
	box.set_border_width_all(1)
	box.border_color = Color8(120, 110, 90)
	box.set_content_margin_all(8)
	_edit.add_theme_stylebox_override("normal", box)
	_edit.add_theme_stylebox_override("focus", box)
	_edit.add_theme_color_override("font_color", Color8(30, 28, 24))
	_edit.add_theme_color_override("caret_color", Color8(30, 28, 24))
	_edit.add_theme_color_override("font_placeholder_color", Color8(150, 145, 130))
	add_child(_edit)

	add_button("NEU", Rect2(20, VH - 30, 90, 20), _new_doc, app_accent)
	add_button("GROSS", Rect2(116, VH - 30, 90, 20), _upper, app_accent)


func _layout_app() -> void:
	if _edit != null:
		var r := _R(Rect2(14, 44, VW - 28, VH - 82))
		_edit.position = r.position
		_edit.size = r.size


func _new_doc() -> void:
	_edit.text = ""


func _upper() -> void:
	_edit.text = _edit.text.to_upper()


func _content(font: Font) -> void:
	# Kopfzeile: Dokumentname + Zähler
	rect(14, 24, VW - 28, 16, Color8(30, 28, 24))
	text(font, "DOKUMENT.TXT", 24, 36, 10, app_accent)
	var t: String = _edit.text if _edit != null else ""
	var words := 0
	for part in t.split(" ", false):
		if part.strip_edges() != "":
			words += 1
	var lines := t.split("\n").size()
	text(font, "Zeilen: %d   Wörter: %d   Zeichen: %d" % [lines, words, t.length()],
		VW - 260, 36, 10, Color8(200, 190, 160))
	text(font, "Ins Feld klicken und tippen · Esc = zurück.", 24, VH - 8, 9, Color8(160, 150, 130))
