@tool
class_name FastRope
extends StaticBody3D

# Keep track of all ropes globally using a Godot 4 static variable
static var all_fast_ropes: Array[FastRope] = []

@export_category("Fast Rope Settings")

## CHANGE THIS to make the rope longer/shorter without using Transform Scale!
@export var rope_length: float = 10.0:
	set(value):
		rope_length = value
		if is_node_ready():
			_update_rope_size()

@export var ascend_speed: float = 15.0
@export var launch_velocity: float = 7.7
## How far down from the crosshair the text appears
@export var label_offset_amount: float = 0.35
@export var climb_radius: float = 0.6

var attached_player: CharacterBody3D = null
var attach_timer: float = 0.0

var locked_x: float = 0.0
var locked_z: float = 0.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var top_marker: Marker3D = $TopMarker
@onready var interact_comp: Interact_Component = $Interact_Component
@onready var highlight_comp: HighlightComponent = $HighlightComponent
@onready var interact_label: Label3D = $Label3D
@onready var rope_mesh: MeshInstance3D = $MeshInstance3D


func _enter_tree() -> void:
	if not self in all_fast_ropes:
		all_fast_ropes.append(self)


func _exit_tree() -> void:
	all_fast_ropes.erase(self)


func _ready() -> void:
	_update_rope_size()

	if Engine.is_editor_hint():
		return

	# --- UI SETUP ---
	if interact_label:
		interact_label.hide()
		var events := InputMap.action_get_events("interact")
		if events.size() > 0:
			var raw_text := events[0].as_text()
			var key_name := raw_text.split(" ")[0]
			interact_label.text = "[" + key_name + "] GO UP"

	# --- SIGNAL CONNECTIONS ---
	if interact_comp:
		if not interact_comp.interacted.is_connected(_on_interacted):
			interact_comp.interacted.connect(_on_interacted)
		if not interact_comp.focused.is_connected(_on_focused):
			interact_comp.focused.connect(_on_focused)
		if not interact_comp.unfocused.is_connected(_on_unfocused):
			interact_comp.unfocused.connect(_on_unfocused)


func _update_rope_size() -> void:
	if collision_shape and collision_shape.shape:
		if collision_shape.shape is BoxShape3D:
			collision_shape.shape.size.y = rope_length
		elif collision_shape.shape is CylinderShape3D:
			collision_shape.shape.height = rope_length
		collision_shape.position.y = rope_length / 2.0

	if rope_mesh and rope_mesh.mesh:
		if rope_mesh.mesh is BoxMesh:
			rope_mesh.mesh.size.y = rope_length
		elif rope_mesh.mesh is CylinderMesh:
			rope_mesh.mesh.height = rope_length
		rope_mesh.position.y = rope_length / 2.0

	if top_marker:
		top_marker.position.y = rope_length


func _on_focused() -> void:
	if not attached_player and interact_label:
		interact_label.show()


func _on_unfocused() -> void:
	if interact_label:
		interact_label.hide()


func _on_interacted(character: CharacterBody3D) -> void:
	if not attached_player:
		attach(character)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# --- 1. MOVEMENT LOGIC ---
	if attached_player:
		attach_timer += delta

		# THIS is the only detach check you need!
		if attach_timer > 0.15 and Input.is_action_just_pressed("interact"):
			detach(false)

		attached_player.velocity = Vector3.ZERO

		# Lock X and Z to the outside radius of the rope
		attached_player.global_position.x = locked_x
		attached_player.global_position.z = locked_z

		# Move Up linearly
		attached_player.global_position.y += ascend_speed * delta

		if attached_player.global_position.y >= top_marker.global_position.y:
			detach(true)

	# --- 2. DYNAMIC UI POSITIONING ---
	elif interact_comp and interact_comp.is_currently_focused and interact_label.visible:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			var hit_point: Vector3 = interact_comp.last_hit_position
			var cam_up: Vector3 = cam.global_transform.basis.y

			# Subtracting cam_up puts the label perfectly Center Down from the hit point
			var final_pos: Vector3 = hit_point - (cam_up * label_offset_amount)
			interact_label.global_position = final_pos


func attach(player: CharacterBody3D) -> void:
	attached_player = player
	attach_timer = 0.0

	# --- CALCULATE PERIMETER POSITION ---
	var offset_dir := attached_player.global_position - global_position
	offset_dir.y = 0.0  # Ignore vertical height for this math

	if offset_dir.length_squared() < 0.001:
		offset_dir = Vector3.FORWARD  # Failsafe if they are somehow dead center
	else:
		offset_dir = offset_dir.normalized()

	# Lock the X and Z coordinates to the edge of the climb radius
	locked_x = global_position.x + (offset_dir.x * climb_radius)
	locked_z = global_position.z + (offset_dir.z * climb_radius)
	# ------------------------------------

	attached_player.add_collision_exception_with(self)

	if interact_label:
		interact_label.hide()
	if highlight_comp:
		highlight_comp.suppress(true)

	if attached_player.has_method("enter_fast_rope"):
		attached_player.enter_fast_rope()


func detach(reached_top: bool) -> void:
	if not attached_player:
		return

	attached_player.remove_collision_exception_with(self)

	if highlight_comp:
		highlight_comp.suppress(false)

	# Tell the player they are free BEFORE giving them the boost
	if attached_player.has_method("exit_fast_rope"):
		attached_player.exit_fast_rope()

	if reached_top:
		attached_player.velocity.y = launch_velocity
	else:
		attached_player.velocity.y = 0

	attached_player = null
