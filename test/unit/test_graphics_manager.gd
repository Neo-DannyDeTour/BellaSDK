## Unit tests for [GraphicsManager] verifying mode changes and timers.
class_name TestGraphicsManager
extends GutTest

const GRAPHICS_MANAGER_SCRIPT: GDScript = preload("res://core/graphics_manager.gd")

## The [Node] autoload instance under test.
var graphics: Node = null


## Sets up clean test instance and resets relevant global settings.
func before_each() -> void:
	print("TestGraphicsManager: before_each() setup.")
	GlobalSettings.save_setting("Settings", "use_auto_optimizer", false)
	GlobalSettings.save_setting("Settings", "optimized_downgrade_level", 0)

	@warning_ignore("unsafe_method_access")
	graphics = GRAPHICS_MANAGER_SCRIPT.new()
	# Prevent auto-fast-forwarding on integrated GPUs during unit tests
	graphics.set("_is_low_end", false)
	add_child_autofree(graphics)


## Verifies that user mode resets optimization state and downgrade level.
func test_enable_user_mode() -> void:
	print("TestGraphicsManager: test_enable_user_mode() called.")
	graphics.call("enable_user_mode")

	@warning_ignore("unsafe_call_argument")
	assert_false(graphics.get("is_auto_optimizing"), "Auto optimization should be false.")
	@warning_ignore("unsafe_call_argument")
	assert_eq(graphics.get("_sdfgi_downgrade_level"), 0, "Downgrade level should reset to 0.")


## Verifies that enabling auto mode starts the FPS monitoring timer.
func test_enable_auto_mode() -> void:
	print("TestGraphicsManager: test_enable_auto_mode() called.")
	graphics.call("enable_user_mode")
	graphics.call("enable_auto_mode")

	@warning_ignore("unsafe_call_argument")
	assert_true(graphics.get("is_auto_optimizing"), "Auto optimization should be true.")

	var timer_variant: Variant = graphics.get("_fps_timer")
	@warning_ignore("unsafe_call_argument")
	assert_not_null(timer_variant, "FPS timer should be assigned.")

	if timer_variant is Timer:
		var fps_timer: Timer = timer_variant
		assert_false(fps_timer.is_stopped(), "FPS timer should be running.")
