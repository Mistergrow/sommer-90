extends RetroWindow
## Hochwertiges Dialogfenster: gerahmtes, animiertes 128er-Pixelportraet,
## deterministischer Text-Reveal und Antworten erst nach der gesprochenen Zeile.

const AnimatedPortraitScript := preload("res://scripts/gfx/animated_portrait.gd")
const RevealScript := preload("res://scripts/ui/dialogue_text_reveal.gd")
const DirectorScript := preload("res://scripts/ui/dialogue_text_director.gd")

var _portrait: Control
var _speaker: Label
var _channel: Label
var _status: Label
var _text: RichTextLabel
var _type_fx: RichTextEffect
var _choices: VBoxContainer
var _continue_hint: Label
var _reveal = RevealScript.new()
var _pending_choices: Array = []
var _session_serial := -1
var _manager_ended := false
var _revealing := false
var _director := DirectorScript.new()
var _directed_text := ""


func _init() -> void:
	title = Loc.t("ui.dialogue_window.gesprach", "GESPRÄCH")
	win_size = Vector2(780, 330)
	set_meta("no_center", true)  # Dialoge docken unten an (siehe UIManager)


func _ready() -> void:
	super._ready()
	var screen := get_viewport_rect().size
	position = Vector2((screen.x - win_size.x) / 2.0 + 48.0,
		screen.y - 96.0 - win_size.y - 8.0)

	_session_serial = DialogueManager.current_session_serial()
	DialogueManager.node_changed.connect(_refresh)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)

	var portrait_col := VBoxContainer.new()
	portrait_col.custom_minimum_size = Vector2(142, 0)
	portrait_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	portrait_col.add_theme_constant_override("separation", 5)
	row.add_child(portrait_col)
	_portrait = AnimatedPortraitScript.new()
	portrait_col.add_child(_portrait)
	_channel = Bezel.dim_label("", 12)
	_channel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_col.add_child(_channel)

	var text_panel := PanelContainer.new()
	text_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_panel.add_theme_stylebox_override("panel", _dialogue_panel_style())
	row.add_child(text_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	text_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	margin.add_child(col)

	var speaker_row := HBoxContainer.new()
	speaker_row.add_theme_constant_override("separation", 8)
	_speaker = Bezel.lcd_label("", Palette.LCD_AMBER, 16)
	_speaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speaker_row.add_child(_speaker)
	_status = Label.new()
	_status.text = Loc.t("ui.dialogue_window.spricht", "● SPRICHT")
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Palette.LCD_GREEN)
	speaker_row.add_child(_status)
	col.add_child(speaker_row)
	var divider := HSeparator.new()
	divider.modulate = Color(1, 1, 1, 0.18)
	col.add_child(divider)

	# RichTextLabel statt Label: trägt die Tipp-Einblendung (type_in-Effekt)
	# und liefert-Abhängige Zeilen-Effekte (wave/shake) über BBCode.
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, 92)
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_color_override("default_color", Palette.UI_TEXT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type_fx = load("res://scripts/ui/type_in_effect.gd").new()
	_text.install_effect(_type_fx)
	col.add_child(_text)

	_continue_hint = Bezel.dim_label("", 12)
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_continue_hint)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	col.add_child(_choices)

	_refresh()
	set_process(true)


func _process(delta: float) -> void:
	if not _revealing:
		return
	if _reveal.advance(delta):
		_apply_reveal_state()
	if _reveal.is_complete():
		_finish_reveal()


func _input(event: InputEvent) -> void:
	if not _revealing or not is_visible_in_tree():
		return
	var skip_requested := event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local: Vector2 = event.position - get_global_rect().position
		# Titelleiste bleibt zum Ziehen und Schliessen erreichbar.
		if local.y <= 30.0:
			return
		skip_requested = Rect2(Vector2.ZERO, win_size).has_point(local)
	if skip_requested:
		_skip_reveal()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var node := DialogueManager.current_node()
	if node.is_empty():
		return
	_session_serial = DialogueManager.current_session_serial()
	var speaker := str(node.get("speaker", ""))
	var text := str(node.get("text", ""))
	var speaker_id := str(node.get("speaker_id", ""))
	var channel := str(node.get("channel", "in_person"))
	var emotion := str(node.get("emotion", ""))
	if emotion == "":
		emotion = _emotion_from_text(text)

	_speaker.text = speaker
	_channel.text = Loc.t("ui.dialogue_window.telefon", "☎  TELEFON") \
		if channel == "phone" else Loc.t("ui.dialogue_window.in_person", "VOR ORT")
	_portrait.call("setup", speaker_id, {"emotion": emotion})
	_portrait.call("set_speaking", true)
	_portrait.call("set_viseme", "rest")
	_status.text = _emotion_status(emotion)
	_status.add_theme_color_override("font_color", Palette.LCD_GREEN)

	_text.visible_characters = 0
	_pending_choices = node.get("choices", []).duplicate(true)
	_clear_choices()
	var delivery: Variant = node.get("delivery", {})
	if channel == "phone" and (delivery == null or (delivery is Dictionary and delivery.is_empty()) or str(delivery) == ""):
		delivery = "phone"
	var direction: Variant = node.get("direction", {})
	var context := {
		"emotion": emotion,
		"channel": channel,
		"slot": TimeManager.slot,
		"trust": NPCManager.get_trust(speaker_id) if speaker_id.begins_with("npc_") else 50,
	}
	var compiled: Dictionary = _director.compile(text, speaker_id, direction, context)
	var reveal_delivery: Dictionary = compiled.get("delivery", {}).duplicate(true)
	_apply_delivery_override(reveal_delivery, delivery)
	_directed_text = str(compiled.get("text", text))
	_text.text = str(compiled.get("bbcode", _decorated_text(_directed_text, delivery, emotion)))
	var profile: Dictionary = compiled.get("profile", {})
	if _type_fx != null:
		_type_fx.set("entrance", str(profile.get("entrance", "settle")))
		_type_fx.set("intensity", float(profile.get("intensity", 1.0)))
	_reveal.start(_directed_text, reveal_delivery)
	_revealing = not _reveal.is_complete()
	_continue_hint.text = Loc.t("ui.dialogue_window.klick_enter_text_einblenden", "KLICK / ENTER  ·  TEXT EINBLENDEN") if _revealing else ""
	_apply_reveal_state()
	if not _revealing:
		_finish_reveal()


## Text mit Erzähl-Effekten einkleiden: Tipp-Einblendung immer; aufgeregte
## Zeilen wogen leicht ([wave]), wütende zittern ([shake]), Telefonzeilen
## haben ein feines Leitungsflirren. BBCode im Spieltext wird escaped.
func _decorated_text(text: String, delivery: Variant, emotion: String) -> String:
	var safe := text.replace("[", "[lb]")
	var profile := str(delivery.get("profile", "")) if delivery is Dictionary else str(delivery)
	var inner := safe
	if emotion == "angry":
		inner = "[shake rate=18.0 level=6]%s[/shake]" % inner
	elif profile in ["fast", "excited"]:
		inner = "[wave amp=12.0 freq=4.5]%s[/wave]" % inner
	elif profile == "phone":
		inner = "[shake rate=30.0 level=2]%s[/shake]" % inner
	return "[type_in]%s[/type_in]" % inner


## Alte delivery-Felder ueberschreiben weiterhin das NPC-Profil. Damit bleiben
## bestehende Dialogdaten kompatibel und einzelne Knoten koennen bewusst aus der
## persoenlichen Standardstimme ausbrechen.
func _apply_delivery_override(target: Dictionary, delivery: Variant) -> void:
	if delivery is Dictionary:
		for key: Variant in delivery:
			if key != "timing_events": target[key] = delivery[key]
		return
	var named := str(delivery)
	match named:
		"slow", "calm": target["cps"] = 19.0
		"fast", "excited": target["cps"] = 34.0
		"phone":
			target["cps"] = 24.0
			target["comma_pause"] = 0.12
		"instant": target["instant"] = true


func _apply_reveal_state() -> void:
	_text.visible_characters = _reveal.visible_characters
	if _type_fx != null:
		_type_fx.progress = float(_reveal.visible_characters)
	if _reveal.is_complete():
		_portrait.call("set_viseme", "rest")
		return
	_portrait.call("speak_character", _reveal.text(), _reveal.latest_character_index())


func _skip_reveal() -> void:
	if not _revealing:
		return
	_reveal.skip()
	_apply_reveal_state()
	_finish_reveal()


func _finish_reveal() -> void:
	if not _revealing and not _choices.get_children().is_empty():
		return
	_revealing = false
	_text.visible_characters = -1
	_portrait.call("set_speaking", false)
	_portrait.call("set_viseme", "rest")
	_status.text = Loc.t("ui.dialogue_window.wartet", "● WARTET")
	_status.add_theme_color_override("font_color", Palette.UI_TEXT_DIM)
	_continue_hint.text = Loc.t("ui.dialogue_window.deine_antwort", "DEINE ANTWORT") if not _pending_choices.is_empty() else ""
	_show_choices()


func _emotion_status(emotion: String) -> String:
	var labels := {
		"happy": Loc.t("ui.dialogue_window.emotion_happy", "● GUT GELAUNT"),
		"laughing": Loc.t("ui.dialogue_window.emotion_laughing", "● LACHT"),
		"sad": Loc.t("ui.dialogue_window.emotion_sad", "● NACHDENKLICH"),
		"angry": Loc.t("ui.dialogue_window.emotion_angry", "● VERÄRGERT"),
		"surprised": Loc.t("ui.dialogue_window.emotion_surprised", "● ÜBERRASCHT"),
		"shocked": Loc.t("ui.dialogue_window.emotion_shocked", "● ERSCHROCKEN"),
		"thinking": Loc.t("ui.dialogue_window.emotion_thinking", "● ÜBERLEGT"),
		"tired": Loc.t("ui.dialogue_window.emotion_tired", "● MÜDE"),
		"nervous": Loc.t("ui.dialogue_window.emotion_nervous", "● NERVÖS"),
		"proud": Loc.t("ui.dialogue_window.emotion_proud", "● STOLZ"),
	}
	return str(labels.get(emotion, Loc.t("ui.dialogue_window.spricht", "● SPRICHT")))


func _show_choices() -> void:
	if not _choices.get_children().is_empty():
		return
	for i in _pending_choices.size():
		var button := make_button(Loc.t("ui.dialogue_window.text", ">  ") + str(_pending_choices[i].get("text", "...")),
			DialogueManager.choose.bind(i))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 14)
		_choices.add_child(button)


func _clear_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()


func _on_dialogue_ended() -> void:
	_manager_ended = true
	if _portrait != null:
		_portrait.call("set_speaking", false)
	if is_inside_tree():
		queue_free()


## Das generische RetroWindow schliesst nur den Knoten. Hier wird auch der
## semantische Dialog beendet; die Session-Pruefung schuetzt einen inzwischen
## neu gestarteten Dialog vor einem alten, verzögert geloeschten Fenster.
func _exit_tree() -> void:
	if _manager_ended:
		return
	if DialogueManager.is_active() \
			and DialogueManager.current_session_serial() == _session_serial:
		_manager_ended = true
		DialogueManager.end_dialogue()


## Rueckfall, wenn ein Knoten keine ausdrueckliche Emotion traegt.
##
## Bis zur Lokalisierung suchte diese Funktion nach deutschen Woertern im
## Anzeigetext ("haha", "traurig", "verdammt", "wüt"). Das ist genau die
## Bauart, die eine Uebersetzung LAUTLOS bricht: der Text wandert nach
## Englisch, die Wortsuche greift nicht mehr, und jedes Gesicht steht
## plotzlich auf "neutral" — ohne Fehlermeldung, ohne Test, der anschlaegt.
##
## Geblieben sind nur SATZZEICHEN. Die stehen in jeder Sprache mit
## lateinischer Schrift fuer dieselbe Haltung und ueberleben jede Uebersetzung.
## Fuer alles Feinere ist das Datenfeld `emotion` zustaendig — alle 164
## Dialogknoten tragen es, siehe tests/dialogue_direction_coverage_check.gd.
## Sprechblasen (Barks) sollten es ueber start_bark(..., presentation) ebenso
## mitgeben, statt sich auf diesen Rueckfall zu verlassen.
static func _emotion_from_text(value: String) -> String:
	if "?!" in value or "!?" in value:
		return "surprised"
	if "!" in value:
		return "talking"
	if "?" in value:
		return "thinking"
	return "neutral"


static func _dialogue_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.05, 0.075, 0.98)
	style.border_color = Color(0.28, 0.38, 0.52)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style
