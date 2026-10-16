## Manages player interactions with environmental volumes and structural systems.
class_name PlayerEnvironmentComponent
extends Node

## Group identifier for waterfall trigger volumes.
const GROUP_WATERFALL: StringName = &"waterfall_area"

## State identifier for ladder climbing.
const STATE_LADDER: StringName = &"Ladder"

## State identifier for airborne movement.
const STATE_AIR: StringName = &"Air"

## State identifier for grounded movement.
const STATE_GROUND: StringName = &"Ground"

## State identifier for swimming.
const STATE_SWIM: StringName = &"Swim"

## State identifier for ledge vaulting.
const STATE_VAULT: StringName = &"Vault"

## State identifier for zipline traversal.
const STATE_ZIPLINE: StringName = &"Zipline"

## State identifier for rope swinging.
const STATE_ROPE: StringName = &"Rope"

## Method identifier for per-frame VFX updates.
const METHOD_PROCESS_VFX: StringName = &"process_vfx"

## Method identifier for entering waterfall overlay.
const METHOD_ENTER_WATERFALL: StringName = &"enter_waterfall"

## Method identifier for exiting waterfall overlay.
const METHOD_EXIT_WATERFALL: StringName = &"exit_waterfall"

## Method identifier for toggling rain volume overlay.
const METHOD_SET_RAIN: StringName = &"set_rain_volume"

@export_category("Node References")

## Reference to the visual effects manager for screen overlays and rain.
@export var vfx_manager: Node

## Reference to the main player state machine.
@export var state_machine: StateMachine

## Reference to the controller handling climbing and vaulting logic.
@export var vault_controller: Node

## The parent player body executing these environment interactions.
var player: CharacterBody3D

## Cooldown timer preventing immediate re-attachment to ziplines.
var zipline_cooldown: float = 0.0

## Cooldown timer preventing immediate re-attachment to monkey bars.
var monkey_bar_cooldown: float = 0.0

## Cooldown timer preventing immediate re-attachment to ladders.
var ladder_cooldown: float = 0.0

## Reference to an active monkey bar zone the player is traversing.
var available_monkey_bar: Node3D = null

## List of currently overlapping waterfall trigger areas.
var overlapping_waterfall_areas: Array[Area3D] = []

## Flag tracking if the player is within a wind updraft volume.
var in_updraft: bool = false

## Lift force magnitude applied by the current updraft volume.
var updraft_strength: float = 0.0

## Maximum vertical threshold bounds of the current updraft volume.
var updraft_top_y: float = 0.0

## Reference to the currently occupied water volume node.
var current_water_node: Node3D = null

## Reference to the last ladder node attached to, for cooldown management.
var last_ladder: Node3D = null

## Cached head [Node3D] reference for zero-lookup pitch queries.
var _head: Node3D = null

## Cached list of bound waterfall [Area3D] nodes for clean exit disconnection.
var _bound_waterfalls: Array[Area3D] = []


## Disables per-frame processing callbacks on initialization.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)


## Disconnects waterfall area signals when removed from the scene tree.
func _exit_tree() -> void:
	for area: Area3D in _bound_waterfalls:
		if is_instance_valid(area):
			if area.body_entered.is_connected(_on_waterfall_entered):
				area.body_entered.disconnect(_on_waterfall_entered)
			if area.body_exited.is_connected(_on_waterfall_exited):
				area.body_exited.disconnect(_on_waterfall_exited)
	_bound_waterfalls.clear()


## Initializes the component by caching the player reference and binding events.
func initialize(p_player: CharacterBody3D) -> void:
	print("EnvironmentComponent: initialize() called. Caching player reference.")
	player = p_player
	assert(is_instance_valid(player), "EnvironmentComponent: Invalid player reference.")
	_head = player.get_node_or_null("Head") as Node3D
	_connect_waterfall_group()


## Frame execution managing cooldown degradation and dynamic VFX updates.
func process_environment_physics(delta: float) -> void:
	if zipline_cooldown > 0.0:
		zipline_cooldown -= delta
	if monkey_bar_cooldown > 0.0:
		monkey_bar_cooldown -= delta

	if ladder_cooldown > 0.0:
		ladder_cooldown -= delta
		if ladder_cooldown <= 0.0:
			last_ladder = null

	if is_instance_valid(vfx_manager) and is_instance_valid(_head):
		vfx_manager.call(METHOD_PROCESS_VFX, delta, _head.rotation.x)


## Begins the cooldown period for zipline re-attachment.
func start_zipline_cooldown(duration: float = 0.5) -> void:
	print("EnvironmentComponent: start_zipline_cooldown() called. Duration: ", duration)
	zipline_cooldown = duration


## Triggers state machine transition to the ladder state if conditions are met.
func enter_ladder(ladder_node: Node3D) -> void:
	print("EnvironmentComponent: enter_ladder() called.")
	if is_instance_valid(vault_controller) and vault_controller.get(&"is_vaulting") == true:
		return

	if ladder_node == last_ladder and ladder_cooldown > 0.0:
		return

	if is_instance_valid(state_machine):
		state_machine.transition_to(STATE_LADDER, {"ladder_node": ladder_node})


## Releases the player from the ladder and returns them to an air state.
func exit_ladder(_ladder_node: Node3D) -> void:
	print("EnvironmentComponent: exit_ladder() called.")
	if is_instance_valid(state_machine) and state_machine.is_in_state(STATE_LADDER):
		state_machine.transition_to(STATE_AIR)


## Processes entry into a swimmable water volume, initiating swim state.
func enter_water(water_volume: Node3D) -> void:
	print("EnvironmentComponent: enter_water() called.")
	current_water_node = water_volume
	Events.swim_surface_toggled.emit(true)

	if is_instance_valid(vault_controller) and vault_controller.get(&"is_vaulting") == true:
		return

	if is_instance_valid(state_machine):
		var blocked_by_state: bool = (
			state_machine.is_in_state(STATE_VAULT)
			or state_machine.is_in_state(STATE_ZIPLINE)
			or state_machine.is_in_state(STATE_ROPE)
		)
		if not blocked_by_state:
			state_machine.transition_to(STATE_SWIM)


## Processes exit from a swimmable water volume, restoring air state if applicable.
func exit_water(water_volume: Node3D) -> void:
	print("EnvironmentComponent: exit_water() called.")
	if current_water_node == water_volume:
		current_water_node = null
		Events.swim_surface_toggled.emit(false)

		if is_instance_valid(vault_controller) and vault_controller.get(&"is_vaulting") == true:
			return

		if is_instance_valid(state_machine) and state_machine.is_in_state(STATE_SWIM):
			state_machine.transition_to(STATE_AIR)


## Applies updraft lift characteristics when entering a wind volume.
func enter_updraft(strength: float, top_y: float) -> void:
	print("EnvironmentComponent: enter_updraft() called. Strength: ", strength)
	in_updraft = true
	updraft_strength = strength
	updraft_top_y = top_y

	if is_instance_valid(state_machine) and state_machine.is_in_state(STATE_GROUND):
		state_machine.transition_to(STATE_AIR)


## Removes updraft lift characteristics when exiting a wind volume.
func exit_updraft() -> void:
	print("EnvironmentComponent: exit_updraft() called.")
	in_updraft = false
	updraft_strength = 0.0


## Directs the state machine to transition to the Zipline state.
func enter_zipline(zipline_node: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	print("EnvironmentComponent: enter_zipline() called. Triggering Zipline state.")
	if is_instance_valid(state_machine):
		state_machine.transition_to(
			STATE_ZIPLINE,
			{"zipline_node": zipline_node, "start_pos": start_pos, "end_pos": end_pos}
		)


## Directs the state machine to transition to the Rope state.
func enter_rope(rope_node: RigidBody3D) -> void:
	print("EnvironmentComponent: enter_rope() called. Triggering Rope state.")
	if is_instance_valid(state_machine):
		state_machine.transition_to(STATE_ROPE, {"rope_node": rope_node})


## Notifies the VFX manager that the player has stepped into a rain zone.
func enter_rain_volume() -> void:
	print("EnvironmentComponent: enter_rain_volume() called.")
	if is_instance_valid(vfx_manager) and vfx_manager.has_method(METHOD_SET_RAIN):
		vfx_manager.call(METHOD_SET_RAIN, true)


## Notifies the VFX manager that the player has stepped out of a rain zone.
func exit_rain_volume() -> void:
	print("EnvironmentComponent: exit_rain_volume() called.")
	if is_instance_valid(vfx_manager) and vfx_manager.has_method(METHOD_SET_RAIN):
		vfx_manager.call(METHOD_SET_RAIN, false)


## Dynamically locates and connects signals to all nodes in the 'waterfall_area' group.
func _connect_waterfall_group() -> void:
	print("EnvironmentComponent: Scanning for 'waterfall_area' group...")
	var connected_count: int = 0
	for node: Node in get_tree().get_nodes_in_group(GROUP_WATERFALL):
		var area: Area3D = node as Area3D
		if is_instance_valid(area):
			if not area.body_entered.is_connected(_on_waterfall_entered):
				area.body_entered.connect(_on_waterfall_entered.bind(area))
			if not area.body_exited.is_connected(_on_waterfall_exited):
				area.body_exited.connect(_on_waterfall_exited.bind(area))
			_bound_waterfalls.append(area)
			connected_count += 1
	print("EnvironmentComponent: Bound signals to ", connected_count, " waterfalls.")


## Tracks entry into waterfall areas and triggers VFX screenshader logic.
func _on_waterfall_entered(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	print("EnvironmentComponent: Entered waterfall: ", area.name)
	if not overlapping_waterfall_areas.has(area):
		overlapping_waterfall_areas.append(area)
	if overlapping_waterfall_areas.size() == 1 and is_instance_valid(vfx_manager):
		vfx_manager.call(METHOD_ENTER_WATERFALL)


## Tracks exit from waterfall areas and disables VFX screenshader logic.
func _on_waterfall_exited(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	print("EnvironmentComponent: Exited waterfall: ", area.name)
	overlapping_waterfall_areas.erase(area)
	if overlapping_waterfall_areas.is_empty() and is_instance_valid(vfx_manager):
		vfx_manager.call(METHOD_EXIT_WATERFALL)
