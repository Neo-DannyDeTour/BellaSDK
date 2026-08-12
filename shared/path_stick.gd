class_name PathStick
extends PathFollow3D

# --------------------------------------
# CONFIGURATION VARIABLES
# (These are now populated automatically by the SlideTrack parent)
# --------------------------------------
## The speed at which the stick moves along the path.
var move_speed: float = 15.0
## The minimum speed required to throw the player at the end of the path.
var throw_speed_threshold: float = 8.0
## The local velocity vector applied to the player when thrown.
var throw_velocity_local: Vector3 = Vector3(0.0, 5.0, -20.0)
## Determines if the player should hang at the end of the path if not thrown.
var stay_at_end: bool = false
## Determines if the stick should instantly reset to the start after use.
var return_immediately: bool = false

# --------------------------------------
# STATE VARIABLES
# --------------------------------------
## Reference to the player currently holding the stick.
var current_player: Player = null
## The current active speed of the stick along the path.
var current_speed: float = 0.0
## Indicates whether the stick is currently in motion.
var is_active: bool = false


# --------------------------------------
# BUILT-IN METHODS
# --------------------------------------
func _ready() -> void:
	loop = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	progress += current_speed * delta

	if progress_ratio >= 1.0:
		print("PathStick: Reached path endpoint.")
		_handle_endpoint()


# --------------------------------------
# INTERACTION & LOGIC
# --------------------------------------
func _on_interact_component_interacted(character: CharacterBody3D) -> void:
	print("PathStick: _on_interact_component_interacted() called. Triggering path stick action.")
	if is_active or not character is Player:
		return

	is_active = true
	current_player = character as Player
	current_speed = move_speed

	if current_player.has_method("enter_path_slide"):
		current_player.enter_path_slide(self)

	set_physics_process(true)


func _handle_endpoint() -> void:
	is_active = false
	set_physics_process(false)

	if not is_instance_valid(current_player):
		_process_return()
		return

	# 1. Throw the player if fast enough
	if current_speed >= throw_speed_threshold:
		var global_throw_dir: Vector3 = global_transform.basis * throw_velocity_local
		current_player.launch_from_path(global_throw_dir)
		_process_return()

	# 2. Handle low speeds
	else:
		if stay_at_end:
			print("PathStick: Speed too low. Holding player at endpoint.")
		else:
			print("PathStick: Speed too low. Dropping player.")
			current_player.exit_path_slide()
			_process_return()


# Called by StatePathSlide when the player jumps off manually
func release_player() -> void:
	current_player = null
	is_active = false
	set_physics_process(false)
	_process_return()


func _process_return() -> void:
	if return_immediately:
		progress_ratio = 0.0
