extends RetroWindow
## Schulhof-Gespräch: was eine Gruppe gerade tuschelt (in IHRER Verzerrung),
## oder das Schwarze Brett (was sich bestätigt hat bzw. bloß Gerücht war).
## mode: "group" (mit group_id) | "board".

var mode := "group"
var group_id := ""

var _screen: RichTextLabel


func _init() -> void:
	win_size = Vector2(430, 300)


func _ready() -> void:
	if mode == "board":
		title = Loc.t("ui.rumor_window.schwarzes_brett", "SCHWARZES BRETT")
	else:
		title = RumorManager.group_by_id(group_id).get("name", "Schulhof").to_upper()
	super._ready()
	RumorManager.rumors_changed.connect(_refresh)

	_screen = RichTextLabel.new()
	_screen.bbcode_enabled = true
	_screen.fit_content = true
	_screen.scroll_active = true
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen.add_theme_font_size_override("normal_font_size", 12)
	content.add_child(_screen)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(make_button(Loc.t("ui.rumor_window.weiterziehen", "Weiterziehen"), queue_free))
	content.add_child(buttons)

	_refresh()


func _refresh() -> void:
	if mode == "board":
		_render_board()
	else:
		_render_group()


func _render_group() -> void:
	var group_name: String = RumorManager.group_by_id(group_id).get("name", "Sie")
	var rumors := RumorManager.rumors_for_group(group_id)
	var lines := ["[color=#cfc]%s:[/color]" % group_name, ""]
	if rumors.is_empty():
		lines.append("[i]Sie reden über Lehrer, das Wochenende und wer mit wem …[/i]")
		lines.append("")
		lines.append("[color=#8a8]Nichts Brauchbares. Vielleicht später wieder vorbeischauen —")
		lines.append("oder eine andere Gruppe fragen.[/color]")
	else:
		lines.append("„Ey, haste schon gehört?“")
		lines.append("")
		for r in rumors:
			lines.append("[color=#fe9]»[/color] %s" % r)
			lines.append("")
		lines.append("[color=#8a8]Wie zuverlässig das ist? Kommt drauf an, wer's erzählt.[/color]")
	_screen.text = "\n".join(lines)


func _render_board() -> void:
	var board := RumorManager.notice_board()
	var lines := ["[color=#cfc]Schwarzes Brett — was dabei rauskam:[/color]", ""]
	if board.is_empty():
		lines.append("[i]Ein paar vergilbte Zettel. Noch hat sich kein Gerücht")
		lines.append("des Hofes bestätigt — dafür ist es zu früh.[/i]")
	else:
		for e in board:
			if bool(e.get("truth", false)):
				lines.append("[color=#8f8]✓ Bestätigt:[/color] %s" % e.get("text", ""))
			else:
				lines.append("[color=#f99]✗ War nur ein Gerücht:[/color] %s" % e.get("text", ""))
			lines.append("")
	_screen.text = "\n".join(lines)
