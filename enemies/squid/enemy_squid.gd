## Hostile ground-skittering squid enemy that leaps like a headcrab and spills floor hazards.
##
## Procedurally assembles an asymmetrical mantle, mismatched eyes, and uneven tentacles
## driven in real time by velocity-synced per-instance shader parameters.
class_name EnemySquid
extends CharacterBody3D

## AI execution states governing movement impulses, ballistic leaps, and recovery.
enum SquidState {
	IDLE,
	PATROL,
	CHASE,
	WINDUP,
	LEAP,
	RECOVER,
}

## Floor spill mode determining whether puddles block sprinting, cause slipping, or alternate.
enum SpillMode {
	NO_SPRINT,
	SLIPPERY,
	ALTERNATING,
}

## Preloaded tentacle and mantle spatial shader.
const SQUID_SHADER: Shader = preload("res://shaders/squid_tentacle.gdshader")

## Per-instance shader parameter name for accumulated wave phase.
const PARAM_WAVE_PHASE: StringName = &"wave_phase"

## Per-instance shader parameter name for normalized velocity intensity.
const PARAM_MOVE_INTENSITY: StringName = &"move_intensity"

## Per-instance shader parameter name for crouch/leap tentacle posture.
const PARAM_LEAP_PHASE: StringName = &"leap_phase"

## Per-instance shader parameter name for unique per-tentacle phase seed.
const PARAM_TENTACLE_SEED: StringName = &"tentacle_seed"

## Property identifier for deferred monitoring updates on [Area3D] hitboxes.
const PROP_MONITORING: StringName = &"monitoring"

## Number of uneven procedural tentacles generated around the mantle skirt.
const TENTACLE_COUNT: int = 8

## Number of reusable [SquidPuddle] instances pre-allocated per squid.
const PUDDLE_POOL_SIZE: int = 4

## Minimum wave phase speed in radians per second when idle.
const IDLE_WAVE_SPEED: float = 2.4

## Maximum wave phase speed in radians per second during high-speed leaps.
const FAST_WAVE_SPEED: float = 15.0

## Vertical target aim offset above player origin for headcrab leap arcs.
const HEADCRAB_TARGET_HEIGHT: float = 1.25

## Controls which floor hazard type is spilled when leaping and landing.
@export var spill_mode: SpillMode = SpillMode.ALTERNATING

## Horizontal velocity impulse applied on each ground skitter stroke.
@export var skitter_impulse: float = 7.5

## Seconds between consecutive ground skitter propulsion strokes.
@export var skitter_interval: float = 0.42

## Minimum squared distance to player required to initiate a headcrab leap.
@export var min_leap_dist_sq: float = 6.25

## Maximum squared distance to player within which a headcrab leap can trigger.
@export var max_leap_dist_sq: float = 64.0

## Squared distance threshold beyond which the squid drops target lock.
@export var deaggro_dist_sq: float = 484.0

## Forward launch speed applied when executing a ballistic headcrab jump.
@export var leap_horizontal_speed: float = 13.5

## Upward vertical velocity applied at the start of a headcrab jump.
@export var leap_vertical_speed: float = 6.8

## Health points subtracted from the player upon leap hitbox contact.
@export var leap_damage: int = 20

## Minimum cooldown in seconds between consecutive leap attacks.
@export var leap_cooldown: float = 2.2

## Duration in seconds that spilled mucus puddles persist on the floor.
@export var puddle_duration: float = 6.0

## Optional manual reference to the entity [FactionComponent].
@export var faction_component: FactionComponent = null

## Optional manual reference to the entity [HealthComponent].
@export var health_component: HealthComponent = null

## Shared [ShaderMaterial] reused across all squid instances to avoid duplication.
static var _shared_squid_material: ShaderMaterial = null

## Shared unit [CylinderMesh] scaled per tentacle to produce uneven dimensions.
static var _shared_tentacle_mesh: CylinderMesh = null

## Current active behavioral state.
var _state: SquidState = SquidState.IDLE

## Currently tracked hostile target node.
var _target: Node3D = null

## World spawn anchor used for local patrol offsets.
var _home_position: Vector3 = Vector3.ZERO

## Current local patrol destination in world coordinates.
var _patrol_target: Vector3 = Vector3.ZERO

## Countdown timer governing rhythmic skitter bursts on the floor.
var _skitter_timer: float = 0.0

## Accumulated wave phase passed to [constant PARAM_WAVE_PHASE].
var _wave_phase: float = 0.0

## Smoothed normalized movement intensity (`0.0` to `1.0`) for shader synchronization.
var _smoothed_intensity: float = 0.0

## Smoothed leap posture value (`-1.0` crouch to `1.0` mid-air cone) for shader sync.
var _leap_posture: float = 0.0

## True while the squid is visible on screen and shader uniforms should update.
var _is_visible_on_screen: bool = true

## True when the headcrab leap cooldown has expired.
var _can_leap: bool = true

## True once the current leap has dealt damage so a single jump never double-hits.
var _leap_hit_registered: bool = false

## Alternation toggle for [enum SpillMode.ALTERNATING].
var _next_puddle_slippery: bool = false

## Ring buffer index pointing to the next pooled [SquidPuddle].
var _puddle_pool_index: int = 0

## Monotonic token used to invalidate stale state [SceneTreeTimer] callbacks on death/reset.
var _state_token: int = 0

## World gravity fetched from project physics settings.
var _gravity: float = 9.8

## Active [Tween] used for windup squash-and-stretch animations.
var _active_tween: Tween = null

## Root [Node3D] holding all procedural squid meshes.
var _visual_root: Node3D = null

## Main deformed mantle [MeshInstance3D].
var _mantle_mesh: MeshInstance3D = null

## Array of uneven procedural tentacle [MeshInstance3D] nodes.
var _tentacle_meshes: Array[MeshInstance3D] = []

## Per-tentacle random phase seeds matching [member _tentacle_meshes] indices.
var _tentacle_seeds: Array[float] = []

## Pre-allocated pool of [SquidPuddle] floor hazard nodes.
var _puddle_pool: Array[SquidPuddle] = []

## Screen visibility notifier gating per-frame shader uniform updates.
var _visibility_notifier: VisibleOnScreenNotifier3D = null

## Proximity sphere waking physics processing when potential targets approach.
var _detection_area: Area3D = null

## Melee hitbox active exclusively during [enum SquidState.LEAP].
var _attack_hitbox: Area3D = null

## Line-of-sight raycast verifying unobstructed path to [member _target].
var _los_ray: RayCast3D = null

## Non-volumetric camera-facing particle burst emitted upon death.
var _ink_particles: GPUParticles3D = null

## Greenish-yellow alien ichor burst particles emitted upon taking damage.
var _ichor_particles: GPUParticles3D = null


## Initializes components, procedural ugly squid geometry, sensors, and puddle pool.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	add_to_group(&"enemy")
	add_to_group(&"damageable")

	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	collision_layer = Types.MASK_ENEMIES
	collision_mask = Types.MASK_ENVIRONMENT | Types.MASK_PLAYER | Types.MASK_ENEMIES

	var gravity_variant: Variant = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if gravity_variant is float:
		_gravity = gravity_variant
	_home_position = global_position
	_patrol_target = _home_position

	_ensure_components()
	_ensure_collision_body()
	_build_ugly_squid_visuals()
	_build_sensors()
	_build_ink_particles()
	_build_ichor_particles()
	call_deferred(&"_init_puddle_pool")

	assert(is_instance_valid(faction_component), "EnemySquid: Missing FactionComponent.")
	assert(is_instance_valid(health_component), "EnemySquid: Missing HealthComponent.")
	assert(is_instance_valid(_visual_root), "EnemySquid: Missing VisualRoot.")

	Events.enemy_spawned.emit(self)
	print("EnemySquid: Initialized at ", global_position)


## Cleans up active tweens and pooled puddles when the squid exits the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_active_tween)
	_active_tween = null

	for puddle: SquidPuddle in _puddle_pool:
		if is_instance_valid(puddle):
			puddle.queue_free()
	_puddle_pool.clear()


## Executes state-driven ground skittering, ballistic leaps, and velocity-synced shader updates.
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	match _state:
		SquidState.IDLE:
			_process_idle_state(delta)
		SquidState.PATROL:
			_process_patrol_state(delta)
		SquidState.CHASE:
			_process_chase_state(delta)
		SquidState.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		SquidState.LEAP:
			_process_leap_state()
		SquidState.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)

	move_and_slide()
	_update_tentacle_sync(delta)


## Resets squid state, position, velocity, and health for object pool reuse.
func reset_squid(new_position: Vector3) -> void:
	global_position = new_position
	_home_position = new_position
	_patrol_target = new_position
	_target = null
	_can_leap = true
	_leap_hit_registered = false
	_skitter_timer = 0.0
	velocity = Vector3.ZERO

	Utilities.safe_kill_tween(_active_tween)
	_active_tween = null

	if is_instance_valid(_visual_root):
		_visual_root.scale = Vector3.ONE
		_visual_root.visible = true

	if is_instance_valid(_attack_hitbox):
		_attack_hitbox.set_deferred(PROP_MONITORING, false)

	if is_instance_valid(_ichor_particles):
		_ichor_particles.emitting = false

	if is_instance_valid(health_component):
		health_component.reset()

	_set_state(SquidState.IDLE)
	set_physics_process(false)
	print("EnemySquid: Reset for pool reuse at ", new_position)


## Inflicts damage, bursts greenish-yellow ichor, applies flinch impulse, and awakens AI.
func take_damage(
	amount: int, hit_position: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO
) -> void:
	print("EnemySquid: take_damage() called. Amount: ", amount)
	if not is_instance_valid(health_component):
		return

	if is_instance_valid(_ichor_particles):
		var local_pos: Vector3 = (
			to_local(hit_position) if hit_position != Vector3.ZERO else Vector3(0.0, 0.55, 0.0)
		)
		_ichor_particles.position = local_pos
		if not dir.is_zero_approx():
			_ichor_particles.rotation.y = atan2(dir.x, dir.z)
		_ichor_particles.restart()
		_ichor_particles.emitting = true

	if not dir.is_zero_approx():
		velocity += dir * 2.5

	if not is_physics_processing():
		set_physics_process(true)

	if _state == SquidState.IDLE or _state == SquidState.PATROL:
		var player_node: Node = get_tree().get_first_node_in_group(&"player")
		if is_instance_valid(player_node) and player_node is Node3D:
			_target = player_node as Node3D
			_set_state(SquidState.CHASE)

	health_component.take_damage(amount)


## Resolves or creates [FactionComponent] and [HealthComponent] nodes.
func _ensure_components() -> void:
	if not is_instance_valid(faction_component):
		faction_component = FactionComponent.get_faction_component(self)
	if not is_instance_valid(faction_component):
		faction_component = FactionComponent.new()
		faction_component.name = "FactionComponent"
		faction_component.faction = Types.Faction.ENEMY
		faction_component.hostile_mask = int(Types.Faction.PLAYER)
		add_child(faction_component)

	if not is_instance_valid(health_component):
		health_component = _find_health_component(self)
	if not is_instance_valid(health_component):
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		health_component.max_health = 60
		health_component.random_health_range = Vector2i(45, 90)
		health_component.use_pooling = false
		add_child(health_component)
	elif health_component.random_health_range == Vector2i.ZERO:
		health_component.random_health_range = Vector2i(45, 90)

	health_component.use_pooling = false

	if not health_component.died.is_connected(_on_died):
		health_component.died.connect(_on_died)
	if not health_component.health_changed.is_connected(_on_health_changed):
		health_component.health_changed.connect(_on_health_changed)


## Creates a physical [CollisionShape3D] on the body root if none exists in the scene.
func _ensure_collision_body() -> void:
	for child: Node in get_children():
		if child is CollisionShape3D:
			return

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.name = "BodyCollision"
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.55
	col_shape.shape = sphere
	col_shape.position = Vector3(0.0, 0.55, 0.0)
	add_child(col_shape)


## Assembles the lumpy mantle, uneven eyes, and 8 asymmetrical tentacles.
func _build_ugly_squid_visuals() -> void:
	if not is_instance_valid(_shared_squid_material):
		_shared_squid_material = ShaderMaterial.new()
		_shared_squid_material.shader = SQUID_SHADER

	if not is_instance_valid(_shared_tentacle_mesh):
		_shared_tentacle_mesh = CylinderMesh.new()
		_shared_tentacle_mesh.height = 1.0
		_shared_tentacle_mesh.top_radius = 0.11
		_shared_tentacle_mesh.bottom_radius = 0.025
		_shared_tentacle_mesh.radial_segments = 8
		_shared_tentacle_mesh.rings = 8
		_shared_tentacle_mesh.material = _shared_squid_material

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	_visual_root.position = Vector3(0.0, 0.58, 0.0)
	add_child(_visual_root)

	_mantle_mesh = MeshInstance3D.new()
	_mantle_mesh.name = "MantleMesh"
	_mantle_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	var mantle_sphere: SphereMesh = SphereMesh.new()
	mantle_sphere.radius = 0.42
	mantle_sphere.height = 0.95
	mantle_sphere.radial_segments = 16
	mantle_sphere.rings = 12
	mantle_sphere.material = _shared_squid_material
	_mantle_mesh.mesh = mantle_sphere
	_mantle_mesh.position = Vector3(0.0, 0.18, -0.08)
	_mantle_mesh.rotation_degrees = Vector3(-28.0, 7.0, -5.0)
	_mantle_mesh.scale = Vector3(1.12, 1.35, 0.92)
	_mantle_mesh.set_instance_shader_parameter(PARAM_TENTACLE_SEED, 0.0)
	_visual_root.add_child(_mantle_mesh)

	_build_mismatched_eyes()
	_build_uneven_tentacles()


## Adds two asymmetrical bulging eyes to give the squid an ugly silhouette.
func _build_mismatched_eyes() -> void:
	var eye_mat: StandardMaterial3D = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.85, 0.78, 0.22, 1.0)
	eye_mat.roughness = 0.12

	var left_eye: MeshInstance3D = MeshInstance3D.new()
	left_eye.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	var left_sphere: SphereMesh = SphereMesh.new()
	left_sphere.radius = 0.13
	left_sphere.height = 0.26
	left_sphere.material = eye_mat
	left_eye.mesh = left_sphere
	left_eye.position = Vector3(-0.24, 0.08, -0.34)
	_visual_root.add_child(left_eye)

	var right_eye: MeshInstance3D = MeshInstance3D.new()
	right_eye.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	var right_sphere: SphereMesh = SphereMesh.new()
	right_sphere.radius = 0.075
	right_sphere.height = 0.15
	right_sphere.material = eye_mat
	right_eye.mesh = right_sphere
	right_eye.position = Vector3(0.27, -0.02, -0.32)
	_visual_root.add_child(right_eye)


## Generates 8 tentacles with uneven lengths, thicknesses, and radial angles.
func _build_uneven_tentacles() -> void:
	_tentacle_meshes.clear()
	_tentacle_seeds.clear()

	var lengths: Array[float] = [0.62, 1.35, 0.78, 1.18, 0.52, 1.42, 0.88, 1.05]
	var widths: Array[float] = [0.85, 1.35, 0.72, 1.15, 0.65, 1.40, 0.95, 1.10]

	for i: int in range(TENTACLE_COUNT):
		var ratio: float = float(i) / float(TENTACLE_COUNT)
		var angle: float = ratio * TAU + ((float(i % 3) - 1.0) * 0.14)
		var len_val: float = lengths[i % lengths.size()]
		var width_val: float = widths[i % widths.size()]
		var seed_val: float = float(i + 1) * 1.37

		var tentacle: MeshInstance3D = MeshInstance3D.new()
		tentacle.name = "Tentacle_%d" % i
		tentacle.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
		tentacle.mesh = _shared_tentacle_mesh

		var radial_dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var socket_pos: Vector3 = radial_dir * 0.28 + Vector3(0.0, -0.12, 0.0)
		var hang_dir: Vector3 = (radial_dir * 0.68 + Vector3(0.0, -0.75, 0.0)).normalized()

		var up_axis: Vector3 = -hang_dir
		var right_axis: Vector3 = up_axis.cross(Vector3.UP).normalized()
		if right_axis.length_squared() < 0.01:
			right_axis = Vector3.RIGHT
		var forward_axis: Vector3 = right_axis.cross(up_axis).normalized()

		var tent_basis: Basis = Basis(right_axis, up_axis, forward_axis)
		tentacle.basis = tent_basis.scaled(Vector3(width_val, len_val, width_val))
		tentacle.position = socket_pos - (up_axis * (0.5 * len_val))
		tentacle.set_instance_shader_parameter(PARAM_TENTACLE_SEED, seed_val)

		_visual_root.add_child(tentacle)
		_tentacle_meshes.append(tentacle)
		_tentacle_seeds.append(seed_val)


## Creates visibility notifier, detection sphere, leap hitbox, and LoS raycast.
func _build_sensors() -> void:
	_visibility_notifier = VisibleOnScreenNotifier3D.new()
	_visibility_notifier.aabb = AABB(Vector3(-1.8, -1.0, -1.8), Vector3(3.6, 2.8, 3.6))
	_visibility_notifier.screen_entered.connect(_on_screen_entered)
	_visibility_notifier.screen_exited.connect(_on_screen_exited)
	add_child(_visibility_notifier)

	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = Types.MASK_PLAYER
	_detection_area.monitorable = false
	var detect_col: CollisionShape3D = CollisionShape3D.new()
	var detect_sphere: SphereShape3D = SphereShape3D.new()
	detect_sphere.radius = 18.0
	detect_col.shape = detect_sphere
	_detection_area.add_child(detect_col)
	_detection_area.body_entered.connect(_on_detection_body_entered)
	add_child(_detection_area)

	_attack_hitbox = Area3D.new()
	_attack_hitbox.name = "AttackHitbox"
	_attack_hitbox.collision_layer = 0
	_attack_hitbox.collision_mask = Types.MASK_PLAYER
	_attack_hitbox.monitorable = false
	_attack_hitbox.monitoring = false
	var hit_col: CollisionShape3D = CollisionShape3D.new()
	var hit_sphere: SphereShape3D = SphereShape3D.new()
	hit_sphere.radius = 0.85
	hit_col.shape = hit_sphere
	hit_col.position = Vector3(0.0, 0.55, -0.25)
	_attack_hitbox.add_child(hit_col)
	_attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	add_child(_attack_hitbox)

	_los_ray = RayCast3D.new()
	_los_ray.name = "LosRay"
	_los_ray.position = Vector3(0.0, 0.65, 0.0)
	_los_ray.collision_mask = Types.MASK_ENVIRONMENT | Types.MASK_PLAYER
	_los_ray.enabled = false
	add_child(_los_ray)


## Builds a non-volumetric GPUParticles3D ink-burst effect using camera-facing quad meshes.
func _build_ink_particles() -> void:
	_ink_particles = GPUParticles3D.new()
	_ink_particles.name = "InkBurstParticles"
	_ink_particles.emitting = false
	_ink_particles.one_shot = true
	_ink_particles.explosiveness = 1.0
	_ink_particles.amount = 24
	_ink_particles.lifetime = 0.75
	_ink_particles.position = Vector3(0.0, 0.6, 0.0)

	var proc_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0.0, 1.0, 0.0)
	proc_mat.spread = 180.0
	proc_mat.initial_velocity_min = 2.5
	proc_mat.initial_velocity_max = 5.5
	proc_mat.gravity = Vector3(0.0, -1.8, 0.0)
	proc_mat.scale_min = 0.35
	proc_mat.scale_max = 1.15
	proc_mat.color = Color(0.12, 0.06, 0.18, 0.92)
	_ink_particles.process_material = proc_mat

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.15, 0.08, 0.22, 0.88)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	_ink_particles.draw_pass_1 = quad

	add_child(_ink_particles)


## Builds a greenish-yellow ichor particle burst emitted on bullet and melee impacts.
func _build_ichor_particles() -> void:
	_ichor_particles = GPUParticles3D.new()
	_ichor_particles.name = "IchorBloodParticles"
	_ichor_particles.emitting = false
	_ichor_particles.one_shot = true
	_ichor_particles.explosiveness = 0.92
	_ichor_particles.amount = 16
	_ichor_particles.lifetime = 0.45
	_ichor_particles.position = Vector3(0.0, 0.55, 0.0)

	var proc_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0.0, 0.35, 1.0)
	proc_mat.spread = 50.0
	proc_mat.initial_velocity_min = 3.0
	proc_mat.initial_velocity_max = 6.5
	proc_mat.gravity = Vector3(0.0, -9.8, 0.0)
	proc_mat.scale_min = 0.15
	proc_mat.scale_max = 0.4
	proc_mat.color = Color(0.68, 0.85, 0.14, 0.95)
	_ichor_particles.process_material = proc_mat

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.68, 0.85, 0.14, 0.95)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.roughness = 0.1
	quad.material = mat
	_ichor_particles.draw_pass_1 = quad

	add_child(_ichor_particles)


## Instantiates the ring buffer of pooled [SquidPuddle] nodes in the active scene.
func _init_puddle_pool() -> void:
	if not is_inside_tree():
		return
	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_parent()
	if not is_instance_valid(scene_root):
		return

	for i: int in range(PUDDLE_POOL_SIZE):
		var puddle: SquidPuddle = SquidPuddle.new()
		puddle.name = "SquidPuddle_%d_%d" % [get_instance_id(), i]
		puddle.duration = puddle_duration
		scene_root.add_child(puddle)
		_puddle_pool.append(puddle)


## Evaluates target lock or transitions to patrol during [enum SquidState.IDLE].
func _process_idle_state(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	if is_instance_valid(_target):
		_set_state(SquidState.CHASE)
		return

	_skitter_timer -= delta
	if _skitter_timer <= 0.0:
		_pick_next_patrol_point()
		_set_state(SquidState.PATROL)


## Skitters toward local patrol offsets while scanning for sightlines to [member _target].
func _process_patrol_state(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 9.5 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 9.5 * delta)

	if is_instance_valid(_target) and _has_line_of_sight(_target):
		_set_state(SquidState.CHASE)
		return

	var dist_sq: float = global_position.distance_squared_to(_patrol_target)
	if dist_sq < 1.44:
		_skitter_timer = 1.2
		_set_state(SquidState.IDLE)
		return

	_skitter_timer -= delta
	if _skitter_timer <= 0.0 and is_on_floor():
		_skitter_timer = skitter_interval * 1.35
		_apply_skitter_burst(_patrol_target, skitter_impulse * 0.65)


## Pursues [member _target] with synchronized ground skitter bursts and triggers headcrab leaps.
func _process_chase_state(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 11.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 11.0 * delta)

	if not is_instance_valid(_target) or not _target.is_inside_tree():
		_target = null
		_set_state(SquidState.IDLE)
		set_physics_process(false)
		return

	var dist_sq: float = global_position.distance_squared_to(_target.global_position)
	if dist_sq > deaggro_dist_sq:
		print("EnemySquid: Target exceeded deaggro distance. Returning to IDLE.")
		_target = null
		_set_state(SquidState.IDLE)
		set_physics_process(false)
		return

	var has_los: bool = _has_line_of_sight(_target)
	if has_los:
		_face_position(_target.global_position, delta * 10.0)
		if (
			is_on_floor()
			and _can_leap
			and dist_sq >= min_leap_dist_sq
			and dist_sq <= max_leap_dist_sq
		):
			_start_leap_windup()
			return

	_skitter_timer -= delta
	if _skitter_timer <= 0.0 and is_on_floor():
		_skitter_timer = skitter_interval
		if has_los:
			_apply_skitter_burst(_target.global_position, skitter_impulse)
		else:
			_pick_next_patrol_point()
			_apply_skitter_burst(_patrol_target, skitter_impulse * 0.75)


## Monitors floor touchdown at the end of a ballistic [enum SquidState.LEAP].
func _process_leap_state() -> void:
	if is_on_floor() and velocity.y <= 0.05:
		_attack_hitbox.set_deferred(PROP_MONITORING, false)
		_spill_puddle()
		_enter_recover_state()


## Applies a single horizontal skitter propulsion burst toward [param destination].
func _apply_skitter_burst(destination: Vector3, impulse_speed: float) -> void:
	var flat_dir: Vector3 = destination - global_position
	flat_dir.y = 0.0
	if flat_dir.length_squared() < 0.001:
		return
	flat_dir = flat_dir.normalized()
	_face_position(destination, 1.0)
	velocity.x = flat_dir.x * impulse_speed
	velocity.z = flat_dir.z * impulse_speed
	velocity.y = 1.65


## Begins the pre-jump crouch windup, spills a puddle, and schedules the ballistic launch.
func _start_leap_windup() -> void:
	_set_state(SquidState.WINDUP)
	_can_leap = false
	_spill_puddle()

	_active_tween = Utilities.reset_tween(self, _active_tween)
	if is_instance_valid(_active_tween):
		(
			_active_tween
			. tween_property(_visual_root, "scale", Vector3(1.32, 0.62, 1.32), 0.24)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)
		_active_tween.tween_callback(_execute_headcrab_leap)


## Launches the squid along a ballistic trajectory toward the player's upper body.
func _execute_headcrab_leap() -> void:
	if _state != SquidState.WINDUP:
		return

	_set_state(SquidState.LEAP)
	_leap_hit_registered = false
	_attack_hitbox.set_deferred(PROP_MONITORING, true)

	_active_tween = Utilities.reset_tween(self, _active_tween)
	if is_instance_valid(_active_tween):
		(
			_active_tween
			. tween_property(_visual_root, "scale", Vector3(0.76, 1.42, 0.76), 0.15)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		_active_tween.tween_property(_visual_root, "scale", Vector3.ONE, 0.25).set_trans(
			Tween.TRANS_SINE
		)

	var aim_pos: Vector3 = global_position - global_transform.basis.z * 4.0
	if is_instance_valid(_target):
		aim_pos = _target.global_position + Vector3(0.0, HEADCRAB_TARGET_HEIGHT, 0.0)

	var to_target: Vector3 = aim_pos - global_position
	var flat_vec: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var flat_dist: float = flat_vec.length()
	var flat_dir: Vector3 = -global_transform.basis.z
	if flat_dist > 0.05:
		flat_dir = flat_vec / flat_dist

	var flight_time: float = clampf(flat_dist / leap_horizontal_speed, 0.28, 0.85)
	var required_vy: float = (
		(to_target.y + 0.5 * _gravity * flight_time * flight_time) / flight_time
	)
	required_vy = clampf(required_vy, leap_vertical_speed * 0.75, leap_vertical_speed * 1.45)

	velocity = flat_dir * leap_horizontal_speed + Vector3(0.0, required_vy, 0.0)
	print("EnemySquid: Launched headcrab leap with velocity ", velocity)


## Enters post-leap recovery and schedules leap cooldown restoration.
func _enter_recover_state() -> void:
	_set_state(SquidState.RECOVER)
	_state_token += 1
	var token: int = _state_token

	_active_tween = Utilities.reset_tween(self, _active_tween)
	if is_instance_valid(_active_tween):
		(
			_active_tween
			. tween_property(_visual_root, "scale", Vector3(1.25, 0.72, 1.25), 0.12)
			. set_trans(Tween.TRANS_SINE)
		)
		_active_tween.tween_property(_visual_root, "scale", Vector3.ONE, 0.22).set_trans(
			Tween.TRANS_SINE
		)

	var recover_timer: SceneTreeTimer = get_tree().create_timer(0.55)
	recover_timer.timeout.connect(_on_recover_finished.bind(token))

	var cd_timer: SceneTreeTimer = get_tree().create_timer(leap_cooldown)
	cd_timer.timeout.connect(_on_leap_cooldown_ready.bind(token))


## Deploys the next pooled [SquidPuddle] at the squid's floor contact position.
func _spill_puddle() -> void:
	if _puddle_pool.is_empty():
		return

	var puddle: SquidPuddle = _puddle_pool[_puddle_pool_index]
	_puddle_pool_index = (_puddle_pool_index + 1) % _puddle_pool.size()
	if not is_instance_valid(puddle):
		return

	var chosen_type: SquidPuddle.PuddleType = SquidPuddle.PuddleType.NO_SPRINT
	if spill_mode == SpillMode.SLIPPERY:
		chosen_type = SquidPuddle.PuddleType.SLIPPERY
	elif spill_mode == SpillMode.ALTERNATING:
		chosen_type = (
			SquidPuddle.PuddleType.SLIPPERY
			if _next_puddle_slippery
			else SquidPuddle.PuddleType.NO_SPRINT
		)
		_next_puddle_slippery = not _next_puddle_slippery

	var floor_pos: Vector3 = global_position + Vector3(0.0, 0.04, 0.0)
	puddle.activate(floor_pos, chosen_type)


## Synchronizes tentacle shader wave speed and posture with real-time squid velocity.
func _update_tentacle_sync(delta: float) -> void:
	if not _is_visible_on_screen:
		return

	var max_speed_sq: float = leap_horizontal_speed * leap_horizontal_speed
	var speed_ratio: float = clampf(velocity.length_squared() / max_speed_sq, 0.0, 1.0)
	_smoothed_intensity = move_toward(_smoothed_intensity, speed_ratio, delta * 4.5)

	var target_posture: float = 0.0
	if _state == SquidState.WINDUP or _state == SquidState.RECOVER:
		target_posture = -1.0
	elif _state == SquidState.LEAP:
		target_posture = 1.0
	else:
		target_posture = _smoothed_intensity * 0.55

	_leap_posture = move_toward(_leap_posture, target_posture, delta * 6.0)
	_wave_phase += delta * lerpf(IDLE_WAVE_SPEED, FAST_WAVE_SPEED, _smoothed_intensity)
	if _wave_phase > TAU * 64.0:
		_wave_phase -= TAU * 64.0

	if is_instance_valid(_mantle_mesh):
		_mantle_mesh.set_instance_shader_parameter(PARAM_WAVE_PHASE, _wave_phase)
		_mantle_mesh.set_instance_shader_parameter(PARAM_MOVE_INTENSITY, _smoothed_intensity)
		_mantle_mesh.set_instance_shader_parameter(PARAM_LEAP_PHASE, _leap_posture)

	for tentacle: MeshInstance3D in _tentacle_meshes:
		tentacle.set_instance_shader_parameter(PARAM_WAVE_PHASE, _wave_phase)
		tentacle.set_instance_shader_parameter(PARAM_MOVE_INTENSITY, _smoothed_intensity)
		tentacle.set_instance_shader_parameter(PARAM_LEAP_PHASE, _leap_posture)


## Returns true if [member _los_ray] has an unobstructed line of sight to [param candidate].
func _has_line_of_sight(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or not is_instance_valid(_los_ray):
		return false

	var target_center: Vector3 = candidate.global_position + Vector3(0.0, 0.9, 0.0)
	_los_ray.target_position = _los_ray.to_local(target_center)
	_los_ray.force_raycast_update()

	if not _los_ray.is_colliding():
		return true
	var collider: Object = _los_ray.get_collider()
	return collider == candidate


## Smoothly rotates the squid around the Y axis to face [param target_pos].
func _face_position(target_pos: Vector3, weight: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	var target_yaw: float = atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(weight, 0.0, 1.0))


## Selects a new local patrol offset around [member _home_position].
func _pick_next_patrol_point() -> void:
	var angle: float = randf() * TAU
	var radius: float = randf_range(2.5, 6.0)
	_patrol_target = _home_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## Transitions to [param new_state] and logs discrete state changes.
func _set_state(new_state: SquidState) -> void:
	if _state == new_state:
		return
	_state = new_state
	print("EnemySquid: State changed to ", _state)


## Locates a [HealthComponent] on [param node] or its child hierarchy.
func _find_health_component(node: Node) -> HealthComponent:
	if not is_instance_valid(node):
		return null
	if "health_component" in node:
		var prop_val: Variant = node.get("health_component")
		if prop_val is HealthComponent:
			return prop_val as HealthComponent

	var direct: Node = node.get_node_or_null("Components/HealthComponent")
	if direct is HealthComponent:
		return direct as HealthComponent

	var child_hc: Node = NodeQuery.find_first_child_of_type(node, HealthComponent)
	if child_hc is HealthComponent:
		return child_hc as HealthComponent
	return null


## Wakes physics processing when a hostile actor enters [member _detection_area].
func _on_detection_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body) or body == self:
		return

	var other_faction: FactionComponent = FactionComponent.get_faction_component(body)
	var is_hostile: bool = false
	if is_instance_valid(other_faction) and is_instance_valid(faction_component):
		is_hostile = faction_component.is_hostile_to(other_faction)
	elif body.is_in_group(&"player"):
		is_hostile = true
	elif body is CollisionObject3D:
		var col_body: CollisionObject3D = body as CollisionObject3D
		if (col_body.collision_layer & Types.MASK_PLAYER) != 0:
			is_hostile = true

	if is_hostile:
		print("EnemySquid: Hostile target detected -> ", body.name)
		_target = body
		_set_state(SquidState.CHASE)
		set_physics_process(true)


## Applies headcrab leap contact damage and rebound impulse upon hitting the player.
func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if _state != SquidState.LEAP or _leap_hit_registered or not is_instance_valid(body):
		return
	if body == self:
		return

	var target_health: HealthComponent = _find_health_component(body)
	if is_instance_valid(target_health):
		_leap_hit_registered = true
		_attack_hitbox.set_deferred(PROP_MONITORING, false)
		print("EnemySquid: Headcrab leap hit ", body.name, " for ", leap_damage, " damage.")
		target_health.take_damage(leap_damage)
		velocity = -velocity.normalized() * 4.5 + Vector3(0.0, 3.2, 0.0)


## Returns to [enum SquidState.CHASE] once post-leap recovery completes.
func _on_recover_finished(token: int) -> void:
	if token != _state_token or not is_inside_tree():
		return
	if _state == SquidState.RECOVER:
		_set_state(SquidState.CHASE)


## Re-enables headcrab leap readiness when cooldown expires.
func _on_leap_cooldown_ready(token: int) -> void:
	if token != _state_token or not is_inside_tree():
		return
	_can_leap = true


## Reacts to damage events by waking AI if currently idle.
func _on_health_changed(current_hp: int) -> void:
	print("EnemySquid: Health changed to ", current_hp)
	if current_hp > 0 and not is_physics_processing():
		set_physics_process(true)
		_set_state(SquidState.PATROL)


## Halts AI, cleans up tweens, triggers ink burst particles, and broadcasts death.
func _on_died() -> void:
	print("EnemySquid: Died.")
	_state_token += 1
	_attack_hitbox.set_deferred(PROP_MONITORING, false)

	Utilities.safe_kill_tween(_active_tween)
	_active_tween = null

	if is_instance_valid(_ink_particles):
		var parent_node: Node = get_parent()
		if is_instance_valid(parent_node) and is_inside_tree():
			Utilities.reparent_keep_transform(_ink_particles, parent_node)
		_ink_particles.restart()
		_ink_particles.emitting = true
		var timer: SceneTreeTimer = get_tree().create_timer(_ink_particles.lifetime + 0.1)
		timer.timeout.connect(_ink_particles.queue_free)

	if is_instance_valid(_ichor_particles):
		var parent_node: Node = get_parent()
		if is_instance_valid(parent_node) and is_inside_tree():
			Utilities.reparent_keep_transform(_ichor_particles, parent_node)
		_ichor_particles.restart()
		_ichor_particles.emitting = true
		var ichor_timer: SceneTreeTimer = get_tree().create_timer(_ichor_particles.lifetime + 0.1)
		ichor_timer.timeout.connect(_ichor_particles.queue_free)

	_spill_puddle()
	_set_state(SquidState.IDLE)
	set_physics_process(false)
	Events.enemy_killed.emit(self, null)


## Enables per-frame shader uniform updates when entering camera frustum.
func _on_screen_entered() -> void:
	_is_visible_on_screen = true


## Disables per-frame shader uniform updates when leaving camera frustum.
func _on_screen_exited() -> void:
	_is_visible_on_screen = false
