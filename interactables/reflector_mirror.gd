## Interactive mirror stand rotated by player to redirect laser beams.
class_name ReflectorMirror
extends AnimatableBody3D

## Cooldown duration in seconds before player detachment is permitted.
const DETACH_COOLDOWN_SEC: float = 0.35

## Cooldown duration in seconds preventing immediate re-attachment.
const REATTACH_COOLDOWN_SEC: float = 0.4

## Duration in seconds of smooth stance transition tween when taking control.
const ALIGN_TWEEN_DURATION_SEC: float = 0.3

## Angular rotation speed of mirror head in radians per second.
@export var rotation_speed: float = 2.0

## Mouse sensitivity factor for yaw rotation during player control.
@export var mouse_sensitivity: float = 0.003

## Spatial marker defining the point and normal direction of laser reflection.
@export var reflect_marker: Marker3D

## Tracks whether player currently actively operates the mirror stand.
var is_controlled: bool = false

## Reference to [CharacterBody3D] player operating the mirror stand.
var controlling_player: CharacterBody3D = null

## Active tween smoothly aligning player to stance marker position.
var _stance_tween: Tween = null

## Indicates whether player is actively tweening into operating stance.
var _is_aligning: bool = false

## Elapsed seconds since control was acquired to prevent instant detach.
var _control_timer: float = 0.0

## Timer preventing immediate re-attachment right after detaching.
var _reattach_cooldown_timer: float = 0.0

## Accumulated horizontal mouse input angle applied on next physics tick.
var _pending_mouse_rotation: float = 0.0

## Pivot node of physical mirror mesh that rotates during interaction.
@onready var mirror_head: AnimatableBody3D = get_node_or_null("MirrorHead") as AnimatableBody3D

## Stance marker designating where player stands during interaction.
@onready var stance_marker: Marker3D = (
	(
		get_node_or_null("MirrorHead/StanceMarker") as Marker3D
		if has_node("MirrorHead/StanceMarker")
		else get_node_or_null("StanceMarker")
	)
	as Marker3D
)

## Interaction component managing player focus and interaction events.
@onready
var interact_comp: InteractComponent = get_node_or_null("InteractComponent") as InteractComponent


## Initializes mirror group memberships and binds interaction events.
func _ready() -> void:
	print("ReflectorMirror: Initializing mirror stand and groups.")
	add_to_group(&"mirror")
	_mark_children_as_mirrors(self)

	if is_instance_valid(interact_comp):
		if interact_comp.has_signal(&"interacted"):
			interact_comp.interacted.connect(_on_interacted)


## Updates rotation, player tracking, and detachment every physics tick.
func _physics_process(delta: float) -> void:
	if _reattach_cooldown_timer > 0.0:
		_reattach_cooldown_timer -= delta

	if is_controlled:
		_control_timer += delta
		_handle_rotation_input(delta)
		_update_controlled_player_transform()
		_check_auto_release()


## Captures input to steer mirror head and handles clean detachment.
func _unhandled_input(event: InputEvent) -> void:
	if not is_controlled:
		return

	if event is InputEventMouseMotion:
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		_pending_mouse_rotation -= mouse_event.relative.x * mouse_sensitivity
		return

	if _control_timer >= DETACH_COOLDOWN_SEC:
		if (
			event.is_action_pressed(&"interact")
			or event.is_action_pressed(&"jump")
			or event.is_action_pressed(&"crouch")
			or event.is_action_pressed(&"ui_cancel")
		):
			print("ReflectorMirror: Detachment requested via unhandled input.")
			_release_control()
			get_viewport().set_input_as_handled()


## Returns outgoing reflection normal facing [member reflect_marker] forward.
func get_reflection_normal(hit_normal: Vector3) -> Vector3:
	var forward: Vector3 = Vector3.FORWARD
	if is_instance_valid(reflect_marker):
		forward = -reflect_marker.global_transform.basis.z.normalized()
	elif is_instance_valid(mirror_head):
		forward = -mirror_head.global_transform.basis.z.normalized()
	else:
		forward = hit_normal

	return forward


## Returns spatial marker designating primary reflection origin.
func get_reflect_marker() -> Marker3D:
	return reflect_marker


## Returns all physics body [RID]s belonging to this reflector stand.
func get_all_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	if is_instance_valid(mirror_head):
		rids.append(mirror_head.get_rid())
	return rids


## Applies keyboard and mouse yaw rotation to [member mirror_head].
func _handle_rotation_input(delta: float) -> void:
	var turn_axis: float = GestureInputManager.get_axis(&"left", &"right")
	if is_zero_approx(turn_axis):
		if InputMap.has_action(&"ui_left") and InputMap.has_action(&"ui_right"):
			turn_axis = Input.get_axis(&"ui_left", &"ui_right")

	var keyboard_rot: float = -turn_axis * rotation_speed * delta
	var total_rot: float = keyboard_rot + _pending_mouse_rotation
	_pending_mouse_rotation = 0.0

	if not is_zero_approx(total_rot):
		print("ReflectorMirror: Rotating mirror head by: ", total_rot)
		if is_instance_valid(mirror_head):
			mirror_head.rotate_y(total_rot)


## Keeps player positioned and oriented facing stand during control.
func _update_controlled_player_transform() -> void:
	if not is_instance_valid(controlling_player):
		return
	if not is_instance_valid(stance_marker):
		return

	if not _is_aligning:
		controlling_player.global_position = stance_marker.global_position

	var center_point: Vector3 = Vector3(
		global_position.x, controlling_player.global_position.y, global_position.z
	)
	if not controlling_player.global_position.is_equal_approx(center_point):
		controlling_player.look_at(center_point, Vector3.UP)


## Releases control if player moves beyond maximum allowed range.
func _check_auto_release() -> void:
	if not is_instance_valid(controlling_player):
		return

	var check_pos: Vector3 = (
		stance_marker.global_position if is_instance_valid(stance_marker) else global_position
	)
	var dist_sq: float = check_pos.distance_squared_to(controlling_player.global_position)
	if dist_sq > 9.0:
		print("ReflectorMirror: Player walked too far away. Auto-releasing.")
		_release_control()


## Dispatches direct interaction call initiated by player character.
func interact_with(character: CharacterBody3D) -> void:
	print("ReflectorMirror: interact_with() called by: ", character.name)
	_on_interacted(character)


## Secondary alias for interaction triggers from external systems.
func interact(character: CharacterBody3D) -> void:
	print("ReflectorMirror: interact() alias called by: ", character.name)
	interact_with(character)


## Toggles mirror control state upon receiving interaction signal.
func _on_interacted(character: CharacterBody3D) -> void:
	print("ReflectorMirror: Interaction triggered by: ", character.name)
	if _reattach_cooldown_timer > 0.0:
		print("ReflectorMirror: Interaction rejected during re-attach cooldown.")
		return

	if not is_controlled:
		_take_control(character)
	elif _control_timer >= DETACH_COOLDOWN_SEC:
		_release_control()


## Binds player, locks physics, and tweens character to stance marker.
func _take_control(character: CharacterBody3D) -> void:
	print("ReflectorMirror: Player took control: ", character.name)
	is_controlled = true
	_control_timer = 0.0
	_pending_mouse_rotation = 0.0
	controlling_player = character

	if controlling_player.has_method(&"set_machine_lock"):
		controlling_player.call(&"set_machine_lock", true)

	if is_instance_valid(_stance_tween):
		_stance_tween.kill()

	if is_instance_valid(stance_marker):
		_is_aligning = true
		_stance_tween = create_tween()
		_stance_tween.set_trans(Tween.TRANS_CUBIC)
		_stance_tween.set_ease(Tween.EASE_OUT)
		_stance_tween.tween_property(
			controlling_player,
			"global_position",
			stance_marker.global_position,
			ALIGN_TWEEN_DURATION_SEC
		)
		_stance_tween.tween_callback(
			func() -> void:
				_is_aligning = false
				print("ReflectorMirror: Player aligned to stance marker.")
		)
	else:
		_is_aligning = false


## Restores player physics state and disengages active mirror control.
func _release_control() -> void:
	print("ReflectorMirror: Player released control of the mirror.")
	is_controlled = false
	_is_aligning = false
	_control_timer = 0.0
	_reattach_cooldown_timer = REATTACH_COOLDOWN_SEC
	_pending_mouse_rotation = 0.0

	if is_instance_valid(_stance_tween):
		_stance_tween.kill()

	if is_instance_valid(controlling_player):
		if controlling_player.has_method(&"set_machine_lock"):
			controlling_player.call(&"set_machine_lock", false)

	controlling_player = null


## Recursively assigns mirror group to all child [PhysicsBody3D] nodes.
func _mark_children_as_mirrors(node: Node) -> void:
	for child: Node in node.get_children():
		if child is PhysicsBody3D:
			print("ReflectorMirror: Marking child as mirror: ", child.name)
			child.add_to_group(&"mirror")
		_mark_children_as_mirrors(child)
