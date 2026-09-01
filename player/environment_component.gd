## Manages player interactions with environmental volumes and structural systems.
##
## Tracks cooldowns and state transitions for mechanics like ladders, ziplines,
## water volumes, updrafts, and environmental VFX triggers.
class_name PlayerEnvironmentComponent
extends Node

@export_category("Node References")
## Reference to the visual effects manager for screen overlays and rain.
@export var vfx_manager: Node
## Reference to the main player state machine.
@export var state_machine: Node
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
## Maintained list of active waterfalls (unused directly by core player).
var active_waterfalls: Array[Area3D] = []
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


## Initializes the component by caching the player reference and binding events.
## [param p_player] The parent [CharacterBody3D] node.
func initialize(p_player: CharacterBody3D) -> void:
	print("EnvironmentComponent: initialize() called. Caching player reference.")
	player = p_player
	_connect_waterfall_group()


## Frame execution managing cooldown degradation and dynamic VFX updates.
## [param delta] The frame time delta in seconds.
func process_environment_physics(delta: float) -> void:
	if zipline_cooldown > 0.0:
		zipline_cooldown -= delta
	if monkey_bar_cooldown > 0.0:
		monkey_bar_cooldown -= delta

	if ladder_cooldown > 0.0:
		ladder_cooldown -= delta
		if ladder_cooldown <= 0.0:
			last_ladder = null

	if is_instance_valid(vfx_manager) and is_instance_valid(player.get_node_or_null("Head")):
		var head: Node3D = player.get_node("Head") as Node3D
		vfx_manager.call("process_vfx", delta, head.rotation.x)


## Begins the cooldown period for zipline re-attachment.
## [param duration] How long in seconds before re-attachment is allowed.
func start_zipline_cooldown(duration: float = 0.5) -> void:
	print("EnvironmentComponent: start_zipline_cooldown() called. Duration: ", duration)
	zipline_cooldown = duration


## Triggers state machine transition to the ladder state if conditions are met.
## [param ladder_node] The ladder object being interacted with.
func enter_ladder(ladder_node: Node3D) -> void:
	print("EnvironmentComponent: enter_ladder() called.")
	if is_instance_valid(vault_controller) and vault_controller.get("is_vaulting"):
		return

	if ladder_node == last_ladder and ladder_cooldown > 0.0:
		return

	if is_instance_valid(state_machine):
		state_machine.call("transition_to", "Ladders", {"ladder_node": ladder_node})


## Releases the player from the ladder and returns them to an air state.
## [param _ladder_node] The ladder object being released.
func exit_ladder(_ladder_node: Node3D) -> void:
	print("EnvironmentComponent: exit_ladder() called.")
	if is_instance_valid(state_machine) and state_machine.get("state").name == "Ladders":
		state_machine.call("transition_to", "Air")


## Processes entry into a swimmable water volume, initiating swim state.
## [param water_volume] The water area node entered.
func enter_water(water_volume: Node3D) -> void:
	print("EnvironmentComponent: enter_water() called.")
	current_water_node = water_volume

	if is_instance_valid(vault_controller) and vault_controller.get("is_vaulting"):
		return

	if (
		is_instance_valid(state_machine)
		and state_machine.get("state").name not in ["Vault", "Zipline", "Rope"]
	):
		state_machine.call("transition_to", "Swim")


## Processes exit from a swimmable water volume, restoring air state if applicable.
## [param water_volume] The water area node exited.
func exit_water(water_volume: Node3D) -> void:
	print("EnvironmentComponent: exit_water() called.")
	if current_water_node == water_volume:
		current_water_node = null

		if is_instance_valid(vault_controller) and vault_controller.get("is_vaulting"):
			return

		if is_instance_valid(state_machine) and state_machine.get("state").name == "Swim":
			state_machine.call("transition_to", "Air")


## Applies updraft lift characteristics when entering a wind volume.
## [param strength] The upward velocity magnitude of the wind.
## [param top_y] The vertical coordinate where the draft ceases applying lift.
func enter_updraft(strength: float, top_y: float) -> void:
	print("EnvironmentComponent: enter_updraft() called. Strength: ", strength)
	in_updraft = true
	updraft_strength = strength
	updraft_top_y = top_y

	if is_instance_valid(state_machine) and state_machine.get("state").name == "Ground":
		state_machine.call("transition_to", "Air")


## Removes updraft lift characteristics when exiting a wind volume.
func exit_updraft() -> void:
	print("EnvironmentComponent: exit_updraft() called.")
	in_updraft = false
	updraft_strength = 0.0


## Dynamically locates and connects signals to all nodes in the 'waterfall_area' group.
func _connect_waterfall_group() -> void:
	print("EnvironmentComponent: Scanning for 'waterfall_area' group...")
	var connected_count: int = 0
	for node: Node in get_tree().get_nodes_in_group("waterfall_area"):
		if node is Area3D:
			var area: Area3D = node as Area3D
			if not area.body_entered.is_connected(_on_waterfall_entered):
				area.body_entered.connect(_on_waterfall_entered.bind(area))
			if not area.body_exited.is_connected(_on_waterfall_exited):
				area.body_exited.connect(_on_waterfall_exited.bind(area))
			connected_count += 1
	print("EnvironmentComponent: Bound signals to ", connected_count, " waterfalls.")


## Tracks entry into waterfall areas and triggers VFX screenshader logic.
## [param body] The physics body that entered the volume.
## [param area] The waterfall volume triggered.
func _on_waterfall_entered(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	print("EnvironmentComponent: Entered waterfall: ", area.name)
	if not overlapping_waterfall_areas.has(area):
		overlapping_waterfall_areas.append(area)
	if overlapping_waterfall_areas.size() == 1 and is_instance_valid(vfx_manager):
		vfx_manager.call("enter_waterfall")


## Tracks exit from waterfall areas and disables VFX screenshader logic.
## [param body] The physics body that exited the volume.
## [param area] The waterfall volume triggered.
func _on_waterfall_exited(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	print("EnvironmentComponent: Exited waterfall: ", area.name)
	overlapping_waterfall_areas.erase(area)
	if overlapping_waterfall_areas.is_empty() and is_instance_valid(vfx_manager):
		vfx_manager.call("exit_waterfall")


## Directs the state machine to transition to the Zipline state.
## [param zipline_node] The zipline node being traversed.
## [param start_pos] World coordinate of the zipline origin.
## [param end_pos] World coordinate of the zipline destination.
func enter_zipline(zipline_node: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	print("EnvironmentComponent: enter_zipline() called. Triggering Zipline state.")
	if is_instance_valid(state_machine):
		state_machine.call(
			"transition_to",
			"Zipline",
			{"zipline_node": zipline_node, "start_pos": start_pos, "end_pos": end_pos}
		)


## Directs the state machine to transition to the Rope state.
## [param rope_node] The physics body segment of the rope being grabbed.
func enter_rope(rope_node: RigidBody3D) -> void:
	print("EnvironmentComponent: enter_rope() called. Triggering Rope state.")
	if is_instance_valid(state_machine):
		state_machine.call("transition_to", "Rope", {"rope_node": rope_node})


## Notifies the VFX manager that the player has stepped into a rain zone.
func enter_rain_volume() -> void:
	print("EnvironmentComponent: enter_rain_volume() called.")
	if is_instance_valid(vfx_manager) and vfx_manager.has_method("set_rain_volume"):
		vfx_manager.call("set_rain_volume", true)


## Notifies the VFX manager that the player has stepped out of a rain zone.
func exit_rain_volume() -> void:
	print("EnvironmentComponent: exit_rain_volume() called.")
	if is_instance_valid(vfx_manager) and vfx_manager.has_method("set_rain_volume"):
		vfx_manager.call("set_rain_volume", false)
