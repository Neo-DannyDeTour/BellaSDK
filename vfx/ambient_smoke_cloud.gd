@tool
## Room/ceiling Half-Life 2 style lit ambient smoke bank driven by [GPUParticles3D].
##
## Uses [code]smoke_hl2_lit.gdshader[/code] on Render Layer 10, per-instance shader parameters
## for tint and density, and [VisibleOnScreenNotifier3D] gating for 60 FPS efficiency.
class_name AmbientSmokeCloud
extends Node3D

## Pre-allocated shader instance uniform key for smoke tint color.
const PARAM_TINT_COLOR: StringName = &"tint_color"
## Pre-allocated shader instance uniform key for smoke density multiplier.
const PARAM_DENSITY_SCALE: StringName = &"density_scale"
## Padding (meters) added to [member volume_extents] for visibility bounds.
const AABB_PADDING: Vector3 = Vector3(2.5, 2.5, 2.5)

## Toggles cloud particle emission on or off.
@export var is_active: bool = true:
	set(value):
		is_active = value
		_sync_emission_state()
## Half-extents (meters) of the box volume spawning ambient smoke clouds.
@export var volume_extents: Vector3 = Vector3(5.0, 2.2, 5.0):
	set(value):
		volume_extents = Vector3(maxf(0.1, value.x), maxf(0.1, value.y), maxf(0.1, value.z))
		_sync_volume_bounds()
## Per-instance charcoal/ambient smoke tint passed to the HL2 lit shader.
@export var smoke_color: Color = Color(0.24, 0.22, 0.20, 0.85):
	set(value):
		smoke_color = value
		_sync_shader_parameters()
## Per-instance alpha density multiplier passed to the HL2 lit shader.
@export_range(0.1, 2.0, 0.05) var density: float = 1.0:
	set(value):
		density = clampf(value, 0.1, 2.0)
		_sync_shader_parameters()
## Continuous directional drift velocity (m/s) applied to emitted cloud puffs.
@export var drift_velocity: Vector3 = Vector3(0.18, 0.08, 0.0):
	set(value):
		drift_velocity = value
		_sync_drift_velocity()

## Runtime frustum visibility flag controlled by [VisibleOnScreenNotifier3D].
var _is_on_screen: bool = true

## Child volumetric smoke particle emitter rendered on Render Layer 10.
@onready var _particles: GPUParticles3D = $SmokeParticles
## Frustum culling notifier gating offscreen particle emission at runtime.
@onready var _visibility_notifier: VisibleOnScreenNotifier3D = $VisibleOnScreenNotifier3D


## Validates child nodes, disables polling, binds visibility signals, and syncs state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_particles), "AmbientSmokeCloud requires SmokeParticles child.")
	assert(
		is_instance_valid(_visibility_notifier),
		"AmbientSmokeCloud requires VisibleOnScreenNotifier3D child."
	)
	assert(volume_extents.x > 0.0 and volume_extents.y > 0.0 and volume_extents.z > 0.0)
	assert(density >= 0.1 and density <= 2.0)

	_particles.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS

	if not Engine.is_editor_hint():
		if not _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			_visibility_notifier.screen_entered.connect(_on_screen_entered)
		if not _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			_visibility_notifier.screen_exited.connect(_on_screen_exited)
		_is_on_screen = _visibility_notifier.is_on_screen()
	else:
		_is_on_screen = true

	_sync_volume_bounds()
	_sync_shader_parameters()
	_sync_drift_velocity()
	_sync_emission_state()


## Disconnects visibility notifier signals when exiting the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(_visibility_notifier):
		if _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			_visibility_notifier.screen_entered.disconnect(_on_screen_entered)
		if _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			_visibility_notifier.screen_exited.disconnect(_on_screen_exited)


## Updates [GPUParticles3D] emission state from [member is_active] and frustum visibility.
func _sync_emission_state() -> void:
	if not is_inside_tree() or not is_instance_valid(_particles):
		return
	var should_emit: bool = is_active and (_is_on_screen or Engine.is_editor_hint())
	_particles.emitting = should_emit
	_particles.visible = is_active


## Updates box emission extents and padded visibility AABBs on child nodes.
func _sync_volume_bounds() -> void:
	if not is_inside_tree():
		return
	var padded: Vector3 = volume_extents + AABB_PADDING
	var bounds: AABB = AABB(-padded, padded * 2.0)
	if is_instance_valid(_visibility_notifier):
		_visibility_notifier.aabb = bounds
	if is_instance_valid(_particles):
		_particles.visibility_aabb = bounds
		var proc_mat: ParticleProcessMaterial = (
			_particles.process_material as ParticleProcessMaterial
		)
		if is_instance_valid(proc_mat):
			proc_mat.emission_box_extents = volume_extents


## Applies per-instance tint and density uniforms without duplicating the shader material.
func _sync_shader_parameters() -> void:
	if not is_inside_tree() or not is_instance_valid(_particles):
		return
	_particles.set_instance_shader_parameter(PARAM_TINT_COLOR, smoke_color)
	_particles.set_instance_shader_parameter(PARAM_DENSITY_SCALE, density)


## Applies [member drift_velocity] to the particle process material direction and speed.
func _sync_drift_velocity() -> void:
	if not is_inside_tree() or not is_instance_valid(_particles):
		return
	var proc_mat: ParticleProcessMaterial = _particles.process_material as ParticleProcessMaterial
	if not is_instance_valid(proc_mat):
		return
	var speed: float = drift_velocity.length()
	if speed > 0.0001:
		proc_mat.direction = drift_velocity / speed
		proc_mat.initial_velocity_min = speed * 0.65
		proc_mat.initial_velocity_max = speed * 1.35
		proc_mat.gravity = drift_velocity * 0.25
	else:
		proc_mat.direction = Vector3.UP
		proc_mat.initial_velocity_min = 0.0
		proc_mat.initial_velocity_max = 0.0
		proc_mat.gravity = Vector3.ZERO


## Resumes cloud particle emission when the volume enters the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_sync_emission_state()


## Pauses cloud particle emission when the volume leaves the camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_sync_emission_state()
