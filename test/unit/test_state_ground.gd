## Unit test suite validating StateGround entry, velocities, and buffered jumping.
class_name TestStateGround
extends GutTest

## The ground state under test.
var state_ground: StateGround = null
## A mock player node.
var mock_player: Player = null
## A mock state machine.
var mock_state_machine: Node = null


## Sets up player dependencies and state machine wiring.
func before_each() -> void:
	print("TestStateGround: before_each() called. Setting up test environment.")

	var mock_player_script: GDScript = GDScript.new()
	mock_player_script.source_code = """
extends Player

## Velocity storage for physics calculations.
var simulated_velocity: Vector3 = Vector3.ZERO
"""
	mock_player_script.reload()
	var raw_player: Variant = mock_player_script.new()
	if raw_player is Player:
		mock_player = raw_player

	var loco_script: GDScript = GDScript.new()
	loco_script.source_code = """
extends PlayerLocomotionComponent

## Movement direction vector.
var _direction: Vector3 = Vector3.ZERO


## Returns current movement direction vector.
func get_direction() -> Vector3:
	return _direction


## Sets current movement direction vector.
func set_direction(d: Vector3) -> void:
	_direction = d
"""
	loco_script.reload()
	var raw_loco: Variant = loco_script.new()
	var loco_comp: PlayerLocomotionComponent = null
	if raw_loco is PlayerLocomotionComponent:
		loco_comp = raw_loco
		loco_comp.name = "LocomotionComponent"
		loco_comp.sprint_active = false
		loco_comp.crouching = false
		loco_comp.can_sprint = true
		loco_comp.walking_speed = 5.0
		loco_comp.sprinting_speed = 8.0
		loco_comp.crouching_speed = 3.0
		loco_comp.ice_lerp_speed = 1.0
		loco_comp.default_lerp_speed = 10.0
		loco_comp.on_ice = false
		loco_comp.on_sand = false
		loco_comp.on_safe_landing = false
		loco_comp.gravity = 9.8
		mock_player.locomotion_component = loco_comp
		mock_player.add_child(loco_comp)

	var env_script: GDScript = GDScript.new()
	env_script.source_code = """
extends PlayerEnvironmentComponent
"""
	env_script.reload()
	var env_raw: Variant = env_script.new()
	if env_raw is PlayerEnvironmentComponent:
		var env_comp: PlayerEnvironmentComponent = env_raw
		env_comp.name = "EnvironmentComponent"
		mock_player.environment_component = env_comp
		mock_player.add_child(env_comp)

	var interact_script: GDScript = GDScript.new()
	interact_script.source_code = """
extends PlayerInteractionComponent
"""
	interact_script.reload()
	var interact_raw: Variant = interact_script.new()
	if interact_raw is PlayerInteractionComponent:
		var interact_comp: PlayerInteractionComponent = interact_raw
		interact_comp.name = "InteractionComponent"
		mock_player.interaction_component = interact_comp
		mock_player.add_child(interact_comp)

	var stats_script: GDScript = GDScript.new()
	stats_script.source_code = """
extends PlayerStatsComponent
"""
	stats_script.reload()
	var stats_raw: Variant = stats_script.new()
	if stats_raw is PlayerStatsComponent:
		var stat_comp: PlayerStatsComponent = stats_raw
		stat_comp.name = "StatsComponent"
		mock_player.stats_component = stat_comp
		mock_player.add_child(stat_comp)

	var components_node: Node = Node.new()
	components_node.name = "Components"
	mock_player.add_child(components_node)

	var health_script: GDScript = load("res://shared/health_component.gd") as GDScript
	if health_script != null:
		var raw_health: Variant = health_script.new()
		if raw_health is Node:
			var health_node: Node = raw_health
			health_node.name = "HealthComponent"
			components_node.add_child(health_node)

	add_child_autoqfree(mock_player)

	mock_state_machine = StateMachine.new()
	var sm_script: GDScript = GDScript.new()
	sm_script.source_code = """
extends StateMachine

## Tracks the last target state transition.
var last_transition: String = ""

## Tracks the last transition message payload.
var last_msg: Dictionary = {}


## Simulates state transition call.
func change_state(target_state_name: StringName, msg: Dictionary = {}) -> bool:
	print("MockStateMachine: Transitioning to ", target_state_name)
	last_transition = target_state_name
	last_msg = msg
	return true
"""
	sm_script.reload()
	mock_state_machine.set_script(sm_script)
	add_child_autoqfree(mock_state_machine)

	state_ground = StateGround.new()
	state_ground.player = mock_player
	state_ground.state_machine = mock_state_machine
	add_child_autoqfree(state_ground)


## Verifies enter resets velocities and movement speed.
func test_enter() -> void:
	print("TestStateGround: test_enter() called.")
	mock_player.velocity.y = -10.0
	state_ground.current_speed = 5.0

	state_ground.enter()

	assert_eq(mock_player.velocity.y, 0.0, "Y velocity should be reset on enter.")
	assert_eq(state_ground.current_speed, 0.0, "Current speed should be reset on enter.")


## Verifies buffered jump input executes immediate transition to Air.
func test_jump_buffered() -> void:
	print("TestStateGround: test_jump_buffered() called.")
	state_ground.enter({"jump_buffered": true})

	var transition_name: String = str(mock_state_machine.get("last_transition"))
	assert_eq(transition_name, "Air", "Should transition to Air state.")
	assert_eq(
		mock_player.velocity.y,
		state_ground.JUMP_VELOCITY,
		"Y velocity should be set to JUMP_VELOCITY."
	)
