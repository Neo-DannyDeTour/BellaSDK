## Central coordinator for player locomotion, camera, input, and environment interactions.
class_name Player
extends CharacterBody3D

# --------------------------------------
# CONSTANTS & ZERO-ALLOCATION IDENTIFIERS
# --------------------------------------
## Group name identifier for detecting sand ground surfaces.
const GROUP_SAND: StringName = &"sand"

## Group name identifier for detecting ice ground surfaces.
const GROUP_ICE: StringName = &"ice"

# --------------------------------------
# COMPONENT REFERENCES (Cached for 60 FPS)
# --------------------------------------
@export_category("Core Modules")

## Handles physics, gravity, and state machine locomotion updates.
@export var locomotion_component: PlayerLocomotionComponent

## Handles raycasting, item holding, and machine interactions.
@export var interaction_component: PlayerInteractionComponent

## Handles external triggers such as water, rain, updrafts, and ladders.
@export var environment_component: PlayerEnvironmentComponent

## Manages player health, damage calculation, and stat serialization.
@export var stats_component: PlayerStatsComponent

## Root [StateMachine] managing active player character states.
@export var state_machine: StateMachine

@export_category("System References")

## Controls camera orientation, positioning, and camera shake.
@export var camera_controller: CameraController

## Manages system menus, pause state, and developer noclip modes.
@export var system_menu: SystemMenuController

## Reference to main UI controller for HUD and screen overlays.
@export var ui_controller: UIController

## Reference to global UI console overlay for debug commands.
var in_game_console: CanvasLayer

## Manages flashlight toggling and battery consumption.
var flashlight_controller: FlashlightController

## Local reference to the player's [HealthComponent] instance.
@onready var health_component: HealthComponent = $Components/HealthComponent

## The [FactionComponent] governing player faction allegiance.
@onready var faction_component: FactionComponent = (
	get_node_or_null("Components/FactionComponent") as FactionComponent
)

## Tracks whether player character is dead to block inputs.
var is_dead: bool = false

## Tracks whether the player is currently standing on sand.
var is_on_sand_surface: bool = false

## Tracks whether the player is currently standing on ice.
var is_on_ice_surface: bool = false

## Tracks whether the player is interacting with a terminal.
var is_in_terminal_mode: bool = false

## Indicates if movement and camera look are locked by a terminal.
var is_terminal_locked: bool = false

## Sensitivity scale applied to mouse look during terminal interaction.
var terminal_mouse_sensitivity_scale: float = 1.0

## Tracks whether a cinematic sequence locks player input and physics.
var is_cinematic_locked: bool = false

# --------------------------------------
# INITIALIZATION
# --------------------------------------


## Initializes groups, subcomponents, and global singleton bindings.
func _ready() -> void:
	print("Player: Initializing character controller.")
	add_to_group(&"saveable")
	add_to_group(&"player")

	var global_singleton: Node = get_node_or_null("/root/Global")
	if is_instance_valid(global_singleton) and "main" in global_singleton:
		global_singleton.set("main", self)

	if not is_instance_valid(health_component):
		health_component = (get_node_or_null("Components/HealthComponent") as HealthComponent)

	if not is_instance_valid(faction_component):
		faction_component = (get_node_or_null("Components/FactionComponent") as FactionComponent)

	_capture_mouse()
	activate_gameplay_camera()

	var console_node: Node = (
		get_node_or_null("/root/InGameConsole")
		if has_node("/root/InGameConsole")
		else get_node_or_null("/root/Console")
	)
	in_game_console = console_node as CanvasLayer

	if not is_instance_valid(ui_controller):
		ui_controller = get_node_or_null("UI") as UIController

	if is_instance_valid(locomotion_component):
		locomotion_component.initialize(self)
	if is_instance_valid(interaction_component):
		interaction_component.initialize(self)
	if is_instance_valid(environment_component):
		environment_component.initialize(self)
	if is_instance_valid(stats_component):
		stats_component.initialize(self)

	if is_instance_valid(health_component):
		Utilities.safe_connect(health_component.died, _on_player_died)

	if Events.has_signal(&"player_health_set_requested"):
		Utilities.safe_connect(Events.player_health_set_requested, _on_health_set_requested)
	if Events.has_signal(&"player_kill_requested"):
		Utilities.safe_connect(Events.player_kill_requested, _on_player_died)
	if Events.has_signal(&"teleport_requested"):
		Utilities.safe_connect(Events.teleport_requested, teleport_to)
	if Events.has_signal(&"flight_mode_toggled"):
		Utilities.safe_connect(Events.flight_mode_toggled, _on_flight_mode_toggled)
	if Events.has_signal(&"player_cinematic_lock_requested"):
		Utilities.safe_connect(Events.player_cinematic_lock_requested, _on_cinematic_lock_requested)


## Captures and locks the mouse cursor for first-person gameplay.
func _capture_mouse() -> void:
	print("Player: Capturing mouse cursor.")
	if not is_inside_tree():
		return
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --------------------------------------
# INPUT ROUTING
# --------------------------------------


## Routes mouse motion events to the [CameraController].
func _input(event: InputEvent) -> void:
	if _is_input_blocked():
		return

	if is_terminal_locked and event is InputEventMouseMotion:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if is_instance_valid(camera_controller) and is_instance_valid(interaction_component):
			var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
			if not is_zero_approx(terminal_mouse_sensitivity_scale - 1.0):
				motion_event = event.duplicate() as InputEventMouseMotion
				motion_event.relative *= terminal_mouse_sensitivity_scale

			camera_controller.handle_mouse_input(
				motion_event,
				interaction_component.is_in_terminal_mode,
				interaction_component.is_heavy_lifting,
				interaction_component.heavy_lift_yaw_base
			)


## Forwards unhandled input events to the [member interaction_component].
func _unhandled_input(event: InputEvent) -> void:
	if _is_input_blocked():
		return

	if is_instance_valid(interaction_component):
		interaction_component.process_unhandled_input(event)


## Configures the mouse look sensitivity multiplier for terminal interfaces.
func set_terminal_mouse_sensitivity_scale(p_scale: float) -> void:
	print("Player: Setting terminal mouse sensitivity scale to: ", p_scale)
	terminal_mouse_sensitivity_scale = p_scale


## Evaluates whether player input is blocked by UI, pause, or death.
func _is_input_blocked() -> bool:
	var is_console_open: bool = is_instance_valid(in_game_console) and in_game_console.visible
	var is_operating: bool = (
		is_instance_valid(interaction_component) and interaction_component.is_operating_machine
	)
	var is_menu_locked: bool = (
		is_instance_valid(system_menu)
		and (system_menu.is_paused or system_menu.is_menu_open or system_menu.is_stunned)
	)
	return is_menu_locked or is_console_open or is_operating or is_dead or is_cinematic_locked


## Dispatches surroundings description requests from gesture manager.
func _handle_describe_input() -> void:
	if not is_instance_valid(GestureInputManager):
		return

	if GestureInputManager.is_action_just_triggered("describe_surroundings"):
		print("Player: Describe surroundings triggered via gesture manager.")
		if Events.has_signal("describe_surroundings_requested"):
			Events.describe_surroundings_requested.emit(self)


## Handles player death, disables physics, and broadcasts death state.
func _on_player_died() -> void:
	print("Player: Death detected. Locking controls and broadcasting event.")
	is_dead = true
	velocity = Vector3.ZERO

	var current_death_state: int = DeathScreen.DeathState.WALKING

	if is_instance_valid(locomotion_component):
		locomotion_component.set_physics_active(false)

		if locomotion_component.crouching:
			current_death_state = DeathScreen.DeathState.CROUCHING
			print("Player: Death state evaluated as CROUCHING.")
		elif locomotion_component.did_run_recently():
			current_death_state = DeathScreen.DeathState.SPRINTING
			print("Player: Death state evaluated as SPRINTING.")
		else:
			print("Player: Death state evaluated as WALKING.")

	if Events.has_signal("player_died"):
		Events.player_died.emit(current_death_state)


# --------------------------------------
# MASTER PHYSICS ROUTING
# --------------------------------------


## Executes physics processing, locomotion, and surface detection.
func _physics_process(delta: float) -> void:
	var in_terminal_state: bool = (
		is_terminal_locked
		or (is_instance_valid(state_machine) and state_machine.is_in_state(&"Terminal"))
	)

	if in_terminal_state:
		velocity = Vector3.ZERO
		if is_instance_valid(locomotion_component):
			locomotion_component.set_physics_active(false)

		if is_instance_valid(interaction_component):
			interaction_component.process_interaction(delta)
		return

	var disable_states: bool = (
		_is_input_blocked() or (is_instance_valid(system_menu) and system_menu.flying)
	)

	if disable_states:
		if (
			is_instance_valid(state_machine)
			and state_machine.process_mode != Node.PROCESS_MODE_DISABLED
		):
			state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		if (
			is_instance_valid(state_machine)
			and state_machine.process_mode != Node.PROCESS_MODE_INHERIT
		):
			state_machine.process_mode = Node.PROCESS_MODE_INHERIT

	if _is_input_blocked():
		if is_instance_valid(locomotion_component):
			locomotion_component.set_physics_active(false)
		velocity = Vector3.ZERO
		return

	_handle_describe_input()

	if (
		is_instance_valid(GestureInputManager)
		and GestureInputManager.is_action_just_triggered("sonar_ping")
	):
		print("Player: Sonar ping triggered via gesture manager.")
		if Events.has_signal("sonar_ping_requested"):
			Events.sonar_ping_requested.emit(self)

	if is_instance_valid(system_menu) and system_menu.flying:
		if is_instance_valid(locomotion_component):
			locomotion_component.set_physics_active(false)
		system_menu.process_noclip(delta)
		return

	if is_instance_valid(locomotion_component):
		locomotion_component.set_physics_active(true)
		locomotion_component.process_movement(delta)

	_update_floor_surface_detection()

	if is_instance_valid(environment_component):
		environment_component.process_environment_physics(delta)

	if is_instance_valid(interaction_component):
		interaction_component.process_interaction(delta)


# --------------------------------------
# ENVIRONMENTAL ADAPTERS (Facade)
# --------------------------------------


## Forwards ladder entrance notifications to [member environment_component].
func enter_ladder(ladder_node: Node3D) -> void:
	print("Player: Forwarding ladder enter to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.enter_ladder(ladder_node)


## Forwards ladder exit notifications to [member environment_component].
func exit_ladder(ladder_node: Node3D) -> void:
	print("Player: Forwarding ladder exit to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.exit_ladder(ladder_node)


## Transitions locomotion into swimming state for water volumes.
func enter_water(water_volume: Node3D) -> void:
	print("Player: Forwarding water enter to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.enter_water(water_volume)


## Restores default locomotion upon leaving water volumes.
func exit_water(water_volume: Node3D) -> void:
	print("Player: Forwarding water exit to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.exit_water(water_volume)


## Applies vertical updraft force to [member environment_component].
func enter_updraft(strength: float, top_y: float) -> void:
	print("Player: Forwarding updraft enter to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.enter_updraft(strength, top_y)


## Notifies [member environment_component] of leaving updraft volume.
func exit_updraft() -> void:
	print("Player: Forwarding updraft exit to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.exit_updraft()


## Teleports player to [param new_position] with brief stun period.
func teleport_to(new_position: Vector3, stun_time: float = 0.1) -> void:
	print("Player: Teleporting player to: ", new_position)
	global_position = new_position
	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	if stun_time > 0.0 and is_instance_valid(system_menu):
		system_menu.is_stunned = true
		Utilities.delay_call(self, stun_time, func() -> void: system_menu.is_stunned = false)


## Registers an active monkey bar handle on [member environment_component].
func set_available_monkey_bar(bar_node: Node3D) -> void:
	print("Player: Setting active monkey bar handle.")
	if is_instance_valid(environment_component):
		environment_component.available_monkey_bar = bar_node


## Clears active monkey bar handle on [member environment_component].
func clear_available_monkey_bar(bar_node: Node3D) -> void:
	print("Player: Clearing active monkey bar handle.")
	if (
		is_instance_valid(environment_component)
		and environment_component.available_monkey_bar == bar_node
	):
		environment_component.available_monkey_bar = null


## Returns true if zipline interaction cooldown is currently active.
func has_zipline_cooldown() -> bool:
	if is_instance_valid(environment_component):
		return environment_component.zipline_cooldown > 0.0
	return false


## Attaches player to zipline traversal segment.
func _on_zipline_grabbed(zipline_node: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	print("Player: Traversing zipline segment.")
	if is_instance_valid(environment_component):
		environment_component.enter_zipline(zipline_node, start_pos, end_pos)


## Attaches player to physics rope link.
func _on_rope_grabbed(rope_node: RigidBody3D) -> void:
	print("Player: Gripping rope link.")
	if is_instance_valid(environment_component):
		environment_component.enter_rope(rope_node)


## Toggles visibility of equipped glider mesh.
func set_glider_visible(p_is_visible: bool) -> void:
	print("Player: Updating glider mesh visibility: ", p_is_visible)
	if (
		is_instance_valid(interaction_component)
		and is_instance_valid(interaction_component.held_item)
	):
		var item: RigidBody3D = interaction_component.held_item
		if item.has_method(&"set_glider_mesh_visible"):
			item.call(&"set_glider_mesh_visible", p_is_visible)


# --------------------------------------
# STATE & MACHINE ROUTING
# --------------------------------------


## Focuses camera and input on the specified [param terminal] node.
func enter_terminal_mode(terminal: Node3D) -> void:
	print("Player: Entering terminal focus mode.")
	is_in_terminal_mode = true
	velocity = Vector3.ZERO

	var captures_wasd: bool = false
	if is_instance_valid(terminal):
		var wasd_variant: Variant = terminal.get(&"captures_wasd")
		captures_wasd = wasd_variant == true

	if captures_wasd and is_instance_valid(state_machine):
		state_machine.transition_to(&"Terminal", {"terminal": terminal})

	if is_instance_valid(interaction_component):
		interaction_component.is_in_terminal_mode = true
		if is_instance_valid(interaction_component.interaction_scanner):
			interaction_component.interaction_scanner.enter_terminal_mode(terminal)


## Activates primary player camera as the current viewport camera.
func activate_gameplay_camera() -> void:
	print("Player: Re-asserting primary gameplay camera.")
	if is_instance_valid(camera_controller) and is_instance_valid(camera_controller.camera):
		camera_controller.camera.make_current()
		if Events.has_signal("player_camera_registered"):
			Events.player_camera_registered.emit(camera_controller.camera)


## Exits terminal mode and restores default camera and movement control.
func exit_terminal_mode() -> void:
	if not is_in_terminal_mode and not is_terminal_locked:
		return

	print("Player: Restoring movement and camera look.")
	is_in_terminal_mode = false
	is_terminal_locked = false
	terminal_mouse_sensitivity_scale = 1.0

	if is_instance_valid(locomotion_component):
		locomotion_component.set_physics_active(true)

	if is_instance_valid(state_machine) and state_machine.is_in_state(&"Terminal"):
		state_machine.transition_to(&"Ground")

	if is_instance_valid(interaction_component):
		interaction_component.is_in_terminal_mode = false
		if is_instance_valid(interaction_component.interaction_scanner):
			interaction_component.interaction_scanner.exit_terminal_mode()


## Updates machine lock state and transitions state machine.
func set_machine_lock(locked: bool) -> void:
	print("Player: Setting machine lock state to: ", locked)
	if is_instance_valid(interaction_component):
		interaction_component.is_operating_machine = locked

	if is_instance_valid(state_machine):
		if locked:
			state_machine.transition_to(&"MachineLock")
		else:
			state_machine.transition_to(&"Ground")


## Engages machine operation mode and zeroes velocity momentum.
func start_operating_machine() -> void:
	print("Player: Engaging machine operation.")
	if is_instance_valid(interaction_component):
		interaction_component.is_operating_machine = true

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	if is_instance_valid(state_machine):
		state_machine.transition_to(&"MachineLock")


## Disengages machine operation mode and restores default controls.
func stop_operating_machine() -> void:
	print("Player: Disengaging machine operation.")
	if is_instance_valid(interaction_component):
		interaction_component.is_operating_machine = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if is_instance_valid(state_machine):
		state_machine.transition_to(&"Ground")


# --------------------------------------
# SAVE / LOAD SYSTEM INTERFACE
# --------------------------------------


## Returns serialized player position, rotation, and component stats.
func get_save_data() -> Dictionary:
	print("Player: Serializing state data.")
	var data: Dictionary = {}
	if is_instance_valid(stats_component):
		data = stats_component.get_save_data()

	data["pos_x"] = global_position.x
	data["pos_y"] = global_position.y
	data["pos_z"] = global_position.z
	data["rot_y"] = global_rotation.y

	if is_instance_valid(camera_controller):
		data["head_rot_x"] = camera_controller.global_rotation.x
		data["head_rot_y"] = camera_controller.global_rotation.y

	return data


## Restores serialized player coordinates, rotation, and component state.
func load_save_data(data: Dictionary) -> void:
	print("Player: Restoring serialized state data.")

	var loaded_pos: Vector3 = global_position
	if data.has("pos_x"):
		loaded_pos.x = float(data["pos_x"])
	if data.has("pos_y"):
		loaded_pos.y = float(data["pos_y"])
	if data.has("pos_z"):
		loaded_pos.z = float(data["pos_z"])

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	global_position = loaded_pos
	if data.has("rot_y"):
		global_rotation.y = float(data["rot_y"])

	if is_instance_valid(camera_controller):
		var pitch: float = camera_controller.global_rotation.x
		var yaw: float = camera_controller.global_rotation.y
		if data.has("head_rot_x"):
			pitch = float(data["head_rot_x"])
		if data.has("head_rot_y"):
			yaw = float(data["head_rot_y"])
		camera_controller.global_rotation = Vector3(pitch, yaw, 0.0)

	if is_instance_valid(stats_component):
		stats_component.load_save_data(data)


## Forwards rain entrance notification to [member environment_component].
func enter_rain_volume() -> void:
	print("Player: Entering rain volume.")
	if is_instance_valid(environment_component):
		environment_component.enter_rain_volume()


## Forwards rain exit notification to [member environment_component].
func exit_rain_volume() -> void:
	print("Player: Exiting rain volume.")
	if is_instance_valid(environment_component):
		environment_component.exit_rain_volume()


## Starts guide rail slide movement along target spline [param stick].
func enter_path_slide(stick: Node3D) -> void:
	print("Player: Entering rail slide.")

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	if is_instance_valid(state_machine):
		state_machine.transition_to(&"PathSlide", {"stick": stick})


## Exits rail slide state into airborne state.
func exit_path_slide() -> void:
	print("Player: Exiting rail slide.")
	if is_instance_valid(state_machine):
		state_machine.transition_to(&"Air")


## Launches player along [param throw_vel] impulse vector.
func launch_from_path(throw_vel: Vector3) -> void:
	print("Player: Launching from path with velocity: ", throw_vel)
	velocity = throw_vel
	if is_instance_valid(state_machine):
		state_machine.transition_to(&"Air", {"release_dir": throw_vel})


# --------------------------------------
# HEALTH & DAMAGE ROUTING
# --------------------------------------


## Routes damage reduction to [member health_component].
func take_damage(amount: int) -> void:
	print("Player: Routing damage to HealthComponent: ", amount)
	if is_instance_valid(health_component):
		health_component.take_damage(amount)


## Routes health point recovery to [member health_component].
func heal(amount: int) -> void:
	print("Player: Routing healing to HealthComponent: ", amount)
	if is_instance_valid(health_component):
		health_component.heal(amount)


## Applies impulse force [param force] and enters airborne state.
func apply_knockback(force: Vector3) -> void:
	print("Player: Applying knockback force and transitioning to Air state.")
	if is_instance_valid(state_machine):
		state_machine.transition_to(&"Air", {"knockback_force": force})


## Zero-allocation floor scan updating sand and ice surface state.
func _update_floor_surface_detection() -> void:
	var on_sand: bool = false
	var on_ice: bool = false

	if is_on_floor():
		var collision_count: int = get_slide_collision_count()
		for i: int in range(collision_count):
			var collision: KinematicCollision3D = get_slide_collision(i)
			if collision.get_normal().dot(up_direction) > 0.5:
				var collider: Object = collision.get_collider()
				if is_instance_valid(collider) and collider is Node:
					var floor_node: Node = collider as Node
					if floor_node.is_in_group(GROUP_SAND):
						on_sand = true
					if floor_node.is_in_group(GROUP_ICE):
						on_ice = true

	if on_sand != is_on_sand_surface:
		is_on_sand_surface = on_sand
		print("Player: Sand surface changed -> ", is_on_sand_surface)
		Events.sand_surface_toggled.emit(is_on_sand_surface)
		if is_instance_valid(locomotion_component):
			locomotion_component.can_sprint = not is_on_sand_surface

	if on_ice != is_on_ice_surface:
		is_on_ice_surface = on_ice
		print("Player: Ice surface changed -> ", is_on_ice_surface)
		Events.ice_surface_toggled.emit(is_on_ice_surface)


## Enters vacuum tube transport sequence with [param tube_node].
func enter_tube(tube_node: Node3D) -> void:
	print("Player: Entering vacuum tube state.")
	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()
	if is_instance_valid(state_machine):
		state_machine.transition_to(&"Tube", {"tube": tube_node})


## Ejects player from vacuum tube with [param throw_vel] velocity.
func exit_tube(throw_vel: Vector3) -> void:
	print("Player: Exiting tube with impulse velocity: ", throw_vel)
	launch_from_path(throw_vel)


## Logs entrance into water detector [param area] volume.
func _on_water_detector_area_entered(area: Area3D) -> void:
	print("Player: Entered water volume -> ", area.name)


## Logs exit from water detector [param area] volume.
func _on_water_detector_area_exited(area: Area3D) -> void:
	print("Player: Exited water volume -> ", area.name)


## Handles direct health change requests dispatched via [Events].
func _on_health_set_requested(amount: int) -> void:
	print("Player: Health set requested via event bus -> ", amount)
	if is_instance_valid(health_component):
		health_component.current_health = amount
		health_component.health_changed.emit(amount)
		if health_component.is_player_health:
			Events.player_health_changed.emit(amount)
		if amount <= 0:
			_on_player_died()


## Handles flight mode toggles dispatched via [Events].
func _on_flight_mode_toggled(is_flying: bool) -> void:
	print("Player: Flight mode toggled via event bus -> ", is_flying)
	if is_instance_valid(system_menu):
		system_menu.flying = is_flying
	if is_instance_valid(locomotion_component):
		locomotion_component.set_physics_active(not is_flying)


## Updates cinematic lock state and halts locomotion momentum.
func _on_cinematic_lock_requested(locked: bool) -> void:
	print("Player: Cinematic lock state updated -> ", locked)
	is_cinematic_locked = locked
	if locked:
		velocity = Vector3.ZERO
		if is_instance_valid(locomotion_component):
			locomotion_component.set_physics_active(false)
	elif is_instance_valid(locomotion_component):
		locomotion_component.set_physics_active(true)
