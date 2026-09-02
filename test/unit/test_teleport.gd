extends GutTest
## Unit tests for the Teleport class.
class_name TestTeleport

## The Teleport instance being tested.
var _teleport: Teleport
## A mock player instance.
var _player: Node3D
## The target portal Area3D.
var _target_portal: Area3D


func before_each() -> void:
	print("TestTeleport: Setting up test environment.")
	_teleport = Teleport.new()
	var portal_sound: AudioStreamPlayer = AudioStreamPlayer.new()
	portal_sound.name = "AudioStreamPlayer"
	var dummy_stream: AudioStreamWAV = AudioStreamWAV.new()
	portal_sound.stream = dummy_stream
	_teleport.add_child(portal_sound)
	_teleport.portal_sound = portal_sound
	add_child(_teleport)

	_target_portal = Area3D.new()
	add_child(_target_portal)
	_target_portal.global_transform.origin = Vector3(10, 20, 30)

	_teleport.connect_portal = _target_portal

	_player = Node3D.new()
	_player.name = "Player"
	add_child(_player)
	_player.global_transform.origin = Vector3.ZERO


func after_each() -> void:
	print("TestTeleport: Tearing down test environment.")
	if is_instance_valid(_teleport):
		_teleport.free()
	if is_instance_valid(_target_portal):
		_target_portal.free()
	if is_instance_valid(_player):
		_player.free()

	_teleport = null
	_target_portal = null
	_player = null


func test_player_enters_teleport() -> void:
	print("TestTeleport: test_player_enters_teleport")

	_teleport._on_body_entered(_player)

	assert_eq(
		_player.global_position,
		Vector3(10, 20, 30),
		"Player should be teleported to the target portal's location."
	)
	assert_true(_teleport.portal_sound.playing, "Portal sound should be playing.")


## Verifies that non-player entities are not teleported.
func test_non_player_enters_teleport() -> void:
	print("TestTeleport: test_non_player_enters_teleport")

	var other_body: Node3D = Node3D.new()
	other_body.name = "Enemy"
	add_child(other_body)
	other_body.global_position = Vector3.ZERO

	_teleport._on_body_entered(other_body)

	assert_eq(
		other_body.global_position, Vector3.ZERO, "Non-player entity should not be teleported."
	)
	assert_false(_teleport.portal_sound.playing, "Portal sound should not be playing.")

	other_body.queue_free()


func test_no_connect_portal_assigned() -> void:
	print("TestTeleport: test_no_connect_portal_assigned")

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


## Verifies that the player is still teleported even when no sound player is assigned.
func test_no_portal_sound_assigned() -> void:
	print("TestTeleport: test_no_portal_sound_assigned")

	if is_instance_valid(_teleport.portal_sound):
		_teleport.portal_sound.queue_free()
	_teleport.portal_sound = null

	_teleport._on_body_entered(_player)

	assert_eq(
		_player.global_position,
		Vector3(10.0, 20.0, 30.0),
		"Player should still be teleported even if portal_sound is missing."
	)
