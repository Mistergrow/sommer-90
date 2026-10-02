class_name Bezel
## Baukasten für die Bezel-UI (Mockup-Stil): betitelte Panels, LCD-Werte,
## Statusbalken. Von Top-Bar, Sidebar und Bottom-Bar gemeinsam genutzt.

## Typografische Rollen. Auf dem 1440x810-Designraster ist 10 px Telemetrie,
## aber kein lesbarer Fliesstext. Neue Fenster sollen diese Rollen verwenden,
## statt willkuerliche Einzelgroessen zu verteilen.
const BODY_FONT_SIZE := 13
const SECONDARY_FONT_SIZE := 12
const META_FONT_SIZE := 10
const SECTION_FONT_SIZE := 12


## Panel mit Kopfzeile im Mockup-Stil. Rückgabe: {"root": Panel, "body": VBox}.
static func titled_panel(title: String) -> Dictionary:
	var root := PanelContainer.new()
	root.clip_contents = true
	root.add_theme_stylebox_override("panel", panel_box())
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	root.add_child(vbox)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Palette.WHITE_SOFT)
	header.clip_text = true
	header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.custom_minimum_size.x = 0.0
	vbox.add_child(header)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)
	# Der Header wird mitgegeben, damit dauerhafte HUD-Panels ihn bei einem
	# Sprachwechsel aktualisieren koennen, ohne das ganze Panel neu zu bauen.
	return {"root": root, "header": header, "body": body}


## LCD-artiger Wert (Geld, Ruf ...) in Leuchtfarbe.
static func lcd_label(text: String, color: Color, font_size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", Palette.BLACK)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 0.0
	return label


## Segment-LCD-Wert für Geldanzeigen wie im Mockup.
static func segment_label(text: String, color: Color, font_size: int = 15) -> Label:
	var label := lcd_label(text, color, font_size)
	var segment_font := load("res://assets/fonts/DSEG14Classic-Regular.ttf") as Font
	if segment_font != null:
		label.add_theme_font_override("font", segment_font)
	return label


## Schmaler Statusbalken (MÜDE/ELTERN ... in der Bottom-Bar, Energie oben).
static func bar(color: Color, min_size: Vector2 = Vector2(90, 10)) -> ProgressBar:
	var progress_bar := ProgressBar.new()
	progress_bar.custom_minimum_size = min_size
	progress_bar.show_percentage = false
	progress_bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color8(6, 6, 6)
	bg.border_color = Color8(35, 35, 33)
	bg.set_border_width_all(1)
	progress_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.border_color = color.darkened(0.35)
	fill.set_border_width_all(0)
	progress_bar.add_theme_stylebox_override("fill", fill)
	return progress_bar


## Sekundärtext (gedimmt, klein).
static func dim_label(text: String, font_size: int = 11) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", Palette.BLACK)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.x = 0.0
	return label


## Primaerer Nutztext. Bewusst heller und groesser als Metadaten.
static func body_label(text: String, font_size: int = BODY_FONT_SIZE) -> Label:
	var label := dim_label(text, maxi(font_size, BODY_FONT_SIZE))
	label.add_theme_color_override("font_color", Palette.UI_TEXT)
	label.set_meta("ui_text_role", "body")
	return label


## Abschnittsueberschrift fuer lange Listen und Inspektoren.
static func section_label(text: String, color: Color = Palette.LCD_AMBER) -> Label:
	var label := lcd_label(text, color, SECTION_FONT_SIZE)
	label.set_meta("ui_text_role", "section")
	return label


## Kompakte, aber noch lesbare Zusatzinformation. Nur echte Instrumenten- und
## Rasteranzeigen duerfen darunter gehen und muessen das lokal begruenden.
static func meta_label(text: String, font_size: int = META_FONT_SIZE) -> Label:
	var label := dim_label(text, maxi(font_size, META_FONT_SIZE))
	label.set_meta("ui_text_role", "meta")
	return label


static func panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(17, 17, 17)
	box.border_color = Color8(64, 64, 60)
	box.set_border_width_all(2)
	box.corner_radius_top_left = 1
	box.corner_radius_top_right = 1
	box.corner_radius_bottom_left = 1
	box.corner_radius_bottom_right = 1
	box.content_margin_left = 9.0
	box.content_margin_right = 9.0
	box.content_margin_top = 5.0
	box.content_margin_bottom = 5.0
	return box


## Displayflächen wie Saison-Animator oder Oszilloskop sitzen bereits in einem
## eigenen gezeichneten Rahmen. Diese Variante behält exakt dieselbe Bezel-
## Materialität, verschenkt aber nicht noch einmal 18 x 10 Pixel Innenraum.
static func display_box() -> StyleBoxFlat:
	var box := panel_box()
	box.content_margin_left = 3.0
	box.content_margin_right = 3.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	return box


static func slot_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(12, 12, 12)
	box.border_color = Color8(46, 46, 44)
	box.set_border_width_all(1)
	box.content_margin_left = 4.0
	box.content_margin_right = 4.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	return box
