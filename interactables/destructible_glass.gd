@tool
## Dual-mode glass pane supporting localized Voronoi shattering and armored crack-only impacts.
class_name DestructibleGlass
extends Node3D

## Emitted when glass takes non-lethal or armored impact and updates fracture state.
signal glass_cracked(impact_uv: Vector2, intensity: float)

## Emitted when breakable glass is breached and shards break out.
signal glass_broken(hit_position: Vector3, hit_direction: Vector3)

## Operating modes for glass durability and visual wire reinforcement.
enum GlassMode { BREAKABLE, ARMORED }

## Per-instance shader uniform toggling embedded armored wire cage [0.0 or 1.0].
const PARAM_IS_ARMORED: StringName = &"is_armored"

## Per-instance shader uniform controlling crack propagation [0.0..1.0].
const PARAM_CRACK_INTENSITY: StringName = &"crack_intensity"

## Per-instance shader uniform storing normalized UV coordinates of impact.
const PARAM_IMPACT_UV: StringName = &"impact_uv"

## Per-instance shader uniform reading per-shard crack state from vertex COLOR.
const PARAM_USE_VERTEX_CRACK: StringName = &"use_vertex_crack"

## Half-thickness of glass physics colliders in meters.
const GLASS_HALF_THICKNESS: float = 0.02

## Maximum falling [RigidBody3D] debris pieces spawned per fracture event.
const MAX_DEBRIS_PER_HIT: int = 12

## Lifetime in seconds before detached falling shard debris is freed.
const DEBRIS_LIFETIME_SEC: float = 2.5

## Controls whether glass can shatter (BREAKABLE) or only crack (ARMORED).
@export var mode: GlassMode = GlassMode.BREAKABLE:
	set(value):
		mode = value
		if is_inside_tree():
			_sync_mode_uniform()

## Dimensions of the glass pane in world units.
@export var size: Vector2 = Vector2(1.5, 2.0):
	set(value):
		size = value.clamp(Vector2(0.1, 0.1), Vector2(16.0, 16.0))
		if is_inside_tree():
			_resize_resources()

## Hit points before a BREAKABLE glass pane breaches on first hit.
@export_range(1.0, 500.0, 1.0) var max_health: float = 50.0:
	set(value):
		max_health = value
		if _health > max_health:
			_health = max_health

## Base radius in meters of the hole punched by a breakable impact.
@export_range(0.1, 2.0, 0.05) var break_radius: float = 0.32

## Minimum colliding body speed (m/s) required to damage BREAKABLE glass on impact.
@export_range(0.5, 50.0, 0.5) var impact_break_speed: float = 8.0

## Optional 3D sound effect played when glass cracks.
@export var crack_sfx: AudioStream = null

## Optional 3D sound effect played when BREAKABLE glass shatters.
@export var break_sfx: AudioStream = null

## Current remaining health for BREAKABLE glass before initial breach.
var _health: float = 50.0

## True once BREAKABLE glass has been breached (at least one hole punched).
var _is_broken: bool = false

## True once pane has been subdivided into Voronoi shards.
var _is_subdivided: bool = false

## Current normalized fracture intensity in range [0.0, 1.0] for intact quad.
var _crack_intensity: float = 0.0

## Current normalized UV coordinates of the latest impact point.
var _impact_uv: Vector2 = Vector2(0.5, 0.5)

## Active [Tween] interpolating intact fracture shader parameter.
var _crack_tween: Tween = null

## Single batched [MeshInstance3D] rendering all surviving Voronoi shards.
var _shards_mesh_inst: MeshInstance3D = null

## Cached base glass material shared across merged shard and debris meshes.
var _shards_base_mat: Material = null

## Generated Voronoi shard records; each entry is a typed Dictionary.
var _shards: Array[Dictionary] = []

## Quad mesh instance rendering the intact transparent/armored glass shader.
@onready var _glass_quad: MeshInstance3D = $Quad as MeshInstance3D

## Static physics body owning intact and per-shard collision shapes.
@onready var _glass_body: StaticBody3D = $GlassBody as StaticBody3D

## Box collider shape on the intact static glass body.
@onready var _collision_shape: CollisionShape3D = $GlassBody/CollisionShape3D as CollisionShape3D

## Area3D detecting fast-moving physics bodies or dashing players.
@onready var _impact_area: Area3D = $ImpactArea as Area3D

## Box collider shape on [member _impact_area].
@onready var _impact_shape: CollisionShape3D = $ImpactArea/CollisionShape3D as CollisionShape3D

## One-shot GPU particle emitter for glass shatter debris.
@onready var _shard_particles: GPUParticles3D = $ShardParticles as GPUParticles3D


## Validates child nodes, initializes health/uniforms, and disables per-frame processing.
func _ready() -> void:
	assert(is_instance_valid(_glass_quad), "DestructibleGlass: missing Quad MeshInstance3D")
	assert(is_instance_valid(_glass_body), "DestructibleGlass: missing GlassBody StaticBody3D")
	assert(is_instance_valid(_collision_shape), "DestructibleGlass: missing CollisionShape3D")
	assert(is_instance_valid(_impact_area), "DestructibleGlass: missing ImpactArea")
	assert(is_instance_valid(_impact_shape), "DestructibleGlass: missing ImpactShape")
	assert(is_instance_valid(_shard_particles), "DestructibleGlass: missing ShardParticles")

	_health = max_health
	_resize_resources()
	_sync_mode_uniform()
	_glass_quad.set_instance_shader_parameter(PARAM_CRACK_INTENSITY, _crack_intensity)
	_glass_quad.set_instance_shader_parameter(PARAM_IMPACT_UV, _impact_uv)

	set_process(false)
	set_physics_process(false)

	if Engine.is_editor_hint():
		return

	Utilities.safe_connect(_impact_area.body_entered, _on_impact_body_entered)


## Disconnects area signals and kills active [Tween] on tree exit.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_crack_tween)
	if not Engine.is_editor_hint() and is_instance_valid(_impact_area):
		if _impact_area.body_entered.is_connected(_on_impact_body_entered):
			_impact_area.body_entered.disconnect(_on_impact_body_entered)


## Returns true once this BREAKABLE glass pane has been breached.
func is_broken() -> bool:
	return _is_broken


## Returns count of surviving intact/cracked shards if subdivided, else 1 if unbroken.
func get_alive_shard_count() -> int:
	if not _is_subdivided:
		return 0 if _is_broken else 1
	var count: int = 0
	for shard: Dictionary in _shards:
		if bool(shard.get(&"alive", false)):
			count += 1
	return count


## Routes weapon, melee, or impact damage into crack propagation or localized shattering.
func take_damage(
	amount: float, hit_position: Vector3 = Vector3.ZERO, hit_dir: Vector3 = Vector3.ZERO
) -> void:
	var impact_pos: Vector3 = (
		global_position if hit_position.is_equal_approx(Vector3.ZERO) else hit_position
	)
	var delta_intensity: float = clampf(amount / maxf(max_health, 1.0), 0.15, 0.55)

	if mode == GlassMode.ARMORED:
		apply_impact(impact_pos, delta_intensity)
		return

	if _is_subdivided:
		if get_alive_shard_count() <= 0:
			return
		var hit_radius: float = _compute_hit_radius(amount)
		_fracture_at(impact_pos, hit_dir, hit_radius)
		return

	_health = maxf(_health - amount, 0.0)
	if _health <= 0.0:
		var breach_radius: float = _compute_hit_radius(amount)
		_fracture_at(impact_pos, hit_dir, breach_radius)
	else:
		apply_impact(impact_pos, delta_intensity)


## Applies localized Voronoi fracture at [param world_pos] without breaking the pane.
func apply_impact(world_pos: Vector3, intensity_delta: float = 0.35) -> void:
	if _is_broken or not is_instance_valid(_glass_quad):
		return
	var local_hit: Vector3 = _glass_quad.to_local(world_pos)
	_impact_uv = _local_to_uv(Vector2(local_hit.x, local_hit.y))
	var target_crack: float = clampf(_crack_intensity + intensity_delta, 0.0, 1.0)

	_glass_quad.set_instance_shader_parameter(PARAM_IMPACT_UV, _impact_uv)
	_crack_tween = Utilities.reset_tween_ext(self, _crack_tween, Tween.TRANS_EXPO, Tween.EASE_OUT)
	if is_instance_valid(_crack_tween):
		_crack_tween.tween_method(_set_crack_level, _crack_intensity, target_crack, 0.18)
	_crack_intensity = target_crack

	if is_instance_valid(crack_sfx) and not Engine.is_editor_hint():
		AudioPool.play_sfx_3d(crack_sfx, world_pos)

	print("DestructibleGlass: cracked mode=", mode, " uv=", _impact_uv, " crack=", _crack_intensity)
	glass_cracked.emit(_impact_uv, _crack_intensity)


## Breaches a BREAKABLE glass pane at [param hit_position], punching a localized Voronoi hole.
func shatter(hit_position: Vector3 = Vector3.ZERO, hit_dir: Vector3 = Vector3.ZERO) -> void:
	if mode == GlassMode.ARMORED:
		return
	var impact_pos: Vector3 = (
		global_position if hit_position.is_equal_approx(Vector3.ZERO) else hit_position
	)
	_fracture_at(impact_pos, hit_dir, break_radius)


## Restores glass pane to intact, uncracked state and clears any Voronoi shards.
func repair_glass() -> void:
	Utilities.safe_kill_tween(_crack_tween)
	_clear_shards()
	_is_broken = false
	_is_subdivided = false
	_health = max_health
	_crack_intensity = 0.0
	if is_instance_valid(_glass_quad):
		_glass_quad.visible = true
		_glass_quad.set_instance_shader_parameter(PARAM_CRACK_INTENSITY, 0.0)
	if is_instance_valid(_collision_shape):
		_collision_shape.set_deferred(&"disabled", false)
	if is_instance_valid(_impact_area):
		_impact_area.set_deferred(&"monitoring", true)
	print("DestructibleGlass: repaired")


## Syncs [member mode] to the per-instance shader uniform on intact quad and merged shards.
func _sync_mode_uniform() -> void:
	var armored_val: float = 1.0 if mode == GlassMode.ARMORED else 0.0
	if is_instance_valid(_glass_quad):
		_glass_quad.set_instance_shader_parameter(PARAM_IS_ARMORED, armored_val)
	if is_instance_valid(_shards_mesh_inst):
		_shards_mesh_inst.set_instance_shader_parameter(PARAM_IS_ARMORED, armored_val)


## Resizes quad mesh, physics shapes, and particle emission bounds to match [member size].
func _resize_resources() -> void:
	if is_instance_valid(_glass_quad):
		var quad_mesh: QuadMesh = _glass_quad.mesh as QuadMesh
		if is_instance_valid(quad_mesh):
			quad_mesh.size = size
	if is_instance_valid(_collision_shape):
		var box: BoxShape3D = _collision_shape.shape as BoxShape3D
		if is_instance_valid(box):
			box.size = Vector3(size.x, size.y, GLASS_HALF_THICKNESS * 2.0)
	if is_instance_valid(_impact_shape):
		var impact_box: BoxShape3D = _impact_shape.shape as BoxShape3D
		if is_instance_valid(impact_box):
			impact_box.size = Vector3(size.x, size.y, 0.14)
	if is_instance_valid(_shard_particles):
		var proc_mat: ParticleProcessMaterial = (
			_shard_particles.process_material as ParticleProcessMaterial
		)
		if is_instance_valid(proc_mat):
			proc_mat.emission_box_extents = Vector3(size.x * 0.5, size.y * 0.5, 0.02)


## Callback for [Tween] interpolation of per-instance shader fracture uniform.
func _set_crack_level(val: float) -> void:
	if is_instance_valid(_glass_quad):
		_glass_quad.set_instance_shader_parameter(PARAM_CRACK_INTENSITY, val)


## Breaks or cracks glass when a fast-moving physics body collides with [member _impact_area].
func _on_impact_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var speed: float = 0.0
	var vel: Vector3 = Vector3.ZERO
	if body is RigidBody3D:
		var rb: RigidBody3D = body as RigidBody3D
		vel = rb.linear_velocity
		speed = vel.length()
	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body as CharacterBody3D
		vel = cb.velocity
		speed = vel.length()

	if speed < impact_break_speed:
		return

	if _is_subdivided:
		var local_hit_3d: Vector3 = _glass_quad.to_local(body.global_position)
		var local_hit: Vector2 = Vector2(local_hit_3d.x, local_hit_3d.y)
		if not _has_alive_shard_near(local_hit, break_radius + 0.15):
			return

	var dmg: float = max_health if mode == GlassMode.BREAKABLE else 35.0
	take_damage(dmg, body.global_position, vel.normalized())


## Computes hole radius scaled by incoming damage relative to [member max_health].
func _compute_hit_radius(amount: float) -> float:
	var scale_factor: float = clampf(amount / maxf(max_health, 1.0), 0.7, 1.5)
	var max_allowed: float = maxf(minf(size.x, size.y) * 0.45, 0.12)
	return clampf(break_radius * scale_factor, 0.12, max_allowed)


## Converts local XY coordinates on the pane into normalized shader UV coordinates.
func _local_to_uv(local_xy: Vector2) -> Vector2:
	var uv_x: float = clampf((local_xy.x / maxf(size.x, 0.001)) + 0.5, 0.05, 0.95)
	var uv_y: float = clampf(0.5 - (local_xy.y / maxf(size.y, 0.001)), 0.05, 0.95)
	return Vector2(uv_x, uv_y)


## Checks whether any surviving shard center or vertex is within [param radius] of [param xy].
func _has_alive_shard_near(xy: Vector2, radius: float) -> bool:
	var r_sq: float = radius * radius
	for shard: Dictionary in _shards:
		if not bool(shard.get(&"alive", false)):
			continue
		var center_raw: Variant = shard.get(&"center", Vector2.ZERO)
		var center: Vector2 = center_raw if center_raw is Vector2 else Vector2.ZERO
		if center.distance_squared_to(xy) <= r_sq:
			return true
	return false


## Subdivides pane if needed, punches hole at [param world_pos], cracks neighbors, drops islands.
func _fracture_at(world_pos: Vector3, hit_dir: Vector3, hit_radius: float) -> void:
	var local_3d: Vector3 = _glass_quad.to_local(world_pos)
	var local_xy: Vector2 = Vector2(
		clampf(local_3d.x, -size.x * 0.5, size.x * 0.5),
		clampf(local_3d.y, -size.y * 0.5, size.y * 0.5)
	)
	var first_breach: bool = not _is_broken
	_is_broken = true
	Utilities.safe_kill_tween(_crack_tween)

	if not _is_subdivided:
		_subdivide_into_shards(local_xy)

	var broken_indices: Array[int] = _collect_hit_shards(local_xy, hit_radius)
	if broken_indices.is_empty():
		return

	for idx: int in broken_indices:
		_shards[idx][&"alive"] = false

	var detached_indices: Array[int] = _collect_floating_shards()
	for idx: int in detached_indices:
		_shards[idx][&"alive"] = false
		broken_indices.append(idx)

	var debris_budget: int = MAX_DEBRIS_PER_HIT
	var impulse_dir: Vector3 = (
		-global_transform.basis.z if hit_dir.is_equal_approx(Vector3.ZERO) else hit_dir.normalized()
	)
	for idx: int in broken_indices:
		var spawn_debris: bool = debris_budget > 0 and not Engine.is_editor_hint()
		if spawn_debris:
			debris_budget -= 1
		_remove_shard(idx, spawn_debris, impulse_dir)

	_apply_radial_cracks(local_xy, hit_radius * 2.5)
	_rebuild_merged_shards_mesh()

	if get_alive_shard_count() <= 0 and is_instance_valid(_impact_area):
		_impact_area.set_deferred(&"monitoring", false)

	if is_instance_valid(_shard_particles) and not Engine.is_editor_hint():
		_shard_particles.restart()
	if is_instance_valid(break_sfx) and not Engine.is_editor_hint():
		AudioPool.play_sfx_3d(break_sfx, world_pos)

	print("DestructibleGlass: fractured ", broken_indices.size(), " shards at ", world_pos)
	if first_breach:
		glass_broken.emit(world_pos, hit_dir)


## Builds merged Voronoi shard mesh and per-shard convex colliders, hiding intact quad/collider.
func _subdivide_into_shards(focus_xy: Vector2) -> void:
	_is_subdivided = true
	if is_instance_valid(_glass_quad):
		_glass_quad.visible = false
	if is_instance_valid(_collision_shape):
		_collision_shape.set_deferred(&"disabled", true)

	_shards_mesh_inst = MeshInstance3D.new()
	_shards_mesh_inst.name = &"ShardsMesh"
	_shards_mesh_inst.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	_shards_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shards_mesh_inst.set_instance_shader_parameter(
		PARAM_IS_ARMORED, 1.0 if mode == GlassMode.ARMORED else 0.0
	)
	_shards_mesh_inst.set_instance_shader_parameter(PARAM_USE_VERTEX_CRACK, 1.0)
	add_child(_shards_mesh_inst)

	var seeds: PackedVector2Array = _generate_voronoi_seeds(focus_xy)
	var half_size: Vector2 = size * 0.5
	_shards_base_mat = null
	if is_instance_valid(_glass_quad) and is_instance_valid(_glass_quad.mesh):
		_shards_base_mat = _glass_quad.mesh.surface_get_material(0)

	var polys: Array[PackedVector2Array] = []
	for i: int in range(seeds.size()):
		var poly: PackedVector2Array = _clip_voronoi_cell(i, seeds, half_size)
		if poly.size() >= 3:
			polys.append(poly)

	_shards.clear()
	for poly: PackedVector2Array in polys:
		var shard: Dictionary = _create_shard_entry(poly, half_size)
		_shards.append(shard)

	_build_shard_adjacency()
	_rebuild_merged_shards_mesh()


## Generates jittered grid seeds plus radial seeds around [param focus_xy] for organic shards.
func _generate_voronoi_seeds(focus_xy: Vector2) -> PackedVector2Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	var area: float = size.x * size.y
	var target_count: int = clampi(int(round(area * 12.0)), 14, 48)
	var aspect: float = size.x / maxf(size.y, 0.01)
	var cols: int = maxi(int(round(sqrt(float(target_count) * aspect))), 3)
	var rows: int = maxi(int(round(float(target_count) / float(cols))), 3)

	var cell_w: float = size.x / float(cols)
	var cell_h: float = size.y / float(rows)
	var seeds: PackedVector2Array = PackedVector2Array()

	for r: int in range(rows):
		for c: int in range(cols):
			var base_x: float = -size.x * 0.5 + (float(c) + 0.5) * cell_w
			var base_y: float = -size.y * 0.5 + (float(r) + 0.5) * cell_h
			var jx: float = rng.randf_range(-0.35, 0.35) * cell_w
			var jy: float = rng.randf_range(-0.35, 0.35) * cell_h
			seeds.append(Vector2(base_x + jx, base_y + jy))

	# Add radial cluster around impact point for finer local splinters.
	var radial_r: float = minf(minf(size.x, size.y) * 0.25, break_radius * 0.7)
	seeds.append(focus_xy)
	for k: int in range(5):
		var angle: float = (TAU / 5.0) * float(k) + rng.randf_range(-0.25, 0.25)
		var pt: Vector2 = focus_xy + Vector2(cos(angle), sin(angle)) * radial_r
		pt.x = clampf(pt.x, -size.x * 0.48, size.x * 0.48)
		pt.y = clampf(pt.y, -size.y * 0.48, size.y * 0.48)
		seeds.append(pt)

	return seeds


## Clips pane rectangle against bisector half-planes of all other Voronoi seeds.
func _clip_voronoi_cell(
	seed_idx: int, seeds: PackedVector2Array, half_size: Vector2
) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array(
		[
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y)
		]
	)
	var p_i: Vector2 = seeds[seed_idx]
	for j: int in range(seeds.size()):
		if j == seed_idx:
			continue
		var p_j: Vector2 = seeds[j]
		var normal: Vector2 = p_j - p_i
		if normal.length_squared() < 0.000001:
			continue
		var mid: Vector2 = (p_i + p_j) * 0.5
		poly = _clip_polygon_half_plane(poly, normal, mid.dot(normal))
		if poly.size() < 3:
			return PackedVector2Array()
	return poly


## Sutherland-Hodgman clip of convex [param poly] keeping points with p.dot(normal) <= d.
func _clip_polygon_half_plane(
	poly: PackedVector2Array, normal: Vector2, d: float
) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var count: int = poly.size()
	if count == 0:
		return out
	for i: int in range(count):
		var curr: Vector2 = poly[i]
		var prev: Vector2 = poly[(i - 1 + count) % count]
		var curr_in: bool = curr.dot(normal) <= d
		var prev_in: bool = prev.dot(normal) <= d
		if curr_in != prev_in:
			var denom: float = (curr - prev).dot(normal)
			if absf(denom) > 0.000001:
				var t: float = clampf((d - prev.dot(normal)) / denom, 0.0, 1.0)
				out.append(prev.lerp(curr, t))
		if curr_in:
			out.append(curr)
	return out


## Creates collider and metadata dictionary for a single Voronoi polygon shard.
func _create_shard_entry(poly: PackedVector2Array, half_size: Vector2) -> Dictionary:
	var center: Vector2 = Vector2.ZERO
	var is_perimeter: bool = false
	for v: Vector2 in poly:
		center += v
		if absf(v.x) >= half_size.x - 0.003 or absf(v.y) >= half_size.y - 0.003:
			is_perimeter = true
	center /= float(poly.size())

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.shape = _build_shard_convex_shape(poly)
	_glass_body.add_child(col_shape)

	var empty_neighbors: Array[int] = []
	return {
		&"poly": poly,
		&"center": center,
		&"is_perimeter": is_perimeter,
		&"neighbors": empty_neighbors,
		&"alive": true,
		&"crack": _crack_intensity,
		&"impact_uv": _impact_uv,
		&"col": col_shape,
	}


## Rebuilds the single merged [ArrayMesh] for all alive Voronoi shards in one draw call.
func _rebuild_merged_shards_mesh() -> void:
	if not is_instance_valid(_shards_mesh_inst):
		return

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()

	for shard: Dictionary in _shards:
		if not bool(shard.get(&"alive", false)):
			continue
		var poly_raw: Variant = shard.get(&"poly", PackedVector2Array())
		if not (poly_raw is PackedVector2Array):
			continue
		var poly: PackedVector2Array = poly_raw as PackedVector2Array
		if poly.size() < 3:
			continue

		var crack_raw: Variant = shard.get(&"crack", 0.0)
		var shard_crack: float = crack_raw if crack_raw is float else 0.0
		var uv_raw: Variant = shard.get(&"impact_uv", Vector2(0.5, 0.5))
		var shard_uv: Vector2 = uv_raw if uv_raw is Vector2 else Vector2(0.5, 0.5)
		var vert_color: Color = Color(shard_crack, shard_uv.x, shard_uv.y, 1.0)
		var base_idx: int = verts.size()

		for v: Vector2 in poly:
			verts.append(Vector3(v.x, v.y, 0.0))
			normals.append(Vector3.BACK)
			tangents.append(1.0)
			tangents.append(0.0)
			tangents.append(0.0)
			tangents.append(1.0)
			uvs.append(_local_to_uv(v))
			colors.append(vert_color)

		for k: int in range(1, poly.size() - 1):
			indices.append(base_idx)
			indices.append(base_idx + k + 1)
			indices.append(base_idx + k)

	if indices.is_empty():
		_shards_mesh_inst.visible = false
		_shards_mesh_inst.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh: ArrayMesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if is_instance_valid(_shards_base_mat):
		arr_mesh.surface_set_material(0, _shards_base_mat)

	_shards_mesh_inst.mesh = arr_mesh
	_shards_mesh_inst.visible = true


## Builds an [ArrayMesh] with front-facing normals, tangents, and pane-aligned UVs.
func _build_shard_array_mesh(poly: PackedVector2Array, base_mat: Material) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	for v: Vector2 in poly:
		verts.append(Vector3(v.x, v.y, 0.0))
		normals.append(Vector3.BACK)
		tangents.append(1.0)
		tangents.append(0.0)
		tangents.append(0.0)
		tangents.append(1.0)
		uvs.append(_local_to_uv(v))

	for k: int in range(1, poly.size() - 1):
		indices.append(0)
		indices.append(k + 1)
		indices.append(k)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh: ArrayMesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if is_instance_valid(base_mat):
		arr_mesh.surface_set_material(0, base_mat)
	return arr_mesh


## Builds an extruded thin [ConvexPolygonShape3D] for a 2D Voronoi shard polygon.
func _build_shard_convex_shape(poly: PackedVector2Array) -> ConvexPolygonShape3D:
	var pts: PackedVector3Array = PackedVector3Array()
	for v: Vector2 in poly:
		pts.append(Vector3(v.x, v.y, GLASS_HALF_THICKNESS))
		pts.append(Vector3(v.x, v.y, -GLASS_HALF_THICKNESS))
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


## Populates neighbor index lists for all Voronoi shards sharing at least two vertices.
func _build_shard_adjacency() -> void:
	var count: int = _shards.size()
	for i: int in range(count):
		var poly_i_raw: Variant = _shards[i].get(&"poly", PackedVector2Array())
		var poly_i: PackedVector2Array = (
			poly_i_raw if poly_i_raw is PackedVector2Array else PackedVector2Array()
		)
		for j: int in range(i + 1, count):
			var poly_j_raw: Variant = _shards[j].get(&"poly", PackedVector2Array())
			var poly_j: PackedVector2Array = (
				poly_j_raw if poly_j_raw is PackedVector2Array else PackedVector2Array()
			)
			if _polys_share_edge(poly_i, poly_j):
				var n_i: Array[int] = _shards[i][&"neighbors"]
				var n_j: Array[int] = _shards[j][&"neighbors"]
				n_i.append(j)
				n_j.append(i)


## Returns true if two convex polygons share at least two matching vertices.
func _polys_share_edge(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var shared: int = 0
	for va: Vector2 in a:
		for vb: Vector2 in b:
			if va.distance_squared_to(vb) <= 0.00001:
				shared += 1
				if shared >= 2:
					return true
				break
	return false


## Returns indices of alive shards within [param hit_radius] of [param local_xy] (min 1).
func _collect_hit_shards(local_xy: Vector2, hit_radius: float) -> Array[int]:
	var result: Array[int] = []
	var r_sq: float = hit_radius * hit_radius
	var best_idx: int = -1
	var best_dist_sq: float = INF

	for i: int in range(_shards.size()):
		if not bool(_shards[i].get(&"alive", false)):
			continue
		var center_raw: Variant = _shards[i].get(&"center", Vector2.ZERO)
		var center: Vector2 = center_raw if center_raw is Vector2 else Vector2.ZERO
		var d_sq: float = center.distance_squared_to(local_xy)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_idx = i
		if d_sq <= r_sq:
			result.append(i)

	if result.is_empty() and best_idx != -1:
		result.append(best_idx)
	return result


## Runs BFS from perimeter-anchored shards and returns indices of disconnected floating islands.
func _collect_floating_shards() -> Array[int]:
	var visited: Array[bool] = []
	visited.resize(_shards.size())
	visited.fill(false)

	var queue: Array[int] = []
	for i: int in range(_shards.size()):
		if bool(_shards[i].get(&"alive", false)) and bool(_shards[i].get(&"is_perimeter", false)):
			visited[i] = true
			queue.append(i)

	var head: int = 0
	while head < queue.size():
		var curr: int = queue[head]
		head += 1
		var neighbors_raw: Variant = _shards[curr].get(&"neighbors", [])
		var neighbors: Array = neighbors_raw if neighbors_raw is Array else []
		for n_raw: Variant in neighbors:
			var n_idx: int = n_raw if n_raw is int else -1
			if n_idx < 0 or visited[n_idx]:
				continue
			if bool(_shards[n_idx].get(&"alive", false)):
				visited[n_idx] = true
				queue.append(n_idx)

	var floating: Array[int] = []
	for i: int in range(_shards.size()):
		if bool(_shards[i].get(&"alive", false)) and not visited[i]:
			floating.append(i)
	return floating


## Frees shard collider and optionally spawns falling [RigidBody3D] debris.
func _remove_shard(idx: int, spawn_debris: bool, impulse_dir: Vector3) -> void:
	var shard: Dictionary = _shards[idx]
	if spawn_debris:
		_spawn_shard_debris(shard, impulse_dir)

	var col_raw: Variant = shard.get(&"col", null)
	if col_raw is CollisionShape3D:
		var cs: CollisionShape3D = col_raw as CollisionShape3D
		if is_instance_valid(cs):
			cs.set_deferred(&"disabled", true)
			cs.queue_free()
	shard[&"col"] = null


## Spawns a lightweight falling [RigidBody3D] shard on Physics Layer 4 and auto-frees it.
func _spawn_shard_debris(shard: Dictionary, impulse_dir: Vector3) -> void:
	var host: Node = get_parent()
	if not is_instance_valid(host) or not is_inside_tree():
		return

	var poly_raw: Variant = shard.get(&"poly", PackedVector2Array())
	if not (poly_raw is PackedVector2Array):
		return

	var poly: PackedVector2Array = poly_raw as PackedVector2Array
	if poly.size() < 3:
		return
	var arr_mesh: ArrayMesh = _build_shard_array_mesh(poly, _shards_base_mat)
	var center_raw: Variant = shard.get(&"center", Vector2.ZERO)
	var center: Vector2 = center_raw if center_raw is Vector2 else Vector2.ZERO

	var body: RigidBody3D = RigidBody3D.new()
	body.collision_layer = CollisionLayers.MASK_DEBRIS
	body.collision_mask = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS
	body.mass = 0.25
	body.global_transform = global_transform

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = arr_mesh
	mi.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter(PARAM_CRACK_INTENSITY, 0.65)
	body.add_child(mi)

	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = _build_shard_convex_shape(poly)
	body.add_child(cs)

	host.add_child(body)

	var world_offset: Vector3 = global_transform.basis * Vector3(center.x, center.y, 0.0)
	var impulse: Vector3 = impulse_dir * randf_range(1.2, 3.2) + Vector3(0.0, 0.4, 0.0)
	body.apply_impulse(impulse, world_offset)
	body.angular_velocity = Vector3(
		randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)
	)

	var timer: SceneTreeTimer = get_tree().create_timer(DEBRIS_LIFETIME_SEC)
	timer.timeout.connect(body.queue_free)


## Increases crack state on surviving shards within [param crack_radius].
func _apply_radial_cracks(local_xy: Vector2, crack_radius: float) -> void:
	var impact_uv: Vector2 = _local_to_uv(local_xy)
	var r_sq: float = crack_radius * crack_radius
	for shard: Dictionary in _shards:
		if not bool(shard.get(&"alive", false)):
			continue
		var center_raw: Variant = shard.get(&"center", Vector2.ZERO)
		var center: Vector2 = center_raw if center_raw is Vector2 else Vector2.ZERO
		var dist_sq: float = center.distance_squared_to(local_xy)
		if dist_sq > r_sq:
			continue
		var falloff: float = 1.0 - (sqrt(dist_sq) / maxf(crack_radius, 0.001))
		var cur_crack_raw: Variant = shard.get(&"crack", 0.0)
		var cur_crack: float = cur_crack_raw if cur_crack_raw is float else 0.0
		var next_crack: float = clampf(cur_crack + 0.4 + 0.55 * falloff, 0.0, 1.0)
		shard[&"crack"] = next_crack
		shard[&"impact_uv"] = impact_uv


## Frees all generated shard colliders, merged mesh node, and cached metadata.
func _clear_shards() -> void:
	for i: int in range(_shards.size()):
		_remove_shard(i, false, Vector3.ZERO)
	_shards.clear()
	if is_instance_valid(_shards_mesh_inst):
		_shards_mesh_inst.queue_free()
	_shards_mesh_inst = null
	_shards_base_mat = null
