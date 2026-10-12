## Physics-driven test dummy with bobbing motion, damage knockback, and gore VFX.
class_name EvilGoon
extends RigidBody3D

## Injected [HealthComponent] managing entity life points and death handling.
@export var health_component: HealthComponent

## The impulse force applied to the dummy when struck by attacks.
@export var knockback_force: float = 0.5

## The vertical impulse added during knockback to lift the dummy.
@export var vertical_kick: float = 0.7

## Lifetime in seconds before blood decals fade out and free to sustain 60 FPS.
@export var decal_lifetime: float = 8.0

@export_group("Blood Decal Assets")
## Collection of blood splatter textures picked at random for impacts.
@export var blood_splatters: Array[Texture2D] = []

## Optional normal map texture applied across blood decal instances.
@export var blood_normal_map: Texture2D

@export_group("Audio Streams (Future Setup)")
## Audio stream played at hit location when taking projectile damage.
@export var hit_sound: AudioStream

## Audio stream played at entity location during death explosion.
@export var death_sound: AudioStream

## Target audio bus name routing spatial gore sound effects.
@export var sfx_bus: StringName = &"SFX"

## Accumulated elapsed time used to compute the oscillating bob motion.
var time_passed: float = 0.0


## Initializes dependencies, resolves [HealthComponent], and sets layers.
func _ready() -> void:
	print("EvilGoon: Initializing goon entity.")
	collision_layer = CollisionLayers.MASK_ENEMIES
	collision_mask = (
		CollisionLayers.MASK_ENVIRONMENT
		| CollisionLayers.MASK_PLAYER
		| CollisionLayers.MASK_INTERACTIVE
		| CollisionLayers.MASK_ENEMIES
	)

	if not is_instance_valid(health_component):
		health_component = get_node_or_null("HealthComponent") as HealthComponent

	if not is_instance_valid(health_component):
		health_component = (find_child("HealthComponent", false, false) as HealthComponent)

	if is_instance_valid(health_component):
		health_component.use_pooling = false
		health_component.died.connect(_on_health_component_died)
		print("EvilGoon: Bound to HealthComponent with ", health_component.current_health, " HP.")
	else:
		push_warning("EvilGoon: HealthComponent could not be resolved.")


## Applies oscillatory vertical bobbing force on the physics body.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	time_passed += get_process_delta_time()
	var bob: float = sin(time_passed * 2.0) * 0.5
	state.apply_force(Vector3(0.0, bob, 0.0))


## Inflicts damage, creates blood VFX and decals, and applies knockback impulse.
func take_damage(amount: int, hit_position: Vector3, dir: Vector3) -> void:
	print("EvilGoon: take_damage() called. Amount: ", amount)
	_play_spatial_sound(hit_sound, hit_position)
	_spawn_blood_spray(hit_position, dir)
	_try_spawn_floor_decal(hit_position, dir)

	if is_instance_valid(health_component):
		health_component.take_damage(amount)

	var punch: Vector3 = dir.normalized() * knockback_force
	punch.y += vertical_kick
	apply_central_impulse(punch)


## Triggered when [signal HealthComponent.died] is emitted.
func _on_health_component_died() -> void:
	print("EvilGoon: _on_health_component_died() received from HealthComponent.")
	die()


## Executes death sequence with blood explosion, smoke, and cleans up entity.
func die() -> void:
	print("EvilGoon: die() called. Spawning explosion VFX and freeing node.")
	_play_spatial_sound(death_sound, global_position)
	_spawn_death_explosion(global_position)
	_try_spawn_floor_decal(global_position + Vector3.UP * 0.5, Vector3.DOWN)

	if Events.has_signal("enemy_killed"):
		Events.enemy_killed.emit(self, null)

	queue_free()


## Relays 3D positional audio requests to the global [Events] bus singleton.
func _play_spatial_sound(stream: AudioStream, at_pos: Vector3) -> void:
	if not is_instance_valid(stream):
		return
	print("EvilGoon: Emitting sfx_3d_requested for audio at ", at_pos)
	Events.sfx_3d_requested.emit(stream, at_pos, sfx_bus)


## Spawns directional blood spray particles flying away from the shooter.
func _spawn_blood_spray(hit_pos: Vector3, shot_dir: Vector3) -> void:
	print("EvilGoon: Instantiating BloodSplatterVFX away from shot.")
	var splatter: BloodSplatterVFX = BloodSplatterVFX.new()
	get_tree().current_scene.add_child(splatter)
	splatter.global_position = hit_pos

	var chosen_tex: Texture2D = null
	if not blood_splatters.is_empty():
		chosen_tex = blood_splatters[randi() % blood_splatters.size()]
	splatter.setup(shot_dir, chosen_tex)


## Casts a ray downward/backward to find an environment surface for a decal.
func _try_spawn_floor_decal(origin: Vector3, shot_dir: Vector3) -> void:
	print("EvilGoon: Raycasting for environment surface to place decal.")
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not is_instance_valid(space_state):
		return

	var cast_dir: Vector3 = (shot_dir.normalized() * 0.6 + Vector3.DOWN).normalized()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + cast_dir * 4.0, 1 << 0
	)
	query.exclude = [get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var surface_pos: Vector3 = result.get("position", Vector3.ZERO)
	var surface_normal: Vector3 = result.get("normal", Vector3.UP)

	var chosen_tex: Texture2D = null
	if not blood_splatters.is_empty():
		chosen_tex = blood_splatters[randi() % blood_splatters.size()]

	var decal: BloodDecal = BloodDecal.new()
	get_tree().current_scene.add_child(decal)
	decal.setup(surface_pos, surface_normal, chosen_tex, decal_lifetime)


## Spawns death blood explosion and smoke burst at the goon position.
func _spawn_death_explosion(death_pos: Vector3) -> void:
	print("EvilGoon: Spawning death gore burst.")
	var root: Node = get_tree().current_scene

	var blood_burst: CPUParticles3D = CPUParticles3D.new()
	blood_burst.emitting = false
	blood_burst.one_shot = true
	blood_burst.explosiveness = 1.0
	blood_burst.amount = 40
	blood_burst.lifetime = 0.5
	var b_quad: QuadMesh = QuadMesh.new()
	b_quad.size = Vector2(0.18, 0.18)
	blood_burst.mesh = b_quad

	var b_mat: StandardMaterial3D = StandardMaterial3D.new()
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	b_mat.alpha_scissor_threshold = 0.2
	b_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	b_mat.albedo_color = Color(0.6, 0.01, 0.01, 1.0)
	if not blood_splatters.is_empty():
		b_mat.albedo_texture = blood_splatters[0]
	blood_burst.material_override = b_mat
	blood_burst.direction = Vector3.UP
	blood_burst.spread = 180.0
	blood_burst.initial_velocity_min = 3.5
	blood_burst.initial_velocity_max = 7.0
	blood_burst.gravity = Vector3(0.0, -12.0, 0.0)

	root.add_child(blood_burst)
	blood_burst.global_position = death_pos + Vector3.UP * 0.4
	blood_burst.emitting = true

	var smoke: CPUParticles3D = CPUParticles3D.new()
	smoke.emitting = false
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.amount = 20
	smoke.lifetime = 0.8
	var s_quad: QuadMesh = QuadMesh.new()
	s_quad.size = Vector2(0.3, 0.3)
	smoke.mesh = s_quad

	var s_mat: StandardMaterial3D = StandardMaterial3D.new()
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	s_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
	smoke.material_override = s_mat
	smoke.direction = Vector3.UP
	smoke.spread = 45.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 2.5
	smoke.gravity = Vector3(0.0, 1.0, 0.0)

	root.add_child(smoke)
	smoke.global_position = death_pos + Vector3.UP * 0.2
	smoke.emitting = true

	var cleanup_timer: SceneTreeTimer = get_tree().create_timer(1.0)
	cleanup_timer.timeout.connect(blood_burst.queue_free)
	cleanup_timer.timeout.connect(smoke.queue_free)
