## A 3D keypad terminal that projects a 2D user interface onto a mesh.
##
## Players interact with the keypad via injected raycast events. Successfully entering
## the correct code triggers assigned target nodes and powers up connected mechanics.
class_name DoorKeypad
extends StaticBody3D

## Emitted when the correct code has been successfully entered and validated.
@warning_ignore("unused_signal")
signal code_accepted

## The required combination string needed to unlock the connected devices.
@export var valid_code: String = "1234"

## A list of nodes that will receive power or open signals when the code is accepted.
@export var targets: Array[Node3D]

## An editor-only mesh used to draw lines connecting the keypad to its targets.
var debug_line: MeshInstance3D

## The physical mesh onto which the UI texture is projected.
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

## The viewport that renders and manages the 2D UI elements.
@onready var sub_viewport: SubViewport = $SubViewport

## Handles player raycast detection and interaction prompts.
@onready var interact_component: InteractComponent = $InteractComponent

## The audio player responsible for spatialized button clicks and UI sounds.
@onready var keypad_audio: AudioStreamPlayer3D = $KeypadAudio


## Connects UI signals, configures one-shot viewport updates, and sets interaction callbacks.
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Freeze SubViewport by default to eliminate per-frame 512x512 render passes
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	if is_instance_valid(interact_component):
		interact_component.interacted.connect(_on_player_interacted)

	if sub_viewport.get_child_count() > 0:
		var ui: Control = sub_viewport.get_child(0) as Control
		if ui and ui.has_signal("code_entered"):
			ui.code_entered.connect(_on_ui_code_entered)
		if ui and ui.has_signal("button_clicked"):
			ui.button_clicked.connect(_on_ui_button_clicked)
		if ui and ui.has_signal("display_updated"):
			ui.connect("display_updated", request_viewport_refresh)


## Triggers a single frame redraw of the keypad [SubViewport].
func request_viewport_refresh() -> void:
	if is_instance_valid(sub_viewport):
		print("DoorKeypad: Refreshing SubViewport texture pass.")
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Plays the click sound effect when the player interacts with an active UI button.
## [param _button_name] The string identifier of the pressed button.
func _on_ui_button_clicked(_button_name: String) -> void:
	print("DoorKeypad: Playing spatialized button click sound.")
	if is_instance_valid(keypad_audio) and keypad_audio.stream != null:
		keypad_audio.play()
	request_viewport_refresh()


## Continuously redraws the connection lines between the keypad and its targets in the editor.
## [param _delta] Frame delta time.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


## Puts the player into terminal interaction mode, restricting movement and enabling the cursor.
## [param character] The player initiating the interaction.
func _on_player_interacted(character: CharacterBody3D) -> void:
	print("DoorKeypad: Player interacting with keypad.")
	request_viewport_refresh()
	if character.has_method("enter_terminal_mode"):
		character.enter_terminal_mode(self)


## Translates a 3D world coordinate raycast hit into a 2D [SubViewport] coordinate.
## [param global_hit] The exact world-space position where the raycast hit the mesh.
## [return] The mapped 2D coordinate on the UI viewport.
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


## Converts a raycast position into a mocked mouse motion event for the UI.
## [param global_hit] The continuous 3D point the player is aiming at.
func inject_mouse_motion(global_hit: Vector3) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	var pos: Vector2 = get_viewport_pos_from_3d(global_hit)
	event.device = 1
	event.position = pos
	event.global_position = pos
	sub_viewport.push_input(event)


## Simulates a left mouse button press down event on the internal 2D viewport UI.
## [param global_hit] The 3D point where the click occurred.
func inject_mouse_click(global_hit: Vector3) -> void:
	print("DoorKeypad: Injecting mouse click at ", global_hit)
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


## Finalizes a simulated mouse click by passing a release event to the UI viewport.
## [param pos] The 2D coordinate where the release should register.
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


## Validates the sequence typed by the player on the UI overlay.
## [param code] The final string submitted by the UI component.
func _on_ui_code_entered(code: String) -> void:
	var ui: Control = sub_viewport.get_child(0) as Control

	if code == valid_code:
		print("DoorKeypad: The code is correct!")
		code_accepted.emit()
		_trigger_targets()
		if ui and ui.has_method("display_result"):
			ui.call("display_result", true)
	else:
		print("DoorKeypad: Invalid code entered.")
		if ui and ui.has_method("display_result"):
			ui.call("display_result", false)
	request_viewport_refresh()


## Iterates through all connected target nodes and forwards power activation signals.
func _trigger_targets() -> void:
	print("DoorKeypad: Triggering connected power targets.")
	for target: Node3D in targets:
		if target == null:
			continue

		if target.has_method("add_power"):
			target.call("add_power")
		else:
			var comp: Node = target.get_node_or_null("PowerComponent")
			if comp and comp.has_method("add_power"):
				comp.call("add_power")
			elif "open" in target:
				target.set("open", true)


## Renders debug lines in the editor window showing exactly what nodes this keypad controls.
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


## Forces the simulated mouse position entirely off-screen to clear any stuck UI hover states.
func clear_mouse_hover() -> void:
	print("DoorKeypad: Clearing SubViewport mouse hover state.")
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.device = 1

	var off_screen_pos: Vector2 = Vector2(-1000.0, -1000.0)
	event.position = off_screen_pos
	event.global_position = off_screen_pos
	sub_viewport.push_input(event)
	request_viewport_refresh()
