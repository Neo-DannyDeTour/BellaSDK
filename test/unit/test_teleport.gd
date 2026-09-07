## Unit tests for the [Teleport] component verifying transitions and audio.
class_name TestTeleport
extends GutTest

## The [Teleport] instance under test.
var _teleport: Teleport = null
## The mock player node instance.
var _player: Node3D = null
## The destination [Area3D] portal node.
var _target_portal: Area3D = null


## Prepares test nodes and wiring before each test execution.
func before_each() -> void:
	print("TestTeleport: Setting up test environment.")
	_teleport = Teleport.new()

	var portal_sound: AudioStreamPlayer = AudioStreamPlayer.new()
	portal_sound.name = "AudioStreamPlayer"
	var dummy_stream: AudioStreamWAV = AudioStreamWAV.new()
	portal_sound.stream = dummy_stream
	_teleport.add_child(portal_sound)
	_teleport.portal_sound = portal_sound
	add_child_autoqfree(_teleport)

	_target_portal = Area3D.new()
	add_child_autoqfree(_target_portal)
	_target_portal.global_transform.origin = Vector3(10.0, 20.0, 30.0)

	_teleport.connect_portal = _target_portal

	_player = Node3D.new()
	_player.name = "Player"
	add_child_autoqfree(_player)
	_player.global_transform.origin = Vector3.ZERO


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestTeleport: Tearing down test environment.")
	_teleport = null
	_target_portal = null
	_player = null


## Verifies that a player body entering the portal updates position and audio.
func test_player_enters_teleport() -> void:
	print("TestTeleport: test_player_enters_teleport() called.")
	_teleport._on_body_entered(_player)

	assert_eq(
		_player.global_position,
		Vector3(10.0, 20.0, 30.0),
		"Player should be teleported to the target portal's location."
	)
	assert_true(_teleport.portal_sound.playing, "Portal sound should be playing.")


## Verifies that non-player bodies entering the portal are ignored.
func test_non_player_enters_teleport() -> void:
	print("TestTeleport: test_non_player_enters_teleport() called.")
	var other_body: Node3D = Node3D.new()
	other_body.name = "Enemy"
	add_child_autoqfree(other_body)
	other_body.global_position = Vector3.ZERO

	_teleport._on_body_entered(other_body)

	assert_eq(
		other_body.global_position, Vector3.ZERO, "Non-player entity should not be teleported."
	)
	assert_false(_teleport.portal_sound.playing, "Portal sound should not be playing.")


## Verifies that no teleportation occurs when no destination portal is bound.
func test_no_connect_portal_assigned() -> void:
	print("TestTeleport: test_no_connect_portal_assigned() called.")
	_teleport.connect_portal = null

	_teleport._on_body_entered(_player)

	assert_eq(
		_player.global_position,
		Vector3.ZERO,
		"Player should not be teleported if no connect_portal is assigned."
	)
	assert_false(
		_teleport.portal_sound.playing,
		"Portal sound should not be playing if teleportation didn't occur."
	)


## Verifies that teleportation completes even if portal_sound is unassigned.
func test_no_portal_sound_assigned() -> void:
	print("TestTeleport: test_no_portal_sound_assigned() called.")
	if is_instance_valid(_teleport.portal_sound):
		var old_sound: AudioStreamPlayer = _teleport.portal_sound
		_teleport.portal_sound = null
		_teleport.remove_child(old_sound)
		old_sound.free()

	_teleport._on_body_entered(_player)

	assert_eq(
		_player.global_position,
		Vector3(10.0, 20.0, 30.0),
		"Player should still be teleported even if portal_sound is missing."
	)
