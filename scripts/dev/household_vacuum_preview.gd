@tool
extends HouseholdSprintStage
## Editor-Vorschau fuer das vollstaendige AGA-Staubsauger-Asset. Die in
## data/household_vacuum_rig.tres gespeicherten Anker koennen im Inspector
## aufgeklappt und direkt gegen die farbigen Markierungen justiert werden.

const Model := preload("res://scripts/minigames/household_sprint_model.gd")

@export_category("Vorschau")
@export_range(0.18, 0.94, 0.01) var preview_nozzle_x := 0.68:
	set(value):
		preview_nozzle_x = value
		_refresh_preview()
@export_range(0.54, 0.93, 0.01) var preview_nozzle_y := 0.78:
	set(value):
		preview_nozzle_y = value
		_refresh_preview()
@export var preview_running := true:
	set(value):
		preview_running = value
		_refresh_preview()


func _ready() -> void:
	super()
	show_vacuum_anchors = true
	_refresh_preview()


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		_pointer = Vector2(preview_nozzle_x * size.x, preview_nozzle_y * size.y)
		_tool_down = preview_running
		queue_redraw()


func _refresh_preview() -> void:
	if not is_inside_tree():
		return
	var model := Model.new()
	model.configure("staubsaugen", 9052)
	set_state("staubsaugen", "vacuum", model.targets, 0,
		model.targets.size(), 0)
	_pointer = Vector2(preview_nozzle_x * size.x, preview_nozzle_y * size.y)
	_tool_down = preview_running
	show_vacuum_anchors = true
	queue_redraw()
