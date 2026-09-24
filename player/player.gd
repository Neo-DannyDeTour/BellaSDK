## Central controller entity coordinating locomotion, input routing, and accessibility actions.
class_name Player
extends CharacterBody3D

# --------------------------------------
# COMPONENT REFERENCES (Cached for 60 FPS)
# --------------------------------------
@export_category("Core Modules")
## Handles all physics, gravity, and state machine locomotion.
@export var locomotion_component: Node

## Handles raycasting, item holding, and machine interfaces.
@export var interaction_component: Node

## Handles external triggers (water, rain, updrafts, ladders).
@export var environment_component: Node

## Manages health, damage, and save data serialization.
@export var stats_component: Node

## The root State Machine controlling player states.
@export var state_machine: Node

@export_category("System References")
## Controls the camera's rotation, positioning, and visual effects (FOV, shake).
@export var camera_controller: CameraController

## Manages all system-level menus, pause state, and noclip functionality.
@export var system_menu: SystemMenuController

## Reference to the main UI controller for HUD and screen effects.
@export var ui_controller: UIController

## Reference to the global UI console overlay for entering debug commands.
var in_game_console: CanvasLayer

## Handles toggling the player's flashlight and managing its battery consumption.
var flashlight_controller: FlashlightController

## Local node reference for receiving and managing the player's health points.
@onready var health_component: HealthComponent = $Components/HealthComponent

## Indicates if the player character has died, used to globally block input and physics.
var is_dead: bool = false

## Flag indicating if the player is actively standing on a surface grouped as "sand".
var is_on_sand_surface: bool = false

## Flag indicating if the player is actively standing on a surface grouped as "ice".
var is_on_ice_surface: bool = false

## Indicates if the player is currently focused on an active terminal.
var is_in_terminal_mode: bool = false

## Indicates if movement and camera look are locked by a minigame terminal.
var is_terminal_locked: bool = false

## Sensitivity scale applied to mouse look during terminal interactions.
var terminal_mouse_sensitivity_scale: float = 1.0


# --------------------------------------
# INITIALIZATION
# --------------------------------------
## Lifecycle method called when the node enters the scene tree.
func _ready() -> void:
	print("Player: Initializing character controller.")
	add_to_group("saveable")
	add_to_group("player")

	if not is_instance_valid(health_component):
		health_component = (get_node_or_null("Components/HealthComponent") as HealthComponent)

	call_deferred("_capture_mouse")
	activate_gameplay_camera()

	in_game_console = (
		(
			get_node_or_null("/root/InGameConsole") as CanvasLayer
			if has_node("/root/InGameConsole")
			else get_node_or_null("/root/Console")
		)
		as CanvasLayer
	)

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
		if not health_component.died.is_connected(_on_player_died):
			health_component.died.connect(_on_player_died)


## Locks and hides the mouse cursor for first-person gameplay navigation.
func _capture_mouse() -> void:
	print("Player: Capturing mouse cursor.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --------------------------------------
# INPUT ROUTING
# --------------------------------------
## Routes hardware mouse motion into the camera controller.
## [param event] The [InputEvent] received from the engine.
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


## Handles unhandled hardware events, routing interaction component events.
## [param event] The [InputEvent] to evaluate.
func _unhandled_input(event: InputEvent) -> void:
	if _is_input_blocked():
		return

	if is_instance_valid(interaction_component):
		interaction_component.process_unhandled_input(event)


## Sets mouse look sensitivity multiplier for terminal interfaces.
## [param p_scale] Mouse sensitivity multiplier value.
func set_terminal_mouse_sensitivity_scale(p_scale: float) -> void:
	print("Player: Setting terminal mouse sensitivity scale to: ", p_scale)
	terminal_mouse_sensitivity_scale = p_scale


## Evaluates if UI overlays, menus, terminals, or death states should block gameplay input.
## [return] True if player inputs should be ignored.
func _is_input_blocked() -> bool:
	var is_console_open: bool = is_instance_valid(in_game_console) and in_game_console.visible
	var is_operating: bool = (
		is_instance_valid(interaction_component)
		and bool(interaction_component.get("is_operating_machine"))
	)
	var is_blocked: bool = (
		(
			is_instance_valid(system_menu)
			and (
				system_menu.is_paused
				or system_menu.is_menu_open
				or bool(system_menu.get("is_stunned"))
			)
		)
		or is_console_open
		or is_operating
		or is_dead
	)
	return is_blocked


## Queries the gesture manager for the spatial description action.
func _handle_describe_input() -> void:
	if not is_instance_valid(GestureInputManager):
		return

	if GestureInputManager.is_action_just_triggered("describe_surroundings"):
		print("Player: Describe surroundings triggered via gesture manager.")
		if Events.has_signal("describe_surroundings_requested"):
			Events.describe_surroundings_requested.emit(self)


## Handles player death by locking locomotion, evaluating death pose, and broadcasting events.
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
		elif (
			locomotion_component.has_method("did_run_recently")
			and locomotion_component.did_run_recently()
		):
			current_death_state = DeathScreen.DeathState.SPRINTING
			print("Player: Death state evaluated as SPRINTING.")
		else:
			print("Player: Death state evaluated as WALKING.")

	if Events.has_signal("player_died"):
		Events.player_died.emit(current_death_state)


# --------------------------------------
# MASTER PHYSICS ROUTING
# --------------------------------------
## Master physics update loop driving state machines, locomotion, and interaction polling.
## [param delta] The physics frame delta time in seconds.
func _physics_process(delta: float) -> void:
	var in_terminal_state: bool = (
		is_terminal_locked
		or (is_instance_valid(state_machine) and state_machine.state.name == "Terminal")
	)

	if in_terminal_state:
		velocity = Vector3.ZERO
		if is_instance_valid(locomotion_component):
			locomotion_component.set_physics_active(false)

		if is_instance_valid(interaction_component):
			if interaction_component.has_method("process_interaction"):
				interaction_component.process_interaction(delta)
			elif (
				interaction_component.get("interaction_scanner")
				and interaction_component.interaction_scanner.has_method("process_interaction")
			):
				interaction_component.interaction_scanner.process_interaction(delta)
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

	if (
		is_instance_valid(environment_component)
		and environment_component.has_method("process_environment_physics")
	):
		environment_component.process_environment_physics(delta)

	if is_instance_valid(interaction_component):
		if interaction_component.has_method("process_interaction"):
			interaction_component.process_interaction(delta)
		elif (
			interaction_component.get("interaction_scanner")
			and interaction_component.interaction_scanner.has_method("process_interaction")
		):
			interaction_component.interaction_scanner.process_interaction(delta)


# --------------------------------------
# ENVIRONMENTAL ADAPTERS (Facade)
# --------------------------------------
## Attaches player locomotion to a ladder volume.
## [param ladder_node] The ladder [Node3D] instance.
func enter_ladder(ladder_node: Node3D) -> void:
	print("Player: Forwarding ladder enter to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.enter_ladder(ladder_node)


## Detaches player locomotion from an active ladder volume.
## [param ladder_node] The ladder [Node3D] instance.
func exit_ladder(ladder_node: Node3D) -> void:
	print("Player: Forwarding ladder exit to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.exit_ladder(ladder_node)


## Switches movement logic to swimming physics inside a water body.
## [param water_volume] The water volume [Node3D].
func enter_water(water_volume: Node3D) -> void:
	print("Player: Forwarding water enter to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.enter_water(water_volume)


## Exits swimming state and restores ground/air physics.
## [param water_volume] The water volume [Node3D].
func exit_water(water_volume: Node3D) -> void:
	print("Player: Forwarding water exit to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.exit_water(water_volume)


## Applies upward vertical force from an updraft vent.
## [param strength] Force scalar applied to vertical velocity.
## [param top_y] Maximum height cap of the updraft.
func enter_updraft(strength: float, top_y: float) -> void:
	print("Player: Forwarding updraft enter to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.enter_updraft(strength, top_y)


## Exits the updraft airflow zone.
func exit_updraft() -> void:
	print("Player: Forwarding updraft exit to EnvironmentComponent.")
	if is_instance_valid(environment_component):
		environment_component.exit_updraft()


## Relocates the player directly to target coordinates with optional input stun.
## [param new_position] Destination [Vector3] coordinates.
## [param stun_time] Stun duration in seconds to lock controls.
func teleport_to(new_position: Vector3, stun_time: float = 0.1) -> void:
	print("Player: Teleporting player to: ", new_position)
	global_position = new_position
	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	if stun_time > 0.0 and is_instance_valid(system_menu):
		system_menu.is_stunned = true
		get_tree().create_timer(stun_time).timeout.connect(
			func() -> void: system_menu.is_stunned = false
		)


## Registers a monkey bar handle in reach of the player.
## [param bar_node] Target bar [Node3D].
func set_available_monkey_bar(bar_node: Node3D) -> void:
	print("Player: Setting active monkey bar handle.")
	if is_instance_valid(environment_component):
		environment_component.available_monkey_bar = bar_node


## Unregisters a monkey bar handle when out of reach.
## [param bar_node] Target bar [Node3D].
func clear_available_monkey_bar(bar_node: Node3D) -> void:
	print("Player: Clearing active monkey bar handle.")
	if (
		is_instance_valid(environment_component)
		and environment_component.available_monkey_bar == bar_node
	):
		environment_component.available_monkey_bar = null


## Checks whether the zipline interaction cooldown is currently active.
## [return] True if still on cooldown.
func has_zipline_cooldown() -> bool:
	if is_instance_valid(environment_component):
		return environment_component.zipline_cooldown > 0.0
	return false


## Starts traversing an active zipline segment.
## [param zipline_node] Zipline [Node3D] reference.
## [param start_pos] World coordinates of the line starting point.
## [param end_pos] World coordinates of the line destination point.
func _on_zipline_grabbed(zipline_node: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	print("Player: Traversing zipline segment.")
	if is_instance_valid(environment_component):
		environment_component.enter_zipline(zipline_node, start_pos, end_pos)


## Attaches the player to a physical rope segment.
## [param rope_node] The [RigidBody3D] rope link gripped.
func _on_rope_grabbed(rope_node: RigidBody3D) -> void:
	print("Player: Gripping rope link.")
	if is_instance_valid(environment_component):
		environment_component.enter_rope(rope_node)


## Updates visibility of the equipped glider mesh.
## [param p_is_visible] Whether the glider should be rendered.
func set_glider_visible(p_is_visible: bool) -> void:
	print("Player: Updating glider mesh visibility: ", p_is_visible)
	if (
		is_instance_valid(interaction_component)
		and is_instance_valid(interaction_component.held_item)
	):
		var item: RigidBody3D = interaction_component.held_item
		if item.has_method("set_glider_mesh_visible"):
			item.set_glider_mesh_visible(p_is_visible)


# --------------------------------------
# STATE & MACHINE ROUTING
# --------------------------------------
## Activates interactive terminal camera and UI focus mode.
## [param terminal] The terminal [Node3D] interacted with.
func enter_terminal_mode(terminal: Node3D) -> void:
	print("Player: Entering terminal focus mode.")
	is_in_terminal_mode = true
	velocity = Vector3.ZERO

	var captures_wasd: bool = is_instance_valid(terminal) and bool(terminal.get("captures_wasd"))
	if captures_wasd and is_instance_valid(state_machine):
		state_machine.transition_to("Terminal", {"terminal": terminal})

	if is_instance_valid(interaction_component):
		interaction_component.set("is_in_terminal_mode", true)
		if is_instance_valid(interaction_component.interaction_scanner):
			interaction_component.interaction_scanner.enter_terminal_mode(terminal)


## Re-asserts the player's primary camera as the active viewport camera.
func activate_gameplay_camera() -> void:
	print("Player: Re-asserting primary gameplay camera.")
	if is_instance_valid(camera_controller) and is_instance_valid(camera_controller.camera):
		camera_controller.camera.make_current()


## Restores player locomotion and camera controls after terminal exit.
func exit_terminal_mode() -> void:
	if not is_in_terminal_mode and not is_terminal_locked:
		return

	print("Player: Restoring movement and camera look.")
	is_in_terminal_mode = false
	is_terminal_locked = false
	terminal_mouse_sensitivity_scale = 1.0

	if is_instance_valid(locomotion_component):
		locomotion_component.set_physics_active(true)

	if is_instance_valid(state_machine) and state_machine.state.name == "Terminal":
		state_machine.transition_to("Ground")

	if is_instance_valid(interaction_component):
		interaction_component.set("is_in_terminal_mode", false)
		if (
			is_instance_valid(interaction_component.interaction_scanner)
			and interaction_component.interaction_scanner.is_in_terminal_mode
		):
			interaction_component.interaction_scanner.exit_terminal_mode()


## Locks locomotion while the player operates fixed machinery.
## [param locked] Whether control is locked to machine operation.
func set_machine_lock(locked: bool) -> void:
	print("Player: Setting machine lock state to: ", locked)
	if is_instance_valid(interaction_component):
		interaction_component.is_operating_machine = locked

	if is_instance_valid(state_machine):
		if locked:
			state_machine.transition_to("MachineLock")
		else:
			state_machine.transition_to("Ground")


## Engages machine operation mode and resets physics momentum.
func start_operating_machine() -> void:
	print("Player: Engaging machine operation.")
	if is_instance_valid(interaction_component):
		interaction_component.is_operating_machine = true

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	if is_instance_valid(state_machine):
		state_machine.transition_to("MachineLock")


## Disengages machine operation mode and restores first-person controls.
func stop_operating_machine() -> void:
	print("Player: Disengaging machine operation.")
	if is_instance_valid(interaction_component):
		interaction_component.is_operating_machine = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if is_instance_valid(state_machine):
		state_machine.transition_to("Ground")


# --------------------------------------
# SAVE / LOAD SYSTEM INTERFACE
# --------------------------------------
## Serializes player spatial coordinates, camera rotation, and stats into a dictionary.
## [return] Serialized data payload [Dictionary].
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


## Deserializes and restores player position, camera pitch/yaw, and component state.
## [param data] Serialized data payload [Dictionary].
func load_save_data(data: Dictionary) -> void:
	print("Player: Restoring serialized state data.")

	var loaded_pos: Vector3 = Vector3(
		data.get("pos_x", global_position.x),
		data.get("pos_y", global_position.y),
		data.get("pos_z", global_position.z)
	)

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	global_position = loaded_pos
	global_rotation.y = data.get("rot_y", global_rotation.y)

	if is_instance_valid(camera_controller):
		var pitch: float = data.get("head_rot_x", camera_controller.global_rotation.x)
		var yaw: float = data.get("head_rot_y", camera_controller.global_rotation.y)
		camera_controller.global_rotation = Vector3(pitch, yaw, 0.0)

	if is_instance_valid(stats_component):
		stats_component.load_save_data(data)


## Notifies the environment component of entering a rain volume.
func enter_rain_volume() -> void:
	print("Player: Entering rain volume.")
	if is_instance_valid(environment_component):
		environment_component.enter_rain_volume()


## Notifies the environment component of exiting a rain volume.
func exit_rain_volume() -> void:
	print("Player: Exiting rain volume.")
	if is_instance_valid(environment_component):
		environment_component.exit_rain_volume()


## Initiates a sliding animation sequence along a guide rail.
## [param stick] The rail guide [Node3D].
func enter_path_slide(stick: Node3D) -> void:
	print("Player: Entering rail slide.")

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	if is_instance_valid(state_machine):
		state_machine.transition_to("PathSlide", {"stick": stick})


## Ends an active rail sliding sequence.
func exit_path_slide() -> void:
	print("Player: Exiting rail slide.")
	if is_instance_valid(state_machine):
		state_machine.transition_to("Air")


## Launches the player from a rail or slide with an impulse velocity.
## [param throw_vel] Ejection velocity vector [Vector3].
func launch_from_path(throw_vel: Vector3) -> void:
	print("Player: Launching from path with velocity: ", throw_vel)
	velocity = throw_vel
	if is_instance_valid(state_machine):
		state_machine.transition_to("Air", {"release_dir": throw_vel})


# --------------------------------------
# HEALTH & DAMAGE ROUTING
# --------------------------------------
## Forwards damage application requests to the HealthComponent.
## [param amount] Damage value to apply.
func take_damage(amount: int) -> void:
	print("Player: Routing damage to HealthComponent: ", amount)
	if is_instance_valid(health_component) and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


## Forwards healing point additions to the HealthComponent.
## [param amount] Healing value to apply.
func heal(amount: int) -> void:
	print("Player: Routing healing to HealthComponent: ", amount)
	if is_instance_valid(health_component) and health_component.has_method("heal"):
		health_component.heal(amount)


## Applies directional impulse force and transitions player into airborne state.
## [param force] Knockback velocity vector [Vector3].
func apply_knockback(force: Vector3) -> void:
	print("Player: Applying knockback force and transitioning to Air state.")

	if is_instance_valid(state_machine):
		if state_machine.has_method("transition_to"):
			state_machine.transition_to("Air", {"knockback_force": force})


## Evaluates the current floor collider and notifies UI of surface changes.
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
					if floor_node.is_in_group(&"sand"):
						on_sand = true
					if floor_node.is_in_group(&"ice"):
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


## Transitions locomotion into the vacuum tube transport state.
func enter_tube(tube_node: Node3D) -> void:
	print("Player: Entering vacuum tube state.")
	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()
	if is_instance_valid(state_machine):
		state_machine.transition_to("Tube", {"tube": tube_node})


## Ejects the player from a tube and transfers velocity into airborne state.
func exit_tube(throw_vel: Vector3) -> void:
	print("Player: Exiting tube with impulse velocity: ", throw_vel)
	launch_from_path(throw_vel)
