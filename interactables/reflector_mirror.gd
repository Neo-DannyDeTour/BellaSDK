## An interactive mirror object that can be rotated by the player to reflect light/lasers.
##
## Inherits from [AnimatableBody3D]. The player can take control of it to adjust its rotation
## dynamically. It recursively marks its physical
## components into a "mirror" group for raycast detection.
class_name ReflectorMirror
extends AnimatableBody3D

## The speed at which the mirror head rotates when the player inputs left or right actions.
@export var rotation_speed: float = 2.0
## The spatial marker defining the exact point and direction of the light reflection.
@export var reflect_marker: Marker3D

## Tracks whether the player is currently actively controlling the mirror's rotation.
var is_controlled: bool = false
## Stores a reference to the [CharacterBody3D] player node currently interacting with the mirror.
var controlling_player: CharacterBody3D = null
## A one-frame flag to prevent immediately detaching from the mirror right after attaching.
var _just_attached: bool = false

## The parent node of the physical mirror mesh that rotates during interaction.
@onready var mirror_head: Node3D = $MirrorHead
## The component responsible for handling player interaction ranges and signals.
@onready var interact_comp: Node = $InteractComponent


## Initializes the mirror, adds it to the appropriate group, and connects interaction signals.
func _ready() -> void:
	add_to_group("mirror")
	_mark_children_as_mirrors(self)

	if interact_comp:
		interact_comp.interacted.connect(_on_interacted)


## Processes rotation input and detachment logic every physics frame if currently controlled.
## [param delta]: The time elapsed since the last physics frame.
func _physics_process(delta: float) -> void:
	if is_controlled:
		_handle_rotation_input(delta)
		_check_auto_release()

		# Skip checking detachment on the exact frame we attached
		if _just_attached:
			_just_attached = false
		else:
			_handle_detachment_input()


## Returns the [Marker3D] node used to calculate reflection trajectories.
func get_reflect_marker() -> Marker3D:
	return reflect_marker


## Reads player input axes and applies horizontal rotation to [member mirror_head].
## [param delta]: The physics frame delta used for framerate-independent rotation.
func _handle_rotation_input(delta: float) -> void:
	var turn_input: float = GestureInputManager.get_axis("left", "right")

	if turn_input != 0.0:
		print("ReflectorMirror: Player rotating mirror head.")
		mirror_head.rotate_y(-turn_input * rotation_speed * delta)


## Verifies the distance to [member controlling_player] and releases control if too far.
func _check_auto_release() -> void:
	if controlling_player == null:
		return

	var dist_squared: float = global_position.distance_squared_to(controlling_player.global_position)
	if dist_squared > 9.0:
		print("ReflectorMirror: Player walked too far away. Auto-releasing.")
		_release_control()


## Triggered when the interaction component emits a signal. Toggles control states.
## [param character]: The [CharacterBody3D] interacting with the mirror.
func _on_interacted(character: CharacterBody3D) -> void:
	print("ReflectorMirror: Player triggered interaction.")
	if not is_controlled:
		_take_control(character)
	else:
		_release_control()


## Assigns the player as the controller and locks their machine state if applicable.
## [param character]: The [CharacterBody3D] taking control.
func _take_control(character: CharacterBody3D) -> void:
	print("ReflectorMirror: Player took control of the mirror.")
	is_controlled = true
	_just_attached = true
	controlling_player = character

	if controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(true)


## Frees the player from mirror control and unlocks their machine state.
func _release_control() -> void:
	print("ReflectorMirror: Player released control of the mirror.")
	is_controlled = false

	if controlling_player and controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(false)

	controlling_player = null


## Recursively assigns the "mirror" group to this node and all valid physical children.
## [param node]: The root [Node] to iterate through.
func _mark_children_as_mirrors(node: Node) -> void:
	for child: Node in node.get_children():
		if child is PhysicsBody3D:
			child.add_to_group("mirror")
		_mark_children_as_mirrors(child)


## Listens for exit actions (interact, jump, crouch) to trigger a control release.
func _handle_detachment_input() -> void:
	if (
		GestureInputManager.is_action_just_pressed("interact")
		or GestureInputManager.is_action_just_pressed("jump")
		or GestureInputManager.is_action_just_pressed("crouch")
	):
		print("ReflectorMirror: Player requested detachment.")
		_release_control()
