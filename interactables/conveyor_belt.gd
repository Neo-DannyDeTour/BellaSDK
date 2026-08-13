@tool
extends StaticBody3D

@export_group("Conveyor Physics")
## Move direction.
@export var move_direction: Vector3 = Vector3(0.0, 0.0, 1.0):
	set(value):
		move_direction = value
		_update_all()

## Speed.
@export var speed: float = 2.0:
	set(value):
		speed = value
		_update_all()

## Conveyor size.
@export var conveyor_size: Vector2 = Vector2(2.0, 10.0):
	set(value):
		conveyor_size = value
		_update_size()

@export_group("Visual Synchronization")
## Auto sync visuals.
@export var auto_sync_visuals: bool = true:
	set(value):
		auto_sync_visuals = value
		_update_all()

## Manual texture rotation.
@export_range(0.0, 360.0) var manual_texture_rotation: float = 0.0:
	set(value):
		manual_texture_rotation = value
		if not auto_sync_visuals:
			_update_visuals()

## Mesh.
@onready var mesh: MeshInstance3D = $MeshInstance3D
## Collision shape.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
## Direction arrow.
@onready var direction_arrow: Node3D = $DirectionArrow


func _ready() -> void:
	if not Engine.is_editor_hint():
		if direction_arrow:
			direction_arrow.hide()

	_update_all()


func _update_all() -> void:
	_update_physics()
	_update_visuals()
	_update_arrow()
	_update_size()


func _update_physics() -> void:
	if not is_node_ready():
		return

	if not Engine.is_editor_hint():
		print("_update_physics() called: Applying velocity.")

	constant_linear_velocity = move_direction.normalized() * speed


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

	mesh.set_instance_shader_parameter("rotation_angle", angle)
	mesh.set_instance_shader_parameter("scroll_speed", speed)


func _update_arrow() -> void:
	if not is_node_ready() or not direction_arrow:
		return

	var dir: Vector3 = move_direction.normalized()

	if dir.length_squared() > 0.001:
		var up_axis: Vector3 = dir
		var right_axis: Vector3 = Vector3.UP.cross(up_axis).normalized()

		if right_axis.length_squared() < 0.001:
			right_axis = Vector3.RIGHT

		var forward_axis: Vector3 = right_axis.cross(up_axis).normalized()
		direction_arrow.basis = Basis(right_axis, up_axis, forward_axis)


func _update_size() -> void:
	if not is_node_ready():
		return

	if not Engine.is_editor_hint():
		print("_update_size() called: Adjusting floor mesh and collision boundaries.")

	if mesh.mesh is BoxMesh:
		mesh.mesh.size = Vector3(conveyor_size.x, 0.1, conveyor_size.y)
	elif mesh.mesh is PlaneMesh:
		mesh.mesh.size = Vector2(conveyor_size.x, conveyor_size.y)

	if collision_shape.shape is BoxShape3D:
		collision_shape.shape.size = Vector3(conveyor_size.x, 0.1, conveyor_size.y)
