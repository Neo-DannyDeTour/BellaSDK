extends GutTest

## Variant instance for the graphics manager under test.
var graphics: Variant = null


func before_each() -> void:
	print("TestGraphicsManager: before_each() setup.")
	graphics = load("res://core/graphics_manager.gd").new()
	add_child_autofree(graphics)
	graphics._ready()


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


func test_run_benchmark_for_60fps_initial_state() -> void:
	print("TestGraphicsManager: test_run_benchmark_for_60fps_initial_state() called.")
	# We can test the initial flags set when the coroutine starts.
	# We won't await the full routine as it takes several seconds and depends on actual framerate,
	# but we can verify it sets is_benchmarking true immediately.

	# Since run_benchmark_for_60fps runs await, it returns a coroutine.
	# We can just check the immediate side effects.
	graphics.run_benchmark_for_60fps()

	assert_true(graphics.is_benchmarking, "Should be flagged as benchmarking.")

	# Cleanup benchmark flag so it doesn't break other potential tests
	graphics.is_benchmarking = false
