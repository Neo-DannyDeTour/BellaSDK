extends GutTest
## Unit tests for [EnterSign] scene, green [OmniLight3D], and [PoweredLight3D] emission sync.
class_name TestEnterSign

## The instantiated [PoweredLight3D] enter sign scene under test.
var _sign: PoweredLight3D = null


## Instantiates enter sign scene before each test run.
func before_each() -> void:
	print("TestEnterSign: Setting up test fixture.")
	var sc: PackedScene = load("res://environment/enter_sign.tscn") as PackedScene
	_sign = sc.instantiate() as PoweredLight3D
	add_child_autofree(_sign)


## Frees test fixture after each test run.
func after_each() -> void:
	print("TestEnterSign: Tearing down test fixture.")
	_sign = null


## Verifies [OmniLight3D], [PowerComponent], and [SignFace] mesh resolve with green tint.
func test_initial_hierarchy_and_green_tint() -> void:
	assert_not_null(_sign, "EnterSign should instantiate as PoweredLight3D.")
	assert_not_null(_sign.power_component, "PowerComponent should be resolved.")
	assert_true(_sign.light is OmniLight3D, "EnterSign light should be OmniLight3D.")
	assert_not_null(_sign.emissive_mesh, "SignFace emissive_mesh should be resolved.")
	assert_true(_sign.is_lit, "EnterSign should start lit when start_on is true.")
	assert_gt(_sign.light.light_color.g, _sign.light.light_color.r, "Light should be green.")
	var mat: BaseMaterial3D = _sign.emissive_mesh.get_surface_override_material(0) as BaseMaterial3D
	assert_not_null(mat, "Override material should exist on SignFace.")
	assert_true(mat.emission_enabled, "SignFace emission should be enabled.")
	assert_gt(mat.emission.g, mat.emission.r, "Emission tint should be green.")


## Verifies turn_off() and turn_on() toggle both [OmniLight3D] and [SignFace] emission.
func test_toggle_off_and_on() -> void:
	var mat: BaseMaterial3D = _sign.emissive_mesh.get_surface_override_material(0) as BaseMaterial3D
	_sign.turn_off()
	assert_false(_sign.is_lit, "EnterSign should be unlit after turn_off().")
	assert_false(_sign.light.visible, "OmniLight3D should be hidden after turn_off().")
	assert_false(mat.emission_enabled, "SignFace emission should be disabled when off.")

	_sign.turn_on()
	assert_true(_sign.is_lit, "EnterSign should be lit after turn_on().")
	assert_true(_sign.light.visible, "OmniLight3D should be visible after turn_on().")
	assert_true(mat.emission_enabled, "SignFace emission should be enabled when on.")
