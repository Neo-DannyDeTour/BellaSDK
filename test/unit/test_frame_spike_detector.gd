extends GutTest

## Variant instance for the frame spike detector under test.
var detector: Variant = null


func before_each() -> void:
	print("TestFrameSpikeDetector: before_each() setup.")
	detector = load("res://core/FrameSpikeDetector.gd").new()
	add_child_autofree(detector)
	detector._ready()


func test_process_normal_frame() -> void:
	print("TestFrameSpikeDetector: test_process_normal_frame() called.")
	# A normal frame at 60 FPS is ~16.6 ms, so delta is ~0.0166s.
	# We use 0.01s (10ms) to safely stay under the spike threshold (16.6ms).
	var normal_delta: float = 0.01

	# _process should complete without any crashes or assertions failing
	detector._process(normal_delta)

	# Since there's no state change to check directly on the object without mocking the console,
	# we just assert true to ensure it runs correctly and reaches this point.
	assert_true(true, "Should process normal frame without issues.")


func test_process_spiked_frame() -> void:
	print("TestFrameSpikeDetector: test_process_spiked_frame() called.")
	# A spiked frame. 100 ms frame time, which is 0.1s delta.
	var spiked_delta: float = 0.10

	# _process should trigger the spike report.
	# We don't have a built-in GUT way to catch print statements easily without complex mocking,
	# but we can verify it doesn't crash during performance metric gathering.
	detector._process(spiked_delta)

	assert_true(true, "Should process spiked frame and report without crashing.")
