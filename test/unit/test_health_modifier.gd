@tool
## Unit test suite for verifying the behavior of the health modifier system.
class_name TestHealthModifier
extends GutTest

## Preloaded script reference for the health modifier under test.
const MODIFIER_SCRIPT: GDScript = preload("res://shared/health_modifier.gd")

## Instance of the health modifier under test.
var modifier: Node = null
## Dummy physics body to represent a character.
var dummy_body: Node3D = null
## Child health component attached to the dummy body.
var health_comp: HealthComponent = null


## Mock modifier simulating overlapping bodies in the test tree.
class MockModifier:
	extends "res://shared/health_modifier.gd"

	## Simulated collection of bodies inside the modifier area.
	var mock_bodies: Array[Node3D] = []

	## Returns the simulated list of overlapping physics bodies.
	func _get_target_bodies() -> Array[Node3D]:
		print("MockModifier: _get_target_bodies() returning mocked bodies.")
		return mock_bodies


## Initializes test fixtures and setup node hierarchy before each test run.
func before_each() -> void:
	print("TestHealthModifier: before_each() setup.")

	@warning_ignore("unsafe_method_access")
	modifier = MODIFIER_SCRIPT.new()
	add_child_autofree(modifier)
	modifier.set("tick_interval", 0.1)

	dummy_body = Node3D.new()
	dummy_body.name = "DummyBody"

	var components_node: Node = Node.new()
	components_node.name = "Components"
	dummy_body.add_child(components_node)

	health_comp = HealthComponent.new()
	health_comp.name = "HealthComponent"
	health_comp.max_health = 100
	components_node.add_child(health_comp)

	add_child_autofree(dummy_body)
	health_comp._ready()


## Verifies that negative modifier values reduce the target's current health.
func test_modifier_applies_damage() -> void:
	print("TestHealthModifier: test_modifier_applies_damage() called.")

	var mocked_modifier: MockModifier = MockModifier.new()
	add_child_autofree(mocked_modifier)
	mocked_modifier.mock_bodies = [dummy_body]
	mocked_modifier.modify_amount = -20

	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should decrease by 20 from modifier.")


## Verifies that positive modifier values restore the target's current health.
func test_modifier_applies_healing() -> void:
	print("TestHealthModifier: test_modifier_applies_healing() called.")
	health_comp.take_damage(50)

	var mocked_modifier: MockModifier = MockModifier.new()
	add_child_autofree(mocked_modifier)
	mocked_modifier.mock_bodies = [dummy_body]
	mocked_modifier.modify_amount = 30

	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should increase by 30 from modifier.")
