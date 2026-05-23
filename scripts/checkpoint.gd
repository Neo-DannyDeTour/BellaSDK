@tool
extends Area3D

@export_group("Trigger Area")
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_trigger_shape()

@export var trigger_offset: Vector3 = Vector3(0.0, 1.0, 0.0):
	set(value):
		trigger_offset = value
		_update_trigger_shape()

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

var is_activated: bool = false

# NEW: We need to remember what this checkpoint looked like before it was activated!
var original_label_text: String
var original_speed: float
var original_line_thickness: float
var original_base_color: Color


func _ready() -> void:
	_update_visuals()
	_update_trigger_shape()

	if not Engine.is_editor_hint():
		# 1. Automatically add to the global group
		add_to_group("checkpoints")

		# 2. Take a snapshot of the default Inspector visuals
		original_label_text = label_text
		original_speed = speed
		original_line_thickness = line_thickness
		original_base_color = base_color

		var trigger_field := get_node_or_null("TriggerField")
		if trigger_field:
			trigger_field.hide()

		body_entered.connect(_on_body_entered)


func _update_trigger_shape() -> void:
	if not is_node_ready():
		return

	var col := get_node_or_null("CollisionShape3D")
	if col:
		if not col.shape is BoxShape3D:
			col.shape = BoxShape3D.new()
		col.shape = col.shape.duplicate()
		col.shape.size = trigger_size
		col.position = trigger_offset

	var mesh_node := get_node_or_null("TriggerField")
	if mesh_node:
		if not mesh_node.mesh is BoxMesh:
			mesh_node.mesh = BoxMesh.new()
		mesh_node.mesh = mesh_node.mesh.duplicate()
		mesh_node.mesh.size = trigger_size
		mesh_node.position = trigger_offset


func _update_visuals() -> void:
	var mesh := get_node_or_null("HologramMesh")
	if not mesh:
		return

	mesh.set_instance_shader_parameter("line_color", line_color)
	mesh.set_instance_shader_parameter("base_color", base_color)
	mesh.set_instance_shader_parameter("speed", speed)
	mesh.set_instance_shader_parameter("line_count", line_count)
	mesh.set_instance_shader_parameter("line_thickness", line_thickness)
	mesh.set_instance_shader_parameter("glow_multiplier", glow_multiplier)

	var label := get_node_or_null("Label3D")
	if label:
		label.text = label_text


func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.name == "Player" or body.is_in_group("Player"):
		if "noclip" in body and body.noclip == true:
			return

		if not is_activated:
			activate_checkpoint()


func activate_checkpoint() -> void:
	# 1. SHUT DOWN EVERY OTHER CHECKPOINT!
	# This calls deactivate_checkpoint() on every node in the group
	get_tree().call_group("checkpoints", "deactivate_checkpoint")

	# 2. TURN THIS ONE ON
	is_activated = true
	SaveSystem.last_checkpoint_pos = global_position
	print("Checkpoint Saved at: ", SaveSystem.last_checkpoint_pos)

	label_text = "Checkpoint Activated"
	speed = -1.0
	line_thickness = 0.8
	base_color = Color(0.0, 0.906, 0.471, 0.102)


# --- NEW: THE RESET FUNCTION ---
func deactivate_checkpoint() -> void:
	# If we are already off, ignore this
	if not is_activated:
		return

	is_activated = false

	# Restore all the original visuals
	label_text = original_label_text
	speed = original_speed
	line_thickness = original_line_thickness
	base_color = original_base_color
