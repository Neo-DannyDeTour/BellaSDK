extends "res://addons/gut/test.gd"
## Unit tests for the Killfield class.
class_name TestKillfield


class MockPlayer:
	extends Node3D
	var noclip: bool = false
	var teleported_to: Vector3
	var teleport_delay: float

	func teleport_to(pos: Vector3, delay: float) -> void:
		teleported_to = pos
		teleport_delay = delay


## The Killfield instance being tested.
var _killfield: Killfield
## A mock player instance.
var _player: MockPlayer


func before_each() -> void:
	print("TestKillfield: Setting up test environment.")
	_killfield = Killfield.new()
	_killfield.spawn_height_offset = 1.0
	add_child(_killfield)

	_player = MockPlayer.new()
	_player.name = "Player"
	add_child(_player)


func after_each() -> void:
	print("TestKillfield: Tearing down test environment.")
	if is_instance_valid(_killfield):
		_killfield.queue_free()
	if is_instance_valid(_player):
		_player.queue_free()

	_killfield = null
	_player = null

	SaveManager.last_checkpoint_pos = Vector3.ZERO


func test_player_enters_killfield() -> void:
	print("TestKillfield: test_player_enters_killfield")
	SaveManager.last_checkpoint_pos = Vector3(10, 0, 10)

	_killfield._on_body_entered(_player)

	var expected_pos: Vector3 = SaveManager.last_checkpoint_pos + Vector3(0, 1.0, 0)
	assert_eq(
		_player.teleported_to,
		expected_pos,
		"Player should be teleported to checkpoint with offset."
	)
	assert_eq(_player.teleport_delay, 0.2, "Teleport delay should be 0.2.")


func test_noclip_player_ignores_killfield() -> void:
	print("TestKillfield: test_noclip_player_ignores_killfield")
	SaveManager.last_checkpoint_pos = Vector3(10, 0, 10)
	_player.noclip = true

	_killfield._on_body_entered(_player)

	assert_eq(_player.teleported_to, Vector3.ZERO, "Noclip player should not be teleported.")


func test_non_player_enters_killfield() -> void:
	print("TestKillfield: test_non_player_enters_killfield")
	SaveManager.last_checkpoint_pos = Vector3(10, 0, 10)

	var other_body: Node3D = Node3D.new()
	other_body.name = "Enemy"
	add_child(other_body)

	_killfield._on_body_entered(other_body)

	other_body.queue_free()
	# No assertion needed, just verifying it doesn't crash trying to access non-existent properties


func test_no_checkpoint_set() -> void:
	print("TestKillfield: test_no_checkpoint_set")
	SaveManager.last_checkpoint_pos = Vector3.ZERO

	_killfield._on_body_entered(_player)

	assert_eq(
		_player.teleported_to,
		Vector3.ZERO,
		"Player should not be teleported if no checkpoint is set."
	)
