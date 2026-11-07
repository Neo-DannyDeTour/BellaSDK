extends GutTest
## Unit tests for [CageLight] scene and [PoweredLight3D] emissive sync.
class_name TestCageLight

## The instantiated [PoweredLight3D] cage light scene under test.
var _light: PoweredLight3D = null


## Instantiates cage light scene before each test run.
func before_each() -> void:
	print("TestCageLight: Setting up test fixture.")
	var sc: PackedScene = load("res://environment/cage_light.tscn") as PackedScene
	_light = sc.instantiate() as PoweredLight3D
	add_child_autofree(_light)


## Frees test fixture after each test run.
func after_each() -> void:
	print("TestCageLight: Tearing down test fixture.")
	_light = null


## Verifies mandatory child components and nodes are configured correctly.
func test_initial_hierarchy_and_references() -> void:
	assert_not_null(_light.power_component, "PowerComponent should be resolved.")
	assert_not_null(_light.light, "SpotLight3D should be resolved.")
	assert_not_null(_light.emissive_mesh, "Glass diffuser mesh should be resolved.")


## Verifies power addition turns on both spotlight and material emission.
func test_power_component_turns_light_and_emission_on() -> void:
	assert_false(_light.is_lit, "Light should start unlit.")
	_light.add_power()
	assert_true(_light.is_lit, "Light should be lit when power threshold reached.")
	assert_true(_light.light.visible, "Spotlight should be visible.")
	var mat: BaseMaterial3D = (
		_light.emissive_mesh.get_surface_override_material(0) as BaseMaterial3D
	)
	assert_not_null(mat, "Override material should be present on bulb mesh.")
	assert_true(mat.emission_enabled, "Bulb emission should be enabled.")
	assert_gt(mat.emission_energy_multiplier, 0.0, "Emission energy should be positive.")


## Verifies removing power disables spotlight and material emission.
func test_remove_power_turns_light_and_emission_off() -> void:
	_light.add_power()
	assert_true(_light.is_lit)
	_light.remove_power()
	assert_false(_light.is_lit, "Light should be unlit after losing power.")
	assert_false(_light.light.visible, "Spotlight should be hidden.")
	var mat: BaseMaterial3D = (
		_light.emissive_mesh.get_surface_override_material(0) as BaseMaterial3D
	)
	assert_not_null(mat)
	assert_false(mat.emission_enabled, "Bulb emission should be disabled.")
