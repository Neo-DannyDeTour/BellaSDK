## Event-driven non-volumetric smoke explosion controller.
## Orchestrates soft-billboard [GPUParticles3D] passes, 1-shot [RayCast3D] containment,
## synchronous [ShapeCast3D] blast impulse on Physics Layers 3/4/5, refractive
## [MeshInstance3D] shockwave, floor [Decal] scorch, and [OmniLight3D] decay.
class_name SmokeExplosionVfx
extends Node3D

## Emitted when the primary [member _smoke_billow_plume] finishes emission.
@warning_ignore("unused_signal")
signal detonation_completed(origin: Vector3)

## Emitted per target on Physics Layers 3, 4, or 5 within unoccluded [constant BLAST_RADIUS].
@warning_ignore("unused_signal")
signal blast_impacted(collider: Node3D, impulse: Vector3, distance_ratio: float)

## Render Layer 1 (Environment); excludes Layer 10 (Volumetrics).
const RENDER_LAYER_ENV: int = CollisionLayers.RENDER_LAYER_ENVIRONMENT_IDX
## Physics Layer 1 (Environment) bitmask for wall, floor, and line-of-sight raycasts.
const PHYSICS_LAYER_ENV: int = CollisionLayers.MASK_ENVIRONMENT
## Physics Layers 3 (Interactive=4), 4 (Debris=8), and 5 (Enemies=16) blast bitmask.
const PHYSICS_MASK_BLAST: int = (
	CollisionLayers.MASK_INTERACTIVE | CollisionLayers.MASK_DEBRIS | CollisionLayers.MASK_ENEMIES
)
## Safety offset (meters) keeping smoke puffs from clipping static walls.
const WALL_MARGIN: float = 0.45
## Outer radius (meters) for the physics blast [ShapeCast3D] query.
const BLAST_RADIUS: float = 6.0
## Squared outer radius for fast proximity rejection via [method Vector3.distance_squared_to].
const BLAST_RADIUS_SQ: float = 36.0
## Peak impulse magnitude (N*s) applied at ground zero before quadratic falloff.
const BLAST_PEAK_IMPULSE: float = 18.0
## Vertical lift bias added to radial blast impulse vectors.
const BLAST_UPWARD_BIAS: float = 0.35
## Squared camera distance threshold (40m) gating sparks and light shadows.
const MAX_SPARK_DIST_SQ: float = 1600.0
## Initial peak energy for the detonation [OmniLight3D] flash.
const FLASH_PEAK_ENERGY: float = 14.0
## Duration (seconds) for the detonation [OmniLight3D] and shockwave expansion.
const FLASH_DURATION: float = 0.34
## Downward raycast reach (meters) to snap [member _scorch_decal] onto floor geometry.
const SCORCH_RAY_DEPTH: float = 2.5
## Delay (seconds) before fading out the floor scorch [Decal].
const SCORCH_FADE_DELAY: float = 2.8
## Duration (seconds) for the floor scorch [Decal] alpha fade-out.
const SCORCH_FADE_DURATION: float = 1.4

## Pre-allocated [StringName] key for radial containment scale.
const PARAM_EXPANSION_SCALE: StringName = &"expansion_scale"
## Pre-allocated [StringName] key for blackbody fire intensity.
const PARAM_HEAT_INTENSITY: StringName = &"heat_intensity"
## Pre-allocated [StringName] key for alpha erosion phase offset.
const PARAM_EROSION_OFFSET: StringName = &"erosion_offset"
## Pre-allocated [StringName] key for normalized shockwave progress (0.0 -> 1.0).
const PARAM_SHOCKWAVE_PROGRESS: StringName = &"shockwave_progress"
## Pre-allocated [StringName] key for maximum shockwave outer radius.
const PARAM_SHOCKWAVE_SCALE: StringName = &"shockwave_scale"

## 12 normalized radial and upper-hemisphere directions for 1-shot containment probing.
const RAY_DIRS: PackedVector3Array = [
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.7071, 0.0, 0.7071),
	Vector3(-0.7071, 0.0, 0.7071),
	Vector3(0.7071, 0.0, -0.7071),
	Vector3(-0.7071, 0.0, -0.7071),
	Vector3(0.5, 0.866, 0.0),
	Vector3(-0.5, 0.866, 0.0),
	Vector3(0.0, 0.866, 0.5),
	Vector3(0.0, 1.0, 0.0),
]

## Automatically triggers detonation upon entering the scene tree.
@export var auto_play: bool = true
## Maximum radial distance in meters when evaluating containment clamping.
@export var max_containment_radius: float = 4.5
## Automatically calls [method Node.queue_free] once plume finishes emission.
@export var free_on_finish: bool = true

## Active [Tween] driving light decay, shockwave expansion, and scorch fade.
var _flash_tween: Tween = null
## Cached list of child particle emitters for batch operations.
var _emitters: Array[GPUParticles3D] = []

## Burst particles emitting high-heat core fireballs.
@onready var _fireball_burst: GPUParticles3D = $FireballBurst
## Primary rising cauliflower smoke plume particles.
@onready var _smoke_billow_plume: GPUParticles3D = $SmokeBillowPlume
## Outward radial shockwave dust ring particles on the ground.
@onready var _radial_ground_ring: GPUParticles3D = $RadialGroundRing
## Fast ballistic sparks and flying debris particles.
@onready var _flying_debris_sparks: GPUParticles3D = $FlyingDebrisSparks
## Screen-space refractive shockwave sphere mesh.
@onready var _shockwave_sphere: MeshInstance3D = $ShockwaveSphere
## Ground scorch decal projected onto Layer 1 environment geometry.
@onready var _scorch_decal: Decal = $ScorchDecal
## Dynamic light simulating initial explosive fire flash.
@onready var _flash_light: OmniLight3D = $FlashLight
## Camera visibility detector used to gate rendering passes.
@onready var _screen_notifier: VisibleOnScreenNotifier3D = $VisibleOnScreenNotifier3D
## Raycast node evaluating room boundaries and floor snapping.
@onready var _containment_ray: RayCast3D = $ContainmentRay
## ShapeCast3D sphere querying blast colliders on physics layers 3, 4, and 5.
@onready var _blast_cast: ShapeCast3D = $BlastCast


## Validates node invariants, disables per-frame polling, binds signals, and triggers auto-play.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(_fireball_burst != null, "SmokeExplosionVfx: missing FireballBurst.")
	assert(_smoke_billow_plume != null, "SmokeExplosionVfx: missing SmokeBillowPlume.")
	assert(_radial_ground_ring != null, "SmokeExplosionVfx: missing RadialGroundRing.")
	assert(_flying_debris_sparks != null, "SmokeExplosionVfx: missing FlyingDebrisSparks.")
	assert(_shockwave_sphere != null, "SmokeExplosionVfx: missing ShockwaveSphere.")
	assert(_scorch_decal != null, "SmokeExplosionVfx: missing ScorchDecal.")
	assert(_flash_light != null, "SmokeExplosionVfx: missing FlashLight.")
	assert(_screen_notifier != null, "SmokeExplosionVfx: missing VisibleOnScreenNotifier3D.")
	assert(_containment_ray != null, "SmokeExplosionVfx: missing ContainmentRay.")
	assert(_blast_cast != null, "SmokeExplosionVfx: missing BlastCast.")
	assert(max_containment_radius > WALL_MARGIN, "SmokeExplosionVfx: radius <= WALL_MARGIN.")

	_emitters = [
		_fireball_burst,
		_smoke_billow_plume,
		_radial_ground_ring,
		_flying_debris_sparks,
	]
	for emitter: GPUParticles3D in _emitters:
		emitter.layers = RENDER_LAYER_ENV
		emitter.one_shot = true
		emitter.emitting = false

	_shockwave_sphere.layers = RENDER_LAYER_ENV
	_shockwave_sphere.visible = false
	_scorch_decal.cull_mask = RENDER_LAYER_ENV
	_scorch_decal.visible = false
	_flash_light.layers = RENDER_LAYER_ENV
	_flash_light.light_energy = 0.0
	_containment_ray.enabled = false
	_containment_ray.collision_mask = PHYSICS_LAYER_ENV
	_blast_cast.enabled = false
	_blast_cast.collision_mask = PHYSICS_MASK_BLAST
	_blast_cast.target_position = Vector3.ZERO

	Utilities.safe_connect(_smoke_billow_plume.finished, _on_plume_finished)
	Utilities.safe_connect(_screen_notifier.screen_entered, _on_screen_entered)
	Utilities.safe_connect(_screen_notifier.screen_exited, _on_screen_exited)

	if auto_play:
		detonate(global_position)


## Cleans up active [Tween] instances on tree exit.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_flash_tween)


## Triggers the 4-phase smoke detonation, physics blast, shockwave, and scorch
## at [param world_pos].
func detonate(world_pos: Vector3 = Vector3.INF) -> void:
	if not is_inside_tree():
		return

	var target_pos: Vector3 = global_position if not world_pos.is_finite() else world_pos
	global_position = target_pos
	print("SmokeExplosionVfx: detonated at ", target_pos)

	var containment_scale: float = _compute_containment_scale(target_pos)
	var has_scorch: bool = _place_scorch_decal()
	_apply_blast_impulse(target_pos)
	_apply_instance_parameters(containment_scale)

	var near_camera: bool = _is_within_detail_distance(target_pos)
	_flash_light.shadow_enabled = near_camera

	_fireball_burst.restart()
	_fireball_burst.emitting = true
	_smoke_billow_plume.restart()
	_smoke_billow_plume.emitting = true
	_radial_ground_ring.restart()
	_radial_ground_ring.emitting = true

	if near_camera:
		_flying_debris_sparks.restart()
		_flying_debris_sparks.emitting = true

	_trigger_flash(has_scorch)


## Sweeps Physics Layers 3, 4, and 5 via [member _blast_cast] and applies LoS-checked impulses.
func _apply_blast_impulse(origin: Vector3) -> void:
	_blast_cast.force_shapecast_update()
	var hit_count: int = _blast_cast.get_collision_count()
	var impacted_count: int = 0

	for i: int in range(hit_count):
		var raw_collider: Object = _blast_cast.get_collider(i)
		var collider: Node3D = raw_collider as Node3D
		if not is_instance_valid(collider):
			continue

		var target_pos: Vector3 = collider.global_position
		var dist_sq: float = origin.distance_squared_to(target_pos)
		if dist_sq > BLAST_RADIUS_SQ:
			continue

		# Verify Layer 1 static geometry does not occlude the blast wave.
		_containment_ray.target_position = target_pos - origin
		_containment_ray.force_raycast_update()
		if _containment_ray.is_colliding():
			continue

		var dist: float = sqrt(dist_sq)
		var dist_ratio: float = clampf(dist / BLAST_RADIUS, 0.0, 1.0)
		var falloff: float = 1.0 - (dist_ratio * dist_ratio)
		var raw_dir: Vector3 = (target_pos - origin) if dist > 0.001 else Vector3.UP
		var dir_biased: Vector3 = raw_dir.normalized() + Vector3(0.0, BLAST_UPWARD_BIAS, 0.0)
		var impulse_vec: Vector3 = dir_biased.normalized() * (BLAST_PEAK_IMPULSE * falloff)

		var body: RigidBody3D = collider as RigidBody3D
		if is_instance_valid(body):
			body.call_deferred(&"apply_impulse", impulse_vec)

		blast_impacted.emit(collider, impulse_vec, dist_ratio)
		impacted_count += 1

	if impacted_count > 0:
		print("SmokeExplosionVfx: blast impacted ", impacted_count, " targets")


## Casts 12 synchronous rays via [member _containment_ray] to clamp expansion near walls.
func _compute_containment_scale(origin: Vector3) -> float:
	# shortcut: 1-shot origin raycast, upgrade to GPUParticlesCollisionSDF3D in baked rooms
	var max_dist_sq: float = max_containment_radius * max_containment_radius
	var min_dist_sq: float = max_dist_sq

	for dir: Vector3 in RAY_DIRS:
		_containment_ray.target_position = dir * max_containment_radius
		_containment_ray.force_raycast_update()
		if _containment_ray.is_colliding():
			var hit_point: Vector3 = _containment_ray.get_collision_point()
			var dist_sq: float = origin.distance_squared_to(hit_point)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq

	if min_dist_sq >= max_dist_sq:
		return 1.0

	var clear_dist: float = maxf(sqrt(min_dist_sq) - WALL_MARGIN, 0.35)
	return clampf(clear_dist / max_containment_radius, 0.35, 1.0)


## Projects a downward ray to snap [member _scorch_decal] flush against Layer 1 floor geometry.
func _place_scorch_decal() -> bool:
	_containment_ray.target_position = Vector3(0.0, -SCORCH_RAY_DEPTH, 0.0)
	_containment_ray.force_raycast_update()
	if not _containment_ray.is_colliding():
		_scorch_decal.visible = false
		return false

	var hit_pos: Vector3 = _containment_ray.get_collision_point()
	var up_vec: Vector3 = _containment_ray.get_collision_normal()
	var ref_axis: Vector3 = Vector3.FORWARD
	if absf(up_vec.dot(ref_axis)) > 0.9:
		ref_axis = Vector3.RIGHT
	var right_vec: Vector3 = up_vec.cross(ref_axis).normalized()
	var fwd_vec: Vector3 = right_vec.cross(up_vec).normalized()

	_scorch_decal.global_transform = Transform3D(Basis(right_vec, up_vec, fwd_vec), hit_pos)
	_scorch_decal.modulate = Color(1.0, 1.0, 1.0, 0.92)
	_scorch_decal.visible = _screen_notifier.is_on_screen()
	return true


## Sets per-instance shader uniforms on particle and shockwave meshes without duplicating materials.
func _apply_instance_parameters(containment_scale: float) -> void:
	_fireball_burst.set_instance_shader_parameter(PARAM_EXPANSION_SCALE, containment_scale)
	_fireball_burst.set_instance_shader_parameter(PARAM_HEAT_INTENSITY, 3.2)
	_fireball_burst.set_instance_shader_parameter(PARAM_EROSION_OFFSET, 0.0)

	_smoke_billow_plume.set_instance_shader_parameter(PARAM_EXPANSION_SCALE, containment_scale)
	_smoke_billow_plume.set_instance_shader_parameter(PARAM_HEAT_INTENSITY, 1.2)
	_smoke_billow_plume.set_instance_shader_parameter(PARAM_EROSION_OFFSET, 0.0)

	_radial_ground_ring.set_instance_shader_parameter(PARAM_EXPANSION_SCALE, containment_scale)
	_radial_ground_ring.set_instance_shader_parameter(PARAM_HEAT_INTENSITY, 0.35)
	_radial_ground_ring.set_instance_shader_parameter(PARAM_EROSION_OFFSET, 0.1)

	var wave_radius: float = max_containment_radius * containment_scale * 1.25
	_shockwave_sphere.set_instance_shader_parameter(PARAM_SHOCKWAVE_SCALE, wave_radius)
	_shockwave_sphere.set_instance_shader_parameter(PARAM_SHOCKWAVE_PROGRESS, 0.0)


## Evaluates squared distance to active [Camera3D] for LOD gating of sparks and shadows.
func _is_within_detail_distance(origin: Vector3) -> bool:
	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return true
	var cam: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(cam):
		return true
	return origin.distance_squared_to(cam.global_position) <= MAX_SPARK_DIST_SQ


## Spawns a unified [Tween] driving light decay, shockwave expansion, and scorch fade-out.
func _trigger_flash(has_scorch: bool) -> void:
	_flash_tween = Utilities.reset_tween(self, _flash_tween)
	if not is_instance_valid(_flash_tween):
		return

	var on_screen: bool = _screen_notifier.is_on_screen()
	_flash_light.visible = on_screen
	_flash_light.light_energy = FLASH_PEAK_ENERGY
	_shockwave_sphere.visible = on_screen

	_flash_tween.set_parallel(true)
	(
		_flash_tween
		. tween_property(_flash_light, "light_energy", 0.0, FLASH_DURATION)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_flash_tween
		. tween_method(_set_shockwave_progress, 0.0, 1.0, FLASH_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_flash_tween.chain().tween_callback(_finish_flash_and_shockwave)

	if has_scorch:
		_flash_tween.tween_interval(SCORCH_FADE_DELAY)
		_flash_tween.tween_property(_scorch_decal, "modulate:a", 0.0, SCORCH_FADE_DURATION)


## Updates the per-instance shockwave expansion uniform during [member _flash_tween].
func _set_shockwave_progress(progress: float) -> void:
	if is_instance_valid(_shockwave_sphere):
		_shockwave_sphere.set_instance_shader_parameter(PARAM_SHOCKWAVE_PROGRESS, progress)


## Hides the flash light and refractive shockwave mesh once their burst completes.
func _finish_flash_and_shockwave() -> void:
	if is_instance_valid(_flash_light):
		_flash_light.visible = false
	if is_instance_valid(_shockwave_sphere):
		_shockwave_sphere.visible = false


## Handles [signal GPUParticles3D.finished] from [member _smoke_billow_plume].
func _on_plume_finished() -> void:
	if not is_inside_tree():
		return
	print("SmokeExplosionVfx: plume finished at ", global_position)
	detonation_completed.emit(global_position)
	if free_on_finish:
		call_deferred(&"queue_free")


## Restores visual node visibility when entering the camera frustum.
func _on_screen_entered() -> void:
	if not is_inside_tree():
		return
	for emitter: GPUParticles3D in _emitters:
		if is_instance_valid(emitter):
			emitter.visible = true
	if is_instance_valid(_flash_light) and _flash_light.light_energy > 0.01:
		_flash_light.visible = true
	if is_instance_valid(_scorch_decal) and _scorch_decal.modulate.a > 0.01:
		_scorch_decal.visible = true


## Suspends visual rendering when off-screen while preserving particle lifetime simulation.
func _on_screen_exited() -> void:
	if not is_inside_tree():
		return
	for emitter: GPUParticles3D in _emitters:
		if is_instance_valid(emitter):
			emitter.visible = false
	if is_instance_valid(_flash_light):
		_flash_light.visible = false
	if is_instance_valid(_shockwave_sphere):
		_shockwave_sphere.visible = false
	if is_instance_valid(_scorch_decal):
		_scorch_decal.visible = false
