class_name StairController
extends Node

const MAX_STEP_HEIGHT: float = 0.5

var _snapped_to_stairs_last_frame: bool = false
var _last_frame_was_on_floor: int = 0

# Cached objects to prevent per-frame allocation
var _up_test := PhysicsTestMotionResult3D.new()
var _forward_test := PhysicsTestMotionResult3D.new()
var _down_test := PhysicsTestMotionResult3D.new()
var _body_test := PhysicsTestMotionResult3D.new()
var _test_params := PhysicsTestMotionParameters3D.new()

@onready var stairs_below_cast: RayCast3D = %StairsBelowCast
@onready var stairs_ahead_cast: RayCast3D = %StairsAheadCast
@onready var player: CharacterBody3D = owner as CharacterBody3D


func _ready() -> void:
	# Ensure the test parameters always reference the player's RID
	_test_params.from = player.global_transform
	_test_params.exclude_bodies = [player.get_rid()]


func snap_up_stairs_check(delta: float) -> bool:
	if not player.is_on_floor() and not _snapped_to_stairs_last_frame:
		return false
	
	if player.velocity.y > 0 or (player.velocity * Vector3(1.0, 0.0, 1.0)).length() == 0:
		return false

	var expected_move_motion: Vector3 = player.velocity * Vector3(1.0, 0.0, 1.0) * delta
	var step_pos_with_clearance: Transform3D = player.global_transform

	# 1. Test moving UP safely
	_run_body_test_motion(step_pos_with_clearance, Vector3(0.0, MAX_STEP_HEIGHT * 2.0, 0.0), _up_test)
	step_pos_with_clearance.origin += _up_test.get_travel()

	# 2. Test moving FORWARD safely
	_run_body_test_motion(step_pos_with_clearance, expected_move_motion, _forward_test)
	step_pos_with_clearance.origin += _forward_test.get_travel()

	# 3. NOW test moving DOWN onto the step
	if (
		_run_body_test_motion(step_pos_with_clearance, Vector3(0.0, -MAX_STEP_HEIGHT * 2.0, 0.0), _down_test)
		and (
			_down_test.get_collider().is_class("StaticBody3D")
			or _down_test.get_collider().is_class("CSGShape3D")
		)
	):
		var step_height: float = ((step_pos_with_clearance.origin + _down_test.get_travel()) - player.global_position).y

		if (
			step_height > MAX_STEP_HEIGHT
			or step_height <= 0.01
			or (_down_test.get_collision_point() - player.global_position).y > MAX_STEP_HEIGHT
		):
			return false

		stairs_ahead_cast.global_position = (
			_down_test.get_collision_point()
			+ Vector3(0.0, MAX_STEP_HEIGHT, 0.0)
			+ expected_move_motion.normalized() * 0.1
		)
		stairs_ahead_cast.force_raycast_update()

		if (
			stairs_ahead_cast.is_colliding()
			and not _is_surface_too_steep(stairs_ahead_cast.get_collision_normal())
		):
			var _old_pos_y: float = player.global_position.y
			player.global_position = step_pos_with_clearance.origin + _down_test.get_travel()
			player.apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			
			# Assuming your camera controller handles the smoothing natively now
			# player.camera_controller.apply_smoothing(player.global_position.y - old_pos_y)
			return true

	return false


func snap_down_to_stairs_check() -> void:
	var did_snap: bool = false
	stairs_below_cast.force_raycast_update()
	var floor_below: bool = (
		stairs_below_cast.is_colliding()
		and not _is_surface_too_steep(stairs_below_cast.get_collision_normal())
	)
	var was_on_floor_last_frame: bool = Engine.get_physics_frames() - _last_frame_was_on_floor == 1

	if (
		not player.is_on_floor()
		and player.velocity.y <= 0
		and (was_on_floor_last_frame or _snapped_to_stairs_last_frame)
		and floor_below
	):
		if _run_body_test_motion(player.global_transform, Vector3(0.0, -MAX_STEP_HEIGHT, 0.0), _body_test):
			var travel_y: float = _body_test.get_travel().y

			if travel_y < -0.05:
				var _old_pos_y: float = player.global_position.y
				player.position.y += travel_y
				player.apply_floor_snap()
				did_snap = true
				# player.camera_controller.apply_smoothing(player.global_position.y - old_pos_y)

	_snapped_to_stairs_last_frame = did_snap


func track_floor_state() -> void:
	if player.is_on_floor():
		_last_frame_was_on_floor = Engine.get_physics_frames()


func _run_body_test_motion(from: Transform3D, motion: Vector3, result: PhysicsTestMotionResult3D) -> bool:
	_test_params.from = from
	_test_params.motion = motion
	return PhysicsServer3D.body_test_motion(player.get_rid(), _test_params, result)


func _is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > player.floor_max_angle
