## Unit tests for [FenceDoor] covering static frame, hinged leaf, lock, touch rattle, and sequencer.
class_name TestFenceDoor
extends GutTest

## Preloaded [FenceDoor] scene under test.
const FENCE_DOOR_SCENE: PackedScene = preload("res://interactables/fence_door.tscn")

## Active [FenceDoor] instance for each test case.
var _door: FenceDoor = null


## Instantiates a fresh [FenceDoor] inside the test scene tree.
func before_each() -> void:
	_door = FENCE_DOOR_SCENE.instantiate() as FenceDoor
	_door.swing_duration = 0.05
	add_child_autofree(_door)


## Verifies leaf mesh reparents to [AnimatableBody3D] while frame remains static on Layer 1.
func test_hierarchy_and_layers() -> void:
	var frame_body: StaticBody3D = _door.get_node("FrameBody") as StaticBody3D
	var leaf_body: AnimatableBody3D = _door.get_node("DoorLeaf") as AnimatableBody3D
	var model_root: Node3D = _door.get_node("FenceDoorModel") as Node3D

	assert_eq(frame_body.collision_layer, CollisionLayers.MASK_ENVIRONMENT)
	assert_eq(leaf_body.collision_layer, CollisionLayers.MASK_INTERACTIVE)
	assert_not_null(leaf_body.find_child("FenceDoor_Leaf", true, false))
	assert_not_null(model_root.find_child("FenceDoor_Frame", true, false))
	assert_null(model_root.find_child("FenceDoor_Leaf", true, false))
	assert_not_null(_door.open_sfx)
	assert_not_null(_door.close_sfx)
	assert_eq(_door.shake_sfx.size(), 3)


## Verifies unlocked interaction toggles open/closed and emits [signal FenceDoor.state_changed].
func test_interact_toggles_when_unlocked() -> void:
	watch_signals(_door)
	assert_false(_door.is_open)

	_door.interact()
	assert_true(_door.is_open)
	assert_signal_emitted(_door, "opened")
	assert_signal_emitted_with_parameters(_door, "state_changed", [true])

	_door.interact()
	assert_false(_door.is_open)
	assert_signal_emitted(_door, "closed")
	assert_signal_emitted_with_parameters(_door, "state_changed", [false])


## Verifies locked interaction blocks opening, rattles fence, and emits [signal door_locked].
func test_interact_blocked_when_locked() -> void:
	_door.is_locked = true
	watch_signals(_door)

	_door.interact()

	assert_false(_door.is_open)
	assert_signal_emitted(_door, "door_locked")
	assert_signal_emitted(_door, "fence_shaken")
	assert_signal_not_emitted(_door, "opened")


## Verifies [EventStep] CALL_METHOD and SET_PROPERTY control lock, open, close, and shake.
func test_event_sequencer_full_control() -> void:
	_door.is_locked = true
	watch_signals(_door)

	var step_open: EventStep = EventStep.new()
	step_open.step_type = EventStep.StepType.CALL_METHOD
	step_open.target_path = NodePath(_door.name)
	step_open.method_name = &"open_door"
	step_open.execute(self, null)
	assert_true(_door.is_open, "Sequencer open_door should bypass is_locked.")

	var step_close: EventStep = EventStep.new()
	step_close.step_type = EventStep.StepType.CALL_METHOD
	step_close.target_path = NodePath(_door.name)
	step_close.method_name = &"close_door"
	step_close.execute(self, null)
	assert_false(_door.is_open)

	var step_unlock: EventStep = EventStep.new()
	step_unlock.step_type = EventStep.StepType.CALL_METHOD
	step_unlock.target_path = NodePath(_door.name)
	step_unlock.method_name = &"unlock_door"
	step_unlock.execute(self, null)
	assert_false(_door.is_locked)
	assert_signal_emitted(_door, "unlocked")

	var step_lock_prop: EventStep = EventStep.new()
	step_lock_prop.step_type = EventStep.StepType.SET_PROPERTY
	step_lock_prop.target_path = NodePath(_door.name)
	step_lock_prop.method_name = &"is_locked"
	step_lock_prop.parameter = "true"
	step_lock_prop.execute(self, null)
	assert_true(_door.is_locked)


## Verifies physical touch callback on [Area3D] emits [signal FenceDoor.fence_shaken] with cooldown.
func test_touch_triggers_fence_shake_with_cooldown() -> void:
	var dummy_player: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(dummy_player)
	_door.touch_shake_cooldown = 1.0
	watch_signals(_door)

	_door._on_touch_area_body_entered(dummy_player)
	assert_signal_emit_count(_door, "fence_shaken", 1)

	_door._on_touch_area_body_entered(dummy_player)
	assert_signal_emit_count(_door, "fence_shaken", 1)
