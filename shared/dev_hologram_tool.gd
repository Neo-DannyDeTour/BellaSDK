@tool
## A generic component for managing procedural hologram materials and labels.
##
## This tool script can be attached to any node to control a linked [MeshInstance3D]
## and [Label3D], passing exported properties into shader instance parameters.
class_name DevHologramTool
extends Node3D

@export_group("Node Connections")

## The target [MeshInstance3D] to apply the hologram shader parameters to.
@export var target_mesh: MeshInstance3D:
	set(value):
		target_mesh = value
		_update_visuals()

## The target [Label3D] to update with the hologram text.
@export var target_label: Label3D:
	set(value):
		target_label = value
		_update_visuals()

@export_group("Hologram Settings")

## The text displayed on the linked [Label3D].
@export var label_text: String = "Checkpoint":
	set(value):
		label_text = value
		_update_visuals()

## The color of the scrolling hologram lines.
@export var line_color: Color = Color.GREEN:
	set(value):
		line_color = value
		_update_visuals()

## The base, semi-transparent color of the hologram object.
@export var base_color: Color = Color(0.0, 0.2, 0.8, 0.1):
	set(value):
		base_color = value
		_update_visuals()

## The speed at which the hologram lines animate.
@export var speed: float = 1.0:
	set(value):
		speed = value
		_update_visuals()

## The number of horizontal lines visible in the hologram shader.
@export var line_count: float = 2.0:
	set(value):
		line_count = value
		_update_visuals()

## The thickness of each scanning line in the hologram.
@export_range(0.01, 1.0) var line_thickness: float = 0.1:
	set(value):
		line_thickness = value
		_update_visuals()

## Multiplier for the emission intensity of the hologram lines.
@export var glow_multiplier: float = 2.0:
	set(value):
		glow_multiplier = value
		_update_visuals()


## Validates and applies initial parameters to linked nodes on spawn.
func _ready() -> void:
	_update_visuals()


## Pushes the current exported properties into the linked mesh's shader and label.
func _update_visuals() -> void:
	if is_instance_valid(target_mesh):
		target_mesh.set_instance_shader_parameter("line_color", line_color)
		target_mesh.set_instance_shader_parameter("base_color", base_color)
		target_mesh.set_instance_shader_parameter("speed", speed)
		target_mesh.set_instance_shader_parameter("line_count", line_count)
		target_mesh.set_instance_shader_parameter("line_thickness", line_thickness)
		target_mesh.set_instance_shader_parameter("glow_multiplier", glow_multiplier)

	if is_instance_valid(target_label):
		target_label.text = label_text
