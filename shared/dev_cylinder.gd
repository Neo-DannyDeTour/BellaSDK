@tool
## A procedural cylinder hologram for developer/debug visualization.
##
## This script synchronizes editor properties to shader instance parameters and a 3D label,
## allowing designers to visually mark areas in a level during development.
class_name DevCylinder
extends Node3D

@export_group("Hologram Settings")

## The text displayed on the hologram's 3D label.
@export var label_text: String = "Checkpoint":
	set(value):
		label_text = value
		_update_visuals()

## The color of the scrolling hologram lines.
@export var line_color: Color = Color.GREEN:
	set(value):
		line_color = value
		_update_visuals()

## The base, semi-transparent color of the hologram cylinder.
@export var base_color: Color = Color(0.0, 0.2, 0.8, 0.1):
	set(value):
		base_color = value
		_update_visuals()

## The speed at which the hologram lines animate vertically.
@export var speed: float = 1.0:
	set(value):
		speed = value
		_update_visuals()

## The number of horizontal lines visible in the hologram shader.
@export var line_count: float = 2.0:
	set(value):
		line_count = value
		_update_visuals()

## The vertical thickness of each scanning line in the hologram.
@export_range(0.01, 1.0) var line_thickness: float = 0.1:
	set(value):
		line_thickness = value
		_update_visuals()

## Multiplier for the emission intensity of the hologram lines.
@export var glow_multiplier: float = 2.0:
	set(value):
		glow_multiplier = value
		_update_visuals()

## Reference to the hologram mesh instance, initialized when added to tree.
@onready var hologram_mesh: MeshInstance3D = $Hologram
## Reference to the label instance, initialized when added to tree.
@onready var hologram_label: Label3D = $Label3D


## Connects properties on ready.
func _ready() -> void:
	_update_visuals()


## Updates the mesh shader instance parameters and 3D label string based on export properties.
func _update_visuals() -> void:
	# Handle tool script initialization before ready
	var mesh: MeshInstance3D = (
		hologram_mesh if is_node_ready() else get_node_or_null("Hologram") as MeshInstance3D
	)

	if is_instance_valid(mesh):
		mesh.set_instance_shader_parameter("line_color", line_color)
		mesh.set_instance_shader_parameter("base_color", base_color)
		mesh.set_instance_shader_parameter("speed", speed)
		mesh.set_instance_shader_parameter("line_count", line_count)
		mesh.set_instance_shader_parameter("line_thickness", line_thickness)
		mesh.set_instance_shader_parameter("glow_multiplier", glow_multiplier)

	var label: Label3D = (
		hologram_label if is_node_ready() else get_node_or_null("Label3D") as Label3D
	)
	if is_instance_valid(label):
		label.text = label_text
