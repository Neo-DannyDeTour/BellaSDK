class_name StateSwim
extends PlayerState
## Handles aquatic locomotion, wave-locked buoyancy, diving, and oxygen depletion.

## Constant downward velocity applied when completely submerged and idle.
const SINK_SPEED: float = -1.6
## Constant downward velocity applied upon initial water plunge.
const PLUNGE_SPEED: float = -4.5
## Upward swim speed applied when pressing jump while head is submerged.
const SWIM_UP_SPEED: float = 3.8
## Downward dive speed applied when pressing crouch or pitching down.
const SWIM_DOWN_SPEED: float = -3.2
## Vertical spring stiffness locking chest elevation to wave height while treading.
const SURFACE_SPRING_STIFFNESS: float = 5.5
## Maximum vertical clamping speed for wave-following spring bobbing.
const MAX_SURFACE_BOB_SPEED: float = 3.2
## Interval in seconds between consecutive drowning damage ticks.
const DROWN_TICK_INTERVAL: float = 0.5
## Amount of health damage dealt per drowning tick.
const DROWN_DAMAGE_PER_TICK: int = 25
## Eye offset above player origin in meters.
const EYE_HEIGHT_OFFSET: float = 1.65
## Chest offset above player origin in meters.
const CHEST_HEIGHT_OFFSET: float = 0.95
## Distance above surface camera must clear to exit submersion hysteresis.
const SURFACE_EXIT_HYSTERESIS: float = 0.18
## Minimum vertical speed required to trigger exit splash sound when surfacing.
const MIN_SPLASH_EXIT_SPEED: float = 1.8

## Method name for querying wave height on active water body.
const METHOD_GET_WAVE_HEIGHT: StringName = &"get_wave_height_at_pos"
## Method name for triggering spatial water exit sound.
const METHOD_PLAY_SPLASH: StringName = &"play_splash_sound"

## Maximum submerged duration in seconds before oxygen runs out.
@export var max_swim_duration: float = 10.0

## Tracks if player viewpoint is submerged beneath wave crests.
var head_in_water: bool = false
## Tracks if player chest is submerged beneath wave crests.
var chest_in_water: bool = false
## Stores previous frame submersion state to detect surface crossings.
var was_head_in_water: bool = false
## Flag indicating water jump was performed, suppressing buoyancy damping.
var just_water_jumped: bool = false
## Elapsed time in seconds while head remains submerged.
var oxygen_timer: float = 0.0
## Elapsed time in seconds between consecutive drowning damage ticks.
var drown_tick_timer: float = 0.0
## Accessibility toggle bypassing oxygen depletion.
var is_infinite_swim: bool = false

var _point_query: PhysicsPointQueryParameters3D = null


## Initializes fallback point query and binds accessibility toggle.
func _ready() -> void:
	_point_query = PhysicsPointQueryParameters3D.new()
	_point_query.collide_with_areas = true
	_point_query.collide_with_bodies = false
	_point_query.collision_mask = 6

	is_infinite_swim = GlobalSettings.get_setting_bool("Accessibility", "infinite_swim", false)
	if not Events.infinite_swim_toggled.is_connected(_on_infinite_swim_toggled):
		Events.infinite_swim_toggled.connect(_on_infinite_swim_toggled)


## Enforces standing collision shape, resets submersion flags, and zeroes oxygen timer.
func enter(_msg: Dictionary = {}) -> void:
	is_infinite_swim = GlobalSettings.get_setting_bool("Accessibility", "infinite_swim", false)

	var loco: PlayerLocomotionComponent = _get_locomotion()
	if is_instance_valid(loco):
		loco.standing_collision.disabled = false
		loco.crouching_collision.disabled = true

	head_in_water = false
	chest_in_water = false
	was_head_in_water = false
	just_water_jumped = false
	oxygen_timer = 0.0
	drown_tick_timer = 0.0


## Resets camera roll, stops HUD oxygen timer, and restores flashlight base energy.
func exit() -> void:
	if head_in_water:
		_update_flashlight_underwater(false, 1.0)
		Events.oxygen_timer_stopped.emit()

	head_in_water = false
	chest_in_water = false
	was_head_in_water = false
	oxygen_timer = 0.0
	drown_tick_timer = 0.0

	var cam_ctrl: Node = _get_camera_controller()
	if is_instance_valid(cam_ctrl):
		var raw_eyes: Variant = cam_ctrl.get(&"eyes")
		if raw_eyes is Node3D:
			var eyes: Node3D = raw_eyes
			eyes.rotation.z = 0.0


## Calculates water wave depth, applies fluid forces, and evaluates transitions.
func physics_update(delta: float) -> void:
	_calculate_water_depth()

	var input_dir: Vector2 = GestureInputManager.get_vector(
		ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACKWARD
	)

	_apply_swim_velocity(delta, input_dir)
	player.move_and_slide()

	_process_drowning(delta)
	_handle_camera_and_vfx(delta, input_dir)
	_check_transitions()


## Updates infinite swim state and syncs HUD oxygen bar countdown.
func _on_infinite_swim_toggled(enabled: bool) -> void:
	is_infinite_swim = enabled
	oxygen_timer = 0.0
	drown_tick_timer = 0.0

	if head_in_water and not is_infinite_swim:
		Events.oxygen_timer_started.emit(max_swim_duration)


## Accumulates oxygen timer while head is submerged and executes damage ticks.
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


## Resolves player health component and applies drowning damage.
func _apply_drowning_damage() -> void:
	var health_comp: HealthComponent = null
	var health_val: Variant = player.get(&"health_component")
	if health_val is HealthComponent:
		health_comp = health_val
	else:
		var stats_val: Variant = player.get(&"stats_component")
		if stats_val is Node:
			var stats_node: Node = stats_val
			var sub_health: Variant = stats_node.get(&"health_component")
			if sub_health is HealthComponent:
				health_comp = sub_health

	if is_instance_valid(health_comp):
		health_comp.take_damage(DROWN_DAMAGE_PER_TICK)


## Evaluates head and chest submersion using wave height from active WaterBody.
func _calculate_water_depth() -> void:
	was_head_in_water = head_in_water

	var env: PlayerEnvironmentComponent = _get_environment()
	var water_node: Node3D = env.current_water_node if is_instance_valid(env) else null
	var cam: Camera3D = _get_camera()
	var cam_pos: Vector3 = (
		cam.global_position
		if is_instance_valid(cam)
		else (player.global_position + Vector3(0.0, EYE_HEIGHT_OFFSET, 0.0))
	)

	if is_instance_valid(water_node) and water_node.has_method(METHOD_GET_WAVE_HEIGHT):
		var raw_surf_y: Variant = water_node.call(METHOD_GET_WAVE_HEIGHT, cam_pos)
		var surf_y: float = raw_surf_y if raw_surf_y is float else 0.0
		var chest_y: float = player.global_position.y + CHEST_HEIGHT_OFFSET

		if head_in_water:
			head_in_water = cam_pos.y < (surf_y + SURFACE_EXIT_HYSTERESIS)
		else:
			head_in_water = cam_pos.y < surf_y

		chest_in_water = chest_y < surf_y
	else:
		_calculate_water_depth_fallback(cam_pos)

	if head_in_water and not was_head_in_water:
		Events.oxygen_timer_started.emit(max_swim_duration)
	elif was_head_in_water and not head_in_water:
		Events.oxygen_timer_stopped.emit()


## Fallback point query when active water node does not expose wave evaluation.
func _calculate_water_depth_fallback(cam_pos: Vector3) -> void:
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	if space_state == null or _point_query == null:
		head_in_water = false
		chest_in_water = false
		return

	_point_query.position = cam_pos - Vector3(0.0, 0.15, 0.0)
	var head_results: Array[Dictionary] = space_state.intersect_point(_point_query, 2)
	head_in_water = not head_results.is_empty()

	_point_query.position = player.global_position + Vector3(0.0, CHEST_HEIGHT_OFFSET, 0.0)
	var chest_results: Array[Dictionary] = space_state.intersect_point(_point_query, 2)
	chest_in_water = not chest_results.is_empty()


## Computes horizontal swimming, wave-locked surface bobbing, and diving motion.
func _apply_swim_velocity(delta: float, input_dir: Vector2) -> void:
	var loco: PlayerLocomotionComponent = _get_locomotion()
	var cam: Camera3D = _get_camera()
	if not is_instance_valid(loco) or not is_instance_valid(cam):
		return

	loco.head.position.y = MathUtils.damp(loco.head.position.y, 1.8, loco.default_lerp_speed, delta)

	var input_vec: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	var cam_basis: Basis = cam.global_transform.basis
	var swim_dir: Vector3 = (cam_basis * input_vec).normalized()
	var target_velocity: Vector3 = swim_dir * loco.swimming_speed

	var actively_swimming_vertical: bool = false
	just_water_jumped = false

	# Ledge Vaulting or Shallow Water Exit Jump
	if GestureInputManager.is_action_just_pressed(ACTION_JUMP) and not head_in_water:
		var env: PlayerEnvironmentComponent = _get_environment()
		var vault_ctrl: Node = env.vault_controller if is_instance_valid(env) else null
		if is_instance_valid(vault_ctrl):
			vault_ctrl.call(&"process_vault_scan")
			if vault_ctrl.get(&"can_vault_current_ledge") == true:
				if vault_ctrl.call(&"try_vault", loco.crouching) == true:
					actively_swimming_vertical = true
					just_water_jumped = true
					state_machine.transition_to(&"Vault")
					return

		if player.is_on_floor() and not chest_in_water:
			target_velocity.y = 4.5
			actively_swimming_vertical = true
			just_water_jumped = true
			state_machine.transition_to(&"Air")
			return

	# Submerged Swimming: Up/Down Control
	if GestureInputManager.is_action_pressed(ACTION_JUMP) and head_in_water:
		target_velocity.y = SWIM_UP_SPEED
		actively_swimming_vertical = true
	elif GestureInputManager.is_action_pressed(ACTION_CROUCH):
		target_velocity.y = SWIM_DOWN_SPEED
		actively_swimming_vertical = true
	elif input_dir.y < -0.1 and swim_dir.y < -0.32:
		target_velocity.y = swim_dir.y * loco.swimming_speed
		actively_swimming_vertical = true

	# Surface Treading & Wave Bobbing
	if not actively_swimming_vertical:
		if head_in_water:
			target_velocity.y = SINK_SPEED
		elif chest_in_water:
			var env: PlayerEnvironmentComponent = _get_environment()
			var water_node: Node3D = env.current_water_node if is_instance_valid(env) else null
			if is_instance_valid(water_node) and water_node.has_method(METHOD_GET_WAVE_HEIGHT):
				var raw_surf: Variant = water_node.call(
					METHOD_GET_WAVE_HEIGHT, player.global_position
				)
				var surf_y: float = raw_surf if raw_surf is float else 0.0
				var desired_chest_y: float = surf_y - 0.25
				var actual_chest_y: float = player.global_position.y + CHEST_HEIGHT_OFFSET
				var displacement: float = desired_chest_y - actual_chest_y
				var spring_force: float = displacement * SURFACE_SPRING_STIFFNESS
				target_velocity.y = clampf(
					spring_force, -MAX_SURFACE_BOB_SPEED, MAX_SURFACE_BOB_SPEED
				)
			else:
				target_velocity.y = 0.0
		else:
			if player.velocity.y < -1.0:
				target_velocity.y = player.velocity.y
			else:
				target_velocity.y = PLUNGE_SPEED

	var target_xz: Vector2 = Vector2(target_velocity.x, target_velocity.z)
	var current_xz: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	current_xz = MathUtils.damp_v2(current_xz, target_xz, 8.0, delta)

	player.velocity.x = current_xz.x
	player.velocity.z = current_xz.y

	if not just_water_jumped:
		player.velocity.y = MathUtils.damp(player.velocity.y, target_velocity.y, 5.0, delta)


## Applies procedural camera strafe banking and boosts flashlight intensity.
func _handle_camera_and_vfx(delta: float, input_dir: Vector2) -> void:
	var target_tilt: float = 0.0
	var loco: PlayerLocomotionComponent = _get_locomotion()
	var cam_ctrl: Node = _get_camera_controller()
	var raw_tilt: Variant = (
		cam_ctrl.get(&"camera_tilt_amount") if is_instance_valid(cam_ctrl) else null
	)
	var tilt_amount: float = raw_tilt if raw_tilt is float else 0.0

	var eyes: Node3D = null
	if is_instance_valid(cam_ctrl):
		var raw_eyes: Variant = cam_ctrl.get(&"eyes")
		if raw_eyes is Node3D:
			eyes = raw_eyes

	if input_dir.x > 0.1:
		target_tilt = deg_to_rad(tilt_amount * 2.0)
	elif input_dir.x < -0.1:
		target_tilt = deg_to_rad(-tilt_amount * 2.0)

	if is_instance_valid(eyes) and is_instance_valid(loco):
		eyes.rotation.z = MathUtils.damp(
			eyes.rotation.z, target_tilt, loco.default_lerp_speed / 3.0, delta
		)

	_update_flashlight_underwater(head_in_water, delta)

	if was_head_in_water and not head_in_water:
		var env: PlayerEnvironmentComponent = _get_environment()
		var water_node: Node3D = env.current_water_node if is_instance_valid(env) else null
		var exit_spd: float = absf(player.velocity.y)
		if is_instance_valid(water_node) and water_node.has_method(METHOD_PLAY_SPLASH):
			if exit_spd >= MIN_SPLASH_EXIT_SPEED:
				water_node.call(METHOD_PLAY_SPLASH, player.global_position, exit_spd)


## Boosts flashlight beam energy to 4x baseline when submerged to overcome water murk.
func _update_flashlight_underwater(is_submerged: bool, delta: float) -> void:
	var flash_ctrl: Node = null
	var direct_ctrl: Variant = player.get(&"flashlight_controller")
	if direct_ctrl is Node:
		flash_ctrl = direct_ctrl
	else:
		var interact: Variant = player.get(&"interaction_component")
		if interact is Node:
			var interact_node: Node = interact
			var sub_ctrl: Variant = interact_node.get(&"flashlight_controller")
			if sub_ctrl is Node:
				flash_ctrl = sub_ctrl

	if is_instance_valid(flash_ctrl) and flash_ctrl.get(&"flashlight") != null:
		var raw_light: Variant = flash_ctrl.get(&"flashlight")
		var light: Light3D = raw_light if raw_light is Light3D else null
		var raw_energy: Variant = flash_ctrl.get(&"base_energy")
		var base_energy: float = raw_energy if raw_energy is float else 1.0
		var target_energy: float = base_energy * 4.0 if is_submerged else base_energy

		if is_instance_valid(light):
			light.light_energy = MathUtils.damp(light.light_energy, target_energy, 4.0, delta)


## Evaluates state transitions to [StateAir] or [StateGround].
func _check_transitions() -> void:
	var env: PlayerEnvironmentComponent = _get_environment()
	if not is_instance_valid(env) or env.current_water_node == null:
		state_machine.transition_to(&"Air")
		return

	if player.is_on_floor() and not chest_in_water and not head_in_water:
		state_machine.transition_to(&"Ground")


## Safely retrieves the player locomotion component.
func _get_locomotion() -> PlayerLocomotionComponent:
	if not is_instance_valid(player):
		return null
	var val: Variant = player.get(&"locomotion_component")
	if val is PlayerLocomotionComponent:
		return val
	return null


## Safely retrieves the player environment component.
func _get_environment() -> PlayerEnvironmentComponent:
	if not is_instance_valid(player):
		return null
	var val: Variant = player.get(&"environment_component")
	if val is PlayerEnvironmentComponent:
		return val
	return null


## Safely retrieves the player camera controller component.
func _get_camera_controller() -> Node:
	if not is_instance_valid(player):
		return null
	var ctrl: Variant = player.get(&"camera_controller")
	if ctrl is Node:
		return ctrl
	return null


## Safely retrieves the active player Camera3D node.
func _get_camera() -> Camera3D:
	var ctrl: Node = _get_camera_controller()
	if is_instance_valid(ctrl):
		var cam: Variant = ctrl.get(&"camera")
		if cam is Camera3D:
			return cam
	return null
