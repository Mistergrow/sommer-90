@tool
extends HouseholdSprintStage
## Justierbare Editor-Vorschau fuer Rasenpolygon, AGA-Maeher und Grasziele.
## Die eigentliche Spiellogik bleibt im HouseholdSprintModel; diese Szene zahlt
## weder Geld aus noch schreibt sie einen Spielstand.

const Model := preload("res://scripts/minigames/household_sprint_model.gd")

@export_category("Vorschau")
@export_range(0.0, 1.0, 0.01) var preview_mower_x := 0.52:
	set(value):
		preview_mower_x = value
		_refresh_preview()
@export_range(0.0, 1.0, 0.01) var preview_mower_y := 0.58:
	set(value):
		preview_mower_y = value
		_refresh_preview()
@export_range(0, 18, 1) var preview_cut_targets := 5:
	set(value):
		preview_cut_targets = value
		_refresh_preview()
@export var preview_running := true:
	set(value):
		preview_running = value
		_refresh_preview()


func _ready() -> void:
	super()
	_refresh_preview()


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		_pointer = Vector2(preview_mower_x * size.x, preview_mower_y * size.y)
		_tool_down = preview_running
		queue_redraw()


func _refresh_preview() -> void:
	if not is_inside_tree():
		return
	var model := Model.new()
	model.configure("rasen", 9051)
	for index in mini(preview_cut_targets, model.targets.size()):
		model.targets[index]["hits"] = 0
	set_state("rasen", "mower", model.targets, preview_cut_targets,
		model.targets.size(), preview_cut_targets)
	_pointer = Vector2(preview_mower_x * size.x, preview_mower_y * size.y)
	_tool_down = preview_running
	_mower_trail.clear()
	if preview_cut_targets > 1:
		for index in preview_cut_targets:
			_mower_trail.append(Vector2(model.targets[index].get("position", Vector2.ZERO)) * size)
	queue_redraw()
