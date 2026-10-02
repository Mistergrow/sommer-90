class_name WbCalcWindow
extends Wb13Window
## Calculator — der Werkbank-Taschenrechner: Anzeige oben, Tastenraster wie
## im Original (CA/CE, Ziffern, Grundrechenarten). Ein Klick links in die
## Anzeige schaltet den erweiterten 3.1-Modus mit Prozent, Wurzel und Speicher.

const KEYS := [
	["CA", "CE", "*", "/"],
	["7", "8", "9", "-"],
	["4", "5", "6", "+"],
	["1", "2", "3", "="],
	["0", ".", "«", "±"],
]
const EXTENDED_KEYS := [
	["MC", "MR", "M+", "M-"],
	["CA", "CE", "SQRT", "%"],
	["7", "8", "9", "/"],
	["4", "5", "6", "*"],
	["1", "2", "3", "-"],
	["0", ".", "=", "+"],
]

var _display := "0"
var _acc := 0.0
var _op := ""
var _fresh := true
var _extended := false
var _memory := 0.0


func _init() -> void:
	title = Loc.t("ui.wb_calc_window.calculator", "Calculator")
	resizable = false


func _key_rect(kx: int, ky: int) -> Rect2:
	var cr := content_rect()
	var kw := (cr.size.x - 20.0) / 4.0
	var kh := (cr.size.y - 46.0) / float(_key_rows().size())
	return Rect2(cr.position.x + 8.0 + kx * kw, cr.position.y + 38.0 + ky * kh, kw - 4.0, kh - 4.0)


func _key_rows() -> Array:
	return EXTENDED_KEYS if _extended else KEYS


func set_extended(enabled: bool) -> void:
	_extended = enabled
	queue_redraw()


func calculator_state() -> Dictionary:
	return {
		"display": _display,
		"accumulator": _acc,
		"operation": _op,
		"extended": _extended,
		"memory": _memory,
	}


func _content_draw(crp: Rect2, sx: float, sy: float) -> void:
	var font := Wb13.font()
	var fs := Wb13.fsize(sy)
	# Anzeige
	var disp := Rect2(crp.position.x + 8.0 * sx, crp.position.y + 8.0 * sy,
		crp.size.x - 16.0 * sx, 22.0 * sy)
	draw_rect(disp, Wb13.white())
	draw_rect(disp, Wb13.black(), false, maxf(1.0, sy))
	draw_string(font, Vector2(disp.position.x + 4.0 * sx, disp.end.y - 6.0 * sy),
		("E" if _extended else "S") + (" M" if _memory != 0.0 else ""),
		HORIZONTAL_ALIGNMENT_LEFT, 40.0 * sx, fs, Wb13.black())
	draw_string(font, Vector2(disp.position.x, disp.end.y - 6.0 * sy), _display,
		HORIZONTAL_ALIGNMENT_RIGHT, disp.size.x - 6.0 * sx, fs, Wb13.black())
	# Tasten
	var rows := _key_rows()
	for ky in rows.size():
		for kx in 4:
			var r := _key_rect(kx, ky)
			var pr := Rect2(r.position.x * sx, r.position.y * sy, r.size.x * sx, r.size.y * sy)
			draw_rect(pr, Wb13.white())
			draw_rect(pr, Wb13.black(), false, maxf(1.0, sy))
			draw_string(font, Vector2(pr.position.x, pr.get_center().y + 6.0 * sy), rows[ky][kx],
				HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, fs, Wb13.black())


func _content_press(v: Vector2, _dbl: bool) -> void:
	if v.y < 34.0 and v.x < 42.0:
		set_extended(not _extended)
		return
	var p := v + content_rect().position  # zurück in Fensterkoordinaten
	var rows := _key_rows()
	for ky in rows.size():
		for kx in 4:
			if _key_rect(kx, ky).has_point(p):
				_press(str(rows[ky][kx]))
				queue_redraw()
				return


func _press(k: String) -> void:
	match k:
		"CA":
			_display = "0"
			_acc = 0.0
			_op = ""
			_fresh = true
		"CE":
			_display = "0"
			_fresh = true
		"MC":
			_memory = 0.0
		"MR":
			_display = _format_value(_memory)
			_fresh = true
		"M+":
			_memory += float(_display)
		"M-":
			_memory -= float(_display)
		"SQRT":
			var value := float(_display)
			_display = _format_value(sqrt(value)) if value >= 0.0 else "ERROR"
			_fresh = true
		"%":
			var value := float(_display)
			_display = _format_value(_acc * value / 100.0 if not _op.is_empty()
				else value / 100.0)
			_fresh = true
		"«":
			_display = _display.substr(0, maxi(1, _display.length() - 1))
			if _display == "-":
				_display = "0"
		"±":
			_display = _display.trim_prefix("-") if _display.begins_with("-") else "-" + _display
		".":
			if not _display.contains("."):
				_display += "."
				_fresh = false
		"+", "-", "*", "/":
			_apply()
			_op = k
			_fresh = true
		"=":
			_apply()
			_op = ""
			_fresh = true
		_:
			if _fresh or _display == "0":
				_display = k
				_fresh = false
			elif _display.length() < 12:
				_display += k


func _apply() -> void:
	var val := float(_display)
	match _op:
		"+": _acc += val
		"-": _acc -= val
		"*": _acc *= val
		"/": _acc = _acc / val if val != 0.0 else 0.0
		_: _acc = val
	_display = _format_value(_acc)


func _format_value(value: float) -> String:
	var result := str(snappedf(value, 0.000001))
	if result.ends_with(".0"):
		result = result.substr(0, result.length() - 2)
	return result
