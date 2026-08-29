## Unit tests for the [DevMetricsPanel] script.
extends GutTest

## The instance of the DevMetricsPanel for testing.
var _metrics: DevMetricsPanel


## Setup logic that runs before each individual test.
func before_each() -> void:
	print("Setting up DevMetricsPanel test environment...")
	_metrics = load("res://core/dev_metrics.gd").new()
	# Inject mock RichTextLabel to satisfy @onready requirement when tested.
	var label: RichTextLabel = RichTextLabel.new()
	label.name = "MetricsLabel"
	_metrics.add_child(label)
	# Normally we'd add it to the tree, but we can test logic without it for some cases.
	# We will add it to ensure lifecycle runs if needed.
	add_child_autofree(_metrics)


## Teardown logic that runs after each individual test.
func after_each() -> void:
	print("Tearing down DevMetricsPanel test environment...")


## Tests the initial configuration and default values of the metrics panel.
func test_initial_state() -> void:
	print("Executing test_initial_state...")
	assert_true(_metrics.is_enabled, "Metrics panel should be enabled by default.")
	assert_eq(_metrics.HISTORY_NUM_FRAMES, 150, "History frames constant should be 150.")
	assert_eq(_metrics._total_history.size(), 0, "Total history should be initially empty.")
	assert_eq(_metrics._cpu_history.size(), 0, "CPU history should be initially empty.")
	assert_eq(_metrics._gpu_history.size(), 0, "GPU history should be initially empty.")
