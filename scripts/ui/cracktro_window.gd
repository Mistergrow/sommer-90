extends RetroWindow
## BYTEWERK-Cracktro: rendert die beim Release gespeicherte Komposition statt
## bei jedem Start eine zufaellige Gruppe zu erfinden. Alte Spielstaende ohne
## release_data behalten einen deterministischen Legacy-Scroller.

signal play_requested(release_data: Dictionary)

const Renderer := preload("res://scripts/ui/cracktro_renderer.gd")
const LEGACY_SCROLL := "   +++ %s PRESENTS +++ %s +++ BYTEWERK VERIFIED +++ GREETINGS FLY OUT TO ALLE SCHULHOF-SWAPPER UND MAILBOX-NACHTEULEN +++ SUPPORT THE CREATORS +++ SWAP FAIR +++   "
const PALETTES := {
	"amber_night": [Color("#080b18"), Color("#27305c"), Color("#f08a24"), Color("#ffe19a"), Color("#52d6d8")],
	"violet_cyan": [Color("#09051a"), Color("#52207a"), Color("#16c9c1"), Color("#d8fff7"), Color("#ee65c5")],
	"steel_red": [Color("#0a0d12"), Color("#394554"), Color("#c7423d"), Color("#f1d1b5"), Color("#f08a24")],
	"green_terminal": [Color("#06110b"), Color("#174a2a"), Color("#49c96b"), Color("#d8ffb5"), Color("#f0c94d")],
	"sunset_disk": [Color("#160a1d"), Color("#68305a"), Color("#e76d3b"), Color("#ffd37a"), Color("#42d9d0")],
}

var game_title := "???"
var release_data: Dictionary = {}
var on_continue: Callable = Callable()

var _canvas: Control
var _time := 0.0
var _group := "ANON-0000"
var _player_handle := "ANON-0000"
var _scroller := ""
var _credits := ""
var _palette_id := "amber_night"
var _logo_style := "shadow"
var _effects: Array = []
var _finished := false


func _init() -> void:
	title = Loc.t("ui.cracktro_window.szene_release", "SZENE-RELEASE")
	win_size = Vector2(740, 530)


func _ready() -> void:
	super._ready()
	_resolve_release()
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, 454)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.clip_contents = true
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_cracktro)
	content.add_child(_canvas)
	var start_button := make_button(Loc.t("ui.cracktro_window.spiel_starten_return", "[ SPIEL STARTEN · RETURN ]"), _finish)
	start_button.custom_minimum_size = Vector2(0, 32)
	start_button.add_theme_font_override("font", Renderer.font())
	start_button.add_theme_font_size_override("font_size", 16)
	start_button.tooltip_text = Loc.t("ui.cracktro_window.intro_beenden_spiel_starten_enter", "Intro beenden und das Spiel starten (Enter)")
	content.add_child(start_button)
	start_button.grab_focus.call_deferred()


func _process(delta: float) -> void:
	if not bool(SettingsManager.value("reduced_motion")):
		_time += minf(delta, 0.05)
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	AudioManager.key_enter()
	play_requested.emit(release_data.duplicate(true))
	if on_continue.is_valid():
		on_continue.call()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_finish()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)


func _resolve_release() -> void:
	var data := release_data
	if data.is_empty():
		_group = _legacy_group()
		_player_handle = _group
		_effects = ["copperbars", "starfield", "sine_scroller"]
		_scroller = LEGACY_SCROLL % [_group, game_title.to_upper()]
		return

	_palette_id = str(data.get("palette", data.get("palette_id", "amber_night")))
	if not PALETTES.has(_palette_id):
		_palette_id = "amber_night"
	_logo_style = str(data.get("logo", data.get("logo_style", "shadow")))
	_effects = _effect_ids(data.get("effects", []))
	if _effects.is_empty():
		_effects = ["copperbars", "sine_scroller"]

	# Gruppenname ist nur erlaubt, wenn er als gespeicherte Release-Entscheidung
	# kommt. Ohne Gruppe praesentiert immer das validierte Szene-Handle selbst.
	_player_handle = _release_handle(data)
	_group = str(data.get("presenting", data.get("group_name", data.get("group", "")))).strip_edges()
	if _group == "":
		_group = _player_handle
	if _group == "":
		_group = _legacy_group()
	if _player_handle == "":
		_player_handle = _group

	_credits = _credit_line(data)
	_scroller = str(data.get("scroller_text", data.get("scroller", ""))).strip_edges()
	if _scroller == "":
		_scroller = LEGACY_SCROLL % [_group, game_title.to_upper()]
	_scroller = _scroller.replace("{TITLE}", game_title.to_upper())
	_scroller = _scroller.replace("{PRESENTING}", _group)
	_scroller = _scroller.replace("{HANDLE}", _player_handle)
	_scroller = _scroller.replace("{YEAR}", str(data.get("year", "")))
	if _credits != "" and _credits.to_upper() not in _scroller.to_upper():
		_scroller += "   +++ " + _credits + " +++   "


func _legacy_group() -> String:
	var scene := get_node_or_null("/root/BBSScene")
	if scene != null and scene.has_method("group_names"):
		var names: Array = scene.call("group_names")
		if not names.is_empty():
			return str(names[(hash(game_title) & 0x7fffffff) % names.size()])
	return "ANON-%04X" % (hash(game_title) & 0xffff)


func _effect_ids(raw: Variant) -> Array:
	var out: Array = []
	if raw is not Array:
		return out
	for value in raw:
		var id := ""
		if value is Dictionary:
			id = str(value.get("id", value.get("effect", "")))
		else:
			id = str(value)
		id = _canonical_effect_id(id.strip_edges().to_lower())
		if id != "" and id not in out and out.size() < 3:
			out.append(id)
	return out


## Alte Releases nutzten mehrere Schreibweisen fuer dieselben visuellen
## Effekte. Intern bleibt nur noch eine ID uebrig, damit Vorschau, Intro und
## Tests exakt dieselbe Komposition sehen.
func _canonical_effect_id(id: String) -> String:
	match id:
		"copper", "rasterbars": return "copperbars"
		"stars": return "starfield"
		"grid", "vector": return "vectorgrid"
		"bob", "sprites": return "bobs"
		"sine", "sinescroll", "sinus_scroller": return "sine_scroller"
		"straight": return "straight_scroller"
		_: return id


func _release_handle(data: Dictionary) -> String:
	for key in ["player_handle", "handle_snapshot", "scene_handle", "handle", "author_handle"]:
		var handle := _safe_handle(str(data.get(key, "")))
		if handle != "":
			return handle
	var actor_id := str(data.get("actor_id", ""))
	if actor_id != "":
		var manager := get_node_or_null("/root/SceneReleaseManager")
		if manager != null and manager.has_method("handle_for_actor"):
			return _safe_handle(str(manager.call("handle_for_actor", actor_id)))
		var scene := get_node_or_null("/root/BBSScene")
		if scene != null and scene.has_method("handle_for_actor"):
			return _safe_handle(str(scene.call("handle_for_actor", actor_id)))
	return ""


## Sichtbare Credits lesen ausschliesslich handle_snapshot/handle oder eine
## interne actor_id. Ein Feld namens name/display_name wird bewusst ignoriert.
func _credit_line(data: Dictionary) -> String:
	var raw: Variant = data.get("credits", data.get("contributors", []))
	if raw is not Array:
		return ""
	var entries: Array[String] = []
	for value in raw:
		var handle := ""
		var role := ""
		if value is Dictionary:
			handle = _safe_handle(str(value.get("handle_snapshot", "")))
			role = str(value.get("role", "")).strip_edges().to_upper()
			if handle == "" and str(value.get("actor_id", "")) != "":
				var actor_id := str(value.get("actor_id", ""))
				var manager := get_node_or_null("/root/SceneReleaseManager")
				if manager != null and manager.has_method("handle_for_actor"):
					handle = _safe_handle(str(manager.call("handle_for_actor", actor_id)))
				else:
					var scene := get_node_or_null("/root/BBSScene")
					if scene != null and scene.has_method("handle_for_actor"):
						handle = _safe_handle(str(scene.call("handle_for_actor", actor_id)))
		# Lose Strings werden absichtlich ignoriert: Nur ein expliziter,
		# unveraenderlicher handle_snapshot oder eine interne actor_id ist Credit.
		if handle == "":
			continue
		var credit := "%s %s" % [handle, role] if role != "" else handle
		if credit not in entries:
			entries.append(credit)
	return " · ".join(entries)


func _safe_handle(value: String) -> String:
	var candidate := value.strip_edges().to_upper()
	if candidate.length() < 2 or candidate.length() > 20:
		return ""
	for i in candidate.length():
		var code := candidate.unicode_at(i)
		var allowed := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
			or candidate[i] in ["-", "_", "."]
		if not allowed:
			return ""
	return candidate


func _palette() -> Array:
	return PALETTES.get(_palette_id, PALETTES["amber_night"])


func _draw_cracktro() -> void:
	Renderer.draw_intro(_canvas, _time, {
		"palette": _palette(),
		"effects": _effects,
		"group": _group,
		"title": game_title,
		"credits": _credits,
		"scroller": _scroller,
		"logo_style": _logo_style,
		"serial": str(release_data.get("serial", "BYTEWERK")),
		"year": int(release_data.get("year", TimeManager.year)),
	})
