## Generic stub component used in unit tests to stand in for optional or auxiliary player modules.
class_name DummyComponent
extends Node

## Flag indicating whether the player is actively operating fixed machinery.
var is_operating_machine: bool = false

## Flag indicating whether the player is currently focused on an interactive terminal.
var is_in_terminal_mode: bool = false

## Flag indicating whether the player is carrying a heavy two-handed object.
var is_heavy_lifting: bool = false

## Yaw heading baseline used for heavy lifting rotation clamping.
var heavy_lift_yaw_base: float = 0.0

## Cooldown duration remaining before a player can latch onto another zipline.
var zipline_cooldown: float = 0.0

## Active monkey bar handle node within grab distance.
var available_monkey_bar: Node3D = null

## The RigidBody3D currently being carried by the player stub.
var held_item: RigidBody3D = null


## Stub initialization method satisfying component bootstrap contracts.
## [param _player] The root [Node3D] player controller.
func initialize(_player: Node3D) -> void:
	print("DummyComponent: initialize() stub called.")


## Stub per-frame interaction raycasting and scanner updates.
## [param _delta] Physics frame delta time in seconds.
func process_interaction(_delta: float) -> void:
	pass


## Stub evaluation for gesture-resolved inputs.
## [param _event] The [InputEvent] dispatched from the engine.
func process_unhandled_input(_event: InputEvent = null) -> void:
	pass


## Stub per-frame environmental physics calculations.
## [param _delta] Physics frame delta time in seconds.
func process_environment_physics(_delta: float) -> void:
	pass


## Stub transition hook when player mounts a ladder.
## [param _ladder_node] Target ladder [Node3D] instance.
func enter_ladder(_ladder_node: Node3D) -> void:
	print("DummyComponent: enter_ladder() stub called.")


## Stub transition hook when player dismounts a ladder.
## [param _ladder_node] Target ladder [Node3D] instance.
func exit_ladder(_ladder_node: Node3D) -> void:
	print("DummyComponent: exit_ladder() stub called.")


## Stub transition hook when player enters a water volume.
## [param _water_volume] Target water volume [Node3D].
func enter_water(_water_volume: Node3D) -> void:
	print("DummyComponent: enter_water() stub called.")


## Stub transition hook when player exits a water volume.
## [param _water_volume] Target water volume [Node3D].
func exit_water(_water_volume: Node3D) -> void:
	print("DummyComponent: exit_water() stub called.")


## Stub transition hook for updraft air streams.
## [param _strength] Upward velocity magnitude.
## [param _top_y] Maximum height boundary.
func enter_updraft(_strength: float, _top_y: float) -> void:
	print("DummyComponent: enter_updraft() stub called.")


## Stub transition hook when exiting updraft air streams.
func exit_updraft() -> void:
	print("DummyComponent: exit_updraft() stub called.")


## Stub transition hook when grabbing a zipline.
## [param _zipline] Target zipline [Node3D].
## [param _start] World coordinates of start anchor.
## [param _end] World coordinates of end anchor.
func enter_zipline(_zipline: Node3D, _start: Vector3, _end: Vector3) -> void:
	print("DummyComponent: enter_zipline() stub called.")


## Stub transition hook when grabbing a physical rope link.
## [param _rope_node] Target [RigidBody3D] link.
func enter_rope(_rope_node: RigidBody3D) -> void:
	print("DummyComponent: enter_rope() stub called.")


## Stub notification hook when entering rain regions.
func enter_rain_volume() -> void:
	print("DummyComponent: enter_rain_volume() stub called.")


## Stub notification hook when exiting rain regions.
func exit_rain_volume() -> void:
	print("DummyComponent: exit_rain_volume() stub called.")


## Stub serialization hook returning empty mock save data.
## [return] Empty save data [Dictionary].
func get_save_data() -> Dictionary:
	print("DummyComponent: get_save_data() stub called.")
	return {}


## Stub deserialization hook restoring component state.
## [param _data] State payload [Dictionary].
func load_save_data(_data: Dictionary) -> void:
	print("DummyComponent: load_save_data() stub called.")
