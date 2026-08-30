## Unit tests for the PowerComponent class.
class_name TestPoweredObject
extends GutTest

## The loaded script reference for [PowerComponent].
const POWER_COMP_SCRIPT: GDScript = preload("res://shared/powered_object.gd")

## The instance of the [PowerComponent] being tested.
var power_comp: Variant = null
## Dummy parent node for the power component.
var parent_node: Node = null


## Sets up the test environment before each test.
func before_each() -> void:
	print("TestPoweredObject: before_each() setup.")
	parent_node = Node.new()
	parent_node.name = "DummyParent"
	add_child_autofree(parent_node)

	power_comp = POWER_COMP_SCRIPT.new()
	power_comp.required_power = 2
	parent_node.add_child(power_comp)


## Verifies adding power increments the current power count and evaluates state.
func test_add_power() -> void:
	print("TestPoweredObject: test_add_power() called.")
	watch_signals(power_comp)

	power_comp.add_power()

	assert_eq(power_comp.current_power, 1, "Power should increase by 1.")
	assert_false(power_comp.is_powered, "Should not be powered yet.")
	assert_signal_not_emitted(power_comp, "powered_on")

	power_comp.add_power()

	assert_eq(power_comp.current_power, 2, "Power should increase to 2.")
	assert_true(power_comp.is_powered, "Should now be powered.")
	assert_signal_emitted(power_comp, "powered_on")


## Verifies removing power decrements current power and emits signal when dropping below threshold.
func test_remove_power() -> void:
	print("TestPoweredObject: test_remove_power() called.")
	power_comp.add_power()
	power_comp.add_power()

	watch_signals(power_comp)

	power_comp.remove_power()

	assert_eq(power_comp.current_power, 1, "Power should decrease by 1.")
	assert_false(power_comp.is_powered, "Should lose power.")
	assert_signal_emitted(power_comp, "powered_off")


## Verifies power doesn't drop below 0 when removing power repeatedly.
func test_remove_power_floor() -> void:
	print("TestPoweredObject: test_remove_power_floor() called.")

	power_comp.remove_power()
	power_comp.remove_power()

	assert_eq(power_comp.current_power, 0, "Power should not drop below 0.")
