## Unit tests for [GraphicsManager] verifying mode changes and timers.
class_name TestGraphicsManager
extends GutTest

## The [GraphicsManager] instance under test.
var graphics: Node = null


## Sets up a clean test instance and resets relevant global settings.
func before_each() -> void:
	print("TestGraphicsManager: before_each() setup.")
	GlobalSettings.save_setting("Settings", "use_auto_optimizer", false)
	GlobalSettings.save_setting("Settings", "optimized_downgrade_level", 0)

	graphics = load("res://core/graphics_manager.gd").new()
	# Prevent auto-fast-forwarding to max downgrade on integrated GPUs during unit tests
	graphics._is_low_end = false
	add_child_autofree(graphics)


## Verifies that user mode resets optimization state and downgrade level.
func test_enable_user_mode() -> void:
	print("TestGraphicsManager: test_enable_user_mode() called.")
	graphics.enable_user_mode()

	assert_false(graphics.is_auto_optimizing, "Auto optimization should be false.")
	assert_eq(graphics._sdfgi_downgrade_level, 0, "Downgrade level should reset to 0.")


## Verifies that enabling auto mode starts the FPS monitoring timer.
func test_enable_auto_mode() -> void:
	print("TestGraphicsManager: test_enable_auto_mode() called.")
	graphics.enable_user_mode()

	graphics.enable_auto_mode()

	assert_true(graphics.is_auto_optimizing, "Auto optimization should be true.")
	assert_not_null(graphics._fps_timer, "FPS timer should be initialized and assigned.")
	assert_false(graphics._fps_timer.is_stopped(), "FPS timer should be running.")
