## Unit tests for the GlobalSettings autoload script.
##
## This suite verifies the behavior of the [GlobalSettings] singleton by instantiating
## a clean test instance and bypassing disk I/O using an empty [ConfigFile].
class_name TestGlobalSettings
extends GutTest

## The [GlobalSettings] test instance used during testing.
var settings: Node = null


## Called before each test to setup a fresh [GlobalSettings] environment.
## Replaces the file-backed [ConfigFile] with an empty memory one.
func before_each() -> void:
	print("TestGlobalSettings: Executing before_each() setup for isolated settings.")
	settings = GlobalSettings.new() as Node
	settings.set("config", ConfigFile.new())
	add_child_autofree(settings)


## Tests that [method GlobalSettings.get_setting] returns the fallback value
## when requested key does not exist.
func test_get_setting_default() -> void:
	print("TestGlobalSettings: Executing test_get_setting_default() for absent key.")
	var result: Variant = settings.call("get_setting", "Audio", "volume", 0.5)
	assert_eq(result, 0.5, "Should return the default fallback if key doesn't exist.")


## Tests that [method GlobalSettings.save_setting] writes to the config
## and [method GlobalSettings.get_setting] retrieves the updated value.
func test_save_and_get_setting() -> void:
	print("TestGlobalSettings: Executing test_save_and_get_setting() after modification.")
	settings.call("save_setting", "Video", "vsync", true)

	var result: Variant = settings.call("get_setting", "Video", "vsync", false)
	assert_true(result, "Should return true since it was saved to the ConfigFile.")
