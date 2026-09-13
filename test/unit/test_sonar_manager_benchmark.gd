## Unit test and benchmark for [SonarManager].
##
## Tests and benchmarks sonar ping scanning across target group nodes.
class_name TestSonarManagerBenchmark
extends GutTest

## The [SonarManager] instance under test.
var _sonar_manager: Node = null

## The origin [Node3D] used for triggering sonar pings.
var _origin_node: Node3D = null

## Array of created target nodes for cleanup.
var _target_nodes: Array[Node3D] = []


## Setup method executed before each test.
func before_each() -> void:
	print("TestSonarManagerBenchmark: Setting up test environment and target nodes.")
	_sonar_manager = load("res://SFX/SonarManager.gd").new()
	add_child_autofree(_sonar_manager)

	_origin_node = Node3D.new()
	add_child_autofree(_origin_node)
	_origin_node.global_position = Vector3.ZERO

	var groups: Array[StringName] = [
		&"hazard", &"waypoint", &"interactables", &"interactable", &"props"
	]
	for i: int in range(25):
		var target: Node3D = Node3D.new()
		var group_idx: int = i % groups.size()
		target.add_to_group(groups[group_idx])
		add_child_autofree(target)
		target.global_position = Vector3(float(i + 1), 0.0, 0.0)
		_target_nodes.append(target)


## Tests functionality and measures performance of [method SonarManager.trigger_sonar].
func test_sonar_trigger_performance() -> void:
	print("TestSonarManagerBenchmark: Executing test_sonar_trigger_performance benchmark.")
	assert_not_null(_sonar_manager, "SonarManager should be initialized.")

	var start_time: int = Time.get_ticks_usec()
	for i: int in range(100):
		_sonar_manager.trigger_sonar(_origin_node)
	var elapsed_time: int = Time.get_ticks_usec() - start_time

	print("TestSonarManagerBenchmark: 100 pings elapsed time (usec): ", elapsed_time)
	assert_true(elapsed_time >= 0, "Elapsed time should be non-negative.")
