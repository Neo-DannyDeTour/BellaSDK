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

@export_category("Audio Settings")
@export var attach_sound: AudioStream
@export var slide_sound: AudioStream
@export var detach_sound: AudioStream

var attached_player: CharacterBody3D = null
var attach_timer: float = 0.0
var locked_x: float = 0.0
var locked_z: float = 0.0

# Track whether the player is currently going up or down
var is_descending: bool = false
var interact_key_name: String = "E"
var interaction_cooldown: float = 0.0

@onready var one_shot_audio: AudioStreamPlayer3D = $OneShotAudio
@onready var loop_audio: AudioStreamPlayer3D = $LoopAudio
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

	# Cache the interact key string once at startup
	if interact_label:
		interact_label.hide()
		var events := InputMap.action_get_events("interact")
		if events.size() > 0:
			var raw_text := events[0].as_text()
			interact_key_name = raw_text.split(" ")[0]

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
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			var mid_point: float = global_position.y + (rope_length / 2.0)
			if cam.global_position.y > mid_point:
				interact_label.text = "[" + interact_key_name + "] GO DOWN"
			else:
				interact_label.text = "[" + interact_key_name + "] GO UP"
		interact_label.show()


func _on_unfocused() -> void:
	if interact_label:
		interact_label.hide()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Decrement cooldown universally
	if interaction_cooldown > 0.0:
		interaction_cooldown -= delta

	# --- 1. MOVEMENT LOGIC ---
	if attached_player:
		attach_timer += delta

		# Keep the sliding sound locked exactly to the player's position
		if is_instance_valid(loop_audio) and loop_audio.playing:
			loop_audio.global_position = attached_player.global_position

		if attach_timer > 0.15 and Input.is_action_just_pressed("interact"):
			detach(false)
			return

		attached_player.velocity = Vector3.ZERO
		attached_player.global_position.x = locked_x
		attached_player.global_position.z = locked_z

		if is_descending:
			attached_player.global_position.y -= ascend_speed * delta
			if attached_player.global_position.y <= global_position.y:
				detach(false)
		else:
			attached_player.global_position.y += ascend_speed * delta
			if attached_player.global_position.y >= top_marker.global_position.y:
				detach(true)

	# --- 2. DYNAMIC UI POSITIONING ---
	elif interact_comp and interact_comp.is_currently_focused and interact_label.visible:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			var hit_point: Vector3 = interact_comp.last_hit_position
			var cam_up: Vector3 = cam.global_transform.basis.y
			var final_pos: Vector3 = hit_point - (cam_up * label_offset_amount)
			interact_label.global_position = final_pos


func _on_interacted(character: CharacterBody3D) -> void:
	print("FastRope: _on_interacted() called. Initiating attach sequence.")
	# Check cooldown before allowing attachment
	if not attached_player and interaction_cooldown <= 0.0:
		attach(character)


func attach(player: CharacterBody3D) -> void:
	attached_player = player
	attach_timer = 0.0

	var mid_point: float = global_position.y + (rope_length / 2.0)
	is_descending = player.global_position.y > mid_point

	# --- CALCULATE PERIMETER POSITION ---
	var offset_dir := attached_player.global_position - global_position
	offset_dir.y = 0.0

	if offset_dir.length_squared() < 0.001:
		offset_dir = Vector3.FORWARD
	else:
		offset_dir = offset_dir.normalized()

	locked_x = global_position.x + (offset_dir.x * climb_radius)
	locked_z = global_position.z + (offset_dir.z * climb_radius)
	# ------------------------------------

	# 1. Break the floor contact immediately so is_on_floor() becomes false
	if not is_descending:
		attached_player.global_position.y += 0.15

	# 2. Instantly disable the StairController to prevent 1-frame execution lag
	var stair_ctrl: Node = attached_player.find_child("StairController", true, false)
	if is_instance_valid(stair_ctrl):
		stair_ctrl.is_enabled = false

	attached_player.add_collision_exception_with(self)

	if interact_label:
		interact_label.hide()
	if highlight_comp:
		highlight_comp.suppress(true)

	if attached_player.has_method("enter_fast_rope"):
		attached_player.enter_fast_rope()

	if attached_player.has_method("enter_fast_rope"):
		attached_player.enter_fast_rope()

	print("FastRope executing: Player attached, triggering attach and slide audio.")

	if is_instance_valid(one_shot_audio) and attach_sound:
		one_shot_audio.stream = attach_sound
		one_shot_audio.global_position = attached_player.global_position
		one_shot_audio.play()

	if is_instance_valid(loop_audio) and slide_sound:
		loop_audio.stream = slide_sound
		loop_audio.global_position = attached_player.global_position
		loop_audio.play()


func detach(reached_top: bool) -> void:
	if not attached_player:
		return

	interaction_cooldown = 0.5

	# Re-enable the StairController instantly
	var stair_ctrl: Node = attached_player.find_child("StairController", true, false)
	if is_instance_valid(stair_ctrl):
		stair_ctrl.is_enabled = true

	attached_player.remove_collision_exception_with(self)

	if highlight_comp:
		highlight_comp.suppress(false)

	if attached_player.has_method("exit_fast_rope"):
		attached_player.exit_fast_rope()

	if reached_top:
		attached_player.velocity.y = launch_velocity
	else:
		attached_player.velocity.y = 0.0

	print("FastRope executing: Player detached, stopping loop and triggering detach audio.")

	if is_instance_valid(loop_audio):
		loop_audio.stop()

	if is_instance_valid(one_shot_audio) and detach_sound:
		# Cache the position before nullifying the attached_player reference
		var cached_pos: Vector3 = attached_player.global_position
		one_shot_audio.stream = detach_sound
		one_shot_audio.global_position = cached_pos
		one_shot_audio.play()

	attached_player = null
