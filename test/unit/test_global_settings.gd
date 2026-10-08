class_name TestGlobalSettings
extends GutTest
## Unit tests verifying [GlobalSettings] fallback defaults and memory-backed key retrieval.

## The [GlobalSettings] test instance used during testing.
var settings: Node = null


## Pre-test setup instantiating isolated settings node with an in-memory [ConfigFile].
func before_each() -> void:
	print("TestGlobalSettings: Executing before_each() setup for isolated settings.")
	var script: GDScript = load("res://core/global_settings.gd") as GDScript
	var raw_instance: Object = script.new()
	if raw_instance is Node:
		settings = raw_instance
		settings.set("config", ConfigFile.new())
		add_child_autofree(settings)


## Tests that [method GlobalSettings.get_setting] returns the fallback value.
func test_get_setting_default() -> void:
	print("TestGlobalSettings: Executing test_get_setting_default() for absent key.")
	assert_not_null(settings, "GlobalSettings instance must be valid.")

	var result_var: Variant = settings.call("get_setting", "Audio", "volume", 0.5)
	var result_float: float = result_var if result_var is float else 0.0
	assert_eq(result_float, 0.5, "Should return the default fallback if key doesn't exist.")


## Tests that [method GlobalSettings.save_setting] writes to config.
func test_save_and_get_setting() -> void:
	print("TestGlobalSettings: Executing test_save_and_get_setting() after modification.")
	assert_not_null(settings, "GlobalSettings instance must be valid.")

	settings.call("save_setting", "Video", "vsync", true)

	var result_var: Variant = settings.call("get_setting", "Video", "vsync", false)
	var result_bool: bool = result_var if result_var is bool else false
	assert_true(result_bool, "Should return true since it was saved to the ConfigFile.")
