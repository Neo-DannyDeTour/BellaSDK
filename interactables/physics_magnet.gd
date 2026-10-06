## Area pulling or repelling RigidBody3D objects in range.
@tool
class_name PhysicsMagnet
extends Area3D

## Defines magnetic influence behavior.
enum MagnetMode {
	THROWN_ONLY,
	ALL,
	REPEL,
}

@export_category("Magnet Settings")
## Operational mode determining which bodies receive force.
@export var mode: MagnetMode = MagnetMode.ALL
## Force multiplier applied to affected bodies.
@export var force_multiplier: float = 25.0
## Minimum speed squared threshold for [constant MagnetMode.THROWN_ONLY].
@export var throw_velocity_threshold: float = 3.0
## Target group name required on bodies for attraction.
@export var allowed_group: StringName = &"magnetizable"

@export_category("Visuals & Range")
## Radius of the magnetic field in meters.
@export var magnet_radius: float = 5.0:
	set(value):
		magnet_radius = value
		if is_inside_tree():
			_update_size()

## Toggles visibility of the debug visual mesh.
@export var show_visuals: bool = true:
	set(value):
		show_visuals = value
		if is_inside_tree():
			_update_visibility()

## Assigned collision shape defining the area boundary.
@export var collision_shape: CollisionShape3D
## Assigned visual mesh displaying area bounds.
@export var visual_mesh: MeshInstance3D

## Sprite displayed exclusively within the editor.
@onready var _editor_icon: Sprite3D = get_node_or_null("%EditorIcon") as Sprite3D

## Cached active bodies currently inside the magnetic area.
var _active_bodies: Dictionary = {}


## Configures masks, signal hooks, and initial visual dimensions.
func _ready() -> void:
	if not Engine.is_editor_hint():
		if is_instance_valid(_editor_icon):
			_editor_icon.queue_free()

		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
		set_physics_process(false)

	collision_layer = 0
	# Layer 1 (Environment) + Layer 3 (Interactive)
	collision_mask = 5
	_update_size()
	_update_visibility()


## Registers entered rigid body and wakes up physics process.
func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D:
		return

	if not body.is_in_group(allowed_group):
		return

	print("PhysicsMagnet: Body entered magnet range: ", body.name)
	_active_bodies[body] = true
	set_physics_process(true)


## Unregisters exiting rigid body and disables processing when empty.
func _on_body_exited(body: Node3D) -> void:
	if _active_bodies.has(body):
		print("PhysicsMagnet: Body exited magnet range: ", body.name)
		_active_bodies.erase(body)

		if _active_bodies.is_empty():
			set_physics_process(false)


## Applies directional magnetic forces to tracked rigid bodies.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	for body: RigidBody3D in _active_bodies:
		if is_instance_valid(body) and _should_affect(body):
			_apply_magnet_force(body)


## Validates whether [param body] satisfies mode-specific velocity checks.
func _should_affect(body: RigidBody3D) -> bool:
	if body.get("is_held") == true:
		return false

	if mode == MagnetMode.THROWN_ONLY:
		var vel: Vector3 = body.linear_velocity
		var threshold_sq: float = throw_velocity_threshold * throw_velocity_threshold
		if vel.length_squared() < threshold_sq:
			return false

	return true


## Calculates distance vector and applies central force to [param body].
func _apply_magnet_force(body: RigidBody3D) -> void:
	var direction: Vector3 = global_position - body.global_position
	var dist_sq: float = direction.length_squared()

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


## Synchronizes radius to collision shape and visual sphere mesh.
func _update_size() -> void:
	if is_instance_valid(collision_shape):
		var sphere_shape: SphereShape3D = collision_shape.shape as SphereShape3D
		if sphere_shape:
			sphere_shape.radius = magnet_radius

	if is_instance_valid(visual_mesh):
		var sphere_mesh: SphereMesh = visual_mesh.mesh as SphereMesh
		if sphere_mesh:
			sphere_mesh.radius = magnet_radius
			sphere_mesh.height = magnet_radius * 2.0


## Updates visibility state of [member visual_mesh].
func _update_visibility() -> void:
	if is_instance_valid(visual_mesh):
		visual_mesh.visible = show_visuals
