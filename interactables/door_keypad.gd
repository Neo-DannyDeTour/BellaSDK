## Universal 3D terminal projecting swappable 2D UIs onto a physical mesh.
@tool
class_name DoorKeypad
extends StaticBody3D

## Emitted when [member valid_code] is accepted and targets trigger.
@warning_ignore("unused_signal")
signal code_accepted

@onready var output_transmitter: OutputTransmitter3D = $OutputTransmitter3D

## Packed UI scene instantiated inside [member sub_viewport].
@export var ui_scene: PackedScene

## Valid combination code string for numeric keypads.
@export var valid_code: String = "1234"

## Target nodes powered when puzzle is solved.
@export var targets: Array[Node3D]

## Determines if WASD inputs are captured for minigames.
@export var captures_wasd: bool = false

## Mouse sensitivity scale applied to player look for numeric UI.
@export var numeric_mouse_sensitivity_scale: float = 0.5

## Tracks whether the terminal puzzle has been successfully solved.
var is_solved: bool = false

## Line renderer displaying links to [member targets] in editor.
var debug_line: MeshInstance3D

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


## Initializes viewport and binds interaction signals.
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_setup_ui_instance()

	if is_instance_valid(interact_component):
		interact_component.interacted.connect(_on_player_interacted)


## Instantiates [member ui_scene] in [member sub_viewport].
func _setup_ui_instance() -> void:
	print("DoorKeypad: Setting up SubViewport UI instance.")
	if sub_viewport.get_child_count() > 0:
		for child: Node in sub_viewport.get_children():
			child.queue_free()

	if ui_scene != null:
		current_ui = ui_scene.instantiate() as Control
		sub_viewport.add_child(current_ui)
	elif sub_viewport.get_child_count() > 0:
		current_ui = sub_viewport.get_child(0) as Control

	if not is_instance_valid(current_ui):
		return

	if current_ui.has_signal("code_entered"):
		current_ui.connect("code_entered", _on_ui_code_entered)
	if current_ui.has_signal("button_clicked"):
		current_ui.connect("button_clicked", _on_ui_button_clicked)
	if current_ui.has_signal("display_updated"):
		current_ui.connect("display_updated", request_viewport_refresh)

	if current_ui is UICircleTimingKeypad:
		captures_wasd = true


## Draws connection lines to [member targets] in editor.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


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
			print("DoorKeypad: Consuming key for timing minigame -> ", key_str)
			if current_ui.has_method("handle_key_input"):
				current_ui.call("handle_key_input", key_str)
			get_viewport().set_input_as_handled()


## Engages terminal mode and scales player mouse sensitivity.
func _on_player_interacted(character: CharacterBody3D) -> void:
	if is_solved and current_ui is UICircleTimingKeypad:
		print("DoorKeypad: Circle minigame already solved. Interaction denied.")
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
		print("DoorKeypad: Scaling mouse sensitivity to 0.5x for numeric keypad.")
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
	if is_instance_valid(sub_viewport):
		if sub_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Plays audio cue when interface buttons are pressed.
func _on_ui_button_clicked(_button_name: String) -> void:
	print("DoorKeypad: Playing interaction audio cue.")
	if is_instance_valid(keypad_audio) and keypad_audio.stream != null:
		keypad_audio.play()


## Validates code, fires triggers, and initiates exit.
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
		get_tree().create_timer(1.2).timeout.connect(_exit_terminal)
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

	get_tree().process_frame.connect(_release_mouse_click.bind(pos), CONNECT_ONE_SHOT)


## Releases simulated mouse button in [member sub_viewport].
func _release_mouse_click(pos: Vector2) -> void:
	var event_release: InputEventMouseButton = InputEventMouseButton.new()
	event_release.device = 1
	event_release.button_index = MOUSE_BUTTON_LEFT
	event_release.button_mask = 0
	event_release.position = pos
	event_release.global_position = pos
	event_release.pressed = false
	sub_viewport.push_input(event_release)
	request_viewport_refresh()


## Renders debug link lines to [member targets] in editor.
func _draw_connection_line() -> void:
	if targets.is_empty():
		if is_instance_valid(debug_line):
			debug_line.queue_free()
			debug_line = null
		return

	if not is_instance_valid(debug_line):
		debug_line = MeshInstance3D.new()
		add_child(debug_line)
		var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
		debug_line.mesh = immediate_mesh
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.DEEP_SKY_BLUE
		debug_line.material_override = mat

	var mesh: ImmediateMesh = debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for target: Node3D in targets:
		if target != null and is_instance_valid(target):
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(to_local(target.global_position))

	mesh.surface_end()
