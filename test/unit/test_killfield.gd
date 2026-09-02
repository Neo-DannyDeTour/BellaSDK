## Inner mock class simulating playerThe errors occur because Godot
## registers inner classes with `class_name` or matching global
## names into the global symbol table. If another script in your
## project already defines a global `class_name MockPlayer`,
## your inner class shadows it, creating a type conflict between the global
## `MockPlayer` and the local inner class `MockPlayer`.
## Unit tests for the [Killfield] class using GUT.class_name TestKillfield
extends GutTest


## A mock player representation used to verify killfield interactions.
class MockKillfieldPlayer:
	extends Node3D

	## Whether noclip mode is enabled on the mock player.
	var noclip: bool = false
	## The position the mock player was teleported to.
	var teleported_to: Vector3 = Vector3.ZERO
	## The teleport delay duration in seconds.
	var teleport_delay: float = 0.0

	## Simulates teleporting the player to [param pos] with [param delay].
	func teleport_to(pos: Vector3, delay: float) -> void:
		print("MockKillfieldPlayer: teleport_to called with pos: ", pos, " delay: ", delay)
		teleported_to = pos
		teleport_delay = delay


## The [Killfield] instance being tested.
var _killfield: Killfield
## The [MockKillfieldPlayer] test instance.
var _player: MockKillfieldPlayer


## Prepares the test fixture before each test run.
func before_each() -> void:
	print("TestKillfield: Setting up test environment.")
	_killfield = Killfield.new()
	_killfield.spawn_height_offset = 1.0
	add_child(_killfield)

	_player = MockKillfieldPlayer.new()
	_player.name = "Player"
	add_child(_player)


## Cleans up instantiated nodes and resets global state after each test run.
func after_each() -> void:
	print("TestKillfield: Tearing down test environment.")
	if is_instance_valid(_killfield):
		_killfield.queue_free()
	if is_instance_valid(_player):
		_player.queue_free()

	_killfield = null
	_player = null

	SaveManager.last_checkpoint_pos = Vector3.ZERO


## Verifies that a valid player entering the killfield teleports to the checkpoint plus offset.
func test_player_enters_killfield() -> void:
	print("TestKillfield: test_player_enters_killfield")
	SaveManager.last_checkpoint_pos = Vector3(10.0, 0.0, 10.0)

	_killfield._on_body_entered(_player)

	var expected_pos: Vector3 = SaveManager.last_checkpoint_pos + Vector3(0.0, 1.0, 0.0)
	assert_eq(
		_player.teleported_to,
		expected_pos,
		"Player should be teleported to checkpoint with offset."
	)
	assert_eq(_player.teleport_delay, 0.2, "Teleport delay should be 0.2.")


## Verifies that a player with noclip active is ignored by the killfield.
func test_noclip_player_ignores_killfield() -> void:
	print("TestKillfield: test_noclip_player_ignores_killfield")
	SaveManager.last_checkpoint_pos = Vector3(10.0, 0.0, 10.0)
	_player.noclip = true

	_killfield._on_body_entered(_player)

	assert_eq(_player.teleported_to, Vector3.ZERO, "Noclip player should not be teleported.")


## Verifies that non-player bodies entering the killfield do not cause crashes.
func test_non_player_enters_killfield() -> void:
	print("TestKillfield: test_non_player_enters_killfield")
	SaveManager.last_checkpoint_pos = Vector3(10.0, 0.0, 10.0)

	var other_body: Node3D = Node3D.new()
	other_body.name = "Enemy"
	add_child(other_body)

	_killfield._on_body_entered(other_body)

	other_body.queue_free()


## Verifies that the player is not teleported if no valid checkpoint is recorded.
func test_no_checkpoint_set() -> void:
	print("TestKillfield: test_no_checkpoint_set")
	SaveManager.last_checkpoint_pos = Vector3.ZERO

	_killfield._on_body_entered(_player)

	assert_eq(
		_player.teleported_to,
		Vector3.ZERO,
		"Player should not be teleported if no checkpoint is set."
	)
