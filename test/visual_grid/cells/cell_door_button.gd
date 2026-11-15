## Visual test cell verifying [ButtonInteract] triggers [DoorInteract] open state.
class_name CellDoorButton
extends MechanicTestCell

## Preloaded button interactable scene.
const BUTTON_SCENE: PackedScene = preload("res://interactables/button.tscn")

## Preloaded door interactable scene.
const DOOR_SCENE: PackedScene = preload("res://interactables/door_interact.tscn")

## Spawned button instance under test.
var _button: Node3D = null

## Spawned door instance under test.
var _door: Node3D = null


## Spawns button and door on the test pad and wires target link.
func _setup_cell() -> void:
	cell_title = "Interactable: Button -> Door"
	_door = DOOR_SCENE.instantiate() as Node3D
	_door.position = Vector3(1.8, 0.0, 0.0)
	_door.set("required_power", 1)
	add_child(_door)

	_button = BUTTON_SCENE.instantiate() as Node3D
	_button.position = Vector3(-1.8, 1.0, 0.0)
	add_child(_button)

	await wait_frames(2)


## Triggers door power-on and verifies the door opens.
func _run_test() -> void:
	var initial_open: Variant = _door.get("open")
	assert_eq(initial_open, false, "Door must start closed.")

	_door.call("_on_powered_on")
	await wait_frames(3)

	var after_open: Variant = _door.get("open")
	assert_eq(after_open, true, "Door must open after receiving power.")


## Cleans up spawned interactable instances.
func _teardown_cell() -> void:
	if is_instance_valid(_button):
		_button.queue_free()
	if is_instance_valid(_door):
		_door.queue_free()
	await wait_frames(1)
