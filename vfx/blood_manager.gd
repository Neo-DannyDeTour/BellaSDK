## Pooled blood particle and procedural surface decal manager for 60 FPS gore VFX.
#class_name BloodManager
extends Node3D

## Preloaded directional droplet spray shader resource.
const SPRAY_SHADER: Shader = preload("res://vfx/blood_spray.gdshader")

## Preloaded lingering aerosol mist shader resource for fatal bursts.
const MIST_SHADER: Shader = preload("res://vfx/blood_mist.gdshader")

## Pre-allocated property path for decal alpha tweening.
const PROP_MODULATE_ALPHA: NodePath = ^"modulate:a"

## Number of pooled directional hit spray [GPUParticles3D] emitters (16 dual impacts).
const HIT_POOL_SIZE: int = 32

## Number of pooled multi-emitter death burst [Node3D] clusters.
const DEATH_POOL_SIZE: int = 10

## Number of pooled environment [Decal] nodes.
const DECAL_POOL_SIZE: int = 40

## Number of procedural splatter texture variations baked at startup.
const SPLATTER_VARIATIONS: int = 4

## Resolution in pixels for each procedural splatter texture.
const TEX_SIZE: int = 128

## Physics Layer 1 bitmask (Environment) for surface decal raycasting.
const ENV_COLLISION_MASK: int = 1 << 0

## Render Layer 1 bitmask (Environment) for decal projection culling.
const ENV_RENDER_LAYER: int = 1 << 0

## Radial clearance offset placing entry/exit emitters outside the 0.5m goon capsule.
const CAPSULE_SURFACE_OFFSET: float = 0.58

## Duration in seconds for blood decals to fade out via [Tween].
const DECAL_FADE_DURATION: float = 8.0

## Ring buffer of pre-instantiated directional hit spray emitters.
var _hit_pool: Array[GPUParticles3D] = []

## Ring buffer of pre-instantiated fatal burst root nodes.
var _death_pool: Array[Node3D] = []

## Parallel array caching heavy droplet emitters inside [_death_pool].
var _death_spray_emitters: Array[GPUParticles3D] = []

## Parallel array caching F.E.A.R./MMod aerosol mist emitters inside [_death_pool].
var _death_mist_emitters: Array[GPUParticles3D] = []

## Ring buffer of pre-instantiated surface [Decal] nodes.
var _decal_pool: Array[Decal] = []

## Parallel array tracking active fade [Tween] instances per decal slot.
var _decal_tweens: Array[Tween] = []

## Startup-baked procedural blood splatter albedo textures.
var _splatter_albedos: Array[ImageTexture] = []

## Startup-baked procedural blood splatter normal maps.
var _splatter_normals: Array[ImageTexture] = []

## Shared wet ORM texture providing low roughness specular sheen on decals.
var _wet_orm_tex: ImageTexture = null

## Single reusable physics raycast query parameter object.
var _ray_query: PhysicsRayQueryParameters3D = null

## Current ring buffer index for [_hit_pool].
var _hit_idx: int = 0

## Current ring buffer index for [_death_pool].
var _death_idx: int = 0

## Current ring buffer index for [_decal_pool].
var _decal_idx: int = 0


## Bakes procedural textures, pre-allocates pools, and connects [Events] signal.
func _ready() -> void:
	print("BloodManager: Pre-warming procedural blood textures and VFX pools.")
	set_process(false)
	set_physics_process(false)

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = ENV_COLLISION_MASK
	_ray_query.collide_with_bodies = true
	_ray_query.collide_with_areas = false

	_bake_procedural_decal_textures()
	_build_pools()

	assert(_hit_pool.size() == HIT_POOL_SIZE, "BloodManager: Hit pool size mismatch.")
	assert(_death_pool.size() == DEATH_POOL_SIZE, "BloodManager: Death pool size mismatch.")
	assert(_decal_pool.size() == DECAL_POOL_SIZE, "BloodManager: Decal pool size mismatch.")

	Events.blood_fx_requested.connect(_on_blood_fx_requested)


## Disconnects global [Events] signal when exiting the scene tree.
func _exit_tree() -> void:
	if Events.blood_fx_requested.is_connected(_on_blood_fx_requested):
		Events.blood_fx_requested.disconnect(_on_blood_fx_requested)


## Handles incoming blood VFX requests with exterior entry/exit sprays and decals.
func _on_blood_fx_requested(hit_position: Vector3, shot_direction: Vector3, is_fatal: bool) -> void:
	var dir: Vector3 = (
		shot_direction.normalized() if not shot_direction.is_zero_approx() else Vector3.FORWARD
	)

	# Keep entry/exit offset horizontal so steep vertical angles still exit chest/back.
	var flat_dir: Vector3 = Vector3(dir.x, 0.0, dir.z)
	var offset_dir: Vector3 = flat_dir.normalized() if flat_dir.length_squared() > 0.001 else dir

	var entry_pos: Vector3 = hit_position - offset_dir * CAPSULE_SURFACE_OFFSET
	var exit_pos: Vector3 = hit_position + offset_dir * CAPSULE_SURFACE_OFFSET

	var entry_spray_dir: Vector3 = (-dir + Vector3.UP * 0.18).normalized()
	var exit_spray_dir: Vector3 = (dir + Vector3.UP * 0.12).normalized()

	if is_fatal:
		print("BloodManager: Spawning 2x fatal mist + bidirectional gore at ", hit_position)
		_trigger_death_burst(hit_position, dir)
		_trigger_hit_spray(entry_pos, entry_spray_dir)
		_trigger_hit_spray(exit_pos, exit_spray_dir)

		var fatal_exit_ray: Vector3 = (dir * 0.7 + Vector3.DOWN * 0.3).normalized() * 5.0
		var fatal_entry_ray: Vector3 = (-dir * 0.6 + Vector3.DOWN * 0.4).normalized() * 4.5
		_cast_and_place_decal(exit_pos, fatal_exit_ray, 1.85)
		_cast_and_place_decal(entry_pos, fatal_entry_ray, 1.65)
		_cast_and_place_decal(hit_position, Vector3.DOWN * 4.0, 2.1)
	else:
		print("BloodManager: Spawning dual entry/exit hit sprays at ", hit_position)
		# Chest entry spray flying towards the shooter + back exit spray flying out the rear.
		_trigger_hit_spray(entry_pos, entry_spray_dir)
		_trigger_hit_spray(exit_pos, exit_spray_dir)

		var exit_ray: Vector3 = (dir * 0.65 + Vector3.DOWN * 0.35).normalized() * 4.5
		var entry_ray: Vector3 = (-dir * 0.55 + Vector3.DOWN * 0.45).normalized() * 4.0
		_cast_and_place_decal(exit_pos, exit_ray, 1.35)
		_cast_and_place_decal(entry_pos, entry_ray, 1.15)


## Generates procedural radial splatter albedo, normal, and wet ORM textures in RAM.
func _bake_procedural_decal_textures() -> void:
	var orm_img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	orm_img.fill(Color(1.0, 0.14, 0.0, 1.0))
	_wet_orm_tex = ImageTexture.create_from_image(orm_img)

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 3
	noise.frequency = 0.065

	var center: Vector2 = Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_radius: float = float(TEX_SIZE) * 0.46

	for var_idx: int in range(SPLATTER_VARIATIONS):
		noise.seed = 104729 + var_idx * 7919
		var albedo_img: Image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
		var bump_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)

		for y: int in range(TEX_SIZE):
			for x: int in range(TEX_SIZE):
				var offset: Vector2 = Vector2(float(x), float(y)) - center
				var dist: float = offset.length() / max_radius
				var angle: float = atan2(offset.y, offset.x)

				# Polar noise creates radial streaks and satellite droplets.
				var streak_n: float = noise.get_noise_2d(
					cos(angle) * 28.0 + float(var_idx * 19), sin(angle) * 28.0 + dist * 16.0
				)
				var detail_n: float = noise.get_noise_2d(float(x) * 1.4, float(y) * 1.4)
				var threshold: float = 0.52 + streak_n * 0.34 + detail_n * 0.16
				var mask: float = clampf((threshold - dist) * 6.5, 0.0, 1.0)

				# Secondary outer satellite droplets near impact perimeter.
				if mask <= 0.01 and dist < 0.92 and detail_n > 0.46 and streak_n > 0.15:
					mask = clampf((detail_n - 0.46) * 4.0, 0.0, 0.95)

				var thickness: float = clampf(mask * (1.1 - dist * 0.45), 0.0, 1.0)
				var red_tone: float = lerpf(0.42, 0.14, thickness)
				albedo_img.set_pixel(x, y, Color(red_tone, 0.008, 0.012, mask))
				bump_img.set_pixel(x, y, Color(thickness, thickness, thickness, 1.0))

		albedo_img.generate_mipmaps()
		bump_img.bump_map_to_normal_map(3.2)
		bump_img.generate_mipmaps()

		_splatter_albedos.append(ImageTexture.create_from_image(albedo_img))
		_splatter_normals.append(ImageTexture.create_from_image(bump_img))


## Instantiates and pre-warms all particle emitters and decal nodes at startup.
func _build_pools() -> void:
	var spray_mat: ShaderMaterial = ShaderMaterial.new()
	spray_mat.shader = SPRAY_SHADER

	var mist_mat: ShaderMaterial = ShaderMaterial.new()
	mist_mat.shader = MIST_SHADER

	var hit_quad: QuadMesh = QuadMesh.new()
	hit_quad.size = Vector2(0.18, 0.42)
	hit_quad.material = spray_mat

	var death_spray_quad: QuadMesh = QuadMesh.new()
	death_spray_quad.size = Vector2(0.24, 0.52)
	death_spray_quad.material = spray_mat

	var mist_quad: QuadMesh = QuadMesh.new()
	mist_quad.size = Vector2(1.9, 1.9)
	mist_quad.material = mist_mat

	var hit_proc: ParticleProcessMaterial = _create_spray_process_material(
		30.0, 5.0, 10.5, 13.5, 0.22
	)
	var death_spray_proc: ParticleProcessMaterial = _create_spray_process_material(
		180.0, 4.5, 9.5, 12.0, 0.55
	)
	var mist_proc: ParticleProcessMaterial = _create_mist_process_material()

	for i: int in range(HIT_POOL_SIZE):
		var emitter: GPUParticles3D = _create_gpu_emitter(16, 0.42, 0.95, hit_proc, hit_quad)
		add_child(emitter)
		_hit_pool.append(emitter)

	for i: int in range(DEATH_POOL_SIZE):
		var cluster: Node3D = Node3D.new()
		var spray_emitter: GPUParticles3D = _create_gpu_emitter(
			28, 0.55, 0.96, death_spray_proc, death_spray_quad
		)
		var mist_emitter: GPUParticles3D = _create_gpu_emitter(18, 0.95, 0.92, mist_proc, mist_quad)
		cluster.add_child(spray_emitter)
		cluster.add_child(mist_emitter)
		add_child(cluster)
		_death_pool.append(cluster)
		_death_spray_emitters.append(spray_emitter)
		_death_mist_emitters.append(mist_emitter)

	for i: int in range(DECAL_POOL_SIZE):
		var decal: Decal = Decal.new()
		var tex_idx: int = i % SPLATTER_VARIATIONS
		decal.texture_albedo = _splatter_albedos[tex_idx]
		decal.texture_normal = _splatter_normals[tex_idx]
		decal.texture_orm = _wet_orm_tex
		decal.cull_mask = ENV_RENDER_LAYER
		decal.upper_fade = 0.2
		decal.lower_fade = 0.2
		decal.normal_fade = 0.35
		decal.visible = false
		add_child(decal)
		_decal_pool.append(decal)
		_decal_tweens.append(null)


## Creates a configured [ParticleProcessMaterial] for arterial droplet sprays.
func _create_spray_process_material(
	spread_deg: float, vel_min: float, vel_max: float, grav_y: float, sphere_radius: float
) -> ParticleProcessMaterial:
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.particle_flag_align_y = true
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = sphere_radius
	proc.direction = Vector3(0.0, 0.15, -1.0)
	proc.spread = spread_deg
	proc.initial_velocity_min = vel_min
	proc.initial_velocity_max = vel_max
	proc.gravity = Vector3(0.0, -grav_y, 0.0)
	proc.damping_min = 2.0
	proc.damping_max = 4.5
	proc.scale_min = 0.95
	proc.scale_max = 1.85
	proc.hue_variation_min = -0.02
	proc.hue_variation_max = 0.02
	return proc


## Creates a 2x volumetric [ParticleProcessMaterial] for F.E.A.R./MMod aerosol mist.
func _create_mist_process_material() -> ParticleProcessMaterial:
	var proc: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.55
	proc.direction = Vector3(0.0, 0.35, -1.0)
	proc.spread = 180.0
	proc.initial_velocity_min = 2.0
	proc.initial_velocity_max = 5.5
	proc.gravity = Vector3(0.0, -0.5, 0.0)
	proc.damping_min = 3.2
	proc.damping_max = 5.8
	proc.scale_min = 1.15
	proc.scale_max = 1.85
	return proc


## Creates a one-shot [GPUParticles3D] node with fixed bounding box and draw pass.
func _create_gpu_emitter(
	count: int, life: float, explosive: float, proc_mat: ParticleProcessMaterial, quad: QuadMesh
) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = life
	particles.explosiveness = explosive
	particles.fixed_fps = 60
	particles.visibility_aabb = AABB(Vector3(-6.0, -6.0, -6.0), Vector3(12.0, 12.0, 12.0))
	particles.process_material = proc_mat
	particles.draw_pass_1 = quad
	return particles


## Recycles the oldest hit spray emitter and fires it along [param shot_dir].
func _trigger_hit_spray(hit_pos: Vector3, shot_dir: Vector3) -> void:
	var emitter: GPUParticles3D = _hit_pool[_hit_idx]
	_hit_idx = (_hit_idx + 1) % HIT_POOL_SIZE

	emitter.global_transform = Transform3D(_build_look_basis(shot_dir), hit_pos)
	emitter.restart()
	emitter.emitting = true


## Recycles the oldest death cluster and triggers both droplet spray and 2x mist.
func _trigger_death_burst(death_pos: Vector3, shot_dir: Vector3) -> void:
	var cluster: Node3D = _death_pool[_death_idx]
	var spray: GPUParticles3D = _death_spray_emitters[_death_idx]
	var mist: GPUParticles3D = _death_mist_emitters[_death_idx]
	_death_idx = (_death_idx + 1) % DEATH_POOL_SIZE

	cluster.global_transform = Transform3D(_build_look_basis(shot_dir), death_pos)
	spray.restart()
	spray.emitting = true
	mist.restart()
	mist.emitting = true


## Casts a ray using the pre-allocated query and aligns a pooled [Decal] on hit.
func _cast_and_place_decal(origin: Vector3, ray_vec: Vector3, base_size: float) -> void:
	var world: World3D = get_world_3d()
	if not is_instance_valid(world):
		return
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if not is_instance_valid(space_state):
		return

	_ray_query.from = origin
	_ray_query.to = origin + ray_vec

	var hit: Dictionary = space_state.intersect_ray(_ray_query)
	if hit.is_empty():
		return

	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	_place_decal(hit_pos, hit_normal, base_size)


## Positions, twists, and fades the next pooled [Decal] on the hit surface.
func _place_decal(surface_pos: Vector3, surface_normal: Vector3, base_size: float) -> void:
	var slot: int = _decal_idx
	_decal_idx = (_decal_idx + 1) % DECAL_POOL_SIZE

	var existing_tween: Tween = _decal_tweens[slot]
	if is_instance_valid(existing_tween):
		existing_tween.kill()

	var decal: Decal = _decal_pool[slot]
	var normal: Vector3 = (
		surface_normal.normalized() if not surface_normal.is_zero_approx() else Vector3.UP
	)

	# Godot 4 Decals project along -Y; align local +Y with surface normal.
	var ref_vec: Vector3 = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var tangent: Vector3 = ref_vec.cross(normal).normalized()
	var bitangent: Vector3 = normal.cross(tangent).normalized()
	var aligned_basis: Basis = Basis(tangent, normal, bitangent).rotated(normal, randf() * TAU)

	var scale_jitter: float = base_size * randf_range(0.85, 1.18)
	decal.size = Vector3(scale_jitter, 0.55, scale_jitter)
	decal.global_transform = Transform3D(aligned_basis, surface_pos)
	decal.modulate = Color(1.0, 1.0, 1.0, 1.0)
	decal.visible = true

	var fade_tween: Tween = create_tween()
	_decal_tweens[slot] = fade_tween
	fade_tween.tween_property(decal, PROP_MODULATE_ALPHA, 0.0, DECAL_FADE_DURATION)
	fade_tween.tween_callback(decal.hide)


## Builds an orthonormal [Basis] where -Z points along [param forward_dir].
func _build_look_basis(forward_dir: Vector3) -> Basis:
	var fwd: Vector3 = (
		forward_dir.normalized() if not forward_dir.is_zero_approx() else Vector3.FORWARD
	)
	var up_ref: Vector3 = Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	return Basis.looking_at(fwd, up_ref)
