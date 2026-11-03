## Unit tests for [SquidPuddle] and locomotion hazard response.
class_name TestSquidPuddle
extends GutTest

const SQUID_PUDDLE_SCRIPT: GDScript = preload("res://enemies/squid/squid_puddle.gd")
const LOCO_SCRIPT: GDScript = preload("res://player/locomotion_component.gd")

## The puddle instance under test.
var _puddle: SquidPuddle = null

## The locomotion component under test.
var _loco: PlayerLocomotionComponent = null


## Sets up a clean test instance for each test.
func before_each() -> void:
	print("TestSquidPuddle: before_each() setup.")
	_puddle = SQUID_PUDDLE_SCRIPT.new() as SquidPuddle
	add_child_autofree(_puddle)

	_loco = LOCO_SCRIPT.new() as PlayerLocomotionComponent
	add_child_autofree(_loco)
	_loco._ready()


## Cleans up test state after each run.
func after_each() -> void:
	print("TestSquidPuddle: after_each() teardown.")
	Events.sand_surface_toggled.emit(false)
	Events.ice_surface_toggled.emit(false)


## Verifies that activating a NO_SPRINT puddle configures visuals and state correctly.
func test_puddle_activation() -> void:
	print("TestSquidPuddle: test_puddle_activation() called.")
	_puddle.activate(Vector3(1.0, 0.0, 1.0), SquidPuddle.PuddleType.NO_SPRINT)

	assert_true(_puddle.visible, "Activated puddle should be visible.")
	assert_eq(
		_puddle.global_position,
		Vector3(1.0, 0.0, 1.0),
		"Puddle position should match activation pos."
	)


## Verifies that locomotion component restricts sprint when sand hazard is active.
func test_locomotion_sand_hazard_blocks_sprint() -> void:
	print("TestSquidPuddle: test_locomotion_sand_hazard_blocks_sprint() called.")
	assert_true(_loco.can_sprint, "Default locomotion should allow sprinting.")

	Events.sand_surface_toggled.emit(true)
	assert_true(_loco.is_sand_hazard_active(), "Sand hazard should be active.")
	assert_false(_loco.can_sprint, "Sprint should be blocked while sand hazard is active.")

	Events.sand_surface_toggled.emit(false)
	assert_false(_loco.is_sand_hazard_active(), "Sand hazard should be inactive.")
	assert_true(_loco.can_sprint, "Sprint should be restored after sand hazard is cleared.")


## Verifies that sprint debuff timer blocks sprint and recovers after duration expires.
func test_locomotion_sprint_debuff_timer() -> void:
	print("TestSquidPuddle: test_locomotion_sprint_debuff_timer() called.")
	assert_true(_loco.can_sprint, "Default locomotion should allow sprinting.")

	Events.sprint_debuff_applied.emit(1.0)
	assert_false(_loco.can_sprint, "Sprint should be blocked after sprint debuff applied.")

	_loco.process_movement(0.5)
	assert_false(_loco.can_sprint, "Sprint should still be blocked after 0.5s.")

	_loco.process_movement(0.6)
	assert_true(_loco.can_sprint, "Sprint should recover after debuff duration expires.")


## Verifies that locomotion component tracks ice hazard state.
func test_locomotion_ice_hazard_tracking() -> void:
	print("TestSquidPuddle: test_locomotion_ice_hazard_tracking() called.")
	assert_false(_loco.is_ice_hazard_active(), "Default ice hazard should be inactive.")

	Events.ice_surface_toggled.emit(true)
	assert_true(_loco.is_ice_hazard_active(), "Ice hazard should be marked active.")

	Events.ice_surface_toggled.emit(false)
	assert_false(_loco.is_ice_hazard_active(), "Ice hazard should be marked inactive.")
