@tool
## Procedural vacuum tube transporting rigid bodies and players along a 3D path.
class_name PneumaticTube
extends Path3D


## Internal tracking record for objects traveling inside the tube.
class PneumaticTubeRider:
	extends RefCounted
	## Reference to the transported entity [Node3D].
	var body: Node3D
	## Distance traveled along the [Curve3D] in meters.
	var progress: float = 0.0
	## Stores whether a [RigidBody3D] was frozen before capture.
	var was_frozen: bool = false
	## Physics processing status before tube entry.
	var had_physics_process: bool = true


## Emitted when an entity enters the suction intake.
signal body_entered_tube(body: Node3D)

## Emitted when an entity is ejected from the tube exit.
signal body_exited_tube(body: Node3D)

## Collision mask targeting layers 2 (Player), 3 (Interactive), 4 (Debris), 5 (Enemies).
const DEFAULT_MASK: int = (
	CollisionLayers.MASK_PLAYER
	| CollisionLayers.MASK_INTERACTIVE
	| CollisionLayers.MASK_DEBRIS
	| CollisionLayers.MASK_ENEMIES
)

## Outer radius of the cylindrical tube in meters.
@export var outer_radius: float = 0.6:
	set(value):
		outer_radius = maxf(0.1, value)
		if is_inside_tree() and is_instance_valid(tube_mesh):
			rebuild_tube()

## Wall thickness of the hollow tube cylinder.
@export var wall_thickness: float = 0.06:
	set(value):
		wall_thickness = clampf(value, 0.01, outer_radius * 0.4)
		if is_inside_tree() and is_instance_valid(tube_mesh):
			rebuild_tube()

## Subdivisions for circular tube geometry resolution.
@export_range(8, 48, 1) var circle_sides: int = 24:
	set(value):
		circle_sides = clampi(value, 8, 48)
		if is_inside_tree() and is_instance_valid(tube_mesh):
			rebuild_tube()

## Speed of travel along the path in meters per second.
@export var transport_speed: float = 24.0

## Launch impulse speed when exiting the tube.
@export var exit_launch_speed: float = 26.0

## Material applied to the procedural mesh instance.
@export var tube_material: Material:
	set(value):
		tube_material = value
		if is_inside_tree() and is_instance_valid(tube_mesh):
			tube_mesh.material_override = tube_material

## Procedural mesh instance displaying the swept hollow tube [ArrayMesh].
@onready var tube_mesh: MeshInstance3D = get_node_or_null("TubeMesh") as MeshInstance3D

## Suction trigger area positioned at the start of the curve.
@onready var intake_area: Area3D = get_node_or_null("IntakeArea") as Area3D

## Orientation marker placed at the path endpoint.
@onready var exit_marker: Marker3D = get_node_or_null("ExitMarker") as Marker3D

## Active list of all bodies currently traveling through the tube.
var _active_riders: Array[PneumaticTubeRider] = []


## Initializes path duplication, sets collision masks, and builds geometry.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	print("PneumaticTube: Initializing tube instance.")
	if curve != null and not Engine.is_editor_hint():
		curve = curve.duplicate()

	if intake_area != null:
		intake_area.collision_layer = CollisionLayers.MASK_NONE
		intake_area.collision_mask = DEFAULT_MASK
		if not intake_area.body_entered.is_connected(_on_intake_body_entered):
			intake_area.body_entered.connect(_on_intake_body_entered)

	rebuild_tube()


## Updates spatial rider positions along the curve each physics tick.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or curve == null or _active_riders.is_empty():
		set_physics_process(false)
		return

	var total_len: float = curve.get_baked_length()
	for i: int in range(_active_riders.size() - 1, -1, -1):
		var rider: PneumaticTubeRider = _active_riders[i]
		if not is_instance_valid(rider.body):
			_active_riders.remove_at(i)
			continue

		rider.progress += transport_speed * delta
		if rider.progress >= total_len:
			_eject_rider(rider)
			_active_riders.remove_at(i)
		else:
			var local_pos: Vector3 = curve.sample_baked(rider.progress)
			rider.body.global_position = to_global(local_pos)

			# Allow player to retain free mouse look; orient physics props along curve
			if not (rider.body is Player):
				var next_progress: float = minf(rider.progress + 0.5, total_len)
				var next_pos: Vector3 = curve.sample_baked(next_progress)
				var dir: Vector3 = (to_global(next_pos) - rider.body.global_position).normalized()
				if not dir.is_zero_approx():
					var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
					rider.body.look_at(rider.body.global_position + dir, up)

	if _active_riders.is_empty():
		set_physics_process(false)


## Rebuilds the hollow cylindrical [ArrayMesh] along the [Curve3D] path.
func rebuild_tube() -> void:
	print("PneumaticTube: Rebuilding procedural ArrayMesh geometry.")
	if not is_instance_valid(tube_mesh) or curve == null or curve.point_count < 2:
		return

	var total_len: float = curve.get_baked_length()
	if total_len <= 0.001:
		return

	var inner_r: float = maxf(0.01, outer_radius - wall_thickness)
	var steps: int = maxi(2, ceili(total_len / 0.5))
	var stride: int = circle_sides + 1

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	# 1. Outer and inner cylindrical walls
	var inner_base: int = (steps + 1) * stride
	for r: int in range(steps + 1):
		var dist: float = (float(r) / float(steps)) * total_len
		var xform: Transform3D = curve.sample_baked_with_rotation(dist, true)
		for s: int in range(stride):
			var angle: float = (float(s) / float(circle_sides)) * TAU
			var dir: Vector3 = xform.basis.x * cos(angle) + xform.basis.y * sin(angle)
			var norm: Vector3 = dir.normalized()
			var uv: Vector2 = Vector2(dist, float(s) / float(circle_sides))
			verts.append(xform.origin + dir * outer_radius)
			normals.append(norm)
			uvs.append(uv)

	for r: int in range(steps + 1):
		var dist: float = (float(r) / float(steps)) * total_len
		var xform: Transform3D = curve.sample_baked_with_rotation(dist, true)
		for s: int in range(stride):
			var angle: float = (float(s) / float(circle_sides)) * TAU
			var dir: Vector3 = xform.basis.x * cos(angle) + xform.basis.y * sin(angle)
			var norm: Vector3 = -dir.normalized()
			var uv: Vector2 = Vector2(dist, float(s) / float(circle_sides))
			verts.append(xform.origin + dir * inner_r)
			normals.append(norm)
			uvs.append(uv)

	for r: int in range(steps):
		var row_a: int = r * stride
		var row_b: int = (r + 1) * stride
		for s: int in range(circle_sides):
			var oa: int = row_a + s
			var ob: int = row_a + s + 1
			var oc: int = row_b + s
			var od: int = row_b + s + 1
			indices.append(oa)
			indices.append(oc)
			indices.append(ob)
			indices.append(ob)
			indices.append(oc)
			indices.append(od)

			var ia: int = inner_base + row_a + s
			var ib: int = inner_base + row_a + s + 1
			var ic: int = inner_base + row_b + s
			var id: int = inner_base + row_b + s + 1
			indices.append(ia)
			indices.append(ib)
			indices.append(ic)
			indices.append(ib)
			indices.append(id)
			indices.append(ic)

	# 2. Annular end caps at start (r=0) and end (r=steps)
	_append_ring_cap(verts, normals, uvs, indices, 0.0, outer_radius, inner_r, true)
	_append_ring_cap(verts, normals, uvs, indices, total_len, outer_radius, inner_r, false)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh: ArrayMesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	tube_mesh.mesh = arr_mesh

	if tube_material != null:
		tube_mesh.material_override = tube_material

	_update_boundary_markers()


## Appends an annular end-cap ring at [param dist] along the baked curve.
func _append_ring_cap(
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	dist: float,
	outer_r: float,
	inner_r: float,
	is_start: bool
) -> void:
	var xform: Transform3D = curve.sample_baked_with_rotation(dist, true)
	var cap_normal: Vector3 = xform.basis.z if is_start else -xform.basis.z
	var base_idx: int = verts.size()
	var stride: int = circle_sides + 1

	for s: int in range(stride):
		var angle: float = (float(s) / float(circle_sides)) * TAU
		var dir: Vector3 = xform.basis.x * cos(angle) + xform.basis.y * sin(angle)
		var v_coord: float = float(s) / float(circle_sides)
		verts.append(xform.origin + dir * outer_r)
		normals.append(cap_normal)
		uvs.append(Vector2(dist, v_coord))
		verts.append(xform.origin + dir * inner_r)
		normals.append(cap_normal)
		uvs.append(Vector2(dist, v_coord))

	for s: int in range(circle_sides):
		var out_a: int = base_idx + (s * 2)
		var in_a: int = out_a + 1
		var out_b: int = out_a + 2
		var in_b: int = out_a + 3
		if is_start:
			indices.append(out_a)
			indices.append(out_b)
			indices.append(in_a)
			indices.append(out_b)
			indices.append(in_b)
			indices.append(in_a)
		else:
			indices.append(out_a)
			indices.append(in_a)
			indices.append(out_b)
			indices.append(out_b)
			indices.append(in_a)
			indices.append(in_b)


## Updates intake area and exit marker coordinates to curve endpoints.
func _update_boundary_markers() -> void:
	if is_instance_valid(intake_area) and curve != null and curve.point_count > 0:
		intake_area.position = curve.get_point_position(0)

	if is_instance_valid(exit_marker) and curve != null and curve.point_count > 1:
		var last_index: int = curve.point_count - 1
		exit_marker.position = curve.get_point_position(last_index)
		var exit_dir: Vector3 = _get_exit_vector()
		if not exit_dir.is_zero_approx():
			var up: Vector3 = Vector3.UP if absf(exit_dir.y) < 0.99 else Vector3.FORWARD
			exit_marker.look_at(exit_marker.global_position + exit_dir, up)


## Detects and captures valid physics bodies entering the intake volume.
func _on_intake_body_entered(body: Node3D) -> void:
	print("PneumaticTube: Body entered intake: ", body.name)
	for rider: PneumaticTubeRider in _active_riders:
		if rider.body == body:
			return
	capture_body(body)


## Registers an entity into the active transport queue.
func capture_body(body: Node3D) -> void:
	print("PneumaticTube: Capturing body into tube: ", body.name)
	var rider: PneumaticTubeRider = PneumaticTubeRider.new()
	rider.body = body
	rider.progress = 0.0
	rider.had_physics_process = body.is_physics_processing()

	if body is Player:
		var pl: Player = body if body is Player else null
		pl.enter_tube(self)
	elif body is RigidBody3D:
		var rb: RigidBody3D = body if body is RigidBody3D else null
		rider.was_frozen = rb.freeze
		rb.set_deferred(&"freeze", true)
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body if body is CharacterBody3D else null
		cb.velocity = Vector3.ZERO
		cb.set_physics_process(false)

	body.global_position = to_global(curve.sample_baked(0.0))
	_active_riders.push_back(rider)
	if not Engine.is_editor_hint():
		set_physics_process(true)
	body_entered_tube.emit(body)


## Launches an entity from the tube exit with forward momentum.
func _eject_rider(rider: PneumaticTubeRider) -> void:
	print("PneumaticTube: Ejecting body from tube: ", rider.body.name)
	var launch_vel: Vector3 = _get_exit_vector() * exit_launch_speed

	if rider.body is Player:
		var pl: Player = rider.body if rider.body is Player else null
		pl.exit_tube(launch_vel)
	elif rider.body is RigidBody3D:
		var rb: RigidBody3D = rider.body if rider.body is RigidBody3D else null
		rb.freeze = rider.was_frozen
		rb.linear_velocity = launch_vel
	elif rider.body is CharacterBody3D:
		var cb: CharacterBody3D = rider.body if rider.body is CharacterBody3D else null
		cb.set_physics_process(rider.had_physics_process)
		cb.velocity = launch_vel

	body_exited_tube.emit(rider.body)


## Calculates the normalized global forward tangent vector at the path exit.
func _get_exit_vector() -> Vector3:
	if curve == null or curve.point_count < 2:
		return -global_transform.basis.z

	var total_len: float = curve.get_baked_length()
	var p_end: Vector3 = curve.sample_baked(total_len)
	var p_prev: Vector3 = curve.sample_baked(maxf(0.0, total_len - 0.2))
	var local_dir: Vector3 = (p_end - p_prev).normalized()
	return (global_transform.basis * local_dir).normalized()
