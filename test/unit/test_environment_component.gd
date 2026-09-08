extends GutTest

## The component being tested.
var component: PlayerEnvironmentComponent

## A mock player character body to pass into the component.
var player: CharacterBody3D


func before_each() -> void:
	print("test_environment_component: before_each() - Setup.")
	component = PlayerEnvironmentComponent.new()
	player = CharacterBody3D.new()
	add_child_autofree(component)
	add_child_autofree(player)


func test_initialize() -> void:
	print("test_environment_component: test_initialize().")
	component.initialize(player)
	assert_eq(component.player, player, "Player reference should be cached.")


func test_start_zipline_cooldown() -> void:
	print("test_environment_component: test_start_zipline_cooldown().")
	component.start_zipline_cooldown(1.5)
	assert_eq(component.zipline_cooldown, 1.5, "Cooldown duration should be applied.")


func test_enter_updraft() -> void:
	print("test_environment_component: test_enter_updraft().")
	component.enter_updraft(15.0, 50.0)
	assert_true(component.in_updraft, "Should flag as being in updraft.")
	assert_eq(component.updraft_strength, 15.0, "Updraft strength should be cached.")
	assert_eq(component.updraft_top_y, 50.0, "Updraft top Y should be cached.")


func test_exit_updraft() -> void:
	print("test_environment_component: test_exit_updraft().")
	component.enter_updraft(15.0, 50.0)
	component.exit_updraft()
	assert_false(component.in_updraft, "Should unflag updraft presence.")
	assert_eq(component.updraft_strength, 0.0, "Updraft strength should reset.")
