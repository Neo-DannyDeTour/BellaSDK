## Destructible reinforced concrete wall panel supporting craters, chunk collapse, and rebar bend.
class_name DestructibleWallPanel
extends StaticBody3D

## Emitted when a concrete chunk at [param chunk_index] breaks free from the wall.
signal chunk_removed(chunk_index: int)

## Emitted once when the first concrete chunk is removed from this panel.
signal panel_breached

## Emitted once when every concrete chunk in this panel has been removed.
signal panel_destroyed

## Spatial shader driving vertex chunk collapse and parallax bullet craters.
const WALL_SHADER: Shader = preload("res://shaders/destructible_wall.gdshader")

## Spatial shader driving vertex blast deformation on exposed steel rebar.
const REBAR_SHADER: Shader = preload("res://shaders/rebar.gdshader")

## Shader uniform storing low 32 bits of the removed-chunk bitmask.
const PARAM_REMOVED_LO: StringName = &"removed_lo"

## Shader uniform storing high 32 bits of the removed-chunk bitmask.
const PARAM_REMOVED_HI: StringName = &"removed_hi"

## Shader uniform selecting inner fracture surface appearance.
const PARAM_IS_INNER: StringName = &"is_inner"

## Shader uniform enabling parallax surface crater raymarching.
const PARAM_HAS_SURFACE_DAMAGE: StringName = &"has_surface_damage"

## Shader uniform binding the RG8 front and back surface crater texture.
const PARAM_DAMAGE_MASK: StringName = &"damage_mask"

## Shader uniform specifying local XY panel dimensions in meters.
const PARAM_PANEL_SIZE: StringName = &"panel_size"

## Shader uniform specifying maximum parallax crater depth in meters.
const PARAM_SURFACE_MAX_DEPTH: StringName = &"surface_max_depth"

## Shader uniform specifying active blast count on the rebar shader.
const PARAM_BLAST_COUNT: StringName = &"blast_count"

## Shader uniform specifying up to four local blast centers and radii.
const PARAM_BLAST_POINTS: StringName = &"blast_points"

## Shader uniform specifying up to four local blast directions and amplitudes.
const PARAM_BLAST_DIRS: StringName = &"blast_dirs"

## Shader uniform specifying rebar height in meters for top and bottom pinning.
const PARAM_PANEL_HEIGHT: StringName = &"panel_height"

## Width in pixels of the lazy RG8 surface damage mask image.
const MASK_WIDTH: int = 128

## Height in pixels of the lazy RG8 surface damage mask image.
const MASK_HEIGHT: int = 192

## Soft circular brush radius in pixels painted on each surface hit.
const BRUSH_RADIUS_PX: int = 5

## Maximum number of localized rebar blast bends supported by the shader.
const MAX_REBAR_BLASTS: int = 4

## Number of dust particles emitted when a sub-threshold chunk disintegrates.
const DUST_PARTICLES_PER_CHUNK: int = 12

## Sleep lifetime in seconds before spawned concrete debris despawns.
const DEFAULT_DEBRIS_SLEEP_LIFETIME: float = 6.0

## Default outer concrete albedo color shared with spawned debris chunks.
const OUTER_CONCRETE_COLOR: Color = Color(0.56, 0.56, 0.53, 1.0)

## Default inner fracture concrete albedo color shared with spawned debris chunks.
const INNER_CONCRETE_COLOR: Color = Color(0.38, 0.37, 0.34, 1.0)

## Shared outer surface shader material reused across undamaged panels.
static var _shared_outer_mat: ShaderMaterial = null

## Shared inner fracture shader material reused across undamaged panels.
static var _shared_inner_mat: ShaderMaterial = null

## Shared rebar shader material reused across unbent panels.
static var _shared_rebar_mat: ShaderMaterial = null

## Shared outer concrete [StandardMaterial3D] assigned to spawned debris chunks.
static var _debris_outer_mat: StandardMaterial3D = null

## Shared inner concrete [StandardMaterial3D] assigned to spawned debris chunks.
static var _debris_inner_mat: StandardMaterial3D = null

## Baked Voronoi chunk geometry, collision shapes, centroids, and adjacency graph.
@export var panel_data: WallPanelData = null

## Base structural hit points initialized per concrete chunk.
@export var chunk_max_hp: float = 100.0

## Scale factor converting bullet damage into chunk structural damage.
@export var bullet_chunk_damage_scale: float = 0.35

## Minimum rigid-body momentum (kg*m/s) required to fracture concrete chunks.
@export var impact_momentum_threshold: float = 180.0

## Minimum chunk volume in cubic meters required to spawn physical debris.
@export var debris_volume_threshold: float = 0.025

## Impact speed in m/s causing falling concrete islands to split apart.
@export var landing_split_speed: float = 4.5

## Maximum parallax occlusion depth in meters for surface bullet craters.
@export var surface_max_depth: float = 0.025

## Optional 3D sound effect played on concrete surface bullet hits.
@export var hit_sfx: AudioStream = null

## Optional 3D sound effect played when concrete chunks break free.
@export var break_sfx: AudioStream = null

## 64-bit bitmask tracking removed concrete chunks.
var removed_mask: int = 0

## True once at least one concrete chunk has been removed.
var is_breached: bool = false

## True once every concrete chunk in this panel has been removed.
var is_destroyed: bool = false

## Remaining hit points indexed by concrete chunk index.
var _chunk_hp: PackedFloat32Array = PackedFloat32Array()

## Direct-child collision shapes spawned per concrete chunk.
var _chunk_colliders: Array[CollisionShape3D] = []

## Active outer wall material (shared until this panel takes damage).
var _outer_mat: ShaderMaterial = null

## Active inner wall material (shared until this panel takes damage).
var _inner_mat: ShaderMaterial = null

## Active rebar material (shared until this panel receives blast deformation).
var _rebar_mat: ShaderMaterial = null

## True after wall shader materials have been duplicated for this panel.
var _has_unique_wall_mats: bool = false

## True after rebar shader material has been duplicated for this panel.
var _has_unique_rebar_mat: bool = false

## Lazy RG8 image storing front (R) and back (G) bullet crater intensities.
var _damage_image: Image = null

## GPU texture backed by [member _damage_image], updated only on surface hits.
var _damage_texture: ImageTexture = null

## Number of active blast sources applied to the rebar shader.
var _blast_count: int = 0

## Next circular slot index used when more than four blasts strike one panel.
var _next_blast_slot: int = 0

## Local blast origin xyz and radius w array passed to the rebar shader.
var _blast_points: Array[Vector4] = []

## Local blast push direction xyz and bend amplitude w array for rebar shader.
var _blast_dirs: Array[Vector4] = []

## Merged two-surface concrete mesh instance.
@onready var _wall_mesh: MeshInstance3D = get_node_or_null("WallMesh") as MeshInstance3D

## Static rebar collider body absorbing hits on exposed reinforcement.
@onready var _rebar_body: StaticBody3D = get_node_or_null("RebarBody") as StaticBody3D

## Visual mesh rendering embedded steel reinforcement bars.
@onready var _rebar_mesh: MeshInstance3D = get_node_or_null("RebarBody/RebarMesh") as MeshInstance3D

## Trimesh collider matching exposed steel reinforcement geometry.
@onready var _rebar_collider: CollisionShape3D = (
	get_node_or_null("RebarBody/RebarCollider") as CollisionShape3D
)

## Area sensor detecting high-momentum physics body collisions.
@onready var _impact_sensor: Area3D = get_node_or_null("ImpactSensor") as Area3D

## Particle emitter bursting concrete dust when small chunks break.
@onready var _dust_particles: GPUParticles3D = get_node_or_null("DustParticles") as GPUParticles3D


## Initializes colliders, shared materials, rebar mesh, and disables tick loops.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	collision_layer = CollisionLayers.MASK_ENVIRONMENT
	collision_mask = CollisionLayers.MASK_NONE

	_blast_points.resize(MAX_REBAR_BLASTS)
	_blast_points.fill(Vector4.ZERO)
	_blast_dirs.resize(MAX_REBAR_BLASTS)
	_blast_dirs.fill(Vector4.ZERO)

	if panel_data == null or not panel_data.is_valid():
		push_warning("DestructibleWallPanel: Missing or invalid panel_data.")
		return

	if is_instance_valid(_wall_mesh):
		_wall_mesh.mesh = panel_data.merged_mesh
		_wall_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
		_outer_mat = _get_shared_outer_mat()
		_inner_mat = _get_shared_inner_mat()
		if panel_data.merged_mesh.get_surface_count() >= 1:
			_wall_mesh.set_surface_override_material(0, _outer_mat)
		if panel_data.merged_mesh.get_surface_count() >= 2:
			_wall_mesh.set_surface_override_material(1, _inner_mat)

	var count: int = panel_data.chunk_count
	_chunk_hp.resize(count)
	_chunk_hp.fill(chunk_max_hp)

	_chunk_colliders.resize(count)
	for i: int in range(count):
		var col_shape: CollisionShape3D = CollisionShape3D.new()
		col_shape.name = "ChunkCol_%d" % i
		col_shape.position = panel_data.chunk_centroids[i]
		col_shape.shape = panel_data.chunk_shapes[i]
		add_child(col_shape)
		_chunk_colliders[i] = col_shape

	if is_instance_valid(_rebar_body):
		_rebar_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
		_rebar_body.collision_mask = CollisionLayers.MASK_NONE
	if is_instance_valid(_rebar_mesh):
		_rebar_mesh.mesh = panel_data.rebar_mesh
		_rebar_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
		_rebar_mat = _get_shared_rebar_mat()
		_rebar_mesh.set_surface_override_material(0, _rebar_mat)
	if is_instance_valid(_rebar_collider):
		_rebar_collider.shape = panel_data.rebar_shape

	if is_instance_valid(_impact_sensor):
		Utilities.safe_connect(_impact_sensor.body_entered, _on_impact_sensor_body_entered)


## Disconnects sensor signal cleanly on scene exit.
func _exit_tree() -> void:
	if is_instance_valid(_impact_sensor):
		if _impact_sensor.body_entered.is_connected(_on_impact_sensor_body_entered):
			_impact_sensor.body_entered.disconnect(_on_impact_sensor_body_entered)


## Applies projectile damage, paints front or back craters, and breaks depleted chunks.
func take_damage(amount: int, hit_pos: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed or amount <= 0:
		return
	if panel_data == null or not panel_data.is_valid():
		return

	var local_pos: Vector3 = to_local(hit_pos)
	var local_dir: Vector3 = global_transform.basis.inverse() * dir
	var is_front: bool = (local_pos.z >= 0.0) if dir.is_zero_approx() else (local_dir.z < 0.0)

	_paint_surface_damage(local_pos, is_front, amount)

	if is_instance_valid(hit_sfx):
		Events.sfx_3d_requested.emit(hit_sfx, hit_pos, &"SFX")

	var chunk_idx: int = panel_data.find_nearest_remaining_chunk(local_pos, removed_mask)
	if chunk_idx < 0:
		return

	var chunk_damage: float = float(amount) * bullet_chunk_damage_scale
	_chunk_hp[chunk_idx] -= chunk_damage
	if _chunk_hp[chunk_idx] <= 0.0:
		var push_local: Vector3 = (
			local_dir.normalized()
			if not local_dir.is_zero_approx()
			else Vector3(0.0, 0.15, -1.0 if is_front else 1.0).normalized()
		)
		var world_vel: Vector3 = (global_transform.basis * push_local) * 2.5
		_mark_chunk_removed(chunk_idx, world_vel)
		_finalize_removal_batch(world_vel, hit_pos)
		print("DestructibleWallPanel: Chunk ", chunk_idx, " shattered by gunfire.")


## Fractures concrete around [param point] when [param momentum] meets threshold.
func apply_impact(point: Vector3, momentum: float) -> void:
	if is_destroyed or momentum < impact_momentum_threshold:
		return
	if panel_data == null or not panel_data.is_valid():
		return

	var local_point: Vector3 = to_local(point)
	var nearest_idx: int = panel_data.find_nearest_remaining_chunk(local_point, removed_mask)
	if nearest_idx < 0:
		return

	var ratio: float = momentum / maxf(impact_momentum_threshold, 1.0)
	var impact_radius: float = clampf(0.4 + (ratio - 1.0) * 0.35, 0.4, 1.4)
	var impact_damage: float = chunk_max_hp * clampf(ratio, 1.0, 4.0)
	var candidates: PackedInt32Array = panel_data.find_chunks_in_radius(
		local_point, impact_radius, removed_mask
	)

	var default_local_dir: Vector3 = (
		Vector3(0.0, 0.15, -1.0 if local_point.z >= 0.0 else 1.0).normalized()
	)
	var fallback_world_vel: Vector3 = (
		(global_transform.basis * default_local_dir) * clampf(ratio * 3.0, 3.0, 10.0)
	)

	for idx: int in candidates:
		if idx == nearest_idx:
			continue
		_chunk_hp[idx] -= impact_damage
		if _chunk_hp[idx] <= 0.0:
			var vel: Vector3 = _compute_outward_velocity(
				panel_data.chunk_centroids[idx], local_point, ratio * 3.2
			)
			_mark_chunk_removed(idx, vel)

	_chunk_hp[nearest_idx] = 0.0
	var nearest_vel: Vector3 = _compute_outward_velocity(
		panel_data.chunk_centroids[nearest_idx], local_point, ratio * 4.0
	)
	_mark_chunk_removed(nearest_idx, nearest_vel)
	_finalize_removal_batch(fallback_world_vel, point)
	print("DestructibleWallPanel: Impact broke chunks at ", local_point, " momentum=", momentum)


## Applies explosive breach around [param center] and bends exposed rebar mesh vertices.
func apply_blast(center: Vector3, radius: float, force: float) -> void:
	if is_destroyed or radius <= 0.0:
		return
	if panel_data == null or not panel_data.is_valid():
		return

	var local_center: Vector3 = to_local(center)
	_record_rebar_blast(local_center, radius, force)

	var candidates: PackedInt32Array = panel_data.find_chunks_in_radius(
		local_center, radius, removed_mask
	)
	if candidates.is_empty():
		return

	var inner_radius: float = radius * 0.6
	var outer_span: float = maxf(radius - inner_radius, 0.001)
	var broke_any: bool = false

	for idx: int in candidates:
		var centroid: Vector3 = panel_data.chunk_centroids[idx]
		var dist: float = centroid.distance_to(local_center)
		var should_break: bool = false
		if dist <= inner_radius:
			_chunk_hp[idx] = 0.0
			should_break = true
		else:
			var falloff: float = clampf(1.0 - ((dist - inner_radius) / outer_span), 0.0, 1.0)
			_chunk_hp[idx] -= force * falloff
			should_break = _chunk_hp[idx] <= 0.0

		if should_break:
			var radial_falloff: float = clampf(1.0 - (dist / maxf(radius, 0.001)), 0.0, 1.0)
			var speed: float = clampf(force * 0.03 * (0.4 + 0.6 * radial_falloff), 3.0, 16.0)
			var vel: Vector3 = _compute_outward_velocity(centroid, local_center, speed)
			_mark_chunk_removed(idx, vel)
			broke_any = true

	if broke_any:
		var push_local: Vector3 = Vector3(0.0, 1.5, 0.0) - local_center
		if push_local.length_squared() < 0.0001:
			push_local = Vector3(0.0, 0.2, -1.0)
		var fallback_world_vel: Vector3 = (
			(global_transform.basis * push_local.normalized()) * clampf(force * 0.025, 3.0, 12.0)
		)
		_finalize_removal_batch(fallback_world_vel, center)
		print("DestructibleWallPanel: Blast breached wall at ", local_center)


## Returns shared base outer [ShaderMaterial] for undamaged wall panels.
func _get_shared_outer_mat() -> ShaderMaterial:
	if not is_instance_valid(_shared_outer_mat):
		_shared_outer_mat = ShaderMaterial.new()
		_shared_outer_mat.shader = WALL_SHADER
		_shared_outer_mat.set_shader_parameter(PARAM_IS_INNER, false)
		_shared_outer_mat.set_shader_parameter(PARAM_HAS_SURFACE_DAMAGE, false)
		_shared_outer_mat.set_shader_parameter(PARAM_REMOVED_LO, 0)
		_shared_outer_mat.set_shader_parameter(PARAM_REMOVED_HI, 0)
	return _shared_outer_mat


## Returns shared base inner [ShaderMaterial] for undamaged wall panels.
func _get_shared_inner_mat() -> ShaderMaterial:
	if not is_instance_valid(_shared_inner_mat):
		_shared_inner_mat = ShaderMaterial.new()
		_shared_inner_mat.shader = WALL_SHADER
		_shared_inner_mat.set_shader_parameter(PARAM_IS_INNER, true)
		_shared_inner_mat.set_shader_parameter(PARAM_HAS_SURFACE_DAMAGE, false)
		_shared_inner_mat.set_shader_parameter(PARAM_REMOVED_LO, 0)
		_shared_inner_mat.set_shader_parameter(PARAM_REMOVED_HI, 0)
	return _shared_inner_mat


## Returns shared base rebar [ShaderMaterial] for unbent panels.
func _get_shared_rebar_mat() -> ShaderMaterial:
	if not is_instance_valid(_shared_rebar_mat):
		_shared_rebar_mat = ShaderMaterial.new()
		_shared_rebar_mat.shader = REBAR_SHADER
		var empty_pts: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
		var empty_dirs: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
		_shared_rebar_mat.set_shader_parameter(PARAM_BLAST_COUNT, 0)
		_shared_rebar_mat.set_shader_parameter(PARAM_BLAST_POINTS, empty_pts)
		_shared_rebar_mat.set_shader_parameter(PARAM_BLAST_DIRS, empty_dirs)
		_shared_rebar_mat.set_shader_parameter(PARAM_PANEL_HEIGHT, 3.0)
	return _shared_rebar_mat


## Returns shared clean outer concrete [StandardMaterial3D] for debris chunks.
func _get_debris_outer_mat() -> StandardMaterial3D:
	if not is_instance_valid(_debris_outer_mat):
		_debris_outer_mat = StandardMaterial3D.new()
		_debris_outer_mat.albedo_color = OUTER_CONCRETE_COLOR
		_debris_outer_mat.roughness = 0.9
	return _debris_outer_mat


## Returns shared clean inner concrete [StandardMaterial3D] for debris chunks.
func _get_debris_inner_mat() -> StandardMaterial3D:
	if not is_instance_valid(_debris_inner_mat):
		_debris_inner_mat = StandardMaterial3D.new()
		_debris_inner_mat.albedo_color = INNER_CONCRETE_COLOR
		_debris_inner_mat.roughness = 0.95
	return _debris_inner_mat


## Duplicates shared wall materials lazily on first hit or chunk removal.
func _ensure_unique_wall_materials() -> void:
	if _has_unique_wall_mats:
		return
	_has_unique_wall_mats = true
	# shortcut: instance uniforms can't hold samplers,
	# upgrade to Texture2DArray atlas if > ~50 damaged panels
	if not is_instance_valid(_outer_mat):
		_outer_mat = _get_shared_outer_mat()
	if not is_instance_valid(_inner_mat):
		_inner_mat = _get_shared_inner_mat()

	_outer_mat = _outer_mat.duplicate() as ShaderMaterial
	_inner_mat = _inner_mat.duplicate() as ShaderMaterial

	var size_xy: Vector2 = Vector2(2.0, 3.0)
	if panel_data != null:
		size_xy = Vector2(panel_data.panel_size.x, panel_data.panel_size.y)

	_outer_mat.set_shader_parameter(PARAM_IS_INNER, false)
	_outer_mat.set_shader_parameter(PARAM_PANEL_SIZE, size_xy)
	_outer_mat.set_shader_parameter(PARAM_SURFACE_MAX_DEPTH, surface_max_depth)

	_inner_mat.set_shader_parameter(PARAM_IS_INNER, true)
	_inner_mat.set_shader_parameter(PARAM_PANEL_SIZE, size_xy)
	_inner_mat.set_shader_parameter(PARAM_SURFACE_MAX_DEPTH, surface_max_depth)

	if is_instance_valid(_wall_mesh) and panel_data != null and panel_data.merged_mesh != null:
		var surf_count: int = panel_data.merged_mesh.get_surface_count()
		if surf_count >= 1:
			_wall_mesh.set_surface_override_material(0, _outer_mat)
		if surf_count >= 2:
			_wall_mesh.set_surface_override_material(1, _inner_mat)


## Duplicates shared rebar material lazily before writing blast deformation uniforms.
func _ensure_unique_rebar_material() -> void:
	if _has_unique_rebar_mat:
		return
	_has_unique_rebar_mat = true
	if not is_instance_valid(_rebar_mat):
		_rebar_mat = _get_shared_rebar_mat()
	_rebar_mat = _rebar_mat.duplicate() as ShaderMaterial
	if panel_data != null:
		_rebar_mat.set_shader_parameter(PARAM_PANEL_HEIGHT, panel_data.panel_size.y)
	if is_instance_valid(_rebar_mesh):
		_rebar_mesh.set_surface_override_material(0, _rebar_mat)


## Lazily creates and paints the RG8 crater mask for front (R) or back (G) hits.
func _paint_surface_damage(local_pos: Vector3, is_front: bool, amount: int) -> void:
	_ensure_unique_wall_materials()
	var is_first_paint: bool = _damage_image == null
	if is_first_paint:
		_damage_image = Image.create(MASK_WIDTH, MASK_HEIGHT, false, Image.FORMAT_RG8)
		_damage_image.fill(Color(0.0, 0.0, 0.0, 1.0))

	var size_x: float = maxf(panel_data.panel_size.x, 0.001)
	var size_y: float = maxf(panel_data.panel_size.y, 0.001)
	var u: float = clampf((local_pos.x / size_x) + 0.5, 0.0, 1.0)
	var v: float = clampf(1.0 - (local_pos.y / size_y), 0.0, 1.0)

	var cx: int = clampi(int(roundf(u * float(MASK_WIDTH - 1))), 0, MASK_WIDTH - 1)
	var cy: int = clampi(int(roundf(v * float(MASK_HEIGHT - 1))), 0, MASK_HEIGHT - 1)
	var hit_strength: float = clampf(float(amount) / 30.0, 0.45, 1.0)

	for dy: int in range(-BRUSH_RADIUS_PX, BRUSH_RADIUS_PX + 1):
		var py: int = cy + dy
		if py < 0 or py >= MASK_HEIGHT:
			continue
		for dx: int in range(-BRUSH_RADIUS_PX, BRUSH_RADIUS_PX + 1):
			var px: int = cx + dx
			if px < 0 or px >= MASK_WIDTH:
				continue
			var dist: float = sqrt(float(dx * dx + dy * dy))
			if dist > float(BRUSH_RADIUS_PX):
				continue
			var t: float = 1.0 - (dist / float(BRUSH_RADIUS_PX))
			var brush: float = (t * t * (3.0 - 2.0 * t)) * hit_strength
			var cur: Color = _damage_image.get_pixel(px, py)
			if is_front:
				cur.r = clampf(cur.r + brush, 0.0, 1.0)
			else:
				cur.g = clampf(cur.g + brush, 0.0, 1.0)
			_damage_image.set_pixel(px, py, cur)

	if is_first_paint or DisplayServer.get_name() == "headless":
		# Dummy headless renderer does not sync ImageTexture.update() back to get_image().
		_damage_texture = ImageTexture.create_from_image(_damage_image)
		if is_instance_valid(_outer_mat):
			_outer_mat.set_shader_parameter(PARAM_HAS_SURFACE_DAMAGE, true)
			_outer_mat.set_shader_parameter(PARAM_DAMAGE_MASK, _damage_texture)
	elif is_instance_valid(_damage_texture):
		_damage_texture.update(_damage_image)


## Records up to four blast deformation vectors onto the rebar shader material.
func _record_rebar_blast(local_center: Vector3, radius: float, force: float) -> void:
	_ensure_unique_rebar_material()
	var panel_mid: Vector3 = Vector3(0.0, panel_data.panel_size.y * 0.5, 0.0)
	var push_dir: Vector3 = panel_mid - local_center
	if push_dir.length_squared() < 0.0001:
		push_dir = Vector3(0.0, 0.0, -1.0)
	else:
		push_dir = push_dir.normalized()

	var bend_amp: float = clampf(force * 0.001, 0.08, 0.28)
	var slot: int = (
		_blast_count if _blast_count < MAX_REBAR_BLASTS else (_next_blast_slot % MAX_REBAR_BLASTS)
	)
	_blast_points[slot] = Vector4(local_center.x, local_center.y, local_center.z, radius)
	_blast_dirs[slot] = Vector4(push_dir.x, push_dir.y, push_dir.z, bend_amp)
	if _blast_count < MAX_REBAR_BLASTS:
		_blast_count += 1
	_next_blast_slot += 1

	if is_instance_valid(_rebar_mat):
		_rebar_mat.set_shader_parameter(PARAM_BLAST_COUNT, _blast_count)
		_rebar_mat.set_shader_parameter(PARAM_BLAST_POINTS, _blast_points)
		_rebar_mat.set_shader_parameter(PARAM_BLAST_DIRS, _blast_dirs)


## Marks [param chunk_idx] removed, disables its collider, spawns debris/dust, emits signals.
func _mark_chunk_removed(chunk_idx: int, world_vel: Vector3) -> void:
	if chunk_idx < 0 or chunk_idx >= panel_data.chunk_count:
		return
	if WallPanelData.is_chunk_set(removed_mask, chunk_idx):
		return

	removed_mask |= WallPanelData.bit_for_chunk(chunk_idx)

	if chunk_idx < _chunk_colliders.size():
		var col_shape: CollisionShape3D = _chunk_colliders[chunk_idx]
		if is_instance_valid(col_shape):
			col_shape.set_deferred(&"disabled", true)

	if panel_data.chunk_volumes[chunk_idx] >= debris_volume_threshold:
		_spawn_single_debris(chunk_idx, world_vel)
	else:
		_emit_dust_burst(panel_data.chunk_centroids[chunk_idx], world_vel)

	if not is_breached:
		is_breached = true
		panel_breached.emit()
		print("DestructibleWallPanel: Wall breached!")

	chunk_removed.emit(chunk_idx)


## Collapses floating islands, updates shader bitmasks, plays SFX, checks full destruction.
func _finalize_removal_batch(fallback_world_vel: Vector3, sfx_pos: Vector3) -> void:
	_process_disconnected_islands(fallback_world_vel)
	_sync_removed_uniforms()

	if is_instance_valid(break_sfx):
		Events.sfx_3d_requested.emit(break_sfx, sfx_pos, &"SFX")

	var all_mask: int = WallPanelData.all_chunks_mask(panel_data.chunk_count)
	if not is_destroyed and (removed_mask & all_mask) == all_mask:
		is_destroyed = true
		if is_instance_valid(_impact_sensor):
			_impact_sensor.set_deferred(&"monitoring", false)
		panel_destroyed.emit()
		print("DestructibleWallPanel: All chunks removed; panel destroyed.")


## Finds unsupported islands via [WallPanelData], disables colliders, and spawns island debris.
func _process_disconnected_islands(fallback_world_vel: Vector3) -> void:
	var islands: Array[PackedInt32Array] = panel_data.find_disconnected_islands(removed_mask)
	if islands.is_empty():
		return

	var island_vel: Vector3 = fallback_world_vel * 0.35 + Vector3(0.0, -0.5, 0.0)
	for island: PackedInt32Array in islands:
		if island.is_empty():
			continue
		var center: Vector3 = Vector3.ZERO
		var total_vol: float = 0.0
		for idx: int in island:
			if WallPanelData.is_chunk_set(removed_mask, idx):
				continue
			removed_mask |= WallPanelData.bit_for_chunk(idx)
			if idx >= 0 and idx < _chunk_colliders.size():
				var col_shape: CollisionShape3D = _chunk_colliders[idx]
				if is_instance_valid(col_shape):
					col_shape.set_deferred(&"disabled", true)
			center += panel_data.chunk_centroids[idx]
			total_vol += panel_data.chunk_volumes[idx]
			chunk_removed.emit(idx)

		center /= float(island.size())
		if total_vol >= debris_volume_threshold:
			_spawn_island_debris(island, center, island_vel)
		else:
			_emit_dust_burst(center, island_vel)
		print("DestructibleWallPanel: Disconnected island collapsed (", island.size(), " chunks).")


## Syncs low/high 32-bit removed bitmasks onto outer and inner wall materials.
func _sync_removed_uniforms() -> void:
	_ensure_unique_wall_materials()
	var lo: int = WallPanelData.mask_low_u32(removed_mask)
	var hi: int = WallPanelData.mask_high_u32(removed_mask)
	if is_instance_valid(_outer_mat):
		_outer_mat.set_shader_parameter(PARAM_REMOVED_LO, lo)
		_outer_mat.set_shader_parameter(PARAM_REMOVED_HI, hi)
	if is_instance_valid(_inner_mat):
		_inner_mat.set_shader_parameter(PARAM_REMOVED_LO, lo)
		_inner_mat.set_shader_parameter(PARAM_REMOVED_HI, hi)


## Spawns a single physical [WallDebris] body for [param chunk_idx].
func _spawn_single_debris(chunk_idx: int, world_vel: Vector3) -> void:
	if not is_inside_tree():
		return
	var host: Node = get_parent()
	if not is_instance_valid(host):
		return

	var debris: WallDebris = WallDebris.new()
	debris.setup_single(
		panel_data.chunk_meshes[chunk_idx],
		panel_data.chunk_shapes[chunk_idx],
		panel_data.chunk_volumes[chunk_idx],
		_get_debris_outer_mat(),
		_get_debris_inner_mat(),
		DEFAULT_DEBRIS_SLEEP_LIFETIME
	)
	host.add_child(debris)
	var world_pos: Vector3 = to_global(panel_data.chunk_centroids[chunk_idx])
	debris.global_transform = Transform3D(global_transform.basis, world_pos)
	debris.linear_velocity = world_vel
	debris.angular_velocity = Vector3(
		randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)
	)
	_register_debris_with_budget(debris)


## Spawns a compound [WallDebris] island body covering [param chunk_indices].
func _spawn_island_debris(
	chunk_indices: PackedInt32Array, island_center: Vector3, world_vel: Vector3
) -> void:
	if not is_inside_tree():
		return
	var host: Node = get_parent()
	if not is_instance_valid(host):
		return

	var debris: WallDebris = WallDebris.new()
	debris.setup_island(
		panel_data,
		chunk_indices,
		island_center,
		_get_debris_outer_mat(),
		_get_debris_inner_mat(),
		landing_split_speed,
		debris_volume_threshold,
		DEFAULT_DEBRIS_SLEEP_LIFETIME
	)
	host.add_child(debris)
	var world_pos: Vector3 = to_global(island_center)
	debris.global_transform = Transform3D(global_transform.basis, world_pos)
	debris.linear_velocity = world_vel
	debris.angular_velocity = Vector3(
		randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)
	)
	_register_debris_with_budget(debris)


## Registers [param debris] with `/root/DebrisBudget` autoload if present.
func _register_debris_with_budget(debris: RigidBody3D) -> void:
	var budget: Node = get_node_or_null("/root/DebrisBudget")
	if is_instance_valid(budget) and budget.has_method(&"register_debris"):
		budget.call(&"register_debris", debris)


## Emits a burst of dust particles at [param local_pos] for sub-threshold fragments.
func _emit_dust_burst(local_pos: Vector3, world_vel: Vector3) -> void:
	if not is_instance_valid(_dust_particles) or not is_inside_tree():
		return
	var world_pos: Vector3 = to_global(local_pos)
	var flags: int = GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY
	for i: int in range(DUST_PARTICLES_PER_CHUNK):
		var jitter: Vector3 = Vector3(
			randf_range(-0.12, 0.12), randf_range(-0.12, 0.12), randf_range(-0.08, 0.08)
		)
		var xform: Transform3D = Transform3D(Basis(), world_pos + jitter)
		var p_vel: Vector3 = (
			world_vel * randf_range(0.3, 0.8)
			+ Vector3(randf_range(-1.2, 1.2), randf_range(0.3, 1.8), randf_range(-1.2, 1.2))
		)
		_dust_particles.emit_particle(xform, p_vel, Color.WHITE, Color.BLACK, flags)


## Computes outward world velocity vector away from [param local_origin].
func _compute_outward_velocity(centroid: Vector3, local_origin: Vector3, speed: float) -> Vector3:
	var local_dir: Vector3 = centroid - local_origin
	if local_dir.length_squared() < 0.0001:
		local_dir = Vector3(0.0, 0.2, -1.0 if local_origin.z >= 0.0 else 1.0)
	else:
		local_dir.y += 0.15
	local_dir = local_dir.normalized()
	var clamped_speed: float = clampf(speed, 1.5, 16.0)
	return (global_transform.basis * local_dir) * clamped_speed


## Handles heavy interactive physics bodies entering [member _impact_sensor].
func _on_impact_sensor_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body) or is_destroyed or panel_data == null:
		return
	if body == self or body is WallDebris or body is WallRebarBody:
		return
	if not (body is RigidBody3D):
		return

	var rb: RigidBody3D = body as RigidBody3D
	var speed: float = rb.linear_velocity.length()
	var prev_vel_raw: Variant = rb.get(&"_last_velocity")
	if prev_vel_raw is Vector3:
		var prev_vel: Vector3 = prev_vel_raw
		speed = maxf(speed, prev_vel.length())
	var momentum: float = rb.mass * speed
	if momentum < impact_momentum_threshold:
		return

	var local_body: Vector3 = to_local(rb.global_position)
	var half_x: float = panel_data.panel_size.x * 0.5
	var half_z: float = panel_data.panel_size.z * 0.5
	var clamped_local: Vector3 = Vector3(
		clampf(local_body.x, -half_x, half_x),
		clampf(local_body.y, 0.0, panel_data.panel_size.y),
		clampf(local_body.z, -half_z, half_z)
	)
	apply_impact.call_deferred(to_global(clamped_local), momentum)
