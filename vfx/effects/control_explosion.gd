## Procedural multi-phase explosion controller inspired by Remedy's Control.
## Coordinates ballistic liquid droplets, GPU collision vapor sub-emitters,
## volumetric core fire/smoke, shockwave refraction, and physics impulses.
@tool
class_name ControlExplosion
extends Node3D

## Emitted when all particle phases and light decay have completed.
## Passes this [ControlExplosion] instance so an object pool can reclaim it.
signal explosion_finished(explosion_node: ControlExplosion)

## Render Layer 1: Environment meshes.
const RENDER_LAYER_ENVIRONMENT: int = 1 << 0
## Render Layer 10: Volumetrics and refractive distortion effects.
const RENDER_LAYER_VOLUMETRICS: int = 1 << 9

## Physics Layer 1: Static environment geometry used for collision and occlusion.
const PHYSICS_LAYER_ENVIRONMENT: int = 1 << 0
## Physics Mask for blast targets: Player (2), Interactive (4), Debris (8), Enemies (16).
const PHYSICS_MASK_BLAST_TARGETS: int = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)

## Pre-allocated [StringName] instance uniform for shockwave normalized progress.
const PARAM_PROGRESS: StringName = &"explosion_progress"
## Pre-allocated [StringName] instance uniform for shockwave refraction intensity.
const PARAM_DISTORTION: StringName = &"distortion_strength"

@export_group("Blast Parameters")
@export var blast_radius: float = 8.5:
	set(value):
		blast_radius = maxf(value, 0.5)
		if is_instance_valid(self) and is_inside_tree() and is_instance_valid(_sphere_shape):
			_sphere_shape.radius = blast_radius
@export var blast_impulse: float = 28.0
@export var upward_lift_ratio: float = 0.35
@export var total_duration: float = 4.2
@export var shockwave_duration: float = 0.55
@export var auto_detonate_on_ready: bool = false
@export var loop: bool = false
@export var loop_interval: float = 0.0

@export_group("Custom Shaders (Optional)")
@export var droplet_shader: Shader
@export var smoke_shader: Shader
@export var shockwave_shader: Shader
@export var spark_shader: Shader

var _visibility_notifier: VisibleOnScreenNotifier3D
var _collision_heightfield: GPUParticlesCollisionHeightField3D
var _blast_light: OmniLight3D
var _shockwave_mesh: MeshInstance3D
var _core_fire_particles: GPUParticles3D
var _droplet_particles: GPUParticles3D
var _vapor_sub_particles: GPUParticles3D
var _spark_particles: GPUParticles3D

var _shockwave_material: ShaderMaterial
var _sphere_shape: SphereShape3D
var _shape_query: PhysicsShapeQueryParameters3D
var _ray_query: PhysicsRayQueryParameters3D
var _active_tween: Tween

var _is_detonating: bool = false
var _is_on_screen: bool = true
var _pending_blast_impulse: bool = false


## Initializes the node hierarchy, pre-allocates physics queries, and disables
## per-frame polling until [method detonate] is invoked.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_ensure_shaders_initialized()
	_build_explosion_hierarchy()
	_preallocate_physics_queries()

	if auto_detonate_on_ready or loop:
		if Engine.is_editor_hint():
			_is_on_screen = true
		call_deferred(&"detonate")


## Disconnects screen visibility signals and cleans up tweens when leaving the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(_active_tween):
		_active_tween.kill()
	if is_instance_valid(_visibility_notifier):
		if _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			_visibility_notifier.screen_entered.disconnect(_on_screen_entered)
		if _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			_visibility_notifier.screen_exited.disconnect(_on_screen_exited)


## Executes the radial blast impulse on a single synchronized physics frame,
## then immediately disables [method _physics_process] to preserve 60 FPS.
func _physics_process(_delta: float) -> void:
	if _pending_blast_impulse:
		_pending_blast_impulse = false
		_execute_blast_impulse()
	set_physics_process(false)


## Triggers the multi-stage explosion, waking the heightfield collider, particle
## emitters, shockwave mesh, and single-frame physics impulse query.
func detonate() -> void:
	print("ControlExplosion: Detonating at ", global_position)
	_is_detonating = true
	_pending_blast_impulse = true

	if is_instance_valid(_collision_heightfield):
		_collision_heightfield.update_mode = (
			GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
		)
		_collision_heightfield.force_update_transform()

	if is_instance_valid(_shockwave_mesh):
		_shockwave_mesh.visible = true
		_shockwave_mesh.scale = Vector3(0.2, 0.2, 0.2)
		_shockwave_mesh.set_instance_shader_parameter(PARAM_PROGRESS, 0.0)
		_shockwave_mesh.set_instance_shader_parameter(PARAM_DISTORTION, 0.05)

	if is_instance_valid(_blast_light):
		_blast_light.visible = true
		_blast_light.light_energy = 14.0
		_blast_light.omni_range = blast_radius * 1.8

	if is_instance_valid(_vapor_sub_particles):
		_vapor_sub_particles.restart()
		_vapor_sub_particles.emitting = true
	if is_instance_valid(_core_fire_particles):
		_core_fire_particles.restart()
		_core_fire_particles.emitting = true
	if is_instance_valid(_droplet_particles):
		_droplet_particles.restart()
		_droplet_particles.emitting = true
	if is_instance_valid(_spark_particles):
		_spark_particles.restart()
		_spark_particles.emitting = true

	if not Engine.is_editor_hint():
		var smoke_mgr: Node = get_node_or_null("/root/SmokeManager")
		if is_instance_valid(smoke_mgr) and smoke_mgr.has_method(&"carve_explosion"):
			smoke_mgr.call(&"carve_explosion", global_position, blast_radius, 3.5)

	_start_detonation_tween()
	set_physics_process(true)


## Spawns a native C++ [Tween] to drive shockwave expansion, light decay, and
## total lifetime completion without per-frame script polling.
func _start_detonation_tween() -> void:
	if is_instance_valid(_active_tween):
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_parallel(true)

	var target_scale: float = blast_radius * 1.6
	(
		_active_tween
		. tween_property(
			_shockwave_mesh,
			"scale",
			Vector3(target_scale, target_scale, target_scale),
			shockwave_duration
		)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	_active_tween.tween_method(_update_shockwave_and_light, 0.0, 1.0, shockwave_duration)
	_active_tween.tween_callback(_hide_transients).set_delay(shockwave_duration)
	_active_tween.tween_callback(_finish_explosion).set_delay(
		maxf(total_duration, shockwave_duration)
	)


## Updates per-instance shockwave progress and flickering light intensity during the blast.
func _update_shockwave_and_light(t: float) -> void:
	if is_instance_valid(_shockwave_mesh):
		_shockwave_mesh.set_instance_shader_parameter(PARAM_PROGRESS, t)
	if is_instance_valid(_blast_light):
		var elapsed: float = t * shockwave_duration
		var flicker: float = 0.85 + 0.15 * sin(elapsed * 55.0)
		_blast_light.light_energy = lerpf(14.0, 0.0, t * t) * flicker


## Hides the transient shockwave mesh and omni light once the initial flash completes.
func _hide_transients() -> void:
	if is_instance_valid(_shockwave_mesh):
		_shockwave_mesh.visible = false
	if is_instance_valid(_blast_light):
		_blast_light.visible = false


## Evaluates radial physics overlap on layers 2, 3, 4, and 5, verifying line-of-sight
## against Layer 1 (Environment) before applying impulses to [RigidBody3D] targets.
func _execute_blast_impulse() -> void:
	var world: World3D = get_world_3d()
	if not is_instance_valid(world):
		return

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var origin: Vector3 = global_position
	var max_dist_sq: float = blast_radius * blast_radius
	_shape_query.transform = Transform3D(Basis.IDENTITY, origin)

	var hits: Array[Dictionary] = space_state.intersect_shape(_shape_query, 32)
	var hit_count: int = hits.size()

	for i: int in range(hit_count):
		var hit_dict: Dictionary = hits[i]
		var collider: Object = hit_dict.get("collider")
		var rigid_body: RigidBody3D = collider as RigidBody3D
		if not is_instance_valid(rigid_body):
			continue

		var target_pos: Vector3 = rigid_body.global_position
		var dist_sq: float = origin.distance_squared_to(target_pos)
		if dist_sq < 0.000001 or dist_sq > max_dist_sq:
			continue

		_ray_query.from = origin
		_ray_query.to = target_pos
		var occlusion: Dictionary = space_state.intersect_ray(_ray_query)
		if not occlusion.is_empty() and occlusion.get("collider") != rigid_body:
			continue

		var dist: float = sqrt(dist_sq)
		var falloff: float = clampf(1.0 - (dist / blast_radius), 0.0, 1.0)
		var to_target: Vector3 = target_pos - origin
		var dir: Vector3 = (to_target / dist + Vector3.UP * upward_lift_ratio).normalized()
		var final_impulse: Vector3 = dir * (blast_impulse * falloff * falloff)
		rigid_body.apply_central_impulse(final_impulse)


## Finishes the active detonation state, resets visibility, emits [signal explosion_finished],
## and schedules the next cycle if [member loop] is active.
func _finish_explosion() -> void:
	_is_detonating = false
	if is_instance_valid(_shockwave_mesh):
		_shockwave_mesh.visible = false
	if is_instance_valid(_blast_light):
		_blast_light.visible = false
	#print("ControlExplosion: Detonation sequence finished.")
	explosion_finished.emit(self)

	if loop and is_inside_tree():
		if loop_interval <= 0.0:
			detonate()
		else:
			get_tree().create_timer(loop_interval, false).timeout.connect(
				_on_loop_timeout, CONNECT_ONE_SHOT
			)


## Restores transient visibility when the explosion enters the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	if _is_detonating and is_instance_valid(_blast_light) and _blast_light.light_energy > 0.01:
		if is_instance_valid(_shockwave_mesh):
			_shockwave_mesh.visible = true
		_blast_light.visible = true


## Hides transient light and refraction meshes when off-screen to save render cost.
func _on_screen_exited() -> void:
	_is_on_screen = false
	if is_instance_valid(_shockwave_mesh):
		_shockwave_mesh.visible = false
	if is_instance_valid(_blast_light):
		_blast_light.visible = false


## Callback triggered by the loop interval timer to detonate again.
func _on_loop_timeout() -> void:
	if loop and is_inside_tree():
		detonate()


## Pre-allocates reusable [SphereShape3D] and query objects to avoid GC allocations.
func _preallocate_physics_queries() -> void:
	_sphere_shape = SphereShape3D.new()
	_sphere_shape.radius = blast_radius

	_shape_query = PhysicsShapeQueryParameters3D.new()
	_shape_query.shape = _sphere_shape
	_shape_query.collision_mask = PHYSICS_MASK_BLAST_TARGETS
	_shape_query.collide_with_bodies = true
	_shape_query.collide_with_areas = false

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = PHYSICS_LAYER_ENVIRONMENT
	_ray_query.collide_with_bodies = true
	_ray_query.collide_with_areas = false


## Builds all required child nodes, meshes, and GPU particle materials procedurally.
func _build_explosion_hierarchy() -> void:
	_visibility_notifier = VisibleOnScreenNotifier3D.new()
	var extent: float = blast_radius * 1.5
	_visibility_notifier.aabb = AABB(
		Vector3(-extent, -extent, -extent), Vector3(extent * 2.0, extent * 2.0, extent * 2.0)
	)
	_visibility_notifier.screen_entered.connect(_on_screen_entered)
	_visibility_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_visibility_notifier)

	_collision_heightfield = GPUParticlesCollisionHeightField3D.new()
	_collision_heightfield.size = Vector3(
		blast_radius * 2.5, blast_radius * 2.0, blast_radius * 2.5
	)
	_collision_heightfield.resolution = (GPUParticlesCollisionHeightField3D.RESOLUTION_512)
	_collision_heightfield.update_mode = (GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED)
	_collision_heightfield.cull_mask = RENDER_LAYER_ENVIRONMENT
	add_child(_collision_heightfield)

	_blast_light = OmniLight3D.new()
	_blast_light.light_color = Color(1.0, 0.62, 0.25)
	_blast_light.light_energy = 0.0
	_blast_light.omni_range = blast_radius * 1.8
	_blast_light.omni_attenuation = 1.6
	_blast_light.shadow_enabled = true
	_blast_light.visible = false
	add_child(_blast_light)

	_build_shockwave_node()
	_build_vapor_sub_emitter()
	_build_droplet_emitter()
	_build_core_fire_emitter()
	_build_spark_emitter()


## Creates the refractive shockwave [MeshInstance3D] on Render Layer 10 (Volumetrics).
func _build_shockwave_node() -> void:
	_shockwave_mesh = MeshInstance3D.new()
	_shockwave_mesh.layers = RENDER_LAYER_VOLUMETRICS
	_shockwave_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shockwave_mesh.visible = false

	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16

	_shockwave_material = ShaderMaterial.new()
	_shockwave_material.shader = shockwave_shader
	sphere.material = _shockwave_material
	_shockwave_mesh.mesh = sphere
	add_child(_shockwave_mesh)


## Creates the GPU sub-emitter that spawns expanding smoke plumes where droplets collide.
func _build_vapor_sub_emitter() -> void:
	_vapor_sub_particles = GPUParticles3D.new()
	_vapor_sub_particles.name = "VaporSubParticles"
	_vapor_sub_particles.layers = RENDER_LAYER_ENVIRONMENT | RENDER_LAYER_VOLUMETRICS
	_vapor_sub_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vapor_sub_particles.emitting = false
	_vapor_sub_particles.amount = 320
	_vapor_sub_particles.lifetime = 2.2
	_vapor_sub_particles.explosiveness = 0.0
	_vapor_sub_particles.fixed_fps = 60
	_vapor_sub_particles.visibility_aabb = _visibility_notifier.aabb

	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 75.0
	proc.initial_velocity_min = 0.6
	proc.initial_velocity_max = 2.4
	proc.gravity = Vector3(0.0, 1.3, 0.0)
	proc.damping_min = 1.5
	proc.damping_max = 3.0
	proc.scale_min = 0.45
	proc.scale_max = 1.25
	proc.color_ramp = _create_fire_to_smoke_ramp(false)
	_vapor_sub_particles.process_material = proc

	var puff_mesh: SphereMesh = SphereMesh.new()
	puff_mesh.radius = 0.42
	puff_mesh.height = 0.84
	puff_mesh.radial_segments = 12
	puff_mesh.rings = 6

	var smoke_mat: ShaderMaterial = ShaderMaterial.new()
	smoke_mat.shader = smoke_shader
	puff_mesh.material = smoke_mat
	_vapor_sub_particles.draw_pass_1 = puff_mesh
	add_child(_vapor_sub_particles)


## Creates the primary ballistic liquid droplet emitter wired to [_vapor_sub_particles].
func _build_droplet_emitter() -> void:
	_droplet_particles = GPUParticles3D.new()
	_droplet_particles.name = "LiquidDropletParticles"
	_droplet_particles.layers = RENDER_LAYER_ENVIRONMENT
	_droplet_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_droplet_particles.emitting = false
	_droplet_particles.one_shot = true
	_droplet_particles.amount = 140
	_droplet_particles.lifetime = 1.6
	_droplet_particles.explosiveness = 0.94
	_droplet_particles.fixed_fps = 60
	_droplet_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	_droplet_particles.visibility_aabb = _visibility_notifier.aabb

	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 115.0
	proc.initial_velocity_min = 8.0
	proc.initial_velocity_max = 21.0
	proc.gravity = Vector3(0.0, -18.5, 0.0)
	proc.damping_min = 0.8
	proc.damping_max = 2.2
	proc.scale_min = 0.07
	proc.scale_max = 0.18
	proc.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	proc.collision_friction = 0.65
	proc.collision_bounce = 0.12
	proc.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	proc.sub_emitter_amount_at_collision = 2
	proc.color_ramp = _create_droplet_cooling_ramp()
	_droplet_particles.process_material = proc

	var drop_mesh: SphereMesh = SphereMesh.new()
	drop_mesh.radius = 0.12
	drop_mesh.height = 0.32
	drop_mesh.radial_segments = 8
	drop_mesh.rings = 4

	var drop_mat: ShaderMaterial = ShaderMaterial.new()
	drop_mat.shader = droplet_shader
	drop_mesh.material = drop_mat
	_droplet_particles.draw_pass_1 = drop_mesh
	add_child(_droplet_particles)
	_droplet_particles.sub_emitter = _vapor_sub_particles.get_path()


## Creates the central high-energy fireball and turbulent smoke cloud emitter.
func _build_core_fire_emitter() -> void:
	_core_fire_particles = GPUParticles3D.new()
	_core_fire_particles.name = "CoreFireSmokeParticles"
	_core_fire_particles.layers = RENDER_LAYER_ENVIRONMENT | RENDER_LAYER_VOLUMETRICS
	_core_fire_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core_fire_particles.emitting = false
	_core_fire_particles.one_shot = true
	_core_fire_particles.amount = 64
	_core_fire_particles.lifetime = 2.6
	_core_fire_particles.explosiveness = 0.92
	_core_fire_particles.fixed_fps = 60
	_core_fire_particles.visibility_aabb = _visibility_notifier.aabb

	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.45
	proc.direction = Vector3.UP
	proc.spread = 180.0
	proc.initial_velocity_min = 2.5
	proc.initial_velocity_max = 9.5
	proc.gravity = Vector3(0.0, 2.2, 0.0)
	proc.damping_min = 3.5
	proc.damping_max = 6.5
	proc.scale_min = 0.9
	proc.scale_max = 2.4
	proc.color_ramp = _create_fire_to_smoke_ramp(true)
	_core_fire_particles.process_material = proc

	var billow_mesh: SphereMesh = SphereMesh.new()
	billow_mesh.radius = 0.75
	billow_mesh.height = 1.5
	billow_mesh.radial_segments = 16
	billow_mesh.rings = 8

	var fire_mat: ShaderMaterial = ShaderMaterial.new()
	fire_mat.shader = smoke_shader
	billow_mesh.material = fire_mat
	_core_fire_particles.draw_pass_1 = billow_mesh
	add_child(_core_fire_particles)


## Creates the high-speed bouncing spark emitter.
func _build_spark_emitter() -> void:
	_spark_particles = GPUParticles3D.new()
	_spark_particles.name = "SparkParticles"
	_spark_particles.layers = RENDER_LAYER_ENVIRONMENT
	_spark_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark_particles.emitting = false
	_spark_particles.one_shot = true
	_spark_particles.amount = 180
	_spark_particles.lifetime = 1.2
	_spark_particles.explosiveness = 0.96
	_spark_particles.fixed_fps = 60
	_spark_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	_spark_particles.visibility_aabb = _visibility_notifier.aabb

	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 145.0
	proc.initial_velocity_min = 14.0
	proc.initial_velocity_max = 32.0
	proc.gravity = Vector3(0.0, -14.0, 0.0)
	proc.damping_min = 1.2
	proc.damping_max = 3.0
	proc.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	proc.collision_bounce = 0.55
	proc.collision_friction = 0.15
	proc.color_ramp = _create_droplet_cooling_ramp()
	_spark_particles.process_material = proc

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.04, 0.42)

	var spark_mat: ShaderMaterial = ShaderMaterial.new()
	spark_mat.shader = spark_shader
	quad.material = spark_mat
	_spark_particles.draw_pass_1 = quad
	add_child(_spark_particles)


## Builds a [GradientTexture1D] encoding heat in the Red channel and erosion in Alpha.
func _create_fire_to_smoke_ramp(intense_core: bool) -> GradientTexture1D:
	var grad: Gradient = Gradient.new()
	var start_heat: float = 1.0 if intense_core else 0.42
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(start_heat, 1.0, 1.0, 0.95))
	grad.add_point(0.28, Color(start_heat * 0.45, 0.5, 0.5, 0.85))
	grad.set_offset(grad.get_point_count() - 1, 1.0)
	grad.set_color(grad.get_point_count() - 1, Color(0.0, 0.0, 0.0, 0.0))

	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


## Builds a [GradientTexture1D] encoding droplet and spark cooling over lifetime.
func _create_droplet_cooling_ramp() -> GradientTexture1D:
	var grad: Gradient = Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.add_point(0.65, Color(0.8, 0.4, 0.1, 0.55))
	grad.set_offset(grad.get_point_count() - 1, 1.0)
	grad.set_color(grad.get_point_count() - 1, Color(0.1, 0.1, 0.1, 0.0))

	var tex: GradientTexture1D = GradientTexture1D.new()
	tex.gradient = grad
	tex.width = 64
	return tex


## Compiles lightweight fallback shaders if external `.gdshader` files are not assigned.
func _ensure_shaders_initialized() -> void:
	if not is_instance_valid(droplet_shader):
		droplet_shader = Shader.new()
		droplet_shader.code = (
			"shader_type spatial;\n"
			+ "void vertex() { VERTEX.y *= mix(1.0, 2.8, COLOR.a); }\n"
			+ "void fragment() {\n"
			+ "	ALBEDO = vec3(0.08);\n"
			+ "	ROUGHNESS = 0.2;\n"
			+ "	EMISSION = vec3(4.0, 1.4, 0.2) * (COLOR.a * COLOR.a);\n"
			+ "}\n"
		)
	if not is_instance_valid(smoke_shader):
		smoke_shader = Shader.new()
		smoke_shader.code = (
			"shader_type spatial;\n"
			+ "render_mode blend_mix, depth_draw_never;\n"
			+ "void fragment() {\n"
			+ "	ALBEDO = vec3(0.09);\n"
			+ "	EMISSION = vec3(3.5, 0.9, 0.15) * smoothstep(0.2, 0.9, COLOR.r);\n"
			+ "	ALPHA = clamp(COLOR.a * dot(NORMAL, VIEW), 0.0, 1.0);\n"
			+ "}\n"
		)
	if not is_instance_valid(shockwave_shader):
		shockwave_shader = Shader.new()
		shockwave_shader.code = (
			"shader_type spatial;\n"
			+ "render_mode blend_mix, depth_draw_never, unshaded;\n"
			+ "uniform sampler2D screen_texture : hint_screen_texture;\n"
			+ "instance uniform float explosion_progress = 0.0;\n"
			+ "instance uniform float distortion_strength = 0.045;\n"
			+ "void fragment() {\n"
			+ "	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);\n"
			+ "	float fade = 1.0 - clamp(explosion_progress, 0.0, 1.0);\n"
			+ "	vec2 uv = SCREEN_UV + NORMAL.xy * f * distortion_strength * fade;\n"
			+ "	ALBEDO = texture(screen_texture, uv).rgb;\n"
			+ "	ALPHA = clamp(f * fade, 0.0, 1.0);\n"
			+ "}\n"
		)
	if not is_instance_valid(spark_shader):
		spark_shader = Shader.new()
		spark_shader.code = (
			"shader_type spatial;\n"
			+ "render_mode blend_add, depth_draw_never, cull_disabled, unshaded;\n"
			+ "void fragment() {\n"
			+ "	ALBEDO = vec3(5.0, 2.2, 0.4) * COLOR.rgb;\n"
			+ "	ALPHA = COLOR.a;\n"
			+ "}\n"
		)
