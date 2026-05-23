@tool
extends StaticBody3D
class_name DoorKeypad

signal code_accepted

@export var validCode: int = 1234
@export var targets: Array[Node3D]  # Assign the doors you want to open in the inspector!

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
@onready var sub_viewport: SubViewport = $SubViewport
@onready var interact_component: Interact_Component = $Interact_Component

# --- EDITOR DEBUG LINE ---
var debug_line: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Listen for the player interaction!
	if interact_component:
		interact_component.interacted.connect(_on_player_interacted)

	# (Keep your existing SubViewport UI connections here)
	if sub_viewport.get_child_count() > 0:
		var ui := sub_viewport.get_child(0)
		if ui.has_signal("code_entered"):
			ui.code_entered.connect(_on_ui_code_entered)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


# 1. When the player presses 'E', tell the player to lock onto this screen
func _on_player_interacted(character: CharacterBody3D) -> void:
	if character.has_method("enter_terminal_mode"):
		character.enter_terminal_mode(self)


# 2. The core math isolated into a helper function
func get_viewport_pos_from_3d(global_hit: Vector3) -> Vector2:
	var local_pos := mesh_instance_3d.to_local(global_hit)
	var aabb := mesh_instance_3d.mesh.get_aabb()

	var percent_x := (local_pos.x - aabb.position.x) / aabb.size.x
	var percent_y := (local_pos.z - aabb.position.z) / aabb.size.z
	# percent_y = 1.0 - percent_y # Uncomment if up/down is inverted

	return Vector2(percent_x * sub_viewport.size.x, percent_y * sub_viewport.size.y)


# 3. New functions to receive continuous mouse data from the player
func inject_mouse_motion(global_hit: Vector3) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_viewport_pos_from_3d(global_hit)
	sub_viewport.push_input(event)


func inject_mouse_click(global_hit: Vector3) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = get_viewport_pos_from_3d(global_hit)

	event.pressed = true
	sub_viewport.push_input(event)
	event.pressed = false
	sub_viewport.push_input(event)


func _on_ui_code_entered(code: int) -> void:
	if code == validCode:
		code_accepted.emit()
		_trigger_targets()
		print("The code is correct!")
	else:
		# Optional: Emit a signal or play a sound for a wrong code
		print("Invalid code entered.")


func _trigger_targets() -> void:
	for target in targets:
		if target == null:
			continue

		# 1. SMART POWER SENDER (Matches your Ground Button!)
		if target.has_method("add_power"):
			target.add_power()
		else:
			var comp := target.get_node_or_null("PowerComponent")
			if comp and comp.has_method("add_power"):
				comp.add_power()

			# 2. FALLBACK for non-powered doors
			# If the target doesn't have a PowerComponent, but HAS an 'open' variable, set it to true
			elif "open" in target:
				target.open = true


# --- DEBUG LINE LOGIC ---
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
		mat.albedo_color = Color.DEEP_SKY_BLUE  # Portal button line color!
		debug_line.material_override = mat

	var mesh := debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for target in targets:
		if target != null and is_instance_valid(target):
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(to_local(target.global_position))

	mesh.surface_end()
