## A player state handling aquatic locomotion, buoyancy, and visual effects when submerged.
class_name StateSwim
extends PlayerState

## Constant vertical velocity applied when the player's head is submerged and no input is given.
const SINK_SPEED: float = -1.8

## Constant vertical velocity applied when plunging into water before buoyancy normalizes.
const PLUNGE_SPEED: float = -5.0

## Interval in seconds between consecutive drowning damage ticks once oxygen depletes.
const DROWN_TICK_INTERVAL: float = 0.5

## Amount of damage dealt to player health per drowning damage tick.
const DROWN_DAMAGE_PER_TICK: int = 25

## Maximum duration in seconds the player can remain submerged before drowning.
@export var max_swim_duration: float = 10.0

## Tracks if the player's camera viewpoint is currently below the water surface.
var head_in_water: bool = false

## Tracks if the player's chest (1 meter below camera) is currently below the water surface.
var chest_in_water: bool = false

## Stores the previous frame's [member head_in_water] state to detect surface break events.
var was_head_in_water: bool = false

## Flag indicating if the player has just initiated a jump from the water, suppressing buoyancy.
var just_water_jumped: bool = false

## Accumulates elapsed time while submerged to determine when oxygen depletes.
var oxygen_timer: float = 0.0

## Accumulates elapsed time between drowning damage ticks once out of oxygen.
var drown_tick_timer: float = 0.0

## Tracks if infinite swim mode is enabled via accessibility options.
var is_infinite_swim: bool = false


## Lifecycle ready method connecting to global event bus.
func _ready() -> void:
	print("StateSwim: _ready() called. Binding event bus listeners.")
	is_infinite_swim = bool(GlobalSettings.get_setting("Accessibility", "infinite_swim", false))
	if not Events.infinite_swim_toggled.is_connected(_on_infinite_swim_toggled):
		Events.infinite_swim_toggled.connect(_on_infinite_swim_toggled)


## Called by the state machine when entering the swim state. Sets up collision shapes.
## [param _msg] Dictionary containing transition parameters (unused in this state).
func enter(_msg: Dictionary = {}) -> void:
	print("StateSwim: enter() called. Setting up water physics.")
	is_infinite_swim = bool(GlobalSettings.get_setting("Accessibility", "infinite_swim", false))

	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent
	loco.standing_collision.disabled = false
	loco.crouching_collision.disabled = true

	head_in_water = false
	chest_in_water = false
	was_head_in_water = false
	just_water_jumped = false
	oxygen_timer = 0.0
	drown_tick_timer = 0.0


## Called by the state machine when exiting the swim state. Cleans up screen VFX.
func exit() -> void:
	print("StateSwim: exit() called. Cleaning up water state.")

	if head_in_water:
		var vfx: Node = player.environment_component.vfx_manager
		if is_instance_valid(vfx) and vfx.has_method("trigger_surface_wipe"):
			vfx.trigger_surface_wipe()

		_update_flashlight_underwater(false, 1.0)
		Events.oxygen_timer_stopped.emit()

	head_in_water = false
	chest_in_water = false
	was_head_in_water = false
	oxygen_timer = 0.0
	drown_tick_timer = 0.0
	player.camera_controller.eyes.rotation.z = 0.0


## Master physics update loop for swimming. Processes depth, buoyancy, and input velocity.
## [param delta] The physics frame delta time in seconds.
func physics_update(delta: float) -> void:
	_calculate_water_depth()

	var input_dir: Vector2 = GestureInputManager.get_vector("left", "right", "forward", "backward")

	_apply_swim_velocity(delta, input_dir)
	player.move_and_slide()

	_process_drowning(delta)
	_handle_camera_and_vfx(delta, input_dir)
	_check_transitions()


## Updates infinite swim status from external setting events.
## [param enabled] Enabled state.
func _on_infinite_swim_toggled(enabled: bool) -> void:
	print("StateSwim: Infinite swim mode updated -> ", enabled)
	is_infinite_swim = enabled
	oxygen_timer = 0.0
	drown_tick_timer = 0.0

	if head_in_water:
		if is_infinite_swim:
			# Signal stopped is NOT emitted here so HUD remains visible
			pass
		else:
			print("StateSwim: Resumed oxygen countdown while submerged.")
			Events.oxygen_timer_started.emit(max_swim_duration)


## Tracks submerged duration and applies recurring damage ticks when out of oxygen.
## [param delta] Physics tick delta time in seconds.
func _process_drowning(delta: float) -> void:
	if is_infinite_swim or not head_in_water:
		oxygen_timer = 0.0
		drown_tick_timer = 0.0
		return

	oxygen_timer += delta
	if oxygen_timer < max_swim_duration:
		return

	drown_tick_timer += delta
	if drown_tick_timer >= DROWN_TICK_INTERVAL:
		drown_tick_timer -= DROWN_TICK_INTERVAL
		_apply_drowning_damage()


## Finds the player's [HealthComponent] and deals drowning damage.
func _apply_drowning_damage() -> void:
	print("StateSwim: Applying drowning damage tick.")
	var health_comp: HealthComponent = null

	if is_instance_valid(player.health_component):
		health_comp = player.health_component
	elif player.has_node("Components/HealthComponent"):
		health_comp = player.get_node("Components/HealthComponent") as HealthComponent
	elif player.has_node("HealthComponent"):
		health_comp = player.get_node("HealthComponent") as HealthComponent

	if is_instance_valid(health_comp):
		health_comp.take_damage(DROWN_DAMAGE_PER_TICK)


## Performs spatial raycasts to determine if the player's head or chest are currently submerged.
func _calculate_water_depth() -> void:
	was_head_in_water = head_in_water
	head_in_water = false
	chest_in_water = false

	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var cam_pos: Vector3 = player.camera_controller.camera.global_position

	query.position = cam_pos - Vector3(0.0, 0.2, 0.0)
	var head_results: Array[Dictionary] = space_state.intersect_point(query)
	for result: Dictionary in head_results:
		var collider: Object = result.get("collider")
		if collider is Area3D and collider.is_in_group("water_area"):
			head_in_water = true
			break

	query.position = cam_pos - Vector3(0.0, 1.0, 0.0)
	var chest_results: Array[Dictionary] = space_state.intersect_point(query)
	for result: Dictionary in chest_results:
		var collider: Object = result.get("collider")
		if collider is Area3D and collider.is_in_group("water_area"):
			chest_in_water = true
			break

	if head_in_water and not was_head_in_water:
		print("StateSwim: Head submerged. Showing swim debuff HUD.")
		Events.oxygen_timer_started.emit(max_swim_duration)
	elif was_head_in_water and not head_in_water:
		print("StateSwim: Head surfaced. Hiding swim debuff HUD.")
		Events.oxygen_timer_stopped.emit()


## Calculates and applies horizontal movement, vertical buoyancy, and jump logic.
## [param delta] The physics frame delta time in seconds.
## [param input_dir] The 2D movement input vector from the player.
func _apply_swim_velocity(delta: float, input_dir: Vector2) -> void:
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent

	loco.head.position.y = lerpf(loco.head.position.y, 1.8, delta * loco.default_lerp_speed)

	var input_vec: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	var cam_basis: Basis = player.camera_controller.camera.global_transform.basis
	var swim_dir: Vector3 = (cam_basis * input_vec).normalized()

	var target_velocity: Vector3 = swim_dir * loco.swimming_speed

	var actively_swimming_vertical: bool = false
	just_water_jumped = false

	if GestureInputManager.is_action_just_pressed("jump") and not head_in_water:
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

	if GestureInputManager.is_action_pressed("jump") and head_in_water:
		target_velocity.y = loco.swim_up_speed
		actively_swimming_vertical = true
	elif GestureInputManager.is_action_pressed("crouch") and (head_in_water or chest_in_water):
		target_velocity.y = -loco.swim_up_speed
		actively_swimming_vertical = true

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

	var target_xz: Vector2 = Vector2(target_velocity.x, target_velocity.z)
	var current_xz: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	current_xz = current_xz.lerp(target_xz, 8.0 * delta)

	player.velocity.x = current_xz.x
	player.velocity.z = current_xz.y

	if not just_water_jumped:
		player.velocity.y = lerpf(player.velocity.y, target_velocity.y, 4.0 * delta)


## Manages procedural camera tilting during strafing and triggers splash/surface VFX.
## [param delta] The physics frame delta time in seconds.
## [param input_dir] The 2D movement input vector from the player.
func _handle_camera_and_vfx(delta: float, input_dir: Vector2) -> void:
	var target_tilt: float = 0.0
	var loco: PlayerLocomotionComponent = player.locomotion_component as PlayerLocomotionComponent

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

			var water_node: Node = player.environment_component.current_water_node
			if is_instance_valid(water_node) and water_node.has_method("play_splash_sound"):
				print("StateSwim _handle_camera_and_vfx: Head broke surface. Triggering splash.")
				var exit_speed: float = maxf(absf(player.velocity.y), 10.0)
				water_node.play_splash_sound(player.global_position, exit_speed)


## Increases flashlight energy multiplier when the player is submerged to combat light attenuation.
## [param is_submerged] True if the player's head is underwater.
## [param delta] The physics frame delta time in seconds.
func _update_flashlight_underwater(is_submerged: bool, delta: float) -> void:
	var flash_ctrl: Node = player.get("flashlight_controller")
	if flash_ctrl == null and player.get("interaction_component"):
		flash_ctrl = player.interaction_component.get("flashlight_controller")

	if is_instance_valid(flash_ctrl) and flash_ctrl.get("flashlight"):
		var base_energy: float = flash_ctrl.get("base_energy")
		var target_energy: float = base_energy * 4.0 if is_submerged else base_energy

		flash_ctrl.flashlight.light_energy = lerpf(
			flash_ctrl.flashlight.light_energy, target_energy, 4.0 * delta
		)


## Evaluates conditions to transition out of the swim state.
func _check_transitions() -> void:
	if player.environment_component.current_water_node == null:
		print("StateSwim: No active water node. Transitioning to Air.")
		state_machine.transition_to("Air")
		return

	if player.is_on_floor() and not chest_in_water and not head_in_water:
		print("StateSwim: Exiting shallow water. Transitioning to Ground.")
		state_machine.transition_to("Ground")
