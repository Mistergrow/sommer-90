class_name WbTextWindow
extends Wb13Window
## Native Text-/Informationsbox der Workbench. Anders als UIManager.open_info
## bleibt sie vollständig im virtuellen Workbench-Desktop: Topaz, Vierfarben-
## palette, klassische Gadgets, Scrollleiste und ein gezeichneter OK-Knopf.

const LINE_HEIGHT := 18.0
const TEXT_MARGIN := 10.0
const BUTTON_SIZE := Vector2(68.0, 20.0)

var body_text := ""
var heading := ""
var accept_label := "OK"


func _init() -> void:
	title = Loc.t("ui.wb_text_window.information", "Information")
	resizable = false


func configure(window_title: String, message: String, message_heading := "") -> void:
	title = window_title
	body_text = message
	heading = message_heading
	scroll_y = 0.0
	_refresh_content_height()
	queue_redraw()


func message_text() -> String:
	return body_text


func sync_layout() -> void:
	super.sync_layout()
	_refresh_content_height()


func _refresh_content_height() -> void:
	var cr := content_rect()
	var line_count := _wrapped_lines(_line_width()).size()
	var heading_height := LINE_HEIGHT + 4.0 if not heading.is_empty() else 0.0
	_content_h = maxf(cr.size.y,
		TEXT_MARGIN + heading_height + line_count * LINE_HEIGHT + BUTTON_SIZE.y + 22.0)
	scroll_y = clampf(scroll_y, 0.0, maxf(0.0, _content_h - cr.size.y))


func _line_width() -> int:
	return maxi(12, floori((content_rect().size.x - TEXT_MARGIN * 2.0) / 8.0))


func _wrapped_lines(max_chars: int) -> Array[String]:
	var result: Array[String] = []
	for paragraph: String in body_text.split("\n", true):
		if paragraph.is_empty():
			result.append("")
			continue
		var current := ""
		for word: String in paragraph.split(" ", false):
			var candidate := word if current.is_empty() else current + " " + word
			if candidate.length() <= max_chars or current.is_empty():
				current = candidate
			else:
				result.append(current)
				current = word
		if not current.is_empty():
			result.append(current)
	return result


func _button_rect() -> Rect2:
	var cr := content_rect()
	return Rect2(cr.size.x - BUTTON_SIZE.x - TEXT_MARGIN,
		_content_h - BUTTON_SIZE.y - 10.0, BUTTON_SIZE.x, BUTTON_SIZE.y)


func _content_draw(crp: Rect2, sx: float, sy: float) -> void:
	var font := Wb13.font()
	var fs := Wb13.fsize(sy)
	var y := TEXT_MARGIN - scroll_y
	if not heading.is_empty():
		_draw_text(crp, sx, sy, heading, TEXT_MARGIN, y + 14.0, font, fs, Wb13.orange())
		y += LINE_HEIGHT + 4.0
	for line: String in _wrapped_lines(_line_width()):
		_draw_text(crp, sx, sy, line, TEXT_MARGIN, y + 14.0, font, fs, Wb13.white())
		y += LINE_HEIGHT

	var button := _button_rect()
	button.position.y -= scroll_y
	var physical := Rect2(crp.position + Vector2(button.position.x * sx, button.position.y * sy),
		Vector2(button.size.x * sx, button.size.y * sy))
	draw_rect(physical, Wb13.white())
	draw_rect(physical, Wb13.black(), false, maxf(1.0, sy))
	draw_string(font, Vector2(physical.position.x, physical.position.y + 15.0 * sy),
		accept_label, HORIZONTAL_ALIGNMENT_CENTER, physical.size.x, fs, Wb13.black())


func _draw_text(crp: Rect2, sx: float, sy: float, value: String, x: float, y: float,
		font: Font, fs: int, color: Color) -> void:
	draw_string(font, crp.position + Vector2(x * sx, y * sy), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _content_press(v: Vector2, _dbl: bool) -> void:
	if _button_rect().has_point(v):
		close_window()
