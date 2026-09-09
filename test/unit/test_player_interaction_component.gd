extends GutTest

## The component being tested.
var component: PlayerInteractionComponent

## A mock player character body to pass into the component.
var player: CharacterBody3D

## A mock camera for the throw direction.
var camera: Camera3D

## A mock rigid body item.
var item: RigidBody3D


## Custom class overriding drop and throw to track invocations.
class MockItem:
	extends RigidBody3D
	## Whether drop was called.
	var drop_called: bool = false

	## Whether throw was called.
	var throw_called: bool = false

	func drop() -> void:
		drop_called = true

	func throw(_force: Vector3) -> void:
		throw_called = true


func before_each() -> void:
	print("test_player_interaction_component: before_each() - Setup.")
	component = PlayerInteractionComponent.new()
	player = CharacterBody3D.new()
	camera = Camera3D.new()
	item = MockItem.new()

	component.camera = camera

	add_child_autofree(component)
	add_child_autofree(player)
	add_child_autofree(camera)
	add_child_autofree(item)


func test_initialize() -> void:
	print("test_player_interaction_component: test_initialize().")
	component.initialize(player)
	assert_eq(component.player, player, "Player reference should be cached.")


func test_throw_held_item() -> void:
	print("test_player_interaction_component: test_throw_held_item().")
	component.initialize(player)
	component.held_item = item

	component.throw_held_item()

	assert_null(component.held_item, "Held item should be cleared after throw.")
	assert_true((item as MockItem).throw_called, "Item throw method should be invoked.")


func test_drop_held_item() -> void:
	print("test_player_interaction_component: test_drop_held_item().")
	component.initialize(player)
	component.held_item = item

	component.drop_held_item()

	assert_null(component.held_item, "Held item should be cleared after drop.")
	assert_true((item as MockItem).drop_called, "Item drop method should be invoked.")


func test_force_clear_hands() -> void:
	print("test_player_interaction_component: test_force_clear_hands().")
	component.held_item = item
	component.force_clear_hands()

	assert_null(component.held_item, "Hands should be cleared.")


func test_set_heavy_lifting() -> void:
	print("test_player_interaction_component: test_set_heavy_lifting().")
	component.initialize(player)

	# The property is actually is_heavy_lifting. Let's test the setter and effect.
	component._set_heavy_lifting(true)
	assert_true(component.is_heavy_lifting, "State should be updated to true.")

	component._set_heavy_lifting(false)
	assert_false(component.is_heavy_lifting, "State should be updated to false.")
