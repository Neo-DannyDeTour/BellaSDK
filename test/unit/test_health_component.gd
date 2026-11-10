## Unit tests for health component verifying damage, healing, and scaling.
class_name TestHealthComponent
extends GutTest

## The component instance under test.
var health_comp: HealthComponent = null


## Sets up a clean test instance and initializes health pool values.
func before_each() -> void:
	print("TestHealthComponent: before_each() setup.")
	health_comp = HealthComponent.new()
	add_child_autofree(health_comp)
	health_comp.max_health = 100
	health_comp.current_health = 100
	health_comp._ready()


## Verifies standard damage reduction and health signal emission.
func test_take_damage() -> void:
	print("TestHealthComponent: test_take_damage() called.")
	watch_signals(health_comp)

	health_comp.take_damage(20)

	assert_eq(health_comp.current_health, 80, "Health should decrease by damage amount.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [80])


## Verifies that health does not drop below zero and emits died signal.
func test_take_fatal_damage() -> void:
	print("TestHealthComponent: test_take_fatal_damage() called.")
	watch_signals(health_comp)

	health_comp.take_damage(150)

	assert_eq(health_comp.current_health, 0, "Health should not drop below zero.")
	assert_signal_emitted(health_comp, "died", "Should emit died signal when health reaches zero.")


## Verifies standard healing increments and health signal emission.
func test_heal() -> void:
	print("TestHealthComponent: test_heal() called.")
	health_comp.take_damage(50)
	watch_signals(health_comp)

	health_comp.heal(30)

	assert_eq(health_comp.current_health, 80, "Health should increase by heal amount.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [80])


## Verifies that healing does not exceed maximum configured health.
func test_over_heal() -> void:
	print("TestHealthComponent: test_over_heal() called.")
	health_comp.take_damage(10)
	watch_signals(health_comp)

	health_comp.heal(50)

	assert_eq(health_comp.current_health, 100, "Health should cap at max_health.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [100])


## Verifies max health scaling and proportional current health updates.
func test_increase_max_health() -> void:
	print("TestHealthComponent: test_increase_max_health() called.")
	watch_signals(health_comp)

	health_comp.increase_max_health(50)

	assert_eq(health_comp.max_health, 150, "Max health should increase.")
	assert_eq(health_comp.current_health, 150, "Current health should scale with max health.")
	assert_signal_emitted_with_parameters(health_comp, "max_health_changed", [150])


## Verifies that random_health_range rolls a value within the specified bounds.
func test_random_health_roll() -> void:
	print("TestHealthComponent: test_random_health_roll() called.")
	var comp: HealthComponent = HealthComponent.new()
	add_child_autofree(comp)
	comp.random_health_range = Vector2i(45, 90)
	comp._ready()

	var rolled_max: int = comp.max_health
	var rolled_curr: int = comp.current_health
	assert_true(rolled_max >= 45 and rolled_max <= 90, "Max health should be within bounds.")
	assert_eq(rolled_curr, rolled_max, "Current health should match randomized max health.")


## Verifies that reset re-rolls health within bounds.
func test_random_health_reset_rerolls() -> void:
	print("TestHealthComponent: test_random_health_reset_rerolls() called.")
	var comp: HealthComponent = HealthComponent.new()
	add_child_autofree(comp)
	comp.random_health_range = Vector2i(45, 90)
	comp._ready()

	comp.take_damage(20)
	comp.reset()
	var reset_curr: int = comp.current_health
	assert_true(reset_curr >= 45 and reset_curr <= 90, "Reset health should be within bounds.")
