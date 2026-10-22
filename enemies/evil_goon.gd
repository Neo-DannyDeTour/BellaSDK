## Physics-driven test dummy with bobbing motion, knockback, and decoupled gore VFX.
class_name EvilGoon
extends RigidBody3D

## Vertical offset from origin for fatal gore burst emission.
const DEATH_FX_OFFSET: Vector3 = Vector3(0.0, 0.4, 0.0)

## Half-height clamp margin ensuring hit height stays within torso bounds.
const HIT_HEIGHT_CLAMP: float = 0.6

## Injected [HealthComponent] managing entity life points and death handling.
@export var health_component: HealthComponent

## The impulse force applied to the dummy when struck by attacks.
@export var knockback_force: float = 0.5

## The vertical impulse added during knockback to lift the dummy.
@export var vertical_kick: float = 0.7

@export_group("Audio Streams (Future Setup)")
## Audio stream played at hit location when taking projectile damage.
@export var hit_sound: AudioStream

## Audio stream played at entity location during death explosion.
@export var death_sound: AudioStream

## Target audio bus name routing spatial gore sound effects.
@export var sfx_bus: StringName = &"SFX"

## Accumulated elapsed time used to compute the oscillating bob motion.
var time_passed: float = 0.0

## Last incoming normalized projectile direction for death splatter alignment.
var _last_hit_dir: Vector3 = Vector3.DOWN

## Guard preventing duplicate death emissions within the same physics frame.
var _is_dead: bool = false


## Initializes dependencies, resolves [HealthComponent], and sets physics layers.
func _ready() -> void:
	print("EvilGoon: Initializing goon entity.")
	set_process(false)
	set_physics_process(false)

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
		health_component = find_child("HealthComponent", false, false) as HealthComponent

	assert(is_instance_valid(health_component), "EvilGoon: HealthComponent is mandatory.")
	if is_instance_valid(health_component):
		health_component.use_pooling = false
		health_component.died.connect(_on_health_component_died)
		print("EvilGoon: Bound to HealthComponent with ", health_component.current_health, " HP.")


## Applies oscillatory vertical bobbing force on the physics body.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	time_passed += state.step
	var bob: float = sin(time_passed * 2.0) * 0.5
	state.apply_force(Vector3(0.0, bob, 0.0))


## Inflicts damage, requests centered entry/exit blood VFX, and applies knockback.
func take_damage(amount: int, hit_position: Vector3, dir: Vector3) -> void:
	if _is_dead:
		return

	print("EvilGoon: take_damage() called. Amount: ", amount)
	_last_hit_dir = dir.normalized() if not dir.is_zero_approx() else Vector3.DOWN

	var clamped_y: float = clampf(
		hit_position.y, global_position.y - HIT_HEIGHT_CLAMP, global_position.y + HIT_HEIGHT_CLAMP
	)
	var core_hit_pos: Vector3 = Vector3(global_position.x, clamped_y, global_position.z)

	_play_spatial_sound(hit_sound, core_hit_pos)

	if is_instance_valid(health_component):
		health_component.take_damage(amount)

	# If damage proved lethal, die() already emitted the fatal blood burst.
	if _is_dead:
		return

	Events.blood_fx_requested.emit(core_hit_pos, _last_hit_dir, false)

	var punch: Vector3 = _last_hit_dir * knockback_force
	punch.y += vertical_kick
	apply_central_impulse(punch)


## Executes death sequence, requests fatal gore burst via [Events], and frees node.
func die() -> void:
	if _is_dead:
		return
	_is_dead = true

	print("EvilGoon: die() called. Emitting fatal blood_fx_requested and freeing node.")
	_play_spatial_sound(death_sound, global_position)
	Events.blood_fx_requested.emit(global_position + DEATH_FX_OFFSET, _last_hit_dir, true)
	Events.enemy_killed.emit(self, null)
	queue_free()


## Triggered when [signal HealthComponent.died] is emitted.
func _on_health_component_died() -> void:
	print("EvilGoon: _on_health_component_died() received from HealthComponent.")
	die()


## Relays 3D positional audio requests to the global [Events] bus singleton.
func _play_spatial_sound(stream: AudioStream, at_pos: Vector3) -> void:
	if not is_instance_valid(stream):
		return
	print("EvilGoon: Emitting sfx_3d_requested for audio at ", at_pos)
	Events.sfx_3d_requested.emit(stream, at_pos, sfx_bus)
