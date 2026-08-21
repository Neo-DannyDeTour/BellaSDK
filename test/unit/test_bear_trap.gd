extends GutTest

## The bear trap instance to test.
var bear_trap: BearTrap

## A mock player node.
var mock_player: Player


## Sets up the bear trap and typed mock dependencies before each test.
func before_each() -> void:
	print("TestBearTrap: before_each() called. Setting up test environment.")

	var bear_trap_scene: PackedScene = load("res://enemies/bear_trap.tscn")
	bear_trap = bear_trap_scene.instantiate()
	add_child_autoqfree(bear_trap)

	await get_tree().process_frame

	var mock_player_script: GDScript = GDScript.new()
	mock_player_script.source_code = """
extends Player

## Tracks the last damage value applied to the mock player.
var last_damage: int = 0


## Simulates player damage.
func take_damage(amount: int) -> void:
	print("MockPlayer: take_damage() called. Applying ", amount, " damage.")
	last_damage = amount
"""
	var err: Error = mock_player_script.reload()
	assert_eq(err, OK, "MockPlayer script failed to compile.")
	mock_player = mock_player_script.new()

	var loco_script: GDScript = GDScript.new()
	loco_script.source_code = """
extends PlayerLocomotionComponent

## Tracks sprint capability flag.
var can_sprint: bool = true
"""
	loco_script.reload()
	mock_player.locomotion_component = loco_script.new()

	var menu_script: GDScript = GDScript.new()
	menu_script.source_code = """
extends SystemMenuController

## Tracks stun status flag.
var is_stunned: bool = false
"""
	menu_script.reload()
	mock_player.system_menu = menu_script.new()

	var dummy_script: GDScript = GDScript.new()
	dummy_script.source_code = """
extends Node

## Stub initialize method to satisfy Player._ready requirements.
func initialize(_p: Node) -> void:
	pass
"""
	dummy_script.reload()

	var interact_comp: Node = Node.new()
	interact_comp.set_script(dummy_script)
	mock_player.interaction_component = interact_comp

	var env_comp: Node = Node.new()
	env_comp.set_script(dummy_script)
	mock_player.environment_component = env_comp

	var stat_comp: Node = Node.new()
	stat_comp.set_script(dummy_script)
	mock_player.stats_component = stat_comp

	mock_player.add_child(mock_player.locomotion_component)
	mock_player.add_child(mock_player.system_menu)
	mock_player.add_child(interact_comp)
	mock_player.add_child(env_comp)
	mock_player.add_child(stat_comp)

	var components_node: Node = Node.new()
	components_node.name = "Components"
	mock_player.add_child(components_node)

	var health_node: HealthComponent = HealthComponent.new()
	health_node.name = "HealthComponent"
	components_node.add_child(health_node)

	add_child_autoqfree(mock_player)


## Validates initial trap state.
func test_initial_state() -> void:
	print("TestBearTrap: test_initial_state() called.")
	assert_eq(
		bear_trap.current_state, BearTrap.TrapState.OPEN, "BearTrap should start in OPEN state."
	)


## Validates snapping logic, damage application, and state flags.
func test_snap_shut() -> void:
	print("TestBearTrap: test_snap_shut() called.")
	bear_trap.snap_shut(mock_player)

	assert_eq(
		bear_trap.current_state,
		BearTrap.TrapState.CLOSED,
		"BearTrap should be CLOSED after snapping."
	)
	assert_eq(mock_player.last_damage, 150, "Player should take 150 damage.")
	assert_true(mock_player.system_menu.is_stunned, "Player should be stunned.")
	assert_false(mock_player.locomotion_component.can_sprint, "Player sprint should be disabled.")
	assert_true(bear_trap.immobilize_timer.time_left > 0, "Immobilize timer should be started.")
	assert_true(bear_trap.sprint_block_timer.time_left > 0, "Sprint block timer should be started.")


## Validates timeouts resetting player state correctly.
func test_timer_timeouts() -> void:
	print("TestBearTrap: test_timer_timeouts() called.")
	bear_trap.snap_shut(mock_player)

	bear_trap._on_immobilize_timeout()
	assert_false(
		mock_player.system_menu.is_stunned, "Player should not be stunned after immobilize timeout."
	)

	bear_trap._on_sprint_block_timeout()
	assert_true(
		mock_player.locomotion_component.can_sprint,
		"Player sprint should be enabled after sprint block timeout."
	)
	assert_null(bear_trap.trapped_player, "Trapped player reference should be cleared.")
