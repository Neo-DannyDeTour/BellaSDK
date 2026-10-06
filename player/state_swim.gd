## Handles aquatic locomotion, buoyancy, and underwater VFX in [StateSwim].
class_name StateSwim
extends PlayerState

## Constant vertical velocity applied when head is submerged and idle.
const SINK_SPEED: float = -1.8

## Constant vertical velocity applied when plunging into water before buoyancy normalizes.
const PLUNGE_SPEED: float = -5.0

## Interval in seconds between consecutive drowning damage ticks once oxygen depletes.
const DROWN_TICK_INTERVAL: float = 0.5

## Amount of damage dealt to player health per drowning damage tick.
const DROWN_DAMAGE_PER_TICK: int = 25

## Maximum duration in seconds the player can remain submerged before drowning.
@export var max_swim_duration: float = 10.0

## Tracks if the player's camera viewpoint is currently below water surface.
var head_in_water: bool = false

## Tracks if the player's chest is currently below water surface.
var chest_in_water: bool = false

## Stores the previous frame's [member head_in_water] state to detect surface breaks.
var was_head_in_water: bool = false

## Flag indicating if player initiated water jump, suppressing buoyancy.
var just_water_jumped: bool = false

## Accumulates elapsed time while submerged to determine when oxygen depletes.
var oxygen_timer: float = 0.0

## Accumulates elapsed time between drowning damage ticks once out of oxygen.
var drown_tick_timer: float = 0.0

## Tracks if infinite swim mode is enabled via accessibility options.
var is_infinite_swim: bool = false

## Cached point query parameter to eliminate per-frame heap allocations.
var _point_query: PhysicsPointQueryParameters3D = null


## Initializes query parameters and connects to accessibility event bus.
func _ready() -> void:
	print("StateSwim: _ready() called. Binding event bus listeners.")
	_point_query = PhysicsPointQueryParameters3D.new()
	_point_query.collide_with_areas = true
	_point_query.collide_with_bodies = false
	_point_query.collision_mask = CollisionLayers.MASK_ENVIRONMENT

	is_infinite_swim = bool(GlobalSettings.get_setting("Accessibility", "infinite_swim", false))
	if not Events.infinite_swim_toggled.is_connected(_on_infinite_swim_toggled):
		Events.infinite_swim_toggled.connect(_on_infinite_swim_toggled)


## Configures water collisions and resets oxygen and buoyancy timers.
func enter(_msg: Dictionary = {}) -> void:
	print("StateSwim: enter() called. Setting up water physics.")
	is_infinite_swim = bool(GlobalSettings.get_setting("Accessibility", "infinite_swim", false))

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


## Restores camera roll, halts oxygen timers, and cleans up water screen VFX.
func exit() -> void:
	print("StateSwim: exit() called. Cleaning up water state.")
	if head_in_water:
		var env: PlayerEnvironmentComponent = _get_environment()
		var vfx: Node = env.vfx_manager if is_instance_valid(env) else null
		if is_instance_valid(vfx) and vfx.has_method(&"trigger_surface_wipe"):
			vfx.call(&"trigger_surface_wipe")

		_update_flashlight_underwater(false, 1.0)
		Events.oxygen_timer_stopped.emit()

	head_in_water = false
	chest_in_water = false
	was_head_in_water = false
	oxygen_timer = 0.0
	drown_tick_timer = 0.0

	var cam_ctrl: Node = _get_camera_controller()
	if is_instance_valid(cam_ctrl):
		var eyes: Node3D = cam_ctrl.get(&"eyes") as Node3D
		if is_instance_valid(eyes):
			eyes.rotation.z = 0.0


## Evaluates water depth, applies swim velocity, and checks transitions.
func physics_update(delta: float) -> void:
	print("StateSwim: physics_update() processing aquatic tick.")
	_calculate_water_depth()

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	_apply_swim_velocity(delta, input_dir)
	player.move_and_slide()

	_process_drowning(delta)
	_handle_camera_and_vfx(delta, input_dir)
	_check_transitions()


## Updates accessibility infinite swim setting and adjusts oxygen countdown.
func _on_infinite_swim_toggled(enabled: bool) -> void:
	print("StateSwim: Infinite swim mode updated -> ", enabled)
	is_infinite_swim = enabled
	oxygen_timer = 0.0
	drown_tick_timer = 0.0

	if head_in_water and not is_infinite_swim:
		print("StateSwim: Resumed oxygen countdown while submerged.")
		Events.oxygen_timer_started.emit(max_swim_duration)


## Tracks submerged duration and applies recurring drowning damage ticks.
func _process_drowning(delta: float) -> void:
	print("StateSwim: _process_drowning() evaluating submerged oxygen timer.")
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


## Resolves player health component and applies drowning damage tick.
func _apply_drowning_damage() -> void:
	print("StateSwim: Applying drowning damage tick.")
	var health_comp: HealthComponent = null

	var health_val: Variant = player.get(&"health_component")
	if health_val is HealthComponent and is_instance_valid(health_val):
		health_comp = health_val as HealthComponent
	else:
		var stats_val: Variant = player.get(&"stats_component")
		if stats_val is Node and is_instance_valid(stats_val as Node):
			var sub_health: Variant = (stats_val as Node).get(&"health_component")
			if sub_health is HealthComponent and is_instance_valid(sub_health):
				health_comp = sub_health as HealthComponent

	if is_instance_valid(health_comp):
		health_comp.take_damage(DROWN_DAMAGE_PER_TICK)


## Performs zero-allocation point queries to check head and chest submersion.
func _calculate_water_depth() -> void:
	print("StateSwim: _calculate_water_depth() polling water body areas.")
	was_head_in_water = head_in_water
	head_in_water = false
	chest_in_water = false

	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var cam: Camera3D = _get_camera()
	if space_state == null or _point_query == null or not is_instance_valid(cam):
		return

	var cam_pos: Vector3 = cam.global_position

	_point_query.position = cam_pos - Vector3(0.0, 0.2, 0.0)
	var head_results: Array[Dictionary] = space_state.intersect_point(_point_query, 4)
	for result: Dictionary in head_results:
		var collider: Object = result.get(&"collider")
		if collider is Area3D and (collider as Area3D).is_in_group(&"water_area"):
			head_in_water = true
			break

	_point_query.position = cam_pos - Vector3(0.0, 1.0, 0.0)
	var chest_results: Array[Dictionary] = space_state.intersect_point(_point_query, 4)
	for result: Dictionary in chest_results:
		var collider: Object = result.get(&"collider")
		if collider is Area3D and (collider as Area3D).is_in_group(&"water_area"):
			chest_in_water = true
			break

	if head_in_water and not was_head_in_water:
		print("StateSwim: Head submerged. Showing swim debuff HUD.")
		Events.oxygen_timer_started.emit(max_swim_duration)
	elif was_head_in_water and not head_in_water:
		print("StateSwim: Head surfaced. Hiding swim debuff HUD.")
		Events.oxygen_timer_stopped.emit()


## Computes horizontal swim velocity, vertical buoyancy, and water jumps.
func _apply_swim_velocity(delta: float, input_dir: Vector2) -> void:
	print("StateSwim: _apply_swim_velocity() applying fluid forces.")
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

	if GestureInputManager.is_action_just_pressed(&"jump") and not head_in_water:
		var env: PlayerEnvironmentComponent = _get_environment()
		var vault_ctrl: Node = env.vault_controller if is_instance_valid(env) else null
		if is_instance_valid(vault_ctrl):
			vault_ctrl.call(&"process_vault_scan")
			if bool(vault_ctrl.get(&"can_vault_current_ledge")):
				if bool(vault_ctrl.call(&"try_vault", loco.crouching)):
					print("StateSwim: Vault successful. Transitioning to Vault.")
					actively_swimming_vertical = true
					just_water_jumped = true
					state_machine.transition_to(&"Vault")
					return

		if player.is_on_floor() and not chest_in_water:
			print("StateSwim: Shallow water jump. Transitioning to Air.")
			target_velocity.y = 4.5
			actively_swimming_vertical = true
			just_water_jumped = true
			state_machine.transition_to(&"Air")
			return

	if GestureInputManager.is_action_pressed(&"jump") and head_in_water:
		target_velocity.y = loco.swim_up_speed
		actively_swimming_vertical = true
	elif GestureInputManager.is_action_pressed(&"crouch") and (head_in_water or chest_in_water):
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
	current_xz = MathUtils.damp_v2(current_xz, target_xz, 8.0, delta)

	player.velocity.x = current_xz.x
	player.velocity.z = current_xz.y

	if not just_water_jumped:
		player.velocity.y = MathUtils.damp(player.velocity.y, target_velocity.y, 4.0, delta)


## Manages procedural camera banking during strafing and triggers splash VFX.
func _handle_camera_and_vfx(delta: float, input_dir: Vector2) -> void:
	print("StateSwim: _handle_camera_and_vfx() updating visual effects.")
	var target_tilt: float = 0.0
	var loco: PlayerLocomotionComponent = _get_locomotion()
	var cam_ctrl: Node = _get_camera_controller()
	var tilt_amount: float = (
		float(cam_ctrl.get(&"camera_tilt_amount")) if is_instance_valid(cam_ctrl) else 0.0
	)
	var eyes: Node3D = cam_ctrl.get(&"eyes") as Node3D if is_instance_valid(cam_ctrl) else null

	if input_dir.x > 0.1:
		target_tilt = deg_to_rad(tilt_amount * 2.0)
	elif input_dir.x < -0.1:
		target_tilt = deg_to_rad(-tilt_amount * 2.0)

	if is_instance_valid(eyes) and is_instance_valid(loco):
		eyes.rotation.z = MathUtils.damp(
			eyes.rotation.z, target_tilt, loco.default_lerp_speed / 3.0, delta
		)

	_update_flashlight_underwater(head_in_water, delta)

	var env: PlayerEnvironmentComponent = _get_environment()
	var vfx: Node = env.vfx_manager if is_instance_valid(env) else null
	if is_instance_valid(vfx):
		if head_in_water and not was_head_in_water:
			if vfx.has_method(&"set_underwater_state"):
				vfx.call(&"set_underwater_state", true)
		elif was_head_in_water and not head_in_water:
			if vfx.has_method(&"trigger_surface_wipe"):
				vfx.call(&"trigger_surface_wipe")

			var water_node: Node = env.current_water_node if is_instance_valid(env) else null
			if is_instance_valid(water_node) and water_node.has_method(&"play_splash_sound"):
				print("StateSwim: Head broke surface. Triggering splash sound.")
				var exit_speed: float = maxf(absf(player.velocity.y), 10.0)
				water_node.call(&"play_splash_sound", player.global_position, exit_speed)


## Adjusts flashlight intensity underwater to compensate for light falloff.
func _update_flashlight_underwater(is_submerged: bool, delta: float) -> void:
	print("StateSwim: _update_flashlight_underwater() adjusting beam energy.")
	var flash_ctrl: Node = null
	var direct_ctrl: Variant = player.get(&"flashlight_controller")
	if direct_ctrl is Node and is_instance_valid(direct_ctrl as Node):
		flash_ctrl = direct_ctrl as Node
	else:
		var interact: Variant = player.get(&"interaction_component")
		if interact is Node and is_instance_valid(interact as Node):
			var sub_ctrl: Variant = (interact as Node).get(&"flashlight_controller")
			if sub_ctrl is Node and is_instance_valid(sub_ctrl as Node):
				flash_ctrl = sub_ctrl as Node

	if is_instance_valid(flash_ctrl) and flash_ctrl.get(&"flashlight"):
		var light: Light3D = flash_ctrl.get(&"flashlight") as Light3D
		var base_energy: float = float(flash_ctrl.get(&"base_energy"))
		var target_energy: float = base_energy * 4.0 if is_submerged else base_energy

		if is_instance_valid(light):
			light.light_energy = MathUtils.damp(light.light_energy, target_energy, 4.0, delta)


## Evaluates water exit criteria to transition to [StateAir] or [StateGround].
func _check_transitions() -> void:
	print("StateSwim: _check_transitions() validating environment state.")
	var env: PlayerEnvironmentComponent = _get_environment()
	if not is_instance_valid(env) or env.current_water_node == null:
		print("StateSwim: No active water node. Transitioning to Air.")
		state_machine.transition_to(&"Air")
		return

	if player.is_on_floor() and not chest_in_water and not head_in_water:
		print("StateSwim: Exiting shallow water. Transitioning to Ground.")
		state_machine.transition_to(&"Ground")


## Safely retrieves the player locomotion component.
func _get_locomotion() -> PlayerLocomotionComponent:
	if not is_instance_valid(player):
		return null
	var val: Variant = player.get(&"locomotion_component")
	if val is PlayerLocomotionComponent and is_instance_valid(val):
		return val as PlayerLocomotionComponent
	return null


## Safely retrieves the player environment component.
func _get_environment() -> PlayerEnvironmentComponent:
	if not is_instance_valid(player):
		return null
	var val: Variant = player.get(&"environment_component")
	if val is PlayerEnvironmentComponent and is_instance_valid(val):
		return val as PlayerEnvironmentComponent
	return null


## Safely retrieves the player camera controller component.
func _get_camera_controller() -> Node:
	if not is_instance_valid(player):
		return null
	var ctrl: Variant = player.get(&"camera_controller")
	if ctrl is Node and is_instance_valid(ctrl as Node):
		return ctrl as Node
	return null


## Safely retrieves the player [Camera3D] node.
func _get_camera() -> Camera3D:
	var ctrl: Node = _get_camera_controller()
	if is_instance_valid(ctrl):
		var cam: Variant = ctrl.get(&"camera")
		if cam is Camera3D and is_instance_valid(cam as Camera3D):
			return cam as Camera3D
	return null
