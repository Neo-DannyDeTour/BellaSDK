@tool
## Procedural stairs generator replacing CSG with high-performance extruded [ArrayMesh].
class_name ProceduralStairs
extends MeshInstance3D

@export_category("Stair Dimensions")
## Total number of individual stair steps in sequence.
@export_range(1, 100) var step_count: int = 10:
	set(value):
		step_count = value
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

## Total vertical climb height in meters for the stairs.
@export var total_height: float = 2.0:
	set(value):
		total_height = maxf(0.1, value)
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

## Total horizontal run length in meters for the stairs.
@export var total_length: float = 3.0:
	set(value):
		total_length = maxf(0.1, value)
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

## Lateral width of the stair treads in meters.
@export var stair_width: float = 1.5:
	set(value):
		stair_width = maxf(0.1, value)
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

@export_category("EQ Landings")
## Zero-based step indices that include an extended intermediate landing.
@export var landing_step_indices: Array[int] = []:
	set(value):
		landing_step_indices = value
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

## Additional horizontal tread length in meters added to intermediate landings.
@export var landing_extra_length: float = 1.0:
	set(value):
		landing_extra_length = maxf(0.0, value)
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

## Additional horizontal tread length in meters added to final topmost step.
@export var top_landing_length: float = 1.5:
	set(value):
		top_landing_length = maxf(0.0, value)
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

@export_category("Stair Style")
## Whether to extrude stair geometry down to base floor plane.
@export var fill_to_floor: bool = true:
	set(value):
		fill_to_floor = value
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

## Profile underside thickness in meters when [member fill_to_floor] is false.
@export var step_thickness: float = 0.2:
	set(value):
		step_thickness = maxf(0.01, value)
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

@export_category("Physics")
## Whether to generate a simplified smooth collision ramp for player movement.
@export var generate_smooth_ramp: bool = true:
	set(value):
		generate_smooth_ramp = value
		if is_instance_valid(self) and is_inside_tree():
			_update_stairs()

## The [StaticBody3D] hosting procedural physics collision shapes.
var ramp_body: StaticBody3D = null

## The [CollisionPolygon3D] extruded along stair width for physics ramp.
var ramp_collision: CollisionPolygon3D = null


## Lifecycle callback initializing stair procedural generation.
func _ready() -> void:
	print("ProceduralStairs: Initializing procedural stair mesh: ", name)
	_update_stairs()


## Recalculates 2D stair profile points and triggers mesh extrusion.
func _update_stairs() -> void:
	if step_count < 1:
		return

	print("ProceduralStairs: Recalculating geometry profiles for: ", name)
	var step_h: float = total_length / float(step_count)
	var step_v: float = total_height / float(step_count)

	var points: PackedVector2Array = PackedVector2Array()
	var ramp_points: PackedVector2Array = PackedVector2Array()

	points.append(Vector2(0.0, 0.0))
	ramp_points.append(Vector2(0.0, 0.0))

	var cx: float = 0.0
	var cy: float = 0.0

	for i: int in range(step_count):
		var extra: float = 0.0

		if i in landing_step_indices:
			extra += landing_extra_length

		if i == step_count - 1:
			extra += top_landing_length

		cy += step_v
		points.append(Vector2(cx, cy))

		cx += step_h + extra
		points.append(Vector2(cx, cy))

		ramp_points.append(Vector2(cx - extra, cy))

		if extra > 0.0:
			ramp_points.append(Vector2(cx, cy))

	if fill_to_floor:
		points.append(Vector2(cx, 0.0))
		ramp_points.append(Vector2(cx, 0.0))
	else:
		points.append(Vector2(cx, cy - step_thickness))
		points.append(Vector2(0.0, -step_thickness))

		ramp_points.append(Vector2(cx, cy - step_thickness))
		ramp_points.append(Vector2(0.0, -step_thickness))

	_build_extruded_mesh(points)
	_build_collision_ramp(ramp_points)


## Constructs an extruded 3D [ArrayMesh] from a 2D profile polygon.
## [param profile] Profile polygon coordinates on XY plane.
func _build_extruded_mesh(profile: PackedVector2Array) -> void:
	print("ProceduralStairs: Generating extruded ArrayMesh geometry.")
	var n: int = profile.size()
	if n < 3:
		return

	var half_width: float = stair_width * 0.5
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(profile)
	var num_indices: int = indices.size()

	var i: int = 0
	while i < num_indices:
		var p0: Vector2 = profile[indices[i]]
		var p1: Vector2 = profile[indices[i + 1]]
		var p2: Vector2 = profile[indices[i + 2]]

		st.set_normal(Vector3(0.0, 0.0, -1.0))
		st.set_uv(Vector2(p0.x, p0.y))
		st.add_vertex(Vector3(p0.x, p0.y, -half_width))

		st.set_normal(Vector3(0.0, 0.0, -1.0))
		st.set_uv(Vector2(p2.x, p2.y))
		st.add_vertex(Vector3(p2.x, p2.y, -half_width))

		st.set_normal(Vector3(0.0, 0.0, -1.0))
		st.set_uv(Vector2(p1.x, p1.y))
		st.add_vertex(Vector3(p1.x, p1.y, -half_width))
		i += 3

	i = 0
	while i < num_indices:
		var p0: Vector2 = profile[indices[i]]
		var p1: Vector2 = profile[indices[i + 1]]
		var p2: Vector2 = profile[indices[i + 2]]

		st.set_normal(Vector3(0.0, 0.0, 1.0))
		st.set_uv(Vector2(p0.x, p0.y))
		st.add_vertex(Vector3(p0.x, p0.y, half_width))

		st.set_normal(Vector3(0.0, 0.0, 1.0))
		st.set_uv(Vector2(p1.x, p1.y))
		st.add_vertex(Vector3(p1.x, p1.y, half_width))

		st.set_normal(Vector3(0.0, 0.0, 1.0))
		st.set_uv(Vector2(p2.x, p2.y))
		st.add_vertex(Vector3(p2.x, p2.y, half_width))
		i += 3

	for edge_idx: int in range(n):
		var p_curr: Vector2 = profile[edge_idx]
		var p_next: Vector2 = profile[(edge_idx + 1) % n]

		var edge_dir: Vector2 = (p_next - p_curr).normalized()
		var normal_2d: Vector2 = Vector2(-edge_dir.y, edge_dir.x)
		var norm_3d: Vector3 = Vector3(normal_2d.x, normal_2d.y, 0.0)

		var v0: Vector3 = Vector3(p_curr.x, p_curr.y, -half_width)
		var v1: Vector3 = Vector3(p_next.x, p_next.y, -half_width)
		var v2: Vector3 = Vector3(p_next.x, p_next.y, half_width)
		var v3: Vector3 = Vector3(p_curr.x, p_curr.y, half_width)

		st.set_normal(norm_3d)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(v0)
		st.set_normal(norm_3d)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(v1)
		st.set_normal(norm_3d)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(v2)

		st.set_normal(norm_3d)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(v0)
		st.set_normal(norm_3d)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(v2)
		st.set_normal(norm_3d)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(v3)

	st.generate_tangents()
	mesh = st.commit()


## Builds or updates the [CollisionPolygon3D] ramp for character navigation.
## [param ramp_points] Profile polygon coordinates for collision ramp.
func _build_collision_ramp(ramp_points: PackedVector2Array) -> void:
	if not generate_smooth_ramp:
		if is_instance_valid(ramp_body):
			print("ProceduralStairs: Disabling smooth ramp collision.")
			ramp_body.queue_free()
			ramp_body = null
		return

	print("ProceduralStairs: Updating physics ramp collision geometry.")
	if not is_instance_valid(ramp_body):
		ramp_body = get_node_or_null("PhysicsRampBody") as StaticBody3D
		if not is_instance_valid(ramp_body):
			ramp_body = StaticBody3D.new()
			ramp_body.name = "PhysicsRampBody"
			add_child(ramp_body)

	# Physics Layer 1: Environment
	ramp_body.collision_layer = 1
	ramp_body.collision_mask = 0

	if not is_instance_valid(ramp_collision):
		ramp_collision = ramp_body.get_node_or_null("RampCollision") as CollisionPolygon3D
		if not is_instance_valid(ramp_collision):
			ramp_collision = CollisionPolygon3D.new()
			ramp_collision.name = "RampCollision"
			ramp_body.add_child(ramp_collision)

	ramp_collision.depth = stair_width
	ramp_collision.position.z = -stair_width * 0.5
	ramp_collision.polygon = ramp_points
