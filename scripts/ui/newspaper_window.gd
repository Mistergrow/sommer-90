class_name NewspaperWindow
extends RetroWindow
## ZEITUNGSSTÄNDER am Kiosk — beide Tagesblätter des Morgens nebeneinander:
## „Der Tagesbote" (seriöse Tageszeitung) und „Der Stadtblitz" (Boulevard). Jede
## zeigt ihr echtes Cover (jahr-/saisonrichtig) + ihre EIGENE Aufmacher-Schlagzeile,
## kleine Meldungen und den Pfennigpreis (aus data/newspapers.json, aus den Cover-
## JSONs extrahiert). So ist der Ära-Wandel jeden Morgen doppelt lesbar.

const DATA := "res://data/newspapers.json"
const ORDER := ["tagesbote", "stadtblitz"]
const NEWS_DIR := "res://assets/ui/newspapers"

static var _doc: Dictionary = {}


func _init() -> void:
	title = Loc.t("ui.newspaper_window.zeitungen_heute_morgen", "ZEITUNGEN · HEUTE MORGEN")
	win_size = Vector2(560, 604)


func _ready() -> void:
	super._ready()
	AudioManager.play("page_turn")
	var doc := _load()
	var papers: Dictionary = doc.get("papers", {})
	var editions: Dictionary = doc.get("editions", {})
	var year := str(TimeManager.year)
	var ek := _season_key()

	content.add_child(Bezel.lcd_label(Loc.t("ui.newspaper_window.s_d_am_kiosk", "%s, %d · am Kiosk") %
		[TimeManager.localized_weekday_name(), TimeManager.year], Color(0.6, 0.85, 1.0), 14))
	content.add_child(_delivery_shift_card())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)

	for pid in ORDER:
		var ed := _edition(editions, pid, year, ek)
		if ed.is_empty():
			continue
		col.add_child(_paper_card(pid, papers.get(pid, {}), ed, year))


## Der Zeitungshotspot am Kiosk ist zugleich die physische Arbeitsstation.
## Damit fuehrt das sichtbare Objekt direkt zur Route statt in eine Sackgasse,
## waehrend das Arbeitsheft weiterhin die Tagesplanung und Fernroute zeigt.
func _delivery_shift_card() -> Control:
	var job := JobManager.job_by_id("job_newspapers")
	var card := PanelContainer.new()
	card.name = "DeliveryShift"
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(8, 18, 24)
	style.border_color = Palette.LCD_CYAN
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(Bezel.lcd_label(Loc.t("ui.newspaper_window.route_title",
		"MORGENROUTE · ZEITUNGEN AUSTRAGEN"), Palette.LCD_AMBER, 12))
	var status := Bezel.dim_label("", 11)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(status)
	row.add_child(copy)
	var button := make_button(Loc.t("ui.newspaper_window.start_route", "ROUTE STARTEN"), func() -> void:
		queue_free()
		UIManager.open_job_shift("job_newspapers"))
	button.name = "StartDeliveryRoute"
	button.custom_minimum_size = Vector2(150, 48)
	row.add_child(button)
	var gate := JobManager.start_gate("job_newspapers")
	if bool(gate.get("ok", false)):
		var pay: Array = job.get("pay", [6, 10])
		status.text = Loc.t("ui.newspaper_window.route_ready",
			"BEREIT · 10 Haeuser · %d–%d DM + Leistungsbonus · echte Zustellroute") % [int(pay[0]), int(pay[1])]
		status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	else:
		button.disabled = true
		status.text = Loc.t("ui.newspaper_window.route_waiting",
			"NAECHSTE SCHICHT · MO–SA · MORGEN ODER MITTAG · %s") % str(gate.get("reason", ""))
		status.add_theme_color_override("font_color", Palette.LCD_AMBER)
	return card


func _load() -> Dictionary:
	if _doc.is_empty() and FileAccess.file_exists(DATA):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if parsed is Dictionary:
			_doc = parsed
	return _doc


func _season_key() -> String:
	match TimeManager.season_name().to_lower():
		"frühling", "fruehling": return "fruehling"
		"herbst": return "herbst"
	return "front"


## Ausgabe für Jahr+Saison, mit Rückfall auf die Standard-Titelseite.
func _edition(editions: Dictionary, pid: String, year: String, ek: String) -> Dictionary:
	var by_year: Dictionary = editions.get(pid, {}).get(year, {})
	if by_year.has(ek):
		return by_year[ek]
	if by_year.has("front"):
		return by_year["front"]
	return {}


func _paper_card(pid: String, paper: Dictionary, ed: Dictionary, year: String) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(24, 24, 28)
	sb.border_color = Color8(70, 74, 86)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 9; sb.content_margin_right = 9
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	# Cover (Hochformat 3:4)
	var cover_path := "%s/%s/%s/%s" % [NEWS_DIR, pid, year, str(ed.get("cover", ""))]
	if ResourceLoader.exists(cover_path):
		var frame := PanelContainer.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color8(12, 12, 14); fs.set_border_width_all(1); fs.border_color = Color8(90, 94, 104)
		frame.add_theme_stylebox_override("panel", fs)
		var tex := TextureRect.new()
		tex.texture = load(cover_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(150, 200)
		frame.add_child(tex)
		row.add_child(frame)

	# Text rechts
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	row.add_child(box)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(Bezel.lcd_label(str(paper.get("name", pid)), Color(0.95, 0.85, 0.45), 15))
	var price := str(ed.get("price", ""))
	if price != "":
		var pl := Bezel.dim_label(price, 11)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_row.add_child(pl)
	box.add_child(name_row)
	box.add_child(Bezel.dim_label(str(paper.get("kind", "")), 10))

	var head := Label.new()
	head.text = Loc.t("ui.newspaper_window.s", "»%s«") % str(ed.get("headline", ""))
	head.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	head.add_theme_font_size_override("font_size", 14)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)

	for m in ed.get("meldungen", []):
		var line := Bezel.dim_label(Loc.t("ui.newspaper_window.bullet", "· %s") % str(m), 11)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
	return card
