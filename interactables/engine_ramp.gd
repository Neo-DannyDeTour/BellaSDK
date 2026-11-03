## Motorized hinged ramp with surface arc detection and coupled gear rotation.
class_name EngineRamp
extends Node3D

## Emitted when ramp begins lowering or raising.
signal ramp_started(is_lowering: bool)
## Emitted when ramp finishes motion at [param final_angle_deg].
signal ramp_stopped(is_deployed: bool, final_angle_deg: float)

## Minimum angular difference in degrees required to trigger motion.
const MIN_ANGLE_DELTA_DEG: float = 0.05

@export_group("Ramp Behavior")
## When true, ramp lowers once and ignores subsequent [method power_off] calls.
@export var is_one_way: bool = false

## Raised resting angle in degrees around local X axis of [member hinge_pivot].
@export var start_angle_deg: float = 0.0

## Maximum lowered fallback angle in degrees when no surface is hit.
@export_range(10.0, 180.0, 0.5) var max_angle_deg: float = 110.0

## Angular travel speed in degrees per second.
@export_range(1.0, 360.0, 0.5) var deg_per_sec: float = 35.0

## Post-stop delay in seconds before a queued reverse transition can start.
@export_range(0.0, 10.0, 0.1) var cooldown_sec: float = 1.0

@export_group("Surface Detection")
## Number of chord segments sampled along tip arc during surface raycast.
@export_range(4, 64, 1) var arc_samples: int = 24

## Half-thickness of ramp deck in meters used for flush surface resting offset.
@export_range(0.0, 1.0, 0.01) var deck_half_thickness: float = 0.1

@export_group("Gear Coupling")
## Local rotation axis for [member gear_a] and [member gear_b] (0=X, 1=Y, 2=Z).
@export_enum("X (Pitch)", "Y (Yaw)", "Z (Roll)") var gear_axis: int = 0

## Multiplier converting ramp hinge degrees to [member gear_a] degrees.
@export var gear_a_ratio: float = 4.0

## Tooth ratio of [member gear_b] relative to [member gear_a] (counter-rotates).
@export var gear_b_ratio: float = 1.5

@export_group("Audio")
## Looping motor sound played on [member motor_loop_player] while ramp moves.
@export var motor_loop_sfx: AudioStream

## One-shot mechanical clunk played via [AudioPool] when ramp stops.
@export var stop_clunk_sfx: AudioStream

@export_group("Internal Node References")
## Static base housing collider excluded from surface detection raycasts.
@export var engine_base: CollisionObject3D

## Pivot node whose local X rotation drives the ramp angle.
@export var hinge_pivot: Node3D

## Kinematic body providing walkable collision on the ramp deck.
@export var ramp_deck: AnimatableBody3D

## Left outer tip marker in [member hinge_pivot] space for arc raycasting.
@export var tip_marker_left: Marker3D

## Right outer tip marker in [member hinge_pivot] space for arc raycasting.
@export var tip_marker_right: Marker3D

## Primary drive gear visual node rotated in sync with hinge motion.
@export var gear_a: Node3D

## Secondary counter-rotating gear visual node meshed with [member gear_a].
@export var gear_b: Node3D

## 3D audio player handling looping motor sound during ramp movement.
@export var motor_loop_player: AudioStreamPlayer3D

## Active tween driving hinge and gear angles.
var _tween: Tween

## Current ramp hinge angle in degrees.
var _current_angle_deg: float = 0.0

## Target deployed state requested by latest [method power_on] or [method power_off].
var _desired_deployed: bool = false

## Actual deployed state reached by the ramp.
var _is_deployed: bool = false

## True while ramp tween is actively interpolating angles.
var _is_moving: bool = false

## True during the post-stop cooldown window before reversal is allowed.
var _in_cooldown: bool = false

## Cached local offset of [member tip_marker_left] relative to [member hinge_pivot].
var _local_tip_left: Vector3 = Vector3(-0.9, -0.1, 4.0)

## Cached local offset of [member tip_marker_right] relative to [member hinge_pivot].
var _local_tip_right: Vector3 = Vector3(0.9, -0.1, 4.0)

## Cached array of self collision RIDs excluded from surface raycasts.
var _exclude_rids: Array[RID] = []


## Initializes node references, caches tip offsets, and disables frame polling.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	if not is_instance_valid(engine_base):
		engine_base = get_node_or_null("EngineBase") as CollisionObject3D
	if not is_instance_valid(hinge_pivot):
		hinge_pivot = get_node_or_null("HingePivot") as Node3D
	if not is_instance_valid(ramp_deck):
		ramp_deck = get_node_or_null("HingePivot/RampDeck") as AnimatableBody3D
	if not is_instance_valid(tip_marker_left):
		tip_marker_left = get_node_or_null("HingePivot/RampDeck/TipMarkerLeft") as Marker3D
	if not is_instance_valid(tip_marker_right):
		tip_marker_right = get_node_or_null("HingePivot/RampDeck/TipMarkerRight") as Marker3D
	if not is_instance_valid(gear_a):
		gear_a = get_node_or_null("GearA") as Node3D
	if not is_instance_valid(gear_b):
		gear_b = get_node_or_null("GearB") as Node3D
	if not is_instance_valid(motor_loop_player):
		motor_loop_player = get_node_or_null("MotorLoopPlayer") as AudioStreamPlayer3D

	assert(is_instance_valid(hinge_pivot), "EngineRamp: hinge_pivot is mandatory.")
	assert(is_instance_valid(ramp_deck), "EngineRamp: ramp_deck is mandatory.")

	_cache_geometry_and_rids()
	_apply_angle_deg(start_angle_deg)


## Commanded by [OutputTransmitter3D] or script to lower the ramp.
func power_on() -> void:
	print("EngineRamp: power_on() received on ", name)
	_desired_deployed = true
	_try_process_desired_state()


## Commanded by [OutputTransmitter3D] or script to raise the ramp.
func power_off() -> void:
	if is_one_way and (_is_deployed or _desired_deployed):
		print("EngineRamp: Ignoring power_off() on ", name, " (is_one_way enabled).")
		return
	print("EngineRamp: power_off() received on ", name)
	_desired_deployed = false
	_try_process_desired_state()


## Evaluates whether a queued transition should start immediately.
func _try_process_desired_state() -> void:
	if _is_moving or _in_cooldown:
		return
	if _desired_deployed == _is_deployed:
		return

	if _desired_deployed:
		var landing_deg: float = _detect_landing_angle_deg()
		_start_motion(landing_deg, true)
	else:
		# shortcut: kinematic raise pushes standing player, add deck Area3D check if needed
		_start_motion(start_angle_deg, false)


## Starts linear tween from [member _current_angle_deg] to [param target_deg].
func _start_motion(target_deg: float, deploying: bool) -> void:
	var angle_delta: float = absf(target_deg - _current_angle_deg)
	if angle_delta < MIN_ANGLE_DELTA_DEG:
		_apply_angle_deg(target_deg)
		_is_deployed = deploying
		return

	var duration: float = angle_delta / maxf(deg_per_sec, 0.1)
	_is_moving = true
	print(
		"EngineRamp: Starting motion on ",
		name,
		" -> target_deg=",
		snappedf(target_deg, 0.1),
		" duration=",
		snappedf(duration, 0.01),
		"s"
	)

	_start_motor_audio()
	ramp_started.emit(deploying)

	_tween = Utilities.reset_tween_ext(self, _tween, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	if not is_instance_valid(_tween):
		_is_moving = false
		return

	_tween.tween_method(_apply_angle_deg, _current_angle_deg, target_deg, duration)
	_tween.tween_callback(_on_motion_finished.bind(deploying, target_deg))


## Handles tween completion, audio stop, clunk SFX, and post-stop cooldown timer.
func _on_motion_finished(deployed_state: bool, final_deg: float) -> void:
	_is_moving = false
	_is_deployed = deployed_state
	_stop_motor_audio()

	if is_instance_valid(stop_clunk_sfx) and is_instance_valid(hinge_pivot):
		AudioPool.play_sfx_3d(stop_clunk_sfx, hinge_pivot.global_position)

	print(
		"EngineRamp: Motion stopped on ",
		name,
		" | deployed=",
		_is_deployed,
		" angle=",
		snappedf(final_deg, 0.1)
	)
	ramp_stopped.emit(_is_deployed, final_deg)

	if cooldown_sec > 0.0 and is_inside_tree():
		_in_cooldown = true
		Utilities.delay_call(self, cooldown_sec, _on_cooldown_timeout)
	else:
		_try_process_desired_state()


## Clears post-stop cooldown and triggers any pending reverse transition.
func _on_cooldown_timeout() -> void:
	_in_cooldown = false
	_try_process_desired_state()


## Updates hinge rotation and both meshed gear rotations for [param angle_deg].
func _apply_angle_deg(angle_deg: float) -> void:
	_current_angle_deg = angle_deg
	if is_instance_valid(hinge_pivot):
		hinge_pivot.rotation_degrees.x = angle_deg

	var gear_a_deg: float = angle_deg * gear_a_ratio
	var gear_b_deg: float = -gear_a_deg * gear_b_ratio
	_set_gear_axis_deg(gear_a, gear_a_deg)
	_set_gear_axis_deg(gear_b, gear_b_deg)


## Assigns [param deg] to the configured [member gear_axis] on [param gear_node].
func _set_gear_axis_deg(gear_node: Node3D, deg: float) -> void:
	if not is_instance_valid(gear_node):
		return
	var rot: Vector3 = gear_node.rotation_degrees
	if gear_axis == 0:
		rot.x = deg
	elif gear_axis == 1:
		rot.y = deg
	else:
		rot.z = deg
	gear_node.rotation_degrees = rot


## Samples the tip sweep arc via raycasts to compute the exact resting angle.
func _detect_landing_angle_deg() -> float:
	if not is_instance_valid(hinge_pivot) or not is_inside_tree():
		return max_angle_deg

	var world: World3D = get_world_3d()
	if not is_instance_valid(world):
		return max_angle_deg
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if not is_instance_valid(space_state):
		return max_angle_deg

	var base_xf: Transform3D = hinge_pivot.global_transform
	var zero_basis: Basis = base_xf.basis * Basis(Vector3.RIGHT, -hinge_pivot.rotation.x)
	var zero_xf: Transform3D = Transform3D(zero_basis, base_xf.origin)

	var steps: int = maxi(arc_samples, 4)
	var start_rad: float = deg_to_rad(start_angle_deg)
	var max_rad: float = deg_to_rad(max_angle_deg)

	var prev_left: Vector3 = _point_on_arc(zero_xf, _local_tip_left, start_rad)
	var prev_right: Vector3 = _point_on_arc(zero_xf, _local_tip_right, start_rad)

	for step_idx: int in range(1, steps + 1):
		var t: float = float(step_idx) / float(steps)
		var sample_rad: float = lerpf(start_rad, max_rad, t)
		var next_left: Vector3 = _point_on_arc(zero_xf, _local_tip_left, sample_rad)
		var next_right: Vector3 = _point_on_arc(zero_xf, _local_tip_right, sample_rad)

		var hit_left: Dictionary = NodeQuery.cast_ray(
			space_state, prev_left, next_left, CollisionLayers.MASK_SOLID_WORLD, _exclude_rids
		)
		var hit_right: Dictionary = NodeQuery.cast_ray(
			space_state, prev_right, next_right, CollisionLayers.MASK_SOLID_WORLD, _exclude_rids
		)

		var has_left: bool = not hit_left.is_empty()
		var has_right: bool = not hit_right.is_empty()
		if has_left or has_right:
			var angle_left: float = max_angle_deg
			var angle_right: float = max_angle_deg
			if has_left:
				var pos_var_l: Variant = hit_left.get("position", next_left)
				var hit_pos_l: Vector3 = pos_var_l if pos_var_l is Vector3 else next_left
				angle_left = _hit_point_to_angle_deg(zero_xf, _local_tip_left, hit_pos_l)
			if has_right:
				var pos_var_r: Variant = hit_right.get("position", next_right)
				var hit_pos_r: Vector3 = pos_var_r if pos_var_r is Vector3 else next_right
				angle_right = _hit_point_to_angle_deg(zero_xf, _local_tip_right, hit_pos_r)

			var resolved_deg: float = minf(angle_left, angle_right)
			return clampf(resolved_deg, start_angle_deg, max_angle_deg)

		prev_left = next_left
		prev_right = next_right

	return max_angle_deg


## Computes world-space position of [param local_tip] rotated by [param angle_rad].
func _point_on_arc(zero_xf: Transform3D, local_tip: Vector3, angle_rad: float) -> Vector3:
	var rotated_local: Vector3 = local_tip.rotated(Vector3.RIGHT, angle_rad)
	return zero_xf * rotated_local


## Converts world [param hit_pos] back to hinge degrees minus deck thickness offset.
func _hit_point_to_angle_deg(zero_xf: Transform3D, local_tip: Vector3, hit_pos: Vector3) -> float:
	var local_hit: Vector3 = zero_xf.affine_inverse() * hit_pos
	var radius: float = Vector2(local_tip.y, local_tip.z).length()
	if radius < 0.001:
		return max_angle_deg

	var tip_base_angle: float = atan2(-local_tip.y, local_tip.z)
	var hit_angle: float = atan2(-local_hit.y, local_hit.z)
	var thickness_offset: float = asin(clampf(deck_half_thickness / radius, 0.0, 0.99))
	var final_rad: float = hit_angle - tip_base_angle - thickness_offset
	return rad_to_deg(final_rad)


## Caches tip marker offsets in zero-angle hinge space and collects self RIDs.
func _cache_geometry_and_rids() -> void:
	_exclude_rids.clear()
	if is_instance_valid(ramp_deck):
		ramp_deck.collision_layer = CollisionLayers.MASK_ENVIRONMENT
		ramp_deck.collision_mask = CollisionLayers.MASK_NONE
		_exclude_rids.append(ramp_deck.get_rid())
	if is_instance_valid(engine_base):
		_exclude_rids.append(engine_base.get_rid())

	if is_instance_valid(hinge_pivot):
		var inv_hinge: Transform3D = hinge_pivot.global_transform.affine_inverse()
		if is_instance_valid(tip_marker_left):
			_local_tip_left = inv_hinge * tip_marker_left.global_position
		if is_instance_valid(tip_marker_right):
			_local_tip_right = inv_hinge * tip_marker_right.global_position


## Starts looping motor audio on [member motor_loop_player] if configured.
func _start_motor_audio() -> void:
	if not is_instance_valid(motor_loop_player):
		return
	if is_instance_valid(motor_loop_sfx):
		motor_loop_player.stream = motor_loop_sfx
	if is_instance_valid(motor_loop_player.stream) and not motor_loop_player.playing:
		motor_loop_player.play()


## Stops looping motor audio on [member motor_loop_player] if active.
func _stop_motor_audio() -> void:
	if is_instance_valid(motor_loop_player) and motor_loop_player.playing:
		motor_loop_player.stop()
