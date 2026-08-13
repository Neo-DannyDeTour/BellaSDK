@tool
class_name PhysicsMagnet
extends Area3D

enum MagnetMode { THROWN_ONLY, ALL, REPEL }

@export_category("Magnet Settings")
## Mode.
@export var mode: MagnetMode = MagnetMode.ALL
## Force multiplier.
@export var force_multiplier: float = 25.0
## Throw velocity threshold.
@export var throw_velocity_threshold: float = 3.0
## Only objects assigned to this group will react to the magnet.
@export var allowed_group: StringName = &"magnetizable"

@export_category("Visuals & Range")
## Magnet radius.
@export var magnet_radius: float = 5.0:
	set(value):
		magnet_radius = value
		_update_size()

## Show visuals.
@export var show_visuals: bool = true:
	set(value):
		show_visuals = value
		_update_visibility()

## Collision shape.
@export var collision_shape: CollisionShape3D
## Visual mesh.
@export var visual_mesh: MeshInstance3D

## Editor icon.
@onready var _editor_icon: Sprite3D = get_node_or_null("%EditorIcon") as Sprite3D

# OPTIMIZATION: Track bodies via signals instead of polling get_overlapping_bodies()
## Active bodies.
var _active_bodies: Dictionary = {}


func _ready() -> void:
	if not Engine.is_editor_hint():
		if is_instance_valid(_editor_icon):
			_editor_icon.queue_free()

		# Connect signals for event-driven tracking
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

		# Disable process by default until something enters the field
		set_physics_process(false)

	collision_layer = 0
	collision_mask = 1
	_update_size()
	_update_visibility()


func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D:
		return

	if not body.is_in_group(allowed_group):
		return

	_active_bodies[body] = true
	set_physics_process(true)  # Wake up the magnet


func _on_body_exited(body: Node3D) -> void:
	if _active_bodies.has(body):
		_active_bodies.erase(body)

		if _active_bodies.is_empty():
			set_physics_process(false)  # Put the magnet to sleep to save CPU


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# OPTIMIZATION: Iterate over the pre-filtered dictionary
	for body: RigidBody3D in _active_bodies:
		if is_instance_valid(body) and _should_affect(body):
			_apply_magnet_force(body)


func _should_affect(body: RigidBody3D) -> bool:
	if body.get("is_held") == true:
		return false

	if mode == MagnetMode.THROWN_ONLY:
		var vel: Vector3 = body.linear_velocity
		# OPTIMIZATION: Compare squared lengths to avoid square root math
		var threshold_sq: float = throw_velocity_threshold * throw_velocity_threshold
		if vel.length_squared() < threshold_sq:
			return false

	return true


func _apply_magnet_force(body: RigidBody3D) -> void:
	var direction: Vector3 = global_position - body.global_position
	var dist_sq: float = direction.length_squared()

	# OPTIMIZATION: 0.2 squared is 0.04
	if dist_sq < 0.04:
		return

	var distance: float = sqrt(dist_sq)
	var force_dir: Vector3 = direction / distance
	var applied_force: Vector3 = Vector3.ZERO

	if mode == MagnetMode.REPEL:
		applied_force = -force_dir * force_multiplier
	else:
		applied_force = force_dir * force_multiplier

	body.apply_central_force(applied_force)


func _update_size() -> void:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
		collision_shape.shape.radius = magnet_radius

	if is_instance_valid(visual_mesh) and visual_mesh.mesh is SphereMesh:
		visual_mesh.mesh.radius = magnet_radius
		visual_mesh.mesh.height = magnet_radius * 2.0


func _update_visibility() -> void:
	if is_instance_valid(visual_mesh):
		visual_mesh.visible = show_visuals
