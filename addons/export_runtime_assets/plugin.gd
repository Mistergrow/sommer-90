@tool
extends EditorPlugin

const ExportRuntimeAssets := preload("res://addons/export_runtime_assets/export_runtime_assets.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = ExportRuntimeAssets.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
