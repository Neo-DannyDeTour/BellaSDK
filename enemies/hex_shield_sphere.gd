@tool
## Goldberg polyhedron energy shield with independent tile hit reactions,
## radial wave propagation, partial directional coverage, and gradual burst fade.
class_name HexShieldSphere
extends StaticBody3D

## Emitted when a tile absorbs damage.
signal shield_hit(current_health: int, max_health: int, hit_pos: Vector3)

## Emitted when shield health reaches zero and the explosion triggers.
signal shield_destroyed

## Physics layer bitmask for Layer 5 (Enemies).
const LAYER_ENEMIES: int = 1 << 4

## Render layer bitmask for Layer 1 (Environment).
const RENDER_LAYER_ENV: int = 1

## Pre-allocated shader instance parameter name for immediate hit flash.
const PARAM_HIT_INTENSITY: StringName = &"hit_intensity"

## Pre-allocated shader instance parameter name for cumulative damage tint.
const PARAM_DAMAGE_RATIO: StringName = &"damage_ratio"

## Pre-allocated shader instance parameter name for tile dissolve alpha.
const PARAM_OPACITY: StringName = &"opacity"

## Pre-allocated property name for deferred collider state mutations.
const PROP_DISABLED: StringName = &"disabled"

@export_category("Shield Resources")
## Shader resource driving hexagon borders, fresnel glow, refraction, and hit tints.
@export var shield_shader: Shader = preload("res://vfx/hex_shield_sphere.gdshader")

@export_category("Shield Configuration")
## Sphere radius in meters.
@export_range(0.5, 20.0, 0.1) var radius: float = 2.0

## Geodesic subdivision level (2 produces 162 tiles: 150 hexagons, 12 pentagons).
@export_range(1, 3, 1) var subdivisions: int = 2

## Fraction of the sphere active around the seed hexagon (0.0 = none, 1.0 = full sphere).
@export_range(0.0, 1.0, 0.01) var coverage: float = 1.0:
	set = set_coverage

## Maximum shield hit points before explosion.
@export var max_health: int = 100

## Total duration in seconds to build the shield outward from the first hexagon.
@export_range(0.1, 5.0, 0.05) var generation_duration: float = 0.85

## Whether to automatically build the shield on [method _ready].
@export var auto_generate: bool = true

## Current health remaining before shield collapse.
var current_health: int = 100

## Shared material assigned across all tile mesh instances.
var _shared_material: ShaderMaterial

## Ordered array of tile mesh instances sorted outward from the seed hexagon.
var _tile_meshes: Array[MeshInstance3D] = []

## Ordered array of per-tile convex collision shapes matching [member _tile_meshes].
var _tile_shapes: Array[CollisionShape3D] = []

## Rest local positions for each tile on the sphere surface.
var _tile_positions: Array[Vector3] = []

## Outward surface normal vectors for each tile.
var _tile_normals: Array[Vector3] = []

## Rest local orientation bases for each tile.
var _tile_bases: Array[Basis] = []

## Active jitter tweens indexed by tile ID so existing tweens are killed before respawn.
var _tile_tweens: Array[Tween] = []

## Master tween controlling sequential shield generation or explosion.
var _master_tween: Tween

## Wave tween scheduling radial red ripple callbacks across visible tiles.
var _wave_tween: Tween

## Visibility gate preventing off-screen jitter tween allocations.
var _screen_notifier: VisibleOnScreenNotifier3D

## Flag preventing further damage once health reaches zero.
var _is_destroyed: bool = false


## Initializes collision layers, builds dual geodesic tiles, and activates shield.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(radius > 0.0 and max_health > 0)

	collision_layer = LAYER_ENEMIES
	collision_mask = 0
	current_health = max_health

	_shared_material = ShaderMaterial.new()
	_shared_material.shader = shield_shader

	# Clear existing children if re-entering tree in editor
	for child: Node in get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			child.queue_free()

	_screen_notifier = VisibleOnScreenNotifier3D.new()
	_screen_notifier.aabb = AABB(
		Vector3(-radius, -radius, -radius), Vector3(radius * 2.0, radius * 2.0, radius * 2.0)
	)
	add_child(_screen_notifier)

	_build_polyhedron_tiles()

	if Engine.is_editor_hint():
		_apply_coverage_immediate()
		return

	if auto_generate:
		generate_shield()
	else:
		_apply_coverage_immediate()


## Updates active tile count and collision state for partial or full sphere display.
func set_coverage(value: float) -> void:
	coverage = clampf(value, 0.0, 1.0)
	if not is_inside_tree() or _tile_meshes.is_empty() or _is_destroyed:
		return
	print("HexShield: Coverage updated to ", coverage)
	_apply_coverage_immediate()


## Animates shield construction starting from one seed hexagon and building outward.
func generate_shield() -> void:
	if _is_destroyed or _tile_meshes.is_empty():
		return

	print("HexShield: Starting outward generation from seed hexagon.")
	if is_instance_valid(_master_tween):
		_master_tween.kill()
	if is_instance_valid(_wave_tween):
		_wave_tween.kill()

	var total_count: int = _tile_meshes.size()
	var active_count: int = roundi(float(total_count) * coverage)

	for i: int in range(total_count):
		var kill_tw: Tween = _tile_tweens[i]
		if is_instance_valid(kill_tw):
			kill_tw.kill()
		var mesh_inst: MeshInstance3D = _tile_meshes[i]
		mesh_inst.visible = false
		mesh_inst.scale = Vector3.ONE * 0.001
		mesh_inst.position = _tile_positions[i]
		mesh_inst.basis = _tile_bases[i]
		mesh_inst.set_instance_shader_parameter(PARAM_OPACITY, 1.0)
		_tile_shapes[i].set_deferred(PROP_DISABLED, true)

	if active_count <= 0:
		return

	_master_tween = create_tween()
	var step_delay: float = generation_duration / float(maxi(active_count, 1))

	for i: int in range(active_count):
		var start_time: float = float(i) * step_delay
		_master_tween.parallel().tween_callback(_spawn_single_tile.bind(i)).set_delay(start_time)


## Processes incoming weapon or projectile hits, jittering impact tile and rippling wave.
func take_damage(
	amount: int, hit_pos: Vector3 = Vector3.ZERO, _shot_dir: Vector3 = Vector3.FORWARD
) -> void:
	if _is_destroyed or amount <= 0:
		return

	current_health = maxi(current_health - amount, 0)
	var dmg_ratio: float = 1.0 - (float(current_health) / float(max_health))
	var hit_index: int = _find_closest_active_tile(hit_pos)

	print(
		"HexShield: Tile ",
		hit_index,
		" took ",
		amount,
		" damage. Health: ",
		current_health,
		"/",
		max_health
	)

	if hit_index >= 0:
		_trigger_tile_jitter(hit_index, dmg_ratio)
		_propagate_hit_wave(hit_index, dmg_ratio)

	shield_hit.emit(current_health, max_health, hit_pos)

	if current_health <= 0:
		_explode_shield()


## Immediately syncs tile visibility and physics colliders to [member coverage].
func _apply_coverage_immediate() -> void:
	var total_count: int = _tile_meshes.size()
	var active_count: int = roundi(float(total_count) * coverage)

	for i: int in range(total_count):
		var is_active: bool = i < active_count
		var mesh_inst: MeshInstance3D = _tile_meshes[i]
		mesh_inst.visible = is_active
		mesh_inst.scale = Vector3.ONE if is_active else Vector3.ONE * 0.001
		mesh_inst.position = _tile_positions[i]
		mesh_inst.basis = _tile_bases[i]
		mesh_inst.set_instance_shader_parameter(PARAM_OPACITY, 1.0)
		_tile_shapes[i].set_deferred(PROP_DISABLED, not is_active)


## Activates and animates a single tile popping into place during generation.
func _spawn_single_tile(tile_idx: int) -> void:
	if _is_destroyed or tile_idx < 0 or tile_idx >= _tile_meshes.size():
		return

	var mesh_inst: MeshInstance3D = _tile_meshes[tile_idx]
	var shape_node: CollisionShape3D = _tile_shapes[tile_idx]
	mesh_inst.visible = true
	shape_node.set_deferred(PROP_DISABLED, false)
	mesh_inst.set_instance_shader_parameter(PARAM_OPACITY, 1.0)
	mesh_inst.set_instance_shader_parameter(PARAM_HIT_INTENSITY, 0.85)

	var prev_tween: Tween = _tile_tweens[tile_idx]
	if is_instance_valid(prev_tween):
		prev_tween.kill()

	var tw: Tween = create_tween().set_parallel(true)
	_tile_tweens[tile_idx] = tw
	(
		tw
		. tween_property(mesh_inst, "scale", Vector3.ONE, 0.18)
		. from(Vector3.ONE * 0.001)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_method(
		func(val: float) -> void:
			if is_instance_valid(mesh_inst):
				mesh_inst.set_instance_shader_parameter(PARAM_HIT_INTENSITY, val),
		0.85,
		0.0,
		0.25
	)


## Locates the nearest visible tile to a world-space impact point using squared distance.
func _find_closest_active_tile(world_hit_pos: Vector3) -> int:
	var local_hit: Vector3 = to_local(world_hit_pos)
	var best_idx: int = -1
	var best_dist_sq: float = INF

	for i: int in range(_tile_meshes.size()):
		if not _tile_meshes[i].visible:
			continue
		var dist_sq: float = _tile_positions[i].distance_squared_to(local_hit)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_idx = i

	return best_idx


## Jitters an impacted tile along its normal and flashes its shader from blue to red.
func _trigger_tile_jitter(tile_idx: int, global_damage_ratio: float) -> void:
	var mesh_inst: MeshInstance3D = _tile_meshes[tile_idx]
	mesh_inst.set_instance_shader_parameter(PARAM_DAMAGE_RATIO, global_damage_ratio)
	mesh_inst.set_instance_shader_parameter(PARAM_HIT_INTENSITY, 1.0)

	if is_instance_valid(_screen_notifier) and not _screen_notifier.is_on_screen():
		return

	var existing_tween: Tween = _tile_tweens[tile_idx]
	if is_instance_valid(existing_tween):
		existing_tween.kill()

	var base_pos: Vector3 = _tile_positions[tile_idx]
	var normal: Vector3 = _tile_normals[tile_idx]
	var base_basis: Basis = _tile_bases[tile_idx]
	var tilt_axis: Vector3 = base_basis.x

	var tw: Tween = create_tween()
	_tile_tweens[tile_idx] = tw

	tw.tween_property(mesh_inst, "position", base_pos - (normal * 0.11), 0.035).set_trans(
		Tween.TRANS_SINE
	)
	tw.parallel().tween_property(mesh_inst, "basis", base_basis.rotated(tilt_axis, 0.16), 0.035)
	tw.parallel().tween_property(mesh_inst, "scale", Vector3.ONE * 0.88, 0.035)

	tw.tween_property(mesh_inst, "position", base_pos + (normal * 0.07), 0.045).set_trans(
		Tween.TRANS_SINE
	)
	tw.parallel().tween_property(mesh_inst, "basis", base_basis.rotated(tilt_axis, -0.12), 0.045)
	tw.parallel().tween_property(mesh_inst, "scale", Vector3.ONE * 1.06, 0.045)

	(
		tw
		. tween_property(mesh_inst, "position", base_pos, 0.12)
		. set_trans(Tween.TRANS_ELASTIC)
		. set_ease(Tween.EASE_OUT)
	)
	tw.parallel().tween_property(mesh_inst, "basis", base_basis, 0.12)
	tw.parallel().tween_property(mesh_inst, "scale", Vector3.ONE, 0.12)
	tw.parallel().tween_method(
		func(val: float) -> void:
			if is_instance_valid(mesh_inst):
				mesh_inst.set_instance_shader_parameter(PARAM_HIT_INTENSITY, val),
		1.0,
		0.0,
		0.32
	)


## Schedules a radial red energy wave across all visible non-impacted tiles.
func _propagate_hit_wave(origin_idx: int, global_damage_ratio: float) -> void:
	if is_instance_valid(_wave_tween):
		_wave_tween.kill()

	var origin_pos: Vector3 = _tile_positions[origin_idx]
	var wave_speed: float = radius * 3.5
	var total_count: int = _tile_meshes.size()

	if is_instance_valid(_screen_notifier) and not _screen_notifier.is_on_screen():
		for i: int in range(total_count):
			if _tile_meshes[i].visible:
				_tile_meshes[i].set_instance_shader_parameter(
					PARAM_DAMAGE_RATIO, global_damage_ratio
				)
		return

	_wave_tween = create_tween().set_parallel(true)

	for i: int in range(total_count):
		if i == origin_idx or not _tile_meshes[i].visible:
			continue
		var dist_sq: float = _tile_positions[i].distance_squared_to(origin_pos)
		var delay: float = sqrt(dist_sq) / wave_speed
		_wave_tween.tween_callback(_pulse_wave_tile.bind(i, global_damage_ratio)).set_delay(delay)


## Flashes and micro-pulses a single tile when the radial hit wave reaches it.
func _pulse_wave_tile(tile_idx: int, global_damage_ratio: float) -> void:
	if _is_destroyed or tile_idx < 0 or tile_idx >= _tile_meshes.size():
		return

	var mesh_inst: MeshInstance3D = _tile_meshes[tile_idx]
	if not mesh_inst.visible:
		return

	mesh_inst.set_instance_shader_parameter(PARAM_DAMAGE_RATIO, global_damage_ratio)
	mesh_inst.set_instance_shader_parameter(PARAM_HIT_INTENSITY, 0.85)

	var existing_tween: Tween = _tile_tweens[tile_idx]
	if is_instance_valid(existing_tween):
		existing_tween.kill()

	var base_pos: Vector3 = _tile_positions[tile_idx]
	var normal: Vector3 = _tile_normals[tile_idx]

	var tw: Tween = create_tween()
	_tile_tweens[tile_idx] = tw

	(
		tw
		. tween_property(mesh_inst, "position", base_pos + (normal * 0.035), 0.04)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(mesh_inst, "position", base_pos, 0.14).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	tw.parallel().tween_method(
		func(val: float) -> void:
			if is_instance_valid(mesh_inst):
				mesh_inst.set_instance_shader_parameter(PARAM_HIT_INTENSITY, val),
		0.85,
		0.0,
		0.26
	)


## Disables all colliders, blasts tiles outward while fading opacity, and frees node.
func _explode_shield() -> void:
	_is_destroyed = true
	print("HexShield: Health reached 0 -> exploding shield.")
	shield_destroyed.emit()

	if is_instance_valid(_master_tween):
		_master_tween.kill()
	if is_instance_valid(_wave_tween):
		_wave_tween.kill()

	for i: int in range(_tile_shapes.size()):
		_tile_shapes[i].set_deferred(PROP_DISABLED, true)
		var active_tw: Tween = _tile_tweens[i]
		if is_instance_valid(active_tw):
			active_tw.kill()

	_master_tween = create_tween().set_parallel(true)
	var has_visible_tiles: bool = false

	for i: int in range(_tile_meshes.size()):
		var mesh_inst: MeshInstance3D = _tile_meshes[i]
		if not mesh_inst.visible:
			continue
		has_visible_tiles = true
		mesh_inst.set_instance_shader_parameter(PARAM_HIT_INTENSITY, 1.0)
		mesh_inst.set_instance_shader_parameter(PARAM_DAMAGE_RATIO, 1.0)
		mesh_inst.set_instance_shader_parameter(PARAM_OPACITY, 1.0)

		var normal: Vector3 = _tile_normals[i]
		var blast_dist: float = radius * randf_range(0.85, 1.65)
		var target_pos: Vector3 = _tile_positions[i] + (normal * blast_dist)
		var spin_basis: Basis = (
			_tile_bases[i]
			. rotated(_tile_bases[i].x, randf_range(-2.6, 2.6))
			. rotated(_tile_bases[i].y, randf_range(-2.6, 2.6))
		)

		(
			_master_tween
			. tween_property(mesh_inst, "position", target_pos, 1.1)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		_master_tween.tween_property(mesh_inst, "basis", spin_basis, 1.1)
		(
			_master_tween
			. tween_property(mesh_inst, "scale", Vector3.ONE * 0.65, 1.1)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_master_tween
			. tween_method(
				func(val: float) -> void:
					if is_instance_valid(mesh_inst):
						mesh_inst.set_instance_shader_parameter(PARAM_OPACITY, val),
				1.0,
				0.0,
				0.75
			)
			. set_delay(0.35)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN)
		)

	if has_visible_tiles:
		_master_tween.chain().tween_callback(queue_free)
	else:
		queue_free()


## Constructs the subdivided icosahedron dual and spawns child meshes and colliders.
func _build_polyhedron_tiles() -> void:
	var phi: float = (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [
		Vector3(-1.0, phi, 0.0).normalized(),
		Vector3(1.0, phi, 0.0).normalized(),
		Vector3(-1.0, -phi, 0.0).normalized(),
		Vector3(1.0, -phi, 0.0).normalized(),
		Vector3(0.0, -1.0, phi).normalized(),
		Vector3(0.0, 1.0, phi).normalized(),
		Vector3(0.0, -1.0, -phi).normalized(),
		Vector3(0.0, 1.0, -phi).normalized(),
		Vector3(phi, 0.0, -1.0).normalized(),
		Vector3(phi, 0.0, 1.0).normalized(),
		Vector3(-phi, 0.0, -1.0).normalized(),
		Vector3(-phi, 0.0, 1.0).normalized()
	]

	var faces: PackedInt32Array = PackedInt32Array(
		[
			0,
			11,
			5,
			0,
			5,
			1,
			0,
			1,
			7,
			0,
			7,
			10,
			0,
			10,
			11,
			1,
			5,
			9,
			5,
			11,
			4,
			11,
			10,
			2,
			10,
			7,
			6,
			7,
			1,
			8,
			3,
			9,
			4,
			3,
			4,
			2,
			3,
			2,
			6,
			3,
			6,
			8,
			3,
			8,
			9,
			4,
			9,
			5,
			2,
			4,
			11,
			6,
			2,
			10,
			8,
			6,
			7,
			9,
			8,
			1
		]
	)

	for step: int in range(subdivisions):
		var mid_cache: Dictionary[int, int] = {}
		var next_faces: PackedInt32Array = PackedInt32Array()
		var tri_count: int = floori(float(faces.size()) / 3.0)
		for t: int in range(tri_count):
			var i0: int = faces[t * 3]
			var i1: int = faces[t * 3 + 1]
			var i2: int = faces[t * 3 + 2]

			var m01: int = _get_midpoint_index(i0, i1, verts, mid_cache)
			var m12: int = _get_midpoint_index(i1, i2, verts, mid_cache)
			var m20: int = _get_midpoint_index(i2, i0, verts, mid_cache)

			next_faces.append_array([i0, m01, m20])
			next_faces.append_array([i1, m12, m01])
			next_faces.append_array([i2, m20, m12])
			next_faces.append_array([m01, m12, m20])
		faces = next_faces

	_align_first_hexagon_to_forward(verts)

	var vert_count: int = verts.size()
	var incident_centroids: Array[PackedVector3Array] = []
	incident_centroids.resize(vert_count)
	for i: int in range(vert_count):
		incident_centroids[i] = PackedVector3Array()

	var final_tri_count: int = floori(float(faces.size()) / 3.0)
	for t: int in range(final_tri_count):
		var a: int = faces[t * 3]
		var b: int = faces[t * 3 + 1]
		var c: int = faces[t * 3 + 2]
		var centroid: Vector3 = ((verts[a] + verts[b] + verts[c]) / 3.0).normalized()
		incident_centroids[a].append(centroid)
		incident_centroids[b].append(centroid)
		incident_centroids[c].append(centroid)

	var order: Array[int] = []
	order.resize(vert_count)
	for i: int in range(vert_count):
		order[i] = i

	order.sort_custom(
		func(idx_a: int, idx_b: int) -> bool:
			var dist_a: float = verts[idx_a].distance_squared_to(Vector3.FORWARD)
			var dist_b: float = verts[idx_b].distance_squared_to(Vector3.FORWARD)
			return dist_a < dist_b
	)

	for sorted_idx: int in order:
		var normal: Vector3 = verts[sorted_idx]
		var corners: Array[Vector3] = []
		corners.assign(incident_centroids[sorted_idx])
		_create_tile_node(normal, corners)


## Rotates the vertex cloud so a 6-sided hexagon sits directly at [constant Vector3.FORWARD].
func _align_first_hexagon_to_forward(verts: Array[Vector3]) -> void:
	var best_hex_idx: int = 12 if verts.size() > 12 else 0
	var best_dist_sq: float = INF

	for i: int in range(best_hex_idx, verts.size()):
		var d_sq: float = verts[i].distance_squared_to(Vector3.FORWARD)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_hex_idx = i

	var from_dir: Vector3 = verts[best_hex_idx]
	var axis: Vector3 = from_dir.cross(Vector3.FORWARD)
	if axis.length_squared() > 0.00001:
		var angle: float = from_dir.angle_to(Vector3.FORWARD)
		var rot_basis: Basis = Basis(axis.normalized(), angle)
		for i: int in range(verts.size()):
			verts[i] = (rot_basis * verts[i]).normalized()


## Returns or creates the normalized midpoint vertex index between two edge vertices.
func _get_midpoint_index(
	idx_a: int, idx_b: int, verts: Array[Vector3], cache: Dictionary[int, int]
) -> int:
	var low: int = mini(idx_a, idx_b)
	var high: int = maxi(idx_a, idx_b)
	var edge_key: int = (low << 16) | high
	if cache.has(edge_key):
		return cache[edge_key]

	var mid: Vector3 = ((verts[idx_a] + verts[idx_b]) * 0.5).normalized()
	var new_idx: int = verts.size()
	verts.append(mid)
	cache[edge_key] = new_idx
	return new_idx


## Builds a single tile [MeshInstance3D] and [CollisionShape3D] from its dual corners.
func _create_tile_node(normal: Vector3, raw_corners: Array[Vector3]) -> void:
	var up_ref: Vector3 = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var tile_basis: Basis = Basis.looking_at(-normal, up_ref)
	var inv_basis: Basis = tile_basis.inverse()
	var tile_center: Vector3 = normal * radius

	var sorted_corners: Array[Vector3] = raw_corners.duplicate()
	sorted_corners.sort_custom(
		func(ca: Vector3, cb: Vector3) -> bool:
			var la: Vector3 = inv_basis * (ca - normal)
			var lb: Vector3 = inv_basis * (cb - normal)
			return atan2(la.y, la.x) < atan2(lb.y, lb.x)
	)

	var corner_count: int = sorted_corners.size()
	var local_corners: PackedVector3Array = PackedVector3Array()
	local_corners.resize(corner_count)
	for i: int in range(corner_count):
		var world_pt: Vector3 = sorted_corners[i] * radius
		local_corners[i] = inv_basis * (world_pt - tile_center)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var out_normal: Vector3 = Vector3(0.0, 0.0, 1.0)

	for i: int in range(corner_count):
		var next_i: int = (i + 1) % corner_count
		st.set_normal(out_normal)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(Vector3.ZERO)

		st.set_normal(out_normal)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(local_corners[i])

		st.set_normal(out_normal)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(local_corners[next_i])

	var array_mesh: ArrayMesh = st.commit()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = array_mesh
	mesh_inst.material_override = _shared_material
	mesh_inst.layers = RENDER_LAYER_ENV
	mesh_inst.position = tile_center
	mesh_inst.basis = tile_basis
	mesh_inst.set_instance_shader_parameter(PARAM_OPACITY, 1.0)
	add_child(mesh_inst)

	var hull_points: PackedVector3Array = PackedVector3Array()
	for i: int in range(corner_count):
		var pt: Vector3 = local_corners[i]
		hull_points.append(pt + Vector3(0.0, 0.0, 0.04))
		hull_points.append(pt - Vector3(0.0, 0.0, 0.04))

	var convex_shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	convex_shape.points = hull_points

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.shape = convex_shape
	col_shape.position = tile_center
	col_shape.basis = tile_basis
	add_child(col_shape)

	_tile_meshes.append(mesh_inst)
	_tile_shapes.append(col_shape)
	_tile_positions.append(tile_center)
	_tile_normals.append(normal)
	_tile_bases.append(tile_basis)
	_tile_tweens.append(null)
