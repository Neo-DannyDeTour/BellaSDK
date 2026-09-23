@tool
## Volumetric dust emitter mirroring Source func_dustvolume with GPU collision and turbulence.
class_name DustVolume
extends GPUParticles3D

## Render layer mask bit for Layer 10 (Volumetrics).
const LAYER_VOLUMETRICS: int = 512

## Emitted when [member frozen] state changes with [param is_frozen].
signal frozen_changed(is_frozen: bool)

## Box bounds of the dust volume in meters.
@export var volume_size: Vector3 = Vector3(6.0, 4.0, 6.0):
	set(value):
		volume_size = value
		if is_inside_tree() and _is_initialized:
			_update_volume()
			_update_culling_bounds()

## Base tint and alpha transparency of the dust motes.
@export var dust_color: Color = Color(0.92, 0.88, 0.78, 0.35):
	set(value):
		dust_color = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Total number of active particles in the volume.
@export_range(16, 2048, 1) var dust_density: int = 160:
	set(value):
		dust_density = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Minimum particle lifetime in seconds.
@export_range(0.5, 30.0, 0.5) var lifetime_min: float = 4.0:
	set(value):
		lifetime_min = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Maximum particle lifetime in seconds.
@export_range(0.5, 30.0, 0.5) var lifetime_max: float = 8.0:
	set(value):
		lifetime_max = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Minimum initial drift velocity in meters per second.
@export_range(0.0, 2.0, 0.01) var speed_min: float = 0.02:
	set(value):
		speed_min = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Maximum initial drift velocity in meters per second.
@export_range(0.0, 2.0, 0.01) var speed_max: float = 0.06:
	set(value):
		speed_max = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Minimum particle billboard scale.
@export_range(0.005, 0.5, 0.005) var size_min: float = 0.015:
	set(value):
		size_min = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Maximum particle billboard scale.
@export_range(0.005, 0.5, 0.005) var size_max: float = 0.045:
	set(value):
		size_max = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Pauses particle simulation when enabled.
@export var frozen: bool = false:
	set(value):
		frozen = value
		if is_inside_tree() and _is_initialized:
			_apply_frozen_state()

## Enables GPU curl-noise turbulence for realistic organic drift.
@export var turbulence_enabled: bool = true:
	set(value):
		turbulence_enabled = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Strength of curl-noise turbulence vector field.
@export_range(0.0, 2.0, 0.05) var turbulence_strength: float = 0.25:
	set(value):
		turbulence_strength = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Proximity fade distance against solid geometry in meters.
@export_range(0.0, 2.0, 0.05) var soft_particle_distance: float = 0.4:
	set(value):
		soft_particle_distance = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Near-plane distance where particles fade out to prevent screen clipping.
@export_range(0.1, 3.0, 0.1) var camera_fade_distance: float = 0.6:
	set(value):
		camera_fade_distance = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Enables additive blending for light shafts instead of alpha mixing.
@export var additive_blend: bool = true:
	set(value):
		additive_blend = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Enables particle deflection against GPUParticlesCollision3D shapes.
@export var enable_collision: bool = true:
	set(value):
		enable_collision = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Collision friction determining speed loss along surface boundaries.
@export_range(0.0, 1.0, 0.05) var collision_friction: float = 0.1:
	set(value):
		collision_friction = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Collision bounciness factor upon contact with collision shapes.
@export_range(0.0, 1.0, 0.05) var collision_bounce: float = 0.2:
	set(value):
		collision_bounce = value
		if is_inside_tree() and _is_initialized:
			_update_volume()

## Tracks initialization state to avoid premature updates in editor.
var _is_initialized: bool = false


## Initializes materials, particle settings, and assigns render Layer 10.
func _ready() -> void:
	print("DustVolume: Initializing on render Layer 10 (Volumetrics).")
	_setup_resources()
	_update_volume()
	_update_culling_bounds()
	_apply_frozen_state()
	_is_initialized = true


## Allocates and configures internal GPU materials and quad mesh pass.
func _setup_resources() -> void:
	layers = LAYER_VOLUMETRICS
	local_coords = false

	if not is_instance_valid(process_material):
		process_material = ParticleProcessMaterial.new()

	if not is_instance_valid(draw_pass_1):
		var quad: QuadMesh = QuadMesh.new()
		var mesh_mat: StandardMaterial3D = StandardMaterial3D.new()

		mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mesh_mat.billboard_keep_scale = true
		mesh_mat.vertex_color_use_as_albedo = true
		mesh_mat.albedo_texture = _generate_dust_texture()

		quad.material = mesh_mat
		draw_pass_1 = quad


## Generates a 32x32 radial gradient texture for round motes.
func _generate_dust_texture() -> Texture2D:
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])

	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	return tex


## Synchronizes exported inspector properties to GPU particle materials.
func _update_volume() -> void:
	if not is_instance_valid(process_material):
		return

	var p_mat: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if not is_instance_valid(p_mat):
		return

	amount = dust_density
	lifetime = maxf(lifetime_max, 0.1)

	p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p_mat.emission_box_extents = volume_size * 0.5
	p_mat.color = dust_color

	p_mat.initial_velocity_min = speed_min
	p_mat.initial_velocity_max = speed_max
	p_mat.gravity = Vector3(0.0, -0.015, 0.0)

	p_mat.scale_min = size_min
	p_mat.scale_max = size_max

	p_mat.turbulence_enabled = turbulence_enabled
	p_mat.turbulence_noise_strength = turbulence_strength
	p_mat.turbulence_noise_scale = 2.0
	p_mat.turbulence_noise_speed = Vector3(0.08, 0.04, 0.08)

	if enable_collision:
		p_mat.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		p_mat.collision_friction = collision_friction
		p_mat.collision_bounce = collision_bounce
	else:
		p_mat.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED

	var quad: QuadMesh = draw_pass_1 as QuadMesh
	if is_instance_valid(quad) and is_instance_valid(quad.material):
		var m_mat: StandardMaterial3D = quad.material as StandardMaterial3D
		if is_instance_valid(m_mat):
			m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m_mat.blend_mode = (
				BaseMaterial3D.BLEND_MODE_ADD if additive_blend else BaseMaterial3D.BLEND_MODE_MIX
			)
			m_mat.proximity_fade_enabled = soft_particle_distance > 0.0
			m_mat.proximity_fade_distance = soft_particle_distance
			m_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
			m_mat.distance_fade_min_distance = camera_fade_distance
			m_mat.distance_fade_max_distance = camera_fade_distance + 0.6

	visibility_aabb = AABB(-volume_size * 0.5, volume_size)


## Synchronizes [VisibleOnScreenEnabler3D] culling bounds with [member volume_size].
func _update_culling_bounds() -> void:
	if not has_node("CullingEnabler"):
		return
	var enabler: VisibleOnScreenEnabler3D = get_node("CullingEnabler") as VisibleOnScreenEnabler3D
	if is_instance_valid(enabler):
		enabler.aabb = AABB(-volume_size * 0.5, volume_size)
		print("DustVolume: Synchronized culling AABB bounds.")


## Toggles particle simulation speed to simulate freezing.
func _apply_frozen_state() -> void:
	speed_scale = 0.0 if frozen else 1.0
	print("DustVolume: Applied frozen state: ", frozen)
	frozen_changed.emit(frozen)


## Rebuilds all materials and updates particle volume parameters.
func rebuild_volume() -> void:
	print("DustVolume: Player/Editor invoked rebuild_volume.")
	_setup_resources()
	_update_volume()
	_update_culling_bounds()
	_apply_frozen_state()


## Sets frozen state and emits [signal frozen_changed].
func set_frozen(state: bool) -> void:
	print("DustVolume: Setting frozen state to: ", state)
	frozen = state
