class_name BulletinBoardWindow
extends RetroWindow
## SCHWARZES BRETT — physische Aushänge eines Ortes (BulletinManager), plus die
## Zettel, die der Spieler selbst anpinnt. Bretter mit "rumors" verlinken zusätzlich
## das Gerüchte-Fenster. board_id wird vor dem Öffnen gesetzt (toggle_window-Factory).

var board_id := ""

# cat -> [Label, Farbe]
const CATS := {
	"tausch":       ["trade", "TAUSCH", Color8(90, 190, 190)],
	"gesuch":       ["wanted", "GESUCHT", Color8(110, 150, 230)],
	"party":        ["party", "PARTY", Color8(205, 120, 210)],
	"compo":        ["competition", "WETTBEWERB", Color8(230, 175, 70)],
	"kleinanzeige": ["classified", "KLEINANZEIGE", Color8(120, 195, 120)],
	"kurs":         ["course", "KURS", Color8(90, 200, 210)],
	"info":         ["info", "INFO", Color8(160, 165, 175)],
	"amtlich":      ["official", "AMTLICH", Color8(150, 170, 205)],
}


func _init() -> void:
	title = Loc.t("ui.bulletin_board_window.schwarzes_brett", "SCHWARZES BRETT")
	win_size = Vector2(500, 546)


func _ready() -> void:
	var b := BulletinManager.board(board_id)
	if b.has("title"):
		title = str(b["title"])
	super._ready()
	_rebuild()


func _rebuild() -> void:
	for c in content.get_children():
		c.queue_free()
	var b := BulletinManager.board(board_id)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 7)
	scroll.add_child(col)

	# Eigene Zettel zuerst (neueste oben).
	var pins := BulletinManager.pins_for(board_id)
	for i in range(pins.size() - 1, -1, -1):
		col.add_child(_note({
			"cat": "_eigen", "title": Loc.t("ui.bulletin_board_window.your_notice", "Dein Aushang"),
			"text": str(pins[i].get("text", "")),
			"by": str(pins[i].get("by", Loc.t("ui.bulletin_board_window.you", "du"))),
			"date": str(pins[i].get("date", "")),
		}))

	var posts := BulletinManager.postings_for(board_id)
	if posts.is_empty() and pins.is_empty():
		col.add_child(Bezel.dim_label(Loc.t("ui.bulletin_board_window.am_brett_hangt_gerade_nichts_hang", "Am Brett hängt gerade nichts. Häng doch selbst einen Zettel auf."), 12))
	for p: Dictionary in posts:
		col.add_child(_note(p))

	# --- Selbst anpinnen ---
	var pin_row := HBoxContainer.new()
	pin_row.add_theme_constant_override("separation", 6)
	var edit := LineEdit.new()
	edit.placeholder_text = Loc.t("ui.bulletin_board_window.deinen_zettel_schreiben", "Deinen Zettel schreiben …")
	edit.max_length = 90
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pin_row.add_child(edit)
	pin_row.add_child(make_button(Loc.t("ui.bulletin_board_window.anpinnen", "📌 Anpinnen"), func() -> void:
		if BulletinManager.pin(board_id, edit.text):
			AudioManager.play("paper", 0.0)
			UIManager.toast(Loc.t("ui.bulletin_board_window.zettel_angepinnt", "Zettel angepinnt."))
			_rebuild()
		else:
			UIManager.toast(Loc.t("ui.bulletin_board_window.schreib_erst_was_auf_den_zettel", "Schreib erst was auf den Zettel."))))
	content.add_child(pin_row)

	# Gerüchte-Zugang (Bretter, die auch Neuigkeiten führen).
	if b.has("rumors"):
		content.add_child(make_button(Loc.t("ui.bulletin_board_window.neuigkeiten_geruchte_horen", "🗣 Neuigkeiten & Gerüchte hören"),
			func() -> void: UIManager.open_rumors(str(b["rumors"]))))


## Ein angepinnter Zettel: Kategorie-Farbstreifen + Titel + Text + Absender.
func _note(p: Dictionary) -> Control:
	var cat := str(p.get("cat", "info"))
	var meta: Array = CATS.get(cat, ["info", "", Color8(160, 165, 175)])
	var accent: Color = Color8(235, 205, 120) if cat == "_eigen" else (meta[2] as Color)
	var label: String = Loc.t("ui.bulletin_board_window.your_notice_upper", "DEIN AUSHANG") \
		if cat == "_eigen" else _category_label(str(meta[0]), str(meta[1]))

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(233, 226, 200) if cat == "_eigen" else Color8(228, 224, 206)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 9; sb.content_margin_right = 9
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.25); sb.shadow_size = 2; sb.shadow_offset = Vector2(1, 1)
	card.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	card.add_child(box)

	var head := Label.new()
	head.text = Loc.t("ui.bulletin_board_window.s_s", "%s   ·   %s") % [label, str(p.get("title", ""))]
	head.add_theme_color_override("font_color", Color8(40, 38, 30))
	head.add_theme_font_size_override("font_size", 13)
	box.add_child(head)

	var body := Label.new()
	body.text = str(p.get("text", ""))
	body.add_theme_color_override("font_color", Color8(72, 66, 54))
	body.add_theme_font_size_override("font_size", 11)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)

	var by := str(p.get("by", ""))
	var date := str(p.get("date", ""))
	if by != "" or date != "":
		var foot := Label.new()
		foot.text = ("— %s" % by) + (("  ·  %s" % date) if date != "" else "")
		foot.add_theme_color_override("font_color", Color8(120, 110, 92))
		foot.add_theme_font_size_override("font_size", 11)
		box.add_child(foot)
	return card


## Explizite Schluessel statt eines dynamisch zusammengesetzten Loc-Schluessels:
## So bleiben alle Kategorien fuer den Katalog-Extractor sichtbar und koennen
## beim Live-Sprachwechsel verlaesslich neu aufgebaut werden.
func _category_label(category: String, fallback: String) -> String:
	match category:
		"trade": return Loc.t("ui.bulletin_board_window.category_trade", "TAUSCH")
		"wanted": return Loc.t("ui.bulletin_board_window.category_wanted", "GESUCHT")
		"party": return Loc.t("ui.bulletin_board_window.category_party", "PARTY")
		"competition": return Loc.t("ui.bulletin_board_window.category_competition", "WETTBEWERB")
		"classified": return Loc.t("ui.bulletin_board_window.category_classified", "KLEINANZEIGE")
		"course": return Loc.t("ui.bulletin_board_window.category_course", "KURS")
		"info": return Loc.t("ui.bulletin_board_window.category_info", "INFO")
		"official": return Loc.t("ui.bulletin_board_window.category_official", "AMTLICH")
	return fallback
