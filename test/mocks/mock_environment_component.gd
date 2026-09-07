## Test mock for PlayerEnvironmentComponent tracking interaction triggers and cooldowns.
class_name MockEnvironmentComponent
extends DummyComponent

## Tracks the last ladder node passed into [method enter_ladder].
var last_entered_ladder: Node3D = null

## Tracks the last ladder node passed into [method exit_ladder].
var last_exited_ladder: Node3D = null

## The remaining cooldown before a ladder can be remounted.
var ladder_cooldown: float = 0.0

## Reference to the previous ladder mounted.
var last_ladder: Node3D = null


## Records ladder mount invocations and tracks entered target.
## [param ladder_node] The ladder [Node3D] instance entered.
func enter_ladder(ladder_node: Node3D) -> void:
	print("MockEnvironmentComponent: enter_ladder() called.")
	if ladder_node == last_ladder and ladder_cooldown > 0.0:
		return
	last_entered_ladder = ladder_node


## Records ladder dismount invocations and tracks exited target.
## [param ladder_node] The ladder [Node3D] instance exited.
func exit_ladder(ladder_node: Node3D) -> void:
	print("MockEnvironmentComponent: exit_ladder() called.")
	last_exited_ladder = ladder_node
