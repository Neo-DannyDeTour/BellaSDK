extends Node3D
class_name MeatCubeInteractor

## The visual node (like a SoftBody3D or MeshInstance3D) whose geometry we are monitoring.
## We check the bounding box of this node to see if it has squished or collapsed.
@export var meat_visual: VisualInstance3D

## The string path to the meat cube scene file.
## Using a string path instead of a PackedScene prevents the circular reference error.
@export_file("*.tscn") var meat_cube_scene_path: String

## The percentage of the original height the cube must reach to be considered "collapsed".
## Keeps the physics check lightweight and simple for 60 FPS.
@export var collapse_threshold: float = 0.7

## Tracks if the cube is currently in a collapsed and resetting state.
## Prevents multiple reset timers from spawning simultaneously.
var _is_resetting: bool = false

## Stores the original global height of the bounding box at spawn.
## Used as the baseline to compare against the current height every physics frame.
var _initial_height: float = 0.0

## Accumulates delta time to print debug information periodically.
## Prevents the console from being flooded with print statements every single frame.
var _debug_timer: float = 0.0


func _ready() -> void:
	print("Meat cube interactor initialized. Waiting to record initial geometry...")
	call_deferred("_record_initial_height")


func _record_initial_height() -> void:
	print("Attempting to record initial meat cube height...")
	if meat_visual:
		# In Godot 4, multiply global transform by the local AABB to get the global bounds
		var global_aabb: AABB = meat_visual.global_transform * meat_visual.get_aabb()
		_initial_height = global_aabb.size.y
		print("Recorded initial global meat cube height as: ", _initial_height)
	else:
		print("WARNING: No meat_visual assigned! Autonomous collapse detection will not work.")


func _physics_process(delta: float) -> void:
	if _is_resetting or meat_visual == null or _initial_height <= 0.0:
		return
		
	# Continuously calculate the global AABB as the soft body deforms
	var global_aabb: AABB = meat_visual.global_transform * meat_visual.get_aabb()
	var current_height: float = global_aabb.size.y
	
	_debug_timer += delta
	if _debug_timer >= 1.0:
		print("Checking geometry - Current height: ", current_height, " | Target to collapse: ", (_initial_height * collapse_threshold))
		_debug_timer = 0.0
		
	if current_height < (_initial_height * collapse_threshold):
		print("Autonomous detection: Cube geometry collapsed! Current height: ", current_height)
		trigger_1_second_reset()


## Call this function when the cube takes heavy physics impacts or collapses under its own weight.
func trigger_1_second_reset() -> void:
	print("Meat cube structural integrity compromised. Initiating 1-second reset timer.")
	if _is_resetting:
		return
		
	_is_resetting = true
	
	var timer: SceneTreeTimer = get_tree().create_timer(1.0)
	timer.timeout.connect(_respawn_cube)


func _respawn_cube() -> void:
	print("Respawning a fresh meat cube to restore initial form.")
	
	if meat_cube_scene_path != "":
		var meat_cube_scene: PackedScene = load(meat_cube_scene_path) as PackedScene
		if meat_cube_scene:
			var fresh_cube: Node3D = meat_cube_scene.instantiate() as Node3D
			get_parent().add_child(fresh_cube)
			fresh_cube.global_transform = global_transform
			queue_free()
	else:
		print("Error: meat_cube_scene_path is empty. Assign it in the Inspector.")
