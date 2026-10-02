## Zustandsfreie UI-Bausteine des Szene-Studios, ausgelagert aus
## demo_maker_window.gd (line_budget ≤1000). KEIN class_name → Pfad-preload,
## sonst raced der globale Klassen-Cache mit dem laufenden Editor
## (siehe [[modularization-rule]]).
extends RefCounted


static func line_edit(node_name: String, min_width := 0, max_length := 160) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = node_name
	edit.max_length = max_length
	edit.select_all_on_focus = true
	edit.caret_blink = true
	if min_width > 0:
		edit.custom_minimum_size.x = min_width
	return edit


static func labeled(label_text: String, control: Control, font_size := 11) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)
	box.add_child(Bezel.dim_label(label_text, font_size))
	box.add_child(control)
	return box


static func wrapped_dim(text: String, font_size := 11) -> Label:
	var label := Bezel.dim_label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 30)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func fill_option(option: OptionButton, catalog: Array, clear := true) -> void:
	if clear:
		option.clear()
	for item: Dictionary in catalog:
		var index := option.item_count
		option.add_item(str(item.get("name", item.get("id", "OPTION"))).to_upper())
		option.set_item_metadata(index, str(item.get("id", "")))


static func select_option(option: OptionButton, wanted: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == wanted:
			option.select(index)
			return
	if option.item_count > 0:
		option.select(0)


static func catalog_name(kind: String, id: String) -> String:
	for item: Dictionary in DemoManager.catalog(kind):
		if str(item.get("id", "")) == id:
			return str(item.get("name", id))
	return id


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func issue_text(issue: Variant) -> String:
	if issue is Dictionary:
		return str(issue.get("message", issue.get("text", issue.get("code", "Unbekannter Fehler"))))
	return str(issue)


static func clean_title(value: String, fallback: String) -> String:
	var clean := value.strip_edges().to_upper()
	return clean if clean != "" else fallback


## Build und Test sind die Hauptaktionen der festen Kommandozeile.
static func accent_command(button: Button, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(accent, 0.12)
	normal.border_color = Color(accent, 0.8)
	normal.set_border_width_all(1)
	normal.border_width_bottom = 3
	normal.set_content_margin_all(7)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.24)
	hover.border_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.34)
	pressed.border_width_bottom = 1
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", accent.lightened(0.3))
