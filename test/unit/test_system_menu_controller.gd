class_name TestSystemMenuController
extends GutTest

## The system menu controller under test.
var controller: Node

## A mock camera used for testing fullbright mode.
var mock_camera: Camera3D

## A mock player body used for testing noclip.
var mock_player: CharacterBody3D


func before_each() -> void:
	print("TestSystemMenuController: before_each() setup starting.")
	var script: Script = load("res://player/system_menu_controller.gd")
	controller = Node.new()
	controller.set_script(script)
	controller.set("menu_scene", null)

	mock_camera = Camera3D.new()
	var initial_env: Environment = Environment.new()
	mock_camera.environment = initial_env
	controller.set("camera", mock_camera)

	mock_player = CharacterBody3D.new()
	controller.set("player_body", mock_player)

	add_child_autofree(mock_camera)
	add_child_autofree(mock_player)

	# Setting process mode manually to bypass an implicit _ready call when added to tree
	controller.process_mode = Node.PROCESS_MODE_ALWAYS
	controller.call("_setup_fullbright_environment")

	add_child_autofree(controller)
	print("TestSystemMenuController: before_each() setup completed.")


func test_toggle_pause() -> void:
	print("TestSystemMenuController: test_toggle_pause() running.")
	var initial_pause: bool = controller.get("is_paused")
	assert_false(initial_pause, "Controller should start unpaused.")

	controller.call("toggle_pause")
	var paused_state: bool = controller.get("is_paused")
	assert_true(paused_state, "Controller should be paused after toggle_pause().")
	assert_true(get_tree().paused, "Scene tree should be paused.")

	controller.call("toggle_pause")
	var unpaused_state: bool = controller.get("is_paused")
	assert_false(unpaused_state, "Controller should be unpaused after second toggle.")
	assert_false(get_tree().paused, "Scene tree should be unpaused.")


func test_toggle_noclip() -> void:
	print("TestSystemMenuController: test_toggle_noclip() running.")
	controller.set("is_debug_allowed", true)

	var initial_flying: bool = controller.get("flying")
	assert_false(initial_flying, "Controller should start not flying.")

	controller.call("toggle_noclip")
	var flying_state: bool = controller.get("flying")
	assert_true(flying_state, "Controller should be flying after toggle_noclip().")

	controller.call("toggle_noclip")
	var not_flying_state: bool = controller.get("flying")
	assert_false(not_flying_state, "Controller should not be flying after second toggle.")


func test_fullbright_toggled() -> void:
	print("TestSystemMenuController: test_fullbright_toggled() running.")
	var initial_env: Environment = mock_camera.environment

	controller.call("_on_fullbright_toggled", true)
	var env_after_true: Environment = mock_camera.environment
	assert_ne(
		env_after_true,
		initial_env,
		"Camera environment should change after fullbright toggled true."
	)
	assert_eq(
		env_after_true,
		controller.get("fullbright_env"),
		"Camera environment should be fullbright_env."
	)

	controller.call("_on_fullbright_toggled", false)
	var env_after_false: Environment = mock_camera.environment
	assert_eq(
		env_after_false, initial_env, "Camera environment should revert to initial environment."
	)
