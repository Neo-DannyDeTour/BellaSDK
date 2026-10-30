@tool
## Event-driven non-volumetric smoke explosion controller with editor preview.
## Orchestrates [GPUParticles3D] passes, 1-shot [RayCast3D] wall containment,
## camera distance LOD gating, and [OmniLight3D] flash decay on Render Layer 1.
class_name SmokeExplosionVfx
extends Node3D

## Emitted when the primary [member _smoke_billow_plume] finishes emission.
@warning_ignore("unused_signal")
signal detonation_completed(origin: Vector3)

## Render Layer 1 (Environment); excludes Layer 10 (Volumetrics).
const RENDER_LAYER_ENV: int = 1
## Physics Layer 1 (Environment) bitmask for wall containment raycasts.
const PHYSICS_LAYER_ENV: int = 1
## Safety offset (meters) keeping displaced lobes from clipping static walls.
const WALL_MARGIN: float = 0.45
## Squared camera distance threshold (40m) gating sparks and light shadows.
const MAX_SPARK_DIST_SQ: float = 1600.0
## Initial peak energy for the detonation [OmniLight3D] flash.
const FLASH_PEAK_ENERGY: float = 14.0
## Duration (seconds) for the detonation [OmniLight3D] decay curve.
const FLASH_DURATION: float = 0.35

## Pre-allocated [StringName] uniform keys for GeometryInstance3D.
const PARAM_EXPANSION_SCALE: StringName = &"expansion_scale"
## Pre-allocated [StringName] key for blackbody fire intensity.
const PARAM_HEAT_INTENSITY: StringName = &"heat_intensity"
## Pre-allocated [StringName] key for alpha erosion phase offset.
const PARAM_EROSION_OFFSET: StringName = &"erosion_offset"

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

## Automatically triggers detonation upon entering tree outside editor.
@export var auto_play: bool = true
## Repeats detonation sequence continuously at runtime and editor preview.
@export var loop: bool = false
## Delay in seconds between plume completion and subsequent looped detonation.
@export_range(0.0, 10.0, 0.1) var loop_interval: float = 1.0
## Editor-only toggle to preview and audition explosion loop in scene viewport.
@export var preview_active: bool = false:
	set = _set_preview_active
## Maximum ray distance when evaluating containment clamping.
@export var max_containment_radius: float = 4.5
## Automatically calls [method Node.queue_free] once plume finishes outside editor.
@export var free_on_finish: bool = true

var _flash_tween: Tween = null
var _loop_tween: Tween = null
var _emitters: Array[GPUParticles3D] = []

@onready var _fireball_burst: GPUParticles3D = $FireballBurst
@onready var _smoke_billow_plume: GPUParticles3D = $SmokeBillowPlume
@onready var _radial_ground_ring: GPUParticles3D = $RadialGroundRing
@onready var _flying_debris_sparks: GPUParticles3D = $FlyingDebrisSparks
@onready var _flash_light: OmniLight3D = $FlashLight
@onready var _screen_notifier: VisibleOnScreenNotifier3D = $VisibleOnScreenNotifier3D
@onready var _containment_ray: RayCast3D = $ContainmentRay


## Validates node invariants, disables per-frame polling, binds signals, and triggers auto-play.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(_fireball_burst != null, "SmokeExplosionVfx: missing FireballBurst.")
	assert(_smoke_billow_plume != null, "SmokeExplosionVfx: missing SmokeBillowPlume.")
	assert(_radial_ground_ring != null, "SmokeExplosionVfx: missing RadialGroundRing.")
	assert(_flying_debris_sparks != null, "SmokeExplosionVfx: missing FlyingDebrisSparks.")
	assert(_flash_light != null, "SmokeExplosionVfx: missing FlashLight.")
	assert(_screen_notifier != null, "SmokeExplosionVfx: missing VisibleOnScreenNotifier3D.")
	assert(_containment_ray != null, "SmokeExplosionVfx: missing ContainmentRay.")
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

	_flash_light.layers = RENDER_LAYER_ENV
	_flash_light.light_energy = 0.0
	_containment_ray.enabled = false
	_containment_ray.collision_mask = PHYSICS_LAYER_ENV

	_smoke_billow_plume.finished.connect(_on_plume_finished)
	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)

	if Engine.is_editor_hint():
		if preview_active:
			detonate(global_position)
	elif auto_play:
		detonate(global_position)


## Cleans up active [Tween] instances and signal bindings on tree exit.
func _exit_tree() -> void:
	if is_instance_valid(_flash_tween) and _flash_tween.is_running():
		_flash_tween.kill()
	if is_instance_valid(_loop_tween) and _loop_tween.is_running():
		_loop_tween.kill()


## Triggers the 4-phase non-volumetric smoke detonation at [param world_pos].
func detonate(world_pos: Vector3 = global_position) -> void:
	if not is_inside_tree():
		return

	if is_instance_valid(_loop_tween) and _loop_tween.is_running():
		_loop_tween.kill()

	global_position = world_pos
	print("SmokeExplosionVfx: detonated at ", world_pos)

	var containment_scale: float = _compute_containment_scale(world_pos)
	_apply_instance_parameters(containment_scale)

	var near_camera: bool = _is_within_detail_distance(world_pos)
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

	_trigger_flash()


## Inspector property setter controlling editor viewport auditioning.
func _set_preview_active(value: bool) -> void:
	preview_active = value
	if not is_inside_tree() or not Engine.is_editor_hint():
		return

	if preview_active:
		detonate(global_position)
	else:
		_stop_all_vfx()


## Immediately aborts particle emissions, kills active tweens, and resets lights.
func _stop_all_vfx() -> void:
	if is_instance_valid(_flash_tween) and _flash_tween.is_running():
		_flash_tween.kill()
	if is_instance_valid(_loop_tween) and _loop_tween.is_running():
		_loop_tween.kill()

	for emitter: GPUParticles3D in _emitters:
		if is_instance_valid(emitter):
			emitter.emitting = false

	if is_instance_valid(_flash_light):
		_flash_light.light_energy = 0.0
		_flash_light.visible = false


## Schedules subsequent detonation via dedicated tween timer.
func _schedule_loop() -> void:
	if is_instance_valid(_loop_tween) and _loop_tween.is_running():
		_loop_tween.kill()

	_loop_tween = create_tween()
	_loop_tween.tween_interval(loop_interval)
	_loop_tween.tween_callback(detonate.bind(global_position))


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
	return clampf(clear_dist / max_containment_radius, 0.25, 1.0)


## Sets per-instance shader uniforms on particle geometry without duplicating materials.
func _apply_instance_parameters(containment_scale: float) -> void:
	_fireball_burst.set_instance_shader_parameter(PARAM_EXPANSION_SCALE, containment_scale)
	_fireball_burst.set_instance_shader_parameter(PARAM_HEAT_INTENSITY, 3.2)
	_fireball_burst.set_instance_shader_parameter(PARAM_EROSION_OFFSET, 0.0)

	_smoke_billow_plume.set_instance_shader_parameter(PARAM_EXPANSION_SCALE, containment_scale)
	_smoke_billow_plume.set_instance_shader_parameter(PARAM_HEAT_INTENSITY, 1.1)
	_smoke_billow_plume.set_instance_shader_parameter(PARAM_EROSION_OFFSET, 0.0)

	_radial_ground_ring.set_instance_shader_parameter(PARAM_EXPANSION_SCALE, containment_scale)
	_radial_ground_ring.set_instance_shader_parameter(PARAM_HEAT_INTENSITY, 0.25)
	_radial_ground_ring.set_instance_shader_parameter(PARAM_EROSION_OFFSET, 0.12)


## Evaluates squared distance to active [Camera3D] for LOD gating of sparks and shadows.
func _is_within_detail_distance(origin: Vector3) -> bool:
	if Engine.is_editor_hint():
		return true

	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return true
	var cam: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(cam):
		return true
	return origin.distance_squared_to(cam.global_position) <= MAX_SPARK_DIST_SQ


## Animates [member _flash_light] energy decay, killing any existing [Tween] first.
func _animate_flash_off() -> void:
	_flash_light.visible = false


## Spawns a fresh [Tween] for detonation light decay after killing prior active tweens.
func _trigger_flash() -> void:
	if is_instance_valid(_flash_tween) and _flash_tween.is_running():
		_flash_tween.kill()

	_flash_light.visible = _screen_notifier.is_on_screen()
	_flash_light.light_energy = FLASH_PEAK_ENERGY
	_flash_tween = create_tween()
	_flash_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_flash_light, "light_energy", 0.0, FLASH_DURATION)
	_flash_tween.tween_callback(_animate_flash_off)


## Handles [signal GPUParticles3D.finished] from [member _smoke_billow_plume].
func _on_plume_finished() -> void:
	if not is_inside_tree():
		return

	print("SmokeExplosionVfx: plume finished at ", global_position)
	detonation_completed.emit(global_position)

	if Engine.is_editor_hint():
		if preview_active and loop:
			_schedule_loop()
		elif preview_active and not loop:
			preview_active = false
		return

	if loop:
		_schedule_loop()
	elif free_on_finish:
		call_deferred(&"queue_free")


## Restores particle rendering and flash light visibility when entering frustum.
func _on_screen_entered() -> void:
	if not is_inside_tree():
		return
	for emitter: GPUParticles3D in _emitters:
		if is_instance_valid(emitter):
			emitter.visible = true
	if is_instance_valid(_flash_light) and _flash_light.light_energy > 0.01:
		_flash_light.visible = true


## Suspends visual rendering when off-screen while preserving particle lifetime simulation.
func _on_screen_exited() -> void:
	if not is_inside_tree():
		return
	for emitter: GPUParticles3D in _emitters:
		if is_instance_valid(emitter):
			emitter.visible = false
	if is_instance_valid(_flash_light):
		_flash_light.visible = false
