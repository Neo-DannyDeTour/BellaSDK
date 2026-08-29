extends GutTest

## Variant instance for the graphics manager under test.
var graphics: Variant = null


func before_each() -> void:
	print("TestGraphicsManager: before_each() setup.")
	graphics = GraphicsManager.new()
	add_child_autofree(graphics)


func test_enable_user_mode() -> void:
	print("TestGraphicsManager: test_enable_user_mode() called.")
	graphics.enable_user_mode()

	assert_false(graphics.is_auto_optimizing, "Auto optimization should be false.")
	assert_eq(graphics._sdfgi_downgrade_level, 0, "Downgrade level should reset to 0.")


func test_enable_auto_mode() -> void:
	print("TestGraphicsManager: test_enable_auto_mode() called.")
	graphics.enable_user_mode()  # Start from known disabled state

	graphics.enable_auto_mode()

	assert_true(graphics.is_auto_optimizing, "Auto optimization should be true.")
	assert_not_null(graphics._fps_timer, "FPS timer should be initialized and assigned.")
	assert_false(graphics._fps_timer.is_stopped(), "FPS timer should be running.")
