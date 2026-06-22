class_name PlayerEnvironmentComponent
extends Node

@export_category("Node References")
@export var vfx_manager: Node
@export var state_machine: Node
@export var vault_controller: Node

var player: Player
var zipline_cooldown: float = 0.0
var monkey_bar_cooldown: float = 0.0
var ladder_cooldown: float = 0.0
var available_monkey_bar: Node3D = null
var overlapping_waterfall_areas: Array[Area3D] = []
var active_waterfalls: Array[Area3D] = []
var in_updraft: bool = false
var updraft_strength: float = 0.0
var updraft_top_y: float = 0.0
var current_water_node: Node3D = null
var last_ladder: Node3D = null

func initialize(p_player: Player) -> void:
	print("EnvironmentComponent: initialize() called. Caching player reference.")
	player = p_player
	_connect_waterfall_group()

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
		var head: Node3D = player.get_node("Head")
		vfx_manager.process_vfx(delta, head.rotation.x)

func enter_ladder(ladder_node: Node3D) -> void:
	print("EnvironmentComponent: enter_ladder() called.")
	if is_instance_valid(vault_controller) and vault_controller.get("is_vaulting"):
		return
		
	if ladder_node == last_ladder and ladder_cooldown > 0.0:
		return
		
	if is_instance_valid(state_machine):
		state_machine.transition_to("Ladders", {"ladder_node": ladder_node})

func exit_ladder(_ladder_node: Node3D) -> void:
	print("EnvironmentComponent: exit_ladder() called.")
	if is_instance_valid(state_machine) and state_machine.get("state").name == "Ladders":
		state_machine.transition_to("Air")

func enter_water(water_volume: Node3D) -> void:
	print("EnvironmentComponent: enter_water() called.")
	current_water_node = water_volume

	if is_instance_valid(vault_controller) and vault_controller.get("is_vaulting"):
		return

	if is_instance_valid(state_machine) and state_machine.get("state").name not in ["Vault", "Zipline", "Rope"]:
		state_machine.transition_to("Swim")

func exit_water(water_volume: Node3D) -> void:
	print("EnvironmentComponent: exit_water() called.")
	if current_water_node == water_volume:
		current_water_node = null

		if is_instance_valid(vault_controller) and vault_controller.get("is_vaulting"):
			return

		if is_instance_valid(state_machine) and state_machine.get("state").name == "Swim":
			state_machine.transition_to("Air")

func enter_updraft(strength: float, top_y: float) -> void:
	print("EnvironmentComponent: enter_updraft() called. Strength: ", strength)
	in_updraft = true
	updraft_strength = strength
	updraft_top_y = top_y

	if is_instance_valid(state_machine) and state_machine.get("state").name == "Ground":
		state_machine.transition_to("Air")

func exit_updraft() -> void:
	print("EnvironmentComponent: exit_updraft() called.")
	in_updraft = false
	updraft_strength = 0.0

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


func _on_waterfall_entered(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	print("EnvironmentComponent: Entered waterfall: ", area.name)
	if not overlapping_waterfall_areas.has(area):
		overlapping_waterfall_areas.append(area)
	if overlapping_waterfall_areas.size() == 1 and is_instance_valid(vfx_manager):
		vfx_manager.enter_waterfall()


func _on_waterfall_exited(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	print("EnvironmentComponent: Exited waterfall: ", area.name)
	overlapping_waterfall_areas.erase(area)
	if overlapping_waterfall_areas.is_empty() and is_instance_valid(vfx_manager):
		vfx_manager.exit_waterfall()


func enter_zipline(zipline_node: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	print("EnvironmentComponent: enter_zipline() called. Triggering Zipline state.")
	if is_instance_valid(state_machine):
		state_machine.transition_to("Zipline", {
			"zipline_node": zipline_node,
			"start_pos": start_pos,
			"end_pos": end_pos
		})


func enter_rope(rope_node: RigidBody3D) -> void:
	print("EnvironmentComponent: enter_rope() called. Triggering Rope state.")
	if is_instance_valid(state_machine):
		state_machine.transition_to("Rope", {"rope_node": rope_node})


func enter_rain_volume() -> void:
	print("EnvironmentComponent: enter_rain_volume() called.")
	if is_instance_valid(vfx_manager) and vfx_manager.has_method("set_rain_volume"):
		vfx_manager.set_rain_volume(true)


func exit_rain_volume() -> void:
	print("EnvironmentComponent: exit_rain_volume() called.")
	if is_instance_valid(vfx_manager) and vfx_manager.has_method("set_rain_volume"):
		vfx_manager.set_rain_volume(false)
