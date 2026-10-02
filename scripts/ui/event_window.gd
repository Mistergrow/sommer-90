extends RetroWindow
## Ereignisfenster: präsentiert ein Zufallsereignis mit Wahlmöglichkeiten.
## Nicht erfüllbare Wahlen (fehlendes Item/Geld) sind ausgegraut.

var event: Dictionary = {}


func _init() -> void:
	title = Loc.t("ui.event_window.ereignis", "EREIGNIS")
	win_size = Vector2(460, 240)


func _ready() -> void:
	super._ready()
	title = event.get("title", "EREIGNIS")

	var heading := Bezel.lcd_label(event.get("title", ""), Palette.LCD_AMBER, 13)
	content.add_child(heading)

	var text := Label.new()
	text.text = event.get("text", "")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(text)

	for choice in event.get("choices", []):
		var button := make_button(Loc.t("ui.event_window.text", "> ") + choice.get("text", "..."), _resolve.bind(choice))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not EventManager.choice_available(choice):
			button.disabled = true
			button.text += "  (fehlt: %s)" % _requirement_hint(choice)
		content.add_child(button)


func _requirement_hint(choice: Dictionary) -> String:
	if choice.has("requires_item"):
		return InventoryManager.ITEM_NAMES.get(choice["requires_item"], choice["requires_item"])
	if choice.has("requires_money"):
		return "%d DM" % int(choice["requires_money"])
	return "?"


func _resolve(choice: Dictionary) -> void:
	var result: Dictionary = EventManager.resolve_choice(choice, str(event.get("id", "")))
	if bool(result.get("ok", false)):
		queue_free()
