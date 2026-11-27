## Pooled bullet hole [Decal] ring buffer and 3-pass [ImpactVfxBurst] impact VFX manager.
## Listens to [signal Events.bullet_impact_requested]; clears on [signal SceneTree.scene_changed].
#class_name ImpactManager
extends Node3D

## Number of pooled bullet hole [Decal] nodes recycled oldest-first.
const POOL_SIZE: int = 64

## Number of pooled [ImpactVfxBurst] nodes recycled oldest-first.
const VFX_POOL_SIZE: int = 16

## Maximum [ImpactVfxBurst] triggers permitted within a single process frame (shotgun throttle).
const MAX_VFX_BURSTS_PER_FRAME: int = 3

## Physics collision mask eligible for bullet impact particle bursts (environment + interactive).
const VFX_COLLISION_MASK: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_INTERACTIVE

## Number of procedural bullet hole texture variations baked per surface at startup.
const VARIANT_COUNT: int = 4

## Resolution in pixels for each procedural bullet hole texture.
const TEX_SIZE: int = 64

## Decal projection depth in meters; shallow to avoid bleeding through thin walls.
const PROJECTION_DEPTH: float = 0.1

## Fade applied where the surface normal diverges from projection axis (corners).
const NORMAL_FADE: float = 0.5

## Minimum randomized bullet hole diameter in meters.
const HOLE_SIZE_MIN: float = 0.08

## Maximum randomized bullet hole diameter in meters.
const HOLE_SIZE_MAX: float = 0.12

## Camera distance in meters where GPU distance fade begins.
const FADE_BEGIN: float = 25.0

## Distance in meters over which decals fade to invisible past [constant FADE_BEGIN].
const FADE_LENGTH: float = 5.0

## Ring buffer of pre-instantiated bullet hole [Decal] nodes.
var _pool: Array[Decal] = []

## Startup-baked concrete albedo textures; swap for preloaded PNGs without other changes.
var _albedos: Array[Texture2D] = []

## Startup-baked concrete normal maps matching [member _albedos] indices.
var _normals: Array[Texture2D] = []

## Startup-baked wood splintered gouge albedo textures.
var _wood_albedos: Array[Texture2D] = []

## Startup-baked wood normal maps matching [member _wood_albedos] indices.
var _wood_normals: Array[Texture2D] = []

## Startup-baked metal dent albedo textures.
var _metal_albedos: Array[Texture2D] = []

## Startup-baked metal normal maps matching [member _metal_albedos] indices.
var _metal_normals: Array[Texture2D] = []

## Startup-baked metal ORM textures giving a shiny metallic rim around a dark dent.
var _metal_orms: Array[Texture2D] = []

## Startup-baked dirt divot albedo textures.
var _dirt_albedos: Array[Texture2D] = []

## Startup-baked dirt normal maps matching [member _dirt_albedos] indices.
var _dirt_normals: Array[Texture2D] = []

## Startup-baked glass star-fracture albedo textures.
var _glass_albedos: Array[Texture2D] = []

## Startup-baked glass normal maps matching [member _glass_albedos] indices.
var _glass_normals: Array[Texture2D] = []

## Shared matte ORM texture giving non-metal holes a rough, non-metallic finish.
var _orm: Texture2D = null

## Next ring buffer slot index in [member _pool].
var _idx: int = 0

## Dedicated child container holding pooled [ImpactVfxBurst] nodes after the 64 decals.
var _vfx_container: Node3D = null

## Ring buffer of pre-instantiated [ImpactVfxBurst] nodes inside [member _vfx_container].
var _vfx_pool: Array[ImpactVfxBurst] = []

## Next ring buffer slot index in [member _vfx_pool].
var _vfx_idx: int = 0

## Process frame counter of the last triggered [ImpactVfxBurst] for per-frame throttling.
var _last_vfx_frame: int = -1

## Number of [ImpactVfxBurst] triggers emitted during [member _last_vfx_frame].
var _frame_burst_count: int = 0


## Bakes surface textures, pre-allocates decal and VFX pools, and connects global signals.
func _ready() -> void:
	print("ImpactManager: Pre-warming ", POOL_SIZE, " decals and ", VFX_POOL_SIZE, " VFX bursts.")
	set_process(false)
	set_physics_process(false)

	_bake_textures()
	_build_pool()

	assert(_pool.size() == POOL_SIZE, "ImpactManager: Pool size mismatch.")
	assert(_albedos.size() == VARIANT_COUNT, "ImpactManager: Albedo variant count mismatch.")
	assert(_normals.size() == VARIANT_COUNT, "ImpactManager: Normal variant count mismatch.")
	assert(_wood_albedos.size() == VARIANT_COUNT, "ImpactManager: Wood albedo mismatch.")
	assert(_metal_albedos.size() == VARIANT_COUNT, "ImpactManager: Metal albedo mismatch.")
	assert(_metal_orms.size() == VARIANT_COUNT, "ImpactManager: Metal ORM mismatch.")
	assert(_vfx_pool.size() == VFX_POOL_SIZE, "ImpactManager: VFX pool size mismatch.")

	Events.bullet_impact_requested.connect(_on_bullet_impact_requested)
	get_tree().scene_changed.connect(_on_scene_changed)


## Disconnects global [Events] and [SceneTree] signals when exiting the tree.
func _exit_tree() -> void:
	if Events.bullet_impact_requested.is_connected(_on_bullet_impact_requested):
		Events.bullet_impact_requested.disconnect(_on_bullet_impact_requested)
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree) and tree.scene_changed.is_connected(_on_scene_changed):
		tree.scene_changed.disconnect(_on_scene_changed)


## Classifies [param collider], triggers throttled VFX burst, and places decals on static env.
func _on_bullet_impact_requested(hit_pos: Vector3, hit_normal: Vector3, collider: Object) -> void:
	if not _is_vfx_collider(collider):
		return

	var surface: SurfaceClassifier.SurfaceType = SurfaceClassifier.classify(collider)
	var current_frame: int = Engine.get_process_frames()
	if current_frame != _last_vfx_frame:
		_last_vfx_frame = current_frame
		_frame_burst_count = 0

	if _frame_burst_count < MAX_VFX_BURSTS_PER_FRAME:
		_trigger_vfx_burst(hit_pos, hit_normal, surface)
		_frame_burst_count += 1

	if _is_static_environment(collider):
		_place(hit_pos, hit_normal, surface)


## Hides every pooled decal and resets every pooled [ImpactVfxBurst] on scene change.
func _on_scene_changed() -> void:
	print("ImpactManager: Scene changed, clearing bullet holes and impact bursts.")
	for decal: Decal in _pool:
		decal.visible = false
	_idx = 0
	for burst: ImpactVfxBurst in _vfx_pool:
		burst.reset()
	_vfx_idx = 0
	_last_vfx_frame = -1
	_frame_burst_count = 0


## Returns true when [param collider] sits on environment or interactive physics layers.
func _is_vfx_collider(collider: Object) -> bool:
	if not is_instance_valid(collider):
		return false
	var layer: int = 0
	if collider is CollisionObject3D:
		layer = (collider as CollisionObject3D).collision_layer
	elif collider is CSGShape3D:
		layer = (collider as CSGShape3D).collision_layer
	return (layer & VFX_COLLISION_MASK) != 0


## Returns true when [param collider] sits on environment layer and cannot move.
func _is_static_environment(collider: Object) -> bool:
	if not is_instance_valid(collider):
		return false
	# AnimatableBody3D extends StaticBody3D, so reject movers before reading layers.
	if collider is RigidBody3D or collider is CharacterBody3D or collider is AnimatableBody3D:
		return false

	var layer: int = 0
	if collider is CollisionObject3D:
		layer = (collider as CollisionObject3D).collision_layer
	elif collider is CSGShape3D:
		layer = (collider as CSGShape3D).collision_layer
	return (layer & CollisionLayers.MASK_ENVIRONMENT) != 0


## Triggers the next pooled [ImpactVfxBurst] at [param hit_pos] along [param hit_normal].
func _trigger_vfx_burst(
	hit_pos: Vector3, hit_normal: Vector3, surface: SurfaceClassifier.SurfaceType
) -> void:
	var burst: ImpactVfxBurst = _vfx_pool[_vfx_idx]
	_vfx_idx = (_vfx_idx + 1) % VFX_POOL_SIZE
	burst.play(hit_pos, hit_normal, surface)


## Aligns the next pooled [Decal] to [param surface_normal] with [param surface] textures.
func _place(
	surface_pos: Vector3,
	surface_normal: Vector3,
	surface: SurfaceClassifier.SurfaceType = SurfaceClassifier.SurfaceType.CONCRETE
) -> void:
	var decal: Decal = _pool[_idx]
	var variant: int = randi() % VARIANT_COUNT
	_idx = (_idx + 1) % POOL_SIZE

	var normal: Vector3 = (
		surface_normal.normalized() if not surface_normal.is_zero_approx() else Vector3.UP
	)

	# Godot 4 Decals project along -Y; align local +Y with surface normal.
	var ref_vec: Vector3 = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var tangent: Vector3 = ref_vec.cross(normal).normalized()
	var bitangent: Vector3 = normal.cross(tangent).normalized()
	var aligned_basis: Basis = Basis(tangent, normal, bitangent).rotated(normal, randf() * TAU)

	var diameter: float = randf_range(HOLE_SIZE_MIN, HOLE_SIZE_MAX)
	decal.size = Vector3(diameter, PROJECTION_DEPTH, diameter)
	decal.global_transform = Transform3D(aligned_basis, surface_pos)
	_apply_decal_textures(decal, surface, variant)
	decal.visible = true


## Assigns surface-matched albedo, normal, and ORM textures for [param variant] onto [param decal].
func _apply_decal_textures(
	decal: Decal, surface: SurfaceClassifier.SurfaceType, variant: int
) -> void:
	match surface:
		SurfaceClassifier.SurfaceType.WOOD:
			decal.texture_albedo = _wood_albedos[variant]
			decal.texture_normal = _wood_normals[variant]
			decal.texture_orm = _orm
		SurfaceClassifier.SurfaceType.METAL:
			decal.texture_albedo = _metal_albedos[variant]
			decal.texture_normal = _metal_normals[variant]
			decal.texture_orm = _metal_orms[variant]
		SurfaceClassifier.SurfaceType.DIRT:
			decal.texture_albedo = _dirt_albedos[variant]
			decal.texture_normal = _dirt_normals[variant]
			decal.texture_orm = _orm
		SurfaceClassifier.SurfaceType.GLASS:
			decal.texture_albedo = _glass_albedos[variant]
			decal.texture_normal = _glass_normals[variant]
			decal.texture_orm = _orm
		_:
			decal.texture_albedo = _albedos[variant]
			decal.texture_normal = _normals[variant]
			decal.texture_orm = _orm


## Instantiates all 64 [Decal] nodes first as direct children, then [member _vfx_container].
func _build_pool() -> void:
	for i: int in range(POOL_SIZE):
		var decal: Decal = Decal.new()
		decal.texture_albedo = _albedos[i % VARIANT_COUNT]
		decal.texture_normal = _normals[i % VARIANT_COUNT]
		decal.texture_orm = _orm
		decal.cull_mask = CollisionLayers.RENDER_MASK_ENVIRONMENT
		decal.normal_fade = NORMAL_FADE
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = FADE_BEGIN
		decal.distance_fade_length = FADE_LENGTH
		decal.visible = false
		add_child(decal)
		_pool.append(decal)

	_vfx_container = Node3D.new()
	_vfx_container.name = "ImpactVfxContainer"
	add_child(_vfx_container)

	for j: int in range(VFX_POOL_SIZE):
		var burst: ImpactVfxBurst = ImpactVfxBurst.new()
		burst.name = "ImpactVfxBurst_%d" % j
		_vfx_container.add_child(burst)
		_vfx_pool.append(burst)


## Generates procedural hole albedo, normal, and ORM textures for all surface types.
func _bake_textures() -> void:
	var orm_img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	orm_img.fill(Color(1.0, 0.9, 0.0, 1.0))
	_orm = ImageTexture.create_from_image(orm_img)

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 2
	noise.frequency = 0.08

	for var_idx: int in range(VARIANT_COUNT):
		_bake_concrete_variant(noise, var_idx)
		_bake_wood_variant(noise, var_idx)
		_bake_metal_variant(noise, var_idx)
		_bake_dirt_variant(noise, var_idx)
		_bake_glass_variant(noise, var_idx)


## Bakes one concrete bullet hole variation (crater, soot ring, radial cracks).
func _bake_concrete_variant(noise: FastNoiseLite, var_idx: int) -> void:
	noise.seed = 7349 + var_idx * 104729
	var center: Vector2 = Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_radius: float = float(TEX_SIZE) * 0.5
	var albedo_img: Image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
	var bump_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)

	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var offset: Vector2 = Vector2(float(x), float(y)) - center
			var dist: float = offset.length() / max_radius
			var angle: float = atan2(offset.y, offset.x)

			var edge_n: float = noise.get_noise_2d(cos(angle) * 12.0, sin(angle) * 12.0)
			var core_radius: float = 0.2 + edge_n * 0.05
			var core: float = clampf((core_radius - dist) * 30.0, 0.0, 1.0)
			var soot: float = clampf(1.0 - (dist - core_radius) / 0.35, 0.0, 1.0) * 0.7

			# Polar noise ridges form thin radial cracks fading toward the rim.
			var crack_n: float = noise.get_noise_2d(
				cos(angle) * 40.0 + float(var_idx * 31), sin(angle) * 40.0
			)
			var crack: float = clampf((absf(crack_n) - 0.55) * 8.0, 0.0, 1.0)
			crack *= clampf(1.0 - dist, 0.0, 1.0)

			var alpha: float = clampf(maxf(maxf(core, soot), crack), 0.0, 1.0)
			var tone: float = lerpf(0.12, 0.02, core)
			albedo_img.set_pixel(x, y, Color(tone, tone, tone, alpha))

			var rim: float = clampf(1.0 - absf(dist - core_radius) * 10.0, 0.0, 1.0)
			var height: float = clampf(0.5 - core * 0.5 + rim * 0.25 - crack * 0.15, 0.0, 1.0)
			bump_img.set_pixel(x, y, Color(height, height, height, 1.0))

	_finalize_variant(albedo_img, bump_img, _albedos, _normals, 4.0)


## Bakes one wood bullet hole variation (elongated dark splintered gouge).
func _bake_wood_variant(noise: FastNoiseLite, var_idx: int) -> void:
	noise.seed = 19283 + var_idx * 65537
	var center: Vector2 = Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_radius: float = float(TEX_SIZE) * 0.5
	var albedo_img: Image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
	var bump_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)

	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var offset: Vector2 = Vector2(float(x), float(y)) - center
			# Stretch vertically to mimic grain-aligned wood splinters.
			var stretched: Vector2 = Vector2(
				offset.x / (max_radius * 0.58), offset.y / (max_radius * 0.92)
			)
			var dist: float = stretched.length()
			var grain_n: float = noise.get_noise_2d(
				float(x) * 2.4 + float(var_idx * 17), float(y) * 0.35
			)
			var core_radius: float = 0.28 + grain_n * 0.08
			var core: float = clampf((core_radius - dist) * 20.0, 0.0, 1.0)

			var splinter_streak: float = clampf(
				(grain_n + 0.15) * 1.4 * (1.0 - absf(stretched.x) * 1.3), 0.0, 1.0
			)
			splinter_streak *= clampf(1.0 - dist * 0.9, 0.0, 1.0)

			var alpha: float = clampf(maxf(core, splinter_streak * 0.85), 0.0, 1.0)
			var red: float = lerpf(0.32, 0.05, core)
			var green: float = lerpf(0.20, 0.03, core)
			var blue: float = lerpf(0.10, 0.02, core)
			albedo_img.set_pixel(x, y, Color(red, green, blue, alpha))

			var rim: float = clampf(1.0 - absf(dist - core_radius) * 9.0, 0.0, 1.0)
			var height: float = clampf(
				0.5 - core * 0.45 + rim * 0.22 + splinter_streak * 0.18, 0.0, 1.0
			)
			bump_img.set_pixel(x, y, Color(height, height, height, 1.0))

	_finalize_variant(albedo_img, bump_img, _wood_albedos, _wood_normals, 3.8)


## Bakes one metal bullet impact variation (dark metallic dent + specular ORM rim).
func _bake_metal_variant(noise: FastNoiseLite, var_idx: int) -> void:
	noise.seed = 41893 + var_idx * 8191
	var center: Vector2 = Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_radius: float = float(TEX_SIZE) * 0.5
	var albedo_img: Image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
	var bump_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var orm_img: Image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)

	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var offset: Vector2 = Vector2(float(x), float(y)) - center
			var dist: float = offset.length() / max_radius
			var angle: float = atan2(offset.y, offset.x)

			var edge_n: float = noise.get_noise_2d(cos(angle) * 14.0, sin(angle) * 14.0)
			var core_radius: float = 0.23 + edge_n * 0.03
			var core: float = clampf((core_radius - dist) * 28.0, 0.0, 1.0)
			var rim: float = clampf(1.0 - absf(dist - core_radius) * 13.0, 0.0, 1.0)
			var scorch: float = clampf(1.0 - (dist - core_radius) / 0.25, 0.0, 1.0) * 0.45

			var alpha: float = clampf(maxf(maxf(core, rim * 0.9), scorch), 0.0, 1.0)
			var base_tone: float = lerpf(0.14, 0.03, core)
			var rim_tone: float = lerpf(base_tone, 0.62, rim)
			albedo_img.set_pixel(x, y, Color(rim_tone, rim_tone * 1.02, rim_tone * 1.06, alpha))

			var height: float = clampf(0.5 - core * 0.5 + rim * 0.38, 0.0, 1.0)
			bump_img.set_pixel(x, y, Color(height, height, height, 1.0))

			# ORM: R=AO, G=Roughness (low specular rim), B=Metallic.
			var ao: float = lerpf(1.0, 0.35, core)
			var rough: float = lerpf(0.62, 0.16, rim)
			var metal: float = lerpf(0.75, 0.96, maxf(rim, core))
			orm_img.set_pixel(x, y, Color(ao, rough, metal, 1.0))

	orm_img.generate_mipmaps()
	_metal_orms.append(ImageTexture.create_from_image(orm_img))
	_finalize_variant(albedo_img, bump_img, _metal_albedos, _metal_normals, 4.5)


## Bakes one dirt bullet divot variation (soft dark soil crater).
func _bake_dirt_variant(noise: FastNoiseLite, var_idx: int) -> void:
	noise.seed = 52103 + var_idx * 4999
	var center: Vector2 = Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_radius: float = float(TEX_SIZE) * 0.5
	var albedo_img: Image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
	var bump_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)

	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var offset: Vector2 = Vector2(float(x), float(y)) - center
			var dist: float = offset.length() / max_radius
			var clump_n: float = noise.get_noise_2d(
				float(x) * 1.1 + float(var_idx * 23), float(y) * 1.1
			)
			var core_radius: float = 0.28 + clump_n * 0.08
			var core: float = clampf((core_radius - dist) * 14.0, 0.0, 1.0)
			var ring: float = clampf(1.0 - (dist - core_radius) / 0.36, 0.0, 1.0) * 0.65
			var alpha: float = clampf(maxf(core, ring), 0.0, 1.0)

			var r_col: float = lerpf(0.18, 0.06, core)
			var g_col: float = lerpf(0.13, 0.04, core)
			var b_col: float = lerpf(0.08, 0.02, core)
			albedo_img.set_pixel(x, y, Color(r_col, g_col, b_col, alpha))

			var rim: float = clampf(1.0 - absf(dist - core_radius) * 8.0, 0.0, 1.0)
			var height: float = clampf(0.5 - core * 0.42 + rim * 0.2, 0.0, 1.0)
			bump_img.set_pixel(x, y, Color(height, height, height, 1.0))

	_finalize_variant(albedo_img, bump_img, _dirt_albedos, _dirt_normals, 3.0)


## Bakes one glass impact variation (tight core puncture + pale star fractures).
func _bake_glass_variant(noise: FastNoiseLite, var_idx: int) -> void:
	noise.seed = 67411 + var_idx * 3571
	var center: Vector2 = Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_radius: float = float(TEX_SIZE) * 0.5
	var albedo_img: Image = Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
	var bump_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)

	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var offset: Vector2 = Vector2(float(x), float(y)) - center
			var dist: float = offset.length() / max_radius
			var angle: float = atan2(offset.y, offset.x)

			var core: float = clampf((0.12 - dist) * 32.0, 0.0, 1.0)
			var ray_n: float = noise.get_noise_2d(
				cos(angle) * 52.0 + float(var_idx * 41), sin(angle) * 52.0
			)
			var star_crack: float = clampf((absf(ray_n) - 0.5) * 9.0, 0.0, 1.0)
			star_crack *= clampf(1.0 - dist * 1.05, 0.0, 1.0)

			var ring_crack: float = clampf(1.0 - absf(dist - 0.34) * 28.0, 0.0, 1.0) * 0.75
			var alpha: float = clampf(maxf(core, maxf(star_crack, ring_crack)), 0.0, 1.0)
			var tone: float = lerpf(0.84, 0.12, core)
			albedo_img.set_pixel(x, y, Color(tone * 0.94, tone * 0.98, tone, alpha * 0.85))

			var height: float = clampf(0.5 - core * 0.4 + star_crack * 0.3, 0.0, 1.0)
			bump_img.set_pixel(x, y, Color(height, height, height, 1.0))

	_finalize_variant(albedo_img, bump_img, _glass_albedos, _glass_normals, 3.5)


## Generates mipmaps, converts bump map to normal map, and appends textures to target arrays.
func _finalize_variant(
	albedo_img: Image,
	bump_img: Image,
	albedo_out: Array[Texture2D],
	normal_out: Array[Texture2D],
	bump_strength: float
) -> void:
	albedo_img.generate_mipmaps()
	bump_img.bump_map_to_normal_map(bump_strength)
	bump_img.generate_mipmaps()
	albedo_out.append(ImageTexture.create_from_image(albedo_img))
	normal_out.append(ImageTexture.create_from_image(bump_img))
