extends RetroWindow
## Generisches Info-Fenster (Hilfe, Jahreswechsel-Schlagzeilen, Tageszeitung).
## Optionales Titelbild (image_path) — z. B. die Zeitungs-Titelseite — wird oben
## im Hochformat angezeigt; fehlt das Bild, bleibt es reiner Text (kein Fehler).

var body_text: String = ""
var image_path: String = ""


func _init() -> void:
	title = Loc.t("ui.info_window.info", "INFO")
	win_size = Vector2(470, 300)


func _ready() -> void:
	var has_cover := image_path != "" and ResourceLoader.exists(image_path)
	if has_cover:
		win_size = Vector2(470, 480)   # mehr Platz für die Titelseite
	super._ready()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	if has_cover:
		var cover := TextureRect.new()
		cover.texture = load(image_path) as Texture2D
		cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cover.custom_minimum_size = Vector2(0, 260)
		cover.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(cover)

	var label := Label.new()
	label.text = body_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(make_button(Loc.t("ui.info_window.alles_klar", "Alles klar"), queue_free))
	content.add_child(buttons)
