## Unit test suite validating [Turret] targeting, state progression, and hostility.
class_name TestTurret
extends GutTest

## Preloaded packed scene reference for the turret under test.
const TURRET_SCENE: PackedScene = preload("res://enemies/turret.tscn")

## The Turret node instance under test.
var turret: Turret = null

## Dummy node for target tracking.
var dummy_target: Node3D = null

## Health component for damage testing.
var health_comp: HealthComponent = null


## Prepares turret instance, mock target, and components before each test run.
func before_each() -> void:
	print("TestTurret: before_each() setup.")

	var raw_instance: Variant = TURRET_SCENE.instantiate()
	if raw_instance is Turret:
		turret = raw_instance
	add_child_autofree(turret)

	dummy_target = Node3D.new()
	dummy_target.name = "DummyTarget"

	var components_node: Node = Node.new()
	components_node.name = "Components"
	dummy_target.add_child(components_node)

	health_comp = HealthComponent.new()
	health_comp.name = "HealthComponent"
	health_comp.max_health = 100
	components_node.add_child(health_comp)

	add_child_autofree(dummy_target)
	dummy_target.set("health_component", health_comp)
	health_comp._ready()


## Validates target assignment and internal health component caching.
func test_set_target() -> void:
	print("TestTurret: test_set_target() called.")
	turret.call("_set_target", dummy_target)

	assert_eq(turret.target, dummy_target, "Turret should correctly assign the target.")
	assert_eq(
		turret.target_health_comp,
		health_comp,
		"Turret should correctly cache the target's HealthComponent."
	)


## Validates transition into engagement state.
func test_change_state() -> void:
	print("TestTurret: test_change_state() called.")
	turret.call("_change_state", Turret.TurretState.ENGAGING)

	assert_eq(
		turret.current_state, Turret.TurretState.ENGAGING, "Turret state should update to ENGAGING."
	)


## Validates target damage application against cached health component.
func test_damage_player() -> void:
	print("TestTurret: test_damage_player() called.")
	turret.call("_set_target", dummy_target)
	turret.damage = 15

	turret.call("_damage_target")

	assert_eq(
		health_comp.current_health,
		85,
		"Turret should deal correct damage to the target's HealthComponent."
	)


## Validates hostile target discrimination based on faction alignment.
func test_is_hostile() -> void:
	print("TestTurret: test_is_hostile() called.")

	var mock_enemy: Node3D = Node3D.new()
	var enemy_faction: FactionComponent = FactionComponent.new()
	enemy_faction.faction = Types.Faction.ENEMY
	mock_enemy.add_child(enemy_faction)

	var mock_player: Node3D = Node3D.new()
	var player_faction: FactionComponent = FactionComponent.new()
	player_faction.faction = Types.Faction.PLAYER
	mock_player.add_child(player_faction)

	var enemy_result: Variant = turret.call("_is_hostile", mock_enemy)
	var enemy_hostile: bool = false
	if enemy_result is bool:
		enemy_hostile = enemy_result

	var player_result: Variant = turret.call("_is_hostile", mock_player)
	var player_hostile: bool = false
	if player_result is bool:
		player_hostile = player_result

	assert_false(enemy_hostile, "Should not identify same faction as hostile.")
	assert_true(player_hostile, "Should identify player faction as hostile.")

	mock_enemy.free()
	mock_player.free()
