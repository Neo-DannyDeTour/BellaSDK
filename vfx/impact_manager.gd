## Pooled bullet hole [Decal] ring buffer placing holes on static environment surfaces.
## Listens to [signal Events.bullet_impact_requested]; clears on [signal SceneTree.scene_changed].
#class_name ImpactManager
extends Node3D

## Number of pooled bullet hole [Decal] nodes recycled oldest-first.
const POOL_SIZE: int = 64

## Number of procedural bullet hole texture variations baked at startup.
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

## Startup-baked albedo textures; swap for preloaded PNGs without other changes.
var _albedos: Array[Texture2D] = []

## Startup-baked normal maps matching [member _albedos] indices.
var _normals: Array[Texture2D] = []

## Shared matte ORM texture giving holes a rough, non-metallic finish.
var _orm: Texture2D = null

## Next ring buffer slot index in [member _pool].
var _idx: int = 0


## Bakes textures, pre-allocates pool, connects impact and scene change signals.
func _ready() -> void:
	print("ImpactManager: Pre-warming ", POOL_SIZE, " bullet hole decals.")
	set_process(false)
	set_physics_process(false)

	_bake_textures()
	_build_pool()

	assert(_pool.size() == POOL_SIZE, "ImpactManager: Pool size mismatch.")
	assert(_albedos.size() == VARIANT_COUNT, "ImpactManager: Albedo variant count mismatch.")
	assert(_normals.size() == VARIANT_COUNT, "ImpactManager: Normal variant count mismatch.")

	Events.bullet_impact_requested.connect(_on_bullet_impact_requested)
	get_tree().scene_changed.connect(_on_scene_changed)


## Disconnects global [Events] and [SceneTree] signals when exiting the tree.
func _exit_tree() -> void:
	if Events.bullet_impact_requested.is_connected(_on_bullet_impact_requested):
		Events.bullet_impact_requested.disconnect(_on_bullet_impact_requested)
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree) and tree.scene_changed.is_connected(_on_scene_changed):
		tree.scene_changed.disconnect(_on_scene_changed)


## Filters [param collider] to static environment, then places a hole at [param hit_pos].
func _on_bullet_impact_requested(hit_pos: Vector3, hit_normal: Vector3, collider: Object) -> void:
	if not _is_static_environment(collider):
		return
	_place(hit_pos, hit_normal)


## Hides every pooled hole so previous level holes never float in the new scene.
func _on_scene_changed() -> void:
	print("ImpactManager: Scene changed, clearing bullet holes.")
	for decal: Decal in _pool:
		decal.visible = false
	_idx = 0


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


## Aligns the next pooled [Decal] to [param surface_normal] at [param surface_pos].
func _place(surface_pos: Vector3, surface_normal: Vector3) -> void:
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
	decal.texture_albedo = _albedos[variant]
	decal.texture_normal = _normals[variant]
	decal.visible = true


## Instantiates all hidden [Decal] nodes with fixed cull, fade, and ORM settings.
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


## Generates procedural hole albedo (core, soot ring, cracks), normals, and shared ORM.
func _bake_textures() -> void:
	var orm_img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	orm_img.fill(Color(1.0, 0.9, 0.0, 1.0))
	_orm = ImageTexture.create_from_image(orm_img)

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_octaves = 2
	noise.frequency = 0.08

	var center: Vector2 = Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var max_radius: float = float(TEX_SIZE) * 0.5

	for var_idx: int in range(VARIANT_COUNT):
		noise.seed = 7349 + var_idx * 104729
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

				# Depressed core, slightly raised rim for normal map relief.
				var rim: float = clampf(1.0 - absf(dist - core_radius) * 10.0, 0.0, 1.0)
				var height: float = clampf(0.5 - core * 0.5 + rim * 0.25 - crack * 0.15, 0.0, 1.0)
				bump_img.set_pixel(x, y, Color(height, height, height, 1.0))

		albedo_img.generate_mipmaps()
		bump_img.bump_map_to_normal_map(4.0)
		bump_img.generate_mipmaps()

		_albedos.append(ImageTexture.create_from_image(albedo_img))
		_normals.append(ImageTexture.create_from_image(bump_img))
