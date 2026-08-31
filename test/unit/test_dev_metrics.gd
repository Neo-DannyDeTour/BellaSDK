extends GutTest

## The dev metrics panel instance being tested.
var _dev_metrics: DevMetricsPanel


func before_each() -> void:
	print("TestDevMetricsPanel: Setting up test environment.")
	_dev_metrics = DevMetricsPanel.new()
	# Simulate adding RichTextLabel child to avoid null reference on _ready
	var label: RichTextLabel = RichTextLabel.new()
	label.name = "MetricsLabel"
	_dev_metrics.add_child(label)


func after_each() -> void:
	print("TestDevMetricsPanel: Tearing down test environment.")
	if is_instance_valid(_dev_metrics):
		_dev_metrics.queue_free()


func test_initialization() -> void:
	print("TestDevMetricsPanel: Testing initialization.")
	# we just add it to the scene so it triggers _ready()
	add_child_autofree(_dev_metrics)

	# Verify hardware info was cached
	var hardware_str: String = _dev_metrics.get("_hardware_info_str")
	assert_ne(hardware_str, "", "Hardware info string should be cached after ready.")

	var static_str: String = _dev_metrics.get("_settings_info_static_str")
	assert_ne(static_str, "", "Static settings info string should be cached after ready.")


func test_frametime_history() -> void:
	print("TestDevMetricsPanel: Testing frametime history limits.")

	# Manually push items into the history array to test limits
	# It shouldn't exceed HISTORY_NUM_FRAMES
	var num_frames: int = _dev_metrics.HISTORY_NUM_FRAMES

	# add one more than the limit
	for i in range(num_frames + 1):
		_dev_metrics._total_history.push_back(0.016)
		_dev_metrics._cpu_history.push_back(0.008)
		_dev_metrics._gpu_history.push_back(0.008)

	# this is the method that's supposed to trim the arrays
	_dev_metrics._update_frametime_history()

	# Since we added 1 over the limit, it should have been popped back down to the limit
	# + the 1 we just added during the update
	var total_size: int = _dev_metrics._total_history.size()
	assert_eq(total_size, num_frames + 1, "Total history should maintain limit size after push.")
	var cpu_size: int = _dev_metrics._cpu_history.size()
	assert_eq(cpu_size, num_frames + 1, "CPU history should maintain limit size after push.")
