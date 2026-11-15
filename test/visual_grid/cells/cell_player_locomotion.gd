## Visual test cell verifying [Player] forward locomotion displacement on test pad.
class_name CellPlayerLocomotion
extends MechanicTestCell

## Preloaded player character scene.
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

## Spawned player instance under test.
var _player: CharacterBody3D = null


## Spawns player on the pad and preserves mouse mode.
func _setup_cell() -> void:
	cell_title = "Player: Locomotion"
	_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	_player.position = Vector3(0.0, 0.5, 2.5)
	add_child(_player)
	await wait_frames(4)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Simulates forward movement input and verifies player displacement.
func _run_test() -> void:
	if not assert_true(is_instance_valid(_player), "Player must instantiate."):
		return

	var start_pos: Vector3 = _player.global_position
	Input.action_press("forward")
	await get_tree().create_timer(0.35).timeout
	Input.action_release("forward")
	await wait_frames(2)

	var moved_sq: float = _player.global_position.distance_squared_to(start_pos)
	assert_true(moved_sq > 0.04, "Player must move forward when forward action is held.")


## Releases held inputs and frees spawned player instance.
func _teardown_cell() -> void:
	Input.action_release("forward")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(_player):
		_player.queue_free()
	await wait_frames(1)
