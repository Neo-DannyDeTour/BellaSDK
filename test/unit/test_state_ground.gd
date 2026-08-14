extends GutTest

## The ground state to test.
var state_ground: StateGround

## A mock player node.
var mock_player: CharacterBody3D

## A mock state machine.
var mock_state_machine: Node


func before_each() -> void:
	print("TestStateGround: before_each() called. Setting up test environment.")

	var PlayerClass: GDScript = load("res://player/player.gd")
	mock_player = PlayerClass.new()
	add_child_autoqfree(mock_player)

	# Mock dependencies inside player
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

func _ready() -> void:
	add_child(standing_collision)
	add_child(crouching_collision)
	add_child(crouch_cast_check)
	add_child(stair_controller)

	var stair_script: GDScript = GDScript.new()
	stair_script.source_code = \"\"\"
extends Node
var time_since_step_up: float = 1.0
var _snapped_to_stairs_last_frame: bool = false
func snap_up_stairs_check(d: Vector3, s: float) -> void: pass
func snap_down_to_stairs_check() -> void: pass
func track_floor_state() -> void: pass
\"\"\"
	stair_script.reload()
	stair_controller.set_script(stair_script)

	var cast_script: GDScript = GDScript.new()
	cast_script.source_code = "extends Node\nfunc is_colliding() -> bool: return false"
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

func _ready() -> void:
	add_child(vault_controller)
	var vault_script: GDScript = GDScript.new()
	vault_script.source_code = (
		"extends Node\nvar is_vaulting: bool = false\nfunc try_vault(c: bool) -> bool: return false"
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
"""
	interact_script.reload()
	interact_component.set_script(interact_script)
	mock_player.interaction_component = interact_component
	mock_player.add_child(interact_component)

	# Stub GlobalSettings if not present
	if not Engine.has_singleton("GlobalSettings"):
		# In a real run, this might be present. For this test, we can inject a mock if needed,
		# but state_ground.gd calls GlobalSettings.get_setting directly.
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
