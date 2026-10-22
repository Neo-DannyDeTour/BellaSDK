## Unit test suite validating JumpPad trajectory computation and launch mechanics.
extends GutTest

const JUMP_PAD_SCRIPT: GDScript = preload("res://interactables/jump_pad.gd")

## JumpPad Area3D instance under test.
var _jump_pad: Area3D

## Target Marker3D node defining jump destination.
var _target_marker: Marker3D


## Sets up JumpPad and target destination before each test run.
func before_each() -> void:
	print("Setting up JumpPad instance for testing.")
	var instance: Variant = JUMP_PAD_SCRIPT.new()
	if instance is Area3D:
		_jump_pad = instance
	_target_marker = Marker3D.new()
	_target_marker.position = Vector3(0.0, 5.0, 10.0)
	_jump_pad.add_child(_target_marker)
	_jump_pad.set(&"assigned_target", _target_marker)
	add_child_autofree(_jump_pad)


## Cleans up JumpPad and target marker after test execution.
func after_each() -> void:
	print("Tearing down JumpPad test instance.")
	_jump_pad = null
	_target_marker = null


## Verifies that default trajectory parameters compute valid flight time and velocity.
func test_trajectory_calculation() -> void:
	print("Testing JumpPad trajectory calculations.")
	_jump_pad.call(&"_update_trajectory")

	var raw_time: Variant = _jump_pad.get(&"_flight_time")
	var flight_time: float = 0.0
	if raw_time is float:
		flight_time = raw_time
	assert_gt(flight_time, 0.0, "Flight time should be strictly positive with valid target.")

	var raw_vel: Variant = _jump_pad.get(&"_initial_velocity")
	var initial_vel: Vector3 = Vector3.ZERO
	if raw_vel is Vector3:
		initial_vel = raw_vel
	assert_gt(initial_vel.y, 0.0, "Upward velocity component should be positive.")


## Verifies that increasing flight speed multiplier reduces overall flight time.
func test_flight_speed_multiplier_effects() -> void:
	print("Testing JumpPad flight speed multiplier scaling.")
	_jump_pad.set(&"flight_speed_multiplier", 1.0)
	_jump_pad.call(&"_update_trajectory")
	var raw_base_time: Variant = _jump_pad.get(&"_flight_time")
	var base_time: float = 0.0
	if raw_base_time is float:
		base_time = raw_base_time

	_jump_pad.set(&"flight_speed_multiplier", 2.0)
	_jump_pad.call(&"_update_trajectory")
	var raw_fast_time: Variant = _jump_pad.get(&"_flight_time")
	var fast_time: float = 0.0
	if raw_fast_time is float:
		fast_time = raw_fast_time

	assert_almost_eq(
		fast_time, base_time / 2.0, 0.01, "Doubling speed multiplier should halve flight time."
	)


## Verifies launching player velocity when body enters jump pad trigger.
func test_on_body_entered_launches_player() -> void:
	print("Testing JumpPad _on_body_entered launching player.")
	_jump_pad.call(&"_update_trajectory")
	var raw_vel: Variant = _jump_pad.get(&"_initial_velocity")
	var expected_velocity: Vector3 = Vector3.ZERO
	if raw_vel is Vector3:
		expected_velocity = raw_vel

	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)

	_jump_pad.call(&"_on_body_entered", player)

	assert_eq(
		player.velocity, expected_velocity, "Player velocity should be set to launch velocity."
	)
