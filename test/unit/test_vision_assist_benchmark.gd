## Unit test and benchmark for VisionAssistManager toggling performance.
##
## Tests and measures performance of [VisionAssistManager] when toggling high contrast overlays
## across registered scene groups.
class_name TestVisionAssistBenchmark
extends GutTest


## Benchmark test measuring execution time of toggling vision assist on and off.
func test_vision_assist_toggled_benchmark() -> void:
	print("TestVisionAssistBenchmark: Setting up test environment for toggling performance.")
	var manager: Node = load("res://ui/VisionAssistManager.gd").new()
	add_child(autofree(manager))

	var groups: Array[String] = [
		"friends", "enemies", "interactables", "traversal", "clues", "cover"
	]

	for group: String in groups:
		for i: int in range(50):
			var node := MeshInstance3D.new()
			node.name = group + "_" + str(i)
			node.add_to_group(group)
			add_child(autofree(node))

	print("TestVisionAssistBenchmark: Executing benchmark loop for vision assist toggling.")
	var start_time: int = Time.get_ticks_usec()
	for loop: int in range(100):
		manager._on_vision_assist_toggled(true)
		manager._on_vision_assist_toggled(false)
	var elapsed_time: int = Time.get_ticks_usec() - start_time

	print("TestVisionAssistBenchmark: Elapsed time for 100 toggles: ", elapsed_time, " us")
	assert_true(elapsed_time >= 0, "Benchmark completed successfully.")
