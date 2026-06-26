extends StaticBody3D
class_name DoorKeypad

signal code_accepted

@export var valid_code: String = "1234"
@export var targets: Array[Node3D]

var debug_line: MeshInstance3D

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
@onready var sub_viewport: SubViewport = $SubViewport
@onready var interact_component: Interact_Component = $Interact_Component
@onready var keypad_audio: AudioStreamPlayer3D = $KeypadAudio

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if interact_component:
		interact_component.interacted.connect(_on_player_interacted)

	if sub_viewport.get_child_count() > 0:
		var ui: Control = sub_viewport.get_child(0)
		if ui.has_signal("code_entered"):
			ui.code_entered.connect(_on_ui_code_entered)
		if ui.has_signal("button_clicked"):
			ui.button_clicked.connect(_on_ui_button_clicked)

func _on_ui_button_clicked(_button_name: String) -> void:
	print("DoorKeypad: Playing spatialized button click sound.")
	if keypad_audio and keypad_audio.stream != null:
		keypad_audio.play()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


func _on_player_interacted(character: CharacterBody3D) -> void:
	print("DoorKeypad: Player interacting with keypad.")
	if character.has_method("enter_terminal_mode"):
		character.enter_terminal_mode(self)


func get_viewport_pos_from_3d(global_hit: Vector3) -> Vector2:
	var local_pos: Vector3 = mesh_instance_3d.to_local(global_hit)
	var aabb: AABB = mesh_instance_3d.mesh.get_aabb()

	var percent_x: float = 0.5
	if aabb.size.x > 0.001:
		percent_x = (local_pos.x - aabb.position.x) / aabb.size.x
	
	var percent_y: float = 0.5
	if aabb.size.y > 0.001:
		percent_y = 1.0 - ((local_pos.y - aabb.position.y) / aabb.size.y)

	# Clamp bounds to prevent division errors from throwing the cursor off-screen
	percent_x = clampf(percent_x, 0.0, 1.0)
	percent_y = clampf(percent_y, 0.0, 1.0)

	return Vector2(percent_x * sub_viewport.size.x, percent_y * sub_viewport.size.y)


func inject_mouse_motion(global_hit: Vector3) -> void:
	var event := InputEventMouseMotion.new()
	var pos: Vector2 = get_viewport_pos_from_3d(global_hit)
	event.device = 1 # Hardware ID isolation
	event.position = pos
	event.global_position = pos
	sub_viewport.push_input(event)


func inject_mouse_click(global_hit: Vector3) -> void:
	print("DoorKeypad: Injecting mouse click at ", global_hit)
	var pos: Vector2 = get_viewport_pos_from_3d(global_hit)
	
	var event_press := InputEventMouseButton.new()
	event_press.device = 1
	event_press.button_index = MOUSE_BUTTON_LEFT
	event_press.button_mask = MOUSE_BUTTON_MASK_LEFT
	event_press.position = pos
	event_press.global_position = pos
	event_press.pressed = true
	sub_viewport.push_input(event_press)
	
	# Delay the mouse release by exactly one frame so the UI registers the click down state
	get_tree().process_frame.connect(_release_mouse_click.bind(pos), CONNECT_ONE_SHOT)


func _release_mouse_click(pos: Vector2) -> void:
	var event_release := InputEventMouseButton.new()
	event_release.device = 1
	event_release.button_index = MOUSE_BUTTON_LEFT
	event_release.button_mask = 0
	event_release.position = pos
	event_release.global_position = pos
	event_release.pressed = false
	sub_viewport.push_input(event_release)


func _on_ui_code_entered(code: String) -> void:
	var ui: Control = sub_viewport.get_child(0)
	
	if code == valid_code:
		print("DoorKeypad: The code is correct!")
		code_accepted.emit()
		_trigger_targets()
		if ui and ui.has_method("display_result"):
			ui.display_result(true)
	else:
		print("DoorKeypad: Invalid code entered.")
		if ui and ui.has_method("display_result"):
			ui.display_result(false)


func _trigger_targets() -> void:
	for target: Node3D in targets:
		if target == null:
			continue

		if target.has_method("add_power"):
			target.add_power()
		else:
			var comp: Node = target.get_node_or_null("PowerComponent")
			if comp and comp.has_method("add_power"):
				comp.add_power()
			elif "open" in target:
				target.open = true


func _draw_connection_line() -> void:
	if targets.is_empty():
		if debug_line:
			debug_line.queue_free()
			debug_line = null
		return

	if not debug_line or not is_instance_valid(debug_line):
		debug_line = MeshInstance3D.new()
		add_child(debug_line)
		var immediate_mesh := ImmediateMesh.new()
		debug_line.mesh = immediate_mesh
		var mat := StandardMaterial3D.new()
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


func clear_mouse_hover() -> void:
	print("DoorKeypad: Clearing SubViewport mouse hover state.")
	var event := InputEventMouseMotion.new()
	event.device = 1
	
	var off_screen_pos := Vector2(-1000.0, -1000.0)
	event.position = off_screen_pos
	event.global_position = off_screen_pos
	sub_viewport.push_input(event)
