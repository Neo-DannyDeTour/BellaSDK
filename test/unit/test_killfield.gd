## Unit tests for the Killfield component.
class_name TestKillfield
extends GutTest

## The loaded script reference for [Killfield].
const KILLFIELD_SCRIPT: GDScript = preload("res://shared/killfield.gd")

## The instance of the [Killfield] being tested.
var killfield: Variant = null
## Dummy player object.
var dummy_player: Variant = null


## Inner class for mocking player.
class MockPlayer:
	extends Node3D
	## Tracks if teleport_to was called.
	var teleport_called: bool = false
	## Noclip variable to test bypass.
	var noclip: bool = false

	## Fake teleport method.
	func teleport_to(_pos: Vector3, _duration: float) -> void:
		teleport_called = true


## Sets up the test environment.
func before_each() -> void:
	print("TestKillfield: before_each() setup.")
	killfield = KILLFIELD_SCRIPT.new()
	killfield.spawn_height_offset = 1.0
	add_child_autofree(killfield)

	dummy_player = MockPlayer.new()
	dummy_player.name = "Player"
	add_child_autofree(dummy_player)

	# Setup the global SaveManager state for the test
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if not save_manager:
		# If the autoload isn't present in the headless GUT run, we create a mock
		save_manager = Node.new()
		save_manager.name = "SaveManager"
		get_tree().root.add_child(save_manager)

	save_manager.set("last_checkpoint_pos", Vector3(10, 10, 10))


## Cleanup after tests.
func after_each() -> void:
	print("TestKillfield: after_each() teardown.")
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.set("last_checkpoint_pos", Vector3.ZERO)


## Verifies killfield triggers teleport on player body entered.
func test_on_body_entered_player() -> void:
	print("TestKillfield: test_on_body_entered_player() called.")

	killfield._on_body_entered(dummy_player)

	assert_true(dummy_player.teleport_called, "Killfield should call teleport_to on player.")


## Verifies killfield ignores players with noclip enabled.
func test_on_body_entered_noclip() -> void:
	print("TestKillfield: test_on_body_entered_noclip() called.")
	dummy_player.noclip = true

	killfield._on_body_entered(dummy_player)

	assert_false(dummy_player.teleport_called, "Killfield should ignore players with noclip.")
