class_name ProtectionFullscreenScreen
extends Control
## Bildschirfuellender Monitor-Host fuer den Kopierschutz selbstbootender Spiele.
## Der eigentliche Abfragevertrag bleibt im ProtectionWindow; dieser Host sorgt
## dafuer, dass Boot, Beilagenritual und Vollspiel wie EIN Amiga-Programm wirken.

const ProtectionWindowScript := preload("res://scripts/ui/protection_window.gd")
const CODE_RED_ART := preload("res://assets/ui/games/code_red/title_background_v01.png")

var game_title := "???"
var software_id := ""
var protection := "handbuch"
var has_beilagen := true
var missing_beilagen: Array = []
var on_result: Callable = Callable()
var was_at_computer := false

var _prompt: Control
var _resolved := false
var _handoff := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	# Unter der globalen Fensterebene bleiben: Nur so kann die physische
	# Handbuch-/Bahnkartenansicht ueber dem Vollbild aufgeschlagen werden.
	z_index = 40
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_backdrop()
	_build_prompt()
	resized.connect(_center_prompt)
	_center_prompt.call_deferred()
	grab_focus.call_deferred()


func _build_backdrop() -> void:
	var background := ColorRect.new()
	background.color = Color8(2, 5, 10)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	if software_id == "code_red_protocol":
		var art := TextureRect.new()
		art.texture = CODE_RED_ART
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(0.38, 0.16, 0.16, 0.34)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0.008, 0.012, 0.02, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var header := Label.new()
	header.text = Loc.t("ui.protection_fullscreen_screen.df0_systemstart_originalpruefung", "DF0:  SYSTEMSTART  ·  ORIGINALPRUEFUNG")
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color8(239, 166, 61))
	header.position = Vector2(18, 14)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	var footer := Label.new()
	footer.text = Loc.t("ui.protection_fullscreen_screen.handbuch_beilagen_bereithalten", "HANDBUCH UND BEILAGEN BEREITHALTEN")
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color8(112, 170, 168))
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 18
	footer.offset_top = -32
	footer.offset_bottom = -12
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)


func _build_prompt() -> void:
	_prompt = ProtectionWindowScript.new()
	_prompt.game_title = game_title
	_prompt.software_id = software_id
	_prompt.protection = protection
	_prompt.has_beilagen = has_beilagen
	_prompt.missing_beilagen = missing_beilagen.duplicate()
	_prompt.on_result = _on_protection_result
	_prompt.tree_exited.connect(_on_prompt_closed)
	add_child(_prompt)


func _center_prompt() -> void:
	if not is_instance_valid(_prompt):
		return
	var target_size: Vector2 = _prompt.get("win_size")
	_prompt.position = ((size - target_size) * 0.5).floor()


func _on_protection_result(ok: bool) -> void:
	_resolved = true
	if on_result.is_valid():
		on_result.call(ok)
	if ok:
		# Der Launcher legt das echte Spiel synchron in denselben Monitor-Host.
		# Nur dann darf _exit_tree den Sitzplatz nicht wieder verlassen.
		var host: Control = GameManager.location_host
		var game_name := "app_game_%s" % software_id
		_handoff = host != null and host.get_node_or_null(NodePath(game_name)) != null
	if not _handoff:
		queue_free()


func _on_prompt_closed() -> void:
	if not _resolved:
		queue_free()


func _exit_tree() -> void:
	if not _handoff:
		UIManager._set_computer_ui(was_at_computer)
