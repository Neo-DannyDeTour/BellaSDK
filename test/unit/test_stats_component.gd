extends GutTest

## The player stats component to test.
var stats_component: PlayerStatsComponent

## A mock player node.
var mock_player: CharacterBody3D

## A mock health component.
var mock_health_component: Node


func before_each() -> void:
	print("TestStatsComponent: before_each() called. Setting up test environment.")

	mock_player = CharacterBody3D.new()
	add_child_autoqfree(mock_player)

	# Stub player properties enough to pass the type check conceptually if needed
	# Note: PlayerStatsComponent expects a `Player` type, but in GDScript, duck typing often works
	# for unit testing unless strictly enforced by static type checking on assignment.
	# We will create a dummy script to bypass static typing issues if needed, but since it's
	# just passed to `initialize`, passing the node itself might be enough if type casts allow it
	# or we can cast it if we just use a generic node.

	# Create a dummy script for mock_health_component
	mock_health_component = Node.new()
	var script: GDScript = GDScript.new()
	script.source_code = """
extends Node
signal health_changed(new_health: int)
signal died

var current_health: int = 100

func take_damage(amount: int) -> void:
	current_health -= amount
	health_changed.emit(current_health)
	if current_health <= 0:
		died.emit()
"""
	script.reload()
	mock_health_component.set_script(script)
	add_child_autoqfree(mock_health_component)

	stats_component = PlayerStatsComponent.new()
	stats_component.health_component = mock_health_component
	add_child_autoqfree(stats_component)


func test_initialize() -> void:
	print("TestStatsComponent: test_initialize() called.")
	# We pass mock_player as is. Unsafe assignment may warn, but we bypass by not
	# strictly casting here or just testing logic. For strict static typing,
	# we might need to load the actual Player class.

	# Workaround for strict typing: load actual player script but don't add to tree fully if not needed
	var PlayerClass: GDScript = load("res://player/player.gd")
	var real_mock_player: CharacterBody3D = PlayerClass.new()
	add_child_autoqfree(real_mock_player)

	stats_component.initialize(real_mock_player)
	assert_eq(stats_component.player, real_mock_player, "Player reference should be cached.")

	assert_true(
		mock_health_component.health_changed.is_connected(stats_component._on_health_changed),
		"health_changed signal should be connected."
	)
	assert_true(
		mock_health_component.died.is_connected(stats_component._on_player_died),
		"died signal should be connected."
	)


func test_get_save_data() -> void:
	print("TestStatsComponent: test_get_save_data() called.")
	mock_health_component.current_health = 75

	var data: Dictionary = stats_component.get_save_data()

	assert_true(data.has("health"), "Save data should contain 'health' key.")
	assert_eq(data["health"], 75, "Save data should match current health.")


func test_load_save_data() -> void:
	print("TestStatsComponent: test_load_save_data() called.")
	var data: Dictionary = {"health": 42}

	stats_component.load_save_data(data)

	assert_eq(mock_health_component.current_health, 42, "Health should be updated from save data.")
