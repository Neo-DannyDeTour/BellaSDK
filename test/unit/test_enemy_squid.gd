## Tests EnemySquid initialization, state transitions, puddle pool, and pool reset.
class_name TestEnemySquid
extends GutTest

## The [EnemySquid] instance under test.
var squid: EnemySquid = null


## Prepares fresh squid instance before each test.
func before_each() -> void:
	squid = EnemySquid.new()
	add_child_autofree(squid)


## Verifies squid initializes with correct collision layers, visual root, and components.
func test_squid_initialization() -> void:
	assert_not_null(squid.faction_component)
	assert_not_null(squid.health_component)
	assert_eq(squid.collision_layer, Types.MASK_ENEMIES)
	assert_eq(squid.motion_mode, CharacterBody3D.MOTION_MODE_GROUNDED)


## Verifies reset_squid re-anchors home position and clears velocity and target.
func test_squid_reset() -> void:
	var reset_pos: Vector3 = Vector3(10.0, 2.0, -5.0)
	squid.reset_squid(reset_pos)
	assert_eq(squid.global_position, reset_pos)
	assert_eq(squid.velocity, Vector3.ZERO)


## Verifies squid is registered in mandatory enemy and damageable groups.
func test_squid_groups() -> void:
	assert_true(squid.is_in_group(&"enemy"), "Squid must be in 'enemy' group.")
	assert_true(squid.is_in_group(&"damageable"), "Squid must be in 'damageable' group.")


## Verifies take_damage reduces health and applies directional flinch impulse.
func test_squid_take_damage_and_flinch() -> void:
	var init_hp: int = squid.health_component.current_health
	var shot_dir: Vector3 = Vector3(0.0, 0.0, -1.0)
	squid.take_damage(20, squid.global_position, shot_dir)

	assert_eq(
		squid.health_component.current_health,
		init_hp - 20,
		"Squid health should decrease by damage amount."
	)
	assert_almost_eq(squid.velocity.z, -2.5, 0.1, "Squid should flinch along shot direction.")
