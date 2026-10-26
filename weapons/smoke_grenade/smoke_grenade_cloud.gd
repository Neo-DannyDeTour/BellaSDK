## Volumetric CS2-style smoke cloud using a wall-conforming multi-lobe [FogVolume] SDF.
class_name SmokeGrenadeCloud
extends FogVolume

## Render layer bitmask for Layer 10 (Volumetrics).
const LAYER_VOLUMETRICS: int = 1 << 9

## Maximum simultaneous bullet and explosion carve slots in the shader ring buffer.
const MAX_RAYS: int = 8

## Total number of raycasted wall-conforming SDF lobes forming the cloud volume.
const LOBE_COUNT: int = 10

## Minimum tunnel radius in meters carved by bullets through the smoke plume.
const DEFAULT_MIN_BULLET_RADIUS: float = 1.15

## Fallback fog shader resource applied when no material is assigned in the scene.
const SMOKE_SHADER: Shader = preload("res://weapons/smoke_grenade/smoke_grenade_cloud.gdshader")

## Pre-allocated uniform [StringName] for bloom expansion progress.
const PARAM_EXPANSION: StringName = &"expansion_progress"

## Pre-allocated uniform [StringName] for cloud fade-out alpha.
const PARAM_DISSIPATION: StringName = &"dissipation_alpha"

## Pre-allocated uniform [StringName] for the 10 wall-conforming lobe spheres.
const PARAM_LOBES: StringName = &"lobe_spheres"

## Pre-allocated uniform [StringName] for active bullet or blast ray count.
const PARAM_ACTIVE_RAYS: StringName = &"active_ray_count"

## Pre-allocated uniform [StringName] for ray start coordinates and normalized life.
const PARAM_RAY_STARTS: StringName = &"ray_starts"

## Pre-allocated uniform [StringName] for ray end coordinates and carve radius.
const PARAM_RAY_ENDS: StringName = &"ray_ends"

## Unit directions sampled during detonation to conform smoke lobes against walls.
const LOBE_DIRS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3.UP,
	Vector3(0.707107, 0.0, -0.707107),
	Vector3(-0.707107, 0.0, -0.707107),
	Vector3(0.707107, 0.0, 0.707107),
	Vector3(-0.707107, 0.0, 0.707107),
]

## Maximum outer radius of the smoke plume in meters.
@export var max_radius: float = 4.4

## Total active hold duration in seconds before dissipation begins.
@export var smoke_duration: float = 15.0

## Duration in seconds for a carved bullet tunnel to stay open and swirl shut.
@export var hole_regen_time: float = 4.2

## Minimum carve radius in meters applied to hitscan shots piercing the cloud.
@export var min_bullet_radius: float = DEFAULT_MIN_BULLET_RADIUS

## Unique [ShaderMaterial] instance driving this volumetric smoke cloud.
var _shader_mat: ShaderMaterial

## World-space bounding box used for fast raycast and AABB overlap checks.
var _world_aabb: AABB = AABB()

## Pre-allocated uniform array storing world lobe centers (XYZ) and radii (W).
var _lobe_spheres: PackedVector4Array = PackedVector4Array()

## Pre-allocated uniform array storing bullet/blast starts (XYZ) and normalized life (W).
var _ray_starts: PackedVector4Array = PackedVector4Array()

## Pre-allocated uniform array storing bullet/blast ends (XYZ) and radius (W).
var _ray_ends: PackedVector4Array = PackedVector4Array()

## Remaining seconds for each of the 8 carve slots.
var _ray_timers: PackedFloat32Array = PackedFloat32Array()

## Initial total duration for each of the 8 carve slots to normalize decay.
var _ray_durations: PackedFloat32Array = PackedFloat32Array()

## Circular buffer index for the next bullet or explosion carve slot.
var _next_ray_slot: int = 0

## Number of currently decaying bullet or explosion cavities.
var _live_ray_count: int = 0

## Current expansion scale multiplier cached for AI line-of-sight checks.
var _current_expansion: float = 0.05

## Current dissipation alpha cached for AI line-of-sight checks.
var _current_dissipation: float = 1.0

## True when [member _notifier] reports this cloud is inside the camera frustum.
var _is_on_screen: bool = true

## Active tween driving expansion bloom and final dissipation.
var _lifecycle_tween: Tween

## Visibility notifier gating off-screen shader parameter updates.
@onready var _notifier: VisibleOnScreenNotifier3D = (
	get_node_or_null("VisibleOnScreenNotifier3D") as VisibleOnScreenNotifier3D
)


## Initializes buffers, raycasts wall-conforming lobes, registers with [SmokeManager], and blooms.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_notifier), "SmokeGrenadeCloud requires VisibleOnScreenNotifier3D.")

	_init_buffers()
	layers = LAYER_VOLUMETRICS

	# shortcut: FogVolume is not a GeometryInstance3D, so instance uniforms are unavailable.
	if material is ShaderMaterial:
		_shader_mat = (material as ShaderMaterial).duplicate() as ShaderMaterial
	else:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = SMOKE_SHADER
	material = _shader_mat

	var vol_size: Vector3 = Vector3(max_radius * 2.5, max_radius * 1.65, max_radius * 2.5)
	size = vol_size
	var half_ext: Vector3 = vol_size * 0.5
	_world_aabb = AABB(global_position - half_ext, vol_size)
	_notifier.aabb = AABB(-half_ext, vol_size)

	_notifier.screen_entered.connect(_on_screen_entered)
	_notifier.screen_exited.connect(_on_screen_exited)
	_is_on_screen = _notifier.is_on_screen()

	_build_conforming_lobes()
	_shader_mat.set_shader_parameter(PARAM_EXPANSION, 0.05)
	_shader_mat.set_shader_parameter(PARAM_DISSIPATION, 1.0)
	_shader_mat.set_shader_parameter(PARAM_ACTIVE_RAYS, 0)

	var smoke_mgr: Node = get_node_or_null("/root/SmokeManager")
	if is_instance_valid(smoke_mgr) and smoke_mgr.has_method(&"register_cloud"):
		smoke_mgr.call(&"register_cloud", self)

	_start_lifecycle()
	print("[SmokeGrenadeCloud] Volumetric plume spawned at: ", global_position)


## Unregisters from [SmokeManager] and cleans up signals and tweens on tree exit.
func _exit_tree() -> void:
	if is_instance_valid(_notifier):
		if _notifier.screen_entered.is_connected(_on_screen_entered):
			_notifier.screen_entered.disconnect(_on_screen_entered)
		if _notifier.screen_exited.is_connected(_on_screen_exited):
			_notifier.screen_exited.disconnect(_on_screen_exited)

	var smoke_mgr: Node = get_node_or_null("/root/SmokeManager")
	if is_instance_valid(smoke_mgr) and smoke_mgr.has_method(&"unregister_cloud"):
		smoke_mgr.call(&"unregister_cloud", self)

	Utilities.safe_kill_tween(_lifecycle_tween)


## Steps bullet and blast cavity regeneration while active and visible.
func _physics_process(delta: float) -> void:
	if _live_ray_count > 0:
		_step_ray_decay(delta)

	if _live_ray_count == 0:
		set_physics_process(false)


## Returns true if [param query_aabb] overlaps this smoke cloud's world bounds.
func intersects_world_aabb(query_aabb: AABB) -> bool:
	return _world_aabb.intersects(query_aabb)


## Returns true if this active smoke cloud blocks AI vision along ray [param from] to [param to].
func is_line_of_sight_obscured(from: Vector3, to: Vector3) -> bool:
	if not visible or _current_dissipation <= 0.2:
		return false
	var closest_pt: Vector3 = Geometry3D.get_closest_point_to_segment(global_position, from, to)
	var effective_radius: float = max_radius * _current_expansion * 0.88
	return global_position.distance_squared_to(closest_pt) <= (effective_radius * effective_radius)


## Carves a wide, long-lasting CS2-style bullet tunnel through the volumetric smoke cloud.
func carve_bullet_ray(start_pos: Vector3, end_pos: Vector3, radius: float = 0.55) -> void:
	if not is_instance_valid(_shader_mat):
		return

	var closest_pt: Vector3 = Geometry3D.get_closest_point_to_segment(
		global_position, start_pos, end_pos
	)
	var scaled_r: float = clampf(maxf(radius * 2.1, min_bullet_radius), min_bullet_radius, 2.2)
	var max_reach: float = (max_radius * 1.35) + scaled_r
	if global_position.distance_squared_to(closest_pt) > (max_reach * max_reach):
		return

	_record_carve_segment(start_pos, end_pos, scaled_r, hole_regen_time)
	print("[SmokeGrenadeCloud] Carved bullet tunnel in slot: ", _next_ray_slot)


## Carves a radial shockwave blast cavity through the cloud when caught in an explosion.
func carve_explosion_sphere(center: Vector3, radius: float, duration: float = 4.5) -> void:
	if not is_instance_valid(_shader_mat):
		return
	var max_reach: float = (max_radius * 1.35) + radius
	if global_position.distance_squared_to(center) > (max_reach * max_reach):
		return

	var blast_r: float = clampf(radius * 0.95, 1.8, 5.0)
	var blast_start: Vector3 = center - Vector3(0.0, 0.05, 0.0)
	var blast_end: Vector3 = center + Vector3(0.0, 0.05, 0.0)
	_record_carve_segment(blast_start, blast_end, blast_r, maxf(duration, 0.5))
	print("[SmokeGrenadeCloud] Carved explosion shockwave in slot: ", _next_ray_slot)


## Pre-allocates fixed-size uniform buffers once on startup to guarantee zero frame allocations.
func _init_buffers() -> void:
	_lobe_spheres.resize(LOBE_COUNT)
	_ray_starts.resize(MAX_RAYS)
	_ray_ends.resize(MAX_RAYS)
	_ray_timers.resize(MAX_RAYS)
	_ray_durations.resize(MAX_RAYS)

	for i: int in range(LOBE_COUNT):
		_lobe_spheres[i] = Vector4.ZERO

	for i: int in range(MAX_RAYS):
		_ray_starts[i] = Vector4.ZERO
		_ray_ends[i] = Vector4.ZERO
		_ray_timers[i] = 0.0
		_ray_durations[i] = 1.0


## Raycasts 10 directions against solid world geometry so smoke lobes deflect off walls/floors.
func _build_conforming_lobes() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3(0.0, 0.5, 0.0)

	for i: int in range(LOBE_COUNT):
		var dir: Vector3 = LOBE_DIRS[i]
		var lobe_pos: Vector3 = origin
		var lobe_rad: float = max_radius * 0.64

		if dir != Vector3.ZERO:
			var max_dist: float = max_radius * 0.74
			var target: Vector3 = origin + dir * max_dist
			var hit: Dictionary = Utilities.raycast_3d(
				space_state, origin, target, Types.MASK_SOLID_WORLD
			)
			var clear_dist: float = max_dist
			if not hit.is_empty():
				var hit_pos: Vector3 = hit.get("position", target)
				clear_dist = maxf(0.35, origin.distance_to(hit_pos) - 0.35)

			lobe_pos = origin + dir * (clear_dist * 0.6)
			lobe_rad = clampf(clear_dist * 0.65, 1.05, max_radius * 0.58)

		_lobe_spheres[i] = Vector4(lobe_pos.x, lobe_pos.y, lobe_pos.z, lobe_rad)

	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_LOBES, _lobe_spheres)


## Writes or coalesces a bullet/blast segment in the 8-slot ring buffer and wakes decay.
func _record_carve_segment(
	start_pos: Vector3, end_pos: Vector3, radius: float, duration: float
) -> void:
	for i: int in range(MAX_RAYS):
		if _is_fresh_matching_ray(i, start_pos, end_pos):
			var cur_end: Vector4 = _ray_ends[i]
			cur_end.w = minf(cur_end.w + 0.14, 2.35)
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


## Animates fast CS2-style expansion, hold duration, and final dissipation.
func _start_lifecycle() -> void:
	_lifecycle_tween = Utilities.reset_tween_ext(
		self, _lifecycle_tween, Tween.TRANS_EXPO, Tween.EASE_OUT
	)
	if not is_instance_valid(_lifecycle_tween):
		return

	_lifecycle_tween.tween_method(_set_expansion_progress, 0.05, 1.0, 0.8)
	_lifecycle_tween.tween_interval(smoke_duration)
	_lifecycle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_lifecycle_tween.tween_method(_set_dissipation_alpha, 1.0, 0.0, 2.2)
	_lifecycle_tween.tween_callback(queue_free)


## Updates expansion progress uniform and cached radius scale.
func _set_expansion_progress(val: float) -> void:
	_current_expansion = val
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_EXPANSION, val)


## Updates dissipation alpha uniform and cached visibility state.
func _set_dissipation_alpha(val: float) -> void:
	_current_dissipation = val
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_DISSIPATION, val)


## Steps bullet and explosion cavity timers and uploads normalized strengths to the shader.
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


## Enables or disables [_physics_process] based on visibility and active holes.
func _refresh_processing_state() -> void:
	var should_process: bool = _is_on_screen and _live_ray_count > 0
	set_physics_process(should_process)


## Resumes physics processing when the smoke cloud enters the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_refresh_processing_state()


## Suspends physics processing when the smoke cloud leaves the camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	set_physics_process(false)
