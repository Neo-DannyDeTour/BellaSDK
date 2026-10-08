## Unit tests for health component verifying damage, healing, and scaling.
class_name TestHealthComponent
extends GutTest

const HEALTH_SCRIPT: GDScript = preload("res://shared/health_component.gd")

## The component instance under test.
var health_comp: Node = null


## Sets up a clean test instance and initializes health pool values.
func before_each() -> void:
	print("TestHealthComponent: before_each() setup.")
	@warning_ignore("unsafe_method_access")
	health_comp = HEALTH_SCRIPT.new()
	add_child_autofree(health_comp)
	health_comp.set("max_health", 100)
	health_comp.call("_ready")


## Verifies standard damage reduction and health signal emission.
func test_take_damage() -> void:
	print("TestHealthComponent: test_take_damage() called.")
	watch_signals(health_comp)

	health_comp.call("take_damage", 20)

	@warning_ignore("unsafe_call_argument")
	assert_eq(health_comp.get("current_health"), 80, "Health should decrease by damage amount.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [80])


## Verifies that health does not drop below zero and emits died signal.
func test_take_fatal_damage() -> void:
	print("TestHealthComponent: test_take_fatal_damage() called.")
	watch_signals(health_comp)

	health_comp.call("take_damage", 150)

	@warning_ignore("unsafe_call_argument")
	assert_eq(health_comp.get("current_health"), 0, "Health should not drop below zero.")
	assert_signal_emitted(health_comp, "died", "Should emit died signal when health reaches zero.")


## Verifies standard healing increments and health signal emission.
func test_heal() -> void:
	print("TestHealthComponent: test_heal() called.")
	health_comp.call("take_damage", 50)
	watch_signals(health_comp)

	health_comp.call("heal", 30)

	@warning_ignore("unsafe_call_argument")
	assert_eq(health_comp.get("current_health"), 80, "Health should increase by heal amount.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [80])


## Verifies that healing does not exceed maximum configured health.
func test_over_heal() -> void:
	print("TestHealthComponent: test_over_heal() called.")
	health_comp.call("take_damage", 10)
	watch_signals(health_comp)

	health_comp.call("heal", 50)

	@warning_ignore("unsafe_call_argument")
	assert_eq(health_comp.get("current_health"), 100, "Health should cap at max_health.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [100])


## Verifies max health scaling and proportional current health updates.
func test_increase_max_health() -> void:
	print("TestHealthComponent: test_increase_max_health() called.")
	watch_signals(health_comp)

	health_comp.call("increase_max_health", 50)

	@warning_ignore("unsafe_call_argument")
	assert_eq(health_comp.get("max_health"), 150, "Max health should increase.")
	@warning_ignore("unsafe_call_argument")
	assert_eq(
		health_comp.get("current_health"), 150, "Current health should scale with max health."
	)
	assert_signal_emitted_with_parameters(health_comp, "max_health_changed", [150])
