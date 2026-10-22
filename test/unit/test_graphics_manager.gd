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


## Verifies that resetting to defaults initializes the canonical "Ultra" preset.
func test_reset_to_defaults_loads_ultra_preset() -> void:
	print("TestGraphicsManager: test_reset_to_defaults_loads_ultra_preset() called.")
	var preset: Variant = graphics.call("get_setting", "preset", "")
	var sdfgi: Variant = graphics.call("get_setting", "sdfgi", "")
	var ssao: Variant = graphics.call("get_setting", "ssao", "")
	var aa_mode: Variant = graphics.call("get_setting", "aa_mode", "")
	var motion_blur: Variant = graphics.call("get_setting", "motion_blur", -1.0)
	var dof_enabled: Variant = graphics.call("get_setting", "dof_enabled", true)

	assert_eq(preset, "Ultra", "Default preset should be Ultra.")
	assert_eq(sdfgi, "High", "Ultra preset SDFGI should default to High.")
	assert_eq(ssao, "High", "Ultra preset SSAO should default to High.")
	assert_eq(aa_mode, "MSAA 4x", "Default AA mode should be MSAA 4x.")
	assert_eq(motion_blur, 0.0, "Default motion blur should be 0.0.")
	assert_eq(dof_enabled, false, "Default DoF should be disabled.")


## Verifies that applying a preset updates the active configuration cache and persists it.
func test_apply_preset_updates_active_config() -> void:
	print("TestGraphicsManager: test_apply_preset_updates_active_config() called.")
	graphics.call("apply_preset", "Ultra")

	assert_eq(graphics.call("get_setting", "preset", ""), "Ultra", "Preset should update to Ultra.")
	assert_eq(graphics.call("get_setting", "sdfgi", ""), "High", "Ultra SDFGI should be High.")
	assert_eq(
		graphics.call("get_setting", "volumetric_fog", ""),
		"High",
		"Ultra Volumetric Fog should be High."
	)
	assert_eq(
		graphics.call("get_setting", "motion_blur", -1.0), 0.0, "Ultra Motion Blur should be 0.0."
	)
	assert_eq(
		graphics.call("get_setting", "dof_enabled", true), false, "Ultra DoF should be disabled."
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


## Verifies that setting volumetric fog to on preserves level zero density for FogVolumes.
func test_volumetric_fog_retains_zero_density_when_enabled() -> void:
	print("TestGraphicsManager: test_volumetric_fog_retains_zero_density_when_enabled() called.")
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_enabled = false
	we.environment = env
	add_child_autofree(we)

	var config: Dictionary = {
		"volumetric_fog": "High",
	}
	VideoApplier.apply_to_world_environment(we, config)

	assert_true(
		we.environment.volumetric_fog_enabled,
		"Volumetric fog should be enabled to support FogVolumes."
	)
	assert_eq(
		we.environment.volumetric_fog_density, 0.0, "Authored zero fog density must be preserved."
	)

	config["volumetric_fog"] = "Off"
	VideoApplier.apply_to_world_environment(we, config)
	assert_false(
		we.environment.volumetric_fog_enabled,
		"Volumetric fog should be disabled when setting is Off."
	)


## Verifies that resolution scale can be set independently and applied to viewport.
func test_resolution_scale_applies_correctly() -> void:
	print("TestGraphicsManager: test_resolution_scale_applies_correctly() called.")
	graphics.call("set_setting", "fsr_mode", "Disabled (Native)")
	graphics.call("set_setting", "resolution_scale", 0.7)

	var sub_vp: SubViewport = SubViewport.new()
	add_child_autofree(sub_vp)

	var active_cfg: Variant = graphics.get("active_config")
	if active_cfg is Dictionary:
		VideoApplier.apply_diorama_preview(sub_vp, active_cfg)
		assert_eq(
			sub_vp.scaling_3d_mode,
			Viewport.SCALING_3D_MODE_BILINEAR,
			"Scaling mode should be Bilinear when FSR is Disabled."
		)
		assert_almost_eq(
			sub_vp.scaling_3d_scale, 0.7, 0.001, "Scaling scale should match resolution scale."
		)
