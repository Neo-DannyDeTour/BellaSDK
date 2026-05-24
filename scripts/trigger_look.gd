class_name TriggerLook
extends Area3D

@export_group("Trigger Settings")
## The object the player needs to look at (e.g., your Marker3D)
@export var look_target: Node3D
## How long the player must look at the target (in seconds)
@export var required_look_time: float = 2.0
## How exact the look needs to be. 1.0 is dead center, 0.95 gives a nice, forgiving cone.
@export_range(0.0, 1.0) var look_tolerance: float = 0.95
## If true, the trigger can only be fired once.
@export var fire_once: bool = true

@export_group("Action Settings")
## Array of nodes to power on. Can be the PowerComponent itself or the Parent node.
@export var targets: Array[Node]

var _player_inside: bool = false
var _current_look_time: float = 0.0
var _has_triggered: bool = false
var _camera: Camera3D


func _ready() -> void:
	# Wire up the Area3D signals automatically
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if not _player_inside or _has_triggered or not is_instance_valid(look_target):
		return

	if not _camera:
		_camera = get_viewport().get_camera_3d()
		if not _camera:
			return

	var dir_to_target := _camera.global_position.direction_to(look_target.global_position)
	var camera_forward := -_camera.global_transform.basis.z
	var dot_product := camera_forward.dot(dir_to_target)

	if dot_product >= look_tolerance:
		_current_look_time += delta

		if _current_look_time >= required_look_time:
			_trigger_event()
	else:
		_current_look_time = 0.0


func _trigger_event() -> void:
	if fire_once:
		_has_triggered = true

	print("Trigger Look completed!")

	# --- SMART POWER SENDER ---
	for target in targets:
		if target == null:
			continue

		# 1. Did they target the component directly?
		if target.has_method("add_power"):
			target.add_power()
		# 2. Did they target the parent node? Look for the component!
		else:
			var comp := target.get_node_or_null("PowerComponent")
			if comp and comp.has_method("add_power"):
				comp.add_power()


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = true


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_inside = false
		_current_look_time = 0.0
