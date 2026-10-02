@tool
extends Control
## Orts-Layout-Editor als EIGENE Szene (analog scenes/previews/RoomPreview.tscn).
##
## Benutzung: die passende scenes/previews/<Ort>Preview.tscn im Editor öffnen und mit
## F6 ("Aktuelle Szene ausführen") starten. Der Ort wird mit seinem Artwork
## geladen, alle Hotspots sind sofort verschiebbar/skalierbar. F8 / Strg+S
## speichert nach data/location_hotspots.json — dieselbe Datei, die der Ort im
## Spiel beim Betreten lädt. Kein Durchspielen, kein In-Game-F8 nötig.
##
## Die eingebaute Werkzeugleiste wechselt zwischen Hotspots, Architekturflächen
## und eingebetteten Tiefenobjekten. F8 speichert jeweils nur den aktiven Pass.
## Pro Ort eine Szene, die nur `location_id` und bei Bedarf Datum/Slot setzt.

const SURFACE_EDITOR_SCENE := preload("res://scenes/editors/SurfaceEditor.tscn")
const OBJECT_EDITOR_SCENE := preload("res://scenes/editors/ObjectEditor.tscn")

@export var location_id: String = "flea_market"
## Jahr für die Artwork-Variante (manche Orte haben Jahresvarianten).
@export var year: int = 1992
## Datum für NPC-Zeitpläne in Preview-Szenen.
@export var month: int = 7
@export var day: int = 6
## Zeit-Slot des Fuenf-Fenster-Tags (0=Morgen, 1=Mittag, 2=Nachmittag,
## 3=Abend, 4=Nacht). Wichtig z. B. fuer den Schulhof, der nachmittags eine
## andere Variante mit anderen Hotspots hat.
@export var slot: int = 0

var _location: LocationBase
var _hotspot_editor: HotspotEditor
var _authoring_overlay: Control
var _authoring_toolbar: PanelContainer
var _mode_label: Label


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	TimeManager.year = year
	TimeManager.month = month
	TimeManager.day = day
	TimeManager.slot = slot
	# Preview-Szenen werden aus dem Titelzustand gestartet. Dort ignoriert der
	# Jahreswechsel absichtlich Live-Definitionen; für Zukunftsorte wie LAN-
	# Keller und Internetcafé laden wir sie deshalb nach dem gesetzten Jahr neu.
	GameManager.LOCATION_DEFS = TownManager.live_defs()
	var def: Dictionary = GameManager.LOCATION_DEFS.get(location_id, {})
	if def.is_empty() or not def.has("script"):
		push_error("LocationPreview: unbekannter Ort '%s'. Bekannt: %s"
			% [location_id, ", ".join(GameManager.LOCATION_DEFS.keys())])
		return
	# Der Preview muss denselben Ortskontext wie GameManager._enter_location
	# setzen. Sonst sehen zeitgeplante NPCs (insbesondere der Händler am
	# Samstag) eine leere current_location_id und werden fälschlich ausgeblendet.
	GameManager.current_location_id = location_id
	_location = def["script"].new()
	_location.location_id = location_id
	add_child(_location)
	# Hotspots aufbauen + Größe übernehmen lassen, dann Editor aufsetzen.
	await get_tree().process_frame
	await get_tree().process_frame
	# Der Layout-Editor zeigt den neutralen Spawn exakt und darf beim Ziehen nicht
	# durch Maus-Parallaxe driften. Im Spiel folgt der gespeicherte Punkt danach
	# wieder ganz normal der gemeinsamen 2,5D-Projektion.
	var depth_stage := _location.depth_stage_25d()
	if depth_stage != null and depth_stage.has_method("set_test_look"):
		depth_stage.call("set_test_look", Vector2.ZERO)
	_hotspot_editor = HotspotEditor.new()
	_hotspot_editor.location = _location
	add_child(_hotspot_editor)
	_build_authoring_toolbar()


func _build_authoring_toolbar() -> void:
	_authoring_toolbar = PanelContainer.new()
	_authoring_toolbar.name = "DepthAuthoringToolbar"
	_authoring_toolbar.set_meta("preview_authoring_ui", true)
	_authoring_toolbar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_authoring_toolbar.position = Vector2(size.x - 704.0, 12.0)
	_authoring_toolbar.size = Vector2(692.0, 46.0)
	_authoring_toolbar.z_index = 3000
	_authoring_toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.025, 0.038, 0.94)
	panel_style.border_color = Color(0.22, 0.68, 0.92, 0.88)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	panel_style.set_content_margin_all(5.0)
	_authoring_toolbar.add_theme_stylebox_override("panel", panel_style)
	add_child(_authoring_toolbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	_authoring_toolbar.add_child(row)
	_mode_label = Label.new()
	_mode_label.text = Loc.t("ui.location_preview.mode_hotspots", "2,5D · HOTSPOTS")
	_mode_label.custom_minimum_size.x = 146.0
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_label.add_theme_font_override("font", load("res://assets/fonts/VT323_UI.ttf"))
	_mode_label.add_theme_font_size_override("font_size", 18)
	_mode_label.add_theme_color_override("font_color", Color(0.58, 0.88, 1.0))
	row.add_child(_mode_label)
	row.add_child(_authoring_button(
		Loc.t("ui.location_preview.f1_hotspots", "F1 HOTSPOTS"),
		_show_authoring_mode.bind("hotspots"),
		Loc.t("ui.location_preview.hotspots_tooltip",
			"Klickzonen und sichtbare Akteure ausrichten")))
	row.add_child(_authoring_button(
		Loc.t("ui.location_preview.f2_flachen", "F2 FLÄCHEN"),
		_show_authoring_mode.bind("surfaces"),
		Loc.t("ui.location_preview.flachen_tooltip",
			"Boden, Wände, Decke und Fenster semantisch markieren")))
	row.add_child(_authoring_button(
		Loc.t("ui.location_preview.f3_objekte", "F3 OBJEKTE"),
		_show_authoring_mode.bind("objects"),
		Loc.t("ui.location_preview.objekte_tooltip",
			"Eingebackene Tiefenobjekte, Lichtfelder und Schatten markieren")))
	row.add_child(_authoring_button(
		Loc.t("ui.location_preview.f4_spielbild", "F4 SPIELBILD"),
		_show_authoring_mode.bind("view"),
		Loc.t("ui.location_preview.spielbild_tooltip",
			"Saubere Szene ohne Editorrahmen prüfen")))


func _authoring_button(text: String, callback: Callable, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", load("res://assets/fonts/VT323_UI.ttf"))
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	return button


func _show_authoring_mode(mode: String) -> void:
	if _authoring_overlay != null and is_instance_valid(_authoring_overlay):
		_authoring_overlay.queue_free()
		_authoring_overlay = null
	if _hotspot_editor != null and is_instance_valid(_hotspot_editor):
		_hotspot_editor.visible = mode == "hotspots"
	if mode == "hotspots":
		_mode_label.text = Loc.t("ui.location_preview.mode_hotspots", "2,5D · HOTSPOTS")
		return
	if mode == "view":
		_mode_label.text = Loc.t("ui.location_preview.mode_spielbild", "2,5D · SPIELBILD")
		return
	var scene := SURFACE_EDITOR_SCENE if mode == "surfaces" else OBJECT_EDITOR_SCENE
	_authoring_overlay = scene.instantiate() as Control
	_authoring_overlay.name = "Embedded%sEditor" % mode.capitalize()
	_authoring_overlay.set_meta("preview_authoring_overlay", true)
	add_child(_authoring_overlay)
	_authoring_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(_authoring_toolbar, get_child_count() - 1)
	var location_key := _location.location_key()
	_authoring_overlay.call_deferred("select_location_key", location_key)
	_mode_label.text = Loc.t("ui.location_preview.mode_flachen", "2,5D · FLÄCHEN") \
		if mode == "surfaces" else Loc.t(
			"ui.location_preview.mode_objekte", "2,5D · OBJEKTE")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			_show_authoring_mode("hotspots")
			get_viewport().set_input_as_handled()
		KEY_F2:
			_show_authoring_mode("surfaces")
			get_viewport().set_input_as_handled()
		KEY_F3:
			_show_authoring_mode("objects")
			get_viewport().set_input_as_handled()
		KEY_F4:
			_show_authoring_mode("view")
			get_viewport().set_input_as_handled()
