class_name NewGameSetup
extends Control
## Spielstart-Setup von SOMMER '90 — Charakter-Erstellung als Aushängeschild:
## zentrierte Karte im Spiel-Theme (VT323), Copper-Bar-Homage, Avatar auf einer
## „Bühne" (Glühen + Bodenschatten, animiert: blinzelt/schaut/gähnt), Merkmale
## als ◄ Wert ►-Zeilen MIT sichtbarem Wert (WYSIWYG: Anzeige == Avatar).
## „Los geht's" schreibt alles in PlayerIdentity und startet GameManager.new_game().

const MONTHS := ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
## Merkmalszeilen: [Hint-Key, Label]. Reihenfolge = Anzeige.
const FEATURES := [
	["skin", "Hautton"], ["face_shape", "Gesicht"], ["hair_style", "Frisur"],
	["hair", "Haarfarbe"], ["eye_type", "Augen"], ["eye_color", "Augenfarbe"],
	["ears", "Ohren"], ["glasses", "Brille"], ["hat", "Hut/Cap"], ["beard", "Bart"],
	["top", "Oberteil"], ["personality", "Lieblingsfarbe"],
]
## Deutsche Anzeigenamen der Options-Tokens (Fallback: capitalize).
const VAL_DE := {
	"beige": "Beige", "sand": "Sand", "tan": "Gebräunt", "pale": "Blass",
	"brown": "Braun", "black": "Schwarz", "grey": "Grau", "blond": "Blond",
	"ginger": "Rotblond", "auburn": "Kastanie", "white": "Weiß", "platinum": "Platin",
	"red": "Rot", "blue": "Blau", "pink": "Pink", "green": "Grün", "teal": "Türkis",
	"orange": "Orange", "violet": "Violett", "mustard": "Senfgelb",
	"buzzcut": "Raspelkurz", "short": "Kurz", "parted": "Scheitel", "messy": "Zerzaust",
	"curly": "Locken", "straight": "Glatt", "medium": "Halblang", "long": "Lang",
	"ponytail": "Pferdeschwanz", "mullet": "Vokuhila", "bob": "Bob", "mohawk": "Irokese",
	"afro": "Afro", "bun": "Dutt", "pigtails": "Zöpfe", "spiky": "Stachelig",
	"quiff": "Tolle", "flattop": "Flattop", "bald": "Glatze",
	"oval": "Oval", "round": "Rund", "square": "Eckig", "heart": "Herzförmig",
	"normal": "Normal", "narrow": "Schmal", "wide": "Groß", "droopy": "Verträumt",
	"plain": "Normal", "big": "Groß",
	"": "Keine", "none": "Keine", "thick": "Hornbrille", "aviator": "Pilotenbrille",
	"cat": "Cat-Eye", "half": "Lesebrille", "sunglasses": "Sonnenbrille",
	"cap": "Basecap", "cap_back": "Cap verkehrt", "beanie": "Beanie", "winter": "Wintermütze",
	"headband": "Stirnband", "bandana": "Bandana", "bucket": "Anglerhut", "sunhat": "Sonnenhut",
	"tophat": "Zylinder", "fedora": "Fedora", "cowboy": "Cowboyhut", "flatcap": "Schiebermütze",
	"visor": "Visor", "party": "Partyhut", "crown": "Krone", "santa": "Weihnachtsmütze",
	"helmet": "Helm", "headphones": "Kopfhörer",
	"stubble": "Stoppeln", "mustache": "Schnurrbart", "goatee": "Ziegenbart", "chin": "Kinnbart",
	"full": "Vollbart", "sideburns": "Koteletten", "soulpatch": "Fliege",
	"handlebar": "Zwirbelbart", "muttonchops": "Backenbart", "longbeard": "Rauschebart",
	"stripes": "Streifen", "hoodie": "Kapuzenpulli", "jacket": "Jacke", "tanktop": "Tanktop",
	"polo": "Polo", "vneck": "V-Ausschnitt", "overall": "Latzhose", "logo": "Logo-Shirt",
}

var _seed := "player"
var _hints: Dictionary = {}
var _opts: Dictionary = {}
var _idx: Dictionary = {}          # feature_key -> aktueller Options-Index
var _value_labels: Dictionary = {} # feature_key -> Label (zeigt gewählten Wert)
var _feature_name_labels: Dictionary = {}
var _form_labels: Dictionary = {}
var _title_label: Label
var _intro_label: Label
var _dice_button: Button
var _starting := false
var _start_button: Button
var _back_button: Button
var _avatar_fig: MiniFigure
var _mini: MiniFigure
var _stage: Control
var _card: PanelContainer
var _gender := "m"
var _gender_btn: Button
var _name_edit: LineEdit
var _day: SpinBox
var _month: OptionButton
var _age_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()               # Spiel-Schrift & -Stile (VT323)
	Localization.locale_changed.connect(_on_locale_changed)
	_opts = PortraitGen.options()
	# „Niemand wird grauhaarig geboren" (PortraitGen remappt grey bei Kindern) —
	# also Grau hier gar nicht erst anbieten, sonst stimmt Anzeige ≠ Avatar.
	var hair: Array = (_opts.get("hair", []) as Array).duplicate()
	hair.erase("grey")
	hair.erase("white")
	_opts["hair"] = hair
	_seed = "player_%d" % (randi() % 100000)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.045, 0.045, 0.075)
	add_child(bg)

	# Zentrierte Karte
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.09, 0.12)
	sb.border_color = Palette.UI_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 26; sb.content_margin_right = 26
	sb.content_margin_top = 18; sb.content_margin_bottom = 20
	_card.add_theme_stylebox_override("panel", sb)
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_card.add_child(col)

	# Titel + Copper-Bar (Amiga-Gruß) + Untertitel
	_title_label = Label.new()
	_title_label.text = Loc.t("ui.new_game_setup.dein_sommer_90_beginnt", "DEIN SOMMER '90 BEGINNT")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Palette.LCD_AMBER)
	col.add_child(_title_label)
	var copper := _Copper.new()
	copper.custom_minimum_size = Vector2(0, 6)
	col.add_child(copper)
	_intro_label = Label.new()
	_intro_label.text = Loc.t("ui.new_game_setup.freitag_6_juli_1990_letzter_schultag", "Freitag, 6. Juli 1990 — letzter Schultag. Die Sommerferien beginnen. Wer bist du?")
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.add_theme_font_size_override("font_size", 14)
	_intro_label.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	col.add_child(_intro_label)
	col.add_child(_spacer(4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	col.add_child(row)
	row.add_child(_build_stage_column())
	row.add_child(_build_feature_column())
	row.add_child(_build_form_column())

	_randomize_all()
	_refresh_avatar()
	call_deferred("_entrance")


# ------------------------------------------------------------- Bühne (links)
func _build_stage_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)

	_stage = _Stage.new()
	# Zwei getrennte Pixelbuehnen: links die Ganzkoerperfigur, rechts das
	# Detailportraet. Bei 290 px lagen beide vorher rund 93 px uebereinander und
	# das Inset verdeckte den Kopf der Figur.
	_stage.custom_minimum_size = Vector2(350, 400)
	col.add_child(_stage)
	# Große Ganzkörper-Figur: FigurePaint32 arbeitet nativ mit 32×48;
	# 192×288 ist ein exakter 6×-Nearest-Schritt ohne ungleich breite Pixel.
	_avatar_fig = MiniFigure.new()
	_avatar_fig.as_figure = true
	_avatar_fig.bob = false
	_avatar_fig.custom_minimum_size = Vector2(192, 288)
	_avatar_fig.size = Vector2(192, 288)
	_stage.add_child(_avatar_fig)
	# Detailporträt: native 32×32, von PortraitGen exakt 4× auf 128×128.
	# Das Inset ist zugleich die verbindliche WYSIWYG-Gesichtsansicht.
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.05, 0.055, 0.085)
	fs.border_color = Palette.UI_BORDER_DARK
	fs.set_border_width_all(1)
	fs.set_corner_radius_all(3)
	fs.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", fs)
	_mini = MiniFigure.new()
	_mini.as_figure = false
	_mini.bob = false
	_mini.custom_minimum_size = Vector2(128, 128)
	_mini.size = Vector2(128, 128)
	frame.add_child(_mini)
	_stage.add_child(frame)
	_stage.resized.connect(func() -> void:
		var figure_lane_width := _stage.size.x - 142.0
		_avatar_fig.position = Vector2(maxf(8.0, (figure_lane_width - 192.0) * 0.5),
			_stage.size.y - 288.0 - 26.0)
		frame.position = Vector2(_stage.size.x - 142.0, 8.0))

	_dice_button = Button.new()
	_dice_button.text = Loc.t("ui.new_game_setup.wurfeln_neues_gesicht", "🎲  Würfeln — neues Gesicht")
	_dice_button.pressed.connect(_dice)
	col.add_child(_dice_button)
	_gender_btn = Button.new()
	_gender_btn.pressed.connect(func() -> void:
		_gender = "f" if _gender == "m" else "m"
		_update_gender_btn()
		_refresh_avatar(true))
	_update_gender_btn()
	col.add_child(_gender_btn)
	return col


func _update_gender_btn() -> void:
	_gender_btn.text = Loc.t("ui.new_game_setup.junge", "♂  Junge") if _gender == "m" \
		else Loc.t("ui.new_game_setup.girl", "♀  Mädchen")


func _dice() -> void:
	_seed = "player_%d" % (randi() % 100000)
	_randomize_all()
	_refresh_avatar()
	_shake(_avatar_fig)


# ------------------------------------------------------------- Merkmale (Mitte)
func _build_feature_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	for f: Array in FEATURES:
		col.add_child(_feature_row(str(f[0]), str(f[1])))
	return col


## Eine Merkmalszeile: Name · ◄ · gewählter Wert · ► — der Wert ist SICHTBAR.
func _feature_row(key: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_label := Label.new()
	name_label.text = _localized_feature_name(key, label)
	name_label.custom_minimum_size = Vector2(112, 0)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	_feature_name_labels[key] = name_label
	row.add_child(name_label)
	var prev := Button.new()
	prev.text = "◄"
	prev.custom_minimum_size = Vector2(30, 26)
	prev.pressed.connect(_cycle.bind(key, -1))
	row.add_child(prev)
	var val := Label.new()
	val.custom_minimum_size = Vector2(136, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_font_size_override("font_size", 15)
	val.add_theme_color_override("font_color", Palette.LCD_AMBER)
	_value_labels[key] = val
	row.add_child(val)
	var next := Button.new()
	next.text = "►"
	next.custom_minimum_size = Vector2(30, 26)
	next.pressed.connect(_cycle.bind(key, 1))
	row.add_child(next)
	return row


## Merkmal weiterschalten: Hint setzen, Wert-Label aktualisieren, Avatar poppt.
func _cycle(key: String, dir: int) -> void:
	var list: Array = _opts.get(key, [])
	if list.is_empty():
		return
	_idx[key] = wrapi(int(_idx.get(key, 0)) + dir, 0, list.size())
	_apply_hint(key)
	_flash(_value_labels[key])
	_refresh_avatar(true)


func _apply_hint(key: String) -> void:
	var list: Array = _opts.get(key, [])
	var val: String = str(list[int(_idx.get(key, 0))])
	if key == "glasses":
		_hints["glasses"] = "none" if val == "" else val
	else:
		_hints[key] = val
	var lbl: Label = _value_labels.get(key)
	if lbl != null:
		lbl.text = _localized_value(val)


## Alles neu würfeln — WYSIWYG: jede Zeile bekommt einen Wert UND setzt ihn als
## Hint (Anzeige == Avatar). Hüte/Brillen/Bärte meist „Keine" (sonst Karneval).
func _randomize_all() -> void:
	_hints.clear()
	for f: Array in FEATURES:
		var key: String = f[0]
		var list: Array = _opts.get(key, [])
		if list.is_empty():
			continue
		var i := randi() % list.size()
		match key:
			"hat":
				i = [1, 2, 3].pick_random() if randf() < 0.22 else 0   # meist ohne, sonst Cap/Beanie
			"glasses":
				i = [1, 2].pick_random() if randf() < 0.25 else 0
			"beard":
				i = 0                                                   # Kinder: kein Bart
		_idx[key] = i
		_apply_hint(key)


func _refresh_avatar(pop: bool = false) -> void:
	# Kindliches Startbild (1990): festes Jahr + Kind-Alter für die Vorschau.
	var h := _hints.duplicate(true)
	h["year"] = 1990
	h["age"] = "child"
	h["gender"] = _gender
	if _avatar_fig != null:
		_avatar_fig.setup(_seed, h, true)
	if _mini != null:
		_mini.setup(_seed, h, false)
	if pop and _avatar_fig != null:
		_pop(_avatar_fig)


# ------------------------------------------------------------- Formular (rechts)
func _build_form_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	col.add_child(_labeled("name", "Name", _make_name_edit()))

	var bd := HBoxContainer.new()
	bd.add_theme_constant_override("separation", 6)
	_day = SpinBox.new(); _day.min_value = 1; _day.max_value = 31; _day.value = 12
	_day.custom_minimum_size = Vector2(64, 0)
	_day.value_changed.connect(func(_v: float) -> void: _update_age())
	bd.add_child(_day)
	_month = OptionButton.new()
	for i in MONTHS.size():
		_month.add_item(_localized_month(i))
	_month.selected = 4
	_month.item_selected.connect(func(_i: int) -> void: _update_age())
	bd.add_child(_month)
	col.add_child(_labeled("birthday", "Geburtstag (Tag / Monat)", bd))

	_age_label = Label.new()
	_age_label.add_theme_font_size_override("font_size", 13)
	_age_label.add_theme_color_override("font_color", Palette.GREEN_LIGHT)
	col.add_child(_age_label)
	_update_age()

	col.add_child(_spacer(12))

	_start_button = Button.new()
	_start_button.text = Loc.t("ui.new_game_setup.los_geht_s", "▶  Los geht's!")
	_start_button.custom_minimum_size = Vector2(280, 46)
	_start_button.add_theme_font_size_override("font_size", 21)
	_start_button.add_theme_color_override("font_color", Palette.LCD_AMBER)
	_start_button.pressed.connect(_start_game)
	col.add_child(_start_button)

	_back_button = Button.new()
	_back_button.text = Loc.t("ui.new_game_setup.zuruck", "Zurück")
	_back_button.pressed.connect(func() -> void: queue_free())
	col.add_child(_back_button)
	return col


func _make_name_edit() -> Control:
	_name_edit = LineEdit.new()
	_name_edit.text = Loc.t("ui.new_game_setup.kevin", "Kevin")
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(240, 0)
	return _name_edit


func _update_age() -> void:
	var age := PlayerIdentity.START_AGE
	if 7 < int(_month.selected) + 1 or (int(_month.selected) + 1 == 7 and _day.value > 6):
		age -= 1   # Geburtstag 1990 noch nicht gewesen (Stichtag 6. Juli)
	_age_label.text = Loc.t("ui.new_game_setup.beim_start_bist_du_d_jahre", "Beim Start bist du %d Jahre alt — bis 1999 wächst du mit.") % age


func _start_game() -> void:
	if _starting:
		return
	_starting = true
	_start_button.disabled = true
	var slot := await SaveManager.choose_new_game_slot()
	if slot < 1:
		_starting = false
		_start_button.disabled = false
		return
	PlayerIdentity.player_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Kevin"
	PlayerIdentity.set_birthday(int(_day.value), int(_month.selected) + 1)
	PlayerIdentity.avatar_seed = _seed
	var saved := _hints.duplicate(true)
	saved["gender"] = _gender          # gewähltes Geschlecht MITSPEICHERN (Top-Avatar == erstellter)
	PlayerIdentity.avatar_hints = saved
	PlayerIdentity.identity_changed.emit()
	queue_free()
	SaveManager.start_new_game_with_screen(slot)


# ------------------------------------------------------------- Animation/Juice
## Karte sanft einblenden (Fade + leichtes Aufziehen).
func _entrance() -> void:
	if OS.get_environment("DSS_SHOT") == "1":
		return   # Proof-Screenshots: sofort voll sichtbar
	_card.pivot_offset = _card.size / 2.0
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel()
	tw.tween_property(_card, "modulate:a", 1.0, 0.22)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Kleiner Squash-Pop bei Merkmalswechsel.
func _pop(node: Control) -> void:
	node.pivot_offset = Vector2(node.size.x * 0.5, node.size.y)
	node.scale = Vector2(1.06, 0.94)
	create_tween().tween_property(node, "scale", Vector2.ONE, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Wackeln beim Würfeln.
func _shake(node: Control) -> void:
	var base := node.position.x
	var tw := create_tween()
	for off in [5.0, -4.0, 2.5, 0.0]:
		tw.tween_property(node, "position:x", base + off, 0.05)


## Wert-Label kurz aufblitzen lassen.
func _flash(l: Label) -> void:
	l.modulate = Color(1.7, 1.7, 1.7)
	create_tween().tween_property(l, "modulate", Color.WHITE, 0.3)


# ------------------------------------------------------------- kleine Helfer
func _labeled(key: String, fallback: String, control: Control) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var lbl := Label.new()
	lbl.text = Loc.t("ui.new_game_setup.form.%s" % key, fallback)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	_form_labels[key] = lbl
	row.add_child(lbl)
	row.add_child(control)
	return row


func _localized_feature_name(key: String, fallback: String) -> String:
	return Loc.t("ui.new_game_setup.feature.%s" % key, fallback)


func _localized_value(value: String) -> String:
	var normalized := "none" if value.is_empty() else value
	return Loc.t("ui.new_game_setup.value.%s" % normalized, str(VAL_DE.get(value, value.capitalize())))


func _localized_month(index: int) -> String:
	return Loc.t("ui.new_game_setup.month.%02d" % (index + 1), MONTHS[index])


func _on_locale_changed(_locale: String) -> void:
	if _title_label == null:
		return
	_title_label.text = Loc.t("ui.new_game_setup.dein_sommer_90_beginnt", "DEIN SOMMER '90 BEGINNT")
	_intro_label.text = Loc.t("ui.new_game_setup.freitag_6_juli_1990_letzter_schultag", "Freitag, 6. Juli 1990 — letzter Schultag. Die Sommerferien beginnen. Wer bist du?")
	_dice_button.text = Loc.t("ui.new_game_setup.wurfeln_neues_gesicht", "🎲  Würfeln — neues Gesicht")
	_start_button.text = Loc.t("ui.new_game_setup.los_geht_s", "▶  Los geht's!")
	_back_button.text = Loc.t("ui.new_game_setup.zuruck", "Zurück")
	_update_gender_btn()
	for feature: Array in FEATURES:
		var key := str(feature[0])
		var label: Label = _feature_name_labels.get(key)
		if label != null:
			label.text = _localized_feature_name(key, str(feature[1]))
		_apply_hint(key)
	var name_label: Label = _form_labels.get("name")
	if name_label != null:
		name_label.text = Loc.t("ui.new_game_setup.form.name", "Name")
	var birthday_label: Label = _form_labels.get("birthday")
	if birthday_label != null:
		birthday_label.text = Loc.t("ui.new_game_setup.form.birthday", "Geburtstag (Tag / Monat)")
	if _month != null:
		for i in _month.item_count:
			_month.set_item_text(i, _localized_month(i))
	_update_age()


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


## Amiga-Gruß: animierte Copper-Bars als schmaler Streifen unter dem Titel.
class _Copper extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var n := 72
		for i in n:
			var f := float(i) / n
			var phase := 0.5 + 0.5 * sin(TAU * (f * 1.6 - _t * 0.35))
			var col := Color(0.98, 0.62, 0.16).lerp(Color(0.82, 0.22, 0.5), phase)
			col = col.darkened(0.3 * (0.5 + 0.5 * sin(TAU * (f * 3.2 + _t * 0.6))))
			draw_rect(Rect2(size.x * f, 0, size.x / n + 1.0, size.y), col)


## Avatar-Bühne: dunkler Grund, weiches Glühen hinter der Figur, Bodenschatten.
class _Stage extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.06, 0.09))
		draw_rect(Rect2(Vector2.ZERO, size), Palette.UI_BORDER_DARK, false, 1.0)
		# Licht und Bodenschatten gehoeren zur linken Figurenbahn; rechts sind
		# 142 px exklusiv fuer das Portraet reserviert.
		var figure_center_x := (size.x - 142.0) * 0.5
		var c := Vector2(figure_center_x, size.y * 0.44)
		# Tight portrait-light behind the native figure.  The old huge, very dark
		# rings gave atmosphere but no local contrast around hair and trousers.
		for band in range(6, 0, -1):
			var band_rect := Rect2(
				Vector2(figure_center_x - 64.0 - band * 4.0, 54.0 - band * 3.0),
				Vector2(128.0 + band * 8.0, size.y - 92.0 + band * 4.0))
			draw_rect(band_rect, Color(0.20, 0.27, 0.49, 0.012 + band * 0.006), true)
		for i in range(11, 0, -1):
			draw_circle(c, size.y * 0.045 * i, Color(0.33, 0.42, 0.78, 0.022))
		# Weicher Bodenschatten unter den Füßen (mehrere gestaffelte Ellipsen)
		draw_set_transform(Vector2(figure_center_x, size.y - 28.0), 0.0, Vector2(1.0, 0.22))
		for j in range(3, 0, -1):
			draw_circle(Vector2.ZERO, size.x * 0.065 * j, Color(0, 0, 0, 0.13))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
