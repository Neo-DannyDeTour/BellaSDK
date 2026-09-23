## Universal 3D terminal projecting swappable 2D UIs onto a physical mesh.
class_name DoorKeypad
extends StaticBody3D

## Emitted when the keypad puzzle has been solved.
@warning_ignore("unused_signal")
signal code_accepted

## The packed UI scene instantiated inside the terminal viewport.
@export var ui_scene: PackedScene

## Valid combination code string for numeric style keypads.
@export var valid_code: String = "1234"

## Target nodes powered or triggered when puzzle is solved.
@export var targets: Array[Node3D]

## Indicates if directional keys should be consumed by terminal.
@export var captures_wasd: bool = false

## Debug line renderer displaying connection links to targets.
var debug_line: MeshInstance3D

## Active player instance currently engaged with terminal.
var active_player: CharacterBody3D = null

## Active UI control instantiated in the viewport.
var current_ui: Control = null

## Target mesh receiving UI projection material.
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

## SubViewport rendering interactive 2D interface.
@onready var sub_viewport: SubViewport = $DoorKeypadSubViewport

## Raycast and interaction collider detector component.
@onready var interact_component: InteractComponent = $InteractComponent

## Spatial audio player for button and error sounds.
@onready var keypad_audio: AudioStreamPlayer3D = $KeypadAudio


## Sets up viewport rendering, instantiates assigned UI scene, and connects signals.
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_setup_ui_instance()

	if is_instance_valid(interact_component):
		interact_component.interacted.connect(_on_player_interacted)


## Instantiates exported UI scene inside the SubViewport.
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


## Redraws targets connection lines while editing in editor.
## [param _delta] Frame delta time in seconds.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


## Intercepts WASD inputs when active and routes to UI.
## [param event] Engine hardware input event.
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


## Handles player terminal engagement, activating dynamic redraws.
## [param character] Interacting player instance.
func _on_player_interacted(character: CharacterBody3D) -> void:
	print("DoorKeypad: Player entered terminal.")
	active_player = character
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if is_instance_valid(current_ui):
		if current_ui.has_method("set_player_reference"):
			current_ui.call("set_player_reference", character)
		if current_ui.has_method("start_puzzle"):
			current_ui.call("start_puzzle")

	request_viewport_refresh()
	if character.has_method("enter_terminal_mode"):
		character.enter_terminal_mode(self)


## Clears active interaction state and restores frozen viewport.
func clear_mouse_hover() -> void:
	print("DoorKeypad: Player exited terminal. Halting puzzle.")
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


## Requests single redraw pass when viewport is frozen.
func request_viewport_refresh() -> void:
	if is_instance_valid(sub_viewport):
		if sub_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Plays sound effects on UI interactions.
## [param _button_name] Pressed button identifier.
func _on_ui_button_clicked(_button_name: String) -> void:
	print("DoorKeypad: Playing interaction audio cue.")
	if is_instance_valid(keypad_audio) and keypad_audio.stream != null:
		keypad_audio.play()


## Validates submitted code and activates connected mechanics.
## [param code] String sequence sent by UI.
func _on_ui_code_entered(code: String) -> void:
	print("DoorKeypad: Validating submitted code -> ", code)
	var is_correct: bool = (code == valid_code) or captures_wasd

	if is_correct:
		print("DoorKeypad: Unlock validated.")
		code_accepted.emit()
		_trigger_targets()
		if is_instance_valid(current_ui) and current_ui.has_method("display_result"):
			current_ui.call("display_result", true)
	else:
		print("DoorKeypad: Unlock rejected.")
		if is_instance_valid(current_ui) and current_ui.has_method("display_result"):
			current_ui.call("display_result", false)


## Forwards power activation signals to target nodes.
func _trigger_targets() -> void:
	print("DoorKeypad: Activating target mechanics.")
	for target: Node3D in targets:
		if not is_instance_valid(target):
			continue
		if target.has_method("add_power"):
			target.call("add_power")
		else:
			var comp: Node = target.get_node_or_null("PowerComponent")
			if comp and comp.has_method("add_power"):
				comp.call("add_power")
			elif "open" in target:
				target.set("open", true)


## Maps world-space raycast hit position to 2D SubViewport coordinates.
## [param global_hit] World hit coordinate.
## [return] Mapped 2D viewport coordinates.
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


## Injects mouse motion into SubViewport.
## [param global_hit] World raycast hit position.
func inject_mouse_motion(global_hit: Vector3) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	var pos: Vector2 = get_viewport_pos_from_3d(global_hit)
	event.device = 1
	event.position = pos
	event.global_position = pos
	sub_viewport.push_input(event)


## Injects mouse click event into SubViewport.
## [param global_hit] World raycast hit position.
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


## Sends mouse release event into SubViewport.
## [param pos] 2D coordinates to release.
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


## Renders debug lines connecting keypad to targets in editor.
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
