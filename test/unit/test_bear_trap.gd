extends GutTest

## The bear trap instance to test.
var bear_trap: BearTrap

## A mock player node.
var mock_player: CharacterBody3D


func before_each() -> void:
	print("TestBearTrap: before_each() called. Setting up test environment.")

	# Instance the scene
	var bear_trap_scene: PackedScene = load("res://enemies/bear_trap.tscn")
	bear_trap = bear_trap_scene.instantiate()
	add_child_autoqfree(bear_trap)

	# Allow node to be ready
	await get_tree().process_frame

	var PlayerClass: GDScript = load("res://player/player.gd")
	mock_player = PlayerClass.new()
	add_child_autoqfree(mock_player)

	var loco_component: Node = Node.new()
	var loco_script: GDScript = GDScript.new()
	loco_script.source_code = "extends Node\nvar can_sprint: bool = true"
	loco_script.reload()
	loco_component.set_script(loco_script)
	mock_player.locomotion_component = loco_component
	mock_player.add_child(loco_component)

	var system_menu: Node = Node.new()
	var sys_script: GDScript = GDScript.new()
	sys_script.source_code = "extends Node\nvar is_stunned: bool = false"
	sys_script.reload()
	system_menu.set_script(sys_script)
	mock_player.system_menu = system_menu
	mock_player.add_child(system_menu)

	# Mock take_damage method dynamically
	var player_script: Script = mock_player.get_script()
	var mock_player_script: GDScript = GDScript.new()
	mock_player_script.source_code = """
extends CharacterBody3D
var locomotion_component
var system_menu
var last_damage: int = 0
func take_damage(amount: int) -> void:
	last_damage = amount
"""
	mock_player_script.reload()
	mock_player.set_script(mock_player_script)
	# Re-assign variables
	mock_player.locomotion_component = loco_component
	mock_player.system_menu = system_menu


func test_initial_state() -> void:
	print("TestBearTrap: test_initial_state() called.")
	assert_eq(
		bear_trap.current_state, BearTrap.TrapState.OPEN, "BearTrap should start in OPEN state."
	)


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
