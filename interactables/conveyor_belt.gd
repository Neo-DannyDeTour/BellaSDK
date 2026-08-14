@tool
## A physical conveyor belt surface that continuously translates physics bodies.
##
## Adjusts the underlying `constant_linear_velocity` parameter while simultaneously scrolling
## a custom shader texture to match the speed and direction vectors.
class_name ConveyorBelt
extends StaticBody3D

@export_group("Conveyor Physics")
## The 3D unit vector defining the direction objects will be pushed.
@export var move_direction: Vector3 = Vector3(0.0, 0.0, 1.0):
	set(value):
		move_direction = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_all()

## The magnitude of velocity applied to bodies riding the belt.
@export var speed: float = 2.0:
	set(value):
		speed = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_all()

## The width and length dimensions of the physical belt and collision area.
@export var conveyor_size: Vector2 = Vector2(2.0, 10.0):
	set(value):
		conveyor_size = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_size()

@export_group("Visual Synchronization")
## Automatically calculates the shader UV rotation based on the physical [member move_direction].
@export var auto_sync_visuals: bool = true:
	set(value):
		auto_sync_visuals = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_all()

## Overrides the shader rotation if [member auto_sync_visuals] is disabled.
@export_range(0.0, 360.0) var manual_texture_rotation: float = 0.0:
	set(value):
		manual_texture_rotation = value
		if not auto_sync_visuals and is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## The visual mesh representing the belt surface.
@onready var mesh: MeshInstance3D = $MeshInstance3D
## The physical bounds of the conveyor platform.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
## An editor-only debug arrow indicating flow direction.
@onready var direction_arrow: Node3D = $DirectionArrow


## Hides editor helpers and performs initial parameter synchronization.
func _ready() -> void:
	if not Engine.is_editor_hint():
		if is_instance_valid(direction_arrow):
			direction_arrow.hide()

	_update_all()


## Helper function that re-evaluates all physics, visual, and dimensional traits.
func _update_all() -> void:
	_update_physics()
	_update_visuals()
	_update_arrow()
	_update_size()


## Applies the calculated velocity vector to the underlying [StaticBody3D] surface properties.
func _update_physics() -> void:
	if not is_node_ready():
		return

	if not Engine.is_editor_hint():
		print("_update_physics() called: Applying velocity.")

	constant_linear_velocity = move_direction.normalized() * speed


## Re-calculates and transmits rotation and speed variables to the surface shader material.
func _update_visuals() -> void:
	if not is_node_ready():
		return

	if not Engine.is_editor_hint():
		print("_update_visuals() called: Synchronizing shader parameters.")

	var angle: float = 0.0

	if auto_sync_visuals:
		angle = atan2(move_direction.x, -move_direction.z)
	else:
		angle = deg_to_rad(manual_texture_rotation)

	if is_instance_valid(mesh):
		mesh.set_instance_shader_parameter("rotation_angle", angle)
		mesh.set_instance_shader_parameter("scroll_speed", speed)


## Rotates the debug arrow node to face the exact trajectory of the current [member move_direction].
func _update_arrow() -> void:
	if not is_node_ready() or not is_instance_valid(direction_arrow):
		return

	var dir: Vector3 = move_direction.normalized()

	if dir.length_squared() > 0.001:
		var up_axis: Vector3 = dir
		var right_axis: Vector3 = Vector3.UP.cross(up_axis).normalized()

		if right_axis.length_squared() < 0.001:
			right_axis = Vector3.RIGHT

		var forward_axis: Vector3 = right_axis.cross(up_axis).normalized()
		direction_arrow.basis = Basis(right_axis, up_axis, forward_axis)


## Synchronizes the dimensions of the active visual mesh and physical collision shape.
func _update_size() -> void:
	if not is_node_ready():
		return

	if not Engine.is_editor_hint():
		print("_update_size() called: Adjusting floor mesh and collision boundaries.")

	if is_instance_valid(mesh):
		if mesh.mesh is BoxMesh:
			mesh.mesh.size = Vector3(conveyor_size.x, 0.1, conveyor_size.y)
		elif mesh.mesh is PlaneMesh:
			mesh.mesh.size = Vector2(conveyor_size.x, conveyor_size.y)

	if is_instance_valid(collision_shape) and collision_shape.shape is BoxShape3D:
		collision_shape.shape.size = Vector3(conveyor_size.x, 0.1, conveyor_size.y)
