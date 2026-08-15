@tool
## A trigger volume that saves the player's progress and updates a global save state.
##
## Visually represents its state through a hologram shader. When the player enters the area,
## this checkpoint activates, saves the position, and deactivates all other checkpoints.
class_name Checkpoint
extends Area3D

@export_group("Trigger Area")
## The 3D size of the collision box and editor debug mesh for the trigger.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_trigger_shape()

## The offset of the trigger shape relative to the node's origin.
@export var trigger_offset: Vector3 = Vector3(0.0, 1.0, 0.0):
	set(value):
		trigger_offset = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_trigger_shape()

@export_group("Hologram Settings")
## The text displayed on the floating [Label3D] above the checkpoint.
@export var label_text: String = "Checkpoint":
	set(value):
		label_text = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## The emission color of the scrolling hologram lines.
@export var line_color: Color = Color.GREEN:
	set(value):
		line_color = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## The translucent base color of the hologram cylinder.
@export var base_color: Color = Color(0.0, 0.2, 0.8, 0.1):
	set(value):
		base_color = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## The speed at which the hologram lines scroll up or down.
@export var speed: float = 1.0:
	set(value):
		speed = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## The number of horizontal lines rendered by the hologram shader.
@export var line_count: float = 2.0:
	set(value):
		line_count = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## The thickness of the scrolling hologram lines.
@export_range(0.01, 1.0) var line_thickness: float = 0.1:
	set(value):
		line_thickness = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## A multiplier to boost the glow intensity of the hologram lines.
@export var glow_multiplier: float = 2.0:
	set(value):
		glow_multiplier = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

@export_group("Audio Settings")
## The [AudioStream] played when the checkpoint is first activated by the player.
@export var activation_sound: AudioStream

## Reference to the audio player used for the activation sound.
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

## Indicates whether this checkpoint is currently the active spawn point.
var is_activated: bool = false
## The original label text, cached to restore state if deactivated.
var original_label_text: String
## The original hologram speed, cached to restore state if deactivated.
var original_speed: float
## The original hologram line thickness, cached to restore state if deactivated.
var original_line_thickness: float
## The original hologram base color, cached to restore state if deactivated.
var original_base_color: Color


## Caches initial visual states, updates shapes, and connects collision signals during gameplay.
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

		var trigger_field: MeshInstance3D = get_node_or_null("TriggerField") as MeshInstance3D
		if trigger_field:
			trigger_field.hide()

		body_entered.connect(_on_body_entered)


## Rebuilds the collision and debug mesh boxes based on the exported dimensions.
func _update_trigger_shape() -> void:
	if not is_node_ready():
		return

	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		if not col.shape is BoxShape3D:
			col.shape = BoxShape3D.new()
		col.shape = col.shape.duplicate()
		col.shape.size = trigger_size
		col.position = trigger_offset

	var mesh_node: MeshInstance3D = get_node_or_null("TriggerField") as MeshInstance3D
	if mesh_node:
		if not mesh_node.mesh is BoxMesh:
			mesh_node.mesh = BoxMesh.new()
		mesh_node.mesh = mesh_node.mesh.duplicate()
		mesh_node.mesh.size = trigger_size
		mesh_node.position = trigger_offset


## Passes the current color and line configuration to the shader material instance.
func _update_visuals() -> void:
	var mesh: MeshInstance3D = get_node_or_null("HologramMesh") as MeshInstance3D
	if not mesh:
		return

	mesh.set_instance_shader_parameter("line_color", line_color)
	mesh.set_instance_shader_parameter("base_color", base_color)
	mesh.set_instance_shader_parameter("speed", speed)
	mesh.set_instance_shader_parameter("line_count", line_count)
	mesh.set_instance_shader_parameter("line_thickness", line_thickness)
	mesh.set_instance_shader_parameter("glow_multiplier", glow_multiplier)

	var label: Label3D = get_node_or_null("Label3D") as Label3D
	if label:
		label.text = label_text


## Detects valid player entry to trigger the checkpoint activation process.
## [param body]: The 3D physics body that entered the trigger volume.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.name == "Player" or body.is_in_group("Player"):
		if "noclip" in body and body.get("noclip") == true:
			return

		if not is_activated:
			activate_checkpoint()


## Marks this node as the active checkpoint, updates the global save, and changes visuals to active.
func activate_checkpoint() -> void:
	# 1. SHUT DOWN EVERY OTHER CHECKPOINT!
	# This calls deactivate_checkpoint() on every node in the group
	get_tree().call_group("checkpoints", "deactivate_checkpoint")

	# 2. TURN THIS ONE ON
	is_activated = true
	SaveManager.last_checkpoint_pos = global_position
	print("Checkpoint executing: Checkpoint position saved at ", SaveManager.last_checkpoint_pos)

	label_text = "Checkpoint Activated"
	speed = -1.0
	line_thickness = 0.8
	base_color = Color(0.0, 0.906, 0.471, 0.102)
	_update_visuals()

	# 3. PLAY ACTIVATION SOUND
	if is_instance_valid(audio_player) and activation_sound:
		print("Checkpoint executing: Playing activation sound.")
		audio_player.stream = activation_sound
		audio_player.play()
	else:
		print("Checkpoint executing: Warning - No audio_player or activation_sound assigned.")


## Resets visuals back to its original cache when another checkpoint is triggered.
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
	_update_visuals()
