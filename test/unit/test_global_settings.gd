extends GutTest

## Variant instance for the global settings Autoload testing
var settings: Variant = null


func before_each() -> void:
	print("TestGlobalSettings: before_each() setup.")
	# For Autoloads, they might already exist in the tree. We instance a fresh one for testing
	settings = load("res://core/global_settings.gd").new()
	# Bypass loading from the real disk by replacing the ConfigFile with a clean one
	settings.config = ConfigFile.new()
	add_child_autofree(settings)


func test_get_setting_default() -> void:
	print("TestGlobalSettings: test_get_setting_default() called.")
	var result: Variant = settings.get_setting("Audio", "volume", 0.5)
	assert_eq(result, 0.5, "Should return the default fallback if key doesn't exist.")


func test_save_and_get_setting() -> void:
	print("TestGlobalSettings: test_save_and_get_setting() called.")
	# Actually save a value and get it back
	settings.save_setting("Video", "vsync", true)

	var result: Variant = settings.get_setting("Video", "vsync", false)
	assert_true(result, "Should return true since it was saved to the ConfigFile.")
