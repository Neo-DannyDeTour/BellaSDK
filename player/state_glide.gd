## Handles mid-air gliding mechanics, aerodynamic banking, and slow descent in [StateGlide].
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
	if player.has_method(&"set_glider_visible"):
		player.call(&"set_glider_visible", true)

	player.interaction_component.is_heavy_lifting = true


## Stows glider visuals, resets view transforms, and unlocks interactions.
func exit() -> void:
	print("StateGlide: exit() called. Stowing glider.")
	if player.has_method(&"set_glider_visible"):
		player.call(&"set_glider_visible", false)

	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)
	interact.is_heavy_lifting = false

	if is_instance_valid(interact.get(&"weapon_holder") as Node3D):
		var weapon_holder: Node3D = interact.get(&"weapon_holder") as Node3D
		weapon_holder.rotation_degrees.z = 0.0
		weapon_holder.rotation.x = 0.0
		weapon_holder.rotation.y = 0.0

	if is_instance_valid(player.camera_controller):
		player.camera_controller.camera.rotation.y = 0.0
		player.camera_controller.camera.rotation.z = 0.0


## Executes glide physics, banking, input steering, and transitions.
func physics_update(delta: float) -> void:
	print("StateGlide: physics_update() processing glide aerodynamics.")
	_apply_glide_physics(delta)
	_handle_debug_updraft()

	if is_instance_valid(player.locomotion_component):
		player.locomotion_component.set(&"last_velocity", player.velocity)

	player.move_and_slide()
	_check_transitions()
	_update_components(delta)


## Applies glide gravity, yaw steering, and damped forward momentum via [MathUtils].
func _apply_glide_physics(delta: float) -> void:
	print("StateGlide: _apply_glide_physics() calculating descent vectors.")
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)

	var gravity: float = loco.gravity if is_instance_valid(loco) else 9.8
	player.velocity.y = move_toward(player.velocity.y, -max_fall_speed, gravity * delta)

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_bank_glider(input_dir.x, delta)

	if input_dir.x != 0.0:
		player.rotate_y(-input_dir.x * turn_speed * delta)

	if is_instance_valid(interact.get(&"weapon_holder") as Node3D):
		var weapon_holder: Node3D = interact.get(&"weapon_holder") as Node3D
		weapon_holder.global_rotation.x = player.global_rotation.x
		weapon_holder.global_rotation.y = player.global_rotation.y

	var forward_dir: Vector3 = -player.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var target_vel: Vector3 = forward_dir * forward_speed
	var air_lerp: float = loco.air_lerp_speed if is_instance_valid(loco) else 1.0

	player.velocity.x = MathUtils.damp(player.velocity.x, target_vel.x, air_lerp, delta)
	player.velocity.z = MathUtils.damp(player.velocity.z, target_vel.z, air_lerp, delta)


## Updates visual roll angle of weapon holder for aerodynamic banking via [MathUtils].
func _bank_glider(input_x: float, delta: float) -> void:
	print("StateGlide: _bank_glider() setting roll rotation degrees.")
	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)

	if is_instance_valid(interact.get(&"weapon_holder") as Node3D):
		var weapon_holder: Node3D = interact.get(&"weapon_holder") as Node3D
		var target_bank: float = -input_x * max_bank_angle
		weapon_holder.rotation_degrees.z = MathUtils.damp(
			weapon_holder.rotation_degrees.z, target_bank, bank_lerp_speed, delta
		)


## Applies vertical updraft impulse upon jump input in debug environments.
func _handle_debug_updraft() -> void:
	print("StateGlide: _handle_debug_updraft() checking debug input.")
	if not is_debug_allowed:
		return

	if GestureInputManager.is_action_just_pressed(&"jump"):
		print("StateGlide: _handle_debug_updraft() triggered. Applying vertical force.")
		player.velocity.y = debug_updraft_force


## Evaluates landing and cancel inputs to transition to ground or air.
func _check_transitions() -> void:
	print("StateGlide: _check_transitions() evaluating state exits.")
	if player.is_on_floor():
		print("StateGlide: _check_transitions() detected floor. Transitioning to Ground.")
		state_machine.transition_to(&"Ground")
		return

	if GestureInputManager.is_action_just_pressed(&"crouch"):
		print("StateGlide: _check_transitions() detected crouch input. Cancelling glide.")
		state_machine.transition_to(&"Air")


## Updates camera head motion and interaction scanner while gliding.
func _update_components(delta: float) -> void:
	print("StateGlide: _update_components() polling camera and scanner.")
	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	player.camera_controller.update_camera(
		delta, input_dir, false, false, false, player.velocity.length()
	)

	var interact: PlayerInteractionComponent = (
		player.interaction_component as PlayerInteractionComponent
	)
	if interact.has_method(&"process_interaction"):
		interact.call(&"process_interaction", delta)
	elif (
		interact.get(&"interaction_scanner")
		and interact.get(&"interaction_scanner").has_method(&"process_interaction")
	):
		interact.get(&"interaction_scanner").call(&"process_interaction", delta)
