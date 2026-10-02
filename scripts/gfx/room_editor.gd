extends Control
## Gemeinsamer Raum-Editor: Hauptzimmer nutzt unveraendert den bewaehrten
## DekoEditor/RoomCompositor; die Sammlerwand nutzt CollectionRoomEditorCanvas.

@onready var _front: RoomCompositor = $WorkArea/RoomCompositor
@onready var _reverse: CollectionRoomEditorCanvas = $WorkArea/CollectionRoomEditorCanvas
@onready var _mode_label: Label = $Toolbar/Mode

var _mode := "front"


func _ready() -> void:
	$Toolbar/Front.pressed.connect(_set_mode.bind("front"))
	$Toolbar/Reverse.pressed.connect(_set_mode.bind("reverse"))
	$Toolbar/Monitor1084.pressed.connect(_reverse.select_monitor.bind("commodore_1084s"))
	$Toolbar/Monitor1901.pressed.connect(_reverse.select_monitor.bind("commodore_1901"))
	$Toolbar/MonitorFront1084.pressed.connect(_select_monitor_model.bind("commodore_1084s"))
	$Toolbar/MonitorFront1901.pressed.connect(_select_monitor_model.bind("commodore_1901"))
	$Toolbar/MonitorFront1942.pressed.connect(_select_monitor_model.bind("commodore_1942"))
	$Toolbar/MonitorFront17.pressed.connect(_select_monitor_model.bind("multisync_17"))
	$Toolbar/ComputerA500.pressed.connect(_select_computer_model.bind("amiga_500"))
	$Toolbar/ComputerA600.pressed.connect(_select_computer_model.bind("amiga_600"))
	$Toolbar/ComputerA1200.pressed.connect(_select_computer_model.bind("amiga_1200"))
	$Toolbar/Save.pressed.connect(_save)
	await get_tree().process_frame
	_set_mode("front")


func _set_mode(mode: String) -> void:
	_mode = mode
	var front := mode == "front"
	_front.visible = front
	_reverse.visible = not front
	$Toolbar/Monitor1084.visible = not front
	$Toolbar/Monitor1901.visible = not front
	for node_name: String in ["MonitorLabel", "MonitorFront1084", "MonitorFront1901",
			"MonitorFront1942", "MonitorFront17"]:
		$Toolbar.get_node(node_name).visible = front
	for node_name: String in ["ComputerLabel", "ComputerA500", "ComputerA600",
			"ComputerA1200"]:
		$Toolbar.get_node(node_name).visible = front
	if front:
		_front.set_edit_mode(true, false)
		_sync_front_controls()
	else:
		_front.set_edit_mode(false, false)
		_mode_label.text = Loc.t("misc.room_editor.sammlerwand_objekt_anklicken_ziehen_oder_an", "SAMMLERWAND · Objekt anklicken, ziehen oder an den Ecken skalieren")


func _select_computer_model(model_id: String) -> void:
	var selected := _front.preview_select_device_model(
		"computer_model", model_id, "computer")
	if selected == null:
		return
	var editor: Control = _front.get("_editor")
	if editor != null and is_instance_valid(editor):
		editor.call("select_layer", selected)
	_sync_front_controls()


func _select_monitor_model(model_id: String) -> void:
	var selected := _front.preview_select_device_model(
		"monitor_model", model_id, "monitor")
	if selected == null:
		return
	var editor: Control = _front.get("_editor")
	if editor != null and is_instance_valid(editor):
		editor.call("select_layer", selected)
	_sync_front_controls()


func _sync_front_controls() -> void:
	var active := _front.preview_active_model("computer_model")
	var active_monitor := _front.preview_active_model("monitor_model")
	var labels := {
		"amiga_500": "A500", "amiga_600": "A600", "amiga_1200": "A1200",
	}
	$Toolbar/ComputerA500.button_pressed = active == "amiga_500"
	$Toolbar/ComputerA600.button_pressed = active == "amiga_600"
	$Toolbar/ComputerA1200.button_pressed = active == "amiga_1200"
	var monitor_buttons := {
		"commodore_1084s": $Toolbar/MonitorFront1084,
		"commodore_1901": $Toolbar/MonitorFront1901,
		"commodore_1942": $Toolbar/MonitorFront1942,
		"multisync_17": $Toolbar/MonitorFront17,
	}
	for model_id: String in monitor_buttons:
		(monitor_buttons[model_id] as Button).button_pressed = active_monitor == model_id
	_mode_label.text = Loc.t(
		"misc.room_editor.hauptzimmer_s_s_varianten_getrennt_s_speichert",
		"HAUPTZIMMER · %s + %s · Varianten getrennt · S speichert") % [
			str(labels.get(active, active)),
			active_monitor.replace("commodore_", "").to_upper()]


func _save() -> void:
	if _mode == "front":
		_front.set_edit_mode(false, true)
		_front.set_edit_mode(true, false)
		_sync_front_controls()
		_mode_label.text = Loc.t(
			"misc.room_editor.hauptzimmer_gespeichert_s_s_data_room_anchors",
			"HAUPTZIMMER GESPEICHERT · %s + %s · data/room_anchors.json") % [
				str(_front.preview_active_model("computer_model")).replace("amiga_", "A"),
				str(_front.preview_active_model("monitor_model")).replace(
					"commodore_", "").to_upper()]
	else:
		_mode_label.text = Loc.t("misc.room_editor.sammlerwand_gespeichert_data_collection_room_layout", "SAMMLERWAND GESPEICHERT · data/collection_room_layout.json") \
			if _reverse.save_layout() else "FEHLER · Layout konnte nicht gespeichert werden"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		_set_mode("reverse" if _mode == "front" else "front")
	elif event.keycode == KEY_S:
		_save()
