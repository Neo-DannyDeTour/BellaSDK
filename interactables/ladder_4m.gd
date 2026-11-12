@tool
## Climbable 4m ladder prop combining [StaticBody3D] collision and optional [Ladder] trigger.
class_name Ladder4M
extends Node3D

## Enables or disables climbing trigger so the ladder can act as a static ground prop.
@export var climbable: bool = true:
	set(value):
		climbable = value
		if is_inside_tree():
			_sync_climbable_state()

## Child [Ladder] trigger volume positioned clear of the solid collision box.
@onready var _ladder_trigger: Ladder = get_node_or_null("LadderTrigger") as Ladder


## Disables per-frame processing and applies initial [member climbable] state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_ladder_trigger), "Ladder4M: Missing LadderTrigger child.")
	_sync_climbable_state()


## Synchronizes [member _ladder_trigger] monitoring and visibility with [member climbable].
func _sync_climbable_state() -> void:
	if not is_instance_valid(_ladder_trigger):
		return

	_ladder_trigger.monitoring = climbable
	_ladder_trigger.monitorable = climbable
	_ladder_trigger.process_mode = (
		Node.PROCESS_MODE_INHERIT if climbable else Node.PROCESS_MODE_DISABLED
	)
	if Engine.is_editor_hint():
		_ladder_trigger.visible = climbable
