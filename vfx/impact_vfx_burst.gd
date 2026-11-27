## Pooled one-shot 3-pass bullet impact VFX burst (lit dust/smoke, tumbling debris, sparks).
class_name ImpactVfxBurst
extends Node3D

## Preloaded Half-Life 2 lit soft-billboard smoke shader.
const SMOKE_SHADER: Shader = preload("res://vfx/smoke_hl2_lit.gdshader")

## Preloaded 4x4 smoke albedo/alpha/erosion atlas texture.
const SMOKE_ALBEDO_ATLAS: Texture2D = preload("res://assets/vfx/smoke/hl2_smoke_cloud_4x4.png")

## Preloaded 4x4 smoke tangent-space normal atlas texture.
const SMOKE_NORMAL_ATLAS: Texture2D = preload("res://assets/vfx/smoke/hl2_smoke_normal_4x4.png")

## Preloaded 2x2 impact debris chip/splinter/clod atlas texture.
const DEBRIS_ATLAS: Texture2D = preload("res://assets/vfx/impacts/impact_debris_2x2.png")

## Pre-allocated [StringName] shader parameter for smoke albedo atlas.
const PARAM_ALBEDO_ATLAS: StringName = &"albedo_atlas"

## Pre-allocated [StringName] shader parameter for smoke normal atlas.
const PARAM_NORMAL_ATLAS: StringName = &"normal_atlas"

## Pre-allocated [StringName] shader parameter for atlas grid dimensions.
const PARAM_ATLAS_GRID: StringName = &"atlas_grid"

## Pre-allocated [StringName] shader parameter for soft particle wall fade distance.
const PARAM_SOFT_PARTICLE_DISTANCE: StringName = &"soft_particle_distance"

## Pre-allocated [StringName] shader parameter for camera near fade distance.
const PARAM_NEAR_FADE_DISTANCE: StringName = &"near_fade_distance"

## Pre-allocated [StringName] shader parameter for forward light scatter strength.
const PARAM_SCATTER_STRENGTH: StringName = &"scatter_strength"

## Pre-allocated [StringName] shader parameter for Half-Lambert wrap diffuse bias.
const PARAM_WRAP_DIFFUSE_BIAS: StringName = &"wrap_diffuse_bias"

## Pre-allocated [StringName] shader parameter for ambient lighting floor.
const PARAM_AMBIENT_FLOOR: StringName = &"ambient_floor"

## Pre-allocated [StringName] shader parameter for normal perturbation strength.
const PARAM_NORMAL_STRENGTH: StringName = &"normal_strength"

## Pre-allocated [StringName] instance shader parameter for per-surface dust/smoke tint.
const INSTANCE_TINT_COLOR: StringName = &"tint_color"

## Pre-allocated [StringName] instance shader parameter for per-surface dust density.
const INSTANCE_DENSITY_SCALE: StringName = &"density_scale"

## Pre-allocated [StringName] instance shader parameter for lifetime alpha erosion bias.
const INSTANCE_EROSION_BIAS: StringName = &"erosion_bias"

## Shared HL2 smoke shader material across all pooled bursts; per-surface tint uses instance params.
static var _shared_smoke_mat: ShaderMaterial = null

## Shared smoke quad mesh referencing [member _shared_smoke_mat].
static var _shared_smoke_mesh: QuadMesh = null

## Shared smoke [ParticleProcessMaterial] configured for normal-aligned puff + buoyancy.
static var _shared_smoke_proc: ParticleProcessMaterial = null

## Cached per-surface [StandardMaterial3D] variants for [member _debris_chips].
static var _shared_debris_mats: Dictionary[SurfaceClassifier.SurfaceType, StandardMaterial3D] = {}

## Shared debris quad mesh using [constant DEBRIS_ATLAS].
static var _shared_debris_mesh: QuadMesh = null

## Shared debris [ParticleProcessMaterial] with gravity and spin.
static var _shared_debris_proc: ParticleProcessMaterial = null

## Shared additive HDR spark quad mesh.
static var _shared_spark_mesh: QuadMesh = null

## Shared velocity-aligned spark [ParticleProcessMaterial].
static var _shared_spark_proc: ParticleProcessMaterial = null

## Child emitter driving surface-tinted billowing dust, sawdust, scorch, or mist.
var _smoke_puff: GPUParticles3D = null

## Child emitter driving gravity-affected tumbling chips, splinters, clods, or shards.
var _debris_chips: GPUParticles3D = null

## Child emitter driving additive HDR velocity-aligned sparks on metal/concrete impacts.
var _metal_sparks: GPUParticles3D = null


## Builds shared GPU resources once and instantiates the 3 child [GPUParticles3D] emitters.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	_ensure_shared_resources()

	_smoke_puff = _create_emitter(
		"SmokePuff", 8, 0.72, 0.92, _shared_smoke_proc, _shared_smoke_mesh
	)
	_debris_chips = _create_emitter(
		"DebrisChips", 10, 0.55, 0.96, _shared_debris_proc, _shared_debris_mesh
	)
	_metal_sparks = _create_emitter(
		"MetalSparks", 14, 0.28, 0.98, _shared_spark_proc, _shared_spark_mesh
	)

	add_child(_smoke_puff)
	add_child(_debris_chips)
	add_child(_metal_sparks)

	assert(is_instance_valid(_smoke_puff), "ImpactVfxBurst: SmokePuff missing.")
	assert(is_instance_valid(_debris_chips), "ImpactVfxBurst: DebrisChips missing.")
	assert(is_instance_valid(_metal_sparks), "ImpactVfxBurst: MetalSparks missing.")


## Orients local +Y along [param hit_normal], sets surface shader params, and restarts emitters.
func play(hit_pos: Vector3, hit_normal: Vector3, surface: SurfaceClassifier.SurfaceType) -> void:
	var normal: Vector3 = hit_normal.normalized() if not hit_normal.is_zero_approx() else Vector3.UP
	var ref_vec: Vector3 = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var tangent: Vector3 = ref_vec.cross(normal).normalized()
	var bitangent: Vector3 = normal.cross(tangent).normalized()
	global_transform = Transform3D(Basis(tangent, normal, bitangent), hit_pos)

	_apply_surface_smoke(surface)
	_apply_surface_debris(surface)
	_apply_surface_sparks(surface)


## Stops emission and hides all child emitters cleanly on scene transitions.
func reset() -> void:
	if is_instance_valid(_smoke_puff):
		_smoke_puff.emitting = false
		_smoke_puff.visible = false
	if is_instance_valid(_debris_chips):
		_debris_chips.emitting = false
		_debris_chips.visible = false
	if is_instance_valid(_metal_sparks):
		_metal_sparks.emitting = false
		_metal_sparks.visible = false


## Configures and restarts [member _smoke_puff] instance shader parameters for [param surface].
func _apply_surface_smoke(surface: SurfaceClassifier.SurfaceType) -> void:
	if not is_instance_valid(_smoke_puff):
		return

	var tint: Color = Color(0.76, 0.75, 0.72, 0.52)
	var density: float = 0.95
	var erosion: float = -0.05
	var ratio: float = 1.0

	match surface:
		SurfaceClassifier.SurfaceType.WOOD:
			tint = Color(0.72, 0.56, 0.36, 0.48)
			density = 0.8
			erosion = 0.0
			ratio = 0.85
		SurfaceClassifier.SurfaceType.METAL:
			tint = Color(0.24, 0.24, 0.26, 0.42)
			density = 0.55
			erosion = 0.15
			ratio = 0.5
		SurfaceClassifier.SurfaceType.DIRT:
			tint = Color(0.55, 0.42, 0.28, 0.56)
			density = 1.05
			erosion = -0.08
			ratio = 1.0
		SurfaceClassifier.SurfaceType.GLASS:
			tint = Color(0.88, 0.93, 0.96, 0.38)
			density = 0.5
			erosion = 0.12
			ratio = 0.65
		_:
			pass

	_smoke_puff.set_instance_shader_parameter(INSTANCE_TINT_COLOR, tint)
	_smoke_puff.set_instance_shader_parameter(INSTANCE_DENSITY_SCALE, density)
	_smoke_puff.set_instance_shader_parameter(INSTANCE_EROSION_BIAS, erosion)
	_smoke_puff.amount_ratio = ratio
	_smoke_puff.visible = true
	_smoke_puff.restart()
	_smoke_puff.emitting = true


## Configures and restarts [member _debris_chips] material and count ratio for [param surface].
func _apply_surface_debris(surface: SurfaceClassifier.SurfaceType) -> void:
	if not is_instance_valid(_debris_chips):
		return

	var debris_mat: StandardMaterial3D = (
		_shared_debris_mats[surface]
		if _shared_debris_mats.has(surface)
		else _shared_debris_mats[SurfaceClassifier.SurfaceType.CONCRETE]
	)
	var ratio: float = 0.9
	match surface:
		SurfaceClassifier.SurfaceType.WOOD:
			ratio = 1.0
		SurfaceClassifier.SurfaceType.METAL:
			ratio = 0.3
		SurfaceClassifier.SurfaceType.DIRT:
			ratio = 1.0
		SurfaceClassifier.SurfaceType.GLASS:
			ratio = 1.0
		_:
			pass

	_debris_chips.material_override = debris_mat
	_debris_chips.amount_ratio = ratio
	_debris_chips.visible = true
	_debris_chips.restart()
	_debris_chips.emitting = true


## Triggers [member _metal_sparks] as full burst on METAL, micro-sparks on CONCRETE, or skips.
func _apply_surface_sparks(surface: SurfaceClassifier.SurfaceType) -> void:
	if not is_instance_valid(_metal_sparks):
		return

	if surface == SurfaceClassifier.SurfaceType.METAL:
		_metal_sparks.amount_ratio = 1.0
		_metal_sparks.visible = true
		_metal_sparks.restart()
		_metal_sparks.emitting = true
	elif surface == SurfaceClassifier.SurfaceType.CONCRETE:
		_metal_sparks.amount_ratio = 0.25
		_metal_sparks.visible = true
		_metal_sparks.restart()
		_metal_sparks.emitting = true
	else:
		_metal_sparks.emitting = false
		_metal_sparks.visible = false


## Instantiates a pooled world-space [GPUParticles3D] emitter on Render Layer 10.
func _create_emitter(
	node_name: String,
	count: int,
	life: float,
	explosive: float,
	proc_mat: ParticleProcessMaterial,
	mesh: QuadMesh
) -> GPUParticles3D:
	var emitter: GPUParticles3D = GPUParticles3D.new()
	emitter.name = node_name
	emitter.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	emitter.local_coords = false
	emitter.one_shot = true
	emitter.emitting = false
	emitter.visible = false
	emitter.amount = count
	emitter.lifetime = life
	emitter.explosiveness = explosive
	emitter.fixed_fps = 60
	emitter.visibility_aabb = AABB(Vector3(-3.0, -3.0, -3.0), Vector3(6.0, 6.0, 6.0))
	emitter.process_material = proc_mat
	emitter.draw_pass_1 = mesh
	return emitter


## Lazily builds shared GPU materials, meshes, and process curves once across the entire pool.
static func _ensure_shared_resources() -> void:
	if is_instance_valid(_shared_smoke_mat):
		return

	_shared_smoke_mat = ShaderMaterial.new()
	_shared_smoke_mat.shader = SMOKE_SHADER
	_shared_smoke_mat.set_shader_parameter(PARAM_ALBEDO_ATLAS, SMOKE_ALBEDO_ATLAS)
	_shared_smoke_mat.set_shader_parameter(PARAM_NORMAL_ATLAS, SMOKE_NORMAL_ATLAS)
	_shared_smoke_mat.set_shader_parameter(PARAM_ATLAS_GRID, Vector2(4.0, 4.0))
	_shared_smoke_mat.set_shader_parameter(PARAM_SOFT_PARTICLE_DISTANCE, 0.35)
	_shared_smoke_mat.set_shader_parameter(PARAM_NEAR_FADE_DISTANCE, 0.45)
	_shared_smoke_mat.set_shader_parameter(PARAM_SCATTER_STRENGTH, 0.65)
	_shared_smoke_mat.set_shader_parameter(PARAM_WRAP_DIFFUSE_BIAS, 0.78)
	_shared_smoke_mat.set_shader_parameter(PARAM_AMBIENT_FLOOR, 0.12)
	_shared_smoke_mat.set_shader_parameter(PARAM_NORMAL_STRENGTH, 0.20)

	_shared_smoke_mesh = QuadMesh.new()
	_shared_smoke_mesh.size = Vector2(0.58, 0.58)
	_shared_smoke_mesh.material = _shared_smoke_mat

	_shared_smoke_proc = _build_smoke_process_material()

	_shared_debris_mats[SurfaceClassifier.SurfaceType.CONCRETE] = _build_debris_material(
		Color(0.62, 0.61, 0.59, 1.0), 0.9
	)
	_shared_debris_mats[SurfaceClassifier.SurfaceType.WOOD] = _build_debris_material(
		Color(0.68, 0.48, 0.26, 1.0), 0.85
	)
	_shared_debris_mats[SurfaceClassifier.SurfaceType.METAL] = _build_debris_material(
		Color(0.32, 0.34, 0.38, 1.0), 0.35
	)
	_shared_debris_mats[SurfaceClassifier.SurfaceType.DIRT] = _build_debris_material(
		Color(0.42, 0.31, 0.19, 1.0), 0.95
	)
	_shared_debris_mats[SurfaceClassifier.SurfaceType.GLASS] = _build_debris_material(
		Color(0.84, 0.94, 0.98, 0.85), 0.15
	)

	_shared_debris_mesh = QuadMesh.new()
	_shared_debris_mesh.size = Vector2(0.06, 0.06)

	_shared_debris_proc = _build_debris_process_material()

	var spark_mat: StandardMaterial3D = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.albedo_color = Color(4.0, 2.2, 0.65, 1.0)

	_shared_spark_mesh = QuadMesh.new()
	_shared_spark_mesh.size = Vector2(0.018, 0.16)
	_shared_spark_mesh.material = spark_mat

	_shared_spark_proc = _build_spark_process_material()


## Builds the shared [ParticleProcessMaterial] for expanding buoyant impact dust/smoke puffs.
static func _build_smoke_process_material() -> ParticleProcessMaterial:
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.05
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 35.0
	proc.initial_velocity_min = 0.8
	proc.initial_velocity_max = 2.0
	proc.gravity = Vector3(0.0, 0.55, 0.0)
	proc.damping_min = 2.8
	proc.damping_max = 4.5
	proc.angle_min = -180.0
	proc.angle_max = 180.0
	proc.angular_velocity_min = -45.0
	proc.angular_velocity_max = 45.0
	proc.scale_min = 0.65
	proc.scale_max = 1.25
	proc.anim_offset_min = 0.0
	proc.anim_offset_max = 1.0
	proc.anim_speed_min = 0.5
	proc.anim_speed_max = 1.0

	var scale_curve: Curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.45))
	scale_curve.add_point(Vector2(0.35, 1.05))
	scale_curve.add_point(Vector2(1.0, 1.45))
	var scale_tex: CurveTexture = CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex

	var alpha_curve: Curve = Curve.new()
	alpha_curve.add_point(Vector2(0.0, 0.9))
	alpha_curve.add_point(Vector2(0.45, 0.7))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_tex: CurveTexture = CurveTexture.new()
	alpha_tex.curve = alpha_curve
	proc.alpha_curve = alpha_tex
	return proc


## Builds a billboard 2x2 flipbook [StandardMaterial3D] for debris chips.
static func _build_debris_material(tint: Color, rough: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = tint
	mat.albedo_texture = DEBRIS_ATLAS
	mat.roughness = rough
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 2
	mat.particles_anim_v_frames = 2
	mat.particles_anim_loop = false
	return mat


## Builds the shared [ParticleProcessMaterial] for ballistic tumbling surface chips.
static func _build_debris_process_material() -> ParticleProcessMaterial:
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.03
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 48.0
	proc.initial_velocity_min = 2.5
	proc.initial_velocity_max = 6.2
	proc.gravity = Vector3(0.0, -14.0, 0.0)
	proc.damping_min = 0.8
	proc.damping_max = 1.8
	proc.angle_min = -180.0
	proc.angle_max = 180.0
	proc.angular_velocity_min = -360.0
	proc.angular_velocity_max = 360.0
	proc.scale_min = 0.55
	proc.scale_max = 1.15
	proc.anim_offset_min = 0.0
	proc.anim_offset_max = 1.0

	var scale_curve: Curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.7, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex: CurveTexture = CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	return proc


## Builds the shared [ParticleProcessMaterial] for velocity-aligned additive sparks.
static func _build_spark_process_material() -> ParticleProcessMaterial:
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.particle_flag_align_y = true
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.02
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 52.0
	proc.initial_velocity_min = 4.5
	proc.initial_velocity_max = 10.5
	proc.gravity = Vector3(0.0, -12.0, 0.0)
	proc.damping_min = 1.5
	proc.damping_max = 3.5
	proc.scale_min = 0.5
	proc.scale_max = 1.2

	var scale_curve: Curve = Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.6, 0.75))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex: CurveTexture = CurveTexture.new()
	scale_tex.curve = scale_curve
	proc.scale_curve = scale_tex
	return proc
