## Camera-facing ribbon trail mesh attached to moving projectiles.
## Generates dynamic strip geometry between historic global positions.
class_name Trail3D
extends MeshInstance3D

## Maximum number of historical points recorded along flight path.
@export var max_points: int = 60

## Duration in seconds before a recorded position point expires.
@export var point_lifetime: float = 1.2

## Ribbon width at leading emitter point in meters.
@export var start_width: float = 0.65

## Ribbon width at trailing expired tail in meters.
@export var end_width: float = 0.05

## Minimum distance traveled before recording a new trail node.
@export var min_distance: float = 0.15

## Base tint and alpha applied across ribbon trail vertices.
@export var trail_color: Color = Color(1.0, 1.0, 1.0, 0.85)

## Local offset from parent origin where ribbon vertices originate.
@export var target_offset: Vector3 = Vector3(0.0, 0.85, 0.0)

## Active flag controlling whether new path points are recorded.
@export var is_emitting: bool = false

## Cached immediate mesh instance generating geometry every frame.
var _immediate_mesh: ImmediateMesh = null

## Unshaded transparent material utilized for ribbon mesh draw calls.
var _material: StandardMaterial3D = null

## History buffer containing global positions along motion path.
var _points: Array[Vector3] = []

## Timestamp buffer tracking age of each recorded position point.
var _times: Array[float] = []


## Configures unshaded material and initializes dynamic immediate mesh.
func _ready() -> void:
	print("Trail3D: Initializing ribbon trail system.")
	top_level = true
	global_transform = Transform3D.IDENTITY

	_immediate_mesh = ImmediateMesh.new()
	mesh = _immediate_mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	material_override = _material


## Updates point lifetimes, records movement, and rebuilds ribbon mesh.
func _process(delta: float) -> void:
	for i: int in range(_times.size()):
		_times[i] += delta

	while not _times.is_empty() and _times.back() > point_lifetime:
		_times.pop_back()
		_points.pop_back()

	var target_node: Node3D = get_parent() as Node3D
	if is_emitting and is_instance_valid(target_node):
		var current_pos: Vector3 = target_node.global_transform * target_offset
		if (
			_points.is_empty()
			or (current_pos.distance_squared_to(_points[0]) >= (min_distance * min_distance))
		):
			_points.push_front(current_pos)
			_times.push_front(0.0)
			if _points.size() > max_points:
				_points.pop_back()
				_times.pop_back()

	if _points.size() < 2:
		if is_instance_valid(_immediate_mesh):
			_immediate_mesh.clear_surfaces()
		return

	_rebuild_mesh()


## Starts emitting new ribbon trail segments from parent position.
func start_trail() -> void:
	print("Trail3D: Activating trail emission.")
	is_emitting = true


## Stops recording new trail segments allowing existing ribbon to fade.
func stop_trail() -> void:
	print("Trail3D: Stopping trail emission.")
	is_emitting = false


## Clears all points immediately and purges mesh geometry surfaces.
func clear_trail() -> void:
	print("Trail3D: Clearing trail points.")
	_points.clear()
	_times.clear()
	if is_instance_valid(_immediate_mesh):
		_immediate_mesh.clear_surfaces()


## Rebuilds camera-aligned quad vertices using discrete triangles.
func _rebuild_mesh() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var cam_pos: Vector3 = (
		camera.global_position if is_instance_valid(camera) else Vector3(0.0, 10.0, 10.0)
	)

	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)

	var point_count: int = _points.size()
	var denom: float = float(point_count - 1)

	# Pre-compute left and right edge points for each recorded step
	var left_pts: Array[Vector3] = []
	var right_pts: Array[Vector3] = []
	var colors: Array[Color] = []
	var uvs_y: Array[float] = []

	left_pts.resize(point_count)
	right_pts.resize(point_count)
	colors.resize(point_count)
	uvs_y.resize(point_count)

	for i: int in range(point_count):
		var t: float = float(i) / denom
		var current_w: float = lerpf(start_width, end_width, t)
		var alpha: float = trail_color.a * (1.0 - t)
		colors[i] = Color(trail_color.r, trail_color.g, trail_color.b, alpha)
		uvs_y[i] = t

		var dir: Vector3
		if i < point_count - 1:
			dir = _points[i] - _points[i + 1]
		else:
			dir = _points[i - 1] - _points[i]

		if dir.is_zero_approx():
			dir = Vector3.FORWARD
		dir = dir.normalized()

		var to_cam: Vector3 = (cam_pos - _points[i]).normalized()
		var side: Vector3 = dir.cross(to_cam).normalized()
		if side.is_zero_approx():
			side = dir.cross(Vector3.UP).normalized()
		if side.is_zero_approx():
			side = Vector3.RIGHT

		var half_w: Vector3 = side * (current_w * 0.5)
		left_pts[i] = _points[i] - half_w
		right_pts[i] = _points[i] + half_w

	# Construct discrete 2-triangle quads (6 vertices per segment, always divisible by 3)
	for i: int in range(point_count - 1):
		var p0_l: Vector3 = left_pts[i]
		var p0_r: Vector3 = right_pts[i]
		var p1_l: Vector3 = left_pts[i + 1]
		var p1_r: Vector3 = right_pts[i + 1]

		var c0: Color = colors[i]
		var c1: Color = colors[i + 1]
		var uv0_y: float = uvs_y[i]
		var uv1_y: float = uvs_y[i + 1]

		# Triangle 1 (p0_l -> p0_r -> p1_l)
		_immediate_mesh.surface_set_color(c0)
		_immediate_mesh.surface_set_uv(Vector2(0.0, uv0_y))
		_immediate_mesh.surface_add_vertex(p0_l)

		_immediate_mesh.surface_set_color(c0)
		_immediate_mesh.surface_set_uv(Vector2(1.0, uv0_y))
		_immediate_mesh.surface_add_vertex(p0_r)

		_immediate_mesh.surface_set_color(c1)
		_immediate_mesh.surface_set_uv(Vector2(0.0, uv1_y))
		_immediate_mesh.surface_add_vertex(p1_l)

		# Triangle 2 (p1_l -> p0_r -> p1_r)
		_immediate_mesh.surface_set_color(c1)
		_immediate_mesh.surface_set_uv(Vector2(0.0, uv1_y))
		_immediate_mesh.surface_add_vertex(p1_l)

		_immediate_mesh.surface_set_color(c0)
		_immediate_mesh.surface_set_uv(Vector2(1.0, uv0_y))
		_immediate_mesh.surface_add_vertex(p0_r)

		_immediate_mesh.surface_set_color(c1)
		_immediate_mesh.surface_set_uv(Vector2(1.0, uv1_y))
		_immediate_mesh.surface_add_vertex(p1_r)

	_immediate_mesh.surface_end()
