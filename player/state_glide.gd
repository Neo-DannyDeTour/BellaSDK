## Handles mid-air gliding mechanics, aerodynamic banking, and descent in [StateGlide].
class_name StateGlide
extends PlayerState

## Indicates if debug commands such as manual updrafts are permitted.
var is_debug_allowed: bool = OS.has_feature("debug")

## Base forward flight speed in meters per second while gliding.
@export var forward_speed: float = 12.0

## Maximum downward descent velocity permitted while glider is active.
@export var max_fall_speed: float = 2.5

## Upward impulse applied when jumping mid-glide in debug builds.
@export var debug_updraft_force: float = 15.0

## Angular rotation speed scalar when steering the glider horizontally.
@export var turn_speed: float = 2.0

## Maximum visual roll banking angle in degrees when steering laterally.
@export var max_bank_angle: float = 15.0

## Damping rate at which glider visual roll banking angle interpolates.
@export var bank_lerp_speed: float = 5.0


## Activates glider mesh visuals and locks out heavy item interactions.
func enter(_msg: Dictionary = {}) -> void:
	print("StateGlide: enter() called. Deploying glider.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	if p.has_method(&"set_glider_visible"):
		p.call(&"set_glider_visible", true)

	var interact: PlayerInteractionComponent = p.interaction_component as PlayerInteractionComponent
	if is_instance_valid(interact):
		interact.is_heavy_lifting = true


## Stows glider visuals, resets view transforms, and unlocks interactions.
func exit() -> void:
	print("StateGlide: exit() called. Stowing glider.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	if p.has_method(&"set_glider_visible"):
		p.call(&"set_glider_visible", false)

	var interact: PlayerInteractionComponent = p.interaction_component as PlayerInteractionComponent
	if is_instance_valid(interact):
		interact.is_heavy_lifting = false

		var weapon_holder: Node3D = interact.get(&"weapon_holder") as Node3D
		if is_instance_valid(weapon_holder):
			weapon_holder.rotation_degrees.z = 0.0
			weapon_holder.rotation.x = 0.0
			weapon_holder.rotation.y = 0.0

	var cam_ctrl: CameraController = p.camera_controller
	if is_instance_valid(cam_ctrl) and is_instance_valid(cam_ctrl.camera):
		cam_ctrl.camera.rotation.y = 0.0
		cam_ctrl.camera.rotation.z = 0.0


## Executes glide physics, banking, input steering, and transitions.
func physics_update(delta: float) -> void:
	print("StateGlide: physics_update() processing glide aerodynamics.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	_apply_glide_physics(delta)
	_handle_debug_updraft()

	var loco: PlayerLocomotionComponent = p.locomotion_component as PlayerLocomotionComponent
	if is_instance_valid(loco):
		loco.set(&"last_velocity", p.velocity)

	p.move_and_slide()
	_check_transitions()
	_update_components(delta)


## Applies glide gravity, yaw steering, and damped momentum via [MathUtils].
func _apply_glide_physics(delta: float) -> void:
	print("StateGlide: _apply_glide_physics() calculating descent vectors.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	var loco: PlayerLocomotionComponent = p.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = p.interaction_component as PlayerInteractionComponent

	var gravity: float = loco.gravity if is_instance_valid(loco) else 9.8
	p.velocity.y = move_toward(p.velocity.y, -max_fall_speed, gravity * delta)

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_bank_glider(input_dir.x, delta)

	if input_dir.x != 0.0:
		p.rotate_y(-input_dir.x * turn_speed * delta)

	if is_instance_valid(interact):
		var weapon_holder: Node3D = interact.get(&"weapon_holder") as Node3D
		if is_instance_valid(weapon_holder):
			weapon_holder.global_rotation.x = p.global_rotation.x
			weapon_holder.global_rotation.y = p.global_rotation.y

	var forward_dir: Vector3 = -p.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var target_vel: Vector3 = forward_dir * forward_speed
	var air_lerp: float = loco.air_lerp_speed if is_instance_valid(loco) else 1.0

	p.velocity.x = MathUtils.damp(p.velocity.x, target_vel.x, air_lerp, delta)
	p.velocity.z = MathUtils.damp(p.velocity.z, target_vel.z, air_lerp, delta)


## Updates visual roll angle of weapon holder via [MathUtils].
func _bank_glider(input_x: float, delta: float) -> void:
	print("StateGlide: _bank_glider() setting roll rotation degrees.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	var interact: PlayerInteractionComponent = p.interaction_component as PlayerInteractionComponent
	if is_instance_valid(interact):
		var weapon_holder: Node3D = interact.get(&"weapon_holder") as Node3D
		if is_instance_valid(weapon_holder):
			var target_bank: float = -input_x * max_bank_angle
			weapon_holder.rotation_degrees.z = MathUtils.damp(
				weapon_holder.rotation_degrees.z, target_bank, bank_lerp_speed, delta
			)


## Applies vertical updraft impulse upon jump input in debug environments.
func _handle_debug_updraft() -> void:
	print("StateGlide: _handle_debug_updraft() checking debug input.")
	if not is_debug_allowed:
		return

	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	if GestureInputManager.is_action_just_pressed(&"jump"):
		print("StateGlide: Updraft triggered. Applying vertical force.")
		p.velocity.y = debug_updraft_force


## Evaluates landing and cancel inputs to transition to ground or air.
func _check_transitions() -> void:
	print("StateGlide: _check_transitions() evaluating state exits.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	if p.is_on_floor():
		print("StateGlide: Detected floor. Transitioning to Ground.")
		state_machine.transition_to(&"Ground")
		return

	if GestureInputManager.is_action_just_pressed(&"crouch"):
		print("StateGlide: Detected crouch input. Cancelling glide.")
		state_machine.transition_to(&"Air")


## Updates camera head motion and interaction scanner while gliding.
func _update_components(delta: float) -> void:
	print("StateGlide: _update_components() polling camera and scanner.")
	var p: Player = player as Player
	if not is_instance_valid(p):
		return

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	var cam_ctrl: CameraController = p.camera_controller
	if is_instance_valid(cam_ctrl):
		cam_ctrl.update_camera(delta, input_dir, false, false, false, p.velocity.length())

	var interact: PlayerInteractionComponent = p.interaction_component as PlayerInteractionComponent
	if not is_instance_valid(interact):
		return

	if interact.has_method(&"process_interaction"):
		interact.call(&"process_interaction", delta)
	else:
		var scanner: Object = interact.get(&"interaction_scanner") as Object
		if is_instance_valid(scanner) and scanner.has_method(&"process_interaction"):
			scanner.call(&"process_interaction", delta)
