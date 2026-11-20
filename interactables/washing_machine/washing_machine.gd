## Interactive top-loader washing machine with tweened hinged lid.
##
## Attach to root [StaticBody3D]. Toggles lid rotation via [method interact]
## or [method interact_with] with zero per-frame overhead.
class_name WashingMachine
extends StaticBody3D

## Emitted when the washing machine door starts toggling open or closed.
@warning_ignore("unused_signal")
signal door_toggled(is_open: bool)

## Hinge rotation target in radians when door is fully open.
const OPEN_ANGLE_RAD: float = deg_to_rad(-85.0)
## Hinge rotation target in radians when door is closed.
const CLOSED_ANGLE_RAD: float = 0.0
## Render layer bitmask for Layer 3 (Interactive).
const RENDER_LAYER_INTERACTIVE: int = 1 << (CollisionLayers.RENDER_LAYER_INTERACTIVE_IDX - 1)

## Pivot [AnimatableBody3D] rotated around local X-axis for the lid.
@export var door_pivot: AnimatableBody3D = null
## Duration of the lid swing tween in seconds.
@export var open_duration: float = 0.35

## Current open/closed state of the washing machine lid.
var is_open: bool = false

## Active lid rotation [Tween] reference.
var _door_tween: Tween = null

## Cached reference to the cabinet body [MeshInstance3D].
@onready var _body_mesh: MeshInstance3D = _resolve_body_mesh()
## Cached reference to the hinged lid [MeshInstance3D].
@onready var _door_mesh: MeshInstance3D = _resolve_door_mesh()


## Validates required nodes, assigns render/physics layers, and disables frame loops.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(is_instance_valid(door_pivot), "WashingMachine: door_pivot must be assigned.")
	assert(is_instance_valid(_body_mesh), "WashingMachine: WasherBody mesh missing.")
	assert(is_instance_valid(_door_mesh), "WashingMachine: WasherDoor mesh missing.")

	if _door_mesh.get_parent() != door_pivot:
		_door_mesh.reparent(door_pivot, true)

	collision_layer = CollisionLayers.MASK_ENVIRONMENT
	collision_mask = CollisionLayers.MASK_NONE
	door_pivot.collision_layer = CollisionLayers.MASK_INTERACTIVE
	door_pivot.collision_mask = CollisionLayers.MASK_NONE

	_body_mesh.layers = RENDER_LAYER_INTERACTIVE
	_door_mesh.layers = RENDER_LAYER_INTERACTIVE


## Receives direct player interaction dispatched from [InteractComponent].
func interact_with(_character: CharacterBody3D) -> void:
	interact()


## Toggles the door between open and closed states using a [Tween].
func interact() -> void:
	is_open = not is_open
	var target_pitch: float = OPEN_ANGLE_RAD if is_open else CLOSED_ANGLE_RAD
	print("WashingMachine: door state -> ", "OPEN" if is_open else "CLOSED")

	_door_tween = Utilities.reset_tween(self, _door_tween)
	_door_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if is_open else Tween.EASE_IN)
	_door_tween.tween_property(door_pivot, "rotation:x", target_pitch, open_duration)
	door_toggled.emit(is_open)


## Resolves the cabinet [MeshInstance3D] from direct child or instanced GLB model.
func _resolve_body_mesh() -> MeshInstance3D:
	var direct: MeshInstance3D = get_node_or_null("WasherBody") as MeshInstance3D
	if is_instance_valid(direct):
		return direct
	return get_node_or_null("Model/WasherBody") as MeshInstance3D


## Resolves the lid [MeshInstance3D] from DoorPivot or instanced GLB model.
func _resolve_door_mesh() -> MeshInstance3D:
	if is_instance_valid(door_pivot):
		var direct: MeshInstance3D = door_pivot.get_node_or_null("WasherDoor") as MeshInstance3D
		if is_instance_valid(direct):
			return direct
	return get_node_or_null("Model/WasherBody/WasherDoor") as MeshInstance3D
