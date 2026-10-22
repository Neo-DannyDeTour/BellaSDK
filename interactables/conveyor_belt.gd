@tool
## A physical conveyor belt surface that continuously translates physics bodies.
##
## Adjusts underlying constant_linear_velocity parameter while scrolling a custom
## shader texture to match speed and direction vectors.
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
## Automatically calculates shader UV rotation based on physical move_direction.
@export var auto_sync_visuals: bool = true:
	set(value):
		auto_sync_visuals = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_all()

## Overrides shader rotation if auto_sync_visuals is disabled.
@export_range(0.0, 360.0) var manual_texture_rotation: float = 0.0:
	set(value):
		manual_texture_rotation = value
		if not auto_sync_visuals and is_inside_tree() and Engine.is_editor_hint():
			_update_visuals()

## The visual mesh representing the belt surface.
var mesh: MeshInstance3D = null
## The physical bounds of the conveyor platform.
var collision_shape: CollisionShape3D = null
## An editor-only debug arrow indicating flow direction.
var direction_arrow: Node3D = null


## Hides editor helpers and performs initial parameter synchronization.
func _ready() -> void:
	mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	direction_arrow = get_node_or_null("DirectionArrow") as Node3D

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


## Applies calculated velocity vector to static body surface properties.
func _update_physics() -> void:
	if not is_node_ready():
		return

	constant_linear_velocity = move_direction.normalized() * speed


## Re-calculates and transmits rotation and speed variables to surface shader material.
func _update_visuals() -> void:
	if not is_node_ready():
		return

	var angle: float = 0.0

	if auto_sync_visuals:
		angle = atan2(move_direction.x, -move_direction.z)
	else:
		angle = deg_to_rad(manual_texture_rotation)

	if is_instance_valid(mesh):
		mesh.set_instance_shader_parameter(&"rotation_angle", angle)
		mesh.set_instance_shader_parameter(&"scroll_speed", speed)


## Rotates debug arrow node to face exact trajectory of current move_direction.
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


## Synchronizes dimensions of active visual mesh and physical collision shape.
func _update_size() -> void:
	if not is_node_ready():
		return

	if is_instance_valid(mesh):
		var box_mesh: BoxMesh = mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(conveyor_size.x, 0.1, conveyor_size.y)
		else:
			var plane_mesh: PlaneMesh = mesh.mesh as PlaneMesh
			if plane_mesh:
				plane_mesh.size = Vector2(conveyor_size.x, conveyor_size.y)

	if is_instance_valid(collision_shape):
		var box_shape: BoxShape3D = collision_shape.shape as BoxShape3D
		if box_shape:
			box_shape.size = Vector3(conveyor_size.x, 0.1, conveyor_size.y)
