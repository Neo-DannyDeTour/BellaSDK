## Interactive physical or static valve mechanism that transmits turning progress to receivers.
## Manages installation states, player interactions, rotation animations, and accessibility prompts.
@tool
class_name Valve
extends StaticBody3D

## The time window in seconds to register two consecutive presses as a double tap.
const DOUBLE_TAP_DELAY: float = 0.3

@export_category("Connections")
## The list of target nodes. These are automatically forwarded to a child [OutputTransmitter3D].
@export var targets: Array[Node3D]:
	set(value):
		targets = value
		_update_transmitter_targets()

@export_category("Installation Settings")
## Determines if the valve is missing by default and needs to be attached by the player.
@export var requires_installation: bool = false
## The [PackedScene] used to spawn the physics-based valve when detached.
@export var pickable_valve_scene: PackedScene

## Allows the player to double-tap to remove the valve, dropping it into the world.
@export var can_be_detached: bool = false:
	set(value):
		can_be_detached = value
		if can_be_detached:
			lock_when_finished = false

@export_category("Valve Settings")
## The total time in seconds it takes to fully turn the valve.
@export var turn_duration: float = 3.0
## How many full 360-degree visual spins the wheel makes during a full turn.
@export var visual_rotations: float = 2.0
## The visual spin direction of the valve wheel.
@export var turn_clockwise: bool = true

## If true, the valve can no longer be interacted with once it reaches 100% progress.
@export var lock_when_finished: bool = false:
	set(value):
		lock_when_finished = value
		if lock_when_finished:
			can_be_detached = false

## If true, turning the valve cycles progress between 0.0 and 1.0 continuously.
@export var is_back_and_forth: bool = true:
	set(value):
		is_back_and_forth = value
		if is_back_and_forth:
			reverts_on_release = false

## If true, the valve will slowly spin back to 0.0 or 1.0 when the player lets go.
@export var reverts_on_release: bool = false:
	set(value):
		reverts_on_release = value
		if reverts_on_release:
			is_back_and_forth = false
		else:
			fast_revert_on_release = false

## If true, releasing the valve causes it to revert to its resting state at an accelerated speed.
@export var fast_revert_on_release: bool = false:
	set(value):
		fast_revert_on_release = value
		if fast_revert_on_release:
			reverts_on_release = true

## The speed multiplier applied when the valve is quickly reverting to its resting state.
@export var fast_revert_multiplier: float = 4.0
## The local axis around which the valve wheel mesh will spin.
@export var spin_axis: Vector3 = Vector3(0, 1, 0)
## The 3D label used to display interaction prompts to the player.
@export var label: Label3D
## The shader material applied to highlight the detached valve item.
@export var outline_material: ShaderMaterial

## The audio stream player responsible for playing turning sounds.
@onready var valve_audio: AudioStreamPlayer3D = get_node_or_null("ValveAudio")

## The current normalized turning progress (0.0 to 1.0).
var progress: float = 0.0
## Tracks whether the player is currently looking directly at the valve.
var is_focused: bool = false
## The current target progress the valve is moving toward (either 0.0 or 1.0).
var current_target_progress: float = 1.0
## Tracks whether the valve has permanently locked into its final state.
var is_locked: bool = false
## Stores the interaction state of the previous frame to detect initial presses and releases.
var was_interacting: bool = false
## Tracks whether the physical valve is currently attached to the base.
var is_installed: bool = true
## A timestamp tracking the last time the player pressed the interact button.
var last_interact_time: float = 0.0
## The visual wheel node that rotates when the valve is turned.
var wheel: Node3D
## The original rotational state of the wheel used to calculate relative spin angles.
var initial_rotation: Vector3
## The component responsible for drawing an outline when the player looks at the valve.
var highlight_comp: Node
## A brief cooldown preventing immediate re-attachment right after detaching.
var install_cooldown: float = 0.0
## Tracks whether the valve has been installed at least once, used for label text logic.
var has_been_installed: bool = false
## A cached reference to the player node to avoid redundant scene tree queries.
var _cached_player: Node3D = null
## Cached reference to the child transmitter component to prevent per-frame node lookups.
var _transmitter: OutputTransmitter3D = null


## Initializes valve installation states, cached references, and binds interaction listeners.
func _ready() -> void:
	print("Valve: Initializing _ready() lifecycle.")
	_update_transmitter_targets()

	if requires_installation:
		is_installed = false
		has_been_installed = false
	else:
		has_been_installed = true

	if Engine.is_editor_hint():
		return

	wheel = get_node_or_null("Valve")
	if is_instance_valid(wheel):
		initial_rotation = wheel.rotation_degrees
		if requires_installation:
			wheel.hide()
	else:
		push_warning("Valve: Please group meshes under Node3D named 'Valve'!")

	highlight_comp = get_node_or_null("HighlightComponent")

	var interact_comp: Node = get_node_or_null("InteractComponent")
	if is_instance_valid(interact_comp):
		if not interact_comp.focused.is_connected(_on_interact_component_focused):
			interact_comp.focused.connect(_on_interact_component_focused)
		if not interact_comp.unfocused.is_connected(_on_interact_component_unfocused):
			interact_comp.unfocused.connect(_on_interact_component_unfocused)


## Manages per-frame installation detection, player interaction inputs, rotation, and audio state.
## [param delta] The elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_transmitter_targets()
		return

	if install_cooldown > 0.0:
		install_cooldown -= delta

	if not is_installed and install_cooldown <= 0.0:
		if not is_instance_valid(_cached_player):
			_cached_player = (get_tree().get_first_node_in_group("player") as Node3D)

		if is_instance_valid(_cached_player):
			var held: Node3D = _get_player_held_object(_cached_player)

			if is_instance_valid(held):
				var dist_sq: float = global_position.distance_squared_to(held.global_position)
				if dist_sq < 0.36:
					_install_valve(_cached_player, held)

	var is_interacting: bool = (
		is_focused and GestureInputManager.is_action_pressed("interact") and is_installed
	)
	var just_pressed: bool = (
		is_focused and Input.is_action_just_pressed("interact") and is_installed
	)

	if can_be_detached and just_pressed:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		if current_time - last_interact_time <= DOUBLE_TAP_DELAY:
			_detach_valve()
			last_interact_time = 0.0
			return
		last_interact_time = current_time

	if is_locked:
		_manage_audio(false)
		return

	if is_instance_valid(highlight_comp) and highlight_comp.has_method("suppress"):
		highlight_comp.suppress(is_interacting)

	if is_interacting and not was_interacting:
		if is_back_and_forth and progress > 0.0 and progress < 1.0:
			current_target_progress = (0.0 if current_target_progress == 1.0 else 1.0)

	var old_progress: float = progress

	if is_interacting:
		progress = move_toward(progress, current_target_progress, delta / turn_duration)
		if lock_when_finished and progress >= 1.0:
			is_locked = true
			progress = 1.0
	else:
		if reverts_on_release:
			var revert_target: float = 0.0 if current_target_progress == 1.0 else 1.0
			var current_turn_duration: float = turn_duration

			if fast_revert_on_release:
				current_turn_duration = (turn_duration / fast_revert_multiplier)
				if was_interacting:
					print("Valve: Released, initiating fast revert towards ", revert_target)

			progress = move_toward(progress, revert_target, delta / current_turn_duration)

	if is_back_and_forth and not is_interacting:
		if progress >= 1.0:
			current_target_progress = 0.0
		elif progress <= 0.0:
			current_target_progress = 1.0

	var is_moving: bool = not is_equal_approx(progress, old_progress)

	if is_moving:
		if is_instance_valid(wheel):
			var dir_multiplier: float = -1.0 if turn_clockwise else 1.0
			var total_angle: float = 360.0 * visual_rotations * dir_multiplier * progress
			wheel.rotation_degrees = (initial_rotation + (spin_axis * total_angle))

		var transmitter: OutputTransmitter3D = _get_transmitter()
		if is_instance_valid(transmitter):
			transmitter.transmit_progress(progress)

	_manage_audio(is_moving)
	was_interacting = is_interacting


## Retrieves and caches the first child node that inherits from [OutputTransmitter3D].
## Returns the child transmitter if found, otherwise returns `null`.
func _get_transmitter() -> OutputTransmitter3D:
	if is_instance_valid(_transmitter):
		return _transmitter
	for child: Node in get_children():
		if child is OutputTransmitter3D:
			_transmitter = child as OutputTransmitter3D
			return _transmitter
	return null


## Safely propagates target scene nodes to the child [OutputTransmitter3D].
func _update_transmitter_targets() -> void:
	if not is_inside_tree():
		return
	var transmitter: OutputTransmitter3D = _get_transmitter()
	if is_instance_valid(transmitter):
		transmitter.targets = targets


## Starts or stops the valve rotation sound effect according to movement state.
## [param is_moving] Indicates whether the valve progress is currently moving.
func _manage_audio(is_moving: bool) -> void:
	if not is_instance_valid(valve_audio):
		return

	if is_moving and not valve_audio.playing:
		print("Valve: Started playing turning audio.")
		valve_audio.play()
	elif not is_moving and valve_audio.playing:
		print("Valve: Stopped turning audio.")
		valve_audio.stop()


## Resolves the object currently held by the player character.
## [param player] The player node reference to inspect.
## Returns the held [Node3D] instance if found, or `null`.
func _get_player_held_object(player: Node3D) -> Node3D:
	if not is_instance_valid(player):
		return null

	if "held_object" in player and player.get("held_object") != null:
		return player.get("held_object") as Node3D

	var int_comp: Node = (
		player.get("interaction_component") if "interaction_component" in player else null
	)
	if is_instance_valid(int_comp):
		if "held_item" in int_comp and int_comp.get("held_item") != null:
			return int_comp.get("held_item") as Node3D

		var scanner: Node = (
			int_comp.get("interaction_scanner") if "interaction_scanner" in int_comp else null
		)
		if (
			is_instance_valid(scanner)
			and "held_object" in scanner
			and scanner.get("held_object") != null
		):
			return scanner.get("held_object") as Node3D

	return null


## Resets all held item slots on the player character.
## [param player] The player node reference whose held object will be cleared.
func _clear_player_held_object(player: Node3D) -> void:
	print("Valve: Clearing player held object references.")
	if not is_instance_valid(player):
		return

	if "held_object" in player:
		player.set("held_object", null)

	var int_comp: Node = (
		player.get("interaction_component") if "interaction_component" in player else null
	)
	if is_instance_valid(int_comp):
		if int_comp.has_method("force_clear_hands"):
			int_comp.force_clear_hands()
		elif "held_item" in int_comp:
			int_comp.set("held_item", null)


## Attaches the held valve wheel onto this base unit and removes the item from the player.
## [param player] The player node performing the installation.
## [param held_valve] The item instance to destroy upon attachment.
func _install_valve(player: Node3D, held_valve: Node3D) -> void:
	print("Valve: _install_valve() called. Destroying pickable valve.")
	if is_instance_valid(held_valve):
		held_valve.queue_free()

	_clear_player_held_object(player)

	is_installed = true
	has_been_installed = true
	is_locked = false
	current_target_progress = 1.0

	if is_instance_valid(wheel):
		wheel.show()

	var weapon_holder: Node3D = player.get_node_or_null("%WeaponHolder") as Node3D
	if is_instance_valid(weapon_holder):
		weapon_holder.show()
	print("Valve: Valve Auto-Installed!")


## Spawns a physical pickable valve scene into the world and clears the base fixture.
func _detach_valve() -> void:
	print("Valve: _detach_valve() called.")
	if not pickable_valve_scene:
		push_warning("Cannot detach: No Pickable Valve Scene assigned!")
		return

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(player):
		return

	var spawned_valve: Node3D = pickable_valve_scene.instantiate() as Node3D

	if is_instance_valid(outline_material) and "outline_material" in spawned_valve:
		spawned_valve.set("outline_material", outline_material)

	get_tree().current_scene.add_child(spawned_valve)

	if "hold_position" in player and is_instance_valid(player.get("hold_position")):
		spawned_valve.global_position = player.get("hold_position").global_position

	if is_instance_valid(wheel):
		spawned_valve.global_position = wheel.global_position
		spawned_valve.global_rotation = wheel.global_rotation
	else:
		spawned_valve.global_position = global_position

	var grabbed_successfully: bool = false
	var int_comp: Node = (
		player.get("interaction_component") if "interaction_component" in player else null
	)

	if is_instance_valid(int_comp) and int_comp.has_method("force_grab_item"):
		int_comp.force_grab_item(spawned_valve as RigidBody3D)
		grabbed_successfully = true
	elif "held_object" in player:
		player.set("held_object", spawned_valve)

	if (
		not grabbed_successfully
		and spawned_valve.has_method("pick_up")
		and "hold_position" in player
	):
		spawned_valve.pick_up(player.get("hold_position"), player)

	var weapon_holder: Node3D = player.get_node_or_null("%WeaponHolder") as Node3D
	if is_instance_valid(weapon_holder) and not grabbed_successfully:
		weapon_holder.hide()

	is_installed = false
	is_locked = false
	install_cooldown = 1.0

	if is_instance_valid(wheel):
		wheel.hide()


## Handles the interaction component focus event to display and vocalize prompt labels.
func _on_interact_component_focused() -> void:
	print("Valve: _on_interact_component_focused() called.")
	if is_locked:
		return
	is_focused = true
	_update_valve_label()
	if is_instance_valid(label):
		label.show()


## Handles the interaction component unfocus event to hide the prompt label.
func _on_interact_component_unfocused() -> void:
	print("Valve: _on_interact_component_unfocused() called.")
	is_focused = false
	if is_instance_valid(label):
		label.hide()


## Updates the visual prompt text on [member label] and dispatches custom spoken text to TTSandy.
func _update_valve_label() -> void:
	print("Valve: _update_valve_label() called.")
	var prompt_text: String = ""
	var speech_text: String = ""

	if is_installed:
		var events: Array = InputMap.action_get_events("interact")
		var key_name: String = "???"

		if events.size() > 0:
			var raw_text: String = events[0].as_text()
			key_name = (
				raw_text
				. replace(" (Physical)", "")
				. replace(" - Physical", "")
				. replace(" (Physics)", "")
				. replace(" - Physics", "")
				. replace("Left Mouse Button", "LMB")
				. replace("Right Mouse Button", "RMB")
				. replace("Middle Mouse Button", "MMB")
				. strip_edges()
			)

		prompt_text = "Hold [%s]" % key_name
		speech_text = "Hold [%s] to turn the valve." % key_name

		if can_be_detached:
			prompt_text += "\nDouble tap [%s] to detach" % key_name
			speech_text += " Double tap [%s] to detach." % key_name
	elif has_been_installed:
		prompt_text = "Attach the valve"
		speech_text = prompt_text
	else:
		prompt_text = "Find the valve"
		speech_text = prompt_text

	if is_instance_valid(label):
		label.text = prompt_text

	if has_node("/root/Events"):
		var events_node: Node = get_node("/root/Events")
		if events_node.has_signal("object_focused") and not speech_text.is_empty():
			print("Valve: Broadcasting object_focused prompt to TTSandy.")
			events_node.object_focused.emit(speech_text, self)
