## Smooths out player physics movement when ascending or descending staircases.
##
## [StairController] casts collision bodies ahead of and below the player to detect
## sharp geometric steps, teleporting the player upwards and offsetting the camera
## downwards to create the illusion of smooth sliding over jagged geometry.
class_name StairController
extends Node

## The maximum vertical height the physics engine is allowed to snap up instantly.
const MAX_STEP_HEIGHT: float = 0.55
## Minimum distance the forward test motion casts to clear the step.
const MIN_STEP_REACH: float = 0.3

## Timer tracking how long it has been since the last upward snap.
var time_since_step_up: float = 100.0
## Internal flag marking if a stair correction was applied the previous physics frame.
var _snapped_to_stairs_last_frame: bool = false
## Records the engine frame index when the player last registered as touching the ground.
var _last_frame_was_on_floor: int = 0
## Global toggle to disable stair smoothing (e.g., when jumping or flying).
var is_enabled: bool = true

## Cached reference object to store upwards physics shape query results.
var _up_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
## Cached reference object to store forward physics shape query results.
var _forward_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
## Cached reference object to store downwards physics shape query results.
var _down_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
## Cached reference object to store general collision physics query results.
var _body_test: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
## Reusable parameter object to execute the `body_test_motion` calls.
var _test_params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
## Timer tracking when the last audio/visual feedback was triggered.
var time_since_step_feedback: float = 100.0

## Downward pointing raycast used to verify a floor exists below a ledge.
@onready var stairs_below_cast: RayCast3D = %StairsBelowCast
## Reference to the root player physics body driving the controller.
@onready var player: CharacterBody3D = owner as CharacterBody3D


## Preconfigures the test parameters to ignore the player's own collision body.
func _ready() -> void:
	_test_params.from = player.global_transform
	_test_params.exclude_bodies = [player.get_rid()]


## Casts a physics profile forward to detect stairs and teleports the player up if matched.
## [param delta] The engine physics delta duration.
## [param is_sprinting] True if moving quickly, adjusting visual feedback thresholds.
## [return] True if an upward correction was applied this frame.
func snap_up_stairs_check(delta: float, is_sprinting: bool = false) -> bool:
	var env: Node = player.get("environment_component")
	var is_vaulting: bool = (
		is_instance_valid(env)
		and is_instance_valid(env.get("vault_controller"))
		and env.get("vault_controller").get("is_vaulting")
	)

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

	# Rely entirely on the motion test, which follows velocity direction perfectly
	if _run_body_test_motion(
		step_pos_with_clearance, Vector3(0.0, -MAX_STEP_HEIGHT * 1.5, 0.0), _down_test
	):
		var travel_point: Vector3 = step_pos_with_clearance.origin + _down_test.get_travel()
		var step_height: float = (travel_point - player.global_position).y

		# Restoring this block kills the micro-jitter entirely
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01:
			return false

		# Validate the surface normal we are stepping onto
		if _is_surface_too_steep(_down_test.get_collision_normal()):
			return false

		var previous_y: float = player.global_position.y
		player.global_position.y = travel_point.y
		player.apply_floor_snap()

		_snapped_to_stairs_last_frame = true
		time_since_step_up = 0.0

		var actual_step_height: float = player.global_position.y - previous_y
		var loco: Node = player.get("locomotion_component")

		if is_instance_valid(loco) and is_instance_valid(loco.get("head")):
			var head: Node3D = loco.get("head")
			head.position.y -= actual_step_height

			var feedback_threshold: float = 0.35 if is_sprinting else 0.25
			if time_since_step_feedback > feedback_threshold:
				time_since_step_feedback = 0.0
				print("StairController: Snapped UP visually. Camera offset: ", -actual_step_height)
			else:
				print("StairController: Micro-step handled physics. Audio suppressed.")

		return true

	return false


## Detects drops in the floor profile directly beneath the player and snaps downwards.
func snap_down_to_stairs_check() -> void:
	var env: Node = player.get("environment_component")
	var is_vaulting: bool = (
		is_instance_valid(env)
		and is_instance_valid(env.get("vault_controller"))
		and env.get("vault_controller").get("is_vaulting")
	)

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
				var loco: Node = player.get("locomotion_component")

				if is_instance_valid(loco) and is_instance_valid(loco.get("head")):
					var head: Node3D = loco.get("head")
					head.position.y -= drop_distance
					print("StairController: Snapped DOWN. Camera offset by: ", -drop_distance)

	if did_snap:
		_snapped_to_stairs_last_frame = true


## Caches the current physics frame index if the player is safely grounded.
func track_floor_state() -> void:
	if player.is_on_floor() or _snapped_to_stairs_last_frame:
		_last_frame_was_on_floor = Engine.get_physics_frames()


## Executes an isolated physics cast of the player's collision shape.
## [param from] Starting global transform.
## [param motion] Displacement vector.
## [param result] The cached object to store intersection data in.
## [return] True if a collision occurred.
func _run_body_test_motion(
	from: Transform3D, motion: Vector3, result: PhysicsTestMotionResult3D
) -> bool:
	_test_params.from = from
	_test_params.motion = motion
	return PhysicsServer3D.body_test_motion(player.get_rid(), _test_params, result)


## Evaluates if a given surface normal exceeds the player's climbable floor angle.
## [param normal] The normalized vector returned from a raycast hit.
## [return] True if the incline is impassable.
func _is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > player.floor_max_angle
