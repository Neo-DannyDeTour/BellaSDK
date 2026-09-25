@tool
## Universal 3D terminal projecting swappable 2D UIs onto a physical mesh.
##
## Handles 3D-to-2D input projection, code verification, and target dispatching.
class_name DoorKeypad
extends StaticBody3D

## Emitted when [member valid_code] is accepted and targets trigger.
@warning_ignore("unused_signal")
signal code_accepted

## Transmitter node powering connected target mechanisms upon puzzle solve.
@onready var output_transmitter: OutputTransmitter3D = $OutputTransmitter3D

## Packed UI scene instantiated inside [member sub_viewport].
@export var ui_scene: PackedScene

## Valid combination code string for numeric keypads.
@export var valid_code: String = "1234"

## Target nodes powered when puzzle is solved.
@export var targets: Array[Node3D] = []:
	set(value):
		targets = value
		_sync_targets_to_transmitter()

## Determines if WASD inputs are captured for minigames.
@export var captures_wasd: bool = false

## Mouse sensitivity scale applied to player look for numeric UI.
@export var numeric_mouse_sensitivity_scale: float = 0.5

## Tracks whether the terminal puzzle has been successfully solved.
var is_solved: bool = false

## Active player [CharacterBody3D] currently using terminal.
var active_player: CharacterBody3D = null

## Active [Control] interface inside [member sub_viewport].
var current_ui: Control = null

## Target [MeshInstance3D] receiving UI projection material.
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

## [SubViewport] rendering the active 2D interface.
@onready var sub_viewport: SubViewport = $DoorKeypadSubViewport

## Component detecting player interaction raycasts.
@onready var interact_component: InteractComponent = $InteractComponent

## Spatial audio player for terminal sound effects.
@onready var keypad_audio: AudioStreamPlayer3D = $KeypadAudio


## Initializes viewport, synchronizes targets, and binds interaction signals.
func _ready() -> void:
	_sync_targets_to_transmitter()

	if Engine.is_editor_hint():
		return

	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_setup_ui_instance()

	if is_instance_valid(interact_component):
		Utilities.safe_connect(interact_component.interacted, _on_player_interacted)


## Synchronizes [member targets] into internal [OutputTransmitter3D].
func _sync_targets_to_transmitter() -> void:
	if not is_inside_tree():
		return

	var transmitter: OutputTransmitter3D = output_transmitter
	if not is_instance_valid(transmitter) and has_node("OutputTransmitter3D"):
		transmitter = get_node("OutputTransmitter3D") as OutputTransmitter3D

	if is_instance_valid(transmitter):
		transmitter.targets = targets


## Instantiates [member ui_scene] in [member sub_viewport] using [Utilities].
func _setup_ui_instance() -> void:
	print("DoorKeypad: Setting up SubViewport UI instance.")
	if is_instance_valid(sub_viewport) and sub_viewport.get_child_count() > 0:
		Utilities.clear_children(sub_viewport)

	if ui_scene != null:
		current_ui = ui_scene.instantiate() as Control
		sub_viewport.add_child(current_ui)
	elif is_instance_valid(sub_viewport) and sub_viewport.get_child_count() > 0:
		current_ui = sub_viewport.get_child(0) as Control

	if not is_instance_valid(current_ui):
		return

	if current_ui.has_signal(&"code_entered"):
		Utilities.safe_connect(Signal(current_ui, &"code_entered"), _on_ui_code_entered)
	if current_ui.has_signal(&"button_clicked"):
		Utilities.safe_connect(Signal(current_ui, &"button_clicked"), _on_ui_button_clicked)
	if current_ui.has_signal(&"display_updated"):
		Utilities.safe_connect(Signal(current_ui, &"display_updated"), request_viewport_refresh)

	if current_ui is UICircleTimingKeypad:
		captures_wasd = true


## Routes WASD key input events to [member current_ui].
func _unhandled_input(event: InputEvent) -> void:
	if active_player == null or not captures_wasd or not is_instance_valid(current_ui):
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_ev: InputEventKey = event as InputEventKey
		var key_str: String = OS.get_keycode_string(key_ev.physical_keycode).to_upper()
		if key_str.is_empty():
			key_str = OS.get_keycode_string(key_ev.keycode).to_upper()

		if key_str in ["W", "A", "S", "D"]:
			print("DoorKeypad: Consuming key for minigame -> ", key_str)
			if current_ui.has_method("handle_key_input"):
				current_ui.call("handle_key_input", key_str)
			get_viewport().set_input_as_handled()


## Engages terminal mode and scales player mouse sensitivity.
func _on_player_interacted(character: CharacterBody3D) -> void:
	if is_solved and current_ui is UICircleTimingKeypad:
		print("DoorKeypad: Minigame already solved. Interaction denied.")
		return

	print("DoorKeypad: Player entered terminal.")
	active_player = character
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if is_instance_valid(current_ui):
		if current_ui.has_method("set_player_reference"):
			current_ui.call("set_player_reference", character)
		if current_ui.has_method("start_puzzle"):
			current_ui.call("start_puzzle")

	if current_ui is UIKeypad and character.has_method("set_terminal_mouse_sensitivity_scale"):
		print("DoorKeypad: Scaling mouse sensitivity for keypad.")
		character.call("set_terminal_mouse_sensitivity_scale", numeric_mouse_sensitivity_scale)

	request_viewport_refresh()
	if character.has_method("enter_terminal_mode"):
		character.enter_terminal_mode(self)


## Exits terminal mode and restores player sensitivity.
func _exit_terminal() -> void:
	print("DoorKeypad: Auto-exiting terminal mode.")
	if is_instance_valid(active_player) and active_player.has_method("exit_terminal_mode"):
		active_player.call("exit_terminal_mode")
	clear_mouse_hover()


## Clears active interaction state and freezes viewport.
func clear_mouse_hover() -> void:
	print("DoorKeypad: Player exited terminal. Halting puzzle.")
	if (
		is_instance_valid(active_player)
		and active_player.has_method("set_terminal_mouse_sensitivity_scale")
	):
		active_player.call("set_terminal_mouse_sensitivity_scale", 1.0)

	active_player = null
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	if is_instance_valid(current_ui) and current_ui.has_method("stop_puzzle"):
		current_ui.call("stop_puzzle")

	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.device = 1
	event.position = Vector2(-1000.0, -1000.0)
	event.global_position = event.position
	sub_viewport.push_input(event)
	request_viewport_refresh()


## Forces a single redraw pass on [member sub_viewport].
func request_viewport_refresh() -> void:
	print("DoorKeypad: Requesting SubViewport redraw pass.")
	if is_instance_valid(sub_viewport):
		if sub_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Plays audio cue when interface buttons are pressed.
func _on_ui_button_clicked(_button_name: String) -> void:
	print("DoorKeypad: Playing interaction audio cue.")
	if is_instance_valid(keypad_audio) and keypad_audio.stream != null:
		keypad_audio.play()


## Validates code, fires triggers, and schedules exit using [Utilities].
func _on_ui_code_entered(code: String) -> void:
	print("DoorKeypad: Validating submitted code -> ", code)
	var is_correct: bool = (code == valid_code) or captures_wasd

	if is_correct:
		print("DoorKeypad: Unlock validated.")
		if current_ui is UICircleTimingKeypad:
			is_solved = true
		code_accepted.emit()
		_trigger_targets()
		if is_instance_valid(current_ui) and current_ui.has_method("display_result"):
			current_ui.call("display_result", true)
		Utilities.delay_call(self, 1.2, _exit_terminal)
	else:
		print("DoorKeypad: Unlock rejected.")
		if is_instance_valid(current_ui) and current_ui.has_method("display_result"):
			current_ui.call("display_result", false)


## Powers attached [OutputTransmitter3D] child.
func _trigger_targets() -> void:
	print("DoorKeypad: Triggering OutputTransmitter3D.")
	if is_instance_valid(output_transmitter):
		output_transmitter.power_on()


## Maps 3D world raycast hit point to 2D viewport coordinates.
func get_viewport_pos_from_3d(global_hit: Vector3) -> Vector2:
	print("DoorKeypad: Mapping 3D world coordinate to 2D viewport.")
	var local_pos: Vector3 = mesh_instance_3d.to_local(global_hit)
	var aabb: AABB = mesh_instance_3d.mesh.get_aabb()

	var percent_x: float = 0.5
	if aabb.size.x > 0.001:
		percent_x = (local_pos.x - aabb.position.x) / aabb.size.x

	var percent_y: float = 0.5
	if aabb.size.y > 0.001:
		percent_y = 1.0 - ((local_pos.y - aabb.position.y) / aabb.size.y)

	percent_x = clampf(percent_x, 0.0, 1.0)
	percent_y = clampf(percent_y, 0.0, 1.0)
	return Vector2(percent_x * sub_viewport.size.x, percent_y * sub_viewport.size.y)


## Injects mouse motion into [member sub_viewport].
func inject_mouse_motion(global_hit: Vector3) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	var pos: Vector2 = get_viewport_pos_from_3d(global_hit)
	event.device = 1
	event.position = pos
	event.global_position = pos
	sub_viewport.push_input(event)


## Injects mouse button press into [member sub_viewport].
func inject_mouse_click(global_hit: Vector3) -> void:
	print("DoorKeypad: Injecting click at: ", global_hit)
	var pos: Vector2 = get_viewport_pos_from_3d(global_hit)
	var event_press: InputEventMouseButton = InputEventMouseButton.new()
	event_press.device = 1
	event_press.button_index = MOUSE_BUTTON_LEFT
	event_press.button_mask = MOUSE_BUTTON_MASK_LEFT
	event_press.position = pos
	event_press.global_position = pos
	event_press.pressed = true
	sub_viewport.push_input(event_press)

	Utilities.safe_connect(
		get_tree().process_frame, _release_mouse_click.bind(pos), Object.CONNECT_ONE_SHOT
	)


## Releases simulated mouse button in [member sub_viewport].
func _release_mouse_click(pos: Vector2) -> void:
	print("DoorKeypad: Releasing simulated mouse click at: ", pos)
	var event_release: InputEventMouseButton = InputEventMouseButton.new()
	event_release.device = 1
	event_release.button_index = MOUSE_BUTTON_LEFT
	event_release.button_mask = 0
	event_release.position = pos
	event_release.global_position = pos
	event_release.pressed = false
	sub_viewport.push_input(event_release)
	request_viewport_refresh()
