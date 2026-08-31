extends GutTest


## Local mock of a player explicitly for testing locomotion independently.
class MockPlayerInner:
	extends CharacterBody3D
	## Tracks the number of slide collisions retrieved to simulate floor checks.
	var collision_count: int = 0

	## Overrides native method for testing floor weight checks.
	func is_on_floor() -> bool:
		return true

	## Overrides native method for testing floor weight checks.
	func get_slide_collision_count() -> int:
		return collision_count


## The locomotion component instance being tested.
var _locomotion: PlayerLocomotionComponent
## The mock player instance used as the parent for testing.
var _player: MockPlayerInner


func before_each() -> void:
	print("TestLocomotionComponent: Setting up test environment.")
	_player = MockPlayerInner.new()
	_locomotion = PlayerLocomotionComponent.new()
	_player.add_child(_locomotion)


func after_each() -> void:
	print("TestLocomotionComponent: Tearing down test environment.")
	if is_instance_valid(_locomotion):
		_locomotion.queue_free()
	if is_instance_valid(_player):
		_player.queue_free()


func test_initialization() -> void:
	print("TestLocomotionComponent: Testing initialization.")
	# Pass as Player using duck typing bypass for the generic test,
	# Godot 4 explicit static typing can be bypassed by set() or direct assignment if type cast fails
	_locomotion.player = _player as Node
	assert_eq(_locomotion.player, _player, "Player reference should be cached.")


func test_physics_active_state() -> void:
	print("TestLocomotionComponent: Testing physics active state toggle.")
	_locomotion.set_physics_active(false)
	assert_false(_locomotion.is_active, "Component should be inactive.")
	_locomotion.set_physics_active(true)
	assert_true(_locomotion.is_active, "Component should be active.")


func test_sprint_tracking() -> void:
	print("TestLocomotionComponent: Testing sprint tracking (did_run_recently).")
	_locomotion.player = _player as Node
	_locomotion.sprint_active = true
	_locomotion.process_movement(0.016)

	# The mock player won't trigger the rigid body weight logic,
	# but it will update the sprint time
	assert_true(_locomotion.did_run_recently(100), "Player should have run recently.")

	# Wait a bit to test the time window
	# Note: In a real test we'd probably mock Time.get_ticks_msec(),
	# but we can't easily do that here.
	# So we'll just test the false case by overriding the private variable
	_locomotion.set("_last_sprint_time", Time.get_ticks_msec() - 1000)
	var not_recent: bool = not _locomotion.did_run_recently(500)
	assert_true(not_recent, "Player should not have run recently outside time window.")
