## Unit test suite for validating [PlayerLocomotionComponent] logic and state updates.
class_name TestLocomotionComponent
extends GutTest

## The component being tested.
var component: PlayerLocomotionComponent

## A mock player character body to pass into the component.
var player: CharacterBody3D


## Instantiates [PlayerLocomotionComponent] and a dummy [CharacterBody3D] before each test.
func before_each() -> void:
	print("TestLocomotionComponent: before_each() - Setting up test environment.")
	component = PlayerLocomotionComponent.new()
	player = CharacterBody3D.new()
	add_child_autofree(component)
	add_child_autofree(player)


## Verifies that [method PlayerLocomotionComponent.initialize] successfully caches the player node.
func test_initialize() -> void:
	print("TestLocomotionComponent: test_initialize() - Verifying caching.")
	component.initialize(player)
	assert_eq(component.player, player, "Player reference should be cached.")


## Verifies that [method PlayerLocomotionComponent.set_physics_active] toggles processing state.
func test_set_physics_active() -> void:
	print("TestLocomotionComponent: test_set_physics_active() - Verifying state toggle.")
	component.set_physics_active(false)
	assert_false(component.is_active, "is_active should update to false.")

	component.set_physics_active(true)
	assert_true(component.is_active, "is_active should update to true.")


## Verifies that directional vectors are stored and retrieved accurately.
func test_set_and_get_direction() -> void:
	print("TestLocomotionComponent: test_set_and_get_direction() - Checking inputs.")
	var dir: Vector3 = Vector3(1.0, 0.0, 0.0)
	component.set_direction(dir)
	assert_eq(component.get_direction(), dir, "Should return the assigned direction.")


## Verifies that [method PlayerLocomotionComponent.reset_momentum] clears all movement vectors.
func test_reset_momentum() -> void:
	print("TestLocomotionComponent: test_reset_momentum() - Verifying state clear.")
	component.initialize(player)

	var dir: Vector3 = Vector3(1.0, 0.0, 0.0)
	var vel: Vector3 = Vector3(5.0, 0.0, 0.0)

	component.set_direction(dir)
	component.last_velocity = vel
	player.velocity = vel

	component.reset_momentum()

	assert_eq(component.get_direction(), Vector3.ZERO, "Direction should clear.")
	assert_eq(component.last_velocity, Vector3.ZERO, "last_velocity should clear.")
	assert_eq(player.velocity, Vector3.ZERO, "Player velocity should clear.")
