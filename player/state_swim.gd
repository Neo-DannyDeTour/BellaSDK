class_name StateSwim
extends PlayerState

# --------------------------------------
# CONSTANTS & VARIABLES
# --------------------------------------
const SINK_SPEED: float = -1.8
const PLUNGE_SPEED: float = -5.0

var head_in_water: bool = false
var chest_in_water: bool = false
var was_head_in_water: bool = false
var just_water_jumped: bool = false


func enter(_msg: Dictionary = {}) -> void:
	print("StateSwim: enter() called. Setting up water physics.")

	var loco := player.locomotion_component as PlayerLocomotionComponent
	loco.standing_collision.disabled = false
	loco.crouching_collision.disabled = true

	head_in_water = false
	chest_in_water = false
	was_head_in_water = false
	just_water_jumped = false


func exit() -> void:
	print("StateSwim: exit() called. Cleaning up water state.")

	if head_in_water:
		var vfx: Node = player.environment_component.vfx_manager
		if is_instance_valid(vfx) and vfx.has_method("trigger_surface_wipe"):
			vfx.trigger_surface_wipe()

		_update_flashlight_underwater(false, 1.0)

	head_in_water = false
	chest_in_water = false
	player.camera_controller.eyes.rotation.z = 0.0


func physics_update(delta: float) -> void:
	# 1. Query Water Depth
	_calculate_water_depth()

	# 2. Read Input
	var input_dir := Input.get_vector("left", "right", "forward", "backward")

	# 3. Process Physics
	_apply_swim_velocity(delta, input_dir)
	player.move_and_slide()

	# 4. Process Camera, Visuals, and Exits
	_handle_camera_and_vfx(delta, input_dir)
	_check_transitions()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
func _calculate_water_depth() -> void:
	was_head_in_water = head_in_water
	head_in_water = false
	chest_in_water = false

	var space_state := player.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collide_with_areas = true
	query.collide_with_bodies = false

	# Use the actual camera node managed by the controller as the positional anchor
	var cam_pos: Vector3 = player.camera_controller.camera.global_position

	# --- CHECK HEAD ---
	query.position = cam_pos - Vector3(0.0, 0.2, 0.0)
	var head_results: Array[Dictionary] = space_state.intersect_point(query)
	for result: Dictionary in head_results:
		var collider: Object = result.get("collider")
		if collider is Area3D and collider.is_in_group("water_area"):
			head_in_water = true
			break

	# --- CHECK CHEST ---
	query.position = cam_pos - Vector3(0.0, 1.0, 0.0)
	var chest_results: Array[Dictionary] = space_state.intersect_point(query)
	for result: Dictionary in chest_results:
		var collider: Object = result.get("collider")
		if collider is Area3D and collider.is_in_group("water_area"):
			chest_in_water = true
			break


func _apply_swim_velocity(delta: float, input_dir: Vector2) -> void:
	var loco := player.locomotion_component as PlayerLocomotionComponent

	loco.head.position.y = lerpf(loco.head.position.y, 1.8, delta * loco.default_lerp_speed)

	var input_vec := Vector3(input_dir.x, 0.0, input_dir.y)
	var cam_basis: Basis = player.camera_controller.camera.global_transform.basis
	var swim_dir := (cam_basis * input_vec).normalized()

	# Now the compiler knows loco.swimming_speed is a float!
	var target_velocity: Vector3 = swim_dir * loco.swimming_speed

	var actively_swimming_vertical: bool = false
	just_water_jumped = false

	# 1. Handle Vaulting or Jumping Out
	if Input.is_action_just_pressed("jump") and not head_in_water:
		var vault_ctrl: Node = player.environment_component.vault_controller
		vault_ctrl.process_vault_scan()

		if vault_ctrl.get("can_vault_current_ledge"):
			if vault_ctrl.try_vault(loco.crouching):
				print("StateSwim: Vault successful. Transitioning to Vault.")
				actively_swimming_vertical = true
				just_water_jumped = true
				state_machine.transition_to("Vault")
				return

		elif player.is_on_floor() and not chest_in_water:
			print("StateSwim: Shallow water jump. Transitioning to Air.")
			target_velocity.y = 4.5
			actively_swimming_vertical = true
			just_water_jumped = true
			state_machine.transition_to("Air")
			return

	# 2. Handle Vertical Swimming (Up / Down)
	if Input.is_action_pressed("jump") and head_in_water:
		target_velocity.y = loco.swim_up_speed
		actively_swimming_vertical = true
	elif Input.is_action_pressed("crouch") and (head_in_water or chest_in_water):
		target_velocity.y = -loco.swim_up_speed
		actively_swimming_vertical = true

	# 3. Handle Buoyancy Zones
	if not actively_swimming_vertical:
		if head_in_water:
			target_velocity.y = SINK_SPEED
		elif chest_in_water:
			target_velocity.y = 0.0
		else:
			if player.velocity.y < -1.0:
				target_velocity.y = player.velocity.y
			else:
				target_velocity.y = PLUNGE_SPEED

	# 4. Apply XZ Velocity
	var target_xz := Vector2(target_velocity.x, target_velocity.z)
	var current_xz := Vector2(player.velocity.x, player.velocity.z)
	current_xz = current_xz.lerp(target_xz, 8.0 * delta)

	player.velocity.x = current_xz.x
	player.velocity.z = current_xz.y

	# 5. Apply Y Velocity
	if not just_water_jumped:
		player.velocity.y = lerpf(player.velocity.y, target_velocity.y, 4.0 * delta)


func _handle_camera_and_vfx(delta: float, input_dir: Vector2) -> void:
	var target_tilt: float = 0.0
	var loco := player.locomotion_component as PlayerLocomotionComponent

	if input_dir.x > 0.1:
		target_tilt = deg_to_rad(player.camera_controller.camera_tilt_amount * 2.0)
	elif input_dir.x < -0.1:
		target_tilt = deg_to_rad(-player.camera_controller.camera_tilt_amount * 2.0)

	player.camera_controller.eyes.rotation.z = lerpf(
		player.camera_controller.eyes.rotation.z,
		target_tilt,
		delta * (loco.default_lerp_speed / 3.0)
	)

	_update_flashlight_underwater(head_in_water, delta)

	var vfx: Node = player.environment_component.vfx_manager
	if is_instance_valid(vfx):
		if head_in_water and not was_head_in_water:
			if vfx.has_method("set_underwater_state"):
				vfx.set_underwater_state(true)
		elif was_head_in_water and not head_in_water:
			if vfx.has_method("trigger_surface_wipe"):
				vfx.trigger_surface_wipe()

			# --- NEW: Trigger splash sound exactly when head breaks surface ---
			var water_node: Node = player.environment_component.current_water_node
			if is_instance_valid(water_node) and water_node.has_method("play_splash_sound"):
				print("StateSwim _handle_camera_and_vfx: Head broke surface. Triggering splash.")
				# We use maxf with 10.0 to ensure a solid baseline volume multiplier
				var exit_speed: float = maxf(absf(player.velocity.y), 10.0)
				water_node.play_splash_sound(player.global_position, exit_speed)


func _update_flashlight_underwater(is_submerged: bool, delta: float) -> void:
	# Safely checks the interaction component or main player for the flashlight
	var flash_ctrl: Node = player.get("flashlight_controller")
	if flash_ctrl == null and player.get("interaction_component"):
		flash_ctrl = player.interaction_component.get("flashlight_controller")

	if is_instance_valid(flash_ctrl) and flash_ctrl.get("flashlight"):
		var base_energy: float = flash_ctrl.get("base_energy")
		var target_energy: float = base_energy * 4.0 if is_submerged else base_energy

		flash_ctrl.flashlight.light_energy = lerpf(
			flash_ctrl.flashlight.light_energy, target_energy, 4.0 * delta
		)


func _check_transitions() -> void:
	if player.environment_component.current_water_node == null:
		print("StateSwim: No active water node. Transitioning to Air.")
		state_machine.transition_to("Air")
		return

	if player.is_on_floor() and not chest_in_water and not head_in_water:
		print("StateSwim: Exiting shallow water. Transitioning to Ground.")
		state_machine.transition_to("Ground")
