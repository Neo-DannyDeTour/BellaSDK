## Controls first-person camera transforms, bobbing, FOV, and input sensitivity.
class_name CameraController
extends Node3D

## Head bobbing cycle speed during sprint locomotion.
const HEAD_BOBBING_SPRINTING_SPEED: float = 22.0
## Head bobbing cycle speed during standard walking.
const HEAD_BOBBING_WALKING_SPEED: float = 14.0
## Head bobbing cycle speed while crouched.
const HEAD_BOBBING_CROUCHING_SPEED: float = 10.0
## Head bobbing cycle speed while standing idle.
const HEAD_BOBBING_IDLE_SPEED: float = 3.0

## Head bobbing displacement intensity during sprint locomotion.
const HEAD_BOBBING_SPRINTING_INTENSITY: float = 0.2
## Head bobbing displacement intensity during standard walking.
const HEAD_BOBBING_WALKING_INTENSITY: float = 0.1
## Head bobbing displacement intensity while crouched.
const HEAD_BOBBING_CROUCHING_INTENSITY: float = 0.08
## Head bobbing displacement intensity while standing idle.
const HEAD_BOBBING_IDLE_INTENSITY: float = 0.02

@export_category("Node References")
## Reference to the root player physics body.
@export var player_body: CharacterBody3D
## Reference to the vertical pitch pivot node.
@export var head: Node3D
## Reference to the camera container node handling offsets.
@export var eyes: Node3D
## Reference to the active 3D camera instance.
@export var camera: Camera3D

@export_category("Sensitivity & FOV")
## Base mouse look sensitivity factor.
@export var mouse_sensitivity_base: float = 0.05
## Default resting field of view in degrees.
@export var base_fov: float = 75.0
## Field of view applied while sprinting.
@export var sprint_fov: float = 85.0
## Field of view applied while zooming.
@export var zoom_fov: float = 10.0
## Interpolation rate for smooth FOV transitions.
@export var fov_change_speed: float = 12.0

@export_category("Camera Movement")
## Interpolation rate for camera smoothing and bobbing.
@export var lerp_speed: float = 15.0
## Roll angle tilt magnitude applied during strafing movements.
@export var camera_tilt_amount: float = 3.0

@export_category("Wolf Mode Jitter")
## Idle bobbing speed multiplier applied when in wolf form.
@export var wolf_idle_bob_speed_scale: float = 2.0
## Translational noise displacement intensity in meters for wolf idle jitter.
@export var wolf_idle_jitter_pos_intensity: float = 0.003
## Rotational noise displacement intensity in radians for wolf idle pitch/yaw/roll.
@export var wolf_idle_jitter_rot_intensity: float = 0.002
## Frequency rate driving wolf idle simplex noise progression over time.
@export var wolf_idle_noise_frequency: float = 24.0
## Interpolation speed for blending wolf idle jitter weight in and out.
@export var wolf_idle_blend_speed: float = 4.0

## Active mouse sensitivity scalar used for real-time input evaluation.
var mouse_sensitivity: float = 0.05
## Target FOV degree goal for interpolation.
var target_fov: float = 75.0
## Whether sprint FOV adjustments are disabled.
var disable_sprint_fov: bool = false
## Whether zoom state is currently held by player.
var is_using_zoom: bool = false

## Time progression accumulator for head bob calculation.
var head_bobbing_index: float = 0.0
## Current magnitude of the active head bob displacement.
var head_bobbing_current_intensity: float = 0.0
## Calculated 2D vector for camera head bob offset.
var headbob_offset: Vector2 = Vector2.ZERO

## Smooth vertical offset applied when traversing stair steps.
var stair_offset: float = 0.0

## Determines if vertical camera movement is inverted.
var invert_y: bool = false

## Whether screen motion and camera head bobbing are reduced.
var reduce_motion: bool = false

## Pre-allocated simplex noise generator driving erratic wolf idle twitching.
var _wolf_noise: FastNoiseLite = FastNoiseLite.new()
## Time progression accumulator for wolf idle noise sampling.
var _wolf_noise_time: float = 0.0
## Active blend weight transitioning wolf idle jitter in and out.
var _wolf_idle_blend: float = 0.0
## Current wolf transformation state received from event bus.
var _is_wolf_mode: bool = false

## Active aim assist operational mode (0=Off, 1=Mid [Friction], 2=Full [Friction+Adhesion]).
var aim_assist_mode: int = 1
## Aim assist strength multiplier (0.0 to 1.0).
var aim_assist_amount: float = 0.5
## Maximum assist range in meters.
var aim_assist_max_range: float = 50.0
## Current active locked target for assist stickiness.
var _current_assist_target: Node3D = null
## Cached state flag indicating if target is acquired.
var _has_acquired_target: bool = false
## Target data evaluated per frame during update_camera().
var _cached_target_data: Dictionary = {}


## Lifecycle initialization method loading saved preferences and camera state.
func _ready() -> void:
	print("CameraController: Initializing settings.")

	mouse_sensitivity_base = GlobalSettings.get_setting_float("Controls", "mouse_sensitivity", 0.05)
	base_fov = GlobalSettings.get_setting_float("Settings", "base_fov", 75.0)
	disable_sprint_fov = GlobalSettings.get_setting_bool("Settings", "disable_sprint_fov", false)
	invert_y = GlobalSettings.get_setting_bool("Controls", "invert_y", false)
	reduce_motion = GlobalSettings.get_setting_bool("Accessibility", "reduce_motion", false)

	mouse_sensitivity = mouse_sensitivity_base
	target_fov = base_fov

	aim_assist_mode = GlobalSettings.get_setting_int("Gameplay", "aim_assist_mode", 1)
	aim_assist_amount = GlobalSettings.get_setting_float("Gameplay", "aim_assist_amount", 0.5)

	_wolf_noise.seed = randi()
	_wolf_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_wolf_noise.frequency = 0.5

	if Events.has_signal(&"wolf_mode_toggled"):
		Events.wolf_mode_toggled.connect(_on_wolf_mode_toggled)
	if Events.has_signal(&"aim_assist_mode_changed"):
		Events.aim_assist_mode_changed.connect(_on_aim_assist_mode_changed)
	if Events.has_signal(&"aim_assist_amount_changed"):
		Events.aim_assist_amount_changed.connect(_on_aim_assist_amount_changed)

	if is_instance_valid(player_body) and player_body.get(&"is_wolf_mode") == true:
		_is_wolf_mode = true


## Cleans up event listeners when removed from the scene tree.
func _exit_tree() -> void:
	if (
		Events.has_signal(&"wolf_mode_toggled")
		and Events.wolf_mode_toggled.is_connected(_on_wolf_mode_toggled)
	):
		Events.wolf_mode_toggled.disconnect(_on_wolf_mode_toggled)
	if (
		Events.has_signal(&"aim_assist_mode_changed")
		and Events.aim_assist_mode_changed.is_connected(_on_aim_assist_mode_changed)
	):
		Events.aim_assist_mode_changed.disconnect(_on_aim_assist_mode_changed)
	if (
		Events.has_signal(&"aim_assist_amount_changed")
		and Events.aim_assist_amount_changed.is_connected(_on_aim_assist_amount_changed)
	):
		Events.aim_assist_amount_changed.disconnect(_on_aim_assist_amount_changed)


## Sets base mouse sensitivity multiplier and syncs live sensitivity.
## [param new_sens] Target mouse sensitivity value.
func set_mouse_sensitivity(new_sens: float) -> void:
	print("CameraController: Setting base sensitivity to: ", new_sens)
	mouse_sensitivity_base = new_sens
	mouse_sensitivity = new_sens


## Evaluates incoming mouse motion to rotate the player body and camera head smoothly.
## [param event] Mouse motion input event.
## [param is_terminal_mode] Whether terminal focus restricts mouse movement.
## [param is_heavy_lifting] Whether heavy lifting restricts camera yaw/pitch.
## [param _heavy_lift_yaw_base] Yaw constraint baseline angle.
func handle_mouse_input(
	event: InputEventMouseMotion,
	is_terminal_mode: bool,
	is_heavy_lifting: bool,
	_heavy_lift_yaw_base: float
) -> void:
	var active_sens: float = mouse_sensitivity
	if is_terminal_mode:
		active_sens *= 0.5

	var y_multiplier: float = -1.0 if invert_y else 1.0
	var pitch_input: float = event.relative.y * active_sens * y_multiplier
	var yaw_input: float = event.relative.x * active_sens

	if not is_terminal_mode and not is_heavy_lifting and aim_assist_mode > 0:
		var assist_result: Vector2 = _evaluate_aim_assist_adjustments(yaw_input, pitch_input)
		yaw_input = assist_result.x
		pitch_input = assist_result.y

	if is_heavy_lifting:
		head.rotation.y = clampf(
			head.rotation.y - deg_to_rad(yaw_input), deg_to_rad(-15.0), deg_to_rad(15.0)
		)
		head.rotation.x = clampf(
			head.rotation.x - deg_to_rad(pitch_input), deg_to_rad(-15.0), deg_to_rad(89.0)
		)
	else:
		player_body.rotate_y(deg_to_rad(-yaw_input))
		head.rotation.x = clampf(
			head.rotation.x - deg_to_rad(pitch_input), deg_to_rad(-89.0), deg_to_rad(89.0)
		)

	head.rotation.z = 0.0


## Calculates Halo-style friction slowdown and adhesion pull using cached frame target.
func _evaluate_aim_assist_adjustments(yaw_in: float, pitch_in: float) -> Vector2:
	if not is_instance_valid(camera) or _cached_target_data.is_empty():
		return Vector2(yaw_in, pitch_in)

	var target_enemy: Node3D = _cached_target_data.get("target", null) as Node3D
	if not is_instance_valid(target_enemy):
		return Vector2(yaw_in, pitch_in)

	var target_pos: Vector3 = (
		_cached_target_data.get("aim_pos", target_enemy.global_position) as Vector3
	)
	var strength: float = clampf(aim_assist_amount, 0.1, 1.0)

	# 1. Halo Reticle Friction (Active in Mid & Full): Slow down camera panning over target
	var friction_factor: float = clampf(1.0 - (0.55 * strength), 0.35, 1.0)
	var out_yaw: float = yaw_in * friction_factor
	var out_pitch: float = pitch_in * friction_factor

	# 2. Halo Adhesion / Magnetism (Active in Full Mode only)
	if aim_assist_mode >= 2:
		var cam_pos: Vector3 = camera.global_position
		var to_target: Vector3 = (target_pos - cam_pos).normalized()
		var cam_right: Vector3 = camera.global_transform.basis.x.normalized()
		var cam_up: Vector3 = camera.global_transform.basis.y.normalized()

		var yaw_diff: float = rad_to_deg(cam_right.dot(to_target))
		var pitch_diff: float = rad_to_deg(cam_up.dot(to_target))

		var move_mag: float = Vector2(yaw_in, pitch_in).length()
		if move_mag > 0.001:
			var glue_strength: float = 0.28 * strength
			var max_yaw_pull: float = absf(yaw_in) * 0.8
			var max_pitch_pull: float = absf(pitch_in) * 0.8
			var pull_yaw: float = clampf(yaw_diff * glue_strength, -max_yaw_pull, max_yaw_pull)
			var pull_pitch: float = clampf(
				-pitch_diff * glue_strength, -max_pitch_pull, max_pitch_pull
			)
			out_yaw += pull_yaw
			out_pitch += pull_pitch

	return Vector2(out_yaw, out_pitch)


## Locates the best unoccluded enemy target within an angular cone from camera center.
func find_best_aim_assist_target(max_angle_rad: float) -> Dictionary:
	if not is_instance_valid(camera):
		return {}

	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemy")
	if enemies.is_empty():
		return {}

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not is_instance_valid(space_state):
		return {}

	var cam_pos: Vector3 = camera.global_position
	var cam_forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var max_dist_sq: float = aim_assist_max_range * aim_assist_max_range

	var best_node: Node3D = null
	var min_score: float = 999999.0
	var best_aim_pos: Vector3 = Vector3.ZERO

	var exclude: Array[RID] = []
	if is_instance_valid(player_body):
		exclude.append(player_body.get_rid())

	for node: Node in enemies:
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var enemy: Node3D = node as Node3D
		if enemy.is_queued_for_deletion():
			continue

		var aim_pos: Vector3 = enemy.global_position + Vector3(0.0, 0.4, 0.0)
		var dist_sq: float = cam_pos.distance_squared_to(aim_pos)
		if dist_sq > max_dist_sq or dist_sq < 0.2:
			continue

		var dir_to_enemy: Vector3 = (aim_pos - cam_pos).normalized()
		var dot: float = cam_forward.dot(dir_to_enemy)
		if dot <= 0.0:
			continue

		var angle: float = acos(clampf(dot, -1.0, 1.0))
		if angle > max_angle_rad:
			continue

		# Check line of sight occlusion against solid world geometry
		var hit: Dictionary = Utilities.raycast_3d(
			space_state, cam_pos, aim_pos, Types.MASK_SOLID_WORLD, exclude
		)
		if not hit.is_empty():
			continue

		var score: float = angle + (sqrt(dist_sq) / aim_assist_max_range * 0.1)
		if enemy == _current_assist_target:
			score *= 0.7

		if score < min_score:
			min_score = score
			best_node = enemy
			best_aim_pos = aim_pos

	if is_instance_valid(best_node):
		_current_assist_target = best_node
		return {"target": best_node, "aim_pos": best_aim_pos, "angle": min_score}

	_current_assist_target = null
	return {}


## Master frame update routing FOV, tilting, headbobbing, and aim assist scan.
## [param delta] Physics frame delta time in seconds.
## [param input_dir] Current horizontal locomotion input vector.
## [param is_sprinting] Sprint locomotion state flag.
## [param is_crouching] Crouch state flag.
## [param is_grounded] Ground contact status flag.
## [param player_velocity] Current horizontal movement speed.
func update_camera(
	delta: float,
	input_dir: Vector2,
	is_sprinting: bool,
	is_crouching: bool,
	is_grounded: bool,
	player_velocity: float
) -> void:
	if (
		GestureInputManager.is_action_just_pressed("zoom")
		or GestureInputManager.is_action_just_pressed("sprint")
	):
		print("CameraController: update_camera() processing state change.")

	_update_target_tracking()
	_update_fov(delta, is_sprinting, is_grounded, input_dir)
	_update_tilt(delta, input_dir)
	_update_headbob(delta, input_dir, is_sprinting, is_crouching)
	_update_wolf_jitter(delta, input_dir)
	_update_stair_smoothing(delta, player_velocity)


## Updates camera FOV and roll tilt during noclip flight, suppressing headbob.
## [param delta] Frame delta time in seconds.
## [param input_dir] Current horizontal locomotion input vector.
## [param is_sprinting] Sprint locomotion state flag.
func update_noclip_camera(delta: float, input_dir: Vector2, is_sprinting: bool) -> void:
	if (
		GestureInputManager.is_action_just_pressed("zoom")
		or GestureInputManager.is_action_just_pressed("sprint")
	):
		print("CameraController: update_noclip_camera() processing state change.")

	_update_target_tracking()
	_update_fov(delta, is_sprinting, true, input_dir)
	_update_tilt(delta, input_dir)

	_wolf_idle_blend = 0.0
	headbob_offset.y = lerpf(headbob_offset.y, 0.0, delta * lerp_speed)
	headbob_offset.x = lerpf(headbob_offset.x, 0.0, delta * lerp_speed)
	if is_instance_valid(eyes):
		eyes.position.y = headbob_offset.y
		eyes.position.x = headbob_offset.x
		eyes.rotation.x = 0.0
		eyes.rotation.y = 0.0


## Continuous frame scan tracking target acquisition status independent of mouse motion.
func _update_target_tracking() -> void:
	if aim_assist_mode == 0 or not is_instance_valid(camera):
		if _has_acquired_target:
			_has_acquired_target = false
			_cached_target_data.clear()
			if Events.has_signal(&"aim_assist_target_acquired"):
				Events.aim_assist_target_acquired.emit(false, Vector2.ZERO)
		return

	_cached_target_data = find_best_aim_assist_target(deg_to_rad(8.0))
	var target_enemy: Node3D = _cached_target_data.get("target", null) as Node3D
	var acquired: bool = is_instance_valid(target_enemy)
	var screen_pos: Vector2 = Vector2.ZERO

	if acquired:
		var target_pos: Vector3 = (
			_cached_target_data.get("aim_pos", target_enemy.global_position) as Vector3
		)
		if not camera.is_position_behind(target_pos):
			screen_pos = camera.unproject_position(target_pos)
		else:
			acquired = false

	if acquired != _has_acquired_target or (acquired and _has_acquired_target):
		_has_acquired_target = acquired
		if Events.has_signal(&"aim_assist_target_acquired"):
			Events.aim_assist_target_acquired.emit(_has_acquired_target, screen_pos)


## Injects step displacement offset when navigating step height changes.
## [param snap_amount] Step displacement distance in meters.
func add_stair_offset(snap_amount: float) -> void:
	print("CameraController: Applying stair snap offset: ", snap_amount)
	stair_offset -= snap_amount
	stair_offset = clampf(stair_offset, -0.5, 0.5)


## Calculates normalized forward look vector from active camera.
## [return] The unit forward [Vector3].
func get_camera_look_dir() -> Vector3:
	if is_instance_valid(camera):
		return -camera.global_transform.basis.z
	return Vector3.FORWARD


## Calculates normalized right view vector from active camera.
## [return] The unit right [Vector3].
func get_camera_right_dir() -> Vector3:
	if is_instance_valid(camera):
		return camera.global_transform.basis.x
	return Vector3.RIGHT


## Forces pitch and yaw rotation values directly to camera components.
## [param pitch] Camera vertical pitch in radians.
## [param yaw] Body horizontal yaw in radians.
func apply_saved_rotation(pitch: float, yaw: float) -> void:
	print("CameraController: apply_saved_rotation() called.")
	global_rotation = Vector3(pitch, yaw, 0.0)

	if is_instance_valid(head):
		head.rotation.x = pitch

	if is_instance_valid(player_body):
		player_body.rotation.y = yaw


## Resets head yaw rotation back to zero alignment with player body.
func reset_head_yaw() -> void:
	if is_instance_valid(head):
		head.rotation.y = 0.0


## Calculates FOV goals based on zooming, sprint states, and interpolates camera FOV.
## [param delta] Frame delta time in seconds.
## [param is_sprinting] Sprint locomotion state flag.
## [param is_grounded] Ground contact status flag.
## [param input_dir] Current movement vector.
func _update_fov(delta: float, is_sprinting: bool, is_grounded: bool, input_dir: Vector2) -> void:
	var is_valid_sprint: bool = (
		(is_sprinting and input_dir.length() > 0.1)
		or (not is_grounded and target_fov == sprint_fov)
	)
	var is_zoom_pressed: bool = (
		(is_instance_valid(GestureInputManager) and GestureInputManager.is_action_pressed("zoom"))
		or Input.is_action_pressed(&"zoom")
	)

	if is_zoom_pressed:
		target_fov = zoom_fov
		mouse_sensitivity = mouse_sensitivity_base / 10.0
		if not is_using_zoom:
			is_using_zoom = true
			print("CameraController: Camera FOV zoom activated.")
			Events.player_zoomed.emit(true)

	elif is_valid_sprint and not disable_sprint_fov:
		target_fov = sprint_fov
		mouse_sensitivity = mouse_sensitivity_base
		if is_using_zoom:
			is_using_zoom = false
			print("CameraController: Sprint overriding zoom.")
			Events.player_zoomed.emit(false)

	else:
		target_fov = base_fov
		mouse_sensitivity = mouse_sensitivity_base
		if is_using_zoom:
			is_using_zoom = false
			print("CameraController: Camera FOV zoom deactivated.")
			Events.player_zoomed.emit(false)

	if is_instance_valid(camera):
		camera.fov = lerpf(camera.fov, target_fov, delta * fov_change_speed)


## Smoothly rolls the camera roll axis when strafing.
## [param delta] Frame delta time in seconds.
## [param input_dir] Current movement vector.
func _update_tilt(delta: float, input_dir: Vector2) -> void:
	if is_instance_valid(eyes):
		var target_tilt: float = 0.0 if reduce_motion else input_dir.x * camera_tilt_amount
		eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(-target_tilt), delta * lerp_speed)


## Updates procedural sine-wave head bobbing offsets for active movement.
## [param delta] Frame delta time in seconds.
## [param input_dir] Current movement vector.
## [param is_sprinting] Sprint locomotion state flag.
## [param is_crouching] Crouch state flag.
## [param intensity_modifier] Additional scaling multiplier for shake/bob.
func _update_headbob(
	delta: float,
	input_dir: Vector2,
	is_sprinting: bool,
	is_crouching: bool,
	intensity_modifier: float = 1.0
) -> void:
	if not is_instance_valid(eyes):
		return

	if reduce_motion:
		headbob_offset = Vector2.ZERO
		eyes.position.y = stair_offset
		eyes.position.x = 0.0
		return

	var bob_speed: float = HEAD_BOBBING_IDLE_SPEED

	if is_sprinting and input_dir != Vector2.ZERO:
		bob_speed = HEAD_BOBBING_SPRINTING_SPEED
		head_bobbing_current_intensity = HEAD_BOBBING_SPRINTING_INTENSITY
	elif input_dir != Vector2.ZERO:
		if is_crouching:
			bob_speed = HEAD_BOBBING_CROUCHING_SPEED
			head_bobbing_current_intensity = HEAD_BOBBING_CROUCHING_INTENSITY
		else:
			bob_speed = HEAD_BOBBING_WALKING_SPEED
			head_bobbing_current_intensity = HEAD_BOBBING_WALKING_INTENSITY
	else:
		head_bobbing_current_intensity = HEAD_BOBBING_IDLE_INTENSITY
		if _is_wolf_mode:
			bob_speed = (
				HEAD_BOBBING_IDLE_SPEED
				* (1.0 + (_wolf_idle_blend * (wolf_idle_bob_speed_scale - 1.0)))
			)

	var movement_multiplier: float = 1.0 if input_dir.length() > 0.1 else 0.5
	head_bobbing_index += bob_speed * delta * movement_multiplier

	var target_bob_y: float = (
		sin(head_bobbing_index) * (head_bobbing_current_intensity / 2.0) * intensity_modifier
	)
	var target_bob_x: float = (
		sin(head_bobbing_index / 2.0) * head_bobbing_current_intensity * intensity_modifier
	)

	headbob_offset.y = lerpf(headbob_offset.y, target_bob_y, delta * lerp_speed)
	headbob_offset.x = lerpf(headbob_offset.x, target_bob_x, delta * lerp_speed)

	eyes.position.y = headbob_offset.y + stair_offset
	eyes.position.x = headbob_offset.x


## Computes high-frequency erratic jitter on camera position and rotation during wolf idle.
## [param delta] Physics frame delta time in seconds.
## [param input_dir] Current horizontal locomotion input vector.
func _update_wolf_jitter(delta: float, input_dir: Vector2) -> void:
	if not is_instance_valid(eyes):
		return

	var is_idle: bool = _is_wolf_mode and input_dir == Vector2.ZERO and not reduce_motion
	var target_blend: float = 1.0 if is_idle else 0.0
	_wolf_idle_blend = move_toward(_wolf_idle_blend, target_blend, delta * wolf_idle_blend_speed)

	if _wolf_idle_blend <= 0.0:
		eyes.rotation.x = 0.0
		eyes.rotation.y = 0.0
		return

	_wolf_noise_time += delta * wolf_idle_noise_frequency

	var sample_pos_x: float = _wolf_noise.get_noise_2d(_wolf_noise_time, 0.0)
	var sample_pos_y: float = _wolf_noise.get_noise_2d(0.0, _wolf_noise_time)
	var sample_rot_x: float = _wolf_noise.get_noise_2d(_wolf_noise_time, 100.0)
	var sample_rot_y: float = _wolf_noise.get_noise_2d(100.0, _wolf_noise_time)
	var sample_rot_z: float = _wolf_noise.get_noise_2d(_wolf_noise_time, _wolf_noise_time)

	var current_pos_intensity: float = wolf_idle_jitter_pos_intensity * _wolf_idle_blend
	var current_rot_intensity: float = wolf_idle_jitter_rot_intensity * _wolf_idle_blend

	eyes.position.x += sample_pos_x * current_pos_intensity
	eyes.position.y += sample_pos_y * current_pos_intensity

	eyes.rotation.x = sample_rot_x * current_rot_intensity
	eyes.rotation.y = sample_rot_y * current_rot_intensity
	eyes.rotation.z = sample_rot_z * current_rot_intensity


## Decays stair displacement back to zero over time.
## [param delta] Frame delta time in seconds.
## [param player_velocity] Current horizontal movement speed.
func _update_stair_smoothing(delta: float, player_velocity: float) -> void:
	if stair_offset == 0.0:
		return

	var move_amount: float = maxf(player_velocity * delta, 2.5 * delta)
	stair_offset = move_toward(stair_offset, 0.0, move_amount)


## Handles wolf form toggle event to activate idle jitter styling.
## [param is_active] True when entering wolf form; false otherwise.
func _on_wolf_mode_toggled(is_active: bool) -> void:
	print("CameraController: _on_wolf_mode_toggled() -> ", is_active)
	_is_wolf_mode = is_active


## Handles external aim assist mode changes from the global event bus.
func _on_aim_assist_mode_changed(mode: int) -> void:
	print("CameraController: _on_aim_assist_mode_changed() -> ", mode)
	aim_assist_mode = mode
	if aim_assist_mode == 0 and _has_acquired_target:
		_has_acquired_target = false
		_cached_target_data.clear()
		if Events.has_signal(&"aim_assist_target_acquired"):
			Events.aim_assist_target_acquired.emit(false, Vector2.ZERO)


## Handles external aim assist strength changes from UI slider adjustments.
func _on_aim_assist_amount_changed(amount: float) -> void:
	print("CameraController: _on_aim_assist_amount_changed() -> ", amount)
	aim_assist_amount = amount
