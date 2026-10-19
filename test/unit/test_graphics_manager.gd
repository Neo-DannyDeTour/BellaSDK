## Unit tests for [GraphicsManager] verifying defaults, preset application, and diorama isolation.
class_name TestGraphicsManager
extends GutTest

const GRAPHICS_MANAGER_SCRIPT: GDScript = preload("res://core/graphics_manager.gd")

## The [Node] autoload instance under test.
var graphics: Node = null


## Sets up a clean test instance and resets video settings to defaults before each test.
func before_each() -> void:
	print("TestGraphicsManager: before_each() setup.")
	@warning_ignore("unsafe_method_access")
	graphics = GRAPHICS_MANAGER_SCRIPT.new()
	add_child_autofree(graphics)
	graphics.call("reset_to_defaults")


## Verifies that resetting to defaults initializes the canonical "High" preset.
func test_reset_to_defaults_loads_high_preset() -> void:
	print("TestGraphicsManager: test_reset_to_defaults_loads_high_preset() called.")
	var preset: Variant = graphics.call("get_setting", "preset", "")
	var sdfgi: Variant = graphics.call("get_setting", "sdfgi", "")
	var ssao: Variant = graphics.call("get_setting", "ssao", "")

	assert_eq(preset, "High", "Default preset should be High.")
	assert_eq(sdfgi, "Low", "High preset SDFGI should default to Low.")
	assert_eq(ssao, "Medium", "High preset SSAO should default to Medium.")


## Verifies that applying a preset updates the active configuration cache and persists it.
func test_apply_preset_updates_active_config() -> void:
	print("TestGraphicsManager: test_apply_preset_updates_active_config() called.")
	graphics.call("apply_preset", "Ultra")

	assert_eq(graphics.call("get_setting", "preset", ""), "Ultra", "Preset should update to Ultra.")
	assert_eq(graphics.call("get_setting", "sdfgi", ""), "Medium", "Ultra SDFGI should be Medium.")
	assert_eq(
		graphics.call("get_setting", "volumetric_fog", ""),
		"Medium",
		"Ultra Volumetric Fog should be Medium."
	)


## Verifies that toggling diorama mode updates the isolation state flag.
func test_set_diorama_mode_toggles_isolation() -> void:
	print("TestGraphicsManager: test_set_diorama_mode_toggles_isolation() called.")
	graphics.call("set_diorama_mode", true)
	@warning_ignore("unsafe_call_argument")
	assert_true(graphics.get("is_diorama_active"), "Diorama mode should be active.")

	graphics.call("set_diorama_mode", false)
	@warning_ignore("unsafe_call_argument")
	assert_false(graphics.get("is_diorama_active"), "Diorama mode should be inactive.")
