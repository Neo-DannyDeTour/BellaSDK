extends "res://addons/gut/test.gd"
## Unit tests for the PowerComponent class.
class_name TestPowerComponent

## The PowerComponent instance being tested.
var _power: PowerComponent


func before_each() -> void:
	print("TestPowerComponent: Setting up test environment.")
	_power = PowerComponent.new()
	var parent: Node3D = Node3D.new()
	parent.name = "TestParent"
	parent.add_child(_power)
	add_child(parent)
	_power.required_power = 2


func after_each() -> void:
	print("TestPowerComponent: Tearing down test environment.")
	if is_instance_valid(_power):
		var p: Node = _power.get_parent()
		if p:
			p.queue_free()

	_power = null


func test_add_power_meets_threshold() -> void:
	print("TestPowerComponent: test_add_power_meets_threshold")
	watch_signals(_power)

	_power.add_power()
	assert_eq(_power.current_power, 1, "Power should be 1 after one add_power.")
	assert_false(_power.is_powered, "Should not be powered yet.")
	assert_signal_not_emitted(_power, "powered_on")

	_power.add_power()
	assert_eq(_power.current_power, 2, "Power should be 2 after second add_power.")
	assert_true(_power.is_powered, "Should be powered now.")
	assert_signal_emitted(_power, "powered_on")


func test_remove_power_below_threshold() -> void:
	print("TestPowerComponent: test_remove_power_below_threshold")
	_power.add_power()
	_power.add_power()
	watch_signals(_power)

	_power.remove_power()
	assert_eq(_power.current_power, 1, "Power should be 1 after remove_power.")
	assert_false(_power.is_powered, "Should lose power.")
	assert_signal_emitted(_power, "powered_off")


func test_power_does_not_go_below_zero() -> void:
	print("TestPowerComponent: test_power_does_not_go_below_zero")
	_power.remove_power()
	assert_eq(_power.current_power, 0, "Power should not go below zero.")
