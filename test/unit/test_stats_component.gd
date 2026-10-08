## Unit test suite validating PlayerStatsComponent serialization and health tracking.
@tool
class_name TestStatsComponent
extends GutTest

## The [PlayerStatsComponent] instance under test.
var stats: PlayerStatsComponent = null


## Mock health component extending HealthComponent for testing save/load state.
class MockHealthComponent:
	extends HealthComponent

	## Initializes starting health values.
	func _init() -> void:
		current_health = 100


## Prepares mock dependencies and stats component before each test.
func before_each() -> void:
	print("TestStatsComponent: before_each() setup.")
	stats = PlayerStatsComponent.new()
	add_child_autofree(stats)


## Verifies serializing and deserializing health data through the stats component.
func test_save_load_data() -> void:
	print("TestStatsComponent: test_save_load_data() called.")
	var health_comp: MockHealthComponent = MockHealthComponent.new()
	add_child_autofree(health_comp)
	stats.health_component = health_comp

	health_comp.current_health = 45
	var raw_data: Dictionary = stats.get_save_data()
	var typed_data: Dictionary[String, int] = {}
	typed_data.assign(raw_data)

	var saved_health: int = typed_data.get("health", 0)
	assert_eq(saved_health, 45, "Should save health correctly.")

	health_comp.current_health = 100
	stats.load_save_data({"health": 72})

	assert_eq(health_comp.current_health, 72, "Should override local state when loading data.")
