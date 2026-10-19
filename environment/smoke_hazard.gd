@tool
## Volumetric environmental smoke hazard with multi-shade billowing plumes, radial suffocation
## buildup, hitscan/explosion carving, actor wakes, and AI line-of-sight obstruction.
class_name SmokeHazard
extends FogVolume

## Emitted when an entity takes a tick of suffocation/toxicity damage inside the smoke cloud.
signal damage_ticked(target: Node3D, amount: float)

## Maximum simultaneous bullet/explosion trajectories tracked in the shader ring buffer.
const MAX_RAYS: int = 8

## Maximum simultaneous physics bodies displacing the smoke volume.
const MAX_ACTORS: int = 8

## Render Layer 10 bitmask reserved for volumetric effects.
const RENDER_LAYER_VOLUMETRICS: int = CollisionLayers.RENDER_MASK_VOLUMETRICS

## Physics bitmask detecting Player (2), Interactive (3), Debris (4), and Enemies (5).
const ACTOR_COLLISION_MASK: int = (
	CollisionLayers.MASK_PLAYER
	| CollisionLayers.MASK_INTERACTIVE
	| CollisionLayers.MASK_DEBRIS
	| CollisionLayers.MASK_ENEMIES
)

## Pre-allocated shader uniform [StringName] constants for zero-allocation updates.
const PARAM_DARK_GREY: StringName = &"color_dark_grey"
const PARAM_MID_GREY: StringName = &"color_mid_grey"
const PARAM_LIGHT_ASH: StringName = &"color_light_ash"
const PARAM_EMISSION_TINT: StringName = &"emission_tint"
const PARAM_BASE_DENSITY: StringName = &"base_density"
const PARAM_PHASE_ALPHA: StringName = &"phase_alpha"
const PARAM_CORE_RATIO: StringName = &"core_radius_ratio"
const PARAM_EDGE_SOFTNESS: StringName = &"edge_softness"
const PARAM_BILLOW_SCALE: StringName = &"billow_scale"
const PARAM_DETAIL_SCALE: StringName = &"detail_scale"
const PARAM_PLUME_CONTRAST: StringName = &"plume_contrast"
const PARAM_TURBULENCE_SPEED: StringName = &"turbulence_speed"
const PARAM_CURL_STRENGTH: StringName = &"curl_strength"
const PARAM_WIND_INFLUENCE: StringName = &"wind_influence"
const PARAM_ACTIVE_RAYS: StringName = &"active_ray_count"
const PARAM_RAY_STARTS: StringName = &"ray_starts"
const PARAM_RAY_ENDS: StringName = &"ray_ends"
const PARAM_ACTIVE_ACTORS: StringName = &"active_actor_count"
const PARAM_ACTOR_POS: StringName = &"actor_positions"
const PARAM_ACTOR_VEL: StringName = &"actor_velocities"

@export_group("Hazard Exposure & Damage")
## Minimum damage dealt per tick once exposure crosses [member suffocation_threshold].
@export var min_damage_per_tick: float = 4.0

## Maximum damage dealt per tick at full (1.0) suffocation exposure.
@export var max_damage_per_tick: float = 18.0

## Time in seconds between consecutive damage ticks once suffocating.
@export_range(0.1, 3.0, 0.05) var tick_rate: float = 0.5

## Rate per second at which suffocation exposure builds up at the dense core.
@export_range(0.05, 3.0, 0.05) var exposure_buildup_rate: float = 0.45

## Rate per second at which exposure recovers when outside or at the edge.
@export_range(0.05, 3.0, 0.05) var exposure_decay_rate: float = 0.35

## Normalized exposure threshold (0.0 to 1.0) before health damage ticks begin.
@export_range(0.05, 0.95, 0.05) var suffocation_threshold: float = 0.35

## Normalized core radius ratio where smoke concentration is at 100%.
@export_range(0.05, 0.9, 0.05) var core_radius_ratio: float = 0.38:
	set(value):
		core_radius_ratio = value
		if is_inside_tree():
			_sync_static_uniforms()

## Enables environment raycast occlusion (Layer 1) to stop hazard buildup through walls.
@export var check_wall_occlusion: bool = true

@export_group("Emission Lifecycle")
## When true, the smoke hazard pulses between active venting and paused dissipation phases.
@export var cycle_enabled: bool = false

## Duration in seconds the smoke cloud remains at full density during a cycle.
@export_range(0.5, 30.0, 0.5) var active_duration: float = 4.0

## Duration in seconds the smoke cloud pauses between active bursts.
@export_range(0.5, 30.0, 0.5) var pause_duration: float = 2.5

## Transition time in seconds when fading smoke density in or out.
@export_range(0.1, 5.0, 0.1) var phase_transition_time: float = 0.8

@export_group("Volumetric Multi-Shade Appearance")
## Deep charcoal grey shade used in the dense turbulent core.
@export var color_dark_grey: Color = Color(0.16, 0.17, 0.19, 1.0):
	set(value):
		color_dark_grey = value
		if is_inside_tree():
			_sync_static_uniforms()

## Mid-tone slate grey shade across billowing body layers.
@export var color_mid_grey: Color = Color(0.44, 0.46, 0.49, 1.0):
	set(value):
		color_mid_grey = value
		if is_inside_tree():
			_sync_static_uniforms()

## Light ash grey highlight shade along upper plumes and sheared rims.
@export var color_light_ash: Color = Color(0.76, 0.78, 0.81, 1.0):
	set(value):
		color_light_ash = value
		if is_inside_tree():
			_sync_static_uniforms()

## Subtle self-illumination tint to preserve depth in unlit corners.
@export var emission_tint: Color = Color(0.04, 0.05, 0.06, 1.0):
	set(value):
		emission_tint = value
		if is_inside_tree():
			_sync_static_uniforms()

## Master volumetric density multiplier.
@export_range(0.1, 8.0, 0.05) var base_density: float = 2.6:
	set(value):
		base_density = value
		if is_inside_tree():
			_sync_static_uniforms()

## Organic domain-warping softness at the outer boundary of the plume.
@export_range(0.05, 0.8, 0.02) var edge_softness: float = 0.42:
	set(value):
		edge_softness = value
		if is_inside_tree():
			_sync_static_uniforms()

## Spatial frequency of large rolling smoke billows.
@export_range(0.1, 4.0, 0.05) var billow_scale: float = 0.85:
	set(value):
		billow_scale = value
		if is_inside_tree():
			_sync_static_uniforms()

## Spatial frequency of fine internal turbulence detail.
@export_range(0.2, 8.0, 0.05) var detail_scale: float = 2.15:
	set(value):
		detail_scale = value
		if is_inside_tree():
			_sync_static_uniforms()

## Contrast between dense soot pockets and thin vapor gaps.
@export_range(0.3, 3.5, 0.05) var plume_contrast: float = 1.55:
	set(value):
		plume_contrast = value
		if is_inside_tree():
			_sync_static_uniforms()

## Speed of upward thermal convection and curl swirl.
@export_range(0.0, 3.0, 0.05) var turbulence_speed: float = 0.48:
	set(value):
		turbulence_speed = value
		if is_inside_tree():
			_sync_static_uniforms()

## Intensity of 3D curl-noise advection and projectile displacement.
@export_range(0.0, 4.0, 0.05) var curl_strength: float = 1.55:
	set(value):
		curl_strength = value
		if is_inside_tree():
			_sync_static_uniforms()

## Multiplier for how strongly global wind shears the smoke plume.
@export_range(0.0, 3.0, 0.05) var wind_influence: float = 0.85:
	set(value):
		wind_influence = value
		if is_inside_tree():
			_sync_static_uniforms()

@export_group("Interaction & Occlusion")
## Time in seconds for a carved bullet tunnel to swirl shut.
@export_range(0.3, 8.0, 0.1) var hole_regen_time: float = 2.4

## Physical clearing radius around walking characters and rigid bodies in meters.
@export_range(0.2, 3.0, 0.05) var actor_carve_radius: float = 0.85

## Trailing wake length multiplier behind moving actors.
@export_range(0.1, 1.5, 0.05) var wake_trail_scale: float = 0.45

## Maximum camera distance in meters before actor wake updates pause.
@export_range(5.0, 150.0, 1.0) var max_interaction_distance: float = 45.0

## Optical density multiplier per meter for AI line-of-sight obstruction rays.
@export_range(0.0, 2.0, 0.05) var ai_occlusion_weight: float = 0.45

@export_group("Trigger Debug Visualizer")
## Toggles visibility of debug trigger shape in runtime builds.
@export var show_visualizer_in_game: bool = false:
	set(value):
		show_visualizer_in_game = value
		if is_inside_tree():
			_sync_bounds()

## Color and transparency of editor debug trigger shape.
@export var visualizer_color: Color = Color(0.55, 0.58, 0.62, 0.22):
	set(value):
		visualizer_color = value
		if is_inside_tree():
			_sync_bounds()

## Edge color applied to the wireframe bounding cage and orientation arrow.
@export var outline_color: Color = Color(0.82, 0.85, 0.9, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_sync_bounds()

## Text label displayed on editor debug shape.
@export var visualizer_text: String = "SMOKE HAZARD":
	set(value):
		visualizer_text = value
		if is_inside_tree():
			_sync_bounds()

## Unique [ShaderMaterial] driving this volumetric smoke instance.
var _shader_mat: ShaderMaterial

## Physics bodies currently overlapping [member hazard_area].
var _overlapping_bodies: Array[Node3D] = []

## Entities with active > 0 suffocation exposure (persists briefly after exit to decay).
var _exposed_entities: Array[Node3D] = []

## Maps entity instance ID to normalized suffocation exposure [0.0, 1.0].
var _exposure_map: Dictionary[int, float] = {}

## Maps entity instance ID to resolved [HealthComponent] reference.
var _health_cache: Dictionary[int, HealthComponent] = {}

## Previous frame world positions keyed by instance ID to derive velocity without allocations.
var _prev_positions: Dictionary[int, Vector3] = {}

## Smoothed world-space velocities keyed by instance ID for lingering wake decay.
var _smoothed_velocities: Dictionary[int, Vector3] = {}

## Pre-allocated uniform array storing bullet start positions and normalized life in W.
var _ray_starts: PackedVector4Array = PackedVector4Array()

## Pre-allocated uniform array storing bullet end positions and tunnel radius in W.
var _ray_ends: PackedVector4Array = PackedVector4Array()

## Remaining seconds for each of the 8 bullet/explosion carve slots.
var _ray_timers: PackedFloat32Array = PackedFloat32Array()

## Initial duration for each of the 8 bullet/explosion carve slots.
var _ray_max_durations: PackedFloat32Array = PackedFloat32Array()

## Pre-allocated uniform array storing actor world positions and carve radius in W.
var _actor_positions: PackedVector4Array = PackedVector4Array()

## Pre-allocated uniform array storing actor velocities and wake trail scale in W.
var _actor_velocities: PackedVector4Array = PackedVector4Array()

## Ring-buffer write index for incoming bullet or explosion trajectories.
var _next_ray_slot: int = 0

## Count of bullet/explosion trajectories currently decaying.
var _live_ray_count: int = 0

## True when [member visibility_notifier] reports this volume is within a camera frustum.
var _is_on_screen: bool = true

## True when the hazard is in its active emitting phase.
var _is_active: bool = true

## Current interpolated phase multiplier [0.0, 1.0] driven by cycle tweens.
var _phase_alpha: float = 1.0

## Elapsed seconds in the current active or paused cycle phase.
var _phase_timer: float = 0.0

## Elapsed seconds toward the next suffocation damage tick.
var _tick_timer: float = 0.0

## Tracks whether the local player is currently registered inside this smoke volume.
var _is_player_inside: bool = false

## Tracks last emitted player exposure value to throttle HUD update signals.
var _last_emitted_exposure: float = -1.0

## Cached last known volume size to sync child shapes when resized in the editor.
var _cached_size: Vector3 = Vector3.ZERO

## Active tween animating phase density transitions.
var _phase_tween: Tween

## Area sensor tracking players, enemies, debris, and interactive props.
@onready var hazard_area: Area3D = get_node_or_null("HazardArea") as Area3D

## Collision shape child inside [member hazard_area].
@onready var area_collision: CollisionShape3D = (
	get_node_or_null("HazardArea/CollisionShape3D") as CollisionShape3D
)

## Frustum visibility sensor gating per-frame shader uniform uploads.
@onready var visibility_notifier: VisibleOnScreenNotifier3D = (
	get_node_or_null("VisibilityNotifier") as VisibleOnScreenNotifier3D
)

## Editor wireframe and metric gizmo visualizer.
@onready var visualizer: EditorTriggerVisualizer = (
	get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
)


## Initializes uniform buffers, configures masks, registers with [SmokeManager], and sleeps if idle.
func _ready() -> void:
	_init_buffers()
	layers = RENDER_LAYER_VOLUMETRICS

	# shortcut: FogVolume is not a GeometryInstance3D, so instance uniforms are unavailable.
	if material is ShaderMaterial:
		_shader_mat = (material as ShaderMaterial).duplicate() as ShaderMaterial
		material = _shader_mat

	_sync_bounds()
	_sync_static_uniforms()

	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(true)
		return

	assert(is_instance_valid(hazard_area), "SmokeHazard requires HazardArea child.")
	assert(is_instance_valid(area_collision), "SmokeHazard requires CollisionShape3D child.")
	assert(is_instance_valid(visibility_notifier), "SmokeHazard requires VisibilityNotifier child.")
	assert(is_instance_valid(_shader_mat), "SmokeHazard requires a valid ShaderMaterial.")

	hazard_area.collision_layer = CollisionLayers.MASK_NONE
	hazard_area.collision_mask = ACTOR_COLLISION_MASK
	hazard_area.monitorable = true
	hazard_area.monitoring = true

	hazard_area.body_entered.connect(_on_body_entered)
	hazard_area.body_exited.connect(_on_body_exited)
	visibility_notifier.screen_entered.connect(_on_screen_entered)
	visibility_notifier.screen_exited.connect(_on_screen_exited)

	_is_on_screen = visibility_notifier.is_on_screen()

	var smoke_mgr: Node = get_node_or_null("/root/SmokeManager")
	if is_instance_valid(smoke_mgr) and smoke_mgr.has_method(&"register_zone"):
		smoke_mgr.call(&"register_zone", self)

	set_process(false)
	_refresh_processing_state()
	print("[SmokeHazard] Initialized volumetric hazard at ", global_position)


## Unregisters from [SmokeManager] and clears player HUD state if removed while occupied.
func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(_phase_tween):
		_phase_tween.kill()
	if _is_player_inside:
		_is_player_inside = false
		Events.smoke_hazard_changed.emit(false, 0.0)
	var smoke_mgr: Node = get_node_or_null("/root/SmokeManager")
	if is_instance_valid(smoke_mgr) and smoke_mgr.has_method(&"unregister_zone"):
		smoke_mgr.call(&"unregister_zone", self)


## Editor-only check keeping child shapes matched to [member size].
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	if size != _cached_size:
		_sync_bounds()


## Advances cycle timers, exposure buildup/decay, suffocation ticks, and volumetric wakes.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if cycle_enabled:
		_step_cycle(delta)

	if _live_ray_count > 0:
		_step_ray_decay(delta)

	if not _overlapping_bodies.is_empty() and _is_on_screen and _is_within_camera_range():
		_step_actor_wakes(delta)

	if not _overlapping_bodies.is_empty() or not _exposed_entities.is_empty():
		_step_exposure_and_damage(delta)

	if (
		not cycle_enabled
		and _live_ray_count == 0
		and _overlapping_bodies.is_empty()
		and _exposed_entities.is_empty()
	):
		set_physics_process(false)


## Returns true if [param world_aabb] overlaps this smoke volume's world-space bounding box.
func intersects_world_aabb(world_aabb: AABB) -> bool:
	var local_aabb: AABB = AABB(-size * 0.5, size)
	var zone_world_aabb: AABB = global_transform * local_aabb
	return zone_world_aabb.intersects(world_aabb)


## Records a new bullet trajectory into the 8-slot ring buffer and wakes decay processing.
func carve_bullet_ray(start_pos: Vector3, end_pos: Vector3, radius: float = 0.55) -> void:
	_record_carve_segment(start_pos, end_pos, radius, hole_regen_time)


## Carves a spherical blast cavity in the smoke volume from an explosion at [param center].
func carve_explosion_sphere(center: Vector3, radius: float, duration: float = 3.5) -> void:
	var half_span: Vector3 = Vector3(0.0, 0.05, 0.0)
	_record_carve_segment(center - half_span, center + half_span, radius, duration)
	print("[SmokeHazard] Carved explosion cavity in ", name, " radius: ", radius)


## Computes integrated optical depth along segment [param from] -> [param to] for AI LoS checks.
func get_segment_optical_depth(from: Vector3, to: Vector3) -> float:
	if _phase_alpha <= 0.05 or base_density <= 0.05 or ai_occlusion_weight <= 0.001:
		return 0.0

	var inv_xf: Transform3D = global_transform.affine_inverse()
	var local_a: Vector3 = inv_xf * from
	var local_b: Vector3 = inv_xf * to
	var half_extents: Vector3 = (size * 0.5).max(Vector3(0.1, 0.1, 0.1))

	# Slab intersection test in local box [-half_extents, half_extents].
	var dir: Vector3 = local_b - local_a
	var t_min: float = 0.0
	var t_max: float = 1.0

	for axis: int in range(3):
		var a_val: float = local_a[axis]
		var d_val: float = dir[axis]
		var bound: float = half_extents[axis]
		if absf(d_val) < 0.00001:
			if absf(a_val) > bound:
				return 0.0
		else:
			var inv_d: float = 1.0 / d_val
			var t1: float = (-bound - a_val) * inv_d
			var t2: float = (bound - a_val) * inv_d
			if t1 > t2:
				var tmp: float = t1
				t1 = t2
				t2 = tmp
			t_min = maxf(t_min, t1)
			t_max = minf(t_max, t2)
			if t_min > t_max:
				return 0.0

	var world_seg_len: float = from.distance_to(to) * (t_max - t_min)
	if world_seg_len <= 0.05:
		return 0.0

	# 4-point midpoint quadrature along clipped segment inside the smoke volume.
	var step_count: int = 4
	var step_len: float = world_seg_len / float(step_count)
	var optical_depth: float = 0.0

	for s: int in range(step_count):
		var frac: float = lerpf(t_min, t_max, (float(s) + 0.5) / float(step_count))
		var sample_world: Vector3 = from.lerp(to, frac)
		var local_density: float = sample_density_at_world_pos(sample_world)
		optical_depth += local_density * base_density * ai_occlusion_weight * step_len

	return optical_depth


## Evaluates normalized [0.0, 1.0] smoke concentration at [param world_pos] including carved holes.
func sample_density_at_world_pos(world_pos: Vector3) -> float:
	if _phase_alpha <= 0.001:
		return 0.0

	var local_pos: Vector3 = to_local(world_pos)
	var half_extents: Vector3 = (size * 0.5).max(Vector3(0.1, 0.1, 0.1))
	var norm_vec: Vector3 = Vector3(
		local_pos.x / half_extents.x, local_pos.y / half_extents.y, local_pos.z / half_extents.z
	)
	var radial_dist: float = norm_vec.length()
	if radial_dist >= 1.0:
		return 0.0

	var radial_factor: float = 1.0 - smoothstep(core_radius_ratio, 1.0, radial_dist)
	var carve_mult: float = _evaluate_carve_transmittance(world_pos)
	return clampf(radial_factor * _phase_alpha * carve_mult, 0.0, 1.0)


## Records a segment or sphere carve into the shader ring buffer.
func _record_carve_segment(
	start_pos: Vector3, end_pos: Vector3, radius: float, duration: float
) -> void:
	if not is_instance_valid(_shader_mat):
		return

	var slot: int = _next_ray_slot
	_next_ray_slot = (_next_ray_slot + 1) % MAX_RAYS

	var safe_duration: float = maxf(duration, 0.1)
	_ray_timers[slot] = safe_duration
	_ray_max_durations[slot] = safe_duration
	_ray_starts[slot] = Vector4(start_pos.x, start_pos.y, start_pos.z, 1.0)
	_ray_ends[slot] = Vector4(end_pos.x, end_pos.y, end_pos.z, radius)

	_live_ray_count = mini(_live_ray_count + 1, MAX_RAYS)
	_shader_mat.set_shader_parameter(PARAM_ACTIVE_RAYS, MAX_RAYS)
	_shader_mat.set_shader_parameter(PARAM_RAY_STARTS, _ray_starts)
	_shader_mat.set_shader_parameter(PARAM_RAY_ENDS, _ray_ends)

	_refresh_processing_state()


## Evaluates how much carved bullet/explosion holes reduce density at [param world_pos].
func _evaluate_carve_transmittance(world_pos: Vector3) -> float:
	if _live_ray_count <= 0:
		return 1.0

	var transmittance: float = 1.0
	for i: int in range(MAX_RAYS):
		var life_strength: float = _ray_starts[i].w
		if life_strength <= 0.01:
			continue
		var start_p: Vector3 = Vector3(_ray_starts[i].x, _ray_starts[i].y, _ray_starts[i].z)
		var end_p: Vector3 = Vector3(_ray_ends[i].x, _ray_ends[i].y, _ray_ends[i].z)
		var radius: float = maxf(_ray_ends[i].w, 0.05)

		var ab: Vector3 = end_p - start_p
		var len_sq: float = maxf(ab.length_squared(), 0.00001)
		var t: float = clampf((world_pos - start_p).dot(ab) / len_sq, 0.0, 1.0)
		var closest: Vector3 = start_p + ab * t
		var dist: float = world_pos.distance_to(closest)

		if dist < radius * 1.2:
			var hole_core: float = smoothstep(radius * 0.3, radius * 1.15, dist)
			transmittance *= lerpf(1.0, hole_core, life_strength)

	return transmittance


## Pre-allocates fixed-size uniform arrays once on startup to guarantee zero frame allocations.
func _init_buffers() -> void:
	_ray_starts.resize(MAX_RAYS)
	_ray_ends.resize(MAX_RAYS)
	_ray_timers.resize(MAX_RAYS)
	_ray_max_durations.resize(MAX_RAYS)
	_actor_positions.resize(MAX_ACTORS)
	_actor_velocities.resize(MAX_ACTORS)

	for i: int in range(MAX_RAYS):
		_ray_starts[i] = Vector4.ZERO
		_ray_ends[i] = Vector4.ZERO
		_ray_timers[i] = 0.0
		_ray_max_durations[i] = 1.0

	for i: int in range(MAX_ACTORS):
		_actor_positions[i] = Vector4.ZERO
		_actor_velocities[i] = Vector4.ZERO


## Resizes child [CollisionShape3D], [VisibleOnScreenNotifier3D], and [EditorTriggerVisualizer].
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

	if is_instance_valid(visualizer):
		visualizer.shape_type = EditorTriggerVisualizer.ShapeType.BOX
		visualizer.trigger_size = size
		visualizer.trigger_color = visualizer_color
		visualizer.outline_color = outline_color
		visualizer.trigger_text = visualizer_text
		visualizer.show_in_game = show_visualizer_in_game


## Pushes static appearance and multi-shade grey uniforms to the [ShaderMaterial].
func _sync_static_uniforms() -> void:
	if not is_instance_valid(_shader_mat):
		return
	_shader_mat.set_shader_parameter(PARAM_DARK_GREY, color_dark_grey)
	_shader_mat.set_shader_parameter(PARAM_MID_GREY, color_mid_grey)
	_shader_mat.set_shader_parameter(PARAM_LIGHT_ASH, color_light_ash)
	_shader_mat.set_shader_parameter(PARAM_EMISSION_TINT, emission_tint)
	_shader_mat.set_shader_parameter(PARAM_BASE_DENSITY, base_density)
	_shader_mat.set_shader_parameter(PARAM_PHASE_ALPHA, _phase_alpha)
	_shader_mat.set_shader_parameter(PARAM_CORE_RATIO, core_radius_ratio)
	_shader_mat.set_shader_parameter(PARAM_EDGE_SOFTNESS, edge_softness)
	_shader_mat.set_shader_parameter(PARAM_BILLOW_SCALE, billow_scale)
	_shader_mat.set_shader_parameter(PARAM_DETAIL_SCALE, detail_scale)
	_shader_mat.set_shader_parameter(PARAM_PLUME_CONTRAST, plume_contrast)
	_shader_mat.set_shader_parameter(PARAM_TURBULENCE_SPEED, turbulence_speed)
	_shader_mat.set_shader_parameter(PARAM_CURL_STRENGTH, curl_strength)
	_shader_mat.set_shader_parameter(PARAM_WIND_INFLUENCE, wind_influence)


## Advances pulsing active/pause phases when [member cycle_enabled] is enabled.
func _step_cycle(delta: float) -> void:
	_phase_timer += delta
	if _is_active and _phase_timer >= active_duration:
		_set_hazard_phase(false)
	elif not _is_active and _phase_timer >= pause_duration:
		_set_hazard_phase(true)


## Transitions between active venting and paused phase using a smooth [Tween].
func _set_hazard_phase(active: bool) -> void:
	_is_active = active
	_phase_timer = 0.0
	print("[SmokeHazard] Phase state changed -> active = ", active)

	if is_instance_valid(_phase_tween):
		_phase_tween.kill()

	var target_alpha: float = 1.0 if active else 0.0
	_phase_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_phase_tween.tween_method(_set_phase_alpha, _phase_alpha, target_alpha, phase_transition_time)


## Updates phase density multiplier and syncs to shader.
func _set_phase_alpha(val: float) -> void:
	_phase_alpha = clampf(val, 0.0, 1.0)
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_PHASE_ALPHA, _phase_alpha)


## Updates per-entity suffocation exposure buildup/decay and applies periodic damage ticks.
func _step_exposure_and_damage(delta: float) -> void:
	var any_above_threshold: bool = false

	# Ensure all currently overlapping combat entities are tracked in _exposed_entities.
	for i: int in range(_overlapping_bodies.size() - 1, -1, -1):
		var body: Node3D = _overlapping_bodies[i]
		if not is_instance_valid(body):
			_overlapping_bodies.remove_at(i)
			continue
		if _is_combat_entity(body) and not _exposed_entities.has(body):
			_exposed_entities.append(body)

	for i: int in range(_exposed_entities.size() - 1, -1, -1):
		var entity: Node3D = _exposed_entities[i]
		if not is_instance_valid(entity):
			_exposed_entities.remove_at(i)
			continue

		var inst_id: int = entity.get_instance_id()
		var prev_exp: float = _exposure_map.get(inst_id, 0.0)
		var is_inside: bool = _overlapping_bodies.has(entity)
		var local_density: float = 0.0

		if is_inside and _phase_alpha > 0.01:
			if not check_wall_occlusion or _has_clear_wall_los(entity):
				var sample_pos: Vector3 = entity.global_position + Vector3(0.0, 0.8, 0.0)
				local_density = sample_density_at_world_pos(sample_pos)

		var next_exp: float = prev_exp
		if local_density > 0.02:
			next_exp = clampf(prev_exp + exposure_buildup_rate * local_density * delta, 0.0, 1.0)
		else:
			next_exp = maxf(0.0, prev_exp - exposure_decay_rate * delta)

		_exposure_map[inst_id] = next_exp

		if entity.is_in_group(&"player") and _is_player_inside:
			var hud_density: float = maxf(local_density * 0.4, next_exp)
			if absf(hud_density - _last_emitted_exposure) >= 0.015:
				_last_emitted_exposure = hud_density
				Events.smoke_exposure_changed.emit(hud_density)

		if next_exp >= suffocation_threshold:
			any_above_threshold = true

		if not is_inside and next_exp <= 0.0001:
			_exposure_map.erase(inst_id)
			_health_cache.erase(inst_id)
			_exposed_entities.remove_at(i)

	if any_above_threshold:
		_tick_timer += delta
		if _tick_timer >= tick_rate:
			_tick_timer -= tick_rate
			_apply_suffocation_ticks()
	else:
		_tick_timer = 0.0


## Deals scaled suffocation damage to all entities whose exposure exceeds
## [member suffocation_threshold].
func _apply_suffocation_ticks() -> void:
	var denom: float = maxf(1.0 - suffocation_threshold, 0.001)
	for entity: Node3D in _exposed_entities:
		if not is_instance_valid(entity):
			continue
		var inst_id: int = entity.get_instance_id()
		var exp_val: float = _exposure_map.get(inst_id, 0.0)
		if exp_val < suffocation_threshold:
			continue

		var severity: float = clampf((exp_val - suffocation_threshold) / denom, 0.0, 1.0)
		var dmg_float: float = lerpf(min_damage_per_tick, max_damage_per_tick, severity)
		var dmg_int: int = maxi(1, int(roundf(dmg_float)))

		var health: HealthComponent = _health_cache.get(inst_id, null)
		if not is_instance_valid(health):
			health = _find_health_component(entity)
			if is_instance_valid(health):
				_health_cache[inst_id] = health

		if is_instance_valid(health):
			damage_ticked.emit(entity, dmg_float)
			health.take_damage(dmg_int)
		elif entity.has_method(&"take_damage"):
			damage_ticked.emit(entity, dmg_float)
			var dir: Vector3 = global_position.direction_to(entity.global_position)
			entity.call(&"take_damage", dmg_int, entity.global_position, dir)


## Steps bullet/explosion hole timers and uploads updated strengths to the shader.
func _step_ray_decay(delta: float) -> void:
	var active_remaining: int = 0

	for i: int in range(MAX_RAYS):
		var remaining: float = _ray_timers[i]
		if remaining > 0.0:
			remaining = maxf(0.0, remaining - delta)
			_ray_timers[i] = remaining
			var inv_max: float = 1.0 / maxf(_ray_max_durations[i], 0.1)
			var start_vec: Vector4 = _ray_starts[i]
			start_vec.w = remaining * inv_max
			_ray_starts[i] = start_vec
			if remaining > 0.0:
				active_remaining += 1

	_live_ray_count = active_remaining
	if is_instance_valid(_shader_mat):
		var shader_count: int = MAX_RAYS if _live_ray_count > 0 else 0
		_shader_mat.set_shader_parameter(PARAM_ACTIVE_RAYS, shader_count)
		_shader_mat.set_shader_parameter(PARAM_RAY_STARTS, _ray_starts)


## Computes smoothed actor velocities and uploads up to 8 wakes to the shader.
func _step_actor_wakes(delta: float) -> void:
	var inv_delta: float = 1.0 / maxf(delta, 0.001)
	var count: int = mini(_overlapping_bodies.size(), MAX_ACTORS)
	var valid_slot: int = 0

	for i: int in range(_overlapping_bodies.size() - 1, -1, -1):
		var body: Node3D = _overlapping_bodies[i]
		if not is_instance_valid(body):
			_overlapping_bodies.remove_at(i)
			continue

		if valid_slot >= count:
			continue

		var inst_id: int = body.get_instance_id()
		var cur_pos: Vector3 = body.global_position + Vector3(0.0, 0.6, 0.0)
		var prev_pos: Vector3 = _prev_positions.get(inst_id, cur_pos)
		_prev_positions[inst_id] = cur_pos

		var raw_vel: Vector3 = (cur_pos - prev_pos) * inv_delta
		var prev_vel: Vector3 = _smoothed_velocities.get(inst_id, Vector3.ZERO)
		var smooth_vel: Vector3 = prev_vel.lerp(raw_vel, clampf(delta * 8.0, 0.0, 1.0))
		_smoothed_velocities[inst_id] = smooth_vel

		_actor_positions[valid_slot] = Vector4(cur_pos.x, cur_pos.y, cur_pos.z, actor_carve_radius)
		_actor_velocities[valid_slot] = Vector4(
			smooth_vel.x, smooth_vel.y, smooth_vel.z, wake_trail_scale
		)
		valid_slot += 1

	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_ACTIVE_ACTORS, valid_slot)
		_shader_mat.set_shader_parameter(PARAM_ACTOR_POS, _actor_positions)
		_shader_mat.set_shader_parameter(PARAM_ACTOR_VEL, _actor_velocities)


## Validates clear line of sight against Layer 1 (Environment) so walls block smoke damage.
func _has_clear_wall_los(target: Node3D) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = global_position
	var end_pos: Vector3 = target.global_position + Vector3(0.0, 0.6, 0.0)
	var result: Dictionary = NodeQuery.cast_ray(
		space_state, start_pos, end_pos, CollisionLayers.MASK_ENVIRONMENT
	)
	return result.is_empty()


## Returns true if [param body] is a Player (Layer 2) or Enemy (Layer 5)
## or carries a [HealthComponent].
func _is_combat_entity(body: Node3D) -> bool:
	if body.is_in_group(&"player"):
		return true
	if body is CollisionObject3D:
		var col: CollisionObject3D = body as CollisionObject3D
		if (col.collision_layer & CollisionLayers.MASK_COMBAT_ENTITIES) != 0:
			return true
	return is_instance_valid(_find_health_component(body))


## Resolves [HealthComponent] on target via properties or [NodeQuery].
func _find_health_component(target: Node) -> HealthComponent:
	if not is_instance_valid(target):
		return null
	if target is HealthComponent:
		return target as HealthComponent
	if "health_component" in target:
		var comp: Variant = target.get("health_component")
		if comp is HealthComponent:
			return comp as HealthComponent
	var found_child: Node = NodeQuery.find_first_child_of_type(target, HealthComponent)
	if found_child is HealthComponent:
		return found_child as HealthComponent
	var ancestor: Node = NodeQuery.find_ancestor_of_type(target, HealthComponent)
	if ancestor is HealthComponent:
		return ancestor as HealthComponent
	return null


## Checks squared distance from the active camera to gate distant wake physics.
func _is_within_camera_range() -> bool:
	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return false
	var cam: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(cam):
		return true
	var max_dist_sq: float = max_interaction_distance * max_interaction_distance
	return global_position.distance_squared_to(cam.global_position) <= max_dist_sq


## Enables or disables [_physics_process] based on active state, timers, and tracked bodies.
func _refresh_processing_state() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	var has_work: bool = (
		cycle_enabled
		or _live_ray_count > 0
		or not _overlapping_bodies.is_empty()
		or not _exposed_entities.is_empty()
	)
	set_physics_process(has_work)


## Registers a physics body entering the smoke volume and wakes processing.
func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body) or _overlapping_bodies.has(body):
		return
	_overlapping_bodies.append(body)
	var inst_id: int = body.get_instance_id()
	_prev_positions[inst_id] = body.global_position + Vector3(0.0, 0.6, 0.0)
	_smoothed_velocities[inst_id] = Vector3.ZERO

	if _is_combat_entity(body):
		if not _exposed_entities.has(body):
			_exposed_entities.append(body)
		var health: HealthComponent = _find_health_component(body)
		if is_instance_valid(health):
			_health_cache[inst_id] = health

	if body.is_in_group(&"player") and not _is_player_inside:
		_is_player_inside = true
		var initial_density: float = sample_density_at_world_pos(
			body.global_position + Vector3(0.0, 0.8, 0.0)
		)
		_last_emitted_exposure = maxf(initial_density * 0.4, 0.15)
		Events.smoke_hazard_changed.emit(true, _last_emitted_exposure)

	print("[SmokeHazard] Body entered smoke (", name, "): ", body.name)
	_refresh_processing_state()


## Unregisters a physics body exiting the smoke volume and triggers HUD exit transition.
func _on_body_exited(body: Node3D) -> void:
	var idx: int = _overlapping_bodies.find(body)
	if idx != -1:
		_overlapping_bodies.remove_at(idx)

	if is_instance_valid(body):
		var inst_id: int = body.get_instance_id()
		_prev_positions.erase(inst_id)
		_smoothed_velocities.erase(inst_id)
		print("[SmokeHazard] Body exited smoke (", name, "): ", body.name)

		if body.is_in_group(&"player") and _is_player_inside:
			_is_player_inside = false
			_last_emitted_exposure = -1.0
			var remaining_exp: float = _exposure_map.get(inst_id, 0.0)
			Events.smoke_hazard_changed.emit(false, remaining_exp)

	if _overlapping_bodies.is_empty() and is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_ACTIVE_ACTORS, 0)

	_refresh_processing_state()


## Resumes wake updates when the smoke volume enters the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_refresh_processing_state()


## Suspends wake updates when the smoke volume leaves the camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_refresh_processing_state()
