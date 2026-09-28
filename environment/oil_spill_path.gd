@tool
## Generates a smooth, ignitable oil puddle path spawning [VolumetricFire].
class_name OilSpillPath
extends Path3D

## Emitted when [method ignite] is triggered, passing world hit coordinates.
signal ignited(hit_position: Vector3)

## Emitted when combustion finishes along the entire curve length.
signal combustion_completed

## Physics collision layer bitmask for Interactive objects (Layer 3).
const INTERACTIVE_PHYSICS_LAYER: int = 4

@export_category("Spill Dimensions")
## Lateral width of the generated oil puddle ribbon in meters.
@export_range(0.2, 5.0, 0.1) var spill_width: float = 1.4:
	set(value):
		spill_width = value
		if is_inside_tree():
			generate_spill()

## Sampling step distance in meters along [Curve3D] for geometry.
@export_range(0.05, 1.0, 0.05) var step_distance: float = 0.15:
	set(value):
		step_distance = value
		if is_inside_tree():
			generate_spill()

## Height offset in meters above terrain to eliminate visual z-fighting.
@export_range(0.001, 0.05, 0.002) var surface_offset_y: float = 0.02:
	set(value):
		surface_offset_y = value
		if is_inside_tree():
			generate_spill()

## Automatically computes smooth Bezier handles for curve control points.
@export var auto_smooth_curve: bool = true:
	set(value):
		auto_smooth_curve = value
		if is_inside_tree():
			generate_spill()

@export_category("Ignition & Fire Propagation")
## Preloaded [VolumetricFire] scene instantiated along burning segments.
@export var volumetric_fire_scene: PackedScene
## Distance interval in meters between consecutive spawned fire instances.
@export_range(0.5, 4.0, 0.1) var fire_spacing: float = 1.2
## Height scale multiplier applied to spawned [VolumetricFire] instances.
@export_range(0.5, 3.0, 0.1) var fire_height_multiplier: float = 1.0
## Linear propagation speed of combustion along the curve in meters/sec.
@export var flame_spread_speed: float = 4.0
## Active burning state flag governing fire spread in [method _process].
@export var is_burning: bool = false

## Current outward combustion spread radius in meters from ignition point.
var _burn_radius_meters: float = 0.0
## Normalized 0.0 to 1.0 curve position where initial ignition occurred.
var _ignite_center_uv: float = 0.5
## Arc length in meters along curve where initial ignition occurred.
var _ignite_center_dist: float = 0.0
## Total arc length in meters of the underlying [Curve3D].
var _curve_length: float = 1.0
## Guard flag preventing recursive [signal Curve3D.changed] callbacks.
var _is_updating_curve: bool = false
## Precomputed arc length positions for spawning fire instances.
var _fire_station_distances: PackedFloat32Array = PackedFloat32Array()
## Tracking flags marking which fire stations have already spawned.
var _fire_station_spawned: Array[bool] = []
## List of currently active spawned [VolumetricFire] instances.
var _spawned_fires: Array[Node3D] = []

## Reference to child [MeshInstance3D] displaying the oil puddle ribbon.
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D as MeshInstance3D
## Child [StaticBody3D] registering raycast hits on Layer 3.
@onready var static_body: StaticBody3D = $StaticBody3D as StaticBody3D
## Child [CollisionShape3D] holding the generated concave polygon shape.
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D as CollisionShape3D


## Resolves and returns child [MeshInstance3D] safely across editor reloads.
func _get_mesh_node() -> MeshInstance3D:
	if not is_instance_valid(mesh_instance):
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	return mesh_instance


## Resolves and returns child [StaticBody3D] safely across editor reloads.
func _get_body_node() -> StaticBody3D:
	if not is_instance_valid(static_body):
		static_body = get_node_or_null("StaticBody3D") as StaticBody3D
	return static_body


## Resolves and returns child [CollisionShape3D] safely across reloads.
func _get_shape_node() -> CollisionShape3D:
	if not is_instance_valid(collision_shape):
		collision_shape = get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	return collision_shape


## Binds curve listeners and creates a unique shader material instance.
func _ready() -> void:
	print("OilSpillPath: Initializing oil spill instance.")
	_ensure_curve_listener()

	var mesh_node: MeshInstance3D = _get_mesh_node()
	if is_instance_valid(mesh_node) and mesh_node.material_override:
		mesh_node.material_override = mesh_node.material_override.duplicate()
		mesh_node.material_override.render_priority = 1

	if not Engine.is_editor_hint():
		is_burning = false
		_burn_radius_meters = 0.0

	generate_spill()


## Connects [signal Curve3D.changed] if not already subscribed.
func _ensure_curve_listener() -> void:
	if is_instance_valid(curve):
		if not curve.changed.is_connected(_on_curve_changed):
			curve.changed.connect(_on_curve_changed)


## Auto-calculates smooth cubic Bezier handles for linear curve points.
func _smooth_curve_points() -> void:
	print("OilSpillPath: Auto-smoothing curve control points.")
	if not is_instance_valid(curve) or curve.point_count < 2:
		return

	var count: int = curve.point_count
	for i: int in range(count):
		if not curve.get_point_in(i).is_zero_approx():
			continue
		if not curve.get_point_out(i).is_zero_approx():
			continue

		var prev_p: Vector3 = curve.get_point_position(maxi(0, i - 1))
		var next_p: Vector3 = curve.get_point_position(mini(count - 1, i + 1))
		var tangent: Vector3 = (next_p - prev_p) * 0.25
		curve.set_point_in(i, -tangent)
		curve.set_point_out(i, tangent)


## Advances combustion spread radius and spawns fire along the curve.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if is_instance_valid(curve):
			if not curve.changed.is_connected(_on_curve_changed):
				_ensure_curve_listener()
				generate_spill()
		return

	if not is_burning:
		return

	var spread_speed: float = maxf(flame_spread_speed, 0.05)
	_burn_radius_meters += spread_speed * delta
	var normalized_radius: float = _burn_radius_meters / maxf(_curve_length, 0.001)

	var min_reach: float = _ignite_center_dist - _burn_radius_meters
	var max_reach: float = _ignite_center_dist + _burn_radius_meters

	for i: int in range(_fire_station_distances.size()):
		if not _fire_station_spawned[i]:
			var dist: float = _fire_station_distances[i]
			if dist >= min_reach and dist <= max_reach:
				_fire_station_spawned[i] = true
				_spawn_fire_at_distance(dist)

	var mesh_node: MeshInstance3D = _get_mesh_node()
	if is_instance_valid(mesh_node) and mesh_node.material_override:
		var mat: ShaderMaterial = mesh_node.material_override as ShaderMaterial
		if is_instance_valid(mat):
			mat.set_shader_parameter("burn_radius", normalized_radius)

	if normalized_radius >= 1.5:
		print("OilSpillPath: Combustion complete across path.")
		is_burning = false
		combustion_completed.emit()


## Samples the [Curve3D], rebuilds ribbon mesh, and updates physics.
func generate_spill() -> void:
	if _is_updating_curve:
		return
	if not is_instance_valid(curve) or curve.point_count < 2:
		return

	_is_updating_curve = true
	print("OilSpillPath: Generating puddle geometry along curve.")

	if auto_smooth_curve:
		_smooth_curve_points()

	var safe_step: float = maxf(step_distance, 0.01)
	if not is_equal_approx(curve.bake_interval, safe_step):
		curve.bake_interval = safe_step

	_curve_length = curve.get_baked_length()
	if _curve_length < 0.1:
		_is_updating_curve = false
		return

	_rebuild_fire_stations()

	var baked_points: PackedVector3Array = curve.get_baked_points()
	if baked_points.size() < 2:
		_is_updating_curve = false
		return

	var array_mesh: ArrayMesh = _build_ribbon_mesh(baked_points)
	var mesh_node: MeshInstance3D = _get_mesh_node()
	if is_instance_valid(mesh_node):
		mesh_node.mesh = array_mesh

	_update_collision_shape(array_mesh)
	_is_updating_curve = false


## Precomputes arc length stations for spawning fire instances safely.
func _rebuild_fire_stations() -> void:
	_fire_station_distances.clear()
	_fire_station_spawned.clear()

	var step: float = maxf(fire_spacing, 0.1)
	var accumulated: float = 0.0
	while accumulated <= _curve_length:
		_fire_station_distances.append(accumulated)
		_fire_station_spawned.append(false)
		accumulated += step

	if accumulated - step < _curve_length:
		_fire_station_distances.append(_curve_length)
		_fire_station_spawned.append(false)


## Constructs a smooth UV-mapped quad ribbon [ArrayMesh] along points.
func _build_ribbon_mesh(points: PackedVector3Array) -> ArrayMesh:
	print("OilSpillPath: Building ribbon mesh arrays.")
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var count: int = points.size()
	var half_width: float = spill_width * 0.5
	var accumulated_dist: float = 0.0

	for i: int in range(count):
		var curr_pt: Vector3 = points[i]
		if i > 0:
			accumulated_dist += curr_pt.distance_to(points[i - 1])

		var forward_dir: Vector3 = Vector3.FORWARD
		if i == 0:
			forward_dir = (points[1] - curr_pt).normalized()
		elif i == count - 1:
			forward_dir = (curr_pt - points[i - 1]).normalized()
		else:
			var dir_in: Vector3 = (curr_pt - points[i - 1]).normalized()
			var dir_out: Vector3 = (points[i + 1] - curr_pt).normalized()
			forward_dir = (dir_in + dir_out).normalized()
			if forward_dir.length_squared() < 0.0001:
				forward_dir = dir_out

		var right_dir: Vector3 = forward_dir.cross(Vector3.UP).normalized()
		if right_dir.length_squared() < 0.0001:
			right_dir = Vector3.RIGHT

		var offset_y: Vector3 = Vector3(0.0, surface_offset_y, 0.0)
		var vert_left: Vector3 = curr_pt - (right_dir * half_width) + offset_y
		var vert_right: Vector3 = curr_pt + (right_dir * half_width) + offset_y

		var u_coord: float = clampf(accumulated_dist / maxf(_curve_length, 0.001), 0.0, 1.0)
		vertices.append(vert_left)
		vertices.append(vert_right)
		uvs.append(Vector2(u_coord, 0.0))
		uvs.append(Vector2(u_coord, 1.0))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

		if i > 0:
			var base_idx: int = (i - 1) * 2
			indices.append(base_idx)
			indices.append(base_idx + 2)
			indices.append(base_idx + 1)

			indices.append(base_idx + 1)
			indices.append(base_idx + 2)
			indices.append(base_idx + 3)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Generates a concave polygon collision shape from ribbon geometry.
func _update_collision_shape(mesh: ArrayMesh) -> void:
	print("OilSpillPath: Updating StaticBody3D collision shape.")
	var body_node: StaticBody3D = _get_body_node()
	var shape_node: CollisionShape3D = _get_shape_node()

	if not is_instance_valid(shape_node) or not is_instance_valid(body_node):
		return

	body_node.collision_layer = INTERACTIVE_PHYSICS_LAYER
	body_node.collision_mask = 0

	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape_node.shape = shape


## Spawns a [VolumetricFire] instance at the specified curve distance.
func _spawn_fire_at_distance(dist: float) -> void:
	print("OilSpillPath: Spawning fire along path at distance: ", dist)
	if not is_instance_valid(volumetric_fire_scene):
		return

	var local_pos: Vector3 = curve.sample_baked(dist)
	var fire_node: Node = volumetric_fire_scene.instantiate()
	var fire: VolumetricFire = fire_node as VolumetricFire
	if not is_instance_valid(fire):
		fire_node.queue_free()
		return

	add_child(fire)
	fire.position = local_pos
	# Do NOT overwrite fire.fire_width or fire.fire_height here
	# so it retains its authored dimensions from fire.tscn.
	fire.ignite()
	_spawned_fires.append(fire)


## Weapon damage entrypoint triggering [method ignite] on projectile hit.
func take_damage(_damage: int, hit_pos: Vector3, _shot_dir: Vector3) -> void:
	print("OilSpillPath: Hit received at ", hit_pos, " -> igniting.")
	ignite(hit_pos)


## Starts combustion at closest curve point to the hit coordinates.
func ignite(hit_pos: Vector3 = Vector3.ZERO) -> void:
	print("OilSpillPath: ignite() triggered at position: ", hit_pos)
	if is_burning:
		print("OilSpillPath: Spill is already burning.")
		return

	is_burning = true
	_burn_radius_meters = 0.0
	_fire_station_spawned.fill(false)

	var local_hit: Vector3 = to_local(hit_pos)
	_ignite_center_dist = curve.get_closest_offset(local_hit)
	_ignite_center_uv = clampf(_ignite_center_dist / maxf(_curve_length, 0.001), 0.0, 1.0)

	var mesh_node: MeshInstance3D = _get_mesh_node()
	if is_instance_valid(mesh_node) and mesh_node.material_override:
		var mat: ShaderMaterial = mesh_node.material_override as ShaderMaterial
		if is_instance_valid(mat):
			mat.set_shader_parameter("ignite_center", _ignite_center_uv)
			mat.set_shader_parameter("burn_radius", 0.0)

	ignited.emit(hit_pos)


## Halts combustion and extinguishes all active fire instances.
func extinguish() -> void:
	print("OilSpillPath: extinguish() called.")
	is_burning = false
	_burn_radius_meters = 0.0

	for fire: Node3D in _spawned_fires:
		if is_instance_valid(fire):
			if fire.has_method(&"extinguish"):
				fire.call(&"extinguish")
			fire.queue_free()
	_spawned_fires.clear()

	_fire_station_spawned.fill(false)

	var mesh_node: MeshInstance3D = _get_mesh_node()
	if is_instance_valid(mesh_node) and mesh_node.material_override:
		var mat: ShaderMaterial = mesh_node.material_override as ShaderMaterial
		if is_instance_valid(mat):
			mat.set_shader_parameter("burn_radius", 0.0)


## Editor callback rebuilding geometry when [Curve3D] alters.
func _on_curve_changed() -> void:
	if _is_updating_curve:
		return
	print("OilSpillPath: Curve changed in editor -> regenerating.")
	generate_spill()
