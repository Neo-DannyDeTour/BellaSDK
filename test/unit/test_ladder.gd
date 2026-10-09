## Mock environment component tracking ladder interactions for test assertions.
#class_name MockEnvironmentComponent
extends PlayerEnvironmentComponent

## Last ladder passed into enter_ladder.
var last_entered_ladder: Node3D = null
## Last ladder passed into exit_ladder.
var last_exited_ladder: Node3D = null


## Intercepts ladder entry to record the node for unit tests.
## [param ladder_node] The ladder instance entered.
func enter_ladder(ladder_node: Node3D) -> void:
	print("MockEnvironmentComponent: enter_ladder() intercepted.")
	if ladder_node == last_ladder and ladder_cooldown > 0.0:
		return
	last_entered_ladder = ladder_node
	super.enter_ladder(ladder_node)


## Intercepts ladder exit to record the node for unit tests.
## [param ladder_node] The ladder instance exited.
func exit_ladder(ladder_node: Node3D) -> void:
	print("MockEnvironmentComponent: exit_ladder() intercepted.")
	last_exited_ladder = ladder_node
	super.exit_ladder(ladder_node)
