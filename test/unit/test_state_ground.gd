extends GutTest

## The ground state to test.
var state_ground: StateGround

## A mock player node.
var mock_player: Player

## A mock state machine.
var mock_state_machine: Node


func before_each() -> void:
	print("TestStateGround: before_each() called. Setting up test environment.")

	# 1. Instantiate a mock script that strictly extends Player
	var mock_player_script: GDScript = GDScript.new()
	mock_player_script.source_code = "extends Player\n"
	mock_player_script.reload()
	mock_player = mock_player_script.new()

	# 2. Mock dependencies inside player (adding dummy initialize() methods)
	var loco_component: Node = Node.new()
	loco_component.name = "LocomotionComponent"
	var loco_script: GDScript = GDScript.new()
	loco_script.source_code = """
extends Node
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

var standing_collision: Node = Node.new()
var crouching_collision: Node = Node.new()
var crouch_cast_check: Node = Node.new()
var stair_controller: Node = Node.new()

func initialize(_p: Node) -> void: pass

func _ready() -> void:
	add_child(standing_collision)
	add_child(crouching_collision)
	add_child(crouch_cast_check)
	add_child(stair_controller)

	var stair_script: GDScript = GDScript.new()
	stair_script.source_code = \"\"\"
extends Node
var time_since_step_up: float = 1.0

@warning_ignore("unused_private_class_variable")
var _snapped_to_stairs_last_frame: bool = false

func snap_up_stairs_check(_d: Vector3, _s: float) -> void: pass
func snap_down_to_stairs_check() -> void: pass
func track_floor_state() -> void: pass
\"\"\"
	stair_script.reload()
	stair_controller.set_script(stair_script)

	var cast_script: GDScript = GDScript.new()
	cast_script.source_code = "extends Node\\nfunc is_colliding() -> bool: return false"
	cast_script.reload()
	crouch_cast_check.set_script(cast_script)

var _dir: Vector3 = Vector3.ZERO
func get_direction() -> Vector3: return _dir
func set_direction(d: Vector3) -> void: _dir = d
"""
	loco_script.reload()
	loco_component.set_script(loco_script)
	mock_player.locomotion_component = loco_component
	mock_player.add_child(loco_component)

	var env_component: Node = Node.new()
	env_component.name = "EnvironmentComponent"
	var env_script: GDScript = GDScript.new()
	env_script.source_code = """
extends Node
var current_water_node: Node = null
var vault_controller: Node = Node.new()

func initialize(_p: Node) -> void: pass

func _ready() -> void:
	add_child(vault_controller)
	var vault_script: GDScript = GDScript.new()
	vault_script.source_code = (
		"extends Node\\nvar is_vaulting: bool = false\\nfunc try_vault(_c: bool) -> bool: return false"
	)
	vault_script.reload()
	vault_controller.set_script(vault_script)
"""
	env_script.reload()
	env_component.set_script(env_script)
	mock_player.environment_component = env_component
	mock_player.add_child(env_component)

	var interact_component: Node = Node.new()
	interact_component.name = "InteractionComponent"
	var interact_script: GDScript = GDScript.new()
	interact_script.source_code = """
extends Node
var is_heavy_lifting: bool = false
var held_item: Node = null
var interaction_scanner: Node = Node.new()

func initialize(_p: Node) -> void: pass
"""
	interact_script.reload()
	interact_component.set_script(interact_script)
	mock_player.interaction_component = interact_component
	mock_player.add_child(interact_component)

	# 3. Create missing StatsComponent to prevent 'initialize in base Nil' crash
	var stats_component: Node = Node.new()
	stats_component.name = "StatsComponent"
	var stats_script: GDScript = GDScript.new()
	stats_script.source_code = "extends Node\nfunc initialize(_p: Node) -> void: pass"
	stats_script.reload()
	stats_component.set_script(stats_script)
	mock_player.stats_component = stats_component
	mock_player.add_child(stats_component)

	# 4. Construct dummy hierarchy to prevent @onready 'Node not found' log errors.
	var components_node: Node = Node.new()
	components_node.name = "Components"
	mock_player.add_child(components_node)

	var health_node: HealthComponent = HealthComponent.new()
	health_node.name = "HealthComponent"
	components_node.add_child(health_node)

	# 5. Safely add to tree AFTER all dependencies are attached
	add_child_autoqfree(mock_player)

	# Stub GlobalSettings if not present
	if not Engine.has_singleton("GlobalSettings"):
		pass

	mock_state_machine = Node.new()
	var sm_script: GDScript = GDScript.new()
	sm_script.source_code = """
extends Node
var last_transition: String = ""
var last_msg: Dictionary = {}
func transition_to(target_state_name: String, msg: Dictionary = {}) -> void:
	last_transition = target_state_name
	last_msg = msg
"""
	sm_script.reload()
	mock_state_machine.set_script(sm_script)
	add_child_autoqfree(mock_state_machine)

	state_ground = StateGround.new()
	state_ground.player = mock_player
	state_ground.state_machine = mock_state_machine
	add_child_autoqfree(state_ground)


func test_enter() -> void:
	print("TestStateGround: test_enter() called.")
	mock_player.velocity.y = -10.0
	state_ground.current_speed = 5.0

	state_ground.enter()

	assert_eq(mock_player.velocity.y, 0.0, "Y velocity should be reset on enter.")
	assert_eq(state_ground.current_speed, 0.0, "Current speed should be reset on enter.")


func test_jump_buffered() -> void:
	print("TestStateGround: test_jump_buffered() called.")
	state_ground.enter({"jump_buffered": true})

	assert_eq(mock_state_machine.last_transition, "Air", "Should transition to Air state.")
	assert_eq(
		mock_player.velocity.y,
		state_ground.JUMP_VELOCITY,
		"Y velocity should be set to JUMP_VELOCITY."
	)
