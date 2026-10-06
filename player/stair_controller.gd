## Handles step-up and step-down stair snapping and camera smoothing for [CharacterBody3D].
class_name StairController
extends Node

## Maximum step obstacle height in meters the character can climb over.
const MAX_STEP_HEIGHT: float = 0.55

## Minimum forward step sweep distance in meters to check for upcoming steps.
const MIN_STEP_REACH: float = 0.3

## Time elapsed in seconds since the last successful step-up snap.
var time_since_step_up: float = 100.0

## Tracks whether the player snapped to a step in the immediately preceding frame.
var _snapped_to_stairs_last_frame: bool = false

## Physics frame index recorded when the player was last detected on the floor.
var _last_frame_was_on_floor: int = 0

## Toggles step snapping logic on or off.
var is_enabled: bool = true

## Collision test result holder for upward vertical motion.
var _up_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()

## Collision test result holder for forward horizontal motion.
var _forward_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()

## Collision test result holder for downward landing motion.
var _down_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()

## Collision test result holder for immediate obstacle checks.
var _body_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()

## Reusable parameters container for physics body test queries.
var _test_params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()

## Accumulated time in seconds since the last step audio/visual feedback trigger.
var time_since_step_feedback: float = 100.0

## Downward raycast used to verify floor existence when snapping down ledges.
@onready var stairs_below_cast: RayCast3D = %StairsBelowCast

## Owning player character controller.
@onready var player: CharacterBody3D = owner as CharacterBody3D


## Pre-populates physics query parameters with the player's initial transform and RID.
func _ready() -> void:
	_test_params.from = player.global_transform
	_test_params.exclude_bodies = [player.get_rid()]


## Tests for an obstacle ahead and snaps the player up onto valid step geometry.
func snap_up_stairs_check(delta: float, is_sprinting: bool = false) -> bool:
	var env: Object = player.get("environment_component") as Object
	var vault_ctrl: Object = (
		env.get("vault_controller") as Object if is_instance_valid(env) else null
	)
	var is_vaulting: bool = is_instance_valid(vault_ctrl) and bool(vault_ctrl.get("is_vaulting"))

	if not is_enabled or is_vaulting:
		return false

	time_since_step_up += delta
	time_since_step_feedback += delta
	var was_snapped_last_frame: bool = _snapped_to_stairs_last_frame
	_snapped_to_stairs_last_frame = false

	if not player.is_on_floor() and not was_snapped_last_frame:
		return false

	var flat_velocity: Vector3 = player.velocity * Vector3(1.0, 0.0, 1.0)
	if player.velocity.y > 0.0 or flat_velocity.length() == 0.0:
		return false

	var check_distance: float = maxf(flat_velocity.length() * delta, 0.05)
	var step_check_motion: Vector3 = flat_velocity.normalized() * check_distance

	if not _run_body_test_motion(player.global_transform, step_check_motion, _body_test):
		return false

	if not _is_surface_too_steep(_body_test.get_collision_normal()):
		return false

	var forward_distance: float = maxf(flat_velocity.length() * delta, MIN_STEP_REACH)
	var expected_move_motion: Vector3 = flat_velocity.normalized() * forward_distance

	var step_pos_with_clearance: Transform3D = player.global_transform

	_run_body_test_motion(
		step_pos_with_clearance, Vector3(0.0, MAX_STEP_HEIGHT * 1.5, 0.0), _up_test
	)
	step_pos_with_clearance.origin += _up_test.get_travel()

	_run_body_test_motion(step_pos_with_clearance, expected_move_motion, _forward_test)
	step_pos_with_clearance.origin += _forward_test.get_travel()

	if _run_body_test_motion(
		step_pos_with_clearance, Vector3(0.0, -MAX_STEP_HEIGHT * 1.5, 0.0), _down_test
	):
		var travel_point: Vector3 = step_pos_with_clearance.origin + _down_test.get_travel()
		var step_height: float = (travel_point - player.global_position).y

		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01:
			return false

		if _is_surface_too_steep(_down_test.get_collision_normal()):
			return false

		var previous_y: float = player.global_position.y
		player.global_position.y = travel_point.y
		player.apply_floor_snap()

		_snapped_to_stairs_last_frame = true
		time_since_step_up = 0.0

		var actual_step_height: float = player.global_position.y - previous_y
		var loco: Object = player.get("locomotion_component") as Object

		if is_instance_valid(loco):
			var head: Node3D = loco.get("head") as Node3D
			if is_instance_valid(head):
				head.position.y -= actual_step_height

				var feedback_threshold: float = 0.35 if is_sprinting else 0.25
				if time_since_step_feedback > feedback_threshold:
					time_since_step_feedback = 0.0
					print("StairController: Snapped UP. Camera offset: ", -actual_step_height)
				else:
					print("StairController: Micro-step physics handled. " + "Audio suppressed.")

		return true

	return false


## Snaps the player downward onto descending stair steps when moving off ledges.
func snap_down_to_stairs_check() -> void:
	var env: Object = player.get("environment_component") as Object
	var vault_ctrl: Object = (
		env.get("vault_controller") as Object if is_instance_valid(env) else null
	)
	var is_vaulting: bool = is_instance_valid(vault_ctrl) and bool(vault_ctrl.get("is_vaulting"))

	if not is_enabled or is_vaulting:
		return

	if time_since_step_up < 0.2:
		return

	var did_snap: bool = false
	stairs_below_cast.target_position = Vector3(0.0, -MAX_STEP_HEIGHT - 0.2, 0.0)
	stairs_below_cast.force_raycast_update()

	var floor_below: bool = (
		stairs_below_cast.is_colliding()
		and not _is_surface_too_steep(stairs_below_cast.get_collision_normal())
	)
	var was_on_floor_last_frame: bool = Engine.get_physics_frames() - _last_frame_was_on_floor == 1

	if (
		not player.is_on_floor()
		and player.velocity.y <= 0.0
		and (was_on_floor_last_frame or _snapped_to_stairs_last_frame)
		and floor_below
	):
		if _run_body_test_motion(
			player.global_transform, Vector3(0.0, -MAX_STEP_HEIGHT, 0.0), _body_test
		):
			var travel_y: float = _body_test.get_travel().y

			if travel_y < -0.05:
				var previous_y: float = player.global_position.y
				player.position.y += travel_y
				player.apply_floor_snap()
				did_snap = true

				var drop_distance: float = player.global_position.y - previous_y
				var loco: Object = player.get("locomotion_component") as Object

				if is_instance_valid(loco):
					var head: Node3D = loco.get("head") as Node3D
					if is_instance_valid(head):
						head.position.y -= drop_distance
						print("StairController: Snapped DOWN. Camera offset by: ", -drop_distance)

	if did_snap:
		_snapped_to_stairs_last_frame = true


## Updates the floor state cache with the current physics frame index.
func track_floor_state() -> void:
	if player.is_on_floor() or _snapped_to_stairs_last_frame:
		_last_frame_was_on_floor = Engine.get_physics_frames()


## Performs a physics test motion simulation from a given origin transform.
func _run_body_test_motion(
	from: Transform3D, motion: Vector3, result: PhysicsTestMotionResult3D
) -> bool:
	_test_params.from = from
	_test_params.motion = motion
	return PhysicsServer3D.body_test_motion(player.get_rid(), _test_params, result)


## Checks if the hit surface slope exceeds the player floor angle threshold.
func _is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > player.floor_max_angle
