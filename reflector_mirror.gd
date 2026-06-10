class_name ReflectorMirror
extends AnimatableBody3D

@export var rotation_speed: float = 2.0
@export var stance_marker: Marker3D
@export var reflect_marker: Marker3D

@onready var mirror_head: Node3D = $MirrorHead
@onready var interact_comp: Interact_Component = $Interact_Component

var is_controlled: bool = false
var controlling_player: CharacterBody3D = null


func _ready() -> void:
	print("ReflectorMirror: _ready() initialized.")
	add_to_group("mirror")
	_mark_children_as_mirrors(self)
	
	if interact_comp:
		interact_comp.interacted.connect(_on_interacted)


func _physics_process(delta: float) -> void:
	if is_controlled:
		_handle_rotation_input(delta)
		_check_auto_release()


func get_reflect_marker() -> Marker3D:
	return reflect_marker


func _handle_rotation_input(delta: float) -> void:
	var turn_input: float = Input.get_axis("left", "right")
	
	if turn_input != 0.0:
		print("ReflectorMirror: Player rotating mirror head.")
		mirror_head.rotate_y(-turn_input * rotation_speed * delta)


func _check_auto_release() -> void:
	if controlling_player == null:
		return
		
	var dist: float = global_position.distance_to(controlling_player.global_position)
	if dist > 3.0:
		print("ReflectorMirror: Player walked too far away. Auto-releasing.")
		_release_control()


func _on_interacted(character: CharacterBody3D) -> void:
	print("ReflectorMirror: Player triggered interaction.")
	if not is_controlled:
		_take_control(character)
	else:
		_release_control()


func _take_control(character: CharacterBody3D) -> void:
	print("ReflectorMirror: Player took control of the mirror.")
	is_controlled = true
	controlling_player = character
	
	if stance_marker:
		controlling_player.global_transform = stance_marker.global_transform
		controlling_player.velocity = Vector3.ZERO
		
	if controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(true)


func _release_control() -> void:
	print("ReflectorMirror: Player released control of the mirror.")
	is_controlled = false
	
	if controlling_player and controlling_player.has_method("set_machine_lock"):
		controlling_player.set_machine_lock(false)
		
	controlling_player = null


func _mark_children_as_mirrors(node: Node) -> void:
	for child: Node in node.get_children():
		if child is PhysicsBody3D:
			child.add_to_group("mirror")
		_mark_children_as_mirrors(child)
