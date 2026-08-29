extends GutTest

const StateGroundScript = preload("res://player/state_ground.gd")

## The ground state under test.
var state_ground: Variant

## A mock player node.
var mock_player: CharacterBody3D

## A mock state machine.
var mock_state_machine: Node


## Sets up player dependencies and state machine wiring.
func before_each() -> void:
	print("TestStateGround: before_each() called. Setting up test environment.")

	var mock_player_script: GDScript = GDScript.new()
	mock_player_script.source_code = """
extends CharacterBody3D


var locomotion_component: Node
var environment_component: Node
var interaction_component: Node
var stats_component: Node
var is_on_floor: bool = true
var is_on_wall: bool = false
"""
	mock_player_script.reload()
	mock_player = mock_player_script.new()

	var loco_script: GDScript = GDScript.new()
	loco_script.source_code = """
extends Node

var _direction: Vector3 = Vector3.ZERO
var sprint_active: bool = false
var crouching: bool = false
var can_sprint: bool = true
var walking_speed: float = 5.0
var sprinting_speed: float = 8.0
var crouching_speed: float = 3.0
var ice_lerp_speed: float = 1.0
var default_lerp_speed: float = 10.0
var on_ice: bool = false
var on_sand: bool = false
var on_safe_landing: bool = false
var gravity: float = 9.8

func get_direction() -> Vector3:
	return _direction

func set_direction(d: Vector3) -> void:
	_direction = d
"""
	loco_script.reload()
	var loco_comp: Node = loco_script.new()
	loco_comp.name = "LocomotionComponent"

	mock_player.locomotion_component = loco_comp
	mock_player.add_child(loco_comp)

	var dummy_script: GDScript = GDScript.new()
	dummy_script.source_code = """
extends Node

func initialize(_p: Node) -> void:
	pass
"""
	dummy_script.reload()

	var env_comp: Node = Node.new()
	env_comp.name = "EnvironmentComponent"
	env_comp.set_script(dummy_script)
	mock_player.environment_component = env_comp
	mock_player.add_child(env_comp)

	var interact_comp: Node = Node.new()
	interact_comp.name = "InteractionComponent"
	interact_comp.set_script(dummy_script)
	mock_player.interaction_component = interact_comp
	mock_player.add_child(interact_comp)

	var stat_comp: Node = Node.new()
	stat_comp.name = "StatsComponent"
	stat_comp.set_script(dummy_script)
	mock_player.stats_component = stat_comp
	mock_player.add_child(stat_comp)

	var components_node: Node = Node.new()
	components_node.name = "Components"
	mock_player.add_child(components_node)

	var health_node: Node = load("res://shared/health_component.gd").new()
	health_node.name = "HealthComponent"
	components_node.add_child(health_node)

	add_child_autoqfree(mock_player)

	mock_state_machine = Node.new()
	var sm_script: GDScript = GDScript.new()
	sm_script.source_code = """
extends Node

var last_transition: String = ""
var last_msg: Dictionary = {}

func transition_to(target_state_name: String, msg: Dictionary = {}) -> void:
	print("MockStateMachine: Transitioning to ", target_state_name)
	last_transition = target_state_name
	last_msg = msg
"""
	sm_script.reload()
	mock_state_machine.set_script(sm_script)
	add_child_autoqfree(mock_state_machine)

	state_ground = StateGroundScript.new()
	state_ground.player = mock_player
	state_ground.state_machine = mock_state_machine
	add_child_autoqfree(state_ground)


## Verifies enter resets velocities and movement speed.
func test_enter() -> void:
	print("TestStateGround: test_enter() called.")
	mock_player.set("velocity", Vector3(0, -10.0, 0))
	state_ground.current_speed = 5.0

	state_ground.enter()

	assert_eq(mock_player.get("velocity").y, 0.0, "Y velocity should be reset on enter.")
	assert_eq(state_ground.current_speed, 0.0, "Current speed should be reset on enter.")


## Verifies buffered jump input executes immediate transition to Air.
func test_jump_buffered() -> void:
	print("TestStateGround: test_jump_buffered() called.")
	state_ground.enter({"jump_buffered": true})

	assert_eq(mock_state_machine.last_transition, "Air", "Should transition to Air state.")
	assert_eq(
		mock_player.get("velocity").y,
		state_ground.JUMP_VELOCITY,
		"Y velocity should be set to JUMP_VELOCITY."
	)
