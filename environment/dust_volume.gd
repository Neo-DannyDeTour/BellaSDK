@tool
## Volumetric dust emitter with GPU collisions and turbulence on Layer 10.
## Mirrored after Source func_dustvolume using [MaterialCache] for 60 FPS.
class_name DustVolume
extends GPUParticles3D

## Render layer bitmask for Layer 10 volumetrics configured from [CollisionLayers].
const LAYER_VOLUMETRICS: int = CollisionLayers.RENDER_MASK_VOLUMETRICS

## Emitted when [member frozen] state changes, passing [param is_frozen].
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

## Cached static radial gradient texture instance to prevent allocations.
static var _cached_dust_texture: Texture2D = null

## Cached dictionary of quad meshes indexed by material variant keys.
static var _cached_quads: Dictionary = {}

## Shared archetype material used to request variants from [MaterialCache].
static var _base_archetype_material: StandardMaterial3D = null

## Cached reference to child [VisibleOnScreenEnabler3D] culling node.
@onready var _culling_enabler: VisibleOnScreenEnabler3D = (
	NodeQuery.find_first_child_of_type(self, VisibleOnScreenEnabler3D) as VisibleOnScreenEnabler3D
)

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


## Configures internal GPU particle process material and quad draw pass.
func _setup_resources() -> void:
	print("DustVolume: Configuring resources and layer bitmask.")
	layers = LAYER_VOLUMETRICS
	local_coords = false

	if not is_instance_valid(process_material):
		process_material = ParticleProcessMaterial.new()

	var variant_key: String = _get_variant_key()
	var mat: StandardMaterial3D = _get_or_create_material(variant_key)
	draw_pass_1 = _get_or_create_quad(variant_key, mat)


## Returns the shared 32x32 radial gradient texture, creating it only once.
func _get_dust_texture() -> Texture2D:
	print("DustVolume: Fetching shared radial gradient texture.")
	if is_instance_valid(_cached_dust_texture):
		return _cached_dust_texture

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

	_cached_dust_texture = tex
	print("DustVolume: Generated and cached static radial dust texture.")
	return _cached_dust_texture


## Returns the base archetype [StandardMaterial3D] used for caching variants.
func _get_archetype_material() -> StandardMaterial3D:
	if not is_instance_valid(_base_archetype_material):
		_base_archetype_material = StandardMaterial3D.new()
		_base_archetype_material.resource_name = "DustVolumeArchetype"
	return _base_archetype_material


## Generates a unique cache key based on material shader blend and fade params.
func _get_variant_key() -> String:
	var blend_str: String = "add" if additive_blend else "mix"
	return (
		"dust_mat_%s_soft_%.2f_cam_%.2f" % [blend_str, soft_particle_distance, camera_fade_distance]
	)


## Retrieves cached material variant from [MaterialCache] or configures one.
func _get_or_create_material(variant_key: String) -> StandardMaterial3D:
	print("DustVolume: Fetching material from [MaterialCache]: ", variant_key)
	var archetype: StandardMaterial3D = _get_archetype_material()
	var cached_mat: Material = MaterialCache.get_variant(archetype, variant_key)
	var mat: StandardMaterial3D = cached_mat if cached_mat is StandardMaterial3D else null

	if not is_instance_valid(mat):
		mat = StandardMaterial3D.new()

	if not is_instance_valid(mat.albedo_texture):
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _get_dust_texture()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = (
			BaseMaterial3D.BLEND_MODE_ADD if additive_blend else BaseMaterial3D.BLEND_MODE_MIX
		)
		mat.proximity_fade_enabled = soft_particle_distance > 0.0
		mat.proximity_fade_distance = soft_particle_distance
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		mat.distance_fade_min_distance = camera_fade_distance
		mat.distance_fade_max_distance = camera_fade_distance + 0.6
		print("DustVolume: Configured new material variant parameters.")

	return mat


## Returns a cached [QuadMesh] configured with the specified material variant.
func _get_or_create_quad(variant_key: String, mat: StandardMaterial3D) -> QuadMesh:
	print("DustVolume: Resolving quad mesh for variant: ", variant_key)
	if _cached_quads.has(variant_key):
		var existing_quad: QuadMesh = (
			_cached_quads[variant_key] if _cached_quads[variant_key] is QuadMesh else null
		)
		if is_instance_valid(existing_quad):
			return existing_quad

	var quad: QuadMesh = QuadMesh.new()
	quad.material = mat
	_cached_quads[variant_key] = quad
	print("DustVolume: Created and cached shared [QuadMesh] for: ", variant_key)
	return quad


## Synchronizes exported inspector properties to GPU particle materials.
func _update_volume() -> void:
	print("DustVolume: Updating particle parameters and volume extents.")
	if not is_instance_valid(process_material):
		process_material = ParticleProcessMaterial.new()

	var p_mat: ParticleProcessMaterial = (
		process_material if process_material is ParticleProcessMaterial else null
	)
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

	var variant_key: String = _get_variant_key()
	var mat: StandardMaterial3D = _get_or_create_material(variant_key)
	var quad: QuadMesh = _get_or_create_quad(variant_key, mat)

	if draw_pass_1 != quad:
		draw_pass_1 = quad

	visibility_aabb = AABB(-volume_size * 0.5, volume_size)


## Resolves the child [VisibleOnScreenEnabler3D] node via cache or [NodeQuery].
func _get_culling_enabler() -> VisibleOnScreenEnabler3D:
	print("DustVolume: Resolving culling enabler node reference.")
	if not is_instance_valid(_culling_enabler):
		_culling_enabler = (
			NodeQuery.find_first_child_of_type(self, VisibleOnScreenEnabler3D)
			as VisibleOnScreenEnabler3D
		)
	return _culling_enabler


## Synchronizes [VisibleOnScreenEnabler3D] culling bounds with [member volume_size].
func _update_culling_bounds() -> void:
	print("DustVolume: Updating culling enabler bounds.")
	var enabler: VisibleOnScreenEnabler3D = _get_culling_enabler()
	if is_instance_valid(enabler):
		enabler.aabb = AABB(-volume_size * 0.5, volume_size)
		print("DustVolume: Synchronized culling AABB bounds to: ", enabler.aabb)


## Toggles particle simulation speed to simulate freezing and emits state signal.
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
