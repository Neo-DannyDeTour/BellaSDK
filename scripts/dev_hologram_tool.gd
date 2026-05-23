@tool
extends Node3D
class_name DevHologramTool  # This makes it a globally recognized component in your project!

@export_group("Node Connections")
# By exporting the Nodes, this script no longer cares what they are named in the scene tree!
@export var target_mesh: MeshInstance3D:
	set(value):
		target_mesh = value
		_update_visuals()

@export var target_label: Label3D:
	set(value):
		target_label = value
		_update_visuals()

@export_group("Hologram Settings")
@export var label_text: String = "Checkpoint":
	set(value):
		label_text = value
		_update_visuals()

@export var line_color: Color = Color.GREEN:
	set(value):
		line_color = value
		_update_visuals()

@export var base_color: Color = Color(0.0, 0.2, 0.8, 0.1):
	set(value):
		base_color = value
		_update_visuals()

@export var speed: float = 1.0:
	set(value):
		speed = value
		_update_visuals()

@export var line_count: float = 2.0:
	set(value):
		line_count = value
		_update_visuals()

@export_range(0.01, 1.0) var line_thickness: float = 0.1:
	set(value):
		line_thickness = value
		_update_visuals()

@export var glow_multiplier: float = 2.0:
	set(value):
		glow_multiplier = value
		_update_visuals()


func _ready() -> void:
	_update_visuals()


func _update_visuals() -> void:
	# 1. Update the Mesh (if one is connected)
	if target_mesh:
		target_mesh.set_instance_shader_parameter("line_color", line_color)
		target_mesh.set_instance_shader_parameter("base_color", base_color)
		target_mesh.set_instance_shader_parameter("speed", speed)
		target_mesh.set_instance_shader_parameter("line_count", line_count)
		target_mesh.set_instance_shader_parameter("line_thickness", line_thickness)
		target_mesh.set_instance_shader_parameter("glow_multiplier", glow_multiplier)

	# 2. Update the Label (if one is connected)
	if target_label:
		target_label.text = label_text
