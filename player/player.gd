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

## Reference to the global UI console overlay for entering debug commands.
var in_game_console: CanvasLayer

## Handles toggling the player's flashlight and managing its battery consumption.
var flashlight_controller: FlashlightController

## Local node reference for receiving and managing the player's health points.
@onready var health_component: HealthComponent = $Components/HealthComponent

## Indicates if the player character has died, used to globally block input and physics.
var is_dead: bool = false

## Duration in seconds the player must hold the key to trigger the spatial description.
const DESCRIBE_HOLD_THRESHOLD: float = 0.4

## Accumulator tracking how long the describe button has been held.
var _describe_hold_timer: float = 0.0

## Tracks if the describe action has already fired during the current button press.
var _describe_triggered: bool = false


# --------------------------------------
# INITIALIZATION
# --------------------------------------
## Lifecycle method called when the node enters the scene tree.
## Configures groups, captures mouse, and initializes attached components.
func _ready() -> void:
	add_to_group("saveable")
	add_to_group("player")

	call_deferred("_capture_mouse")

	in_game_console = get_node_or_null("/root/Console") as CanvasLayer

	locomotion_component.initialize(self)
	interaction_component.initialize(self)
	environment_component.initialize(self)
	stats_component.initialize(self)

	_bridge_health_signals()

	if is_instance_valid(health_component):
		if not health_component.died.is_connected(_on_player_died):
			health_component.died.connect(_on_player_died)


## Locks and hides the mouse cursor for first-person gameplay navigation.
func _capture_mouse() -> void:
	print("Player: _capture_mouse() called. Capturing mouse cursor.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --------------------------------------
# INPUT ROUTING
# --------------------------------------
## Routes hardware mouse motion into the camera controller.
## [param event] The [InputEvent] received from the engine.
func _input(event: InputEvent) -> void:
	print("Player: _input() called. Routing hardware input.")
	if _is_input_blocked():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_controller.handle_mouse_input(
			event,
			interaction_component.is_in_terminal_mode,
			interaction_component.is_heavy_lifting,
			interaction_component.heavy_lift_yaw_base
		)


## Handles unhandled hardware events, routing sonar ping and interaction gestures.
## [param event] The [InputEvent] to evaluate.
func _unhandled_input(event: InputEvent) -> void:
	print("Player: _unhandled_input() called. Routing input.")
	if _is_input_blocked():
		return

	if InputMap.has_action(&"sonar_ping") and event.is_action_pressed(&"sonar_ping"):
		print("Player: Sonar ping triggered via input action. Emitting to Events bus.")
		if Events.has_signal("sonar_ping_requested"):
			Events.sonar_ping_requested.emit(self)
		get_viewport().set_input_as_handled()
		return

	interaction_component.process_unhandled_input(event)


## Evaluates if UI overlays, menus, terminals, or death states should block gameplay input.
## Returns true if player inputs should be ignored.
func _is_input_blocked() -> bool:
	var is_console_open: bool = (
		is_instance_valid(in_game_console) and in_game_console.visible
	)
	var is_blocked: bool = (
		system_menu.is_paused
		or system_menu.is_menu_open
		or system_menu.get("is_stunned")
		or is_console_open
		or interaction_component.is_operating_machine
		or is_dead
	)
	return is_blocked


## Evaluates the hold timer for the spatial interactables description action.
## [param delta] The physics frame delta time in seconds.
func _handle_describe_input(delta: float) -> void:
	if not InputMap.has_action(&"describe_surroundings"):
		return

	if Input.is_action_pressed(&"describe_surroundings"):
		_describe_hold_timer += delta
		if _describe_hold_timer >= DESCRIBE_HOLD_THRESHOLD and not _describe_triggered:
			_describe_triggered = true
			print("Player: Hold threshold reached. Emitting describe surroundings request.")
			if Events.has_signal("describe_surroundings_requested"):
				Events.describe_surroundings_requested.emit(self)
	else:
		_describe_hold_timer = 0.0
		_describe_triggered = false


## Handles player death by locking locomotion, evaluating death pose, and broadcasting events.
func _on_player_died() -> void:
	print("Player: _on_player_died() called. Locking controls and broadcasting death.")
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
	var disable_states: bool = _is_input_blocked() or system_menu.flying

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
		locomotion_component.set_physics_active(false)
		velocity = Vector3.ZERO
		return

	_handle_describe_input(delta)

	if system_menu.flying:
		locomotion_component.set_physics_active(false)
		system_menu.process_noclip(delta)
		return

	locomotion_component.set_physics_active(true)
	locomotion_component.process_movement(delta)
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
	print("Player: enter_ladder() called. Forwarding to EnvironmentComponent.")
	environment_component.enter_ladder(ladder_node)


## Detaches player locomotion from an active ladder volume.
## [param ladder_node] The ladder [Node3D] instance.
func exit_ladder(ladder_node: Node3D) -> void:
	print("Player: exit_ladder() called. Forwarding to EnvironmentComponent.")
	environment_component.exit_ladder(ladder_node)


## Switches movement logic to swimming physics inside a water body.
## [param water_volume] The water volume [Node3D].
func enter_water(water_volume: Node3D) -> void:
	print("Player: enter_water() called. Forwarding to EnvironmentComponent.")
	environment_component.enter_water(water_volume)


## Exits swimming state and restores ground/air physics.
## [param water_volume] The water volume [Node3D].
func exit_water(water_volume: Node3D) -> void:
	print("Player: exit_water() called. Forwarding to EnvironmentComponent.")
	environment_component.exit_water(water_volume)


## Applies upward vertical force from an updraft vent.
## [param strength] Force scalar applied to vertical velocity.
## [param top_y] Maximum height cap of the updraft.
func enter_updraft(strength: float, top_y: float) -> void:
	print("Player: enter_updraft() called. Forwarding to EnvironmentComponent.")
	environment_component.enter_updraft(strength, top_y)


## Exits the updraft airflow zone.
func exit_updraft() -> void:
	print("Player: exit_updraft() called. Forwarding to EnvironmentComponent.")
	environment_component.exit_updraft()


## Relocates the player directly to target coordinates with optional input stun.
## [param new_position] Destination [Vector3] coordinates.
## [param stun_time] Stun duration in seconds to lock controls.
func teleport_to(new_position: Vector3, stun_time: float = 0.1) -> void:
	print("Player: teleport_to() called. Forwarding to LocomotionComponent.")
	global_position = new_position
	locomotion_component.reset_momentum()

	if stun_time > 0.0:
		system_menu.is_stunned = true
		get_tree().create_timer(stun_time).timeout.connect(
			func() -> void: system_menu.is_stunned = false
		)


## Registers a monkey bar handle in reach of the player.
## [param bar_node] Target bar [Node3D].
func set_available_monkey_bar(bar_node: Node3D) -> void:
	print("Player: set_available_monkey_bar() called.")
	environment_component.available_monkey_bar = bar_node


## Unregisters a monkey bar handle when out of reach.
## [param bar_node] Target bar [Node3D].
func clear_available_monkey_bar(bar_node: Node3D) -> void:
	print("Player: clear_available_monkey_bar() called.")
	if environment_component.available_monkey_bar == bar_node:
		environment_component.available_monkey_bar = null


## Checks whether the zipline interaction cooldown is currently active.
## Returns true if still on cooldown.
func has_zipline_cooldown() -> bool:
	return environment_component.zipline_cooldown > 0.0


## Starts traversing an active zipline segment.
## [param zipline_node] Zipline [Node3D] reference.
## [param start_pos] World coordinates of the line starting point.
## [param end_pos] World coordinates of the line destination point.
func _on_zipline_grabbed(zipline_node: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	print("Player: _on_zipline_grabbed() called.")
	environment_component.enter_zipline(zipline_node, start_pos, end_pos)


## Attaches the player to a physical rope segment.
## [param rope_node] The [RigidBody3D] rope link gripped.
func _on_rope_grabbed(rope_node: RigidBody3D) -> void:
	print("Player: _on_rope_grabbed() called.")
	environment_component.enter_rope(rope_node)


## Updates visibility of the equipped glider mesh.
## [param p_is_visible] Whether the glider should be rendered.
func set_glider_visible(p_is_visible: bool) -> void:
	print("Player: set_glider_visible() called. Forwarding to InteractionComponent.")
	if is_instance_valid(interaction_component.held_item):
		var item: RigidBody3D = interaction_component.held_item
		if item.has_method("set_glider_mesh_visible"):
			item.set_glider_mesh_visible(p_is_visible)


# --------------------------------------
# STATE & MACHINE ROUTING
# --------------------------------------
## Activates interactive terminal camera and UI focus mode.
## [param terminal] The terminal [Node3D] interacted with.
func enter_terminal_mode(terminal: Node3D) -> void:
	print("Player: enter_terminal_mode() called.")
	interaction_component.interaction_scanner.enter_terminal_mode(terminal)


## Locks locomotion while the player operates fixed machinery.
## [param locked] Whether control is locked to machine operation.
func set_machine_lock(locked: bool) -> void:
	print("Player: set_machine_lock() called. Locked: ", locked)
	interaction_component.is_operating_machine = locked

	if locked:
		state_machine.transition_to("MachineLock")
	else:
		state_machine.transition_to("Ground")


## Engages machine operation mode and resets physics momentum.
func start_operating_machine() -> void:
	print("Player: start_operating_machine() called.")
	interaction_component.is_operating_machine = true

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	$StateMachine.transition_to("MachineLock")


## Disengages machine operation mode and restores first-person controls.
func stop_operating_machine() -> void:
	print("Player: stop_operating_machine() called.")
	interaction_component.is_operating_machine = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	$StateMachine.transition_to("Ground")


# --------------------------------------
# SAVE / LOAD SYSTEM INTERFACE
# --------------------------------------
## Serializes player spatial coordinates, camera rotation, and stats into a dictionary.
## Returns serialized data payload [Dictionary].
func get_save_data() -> Dictionary:
	print("Player: get_save_data() called. Gathering component data.")
	var data: Dictionary = stats_component.get_save_data()

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
	print("Player: load_save_data() called. Restoring component data.")

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

	stats_component.load_save_data(data)


## Notifies the environment component of entering a rain volume.
func enter_rain_volume() -> void:
	print("Player: enter_rain_volume() called.")
	environment_component.enter_rain_volume()


## Notifies the environment component of exiting a rain volume.
func exit_rain_volume() -> void:
	print("Player: exit_rain_volume() called.")
	environment_component.exit_rain_volume()


## Initiates a sliding animation sequence along a guide rail.
## [param stick] The rail guide [Node3D].
func enter_path_slide(stick: Node3D) -> void:
	print("Player: enter_path_slide() called.")

	if is_instance_valid(locomotion_component):
		locomotion_component.reset_momentum()

	state_machine.transition_to("PathSlide", {"stick": stick})


## Ends an active rail sliding sequence.
func exit_path_slide() -> void:
	print("Player: exit_path_slide() called.")
	state_machine.transition_to("Air")


## Launches the player from a rail or slide with an impulse velocity.
## [param throw_vel] Ejection velocity vector [Vector3].
func launch_from_path(throw_vel: Vector3) -> void:
	print("Player: launch_from_path() called with velocity: ", throw_vel)
	velocity = throw_vel
	state_machine.transition_to("Air", {"release_dir": throw_vel})


## Connects local health component signals to the event bus.
func _bridge_health_signals() -> void:
	print("Player: _bridge_health_signals() connecting local HealthComponent.")

	if is_instance_valid(health_component):
		if not health_component.health_changed.is_connected(_on_local_health_changed):
			health_component.health_changed.connect(_on_local_health_changed)
			print("Player: Successfully bridged HealthComponent to global Events.")
	else:
		push_warning("Player: HealthComponent node not found at $Components/HealthComponent!")


## Forwards health change events from the local component to the global event bus.
## [param new_health] Current health value.
func _on_local_health_changed(new_health: int) -> void:
	if (
		Events.has_user_signal("player_health_changed")
		or Events.has_signal("player_health_changed")
	):
		print("Player: Broadcasting health change to Events bus: ", new_health)
		Events.player_health_changed.emit(new_health)


# --------------------------------------
# HEALTH & DAMAGE ROUTING
# --------------------------------------
## Forwards damage application requests to the HealthComponent.
## [param amount] Damage value to apply.
func take_damage(amount: int) -> void:
	print("Player: take_damage() called. Routing ", amount, " damage to HealthComponent.")
	if is_instance_valid(health_component) and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


## Forwards healing point additions to the HealthComponent.
## [param amount] Healing value to apply.
func heal(amount: int) -> void:
	print("Player: heal() called. Routing ", amount, " healing to HealthComponent.")
	if is_instance_valid(health_component) and health_component.has_method("heal"):
		health_component.heal(amount)


## Applies directional impulse force and transitions player into airborne state.
## [param force] Knockback velocity vector [Vector3].
func apply_knockback(force: Vector3) -> void:
	print("Player: apply_knockback() called. Forcing transition to Air state.")

	if is_instance_valid(state_machine):
		if state_machine.has_method("transition_to"):
			state_machine.transition_to("Air", {"knockback_force": force})
