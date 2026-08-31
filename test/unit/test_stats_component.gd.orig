extends GutTest

## Variant instance for the stats component under test
var stats: Variant = null


class MockHealthComponent:
	extends "res://shared/health_component.gd"
	@warning_ignore("unused_signal")
	signal died_mock


func before_each() -> void:
	print("TestStatsComponent: before_each() setup.")
	stats = load("res://player/stats_component.gd").new()
	add_child_autofree(stats)


func test_save_load_data() -> void:
	print("TestStatsComponent: test_save_load_data() called.")
	var health_comp: MockHealthComponent = MockHealthComponent.new()
	add_child_autofree(health_comp)
	stats.health_component = health_comp

	health_comp.current_health = 45
	var data: Dictionary = stats.get_save_data()

	assert_eq(data["health"], 45, "Should save health correctly.")

	health_comp.current_health = 100
	stats.load_save_data({"health": 72})

	assert_eq(health_comp.current_health, 72, "Should override local state when loading data.")
