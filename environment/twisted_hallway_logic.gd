extends Node3D
class_name TwistedHallway

## The node that groups the visual meshes (floor, walls, ceiling).
## Rotates along the local Z-axis to create the twisting optical illusion.
@export var visual_pivot: Node3D

## The trigger volume at the start of the hallway.
## Activates the tracking logic when the player enters from the beginning.
@export var entry_trigger: Area3D

## The trigger volume at the end of the hallway.
## Activates the tracking logic when the player enters from the far end.
@export var exit_trigger: Area3D

## The maximum rotation applied to the visual pivot in degrees.
## Determines how far the hallway twists by the end of the 10 meter length.
@export var max_twist_degrees: float = -90.0

## The target player node currently inside the hallway.
## Used to retrieve the global position and calculate the required twist.
var _player_node: Node3D = null


func _ready() -> void:
	print("TwistedHallway: Ready. Connecting triggers.")
	entry_trigger.body_entered.connect(_on_trigger_entered)
	exit_trigger.body_entered.connect(_on_trigger_entered)


func _physics_process(_delta: float) -> void:
	if _player_node != null:
		_process_hallway_twist()


func _on_trigger_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		print("TwistedHallway: Player entered a trigger. Tracking activated.")
		_player_node = body


func _process_hallway_twist() -> void:
	var local_pos: Vector3 = to_local(_player_node.global_position)
	
	# This will tell us what the math is actually seeing
	print("DEBUG: Player local Z position is: ", local_pos.z) 
	
	var progress: float = clampf(local_pos.z / -10.0, 0.0, 1.0)
	visual_pivot.rotation.z = deg_to_rad(max_twist_degrees) * progress
	
	if local_pos.z > 2.0 or local_pos.z < -12.0:
		print("TwistedHallway: Player exited extended bounds. Deactivating.")
		_player_node = null
