@tool
extends Node3D

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
	var mesh := get_node_or_null("Hologram")

	if not mesh:
		return

	# Push every single inspector value down into the shader
	mesh.set_instance_shader_parameter("line_color", line_color)
	mesh.set_instance_shader_parameter("base_color", base_color)
	mesh.set_instance_shader_parameter("speed", speed)
	mesh.set_instance_shader_parameter("line_count", line_count)
	mesh.set_instance_shader_parameter("line_thickness", line_thickness)
	mesh.set_instance_shader_parameter("glow_multiplier", glow_multiplier)

	var label := get_node_or_null("Label3D")
	if label:
		label.text = label_text
