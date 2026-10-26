## Interactive volumetric fog volume supporting CS2 bullet holes, blasts, and APEX wakes.
@tool
class_name DynamicFogZone
extends FogVolume

## Vertical distribution presets allowing one scene to act as floor mist or room fog.
enum FogMode {
	GROUND_HUGGING,
	FULL_ROOM,
	CUSTOM,
}

## Maximum simultaneous bullet or explosion trajectories tracked in the ring buffer.
const MAX_RAYS: int = 8

## Maximum simultaneous physics bodies displacing the fog volume.
const MAX_ACTORS: int = 8

## Render Layer 10 bitmask reserved for volumetric effects.
const RENDER_LAYER_VOLUMETRICS: int = 1 << 9

## Squared minimum actor speed (0.5 m/s) required to inject wake turbulence.
const MIN_WAKE_SPEED_SQ: float = 0.25

## Physics bitmask detecting Player (2), Interactive (3), Debris (4), and Enemies (5).
const ACTOR_COLLISION_MASK: int = (
	Types.MASK_PLAYER | Types.MASK_INTERACTIVE | Types.MASK_DEBRIS | Types.MASK_ENEMIES
)

## Pre-allocated shader uniform [StringName] constants for zero-allocation updates.
const PARAM_BASE_COLOR: StringName = &"base_color"
const PARAM_EMISSION_COLOR: StringName = &"emission_color"
const PARAM_BASE_DENSITY: StringName = &"base_density"
const PARAM_HEIGHT_FALLOFF: StringName = &"height_falloff"
const PARAM_GROUND_HEIGHT: StringName = &"ground_hugging_height"
const PARAM_EDGE_FADE: StringName = &"edge_fade"
const PARAM_WAVE_SPEED: StringName = &"wave_speed"
const PARAM_WAVE_SCALE: StringName = &"wave_scale"
const PARAM_CLUMP_SCALE: StringName = &"clump_scale"
const PARAM_CLUMP_CONTRAST: StringName = &"clump_contrast"
const PARAM_CURL_STRENGTH: StringName = &"curl_advection_strength"
const PARAM_ACTIVE_RAYS: StringName = &"active_ray_count"
const PARAM_RAY_STARTS: StringName = &"ray_starts"
const PARAM_RAY_ENDS: StringName = &"ray_ends"
const PARAM_ACTIVE_ACTORS: StringName = &"active_actor_count"
const PARAM_ACTOR_POS: StringName = &"actor_positions"
const PARAM_ACTOR_VEL: StringName = &"actor_velocities"

@export_category("Fog Behavior")
## Controls whether the fog hugs the floor, fills the entire box, or uses custom falloff.
@export var fog_mode: FogMode = FogMode.GROUND_HUGGING:
	set(value):
		fog_mode = value
		if is_inside_tree():
			_apply_mode_parameters()

## Albedo scattering color of the fog volume.
@export var albedo_color: Color = Color(0.72, 0.78, 0.84, 1.0):
	set(value):
		albedo_color = value
		if is_inside_tree():
			_sync_static_uniforms()

## Subtle self-illumination color to preserve mood in unlit corners.
@export var emission_tint: Color = Color(0.06, 0.09, 0.12, 1.0):
	set(value):
		emission_tint = value
		if is_inside_tree():
			_sync_static_uniforms()

## Base volumetric density multiplier.
@export_range(0.05, 5.0, 0.05) var base_density: float = 1.25:
	set(value):
		base_density = value
		if is_inside_tree():
			_sync_static_uniforms()

## Exponential vertical decay rate used when [member fog_mode] is [constant FogMode.CUSTOM].
@export_range(0.0, 10.0, 0.1) var custom_height_falloff: float = 3.2:
	set(value):
		custom_height_falloff = value
		if is_inside_tree() and fog_mode == FogMode.CUSTOM:
			_sync_static_uniforms()

## Normalized floor blanket thickness used in [constant FogMode.CUSTOM].
@export_range(0.0, 1.0, 0.02) var custom_ground_height: float = 0.28:
	set(value):
		custom_ground_height = value
		if is_inside_tree() and fog_mode == FogMode.CUSTOM:
			_sync_static_uniforms()

@export_category("Waves & Curl Advection")
## Speed of rolling billows and 3D curl noise evolution.
@export_range(0.0, 3.0, 0.05) var wave_speed: float = 0.38:
	set(value):
		wave_speed = value
		if is_inside_tree():
			_sync_static_uniforms()

## Spatial frequency of large rolling fog waves.
@export_range(0.05, 3.0, 0.05) var wave_scale: float = 0.35:
	set(value):
		wave_scale = value
		if is_inside_tree():
			_sync_static_uniforms()

## Spatial frequency of internal 3D fog clumps.
@export_range(0.1, 4.0, 0.05) var clump_scale: float = 0.75:
	set(value):
		clump_scale = value
		if is_inside_tree():
			_sync_static_uniforms()

## Sharpness between dense fog clumps and thin pockets.
@export_range(0.2, 3.0, 0.05) var clump_contrast: float = 1.45:
	set(value):
		clump_contrast = value
		if is_inside_tree():
			_sync_static_uniforms()

## Intensity of 3D curl-noise swirl when bullets or actors displace fog.
@export_range(0.0, 4.0, 0.05) var curl_advection_strength: float = 1.35:
	set(value):
		curl_advection_strength = value
		if is_inside_tree():
			_sync_static_uniforms()

@export_category("Interaction & Performance")
## Time in seconds for a carved bullet tunnel to swirl shut.
@export_range(0.3, 8.0, 0.1) var hole_regen_time: float = 3.8

## Physical clearing radius around walking characters and rigid bodies in meters.
@export_range(0.2, 3.0, 0.05) var actor_carve_radius: float = 0.85

## Trailing wake length multiplier behind moving actors.
@export_range(0.1, 1.5, 0.05) var wake_trail_scale: float = 0.45

## Maximum camera distance in meters before actor wake updates pause.
@export_range(5.0, 150.0, 1.0) var max_interaction_distance: float = 45.0

## Unique [ShaderMaterial] driving this fog instance.
var _shader_mat: ShaderMaterial

## Cached list of physics bodies currently inside [member interaction_area].
var _tracked_bodies: Array[Node3D] = []

## Previous frame world positions keyed by instance ID to derive velocity without allocations.
var _prev_positions: Dictionary[int, Vector3] = {}

## Smoothed world-space velocities keyed by instance ID for lingering wake decay.
var _smoothed_velocities: Dictionary[int, Vector3] = {}

## Pre-allocated uniform array storing bullet start positions and normalized life in W.
var _ray_starts: PackedVector4Array = PackedVector4Array()

## Pre-allocated uniform array storing bullet end positions and tunnel radius in W.
var _ray_ends: PackedVector4Array = PackedVector4Array()

## Remaining seconds for each of the 8 bullet/blast ray slots.
var _ray_timers: PackedFloat32Array = PackedFloat32Array()

## Initial duration for each of the 8 ray slots used to normalize decay progress.
var _ray_durations: PackedFloat32Array = PackedFloat32Array()

## Pre-allocated uniform array storing actor world positions and carve radius in W.
var _actor_positions: PackedVector4Array = PackedVector4Array()

## Pre-allocated uniform array storing actor velocities and wake trail scale in W.
var _actor_velocities: PackedVector4Array = PackedVector4Array()

## Ring-buffer write index for incoming bullet or explosion trajectories.
var _next_ray_slot: int = 0

## Count of bullet or explosion trajectories currently decaying.
var _live_ray_count: int = 0

## Cached count of moving actors uploaded on the previous frame to skip redundant uploads.
var _prev_active_actors: int = 0

## True when [member visibility_notifier] reports this volume is within a camera frustum.
var _is_on_screen: bool = true

## Cached last known volume size to sync child shapes when resized in the editor.
var _cached_size: Vector3 = Vector3.ZERO

## Area sensor tracking players, enemies, debris, and interactive props.
@onready var interaction_area: Area3D = get_node_or_null("InteractionArea") as Area3D

## Collision shape child inside [member interaction_area].
@onready var area_collision: CollisionShape3D = (
	get_node_or_null("InteractionArea/CollisionShape3D") as CollisionShape3D
)

## Frustum visibility sensor gating per-frame shader uniform uploads.
@onready var visibility_notifier: VisibleOnScreenNotifier3D = (
	get_node_or_null("VisibilityNotifier") as VisibleOnScreenNotifier3D
)


## Initializes buffers, validates child nodes, configures masks, and disables idle loops.
func _ready() -> void:
	_init_buffers()
	layers = RENDER_LAYER_VOLUMETRICS

	# shortcut: FogVolume is not a GeometryInstance3D, so instance uniforms are unavailable.
	if material is ShaderMaterial:
		_shader_mat = (material as ShaderMaterial).duplicate() as ShaderMaterial
		material = _shader_mat

	_sync_bounds()
	_apply_mode_parameters()

	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(true)
		return

	assert(is_instance_valid(interaction_area), "DynamicFogZone requires InteractionArea child.")
	assert(is_instance_valid(area_collision), "DynamicFogZone requires CollisionShape3D child.")
	assert(
		is_instance_valid(visibility_notifier), "DynamicFogZone requires VisibilityNotifier child."
	)
	assert(is_instance_valid(_shader_mat), "DynamicFogZone requires a valid ShaderMaterial.")

	interaction_area.collision_layer = 0
	interaction_area.collision_mask = ACTOR_COLLISION_MASK
	interaction_area.monitorable = false
	interaction_area.monitoring = true

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	visibility_notifier.screen_entered.connect(_on_screen_entered)
	visibility_notifier.screen_exited.connect(_on_screen_exited)

	_is_on_screen = visibility_notifier.is_on_screen()

	var smoke_mgr: Node = get_node_or_null("/root/SmokeManager")
	if is_instance_valid(smoke_mgr) and smoke_mgr.has_method("register_zone"):
		smoke_mgr.call(&"register_zone", self)

	set_process(false)
	set_physics_process(false)
	print("[DynamicFogZone] Initialized zone: ", name, " size: ", size)


## Disconnects physics/visibility signals and unregisters from [SmokeManager] on tree exit.
func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return

	if is_instance_valid(interaction_area):
		if interaction_area.body_entered.is_connected(_on_body_entered):
			interaction_area.body_entered.disconnect(_on_body_entered)
		if interaction_area.body_exited.is_connected(_on_body_exited):
			interaction_area.body_exited.disconnect(_on_body_exited)

	if is_instance_valid(visibility_notifier):
		if visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			visibility_notifier.screen_entered.disconnect(_on_screen_entered)
		if visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			visibility_notifier.screen_exited.disconnect(_on_screen_exited)

	_tracked_bodies.clear()
	_prev_positions.clear()
	_smoothed_velocities.clear()

	var smoke_mgr: Node = get_node_or_null("/root/SmokeManager")
	if is_instance_valid(smoke_mgr) and smoke_mgr.has_method("unregister_zone"):
		smoke_mgr.call(&"unregister_zone", self)


## Editor-only check keeping the [Area3D] and [VisibleOnScreenNotifier3D] matched to [member size].
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	if size != _cached_size:
		_sync_bounds()


## Advances bullet hole regeneration and actor velocity wakes only while active and visible.
func _physics_process(delta: float) -> void:
	if _live_ray_count > 0:
		_step_ray_decay(delta)

	if not _tracked_bodies.is_empty() and _is_within_camera_range():
		_step_actor_wakes(delta)

	if _live_ray_count == 0 and _tracked_bodies.is_empty():
		set_physics_process(false)


## Returns true if [param world_aabb] overlaps this fog volume's world-space bounding box.
func intersects_world_aabb(world_aabb: AABB) -> bool:
	var local_aabb: AABB = AABB(-size * 0.5, size)
	var zone_world_aabb: AABB = global_transform * local_aabb
	return zone_world_aabb.intersects(world_aabb)


## Computes optical depth along segment [param from] to [param to] for AI line-of-sight checks.
func get_segment_optical_depth(from: Vector3, to: Vector3) -> float:
	if not visible or base_density <= 0.05:
		return 0.0
	var inv_xform: Transform3D = global_transform.affine_inverse()
	var local_a: Vector3 = inv_xform * from
	var local_b: Vector3 = inv_xform * to
	var half_ext: Vector3 = size * 0.5
	var local_box: AABB = AABB(-half_ext, size)
	var hit: Variant = local_box.intersects_segment(local_a, local_b)
	if hit == null:
		return 0.0
	var mid_y: float = clampf(((local_a.y + local_b.y) * 0.5 / maxf(size.y, 0.1)) + 0.5, 0.0, 1.0)
	var ground_h: float = 0.25 if fog_mode == FogMode.GROUND_HUGGING else 0.95
	if fog_mode == FogMode.CUSTOM:
		ground_h = custom_ground_height
	if mid_y > ground_h + 0.2:
		return 0.0
	var dist: float = local_a.distance_to(local_b)
	return clampf(dist * base_density * 0.18, 0.0, 2.5)


## Records a new bullet trajectory into the 8-slot ring buffer and wakes decay processing.
func carve_bullet_ray(start_pos: Vector3, end_pos: Vector3, radius: float = 0.85) -> void:
	if not is_instance_valid(_shader_mat):
		return
	var scaled_r: float = clampf(maxf(radius * 1.55, 0.85), 0.85, 1.8)
	_record_carve_segment(start_pos, end_pos, scaled_r, hole_regen_time)
	print("[DynamicFogZone] Carved bullet tunnel in ", name, " slot: ", _next_ray_slot)


## Carves a spherical explosion blast cavity and radial shockwave in the fog volume.
func carve_explosion_sphere(center: Vector3, radius: float, duration: float = 4.0) -> void:
	if not is_instance_valid(_shader_mat):
		return
	var blast_r: float = clampf(radius * 0.9, 1.2, 5.0)
	var blast_start: Vector3 = center - Vector3(0.0, 0.05, 0.0)
	var blast_end: Vector3 = center + Vector3(0.0, 0.05, 0.0)
	_record_carve_segment(blast_start, blast_end, blast_r, maxf(duration, 0.3))
	print("[DynamicFogZone] Carved explosion blast in ", name, " slot: ", _next_ray_slot)


## Pre-allocates fixed-size uniform arrays once on startup to guarantee zero frame allocations.
func _init_buffers() -> void:
	_ray_starts.resize(MAX_RAYS)
	_ray_ends.resize(MAX_RAYS)
	_ray_timers.resize(MAX_RAYS)
	_ray_durations.resize(MAX_RAYS)
	_actor_positions.resize(MAX_ACTORS)
	_actor_velocities.resize(MAX_ACTORS)

	for i: int in range(MAX_RAYS):
		_ray_starts[i] = Vector4.ZERO
		_ray_ends[i] = Vector4.ZERO
		_ray_timers[i] = 0.0
		_ray_durations[i] = 1.0

	for i: int in range(MAX_ACTORS):
		_actor_positions[i] = Vector4.ZERO
		_actor_velocities[i] = Vector4.ZERO


## Writes or coalesces a carve segment in the ring buffer and uploads to the shader.
func _record_carve_segment(
	start_pos: Vector3, end_pos: Vector3, radius: float, duration: float
) -> void:
	for i: int in range(MAX_RAYS):
		if _is_fresh_matching_ray(i, start_pos, end_pos):
			var cur_end: Vector4 = _ray_ends[i]
			cur_end.w = minf(cur_end.w + 0.12, 2.0)
			_ray_ends[i] = cur_end
			_ray_timers[i] = maxf(_ray_timers[i], duration)
			_shader_mat.set_shader_parameter(PARAM_RAY_ENDS, _ray_ends)
			return

	var slot: int = _next_ray_slot
	_next_ray_slot = (_next_ray_slot + 1) % MAX_RAYS

	_ray_durations[slot] = maxf(duration, 0.1)
	_ray_timers[slot] = _ray_durations[slot]
	_ray_starts[slot] = Vector4(start_pos.x, start_pos.y, start_pos.z, 1.0)
	_ray_ends[slot] = Vector4(end_pos.x, end_pos.y, end_pos.z, radius)

	_live_ray_count = mini(_live_ray_count + 1, MAX_RAYS)
	_shader_mat.set_shader_parameter(PARAM_ACTIVE_RAYS, MAX_RAYS)
	_shader_mat.set_shader_parameter(PARAM_RAY_STARTS, _ray_starts)
	_shader_mat.set_shader_parameter(PARAM_RAY_ENDS, _ray_ends)
	_refresh_processing_state()


## Returns true if slot [param idx] was carved this frame along a near-identical trajectory.
func _is_fresh_matching_ray(idx: int, start_pos: Vector3, end_pos: Vector3) -> bool:
	var start_vec: Vector4 = _ray_starts[idx]
	if start_vec.w < 0.96:
		return false
	var existing_start: Vector3 = Vector3(start_vec.x, start_vec.y, start_vec.z)
	if existing_start.distance_squared_to(start_pos) > 0.25:
		return false
	var end_vec: Vector4 = _ray_ends[idx]
	var existing_end: Vector3 = Vector3(end_vec.x, end_vec.y, end_vec.z)
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(existing_end, start_pos, end_pos)
	return existing_end.distance_squared_to(closest) <= 0.65


## Resizes child [CollisionShape3D] and [VisibleOnScreenNotifier3D] to match [member size].
func _sync_bounds() -> void:
	_cached_size = size
	if is_instance_valid(area_collision):
		var box: BoxShape3D = area_collision.shape as BoxShape3D
		if not is_instance_valid(box):
			box = BoxShape3D.new()
			area_collision.shape = box
		box.size = size

	if is_instance_valid(visibility_notifier):
		visibility_notifier.aabb = AABB(-size * 0.5, size)


## Applies height falloff presets for Ground-Hugging vs Full-Room modes.
func _apply_mode_parameters() -> void:
	if not is_instance_valid(_shader_mat):
		return

	var target_falloff: float = custom_height_falloff
	var target_ground_h: float = custom_ground_height

	match fog_mode:
		FogMode.GROUND_HUGGING:
			target_falloff = 4.2
			target_ground_h = 0.25
		FogMode.FULL_ROOM:
			target_falloff = 0.15
			target_ground_h = 0.95
		FogMode.CUSTOM:
			target_falloff = custom_height_falloff
			target_ground_h = custom_ground_height

	_shader_mat.set_shader_parameter(PARAM_HEIGHT_FALLOFF, target_falloff)
	_shader_mat.set_shader_parameter(PARAM_GROUND_HEIGHT, target_ground_h)
	_sync_static_uniforms()


## Pushes static appearance and noise uniforms to the [ShaderMaterial].
func _sync_static_uniforms() -> void:
	if not is_instance_valid(_shader_mat):
		return
	_shader_mat.set_shader_parameter(PARAM_BASE_COLOR, albedo_color)
	_shader_mat.set_shader_parameter(PARAM_EMISSION_COLOR, emission_tint)
	_shader_mat.set_shader_parameter(PARAM_BASE_DENSITY, base_density)
	_shader_mat.set_shader_parameter(PARAM_EDGE_FADE, 0.12)
	_shader_mat.set_shader_parameter(PARAM_WAVE_SPEED, wave_speed)
	_shader_mat.set_shader_parameter(PARAM_WAVE_SCALE, wave_scale)
	_shader_mat.set_shader_parameter(PARAM_CLUMP_SCALE, clump_scale)
	_shader_mat.set_shader_parameter(PARAM_CLUMP_CONTRAST, clump_contrast)
	_shader_mat.set_shader_parameter(PARAM_CURL_STRENGTH, curl_advection_strength)


## Steps bullet and blast hole timers and uploads updated normalized strengths to the shader.
func _step_ray_decay(delta: float) -> void:
	var active_remaining: int = 0

	for i: int in range(MAX_RAYS):
		var remaining: float = _ray_timers[i]
		if remaining > 0.0:
			remaining = maxf(0.0, remaining - delta)
			_ray_timers[i] = remaining
			var start_vec: Vector4 = _ray_starts[i]
			start_vec.w = remaining / _ray_durations[i]
			_ray_starts[i] = start_vec
			if remaining > 0.0:
				active_remaining += 1

	_live_ray_count = active_remaining
	if is_instance_valid(_shader_mat):
		var shader_count: int = MAX_RAYS if _live_ray_count > 0 else 0
		_shader_mat.set_shader_parameter(PARAM_ACTIVE_RAYS, shader_count)
		_shader_mat.set_shader_parameter(PARAM_RAY_STARTS, _ray_starts)


## Computes smoothed actor velocities (gated at > 0.5 m/s) and skips idle uniform uploads.
func _step_actor_wakes(delta: float) -> void:
	var inv_delta: float = 1.0 / maxf(delta, 0.001)
	var count: int = mini(_tracked_bodies.size(), MAX_ACTORS)
	var valid_slot: int = 0

	for i: int in range(_tracked_bodies.size() - 1, -1, -1):
		var body: Node3D = _tracked_bodies[i]
		if not is_instance_valid(body):
			_tracked_bodies.remove_at(i)
			continue

		if valid_slot >= count:
			continue

		var inst_id: int = body.get_instance_id()
		var cur_pos: Vector3 = body.global_position + Vector3(0.0, 0.6, 0.0)
		var prev_pos: Vector3 = _prev_positions.get(inst_id, cur_pos)
		_prev_positions[inst_id] = cur_pos

		var raw_vel: Vector3 = (cur_pos - prev_pos) * inv_delta
		var target_vel: Vector3 = (
			raw_vel if raw_vel.length_squared() >= MIN_WAKE_SPEED_SQ else Vector3.ZERO
		)
		var prev_vel: Vector3 = _smoothed_velocities.get(inst_id, Vector3.ZERO)
		var smooth_vel: Vector3 = prev_vel.lerp(target_vel, clampf(delta * 8.0, 0.0, 1.0))
		_smoothed_velocities[inst_id] = smooth_vel

		if smooth_vel.length_squared() < 0.02:
			continue

		_actor_positions[valid_slot] = Vector4(cur_pos.x, cur_pos.y, cur_pos.z, actor_carve_radius)
		_actor_velocities[valid_slot] = Vector4(
			smooth_vel.x, smooth_vel.y, smooth_vel.z, wake_trail_scale
		)
		valid_slot += 1

	if is_instance_valid(_shader_mat) and (valid_slot > 0 or _prev_active_actors > 0):
		_shader_mat.set_shader_parameter(PARAM_ACTIVE_ACTORS, valid_slot)
		if valid_slot > 0:
			_shader_mat.set_shader_parameter(PARAM_ACTOR_POS, _actor_positions)
			_shader_mat.set_shader_parameter(PARAM_ACTOR_VEL, _actor_velocities)
	_prev_active_actors = valid_slot


## Checks squared distance from the active camera to gate distant fog physics.
func _is_within_camera_range() -> bool:
	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return false
	var cam: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(cam):
		return true
	var max_dist_sq: float = max_interaction_distance * max_interaction_distance
	return global_position.distance_squared_to(cam.global_position) <= max_dist_sq


## Enables or disables [_physics_process] based on visibility and active interactions.
func _refresh_processing_state() -> void:
	var should_process: bool = (
		_is_on_screen and (_live_ray_count > 0 or not _tracked_bodies.is_empty())
	)
	set_physics_process(should_process)


## Registers a physics body entering the fog zone and wakes physics processing.
func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body) or _tracked_bodies.has(body):
		return
	_tracked_bodies.append(body)
	var inst_id: int = body.get_instance_id()
	_prev_positions[inst_id] = body.global_position + Vector3(0.0, 0.6, 0.0)
	_smoothed_velocities[inst_id] = Vector3.ZERO
	print("[DynamicFogZone] Body entered fog (", name, "): ", body.name)
	_refresh_processing_state()


## Removes a physics body exiting the fog zone and clears its wake slot if empty.
func _on_body_exited(body: Node3D) -> void:
	var idx: int = _tracked_bodies.find(body)
	if idx != -1:
		_tracked_bodies.remove_at(idx)
	if is_instance_valid(body):
		var inst_id: int = body.get_instance_id()
		_prev_positions.erase(inst_id)
		_smoothed_velocities.erase(inst_id)
		print("[DynamicFogZone] Body exited fog (", name, "): ", body.name)

	if _tracked_bodies.is_empty() and is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_ACTIVE_ACTORS, 0)
		_prev_active_actors = 0
	_refresh_processing_state()


## Resumes physics processing when the fog zone enters the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	print("[DynamicFogZone] Entered screen frustum: ", name)
	_refresh_processing_state()


## Suspends physics processing when the fog zone leaves the camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	set_physics_process(false)
	print("[DynamicFogZone] Exited screen frustum: ", name)
