extends GutTest

## Variant instance for the health component under test.
var health_comp: Variant = null


func before_each() -> void:
	print("TestHealthComponent: before_each() setup.")
	health_comp = load("res://shared/health_component.gd").new()
	add_child_autofree(health_comp)
	health_comp.max_health = 100
	health_comp._ready()


func test_take_damage() -> void:
	print("TestHealthComponent: test_take_damage() called.")
	watch_signals(health_comp)

	health_comp.take_damage(20)

	assert_eq(health_comp.current_health, 80, "Health should decrease by damage amount.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [80])


func test_take_fatal_damage() -> void:
	print("TestHealthComponent: test_take_fatal_damage() called.")
	watch_signals(health_comp)

	health_comp.take_damage(150)

	assert_eq(health_comp.current_health, 0, "Health should not drop below zero.")
	assert_signal_emitted(health_comp, "died", "Should emit died signal when health reaches zero.")


func test_heal() -> void:
	print("TestHealthComponent: test_heal() called.")
	health_comp.take_damage(50)
	watch_signals(health_comp)

	health_comp.heal(30)

	assert_eq(health_comp.current_health, 80, "Health should increase by heal amount.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [80])


func test_over_heal() -> void:
	print("TestHealthComponent: test_over_heal() called.")
	health_comp.take_damage(10)
	watch_signals(health_comp)

	health_comp.heal(50)

	assert_eq(health_comp.current_health, 100, "Health should cap at max_health.")
	assert_signal_emitted_with_parameters(health_comp, "health_changed", [100])


func test_increase_max_health() -> void:
	print("TestHealthComponent: test_increase_max_health() called.")
	watch_signals(health_comp)

	health_comp.increase_max_health(50)

	assert_eq(health_comp.max_health, 150, "Max health should increase.")
	assert_eq(health_comp.current_health, 150, "Current health should scale with max health.")
	assert_signal_emitted_with_parameters(health_comp, "max_health_changed", [150])
