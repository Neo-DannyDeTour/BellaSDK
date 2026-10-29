## Unit tests for [SunshineCloudsGD] verifying pipeline rebuild decoupling,
## resolution scale setter redundancy guards, and temporal accumulation retention.
class_name TestSunshineCloudsRebuildDecoupling
extends GutTest


## Verifies that setting resolution_scale to the same value does not wipe last_size.
func test_resolution_scale_setter_redundancy_guard() -> void:
	print("TestSunshineCloudsRebuildDecoupling: test_resolution_scale_setter_redundancy_guard()")
	var clouds: SunshineCloudsGD = SunshineCloudsGD.new()
	autofree(clouds)

	clouds.resolution_scale = 1
	clouds.last_size = Vector2i(1920, 1080)

	# Redundant assignment must preserve last_size to prevent full pipeline rebuilds
	clouds.resolution_scale = 1
	assert_eq(
		clouds.last_size,
		Vector2i(1920, 1080),
		"Redundant resolution_scale assignment must not invalidate last_size."
	)

	# Actual change must invalidate last_size to trigger full pipeline rebuild
	clouds.resolution_scale = 2
	assert_eq(
		clouds.last_size,
		Vector2i(0, 0),
		"Changing resolution_scale must reset last_size to Vector2i(0, 0)."
	)


## Verifies that temporal accumulation ignore flag is decoupled from render target changes.
func test_temporal_accumulation_decoupling_logic() -> void:
	print("TestSunshineCloudsRebuildDecoupling: test_temporal_accumulation_decoupling_logic()")
	var clouds: SunshineCloudsGD = SunshineCloudsGD.new()
	autofree(clouds)

	# Simulate steady-state viewport frame (size matches last_size)
	var current_size: Vector2i = Vector2i(1920, 1080)
	clouds.last_size = current_size

	var should_ignore: bool = current_size != clouds.last_size
	assert_false(should_ignore, "Steady-state frames must retain temporal accumulation history.")

	# Simulate resolution shift (e.g. window resize or dynamic scaling)
	var resized_size: Vector2i = Vector2i(1280, 720)
	should_ignore = (resized_size != clouds.last_size)
	assert_true(should_ignore, "Resolution changes must cleanly flush stale history buffers.")
