## Monitors a soft body physics cube and autonomously resets it if structural collapse is detected.
##
## Tracks the global axis-aligned bounding box (AABB) of the assigned visual mesh. If the vertical
## height falls below the defined threshold, the script assumes the cube was crushed and replaces
## it with a freshly instantiated packed scene.
class_name MeatCubeInteractor
extends Node3D

## The visual node (like a SoftBody3D or MeshInstance3D) whose geometry we are monitoring.
@export var meat_visual: VisualInstance3D

## The string path to the scene. Bypassing a [PackedScene] prevents circular reference errors.
@export_file("*.tscn") var meat_cube_scene_path: String

## The percentage of the original height the cube must reach to be considered "collapsed".
@export var collapse_threshold: float = 0.7

## Tracks if the cube is currently in a collapsed and resetting state.
var _is_resetting: bool = false
## Stores the original global height of the bounding box at spawn.
var _initial_height: float = 0.0
## Accumulates delta time to print debug information periodically instead of every frame.
var _debug_timer: float = 0.0


## Defers the initialization of the baseline geometry height until physics are settled.
func _ready() -> void:
	print("Meat cube interactor initialized. Waiting to record initial geometry...")
	call_deferred("_record_initial_height")


## Calculates the true global height of the [member meat_visual] bounds.
func _record_initial_height() -> void:
	print("Attempting to record initial meat cube height...")
	if is_instance_valid(meat_visual):
		# In Godot 4, multiply global transform by the local AABB to get the global bounds
		var global_aabb: AABB = meat_visual.global_transform * meat_visual.get_aabb()
		_initial_height = global_aabb.size.y
		print("Recorded initial global meat cube height as: ", _initial_height)
	else:
		print("WARNING: No meat_visual assigned! Autonomous collapse detection will not work.")


## Calculates the global AABB as the soft body deforms to check for collapse conditions.
## [param delta]: Frame delta time.
func _physics_process(delta: float) -> void:
	if _is_resetting or not is_instance_valid(meat_visual) or _initial_height <= 0.0:
		return

	# Continuously calculate the global AABB as the soft body deforms
	var global_aabb: AABB = meat_visual.global_transform * meat_visual.get_aabb()
	var current_height: float = global_aabb.size.y

	_debug_timer += delta
	if _debug_timer >= 1.0:
		print(
			"Checking geometry - Current height: ",
			current_height,
			" | Target to collapse: ",
			_initial_height * collapse_threshold
		)
		_debug_timer = 0.0

	if current_height < (_initial_height * collapse_threshold):
		print("Autonomous detection: Cube geometry collapsed! Current height: ", current_height)
		trigger_1_second_reset()


## Locks the logic loop and queues a fresh respawn after a short delay.
func trigger_1_second_reset() -> void:
	print("Meat cube structural integrity compromised. Initiating 1-second reset timer.")
	if _is_resetting:
		return

	_is_resetting = true

	var timer: SceneTreeTimer = get_tree().create_timer(1.0)
	timer.timeout.connect(_respawn_cube)


## Instantiates the [member meat_cube_scene_path] and deletes this instance.
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
