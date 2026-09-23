## Handles downhill sliding momentum, lateral steering, and snow deformation.
class_name StateSlide
extends PlayerState

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Slide Physics")
## Downward slide acceleration rate.
@export var slide_acceleration: float = 15.0
## Maximum allowed horizontal slide speed.
@export var max_slide_speed: float = 25.0
## Lateral steering sensitivity while sliding.
@export var slide_steering_speed: float = 8.0


# --------------------------------------
# STATE METHODS
# --------------------------------------
## Locks player collision into crouched stance on slide initiation.
func enter(_msg: Dictionary = {}) -> void:
	print("StateSlide: enter() called. Player locked into slide.")
	var loco: Node = player.locomotion_component
	if is_instance_valid(loco):
		loco.crouching = true
		loco.standing_collision.disabled = true
		loco.crouching_collision.disabled = false


## Restores default standing collision if overhead clearance allows.
func exit() -> void:
	print("StateSlide: exit() called. Restoring default collision state.")
	var loco: Node = player.locomotion_component
	if is_instance_valid(loco) and not loco.crouch_cast_check.is_colliding():
		print("StateSlide: Headroom clear. Standing up.")
		loco.crouching = false
		loco.standing_collision.disabled = false
		loco.crouching_collision.disabled = true


## Updates downhill momentum, steering, gravity, and decoupled components.
func physics_update(delta: float) -> void:
	var loco: Node = player.locomotion_component
	var interact: Node = player.interaction_component

	if not player.is_on_floor():
		print("StateSlide: Floor lost. Transitioning to Air.")
		state_machine.transition_to("Air")
		return

	var floor_normal: Vector3 = player.get_floor_normal()

	if floor_normal.y > 0.99 and player.velocity.length_squared() < 1.0:
		print("StateSlide: Ground flat, low speed. Transitioning to Ground.")
		state_machine.transition_to("Ground")
		return

	var downhill_dir: Vector3 = Vector3.DOWN.slide(floor_normal)
	if downhill_dir.length_squared() > 0.0001:
		downhill_dir = downhill_dir.normalized()
	else:
		downhill_dir = Vector3.ZERO

	player.velocity += downhill_dir * slide_acceleration * delta

	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")

	var camera_right: Vector3 = Vector3.RIGHT
	if is_instance_valid(interact) and is_instance_valid(interact.get("camera")):
		camera_right = (interact.camera.global_transform.basis.x.normalized())
	elif is_instance_valid(player.camera_controller):
		camera_right = (player.camera_controller.camera.global_transform.basis.x.normalized())

	var steer_dir: Vector3 = camera_right.slide(floor_normal)
	if steer_dir.length_squared() > 0.0001:
		steer_dir = steer_dir.normalized()
	else:
		steer_dir = Vector3.ZERO

	var current_lateral: Vector3 = player.velocity.project(steer_dir)
	var forward_momentum: Vector3 = player.velocity - current_lateral

	var target_lateral: Vector3 = steer_dir * (input_dir.x * slide_steering_speed)
	current_lateral = current_lateral.lerp(target_lateral, 10.0 * delta)
	player.velocity = forward_momentum + current_lateral

	if player.velocity.length_squared() > (max_slide_speed * max_slide_speed):
		player.velocity = player.velocity.limit_length(max_slide_speed)

	var current_gravity: float = loco.gravity if is_instance_valid(loco) else 9.8
	player.velocity.y -= current_gravity * delta

	player.move_and_slide()
	_update_components(delta, input_dir)


## Updates camera, footsteps, and slide deformation across subsystems.
func _update_components(delta: float, input_dir: Vector2) -> void:
	var loco: Node = player.locomotion_component
	var interact: Node = player.interaction_component

	if is_instance_valid(player.camera_controller):
		player.camera_controller.update_camera(
			delta, input_dir, false, true, true, player.velocity.length()
		)

	if is_instance_valid(loco) and is_instance_valid(loco.get("footstep_manager")):
		var fm: FootstepManager = loco.footstep_manager as FootstepManager
		fm.process_surface_and_footsteps(delta, true, player.velocity.length(), false, true)
		var speed_ratio: float = player.velocity.length() / max_slide_speed
		fm.carve_slide(delta, speed_ratio)

	if is_instance_valid(interact) and is_instance_valid(interact.get("interaction_scanner")):
		interact.interaction_scanner.process_interaction(delta)
