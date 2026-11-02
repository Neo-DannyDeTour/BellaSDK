@tool
# class_name WeatherVolume
extends Node3D

## Controls localized snow and dust [GPUParticles3D] volumes with screen-culling.
##
## Synchronizes emission box extents, visibility AABBs, intensity ratios, and
## wind vectors across child particle systems without per-frame CPU overhead.

## Vertical bounding margin applied to particle visibility [AABB] for falling motes.
const _DROP_AABB_MARGIN: float = 2.5
## Minimum intensity ratio required before enabling particle emission.
const _MIN_ACTIVE_RATIO: float = 0.001

## Half-extents of the weather emission volume in 3D units.
@export var volume_extents: Vector3 = Vector3(10.0, 6.0, 10.0):
	set(value):
		volume_extents = value.max(Vector3(0.5, 0.5, 0.5))
		if is_inside_tree():
			_apply_volume_extents()

## Normalized emission intensity of the snow particle system.
@export_range(0.0, 1.0, 0.01) var snow_intensity: float = 1.0:
	set(value):
		snow_intensity = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_apply_intensities()

## Normalized emission intensity of the dust particle system.
@export_range(0.0, 1.0, 0.01) var dust_intensity: float = 1.0:
	set(value):
		dust_intensity = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_apply_intensities()

## Global wind directional force and speed vector applied to particle trajectories.
@export var wind_velocity: Vector3 = Vector3(0.4, 0.0, 0.2):
	set(value):
		wind_velocity = value
		if is_inside_tree():
			_apply_wind()

## Tracks whether volume is within active camera view frustum.
var _is_on_screen: bool = true

## Cached reference to child snow [GPUParticles3D] system.
@onready var _snow_particles: GPUParticles3D = $SnowParticles
## Cached reference to child dust [GPUParticles3D] system.
@onready var _dust_particles: GPUParticles3D = $DustParticles
## Cached reference to camera frustum visibility notifier.
@onready var _screen_notifier: VisibleOnScreenNotifier3D = $VisibleOnScreenNotifier3D


## Validates required child nodes, disables frame loops, and binds visibility signals.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(is_instance_valid(_snow_particles), "WeatherVolume: Missing SnowParticles.")
	assert(is_instance_valid(_dust_particles), "WeatherVolume: Missing DustParticles.")
	assert(is_instance_valid(_screen_notifier), "WeatherVolume: Missing Notifier.")

	if not _screen_notifier.screen_entered.is_connected(_on_screen_entered):
		_screen_notifier.screen_entered.connect(_on_screen_entered)
	if not _screen_notifier.screen_exited.is_connected(_on_screen_exited):
		_screen_notifier.screen_exited.connect(_on_screen_exited)

	_is_on_screen = Engine.is_editor_hint() or _screen_notifier.is_on_screen()
	_apply_volume_extents()
	_apply_wind()
	_apply_intensities()


## Updates emission box shapes and culling bounds on child nodes when [member volume_extents]
## changes.
func _apply_volume_extents() -> void:
	if not is_instance_valid(_snow_particles) or not is_instance_valid(_dust_particles):
		return

	var half_extents: Vector3 = volume_extents * 0.5
	var snow_mat: ParticleProcessMaterial = (
		_snow_particles.process_material as ParticleProcessMaterial
	)
	if is_instance_valid(snow_mat):
		snow_mat.emission_box_extents = half_extents

	var dust_mat: ParticleProcessMaterial = (
		_dust_particles.process_material as ParticleProcessMaterial
	)
	if is_instance_valid(dust_mat):
		dust_mat.emission_box_extents = half_extents

	var vis_size: Vector3 = volume_extents + Vector3(0.0, _DROP_AABB_MARGIN, 0.0)
	var vis_pos: Vector3 = -half_extents - Vector3(0.0, _DROP_AABB_MARGIN, 0.0)
	var bounds: AABB = AABB(vis_pos, vis_size)

	_snow_particles.visibility_aabb = bounds
	_dust_particles.visibility_aabb = bounds

	if is_instance_valid(_screen_notifier):
		_screen_notifier.aabb = bounds


## Updates emission ratios and active emission state based on intensity and visibility.
func _apply_intensities() -> void:
	if is_instance_valid(_snow_particles):
		_snow_particles.amount_ratio = snow_intensity
		_snow_particles.emitting = _is_on_screen and (snow_intensity > _MIN_ACTIVE_RATIO)

	if is_instance_valid(_dust_particles):
		_dust_particles.amount_ratio = dust_intensity
		_dust_particles.emitting = _is_on_screen and (dust_intensity > _MIN_ACTIVE_RATIO)


## Applies [member wind_velocity] to both particle process materials.
func _apply_wind() -> void:
	if not is_instance_valid(_snow_particles) or not is_instance_valid(_dust_particles):
		return

	var wind_speed: float = wind_velocity.length()
	var wind_dir: Vector3 = (
		wind_velocity / wind_speed if wind_speed > 0.001 else Vector3(0.0, -1.0, 0.0)
	)

	var snow_mat: ParticleProcessMaterial = (
		_snow_particles.process_material as ParticleProcessMaterial
	)
	if is_instance_valid(snow_mat):
		snow_mat.direction = (wind_dir + Vector3(0.0, -1.0, 0.0)).normalized()
		snow_mat.initial_velocity_min = maxf(0.2, wind_speed * 0.7)
		snow_mat.initial_velocity_max = maxf(0.6, wind_speed * 1.3)

	var dust_mat: ParticleProcessMaterial = (
		_dust_particles.process_material as ParticleProcessMaterial
	)
	if is_instance_valid(dust_mat):
		dust_mat.direction = wind_dir
		dust_mat.initial_velocity_min = maxf(0.05, wind_speed * 0.3)
		dust_mat.initial_velocity_max = maxf(0.25, wind_speed * 0.8)


## Enables particle emission when volume enters camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_apply_intensities()
	print("WeatherVolume: Entered screen -> active")


## Suspends particle emission when volume exits camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_apply_intensities()
	print("WeatherVolume: Exited screen -> culled")
