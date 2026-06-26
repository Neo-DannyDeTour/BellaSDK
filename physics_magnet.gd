@tool
class_name PhysicsMagnet
extends Area3D

enum MagnetMode { THROWN_ONLY, ALL, REPEL }

@export_category("Magnet Settings")
@export var mode: MagnetMode = MagnetMode.ALL
@export var force_multiplier: float = 25.0
@export var throw_velocity_threshold: float = 3.0
## Only objects assigned to this group will react to the magnet.
@export var allowed_group: StringName = &"magnetizable"

@export_category("Visuals & Range")
@export var magnet_radius: float = 5.0:
	set(value):
		magnet_radius = value
		_update_size()

@export var show_visuals: bool = true:
	set(value):
		show_visuals = value
		_update_visibility()

@export var collision_shape: CollisionShape3D
@export var visual_mesh: MeshInstance3D

@onready var _editor_icon: Sprite3D = %EditorIcon


func _ready() -> void:
	if not Engine.is_editor_hint():
		if is_instance_valid(_editor_icon):
			_editor_icon.queue_free()

	if not Engine.is_editor_hint():
		print("PhysicsMagnet: _ready() initialized.")
	collision_layer = 0
	collision_mask = 1
	_update_size()
	_update_visibility()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var bodies: Array[Node3D] = get_overlapping_bodies()

	for body in bodies:
		if not body is RigidBody3D:
			continue

		if not body.is_in_group(allowed_group):
			continue

		if _should_affect(body):
			_apply_magnet_force(body as RigidBody3D)


func _should_affect(body: Node3D) -> bool:
	if body.get("is_held") == true:
		return false

	if mode == MagnetMode.THROWN_ONLY:
		var vel: Vector3 = body.get("linear_velocity")
		if vel.length() < throw_velocity_threshold:
			return false

	return true


func _apply_magnet_force(body: RigidBody3D) -> void:
	var direction: Vector3 = global_position - body.global_position
	var distance: float = direction.length()

	if distance < 0.2:
		return

	var force_dir: Vector3 = direction.normalized()
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
