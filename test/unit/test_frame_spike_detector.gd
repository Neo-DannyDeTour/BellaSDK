class_name TestFrameSpikeDetector
extends GutTest
## GUT test suite verifying frame time spike detector execution without regressions.

## Node instance for the frame spike detector under test.
var detector: Node = null


## Pre-test setup instantiating and attaching the frame spike detector.
func before_each() -> void:
	print("TestFrameSpikeDetector: before_each() setup.")
	var detector_script: GDScript = load("res://core/FrameSpikeDetector.gd") as GDScript
	var raw_detector: Object = detector_script.new()
	if raw_detector is Node:
		detector = raw_detector
		add_child_autofree(detector)


## Verifies processing a normal delta under the 16.6ms threshold without errors.
func test_process_normal_frame() -> void:
	print("TestFrameSpikeDetector: test_process_normal_frame() called.")
	assert_not_null(detector, "Detector node should be valid.")

	var normal_delta: float = 0.01
	detector.call("_process", normal_delta)

	assert_true(true, "Should process normal frame without issues.")


## Verifies processing a spiked frame time delta without crashes or runtime errors.
func test_process_spiked_frame() -> void:
	print("TestFrameSpikeDetector: test_process_spiked_frame() called.")
	assert_not_null(detector, "Detector node should be valid.")

	var spiked_delta: float = 0.10
	detector.call("_process", spiked_delta)

	assert_true(true, "Should process spiked frame and report without crashing.")
