## Unit test suite for validating [PlayerInteractionComponent] logic involving
## held items and throws.
class_name TestPlayerInteractionComponent
extends GutTest

## The component being tested.
var component: PlayerInteractionComponent

## A mock player character body to pass into the component.
var player: CharacterBody3D

## A mock camera for the throw direction.
var camera: Camera3D

## A mock rigid body item.
var item: MockItem


## Custom class overriding drop and throw to track invocations.
class MockItem:
	extends PickableObject
	## Whether drop was called.
	var drop_called: bool = false

	## Whether throw was called.
	var throw_called: bool = false

	## Records the drop action.
	func drop() -> void:
		drop_called = true

	## Records the throw action.
	## [param _force] The forward throw impulse vector.
	func throw(_force: Vector3) -> void:
		throw_called = true


## Sets up the test environment with a mock component, player, camera, and item.
func before_each() -> void:
	print("TestPlayerInteractionComponent: before_each() - Setup.")
	component = PlayerInteractionComponent.new()
	player = CharacterBody3D.new()
	camera = Camera3D.new()
	item = MockItem.new()

	component.camera = camera

	add_child_autofree(component)
	add_child_autofree(player)
	add_child_autofree(camera)
	add_child_autofree(item)


## Verifies that [method PlayerInteractionComponent.initialize] successfully caches the player node.
func test_initialize() -> void:
	print("TestPlayerInteractionComponent: test_initialize().")
	component.initialize(player)
	assert_eq(component.player, player, "Player reference should be cached.")


## Verifies that [method PlayerInteractionComponent.throw_held_item] clears hands and
## invokes item throw.
func test_throw_held_item() -> void:
	print("TestPlayerInteractionComponent: test_throw_held_item().")
	component.initialize(player)
	component.held_item = item

	component.throw_held_item()

	assert_null(component.held_item, "Held item should be cleared after throw.")
	assert_true(item.throw_called, "Item throw method should be invoked.")


## Verifies that [method PlayerInteractionComponent.drop_held_item] clears hands and
## invokes item drop.
func test_drop_held_item() -> void:
	print("TestPlayerInteractionComponent: test_drop_held_item().")
	component.initialize(player)
	component.held_item = item

	component.drop_held_item()

	assert_null(component.held_item, "Held item should be cleared after drop.")
	assert_true(item.drop_called, "Item drop method should be invoked.")


## Verifies that [method PlayerInteractionComponent.force_clear_hands] nullifies the
## held item reference.
func test_force_clear_hands() -> void:
	print("TestPlayerInteractionComponent: test_force_clear_hands().")
	component.held_item = item
	component.force_clear_hands()

	assert_null(component.held_item, "Hands should be cleared.")


## Verifies that heavy lifting states are accurately tracked and updated.
func test_set_heavy_lifting() -> void:
	print("TestPlayerInteractionComponent: test_set_heavy_lifting().")
	component.initialize(player)

	# The property is actually is_heavy_lifting. Let's test the setter and effect.
	component._set_heavy_lifting(true)
	assert_true(component.is_heavy_lifting, "State should be updated to true.")

	component._set_heavy_lifting(false)
	assert_false(component.is_heavy_lifting, "State should be updated to false.")
