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
	player.standing_collision.disabled = false
	player.crouching_collision.disabled = true
	head_in_water = false
	chest_in_water = false
	was_head_in_water = false
	just_water_jumped = false
	
	print("--- ENTERED WATER ---")


func exit() -> void:
	# Ensure VFX and states are cleared if we get teleported or launched out
	if head_in_water:
		player.vfx_manager.trigger_surface_wipe()
		_update_flashlight_underwater(false, 1.0) # Reset flashlight
		
	head_in_water = false
	chest_in_water = false
	player.camera_controller.eyes.rotation.z = 0.0
	
	print("--- LEFT WATER ---")


func physics_update(delta: float) -> void:
	# 1. Query Water Depth
	_calculate_water_depth()

	# 2. Read Input
	var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	
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

	# --- CHECK HEAD ---
	query.position = player.camera.global_position - Vector3(0.0, 0.2, 0.0)
	var head_results: Array[Dictionary] = space_state.intersect_point(query)
	for result: Dictionary in head_results:
		var collider: Object = result.get("collider")
		if collider is Area3D and collider.is_in_group("water_area"):
			head_in_water = true
			break

	# --- CHECK CHEST ---
	query.position = player.camera.global_position - Vector3(0.0, 1.0, 0.0)
	var chest_results: Array[Dictionary] = space_state.intersect_point(query)
	for result: Dictionary in chest_results:
		var collider: Object = result.get("collider")
		if collider is Area3D and collider.is_in_group("water_area"):
			chest_in_water = true
			break


func _apply_swim_velocity(delta: float, input_dir: Vector2) -> void:
	player.head.position.y = lerpf(player.head.position.y, 1.8, delta * player.default_lerp_speed)

	var swim_dir: Vector3 = (player.camera.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity: Vector3 = swim_dir * player.swimming_speed
	var actively_swimming_vertical: bool = false
	just_water_jumped = false

	# Handle Ascend / Descend Input
	if Input.is_action_just_pressed("jump") and not head_in_water:
		
		# ---> THE FIX: Tell the vault controller to look for a ledge first! <---
		player.vault_controller.process_vault_scan()
		
		if player.vault_controller.can_vault_current_ledge:
			if player.vault_controller.try_vault(player.crouching):
				actively_swimming_vertical = true
				just_water_jumped = true
				state_machine.transition_to("Vault")
				return
				
		# ---> BONUS: Shallow Water Jump Fix <---
		# If we failed the vault, but our feet are on the floor in shallow water, just do a normal jump!
		elif player.is_on_floor() and not chest_in_water:
			target_velocity.y = 4.5 # JUMP_VELOCITY from your Air state
			actively_swimming_vertical = true
			just_water_jumped = true

	# Handle Buoyancy Zones
	if not actively_swimming_vertical:
		if head_in_water:
			# ZONE 3: UNDERWATER (Horror pull)
			target_velocity.y = SINK_SPEED
		elif chest_in_water:
			# ZONE 2: THE SURFACE (Safe zone)
			target_velocity.y = 0.0
		else:
			# ZONE 1: ENTERING WATER (Plunge momentum)
			if player.velocity.y < -1.0:
				target_velocity.y = player.velocity.y
			else:
				target_velocity.y = PLUNGE_SPEED

	# Apply XZ Velocity
	var target_xz := Vector2(target_velocity.x, target_velocity.z)
	var current_xz := Vector2(player.velocity.x, player.velocity.z)
	current_xz = current_xz.lerp(target_xz, 8.0 * delta)
	
	player.velocity.x = current_xz.x
	player.velocity.z = current_xz.y

	# Apply Y Velocity
	if not just_water_jumped:
		player.velocity.y = lerpf(player.velocity.y, target_velocity.y, 4.0 * delta)


func _handle_camera_and_vfx(delta: float, input_dir: Vector2) -> void:
	# 1. Camera Tilt & Animations
	var target_anim: String = "RESET"
	var target_tilt: float = 0.0

	if input_dir.x > 0.1:
		target_anim = "swimming_underwater_sideways_right"
		target_tilt = deg_to_rad(player.camera_controller.camera_tilt_amount * 2.0)
	elif input_dir.x < -0.1:
		target_anim = "swimming_underwater_sideways_left"
		target_tilt = deg_to_rad(-player.camera_controller.camera_tilt_amount * 2.0)
	elif absf(input_dir.y) > 0.1:
		target_anim = "swimming"
	elif (Input.is_action_pressed("jump") or Input.is_action_pressed("sprint")) and head_in_water:
		target_anim = "swimming_up"

	# if player.camera_anims.current_animation != target_anim:
	# 	player.camera_anims.play(target_anim, 2.0)

	player.camera_controller.eyes.rotation.z = lerpf(
		player.camera_controller.eyes.rotation.z, target_tilt, delta * (player.default_lerp_speed / 3.0)
	)

	# 2. Flashlight & Screen VFX Updates
	_update_flashlight_underwater(head_in_water, delta)

	if head_in_water:
		if not was_head_in_water:
			player.vfx_manager.set_underwater_state(true)
	elif was_head_in_water and not head_in_water:
		player.vfx_manager.trigger_surface_wipe()


func _update_flashlight_underwater(is_submerged: bool, delta: float) -> void:
	# Assuming your FlashlightController exports or manages base values. 
	# Safely modifying the spotlight directly or telling the controller:
	if player.flashlight_controller and player.flashlight_controller.flashlight:
		var base_energy: float = player.flashlight_controller.base_energy
		var target_energy: float = base_energy * 4.0 if is_submerged else base_energy
		
		# Smooth transition via the controller or directly if exposed
		player.flashlight_controller.flashlight.light_energy = lerpf(
			player.flashlight_controller.flashlight.light_energy, target_energy, 4.0 * delta
		)


func _check_transitions() -> void:
	if player.current_water_node == null:
		state_machine.transition_to("Air")
		return

	# Restored: Hand control to StateGround for shallow wading
	if player.is_on_floor() and not chest_in_water and not head_in_water:
		state_machine.transition_to("Ground")
