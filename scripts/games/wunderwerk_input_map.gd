extends RefCounted
## Reine Zuordnung von Tastatur/Joystick-Ersatzkeys zu semantischen Befehlen.
## Der Spielcontroller führt die Befehle aus; dadurch bleiben Eingabebelegung
## und Parkzustand voneinander getrennt und gemeinsam testbar.

const TITLE := 1
const SCENARIO := 2
const PARK := 3
const MANUAL := 4
const FINANCES := 5
const RECORDS := 6
const PAUSE := 7
const RESULTS := 8
const EXIT_CONFIRM := 9


static func key_command(screen: int, event: InputEventKey) -> Dictionary:
	match screen:
		TITLE:
			if event.keycode in [KEY_UP, KEY_W]:
				return _command("menu", {"delta": -1})
			if event.keycode in [KEY_DOWN, KEY_S]:
				return _command("menu", {"delta": 1})
			if _accept(event):
				return _command("accept_title")
			if event.keycode == KEY_ESCAPE:
				return _command("exit_confirm")
		SCENARIO:
			if event.keycode in [KEY_UP, KEY_LEFT]:
				return _command("scenario", {"delta": -1})
			if event.keycode in [KEY_DOWN, KEY_RIGHT]:
				return _command("scenario", {"delta": 1})
			if _accept(event):
				return _command("start_scenario")
			if event.keycode == KEY_ESCAPE:
				return _command("title")
		PARK:
			return _park_command(event)
		PAUSE:
			if _accept(event):
				return _command("resume")
			if event.keycode == KEY_F5:
				return _command("save")
			if event.keycode == KEY_ESCAPE:
				return _command("save_title")
		MANUAL:
			if event.keycode in [KEY_LEFT, KEY_UP]:
				return _command("manual", {"delta": -1})
			if event.keycode in [KEY_RIGHT, KEY_DOWN, KEY_ENTER, KEY_SPACE]:
				return _command("manual", {"delta": 1})
			if event.keycode == KEY_ESCAPE:
				return _command("return")
		FINANCES, RECORDS:
			if event.keycode == KEY_ESCAPE or _accept(event):
				return _command("return")
		RESULTS:
			if event.keycode == KEY_F5:
				return _command("save")
			if _accept(event) or event.keycode == KEY_ESCAPE:
				return _command("title")
		EXIT_CONFIRM:
			if _accept(event):
				return _command("exit")
			if event.keycode == KEY_ESCAPE:
				return _command("title")
	return {}


static func _park_command(event: InputEventKey) -> Dictionary:
	if event.shift_pressed:
		match event.keycode:
			KEY_LEFT, KEY_A: return _command("pan", {"delta": Vector2(24, 0)})
			KEY_RIGHT, KEY_D: return _command("pan", {"delta": Vector2(-24, 0)})
			KEY_UP, KEY_W: return _command("pan", {"delta": Vector2(0, 16)})
			KEY_DOWN, KEY_S: return _command("pan", {"delta": Vector2(0, -16)})
	match event.keycode:
		KEY_UP, KEY_W: return _command("cursor", {"delta": Vector2i(0, -1)})
		KEY_DOWN, KEY_S: return _command("cursor", {"delta": Vector2i(0, 1)})
		KEY_LEFT, KEY_A: return _command("cursor", {"delta": Vector2i(-1, 0)})
		KEY_RIGHT, KEY_D: return _command("cursor", {"delta": Vector2i(1, 0)})
		KEY_Q: return _command("tool", {"delta": -1})
		KEY_E, KEY_TAB: return _command("tool", {"delta": 1})
		KEY_HOME, KEY_PAGEUP: return _command("tool_page", {"delta": -1})
		KEY_PAGEDOWN: return _command("tool_page", {"delta": 1})
		KEY_B: return _command("toolbar")
		KEY_ENTER, KEY_KP_ENTER: return _command("use")
		KEY_SPACE: return _command("speed")
		KEY_F1: return _command("manual_screen")
		KEY_F2: return _command("finances")
		KEY_F5: return _command("save")
		KEY_ESCAPE: return _command("cancel")
		KEY_O: return _command("toggle_object")
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			return _command("price", {"delta": 1})
		KEY_MINUS, KEY_KP_SUBTRACT:
			return _command("price", {"delta": -1})
	return {}


static func _accept(event: InputEventKey) -> bool:
	return event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]


static func _command(name: String, data: Dictionary = {}) -> Dictionary:
	var result := data.duplicate()
	result["name"] = name
	return result
