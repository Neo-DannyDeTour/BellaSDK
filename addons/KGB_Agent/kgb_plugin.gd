@tool
extends EditorPlugin

var dock: Node


func _enter_tree() -> void:
	dock = preload("res://addons/KGB_Agent/kgb_dock.gd").new()
	dock.name = "KGB Agent"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
	remove_control_from_docks(dock)
	dock.free()
