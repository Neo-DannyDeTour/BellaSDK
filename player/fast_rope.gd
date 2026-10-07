@tool
## Interactive fast rope providing mechanics to grab on, rapidly slide, and vault off.
class_name FastRope
extends StaticBody3D

## Global registry tracking all active fast rope instances in the loaded scene tree.
static var all_fast_ropes: Array[FastRope] = []

@export_category("Fast Rope Settings")
## Total vertical height and collision span of the rope in meters.
@export var rope_length: float = 10.0:
	set(value):
		rope_length = value
		if is_inside_tree():
			_update_rope_size()

## Vertical movement velocity in meters per second while traversing the rope.
@export var ascend_speed: float = 15.0

## Vertical launch velocity applied when vaulting off the top of the rope.
@export var launch_velocity: float = 7.7

## Vertical distance offset beneath crosshair for floating interaction prompts.
@export var label_offset_amount: float = 0.35

## Horizontal radial offset distance from rope center maintained during climbing.
@export var climb_radius: float = 0.6

@export_category("Audio Settings")
## One-shot sound effect played when the player latches onto the rope.
@export var attach_sound: AudioStream

## Looping audio stream played continuously while traversing along the rope.
@export var slide_sound: AudioStream

## One-shot sound effect played when detaching or launching from the rope.
@export var detach_sound: AudioStream

## Reference to the player character currently attached to this rope.
var attached_player: CharacterBody3D = null

## Elapsed time in seconds since the player latched onto the rope.
var attach_timer: float = 0.0

## Cached active viewport camera instance to avoid frequent queries.
var _cached_camera: Camera3D = null

## Cached world-space X coordinate locked to during rope climb motion.
var locked_x: float = 0.0

## Cached world-space Z coordinate locked to during rope climb motion.
var locked_z: float = 0.0

## Indicates whether player traversal direction is downward toward the base.
var is_descending: bool = false

## Display name of the action key mapped to rope interaction.
var interact_key_name: String = "E"

## Cooldown duration in seconds preventing instant re-attachment upon release.
var interaction_cooldown: float = 0.0

## Spatial audio player for instantaneous attach and detach sound effects.
@onready var one_shot_audio: AudioStreamPlayer3D = $OneShotAudio

## Spatial audio player looping continuous sliding sound effects.
@onready var loop_audio: AudioStreamPlayer3D = $LoopAudio

## Collision shape bounding the physical interactable span of the rope.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

## Spatial marker denoting the top dismount boundary of the rope.
@onready var top_marker: Marker3D = $TopMarker

## Interaction raycast component managing focus and activation events.
@onready var interact_comp: InteractComponent = $InteractComponent

## Component outlining the rope mesh when focused by the player crosshair.
@onready var highlight_comp: HighlightComponent = $HighlightComponent

## Floating 3D label presenting dynamic interact text prompts.
@onready var interact_label: Label3D = $Label3D

## Visual mesh instance representing the cylindrical rope body.
@onready var rope_mesh: MeshInstance3D = $MeshInstance3D


## Registers this rope into the static global registry when entering the tree.
func _enter_tree() -> void:
	if not self in all_fast_ropes:
		all_fast_ropes.append(self)


## Removes this rope from the static global registry when exiting the tree.
func _exit_tree() -> void:
	all_fast_ropes.erase(self)


## Validates dimensions, configures keybindings, and connects signals.
func _ready() -> void:
	_update_rope_size()

	if Engine.is_editor_hint():
		return

	if is_instance_valid(interact_label):
		interact_label.hide()
		var events: Array[InputEvent] = InputMap.action_get_events("interact")
		if not events.is_empty():
			var raw_text: String = events[0].as_text()
			interact_key_name = raw_text.split(" ")[0]

	if is_instance_valid(interact_comp):
		if not interact_comp.interacted.is_connected(_on_interacted):
			interact_comp.interacted.connect(_on_interacted)
		if not interact_comp.focused.is_connected(_on_focused):
			interact_comp.focused.connect(_on_focused)
		if not interact_comp.unfocused.is_connected(_on_unfocused):
			interact_comp.unfocused.connect(_on_unfocused)


## Dynamically adjusts collision boundaries and mesh dimensions to match length.
func _update_rope_size() -> void:
	if is_instance_valid(collision_shape) and collision_shape.shape != null:
		if collision_shape.shape is BoxShape3D:
			var box: BoxShape3D = (
				collision_shape.shape if collision_shape.shape is BoxShape3D else null
			)
			box.size.y = rope_length
		elif collision_shape.shape is CylinderShape3D:
			var cyl: CylinderShape3D = (
				collision_shape.shape if collision_shape.shape is CylinderShape3D else null
			)
			cyl.height = rope_length
		collision_shape.position.y = rope_length / 2.0

	if is_instance_valid(rope_mesh) and rope_mesh.mesh != null:
		if rope_mesh.mesh is BoxMesh:
			var box_m: BoxMesh = rope_mesh.mesh if rope_mesh.mesh is BoxMesh else null
			box_m.size.y = rope_length
		elif rope_mesh.mesh is CylinderMesh:
			var cyl_m: CylinderMesh = rope_mesh.mesh if rope_mesh.mesh is CylinderMesh else null
			cyl_m.height = rope_length
		rope_mesh.position.y = rope_length / 2.0

	if is_instance_valid(top_marker):
		top_marker.position.y = rope_length


## Displays context-sensitive direction prompt when the player targets the rope.
func _on_focused() -> void:
	if not is_instance_valid(attached_player) and is_instance_valid(interact_label):
		var cam: Camera3D = _get_camera()
		if is_instance_valid(cam):
			var mid_point: float = global_position.y + (rope_length / 2.0)
			if cam.global_position.y > mid_point:
				interact_label.text = "[" + interact_key_name + "] GO DOWN"
			else:
				interact_label.text = "[" + interact_key_name + "] GO UP"
		interact_label.show()


## Hides floating interaction prompt when player crosshair turns away.
func _on_unfocused() -> void:
	if is_instance_valid(interact_label):
		interact_label.hide()


## Processes player ascent/descent, audio tracking, or repositions target label.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if interaction_cooldown > 0.0:
		interaction_cooldown -= delta

	if is_instance_valid(attached_player):
		attach_timer += delta

		if is_instance_valid(loop_audio) and loop_audio.playing:
			loop_audio.global_position = attached_player.global_position

		if attach_timer > 0.15 and GestureInputManager.is_action_just_pressed("interact"):
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
			if is_instance_valid(top_marker):
				if attached_player.global_position.y >= top_marker.global_position.y:
					detach(true)

	elif (
		is_instance_valid(interact_comp)
		and interact_comp.is_currently_focused
		and is_instance_valid(interact_label)
		and interact_label.visible
	):
		var cam: Camera3D = _get_camera()
		if is_instance_valid(cam):
			var hit_point: Vector3 = interact_comp.last_hit_position
			var cam_up: Vector3 = cam.global_transform.basis.y
			var final_pos: Vector3 = hit_point - (cam_up * label_offset_amount)
			interact_label.global_position = final_pos


## Receives interaction event and attaches player if vacant and cooled down.
func _on_interacted(character: CharacterBody3D) -> void:
	print("FastRope: _on_interacted() called. Initiating attach sequence.")
	if not is_instance_valid(attached_player) and interaction_cooldown <= 0.0:
		attach(character)


## Locks player to radial position, halts gravity, and starts slide sounds.
func attach(player: CharacterBody3D) -> void:
	print("FastRope: attach() called. Locking player to rope trajectory.")
	attached_player = player
	attach_timer = 0.0

	var mid_point: float = global_position.y + (rope_length / 2.0)
	is_descending = player.global_position.y > mid_point

	var offset_dir: Vector3 = attached_player.global_position - global_position
	offset_dir.y = 0.0

	if offset_dir.length_squared() < 0.001:
		offset_dir = Vector3.FORWARD
	else:
		offset_dir = offset_dir.normalized()

	locked_x = global_position.x + (offset_dir.x * climb_radius)
	locked_z = global_position.z + (offset_dir.z * climb_radius)

	if not is_descending:
		attached_player.global_position.y += 0.15

	if "stair_controller" in attached_player:
		var raw_ctrl: Variant = attached_player.get("stair_controller")
		var stair_ctrl: Node = raw_ctrl if raw_ctrl is Node else null
		if is_instance_valid(stair_ctrl):
			stair_ctrl.set("is_enabled", false)

	attached_player.add_collision_exception_with(self)

	if is_instance_valid(interact_label):
		interact_label.hide()
	if is_instance_valid(highlight_comp):
		highlight_comp.suppress(true)

	if attached_player.has_method("enter_fast_rope"):
		attached_player.call(&"enter_fast_rope")

	print("FastRope executing: Player attached, triggering attach and slide audio.")

	if is_instance_valid(one_shot_audio) and attach_sound != null:
		one_shot_audio.stream = attach_sound
		one_shot_audio.global_position = attached_player.global_position
		one_shot_audio.play()

	if is_instance_valid(loop_audio) and slide_sound != null:
		loop_audio.stream = slide_sound
		loop_audio.global_position = attached_player.global_position
		loop_audio.play()


## Detaches player from rope, applies optional launch impulse, and resets audio.
func detach(reached_top: bool) -> void:
	print("FastRope: detach() called. Releasing player.")
	if not is_instance_valid(attached_player):
		return

	interaction_cooldown = 0.5

	if "stair_controller" in attached_player:
		var raw_ctrl: Variant = attached_player.get("stair_controller")
		var stair_ctrl: Node = raw_ctrl if raw_ctrl is Node else null
		if is_instance_valid(stair_ctrl):
			stair_ctrl.set("is_enabled", true)

	attached_player.remove_collision_exception_with(self)

	if is_instance_valid(highlight_comp):
		highlight_comp.suppress(false)

	if attached_player.has_method("exit_fast_rope"):
		attached_player.call(&"exit_fast_rope")

	if reached_top:
		attached_player.velocity.y = launch_velocity
	else:
		attached_player.velocity.y = 0.0

	print("FastRope executing: Player detached, stopping loop and triggering detach audio.")

	if is_instance_valid(loop_audio):
		loop_audio.stop()

	if is_instance_valid(one_shot_audio) and detach_sound != null:
		var cached_pos: Vector3 = attached_player.global_position
		one_shot_audio.stream = detach_sound
		one_shot_audio.global_position = cached_pos
		one_shot_audio.play()

	attached_player = null


## Retrieves and caches the active 3D camera from the main viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() != null else null
	return _cached_camera
